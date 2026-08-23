// Compiled instead of llama_shim.cpp when Frameworks/llama.xcframework is absent.
//
// See llama_bindings.podspec: without the xcframework there is no llama.h to compile the
// shim against, and CocoaPods refuses to install a pod whose `vendored_frameworks` does not
// exist. This translation unit keeps the pod installable so the app still builds and runs
// with inference disabled.
//
// It deliberately exports no `lc_*` symbol — that absence is what
// `isLlamaLibraryAvailable()` detects on the Dart side, which selects `StubChatEngine`.
//
// Run ./scripts/build_llama_ios.sh and re-run `pod install` to get the real shim back.

#import <Foundation/Foundation.h>

@interface LlamaBindingsPlaceholder : NSObject
@end
