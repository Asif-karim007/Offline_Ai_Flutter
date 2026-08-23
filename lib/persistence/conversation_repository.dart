import '../domain/chat_message.dart';
import 'conversation.dart';

/// Why a repository call failed for a reason that is not a database fault.
///
/// The Swift original had exactly one case, nested in the SwiftData implementation. It is
/// promoted to the interface here because it is part of the contract, not an implementation
/// detail: `saveMessage` is the one method that throws on a missing conversation, and a
/// caller has to be able to catch that without knowing which backend it is talking to.
/// Everything that is genuinely a storage failure is thrown as `LlamaError` with
/// `LlamaErrorKind.databaseSaveFailed`, exactly as the Swift `save()` helper did.
enum RepositoryErrorKind { conversationNotFound }

class RepositoryException implements Exception {
  const RepositoryException(this.kind, {this.conversationId});

  final RepositoryErrorKind kind;
  final String? conversationId;

  @override
  String toString() => 'RepositoryException.${kind.name}($conversationId)';
}

/// The persistence boundary for saved (non-temporary) conversations.
///
/// Accepts and returns only immutable value types — never a database row handle, never a
/// live object. The Swift protocol enforced this so a `@MainActor` view model could never
/// touch a `ModelContext` belonging to another actor; the same rule is kept here for a
/// different but equally real reason: sqflite work belongs off the UI's critical path, and
/// values are what can cross that boundary safely.
///
/// Temporary chats never reach this interface at all. That is enforced at the call site by
/// `ChatSessionMode.isTemporary`, not here — the repository has no notion of a session.
abstract interface class ConversationRepository {
  /// Creates the conversation row.
  ///
  /// `updatedAt` is seeded with [createdAt] rather than with "now", so a conversation that
  /// is created and never written to sorts by its creation time in the sidebar instead of
  /// by the instant the row happened to be inserted.
  Future<void> createConversation({
    required String id,
    required String title,
    required DateTime createdAt,
  });

  /// Writes one message.
  ///
  /// Throws [RepositoryException] with [RepositoryErrorKind.conversationNotFound] when the
  /// parent row is missing — the only lookup in this interface that treats "not found" as an
  /// error rather than a no-op, because a message with no conversation is data loss, while a
  /// rename of a deleted conversation is merely late.
  ///
  /// Saving the same message id twice replaces the existing row. Streaming a response means
  /// the final content of a message is not known when its id is minted, and retry paths can
  /// legitimately re-save.
  Future<void> saveMessage(ChatMessage message, {required String conversationId});

  /// Silently does nothing when the conversation is missing.
  Future<void> touchConversation({required String id, required DateTime updatedAt});

  /// Silently does nothing when the conversation is missing.
  Future<void> renameConversation({required String id, required String title});

  /// Silently does nothing when the conversation is missing. Cascades to its messages.
  Future<void> deleteConversation(String id);

  Future<void> deleteAllConversations();

  /// Ascending by `createdAt`. Empty when the conversation does not exist — a missing
  /// conversation and an empty one are indistinguishable to the caller, matching Swift.
  Future<List<ChatMessage>> fetchMessages(String conversationId);

  /// Newest activity first, ordered by `updatedAt` descending.
  Future<List<ConversationSummary>> fetchAllSummaries();
}
