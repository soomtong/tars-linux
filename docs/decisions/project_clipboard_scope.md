---
name: project_clipboard_scope
description: 클립보드가 vt.Screen 밖으로 나와 terminal 전체에 하나가 됐다(기본 shared, tars.conf의 clipboard=pane이 옛 동작). 요청의 전제(워크스페이스마다)와 실제(패널마다)의 차이, workspace 범위를 안 둔 이유, argv 아홉째 칸, 그리고 줄 끝에 고정한 게이트 판정이 다음 키에 깨진 일(CB-M0, 2026-10-05 종료)
metadata:
  type: project
---

Clipboard Scope(CB)는 2026-10-05에 CB-M0 하나로 닫혔다. 사용자의 요청
("터미널 패널이나 워크스페이스 사이 clipboard를 공유해서 사용하는 옵션;
기본적으로 전체 공유 활성화. 현재는 각각의 워크스페이스가 독립된 클립보드를
가짐")에서 시작했다. design은 `docs/specs/2026-10-05-tars-clipboard-scope-design.md`,
plan은 `docs/plans/2026-10-05-tars-clipboard-scope-cb-m0.md`.

설계 · plan은 Opus 서브에이전트가, 구현도 Opus 서브에이전트가, 대조 · 루트
게이트 · commit은 lead(Fable)가 했다. Escape Latin([[project_escape_latin]])과
같은 날 같은 방식으로 열었고, 사용자의 "안전하게 순차 진행" 결정으로 EL 뒤에
구현했다.

## 요청의 전제가 하나 틀려 있었다 — 워크스페이스가 아니라 패널마다였다

클립보드는 `vt.Screen`의 칸 하나(`clip`)였다. CM이 그렇게 정했을 때
([[project_copy_mode]] 결정 1)는 화면이 하나였고, WP가 패널마다 `Screen`을
하나씩 두면서([[project_workspace_panes]]) 클립보드도 패널 수만큼 생겼다. 같은
워크스페이스 안의 다른 패널에 `Cmd+V`해도 `clip> paste empty`였다 — 사용자가
본 "워크스페이스마다 독립"은 워크스페이스마다 패널이 하나뿐일 때의 모습이다.
planner가 mutation 1(범위를 무시하고 늘 패널 칸)로 CB 전 동작을 재현해 확인했다.

이 차이가 범위의 이름을 정했다. 옛 동작을 남기는 범위는 `workspace`가 아니라
`pane`이다. `workspace`(같은 워크스페이스 안에서만 나눈다)는 한 번도 있었던
적이 없는 셋째 동작이라 두지 않았다(design 비목표 1). 쓰는 사람이 생기면
`Workspace`의 칸 · 워크스페이스를 닫는 자리의 해제 · `pick`의 셋째 갈래를 더한다.

## 모양 — 주인은 `main.zig`, 칸은 `clipboard.zig`, 화면은 글자만 뽑는다

새 순수 모듈 `terminal/src/clipboard.zig`가 `Scope`(`shared` · `pane`) ·
`Clipboard`(할당자 · `?[:0]const u8`, `set`이 옛것을 해제) · `pick` 셋이다.
`vt.Screen.copyYank(clip)`은 선택을 `clip.alloc`으로 문자열로 만들어 `clip.set`에
넘기고(할당한 쪽과 해제하는 쪽이 같은 할당자), `findPaste(text)`는 글자를 인자로
받는다. `Screen.clip` · `clipboard()`는 지웠다. `main.zig`의 `Clips`가 공유 칸
하나를 들고 `of(pane)` 한 자리에서 칸을 고르며, `y` · 포인터 뗌 · `Cmd+V` ·
검색창의 `Cmd+V` 넷이 전부 `Clips.yank` · `Clips.paste`를 지난다. `Pane.clip`은
패널을 닫는 두 자리에서 해제한다. `pasteParts`(모드 2004)는 `Screen`에 남는다 —
감쌀지는 붙이는 패널의 자식이 정한다.

후보 둘을 버렸다. `shared`면 `y`할 때 모든 `Screen`에 사본을 넣는 것(칸이
여럿인데 같아야 한다는 규칙을 코드가 아니라 규율로 지킨다), `Screen`에
`*Clipboard`를 주입하는 것(공유 칸의 수명이 `Screen`보다 길다는 사실이 타입에
안 보인다).

## 설정은 argv의 아홉째 칸으로 갔다

`tars.conf`의 `clipboard=shared|pane`(기본 `shared`). `Child.argv`가 `[8:null]`로
꽉 차 있어 `[9:null]`로 넓혔고, 같은 타입을 쓰는 자리 여섯(terminal · 콘솔 셸 ·
서비스 · `CHRONYD_ARGV` · `DHCPCD_ARGV` · `WIFI_ARGV`)을 함께 고쳤다 — 리터럴
길이가 타입과 안 맞으면 컴파일이 막히므로 하나라도 빠뜨리면 빌드가 말한다.
EL이 같은 날 `esc_latin`을 목록 문자열에 실어 보낸 것과 다른 길을 택한 이유는,
여덟째 칸이 `parseToggles`가 콤마로 읽는 집합이라 뜻이 다른 값을 섞으면 파서
둘이 한 문자열을 나눠 읽게 되기 때문이다.

로그는 짝 둘이다 — `tars-init: config … clipboard=`(파일에서 읽었다)와
`terminal: clipboard scope=`(argv를 건너 닿았다). 범위 이름이 init과 terminal에
한 벌씩 있고 둘을 잇는 것은 argv 문자열뿐이라 컴파일러가 못 잡는다. 게이트의
검사 13(`clipboard=pane`을 심은 부팅 B)이 그 경로를 끝까지 본다. 심는 값이
기본값과 다른 것이 요점이다 — 설정을 통째로 무시하는 코드도 `shared`로는 초록이다.

## 줄 끝에 고정한 판정은 다음 키가 깨뜨린다

regression에서 hangul 체인이 18초 만에 빨갰다. EL-M0이 넣은 판정이
`esc_latin=on$`로 init 로그 줄 끝에 고정돼 있었고, CB가 그 뒤에
`clipboard=shared`를 붙였기 때문이다. planner의 regression은 EL 전 HEAD에서
돌아 그 판정을 못 봤다. 처방은 바로 위 `toggles=` 판정이 이미 쓰던 `( |$)`
경계다(plan 밖 편집 하나, `hangul/check.sh` +4 −2).

lessons의 "키를 더할 때는 맨 뒤에 붙인다"는 앵커를 줄 끝에 두지 말라는 뜻도
된다 — 맨 뒤에 붙이는 규칙과 줄 끝 앵커는 서로를 깨뜨린다. 저장소에서 config
줄을 줄 끝에 고정한 자리는 그 하나뿐이었다(`rg`로 확인). 같은 날 같은 줄에
키 둘이 붙은 것이 이 사고를 바로 드러냈다.

## 게이트에서 배운 것

- `clip> paste len=` 줄은 어느 패널의 것인지 말하지 않는다. 붙인 글자가 실행된
  결과를 포커스 패널의 마지막 `screen>` 줄에서 함께 본다
  ([[project_gate_screen_echo]]).
- 음성 판정(다른 패널의 `Cmd+V`가 비었다)에는 `paste empty`가 하나 느는 양성
  신호와 대조군(`y`한 패널에서는 붙는다)을 붙인다.
- 부팅 B의 NUL 검사를 부팅 A처럼 크기를 두 번 재는 모양으로 쓰면 두 읽기 사이에
  게스트가 쓴 프레임 덤프가 차이로 잡혀 거짓으로 빨개진다. 한 번의 읽기로 센다.
- seed `tars.conf`가 EL · CB로 40 → 48줄이 되어 게스트 화면 47줄을 넘었다.
  `config` 체인 1차가 보는 `| shell_config=on`은 25번째 줄이라 남았고
  `wait_for_screen`은 로그 전체의 `screen>`을 보므로 밀린 줄도 어느 프레임엔가
  있다. 다음에 키를 더하는 사람은 그 검사를 함께 본다.

## 숫자

- pane 체인 33초 → 43초(부팅 B 하나). 루트 게이트 19체인 2/2, 51분 15초
  (EL-M0의 50분 58초 + 17초).
- 편집 88 · 새 파일 2 · 13파일 · +536 −102(hangul 처방 포함). `vt_test` OK 82
  그대로, `clipboard_test` OK 7. mutation 넷 전부 예상한 검사에서 빨갰다.

## 남긴 것(비목표)

범위 `workspace` · 클립보드가 재시작을 넘는 것 · OSC 52 · 다른 프로세스와의
클립보드 · 상한(PE 위험 1) · 실행 중 범위 바꾸기 · 클립보드 기록.

관련: [[project_copy_mode]] · [[project_workspace_panes]] ·
[[project_paste_ergonomics]] · [[project_config_persistence]] ·
[[project_seeding_a_config_disk]] · [[project_gate_screen_echo]] ·
[[project_escape_latin]]
