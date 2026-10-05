# PD-M2 — 누르면 포커스가 옮겨 가고, 끌어 고른 글자가 뗄 때 클립보드에 들어간다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-pointer-devices-design.md`
Status: 끝났다(2026-10-05). 실측은 맨 아래 "PD-M2가 실측한 것" 절에 있다. 기준은 `6f4dfb2`. 이것으로 사용자의 요청 1(마우스 포인터 · 드래그 선택)이 끝났다.
commit)이고, 그 위에서 사본 컴파일 · 호스트 검사 넷 · 체인 · regression 셋 · mutation 넷을 돌려 봤다(확정 12).

## 누가 무엇을 하나

design 결정 11. Task 0~7은 구현 서브에이전트(Opus)가 main 작업 트리에서 직접 편집한다. Task 8(루트 게이트 2회 ·
실측 절 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각
Task의 명령 출력을 그대로 보고한다. mutation(Task 7)도 구현자가 돌린다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은
구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/pdm2/term/src/` · `/tmp/run/pdm2/pointer/check.sh` ·
`/tmp/run/pdm2/root_check.sh`)에 먼저 넣었고, 아래의 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다
(`/tmp/run/pdm2/hunks.py`). 구현자는 코드를 새로 짓지 않는다. Edit 도구에 글자 그대로 넣고, 각 Task 끝에서 사본과
`diff`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 사본이 서로 다르다고
보이면 고치지 말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/pointer.zig` | 머리 주석 셋 줄과, 끝에 제스처 절 — `Cell` · `Target` · `Scroll` · `Intent` · `Intents` · `Gesture` · `sameCell` | +204 −3 |
| `terminal/src/pointer_test.zig` | `expectIntents`와 검사 16~22 | +149 |
| `terminal/src/layout.zig` | `clampInto`(모듈 수준 함수) | +15 |
| `terminal/src/layout_test.zig` | 검사 13(`clampInto`) | +21 |
| `terminal/src/vt.zig` | `copyEnterAt` · `copyPointTo` · `copyClamp` | +46 |
| `terminal/src/vt_test.zig` | 검사 97~101 | +114 |
| `terminal/src/input.zig` | `State.pointerMode` | +25 |
| `terminal/src/input_test.zig` | 검사 64~67 | +80 |
| `terminal/src/main.zig` | 편집 여섯 — 전이 기록 · `gridCellClamped` · `PointerWire` · 변수 둘 · 포인터 분기 | +234 −13 |
| `pointer/check.sh` | 편집 일곱 — 머리 주석 · 표식 · 도구 · 검사 13~18과 16의 둘째 · PASS 줄 | +427 −3 |
| `check.sh` | 체인 설명 문단과 `CHAINS`의 `"PD-M1:…"` → `"PD-M2:…"` | +5 −3 |

`terminal/build.zig`는 안 고친다 — 검사 넷이 이미 등록돼 있다. 커널도 안 고친다.

`docs/guides/lessons.md` · design `Status:` · `HANDOFF.md`는 이 milestone에서 안 고친다(design "닫을 때").

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/pdm2/impl/` 아래에 둔다.
`/tmp/run/pdm2/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(PD-M1 plan
확정 11 · 2026-10-05 lead 실측). 컨테이너는 언제나 하나씩 돌린다.

## 이 milestone이 끝나면

- 포커스가 아닌 패널을 누르면 포커스가 그리로 간다. 여백 · 구분선 · 상태 줄을 누르면 아무 일도 없다.
- 글자 위를 누르고 다른 칸까지 끌면 copy mode에 들어가 문자 단위 선택이 늘어난다(반전, 상태 줄 꼬리의 `COPY`).
  copy mode에는 누름이 아니라 첫 칸 이동에 들어간다.
- 끌다가 떼면 선택이 클립보드에 들어가고 copy mode를 나간다. 키보드의 `y` · `Cmd+C`와 같은 `clip>` · `copy> yank`
  줄이 찍히고, `Cmd+V`로 붙는다. 끌지 않고 떼면(클릭) 아무 일도 없다.
- 이웃 패널 위까지 끌어도 선택 끝은 누른 패널의 가장자리 칸에서 멈춘다.
- 누른 채 휠을 굴리면 누른 패널이 세 줄씩 움직이고 선택 끝이 지금 포인터 칸으로 다시 맞춰진다.
- 입력 모드의 두 사본(`input.State.mode`와 `vt.Screen.copy_cursor`)이 함께 움직인다. 끌어서 들어간 뒤 친 `j`는 copy
  표로 가고, 복사한 뒤 친 글자는 셸로 간다. 조합 중인 한글은 누름에서 확정돼 옛 포커스의 셸로 간다(검색 프롬프트였으면
  버린다).
- 키보드 copy mode인 패널을 누르면 복사 없이 그 모드가 닫힌다. 검색 프롬프트가 열려 있었으면 프롬프트도 닫힌다.
- 호스트 검사가 는다 — `pointer_test` 검사 16~22, `layout_test` 검사 13, `vt_test` 검사 97~101, `input_test` 검사
  64~67. 체인 수는 그대로 열아홉이고 `pointer/check.sh`의 부팅은 여전히 하나다. 이 milestone이 끝나면 사용자의
  요청 1(마우스 포인터와 드래그 선택)이 끝난다.

로그 줄(정본 — `main.zig`와 `pointer/check.sh`가 이 글자를 쓴다). 새 줄은 `press` · `release` 둘이고, 나머지는 키보드의
copy mode가 이미 찍는 줄과 같은 모양이다.

```
terminal: pointer> press leaf=1 row=4 col=0
terminal: pointer> press none
terminal: copy> enter row=4 col=0
terminal: copy> point row=4 col=11
terminal: pointer> release drag=1
terminal: clip> len=12 text=pd-drag-word
terminal: copy> yank
terminal: pointer> release drag=0
terminal: copy> exit
```

`press none`은 누른 자리가 여백 · 구분선 · 상태 줄이라는 뜻이다. `release drag=1`은 끈 뒤의 뗌이고, 복사했는지는
뒤따르는 `clip>` 줄이 말한다. `copy> point`는 끄는 동안 선택 끝이 옮겨 간 칸이다(키보드의 `copy> down` 등과 같은
자리). `at` · `open` · `skip` · `close` 줄은 PD-M1 그대로다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 코드를 읽어 정한 것이다. QEMU · zig를 쓰는 측정은 루트 게이트 뒤로 미뤘다(확정 12).

1. `Gesture`의 상태 기계. `pointer.zig`에 둔다. 순수하다 — 패널도 화면도 모르고, 시스템 콜도 import도 새로 없다.
   입력은 넷(누름 · 움직임 · 뗌 · 휠)이고 출력은 의도 목록(`Intents`, 셋 이하)이다.

   | phase | `press(hit, focus)` | `motion(cell, target)` | `release(target)` | `wheel(n, target)` |
   |---|---|---|---|---|
   | `idle` | 패널 칸이면 `pressed`, `[cancel, focus?]`. null이면 `ignored`, `[]` | `[]` | `[]` | null |
   | `pressed` | (안 온다) | `gone`이면 `ignored`. 같은 칸이면 `[]`. 다른 칸이면 `dragging`, `[select_start(누른 칸), select_to(지금 칸)]` | `[]` → `idle` | `gone`이면 `ignored`, null. 아니면 `dragging`, `[select_start, scroll, select_to(지금 칸)]` |
   | `dragging` | (안 온다) | `copy`가 아니면 `ignored`. 같은 칸이면 `[]`. 다른 칸이면 `[select_to]` | `copy`면 `[copy]`. 아니면 `[]`. → `idle` | `copy`가 아니면 `ignored`, null. 아니면 `[scroll, select_to(지금 칸)]` |
   | `ignored` | (안 온다) | `[]` | `[]` → `idle` | null |

   `focus?`는 누른 잎이 지금 포커스와 다를 때만이다. 휠의 null은 "이 휠은 제스처의 것이 아니다"이고, 그때
   `main.zig`가 PD-M1의 휠(포인터 아래 패널)로 다룬다. "안 온다"는 왼쪽 버튼의 눌림이 뗌 없이 두 번 오지 않기
   때문이다(`Pointer.apply`가 장치 전체의 합이 바뀔 때만 눌림을 낸다). 와도 `press`가 상태를 새로 잡는다.

2. `Target` — 누른 패널이 지금 어떤 상태인가. design은 "`Gesture`가 copy가 꺼진 것을 본다"고 적었다. `Gesture`는
   화면을 모르므로 `main.zig`가 단계마다 셋 중 하나로 알려 준다.

   | 값 | 뜻 |
   |---|---|
   | `gone` | 누른 패널이 더는 포커스가 아니다 — 누른 뒤 키보드가 포커스(`Cmd+]`)나 워크스페이스(`Cmd+2`)를 옮겼거나 그 패널이 닫혔다 |
   | `normal` | 포커스이고 copy mode가 아니다 |
   | `copy` | 포커스이고 copy mode다 |

   이 셋이면 design 결정 6의 "키보드 copy mode와 섞일 때" 표가 다 갈린다. 근거는 키보드 copy mode가 언제나 포커스
   패널에만 있다는 것이다. copy 표(`handleKey`의 1.5번 단계)가 `chord()`보다 앞이라 copy mode 안에서는 `Cmd+]` ·
   `Cmd+[` · `Cmd+1`~`9` · `Cmd+T`가 전부 삼켜진다(`input_test` 검사 61 · 63). 그래서 "누른 패널이 키보드 copy mode다"는
   "누른 패널이 포커스이고 copy mode다"와 같다.

   `main.zig`의 셈은 `PointerWire.target`이다 — 누른 워크스페이스 번호(`gesture_ws`)가 지금 번호와 같고, `ws.focus`가
   누른 잎이고, 그 패널이 있으면 `copyActive()`로 `copy`와 `normal`을 가른다.

3. 의도와 그 실행. `pointer.Intent`는 design의 여섯 그대로다(`cancel` · `focus` · `select_start` · `select_to` ·
   `scroll` · `copy`). 실행은 `main.zig`의 `PointerWire.run`이고 switch에 `else`가 없다.

   | 의도 | `main.zig`가 하는 일 | 로그 |
   |---|---|---|
   | `cancel` | `pointerMode(.normal)`의 확정분을 지금 포커스(옛 포커스)의 PTY에 쓰고, 그 패널이 copy mode면 `copyExit` | 조합이 있었으면 `hangul>`, copy mode였으면 `copy> exit` |
   | `focus` | `ws.focus = 잎` | 그 프레임의 `pane>` |
   | `select_start` | `pointerMode(.copy)`(확정분은 그 패널의 PTY로) 뒤 `copyEnterAt` | `copy> enter row= col=` |
   | `select_to` | `copyPointTo` | `copy> point row= col=` |
   | `scroll` | `scrollByRows(-WHEEL_ROWS × 눈금)` | 그 프레임의 `scroll>` |
   | `copy` | `copyYank` → `dumpClip`, `copy> yank`, `pointerMode(.normal)` | `clip> len= text=` · `copy> yank` |

   `cancel`이 페이로드가 없는 것은 확정 2 때문이다. 닫을 copy mode는 언제나 지금 포커스 패널의 것이다. 누른 패널이
   포커스면 그 패널을 닫고(design 표의 첫 줄), 다른 패널이면 옛 포커스 패널을 닫는다(design 동작 표의 "옛 패널의 copy
   mode는 닫힌다"). 그래서 누름은 패널 칸이면 언제나 `cancel`을 내고, 다른 패널이면 그 뒤에 `focus`를 낸다. 순서가
   design 결정 6의 "확정분 → 포커스 이동 → 선택"이다.

   화면이 바뀐 의도만 `redraw`를 켠다. `cancel`은 조합이 있었거나 copy mode를 닫았을 때만이다. 아무것도 안 바꾼 클릭이
   프레임을 그리면 PD-M1 체인의 "움직임만으로는 `screen>`이 안 는다"(검사 7의 둘째)가 그 앞의 버튼 검사(검사 3,
   패널 위 700, 455에서 누르고 뗀다)에서 깨진다.

4. 한 회차 안의 순서. `drainPointer`는 장치에서 읽은 `Frame`을 회차 단위로 합친다(`PointerRound`). 이동과 휠은 합쳐도
   되지만 누름 · 뗌은 순서와 그 순간의 자리가 뜻을 가진다 — "끌다가 뗐다"를 회차 끝의 자리 하나로는 되살릴 수 없다.
   그래서 `PointerRound`에 왼쪽 버튼 전이를 담는 칸 여덟(`edges`)을 더하고, 전이마다 그 순간의 포인터 자리를 함께
   담는다. 포인터 분기는 이렇게 돈다.

   1. 전이마다 그 자리로 `motion`을 먼저 주고, 그다음 `press`나 `release`를 준다. 끌다가 뗀 보고 하나는 마지막 칸까지
      선택을 늘린 뒤에 복사해야 한다.
   2. 회차에 움직임이나 누름이 있었으면(`round.woke`) 회차 끝의 자리로 `motion` 한 번.
   3. 회차의 휠(`round.wheel`)이 0이 아니면 `wheel`.

   휠이 맨 뒤라 한 회차 안의 누름 · 휠 · 뗌의 순서는 안 남는다. 사람의 손으로 한 회차(밀리초 단위)에 그 셋이 함께 오는
   일은 드물다. 게이트는 HMP 명령 하나마다 그 결과 줄을 기다리므로 명령 하나가 회차 하나다. 여덟을 넘는 전이는 버린다 —
   뗌을 잃어도 다음 누름이 제스처를 새로 잡는다.

5. 가장자리 처리(design 결정 5). 두 자리가 나눠 한다.
   - `main.zig`가 끄는 칸을 누른 패널의 사각형으로 자른다. 픽셀 → 격자 칸은 `gridCellClamped`(격자 밖이면 가장 가까운
     가장자리 칸, `gridCell`과 같은 상수 넷), 격자 칸 → 누른 잎의 상대 칸은 `layout.clampInto`(순수, `layout_test`
     검사 13).
   - `Gesture`는 받은 칸의 잎을 안 본다. 선택 끝의 잎은 언제나 누른 잎이다(`pointer_test` 검사 19).

   누름은 `gridCell`(격자 밖이면 null)과 `Tree.hit`(구분선이면 null)을 그대로 쓴다. PD-M1의 휠과 같은 길이다.

   `clampInto`를 `Tree`의 메서드로 두지 않은 이유. 트리가 필요 없다 — 사각형 하나와 칸 하나의 산수다. `main.zig`가
   `rects`로 얻은 누른 잎의 사각형을 넘긴다.

6. `copyEnterAt` · `copyPointTo`(`vt.zig`). design은 `copyEnterAt = copyEnter + copy_cursor = (x, y) + copySelect(.char)`,
   `copyPointTo`는 "칸이 같으면 아무것도 안 한다"였다. 둘 다 고쳤다.
   - `copyEnterAt`은 이미 copy mode면 먼저 `copyExit`한다. 키보드로 들어가 `v`를 눌러 둔 상태에서 `copySelect(.char)`를
     부르면 "같은 방식을 다시 눌렀다"가 되어 선택이 풀린다(`vt_test` 검사 99). `copyEnter`는 안 부른다 — 그 함수의 일은
     커서를 셸 커서 자리에 두는 것뿐이고 곧바로 덮어쓴다.
   - `copyPointTo`는 칸이 같아도 다시 맞춘다. 끄는 중의 휠이 뷰포트를 밀면 같은 뷰포트 칸이 다른 글자다(확정 8,
     `vt_test` 검사 101). 같은 칸으로 거듭 부르지 않는 일은 `Gesture`가 한다.
   - 둘 다 좌표를 화면 안으로 붙인다(`copyClamp`, `copyMove`와 같은 규칙). `main.zig`가 이미 패널 사각형으로 잘라
     넘기지만, `vt.zig`의 공개 함수가 범위 밖 좌표를 그대로 `copy_cursor`에 담으면 `cells()`가 화면 밖 커서를 다룬다.
   - `copyPointTo`의 끝은 `copyMove`와 같은 모양이다 — 지금 선택의 start가 곧 앵커다(CM 결정 5). 그래서 끌어 만든
     선택에서 `y`를 쳐도 키보드로 만든 선택과 같은 문자열이 나온다(`vt_test` 검사 97).

   `copyPin` · `copyApply`는 그대로 private이다. 두 공개 함수가 같은 파일 안에서 부른다.

7. `pointerMode`(`input.zig`).

   ```zig
   pub fn pointerMode(self: *State, to: Mode) []const u8 {
       switch (self.mode) {
           .normal => self.commitHangul(),
           .copy, .find => self.hangul_buf = .{},
       }
       self.mode = to;
       return self.takeCommit();
   }
   ```

   normal이면 확정하고, find면 버린다(`Esc`와 같은 뜻 — SH 결정 3). copy에서는 조합이 남아 있을 수 없지만(copy mode에
   들어가는 키가 이미 확정했다) 남아 있으면 버린다. 돌려주는 슬라이스는 `commit_buf`를 가리키므로 호출부가 바로 쓴다.

   부르는 자리는 셋이다. `cancel`(→ normal, 확정분은 옛 포커스의 PTY), `select_start`(→ copy, 확정분은 누른 패널의 PTY —
   누른 뒤 첫 이동 전에 친 한글이 있을 수 있고, 누름이 포커스를 이미 옮겼다), `copy`(→ normal, 확정분은 없다). 순서는
   `main.zig`의 편집 E4가 정한다 — 확정분을 쓰고, 그 패널의 `setPreedit(null)`, 그다음 화면 쪽(`copyExit` ·
   `copyEnterAt`).

   design 결정 2가 미룬 검사도 여기 둔다. 키보드 fd로 온 `BTN_LEFT`(0x110)는 키맵 밖의 코드라 바이트도 모드 변화도
   없다(`input_test` 검사 67). 한 가지는 design과 다르다 — 조합 중이면 확정한다. `hangulLayer`의 "표 밖의 키" 갈래(HI
   결정 6, 방향키 · PageUp과 같다)다. 같은 누름이 포인터 경로에서도 `cancel`로 확정을 부르므로 결과가 어긋나지 않는다.
   그 갈래를 막는 코드는 넣지 않았다.

8. 끄는 중의 휠(design 결정 7의 마지막 줄). 누른 패널을 움직이고 선택 끝을 지금 포인터 칸으로 다시 맞춘다. design은
   "끄는 중"이라 적었는데, 누르기만 하고 아직 안 끈(`pressed`) 채 굴린 휠도 같은 갈래로 넣었다. 그때는 선택을 먼저
   시작한다.

   순서가 요점이다 — `select_start`(앵커가 누른 글자에 붙는다) → `scroll` → `select_to`(같은 뷰포트 칸이 이제 세 줄 위
   글자다). 순서가 뒤집히면 앵커가 스크롤 뒤의 글자에 붙어 한 글자짜리 선택이 된다(`pointer_test` 검사 22가 순서를
   본다). 앵커는 tracked selection이라 뷰포트가 움직여도 글자에 붙어 있다(CM 결정 5).

   PD-M1의 "키보드 copy mode인 패널에서는 휠을 무시한다"는 그대로다. 그것은 제스처가 아닌 휠(아무것도 안 누른 채)의
   규칙이다. 끄는 중의 copy mode는 포인터의 것이라 휠이 선택을 함께 옮긴다.

9. 로그 줄. design 결정 10의 예시(`press leaf=0 row=3 col=10` · `release drag=1`)에 둘을 더했다. `press none`(누른
   자리가 패널 칸이 아니다 — 체인 검사 14가 "누름이 도착했고 아무 일도 안 했다"를 이 줄로 본다)과 `copy> point`(끄는
   동안의 선택 끝)다. 선택의 시작 · 복사 · 닫기는 키보드의 copy mode와 같은 줄(`copy> enter` · `clip>` · `copy> yank` ·
   `copy> exit`)이라 copy 체인의 수법(`clip> len= text=`를 보고 `Cmd+V` 에코로 왕복)을 그대로 쓴다.

   `press` · `release`는 의도를 실행하기 전에 찍는다. 그래서 `press` 뒤에 `copy> exit`이나 `pane>`(그 회차의 프레임)이
   온다. 누름 회차의 프레임은 그 회차 끝에 찍히므로, 체인이 뗌의 `release` 줄을 보면 누름 회차의 `pane>`은 이미 로그에
   있다.

10. 체인의 순서. PD-M1의 검사 12 뒤, 부팅 마우스를 빼는 마지막 검사(9의 둘째) 앞에 넣는다. 그 자리에서 포인터는
    (679, 0)이고 패널은 하나(seq 200의 스크롤백)다. 끝에서 포인터를 (679, 0)으로 되돌린다 — 마지막 검사가 그 자리의
    `at` 줄을 보고, 움직여야 화살표가 다시 보여 뺄 때 숨는 줄이 찍힌다.

    격자는 (20, 20)에서 시작하고 칸은 8 × 16이다. `Cmd+D` 뒤 왼쪽은 0~76열, 구분선 77열, 오른쪽 78~154열이다.
    칸의 픽셀은 x = 20 + 8 × 열, y = 20 + 16 × 행이고 오른쪽 아래 끝은 거기에 7 · 15를 더한다(체인의 `cell_x` ·
    `cell_y`).

    | 순서 | 검사 | 친다 | 본다 |
    |---|---|---|---|
    | 1 | — | `Cmd+D` | `pane> … panes=2 focus=1 rect=78,0 77x47` |
    | 2 | 14 | 구분선 칸(77열, 10행)의 왼쪽 위 끝(636, 180)과 오른쪽 아래 끝(643, 195)에서 누르고 뗀다 | `press none` 둘 · `release drag=0` 둘 · `pane>` 줄 수가 그대로 |
    | 3 | 13 | 왼쪽 76열 칸의 오른쪽 아래 끝(635, 195), 오른쪽 78열 칸의 왼쪽 위 끝(644, 180)에서 클릭 | `press leaf=0 row=10 col=76` → `focus=0`, `press leaf=1 row=10 col=0` → `focus=1`. `clip>` · `copy> enter` 줄 수가 그대로 |
    | 4 | 15 | 오른쪽 패널에 `echo pd-drag-word`. 그 줄 0열을 누르고 0.5초, `mouse_move 95 15`, 뗀다 | 누름만으로는 `copy> enter`가 안 는다 · `copy> enter row=R col=0` · `copy> point row=R col=11` · 상태 줄 꼬리 `  COPY` · `release drag=1` · `clip> len=12 text=pd-drag-word` · `COPY`가 사라진다 |
    | 5 | 18 | `echo pd-after-drag` | 출력 줄 `pd-after-drag` |
    | 6 | 15의 둘째 | `echo got-` · `Cmd+V` · Enter | `clip> paste len=12` · 출력 줄 `got-pd-drag-word` |
    | 7 | 17 | `Cmd+Shift+C` 뒤 클릭, `echo pd-click-out` | `copy> exit` · `clip>` 줄 수가 그대로 · 출력 줄 `pd-click-out` |
    | 8 | 17의 둘째 | `Cmd+Shift+C` · `/` · `q` 뒤 클릭, `echo pd-find-out` | `copy> exit` · 출력 줄 `pd-find-out` · 마지막 프레임에 `find> overlay`가 없다 |
    | 9 | 16 | 왼쪽 패널 클릭(`focus=0`), `seq -s , 40`. 접힌 첫 줄(`seq -s , 29`와 같은 77자)의 0열을 누르고 x 720(오른쪽 패널 87열)까지 끌어 뗀다 | `copy> point row=R col=76` · `clip> len=77 text=1,2,…,29` · `focus=0` 그대로 |
    | 10 | 16의 둘째 | `seq 120 160`. `150`의 0열을 누른 채 휠 위로 한 눈금, 뗀다 | `offset`이 3 준다 · `copy> enter row=R col=0` · `clip> len=13 text=147` |
    | 11 | — | (679, 0)으로 옮긴다 | 마지막 검사의 전제 |

    검사 14를 13보다 먼저 하는 이유는 mutation 1이다. `hit`이 구분선 칸을 왼쪽 잎에 넣으면 포커스가 0으로 간다 —
    포커스가 이미 0이면 그 고장이 안 보인다. `Cmd+D` 직후라 포커스가 1이다.

    검사 16에 마지막 열까지 글자가 찬 줄을 쓰는 이유. `copyYank`가 줄 끝 공백을 트림하므로, 짧은 줄로는 선택이 76열에서
    끝났는지 22열에서 끝났는지가 문자열로 안 갈린다. `seq -s , 29`는 77자다(1~9가 쉼표와 함께 18자, 10~29가 60자, 마지막
    쉼표를 뺀다). `seq -s , 40`의 출력(110자)이 77칸에서 접히면 첫 줄이 정확히 그것이다. 체인은 기대 문자열을 컨테이너의
    `seq -s , 29`로 만든다.

    검사 16의 둘째에서 13바이트는 `147\n148\n149\n1`이다. 앵커가 `150`의 0열에 붙고 끝이 세 줄 위 `147`의 0열이라 문자
    단위 선택이 `150`의 첫 글자에서 끝난다. `clip>` 줄은 개행을 그대로 찍으므로 체인은 첫 줄 `clip> len=13 text=147`만
    본다(copy 체인 검사의 `clip> len=21 text=echo PEONE`과 같은 수법).

    글자 판정은 전부 친 줄과 겹치지 않는다(`project_gate_screen_echo`). `'\| pd-after-drag \|'`처럼 그 글자만 있는 출력
    줄을 보고, 명령줄(`root@(none) ~# echo pd-after-drag`)은 앞에 `| `가 안 붙는다. 글자에 `y` · `v` · `n` · `w` · `b` ·
    `/`를 안 쓴 것은 mutation 3에서 입력 모드가 copy에 남았을 때 그 키가 copy 명령(`y`는 yank)이 되어 모드를 바꾸지
    않게 하기 위해서다 — 그러면 빨개지는 자리와 문구가 흔들린다.

    패널의 행 번호는 마지막 `screen>`에서 그 글자만 있는 구간의 번호로 구한다(체인의 `screen_row`, perl). `screen>`은
    포커스 패널의 행을 ` | `로 잇고 행이 바뀔 때마다 구분자가 하나씩 붙으므로(`dumpScreen`) 구간의 번호가 곧 행
    번호다. 세로 분할의 두 패널은 격자의 0행에서 시작하므로 패널의 행이 곧 격자의 행이다.

11. mutation 넷. design 결정 10의 M2 네 줄이다. 넣는 법은 PD-M1 plan 확정 12와 같다 — 저장소 파일은 안 고치고, 사본을
    `-v`로 그 파일 자리에 덮는다. 같은 `docker run` 안에서 `terminal/.zig-cache` · `terminal/zig-out`을 지우고, 덮인 사본이
    쓰였는지 `grep -c`로 mutation 글자를 센다. 조건에는 runtime 값을 쓴다(`self.cols == 0`).

    | mutation | 심는 고장 | 고치는 줄 | 빨개지는 자리 |
    |---|---|---|---|
    | 1 | `hit`이 구분선 칸을 왼쪽 잎에 넣는다 | `layout.zig` `if (col < r.col or col >= r.col + r.cols) continue;` → `col > r.col + r.cols` | `layout_test` 검사 12가 부팅 전에. 그것을 끈 사본 체인에서는 검사 14 — `press leaf=0 row=10 col=77` |
    | 2 | 뗌에서 `copyYank`를 안 부른다 | `main.zig` `dumpClip(try p.screen.copyYank());` 앞에 `if (self.cols == 0) ` | 검사 15 — 새 `clip> len=` 줄이 없다 |
    | 3 | 뗌 뒤 `pointerMode`를 안 부른다 | `main.zig` `_ = self.key_state.pointerMode(.normal);` 앞에 `if (self.cols == 0) ` | 검사 18 — `pd-after-drag`가 셸에 안 온다(copy 표가 삼킨다) |
    | 4 | 끄는 칸을 누른 패널로 자르지 않는다 | `main.zig` `const h = layout.clampInto(…);` → `const h = self.ws.tree.hit(self.whole, gc.col, gc.row) orelse layout.clampInto(…);` | 검사 16 — 선택 끝이 `col=9`(오른쪽 패널의 상대 칸이 왼쪽 패널에 적용된다) |

    mutation 3은 design이 "`pointerMode`를 안 부른다"고만 적은 것을 뗌 쪽 한 자리로 좁혔다. `select_start`의
    `pointerMode(.copy)`를 빼면 끄는 동안 친 키가 셸로 가지만, 뗌이 normal로 되돌리므로 검사 18은 초록이다. 끄는 동안
    키를 치는 검사는 체인에 없다 — `input_test` 검사 64가 "pointerMode(.copy) 뒤 `j`는 copy 표로 간다"를 본다.

    mutation 4가 검사 15에서는 초록인 것이 맞다. 검사 15의 끌기는 오른쪽 패널 안에서 끝나므로 `hit`과 `clampInto`가 같은
    칸을 준다.

12. 사본에서 돌려 본 것. plan은 PD-M1 게이트가 도는 동안 써서 처음에는 기계 대조만 했고, 게이트가 끝나고 PD-M1 ·
    반복 수 commit이 들어간 뒤(`6f4dfb2`) 아래를 쟀다. 저장소를 `/tmp/run/pdm2/repo/`로 통째로 복사하고(`.git` ·
    zig 캐시 제외) 이 plan의 편집 25개를 `/tmp/run/pdm2/apply.py`로 넣어 거기서 돌렸다. 저장소의 작업 트리는 한 글자도
    안 바뀌었다. 체인의 monitor 포트는 저장소와 같은 45488이다(VM을 혼자 썼다).

    | 무엇 | 결과 |
    |---|---|
    | 앵커(`/tmp/run/pdm2/anchors.py pre`) | `pre: 25 edits, 0 bad` — PD-M1 구현이 들어간 작업 트리(commit 전)에서 각 `old_string`이 정확히 한 번 |
    | 편집 추출(`hunks.py`) | 원본에 `old_string` → `new_string`을 차례로 넣으면 사본과 바이트까지 같다(스크립트 안의 assert) |
    | `bash -n pointer/check.sh` | 통과 |
    | 앵커를 `6f4dfb2`에서 다시 | `pre: 25 edits, 0 bad`. 소스 아홉과 `pointer/check.sh`는 기준 사본과 바이트까지 같았다. `check.sh`는 `RUNS` 블록이 들어가 줄이 8줄 밀렸고, 이 plan의 두 앵커는 그 블록과 안 겹친다 — 새 HEAD로 사본을 다시 만들어 편집을 다시 뽑았다(줄 번호만 바뀌었다) |
    | `zig build` | `build=0` |
    | `zig build test` | `test=0`. OK 줄이 `pointer_test` 75 → 107(+32), `layout_test: hit` 22 → 30, `vt_test` 105 → 110, `input_test` 12 → 15. `all checks passed` 셋과 `PASS` 다섯 |
    | `zig fmt --check` | `pointer` · `pointer_test` · `layout` · `layout_test` · `vt_test`는 깨끗하다. `vt` · `input` · `input_test` · `main`은 고치기 전부터 fmt와 다르다 — 기준과 결과를 각각 `zig fmt`으로 돌려 차이를 비교하니 이 plan이 더한 줄에서 생긴 차이는 0이었다 |
    | 진입 검사 셋 | `ENTRY-OK`, `bash -n` 둘 통과 |
    | 체인 `pointer` | `PD-M2 check PASS` 두 판 — 1분 0초 · 37초(둘째는 빌드 캐시가 있었다). 줄은 Task 6-1의 기대 그대로 |
    | regression `render` · `copy` · `pane` | `TR-M2 PASS` 1분 47초 · `CM-M2 check PASS` 2분 51초 · `WP-M2 check PASS` 33초 |
    | mutation 1~4 | 넷 다 Task 7의 표의 자리와 문구 그대로 빨갰다. 1분 28초 · 1분 51초 · 2분 4초 · 1분 55초 |

    컨테이너는 하나씩 돌렸고 `Killed`는 한 번도 없었다.

    PD-M1이 commit돼도 앵커는 그대로 맞는다 — commit은 작업 트리의 글자를 바꾸지 않는다. lead가 그 뒤에 만드는 루트
    게이트 반복 수 commit(확정 13)은 `check.sh`의 `run_chain` · `3/3` 자리만 고치고, 이 plan의 `check.sh` 앵커 둘(체인
    설명 문단 · `CHAINS` 줄)은 그 자리와 안 겹친다.

13. 루트 게이트는 2회다(`feedback_gate_runs`, 2026-10-05 사용자 결정). lead가 PD-M1 commit 바로 뒤에 PD와 무관한
    별도 commit(`6f4dfb2`)으로 `check.sh`에 `RUNS=2`를 두었고 PASS 문구가 `PASS: 2/2`가 됐다. 이 plan은 그 commit
    위에 서 있다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다. Task 6 · 7이 docker로 체인을 돌리므로 겹치면 monitor 포트와
   `kernel/initrd.cpio`가 부딪치고, Docker VM의 메모리(4GB)를 넘는다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -4
   rg -n '^RUNS=' check.sh
   ```

   기대: `git status`는 이 plan 파일(`??` 또는 이미 commit됐으면 0줄)과, lead가 고치는 중일 수 있는 `HANDOFF.md`뿐이다.
   `6f4dfb2 Run each gate chain twice …`와 `8dcf6f1 PD-M1: …`이 보여야 한다. 셋째 명령은 `RUNS=2`의 자리를 본다 —
   `check.sh`에 `RUNS=2`가 있어야 한다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 12).

   ```bash
   python3 /tmp/run/pdm2/anchors.py pre "$PWD"
   ```

   기대: `pre: 25 edits, 0 bad`. 하나라도 `bad`면 그 줄(`파일 edit N: pre count=…`)을 보고하고 멈춘다.

4. 호스트 검사를 한 번 초록으로 본다.

   ```bash
   mkdir -p /tmp/run/pdm2/impl
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
     bash -c 'zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -a -c "^pointer_test: .* OK$" /tmp/t.out; grep -a -c "^layout_test: hit .* OK$" /tmp/t.out; grep -a -E "all checks passed|^PASS$|FAIL" /tmp/t.out'
   ```

   기대: `exit=0`, `75`, `22`, `all checks passed` 셋과 `PASS` 다섯. `FAIL`은 0줄. (`pointer_test`의 75는 PD-M1 plan이
   적은 69와 다르다 — 그 수는 grep의 패턴이 달랐을 때의 것이고, 이 plan은 위 명령으로 `6f4dfb2`에서 잰 75를 쓴다.)

## Task 1: `terminal/src/pointer.zig` · `pointer_test.zig` — 제스처

`pointer.zig`는 Edit 둘이다. 머리 주석의 층 목록을 셋에서 넷으로 고치고, 파일 끝(`Sprite`의 닫는 중괄호 뒤)에 제스처
절을 붙인다. 순수한 그대로다 — 시스템 콜도 import도 새로 없다.

읽을 자리 셋. `press`가 패널 칸이면 언제나 `cancel`을 내는 것(확정 3), `motion`이 받은 칸의 잎 대신 `start.leaf`를
쓰는 것(확정 5), `wheel`의 `pressed` 갈래가 `select_start`를 `scroll`보다 먼저 넣는 것(확정 8).

`old_string`(기준 파일 7줄부터):

```zig
//! 층은 셋이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼).
//! 누름 · 끎 · 뗌을 의도로 바꾸는 `Gesture`는 PD-M2가 여기에 더한다.
```

`new_string`:

```zig
//! 층은 넷이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼) →
//! `Gesture`(누름 · 끎 · 뗌 · 휠을 의도로, PD-M2).
```

`old_string`(기준 파일 443줄부터):

```zig
        return n;
    }
};
```

`new_string`:

```zig
        return n;
    }
};

// ── 제스처(PD-M2) ─────────────────────────────────────────────────────
//
// 누름 · 끎 · 뗌 · 휠을 "포커스 옮김 · 선택 시작 · 선택 늘림 · 복사 · 스크롤"
// 의도로 바꾼다(PD design 결정 3 · 6). 판단만 한다 — 패널도 화면도 모른다.
// 의도를 실행하는 것은 `main.zig`이고, 그 실행이 바꾼 것(포커스가 옮겨졌다,
// 키보드가 copy mode를 닫았다)은 `main.zig`가 다음 단계에 `Target`으로
// 알려 준다.

/// 패널 안의 칸 하나. `layout.Hit`과 같은 모양이다 — 이 파일은 `layout.zig`를
/// import하지 않으므로(머리 주석) `main.zig`가 옮겨 담는다. `col` · `row`는
/// 그 잎의 사각형 안의 상대 칸이고 `vt.Screen`이 아는 뷰포트 좌표다.
pub const Cell = struct { leaf: u4, col: u16, row: u16 };

/// 누른 패널이 지금 어떤 상태인가. `main.zig`가 단계마다 알려 준다.
pub const Target = enum {
    /// 누른 패널이 더는 포커스가 아니다. 누른 뒤 키보드가 포커스나
    /// 워크스페이스를 옮겼거나, 그 패널이 닫혔다.
    gone,
    /// 포커스이고 copy mode가 아니다.
    normal,
    /// 포커스이고 copy mode다.
    copy,
};

/// 끄는 중의 휠(design 결정 7). 누른 패널을 `notches` 눈금만큼 움직인다.
/// 양수가 휠을 앞으로 민 것이고 위로 간다 — `Frame.wheel`과 같다.
pub const Scroll = struct { leaf: u4, notches: i32 };

/// `Gesture`가 내는 의도. `main.zig`의 switch가 `else` 없이 닫는다 —
/// variant를 하나 더하면 컴파일러가 배선할 자리를 알려 준다(design 결정 3).
pub const Intent = union(enum) {
    /// 키보드 쪽 모드를 끝낸다. 조합 중인 한글을 확정하거나 버리고, 지금
    /// 포커스 패널의 copy mode와 검색 프롬프트를 복사 없이 닫는다.
    cancel,
    /// 포커스를 이 잎으로 옮긴다.
    focus: u4,
    /// copy mode에 들어가며 이 칸에서 문자 단위 선택을 시작한다.
    select_start: Cell,
    /// 선택 끝을 이 칸으로 옮긴다. 칸이 같아도 다시 맞춘다 — 휠이 뷰포트를
    /// 밀었으면 같은 칸이 다른 글자다.
    select_to: Cell,
    /// 누른 패널을 휠 눈금만큼 움직인다.
    scroll: Scroll,
    /// 이 잎의 선택을 클립보드에 넣고 copy mode를 나간다(`Cmd+C`와 같다).
    copy: u4,
};

/// 한 단계가 내는 의도들. 셋을 넘지 않는다 — 누름이 `cancel` · `focus`,
/// 첫 이동이 `select_start` · `select_to`, 누른 채 첫 휠이 `select_start` ·
/// `scroll` · `select_to`다. 순서대로 실행한다.
pub const Intents = struct {
    buf: [3]Intent = undefined,
    len: usize = 0,

    fn push(self: *Intents, it: Intent) void {
        self.buf[self.len] = it;
        self.len += 1;
    }

    pub fn items(self: *const Intents) []const Intent {
        return self.buf[0..self.len];
    }
};

/// 왼쪽 버튼 하나의 누름 · 끎 · 뗌(PD design 결정 6).
///
/// | phase | 뜻 |
/// |---|---|
/// | `idle` | 버튼이 안 눌렸다 |
/// | `pressed` | 패널 칸 위에서 눌렀고 아직 다른 칸에 안 닿았다. copy mode에 아직 안 들어갔다 |
/// | `dragging` | 다른 칸에 닿아 선택 중이다 |
/// | `ignored` | 뗄 때까지 아무것도 안 한다 — 여백 · 구분선을 눌렀거나, 키보드가 모드를 닫았거나, 누른 패널이 포커스를 잃었다 |
///
/// copy mode에 누름이 아니라 첫 칸 이동에 들어가는 이유는 클릭이다(design
/// 결정 6). 누름에 들어가면 모든 클릭이 한 프레임 동안 `COPY`를 띄우고,
/// 떼는 순간 앵커와 끝이 같은 한 칸 선택이 남는다.
///
/// 누른 잎을 기억하는 것이 가장자리 처리의 절반이다(design 결정 5). 선택
/// 끝의 잎은 언제나 누른 잎이다 — `motion`이 받은 칸의 잎은 안 본다.
/// 나머지 절반(끄는 칸을 누른 패널의 사각형으로 자르는 것)은 사각형을
/// 아는 `main.zig`가 한다.
pub const Gesture = struct {
    phase: Phase = .idle,
    /// 누른 칸. `phase`가 `pressed` · `dragging`일 때만 뜻이 있다.
    start: Cell = .{ .leaf = 0, .col = 0, .row = 0 },
    /// 마지막으로 선택 끝을 맞춘 칸. `pressed`에서는 `start`와 같다.
    cur: Cell = .{ .leaf = 0, .col = 0, .row = 0 },

    pub const Phase = enum { idle, pressed, dragging, ignored };

    /// 누른 잎. 버튼이 패널 칸 위에서 눌린 채이면 그 잎이고, 아니면 null이다.
    /// `main.zig`가 끄는 칸을 자를 사각형과 `Target`을 이것으로 고른다.
    pub fn held(self: *const Gesture) ?u4 {
        return switch (self.phase) {
            .pressed, .dragging => self.start.leaf,
            .idle, .ignored => null,
        };
    }

    /// 왼쪽 버튼이 눌렸다. `hit`은 누른 자리의 칸이고 여백 · 구분선 ·
    /// 상태 줄이면 null이다. `focus`는 지금 포커스 잎이다.
    ///
    /// 패널 칸이면 언제나 `cancel`을 낸다 — 그 패널이 키보드 copy mode였으면
    /// 닫히고(선택의 주인은 한 번에 하나다), 다른 패널이면 옛 포커스 패널의
    /// copy mode가 닫힌다. 키보드 copy mode는 포커스 패널에만 있다(copy 표가
    /// `Cmd+]`를 삼킨다). 그리고 다른 패널이면 `focus`를 낸다. 순서가
    /// 계약이다 — 조합 중인 한글은 옛 포커스의 PTY로 가야 한다(WP 결정 4).
    pub fn press(self: *Gesture, hit: ?Cell, focus: u4) Intents {
        var out: Intents = .{};
        const h = hit orelse {
            self.phase = .ignored;
            return out;
        };
        self.phase = .pressed;
        self.start = h;
        self.cur = h;
        out.push(.cancel);
        if (h.leaf != focus) out.push(.{ .focus = h.leaf });
        return out;
    }

    /// 포인터가 움직였다. `cell`은 누른 패널의 사각형으로 이미 자른 칸이다
    /// (`target`이 `gone`이면 무엇이든 된다).
    pub fn motion(self: *Gesture, cell: Cell, target: Target) Intents {
        var out: Intents = .{};
        const at: Cell = .{ .leaf = self.start.leaf, .col = cell.col, .row = cell.row };
        switch (self.phase) {
            .idle, .ignored => {},
            .pressed => {
                if (target == .gone) {
                    self.phase = .ignored;
                } else if (!sameCell(at, self.start)) {
                    self.phase = .dragging;
                    out.push(.{ .select_start = self.start });
                    out.push(.{ .select_to = at });
                    self.cur = at;
                }
            },
            .dragging => {
                // 키보드가 모드를 닫았다(`Esc` · `y` · `Cmd+C`, design 결정 6의
                // 표). 뗄 때까지의 움직임은 무시한다.
                if (target != .copy) {
                    self.phase = .ignored;
                } else if (!sameCell(at, self.cur)) {
                    out.push(.{ .select_to = at });
                    self.cur = at;
                }
            },
        }
        return out;
    }

    /// 왼쪽 버튼을 뗐다. 끈 뒤이고 copy mode가 살아 있으면 `copy`를 낸다.
    /// 안 끈 채(클릭)면 아무 일도 없다 — 클릭의 일은 누름이 이미 했다.
    pub fn release(self: *Gesture, target: Target) Intents {
        var out: Intents = .{};
        if (self.phase == .dragging and target == .copy) out.push(.{ .copy = self.start.leaf });
        self.phase = .idle;
        return out;
    }

    /// 휠을 굴렸다. 버튼이 패널 칸 위에서 눌린 채면 누른 패널을 움직이고
    /// 선택 끝을 다시 맞춘다(design 결정 7의 "끄는 중"). 한 화면보다 긴
    /// 선택을 만드는 길이다.
    ///
    /// null이면 이 휠은 제스처의 것이 아니다 — `main.zig`가 평소의 휠(포인터
    /// 아래 패널)로 다룬다.
    ///
    /// 아직 안 끌었으면(`pressed`) 여기서 선택을 시작한다. 시작이 스크롤보다
    /// 먼저인 것이 요점이다 — 앵커가 누른 글자에 붙은 뒤에 뷰포트가 움직여야
    /// 한다. 순서가 뒤집히면 누른 칸의 뷰포트 좌표가 다른 글자를 가리킨다.
    pub fn wheel(self: *Gesture, notches: i32, target: Target) ?Intents {
        var out: Intents = .{};
        switch (self.phase) {
            .idle, .ignored => return null,
            .pressed => {
                if (target == .gone) {
                    self.phase = .ignored;
                    return null;
                }
                self.phase = .dragging;
                out.push(.{ .select_start = self.start });
            },
            .dragging => {
                if (target != .copy) {
                    self.phase = .ignored;
                    return null;
                }
            },
        }
        out.push(.{ .scroll = .{ .leaf = self.start.leaf, .notches = notches } });
        out.push(.{ .select_to = self.cur });
        return out;
    }
};

/// 두 칸이 같은가.
pub fn sameCell(a: Cell, b: Cell) bool {
    return a.leaf == b.leaf and a.col == b.col and a.row == b.row;
}
```

`pointer_test.zig`는 Edit 둘이다. 헬퍼 `expectIntents`(의도 목록을 순서까지 비교한다)와 검사 16~22다. 검사 번호는 이
파일의 마지막(15)에서 잇는다.

`old_string`(기준 파일 82줄부터):

```zig
    return error.WrongFrame;
```

`new_string`:

```zig
    return error.WrongFrame;
}

/// 의도 목록이 기대와 같은가. 순서까지 본다 — `cancel`이 `focus`보다 먼저,
/// `select_start`가 `scroll`보다 먼저인 것이 design 결정 6 · 7의 계약이다.
fn expectIntents(what: []const u8, got: pointer.Intents, want: []const pointer.Intent) !void {
    const items = got.items();
    var same = items.len == want.len;
    if (same) {
        for (items, want) |g, w| {
            if (!std.meta.eql(g, w)) same = false;
        }
    }
    if (same) {
        std.debug.print("pointer_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, items, want });
    return error.WrongIntents;
```

`old_string`(기준 파일 435줄부터):

```zig
    std.debug.print("pointer_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 16: 클릭(PD-M2) ───────────────────────────────────────────────
    //
    // 누름은 위치를 기억하고 키보드 쪽 모드를 닫는다(`cancel`). copy mode에는
    // 아직 안 들어간다 — 끌지 않고 떼면 아무 일도 없다(design 결정 6).
    const a: pointer.Cell = .{ .leaf = 0, .col = 3, .row = 2 };
    {
        var g: pointer.Gesture = .{};
        try expectIntents("a click on the focused pane only cancels", g.press(a, 0), &.{.cancel});
        try expectTrue("the press remembers the leaf", g.held() != null and g.held().? == 0);
        try expectIntents("a move inside the same cell does nothing", g.motion(a, .normal), &.{});
        try expectIntents("releasing a click copies nothing", g.release(.normal), &.{});
        try expectTrue("after the release nothing is held", g.held() == null and g.phase == .idle);

        // 다른 패널을 누르면 포커스가 그리로 간다. `cancel`이 먼저다 — 조합
        // 중인 한글이 옛 포커스의 PTY로 가야 한다(WP 결정 4).
        const b: pointer.Cell = .{ .leaf = 1, .col = 0, .row = 5 };
        try expectIntents("a click on another pane cancels, then moves the focus", g.press(b, 0), &.{ .cancel, .{ .focus = 1 } });
        try expectIntents("its release copies nothing", g.release(.normal), &.{});
    }

    // ── 검사 17: 여백 · 구분선 · 상태 줄을 누른다 ─────────────────────────
    //
    // 아무 일도 없다 — 포커스도 안 바뀌고 키보드 copy mode도 안 닫힌다. 뗄
    // 때까지의 움직임과 휠도 제스처의 것이 아니다(휠은 평소의 휠로 간다).
    {
        var g: pointer.Gesture = .{};
        try expectIntents("a press off any pane does nothing", g.press(null, 0), &.{});
        try expectTrue("a press off any pane holds nothing", g.held() == null);
        try expectIntents("dragging from the margin does nothing", g.motion(a, .normal), &.{});
        try expectTrue("a wheel after a margin press is the plain wheel", g.wheel(1, .normal) == null);
        try expectIntents("releasing it does nothing", g.release(.normal), &.{});
    }

    // ── 검사 18: 끌어서 고르고 떼면 복사한다 ───────────────────────────────
    //
    // 처음으로 다른 칸에 닿을 때 들어간다 — `select_start`(누른 칸)와
    // `select_to`(지금 칸)가 함께 나온다. 그 뒤로는 칸이 바뀔 때만 `select_to`다.
    {
        var g: pointer.Gesture = .{};
        _ = g.press(a, 0);
        try expectIntents("the first move to another cell starts the selection", g.motion(.{ .leaf = 0, .col = 5, .row = 2 }, .normal), &.{
            .{ .select_start = a },
            .{ .select_to = .{ .leaf = 0, .col = 5, .row = 2 } },
        });
        try expectTrue("the gesture is dragging", g.phase == .dragging);
        try expectIntents("the same cell again does nothing", g.motion(.{ .leaf = 0, .col = 5, .row = 2 }, .copy), &.{});
        try expectIntents("a new cell moves the end", g.motion(.{ .leaf = 0, .col = 7, .row = 4 }, .copy), &.{
            .{ .select_to = .{ .leaf = 0, .col = 7, .row = 4 } },
        });
        try expectIntents("the release after a drag copies", g.release(.copy), &.{.{ .copy = 0 }});
        try expectTrue("after the copy nothing is held", g.held() == null);
    }

    // ── 검사 19: 선택 끝의 잎은 언제나 누른 잎이다 ─────────────────────────
    //
    // 가장자리 처리의 절반(design 결정 5). `main.zig`가 칸을 누른 패널로
    // 자르지만, 이웃 잎의 칸이 들어와도 잎은 누른 잎이다.
    {
        var g: pointer.Gesture = .{};
        _ = g.press(a, 0);
        try expectIntents("a cell from another leaf still ends in the pressed leaf", g.motion(.{ .leaf = 1, .col = 9, .row = 2 }, .normal), &.{
            .{ .select_start = a },
            .{ .select_to = .{ .leaf = 0, .col = 9, .row = 2 } },
        });
    }

    // ── 검사 20: 키보드가 모드를 닫았거나 패널이 포커스를 잃었다 ─────────
    //
    // 끄는 중에 `Esc` · `y` · `Cmd+C`가 오면 키보드 경로가 모드를 닫는다. 뗄
    // 때까지의 움직임은 무시하고 뗌도 아무것도 안 한다(design 결정 6의 표).
    // 누른 패널이 포커스를 잃어도(`gone`) 같다.
    {
        var g: pointer.Gesture = .{};
        _ = g.press(a, 0);
        _ = g.motion(.{ .leaf = 0, .col = 5, .row = 2 }, .normal);
        try expectIntents("a move after the keyboard closed the mode does nothing", g.motion(.{ .leaf = 0, .col = 6, .row = 2 }, .normal), &.{});
        try expectTrue("the gesture now ignores the rest", g.phase == .ignored);
        try expectIntents("even if copy mode comes back, moves stay ignored", g.motion(.{ .leaf = 0, .col = 7, .row = 2 }, .copy), &.{});
        try expectIntents("the release copies nothing", g.release(.copy), &.{});

        _ = g.press(a, 0);
        try expectIntents("a move after the pressed pane lost the focus does nothing", g.motion(.{ .leaf = 0, .col = 5, .row = 2 }, .gone), &.{});
        try expectIntents("and its release copies nothing", g.release(.normal), &.{});
    }

    // ── 검사 21: 누른 뒤 키보드가 copy mode에 들어갔다 ───────────────────
    //
    // 첫 이동 전에 `Cmd+Shift+C`를 쳤다. 끌기가 시작되면 끌기의 것이다 —
    // `select_start`를 그대로 내고, `vt.Screen.copyEnterAt`이 키보드 copy mode를
    // 먼저 닫는다.
    {
        var g: pointer.Gesture = .{};
        _ = g.press(a, 0);
        try expectIntents("a drag still starts when the keyboard entered copy mode first", g.motion(.{ .leaf = 0, .col = 4, .row = 2 }, .copy), &.{
            .{ .select_start = a },
            .{ .select_to = .{ .leaf = 0, .col = 4, .row = 2 } },
        });
    }

    // ── 검사 22: 끄는 중의 휠 ─────────────────────────────────────────────
    //
    // 누른 채 굴리면 누른 패널을 움직이고 선택 끝을 지금 칸으로 다시 맞춘다
    // (design 결정 7). 아직 안 끌었으면 선택을 먼저 시작한다 — 앵커가 누른
    // 글자에 붙은 뒤에 뷰포트가 움직여야 한다. 칸이 같아도 `select_to`를 낸다.
    {
        var g: pointer.Gesture = .{};
        _ = g.press(a, 0);
        try expectIntents("a wheel while pressed starts the selection before it scrolls", g.wheel(1, .normal).?, &.{
            .{ .select_start = a },
            .{ .scroll = .{ .leaf = 0, .notches = 1 } },
            .{ .select_to = a },
        });
        try expectIntents("a wheel while dragging scrolls and re-points the same cell", g.wheel(-1, .copy).?, &.{
            .{ .scroll = .{ .leaf = 0, .notches = -1 } },
            .{ .select_to = a },
        });
        _ = g.motion(.{ .leaf = 0, .col = 4, .row = 2 }, .copy);
        try expectIntents("the wheel re-points the cell the pointer is on now", g.wheel(2, .copy).?, &.{
            .{ .scroll = .{ .leaf = 0, .notches = 2 } },
            .{ .select_to = .{ .leaf = 0, .col = 4, .row = 2 } },
        });
        try expectIntents("the release after a wheel copies", g.release(.copy), &.{.{ .copy = 0 }});
        try expectTrue("a wheel with nothing held is the plain wheel", g.wheel(1, .normal) == null);

        // 키보드가 모드를 닫은 뒤의 휠은 제스처의 것이 아니다.
        _ = g.press(a, 0);
        _ = g.motion(.{ .leaf = 0, .col = 5, .row = 2 }, .normal);
        try expectTrue("a wheel after the keyboard closed the mode is the plain wheel", g.wheel(1, .normal) == null);
        _ = g.release(.normal);
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
```

확인.

```bash
diff terminal/src/pointer.zig /tmp/run/pdm2/term/src/pointer.zig && echo POINTER-SAME
diff terminal/src/pointer_test.zig /tmp/run/pdm2/term/src/pointer_test.zig && echo POINTER-TEST-SAME
git diff --stat terminal/src/pointer.zig terminal/src/pointer_test.zig
git diff terminal/src/pointer.zig | rg '^-[^-]'
```

기대: `POINTER-SAME` · `POINTER-TEST-SAME`, `2 files changed, 353 insertions(+), 3 deletions(-)`. 지운 줄은 머리 주석 셋
줄뿐이다.

```
-//! 층은 셋이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
-//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼).
-//! 누름 · 끎 · 뗌을 의도로 바꾸는 `Gesture`는 PD-M2가 여기에 더한다.
```

## Task 2: `terminal/src/layout.zig` · `layout_test.zig` — `clampInto`

`layout.zig`는 Edit 하나다. `halves` 앞에 모듈 수준 함수 `clampInto`를 넣는다(확정 5).

`old_string`(기준 파일 283줄부터):

```zig
/// 사각형 하나를 둘과 구분선으로 가른다. `fill`과 `separators`가 같은
```

`new_string`:

```zig
/// 격자 칸 `(col, row)`를 사각형 `r` 안으로 붙이고 그 안의 상대 칸으로
/// 돌려준다(PD design 결정 5). 끄는 동안 선택 끝이 누른 패널 밖으로 안
/// 나가게 하는 자리다 — 이웃 패널이나 구분선 위로 끌어도 누른 패널의
/// 가장자리 칸에서 멈춘다.
///
/// `hit`과 달리 null이 없다. 끄는 중에는 포인터가 어디에 있든 선택 끝이
/// 있어야 하기 때문이다. 격자 밖의 픽셀을 격자 칸으로 붙이는 것은
/// `main.zig`의 몫이다(이 파일은 셀 단위만 안다). `r`은 넓이가 1 이상이어야
/// 한다 — `split`이 그보다 작은 잎을 안 만든다.
pub fn clampInto(r: Rect, leaf: u4, col: u16, row: u16) Hit {
    const c = @min(@max(col, r.col), r.col + r.cols - 1);
    const w = @min(@max(row, r.row), r.row + r.rows - 1);
    return .{ .leaf = leaf, .col = c - r.col, .row = w - r.row };
}

/// 사각형 하나를 둘과 구분선으로 가른다. `fill`과 `separators`가 같은
```

`layout_test.zig`는 Edit 하나다. 검사 13이고 기존 헬퍼 `expectHit`을 쓴다(그래서 OK 줄이 `layout_test: hit clamp …
OK` 모양이다).

`old_string`(기준 파일 335줄부터):

```zig
    std.debug.print("layout_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 13: 끄는 칸을 누른 패널 안으로 붙인다 (PD-M2) ────────────────
    //
    // 끄는 동안 선택 끝이 이웃 패널로 넘어가지 않는 자리다(PD design 결정 5).
    // 0 | 1에서 왼쪽은 0,0 77x47, 오른쪽은 78,0 77x47이다. 안의 칸은 `hit`과
    // 같은 상대 칸이 되고, 밖의 칸은 가장 가까운 가장자리 칸이 된다. 구분선
    // 칸(77열)은 왼쪽 잎에서는 마지막 열, 오른쪽 잎에서는 첫 열이다.
    {
        const left: Rect = .{ .col = 0, .row = 0, .cols = 77, .rows = 47 };
        const right: Rect = .{ .col = 78, .row = 0, .cols = 77, .rows = 47 };
        try expectHit("clamp inside the left leaf", layout.clampInto(left, 0, 10, 5), .{ .leaf = 0, .col = 10, .row = 5 });
        try expectHit("clamp the separator into the left leaf", layout.clampInto(left, 0, 77, 5), .{ .leaf = 0, .col = 76, .row = 5 });
        try expectHit("clamp the right leaf into the left leaf", layout.clampInto(left, 0, 120, 5), .{ .leaf = 0, .col = 76, .row = 5 });
        try expectHit("clamp past the bottom into the left leaf", layout.clampInto(left, 0, 3, 60), .{ .leaf = 0, .col = 3, .row = 46 });
        try expectHit("clamp the separator into the right leaf", layout.clampInto(right, 1, 77, 5), .{ .leaf = 1, .col = 0, .row = 5 });
        try expectHit("clamp the left leaf into the right leaf", layout.clampInto(right, 1, 10, 0), .{ .leaf = 1, .col = 0, .row = 0 });
        try expectHit("clamp inside the right leaf", layout.clampInto(right, 1, 154, 46), .{ .leaf = 1, .col = 76, .row = 46 });
        // 가로 분할의 아래 잎(78,24 77x23, 검사 12). 위로 끌어 나가면 첫 줄이다.
        const lower: Rect = .{ .col = 78, .row = 24, .cols = 77, .rows = 23 };
        try expectHit("clamp above the lower leaf", layout.clampInto(lower, 2, 100, 3), .{ .leaf = 2, .col = 22, .row = 0 });
    }

    std.debug.print("layout_test: all checks passed\n", .{});
```

확인.

```bash
diff terminal/src/layout.zig /tmp/run/pdm2/term/src/layout.zig && echo LAYOUT-SAME
diff terminal/src/layout_test.zig /tmp/run/pdm2/term/src/layout_test.zig && echo LAYOUT-TEST-SAME
git diff --stat terminal/src/layout.zig terminal/src/layout_test.zig
```

기대: `LAYOUT-SAME` · `LAYOUT-TEST-SAME`, `2 files changed, 36 insertions(+)`. 지운 줄이 없다.

## Task 3: `vt.zig` · `vt_test.zig` · `input.zig` · `input_test.zig` — 모드의 두 사본

`vt.zig`는 Edit 하나다. `copyExit` 바로 앞에 `copyEnterAt` · `copyPointTo` · `copyClamp`를 넣는다(확정 6).

`old_string`(기준 파일 1125줄부터):

```zig
    /// copy mode를 나간다. 선택도 함께 지운다 — 안 지우면 모드를 나간 뒤에도
```

`new_string`:

```zig
    /// 포인터가 copy mode에 들어간다(PD design 결정 6). 커서를 `(x, y)`에 두고
    /// 그 칸에서 문자 단위 선택을 시작한다. 좌표는 뷰포트 좌표이고 화면
    /// 밖이면 가장자리 칸으로 붙인다(`copyMove`와 같은 규칙).
    ///
    /// 이미 copy mode면 먼저 나간다. 키보드로 들어가 `v`를 눌러 둔 상태에서
    /// `copySelect(.char)`를 부르면 선택이 풀려 버린다(같은 방식을 다시 누르면
    /// 푼다). 선택의 주인은 한 번에 하나이고, 끌기가 시작되면 끌기의 것이다.
    ///
    /// `copyEnter`를 부르지 않는다. 그 함수가 하는 일은 커서를 셸 커서 자리에
    /// 두는 것뿐이고 여기서는 곧바로 덮어쓴다.
    pub fn copyEnterAt(self: *Screen, x: u16, y: u16) !void {
        if (self.copy_cursor != null) self.copyExit();
        self.copy_cursor = self.copyClamp(x, y) orelse return;
        try self.copySelect(.char);
    }

    /// 포인터가 선택 끝을 `(x, y)`로 옮긴다(PD design 결정 6). 화면 밖이면
    /// 가장자리 칸으로 붙인다. copy mode가 아니면 아무 일도 안 한다.
    ///
    /// 칸이 같아도 다시 맞춘다. 끄는 중의 휠이 뷰포트를 밀면 같은 뷰포트
    /// 칸이 다른 글자이고(design 결정 7), 그때 선택 끝이 따라가야 한다. 같은
    /// 칸으로 여러 번 부르지 않는 것은 `pointer.Gesture`가 한다.
    ///
    /// 끝이 `copyMove`와 같은 모양이다 — 지금 선택의 start가 곧 앵커다(design
    /// 결정 5). 그래서 끌어 만든 선택에서 `y`를 쳐도, 키보드로 만든 선택과
    /// 같은 문자열이 나온다(`vt_test` 검사 97).
    pub fn copyPointTo(self: *Screen, x: u16, y: u16) !void {
        if (self.copy_cursor == null) return;
        self.copy_cursor = self.copyClamp(x, y) orelse return;
        if (self.copy_kind == null) return;
        const sel = self.term.screens.active.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 뷰포트 좌표를 화면 안으로 붙인다. 화면 크기가 아직 0이면 null이다.
    /// 격자 크기를 `pages`에서 읽는 이유는 `copyMove`의 주석에 있다.
    fn copyClamp(self: *Screen, x: u16, y: u16) ?Cursor {
        const pages = &self.term.screens.active.pages;
        if (pages.cols == 0 or pages.rows == 0) return null;
        return .{
            .x = @min(x, @as(u16, @intCast(pages.cols - 1))),
            .y = @min(y, @as(u16, @intCast(pages.rows - 1))),
        };
    }

    /// copy mode를 나간다. 선택도 함께 지운다 — 안 지우면 모드를 나간 뒤에도
```

`vt_test.zig`는 Edit 하나다. 검사 97~101이고 화면을 셋 새로 만든다(`pd_kb` · `pd_pt` · `pd_sc`). 이 파일은 `main()`
하나라 모든 지역 변수가 서로 부딪친다(lessons "핵심 파일") — 새 이름은 전부 `pd_` 접두다. 기존 파일에 `pd_`로
시작하는 이름이 없는 것을 `rg`로 확인했다.

`old_string`(기준 파일 2604줄부터):

```zig
    std.debug.print("PASS\n", .{});
```

`new_string`:

```zig
    // ── PD-M2: 포인터의 선택 ─────────────────────────────────────────────
    //
    // 검사 97. `copyEnterAt` · `copyPointTo`가 키보드의 `copySelect` ·
    // `copyMove`와 같은 선택 문자열을 낸다(PD design "검증"). 화면 둘을 같은
    // 글자로 채우고 한쪽은 키보드로, 한쪽은 포인터로 같은 두 칸을 고른다.
    // 두 줄에 걸친 선택이라 줄바꿈이 든 문자열을 비교한다 — (6, 0)의 `w`에서
    // (5, 1)의 `d`까지가 `world\nsecond`다.
    const pd_kb = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pd_kb.deinit();
    const pd_pt = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pd_pt.deinit();
    pd_kb.feed("hello world\r\nsecond line\r\n");
    pd_pt.feed("hello world\r\nsecond line\r\n");
    _ = try pd_kb.cells(&buf);
    _ = try pd_pt.cells(&buf);
    // 키보드는 셸 커서(row 2, col 0)에서 출발한다.
    pd_kb.copyEnter();
    try pd_kb.copyMove(0, -1);
    try pd_kb.copyMove(0, -1);
    var pd_step: usize = 0;
    while (pd_step < 6) : (pd_step += 1) try pd_kb.copyMove(1, 0);
    try pd_kb.copySelect(.char);
    try pd_kb.copyMove(0, 1);
    try pd_kb.copyMove(-1, 0);
    const pd_kb_text = (try pd_kb.copyYank()) orelse return error.NothingYanked;
    try pd_pt.copyEnterAt(6, 0);
    const pd_at = pd_pt.copyCursor() orelse return error.NoCopyCursor;
    if (pd_at.x != 6 or pd_at.y != 0) {
        std.debug.print("FAIL: copyEnterAt(6, 0) put the copy cursor at {d},{d}\n", .{ pd_at.x, pd_at.y });
        return error.WrongCopyCursor;
    }
    try pd_pt.copyPointTo(5, 1);
    const pd_pt_text = (try pd_pt.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, pd_kb_text, "world\nsecond") or !std.mem.eql(u8, pd_pt_text, pd_kb_text)) {
        std.debug.print("FAIL: the keyboard yanked '{s}', the pointer yanked '{s}' (both should be 'world\\nsecond')\n", .{ pd_kb_text, pd_pt_text });
        return error.PointerSelectionDiffers;
    }
    if (pd_pt.copyActive()) {
        std.debug.print("FAIL: y after a pointer selection did not leave copy mode\n", .{});
        return error.YankDidNotLeave;
    }
    std.debug.print("vt_test: 포인터로 고른 선택이 키보드로 고른 것과 같은 글자를 준다 OK\n", .{});

    // 검사 98. 거꾸로 끌어도 같다 — 앵커가 오른쪽, 끝이 왼쪽(검사 6과 같은 성질).
    try pd_pt.copyEnterAt(4, 0);
    try pd_pt.copyPointTo(0, 0);
    const pd_back = (try pd_pt.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, pd_back, "hello")) {
        std.debug.print("FAIL: a backward pointer selection yanked '{s}' (expected 'hello')\n", .{pd_back});
        return error.BackwardSelectionWrong;
    }
    std.debug.print("vt_test: 거꾸로 끈 포인터 선택도 같은 글자를 준다 OK\n", .{});

    // 검사 99. 키보드 copy mode에서 `v`를 눌러 둔 채 끌기가 시작돼도 선택이 산다.
    // `copyEnterAt`이 먼저 모드를 나가지 않으면 `copySelect(.char)`가 같은
    // 방식을 다시 누른 것이 되어 선택을 푼다(design 결정 6의 "선택의 주인은
    // 한 번에 하나").
    pd_pt.copyEnter();
    try pd_pt.copySelect(.char);
    try pd_pt.copyEnterAt(0, 1);
    try pd_pt.copyPointTo(5, 1);
    const pd_over = (try pd_pt.copyYank()) orelse {
        std.debug.print("FAIL: a drag that started inside keyboard copy mode (v on) left no selection\n", .{});
        return error.SelectionToggledOff;
    };
    if (!std.mem.eql(u8, pd_over, "second")) {
        std.debug.print("FAIL: the drag over keyboard copy mode yanked '{s}' (expected 'second')\n", .{pd_over});
        return error.WrongClipText;
    }
    std.debug.print("vt_test: 키보드 copy mode 위에서 시작한 끌기가 선택을 새로 잡는다 OK\n", .{});

    // 검사 100. 화면 밖 좌표는 가장자리 칸으로 붙는다. 20칸 화면에 99를 주면
    // 19다. 줄 끝 공백은 트림되므로 문자열은 `second line`이다.
    try pd_pt.copyEnterAt(0, 1);
    try pd_pt.copyPointTo(99, 1);
    const pd_edge = pd_pt.copyCursor() orelse return error.NoCopyCursor;
    if (pd_edge.x != 19 or pd_edge.y != 1) {
        std.debug.print("FAIL: copyPointTo(99, 1) put the copy cursor at {d},{d} (expected 19,1)\n", .{ pd_edge.x, pd_edge.y });
        return error.WrongCopyCursor;
    }
    const pd_wide = (try pd_pt.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, pd_wide, "second line")) {
        std.debug.print("FAIL: a selection to the clamped edge yanked '{s}' (expected 'second line')\n", .{pd_wide});
        return error.WrongClipText;
    }
    std.debug.print("vt_test: 화면 밖 좌표는 가장자리 칸으로 붙는다 OK\n", .{});

    // 검사 101. 끄는 중의 휠(design 결정 7). 앵커를 잡은 뒤 뷰포트를 세 줄
    // 올리고 같은 뷰포트 칸으로 끝을 다시 맞추면, 끝은 세 줄 위의 글자다.
    // 앵커는 tracked selection이라 글자에 붙어 있다(CM 결정 5).
    //
    // 같은 칸으로 두 번 부르는 것이 요점이다. 휠 앞의 `copyPointTo(0, 3)`과
    // 뒤의 그것은 좌표가 같다 — "칸이 같으면 아무것도 안 한다"로 만들면 끝이
    // 앵커에 남아 `A` 한 글자가 나온다.
    const pd_sc = try vt.Screen.init(init.io, init.gpa, 20, 5, CELL);
    defer pd_sc.deinit();
    var pd_line: [16]u8 = undefined;
    var pd_n: usize = 1;
    while (pd_n <= 30) : (pd_n += 1) {
        pd_sc.feed(std.fmt.bufPrint(&pd_line, "A{d:0>2}\r\n", .{pd_n}) catch unreachable);
    }
    _ = try pd_sc.cells(&buf);
    // 바닥의 뷰포트는 A27 · A28 · A29 · A30 · 빈 줄(셸 커서)이다. row 3이 A30이다.
    try pd_sc.copyEnterAt(0, 3);
    try pd_sc.copyPointTo(0, 3);
    pd_sc.scrollByRows(-3);
    try pd_sc.copyPointTo(0, 3);
    const pd_long = (try pd_sc.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, pd_long, "A27\nA28\nA29\nA")) {
        std.debug.print("FAIL: the selection after a wheel yanked '{s}' (expected 'A27\\nA28\\nA29\\nA')\n", .{pd_long});
        return error.WheelSelectionWrong;
    }
    std.debug.print("vt_test: 끄는 중의 휠이 선택 끝을 세 줄 위 글자로 다시 맞춘다 OK\n", .{});

    std.debug.print("PASS\n", .{});
```

`input.zig`는 Edit 하나다. `preedit()` 바로 앞에 `pointerMode`를 넣는다(확정 7).

`old_string`(기준 파일 965줄부터):

```zig
    /// 지금 조합 중인 글자. 없으면 null.
```

`new_string`:

```zig
    /// 포인터가 모드를 바꾼다(PD design 결정 6). 조합 중인 한글은 normal이었으면
    /// 확정해 돌려주고(호출부가 옛 포커스의 PTY에 쓴다), find였으면 버린다
    /// (`Esc`와 같은 뜻 — 검색 프롬프트의 조합은 검색어지 셸 입력이 아니다).
    /// 그리고 `mode`를 `to`로 둔다.
    ///
    /// 왜 이것이 필요한가. 입력 모드는 두 곳에 있다 — 여기의 `mode`(키를 어떻게
    /// 해석하나)와 `vt.Screen.copy_cursor`(화면이 모드인가). 키보드 경로는 둘을
    /// 같은 키에서 함께 바꾼다. 포인터 경로가 화면 쪽만 바꾸면, 끌어서 copy
    /// mode에 들어간 뒤 친 `j`가 셸로 가고 복사한 뒤 친 글자가 copy 표에
    /// 삼켜진다(PD design 결정 6).
    ///
    /// copy였으면 버린다. copy mode에 들어가는 키가 이미 확정했으므로 조합이
    /// 남아 있을 수 없지만, 남아 있다면 그것은 셸에 갈 글자가 아니다.
    ///
    /// 돌려주는 슬라이스는 `commit_buf`를 가리킨다. 다음 키가 덮어쓰므로
    /// 호출부가 바로 쓴다 — `takeCommit`과 같은 계약이다.
    pub fn pointerMode(self: *State, to: Mode) []const u8 {
        switch (self.mode) {
            .normal => self.commitHangul(),
            .copy, .find => self.hangul_buf = .{},
        }
        self.mode = to;
        return self.takeCommit();
    }

    /// 지금 조합 중인 글자. 없으면 null.
```

`input_test.zig`는 Edit 하나다. 검사 64~67이고 새 이름은 전부 `pk_` 접두다.

`old_string`(기준 파일 1740줄부터):

```zig
    std.debug.print("PASS\n", .{});
```

`new_string`:

```zig
    // ── PD-M2: 포인터가 모드를 바꾼다 ────────────────────────────────────
    //
    // 검사 64. normal에서 조합 중이면 확정해 돌려준다 — 호출부가 옛 포커스의
    // PTY에 쓴다(PD design 결정 6 · WP 결정 4). 모드도 바뀐다. 확정분은 한 번만
    // 나온다 — 돌려준 뒤 `takeCommit`은 비었다.
    {
        var pk_n: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expectHangul(&pk_n, K.KEY_G, "", 'ㅎ');
        try expectHangul(&pk_n, K.KEY_K, "", '하');
        const pk_out = pk_n.pointerMode(.copy);
        if (!std.mem.eql(u8, pk_out, "하")) {
            std.debug.print("FAIL: pointerMode from normal returned \"{s}\", want \"하\"\n", .{pk_out});
            return error.PointerModeCommit;
        }
        if (pk_n.mode != .copy or pk_n.preedit() != null) {
            std.debug.print("FAIL: after pointerMode(.copy) mode={s} preedit={?d}\n", .{ @tagName(pk_n.mode), pk_n.preedit() });
            return error.PointerModeState;
        }
        try expectCommit(&pk_n, 0, "");
        // 검사 66의 앞 절반. 이제 키는 copy 표로 간다 — 끌어서 들어간 뒤 친
        // `j`가 셸로 새지 않는다.
        try expectCopy(&pk_n, K.KEY_J, .down);
        const pk_back = pk_n.pointerMode(.normal);
        if (pk_back.len != 0 or pk_n.mode != .normal) {
            std.debug.print("FAIL: pointerMode(.normal) from copy returned {d} byte(s), mode={s}\n", .{ pk_back.len, @tagName(pk_n.mode) });
            return error.PointerModeState;
        }
        // 검사 66의 뒤 절반. 복사한 뒤 친 글자는 셸로 간다. 한글이 켜져 있으니
        // 자모가 조합으로 간다 — copy 표에 삼켜지지 않았다는 것이 요점이다.
        try expectHangul(&pk_n, K.KEY_J, "", 'ㅓ');
    }
    std.debug.print("input_test: 포인터가 normal에서 조합을 확정해 돌려주고 모드를 옮긴다 OK\n", .{});

    // 검사 65. find에서는 조합을 버린다 — 검색 프롬프트의 조합은 검색어지 셸
    // 입력이 아니다(`Esc`와 같은 뜻). 한/영은 그대로다 — 포인터는 조합만
    // 끝내고 입력기 상태를 안 바꾼다.
    {
        var pk_f: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        pk_f.mode = .find;
        try expectHangul(&pk_f, K.KEY_G, "", 'ㅎ');
        try expectHangul(&pk_f, K.KEY_K, "", '하');
        const pk_drop = pk_f.pointerMode(.normal);
        if (pk_drop.len != 0) {
            std.debug.print("FAIL: pointerMode from find returned \"{s}\"; the composing syllable belongs to the needle, not the shell\n", .{pk_drop});
            return error.PointerModeLeak;
        }
        if (pk_f.mode != .normal or pk_f.preedit() != null or !pk_f.hangul_on) {
            std.debug.print("FAIL: after pointerMode from find mode={s} preedit={?d} hangul_on={}\n", .{ @tagName(pk_f.mode), pk_f.preedit(), pk_f.hangul_on });
            return error.PointerModeState;
        }
        try expectCommit(&pk_f, 0, "");
    }
    std.debug.print("input_test: 포인터가 find에서는 조합을 버린다 OK\n", .{});

    // 검사 67. 키보드 fd로 온 `BTN_LEFT`는 아무것도 안 만든다(PD design 결정 2).
    // 키보드와 마우스를 한 노드로 내는 장치는 init이 키보드로 열고 terminal이
    // 마우스로 또 연다. `BTN_*`도 `EV_KEY`라 `handleKey`에 닿는데, 키맵 밖의
    // 코드라 바이트도 모드 변화도 없다(PD-M0 plan이 이 검사를 M2로 미뤘다).
    //
    // 조합 중이면 확정한다. 방향키 · PageUp 같은 키맵 밖의 키와 같은 갈래다
    // (HI 결정 6) — 같은 누름이 포인터 경로에서도 확정을 부르므로(`cancel`)
    // 결과가 어긋나지 않는다.
    {
        var pk_b: input.State = .{};
        try expect(&pk_b, K.BTN_LEFT, 1, "");
        try expect(&pk_b, K.BTN_LEFT, 0, "");
        try expect(&pk_b, K.BTN_RIGHT, 1, "");
        try expect(&pk_b, K.BTN_RIGHT, 0, "");
        try expectCommit(&pk_b, K.BTN_LEFT, "");
        if (pk_b.mode != .normal) return error.ModeLeft;

        var pk_bh: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expectHangul(&pk_bh, K.KEY_G, "", 'ㅎ');
        try expectHangul(&pk_bh, K.KEY_K, "", '하');
        try expect(&pk_bh, K.BTN_LEFT, 1, "");
        try expectCommit(&pk_bh, K.BTN_LEFT, "하");
        try expectPreedit(&pk_bh, K.BTN_LEFT, null);
    }
    std.debug.print("input_test: 키보드 fd로 온 BTN_LEFT는 아무것도 안 만든다 OK\n", .{});

    std.debug.print("PASS\n", .{});
```

확인.

```bash
for f in vt vt_test input input_test; do
  diff terminal/src/$f.zig /tmp/run/pdm2/term/src/$f.zig && echo "$f SAME"
done
git diff --stat terminal/src/vt.zig terminal/src/vt_test.zig terminal/src/input.zig terminal/src/input_test.zig
```

기대: `SAME` 넷, `4 files changed, 265 insertions(+)`. 지운 줄이 없다.

## Task 4: `terminal/src/main.zig` — 편집 여섯

순서대로 넣는다. 줄 번호는 기준 파일에서 잰 참고값이고, 앞의 편집이 줄을 늘리므로 뒤로 갈수록 밀린다.

### 4-1. 전이를 담는 칸(E1 · E2)

`PointerRound` 앞에 `PointerEdge` · `MAX_EDGES`, 안에 `edges` · `edge_count`(확정 4).

E1 — `old_string`(기준 파일 1463줄부터):

```zig
/// 한 poll 회차의 포인터 이벤트 요약. 회차가 끝나면 `at` 줄 하나가 된다.
```

`new_string`:

```zig
/// 한 회차의 왼쪽 버튼 전이 하나(PD-M2). 그 순간의 포인터 자리와 함께 든다 —
/// 회차가 끝난 뒤의 자리 하나로는 "누르고 끌고 뗐다"의 순서를 되살릴 수 없다.
const PointerEdge = struct { down: bool, x: u32, y: u32 };

/// 한 회차에 담는 전이의 수. 사람의 손으로는 한 회차(밀리초 단위)에 둘을
/// 넘기 어렵다. 넘치면 뒤를 버린다 — 뗌을 잃어도 다음 누름이 제스처를 새로
/// 잡는다(`Gesture.press`).
const MAX_EDGES = 8;

/// 한 poll 회차의 포인터 이벤트 요약. 회차가 끝나면 `at` 줄 하나가 된다.
```

E2 — `old_string`(기준 파일 1469줄부터):

```zig
    woke: bool = false,
```

`new_string`:

```zig
    woke: bool = false,
    /// 왼쪽 버튼의 눌림 · 뗌(PD-M2). 회차 안의 순서대로, 그 순간의 자리와 함께.
    edges: [MAX_EDGES]PointerEdge = undefined,
    edge_count: usize = 0,
```

### 4-2. 드레인이 왼쪽 버튼의 전이를 담는다(E3)

E3 — `old_string`(기준 파일 1667줄부터):

```zig
            if (e.moved or e.pressed.bits() != 0) round.woke = true;
```

`new_string`:

```zig
            if (e.moved or e.pressed.bits() != 0) round.woke = true;
            // 왼쪽 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
            // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
            if ((e.pressed.left or e.released.left) and round.edge_count < MAX_EDGES) {
                round.edges[round.edge_count] = .{ .down = e.pressed.left, .x = state.x, .y = state.y };
                round.edge_count += 1;
            }
```

### 4-3. `gridCellClamped`와 `PointerWire`(E4)

`closePointer` 뒤 · `main` 앞이다. 읽을 자리 넷. `target`의 셈(확정 2), `motion`이 누른 잎의 사각형으로 자르는 줄
(mutation 4의 자리), `wheel`이 제스처의 null 뒤에 PD-M1의 휠을 그대로 하는 것, `run`의 switch에 `else`가 없는 것과
`cancel`이 바뀐 것이 있을 때만 `redraw`를 켜는 것(확정 3).

E4 — `old_string`(기준 파일 1679줄부터):

```zig
    devs[slot] = null;
}
```

`new_string`:

```zig
    devs[slot] = null;
}

/// 픽셀을 격자 칸으로 바꾸되, 격자 밖이면 가장 가까운 가장자리 칸으로
/// 붙인다(PD-M2). 끄는 중에는 포인터가 여백 위에 있어도 선택 끝이 있어야
/// 한다. `gridCell`과 같은 상수 넷을 쓴다 — 다른 상수를 쓰면 화살표 끝과
/// 선택 끝이 한 칸 어긋난다(design 결정 5).
fn gridCellClamped(x: u32, y: u32, cols: u16, rows: u16) GridCell {
    const col: u32 = if (x < GRID_X) 0 else @min((x - GRID_X) / CELL_W, @as(u32, cols) - 1);
    const row: u32 = if (y < GRID_Y) 0 else @min((y - GRID_Y) / ROW_HEIGHT, @as(u32, rows) - 1);
    return .{ .col = @intCast(col), .row = @intCast(row) };
}

/// 포인터의 누름 · 끎 · 뗌 · 휠을 패널과 copy mode에 잇는다(PD-M2).
///
/// 판단은 `pointer.Gesture`가 하고(순수), 여기는 픽셀을 칸으로 바꿔 넘기고
/// 돌아온 의도를 실행한다(design 결정 3). 회차마다 새로 짓는다 — 필드가
/// `main`의 변수를 가리키므로 회차를 넘는 상태가 여기 없다.
const PointerWire = struct {
    gesture: *pointer.Gesture,
    /// 누른 패널의 워크스페이스 번호. 누름이 쓰고 `target`이 읽는다.
    gesture_ws: *usize,
    ws: *Workspace,
    current: usize,
    key_state: *input.State,
    whole: layout.Rect,
    cols: u16,
    rows: u16,
    /// 의도가 화면을 바꿨다. 부르는 쪽이 `needs_redraw`로 옮긴다.
    redraw: bool = false,

    /// 누른 패널이 지금 어떤 상태인가(`pointer.Target`). 누른 뒤 키보드가
    /// 포커스나 워크스페이스를 옮겼거나 그 패널이 닫혔으면 `gone`이다.
    ///
    /// 키보드 copy mode는 포커스 패널에만 있다(copy 표가 `Cmd+]`를 삼킨다).
    /// 그래서 "누른 패널이 포커스인가"와 "그 패널이 copy mode인가" 둘이면
    /// 키보드와 포인터가 섞이는 경우(design 결정 6의 표)가 다 갈린다.
    fn target(self: *const PointerWire) pointer.Target {
        const leaf = self.gesture.held() orelse return .gone;
        if (self.gesture_ws.* != self.current or self.ws.focus != leaf) return .gone;
        const p = self.ws.panes[leaf] orelse return .gone;
        return if (p.screen.copyActive()) .copy else .normal;
    }

    /// 왼쪽 버튼이 눌렸다. `pointer> press` 줄을 찍는다 — 패널 칸이면 그
    /// 잎과 상대 칸이고, 여백 · 구분선 · 상태 줄이면 `none`이다.
    fn press(self: *PointerWire, x: u32, y: u32) !void {
        const hit: ?pointer.Cell = cell: {
            const gc = gridCell(x, y, self.cols, self.rows) orelse break :cell null;
            const h = self.ws.tree.hit(self.whole, gc.col, gc.row) orelse break :cell null;
            break :cell .{ .leaf = h.leaf, .col = h.col, .row = h.row };
        };
        if (hit) |h| {
            std.debug.print("terminal: pointer> press leaf={d} row={d} col={d}\n", .{ h.leaf, h.row, h.col });
        } else {
            std.debug.print("terminal: pointer> press none\n", .{});
        }
        self.gesture_ws.* = self.current;
        try self.run(self.gesture.press(hit, self.ws.focus));
    }

    /// 포인터가 움직였다. 버튼이 패널 칸 위에서 눌린 채일 때만 일이 있다.
    ///
    /// 끄는 칸은 누른 패널의 사각형으로 자른다(design 결정 5). 이웃 패널이나
    /// 여백 위로 끌어도 선택 끝은 누른 패널의 가장자리 칸이다.
    fn motion(self: *PointerWire, x: u32, y: u32) !void {
        const leaf = self.gesture.held() orelse return;
        const t = self.target();
        // 누른 패널이 포커스를 잃었으면 칸을 셀 사각형이 없을 수 있다(지금
        // 트리에 그 잎이 없다). `Gesture`는 `gone`이면 칸을 안 본다.
        if (t == .gone) return self.run(self.gesture.motion(self.gesture.start, t));
        var rs: [layout.MAX_LEAVES]layout.Rect = undefined;
        self.ws.tree.rects(self.whole, &rs);
        const gc = gridCellClamped(x, y, self.cols, self.rows);
        const h = layout.clampInto(rs[leaf], leaf, gc.col, gc.row);
        try self.run(self.gesture.motion(.{ .leaf = h.leaf, .col = h.col, .row = h.row }, t));
    }

    /// 왼쪽 버튼을 뗐다. `pointer> release drag=` 줄을 찍는다 — 1이면 끈
    /// 뒤의 뗌이다. 복사했는지는 뒤따르는 `clip>` 줄이 말한다.
    fn release(self: *PointerWire) !void {
        const dragged = self.gesture.phase == .dragging;
        std.debug.print("terminal: pointer> release drag={d}\n", .{@intFromBool(dragged)});
        try self.run(self.gesture.release(self.target()));
    }

    /// 휠(PD design 결정 7). 버튼이 패널 위에서 눌린 채면 제스처의 것이다 —
    /// 누른 패널을 움직이고 선택 끝을 다시 맞춘다. 아니면 PD-M1의 휠이다.
    ///
    /// PD-M1의 휠. 포인터 아래 패널이 움직이고 포커스는 안 바뀐다. 여백 ·
    /// 구분선 위면 아무 일도 없다. 키보드 copy mode인 패널도 무시한다 — copy
    /// 커서는 뷰포트 좌표라 밖에서 뷰포트를 밀면 커서가 다른 글자를 가리키는데
    /// 선택은 안 따라온다. 양수가 휠을 앞으로 민 것이고 위로 간다.
    fn wheel(self: *PointerWire, notches: i32, x: u32, y: u32) !void {
        if (self.gesture.wheel(notches, self.target())) |its| return self.run(its);
        const cell = gridCell(x, y, self.cols, self.rows) orelse return;
        const h = self.ws.tree.hit(self.whole, cell.col, cell.row) orelse return;
        const p = &self.ws.panes[h.leaf].?;
        if (p.screen.copyActive()) return;
        p.screen.scrollByRows(-WHEEL_ROWS * @as(isize, notches));
        self.redraw = true;
    }

    /// 의도를 차례로 실행한다. switch에 `else`가 없다 — `pointer.Intent`에
    /// variant가 늘면 여기서 컴파일이 멈춘다(design 결정 3).
    ///
    /// 화면이 바뀐 의도만 `redraw`를 켠다. 아무것도 안 바꾼 클릭이 프레임을
    /// 그리면 클릭마다 `screen>` 등 덤프가 찍힌다.
    ///
    /// `select_start` · `select_to` · `scroll` · `copy`의 잎은 언제나 포커스
    /// 패널이다. `Gesture`는 `target`이 `gone`이 아닐 때만 그것들을 내고,
    /// `gone`이 아니라는 것은 누른 잎이 지금 포커스이고 그 패널이 있다는 뜻이다.
    fn run(self: *PointerWire, intents: pointer.Intents) !void {
        for (intents.items()) |it| {
            switch (it) {
                // 옛 포커스 패널을 정리한다. 확정된 한글을 그 PTY에 먼저 쓰고,
                // 그 패널의 copy mode와 검색 프롬프트를 복사 없이 닫는다
                // (`copyExit`이 `findCancel`까지 한다). 이 의도가 `focus`보다
                // 먼저 온다 — 확정 → 포커스 이동 → 선택이 design 결정 6의
                // 순서다.
                .cancel => {
                    const fp = &self.ws.panes[self.ws.focus].?;
                    const composing = self.key_state.preedit() != null;
                    const bytes = self.key_state.pointerMode(.normal);
                    if (bytes.len > 0) pty.write(fp.session.master_fd, bytes);
                    if (composing) {
                        fp.screen.setPreedit(null);
                        dumpHangul(self.key_state);
                        self.redraw = true;
                    }
                    if (fp.screen.copyActive()) {
                        fp.screen.copyExit();
                        dumpCopy(fp.screen, "exit");
                        self.redraw = true;
                    }
                },
                // 포커스만 옮긴다. `pane>` 줄은 이 프레임의 덤프가 찍는다.
                .focus => |leaf| {
                    self.ws.focus = leaf;
                    self.redraw = true;
                },
                // 처음으로 다른 칸에 닿았다. 입력 모드와 화면 모드를 함께
                // 옮긴다(design 결정 6). 누른 뒤 첫 이동 전에 친 한글이 조합
                // 중일 수 있고, 그 글자는 이 패널의 셸로 간다 — 누름이 포커스를
                // 이미 이리로 옮겼다.
                .select_start => |at| {
                    const p = &self.ws.panes[at.leaf].?;
                    const composing = self.key_state.preedit() != null;
                    const bytes = self.key_state.pointerMode(.copy);
                    if (bytes.len > 0) pty.write(p.session.master_fd, bytes);
                    if (composing) {
                        p.screen.setPreedit(null);
                        dumpHangul(self.key_state);
                    }
                    try p.screen.copyEnterAt(at.col, at.row);
                    dumpCopy(p.screen, "enter");
                    self.redraw = true;
                },
                .select_to => |at| {
                    const p = &self.ws.panes[at.leaf].?;
                    try p.screen.copyPointTo(at.col, at.row);
                    dumpCopy(p.screen, "point");
                    self.redraw = true;
                },
                .scroll => |s| {
                    self.ws.panes[s.leaf].?.screen.scrollByRows(-WHEEL_ROWS * @as(isize, s.notches));
                    self.redraw = true;
                },
                // 뗌 = 복사(design 결정 6). 키보드의 `y`와 같은 줄 둘이 같은
                // 순서로 찍힌다 — `clip>` 다음 `copy> yank`. 그리고 입력 모드를
                // normal로 되돌린다. 안 되돌리면 복사한 뒤 친 글자가 copy 표에
                // 삼켜진다(pointer/check.sh 검사 18).
                .copy => |leaf| {
                    const p = &self.ws.panes[leaf].?;
                    dumpClip(try p.screen.copyYank());
                    dumpCopy(p.screen, "yank");
                    _ = self.key_state.pointerMode(.normal);
                    self.redraw = true;
                },
            }
        }
    }
};
```

### 4-4. 변수 둘(E5)

E5 — `old_string`(기준 파일 1936줄부터):

```zig
    var pointer_shown = false;
```

`new_string`:

```zig
    var pointer_shown = false;
    // 누름 · 끎 · 뗌의 상태(PD-M2, design 결정 6)와, 누른 패널이 있던
    // 워크스페이스 번호. 누른 채 키보드가 워크스페이스를 바꾸면 `PointerWire`가
    // 이 번호로 알아채고 제스처를 버린다.
    var gesture: pointer.Gesture = .{};
    var gesture_ws: usize = 0;
```

### 4-5. 포인터 분기(E6)

PD-M1의 휠 블록(주석 여섯 줄과 `if (round.wheel != 0) wheel: { … }`)이 `PointerWire`를 짓고 돌리는 블록으로 바뀐다. PD-M1의
휠은 `PointerWire.wheel`의 뒷부분으로 옮겨 갔다 — 같은 다섯 줄이고 `break :wheel`이 `return`이 됐다.

E6 — `old_string`(기준 파일 2289줄부터):

```zig
        // 휠(PD design 결정 7). 포인터 아래 패널이 움직이고 포커스는 안 바뀐다.
        // 여백 · 구분선 위면 아무 일도 없다. 키보드 copy mode인 패널도 무시한다 —
        // copy 커서는 뷰포트 좌표라 밖에서 뷰포트를 밀면 커서가 다른 글자를
        // 가리키는데 선택은 안 따라온다.
        //
        // 양수가 휠을 앞으로 민 것이고 위로 간다. 뷰포트가 바뀌었으므로 화면
        // 전체를 다시 그린다(`scroll>` 줄도 그 프레임에 찍힌다).
        if (round.wheel != 0) wheel: {
            const cell = gridCell(pointer_state.x, pointer_state.y, cols, rows) orelse break :wheel;
            const h = ws.tree.hit(whole, cell.col, cell.row) orelse break :wheel;
            const p = &ws.panes[h.leaf].?;
            if (p.screen.copyActive()) break :wheel;
            p.screen.scrollByRows(-WHEEL_ROWS * @as(isize, round.wheel));
            needs_redraw = true;
```

`new_string`:

```zig
        // 누름 · 끎 · 뗌 · 휠(PD-M2). 판단은 `pointer.Gesture`, 실행은
        // `PointerWire`다(design 결정 3).
        //
        // 왼쪽 버튼의 전이를 회차 안의 순서대로 먼저 돈다. 전이마다 그 순간의
        // 자리로 움직임을 먼저 주고 그다음 누름이나 뗌을 준다 — 끌다가 뗀 보고
        // 하나는 마지막 칸까지 선택을 늘린 뒤에 복사해야 한다. 그다음 회차
        // 끝의 자리로 움직임 한 번, 마지막이 휠이다.
        //
        // 휠이 맨 뒤라 한 회차 안의 누름 · 휠 · 뗌의 순서는 안 남는다. 사람의
        // 손으로 한 회차(밀리초 단위)에 그 셋이 함께 오는 일은 드물다.
        //
        // 뷰포트가 바뀌었거나 선택이 바뀌었으면 화면 전체를 다시 그린다
        // (`scroll>` · `copy>` 줄도 그 프레임 앞뒤에 찍힌다).
        {
            var wire: PointerWire = .{
                .gesture = &gesture,
                .gesture_ws = &gesture_ws,
                .ws = ws,
                .current = current,
                .key_state = &key_state,
                .whole = whole,
                .cols = cols,
                .rows = rows,
            };
            for (round.edges[0..round.edge_count]) |e| {
                try wire.motion(e.x, e.y);
                if (e.down) try wire.press(e.x, e.y) else try wire.release();
            }
            if (round.woke) try wire.motion(pointer_state.x, pointer_state.y);
            if (round.wheel != 0) try wire.wheel(round.wheel, pointer_state.x, pointer_state.y);
            if (wire.redraw) needs_redraw = true;
```

### 4-6. 확인

```bash
diff terminal/src/main.zig /tmp/run/pdm2/term/src/main.zig && echo MAIN-SAME
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | rg '^-[^-]'
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build > /tmp/b.out 2>&1; echo "build=$?"; grep -a -E "error" -A3 /tmp/b.out | head -20
  zig build test > /tmp/t.out 2>&1; echo "test=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  grep -a -c "^layout_test: hit .* OK$" /tmp/t.out
  grep -a -c "^vt_test: .* OK" /tmp/t.out
  grep -a -c "^input_test: .* OK$" /tmp/t.out
  grep -a -E "all checks passed|^PASS$|^FAIL" /tmp/t.out'
```

기대.

- `MAIN-SAME`, `1 file changed, 234 insertions(+), 13 deletions(-)`.
- `rg '^-[^-]'`: 아래 열세 줄이다. PD-M1의 휠 블록이 통째로 `PointerWire` 블록으로 바뀐다. 휠 블록 주석의 빈 줄(`//`)과
  닫는 `}`는 git이 새 블록의 같은 줄과 짝지어 `-`로 안 보인다.

  ```
  -        // 휠(PD design 결정 7). 포인터 아래 패널이 움직이고 포커스는 안 바뀐다.
  -        // 여백 · 구분선 위면 아무 일도 없다. 키보드 copy mode인 패널도 무시한다 —
  -        // copy 커서는 뷰포트 좌표라 밖에서 뷰포트를 밀면 커서가 다른 글자를
  -        // 가리키는데 선택은 안 따라온다.
  -        // 양수가 휠을 앞으로 민 것이고 위로 간다. 뷰포트가 바뀌었으므로 화면
  -        // 전체를 다시 그린다(`scroll>` 줄도 그 프레임에 찍힌다).
  -        if (round.wheel != 0) wheel: {
  -            const cell = gridCell(pointer_state.x, pointer_state.y, cols, rows) orelse break :wheel;
  -            const h = ws.tree.hit(whole, cell.col, cell.row) orelse break :wheel;
  -            const p = &ws.panes[h.leaf].?;
  -            if (p.screen.copyActive()) break :wheel;
  -            p.screen.scrollByRows(-WHEEL_ROWS * @as(isize, round.wheel));
  -            needs_redraw = true;
  ```

- `build=0`, `test=0`, 그다음 넷이 `107` · `30` · `110` · `15`(확정 12). 늘어난 수는 `pointer_test` 검사 16~22의
  서른둘, `layout_test` 검사 13의 여덟, `vt_test` 검사 97~101의 다섯, `input_test` 검사 64~67의 셋이다. `all checks
  passed` 셋과 `PASS` 다섯, `FAIL` 0줄.

`build=0`이 아니면 그 에러 줄을 보고한다. 이 plan의 사본은 `build=0`이었으므로(확정 12) 에러는 편집이 빗나간 것이다 —
`diff`가 `MAIN-SAME`을 안 낸 자리부터 본다.

## Task 5: `pointer/check.sh` · `check.sh`

### 5-1. `pointer/check.sh` — 편집 일곱

M0 · M1 부분은 한 줄도 안 바뀐다. 지우는 줄은 셋(머리 주석의 milestone 표기, 판정 도구 주석의 `scroll>` 줄, PASS
줄)이고 나머지는 더하기다.

편집 1~3 — 머리 주석.

`old_string`(기준 파일 6줄부터):

```bash
# PD 체인 — 포인터 장치(PD-M0 · M1). 열아홉번째 체인.
```

`new_string`:

```bash
# PD 체인 — 포인터 장치(PD-M0~M2). 열아홉번째 체인.
```

`old_string`(기준 파일 19줄부터):

```bash
#   → 키를 치면 숨고, 휠은 포인터 아래 패널을 세 줄씩 움직인다(PD-M1)
```

`new_string`:

```bash
#   → 키를 치면 숨고, 휠은 포인터 아래 패널을 세 줄씩 움직인다(PD-M1)
#   → 다른 패널을 누르면 포커스가 그리로 간다. 여백 · 구분선은 아무 일도 없다(PD-M2)
#   → 글자 위를 누르고 끌면 copy mode의 선택이 늘어나고, 떼면 클립보드에
#     들어간다. 입력 모드도 함께 돌아와 그다음 친 글자가 셸에 간다(PD-M2)
```

`old_string`(기준 파일 33줄부터):

```bash
#   scroll> 줄 — 휠이 움직인 뷰포트(검사 11 · 12).
```

`new_string`:

```bash
#   scroll> 줄 — 휠이 움직인 뷰포트(검사 11 · 12 · 16의 둘째).
#   press · release 줄과 copy> · clip> · pane> 줄 — 누름이 어느 잎의 어느 칸에
#                닿았는지, 선택이 어디서 어디까지인지, 클립보드에 무엇이
#                들어갔는지, 포커스가 어디인지(검사 13~18). copy> · clip>은
#                키보드의 copy mode가 찍는 것과 같은 줄이라 copy 체인의 수법을
#                그대로 쓴다.
```

편집 4 — `report_failure`의 표식 넷.

`old_string`(기준 파일 125줄부터):

```bash
    "terminal: copy> enter" \
```

`new_string`:

```bash
    "terminal: copy> enter" \
    "terminal: pointer> press" \
    "terminal: pointer> release" \
    "terminal: clip> len=" \
    "terminal: pane> ws=1/1 panes=2" \
```

편집 5 — PD-M2의 도구. `hmp` 바로 앞이다. 도구가 쓰는 `last_at` · `wait_for_at` · `wait_for_count` · `hmp`는 bash가
부를 때 찾으므로 정의 순서가 상관없다.

`old_string`(기준 파일 245줄부터):

```bash

# HMP 명령 하나. 키와 달리 로그가 자라기를 기다리지 않는다 — 결과는 부르는
```

`new_string`:

```bash

# ── PD-M2의 도구 ──────────────────────────────────────────────────────

# 마지막 press · release 줄.
last_press() {
  grep -a 'terminal: pointer> press ' "$LOG" | tail -n 1 | tr -d '\r'
}

last_release() {
  grep -a 'terminal: pointer> release ' "$LOG" | tail -n 1 | tr -d '\r'
}

# copy> 줄 중 동사가 맞는 것의 개수(`enter` · `point` · `exit` · `yank`).
copy_lines() {
  grep -ac "terminal: copy> $1" "$LOG" || true
}

# 클립보드에 넣은 횟수와 마지막 줄. 붙여넣기 줄(`clip> paste`)은 안 센다.
clip_lines() {
  grep -ac 'terminal: clip> len=' "$LOG" || true
}

last_clip() {
  grep -a 'terminal: clip> len=' "$LOG" | tail -n 1 | tr -d '\r'
}

# 12바이트 붙여넣기의 횟수(검사 15의 둘째). 클립보드는 pd-drag-word다.
paste_lines() {
  grep -ac 'terminal: clip> paste len=12 ' "$LOG" || true
}

# 마지막 배치 줄과 그 개수(pane/check.sh의 last_pane_line과 같다).
last_pane_line() {
  grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r'
}

pane_lines() {
  grep -ac 'terminal: pane> ws=' "$LOG" || true
}

# 마지막 배치 줄이 패턴(ERE)에 맞을 때까지 기다린다. 15초.
wait_for_pane() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(last_pane_line)"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 마지막 상태 줄의 글자(copy/check.sh의 status_text와 같다).
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'
}

# 상태 줄 꼬리가 `  COPY`가 될 때까지(인자 on) 또는 아닐 때까지(off) 기다린다.
wait_for_status_copy() {
  local want="$1" i text
  for i in $(seq 1 150); do
    text="$(status_text)"
    case "$text" in
      *"  COPY") [ "$want" = on ] && return 0 ;;
      *) [ "$want" = off ] && return 0 ;;
    esac
    sleep 0.1
  done
  return 1
}

# 마지막 프레임(마지막 screen>부터 끝까지, copy/check.sh의 last_frame과 같다).
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 screen> 줄에서 글자가 정확히 $1인 행의 번호(0부터). 여럿이면 가장
# 아래 것, 없으면 -1이다. screen>은 포커스 패널의 행을 ' | '로 잇고(main.zig의
# dumpScreen) 행이 바뀔 때마다 구분자가 하나씩 붙으므로 구간의 번호가 곧 행
# 번호다. 행은 패널 안의 상대 행이다 — 세로 분할의 두 패널은 격자의 0행에서
# 시작하므로 격자의 행과 같다.
screen_row() {
  grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' |
    WANT="$1" perl -ne 's/^.*?terminal: screen> //; chomp; my @r = split / \| /, $_, -1;
      my $i = -1; for my $k (0 .. $#r) { $i = $k if $r[$k] eq $ENV{WANT} } print "$i\n";'
}

# 포인터를 (X, Y)로 옮긴다. 마지막 at 줄의 자리에서 상대 이동을 100 이하씩
# 나눠 보내고 그 자리의 at 줄을 기다린다. 버튼을 누른 채 부르면 그것이 곧
# 끌기다 — 나눈 이동마다 선택 끝이 따라온다.
move_to() {
  local tx="$1" ty="$2" line cx cy dx dy sx sy
  line="$(last_at)"
  cx="$(sed -E 's/.* x=([0-9]+) .*/\1/' <<<"$line")"
  cy="$(sed -E 's/.* y=([0-9]+) .*/\1/' <<<"$line")"
  dx=$((tx - cx))
  dy=$((ty - cy))
  while [ "$dx" -ne 0 ] || [ "$dy" -ne 0 ]; do
    sx=$dx; [ "$sx" -gt 100 ] && sx=100; [ "$sx" -lt -100 ] && sx=-100
    sy=$dy; [ "$sy" -gt 100 ] && sy=100; [ "$sy" -lt -100 ] && sy=-100
    hmp "mouse_move $sx $sy"
    dx=$((dx - sx))
    dy=$((dy - sy))
  done
  wait_for_at "^terminal: pointer> at x=${tx} y=${ty} "
}

# 왼쪽 버튼을 누른다 · 뗀다. 그 줄(press · release)이 하나 늘 때까지 기다린다.
#
# 누름의 일(포커스 옮김 · copy mode 닫기)은 그 줄을 찍은 회차 안에서 끝나고,
# 화면이 바뀌었으면 같은 회차 끝에 프레임(pane> 등)이 찍힌다. 그래서 뗌의 줄이
# 보이면 누름 회차의 프레임은 이미 로그에 있다.
button_down() {
  local n
  n="$(pointer_count 'press ')"
  hmp "mouse_button 1"
  wait_for_count pointer_count 'press ' "$((n + 1))"
}

button_up() {
  local n
  n="$(pointer_count 'release ')"
  hmp "mouse_button 0"
  wait_for_count pointer_count 'release ' "$((n + 1))"
}

# 격자 칸의 왼쪽 위 끝 픽셀(PD design 결정 5). 격자는 (20, 20)에서 시작하고
# 칸은 8 × 16이다(main.zig의 GRID_X · GRID_Y · CELL_W · ROW_HEIGHT). 오른쪽 아래
# 끝 픽셀은 여기에 7 · 15를 더한다.
cell_x() { echo $((20 + 8 * $1)); }
cell_y() { echo $((20 + 16 * $1)); }

# HMP 명령 하나. 키와 달리 로그가 자라기를 기다리지 않는다 — 결과는 부르는
```

편집 6 — 검사 본문. PD-M1의 검사 12 뒤, "검사 9의 둘째"(부팅 마우스를 뺀다) 앞이다(확정 10).

`old_string`(기준 파일 582줄부터):

```bash
# ── 검사 9의 둘째: 마지막 장치가 빠지면 숨는다 ────────────────────────
```

`new_string`:

```bash
# ── PD-M2: 누름 · 끎 · 뗌 ──────────────────────────────────────────────
#
# 패널을 둘로 가르고 시작한다. 0 | 1이고 왼쪽은 0,0 77x47, 구분선이 77열,
# 오른쪽은 78,0 77x47이다(WP). 칸의 픽셀은 cell_x · cell_y로 셈한다 — 77열은
# x 636~643, 76열은 628~635, 78열은 644~651이다. 행 10은 y 180~195다.
#
# 포커스는 새 패널(1)에 있다. 검사 14를 먼저 하는 이유는 mutation 1이다 — hit이
# 구분선 칸을 왼쪽 잎에 넣으면 포커스가 0으로 간다. 포커스가 이미 0이면 그
# 고장이 안 보인다.
echo "=== Cmd+D: two panes for the click checks ==="
type_keys meta_l-d
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "Cmd+D did not give 'panes=2 focus=1 rect=78,0 77x47' (last pane> line: '$(last_pane_line)')"
CLIPS_BEFORE="$(clip_lines)"
ENTERS_BEFORE="$(copy_lines enter)"

# ── 검사 14: 구분선 칸을 누르면 아무 일도 없다 ────────────────────────
#
# 구분선 칸은 어느 잎의 사각형에도 안 든다(layout.Tree.hit의 null). 칸의 왼쪽
# 위 끝 픽셀과 오른쪽 아래 끝 픽셀을 둘 다 누른다 — 픽셀 → 칸 변환이 한 칸
# 어긋나면 한쪽 끝이 이웃 패널의 칸이 된다(PD design 결정 5). 포커스도
# 안 바뀌고 pane> 줄도 안 는다.
echo "=== a press on the separator does nothing ==="
PANES_N="$(pane_lines)"
for spot in "$(cell_x 77) $(cell_y 10)" "$(( $(cell_x 77) + 7 )) $(( $(cell_y 10) + 15 ))"; do
  read -r SX SY <<<"$spot"
  move_to "$SX" "$SY" ||
    report_failure "the pointer did not reach ${SX},${SY} (last at: '$(last_at)')"
  button_down || report_failure "mouse_button 1 at ${SX},${SY} printed no 'pointer> press' line"
  [ "$(last_press)" = "terminal: pointer> press none" ] ||
    report_failure "a press on the separator pixel ${SX},${SY} printed '$(last_press)', expected 'pointer> press none'"
  button_up || report_failure "mouse_button 0 at ${SX},${SY} printed no 'pointer> release' line"
  [ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
    report_failure "the release on the separator printed '$(last_release)', expected 'release drag=0'"
done
[ "$(pane_lines)" -eq "$PANES_N" ] ||
  report_failure "a press on the separator changed the panes (pane> ${PANES_N} -> $(pane_lines) lines, last: '$(last_pane_line)')"
echo "separator: two presses, $(last_pane_line)"

# ── 검사 13: 다른 패널을 누르면 포커스가 그리로 간다 ───────────────────
#
# 왼쪽 패널의 마지막 열(76) 칸의 오른쪽 아래 끝 픽셀(635, 195), 그다음 오른쪽
# 패널의 첫 열(78) 칸의 왼쪽 위 끝 픽셀(644, 180). 구분선을 사이에 둔 두 픽셀이
# 서로 다른 잎의 경계 칸이 된다. 클릭이라 클립보드도 copy mode도 안 움직인다.
echo "=== a press on another pane moves the focus there ==="
move_to "$(( $(cell_x 76) + 7 ))" "$(( $(cell_y 10) + 15 ))" ||
  report_failure "the pointer did not reach the left pane's last cell (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the left pane printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=10 col=76" ] ||
  report_failure "a press on pixel 635,195 printed '$(last_press)', expected 'press leaf=0 row=10 col=76'"
button_up || report_failure "mouse_button 0 on the left pane printed no 'pointer> release' line"
[ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
  report_failure "the click on the left pane released as '$(last_release)', expected 'release drag=0'"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "a click on the left pane did not move the focus (last pane> line: '$(last_pane_line)')"
echo "focus left: $(last_pane_line)"

move_to "$(cell_x 78)" "$(cell_y 10)" ||
  report_failure "the pointer did not reach the right pane's first cell (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the right pane printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=1 row=10 col=0" ] ||
  report_failure "a press on pixel 644,180 printed '$(last_press)', expected 'press leaf=1 row=10 col=0'"
button_up || report_failure "mouse_button 0 on the right pane printed no 'pointer> release' line"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "a click on the right pane did not move the focus back (last pane> line: '$(last_pane_line)')"
[ "$(clip_lines)" -eq "$CLIPS_BEFORE" ] ||
  report_failure "a click put something on the clipboard: '$(last_clip)'"
[ "$(copy_lines enter)" -eq "$ENTERS_BEFORE" ] ||
  report_failure "a click entered copy mode (copy> enter ${ENTERS_BEFORE} -> $(copy_lines enter))"
echo "focus right: $(last_pane_line)"

# ── 검사 15: 글자 위를 누르고 끌어 떼면 그 글자가 클립보드에 들어간다 ──
#
# 오른쪽 패널(포커스)에 pd-drag-word를 찍고 그 줄의 0열을 누른다. 누름에서는
# copy mode에 안 들어간다(design 결정 6). 0.5초를 기다려 copy> enter가 안 는
# 것을 본다 — 누름의 일은 press 줄과 같은 회차에 끝나므로 그 사이에 찍혔다면
# 이미 로그에 있다.
#
# 11열(d) 칸의 오른쪽 아래 끝 픽셀로 한 번에 끈다. 첫 칸 이동에 들어가므로
# copy> enter(누른 칸)와 copy> point(지금 칸)가 함께 찍히고, 상태 줄 꼬리에
# COPY가 뜬다. 떼면 clip> 줄이 키보드의 y와 같은 모양으로 찍힌다.
#
# 판정은 clip> 줄이라 화면 에코와 상관없다(project_gate_screen_echo).
echo "=== press, drag, release copies the word ==="
type_keys e c h o spc p d minus d r a g minus w o r d ret
wait_for_screen '\| pd-drag-word \|' ||
  report_failure "the right pane's shell did not print pd-drag-word"
ROW="$(screen_row pd-drag-word)"
[ "$ROW" -ge 0 ] ||
  report_failure "pd-drag-word is not a row of its own on the last screen: $(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
PX="$(cell_x 78)"
PY="$(cell_y "$ROW")"
move_to "$PX" "$PY" ||
  report_failure "the pointer did not reach the p of pd-drag-word at ${PX},${PY} (last at: '$(last_at)')"
ENTERS="$(copy_lines enter)"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on pd-drag-word printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=1 row=${ROW} col=0" ] ||
  report_failure "the press on pd-drag-word printed '$(last_press)', expected 'press leaf=1 row=${ROW} col=0'"
sleep 0.5
[ "$(copy_lines enter)" -eq "$ENTERS" ] ||
  report_failure "the press alone entered copy mode; it must wait for the first move to another cell"
hmp "mouse_move 95 15"
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "dragging to the next cells did not enter copy mode (no new 'copy> enter')"
wait_for_log "terminal: copy> point row=${ROW} col=11" ||
  report_failure "the drag did not move the selection end to row ${ROW} col 11 (last copy> line: '$(grep -a 'terminal: copy>' "$LOG" | tail -n 1 | tr -d '\r')')"
[ "$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')" = "terminal: copy> enter row=${ROW} col=0" ] ||
  report_failure "the drag entered copy mode at '$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')', expected the pressed cell row=${ROW} col=0"
wait_for_status_copy on ||
  report_failure "while dragging the status line reads '$(status_text)', expected it to end with '  COPY'"
button_up || report_failure "mouse_button 0 after the drag printed no 'pointer> release' line"
[ "$(last_release)" = "terminal: pointer> release drag=1" ] ||
  report_failure "the release after the drag printed '$(last_release)', expected 'release drag=1'"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release after the drag put nothing on the clipboard (no new 'clip> len=' line)"
[ "$(last_clip)" = "terminal: clip> len=12 text=pd-drag-word" ] ||
  report_failure "the drag copied '$(last_clip)', expected 'clip> len=12 text=pd-drag-word'"
wait_for_status_copy off ||
  report_failure "after the release the status line still reads '$(status_text)'; the release leaves copy mode"
echo "dragged: $(last_clip)"

# ── 검사 18: 끌어 복사한 직후 친 글자가 셸에 간다 ──────────────────────
#
# 모드의 두 사본(input.State.mode와 vt.Screen.copy_cursor)이 함께 돌아왔다는
# 것이다. 화면 쪽만 돌아오면 입력 모드가 copy에 남아 이 글자들이 copy 표에
# 삼켜진다(mutation 3). 출력 줄만 보는 패턴이라 친 명령줄과 안 겹친다.
echo "=== typing right after a drag copy reaches the shell ==="
type_keys e c h o spc p d minus a f t e r minus d r a g ret
wait_for_screen '\| pd-after-drag \|' ||
  report_failure "the keys typed right after the drag copy never reached the shell (no 'pd-after-drag' output line); the input mode must come back to normal with the screen"
echo "typed after the drag: pd-after-drag"

# ── 검사 15의 둘째: 끌어 넣은 클립보드를 Cmd+V로 붙인다 ────────────────
#
# 클립보드가 셸까지 왕복한다. 붙일 자리 앞에 got-을 쳐 두므로 출력 줄은
# got-pd-drag-word 하나뿐이다 — 명령줄(echo got-pd-drag-word)과 안 겹친다.
echo "=== Cmd+V pastes what the drag copied ==="
PASTES="$(paste_lines)"
type_keys e c h o spc g o t minus
type_keys meta_l-v
wait_for_count paste_lines '' "$((PASTES + 1))" ||
  report_failure "Cmd+V did not write the 12-byte clipboard (no new 'clip> paste len=12' line)"
type_keys ret
wait_for_screen '\| got-pd-drag-word \|' ||
  report_failure "the pasted word never ran in the shell (no 'got-pd-drag-word' output line)"
echo "pasted: got-pd-drag-word"

# ── 검사 17: 키보드 copy mode 중 클릭은 복사 없이 모드를 닫는다 ─────────
#
# 선택의 주인은 한 번에 하나다(design 결정 6의 표). 누름이 그 패널의 copy
# mode를 닫고(copy> exit) 입력 모드를 normal로 되돌린다 — 그다음 친 글자가
# 셸에 온다. 클립보드는 그대로다.
#
# 둘째는 검색 프롬프트가 열린 채다. copyExit이 findCancel까지 하므로 프롬프트도
# 닫히고, 입력 모드가 find에서 normal로 온다. 안 오면 친 글자가 검색어로 간다.
echo "=== a click in keyboard copy mode leaves it without copying ==="
CLIPS="$(clip_lines)"
ENTERS="$(copy_lines enter)"
EXITS="$(copy_lines exit)"
type_keys meta_l-shift-c
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "Cmd+Shift+C did not enter copy mode (no new 'copy> enter')"
button_down || report_failure "mouse_button 1 in keyboard copy mode printed no 'pointer> press' line"
wait_for_count copy_lines exit "$((EXITS + 1))" ||
  report_failure "a click on a pane in keyboard copy mode did not leave copy mode (no new 'copy> exit')"
button_up || report_failure "mouse_button 0 in keyboard copy mode printed no 'pointer> release' line"
[ "$(clip_lines)" -eq "$CLIPS" ] ||
  report_failure "a click that left keyboard copy mode copied '$(last_clip)'; it must close the mode without copying"
type_keys e c h o spc p d minus c l i c k minus o u t ret
wait_for_screen '\| pd-click-out \|' ||
  report_failure "after the click left copy mode the typed keys never reached the shell (no 'pd-click-out' output line)"
echo "copy mode click: closed without copying, typing reaches the shell"

echo "=== a click with the find prompt open closes the prompt and the mode ==="
ENTERS="$(copy_lines enter)"
EXITS="$(copy_lines exit)"
type_keys meta_l-shift-c
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "Cmd+Shift+C did not enter copy mode the second time"
type_keys slash
wait_for_log 'terminal: find> open' ||
  report_failure "/ did not open the find prompt (no 'find> open')"
type_keys q
wait_for_log 'terminal: find> type needle=q len=1' ||
  report_failure "q did not reach the find prompt (no 'find> type needle=q len=1')"
button_down || report_failure "mouse_button 1 with the find prompt open printed no 'pointer> press' line"
wait_for_count copy_lines exit "$((EXITS + 1))" ||
  report_failure "a click with the find prompt open did not leave copy mode (no new 'copy> exit')"
button_up || report_failure "mouse_button 0 with the find prompt open printed no 'pointer> release' line"
type_keys e c h o spc p d minus f i n d minus o u t ret
wait_for_screen '\| pd-find-out \|' ||
  report_failure "after the click closed the find prompt the typed keys never reached the shell (no 'pd-find-out' output line); the input mode stayed in find"
[ "$(last_frame | grep -ac 'terminal: find> overlay' || true)" -eq 0 ] ||
  report_failure "the find prompt is still drawn after the click: $(last_frame | grep -a 'terminal: find> overlay' | tr -d '\r')"
echo "find prompt click: closed, typing reaches the shell"

# ── 검사 16: 이웃 패널 위까지 끌어도 누른 패널의 마지막 열에서 멈춘다 ──
#
# 왼쪽 패널로 포커스를 옮기고 seq -s , 40을 친다. 출력은 110자라 77칸에서
# 접히고, 첫 줄이 정확히 1,2,…,28,29(77자)다 — 그 줄의 마지막 글자가 76열이다.
# 그 줄의 0열을 누르고 오른쪽 패널(x 720 = 87열) 위까지 끈다. 끄는 칸이 누른
# 패널로 잘리면 선택 끝이 76열이라 77자가 다 들어간다. 안 잘리면(mutation 4)
# 오른쪽 패널의 상대 칸(9열)이 왼쪽 패널에 적용돼 1,2,3,4,5, 열 자만 들어간다.
#
# 줄 끝 공백 트림 때문에 줄이 짧으면 76열에서 끝났는지가 안 보인다. 그래서
# 마지막 열까지 글자가 찬 줄을 쓴다.
echo "=== dragging over the neighbor pane stops at the pressed pane's last column ==="
move_to "$(cell_x 40)" "$(cell_y 20)" ||
  report_failure "the pointer did not reach the left pane (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the left pane printed no 'pointer> press' line"
button_up || report_failure "mouse_button 0 on the left pane printed no 'pointer> release' line"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "a click on the left pane did not move the focus (last pane> line: '$(last_pane_line)')"
LONG="$(seq -s , 29)"
type_keys s e q spc minus s spc comma spc 4 0 ret
wait_for_screen "\\| ${LONG} \\|" ||
  report_failure "seq -s , 40 did not fold into a 77-column row '${LONG}'"
ROW="$(screen_row "$LONG")"
[ "$ROW" -ge 0 ] || report_failure "the 77-column row is not on the last screen"
PY="$(cell_y "$ROW")"
move_to "$(cell_x 0)" "$PY" ||
  report_failure "the pointer did not reach the start of the long row (last at: '$(last_at)')"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on the long row printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the press on the long row printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
move_to 720 "$PY" ||
  report_failure "the drag did not reach x=720 over the right pane (last at: '$(last_at)')"
wait_for_log "terminal: copy> point row=${ROW} col=76" ||
  report_failure "over the right pane the selection end is '$(grep -a 'terminal: copy> point' "$LOG" | tail -n 1 | tr -d '\r')', expected row=${ROW} col=76 (the pressed pane's last column)"
button_up || report_failure "mouse_button 0 over the right pane printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release over the right pane put nothing on the clipboard"
[ "$(last_clip)" = "terminal: clip> len=77 text=${LONG}" ] ||
  report_failure "dragging over the neighbor copied '$(last_clip)', expected the whole 77-column row (len=77 text=${LONG})"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 ' ||
  report_failure "dragging over the right pane moved the focus (last pane> line: '$(last_pane_line)')"
echo "clamped drag: $(last_clip)"

# ── 검사 16의 둘째: 누른 채 굴린 휠은 누른 패널을 움직이고 선택 끝을 맞춘다 ──
#
# design 결정 7의 "끄는 중" 행. seq 120 160을 찍고 150의 0열을 누른 채(끌지
# 않고) 휠을 앞으로 한 눈금 민다. 선택이 먼저 시작되고(앵커가 150에 붙는다)
# 그다음 뷰포트가 세 줄 올라가며, 선택 끝은 같은 뷰포트 칸 — 이제 147 — 으로
# 다시 맞춰진다. 떼면 147부터 150의 첫 글자까지 열세 바이트다.
#
# 순서가 뒤집히면(스크롤 뒤에 선택 시작) 앵커가 147에 붙어 한 글자짜리
# 선택이 된다. 그것은 pointer_test 검사 22가 부팅 전에 잡는다.
echo "=== a wheel notch while pressed scrolls the pressed pane and moves the end ==="
type_keys s e q spc 1 2 0 spc 1 6 0 ret
wait_for_screen '\| 160 \| root@\(none\) ~#' ||
  report_failure "seq 120 160 did not finish (no '| 160 | root@(none) ~#' on the screen)"
ROW="$(screen_row 150)"
[ "$ROW" -ge 3 ] || report_failure "150 is not on the last screen with three rows above it (row ${ROW})"
move_to "$(cell_x 0)" "$(cell_y "$ROW")" ||
  report_failure "the pointer did not reach 150 (last at: '$(last_at)')"
OFF_A="$(scroll_field offset)"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on 150 printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the press on 150 printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch while pressed printed no at line"
OFF_B="$(scroll_field offset)"
[ "$OFF_B" -eq "$((OFF_A - 3))" ] ||
  report_failure "a wheel notch while pressed moved the pressed pane from offset ${OFF_A} to ${OFF_B}, expected $((OFF_A - 3))"
[ "$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')" = "terminal: copy> enter row=${ROW} col=0" ] ||
  report_failure "the wheel while pressed did not start the selection at the pressed cell (last copy> enter: '$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')')"
button_up || report_failure "mouse_button 0 after the wheel printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release after the wheel put nothing on the clipboard"
[ "$(last_clip)" = "terminal: clip> len=13 text=147" ] ||
  report_failure "the wheel drag copied '$(last_clip)', expected 'clip> len=13 text=147' (147 to the first byte of 150)"
echo "wheel while pressed: offset ${OFF_A} -> ${OFF_B}, $(last_clip)"

# 마지막 검사(부팅 마우스를 뺀다)는 M1의 자리(679, 0)를 본다. 그리로 되돌린다.
# 움직이면 화살표가 다시 보이므로, 뺄 때 숨는 at 줄이 찍힌다.
move_to 679 0 ||
  report_failure "the pointer did not get back to 679,0 (last at: '$(last_at)')"

# ── 검사 9의 둘째: 마지막 장치가 빠지면 숨는다 ────────────────────────
```

편집 7 — PASS 줄.

`old_string`(기준 파일 605줄부터):

```bash
echo "PD-M1 check PASS"
```

`new_string`:

```bash
echo "PD-M2 check PASS"
```

### 5-2. `check.sh` — 문단과 `CHAINS`

`old_string`(기준 파일 323줄부터):

```bash
# 포인터를 따라오고 휠이 패널을 움직인다. 판정은 terminal의 pointer> · scroll>
# 줄과 screendump 넷(perl로 화살표 색을 센다)이다. 회차당 부팅 1회.
```

`new_string`:

```bash
# 포인터를 따라오고 휠이 패널을 움직인다. PD-M2부터 누르면 포커스가 옮겨 가고,
# 끌어 고른 글자가 뗄 때 클립보드에 들어간다. 판정은 terminal의 pointer> ·
# scroll> · copy> · clip> · pane> 줄과 screendump 넷(perl로 화살표 색을 센다)이다.
# 회차당 부팅 1회.
```

`old_string`(기준 파일 347줄부터):

```bash
  "PD-M1:./pointer/check.sh"
```

`new_string`:

```bash
  "PD-M2:./pointer/check.sh"
```

### 5-3. 확인

```bash
bash -n pointer/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pointer/check.sh && require_no_early_exit_pipe ./pointer/check.sh &&
  require_explicit_nic ./pointer/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
ls -l pointer/check.sh | cut -c1-10
diff pointer/check.sh /tmp/run/pdm2/pointer/check.sh && echo SAME
git diff --stat pointer/check.sh check.sh
python3 /tmp/run/pdm2/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK`, 권한 `-rwxr-xr-x`, `SAME`, `2 files changed, 432 insertions(+), 6
deletions(-)`, `post: 25 edits, 0 bad`. `check.sh`는 `SAME`으로 안 본다 — 앵커 검사가 판정이다.

## Task 6: 체인 한 번과 regression 셋

체인은 하나씩 돈다. 넷이 같은 `kernel/initrd.cpio`를 다시 만들고, Docker VM의 메모리가 4GB라 겹치면 죽는다. 커널은
PD-M1 뒤 그대로라 `kernel/build.sh`는 빌드 없이 지난다.

### 6-1. `pointer` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm2:/tmp/run/pdm2 -w /workspace tars-devcontainer bash -c '
    bash pointer/check.sh > /tmp/run/pdm2/impl/pointer.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^===|^FAIL|^separator|^focus |^dragged|^typed after|^pasted|^copy mode click|^find prompt click|^clamped drag|^wheel while pressed|took about|PD-M2 check' /tmp/run/pdm2/impl/pointer.log
rg -a 'terminal: (pointer> (press|release)|clip> len=|copy> (enter|point|exit|yank))' /tmp/run/pdm2/impl/pointer.log | tail -40
```

기대: `exit=0`. 첫 `rg`는 PD-M1의 줄(PD-M1 plan Task 6-1) 뒤에 아래 줄들이 이어지고 `PD-M2 check PASS`로 끝난다(확정
12의 두 판이 찍은 그대로). `offset` 값과 `sep ink=`의 값은 그 회차의 것이고 판정은 그 수끼리의 관계만 본다. 둘째 `rg`는
비어 있다 — 체인의 출력 파일에는 시리얼 로그가 없고(`$LOG`는 `mktemp`), 체인이 끝에 찍는 `pointer> lines:` 목록에
`press` · `release` 줄만 나온다. 그 목록의 M2 부분은 확정 12의 판에서 이랬다.

```
terminal: pointer> press none
terminal: pointer> release drag=0
terminal: pointer> press none
terminal: pointer> release drag=0
terminal: pointer> press leaf=0 row=10 col=76
terminal: pointer> release drag=0
terminal: pointer> press leaf=1 row=10 col=0
terminal: pointer> release drag=0
terminal: pointer> press leaf=1 row=1 col=0
terminal: pointer> release drag=1
terminal: pointer> press leaf=1 row=1 col=11
terminal: pointer> release drag=0
terminal: pointer> press leaf=1 row=1 col=11
terminal: pointer> release drag=0
terminal: pointer> press leaf=0 row=20 col=40
terminal: pointer> release drag=0
terminal: pointer> press leaf=0 row=44 col=0
terminal: pointer> release drag=1
terminal: pointer> press leaf=0 row=35 col=0
terminal: pointer> release drag=1
```

그 앞의 `press leaf=0 row=27 col=85` · `release drag=0`은 PD-M1의 검사 3(700, 455에서 누르고 뗀다)이 이제 찍는 줄이다.

```
=== Cmd+D: two panes for the click checks ===
=== a press on the separator does nothing ===
separator: two presses, terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 sep ink=6016
=== a press on another pane moves the focus there ===
focus left: terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 sep ink=5923
focus right: terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 sep ink=6016
=== press, drag, release copies the word ===
dragged: terminal: clip> len=12 text=pd-drag-word
=== typing right after a drag copy reaches the shell ===
typed after the drag: pd-after-drag
=== Cmd+V pastes what the drag copied ===
pasted: got-pd-drag-word
=== a click in keyboard copy mode leaves it without copying ===
copy mode click: closed without copying, typing reaches the shell
=== a click with the find prompt open closes the prompt and the mode ===
find prompt click: closed, typing reaches the shell
=== dragging over the neighbor pane stops at the pressed pane's last column ===
clamped drag: terminal: clip> len=77 text=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29
=== a wheel notch while pressed scrolls the pressed pane and moves the end ===
wheel while pressed: offset 202 -> 199, terminal: clip> len=13 text=147
=== the last mouse goes away ===
gone: terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=0 ink=0
PD-M2 check PASS
```

`sep ink=`의 값은 화살표가 구분선 위에 있었는지에 따라 달라지므로 판정에 안 쓴다.

### 6-2. regression — `render` · `copy` · `pane`

세 체인에는 포인터 장치가 없다. 제스처는 한 번도 안 깨어나고, 이 plan이 고친 `vt.zig` · `input.zig`의 공개 함수는
포인터 경로에서만 불린다. `copy`는 키보드 copy mode 전체를, `pane`은 포커스 · 분할을, `render`는 픽셀 판정을 본다.

```bash
for ch in render copy pane; do
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm2:/tmp/run/pdm2 -w /workspace tars-devcontainer bash -c "
      bash $ch/check.sh > /tmp/run/pdm2/impl/$ch.log 2>&1; echo exit=\$?" ; } 2>&1 | tail -4
  rg -a 'check PASS|^TR-M2 PASS|^FAIL' /tmp/run/pdm2/impl/$ch.log | cut -c1-60
  rg -a -c 'terminal: pointer> (open|at|press) ' /tmp/run/pdm2/impl/$ch.log || echo "pointer open/at/press: 0"
done
```

기대: 셋 다 `exit=0`. PASS 줄이 `TR-M2 PASS: colors reach the framebuffer, …`(앞 60자) · `CM-M2 check PASS` · `WP-M2 check
PASS`이고, 셋 다 `pointer open/at/press: 0`이다. 시간은 PD-M1에서 약 1분 47초 · 2분 50초 · 31초였다.

## Task 7: mutation 넷

확정 11의 표다. 사본은 `/tmp/run/pdm2/impl/mut/`에 만든다. 돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 —
`sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

### 7-0. 사본을 만든다

```bash
M=/tmp/run/pdm2/impl/mut; mkdir -p $M
cp terminal/src/layout.zig $M/layout_m1.zig
cp terminal/src/main.zig $M/main_m2.zig
cp terminal/src/main.zig $M/main_m3.zig
cp terminal/src/main.zig $M/main_m4.zig
cp pointer/check.sh $M/pointer_notest.sh
sd -F 'if (col < r.col or col >= r.col + r.cols) continue;' 'if (col < r.col or col > r.col + r.cols) continue;' $M/layout_m1.zig
sd -F 'dumpClip(try p.screen.copyYank());' 'if (self.cols == 0) dumpClip(try p.screen.copyYank());' $M/main_m2.zig
sd -F '_ = self.key_state.pointerMode(.normal);' 'if (self.cols == 0) _ = self.key_state.pointerMode(.normal);' $M/main_m3.zig
sd -F 'const h = layout.clampInto(rs[leaf], leaf, gc.col, gc.row);' 'const h = self.ws.tree.hit(self.whole, gc.col, gc.row) orelse layout.clampInto(rs[leaf], leaf, gc.col, gc.row);' $M/main_m4.zig
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' $M/pointer_notest.sh
chmod +x $M/pointer_notest.sh
bash -c 'M=/tmp/run/pdm2/impl/mut
for p in "layout.zig layout_m1.zig" "main.zig main_m2.zig" "main.zig main_m3.zig" "main.zig main_m4.zig"; do
  set -- $p; echo "== $2"; diff terminal/src/$1 $M/$2
done
echo "== pointer_notest.sh"; diff pointer/check.sh $M/pointer_notest.sh'
```

기대: 다섯 `diff`가 각각 한 줄의 차이다 — `layout.zig` 182줄, `main.zig` 1871 · 1873 · 1771줄, 체인 79줄.

### 7-1. mutation 1 — 먼저 `layout_test`

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm2/impl/mut/layout_m1.zig:/workspace/terminal/src/layout.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c '
  echo "mounted: $(grep -c "col > r.col + r.cols" src/layout.zig)"
  rm -rf .zig-cache zig-out
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -E "^FAIL|^error: [A-Z]" /tmp/t.out | head -3'
```

기대(확정 12에서 본 그대로): `mounted: 1`, `exit=1`, `FAIL: hit one leaf, past the right edge = .{ .leaf = 0, .col = 155,
.row = 0 }, want null`, `error: WrongHit`. 먼저 걸리는 것은 구분선 검사가 아니라 PD-M1의 "격자 오른쪽 끝 밖" 검사다 —
같은 부등호가 패널 하나일 때는 격자 밖 한 칸을 잎에 넣는다.

### 7-2. 체인 넷

mutation 1은 `zig build test`를 건너뛴 사본 체인으로, 2 · 3 · 4는 그대로의 체인으로 돌린다. `-e m=$m`으로 번호를
컨테이너에 넘긴다 — 작은따옴표 안의 `$m`은 컨테이너에서 빈 값이 된다(PE-M1 실측 5).

```bash
M=/tmp/run/pdm2/impl/mut
run_mut() {  # 번호, 덮을 -v 인자들
  local m="$1"; shift
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm2:/tmp/run/pdm2 "$@" -e m="$m" \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: layout=$(grep -c "col > r.col + r.cols" terminal/src/layout.zig) main=$(grep -c -E "self.cols == 0\) (dumpClip|_ = self.key_state)|orelse layout.clampInto" terminal/src/main.zig) notest=$(grep -c "^if false; then" pointer/check.sh)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash pointer/check.sh > /tmp/run/pdm2/impl/mut/m$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -a -n '^===|^FAIL' $M/m$m.log | tail -3
}
run_mut 1 -v $M/layout_m1.zig:/workspace/terminal/src/layout.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 2 -v $M/main_m2.zig:/workspace/terminal/src/main.zig:ro
run_mut 3 -v $M/main_m3.zig:/workspace/terminal/src/main.zig:ro
run_mut 4 -v $M/main_m4.zig:/workspace/terminal/src/main.zig:ro
```

함수 정의가 zsh에서 문제가 되면 `bash -c '…'`로 감싸 친다. Bash 도구의 10분 상한 때문에 `run_mut`을 한 번에 하나씩
부른다. 판을 겹치지 않는다. 로그에 `Killed`가 보이고 `FAIL: terminal build failed`로 끝나면 mutation의 결과가 아니라
메모리다. 다른 컨테이너가 없는지(`docker ps`) 보고 그 판만 다시 돌린다.

기대(확정 12에서 본 그대로. `R`은 그 회차의 행이고 판에서는 44였다).

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 구분선이 왼쪽 잎 | `layout=1 main=0 notest=1` | 검사 14의 첫 누름 | `FAIL: a press on the separator pixel 636,180 printed 'terminal: pointer> press leaf=0 row=10 col=77', expected 'pointer> press none'` |
| 2 `copyYank`를 안 부른다 | `layout=0 main=1 notest=0` | 검사 15의 뗌 뒤 | `FAIL: the release after the drag put nothing on the clipboard (no new 'clip> len=' line)` |
| 3 `pointerMode`를 안 부른다 | `layout=0 main=1 notest=0` | 검사 18 | `FAIL: the keys typed right after the drag copy never reached the shell (no 'pd-after-drag' output line); the input mode must come back to normal with the screen` |
| 4 자르지 않는다 | `layout=0 main=1 notest=0` | 검사 16의 끌기 | `FAIL: over the right pane the selection end is 'terminal: copy> point row=R col=9', expected row=R col=76 (the pressed pane's last column)` |

mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다
(`project_zig_out_staleness` — 캐시 삭제가 같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 7-3. 되돌린다

mutation 체인은 저장소의 `terminal/zig-out`과 `kernel/initrd.cpio`(둘 다 gitignore 대상)에 망가진 판을 남긴다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "exit=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  (cd kernel && ./make_initrd.sh > /tmp/i.out 2>&1); echo "initrd exit=$?"'
git status --short
```

기대: `exit=0`, `pointer_test` OK 줄 수(Task 4-6과 같다), `initrd exit=0`. `git status`는 `M` 열하나(`check.sh` ·
`pointer/check.sh` · `terminal/src/`의 아홉)와, plan이 아직 commit 전이면 `??` 하나뿐이다. 다른 것이 보이면(특히 `-v`로
없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 7-4. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력 넷.
- Task 1~5의 확인 출력(`SAME` · `--stat` · `anchors.py` · OK 줄 수 · `ENTRY-OK`).
- Task 6의 `exit=` · `real` · `rg` 출력.
- Task 7의 `diff` 다섯 · `mounted:` · `exit=` · `real` · `FAIL` 줄, 7-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 8: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고 Task 6의 로그를 대조한다.
2. 루트 게이트 2회, 열아홉 체인 × 2(`feedback_gate_runs`)이고 판정은 `PASS: 2/2` × 19다.
   반복 수를 2로 바꾼 commit은 `6f4dfb2`로 이미 들어갔다(확정 13). PD-M1 게이트(3회)가 약 1시간 10분이었으므로 2회는 약 50분으로
   본다 — 재지 않았고 게이트의 시간으로 본다. `pointer` 체인의 한 판은 M2에서 약 1분이다(확정 12). `run_in_background`로
   돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다(Docker VM 4GB).

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pd2.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pd2.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 2/2' /tmp/gate_pd2.log`가 19여야 하고 `PD-M2 check PASS`가 둘이어야 한다.
3. 실측 절 채우기.
4. commit. 넣는 것은 열한 파일과 이 plan이다. `git add`는 경로를 하나씩 지정한다.

## design과 다르게 적은 것

1. `Gesture`가 copy가 꺼진 것을 스스로 보지 않고, `main.zig`가 단계마다 `Target`(셋)으로 알려 준다(확정 2).
2. `cancel`이 페이로드 없이 지금 포커스 패널을 정리한다. 키보드 copy mode가 포커스 패널에만 있기 때문이다(확정 2 · 3).
   그래서 같은 패널을 클릭해도 조합 중인 한글이 확정된다(macOS의 터미널들도 클릭에 조합을 끝낸다). lead가 정했다(2026-10-05).
3. `copyEnterAt`이 이미 copy mode면 먼저 나가고, `copyEnter`를 안 부른다. `copyPointTo`는 칸이 같아도 다시 맞춘다. 둘 다
   좌표를 화면 안으로 붙인다(확정 6). lead가 정했다(2026-10-05).
4. 한 회차 안의 순서를 `PointerRound.edges`로 지킨다(확정 4). design은 회차 안의 순서를 말하지 않았다.
5. 누르기만 하고 아직 안 끈 채 굴린 휠도 "끄는 중의 휠"로 다룬다. 그때 선택을 먼저 시작한다(확정 8). lead가 정했다(2026-10-05).
6. 로그 줄 둘을 더했다 — `press none`과 `copy> point`(확정 9). lead가 정했다(2026-10-05).
7. `Cell`이 `pointer.zig`에 있고 `Hit`은 `layout.zig`에 그대로 있다(PD-M1 확정 6). `main.zig`가 옮겨 담는다.
8. 키보드 fd로 온 `BTN_LEFT`가 조합 중이면 확정한다(확정 7). design 결정 2는 "아무것도 안 만든다"였다. HI의 "표 밖의 키" 갈래와 일관되게 두기로 lead가 정했다(2026-10-05).
9. mutation 3을 뗌 쪽 `pointerMode` 한 자리로 좁혔다(확정 11).
10. 검사가 셋 늘었다 — 15의 둘째(`Cmd+V` 왕복을 따로 떼었다), 16의 둘째(누른 채 휠), 17의 둘째(검색 프롬프트).

## 이 milestone에서 안 하는 것

- 누름과 첫 칸 이동 사이에 PTY 출력이 오면 기억해 둔 칸이 다른 글자를 가리킨다(design 위험 2). 그대로 둔다. 누름
  회차에 `copy> enter`가 안 찍히고 첫 이동에 찍히는 것은 체인 검사 15가 본다.
- 가지치기가 copy mode를 닫을 때 `input.State.mode`가 copy에 남는다(design 위험 5). 끌어 만든 선택 중에 나면 제스처는
  `Target`이 `normal`이 되어 뗄 때까지 무시하고, 입력 모드는 copy에 남는다 — 사람은 `Esc`를 한 번 더 친다.
- 누른 채 장치를 뽑으면 뗌이 안 온다(`closePointer`의 `Pointer.forget`이 내는 뗌을 제스처에 안 넘긴다). 다음 누름이
  제스처를 새로 잡는다. 그 사이 다른 장치로 움직이면 선택이 계속 따라간다.
- 누른 채 키보드로 워크스페이스를 닫아 배열이 당겨지는 경우. `gesture_ws`가 번호라 우연히 같은 번호 · 같은 잎이 되면
  제스처가 다른 패널을 누른 것으로 여긴다. 누른 채 그 패널의 셸이 끝나야 생긴다.
- 끄는 동안 키를 치는 체인 검사. 호스트 검사(`input_test` 검사 64)만 본다(확정 11).
- 조합 중인 한글의 체인 검사. `input_test` 검사 64 · 65 · 67이 본다.
- 더블클릭 · 가장자리 자동 스크롤 · 뗀 뒤 반전 남기기 · 마우스 보고(design 비목표 1~3 · 5).
- 터치패드(PD-M3).
- `docs/guides/lessons.md` · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design `Status:`(design "닫을 때").

## PD-M2가 실측한 것

구현 전에 사본에서 잰 것은 확정 12에 있다. 구현은 Opus 서브에이전트가 2026-10-05에 plan 그대로 했다. `old_string` ·
`new_string` 25쌍을 plan 본문에서 뽑아 `anchors.json`과 바이트까지 대조한 뒤 Task 순서대로 넣었고(각 쌍이 정확히 한 번),
끝에 파일 열하나와 `check.sh`가 사본과 `SAME`이었다. lead가 같은 `cmp`를 다시 했고 전부 같았다. plan 코드를 고친 곳은 없다.

1. 호스트 검사. `pointer_test` OK 75 → 107, `layout_test` `hit` 22 → 30, `vt_test` 105 → 110, `input_test` 12 → 15.
   `zig build` · `zig build test` exit 0(44.5초).
2. `pointer` 체인 37.1초(캐시 따뜻). 새 판정 — 구분선 누름에 `focus=1` 그대로 · 왼쪽 패널 누름 `focus=0` · 끌어 뗌
   `clip> len=12 text=pd-drag-word` · 직후 친 글자 `pd-after-drag`가 셸에 · `Cmd+V` `got-pd-drag-word` · 키보드 copy mode
   클릭과 검색 프롬프트 클릭이 둘 다 복사 없이 닫히고 그 뒤 글자가 셸에 · 이웃 패널 위까지 끌어도 `clip> len=77`이 누른
   패널의 마지막 열에서 끝남 · 누른 채 휠 `offset 202 → 199`, `clip> len=13 text=147` · 마지막 마우스가 빠지면 `shown=0`.
   `press` · `release` 줄 스무 개가 plan의 목록과 글자까지 같았다.
3. regression — `render` 1분 48초 · `copy` 2분 50초 · `pane` 34초, 셋 다 PASS, `pointer>` 줄 0.
4. mutation 넷 전부 빨감, `Killed` 0번.

   | mutation | 잡은 자리 | 문구 | 시간 |
   |---|---|---|---|
   | 1 `hit`이 구분선 칸을 왼쪽 잎에 넣는다 | `layout_test` 먼저(`one leaf, past the right edge … want null`), 끄면 검사 14 | `a press on the separator pixel 636,180 printed 'pointer> press leaf=0 row=10 col=77', expected 'pointer> press none'` | 1분 30초 |
   | 2 뗌에서 `copyYank`를 안 부른다 | 검사 15 | `the release after the drag put nothing on the clipboard (no new 'clip> len=' line)` | 1분 50초 |
   | 3 뗌 뒤 `pointerMode`를 안 부른다 | 검사 18 | `the keys typed right after the drag copy never reached the shell (no 'pd-after-drag' output line)` | 2분 3초 |
   | 4 끄는 칸을 누른 패널로 clamp하지 않는다 | 검사 16 | `over the right pane the selection end is 'copy> point row=44 col=9', expected row=44 col=76` | 2분 0초 |

5. plan의 기대와 다른 것은 셋이고 전부 plan 문구였다 — `run_mut`의 `tail -5`가 `mounted:` 줄을 자른다(여섯 줄이라 `tail -6`) ·
   Task 6-1 첫 `rg` 패턴에 `^gone`이 없어 그 줄이 출력에 안 나온다(로그에는 있다) · 둘째 `rg`의 `clip> len=` 패턴에 앵커가
   없어 판정 줄 셋이 목록 앞에 끼어 나온다. 코드는 기대대로였다.
6. 루트 게이트(처음으로 2회 — `feedback_gate_runs`): 열아홉 체인 2/2, `PD-M2 check PASS` 둘, `FAIL` 0줄, 47분 46초
   (2026-10-05, docker 작업 없이 단독). 3회였던 PD-M1의 1시간 8분 41초에서 20분 55초가 줄었다 — `feedback_gate_runs`가
   어림한 "약 20분"과 맞다.
