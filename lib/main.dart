import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app/app_coordinator.dart';
import 'curriculum/curriculum_service.dart';
import 'l10n/app_strings.dart';
import 'model_management/app_settings.dart';
import 'persistence/conversation_repository.dart';
import 'viewmodels/app_view_model.dart';
import 'views/root_view.dart';
import 'views/theme.dart';

Future<void> main() async {
  // Required before any plugin channel is touched, and `AppCoordinator.create` touches three
  // of them — SharedPreferences, path_provider and sqflite.
  WidgetsFlutterBinding.ensureInitialized();

  // Date and time symbols for every locale `intl` knows, not just the UI's: a Bangla question
  // on an English-language phone still gets its date answer formatted in Bangla
  // (`DeviceContextTool`), and that needs the `bn` tables loaded regardless of the UI locale.
  await initializeDateFormatting();

  try {
    final coordinator = await AppCoordinator.create();
    runApp(OfflineAiChatApp(coordinator: coordinator));
  } on AppStartupException catch (error) {
    // The Swift app called `fatalError` here and bricked itself with a crash log. This
    // renders the failure instead: the user gets a sentence they can act on rather than an
    // app that dies on launch with no explanation.
    runApp(StartupFailureApp(message: error.message));
  }
}

class OfflineAiChatApp extends StatefulWidget {
  const OfflineAiChatApp({super.key, required this.coordinator});

  final AppCoordinator coordinator;

  @override
  State<OfflineAiChatApp> createState() => _OfflineAiChatAppState();
}

class _OfflineAiChatAppState extends State<OfflineAiChatApp> {
  late final AppViewModel _appViewModel =
      AppViewModel.fromCoordinator(widget.coordinator);

  @override
  void dispose() {
    _appViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Above `MaterialApp`, so that anything presented through the root navigator — the
        // settings sheet and the debug sheet both are — still finds them.
        Provider<AppCoordinator>.value(value: widget.coordinator),
        Provider<ConversationRepository>.value(value: widget.coordinator.repository),
        ChangeNotifierProvider<AppSettings>.value(value: widget.coordinator.settings),
        ChangeNotifierProvider<CurriculumService>.value(value: widget.coordinator.curriculum),
        ChangeNotifierProvider<AppViewModel>.value(value: _appViewModel),
      ],
      // Only the language is selected here, so changing any other setting does not rebuild
      // the whole app.
      child: Selector<AppSettings, AppLanguage>(
        selector: (_, settings) => settings.appLanguage,
        builder: (context, language, _) => MaterialApp(
          onGenerateTitle: (context) => AppStrings.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: language.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: _localizationsDelegates,
          localeResolutionCallback: _resolveLocale,
          home: const RootView(),
        ),
      ),
    );
  }
}

const List<LocalizationsDelegate<Object>> _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Bangla for a device in Bangla (`bn`, `bn_BD`, `bn_IN`), English for everything else —
/// including when the device lists Bangla only as a second preference, which is what the
/// default resolution would also pick and is the least surprising outcome.
Locale _resolveLocale(Locale? deviceLocale, Iterable<Locale> supported) =>
    deviceLocale?.languageCode == 'bn' ? const Locale('bn') : const Locale('en');

/// The one screen that exists outside the dependency graph, because the graph is what failed.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // No settings exist here — loading them is part of what failed — so this follows the
    // device language.
    return MaterialApp(
      onGenerateTitle: (context) => AppStrings.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      localeResolutionCallback: _resolveLocale,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.exclamationmarkTriangleFill,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.of(context).appTitle,
                    style: AppText.title(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: AppText.subheadline(context).copyWith(
                      color: AppColors.secondaryLabel(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
