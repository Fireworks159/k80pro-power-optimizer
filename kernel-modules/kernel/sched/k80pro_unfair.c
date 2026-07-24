// SPDX-License-Identifier: GPL-2.0
/*
 * K80 Pro Power Optimizer - Unfair scheduling implementation
 *
 * Implements "unfair scheduling" for Android on the EEVDF scheduler
 * (Linux 6.6+). Foreground tasks get shorter virtual deadlines so
 * they are selected earlier; background tasks get longer deadlines
 * so they are delayed. Top-app wakeups force-preempt backgrounds.
 *
 * Classification uses standard Android cpuset cgroup names.
 * Deadline adjustment is done at pick_eevdf() selection time,
 * so the EEVDF scheduling logic and accounting are completely
 * unaffected.
 */
#include <linux/sched.h>
#include <linux/cgroup.h>
#include <linux/cpuset.h>
#include <linux/sysctl.h>
#include <linux/kernfs.h>
#include <linux/string.h>
#include <linux/rcupdate.h>
#include <linux/k80pro_unfair.h>

#include "sched.h"

unsigned int k80pro_unfair_enable	= 1;
unsigned int k80pro_fg_boost_pct	= 30;
unsigned int k80pro_bg_throttle_pct	= 50;

static const int k80pro_zero		= 0;
static const int k80pro_one_hundred	= 100;
static const int k80pro_two_hundred	= 200;

static unsigned int k80pro_get_task_class(struct task_struct *p)
{
	struct cgroup_subsys_state *css;
	unsigned int cls = K80PRO_CLASS_NORMAL;
	const char *name = NULL;

	rcu_read_lock();
	css = task_css(p, cpuset_cgrp_id);
	if (css && css->cgroup && css->cgroup->kn)
		name = css->cgroup->kn->name;

	if (name) {
		if (!strcmp(name, "top-app"))
			cls = K80PRO_CLASS_TOPAPP;
		else if (!strcmp(name, "foreground"))
			cls = K80PRO_CLASS_FG;
		else if (!strcmp(name, "background") ||
			 !strcmp(name, "system-background") ||
			 !strcmp(name, "restricted"))
			cls = K80PRO_CLASS_BG;
	}
	rcu_read_unlock();

	return cls;
}

void k80pro_update_task_class(struct task_struct *p)
{
	if (!k80pro_unfair_enable) {
		p->k80pro_task_class = K80PRO_CLASS_NORMAL;
		return;
	}
	p->k80pro_task_class = k80pro_get_task_class(p);
}

void k80pro_sched_enqueue_hook(struct task_struct *p)
{
	if (!k80pro_unfair_enable)
		return;
	k80pro_update_task_class(p);
}

/*
 * Adjust the EEVDF deadline for unfair scheduling.
 * Called from update_deadline() after the new deadline is computed,
 * so the scaling persists across slice replenishment.
 */
void k80pro_update_deadline_hook(struct sched_entity *se)
{
	struct task_struct *p;
	unsigned int cls;

	if (!k80pro_unfair_enable)
		return;

	if (!entity_is_task(se))
		return;

	p = task_of(se);
	if (!p->k80pro_task_class)
		k80pro_update_task_class(p);

	cls = p->k80pro_task_class;

	switch (cls) {
	case K80PRO_CLASS_TOPAPP:
		se->deadline = se->deadline * (100 - k80pro_fg_boost_pct) / 100;
		break;
	case K80PRO_CLASS_FG:
		se->deadline = se->deadline * (100 - k80pro_fg_boost_pct / 2) / 100;
		break;
	case K80PRO_CLASS_BG:
		se->deadline = se->deadline * (100 + k80pro_bg_throttle_pct) / 100;
		break;
	default:
		break;
	}
}

bool k80pro_sched_wakeup_preempt_hook(struct task_struct *curr,
				      struct task_struct *p)
{
	unsigned int curr_cls, p_cls;

	if (!k80pro_unfair_enable)
		return false;

	if (!p->k80pro_task_class)
		k80pro_update_task_class(p);
	if (!curr->k80pro_task_class)
		k80pro_update_task_class(curr);

	p_cls = p->k80pro_task_class;
	curr_cls = curr->k80pro_task_class;

	if (p_cls == K80PRO_CLASS_TOPAPP && curr_cls == K80PRO_CLASS_BG)
		return true;

	if (p_cls == K80PRO_CLASS_FG && curr_cls == K80PRO_CLASS_BG &&
	    k80pro_fg_boost_pct >= 50)
		return true;

	return false;
}

#ifdef CONFIG_SYSCTL
static struct ctl_table k80pro_unfair_table[] = {
	{
		.procname	= "k80pro_unfair_enable",
		.data		= &k80pro_unfair_enable,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= (void *)&k80pro_zero,
		.extra2		= (void *)&k80pro_one_hundred,
	},
	{
		.procname	= "k80pro_fg_boost_pct",
		.data		= &k80pro_fg_boost_pct,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= (void *)&k80pro_zero,
		.extra2		= (void *)&k80pro_one_hundred,
	},
	{
		.procname	= "k80pro_bg_throttle_pct",
		.data		= &k80pro_bg_throttle_pct,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= (void *)&k80pro_zero,
		.extra2		= (void *)&k80pro_two_hundred,
	},
};

static int __init k80pro_unfair_sysctl_init(void)
{
	register_sysctl("kernel", k80pro_unfair_table);
	pr_info("k80pro_unfair: scheduling module loaded\n");
	return 0;
}
late_initcall(k80pro_unfair_sysctl_init);
#endif /* CONFIG_SYSCTL */
