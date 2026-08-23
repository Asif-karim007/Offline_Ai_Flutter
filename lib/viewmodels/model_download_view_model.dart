import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model_management/model_catalog.dart';
import '../model_management/model_downloader.dart';
import '../model_management/model_store.dart';
import 'error_text.dart';

/// Where the recommended-model download is.
sealed class ModelDownloadState {
  const ModelDownloadState();

  static const ModelDownloadState idle = DownloadIdle();

  const factory ModelDownloadState.downloading({
    required int bytesWritten,
    required int totalBytes,
  }) = Downloading;

  const factory ModelDownloadState.failed(String message) = DownloadFailed;
}

final class DownloadIdle extends ModelDownloadState {
  const DownloadIdle();

  @override
  bool operator ==(Object other) => other is DownloadIdle;

  @override
  int get hashCode => (DownloadIdle).hashCode;
}

final class Downloading extends ModelDownloadState {
  const Downloading({required this.bytesWritten, required this.totalBytes});

  final int bytesWritten;

  /// `-1` (or any non-positive value) means the server sent no length, and the progress bar
  /// is indeterminate.
  final int totalBytes;

  bool get isDeterminate => totalBytes > 0;

  double? get fraction =>
      isDeterminate ? (bytesWritten / totalBytes).clamp(0.0, 1.0) : null;

  @override
  bool operator ==(Object other) =>
      other is Downloading &&
      other.bytesWritten == bytesWritten &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(bytesWritten, totalBytes);
}

final class DownloadFailed extends ModelDownloadState {
  const DownloadFailed(this.message);

  final String message;

  @override
  bool operator ==(Object other) => other is DownloadFailed && other.message == message;

  @override
  int get hashCode => Object.hash('downloadFailed', message);
}

/// Downloads a catalog model.
///
/// Created lazily, when the user presses a download button, and thrown away when they
/// dismiss a download error — which is what makes a second press start clean.
///
/// **Was hardcoded to one URL.** Since importing a `.gguf` by hand is no longer possible,
/// downloading is the only way a model reaches the device, and pinning that to a single
/// file would have capped the app at exactly one model forever. Every entry in
/// [ModelCatalog] already carries the repository, revision and file name needed to build a
/// download URL — see [CatalogModel.downloadUrl] — so the view model now takes the model as
/// an argument and the catalog decides what is on offer.
class ModelDownloadViewModel extends ChangeNotifier {
  ModelDownloadViewModel({
    required ModelStore modelStore,
    ModelDownloader Function()? downloaderFactory,
  })  : _modelStore = modelStore,
        _downloaderFactory = downloaderFactory ?? ModelDownloader.new;

  final ModelStore _modelStore;
  final ModelDownloader Function() _downloaderFactory;

  // No `recommendedModel` constant here. The hardcoded `Qwen3-0.6B-Q8_0` (639.4 MB) URL,
  // file name and size are gone, and the recommendation is not this class's to hold:
  // `CatalogModel.tier` already records it, so the catalog list badges
  // `ModelTier.bundledDefault` directly and there is one source of truth rather than two.
  // (The porting rule that keeps user-visible strings verbatim yields here — the screen
  // that carried those strings no longer exists in the same form.)

  ModelDownloadState _state = ModelDownloadState.idle;

  CatalogModel? _activeModel;

  /// The model currently being fetched, or the last one attempted. Lets a list of models
  /// show progress against the right row.
  CatalogModel? get activeModel => _activeModel;

  ModelDownloadState get state => _state;

  bool get isDownloading => _state is Downloading;

  ModelDownloader? _downloader;
  StreamSubscription<ModelDownloadEvent>? _subscription;

  /// Starts the transfer of [model]. [onComplete] receives the finished file's path.
  ///
  /// Fire-and-forget by design: the caller is a button, and every outcome is reported through
  /// [state] rather than through the returned future.
  void startDownload({
    required CatalogModel model,
    required Future<void> Function(String filePath) onComplete,
  }) {
    if (isDownloading) {
      return;
    }
    _activeModel = model;
    // Seeded with the catalog's published size rather than 0, so the progress bar is
    // determinate from the first frame instead of jumping once the first chunk lands and
    // the server's Content-Length arrives.
    _setState(ModelDownloadState.downloading(
      bytesWritten: 0,
      totalBytes: model.downloadSizeBytes,
    ));
    unawaited(_run(model, onComplete));
  }

  Future<void> _run(
    CatalogModel model,
    Future<void> Function(String filePath) onComplete,
  ) async {
    try {
      await _modelStore.ensureDirectoryExists();
      final destination = _modelStore.pathForFileName(model.fileName);
      final downloader = _downloaderFactory();
      _downloader = downloader;

      final completer = Completer<void>();
      final subscription = downloader
          .download(url: model.downloadUrl, destinationPath: destination)
          .listen(
        (event) {
          switch (event) {
            case ModelDownloadProgress(:final bytesWritten, :final totalBytes):
              _setState(ModelDownloadState.downloading(
                bytesWritten: bytesWritten,
                totalBytes: totalBytes,
              ));
            case ModelDownloadFinished(:final filePath):
              _setState(ModelDownloadState.idle);
              unawaited(onComplete(filePath));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _setState(ModelDownloadState.failed(describeError(error)));
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );
      _subscription = subscription;

      await completer.future;
      await subscription.cancel();
      _subscription = null;
    } on Object catch (error) {
      _setState(ModelDownloadState.failed(describeError(error)));
    } finally {
      _downloader = null;
    }
  }

  /// Cancellation is silent — no error banner. A user who pressed Cancel does not need to be
  /// told that cancelling worked. The partial file stays on disk, so a later attempt resumes.
  void cancelDownload() {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final downloader = _downloader;
    _downloader = null;
    if (downloader != null) {
      unawaited(downloader.cancel());
    }
    _setState(ModelDownloadState.idle);
  }

  void _setState(ModelDownloadState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The file name a finished download landed under, for handing to
  /// `AppViewModel.useDownloadedModel`.
  static String fileNameFromPath(String filePath) => p.basename(filePath);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_downloader?.cancel());
    _downloader = null;
    super.dispose();
  }
}
