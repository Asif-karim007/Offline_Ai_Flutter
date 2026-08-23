/// Low-level bindings to llama.cpp.
///
/// Nothing above this package should import `dart:ffi` or know that llama.cpp exists. The
/// app depends on the `ChatEngine` interface in `lib/llm/chat_engine.dart`; `LlamaEngine` is
/// the only implementation that reaches down here.
library llama_bindings;

export 'src/cancellation_flag.dart' show CancellationFlag;
export 'src/llama_ffi.dart' show LlamaFfi, lcDecodeException, lcSampleError;
export 'src/llama_library.dart' show isLlamaLibraryAvailable;
export 'src/llama_native.dart' show LlamaNative, LlamaNativeException;
