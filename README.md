# Offline AI Chat (Flutter)

An offline-first AI agent for iOS and Android, built with Flutter, Dart isolates, sqflite,
and [`llama.cpp`](https://github.com/ggml-org/llama.cpp). All reasoning and final answer
generation always happen on-device, on a local GGUF model. Optional tools — local document
RAG and web search — provide *information*; they never do the reasoning and never replace
the local model. See section 9 for the precise, two-mode privacy model.

This is a port of a SwiftUI/SwiftData iOS app. `PORTING_CONVENTIONS.md` states the rules
the port follows — prompt strings, thresholds and token caps are copied rather than
paraphrased, and deliberate limitations are preserved rather than "fixed". Read it before
changing anything under `lib/`.

## 1. Overview

- Runs a local GGUF language model (recommended: `Qwen3.5-0.8B-Q4_K_M`) through
  `llama.cpp`, reached from Dart over `dart:ffi` through a plain-C shim.
- One model stays loaded and one `llama_context` stays alive for the lifetime of the app;
  switching conversations clears the context without reloading model weights.
- An agent layer sits above the raw chat pipeline and runs a *bounded* pipeline per
  message: a cheap deterministic router, an optional small structured planner call, at most
  one retrieval round (local documents and/or web), then one final local generation. There
  is no recursive think/search loop.
- Session-only conversational memory keeps long chats coherent by compacting old turns into
  a compact structured summary once the conversation crosses ~70% of the active context
  budget — never persisted, cleared when the session ends.
- Local document RAG lets you attach `.txt`/`.md`/`.json`/`.csv`/source files/`.pdf` files
  to a session; only user-selected files are ever read, never a folder scan, and retrieval
  is hybrid lexical (BM25) + semantic with a relevance floor. **On this port the semantic
  half is currently a null implementation — see section 12.**
- Optional web search is off by default for reasoning purposes and gated by an
  Off/Ask/Automatic setting; only a minimized search query and the specific result URLs
  ever leave the device — never the conversation or file contents. Fetched pages are
  treated as untrusted evidence, never as instructions.
- Persistent chats are saved in a hand-written sqflite schema. Temporary chats are never
  written to disk.
- The UI and view models never touch native `llama.cpp` pointers: `ChatEngine` is the only
  abstraction they depend on, and nothing outside `lib/llm/` imports `package:llama_bindings`.

## 2. Architecture

```
lib/
  domain/            Plain immutable value types shared across layers
  llm/               ChatEngine + LlamaEngine (owns the inference isolate)
  agent/             Orchestrator + router/planner/context assembly
  agent/memory/      Session-only structured conversational memory
  agent/documents/   Local document import, extraction, chunking, RAG retrieval
  agent/web/         Optional web search provider, page fetch, extraction
  agent/retrieval/   Hybrid (lexical + semantic) scoring shared by memory and documents
  agent/benchmark/   Debug-only on-device benchmarking harness
  persistence/       sqflite schema + ConversationRepository
  model_management/  Model file storage, catalog, download, first-launch bootstrap, settings
  viewmodels/        ChangeNotifier view models, one per Swift @Observable original
  l10n/              Every UI string, in English and Bangla (hand-written, no code generation)
  views/             Flutter widgets
  utilities/         Small stateless helpers
assets/models/       Optional bundled GGUF model (not committed — see section 6)

packages/llama_bindings/
  lib/               dart:ffi bindings, isolate-safe cancellation flag, library resolution
  src/               llama_shim.{h,cpp} — the plain-C surface, shared by both platforms
  ios/               podspec, vendors llama.xcframework
  android/           Gradle library, builds src/CMakeLists.txt against prebuilt .so files
scripts/             build_llama_ios.sh, build_llama_android.sh
```

The layer boundaries match the Swift app one for one, and one Swift file maps to one
`snake_case` Dart file. **Not every layer has landed yet** — the port is progressing
bottom-up, and `lib/domain/` and `lib/llm/` plus the whole of `packages/llama_bindings/`
are what exist at the time of writing. The map above is the target shape, not a claim about
the current tree; `ls lib/` is the truth.

### The engine

`LlamaEngine` owns a dedicated **isolate** (`lib/llm/llama_worker.dart`) that holds the
model pointer, context, vocabulary, sampler chain, and batch. This is the Dart equivalent of
the Swift original's `actor`, and it exists for the same reason: a `llama_context` is not
safe for concurrent access, so every native call has to be serialized onto one execution
context. It buys a second thing Swift got for free — inference runs off the platform thread,
so a 40-token-per-second stream does not stutter the UI.

Per `PORTING_CONVENTIONS.md`, an isolate is used *only* where native state demands it.
Everywhere else a Swift `actor` becomes an ordinary class with a guard flag, because Dart's
single-threaded event loop already provides the mutual exclusion the actor was there for.

Nothing in the Dart layer knows a llama.cpp struct layout. `packages/llama_bindings/src/`
holds a plain-C shim whose functions take only primitives and opaque pointers, catch C++
exceptions before they can cross the FFI boundary (an uncaught one hits `std::terminate` and
kills the process — Dart can no more catch it than Swift could), and expose one flat surface
that both platforms compile identically.

Generation uses a **full-prompt-rebuild** strategy: for every new message the KV cache is
cleared and the entire token-budget-trimmed conversation is re-tokenized and re-decoded.
This is deliberately simpler and more obviously correct than incremental KV-cache reuse, at
some cost to throughput. The agent layer preserves it exactly: the planner call and the
final-answer call are each their own independent clear-KV → decode → sample pass against the
same engine, so there is never concurrent native access.

### Agent pipeline

One message runs a bounded pipeline:

1. **Route** — a cheap, deterministic keyword/phrase pre-check (no model call) that decides
   whether a tool might plausibly be needed.
2. **Plan** *(only if routing flagged it)* — a tiny structured JSON question to the local
   model — `{action, query, reason, needs_current_information, needs_private_files}` —
   capped at ~120 tokens. Never shown to the user.
3. **Retrieve** *(at most one round)* — attached documents, and/or the public web when
   explicitly enabled (section 9).
4. **Assemble** — session memory, document evidence and web evidence folded into the system
   prompt within per-category token caps, with document/web text wrapped as explicitly
   untrusted `<document_sources>`/`<web_sources>` evidence. `TokenBudgetManager.fitHistory`
   is reused unchanged to fit recent history into whatever room remains.
5. **Generate** — the streaming generation path, unchanged, produces the final answer.

There is no recursive think → search → think loop: at most one planning round and one
retrieval round ever happen before the final answer, which bounds latency, battery, and
memory use.

## 3. Requirements

| | |
|---|---|
| Flutter | 3.22 or later (Dart 3.4+). `flutter --version` |
| iOS | Deployment target 13.0+, Xcode 16 or later, CocoaPods |
| Android | `minSdk 26`, `compileSdk`/`targetSdk 35`, NDK **27.0.12077973**, JDK 17, Gradle 8.9, AGP 8.5.2 |
| ABI | **arm64 only** on both platforms — `arm64-v8a` on Android, `arm64` on iOS device |
| CMake | 3.28+ for the iOS xcframework, 3.22+ for Android (`brew install cmake`, or the SDK Manager's "CMake" package) |
| Hardware | A physical device. Both simulators run CPU-only inference and are far slower than the phone in your pocket |

Application id / bundle identifier: **`net.salebee.offline_ai_chat`** on both platforms.
(The Swift original used `asif.Offline-Ai-Chat`; the port moved to a reverse-DNS id that is
legal as an Android package name. See the caveat about underscores in `ios/README.md`.)

Free disk: the llama.cpp checkout and its build trees under `.build/` run to several GB, and
that is before any model weights.

## 4. Building llama.cpp

Both platforms pin the same llama.cpp revision, **`b9222`**. That pin is not decoration:
Qwen3.5's Gated DeltaNet / sparse-MoE architecture and its recurrent-state KV cache need a
build at or after b9222. The commit the Swift app pinned (`4c1a0af`) predates it and will
not load a Qwen3.5 GGUF at all.

The shim in `packages/llama_bindings/src/llama_shim.cpp` was written against this revision's
`include/llama.h`. If you move the pin, diff `llama.h` for renamed functions before assuming
the shim still compiles — llama.cpp's C API does evolve (`llama_new_context_with_model` →
`llama_init_from_model`, `llama_n_ctx_train` → `llama_model_n_ctx_train`, and so on).

### iOS / macOS

```bash
./scripts/build_llama_ios.sh
```

Clones llama.cpp into `.build/`, checks out the pin, runs upstream's
`build-xcframework.sh`, and installs the result at
`packages/llama_bindings/ios/Frameworks/llama.xcframework`, which the podspec vendors.
Roughly 10–20 minutes on Apple Silicon without `ccache`. macOS only, obviously.

The upstream script already sets the flags that matter — `GGML_METAL=ON`,
`GGML_METAL_EMBED_LIBRARY=ON` (compiles the `.metal` shaders into the binary so there is no
`default.metallib` to locate at runtime — the single biggest source of "works in debug,
fails in release" on iOS), and `GGML_BLAS_DEFAULT=ON` for Accelerate.

If you already have a working xcframework — the Swift app's `Frameworks/llama.xcframework`,
for instance — skip the build entirely:

```bash
mkdir -p packages/llama_bindings/ios/Frameworks
cp -R /path/to/Frameworks/llama.xcframework packages/llama_bindings/ios/Frameworks/
```

...but only if it was built at or after b9222, or Qwen3.5 will not load.

### Android

```bash
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.0.12077973   # or let the script find it
./scripts/build_llama_android.sh
```

Cross-compiles for `arm64-v8a` and installs into
`packages/llama_bindings/android/prebuilt/arm64-v8a/*.so` plus
`prebuilt/include/*.h`, which `packages/llama_bindings/src/CMakeLists.txt` imports. The app
build then only compiles the shim — building llama.cpp on every app build would add 10–20
minutes to a clean CI run for nothing.

Run it once after cloning, and again whenever the pin changes.

The script checks the LOAD segment alignment of `libllama.so` and warns if it is not
`2**14`. Take that warning seriously: Android 15 refuses to load shared libraries that are
not 16 KB page aligned, and an NDK older than r27 produces exactly that. The failure happens
on the user's device, not on your build machine.

The Adreno OpenCL backend is off by default (`LLAMA_ANDROID_OPENCL=1` to include it). It
only helps on Qualcomm, and GPU backends on Android are frequently *slower* than CPU, so CPU
is the honest baseline here. The plugin's CMake picks up `libggml-opencl.so` automatically
if the file is present.

## 5. First-run setup

> **Status: the generated platform files are now in the tree.** `ios/Runner.xcodeproj`,
> `ios/Runner.xcworkspace`, `ios/RunnerTests`, the Gradle wrapper and the launcher icons
> were all filled in, so a fresh clone builds and runs with `flutter pub get && flutter run`
> — no `flutter create` step. The llama.cpp binaries are still not committed (section 4);
> without them the app launches with inference disabled and says so on screen. The rest of
> this section is kept as the procedure for regenerating those files if they are ever lost
> or you want Flutter's own versions.

Three things were originally missing on purpose, all of them binary or
generated, and each has a README next to where it belongs.

### 5.1 The Xcode project

`ios/Runner.xcodeproj/project.pbxproj` is not committed — it is thousands of lines of
generated Xcode plumbing, and a hand-written one is wrong in ways that surface as "file not
found" for files that plainly exist. Regenerate it:

```bash
git commit -am "platform shells before flutter create"     # so you can see what gets clobbered
flutter create --platforms=ios --org net.salebee --project-name offline_ai_chat .
git checkout -- ios                                        # restore the authored files
cd ios && pod install
```

**`ios/README.md` is the authoritative version of this procedure** — it lists precisely
which generated files to keep, which to overwrite, and the two build settings
(`IPHONEOS_DEPLOYMENT_TARGET`, `PRODUCT_BUNDLE_IDENTIFIER`) that `flutter create` gets wrong
for this project. Read it rather than trusting the four lines above.

`pod install` needs `packages/llama_bindings/ios/Frameworks/llama.xcframework` to exist
already, so do section 4 first.

### 5.2 The Gradle wrapper and the Android launcher icons

`android/gradle/wrapper/gradle-wrapper.jar`, `android/gradlew` and `android/gradlew.bat` are
binary/executable and not committed; `gradle-wrapper.properties` (which pins Gradle 8.9) is.
The launcher icon PNGs are not committed either, and the manifest references
`@mipmap/ic_launcher`, so packaging fails without them.

See `android/README.md` and `android/app/src/main/res/README.md`. The short version:

```bash
flutter create --platforms=android --org net.salebee --project-name offline_ai_chat .
git checkout -- android/app/build.gradle android/build.gradle android/settings.gradle \
                android/gradle.properties android/gradle/wrapper/gradle-wrapper.properties \
                android/app/src android/app/proguard-rules.pro
```

Check afterwards that `gradle-wrapper.properties` still names `gradle-8.9-all.zip`.

### 5.3 Model weights

Section 6. Optional if you are happy to download a model from the catalog at first launch.

## 6. Model resource setup

### Optional bundled model

Place a GGUF file at:

```
assets/models/Qwen3.5-0.8B-Q4_K_M.gguf
```

`pubspec.yaml` already declares `assets/models/` as an asset directory. On first launch, if
no model is installed, the app copies the asset into the platform's application support
directory exactly once, marks the copy excluded from backup, and loads only from that copy.
The bundled original is never modified and never mmapped in place.

This repo does **not** ship that file. Model weights are large binary assets that do not
belong in git history — see `assets/models/README.md`. Without it, the catalog download
below is how a model gets onto the device — it is the only way, so a first run needs a
network connection once.

### The catalog (`lib/model_management/model_catalog.dart`)

`ModelCatalog` is the single source of truth for what can be downloaded: the model picker, the
first-run screen and the bundled-asset bootstrap all read from it, so adding a model is a
one-file change. These are the entries as they stand:

| Tier | Model | File | Size | Min. RAM | Notes |
|---|---|---|---|---|---|
| Bundled / default | **Qwen3.5-0.8B-Q4_K_M** | `Qwen3.5-0.8B-Q4_K_M.gguf` | 533 MB | 3 GB | Recommended starting point. 201 languages including Bengali. Comfortable on any arm64 device from the last few years, and a genuinely instruction-tuned chat model with a usable embedded chat template. |
| Recommended | **Qwen3.5-2B-Q4_K_M** | `Qwen3.5-2B-Q4_K_M.gguf` | 1.28 GB | 4 GB | Measured 39 tok/s at 1.48 GB peak on A19 Pro. Noticeably better at multi-step instructions and at the planner's structured JSON. |
| Max | **Qwen3.5-4B-Q4_K_M** | `Qwen3.5-4B-Q4_K_M.gguf` | 2.74 GB | 8 GB | Weights alone are 2.74 GB before KV cache. Expect memory-pressure terminations below 8 GB, especially on Android where the app competes with more background work. |
| Embedding | **multilingual-e5-small Q8_0** | `multilingual-e5-small-Q8_0.gguf` | 126 MiB | 2 GB | 384-dimension embeddings for hybrid retrieval. Not a chat model, never offered as one. **Not wired up in this version** — see section 12. |

The three Qwen entries are Apache-2.0, ChatML, 256K trained context, and come from Unsloth's
GGUF repositories; the embedding model is MIT. `ModelCatalog.chatModels` is the first three —
that is exactly what the download screen lists. Every entry resolves to a Hugging Face
`resolve/main/<file>` URL, and `revision` defaults to the branch tip: **pin a commit SHA
there before shipping**, or a re-upload silently delivers different weights than the sizes in
this table describe.

Each entry also declares the device RAM below which it should not be offered — the "Min. RAM"
column — and `ModelCatalog.fittingMemory()` applies it, so the 4B entry can be kept off a
phone that cannot hold it. A device that reports no memory figure at all gets the unfiltered
list rather than an empty one.

**On the old recommended download.** The first-run screen used to hard-code one Hugging Face
URL — `Qwen3-0.6B-Q8_0`, 639.4 MB — with the size written as a literal in the view so the
button label could be formatted. Those constants are gone. The recommendation is now
`ModelCatalog.bundledDefault`, which resolves to `ModelCatalog.qwen35Point8B`, i.e.
**Qwen3.5-0.8B-Q4_K_M at 533 MB** — the same file named by `assets/models/` above. This is a
deliberate departure from the porting rule that copies user-visible strings verbatim: the
screen that carried them no longer exists in the same form.

Any other instruction-tuned GGUF with an embedded chat template still *loads* if you get it
into `<application support>/Models` yourself (a debug-build `adb push`, say) — the app scans
that directory and lists whatever it finds. There is no in-app path for it. The app
**rejects a model with no usable chat template rather than guessing one**, so base
(non-instruct) conversions fail to load by design.

Qwen3.5 requires the b9222 llama.cpp pin (section 4). A model that loads under the Swift
app's older framework may simply refuse to load here, and vice versa.

### Downloading a model

Downloading from the catalog is the only way a model reaches the device — hand-importing a
`.gguf` through the document picker was removed, along with the iOS `.gguf` file association
and the Files-sharing keys that existed to serve it (`ios/Runner/Info.plist`).

If no model is installed, the app shows a setup screen listing `ModelCatalog.chatModels` with
a **Download** button per row; the same list is reachable later from the model manager's
**Download a Model** row. The download runs over HTTPS and reports determinate progress when
the server sends a length, a bytes-only spinner when it does not. It is resumable — a partial
transfer is kept at `<file>.part` and continued with a `Range` header, and the `.part` file is
renamed into place only once the transfer completes, so an interrupted download is never
mistaken for an installed model. The finished file lands in
`<application support>/Models`, which is where the engine loads from. That directory is not
user-visible on either platform: on Android it is the app's private files directory, and on
iOS it is under `Library/`, which file sharing does not expose.

A model is downloaded once and stays installed. Switching between installed models, and
deleting one to reclaim space, are both in the model manager.

## 7. Running it

Everything except the llama.cpp binaries is in the tree, so the short version is:

```bash
flutter pub get
flutter run -d <your-device>
```

That builds and launches. Inference is disabled until llama.cpp is built — the app detects
the missing library at startup, falls back to a stub engine, and the first reply explains
what to run. Every other screen behaves normally.

For the real thing:

```bash
flutter pub get
./scripts/build_llama_ios.sh          # macOS, for iOS
./scripts/build_llama_android.sh      # for Android
cd ios && pod install && cd ..        # iOS only; re-run after building the xcframework
flutter run --release -d <your-device>
```

The switch is automatic: `AppCoordinator` probes for the `lc_backend_init` symbol on every
launch and uses the real engine whenever it resolves.

Use `--release` (or at least `--profile`) for anything you intend to judge performance by. A
debug build's Dart is JIT-compiled and its native code is unoptimized; tokens/second in
debug mean nothing.

On first launch either the bundled model copies in automatically, or — the usual case, since
this repo ships no GGUF — you get the model catalog screen and download one (section 6). That
first download is the one moment the app needs a network connection; everything after it works
in Airplane Mode.

### Airplane Mode test

This is the test that matters. Once a model is loaded, enable Airplane Mode and send a
message. Generation must work identically — nothing in the generation path makes a network
call. If Web Search is set to Automatic and you ask a current-information question, the app
will transparently report that web search is unavailable and answer from local knowledge
only (section 9) rather than pretending to be current.

Worth doing on both platforms after any change to the model-management or agent layers. It
is the cheapest possible regression test for an accidental network dependency.

## 8. Debugging common build errors

| Error | Likely cause / fix |
|---|---|
| `ArgumentError: Failed to lookup symbol 'lc_backend_init'` (or any `lc_*`), **iOS Release only** | The Release linker stripped the shim's symbols. Nothing references them at compile time — only `DynamicLibrary.process()` at runtime — so `STRIP_STYLE=all` and `DEAD_CODE_STRIPPING=YES` delete them. `ios/Podfile`'s `post_install` sets `STRIP_STYLE=non-global` and `DEAD_CODE_STRIPPING=NO` on both the pod targets *and* the Runner target. Re-run `pod install`; confirm with `nm -gU build/ios/iphoneos/Runner.app/Runner \| grep ' _lc_'`. |
| `libllama.so not found` / `dlopen failed: library "libllama.so" not found` | `./scripts/build_llama_android.sh` has not been run, or was run for a different ABI. The prebuilt libraries have to exist at `packages/llama_bindings/android/prebuilt/arm64-v8a/` before the app build. If they are missing entirely CMake no longer fails: it prints a `WARNING`, builds a placeholder `libllama_shim.so` with no `lc_*` symbols, and the app runs on `StubChatEngine` — so an app that launches but refuses to infer means this script has not been run. |
| App launches but the first reply says the native library is not built | Working as designed: `isLlamaLibraryAvailable()` found no `lc_backend_init`, so `AppCoordinator` selected `StubChatEngine`. Build llama.cpp (section 4), then `flutter clean && flutter run` on Android (the CMake configure has to re-run) or `pod install` again on iOS. |
| `dlopen failed: "libllama.so" is not 16 KB aligned` / crash on load, Android 15 only | Built with an NDK older than r27. Set `ANDROID_NDK_HOME` to 27.0.12077973 and re-run the Android build script. Also check `packagingOptions.jniLibs.useLegacyPackaging` is `false` and that nothing hardcodes `android:extractNativeLibs` in the manifest — the .so has to be mmapped from an aligned position inside the APK, and AGP 8.5.1+ is what aligns it. |
| `No such file or directory: 'llama.xcframework'` at `pod install` | Only with a podspec older than this one. The current podspec vendors the framework *conditionally*: when `packages/llama_bindings/ios/Frameworks/llama.xcframework` is absent it compiles a placeholder instead and the app falls back to `StubChatEngine`. Run `./scripts/build_llama_ios.sh` (or copy an xcframework there, section 4) **and re-run `pod install`** — `flutter run` will not re-run it for you. |
| `flutter.sdk not set in local.properties` | Gradle was invoked directly in a checkout where no Flutter command has run yet. Run `flutter pub get`, or write `android/local.properties` by hand (`android/README.md`). |
| `Could not find gradle-wrapper.jar` / `./gradlew: No such file` | The wrapper binaries are not committed. See `android/README.md`, section 1. |
| `resource mipmap/ic_launcher not found` | Launcher icons not generated. See `android/app/src/main/res/README.md`. |
| `Module 'llama' not found` / missing headers on iOS | `HEADER_SEARCH_PATHS` in the podspec points into the xcframework's slice-specific `Headers` directory. A device-only or simulator-only xcframework build breaks it — rebuild with upstream's `build-xcframework.sh`, which produces all slices. |
| Model fails to load | Check the file is a valid, non-truncated `.gguf`. `LlamaError.modelLoadFailed` carries the shim's error string in debug builds. A Qwen3.5 GGUF against a pre-b9222 build fails here. |
| Missing chat template | The GGUF has no usable embedded template. Deliberate: the app rejects rather than guesses. Try a mainstream instruction-tuned model. |
| Runs slowly in a simulator/emulator | Expected. Both simulate CPU-only, and the Android emulator additionally runs x86_64 while this build is arm64-only, so it will not even install there. Test on hardware. |
| Context overflow / prompt too large | `TokenBudgetManager` trims old turns automatically. If the *current* message alone does not fit you get `LlamaError.promptTooLarge` — lower the context length preset or shorten the message. |
| Invalid UTF-8 in the token stream | Should not happen — `UTF8TokenBuffer` holds back incomplete multi-byte sequences until they complete. File a bug with the model name if you see mangled text. |
| Memory-pressure termination | A smaller context length preset, or a smaller/lower-quantization model. On Android, confirm `android:largeHeap="true"` survived a manifest merge (`build/app/outputs/logs/manifest-merger-*-report.txt`). |
| App terminates when backgrounded mid-generation | Expected, and documented: there are no `UIBackgroundModes` and no foreground service. Inference is foreground-only (see the comment in `ios/Runner/Info.plist`). |

## 9. Privacy behaviour

This app has two modes. Read both — the difference matters.

### Offline Mode (default; the only mode when Web Search is Off)

All inference, chat history, session memory, and document processing stay entirely
on-device. No network access is required or made:

- Chat generation, the structured planner call, and memory compaction all run locally
  through `llama.cpp` — no prompt or response text is ever sent over the network.
- Attached documents are extracted, chunked, and retrieved entirely on-device; file contents
  never leave the device, automatically or otherwise. PDF text extraction is PDFium running
  in-process (`pdfrx`), not a service call.
- No chat content is written to analytics, crash logs, or platform logging — the logger only
  records structural metadata (token counts, durations), never message text. Android release
  builds keep `SourceFile`/`LineNumberTable` for stack traces and nothing else
  (`android/app/proguard-rules.pro`).
- **Temporary Chat** messages exist only in memory: never written to sqflite, shared
  preferences, logs, or any file. They are gone the moment you leave the temporary session
  or the app terminates.
- Saved (persistent) chats stay entirely on-device in the app's local SQLite database, which
  is excluded from cloud backup and device-to-device transfer on both platforms
  (`android/app/src/main/res/xml/data_extraction_rules.xml`; excluded-from-backup attribute
  on iOS).
- The `INTERNET` permission on Android and the absence of an ATS exception on iOS are the
  whole network surface. The permission exists only for the two opt-in features below; the
  app is fully functional for offline chat without ever exercising it.

### Web-Assisted Mode (opt-in, via Settings → Web Search: Ask or Automatic)

The model's local reasoning and final answer generation are unaffected — they still happen
entirely on-device. What changes is that the app *may*, for questions that plausibly need
current information, make a network request:

- A short, minimized search query (e.g. `"current CEO Apple recent changes"`) — **never** the
  full conversation, **never** document contents — is sent to the configured search provider.
- The app then downloads the selected public web page(s) for the top results, over HTTPS
  only (`usesCleartextTraffic="false"`; ATS defaults, no exceptions).
- With **Ask** (the default once web search is enabled at all) you approve each search before
  it happens. With **Automatic**, current-information questions search without prompting.
- Fetched web content is treated as untrusted evidence, not instructions — the model is
  explicitly told never to follow commands embedded in a web page, and never to disclose
  local file contents or chat history because a web page asks for it.
- Session memory, local documents, and the SQLite contents are never sent to the search
  provider or to any fetched page, under any setting.
- Every agent-assisted answer is labelled **On Device** (fully local) or **On Device + Web**
  (web evidence was used) so you always know whether a given response used the network.
- If Web Search is Off and a question looks like it needs current information, the app says
  so plainly rather than answering as if it were current, and points you at the setting.
- The provider API key is stored in the platform keystore/keychain via
  `flutter_secure_storage`, and is excluded from backup and device transfer.

Nothing else in this document's offline claims changes: this is strictly additive, and the
default (Ask, and effectively Off until a provider API key is configured) keeps the app fully
offline unless you deliberately turn it on.

## 10. Temporary Chat behaviour

Tap the eye-slash button (accessibility label "Start Temporary Chat") in the top-right of
the chat toolbar to start one. A banner reads "Temporary chat — messages will not be
saved." Temporary chats never appear in the sidebar history and are discarded on app
relaunch. If you try to leave a non-empty temporary chat (New Chat, selecting a saved
conversation, or starting another temporary chat), you get a confirmation alert before it is
discarded.

## 11. Model and `llama.cpp` licensing

- `llama.cpp` is MIT-licensed. See `LICENSE` in the cloned source under `.build/llama.cpp/`.
- GGUF model weights carry their own license from whoever published them (Qwen models are
  generally Apache 2.0, but always check the specific model card you download from). You are
  responsible for complying with the license of any model you bundle with or distribute
  alongside this app — that responsibility is not satisfied by anything in this repository.
- `pdfrx` bundles PDFium (BSD-3-Clause). It was chosen over Syncfusion's PDF library
  specifically because Syncfusion's community licence is revenue-capped.

## 12. Known limitations

- **No bundled model and no prebuilt native binaries in git.** The GGUF, the iOS
  `llama.xcframework` and the Android `prebuilt/*.so` files are all produced locally
  (sections 4 and 6). A fresh clone runs two build scripts before it can run the app.
- **The Xcode project is generated, not committed** (section 5.1), and the Gradle wrapper
  jar and launcher icons likewise. This is a deliberate trade: a hand-written `project.pbxproj`
  would be subtly wrong, and fabricated binary assets are worse than absent ones.
- **Android has no Metal equivalent, so CPU is the baseline.** iOS gets Metal GPU offload for
  free through the xcframework; on Android the honest default is CPU inference. The Adreno
  OpenCL backend exists behind `LLAMA_ANDROID_OPENCL=1` but is Qualcomm-only and frequently
  slower than CPU, and Vulkan is worse. Expect Android tokens/second to trail a comparable
  iPhone, and do not treat that gap as a bug to be fixed with a flag.
- **`TextEmbeddingProvider` ships as a null implementation.** The Swift app used Apple's
  `NLEmbedding`, which has no cross-platform equivalent and no Android counterpart worth
  shipping. Until the `multilingual-e5-small` path is wired up, hybrid retrieval degrades to
  **lexical-only (BM25)** scoring for both session memory and document RAG. Retrieval still
  works and still applies its relevance floor; it is just worse at paraphrase.
- **The WKWebView-backed search provider was dropped in the port.** It depended on driving a
  real web view to render and scrape results, which does not survive the move to Flutter in
  any form worth maintaining. Web search is HTTP-API-based only. `WebSearchProvider` is still
  a pluggable interface if you want to add one.
- **No provider is configured out of the box**, so Web Search behaves as Off until you add
  an API key. Changing or removing the key currently requires an app restart to take effect.
- **Prompt processing always rebuilds the full context** rather than reusing the KV cache
  incrementally (section 2). Intentional for v1 correctness, at some cost to throughput on
  long conversations.
- **Grammar-constrained sampling is plumbed but unused.** `lc_sampler_add_grammar` exists and
  the planner passes no GBNF grammar, because grammar sampling threw a C++ exception on
  Qwen3's `<think>` preamble and killed the process. `PORTING_CONVENTIONS.md` rule 2: do not
  "fix" this. The planner parses structurally instead.
- **`llama_chat_apply_template` matches a table of known template families** rather than
  running a full Jinja2 engine. This covers mainstream instruction-tuned families (Qwen
  included) but is not a universal interpreter.
- **The port is in progress.** `lib/domain/` and `lib/llm/` and the FFI plugin are complete;
  the agent, persistence, model-management, view-model and view layers are landing in that
  order. Section 2's map describes the target, and this README describes the app as designed
  — check `ls lib/` before assuming a feature exists in your checkout.
- **Inference is foreground-only** and there is no background mode on either platform
  (see the reasoning in `ios/Runner/Info.plist`). Backgrounding mid-generation suspends the
  isolate and may get the process terminated; the cancellation flag makes that a clean stop
  rather than a corrupt KV cache, but the answer is lost.
- **The recommended default is still the smallest model.** Moving to Qwen3.5-2B as the
  bundled default is gated on real on-device benchmarking (`lib/agent/benchmark/`, reachable
  from Settings → Debug once debug metrics are on) rather than assumed from parameter count.
