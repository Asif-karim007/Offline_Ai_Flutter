import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../l10n/app_strings.dart';

import '../utilities/logger.dart';

/// One item in a download stream.
sealed class ModelDownloadEvent {
  const ModelDownloadEvent();
}

/// Cumulative progress.
///
/// [bytesWritten] is the running total, not the size of the last chunk — the same shape the
/// Swift delegate reported (`totalBytesWritten`, despite the parameter being named
/// `bytesWritten` there too).
final class ModelDownloadProgress extends ModelDownloadEvent {
  const ModelDownloadProgress({required this.bytesWritten, required this.totalBytes});

  final int bytesWritten;

  /// `-1` when the server sent no length, mirroring `NSURLSessionTransferSizeUnknown`. The
  /// UI treats a positive value as determinate and anything else as a spinner with a
  /// bytes-only label, so this must stay `-1` rather than becoming `0` or `null`.
  final int totalBytes;

  bool get isDeterminate => totalBytes > 0;

  double? get fraction =>
      isDeterminate ? (bytesWritten / totalBytes).clamp(0.0, 1.0) : null;

  @override
  bool operator ==(Object other) =>
      other is ModelDownloadProgress &&
      other.bytesWritten == bytesWritten &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(bytesWritten, totalBytes);
}

final class ModelDownloadFinished extends ModelDownloadEvent {
  const ModelDownloadFinished(this.filePath);

  final String filePath;

  @override
  bool operator ==(Object other) =>
      other is ModelDownloadFinished && other.filePath == filePath;

  @override
  int get hashCode => filePath.hashCode;
}

enum ModelDownloadErrorKind { invalidResponse, serverError }

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.kind, {this.statusCode});

  final ModelDownloadErrorKind kind;
  final int? statusCode;

  /// Verbatim from the Swift `ModelDownloadError`.
  String get errorDescription => switch (kind) {
        ModelDownloadErrorKind.invalidResponse =>
          AppStrings.current.errorDownloadInvalidResponse,
        ModelDownloadErrorKind.serverError => AppStrings.current.errorDownloadServer(statusCode),
      };

  @override
  String toString() => errorDescription;
}

/// Streams a GGUF model file to a destination path, with progress, resume and cancellation.
///
/// One instance per download; not reusable concurrently, exactly as the Swift class
/// documented. This is the app's only outbound network code that a user can trigger, and it
/// exists solely to fetch weights on request — nothing in the generation path opens a socket.
///
/// Three things the Swift version left on the table, all of which matter for a file that can
/// be several gigabytes over a phone connection:
///
/// * **Resume.** A partial download is kept at `<destination>.part` and continued with a
///   `Range` header. A server that ignores the range (answering `200` instead of `206`)
///   is handled by starting the file over rather than by appending to it, which would
///   otherwise produce a corrupt file that only fails much later at load time.
/// * **Atomic completion.** Bytes land in the `.part` file and are renamed into place only
///   after the stream completes. The models directory therefore never contains a truncated
///   `.gguf`, and `ModelStore.installedModels` — which filters on the extension — never
///   lists one.
/// * **Backup exclusion.** Callers get the finished file's path and are expected to pass it
///   through `ModelStore.excludeFromDeviceBackup`. In the Swift app downloads bypassed the
///   import path entirely and were the one class of installed model that was never excluded
///   from iCloud backup.
class ModelDownloader {
  ModelDownloader({http.Client? client}) : _injectedClient = client;

  /// Suffix for the in-progress file. Chosen so it fails the `.gguf` extension check.
  static const String partialSuffix = '.part';

  final http.Client? _injectedClient;

  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _streamCompleter;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Downloads [url] to [destinationPath].
  ///
  /// The stream is single-subscription: cancelling the subscription cancels the transfer,
  /// which is how the Swift `continuation.onTermination` hook behaved. [cancel] does the
  /// same thing explicitly for callers that hold the downloader rather than the stream.
  Stream<ModelDownloadEvent> download({
    required Uri url,
    required String destinationPath,
  }) {
    late final StreamController<ModelDownloadEvent> controller;
    controller = StreamController<ModelDownloadEvent>(
      onListen: () => unawaited(_run(url, destinationPath, controller)),
      onCancel: () => cancel(),
    );
    return controller.stream;
  }

  /// Stops the transfer. The partial file is kept so a later call can resume it.
  ///
  /// Cancellation is silent: the stream closes without an error, matching the Swift
  /// delegate's `NSURLErrorCancelled` special case. A user who pressed Stop does not need to
  /// be told that stopping worked.
  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    await _subscription?.cancel();
    _subscription = null;
    // The read loop is parked on this; completing it lets `_run` unwind and close its sink
    // instead of leaking the file handle.
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
  }

  Future<void> _run(
    Uri url,
    String destinationPath,
    StreamController<ModelDownloadEvent> controller,
  ) async {
    final client = _injectedClient ?? http.Client();
    final ownsClient = _injectedClient == null;
    final partialFile = File('$destinationPath$partialSuffix');

    IOSink? sink;
    try {
      final resumeFrom = await partialFile.exists() ? await partialFile.length() : 0;

      final request = http.Request('GET', url);
      if (resumeFrom > 0) {
        request.headers['Range'] = 'bytes=$resumeFrom-';
      }

      final response = await client.send(request);
      if (_cancelled) {
        return;
      }

      final status = response.statusCode;
      if (status != 200 && status != 206) {
        throw ModelDownloadException(
          ModelDownloadErrorKind.serverError,
          statusCode: status,
        );
      }

      // A `206` with no `Content-Range` is a server contradicting itself: it claims to be
      // sending a partial body but will not say which part. Appending blind would silently
      // corrupt the file, so this is refused outright.
      if (status == 206 && !response.headers.containsKey('content-range')) {
        throw const ModelDownloadException(ModelDownloadErrorKind.invalidResponse);
      }

      // A `200` in reply to a `Range` request means the server does not support resuming and
      // is sending the whole file again. Appending would interleave two copies.
      final appending = resumeFrom > 0 && status == 206;
      var received = appending ? resumeFrom : 0;

      final totalBytes = _resolveTotalBytes(
        response: response,
        appending: appending,
        alreadyReceived: received,
      );

      AppLog.model('model.downloadStarted', fields: [
        LogField.count('httpStatus', status),
        LogField.bytes('resumeFrom', appending ? resumeFrom : 0),
        LogField.bytes('expectedTotal', totalBytes),
      ]);

      sink = partialFile.openWrite(
        mode: appending ? FileMode.writeOnlyAppend : FileMode.writeOnly,
      );

      final completer = Completer<void>();
      _streamCompleter = completer;
      _subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          if (!controller.isClosed) {
            controller.add(ModelDownloadProgress(
              bytesWritten: received,
              totalBytes: totalBytes,
            ));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future;

      await sink.flush();
      await sink.close();
      sink = null;

      if (_cancelled) {
        return;
      }

      final destination = File(destinationPath);
      if (await destination.exists()) {
        await destination.delete();
      }
      // Rename, not copy: within one filesystem this is atomic and instant, so the file
      // either is not there or is complete. Copying a 3 GB file to finish a 3 GB download
      // would also need 6 GB free.
      await partialFile.rename(destinationPath);

      AppLog.model('model.downloadFinished',
          fields: [LogField.bytes('size', received)]);

      if (!controller.isClosed) {
        controller.add(ModelDownloadFinished(destinationPath));
      }
    } catch (error, stackTrace) {
      // The partial file is deliberately left on disk: it is the resume point, and a failure
      // halfway through a large download is precisely when a user wants to retry rather than
      // start again.
      if (!_cancelled && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    } finally {
      _subscription = null;
      _streamCompleter = null;
      if (sink != null) {
        // Only reached on a failure path; the success path already closed it.
        try {
          await sink.close();
        } on FileSystemException {
          // Nothing useful to do — the transfer already failed.
        }
      }
      if (ownsClient) {
        client.close();
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  /// Total size of the complete file, or `-1` when the server did not say.
  ///
  /// For a resumed transfer the interesting number is the size of the *whole* file, not of
  /// the remaining range, so the already-received bytes are added back — otherwise a resumed
  /// download would show a progress bar that jumps backwards.
  static int _resolveTotalBytes({
    required http.StreamedResponse response,
    required bool appending,
    required int alreadyReceived,
  }) {
    final contentRange = response.headers['content-range'];
    if (appending && contentRange != null) {
      // `bytes 1024-4095/4096` — the part after the slash is the full length, or `*` when
      // the server does not know it.
      final total = int.tryParse(contentRange.split('/').last.trim());
      if (total != null && total > 0) {
        return total;
      }
    }

    final contentLength = response.contentLength;
    if (contentLength == null || contentLength <= 0) {
      return -1;
    }
    return appending ? contentLength + alreadyReceived : contentLength;
  }
}
