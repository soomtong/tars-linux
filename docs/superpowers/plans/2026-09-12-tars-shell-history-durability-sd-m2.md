# SD-M2 Implementation Plan — 게이트가 그 한 줄이 하는 일을 본다

> 완료: 2026-09-12. Task 일곱 전부. config 체인 단독 1분 36.42초에 `FAIL`
> 없음, 반사실이 7차에서 죽었고, 루트 게이트 3/3.
>
> 사용자가 이 milestone부터 편집까지 위임했다 — "검증에 대한 부분이 많으니
> Claude Code가 직접 진행"이고, 근거는 리눅스 시스템 빌드와 타이핑을 이미
> 충분히 해 봐서 코드를 읽는 자리의 값이 편집하는 자리보다 크다는 것이다.
>
> plan이 두 군데에서 틀렸고 지우지 않고 남긴다.
>
> 1. Task 5가 마운트 하나로 된다고 적었는데 둘이 필요했다. 씨앗에서 그 줄을
>    빼면 SD-M1의 역방향 검사가 부팅 전에 죽여서 게이트가 7차까지 못 간다.
>    `config_test.zig`의 그 loop 한 줄(`if (seen_opt[i] or true) continue;`)도
>    함께 눕혀야 반사실이 게이트에 닿는다. M1이 값을 한다는 증거다.
> 2. Task 5 Step 2의 기대값이 틀렸다. *"앞의 둘은 초록이고 셋째에서 죽는다"*로
>    적었는데 실제로는 첫째(`neg0`)에서 죽었다 — 옵션이 없으면 그 시점에
>    `/config/zsh_history`가 아예 없어서 `grep`이 에러를 내고 `echo`가 숫자
>    없는 `neg`를 찍는다. design 실측 16이 그 화면이다.

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: `config/check.sh` 7차 부팅이 중첩 zsh 둘로 음성·양성 대조군을 만들어,
씨앗 rc의 `setopt INC_APPEND_HISTORY` 한 줄이 게스트에서 실제로 하는 일을
판정한다. 그리고 SM-M2가 우회로 넣은 `fc -W`를 뺀다 — 옵션이 켜지면 필요
없고(실측 6), 다른 세션이 써 둔 줄을 지우므로 이 검사 자신을 망가뜨린다
(실측 10).

Architecture: 새 파일이 없고 고치는 파일이 하나다.

| 파일 | 이 milestone에서 하는 일 |
|---|---|
| `config/check.sh` | 상수 둘을 여섯으로 갈고, 7차 probe의 마지막 블록을 판정 셋으로 바꾸고, 8차의 판정 글자를 옮긴다 |
| `init/src/` · `terminal/` · `kernel/` | 안 고친다. SD-M1이 넣은 코드가 그대로 증명 대상이다 |
| `gate_lib.sh` · `check.sh` | 안 고친다. 체인이 늘지도 줄지도 않는다 |

Tech Stack: bash(게이트 체인) · QEMU monitor `sendkey` · `wait_for_screen`
(`gate_lib.sh`) · zsh(게스트 셸)

읽고 시작할 것:
`docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md` —
결정 5(음성 대조군의 모양) · 확인 2(게이트는 셸이 나갈 때를 영영 못 본다) ·
확인 3(중첩 zsh면 콘솔 셸을 안 끌어와도 된다) · 실측 10·11·12.

그리고 고칠 자리의 소스 셋. `config/check.sh`의 `── SM-M2 ──` 상수 블록 ·
`probe_shell_hooks`의 마지막 블록 · `probe_persisted_memory`의 판정 3.

---

## 이 milestone을 지배하는 사실 넷

### 1. `fc -W`는 남의 줄을 지운다 — 그래서 먼저 빠져야 한다

실측 10이 쟀다. 세션 A가 `fc -W`를 치면 파일이 A의 메모리 목록으로 덮어써지고
B가 써 둔 줄이 사라진다. 이 milestone이 만드는 것이 바로 "같은 파일을 보는
세션 둘"이므로, 그 명령을 남겨 두면 검사가 자기 재료를 지운다.

뺄 수 있는 이유는 SD-M1이 넣은 줄이다. 옵션이 켜지면 명령을 칠 때 이미
파일에 있으므로, 게이트가 전원을 뽑아도 8차가 읽을 것이 디스크에 남는다.
SM-M2가 `게이트는 전원을 뽑는다`를 이유로 넣은 우회가 이 옵션과 함께
없어지는 것이다.

### 2. 판정은 세션이 살아 있는 동안 해야 한다

실측 11의 다섯째 행이 계약이다. 옵션을 끈 세션도 `exit`할 때는 자기 목록을
append한다 — 나간 뒤에 세면 음성과 양성이 같은 숫자가 된다.

| 단계 | 파일의 줄 수 |
|---|---|
| 중첩에서 `unsetopt INC_APPEND_HISTORY` | 3 |
| 중첩에서 `echo neg_one` | 3 — 안 자랐다 |
| 중첩이 `exit`으로 나갔다 | 6 — 여기서 한꺼번에 들어온다 |

### 3. 앵커가 없으면 `grep`이 자기를 센다

옵션이 켜져 있으면 판정에 쓰는 `grep`의 명령줄이 실행 전에 파일에 써진다
(실측 11). 그래서 패턴은 줄 전체 일치여야 한다. 이 plan은 `^…$` 대신
`grep -x`를 쓴다 — 같은 뜻인데 게스트에 따옴표를 안 쳐도 되고, `sendkey`로
치는 키가 넷 줄어든다.

앵커가 없으면 음성 기대값이 0이 아니라 1이 되고, 그 검사는 아무것도 안 보면서
초록이 된다.

### 4. "없다"는 증거가 아니다 — 그래서 판정이 셋이다

음성 검사가 보는 것은 "파일에 그 줄이 없다"이고, 그것만으로는 *"아직 안
썼다"*와 *"애초에 안 쳐졌다"*가 안 갈린다. SD-M0이 첫 회차를 정확히 그것으로
버렸고, HANDOFF의 "시도했으나 안 되는 접근"에 그 항목이 있다.

그래서 음성 세션이 나간 뒤에 한 번 더 센다. 나가면서 append된 것이 보이면
그 명령은 분명히 쳐진 것이고, 그러면 앞의 0은 "아직 안 썼다"가 맞다.

| 판정 글자 | 언제 | 무엇을 말하나 |
|---|---|---|
| `neg0` | 음성 세션이 살아 있는 동안 | 옵션을 끈 세션이 친 명령은 파일에 없다 |
| `aft1` | 음성 세션이 나간 뒤 | 그 명령은 분명히 쳐졌다 — 위의 0이 진짜다 |
| `pos1` | 양성 세션이 살아 있는 동안 | 옵션이 켜진 세션이 친 명령은 그 자리에서 파일에 있다 |

## 판정 글자를 우리가 만드는 이유

`grep -c`의 출력은 `0`이나 `1` 한 글자다. 화면 어디에나 있을 수 있는 모양이고,
`wait_for_screen`은 마지막 프레임이 아니라 로그 전체를 보므로 앞선 프레임의
무언가에 걸릴 여지가 있다. 그리고 중첩 zsh는 한 글자도 안 찍고 프롬프트가
바깥과 글자 그대로 같아서(실측 12) 프롬프트로는 아무것도 못 가른다.

그래서 숫자를 `echo neg$(…)`로 감싼다. 화면에 `neg0`이 뜨고, 그 글자를 만들 수
있는 것은 이 `echo` 하나뿐이다 — 타이핑한 명령줄에는 `neg$(grep`까지만 있다.
실패했을 때 화면에 `neg1`이 남는 것도 값이다. 어느 쪽으로 틀렸는지가 로그
한 줄에 찍힌다.

표적은 `negmark=1`·`posmark=1`이다. 변수 대입이라 아무것도 안 찍고, 공백이
없어서 `grep -x`의 패턴에 따옴표가 필요 없다.

## 8차의 판정 글자를 옮기는 이유

8차는 `history`를 인자 없이 친다. zsh는 그것을 최근 16개로 자른다(실측 36).

지금 판정 글자는 7차의 `whence -w fzf-history-widget`인데, 이 milestone이
7차의 히스토리 뒤에 줄을 여럿 더한다.

```
… whence -w fzf-history-widget        ← 지금의 판정 글자
   zsh
   unsetopt INC_APPEND_HISTORY        ┐ 음성 세션이 나가면서
   negmark=1                          │ 한꺼번에 append한다
   echo neg$(grep -cx negmark=1 …)    │
   exit                               ┘
   echo aft$(grep -cx negmark=1 …)
   zsh
   posmark=1                          ← 새 판정 글자
   echo pos$(grep -cx posmark=1 …)
```

거기에 8차 자신이 치는 넷(`z`·`pwd`·`ls`·`history`)이 더 붙는다. 옛 판정
글자는 창 16 밖으로 밀려나고, 새 것은 끝에서 여섯째쯤이다.

옮겨도 검사의 뜻이 안 바뀐다. `posmark=1`을 친 것은 7차뿐이고 8차는 그 글자를
만들 방법이 없다 — 오히려 증명이 더 정확해진다. 옛 글자는 `fc -W`가 쓴
것이었고 새 글자는 옵션이 칠 때마다 쓴 것이라, 8차가 판정하는 대상이
이 서브프로젝트가 넣은 그 줄이 된다.

---

## Task 1: 7차가 칠 것들을 상수로 갈아 끼운다

Files:
- Modify: `config/check.sh` (`── SM-M2 ──` 상수 블록)

- [ ] Step 1: 지울 것 — `HIST_WRITE_KEYS`와 `HIST_COUNT_KEYS`의 블록 전부

`# ── SM-M2 ──`로 시작해서 `HIST_COUNT_KEYS=(…ret)`로 끝나는 20줄이다.
바로 아래 `# ── 8차 부팅이 치는 셋 ──`이 오므로 그 줄은 남긴다.

```bash
# ── SM-M2 ───────────────────────────────────────────────────────────────
#
# 게이트는 전원을 뽑는다. boot_once가 마커를 보면 `kill "$QEMU_PID"`로
# 기계를 끝내므로 셸이 나갈 때 하는 일이 하나도 안 일어난다. zsh는
# SIGTERM·SIGHUP을 받으면 HISTFILE을 쓰지만(실측 34) QEMU가 죽으면 그 신호도
# 안 온다 — 실기의 전원 버튼에서는 저장되고, 여기서만 안 된다.
#
# 그래서 7차가 직접 쓴다. `fc -W`는 히스토리 목록을 그 자리에서 파일에 쓴다.
#
# ⚠ 이 저장소가 대문자를 처음 친다. `sendkey`에 대문자 키 이름은 없지만
# `shift-w`는 있고, 게스트의 keymap이 `.{ 'w', 'W' }`를 갖고 있다
# (`terminal/src/input.zig:47`). 안 먹으면 화면에 `fc: bad option`이 뜨고 바로
# 아래 되읽기가 빨개진다 — 실패가 그 자리에서 보인다.
HIST_WRITE_KEYS=(f c spc minus shift-w ret)
# wc -l /config/zsh_history — 되읽기. 판정 글자는 wc가 만드는 숫자다.
# GNU wc는 파일이 하나면 앞에 공백을 안 넣으므로(실측 35) 행의 첫머리가
# 숫자인 줄은 이 출력뿐이고, 방금 타이핑한 줄은 프롬프트로 시작한다.
# 밑줄은 shift-minus다(OFF_KEYS가 쓰고 있는 그 키다).
HIST_COUNT_KEYS=(w c spc minus l spc slash c o n f i g slash
                 z s h shift-minus h i s t o r y ret)
```

- [ ] Step 2: 넣을 것 — 그 자리에 SD-M2의 상수 여섯

```bash
# ── SD-M2 ───────────────────────────────────────────────────────────────
#
# SM-M2는 여기서 `fc -W`를 쳤다. 게이트가 전원을 뽑으므로(boot_once의
# `kill "$QEMU_PID"`) 셸이 나갈 때 하는 일이 하나도 안 일어나고, 8차가 읽을
# 파일을 7차가 손으로 써 두어야 했다.
#
# 그 줄이 이제 없다. 이유가 둘이다.
#
#   1. 필요 없다. 씨앗 rc의 `setopt INC_APPEND_HISTORY`가 명령을 칠 때마다
#      그 자리에서 파일에 쓴다(SD 실측 6). 전원을 뽑는 시점에 8차가 읽을
#      것이 이미 디스크에 있다.
#   2. 해롭다. `fc -W`는 메모리의 목록으로 파일을 통째로 덮어쓰므로 다른
#      세션이 써 둔 줄을 지운다(SD 실측 10). 아래가 같은 파일을 보는 세션
#      둘을 만드는 검사라, 그 명령을 남겨 두면 검사가 자기 재료를 지운다.
#
# 대신 이 부팅이 중첩 zsh 둘로 음성·양성 대조군을 만든다(SD 결정 5). 둘 다
# 같은 씨앗 rc를 읽으므로 production과 같은 모양이고, 다른 것은 첫 명령
# 한 줄뿐이다. 콘솔 셸을 끌어오지 않는 이유는 SD 확인 3에 있다 — 중첩이
# 같은 경합을 만들고, FIFO는 이 체인의 골격을 바꾼다.
NEST_KEYS=(z s h ret)
# unsetopt INC_APPEND_HISTORY — 음성 세션의 첫 명령이자 음성이 양성과 다른
# 유일한 줄. 대문자는 shift-<글자>이고 밑줄은 shift-minus다(SM-M2가 `fc -W`의
# W를 그 수법으로 쳤다).
NEG_UNSET_KEYS=(u n s e t o p t spc
                shift-i shift-n shift-c shift-minus
                shift-a shift-p shift-p shift-e shift-n shift-d shift-minus
                shift-h shift-i shift-s shift-t shift-o shift-r shift-y ret)
# negmark=1 / posmark=1 — 세는 대상. 변수 대입이라 화면에 한 글자도 안 찍고,
# 공백이 없어서 아래 `grep -x`의 패턴에 따옴표가 필요 없다.
NEG_MARK_KEYS=(n e g m a r k equal 1 ret)
POS_MARK_KEYS=(p o s m a r k equal 1 ret)
# echo neg$(grep -cx negmark=1 /config/zsh_history) — 판정 글자를 우리가
# 만든다. 화면에 `neg0`이 뜨고, 그 글자를 만들 수 있는 것은 이 echo 하나다
# (타이핑한 줄에는 `neg$(grep`까지만 있다).
#
# 왜 숫자를 그대로 안 보나. `grep -c`의 출력은 한 글자라 화면 어디에나 있을
# 수 있는 모양이고, wait_for_screen은 마지막 프레임이 아니라 로그 전체를
# 본다. 그리고 중첩 zsh는 한 글자도 안 찍고 프롬프트가 바깥과 같아서
# (SD 실측 12) 프롬프트로는 아무것도 못 가른다.
#
# 왜 `-x`인가. 옵션이 켜져 있으면 이 grep의 명령줄이 실행 전에 파일에
# 써진다(SD 실측 11). 줄 전체 일치가 아니면 패턴이 자기를 세고, 음성
# 기대값이 0이 아니라 1이 되어 검사가 조용히 죽는다. `^…$`와 같은 뜻인데
# 따옴표를 안 쳐도 된다.
NEG_COUNT_KEYS=(e c h o spc n e g shift-4 shift-9
                g r e p spc minus c x spc n e g m a r k equal 1 spc
                slash c o n f i g slash z s h shift-minus h i s t o r y
                shift-0 ret)
POS_COUNT_KEYS=(e c h o spc p o s shift-4 shift-9
                g r e p spc minus c x spc p o s m a r k equal 1 spc
                slash c o n f i g slash z s h shift-minus h i s t o r y
                shift-0 ret)
# echo aft$(grep -cx negmark=1 /config/zsh_history) — 음성 세션이 나간 뒤에
# 같은 표적을 한 번 더 센다. 이것이 없으면 위의 `neg0`은 "아직 안 썼다"와
# "애초에 안 쳐졌다"를 못 가른다(SD-M0이 첫 회차를 그것으로 버렸다).
# 나가면서 append된 것이 보이면 그 명령은 분명히 쳐진 것이다(SD 실측 11의
# 다섯째 행).
AFT_COUNT_KEYS=(e c h o spc a f t shift-4 shift-9
                g r e p spc minus c x spc n e g m a r k equal 1 spc
                slash c o n f i g slash z s h shift-minus h i s t o r y
                shift-0 ret)
# exit — 음성 세션에서 나온다. 양성 세션은 안 나온다(probe가 돌아가면
# boot_once가 전원을 뽑는다). 나오지 않는 편이 8차가 읽을 표적을 파일 끝에
# 더 가깝게 둔다.
EXIT_KEYS=(e x i t ret)
```

- [ ] Step 3: 넣은 것을 눈으로 확인한다

```bash
git -C /Users/dp/Repository/tars-linux diff --stat config/check.sh
git -C /Users/dp/Repository/tars-linux diff config/check.sh | grep '^-' | head -30
```

Expected: 지운 줄이 정확히 위 Step 1의 20줄 + `-–`로 시작하는 diff 머리
한 줄. 다른 상수(`HOOK_*`·`XDG_LS_KEYS`·`HISTORY_KEYS`)가 지운 줄에 섞이면
자리를 잘못 잡은 것이다.

---

## Task 2: 7차 probe의 마지막 블록을 판정 셋으로 바꾼다

Files:
- Modify: `config/check.sh` (`probe_shell_hooks`의 `── SM-M2: 8차가 읽을 것을
  여기서 디스크에 쓴다 ──` 블록)

- [ ] Step 1: 지울 것 — `fc -W` 블록 전부(`return 0` 앞까지)

```bash
  # ── SM-M2: 8차가 읽을 것을 여기서 디스크에 쓴다 ──────────────────────
  #
  # 게이트가 전원을 뽑기 때문에 필요한 두 줄이다(실측 34). 실기에서
  # 전원 버튼을 누르면 PID 1의 SIGTERM이 셸에게 가고 zsh가 스스로 쓴다 —
  # 여기서만 그 신호가 없다.
  #
  # `fc -W`는 아무것도 안 찍으므로 되읽기가 따로 필요하다. 그 되읽기가
  # 없으면 이 줄이 실패했을 때 8차가 빨간 이유가 "안 썼다"인지 "안
  # 읽었다"인지 안 갈린다 — M1이 부팅을 둘로 나눈 것과 같은 이유다.
  type_keys "${HIST_WRITE_KEYS[@]}"
  type_keys "${HIST_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| [1-9][0-9]* /config/zsh_history'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 7): 'fc -W' left no history file for the eighth boot to read"
    echo "  둘 중 하나다 — HISTFILE/SAVEHIST가 셸에 안 갔거나(init의 env),"
    echo "  대문자 W가 게스트에 안 닿았다. 아래 마지막 화면에 'bad option'이"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the shell wrote its history to the config disk before the power was cut"
  return 0
}
```

- [ ] Step 2: 넣을 것 — 같은 자리에 판정 셋

```bash
  # ── SD-M2: 그 한 줄이 게스트에서 실제로 하는 일을 본다 ────────────────
  #
  # 중첩 zsh 둘이 음성·양성 대조군이다(SD 결정 5). 둘 다 같은 씨앗 rc를
  # 읽고, 다른 것은 음성이 첫 명령으로 옵션을 끄는 것 하나뿐이다. 그래서
  # 이 셋이 증명하는 것이 "우리가 넣은 그 줄이 차이를 만든다"가 된다.
  #
  #   neg0  옵션을 끈 세션이 친 명령은 살아 있는 동안 파일에 없다
  #   aft1  그 세션이 나가면서 append했다 — 그러니 그 명령은 분명히 쳐졌다
  #   pos1  옵션이 켜진 세션이 친 명령은 치는 그 자리에서 파일에 있다
  #
  # 가운데 것이 왜 있는가. neg0만 보면 "아직 안 썼다"와 "애초에 안 쳐졌다"가
  # 안 갈린다 — SD-M0이 첫 회차를 정확히 그것으로 버렸다.
  #
  # ⚠ 순서가 계약이다. 옵션을 끈 세션도 나갈 때는 자기 목록을 append하므로
  #   (SD 실측 11의 다섯째 행) 음성 판정은 그 세션이 살아 있는 동안 해야
  #   한다. 나간 뒤에 세면 음성과 양성이 같은 숫자가 된다.
  type_keys "${NEST_KEYS[@]}"
  type_keys "${NEG_UNSET_KEYS[@]}"
  type_keys "${NEG_MARK_KEYS[@]}"
  type_keys "${NEG_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| neg0'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): the session that turned the option off still wrote its command to the history file"
    echo "  화면에 neg1이 있으면 unsetopt가 안 먹은 것이다(이름이 틀렸거나"
    echo "  그 줄이 게스트에 안 닿았다). neg라는 글자가 아예 없으면 그 앞의"
    echo "  타이핑이 셸에 안 닿았다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: with the option unset, a typed command is not in the file while that session lives"

  type_keys "${EXIT_KEYS[@]}"
  type_keys "${AFT_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| aft1'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): the negative session's command never reached the file, so the check above saw nothing"
    echo "  화면에 aft0이 있으면 그 명령이 애초에 안 쳐진 것이고, 그러면"
    echo "  위의 neg0은 옵션과 아무 상관이 없다. 중첩 zsh가 떴는지부터 본다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: that same command did land when the session left, so the zero above meant 'not yet written'"

  type_keys "${NEST_KEYS[@]}"
  type_keys "${POS_MARK_KEYS[@]}"
  type_keys "${POS_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| pos1'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 7): with the seeded option on, a typed command was not in the history file yet"
    echo "  화면에 pos0이 있으면 씨앗의 setopt 줄이 안 걸린 것이다 — 그 줄이"
    echo "  없거나(rcSeed), 셸이 rc를 안 읽었거나, 옵션 이름이 틀렸다."
    echo "  이 줄이 SD가 넣은 그 한 줄을 게이트가 보는 유일한 자리다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the seeded option put a typed command on the config disk the moment it was typed"
  return 0
}
```

- [ ] Step 3: 지운 줄을 직접 읽어서 확인한다

```bash
git -C /Users/dp/Repository/tars-linux diff config/check.sh | grep '^-' | grep -v '^---'
```

Expected: Task 1의 20줄과 Task 2의 26줄만 나온다. `probe_shell_hooks`의 앞
블록(`z`·`pwd`·`whence`)이나 `probe_persisted_memory`의 줄이 섞이면 안 된다.

---

## Task 3: 8차의 판정 글자를 `posmark=1`로 옮긴다

Files:
- Modify: `config/check.sh` (`probe_persisted_memory` 머리 주석과 판정 3)

- [ ] Step 1: 지울 것 — 머리 주석의 셋째 줄

```bash
#   3. history에 있다  → 나갈 때 쓰는 파일을 7차가 fc -W로 대신 썼다
```

- [ ] Step 2: 넣을 것 — 그 자리에

```bash
#   3. history에 있다  → 7차가 칠 때마다 쓴 줄이 전원을 넘었다(SD-M2)
```

- [ ] Step 3: 지울 것 — 판정 3의 주석과 판정 줄

```bash
  # ── 3. 쳤던 명령 ───────────────────────────────────────────────────────
  #
  # 판정 글자가 행의 첫머리가 아니다. `history`의 출력은 네 칸 들여쓴
  # 번호로 시작하기 때문이다(실측 36). 그래도 이 검사가 진짜인 이유는 같다 —
  # `whence -w fzf-history-widget`은 이 부팅에서 아무도 안 친다. 8차가
  # 치는 것은 `z`·`pwd`·`ls`·`history` 넷뿐이고, 그 글자를 화면에 만들 수
  # 있는 것은 7차가 쓰고 간 파일 하나다.
  type_keys "${HISTORY_KEYS[@]}"
  local ok=0
  if wait_for_screen 'whence -w fzf-history-widget'; then ok=1; fi
```

- [ ] Step 4: 넣을 것 — 그 자리에

```bash
  # ── 3. 쳤던 명령 ───────────────────────────────────────────────────────
  #
  # 판정 글자가 행의 첫머리가 아니다. `history`의 출력은 네 칸 들여쓴
  # 번호로 시작하기 때문이다(실측 36). 그래도 이 검사가 진짜인 이유는 같다 —
  # `posmark=1`은 이 부팅에서 아무도 안 친다. 8차가 치는 것은 `z`·`pwd`·
  # `ls`·`history` 넷뿐이고, 그 글자를 화면에 만들 수 있는 것은 7차가 쓰고
  # 간 파일 하나다.
  #
  # SD-M2가 판정 글자를 `whence -w fzf-history-widget`에서 이리로 옮겼다.
  # 이유가 둘이다. 하나는 `history`가 최근 16개만 찍는데(실측 36) 7차가
  # 중첩 세션 둘을 돌면서 그 뒤로 줄이 아홉쯤 더 붙어 옛 글자가 창 밖으로
  # 밀려난 것이고, 다른 하나는 이쪽이 더 정확하다는 것이다 — 옛 글자는
  # `fc -W`가 쓴 것이었고 이 글자는 씨앗의 옵션이 칠 때마다 쓴 것이라,
  # 이 검사가 판정하는 대상이 SD가 넣은 그 한 줄이 된다.
  type_keys "${HISTORY_KEYS[@]}"
  local ok=0
  if wait_for_screen 'posmark=1'; then ok=1; fi
```

- [ ] Step 5: 지울 것 — 실패 문구의 진단 두 줄

```bash
    echo "  둘 중 하나다 — 7차의 fc -W가 못 썼거나(그러면 7차가 빨갰다),"
    echo "  이 부팅의 셸이 HISTFILE을 안 읽었다."
```

- [ ] Step 6: 넣을 것 — 그 자리에

```bash
    echo "  둘 중 하나다 — 7차가 칠 때마다 쓰는 옵션이 안 걸렸거나(그러면"
    echo "  7차의 pos1이 빨갰다), 이 부팅의 셸이 HISTFILE을 안 읽었다."
```

- [ ] Step 7: 셋을 함께 확인한다

```bash
grep -n "fc -W\|HIST_WRITE_KEYS\|HIST_COUNT_KEYS\|whence -w fzf-history-widget" \
  /Users/dp/Repository/tars-linux/config/check.sh
```

Expected: `whence -w fzf-history-widget`이 7차의 `HOOK_WIDGET_KEYS` 주석과
그 판정 한 자리에만 남고(8차에는 없다), `fc -W`·`HIST_WRITE_KEYS`·
`HIST_COUNT_KEYS`는 한 줄도 안 나온다.

---

## Task 4: config 체인 단독으로 돌린다

Files: 없음(실행만)

- [ ] Step 1: 체인을 돌린다 (부팅 여덟, 약 1분 30초 — 타이핑이 늘어 기준선
      1분 26.01초보다 조금 길다)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh > /tmp/sd_m2_config.log 2>&1; echo "exit=$?"
tail -40 /tmp/sd_m2_config.log
```

Expected: `exit=0`. 7차에서 새 줄 셋이 순서대로 나온다.

```
boot 7: with the option unset, a typed command is not in the file while that session lives
boot 7: that same command did land when the session left, so the zero above meant 'not yet written'
boot 7: the seeded option put a typed command on the config disk the moment it was typed
```

그리고 8차가 여전히 초록이다.

```
boot 8: the history list carries a command only the seventh boot typed
```

- [ ] Step 2: `FAIL`이 한 줄도 없는 것을 확인한다

```bash
grep -c "FAIL" /tmp/sd_m2_config.log
```

Expected: `0`

- [ ] Step 3: 빨갛다면 화면을 직접 본다 — 마지막 프레임에 `neg`·`aft`·`pos`가
      어떤 숫자로 찍혔는지가 원인을 가른다

```bash
grep -ao "terminal: screen>.*" /tmp/sd_m2_config.log | tail -1 | tr '|' '\n' | tail -20
```

읽는 법. `neg1`이면 `unsetopt`가 안 먹었다. `aft0`이면 음성 세션의 명령이
애초에 안 쳐졌다. `pos0`이면 씨앗의 옵션이 안 걸렸다. 셋 중 아무 글자도
없으면 타이핑이 셸에 안 닿은 것이고, 그때는 `sendkey` 이름부터 의심한다
(`shift-4`·`shift-9`·`shift-0`이 이 저장소가 처음 치는 키다).

- [ ] Step 4: 커밋한다

```bash
git add config/check.sh
git commit -m "Let the gate watch the history option do its work"
```

---

## Task 5: 되돌림 — 씨앗에서 그 줄을 빼면 게이트가 빨개지는가

이 milestone의 핵심 증명이다. Task 4의 초록은 "검사가 돈다"까지이고, 그
검사가 정말로 그 한 줄을 보고 있는지는 그 줄을 없애 봐야 안다.

방법은 SD-M1이 쓴 것 그대로다 — 고친 사본을 `/tmp`에 만들어 `-v`로 마운트
한다. 저장소 파일이 한 번도 안 바뀌므로 되돌리는 것을 잊는 경로가 없다.

Files:
- Create: `/tmp/config_noopt.zig` (저장소 밖)

- [ ] Step 1: `setopt` 줄만 뺀 사본을 만든다

```bash
cd /Users/dp/Repository/tars-linux
grep -v '^            \\\\setopt INC_APPEND_HISTORY$' init/src/config.zig \
  > /tmp/config_noopt.zig
diff <(wc -l < init/src/config.zig) <(wc -l < /tmp/config_noopt.zig)
```

Expected: 줄 수가 정확히 1 줄어든다(`diff`가 두 숫자를 보인다). 0이면 패턴이
안 맞은 것이고, 2 이상이면 다른 줄까지 지운 것이다 — 그대로 진행하면 안 된다.

- [ ] Step 2: 그 사본을 마운트해서 체인을 돌린다 (약 1분 30초)

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/config_noopt.zig:/workspace/init/src/config.zig:ro \
  -w /workspace tars-devcontainer bash config/check.sh \
  > /tmp/sd_m2_revert.log 2>&1; echo "exit=$?"
grep -a "FAIL\|boot 7:" /tmp/sd_m2_revert.log
```

Expected: `exit`가 0이 아니고, 7차의 세 줄 중 앞의 둘은 초록이고 셋째에서
죽는다.

```
boot 7: with the option unset, a typed command is not in the file while that session lives
boot 7: that same command did land when the session left, so the zero above meant 'not yet written'
FAIL(boot 7): with the seeded option on, a typed command was not in the history file yet
```

앞의 둘이 초록인 것이 요점이다. 옵션이 아예 없는 기계에서도 음성 검사는
초록이어야 맞는다 — 음성이 보는 것은 "옵션이 없으면 안 쓴다"이고, 그것이
바로 이 반사실의 상태이기 때문이다. 셋째만 갈린다.

- [ ] Step 3: 화면에 `pos0`이 찍혔는지 확인한다

```bash
grep -ao "terminal: screen>.*" /tmp/sd_m2_revert.log | tail -1 | tr '|' '\n' | grep -n "pos\|neg\|aft"
```

Expected: `neg0` · `aft1` · `pos0`. 셋째가 `pos0`인 것이 "옵션이 없으니 안
썼다"의 직접 증거다.

- [ ] Step 4: 사본을 지운다

```bash
rm -f /tmp/config_noopt.zig
git -C /Users/dp/Repository/tars-linux status --short
```

Expected: `git status`가 아무것도 안 뱉는다(Task 4에서 이미 커밋했다).
`init/src/config.zig`가 `M`으로 나오면 마운트가 아니라 파일을 고친 것이므로
`git checkout`으로 되돌린다.

---

## Task 6: 루트 게이트 3/3

Files: 없음(실행만)

- [ ] Step 1: 게이트를 background로 돌린다 (약 28분. Bash 도구의 10분
      타임아웃을 넘으므로 `run_in_background`가 아니면 안 된다)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [ ] Step 2: 끝나면 판정과 시간을 본다

```bash
tail -20 /tmp/gate.log
tail -5 /tmp/gate.time
grep -c "FAIL" /tmp/gate.log
```

Expected: 3/3, `FAIL` 0개. 시간은 27분 35.61초 근처다 — 이 게이트의 잡음이
±3분이므로 그 안의 차이는 갈렸다고 말하지 않는다. 7차의 타이핑이 부팅당
100키쯤 늘었고 회차마다 한 번씩이라, 늘어난다면 1분 안쪽이 예상값이다.

- [ ] Step 3: 커널 스킵 횟수를 확인한다 (체인 수 × 3 − 1 = 32)

```bash
grep -c "skipping make" /tmp/gate.log
```

Expected: `32`

---

## Task 7: 문서와 기억

Files:
- Modify: `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
- Modify: `HANDOFF.md`
- Modify: `MEMORY.md`
- Modify: `CLAUDE.md`
- Create: `docs/decisions/project_shell_history.md`
- Modify: `docs/superpowers/plans/2026-09-12-tars-shell-history-durability-sd-m2.md` (이 파일)

- [ ] Step 1: design의 milestone 표에서 SD-M2를 끝났다로, `Status:` 줄을
      고친다. 그리고 SD-M2가 plan에 없던 것을 했으면(판정 셋 중 `aft1`) 그
      사실을 표 아래 문단으로 적는다.

- [ ] Step 2: 이 plan 파일 맨 위에 완료 줄을 단다 — 무엇이 plan과 달랐는지,
      실측 시간이 얼마였는지. SD-M1의 plan이 그 모양이다.

- [ ] Step 3: `docs/decisions/project_shell_history.md`를 만든다. 담을 것은
      다음 세션이 다시 조사하지 않아도 되는 것들이다.

  - 콘솔 셸과 화면 셸의 운명이 갈리는 이유(PTY 주인이 죽으면 SIGHUP)
  - `setopt INC_APPEND_HISTORY` 한 줄이 그 갈림을 없앤다
  - `fc -W`는 다른 세션의 줄을 지운다 — 되살리지 말 것
  - 게이트의 판정 셋(`neg0`·`aft1`·`pos1`)과 왜 셋인가
  - 상수가 세 벌인 이유(`HIST_OPTIONS_ZSH` · 씨앗 · `KNOWN_HIST_OPTIONS`)
  - 이미 설정 디스크를 가진 기계의 처방(결정 6)

- [ ] Step 4: `MEMORY.md`에 한 줄을 더한다.

- [ ] Step 5: `CLAUDE.md`의 완료된 서브프로젝트 표에 SD를 더한다.

- [ ] Step 6: `HANDOFF.md`를 다음 세션용으로 다시 쓴다. SD가 닫혔으므로
      "바로 다음에 할 것"이 이월 숙제에서 다음 서브프로젝트를 고르는 자리가
      된다. 그리고 "서브프로젝트를 넘어 유효한 실측"에 SD-M2가 배운 것을
      더한다 — `sendkey`로 `$(`를 치는 법(`shift-4`·`shift-9`·`shift-0`)과
      `wait_for_screen`이 로그 전체를 보므로 판정 글자를 우리가 만든다는 것.

- [ ] Step 7: 커밋한다

```bash
git add docs HANDOFF.md MEMORY.md CLAUDE.md
git commit -m "Close the history durability work with what it measured"
```

---

## 자기 검토

Spec 대조. 결정 5(음성 대조군의 모양)는 Task 1·2가, 실측 10(`fc -W` 제거)은
Task 1이, 실측 11(앵커)은 `grep -cx`가, 실측 12(프롬프트로 못 가른다)는
`echo neg$(…)`가 받는다. 확인 2(게이트는 나갈 때를 못 본다)는 이 milestone이
그 제약 안에서 판정하는 근거이고, 확인 3(콘솔 셸을 안 끌어온다)은 중첩 zsh를
고른 이유다. design이 예고하지 않은 것이 하나 있다 — 판정 `aft1`. 근거는
design이 아니라 HANDOFF의 "시도했으나 안 되는 접근"이고, Task 7 Step 1이 그
사실을 design에 적는다.

위험 셋과 그 처방.

1. `shift-4`·`shift-9`·`shift-0`이 이 저장소가 처음 치는 키다. 게스트 keymap에
   `.{ '4', '$' }`·`.{ '9', '(' }`·`.{ '0', ')' }`가 있는 것은 읽어서 확인했고
   (`terminal/src/input.zig:35,40,41`), 안 닿으면 화면에 판정 글자가 아예 안
   생겨 Task 4 Step 3이 그 자리에서 드러낸다. 체인 단독이 1분 30초라 재시도가
   싸다.
2. 중첩 zsh가 안 뜨면 `unsetopt`와 `exit`가 바깥 셸에 먹는다. 그 경로는
   조용히 초록이 되지 않는다 — 바깥 셸이 죽으면 init이 `terminal`을 다시
   띄우고, 7차의 기존 검사가 `started terminal`을 정확히 1로 못 박고 있다
   (`config/check.sh`의 7차 블록).
3. 8차의 16줄 창. 위 "8차의 판정 글자를 옮기는 이유"에서 세어 두었고, 새
   글자는 끝에서 여섯째쯤이다. 7차에 명령을 더 더하는 사람은 이 수를 다시
   세야 한다.
