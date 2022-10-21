SUBMODULE_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONTRIB_ROOT_PATH="$(realpath "$SUBMODULE_SCRIPT_DIR/..")"
cd "$CONTRIB_ROOT_PATH" || exit 1

# Configuration
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"

APK_TOOLS_FILENAME="apk-tools-static-2.12.9-r3.apk"
APK_TOOLS_URL="$ALPINE_MIRROR/v3.16/main/x86_64/$APK_TOOLS_FILENAME"

ALPINE_KEYS_FILENAME="alpine-keys-2.4-r1.apk"
ALPINE_KEYS_URL="$ALPINE_MIRROR/v3.16/main/x86_64/$ALPINE_KEYS_FILENAME"

# Common functions
root_path() {
  # Absolute path so we don't end up using the Alpine Linux realpath
  /usr/bin/realpath --no-symlinks "$CONTRIB_ROOT_PATH/$1"
}

download_package() {
  TARGET_PATH="$1"
  FILENAME="$2"
  EXTENSION="$3"
  URL="$4"

  FULL_PATH="$CONTRIB_ROOT_PATH/packages/$FILENAME$EXTENSION"

  if [ ! -f "$FULL_PATH" ]; then
    echo "Downloading '$URL'"
    wget "$URL" -O "$FULL_PATH" || exit 1
  fi
  if [ "$TARGET_PATH" != "-" ]; then
    echo "Extracting '$FILENAME' to '$TARGET_PATH'"
    tar -x -f "$FULL_PATH" || exit 1
    mv "$FILENAME" "$TARGET_PATH" || exit 1
  fi
}

use_musl_root() {
  export AR="$(root_path musl_root/usr/bin/llvm-ar)"
  export RANLIB="$(root_path musl_root/usr/bin/llvm-ranlib)"
  export CC="$(root_path musl_root/usr/bin/clang)"
  export CXX="$(root_path musl_root/usr/bin/clang++)"

  export LD_LIBRARY_PATH="$(root_path musl_usr/lib):$(root_path musl_root/lib):$(root_path musl_root/usr/lib)"
  export LIBRARY_PATH="$(root_path musl_usr/lib):$(root_path musl_root/lib):$(root_path musl_root/usr/lib)"
  export PATH="$(root_path musl_usr/bin):$(root_path musl_root/bin):$(root_path musl_root/sbin):$(root_path musl_root/usr/bin):$(root_path musl_root/usr/sbin)"
  export C_INCLUDE_PATH="$(root_path musl_usr/include):$(root_path musl_root/usr/include)"
  export CPLUS_INCLUDE_PATH="$(root_path musl_usr/include):$(root_path musl_root/usr/include)"

  export CFLAGS="$CFLAGS_COMMON"
  export LDFLAGS="$LDFLAGS_COMMON"

  export APK="apk -p $(root_path musl_root)"
  export ABUILD_SHAREDIR="$(root_path musl_root/usr/share/abuild)"
  export FAKEROOT="fakeroot -l $(root_path musl_root/usr/lib/libfakeroot.so)"
}

use_hardened_flags() {
  export CFLAGS="$(strip_flags "$CFLAGS_COMMON $1")"
  export LDFLAGS="$(strip_flags "$CFLAGS_COMMON $1 $2")"
}
use_unhardened_flags() {
  export CFLAGS="$(strip_flags "$CFLAGS_COMMON_UNHARDENED $1")"
  export LDFLAGS="$(strip_flags "$CFLAGS_COMMON_UNHARDENED $1 $2")"
}

strip_flags() {
  # shellcheck disable=SC2001
  echo -n " $1 " | tr -d "\n" | sed -e "s/\s\+/ /g"
}

apk_add_package() {
  apk \
    -X "$ALPINE_MIRROR/edge/main" -U -p musl_root --initdb --cache-dir "$(root_path packages/apk_cache)" add \
    "$@"
}

# Common C Flags
BUILD_TARGET="x86_64-unknown-linux-musl"
if [ "$OPT_LEVEL" = "" ]; then
  OPT_LEVEL="-Os"
fi

CFLAGS_BASIC="$(strip_flags "
  $OPT_LEVEL -target $BUILD_TARGET
  -rtlib=compiler-rt -L$(root_path musl_root/usr/lib) -L$(root_path musl_root/lib)
  -static -Wl,--static
")"
CFLAGS_LTO="$(strip_flags "
  -flto=full -fuse-ld=lld
")"
CFLAGS_HARDENING_BASIC="$(strip_flags "
  -D_FORTIFY_SOURCE=2 -fPIE -fstack-protector-strong -fstack-clash-protection
")"
CFLAGS_HARDENING="$(strip_flags "
  $CFLAGS_LTO $CFLAGS_HARDENING_BASIC
  -fsanitize=cfi -fvisibility=hidden -fvirtual-function-elimination -fsanitize=safe-stack
")"

CFLAGS_COMMON="$CFLAGS_BASIC $CFLAGS_HARDENING"
CFLAGS_COMMON_UNHARDENED="$CFLAGS_BASIC $CFLAGS_LTO"
CFLAGS_ABULID_MUSL="$CFLAGS_BASIC $CFLAGS_HARDENING_BASIC"

MAKE_CT="-j$(nproc --all)" # Flag for number of processors for `make`
