# SM-M1 Implementation Plan — 훅이 걸린다

> 완료: 2026-09-12. Task 아홉 전부. 게이트는 27분 05.06초, 18 PASS /
> 0 FAIL, 첫 회차에 통과했다.
>
> 이 plan이 두 군데에서 틀렸고 지우지 않고 남긴다.
>
> 1. Task 7의 "되돌림 C에서 `whence` 검사는 초록"이 관측되지 않는다.
>    첫 판정(`z`)이 죽으면 `probe_shell_hooks`가 그 자리에서 돌아오므로 둘째
>    판정에 안 닿는다. 독립성을 보여 준 것은 되돌림 D 하나다(`z` 초록 ·
>    위젯 빨강). 되돌림 둘의 비대칭을 plan이 안 봤다.
> 2. Task 4·7의 "각각 두 번"이 처방이 아니었다. 첫 회차가 거짓 초록인
>    이유가 `zig-out`이라는 것을 실행 중에 좁혔다(실측 32) — 그래서 절차가
>    "두 번 돌린다"에서 "돌리기 전에 `rm -rf init/zig-out`"으로 바뀌었다.
>    바뀐 뒤에는 첫 회차부터 빨강이다(넷 중 넷).
>
> 그리고 plan에 없던 것을 하나 했다 — 씨앗의 실제 바이트를 꺼내
> (`zig run`으로 `rcSeed()`를 찍어서) 그것으로 셸 셋을 띄워 봤다. 실측 23의
> 마지막 문단이 그것이고, 상수 문자열로 잰 것과 씨앗 1,382바이트로 잰 것이
> 같다는 확인이다.

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

Goal: 씨앗 rc 셋이 `zoxide`와 `fzf`의 훅을 담는다. 그리고 게이트가
아무도 `zoxide add`를 안 쳤는데 DB에 디렉터리가 들어가 있는 것을 본다 —
`cd` 한 번이 그것을 했다는 뜻이고, 그것이 "훅이 걸렸다"의 유일한 증거다.

Architecture: 새 파일이 하나도 없다. 고치는 파일이 셋이다.

| 파일 | 이 milestone에서 하는 일 |
|---|---|
| `init/src/config.zig` | `Shell.hookLines()`가 새로 서고, `rcSeed()` 셋이 그 두 줄을 담는다 |
| `init/src/config_test.zig` | `expectQuietSeed`를 정확 허용 목록 양방향으로 넓힌다(design 결정 6) |
| `config/check.sh` | 부팅 둘을 더한다 — 6차가 수리하고 7차가 훅을 증명한다 |
| `kernel/` · `terminal/` · `devcontainer/` | 안 고친다 |

Tech Stack: Zig 0.16(init) · bash(게이트 체인) · QEMU monitor `sendkey`

읽고 시작할 것:
`docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md` — 특히
실측 5·6(훅의 출력이 0바이트) · 실측 13(씨앗 문법이 둘로 막혀 있다) ·
결정 5(훅은 씨앗에 들어가고 기본이 켜짐) · 결정 6(정확 허용 목록) ·
결정 8(게이트는 둘로 나눠 보고 `config/check.sh`가 부팅을 더한다).

그리고 `init/src/config.zig`의 `rcSeed()` 머리 주석과
`init/src/config_test.zig`의 `expectQuietSeed` 머리 주석. 둘이 서로를
가리키고 있고, 이 milestone은 그 둘을 함께 넓힌다.

---

## 이 milestone을 지배하는 사실 둘

### 1. 씨앗이 한 글자라도 찍으면 다른 다섯 체인이 깨진다

설정 디스크를 붙이는 체인이 다섯이고(`config`·`input`·`power`·`hangul`·
`machine`) 그중 셋이 화면의 셀 좌표로 판정한다. 씨앗은 그 다섯 전부에서
읽히므로, 이 milestone의 가장 큰 위험은 "훅이 안 돈다"가 아니라 "훅이 한
줄 찍어서 엉뚱한 체인이 깨진다"다.

그래서 훅 두 줄에 관문(`command -v` / `type -q`)이 붙는다. 근거는 아래
실측 27이다 — 도구가 없을 때 관문 없는 훅은 zsh에서 50바이트, fish에서
191바이트(6줄)를 찍는다.

### 2. 판정 글자가 타이핑한 명령줄에 있으면 그 검사는 훅이 죽어도 초록이다

M0이 세 번 밟은 자리다. design 결정 8의 6차 부팅 시퀀스가 이 함정에 걸려
있었다 — `cd /tmp` → `cd /` → `z tmp` → `pwd`로 `/tmp`을 보는 것인데,
`/tmp`은 방금 타이핑한 `cd /tmp`에 있다.

처방은 M0의 것을 그대로 쓴다. `..`를 지나는 경로를 `cd`하면 셸이 `$PWD`를
정규화하고, 훅이 그 정규형을 DB에 넣는다.

```
cd /usr/bin/../share/terminfo/x     ← 화면에 남는 글자는 `..`가 든 쪽이다
cd /
z terminfo x
pwd  →  /usr/share/terminfo/x       ← 이 글자를 만든 주체는 DB뿐이다
```

`tools/check.sh` 검사 18과 판정 글자가 같은 것에 뜻이 있다. 그 검사는
사람이 `zoxide add`를 쳤고, 이쪽은 아무도 안 친다. 둘의 차이가 정확히
"훅"이다.

---

## 부팅이 하나가 아니라 둘 늘어난다 — design이 못 본 것

design 결정 8은 M1이 6차 부팅 하나를 더한다고 적었다. 그럴 수 없다.

| 부팅 | 디스크의 `/config/zshrc` 상태 |
|---|---|
| 3차 | 끝에 `exit`를 심는다 — 일부러 죽는 rc |
| 4차 | 그 rc로 셸이 세 번 죽고 탈출로가 발동 |
| 5차 | `tars.noconfig`로 rc를 안 읽는다. 파일은 그대로 깨져 있다 |

6차가 그 디스크로 rc를 읽으면 셸이 죽고 탈출로가 rc 없이 되살린다 — 훅도
함께 안 걸린다. 그래서 M1은 부팅 둘을 더한다.

| 부팅 | cmdline | 하는 일 |
|---|---|---|
| 6차 | `tars.noconfig` | `rm /config/zshrc` — 깨진 rc를 지운다 |
| 7차 | 기본 | init이 다시 씨앗을 깐다(`O_EXCL`). 그 씨앗의 훅이 돈다 |

`sed`로 `exit` 한 줄만 지우지 않고 파일을 통째로 지우는 이유가 셋이다.

1. 7차의 rc가 정확히 우리 씨앗이다 — 게이트가 1차에서 손으로 더한
   `echo tars-rc-alive`도 없다. 증명 대상이 `rcSeed()`의 내용 그 자체가
   된다.
2. `seedRcFiles`의 `O_EXCL`이 "없으면 만든다"라는 것을 다시, 빈 디스크가
   아닌 자리에서 증명한다. 셋 중 하나만 지웠으므로 `seeded`는 한 줄만
   나와야 한다 — 그것이 `O_EXCL`의 정확한 계약이다.
3. 타이핑이 `rm`과 `ls` 둘로 끝난다.

6차가 `tars.noconfig`를 쓰는 것에도 뜻이 있다. SC-M2가 그 토큰을 만든
근거가 *"설정을 고칠 셸이 없을 때 쓰는 것"*이었다. M1이 그것을 실제로 그
용도로 쓴다 — 게이트가 자기 탈출로를 쓰는 첫 자리다.

⚠ 5차에 타이핑을 더하지 않는다. 그 부팅은 볼 것이 전부 "없어야 할 것"이라
아무것도 안 치도록 SC-M2가 정했고(`config/check.sh:594`), 거기에 수리를
얹으면 SC-M2의 증명과 SM-M1의 준비가 한 함수에서 엉킨다.

---

## Task 1: 훅의 침묵을 컨테이너에서 잰다 (완료 — 실측 23~28)

Files: 없음(측정만)

- [x] Step 1: 측정용 컨테이너를 띄운다

devcontainer에는 arm64 `zsh`·`fish`·`zoxide`·`fzf`가 없다(sysroot의
amd64 바이너리만 있다). 버릴 컨테이너에 arm64 것을 깔아서 잰다 — design의
실측 4~11이 쓴 방법과 같다.

```bash
docker run -d --name tars-measure tars-devcontainer sleep 3600
docker exec tars-measure bash -c 'apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fish zoxide fzf'
```

잰 버전: zsh 5.9 · fish 4.0.2 · zoxide 0.9.7 · fzf 0.60. 게스트의
amd64와 같은 Debian trixie 스냅샷이다.

- [x] Step 2: 실측 23 — 훅 두 줄은 셋 다 0바이트다

`script -qec`로 pty를 주고 대화형으로 띄운다(게스트의 셸은 PTY 위에 산다).

| 셸 | rc에 훅 두 줄 | stdout | stderr |
|---|---|---|---|
| zsh | `command -v … && eval "$(…)"` | 0 | 0 |
| bash | 같은 모양 | 0 | 0 |
| fish | `type -q … && … \| source` | 0 | 0 |

게스트의 TERM 둘로도 다시 쟀다 — 화면 셸은 `xterm-256color`, 시리얼 콘솔
셸은 `linux`다(`environ.zig`). `dumb`까지 셋 다 0바이트다.

- [x] Step 3: 실측 24 — `whence -w`의 답은 `widget`이 아니라 `function`이다

```
whence -w z                    → z: function
whence -w fzf-history-widget   → fzf-history-widget: function
```

design 결정 8은 명령만 적고 출력을 안 적었다. `zle -N`로 위젯이 되지만
`whence -w`가 보는 것은 그 이름의 함수다. 게이트의 판정 글자는
`fzf-history-widget: function`이다.

- [x] Step 4: 실측 25 — 훅이 걸린 zsh에서 `cd` 한 번이 DB를 채운다

```
zsh -i -c 'cd /usr/bin/../share/terminfo/x; cd /; z terminfo x; pwd'
  → /usr/share/terminfo/x          ← 출력이 이 한 줄이 전부다
```

`cd`도 `z`도 아무것도 안 찍는다. 그 한 줄을 찍은 것은 `pwd`이고, 그 값을
만든 것은 DB다. 7차 부팅이 그대로 쓰는 시퀀스다.

- [x] Step 5: 실측 26 — bash의 훅은 `cd`가 아니라 프롬프트에 걸린다

같은 시퀀스를 bash로 하면 `zoxide: no match found`가 나고 `pwd`가 `/`다.
`bash -i -c`는 프롬프트를 그리지 않으므로 `PROMPT_COMMAND`가 한 번도 안
돈다 — 버그가 아니라 훅 자리의 차이다(zsh는 `chpwd_functions`, fish는
`--on-variable PWD`). 게이트가 zsh로 판정하는 이유가 하나 늘었다.

- [x] Step 6: 실측 27 — 관문을 빼면 도구가 없을 때 시끄럽다

| 셸 | 관문 있음 | 관문 없음(도구가 없을 때) |
|---|---|---|
| zsh | 0바이트 | 50바이트 `.zshrc:1: command not found: …` |
| bash | 0바이트 | 38바이트 |
| fish | 0바이트 | 191바이트 / 6줄 |

이 표가 관문의 전부다. 씨앗이 한 줄 찍으면 다섯 체인의 셀 좌표가 밀린다.

- [x] Step 7: 실측 28 — 훅의 비용은 arm64에서 2ms다

대화형 zsh 기동이 25ms → 27ms(5회 평균, arm64 native). 파싱하는 양은
`zoxide init zsh` 4,569바이트 + `fzf --zsh` 19,545바이트다. 게스트는 TCG라
이것의 몇 배가 되지만, 부팅 한 번에 셸 둘이므로 초 단위로는 안 보일
크기다.

- [x] Step 8: 실측 29 — fzf가 뺏는 키 넷을 직접 다시 셌다

design 실측 8을 안 믿고 다시 셌다(`rg -o 'sendkey [a-z0-9-]+'` + type_keys
배열 전체).

```
fzf가 바인드하는 것: ^I(Tab) · ^T · ^R · \ec(Alt+C)   ← zsh·fish 둘 다 같다
게이트가 치는 것:    ctrl-c · ctrl-a · ctrl-l · alt-l · caps · ctrl ·
                     shift-spc · shift-home/end/pgup · ctrl-alt-delete · 글자들
```

겹치는 것이 없다. `tab`·`ctrl-r`·`ctrl-t`·`alt-c`는 저장소 어느
`check.sh`에도 한 번도 안 나온다.

---

## Task 2: `config.zig` — `hookLines()`와 씨앗 셋

Files:
- Modify: `init/src/config.zig` (`Shell` enum 안, `rcPath()`와 `rcSeed()`
  사이에 `hookLines()`를 넣고 `rcSeed()` 셋에 두 줄씩 더한다)

- [x] Step 1: 훅 목록을 상수로 세운다

`Shell.rcPath()` 바로 뒤, `rcSeed()` 앞에 `hookLines()`를 넣는다. 문자열은
컨테이너 상수 셋(`HOOKS_FISH`·`HOOKS_BASH`·`HOOKS_ZSH`)에 둔다.

씨앗의 글자와 여기 글자를 일부러 두 벌로 둔다. `rcSeed()`를 이 목록에서
`++`로 조립하면 두 벌이 하나가 되고 design 결정 6의 역방향 검사가
tautology가 된다 — 이 저장소가 반복해서 부딪친 "통과했다와 볼 것이 없었다를
가르는" 자리다(UT-M1의 정적 목록 검사가 같은 이유로 가짜였다). 두 벌을 잇는
것은 `config_test.zig`이고, 그것이 결정 6의 목적이다.

- [x] Step 2: 씨앗 셋에 훅 두 줄과 그 설명을 더한다

alias 둘 뒤에 붙인다. 머리 주석의 *"여기 있는 것이 주석과 alias뿐"*도
함께 고친다 — 그 문장이 틀린 채로 남으면 다음 사람이 이 규칙을 잘못
배운다.

- [x] Step 3: 컴파일

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build'
```

---

## Task 3: `config_test.zig` — 정확 허용 목록 양방향

Files:
- Modify: `init/src/config_test.zig` (`expectQuietSeed`)

- [x] Step 1: 검사를 셋으로 넓힌다

| | 무엇 | 무엇을 막나 |
|---|---|---|
| 정방향 | 비주석·비`alias` 줄은 `hookLines()`의 한 줄과 글자 그대로 같아야 한다 | 씨앗에 아무 문장이나 들어오는 것 |
| 역방향 | `hookLines()`의 전부가 씨앗에 있어야 한다 | 훅을 지우는 것이 통과하는 것 |
| 덮개 | 훅 목록이 `zoxide`와 `fzf` 둘을 다 덮어야 한다 | 두 자리에서 함께 지우는 것 |

셋째가 없으면 "둘 다 없애기"가 조용히 통과한다 — 씨앗과 `hookLines()`를
같이 고치면 정·역방향이 둘 다 만족되기 때문이다. 그 편집이 정당할 수도 있지만,
그때는 이 줄을 먼저 지워야 한다 — 손이 한 번 멈추는 자리를 만드는 것이
목적이다.

- [x] Step 2: 호스트에서 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

⚠ `zig build test`가 직전 내용의 결과를 낼 수 있다(SC가 세 번 봤다).
두 번 돌린다.

---

## Task 4: 호스트 음성 확인 둘 — 각각 두 번

Files: 없음(되돌렸다 복구)

- [x] 되돌림 A: 씨앗에 `echo` 한 줄 → 정방향이 잡는다
- [x] 되돌림 B: 씨앗에서 훅 한 줄을 지운다 → 역방향이 잡는다
- [x] 되돌림 B2: 훅을 `hookLines()`와 씨앗에서 함께 지운다 → 덮개가
      잡는다(`FAIL: no fzf hook line for the zsh seed`)

B가 이 milestone의 새 그물이고, B2는 plan에 없던 것을 더한 것이다 — 검사를
셋으로 만들었으면 셋째가 죽는 경우도 직접 만들어 봐야 한다. 안 만들면 그
검사는 아직 아무것도 증명하지 않았다(UT가 세 번 배운 것).

⚠ 여기서 `zig-out` 함정을 처음 봤다. A와 B2의 첫 회차가 `PASS`였고 둘째
회차가 잡았다. 그때는 SC가 적어 둔 *"두 번 돌릴 것"*으로 넘겼고, Task 7에서
범인을 좁혔다(실측 32). A·B·B2 셋 다 `rm -rf init/zig-out` 뒤에는 첫
회차부터 빨강이다.

---

## Task 5: `config/check.sh` — 부팅 둘

Files:
- Modify: `config/check.sh`

- [x] Step 1: 머리글 `/5` → `/7` 다섯 자리
- [x] Step 2: 키 배열 넷을 더한다(`RM_RC_KEYS`·`RM_READBACK_KEYS`·
      `HOOK_CD_KEYS`·`HOOK_Z_KEYS`·`WIDGET_KEYS`)
- [x] Step 3: 훅 함수 둘(`repair_broken_rc`·`probe_shell_hooks`)
- [x] Step 4: 부팅 6·7 블록

6차의 판정: `ls /config/zshrc` → `No such file`.
7차의 판정 둘: 행 첫머리 `/usr/share/terminfo/x` · 행 첫머리
`fzf-history-widget: function`.

7차의 부정 검사 셋이 함께 선다.

| 검사 | 무엇을 뜻하나 |
|---|---|
| `seeded /config/zshrc`가 있다 | `O_EXCL`이 없는 것을 다시 만들었다 |
| `seeded /config/bashrc`가 없다 | 있는 것은 안 건드렸다 |
| `tars-rc-alive`가 없다 | 7차의 rc는 사람이 손댄 적 없는 우리 씨앗이다 |
| `times fast`가 없다 | 훅이 셸을 안 죽였다 |

---

## Task 6: config 체인 단독 실행

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh 2>&1 | tail -40
```

- [x] Step 1: 통과할 때까지 (부팅 일곱, 기준선을 적는다)

---

## Task 7: 게스트 음성 확인 둘 — 각각 두 번

"훅이 걸렸다"를 판정하는 것이 진짜인지 본다. 훅 한 줄만 죽이면
나머지 하나의 검사는 초록이어야 한다 — 그것이 두 판정이 서로 독립이라는 뜻이다.

- [x] 되돌림 C: zoxide 훅의 관문을 없는 이름으로(`command -v zoxide-nope`).
      `hookLines()`와 씨앗을 함께 고친다.
      기대: `z`가 못 돌고 7차가 빨강. `whence` 검사는 초록.

⚠ plan이 틀렸다 — 셋.

(가) 덮개 검사를 끌 필요가 없었다. `zoxide-nope`에는 `zoxide`가 부분
문자열로 들어 있어서 그 검사를 그대로 지나간다. 관문 이름을 고르는 방식이
되돌림을 싸게 만든 것이고, 그것은 운이었다.

(나) `whence` 검사가 초록인 것을 볼 수 없다. 첫 판정이 죽으면
`probe_shell_hooks`가 그 자리에서 돌아온다 — 독립성을 보여 주는 것은 아래
되돌림 D 하나다.

(다) 첫 시도의 편집이 한쪽만 고쳤다. `perl -pi`의 정규식이 상수 쪽
(`eval \"…\"` — 백슬래시가 있다)과 씨앗 쪽(`eval "…"`)을 같은 패턴으로 잡으려
했다. 그래서 씨앗만 바뀌고 `hookLines()`는 안 바뀌었고, 호스트 검사가 그것을
잡았다 — 내가 만들려던 실패가 아니라 정방향 검사가 자기 일을 한 것이다.
고친 뒤 다시 했다.

관측된 것(두 번 다 같다):

```
(none)# z terminfo x
zsh: command not found: z
(none)# pwd
/
FAIL(boot 7): nobody typed 'zoxide add', and z did not walk back to …
```

- [x] 되돌림 D: fzf 훅만 같은 식으로. 기대: `z`는 초록,
      `whence -w`가 빨강. 두 번 다 그대로 나왔다 — 이것이 판정 둘의
      독립성이다.

넷 다 `rm -rf init/zig-out`을 앞에 두고 돌렸고, 넷 다 첫 회차부터
빨강이었다(실측 32).

---

## Task 8: 루트 게이트 (약 27분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [x] Step 1: 3/3
- [x] Step 2: 세는 것 — `Welcome to fish`가 6(회귀 없음) ·
      `command not found`가 0 · 새 `echo` 줄 셋이 각 3

⚠ 다섯 체인 전부가 씨앗을 새로 받는다. 훅이 한 줄이라도 찍으면
`input`·`power`·`hangul`·`machine` 중 하나가 깨진다 — 그것이 이 게이트가
보는 가장 중요한 것이고, 실측 23이 예측하는 것은 "안 깨진다"다.

---

## Task 9: 문서

- [x] design의 실측 23~29 · 결정 10(두 벌로 두는 이유) · 결정 8의 정정
      (부팅이 둘 늘고 시퀀스가 `..`로 바뀌었다)
- [x] `docs/decisions/project_shell_memory.md`
- [x] `MEMORY.md` · `CLAUDE.md` · `HANDOFF.md`
- [x] 이 plan의 체크박스

---

## 이 milestone이 안 하는 것

| | 왜 |
|---|---|
| `XDG_DATA_HOME`·`HISTFILE`·`HISTSIZE`·`SAVEHIST` | M2다(결정 3) |
| `/config/xdg`를 만드는 것 | 같다(결정 9) |
| 8차 부팅(부팅을 넘어 기억한다) | 같다 |
| `grep -q` 다섯 자리 | M0이 남긴 숙제. `config/check.sh:552`가 다음 후보 |
| 위험 3(zsh 두 세션의 겹쳐 쓰기) | 알고 둔다. `setopt`은 허용 목록을 한 줄 더 넓히는 일이다 |
