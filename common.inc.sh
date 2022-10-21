SUBMODULE_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONTRIB_ROOT_PATH="$(realpath "$SUBMODULE_SCRIPT_DIR/..")"
cd "$CONTRIB_ROOT_PATH" || exit 1

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

  export LD_LIBRARY_PATH="$(root_path musl_root/lib):$(root_path musl_root/usr/lib)"
  export LIBRARY_PATH="$(root_path musl_usr/lib):$(root_path musl_root/lib):$(root_path musl_root/usr/lib)"
  export PATH="$(root_path musl_root/bin):$(root_path musl_root/sbin):$(root_path musl_root/usr/bin):$(root_path musl_root/usr/sbin)"
  export C_INCLUDE_PATH="$(root_path musl_root/usr/include)"
  export CPLUS_INCLUDE_PATH="$(root_path musl_root/usr/include)"

  export CFLAGS="$CFLAGS_COMMON_SIZE"
  export LDFLAGS="$CFLAGS_COMMON_SIZE"

  export APK="apk -p $(root_path musl_root)"
  export ABUILD_SHAREDIR="$(root_path musl_root/usr/share/abuild)"
  export FAKEROOT="fakeroot -l $(root_path musl_root/usr/lib/libfakeroot.so)"
}

strip_flags() {
  # shellcheck disable=SC2001
  echo -n " $1 " | tr -d "\n" | sed -e "s/\s\+/ /g"
}

# Common C Flags
BUILD_TARGET="x86_64-unknown-linux-gnu"

CFLAGS_BASIC="
  -target $BUILD_TARGET -rtlib=compiler-rt -L $(root_path musl_root/lib) -L $(root_path musl_root/usr/lib)
"
CFLAGS_LTO="
  -flto=full -fuse-ld=lld
"
CFLAGS_HARDENING_BASIC="
  -D_FORTIFY_SOURCE=2 -fPIE
  -fstack-protector-strong -fsanitize=safe-stack -fPIE -fstack-clash-protection
"
CFLAGS_HARDENING="
  $CFLAGS_LTO $CFLAGS_HARDENING_BASIC
  -fsanitize=cfi -fvisibility=hidden -fvirtual-function-elimination
"

CFLAGS_COMMON_SIZE="-Os -static $(strip_flags "$CFLAGS_BASIC") $(strip_flags "$CFLAGS_HARDENING")"
CFLAGS_COMMON_OPT="-O2 -static $(strip_flags "$CFLAGS_BASIC") $(strip_flags "$CFLAGS_HARDENING")"

CFLAGS_COMMON_UNHARDENED_SIZE="-Os -static $(strip_flags "$CFLAGS_BASIC") $(strip_flags "$CFLAGS_LTO")"
CFLAGS_COMMON_UNHARDENED_OPT="-O2 -static $(strip_flags "$CFLAGS_BASIC") $(strip_flags "$CFLAGS_LTO")"

CFLAGS_ABULID="-O2 $(strip_flags "$CFLAGS_BASIC") $(strip_flags "$CFLAGS_HARDENING_BASIC")"

MAKE_CT="-j$(nproc --all)" # Flag for number of processors for `make`
