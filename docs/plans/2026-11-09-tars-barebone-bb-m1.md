# BB-M1 — fakesteak 묶음과 부팅 때 자동 실행

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-barebone-design.md`(결정 2 · 3 · 5 · 6)
Status: 끝났다(2026-11-09)

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

- `make iso ISO_LAYERS="fakesteak"` → 저장소 밖 빈 디렉터리에 `tars-demo-fakesteak-<YYYYMMDD>-x86_64.iso`(Task 5가 올린다). 트리가 clean이어야
  버전 글자에 `-dirty`가 없다 — Task 1 · 2를 커밋한 뒤에 짓는다.
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

## Task 5 — 데모 릴리스(사용자 2026-11-09 요청)

Task 4가 판정을 지난 뒤, `project_release_0_2`의 프리릴리스 모양 그대로:

- `git tag -a demo-fakesteak-<YYYYMMDD> <ISO를 지은 커밋> -m …` → push → `gh release create … --prerelease --latest=false`, 파일은 ISO와 `SHA256SUMS`.
- 노트: barebone 위 fakesteak 묶음 하나, 디스크에 설치한 뒤 부팅하면 첫 패널에 자동 실행 · Ctrl+C로 셸, 개발 도구 층이 깔린 디스크를 갱신하면
  묶음이 fakesteak 하나로 바뀐다는 경고(확정 6), USB 라이브 부팅에는 묶음이 안 붙는다.
- 새 빈 디렉터리에 `gh release download` 후 `shasum -a 256 -c SHA256SUMS`가 OK.

## 판정

- Task 4의 다섯이 모두 맞다. init · terminal 코드 변경 0 — 루트 게이트는 안 돌린다(design: smoke만, 체인 없음).

## 비목표

1. 사용자의 맥북 에어 실기 — 확정 6 때문에 사용자가 고른다. 고르면 Task 5의 release 파일을 쓴다.
2. 셸 없는 키오스크(design 비목표).
3. 소개 페이지 — BB를 닫을 때.

## 결과

판정을 지났다. init · terminal 코드 변경 0.

- Task 1 `3151e37`: manifest 줄 하나(7열), 조각 둘. `make quick` PASS(shellcheck 89파일 — 조각은 추적되는 `*.sh`라 저절로 들어갔다), `fish -n` OK.
- Task 2: `make dev-layers DEV_LAYERS=fakesteak` 4초. 거두기 `no debian lines`, verify `elf=1 unresolved=0`, 묶음 323,584 B — `usr/local/bin/fakesteak`
  → `../lib/fakesteak-1.0.0/fakesteak`, `etc/` 조각 둘, 출처 기록.
- Task 3: `make iso ISO_LAYERS="fakesteak"` 196초, 144,082,944 B(barebone + 331,776 B), 버전 `0.1.4+3151e37`.
- Task 4(`out/bb-m1/probe.sh`, 컨테이너 안 QEMU, 부팅 둘 합 60초): 설치 `layers  fakesteak (1 MiB)` · `copied 1 layers (1 MiB) in 19ms`. 다시 뜬 부팅
  `overlay /usr from 1 layers in 26ms` · `layer fakesteak: 2 files into /etc`, `fakesteak -b`가 uid tars(pid 63), 표시 파일 tars 소유. 화면
  `rain2.png`에 비, `sendkey ctrl-c` 뒤 프로세스 없음 · 화면은 프롬프트 하나(`cli_reset`), 같은 패널의 새 `fish`가 다시 안 띄운다. 첫 판의
  FAIL 한 줄은 판정 grep이 콘솔에 되비친 명령 줄(`sed 's/^/bb-pg3: /'`)을 센 것이었다 — `project_gate_screen_echo`의 함정. 출력 줄만 골라 다시 봤다.
- Task 5: 태그 `demo-fakesteak-20261109` → `3151e37`(annotated), 프리릴리스 · Latest 아님,
  https://github.com/soomtong/tars-linux/releases/tag/demo-fakesteak-20261109 — `tars-demo-fakesteak-20261109-x86_64.iso`
  sha256 `370ead60d0e485d385a8e1201e3c95a80eca21d203e312fdc4f9dd63b29c070e`. 새 디렉터리에 받아 `shasum -c` OK.
- 실기(2026-11-09, 사용자가 골랐다): 맥북 에어 2011에 데모 릴리스를 깔고 부팅 — 첫 패널에 fakesteak이 떴다(사진). 상태 줄(`EN 신세벌 PCS 쿼티 CAPS` ·
  배터리 `98%`)과 격자 둘레의 여백(`GRID_X` · `GRID_Y` 20px, `MARGIN_COLOR`)이 그대로 보인다. 사용자: "Full screen mode 필요하겠다" — 다음 후보
  (HANDOFF).

