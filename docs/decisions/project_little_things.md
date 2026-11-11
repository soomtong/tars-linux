---
name: project_little_things
description: "작은 것 다섯(LT-M0, 2026-11-12) — `hostname=` 키(기본 tars, 갈래 now), initrd의 ping과 ping_group_range, `/sys/class/dmi/id`(DMIID), Landlock(Homebrew 7의 샌드박스), sudo `timestamp_type=global`. 함정 — 기본 이름이 게이트의 프롬프트를 두 칸 줄였다, seed가 4096을 넘었다, 화면 dump는 탭을 안 싣는다"
metadata:
  node_type: memory
  type: project
---

LT(Little Things, 2026-11-11~12)가 세웠다. design `docs/specs/2026-11-11-tars-little-things-design.md`, plan `-lt-m0`. `carryover.md`에 쌓여 있던
실기 진단의 아쉬움 다섯을 사용자가 한 묶음으로 골랐다. 구현은 서브에이전트, 커널 옵션 · 게이트 · 커밋은 lead.

## 무엇이 섰나

- `hostname=`(스물둘째 키, 기본 `tars`): 영문 소문자 · 숫자 · `-`, 1~63자, `-`로 시작 · 끝나지 않는다(대문자는 거절). init이 `sethostname`,
  `/etc/hostname`, `/etc/hosts`의 `127.0.1.1 <이름>`. 갈래는 `now`(terminal argv에 안 든다). 로그 `tars-init: hostname NAME`,
  `config shell=…` 줄의 맨 끝 칸.
- `ping`: `iputils-ping`을 sysroot · initrd에(새 라이브러리 0개), init이 `ping_group_range`를 `0 2147483647`로 — setuid도 capability도 없이
  사용자가 ICMP를 보낸다.
- 커널: `DMIID`(`/sys/class/dmi/id/product_name` 등), `SECURITY` · `SECURITYFS` · `SECURITY_LANDLOCK` · `LSM="landlock"`(다른 LSM · `INTEGRITY`는 끔).
  bzImage +48KiB. 판정 줄 `landlock: Up and running.`
- sudoers `Defaults timestamp_type=global` — 한 패널에서 확인하면 15분 동안 다른 패널 · ssh에서 안 묻는다.

## 함정

1. 기본 이름이 프롬프트를 `root@(none) ~#` → `root@tars ~#`로 두 칸 줄였다. 그 글자를 보는 체인 열(pointer · keyboard · fullscreen · cursor ·
   battery · hidpi · pane · dictation · mise · devtools)과 칸 수 둘(cursor `col=15 → 13`, copy `col 20 → 18`)을 함께 고쳤다.
2. seed에 두 줄이 늘자 `tars.conf`가 설치기의 `user=` 꼬리와 합쳐 `config.MAX_FILE` 4096을 넘었다(설치기가 파일을 못 쓴다). 8192로 올렸다 —
   키를 더할 때 `config_test`의 32자 사용자 이름 검사가 이제 잡는다.
3. 화면 dump는 탭이 건너뛴 칸을 싣지 않는다 — `/etc/hosts`의 `127.0.1.1\tair`가 `127.0.1.1air`다. 두 판정이 첫 판에 빨갰다.
4. sudo 1.9.14부터 `use_pty`가 기본이라 `sudo -u 사용자`가 새 pty를 준다 — home 체인 8g가 그것으로 "다른 tty"를 만든다.

pm 체인이 덤으로 본 것: `brew install hello`가 `Sandbox unavailable` 대신 `Landlock ABI: 7`로 샌드박스를 쓴다(망 전부를 막는 것은 ABI 10부터 —
커널 7.x에서). 게이트가 안 보는 것: git 기본 신원의 `.(none)`.

5. 프롬프트를 보는 체인을 고칠 때 pm 한 자리를 놓쳤고 루트 게이트가 찾았다. 체인 단독 실행은 루트 게이트의 입구 검사(`grep -q` 등)도
   안 지난다 — 체인을 고친 뒤에는 lessons의 입구 검사 한 줄을 모든 체인에 돌린다.

관련: [[project_container_environment]] · [[project_release]]
