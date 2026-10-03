# CI-M0 — `COPY` 칸이 뜨고 사라진다

Date: 2026-10-03
Design: `docs/specs/2026-10-03-tars-copy-indicator-design.md`
Status: 끝났다(2026-10-03). 값은 design의 "CI-M0이 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- copy mode에 있는 동안 상태 줄이 `EN  신세벌 PCS  쿼티  CAPS  COPY`가 되고,
  나가면 `  COPY`가 사라진다. 앞 넷은 안 움직인다(결정 1 · 2).
- 색이 넷이 된다 — `STATUS_COPY`(`0x00E0E8F0`)가 `COPY` 칸 전용이다(결정 3).
- `statusText(state, copy, buf)`가 된다. `MAX_LEN`이 36에서 42가 되고,
  손으로 늘린 버퍼는 없다(결정 4).
- `dumpStatus`가 넷째 줄 `status> copy ink=N`을 찍는다(결정 6).
- `copy/check.sh`가 진입 뒤와 Esc 뒤에 판정 둘을 더 한다. 키는 하나도
  안 더한다.
- 서브프로젝트 CI가 닫힌다. design의 `Status:`, `docs/decisions/project_copy_indicator.md`,
  `MEMORY.md`, `CLAUDE.md`의 표, `HANDOFF.md`를 함께 고친다.

## 착수 전에 확정한 것

1. copy 명령은 전부 `needs_redraw`를 켠다 — `main.zig`의 copy 루프 끝
   (`dumpCopy(screen, @tagName(cmd)); needs_redraw = true;`). 그래서 갱신
   경로를 새로 만들 자리가 없다.
2. hangul 체인의 `status>` 판정은 전부 첫 `meta_l-shift-c`(823행) 앞이다
   (366 · 379 · 448 · 668 · 697). `COPY`가 꼬리에 붙어도 기대값이 안 바뀐다.
3. `drawStatus`는 `CAPS`의 시작을 `text.len - CAPS.len`으로 센다. 꼬리에
   `COPY`가 붙으면 `Status.copy`를 보고 `GAP.len + COPY.len`만큼 더 물러나야
   한다 — 안 그러면 색이 한 칸 밀린다(design 위험 2).
4. `status_test`의 검사 10("가장 긴 줄이 `MAX_LEN`과 정확히 같다")은
   `copy=true`로 바꿔야 한다. 안 바꾸면 36 ≠ 42로 빨개진다 — 그것이 이
   plan의 첫 실패이고, 의도된 것이다.

## Task 1: `status.zig` · `status_test.zig`

- `pub const COPY = "COPY"`. `MAX_LEN`에 `GAP.len + COPY.len`을 더한다.
- `statusText(state, copy, buf)`. `copy`면 끝에 `GAP ++ COPY`.
- 검사 10을 `copy=true`로, 검사 13 · 14를 더한다.
- `expectText`가 `copy`를 받게 넓힌다. 기존 호출 열넷은 `false`.

## Task 2: `main.zig`

- `STATUS_COPY` 상수. `Status.copy: bool`.
- `drawStatus`: 꼬리를 셋으로 가른다 — 앞 세 칸 · `CAPS` · (있으면) `COPY`.
- `dumpStatus`: `STATUS_COPY` 픽셀을 함께 세고 `status> copy ink=N`.
- 루프: `.copy = screen.copyActive()`를 `statusText`와 `Status` 양쪽에.

## Task 3: `copy/check.sh`

- `status_text` · `status_copy_ink` 헬퍼(hangul 체인의 것과 같은 모양).
- 검사 2 뒤: `text=`가 `  COPY`로 끝나고 `copy ink>0`.
- 검사 6 뒤: `text=`에 `COPY`가 없고 `copy ink=0`.

## Task 4: 게이트

- `zig build test`(컨테이너) — Task 1 뒤에 한 번 빨간 것을 보고, 고친 뒤 초록.
- `copy/check.sh` · `hangul/check.sh` 각 한 번.
- 루트 게이트 3/3.

## Task 5: 문서

design `Status:` · 기억 · `MEMORY.md` · `CLAUDE.md` 표 · `HANDOFF.md`.
