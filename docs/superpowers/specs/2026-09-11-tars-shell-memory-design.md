# TARS Shell Memory — Design

**Date:** 2026-09-11
**Status:** 진행 중 — **SM-M0 완료(2026-09-11)**, M1·M2 미착수.
Shell Config(SC-M0~M2)가 2026-09-11에 닫히면서
**훅을 걸 자리**가 생겼고, 이 서브프로젝트가 그 자리에 처음으로 무언가를
건다. `zoxide`와 `fzf`를 게스트에 세우고, 셸 셋의 씨앗 rc가 그 둘의 훅을
기본으로 담고, **기계가 사용자에게서 배운 것 둘**(자주 간 디렉터리 · 쳤던
명령)을 `/config`에 남겨 부팅을 넘어 기억하게 한다.

## 한 줄 요약

**UT는 도구를 세웠고, SC는 그 도구에 훅을 걸 자리를 만들었다. SM은 그 자리에
처음으로 훅을 걸고, 기계가 부팅을 넘어 기억하게 한다.**

이 셋이 한 서브프로젝트인 이유는 "도구 두 개 넣기"가 아니다.

| 기계가 배운 것 | 어디에 남나 | 사용자가 뒤지는 법 |
|---|---|---|
| 어느 디렉터리에 자주 갔나 | `zoxide`의 `db.zo` | `z <조각>` |
| 어떤 명령을 쳤나 | 셸 히스토리 | `Ctrl+R` (fzf) |

**둘 다 "학습한 상태를 `/config`에 남기고 rc의 훅으로 셸에 잇는다"는 한
종류의 일이다.** 그래서 씨앗 문법을 넓히는 공사도 한 번에 끝난다.

## 왜 지금인가

UT 비목표 6이 이 문단의 앞줄이다.

> **6. `zoxide`·`fzf`.** 실측 10이 이유다. 셸이 무조건 no-config로 뜨는 한
> 훅을 걸 자리가 없다. **셸 설정을 다루는 서브프로젝트가 생기면 그때 함께
> 온다.**

그 서브프로젝트가 SC였고, 끝났다. SC 비목표 1이 넘긴 것을 그대로 받는다.

> **1. `zoxide`·`fzf`를 넣는 것.** 훅을 걸 자리가 생기면 사용자가 rc에 쓰면
> 되지만, **도구 조달은 UT의 일이다** — `.deb` 목록 · 라이브러리 closure ·
> `guest_tools.sh` · `tools/check.sh`의 검사를 다시 여는 일이고 UT가 세운
> 절차가 그대로 적용된다.

그리고 **범위에 셸 히스토리 영속(SC 비목표 2)을 함께 넣는다** — 사용자가
2026-09-11에 정했다. 근거는 실측 8에 있다: **`fzf`의 `Ctrl+R`이 뒤지는 것이
셸 히스토리이고, 그 히스토리는 지금 부팅마다 사라진다.** 도구만 넣으면
`Ctrl+R`은 반쪽이다.

**`git-delta`는 안 넣는다** — UT 비목표 5가 *"다음에 후보를 찾을 때 이 문단을
먼저 읽을 것"*이라고 적어 둔 것이고 훅 자리(`/config/gitconfig`의
`core.pager`)도 이미 서 있지만, 사용자가 이번 범위에서 뺐다. 비목표 1이다.

## 착수 전에 실측한 것 — **다시 조사하지 말 것**

**측정 환경을 먼저 적는다.** 크기와 `DT_NEEDED`는 **amd64 `.deb`**로 쟀다
(게스트가 amd64다). **동작**(DB 경로 · 히스토리 · 훅의 출력)은 devcontainer가
arm64라 **arm64 바이너리로 쟀다** — 같은 소스의 같은 버전이고 경로 규칙과
환경 변수 처리는 아키텍처에 안 갈리는 자리다. **그래도 게이트가 보는 것은
amd64이고, 그것이 M0의 첫 회차가 하는 일이다.**

### 1. `.deb` 둘은 바이너리 하나씩이고, 하나는 예제를 데려온다

| 패키지 | 버전 | `.deb` | `Depends` |
|---|---|---|---|
| `zoxide` | 0.9.7-1+b1 | 424,452바이트 | `libc6` · `libgcc-s1` |
| `fzf` | 0.60.3-1+b2 | 1,473,536바이트 | `libc6` |

`fzf`의 `.deb` 안에 우리가 **안 넣을** 것이 함께 있다.

```
usr/bin/fzf-tmux                                    7,393    tmux가 없다
usr/share/doc/fzf/examples/key-bindings.{bash,zsh,fish}     실측 6이 이유다
usr/share/doc/fzf/examples/completion.{bash,zsh}            같은 이유
usr/share/fish/vendor_functions.d/fzf_key_bindings.fish     같은 이유
```

### 2. amd64 크기와 `DT_NEEDED` — **새 라이브러리가 0이다**

```
/usr/bin/zoxide   1,173,976바이트   libgcc_s.so.1 libm.so.6 libc.so.6
/usr/bin/fzf      4,368,112바이트   libc.so.6
```

**합 5,542,088바이트이고 새 라이브러리는 하나도 없다.** `libgcc-s1:amd64`는
`devcontainer/Dockerfile:206`에 이미 있고(`btop`의 `libstdc++`가 데려온
것이다), `libm.so.6`은 `libc6`이 담고 있으며 `vim.tiny`가 이미 쓴다.
`copy_lib_deps`가 재귀로 따라가므로 셋 다 이미 initrd에 있다.

> **UT가 세 번 배운 것을 이번에는 착수 전에 했다** — M1·M2는 바이너리의
> `DT_NEEDED`만 보고 `.so`의 것을 안 봐서 두 번 틀렸다. 이번 둘은 사슬이
> 한 겹이라 그 함정이 없다.

### 3. `zoxide`는 `XDG_DATA_HOME`을 본다

```
HOME=… XDG_DATA_HOME=/tmp/p/xdg zoxide add /tmp
  → /tmp/p/xdg/zoxide/db.zo
```

`_ZO_DATA_DIR`도 있지만 **필요가 없다.** `XDG_DATA_HOME` 하나가 `zoxide`와
fish 히스토리(실측 11)를 **동시에** 옮긴다.

기본값은 `$HOME/.local/share/zoxide/db.zo`이고 홈(`/`)은 tmpfs다 — **아무것도
안 하면 DB가 부팅마다 사라진다.**

### 4. **없는 경로는 만들고, 댕글링 링크는 에러다** — 결정 1의 근거

| 무엇을 했나 | 결과 |
|---|---|
| `_ZO_DATA_DIR`을 **없는 깊은 경로**로 두고 `zoxide add /tmp` | **`exit 0`.** `/tmp/p/made/up/deep/db.zo`를 만들었다 |
| DB 자리를 **댕글링 심볼릭 링크**로 두고 `zoxide add /tmp` | **`exit 1`** |

```
zoxide: unable to create data directory: /tmp/zp/h2/.local/share/zoxide

Caused by:
    File exists (os error 17)
```

**이 두 줄이 SC 결정 1의 링크 패턴을 여기서 기각한다.** 게이트 열한 체인 중
설정 디스크가 없는 것이 여섯이고(실측 12), 그 기계에서 `/config/…`를 가리키는
링크는 댕글링이다. `zoxide`의 훅은 `chpwd_functions`에 걸려 있어(실측 5)
**`cd` 한 번마다 위 두 줄이 화면에 찍힌다** — 그것이 곧 화면 좌표다.

### 5. `zoxide init`은 조용하고, 훅은 `cd`에만 걸린다

```
zoxide init zsh   →  stdout 4,569바이트 / 149줄,  stderr 0바이트
                     fish · bash · zsh 셋 다 나온다
```

```
25:function __zoxide_hook() {
34:precmd_functions=("${(@)precmd_functions:#__zoxide_hook}")   ← precmd에서 뺀다
37:chpwd_functions+=(__zoxide_hook)                             ← chpwd에만 넣는다
```

**프롬프트마다가 아니라 디렉터리를 옮길 때만 돈다.** 위험 1의 반경을 좁히는
사실이다.

DB가 없을 때 `zoxide query`는 `zoxide: no match found`를 찍고 `exit 1`이다 —
**훅이 아니라 사용자가 부를 때의 이야기**이므로 부팅 화면과 무관하다.

### 6. **fzf 0.60에는 셸 통합이 내장돼 있다** — `.deb`의 예제를 안 넣는 이유

```
fzf --zsh    →  563줄 / 19,545바이트    stderr 0바이트
fzf --bash   →  775줄 / 24,142바이트    stderr 0바이트
fzf --fish   →  187줄 /  6,418바이트    stderr 0바이트
```

`.deb`의 `key-bindings.zsh`와 **다르다** — 내장 쪽이 자동완성까지 함께 낸다.
그래서 `/usr/share/doc/fzf/examples/*`를 initrd에 넣을 이유가 없고, 훅이
`eval "$(fzf --zsh)"`로 **`zoxide`와 대칭**이 된다.

### 7. `fzf --filter`는 비대화형이다 — **게이트가 칠 수 있는 유일한 fzf**

```
printf "alpha\nbravo\ncharlie\n" | fzf --filter=brv   →  bravo      exit 0
printf "alpha\nbravo\n"          | fzf --filter=zzz   →  (없음)      exit 1
```

그리고 **stdin이 tty면 내장 walker로 파일을 찾는다** — 게이트의 셸에는 tty가
있으므로 **파이프도 따옴표도 없이** 칠 수 있다.

```
fzf --filter=descr --walker-root=/usr/share/git-core
  →  /usr/share/git-core/templates/description
```

`sendkey`로 `|`·`"`를 만들지 않아도 된다는 것이 이 실측의 값이다.

**walker root를 `/config`로 잡으면 안 된다** — `tools/check.sh`에는 설정
디스크가 없어서 거기가 **빈 디렉터리**이고, fzf는 아무것도 못 찾아 `exit 1`
이다(실측 12). `/usr/share/git-core/templates`는 UT-M3이 넣은 것이고 **디스크
없이도 항상 거기 있다.** 그리고 판정 글자 `templates/description`은 타이핑한
`descr`과 겹치지 않는다 — **fuzzy 검색어와 판정 글자가 다른 것이 이 프로브의
설계다.**

### 8. `fzf`가 뺏는 키 넷은 **게이트가 치는 키 넷과 안 겹친다**

| | 키 |
|---|---|
| `fzf --zsh`가 바인드 | `^I`(Tab, 자동완성) · `Ctrl+T`(파일) · `Ctrl+R`(히스토리) · `Alt+C`(디렉터리) |
| 게이트가 치는 것 전부 | `ctrl-c` 12회 · `alt-l` 10회 · `ctrl-a` 9회 · `ctrl-l` 3회 |

저장소의 `check.sh` 열한 개와 `gate_lib.sh`를 전부 훑어 셌다. **`tab`·
`ctrl-r`·`ctrl-t`·`alt-c`는 한 번도 안 나온다.** 위험 2가 이것을 지킨다.

그리고 **`Ctrl+R`·`Ctrl+T`·`Alt+C`는 게이트가 치면 안 된다** — 셋 다 화면을
통째로 가져가는 TUI라 `sendkey`로 열면 체인이 타임아웃으로 매달린다
(`less`·`top`·`htop`·`btop`·`ncdu`와 같은 자리, UT design 실측 26).

### 9. zsh는 **`HISTFILE`과 `SAVEHIST` 둘 다** 필요하고, 둘 다 env에서 먹는다

zsh 5.9으로 쟀다.

| 무엇을 줬나 | 파일이 써졌나 |
|---|---|
| 아무것도 (`zsh -f -i`) | **안 써진다.** zsh는 `HISTFILE`이 없으면 히스토리를 저장하지 않는다 |
| `HISTFILE`만 | **안 써진다** — `SAVEHIST`가 0이다 |
| env의 `HISTFILE` + `SAVEHIST=50` | **써진다.** rc 파일 없이 env만으로 됐다 |

```
$ HOME=… HISTFILE=…/H SAVEHIST=50 zsh -f -i -c 'print -s marker_one; fc -W'
$ cat …/H
marker_one
```

`SAVEHIST=77`을 env로 주고 셸 안에서 `echo $SAVEHIST`를 하면 `77`이 나온다 —
**zsh가 env를 파라미터로 들인다는 것을 직접 확인했다.**

### 10. bash는 env의 `HISTFILE`을 먹고 **세션 사이에 append한다**

```
세션 1 뒤:  echo bash_cmd / exit
세션 2 뒤:  echo bash_cmd / exit / echo bash_cmd2 / exit
```

**zsh와 다른 자리다.** zsh는 나갈 때 메모리의 목록으로 파일을 다시 쓰므로
세션이 겹치면 뒤에 나간 쪽이 이긴다(위험 3).

### 11. fish 히스토리는 `XDG_DATA_HOME` 아래로 **자동으로** 간다

fish는 `$XDG_DATA_HOME/fish/fish_history`에 쓴다. **rc 줄도 env 변수도 따로
필요 없다** — 실측 3의 `XDG_DATA_HOME` 하나가 `zoxide`와 함께 이것도 옮긴다.

대가: **fish에는 히스토리 줄 수를 정하는 변수가 없다.** 비목표 4다.

### 12. `/config`는 16MiB이고 파일 다섯이 산다

```
out/config.img   16,777,216바이트   ext2, 라벨 tars-config (init은 tars- 접두사로 찾는다)
  tars.conf  fish.config  bashrc  zshrc  gitconfig
```

게이트 열한 체인 중 **설정 디스크를 붙이는 것은 다섯**이다(`config`·`input`·
`power`·`hangul`·`machine`. SC 실측 4). 나머지 여섯에서 `/config`는 **tmpfs의
빈 디렉터리**이고 쓰기가 된다.

### 13. 씨앗 문법은 주석과 `alias` 둘로 막혀 있다

`init/src/config_test.zig`의 `expectQuietSeed`가 호스트에서 0.1초에 판정한다.

```
FAIL: the zsh seed has a line that is neither a comment nor an alias:
  echo hello
```

**훅 두 줄은 주석도 alias도 아니다.** 이 검사를 어떻게 여는지가 결정 6이고,
**그 규칙의 근거(부팅 때 한 글자라도 찍으면 다섯 체인의 화면 좌표가 밀린다)는
그대로 살아 있다.**

### 14. `environ.zig`에 자리가 넉넉하다

```
MAX_ENTRIES = 16
지금 쓰는 것 = 3   (커널의 HOME · TERM + PID 1이 더한 PATH)
```

그리고 그 파일이 스스로 규칙을 적어 뒀다 — *"PATH를 PID 1이 더하는 이유는
그것이 **자식마다 갈릴 이유가 없는 값**이기 때문이다. TERM은 갈려야 맞아서
terminal 쪽 setenv에 있고, LANG은 갈릴 이유가 없는데도 거기 있다 — 여기가 그
실수를 반복하지 않는 자리다."* **SM이 더하는 넷은 자식마다 갈릴 이유가
없다**(결정 3).

### 15. **`zoxide`는 경로를 정규화한다** — 그것이 게이트의 판정을 진짜로 만든다

```
$ zoxide add /usr/bin/../share/fonts     exit 0
$ zoxide query fonts
/usr/share/fonts                          ← DB가 돌려준 것. 우리가 친 글자가 아니다
$ zoxide add /definitely/not/here
zoxide: not a directory: /definitely/not/here     exit 1
```

**게이트가 이것을 쓴다.** 판정 글자가 타이핑한 명령줄에도 있으면 그 검사는
도구가 죽어도 초록이다(UT design 실측 26의 `bat`이 검사를 못 만든 이유와 같은
문제다). `..`를 지나는 경로를 치면 **DB가 돌려주는 글자가 화면의 다른
어디에도 없다** — `zoxide`가 그 글자를 만든 유일한 주체가 된다.

`query` 출력은 개행 하나로 끝나는 한 줄이다.

## SM-M0이 실행으로 증명한 것

**2026-09-11 실행.** 실측 1~15는 착수 전에 잰 것이고, 여기부터는 코드를
고치고 돌려서 안 것이다. **예상과 달랐던 것을 먼저 적는다.**

### 실측 18 — **zoxide는 마지막 키워드가 경로의 마지막 컴포넌트와 맞아야 한다**

plan이 여기서 틀렸다. 검사 18을 `zoxide add /usr/bin/../share/terminfo/x`
→ `zoxide query terminfo`로 짰는데 첫 실행에서 이렇게 나왔다.

```
root@(none) /t/r (main)# zoxide add /usr/bin/../share/terminfo/x
root@(none) /t/r (main)# zoxide query terminfo
zoxide: no match found
root@(none) /t/r (main) [1]#
```

컨테이너에서 arm64 zoxide 0.9.7로 좁혔다.

```
$ zoxide query --list
/usr/share/terminfo/x           ← 정규화는 맞았다. 실측 15가 옳다
$ zoxide query terminfo         → zoxide: no match found   rc=1
$ zoxide query x                → /usr/share/terminfo/x    rc=0
$ zoxide query terminfo x       → /usr/share/terminfo/x    rc=0
```

**실측 15가 틀린 것이 아니다.** 그때는 `add /usr/bin/../share/fonts` →
`query fonts`였고 마지막 컴포넌트가 마침 `fonts`라 맞았다. **실측 15는
정규화를 이름 붙였고, 그 옆의 불변식은 이름 붙이지 않았다** — plan이 겹침을
피하려고 `fonts`를 `terminfo/x`로 바꿨을 때 이름 없는 쪽이 깨졌다.

**키워드 둘(`terminfo x`)로 갔다.** `x` 하나로도 맞지만, SM-M2가 DB를 부팅
너머로 남기면 `x`로 끝나는 경로가 여럿일 수 있다.

### 실측 19 — **맨 뒤의 음성 확인은 쓰인 날부터 죽어 있었다**

**이 milestone에서 가장 값진 발견이고, 새 도구와 아무 상관이 없다.**

되돌림 2(zoxide 바이너리를 지우고 검사 18의 `..`를 빼서 판정을 가짜로 만든
것)의 예상은 *"검사 18은 초록으로 거짓말하고 맨 뒤의 검사 19가 잡는다"*였다.
**체인 전체가 PASS했다.** 세 번 돌려 세 번 다 그랬다.

첫 의심은 경합이었다. 시리얼 로그를 꺼내 보니 근거가 있었다.

| 로그 줄 | 무엇 |
|---|---|
| 69421 | `/usr/share/terminfo/x`가 처음 화면에 = **타이핑한 줄의 에코** |
| 69813 | `Unknown command`가 처음 화면에 = 셸이 실제로 실패한 결과 |

**392줄이 비어 있다.** positive가 명령의 *출력*이 아니라 *에코*로 만족되면
그 검사는 즉시 돌아오고, 그물은 증거가 프레임에 실리기 전의 로그를 읽기
시작한다.

**그런데 그것이 원인이 아니었다.** 로그에는 `Unknown command`가 든 프레임이
스무 줄이나 있었고 그 줄들은 `terminal: screen>`도 함께 달고 있었다. 검사
19의 조건이 그 스물을 못 본 것이다.

```
$ bash -c 'grep -a "terminal: screen>" serial.log | grep -aq "Unknown command"; echo $?'
0            ← pipefail 없이
$ bash -c 'set -uo pipefail; grep -a ... | grep -aq ...; echo $?'
141          ← 5회 중 5회
```

**`grep -q`가 첫 매치에서 즉시 나가고, 3.7MB를 아직 쏟고 있던 앞단 grep이
SIGPIPE로 죽는다. `set -uo pipefail`이 그 141을 파이프라인의 종료 코드로
올리고 `if`는 그것을 "안 맞았다"로 읽는다** — **매치할수록 초록이 되는
검사**였다.

**이 파일이 자기 함정에 걸렸다.** 같은 스크립트의 검사 1이 파이프라인 대신
변수와 case를 쓰는 이유로 이 함정을 주석에 적어 두었고, `fail()`의 `|| true`
(RM-M2)와 `gate_lib.sh:108`도 같은 것을 경고한다. **아는 것과 안 밟는 것이
다르다.**

`-q`를 빼서 뒤쪽 grep이 입력을 끝까지 읽게 했다. 고친 뒤 되돌림 2는 두 번 다
예상대로 나온다.

```
zoxide learned a directory and gave it back normalized     ← 검사 18의 거짓말
FAIL: the shell said it could not find one of the commands ← 그물이 잡았다
```

**같은 모양이 저장소에 다섯 더 있다**(`rg '\| *grep -[a-z]*q'`).

| 자리 | 모양 | SIGPIPE가 나면 |
|---|---|---|
| `config/check.sh:552` | `if … \| grep -qv …; then fail` | **조용한 초록** — 이 자리와 같은 종류 |
| `config/check.sh:573·576` | `if ! … \| grep -q …` | 거짓 빨강(시끄럽다) |
| `machine/check.sh:226·241·288·354` | `if ! … \| grep -aq …` | 거짓 빨강 |

**SM-M0은 자기 그물만 고쳤다.** 다섯은 이 milestone이 만든 것이 아니고,
고치면 그 체인들을 다시 돌려 판정해야 한다. **`config/check.sh:552`가 다음
후보다** — 유일하게 조용한 쪽이다.

### 실측 20 — 관문 하나를 더했다. **그것은 고친 것이 아니라 보장한 것이다**

검사 19 앞에 `uname -o`를 치고 `GNU/Linux`를 기다리는 관문을 넣었다. 셸은
명령을 하나씩 처리하므로 **관문의 출력이 뜬 순간 그 앞의 모든 명령은 이미
실행되고 그려졌다.**

**정직하게 적는다: 이 관문은 되돌림 2를 고치지 않았다.** SIGPIPE를 고친 뒤
**관문을 꺼도 잡는다**(실측). 안 켜도 잡히는 이유는 아래 grep이 3.7MB를 읽는
**동안에도 로그가 계속 자라서** 에러 프레임이 결국 읽히기 때문 — 즉 "grep이
게스트보다 느리다"는 **우연한 성질**에 기대고 있었다. 관문은 그 우연을
보장으로 바꾼다. 비용은 명령 하나다.

**관문의 판정 글자도 타이핑한 줄과 겹치면 안 된다** — 겹치면 관문 자신이
같은 함정에 빠져 아무것도 안 기다린다. `uname -o`는 여섯 글자를 치고
`GNU/Linux`를 본다.

### 실측 16 — 크기와 `DT_NEEDED`는 **예측이 그대로 맞았다**

```
/usr/local/amd64-sysroot/usr/bin/fzf      4368112   libc.so.6
/usr/local/amd64-sysroot/usr/bin/zoxide   1173976   libgcc_s.so.1 libm.so.6 libc.so.6
libgcc_s.so.1: ok   libm.so.6: ok   libc.so.6: ok
```

실측 2와 바이트까지 같다. **새 라이브러리가 0이라는 예측도 맞았고, 그래서
`copy_lib_deps`를 깨뜨리는 되돌림을 하나 안 했다** — 아무것도 안 죽는
되돌림은 음성 확인이 아니다.

**세 milestone 만에 라이브러리 예측이 두 번 연속 맞았다**(UT-M3이 처음,
SM-M0이 둘째). UT-M1·M2에서는 두 번 다 틀렸다.

### 실측 17 — initrd가 5.5MB 늘었고, tmpfs 벽까지 **165MiB** 남았다

| | 전 | 후 | 증가 | 예측 |
|---|---|---|---|---|
| gzip | 34,869,668 | 37,162,196 | +2,292,528 | "+2MB 안쪽" → **살짝 빗나갔다**(2.19 MiB) |
| 푼 것 | 90,329,088 | 95,871,488 | **+5,542,400** | +5,542,088 → **312바이트 차이** |

312바이트는 cpio 헤더 패딩이다. **푼 크기가 그대로 RAM에 남는다** —
initramfs는 tmpfs이고 크기 기본값이 RAM의 절반이다. `GUEST_MEM=512`이므로
벽은 256MiB, 지금 91.4MiB를 쓰니 **여유가 약 165MiB**다. UT design 실측 34가
이 여유를 안 쟀던 것을 자기비판으로 적어 두었다 — 이제 수가 있다.

gzip 쪽 예측이 빗나간 것은 방향이 안전한 쪽이라 아무것도 안 바꿨다.

### 실측 21 — 되돌림 1·3의 결과

**되돌림 1(`guest_tools.sh`에서 `fzf` 줄을 지운다), 두 번 다 예상대로.**

```
the initrd carries the four bones and all 66 tools the list names   ← 정적 검사는 초록
FAIL: fzf did not filter the git template tree
  … fish: Unknown command: fzf
```

**정적 검사가 tautology라는 것의 실연이다** — 목록에서 줄을 지우면 찾을 것도
함께 없어진다. 목록의 완전함을 증명하는 것은 정적 검사가 아니라 **타이핑**이다.

**되돌림 3(fzf의 walker root를 `/config`로), 두 번 다 예상대로.**

```
FAIL: fzf did not filter the git template tree
=== fzf 명령 뒤 화면 마지막 줄
  terminal: screen> root@(none) ~#
=== 화면에 에러 문구가 있나
  (없음)
```

**"실패했는데 아무 말도 없는" 실패의 모양이다.** fzf는 빈 디렉터리를 훑고
조용히 `exit 1`한다. 실측 7이 글로 경고한 것을 실행으로 봤다. design을 쓰고
self-review에서 이 자리를 잡았던 것이 옳았다.

### 실측 22 — 루트 게이트 **26분 27.84초, 첫 회차에 통과**

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
18 PASS   0 FAIL
```

기준선은 SC-M2의 **25분 58.09초**이고 **+29.75초**다. M0은 부팅을 하나도 안
더했으므로 잡음(±3분) 안이다. 늘어난 것은 `tools` 체인의 명령 넷(fzf 하나 ·
zoxide 둘 · 관문 하나) × 세 회차뿐이다.

| 세는 것 | 수 | 뜻 |
|---|---|---|
| `Unknown command` | **0** | 열한 체인 어디서도 못 찾은 명령이 없다 |
| `error while loading shared libraries` | **0** | 새 라이브러리 0이 게스트에서도 맞았다 |
| `not a directory` | **0** | `zoxide add`가 세 회차 다 성공했다 |
| `Welcome to fish` | **6** | **SC-M0·M1·M2와 같다 — 회귀 없음** |
| `fzf filtered a file tree` | **3** | 새 검사 17 × 세 회차 |
| `zoxide learned a directory` | **3** | 새 검사 18 × 세 회차 |
| `to drain the guest before the net reads` | **3** | 새 관문 × 세 회차 |
| `all 67 tools the list names` | **3** | 65 → **67** |

**plan이 여기서도 작게 틀렸다.** Task 6 Step 3은 `templates/description`과
`/usr/share/terminfo/x`가 각각 **3**일 것으로 적었는데 **둘 다 0이다.** 그
글자는 게스트 **화면**에 있고, 화면 덤프는 체인이 컨테이너 안에 만드는
`$LOG`에 살며 **실패했을 때만** 루트 게이트의 stdout으로 나온다. 초록일 때
루트 로그에 남는 것은 체인이 스스로 찍는 `echo` 줄뿐이다 — 위 표의 아래 넷이
그것이다. **`Welcome to fish`가 6으로 세어지는 것은 그 줄을 시리얼에 직접
찍는 체인이 따로 있기 때문**이고, 그래서 이 둘을 같은 방식으로 셀 수 있다고
믿은 것이 틀렸다.

## 비목표

**1. `git-delta`.** UT 비목표 5가 *"다음에 후보를 찾을 때 이 문단을 먼저 읽을
것"*이라고 적어 둔 것이고, git이 서면서 `libgit2`를 이미 들였으므로 라이브러리
비용이 0에 가깝다(바이너리 6,743KB). 훅도 rc가 아니라 `/config/gitconfig`의
`core.pager`라 **인프라가 이미 서 있다.** 그래도 사용자가 2026-09-11에 이번
범위에서 뺐다. **다음 후보를 찾는 사람은 UT 비목표 5와 이 문단을 함께 읽을
것.**

**2. `Ctrl+R`·`Ctrl+T`·`Alt+C`를 게이트가 치는 것.** 실측 8이 이유다. 셋 다
TUI라 체인이 매달린다. 게이트가 보는 것은 **위젯이 정의됐다는 것**까지다
(결정 8).

**3. `/config`가 찼을 때의 정책.** 상한을 5,000줄로 두는 것까지가 이
서브프로젝트다(결정 4). **디스크가 꽉 찼을 때 무슨 일이 나는지는 안
만든다** — 지금도 만들지 않았고, 히스토리가 그 수를 유의미하게 바꾸지
않는다(250KB / 16MiB = 1.5%).

**4. fish 히스토리의 줄 수 상한.** 실측 11이 이유다. fish에 그 변수가 없다.
`XDG_DATA_HOME` 아래로 옮기는 것까지만 한다.

**5. `zoxide`의 `zi`(대화형 선택).** fzf가 있으므로 **돈다.** 게이트가 안 본다
— 비목표 2와 같은 이유다.

**6. 훅을 사용자가 끌 수 없게 만드는 것.** `shell_config=off`와
`tars.noconfig`가 rc를 막으면 훅도 함께 안 걸린다. **그것이 맞다** — SC가 만든
탈출로가 SM이 더한 것까지 덮어야 한다.

**7. 셸을 셋보다 늘리는 것 · rc를 런타임에 다시 읽는 것.** SC 비목표 7·8이
그대로다.

## 결정

### 결정 1 — 자리를 옮기는 것은 **링크가 아니라 환경 변수**다

SC 결정 1은 `/config`의 rc 파일을 홈에 **링크**로 이었다. **SM은 그 패턴을 안
쓴다.** 실측 4가 이유다 — 댕글링 링크에서 `zoxide`는 `cd`마다 에러 두 줄을
찍고, 없는 경로를 준 환경 변수에서는 `mkdir -p`하고 조용히 성공한다.

| | 링크 (SC 결정 1) | 환경 변수 (SM 결정 1) |
|---|---|---|
| 디스크가 있을 때 | 영속한다 | 영속한다 |
| 디스크가 **없을 때** | **댕글링 → `cd`마다 에러 두 줄** | **tmpfs에 만든다 → 조용하다** |

**같은 저장소에서 두 서브프로젝트가 반대 결정을 하는 것이고, 갈린 것은 취향이
아니라 실측이다.** rc 파일은 **우리가 만드는 것**이라 없으면 만들면 되고
(`seedRcFiles`의 `O_EXCL`), DB는 **도구가 만드는 것**이라 우리가 그 도구의
실패 모드를 물려받는다.

### 결정 2 — `XDG_DATA_HOME` 하나가 둘을 옮긴다

```
XDG_DATA_HOME=/config/xdg
  → /config/xdg/zoxide/db.zo          (실측 3)
  → /config/xdg/fish/fish_history     (실측 11)
```

**안 고른 쪽:** `_ZO_DATA_DIR`로 `zoxide`만 명시적으로 옮기는 것. 그러면
fish 히스토리를 옮길 방법이 따로 없다 — fish에는 경로 변수가 없고
`fish_history`는 **세션 이름**이지 경로가 아니다. `XDG_DATA_HOME`이 유일한
지렛대이고, 그것을 쓰면 `zoxide`가 공짜로 따라온다.

**대가:** XDG를 보는 도구가 앞으로 늘면 그것들도 조용히 `/config`에 쓰기
시작한다. 16MiB짜리 디스크라 그것이 언젠가 문제가 될 수 있다 — 비목표 3이 그
경계를 적어 둔다.

### 결정 3 — 히스토리는 env 넷으로 세우고, `environ.zig`가 그것을 짓는다

씨앗 rc에 히스토리 줄을 **한 줄도 안 넣는다.** 실측 9·10·11이 근거다.

| 항목 | 값 | 누가 먹나 |
|---|---|---|
| `XDG_DATA_HOME` | `/config/xdg` | fish 히스토리 · zoxide DB |
| `HISTFILE` | `/config/<셸>_history` | bash · zsh |
| `HISTSIZE` | `5000` | bash · zsh |
| `SAVEHIST` | `5000` | zsh (**없으면 한 줄도 안 쓴다**) |

`HISTFILE`이 **셸마다 갈리는 이유는 형식이다** — zsh는
`: <ts>:<dur>;<cmd>`, bash는 평문이다. 한 파일에 섞으면 서로의 것을 못 읽는다.
init이 `cfg.shell`을 이미 알고 있으므로 그 자리에서 정한다.

**콘솔 셸과 화면 셸은 같은 파일을 공유한다**(사용자가 2026-09-11에 정했다).
근거는 *"화면에서 친 명령을 콘솔에서도 찾을 수 있어야 한다"*이고, 대가는
위험 3이다.

**안 고른 쪽:** 화면 셸에만 `terminal`이 `setenv`로 다른 `HISTFILE`을 주는 것
(`TERM`·`LANG`이 이미 그 자리에 있다). 겹쳐 쓸 일이 없어지지만 `Ctrl+R`이
자리마다 다른 것을 보여 준다.

### 결정 4 — 상한은 5,000줄

한 줄을 50바이트로 보면 250KB, 16MiB의 **1.5%**다. `zoxide`의 `db.zo`는 고유
디렉터리 수에 비례해 KB 단위다.

**이 수의 근거는 "크면 위험하고 작으면 쓸모없다"의 중간이 아니라 디스크
예산이다** — 히스토리가 `/config`를 채우는 일이 없어야 하고, 5,000줄은 사람이
한 기계에서 몇 달 치는 양이다.

### 결정 5 — 훅은 씨앗 rc에 들어간다. **기본이 켜짐이다**

사용자가 2026-09-11에 정했다("받아서 버린다"). 새 설정 디스크로 처음 뜬
기계에서 `z`와 `Ctrl+R`이 **바로** 돈다.

| 셸 | 훅 두 줄 |
|---|---|
| `zsh` | `eval "$(zoxide init zsh)"` · `eval "$(fzf --zsh)"` |
| `bash` | `eval "$(zoxide init bash)"` · `eval "$(fzf --bash)"` |
| `fish` | `zoxide init fish \| source` · `fzf --fish \| source` |

**안 고른 쪽 둘.** 주석으로 넣고 사용자가 벗기게 하는 것 — `expectQuietSeed`를
한 자도 안 건드리지만 "도구가 있는데 안 돈다"는 상태가 기본이 된다. 씨앗을 안
건드리고 README에만 적는 것 — 가장 짧지만 **게이트가 `z`가 실제로 도는 것을
영영 못 본다.**

### 결정 6 — `expectQuietSeed`는 문법 범주가 아니라 **정확 허용 목록**으로 연다

실측 13의 검사를 *"주석 · `alias` · `eval` 세 범주"*로 넓히면 **`eval` 뒤에
아무 문장이나 올 수 있다** — 씨앗이 부팅 때 찍을 수 있는 것이 무한히 열리고,
그 규칙이 막으려던 것이 정확히 그것이다.

대신 이렇게 연다.

1. `Shell.hookLines()`가 그 셸의 훅 줄들을 돌려준다(결정 5의 표).
2. 씨앗의 비주석·비`alias` 줄은 **그 목록의 한 줄과 글자 그대로 같아야
   한다.**
3. **역방향도 검사한다** — 훅 줄 **전부**가 씨앗에 있어야 한다.

3번이 있는 이유는 1·2번만으로는 **훅을 지우는 것이 통과**하기 때문이다.
그리고 그 검사는 호스트에서 0.1초에 돌아 **부팅 20초를 쓰기 전에** 죽는다.

> **이 검사의 목적은 지금 통과하는 것이 아니라 나중에 막는 것이다.** SC-M1이
> 같은 문장을 적었고, SM은 그 문의 폭을 **두 줄만큼** 넓힌다.

### 결정 7 — fzf 셸 통합은 `.deb`의 예제가 아니라 **바이너리 내장**을 쓴다

실측 6이 근거다. initrd에 파일이 하나도 안 늘고, 훅이 `zoxide`와 대칭이 되고,
`.deb`의 예제와 달리 자동완성까지 함께 온다.

**대가:** `fzf`를 업그레이드하면 훅이 내는 내용이 바뀔 수 있다. 그것을
게이트가 보는 자리가 결정 8의 `whence -w`다.

### 결정 8 — 게이트는 둘로 나눠 본다. `config/check.sh`는 부팅 **일곱**

| 체인 | 디스크 | 무엇을 보나 |
|---|---|---|
| `tools/check.sh` | **없다** | 목록 검사 + **바이너리가 돈다** — `fzf --filter=descr --walker-root=/usr/share/git-core`(실측 7) · `zoxide add /usr/bin/../share/terminfo/x` → `zoxide query terminfo` |
| `config/check.sh` | 있다 | **훅이 걸렸다 + 부팅을 넘어 기억한다** — 부팅 둘을 더한다 |

**부팅 6·7차가 하는 일.**

| 부팅 | 치는 것 | 증명하는 것 |
|---|---|---|
| **6차** | `cd /tmp` → `cd /` → `z tmp` → `pwd` | **한 시퀀스가 셋을 본다** — 훅이 걸렸다 · DB가 쓰였다 · `z`가 돈다 |
| | `whence -w fzf-history-widget` | fzf 통합이 **실제로 위젯을 정의했다**(`Ctrl+R`을 안 치고 보는 법. 비목표 2) |
| **7차** | 아무것도 안 침 → `z tmp` → `pwd` · `history` | **재부팅을 넘어 기억한다** |

**6차가 7차를 진짜로 만든다** — 6차가 DB에 무언가를 넣었다는 것이 보였기
때문에 7차의 `z tmp`가 "이전 부팅에서 배운 것"을 증명한다. SC-M1의 3차가
2차에 기대고 SC-M2의 5차가 4차에 기댄 것과 같은 구조다.

**치는 명령이 전부 소문자다** — `sendkey`에 대문자가 없다(UT-M3). 그래서
`whence -w`이고 `WHENCE`가 아니다.

### 결정 9 — 조건이 없다. 설정 디스크가 없어도 같은 값을 준다

SC-M2의 `rescue_flag`는 `storage_mounted`를 봐야 했다. **SM의 env 넷은 안
본다.** 실측 4가 그래도 되게 만든다 — 디스크가 없으면 `/config`는 tmpfs의 빈
디렉터리이고, 도구 둘은 거기에 조용히 쓴다. 사라지지만 **에러가 안 나고, 에러가
안 나는 것이 화면 좌표를 지키는 것이다.**

**`/config/xdg`는 init이 만든다** — 디스크를 붙였을 때 `seedRcFiles` 옆에서
`mkdir` 한 번이다. fish와 zoxide가 스스로 만들기도 하지만(실측 4), **`HISTFILE`의
부모는 아무도 안 만든다.** 그래서 히스토리 파일을 `/config/history/` 아래가
아니라 **`/config` 바로 아래**(`/config/zsh_history`)에 둔다 — 디렉터리를 만들
필요가 없고, `tars.conf`·`gitconfig`와 같은 평면이다.

## Milestone 셋

| | 무엇 | 검증 |
|---|---|---|
| **SM-M0** | 도구 둘이 선다. **훅 없음** | `tools/check.sh`가 목록을 보고 **둘을 타이핑한다** — `fzf --filter`가 파일을 찾고 `zoxide query`가 방금 넣은 것을 돌려준다 |
| **SM-M1** | 훅이 걸린다(결정 5·6·7) | 호스트 검사가 허용 목록 **양방향**을 본다 · `config/check.sh` 6차 부팅에서 **`z tmp`가 돈다** |
| **SM-M2** | 배운 것이 남는다(결정 2·3·4·9) | `config/check.sh` 7차 부팅이 **이전 부팅에서 배운 디렉터리와 명령을 찾는다** |

**M1의 6차 부팅이 M2 없이도 도는 이유**를 적어 둔다 — 결정 2의
`XDG_DATA_HOME`이 없으면 `zoxide`는 `$HOME/.local/share/zoxide/db.zo`로
떨어지고, 홈은 tmpfs지만 **한 부팅 안에서는 멀쩡히 쓰고 읽는다**(실측 3).
그래서 M1은 *"훅이 걸렸다"*를, M2는 *"부팅을 넘어 남는다"*를 각각 따로
증명한다. **6차의 판정 글자는 M2에서도 안 바뀐다** — 바뀌는 것은 그 DB가 어느
파일시스템에 있는지뿐이다.

**M0이 훅 없이 한 단계인 이유**는 UT가 세 번 배운 것이다 — *"검사를 넣었으면
그것이 죽는 경우를 직접 만들어 봐야 한다. 다른 검사가 먼저 죽으면 그 검사는
아직 아무것도 증명하지 않았다."* 훅과 바이너리를 한 milestone에 넣으면
`zoxide query`가 실패했을 때 **바이너리가 안 돈 것**과 **훅이 안 걸린 것**이
안 갈린다.

`CLAUDE.md`대로 **각 milestone의 plan은 그 시점에 새로 쓴다.**

## 위험

### 위험 1 — 훅이 부팅할 때 한 글자라도 찍으면 다섯 체인의 화면이 밀린다

실측 13이 적은 규칙의 대상이 이번에는 **우리가 넣는 훅**이다. 실측 5·6이
stderr 0바이트를 쟀고 `zoxide`의 훅이 `chpwd`에만 걸린다는 것도 쟀다. **그래도
게이트의 첫 회차가 이것의 진짜 검사다** — 설정 디스크를 붙이는 다섯 체인 중
셋이 화면의 **셀 좌표**로 판정한다.

**부분적 처방이 이미 있다:** 실패가 "화면이 밀렸다"로 나타나면 훅을 씨앗에서
빼고 다시 돌려 **훅이 원인인지**를 한 번에 가릴 수 있다(결정 6의 역방향 검사가
그 상태를 호스트에서 먼저 잡으므로, 가릴 때는 그 검사도 함께 끈다).

### 위험 2 — `fzf`가 Tab을 자동완성 위젯으로 뺏는다

실측 8이 "지금은 안 겹친다"를 쟀다. **앞으로 `tab`을 치려는 사람이 이 줄을 볼
자리다** — 게이트가 Tab을 치면 그 순간부터 fzf가 그 키를 받는다.

### 위험 3 — zsh 두 세션이 같은 `HISTFILE`을 겹쳐 쓴다

실측 10이 근거다. bash는 append하고 zsh는 나갈 때 파일을 다시 쓴다. 콘솔 셸과
화면 셸이 동시에 살아 있고 둘 다 zsh면, 뒤에 나간 쪽의 목록이 이긴다.

**고치려면 `setopt APPEND_HISTORY`가 필요하고 그것은 결정 6의 허용 목록을 세
줄로 넓히는 일이다.** 이번에는 **알고 둔다** — 위험을 아는 것과 고치는 것이
다르고, 이 서브프로젝트가 먼저 증명할 것은 "남는다"다.

### 위험 4 — initrd가 5.54MB 커진다

UT-M2가 배운 것이 여기 걸린다: initramfs는 tmpfs라 **푼 크기가 통째로 RAM에
남는다.** 그때 84MB에서 기본 128MiB가 panic이었고 `gate_lib.sh`의
`GUEST_MEM=512`가 그 처방이었다 — **그 여유가 이미 서 있다.** M0에서 gzip 뒤
증가분과 프롬프트까지의 시간을 잰다.

### 위험 5 — 게이트가 부팅 둘만큼 늘어난다

기준선은 SC-M2의 **열한 체인 3/3 = 25분 58.09초**다. `config/check.sh`가
부팅 다섯에서 일곱이 되고, 6·7차는 화면을 폴링으로 기다릴 수 있어(찾을 글자가
**있어야 할 것**이다) SC-M2의 4·5차처럼 8초를 고정으로 쓰지 않는다. **+40초
안쪽으로 본다.**

## 참고

- SC design: `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
  (비목표 1·2가 이 문서의 입구다)
- UT design: `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
  (비목표 5·6 · 도구 조달 절차 · 실측 26)
- 기억: `docs/decisions/project_shell_config.md` ·
  `docs/decisions/project_userland_tools.md` ·
  `docs/decisions/project_guest_environment.md`
