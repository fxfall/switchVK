#!/usr/bin/env bash
set -euo pipefail

SDK=${1:?Usage: verify_sdk.sh /path/to/nvk-switch-X.Y.Z}
DEVKITPRO=${DEVKITPRO:-/opt/devkitpro}
NM=${NM:-$DEVKITPRO/devkitA64/bin/aarch64-none-elf-nm}
[[ -x "$NM" ]] || { echo "ERROR: missing target nm: $NM" >&2; exit 1; }
[[ -f "$SDK/lib/libvulkan.a" ]] || { echo "ERROR: missing lib/libvulkan.a" >&2; exit 1; }
[[ -f "$SDK/lib/libnvk.a" ]] || { echo "ERROR: missing lib/libnvk.a" >&2; exit 1; }
[[ -f "$SDK/include/vulkan/vulkan.h" ]] || { echo "ERROR: missing Vulkan headers" >&2; exit 1; }
[[ -f "$SDK/metadata.json" ]] || { echo "ERROR: missing metadata.json" >&2; exit 1; }

symbols="$SDK/.verify-symbols.txt"
trap 'rm -f "$symbols"' EXIT
"$NM" --defined-only --extern-only "$SDK/lib/libvulkan.a" > "$symbols"

required=(
    vk_icdGetInstanceProcAddr
    vk_icdNegotiateLoaderICDInterfaceVersion
    wsi_CreateViSurfaceNN
    wsi_CreateSwapchainKHR
    wsi_switch_init_wsi
    nvkmd_nvgpu_create_dev
    nvkmd_nvgpu_create_ctx
    nvkmd_nvgpu_alloc_mem
    nvkmd_nvgpu_alloc_va
    nvkmd_nvgpu_syncobj_type
    nvkmd_nvgpu_syncobj_set_fence
)
for symbol in "${required[@]}"; do
    if ! grep -Eq "[[:space:]]${symbol}$" "$symbols"; then
        echo "ERROR: SDK is missing required symbol: $symbol" >&2
        exit 1
    fi
done

archive_count=$(find "$SDK/lib/archives" -type f -name '*.a' 2>/dev/null | wc -l | tr -d ' ')
[[ "$archive_count" -gt 0 ]] || { echo "ERROR: no preserved Mesa archives" >&2; exit 1; }
echo "SDK verification passed"
echo "  root: $SDK"
echo "  archives: $archive_count"
echo "  required NVK/WSI symbols: ${#required[@]}"
