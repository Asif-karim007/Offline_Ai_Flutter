/// Debug and performance figures for the most recent generation.
///
/// Deliberately contains no prompt or response text, which is what makes it safe to log.
/// Everything here is structural: counts, sizes and durations.
class GenerationMetrics {
  const GenerationMetrics({
    required this.modelName,
    required this.modelFileSizeBytes,
    required this.nativeContextLength,
    required this.allocatedContextLength,
    required this.promptTokenCount,
    required this.reservedOutputTokens,
    required this.generatedTokenCount,
    required this.conversationMode,
    this.firstTokenLatency,
    this.totalGenerationDuration,
    this.plannerDuration,
    this.searchDuration,
    this.documentRetrievalDuration,
    this.ragTokenCount,
    this.memoryTokenCount,
  });

  final String modelName;
  final int modelFileSizeBytes;
  final int nativeContextLength;
  final int allocatedContextLength;
  final int promptTokenCount;
  final int reservedOutputTokens;
  final int generatedTokenCount;
  final Duration? firstTokenLatency;
  final Duration? totalGenerationDuration;
  final String conversationMode;

  // Agent-pipeline instrumentation, filled in by the orchestrator and never by the engine,
  // which knows nothing about routing or retrieval. All null when the fast path was taken —
  // no planner call, no tools.
  final Duration? plannerDuration;
  final Duration? searchDuration;
  final Duration? documentRetrievalDuration;
  final int? ragTokenCount;
  final int? memoryTokenCount;

  double? get tokensPerSecond {
    final total = totalGenerationDuration;
    if (total == null || total.inMicroseconds <= 0 || generatedTokenCount <= 0) {
      return null;
    }
    return generatedTokenCount / (total.inMicroseconds / Duration.microsecondsPerSecond);
  }

  static const GenerationMetrics empty = GenerationMetrics(
    modelName: '-',
    modelFileSizeBytes: 0,
    nativeContextLength: 0,
    allocatedContextLength: 0,
    promptTokenCount: 0,
    reservedOutputTokens: 0,
    generatedTokenCount: 0,
    conversationMode: '-',
  );

  GenerationMetrics copyWith({
    String? conversationMode,
    Duration? plannerDuration,
    Duration? searchDuration,
    Duration? documentRetrievalDuration,
    int? ragTokenCount,
    int? memoryTokenCount,
  }) {
    return GenerationMetrics(
      modelName: modelName,
      modelFileSizeBytes: modelFileSizeBytes,
      nativeContextLength: nativeContextLength,
      allocatedContextLength: allocatedContextLength,
      promptTokenCount: promptTokenCount,
      reservedOutputTokens: reservedOutputTokens,
      generatedTokenCount: generatedTokenCount,
      firstTokenLatency: firstTokenLatency,
      totalGenerationDuration: totalGenerationDuration,
      conversationMode: conversationMode ?? this.conversationMode,
      plannerDuration: plannerDuration ?? this.plannerDuration,
      searchDuration: searchDuration ?? this.searchDuration,
      documentRetrievalDuration: documentRetrievalDuration ?? this.documentRetrievalDuration,
      ragTokenCount: ragTokenCount ?? this.ragTokenCount,
      memoryTokenCount: memoryTokenCount ?? this.memoryTokenCount,
    );
  }

  Map<String, Object?> toIsolateMap() => {
        'modelName': modelName,
        'modelFileSizeBytes': modelFileSizeBytes,
        'nativeContextLength': nativeContextLength,
        'allocatedContextLength': allocatedContextLength,
        'promptTokenCount': promptTokenCount,
        'reservedOutputTokens': reservedOutputTokens,
        'generatedTokenCount': generatedTokenCount,
        'firstTokenLatencyUs': firstTokenLatency?.inMicroseconds,
        'totalGenerationDurationUs': totalGenerationDuration?.inMicroseconds,
        'conversationMode': conversationMode,
      };

  static GenerationMetrics fromIsolateMap(Map<String, Object?> map) {
    Duration? micros(String key) {
      final value = map[key] as int?;
      return value == null ? null : Duration(microseconds: value);
    }

    return GenerationMetrics(
      modelName: map['modelName']! as String,
      modelFileSizeBytes: map['modelFileSizeBytes']! as int,
      nativeContextLength: map['nativeContextLength']! as int,
      allocatedContextLength: map['allocatedContextLength']! as int,
      promptTokenCount: map['promptTokenCount']! as int,
      reservedOutputTokens: map['reservedOutputTokens']! as int,
      generatedTokenCount: map['generatedTokenCount']! as int,
      firstTokenLatency: micros('firstTokenLatencyUs'),
      totalGenerationDuration: micros('totalGenerationDurationUs'),
      conversationMode: map['conversationMode']! as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GenerationMetrics &&
      other.modelName == modelName &&
      other.modelFileSizeBytes == modelFileSizeBytes &&
      other.nativeContextLength == nativeContextLength &&
      other.allocatedContextLength == allocatedContextLength &&
      other.promptTokenCount == promptTokenCount &&
      other.reservedOutputTokens == reservedOutputTokens &&
      other.generatedTokenCount == generatedTokenCount &&
      other.firstTokenLatency == firstTokenLatency &&
      other.totalGenerationDuration == totalGenerationDuration &&
      other.conversationMode == conversationMode &&
      other.plannerDuration == plannerDuration &&
      other.searchDuration == searchDuration &&
      other.documentRetrievalDuration == documentRetrievalDuration &&
      other.ragTokenCount == ragTokenCount &&
      other.memoryTokenCount == memoryTokenCount;

  @override
  int get hashCode => Object.hash(
        modelName,
        modelFileSizeBytes,
        nativeContextLength,
        allocatedContextLength,
        promptTokenCount,
        reservedOutputTokens,
        generatedTokenCount,
        firstTokenLatency,
        totalGenerationDuration,
        conversationMode,
        plannerDuration,
        searchDuration,
        documentRetrievalDuration,
        ragTokenCount,
        memoryTokenCount,
      );
}
