import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_ai_chat/curriculum/curriculum_service.dart';
import 'package:offline_ai_chat/l10n/app_strings.dart';
import 'package:offline_ai_chat/llm/stub_chat_engine.dart';
import 'package:offline_ai_chat/model_management/app_settings.dart';
import 'package:offline_ai_chat/model_management/model_store.dart';
import 'package:offline_ai_chat/viewmodels/model_manager_view_model.dart';
import 'package:offline_ai_chat/views/model_manager_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bangla runs longer than English, so the settings sheet — the densest screen — is laid
/// out in Bangla on a small phone at a large text size. Any overflow fails the test.
void main() {
  testWidgets('settings sheet lays out in Bangla on a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.appLanguage = AppLanguage.bangla;
    settings.debugMetricsEnabled = true; // include the benchmark section too
    final modelsDirectory = Directory.systemTemp.createTempSync('models');
    addTearDown(() => modelsDirectory.deleteSync(recursive: true));
    final curriculum = CurriculumService(
      directory: modelsDirectory,
      settings: settings,
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(curriculum.dispose);
    final viewModel = ModelManagerViewModel(
      modelStore: ModelStore(modelsDirectory),
      chatEngine: StubChatEngine(),
      settings: settings,
    );

    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<ModelManagerViewModel>.value(value: viewModel),
        ChangeNotifierProvider<CurriculumService>.value(value: curriculum),
      ],
      child: MaterialApp(
        locale: const Locale('bn'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ModelManagerView(onWillSwitchModel: () async {}),
      ),
    ));
    await tester.runAsync(() => viewModel.refresh());
    await tester.pump();

    expect(find.text('সেটিংস ও মডেল'), findsOneWidget);
    expect(find.text('ভাষা'), findsWidgets);

    // Scroll the whole sheet through, so every section is laid out at least once.
    await tester.dragUntilVisible(
      find.text('বেঞ্চমার্ক চালান'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(tester.takeException(), isNull);
  });
}
