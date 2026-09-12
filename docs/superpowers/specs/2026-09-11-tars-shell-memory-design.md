# TARS Shell Memory — Design

Date: 2026-09-11
Status: 완료 — SM-M0(2026-09-11) · SM-M1(2026-09-12) · SM-M2(2026-09-12).
서브프로젝트가 닫혔다. 기계가 배운 것 둘이 전원을 끊어도 남고,
`config/check.sh`의 8차 부팅이 그것을 본다.
Shell Config(SC-M0~M2)가 2026-09-11에 닫히면서
훅을 걸 자리가 생겼고, 이 서브프로젝트가 그 자리에 처음으로 무언가를
건다. `zoxide`와 `fzf`를 게스트에 세우고, 셸 셋의 씨앗 rc가 그 둘의 훅을
기본으로 담고, 기계가 사용자에게서 배운 것 둘(자주 간 디렉터리 · 쳤던
명령)을 `/config`에 남겨 부팅을 넘어 기억하게 한다.

## 한 줄 요약

UT는 도구를 세웠고, SC는 그 도구에 훅을 걸 자리를 만들었다. SM은 그 자리에
처음으로 훅을 걸고, 기계가 부팅을 넘어 기억하게 한다.

이 셋이 한 서브프로젝트인 이유는 "도구 두 개 넣기"가 아니다.

| 기계가 배운 것 | 어디에 남나 | 사용자가 뒤지는 법 |
|---|---|---|
| 어느 디렉터리에 자주 갔나 | `zoxide`의 `db.zo` | `z <조각>` |
| 어떤 명령을 쳤나 | 셸 히스토리 | `Ctrl+R` (fzf) |

둘 다 "학습한 상태를 `/config`에 남기고 rc의 훅으로 셸에 잇는다"는 한
종류의 일이다. 그래서 씨앗 문법을 넓히는 공사도 한 번에 끝난다.

## 왜 지금인가

UT 비목표 6이 이 문단의 앞줄이다.

> 6. `zoxide`·`fzf`. 실측 10이 이유다. 셸이 무조건 no-config로 뜨는 한
> 훅을 걸 자리가 없다. 셸 설정을 다루는 서브프로젝트가 생기면 그때 함께
> 온다.

그 서브프로젝트가 SC였고, 끝났다. SC 비목표 1이 넘긴 것을 그대로 받는다.

> 1. `zoxide`·`fzf`를 넣는 것. 훅을 걸 자리가 생기면 사용자가 rc에 쓰면
> 되지만, 도구 조달은 UT의 일이다 — `.deb` 목록 · 라이브러리 closure ·
> `guest_tools.sh` · `tools/check.sh`의 검사를 다시 여는 일이고 UT가 세운
> 절차가 그대로 적용된다.

그리고 범위에 셸 히스토리 영속(SC 비목표 2)을 함께 넣는다 — 사용자가
2026-09-11에 정했다. 근거는 실측 8에 있다: `fzf`의 `Ctrl+R`이 뒤지는 것이
셸 히스토리이고, 그 히스토리는 지금 부팅마다 사라진다. 도구만 넣으면
`Ctrl+R`은 반쪽이다.

`git-delta`는 안 넣는다 — UT 비목표 5가 *"다음에 후보를 찾을 때 이 문단을
먼저 읽을 것"*이라고 적어 둔 것이고 훅 자리(`/config/gitconfig`의
`core.pager`)도 이미 서 있지만, 사용자가 이번 범위에서 뺐다. 비목표 1이다.

## 착수 전에 실측한 것 — 다시 조사하지 말 것

측정 환경을 먼저 적는다. 크기와 `DT_NEEDED`는 amd64 `.deb`로 쟀다
(게스트가 amd64다). 동작(DB 경로 · 히스토리 · 훅의 출력)은 devcontainer가
arm64라 arm64 바이너리로 쟀다 — 같은 소스의 같은 버전이고 경로 규칙과
환경 변수 처리는 아키텍처에 안 갈리는 자리다. 그래도 게이트가 보는 것은
amd64이고, 그것이 M0의 첫 회차가 하는 일이다.

### 1. `.deb` 둘은 바이너리 하나씩이고, 하나는 예제를 데려온다

| 패키지 | 버전 | `.deb` | `Depends` |
|---|---|---|---|
| `zoxide` | 0.9.7-1+b1 | 424,452바이트 | `libc6` · `libgcc-s1` |
| `fzf` | 0.60.3-1+b2 | 1,473,536바이트 | `libc6` |

`fzf`의 `.deb` 안에 우리가 안 넣을 것이 함께 있다.

```
usr/bin/fzf-tmux                                    7,393    tmux가 없다
usr/share/doc/fzf/examples/key-bindings.{bash,zsh,fish}     실측 6이 이유다
usr/share/doc/fzf/examples/completion.{bash,zsh}            같은 이유
usr/share/fish/vendor_functions.d/fzf_key_bindings.fish     같은 이유
```

### 2. amd64 크기와 `DT_NEEDED` — 새 라이브러리가 0이다

```
/usr/bin/zoxide   1,173,976바이트   libgcc_s.so.1 libm.so.6 libc.so.6
/usr/bin/fzf      4,368,112바이트   libc.so.6
```

합 5,542,088바이트이고 새 라이브러리는 하나도 없다. `libgcc-s1:amd64`는
`devcontainer/Dockerfile:206`에 이미 있고(`btop`의 `libstdc++`가 데려온
것이다), `libm.so.6`은 `libc6`이 담고 있으며 `vim.tiny`가 이미 쓴다.
`copy_lib_deps`가 재귀로 따라가므로 셋 다 이미 initrd에 있다.

> UT가 세 번 배운 것을 이번에는 착수 전에 했다 — M1·M2는 바이너리의
> `DT_NEEDED`만 보고 `.so`의 것을 안 봐서 두 번 틀렸다. 이번 둘은 사슬이
> 한 겹이라 그 함정이 없다.

### 3. `zoxide`는 `XDG_DATA_HOME`을 본다

```
HOME=… XDG_DATA_HOME=/tmp/p/xdg zoxide add /tmp
  → /tmp/p/xdg/zoxide/db.zo
```

`_ZO_DATA_DIR`도 있지만 필요가 없다. `XDG_DATA_HOME` 하나가 `zoxide`와
fish 히스토리(실측 11)를 동시에 옮긴다.

기본값은 `$HOME/.local/share/zoxide/db.zo`이고 홈(`/`)은 tmpfs다 — 아무것도
안 하면 DB가 부팅마다 사라진다.

### 4. 없는 경로는 만들고, 댕글링 링크는 에러다 — 결정 1의 근거

| 무엇을 했나 | 결과 |
|---|---|
| `_ZO_DATA_DIR`을 없는 깊은 경로로 두고 `zoxide add /tmp` | `exit 0`. `/tmp/p/made/up/deep/db.zo`를 만들었다 |
| DB 자리를 댕글링 심볼릭 링크로 두고 `zoxide add /tmp` | `exit 1` |

```
zoxide: unable to create data directory: /tmp/zp/h2/.local/share/zoxide

Caused by:
    File exists (os error 17)
```

이 두 줄이 SC 결정 1의 링크 패턴을 여기서 기각한다. 게이트 열한 체인 중
설정 디스크가 없는 것이 여섯이고(실측 12), 그 기계에서 `/config/…`를 가리키는
링크는 댕글링이다. `zoxide`의 훅은 `chpwd_functions`에 걸려 있어(실측 5)
`cd` 한 번마다 위 두 줄이 화면에 찍힌다 — 그것이 곧 화면 좌표다.

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

프롬프트마다가 아니라 디렉터리를 옮길 때만 돈다. 위험 1의 반경을 좁히는
사실이다.

DB가 없을 때 `zoxide query`는 `zoxide: no match found`를 찍고 `exit 1`이다 —
훅이 아니라 사용자가 부를 때의 이야기이므로 부팅 화면과 무관하다.

### 6. fzf 0.60에는 셸 통합이 내장돼 있다 — `.deb`의 예제를 안 넣는 이유

```
fzf --zsh    →  563줄 / 19,545바이트    stderr 0바이트
fzf --bash   →  775줄 / 24,142바이트    stderr 0바이트
fzf --fish   →  187줄 /  6,418바이트    stderr 0바이트
```

`.deb`의 `key-bindings.zsh`와 다르다 — 내장 쪽이 자동완성까지 함께 낸다.
그래서 `/usr/share/doc/fzf/examples/*`를 initrd에 넣을 이유가 없고, 훅이
`eval "$(fzf --zsh)"`로 `zoxide`와 대칭이 된다.

### 7. `fzf --filter`는 비대화형이다 — 게이트가 칠 수 있는 유일한 fzf

```
printf "alpha\nbravo\ncharlie\n" | fzf --filter=brv   →  bravo      exit 0
printf "alpha\nbravo\n"          | fzf --filter=zzz   →  (없음)      exit 1
```

그리고 stdin이 tty면 내장 walker로 파일을 찾는다 — 게이트의 셸에는 tty가
있으므로 파이프도 따옴표도 없이 칠 수 있다.

```
fzf --filter=descr --walker-root=/usr/share/git-core
  →  /usr/share/git-core/templates/description
```

`sendkey`로 `|`·`"`를 만들지 않아도 된다는 것이 이 실측의 값이다.

walker root를 `/config`로 잡으면 안 된다 — `tools/check.sh`에는 설정
디스크가 없어서 거기가 빈 디렉터리이고, fzf는 아무것도 못 찾아 `exit 1`
이다(실측 12). `/usr/share/git-core/templates`는 UT-M3이 넣은 것이고 디스크
없이도 항상 거기 있다. 그리고 판정 글자 `templates/description`은 타이핑한
`descr`과 겹치지 않는다 — fuzzy 검색어와 판정 글자가 다른 것이 이 프로브의
설계다.

### 8. `fzf`가 뺏는 키 넷은 게이트가 치는 키 넷과 안 겹친다

| | 키 |
|---|---|
| `fzf --zsh`가 바인드 | `^I`(Tab, 자동완성) · `Ctrl+T`(파일) · `Ctrl+R`(히스토리) · `Alt+C`(디렉터리) |
| 게이트가 치는 것 전부 | `ctrl-c` 12회 · `alt-l` 10회 · `ctrl-a` 9회 · `ctrl-l` 3회 |

저장소의 `check.sh` 열한 개와 `gate_lib.sh`를 전부 훑어 셌다. `tab`·
`ctrl-r`·`ctrl-t`·`alt-c`는 한 번도 안 나온다. 위험 2가 이것을 지킨다.

그리고 `Ctrl+R`·`Ctrl+T`·`Alt+C`는 게이트가 치면 안 된다 — 셋 다 화면을
통째로 가져가는 TUI라 `sendkey`로 열면 체인이 타임아웃으로 매달린다
(`less`·`top`·`htop`·`btop`·`ncdu`와 같은 자리, UT design 실측 26).

### 9. zsh는 `HISTFILE`과 `SAVEHIST` 둘 다 필요하고, 둘 다 env에서 먹는다

zsh 5.9으로 쟀다.

| 무엇을 줬나 | 파일이 써졌나 |
|---|---|
| 아무것도 (`zsh -f -i`) | 안 써진다. zsh는 `HISTFILE`이 없으면 히스토리를 저장하지 않는다 |
| `HISTFILE`만 | 안 써진다 — `SAVEHIST`가 0이다 |
| env의 `HISTFILE` + `SAVEHIST=50` | 써진다. rc 파일 없이 env만으로 됐다 |

```
$ HOME=… HISTFILE=…/H SAVEHIST=50 zsh -f -i -c 'print -s marker_one; fc -W'
$ cat …/H
marker_one
```

`SAVEHIST=77`을 env로 주고 셸 안에서 `echo $SAVEHIST`를 하면 `77`이 나온다 —
zsh가 env를 파라미터로 들인다는 것을 직접 확인했다.

### 10. bash는 env의 `HISTFILE`을 먹고 세션 사이에 append한다

```
세션 1 뒤:  echo bash_cmd / exit
세션 2 뒤:  echo bash_cmd / exit / echo bash_cmd2 / exit
```

zsh와 다른 자리다. zsh는 나갈 때 메모리의 목록으로 파일을 다시 쓰므로
세션이 겹치면 뒤에 나간 쪽이 이긴다(위험 3).

> ⚠ 정정(2026-09-12, SD design 실측 1) — 위 마지막 문단이 틀렸다. zsh도
> append한다. `APPEND_HISTORY`가 zsh의 기본값이고, 두 세션으로 재 보면
> 나중에 나간 쪽이 앞의 줄을 안 지운다. 그리고 이 실측의 실험 설계도
> 약하다 — 세션을 순차로 돌리면 뒤 세션이 시작할 때 앞 세션의 파일을 읽기
> 때문에, append와 덮어쓰기가 구별되지 않는다. 동시 세션으로 재야 한다.
> 본문은 `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`.

### 11. fish 히스토리는 `XDG_DATA_HOME` 아래로 자동으로 간다

fish는 `$XDG_DATA_HOME/fish/fish_history`에 쓴다. rc 줄도 env 변수도 따로
필요 없다 — 실측 3의 `XDG_DATA_HOME` 하나가 `zoxide`와 함께 이것도 옮긴다.

대가: fish에는 히스토리 줄 수를 정하는 변수가 없다. 비목표 4다.

### 12. `/config`는 16MiB이고 파일 다섯이 산다

```
out/config.img   16,777,216바이트   ext2, 라벨 tars-config (init은 tars- 접두사로 찾는다)
  tars.conf  fish.config  bashrc  zshrc  gitconfig
```

게이트 열한 체인 중 설정 디스크를 붙이는 것은 다섯이다(`config`·`input`·
`power`·`hangul`·`machine`. SC 실측 4). 나머지 여섯에서 `/config`는 tmpfs의
빈 디렉터리이고 쓰기가 된다.

### 13. 씨앗 문법은 주석과 `alias` 둘로 막혀 있다

`init/src/config_test.zig`의 `expectQuietSeed`가 호스트에서 0.1초에 판정한다.

```
FAIL: the zsh seed has a line that is neither a comment nor an alias:
  echo hello
```

훅 두 줄은 주석도 alias도 아니다. 이 검사를 어떻게 여는지가 결정 6이고,
그 규칙의 근거(부팅 때 한 글자라도 찍으면 다섯 체인의 화면 좌표가 밀린다)는
그대로 살아 있다.

### 14. `environ.zig`에 자리가 넉넉하다

```
MAX_ENTRIES = 16
지금 쓰는 것 = 3   (커널의 HOME · TERM + PID 1이 더한 PATH)
```

그리고 그 파일이 스스로 규칙을 적어 뒀다 — *"PATH를 PID 1이 더하는 이유는
그것이 자식마다 갈릴 이유가 없는 값이기 때문이다. TERM은 갈려야 맞아서
terminal 쪽 setenv에 있고, LANG은 갈릴 이유가 없는데도 거기 있다 — 여기가 그
실수를 반복하지 않는 자리다."* SM이 더하는 넷은 자식마다 갈릴 이유가
없다(결정 3).

### 15. `zoxide`는 경로를 정규화한다 — 그것이 게이트의 판정을 진짜로 만든다

```
$ zoxide add /usr/bin/../share/fonts     exit 0
$ zoxide query fonts
/usr/share/fonts                          ← DB가 돌려준 것. 우리가 친 글자가 아니다
$ zoxide add /definitely/not/here
zoxide: not a directory: /definitely/not/here     exit 1
```

게이트가 이것을 쓴다. 판정 글자가 타이핑한 명령줄에도 있으면 그 검사는
도구가 죽어도 초록이다(UT design 실측 26의 `bat`이 검사를 못 만든 이유와 같은
문제다). `..`를 지나는 경로를 치면 DB가 돌려주는 글자가 화면의 다른
어디에도 없다 — `zoxide`가 그 글자를 만든 유일한 주체가 된다.

`query` 출력은 개행 하나로 끝나는 한 줄이다.

## SM-M0이 실행으로 증명한 것

2026-09-11 실행. 실측 1~15는 착수 전에 잰 것이고, 여기부터는 코드를
고치고 돌려서 안 것이다. 예상과 달랐던 것을 먼저 적는다.

### 실측 18 — zoxide는 마지막 키워드가 경로의 마지막 컴포넌트와 맞아야 한다

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

실측 15가 틀린 것이 아니다. 그때는 `add /usr/bin/../share/fonts` →
`query fonts`였고 마지막 컴포넌트가 마침 `fonts`라 맞았다. 실측 15는
정규화를 이름 붙였고, 그 옆의 불변식은 이름 붙이지 않았다 — plan이 겹침을
피하려고 `fonts`를 `terminfo/x`로 바꿨을 때 이름 없는 쪽이 깨졌다.

키워드 둘(`terminfo x`)로 갔다. `x` 하나로도 맞지만, SM-M2가 DB를 부팅
너머로 남기면 `x`로 끝나는 경로가 여럿일 수 있다.

### 실측 19 — 맨 뒤의 음성 확인은 쓰인 날부터 죽어 있었다

이 milestone에서 가장 값진 발견이고, 새 도구와 아무 상관이 없다.

되돌림 2(zoxide 바이너리를 지우고 검사 18의 `..`를 빼서 판정을 가짜로 만든
것)의 예상은 *"검사 18은 초록으로 거짓말하고 맨 뒤의 검사 19가 잡는다"*였다.
체인 전체가 PASS했다. 세 번 돌려 세 번 다 그랬다.

첫 의심은 경합이었다. 시리얼 로그를 꺼내 보니 근거가 있었다.

| 로그 줄 | 무엇 |
|---|---|
| 69421 | `/usr/share/terminfo/x`가 처음 화면에 = 타이핑한 줄의 에코 |
| 69813 | `Unknown command`가 처음 화면에 = 셸이 실제로 실패한 결과 |

392줄이 비어 있다. positive가 명령의 *출력*이 아니라 *에코*로 만족되면
그 검사는 즉시 돌아오고, 그물은 증거가 프레임에 실리기 전의 로그를 읽기
시작한다.

그런데 그것이 원인이 아니었다. 로그에는 `Unknown command`가 든 프레임이
스무 줄이나 있었고 그 줄들은 `terminal: screen>`도 함께 달고 있었다. 검사
19의 조건이 그 스물을 못 본 것이다.

```
$ bash -c 'grep -a "terminal: screen>" serial.log | grep -aq "Unknown command"; echo $?'
0            ← pipefail 없이
$ bash -c 'set -uo pipefail; grep -a ... | grep -aq ...; echo $?'
141          ← 5회 중 5회
```

`grep -q`가 첫 매치에서 즉시 나가고, 3.7MB를 아직 쏟고 있던 앞단 grep이
SIGPIPE로 죽는다. `set -uo pipefail`이 그 141을 파이프라인의 종료 코드로
올리고 `if`는 그것을 "안 맞았다"로 읽는다 — 매치할수록 초록이 되는
검사였다.

이 파일이 자기 함정에 걸렸다. 같은 스크립트의 검사 1이 파이프라인 대신
변수와 case를 쓰는 이유로 이 함정을 주석에 적어 두었고, `fail()`의 `|| true`
(RM-M2)와 `gate_lib.sh:108`도 같은 것을 경고한다. 아는 것과 안 밟는 것이
다르다.

`-q`를 빼서 뒤쪽 grep이 입력을 끝까지 읽게 했다. 고친 뒤 되돌림 2는 두 번 다
예상대로 나온다.

```
zoxide learned a directory and gave it back normalized     ← 검사 18의 거짓말
FAIL: the shell said it could not find one of the commands ← 그물이 잡았다
```

같은 모양이 저장소에 다섯 더 있다(`rg '\| *grep -[a-z]*q'`).

| 자리 | 모양 | SIGPIPE가 나면 |
|---|---|---|
| `config/check.sh:552` | `if … \| grep -qv …; then fail` | 조용한 초록 — 이 자리와 같은 종류 |
| `config/check.sh:573·576` | `if ! … \| grep -q …` | 거짓 빨강(시끄럽다) |
| `machine/check.sh:226·241·288·354` | `if ! … \| grep -aq …` | 거짓 빨강 |

SM-M0은 자기 그물만 고쳤다. 다섯은 이 milestone이 만든 것이 아니고,
고치면 그 체인들을 다시 돌려 판정해야 한다. `config/check.sh:552`가 다음
후보다 — 유일하게 조용한 쪽이다.

### 실측 20 — 관문 하나를 더했다. 그것은 고친 것이 아니라 보장한 것이다

검사 19 앞에 `uname -o`를 치고 `GNU/Linux`를 기다리는 관문을 넣었다. 셸은
명령을 하나씩 처리하므로 관문의 출력이 뜬 순간 그 앞의 모든 명령은 이미
실행되고 그려졌다.

정직하게 적는다: 이 관문은 되돌림 2를 고치지 않았다. SIGPIPE를 고친 뒤
관문을 꺼도 잡는다(실측). 안 켜도 잡히는 이유는 아래 grep이 3.7MB를 읽는
동안에도 로그가 계속 자라서 에러 프레임이 결국 읽히기 때문 — 즉 "grep이
게스트보다 느리다"는 우연한 성질에 기대고 있었다. 관문은 그 우연을
보장으로 바꾼다. 비용은 명령 하나다.

관문의 판정 글자도 타이핑한 줄과 겹치면 안 된다 — 겹치면 관문 자신이
같은 함정에 빠져 아무것도 안 기다린다. `uname -o`는 여섯 글자를 치고
`GNU/Linux`를 본다.

### 실측 16 — 크기와 `DT_NEEDED`는 예측이 그대로 맞았다

```
/usr/local/amd64-sysroot/usr/bin/fzf      4368112   libc.so.6
/usr/local/amd64-sysroot/usr/bin/zoxide   1173976   libgcc_s.so.1 libm.so.6 libc.so.6
libgcc_s.so.1: ok   libm.so.6: ok   libc.so.6: ok
```

실측 2와 바이트까지 같다. 새 라이브러리가 0이라는 예측도 맞았고, 그래서
`copy_lib_deps`를 깨뜨리는 되돌림을 하나 안 했다 — 아무것도 안 죽는
되돌림은 음성 확인이 아니다.

세 milestone 만에 라이브러리 예측이 두 번 연속 맞았다(UT-M3이 처음,
SM-M0이 둘째). UT-M1·M2에서는 두 번 다 틀렸다.

### 실측 17 — initrd가 5.5MB 늘었고, tmpfs 벽까지 165MiB 남았다

| | 전 | 후 | 증가 | 예측 |
|---|---|---|---|---|
| gzip | 34,869,668 | 37,162,196 | +2,292,528 | "+2MB 안쪽" → 살짝 빗나갔다(2.19 MiB) |
| 푼 것 | 90,329,088 | 95,871,488 | +5,542,400 | +5,542,088 → 312바이트 차이 |

312바이트는 cpio 헤더 패딩이다. 푼 크기가 그대로 RAM에 남는다 —
initramfs는 tmpfs이고 크기 기본값이 RAM의 절반이다. `GUEST_MEM=512`이므로
벽은 256MiB, 지금 91.4MiB를 쓰니 여유가 약 165MiB다. UT design 실측 34가
이 여유를 안 쟀던 것을 자기비판으로 적어 두었다 — 이제 수가 있다.

gzip 쪽 예측이 빗나간 것은 방향이 안전한 쪽이라 아무것도 안 바꿨다.

### 실측 21 — 되돌림 1·3의 결과

되돌림 1(`guest_tools.sh`에서 `fzf` 줄을 지운다), 두 번 다 예상대로.

```
the initrd carries the four bones and all 66 tools the list names   ← 정적 검사는 초록
FAIL: fzf did not filter the git template tree
  … fish: Unknown command: fzf
```

정적 검사가 tautology라는 것의 실연이다 — 목록에서 줄을 지우면 찾을 것도
함께 없어진다. 목록의 완전함을 증명하는 것은 정적 검사가 아니라 타이핑이다.

되돌림 3(fzf의 walker root를 `/config`로), 두 번 다 예상대로.

```
FAIL: fzf did not filter the git template tree
=== fzf 명령 뒤 화면 마지막 줄
  terminal: screen> root@(none) ~#
=== 화면에 에러 문구가 있나
  (없음)
```

"실패했는데 아무 말도 없는" 실패의 모양이다. fzf는 빈 디렉터리를 훑고
조용히 `exit 1`한다. 실측 7이 글로 경고한 것을 실행으로 봤다. design을 쓰고
self-review에서 이 자리를 잡았던 것이 옳았다.

### 실측 22 — 루트 게이트 26분 27.84초, 첫 회차에 통과

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
18 PASS   0 FAIL
```

기준선은 SC-M2의 25분 58.09초이고 +29.75초다. M0은 부팅을 하나도 안
더했으므로 잡음(±3분) 안이다. 늘어난 것은 `tools` 체인의 명령 넷(fzf 하나 ·
zoxide 둘 · 관문 하나) × 세 회차뿐이다.

| 세는 것 | 수 | 뜻 |
|---|---|---|
| `Unknown command` | 0 | 열한 체인 어디서도 못 찾은 명령이 없다 |
| `error while loading shared libraries` | 0 | 새 라이브러리 0이 게스트에서도 맞았다 |
| `not a directory` | 0 | `zoxide add`가 세 회차 다 성공했다 |
| `Welcome to fish` | 6 | SC-M0·M1·M2와 같다 — 회귀 없음 |
| `fzf filtered a file tree` | 3 | 새 검사 17 × 세 회차 |
| `zoxide learned a directory` | 3 | 새 검사 18 × 세 회차 |
| `to drain the guest before the net reads` | 3 | 새 관문 × 세 회차 |
| `all 67 tools the list names` | 3 | 65 → 67 |

plan이 여기서도 작게 틀렸다. Task 6 Step 3은 `templates/description`과
`/usr/share/terminfo/x`가 각각 3일 것으로 적었는데 둘 다 0이다. 그
글자는 게스트 화면에 있고, 화면 덤프는 체인이 컨테이너 안에 만드는
`$LOG`에 살며 실패했을 때만 루트 게이트의 stdout으로 나온다. 초록일 때
루트 로그에 남는 것은 체인이 스스로 찍는 `echo` 줄뿐이다 — 위 표의 아래 넷이
그것이다. `Welcome to fish`가 6으로 세어지는 것은 그 줄을 시리얼에 직접
찍는 체인이 따로 있기 때문이고, 그래서 이 둘을 같은 방식으로 셀 수 있다고
믿은 것이 틀렸다.

## SM-M1이 실행으로 증명한 것

2026-09-12 실행. 실측 23~29는 코드를 고치기 전에 컨테이너에서 잰
것이고(그 넷이 설계를 바꿨다), 30부터는 고치고 돌려서 안 것이다.

측정 환경: devcontainer가 arm64라 arm64 바이너리로 쟀다 — zsh 5.9 ·
fish 4.0.2 · zoxide 0.9.7 · fzf 0.60, 게스트의 amd64와 같은 Debian trixie
스냅샷이다. devcontainer에는 이 넷이 없어서(amd64 sysroot의 것만 있다)
버릴 컨테이너에 arm64로 따로 깔았다.

```bash
docker run -d --name tars-measure tars-devcontainer sleep 3600
docker exec tars-measure bash -c 'apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fish zoxide fzf'
```

그리고 `script -qec`로 pty를 줬다 — 게스트의 셸은 PTY 위에 살고, 훅이
찍는지 안 찍는지는 그 차이에 갈릴 수 있는 종류의 질문이다.

### 실측 23 — 훅 두 줄은 셋 다 0바이트다

| 셸 | rc | stdout | stderr |
|---|---|---|---|
| zsh | `command -v … >/dev/null && eval "$(…)"` | 0 | 0 |
| bash | 같은 모양 | 0 | 0 |
| fish | `type -q … && … \| source` | 0 | 0 |

게스트의 TERM 둘로 다시 쟀다 — 화면 셸은 `xterm-256color`, 시리얼 콘솔
셸은 `linux`다(`environ.zig`). `dumb`까지 셋 다 0이다.

그리고 씨앗의 실제 바이트로 한 번 더 쟀다. 주석·alias·훅이 든 1,382바이트
(zsh)를 그대로 `.zshrc`에 놓고 띄웠고, 나온 것은 우리가 물어본 것뿐이었다.

```
z: function                     ← whence -w z
fzf-history-widget: function    ← whence -w fzf-history-widget
tars-config: alias              ← SC의 alias도 그대로 산다
```

씨앗을 통째로 꺼내 보는 법(이번에 처음 썼다):

```zig
// init/src/seed_dump.zig 를 임시로 만들고 zig run 한다
for (std.enums.values(config.Shell)) |sh|
    std.debug.print("===== {s}\n{s}", .{ @tagName(sh), sh.rcSeed() });
```

### 실측 24 — `whence -w`의 답은 `widget`이 아니라 `function`이다

```
whence -w z                    → z: function
whence -w fzf-history-widget   → fzf-history-widget: function
```

`zle -N`로 위젯이 되지만 `whence -w`가 보는 것은 그 이름의 함수다. 결정 8이
명령만 적고 출력을 안 적어서 이것으로 판정 글자를 정했다. fish도 같은 이름의
함수를 정의한다(`functions -q fzf-history-widget` → 0).

### 실측 25 — `cd` 한 번이 DB를 채운다. 그리고 `cd`도 `z`도 조용하다

```
zsh -i -c 'cd /usr/bin/../share/terminfo/x; cd /; z terminfo x; pwd'
  → /usr/share/terminfo/x       ← 출력이 이 한 줄이 전부다
```

이 한 줄을 찍은 것은 `pwd`이고, 그 값을 만든 것은 DB다. 7차 부팅이 그대로
쓰는 시퀀스이고, 게이트의 화면에서 프롬프트가 `(none)#`(cwd 없음)인 것이 이
판정을 더 좁힌다.

### 실측 26 — bash의 훅은 `cd`가 아니라 프롬프트에 걸린다

같은 시퀀스를 bash로 하면 `zoxide: no match found`가 나고 `pwd`가 `/`다.
`bash -i -c`는 프롬프트를 안 그리므로 `PROMPT_COMMAND`가 한 번도 안 돈다.

| 셸 | 훅이 걸리는 자리 |
|---|---|
| zsh | `chpwd_functions` — 디렉터리를 옮길 때 |
| fish | `--on-variable PWD` — 같다 |
| bash | `PROMPT_COMMAND` — 프롬프트마다 |

버그가 아니라 셸의 차이다. 게이트가 zsh로 판정하는 이유가 하나 늘었고,
씨앗의 주석도 셸마다 다르게 적었다.

### 실측 27 — 관문을 빼면 도구가 없을 때 시끄럽다 → 결정 11

| 셸 | 관문 있음 | 관문 없음(도구가 없을 때) |
|---|---|---|
| zsh | 0바이트 | 50바이트 `.zshrc:1: command not found: …` |
| bash | 0바이트 | 38바이트 |
| fish | 0바이트 | 191바이트 / 6줄(소스 위치와 화살표까지 그린다) |

이 표가 결정 11의 전부다.

### 실측 28 — 훅의 비용은 arm64에서 2ms

대화형 zsh 기동이 25ms → 27ms(5회 평균). 파싱하는 양은 `zoxide init zsh`
4,569바이트 + `fzf --zsh` 19,545바이트다(fish 6,418 · bash 24,142). 게스트는
TCG라 이것의 몇 배지만 초 단위로는 안 보일 크기이고, 게이트가 그것을
확인했다(실측 33).

### 실측 29 — fzf가 뺏는 키 넷을 직접 다시 셌다

실측 8을 안 믿고 다시 셌다(`rg -o 'sendkey [a-z0-9-]+'` + `type_keys` 배열
전체).

```
fzf가 바인드: ^I(Tab) · ^T · ^R · \ec(Alt+C)      ← zsh·fish 둘 다 같다
게이트가 치는 것: ctrl-c · ctrl-a · ctrl-l · alt-l · caps · ctrl ·
                  shift-spc · shift-home/end/pgup · ctrl-alt-delete · 글자들
```

`tab`·`ctrl-r`·`ctrl-t`·`alt-c`는 저장소 어느 `check.sh`에도 한 번도 안
나온다. 실측 8이 맞았다.

### 실측 30 — 부팅이 하나가 아니라 둘 필요했다

결정 8의 정정 블록에 전문이 있다. 요약하면 4·5차가 쓰고 간 디스크에는
3차가 심은 `exit`가 아직 있고, 그것을 읽는 부팅은 훅을 못 건다.

한 줄만 지우지 않고 파일을 통째로 지운 것이 이 milestone에서 가장 만족스러운
자리다. 얻은 것이 셋이다.

1. 7차의 rc가 정확히 `rcSeed()`의 내용이 된다 — 1차에서 사람이 더한
   `echo tars-rc-alive`도 없다. 증명 대상이 우리가 짠 글자 그 자체다.
2. `O_EXCL`의 계약을 빈 디스크가 아닌 자리에서 다시 증명한다 — 없어진
   하나만 다시 깔고(`seeded /config/zshrc`가 있다) 있는 둘은 안 건드린다
   (`seeded /config/bashrc`가 없다).
3. 타이핑이 `rm`과 `ls` 둘로 끝난다.

6차가 `tars.noconfig`로 뜨는 것에도 뜻이 있다. SC-M2가 그 토큰을 만든
근거가 *"설정을 고칠 셸이 없을 때 쓰는 것"*이었고, M1이 그것을 실제로 그
용도로 썼다 — 게이트가 자기 탈출로를 쓰는 첫 자리다.

### 실측 31 — 되돌림 둘: 판정 두 개가 서로 독립이다

훅을 한 줄만 죽였다(`command -v zoxide-nope`처럼 관문을 없는 이름으로).
씨앗과 `hookLines()`를 함께 고쳤으므로 호스트 검사는 통과하고 부팅까지
간다 — 도구 이름이 `zoxide-nope`여도 덮개 검사의 부분 문자열에는 걸린다는
것이 여기서 편리했다.

| | 무엇을 죽였나 | `z` 판정 | 위젯 판정 |
|---|---|---|---|
| C | zoxide 훅 | 빨강 | 안 닿는다(첫 판정에서 돌아온다) |
| D | fzf 훅 | 초록 | 빨강 |

둘 다 두 번씩 돌려 네 번 다 같았다. 되돌림 C의 화면이 이 검사의 모양을
가장 잘 보여 준다.

```
(none)# cd /usr/bin/../share/terminfo/x
(none)# cd /
(none)# z terminfo x
zsh: command not found: z
(none)# pwd
/
```

타이핑한 줄에 `/usr/share/terminfo/x`가 한 번도 안 나온다(있는 것은 `..`가
든 쪽이다). 그리고 프롬프트에 cwd가 없다 — 판정 글자를 만들 수 있는 것이
`pwd` 하나뿐이라는 뜻이다.

되돌림 D가 독립성을 증명한다. `z`가 초록인 채로 위젯만 빨개졌으므로, 위젯
검사는 zoxide가 살아 있는 것으로 만족되지 않는다.

### 실측 32 — "깨뜨렸는데 첫 회차가 초록"의 비율을 처음 쟀다

이 milestone에서 새 코드와 가장 무관하고 가장 값진 것이다.

되돌림을 처음 돌렸을 때 깨뜨린 첫 회차가 통과했다 — 호스트 검사에서 두 번,
그리고 체인 전체에서 한 번. SC가 세 번 보고 *"`zig build test`가 직전 내용의
결과를 낸다"*고 적어 둔 그 증상이다.

이번에는 넘기지 않고 쟀다. 절차는 이렇다 — 초록을 한 번 빌드해 캐시에 넣고,
씨앗에 `echo` 한 줄을 더해 깨뜨리고, 한 번만 돌려서 그것이 잡히는지 본다.

| 조건 | 첫 회차가 잡았나 |
|---|---|
| 따뜻한 캐시 | 5회 중 4회. 1회는 거짓 초록 |
| `rm -rf init/.zig-cache init/zig-out` | 4회 중 4회 |

거짓 초록이 난 회차는 `--summary all`에서 run 스텝까지 `cached`였다. 그런데
그 수로는 갈릴 수 없다 — 잡은 회차에도 같은 수가 찍힌 경우가 있었다.
"어느 회차를 믿을지 알려 주는 신호가 없다"가 이 측정의 결론이고, 그래서
*"두 번 돌린다"*가 처방이 안 된다.

범인이 아닌 것도 쟀다.

| 의심 | 어떻게 쟀나 | 결과 |
|---|---|---|
| 바인드 마운트가 낡은 내용을 준다 | 고치고 컨테이너 둘에서 연달아 `cat` × 5회 | 아니다. 10/10 새 내용 |
| mtime만 바뀌어서 못 본다 | 위 측정은 줄을 더하는 편집이다(크기가 바뀐다) | 그것으로는 설명이 안 된다 |

> 중간에 한 번 틀리게 적었다가 고쳤다. 처음에는 *"범인은 `zig build`의
> install 단계이고 `zig-out`을 지우면 된다"*고 결론을 냈는데, `init/build.zig`가
> `config_test`를 `installArtifact`하지 않는다 — 그 실행 파일은
> `.zig-cache`에서 직접 돌아간다. `zig-out`을 지우는 것이 호스트 검사에
> 영향을 줄 수 없다는 뜻이고, 그래서 그 결론은 관측 넷의 우연이었다(거짓
> 초록이 5분의 1이면 넷이 연속으로 옳게 나오는 것은 절반쯤 일어난다).
> 문서에 인과를 적기 전에 그 인과가 코드에서 가능한지 먼저 봤어야 했다.

UT-M3은 산출물 쪽 실체를 직접 봤다 — 소스 mtime이 더 새것인데도
`zig-out/bin/init`이 옛것이었고 바이트 수가 달랐다. 증상이 양쪽으로 나는
것이 이 함정을 여섯 번이나 다른 것으로 보이게 만들었다.

| 편집 방향 | 어떻게 보이나 |
|---|---|
| 깨뜨렸다 | 깨뜨렸는데 초록(SC ×3, SM-M1 ×2) |
| 되돌렸다 | 고쳤는데 빨강(UT-M3) |

처방은 음성 확인 전에 `.zig-cache`와 `zig-out`을 함께 지우는 것이다.
루트 게이트는 이미 안전하다 — `clean()`이 매 판 시작에 넷을 다 지운다
(`check.sh:15`). 위험한 것은 체인을 단독으로 돌릴 때뿐이고, 음성 확인이
정확히 그 자리다. 본문은 `docs/decisions/project_zig_out_staleness.md`.

### 실측 33 — 루트 게이트

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
18 PASS   0 FAIL          27분 05.06초, 첫 회차에 통과
```

기준선은 SM-M0의 26분 27.84초이고 +37.22초다. 부팅이 둘 늘어 회차마다
여섯 번 더 켜졌으니 부팅당 약 6초이고, 위험 5가 "+40초 안쪽"으로 본 것과
맞는다.

| 세는 것 | 수 | 뜻 |
|---|---|---|
| `command not found` | 0 | 훅이 열한 체인 어디서도 한 글자도 안 찍었다 — 위험 1이 안 일어났다 |
| `Unknown command` | 0 | fish 쪽도 같다 |
| `error while loading shared libraries` | 0 | 새 라이브러리를 안 더했으니 당연하고, 그래도 센다 |
| `Welcome to fish` | 6 | SC-M0·M1·M2·SM-M0과 같다 — 회귀 없음 |
| `times fast` | 6 | 4차 부팅의 자식 둘 × 세 회차. 7차가 이 수를 안 늘렸다 |
| `boot 6: removed the rc …` | 3 | 새 6차 × 세 회차 |
| `boot 7:` 넷 | 각 3 | 새 7차의 `echo` 넷 |
| `all 67 tools` | 3 | `tools` 체인은 안 건드렸다 |

`command not found`가 0인 것이 이 게이트에서 가장 중요한 수다. 설정 디스크를
붙이는 다섯 체인이 전부 씨앗을 새로 받았고, 그중 셋은 화면의 셀 좌표로
판정한다 — 실측 23이 예측한 "안 깨진다"가 서른세 번의 체인 실행에서 재현됐다.

`Welcome to fish`가 6인 것이 뜻하는 것을 정확히 적는다. 처음에는 *"훅이
fish를 죽였다면 이 수가 줄어든다"*고 쓰려다 재 봤다 — 인사말은 rc가 `exit`로
끝나도 찍힌다(세 경우를 pty로 재서 셋 다 1). 인사말은 rc보다 먼저 나온다.

| 이 수가 말하는 것 | 이 수가 말하지 않는 것 |
|---|---|
| fish가 같은 여섯 자리에서 대화형으로 떴다(회귀 없음) | rc가 살아남았다 |

"씨앗이 셸을 안 죽였다"를 말하는 것은 다른 두 수다 — `times fast`가 6에서
안 늘어난 것과, 7차의 `started … exactly 1`이다.

## SM-M2가 실행으로 증명한 것

M2가 이 서브프로젝트를 닫았다. 고친 파일이 일곱이고 새 파일이 하나도
없다. 씨앗 rc와 `expectQuietSeed`는 한 글자도 안 건드렸다(결정 3이 옳았던
것의 값이 여기서 나온다 — 히스토리 줄이 rc에 한 줄도 필요 없었다).

### 실측 34 — 셸이 어떻게 끝나야 `HISTFILE`이 써지나

컨테이너에서 pty(`script -qfc` + fifo) 위의 zsh를 네 가지 방법으로 끝냈다.

| 끝내는 법 | 파일 | 내용 |
|---|---|---|
| `exit` | 있다 | `echo marker_exit` / `exit` |
| SIGTERM | 있다 | `echo marker_TERM` |
| SIGHUP | 있다 | `echo marker_HUP` |
| SIGKILL(=전원) | 없다 | — |

이 표가 M2의 모양을 정했다. 위 결정 3의 정정 블록이 여기서 나왔고, 그것이
`config/check.sh`의 7차에 `fc -W` 두 줄을 넣은 이유다.

> ⚠ 정정(2026-09-12, SD design 실측 2·3) — SIGTERM 행이 틀렸다. 대화형 zsh는
> 자기에게 온 SIGTERM을 무시한다. 보낸 뒤에도 살아서 다음 명령을 실행하고
> 파일은 안 생긴다. 이 표에 파일이 있는 것으로 나온 이유는 신호를 받은 것이
> 셸이 아니라 `script` 껍데기였기 때문으로 보인다 — PTY 주인이 죽으면 커널이
> 안쪽 셸에게 SIGHUP을 보내고, 그 SIGHUP이 파일을 쓴 것이다. 그래서 이 표의
> 진짜 내용은 *"누구에게 보내는지가 갈린다"*이고, 그것이 TARS의 두 셸에서
> 다르게 작동한다(화면 셸은 PTY 주인이 `terminal`이고, 콘솔 셸은 닫히지 않는
> 커널 콘솔이다).
> 본문은 `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`.

### 실측 35 — `fc -W`가 쓰고, `wc -l`은 앞에 공백을 안 넣는다

```
$ fc -W ; wc -l $HISTFILE
6 /tmp/rehearse/config/zsh_history      ← 행의 첫머리가 숫자다
```

파일은 평문 한 줄에 명령 하나다(`EXTENDED_HISTORY`가 꺼져 있다 — 실측 9와
같다). GNU `wc`는 파일이 하나면 앞에 공백을 안 넣는다 — 그래서 게이트가
`\| [1-9][0-9]* /config/zsh_history` 하나로 이 출력을 타이핑한 줄과 가른다.

### 실측 36 — 새 셸의 `history` 출력 모양

```
    1  cd /usr/bin/../share/terminfo/x
    2  cd /
    3  whence -w fzf-history-widget
    4  fc -W
```

네 칸 들여쓰고 번호, 공백 둘, 명령이다. 그래서 8차의 셋째 판정만 *"행의
첫머리"* 수법을 못 쓴다 — 대신 그 부팅에서 아무도 안 치는 명령을 찾는다.

### 실측 37 — bash는 `HISTSIZE`만으로 파일까지 자른다

`HISTFILESIZE`를 안 주고 `HISTSIZE=5`로 열두 개를 친 뒤 나가니 파일이 5줄이다.
결정 4의 5,000줄 상한이 bash에서도 선다는 뜻이고, env 항목을 하나 안 늘려도
된다.

### 실측 38 — `XDG_DATA_HOME` 하나가 DB를 옮긴다

```
XDG_DATA_HOME=…/config/xdg zoxide add /usr/bin/../share/terminfo/x
  → …/config/xdg/zoxide/db.zo     ← 없는 경로 **둘**을 스스로 만들었다
  → 홈에는 아무것도 없다
  → ls $XDG_DATA_HOME/zoxide  →  db.zo
```

실측 3·4의 재확인이고, `ls`의 출력이 `db.zo` 한 단어라는 것이 8차 부팅의
둘째 판정이 됐다.

### 실측 39 — env 넷의 비용은 0바이트다

`env -i` 위에서 셸 셋을 전/후로 쟀고 바이트가 같았다.

| 셸 | 전 | 후 |
|---|---|---|
| zsh | 371 | 371 |
| bash | 127 | 127 |
| fish | 863 | 863 |

위험 1(씨앗이 한 글자라도 찍으면 다섯 체인의 화면 좌표가 밀린다)이 이번에도
같은 자리에 있었고, 이 표가 착수 전 근거였다. 실측 43이 그것을 게이트에서
확인했다.

⚠ `env -i`가 이 측정의 전부다. 처음에는 앞 측정의 `export`가 새서
엉뚱한 것을 봤고, 그것이 아래 실측 41이 됐다.

### 실측 40 — fish 히스토리는 `XDG_DATA_HOME` 아래로 자동으로 간다

```
…/xdg/fish/fish_history
- cmd: echo marker
  when: 1789172042
```

실측 11이 맞았다. fish에게는 env를 하나도 안 준다 — `XDG_DATA_HOME` 하나가
히스토리까지 옮긴다. 그래서 `histEntries()`가 fish에 빈 목록을 준다.

### 실측 41 — fish는 첫 대화형 기동에 `$HISTFILE`을 가져온다

```
HISTFILE=…/borrowed_bash_history 를 주고 fish를 처음 띄우면
  fish_history:  - cmd: echo bash_line_one
                 - cmd: echo bash_line_two
```

우연히 발견한 것이고, 우리 설계에서는 안 일어난다 — `shell=fish`인 기계에는
`HISTFILE`이 아예 없다. `shell`을 bash에서 fish로 바꾼 사람에게는 이것이
기능이 된다(쳤던 명령이 따라온다). 문서에 적어 두고 코드로는 아무것도 안
했다(비목표 8).

### 실측 42 — 7차→8차를 컨테이너에서 통째로 예행했다

씨앗과 같은 훅이 든 `.zshrc`를 놓고, 7차를 `kill -9`로 끝내고(전원), 새 세션을
띄워 `cd`를 한 번도 안 치고 판정 셋을 확인했다.

```
=== 7차 (전원을 뽑는다)
/usr/share/terminfo/x                     ← z가 돈다(M1의 판정)
fzf-history-widget: function              ← 위젯이 있다(M1의 판정)
6 /tmp/rehearse/config/zsh_history        ← fc -W가 썼다(M2의 새 판정)

=== 8차 — 아무도 cd를 안 친다
/usr/share/terminfo/x                     ← z가 이전 부팅의 자리로 갔다
db.zo                                     ← 그 기억이 설정 디스크에 있다
    5  whence -w fzf-history-widget       ← 7차만 친 명령이 목록에 있다
```

게이트를 짜기 전에 판정이 실제로 나오는 것을 봤다. M0·M1이 각각 한 번씩
*"판정 글자가 안 나온다"*로 되돌아간 자리를 이번에는 앞에서 막았고,
`config/check.sh`가 첫 실행에 통과했다(부팅 여덟, 1분 26초).

### 실측 43 — 되돌림 셋과 측정 하나

| | 무엇을 깼나 | 무엇이 빨개졌나 |
|---|---|---|
| A | `HIST_ZSH`에서 `SAVEHIST` | `FAIL: the zsh shell carries 2 history env entries, want 3` |
| B | bash의 `HISTFILE`을 zsh와 같은 파일로 | `FAIL: bash and zsh point HISTFILE at the same file` |
| C | `withTarsEnv`에서 `XDG_ENTRY`를 뺀다 | `FAIL: want 7 entries for zsh, got 6` |
| D | `XDG_DATA_DIR` → `/tmp/xdg` | 7차 초록 · `FAIL(boot 8): the machine forgot the directory the seventh boot learned` |
| E | `HIST_ZSH`에서 `SAVEHIST`(게스트까지) | `FAIL(boot 7): 'fc -W' left no history file …` + 화면에 `wc: /config/zsh_history: No such file or directory` |
| F(측정) | `makeXdgDir()` 호출을 지운다 | 초록이다 |

D의 비대칭이 이 milestone이 증명하는 것의 정확한 모양이다 — 한 부팅
안에서는 되고, 부팅을 넘으면 안 된다. M1의 7차는 이 되돌림을 못 잡는다.

E가 실측 9의 게스트 재현이다. `fc -W`는 조용히 성공했는데 파일이 아예 안
생겼다 — `SAVEHIST`가 없으면 zsh는 `HISTFILE`이 있어도 한 줄도 안 쓴다.

F는 음성 확인이 아니라 측정이다. `makeXdgDir()`이 없어도 zoxide가 없는
경로를 스스로 만든다(실측 4·38이 게스트에서도 맞다). 그 `mkdir`은 기능이 아니라
실패의 자리를 정하는 것이고, SM-M0이 관문에 대해 *"고친 것이 아니라 보장한
것이다"*라고 적은 것과 같은 종류다.

### 실측 44 — 호스트에서 캐시를 지우면 `zig build`가 이따금 죽는다

M2가 새 코드와 무관한 것을 하나 더 좁혔다. `docs/decisions/
project_zig_out_staleness.md`의 처방은 *"음성 확인 앞에
`rm -rf init/.zig-cache init/zig-out`"*인데, 그것을 호스트(macOS)에서 치면
바로 뒤의 `zig build`가 `error: FileNotFound` 한 줄로 죽는다 — 9회 중 2회.

```
# 호스트에서 지운다        → 9회 중 2회 error: FileNotFound (메시지가 그 한 줄뿐)
rm -rf init/.zig-cache init/zig-out
docker run … 'cd init && zig build'

# 같은 컨테이너 안에서 지운다 → 6/6 정상
docker run … 'rm -rf init/.zig-cache init/zig-out; cd init && zig build'
```

`--verbose`를 줘도 한 줄도 더 안 나온다(빌드가 시작되기도 전에 죽는다).
호스트의 `rm`과 컨테이너의 `open`이 bind mount를 사이에 두고 갈리는 것으로
보이며, 원인을 더 파지는 않았다 — 처방이 한 글자 옮기는 것이라서다.
⚠ 이 실패는 컴파일 에러와 구분이 안 되는 모양으로 나온다. 다시 돌리면
지나가므로 `zig build`의 실패를 만나면 먼저 한 번 더 돌린다.

### 실측 45 — 루트 게이트가 한 번 빨갰고, 원인이 SM-M0이 센 그 함정이었다

첫 게이트가 `HI-M3 run 2/3`에서 죽었다.

```
FAIL: init did not read hangul_toggle=shift_space,capslock_tap,lctrl_tap
      from the config disk
--- last 40 lines ---
terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=shift_space,capslock_tap,lctrl_tap
```

판정 글자가 로그에 멀쩡히 있는데 빨갰고, 같은 게이트의 run 1/3은
초록이었다. `hangul/check.sh:326`이 이렇게 생겨 있었다.

```bash
if ! tr -d '\r' < "$LOG" | grep -aqE "tars-init: config .*toggles=…"; then
```

SM-M0이 `tools/check.sh`에서 고친 그 병이고, 여기서는 `!` 형이라 거짓
빨강이다. `grep -q`가 첫 매치에서 나가면 아직 로그를 쏟던 `tr`이 SIGPIPE로
죽고, `pipefail`이 그 141을 파이프라인 코드로 올린다. 호스트에서 바로
재현했다.

```
tr -d '\r' < 200KB짜리 로그 | grep -aqE '앞쪽에 있는 글자'   → rc=141
tr -d '\r' < 4KB짜리  로그 | grep -aqE '앞쪽에 있는 글자'   → rc=0
```

크기가 아니라 경주다 — 파이프 버퍼(64KiB)보다 로그가 크면 터지는데,
QEMU가 살아 있는 동안 로그가 계속 자라므로 회차마다 갈린다. 처방은 같다:
`-q`를 빼서 뒤쪽 grep이 입력을 끝까지 읽게 한다.

SM-M0의 목록이 이것을 못 셌던 이유가 명확하다 — 그때 쓴
`rg '\| *grep -[a-z]*q'`는 플래그 끝이 `q`인 것만 찾는데 이 자리는 `-aqE`로
`q`가 가운데 있다. 다음에 세는 사람은
`rg '\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q'`를 쓸 것.

이것은 SM-M2가 만든 병이 아니다 — 쓰인 날부터 있던 경주이고, 이 게이트가
그것을 처음 터뜨렸을 뿐이다. 그래도 고치지 않고는 M2를 초록으로 만들 수
없어서 이 milestone이 고쳤다. SM-M0이 자기 그물만 고치고 남긴 목록의
여덟째이고, 남은 일곱은 그대로 숙제다.

### 실측 46 — 루트 게이트(고친 뒤)

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
체인 열하나 × 3회, FAIL 0            28분 03.23초
```

기준선은 SM-M1의 27분 05.06초이고 +57.71초다. 부팅이 하나 늘어 회차마다
세 번 더 켜지므로 부팅당 약 19초인데, 위험 5가 "+20초 안쪽"으로 본 것보다
크다. 그 차이를 부팅 하나의 값으로 읽으면 안 된다 — `config` 체인을 단독으로
돌렸을 때는 부팅 여덟에 1분 26초로 SM-M1이 부팅 일곱에 적은 1분 40초보다
오히려 빨랐다. 기계의 그날 상태가 이 수에 부팅 셋보다 크게 들어간다.

| 세는 것 | 기대 | 실제 | 뜻 |
|---|---|---|---|
| `command not found` | 0 | 0 | env 넷이 열한 체인 어디서도 한 글자도 안 찍었다 — 위험 1이 안 일어났다 |
| `Unknown command` | 0 | 0 | fish 쪽도 같다 |
| `Welcome to fish` | 6 | 6 | SC-M0~SM-M1과 같다 — 회귀 없음 |
| `times fast` | 6 | 6 | 4차 부팅의 자식 둘 × 세 회차. 8차가 이 수를 안 늘렸다 |
| `boot 8: the machine remembered` | 3 | 3 | 새 부팅 × 세 회차 |
| `all 67 tools` | 3 | 3 | `tools` 체인은 안 건드렸다 |

`command not found`가 0인 것이 이 게이트에서 가장 중요한 수다. 설정
디스크를 붙이는 다섯 체인이 전부 새 env 넷을 받았고(조건이 없다 — 결정 9),
그중 셋이 화면의 셀 좌표로 판정한다. 실측 39가 예측한 "0바이트"가 서른세
번의 체인 실행에서 재현됐다.

`Welcome to fish`가 6인 것이 말하지 않는 것은 SM-M1이 적은 그대로다 —
인사말은 rc가 `exit`로 끝나도 찍힌다. *"씨앗이 셸을 안 죽였다"*를 말하는 것은
`times fast`가 6에서 안 늘어난 것과 7차·8차의 `started … exactly 1`이다.

## 비목표

1. `git-delta`. UT 비목표 5가 *"다음에 후보를 찾을 때 이 문단을 먼저 읽을
것"*이라고 적어 둔 것이고, git이 서면서 `libgit2`를 이미 들였으므로 라이브러리
비용이 0에 가깝다(바이너리 6,743KB). 훅도 rc가 아니라 `/config/gitconfig`의
`core.pager`라 인프라가 이미 서 있다. 그래도 사용자가 2026-09-11에 이번
범위에서 뺐다. 다음 후보를 찾는 사람은 UT 비목표 5와 이 문단을 함께 읽을
것.

2. `Ctrl+R`·`Ctrl+T`·`Alt+C`를 게이트가 치는 것. 실측 8이 이유다. 셋 다
TUI라 체인이 매달린다. 게이트가 보는 것은 위젯이 정의됐다는 것까지다
(결정 8).

3. `/config`가 찼을 때의 정책. 상한을 5,000줄로 두는 것까지가 이
서브프로젝트다(결정 4). 디스크가 꽉 찼을 때 무슨 일이 나는지는 안
만든다 — 지금도 만들지 않았고, 히스토리가 그 수를 유의미하게 바꾸지
않는다(250KB / 16MiB = 1.5%).

4. fish 히스토리의 줄 수 상한. 실측 11이 이유다. fish에 그 변수가 없다.
`XDG_DATA_HOME` 아래로 옮기는 것까지만 한다.

5. `zoxide`의 `zi`(대화형 선택). fzf가 있으므로 돈다. 게이트가 안 본다
— 비목표 2와 같은 이유다.

6. 훅을 사용자가 끌 수 없게 만드는 것. `shell_config=off`와
`tars.noconfig`가 rc를 막으면 훅도 함께 안 걸린다. 그것이 맞다 — SC가 만든
탈출로가 SM이 더한 것까지 덮어야 한다.

7. 셸을 셋보다 늘리는 것 · rc를 런타임에 다시 읽는 것. SC 비목표 7·8이
그대로다.

8. 실측 41(fish가 첫 기동에 `$HISTFILE`을 가져온다)을 쓰는 것. 우리
설계에서는 안 일어난다 — `shell=fish`인 기계에는 `HISTFILE`이 아예 없다.
`shell`을 바꾼 사람에게 히스토리가 따라오는 것은 공짜로 얻은 기능이고,
코드로는 아무것도 안 했다.

9. 위험 3 — zsh 두 세션이 같은 `HISTFILE`을 겹쳐 쓴다. 알고 둔다.
`setopt APPEND_HISTORY`는 씨앗 허용 목록(`expectQuietSeed`)을 한 줄 더 넓히는
일이고, 이 서브프로젝트가 먼저 증명할 것은 *"남는다"*였다. 다음에 이
서브프로젝트를 다시 여는 사람의 첫 후보가 이것이다.

> ⚠ 정정(2026-09-12) — 그 후보를 2026-09-12에 집었고, 착수 전 측정이 이 항목의
> 전제가 틀렸다는 것을 보였다(위험 3의 정정 블록). 그 자리에서 나온
> 서브프로젝트가 Shell History Durability(SD)이고, 고치는 것은
> `INC_APPEND_HISTORY`다.

## 결정

### 결정 1 — 자리를 옮기는 것은 링크가 아니라 환경 변수다

SC 결정 1은 `/config`의 rc 파일을 홈에 링크로 이었다. SM은 그 패턴을 안
쓴다. 실측 4가 이유다 — 댕글링 링크에서 `zoxide`는 `cd`마다 에러 두 줄을
찍고, 없는 경로를 준 환경 변수에서는 `mkdir -p`하고 조용히 성공한다.

| | 링크 (SC 결정 1) | 환경 변수 (SM 결정 1) |
|---|---|---|
| 디스크가 있을 때 | 영속한다 | 영속한다 |
| 디스크가 없을 때 | 댕글링 → `cd`마다 에러 두 줄 | tmpfs에 만든다 → 조용하다 |

같은 저장소에서 두 서브프로젝트가 반대 결정을 하는 것이고, 갈린 것은 취향이
아니라 실측이다. rc 파일은 우리가 만드는 것이라 없으면 만들면 되고
(`seedRcFiles`의 `O_EXCL`), DB는 도구가 만드는 것이라 우리가 그 도구의
실패 모드를 물려받는다.

### 결정 2 — `XDG_DATA_HOME` 하나가 둘을 옮긴다

```
XDG_DATA_HOME=/config/xdg
  → /config/xdg/zoxide/db.zo          (실측 3)
  → /config/xdg/fish/fish_history     (실측 11)
```

안 고른 쪽: `_ZO_DATA_DIR`로 `zoxide`만 명시적으로 옮기는 것. 그러면
fish 히스토리를 옮길 방법이 따로 없다 — fish에는 경로 변수가 없고
`fish_history`는 세션 이름이지 경로가 아니다. `XDG_DATA_HOME`이 유일한
지렛대이고, 그것을 쓰면 `zoxide`가 공짜로 따라온다.

대가: XDG를 보는 도구가 앞으로 늘면 그것들도 조용히 `/config`에 쓰기
시작한다. 16MiB짜리 디스크라 그것이 언젠가 문제가 될 수 있다 — 비목표 3이 그
경계를 적어 둔다.

### 결정 3 — 히스토리는 env 넷으로 세우고, `environ.zig`가 그것을 짓는다

씨앗 rc에 히스토리 줄을 한 줄도 안 넣는다. 실측 9·10·11이 근거다.

| 항목 | 값 | 누가 먹나 |
|---|---|---|
| `XDG_DATA_HOME` | `/config/xdg` | fish 히스토리 · zoxide DB |
| `HISTFILE` | `/config/<셸>_history` | bash · zsh |
| `HISTSIZE` | `5000` | bash · zsh |
| `SAVEHIST` | `5000` | zsh (없으면 한 줄도 안 쓴다) |

`HISTFILE`이 셸마다 갈리는 이유는 형식이다 — zsh는
`: <ts>:<dur>;<cmd>`, bash는 평문이다. 한 파일에 섞으면 서로의 것을 못 읽는다.
init이 `cfg.shell`을 이미 알고 있으므로 그 자리에서 정한다.

콘솔 셸과 화면 셸은 같은 파일을 공유한다(사용자가 2026-09-11에 정했다).
근거는 *"화면에서 친 명령을 콘솔에서도 찾을 수 있어야 한다"*이고, 대가는
위험 3이다.

안 고른 쪽: 화면 셸에만 `terminal`이 `setenv`로 다른 `HISTFILE`을 주는 것
(`TERM`·`LANG`이 이미 그 자리에 있다). 겹쳐 쓸 일이 없어지지만 `Ctrl+R`이
자리마다 다른 것을 보여 준다.

#### ⚠ 정정(SM-M2 착수 전) — 이 결정은 게이트가 전원을 뽑는다는 것을 안 봤다

위 표는 *"부팅 사이에 남는다"*를 적으면서 게이트가 기계를 어떻게
끝내는지를 안 봤다. `boot_once`는 마커를 보면 `kill "$QEMU_PID"`로 끝내고,
게스트에게 그것은 전원이 끊긴 것이다 — 셸이 나갈 때 하는 일이 하나도 안
일어난다. 실측 34가 그 경계를 정확히 그었다(`exit`·SIGTERM·SIGHUP은 써지고
SIGKILL은 안 써진다).

실기는 안전하다. 전원 버튼을 누르면 PID 1의 SIGTERM이 셸에게 가고
(`power.zig`) 그때 zsh가 스스로 쓴다. 못 쓰는 것은 게이트뿐이고, 처방은
7차 부팅이 `fc -W`를 직접 치는 것이다(되읽기 `wc -l`을 함께 둔다 — 없으면
8차가 빨간 이유가 *"안 썼다"*인지 *"안 읽었다"*인지 안 갈린다).

> ⚠ 정정(2026-09-12, SD design 실측 2·3·4) — *"실기는 안전하다"*가 틀렸다.
> 세 군데다. SIGTERM은 셸에게 가지만 대화형 셸이 그것을 무시한다.
> 화면 셸이 쓰는 것은 그 신호 때문이 아니라 `terminal`이 먼저 죽어 PTY가
> 닫히면서 온 SIGHUP 때문이다. 그리고 콘솔 셸은 `/dev/console`을 제어
> 터미널로 잡으므로 그 SIGHUP이 올 데가 없어 아예 못 쓴다 — 그 세션의
> 히스토리는 전원 버튼에서 사라진다. `power.zig:178`의 주석이 첫째를 이미
> 적어 두고 있었는데 이 결정과 맞춰 보지 않았다.
> 본문은 `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`.

SM-M1에서 *"design이 앞 부팅이 남긴 디스크 상태를 안 봤다"*와 같은 종류의 빈
자리이고, 이번에는 착수 전에 걸렸다.

### 결정 4 — 상한은 5,000줄

한 줄을 50바이트로 보면 250KB, 16MiB의 1.5%다. `zoxide`의 `db.zo`는 고유
디렉터리 수에 비례해 KB 단위다.

이 수의 근거는 "크면 위험하고 작으면 쓸모없다"의 중간이 아니라 디스크
예산이다 — 히스토리가 `/config`를 채우는 일이 없어야 하고, 5,000줄은 사람이
한 기계에서 몇 달 치는 양이다.

### 결정 5 — 훅은 씨앗 rc에 들어간다. 기본이 켜짐이다

사용자가 2026-09-11에 정했다("받아서 버린다"). 새 설정 디스크로 처음 뜬
기계에서 `z`와 `Ctrl+R`이 바로 돈다.

| 셸 | 훅 두 줄 |
|---|---|
| `zsh` | `eval "$(zoxide init zsh)"` · `eval "$(fzf --zsh)"` |
| `bash` | `eval "$(zoxide init bash)"` · `eval "$(fzf --bash)"` |
| `fish` | `zoxide init fish \| source` · `fzf --fish \| source` |

안 고른 쪽 둘. 주석으로 넣고 사용자가 벗기게 하는 것 — `expectQuietSeed`를
한 자도 안 건드리지만 "도구가 있는데 안 돈다"는 상태가 기본이 된다. 씨앗을 안
건드리고 README에만 적는 것 — 가장 짧지만 게이트가 `z`가 실제로 도는 것을
영영 못 본다.

### 결정 6 — `expectQuietSeed`는 문법 범주가 아니라 정확 허용 목록으로 연다

실측 13의 검사를 *"주석 · `alias` · `eval` 세 범주"*로 넓히면 `eval` 뒤에
아무 문장이나 올 수 있다 — 씨앗이 부팅 때 찍을 수 있는 것이 무한히 열리고,
그 규칙이 막으려던 것이 정확히 그것이다.

대신 이렇게 연다.

1. `Shell.hookLines()`가 그 셸의 훅 줄들을 돌려준다(결정 5의 표).
2. 씨앗의 비주석·비`alias` 줄은 그 목록의 한 줄과 글자 그대로 같아야
   한다.
3. 역방향도 검사한다 — 훅 줄 전부가 씨앗에 있어야 한다.

3번이 있는 이유는 1·2번만으로는 훅을 지우는 것이 통과하기 때문이다.
그리고 그 검사는 호스트에서 0.1초에 돌아 부팅 20초를 쓰기 전에 죽는다.

> 이 검사의 목적은 지금 통과하는 것이 아니라 나중에 막는 것이다. SC-M1이
> 같은 문장을 적었고, SM은 그 문의 폭을 두 줄만큼 넓힌다.

### 결정 7 — fzf 셸 통합은 `.deb`의 예제가 아니라 바이너리 내장을 쓴다

실측 6이 근거다. initrd에 파일이 하나도 안 늘고, 훅이 `zoxide`와 대칭이 되고,
`.deb`의 예제와 달리 자동완성까지 함께 온다.

대가: `fzf`를 업그레이드하면 훅이 내는 내용이 바뀔 수 있다. 그것을
게이트가 보는 자리가 결정 8의 `whence -w`다.

### 결정 8 — 게이트는 둘로 나눠 본다. `config/check.sh`는 부팅 여덟

> ⚠ 이 결정이 두 자리에서 틀렸고, SM-M1이 실행하면서 고쳤다. 지우지 않고
> 남긴다.
>
> 1. 부팅이 일곱이 아니라 여덟이다. M1이 하나가 아니라 둘을 더했다 —
> 아래 표는 M1이 6차에서 `z tmp`를 친다고 적었지만, 그 시점의
> `/config/zshrc`에는 3차가 심은 `exit`가 아직 들어 있다. 그 파일을 읽는
> 부팅은 셸이 죽고 탈출로가 rc 없이 되살리므로 훅도 함께 안 걸린다.
> 그래서 6차가 수리하고(`tars.noconfig`로 떠서 그 파일을 지운다) 7차가
> 훅을 증명한다. M2의 "부팅을 넘어 기억한다"는 8차다.
>
> 이 결정을 쓸 때 4·5차가 쓰고 간 디스크 상태를 안 봤다 — design이 부팅을
> 세면서 그 부팅들이 남긴 것을 안 센 것이다.
>
> 2. 6차의 시퀀스가 자기 함정에 걸려 있었다. 아래 표의 `cd /tmp` → `cd /`
> → `z tmp` → `pwd`는 `/tmp`을 판정 글자로 쓰는데, 그 글자는 방금 타이핑한
> `cd /tmp`에 있다. 훅이 죽어도 초록인 검사다 — 이 문서가 실측 15에서
> 스스로 경고한 것과 글자 그대로 같은 함정이고, 경고한 사람이 다음 절에서
> 밟았다. 7차는 `cd /usr/bin/../share/terminfo/x` → `cd /` → `z terminfo x`
> → `pwd`로 간다(실측 30).

| 체인 | 디스크 | 무엇을 보나 |
|---|---|---|
| `tools/check.sh` | 없다 | 목록 검사 + 바이너리가 돈다 — `fzf --filter=descr --walker-root=/usr/share/git-core`(실측 7) · `zoxide add /usr/bin/../share/terminfo/x` → `zoxide query terminfo` |
| `config/check.sh` | 있다 | 훅이 걸렸다 + 부팅을 넘어 기억한다 — 부팅 둘을 더한다 |

부팅 6·7차가 하는 일.

| 부팅 | 치는 것 | 증명하는 것 |
|---|---|---|
| 6차 | `cd /tmp` → `cd /` → `z tmp` → `pwd` | 한 시퀀스가 셋을 본다 — 훅이 걸렸다 · DB가 쓰였다 · `z`가 돈다 |
| | `whence -w fzf-history-widget` | fzf 통합이 실제로 위젯을 정의했다(`Ctrl+R`을 안 치고 보는 법. 비목표 2) |
| 7차 | 아무것도 안 침 → `z tmp` → `pwd` · `history` | 재부팅을 넘어 기억한다 |

6차가 7차를 진짜로 만든다 — 6차가 DB에 무언가를 넣었다는 것이 보였기
때문에 7차의 `z tmp`가 "이전 부팅에서 배운 것"을 증명한다. SC-M1의 3차가
2차에 기대고 SC-M2의 5차가 4차에 기댄 것과 같은 구조다.

치는 명령이 전부 소문자다 — `sendkey`에 대문자가 없다(UT-M3). 그래서
`whence -w`이고 `WHENCE`가 아니다.

`whence -w`의 답은 `widget`이 아니라 `function`이다(실측 24). 이 결정이
명령만 적고 출력을 안 적어서 M1이 실측으로 정했다.

### 결정 10 — 훅 글자를 두 벌로 둔다(SM-M1이 더했다)

`rcSeed()`의 씨앗 안에 있는 훅 줄과 `hookLines()`의 훅 줄이 글자가 같은 두
벌이다. `rcSeed()`를 `hookLines()`에서 `++`로 조립하면 한 벌이 되고
중복이 사라진다. 그렇게 안 한다.

결정 6의 역방향 검사가 tautology가 되기 때문이다. *"훅이 씨앗에
있는가"*를 묻는데 씨앗이 그 목록으로 만들어졌으면 답이 언제나 참이다 — 이
저장소가 반복해서 부딪친 자리이고(UT-M1의 정적 목록 검사가 같은 이유로
가짜였다), SM-M0의 되돌림 1이 그것을 실연했다.

두 벌을 잇는 것은 컴파일러가 아니라 `config_test.zig`이고, 그것이 결정 6의
목적이다. 이 파일에는 같은 종류의 이음매가 이미 셋 있다 —
`HangulLayout` ↔ `hangul.Layout` · `Shell.path()` ↔ `make_initrd.sh` ·
`Shell.rcPath()` ↔ `make_initrd.sh`의 링크 셋.

대가: 훅을 고치는 사람이 두 자리를 고쳐야 한다. 한 자리만 고치면
호스트에서 0.1초에 막히므로, 그 대가는 "부팅 20초"가 아니라 "에러 메시지
한 줄"이다.

### 결정 11 — 훅 줄마다 관문이 붙는다(SM-M1이 더했다)

결정 5의 표는 훅을 `eval "$(zoxide init zsh)"` 한 줄로 적었다. 실제로 들어간
것은 앞에 `command -v`(fish는 `type -q`) 관문이 붙은 줄이다.

근거는 실측 27이다 — 도구가 없을 때 관문 없는 훅은 찍는다.

| 셸 | 관문 있음 | 관문 없음(도구가 없을 때) |
|---|---|---|
| zsh | 0바이트 | 50바이트 |
| bash | 0바이트 | 38바이트 |
| fish | 0바이트 | 191바이트 / 6줄 |

그 한 줄이 설정 디스크를 붙이는 다섯 체인의 화면 좌표를 밀어 버린다(위험
1). 관문이 있으면 도구가 없어진 기계는 조용히 기억을 잃고, 그 사실은
`config/check.sh` 7차 부팅이 빨강으로 알린다 — 엉뚱한 체인 넷이 아니라 그
사실을 검사하는 자리 하나가 빨개지는 것이 이 관문이 사는 값이다.

안 고른 쪽: 관문 없이 두고 "도구는 initrd에 늘 있다"에 기대는 것.
`tools/check.sh`의 검사 17·18이 그것을 지키고 있지만, 그 검사가 지키는 것과
이 관문이 막는 것은 다른 실패다 — 전자는 "도구가 없다"를, 후자는 "도구가
없을 때 어떻게 실패하는가"를 정한다.

### 결정 9 — 조건이 없다. 설정 디스크가 없어도 같은 값을 준다

SC-M2의 `rescue_flag`는 `storage_mounted`를 봐야 했다. SM의 env 넷은 안
본다. 실측 4가 그래도 되게 만든다 — 디스크가 없으면 `/config`는 tmpfs의 빈
디렉터리이고, 도구 둘은 거기에 조용히 쓴다. 사라지지만 에러가 안 나고, 에러가
안 나는 것이 화면 좌표를 지키는 것이다.

`/config/xdg`는 init이 만든다 — 디스크를 붙였을 때 `seedRcFiles` 옆에서
`mkdir` 한 번이다. fish와 zoxide가 스스로 만들기도 하지만(실측 4), `HISTFILE`의
부모는 아무도 안 만든다. 그래서 히스토리 파일을 `/config/history/` 아래가
아니라 `/config` 바로 아래(`/config/zsh_history`)에 둔다 — 디렉터리를 만들
필요가 없고, `tars.conf`·`gitconfig`와 같은 평면이다.

## Milestone 셋

| | 무엇 | 검증 |
|---|---|---|
| SM-M0 | 도구 둘이 선다. 훅 없음 | `tools/check.sh`가 목록을 보고 둘을 타이핑한다 — `fzf --filter`가 파일을 찾고 `zoxide query`가 방금 넣은 것을 돌려준다 |
| SM-M1 | 훅이 걸린다(결정 5·6·7·10·11) | 호스트 검사가 허용 목록 양방향 + 덮개를 본다 · `config/check.sh`가 부팅 둘을 더해(6차 수리 · 7차 증명) 아무도 `zoxide add`를 안 쳤는데 `z`가 돈다 |
| SM-M2 | 배운 것이 남는다(결정 2·3·4·9) | `config/check.sh` 8차 부팅이 이전 부팅에서 배운 디렉터리와 명령을 찾는다 |

M1의 훅 증명 부팅이 M2 없이도 도는 이유를 적어 둔다 — 결정 2의
`XDG_DATA_HOME`이 없으면 `zoxide`는 `$HOME/.local/share/zoxide/db.zo`로
떨어지고, 홈은 tmpfs지만 한 부팅 안에서는 멀쩡히 쓰고 읽는다(실측 3).
그래서 M1은 *"훅이 걸렸다"*를, M2는 *"부팅을 넘어 남는다"*를 각각 따로
증명한다. 7차의 판정 글자는 M2에서도 안 바뀐다 — 바뀌는 것은 그 DB가 어느
파일시스템에 있는지뿐이다.

> M2를 쓰는 사람이 먼저 읽을 것. 7차가 DB에 넣는 것은
> `/usr/share/terminfo/x` 하나이고, M2가 `XDG_DATA_HOME`을 켜면 그 하나가
> 8차까지 살아남는다. 그래서 8차는 `cd`를 한 번도 안 치고 `z terminfo x`
> → `pwd`만으로 판정할 수 있다 — 7차가 8차를 진짜로 만든다.

M0이 훅 없이 한 단계인 이유는 UT가 세 번 배운 것이다 — *"검사를 넣었으면
그것이 죽는 경우를 직접 만들어 봐야 한다. 다른 검사가 먼저 죽으면 그 검사는
아직 아무것도 증명하지 않았다."* 훅과 바이너리를 한 milestone에 넣으면
`zoxide query`가 실패했을 때 바이너리가 안 돈 것과 훅이 안 걸린 것이
안 갈린다.

`CLAUDE.md`대로 각 milestone의 plan은 그 시점에 새로 쓴다.

## 위험

### 위험 1 — 훅이 부팅할 때 한 글자라도 찍으면 다섯 체인의 화면이 밀린다

실측 13이 적은 규칙의 대상이 이번에는 우리가 넣는 훅이다. 실측 5·6이
stderr 0바이트를 쟀고 `zoxide`의 훅이 `chpwd`에만 걸린다는 것도 쟀다. 그래도
게이트의 첫 회차가 이것의 진짜 검사다 — 설정 디스크를 붙이는 다섯 체인 중
셋이 화면의 셀 좌표로 판정한다.

부분적 처방이 이미 있다: 실패가 "화면이 밀렸다"로 나타나면 훅을 씨앗에서
빼고 다시 돌려 훅이 원인인지를 한 번에 가릴 수 있다(결정 6의 역방향 검사가
그 상태를 호스트에서 먼저 잡으므로, 가릴 때는 그 검사도 함께 끈다).

### 위험 2 — `fzf`가 Tab을 자동완성 위젯으로 뺏는다

실측 8이 "지금은 안 겹친다"를 쟀다. 앞으로 `tab`을 치려는 사람이 이 줄을 볼
자리다 — 게이트가 Tab을 치면 그 순간부터 fzf가 그 키를 받는다.

### 위험 3 — zsh 두 세션이 같은 `HISTFILE`을 겹쳐 쓴다

실측 10이 근거다. bash는 append하고 zsh는 나갈 때 파일을 다시 쓴다. 콘솔 셸과
화면 셸이 동시에 살아 있고 둘 다 zsh면, 뒤에 나간 쪽의 목록이 이긴다.

고치려면 `setopt APPEND_HISTORY`가 필요하고 그것은 결정 6의 허용 목록을 세
줄로 넓히는 일이다. 이번에는 알고 둔다 — 위험을 아는 것과 고치는 것이
다르고, 이 서브프로젝트가 먼저 증명할 것은 "남는다"다.

> ⚠ 정정(2026-09-12, SD design 실측 1·5) — 이 위험이 실재하지 않는다.
> `APPEND_HISTORY`는 zsh의 기본값이라 넣어도 바뀌는 것이 없고, 두 세션은
> 서로를 지우지 않는다. 이 자리를 재려고 시작한 서브프로젝트가 대신 찾은
> 진짜 문제는 *"세션이 살아 있는 동안 파일에 아무것도 없다"*이고, 그것을
> 고치는 옵션은 `INC_APPEND_HISTORY`다.
> 본문은 `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`.

### 위험 4 — initrd가 5.54MB 커진다

UT-M2가 배운 것이 여기 걸린다: initramfs는 tmpfs라 푼 크기가 통째로 RAM에
남는다. 그때 84MB에서 기본 128MiB가 panic이었고 `gate_lib.sh`의
`GUEST_MEM=512`가 그 처방이었다 — 그 여유가 이미 서 있다. M0에서 gzip 뒤
증가분과 프롬프트까지의 시간을 잰다.

### 위험 5 — 게이트가 부팅 둘만큼 늘어난다

기준선은 SC-M2의 열한 체인 3/3 = 25분 58.09초다. `config/check.sh`가
부팅 다섯에서 일곱이 되고, 6·7차는 화면을 폴링으로 기다릴 수 있어(찾을 글자가
있어야 할 것이다) SC-M2의 4·5차처럼 8초를 고정으로 쓰지 않는다. +40초
안쪽으로 본다.

## 참고

- SC design: `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
  (비목표 1·2가 이 문서의 입구다)
- UT design: `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
  (비목표 5·6 · 도구 조달 절차 · 실측 26)
- 기억: `docs/decisions/project_shell_config.md` ·
  `docs/decisions/project_userland_tools.md` ·
  `docs/decisions/project_guest_environment.md`
