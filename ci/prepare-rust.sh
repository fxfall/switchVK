#!/usr/bin/env bash
set -euo pipefail

SOURCE=${1:?Usage: prepare-rust.sh /path/to/nxvk}
TARGET=aarch64-switch-horizon
SYSROOT="$SOURCE/switch/rust/sysroot/lib/rustlib/$TARGET/lib"

if compgen -G "$SYSROOT/libstd-*.rlib" >/dev/null 2>&1; then
    echo "Using existing Rust sysroot: $SYSROOT"
    exit 0
fi

RUST_SYSROOT=$(rustc +nightly --print sysroot)
RUST_SRC="$RUST_SYSROOT/lib/rustlib/src/rust"
STD_FILE="$RUST_SRC/library/std/src/sys/fs/unix.rs"
LIBC_FILE=$(find "$RUST_SRC/library/vendor" -path '*/src/unix/newlib/mod.rs' -print -quit)

[[ -f "$STD_FILE" && -f "$LIBC_FILE" ]] || {
    echo "ERROR: rust-src/newlib sources not found under $RUST_SRC" >&2
    exit 1
}

# Current nightly's std expects libc::AT_FDCWD, while devkitPro's newlib
# module intentionally omits the glibc constant.  This is a container-local
# compatibility patch; it never modifies the NXVK checkout or the SDK ABI.
sed -i 's/libc::fchmodat(libc::AT_FDCWD, p.as_ptr(), perm.mode, 0)/libc::fchmodat(-100, p.as_ptr(), perm.mode, 0)/' "$STD_FILE"
if ! grep -q 'pub const AT_FDCWD' "$LIBC_FILE"; then
    sed -i '2i pub const AT_FDCWD: c_int = -100;' "$LIBC_FILE"
fi

bash "$SOURCE/switch/rust/build-std-sysroot.sh"
compgen -G "$SYSROOT/libstd-*.rlib" >/dev/null 2>&1 || {
    echo "ERROR: Rust sysroot did not produce libstd" >&2
    exit 1
}
echo "Prepared Rust sysroot: $SYSROOT"
