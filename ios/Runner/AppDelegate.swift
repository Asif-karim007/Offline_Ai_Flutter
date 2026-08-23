import Flutter
import UIKit

/// The whole native iOS layer.
///
/// There is no platform channel and no Swift bridge to llama.cpp: `llama_shim.cpp` is
/// compiled into this binary by the `llama_bindings` pod and reached from Dart through
/// `dart:ffi`, so nothing native needs to be registered by hand here. The one job left is
/// registering the generated plugin registrant for the pub plugins (path_provider,
/// sqflite, file_picker, pdfrx, shared_preferences, flutter_secure_storage).
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
