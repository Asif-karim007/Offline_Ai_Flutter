import '../../domain/chat_message.dart';
import '../../domain/generation_configuration.dart';
import '../../llm/chat_engine.dart';
import '../retrieval/hybrid_retriever.dart';
import '../token_estimator.dart';
import 'memory_summarizer.dart';
import 'session_memory.dart';

/// Owns the active session's structured memory. In memory only, one instance per orchestrator
/// session — [reset] is called from `AgentOrchestrator.resetSession()` at the same points the
/// engine's `resetConversation()` already is (new chat, temporary chat, loading a different
/// conversation), so memory never leaks across sessions.
class SessionMemoryManager {
  SessionMemoryManager({required ChatEngine chatEngine})
      : _summarizer = MemorySummarizer(chatEngine: chatEngine);

  /// The most recent this many *messages* — not turns — are always kept verbatim in the prompt
  /// and never considered for compaction, regardless of token pressure. Both use sites index a
  /// `List<ChatMessage>`, so at one user message plus one assistant reply per turn this is three
  /// turns. The number is the tuned value and stays as it is; only the name was wrong.
  static const int minimumVerbatimMessages = 6;

  /// Compact once the conversation-history estimate crosses this fraction of the allocated
  /// context — the lower bound of the 70–75% target, so compaction happens a little early rather
  /// than right at the edge. At a 4096 context that is 2867 estimated tokens.
  static const double compactionThresholdFraction = 0.70;

  final MemorySummarizer _summarizer;

  SessionMemory _memory = const SessionMemory();
  final Set<String> _compactedMessageIds = {};

  /// Swift relied on actor isolation to stop two compactions overlapping. Here an explicit flag
  /// does it: compaction is opportunistic maintenance fired after a turn completes, so skipping
  /// a round that is already in flight is exactly the right behaviour — the next turn will
  /// re-evaluate the threshold anyway.
  bool _isCompacting = false;

  void reset() {
    _memory = const SessionMemory();
    _compactedMessageIds.clear();
    _isCompacting = false;
  }

  /// Selects the memory relevant to [query].
  ///
  /// Summary, decisions, goals, unresolved items and entities are already compact after
  /// compaction and are always included as-is; only facts are relevance-ranked, so a long
  /// session's older irrelevant facts do not crowd out the current question. The retriever's
  /// relevance floor can return fewer than [limit] facts, or none.
  Future<SessionMemory> relevantMemory(String query, {int limit = 8}) async {
    if (_memory.isEmpty) return _memory;
    // Below the limit there is nothing to choose between, so the facts are returned untouched —
    // including their `lastReferencedAt`, which is only refreshed on the ranked path.
    if (_memory.facts.length <= limit) return _memory;

    final retriever = HybridRetriever();
    final ranked = await retriever.rank<MemoryFact>(
      query: query,
      items: _memory.facts,
      limit: limit,
      text: (fact) => fact.content,
    );

    final now = DateTime.now();
    final selected =
        ranked.map((scored) => scored.item.copyWith(lastReferencedAt: now)).toList();
    return _memory.copyWith(facts: selected);
  }

  /// Cheap estimate-based check, safe to call every turn: only summarises the previously
  /// un-compacted portion of [history] older than the most recent [minimumVerbatimMessages], and
  /// only once the estimated total is past the compaction threshold.
  Future<void> compactIfNeeded({
    required List<ChatMessage> history,
    required int allocatedContextLength,
    required GenerationConfiguration configuration,
  }) async {
    if (_isCompacting) return;
    if (allocatedContextLength <= 0 || history.length <= minimumVerbatimMessages) return;

    final estimatedTokens = history.fold<int>(
        0, (sum, message) => sum + TokenEstimator.estimateTokenCount(message.content));
    final threshold = (allocatedContextLength * compactionThresholdFraction).toInt();
    if (estimatedTokens < threshold) return;

    final oldPortion = history
        .sublist(0, history.length - minimumVerbatimMessages)
        .where((message) => !_compactedMessageIds.contains(message.id))
        .toList();
    if (oldPortion.isEmpty) return;

    _isCompacting = true;
    try {
      // Replacement, not accumulation: the returned memory fully supersedes the previous one.
      _memory = await _summarizer.summarize(
        previousMemory: _memory,
        newMessages: oldPortion,
        configuration: configuration,
      );
      for (final message in oldPortion) {
        _compactedMessageIds.add(message.id);
      }
    } finally {
      _isCompacting = false;
    }
  }
}
