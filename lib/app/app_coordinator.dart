import 'package:llama_bindings/llama_bindings.dart' show isLlamaLibraryAvailable;

import '../llm/chat_engine.dart';
import '../llm/llama_engine.dart';
import '../llm/model_metadata_reader.dart';
import '../llm/stub_chat_engine.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_bootstrap_service.dart';
import '../model_management/model_downloader.dart';
import '../model_management/model_importer.dart';
import '../model_management/model_store.dart';
import '../persistence/conversation_repository.dart';
import '../persistence/sqflite_conversation_repository.dart';
import '../utilities/logger.dart';

/// The loading states the root view switches on, re-exported so a view model importing the
/// coordinator does not also have to know which model-management file declares them.
export '../model_management/model_bootstrap_service.dart'
    show AppLoadingState, FailedLoading, ModelResolution, NeedsImport, ResolvedModel;

/// Start-up failed in a way the app cannot continue from.
///
/// The Swift original called `fatalError` when the SwiftData container could not be created,
/// which bricked the app with a crash and no recovery path. This is thrown instead: the same
/// condition, but reported rather than aborted, so `main()` can render an explicit error
/// screen offering the one recovery that actually works — clearing the store.
class AppStartupException implements Exception {
  const AppStartupException(this.message);

  final String message;

  @override
  String toString() => 'AppStartupException: $message';
}

/// Owns every top-level, app-lifetime dependency.
///
/// Constructed exactly once, in `main()`, and handed down. The construction order below is
/// the Swift `AppCoordinator.init` order, and it is not arbitrary: the store must exist
/// before anything that reads from it, and the engine before anything that holds a reference
/// to it.
///
/// **This file deliberately contains no widgets.** The Swift `AppCoordinator.swift` also held
/// `RootView`; that half belongs to `lib/views/` here, and this half is plain Dart that can
/// be constructed in a test with no `WidgetsApp` around it.
///
/// Two members of the Swift graph are absent because they belong to another layer:
/// `LocalDocumentManager` and `AgentOrchestrator` are built by the agent layer, and
/// `AppViewModel` by the view-model layer. The seam between them is
/// [webSearchApiKeyProvider], which reproduces the one piece of wiring the Swift coordinator
/// contributed to the orchestrator.
class AppCoordinator {
  AppCoordinator._({
    required this.repository,
    required this.chatEngine,
    required this.settings,
    required this.modelStore,
    required this.bootstrapService,
    required this.modelImporter,
    required this.metadataReader,
  });

  /// Builds the graph.
  ///
  /// Async where the Swift version was synchronous, because three of these — the database
  /// file, `SharedPreferences` and the application support directory — are futures on
  /// Flutter and were synchronous calls on iOS. Resolving them here, once, is what keeps
  /// every consumer of this graph free of a "not loaded yet" state.
  static Future<AppCoordinator> create() async {
    // 1. Persistence first, matching the Swift order and for the same reason: it is the one
    //    dependency whose failure is fatal, and finding that out before a multi-gigabyte
    //    model load starts is cheaper than finding out after.
    final SqfliteConversationRepository repository;
    try {
      repository = await SqfliteConversationRepository.open();
    } on Object catch (error) {
      throw AppStartupException('Failed to open the conversation store: $error');
    }

    // 2. The single, app-lifetime inference engine. One engine means one `llama_context`
    //    and one set of model weights in memory for the life of the process — switching
    //    conversations resets the KV cache rather than reloading the model.
    //
    //    Probed rather than assumed. The llama.cpp shim is built by
    //    `scripts/build_llama_{android,ios}.sh` and is not in the repository, so on a fresh
    //    clone there is no `lc_*` symbol to call. `LlamaEngine` would spawn its worker with
    //    `errorsAreFatal: true` and take the app down on the first message; `StubChatEngine`
    //    keeps every other screen usable and says what to run instead. The probe is one
    //    `dlsym` on the UI isolate and re-runs on every launch, so building the library is
    //    all it takes to get the real engine back.
    final ChatEngine chatEngine;
    if (isLlamaLibraryAvailable()) {
      chatEngine = LlamaEngine();
    } else {
      chatEngine = StubChatEngine();
      AppLog.ui('app.nativeLibraryMissing.usingStubEngine');
    }

    // 3. Settings, read once from SharedPreferences.
    final settings = await AppSettings.load();

    // 4. The models directory.
    final modelStore = await ModelStore.open();

    final coordinator = AppCoordinator._(
      repository: repository,
      chatEngine: chatEngine,
      settings: settings,
      modelStore: modelStore,
      // Created from the store, as the Swift `AppViewModel.init` did — they are pure
      // functions of it and hold no state of their own.
      bootstrapService: ModelBootstrapService(modelStore: modelStore),
      modelImporter: ModelImporter(modelStore),
      metadataReader: const ModelMetadataReader(),
    );

    AppLog.ui('app.graphConstructed');
    return coordinator;
  }

  /// The persistence boundary. Deliberately not published through a global provider in the
  /// Swift app either — it is passed by explicit constructor argument so the set of things
  /// that can write to the database stays enumerable.
  final ConversationRepository repository;

  final ChatEngine chatEngine;

  final AppSettings settings;

  final ModelStore modelStore;

  final ModelBootstrapService bootstrapService;

  final ModelImporter modelImporter;

  final ModelMetadataReader metadataReader;

  /// Re-reads the keychain on every call, and is meant to be called per request rather than
  /// held.
  ///
  /// This is the Dart form of the closure the Swift coordinator passed as
  /// `AgentOrchestrator(webSearchServiceProvider:)`. Keeping it a function rather than a
  /// resolved value is the whole point: configuring or changing the Brave API key in
  /// Settings takes effect on the very next message, with no restart. A non-null result
  /// selects the Brave provider; a null one selects the zero-configuration fallback, which
  /// is why web search works out of the box.
  Future<String?> webSearchApiKeyProvider() => settings.currentBraveApiKey();

  /// A fresh downloader per download.
  ///
  /// Not a shared instance: a downloader owns the state of one transfer — its subscription,
  /// its partial file, its cancellation flag — and reusing one across two downloads would
  /// have the second cancel the first.
  ModelDownloader createModelDownloader() => ModelDownloader();

  /// Releases everything the graph holds. Called when the app is torn down, and by tests
  /// between cases.
  Future<void> dispose() async {
    settings.dispose();
    await chatEngine.unloadModel();
    final store = repository;
    if (store is SqfliteConversationRepository) {
      await store.close();
    }
  }
}
