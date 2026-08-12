# switchVK SDK（基于公开 NXVK）

这个目录把公开的 [`beiklive/nxvk`](https://github.com/beiklive/nxvk) Switch 分支整理成
GBAStation 两个核心现有构建脚本所需要的 SDK 格式。NXVK 原始构建会产生
`libnvk.a` 和多组 Mesa 支持库；本项目将这些归档合并成一个可被 NRO 静态链接的
`lib/libvulkan.a`，并保留原始归档用于诊断。

## 目录布局

```text
switchVK/
├── nxvk-source/                    # 公开 NXVK 源码（switch 分支子模块）
├── build_local.sh                  # 配置/编译 NXVK 并生成 SDK
├── package_sdk.sh                  # 从已有 cross build 生成 SDK
├── verify_sdk.sh                   # 检查头文件、归档和 NVK/WSI 符号
└── nvk-switch-26.1.4/
    ├── include/vulkan/*.h
    ├── lib/libvulkan.a             # 合并后的单一静态归档
    ├── lib/libnvk.a                # 原始 NVK 归档
    ├── lib/archives/*.a            # Mesa 支持归档
    ├── metadata.json
    ├── archive-manifest.txt
    └── symbols.txt
```

GitHub Actions 会把 SDK 发布为 `switchVK-26.1.4.tar.xz` 和
`switchVK-26.1.4-diagnostic.tar.xz`。归档内的目录名仍是
`nvk-switch-26.1.4[-diagnostic]`，正好匹配两个核心当前的 SDK 查找逻辑。

## Linux 构建

需要 devkitPro devkita64、Meson、Ninja、Python、Rust/bindgen/cbindgen，以及公开
NXVK 文档中列出的 Mesa 主机构建工具。NXVK 自带 Dockerfile；若使用容器，应在
容器内执行同一个脚本并把本目录挂载到 `/work`：

```sh
cd /mnt/mac/Volumes/Repositories/core/switchVK
bash ci/build-sdk-in-container.sh
```

脚本会自动构建 SPIR-V-Headers/SPIRV-Tools、准备 Rust sysroot，先运行 NXVK 的
`build-native-tools.sh` 和 `configure-mesa.sh`，再让 Ninja
构建所有 Mesa 静态归档。最终 `libvulkan_nouveau.so` 的链接失败是 NXVK 文档中
明确允许的；脚本只要求所有静态归档已经生成，然后执行 SDK 合并和符号审计。

如果已经有 `switch/build/cross`，也可以只打包：

```sh
bash package_sdk.sh
bash verify_sdk.sh nvk-switch-26.1.4
```

## 链接契约

合并归档使用 NXVK 文档要求的 `--whole-archive` 语义。它必须包含以下入口：

```text
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
```

3DS 核心还会从归档中提取其余 `nvk_*`、`vk_common_*`、`wsi_*` 入口，PPSSPP 核心
通过 `vk_icdGetInstanceProcAddr` 解析 Vulkan 函数。SDK 不提供动态 `.so`，也不
尝试在 Switch 上运行时加载驱动。

## 版本和来源

当前 SDK 版本目录使用 Mesa/NXVK 的 `26.1.4`，与公开 NXVK Switch 分支 README
一致。`metadata.json` 会记录 NXVK commit、构建时间、目标架构和合并归档清单，
便于以后更新 Mesa 后重新审计。
