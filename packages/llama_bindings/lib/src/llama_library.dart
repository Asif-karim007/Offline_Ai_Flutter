import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

/// Resolves the dynamic library that exports the `lc_*` shim symbols.
///
/// The two platforms link the shim differently, so the lookup differs:
///
///  * **Android** — CMake produces a standalone `libllama_shim.so` that Gradle packages into
///    the APK alongside llama.cpp's own shared objects. It is opened by name.
///  * **iOS / macOS** — CocoaPods compiles `llama_shim.cpp` directly into the app binary as
///    a static pod, so there is no separate library file to open. The symbols are already in
///    the running process.
///
/// Note that `DynamicLibrary.open` on Android does not need the llama.cpp libraries opened
/// first: `libllama_shim.so` records them as `DT_NEEDED` dependencies and the loader resolves
/// them transitively, provided CMake copied them next to the shim (it does — see the
/// POST_BUILD step in `src/CMakeLists.txt`).
ffi.DynamicLibrary openLlamaLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libllama_shim.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isLinux || Platform.isWindows) {
    // Desktop is not a shipping target, but keeping this path working means the engine can
    // be exercised from a plain `dart test` run on a developer machine.
    return ffi.DynamicLibrary.open(
      Platform.isWindows ? 'llama_shim.dll' : 'libllama_shim.so',
    );
  }
  throw UnsupportedError(
    'llama.cpp is not available on this platform (${Platform.operatingSystem}).',
  );
}

/// Whether the llama.cpp shim is actually present in this process.
///
/// The native library is not checked into the repository — it is produced by
/// `scripts/build_llama_android.sh` / `scripts/build_llama_ios.sh`. Until that build has
/// run, `openLlamaLibrary()` throws on Android (no `libllama_shim.so` in the APK) or
/// resolves to a process handle with no `lc_*` symbols on iOS.
///
/// Probing here — cheaply, once, on the UI isolate — is what lets `AppCoordinator` pick a
/// stub engine instead of spawning a worker isolate that would die on its first symbol
/// lookup and take the app's error reporting with it.
///
/// `lc_backend_init` is used as the sentinel because it is the first symbol the real engine
/// resolves; if it is missing, every other lookup would fail too.
bool isLlamaLibraryAvailable() {
  try {
    return openLlamaLibrary().providesSymbol('lc_backend_init');
  } on Object {
    return false;
  }
}
