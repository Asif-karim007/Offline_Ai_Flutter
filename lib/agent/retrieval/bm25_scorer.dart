import 'dart:math' as math;

/// Lightweight BM25 lexical scorer over a small in-session corpus (memory facts, document
/// chunks). Not meant to scale beyond a few hundred short passages — there is no persistent
/// index; everything is recomputed per query, which is fine at this scale. No stemming and no
/// stopword removal either.
abstract final class BM25Scorer {
  static const double _k1 = 1.5;
  static const double _b = 0.75;

  /// Splits on any non-alphanumeric run. Unicode-aware, matching Swift's
  /// `CharacterSet.alphanumerics.inverted` — an ASCII-only `[^a-z0-9]+` would silently shred
  /// every non-Latin script into empty tokens.
  static final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Returns a score per document index in [documents]; higher is more relevant.
  static List<double> scores({required String query, required List<String> documents}) {
    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty || documents.isEmpty) {
      return List<double>.filled(documents.length, 0);
    }

    final docTerms = documents.map(_tokenize).toList();
    final docLengths = docTerms.map((terms) => terms.length).toList();
    final totalLength = docLengths.fold<int>(0, (sum, length) => sum + length);
    final averageLength = totalLength / math.max(docLengths.length, 1);

    final documentFrequency = <String, int>{};
    for (final terms in docTerms) {
      for (final term in terms.toSet()) {
        documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
      }
    }
    final documentCount = documents.length.toDouble();

    final results = <double>[];
    for (var index = 0; index < docTerms.length; index++) {
      final termCounts = <String, int>{};
      for (final term in docTerms[index]) {
        termCounts[term] = (termCounts[term] ?? 0) + 1;
      }
      final length = docLengths[index].toDouble();
      var score = 0.0;
      // Iterates the query's terms *with duplicates*, so a term repeated in the query
      // contributes its weight more than once. That is the Swift behaviour and it is what makes
      // an emphatic repeated word count for more, so it is preserved rather than deduplicated.
      for (final term in queryTerms) {
        final termFrequency = termCounts[term];
        if (termFrequency == null || termFrequency == 0) continue;
        final df = (documentFrequency[term] ?? 0).toDouble();
        final idf = math.log(1 + (documentCount - df + 0.5) / (df + 0.5));
        final numerator = termFrequency * (_k1 + 1);
        final denominator =
            termFrequency + _k1 * (1 - _b + _b * (length / math.max(averageLength, 1)));
        score += idf * (numerator / denominator);
      }
      results.add(score);
    }
    return results;
  }

  static List<String> _tokenize(String text) => text
      .toLowerCase()
      .split(_separators)
      .where((token) => token.isNotEmpty)
      .toList();
}
