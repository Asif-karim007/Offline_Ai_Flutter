Pod::Spec.new do |s|
  s.name             = 'llama_shim'
  s.version          = '1.0.0'
  s.summary          = 'dart:ffi bindings to llama.cpp via a plain-C shim.'
  s.description      = <<-DESC
Compiles the llama_shim translation unit into a dynamic framework and links it against
llama.xcframework, vendored by the sibling llama_bindings pod. See llama_bindings.podspec for
why this is a separate pod rather than a subspec of it. Not a Flutter plugin itself — wired
into ios/Podfile directly, next to the `llama_bindings` plugin's own
`flutter_install_all_ios_pods` line, since Flutter's plugin registry only looks for a podspec
named after the plugin.

Built as a dynamic framework, deliberately: `lib/src/llama_library.dart` opens it by path
(`DynamicLibrary.open('@rpath/llama_shim.framework/llama_shim')`) rather than scanning the
main executable, because a dynamic library's exported symbols are always visible to
dlopen/dlsym regardless of whether anything references them at link time — which nothing
does; Dart only ever reaches `lc_*` through `dlsym`. An earlier static-linkage design fought
Xcode's linker over exactly that (`-force_load`, `-Wl,-u,symbol`, `-all_load`,
dead-code-stripping settings — some combination always either dropped the symbols, stripped
them back out, or duplicated CocoaPods' own dummy anchor object). None of that plumbing is
needed here.
                       DESC
  s.homepage         = 'https://github.com/salebee/offline-ai-chat'
  s.license          = { :type => 'MIT' }
  s.author           = { 'SaleBee' => 'crm@salebee.net' }
  s.source           = { :path => '.' }

  s.dependency 'Flutter'
  s.dependency 'llama_bindings'
  s.platform = :ios, '13.0'

  # See llama_bindings.podspec for what this flag means and why it can be false.
  llama_xcframework_available = Dir.exist?(File.join(File.dirname(__FILE__), 'Frameworks', 'llama.xcframework'))

  if llama_xcframework_available
    # `Shim/` holds symlinks to ../../src/llama_shim.{cpp,h}, not the files themselves — so
    # Android and iOS still compile the identical file. The symlinks exist because CocoaPods'
    # file globbing for a `:path`-based local pod silently matches zero files for a
    # `source_files` pattern that escapes the podspec's own directory (a bare `'../src/...'`
    # pattern here produced a pod with *no compile phase at all*: no warning, no error, no
    # `lc_*` symbol anywhere in the app, ever). Keeping the glob pattern inside `ios/` and
    # letting the filesystem do the `../` instead avoids that.
    s.source_files        = 'Shim/llama_shim.cpp', 'Shim/llama_shim.h'
    s.public_header_files = 'Shim/llama_shim.h'
  else
    s.source_files        = 'Classes/LlamaBindingsPlaceholder.{h,m}'
    s.public_header_files = 'Classes/LlamaBindingsPlaceholder.h'
  end

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    # llama.xcframework ships its headers inside the framework bundle (vendored by the
    # llama_bindings pod, one directory up from this podspec — same directory as this one, in
    # fact, since both podspecs live side by side). The shim includes "llama.h" unqualified,
    # so the framework's Headers directory has to be on the search path.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/llama.xcframework/ios-arm64/llama.framework/Headers" "${PODS_TARGET_SRCROOT}/Frameworks/llama.xcframework/ios-arm64_x86_64-simulator/llama.framework/Headers"',
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.libraries = 'c++'
  s.frameworks = llama_xcframework_available ?
    ['Accelerate', 'Metal', 'MetalKit', 'Foundation'] : ['Foundation']
end
