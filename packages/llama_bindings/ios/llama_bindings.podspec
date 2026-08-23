Pod::Spec.new do |s|
  s.name             = 'llama_bindings'
  s.version          = '1.0.0'
  s.summary          = 'dart:ffi bindings to llama.cpp via a plain-C shim.'
  s.description      = <<-DESC
Compiles the llama_shim translation unit and vendors llama.xcframework. All struct layouts
and C++ exception handling live in the shim, so the Dart side only ever sees primitives and
opaque pointers.
                       DESC
  s.homepage         = 'https://github.com/salebee/offline-ai-chat'
  s.license          = { :type => 'MIT' }
  s.author           = { 'SaleBee' => 'crm@salebee.net' }
  s.source           = { :path => '.' }

  # ---------------------------------------------------------------------------------------
  # llama.xcframework is optional at install time
  # ---------------------------------------------------------------------------------------
  #
  # It is produced by scripts/build_llama_ios.sh and is not committed. Declaring it
  # unconditionally made `pod install` fail outright on a fresh clone — CocoaPods validates
  # `vendored_frameworks` paths — which meant the app could not even be built, let alone run.
  #
  # When it is missing this pod compiles a placeholder translation unit instead of the shim.
  # There is no llama.h to compile llama_shim.cpp against without the framework, and the
  # resulting binary exports no `lc_*` symbol — which is exactly what
  # `isLlamaLibraryAvailable()` probes for, so the app falls back to `StubChatEngine` and
  # everything except inference works.
  #
  # Build the framework and re-run `pod install` to get the real shim back.
  llama_xcframework_available = Dir.exist?(File.join(File.dirname(__FILE__), 'Frameworks', 'llama.xcframework'))

  if llama_xcframework_available
    # The shim itself lives one level up so Android and iOS compile the identical file.
    s.source_files        = '../src/llama_shim.cpp', '../src/llama_shim.h'
    s.public_header_files = '../src/llama_shim.h'
    s.vendored_frameworks = 'Frameworks/llama.xcframework'
  else
    s.source_files        = 'Classes/LlamaBindingsPlaceholder.{h,m}'
    s.public_header_files = 'Classes/LlamaBindingsPlaceholder.h'
  end

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    # llama.xcframework ships its headers inside the framework bundle. The shim includes
    # "llama.h" unqualified, so the framework's Headers directory has to be on the search path.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/llama.xcframework/ios-arm64/llama.framework/Headers" "${PODS_TARGET_SRCROOT}/Frameworks/llama.xcframework/ios-arm64_x86_64-simulator/llama.framework/Headers"',
    # Without this the linker strips lc_* in Release and every FFI lookup throws
    # ArgumentError: Failed to lookup symbol.
    'STRIP_STYLE' => 'non-global',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.libraries = 'c++'
  # Accelerate/Metal/MetalKit are llama.cpp's backends; without the framework there is
  # nothing to link them for, and Foundation is all the placeholder needs.
  s.frameworks = llama_xcframework_available ?
    ['Accelerate', 'Metal', 'MetalKit', 'Foundation'] : ['Foundation']
end
