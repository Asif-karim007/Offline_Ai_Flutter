Pod::Spec.new do |s|
  s.name             = 'llama_bindings'
  s.version          = '1.0.0'
  s.summary          = 'dart:ffi bindings to llama.cpp via a plain-C shim.'
  s.description      = 'macOS slice of the same shim compiled for iOS.'
  s.homepage         = 'https://github.com/salebee/offline-ai-chat'
  s.license          = { :type => 'MIT' }
  s.author           = { 'SaleBee' => 'crm@salebee.net' }
  s.source           = { :path => '.' }

  # Optional exactly as on iOS — see ios/llama_bindings.podspec for the reasoning. Without
  # the xcframework this pod compiles the shared placeholder translation unit and the app
  # falls back to StubChatEngine instead of `pod install` failing outright.
  llama_xcframework_available =
    Dir.exist?(File.join(File.dirname(__FILE__), '..', 'ios', 'Frameworks', 'llama.xcframework'))

  if llama_xcframework_available
    s.source_files        = '../src/llama_shim.cpp', '../src/llama_shim.h'
    s.public_header_files = '../src/llama_shim.h'
    s.vendored_frameworks = '../ios/Frameworks/llama.xcframework'
  else
    s.source_files        = '../ios/Classes/LlamaBindingsPlaceholder.{h,m}'
    s.public_header_files = '../ios/Classes/LlamaBindingsPlaceholder.h'
  end

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../ios/Frameworks/llama.xcframework/macos-arm64_x86_64/llama.framework/Versions/A/Headers"',
    'STRIP_STYLE' => 'non-global',
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.libraries = 'c++'
  s.frameworks = llama_xcframework_available ?
    ['Accelerate', 'Metal', 'MetalKit', 'Foundation'] : ['Foundation']
end
