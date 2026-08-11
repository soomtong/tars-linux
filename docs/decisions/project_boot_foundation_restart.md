---
name: project-boot-foundation-restart
description: "TARS project was physically restarted as a new repo focused on a from-scratch, learning-oriented Boot Foundation sub-project"
metadata: 
  node_type: memory
  type: project
  originSessionId: 22978997-aa43-4082-af11-aeec48afb813
---

TARS (macOS-semantics terminal-first Linux userland) was restarted from
scratch in this repo (`git@github.com:soomtong/tars-linux.git`), abandoning
the previous repo (`git@github.com:soomtong/tars.git`) which had reached V1
M12 but accumulated many small, poorly-understood fixes (RC6–RC21: fbdev
capture race, ptmx mknod, devpts mount point, etc.) without real forward
progress.

**Why:** User's own assessment — the old project was "vibe coded and ruined,"
producing code without understanding how/why it worked. The restart's
explicit goal is understanding over speed.

**Decisions locked in (see
`docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`):**
- First sub-project = **Boot Foundation**: self-built Linux kernel
  (kernel.org source, own `.config`) + Limine bootloader + custom Rust PID 1
  init (no BusyBox) + `xorriso` hybrid El Torito ISO, booted in QEMU via
  `-cdrom` (not QEMU's `-kernel` shortcut) to a shell prompt.
- Full vision (macOS Cmd/Ctrl/Opt semantics, ghostty-based terminal, Linux
  homebrew-style package manager, AI coding tool integration, self-built CJK
  IME, minimal X11/Wayland) is deliberately deferred — each is its own future
  sub-project, not designed yet.
- Milestones: BF-M0 (toolchain baseline + multiboot sanity check) → BF-M1
  (kernel boots, panics with no init — deliberate gate showing the
  kernel/userspace boundary) → BF-M2 (Rust init mounts proc/sys/devtmpfs,
  spawns shell, still via QEMU `-kernel` direct boot) → BF-M3 (real Limine +
  hybrid ISO replaces QEMU's `-kernel` shortcut) → BF-M4 (reproducibility
  gate, 3 consecutive successful runs).

**How to apply:** When resuming this project, check
`docs/superpowers/plans/` for the current milestone's plan before assuming
work status — this restart is recent (2026-08-01) and supersedes anything
inferred from old habits/assumptions about the previous `tars.git` repo.
Also see [[feedback-commit-delegation]] for the collaboration workflow in
effect (user hands-on for files/commands, Claude handles commits).
