#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. $SCRIPT_DIR/common.inc.sh

# Recreate the relevant directories
rm -rf build
mkdir build || exit 1

rm -rf "$ALPINE_ROOT"
mkdir -p "$ALPINE_ROOT" || exit 1

if [ ! -d packages ]; then
  mkdir packages || exit 1
fi
if [ ! -d packages/apk_cache ]; then
  mkdir packages/apk_cache || exit 1
fi

# Download and extract the bootstrap
mkdir build/apk || exit 1
cd build/apk || exit 1
  wget $APK_TOOLS_URL $ALPINE_KEYS_URL || exit 1
  sha256sum -c ../../src/alpine_sha256sum || exit 1

  tar -x -f $APK_TOOLS_FILENAME || exit 1
  tar -x -f $ALPINE_KEYS_FILENAME || exit 1

  export PATH="$(realpath sbin):$PATH"
  export APK_KEYS_PATH="$(realpath usr/share/apk/keys)"
cd ../.. || exit 1

# Bootstrap Alpine Linux
APK_REPOS="-X $ALPINE_MIRROR/edge/main -X $ALPINE_MIRROR/edge/community -X $ALPINE_MIRROR/edge/testing"
APK_FLAGS="$APK_REPOS -U -p $ALPINE_ROOT --cache-dir $(root_path packages/apk_cache)"
apk.static $APK_FLAGS --keys-dir "$APK_KEYS_PATH" --initdb add alpine-base proot qemu-x86_64

# Properly install Alpine Linux and our basic packages after bootstrapping
alpine /bin/busybox --install -s || exit 1
mkdir -p "$ALPINE_ROOT/home/$USER"
cp "$SCRIPT_DIR/repositories" "$ALPINE_ROOT/etc/apk/repositories" || exit 1
apk update
apk upgrade
apk add alpine-sdk llvm15 clang15 gcc lld libstdc++-dev compiler-rt autoconf automake

# Install custom packages and set up abuild properly.
REPODEST="$(root_path build/packages)"
mkdir "$REPODEST" || exit 1
if [ ! -d ~/.abuild ]; then
  alpine abuild-keygen -q -n -a || exit 1
fi

cp -v ~/.abuild/*.pub "$SCRIPT_DIR/apk/keys/"*.pub "$ALPINE_ROOT/etc/apk/keys"
apk -U --no-cache add "$SCRIPT_DIR/apk/packages/aports/x86_64/make-4.3-r0.apk"

# Build and install our customized musl
use_flags "$OPT_LEVEL $CFLAGS_BASIC $CFLAGS_HARDENING_BASIC"
abuild_dir "$SCRIPT_DIR/aports/musl"
apk -U --no-cache add "$APK_PACKAGE_ROOT"/musl-dev-*.apk

# Build our custom hardened-malloc
use_flags "$OPT_LEVEL $CFLAGS_BASIC $CFLAGS_HARDENING -fvisibility=hidden"
abuild_dir "$SCRIPT_DIR/aports/hardened-malloc"
apk -U --no-cache add hardened-malloc

# Install rustc
apk add rustup
alpine rustup-init --default-toolchain nightly -y || exit 1

# Delete the build directory
rm -rf build
