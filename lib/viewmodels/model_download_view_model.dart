import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

/// Downloads the one model the first-run screen offers.
///
/// Created lazily, when the user presses the download button, and thrown away when they
/// dismiss a download error — which is what makes a second press start clean.
class ModelDownloadViewModel extends ChangeNotifier {
  ModelDownloadViewModel({
    required ModelStore modelStore,
    ModelDownloader Function()? downloaderFactory,
  })  : _modelStore = modelStore,
        _downloaderFactory = downloaderFactory ?? ModelDownloader.new;

  final ModelStore _modelStore;
  final ModelDownloader Function() _downloaderFactory;

  /// The recommended download, carried over verbatim from the Swift
  /// `ModelDownloadViewModel`.
  ///
  /// **These deliberately do not come from `ModelCatalog`, and a reviewer should decide
  /// whether that is right.** The catalog is new in the port and recommends
  /// `Qwen3.5-0.8B-Q4_K_M` (533 MB); these constants, the body copy on the setup screen
  /// ("…the recommended starter model is Qwen3-0.6B.") and the button's "639.4 MB" are the
  /// iOS app's, and the porting rules make user-visible strings verbatim. Switching to
  /// `ModelCatalog.bundledDefault` would change all three at once and is a product decision,
  /// not a translation.
  static final Uri recommendedModelUrl = Uri.parse(
      'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf');

  static const String recommendedModelFileName = 'Qwen3-0.6B-Q8_0.gguf';

  /// The literal the Swift view formatted into the download button's label.
  static const int recommendedModelSizeBytes = 639446688;

  ModelDownloadState _state = ModelDownloadState.idle;

  ModelDownloadState get state => _state;

  bool get isDownloading => _state is Downloading;

  ModelDownloader? _downloader;
  StreamSubscription<ModelDownloadEvent>? _subscription;

  /// Starts the transfer. [onComplete] receives the finished file's path.
  ///
  /// Fire-and-forget by design: the caller is a button, and every outcome is reported through
  /// [state] rather than through the returned future.
  void startDownload({
    required Future<void> Function(String filePath) onComplete,
  }) {
    if (isDownloading) {
      return;
    }
    _setState(const ModelDownloadState.downloading(bytesWritten: 0, totalBytes: 0));
    unawaited(_run(onComplete));
  }

  Future<void> _run(Future<void> Function(String filePath) onComplete) async {
    try {
      await _modelStore.ensureDirectoryExists();
      final destination = _modelStore.pathForFileName(recommendedModelFileName);
      final downloader = _downloaderFactory();
      _downloader = downloader;

      final completer = Completer<void>();
      final subscription = downloader
          .download(url: recommendedModelUrl, destinationPath: destination)
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
