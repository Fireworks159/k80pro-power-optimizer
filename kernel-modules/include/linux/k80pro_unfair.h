/* SPDX-License-Identifier: GPL-2.0 */
/*
 * K80 Pro Power Optimizer - Unfair scheduling interface
 *
 * Lightweight kernel-level "unfair scheduling": foreground (top-app)
 * tasks get priority treatment while background tasks are throttled.
 *
 * Built unconditionally (obj-y); runtime on/off is controlled by
 * the k80pro_unfair_enable sysctl.
 */
#ifndef _LINUX_K80PRO_UNFAIR_H
#define _LINUX_K80PRO_UNFAIR_H

#include <linux/sched.h>

enum k80pro_task_class {
	K80PRO_CLASS_NORMAL	= 0,
	K80PRO_CLASS_TOPAPP	= 1,
	K80PRO_CLASS_FG		= 2,
	K80PRO_CLASS_BG		= 3,
};

extern unsigned int k80pro_unfair_enable;
extern unsigned int k80pro_fg_boost_pct;
extern unsigned int k80pro_bg_throttle_pct;

struct sched_entity;

void k80pro_update_task_class(struct task_struct *p);
void k80pro_sched_enqueue_hook(struct task_struct *p);
bool k80pro_sched_wakeup_preempt_hook(struct task_struct *curr,
				      struct task_struct *p);
void k80pro_update_deadline_hook(struct sched_entity *se);

#endif /* _LINUX_K80PRO_UNFAIR_H */
