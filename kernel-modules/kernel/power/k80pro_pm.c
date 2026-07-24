// SPDX-License-Identifier: GPL-2.0
/*
 * K80 Pro Power Optimizer - PM telemetry
 *
 * Self-contained module that:
 *   1. Counts suspend/resume cycles via a PM notifier.
 *   2. Accumulates total suspend time.
 *   3. Exposes the counters through /proc/sys/kernel/.
 *
 * No wakelock.c, idle.c, or cpuidle internals are modified.
 */
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/ktime.h>
#include <linux/sysctl.h>
#include <linux/suspend.h>
#include <linux/notifier.h>
#include <linux/spinlock.h>
#include <linux/k80pro_pm.h>

unsigned int k80pro_pm_enable = 1;

static const int k80pro_zero = 0;
static const int k80pro_one  = 1;

static unsigned int  k80pro_pm_suspend_count;
static unsigned long k80pro_pm_total_suspend_ms;
static unsigned long k80pro_pm_last_resume_ms;
static ktime_t       k80pro_pm_suspend_start;
static DEFINE_SPINLOCK(k80pro_pm_lock);

static int k80pro_pm_notifier_call(struct notifier_block *nb,
				   unsigned long event, void *dummy)
{
	unsigned long flags;
	ktime_t now;
	unsigned long dur_ms;

	if (!k80pro_pm_enable)
		return NOTIFY_OK;

	switch (event) {
	case PM_SUSPEND_PREPARE:
		spin_lock_irqsave(&k80pro_pm_lock, flags);
		k80pro_pm_suspend_start = ktime_get();
		spin_unlock_irqrestore(&k80pro_pm_lock, flags);
		break;

	case PM_POST_SUSPEND:
		now = ktime_get();
		spin_lock_irqsave(&k80pro_pm_lock, flags);
		dur_ms = (unsigned long)ktime_to_ms(ktime_sub(now,
							k80pro_pm_suspend_start));
		k80pro_pm_suspend_count++;
		k80pro_pm_total_suspend_ms += dur_ms;
		k80pro_pm_last_resume_ms = dur_ms;
		spin_unlock_irqrestore(&k80pro_pm_lock, flags);
		pr_info("k80pro_pm: resume after %lu ms (total %u suspends)\n",
			dur_ms, k80pro_pm_suspend_count);
		break;
	}

	return NOTIFY_OK;
}

static struct notifier_block k80pro_pm_notifier_block = {
	.notifier_call	= k80pro_pm_notifier_call,
	.priority	= 0,
};

#ifdef CONFIG_SYSCTL
static struct ctl_table k80pro_pm_table[] = {
	{
		.procname	= "k80pro_pm_enable",
		.data		= &k80pro_pm_enable,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= (void *)&k80pro_zero,
		.extra2		= (void *)&k80pro_one,
	},
	{
		.procname	= "k80pro_pm_suspend_count",
		.data		= &k80pro_pm_suspend_count,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0444,
		.proc_handler	= proc_dointvec,
	},
	{
		.procname	= "k80pro_pm_total_suspend_ms",
		.data		= &k80pro_pm_total_suspend_ms,
		.maxlen		= sizeof(unsigned long),
		.mode		= 0444,
		.proc_handler	= proc_doulongvec_minmax,
	},
	{
		.procname	= "k80pro_pm_last_resume_ms",
		.data		= &k80pro_pm_last_resume_ms,
		.maxlen		= sizeof(unsigned long),
		.mode		= 0444,
		.proc_handler	= proc_doulongvec_minmax,
	},
};

static int __init k80pro_pm_sysctl_init(void)
{
	register_sysctl("kernel", k80pro_pm_table);
	return 0;
}
late_initcall(k80pro_pm_sysctl_init);
#endif /* CONFIG_SYSCTL */

static int __init k80pro_pm_init(void)
{
	return register_pm_notifier(&k80pro_pm_notifier_block);
}
late_initcall(k80pro_pm_init);
