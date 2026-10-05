---
name: project_escape_latin
description: 한글을 치다가 Esc를 누르면 조합을 확정하고 영문으로 돌아온다(Patal의 ESC라틴). esc_latin=on|off가 hangul_toggle 목록이 아니라 따로 있는 키인 이유, argv에 실어 보낸 길, readKeys가 hangul_on의 앞뒤를 비교하는 이유(EL-M0, 2026-10-05 종료)
metadata:
  type: project
---

Escape Latin(EL)은 2026-10-05에 EL-M0 하나로 닫혔다. 사용자의 요청 한 줄
("esc키 누르면 한글 자판인 경우 영문자판으로 전환; vim 사용할 때 큰 도움이
됨")에서 시작했고, 사용자의 macOS 입력기 Patal의 `ESC라틴` trait과 같은
동작이다 — 조합을 확정하고, 영문으로 돌리고, Esc 자체는 프로그램이 받는다.
design은 `docs/specs/2026-10-05-tars-escape-latin-design.md`, plan은
`docs/plans/2026-10-05-tars-escape-latin-el-m0.md`.

설계 · plan은 Opus 서브에이전트가, 구현은 Sonnet 서브에이전트가, 대조 · 루트
게이트 · commit은 lead(Fable)가 했다. planner가 lead의 권고 하나를 바로잡았고
그것이 이 기억의 첫 항목이다.

## 설정이 `hangul_toggle`의 다섯째 이름이 아니라 따로 있는 키인 이유

lead는 argv가 여덟 칸으로 꽉 차 있으니 전환 키 목록에 `esc_latin`을 더하자고
권했다. planner가 seed를 읽고 뒤집었다 — `save()`가 쓰는 seed `tars.conf`에
`hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap`이 글자 그대로
있다. 목록에 이름을 더하면 새 기본값은 새로 만든 파일에만 들어가고, 이미 쓰고
있는 기계(설치한 노트북의 설정 파티션은 ISO를 갈아도 남는다)에서는 이 기능이
꺼진 채로 뜬다. 요청한 사람의 기계가 바로 그 기계다.

그래서 `esc_latin=on|off`(기본 `on`)는 따로 있는 키다. 그 줄이 없는 파일에서
기본값이 되는 성질 — `shell_config` · `net` · `firewall`을 더할 때마다 써 온
것이다. 교훈은 "기본값을 바꾸는 일은 seed가 무엇을 적어 두었는지부터 본다"다.

argv는 권고대로 간다. init이 목록 문자열 끝에 `esc_latin`을 붙여 여덟째 칸
그대로 넘기고(`Config.terminalToggles`, 순수 함수), terminal의 `Toggles`가
그 이름을 받는다. 그래서 같은 이름의 구조체 둘이 다른 뜻이다 — init 쪽은
"파일의 `hangul_toggle` 줄", terminal 쪽은 "argv로 온 목록". 두 주석이 그
차이를 적는다. init 로그의 `toggles=`는 파일의 목록 그대로이고 줄 끝에
`esc_latin=`이 붙는다. terminal 로그의 `toggles=`에는 `,esc_latin`이 붙는다.

## Esc의 뜻은 normal 모드 · 수정키 없음 · 한글 켜짐일 때뿐이다

자리는 `hangulLayer`의 Ctrl · Alt · Meta 갈래 바로 뒤다. 확정하고
(`commitHangul`), 끄고(`hangul_on = false`), null을 돌려준다. null이라서 Esc는
평소의 길(`keymap`)로 0x1b가 되어 PTY로 나가고, 확정분은 `readKeys`가 그
바이트보다 먼저 쓴다 — 조합 중이었으면 한 write에 "음절 3바이트 + ESC"다
(`key> 4 byte(s)`). vim은 글자를 받은 뒤에 Esc를 받는다.

copy mode와 검색 프롬프트의 Esc는 안 바꿨다. 둘 다 `handleKey`에서 한글 층보다
앞에서 Esc를 가로채는 한 겹 벗기기 명령이고, 한/영은 셸에 칠 글자의 상태라
모드에 들어갔다 나와도 그대로여야 한다(HI design 결정 5의 직교성). Shift+Esc와
`Ctrl+[`도 안 본다 — Patal을 따랐다.

## 바이트를 내보내는 키는 `.redraw`를 못 돌려준다

`Action`은 union이라 하나만 나른다. Esc는 `.bytes`여야 vim이 받으므로
`.redraw`를 함께 돌려줄 수 없다. 조합 중이었으면 확정분이 `redraw`를 켜지만,
조합 없이 Esc만 치면 아무것도 안 켜서 상태 줄의 `한`이 다음 프레임까지 남고
게이트의 유일한 창구(`hangul> on=…` 줄)도 안 찍힌다. mutation 1이 이것을
그대로 보였다 — 안에서는 한글이 꺼졌는데 화면과 로그에는 안 나타난다.

처방은 `readKeys`가 `handleKey` 앞에서 `hangul_on`을 읽고 뒤와 비교해 `redraw`를
켜는 한 줄이다. `to_needle`을 `handleKey` 앞에서 읽는 것(SH design 결정 5)과
같은 자리다. `Action`에 variant를 더하지 않은 것은 IS-M1이 `Action.caps`를 안
만든 것과 같은 판단이고, 앞으로 `hangul_on`을 바꾸는 길이 또 생겨도 이 한 줄이
덮는다.

## 게이트는 설정 디스크를 안 고치는 것으로 옛 파일을 본다

hangul 체인의 설정 디스크에는 `hangul_toggle` 목록은 있고 `esc_latin=` 줄은
없다 — EL 전에 만든 설정 파일의 모양 그대로다. 디스크를 고치지 않는 것 자체가
"옛 파일에서도 켜지는가"를 게이트가 보게 한다. 새 검사 넷(21~24) 중 24가 실제
vim에서 insert로 `닷`을 치고 Esc를 누른 뒤 `:wq`로 나와 `cat`으로 확인한다.
`esc_latin=off` 갈래는 디스크가 하나 더 필요해 부팅으로 안 보고 호스트
검사(`input_test` 72 · `config_test`)가 본다.

## 숫자

- hangul 체인 65초 → 81초(검사 넷이 16초). 루트 게이트 19체인 2/2, 50분 58초
  (PD-M4의 49분 56초 + 62초).
- `input_test` OK 16 → 20. mutation 다섯 판 전부 예상한 검사에서 빨갰다.
- 편집 36 · 8파일 · +570 −17. 구현자가 Edit 도구 대신 plan 본문에서 뽑은
  스크립트로 넣었고 여덟 파일이 planner의 사본과 바이트까지 같았다.

## 남긴 것

- seed `tars.conf`의 `ntp:` 주석이 TD 전의 설명("부팅할 때 한 번만 묻고")으로
  남아 있다. 고치면 seed의 글자가 바뀌어 `config` 체인을 함께 본다(이월 숙제).
- 비목표: copy · find의 Esc, Shift+Esc와 `Ctrl+[`, 반대 방향(insert로 돌아갈 때
  한글 되살리기 — vim의 모드를 우리가 모른다), 패널마다 한/영, `esc_latin=off`
  부팅.

관련: [[project_hangul_input]] · [[project_input_status]] ·
[[project_search_hangul]] · [[project_config_persistence]] ·
[[project_zig_out_staleness]]
