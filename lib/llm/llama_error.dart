/// Every failure mode the inference stack can produce.
///
/// Modelled as one class with a [kind] discriminator rather than a sealed hierarchy for two
/// reasons: it crosses an isolate boundary as a plain map, and the UI switches on the kind
/// in exactly one place. A hierarchy would buy pattern matching and cost serialisation.
enum LlamaErrorKind {
  modelFileMissing,
  invalidFileExtension,
  fileAccessDenied,
  modelCopyFailed,
  modelLoadFailed,
  unsupportedGguf,
  missingChatTemplate,
  contextCreationFailed,
  samplerCreationFailed,
  tokenizationFailed,
  promptTooLarge,
  decodeFailed,
  generationCancelled,
  outputDecodingFailed,
  databaseSaveFailed,
  insufficientStorage,
  modelNotLoaded,
  generationAlreadyInProgress,

  /// A C++ exception was thrown inside llama.cpp and caught at the shim boundary before it
  /// could cross into Dart and take the process down with it.
  nativeException,
  unknownNativeError,
}

class LlamaError implements Exception {
  const LlamaError(
    this.kind, {
    this.detail,
    this.operation,
    this.requiredTokens,
    this.availableTokens,
  });

  final LlamaErrorKind kind;

  /// Underlying cause — a path, a file name, or a native error string. Developer-facing.
  final String? detail;

  /// For [LlamaErrorKind.nativeException]: which native operation threw.
  final String? operation;

  final int? requiredTokens;
  final int? availableTokens;

  const LlamaError.modelFileMissing(String path)
      : this(LlamaErrorKind.modelFileMissing, detail: path);

  const LlamaError.invalidFileExtension(String fileName)
      : this(LlamaErrorKind.invalidFileExtension, detail: fileName);

  const LlamaError.fileAccessDenied(String path)
      : this(LlamaErrorKind.fileAccessDenied, detail: path);

  const LlamaError.modelCopyFailed(String underlying)
      : this(LlamaErrorKind.modelCopyFailed, detail: underlying);

  const LlamaError.modelLoadFailed(String underlying)
      : this(LlamaErrorKind.modelLoadFailed, detail: underlying);

  const LlamaError.unsupportedGguf(String underlying)
      : this(LlamaErrorKind.unsupportedGguf, detail: underlying);

  const LlamaError.missingChatTemplate() : this(LlamaErrorKind.missingChatTemplate);

  const LlamaError.contextCreationFailed([String? underlying])
      : this(LlamaErrorKind.contextCreationFailed, detail: underlying);

  const LlamaError.samplerCreationFailed([String? underlying])
      : this(LlamaErrorKind.samplerCreationFailed, detail: underlying);

  const LlamaError.tokenizationFailed() : this(LlamaErrorKind.tokenizationFailed);

  const LlamaError.promptTooLarge({required int required, required int available})
      : this(LlamaErrorKind.promptTooLarge,
            requiredTokens: required, availableTokens: available);

  const LlamaError.decodeFailed([String? underlying])
      : this(LlamaErrorKind.decodeFailed, detail: underlying);

  const LlamaError.generationCancelled() : this(LlamaErrorKind.generationCancelled);

  const LlamaError.outputDecodingFailed() : this(LlamaErrorKind.outputDecodingFailed);

  const LlamaError.databaseSaveFailed(String underlying)
      : this(LlamaErrorKind.databaseSaveFailed, detail: underlying);

  const LlamaError.insufficientStorage() : this(LlamaErrorKind.insufficientStorage);

  const LlamaError.modelNotLoaded() : this(LlamaErrorKind.modelNotLoaded);

  const LlamaError.generationAlreadyInProgress()
      : this(LlamaErrorKind.generationAlreadyInProgress);

  const LlamaError.nativeException({required String operation, required String underlying})
      : this(LlamaErrorKind.nativeException, operation: operation, detail: underlying);

  const LlamaError.unknownNativeError(String underlying)
      : this(LlamaErrorKind.unknownNativeError, detail: underlying);

  /// User-facing text. Carried over verbatim from the Swift app's `LlamaError`.
  String get errorDescription => switch (kind) {
        LlamaErrorKind.modelFileMissing =>
          'The selected model file could not be found. It may have been deleted or moved.',
        LlamaErrorKind.invalidFileExtension =>
          "That file isn't a GGUF model. Please choose a file ending in .gguf.",
        LlamaErrorKind.fileAccessDenied =>
          "The app doesn't have permission to read that file.",
        LlamaErrorKind.modelCopyFailed =>
          "The model file couldn't be copied into the app's storage.",
        LlamaErrorKind.modelLoadFailed =>
          'The model failed to load. It may be corrupted or incompatible with this device.',
        LlamaErrorKind.unsupportedGguf => "This GGUF file isn't a supported model format.",
        LlamaErrorKind.missingChatTemplate =>
          "This model doesn't include a usable chat template, so it can't be used for chat yet.",
        LlamaErrorKind.contextCreationFailed =>
          "The app couldn't allocate memory to run this model. Try a smaller context length.",
        LlamaErrorKind.samplerCreationFailed =>
          "The app couldn't set up text generation for this model.",
        LlamaErrorKind.tokenizationFailed =>
          "The app couldn't process this text for the model.",
        LlamaErrorKind.promptTooLarge =>
          "This message is too long for the model's context window "
              '($requiredTokens tokens needed, $availableTokens available).',
        LlamaErrorKind.decodeFailed =>
          'The model encountered an internal error while generating a response.',
        LlamaErrorKind.generationCancelled => 'Generation was stopped.',
        LlamaErrorKind.outputDecodingFailed =>
          "The model produced output that couldn't be decoded as text.",
        LlamaErrorKind.databaseSaveFailed => "Your conversation couldn't be saved.",
        LlamaErrorKind.insufficientStorage =>
          "There isn't enough free storage to complete this operation.",
        LlamaErrorKind.modelNotLoaded => 'No model is currently loaded.',
        LlamaErrorKind.generationAlreadyInProgress =>
          'A response is already being generated.',
        LlamaErrorKind.nativeException =>
          'The model engine hit an internal error and recovered safely. Please try again.',
        LlamaErrorKind.unknownNativeError =>
          'An unexpected error occurred in the model engine.',
      };

  /// Extra detail intended for debug builds only. Never shown in a release UI.
  String? get developerDetail => switch (kind) {
        LlamaErrorKind.nativeException => '$operation: $detail',
        LlamaErrorKind.modelFileMissing ||
        LlamaErrorKind.invalidFileExtension ||
        LlamaErrorKind.fileAccessDenied ||
        LlamaErrorKind.modelCopyFailed ||
        LlamaErrorKind.modelLoadFailed ||
        LlamaErrorKind.unsupportedGguf ||
        LlamaErrorKind.databaseSaveFailed ||
        LlamaErrorKind.unknownNativeError =>
          detail,
        _ => null,
      };

  Map<String, Object?> toIsolateMap() => {
        'kind': kind.name,
        'detail': detail,
        'operation': operation,
        'requiredTokens': requiredTokens,
        'availableTokens': availableTokens,
      };

  static LlamaError fromIsolateMap(Map<String, Object?> map) => LlamaError(
        LlamaErrorKind.values.firstWhere(
          (k) => k.name == map['kind'],
          orElse: () => LlamaErrorKind.unknownNativeError,
        ),
        detail: map['detail'] as String?,
        operation: map['operation'] as String?,
        requiredTokens: map['requiredTokens'] as int?,
        availableTokens: map['availableTokens'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is LlamaError &&
      other.kind == kind &&
      other.detail == detail &&
      other.operation == operation &&
      other.requiredTokens == requiredTokens &&
      other.availableTokens == availableTokens;

  @override
  int get hashCode =>
      Object.hash(kind, detail, operation, requiredTokens, availableTokens);

  @override
  String toString() {
    final extra = developerDetail;
    return extra == null ? 'LlamaError.${kind.name}' : 'LlamaError.${kind.name}($extra)';
  }
}
