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
  /// Rough average of ~4 characters per token for English-like text.
  static int estimateTokenCount(String text) {
    final estimate = text.length ~/ 4;
    return estimate > 1 ? estimate : 1;
  }

  /// Truncates [text] to approximately [tokenBudget] tokens, appending U+2026 when truncated.
  /// Returns an empty string when the budget is not positive.
  static String truncate(String text, {required int tokenBudget}) {
    if (tokenBudget <= 0) return '';
    final approxCharBudget = tokenBudget * 4;
    if (text.length <= approxCharBudget) return text;
    return '${text.substring(0, approxCharBudget)}…';
  }
}
