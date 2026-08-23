import 'dart:math' as math;

import 'bm25_scorer.dart';
import 'text_embedding_provider.dart';

/// One ranked item and the combined score that got it there.
class Scored<Item> {
  const Scored({required this.item, required this.score});

  final Item item;
  final double score;
}

/// Combines optional semantic similarity (via [TextEmbeddingProvider]) with BM25 lexical
/// scoring into one ranked list. Shared by [SessionMemoryManager]'s relevance selection,
/// [DocumentRetriever], and [WebSearchService]'s per-page excerpt selection.
///
/// The starting weights (0.70 semantic / 0.30 lexical) are not sacred — they were meant to be
/// tuned once real usage data existed. They are carried across unchanged so that any future
/// tuning is measured against the same baseline both apps had.
class HybridRetriever {
  HybridRetriever({
    TextEmbeddingProvider embeddingProvider = const NullEmbeddingProvider(),
    this.semanticWeight = 0.70,
    this.lexicalWeight = 0.30,
    this.relevanceFloor = 0.15,
  }) : _embeddingProvider = embeddingProvider;

  final TextEmbeddingProvider _embeddingProvider;

  final double semanticWeight;
  final double lexicalWeight;

  /// Below this combined score — after min-max normalisation to 0...1 — a candidate is dropped
  /// rather than padded in just to hit a fixed result count. Note that min-max normalisation
  /// puts the best candidate at exactly 1.0 and the worst at exactly 0.0, so whenever scores
  /// differ at all the worst candidate is always discarded.
  final double relevanceFloor;

  /// Ranks [items] against [query], returning at most [limit] results above [relevanceFloor],
  /// highest score first. [text] extracts the string to score each item against.
  ///
  /// [precomputedEmbeddings], when provided, avoids a redundant `embed()` call per item for
  /// callers (like [DocumentRetriever]) that already cache embeddings at index time. Entries may
  /// be null; a null entry leaves that item's semantic score at zero.
  Future<List<Scored<Item>>> rank<Item>({
    required String query,
    required List<Item> items,
    required int limit,
    required String Function(Item item) text,
    List<List<double>?>? precomputedEmbeddings,
  }) async {
    // Not `const []`: Dart forbids a const literal whose element type is a type parameter.
    if (items.isEmpty) return <Scored<Item>>[];

    final documents = items.map(text).toList();
    final lexicalScores = BM25Scorer.scores(query: query, documents: documents);

    final semanticScores = List<double>.filled(items.length, 0);
    final queryVector = await _embeddingProvider.embed(query);
    // A null query vector leaves every semantic score at zero, which is the lexical-only path.
    if (queryVector != null) {
      for (var index = 0; index < items.length; index++) {
        final List<double>? vector;
        if (precomputedEmbeddings != null && index < precomputedEmbeddings.length) {
          vector = precomputedEmbeddings[index];
        } else {
          vector = await _embeddingProvider.embed(documents[index]);
        }
        if (vector == null) continue;
        semanticScores[index] = _cosineSimilarity(queryVector, vector);
      }
    }

    final normalizedLexical = _normalize(lexicalScores);
    final normalizedSemantic = _normalize(semanticScores);

    final combined = <Scored<Item>>[];
    for (var index = 0; index < items.length; index++) {
      final score = semanticWeight * normalizedSemantic[index] +
          lexicalWeight * normalizedLexical[index];
      combined.add(Scored(item: items[index], score: score));
    }

    final surviving = combined.where((scored) => scored.score >= relevanceFloor).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return surviving.length <= limit ? surviving : surviving.sublist(0, limit);
  }

  /// Min-max normalisation. When every value is identical — including the all-zeros case that
  /// the null embedding provider always produces — this degenerates to a 0/1 indicator rather
  /// than dividing by zero.
  static List<double> _normalize(List<double> values) {
    if (values.isEmpty) return values;
    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    if (!(maxValue > minValue)) {
      return values.map((value) => value > 0 ? 1.0 : 0.0).toList();
    }
    return values.map((value) => (value - minValue) / (maxValue - minValue)).toList();
  }

  /// Swift accumulated these in `Float` and widened at the end; Dart has only `double`, so this
  /// runs at higher precision. The difference is far below the granularity the relevance floor
  /// cares about.
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var index = 0; index < a.length; index++) {
      dot += a[index] * b[index];
      normA += a[index] * a[index];
      normB += b[index] * b[index];
    }
    if (normA <= 0 || normB <= 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
