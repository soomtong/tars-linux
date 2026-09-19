---
name: project_terminal_queries
description: 터미널이 자식의 vt 질의에 답한다 — effects.write_pty 한 칸과 그 답이 pty로 돌아가는 길(TQ-M1, 2026-09-19)
metadata:
  type: project
---

셸 설정을 손보다가 나온 자리인데 원인은 셸이 아니라 터미널이었다. 기억을 따로
두는 이유가 그것이다 — `init/src/config.zig`를 보는 사람은 여기를 못 본다.

## 병 — 고쳐졌다

fzf의 셸 통합(fish는 `fzf --fish`, bash는 `fzf --bash`)은 위젯마다
`--height 40%`를 붙인다. fzf는 `--height`일 때 커서가 지금 몇 행에 있는지를
터미널에 묻고(`ESC[6n`, 커서 위치 보고) 그 답으로 자기 상자 높이를 정한다.

우리 `terminal`은 그 질의에 답하지 않았다. ghostty lib-vt가 답을 만들 창구를
갖고 있지만(`stream_terminal.zig:78`의 `write_pty`) 그 칸이 `null`이었고,
라이브러리는 그 칸이 비면 답을 아예 만들지 않는다(응답 갈래 여럿이 이 필드를
문지기로 본다). 그래서 fzf가 답을 기다리며 멈췄다 — 증상이 사람에게 보이는
모양은 "Ctrl+R을 두 번 눌러야 picker가 열린다"였다(첫 누름에 멈춰 있다가 다음
키가 그 바이트를 답으로 읽고 그제야 그린다).

TQ-M1(2026-09-19)이 고쳤다. 답의 값은 라이브러리가 만들고, 우리가 한 일은
그 한 칸을 채우고 받은 바이트를 pty로 돌려주는 것뿐이다.

ST-M3이 그때 잰 값(첫 Ctrl+R 뒤 6~12초 관찰):

| 조건 | 결과 |
|---|---|
| 기본값(`--height 40%`) | 프레임이 한 장도 안 늘어난다 |
| `FZF_CTRL_R_OPTS=--no-height` | 프레임 5 → 52, 첫 누름에 picker가 뜬다 |
| `echo hi \| fzf` (통합 없이) | 즉시 뜬다 — 전체 화면이라 질의가 필요 없다 |

## 지금 어디에 있나 — 고치는 사람이 볼 자리

- `terminal/src/vt.zig` — `Handler`(`TerminalStream`의 handler 필드 타입) ·
  `REPLY_MAX`(512) · `onWritePty`(콜백) · `Screen.reply_buf`·`reply_len`·
  `reply_dropped` · `pushReply`/`takeReplies`. `init`이
  `self.stream.handler.effects.write_pty = &onWritePty`로 그 한 칸을 채운다.
- `terminal/src/main.zig` — `screen.feed(out)` 바로 뒤에 `takeReplies()`를
  pty로 쓴다. pty에 쓰는 자리가 거기 하나뿐이라 순서가 코드 모양으로
  고정된다(질의의 답이 그 뒤에 친 키보다 먼저 나간다).
- `kernel/tq-probe.sh` → 게스트의 `/usr/bin/tq-probe`(`make_initrd.sh`가 넣고
  `tools/check.sh`의 `WANT`가 지킨다). 게이트가 그 이름을 친다.
- `terminal/check.sh` — 프로브를 치고 `len[1-9]`를 본다(답이 오면 `len6`,
  안 오면 `len0`).
- `init/src/config.zig` — 씨앗 셋에 `FZF_DEFAULT_OPTS` 줄이 없다(ST-M3의
  우회를 지웠다). `config_test.zig`의 `KNOWN_SEED_ENV`도 함께 사라졌다.

게이트가 보는 자리 셋: terminal 체인(vt 단위 검사 넷 + 게스트의 `len6`) ·
config 체인 1차 부팅(우회 없이 첫 Ctrl+R에 picker) · tools 체인(정적 목록).

## 다시 밟지 말 것 다섯

1. 질의 바이트를 게이트가 `type_keys`로 칠 수 없다. 이스케이프가 fish → bash
   → printf 층에서 죽어 리터럴 `033[6n`이 나간다(화면에 그대로 찍혔다). ESC가
   든 스크립트를 initrd에 실어 그 경로를 치게 한다.
2. 묻기와 읽기가 한 프로세스 안에 있어야 한다. 답은 pty의 입력이라, 사이에
   프롬프트로 돌아온 셸의 라인 편집기가 먼저 가져간다 — fish가 묻고 bash가
   읽게 했더니 `len0`이었다.
3. 답은 tty가 되울린다(ECHOCTL이 ESC를 `^[`로 바꾼다). 화면에는
   `^[[4;1Rlen6`처럼 한 행에 붙어 나오므로 판정 글자를 행 첫머리에 기대면
   안 된다 — `len<n>`이고, 우리가 치는 것에 `len`이 없다는 것이 그 판정이
   안전한 근거다(`project_gate_screen_echo`의 autosuggestion 함정과 같은 자리).
4. DA1(`ESC[c`)은 그 한 칸으로 안 된다(0바이트). 임베더가 장치 속성을
   선언해야 만들어진다 — design 비목표 1이고 지금도 안 한다.
5. 넘치는 답은 통째로 버린다. 반쪽을 넣으면 자식 파서가 그걸 답으로 읽어
   커서를 엉뚱한 자리에 그린다. 6바이트 답 200개를 몰아치면 85개(510바이트)가
   남고 115개를 버린다(510 + 6 = 516 > 512).

## 남은 것

없다 — TQ는 M1 하나로 닫혔다. 다음 후보는 씨앗의 허용 범주를 늘리는 일
(fzf의 `FZF_DEFAULT_COMMAND` 같은 환경 변수 줄)이고 그 자리는
`project_shell_tools`다.

관련 기억: [project_shell_tools](이 자리를 찾은 서브프로젝트) ·
[project_shell_memory](훅을 건 곳) ·
[project_terminal_rendering](vt와 렌더러) ·
[project_gate_screen_echo](판정 글자를 게스트가 만드는 글자로 두는 이유).
