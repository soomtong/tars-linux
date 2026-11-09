# BB-M1 — fakesteak 묶음과 부팅 때 자동 실행

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-barebone-design.md`(결정 2 · 3 · 5 · 6)
Status: plan — 착수 전

## 착수 전에 확정한 것

design의 "BB-M1 plan이 먼저 확인할 것" 셋과, plan을 쓰며 읽은 것(HEAD `b1a13fb`).

1. fakesteak의 끝내기. `on_signal`이 SIGINT · SIGQUIT · SIGTERM에 `running = 0`만 세우고, 메인 루프가 빠져나와 `mat_free` → `cli_reset()`
   (커서 보이기 · termios 되돌리기)을 부른다(`src/fakesteak.c` 207-220 · 끝부분, fork `76c5f4c`). Ctrl+C로 끝내도 패널이 깨끗하다.
2. 순서. init의 `Boot`가 `/home`을 붙인 뒤 `layers.mountAll`(`init/src/main.zig:1244`)에서 묶음마다 `etc/`를 tmpfs `/etc`로 복사하고
   (`init/src/layers.zig:383-389`, 로그 `tars-init: layer <이름>: N files into /etc`), terminal은 그 뒤(`main.zig:1548~`)에 뜬다. 첫 패널의 셸이
   조각을 읽을 때 조각은 이미 있다.
3. `/tmp`는 `chmod 1777`(`kernel/make_initrd.sh:154`) — 사용자 tars가 표시 파일을 만들 수 있다. initrd의 RAM이라 부팅마다 비워진다.
4. 셸 조각을 읽는 자리. bash · zsh는 시스템 rc의 맨 앞에서 `for f in /etc/tars/rc.d/*.sh; do . "$f"; done`(`make_initrd.sh:931-948`) — 조각은
   그 루프 안에서 source되므로 조각 안의 `return`은 바깥 rc를 끝낸다. 그래서 조각은 `return` 없이 `if` 하나로 쓴다. fish는 `/etc/fish/conf.d/`를
   이름 순으로 읽는다. 선례는 server 묶음의 `etc/tars/rc.d/server.sh` · `etc/fish/conf.d/10-server.fish`.
5. 패널의 셸은 `TERM=xterm-256color`(terminal이 setenv, `terminal/src/main.zig:3758`), 시리얼 콘솔 셸은 `TERM=linux`. ssh는 `SSH_CONNECTION`.
6. 매체의 묶음이 fakesteak 하나인 ISO로 개발 도구 층이 깔린 디스크를 갱신하면, 설치기가 옛 묶음 열을 지우고 fakesteak 하나만 옮긴다
   (`init/src/install.zig` `copyLayersMounted` — 2026-11-09 실기 로그의 `8 old layers removed`). 사용자의 맥북 에어에 이 ISO를 깔면 개발 도구가
   사라진다 — 되돌리려면 묶음 판 ISO로 다시 갱신한다(설치 시간 약 1분). 실기는 사용자가 이것을 알고 고른다.

## Task 1 — manifest 줄과 조각 둘

- `devlayer/manifest.tsv` 끝에 절 머리 주석(BB-M1 — 납품 프로젝트 묶음, 개발 도구가 아니라 `DEV_LAYERS` 기본값에 없다)과 design의 줄 하나.
- `devlayer/files/fakesteak/etc/tars/rc.d/fakesteak.sh`(POSIX sh, `# shellcheck shell=sh`):
  ```sh
  case $- in *i*)
    if [ "${TERM:-}" = xterm-256color ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /tmp/.tars-autorun ] && command -v fakesteak >/dev/null 2>&1; then
      : > /tmp/.tars-autorun
      fakesteak <옵션>
    fi
  ;; esac
  ```
- `devlayer/files/fakesteak/etc/fish/conf.d/90-fakesteak.fish`: 같은 넷을 fish로(`status is-interactive`, `test "$TERM" = xterm-256color`,
  `not set -q SSH_CONNECTION`, `not test -e /tmp/.tars-autorun`, `command -q fakesteak`).
- 표시 파일을 먼저 만들고 띄운다 — fakesteak이 무슨 이유로 죽어도 새 패널마다 다시 뜨지 않는다.
- `<옵션>`은 Task 4의 화면을 보고 고른다. 출발값 `-b`(검은 배경 — 기본 배경 `#102030` 위보다 원작에 가깝다).
- 확인: `make quick`(shellcheck가 조각을 본다면 그것까지).

## Task 2 — 묶음 굽기

- `make dev-layers DEV_LAYERS=fakesteak`. 거두기는 debian 줄이 없어 건너뛴다(design 확인 4). build.sh가 받기 · sha256 · 풀기(`strip=1`) · 링크
  (`exe=fakesteak`) · initrd와 겹친 경로 · NEEDED 검사(정적이라 없음) · 굽기.
- 기록: `devlayer/build/fakesteak.sqfs` 크기, 묶음 안 경로(`unsquashfs -l`), 걸린 시간.

## Task 3 — 납품 ISO

- `make iso ISO_LAYERS="fakesteak"` → 저장소 밖에 `tars-<ver>-fakesteak-x86_64.iso`(데모 — 릴리스에 안 올린다, design 비목표).
- 크기 기록(barebone 143,751,168 B + 묶음).

## Task 4 — QEMU probe 한 판(`out/bb-m1/probe.sh`, 저장소 밖 — TP-M12의 방식)

devtools 체인의 모양(OVMF · NVMe 16GiB · 시리얼 FIFO · `-cpu SandyBridge`)을 따른 부팅 둘.

1. ISO + 빈 NVMe: `tars-install /dev/nvme0n1 --yes` → `done`, 묶음 줄에 fakesteak 하나.
2. NVMe만: 판정
   - 로그 `tars-init: layer fakesteak: 2 files into /etc`.
   - root 콘솔에서 `pgrep -a fakesteak`(uid 1000), `ls -l /tmp/.tars-autorun`. 콘솔 셸(`TERM=linux`)은 안 띄웠다 — `pgrep`이 하나뿐.
   - monitor `screendump`으로 화면 한 장(비가 내리는가 — 사용자에게 보일 그림).
   - monitor `sendkey ctrl-c` → `pgrep`이 비고, 화면 한 장(프롬프트가 돌아왔는가).
   - 새 패널(키는 WP의 단축키)을 열어도 `pgrep`이 비어 있다(한 번만).

## 판정

- Task 4의 다섯이 모두 맞다. init · terminal 코드 변경 0 — 루트 게이트는 안 돌린다(design: smoke만, 체인 없음).

## 비목표

1. 사용자의 맥북 에어 실기 — 확정 6 때문에 사용자가 고른다. 고르면 Task 3의 파일을 쓴다.
2. 셸 없는 키오스크(design 비목표).
3. 소개 페이지 — BB를 닫을 때.
