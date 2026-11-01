# SE-M1 — 배선과 게이트: 뗌이 선택을 남기고, Shift 클릭이 늘린다

Goal: SE-M0의 순수 층을 `main.zig`의 두 자리에 이어 게스트에서 동작하게 하고, `pointer` 체인이 네 검사로 본다. 루트 게이트로 닫고
서브프로젝트를 끝낸다.

Architecture: `PointerWire.run`의 `.copy`가 `copyYank` 대신 `copyRelease`를 부르고(`Clips.release`), `PointerWire.press`가
`Stamp.extend`에 `mods.shift and 누른 패널.hasLinger()`를 넘긴다. 로그는 M0이 이미 찍는다(`copy> extend` · `copy> deselect`).
`pointer` 체인은 copy 체인의 `inverted_cells`를 옮겨 와 뗀 뒤의 반전을 센다.

---

## 착수 전에 확정한 것

1. `pointer/check.sh`의 `copy_lines <동사>`가 `copy> extend` · `copy> deselect`도 센다 — 동사가 인자다. 새 헬퍼는 `inverted_cells`
   하나(copy 체인의 것과 같은 식: `last_frame`의 `style> ROW,COL fg=102030 bg=…` 줄 수).
2. `style>`은 포커스 패널의 기본색 아닌 셀을 96개(`STYLE_DUMP_LIMIT`)까지 찍는다. MC의 줄은 왼쪽 패널(포커스)이고 선택은 6~19칸이라
   상한에 안 닿는다 — 닿으면 검사 38의 하한(6 이상)이 먼저 빨개진다.
3. HMP `sendkey shift 3000`은 3초 뒤 저절로 떨어진다(검사 29). Shift 클릭은 `sendkey` 뒤 0.3초에 `hmp` 둘로 보낸다. Shift 없는 클릭이
   뒤따르는 검사 41은 그 3초가 지난 뒤에 누른다(`sleep 3.2`) — 안 기다리면 보통 클릭이 늘리기가 된다.
4. 검사 38의 끌기 뒤 검사 39의 Shift 클릭은 반복이 아니다 — 앞 누름이 끌렸다(MC 결정 3의 4). 늘리기 뒤의 누름은 연속을 안
   기억하므로(M0) 검사 40 · 41의 누름도 반복이 아니다. 그래도 검사 사이에 `sleep 0.7`을 둔다 — 조건 하나에 기대지 않는다.
5. 검사 15 · 29 · 33~37의 뗌 뒤에도 이제 선택이 남는다. 그 다음 검사의 첫 누름이 `deselect`로 지우고, 판정 줄(`clip>` · `repeat` ·
   `COPY` 꺼짐 · `copy> enter|exit` 수)은 그대로다. 검사 17의 `Cmd+Shift+C`는 `copyEnter`가 남은 선택을 조용히 지운다.

## Task 1: `main.zig`

- `Clips.release(pane)` — `dumpClip(try pane.screen.copyRelease(self.of(pane)))`. `yank`는 키보드의 것으로 남는다.
- `run`의 `.copy` → `self.clips.release(p)`. 주석에 "선택은 남는다(SE design 결정 1)".
- `press`: `hit`의 패널에서 `self.ws.panes[h.leaf].?.screen.hasLinger()`를 읽어 `.extend = self.mods.shift and linger`. M0의 "SE-M1이
  잇는다" 주석을 지운다.

## Task 2: `pointer/check.sh` — 검사 38~41

자리는 검사 37 뒤, `move_to 679 0` 앞. 같은 줄 `mc-one mc-two:three`(ROW · PY)다 — `mc-two`는 7~12열, `three`는 14~18열.

```bash
inverted_cells() {
  last_frame | grep -acE "terminal: style> $1,[0-9]+ fg=102030 bg=[0-9A-F]{6}" || true
}
```

1. 검사 38 — 뗀 뒤 반전이 남는다. `move_to (cell_x 7) PY` · `button_down` · `move_to (cell_x 12) PY` · `button_up`. `clip> len=6
   text=mc-two`, `COPY` 꺼짐, 그리고 `inverted_cells ROW`가 6 이상(지금은 0 — mutation 1).
2. 검사 39 — Shift 클릭이 오른쪽 끝을 옮긴다. `move_to (cell_x 18) PY` · `sendkey shift 3000` · `sleep 0.3` · `hmp 1; hmp 0`.
   `copy> extend row=ROW col=18` 한 줄, `clip> len=12 text=mc-two:three`, `repeat` 수 그대로, `COPY` 꺼짐.
3. 검사 40 — 선택 앞을 Shift 클릭하면 가까운 끝(왼쫽)이 움직인다. `move_to (cell_x 0) PY` · 다시 `sendkey shift 3000` · `hmp 1; hmp 0`.
   `clip> len=19 text=mc-one mc-two:three`. 앵커 고정이면 `mc-one m`(8)이다 — mutation 2.
4. 검사 41 — Shift 없는 클릭이 지운다. `sleep 3.2` · `move_to (cell_x 3) PY` · `button_down` · `button_up`. `copy> deselect` 한 줄,
   `inverted_cells ROW`가 0, `clip>` 수 그대로. 이어 `sendkey shift 3000` · `move_to (cell_x 10) PY` · `hmp 1; hmp 0` · `sleep 0.5` →
   `copy> extend` 수 그대로, `clip>` 수 그대로(남은 선택이 없으니 보통 클릭). 끝에 `sleep 3`(Shift가 떨어진 뒤 다음 검사로).

모든 검사는 실패 문구에 마지막 `clip>` · `copy>` 줄을 붙인다.

## Task 3: 판정

1. `make quick`.
2. `pointer` 체인 단독(`make check CHAIN=pointer`, 약 3분 30초).
3. mutation 넷(되돌린다, 각각 `pointer` 체인 단독): (1) `.copy`를 `clips.yank`로 → 검사 38 빨강(반전 0). (2) `copyExtendAt`의 앵커를
   언제나 `topLeft`로 → 검사 40의 글자가 `mc-one m`. (3) `.deselect` 갈래를 비움 → 검사 41 빨강(반전이 남고 둘째 클릭이 늘린다).
   (4) `.extend`에서 `mods.shift`를 뺌 → 검사 41의 Shift 없는 클릭이 늘린다.
4. 루트 게이트 1회(`make gate`, 약 11분). `verify` 줄 전부 `ok` — 남은 선택의 프레임을 증분 렌더가 놓치면 `mismatch cells`.

## Task 4: 닫기

design `Status` · `docs/guides/completed.md` 한 행 · 소개 페이지(`gh-pages` `data.js`) "마우스 · 터치패드"에 한 줄 ·
`docs/decisions/project_shift_extend.md` + `MEMORY.md` 한 줄 · `HANDOFF.md` · PD design 비목표 5와 MC design 비목표 1에 "SE가 열었다"
한 줄 · `docs/decisions/project_pointer_devices.md` · `project_multi_click.md`에 한 줄.
