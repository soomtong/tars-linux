# CO-M1 — 커서 모양 기본값: tars.conf의 cursor_shape

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-cursor-options-design.md`(결정 5~7)
Status: 초안(2026-11-10). CO-M0 게이트가 끝나면 그 결과로 바뀌는 자리가 있는지 대조한 뒤 구현에 넘긴다(CLAUDE.md의 milestone 절).

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `ae3dca6`).

1. lib-vt: `Terminal.Options.default_cursor_style`(`ghostty-src/src/terminal/Terminal.zig:301`, 기본 `.block`), 그 값으로 돌아가는
   `setCursorStyle(.default)`(`:440` — DECSCUSR `0` · RIS · DECSTR), 실행 중에 바꾸는 `setDefaultCursorStyle`(`:466` — 프로그램이 모양을
   정해 둔 동안에는 덮지 않는다). `Terminal.init`은 옵션 값을 `cursor.default_style`에 넣고 곧바로 `setCursorStyle(.default)`를 부른다
   (`:366` 근처).
2. 우리 `vt.Screen.init`(`terminal/src/vt.zig:539`의 `.term = try .init(…)`)은 `default_cursor_style`을 안 준다. `vt.Screen.init`을 부르는
   자리는 terminal에서 `spawnPane`(`main.zig:1696`) 하나이고 vt_test · dirty_test 등 호스트 검사에서 여럿이다.
   그래서 `init`의 인자를 늘리지 않고 setter 하나를 둔다(Task 2) — 막 만든 화면은 `is_default`가 참이라 setter가 곧바로 모양을 바꾸고,
   결과는 옵션으로 준 것과 같다(확정 1). 호스트 검사의 호출 자리는 안 바뀐다.
3. 화면 키의 길은 FU-M0의 `fullscreen=`과 같다(design 확인 9):
   - `shared/screen_args.zig`: enum(`Fullscreen` `:162` 모양) · `Slot.fullscreen = 14`(`:346`) · `ARGC = 15`(`:358`) ·
     `default_fullscreen`(`:407`) · `Args` 필드(`:453`) · `encode`(`:477`) · decode(`:509`, `enumAt`).
   - `init/src/config.zig`: `pub const Fullscreen = screen_args.Fullscreen`(`:807`), 필드(`:885`), 파싱 갈래(`:1146`, 모르는 값은 로그 뒤
     지금 값 유지), 기본 파일의 주석 · 값 줄(`:1264`), 그 형식 인자(`:1287`).
   - `init/src/reload.zig`의 `term` 배열(`:41`, 머리 주석 "스무 키"). 빠뜨리면 `groupOf`가 컴파일 에러를 낸다.
   - `init/src/main.zig`: `reload terminal` 줄(`:720` · `:735`), `config` 줄(`:1323` · `:1342`), argv 짓기(`:1552`).
   - `init/src/config_edit_test.zig`: 키 표(`:47`), hint · 거절 검사(`:178`).
   - terminal: `App` 초기화가 argv를 받는 자리(`main.zig:3649` 근처)에서 값을 App 필드에 두고 `spawnPane`이 쓴다.
4. config 체인의 `TC_LIST_WANT`(`config/check.sh:136`)는 부분 집합 대조다(`:563`의 for — `fullscreen`도 없다). 더하지 않아도 안 깨지고,
   더하면 `tars-config list`가 새 키의 기본값을 찍는지를 본다. 더한다.
5. 게이트: render 체인은 설정 디스크 없는 부팅 하나로 짜였다(`render/check.sh:66` `LOG` 하나). 설정 디스크 부팅을 거기 끼우면 체인 전체의
   로그 구간 계산이 흔들린다. 그래서 fullscreen 체인(`fullscreen/check.sh`, 354줄, `settings_disk` `:156` · `boot`)을 본뜬 새 체인
   `cursor/check.sh` 하나를 둔다. 서른셋째 체인이다.
6. vim의 모양은 대체 화면 안에서만 바뀐다(design 확인 8, CU 실측 10, vt_test 검사 91). 그러니 사용자 모양이 bar일 때 vim을 나오면
   프롬프트는 bar여야 한다 — 소스로 읽은 사실이라 게스트 판정으로 다시 본다(Task 5의 판정 4).

## Task 1 — `shared/screen_args.zig`

- `pub const CursorShape = enum { block, bar, underline; pub fn arg(…) }` — 이름은 terminal의 `vt.CursorShape`와 같지만 공유 파일이 vt를
  import하지 않으므로 따로 둔다(`Fullscreen`이 그런 것처럼). 머리 주석에 CO design 결정 5.
- `Slot.cursor_shape = 15`, `ARGC = 16`, `default_cursor_shape: CursorShape = .block`, `Args.cursor_shape`, `encode` · decode 한 줄씩.
- `screen_args_test`가 있으면 왕복 한 줄(값 셋).

## Task 2 — terminal

- `vt.zig`: `pub fn setDefaultShape(self: *Screen, shape: CursorShape) void` — `self.term.setDefaultCursorStyle(...)`로 넘긴다(block →
  `.block`, bar → `.bar`, underline → `.underline`). `else`를 안 둔다.
- `main.zig`: App 필드 `cursor_shape: vt.CursorShape`(argv에서), `spawnPane`이 `vt.Screen.init` 직후 `screen.setDefaultShape(self.cursor_shape)`.
  terminal 시작 로그 줄(`terminal: keyboard=…` 꼴이 있으면 거기)에 `cursor_shape=` 한 칸 — 게이트가 argv가 닿았는지 본다.
  알맞은 줄이 없으면 FU의 `fullscreen>`처럼 따로 한 줄(`terminal: cursor_shape=bar`)을 시작 때 한 번 찍는다.
- 호스트 검사 `vt_test` 134~136:
  - 134. 새 화면에 `setDefaultShape(.bar)` → `cursorAsked()` bar, `cursorMark()` bar 띠, 반전 0.
  - 135. 그 화면에 `CSI 2 SP q` → block(프로그램이 이긴다), `CSI 0 SP q` → bar, 빈 인자 `CSI SP q` → bar.
  - 136. `CSI 4 SP q`로 정해 둔 화면에 `setDefaultShape(.block)` → 여전히 underline(정한 모양을 안 덮는다), `CSI 0 SP q` → block.
  - 빨강 하나: setter의 본문을 비우고 134가 실패하는지 본 뒤 되돌린다.

## Task 3 — init

- `config.zig`: 필드 `cursor_shape: CursorShape = .block`, 파싱 갈래(fullscreen과 같은 꼴, 로그 `unknown cursor_shape '…', falling back to …`),
  기본 파일에 두 줄:

  ```
  # cursor_shape: block | bar | underline
  #   the shape when a program has not asked for one; vim still switches it by mode
  cursor_shape={s}
  ```
- `reload.zig`: `term` 배열에 `"cursor_shape"`(주석 `CO-M1. 다시 뜬 terminal이 새 패널에 준다.`), 머리 주석의 키 수를 고친다.
- `main.zig`: argv 짓기, `config` 줄 · `reload terminal` 줄 끝에 `cursor_shape={s}`.
- `config_edit_test.zig`: 키 표에 `cursor_shape=bar`, hint `block | bar | underline`, 거절 `cursor_shape=beam`.
- `zig build test`(init) · `zig build test`(terminal) 둘.

## Task 4 — 안내 `docs/help/config.md`

"자주 쓰는 키" 표에 한 행: `cursor_shape` · `block` · 프로그램이 정하지 않았을 때의 커서 모양 — `block` · `bar` · `underline`. 바꾼 뒤
`sudo tars-config reload terminal`(열린 패널이 닫힌다)은 표 아래의 기존 문장이 이미 말하는지 보고, 없으면 desk.md의 fullscreen 줄과 같은
꼴로 한 줄. `make quick`은 하위 명령 이름만 대조하므로 키 이름은 사람이 본다(CLAUDE.md).

## Task 5 — 새 체인 `cursor/check.sh`(CO-M1)

fullscreen 체인을 본뜬다(빌드 넷 · `settings_disk` · `boot` · monitor). monitor 포트는 예약 범위(RP-M0)에서 다음 빈 자리 — 쓰기 전에 다른
체인의 포트를 `rg`로 모아 확인한다. 부팅 하나, 설정 디스크 `shell=fish` · `cursor_shape=bar`.

1. `tars-init: config … cursor_shape=bar`, terminal의 `cursor_shape=bar` 줄.
2. 첫 프롬프트의 `cursor>`가 `vt=bar drawn=bar … ink=32 box=2x16`, 반전 0.
3. `printf '\033[2 q'` → `vt=block drawn=block`, 반전 1. `printf '\033[0 q'` → 다시 bar(결정 6의 "돌아온다").
4. `vim /tmp/co.txt` → normal의 block(vimrc가 2를 보낸다) → `:q` → 프롬프트의 `cursor>`가 bar(확정 6).
5. `tars-config list`에 `cursor_shape=bar`가 보이고, `sudo tars-config set cursor_shape=underline` → `sudo tars-config reload terminal`
   → 새 terminal의 첫 프롬프트가 `vt=underline drawn=underline … ink=16 box=8x2`. `reload terminal` 로그 줄에 `cursor_shape=underline`.

- `check.sh`의 `CHAINS` 끝에 `"CO-M1:./cursor/check.sh"`, 루트 `Makefile`에 체인 목록이 따로 있으면 거기도.
- config 체인의 `TC_LIST_WANT`에 `cursor_shape=block`(확정 4).
- 판정: 체인 단독 2회. 입구 검사 정규식을 새 체인에 한 번 대 본다(FU-M1 결과 4).

## 끝내기

루트 게이트 한 판 — CO-M0 · CO-M1을 함께 판정한다(design 위험 1 · 4). 시간은 FU-M1 판(36분)에 새 체인 몫 1~2분을 더한 정도로 본다.
그 뒤 CLAUDE.md의 "서브프로젝트를 끝내면" 목록: design Status, CU design 비목표 1 · 4 · 9에 "CO가 정했다/닫았다" 한 마디, `completed.md` 한 행,
소개 페이지(`data.js` — 기능 목록에 커서 숨김 · 모양 키), 기억 한 파일 + `MEMORY.md`, `HANDOFF.md`. `docs/help/`는 Task 4에서 고쳤다.

## 비목표

design의 비목표. 특히 깜빡임(결정 7)과 두께 · 색.

## 결과

(작성 전)
