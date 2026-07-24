# K80 Pro Power Optimizer

**不公平调度省电内核** —— 为 Redmi K80 Pro 量身打造的内核级省电与性能优化方案

## 📋 目录

- [概述](#概述)
- [核心特性](#核心特性)
- [工作原理](#工作原理)
- [快速开始](#快速开始)
- [内核编译](#内核编译)
- [运行时调优](#运行时调优)
- [验证](#验证)
- [常见问题](#常见问题)
- [贡献指南](#贡献指南)
- [许可证](#许可证)

## 概述

K80 Pro Power Optimizer 是一套**纯内核级**的 Android 性能与省电优化方案，通过模拟 vivo OriginOS 3.0 的"不公平调度"策略，在 Redmi K80 Pro (Snapdragon 8 Elite) 上实现：

- ⚡ **更流畅的前台体验** —— 前台任务在 EEVDF 调度器中获得更短的虚拟截止时间
- 🔋 **更长的续航时间** —— 后台任务被压制，减少不必要的 CPU 占用
- 🧠 **基于 EEVDF 调度器** —— Linux 6.6+ 内核原生支持
- 🔧 **运行时可调** —— 所有优化都通过 sysctl 暴露，无需重新编译即可调整

### 适用设备

- **主要适配**: Redmi K80 Pro (miro / SM8750)
- **理论兼容**: 所有搭载 Snapdragon 8 Elite 且使用 6.6.x 内核的设备（需自行测试）

### 系统要求

- Android 16 / HyperOS 3.0+
- Linux Kernel 6.6.x (EEVDF 调度器)
- 已解锁 BootLoader
- 备份原始 `boot.img`

> 本项目仅提供内核补丁与构建脚本，**不包含任何用户空间/Magisk 模块**。所有优化在内核态完成。

## 核心特性

本项目通过三个自包含的内核补丁实现优化，每个补丁都尽量减少对上游调度器/电源代码的修改，把新代码集中在新文件中，便于维护与升级。

### Patch 1: EEVDF 不公平调度 (`0001-scheduler-unfair-boost.patch`)

通过三个 hook 实现前台任务优先：

| 优化维度 | 实现方法 | 效果 |
|---|---|---|
| **任务分类** | 通过 cpuset cgroup 名识别 top-app / foreground / background | 无需用户空间配合 |
| **Deadline 调整** | 在 `pick_eevdf()` 中调整 deadline：前台缩短，后台延长 | EEVDF 视前台任务更"紧急" |
| **唤醒抢占** | `top-app` 唤醒时强制抢占后台任务 | 前台响应更快 |
| **入队刷新** | `enqueue_task_fair()` 中刷新任务分类 | 分类始终最新 |

新增 sysctl：

- `k80pro_unfair_enable` —— 总开关 (0/1)
- `k80pro_fg_boost_pct` —— 前台 boost 强度 (0-100)
- `k80pro_bg_throttle_pct` —— 后台压制强度 (0-200)

### Patch 2: SM8750 EEVDF 调优 (`0002-cpu-governor-tuning.patch`)

在 `late_initcall` 阶段写入上游 EEVDF sysctl 的优化默认值，适配 Snapdragon 8 Elite 双集群 Oryon 拓扑。**不修改任何调度器内部代码**，只调整运行时参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `sched_latency_ns` | 4ms | 调度周期，前台更跟手 |
| `sched_wakeup_granularity_ns` | 0.3ms | 唤醒抢占粒度 |
| `sched_migration_cost_ns` | 0.2ms | 跨集群迁移成本 |
| `sched_nr_migrate` | 8 | 单次迁移任务数 |

新增 sysctl：`k80pro_tune_enable` (0/1)

> 注意：6.6 EEVDF 已将 `sysctl_sched_min_granularity` 改名为 `sysctl_sched_base_slice`，本补丁刻意避开该符号。

### Patch 3: 电源管理遥测 (`0003-power-management.patch`)

通过 PM notifier 统计挂起/恢复周期，**不修改** `wakelock.c` / `idle.c`：

| sysctl | 说明 |
|---|---|
| `k80pro_pm_enable` | 总开关 (0/1) |
| `k80pro_pm_suspend_count` | 累计挂起次数（只读） |
| `k80pro_pm_total_suspend_ms` | 累计挂起时长（只读） |
| `k80pro_pm_last_resume_ms` | 上次挂起时长（只读） |

## 工作原理

### "不公平调度"原理

传统 EEVDF 调度器按虚拟截止时间（deadline）公平分配 CPU。本补丁打破这种公平性：根据任务所属的 cpuset cgroup 调整其虚拟截止时间，让**前台应用**获得更短的 deadline（更早被调度），**后台应用**获得更长的 deadline（更晚被调度）。

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: 任务分类 (cpuset cgroup 名)                     │
│ • top-app → K80PRO_CLASS_TOPAPP                         │
│ • foreground → K80PRO_CLASS_FG                          │
│ • background → K80PRO_CLASS_BG                          │
│ • 其他 → K80PRO_CLASS_NORMAL                             │
├─────────────────────────────────────────────────────────┤
│ Layer 2: EEVDF deadline 调整 (pick_eevdf 中)            │
│ • top-app/fg: deadline *= (100 - fg_boost_pct) / 100   │
│ • bg: deadline *= (100 + bg_throttle_pct) / 100         │
├─────────────────────────────────────────────────────────┤
│ Layer 3: 唤醒抢占 (check_preempt_wakeup 中)             │
│ • top-app 唤醒时，强制抢占正在运行的 bg 任务              │
├─────────────────────────────────────────────────────────┤
│ Layer 4: 入队刷新 (enqueue_task_fair 中)                │
│ • 每次任务入队时刷新 cpuset 分类                        │
└─────────────────────────────────────────────────────────┘
```

### SM8750 CPU 拓扑

```
┌────────────────────────────────────────────────────────────┐
│ Snapdragon 8 Elite (SM8750) - 2 集群 Oryon 架构           │
├────────────────────────────────────────────────────────────┤
│ CPU6-7: Oryon Phoenix L @ 4.32GHz (Prime)    [超大核]    │
│ ├─ 用途: 极短时间爆发性能                                │
│ └─ EEVDF 调优: 允许快速迁移，缩短 wakeup granularity     │
├────────────────────────────────────────────────────────────┤
│ CPU0-5: Oryon Phoenix M @ 3.53GHz (Performance) [性能核] │
│ ├─ 用途: 前台应用主力、后台应用                          │
│ └─ EEVDF 调优: 缩短 sched_latency，前台更跟手            │
└────────────────────────────────────────────────────────────┘
```

### 设计原则

1. **自包含模块** —— 所有新代码放在独立文件（`k80pro_unfair.c` / `k80pro_tune.c` / `k80pro_pm.c`），对上游 `fair.c` 等的修改最小化
2. **运行时可调** —— 通过 sysctl 暴露所有参数，无需重新编译即可调整
3. **安全可关** —— 每个模块都有独立的 `enable` 开关，可在运行时关闭
4. **链接兼容** —— 避免引用 6.6 已重命名/移除的符号
5. **无条件编译** —— 使用 `obj-y` 而非 `obj-$(CONFIG_*)`，不依赖 Kconfig

## 快速开始

### 方式一：GitHub Actions 云端编译（推荐）

无需本地 Linux 环境，推送代码后在 GitHub 云端自动编译。详见 [GITHUB-SETUP.md](GITHUB-SETUP.md)。

```
1. 推送代码到 GitHub → 2. 点击 Actions 编译 → 3. 下载内核 ZIP → 4. 刷入
```

### 方式二：本地一键构建

```bash
cd k80pro-power-optimizer/kernel-build
bash build-kernel.sh
```

## 内核编译

### 手动编译步骤

```bash
# 1. 获取内核源码
git clone https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git -b bsp-miro-v-oss k80pro-kernel
cd k80pro-kernel

# 2. (可选) 集成 SukiSU-Ultra Root
curl -LSs https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh | bash -s main

# 3. 应用补丁
git am /path/to/kernel-patches/0001-scheduler-unfair-boost.patch
git am /path/to/kernel-patches/0002-cpu-governor-tuning.patch
git am /path/to/kernel-patches/0003-power-management.patch

# 4. 配置 (GKI + vendor fragments)
make O=out ARCH=arm64 gki_defconfig
./scripts/kconfig/merge_config.sh -m -O out \
  arch/arm64/configs/vendor/sun_perf.config \
  arch/arm64/configs/vendor/miro_perf.config
cat /path/to/kernel-patches/defconfig-additions.conf >> out/.config
make O=out olddefconfig

# 5. 编译
make O=out ARCH=arm64 LLVM=1 -j$(nproc)
```

### 构建选项

```bash
TOOLCHAIN=system bash build-kernel.sh   # 使用系统 clang
SKIP_PATCHES=1 bash build-kernel.sh    # 跳过省电补丁
SKIP_SUKISU=1 bash build-kernel.sh     # 跳过 SukiSU 集成
CLEAN_BUILD=1 bash build-kernel.sh    # 清理重编译
JOBS=8 bash build-kernel.sh            # 指定并行线程数
```

## 运行时调优

内核刷入后，通过 sysctl 实时调整（需 root）：

```bash
# === 不公平调度 (Patch 1) ===
echo 1 > /proc/sys/kernel/k80pro_unfair_enable      # 总开关
echo 30 > /proc/sys/kernel/k80pro_fg_boost_pct      # 前台 boost 强度 (0-100)
echo 50 > /proc/sys/kernel/k80pro_bg_throttle_pct   # 后台压制强度 (0-200)

# === EEVDF 调优 (Patch 2) ===
echo 1 > /proc/sys/kernel/k80pro_tune_enable        # 总开关

# === PM 遥测 (Patch 3) ===
cat /proc/sys/kernel/k80pro_pm_suspend_count        # 累计挂起次数
cat /proc/sys/kernel/k80pro_pm_total_suspend_ms    # 累计挂起时长
cat /proc/sys/kernel/k80pro_pm_last_resume_ms      # 上次挂起时长
```

## 验证

刷入后在手机上验证：

```bash
# 1. 检查内核版本
adb shell su -c 'uname -r'
# → 6.6.77-k80pro-optimized

# 2. 检查不公平调度
adb shell su -c 'cat /proc/sys/kernel/k80pro_unfair_enable'
# → 1

# 3. 检查 EEVDF 调优
adb shell su -c 'cat /proc/sys/kernel/k80pro_tune_enable'
# → 1

# 4. 检查 PM 遥测
adb shell su -c 'cat /proc/sys/kernel/k80pro_pm_suspend_count'
# → 0 (随挂起次数递增)
```

## 项目结构

```
k80pro-power-optimizer/
├── .github/workflows/
│   └── build-kernel.yml                 # GitHub Actions 云端编译
├── kernel-patches/                      # 内核补丁
│   ├── 0001-scheduler-unfair-boost.patch  # EEVDF 不公平调度
│   ├── 0002-cpu-governor-tuning.patch     # SM8750 EEVDF 调优
│   ├── 0003-power-management.patch        # PM 遥测
│   ├── defconfig-additions.conf           # 内核编译附加配置
│   └── BUILD-GUIDE.md                    # 内核编译指南
├── kernel-build/                        # 构建系统
│   ├── build-kernel.sh                   # 一键构建脚本
│   └── anykernel/                        # AnyKernel3 模板
│       └── anykernel.sh
├── tools/
│   └── backup-kernel.sh                  # boot.img 备份工具
├── README.md                             # 本文档
├── GITHUB-SETUP.md                       # GitHub 云端编译指南
└── LICENSE                              # GPL v3
```

## 常见问题

**Q: 补丁应用失败？**

```bash
# 检查补丁是否兼容
git apply --check 0001-scheduler-unfair-boost.patch

# 失败时可尝试强制应用
git apply --reject 0001-scheduler-unfair-boost.patch
```

补丁针对 MiCode `bsp-miro-v-oss` 分支开发，若使用其他分支可能需要手动调整 hunk 上下文。

**Q: 编译报错 "undefined reference to sysctl_sched_min_granularity"？**

6.6 EEVDF 已将该符号改名为 `sysctl_sched_base_slice`。本项目的补丁已刻意避开此符号。

**Q: 编译报错 "missing-prototypes"？**

补丁中所有非 static 函数都已在对应头文件中声明。

**Q: 刷入后无法开机？**

通过 fastboot 刷回原始 boot.img：

```bash
fastboot flash boot backup_boot.img
fastboot reboot
```

**Q: 能否在其他设备上使用？**

理论上所有 6.6.x EEVDF 内核都可应用，但 Patch 2 的调优值针对 SM8750 双集群 Oryon 拓扑。其他 SoC 需要根据实际 CPU 拓扑调整。

**Q: SukiSU-Ultra 集成失败怎么办？**

可以跳过 SukiSU 集成（`SKIP_SUKISU=1`），内核仍然可以编译通过，只是没有内核级 Root 功能。

## 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交规范

- 功能新增：`feat: 添加 xxx 功能`
- Bug 修复：`fix: 修复 xxx 问题`
- 文档更新：`docs: 更新 xxx 文档`
- 性能优化：`perf: 优化 xxx 性能`

### 补丁开发注意

- 新增代码尽量放在独立文件，避免修改上游关键文件
- 所有 sysctl 参数都要有 `enable` 开关
- 避免引用 6.6 已重命名/移除的符号
- 函数要么 `static`，要么在头文件中声明

## 致谢

- [MiCode](https://github.com/MiCode/Xiaomi_Kernel_OpenSource) - 小米开源内核
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) - 内核级 Root 方案
- vivo OriginOS 团队 - 不公平调度灵感来源
- Linux Kernel 社区 - EEVDF 调度器

## 许可证

本项目采用 GPL v3 许可证 - 详见 [LICENSE](LICENSE) 文件

## 免责声明

- 本项目仅供学习研究使用
- 刷入自定义内核有风险，请自行承担后果
- 作者不对因使用本项目导致的任何硬件损坏、数据丢失或保修失效负责
- 请在了解风险的前提下使用，并做好数据备份