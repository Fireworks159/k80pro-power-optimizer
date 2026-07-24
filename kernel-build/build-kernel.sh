#!/bin/bash
# ================================================================
# K80 Pro 自定义内核构建脚本
# 纯内核方案: 集成 SukiSU-Ultra Root + 不公平调度省电优化
# ================================================================
#
# 使用方法:
#   bash build-kernel.sh
#
# 环境要求:
#   - Linux / WSL2 (Ubuntu 22.04+)
#   - 32GB+ 磁盘空间
#   - 16GB+ RAM
#
# 选项 (通过环境变量设置):
#   TOOLCHAIN=neutron    使用 NeutronClang (默认)
#   TOOLCHAIN=system      使用系统 clang
#   TOOLCHAIN=custom      使用自定义 clang 路径 ($CLANG_PATH)
#   JOBS=8                并行编译线程数 (默认: nproc)
#   DEFCONFIG=xxx         指定 defconfig 文件名
#   SKIP_SUKISU=1         跳过 SukiSU-Ultra 集成
#   SKIP_PATCHES=1        跳过省电补丁
#   CLEAN_BUILD=1         清理后重新编译
# ================================================================
set -e

# ---- 配置 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$PROJECT_DIR/kernel-source"
OUT_DIR="$KERNEL_DIR/out"
PATCHES_DIR="$PROJECT_DIR/kernel-patches"
ANY_KERNEL_DIR="$SCRIPT_DIR/anykernel"
RELEASE_DIR="$PROJECT_DIR/release"
TOOLCHAINS_DIR="$HOME/toolchains"

DEVICE_CODENAME="miro"
DEVICE_PLATFORM="sun"
KERNEL_BRANCH="bsp-miro-v-oss"
KERNEL_REPO="https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git"
SUKISU_REPO="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
SUKISU_BRANCH="${SUKISU_BRANCH:-main}"
SUKISU_SETUP_URL="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh"

KERNEL_VERSION="6.6.77-k80pro-v1.0"
BUILD_DATE=$(date +%Y%m%d-%H%M)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║    K80 Pro 自定义内核构建工具 v2.0                       ║"
    echo "║    纯内核方案: SukiSU-Ultra + 不公平调度 + EEVDF 调优    ║"
    echo "║    设备: Redmi K80 Pro ($DEVICE_CODENAME / SM8750)       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}
info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }
step()    { echo -e "\n${BLUE}${BOLD}[>>> $1]${NC}"; }
section() { echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}$1${NC}"; echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ---- 环境检查 ----
check_prerequisites() {
    section "1. 检查构建环境"
    local missing=()
    for cmd in git make curl python3 ccache; do
        command -v $cmd >/dev/null 2>&1 || missing+=($cmd)
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少必要工具: ${missing[*]}"
        echo "  请运行: sudo apt install -y git make curl python3 ccache"
        echo "  以及:   sudo apt install -y build-essential bc bison flex"
        echo "          sudo apt install -y libncurses-dev libssl-dev libelf-dev"
        echo "          sudo apt install -y libmpc-dev libgmp-dev texinfo"
        exit 1
    fi
    info "基本工具: 就绪"
    local available_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_gb" -lt 30 ] 2>/dev/null; then
        warn "磁盘剩余空间不足 30GB (当前: ${available_gb}G)"
        if [ "${CI:-0}" = "1" ]; then
            error "CI 环境磁盘空间不足，无法继续"
            exit 1
        fi
        read -p "继续? (y/N): " confirm
        [ "$confirm" != "y" ] && exit 1
    else
        info "磁盘空间: ${available_gb}GB 可用"
    fi
}

# ---- 准备编译器 ----
setup_toolchain() {
    section "2. 准备 Clang 编译器"
    local toolchain="${TOOLCHAIN:-neutron}"
    if [ "$toolchain" = "system" ]; then
        CC=$(command -v clang 2>/dev/null || true)
        if [ -z "$CC" ]; then
            error "系统 clang 未找到，请安装或使用 TOOLCHAIN=neutron"
            exit 1
        fi
        EXPORT_CC="clang"
        info "使用系统 Clang: $(clang --version | head -1)"
        return
    fi
    if [ "$toolchain" = "custom" ]; then
        if [ -z "${CLANG_PATH:-}" ]; then
            error "TOOLCHAIN=custom 但 CLANG_PATH 未设置"
            exit 1
        fi
        EXPORT_CC="clang"
        export PATH="$CLANG_PATH/bin:$PATH"
        info "使用自定义 Clang: $CLANG_PATH"
        return
    fi
    if [ ! -d "$TOOLCHAINS_DIR/neutron-clang/bin" ]; then
        info "下载 NeutronClang (通过 AntMan)..."
        mkdir -p "$TOOLCHAINS_DIR/neutron-clang"
        cd "$TOOLCHAINS_DIR/neutron-clang"
        curl -LO "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman" || {
            warn "AntMan 下载失败，尝试使用系统 clang"
            cd "$PROJECT_DIR"
            TOOLCHAIN="system"
            setup_toolchain
            return
        }
        chmod +x antman
        ./antman -S || {
            warn "NeutronClang 下载失败，尝试使用系统 clang"
            cd "$PROJECT_DIR"
            TOOLCHAIN="system"
            setup_toolchain
            return
        }
        cd "$PROJECT_DIR"
    fi
    EXPORT_CC="clang"
    export PATH="$TOOLCHAINS_DIR/neutron-clang/bin:$PATH"
    info "NeutronClang: $(clang --version 2>/dev/null | head -1 || echo '就绪')"
}

# ---- 获取内核源码 ----
clone_kernel_source() {
    section "3. 获取 K80 Pro 内核源码"
    if [ -d "$KERNEL_DIR/.git" ]; then
        info "内核源码目录已存在，更新中..."
        cd "$KERNEL_DIR"
        git fetch origin "$KERNEL_BRANCH" 2>/dev/null || true
        git reset --hard "origin/$KERNEL_BRANCH" 2>/dev/null || git reset --hard HEAD
        git clean -fdx
        cd "$PROJECT_DIR"
        info "内核源码: 已更新到最新"
        return
    fi
    info "克隆 Xiaomi Kernel OpenSource (分支: $KERNEL_BRANCH)..."
    git clone --depth 1 --branch "$KERNEL_BRANCH" \
        "$KERNEL_REPO" "$KERNEL_DIR" || {
        error "克隆失败！请检查网络连接"
        exit 1
    }
    info "内核源码: 就绪"
}

# ---- 修复 MiCode OSS 缺失的 Kconfig ----
fix_micode_kconfig() {
    section "4. 修复 MiCode OSS 缺失的 Kconfig 引用"
    cd "$KERNEL_DIR"
    local fixed=0

    ensure_dir() {
        local dir="$1"
        if [ -e "$dir" ] || [ -L "$dir" ]; then
            if [ ! -d "$dir" ]; then
                rm -f "$dir"
            fi
        fi
        mkdir -p "$dir" 2>/dev/null || true
    }

    # mca charger (broken symlink to proprietary code)
    ensure_dir "drivers/power/supply/mca"
    if [ ! -f "drivers/power/supply/mca/Kconfig" ]; then
        printf '%s\n' \
            'config MCA_CHARGER' \
            '	bool "MCA Charger support (stub)"' \
            '	default n' \
            '	help' \
            '	  Stub for missing MCA charger Kconfig in OSS kernel.' \
            '' \
            'config MCA_CHARGER_FG' \
            '	bool "MCA Fuel Gauge support (stub)"' \
            '	default n' \
            > drivers/power/supply/mca/Kconfig
        fixed=$((fixed + 1))
    fi

    # Scan all Kconfig source references
    for kpath in $(grep -roh '^source "[^"]*"' $(find . -name "Kconfig" -not -path "./out/*" 2>/dev/null) 2>/dev/null | sed 's/^source "//;s/"$//' | sort -u); do
        if [ -n "$kpath" ] && ! [ -f "$kpath" ]; then
            ensure_dir "$(dirname "$kpath")"
            echo "# Stub Kconfig for $kpath" > "$kpath"
            fixed=$((fixed + 1))
        fi
    done

    if [ "$fixed" -gt 0 ]; then
        info "修复了 $fixed 个缺失的 Kconfig 引用"
    else
        info "所有 Kconfig 引用已存在"
    fi

    # Cirrus DSP 驱动在 OSS / NeutronClang 下编译失败，
    # 但其 Kconfig 默认设为 m，olddefconfig 会反复打开。
    # 把 FW_CS_DSP 的默认值改为 n。
    if [ -f "drivers/firmware/cirrus/Kconfig" ]; then
        sed -i '/^config FW_CS_DSP$/,/^config /{s/default m/default n/}' drivers/firmware/cirrus/Kconfig 2>/dev/null || true
        info "已修改 Cirrus DSP Kconfig 默认值"
    fi

    cd "$PROJECT_DIR"
}

# ---- 集成 SukiSU-Ultra ----
integrate_sukisu() {
    section "5. 集成 SukiSU-Ultra (内核级 Root)"
    if [ "${SKIP_SUKISU:-0}" = "1" ]; then
        warn "已跳过 SukiSU-Ultra 集成 (SKIP_SUKISU=1)"
        warn "  注意: defconfig 中的 CONFIG_KSU=y 将被自动禁用"
        SUKISU_INTEGRATED=0
        return
    fi
    cd "$KERNEL_DIR"

    # Check if already integrated
    if [ -d "KernelSU" ] || [ -L "drivers/kernelsu" ] || [ -L "common/drivers/kernelsu" ]; then
        info "检测到已有 SukiSU-Ultra 集成，跳过"
        SUKISU_INTEGRATED=1
        cd "$PROJECT_DIR"
        return
    fi

    # Check directory structure
    local drivers_dir=""
    if [ -d "common/drivers" ]; then
        drivers_dir="common/drivers"
    elif [ -d "drivers" ]; then
        drivers_dir="drivers"
    else
        error "未找到 drivers/ 目录，内核源码结构异常"
        SUKISU_INTEGRATED=0
        cd "$PROJECT_DIR"
        return
    fi

    info "运行 SukiSU-Ultra 集成脚本 (分支: $SUKISU_BRANCH)..."

    # Try official setup.sh first
    if curl -LSs "$SUKISU_SETUP_URL" -o /tmp/sukisu-setup.sh 2>/dev/null; then
        chmod +x /tmp/sukisu-setup.sh
        if bash /tmp/sukisu-setup.sh "$SUKISU_BRANCH" 2>/dev/null; then
            info "SukiSU-Ultra: 集成完成 (官方脚本)"
            SUKISU_INTEGRATED=1
            cd "$PROJECT_DIR"
            return
        fi
        warn "官方 setup.sh 失败，尝试手动集成..."
    else
        warn "下载 setup.sh 失败，尝试手动集成..."
    fi

    # Manual integration fallback
    local sukisu_dir="$KERNEL_DIR/KernelSU"
    if [ ! -d "$sukisu_dir" ]; then
        if ! git clone --depth 1 -b "$SUKISU_BRANCH" "$SUKISU_REPO" "$sukisu_dir" 2>/dev/null; then
            git clone --depth 1 "$SUKISU_REPO" "$sukisu_dir" 2>/dev/null || {
                warn "SukiSU-Ultra 仓库克隆失败"
                SUKISU_INTEGRATED=0
                cd "$PROJECT_DIR"
                return
            }
        fi
    fi

    # Create symlink and update Makefile/Kconfig
    if [ -d "$drivers_dir" ]; then
        ln -sf "$(realpath "$sukisu_dir/kernel")" "$drivers_dir/kernelsu" 2>/dev/null || true
        grep -q "kernelsu" "$drivers_dir/Makefile" 2>/dev/null || \
            printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$drivers_dir/Makefile"
        grep -q 'source "drivers/kernelsu/Kconfig"' "$drivers_dir/Kconfig" 2>/dev/null || \
            sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "$drivers_dir/Kconfig" 2>/dev/null || true
    fi

    info "SukiSU-Ultra: 集成完成 (手动方式)"
    SUKISU_INTEGRATED=1
    cd "$PROJECT_DIR"
}

# ---- 集成 K80 Pro 内核模块 ----
apply_power_patches() {
    section "6. 集成 K80 Pro  unfair 调度 / EEVDF 调优 / PM 统计模块"
    if [ "${SKIP_PATCHES:-0}" = "1" ]; then
        warn "已跳过 K80 Pro 模块集成 (SKIP_PATCHES=1)"
        return
    fi
    cd "$PROJECT_DIR"

    local integrate_script="$SCRIPT_DIR/integrate-modules.py"
    if [ ! -f "$integrate_script" ]; then
        error "找不到集成脚本: $integrate_script"
        exit 1
    fi

    python3 "$integrate_script" "$KERNEL_DIR"
    if [ $? -ne 0 ]; then
        error "K80 Pro 内核模块集成失败"
        exit 1
    fi

    info "K80 Pro 内核模块: 集成完成"

    # Validate integration before continuing
    local validate_script="$SCRIPT_DIR/validate-integration.py"
    if [ -f "$validate_script" ]; then
        python3 "$validate_script" "$KERNEL_DIR"
        if [ $? -ne 0 ]; then
            error "K80 Pro 内核模块验证失败"
            exit 1
        fi
        info "K80 Pro 内核模块: 验证通过"
    fi

    cd "$PROJECT_DIR"
}

# ---- 配置内核 defconfig ----
configure_defconfig() {
    section "7. 配置内核编译选项"
    cd "$KERNEL_DIR"
    export ARCH=arm64

    # Strategy 1: Look for vendor-specific defconfig
    local defconfig=""
    local search_paths=(
        "arch/arm64/configs/vendor/sun-miro_defconfig"
        "arch/arm64/configs/vendor/sun_miro_defconfig"
        "arch/arm64/configs/vendor/sun_defconfig"
        "arch/arm64/configs/vendor/miro_defconfig"
        "arch/arm64/configs/sun-miro_defconfig"
        "arch/arm64/configs/sun_defconfig"
        "arch/arm64/configs/miro_defconfig"
    )

    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            defconfig="$path"
            info "找到 vendor defconfig: $defconfig"
            break
        fi
    done

    # Strategy 2: GKI defconfig + vendor fragments
    if [ -z "$defconfig" ]; then
        info "未找到 vendor defconfig，尝试 GKI + fragments..."
        local gki_base=""
        local frag_dir=""

        for gpath in "arch/arm64/configs/gki_defconfig" "gki_defconfig"; do
            if [ -f "$gpath" ]; then
                gki_base="$gpath"
                break
            fi
        done

        if [ -n "$gki_base" ]; then
            # Search for vendor fragments
            for fdir in "arch/arm64/configs/vendor" "vendor" "arch/arm64/configs"; do
                if [ -f "$fdir/sun_perf.config" ] && [ -f "$fdir/miro_perf.config" ]; then
                    frag_dir="$fdir"
                    break
                elif [ -f "$fdir/sun_consolidate.config" ] && [ -f "$fdir/miro_consolidate.config" ]; then
                    frag_dir="$fdir"
                    break
                fi
            done

            if [ -n "$frag_dir" ]; then
                info "使用 GKI defconfig + vendor fragments"
                make O="$OUT_DIR" ARCH=arm64 gki_defconfig 2>&1 | tail -3

                if [ -f "scripts/kconfig/merge_config.sh" ]; then
                    for frag in "$frag_dir"/*.config; do
                        [ -f "$frag" ] || continue
                        scripts/kconfig/merge_config.sh -m -O "$OUT_DIR" "$frag" 2>/dev/null || \
                            cat "$frag" >> "$OUT_DIR/.config"
                    done
                else
                    for frag in "$frag_dir"/*.config; do
                        [ -f "$frag" ] || continue
                        cat "$frag" >> "$OUT_DIR/.config"
                    done
                fi
                info "GKI + vendor fragments 已加载"
            else
                info "使用纯 GKI defconfig (无 vendor fragments)"
                make O="$OUT_DIR" ARCH=arm64 gki_defconfig 2>&1 | tail -3
            fi
        fi
    else
        # Use the found defconfig
        local defconfig_base=$(basename "$defconfig")
        make O="$OUT_DIR" ARCH=arm64 "$defconfig_base" 2>&1 | tail -3
        info "defconfig 已加载: $defconfig"
    fi

    # Verify .config exists
    if [ ! -f "$OUT_DIR/.config" ]; then
        error "内核配置文件未生成！"
        exit 1
    fi

    # Merge custom additions
    local additions="$PATCHES_DIR/defconfig-additions.conf"
    if [ -f "$additions" ]; then
        info "合并自定义内核配置..."

        local re_config='^CONFIG_([A-Za-z0-9_]+)=(.+)$'
        local re_notset='^# CONFIG_([A-Za-z0-9_]+) is not set$'

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Handle "not set" lines
            if [[ "$line" =~ $re_notset ]]; then
                local name="${BASH_REMATCH[1]}"
                scripts/config --file "$OUT_DIR/.config" --disable "CONFIG_$name" 2>/dev/null || true
                continue
            fi

            # Skip comments
            [[ "$line" =~ ^# ]] && continue

            # Handle CONFIG_XXX=y or CONFIG_XXX="string"
            if [[ "$line" =~ $re_config ]]; then
                local name="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"

                # Skip CONFIG_KSU if SukiSU not integrated
                if [ "$name" = "KSU" ] && [ "${SUKISU_INTEGRATED:-0}" != "1" ]; then
                    warn "  跳过 CONFIG_KSU=y (SukiSU 未集成)"
                    continue
                fi

                scripts/config --file "$OUT_DIR/.config" --enable "CONFIG_$name" 2>/dev/null || true
                if [ "$val" != "y" ]; then
                    val="${val%\"}"
                    val="${val#\"}"
                    scripts/config --file "$OUT_DIR/.config" --set-str "CONFIG_$name" "$val" 2>/dev/null || true
                fi
            fi
        done < "$additions"

        info "自定义配置已合并"
    fi

    # Set kernel version
    scripts/config --file "$OUT_DIR/.config" --set-str CONFIG_LOCALVERSION "-k80pro-optimized" 2>/dev/null || true

    # olddefconfig to resolve any inconsistencies
    make O="$OUT_DIR" ARCH=arm64 olddefconfig 2>&1 | tail -3

    # 强制禁用 MiCode OSS 中有问题的驱动
    for bad_cfg in CONFIG_PERF_HELPER CONFIG_FW_CS_DSP CONFIG_CL_DSP CONFIG_MTD_OOPS; do
        if grep -qE "^${bad_cfg}=(y|m)" "$OUT_DIR/.config"; then
            sed -i -E "s/^${bad_cfg}=(y|m)/# ${bad_cfg} is not set/" "$OUT_DIR/.config"
            echo "  已禁用 ${bad_cfg}"
        fi
    done

    if [ "${SUKISU_INTEGRATED:-0}" = "1" ]; then
        info "SukiSU 集成状态: 已启用 (CONFIG_KSU=y)"
    else
        warn "SukiSU 集成状态: 未启用 (CONFIG_KSU 已跳过)"
    fi

    cd "$PROJECT_DIR"
}

# ---- 编译内核 ----
compile_kernel() {
    section "8. 编译内核"
    cd "$KERNEL_DIR"

    local jobs="${JOBS:-$(nproc 2>/dev/null || echo 8)}"
    info "编译线程数: $jobs"

    if [ "${CLEAN_BUILD:-0}" = "1" ]; then
        info "清理旧编译产物..."
        make O="$OUT_DIR" ARCH=arm64 mrproper 2>/dev/null || true
    fi

    info "开始编译 (这可能需要 15-30 分钟)..."
    echo ""

    export CC="$EXPORT_CC"
    make O="$OUT_DIR" ARCH=arm64 LLVM=1 -j"$jobs" 2>&1 | tee "$PROJECT_DIR/build.log" | tail -20

    local ret=${PIPESTATUS[0]}
    if [ $ret -ne 0 ]; then
        error "编译失败！查看 build.log 获取详细错误信息"
        echo ""
        echo "  最后 50 行错误:"
        grep -i "error:" "$PROJECT_DIR/build.log" | tail -20 || \
            tail -50 "$PROJECT_DIR/build.log"
        exit 1
    fi

    info "内核编译成功！"
    info "输出目录: $OUT_DIR"

    local kernel_img="$OUT_DIR/arch/arm64/boot/Image"
    if [ -f "$kernel_img" ]; then
        info "内核镜像: $kernel_img ($(du -h "$kernel_img" | cut -f1))"
    fi
    cd "$PROJECT_DIR"
}

# ---- AnyKernel3 打包 ----
package_kernel() {
    section "9. AnyKernel3 打包"

    if [ ! -d "$ANY_KERNEL_DIR" ]; then
        warn "AnyKernel 目录不存在，跳过打包"
        return
    fi

    mkdir -p "$RELEASE_DIR"

    local zip_name="K80Pro-Power-Kernel-${BUILD_DATE}.zip"
    local zip_path="$RELEASE_DIR/$zip_name"

    info "创建 AnyKernel3 ZIP: $zip_name"

    local tmp_dir=$(mktemp -d)
    cp -r "$ANY_KERNEL_DIR"/* "$tmp_dir/" 2>/dev/null || true

    # Recovery 要求 update-binary 必须有可执行权限，否则报
    # "Failed to extract update-binary" 或刷入失败。
    chmod +x "$tmp_dir/META-INF/com/google/android/update-binary" 2>/dev/null || true
    chmod +x "$tmp_dir/tools/"* 2>/dev/null || true

    # Copy kernel image (must be named "Image" for flash_boot to find it)
    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        cp "$OUT_DIR/arch/arm64/boot/Image" "$tmp_dir/Image" 2>/dev/null || true
        info "内核镜像已复制: $tmp_dir/Image"
    fi

    # Copy dtb if available
    if [ -f "$OUT_DIR/arch/arm64/boot/dtb.img" ]; then
        cp "$OUT_DIR/arch/arm64/boot/dtb.img" "$tmp_dir/dtb.img" 2>/dev/null || true
    fi

    # Create zip using Python for maximum Recovery compatibility
    # (system zip command may produce Recovery-incompatible format)
    local zip_script="$SCRIPT_DIR/create-ak3-zip.py"
    if [ -f "$zip_script" ]; then
        python3 "$zip_script" "$tmp_dir" "$zip_path" 2>/dev/null || {
            cd "$tmp_dir"
            zip -r "$zip_path" . -x "*.git*" 2>/dev/null || \
                7z a -tzip "$zip_path" . 2>/dev/null || {
                warn "ZIP 打包失败"
                cd "$PROJECT_DIR"
                rm -rf "$tmp_dir"
                return
            }
        }
    else
        cd "$tmp_dir"
        zip -r "$zip_path" . -x "*.git*" 2>/dev/null || \
            7z a -tzip "$zip_path" . 2>/dev/null || {
            warn "ZIP 打包失败"
            cd "$PROJECT_DIR"
            rm -rf "$tmp_dir"
            return
        }
    fi
    cd "$PROJECT_DIR"
    rm -rf "$tmp_dir"

    if [ -f "$zip_path" ]; then
        info "ZIP 打包成功: $zip_path ($(du -h "$zip_path" | cut -f1))"
        info "刷入方法:"
        echo "  1. 将 $zip_name 传到手机"
        echo "  2. 在 Magisk/KernelSU 中刷入"
        echo "  3. 重启手机"
    fi
}

# ---- 主流程 ----
main() {
    banner
    check_prerequisites
    setup_toolchain
    clone_kernel_source
    fix_micode_kconfig
    integrate_sukisu
    apply_power_patches
    configure_defconfig
    compile_kernel
    package_kernel

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  构建完成!                                               ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  内核版本: $KERNEL_VERSION"
    echo "  构建时间: $BUILD_DATE"
    echo "  输出目录: $RELEASE_DIR"
    echo ""
    if [ -d "$RELEASE_DIR" ]; then
        echo "  产物列表:"
        ls -la "$RELEASE_DIR/" 2>/dev/null || echo "    (空)"
    fi
}

main "$@"