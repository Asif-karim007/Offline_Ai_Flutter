import 'dart:async';

import '../domain/chat_message.dart';
import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';
import 'chat_engine.dart';

/// The [ChatEngine] used when the llama.cpp shim is not in the process.
///
/// The native library is not checked into the repository; it is produced by
/// `scripts/build_llama_android.sh` / `scripts/build_llama_ios.sh`. Before that build has
/// run there is no `lc_*` symbol to call, and [LlamaEngine] would spawn a worker isolate
/// that dies on its first lookup — with `errorsAreFatal: true`, that takes the app down on
/// the first message with a stack trace instead of an explanation.
///
/// This stands in instead. Every screen, the conversation store, settings, model management,
/// document import and the whole agent pipeline stay exercisable; the one thing that does
/// not happen is inference, and asking for it produces a message saying exactly why and what
/// to run. Swap back to the real engine by building the native library — [AppCoordinator]
/// re-probes on every launch and prefers [LlamaEngine] whenever the symbol resolves.
class StubChatEngine implements ChatEngine {
  StubChatEngine();

  /// The same ~4-characters-per-token rule of thumb `TokenEstimator` uses, inlined so the
  /// llm layer keeps its one-way dependency on `domain` and does not reach up into `agent`.
  static int _estimateTokens(String text) {
    final estimate = text.length ~/ 4;
    return estimate > 1 ? estimate : 1;
  }

  /// Roughly a fast local model, so streaming looks like streaming rather than a paste.
  static const Duration _tokenInterval = Duration(milliseconds: 28);

  static const String _explanation =
      'The llama.cpp native library is not built into this app yet, so there is no model to '
      'run. Everything else works — conversations, documents, settings and model management '
      'are all real.\n\n'
      'To enable inference:\n'
      '  • Android — run scripts/build_llama_android.sh, then flutter run\n'
      '  • iOS — run scripts/build_llama_ios.sh, then pod install in ios/ and flutter run\n\n'
      'The app detects the library on launch and switches to the real engine automatically.';

  bool _modelLoaded = false;
  String _modelName = '-';
  int _contextLength = 0;

  @override
  Future<void> loadModel({
    required String path,
    required GenerationConfiguration configuration,
  }) async {
    _modelName = path.split('/').last;
    _contextLength = configuration.contextLength;
    _modelLoaded = true;
  }

  @override
  Future<void> unloadModel() async {
    _modelLoaded = false;
    _contextLength = 0;
  }

  @override
  Future<void> resetConversation() async {}

  @override
  Future<bool> get isModelLoaded async => _modelLoaded;

  @override
  Future<int> get currentAllocatedContextLength async => _contextLength;

  @override
  Future<int> countTokens(List<ChatMessage> messages) async {
    var total = 0;
    for (final message in messages) {
      total += _estimateTokens(message.content);
    }
    return total;
  }

  /// Returns the planner's own "no tool needed" shape.
  ///
  /// [AgentPlanner] parses this leniently and falls back to a direct answer when it cannot,
  /// so the exact keys matter less than the response being valid JSON — but returning the
  /// real shape keeps the stub on the same code path as the model.
  @override
  Future<String> generateStructured({
    required List<({String role, String content})> messages,
    required GenerationConfiguration configuration,
    required int maxTokens,
    String? grammar,
  }) async {
    return '{"action":"answer","reason":"stub engine: no model loaded"}';
  }

  @override
  Stream<GenerationEvent> generate({
    required List<ChatMessage> messages,
    required GenerationConfiguration configuration,
  }) {
    late final StreamController<GenerationEvent> controller;
    Timer? timer;
    var cancelled = false;

    controller = StreamController<GenerationEvent>(
      onListen: () {
        final started = DateTime.now();
        // Word-at-a-time rather than character-at-a-time: the message bubble re-lays-out on
        // every chunk, and a whitespace-preserving split is the closest cheap analogue of
        // what a real tokenizer emits.
        final chunks = _explanation.split(RegExp(r'(?<=\s)'));
        var emitted = 0;
        Duration? firstTokenLatency;

        timer = Timer.periodic(_tokenInterval, (Timer t) {
          if (cancelled || controller.isClosed) {
            t.cancel();
            return;
          }
          if (emitted >= chunks.length) {
            t.cancel();
            controller.add(GenerationEvent.finished(
              reason: GenerationFinishReason.endOfSequence,
              metrics: _metrics(
                messages: messages,
                configuration: configuration,
                generated: emitted,
                firstTokenLatency: firstTokenLatency,
                total: DateTime.now().difference(started),
              ),
            ));
            unawaited(controller.close());
            return;
          }
          firstTokenLatency ??= DateTime.now().difference(started);
          controller.add(GenerationEvent.token(chunks[emitted]));
          emitted++;
        });
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  GenerationMetrics _metrics({
    required List<ChatMessage> messages,
    required GenerationConfiguration configuration,
    required int generated,
    required Duration? firstTokenLatency,
    required Duration total,
  }) {
    var promptTokens = 0;
    for (final message in messages) {
      promptTokens += _estimateTokens(message.content);
    }
    return GenerationMetrics(
      modelName: _modelLoaded ? '$_modelName (stub)' : 'stub',
      modelFileSizeBytes: 0,
      nativeContextLength: configuration.contextLength,
      allocatedContextLength: _contextLength,
      promptTokenCount: promptTokens,
      reservedOutputTokens: configuration.maxNewTokens,
      generatedTokenCount: generated,
      conversationMode: 'stub',
      firstTokenLatency: firstTokenLatency,
      totalGenerationDuration: total,
    );
  }
}
