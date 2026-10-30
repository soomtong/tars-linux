# SB-M0 — 상태 줄 띠를 바뀐 프레임에만 그린다

Date: 2026-10-30
Design: `docs/specs/2026-10-30-tars-status-band-design.md`(결정 1~7)
Status: 착수 전

## 이 milestone이 끝나면

- 키 하나의 프레임에서 격자 아래 띠(1280 × 28)를 지우지도 쓰지도 않고 clip에도 안 넣는다. 띠를 그리는 프레임은 통째 프레임
  (`full`)과 상태 줄의 내용(`text` · `caps` · `battery`)이 지난 프레임과 다른 프레임뿐이다(design 결정 1 · 4).
- `dumpStatus`의 메모 넷이 `render`의 메모 하나가 되고, `status>` 다섯 줄은 지금과 같은 프레임에 같은 내용으로 찍힌다(결정 2 · 7).
- 그림자(`verifyFrame`)는 `renderOverlay`를 그대로 불러 매 프레임 띠를 통째로 그린다 — 실제 경로가 띠를 잘못 건너뛰면
  `mismatch rows=1 first=47`, clip을 빼먹으면 `mismatch clip`이다(결정 3 · 5). mutation 둘로 그것을 본다.
- 같은 프로브로 (a) frame을 다시 재서 M3의 0.92ms · overlay 0.22ms · present 0.36ms와 비교한다(결정 6).
- 여섯 체인의 `status>` 기준값과 `status_test`는 0줄 바뀐다.

## 착수 전에 확정한 것

HEAD `25e34ef`에서 코드로 확인했다. 줄 번호는 그 HEAD의 `terminal/src/main.zig`다.

1. 메모 타입 `StatusMemo`를 `main.zig`에 둔다 — `text: [status.MAX_LEN]u8` · `len: ?usize` · `caps: bool` · `battery: ?BatteryCell`.
   메서드 둘: `changed(self, st: Status) bool`(len이 null이면 참, 아니면 `text` 바이트 · `caps` · `battery`(`std.meta.eql`) 가운데
   하나라도 다르면 참)과 `remember(self, st)`. `App`의 네 필드(`last_status` · `last_status_len` · `last_status_caps` ·
   `last_status_battery`, `:3118-3128`)가 `status_memo: StatusMemo = .{}` 하나가 된다. `len`이 `?usize`인 뜻(0과 "아직 없음"을
   가른다)은 그대로 옮긴다.
2. `Frame`에 `status_changed: bool = false`를 더한다(`:4181`). `render`가 `frame.status_line`을 지은 바로 뒤(`:4284` 앞)에
   `frame.status_changed = self.status_memo.changed(frame.status_line); if (frame.status_changed) self.status_memo.remember(frame.status_line);`.
   `full`과 무관하게 바뀌었으면 기억한다 — 메모는 "마지막으로 본 내용"이지 "마지막으로 그린 때"가 아니다.
3. 실제 경로(`render`, `:4290-4295`). 지금의 세 줄
   ```zig
   frame.prompt_ink = try renderOverlay(self.fb, &self.cache, frame.prompt, frame.status_line);
   const grid_bottom = GRID_Y + @as(u32, self.rows) * ROW_HEIGHT;
   if (grid_bottom < self.fb.height) clips.push(0, grid_bottom, self.fb.width, self.fb.height - grid_bottom);
   ```
   이 둘이 된다.
   ```zig
   frame.prompt_ink = if (frame.prompt) |p| try drawPrompt(self.fb, &self.cache, p) else null;
   paintBand(self.fb, &self.cache, frame.status_line, full or frame.status_changed, &clips);
   ```
   `paintBand`는 자유 함수다 — `want`가 거짓이면 아무것도 안 한다. 참이면 `renderStatusBand`를 부르고 띠의 사각형을 `clips`에
   넣는다(`full`이면 `clips.whole`이라 무시된다 — 지금과 같다). `paintPane`과 짝이 되는 이름이다.
4. 자유 함수 둘을 가른다. `renderStatusBand(fb, cache, st)`는 지금 `renderOverlay`의 뒤 절반(띠 지우기 `fillRect` + `drawStatus`)이다.
   `renderOverlay`는 `drawPrompt`(있으면) → `renderStatusBand`를 차례로 부르는 함수로 남고 `verifyFrame`(`:4457`)만 부른다 —
   머리 주석에 "통째 경로의 정의, 그림자가 쓴다. 실제 경로는 둘을 따로 부른다(SB-M0)"를 적는다. `drawStatus`는 0줄.
5. `dumpStatus`(`:1245`)의 인자 넷(`last` · `last_len` · `last_caps` · `last_battery`)이 `changed: bool` 하나가 되고, 거짓이면 곧바로
   돌아온다. `dumpFrame`(`:4499`)의 호출이 `dumpStatus(self.fb, frame.status_line, frame.status_changed)`. 머리 주석의 메모 문단
   둘("메모가 `text`만 보면 안 된다" · "메모가 칸의 글자와 갈래도 기억하는 이유는 `sameBatteryCell`에 있다")은 `StatusMemo`를
   가리키게 고친다. `sameBatteryCell`(`:2240-2249`)은 지운다 — 주석의 "mutation이 메모만 건드리게"는 design 결정 2대로 verify가
   대신한다.
6. `render`의 머리 주석(`:4190`, "프롬프트 · 상태 줄(`renderOverlay`)")과 `:4291`의 "상태 줄의 띠는 `renderOverlay`가 매 프레임
   다시 칠한다" 문장을 고친다. `verifyFrame` 주석은 그대로다(그림자는 여전히 `renderOverlay`).
7. `probe/split.pl`의 `overlay` anchor(`:91`)가 새 `paintBand` 줄이 된다 —
   `paintBand(self.fb, &self.cache, frame.status_line, full or frame.status_changed, &clips);` 뒤에 `lap("overlay")`. 그러면 `overlay`
   구간이 프롬프트 + 띠 판정 + 띠 그리기(그린 프레임만)다. `patch.pl`의 anchor 넷과 다른 anchor는 그대로 붙는다.
8. mutation 둘, 둘 다 hangul 체인(`make check CHAIN=hangul`, 검사 2의 Shift+Space가 `한` → `EN`으로 띠를 바꾼다).
   (a) `full or frame.status_changed` → `full`. 첫 프레임은 그려지고 전환 뒤 띠가 낡는다 — `mismatch rows=1 first=47`. 검사 2의
   `text=`는 메모가 찍으므로 그대로 초록일 것이고, 그것이 verify가 있어야 하는 이유다. (b) `paintBand`의 `clips.push`를 뺀 판 —
   전환 프레임에 띠를 그렸는데 clip 밖이라 `mismatch clip`. 체인 자체는 PASS일 수 있다(verify 줄은 루트 게이트의
   `check_verify_lines`가 판정한다) — 그래서 그 회차 로그에서 `verify>` 줄을 직접 센다.
9. 프로브. 비교 판 `sb-m0`(`patch.pl`) · 진단 판 `sb-m0-split`(`patch.pl` + `split.pl`) 각 부팅 3회, 열두 프레임의 중앙값(DR-M3
   결과 절). 기준은 M3의 frame 0.92 · overlay 0.22 · present 0.36. 판단 규칙은 없다 — 이 milestone 뒤에 같은 축의 다음 단계가 없다.
   `overlay`가 0.05를 넘으면 왜인지 읽는다(프롬프트가 없는 (a)에서 남을 것은 띠 판정의 `eql` 셋뿐이다).

## Task 1: 코드와 mutation

- `terminal/src/main.zig`: 확정 1~6. `probe/split.pl`: 확정 7.
- 호스트 0.17로 `fmt --check` · `ast-check`(lessons "범용 명령"). 컨테이너에서 `zig build`(terminal) — 호스트 테스트는 0줄 변경.
- mutation (a) · (b)(확정 8), 되돌린 뒤 `hangul` · `battery`(배터리 칸이 60초 주기로 바뀐다) 체인.
- commit 하나.

## Task 2: 측정 · 루트 게이트 · 닫기

- 비교 판 + 진단 판 각 3회(확정 9). 결과 절에 M3과 나란히.
- 루트 게이트(`RUNS` 기본, 약 10분). `verify lines`가 전부 `ok`.
- 닫기: design 표 · Status, `completed.md`에 SB 행, `measurements.md` 98, `docs/decisions/project_status_band.md` + `MEMORY.md` 한 줄,
  `HANDOFF.md`("사용자가 확인할 것"의 RS · DR 항목에 띠 한 줄). 소개 페이지에는 안 넣는다(내부 작업 — ZU · SA · LE · CR과 같다).
  이 plan Status.
- commit 하나.

## 결과
