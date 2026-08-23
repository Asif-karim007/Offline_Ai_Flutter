import 'extracted_document.dart';

enum DocumentExtractionErrorKind {
  unsupportedFormat,
  noExtractableText,
  fileAccessDenied,
}

/// Extraction failures. Modelled the same way `LlamaError` is — one class with a [kind]
/// discriminator — so the two error types read alike at a `catch` site.
class DocumentExtractionError implements Exception {
  const DocumentExtractionError(this.kind, {this.fileName});

  final DocumentExtractionErrorKind kind;

  /// Set for [DocumentExtractionErrorKind.unsupportedFormat] only.
  final String? fileName;

  const DocumentExtractionError.unsupportedFormat(String fileName)
      : this(DocumentExtractionErrorKind.unsupportedFormat, fileName: fileName);

  const DocumentExtractionError.noExtractableText()
      : this(DocumentExtractionErrorKind.noExtractableText);

  const DocumentExtractionError.fileAccessDenied()
      : this(DocumentExtractionErrorKind.fileAccessDenied);

  /// User-facing text, verbatim from the Swift `LocalizedError` conformance.
  String get errorDescription => switch (kind) {
        DocumentExtractionErrorKind.unsupportedFormat =>
          '"$fileName" isn\'t a supported file type.',
        DocumentExtractionErrorKind.noExtractableText =>
          'This PDF does not contain extractable text.',
        DocumentExtractionErrorKind.fileAccessDenied =>
          'I no longer have access to this file. Please select it again.',
      };

  @override
  bool operator ==(Object other) =>
      other is DocumentExtractionError && other.kind == kind && other.fileName == fileName;

  @override
  int get hashCode => Object.hash(kind, fileName);

  @override
  String toString() => 'DocumentExtractionError.${kind.name}';
}

/// Turns one file into plain text. Implementations are tried in order by
/// [LocalDocumentManager]; the first whose [canHandle] returns true wins.
abstract interface class DocumentTextExtractor {
  bool canHandle(Uri uri);

  Future<ExtractedDocument> extract(Uri uri);
}
