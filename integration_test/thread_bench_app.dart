// Measures prompt-reading and writing speed for several CPU thread counts on the device.
//
//   flutter build apk --debug -t integration_test/thread_bench_app.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb shell am start -n net.salebee.offline_ai_chat/.MainActivity
//   adb logcat -s flutter | grep "BENCH|"
//
// Phones mix fast and slow cores (2 fast + 6 slow on a Snapdragon 732G), and llama.cpp
// splits each step evenly across threads, so the fastest thread count is a measurement, not
// a formula. Each count gets a fresh model load, one warm-up run, then a timed run over the
// same Bangla prompt.
import 'package:flutter/material.dart';
import 'package:offline_ai_chat/app/app_coordinator.dart';
import 'package:offline_ai_chat/domain/chat_message.dart';
import 'package:offline_ai_chat/domain/chat_role.dart';
import 'package:offline_ai_chat/domain/generation_configuration.dart';
import 'package:offline_ai_chat/domain/generation_metrics.dart';
import 'package:offline_ai_chat/llm/chat_engine.dart';

const List<int> _threadCounts = [2, 4, 6, 8];

const String _prompt = 'নিউটনের গতির তৃতীয় সূত্র: যখন একটি বস্তু অন্য একটি বস্তুর ওপর বল প্রয়োগ '
    'করে তখন সেই বস্তুটিও প্রথম বস্তুটির ওপর বিপরীত দিকে সমান বল প্রয়োগ করে। বন্দুক থেকে গুলি '
    'ছোড়ার সময় বন্দুক পেছনের দিকে ধাক্কা দেয়। নৌকা থেকে লাফ দিলে নৌকা পেছনে সরে যায়। এই সূত্রটি '
    'দুটি উদাহরণ দিয়ে সহজ ভাষায় ব্যাখ্যা করো।';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Running thread benchmark…')))));
  try {
    await _run();
    _log('DONE');
  } catch (error, stackTrace) {
    _log('FAILED $error\n$stackTrace');
  }
}

Future<void> _run() async {
  final coordinator = await AppCoordinator.create();
  final engine = coordinator.chatEngine;
  final models = await coordinator.modelStore.installedModels();
  final model = models.first;
  _log('MODEL ${model.fileName}');

  for (final threads in _threadCounts) {
    final configuration = GenerationConfiguration.standard(gpuLayers: 0).copyWith(
      systemPrompt: 'You are a helpful tutor.',
      maxNewTokens: 48,
      deterministicSeed: 7,
      threadCount: threads,
    );
    await engine.unloadModel();
    await engine.loadModel(
      path: coordinator.modelStore.pathForFileName(model.fileName),
      configuration: configuration,
    );
    for (final timed in [false, true]) {
      await engine.resetConversation();
      GenerationMetrics? metrics;
      await for (final event in engine.generate(
        messages: [
          ChatMessage(id: 'b', role: ChatRole.user, content: _prompt, createdAt: DateTime.now()),
        ],
        configuration: configuration,
      )) {
        if (event is FinishedEvent) metrics = event.metrics;
      }
      if (!timed || metrics == null) continue;
      final prefill = metrics.firstTokenLatency ?? Duration.zero;
      final total = metrics.totalGenerationDuration ?? Duration.zero;
      final decodeSeconds = (total - prefill).inMilliseconds / 1000;
      final prefillTps = metrics.promptTokenCount / (prefill.inMilliseconds / 1000);
      final decodeTps = decodeSeconds > 0 ? (metrics.generatedTokenCount - 1) / decodeSeconds : 0;
      _log('threads=$threads prompt=${metrics.promptTokenCount} tok '
          'read=${prefillTps.toStringAsFixed(1)} tok/s write=${decodeTps.toStringAsFixed(2)} tok/s');
    }
  }
}

void _log(String message) => debugPrint('BENCH| $message');
