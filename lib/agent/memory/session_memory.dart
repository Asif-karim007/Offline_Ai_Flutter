/// One remembered fact.
///
/// [importance] is written as a flat 0.5 by [MemorySummarizer] and is currently read by no
/// ranking path at all. It is kept because dropping it would change the memory JSON schema the
/// summariser prompt describes, and because relevance ranking is the obvious place it will
/// eventually be used.
class MemoryFact {
  const MemoryFact({
    required this.content,
    required this.importance,
    required this.lastReferencedAt,
  });

  final String content;
  final double importance;
  final DateTime lastReferencedAt;

  MemoryFact copyWith({String? content, double? importance, DateTime? lastReferencedAt}) {
    return MemoryFact(
      content: content ?? this.content,
      importance: importance ?? this.importance,
      lastReferencedAt: lastReferencedAt ?? this.lastReferencedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MemoryFact &&
      other.content == content &&
      other.importance == importance &&
      other.lastReferencedAt == lastReferencedAt;

  @override
  int get hashCode => Object.hash(content, importance, lastReferencedAt);
}

/// Structured, session-only conversational memory.
///
/// Never persisted to the database or to disk — it lives only inside [SessionMemoryManager] for
/// the lifetime of the active chat session and is cleared whenever that session ends (new chat,
/// temporary chat, loading a different conversation).
class SessionMemory {
  const SessionMemory({
    this.summary = '',
    this.facts = const [],
    this.decisions = const [],
    this.userGoals = const [],
    this.unresolvedItems = const [],
    this.importantEntities = const [],
  });

  final String summary;
  final List<MemoryFact> facts;
  final List<String> decisions;
  final List<String> userGoals;
  final List<String> unresolvedItems;
  final List<String> importantEntities;

  bool get isEmpty =>
      summary.isEmpty &&
      facts.isEmpty &&
      decisions.isEmpty &&
      userGoals.isEmpty &&
      unresolvedItems.isEmpty &&
      importantEntities.isEmpty;

  /// Compact plain-text rendering used both as the prompt for the next compaction round and as
  /// the text injected into the assembled system prompt by [ContextAssembler]. Sections appear
  /// in a fixed order and are omitted entirely when empty.
  String renderedText() {
    final sections = <String>[];
    if (summary.isNotEmpty) sections.add('Summary: $summary');
    if (facts.isNotEmpty) {
      sections.add('Known facts:\n${facts.map((fact) => '- ${fact.content}').join('\n')}');
    }
    if (decisions.isNotEmpty) {
      sections.add('Decisions:\n${decisions.map((item) => '- $item').join('\n')}');
    }
    if (userGoals.isNotEmpty) {
      sections.add('User goals:\n${userGoals.map((item) => '- $item').join('\n')}');
    }
    if (unresolvedItems.isNotEmpty) {
      sections.add('Unresolved:\n${unresolvedItems.map((item) => '- $item').join('\n')}');
    }
    if (importantEntities.isNotEmpty) {
      sections.add('Entities: ${importantEntities.join(', ')}');
    }
    return sections.join('\n\n');
  }

  SessionMemory copyWith({
    String? summary,
    List<MemoryFact>? facts,
    List<String>? decisions,
    List<String>? userGoals,
    List<String>? unresolvedItems,
    List<String>? importantEntities,
  }) {
    return SessionMemory(
      summary: summary ?? this.summary,
      facts: facts ?? this.facts,
      decisions: decisions ?? this.decisions,
      userGoals: userGoals ?? this.userGoals,
      unresolvedItems: unresolvedItems ?? this.unresolvedItems,
      importantEntities: importantEntities ?? this.importantEntities,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! SessionMemory) return false;
    return other.summary == summary &&
        _listEquals(other.facts, facts) &&
        _listEquals(other.decisions, decisions) &&
        _listEquals(other.userGoals, userGoals) &&
        _listEquals(other.unresolvedItems, unresolvedItems) &&
        _listEquals(other.importantEntities, importantEntities);
  }

  @override
  int get hashCode => Object.hash(
        summary,
        Object.hashAll(facts),
        Object.hashAll(decisions),
        Object.hashAll(userGoals),
        Object.hashAll(unresolvedItems),
        Object.hashAll(importantEntities),
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
