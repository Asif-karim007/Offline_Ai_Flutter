import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

/// Resolves the dynamic library that exports the `lc_*` shim symbols.
///
/// Every platform opens an actual library file by name or path — never
/// `DynamicLibrary.process()`. An earlier iOS-only design tried to statically merge
/// `llama_shim.cpp`'s object code into the main executable so `DynamicLibrary.process()`
/// could find it there, on the theory that `dart:ffi` never calls any of the `lc_*`
/// functions at compile time so nothing else would either. That is true, and it is exactly
/// the problem: a static linker only keeps what something references, so it kept dropping,
/// stripping, or duplicating the shim depending on which combination of `-force_load`,
/// `-Wl,-u,symbol`, dead-code-stripping settings and Xcode's "Eager Linking" pre-link stubs
/// was in play that day. Every platform below sidesteps the whole category: a *dynamic*
/// library always exposes its full exported symbol table to `dlopen`/`dlsym` regardless of
/// whether anything references those symbols at link time, so there is nothing for a linker
/// to prune.
///
///  * **Android** — CMake produces a standalone `libllama_shim.so` that Gradle packages into
///    the APK alongside llama.cpp's own shared objects. It is opened by name; the OS loader
///    finds it via the APK's native library path.
///  * **iOS / macOS** — CocoaPods builds `llama_shim` as a genuine dynamic framework
///    (`ios/Podfile` no longer forces static linkage), embedded in the app bundle's
///    `Frameworks/` directory the same way `llama.xcframework` itself already was. `@rpath`
///    is what resolves it: Xcode adds `@executable_path/Frameworks` (apps) /
///    `@loader_path/../Frameworks` (frameworks/tests) to the binary's run-path search list
///    automatically for every embedded framework, and `dlopen` honors an `@rpath/`-prefixed
///    path exactly the way the OS's own dynamic linker does for a `DT_NEEDED`/`LC_LOAD_DYLIB`
///    entry.
///
/// Note that `DynamicLibrary.open` on Android does not need the llama.cpp libraries opened
/// first: `libllama_shim.so` records them as `DT_NEEDED` dependencies and the loader resolves
/// them transitively, provided CMake copied them next to the shim (it does — see the
/// POST_BUILD step in `src/CMakeLists.txt`). iOS resolves `llama_shim.framework`'s own link
/// against `llama.framework` the same transitive way, via its `LC_LOAD_DYLIB` entry.
ffi.DynamicLibrary openLlamaLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libllama_shim.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.open('@rpath/llama_shim.framework/llama_shim');
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
/// run, `openLlamaLibrary()` throws — on Android there is no `libllama_shim.so` in the APK;
/// on iOS there is no `llama_shim.framework` in the app bundle for `@rpath` to resolve.
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
