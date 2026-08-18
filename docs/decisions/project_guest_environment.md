---
name: project_guest_environment
description: "게스트의 환경변수는 커널이 준 HOME=/ 와 TERM=linux 둘뿐이다 — PATH가 없으므로 게스트에서 외부 명령을 칠 때는 절대 경로로, TERM은 IP-M1이 terminal 쪽 setenv로 xterm으로 고쳤다(시리얼 셸은 linux 유지)"
metadata:
  node_type: memory
  type: project
---

2026-08-17 IP-M0 게이트를 쓰다가 확인했다. TARS 게스트에서 도는 모든
프로세스의 환경변수는 **리눅스 커널이 PID 1에게 준 두 개**가 전부다.

```c
/* linux/init/main.c */
const char *envp_init[MAX_INIT_ENVS+2] = { "HOME=/", "TERM=linux", NULL, };
```

우리 PID 1은 이것을 **그대로 흘려보낸다** — `init/src/main.zig:307`이
`init.environ.block`을 받아 `execve`의 `envp`로 넘기고(`:198-209`), 그
`terminal`이 다시 `forkpty` 뒤 셸을 `exec`하면서 자기 환경을 물려준다.
중간에 아무도 무엇도 추가하지 않는다. initrd에 프로필 스크립트도 없고,
게이트가 띄우는 셸은 전부 no-config 모드(`fish --no-config` / `bash --norc`
/ `zsh -f`)라 셸 초기화 파일이 채워줄 여지도 없다.

## 결과 1: `PATH`가 없다

게스트 셸에서 `sleep 100`은 실패할 수 있다. **외부 명령은 절대 경로로 쓴다**
— `/usr/bin/sleep`, `/usr/bin/bash`. IP-M0 게이트가 그렇게 고쳐졌고
(`input/check.sh`), IP-M2가 fish에서 bash로 갈아타는 대목도 같은 제약을
받는다.

CP-M2까지 이 사실이 드러나지 않은 이유는 그때까지 게이트가 화면 셸에서 **셸
builtin만** 썼기 때문이다(`echo ... > /config/tars.conf`). IP-M0의
`/usr/bin/sleep`이 화면 셸에서 외부 바이너리를 실행한 첫 사례다.

`PATH`를 채워주는 것이 옳은 해결처럼 보이지만 지금은 하지 않는다 — 채우는
자리가 PID 1인지(`init`), 터미널인지, 셸 설정인지는 설정 시스템과 함께
결정할 문제이고, 게이트에 절대 경로를 쓰는 비용은 키 몇 개다.

## 결과 2: `TERM`은 거짓말이었다 — IP-M1(2026-08-18)에 고쳤다

커널이 준 `TERM=linux`가 그대로 상속되는데, 실제 상대는 libghostty-vt
(xterm 계열)다. 셸과 ncurses 프로그램은 terminfo를 보고 시퀀스를 고르므로
**방향키에서 실제로 어긋난다** — Home이 `linux`에서는 `ESC [ 1 ~`,
xterm(`khome`)에서는 `ESC O H`다.

**IP-M1이 이것을 닫았다.** `terminal/src/main.zig`가 `forkpty` 직전에
`setenv("TERM","xterm",1)`을 부르고(셋째 인자 `overwrite`가 **1이어야**
한다 — 값이 이미 있으므로 0이면 조용히 아무 일도 안 한다),
`kernel/make_initrd.sh`가 `/usr/share/terminfo/x/xterm` **파일 하나**를
넣는다. 그 파일은 `devcontainer/Dockerfile`의 `apt-get download` 목록에
추가한 `ncurses-base`에서 온다 — arch: all이라 `fish-common`/`zsh-common`과
같이 **`:amd64`를 붙이지 않는다**(붙이면 안 된다고 걱정하던 위험은 이렇게
해소됐다).

`xterm-256color`가 아니라 `xterm`인 이유는 아직 색을 하나도 그리지 않기
때문이다. 256색을 광고하면 반대 방향의 거짓말이 된다.

**시리얼 콘솔 셸은 `linux`를 유지한다.** 그쪽은 정말로 커널 콘솔이고,
`terminal`을 거치지 않으므로 xterm이 아니다. PID 1이 자식 둘을 띄우는데
(`project_init_supervisor`) 둘의 `TERM`이 서로 달라야 한다는 뜻이다 — 그래서
`setenv`가 PID 1이 아니라 `terminal` 쪽에 있다. **게이트는 PTY 쪽만
확인한다**(`echo $TERM` → `xterm`). 시리얼 쪽이 `linux`로 남는 것은 코드
구조상 보장될 뿐 관측된 적은 없다.

부수 사실 하나: terminfo를 제대로 넣어준 뒤에도 `fish --no-config`는
`smkx`를 보내지 않는다(DECCKM이 계속 꺼져 있다). 자세히는
[[project_gate_chain_composition]]의 "게이트가 구조적으로 밟을 수 없는 경로".

**How to apply:** 게스트에서 명령을 실행하는 코드나 게이트를 쓸 때는 `PATH`가
없다고 가정하고 절대 경로를 쓴다. 환경변수에 의존하는 동작을 보게 되면
"그 변수가 게스트에 실제로 있는가"를 먼저 확인한다 — 기본값은 **없다**다.
새 환경변수가 필요해지면 그것을 넣는 자리(PID 1 / terminal / 셸 설정)가
`TERM`처럼 자식마다 달라야 하는 값인지 먼저 판단한다.

관련: [[project_init_supervisor]], [[project_config_persistence]],
[[project_gate_chain_composition]]
