/// One retrievable span of an extracted document.
class DocumentChunk {
  const DocumentChunk({
    required this.id,
    required this.documentId,
    required this.documentName,
    required this.chunkIndex,
    required this.text,
    this.startOffset,
    this.pageNumber,
  });

  final String id;
  final String documentId;
  final String documentName;
  final int chunkIndex;
  final String text;

  /// Character offset into the page-marker-stripped document text.
  final int? startOffset;

  /// One-based, and only ever non-null for PDFs — it is derived from the `[[page:N]]` markers
  /// [PdfTextExtractor] embeds and [DocumentChunker] strips.
  final int? pageNumber;

  @override
  bool operator ==(Object other) =>
      other is DocumentChunk &&
      other.id == id &&
      other.documentId == documentId &&
      other.documentName == documentName &&
      other.chunkIndex == chunkIndex &&
      other.text == text &&
      other.startOffset == startOffset &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode =>
      Object.hash(id, documentId, documentName, chunkIndex, text, startOffset, pageNumber);
}
