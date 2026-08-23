import '../domain/chat_message.dart';

/// Assembles the role-ordered message list handed to the chat-template formatter.
///
/// Pure logic with no native dependency, so it is directly unit testable.
class PromptBuilder {
  const PromptBuilder();

  /// The system prompt is synthesised as the first entry every time. It is never stored as a
  /// [ChatMessage], never persisted, and never rendered as a bubble — which is why it is
  /// built here rather than being prepended to the conversation somewhere upstream.
  List<({String role, String content})> messageList({
    required String systemPrompt,
    required List<ChatMessage> history,
    required ChatMessage currentUserMessage,
  }) {
    return <({String role, String content})>[
      (role: 'system', content: systemPrompt),
      for (final message in history)
        (role: message.role.wireValue, content: message.content),
      (role: currentUserMessage.role.wireValue, content: currentUserMessage.content),
    ];
  }
}
