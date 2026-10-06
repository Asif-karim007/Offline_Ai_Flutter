import 'package:flutter/foundation.dart';

import '../agent/benchmark/benchmark_result.dart';
import '../agent/benchmark/benchmark_runner.dart';
import '../domain/local_model_info.dart';
import '../l10n/app_strings.dart';
import '../llm/chat_engine.dart';
import '../llm/model_metadata_reader.dart';
import '../model_management/app_settings.dart';
import '../model_management/model_store.dart';
import 'error_text.dart';

/// The settings sheet's model half: the installed list, the active model's metadata, model
/// switching, and the debug benchmark.
class ModelManagerViewModel extends ChangeNotifier {
  ModelManagerViewModel({
    required ModelStore modelStore,
    required ChatEngine chatEngine,
    required AppSettings settings,
    ModelMetadataReader metadataReader = const ModelMetadataReader(),
  })  : _modelStore = modelStore,
        _chatEngine = chatEngine,
        _settings = settings,
        _metadataReader = metadataReader;

  final ModelStore _modelStore;
  final ChatEngine _chatEngine;
  final AppSettings _settings;
  final ModelMetadataReader _metadataReader;

  List<LocalModelInfo> _installedModels = const [];
  bool _isLoadingList = false;
  bool _isSwitchingModel = false;
  ModelMetadata? _loadedModelMetadata;
  List<BenchmarkResult> _benchmarkResults = const [];
  bool _isBenchmarking = false;
  String? _errorMessage;

  List<LocalModelInfo> get installedModels => List.unmodifiable(_installedModels);

  /// Never read by any view, in either app. Kept because it is part of the ported surface and
  /// costs nothing.
  bool get isLoadingList => _isLoadingList;

  bool get isSwitchingModel => _isSwitchingModel;

  ModelMetadata? get loadedModelMetadata => _loadedModelMetadata;

  List<BenchmarkResult> get benchmarkResults => List.unmodifiable(_benchmarkResults);

  bool get isBenchmarking => _isBenchmarking;

  /// Drives the "Error" alert; cleared by its "OK" button.
  String? get errorMessage => _errorMessage;

  set errorMessage(String? value) {
    if (_errorMessage == value) {
      return;
    }
    _errorMessage = value;
    _notify();
  }

  String? get selectedFileName => _settings.selectedModelFileName;

  Future<void> refresh() async {
    _isLoadingList = true;
    _notify();
    try {
      _installedModels = await _modelStore.installedModels();
      final selected = selectedFileName;
      if (selected != null) {
        await _refreshLoadedMetadata(selected);
      }
    } on Object catch (error) {
      _errorMessage = describeError(error);
    } finally {
      _isLoadingList = false;
      _notify();
    }
  }

  /// Adopts a model that has just finished downloading.
  ///
  /// Downloading a model activates it, for the same reason importing one used to: a user who
  /// waits out a 500 MB transfer wants to use that model, not to add it to a list. The file
  /// is already at its final path in the store by the time this is called — the downloader
  /// renames it into place atomically — so this only refreshes the list and switches.
  Future<void> useDownloadedModel(String fileName) async {
    try {
      await refresh();
      await switchToModel(fileName);
    } on Object catch (error) {
      _errorMessage = describeError(error);
      _notify();
    }
  }

  /// Unloads the current model and loads [fileName].
  ///
  /// **Caller contract:** whoever calls this must already have stopped any generation in
  /// flight. `ModelManagerView` satisfies it by awaiting `onWillSwitchModel` — which is
  /// `ChatViewModel.startNewPersistentChat()` — first, on all three paths (download, switch,
  /// reload). Saved chat history is untouched either way; only the native context is rebuilt.
  Future<void> switchToModel(String fileName) async {
    _isSwitchingModel = true;
    _notify();
    try {
      await _chatEngine.unloadModel();
      await _chatEngine.loadModel(
        path: _modelStore.pathForFileName(fileName),
        configuration: _settings.currentGenerationConfiguration(),
      );
      _settings.selectedModelFileName = fileName;
      await _refreshLoadedMetadata(fileName);
    } on Object catch (error) {
      // The engine is left unloaded on this path — the error alert is the only signal, and
      // the "Status" row goes back to reading "Ready". Preserved from the original.
      _errorMessage = describeError(error);
    } finally {
      _isSwitchingModel = false;
      _notify();
    }
  }

  Future<void> reloadCurrentModel() async {
    final fileName = selectedFileName;
    if (fileName == null) {
      return;
    }
    await switchToModel(fileName);
  }

  /// A second line of defence: the swipe action is already disabled for the active model.
  Future<void> deleteModel(String fileName) async {
    if (fileName == selectedFileName) {
      _errorMessage = AppStrings.current.cannotDeleteActiveModel;
      _notify();
      return;
    }
    try {
      await _modelStore.deleteModel(fileName);
      await refresh();
    } on Object catch (error) {
      _errorMessage = describeError(error);
      _notify();
    }
  }

  /// Debug-only. Produces real numbers from real generations against whichever model is
  /// loaded; it decides nothing on its own and stores nothing anywhere.
  Future<void> runBenchmark() async {
    _isBenchmarking = true;
    _notify();
    try {
      final runner = BenchmarkRunner(chatEngine: _chatEngine);
      // Results replace rather than append — a benchmark table mixing two models would be
      // worse than no table.
      _benchmarkResults = await runner.run(
        configuration: _settings.currentGenerationConfiguration(),
      );
    } on Object catch (error) {
      _errorMessage = describeError(error);
    } finally {
      _isBenchmarking = false;
      _notify();
    }
  }

  /// A failed read clears the metadata rather than reporting it: the rows simply disappear.
  /// Metadata is decoration on this screen, and a probe that fails on a model the engine has
  /// already loaded successfully is not something the user can act on.
  Future<void> _refreshLoadedMetadata(String fileName) async {
    try {
      _loadedModelMetadata =
          await _metadataReader.read(_modelStore.pathForFileName(fileName));
    } on Object {
      _loadedModelMetadata = null;
    }
    _notify();
  }

  bool _disposed = false;

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
