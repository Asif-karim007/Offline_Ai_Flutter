/// One passage from a curriculum textbook, as handed to the model and cited back to the user.
class TextbookExcerpt {
  const TextbookExcerpt({
    required this.bookTitle,
    required this.page,
    required this.text,
  });

  final String bookTitle;

  /// The PDF page the passage starts on. Null when the pack did not record one.
  final int? page;

  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextbookExcerpt &&
      other.bookTitle == bookTitle &&
      other.page == page &&
      other.text == text;

  @override
  int get hashCode => Object.hash(bookTitle, page, text);
}

/// Searches the student's installed curriculum pack.
///
/// The agent layer depends on this interface only — not on SQLite, the pack format or how
/// packs are downloaded — the same way it reaches web search through `WebSearchService`.
abstract interface class TextbookRetriever {
  /// The best-matching passages for [query], at most [limit], most relevant first. Empty when
  /// no pack is active, the pack is still being prepared, or nothing matches. Never throws:
  /// a broken pack must degrade to "no textbook evidence", not to a failed answer.
  Future<List<TextbookExcerpt>> search(String query, {int limit});
}
