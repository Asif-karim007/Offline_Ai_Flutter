#!/usr/bin/env bash
#
# Builds llama.xcframework for the iOS/macOS side of the plugin.
#
# If you already have a working xcframework — the Swift app's `Frameworks/llama.xcframework`,
# for instance — you can skip this entirely and just copy it into place:
#
#   cp -R "../Frameworks/llama.xcframework" packages/llama_bindings/ios/Frameworks/
#
# Only rebuild when you need a newer llama.cpp. Note that Qwen3.5 needs a build at or after
# b9222 for its Gated DeltaNet / sparse-MoE architecture and recurrent-state KV cache; the
# commit the Swift app pinned (4c1a0af) predates that and will not load a Qwen3.5 GGUF.
#
# Requires: Xcode command line tools, cmake 3.28+ (brew install cmake).
# Takes 10–20 minutes on Apple Silicon without ccache.

set -euo pipefail

# A pin, not a branch. Tracking master means a llama.h change silently breaks the shim.
LLAMA_CPP_REF="${LLAMA_CPP_REF:-b9222}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${PROJECT_ROOT}/.build"
SRC_DIR="${BUILD_ROOT}/llama.cpp"
DEST_DIR="${PROJECT_ROOT}/packages/llama_bindings/ios/Frameworks"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: an xcframework can only be built on macOS." >&2
  exit 1
fi

for tool in cmake git xcodebuild; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} not found on PATH." >&2
    exit 1
  fi
done

mkdir -p "${BUILD_ROOT}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "==> cloning llama.cpp"
  git clone https://github.com/ggml-org/llama.cpp.git "${SRC_DIR}"
fi

echo "==> checking out ${LLAMA_CPP_REF}"
git -C "${SRC_DIR}" fetch --tags --force
git -C "${SRC_DIR}" checkout --detach "${LLAMA_CPP_REF}"
echo "    HEAD is now $(git -C "${SRC_DIR}" rev-parse HEAD)"

echo "==> building xcframework"
# build-xcframework.sh already sets the flags that matter:
#   GGML_METAL=ON               Metal backend
#   GGML_METAL_EMBED_LIBRARY=ON compiles the .metal shaders into the binary, so there is no
#                               default.metallib to locate at runtime — the single biggest
#                               source of "works in debug, fails in release" on iOS
#   GGML_BLAS_DEFAULT=ON        Accelerate
chmod +x "${SRC_DIR}/build-xcframework.sh"
( cd "${SRC_DIR}" && ./build-xcframework.sh )

if [[ ! -d "${SRC_DIR}/build-apple/llama.xcframework" ]]; then
  echo "error: build finished but build-apple/llama.xcframework is missing." >&2
  exit 1
fi

echo "==> installing into ${DEST_DIR}"
mkdir -p "${DEST_DIR}"
rm -rf "${DEST_DIR}/llama.xcframework"
cp -R "${SRC_DIR}/build-apple/llama.xcframework" "${DEST_DIR}/"

echo
echo "done. llama.xcframework installed."
echo "Slices present:"
ls -1 "${DEST_DIR}/llama.xcframework" | grep -v Info.plist | sed 's/^/  /'
echo
echo "Next: cd ios && pod install"
