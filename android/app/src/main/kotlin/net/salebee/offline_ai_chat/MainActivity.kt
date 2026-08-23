package net.salebee.offline_ai_chat

import io.flutter.embedding.android.FlutterActivity

/**
 * Plain Flutter host activity.
 *
 * There is deliberately no `configureFlutterEngine` override and no MethodChannel: the only
 * native code this app owns is llama.cpp behind `packages/llama_bindings`, and that is
 * reached through `dart:ffi` from a background isolate, not through the platform channel on
 * the main thread. Keeping the activity empty is what makes the Android and iOS shells
 * interchangeable.
 */
class MainActivity : FlutterActivity()
