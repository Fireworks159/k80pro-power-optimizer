#!/system/bin/sh
# ============================================================
# K80 Pro 内核备份脚本
# 适用于已 root 的 Redmi K80 Pro (miro / SM8750)
# 提取 boot、dtbo、vbmeta 等关键分区到 /sdcard/kernel-backup/
# ============================================================
# 使用方法:
#   1. 将此脚本传到手机
#   2. 用 Termux 或 adb shell 执行:
#      su
#      sh /sdcard/kernel-backup.sh
# ============================================================
set -e
BACKUP_DIR="/sdcard/kernel-backup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SAVE_DIR="${BACKUP_DIR}/${TIMESTAMP}"

echo ""
echo "========================================"
echo "  K80 Pro 内核备份工具"
echo "========================================"
echo ""

# --- 0. 检查 root ---
if [ "$(id -u)" != "0" ]; then
    echo "[!] 需要 root 权限，请先执行 su"
    exit 1
fi
echo "[OK] Root 权限已获取"

# --- 1. 创建备份目录 ---
mkdir -p "$SAVE_DIR"
echo "[OK] 备份目录: $SAVE_DIR"
echo ""

# --- 2. 记录系统信息 ---
echo "=== 记录系统信息 ==="
{
    echo "# K80 Pro 内核备份信息"
    echo "# 备份时间: $(date)"
    echo "# 设备: $(getprop ro.product.model)"
    echo "# 代号: $(getprop ro.product.device)"
    echo "# Android: $(getprop ro.build.version.release)"
    echo "# 系统: $(getprop ro.build.version.incremental)"
    echo "# HyperOS: $(getprop ro.miui.ui.version.name)"
    echo "# 内核: $(uname -r)"
    echo "# 内核编译: $(uname -v)"
    echo "# 当前 slot: $(getprop ro.boot.slot_suffix)"
    echo "# SoC: $(getprop ro.soc.model) ($(getprop ro.soc.manufacturer))"
    echo "# 安全补丁: $(getprop ro.build.version.security_patch)"
    echo ""
    echo "# === 分区信息 ==="
    for part in boot init_boot dtbo vbmeta vendor_boot; do
        echo "# ${part}: $(ls -la /dev/block/by-name/${part}* 2>/dev/null || echo '未找到')"
    done
} > "$SAVE_DIR/backup_info.txt"
cat "$SAVE_DIR/backup_info.txt"
echo ""

# --- 3. A/B slot ---
SLOT=$(getprop ro.boot.slot_suffix)
echo "=== A/B 槽位 ==="
if [ -n "$SLOT" ]; then
    echo "[OK] 当前活动槽位: $SLOT"
else
    echo "[!] 未检测到 A/B slot (可能是 A-only 设备)"
    SLOT=""
fi
echo ""

# --- 4. 备份 boot 分区 ---
echo "=== 备份 boot 分区 ==="
BOOT_PATH="/dev/block/by-name/boot${SLOT}"
if [ ! -e "$BOOT_PATH" ]; then
    BOOT_PATH=$(readlink -f "/dev/block/by-name/boot${SLOT}" 2>/dev/null || echo "")
fi
if [ -e "$BOOT_PATH" ]; then
    echo "  路径: $BOOT_PATH"
    echo "  大小: $(blockdev --getsize64 "$BOOT_PATH" 2>/dev/null || echo "未知") bytes"
    dd if="$BOOT_PATH" of="$SAVE_DIR/boot.img" bs=4096 2>/dev/null
    echo "[OK] boot.img 已备份 ($(ls -la "$SAVE_DIR/boot.img" | awk '{print $5}') bytes)"
else
    echo "[!] 未找到 boot 分区，扫描中..."
    find /dev/block/by-name/ -name "boot*" -exec echo "  发现: {}" \;
fi
echo ""

# --- 5. 备份 init_boot ---
echo "=== 备份 init_boot 分区 ==="
INIT_BOOT_PATH="/dev/block/by-name/init_boot${SLOT}"
if [ ! -e "$INIT_BOOT_PATH" ]; then
    INIT_BOOT_PATH=$(readlink -f "/dev/block/by-name/init_boot${SLOT}" 2>/dev/null || echo "")
fi
if [ -e "$INIT_BOOT_PATH" ]; then
    dd if="$INIT_BOOT_PATH" of="$SAVE_DIR/init_boot.img" bs=4096 2>/dev/null
    echo "[OK] init_boot.img 已备份"
else
    echo "[!] 未找到 init_boot 分区 (可忽略)"
fi
echo ""

# --- 6. 备份 dtbo ---
echo "=== 备份 dtbo 分区 ==="
DTBO_PATH="/dev/block/by-name/dtbo${SLOT}"
if [ ! -e "$DTBO_PATH" ]; then
    DTBO_PATH=$(readlink -f "/dev/block/by-name/dtbo${SLOT}" 2>/dev/null || echo "")
fi
if [ -e "$DTBO_PATH" ]; then
    dd if="$DTBO_PATH" of="$SAVE_DIR/dtbo.img" bs=4096 2>/dev/null
    echo "[OK] dtbo.img 已备份"
else
    echo "[!] 未找到 dtbo 分区 (可忽略)"
fi
echo ""

# --- 7. 备份 vbmeta ---
echo "=== 备份 vbmeta 分区 ==="
VBMETA_PATH="/dev/block/by-name/vbmeta${SLOT}"
if [ ! -e "$VBMETA_PATH" ]; then
    VBMETA_PATH=$(readlink -f "/dev/block/by-name/vbmeta${SLOT}" 2>/dev/null || echo "")
fi
if [ -e "$VBMETA_PATH" ]; then
    dd if="$VBMETA_PATH" of="$SAVE_DIR/vbmeta.img" bs=4096 2>/dev/null
    echo "[OK] vbmeta.img 已备份"
else
    echo "[!] 未找到 vbmeta 分区 (可忽略)"
fi
echo ""

# --- 8. 备份 vendor_boot ---
echo "=== 备份 vendor_boot 分区 ==="
VENDOR_BOOT_PATH="/dev/block/by-name/vendor_boot${SLOT}"
if [ ! -e "$VENDOR_BOOT_PATH" ]; then
    VENDOR_BOOT_PATH=$(readlink -f "/dev/block/by-name/vendor_boot${SLOT}" 2>/dev/null || echo "")
fi
if [ -e "$VENDOR_BOOT_PATH" ]; then
    dd if="$VENDOR_BOOT_PATH" of="$SAVE_DIR/vendor_boot.img" bs=4096 2>/dev/null
    echo "[OK] vendor_boot.img 已备份"
else
    echo "[!] 未找到 vendor_boot 分区 (可忽略)"
fi
echo ""

# --- 9. 生成校验 ---
echo "=== 生成 MD5 校验 ==="
cd "$SAVE_DIR"
md5sum *.img > md5sum.txt 2>/dev/null || true
cat md5sum.txt 2>/dev/null || echo "(无 img 文件)"
echo ""

# --- 10. 汇总 ---
echo "========================================"
echo "  备份完成!"
echo "========================================"
echo ""
echo "备份位置: $SAVE_DIR"
echo ""
echo "文件列表:"
ls -la "$SAVE_DIR/"
echo ""
echo "总大小: $(du -sh "$SAVE_DIR/" | awk '{print $1}')"
echo ""
echo "========================================"
echo "  重要提醒:"
echo "========================================"
echo ""
echo "1. 请将备份文件夹复制到电脑或云盘保存"
echo "   adb pull $SAVE_DIR"
echo ""
echo "2. 如果刷入自定义内核后无法开机:"
echo "   - 进入 Fastboot (关机 + 音量减 + 电源)"
echo "   - fastboot flash boot boot.img"
echo "   - fastboot flash init_boot init_boot.img"
echo "   - fastboot flash dtbo dtbo.img"
echo "   - fastboot reboot"
echo ""
echo "3. 请勿删除此备份，直到确认新内核稳定运行"
echo ""