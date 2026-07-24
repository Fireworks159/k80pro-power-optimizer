// SPDX-License-Identifier: GPL-2.0
/*
 * K80 Pro Power Optimizer - EEVDF scheduler tuning
 *
 * Applies optimised EEVDF parameters for the Snapdragon 8 Elite
 * (SM8750) SoC / Redmi K80 Pro (miro).
 *
 * This file only sets upstream sysctl values -- it does NOT
 * modify any scheduler internals and therefore survives
 * scheduler updates cleanly.
 */
#include <linux/sched.h>
#include <linux/sysctl.h>
#include <linux/k80pro_tune.h>
#include <linux/printk.h>

#include "sched.h"

/*
 * sysctl_sched_latency is defined in kernel/sched/fair.c and not
 * exported via a header on all kernel versions.
 */
extern unsigned int sysctl_sched_latency;

unsigned int k80pro_tune_enable = 1;

static int __init k80pro_apply_eevdf_tuning(void)
{
	if (!k80pro_tune_enable)
		return 0;

	pr_info("k80pro_tune: applying SM8750 EEVDF scheduler tuning\n");

	/*
	 * Only latency is guaranteed writable across builds.
	 * sysctl_sched_migration_cost / sysctl_sched_nr_migrate are
	 * const_debug (read-only when CONFIG_SCHED_DEBUG is off) on
	 * MiCode, so we leave them alone to avoid const violations.
	 */
	sysctl_sched_latency = K80PRO_TUNE_LATENCY_NS;

	pr_info("k80pro_tune: latency=%llu ns\n",
		(unsigned long long)sysctl_sched_latency);

	return 0;
}

#ifdef CONFIG_SYSCTL
static const int k80pro_tune_zero     = 0;
static const int k80pro_tune_one      = 1;

static struct ctl_table k80pro_tune_table[] = {
	{
		.procname	= "k80pro_tune_enable",
		.data		= &k80pro_tune_enable,
		.maxlen		= sizeof(unsigned int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= (void *)&k80pro_tune_zero,
		.extra2		= (void *)&k80pro_tune_one,
	},
};

static int __init k80pro_tune_sysctl_init(void)
{
	register_sysctl("kernel", k80pro_tune_table);
	return 0;
}
late_initcall(k80pro_tune_sysctl_init);
#endif /* CONFIG_SYSCTL */

late_initcall(k80pro_apply_eevdf_tuning);
