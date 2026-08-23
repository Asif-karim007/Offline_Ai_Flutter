/// One excerpt of one fetched page, ready to be folded into the system prompt as untrusted
/// evidence.
class RetrievedWebChunk {
  const RetrievedWebChunk({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.url,
    required this.text,
    required this.retrievedAt,
    this.publishedDate,
  });

  final String id;

  /// The originating [WebSearchResult]'s id, so several excerpts from one page stay linkable
  /// back to a single source.
  final String sourceId;

  final String title;
  final Uri url;
  final String text;
  final DateTime? publishedDate;

  /// One timestamp shared by every chunk from the same search batch.
  final DateTime retrievedAt;

  @override
  bool operator ==(Object other) =>
      other is RetrievedWebChunk &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.title == title &&
      other.url == url &&
      other.text == text &&
      other.publishedDate == publishedDate &&
      other.retrievedAt == retrievedAt;

  @override
  int get hashCode =>
      Object.hash(id, sourceId, title, url, text, publishedDate, retrievedAt);
}
