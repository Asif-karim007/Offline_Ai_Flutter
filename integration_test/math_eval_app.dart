// Evaluation as a plain app entry point — no test runner, no VM-service attach.
//
//   flutter build apk --debug -t integration_test/math_eval_app.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb shell am start -n net.salebee.offline_ai_chat/.MainActivity
//   adb logcat -s flutter | grep "EVAL|"
//
// Same questions and pipeline as math_eval_test.dart. Exists because `flutter test` attaches
// to the app's VM service through an adb port forward, which over *wireless* adb repeatedly
// failed with "Connection closed before full header was received" while the app itself ran
// fine. Results go to logcat, which needs no forward at all.
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:offline_ai_chat/agent/agent_event.dart';
import 'package:offline_ai_chat/agent/agent_request.dart';
import 'package:offline_ai_chat/app/app_coordinator.dart';
import 'package:offline_ai_chat/curriculum/curriculum_service.dart';
import 'package:offline_ai_chat/domain/chat_message.dart';
import 'package:offline_ai_chat/domain/chat_role.dart';
import 'package:offline_ai_chat/viewmodels/app_view_model.dart';

const String _modelFileName = 'Qwen3.5-2B-Q4_K_M.gguf';
const String _packId = 'general_class-9-10_bn';

/// The questions, with the answer a correct solution reaches (for grading the log).
const List<(String, String)> _questions = [
  ('Solve for x: 2x² − 7x + 3 = 0. Show the steps.', 'x = 3 or x = 1/2'),
  ('If sin θ + cos θ = √2, find the value of sin θ · cos θ.', '1/2'),
  (
    'The sum of two numbers is 25 and their product is 144. Find the numbers.',
    '16 and 9'
  ),
  (
    'Find the sum of the first 20 terms of the arithmetic series 3 + 7 + 11 + ...',
    '820'
  ),
  (
    'A ladder 13 m long leans against a wall with its foot 5 m from the wall. How high up '
        'the wall does it reach?',
    '12 m'
  ),
  ('Find the value of (a³ − b³)/(a − b) when a = 3 and b = 2.', '19'),
  ('If log₂(x) + log₂(x − 2) = 3, find x.', 'x = 4 (x = −2 rejected)'),
  ('x² − 5x + 6 = 0 সমীকরণটি সমাধান করো।', 'x = 2, 3'),
  (
    'একটি সমবাহু ত্রিভুজের এক বাহুর দৈর্ঘ্য 6 সেমি হলে, এর ক্ষেত্রফল কত?',
    '9√3 ≈ 15.59 বর্গসেমি'
  ),
  ('যদি a + b = 7 এবং ab = 12 হয়, তবে a² + b² এর মান নির্ণয় করো।', '25'),
  (
    'পিথাগোরাসের উপপাদ্যটি বিবৃত করো এবং প্রমাণ করো।',
    'statement + a valid proof'
  ),
  ('২০০০ টাকার বার্ষিক ৫% হারে ৩ বছরের চক্রবৃদ্ধি মুনাফা কত?', '315.25 টাকা'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Something on screen keeps the activity — and with it the process — in the foreground.
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Running math evaluation…')))));
  try {
    await _run();
    _log('DONE');
  } catch (error, stackTrace) {
    _log('FAILED $error\n$stackTrace');
  }
}

Future<void> _run() async {
  await initializeDateFormatting();
  final coordinator = await AppCoordinator.create();
  final settings = coordinator.settings;
  // Room for full working; the app's default (384) is reported alongside.
  settings.maxResponseTokens = 1024;
  settings.selectedModelFileName = _modelFileName;

  final app = AppViewModel.fromCoordinator(coordinator);
  await app.bootstrap();
  if (!app.loadingState.isReady) throw StateError(app.loadingState.statusText);
  _log('MODEL $_modelFileName loaded');

  final curriculum = coordinator.curriculum;
  await curriculum.refreshManifest();
  final pack = curriculum.manifest!.byId(_packId)!;
  final started = DateTime.now();
  if (curriculum.statusOf(pack) != CurriculumPackStatus.installed) {
    await curriculum.download(pack);
  }
  await curriculum.activate(pack);
  {
    _log(
        'PACK $_packId ready in ${DateTime.now().difference(started).inSeconds}s '
        'error=${curriculum.errorMessage}');
  }

  for (var index = 0; index < _questions.length; index++) {
    final (question, expected) = _questions[index];
    await app.agentOrchestrator.resetSession();
    await app.chatEngine.resetConversation();

    final request = AgentRequest(
      userMessage: question,
      conversationId: null,
      recentMessages: [
        ChatMessage(
          id: 'q$index',
          role: ChatRole.user,
          content: question,
          createdAt: DateTime.now(),
        ),
      ],
      attachedDocuments: const [],
      permissions: AgentPermissions.offlineOnly,
    );

    final answer = StringBuffer();
    final sources = <String>[];
    String? finish;
    var generated = 0;
    double? tokensPerSecond;
    final started = DateTime.now();
    await for (final event in app.agentOrchestrator.handle(request,
        configuration: settings.currentGenerationConfiguration())) {
      switch (event) {
        case AgentTokenEvent(:final text):
          answer.write(text);
        case AgentProvenanceUpdatedEvent(:final provenance):
          sources
            ..clear()
            ..addAll(provenance.sources
                .map((s) => '[${s.id}] ${s.title} p${s.page}'));
        case AgentCompletedEvent(:final reason, :final metrics):
          finish = reason.name;
          generated = metrics.generatedTokenCount;
          tokensPerSecond = metrics.tokensPerSecond;
        default:
          break;
      }
    }
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    _log('=== Q${index + 1} ===\n'
        'QUESTION: $question\n'
        'EXPECTED: $expected\n'
        'SOURCES: ${sources.isEmpty ? '(none)' : sources.join(' | ')}\n'
        'STATS: ${seconds.toStringAsFixed(1)}s, $generated tokens, '
        '${tokensPerSecond?.toStringAsFixed(1)} tok/s, finish=$finish\n'
        'ANSWER:\n${answer.toString().trim()}\n'
        '=== END Q${index + 1} ===');
  }
}

void _log(String message) {
  for (final line in message.split('\n')) {
    debugPrint('EVAL| $line');
  }
}
