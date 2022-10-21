#!/bin/bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. $SCRIPT_DIR/common.inc.sh

# Configuration
MIRROR="https://dl-cdn.alpinelinux.org/alpine"

APK_TOOLS_FILENAME="apk-tools-static-2.12.9-r3.apk"
APK_TOOLS_URL="$MIRROR/v3.16/main/x86_64/$APK_TOOLS_FILENAME"

ALPINE_KEYS_FILENAME="alpine-keys-2.4-r1.apk"
ALPINE_KEYS_URL="$MIRROR/v3.16/main/x86_64/$ALPINE_KEYS_FILENAME"

# Recreate the relevant directories
rm -rf build
mkdir build || exit

rm -rf musl_root
mkdir musl_root || exit

# Download and extract the bootstrap
mkdir build/apk || exit
cd build/apk || exit
  wget $APK_TOOLS_URL $ALPINE_KEYS_URL || exit
  sha256sum -c ../../src/alpine_sha256sum || exit

  tar -x -f $APK_TOOLS_FILENAME || exit
  tar -x -f $ALPINE_KEYS_FILENAME || exit

  export PATH="$(realpath sbin):$PATH"
  export APK_KEYS_PATH="$(realpath usr/share/apk/keys)"
cd ../.. || exit

# Bootstrap Alpine Linux
apk.static \
  -X "$MIRROR/edge/main" -U -p musl_root --initdb \
  --keys-dir "$APK_KEYS_PATH" --cache-dir "$(root_path packages/apk_cache)" add \
  alpine-base alpine-sdk libc6-compat llvm15 clang15 gcc lld libstdc++-dev compiler-rt

# Activate the musl root since we're about to do some custom builds
use_musl_root
"$(/usr/bin/which busybox)" --install musl_root/bin || exit
/usr/bin/sed --in-place=.bak "s_/bin/ash -e_/usr/bin/env ash_" musl_root/usr/bin/abuild || exit

# Setup abuild and our new repository
export REPODEST="$(root_path build/packages)"
mkdir "$REPODEST" || exit
if [ ! -d ~/.abuild ]; then
  abuild-keygen -q -n -a || exit
fi

# Do the custom musl build
cd build || exit
  cp -r "$SCRIPT_DIR/musl" musl || exit
  cd musl || exit
    export CFLAGS="$CFLAGS_ABULID"
    SAFESTACK_O="$(root_path musl_root/usr/lib/clang)"
    SAFESTACK_O="$(echo "$SAFESTACK_O"/*/lib/linux/libclang_rt.safestack-x86_64.a)"
    export LDFLAGS="$LDFLAGS -Wl,$SAFESTACK_O"
    abuild || exit
  cd .. || exit
cd .. || exit

# Install our custom packages
apk \
  -X "$REPODEST/build" -U -p musl_root --keys-dir ~/.abuild --cache-dir "$(root_path packages/apk_cache)" \
  add libc6-compat musl musl-dbg musl-dev musl-libintl musl-utils
apk \
  -X "$REPODEST/build" -U -p musl_root --keys-dir ~/.abuild --cache-dir "$(root_path packages/apk_cache)" \
  upgrade

# Delete the build directory
rm -rf build
