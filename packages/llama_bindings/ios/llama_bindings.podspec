Pod::Spec.new do |s|
  s.name             = 'llama_bindings'
  s.version          = '1.0.0'
  s.summary          = 'Vendors llama.xcframework for the sibling llama_shim pod to link against.'
  s.description      = <<-DESC
Vendors llama.xcframework (produced by scripts/build_llama_ios.sh, not committed) so the
sibling `llama_shim` pod — declared in llama_shim.podspec next to this file, wired into
ios/Podfile directly since it is not itself a Flutter plugin — can compile and link the FFI
shim against it.

Split into two pods, not one pod with a subspec, because CocoaPods merges every subspec of a
single pod into one Xcode target, and that merged target still comes out as a script-only
PBXAggregateTarget (just the "[CP] Copy XCFrameworks" phase) whenever `vendored_frameworks`
is present anywhere in the merge, under `use_frameworks! :linkage => :static`. Under that
representation `llama_shim.cpp` is silently never compiled — not stripped, never built in the
first place. A second, genuinely separate pod is what reliably gets its own compiling
PBXNativeTarget.
                       DESC
  s.homepage         = 'https://github.com/salebee/offline-ai-chat'
  s.license          = { :type => 'MIT' }
  s.author           = { 'SaleBee' => 'crm@salebee.net' }
  s.source           = { :path => '.' }

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # ---------------------------------------------------------------------------------------
  # llama.xcframework is optional at install time
  # ---------------------------------------------------------------------------------------
  #
  # It is produced by scripts/build_llama_ios.sh and is not committed. Declaring it
  # unconditionally made `pod install` fail outright on a fresh clone — CocoaPods validates
  # `vendored_frameworks` paths — which meant the app could not even be built, let alone run.
  #
  # When it is missing, this pod (and llama_shim) compile a placeholder translation unit
  # instead. There is no llama.h to compile llama_shim.cpp against without the framework, and
  # the resulting binary exports no `lc_*` symbol — which is exactly what
  # `isLlamaLibraryAvailable()` probes for, so the app falls back to `StubChatEngine` and
  # everything except inference works.
  #
  # Build the framework and re-run `pod install` to get the real shim back.
  llama_xcframework_available = Dir.exist?(File.join(File.dirname(__FILE__), 'Frameworks', 'llama.xcframework'))

  if llama_xcframework_available
    s.vendored_frameworks = 'Frameworks/llama.xcframework'
  else
    # Nothing to vendor yet. A trivial no-op translation unit keeps this pod (and the
    # workspace) valid without the framework built; llama_shim.podspec's own placeholder
    # branch is what actually keeps `isLlamaLibraryAvailable()` returning false.
    s.source_files        = 'Classes/LlamaBindingsPlaceholder.{h,m}'
    s.public_header_files = 'Classes/LlamaBindingsPlaceholder.h'
  end

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.libraries = 'c++'
  s.frameworks = llama_xcframework_available ?
    ['Accelerate', 'Metal', 'MetalKit', 'Foundation'] : ['Foundation']
end
