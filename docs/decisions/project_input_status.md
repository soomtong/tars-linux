---
name: project_input_status
description: "화면 맨 아래 여백의 상태 줄 — 한/영 · 자판 · 대문자 잠금(IS-M0 · M1, 2026-09-09). 왜 아래 여백인지 · 순수 status.zig · Action.hangul 갱신 구멍"
metadata:
  type: project
---

# Input Status (IS) — 입력기 상태를 화면에 보여 주는 층

IS-M0 · IS-M1(2026-09-02~09)이 세웠다. Hangul Input이 비목표로 남긴 "대문자
잠금 · 한/영 · 자판이 몸 밖에 하나도 안 드러난다"를 닫는다. 코드는
`terminal/src/status.zig`, 호스트 검사는 `status_test`, 게이트 판정은
`hangul/check.sh`의 `status>` 줄이다. milestone별 경과와 게이트 시간은
2026-10-20에 지웠다(커밋 이력에 있다).

- design: `docs/specs/2026-09-02-tars-input-status-design.md`
- plan: `docs/plans/2026-09-02-tars-input-status-is-m0.md` ·
  `.../2026-09-08-tars-input-status-is-m1.md`

## 왜 아래 여백인가

"맨 아랫줄 오른쪽 끝"은 검색 프롬프트와 같은 줄이라 터미널 한 줄을 영영
덮어써야 하고, "변할 때만 잠깐 뜨는 배지"는 잊은 뒤에는 아무것도 안 보여
원래 문제를 안 푼다(사용자가 골랐다).

아래 여백은 공짜로 비어 있던 자리다. 1280×800에 `GRID_Y=20` · `rows=47` ·
`ROW_HEIGHT=16`이라 격자가 y=20~772를 쓰고 28픽셀이 남는다. 16픽셀 글자 한
줄이 들어가고 `cells()` · `rows` · PTY 크기 · 검색 프롬프트와 안 부딪힌다.
대가는 격자 밖이라 기존 관측 창구(`screen>` · `style>` · `ink>`)가 하나도 못
본다는 것이다 — 그래서 픽셀을 직접 세는 판정을 넣었다("검증 구조").

## 왜 예쁜 이름인가

`@tagName`이면 화면에 `shin_pcs`가 뜬다. 사용자가 사람이 읽는 이름(`신세벌
PCS` · `공세벌 3-P3` · `신세벌 P2` · `두벌식` · `쿼티` · `드보락`)을 골랐다.
표가 하나 느는 대가의 처방은 `else` 없는 `switch`다 — 자판을 더하며 이름을
빼먹으면 컴파일 에러다. 배열이나 map이면 조용히 통과하고 증상은 화면의 빈
칸이다.

`MAX_LEN`은 이름 표를 `comptime`에 훑어 세므로 버퍼를 손으로 안 늘려도 된다.
`promptText`가 173바이트를 주석의 산수로 정당화한 것과 갈리는 이유는 여기는
값의 집합이 닫혀 있기 때문이다(needle 같은 가변 입력이 없다).

## 왜 `status.zig`가 따로 서는가

SP-M1에서 `promptText`가 `main.zig`의 private이라 `vt_test`가 못 불렀고
프롬프트 글자는 게이트로만 볼 수 있었다. 상태 줄은 상태를 받아 문자열을
돌려주는 순수 계산이라 `status_test`가 자판 여섯 × 한/영 둘을 부팅 없이 돈다.

"순수"가 "import가 비어 있다"는 뜻은 아니다. `statusText`가 `input.State` ·
`input.LatinLayout`을 보므로 `input.zig`를 import하고 `@cImport("linux/input.h")`가
따라온다 — 그래서 `status_test`는 `hangul_test`와 달리 `link_libc = true`가
필요하다. `LatinLayout`은 이름 하나 때문에 `latinChar()`와 `keymap`의 경계를
흔들 일이 아니라 옮기지 않았다.

## 검증 구조 — 판정이 왜 둘인가

`text=` 판정은 `statusText`가 만든 문자열을 되읽을 뿐이라 `drawStatus`가
통째로 비어 있어도 초록이다. 그래서 띠 안의 픽셀을 세는 판정을 더했다.

| 판정 | 무엇을 잡는가 |
|---|---|
| `status> text=` | 글자를 맞게 만들었다 |
| `status> ink fg=` | 그 글자가 프레임버퍼에 닿았다("안 그렸다") |
| `status> caps ink on=N off=M` | `CAPS` 칸의 색이 바뀌었다("안 밝아졌다") |

`ink fg=` 실측값은 383(영문) · 381(한글)이다. `caps ink`는 `CAPS` 칸의 x
범위를 안 잰다 — `STATUS_ON` · `STATUS_OFF`가 여백 안에서 그 칸에만 쓰여 띠
전체를 세도 답이 같다. 범위를 재면 `drawStatus`의 col 전진 산수를
`dumpStatus`가 다시 해야 하고, 어긋나면 언제나 0이라 "안 그렸다"와 증상이
같아진다. `on`과 `off`를 한 줄에 함께 찍어야 "아예 안 그렸다"와 "반대 색으로
그렸다"가 갈린다(IS-M1 실측 5).

## `Action.hangul`의 갱신 구멍 — IS-M1이 닫았다

긴 CapsLock이 `self.caps_lock`만 뒤집고 `nothing`을 돌려줘 `needs_redraw`가
안 켜졌다. 대문자 잠금이 다음 글자에서만 드러나던 동안은 버그가 아니었고
`CAPS` 칸이 생기며 버그가 됐다. 처방은 `.hangul`을 `.redraw`로 넓히고 그
분기가 그것을 돌려주게 한 것이다. 뜻은 원래부터 "화면을 다시 그려라"였고
둘째 호출자는 이름이 좁았다는 신호였다.

`Action.caps`를 더하지 않았다 — 셋째 호출자에서 `main.zig`가 `if (keys.hangul
or keys.caps)`가 되고, 넷째를 빼먹는 것이 다음 사고다(HI-M1 실측 2와 같은
함정).

## milestone을 둘로 가른 이유

| | 무엇 | 갱신 경로 |
|---|---|---|
| IS-M0 | 칸 셋 | 기존 것만 쓴다 — `Action.hangul`이 이미 `needs_redraw`를 켠다 |
| IS-M1 | `CAPS` 칸과 색 셋 · `Action.hangul` → `Action.redraw` | 새 경로 하나 |

M0이 증명된 갱신 경로만 쓰므로 M1에서 `CAPS`가 안 밝아지면 그리는 층을
의심할 필요가 없다. 실제로 M1 판정이 `on=0`으로 실패했을 때 띠에 `off=87`이
멀쩡히 있어 의심할 것이 `Action.redraw` 하나뿐이었다.

## 실행이 증명한 것 — 값과 근거는 design의 "IS-M0/IS-M1이 실측한 것" 절에

여기 남길 것은 둘이다. "매 프레임 찍지 않는다"는 게이트 시간이 아니라 로그 줄 수로
본다(`screen>` 57번에 `status>` 12줄 — 매 프레임이면 114줄). 그리고 호스트 검사가
게이트보다 먼저 지키므로 게이트 판정을 음성으로 확인하려면 호스트 검사 넷도 함께
되돌려야 한다 — 위층을 보려면 아래층을 먼저 끈다. 편집 사고(`dependOn`의 똑같은 줄
다섯 중 첫 줄에 들어간 삭제 · 지울 줄을 안 지우고 넣기만 한 편집)와 Zig 컴파일러의
한계(에러 셋까지만 · 타입이 걸리는 자리만)는 design의 그 절에 있다. 체인의 시리얼
로그를 호스트에서 읽는 법은 `docs/guides/lessons.md`의 "회차의 로그는
out/gate-logs…" 절이다(IS 당시의 `-e TMPDIR=/workspace/out`은 GF-M1이 필요 없게 했다).

## 관련

- [[project_hangul_input]] — 이 서브프로젝트가 이어받은 비목표가 거기 있다
- [[project_render_cost]] — 시리얼 한 줄이 0.6~8.8밀리초라는 실측이 "값이
  바뀔 때만 찍는다"의 근거다
- [[project_search_position]] — `promptText`가 private이라 게이트와 `vt_test`가
  나눠 봐야 했던 자리. `status.zig`가 따로 서는 이유다
- [[project_gate_chain_composition]] — "게이트는 자기가 안 보는 것을
  통과시킨다". 여백이 격자 밖이라 `ink fg=` 판정이 필요했던 것이 같은 병이다
