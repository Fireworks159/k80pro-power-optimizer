#!/usr/bin/env python3
"""
Validate that integrate-modules.py has correctly applied K80 Pro modules
into a kernel tree without performing a full build.

Usage:
    python3 validate-integration.py <kernel-source-dir>
"""
import sys
from pathlib import Path

EXPECTED_FILES = [
    "include/linux/k80pro_unfair.h",
    "kernel/sched/k80pro_unfair.c",
    "include/linux/k80pro_tune.h",
    "kernel/sched/k80pro_tune.c",
    "include/linux/k80pro_pm.h",
    "kernel/power/k80pro_pm.c",
]

EXPECTED_HOOKS = {
    "include/linux/sched.h": [
        "unsigned int\t\t\tk80pro_task_class;",
    ],
    "kernel/sched/fair.c": [
        "#include <linux/k80pro_unfair.h>",
        "k80pro_sched_enqueue_hook(p);",
        "k80pro_sched_wakeup_preempt_hook(",
        "k80pro_update_deadline_hook(se);",
    ],
    "kernel/sched/Makefile": [
        "obj-y += k80pro_unfair.o",
        "obj-y += k80pro_tune.o",
    ],
    "kernel/power/Makefile": [
        "obj-y += k80pro_pm.o",
    ],
}


def fail(msg):
    print(f"  FAIL: {msg}")
    return False


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <kernel-source-dir>", file=sys.stderr)
        sys.exit(1)

    kernel_dir = Path(sys.argv[1]).resolve()
    ok = True

    print(f"Validating K80 Pro integration in: {kernel_dir}")

    print("\n[1/3] Checking copied module files...")
    for rel in EXPECTED_FILES:
        path = kernel_dir / rel
        if not path.is_file():
            ok = fail(f"missing file {rel}")
        else:
            print(f"  OK: {rel}")

    print("\n[2/3] Checking hook insertions...")
    for rel, needles in EXPECTED_HOOKS.items():
        path = kernel_dir / rel
        if not path.is_file():
            ok = fail(f"missing file {rel}")
            continue
        text = path.read_text()
        for needle in needles:
            if needle not in text:
                ok = fail(f"{rel} missing hook: {needle}")
            else:
                print(f"  OK: {rel} -> {needle}")

    print("\n[3/3] Checking for removed/renamed sysctl variables...")
    tune_c = (kernel_dir / "kernel/sched/k80pro_tune.c").read_text()
    for sysctl in ["sysctl_sched_wakeup_granularity"]:
        if sysctl in tune_c:
            ok = fail(f"k80pro_tune.c references removed sysctl {sysctl}")
        else:
            print(f"  OK: not using removed sysctl {sysctl}")

    if ok:
        print("\nValidation passed.")
        return 0
    else:
        print("\nValidation FAILED.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
