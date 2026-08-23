import 'dart:async';
import 'dart:isolate';

import 'package:llama_bindings/llama_bindings.dart';

import '../domain/chat_message.dart';
import '../domain/generation_configuration.dart';
import '../domain/generation_metrics.dart';
import 'chat_engine.dart';
import 'llama_error.dart';
import 'llama_worker.dart';

/// The production [ChatEngine].
///
/// This half runs on whatever isolate constructed it — in practice the UI isolate — and owns
/// no native memory beyond the cancellation flag. All model, context, sampler and batch
/// pointers live in a worker isolate spawned on first use, and stay pinned there for its
/// lifetime, because a `llama_context` is not safe to touch from two places and an FFI
/// pointer cannot be shared across isolates as an object anyway.
///
/// The worker is started lazily and never restarted. If it dies, the engine is dead: a
/// crashed inference isolate means llama.cpp reached a state the shim could not contain, and
/// silently respawning it would paper over exactly the failure the app most needs to report.
class LlamaEngine implements ChatEngine {
  LlamaEngine();

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _replyPort;
  Future<void>? _startup;

  final CancellationFlag _cancellation = CancellationFlag.allocate();

  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final Map<int, StreamController<GenerationEvent>> _streams = {};

  int _nextRequestId = 1;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _ensureStarted() {
    if (_disposed) {
      throw StateError('LlamaEngine has been disposed.');
    }
    return _startup ??= _start();
  }

  Future<void> _start() async {
    final replyPort = ReceivePort();
    _replyPort = replyPort;

    final ready = Completer<SendPort>();

    replyPort.listen((Object? message) {
      if (message is! Map) return;
      final reply = message.cast<String, Object?>();

      if (reply['status'] == WorkerReply.ready) {
        ready.complete(reply['port']! as SendPort);
        return;
      }
      _dispatchReply(reply);
    });

    _isolate = await Isolate.spawn(
      llamaWorkerEntry,
      WorkerBootstrap(
        replyPort: replyPort.sendPort,
        cancellationAddress: _cancellation.address,
      ),
      debugName: 'llama-inference',
      errorsAreFatal: true,
    );

    _commandPort = await ready.future;
  }

  void _dispatchReply(Map<String, Object?> reply) {
    final id = reply['id'] as int?;
    if (id == null) return;

    switch (reply['status']) {
      case WorkerReply.token:
        _streams[id]?.add(GenerationEvent.token(reply['text']! as String));

      case WorkerReply.finished:
        final controller = _streams.remove(id);
        controller?.add(GenerationEvent.finished(
          reason: GenerationFinishReason.fromWireValue(reply['reason']! as String),
          metrics: GenerationMetrics.fromIsolateMap(
              (reply['metrics']! as Map).cast<String, Object?>()),
        ));
        unawaited(controller?.close() ?? Future<void>.value());

      case WorkerReply.error:
        final error =
            LlamaError.fromIsolateMap((reply['error']! as Map).cast<String, Object?>());
        final controller = _streams.remove(id);
        if (controller != null) {
          controller.addError(error);
          unawaited(controller.close());
        }
        _pending.remove(id)?.completeError(error);

      case WorkerReply.ok:
        _pending.remove(id)?.complete(reply);
    }
  }

  Future<Map<String, Object?>> _request(String op, [Map<String, Object?> payload = const {}]) async {
    await _ensureStarted();
    final id = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _commandPort!.send(<String, Object?>{'id': id, 'op': op, ...payload});
    return completer.future;
  }

  /// Shuts the worker down and releases the cancellation flag.
  ///
  /// Safe to call more than once. After this the engine cannot be used again.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _cancellation.cancel();

    for (final controller in _streams.values) {
      unawaited(controller.close());
    }
    _streams.clear();

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const LlamaError.modelNotLoaded());
      }
    }
    _pending.clear();

    _commandPort?.send(<String, Object?>{'id': 0, 'op': WorkerOp.shutdown});

    // Give the worker a moment to free its native resources before killing it. Without this
    // the model's memory mapping is released by process teardown instead of by
    // llama_model_free, which is harmless at app exit but leaks across a hot restart.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replyPort?.close();
    _replyPort = null;
    _commandPort = null;
    _cancellation.dispose();
  }

  // ---------------------------------------------------------------------------
  // ChatEngine
  // ---------------------------------------------------------------------------

  @override
  Future<void> loadModel({
    required String path,
    required GenerationConfiguration configuration,
  }) async {
    await _request(WorkerOp.load, {
      'path': path,
      'configuration': configuration.toIsolateMap(),
    });
  }

  @override
  Future<void> unloadModel() async {
    if (_startup == null) return;
    await _request(WorkerOp.unload);
  }

  @override
  Future<void> resetConversation() async {
    if (_startup == null) return;
    await _request(WorkerOp.reset);
  }

  @override
  Future<bool> get isModelLoaded async {
    if (_startup == null) return false;
    final reply = await _request(WorkerOp.status);
    return reply['isModelLoaded']! as bool;
  }

  @override
  Future<int> get currentAllocatedContextLength async {
    if (_startup == null) return 0;
    final reply = await _request(WorkerOp.status);
    return reply['allocatedContextLength']! as int;
  }

  @override
  Future<int> countTokens(List<ChatMessage> messages) async {
    final reply = await _request(WorkerOp.countTokens, {
      'messages': messages.map((m) => m.toIsolateMap()).toList(growable: false),
    });
    return reply['count']! as int;
  }

  @override
  Future<String> generateStructured({
    required List<({String role, String content})> messages,
    required GenerationConfiguration configuration,
    required int maxTokens,
    String? grammar,
  }) async {
    final reply = await _request(WorkerOp.generateStructured, {
      'messages': messages
          .map((m) => <String, Object?>{'role': m.role, 'content': m.content})
          .toList(growable: false),
      'configuration': configuration.toIsolateMap(),
      'maxTokens': maxTokens,
      'grammar': grammar,
    });
    return reply['text']! as String;
  }

  @override
  Stream<GenerationEvent> generate({
    required List<ChatMessage> messages,
    required GenerationConfiguration configuration,
  }) {
    late final StreamController<GenerationEvent> controller;
    // Nullable rather than `late final`: a subscription cancelled while `_ensureStarted()` is
    // still running reaches `onCancel` before an id was ever handed out.
    int? id;

    controller = StreamController<GenerationEvent>(
      onListen: () async {
        try {
          await _ensureStarted();
          final requestId = _nextRequestId++;
          id = requestId;
          _streams[requestId] = controller;
          _cancellation.reset();
          _commandPort!.send(<String, Object?>{
            'id': requestId,
            'op': WorkerOp.generate,
            'messages': messages.map((m) => m.toIsolateMap()).toList(growable: false),
            'configuration': configuration.toIsolateMap(),
          });
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      },
      onCancel: () {
        // Setting the flag stops the native loop on its next iteration — during token
        // sampling and during prompt prefill alike. The worker still sends a `finished`
        // reply with reason `cancelled`, which this controller is no longer listening for,
        // so the id is removed here to avoid holding a closed controller.
        _cancellation.cancel();
        final currentId = id;
        if (currentId != null) _streams.remove(currentId);
      },
    );

    return controller.stream;
  }

  /// Stops the current generation without tearing down the stream.
  ///
  /// The stream still terminates normally, with a [FinishedEvent] carrying
  /// [GenerationFinishReason.cancelled] and the metrics for the partial run — which is what
  /// lets the UI keep the text produced so far and mark the message "stopped" rather than
  /// "failed".
  void cancelGeneration() => _cancellation.cancel();
}
