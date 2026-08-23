import '../domain/chat_message.dart';
import '../domain/chat_role.dart';
import 'llama_error.dart';

class FittedPrompt {
  const FittedPrompt({
    required this.includedHistory,
    required this.promptTokenCount,
    required this.droppedTurnCount,
  });

  final List<ChatMessage> includedHistory;
  final int promptTokenCount;
  final int droppedTurnCount;
}

/// Signature of the token counter injected into [TokenBudgetManager.fitHistory].
///
/// Injected rather than called directly so this whole class has no llama.cpp dependency and
/// can be tested with a deterministic fake counter.
typedef TokenCounter = int Function(String systemPrompt, List<ChatMessage> messages);

/// Trims a conversation down until it fits the model's context window.
class TokenBudgetManager {
  const TokenBudgetManager();

  /// Drops history from the oldest turn forward until
  /// `promptTokens + reservedOutputTokens + safetyMargin <= contextCapacity`.
  ///
  /// A turn is a user message and the assistant reply that follows it; both are always
  /// dropped together, because leaving an orphaned reply in the history teaches the model a
  /// conversation shape that never happened. A lone trailing user message with no reply —
  /// left behind by a failed generation — is dropped by itself, since it has no partner.
  ///
  /// Throws [LlamaError.promptTooLarge] when even the system prompt plus the current message
  /// alone cannot fit, which is the one case trimming cannot rescue.
  FittedPrompt fitHistory({
    required String systemPrompt,
    required List<ChatMessage> history,
    required ChatMessage currentUserMessage,
    required int contextCapacity,
    required int reservedOutputTokens,
    required int safetyMargin,
    required TokenCounter countTokens,
  }) {
    final candidateHistory = List<ChatMessage>.of(history);
    var droppedTurns = 0;
    final budget = contextCapacity - reservedOutputTokens - safetyMargin;

    while (true) {
      final tokenCount =
          countTokens(systemPrompt, [...candidateHistory, currentUserMessage]);

      if (tokenCount <= budget) {
        return FittedPrompt(
          includedHistory: List<ChatMessage>.unmodifiable(candidateHistory),
          promptTokenCount: tokenCount,
          droppedTurnCount: droppedTurns,
        );
      }

      final dropCount = oldestTurnLength(candidateHistory);
      if (dropCount == 0) {
        throw LlamaError.promptTooLarge(
          required: tokenCount,
          available: budget < 0 ? 0 : budget,
        );
      }

      candidateHistory.removeRange(0, dropCount);
      droppedTurns += 1;
    }
  }

  /// How many messages the oldest complete turn occupies: 2 for a (user, assistant) pair,
  /// 1 for a lone leading message, 0 when there is nothing left to drop.
  static int oldestTurnLength(List<ChatMessage> messages) {
    if (messages.isEmpty) return 0;
    if (messages.length >= 2 &&
        messages[0].role == ChatRole.user &&
        messages[1].role == ChatRole.assistant) {
      return 2;
    }
    return 1;
  }
}
