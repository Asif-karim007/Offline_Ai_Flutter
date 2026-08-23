import 'chat_role.dart';

enum MessageStatus {
  generating('generating'),
  complete('complete'),
  stopped('stopped'),
  failed('failed');

  const MessageStatus(this.wireValue);

  final String wireValue;

  static MessageStatus fromWireValue(String value) {
    return MessageStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse: () => MessageStatus.complete,
    );
  }
}

/// An immutable chat message, used across the engine, view models and views.
///
/// Distinct from the persistence representation in `lib/persistence/` — this one is a plain
/// value, safe to send across an isolate boundary, and never carries a database identity.
///
/// Mutation goes through [copyWith] rather than settable fields. Token streaming rebuilds
/// the message on every chunk, and an immutable value makes it impossible for a stale
/// reference held by a widget to observe a half-updated message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.complete,
    this.errorDescription,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? errorDescription;

  bool get isStreaming => status == MessageStatus.generating;

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    String? errorDescription,
    bool clearErrorDescription = false,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      status: status ?? this.status,
      errorDescription:
          clearErrorDescription ? null : (errorDescription ?? this.errorDescription),
    );
  }

  /// Appends a streamed chunk. Separate from [copyWith] because it is the hot path — one
  /// call per token — and reads better at the call site than `copyWith(content: a + b)`.
  ChatMessage appending(String chunk) => copyWith(content: content + chunk);

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.role == role &&
      other.content == content &&
      other.createdAt == createdAt &&
      other.status == status &&
      other.errorDescription == errorDescription;

  @override
  int get hashCode => Object.hash(id, role, content, createdAt, status, errorDescription);

  /// The plain-map form used to hand messages to the inference isolate.
  ///
  /// Dart can send most objects across isolates directly, but a map keeps the boundary
  /// explicit and stable — the worker never has to be recompiled against a changed class.
  Map<String, Object?> toIsolateMap() => {
        'id': id,
        'role': role.wireValue,
        'content': content,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'status': status.wireValue,
        'errorDescription': errorDescription,
      };

  static ChatMessage fromIsolateMap(Map<String, Object?> map) => ChatMessage(
        id: map['id']! as String,
        role: ChatRole.fromWireValue(map['role']! as String),
        content: map['content']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']! as int),
        status: MessageStatus.fromWireValue(map['status']! as String),
        errorDescription: map['errorDescription'] as String?,
      );
}
