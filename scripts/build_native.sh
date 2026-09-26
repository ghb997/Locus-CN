#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
revision=d32c8189c51c2789496b0768039419c3705498c3
toolchain=1.98.1
native="$root/Vendor/idevice-build"
if [[ ! -d "$native/.git" ]]; then
  git clone --no-checkout https://github.com/jkcoxson/idevice.git "$native"
fi
git -C "$native" fetch origin "$revision" --depth 1
git -C "$native" checkout --detach "$revision"
test "$(git -C "$native" rev-parse HEAD)" = "$revision"
rustup toolchain install "$toolchain" --profile minimal --target aarch64-apple-ios
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)"
export CARGO_TARGET_DIR="$root/build/native-target"
export CARGO_PROFILE_RELEASE_DEBUG=0
export CARGO_PROFILE_RELEASE_STRIP=debuginfo
(
  cd "$native/ffi"
  cargo +"$toolchain" build --locked --release --target aarch64-apple-ios --no-default-features --features ring,full
  cargo +"$toolchain" metadata --locked --format-version 1 --filter-platform aarch64-apple-ios \
    --no-default-features --features ring,full > "$root/build/native-metadata.json"
)
cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libidevice_ffi.a" "$root/Vendor/idevice/libidevice_ffi.a"
cp "$native/ffi/idevice.h" "$root/Vendor/idevice/idevice.h"
cp "$native/LICENSE.txt" "$root/Vendor/idevice/LICENSE.txt"
python3 scripts/inspect_native.py
python3 scripts/collect_native_notices.py
