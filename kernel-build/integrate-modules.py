#!/usr/bin/env python3
"""
Integrate K80 Pro kernel modules into an upstream/MiCode kernel tree.

This script is idempotent: running it multiple times on the same tree is safe.
It uses stable anchor strings instead of fragile line numbers or git patches.

Usage:
    python3 integrate-modules.py <kernel-source-dir>
"""
import os
import shutil
import sys
from pathlib import Path

MODULES_ROOT = Path(__file__).resolve().parent.parent / "kernel-modules"

HOOKS = {
    "include/linux/sched.h": {
        "anchor": "\tstruct css_set __rcu\t\t*cgroups;\n",
        "insert_after": "\t/* K80 Pro: cached cpuset classification */\n\tunsigned int\t\t\tk80pro_task_class;\n",
        "guard": "k80pro_task_class",
    },
    "kernel/sched/fair.c": [
        {
            "anchor": "#include <linux/sched/nohz.h>\n",
            "insert_after": "#include <linux/k80pro_unfair.h>\n",
            "guard": "k80pro_unfair.h",
        },
        {
            "anchor": "\tint should_iowait_boost;\n",
            "insert_after": "\n\t/* K80 Pro: refresh cpuset-based task classification */\n\tk80pro_sched_enqueue_hook(p);\n",
            "guard": "k80pro_sched_enqueue_hook",
        },
        {
            "anchor": "\tif (unlikely(task_has_idle_policy(curr)) &&\n\t    likely(!task_has_idle_policy(p)))\n\t\tgoto preempt;\n",
            "insert_after": "\n\t/* K80 Pro unfair scheduling: top-app may preempt background */\n\tif (k80pro_sched_wakeup_preempt_hook(rq->curr, p)) {\n\t\tresched_curr(rq);\n\t\treturn;\n\t}\n",
            "guard": "k80pro_sched_wakeup_preempt_hook",
        },
        {
            "anchor": "\tse->deadline = se->vruntime + calc_delta_fair(se->slice, se);\n",
            "insert_after": "\n\t/* K80 Pro: scale deadline for unfair scheduling */\n\tk80pro_update_deadline_hook(se);\n",
            "guard": "k80pro_update_deadline_hook",
        },
    ],
}

MAKEFILE_ADDITIONS = {
    "kernel/sched/Makefile": ["obj-y += k80pro_unfair.o\n", "obj-y += k80pro_tune.o\n"],
    "kernel/power/Makefile": ["obj-y += k80pro_pm.o\n"],
}

FILES_TO_COPY = [
    ("include/linux/k80pro_unfair.h", "include/linux/k80pro_unfair.h"),
    ("kernel/sched/k80pro_unfair.c", "kernel/sched/k80pro_unfair.c"),
    ("include/linux/k80pro_tune.h", "include/linux/k80pro_tune.h"),
    ("kernel/sched/k80pro_tune.c", "kernel/sched/k80pro_tune.c"),
    ("include/linux/k80pro_pm.h", "include/linux/k80pro_pm.h"),
    ("kernel/power/k80pro_pm.c", "kernel/power/k80pro_pm.c"),
]


def copy_modules(kernel_dir: Path):
    for src_rel, dst_rel in FILES_TO_COPY:
        src = MODULES_ROOT / src_rel
        dst = kernel_dir / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  [COPY] {dst_rel}")


def patch_file(path: Path, hook):
    if isinstance(hook, list):
        for h in hook:
            patch_file(path, h)
        return

    text = path.read_text()
    if hook["guard"] in text:
        print(f"  [SKIP] {path.name}: already contains {hook['guard']}")
        return

    if hook["anchor"] not in text:
        raise RuntimeError(
            f"Cannot find anchor in {path}: {hook['anchor']!r}\n"
            f"The upstream file may have changed; please update the anchor."
        )

    text = text.replace(hook["anchor"], hook["anchor"] + hook["insert_after"], 1)
    path.write_text(text)
    print(f"  [PATCH] {path.name}: inserted {hook['guard']}")


def patch_makefiles(kernel_dir: Path):
    for rel_path, additions in MAKEFILE_ADDITIONS.items():
        path = kernel_dir / rel_path
        text = path.read_text()
        for addition in additions:
            if addition.strip() in text:
                print(f"  [SKIP] {rel_path}: already contains {addition.strip()}")
                continue
            text += addition
            print(f"  [PATCH] {rel_path}: appended {addition.strip()}")
        path.write_text(text)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <kernel-source-dir>", file=sys.stderr)
        sys.exit(1)

    kernel_dir = Path(sys.argv[1]).resolve()
    if not kernel_dir.is_dir():
        print(f"Error: {kernel_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    print(f"Integrating K80 Pro modules into: {kernel_dir}")

    print("\n[1/3] Copying module sources...")
    copy_modules(kernel_dir)

    print("\n[2/3] Patching source files...")
    for rel_path, hook in HOOKS.items():
        patch_file(kernel_dir / rel_path, hook)

    print("\n[3/3] Updating Makefiles...")
    patch_makefiles(kernel_dir)

    print("\nIntegration complete.")


if __name__ == "__main__":
    main()
