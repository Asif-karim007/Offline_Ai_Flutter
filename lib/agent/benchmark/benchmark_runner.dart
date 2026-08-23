import 'dart:io';

import '../../domain/chat_message.dart';
import '../../domain/chat_role.dart';
import '../../domain/generation_configuration.dart';
import '../../llm/chat_engine.dart';
import '../agent_id.dart';
import 'benchmark_result.dart';

/// Debug-only instrumentation for comparing models and devices on first-token latency,
/// generation speed and resident memory. Model load time is timed separately by whatever calls
/// `loadModel`.
///
/// Never wired into production UI — reachable only from the settings debug section, itself gated
/// behind a debug-metrics flag. This decides nothing on its own and fabricates no numbers: every
/// value comes from a real generation run against whichever model is currently loaded. Use it on
/// a physical device; a simulator is CPU-only and not representative.
class BenchmarkRunner {
  const BenchmarkRunner({required ChatEngine chatEngine}) : _chatEngine = chatEngine;

  final ChatEngine _chatEngine;

  static const List<String> defaultPrompts = [
    'Explain what a Swift actor is in two sentences.',
    'Write a short haiku about offline software.',
    'List three benefits of on-device AI inference.',
    'Summarize why prompt caching improves latency.',
  ];

  /// Runs each prompt as its own single-turn conversation, resetting the KV cache between runs
  /// so later prompts are not advantaged by a warm cache, and sequentially — concurrent
  /// generation is unsupported by the engine and would not be representative anyway.
  ///
  /// A prompt whose generation fails is skipped rather than aborting the whole run; a partial
  /// table of real numbers is more useful than none.
  Future<List<BenchmarkResult>> run({
    List<String> prompts = defaultPrompts,
    required GenerationConfiguration configuration,
  }) async {
    final results = <BenchmarkResult>[];
    for (final prompt in prompts) {
      await _chatEngine.resetConversation();
      final message = ChatMessage(
        id: newAgentId(),
        role: ChatRole.user,
        content: prompt,
        createdAt: DateTime.now(),
      );
      try {
        final stream = _chatEngine
            .generate(messages: [message], configuration: configuration);
        await for (final event in stream) {
          if (event is! FinishedEvent) continue;
          final metrics = event.metrics;
          results.add(BenchmarkResult(
            id: newAgentId(),
            promptLabel:
                prompt.length <= 40 ? prompt : prompt.substring(0, 40),
            modelName: metrics.modelName,
            promptTokenCount: metrics.promptTokenCount,
            generatedTokenCount: metrics.generatedTokenCount,
            firstTokenLatency: metrics.firstTokenLatency,
            totalDuration: metrics.totalGenerationDuration,
            tokensPerSecond: metrics.tokensPerSecond,
            residentMemoryBytesAfter: _currentResidentMemoryBytes(),
          ));
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  /// Swift read this from Mach's `task_info(MACH_TASK_BASIC_INFO)`. `ProcessInfo.currentRss` is
  /// the direct Dart equivalent — resident set size of the running process in bytes — so the
  /// figure is comparable in kind, though not to the digit: it counts the whole Flutter process
  /// including the Dart heap, where the Swift number counted a Swift process.
  ///
  /// Returns null on any platform where the VM does not expose it rather than substituting zero,
  /// which would read as a measurement.
  static int? _currentResidentMemoryBytes() {
    try {
      final rss = ProcessInfo.currentRss;
      return rss > 0 ? rss : null;
    } catch (_) {
      return null;
    }
  }
}
