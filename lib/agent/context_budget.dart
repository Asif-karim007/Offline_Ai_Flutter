/// Token caps (estimated, not exact) for each optional evidence category folded into the
/// system prompt before handing off to the unchanged token-budget trimming inside the engine's
/// `generate()`. Deliberately simple: each category is truncated to its cap independently, and
/// the *recent conversation history* budget is not computed here at all — it is whatever the
/// engine's existing `TokenBudgetManager` leaves room for once the (now larger) system prompt
/// is accounted for. This reuses proven trimming logic instead of adding a second allocator.
class ContextBudget {
  const ContextBudget({
    required this.memoryCap,
    required this.documentEvidenceCap,
    required this.webEvidenceCap,
    required this.textbookEvidenceCap,
  });

  final int memoryCap;
  final int documentEvidenceCap;
  final int webEvidenceCap;

  /// Curriculum passages. The largest single cap, because for a study question the textbook
  /// is the evidence — and Bangla text spends tokens about twice as fast as English.
  final int textbookEvidenceCap;

  /// [allocatedContextLength] should be the model's actually-allocated context
  /// (`ChatEngine.currentAllocatedContextLength`) when available; callers fall back to the
  /// configured `contextLength` before a model has reported its real allocation.
  ///
  /// `toInt()` truncates toward zero, matching Swift's `Int(Double)` conversion. At a 4096
  /// context that is 491 / 819 / 819 / 1024.
  static ContextBudget standard({required int allocatedContextLength}) {
    final base = allocatedContextLength > 0 ? allocatedContextLength : 0;
    return ContextBudget(
      memoryCap: (base * 0.12).toInt(),
      documentEvidenceCap: (base * 0.20).toInt(),
      webEvidenceCap: (base * 0.20).toInt(),
      textbookEvidenceCap: (base * 0.25).toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContextBudget &&
      other.memoryCap == memoryCap &&
      other.documentEvidenceCap == documentEvidenceCap &&
      other.webEvidenceCap == webEvidenceCap &&
      other.textbookEvidenceCap == textbookEvidenceCap;

  @override
  int get hashCode =>
      Object.hash(memoryCap, documentEvidenceCap, webEvidenceCap, textbookEvidenceCap);
}
