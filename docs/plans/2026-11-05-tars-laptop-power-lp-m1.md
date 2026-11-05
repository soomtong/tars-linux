# LP-M1 — 뚜껑 닫기 · `sudo suspend`

> 구현은 lead가 직접 넣었다(2026-11-05, worktree `lp`에서 M0 게이트와 나란히 — 커밋 뒤 main에 cherry-pick, worktree는 지웠다).
> 사용자가 외출하며 남은 결정을 위임했다. 결과는 끝의 "결과" 절.

Goal: LP design 결정 3 · 4.

## 할 일

1. `power.zig` — `Action.sleep`(3), `SIGUSR1` → `.sleep`, 자식은 USR1도 기본값. `sleep()`: sync → `/sys/power/mem_sleep`에 `deep`(있으면) →
   `/sys/power/state`에 `mem` → `resumed after Nms`(BOOTTIME — MONOTONIC은 자는 동안 멈춘다). `shutdown`의 switch에 `.sleep => unreachable`.
   power · device 체인이 글자 그대로 grep하는 `signal handlers installed (TERM, INT)`는 그대로 두고 `SIGUSR1 suspends`를 따로 찍는다.
2. `devices.zig` — `looksLikeLid`(EV_SW 5 · SW_LID 0), `findLids`(`capabilities/sw`가 없으면 "0"), `drainButton`이 `Seen{power, lid_closed}`,
   `openPowerButtons`가 버튼 뒤에 뚜껑도 연다(`MAX_WATCHED` = 버튼 4 + 뚜껑 2). device 체인이 보는 `watching N power button(s)`는 버튼 수
   그대로이고 뚜껑은 `tars-init: lid switch …` 줄이다.
3. `main.zig` — `take()`가 `.sleep`이면 `sleep()`, 뚜껑 닫힘은 `request(.sleep)`(전원 버튼이 함께면 끄는 쪽).
4. `kernel/power/shutdown`에 이름 `suspend`(→ USR1), initrd에 링크.
5. `devices_test` 9a(뚜껑 고르기 — 태블릿 모드 스위치는 아니다) · 10(닫힘만 센다), `power_test`(USR1 → sleep).
6. 체인 `sleep`(LP-M1, QMP 45503) — q35 + `ICH9-LPC.disable_s3=0`, 시리얼 셸에서 `/usr/bin/suspend`.

## 확인한 것

1. bash · zsh · fish에 내장 `suspend`가 있다 — 이름만 치면 셸 자신이 멈춘다. 사람은 `sudo suspend`(sudo가 경로로 찾는다), 체인은
   전체 경로. 이름은 사용자가 고른 `suspend`를 지켰고 가이드에 적었다. `zzz` 같은 다른 이름은 사용자가 원하면.
2. 편집 사고 하나 — worktree에서 `devices.zig`를 쓰기용으로 연 뒤 읽는 한 줄이 파일을 비웠다(328줄 삭제). `git diff --stat`이 잡았고
   HEAD로 되돌려 다시 넣었다.

## 결과

- `zig build test`(devices_test 9a · 10, power_test USR1) 통과.
- `sleep` 체인 첫 판 PASS — `suspend (deep)` · `PM: suspend entry (deep)` · QMP `suspended` · `system_wakeup` 뒤 `resumed after 2594ms`(2초 재움 +
  드나듦) · 셸의 `lp-42` · terminal 살아 있음. QEMU는 깨울 때 virtio-gpu를 리셋하지만 terminal 프로세스는 버텼다(다시 그려지는지는
  안 본다 — 실기에서는 i915가 그 일이다).
- 루트 게이트 30/30(LP-M2와 함께, 17분 28초).
