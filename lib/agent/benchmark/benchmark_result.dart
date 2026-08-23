/// One benchmark run's outcome.
///
/// Every field comes from a real generation against whichever model is currently loaded — this
/// type carries measurements, never estimates, so a model-comparison decision can be made from
/// real numbers collected on real devices rather than assumptions.
class BenchmarkResult {
  const BenchmarkResult({
    required this.id,
    required this.promptLabel,
    required this.modelName,
    required this.promptTokenCount,
    required this.generatedTokenCount,
    this.firstTokenLatency,
    this.totalDuration,
    this.tokensPerSecond,
    this.residentMemoryBytesAfter,
  });

  final String id;
  final String promptLabel;
  final String modelName;
  final int promptTokenCount;
  final int generatedTokenCount;
  final Duration? firstTokenLatency;
  final Duration? totalDuration;
  final double? tokensPerSecond;
  final int? residentMemoryBytesAfter;

  @override
  bool operator ==(Object other) =>
      other is BenchmarkResult &&
      other.id == id &&
      other.promptLabel == promptLabel &&
      other.modelName == modelName &&
      other.promptTokenCount == promptTokenCount &&
      other.generatedTokenCount == generatedTokenCount &&
      other.firstTokenLatency == firstTokenLatency &&
      other.totalDuration == totalDuration &&
      other.tokensPerSecond == tokensPerSecond &&
      other.residentMemoryBytesAfter == residentMemoryBytesAfter;

  @override
  int get hashCode => Object.hash(
        id,
        promptLabel,
        modelName,
        promptTokenCount,
        generatedTokenCount,
        firstTokenLatency,
        totalDuration,
        tokensPerSecond,
        residentMemoryBytesAfter,
      );
}
