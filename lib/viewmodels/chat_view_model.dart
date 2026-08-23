import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent_event.dart';
import '../agent/agent_orchestrator.dart';
import '../agent/agent_request.dart';
import '../agent/documents/local_document_manager.dart';
import '../agent/documents/local_document_reference.dart';
import '../agent/response_provenance.dart';
import '../domain/chat_message.dart';
import '../domain/chat_role.dart';
import '../domain/chat_session_mode.dart';
import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';
import '../llm/chat_engine.dart';
import '../model_management/app_settings.dart';
import '../persistence/conversation.dart';
import '../persistence/conversation_repository.dart';
import '../utilities/conversation_title_generator.dart';
import 'error_text.dart';

/// Where the chat screen is in one turn.
///
/// `preparing` and `failed` are declared but never assigned, exactly as in the Swift
/// original. They are kept so the two enums can be diffed case for case.
sealed class ChatGenerationState {
  const ChatGenerationState();

  static const ChatGenerationState idle = _Idle();
  static const ChatGenerationState preparing = _Preparing();
  static const ChatGenerationState generating = _Generating();
  static const ChatGenerationState stopping = _Stopping();

  const factory ChatGenerationState.failed(String message) = FailedGeneration;

  bool get isBusy => this is _Preparing || this is _Generating || this is _Stopping;
}

final class _Idle extends ChatGenerationState {
  const _Idle();
}

final class _Preparing extends ChatGenerationState {
  const _Preparing();
}

final class _Generating extends ChatGenerationState {
  const _Generating();
}

final class _Stopping extends ChatGenerationState {
  const _Stopping();
}

final class FailedGeneration extends ChatGenerationState {
  const FailedGeneration(this.message);

  final String message;

  @override
  bool operator ==(Object other) => other is FailedGeneration && other.message == message;

  @override
  int get hashCode => Object.hash('failedGeneration', message);
}

/// The request, configuration and identities needed to re-run one turn after the user has
/// answered the "Search the web for …?" prompt.
class _PendingWebSearchConfirmation {
  const _PendingWebSearchConfirmation({
    required this.request,
    required this.configuration,
    required this.assistantMessageId,
    required this.conversationId,
  });

  final AgentRequest request;
  final GenerationConfiguration configuration;
  final String assistantMessageId;
  final String? conversationId;
}

/// The chat screen's whole state machine: session lifecycle, sending, streaming, stopping,
/// document attachment and the ask-gated web-search round trip.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required ChatEngine chatEngine,
    required AgentOrchestrator agentOrchestrator,
    required LocalDocumentManager documentManager,
    required ConversationRepository repository,
    required AppSettings settings,
    bool isModelReady = true,
    this.onConversationsChanged,
  })  : _chatEngine = chatEngine,
        _agentOrchestrator = agentOrchestrator,
        _documentManager = documentManager,
        _repository = repository,
        _settings = settings,
        _isModelReady = isModelReady;

  final ChatEngine _chatEngine;
  final AgentOrchestrator _agentOrchestrator;
  final LocalDocumentManager _documentManager;
  final ConversationRepository _repository;
  final AppSettings _settings;

  /// Fired after this view model has written to the conversation store.
  ///
  /// **New in the port, and structural rather than cosmetic.** SwiftData's `@Query` gave the
  /// sidebar a live, self-updating list, so nothing had to tell it that a conversation had
  /// been created, saved to or touched. `ConversationRepository` exposes a plain
  /// `fetchAllSummaries()` future and no change stream, so the sidebar has to be told. This
  /// is the notification; `MainSplitView` wires it to `SidebarViewModel.refresh()`.
  final VoidCallback? onConversationsChanged;

  // --- observable state -------------------------------------------------------------------

  List<ChatMessage> _messages = const [];
  ChatSessionMode _sessionMode = const ChatSessionMode.persistent();
  ChatGenerationState _generationState = ChatGenerationState.idle;
  String? _conversationTitle;
  String _composerText = '';
  String? _errorMessage;
  GenerationMetrics _lastMetrics = GenerationMetrics.empty;
  String? _activityStatus;
  Map<String, ResponseProvenance> _currentProvenance = const {};
  List<LocalDocumentReference> _attachedDocuments = const [];
  String? _pendingWebSearchQuery;
  bool _isModelReady;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  ChatSessionMode get sessionMode => _sessionMode;

  ChatGenerationState get generationState => _generationState;

  String? get conversationTitle => _conversationTitle;

  set conversationTitle(String? value) {
    if (_conversationTitle == value) {
      return;
    }
    _conversationTitle = value;
    _notify();
  }

  /// Two-way bound to the composer's text field.
  String get composerText => _composerText;

  set composerText(String value) {
    if (_composerText == value) {
      return;
    }
    _composerText = value;
    _notify();
  }

  String? get errorMessage => _errorMessage;

  set errorMessage(String? value) {
    if (_errorMessage == value) {
      return;
    }
    _errorMessage = value;
    _notify();
  }

  GenerationMetrics get lastMetrics => _lastMetrics;

  /// Transient "Thinking…" / "Searching the web…" status from the active agent pipeline.
  /// Never persisted; cleared once token streaming begins or generation ends.
  String? get activityStatus => _activityStatus;

  /// What actually produced each assistant answer, keyed by assistant message id. Drives the
  /// provenance badge — never derived from the model's own text. Session-display metadata
  /// only, never written to the database alongside a message.
  Map<String, ResponseProvenance> get currentProvenance =>
      Map.unmodifiable(_currentProvenance);

  List<LocalDocumentReference> get attachedDocuments =>
      List.unmodifiable(_attachedDocuments);

  /// Non-null while waiting on the user to approve or decline a web search gated by
  /// `AppSettings.webSearchMode == WebSearchMode.ask`.
  String? get pendingWebSearchQuery => _pendingWebSearchQuery;

  bool get isModelReady => _isModelReady;

  set isModelReady(bool value) {
    if (_isModelReady == value) {
      return;
    }
    _isModelReady = value;
    _notify();
  }

  bool get isTemporary => _sessionMode.isTemporary;

  bool get canSend =>
      _composerText.trim().isNotEmpty && !_generationState.isBusy && _isModelReady;

  /// One message by id, or `null` when it is no longer in the transcript.
  ///
  /// The message list is addressed by id rather than by index everywhere above this class so
  /// that a single streaming bubble can rebuild without the rest of the list rebuilding
  /// with it.
  ChatMessage? messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
  }

  ResponseProvenance provenanceFor(String messageId) =>
      _currentProvenance[messageId] ?? ResponseProvenance.empty;

  // --- private, non-observable state ------------------------------------------------------

  /// A turn can outlive the widget tree that started it — the stream is only asked to stop in
  /// [dispose], and its unwind lands a frame or two later. Notifying a disposed
  /// [ChangeNotifier] throws, so every notification in this class goes through here.
  bool _disposed = false;

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void>? _generationFuture;
  StreamSubscription<AgentEvent>? _generationSubscription;
  Completer<void>? _generationCompleter;
  bool _cancelRequested = false;
  _PendingWebSearchConfirmation? _pendingWebSearchConfirmation;

  // --- session lifecycle --------------------------------------------------------------

  Future<void> startNewPersistentChat() async {
    // Order matters: the old generation has to be gone before the KV cache is cleared, or a
    // decode in flight would run against a context that has been reset underneath it.
    await _cancelActiveGenerationAndWait();
    await _chatEngine.resetConversation();
    await _agentOrchestrator.resetSession();
    _composerText = '';
    _errorMessage = null;
    _messages = const [];
    _currentProvenance = const {};
    _attachedDocuments = const [];
    _pendingWebSearchQuery = null;
    _pendingWebSearchConfirmation = null;
    _conversationTitle = null;
    _sessionMode = const ChatSessionMode.persistent();
    _notify();
  }

  Future<void> startTemporaryChat() async {
    await _cancelActiveGenerationAndWait();
    await _chatEngine.resetConversation();
    await _agentOrchestrator.resetSession();
    _composerText = '';
    _errorMessage = null;
    _messages = const [];
    _currentProvenance = const {};
    _attachedDocuments = const [];
    _pendingWebSearchQuery = null;
    _pendingWebSearchConfirmation = null;
    _conversationTitle = 'Temporary Chat';
    _sessionMode = const ChatSessionMode.temporary();
    _notify();
  }

  /// True when the caller should show the "End Temporary Chat?" confirmation before
  /// destroying the current session.
  bool temporaryChatNeedsDiscardConfirmation() => isTemporary && _messages.isNotEmpty;

  Future<void> discardTemporaryChat() => startNewPersistentChat();

  Future<void> loadConversation({required String id, required String title}) async {
    await _cancelActiveGenerationAndWait();
    await _chatEngine.resetConversation();
    await _agentOrchestrator.resetSession();
    _errorMessage = null;
    _composerText = '';
    _currentProvenance = const {};
    _attachedDocuments = const [];
    _pendingWebSearchQuery = null;
    _pendingWebSearchConfirmation = null;
    _notify();

    try {
      _messages = await _repository.fetchMessages(id);
      _conversationTitle = title;
      _sessionMode = ChatSessionMode.persistent(conversationId: id);
    } on Object catch (error) {
      // Left half-reset on failure, as in the original: messages stay empty and the session
      // mode is unchanged, so the user sees an empty screen plus the error rather than a
      // transcript belonging to the conversation they navigated away from.
      _errorMessage = describeError(error);
    }
    _notify();
  }

  // --- sending ------------------------------------------------------------------------

  /// Sends [overrideText] when given (the suggestion chips), otherwise the composer's
  /// contents.
  ///
  /// Returns only once the whole turn has finished, matching the Swift `send()` which awaited
  /// the generation task's value.
  Future<void> send({String? overrideText}) async {
    final text = (overrideText ?? _composerText).trim();
    if (text.isEmpty || _generationState.isBusy || !_isModelReady) {
      return;
    }

    _errorMessage = null;
    // Cleared immediately, before any await. On the conversation-create failure path below
    // this means the user's typed text is gone — a real rough edge, preserved rather than
    // quietly changed so the two apps behave identically.
    _composerText = '';
    _notify();

    var conversationId = _sessionMode.conversationId;

    if (_sessionMode is PersistentSession && conversationId == null) {
      final newId = Conversation.newId();
      final title = ConversationTitleGenerator.titleFromFirstMessage(text);
      try {
        await _repository.createConversation(
          id: newId,
          title: title,
          createdAt: DateTime.now(),
        );
        conversationId = newId;
        _conversationTitle = title;
        _sessionMode = ChatSessionMode.persistent(conversationId: newId);
        onConversationsChanged?.call();
      } on Object catch (error) {
        _errorMessage = describeError(error);
        _notify();
        return;
      }
    }

    final userMessage = ChatMessage(
      id: Conversation.newId(),
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    );
    _messages = [..._messages, userMessage];
    _notify();

    if (conversationId != null) {
      // Errors deliberately swallowed: a failed write must not cost the user the turn they
      // are in the middle of, and the message is already on screen.
      try {
        await _repository.saveMessage(userMessage, conversationId: conversationId);
        await _repository.touchConversation(
          id: conversationId,
          updatedAt: DateTime.now(),
        );
      } on Object {
        // Intentionally ignored — see above.
      }
      onConversationsChanged?.call();
    }

    // `_messages` now ends with the just-appended user message and carries no assistant
    // placeholder, which is exactly the contract `AgentRequest.recentMessages` and
    // `ChatEngine.generate(messages:)` expect.
    final configuration = _settings.currentGenerationConfiguration();
    final request = AgentRequest(
      userMessage: text,
      conversationId: conversationId,
      recentMessages: _messages,
      attachedDocuments: _attachedDocuments,
      permissions: _currentPermissions(),
    );

    await _resumeGeneration(
      request: request,
      configuration: configuration,
      assistantMessageId: Conversation.newId(),
      conversationId: conversationId,
    );
  }

  AgentPermissions _currentPermissions({bool webSearchApprovedForThisTurn = false}) {
    return AgentPermissions(
      webSearchMode: _settings.webSearchMode,
      webSearchApprovedForThisTurn: webSearchApprovedForThisTurn,
      allowFileSearch: _attachedDocuments.isNotEmpty,
    );
  }

  /// Appends a fresh assistant placeholder for [assistantMessageId] and runs the turn.
  ///
  /// Shared by [send] and by the confirm/decline paths, which re-run the same pipeline with
  /// different permissions after the empty placeholder was removed — reusing the id keeps the
  /// bubble's list identity stable across the round trip.
  Future<void> _resumeGeneration({
    required AgentRequest request,
    required GenerationConfiguration configuration,
    required String assistantMessageId,
    required String? conversationId,
  }) async {
    final placeholder = ChatMessage(
      id: assistantMessageId,
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.generating,
    );
    _messages = [..._messages, placeholder];
    _generationState = ChatGenerationState.generating;
    _notify();

    final future = _runGeneration(
      request: request,
      configuration: configuration,
      assistantMessageId: assistantMessageId,
      conversationId: conversationId,
    );
    _generationFuture = future;
    await future;
  }

  // --- the streaming loop ---------------------------------------------------------------

  /// One turn, start to finish.
  ///
  /// The token-flush throttle — flush once 12 characters have accumulated *or* 80 ms have
  /// passed — is copied from the Swift original and is load-bearing. Rebuilding the streaming
  /// bubble on every single token is measurably slower than the model can produce them.
  Future<void> _runGeneration({
    required AgentRequest request,
    required GenerationConfiguration configuration,
    required String assistantMessageId,
    required String? conversationId,
  }) async {
    var pendingText = '';
    var lastFlush = DateTime.now();

    void flushPending() {
      if (pendingText.isEmpty) {
        return;
      }
      _appendToAssistantMessage(assistantMessageId, pendingText);
      pendingText = '';
      lastFlush = DateTime.now();
    }

    _cancelRequested = false;
    _activityStatus = null;
    _notify();

    final completer = Completer<void>();
    _generationCompleter = completer;
    var completedNormally = false;
    // The completed event's persistence is started inside the listener but awaited in the
    // tail. Leaving it unawaited would let `startNewPersistentChat` clear `_messages` out
    // from under it, and the answer would silently never reach the database.
    Future<void>? persistence;

    void setActivity(String? status) {
      if (_activityStatus == status) {
        return;
      }
      _activityStatus = status;
      _notify();
    }

    final subscription = _agentOrchestrator
        .handle(request, configuration: configuration)
        .listen(
      (event) {
        // Swift re-checked `Task.isCancelled` at the top of every loop iteration; the same
        // check, at the same point.
        if (_cancelRequested && _generationState != ChatGenerationState.stopping) {
          _generationState = ChatGenerationState.stopping;
          _notify();
        }

        switch (event) {
          case AgentRoutingEvent():
          case AgentGeneratingEvent():
            setActivity(null);
          case AgentPlanningEvent():
            setActivity('Thinking…');
          case AgentSearchingWebEvent():
            setActivity('Searching the web…');
          case AgentReadingDocumentsEvent():
            setActivity('Searching documents…');
          case AgentNeedsWebSearchConfirmationEvent(:final query):
            _activityStatus = null;
            _pendingWebSearchQuery = query;
            _pendingWebSearchConfirmation = _PendingWebSearchConfirmation(
              request: request,
              configuration: configuration,
              assistantMessageId: assistantMessageId,
              conversationId: conversationId,
            );
            // No answer was produced — remove the empty placeholder rather than leaving a
            // blank assistant bubble sitting there while the user decides.
            _messages = _messages
                .where((message) => message.id != assistantMessageId)
                .toList(growable: false);
            _notify();
          case AgentTokenEvent(:final text):
            _activityStatus = null;
            pendingText += text;
            final now = DateTime.now();
            if (pendingText.length >= _flushCharacterThreshold ||
                now.difference(lastFlush) >= _flushInterval) {
              flushPending();
            }
          case AgentProvenanceUpdatedEvent(:final provenance):
            _currentProvenance = {
              ..._currentProvenance,
              assistantMessageId: provenance,
            };
            _notify();
          case AgentCompletedEvent(:final reason, :final metrics):
            completedNormally = true;
            flushPending();
            _lastMetrics = metrics;
            _finalizeAssistantMessage(assistantMessageId, reason);
            _notify();
            if (conversationId != null) {
              persistence = _persistAssistantMessageIfNeeded(
                assistantMessageId,
                conversationId: conversationId,
              );
            }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // An engine failure arrives here, as a stream error, not as an event.
        flushPending();
        _markAssistantMessageFailed(assistantMessageId, error);
        _errorMessage = describeError(error);
        _notify();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );
    _generationSubscription = subscription;

    await completer.future;

    // A cancelled subscription never delivers the orchestrator's own cancelled-completion
    // event — or any further event at all — so the turn is finalised here instead. Swift got
    // that event because Task cancellation did not tear the stream down mid-flight.
    if (_cancelRequested && !completedNormally) {
      flushPending();
      _finalizeAssistantMessage(assistantMessageId, GenerationFinishReason.cancelled);
      if (conversationId != null) {
        persistence = _persistAssistantMessageIfNeeded(
          assistantMessageId,
          conversationId: conversationId,
        );
      }
    }

    await persistence;
    await subscription.cancel();
    _generationSubscription = null;
    _generationCompleter = null;
    _activityStatus = null;
    _generationState = ChatGenerationState.idle;
    _generationFuture = null;
    _cancelRequested = false;
    _notify();
  }

  /// Flush once this many characters have queued.
  static const int _flushCharacterThreshold = 12;

  /// …or once this long has passed since the last flush, whichever comes first.
  static const Duration _flushInterval = Duration(milliseconds: 80);

  /// Stops the turn in progress.
  ///
  /// Guarded on exact equality with `generating`, as in the original — which is also why the
  /// composer's stop affordance disappears again while `stopping` is still in flight.
  void stopGeneration() {
    if (_generationState != ChatGenerationState.generating) {
      return;
    }
    _generationState = ChatGenerationState.stopping;
    _cancelRequested = true;
    _notify();
    unawaited(_tearDownGeneration());
  }

  /// Cancels the subscription — which stops native decoding within one token — and releases
  /// the awaiting `_runGeneration`.
  Future<void> _tearDownGeneration() async {
    final subscription = _generationSubscription;
    _generationSubscription = null;
    await subscription?.cancel();
    final completer = _generationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Cancels any active turn and waits for it to unwind, so a new session never races the
  /// old stream.
  Future<void> _cancelActiveGenerationAndWait() async {
    final future = _generationFuture;
    if (future == null) {
      return;
    }
    _cancelRequested = true;
    await _tearDownGeneration();
    await future;
    _generationFuture = null;
    _generationState = ChatGenerationState.idle;
    _cancelRequested = false;
  }

  // --- web search confirmation ----------------------------------------------------------

  Future<void> confirmPendingWebSearch() async {
    final pending = _pendingWebSearchConfirmation;
    if (pending == null) {
      return;
    }
    _pendingWebSearchConfirmation = null;
    _pendingWebSearchQuery = null;
    _notify();

    final approved = pending.request.copyWith(
      permissions: pending.request.permissions.copyWith(
        webSearchApprovedForThisTurn: true,
      ),
    );
    await _resumeGeneration(
      request: approved,
      configuration: pending.configuration,
      assistantMessageId: pending.assistantMessageId,
      conversationId: pending.conversationId,
    );
  }

  Future<void> declinePendingWebSearch() async {
    final pending = _pendingWebSearchConfirmation;
    if (pending == null) {
      return;
    }
    _pendingWebSearchConfirmation = null;
    _pendingWebSearchQuery = null;
    _notify();

    // The same turn re-run with web access switched off entirely. File search is preserved:
    // declining a web lookup is not a statement about the documents the user attached.
    final localOnly = pending.request.copyWith(
      permissions: AgentPermissions(
        webSearchMode: WebSearchMode.off,
        webSearchApprovedForThisTurn: false,
        allowFileSearch: pending.request.permissions.allowFileSearch,
      ),
    );
    await _resumeGeneration(
      request: localOnly,
      configuration: pending.configuration,
      assistantMessageId: pending.assistantMessageId,
      conversationId: pending.conversationId,
    );
  }

  // --- session documents ------------------------------------------------------------------

  Future<void> addDocument(String path) async {
    try {
      await _documentManager.addDocument(Uri.file(path));
      _attachedDocuments = _documentManager.references;
    } on Object catch (error) {
      _errorMessage = describeError(error);
    }
    _notify();
  }

  Future<void> removeDocument(String id) async {
    await _documentManager.removeDocument(id);
    _attachedDocuments = _documentManager.references;
    _notify();
  }

  // --- message mutation helpers -----------------------------------------------------------

  /// No-op when the message is gone — which is the normal case after the placeholder was
  /// removed for a web-search confirmation.
  void _appendToAssistantMessage(String id, String text) {
    final index = _indexOf(id);
    if (index == null) {
      return;
    }
    final updated = List<ChatMessage>.of(_messages);
    updated[index] = updated[index].appending(text);
    _messages = updated;
    _notify();
  }

  void _finalizeAssistantMessage(String id, GenerationFinishReason reason) {
    final index = _indexOf(id);
    if (index == null) {
      return;
    }
    final status = switch (reason) {
      GenerationFinishReason.endOfSequence ||
      GenerationFinishReason.maxTokensReached =>
        MessageStatus.complete,
      GenerationFinishReason.cancelled => MessageStatus.stopped,
    };
    final updated = List<ChatMessage>.of(_messages);
    updated[index] = updated[index].copyWith(status: status);
    _messages = updated;
  }

  /// A failure with no text at all is a failure the user needs told about. A failure that
  /// interrupted a partial answer is reported as a stop instead, and the partial text kept —
  /// showing an error under half an answer reads as if the answer itself were wrong.
  void _markAssistantMessageFailed(String id, Object error) {
    final index = _indexOf(id);
    if (index == null) {
      return;
    }
    final updated = List<ChatMessage>.of(_messages);
    final message = updated[index];
    updated[index] = message.content.isEmpty
        ? message.copyWith(
            status: MessageStatus.failed,
            errorDescription: describeError(error),
          )
        : message.copyWith(status: MessageStatus.stopped);
    _messages = updated;
  }

  Future<void> _persistAssistantMessageIfNeeded(
    String id, {
    required String conversationId,
  }) async {
    final index = _indexOf(id);
    if (index == null) {
      return;
    }
    final message = _messages[index];
    // An empty assistant message carries nothing worth restoring on reload.
    if (message.content.isEmpty) {
      return;
    }
    try {
      await _repository.saveMessage(message, conversationId: conversationId);
      await _repository.touchConversation(
        id: conversationId,
        updatedAt: DateTime.now(),
      );
    } on Object {
      // Swallowed, as in the original.
    }
    onConversationsChanged?.call();
  }

  int? _indexOf(String id) {
    for (var index = 0; index < _messages.length; index++) {
      if (_messages[index].id == id) {
        return index;
      }
    }
    return null;
  }

  // --- message actions ----------------------------------------------------------------

  String copyText(ChatMessage message) => message.content;

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    unawaited(_tearDownGeneration());
    super.dispose();
  }
}
