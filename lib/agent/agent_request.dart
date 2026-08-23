import '../domain/chat_message.dart';
import 'documents/local_document_reference.dart';

/// Web search availability for the active session, mirrored from `AppSettings`.
///
/// [AgentPermissions] is resolved by the chat view model before building an [AgentRequest] —
/// [AgentOrchestrator] never reads settings directly, which keeps it testable without a live
/// settings instance. The wire values are persisted in preferences, so they carry across from
/// the Swift app's `UserDefaults` unchanged.
enum WebSearchMode {
  off('off'),
  ask('ask'),
  automatic('automatic');

  const WebSearchMode(this.wireValue);

  final String wireValue;

  static WebSearchMode fromWireValue(String value) => WebSearchMode.values.firstWhere(
        (mode) => mode.wireValue == value,
        orElse: () => WebSearchMode.ask,
      );
}

/// What [AgentOrchestrator] is allowed to do for one request, resolved ahead of time by the
/// caller from user settings and any in-the-moment confirmation.
class AgentPermissions {
  const AgentPermissions({
    required this.webSearchMode,
    required this.webSearchApprovedForThisTurn,
    required this.allowFileSearch,
  });

  final WebSearchMode webSearchMode;

  /// Set when the user has already confirmed an "Ask"-gated web search for this specific turn,
  /// letting the orchestrator skip straight to searching instead of asking again.
  final bool webSearchApprovedForThisTurn;

  final bool allowFileSearch;

  /// No tool use permitted.
  static const AgentPermissions offlineOnly = AgentPermissions(
    webSearchMode: WebSearchMode.off,
    webSearchApprovedForThisTurn: false,
    allowFileSearch: false,
  );

  AgentPermissions copyWith({
    WebSearchMode? webSearchMode,
    bool? webSearchApprovedForThisTurn,
    bool? allowFileSearch,
  }) {
    return AgentPermissions(
      webSearchMode: webSearchMode ?? this.webSearchMode,
      webSearchApprovedForThisTurn:
          webSearchApprovedForThisTurn ?? this.webSearchApprovedForThisTurn,
      allowFileSearch: allowFileSearch ?? this.allowFileSearch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentPermissions &&
      other.webSearchMode == webSearchMode &&
      other.webSearchApprovedForThisTurn == webSearchApprovedForThisTurn &&
      other.allowFileSearch == allowFileSearch;

  @override
  int get hashCode =>
      Object.hash(webSearchMode, webSearchApprovedForThisTurn, allowFileSearch);
}

/// One user turn handed to [AgentOrchestrator].
///
/// [recentMessages] uses the exact same contract `ChatEngine.generate` already relies on: full
/// conversation history with the current user message as the last element. It is not trimmed
/// here — only the engine can count tokens with the model's real tokenizer.
class AgentRequest {
  const AgentRequest({
    required this.userMessage,
    required this.conversationId,
    required this.recentMessages,
    required this.attachedDocuments,
    required this.permissions,
  });

  final String userMessage;
  final String? conversationId;
  final List<ChatMessage> recentMessages;
  final List<LocalDocumentReference> attachedDocuments;
  final AgentPermissions permissions;

  AgentRequest copyWith({
    String? userMessage,
    String? conversationId,
    List<ChatMessage>? recentMessages,
    List<LocalDocumentReference>? attachedDocuments,
    AgentPermissions? permissions,
  }) {
    return AgentRequest(
      userMessage: userMessage ?? this.userMessage,
      conversationId: conversationId ?? this.conversationId,
      recentMessages: recentMessages ?? this.recentMessages,
      attachedDocuments: attachedDocuments ?? this.attachedDocuments,
      permissions: permissions ?? this.permissions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AgentRequest) return false;
    if (other.userMessage != userMessage ||
        other.conversationId != conversationId ||
        other.permissions != permissions ||
        other.recentMessages.length != recentMessages.length ||
        other.attachedDocuments.length != attachedDocuments.length) {
      return false;
    }
    for (var index = 0; index < recentMessages.length; index++) {
      if (other.recentMessages[index] != recentMessages[index]) return false;
    }
    for (var index = 0; index < attachedDocuments.length; index++) {
      if (other.attachedDocuments[index] != attachedDocuments[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        userMessage,
        conversationId,
        Object.hashAll(recentMessages),
        Object.hashAll(attachedDocuments),
        permissions,
      );
}
