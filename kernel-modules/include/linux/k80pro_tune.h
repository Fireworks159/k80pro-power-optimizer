/* SPDX-License-Identifier: GPL-2.0 */
/*
 * K80 Pro Power Optimizer - EEVDF scheduler tuning interface
 */
#ifndef _LINUX_K80PRO_TUNE_H
#define _LINUX_K80PRO_TUNE_H

extern unsigned int k80pro_tune_enable;

#define K80PRO_TUNE_LATENCY_NS		4000000ULL
#define K80PRO_TUNE_MIGRATE_COST	200000ULL
#define K80PRO_TUNE_NR_MIGRATE		8

#endif /* _LINUX_K80PRO_TUNE_H */
