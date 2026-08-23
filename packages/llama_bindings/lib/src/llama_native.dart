import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'llama_ffi.dart';

/// Thrown when the shim caught a C++ exception, or when a native call failed in a way the
/// caller has to handle. The `operation` matches the wording the Swift original used in
/// `LlamaError.nativeException` so log output stays comparable between the two apps.
class LlamaNativeException implements Exception {
  const LlamaNativeException(this.operation, this.message);

  final String operation;
  final String message;

  @override
  String toString() => 'LlamaNativeException($operation): $message';
}

/// Marshalling layer over [LlamaFfi].
///
/// Everything here is mechanical: allocate, copy in, call, copy out, free. There is no
/// policy — no prompt construction, no budgeting, no sampling strategy. That belongs to the
/// engine one layer up, which is what makes the engine unit-testable against a fake.
///
/// All memory is allocated with the `ffi` package's `calloc` and released in `finally`
/// blocks, including on the exception paths, because a throw here happens during generation
/// and would otherwise leak a buffer per failed token.
class LlamaNative {
  LlamaNative._(this._ffi);

  /// One instance per isolate. See [LlamaFfi.instance] for why this is not process-wide.
  factory LlamaNative.forCurrentIsolate() => LlamaNative._(LlamaFfi.instance);

  final LlamaFfi _ffi;

  static const int _errorBufferSize = 512;

  // ---------------------------------------------------------------------------
  // Backend
  // ---------------------------------------------------------------------------

  void backendInit() => _ffi.backendInit();

  /// Silences llama.cpp's own stderr output. Called once at engine start: the app's own
  /// logging records structural metadata only, and llama.cpp would otherwise print prompt
  /// and timing detail straight to the system log.
  void disableNativeLogging() => _ffi.logDisable();

  bool get supportsGpuOffload => _ffi.supportsGpuOffload();

  /// The thread count the engine should ask for.
  ///
  /// `max(1, min(8, cores - 2))` — carried over verbatim from `LlamaEngine.loadModel`.
  /// Leaving two cores free keeps the UI isolate responsive during a long prefill, and the
  /// cap at eight is where llama.cpp stops scaling on phone-class memory bandwidth.
  int get recommendedThreadCount {
    final cores = _ffi.cpuCount();
    final leaveFree = cores - 2;
    return leaveFree < 1 ? 1 : (leaveFree > 8 ? 8 : leaveFree);
  }

  int get defaultSeed => _ffi.defaultSeed();

  // ---------------------------------------------------------------------------
  // Model
  // ---------------------------------------------------------------------------

  /// Loads a model, or throws [LlamaNativeException].
  ffi.Pointer<ffi.Void> loadModel({
    required String path,
    required int gpuLayers,
    bool vocabOnly = false,
  }) {
    final pathPtr = path.toNativeUtf8().cast<ffi.Char>();
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      final model = _ffi.modelLoad(pathPtr, gpuLayers, vocabOnly, err, _errorBufferSize);
      if (model == ffi.nullptr) {
        throw LlamaNativeException('loading model', _readError(err));
      }
      return model;
    } finally {
      calloc.free(pathPtr);
      calloc.free(err);
    }
  }

  void freeModel(ffi.Pointer<ffi.Void> model) => _ffi.modelFree(model);

  ffi.Pointer<ffi.Void> modelVocab(ffi.Pointer<ffi.Void> model) => _ffi.modelVocab(model);

  int modelTrainedContextLength(ffi.Pointer<ffi.Void> model) => _ffi.modelNCtxTrain(model);

  int modelSizeBytes(ffi.Pointer<ffi.Void> model) => _ffi.modelSize(model);

  int modelParameterCount(ffi.Pointer<ffi.Void> model) => _ffi.modelNParams(model);

  /// The GGUF-embedded chat template, or `null` when the model has none.
  ///
  /// A missing template is not recoverable and must not be guessed at — the caller rejects
  /// the model. Templates for large models run to several kilobytes, so this grows the
  /// buffer once on the negative-return path rather than guessing large up front.
  String? modelChatTemplate(ffi.Pointer<ffi.Void> model) {
    var capacity = 8192;
    for (var attempt = 0; attempt < 2; attempt++) {
      final buf = calloc<ffi.Char>(capacity);
      try {
        final written = _ffi.modelChatTemplate(model, buf, capacity);
        if (written == 0) return null;
        if (written > 0) {
          return utf8.decode(_copyBytes(buf, written), allowMalformed: true);
        }
        capacity = -written + 1;
      } finally {
        calloc.free(buf);
      }
    }
    return null;
  }

  /// Reads one GGUF metadata string, e.g. `general.architecture`.
  String? modelMetadataString(ffi.Pointer<ffi.Void> model, String key) {
    final keyPtr = key.toNativeUtf8().cast<ffi.Char>();
    const capacity = 512;
    final buf = calloc<ffi.Char>(capacity);
    try {
      final written = _ffi.modelMetaValStr(model, keyPtr, buf, capacity);
      if (written <= 0) return null;
      return utf8.decode(_copyBytes(buf, written), allowMalformed: true);
    } finally {
      calloc.free(keyPtr);
      calloc.free(buf);
    }
  }

  // ---------------------------------------------------------------------------
  // Context
  // ---------------------------------------------------------------------------

  ffi.Pointer<ffi.Void> createContext({
    required ffi.Pointer<ffi.Void> model,
    required int contextLength,
    required int batchSize,
    required int threadCount,
  }) {
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      final ctx =
          _ffi.contextNew(model, contextLength, batchSize, threadCount, err, _errorBufferSize);
      if (ctx == ffi.nullptr) {
        throw LlamaNativeException('creating context', _readError(err));
      }
      return ctx;
    } finally {
      calloc.free(err);
    }
  }

  void freeContext(ffi.Pointer<ffi.Void> ctx) => _ffi.contextFree(ctx);

  int allocatedContextLength(ffi.Pointer<ffi.Void> ctx) => _ffi.nCtx(ctx);

  /// Clears the KV cache without touching model weights.
  void clearMemory(ffi.Pointer<ffi.Void> ctx) => _ffi.memoryClear(ctx);

  // ---------------------------------------------------------------------------
  // Batch
  // ---------------------------------------------------------------------------

  ffi.Pointer<ffi.Void> createBatch(int capacity) {
    final batch = _ffi.batchNew(capacity);
    if (batch == ffi.nullptr) {
      throw const LlamaNativeException('allocating batch', 'lc_batch_new returned NULL');
    }
    return batch;
  }

  void freeBatch(ffi.Pointer<ffi.Void> batch) => _ffi.batchFree(batch);

  void clearBatch(ffi.Pointer<ffi.Void> batch) => _ffi.batchClear(batch);

  void addToBatch(
    ffi.Pointer<ffi.Void> batch, {
    required int token,
    required int position,
    required bool needsLogits,
  }) {
    if (!_ffi.batchAdd(batch, token, position, needsLogits)) {
      throw const LlamaNativeException('adding to batch', 'batch is at capacity');
    }
  }

  /// Runs one decode. Returns llama.cpp's own result code, where 0 means success and a
  /// positive value is a warning (1 = no KV slot, 2 = aborted).
  ///
  /// Throws [LlamaNativeException] when the shim caught a C++ exception, which is the case
  /// the Swift original added its Objective-C++ shim for. Without that catch the process
  /// dies rather than surfacing an error.
  int decode(ffi.Pointer<ffi.Void> ctx, ffi.Pointer<ffi.Void> batch) {
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      final result = _ffi.decode(ctx, batch, err, _errorBufferSize);
      if (result == lcDecodeException) {
        throw LlamaNativeException('decoding', _readError(err));
      }
      return result;
    } finally {
      calloc.free(err);
    }
  }

  // ---------------------------------------------------------------------------
  // Vocabulary
  // ---------------------------------------------------------------------------

  /// Tokenises `text`, growing the output buffer once if the first estimate was short.
  ///
  /// `addSpecial` is false at every call site because the chat template has already inserted
  /// the model's own BOS/turn markers; letting the tokenizer add another would corrupt the
  /// prompt. `parseSpecial` is true so those template markers tokenise as the control tokens
  /// they are rather than as literal text.
  Int32List tokenize(
    ffi.Pointer<ffi.Void> vocab,
    String text, {
    bool addSpecial = false,
    bool parseSpecial = true,
  }) {
    final utf8Bytes = utf8.encode(text);
    final textPtr = calloc<ffi.Uint8>(utf8Bytes.length + 1);
    textPtr.asTypedList(utf8Bytes.length + 1).setAll(0, [...utf8Bytes, 0]);

    var capacity = utf8Bytes.length + 16;
    var out = calloc<ffi.Int32>(capacity);
    try {
      var count = _ffi.tokenize(vocab, textPtr.cast<ffi.Char>(), utf8Bytes.length, out,
          capacity, addSpecial, parseSpecial);

      if (count < 0) {
        calloc.free(out);
        capacity = -count;
        out = calloc<ffi.Int32>(capacity);
        count = _ffi.tokenize(vocab, textPtr.cast<ffi.Char>(), utf8Bytes.length, out, capacity,
            addSpecial, parseSpecial);
        if (count < 0) {
          throw const LlamaNativeException('tokenizing', 'llama_tokenize failed twice');
        }
      }

      return Int32List.fromList(out.asTypedList(count));
    } finally {
      calloc.free(textPtr);
      calloc.free(out);
    }
  }

  /// The raw bytes for one token.
  ///
  /// Returns bytes, not a String, on purpose: a single token is frequently only part of a
  /// multi-byte scalar, so decoding here would produce replacement characters mid-word. The
  /// caller reassembles across tokens.
  Uint8List tokenToPieceBytes(ffi.Pointer<ffi.Void> vocab, int token) {
    var capacity = 16;
    for (var attempt = 0; attempt < 2; attempt++) {
      final buf = calloc<ffi.Char>(capacity);
      try {
        final written = _ffi.tokenToPiece(vocab, token, buf, capacity);
        if (written > 0) {
          return Uint8List.fromList(_copyBytes(buf, written));
        }
        if (written == 0) return Uint8List(0);
        capacity = -written;
      } finally {
        calloc.free(buf);
      }
    }
    return Uint8List(0);
  }

  bool isEndOfGeneration(ffi.Pointer<ffi.Void> vocab, int token) =>
      _ffi.vocabIsEog(vocab, token);

  // ---------------------------------------------------------------------------
  // Chat template
  // ---------------------------------------------------------------------------

  /// Applies the model's own chat template to `messages`.
  ///
  /// [addAssistantMarker] appends the tokens that open an assistant turn, which is required
  /// so the model continues as the assistant instead of repeating the user's turn.
  ///
  /// Returns `null` when the template could not be applied at all, which the caller treats
  /// as a missing-template failure.
  String? applyChatTemplate({
    required String template,
    required List<({String role, String content})> messages,
    required bool addAssistantMarker,
  }) {
    final templatePtr = template.toNativeUtf8().cast<ffi.Char>();
    final roles = calloc<ffi.Pointer<ffi.Char>>(messages.length);
    final contents = calloc<ffi.Pointer<ffi.Char>>(messages.length);
    final owned = <ffi.Pointer<Utf8>>[];

    try {
      for (var i = 0; i < messages.length; i++) {
        final rolePtr = messages[i].role.toNativeUtf8();
        final contentPtr = messages[i].content.toNativeUtf8();
        owned..add(rolePtr)..add(contentPtr);
        roles[i] = rolePtr.cast<ffi.Char>();
        contents[i] = contentPtr.cast<ffi.Char>();
      }

      // llama.cpp's own guidance: allocate twice the total character count.
      var capacity = 64;
      for (final message in messages) {
        capacity += (message.role.length + message.content.length + 8) * 2;
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        final buf = calloc<ffi.Char>(capacity);
        try {
          final required = _ffi.chatApplyTemplate(
              templatePtr, roles, contents, messages.length, addAssistantMarker, buf, capacity);
          if (required < 0) return null;
          if (required <= capacity) {
            return utf8.decode(_copyBytes(buf, required), allowMalformed: true);
          }
          capacity = required + 1;
        } finally {
          calloc.free(buf);
        }
      }
      return null;
    } finally {
      calloc.free(templatePtr);
      calloc.free(roles);
      calloc.free(contents);
      for (final ptr in owned) {
        calloc.free(ptr);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Sampler chain
  // ---------------------------------------------------------------------------

  /// Builds a sampler chain: optional grammar, then min-p, top-p, temperature, distribution.
  ///
  /// That order is carried over from `LlamaEngine.makeSampler` unchanged. Passing a
  /// [grammar] is supported but no call site in this app does — see the note in
  /// `src/llama_shim.h` about why grammar-constrained sampling is deliberately unused.
  ffi.Pointer<ffi.Void> createSamplerChain({
    required ffi.Pointer<ffi.Void> vocab,
    required double temperature,
    required double minP,
    required double topP,
    required int seed,
    String? grammar,
    String grammarRoot = 'root',
  }) {
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      final chain = _ffi.samplerChainNew(err, _errorBufferSize);
      if (chain == ffi.nullptr) {
        throw LlamaNativeException('creating sampler', _readError(err));
      }

      if (grammar != null) {
        final grammarPtr = grammar.toNativeUtf8().cast<ffi.Char>();
        final rootPtr = grammarRoot.toNativeUtf8().cast<ffi.Char>();
        try {
          final ok = _ffi.samplerAddGrammar(
              chain, vocab, grammarPtr, rootPtr, err, _errorBufferSize);
          if (!ok) {
            _ffi.samplerFree(chain);
            throw LlamaNativeException('grammar creation', _readError(err));
          }
        } finally {
          calloc.free(grammarPtr);
          calloc.free(rootPtr);
        }
      }

      _ffi.samplerAddMinP(chain, minP, 1);
      _ffi.samplerAddTopP(chain, topP, 1);
      _ffi.samplerAddTemp(chain, temperature);
      _ffi.samplerAddDist(chain, seed);
      return chain;
    } finally {
      calloc.free(err);
    }
  }

  void freeSamplerChain(ffi.Pointer<ffi.Void> chain) => _ffi.samplerFree(chain);

  int sample(ffi.Pointer<ffi.Void> chain, ffi.Pointer<ffi.Void> ctx, {int index = -1}) {
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      final token = _ffi.samplerSample(chain, ctx, index, err, _errorBufferSize);
      if (token == lcSampleError) {
        throw LlamaNativeException('sampling', _readError(err));
      }
      return token;
    } finally {
      calloc.free(err);
    }
  }

  void acceptToken(ffi.Pointer<ffi.Void> chain, int token) {
    final err = calloc<ffi.Char>(_errorBufferSize);
    try {
      if (!_ffi.samplerAccept(chain, token, err, _errorBufferSize)) {
        throw LlamaNativeException('accepting token', _readError(err));
      }
    } finally {
      calloc.free(err);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _readError(ffi.Pointer<ffi.Char> err) {
    final message = err.cast<Utf8>().toDartString();
    return message.isEmpty ? 'unknown native error' : message;
  }

  /// Copies `length` bytes out of a native char buffer.
  ///
  /// `llama_token_to_piece` does not write a NUL terminator, so this must be length-driven
  /// rather than using `toDartString()`.
  static List<int> _copyBytes(ffi.Pointer<ffi.Char> buf, int length) =>
      List<int>.from(buf.cast<ffi.Uint8>().asTypedList(length));
}
