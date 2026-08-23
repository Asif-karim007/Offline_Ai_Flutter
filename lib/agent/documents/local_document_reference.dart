/// A document the user has explicitly attached to the active session.
///
/// A lightweight reference only — extracted text and chunks live in [DocumentIndex], never here
/// and never in [AgentRequest] or `ChatMessage`.
class LocalDocumentReference {
  const LocalDocumentReference({required this.id, required this.displayName});

  final String id;
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is LocalDocumentReference &&
      other.id == id &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, displayName);
}
