#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=${1:?Usage: apply-nxvk-patches.sh /path/to/nxvk}

for patch in "$ROOT"/patches/nxvk-*.patch; do
    [[ -f "$patch" ]] || continue
    if git -C "$SOURCE" apply --check "$patch" >/dev/null 2>&1; then
        git -C "$SOURCE" apply "$patch"
        echo "Applied $(basename "$patch")"
    elif git -C "$SOURCE" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "Already applied $(basename "$patch")"
    else
        echo "ERROR: NXVK patch does not apply cleanly: $patch" >&2
        exit 1
    fi
done
