import 'dart:io';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

import '../llm/llama_error.dart';
import '../utilities/logger.dart';
import 'model_catalog.dart';
import 'model_store.dart';

/// Where the app is in its start-up sequence.
///
/// A sealed class rather than an enum because `failed` carries a message and the others
/// carry nothing — the same rule that made `ChatSessionMode` a sealed class. The const
/// singletons keep the call sites reading like the Swift enum they came from:
/// `AppLoadingState.loadingModel`, `AppLoadingState.failed(message)`.
sealed class AppLoadingState {
  const AppLoadingState();

  static const AppLoadingState checkingForModel = _CheckingForModel();
  static const AppLoadingState copyingModel = _CopyingModel();
  static const AppLoadingState validatingModel = _ValidatingModel();
  static const AppLoadingState loadingModel = _LoadingModel();
  static const AppLoadingState preparingInferenceEngine = _PreparingInferenceEngine();
  static const AppLoadingState needsModel = _NeedsModel();
  static const AppLoadingState ready = _Ready();

  const factory AppLoadingState.failed(String message) = FailedLoading;

  /// User-visible status text, in the app's current language. Read at render time, so a
  /// language switch mid-launch shows up on the next frame. The English is verbatim,
  /// including the U+2026 ellipsis character — these are three-dot ellipses nowhere in
  /// either app.
  String get statusText;

  bool get isReady => this is _Ready;

  bool get isFailed => this is FailedLoading;
}

final class _CheckingForModel extends AppLoadingState {
  const _CheckingForModel();

  @override
  String get statusText => AppStrings.current.checkingModel;
}

final class _CopyingModel extends AppLoadingState {
  const _CopyingModel();

  @override
  String get statusText => AppStrings.current.copyingModel;
}

final class _ValidatingModel extends AppLoadingState {
  const _ValidatingModel();

  @override
  String get statusText => AppStrings.current.validatingModel;
}

final class _LoadingModel extends AppLoadingState {
  const _LoadingModel();

  @override
  String get statusText => AppStrings.current.loadingModel;
}

final class _PreparingInferenceEngine extends AppLoadingState {
  const _PreparingInferenceEngine();

  @override
  String get statusText => AppStrings.current.preparingEngine;
}

final class _NeedsModel extends AppLoadingState {
  const _NeedsModel();

  @override
  String get statusText => AppStrings.current.noModelInstalled;
}

final class _Ready extends AppLoadingState {
  const _Ready();

  @override
  String get statusText => AppStrings.current.ready;
}

final class FailedLoading extends AppLoadingState {
  const FailedLoading(this.message);

  final String message;

  @override
  String get statusText => message;

  @override
  bool operator ==(Object other) => other is FailedLoading && other.message == message;

  @override
  int get hashCode => Object.hash('failed', message);
}

/// What model discovery concluded.
sealed class ModelResolution {
  const ModelResolution();

  const factory ModelResolution.ready({
    required String fileName,
    required bool bundledModelWasCopied,
  }) = ResolvedModel;

  const factory ModelResolution.needsDownload() = NeedsDownload;
}

final class ResolvedModel extends ModelResolution {
  const ResolvedModel({required this.fileName, required this.bundledModelWasCopied});

  final String fileName;

  /// True only on the launch that performed the bundled-asset copy. The caller flips the
  /// persisted "already copied" flag on the strength of it.
  final bool bundledModelWasCopied;

  @override
  bool operator ==(Object other) =>
      other is ResolvedModel &&
      other.fileName == fileName &&
      other.bundledModelWasCopied == bundledModelWasCopied;

  @override
  int get hashCode => Object.hash(fileName, bundledModelWasCopied);
}

final class NeedsDownload extends ModelResolution {
  const NeedsDownload();

  @override
  bool operator ==(Object other) => other is NeedsDownload;

  @override
  int get hashCode => 'needsDownload'.hashCode;
}

/// First-launch and later-launch model discovery.
///
/// The pipeline, unchanged from the Swift original: the previously selected model if it is
/// still installed, else any installed model (the most recent), else the bundled asset
/// copied out exactly once, else nothing.
class ModelBootstrapService {
  ModelBootstrapService({
    required this.modelStore,
    String? bundledModelFileName,
    AssetBundle? assetBundle,
  })  : bundledModelFileName = bundledModelFileName ?? ModelCatalog.bundledDefault.fileName,
        _assetBundle = assetBundle ?? rootBundle;

  final ModelStore modelStore;

  /// The asset to copy on first launch, defaulting to the catalog's bundled/default entry.
  ///
  /// The Swift constant was `Qwen3-0.6B-Q4_K_M` + `gguf`, resolved through `Bundle.main`.
  /// The port names the current default model instead of the 2025 one; the *mechanism* is
  /// unchanged, and the repository ships no asset either way (see `assets/models/`), so the
  /// bundled path is dead code here exactly as it was there.
  final String bundledModelFileName;

  final AssetBundle _assetBundle;

  String get bundledAssetKey => '$assetDirectory$bundledModelFileName';

  static const String assetDirectory = 'assets/models/';

  /// Runs the pipeline, reporting each phase through [onProgress].
  ///
  /// [onProgress] is awaited, as the Swift closure was, so a caller that drives a UI from it
  /// is guaranteed to have rendered a phase before the next one starts.
  Future<ModelResolution> resolveModel({
    required String? previouslySelectedFileName,
    required bool bundledModelAlreadyCopied,
    required Future<void> Function(AppLoadingState) onProgress,
  }) async {
    await onProgress(AppLoadingState.checkingForModel);

    if (previouslySelectedFileName != null &&
        await modelStore.modelExists(previouslySelectedFileName)) {
      return ResolvedModel(
        fileName: previouslySelectedFileName,
        bundledModelWasCopied: false,
      );
    }

    final installed = await modelStore.installedModels();
    if (installed.isNotEmpty) {
      // Sorted newest first by the store, so the first entry is the most recently installed.
      return ResolvedModel(
        fileName: installed.first.fileName,
        bundledModelWasCopied: false,
      );
    }

    if (!bundledModelAlreadyCopied && await _bundledAssetExists()) {
      await onProgress(AppLoadingState.copyingModel);
      await _copyBundledAsset();

      await onProgress(AppLoadingState.validatingModel);
      if (!await modelStore.modelExists(bundledModelFileName)) {
        throw const LlamaError.modelCopyFailed(
            'copied file missing immediately after copy');
      }

      AppLog.model('model.bundledCopyCompleted');
      return ResolvedModel(
        fileName: bundledModelFileName,
        bundledModelWasCopied: true,
      );
    }

    return const NeedsDownload();
  }

  /// Whether the app was actually built with a bundled model.
  ///
  /// Asked through the asset manifest rather than by catching a failed load, because a
  /// failed `rootBundle.load` of a missing asset and a failed load of a corrupt one look the
  /// same, and one of those should not be treated as "no bundled model, carry on".
  Future<bool> _bundledAssetExists() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(_assetBundle);
      return manifest.listAssets().contains(bundledAssetKey);
    } on Exception {
      // No manifest at all — a test harness with a stub bundle, for instance. Treated as
      // "nothing bundled", which lands on the download screen rather than on an error.
      return false;
    }
  }

  /// Copies the bundled asset into the models directory.
  ///
  /// Flutter has no streaming asset reader: `AssetBundle.load` returns the whole asset as
  /// one `ByteData`, so this briefly holds the entire model in memory — for the 533 MB
  /// default entry that is a real spike on a 3 GB device, and it is why the catalog's larger
  /// entries are downloads rather than bundled assets. The alternative, reading the file out
  /// of the app package directly, needs a platform-specific path that Flutter does not
  /// expose.
  ///
  /// The bytes are written to a temporary file and renamed into place, so an interrupted
  /// first launch cannot leave a truncated `.gguf` that the store would then list as
  /// installed.
  Future<void> _copyBundledAsset() async {
    await modelStore.ensureDirectoryExists();

    final data = await _assetBundle.load(bundledAssetKey);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final destinationPath = modelStore.pathForFileName(bundledModelFileName);
    final staging = File('$destinationPath.copying');

    try {
      await staging.writeAsBytes(bytes, flush: true);
      final destination = File(destinationPath);
      if (await destination.exists()) {
        await destination.delete();
      }
      await staging.rename(destinationPath);
      await modelStore.excludeFromDeviceBackup(File(destinationPath));
    } on FileSystemException catch (error) {
      if (await staging.exists()) {
        await staging.delete();
      }
      if (error.osError?.errorCode == 28) {
        throw const ModelStoreException(ModelStoreErrorKind.insufficientStorage);
      }
      throw LlamaError.modelCopyFailed(error.message);
    } finally {
      // Releases the bundle's cached copy of a several-hundred-megabyte asset that will
      // never be read again.
      _assetBundle.evict(bundledAssetKey);
    }
  }
}
