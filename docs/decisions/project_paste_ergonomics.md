---
name: project_paste_ergonomics
description: 붙인 글자와 고친 설정이 사람이 뜻한 대로 남게 한 셋 — service 체인이 dhcpcd의 adding default route 줄까지 기다린다(M0), 자식이 모드 2004를 켰으면 Cmd+V를 ESC[200~ · ESC[201~로 감싼다(M1, CM 결정 9를 다시 열었다), /.vimrc가 /config/vimrc로 가는 링크이고 init이 주석뿐인 seed를 깐다(M2). PE-M0~M2, 2026-10-04 종료. 새 체인 없이 copy 검사 21 · 22와 config 1 · 2차 부팅이 본다
metadata:
  type: project
---

Paste Ergonomics(PE)는 2026-10-04에 M0~M2로 닫혔다. GE가 남긴 둘(터미널의 bracketed paste · 사용자
vimrc 영속)과 루트 게이트를 흔든 체인 경합 하나에서 시작했다. 분업(plan · 구현은 서브에이전트, lead는
대조 · 게이트 · commit)은 design 결정 9다.

- design: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
- plan: `docs/plans/2026-10-04-tars-paste-ergonomics-pe-m0.md` · `-pe-m1.md` · `-pe-m2.md`

## 무엇이 바뀌었나

- `service/check.sh`의 `boot_ssh`(PE-M0)가 `leased` 뒤에 `eth0: adding default route via
  10\.0\.2\.2`를 한 줄 더 기다린다. 왜인지(dhcpcd가 로그를 먼저 찍고 주소를 뒤에 붙인다)는
  measurements 73. 코드는 0줄이다.
- `vt.Screen.pasteParts`와 `dumpPaste`(PE-M1). 자식이 모드 2004를 켰으면(`term.modes.get(.bracketed_paste)`)
  머리 `ESC[200~` · 본문 · 꼬리 `ESC[201~`를 `pty.write` 세 번으로 쓰고, 꺼져 있으면 본문만 쓴다. 본문은
  한 바이트도 안 바꾼다 — 라이브러리의 `encodePaste`는 모드가 꺼진 갈래에서 `\n`을 `\r`로 바꾸므로 안
  쓴다. 로그는 `terminal: clip> paste len=N bracketed=0|1`이고 `len=`은 본문 길이 그대로다. 검색 프롬프트로
  가는 갈래(`dumpFindPaste`)는 안 바뀐다.
- `/.vimrc -> config/vimrc`(PE-M2). 링크 · seed(`seedVimrc()`, `O_EXCL`) · `config_test`의 규칙 다섯 ·
  설정 디스크가 없을 때의 댕글링과 stub은 `docs/guides/key-files.md`의 `kernel/vim/` 항목에 있다.

## 다시 조사하지 말 것

- bracketed paste의 실측 — 셸 셋과 vim이 `ESC[?2004h`를 보내는 것 · fish가 프롬프트 내내 켜 두지 않는
  것 · fish가 꼬리까지 키를 삼키는 것 · ghostty vt의 모드 2004가 `Terminal.modes` 하나인 것 — 은
  measurements 75. 덤으로, 꼬리를 빠뜨리는 mutation은 새 검사 21이 아니라 기존 검사 11(한 줄 붙여넣기)이
  먼저 잡는다. `ModeState.get`은 `*const`를 받는다.
- 모드가 꺼진 프로그램(`cat`)에 감싼 글자를 주면 tty의 `ECHOCTL`이 `^[[200~`를 화면에 찍는다 — 검사
  22의 음성 판정이 그 글자다. tty의 에코와 `cat`의 출력 순서는 스케줄이 정하므로 화면 모양이 아니라
  `echo PEONE` 개수(+2)로 판정한다.
- `vim -e`의 대체 화면과 `-T dumb` · `HOME=/`의 `scriptnames` · zsh에서 `?`를 따옴표로 감싸는 것 · 게이트
  키 이름은 measurements 74. `>`는 `shift-dot`이다.
- vimrc에 틀린 줄이 있어도 `scriptnames`는 2 자리에 `/.vimrc`를 그대로 찍는다 — 양성 기다림만으로는
  에러를 못 보고, `Error detected while processing`이 화면에 없다는 음성 검사가 필요하다.
- `seedOneFile`에는 `O_TRUNC`가 없다. `O_EXCL`만 빼면 seed가 파일 앞부분을 같은 글자로 덮을 뿐이라
  사람이 더한 줄이 남는다 — "매 부팅 다시 쓴다" mutation은 `.EXCL`을 `.TRUNC`로 바꾸는 것이다.
- 부팅 넷의 시리얼 로그는 전부 남는다 — PE-M0 당시 체인이 A · B · D를 지워 `/tmp/tmp.*`를 1초마다
  복사했는데, AL-M0가 지우는 자리를 없애고 GF-M1이 `out/gate-logs/`로 옮겼다(`docs/guides/lessons.md`의
  "회차의 로그는 out/gate-logs…" 절).

## 탈출로

- 모드를 켠 채 죽은 자식 뒤에 `^[[200~`가 끼면 `reset`(RIS)이 모드를 끈다.
- 사용자 vimrc를 안 쓰려면 `/config/vimrc`를 비우거나 지운다 — 지우면 다음 부팅에 seed가 다시 깔린다
  (seed의 `O_EXCL` 규칙은 [[project_shell_history]]의 "이미 설정 디스크를 가진 기계"). `vim -u NONE`은
  시스템 vimrc까지 건너뛴다.
- `/config/vimrc`에 틀린 줄을 넣으면 vim이 뜰 때마다 `Error detected while processing /.vimrc`를 찍는다.
  시스템 vimrc(`/etc/vim/vimrc`)는 initrd에서 와서 사람이 망가뜨릴 수 없다.

## 관련

[[project_copy_mode]](CM 결정 9가 비워 둔 자리를 M1이 채웠다) ·
[[project_guest_ergonomics]](위험 2의 autoindent 계단과 비목표 2의 vimrc) ·
[[project_shell_tools]](gitconfig seed와 댕글링 링크 — M2가 같은 모양을 따랐다) ·
[[project_gate_screen_echo]](검사 21 · 22와 config 1 · 2차의 판정 글자) ·
[[project_gate_chain_composition]](CM 결정 9가 인용한 부채 — 이번에는 두 갈래를 다 본다) ·
[[project_write_or_reuse]](`encodePaste`를 안 쓴 저울) ·
[[project_guest_network]](dhcpcd의 로그 순서는 네트워크를 쓰는 다른 체인에도 유효하다)
