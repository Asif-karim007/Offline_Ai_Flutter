// On-device evaluation of the app as a *tutor*: can a student learn a topic from it without
// searching anywhere else?
//
//   flutter build apk --debug -t integration_test/learning_eval_app.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb shell am start -n net.salebee.offline_ai_chat/.MainActivity
//   adb logcat -s flutter | grep "EVAL|"
//
// Each lesson is a short conversation, the way students actually study: a first question,
// then follow-ups ("simpler", "quiz me", "is my answer right?"). Every turn goes through the
// real pipeline — router, textbook search, prompt assembly, the on-device model — with web
// search off. Results go to logcat (no VM-service attach; see math_eval_app.dart for why).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:offline_ai_chat/agent/agent_event.dart';
import 'package:offline_ai_chat/agent/agent_request.dart';
import 'package:offline_ai_chat/app/app_coordinator.dart';
import 'package:offline_ai_chat/curriculum/curriculum_service.dart';
import 'package:offline_ai_chat/domain/chat_message.dart';
import 'package:offline_ai_chat/domain/chat_role.dart';
import 'package:offline_ai_chat/viewmodels/app_view_model.dart';
import 'package:path_provider/path_provider.dart';

/// Preferred model; falls back to whatever chat model is installed on the device.
const String _preferredModel = String.fromEnvironment(
  'EVAL_MODEL',
  defaultValue: 'gemma-4-E2B_q4_0-it.gguf',
);
const String _packId = 'general_class-9-10_bn';

/// (subject, turns, what a good tutor's answer must contain — for grading the log).
const List<(String, List<String>, String)> _lessons = [
  (
    'Physics (BN)',
    [
      'নিউটনের গতির তৃতীয় সূত্রটি উদাহরণসহ ব্যাখ্যা করো।',
      'আরো সহজ করে বুঝিয়ে দাও, দৈনন্দিন জীবনের একটা উদাহরণ দিয়ে।',
    ],
    'action = −reaction, equal & opposite, on different bodies; simple everyday example',
  ),
  (
    'Biology (EN)',
    [
      'What is the difference between mitosis and meiosis?',
      'Give me a 3-question quiz on this, with answers at the end.',
    ],
    'mitosis: 2 identical diploid cells, growth/repair; meiosis: 4 haploid gametes, '
        'crossing over; a sensible quiz',
  ),
  (
    'Chemistry (BN)',
    ['অণু ও পরমাণুর মধ্যে পার্থক্য লেখো।'],
    'atom = smallest particle of an element; molecule = 2+ atoms bonded; examples (O, O₂)',
  ),
  (
    'History (BN)',
    ['১৯৫২ সালের ভাষা আন্দোলন কেন হয়েছিল এবং এর গুরুত্ব কী?'],
    'Urdu as sole state language; 21 Feb 1952 shootings; Bangla recognised; seed of '
        'nationalism; 21 Feb = International Mother Language Day',
  ),
  (
    'English grammar (EN)',
    [
      'Teach me the present perfect tense with 3 examples and a short practice exercise.',
      "Is this correct: 'I have went to Dhaka last year.'",
    ],
    'have/has + past participle; correction: "I went to Dhaka last year" (finished '
        'past time → simple past) or "I have been to Dhaka"',
  ),
  (
    'Math (BN)',
    [
      'x² − 5x + 6 = 0 সমীকরণটি সমাধান করো।',
      'আমি উত্তর পেয়েছি x = 1 এবং x = 6। এটা কি ঠিক?',
    ],
    'x = 2, 3; the student\'s 1 and 6 are wrong (1 + 6 ≠ 5 as needed: they used product 6, '
        'sum 7); explain kindly',
  ),
  (
    'Math (EN)',
    ['Solve for x: 2x² − 7x + 3 = 0. Show the steps.'],
    'x = 3 or x = 1/2, working before the answer',
  ),
  (
    'Math (BN)',
    ['২০০০ টাকার বার্ষিক ৫% হারে ৩ বছরের চক্রবৃদ্ধি মুনাফা কত?'],
    '2000 × (1.05³ − 1) = 315.25 টাকা',
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Running learning evaluation…')))));
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
  // The app's real default length, so the run shows what a student actually gets.
  final installed = await coordinator.modelStore.installedModels();
  final names = installed.map((model) => model.fileName).toList();
  final modelFileName = names.contains(_preferredModel) ? _preferredModel : names.first;
  settings.selectedModelFileName = modelFileName;

  final app = AppViewModel.fromCoordinator(coordinator);
  await app.bootstrap();
  if (!app.loadingState.isReady) throw StateError(app.loadingState.statusText);
  _log('MODEL $modelFileName loaded (installed: ${names.join(', ')}), '
      'maxResponseTokens=${settings.maxResponseTokens}');

  final curriculum = coordinator.curriculum;
  await curriculum.refreshManifest();
  final pack = curriculum.manifest?.byId(_packId);
  if (pack != null) {
    if (curriculum.statusOf(pack) != CurriculumPackStatus.installed) {
      await curriculum.download(pack);
    }
    await curriculum.activate(pack);
  }
  _log('PACK active=${curriculum.activePackId} error=${curriculum.errorMessage}');

  // Phone vendors (Xiaomi's MiuiMemoryService, seen killing this app three times in one run)
  // stop a 3 GB process the moment it leaves the screen, and the app is then relaunched from
  // the top. Progress is kept in a file so a relaunch continues where it was killed instead
  // of repeating finished lessons.
  final progress = File('${(await getApplicationSupportDirectory()).path}/eval_progress_$modelFileName');
  final firstLesson = await progress.exists() ? int.parse(await progress.readAsString()) : 0;
  if (firstLesson > 0) _log('RESUMING at lesson ${firstLesson + 1}');

  for (var lesson = firstLesson; lesson < _lessons.length; lesson++) {
    final (subject, turns, rubric) = _lessons[lesson];
    await app.agentOrchestrator.resetSession();
    await app.chatEngine.resetConversation();
    final history = <ChatMessage>[];
    _log('##### LESSON ${lesson + 1}: $subject\nRUBRIC: $rubric');

    for (var turn = 0; turn < turns.length; turn++) {
      final question = turns[turn];
      history.add(ChatMessage(
        id: 'l$lesson-u$turn',
        role: ChatRole.user,
        content: question,
        createdAt: DateTime.now(),
      ));
      final request = AgentRequest(
        userMessage: question,
        conversationId: null,
        recentMessages: List.of(history),
        attachedDocuments: const [],
        permissions: AgentPermissions.offlineOnly,
      );

      final answer = StringBuffer();
      final sources = <String>[];
      String? finish;
      var generated = 0;
      double? tokensPerSecond;
      Duration? firstToken;
      final started = DateTime.now();
      await for (final event in app.agentOrchestrator
          .handle(request, configuration: settings.currentGenerationConfiguration())) {
        switch (event) {
          case AgentTokenEvent(:final text):
            firstToken ??= DateTime.now().difference(started);
            answer.write(text);
          case AgentProvenanceUpdatedEvent(:final provenance):
            sources
              ..clear()
              ..addAll(provenance.sources.map((s) => '[${s.id}] ${s.title} p${s.page}'));
          case AgentCompletedEvent(:final reason, :final metrics):
            finish = reason.name;
            generated = metrics.generatedTokenCount;
            tokensPerSecond = metrics.tokensPerSecond;
          default:
            break;
        }
      }
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
      history.add(ChatMessage(
        id: 'l$lesson-a$turn',
        role: ChatRole.assistant,
        content: answer.toString(),
        createdAt: DateTime.now(),
      ));
      _log('=== L${lesson + 1}.T${turn + 1} ===\n'
          'QUESTION: $question\n'
          'SOURCES: ${sources.isEmpty ? '(none)' : sources.join(' | ')}\n'
          'STATS: ${seconds.toStringAsFixed(1)}s total, first word after '
          '${((firstToken?.inMilliseconds ?? 0) / 1000).toStringAsFixed(1)}s, $generated tokens, '
          '${tokensPerSecond?.toStringAsFixed(1)} tok/s, finish=$finish\n'
          'ANSWER:\n${answer.toString().trim()}\n'
          '=== END L${lesson + 1}.T${turn + 1} ===');
    }
    await progress.writeAsString('${lesson + 1}');
  }
}

void _log(String message) {
  for (final line in message.split('\n')) {
    debugPrint('EVAL| $line');
  }
}
