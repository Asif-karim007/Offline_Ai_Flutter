import Flutter
import UIKit
import XCTest

/// Native-side smoke test.
///
/// The Podfile declares a `RunnerTests` target, so this target has to exist for
/// `pod install` to succeed. There is nothing native to test beyond the app booting: the
/// llama.cpp shim is exercised from Dart through `dart:ffi`, and the Dart tests under
/// `test/` cover the rest.
class RunnerTests: XCTestCase {
  func testAppDelegateExists() {
    XCTAssertNotNil(AppDelegate())
  }
}
