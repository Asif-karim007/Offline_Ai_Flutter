import '../domain/chat_message.dart';
import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';

enum GenerationFinishReason {
  endOfSequence('endOfSequence'),
  maxTokensReached('maxTokensReached'),
  cancelled('cancelled');

  const GenerationFinishReason(this.wireValue);

  final String wireValue;

  static GenerationFinishReason fromWireValue(String value) =>
      GenerationFinishReason.values.firstWhere(
        (reason) => reason.wireValue == value,
        orElse: () => GenerationFinishReason.endOfSequence,
      );
}

/// One item in a generation stream: either a chunk of text, or the terminal summary.
sealed class GenerationEvent {
  const GenerationEvent();

  const factory GenerationEvent.token(String text) = TokenEvent;

  const factory GenerationEvent.finished({
    required GenerationFinishReason reason,
    required GenerationMetrics metrics,
  }) = FinishedEvent;
}

final class TokenEvent extends GenerationEvent {
  const TokenEvent(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TokenEvent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class FinishedEvent extends GenerationEvent {
  const FinishedEvent({required this.reason, required this.metrics});

  final GenerationFinishReason reason;
  final GenerationMetrics metrics;

  @override
  bool operator ==(Object other) =>
      other is FinishedEvent && other.reason == reason && other.metrics == metrics;

  @override
  int get hashCode => Object.hash(reason, metrics);
}

/// The only inference abstraction the rest of the app knows about.
///
/// Nothing above this interface imports `dart:ffi`, touches a pointer, or knows that
/// llama.cpp exists — which is what lets the view models and the whole agent pipeline be
/// tested against `MockChatEngine` with no native library present.
abstract interface class ChatEngine {
  Future<void> loadModel({
    required String path,
    required GenerationConfiguration configuration,
  });

  /// Rebuilds the full prompt from [messages] and streams the response as it is produced.
  ///
  /// Callers pass complete, untrimmed history: the engine does its own token-budget trimming
  /// internally, because only it can count tokens with the model's real tokenizer.
  ///
  /// Cancel by cancelling the subscription. The underlying native loop stops within one
  /// token — or one batch, during prefill.
  Stream<GenerationEvent> generate({
    required List<ChatMessage> messages,
    required GenerationConfiguration configuration,
  });

  Future<int> countTokens(List<ChatMessage> messages);

  /// A short, non-streamed generation for internal structured use — the JSON planner and
  /// memory compaction — rather than a user-facing turn.
  ///
  /// Clears and rebuilds the KV cache exactly as [generate] does, using a temporary sampler
  /// chain so the persistent conversational chain is never disturbed. The result is never
  /// streamed and never shown to the user.
  ///
  /// [grammar] is accepted but no call site in this app passes one: grammar-constrained
  /// sampling is the documented source of the C++ exceptions the native shim exists to
  /// contain, and it was observed crashing on Qwen3's `<think>` preamble. Structural
  /// correctness comes from tolerant parsing plus a deterministic fallback instead.
  Future<String> generateStructured({
    required List<({String role, String content})> messages,
    required GenerationConfiguration configuration,
    required int maxTokens,
    String? grammar,
  });

  /// Clears the active KV cache without unloading model weights. This is what switching
  /// conversations does — reloading a multi-gigabyte model to start a new chat would be
  /// absurd, and is exactly what the one-model-one-context design avoids.
  Future<void> resetConversation();

  Future<void> unloadModel();

  Future<bool> get isModelLoaded;

  /// The context length actually allocated, after clamping to the model's trained length.
  /// Zero when no model is loaded.
  Future<int> get currentAllocatedContextLength;
}
