---
name: project_paste_ergonomics
description: 붙인 글자와 고친 설정이 사람이 뜻한 대로 남게 한 셋 — service 체인이 dhcpcd의 adding default route 줄까지 기다린다(M0), 자식이 모드 2004를 켰으면 Cmd+V를 ESC[200~ · ESC[201~로 감싼다(M1, CM 결정 9를 다시 열었다), /.vimrc가 /config/vimrc로 가는 링크이고 init이 주석뿐인 seed를 깐다(M2). PE-M0~M2, 2026-10-04 종료. 새 체인 없이 copy 검사 21 · 22와 config 1 · 2차 부팅이 본다
metadata:
  type: project
---

Paste Ergonomics(PE)는 2026-10-04에 M0~M2로 닫혔다. GE가 남긴 둘(터미널의 bracketed paste · 사용자
vimrc 영속)과 루트 게이트를 흔든 체인 경합 하나에서 시작했다. 설계와 plan은 Opus 서브에이전트가,
구현은 M0 · M2를 Sonnet, M1을 Opus 서브에이전트가 했고, Fable이 대조 · 루트 게이트 · commit을 맡았다.

- design: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
- plan: `docs/plans/2026-10-04-tars-paste-ergonomics-pe-m0.md` · `-pe-m1.md` · `-pe-m2.md`

## 무엇이 바뀌었나

- `service/check.sh`의 `boot_ssh`(PE-M0). dhcpcd는 `eth0: leased …`를 찍은 다음에 주소를 붙이고
  (`ipv4_applyaddr`) 경로 줄을 찍는다. 그 사이에 hostfwd로 붙으면 SLIRP은 호스트 쪽 연결을 받아 주지만
  게스트가 SYN을 버려서 `ssh-keyscan`이 빈 값을, ssh가 `banner exchange` 타임아웃을 낸다. 그래서
  `leased` 뒤에 `eth0: adding default route via 10\.0\.2\.2`를 한 줄 더 기다린다. 코드는 0줄이다.
- `vt.Screen.pasteParts`와 `dumpPaste`(PE-M1). 자식이 모드 2004를 켰으면(`term.modes.get(.bracketed_paste)`)
  머리 `ESC[200~` · 본문 · 꼬리 `ESC[201~`를 `pty.write` 세 번으로 쓰고, 꺼져 있으면 본문만 쓴다. 본문은
  한 바이트도 안 바꾼다 — 라이브러리의 `encodePaste`는 모드가 꺼진 갈래에서 `\n`을 `\r`로 바꾸므로 안
  쓴다. 로그는 `terminal: clip> paste len=N bracketed=0|1`이고 `len=`은 본문 길이 그대로다. 검색 프롬프트로
  가는 갈래(`dumpFindPaste`)는 안 바뀐다.
- `/.vimrc -> config/vimrc`(PE-M2). `make_initrd.sh`가 `.gitconfig` · rc 셋 옆에 링크를 걸고, `init`이
  `storage_mounted`일 때 `seedVimrc()`로 주석 21줄(843바이트, ASCII)짜리 seed를 `O_EXCL`로 깐다.
  `config_test`가 seed를 다섯 가지로 지킨다 — 끝 개행 · ASCII · 비지 않은 줄은 전부 `"` · `/etc/vim/vimrc`
  언급 · `tabstop`이라는 낱말 없음. 설정 디스크가 없는 부팅(`render` 체인 · ISO)에서는 링크가 댕글링이고
  vim은 지금처럼 stub `defaults.vim`을 읽는다.

## 다시 조사하지 말 것

- 게스트의 zsh 5.9(ZLE 모듈) · bash 5.2(자기 안의 readline — `libreadline`을 링크하지 않는다) · fish
  4.0.2 · vim 9.1이 전부 `ESC[?2004h`를 보내고, 셸 셋은 명령을 띄우기 전에 `ESC[?2004l`을 보낸다. 감싸지
  않은 두 줄은 첫 줄이 곧바로 실행되고, 감싼 두 줄은 Enter까지 한 입력줄에 남는다.
- fish 4.0.2는 프롬프트 내내 모드 2004를 켜 두지 않는다. 인자를 치기 시작하면(`echo h`) 끄고 다음 키까지
  꺼진 채이고, 감싼 두 줄을 받은 직후에도 꺼진다. 그 순간에 붙이면 우리도 ghostty 앱도 감싸지 않는다.
  게이트의 붙여넣기는 빈 프롬프트에서 일어나 영향이 없다(design 위험 4).
- fish는 꼬리 `ESC[201~`가 올 때까지 붙인 글자를 하나도 그리지 않고 그동안 오는 키(Enter · ctrl-c 포함)를
  전부 삼킨다. 그래서 꼬리를 빠뜨리는 mutation은 새 검사 21이 아니라 기존 검사 11(한 줄 붙여넣기)이
  먼저 잡는다.
- ghostty vt의 모드 2004는 화면별이 아니라 `Terminal.modes` 하나다 — 대체 화면을 오가도 같은 값이고,
  RIS가 끈다. `vt_test` 95 · 96이 본다. `ModeState.get`은 `*const`를 받는다.
- 모드가 꺼진 프로그램(`cat`)에 감싼 글자를 주면 tty의 `ECHOCTL`이 `^[[200~`를 화면에 찍는다 — 검사
  22의 음성 판정이 그 글자다. tty의 에코와 `cat`의 출력 순서는 스케줄이 정하므로 화면 모양이 아니라
  `echo PEONE` 개수(+2)로 판정한다.
- `vim -e`는 `TERM=xterm-256color`에서 Ex 모드여도 smcup(`ESC[?1049h`)으로 대체 화면에 들어가 거기에 찍고
  나가면서 출력이 사라진다. 게이트에서 vim의 Ex 출력을 화면으로 보려면 `-T dumb`이다(게스트에 `dumb`
  terminfo가 없어도 vim이 내장 항목으로 조용히 넘어간다). design 실측의 pyte가 1049를 구현하지 않아 이것을
  놓쳤다.
- 게스트의 `HOME=/`에서 `scriptnames`는 `~/.vimrc`가 아니라 `  2: /.vimrc`를 찍는다. `HOME`을 빈
  디렉터리로 두고 재면 `~`로 축약된다.
- vimrc에 틀린 줄이 있어도 `scriptnames`는 2 자리에 `/.vimrc`를 그대로 찍는다 — 양성 기다림만으로는
  에러를 못 보고, `Error detected while processing`이 화면에 없다는 음성 검사가 필요하다.
- `seedOneFile`에는 `O_TRUNC`가 없다. `O_EXCL`만 빼면 seed가 파일 앞부분을 같은 글자로 덮을 뿐이라
  사람이 더한 줄이 남는다 — "매 부팅 다시 쓴다" mutation은 `.EXCL`을 `.TRUNC`로 바꾸는 것이다.
- zsh에서 `vim +set\ ts?`처럼 `?`를 따옴표 없이 치면 glob으로 펴려다 `zsh: no matches found`로 명령을 안
  돌린다. `+'set ts?'`로 감싼다. 게이트 키 이름은 `+` `shift-equal` · `'` `apostrophe` · `?`
  `shift-slash` · `>` `shift-dot`.
- 통과한 `service` 체인은 부팅 A · B · D의 시리얼 로그를 지우고 C만 남긴다. 부팅마다 로그를 얻으려면 체인을
  배경으로 돌리며 1초마다 `/tmp/tmp.*`를 복사한다(PE-M0 plan 3-3). 그래도 부팅 A의 마지막 1초는 놓칠 수
  있다.

## 탈출로

- 모드를 켠 채 죽은 자식 뒤에 `^[[200~`가 끼면 `reset`(RIS)이 모드를 끈다.
- 사용자 vimrc를 안 쓰려면 `/config/vimrc`를 비우거나 지운다 — 지우면 다음 부팅에 seed가 다시 깔린다
  (`O_EXCL`이 "없다"를 답한다). `vim -u NONE`은 시스템 vimrc까지 건너뛴다.
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
