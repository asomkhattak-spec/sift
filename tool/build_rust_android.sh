#!/usr/bin/env bash
#
# Cross-compiles the Rust search core for Android and copies the shared
# libraries into android/app/src/main/jniLibs, where the Android Gradle Plugin
# packages them into the APK.
#
# Requires: rustup (with the Android targets), an Android NDK, and cargo.
# On CI the NDK is installed by nttld/setup-ndk, which exports
# ANDROID_NDK_HOME. Locally the script also checks the usual SDK locations.
#
# Usage:
#   tool/build_rust_android.sh            # skip quietly when no NDK is found
#   tool/build_rust_android.sh --required # fail when no NDK is found

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRED=0
if [[ "${1:-}" == "--required" ]]; then
  REQUIRED=1
fi

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK" ]]; then
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/ndk/"* \
    "${ANDROID_HOME:-}/ndk/"* \
    "$HOME/Android/Sdk/ndk/"* \
    /usr/local/lib/android/sdk/ndk/*; do
    if [[ -d "$candidate/toolchains/llvm/prebuilt" ]]; then
      NDK="$candidate"
    fi
  done
fi

if [[ -z "$NDK" || ! -d "$NDK/toolchains/llvm/prebuilt" ]]; then
  if [[ "$REQUIRED" == "1" ]]; then
    echo "No Android NDK found. Set ANDROID_NDK_HOME." >&2
    exit 1
  fi
  echo "No Android NDK found; keeping the Dart fallback core for this build."
  exit 0
fi

case "$(uname -s)" in
  Darwin) HOST_TAG="darwin-x86_64" ;;
  *) HOST_TAG="linux-x86_64" ;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
if [[ ! -d "$TOOLCHAIN" ]]; then
  echo "NDK toolchain not found at $TOOLCHAIN" >&2
  exit 1
fi

API="${SIFT_ANDROID_API:-23}"
MANIFEST="$ROOT/rust/sift_core/Cargo.toml"
JNI_DIR="$ROOT/android/app/src/main/jniLibs"

build_abi() {
  local triple="$1"
  local abi="$2"
  local clang_prefix="$3"

  local clang="$TOOLCHAIN/bin/${clang_prefix}${API}-clang"
  if [[ ! -x "$clang" ]]; then
    echo "Missing compiler: $clang" >&2
    exit 1
  fi

  echo "Building $triple ($abi) for API $API"
  local env_name
  env_name="$(echo "$triple" | tr '[:lower:]-' '[:upper:]_')"
  env "CARGO_TARGET_${env_name}_LINKER=$clang" \
      "CC_${triple}=$clang" \
      "AR_${triple}=$TOOLCHAIN/bin/llvm-ar" \
      cargo build --locked --release \
        --manifest-path "$MANIFEST" \
        --target "$triple"

  mkdir -p "$JNI_DIR/$abi"
  cp "$ROOT/rust/target/$triple/release/libsift_core.so" \
     "$JNI_DIR/$abi/libsift_core.so"
}

rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

build_abi aarch64-linux-android arm64-v8a aarch64-linux-android
build_abi armv7-linux-androideabi armeabi-v7a armv7a-linux-androideabi
build_abi x86_64-linux-android x86_64 x86_64-linux-android

echo "Rust core packaged in $JNI_DIR"
