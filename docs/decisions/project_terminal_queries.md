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

진짜 수리(아직 안 함): `terminal`이 lib-vt의 콜백을 등록해 답을 pty로 쓴다 —
커서 위치 보고 · DA1/DA2 · 모드 질의 · 색 질의. 그러면 fzf가 40% 상자로
돌아오고, 같은 것을 묻는 다른 도구도 함께 낫는다. 다음 서브프로젝트 후보
1순위다(ST design의 "다음" 절).

## 이 검사를 게이트 어디에 두었나 (그리고 왜 마지막인가)

`config/check.sh` 1차 부팅 훅의 **맨 끝**이다. 중간에 두었더니 picker를 닫은
직후의 fzf가 화면을 되돌리는 동안 다음 타이핑이 fzf로 새어, 뒤따르던
되읽기 검사(`shell=zsh`)가 깨졌다. 판정 하나가 다음 판정을 흔들지 않게
마지막에 둔다 — 다음 부팅은 새 부팅이다.

관련 기억은 [[project_shell_tools]](이 자리를 찾은 서브프로젝트) ·
[[project_shell_memory]](훅을 건 곳) ·
[[project_terminal_rendering]](vt와 렌더러)이다.
