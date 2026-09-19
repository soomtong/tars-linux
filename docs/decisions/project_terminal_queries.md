---
name: project_terminal_queries
description: 우리 terminal은 vt의 질의(커서 위치·DA 등)에 답하지 않는다 — fzf의 --height가 그 답을 기다리며 멈춘다(ST-M3, 2026-09-19)
metadata:
  type: project
---

셸 설정을 손보다가 나온 자리인데 원인은 셸이 아니라 터미널이다. 기억을 따로
두는 이유가 그것이다 — `init/src/config.zig`를 보는 사람은 여기를 못 본다.

## 병

fzf의 셸 통합(fish는 `fzf --fish`, bash는 `fzf --bash`)은 위젯마다
`--height 40%`를 붙인다. fzf는 `--height`일 때 **커서가 지금 몇 행에 있는지**를
터미널에 묻고(`ESC[6n`, 커서 위치 보고) 그 답을 받아 자기를 그 자리에 그린다.

우리 `terminal`은 그 질의에 답하지 않는다. ghostty lib-vt가 그 답을 만들
창구(콜백)를 갖고 있지만 **우리가 하나도 등록하지 않았다** —
`terminal/src`에 `ghostty_vt_terminal_set*`이나 콜백 등록이 0개다. 그래서
fzf가 답을 기다리며 멈춘다.

증상이 사람에게 보이는 모양: **Ctrl+R을 두 번 눌러야 picker가 열린다.**
첫 누름에 fzf는 멈춰 있고(화면에는 아무 일도 안 일어난다), 두 번째 키가
pty로 들어오면 fzf가 그 바이트를 답으로 읽고 그제야 그린다.

## 잰 것 (ST-M3, 2026-09-19)

| 조건 | 첫 Ctrl+R 뒤 키를 안 누르고 6~12초 |
|---|---|
| 기본값(`--height 40%`) | 프레임이 **한 장도 안 늘어난다**(12초 관찰) |
| `FZF_CTRL_R_OPTS=--no-height` | 프레임 5 → 52, picker가 첫 누름에 뜬다 |
| `echo hi \| fzf` (통합 없이 직접) | 즉시 뜬다 — 전체 화면이라 질의가 필요 없다 |

부수 관찰: `less`는 즉시 그린다(그래서 `git log`는 멀쩡하다). `fzf --version`의
실행 시간은 34ms다 — 느린 것이 아니라 **기다리는 것**이다.

## 지금의 처방과 진짜 수리

처방(우회): 씨앗 rc가 `FZF_DEFAULT_OPTS --no-height`를 준다(fish는
`set -gx`, bash·zsh는 `export`). 대가는 picker가 화면 전체를 쓰는 것이고,
`config/check.sh`의 1차 부팅이 "첫 Ctrl+R에 picker가 뜬다"로 그것을 지킨다.

진짜 수리(TQ로 열었다 — 구현은 다음 세션): `terminal`이 lib-vt의 `write_pty`
effect를 채워 답을 pty로 쓴다. **한 칸이면 된다** — vendored
`stream_terminal.zig:78`의 `write_pty: ?*const fn (*Handler, [:0]const u8) void`가
지금 `null`이고, 라이브러리는 그 칸이 비면 답을 아예 안 만든다(응답 갈래 여럿이
이 필드를 문지기로 본다: `:186` · `:365` · `:523` · `:841` · `:928` · `:966` · `:983`).
핸들러는 `TerminalStream`의 공개 필드이고(`stream.zig:477`), 우리 Screen은
`handler.terminal`에서 `@fieldParentPtr`로 되찾을 수 있다.

## 한 번 구현해 보고 되돌린 것 (2026-09-19)

사용자가 "다음 세션에 하려던 것"이라고 해서 코드를 검증된 M3 상태로 되돌렸다.
그때 확인된 것 넷을 남긴다 — 다시 밟지 말 것.

| 잰 것 | 결과 |
|---|---|
| `write_pty` 한 칸으로 CPR(`ESC[6n`) | 답이 온다 — 6바이트, `ESC[<행>;<열>R` 꼴 |
| 같은 칸으로 DSR(`ESC[5n`) | 답이 온다 — 4바이트, `ESC[0n` 꼴 |
| 같은 칸으로 DA1(`ESC[c`) | **0바이트** — 임베더가 장치 속성을 선언해야 만들어진다 |
| 평범한 출력 | 답 0바이트(검사로 못 박아야 한다 — 안 그러면 모든 출력에 답을 만드는 고장이 통과한다) |

게이트에서 밟은 함정 둘.

1. **질의 바이트를 `type_keys`로 타이핑하지 말 것.** `printf \033[6n`의
   이스케이프가 fish → bash → printf 층에서 죽어 리터럴 `033[6n`이 나갔다(화면에
   그대로 찍혀 확인). ESC가 든 작은 스크립트를 initrd에 실어 그 경로를 치게 한다
   — dhcpcd hook을 싣는 것과 같은 방식.
2. **물어보기와 읽기는 같은 프로세스 안에 있어야 한다.** fish가 묻고 bash가
   읽으면 답이 0바이트로 나온다 — 답은 pty의 입력이고, 그 사이에 프롬프트로
   돌아온 셸의 라인 편집기가 먼저 가져간다. `printf; read -n 20 -t 2`를 한
   프로세스에서 해야 한다.

## 이 검사를 게이트 어디에 두었나 (그리고 왜 마지막인가)

`config/check.sh` 1차 부팅 훅의 **맨 끝**이다. 중간에 두었더니 picker를 닫은
직후의 fzf가 화면을 되돌리는 동안 다음 타이핑이 fzf로 새어, 뒤따르던
되읽기 검사(`shell=zsh`)가 깨졌다. 판정 하나가 다음 판정을 흔들지 않게
마지막에 둔다 — 다음 부팅은 새 부팅이다.

관련 기억은 [[project_shell_tools]](이 자리를 찾은 서브프로젝트) ·
[[project_shell_memory]](훅을 건 곳) ·
[[project_terminal_rendering]](vt와 렌더러)이다.
