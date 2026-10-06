/// Cheap, tokenizer-free approximate token count. Used anywhere a real engine call would be
/// too expensive to reach for (chunk sizing, evidence-block truncation). Never used for the
/// final prompt-fitting decision that actually gates what gets decoded — that still goes
/// through the real tokenizer inside the engine's `TokenBudgetManager`.
///
/// Port note: Swift's `String.count` counts grapheme clusters; Dart's `String.length` counts
/// UTF-16 code units. This port uses `length`/`substring` throughout — here, in
/// [ThinkingContentFilter], in [DocumentChunker] and in [SearchQueryBuilder] — rather than
/// mixing conventions. The two agree for prose and diverge for emoji and combining marks,
/// where this port will estimate slightly more tokens than the Swift original. Consistency
/// matters more than the absolute number: this estimator is deliberately crude, and the same
/// convention on both sides of a comparison keeps chunk sizing and truncation coherent.
abstract final class TokenEstimator {
  /// Rough average of ~4 characters per token for English-like text, and ~2 for Bengali
  /// script.
  ///
  /// The 4:1 rule alone undercounts Bangla badly — its vowel signs and conjuncts are separate
  /// code units, and BPE vocabularies cover the script far more sparsely than English — so a
  /// textbook passage sized "to fit" by it would overflow the context. Counting Bengali code
  /// units at half weight keeps estimates for English text exactly as they were.
  static int estimateTokenCount(String text) {
    final estimate = _cost(text, text.length) ~/ _scale;
    return estimate > 1 ? estimate : 1;
  }

  /// Truncates [text] to approximately [tokenBudget] tokens, appending U+2026 when truncated.
  /// Returns an empty string when the budget is not positive.
  static String truncate(String text, {required int tokenBudget}) {
    if (tokenBudget <= 0) return '';
    final budget = tokenBudget * _scale;
    if (_cost(text, text.length) <= budget) return text;
    var spent = 0;
    var end = 0;
    while (end < text.length) {
      final next = spent + _unitCost(text.codeUnitAt(end));
      if (next > budget) break;
      spent = next;
      end++;
    }
    return '${text.substring(0, end)}…';
  }

  /// Costs are in quarter-tokens so both scripts stay in integer arithmetic: a Latin code
  /// unit costs 1 (four per token), a Bengali one 2 (two per token).
  static const int _scale = 4;

  static int _unitCost(int unit) => unit >= 0x0980 && unit <= 0x09FF ? 2 : 1;

  static int _cost(String text, int end) {
    var cost = 0;
    for (var index = 0; index < end; index++) {
      cost += _unitCost(text.codeUnitAt(index));
    }
    return cost;
  }
}
