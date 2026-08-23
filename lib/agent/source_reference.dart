enum SourceKind { document, web }

/// A citation the UI can render and the user can tap, mapped back from real retrieval/search
/// metadata — never from text the model generated. The model only ever emits bracketed IDs
/// (`[doc:1]`, `[web:2]`) that the app resolves against the references it actually retrieved.
class SourceReference {
  const SourceReference({
    required this.id,
    required this.kind,
    required this.title,
    this.url,
    this.page,
    this.section,
  });

  /// `"doc:1"` / `"web:1"`, one-based, assigned by the orchestrator in retrieval order.
  final String id;
  final SourceKind kind;
  final String title;
  final Uri? url;
  final int? page;

  /// Always null in the current pipeline — retained because the citation format allows for a
  /// section anchor and dropping the field would be a schema change, not a simplification.
  final String? section;

  @override
  bool operator ==(Object other) =>
      other is SourceReference &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.url == url &&
      other.page == page &&
      other.section == section;

  @override
  int get hashCode => Object.hash(id, kind, title, url, page, section);
}
