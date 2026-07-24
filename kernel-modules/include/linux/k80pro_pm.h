/* SPDX-License-Identifier: GPL-2.0 */
/*
 * K80 Pro Power Optimizer - Power-management telemetry interface.
 *
 * Self-contained module: counts suspend/resume cycles and exposes
 * the counters via sysctl. No wakelock or cpuidle internals touched.
 */
#ifndef _LINUX_K80PRO_PM_H
#define _LINUX_K80PRO_PM_H

extern unsigned int k80pro_pm_enable;

#endif /* _LINUX_K80PRO_PM_H */
