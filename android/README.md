# Android shell — what is here and what you have to generate

> **The Gradle wrapper and the launcher icons are now committed.** `gradlew`, `gradlew.bat`,
> `gradle/wrapper/gradle-wrapper.jar` and `app/src/main/res/mipmap-*/ic_launcher.png` are all
> present, and `gradle-wrapper.properties` still pins `gradle-8.9-all.zip`. A missing
> llama.cpp prebuilt is no longer a configure-time `FATAL_ERROR` either — CMake builds a
> placeholder `libllama_shim.so` with no `lc_*` symbols and the app runs with inference
> disabled. The instructions below are the procedure for regenerating these if needed.

Every text file `flutter create` would have produced for the Android platform folder is
committed here and configured for this project (arm64-only, `minSdk 26`, NDK r27, 16 KB
page alignment, an uncompressed GGUF asset). Three things are **not** here, because they
are binary or machine-local, and the build fails without them.

## 1. The Gradle wrapper (`gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`)

`gradle/wrapper/gradle-wrapper.properties` is committed and pins **Gradle 8.9**. The jar
and the two launcher scripts are not — the jar is a binary and the scripts must be
executable. Produce them with either:

```bash
# If you have a system Gradle (any 8.x) on PATH:
cd android && gradle wrapper --gradle-version 8.9 --distribution-type all
```

or by letting `flutter create` generate them (see the root `README.md`, "First-run
setup"), which is the same command that generates the missing Xcode project.

Verify afterwards that `android/gradle/wrapper/gradle-wrapper.properties` still names
`gradle-8.9-all.zip` — `gradle wrapper` rewrites that file.

## 2. Launcher icons

See `app/src/main/res/README.md`. `AndroidManifest.xml` references `@mipmap/ic_launcher`
and packaging fails until those PNGs exist.

## 3. `local.properties`

Machine-local and git-ignored. `flutter run` / `flutter build` writes it for you on first
invocation; `settings.gradle` reads `flutter.sdk` out of it. If you invoke Gradle directly
without ever having run a Flutter command in this checkout, create it by hand:

```properties
sdk.dir=/path/to/Android/sdk
flutter.sdk=/path/to/flutter
```

## Release signing (optional)

`app/build.gradle` reads `android/key.properties` if it exists:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without it, release builds are signed with the debug key so that
`flutter build apk --release` still works for on-device benchmarking. That APK is not
distributable.
