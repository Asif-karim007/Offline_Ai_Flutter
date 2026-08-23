/// One result row from a search provider, before any page has been fetched.
class WebSearchResult {
  const WebSearchResult({
    required this.id,
    required this.title,
    required this.url,
    required this.snippet,
    this.sourceName,
    this.publishedDate,
  });

  final String id;
  final String title;
  final Uri url;
  final String snippet;
  final String? sourceName;

  /// Left null by every provider in this app rather than guessed at from an undocumented,
  /// plan-dependent response field.
  final DateTime? publishedDate;

  @override
  bool operator ==(Object other) =>
      other is WebSearchResult &&
      other.id == id &&
      other.title == title &&
      other.url == url &&
      other.snippet == snippet &&
      other.sourceName == sourceName &&
      other.publishedDate == publishedDate;

  @override
  int get hashCode => Object.hash(id, title, url, snippet, sourceName, publishedDate);
}
