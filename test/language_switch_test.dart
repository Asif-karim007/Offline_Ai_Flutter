import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/l10n/app_strings.dart';
import 'package:offline_ai_chat/llm/llama_error.dart';
import 'package:offline_ai_chat/model_management/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same wiring `main.dart` uses: the language setting selected above `MaterialApp`, and
/// the app's delegate alongside the framework's.
Widget _app(AppSettings settings) => ChangeNotifierProvider<AppSettings>.value(
      value: settings,
      child: Selector<AppSettings, AppLanguage>(
        selector: (_, settings) => settings.appLanguage,
        builder: (context, language, _) => MaterialApp(
          locale: language.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Text(AppStrings.of(context).newChat),
          ),
        ),
      ),
    );

void main() {
  testWidgets('switching the language setting relabels the UI and context-free text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();

    settings.appLanguage = AppLanguage.english;
    await tester.pumpWidget(_app(settings));
    expect(find.text('New Chat'), findsOneWidget);

    settings.appLanguage = AppLanguage.bangla;
    await tester.pumpAndSettle();
    expect(find.text('নতুন চ্যাট'), findsOneWidget);
    // Error types have no BuildContext; they follow the same switch through `current`.
    expect(const LlamaError.modelNotLoaded().errorDescription, 'এখন কোনো মডেল লোড করা নেই।');

    settings.appLanguage = AppLanguage.english;
    await tester.pumpAndSettle();
    expect(find.text('New Chat'), findsOneWidget);
    expect(const LlamaError.modelNotLoaded().errorDescription, 'No model is currently loaded.');
  });

  test('the language choice is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.appLanguage, AppLanguage.system);

    settings.appLanguage = AppLanguage.bangla;
    final reloaded = await AppSettings.load();
    expect(reloaded.appLanguage, AppLanguage.bangla);
  });
}
