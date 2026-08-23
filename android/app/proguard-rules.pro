# R8 rules for the release build (minifyEnabled true in app/build.gradle).
#
# A note on scope, because it is the single most misunderstood thing about FFI and R8:
# R8 does not touch native code. It cannot shrink, rename, or strip a symbol inside
# libllama_shim.so, and the `lc_*` lookups that dart:ffi performs at runtime resolve
# through dlsym against that .so, never through the Java/Kotlin class graph. The iOS
# equivalent problem (STRIP_STYLE / DEAD_CODE_STRIPPING in ios/Podfile) has no counterpart
# here — on Android the equivalent guard lives in CMake, where the shim's exports are
# marked __attribute__((visibility("default"), used)).
#
# What R8 *can* break is the Java side that gets the libraries loaded and the plugins
# registered in the first place. That is what the rules below protect.

# --- Flutter embedding -----------------------------------------------------------------
# Reached reflectively by the engine and by GeneratedPluginRegistrant.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- This app's entry point --------------------------------------------------------------
# Named as a string in AndroidManifest.xml, so nothing in the class graph references it.
-keep class net.salebee.offline_ai_chat.MainActivity { *; }

# --- llama_bindings ----------------------------------------------------------------------
# The plugin is an ffiPlugin: it has no Dart platform channel and, today, no Java classes of
# its own — the AAR exists only to carry libllama_shim.so and llama.cpp's .so files. This
# keep rule is deliberately broad so that adding a JNI helper later (a thermal-state
# listener, say) cannot be silently stripped and turned into a runtime UnsatisfiedLinkError.
-keep class net.salebee.llama_bindings.** { *; }

# Any class that declares a native method must keep its name and the method's name, or the
# JNI lookup by mangled symbol fails.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# --- Plugins that use reflection ---------------------------------------------------------
# file_picker + the platform's document provider path.
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# pdfrx loads libpdfium.so and reaches it through FFI; the Java side is only the loader.
-dontwarn org.jetbrains.annotations.**

# flutter_secure_storage -> AndroidX security-crypto -> Tink, which reflects over its own
# key-type registry.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class androidx.security.crypto.** { *; }

# sqflite / SQLite: no reflection, but the error-mapping code switches on exception class
# names, so keep them readable.
-keep class com.tekartik.sqflite.** { *; }

# --- Diagnostics ---------------------------------------------------------------------------
# Crash reports from release builds are worthless without these; they cost nothing at runtime.
-keepattributes SourceFile,LineNumberTable,Signature,*Annotation*
-renamesourcefileattribute SourceFile
