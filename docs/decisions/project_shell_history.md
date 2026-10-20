---
name: project_shell_history
description: "콘솔 셸 히스토리가 전원 버튼에 사라지던 것을 seed rc 한 줄로 고쳤다(SD · BH) — zsh `setopt INC_APPEND_HISTORY` · bash `PROMPT_COMMAND='history -a'`는 zoxide 훅보다 먼저 · `fc -W`를 되살리지 말 것 · 판정 `grep`은 앵커(`grep -x`) · 중첩 zsh는 프롬프트로 못 가른다 · 음성 판정은 세션이 살아 있는 동안 · 상수가 세 벌"
metadata:
  node_type: memory
  type: project
---

SD(zsh)와 BH(bash)가 2026-09-12 하루에 세웠다. design은
`docs/specs/2026-09-12-tars-shell-history-durability-design.md` ·
`docs/specs/2026-09-12-tars-bash-history-durability-design.md`, 코드는
`init/src/config.zig`의 seed와 `config_test.zig`, 게이트는 `config/check.sh`
7차·8차 부팅이다. milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋
이력에 있다).

## 무엇이 고쳐졌나

콘솔 셸에 친 명령이 전원 버튼과 함께 사라졌다. 화면 셸에 친 것이 남은 것은
설계가 아니라 우연이다 — `terminal`이 먼저 죽어 PTY가 닫히면 커널이 그 아래
셸에게 SIGHUP을 보낸다. 콘솔 셸은 닫히지 않는 `/dev/console`을 잡고 있어
SIGHUP이 없고, 대화형 셸은 SIGTERM을 무시하므로 3초 뒤 SIGKILL에 죽는다
([[project_shutdown_signals]]).

처방은 seed rc의 zsh 갈래에 넣은 `setopt INC_APPEND_HISTORY` 한 줄이다. 명령을
칠 때마다 그 자리에서 `HISTFILE`에 쓰므로 쓰는 시점이 종료 경로에서 떨어져
나오고, 전원 버튼도 전원 분리도 커널 패닉도 SIGKILL도 히스토리를 못 지운다.
fish는 이 문제가 없다(`exit` · SIGTERM · SIGHUP 셋 다에서 쓴다).

착수 전 측정이 전제를 뒤집었다. 고치려던 SM 비목표 9(zsh 두 세션이 같은
`HISTFILE`을 겹쳐 쓴다)는 `APPEND_HISTORY`가 zsh 기본값이라 애초에 안 나는
일이고, 대신 위의 더 나쁜 것이 나왔다. 코드를 안 고치는 측정 milestone(M0)을
따로 둔 것이 넣었다 되돌릴 일 둘을 막았다.

## bash도 같은 날 섰다 (BH-M0~M2, 2026-09-12)

처방은 `PROMPT_COMMAND='history -a'` 한 줄이고, zsh 것과 성질이 셋 다르다.

1. 그 줄은 seed에서 훅 두 줄보다 먼저 와야 한다. `PROMPT_COMMAND`는 변수가
   하나뿐이라 마지막 대입이 이기는데, `zoxide init bash`는 기존 값을 보존하며
   앞에 붙인다(`__zoxide_hook;${PROMPT_COMMAND#;}`). 우리가 먼저면 둘 다 돌고,
   나중이면 우리 대입이 zoxide를 통째로 지운다. 증상이 조용하다 — 히스토리는
   남고 `z`만 아무 디렉터리도 안 배운다. `config_test.zig`의
   `expectPromptCommandBeforeHooks`가 그 순서를 못 박는다.
2. 쓰는 타이밍이 한 칸 다르다. zsh는 명령을 읽자마자 써서 실행 중인 명령이
   이미 파일에 있고, bash의 `PROMPT_COMMAND`는 직전 명령까지만 쓴다. 그래서
   아래 "판정에 쓰는 `grep`에는 앵커를 붙인다"의 이유가 bash에서는 "자기를
   센다"가 아니라 "앞선 줄을 센다"가 된다. 앵커는 그래도 붙인다.
3. 비대화형 bash는 `PROMPT_COMMAND`를 안 돌아서 오타도 0바이트로 보인다 — 새
   줄이 조용한지 재는 방법은 [[project_measuring_shells]]에 있다.

`shopt -s histappend`는 안 넣었다. 그 옵션은 끝날 때 덮어쓸지 이어 쓸지를
정하는데, 우리가 지는 싸움은 끝날 때가 아예 안 온다는 것이다. `history -a`를
쓰는 세션은 나가면서 남의 줄을 안 지운다(BH 실측 12) — 이미 append해 두면
종료 시 다시 쓸 것이 없다.

bash 게이트(`bneg0` · `baft1` · `bpos1`)는 아래 zsh 판정과 구조가 같고 다른
것이 셋이다.

- 음성이 옵션을 끄는 방법이 `unsetopt`가 아니라 `PROMPT_COMMAND=`다.
- 첫 명령이 `HISTFILE=/config/bash_history`다. 7차는 zsh로 떠서 env의
  `HISTFILE`이 zsh 것이고, 안 맞추면 zsh 파일에 섞인 평문을 센다.
- 중첩 bash는 프롬프트가 `bash-5.2#`로 바뀌므로 첫 중첩 뒤
  `wait_for_screen 'bash-5\.2#'`로 기다린다. 안 기다리면 rc를 읽는 중에
  타이핑이 끼어들어 글자가 쪼개진다.

bash 판정이 zsh 판정보다 앞에 있다. 7차가 zsh 파일에 더하는 세 줄이
`posmark=1` 뒤에 오면 8차의 `history` 16줄 창에서 그 글자를 민다.

게스트에 `/dev/fd`가 없어 seed의 fzf 훅이 부팅 때 에러 한 줄을 찍던 것도 BH가
고쳤다([[project_measuring_shells]]).

## 게이트에서 다시 조사하지 말 것

### 1. `fc -W`를 되살리지 말 것

게이트가 전원을 뽑으므로(`boot_once`의 `kill "$QEMU_PID"`) SM-M2 시절 7차는
8차가 읽을 파일을 `fc -W`로 손수 썼다. 그 명령은 메모리의 목록으로 파일을
통째로 덮어써서 다른 세션이 써 둔 줄을 지우고, 그 줄은 두 세션이 나간 뒤에도
안 돌아온다. 옵션이 켜지면 필요 없고, 같은 파일을 보는 세션 둘을 만드는 검사가
그 자리에 들어왔으므로 남겨 두면 검사가 자기 재료를 지운다.

### 2. 판정에 쓰는 `grep`에는 앵커를 붙인다

히스토리를 증분으로 쓰는 zsh에서는 `grep` 명령줄이 실행 전에 파일에 써져서,
앵커가 없으면 패턴이 자기를 센다.

```
echo marktarget  을 친 뒤
grep -c marktarget …            → 2   ← 자기 명령줄까지 센다
grep -c '^echo marktarget$' …   → 1
grep -c '^echo nothinghere$' …  → 0
```

음성 검사에서 그 차이가 0과 1이라, 앵커가 없으면 아무것도 안 보면서 초록이
된다. 게이트는 `^…$` 대신 `grep -x`를 쓴다 — 같은 뜻인데 게스트에 따옴표를 안
쳐도 된다.

### 3. 중첩 zsh는 프롬프트로 못 가른다

중첩 기동은 한 글자도 안 찍고 프롬프트가 바깥 세션과 글자 그대로 같다. 들어갔는지
나왔는지를 화면으로 알 수 없으므로 판정은 우리가 만든 글자로 한다.

### 4. 음성 판정은 그 세션이 살아 있는 동안 한다

옵션을 끈 세션도 `exit`할 때는 자기 목록을 append한다. 나간 뒤에 세면 음성과
양성이 같은 숫자가 된다.

## 게이트의 판정이 셋인 이유

7차 부팅이 같은 seed rc를 읽는 중첩 zsh 둘을 띄우고, 음성은 첫 명령으로 옵션을
끈다.

| 판정 글자 | 언제 | 무엇을 말하나 |
|---|---|---|
| `neg0` | 음성 세션이 살아 있는 동안 | 옵션을 끈 세션이 친 명령은 파일에 없다 |
| `aft1` | 음성 세션이 나간 뒤 | 그 명령은 분명히 쳐졌다 — 위의 0이 진짜다 |
| `pos1` | 양성 세션이 살아 있는 동안 | 옵션이 켜진 세션이 친 명령은 그 자리에서 파일에 있다 |

`aft1`이 없으면 "아직 안 썼다"와 "애초에 안 쳐졌다"가 안 갈린다(SD-M0이 첫
회차를 그것으로 버렸다). 판정 글자는
`echo neg$(grep -cx negmark=1 /config/zsh_history)`가 만든다. `grep -c`의
출력은 한 글자라 판정 글자가 못 되고(`wait_for_screen`은 마지막 프레임이 아니라
로그 전체를 본다), 실패하면 화면에 남는 `neg1`이 진단이 된다.

## 상수가 세 벌인 이유

`init/src/config.zig`의 `HIST_OPTIONS_ZSH` · seed `rcSeed()`의 글자 ·
`config_test.zig`의 `KNOWN_HIST_OPTIONS`. 앞의 둘을 조립하지 않는 이유는
`hookLines()`와 같다 — 조립하면 역방향 검사가 tautology가 된다. 셋째 벌은 앞의
둘을 함께 고치면 양방향이 둘 다 만족되는 것을 막고, 그것이 막는 사고는 오타 한
글자다.

```
/tmp/q_typo/.zshrc:setopt:1: no such option: INC_APPEND_HISTORYY
```

그 65바이트가 설정 디스크를 붙이는 다섯 체인의 화면 좌표를 민다 — 게이트가
아니라 호스트 검사가 먼저 잡아야 하는 사고다. 되돌림 넷이 각각 다른 줄에서
죽는다: seed 줄을 `echo hi`로(정방향) · seed에서만 지우기(역방향) · seed와
목록에서 함께 지우기(개수) · 둘을 함께 오타로(`KNOWN_HIST_OPTIONS`).

seed에서 그 줄을 빼면 부팅 전에 호스트 검사가 죽으므로, 게이트가 무엇을 보는지
mutation으로 확인하려면 `config_test.zig`의 역방향 loop도 함께 눕혀야 한다.

## 이미 설정 디스크를 가진 기계

seed rc는 파일이 없을 때만 깔린다(`O_EXCL`). 이미 디스크를 가진 기계는 이 줄을
저절로 받지 못하고, 마이그레이션은 만들지 않는다. 우리가 사용자 파일에 줄을
넣기 시작하면 "사용자가 지운 줄을 우리가 다시 넣는다"와 구별할 수 없기
때문이다. 처방은 손으로 그 한 줄을 더하거나 `/config/zshrc`를 지우고 재부팅하는
것이다.

## 관련

[[project_shutdown_signals]] · [[project_shell_memory]] ·
[[project_shell_config]] · [[project_guest_environment]]
