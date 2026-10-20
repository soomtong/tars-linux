---
name: project_guest_environment
description: "게스트의 환경변수는 커널이 준 HOME=/ · TERM=linux 둘에서 시작한다 · PATH=/usr/bin:/bin은 PID 1이 지어 자식 둘에게 준다(UT-M0) · TERM=xterm-256color와 LANG=C.UTF-8은 terminal의 setenv로 화면 셸에만, 시리얼 셸은 linux · C 로케일 · 환경변수와 데이터(terminfo · C.utf8)는 한 벌로 initrd에 넣는다 · 자식마다 갈릴 이유가 없는 값은 PID 1에"
metadata:
  node_type: memory
  type: project
---

IP-M0(2026-08-17)이 확인했고 IP-M1 · TR-M2 · HI-M1 · UT-M0이 하나씩 채웠다.
코드는 `init/src/environ.zig`(PID 1의 블록) · `terminal/src/main.zig`(`setenv`)
· `kernel/make_initrd.sh`(데이터)이고, 게이트는 `tools/check.sh` ·
`input/check.sh`다. milestone별 경과와 게이트 시간은 2026-10-20에
지웠다(커밋 이력에 있다).

게스트의 모든 프로세스의 환경은 커널이 PID 1에게 준 두 개에서 시작한다.

```c
/* linux/init/main.c */
const char *envp_init[MAX_INIT_ENVS+2] = { "HOME=/", "TERM=linux", NULL, };
```

initrd에 프로필 스크립트가 없고 게이트의 셸은 전부 no-config 모드(`fish
--no-config` / `bash --norc` / `zsh -f`)라 셸 초기화 파일이 채울 여지도 없다.
그래서 필요한 값은 우리가 PID 1이나 `terminal`에서 넣어야 하고, 넣지 않은
것은 없다.

## 결과 1: `PATH`가 없었다 — UT-M0(2026-09-10)에 고쳤다

증상은 게스트 셸에서 `sleep 100`이 실패하는 것이었다. 게이트가 화면 셸에서
builtin만 쓰는 동안은 드러나지 않았고, 사람이 기계를 쓰자 "`ls` 같은 것들이
없다"로 드러났다. 그동안 게이트는 IP-M0부터 외부 명령을 절대 경로
(`/usr/bin/sleep` · `/usr/bin/bash`)로 쳤고 지금도 그렇다.

결정: `PATH`는 PID 1이 짓는다. `TERM`과 달리 자식마다 갈릴 이유가 없는
값이라(화면 셸도 시리얼 셸도 같은 `/usr/bin`을 본다) `terminal`의 `setenv`
옆이 아니라 커널 블록을 짓는 자리로 갔다.

| 자리 | 무엇 |
|---|---|
| `init/src/environ.zig` | 커널 블록을 복사하고 끝에 `PATH=/usr/bin:/bin`을 붙인 새 블록을 짓는다. 시스템 콜을 안 한다 |
| `init/src/environ_test.zig` | 그 함수의 호스트 검사 넷 |
| `init/src/main.zig` | `main()`의 스택에 블록을 잡고 `supervise()`가 자식 둘에게 그대로 넘긴다 |
| `tools/check.sh` | 게스트에 절대 경로 없이 `ls`를 치는 체인 |

값이 `/usr/bin:/bin` 둘뿐인 것에 뜻이 있다. 도구는 전부 `/usr/bin`에, `/bin`
에는 `sh` 하나만 둔다. 이 문자열과 `kernel/make_initrd.sh`가 넣는 자리가
어긋나면 증상은 "어떤 명령도 안 찾아진다"이고 원인에서 멀다.

자리가 모자라면 커널 블록을 그대로 돌려준다. PATH가 없는 게스트는 살아
있지만 버퍼를 넘겨 쓴 PID 1은 기계를 못 켠다. 그때 `tars-init: env unchanged
(no room for PATH)`를 찍고, 그 줄이 없는 것이 게이트의 판정이다.

시리얼 콘솔 셸도 받는다 — 다만 `supervise()`가 `start(c, envp)`를 한
루프에서 부르는 코드 구조가 보장할 뿐 관측된 적은 없다. 체인 전부가
`-serial file:`(쓰기 전용)이라 시리얼 셸에 타이핑하는 체인이 없다.

`PATH`만으로는 부족해 뼈대 넷이 함께 생겼다 — `/bin/sh`(→
`../usr/bin/bash`) · `/tmp`(모드 1777) · `/etc/passwd` · `/etc/group`.
자세히는 [[project_userland_tools]].

## 결과 2: `TERM`은 거짓말이었다 — IP-M1(2026-08-18)에 고쳤다

커널의 `TERM=linux`가 상속되는데 실제 상대는 libghostty-vt(xterm 계열)다.
셸과 ncurses는 terminfo로 시퀀스를 고르므로 방향키가 어긋난다 — Home이
`linux`에서는 `ESC [ 1 ~`, xterm(`khome`)에서는 `ESC O H`다.

처방: `terminal/src/main.zig`가 `forkpty` 직전에
`setenv("TERM","xterm-256color",1)`을 부른다(IP-M1은 `xterm`, TR-M0이 256색
· truecolor를 칠하게 되며 바꿨다). 셋째 인자 `overwrite`가 1이어야 한다 —
값이 이미 있으므로 0이면 조용히 아무 일도 안 한다. terminfo는
`kernel/make_initrd.sh`가 `/usr/share/terminfo/x/xterm`과
`x/xterm-256color`를 넣고, 파일은 `devcontainer/Dockerfile`의 `apt-get
download` 목록의 `ncurses-base`에서 온다 — arch: all이라
`fish-common`/`zsh-common`처럼 `:amd64`를 붙이지 않는다.

함정: 이름을 바꾸면 데이터가 따라와야 한다. TR-M0이 `xterm-256color`로
바꾸고 initrd는 `x/xterm`만 복사해, 광고하는 이름의 terminfo가 없는 채로 두
milestone을 건넜다. 게이트가 초록이었던 것은 fish가 조용히 폴백했기
때문이다. 그것을 막았어야 할 `input/check.sh`의 initrd 목록 검사가
`*terminfo/x/xterm*` 글로브라 `xterm` 하나로 통과했다 — 조용한 실패를 막는
검사가 조용히 실패한 자리다. TR-M2가 파일과 검사를 함께 고쳐, 목록 앞뒤에
줄바꿈을 덧대고 줄 하나를 통째로 맞춘다.

```bash
PADDED_LIST="$(printf '\n%s\n' "$INITRD_LIST")"
for want in xterm xterm-256color; do
  case "$PADDED_LIST" in
    *$'\n'"usr/share/terminfo/x/${want}"$'\n'*) ;;
    *) echo "FAIL: ${want} terminfo is missing from the initrd"; exit 1 ;;
  esac
done
```

`grep -qx`를 안 쓰는 이유는 그 파일 위쪽의 `case` 주석과 같다 — `grep -q`가
첫 매치에서 빠져나가며 앞단 `cpio`에 SIGPIPE를 일으키고 `pipefail`이 그것을
실패로 판정한다.

terminfo를 제대로 넣어도 화면을 grep하는 체인의 `screen>` 줄은 하나도
달라지지 않았다(TR design 위험 1이 닫혔다). 그래도 `fish --no-config`는
`smkx`를 보내지 않는다(DECCKM이 계속 꺼져 있다) —
[[project_gate_chain_composition]]의 "게이트가 구조적으로 밟을 수 없는 경로".

시리얼 콘솔 셸은 `linux`를 유지한다. 그쪽은 정말로 커널 콘솔이라 xterm이
아니다. PID 1이 띄우는 자식 둘([[project_init_supervisor]])의 `TERM`이 달라야
하므로 `setenv`가 PID 1이 아니라 `terminal` 쪽에 있다. 게이트는 PTY 쪽만
확인하고, 시리얼 쪽이 `linux`인 것은 코드 구조상 보장될 뿐이다.

## 결과 3: 로케일이 없었다 — HI-M1(2026-09-01)에 고쳤다

`LANG`도 `LC_ALL`도 없어 모든 프로세스가 C 로케일이었고, Debian은 미리
컴파일된 `/usr/lib/locale/C.utf8`을 `libc6`가 아니라 `libc-bin`에 담아서
UTF-8 로케일이 아예 없었다.

증상은 입력이 아니라 화면에 나온다. 한글 입력기가 음절을 UTF-8 세 바이트로
PTY에 보내는데, `setlocale`이 실패한 셸에서 `mbrtowc`가 바이트를 하나씩
돌려준다. fish는 세 글자로 들고 바이트마다 폭을 센다(0x80~0x9F는 C1 제어라
0칸, 0xA0 이상은 1칸). 커서가 두 칸짜리 글자의 가운데에 서고 다음 글자가 앞
글자를 지워 `가나다`가 `가 다`가 된다.

```
string length 나          → 3   ← 세 글자로 센다
string length -V 나       → 1   ← 그래서 폭이 1
string length \ub098   → 1   ← 이스케이프로 만든 같은 글자는 정상
```

함정: `LANG`만 설정해서는 안 된다. 값이 셸까지 닿아도(`echo x=$LANG` →
`x=C.UTF-8`) 로케일 파일이 없으면 `setlocale`은 실패한다. 환경변수와 데이터가
한 벌이어야 한다 — `TERM`과 terminfo와 같은 모양이고 고치는 자리도 같다.

| 자리 | 무엇 |
|---|---|
| `devcontainer/Dockerfile` | `libc-bin:amd64`를 받아 sysroot에 푼다 |
| `kernel/make_initrd.sh` | `/usr/lib/locale/C.utf8` 404KB를 initrd에 넣는다 |
| `terminal/src/main.zig` | `TERM` 옆에서 `LANG=C.UTF-8`을 설정한다 |

시리얼 콘솔 셸은 C 로케일로 남는다. `TERM`과 달리 갈릴 이유가 없는데
갈려 있다 — HI-M1 때는 PID 1이 블록을 새로 짓는 코드가 없어서였다. 이제
`init/src/environ.zig`가 있으므로 `LANG`을 PID 1로 옮기는 비용은 `PATH_ENTRY`
옆에 줄 하나다. 안 옮긴 것은 그 변화를 볼 체인(시리얼 셸에 타이핑하는 체인)이
없어서이고, 남겨 둔 후보다.

## How to apply

게스트에 지금 있는 환경변수는 넷이다 — `HOME=/`(커널) · `TERM`(화면 셸은
`xterm-256color`, 시리얼 셸은 `linux`) · `LANG=C.UTF-8`(화면 셸만) ·
`PATH=/usr/bin:/bin`(둘 다). 그 밖의 것은 없다고 가정한다.

게이트를 새로 쓸 때는 여전히 절대 경로(`/usr/bin/sleep`)를 기본으로 쓴다.
PATH가 생겼어도 틀린 것이 아니고 기존 체인이 그렇게 쓰여 있어 일관성이 값이다.
이름으로 부르는 것을 일부러 시험하는 자리는 `tools/check.sh` 하나다.

새 환경변수가 필요해지면 그것을 넣는 자리(PID 1 / terminal / 셸 설정)가
`TERM`처럼 자식마다 달라야 하는 값인지 먼저 판단한다. 갈릴 이유가 없으면
PID 1이고, `init/src/environ.zig`의 `PATH_ENTRY` 옆에 항목을 하나 더하고
`MAX_ENTRIES`가 남는지만 보면 된다. 값을 넣으면 그 값이 가리키는 데이터
(terminfo · 로케일 파일)도 initrd에 있는지, 그리고 검사가 그 파일을 줄
단위로 맞추는지 본다.

관련: [[project_init_supervisor]], [[project_config_persistence]],
[[project_gate_chain_composition]], [[project_userland_tools]]
