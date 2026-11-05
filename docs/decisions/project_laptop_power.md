---
name: project_laptop_power
description: "맥북의 밝기 · 절전(LP-M0~M2, 2026-11-05) — DRM_I915 · PM · SUSPEND를 켜고 RM 결정 3을 뒤집었다, i915가 TMPFS를 끌고 와 rootfs가 tmpfs(RAM 절반)로 바뀌는 함정 → rootfstype=ramfs, SND_HDA_I915 → gpu_bind=0, PID 1이 뚜껑 · USR1에 deep S3, terminal이 Apple F1 · F2로 16단계"
metadata:
  type: project
---

design `docs/specs/2026-11-05-tars-laptop-power-design.md`, plan `…-lp-m0.md` · `-m1.md` · `-m2.md`, 사용 법 `running-tars.md`의 "밝기와 절전".

## 무엇이 섰나

- 커널: `DRM_I915` · `PM` · `SUSPEND`(+따라온 47줄), bzImage +1.5MB. 내장 cmdline에 `snd_hda_core.gpu_bind=0` · `rootfstype=ramfs`.
  machine 체인이 맥 GPU 넷(`8086:0116 · 0166 · 0A2E · 0D26`)의 i915 표와 cmdline을 본다.
- PID 1: 뚜껑 닫힘(SW_LID 1)과 SIGUSR1이 `.sleep` → sync → `mem_sleep`에 deep → `state`에 mem → `resumed after Nms`(BOOTTIME). 체인 `sleep`.
- terminal: `backlight.zig`(순위 raw > platform > firmware, 16단계), Apple 칸의 F1 · F2와 밝기 키 → `Action.brightness`.

## 배운 것

1. 커널 심볼 하나가 사용자 공간의 바닥을 바꿀 수 있다 — i915가 `TMPFS`를 select하면 `init_rootfs`가 initramfs를 tmpfs에 푼다(상한 RAM의
   절반). 512MB 게스트에서 열여덟 체인이 서로 다른 문구로 빨갰고, 공통 원인은 로그 곳곳의 `No space left on device`였다. 많은 체인이
   한꺼번에 제각각 빨개지면 바닥(rootfs · 디스크 · 메모리)부터 본다.
2. 음성 검사는 그 근거를 다시 읽고 바꾼다 — audio 체인의 "SND_HDA_I915 꺼짐"은 "i915가 맡지 않는 Intel GPU에서 HDA가 영영 기다린다"였고,
   i915를 켜도 xe 몫(Lunar · Panther Lake)에서는 그대로라 `gpu_bind=0` 검사로 바꿨다.
3. terminal은 원래 F1~F12를 안 보낸다 — Apple 칸의 F1 · F2를 밝기로 써도 잃는 것이 없다.
4. QEMU S3: q35 + `-global ICH9-LPC.disable_s3=0`, QMP `query-status`가 `suspended`, `system_wakeup`. 깨울 때 virtio-gpu가 리셋돼도
   terminal 프로세스는 버틴다.
5. 실기가 볼 것: `backlight> pick=intel_backlight`, 깨어난 화면(i915), `suspend (deep)`, 깨어난 뒤 brcmsmac(Air 무선) · USB 키보드 첫 키
   (design 위험 2 · 3), i915가 card0을 받는지(위험 1).
