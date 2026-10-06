import 'dart:async';
import 'dart:developer' as developer;

import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';
import '../l10n/app_strings.dart';
import '../llm/chat_engine.dart';
import 'agent_decision.dart';
import 'agent_event.dart';
import 'agent_planner.dart';
import 'agent_request.dart';
import 'agent_router.dart';
import 'context_assembler.dart';
import 'context_budget.dart';
import 'curriculum/textbook_retriever.dart';
import 'device_context_tool.dart';
import 'documents/document_chunk.dart';
import 'documents/local_document_manager.dart';
import 'evidence_requirement.dart';
import 'memory/session_memory_manager.dart';
import 'response_provenance.dart';
import 'source_reference.dart';
import 'thinking_content_filter.dart';
import 'token_estimator.dart';
import 'web/retrieved_web_chunk.dart';
import 'web/search_query_builder.dart';
import 'web/web_search_provider.dart';
import 'web/web_search_service.dart';

/// Why a web-requiring route could not be answered with real evidence.
///
/// Drives [_webEvidenceUnavailableMessage], which is deliberately a fixed, model-free string
/// with no topic-specific content — so it can never itself become a hardcoded factual answer for
/// any particular query.
enum _WebEvidenceUnavailableReason {
  /// Web access was not available for this turn at all (not configured, mode off, or an explicit
  /// user restriction). Retrieval was never attempted.
  notAllowed,

  /// Web access was allowed and attempted, but returned no usable evidence — empty results or a
  /// caught error. Which one is in the `[Web] searchFailed` log.
  retrievalFailed,
}

/// Cooperative cancellation for one in-flight request. Replaces Swift's `Task.isCancelled`,
/// checked at the same points, and carries the engine subscription so cancelling the consumer's
/// subscription stops native decoding within a token rather than at the next checkpoint.
class _Cancellation {
  bool isCancelled = false;
  StreamSubscription<GenerationEvent>? engineSubscription;

  /// Completed by [cancel] as well as by the engine stream itself. Without this, cancelling a
  /// subscription mid-generation would leave the pipeline waiting on an `onDone` that a
  /// cancelled stream never delivers, and the request's future would never finish.
  Completer<void>? generationCompleter;

  Future<void> cancel() async {
    isCancelled = true;
    final subscription = engineSubscription;
    engineSubscription = null;
    await subscription?.cancel();
    final completer = generationCompleter;
    generationCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}

/// Coordinates one user request through a bounded, single-round pipeline: authoritative
/// deterministic routing → an optional structured planner call for genuinely ambiguous cases →
/// at most one retrieval round (device context, local documents, and/or web) → final local
/// generation with reasoning stripped from the visible stream.
///
/// There is no recursive think/search loop. At most one planning round and one retrieval round
/// ever happen before the final answer.
///
/// This is a client of [ChatEngine] exactly as the chat view model is: it never touches
/// persistence, and it never issues two native generation calls concurrently, so it adds no
/// isolation risk on top of the engine's existing serialisation. Every capability except web
/// search — memory, local document RAG, device context, local reasoning — works fully offline.
class AgentOrchestrator {
  AgentOrchestrator({
    required ChatEngine chatEngine,
    required LocalDocumentManager documentManager,
    required Future<WebSearchService?> Function() webSearchServiceProvider,
    TextbookRetriever? textbookRetriever,
  })  : _chatEngine = chatEngine,
        _documentManager = documentManager,
        _webSearchServiceProvider = webSearchServiceProvider,
        _textbookRetriever = textbookRetriever,
        _planner = AgentPlanner(chatEngine: chatEngine),
        _sessionMemory = SessionMemoryManager(chatEngine: chatEngine);

  /// Convenience constructor for callers — mainly tests — that already hold a fixed service and
  /// do not need per-request reactivity.
  AgentOrchestrator.withService({
    required ChatEngine chatEngine,
    required LocalDocumentManager documentManager,
    WebSearchService? webSearchService,
  }) : this(
          chatEngine: chatEngine,
          documentManager: documentManager,
          webSearchServiceProvider: (() async => webSearchService),
        );

  final ChatEngine _chatEngine;
  final LocalDocumentManager _documentManager;

  /// Re-invoked fresh on every request rather than captured once. If this were a stored
  /// `WebSearchService?`, configuring or changing the search API key in Settings after launch
  /// would never take effect until the app fully restarted, since the orchestrator is
  /// constructed exactly once at launch.
  final Future<WebSearchService?> Function() _webSearchServiceProvider;

  /// The student's curriculum pack. Searched on every question that is not about current
  /// events, the clock or the web — i.e. on every ordinary study question.
  final TextbookRetriever? _textbookRetriever;

  final AgentRouter _router = const AgentRouter();
  final AgentPlanner _planner;
  final SessionMemoryManager _sessionMemory;
  final ContextAssembler _contextAssembler = const ContextAssembler();

  /// The previous turn's memory compaction, while it is still running. Held so the next turn can
  /// wait for it instead of issuing a second, overlapping generation call.
  Future<void>? _compactionInFlight;

  /// Clears session-scoped agent state: session memory and the document index. Called alongside
  /// `ChatEngine.resetConversation()` whenever the app starts a new chat, starts a temporary
  /// chat, or loads a different conversation.
  Future<void> resetSession() async {
    // Let any in-flight compaction finish before the memory it is writing into is discarded, and
    // before the caller's `ChatEngine.resetConversation()` runs — it is a live engine call.
    if (_compactionInFlight != null) await _compactionInFlight;
    _compactionInFlight = null;
    _sessionMemory.reset();
    await _documentManager.clearSession();
  }

  /// Runs one request. Single-subscription: work starts when the returned stream is listened to
  /// and stops when the subscription is cancelled.
  Stream<AgentEvent> handle(
    AgentRequest request, {
    required GenerationConfiguration configuration,
  }) {
    final controller = StreamController<AgentEvent>();
    final cancellation = _Cancellation();

    controller.onListen = () {
      _run(request, configuration, controller, cancellation).then((_) {
        if (!controller.isClosed) controller.close();
      }).catchError((Object error, StackTrace stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          controller.close();
        }
      });
    };
    controller.onCancel = cancellation.cancel;

    return controller.stream;
  }

  Future<void> _run(
    AgentRequest request,
    GenerationConfiguration configuration,
    StreamController<AgentEvent> controller,
    _Cancellation cancellation,
  ) async {
    void emit(AgentEvent event) {
      if (!controller.isClosed) controller.add(event);
    }

    void finishCancelled() {
      emit(const AgentCompletedEvent(
        reason: GenerationFinishReason.cancelled,
        metrics: GenerationMetrics.empty,
      ));
      // Synchronous local function, so the close cannot be awaited here; it is still a Future
      // that nothing observes.
      if (!controller.isClosed) unawaited(controller.close());
    }

    // Compaction from the previous turn is a second engine call and the engine is
    // single-occupancy, so this turn waits for it rather than colliding with it.
    if (_compactionInFlight != null) await _compactionInFlight;

    emit(const AgentRoutingEvent());
    if (cancellation.isCancelled) {
      finishCancelled();
      return;
    }

    final route = _router.route(request);
    final AgentDecision decision;
    var plannerUsed = false;
    Duration? plannerDuration;

    if (route is DefiniteRoute) {
      // The router is authoritative here — the planner is never consulted, so an unreliable
      // small-model judgment cannot override an explicit instruction, a device-context
      // question, or a well-known freshness pattern.
      decision = route.decision;
    } else if (route is FastAnswerRoute) {
      decision = AgentDecision.fallbackAnswer(reason: 'fast_path');
    } else {
      emit(const AgentPlanningEvent());
      plannerUsed = true;
      final plannerStart = DateTime.now();
      decision = await _planner.decide(request: request, configuration: configuration);
      plannerDuration = DateTime.now().difference(plannerStart);
      if (cancellation.isCancelled) {
        finishCancelled();
        return;
      }
    }

    _logDecision(route: route, plannerUsed: plannerUsed, decision: decision);

    // Device-local date/time: answered deterministically, no LLM call and no network at all.
    if (decision.action == AgentAction.deviceContext) {
      if (cancellation.isCancelled) {
        finishCancelled();
        return;
      }
      emit(const AgentProvenanceUpdatedEvent(ResponseProvenance(
        usedWeb: false,
        usedDocuments: false,
        usedDeviceContext: true,
        sources: [],
      )));
      emit(const AgentGeneratingEvent());
      emit(AgentTokenEvent(DeviceContextTool.formattedAnswer(request.userMessage)));
      emit(const AgentCompletedEvent(
        reason: GenerationFinishReason.endOfSequence,
        metrics: GenerationMetrics.empty,
      ));
      if (!controller.isClosed) await controller.close();
      return;
    }

    // The route was forced away from web entirely (an explicit "don't use the internet"
    // restriction), but the question itself is a freshness question. Answering anyway risks
    // presenting a stale guess as fact, so give a deterministic, model-free refusal instead.
    // Scoped to the pure answer case so a mixed file-plus-restricted-web question still gets a
    // normal file-grounded answer with the transparency caveat rather than being refused.
    if (decision.action == AgentAction.answer && decision.needsCurrentInformation) {
      if (cancellation.isCancelled) {
        finishCancelled();
        return;
      }
      _log('[Provenance] usedWeb=false reason=explicitlyRestrictedButNeedsCurrentInfo');
      emit(const AgentProvenanceUpdatedEvent(ResponseProvenance.empty));
      emit(const AgentGeneratingEvent());
      emit(AgentTokenEvent(
          _webEvidenceUnavailableMessage(
              _WebEvidenceUnavailableReason.notAllowed, request.userMessage)));
      emit(const AgentCompletedEvent(
        reason: GenerationFinishReason.endOfSequence,
        metrics: GenerationMetrics.empty,
      ));
      if (!controller.isClosed) await controller.close();
      return;
    }

    final rawQuery =
        decision.query.trim().isEmpty ? request.userMessage : decision.query;
    final effectiveQuery = SearchQueryBuilder.minimalQuery(rawQuery);
    final evidenceRequirement = EvidenceRequirement.forAction(decision.action);

    final wantsWeb = evidenceRequirement.requiresWeb;
    final documentsAvailable = !_documentManager.isEmpty;
    final wantsFiles = evidenceRequirement.requiresDocuments &&
        request.permissions.allowFileSearch &&
        documentsAvailable;

    // "Ask" gate: never touch the network without an explicit per-turn confirmation. Note it
    // requires a configured service — with no provider this falls through to the refusal below
    // instead of asking the user to approve a search that could not happen.
    final webSearchService = await _webSearchServiceProvider();
    if (wantsWeb &&
        webSearchService != null &&
        request.permissions.webSearchMode == WebSearchMode.ask &&
        !request.permissions.webSearchApprovedForThisTurn) {
      emit(AgentNeedsWebSearchConfirmationEvent(effectiveQuery));
      // No completion event: the caller re-submits with approval granted.
      if (!controller.isClosed) await controller.close();
      return;
    }

    final webAllowed = webSearchService != null &&
        request.permissions.webSearchMode != WebSearchMode.off &&
        (request.permissions.webSearchMode == WebSearchMode.automatic ||
            request.permissions.webSearchApprovedForThisTurn);

    var documentChunks = <DocumentChunk>[];
    var webChunks = <RetrievedWebChunk>[];
    var textbookExcerpts = <TextbookExcerpt>[];
    Duration? searchDuration;
    Duration? documentRetrievalDuration;

    // Textbooks are consulted for every question except those that need *current*
    // information — a textbook is never the source for today's news — and those whose answer
    // must come from the web alone. The raw message is searched, not the web-minimised query:
    // the minimiser is tuned for search engines and drops words the keyword index needs.
    final textbookRetriever = _textbookRetriever;
    final wantsTextbooks = textbookRetriever != null &&
        !decision.needsCurrentInformation &&
        evidenceRequirement != EvidenceRequirement.webRequired;
    if (wantsTextbooks) {
      emit(const AgentSearchingTextbooksEvent());
      final start = DateTime.now();
      textbookExcerpts = List.of(await textbookRetriever.search(request.userMessage));
      documentRetrievalDuration = DateTime.now().difference(start);
      _log('[Textbook] excerpts=${textbookExcerpts.length}');
    }

    if (wantsFiles) {
      emit(const AgentReadingDocumentsEvent());
      final start = DateTime.now();
      documentChunks = await _documentManager.retrieveRelevantChunks(effectiveQuery);
      documentRetrievalDuration =
          (documentRetrievalDuration ?? Duration.zero) + DateTime.now().difference(start);
      _log('[Retrieval] usableChunks=${documentChunks.length}');
    }

    if (wantsWeb && webAllowed && webSearchService != null) {
      emit(AgentSearchingWebEvent(effectiveQuery));
      _log('[Web] searchStarted');
      final start = DateTime.now();
      try {
        webChunks = await webSearchService.searchAndFetch(effectiveQuery);
        if (webChunks.isEmpty) {
          _log('[Web] searchCompleted resultCount=0 usableChunks=0');
        } else {
          _log('[Web] searchCompleted usableChunks=${webChunks.length}');
        }
      } catch (error) {
        // Search errors are swallowed, never rethrown — the evidence invariant below decides
        // what an empty result set means, and it is the only thing that should.
        _log('[Web] searchFailed errorType=${error.runtimeType} '
            'errorDescription=${_describe(error)}');
        webChunks = <RetrievedWebChunk>[];
      }
      searchDuration = DateTime.now().difference(start);
    }

    if (cancellation.isCancelled) {
      finishCancelled();
      return;
    }

    // Non-negotiable invariant: a route that *requires* web evidence must never fall through to
    // a normal generation call when that evidence did not arrive — whether because it was not
    // allowed (not configured, mode off) or because retrieval ran and came back empty or errored.
    // No evidence, no claimed current fact.
    //
    // The exact-equality check is deliberate and load-bearing: a web-and-file route with no web
    // evidence proceeds on document evidence plus the transparency caveat, where a web-only
    // route refuses outright.
    if (evidenceRequirement == EvidenceRequirement.webRequired) {
      final hasUsableWebEvidence = webAllowed && webChunks.isNotEmpty;
      if (!hasUsableWebEvidence) {
        if (cancellation.isCancelled) {
          finishCancelled();
          return;
        }
        final reason = webAllowed
            ? _WebEvidenceUnavailableReason.retrievalFailed
            : _WebEvidenceUnavailableReason.notAllowed;
        _log('[Provenance] usedWeb=false reason=${reason.name}');
        emit(const AgentProvenanceUpdatedEvent(ResponseProvenance.empty));
        emit(const AgentGeneratingEvent());
        emit(AgentTokenEvent(_webEvidenceUnavailableMessage(reason, request.userMessage)));
        emit(const AgentCompletedEvent(
          reason: GenerationFinishReason.endOfSequence,
          metrics: GenerationMetrics.empty,
        ));
        if (!controller.isClosed) await controller.close();
        return;
      }
    }

    // Provenance is derived from real pipeline state only, never from the model's text.
    final sources = <SourceReference>[];
    for (var index = 0; index < textbookExcerpts.length; index++) {
      final excerpt = textbookExcerpts[index];
      sources.add(SourceReference(
        id: 'book:${index + 1}',
        kind: SourceKind.textbook,
        title: excerpt.bookTitle,
        url: null,
        page: excerpt.page,
        section: null,
      ));
    }
    for (var index = 0; index < documentChunks.length; index++) {
      final chunk = documentChunks[index];
      sources.add(SourceReference(
        id: 'doc:${index + 1}',
        kind: SourceKind.document,
        title: chunk.documentName,
        url: null,
        page: chunk.pageNumber,
        section: null,
      ));
    }
    for (var index = 0; index < webChunks.length; index++) {
      final chunk = webChunks[index];
      sources.add(SourceReference(
        id: 'web:${index + 1}',
        kind: SourceKind.web,
        title: chunk.title,
        url: chunk.url,
        page: null,
        section: null,
      ));
    }
    final provenance = ResponseProvenance(
      usedWeb: webChunks.isNotEmpty,
      usedDocuments: documentChunks.isNotEmpty || textbookExcerpts.isNotEmpty,
      usedDeviceContext: false,
      sources: sources,
    );
    _log('[Provenance] usedWeb=${provenance.usedWeb} '
        'usedDocuments=${provenance.usedDocuments} sources=${sources.length}');
    emit(AgentProvenanceUpdatedEvent(provenance));

    // The raw user message, not the minimised search query — memory relevance is about what the
    // user actually said, and the minimiser strips exactly the conversational framing that can
    // carry the reference back to an earlier turn.
    final memory = await _sessionMemory.relevantMemory(request.userMessage);
    final reportedContextLength = await _chatEngine.currentAllocatedContextLength;
    final allocatedContextLength =
        reportedContextLength > 0 ? reportedContextLength : configuration.contextLength;
    final budget = ContextBudget.standard(allocatedContextLength: allocatedContextLength);

    var assembledConfiguration = _contextAssembler.assemble(
      ContextAssemblerInput(
        baseConfiguration: configuration,
        memory: memory,
        documentChunks: documentChunks,
        webChunks: webChunks,
        // Search *attempted* for documents, evidence *obtained* for web — see
        // `ContextAssemblerInput` for why the two differ.
        documentSearchPerformed: wantsFiles,
        webSearchPerformed: webChunks.isNotEmpty,
        textbookExcerpts: textbookExcerpts,
        textbookSearchPerformed: wantsTextbooks,
      ),
      budget: budget,
    );
    assembledConfiguration = assembledConfiguration.copyWith(
      systemPrompt: assembledConfiguration.systemPrompt +
          _transparencyNote(
            wantsWeb: wantsWeb,
            webAllowed: webAllowed,
            webConfigured: webSearchService != null,
            webSearchMode: request.permissions.webSearchMode,
            wantsFiles: wantsFiles,
            documentChunksFound: documentChunks.isNotEmpty,
          ),
    );

    final ragTokenCount = textbookExcerpts.fold<int>(
            0, (sum, excerpt) => sum + TokenEstimator.estimateTokenCount(excerpt.text)) +
        documentChunks.fold<int>(
            0, (sum, chunk) => sum + TokenEstimator.estimateTokenCount(chunk.text)) +
        webChunks.fold<int>(
            0, (sum, chunk) => sum + TokenEstimator.estimateTokenCount(chunk.text));
    final memoryTokenCount =
        memory.isEmpty ? 0 : TokenEstimator.estimateTokenCount(memory.renderedText());
    final systemTokenEstimate =
        TokenEstimator.estimateTokenCount(assembledConfiguration.systemPrompt);
    _log('[Context] systemTokens=$systemTokenEstimate memoryTokens=$memoryTokenCount '
        'ragTokens=$ragTokenCount allocatedContext=$allocatedContextLength '
        'generationReserve=${assembledConfiguration.maxNewTokens}');

    emit(const AgentGeneratingEvent());
    _log('[LLM] generationStarted');

    await _streamGeneration(
      request: request,
      assembledConfiguration: assembledConfiguration,
      cancellation: cancellation,
      emit: emit,
      plannerDuration: plannerDuration,
      searchDuration: searchDuration,
      documentRetrievalDuration: documentRetrievalDuration,
      ragTokenCount: ragTokenCount,
      memoryTokenCount: memoryTokenCount,
    );

    if (!controller.isClosed) await controller.close();

    // Maintenance that keeps the *next* turn's memory up to date. The consumer already has its
    // completion event and a closed stream by this point, so this never delays the UI.
    //
    // Deliberately not awaited here, but tracked: compaction is a second engine call, and the
    // engine is single-occupancy. Awaiting it inline would hold the UI; letting it run
    // unobserved would let it collide with the next turn's generation, and since
    // `MemorySummarizer` swallows its own errors the collision would surface as a failure of
    // the *user's* request instead. The next `_run` waits on this handle before it touches the
    // engine.
    final compaction = _sessionMemory.compactIfNeeded(
      history: request.recentMessages,
      allocatedContextLength: allocatedContextLength,
      // The base configuration, not the assembled one: compaction must not inherit a system
      // prompt stuffed with this turn's evidence.
      configuration: configuration,
    );
    _compactionInFlight = compaction.whenComplete(() {
      _compactionInFlight = null;
    });
    unawaited(_compactionInFlight);
  }

  /// Bridges the engine's token stream onto the agent stream, stripping `<think>` content as it
  /// arrives. An engine error propagates out of here and becomes a stream error on the agent
  /// stream — the only error path that reaches the consumer that way.
  Future<void> _streamGeneration({
    required AgentRequest request,
    required GenerationConfiguration assembledConfiguration,
    required _Cancellation cancellation,
    required void Function(AgentEvent event) emit,
    required Duration? plannerDuration,
    required Duration? searchDuration,
    required Duration? documentRetrievalDuration,
    required int ragTokenCount,
    required int memoryTokenCount,
  }) {
    final completer = Completer<void>();
    final thinkingFilter = ThinkingContentFilter();

    final subscription = _chatEngine
        .generate(
      messages: request.recentMessages,
      configuration: assembledConfiguration,
    )
        .listen(
      (event) {
        switch (event) {
          case TokenEvent(:final text):
            final visible = thinkingFilter.push(text);
            if (visible.isNotEmpty) emit(AgentTokenEvent(visible));
          case FinishedEvent(:final reason, :final metrics):
            final remainder = thinkingFilter.flush();
            if (remainder.isNotEmpty) emit(AgentTokenEvent(remainder));
            _log('[LLM] generationCompleted reason=${reason.name} '
                'tokens=${metrics.generatedTokenCount}');
            emit(AgentCompletedEvent(
              reason: reason,
              metrics: metrics.copyWith(
                plannerDuration: plannerDuration,
                searchDuration: searchDuration,
                documentRetrievalDuration: documentRetrievalDuration,
                ragTokenCount: ragTokenCount > 0 ? ragTokenCount : null,
                memoryTokenCount: memoryTokenCount > 0 ? memoryTokenCount : null,
              ),
            ));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    cancellation.engineSubscription = subscription;
    cancellation.generationCompleter = completer;
    return completer.future.whenComplete(() {
      cancellation.engineSubscription = null;
      cancellation.generationCompleter = null;
    });
  }

  /// In the language of [userMessage] — a question asked in Bangla is refused in Bangla —
  /// rather than in the language of the app's buttons.
  static String _webEvidenceUnavailableMessage(
    _WebEvidenceUnavailableReason reason,
    String userMessage,
  ) {
    final strings = AppStrings.forText(userMessage);
    return switch (reason) {
      _WebEvidenceUnavailableReason.notAllowed => strings.replyWebNotAllowed,
      _WebEvidenceUnavailableReason.retrievalFailed => strings.replyWebRetrievalFailed,
    };
  }

  static String _transparencyNote({
    required bool wantsWeb,
    required bool webAllowed,
    required bool webConfigured,
    required WebSearchMode webSearchMode,
    required bool wantsFiles,
    required bool documentChunksFound,
  }) {
    var note = '';
    if (wantsWeb && !webAllowed) {
      if (!webConfigured) {
        note += "\n\nNote: web search isn't configured in this app yet. If this question "
            'needs current information, say your knowledge may be outdated rather than '
            'guessing.';
      } else if (webSearchMode == WebSearchMode.off) {
        note += '\n\nNote: web search is turned off. If this question needs current '
            'information, say your knowledge may not be current and suggest enabling web '
            'search in Settings.';
      }
      // No note for the configured-but-unapproved "ask" case: that path already exited at the
      // confirmation gate.
    }
    if (wantsFiles && !documentChunksFound) {
      note += '\n\nNote: no relevant content was found in the attached documents for this '
          'question -- say so rather than guessing at file contents.';
    }
    return note;
  }

  /// Privacy-safe routing log: structural decisions only, never message or evidence text.
  static void _logDecision({
    required AgentRoute route,
    required bool plannerUsed,
    required AgentDecision decision,
  }) {
    final routeLabel = switch (route) {
      DefiniteRoute() => 'definite(${decision.reason})',
      FastAnswerRoute() => 'fastAnswer',
      NeedsPlanningRoute() => 'needsPlanning',
    };
    _log('[Agent] route=$routeLabel plannerUsed=$plannerUsed '
        'decision=${decision.action.wireValue} '
        'needsCurrentInfo=${decision.needsCurrentInformation} '
        'needsPrivateFiles=${decision.needsPrivateFiles}');
  }

  /// Everything logged from this file is structural — counts, durations, decisions, flags. No
  /// message, prompt, evidence or response text ever reaches here. That invariant is what makes
  /// these logs safe to leave on in a release build, and it is worth checking before adding a
  /// line.
  static void _log(String message) => developer.log(message, name: 'model');

  static String _describe(Object error) =>
      error is WebSearchError ? error.errorDescription : error.toString();
}
