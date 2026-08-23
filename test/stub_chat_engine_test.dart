import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/domain/chat_message.dart';
import 'package:offline_ai_chat/domain/chat_role.dart';
import 'package:offline_ai_chat/domain/generation_configuration.dart';
import 'package:offline_ai_chat/llm/chat_engine.dart';
import 'package:offline_ai_chat/llm/stub_chat_engine.dart';

ChatMessage _message(ChatRole role, String content) => ChatMessage(
      id: 'test-${role.name}-${content.length}',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// Guards the fallback path taken when the llama.cpp shim is not linked in.
///
/// The point of these is not the stub's output but its *contract*: it has to satisfy
/// [ChatEngine] closely enough that the agent pipeline and the view models cannot tell the
/// difference, because they run against it unchanged on a machine with no native library.
void main() {
  late StubChatEngine engine;
  final configuration = GenerationConfiguration.standard(gpuLayers: 0);

  setUp(() => engine = StubChatEngine());

  test('reports no model until one is loaded', () async {
    expect(await engine.isModelLoaded, isFalse);
    expect(await engine.currentAllocatedContextLength, 0);
  });

  test('loading records the file name and the requested context length', () async {
    await engine.loadModel(path: '/models/qwen3-4b.gguf', configuration: configuration);

    expect(await engine.isModelLoaded, isTrue);
    expect(await engine.currentAllocatedContextLength, configuration.contextLength);
  });

  test('unloading clears the loaded state', () async {
    await engine.loadModel(path: '/models/qwen3-4b.gguf', configuration: configuration);
    await engine.unloadModel();

    expect(await engine.isModelLoaded, isFalse);
    expect(await engine.currentAllocatedContextLength, 0);
  });

  test('countTokens sums an estimate over the messages', () async {
    final messages = [
      _message(ChatRole.user, 'a' * 400),
      _message(ChatRole.assistant, 'b' * 800),
    ];

    expect(await engine.countTokens(messages), 300);
  });

  test('generateStructured returns parseable planner JSON', () async {
    final raw = await engine.generateStructured(
      messages: const [(role: 'user', content: 'hello')],
      configuration: configuration,
      maxTokens: 64,
    );

    expect(raw, contains('"action"'));
  });

  test('generate streams tokens and terminates with a FinishedEvent', () async {
    await engine.loadModel(path: '/models/qwen3-4b.gguf', configuration: configuration);

    final events = await engine
        .generate(messages: [_message(ChatRole.user, 'hi')], configuration: configuration)
        .toList();

    expect(events.whereType<TokenEvent>(), isNotEmpty);
    expect(events.last, isA<FinishedEvent>());

    final finished = events.last as FinishedEvent;
    expect(finished.reason, GenerationFinishReason.endOfSequence);
    expect(finished.metrics.generatedTokenCount, events.whereType<TokenEvent>().length);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cancelling the subscription stops the stream', () async {
    await engine.loadModel(path: '/models/qwen3-4b.gguf', configuration: configuration);

    final received = <GenerationEvent>[];
    final subscription = engine
        .generate(messages: [_message(ChatRole.user, 'hi')], configuration: configuration)
        .listen(received.add);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    await subscription.cancel();
    final countAtCancel = received.length;

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(received.length, countAtCancel);
  });
}
