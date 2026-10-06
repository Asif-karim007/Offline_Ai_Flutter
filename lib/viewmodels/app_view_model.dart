import 'package:flutter/foundation.dart';

import '../agent/agent_orchestrator.dart';
import '../agent/documents/local_document_manager.dart';
import '../agent/web/brave_web_search_provider.dart';
import '../agent/web/duckduckgo_html_search_provider.dart';
import '../agent/web/web_search_provider.dart';
import '../agent/web/web_search_service.dart';
import '../app/app_coordinator.dart';
import '../llm/chat_engine.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_bootstrap_service.dart';
import '../model_management/model_store.dart';
import 'error_text.dart';

/// Owns the app's start-up state machine and the long-lived dependency handles the shell
/// hands down to the other view models.
///
/// `ModelBootstrapService.resolveModel` only reports `checkingForModel`, `copyingModel` and
/// `validatingModel`. Everything after discovery — `loadingModel`,
/// `preparingInferenceEngine`, `ready`, `needsModel` and every `failed` — is decided here,
/// exactly as it was in the Swift `AppViewModel`.
class AppViewModel extends ChangeNotifier {
  AppViewModel({
    required this.chatEngine,
    required this.agentOrchestrator,
    required this.documentManager,
    required this.settings,
    required this.modelStore,
    required ModelBootstrapService bootstrapService,
  }) : _bootstrapService = bootstrapService;

  /// Builds the half of the graph `AppCoordinator` deliberately leaves out.
  ///
  /// The coordinator's doc comment names the seam: it constructs everything with an app
  /// lifetime except [LocalDocumentManager], [AgentOrchestrator] and this view model, and
  /// contributes [AppCoordinator.webSearchApiKeyProvider] as the one piece of orchestrator
  /// wiring it owns. This factory closes that seam in one place.
  factory AppViewModel.fromCoordinator(AppCoordinator coordinator) {
    final documentManager = LocalDocumentManager();
    return AppViewModel(
      chatEngine: coordinator.chatEngine,
      agentOrchestrator: AgentOrchestrator(
        chatEngine: coordinator.chatEngine,
        documentManager: documentManager,
        // The *function* is passed, never its result. Resolving the key once here would mean
        // a Brave key configured in Settings never took effect until the next launch, since
        // the orchestrator is constructed exactly once.
        webSearchServiceProvider: () =>
            _webSearchService(coordinator.webSearchApiKeyProvider),
        textbookRetriever: coordinator.curriculum,
      ),
      documentManager: documentManager,
      settings: coordinator.settings,
      modelStore: coordinator.modelStore,
      bootstrapService: coordinator.bootstrapService,
    );
  }

  final ChatEngine chatEngine;
  final AgentOrchestrator agentOrchestrator;
  final LocalDocumentManager documentManager;
  final AppSettings settings;
  final ModelStore modelStore;

  final ModelBootstrapService _bootstrapService;
  AppLoadingState _loadingState = AppLoadingState.checkingForModel;

  AppLoadingState get loadingState => _loadingState;

  void _setLoadingState(AppLoadingState state) {
    if (_loadingState == state) {
      return;
    }
    _loadingState = state;
    notifyListeners();
  }

  /// Runs discovery and, when a model is found, loads it.
  ///
  /// Invoked once when the root view appears, matching the Swift `.task { }` on `RootView`.
  Future<void> bootstrap() async {
    try {
      final resolution = await _bootstrapService.resolveModel(
        previouslySelectedFileName: settings.selectedModelFileName,
        bundledModelAlreadyCopied: settings.hasBundledModelBeenCopied,
        onProgress: (state) async => _setLoadingState(state),
      );

      switch (resolution) {
        case NeedsDownload():
          _setLoadingState(AppLoadingState.needsModel);
        case ResolvedModel(:final fileName, :final bundledModelWasCopied):
          if (bundledModelWasCopied) {
            settings.hasBundledModelBeenCopied = true;
          }
          await _loadModel(fileName);
      }
    } on Object catch (error) {
      _setLoadingState(AppLoadingState.failed(describeError(error)));
    }
  }

  /// Called once a download has finished and the file already sits at its final path in the
  /// model store — this only loads it.
  Future<void> useDownloadedModel(String fileName) => _loadModel(fileName);

  Future<void> retry() async {
    _setLoadingState(AppLoadingState.checkingForModel);
    await bootstrap();
  }

  /// Forgets the selected model without deleting the file, and returns to the setup screen.
  void chooseAnotherModel() {
    settings.selectedModelFileName = null;
    _setLoadingState(AppLoadingState.needsModel);
  }

  Future<void> deleteInvalidModelAndRetry() async {
    final fileName = settings.selectedModelFileName;
    if (fileName != null) {
      // Deliberately swallowed, as in the original: the point of this button is to get back
      // to a working state, and a failed delete must not replace the load error with a
      // delete error the user can do even less about.
      try {
        await modelStore.deleteModel(fileName);
      } on Object {
        // Ignored on purpose — see above.
      }
      settings.selectedModelFileName = null;
    }
    await bootstrap();
  }

  /// `preparingInferenceEngine` is set *after* the load returns and is immediately replaced
  /// by `ready`, so it flashes for at most one frame. That is the Swift behaviour and it is
  /// kept rather than "fixed", because the state exists for the splash copy, not for timing.
  Future<void> _loadModel(String fileName) async {
    _setLoadingState(AppLoadingState.loadingModel);
    try {
      await chatEngine.loadModel(
        path: modelStore.pathForFileName(fileName),
        configuration: settings.currentGenerationConfiguration(),
      );
      _setLoadingState(AppLoadingState.preparingInferenceEngine);
      settings.selectedModelFileName = fileName;
      _setLoadingState(AppLoadingState.ready);
    } on Object catch (error) {
      _setLoadingState(AppLoadingState.failed(describeError(error)));
    }
  }
}

/// Resolves the search service for one request from whatever key is in secure storage now.
///
/// A configured Brave key selects the Brave provider; no key selects the zero-configuration
/// DuckDuckGo fallback, which is why web search works without any setup at all. The service
/// itself is never null — whether a search happens is decided by `AgentPermissions`, not by
/// the absence of a provider.
Future<WebSearchService?> _webSearchService(
  Future<String?> Function() apiKeyProvider,
) async {
  final apiKey = await apiKeyProvider();
  final WebSearchProvider provider = (apiKey != null && apiKey.isNotEmpty)
      ? BraveWebSearchProvider(apiKey: apiKey)
      : DuckDuckGoHtmlSearchProvider();
  return WebSearchService(provider: provider);
}
