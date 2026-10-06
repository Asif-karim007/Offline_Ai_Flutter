import '../l10n/app_strings.dart';

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

  /// User-facing text, in the app's current language. The English wording is carried over
  /// verbatim from the Swift app's `LlamaError`; see `AppStringsEn`.
  String get errorDescription {
    final strings = AppStrings.current;
    return switch (kind) {
      LlamaErrorKind.modelFileMissing => strings.errorModelFileMissing,
      LlamaErrorKind.invalidFileExtension => strings.errorInvalidFileExtension,
      LlamaErrorKind.fileAccessDenied => strings.errorFileAccessDenied,
      LlamaErrorKind.modelCopyFailed => strings.errorModelCopyFailed,
      LlamaErrorKind.modelLoadFailed => strings.errorModelLoadFailed,
      LlamaErrorKind.unsupportedGguf => strings.errorUnsupportedGguf,
      LlamaErrorKind.missingChatTemplate => strings.errorMissingChatTemplate,
      LlamaErrorKind.contextCreationFailed => strings.errorContextCreationFailed,
      LlamaErrorKind.samplerCreationFailed => strings.errorSamplerCreationFailed,
      LlamaErrorKind.tokenizationFailed => strings.errorTokenizationFailed,
      LlamaErrorKind.promptTooLarge =>
        strings.errorPromptTooLarge(requiredTokens, availableTokens),
      LlamaErrorKind.decodeFailed => strings.errorDecodeFailed,
      LlamaErrorKind.generationCancelled => strings.errorGenerationCancelled,
      LlamaErrorKind.outputDecodingFailed => strings.errorOutputDecodingFailed,
      LlamaErrorKind.databaseSaveFailed => strings.errorDatabaseSaveFailed,
      LlamaErrorKind.insufficientStorage => strings.errorInsufficientStorage,
      LlamaErrorKind.modelNotLoaded => strings.errorModelNotLoaded,
      LlamaErrorKind.generationAlreadyInProgress => strings.errorGenerationAlreadyInProgress,
      LlamaErrorKind.nativeException => strings.errorNativeException,
      LlamaErrorKind.unknownNativeError => strings.errorUnknownNative,
    };
  }

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
