/// Whether the active chat is being saved.
///
/// A temporary chat exists in memory only: it is never written to the database, to
/// preferences, to logs, or to any file, and it is gone the moment the session ends. That
/// guarantee is enforced by every write path checking [isTemporary] before touching disk.
sealed class ChatSessionMode {
  const ChatSessionMode();

  const factory ChatSessionMode.persistent({String? conversationId}) = PersistentSession;

  const factory ChatSessionMode.temporary() = TemporarySession;

  bool get isTemporary => this is TemporarySession;

  /// The conversation this session writes to, or `null` for a persistent session that has
  /// not been saved yet (no messages sent) and for every temporary session.
  String? get conversationId => switch (this) {
        PersistentSession(:final conversationId) => conversationId,
        TemporarySession() => null,
      };
}

final class PersistentSession extends ChatSessionMode {
  const PersistentSession({this.conversationId});

  @override
  final String? conversationId;

  @override
  bool operator ==(Object other) =>
      other is PersistentSession && other.conversationId == conversationId;

  @override
  int get hashCode => Object.hash('persistent', conversationId);
}

final class TemporarySession extends ChatSessionMode {
  const TemporarySession();

  @override
  bool operator ==(Object other) => other is TemporarySession;

  @override
  int get hashCode => 'temporary'.hashCode;
}
