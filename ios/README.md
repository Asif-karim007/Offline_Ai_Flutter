# iOS shell — regenerating `Runner.xcodeproj`

> **`Runner.xcodeproj` now exists in the tree**, along with `Runner.xcworkspace`,
> `Runner.xcodeproj/project.xcworkspace`, the shared `Runner` scheme, `RunnerTests/`, the
> app-icon PNGs and `ios/.gitignore`. It already has `IPHONEOS_DEPLOYMENT_TARGET = 13.0` and
> `PRODUCT_BUNDLE_IDENTIFIER = net.salebee.offline_ai_chat` on all three configurations, so
> step 4 below is already done. `pod install` also no longer requires
> `Frameworks/llama.xcframework`: the podspec compiles a placeholder translation unit when
> it is absent, and the app falls back to `StubChatEngine`. Follow the procedure below only
> if you need to regenerate the project from scratch.

Everything in this directory is hand-written and specific to this app: the deployment
target, the annotated Info.plist and the decisions recorded in it, the CocoaPods `post_install`
that keeps the FFI symbols alive in Release. One thing used to be deliberately **not**
committed:

```
ios/Runner.xcodeproj/project.pbxproj
```

It is several thousand lines of generated Xcode plumbing — object graph UUIDs, build
phases, file references, per-configuration settings — and a hand-written one is wrong in
ways that surface as "file not found" for files that plainly exist. The committed copy is
checked against the stock template on every change for exactly that reason; if you touch it,
diff it against a fresh `flutter create` before trusting it.

The same applied to `Runner.xcworkspace/`, `Runner.xcodeproj/project.xcworkspace/`, the
scheme under `Runner.xcodeproj/xcshareddata/xcschemes/`, and `RunnerTests/`. All of them are
now in the tree.

---

## The procedure

Run all of this from the **project root** (`offline_ai_chat_flutter/`), not from `ios/`.

### 1. Put this directory somewhere safe

`flutter create` will happily overwrite the files below with its stock templates. Take a
copy first — the easiest correct move if the repo is under git is to make sure everything
is committed, so `git status` afterwards shows you exactly what was clobbered:

```bash
git add -A && git commit -m "platform shells before flutter create"
# or, without git:
cp -R ios /tmp/ios-authored
```

### 2. Generate the missing Xcode project

```bash
flutter create --platforms=ios --org net.salebee --project-name offline_ai_chat .
```

The trailing `.` matters — it means "fill in the missing platform folders of the project
that is already here", not "make a new project".

### 3. Restore the authored files over the generated ones

```bash
git checkout -- ios          # if you committed in step 1
# or:
cp -R /tmp/ios-authored/. ios/
```

**Keep what `flutter create` generated:**

| Path | Why |
|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | The whole point of the exercise. |
| `ios/Runner.xcodeproj/project.xcworkspace/` | Workspace settings for the bare project. |
| `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | The Runner/Profile/Release scheme. `flutter run --profile` fails without it. |
| `ios/Runner.xcworkspace/` | What Xcode actually opens once pods exist. |
| `ios/RunnerTests/RunnerTests.swift` | The Podfile declares a `RunnerTests` target; the pbxproj expects this file. |
| `ios/Runner/Assets.xcassets/**/*.png` | The icon and launch-image binaries this repo does not ship (see the READMEs in those folders). |
| `ios/.gitignore` | Standard, and identical to what you would write. |

**Overwrite the generated copies with the versions in this repository:**

| Path | What you lose if you keep the generated one |
|---|---|
| `ios/Podfile` | The `post_install` block. Release builds then throw `ArgumentError: Failed to lookup symbol 'lc_*'` at the first inference. This is the one that costs you an afternoon. |
| `ios/Runner/Info.plist` | Display name, and the documented decisions about background modes, ATS, and the deliberately absent file-sharing and `.gguf` document-type keys (removed with hand-importing a model — a model now only arrives through the in-app catalog download). |
| `ios/Runner/AppDelegate.swift` | Only comments differ, but keep them. |
| `ios/Runner/Runner-Bridging-Header.h` | Same. |
| `ios/Runner/Base.lproj/*.storyboard` | The launch screen's `systemBackgroundColor` (the stock one is hardcoded white and flashes in dark mode). |
| `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig` | Functionally identical; keep the annotated versions. |
| `ios/Flutter/AppFrameworkInfo.plist` | `MinimumOSVersion` — the template writes 12.0, this project needs 13.0. |
| `ios/Runner/Assets.xcassets/**/Contents.json` | Identical to the template; harmless either way. |

### 4. Fix the two settings `flutter create` gets wrong for this project

Open `ios/Runner.xcodeproj/project.pbxproj` (or Xcode → Runner target → Build Settings) and
check both of these for **every** configuration — Debug, Release, and Profile:

1. **`IPHONEOS_DEPLOYMENT_TARGET`** — Flutter's template writes `12.0`. This project needs
   `13.0`, matching `platform :ios, '13.0'` in the Podfile,
   `s.platform = :ios, '13.0'` in `packages/llama_bindings/ios/llama_bindings.podspec`, and
   `MinimumOSVersion` in `ios/Flutter/AppFrameworkInfo.plist`. The Podfile's `post_install`
   already forces this on the pod targets and on the Runner target, but it only runs during
   `pod install` — set it in the project too so a fresh Xcode build before `pod install`
   is not misleading.

2. **`PRODUCT_BUNDLE_IDENTIFIER`** — `flutter create` camel-cases the project name and
   writes `net.salebee.offlineAiChat`. This project uses **`net.salebee.offline_ai_chat`**,
   the same string as the Android `applicationId`. Change all three configurations, plus
   the `RunnerTests` target's `net.salebee.offlineAiChat.RunnerTests`.

   > A caveat worth knowing before you ship: Apple documents bundle identifiers as
   > alphanumerics, hyphen and period only, and App Store Connect has been known to reject
   > underscores. It builds, installs and runs on device fine. If you hit a rejection,
   > `net.salebee.offline-ai-chat` is the conventional substitute — and if you change it,
   > change it on Android too so the two stay in step.

### 5. Install the pods

```bash
cd ios && pod install
```

This is also when the `post_install` hook rewrites `Runner.xcodeproj`'s strip settings, so
**you must re-run `pod install` after any `flutter create`**, not just the first time.

`pod install` no longer requires `packages/llama_bindings/ios/Frameworks/llama.xcframework`.
The podspec vendors it only when it exists and compiles `Classes/LlamaBindingsPlaceholder.m`
when it does not, so a clone with no xcframework installs, builds and launches — with
inference disabled, on `StubChatEngine`. Run `./scripts/build_llama_ios.sh` (or copy an
existing xcframework into that folder; root `README.md`, section 4) and **re-run
`pod install`** to get the real shim.

### 6. Open the workspace, never the project

```bash
open ios/Runner.xcworkspace
```

Opening `Runner.xcodeproj` directly builds without pods and fails at link time.

---

## Verifying the strip settings actually took

The failure mode this directory exists to prevent is invisible in Debug. After a Release
build, check that the shim's symbols survived:

```bash
flutter build ios --release --no-codesign
nm -gU build/ios/iphoneos/Runner.app/Runner | grep ' _lc_' | head
```

You should see `_lc_backend_init`, `_lc_model_load`, `_lc_decode` and friends. An empty
result means the strip settings were lost — check that `pod install` ran after the last
`flutter create`, and that `ios/Podfile` is the version from this repository.
