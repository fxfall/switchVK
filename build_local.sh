#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=${NXVK_SOURCE_DIR:-"$ROOT/nxvk-source"}
BUILD_DIR=${CROSS_BUILD:-"$SOURCE_DIR/switch/build/cross"}
NATIVE_DIR=${NATIVE_PREFIX:-"$SOURCE_DIR/switch/build/native-tools"}
SPIRV_PREFIX=${SPIRV_PREFIX:-"$ROOT/.switchvk-tmp/spirv-tools-prefix"}
JOBS=${SWITCHVK_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
VERSION=${SWITCHVK_VERSION:-26.1.4}
VARIANT=release
REBUILD=0

usage() {
    cat <<'EOF'
Usage: bash build_local.sh [--rebuild] [--diagnostic] [-j JOBS]

Build public NXVK for Nintendo Switch and package nvk-switch-26.1.4[-diagnostic].
The script must run in a devkitPro/Meson build environment. The NXVK source is
read from nxvk-source unless NXVK_SOURCE_DIR is set.
EOF
}

while (($#)); do
    case "$1" in
        --rebuild) REBUILD=1; shift ;;
        --diagnostic) VARIANT=diagnostic; shift ;;
        -j|--jobs) JOBS=${2:?missing job count}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid job count: $JOBS" >&2; exit 2; }
[[ -f "$SOURCE_DIR/switch/build/configure-mesa.sh" ]] || {
    echo "ERROR: NXVK source not found: $SOURCE_DIR" >&2
    echo "Clone the public switch branch into switchVK/nxvk-source first." >&2
    exit 1
}
command -v meson >/dev/null 2>&1 || { echo "ERROR: meson is required" >&2; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "ERROR: ninja is required" >&2; exit 1; }
[[ -n "${DEVKITPRO:-}" ]] || export DEVKITPRO=/opt/devkitpro
[[ -x "$DEVKITPRO/devkitA64/bin/aarch64-none-elf-gcc" ]] || {
    echo "ERROR: devkitA64 toolchain not found under $DEVKITPRO" >&2
    exit 1
}

if ((REBUILD)); then
    rm -rf "$BUILD_DIR" "$NATIVE_DIR"
fi

# Meson's Rust cross file refers to the wrapper by name. Keep the wrapper
# beside the checked-out NXVK tree on PATH so the build works regardless of
# whether the source is mounted at /work, /workspace, or another path.
export PATH="$SOURCE_DIR/switch/rust:$DEVKITPRO/devkitA64/bin:$DEVKITPRO/tools/bin:$NATIVE_DIR/bin:$PATH"
export NXVK_SOURCE_DIR="$SOURCE_DIR"

bash "$ROOT/ci/apply-nxvk-patches.sh" "$SOURCE_DIR"
bash "$ROOT/ci/prepare-spirv-tools.sh" "$SPIRV_PREFIX" "$JOBS"
bash "$ROOT/ci/prepare-rust.sh" "$SOURCE_DIR"
export PKG_CONFIG_PATH="$SPIRV_PREFIX/lib/pkgconfig:$SPIRV_PREFIX/lib/aarch64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="$SPIRV_PREFIX/lib/pkgconfig:$SPIRV_PREFIX/lib/aarch64-linux-gnu/pkgconfig:$DEVKITPRO/portlibs/switch/lib/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"

if [[ ! -x "$NATIVE_DIR/bin/mesa_clc" || ! -x "$NATIVE_DIR/bin/vtn_bindgen2" ]]; then
    SRC="$SOURCE_DIR" bash "$SOURCE_DIR/switch/build/build-native-tools.sh"
fi
SRC="$SOURCE_DIR" bash "$SOURCE_DIR/switch/build/configure-mesa.sh"

# NXVK documents that the final shared ICD link is expected to fail on Horizon.
# Building that target with -k0 forces Ninja to materialize every static archive.
set +e
ninja -k0 -C "$BUILD_DIR" -j "$JOBS" src/nouveau/vulkan/libvulkan_nouveau.so
status=$?
set -e
if [[ ! -f "$BUILD_DIR/src/nouveau/vulkan/libnvk.a" ]]; then
    echo "ERROR: NXVK did not produce libnvk.a (ninja status $status)" >&2
    exit 1
fi

PACKAGE_VERSION="nvk-switch-${VERSION}"
[[ "$VARIANT" == diagnostic ]] && PACKAGE_VERSION+="-diagnostic"
bash "$ROOT/package_sdk.sh" \
    --source "$SOURCE_DIR" \
    --build "$BUILD_DIR" \
    --output "$ROOT/$PACKAGE_VERSION" \
    --version "$VERSION" \
    --variant "$VARIANT"
bash "$ROOT/verify_sdk.sh" "$ROOT/$PACKAGE_VERSION"
echo "OK: SDK generated at $ROOT/$PACKAGE_VERSION (ninja status $status)"
