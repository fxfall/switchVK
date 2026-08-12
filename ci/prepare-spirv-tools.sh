#!/usr/bin/env bash
set -euo pipefail

PREFIX=${1:?Usage: prepare-spirv-tools.sh /path/to/prefix [jobs]}
JOBS=${2:-${SWITCHVK_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}}
TOOLS_VERSION=${SPIRV_TOOLS_VERSION:-v2025.1}
HEADERS_VERSION=${SPIRV_HEADERS_VERSION:-vulkan-sdk-1.4.309.0}
TMP_ROOT=${SWITCHVK_DEPS_TMP:-/tmp/switchvk-deps}

mkdir -p "$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

if version=$(pkg-config --modversion SPIRV-Tools 2>/dev/null); then
    if python3 - "$version" <<'PY'
import re
import sys

match = re.match(r"(\d+)\.(\d+)", sys.argv[1])
raise SystemExit(0 if match and (int(match.group(1)), int(match.group(2))) >= (2024, 1) else 1)
PY
    then
        echo "Using SPIRV-Tools $version from $PREFIX"
        exit 0
    fi
fi

mkdir -p "$TMP_ROOT"
HEADERS="$TMP_ROOT/spirv-headers"
TOOLS="$TMP_ROOT/spirv-tools"
BUILD="$TMP_ROOT/spirv-tools-build"

if [[ ! -d "$HEADERS/.git" ]]; then
    rm -rf "$HEADERS"
    git clone --depth 1 --branch "$HEADERS_VERSION" \
        https://github.com/KhronosGroup/SPIRV-Headers.git "$HEADERS"
fi
if [[ ! -d "$TOOLS/.git" ]]; then
    rm -rf "$TOOLS"
    git clone --depth 1 --branch "$TOOLS_VERSION" \
        https://github.com/KhronosGroup/SPIRV-Tools.git "$TOOLS"
fi

cmake -S "$TOOLS" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_TOOLS_BUILD_STATIC=ON \
    -DSPIRV-Headers_SOURCE_DIR="$HEADERS"
cmake --build "$BUILD" -j "$JOBS"
cmake --install "$BUILD"

version=$(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --modversion SPIRV-Tools)
echo "Prepared SPIRV-Tools $version in $PREFIX"
