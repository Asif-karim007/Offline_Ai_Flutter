#!/usr/bin/env bash
#
# Cross-compiles llama.cpp for Android and installs the result where the plugin's
# CMakeLists.txt expects it:
#
#   packages/llama_bindings/android/prebuilt/arm64-v8a/lib*.so
#   packages/llama_bindings/android/prebuilt/include/*.h
#
# Run this once after cloning, and again whenever LLAMA_CPP_REF changes. App builds then
# just link against the output, instead of paying 10–20 minutes to rebuild llama.cpp on
# every clean build.
#
# Requires: Android NDK r27 or newer, cmake 3.22+, ninja, git.
# Set ANDROID_NDK_HOME, or let the script find it under $ANDROID_HOME/ndk.

set -euo pipefail

LLAMA_CPP_REF="${LLAMA_CPP_REF:-b9222}"

# arm64 only. Every 64-bit Android phone from the last decade is arm64-v8a, and armeabi-v7a
# cannot address enough memory to hold a useful model anyway.
ABIS="${LLAMA_ANDROID_ABIS:-arm64-v8a}"

# Android 15 refuses to load shared libraries that are not 16 KB page aligned. NDK r27+
# does this by default; this makes it explicit so an older NDK fails loudly here rather than
# at install time on a user's device.
MIN_SDK="${LLAMA_ANDROID_MIN_SDK:-26}"

# Adreno OpenCL backend. Off by default: it only helps on Qualcomm, and Vulkan on Android is
# frequently *slower* than CPU, so CPU is the honest baseline. Set LLAMA_ANDROID_OPENCL=1 to
# include it — the plugin's CMakeLists picks it up automatically when the .so is present.
WANT_OPENCL="${LLAMA_ANDROID_OPENCL:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${PROJECT_ROOT}/.build"
SRC_DIR="${BUILD_ROOT}/llama.cpp"
DEST_ROOT="${PROJECT_ROOT}/packages/llama_bindings/android/prebuilt"

# --- locate the NDK -------------------------------------------------------------------

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  for candidate in "${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk"/* \
                   "${ANDROID_SDK_ROOT:-}/ndk"/*; do
    if [[ -d "${candidate}" ]]; then
      ANDROID_NDK_HOME="${candidate}"
    fi
  done
fi

if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "${ANDROID_NDK_HOME}" ]]; then
  echo "error: Android NDK not found." >&2
  echo "       Install it via Android Studio (SDK Manager -> SDK Tools -> NDK)," >&2
  echo "       then set ANDROID_NDK_HOME." >&2
  exit 1
fi

TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
if [[ ! -f "${TOOLCHAIN}" ]]; then
  echo "error: ${TOOLCHAIN} is missing — ANDROID_NDK_HOME does not look like an NDK." >&2
  exit 1
fi

NDK_VERSION="$(basename "${ANDROID_NDK_HOME}")"
NDK_MAJOR="${NDK_VERSION%%.*}"
if [[ "${NDK_MAJOR}" =~ ^[0-9]+$ ]] && (( NDK_MAJOR < 27 )); then
  echo "warning: NDK ${NDK_VERSION} predates r27. Libraries it produces are not 16 KB page" >&2
  echo "         aligned and will fail to load on Android 15+. Upgrade before shipping." >&2
fi

echo "==> NDK: ${ANDROID_NDK_HOME}"

for tool in cmake git ninja; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} not found on PATH." >&2
    exit 1
  fi
done

# --- source ---------------------------------------------------------------------------

mkdir -p "${BUILD_ROOT}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "==> cloning llama.cpp"
  git clone https://github.com/ggml-org/llama.cpp.git "${SRC_DIR}"
fi

echo "==> checking out ${LLAMA_CPP_REF}"
git -C "${SRC_DIR}" fetch --tags --force
git -C "${SRC_DIR}" checkout --detach "${LLAMA_CPP_REF}"
echo "    HEAD is now $(git -C "${SRC_DIR}" rev-parse HEAD)"

# --- build ----------------------------------------------------------------------------

for ABI in ${ABIS}; do
  echo
  echo "==> building ${ABI}"
  BUILD_DIR="${BUILD_ROOT}/android-${ABI}"
  rm -rf "${BUILD_DIR}"

  EXTRA_ARGS=()
  if [[ "${WANT_OPENCL}" == "1" ]]; then
    echo "    including the Adreno OpenCL backend"
    EXTRA_ARGS+=(-DGGML_OPENCL=ON)
  fi

  cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DANDROID_ABI="${ABI}" \
    -DANDROID_PLATFORM="android-${MIN_SDK}" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_LLAMAFILE=OFF \
    "${EXTRA_ARGS[@]}"

  cmake --build "${BUILD_DIR}" --config Release -j "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

  DEST="${DEST_ROOT}/${ABI}"
  mkdir -p "${DEST}"
  rm -f "${DEST}"/*.so

  # llama.cpp scatters its shared objects across the build tree depending on version, so
  # collect by name rather than by expected path.
  found=0
  while IFS= read -r lib; do
    cp "${lib}" "${DEST}/"
    found=$((found + 1))
  done < <(find "${BUILD_DIR}" -name 'libllama.so' -o -name 'libggml*.so' | sort)

  if (( found == 0 )); then
    echo "error: build produced no shared libraries for ${ABI}." >&2
    exit 1
  fi

  echo "    installed ${found} libraries:"
  ls -1 "${DEST}" | sed 's/^/      /'

  # 16 KB alignment check. objdump reports the LOAD segment alignment; anything below
  # 0x4000 will be rejected by Android 15.
  OBJDUMP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/bin/llvm-objdump"
  if [[ "${ABI}" == "arm64-v8a" && -x "${OBJDUMP}" ]]; then
    align="$("${OBJDUMP}" -p "${DEST}/libllama.so" 2>/dev/null | awk '/LOAD/ {print $NF; exit}')"
    if [[ -n "${align}" && "${align}" != "2**14" ]]; then
      echo "    warning: libllama.so LOAD alignment is ${align}, expected 2**14 (16 KB)." >&2
      echo "             This will not load on Android 15+." >&2
    fi
  fi
done

# --- headers --------------------------------------------------------------------------

echo
echo "==> installing headers"
mkdir -p "${DEST_ROOT}/include"
cp "${SRC_DIR}/include/llama.h" "${DEST_ROOT}/include/"
cp "${SRC_DIR}"/ggml/include/*.h "${DEST_ROOT}/include/"

echo
echo "done. Prebuilt llama.cpp installed under:"
echo "  ${DEST_ROOT}"
echo
echo "Next: flutter build apk"
