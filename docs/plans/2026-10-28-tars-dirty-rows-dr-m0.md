# DR-M0 — 키 하나의 그리기를 구간으로 쪼갠다

Date: 2026-10-28
Design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`
Status: 착수 전.

## 이 milestone이 끝나면

- 지금 HEAD의 기준선이 있다 — RS의 프로브(`probe/patch.pl`) 그대로, 부팅 3회. RS-M3(2026-10-11) 뒤로 WP · CU · PD · BS · MS …가
  들어왔으므로 RS-M3의 4.3ms를 기준으로 쓰지 않고 다시 잰다. DR-M2가 같은 판으로 다시 재서 이것과 비교한다.
- 시나리오 (a)(화면이 찬 상태에서 키 하나)의 그리기가 구간 여섯으로 나뉜 표가 있다. 이것이 부분 갱신이 줄일 수 있는 몫의
  상한이다(design 결정 1).
- `cells()`의 몫으로 M3(행 dirty 비트)을 제안할지가 정해진다(아래 확정 6).
- `terminal/src/`는 0줄 바뀐다.

## 착수 전에 확정한 것

HEAD `8483f59`에서 코드로 확인했다.

1. 프로브가 둘이다. 비교 판은 `probe/patch.pl` 그대로다 — anchor가 그리기 함수 밖(`App`의 필드 · `feed` · `dumpFrame`)이라
   M2 뒤에도 붙는다. 진단 판은 새 `probe/split.pl`이고 `patch.pl`의 결과 위에 얹는다. 진단 판의 anchor는 M2가 고칠 자리 안에
   있으므로 M0의 HEAD에만 붙으면 된다 — M2 뒤에 다시 쪼개 볼 일이 생기면 그때 anchor를 고친다. design 결정 1의 "M2가 고칠 자리를
   피한다"는 비교 판에 대한 말로 읽는다.
2. 구간 여섯과 anchor(`App.render`, 전부 `main.zig`에 정확히 한 번 나오는 것을 셌다).
   - `backdrop` — `renderBackdrop(self.fb, &ws.tree, self.whole);`(fb 전체 `fill` + 구분선)
   - `others` — 그 뒤부터 `focus.screen.focused = true;`까지(포커스 아닌 패널들. 시나리오는 패널 하나라 0에 가깝다)
   - `cells` — `frame.cells = try focus.screen.cells(self.cell_buf);`
   - `pane` — 포커스 패널의 `try renderPane(self.fb, &self.cache, frame.cells, …);`
   - `finish` — `frame.prompt_ink = try renderFinish(…);`(프롬프트 · 상태 줄 · 화살표 · `present`)
   - `present` — `renderFinish` 안의 `    try fb.present();`. 이 자리는 자유 함수라 `self.io`가 없다. 파일 스코프
     `var probe_io: std.Io = undefined;`를 두고 `const frame_start = …` 줄 뒤에서 `probe_io = self.io;`로 채운다.
   - 나머지(`frame` − 여섯의 합)는 프롬프트 · 상태 줄 문자열 짓기와 `images()`다. 표에 `rest`로 적는다.
3. 진단 줄은 `terminal: split> backdrop=<us> others=<us> cells=<us> pane=<us> finish=<us> present=<us>`이고, `render`가
   `frame.frame_us`를 셈한 줄 바로 뒤에서 찍는다. 그래서 `frame`에는 안 들어가고, 같은 프레임의 `probe>` 줄보다 앞에 온다.
   `dump`에도 안 들어간다(`probe_dump_start`는 `dumpFrame`에서 잡는다). (b)의 `other`에는 들어가므로 진단 판의 (b)는 읽지 않는다.
4. `report.pl`은 `split>` 줄이 있는 로그면 마지막으로 본 `split>` 값을 다음 `probe>` 프레임에 붙이고, (a)의 구간별 중앙값을 한
   줄 더 찍는다. `split>`이 없는 로그(비교 판)의 출력은 지금과 바이트까지 같다.
5. 회차는 비교 판 3회(label `dr-m0`)와 진단 판 3회(label `dr-m0-split`)다. 부팅 한 번이 1분 10초 남짓이라 여섯 번에 8분쯤이다.
   `out/probe-rs/`는 루트 게이트의 `clean()`이 지우므로 결과는 이 plan에 옮겨 적는다.
6. 판단 규칙 — 숫자를 보기 전에 정한다. (a)의 `cells` 중앙값이 (a) `frame` 중앙값의 30% 이상이면, M2가 칠하기를 줄여도
   `cells()`가 남는 몫이 크다는 뜻이므로 design에 M3(행 dirty 비트, 결정 2)을 더하자고 사용자에게 제안한다. 30% 미만이면
   M3 없이 M2로 닫는 것이 기본이다. `present`의 몫은 M2의 clip이 QEMU에서도 보이는지를 미리 말해 준다 — virtio-gpu는 손상
   영역만 host로 옮긴다(RS 배경 6).

## Task 1: 진단 판과 집계

- `probe/split.pl`: `patch.pl`과 같은 모양(anchor가 정확히 한 번이 아니면 멈춘다). 머리 주석에 확정 1 · 3을 적는다.
- `probe/report.pl`: 확정 4.
- 호스트에서 두 패치를 차례로 붙이고 diff로 더한 줄만 있는 것을 본다. 0.17 `zig ast-check`로 패치된 사본이 구문상 맞는지 본다
  (lessons "범용 명령"). `split>` 없는 RS-M3 형식의 가짜 로그 한 개로 `report.pl` 출력이 바뀌지 않는 것을 본다.
- commit 하나.

## Task 2: 측정과 기록

- 비교 판 3회, 진단 판 3회(확정 5). 컨테이너에서 빌드가 통과하는 것이 진단 판의 컴파일 검사다.
- 결과 절에 회차별 줄과 중앙값, 구간 표, 확정 6의 판단을 적는다.
- design의 milestone 표 DR-M0 행 상태, 이 plan Status, `HANDOFF.md`.
- 코드 0줄이라 루트 게이트는 안 돈다(LS-M0과 같다). commit 하나.
