---
name: project_shell_history
description: "콘솔 셸에 친 명령이 전원 버튼과 함께 사라지던 것을 고친 층(SD와 BH) — 둘 다 2026-09-12에 열고 같은 날 닫았다. zsh는 씨앗 rc의 `setopt INC_APPEND_HISTORY` 한 줄(SD), bash는 `PROMPT_COMMAND='history -a'` 한 줄(BH)이고, bash 쪽은 그 줄이 zoxide 훅보다 먼저 있어야 한다 — `PROMPT_COMMAND`는 변수가 하나뿐이라 마지막 대입이 이기고, 뒤집히면 히스토리는 남는데 `z`가 아무것도 안 배운다. 게이트 판정은 7차 부팅의 중첩 셸 넷이다(zsh `neg0`·`aft1`·`pos1`, bash `bneg0`·`baft1`·`bpos1`). 처방은 씨앗 rc의 zsh 갈래에 넣은 `setopt INC_APPEND_HISTORY` 한 줄이고, 그 줄이 쓰는 시점을 종료 경로에서 떼어 낸다. 착수 전 측정이 이 서브프로젝트의 전제를 뒤집었다 — 고치려던 SM 비목표 9(`두 세션이 서로를 지운다`)는 애초에 안 나는 일이고(`APPEND_HISTORY`가 zsh 기본값이다) 대신 더 나쁜 것이 나왔다. 게이트에서 다시 조사하지 말 것 넷: `fc -W`는 메모리 목록으로 파일을 덮어써 다른 세션의 줄을 지우므로 되살리지 말 것 · 히스토리를 증분으로 쓰는 zsh에서는 판정에 쓰는 `grep` 명령줄이 실행 전에 파일에 써지므로 앵커(`grep -x`)가 필수다 · 중첩 zsh는 한 글자도 안 찍고 프롬프트가 바깥과 같아서 프롬프트로는 아무것도 못 가른다 · 옵션을 끈 세션도 나갈 때는 자기 목록을 append하므로 음성 판정은 그 세션이 살아 있는 동안 해야 한다. 상수가 세 벌인 이유(`HIST_OPTIONS_ZSH` · 씨앗 · `KNOWN_HIST_OPTIONS`)와 게이트의 판정 셋(`neg0`·`aft1`·`pos1`)이 본문에 있다"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-12에 SM이 닫히자마자 골랐다. SM 비목표 9를 고치려고 열었고,
착수 전 측정이 그 비목표의 전제를 뒤집었다. design은
`docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`,
milestone 셋(SD-M0·M1·M2)이 2026-09-12 하루에 다 끝났다.

## 무엇이 고쳐졌나

콘솔 셸에 친 명령이 전원 버튼과 함께 사라졌다. 화면 셸에 친 것은 남았는데,
그것은 설계가 아니라 우연이다 — `terminal`이 시그널 핸들러를 하나도 안
가져서 먼저 죽고, PTY가 닫히면서 커널이 그 아래 셸에게 SIGHUP을 보낸다.
콘솔 셸은 닫히지 않는 `/dev/console`을 잡고 있어서 그 SIGHUP이 없고,
대화형 셸은 SIGTERM을 무시하므로 3초 뒤 SIGKILL에 죽는다. 자세한 것은
[[project_shutdown_signals]]에 있다.

처방은 씨앗 rc의 zsh 갈래에 넣은 한 줄이다.

```
setopt INC_APPEND_HISTORY
```

이 줄이 있으면 zsh가 명령을 칠 때마다 그 자리에서 `HISTFILE`에 쓴다. 쓰는
시점이 종료 경로에서 떨어져 나오므로 전원 버튼도 전원 분리도 커널 패닉도
SIGKILL도 히스토리를 못 지운다.

SD는 zsh만 고쳤다. fish는 이 문제를 애초에 안 갖고 있고(`exit`·SIGTERM·SIGHUP
셋 다에서 쓴다), bash는 이월 숙제로 남겼다. 그 숙제를 같은 날 BH가 했다.

## bash도 같은 날 섰다 (BH-M0~M2, 2026-09-12)

design은 `docs/superpowers/specs/2026-09-12-tars-bash-history-durability-design.md`.
처방이 zsh의 `setopt` 한 줄에 대응하는 한 줄이다.

```
PROMPT_COMMAND='history -a'
```

크기는 같은데 성질이 셋 다르다.

1. 그 줄은 씨앗에서 훅 두 줄보다 먼저 와야 한다. `PROMPT_COMMAND`는 변수가
   하나뿐이라 마지막 대입이 이기는데 `zoxide init bash`가 같은 변수를 쓴다.
   zoxide는 기존 값을 보존하며 앞에 붙이므로(`__zoxide_hook;${PROMPT_COMMAND#;}`)
   우리가 먼저면 둘 다 돌고, 나중이면 우리 대입이 zoxide를 통째로 지운다.
   증상이 조용하다 — 히스토리는 남고 `z`만 아무 디렉터리도 안 배운다.
   `config_test.zig`의 `expectPromptCommandBeforeHooks`가 그 순서를 못 박는다.
2. 쓰는 타이밍이 zsh와 한 칸 다르다. zsh는 명령을 읽자마자 써서 실행 중인
   명령이 이미 파일에 있는데, bash의 `PROMPT_COMMAND`는 직전 명령까지만 쓴다.
   그래서 아래 "판정에 쓰는 `grep`에는 앵커를 붙인다"의 이유가 bash에서는
   "자기를 센다"가 아니라 "앞선 줄을 센다"로 바뀐다. 앵커는 그래도 붙인다.
3. 새 줄이 조용한지 재는 방법이 다르다. 비대화형 bash는 `PROMPT_COMMAND`를
   아예 안 돌아서 오타도 0바이트로 보인다. 자세한 것은
   [[project_measuring_shells]]에 있다.

`shopt -s histappend`는 안 넣었다. 그 옵션이 정하는 것은 셸이 끝날 때
덮어쓸 것인가 이어 쓸 것인가이고, 우리가 지는 싸움은 "끝날 때가 아예 안
온다"이다. 한 번 의심해서 재 봤는데(BH 실측 12) `history -a`를 쓰는 세션은
나가면서 남의 줄을 안 지운다 — 이미 append해 두면 종료 시 다시 쓸 것이 없다.

게이트는 7차 부팅에 중첩 bash 둘을 띄워 판정한다 — `bneg0` · `baft1` ·
`bpos1`. 구조가 아래 zsh의 것과 같고 다른 것이 둘이다. 음성이 옵션을 끄는
방법이 `unsetopt`가 아니라 `PROMPT_COMMAND=`이고, 첫 명령이
`HISTFILE=/config/bash_history`다 — 7차는 zsh로 떴으므로 env의 `HISTFILE`이
zsh 것이고, 안 맞추면 검사가 zsh 파일에 섞인 평문을 센다.

bash 판정이 zsh 판정보다 앞에 있다. bash 중첩 안에서 친 것은 zsh 히스토리에
안 들어가므로 7차가 zsh 파일에 더하는 것은 세 줄뿐인데, 그 셋이 `posmark=1`
뒤에 오면 8차의 `history` 16줄 창에서 그 글자를 민다.

중첩 bash는 프롬프트로 기다릴 수 있다 — 중첩 zsh와 갈리는 자리다. zsh는
프롬프트가 바깥과 같아서 "떴는가"를 아무것도 못 가르는데 bash는
`bash-5.2#`로 바뀐다. 첫 중첩 뒤에 `wait_for_screen 'bash-5\.2#'`가 있는
이유가 이것이고, 안 기다리면 rc를 읽는 중에 타이핑이 끼어들어 글자가
쪼개진다.

BH가 계획에 없던 것을 하나 고쳤다. 게스트에 `/dev/fd`가 없어서 씨앗의 fzf
훅이 부팅할 때 에러 한 줄을 찍고 있었다 — 자세한 것은
[[project_measuring_shells]]에 있다.

## 전제가 틀렸다는 것을 착수 전에 알았다

SM 비목표 9는 *"zsh 두 세션이 같은 `HISTFILE`을 겹쳐 쓴다"*였고, 그것이
이 서브프로젝트를 연 이유였다. 측정이 아니라고 답했다 — `APPEND_HISTORY`가
zsh의 기본값이라 두 세션은 서로를 안 지운다.

M0을 코드 한 줄 안 고치는 milestone으로 따로 둔 것이 값을 했다. 그 측정이
없었으면 M1에서 코드를 넣고 M2에서 되돌릴 일이 둘 있었다.

## 게이트에서 다시 조사하지 말 것

### 1. `fc -W`를 되살리지 말 것

`config/check.sh` 7차는 SM-M2 시절 `fc -W`를 직접 쳤다. 게이트가 전원을
뽑기 때문에(`boot_once`의 `kill "$QEMU_PID"`) 8차가 읽을 파일을 7차가 손으로
써 두어야 했다.

그 명령은 메모리의 목록으로 파일을 통째로 덮어쓴다. 세션 A가 치면 B가 써 둔
줄이 사라지고, 두 세션이 나간 뒤에도 안 돌아온다. SD-M2가 그것을 뺐다 —
옵션이 켜지면 애초에 필요 없고, 같은 파일을 보는 세션 둘을 만드는 검사가
그 자리에 들어왔으므로 남겨 두면 검사가 자기 재료를 지운다.

### 2. 판정에 쓰는 `grep`에는 앵커를 붙인다

히스토리를 증분으로 쓰는 zsh에서는 `grep` 명령줄이 실행 전에 파일에 써진다.
앵커가 없으면 패턴이 자기를 센다.

```
echo marktarget  을 친 뒤
grep -c marktarget …            → 2   ← 자기 명령줄까지 센다
grep -c '^echo marktarget$' …   → 1
grep -c '^echo nothinghere$' …  → 0
```

음성 검사에서 그 차이가 0과 1이라, 앵커가 없으면 검사가 아무것도 안 보면서
초록이 된다. 게이트는 `^…$` 대신 `grep -x`를 쓴다 — 같은 뜻인데 게스트에
따옴표를 안 쳐도 된다.

### 3. 중첩 zsh는 프롬프트로 못 가른다

중첩 기동은 한 글자도 안 찍고 프롬프트가 바깥 세션과 글자 그대로 같다.
중첩에 들어갔는지 나왔는지를 화면으로 알 수 없으므로, 판정은 우리가 만든
글자로 한다.

### 4. 음성 판정은 그 세션이 살아 있는 동안 한다

옵션을 끈 세션도 `exit`할 때는 자기 목록을 append한다. 나간 뒤에 세면 음성과
양성이 같은 숫자가 되어 검사가 무의미해진다.

## 게이트의 판정이 셋인 이유

7차 부팅이 중첩 zsh 둘을 띄운다. 둘 다 같은 씨앗 rc를 읽고, 다른 것은 음성이
첫 명령으로 옵션을 끄는 것 하나뿐이다.

| 판정 글자 | 언제 | 무엇을 말하나 |
|---|---|---|
| `neg0` | 음성 세션이 살아 있는 동안 | 옵션을 끈 세션이 친 명령은 파일에 없다 |
| `aft1` | 음성 세션이 나간 뒤 | 그 명령은 분명히 쳐졌다 — 위의 0이 진짜다 |
| `pos1` | 양성 세션이 살아 있는 동안 | 옵션이 켜진 세션이 친 명령은 그 자리에서 파일에 있다 |

가운데 것이 design에 없던 것이다. 음성이 보는 것은 *"파일에 그 줄이 없다"*
이고, 그것만으로는 *"아직 안 썼다"*와 *"애초에 안 쳐졌다"*가 안 갈린다.
SD-M0이 첫 회차를 정확히 그것으로 버렸다.

판정 글자는 `echo neg$(grep -cx negmark=1 /config/zsh_history)`가 만든다.
`grep -c`의 출력은 한 글자라 판정 글자가 못 되고(`wait_for_screen`이 마지막
프레임이 아니라 로그 전체를 본다), 실패했을 때 화면에 `neg1`이 남는 것이
진단이 된다.

## 상수가 세 벌인 이유

`init/src/config.zig`의 `HIST_OPTIONS_ZSH` · 씨앗 `rcSeed()`의 글자 ·
`config_test.zig`의 `KNOWN_HIST_OPTIONS`. 앞의 둘을 조립하지 않는 이유는
`hookLines()`와 같다 — 조립하면 역방향 검사가 tautology가 된다. 셋째 벌이
있는 이유는 앞의 둘을 함께 고치면 양방향이 둘 다 만족되기 때문이고, 그것이
막는 사고는 오타 한 글자다.

```
/tmp/q_typo/.zshrc:setopt:1: no such option: INC_APPEND_HISTORYY
```

그 65바이트가 설정 디스크를 붙이는 다섯 체인의 화면 좌표를 민다. 게이트가
아니라 호스트 검사가 먼저 잡아야 하는 종류의 사고다. 되돌림 넷이 각각 다른
줄에서 죽는 것을 확인했다 — 씨앗 줄을 `echo hi`로(정방향) · 씨앗에서만
지우기(역방향) · 씨앗과 목록에서 함께 지우기(개수) · 둘을 함께 오타로
(`KNOWN_HIST_OPTIONS`).

M1의 그 검사들이 M2의 반사실을 막기도 했다. 씨앗에서 그 줄을 빼면 부팅 전에
죽으므로, 게이트가 무엇을 보는지 확인하려면 `config_test.zig`의 역방향 loop도
함께 눕혀야 한다.

## 이미 설정 디스크를 가진 기계

씨앗 rc는 파일이 없을 때만 깔린다(`O_EXCL`). 그래서 이미 디스크를 가진
기계는 이 줄을 저절로 받지 못하고, 마이그레이션을 만들지 않는다.

만들지 않는 이유는 비용이 아니라 성질이다. 우리가 사용자 파일에 줄을 넣기
시작하면 *"사용자가 지운 줄을 우리가 다시 넣는다"*와 구별할 수 없게 된다.
처방은 손으로 그 한 줄을 더하거나 `/config/zshrc`를 지우고 재부팅하는 것이다.

## 관련

[[project_shutdown_signals]] · [[project_shell_memory]] ·
[[project_shell_config]] · [[project_guest_environment]]
