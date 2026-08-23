import '../domain/chat_message.dart';
import '../domain/chat_role.dart';

/// The row shape of a persisted message — the port of `StoredMessageEntity`.
///
/// Kept separate from [ChatMessage] for the same reason the Swift app kept
/// `StoredMessageEntity` separate from it: the stored form carries a foreign key and stores
/// its enums as raw strings, and the domain form carries neither. Converting explicitly at
/// the boundary is what stops a database concern from leaking into the engine and the views.
class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.conversationId,
    required this.roleWireValue,
    required this.content,
    required this.createdAt,
    required this.statusWireValue,
  });

  final String id;
  final String conversationId;

  /// Stored as the raw string, decoded leniently.
  ///
  /// An unrecognised role reads back as `user` and an unrecognised status as `complete`,
  /// matching `ChatRole(rawValue:) ?? .user` and `MessageStatus(rawValue:) ?? .complete`.
  /// A strict converter that threw would make one bad row poison an entire transcript, and
  /// the fallbacks are the safe direction: an unknown role rendered as the user's own text
  /// is visibly wrong, whereas rendering it as the assistant's would be quietly wrong.
  final String roleWireValue;

  final String content;
  final DateTime createdAt;
  final String statusWireValue;

  ChatRole get role => ChatRole.fromWireValue(roleWireValue);

  MessageStatus get status => MessageStatus.fromWireValue(statusWireValue);

  static StoredMessage fromChatMessage(ChatMessage message, String conversationId) {
    return StoredMessage(
      id: message.id,
      conversationId: conversationId,
      roleWireValue: message.role.wireValue,
      content: message.content,
      createdAt: message.createdAt,
      statusWireValue: message.status.wireValue,
    );
  }

  /// Rebuilds the domain value.
  ///
  /// [ChatMessage.errorDescription] is always `null` here because it has no column. That is
  /// the Swift behaviour preserved deliberately, not an oversight: the field describes a
  /// failure of one live generation attempt, and a failure message replayed days later from
  /// a reloaded transcript would read as if it had just happened. A message that failed is
  /// still distinguishable after a reload — its `status` is `failed`, which is persisted.
  ChatMessage toChatMessage() {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      status: status,
    );
  }

  /// Column names match `SqfliteConversationRepository`'s schema exactly; the repository
  /// owns the SQL, this owns the mapping.
  Map<String, Object?> toRow() => {
        'id': id,
        'conversation_id': conversationId,
        'role': roleWireValue,
        'content': content,
        // Millis since the Unix epoch, UTC. SQLite has no date type and sorting has to
        // happen on a numeric column, so the conversion is done here rather than relying on
        // lexicographic ordering of ISO-8601 text.
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'status': statusWireValue,
      };

  static StoredMessage fromRow(Map<String, Object?> row) {
    return StoredMessage(
      id: row['id']! as String,
      conversationId: row['conversation_id']! as String,
      roleWireValue: row['role']! as String,
      content: row['content']! as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int, isUtc: true)
              .toLocal(),
      statusWireValue: row['status']! as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoredMessage &&
      other.id == id &&
      other.conversationId == conversationId &&
      other.roleWireValue == roleWireValue &&
      other.content == content &&
      other.createdAt == createdAt &&
      other.statusWireValue == statusWireValue;

  @override
  int get hashCode => Object.hash(
      id, conversationId, roleWireValue, content, createdAt, statusWireValue);
}
