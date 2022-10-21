#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. $SCRIPT_DIR/common.inc.sh

# Recreate the relevant directories
rm -rf build
mkdir build || exit 1

rm -rf musl_root
mkdir musl_root || exit 1

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
apk.static \
  -X "$ALPINE_MIRROR/edge/main" -U -p musl_root --initdb \
  --keys-dir "$APK_KEYS_PATH" --cache-dir "$(root_path packages/apk_cache)" add \
  alpine-base alpine-sdk musl musl-dev llvm15 clang15 gcc lld libstdc++-dev compiler-rt

# Activate the musl root since we're about to do some custom builds
use_musl_root
"$(/usr/bin/which busybox)" --install musl_root/bin || exit 1
/usr/bin/sed --in-place=.bak "s_/bin/ash -e_/usr/bin/env ash_" musl_root/usr/bin/abuild || exit 1

# Setup abuild and our new repository
export REPODEST="$(root_path build/packages)"
mkdir "$REPODEST" || exit 1
if [ ! -d ~/.abuild ]; then
  abuild-keygen -q -n -a || exit 1
fi

# Do the custom musl build
cd build || exit 1
  cp -r "$SCRIPT_DIR/musl" musl || exit 1
  cd musl || exit 1
    SAFESTACK_O="$(root_path musl_root/usr/lib/clang)"
    SAFESTACK_O="$(echo "$SAFESTACK_O"/*/lib/linux/libclang_rt.safestack-x86_64.a)"
    export CFLAGS="$CFLAGS_ABULID_MUSL"
    export LDFLAGS="$LDFLAGS_ABULID_MUSL -Wl,$SAFESTACK_O"
    abuild || exit 1
  cd .. || exit 1
cd .. || exit 1

# Install our custom packages
apk \
  -X "$REPODEST/build" -U -p musl_root --keys-dir ~/.abuild --no-cache \
  upgrade

# Delete the build directory
rm -rf build
