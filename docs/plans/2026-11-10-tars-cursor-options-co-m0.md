# CO-M0 — 커서 숨김: 패널이 보내는 CSI ? 25 l / h

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-cursor-options-design.md`(결정 1~4)
Status: 초안(2026-11-10)

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `ae3dca6`).

1. `computeShellCursor`(`terminal/src/vt.zig:1086`)의 검사 순서: copy mode → 포커스 → 뷰포트(`state.cursor.viewport`) → 모양. `cells()`
   (`:780`)가 프레임마다 한 번 부르고, 같은 값이 `invert_cursor`(`:783`) · `cur_spot`(`:792`) · `cursorMark()`(`:1137`)로 나간다.
   그러니 조건 하나가 반전 · 띠 · dirty 행 · 로그를 함께 바꾼다.
2. `state.cursor.visible`은 `self.state.update`(`:771`)가 채운다 — `computeShellCursor`가 그 뒤에 불리므로 이 프레임의 값이다.
3. preedit 치환(`vt.zig` 커서 층의 `cp = pcp`)은 `shell_cursor`를 안 본다. design 결정 2대로 preedit이 있으면 숨김을 무시하므로 지금의
   두 칸 반전이 그대로 남는다.
4. 호스트 검사의 선례: CU-M0의 검사 84~87(`vt_test.zig:2370` 근처, `cuInverted` · `cuExpectMark` · `cuCellAt`). 마지막 번호는 129.
5. 게스트 판정의 선례: render 체인 검사 20~24(`render/check.sh:700` 근처). `cursor_shape_check`는 `drawn=` 뒤에 row · col을 기다려서
   `drawn=none`에 못 쓴다 — 기다림 · settle · 반전 셀 수를 직접 쓴다. 마지막 번호는 37.
6. `dirty_test.zig:169`가 `?25l/h`를 무작위로 먹이고 증분 목록과 새 목록을 비교한다. 이제 그 조작이 커서 층을 바꾸므로 이 검사가
   처음으로 "숨김 ↔ 보임의 dirty 행"을 덮는다. 따로 더할 것이 없다.

## Task 1 — `terminal/src/vt.zig`

`computeShellCursor`의 뷰포트 검사 바로 뒤:

```zig
// 패널의 프로그램이 DECTCEM(`CSI ? 25 l`)으로 커서를 숨겼다(CO design 결정 1).
// preedit은 숨김을 무시한다 — 두 칸 반전이 조합 중인 글자의 표시다(결정 2).
if (!self.state.cursor.visible and self.preedit == null) return null;
```

함수 머리 주석의 우선순위 표에 한 줄(`숨겼는가(preedit 없음) → 없다`)을 뷰포트 다음에 더한다.

## Task 2 — 호스트 검사(`terminal/src/vt_test.zig`, 검사 130~133)

- 130. 20×5 화면, `?25l` → `cursorMark()` null, 반전 0. `?25h` → (0,0) block, 반전 1.
- 131. `CSI 6 SP q`(bar) 뒤 `?25l` → null(띠도 없다). `?25h` → bar로 돌아온다.
- 132. `?25l` 뒤 `setPreedit(0xAC00)` → 두 칸 block, 반전 2(결정 2). `setPreedit(null)` → 다시 null.
- 133. 숨긴 채 글자를 쓰고 커서를 옮겨도(`abc`, `CSI 3;4 H`) null — 숨김은 자리와 상관없다.

빨강 하나: Task 1의 조건을 빼고 `zig build test`가 130에서 실패하는지 본 뒤 되돌린다.

## Task 3 — 게스트 판정(`render/check.sh`, 검사 24 뒤에 38 · 39)

번호를 25~37 사이에 끼우지 않는다 — 다른 문서가 "검사 25~32"를 가리킨다. 놓는 자리는 검사 24(기본 block으로 되돌림) 뒤, vim 앞이다.
주석에 번호가 순서와 다른 이유를 한 줄.

- 38. `printf '\033[H\033[2J\033[?25l'` → `wait_for_cursor 'vt=block drawn=none'` → settle → 마지막 줄이 여전히 `drawn=none`(fish가
  프롬프트를 그리며 되살리지 않았다) · 덤프가 안 잘림 · 반전 0.
- 39. `printf '\033[H\033[2J\033[?25h'` → 기다림 패턴 `${CU_WANT}`(검사 20의 그 줄) · 반전 1. 뒤의 vim 검사가 보이는 커서를 물려받는다.
- 판정: `make check CHAIN=render` 단독 2회. 그 전에 `check.sh` 입구 검사의 grep 정규식을 고친 체인에 한 번 대 본다(FU-M1 결과 4).

만약 38에서 fish가 `?25h`를 다시 보내 `drawn=none`이 유지되지 않으면, 그것은 design 위험 1의 반대 방향이라 무해하다 — 판정을
`printf '\033[?25l'; sleep 3`로 바꿔 sleep 동안의 프레임을 보고, 결과 절에 적는다.

## Task 4 — fakesteak QEMU probe(저장소 밖 `out/co-m0/probe.sh`, FU-M1 Task 6의 방식)

`make iso ISO_LAYERS="fakesteak"` → 빈 NVMe에 설치 → NVMe만으로 부팅:

- autorun이 띄운 fakesteak 동안 screendump 다섯 장(0.3초 간격). 각 장에 흰 반전 칸(커서 색 `#F0F0F0`이 바탕인 셀)이 없다.
- 같은 동안의 `cursor>` 줄이 모두 `drawn=none`.
- `sendkey ctrl-c` → fakesteak의 `?25h`로 커서가 돌아온다: 프롬프트 자리에 반전 칸 하나(screendump 한 장).

비교군으로 Task 1 전의 ISO(`v0.2.0` 판 fakesteak ISO)에서 같은 screendump를 떠서 반전 칸이 장마다 다른 자리에 있는지 본다 — design
확인 4의 추정을 판정한다. 결과가 추정과 달라도 Task 1은 그대로다.

## 끝내기

CO-M1이 이어진다. 루트 게이트는 CO-M1 끝에 한 판(design 위험 1 · 4의 판정을 함께 한다). CO-M0만의 커밋은 체인 단독 PASS로 한다.

## 비목표

design의 비목표. fakesteak 데모 ISO를 다시 내는 것(사용자가 말하면 `project_release`의 절차로).

## 결과

(작성 전)
