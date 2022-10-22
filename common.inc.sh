SUBMODULE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONTRIB_ROOT_PATH="$(realpath "$SUBMODULE_DIR/..")"
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

  FULL_PATH="$PACKAGE_ROOT/$FILENAME$EXTENSION"

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

use_hardened_flags() {
  export ALPINE_CFLAGS="$(strip_flags "$CFLAGS_COMMON $1")"
  export ALPINE_LDFLAGS="$(strip_flags "$2") -Wl,-lhardened_malloc"
}
use_unhardened_flags() {
  export ALPINE_CFLAGS="$(strip_flags "$CFLAGS_COMMON_UNHARDENED $1")"
  export ALPINE_LDFLAGS="$(strip_flags "$2")"
}
use_flags() {
  export ALPINE_CFLAGS="$(strip_flags "$1")"
  export ALPINE_LDFLAGS="$(strip_flags "$1 $2")"
}

strip_flags() {
  # shellcheck disable=SC2001
  echo -n " $1 " | tr -d "\n" | sed -e "s/\s\+/ /g"
}
apk_add_package() {
  apk $APK_FLAGS add "$@"
}

alpine() {
  PATH="$ALPINE_ROOT/bin:$ALPINE_ROOT/usr/bin" \
  LD_LIBRARY_PATH="$ALPINE_ROOT/lib:$ALPINE_ROOT/usr/lib" \
    "$ALPINE_ROOT/usr/bin/proot" \
      -r "$ALPINE_ROOT" -b "$REPO_ROOT" \
      -b ~/.abuild -b ~/.rustup/toolchains -b ~/.rustup/update-hashes \
      -b /etc/passwd -b /etc/group -b /etc/resolv.conf -b /etc/localtime \
      -b /dev -b /sys -b /proc -b /tmp -b /run -b /var/run/dbus/system_bus_socket \
    /bin/busybox env -i \
      USER="$USER" HOME="/home/$USER" LANG="$LANG" TERM="$TERM" \
      PATH="/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/sbin:/usr/local/bin:$HOME/.cargo/bin:$ALPINE_USR_ROOT/bin" \
      AR="llvm-ar" RANLIB="llvm-ranlib" CC="clang" CXX="clang++" \
      LIBRARY_PATH="$ALPINE_USR_ROOT/lib:/lib:/usr/lib:/usr/local/lib" \
      C_INCLUDE_PATH="$ALPINE_USR_ROOT/include:/include:/usr/include:/usr/local/include" \
      CPLUS_INCLUDE_PATH="$ALPINE_USR_ROOT/include:/include:/usr/include:/usr/local/include" \
      CFLAGS="$ALPINE_CFLAGS" ALPINE_LDFLAGS="$ALPINE_LDFLAGS" \
    "$@"
}
abuild_dir() {
  mkdir -p "$APK_BUILD_ROOT" "$APK_REPO_ROOT"

  CWD_RET="$(pwd)"
  PKG_NAME="$(basename "$1")"

  cd "$APK_BUILD_ROOT" || exit 1
    cp -r "$1" "$PKG_NAME" || exit 1
    cd "$PKG_NAME" || exit 1
      alpine abuild -d -P"$APK_REPO_ROOT" || exit 1
    cd .. || exit 1
  cd "$CWD_RET" || exit 1
}
apk() {
  alpine apk -X "$APK_REPO_ROOT/apk_packages" --cache-dir "$PACKAGE_ROOT/apk_cache" "$@"
}

# Important internal variables
ALPINE_ROOT="$(root_path alpine_root)"
ALPINE_USR_ROOT="$(root_path alpine_usr)"
PACKAGE_ROOT="$(root_path packages)"
REPO_ROOT="$(dirname "$(cargo locate-project --workspace --message-format plain || exit 1)")"
APK_BUILD_ROOT="$(root_path build/apk_packages)"
APK_REPO_ROOT="$(root_path build/apk_repo)"
APK_PACKAGE_ROOT="$APK_REPO_ROOT/apk_packages/x86_64"

# Common C Flags
if [ "$OPT_LEVEL" = "" ]; then
  OPT_LEVEL="-Os"
fi

CFLAGS_BASIC="$(strip_flags "
  -fuse-ld=lld -rtlib=compiler-rt -pie -fPIE
  -Wno-unused-command-line-argument -Wno-unknown-warning-option
")"
CFLAGS_STATIC="$(strip_flags "
  -static -all-static -Wl,--static,--as-needed -static-pie
")"
CFLAGS_LTO="$(strip_flags "
  -flto=full -Wl,--lto-whole-program-visibility
")"
CFLAGS_HARDENING_BASIC="$(strip_flags "
  -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fstack-clash-protection
")"
CFLAGS_HARDENING="$(strip_flags "
  $CFLAGS_LTO $CFLAGS_HARDENING_BASIC
  -fsanitize=cfi -fvirtual-function-elimination -fsanitize=safe-stack
")"

CFLAGS_COMMON="$CFLAGS_STATIC $OPT_LEVEL $CFLAGS_BASIC $CFLAGS_HARDENING -fvisibility=hidden"
CFLAGS_COMMON_UNHARDENED="$CFLAGS_STATIC $OPT_LEVEL $CFLAGS_BASIC $CFLAGS_LTO -fvisibility=hidden"

MAKE_CT="-j$(nproc)" # Flag for number of processors for `make`
