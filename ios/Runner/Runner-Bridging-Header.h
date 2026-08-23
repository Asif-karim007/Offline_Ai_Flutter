// Objective-C headers visible to Swift in the Runner target.
//
// Only the plugin registrant is needed. In particular `llama_shim.h` is deliberately NOT
// imported here: no Swift code calls the shim. Dart resolves the `lc_*` symbols out of the
// running process with `DynamicLibrary.process()` (see
// packages/llama_bindings/lib/src/llama_library.dart), so the shim's only requirement of
// this target is that its symbols survive the Release strip — which is what the
// STRIP_STYLE / DEAD_CODE_STRIPPING settings in the Podfile's post_install exist for.
#import "GeneratedPluginRegistrant.h"
