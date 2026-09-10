---
name: project_guest_environment
description: "게스트의 환경변수는 커널이 준 HOME=/ 와 TERM=linux 둘에서 시작한다 — PATH는 UT-M0부터 PID 1이 지어 자식 둘에게 준다(PATH=/usr/bin:/bin), TERM은 terminal 쪽 setenv로 xterm-256color가 되고 그 terminfo는 initrd에 직접 넣는다(시리얼 셸은 linux 유지)"
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

## 결과 1: `PATH`가 없었다 — UT-M0(2026-09-10)에 고쳤다

**2026-08-17부터 2026-09-10까지 참이었던 것.** 게스트 셸에서 `sleep 100`이
실패했다. 그동안 **외부 명령은 절대 경로로 썼다** — `/usr/bin/sleep`,
`/usr/bin/bash`. IP-M0 게이트가 그렇게 고쳐졌고(`input/check.sh`), IP-M2가
fish에서 bash로 갈아타는 대목도 같은 제약을 받았다. **열 체인이 전부 그렇게
쓰여 있고 지금도 그렇다** — 절대 경로는 PATH가 있어도 여전히 맞기 때문에
고칠 이유가 없다.

CP-M2까지 이 사실이 드러나지 않은 이유는 그때까지 게이트가 화면 셸에서 **셸
builtin만** 썼기 때문이다(`echo ... > /config/tars.conf`). IP-M0의
`/usr/bin/sleep`이 화면 셸에서 외부 바이너리를 실행한 첫 사례다.

이 문서는 그때 **유예를 적어 뒀다** — *"채우는 자리가 PID 1인지, 터미널인지,
셸 설정인지는 설정 시스템과 함께 결정할 문제이고, 게이트에 절대 경로를 쓰는
비용은 키 몇 개다."* **그 설정 시스템이 CP-M2로 2026-08-15에 생겼고, 비용이
"키 몇 개"인 것도 더 이상 참이 아니게 됐다** — 2026-09-10에 사용자가 기계를
실제로 써 보고 "`ls` 같은 것들이 없다"고 지목했다. 게이트가 아니라 사람이
쓰는 기계가 됐다는 뜻이다.

**UT-M0이 그 자리를 PID 1로 정했다.** `PATH`는 `TERM`과 달리 자식마다 갈릴
이유가 없는 값이고(화면 셸도 시리얼 콘솔 셸도 같은 `/usr/bin`을 본다), 그래서
`terminal`의 `setenv` 옆이 아니라 커널 블록을 짓는 자리로 갔다. **아래 결과
3의 `LANG`이 갈릴 이유 없이 갈려 있는 자기비판을 이 문서가 적어 뒀고, 그
실수를 반복하지 않은 것이 이 결정이다.**

| 자리 | 무엇 |
|---|---|
| `init/src/environ.zig` | 커널 블록을 복사하고 끝에 `PATH=/usr/bin:/bin`을 붙인 새 블록을 짓는다. **시스템 콜을 안 한다** |
| `init/src/environ_test.zig` | 그 함수의 호스트 검사 넷. 부팅 20초가 아니라 0.1초로 돈다 |
| `init/src/main.zig` | `main()`의 스택에 블록을 잡고 `supervise()`가 자식 둘에게 그대로 넘긴다 |
| `tools/check.sh` | 열한번째 체인. 게스트에 **절대 경로 없이** `ls`를 친다 |

**값이 `/usr/bin:/bin` 둘뿐인 것에 뜻이 있다.** 도구는 전부 `/usr/bin`에 넣고
`/bin`에는 `sh` 하나만 둔다. 이 문자열과 `kernel/make_initrd.sh`가 넣는 자리가
어긋나면 증상은 "어떤 명령도 안 찾아진다"이고 원인에서 멀다.

**자리가 모자라면 커널 블록을 그대로 돌려준다.** PATH가 없는 게스트는
불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다. 그때
init이 `tars-init: env unchanged (no room for PATH)`를 찍고, 그 침묵이 곧
게이트의 판정이다.

**시리얼 콘솔 셸도 받는다 — 다만 관측된 적은 없다.** `supervise()`가
`start(c, envp)`를 한 루프에서 부르는 코드 구조가 보장할 뿐이다. 아래
`TERM`에 대해 이 문서가 같은 말을 적어 둔 것과 같은 기준이고, 저장소의 열한
체인 전부가 `-serial file:`(쓰기 전용)이라 시리얼 셸에 타이핑한 체인이
하나도 없다.

**함께 생긴 것이 뼈대 넷이다** — `/bin/sh`(→ `../usr/bin/bash` 심볼릭 링크) ·
`/tmp`(모드 1777) · `/etc/passwd` · `/etc/group`. `PATH`만으로는 부족했다.
자세히는 [[project_userland_tools]].

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

**TR-M0(2026-08-23)이 그 값을 `xterm-256color`로 바꿨다** — 이제 팔레트
256색과 truecolor를 전부 칠하므로 `xterm`이라고 말하는 쪽이 거짓말이 된다.

**그런데 그때 initrd는 따라오지 않았다. TR-M2(2026-08-23)가 닫았다.**

TR-M0이 이름만 바꾸고 `make_initrd.sh`는 `x/xterm` 파일 하나만 계속 복사해서,
**게스트가 광고하는 이름의 terminfo가 실제로는 없는 상태로 두 milestone을
건너왔다.** 게이트가 초록이었던 이유는 fish가 조용히 폴백했기 때문이지 맞아서가
아니다 — IP-M1이 닫았던 "TERM이 거짓말한다"는 구멍이 방향만 바뀌어 다시 열려
있었다.

**더 중요한 것은 그것을 막았어야 할 검사가 놓쳤다는 사실이다.**
`input/check.sh`의 initrd 목록 검사가 `*terminfo/x/xterm*` 글로브라
`xterm-256color`가 없어도 `xterm` 하나로 통과했다 — **조용한 실패를 막으려고
만든 검사가 조용히 실패한 자리다.** 그래서 TR-M2는 파일을 넣는 두 줄만 고치지
않고 검사도 조였다. 목록 앞뒤에 줄바꿈을 덧대고 **줄 하나를 통째로** 맞춘다.

```bash
PADDED_LIST="$(printf '\n%s\n' "$INITRD_LIST")"
for want in xterm xterm-256color; do
  case "$PADDED_LIST" in
    *$'\n'"usr/share/terminfo/x/${want}"$'\n'*) ;;
    *) echo "FAIL: ${want} terminfo is missing from the initrd"; exit 1 ;;
  esac
done
```

`grep -qx`로 쓰지 않는 이유는 이 파일 위쪽의 `case` 주석과 같다 — `grep -q`가
첫 매치에서 빠져나가며 앞단 `cpio`에 SIGPIPE를 일으키고 `pipefail`이 그것을
실패로 판정한다.

**terminfo를 제대로 넣어도 셸은 색 시퀀스를 쓰지 않았다.** TR design 위험 1이
"TERM을 바꾸면 화면을 grep하는 다섯 체인이 흔들릴 수 있다"고 경고한 자리인데,
TR-M0에서는 terminfo가 없어서 셸이 능력을 몰랐던 것이라 **진짜 시험이
아니었다.** TR-M2가 파일을 넣은 뒤 IP 체인(fish + bash 두 번 부팅)과 루트
게이트 일곱 체인 3/3을 돌려도 `screen>` 줄이 하나도 달라지지 않았다 — **이제
진짜로 닫힌 위험이다.**

**시리얼 콘솔 셸은 `linux`를 유지한다.** 그쪽은 정말로 커널 콘솔이고,
`terminal`을 거치지 않으므로 xterm이 아니다. PID 1이 자식 둘을 띄우는데
(`project_init_supervisor`) 둘의 `TERM`이 서로 달라야 한다는 뜻이다 — 그래서
`setenv`가 PID 1이 아니라 `terminal` 쪽에 있다. **게이트는 PTY 쪽만
확인한다**(`echo $TERM` → `xterm`). 시리얼 쪽이 `linux`로 남는 것은 코드
구조상 보장될 뿐 관측된 적은 없다.

부수 사실 하나: terminfo를 제대로 넣어준 뒤에도 `fish --no-config`는
`smkx`를 보내지 않는다(DECCKM이 계속 꺼져 있다). 자세히는
[[project_gate_chain_composition]]의 "게이트가 구조적으로 밟을 수 없는 경로".

**How to apply:** 게스트에 지금 있는 환경변수는 **넷**이다 —
`HOME=/`(커널) · `TERM`(화면 셸은 `xterm-256color`, 시리얼 셸은 `linux`) ·
`LANG=C.UTF-8`(화면 셸만) · `PATH=/usr/bin:/bin`(둘 다). **그 밖의 것은
없다고 가정한다.**

게이트를 새로 쓸 때는 여전히 **절대 경로를 기본으로 쓴다.** PATH가 생겼어도
절대 경로가 틀린 것이 아니고, 열 체인이 그렇게 쓰여 있어 일관성이 값이다.
**이름으로 부르는 것을 일부러 시험하는 자리는 `tools/check.sh` 하나다** —
그것이 그 체인의 존재 이유다.

새 환경변수가 필요해지면 그것을 넣는 자리(PID 1 / terminal / 셸 설정)가
`TERM`처럼 **자식마다 달라야 하는 값인지** 먼저 판단한다. 갈릴 이유가 없으면
PID 1이고, 그 길은 `init/src/environ.zig`에 이미 깔려 있다 — `PATH_ENTRY`
옆에 항목을 하나 더하고 `MAX_ENTRIES`가 남는지만 보면 된다.

관련: [[project_init_supervisor]], [[project_config_persistence]],
[[project_gate_chain_composition]], [[project_userland_tools]]

## 결과 3: 로케일이 없었다 — HI-M1(2026-09-01)에 고쳤다

**`LANG`도 `LC_ALL`도 없으므로 게스트의 모든 프로세스가 C 로케일이다.** 그리고
`libc6`에는 로케일 데이터가 없다 — Debian은 미리 컴파일된
`/usr/lib/locale/C.utf8`을 **`libc-bin`**에 담는다. 그것을 안 받아 왔으므로
게스트에는 UTF-8 로케일이 **아예 없었다.**

**증상이 입력이 아니라 화면에 나타난다.** 한글 입력기(HI-M1)가 확정된 음절을
UTF-8 세 바이트로 PTY에 보내는데, 셸의 `setlocale`이 실패한 상태라
`mbrtowc`가 바이트를 하나씩 돌려준다. fish는 그것을 **한 글자가 아니라 세
글자로** 들고, 바이트마다 폭을 센다 — 0x80~0x9F는 C1 제어라 0칸, 0xA0 이상은
1칸이다. 그러면 커서가 두 칸짜리 글자의 **가운데**에 서고 다음 글자가 앞
글자를 지운다. `가나다`가 `가 다`가 된다.

```
string length 나          → 3   ← 세 글자로 센다
string length -V 나       → 1   ← 그래서 폭이 1
string length \ub098   → 1   ← 이스케이프로 만든 같은 글자는 정상
```

**`LANG`만 설정해서는 안 된다.** 값이 셸까지 닿는 것은 확인했는데
(`echo x=$LANG` → `x=C.UTF-8`) 로케일 파일이 없어서 `setlocale`이 그래도
실패한다. **환경변수와 데이터가 한 벌이어야 한다** — TERM과 terminfo가 정확히
같은 모양이고, 그래서 고치는 자리도 같다.

| 자리 | 무엇 |
|---|---|
| `devcontainer/Dockerfile` | `libc-bin:amd64`를 받아 sysroot에 푼다 |
| `kernel/make_initrd.sh` | `/usr/lib/locale/C.utf8` 404KB를 initrd에 넣는다 |
| `terminal/src/main.zig` | `TERM` 옆에서 `LANG=C.UTF-8`을 설정한다 |

**시리얼 콘솔 셸은 C 로케일로 남는다.** PID 1이 커널의 envp 블록을 그대로
넘기므로 거기에 항목을 더하려면 블록을 새로 만들어야 하는데, 한글 입력을 받는
셸은 화면 쪽 하나뿐이라 그 값을 안 치렀다. **TERM이 둘로 갈리는 것과 이유가
다르다** — 그쪽은 갈려야 맞고, 이쪽은 갈릴 이유가 없는데도 갈려 있다.

**UT-M0(2026-09-10)이 그 값을 치렀다 — `LANG`은 아직 안 옮겼다.** 블록을
새로 짓는 코드가 `init/src/environ.zig`에 생겼으므로, `LANG`을 PID 1로
옮기는 비용은 이제 `PATH_ENTRY` 옆에 줄 하나다. **안 옮긴 이유는 UT-M0의
범위가 아니어서이지 어려워서가 아니다** — 옮기면 시리얼 셸도 UTF-8이 되고,
그 변화를 볼 체인이 저장소에 없다(시리얼 셸에 타이핑하는 체인이 하나도
없다). **다음에 이 문단을 읽는 사람에게 남기는 후보다.**
