import 'dart:convert';

import '../../domain/chat_message.dart';
import '../../domain/generation_configuration.dart';
import '../../llm/chat_engine.dart';
import '../agent_planner.dart';
import 'session_memory.dart';

/// The JSON shape the summariser prompt asks for. Keys are the Swift property names verbatim —
/// camelCase, no `CodingKeys` remapping — because the prompt names them literally.
class _MemoryUpdatePayload {
  const _MemoryUpdatePayload({
    required this.summary,
    required this.facts,
    required this.decisions,
    required this.userGoals,
    required this.unresolvedItems,
    required this.importantEntities,
  });

  final String summary;
  final List<String> facts;
  final List<String> decisions;
  final List<String> userGoals;
  final List<String> unresolvedItems;
  final List<String> importantEntities;

  /// As strict as Swift's synthesized `Codable`: every key required, every type checked,
  /// including each array element. Returns null rather than defaulting, so a malformed
  /// compaction simply keeps the previous memory.
  static _MemoryUpdatePayload? fromJson(Object? decoded) {
    if (decoded is! Map) return null;

    final summary = decoded['summary'];
    if (summary is! String) return null;

    final facts = _stringList(decoded['facts']);
    final decisions = _stringList(decoded['decisions']);
    final userGoals = _stringList(decoded['userGoals']);
    final unresolvedItems = _stringList(decoded['unresolvedItems']);
    final importantEntities = _stringList(decoded['importantEntities']);
    if (facts == null ||
        decisions == null ||
        userGoals == null ||
        unresolvedItems == null ||
        importantEntities == null) {
      return null;
    }

    return _MemoryUpdatePayload(
      summary: summary,
      facts: facts,
      decisions: decisions,
      userGoals: userGoals,
      unresolvedItems: unresolvedItems,
      importantEntities: importantEntities,
    );
  }

  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    final result = <String>[];
    for (final element in value) {
      if (element is! String) return null;
      result.add(element);
    }
    return result;
  }
}

/// Folds newly-old conversation turns into the running [SessionMemory], replacing rather than
/// appending to the previous summary so memory can never grow unbounded:
/// `previous memory + newly compressed history -> updated compact memory`.
///
/// Like the planner, this uses a plain structured call with no grammar. The nested-array schema
/// here is not worth a hand-written GBNF grammar the way the small planner schema might have
/// been, and grammar sampling is off the table for the reason documented on [AgentPlanner]
/// anyway. Output is parsed leniently, and any parse failure just skips this compaction round
/// and keeps the previous memory — never fatal, never lost history, since the raw messages are
/// untouched either way. This is purely optional enrichment.
class MemorySummarizer {
  const MemorySummarizer({required ChatEngine chatEngine}) : _chatEngine = chatEngine;

  final ChatEngine _chatEngine;

  static const String systemPrompt =
      'You maintain compact structured memory for an ongoing offline chat session. You will be '
      'given the existing memory (if any) and a batch of new conversation turns. Produce updated '
      'memory that preserves important facts, names, user goals, constraints, decisions, '
      'technical details, unresolved questions, and corrections -- and aggressively drops '
      'greetings, filler, repetition, obsolete intermediate reasoning, and information that has '
      'since been superseded. Respond with a single compact JSON object with exactly these keys: '
      '"summary" (string), "facts" (array of short strings), "decisions" (array of short '
      'strings), "userGoals" (array of short strings), "unresolvedItems" (array of short '
      'strings), "importantEntities" (array of short strings). Output only the JSON object, '
      'nothing else.';

  static const int maxTokens = 400;

  /// Never throws: a failed call returns [previousMemory] untouched.
  Future<SessionMemory> summarize({
    required SessionMemory previousMemory,
    required List<ChatMessage> newMessages,
    required GenerationConfiguration configuration,
  }) async {
    if (newMessages.isEmpty) return previousMemory;

    final summarizerConfiguration = configuration.copyWith(
      temperature: 0.2,
      minP: 0.0,
      topP: 1.0,
    );

    final transcript = newMessages
        .map((message) => '${message.role.wireValue}: ${message.content}')
        .join('\n');
    final existing = previousMemory.isEmpty ? '(none yet)' : previousMemory.renderedText();
    final userPrompt = 'Existing memory:\n'
        '$existing\n'
        '\n'
        'New conversation turns to fold in:\n'
        '$transcript';

    try {
      final raw = await _chatEngine.generateStructured(
        messages: <({String role, String content})>[
          (role: 'system', content: systemPrompt),
          (role: 'user', content: userPrompt),
        ],
        configuration: summarizerConfiguration,
        maxTokens: maxTokens,
        grammar: null,
      );
      return _parse(raw, fallback: previousMemory);
    } catch (_) {
      return previousMemory;
    }
  }

  static SessionMemory _parse(String raw, {required SessionMemory fallback}) {
    final payload = _decodePayload(raw);
    if (payload == null) return fallback;
    final now = DateTime.now();
    return SessionMemory(
      summary: payload.summary,
      // A flat 0.5 for every fact, exactly as the Swift did. Nothing reads it yet.
      facts: payload.facts
          .map((content) =>
              MemoryFact(content: content, importance: 0.5, lastReferencedAt: now))
          .toList(),
      decisions: payload.decisions,
      userGoals: payload.userGoals,
      unresolvedItems: payload.unresolvedItems,
      importantEntities: payload.importantEntities,
    );
  }

  static _MemoryUpdatePayload? _decodePayload(String raw) {
    try {
      final payload = _MemoryUpdatePayload.fromJson(jsonDecode(raw));
      if (payload != null) return payload;
    } on FormatException {
      // Fall through to the tolerant path.
    }

    // Models sometimes wrap JSON in a <think> preamble, Markdown fences, or stray prose despite
    // instructions. Reuse the planner's tolerant extraction rather than a naive
    // first-'{'-to-last-'}' substring, which could span past the actual object into unrelated
    // trailing text or swallow a brace mentioned inside suppressed reasoning.
    final withoutThinking = AgentPlanner.removingThinkBlocks(raw);
    final withoutFences = AgentPlanner.strippingCodeFences(withoutThinking);
    final jsonSubstring = AgentPlanner.firstBalancedJsonObject(withoutFences);
    if (jsonSubstring == null) return null;
    try {
      return _MemoryUpdatePayload.fromJson(jsonDecode(jsonSubstring));
    } on FormatException {
      return null;
    }
  }
}
