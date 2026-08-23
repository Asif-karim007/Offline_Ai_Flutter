import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_coordinator.dart';
import 'model_management/app_settings.dart';
import 'persistence/conversation_repository.dart';
import 'viewmodels/app_view_model.dart';
import 'views/root_view.dart';
import 'views/theme.dart';

Future<void> main() async {
  // Required before any plugin channel is touched, and `AppCoordinator.create` touches three
  // of them — SharedPreferences, path_provider and sqflite.
  WidgetsFlutterBinding.ensureInitialized();

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
        ChangeNotifierProvider<AppViewModel>.value(value: _appViewModel),
      ],
      child: MaterialApp(
        title: 'Offline AI Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const RootView(),
      ),
    );
  }
}

/// The one screen that exists outside the dependency graph, because the graph is what failed.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline AI Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
                    'Offline AI Chat',
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
