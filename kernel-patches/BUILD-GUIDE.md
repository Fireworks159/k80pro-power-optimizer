# K80 Pro 自定义内核编译指南

## 概述

本指南帮助你从源码编译一个完整的 K80 Pro 自定义内核，集成：

| 功能 | 说明 |
|------|------|
| **SukiSU-Ultra** | 基于 KernelSU 的内核级 Root |
| **不公平调度** | vivo OriginOS 风格的前台优先 EEVDF 调度 (Patch 1) |
| **EEVDF 调优** | SM8750 双集群 Oryon 拓扑的调度器参数优化 (Patch 2) |
| **PM 遥测** | 挂起/恢复周期计数与统计 (Patch 3) |

---

## 零环境云端编译（最推荐）

**无需安装 WSL2 或 Linux，无需本地编译！**

项目已配置好 GitHub Actions CI，推送代码到 GitHub 后在云端自动编译，30-45 分钟后直接下载刷入 ZIP。

> 详细操作指南: [GITHUB-SETUP.md](../GITHUB-SETUP.md)

**三步完成：**

```
1. 推送代码到 GitHub → 2. 点击 Actions 编译 → 3. 下载内核 ZIP
```

---

## 自动化构建（本地 WSL2/Linux）

### 1. 准备环境

```bash
# Ubuntu 22.04+ / Debian 12+
sudo apt update
sudo apt install -y git build-essential bc bison flex \
    libncurses-dev libssl-dev libelf-dev libmpc-dev \
    libgmp-dev texinfo python3 python3-pip ccache curl zip zstd
```

### 2. 一键构建

```bash
cd k80pro-power-optimizer/kernel-build
bash build-kernel.sh
```

脚本自动完成：
1. 检查构建环境（磁盘/内存/工具）
2. 下载 NeutronClang 编译器
3. 克隆 Xiaomi bsp-miro-v-oss 内核源码
4. 修复 MiCode OSS 缺失的 Kconfig 引用
5. 运行 SukiSU-Ultra 集成脚本
6. 应用不公平调度 + EEVDF 调优 + PM 遥测补丁
7. 自动查找并配置 defconfig
8. 编译内核（15-30 分钟）
9. AnyKernel3 打包为可刷入 ZIP

### 构建选项

```bash
# 使用系统 Clang 而非 NeutronClang
TOOLCHAIN=system bash build-kernel.sh

# 跳过 SukiSU-Ultra 集成（内核仍可编译）
SKIP_SUKISU=1 bash build-kernel.sh

# 跳过省电补丁（纯原生内核）
SKIP_PATCHES=1 bash build-kernel.sh

# 清理后重新编译
CLEAN_BUILD=1 bash build-kernel.sh

# 指定并行线程数
JOBS=8 bash build-kernel.sh
```

---

## 手动编译步骤

### Step 1: 获取内核源码

```bash
git clone --depth 1 -b bsp-miro-v-oss \
    https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git \
    k80pro-kernel
cd k80pro-kernel
```

### Step 2: (可选) 集成 SukiSU-Ultra

```bash
# 方式一: 使用官方脚本
curl -LSs https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh \
    | bash -s main

# 方式二: 手动集成
git clone --depth 1 https://github.com/SukiSU-Ultra/SukiSU-Ultra.git KernelSU
ln -sf "$(realpath KernelSU/kernel)" drivers/kernelsu
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
```

### Step 3: 应用内核补丁

```bash
# 修复可能的 broken symlink
for dir in "drivers/power/supply/mca"; do
    [ -L "$dir" ] && rm -f "$dir" && mkdir -p "$dir"
done
for kpath in $(grep -roh '^source "[^"]*"' $(find . -name "Kconfig") | sed 's/^source "//;s/"$//' | sort -u); do
    [ ! -f "$kpath" ] && mkdir -p "$(dirname "$kpath")" && echo "# Stub" > "$kpath"
done

# 应用三个补丁
git am /path/to/kernel-patches/0001-scheduler-unfair-boost.patch
git am /path/to/kernel-patches/0002-cpu-governor-tuning.patch
git am /path/to/kernel-patches/0003-power-management.patch
```

如果 `git am` 失败（通常是因为 SukiSU 集成修改了 Makefile/Kconfig 但未提交），可以用 `git apply`：

```bash
git apply /path/to/kernel-patches/0001-scheduler-unfair-boost.patch
git apply /path/to/kernel-patches/0002-cpu-governor-tuning.patch
git apply /path/to/kernel-patches/0003-power-management.patch
```

### Step 4: 配置内核

```bash
export ARCH=arm64

# GKI + vendor fragments 方式
make O=out gki_defconfig

# 查找并合并 vendor fragments
FRAG_DIR=""
for d in arch/arm64/configs/vendor vendor arch/arm64/configs; do
    if [ -f "$d/sun_perf.config" ] && [ -f "$d/miro_perf.config" ]; then
        FRAG_DIR="$d"
        break
    fi
done

if [ -n "$FRAG_DIR" ]; then
    ./scripts/kconfig/merge_config.sh -m -O out \
        "$FRAG_DIR/sun_perf.config" "$FRAG_DIR/miro_perf.config"
fi

# 追加自定义配置
cat /path/to/kernel-patches/defconfig-additions.conf >> out/.config
make O=out olddefconfig
```

### Step 5: 编译

```bash
export CC=clang
make O=out ARCH=arm64 LLVM=1 -j$(nproc)
```

编译时间: 约 15-30 分钟（取决于机器性能）

### Step 6: 打包刷入

```bash
# 创建 AnyKernel3 ZIP
mkdir -p release
cd release
cp /path/to/anykernel/* .
cp ../out/arch/arm64/boot/Image kernel
zip -r K80Pro-Power-Kernel.zip .

# 传到手机刷入
adb push K80Pro-Power-Kernel.zip /sdcard/
# 在 Magisk/KernelSU 中刷入 ZIP 并重启
```

---

## 故障排除

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `git am` 失败 | working tree 有未提交修改 | 用 `git apply` 代替 |
| `git apply --check` 失败 | 内核源码版本不匹配 | 确认使用 `bsp-miro-v-oss` 分支 |
| `undefined reference` 错误 | 符号在 6.6 中已改名 | 本项目补丁已处理 |
| `-Werror` 错误 | NeutronClang 警告升级为错误 | `defconfig-additions.conf` 已禁用 WERROR |
| Kconfig `source` 找不到文件 | MiCode OSS broken symlink | 运行 `fix_micode_kconfig` 步骤 |
| `CONFIG_KSU` 未定义 | SukiSU 集成失败 | 跳过 SukiSU (`SKIP_SUKISU=1`) |

---

## 验证编译产物

```bash
# 检查内核版本
file out/arch/arm64/boot/Image

# 检查补丁是否生效
strings out/arch/arm64/boot/Image | grep "k80pro"
# 应看到: k80pro_unfair, k80pro_tune, k80pro_pm

# 检查 SukiSU
strings out/arch/arm64/boot/Image | grep -i "kernelsu"
```