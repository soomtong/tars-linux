---
name: project_kernel_upgrade
description: "설치된 디스크의 이미지 슬롯 둘(new · old)과 1GiB ESP, 그 위에서 커널 6.18.42 → 6.18.60(KU-M0~M1, 2026-11-01). 롤백은 사람이 Limine 메뉴에서 한다. 함정 — pipefail 아래 clean | grep -q, 게이트의 clean()이 지난 로그를 지운다"
metadata:
  node_type: memory
  type: project
---

# Kernel Upgrade (KU)

design은 `docs/specs/2026-11-01-tars-kernel-upgrade-design.md`, plan은 `docs/plans/2026-11-01-tars-kernel-upgrade-ku-m0.md` ·
`…-ku-m1.md`. 사용자가 제안했다(2026-11-01). 처음 제안의 legacy 세대 보관은 사용자가 뺐고, ESP 1GiB는 사용자가 정했다.

## 무엇이 섰나

- 슬롯 둘. new는 지금 자리 `boot/`, old는 `boot/old/`. 슬롯 하나 = `bzImage` · `initrd.cpio` · `version`이다 — firmware가 initrd에 있어
  커널만 따로 두면 짝이 어긋난다. `version`은 맨 마지막에 써서 "끝까지 써졌다"는 표지를 겸하고, 없으면 회전하지 않고 덮는다.
- 회전 순서 `disk.ROTATION` = clear_old → write_conf → move_to_old → copy_new → write_version, op마다 `sync`. write_conf가 move보다
  먼저인 것이 핵심이다(반대면 옛 conf가 빈 `boot/bzImage`를 가리키는 순간이 생긴다). 회전 전에 `빈 자리 + old ≥ 매체 두 파일 + 1MiB`를
  보고 모자라면 YES 전에 멈춘다.
- ESP conf만 `timeout: 3`, 엔트리 둘, 기본은 늘 new(`remember_last_entry` 안 씀). ISO conf는 `timeout: 0` 그대로. old 엔트리는
  `tars.slot=old`를 붙인다(init은 안 읽는다, 사람과 게이트가 `/proc/cmdline`으로 본다).
- 새 설치의 ESP는 1GiB(`MIN_DISK_BYTES` = 2 GiB + 2 MiB, 모자라면 YES 전 거절). 이미 깔린 256MiB 디스크는 `--wipe`로만 넓어진다.
- 커널 6.18.60. 다음 longterm(7.4)이 없어 같은 줄기의 최신 패치로 갔다(사용자 결정).

## 배운 것 — 다시 조사하지 말 것

1. Limine(v12.5.2)에는 자동 롤백의 재료가 없다 — boot counting · fallback · one-shot 없음, ESP에 아무것도 안 쓴다. 자동 롤백은 UEFI
   `BootNext`와 init의 "부팅 성공" 확정을 묶어야 한다(KU 비목표 2).
2. Limine 메뉴는 시리얼로 고를 수 있다(`ESC [ B`, 0.5초 뒤 `CR`). 메뉴 글자 사이에 escape가 끼어 날 로그로 grep하면 안 보인다 — escape를
   걷은 뒤 `Booting automatically`를 본다. 없는 `kernel_path`는 panic이지만 키 하나로 카운트다운 없는 메뉴에 돌아간다.
3. `set -o pipefail` 아래 `clean | grep -q`는 일치를 찾고도 거짓이 될 수 있다 — grep이 먼저 끝나면 perl이 SIGPIPE(141)로 죽는다.
   `>/dev/null`로 쓴다. 루트 `check.sh`의 진입 검사가 이 모양을 잡으므로, 체인을 단독으로 돌리기 전에 진입 검사부터 본다.
4. 커널 패치 버전을 올릴 때 읽을 자리(KU-M1 plan 확정 1~7): `sha256sums.asc`, 커밋된 `.config`가 옛 소스의 `olddefconfig` 고정점인지,
   새 소스의 `olddefconfig` diff, iwlwifi `*_UCODE_API_MAX`(정렬해서 — `grep -r` 순서가 달라 거짓 diff가 난다), 트리 전체
   `MODULE_FIRMWARE`, `drm.zig`가 기대는 DRM 파일. 소스는 컨테이너 안에 푼다(macOS는 대소문자만 다른 커널 파일을 겹친다), 컨테이너엔
   python3가 없어 `scripts/diffconfig` 대신 호스트 `diff`.
5. 게이트의 `clean()`이 `out/`을 지우므로 `out/gate-logs`에는 마지막 회차만 남는다. 회차 사이 비교가 필요하면 게이트 전에 옮겨 둔다.
6. `perl -e 'alarm N; exec @ARGV' make run-qemu …`는 make만 끊고 QEMU는 남는다(ppid 1).

## 숫자

한 벌 102,362,098바이트(6.18.60, bzImage 8,983,552). 첫 설치 뒤 1GiB ESP의 빈 자리 968,904,704바이트. 루트 게이트 22/22 — M0 10분 26초
(verify 8237), M1 10분 30초(prebuild 322 + lanes 306초, verify 8214).

관련: [[project_disk_install]] · [[project_kernel_config]] · [[project_release]].
