/// A GGUF model file installed in the app's models directory.
class LocalModelInfo {
  const LocalModelInfo({
    required this.fileName,
    required this.fileSizeBytes,
    required this.importedAt,
    this.architecture,
    this.quantization,
    this.nativeContextLength,
    this.hasChatTemplate,
  });

  /// The file name is the identity. Two models with the same name cannot coexist in the
  /// models directory, so nothing else is needed to tell them apart.
  String get id => fileName;

  final String fileName;
  final int fileSizeBytes;
  final DateTime importedAt;

  /// Read from GGUF metadata with a vocab-only load, so these are null until the model has
  /// been probed. A probe never touches the live context.
  final String? architecture;
  final String? quantization;
  final int? nativeContextLength;

  /// Null means "not probed yet"; false means the model has no usable chat template and
  /// cannot be selected. The two are different states and the UI shows them differently.
  final bool? hasChatTemplate;

  LocalModelInfo copyWith({
    String? architecture,
    String? quantization,
    int? nativeContextLength,
    bool? hasChatTemplate,
  }) {
    return LocalModelInfo(
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      importedAt: importedAt,
      architecture: architecture ?? this.architecture,
      quantization: quantization ?? this.quantization,
      nativeContextLength: nativeContextLength ?? this.nativeContextLength,
      hasChatTemplate: hasChatTemplate ?? this.hasChatTemplate,
    );
  }

  Map<String, Object?> toJson() => {
        'fileName': fileName,
        'fileSizeBytes': fileSizeBytes,
        'importedAt': importedAt.toIso8601String(),
        'architecture': architecture,
        'quantization': quantization,
        'nativeContextLength': nativeContextLength,
        'hasChatTemplate': hasChatTemplate,
      };

  static LocalModelInfo fromJson(Map<String, Object?> json) => LocalModelInfo(
        fileName: json['fileName']! as String,
        fileSizeBytes: json['fileSizeBytes']! as int,
        importedAt: DateTime.parse(json['importedAt']! as String),
        architecture: json['architecture'] as String?,
        quantization: json['quantization'] as String?,
        nativeContextLength: json['nativeContextLength'] as int?,
        hasChatTemplate: json['hasChatTemplate'] as bool?,
      );

  @override
  bool operator ==(Object other) =>
      other is LocalModelInfo &&
      other.fileName == fileName &&
      other.fileSizeBytes == fileSizeBytes &&
      other.importedAt == importedAt &&
      other.architecture == architecture &&
      other.quantization == quantization &&
      other.nativeContextLength == nativeContextLength &&
      other.hasChatTemplate == hasChatTemplate;

  @override
  int get hashCode => Object.hash(fileName, fileSizeBytes, importedAt, architecture,
      quantization, nativeContextLength, hasChatTemplate);
}
