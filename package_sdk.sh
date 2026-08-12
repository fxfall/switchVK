#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$ROOT/nxvk-source
BUILD_DIR=
OUTPUT=
VERSION=26.1.4
VARIANT=release

usage() {
    echo "Usage: package_sdk.sh [--source DIR] --build DIR --output DIR [--version X.Y.Z] [--variant release|diagnostic]"
}

while (($#)); do
    case "$1" in
        --source) SOURCE_DIR=${2:?missing source}; shift 2 ;;
        --build) BUILD_DIR=${2:?missing build}; shift 2 ;;
        --output) OUTPUT=${2:?missing output}; shift 2 ;;
        --version) VERSION=${2:?missing version}; shift 2 ;;
        --variant) VARIANT=${2:?missing variant}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$BUILD_DIR" && -n "$OUTPUT" ]] || { usage >&2; exit 2; }
[[ "$VARIANT" == release || "$VARIANT" == diagnostic ]] || {
    echo "ERROR: variant must be release or diagnostic" >&2
    exit 2
}
[[ -d "$SOURCE_DIR/include/vulkan" ]] || {
    echo "ERROR: Vulkan headers missing: $SOURCE_DIR/include/vulkan" >&2
    exit 1
}
[[ -f "$BUILD_DIR/src/nouveau/vulkan/libnvk.a" ]] || {
    echo "ERROR: missing $BUILD_DIR/src/nouveau/vulkan/libnvk.a" >&2
    exit 1
}

DEVKITPRO=${DEVKITPRO:-/opt/devkitpro}
AR=${AR:-$DEVKITPRO/devkitA64/bin/aarch64-none-elf-ar}
RANLIB=${RANLIB:-$DEVKITPRO/devkitA64/bin/aarch64-none-elf-ranlib}
NM=${NM:-$DEVKITPRO/devkitA64/bin/aarch64-none-elf-nm}
[[ -x "$AR" && -x "$RANLIB" && -x "$NM" ]] || {
    echo "ERROR: devkitA64 ar/ranlib/nm are required" >&2
    exit 1
}

case "$VERSION" in
    ''|*[!0-9.]*|*.*.*.*)
        echo "ERROR: invalid SDK version: $VERSION" >&2
        exit 2
        ;;
esac

TMP=$(mktemp -d "${TMPDIR:-/tmp}/switchvk-package.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
mkdir -p "$STAGE/include" "$STAGE/lib/archives"
cp -R "$SOURCE_DIR/include/vulkan" "$STAGE/include/"

ARCHIVES=()
while IFS= read -r archive; do
    ARCHIVES+=("$archive")
done < <(find "$BUILD_DIR/src" -type f -name '*.a' -print | sort)
[[ ${#ARCHIVES[@]} -gt 0 ]] || {
    echo "ERROR: no Mesa archives found" >&2
    exit 1
}

# Keep every cross-built Mesa archive in a private subdirectory, then merge all
# object members into libvulkan.a. This avoids depending on a fragile hand-made
# archive order and makes the SDK consumable by both CMake frontends.
for archive in "${ARCHIVES[@]}"; do
    rel=${archive#"$BUILD_DIR/"}
    mkdir -p "$STAGE/lib/archives/$(dirname "$rel")"
    cp "$archive" "$STAGE/lib/archives/$rel"
done

MERGE="$TMP/objects"
mkdir -p "$MERGE"
index=0
for archive in "${ARCHIVES[@]}"; do
    dir="$MERGE/$(printf '%05d' "$index")"
    mkdir -p "$dir"
    # Mesa's Meson static targets are thin archives.  `ar x` rejects thin
    # archives, while printing each member with `ar p` works for both thin and
    # regular archives and gives us self-contained object files for the merged
    # SDK archive.
    member_index=0
    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        object="$dir/$(printf '%05d' "$member_index")-$(basename "$member")"
        "$AR" p "$archive" "$member" > "$object"
        member_index=$((member_index + 1))
    done < <("$AR" t "$archive")
    index=$((index + 1))
done

mkdir -p "$STAGE/lib"
MERGED="$STAGE/lib/libvulkan.a"
rm -f "$MERGED"
for object in "$MERGE"/*/*.o; do
    [[ -f "$object" ]] || continue
    "$AR" q "$MERGED" "$object" >/dev/null
done
"$RANLIB" "$MERGED"
cp "$BUILD_DIR/src/nouveau/vulkan/libnvk.a" "$STAGE/lib/libnvk.a"

sha256sum "$MERGED" > "$STAGE/lib/libvulkan.a.sha256"

"$NM" --defined-only --extern-only "$MERGED" > "$STAGE/symbols.txt"
find "$BUILD_DIR/src" -type f -name '*.a' -print | sed "s#^$BUILD_DIR/##" > "$STAGE/archive-manifest.txt"

source_commit=unknown
if git -C "$SOURCE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    source_commit=$(git -C "$SOURCE_DIR" rev-parse HEAD)
fi
python3 - "$STAGE/metadata.json" "$VERSION" "$VARIANT" "$source_commit" "${#ARCHIVES[@]}" <<'PY'
import json
import pathlib
import sys

out, version, variant, commit, archive_count = sys.argv[1:]
pathlib.Path(out).write_text(json.dumps({
    "schema": 1,
    "name": "switchVK",
    "version": version,
    "variant": variant,
    "mesa": version,
    "source": "beiklive/nxvk",
    "source_commit": commit,
    "target": "Nintendo Switch Horizon / Tegra X1 GM20B",
    "architecture": "aarch64-none-elf",
    "archive_count": int(archive_count),
    "link_model": "static-whole-archive",
    "entrypoint": "vk_icdGetInstanceProcAddr",
}, indent=2) + "\n", encoding="utf-8")
PY

rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
mv "$STAGE" "$OUTPUT"
