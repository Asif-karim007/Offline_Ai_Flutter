import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:llama_bindings/llama_bindings.dart';

import '../domain/chat_message.dart';
import '../domain/chat_role.dart';
import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';
import 'chat_engine.dart';
import 'llama_error.dart';
import 'prompt_builder.dart';
import 'token_budget_manager.dart';
import 'utf8_token_buffer.dart';

/// Wire protocol between [LlamaEngine] and the inference isolate.
///
/// Deliberately plain maps rather than sent objects. Dart could send the domain classes
/// directly, but a stable map schema means the worker and the engine can be reasoned about
/// — and versioned — independently of the domain layer.
abstract final class WorkerOp {
  static const String load = 'load';
  static const String unload = 'unload';
  static const String reset = 'reset';
  static const String countTokens = 'countTokens';
  static const String generate = 'generate';
  static const String generateStructured = 'generateStructured';
  static const String status = 'status';
  static const String shutdown = 'shutdown';
}

abstract final class WorkerReply {
  static const String ok = 'ok';
  static const String error = 'error';
  static const String token = 'token';
  static const String finished = 'finished';
  static const String ready = 'ready';
}

/// Everything the isolate needs at spawn time.
class WorkerBootstrap {
  const WorkerBootstrap({
    required this.replyPort,
    required this.cancellationAddress,
  });

  final SendPort replyPort;

  /// Address of the shared cancellation flag. See [CancellationFlag] for why this is a raw
  /// address and not a message.
  final int cancellationAddress;
}

/// Isolate entry point. Never call this directly.
void llamaWorkerEntry(WorkerBootstrap bootstrap) {
  final worker = _LlamaWorker(
    replyPort: bootstrap.replyPort,
    cancellation: CancellationFlag.fromAddress(bootstrap.cancellationAddress),
  );

  final commands = ReceivePort();
  bootstrap.replyPort.send(<String, Object?>{
    'status': WorkerReply.ready,
    'port': commands.sendPort,
  });

  commands.listen((Object? message) async {
    if (message is! Map) return;
    final command = message.cast<String, Object?>();
    if (command['op'] == WorkerOp.shutdown) {
      worker.dispose();
      commands.close();
      Isolate.exit();
    }
    await worker.handle(command);
  });
}

/// Owns every native resource: model, context, vocabulary, sampler chain and batch.
///
/// Living inside a single isolate is what makes this safe. A `llama_context` is not
/// concurrency-safe, and an isolate gives the same one-execution-context guarantee the Swift
/// original got from being an `actor` — with the bonus that the decode loop cannot block the
/// UI thread, which on iOS it shared.
class _LlamaWorker {
  _LlamaWorker({required this.replyPort, required this.cancellation}) {
    _native = LlamaNative.forCurrentIsolate();
    _native.backendInit();
    // llama.cpp otherwise prints prompt and timing detail straight to the system log. The
    // app's privacy claim is that no chat content reaches the unified log, and this is the
    // one place that would have quietly broken it.
    _native.disableNativeLogging();
  }

  final SendPort replyPort;
  final CancellationFlag cancellation;

  late final LlamaNative _native;

  static const PromptBuilder _promptBuilder = PromptBuilder();
  static const TokenBudgetManager _tokenBudget = TokenBudgetManager();

  ffi.Pointer<ffi.Void> _model = ffi.nullptr;
  ffi.Pointer<ffi.Void> _context = ffi.nullptr;
  ffi.Pointer<ffi.Void> _vocab = ffi.nullptr;
  ffi.Pointer<ffi.Void> _sampler = ffi.nullptr;
  ffi.Pointer<ffi.Void> _batch = ffi.nullptr;

  String? _chatTemplate;
  String? _modelPath;
  int _modelFileSizeBytes = 0;
  int _trainedContextLength = 0;
  int _allocatedContextLength = 0;
  GenerationConfiguration? _activeConfiguration;

  /// The configuration the current [_sampler] chain was built from — not necessarily the one the
  /// next generation will run with. See [_samplerNeedsRebuild].
  GenerationConfiguration? _samplerConfiguration;
  bool _isGenerating = false;

  bool get _isModelLoaded => _model != ffi.nullptr && _context != ffi.nullptr;

  // ---------------------------------------------------------------------------
  // Command dispatch
  // ---------------------------------------------------------------------------

  Future<void> handle(Map<String, Object?> command) async {
    final id = command['id']! as int;
    final op = command['op']! as String;

    try {
      switch (op) {
        case WorkerOp.load:
          _loadModel(
            path: command['path']! as String,
            configuration: GenerationConfiguration.fromIsolateMap(
                (command['configuration']! as Map).cast<String, Object?>()),
          );
          _replyOk(id, {
            'allocatedContextLength': _allocatedContextLength,
            'trainedContextLength': _trainedContextLength,
          });

        case WorkerOp.unload:
          _requireNotGenerating();
          _freeNativeResources();
          _replyOk(id, const {});

        case WorkerOp.reset:
          _requireNotGenerating();
          if (_context != ffi.nullptr) {
            _native.clearMemory(_context);
          }
          _replyOk(id, const {});

        case WorkerOp.status:
          _replyOk(id, {
            'isModelLoaded': _isModelLoaded,
            'allocatedContextLength': _allocatedContextLength,
          });

        case WorkerOp.countTokens:
          final messages = _decodeMessages(command['messages']);
          _replyOk(id, {'count': _countTokensForConversation(messages)});

        case WorkerOp.generateStructured:
          final raw = (command['messages']! as List).cast<Map<Object?, Object?>>();
          final messages = raw
              .map((m) => (
                    role: m['role']! as String,
                    content: m['content']! as String,
                  ))
              .toList(growable: false);
          final text = await _generateStructured(
            messages: messages,
            configuration: GenerationConfiguration.fromIsolateMap(
                (command['configuration']! as Map).cast<String, Object?>()),
            maxTokens: command['maxTokens']! as int,
            grammar: command['grammar'] as String?,
          );
          _replyOk(id, {'text': text});

        case WorkerOp.generate:
          await _generate(
            id: id,
            messages: _decodeMessages(command['messages']),
            configuration: GenerationConfiguration.fromIsolateMap(
                (command['configuration']! as Map).cast<String, Object?>()),
          );

        default:
          _replyError(id, const LlamaError.unknownNativeError('unknown worker operation'));
      }
    } on LlamaError catch (error) {
      _replyError(id, error);
    } on LlamaNativeException catch (error) {
      _replyError(
        id,
        LlamaError.nativeException(operation: error.operation, underlying: error.message),
      );
    } catch (error) {
      _replyError(id, LlamaError.unknownNativeError(error.toString()));
    }
  }

  void dispose() => _freeNativeResources();

  // ---------------------------------------------------------------------------
  // Load / unload
  // ---------------------------------------------------------------------------

  void _loadModel({required String path, required GenerationConfiguration configuration}) {
    _requireNotGenerating();
    _freeNativeResources();

    final file = File(path);
    if (!file.existsSync()) {
      throw LlamaError.modelFileMissing(path);
    }
    if (!path.toLowerCase().endsWith('.gguf')) {
      throw LlamaError.invalidFileExtension(path.split(Platform.pathSeparator).last);
    }
    final fileSize = file.lengthSync();
    if (fileSize <= 0) {
      throw LlamaError.modelFileMissing(path);
    }

    // GPU offload is only ever attempted where a GPU backend is actually compiled in.
    // On the iOS simulator and on Android CPU builds this collapses to 0, which is the
    // same behaviour the Swift app got from its `#if targetEnvironment(simulator)` guard —
    // generalised, because Android has far more configurations that lack a usable GPU path.
    final gpuLayers = _native.supportsGpuOffload ? configuration.gpuLayers : 0;

    final model = _native.loadModel(path: path, gpuLayers: gpuLayers);

    ffi.Pointer<ffi.Void> vocab = ffi.nullptr;
    try {
      vocab = _native.modelVocab(model);
      if (vocab == ffi.nullptr) {
        throw const LlamaError.modelLoadFailed('model has no vocabulary');
      }

      // A model with no embedded chat template is rejected rather than guessed at. Picking
      // a template that does not match the model's training produces fluent, confident,
      // subtly wrong output — a much worse failure than refusing to load.
      final template = _native.modelChatTemplate(model);
      if (template == null || template.isEmpty) {
        throw const LlamaError.missingChatTemplate();
      }

      final trainedContext = _native.modelTrainedContextLength(model);
      final clampedContext = trainedContext > 0
          ? min(configuration.contextLength, trainedContext)
          : configuration.contextLength;

      final context = _native.createContext(
        model: model,
        contextLength: clampedContext,
        batchSize: configuration.batchSize,
        threadCount: _native.recommendedThreadCount,
      );

      ffi.Pointer<ffi.Void> sampler = ffi.nullptr;
      ffi.Pointer<ffi.Void> batch = ffi.nullptr;
      try {
        sampler = _makeSampler(vocab: vocab, configuration: configuration);
        batch = _native.createBatch(configuration.batchSize);
      } catch (_) {
        if (sampler != ffi.nullptr) _native.freeSamplerChain(sampler);
        _native.freeContext(context);
        rethrow;
      }

      _model = model;
      _vocab = vocab;
      _context = context;
      _sampler = sampler;
      _batch = batch;
      _chatTemplate = template;
      _modelPath = path;
      _modelFileSizeBytes = fileSize;
      _trainedContextLength = trainedContext;
      _allocatedContextLength = _native.allocatedContextLength(context);
      _activeConfiguration = configuration;
      _samplerConfiguration = configuration;
    } catch (_) {
      _native.freeModel(model);
      rethrow;
    }
  }

  /// min-p → top-p → temperature → distribution, matching the Swift original exactly.
  ///
  /// Order is not arbitrary: min-p and top-p prune the candidate set before temperature
  /// reshapes what is left, so reordering them changes the output distribution.
  ffi.Pointer<ffi.Void> _makeSampler({
    required ffi.Pointer<ffi.Void> vocab,
    required GenerationConfiguration configuration,
    String? grammar,
  }) {
    return _native.createSamplerChain(
      vocab: vocab,
      temperature: configuration.temperature,
      minP: configuration.minP,
      topP: configuration.topP,
      seed: configuration.deterministicSeed ?? _native.defaultSeed,
      grammar: grammar,
    );
  }

  void _freeNativeResources() {
    if (_sampler != ffi.nullptr) _native.freeSamplerChain(_sampler);
    if (_batch != ffi.nullptr) _native.freeBatch(_batch);
    if (_context != ffi.nullptr) _native.freeContext(_context);
    if (_model != ffi.nullptr) _native.freeModel(_model);

    _sampler = ffi.nullptr;
    _batch = ffi.nullptr;
    _context = ffi.nullptr;
    _model = ffi.nullptr;
    _vocab = ffi.nullptr;
    _chatTemplate = null;
    _modelPath = null;
    _modelFileSizeBytes = 0;
    _trainedContextLength = 0;
    _allocatedContextLength = 0;
    _activeConfiguration = null;
    _samplerConfiguration = null;
  }

  /// Whether [_sampler] was built from different sampling parameters than [configuration].
  ///
  /// The conversational chain is persistent — it is built once at load and kept across turns so
  /// its accepted-token state survives — which means nothing invalidates it on its own. A
  /// temperature, min-p, top-p or seed change made in Settings therefore has no effect until it
  /// is invalidated explicitly here. Only the four sampling fields matter; the rest of the
  /// configuration does not reach the chain.
  bool _samplerNeedsRebuild(GenerationConfiguration configuration) {
    final built = _samplerConfiguration;
    if (built == null) return true;
    return built.temperature != configuration.temperature ||
        built.minP != configuration.minP ||
        built.topP != configuration.topP ||
        built.deterministicSeed != configuration.deterministicSeed;
  }

  // ---------------------------------------------------------------------------
  // Token counting
  // ---------------------------------------------------------------------------

  int _countTokensForConversation(List<ChatMessage> messages) {
    final configuration = _activeConfiguration;
    if (!_isModelLoaded || configuration == null) {
      throw const LlamaError.modelNotLoaded();
    }
    if (messages.isEmpty) return 0;

    return _countPromptTokens(
      systemPrompt: configuration.systemPrompt,
      history: messages.sublist(0, messages.length - 1),
      currentUserMessage: messages.last,
    );
  }

  int _countPromptTokens({
    required String systemPrompt,
    required List<ChatMessage> history,
    required ChatMessage currentUserMessage,
  }) {
    final list = _promptBuilder.messageList(
      systemPrompt: systemPrompt,
      history: history,
      currentUserMessage: currentUserMessage,
    );
    final formatted = _applyTemplate(list);
    return _tokenize(formatted).length;
  }

  String _applyTemplate(List<({String role, String content})> messages) {
    final template = _chatTemplate;
    if (template == null) {
      throw const LlamaError.missingChatTemplate();
    }
    final formatted = _native.applyChatTemplate(
      template: template,
      messages: messages,
      addAssistantMarker: true,
    );
    if (formatted == null) {
      throw const LlamaError.missingChatTemplate();
    }
    return formatted;
  }

  List<int> _tokenize(String text) {
    if (_vocab == ffi.nullptr) {
      throw const LlamaError.modelNotLoaded();
    }
    return _native.tokenize(_vocab, text);
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _generate({
    required int id,
    required List<ChatMessage> messages,
    required GenerationConfiguration configuration,
  }) async {
    if (!_isModelLoaded) throw const LlamaError.modelNotLoaded();
    if (_isGenerating) throw const LlamaError.generationAlreadyInProgress();
    if (messages.isEmpty || messages.last.role != ChatRole.user) {
      throw const LlamaError.tokenizationFailed();
    }

    _activeConfiguration = configuration;
    _isGenerating = true;
    cancellation.reset();

    final stopwatch = Stopwatch()..start();
    Duration? firstTokenLatency;
    final utf8Buffer = Utf8TokenBuffer();
    var generatedCount = 0;
    var finishReason = GenerationFinishReason.endOfSequence;

    try {
      // 0. Pick up sampling parameters changed since the chain was built.
      if (_samplerNeedsRebuild(configuration)) {
        // Built before the old chain is freed so a failure here cannot leave `_sampler`
        // pointing at freed memory.
        final rebuilt = _makeSampler(vocab: _vocab, configuration: configuration);
        if (_sampler != ffi.nullptr) _native.freeSamplerChain(_sampler);
        _sampler = rebuilt;
        _samplerConfiguration = configuration;
      }

      // 1. Clear the KV cache. The full-prompt-rebuild strategy starts from nothing every
      //    turn — slower than incremental reuse, and impossible to get subtly wrong.
      _native.clearMemory(_context);

      // 2. Trim history to fit, always keeping the current message.
      final history = messages.sublist(0, messages.length - 1);
      final fitted = _tokenBudget.fitHistory(
        systemPrompt: configuration.systemPrompt,
        history: history,
        currentUserMessage: messages.last,
        contextCapacity: _allocatedContextLength,
        reservedOutputTokens: configuration.maxNewTokens,
        safetyMargin: configuration.safetyMargin,
        countTokens: (systemPrompt, msgs) {
          if (msgs.isEmpty) return 0;
          return _countPromptTokens(
            systemPrompt: systemPrompt,
            history: msgs.sublist(0, msgs.length - 1),
            currentUserMessage: msgs.last,
          );
        },
      );

      // 3. Build and tokenize the final prompt.
      final promptTokens = _tokenize(_applyTemplate(_promptBuilder.messageList(
        systemPrompt: configuration.systemPrompt,
        history: fitted.includedHistory,
        currentUserMessage: messages.last,
      )));
      if (promptTokens.isEmpty) {
        throw const LlamaError.tokenizationFailed();
      }

      // 4. Decode the prompt in batch-sized chunks.
      var nPast = await _decodePrompt(promptTokens, batchSize: configuration.batchSize);

      if (cancellation.isCancelled) {
        finishReason = GenerationFinishReason.cancelled;
      } else {
        // 5. Sample until end-of-generation, the token cap, or the context edge.
        while (true) {
          if (cancellation.isCancelled) {
            finishReason = GenerationFinishReason.cancelled;
            break;
          }

          final token = _native.sample(_sampler, _context);
          _native.acceptToken(_sampler, token);

          if (_native.isEndOfGeneration(_vocab, token)) {
            finishReason = GenerationFinishReason.endOfSequence;
            break;
          }

          final text = utf8Buffer.push(_native.tokenToPieceBytes(_vocab, token));
          if (text.isNotEmpty) {
            firstTokenLatency ??= stopwatch.elapsed;
            replyPort.send(<String, Object?>{
              'id': id,
              'status': WorkerReply.token,
              'text': text,
            });
          }

          generatedCount += 1;
          if (generatedCount >= configuration.maxNewTokens) {
            finishReason = GenerationFinishReason.maxTokensReached;
            break;
          }
          // Inherited from the Swift original: hitting the context edge is reported as
          // `maxTokensReached` too, so the UI cannot tell the two causes apart. Kept for
          // fidelity.
          if (nPast >= _allocatedContextLength - 1) {
            finishReason = GenerationFinishReason.maxTokensReached;
            break;
          }

          _decodeSingleToken(token, at: nPast);
          nPast += 1;

          // Hand the event loop a turn so the isolate can answer a status query and so the
          // token just sent actually leaves the port. One microtask per token is free next
          // to a decode that costs tens of milliseconds.
          await Future<void>.delayed(Duration.zero);
        }
      }

      final remainder = utf8Buffer.flush();
      if (remainder.isNotEmpty) {
        replyPort.send(<String, Object?>{
          'id': id,
          'status': WorkerReply.token,
          'text': remainder,
        });
      }

      stopwatch.stop();

      final metrics = GenerationMetrics(
        modelName: _modelFileName,
        modelFileSizeBytes: _modelFileSizeBytes,
        nativeContextLength: _trainedContextLength,
        allocatedContextLength: _allocatedContextLength,
        promptTokenCount: fitted.promptTokenCount,
        reservedOutputTokens: configuration.maxNewTokens,
        generatedTokenCount: generatedCount,
        firstTokenLatency: firstTokenLatency,
        totalGenerationDuration: stopwatch.elapsed,
        conversationMode: '',
      );

      replyPort.send(<String, Object?>{
        'id': id,
        'status': WorkerReply.finished,
        'reason': finishReason.wireValue,
        'metrics': metrics.toIsolateMap(),
      });
    } catch (error) {
      // Emit whatever was buffered before surfacing the failure. Dropping a half-formed
      // multi-byte character on the error path loses text the model actually produced.
      final remainder = utf8Buffer.flush();
      if (remainder.isNotEmpty) {
        replyPort.send(<String, Object?>{
          'id': id,
          'status': WorkerReply.token,
          'text': remainder,
        });
      }
      rethrow;
    } finally {
      _isGenerating = false;
    }
  }

  Future<String> _generateStructured({
    required List<({String role, String content})> messages,
    required GenerationConfiguration configuration,
    required int maxTokens,
    String? grammar,
  }) async {
    if (!_isModelLoaded) throw const LlamaError.modelNotLoaded();
    if (_isGenerating) throw const LlamaError.generationAlreadyInProgress();

    _isGenerating = true;
    cancellation.reset();

    // A temporary chain, freed on the way out, so the persistent conversational sampler is
    // never disturbed by a planner call. The two are never in use at once — this isolate
    // runs one generation at a time by construction.
    ffi.Pointer<ffi.Void> chain = ffi.nullptr;

    try {
      _native.clearMemory(_context);

      final promptTokens = _tokenize(_applyTemplate(messages));
      if (promptTokens.isEmpty) {
        throw const LlamaError.tokenizationFailed();
      }

      var nPast = await _decodePrompt(promptTokens, batchSize: configuration.batchSize);

      chain = _makeSampler(
        vocab: _vocab,
        configuration: configuration,
        grammar: grammar,
      );

      final utf8Buffer = Utf8TokenBuffer();
      final output = StringBuffer();
      var generatedCount = 0;

      while (true) {
        if (cancellation.isCancelled) break;

        final token = _native.sample(chain, _context);
        _native.acceptToken(chain, token);
        if (_native.isEndOfGeneration(_vocab, token)) break;

        output.write(utf8Buffer.push(_native.tokenToPieceBytes(_vocab, token)));

        generatedCount += 1;
        if (generatedCount >= maxTokens) break;
        if (nPast >= _allocatedContextLength - 1) break;

        _decodeSingleToken(token, at: nPast);
        nPast += 1;

        await Future<void>.delayed(Duration.zero);
      }

      output.write(utf8Buffer.flush());
      return output.toString();
    } finally {
      if (chain != ffi.nullptr) {
        _native.freeSamplerChain(chain);
      }
      _isGenerating = false;
    }
  }

  /// Feeds the prompt through in batch-sized chunks, returning the resulting position.
  ///
  /// Only the very last token of the whole prompt asks for logits — every earlier one is
  /// pure context, and computing logits for all of them would cost prompt-length times more
  /// memory bandwidth for output that is thrown away.
  ///
  /// The cancellation check between chunks is what makes a long prefill interruptible. The
  /// Swift original could not cancel here at all, because prompt decoding happened before
  /// its stream even existed.
  Future<int> _decodePrompt(List<int> tokens, {required int batchSize}) async {
    var position = 0;
    var index = 0;

    while (index < tokens.length) {
      if (cancellation.isCancelled) return position;

      final chunkEnd = min(index + batchSize, tokens.length);
      _native.clearBatch(_batch);

      for (var offset = 0; offset < chunkEnd - index; offset++) {
        final isLastTokenOverall = chunkEnd == tokens.length && index + offset == tokens.length - 1;
        _native.addToBatch(
          _batch,
          token: tokens[index + offset],
          position: position + offset,
          needsLogits: isLastTokenOverall,
        );
      }

      if (_native.decode(_context, _batch) != 0) {
        throw const LlamaError.decodeFailed();
      }

      position += chunkEnd - index;
      index = chunkEnd;

      await Future<void>.delayed(Duration.zero);
    }

    return position;
  }

  void _decodeSingleToken(int token, {required int at}) {
    _native.clearBatch(_batch);
    _native.addToBatch(_batch, token: token, position: at, needsLogits: true);
    if (_native.decode(_context, _batch) != 0) {
      throw const LlamaError.decodeFailed();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get _modelFileName {
    final path = _modelPath;
    if (path == null) return '-';
    final separator = path.contains('/') ? '/' : Platform.pathSeparator;
    return path.split(separator).last;
  }

  void _requireNotGenerating() {
    if (_isGenerating) {
      throw const LlamaError.generationAlreadyInProgress();
    }
  }

  static List<ChatMessage> _decodeMessages(Object? raw) {
    return (raw! as List)
        .cast<Map<Object?, Object?>>()
        .map((m) => ChatMessage.fromIsolateMap(m.cast<String, Object?>()))
        .toList(growable: false);
  }

  void _replyOk(int id, Map<String, Object?> payload) {
    replyPort.send(<String, Object?>{'id': id, 'status': WorkerReply.ok, ...payload});
  }

  void _replyError(int id, LlamaError error) {
    replyPort.send(<String, Object?>{
      'id': id,
      'status': WorkerReply.error,
      'error': error.toIsolateMap(),
    });
  }
}
