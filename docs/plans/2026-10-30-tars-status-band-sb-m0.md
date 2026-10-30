# SB-M0 — 상태 줄 띠를 바뀐 프레임에만 그린다

Date: 2026-10-30
Design: `docs/specs/2026-10-30-tars-status-band-design.md`(결정 1~7)
Status: 끝났다(2026-10-30). plan `9c004ab` · Task 1 `7ab50e0` · Task 2 닫기. (a) frame 0.92 → 0.42ms(−54%, DR-M0의 2.45에서 −83%),
overlay 0.22 → 0.001, present 0.36 → 0.27. 루트 게이트 22/22(11분 14초), verify 8109프레임 전부 `ok`.

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

### Task 1 — 코드와 mutation (2026-10-30)

`main.zig` +94/−67(`StatusMemo` · `renderStatusBand` · `paintBand` · `Frame.status_changed` · `dumpStatus`의 인자 셋 · `sameBatteryCell`
삭제 · 주석), `probe/split.pl` anchor 하나 + 주석. 호스트 0.17 `fmt --check` · `ast-check` 통과, 컨테이너 `zig build` · `zig build test`
통과(호스트 테스트 0줄 변경). `patch.pl` + `split.pl`이 새 HEAD에 붙고 `ast-check`를 지난다.

mutation 둘, 둘 다 hangul 체인(마운트, `TARS_RENDER_VERIFY=1`):

| 판 | 체인 | verify 줄 |
|---|---|---|
| (a) `full or frame.status_changed` → `full` | FAIL — CapsLock 홀드 검사 `on=0`("Action.redraw is missing") | `ok` 22 · `mismatch rows=1 first=47` 25. 첫 mismatch가 Shift+Space 프레임(`status> text=한 …` 바로 앞 줄) |
| (b) 띠 clip을 1 × 1로 | PASS(rc=0) | `ok` 110 · `mismatch clip rows=1 first=47` 67. 첫 mismatch가 같은 프레임 |

(a)에서 체인이 빨개진 자리는 확정 8의 예상("`text=`는 초록")대로 검사 2가 아니다 — `text=`는 메모가 찍으므로 `한`으로 바뀌어 지나갔고,
`ink fg=`도 `한`(2칸)과 `EN`(2칸)의 픽셀 수가 우연히 비슷해 지나갔으며, 띠의 앰버 픽셀을 세는 CapsLock 검사에서야 멈췄다. 띠가
낡은 것을 그 프레임에 바로 말한 것은 verify뿐이다(design 결정 5). (b)는 체인이 PASS다 — 그린 픽셀은 맞고 clip만 빠졌으므로 덤프는
전부 정상이고, 화면 흉내가 띠를 영영 못 받아 그 뒤 모든 프레임이 `mismatch clip`이다. 루트 게이트의 `check_verify_lines`가
빨갛게 만드는 자리다(확정 8의 둘째 문장 그대로).

되돌린 판(`make check`): hangul PASS, 178프레임 `ok` · `mismatch` 0 · `status> text=` 19줄. battery PASS, 부팅 A 221프레임 `ok` ·
`status>` 5줄(배터리 칸이 바뀌는 프레임마다 띠를 다시 그렸다), 부팅 B 3프레임 `ok`.

### Task 2 — 측정 (2026-10-30, HEAD `7ab50e0`)

같은 프로브, 부팅 3회씩. 비교 판(`sb-m0`, `patch.pl` 그대로):

```
sb-m0-run1  (b) span=1245ms frames=75 frame_sum=184ms dump_sum=104ms other=957ms reads=372   (a) frame=0.393 dump=2.584
sb-m0-run2  (b) span=1216ms frames=73 frame_sum=177ms dump_sum=117ms other=922ms reads=370   (a) frame=0.368 dump=2.783
sb-m0-run3  (b) span=1121ms frames=68 frame_sum=160ms dump_sum=96ms  other=864ms reads=368   (a) frame=0.495 dump=3.862
median      (b) span=1216ms frames=73 frame_sum=177ms dump_sum=104ms                          (a) frame=0.42 ms (n=12)
```

진단 판(`sb-m0-split`, `split.pl`의 anchor를 `paintBand` 줄로):

```
median      (a) frame=0.528 ms (n=12)
  split: others=0.01 cells=0.074 pane=0.164 rows=0.135 overlay=0.001 finish=0.275 present=0.272
```

| (a) 키 하나 | M0 `67596a0` | DR-M2 | DR-M3 `a2f5aef` | SB-M0 `7ab50e0` |
|---|---|---|---|---|
| frame | 2.45 | 1.36 | 0.92 | 0.42 (M3에서 −54%, M0에서 −83%) |
| cells | 0.63 | 0.63 | 0.12 | 0.07 |
| pane(비교 + 행 칠하기) | 0.81 | 0.165 | 0.18 | 0.16 |
| overlay | — | 0.20 | 0.22 | 0.001 |
| finish(present) | 0.29 (0.21) | 0.32 (0.32) | 0.37 (0.36) | 0.28 (0.27) |
| (b) `seq 1 200000` | 1,135ms | 1,105ms | 1,139ms | 1,216ms(잡음 안 — 회차 1,121 · 1,216 · 1,245) |

`overlay`가 0.22 → 0.001ms다 — (a)의 프레임에서 띠 판정은 `eql` 셋뿐이고 띠를 안 그린다(확정 9의 "0.05를 넘으면"은 안 넘었다).
`present`도 0.36 → 0.27로 줄었다 — 띠 clip(1280 × 28)이 빠져 virtio-gpu가 받는 경계 상자가 작아진 것이고, 확정 9가 "줄 수
있다"고만 한 자리다. 비교 판의 frame 0.42와 진단 판의 0.53의 차는 `lap` 다섯과 `split>` 줄의 비용이다(M3에서는 0.92 · 0.96).
세 회차가 0.37 · 0.39 · 0.50으로 M3(0.58 · 0.92 · 1.84)보다 고르다. (b)는 잡음 안 — 스크롤 프레임은 띠와 무관하다(design "안 하는 것").

### Task 2 — 루트 게이트 · 닫기 (2026-10-30)

루트 게이트(`bash check.sh`, 21:17:59 → 21:29:13): 22/22, 11분 14초(prebuild 364 + lanes 308초 — prebuild는 cold build라 흔들린다,
DR-M3 닫기는 279초였다). `verify lines` 합 8109(DR-M3 닫기 8119과 같은 자리 — CP 1980 · TD 1381 · UT 911 · TR 798 · PD 668 · CM 545 ·
FW 510 · CB 380 …), 회차 로그 스물둘에 `mismatch` 0. `cut log lines` 전부 0.

닫기: design 표 · Status, `completed.md`의 SB 행, `measurements.md` 98, `docs/decisions/project_status_band.md` + `MEMORY.md` 한 줄,
`HANDOFF.md`(지금 상태 · 사용자가 확인할 것의 RS · DR 항목 · 다음 후보 · 게이트 줄). 소개 페이지에는 안 넣었다(내부 작업).
