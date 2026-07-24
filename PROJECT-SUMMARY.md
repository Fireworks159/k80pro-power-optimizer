# K80 Pro Power Optimizer - 项目总结

## 项目信息
- **项目名称**: K80 Pro Power Optimizer
- **版本**: v2.0.0 (纯内核方案)
- **目标设备**: Redmi K80 Pro (miro / SM8750 - Snapdragon 8 Elite)
- **系统要求**: Android 16 / HyperOS 3.0+ / Linux Kernel 6.6.x (EEVDF)
- **项目类型**: 纯内核级优化（无 Magisk 模块、无用户空间脚本）

## 核心改进 (v2.0 vs v1.0)

| 方面 | v1.0 (旧) | v2.0 (当前) |
|------|-----------|------------|
| 方案 | Magisk 模块 + 内核补丁 | 纯内核补丁 |
| Patch 2 | 仅注册 sysctl，不设置参数 | **实际写入 EEVDF 调度器参数** |
| Patch 1 | 仅 hook 入队+抢占 | 新增 **pick_eevdf deadline 调整** |
| SukiSU 集成 | 脆弱，失败则编译报错 | **优雅降级**，失败可跳过 |
| defconfig | 含不存在的选项 | 仅包含 6.6 合法选项 |
| WERROR | 未处理 | **显式禁用**避免编译中断 |
| CI | 复杂且易失败 | **健壮的缓存恢复机制** |

## 三大内核补丁

### Patch 1: EEVDF 不公平调度
- **文件**: `kernel/sched/k80pro_unfair.c` + `include/linux/k80pro_unfair.h`
- **Hook 点**: `enqueue_task_fair()`, `check_preempt_wakeup()`, `pick_eevdf()`
- **功能**: 前台任务 deadline 缩短 + 后台 deadline 延长 + 强制抢占
- **sysctl**: `k80pro_unfair_enable`, `k80pro_fg_boost_pct`, `k80pro_bg_throttle_pct`

### Patch 2: SM8750 EEVDF 调优
- **文件**: `kernel/sched/k80pro_tune.c` + `include/linux/k80pro_tune.h`
- **实现**: `late_initcall` 中实际写入 EEVDF 参数
- **调优值**: sched_latency=4ms, wakeup_granularity=0.3ms, migrate_cost=0.2ms, nr_migrate=8
- **sysctl**: `k80pro_tune_enable`

### Patch 3: 电源管理遥测
- **文件**: `kernel/power/k80pro_pm.c` + `include/linux/k80pro_pm.h`
- **实现**: PM notifier 统计挂起/恢复
- **sysctl**: `k80pro_pm_enable`, `k80pro_pm_suspend_count`, `k80pro_pm_total_suspend_ms`, `k80pro_pm_last_resume_ms`

## 设计原则

1. **自包含模块** — 所有新代码放在独立文件，对上游修改最小化
2. **运行时可调** — 通过 sysctl 暴露所有参数
3. **安全可关** — 每个模块都有独立的 enable 开关
4. **链接兼容** — 避开 6.6 已改名的 `sysctl_sched_base_slice`
5. **无条件编译** — 用 `obj-y` 不依赖 Kconfig
6. **优雅降级** — SukiSU 集成失败不阻塞编译

## 兼容性
- **主要适配**: Redmi K80 Pro (miro / SM8750)
- **理论兼容**: 所有 Snapdragon 8 Elite + 6.6.x EEVDF 内核
- **内核要求**: Linux 6.6.x (EEVDF 调度器)
- **前置条件**: 已解锁 BootLoader，备份原始 boot.img

## 开源协议
- **许可证**: GPL v3