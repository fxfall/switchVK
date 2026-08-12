#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=${NXVK_SOURCE_DIR:-/work}
JOBS=${SWITCHVK_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
PREFIX=${SPIRV_PREFIX:-/spirv-tools-prefix}

export NXVK_SOURCE_DIR="$SOURCE"
export SPIRV_PREFIX="$PREFIX"
export SWITCHVK_DEPS_TMP=${SWITCHVK_DEPS_TMP:-/tmp/switchvk-deps}

bash "$ROOT/ci/apply-nxvk-patches.sh" "$SOURCE"
bash "$ROOT/ci/prepare-spirv-tools.sh" "$PREFIX" "$JOBS"
bash "$ROOT/ci/prepare-rust.sh" "$SOURCE"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/aarch64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/lib/aarch64-linux-gnu/pkgconfig:$DEVKITPRO/portlibs/switch/lib/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"

bash "$ROOT/build_local.sh" -j "$JOBS"
