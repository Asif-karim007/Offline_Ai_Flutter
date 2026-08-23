import 'agent_decision.dart';
import 'agent_request.dart';

/// The router's routing outcome. [AgentOrchestrator] only falls through to [AgentPlanner] for
/// [NeedsPlanningRoute] — [DefiniteRoute] skips the planner (and the small model's unreliable
/// judgment) entirely, and [FastAnswerRoute] skips both the planner and any retrieval.
sealed class AgentRoute {
  const AgentRoute();
}

final class DefiniteRoute extends AgentRoute {
  const DefiniteRoute(this.decision);

  final AgentDecision decision;

  @override
  bool operator ==(Object other) => other is DefiniteRoute && other.decision == decision;

  @override
  int get hashCode => Object.hash(DefiniteRoute, decision);
}

final class FastAnswerRoute extends AgentRoute {
  const FastAnswerRoute();

  @override
  bool operator ==(Object other) => other is FastAnswerRoute;

  @override
  int get hashCode => (FastAnswerRoute).hashCode;
}

final class NeedsPlanningRoute extends AgentRoute {
  const NeedsPlanningRoute();

  @override
  bool operator ==(Object other) => other is NeedsPlanningRoute;

  @override
  int get hashCode => (NeedsPlanningRoute).hashCode;
}

/// Deterministic routing, checked in a fixed priority order, run on every message before ever
/// considering a planner call:
///
/// 1. Explicit user tool request/restriction (always wins, even over a freshness match)
/// 2. Device-local dynamic information (date/time — never the network, never pretrained memory)
/// 3. Explicit "use only this file" restriction
/// 4/5. Hard freshness intent (optionally combined with attached documents)
/// 6. Remaining soft/ambiguous signal → the planner gets a look
/// 7. Nothing plausible → direct local answer
///
/// A 0.6B-parameter model is not trusted as the sole decision-maker for any of the first five
/// obvious categories; the planner exists only to adjudicate genuine ambiguity (category 6).
/// Multi-word phrase matching is used throughout — not single keywords like "current" or
/// "latest" in isolation — specifically so ordinary definitional questions ("what does current
/// mean in electricity") do not false-positive into a forced web search. See
/// [negativeFreshnessGuards].
class AgentRouter {
  const AgentRouter();

  // ---------------------------------------------------------------------------------------
  // Phrase and pattern tables.
  //
  // Public, not private, on purpose: `AgentPlanner.deterministicFallback` and
  // `DeviceContextTool` reuse the exact same signals rather than keeping duplicated, weaker
  // copies that can drift out of sync.
  // ---------------------------------------------------------------------------------------

  static const List<String> explicitWebPhrases = [
    'search web', 'search the web', 'search online', 'look online',
    'look this up online', 'look it up online', 'check online', 'google it',
    'search internet', 'search the internet', 'look up online',
  ];

  /// Straight ASCII apostrophes, not typographic ones — a user typing on an iOS keyboard with
  /// smart punctuation produces `’`, which deliberately does not match. That was true in the
  /// Swift app too and is preserved rather than quietly widened.
  static const List<String> explicitNoWebPhrases = [
    "don't use the internet", 'do not use the internet', 'without using the internet',
    "don't search", 'do not search', 'no internet', 'offline only',
    'without searching', "don't look online", 'do not look online',
    'without internet access', "don't go online", 'do not go online',
    "don't search the web", 'do not search the web',
  ];

  static const List<String> explicitFileOnlyPhrases = [
    'use only this file', 'only use this file', 'use only this document',
    'only use this document', 'just this pdf', 'only from this file',
    'only from this document', 'use only the attached', 'based only on this file',
    'based only on the attached', 'only this document', 'only this file',
  ];

  static const List<String> deviceTimePhrases = [
    'what time is it', "what's the time", 'whats the time', 'current time',
    'time is it', 'what time it is', 'tell me the time', 'time now',
    "what's the time now", 'whats the time now', 'time right now',
    'what time is it here',
  ];

  static const List<String> deviceDatePhrases = [
    'what day is it', "what's today's date", "whats today's date", 'todays date',
    "today's date", "what is today's date", 'what is the date today',
    'what date is it', "what's the date", 'whats the date', 'the time today',
    'the date today', 'what day of the week', 'is today',
  ];

  /// Multi-word patterns that are strong, low-false-positive signals that the answer can change
  /// materially over time. Deliberately phrase-level, not single keywords.
  static const List<String> hardFreshnessPatterns = [
    'latest version', 'latest release', 'newest version', 'current version',
    'latest stable', "what's the latest", 'whats the latest', "what's new in",
    'whats new in', 'release date of', 'just released', 'just came out',
    'current ceo', 'current president', 'who is the current', 'latest news',
    'recent news', 'news today', 'news about', 'stock price', 'share price',
    'crypto price', 'bitcoin price', 'price of bitcoin', 'weather today',
    'weather in', 'weather forecast', 'who won', 'game score', 'score of',
    'match score', "today's game", 'current price', 'current availability',
    'available now', 'latest ios', 'latest xcode', 'latest swift', 'latest python',
    'newest release', 'worth today', 'worth right now', 'current information',
    'up to date information', 'up-to-date information', 'information online',
  ];

  /// Office/role titles for the generalized "who is the (current) <role> (of X)" pattern —
  /// covers any officeholder query without enumerating every country or organization, and
  /// without ever hardcoding *who* holds the office (that answer only ever comes from retrieved
  /// web evidence).
  static const List<String> officeHolderRoles = [
    'prime minister', 'president', 'ceo', 'governor', 'chairman', 'chairwoman',
    'chairperson', 'mayor', 'monarch', 'king', 'queen', 'pope', 'chancellor',
    'premier', 'secretary general', 'foreign minister', 'defense minister',
    'finance minister', 'director general',
  ];

  /// Checked before the freshness patterns and version regexes. If any of these match, the
  /// message is treated as a definitional/educational use of the word even though a freshness
  /// word appears in it, and routing falls through instead of forcing a web search.
  static const List<String> negativeFreshnessGuards = [
    'current mean', 'current means', 'what is current', 'define current',
    'explain current', 'concept of current', 'current in electricity',
    'current in physics', 'alternating current', 'direct current',
    'current flowing', 'current flows', 'electric current', 'current assets',
    'current liabilities', 'current account', 'current affairs',
  ];

  /// Softer signals — still worth a planner call for genuine ambiguity, but not strong enough
  /// to force a route outright.
  static const List<String> currentInformationPhrases = [
    'latest', 'current', 'today', 'recently', 'this week', 'who is currently',
    'recent release', 'new release', 'weather', 'score', 'schedule', 'ceo',
    'president', 'regulation', 'stock', 'availability', 'price', 'version', 'news', 'law',
  ];

  static const List<String> fileReferencePhrases = [
    'in this pdf', 'in my file', 'in this file', 'in this document', 'search my files',
    'based on the document', 'attached file', 'attached document', 'in my document',
  ];

  /// Generalized "latest/newest/current <product> version|release" pattern — covers any product
  /// name without hardcoding one, since a fixed phrase list cannot enumerate every product a
  /// user might ask about.
  static final RegExp _versionFreshnessRegex = RegExp(
    r'\b(latest|newest|current)(\s+stable)?\s+([a-z0-9+#.\-]+\s+){0,3}(version|release)\b',
    caseSensitive: false,
  );

  static final RegExp _versionOfRegex = RegExp(
    r'\b(latest|newest|current)\s+(version|release)\s+of\s+[a-z0-9+#.\-]+\b',
    caseSensitive: false,
  );

  /// Asking "who IS the <role> (of X)" is, in ordinary usage, already an implicit request for
  /// the *current* holder — it does not need a separate "now"/"currently" qualifier to count as
  /// a freshness question, which is what makes "Who is the prime minister of Bangladesh now?"
  /// and the same question without "now" both match.
  static final RegExp _officeHolderRegex = _buildOfficeHolderRegex();

  static RegExp _buildOfficeHolderRegex() {
    final roles = officeHolderRoles.map(RegExp.escape).join('|');
    return RegExp(
      r'\b(who is (the )?(current )?(' + roles + r')\b|current (' + roles + r')\b)',
      caseSensitive: false,
    );
  }

  // ---------------------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------------------

  AgentRoute route(AgentRequest request) {
    final lowered = request.userMessage.toLowerCase();
    final hasDocuments = request.attachedDocuments.isNotEmpty;

    // 1. Explicit instruction/restriction always wins — checked before everything else,
    //    including a freshness match, so "don't use the internet, what's the latest Python
    //    version" still honours the restriction. Critically this does NOT silently answer as if
    //    it were an ordinary question: `needsCurrentInformation` is still set when the
    //    restricted question is itself a freshness question, so the orchestrator can give a
    //    deterministic "can't verify without web access" answer instead of letting the model
    //    guess a possibly-stale fact just because no route to search exists.
    if (_containsAny(lowered, explicitNoWebPhrases)) {
      final wantsFiles = hasDocuments;
      final isDefinitionalUseOfFreshnessWord = _containsAny(lowered, negativeFreshnessGuards);
      final needsCurrentInfo =
          !isDefinitionalUseOfFreshnessWord && matchesHardFreshness(lowered);
      return DefiniteRoute(AgentDecision(
        action: wantsFiles ? AgentAction.fileSearch : AgentAction.answer,
        query: request.userMessage,
        reason: 'router_explicit_no_web',
        needsCurrentInformation: needsCurrentInfo,
        needsPrivateFiles: wantsFiles,
      ));
    }

    if (_containsAny(lowered, explicitWebPhrases)) {
      return DefiniteRoute(AgentDecision(
        action: hasDocuments ? AgentAction.webAndFileSearch : AgentAction.webSearch,
        query: request.userMessage,
        reason: 'router_explicit_web',
        needsCurrentInformation: true,
        needsPrivateFiles: hasDocuments,
      ));
    }

    // 2. Device-local dynamic information — must never hit the network or rely on pretrained
    //    knowledge for something the device already knows exactly.
    if (_containsAny(lowered, deviceTimePhrases) || _containsAny(lowered, deviceDatePhrases)) {
      return DefiniteRoute(AgentDecision(
        action: AgentAction.deviceContext,
        query: request.userMessage,
        reason: 'router_device_context',
        needsCurrentInformation: false,
        needsPrivateFiles: false,
      ));
    }

    // 3. Explicit file-only restriction.
    if (hasDocuments && _containsAny(lowered, explicitFileOnlyPhrases)) {
      return DefiniteRoute(AgentDecision(
        action: AgentAction.fileSearch,
        query: request.userMessage,
        reason: 'router_explicit_file_only',
        needsCurrentInformation: false,
        needsPrivateFiles: true,
      ));
    }

    final isDefinitionalUseOfFreshnessWord = _containsAny(lowered, negativeFreshnessGuards);

    // 4/5. Hard freshness intent, optionally combined with attached documents.
    if (!isDefinitionalUseOfFreshnessWord && matchesHardFreshness(lowered)) {
      return DefiniteRoute(AgentDecision(
        action: hasDocuments ? AgentAction.webAndFileSearch : AgentAction.webSearch,
        query: request.userMessage,
        reason: 'router_hard_freshness',
        needsCurrentInformation: true,
        needsPrivateFiles: hasDocuments,
      ));
    }

    // Any attached document deserves at least a planner look — a question can be *about* the
    // file with no explicit "in this document" phrasing at all (plain "Summarize this"), so
    // this cannot be a hard, phrase-based route the way the others are.
    if (hasDocuments) {
      return const NeedsPlanningRoute();
    }

    // 6. Remaining soft signal — worth a cheap planner call rather than guessing.
    final softSignal = _containsAny(lowered, fileReferencePhrases) ||
        (!isDefinitionalUseOfFreshnessWord &&
            _containsAny(lowered, currentInformationPhrases));
    if (softSignal) {
      return const NeedsPlanningRoute();
    }

    // 7. Nothing plausibly needs a tool.
    return const FastAnswerRoute();
  }

  /// Public, not private, so `AgentPlanner.deterministicFallback` shares the exact same
  /// freshness detection — including the version and office-holder regexes, not just the plain
  /// phrase lists.
  static bool matchesHardFreshness(String lowered) {
    if (_containsAny(lowered, hardFreshnessPatterns)) return true;
    if (_versionFreshnessRegex.hasMatch(lowered)) return true;
    if (_versionOfRegex.hasMatch(lowered)) return true;
    if (_officeHolderRegex.hasMatch(lowered)) return true;
    return false;
  }

  static bool _containsAny(String lowered, List<String> phrases) {
    for (final phrase in phrases) {
      if (lowered.contains(phrase)) return true;
    }
    return false;
  }
}
