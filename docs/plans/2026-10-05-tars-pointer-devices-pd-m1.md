# PD-M1 — 화살표가 포인터를 따라오고, 휠이 패널을 움직인다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-pointer-devices-design.md`
Status: 끝났다(2026-10-05). 실측은 맨 아래 "PD-M1이 실측한 것" 절에 있다. 기준은 PD-M0 commit `8f8a030`.
regression · mutation 다섯을 돌려 봤다(확정 11 · 13).

## 누가 무엇을 하나

design 결정 11. Task 0~7은 구현 서브에이전트(Sonnet)가 main 작업 트리에서 직접 편집한다. Task 8(루트 게이트 ·
실측 절 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` ·
각 Task의 명령 출력을 그대로 보고한다. mutation(Task 7)도 구현자가 돌린다. 이 plan의 "확정한 것" 절과 "실측한 것"
절은 구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본에서 이미 컴파일하고 호스트 검사를 돌렸다(확정 10). 아래의 `old_string` ·
`new_string`과 새 파일 내용은 그 사본에서 기계로 뽑은 것이다 — 구현자는 코드를 새로 짓지 않는다. Edit 도구에 글자
그대로 넣고, 각 Task 끝에서 확인한다 — PD-M0이 안 건드리는 파일은 사본과 `diff`해 같은지, `main.zig` · `check.sh`는
앵커 검사(`anchors.py post`)로 각 `new_string`이 정확히 한 번 들어갔는지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에
맞춰 고친다. plan의 글자와 사본이 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄(참고) |
|---|---|---|
| `terminal/src/pointer.zig` | 끝에 화살표 절 하나 — 크기 · 전용 색 둘 · 모양 · `ARROW_INK` · `arrowColor` · `Spot` · `sameSpot` · `Sprite` | +174 |
| `terminal/src/pointer_test.zig` | 가짜 화면 `Fake`와 검사 11~15. OK 줄이 47에서 69가 된다 | +131 |
| `terminal/src/layout.zig` | `Hit`과 `Tree.hit` | +27 |
| `terminal/src/layout_test.zig` | `expectHit`과 검사 12. `hit` OK 줄 22 | +54 |
| `terminal/src/main.zig` | 편집 열둘 | +136 −13 |
| `pointer/check.sh` | 통째로 다시 쓴다. M0 검사를 M1의 화면에 맞게 고치고 검사 8~12를 더한다 | +287 −70 |
| `check.sh` | 체인 설명 문단과 `CHAINS`의 `"PD-M0:…"` → `"PD-M1:…"` | +4 −3 |

`terminal/build.zig`는 안 고친다 — `pointer_test` · `layout_test`가 이미 등록돼 있다. 커널도 안 고친다.

`docs/guides/lessons.md` · design `Status:` · `HANDOFF.md`는 이 milestone에서 안 고친다(design "닫을 때").

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/pdm1/impl/` 아래에 둔다.
`/tmp/run/pdm1/` 바로 아래는 이 plan을 쓰며 만든 것이다. 특히 `/tmp/run/pdm1/term/src/` · `/tmp/run/pdm1/pointer/check.sh` ·
`/tmp/run/pdm1/root_check.sh`는 이 plan의 코드를 그대로 넣은 사본이고 대조에 쓴다. 지우지 않는다.

## 이 milestone이 끝나면

- 마우스를 움직이면 12 × 19 픽셀의 화살표가 포인터 좌표(왼쪽 위 끝이 hotspot)에 나타나 따라온다. 색은 전용 둘이다 —
  안쪽 `POINTER_FILL` `0x00FCFCF4`, 테두리 `POINTER_EDGE` `0x00040810`.
- 움직임만 있는 회차는 화면 전체를 다시 그리지 않는다. 저장해 둔 픽셀을 되돌리고, 새 자리 밑을 저장하고, 그리고,
  `present`한다(save-under). `screen>` 같은 덤프 줄도 안 찍힌다.
- 셀이 바뀐 회차(출력 · 키 · 스크롤)는 지금처럼 다시 그리고, `present` 바로 앞에서 화살표를 새로 그린다.
- 화살표는 세 조건이 다 맞을 때 보인다 — 열린 포인터 장치가 하나 이상이다, 열린 뒤 움직였거나 버튼을 눌렀다, 그 뒤로
  키보드가 PTY에 바이트를 보내지 않았다. 키를 치면 숨고 다음 움직임에 다시 나타난다. 마지막 장치가 빠지면 숨는다.
- 휠 한 눈금이 포인터 아래 패널의 스크롤백을 세 줄 움직인다. 앞으로 밀면 위로 간다. 포커스는 안 바뀐다. 여백 ·
  구분선 위, 그리고 키보드 copy mode인 패널에서는 아무 일도 없다.
- `pointer> at` 줄의 `shown=` · `ink=`가 실제 값을 찍는다. 화살표가 숨은 회차에도 한 줄 찍힌다.
- 호스트 검사의 OK 줄이 는다(`pointer_test` 47 → 69, `layout_test`에 `hit` 22). 체인 수는 그대로 열아홉이고
  `pointer/check.sh`의 부팅은 여전히 하나다.

로그 줄(정본 — `main.zig`와 `pointer/check.sh`가 이 글자를 쓴다).

```
terminal: pointer> open /dev/input/event2 kind=mouse shown=0 name=QEMU QEMU USB Mouse
terminal: pointer> open /dev/input/event3 kind=mouse shown=1 name=QEMU QEMU USB Mouse
terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1
terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> at x=679 y=499 buttons=0 wheel=1 shown=1 ink=118
```

`skip` · `close` · `uevent failed` · `scan failed` 줄은 PD-M0(`8f8a030`) 그대로다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 정하고 잰 것이다. 이 plan을 쓰는 동안 루트 게이트(PD-M0)가 돌고 있어서 QEMU를 띄우는
측정은 게이트 뒤로 미뤘고, 게이트 뒤에 쟀다(확정 11).

1. 화살표 모양과 `ink` 상수. 고전적인 12 × 19 화살표를 그대로 옮겼다. 테두리 49픽셀 + 안쪽 69픽셀 = 118이다.
   `pointer.zig`의 `ARROW_INK = 118`이 이 수이고, `pointer_test` 검사 11이 `ARROW`에서 다시 세어 대조한다. 끝
   (0, 0)은 테두리다.

   ```
   E...........   E 테두리 POINTER_EDGE
   EE..........   F 안쪽   POINTER_FILL
   EFE.........   . 그리지 않는다
   EFFE........
   EFFFE.......
   EFFFFE......
   EFFFFFE.....
   EFFFFFFE....
   EFFFFFFFE...
   EFFFFFFFFE..
   EFFFFFFFFFE.
   EFFFFFFEEEEE
   EFFFEFFE....
   EFFEEFFE....
   EFE..EFFE...
   EE...EFFE...
   E.....EFFE..
   ......EFFE..
   .......EE...
   ```

   잘린 자리의 값 둘도 정해 둔다. 오른쪽 아래 끝(1279, 799)에는 끝 한 픽셀만 남아 `ink=1`이다(검사 10). (1269, 789)에는
   왼쪽 위 11 × 11만 남아 `ink=66`이다(검사 6의 핫플러그 마우스가 가는 자리). 둘 다 `pointer_test` 검사 14가 64 × 48
   가짜 화면의 같은 모양 자리에서 본다.

2. 색 둘은 겹치지 않는다. `rg -o '0x00[0-9A-Fa-f]{6}' terminal/src/*.zig`의 값은 `102030` · `303840` · `405060` ·
   `705000` · `808890` · `C08000` · `E0E8F0` · `F0F0F0` · `FFFFFF`이고 `FCFCF4` · `040810`은 없다. xterm 256색에도 없다
   (큐브 단계 `00 5f 87 af d7 ff`, 회색 `08`부터 10씩 — `FC` · `F4` · `04` · `10`이 어느 쪽에도 없다).

3. save-under의 모양. `pointer.Sprite`가 대상 크기(`w` · `h`), 그린 자리 `at: ?Spot`, 저장 버퍼 `[19 × 12]u32`를 든다.
   함수는 넷이다 — `show`(밑을 저장하고 그린다) · `restore`(저장한 것을 되돌리고 `at`을 비운다) · `forget`(픽셀은 안
   건드리고 `at`만 비운다) · `ink`(아래 확정 5). 대상은 `anytype`이라 게스트에서는 `drm.Framebuffer`, 호스트에서는
   `pointer_test`의 `Fake`다. 저장과 되돌리기는 화살표가 덮는 118자리만 한다. 실기의 프레임버퍼는 캐시가 없어 되읽기가
   비싸다(design 결정 10). 대상 가장자리에서 자르는 것도 `Sprite`다 — `setPixel`에 범위 검사가 없다.

   `main.zig` 루프의 두 길은 이렇다.

   | 회차 | 하는 일 |
   |---|---|
   | `needs_redraw`가 꺼졌고 화살표가 있어야 할 자리(`want`)가 지금 자리(`sprite.at`)와 다르다 | `restore` → (`want`이 있으면) `show` → `present`. 렌더도 덤프도 없다 |
   | `needs_redraw`가 꺼졌고 자리가 같다 | 아무것도 안 그리고 `present`도 안 한다 |
   | `needs_redraw`가 켜졌다 | 평소대로 다 그리고 `renderFinish` 안에서 `forget` → (`want`이 있으면) `show` → `present` |

   셋째 줄에서 `restore`가 아니라 `forget`인 것이 요점이다. `renderBackdrop`의 `fb.fill`이 화면 전체를 다시 칠하므로 옛
   화살표는 이미 지워졌고, 저장한 픽셀은 지난 프레임의 것이다. 거기서 되돌리면 새 프레임 위에 지난 프레임의 조각을
   붙인다.

   두 길이 갈리는 자리는 루프 끝의 `if (!needs_redraw) continue;`다. 그 한 줄이 블록이 된다(편집 E10).

4. 보이는 조건 셋은 상태 둘이다. `pointer_shown: bool`(조건 2 · 3)과 열린 장치 수(조건 1, `pointerCount`)다. `want`은
   `pointer_shown and pointerCount > 0`일 때 지금 좌표, 아니면 null이다.

   | 바꾸는 자리 | 값 | 이유 |
   |---|---|---|
   | 포인터 분기, 그 회차에 움직였거나 버튼이 눌렸다(`round.woke`) | `true` | 조건 2. 휠만 굴린 회차는 아니다 — design 결정 4의 목록이 움직임과 누름이다 |
   | 키보드 분기, `keys.bytes.len > 0`이라 `pty.write`를 한 블록 | `false` | 조건 3. 셸로 가는 글자를 친 회차다 |
   | 포인터 분기, 빠진 장치를 닫고 새 장치를 연 뒤 열린 장치가 0 | `false` | 다시 꽂은 장치는 움직여야 보인다("열린 뒤", lead가 정했다, 2026-10-05). 조건 1은 `want`이 따로 본다 |

   조건 3의 자리를 `keys.bytes`의 블록 하나로 정했다(lead가 정했다, 2026-10-05). 수정 키 · copy mode 명령(`j` · `k` · `y` · `Esc`) · `PageUp` ·
   패널 명령은 PTY로 아무것도 안 보내므로 화살표가 그대로다. `Cmd+V`(`dumpPaste`)와 터미널 질의의 답
   (`takeReplies`)은 PTY에 쓰지만 이 블록 밖이라 숨기지 않는다 — 붙여넣기는 치는 일이 아니고, 질의의 답은 키보드가
   아니다. PD-M2가 끌어 복사한 뒤 `Cmd+V`를 다루며 이 자리를 다시 볼 수 있다.

   같은 회차에 키와 움직임이 함께 오면 키보드 분기가 먼저라 끄고, 포인터 분기가 뒤에서 켠다. 움직임이 이긴다.

   `open` 줄의 `shown=`은 그 회차 앞에 화면에 화살표가 그려져 있었는가다. PD-M0은 상수 0이었다. 첫 장치는 언제나 0이고,
   화살표가 보이는 동안 꽂은 둘째 장치는 1이다 — 검사 6이 그 1을 본다.

   그 값은 파일 하나의 `var pointer_drawn`이 나른다. 포인터 분기가 회차 머리에서 `before_spot != null`을 써 두고
   `tryOpenPointer`가 읽는다. 인자로 나르면 장치를 여는 함수 셋(`tryOpenPointer` · 처음 훑기 · 핫플러그 드레인)의 머리를
   다 고쳐야 하는데, 뒤의 둘은 PD-M0이 inotify를 netlink로 바꾸며 다시 썼다(확정 13). 쓰는 자리가 하나이고
   읽는 자리가 하나라 전역 값의 흔한 병(누가 언제 바꿨나)이 없다.

5. `at` 줄. 찍는 자리를 포인터 분기에서 "그린 뒤"로 옮겼다(`dumpPointerAt`). `ink`가 그린 결과를 되읽어야 하기
   때문이다. 움직임만 있는 회차는 `present` 뒤, 전체 프레임은 덤프들 맨 뒤(`dumpScroll` · `font>` 뒤)다. 뒤의 것에
   뜻이 있다 — 게이트가 새 `at` 줄을 보면 그 프레임의 `scroll>` 줄은 이미 찍혔다(검사 11).

   `ink`는 lead가 고친 정의대로 직전 자리(`before_spot`, 그 회차 앞의 `sprite.at`)와 지금 자리(`sprite.at`)의 사각형
   둘에서 `POINTER_FILL` · `POINTER_EDGE`를 센다. 겹치면 합집합을 한 번 센다. 다 보이면 118, 숨었으면 0, 잘리면
   그 사이, 옛 자리를 못 지웠으면 118보다 크다.

   숨긴 회차의 줄. 키를 친 회차에는 포인터 이벤트가 없어 M0의 규칙("이벤트가 있던 회차")으로는 줄이 안 나온다. 안 셋
   중 (c) "숨기는 회차에 `at` 줄을 한 번 찍는다"를 골랐다. 조건은 `before_spot != null and sprite.at == null`이다.

   - (a) `pointer> hide` 줄을 따로 두면 그 줄에도 `ink`가 있어야 "정말 지웠다"를 본다. 그러면 같은 값을 두 줄 모양이
     나눠 찍고, 게이트의 판정 함수(`last_at` · `wait_for_at`)도 둘이 된다.
   - (b) 다음 `at` 줄의 `shown=0`은 오지 않는다. 다음 움직임이 다시 보이게 하기 때문이다.
   - (c)는 줄 모양이 하나이고, 숨은 회차의 `ink`가 직전 자리 사각형을 세므로 "되돌렸다"를 그 자리에서 본다
     (`shown=0 ink=0`). 마지막 장치가 빠진 회차도 같은 줄이 된다.

   그래서 `at` 줄이 나오는 회차는 둘이다 — 포인터 이벤트가 있던 회차, 화살표가 숨은 회차. 셸 출력만 있는 회차에는
   여전히 안 나온다.

6. 픽셀 → 칸 → 잎. design 결정 5 그대로 두 단계다. `main.zig`의 `gridCell(x, y, cols, rows) ?GridCell`이
   `paneOrigin`과 같은 상수 넷으로 픽셀을 격자 칸으로 바꾸고, `layout.Tree.hit(whole, col, row) ?Hit`이 칸을 잎과 그
   안의 상대 칸으로 바꾼다. 게이트의 격자는 x 20~1259, y 20~771이고 그 밖이 null이다.

   `Hit`은 `layout.zig`에 둔다. design의 스케치는 `pointer.zig`에 두었는데, `layout.zig`가 `pointer.zig`를 import하면
   `layout_test`가 `c_input` 번역을 링크해야 하고, `pointer.zig`는 `layout.zig`를 import하지 않기로 했다(그 파일의
   머리 주석). PD-M2의 `Gesture`가 `Hit`을 받을 때 `pointer.zig`에 둘지(그때는 `main.zig`가 옮겨 담는다) 그 plan이
   정한다.

   `hit`은 `rects`로 사각형을 얻고 트리 순회(`leaves`)로 있는 잎만 본다. `rects`는 없는 잎의 칸을 안 건드리므로 배열을
   통째로 훑으면 쓰레기 값을 읽는다.

7. 휠. 포인터 분기에서 드레인 뒤에 한다. `round.wheel`(회차의 `REL_WHEEL` 합)이 0이 아니면 지금 좌표 → `gridCell` →
   `ws.tree.hit` → 그 잎의 패널. 그 패널이 `copyActive()`면 아무것도 안 한다. 아니면
   `scrollByRows(-WHEEL_ROWS * wheel)`이고 `needs_redraw`를 켠다. `WHEEL_ROWS`는 `isize` 3이다. 셋 중 하나라도
   null이면 labeled block(`wheel:`)을 `break`로 나간다.

   포커스 아닌 패널을 굴려도 된다(결정 7). 그때 `scroll>` 줄은 포커스 패널의 값이라 안 바뀐다. M1의 체인은 패널이
   하나라 상관없고, 패널이 여럿인 경우는 PD-M2가 끄는 동안의 휠과 함께 본다.

   `REL_WHEEL_HI_RES`는 M0 디코더가 이미 버린다(`Mouse.feed`의 REL `switch`의 `else`). M1은 디코더를 안 고친다.

8. `present`의 로그 줄. `drm.zig`의 `present`가 매번 `kms: set crtc N to fb M` 한 줄을 찍는다. 움직임 회차마다 그 줄이
   는다. 어느 체인도 그 줄을 세거나 보지 않는다 — `rg -n 'set crtc|kms:' --glob '*.sh'`가 0줄이다. `type_keys`는 로그가
   자라는지를 보는데 포인터가 없는 체인에서는 이 줄이 안 생기고, 포인터 체인에서는 키를 친 회차가 어차피 `at` 줄이나
   에코를 만든다.

9. 체인의 순서를 다시 짰다. M0의 검사 넷이 M1의 화면과 부딪친다.

   | M0 | 부딪치는 것 | M1에서 |
   |---|---|---|
   | 검사 2~5의 `shown=0 ink=0` | 이제 그린다 | `shown=1 ink=118`(끝에서는 `ink=1`) |
   | 검사 4(650, 405에서 휠) | 패널 위라 휠이 화면을 다시 그린다 | 검사 11로 옮긴다. `seq 200` 뒤라 offset이 실제로 움직인다 |
   | 검사 7(움직인 뒤 screendump가 바이트까지 같다) | 화살표가 보인다 | 둘로 가른다. 움직이기 전 screendump에 화살표 색이 0개(보이는 조건 2, mutation 1이 여기서 빨개진다), 그리고 움직임만으로는 `screen>`이 안 는다(save-under) |
   | 검사 6의 둘째 `open … shown=0` | 화살표가 보이는 중에 꽂는다 | `shown=1` |

   그리고 screendump의 바이트 비교 대신 두 장의 차이를 본다. 움직이기 전과 두 번 움직인 뒤를 비교해 다른 픽셀이
   정확히 118개이고 전부 (700, 455)의 12 × 19 안이며 전부 화살표 색이면, 옛 자리가 바이트까지 돌아왔고 `present`가
   그 화면을 QEMU까지 보냈다는 것이다. `at` 줄의 `ink`는 terminal이 자기 메모리를 되읽은 것이라 `present`가 빠져도
   맞는다.

   screendump를 세는 도구는 perl이다. 컨테이너에 python3 · xxd가 없고 perl은 있으며(`/usr/bin/perl`), `net` 체인의 NTP
   stub과 `install` 체인이 이미 쓴다. 함수 둘(`ppm_arrow` · `ppm_diff`)이고, 호스트에서 가짜 1280 × 800 P6 파일로 돌려
   보니 비교 한 번이 0.15초였다.

   검사 번호는 design 결정 10의 것을 그대로 쓴다. 더한 둘은 번호를 새로 안 주고 "검사 9의 둘째"(마지막 장치가 빠지면
   숨는다) · "검사 11의 둘째"(키보드 copy mode에서는 휠을 무시한다)로 부른다. 13번부터는 PD-M2의 몫이다.

   부팅 마우스에 id를 붙인다(`-device usb-mouse,id=pdboot`). 검사 9의 둘째가 `device_del pdboot`로 그것을 뺀다.

   체인의 순서(좌표는 게이트 프레임버퍼 1280 × 800, 출발 640, 400).

   | 순서 | 검사 | 친다 | 본다 |
   |---|---|---|---|
   | 1 | 1 | 부팅 | `open … kind=mouse shown=0` 정확히 하나 · 키보드 · 전원 버튼 `skip` |
   | 2 | 7 | 움직이기 전 | screendump의 화살표 색 0 · `pane>` 줄이 포인터 없는 부팅과 같다 |
   | 3 | 2 · 8 | `mouse_move 10 5` · `mouse_move 50 50` | `650,405 … shown=1 ink=118` · `700,455 … ink=118` · screendump 차이 `n=118 box=700,455 711,473 other=0` |
   | 4 | 3 | `mouse_button 1` · `0` | `buttons=1` 뒤 `buttons=0`, 둘 다 `ink=118` |
   | 5 | 5 · 10 | 왼쪽 위로 크게 · 오른쪽 아래로 크게 | `x=0 y=0 … ink=118` · `x=1279 y=799 … ink=1` |
   | 6 | 7의 둘째 | — | 여기까지 `screen>` 줄 수가 그대로 |
   | 7 | 6 | `device_add` · 움직임 · `device_del` · 움직임 | 둘째 `open … shown=1` · `1269,789 … ink=66` · `close` · `1279,799 … ink=1` |
   | 8 | 9 | 가운데로 옮긴 뒤 `echo pd-hide-ok` | `679,499 … shown=0 ink=0` 한 줄 · 에코 · screendump 화살표 0 · 다음 움직임에 `ink=118` |
   | 9 | 11 | `seq 200` 뒤 휠 위 · 아래 | offset이 3 줄고 되돌아온다 · `wheel=1` · `wheel=-1` |
   | 10 | 11의 둘째 | `Cmd+Shift+C` 뒤 휠 · `Esc` | offset과 `screen>` 수가 그대로 |
   | 11 | 12 | 위 여백(y=0)으로 옮긴 뒤 휠 | `wheel=1` · offset과 `screen>` 수가 그대로 |
   | 12 | 9의 둘째 | `device_del pdboot` | `close` · `679,0 … shown=0 ink=0` · screendump 화살표 0 |

10. 사본에서 돌려 본 것. 처음에는 저장소의 `terminal/`을 캐시만 빼고 `/tmp/run/pdm1/term/`으로 복사해(그때는 PD-M0의
    inotify 판, commit 전 작업 트리) 이 plan의 편집을 넣었다. PD-M0이 `8f8a030`으로 commit된 뒤 같은 편집을 그 commit의
    파일에 다시 넣었고, 지금의 `/tmp/run/pdm1/term/src/` · `/tmp/run/pdm1/root_check.sh`는 `8f8a030` + 이 plan이다. 아래의
    `old_string` · `new_string`과 참고 줄 번호도 `8f8a030`에서 뽑았다.

    | 명령 | 결과 |
    |---|---|
    | `zig build` | `exit=0` |
    | `zig build test` | `exit=0`, `pointer_test` OK 줄 69, `layout_test: hit … OK` 22줄, `all checks passed` 셋 |
    | `zig fmt --check` | 고친 넷(`pointer` · `pointer_test` · `layout` · `layout_test`)은 깨끗하다. `main.zig`는 고치기 전부터 세 자리가 fmt와 다르고(`CELL_W` 꼬리 주석 · `dumpCursor` · `dumpImages`의 인자 정렬) 이 plan이 더한 줄은 fmt와 같다 |
    | `pointer/check.sh` | `bash -n` 통과, 진입 검사 셋 `ENTRY-OK` |

    편집은 기계로 뽑았다(`/tmp/run/pdm1/hunks.py`). 원본에 `old_string` → `new_string`을 차례로 넣으면 사본과 바이트까지
    같다. 앵커는 바뀐 줄만 담고(앞뒤 문맥 0줄), 그 글자가 파일에 한 번뿐이 아니면 위아래로 한 줄씩 늘렸다. 그리고
    PD-M0이 다시 쓰는 글자(`drainWatch` · `watch_fd` · `inotify` · `fds[1]` · `scanPointers`)는 어느 `old_string`에도 안
    들어가게 막았다.

    앵커 검사 도구가 `/tmp/run/pdm1/anchors.py`다(데이터는 같은 자리의 `anchors.json`, 파일 여섯의 편집 스물하나 —
    `pointer/check.sh`는 통째로 쓰므로 빠진다). `pre`는 각 `old_string`이 저장소 파일에 정확히 한 번 있는지, `post`는
    각 `new_string`이 정확히 한 번 있는지 본다. `8f8a030`에서 `pre: 21 edits, 0 bad`였다. 편집은 inotify 판에서 뽑은
    것과 글자 하나 다르지 않았다 — PD-M0의 netlink 전환이 이 plan의 앵커를 하나도 안 건드렸다.

11. 게이트 뒤에 잰 것. 2026-10-05에 두 번 쟀다. 저장소를 `/tmp/run/pdm1/repo/`로 통째로 복사하고(`.git` 제외) 이
    plan의 파일을 덮어 거기서 돌렸다. 체인의 monitor 포트는 사본에서 45495, HI_RES probe가 45496, regression이 45496 ·
    45497 · 45498이다(다른 작업과 부딪치지 않게 바꿨다 — 저장소의 체인은 45488 그대로다). 로그는 `/tmp/run/pdm1/repo/out/` ·
    `/tmp/run/pdm1/meas/`에 있다.

    첫째 판은 PD-M0의 inotify 판(commit 전) 위에서, 사본의 `kernel/.config`만 `CONFIG_INOTIFY_USER=y`로 켜고 쟀다.
    QEMU와 커널의 성질 넷은 이 판의 값이다 — PD-M0의 판과 무관하다.

    | 무엇 | 결과 |
    |---|---|
    | `REL_WHEEL_HI_RES` 값 | 한 눈금에 ±120이다. 게스트에서 `head -c 72 /dev/input/event2 \| cat -v`로 `mouse_move 0 0 -1`의 이벤트를 읽었더니 `REL_WHEEL`(8) -1 뒤에 코드 11(`^K`)의 값 `0xFFFFFF88`(-120)이 왔다. 휠만 굴린 회차의 `at` 줄은 `shown=0 ink=0`이었다(보이는 조건 2가 휠을 안 센다) |
    | `-device usb-mouse,id=pdboot` · `device_del pdboot` | 된다. 노드는 id 없을 때와 같은 event2이고, 뺀 뒤 `close /dev/input/event2`와 `shown=0 ink=0` 줄이 나왔다 |
    | screendump와 `present` | screendump는 `present` 뒤의 화면이다. 색도 그대로다 — 두 번 움직인 뒤 차이가 `n=118 box=700,455 711,473 other=0`. 움직임 회차의 `present`를 빼는 mutation 5는 같은 자리에서 `n=0`이 됐다 |
    | 움직임만 있는 회차의 비용 | 40회. 그리기(`restore` + `show`)가 중앙값 19µs(5~141), `present`까지 합쳐 중앙값 687µs(347~5,671). 같은 부팅의 첫 전체 프레임은 63,183µs였다. 측정용 사본이 `std.Io.Clock`으로 쟀고 저장소 코드에는 없다 |

    둘째 판은 `8f8a030`(netlink 판) 위에서 쟀다. 커널은 HEAD 그대로다. 체인 · regression · mutation은 이 판의 값이 정본이다.

    | 무엇 | 결과 | 시간 |
    |---|---|---|
    | 체인 `pointer` | `PD-M1 check PASS`. 줄은 Task 6-1의 기대 그대로 | 1분 4초(커널 빌드 없음, terminal 증분 빌드 포함) |
    | regression `render` | `TR-M2 PASS`, `pointer>` 줄 0 | 1분 47초 |
    | regression `copy` | `CM-M2 check PASS`, `pointer>` 줄 0 | 2분 50초 |
    | regression `pane` | `WP-M2 check PASS`, `pointer>` 줄 0 | 31초 |
    | mutation 1~5 | 다섯 다 Task 7의 표의 자리와 문구 그대로 빨갰다 | 1분 19초 · 1분 22초 · 1분 32초 · 1분 29초 · 1분 23초 |

    첫째 판에서 컨테이너 안의 `zig build`가 `Killed`로 두 번 죽었다. 캐시를 지운 빌드(mutation 판)와 다른 작업의 체인이
    겹쳐 Docker VM의 메모리 4GB를 넘은 것이다. 둘째 판은 VM을 혼자 쓰며 하나씩 돌렸고 한 번도 안 죽었다. Task 7은 판을
    하나씩 돌린다.

12. mutation을 넣는 법은 PD-M0 plan 확정 11과 같다. 저장소 파일은 안 고치고, 사본을 `-v`로 그 파일 자리에 덮는다. 같은
    `docker run` 안에서 먼저 `terminal/.zig-cache`와 `terminal/zig-out`을 지우고, 덮인 사본이 쓰였는지 `grep -c`로
    mutation 글자를 센다. `pointer.zig`를 바꾸는 mutation 4는 체인이 부팅 전에 돌리는 `zig build test`가 먼저 잡으므로,
    체인의 판정은 그 한 단계만 끈 사본 체인으로 본다. 조건에는 runtime 값을 쓴다(`pointer_state.w == 0`) — comptime에
    정해지는 조건은 뒤의 줄을 도달 불가로 만들어 컴파일 에러가 날 수 있다.

13. PD-M0이 이 plan을 쓰는 동안 바뀌었다. 2026-10-05의 루트 게이트가 두 번 다 `install` 체인 부팅 7에서 빨갰고,
    원인은 PD-M0이 켠 `CONFIG_INOTIFY_USER=y`(→ `FSNOTIFY=y`)가 TCG에서 initramfs 풀기를 2.6초에서 3.8초로 늦춰 그
    체인의 3초 창을 닫은 것이었다. 그래서 PD-M0은 inotify를 버리고 netlink uevent(`NETLINK_KOBJECT_UEVENT`)로 핫플러그를
    잡도록 고쳐 `8f8a030`으로 commit됐다. 커널은 안 바뀌었다.

    이 plan이 그에 맞춘 것.
    - `main.zig`의 편집은 핫플러그 코드(uevent 소켓 · 그 드레인 · `fds[1]`)를 앵커로 안 쓴다(확정 10). 그래서 `8f8a030`에
      그대로 들어갔다.
    - `open` 줄의 `shown`을 인자가 아니라 `pointer_drawn`으로 나른다(확정 4).
    - `pointer/check.sh`의 M0 부분을 `8f8a030`의 글자로 맞췄다 — 머리 주석의 uevent 두 줄, `report_failure`의
      `uevent failed` 표식, 검사 1 · 6 주석의 uevent 문구. 이 plan의 체인은 `8f8a030`의 체인에서 만들었다(+287 −70).
    - 확정 11의 둘째 판이 `8f8a030` 위에서 체인 · regression · mutation 다섯을 다시 돌렸다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다. Task 6 · 7이 docker로 체인을 돌리므로 겹치면 monitor 포트와 `kernel/initrd.cpio`가
   부딪친다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: `git status`는 이 plan 파일(`??` 또는 이미 commit됐으면 0줄)과, lead가 고치는 중일 수 있는 `HANDOFF.md`뿐이다.
   PD-M0의 commit `8f8a030`(`PD-M0: Find pointer devices over uevent, …`)이 보여야 한다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 10).

   ```bash
   python3 /tmp/run/pdm1/anchors.py pre "$PWD"
   ```

   기대: `pre: 21 edits, 0 bad`. 하나라도 `bad`면 그 줄(`파일 edit N: pre count=…`)을 보고하고 멈춘다 — PD-M0이 그 글자를
   바꿨다는 뜻이다.

4. 호스트 검사를 한 번 초록으로 본다.

   ```bash
   mkdir -p /tmp/run/pdm1/impl
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
     bash -c 'zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -a -c "^pointer_test: .* OK$" /tmp/t.out; grep -a -E "all checks passed|FAIL" /tmp/t.out'
   ```

   기대: `exit=0`, `47`, 그리고 `layout_test` · `pointer_test` · `status_test`의 `all checks passed` 세 줄. `FAIL`은 0줄.

## Task 1: `terminal/src/pointer.zig` — 화살표 절

파일 끝(`clampAdd`의 닫는 중괄호 뒤)에 한 절을 붙인다. 순수한 그대로다 — 시스템 콜도 import도 새로 없다.

읽을 자리 셋. `Sprite.show`가 그리기 전에 밑을 저장하는 것, `restore`가 그 자리를 되돌리고 `at`을 비우는 것과
`forget`이 픽셀을 안 건드리는 것의 차이(확정 3), `ink`가 두 사각형을 합집합으로 세는 것(확정 5).

Edit 하나다. `old_string`은 파일의 마지막 두 줄이다.

`old_string`(기준 파일 270줄부터):

```zig
    return @intCast(next);
}
```

`new_string`:

```zig
    return @intCast(next);
}

// ── 화살표(PD-M1) ─────────────────────────────────────────────────────
//
// 화면에 그리는 쪽의 산수다. 대상은 `anytype` — `getPixel(x, y) u32`와
// `setPixel(x, y, color)`가 있는 것 — 이라 게스트에서는 `drm.Framebuffer`가,
// `pointer_test`에서는 `u32` 배열이 들어온다. `image.zig`와 같은 모양이다.

/// 화살표의 크기(PD design 결정 4). hotspot은 왼쪽 위 끝 (0, 0)이다.
pub const ARROW_W: u32 = 12;
pub const ARROW_H: u32 = 19;

/// 화살표 안쪽의 색(PD design 결정 4). 전용 색이다 — 게이트가 이 색과
/// `POINTER_EDGE`만 세어 "그 자리에 그렸는가"를 본다(CI 결정 3 · WP의
/// `SEPARATOR`와 같은 이유). 지금의 색 상수와 xterm 256색 팔레트에 없다.
pub const POINTER_FILL: u32 = 0x00FCFCF4;

/// 화살표 테두리 한 픽셀의 색. 밝은 글자 위에서도 화살표가 보이게 한다.
pub const POINTER_EDGE: u32 = 0x00040810;

/// 화살표 모양. `E`는 테두리, `F`는 안쪽, `.`은 그리지 않는 자리다. 줄이
/// y, 글자가 x다. 고전적인 12 × 19 화살표를 그대로 옮겼다.
const ARROW = [ARROW_H]*const [ARROW_W]u8{
    "E...........",
    "EE..........",
    "EFE.........",
    "EFFE........",
    "EFFFE.......",
    "EFFFFE......",
    "EFFFFFE.....",
    "EFFFFFFE....",
    "EFFFFFFFE...",
    "EFFFFFFFFE..",
    "EFFFFFFFFFE.",
    "EFFFFFFEEEEE",
    "EFFFEFFE....",
    "EFFEEFFE....",
    "EFE..EFFE...",
    "EE...EFFE...",
    "E.....EFFE..",
    "......EFFE..",
    ".......EE...",
};

/// 화살표가 다 보일 때의 `ink`(테두리 49 + 안쪽 69). `pointer> at` 줄이 이
/// 수를 찍고 `pointer/check.sh`가 이 글자를 본다. `pointer_test`가 `ARROW`에서
/// 다시 세어 대조한다 — 모양을 고치면 이 수와 게이트를 함께 고친다.
pub const ARROW_INK: u32 = 118;

/// 화살표 안의 한 자리 `(dx, dy)`의 색. 그리지 않는 자리면 null이다.
pub fn arrowColor(dx: u32, dy: u32) ?u32 {
    return switch (ARROW[dy][dx]) {
        'E' => POINTER_EDGE,
        'F' => POINTER_FILL,
        else => null,
    };
}

/// 화살표의 자리. 대상의 픽셀 좌표이고 hotspot(왼쪽 위 끝)의 자리다.
pub const Spot = struct { x: u32, y: u32 };

/// 두 자리가 같은가. 둘 다 null이면 같다.
pub fn sameSpot(a: ?Spot, b: ?Spot) bool {
    const p = a orelse return b == null;
    const q = b orelse return false;
    return p.x == q.x and p.y == q.y;
}

/// 화면의 화살표 하나와 그 밑의 픽셀(save-under, PD design 결정 4).
///
/// 움직임만 있는 회차는 화면 전체를 다시 그리지 않는다. 저장해 둔 픽셀을
/// 되돌리고(`restore`), 새 자리 밑을 저장하고 그린다(`show`). 셀이 바뀐
/// 회차는 화면 전체를 다시 칠하므로 저장한 픽셀이 낡는다 — 그때는 되돌리지
/// 않고 잊는다(`forget`). 되돌리면 새 프레임 위에 지난 프레임의 조각을 붙인다.
///
/// 화살표가 덮는 픽셀(`arrowColor`가 null이 아닌 자리)만 저장하고 되돌린다.
/// 나머지는 화살표가 안 건드리므로 그대로다. 실기의 프레임버퍼는 캐시가 없는
/// 메모리라 되읽기가 비싸다(design 결정 10) — 읽는 수를 줄인다.
///
/// 대상의 가장자리에서 화살표가 잘린다. `drm.Framebuffer.setPixel`에 범위
/// 검사가 없으므로 이 자르기가 곧 프레임버퍼 밖 쓰기를 막는 자리다.
pub const Sprite = struct {
    /// 대상의 크기. 자르기에 쓴다.
    w: u32,
    h: u32,
    /// 지금 화살표가 그려진 자리. null이면 화면에 화살표가 없다.
    at: ?Spot = null,
    /// `at`에 그리기 전에 저장한 픽셀. `[dy * ARROW_W + dx]`다.
    saved: [ARROW_H * ARROW_W]u32 = @splat(0),

    pub fn init(w: u32, h: u32) Sprite {
        return .{ .w = w, .h = h };
    }

    /// `s`에서 대상 안에 남는 폭과 높이. 대상 밖이면 0이다.
    fn span(self: *const Sprite, s: Spot) struct { w: u32, h: u32 } {
        return .{
            .w = if (s.x >= self.w) 0 else @min(ARROW_W, self.w - s.x),
            .h = if (s.y >= self.h) 0 else @min(ARROW_H, self.h - s.y),
        };
    }

    /// `s`에 화살표를 그린다. 그리기 전에 그 밑을 저장한다. 이미 그려진
    /// 화살표가 있으면 먼저 `restore`나 `forget`을 불러야 한다 — 이 함수는
    /// 옛 자리를 모른다.
    pub fn show(self: *Sprite, target: anytype, s: Spot) void {
        const sp = self.span(s);
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                const color = arrowColor(dx, dy) orelse continue;
                self.saved[dy * ARROW_W + dx] = target.getPixel(s.x + dx, s.y + dy);
                target.setPixel(s.x + dx, s.y + dy, color);
            }
        }
        self.at = s;
    }

    /// 저장한 픽셀을 되돌린다. 화살표가 없으면 아무 일도 안 한다.
    pub fn restore(self: *Sprite, target: anytype) void {
        const s = self.at orelse return;
        const sp = self.span(s);
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                if (arrowColor(dx, dy) == null) continue;
                target.setPixel(s.x + dx, s.y + dy, self.saved[dy * ARROW_W + dx]);
            }
        }
        self.at = null;
    }

    /// 화면 전체가 새로 칠해졌다. 화살표는 이미 지워졌고 저장한 픽셀은 낡았다.
    pub fn forget(self: *Sprite) void {
        self.at = null;
    }

    /// 두 사각형(직전 자리 `before`와 지금 자리 `at`, 각 12 × 19) 안에서
    /// `POINTER_FILL` · `POINTER_EDGE` 픽셀을 센다(PD design 결정 10).
    ///
    /// 화살표가 다 보이면 `ARROW_INK`이고, 숨었으면 0이고, 가장자리에서
    /// 잘리면 그 사이다. 옛 자리를 못 지웠으면 `ARROW_INK`보다 크다 — 자국은
    /// 되돌리지 못한 옛 자리에 남으므로 이 두 사각형 안에서 잡힌다. 두
    /// 사각형이 겹치면 겹친 픽셀은 한 번만 센다.
    ///
    /// 화면 전체를 세지 않는 이유는 이 수가 움직임 회차마다 찍히기 때문이다.
    pub fn ink(self: *const Sprite, target: anytype, before: ?Spot) u32 {
        var n: u32 = 0;
        if (before) |b| n += self.countRect(target, b, null);
        if (self.at) |a| n += self.countRect(target, a, before);
        return n;
    }

    /// 사각형 `s` 안의 화살표 색 픽셀 수. `skip` 사각형 안의 픽셀은 안 센다.
    fn countRect(self: *const Sprite, target: anytype, s: Spot, skip: ?Spot) u32 {
        const sp = self.span(s);
        var n: u32 = 0;
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                const x = s.x + dx;
                const y = s.y + dy;
                if (skip) |k| {
                    if (x >= k.x and x < k.x + ARROW_W and y >= k.y and y < k.y + ARROW_H) continue;
                }
                const p = target.getPixel(x, y) & 0x00FFFFFF;
                if (p == POINTER_FILL or p == POINTER_EDGE) n += 1;
            }
        }
        return n;
    }
};
```

확인.

```bash
git diff --stat terminal/src/pointer.zig
diff terminal/src/pointer.zig /tmp/run/pdm1/term/src/pointer.zig && echo SAME
```

기대: `1 file changed, 174 insertions(+)`, `SAME`.

## Task 2: `terminal/src/pointer_test.zig` — 가짜 화면과 검사 다섯

`Fake`는 64 × 48 화면이다. `image_test`의 `Fake`와 같은 모양이고 하나가 더 있다 — 범위 밖을 읽거나 쓰면 `oob`를
세우고 아무것도 안 한다. `drm.Framebuffer`는 그때 게스트를 죽이므로 검사가 그것을 봐야 한다.

검사 다섯.

| 검사 | 본다 |
|---|---|
| 11 | `ARROW`의 픽셀 수가 `ARROW_INK`(118)다 · 끝이 테두리 색이다 |
| 12 | `show` 뒤 `restore`면 모든 픽셀이 처음과 같다 · 움직임(restore → show)의 `ink`가 118이다 |
| 13 | 되돌리지 않고 다시 그리면 `ink`가 236이다(게이트 검사 8이 잡는 고장) · 겹치는 두 자리는 한 번 센다 · `forget` |
| 14 | 오른쪽 아래 끝 `ink=1`, 11 × 11이 남는 자리 `ink=66`, 화면 밖 `ink=0`, 범위 밖 쓰기 없음 |
| 15 | `sameSpot` |

Edit 둘이다. 첫째는 `Fake`를 `feed` 도우미 앞에 넣는다.

`old_string`(기준 파일 91줄부터):

```zig
    return error.WrongPosition;
}
```

`new_string`:

```zig
    return error.WrongPosition;
}

/// 64 × 48 화면 하나. 프레임버퍼 대신 들어간다(`image_test`의 `Fake`와 같은
/// 모양). 범위 밖을 읽거나 쓰면 `oob`를 세우고 아무것도 안 한다 —
/// `drm.Framebuffer`는 그때 게스트를 죽이므로 검사가 그것을 봐야 한다.
const Fake = struct {
    const W: u32 = 64;
    const H: u32 = 48;
    px: [W * H]u32 = @splat(0x00102030),
    oob: bool = false,

    pub fn getPixel(self: *Fake, x: u32, y: u32) u32 {
        if (x >= W or y >= H) {
            self.oob = true;
            return 0;
        }
        return self.px[y * W + x];
    }
    pub fn setPixel(self: *Fake, x: u32, y: u32, color: u32) void {
        if (x >= W or y >= H) {
            self.oob = true;
            return;
        }
        self.px[y * W + x] = color;
    }
    /// 픽셀마다 다른 값. 화살표 색 둘과는 안 겹친다(위 바이트가 0이 아니다).
    fn pattern(self: *Fake) void {
        for (&self.px, 0..) |*p, i| p.* = 0x01000000 | @as(u32, @intCast(i));
    }
};
```

둘째는 검사 11~15를 `all checks passed` 앞에 넣는다.

`old_string`(기준 파일 304줄부터):

```zig
    std.debug.print("pointer_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 11: 화살표 모양과 그 ink 상수(PD-M1) ──────────────────────
    //
    // `ARROW_INK`는 게이트가 `at` 줄에서 보는 글자다. 모양을 고치고 상수를
    // 안 고치면 여기서 먼저 빨개진다. 끝(hotspot)이 테두리 색인 것도 본다 —
    // 오른쪽 아래 끝에서 화살표가 한 픽셀만 남을 때 그 픽셀이 이것이다.
    {
        var n: u32 = 0;
        var dy: u32 = 0;
        while (dy < pointer.ARROW_H) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < pointer.ARROW_W) : (dx += 1) {
                if (pointer.arrowColor(dx, dy) != null) n += 1;
            }
        }
        try expectNum("pixels in the arrow bitmap", n, pointer.ARROW_INK);
        try expectTrue("the hotspot (0,0) is an edge pixel", pointer.arrowColor(0, 0) == pointer.POINTER_EDGE);
        try expectTrue("fill and edge are different colors", pointer.POINTER_FILL != pointer.POINTER_EDGE);
    }

    // ── 검사 12: save-under 왕복 — 되돌리면 처음과 같다 ──────────────────
    //
    // 바탕을 픽셀마다 다른 값으로 채운다. 한 칸 어긋나게 저장하거나 되돌리면
    // 같은 값이 안 돌아오므로 여기서 보인다.
    {
        var f: Fake = .{};
        f.pattern();
        const orig = f.px;
        var s = pointer.Sprite.init(Fake.W, Fake.H);
        s.show(&f, .{ .x = 10, .y = 7 });
        try expectNum("ink after show at 10,7", s.ink(&f, null), pointer.ARROW_INK);
        try expectTrue("show changed the pixels under the arrow", !std.mem.eql(u32, &f.px, &orig));
        s.restore(&f);
        try expectTrue("restore brings back every pixel", std.mem.eql(u32, &f.px, &orig));
        try expectTrue("after restore no arrow is drawn", s.at == null and s.ink(&f, .{ .x = 10, .y = 7 }) == 0);

        // 움직임 한 번 = restore 뒤 show. 옛 자리는 처음 값으로 돌아오고 ink는
        // 두 사각형을 합쳐도 상수 하나다.
        s.show(&f, .{ .x = 10, .y = 7 });
        s.restore(&f);
        s.show(&f, .{ .x = 40, .y = 20 });
        try expectNum("ink over the old and the new spot after a move", s.ink(&f, .{ .x = 10, .y = 7 }), pointer.ARROW_INK);
        s.restore(&f);
        try expectTrue("a move then restore leaves no trace", std.mem.eql(u32, &f.px, &orig));
        try expectTrue("no write fell outside", !f.oob);
    }

    // ── 검사 13: 되돌리기를 빠뜨리면 ink가 상수보다 크다 ─────────────────
    //
    // 게이트 검사 8이 잡는 고장(save-under의 되돌리기를 뺀다)을 여기서 먼저
    // 재현한다. 두 자리가 겹치면 겹친 픽셀은 한 번만 센다.
    {
        var f: Fake = .{};
        var s = pointer.Sprite.init(Fake.W, Fake.H);
        s.show(&f, .{ .x = 0, .y = 0 });
        s.show(&f, .{ .x = 30, .y = 25 }); // restore 없이
        try expectNum("ink with a trace left behind (apart)", s.ink(&f, .{ .x = 0, .y = 0 }), 2 * pointer.ARROW_INK);

        var g: Fake = .{};
        var t = pointer.Sprite.init(Fake.W, Fake.H);
        t.show(&g, .{ .x = 5, .y = 5 });
        t.restore(&g);
        t.show(&g, .{ .x = 8, .y = 9 });
        try expectNum("overlapping spots are counted once", t.ink(&g, .{ .x = 5, .y = 5 }), pointer.ARROW_INK);
        t.forget();
        try expectTrue("forget drops the spot without touching pixels", t.at == null and t.ink(&g, null) == 0 and
            t.ink(&g, .{ .x = 8, .y = 9 }) == pointer.ARROW_INK);
    }

    // ── 검사 14: 가장자리에서 잘린다 — 범위 밖 쓰기가 없다 ───────────────
    //
    // 게이트 검사 10의 자리(오른쪽 아래 끝)다. 끝에 붙이면 hotspot 한 픽셀만
    // 남는다. 오른쪽 아래 11 × 11만 남는 자리는 게이트 검사 6이 핫플러그한
    // 마우스로 가는 자리(1269, 789)와 같은 모양이다.
    {
        var f: Fake = .{};
        f.pattern();
        const orig = f.px;
        var s = pointer.Sprite.init(Fake.W, Fake.H);
        s.show(&f, .{ .x = Fake.W - 1, .y = Fake.H - 1 });
        try expectNum("ink at the bottom right corner", s.ink(&f, null), 1);
        s.restore(&f);
        s.show(&f, .{ .x = Fake.W - 11, .y = Fake.H - 11 });
        try expectNum("ink with 11 x 11 left on screen", s.ink(&f, null), 66);
        s.restore(&f);
        s.show(&f, .{ .x = Fake.W + 5, .y = 0 });
        try expectNum("ink when the spot is past the right edge", s.ink(&f, null), 0);
        s.restore(&f);
        try expectTrue("no write fell outside at the edges", !f.oob);
        try expectTrue("clipped draws restore cleanly", std.mem.eql(u32, &f.px, &orig));
    }

    // ── 검사 15: 자리 비교 ────────────────────────────────────────────────
    //
    // `main.zig`가 "움직임만 있는 회차에 다시 그릴까"를 이것으로 가른다.
    {
        try expectTrue("null and null are the same spot", pointer.sameSpot(null, null));
        try expectTrue("null and a spot differ", !pointer.sameSpot(null, .{ .x = 0, .y = 0 }) and
            !pointer.sameSpot(.{ .x = 0, .y = 0 }, null));
        try expectTrue("equal spots are the same", pointer.sameSpot(.{ .x = 3, .y = 4 }, .{ .x = 3, .y = 4 }));
        try expectTrue("different spots differ", !pointer.sameSpot(.{ .x = 3, .y = 4 }, .{ .x = 4, .y = 3 }));
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
```

확인.

```bash
git diff --stat terminal/src/pointer_test.zig
diff terminal/src/pointer_test.zig /tmp/run/pdm1/term/src/pointer_test.zig && echo SAME
```

기대: `1 file changed, 131 insertions(+)`, `SAME`. 실행은 Task 4 끝에서 한 번에 한다.

## Task 3: `terminal/src/layout.zig` · `layout_test.zig` — `Tree.hit`

`Hit`을 `Dir` 앞에, `hit`을 `count` 앞에 넣는다(확정 6).

`old_string`(기준 파일 10줄부터):

```zig
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };
```

`new_string`:

```zig
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };

/// 격자 칸 하나가 어느 잎의 어느 칸인가(PD design 결정 5). `col` · `row`는
/// 그 잎의 사각형 안의 상대 칸이다 — 패널의 `vt.Screen`이 아는 좌표다.
pub const Hit = struct { leaf: u4, col: u16, row: u16 };
```

`old_string`(기준 파일 162줄부터):

```zig
    /// 잎의 수.
```

`new_string`:

```zig
    /// 격자 칸 `(col, row)`가 든 잎과 그 안의 상대 칸(PD design 결정 5).
    /// 포인터가 가리키는 패널을 고르는 자리다.
    ///
    /// null이 둘이다. 구분선 칸은 어느 잎의 사각형에도 안 들어가고(`halves`가
    /// 구분선을 두 잎 사이에 따로 둔다), 격자 밖 칸은 `whole` 밖이다. 픽셀을
    /// 격자 칸으로 바꾸는 것은 `main.zig`다 — 이 파일은 셀 단위만 안다.
    ///
    /// 사각형은 `rects`로 얻는다. 같은 산수를 여기서 다시 하면 언젠가 한 칸
    /// 어긋나고, 그 어긋남은 "구분선 위를 가리켰는데 왼쪽 패널이 움직인다"로
    /// 나타난다.
    pub fn hit(self: *const Tree, whole: Rect, col: u16, row: u16) ?Hit {
        var rs: [MAX_LEAVES]Rect = undefined;
        self.rects(whole, &rs);
        var buf: [MAX_LEAVES]u4 = undefined;
        for (self.leaves(&buf)) |leaf| {
            const r = rs[leaf];
            if (col < r.col or col >= r.col + r.cols) continue;
            if (row < r.row or row >= r.row + r.rows) continue;
            return .{ .leaf = leaf, .col = col - r.col, .row = row - r.row };
        }
        return null;
    }

    /// 잎의 수.
```

`layout_test`에 `expectHit`과 검사 12를 넣는다. 0 | (1 / 2) 트리에서 잎마다 네 모서리 칸 · 구분선 칸 넷 · 격자 밖 둘,
그리고 잎 하나짜리 트리의 네 자리다.

`old_string`(기준 파일 30줄부터):

```zig
    return error.WrongLeaf;
```

`new_string`:

```zig
    return error.WrongLeaf;
}

fn expectHit(what: []const u8, got: ?layout.Hit, want: ?layout.Hit) !void {
    if (std.meta.eql(got, want)) {
        if (got) |h| {
            std.debug.print("layout_test: hit {s} = leaf {d} at {d},{d} OK\n", .{ what, h.leaf, h.col, h.row });
        } else {
            std.debug.print("layout_test: hit {s} = none OK\n", .{what});
        }
        return;
    }
    std.debug.print("FAIL: hit {s} = {any}, want {any}\n", .{ what, got, want });
    return error.WrongHit;
```

`old_string`(기준 파일 281줄부터):

```zig
    std.debug.print("layout_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 12: 격자 칸 → 잎 (PD-M1) ──────────────────────────────────
    //
    // 포인터 아래 패널을 고르는 자리다(PD design 결정 5). 0 | (1 / 2)에서
    // 각 잎의 네 모서리 칸이 그 잎의 상대 칸 네 모서리가 되고, 구분선 칸과
    // 격자 밖은 null이다. 왼쪽은 0,0 77x47, 세로 구분선이 77열, 오른쪽 위가
    // 78,0 77x23, 가로 구분선이 23줄, 오른쪽 아래가 78,24 77x23이다(검사 9).
    {
        const one = layout.Tree.init();
        try expectHit("one leaf, top left", one.hit(WHOLE, 0, 0), .{ .leaf = 0, .col = 0, .row = 0 });
        try expectHit("one leaf, bottom right", one.hit(WHOLE, 154, 46), .{ .leaf = 0, .col = 154, .row = 46 });
        try expectHit("one leaf, past the right edge", one.hit(WHOLE, 155, 0), null);
        try expectHit("one leaf, past the bottom", one.hit(WHOLE, 0, 47), null);

        var t = layout.Tree.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .below, WHOLE);
        // 왼쪽 잎 0의 네 모서리.
        try expectHit("leaf 0 top left", t.hit(WHOLE, 0, 0), .{ .leaf = 0, .col = 0, .row = 0 });
        try expectHit("leaf 0 top right", t.hit(WHOLE, 76, 0), .{ .leaf = 0, .col = 76, .row = 0 });
        try expectHit("leaf 0 bottom left", t.hit(WHOLE, 0, 46), .{ .leaf = 0, .col = 0, .row = 46 });
        try expectHit("leaf 0 bottom right", t.hit(WHOLE, 76, 46), .{ .leaf = 0, .col = 76, .row = 46 });
        // 오른쪽 위 잎 1의 네 모서리.
        try expectHit("leaf 1 top left", t.hit(WHOLE, 78, 0), .{ .leaf = 1, .col = 0, .row = 0 });
        try expectHit("leaf 1 top right", t.hit(WHOLE, 154, 0), .{ .leaf = 1, .col = 76, .row = 0 });
        try expectHit("leaf 1 bottom left", t.hit(WHOLE, 78, 22), .{ .leaf = 1, .col = 0, .row = 22 });
        try expectHit("leaf 1 bottom right", t.hit(WHOLE, 154, 22), .{ .leaf = 1, .col = 76, .row = 22 });
        // 오른쪽 아래 잎 2의 네 모서리.
        try expectHit("leaf 2 top left", t.hit(WHOLE, 78, 24), .{ .leaf = 2, .col = 0, .row = 0 });
        try expectHit("leaf 2 top right", t.hit(WHOLE, 154, 24), .{ .leaf = 2, .col = 76, .row = 0 });
        try expectHit("leaf 2 bottom left", t.hit(WHOLE, 78, 46), .{ .leaf = 2, .col = 0, .row = 22 });
        try expectHit("leaf 2 bottom right", t.hit(WHOLE, 154, 46), .{ .leaf = 2, .col = 76, .row = 22 });
        // 구분선 칸.
        try expectHit("vertical separator, top", t.hit(WHOLE, 77, 0), null);
        try expectHit("vertical separator, bottom", t.hit(WHOLE, 77, 46), null);
        try expectHit("horizontal separator, left end", t.hit(WHOLE, 78, 23), null);
        try expectHit("horizontal separator, right end", t.hit(WHOLE, 154, 23), null);
        // 격자 밖.
        try expectHit("past the right edge", t.hit(WHOLE, 155, 10), null);
        try expectHit("past the bottom", t.hit(WHOLE, 10, 47), null);
    }

    std.debug.print("layout_test: all checks passed\n", .{});
```

확인.

```bash
git diff --stat terminal/src/layout.zig terminal/src/layout_test.zig
diff terminal/src/layout.zig /tmp/run/pdm1/term/src/layout.zig && echo SAME
diff terminal/src/layout_test.zig /tmp/run/pdm1/term/src/layout_test.zig && echo SAME
```

기대: `2 files changed, 81 insertions(+)`, `SAME` 둘.

## Task 4: `terminal/src/main.zig` — 편집 열둘

순서대로 넣는다. 줄 번호는 이 plan의 기준 파일에서 잰 참고값이고, 앞의 편집이 줄을 늘리므로 뒤로 갈수록 밀린다.
앵커는 바뀐 줄만 담아 짧다 — 한 줄짜리 `old_string`도 파일에 정확히 한 번 나오는 것을 기계로 확인했다(Task 0-3).

### 4-1. `renderFinish` — 화살표를 `present` 앞에(E1 · E2)

인자 둘(`sprite` · `want`)을 더하고, `drawStatus` 뒤 · `present` 앞에서 `forget` → `show`한다(확정 3의 셋째 줄). E1의
`old_string`은 함수 머리의 닫는 줄 하나다.

E1 — `old_string`(기준 파일 477줄부터):

```zig
) !?PromptInk {
```

`new_string`:

```zig
    // 화살표(PD-M1). `want`이 null이면 안 그린다. 화면 전체를 방금 다시
    // 칠했으므로 옛 화살표는 이미 지워졌고 저장한 픽셀은 낡았다 — 되돌리지
    // 않고 잊는다(`forget`). 그리고 `present` 바로 앞에서 새로 저장하고 그린다
    // (PD design 결정 4).
    sprite: *pointer.Sprite,
    want: ?pointer.Spot,
) !?PromptInk {
```

E2 — `old_string`(기준 파일 486줄부터):

```zig
    try drawStatus(fb, cache, st);

```

`new_string`:

```zig
    try drawStatus(fb, cache, st);

    // 무엇보다 위에 그린다 — 프롬프트와 상태 줄 뒤, `present` 앞이다. 그래서
    // 아래 덤프들이 화살표 픽셀을 읽는다(design 결정 4가 받아들였다). 화살표가
    // 보이는 것은 사람이 포인터를 움직인 뒤뿐이라 다른 체인의 덤프는 안 바뀐다.
    sprite.forget();
    if (want) |s| sprite.show(fb, s);
```

### 4-2. 포인터 절의 새 것들(E3)

`PointerRound`에 `woke`, 그 뒤에 `pointer_drawn` · `WHEEL_ROWS` · `GridCell` · `gridCell` · `pointerCount` ·
`dumpPointerAt`을 넣는다. `dumpPointerAt`이 M0의 `at` 줄을 대신한다(확정 5). `pointer_drawn`은 확정 4의 끝.

E3 — `old_string`(기준 파일 1455줄부터):

```zig
    wheel: i32 = 0,
};
```

`new_string`:

```zig
    wheel: i32 = 0,
    /// 이 회차에 포인터가 움직였거나 버튼이 눌렸다. 화살표가 보이는 조건
    /// 2다(PD design 결정 4). 휠만 굴린 회차는 아니다.
    woke: bool = false,
};

/// 이 회차 앞에 화면에 화살표가 그려져 있었는가(PD-M1). `open` 줄의 `shown=`이
/// 이것을 찍는다. 장치를 여는 자리(처음 훑기 · 핫플러그)가 여럿이라 인자로
/// 나르지 않고 파일 하나의 값으로 둔다 — 쓰는 자리는 `main`의 포인터 분기
/// 하나다.
var pointer_drawn = false;

/// 휠 한 눈금이 움직이는 줄 수(PD design 결정 7). xterm 계열이 흔히 쓰는
/// 값이다. 설정은 비목표 7이다.
const WHEEL_ROWS: isize = 3;

/// 격자의 칸 하나. 패널이 아니라 격자 전체의 좌표다.
const GridCell = struct { col: u16, row: u16 };

/// 프레임버퍼 픽셀을 격자 칸으로 바꾼다(PD design 결정 5). 여백 · 상태 줄
/// 위면 null이다.
///
/// `paneOrigin`의 역이고 같은 상수 넷(`GRID_X` · `GRID_Y` · `CELL_W` ·
/// `ROW_HEIGHT`)을 쓴다. 다른 상수를 쓰면 화살표 끝과 고른 칸이 한 칸
/// 어긋나고, 그 어긋남은 글자만 보는 판정으로는 안 보인다.
fn gridCell(x: u32, y: u32, cols: u16, rows: u16) ?GridCell {
    if (x < GRID_X or y < GRID_Y) return null;
    const col = (x - GRID_X) / CELL_W;
    const row = (y - GRID_Y) / ROW_HEIGHT;
    if (col >= cols or row >= rows) return null;
    return .{ .col = @intCast(col), .row = @intCast(row) };
}

/// 열린 포인터 장치의 수. 0이면 화살표가 안 보인다(보이는 조건 1).
fn pointerCount(devs: *const [pointer.MAX_DEVICES]?PointerDev) usize {
    var n: usize = 0;
    for (devs) |slot| {
        if (slot != null) n += 1;
    }
    return n;
}

/// 이 회차의 `pointer> at` 줄(PD design 결정 10). 그린 뒤에 부른다 —
/// `ink`가 프레임버퍼를 되읽는다.
///
/// 이벤트마다가 아니라 회차마다 한 줄이다. 이벤트마다 찍으면 마우스의 보고
/// 빈도(수백 Hz)가 그대로 줄 수가 된다(design 결정 3).
///
/// 찍는 회차가 둘이다. 포인터 이벤트가 있던 회차, 그리고 화살표가 숨은
/// 회차(키를 쳤다 · 장치가 다 빠졌다). 뒤의 것이 없으면 키를 친 회차에는
/// 포인터 이벤트가 없어 줄이 안 나오고, 다음 움직임은 화살표를 다시
/// 보이게 하므로 "숨었다"를 볼 창구가 없다.
///
/// `shown`은 지금 화면에 화살표가 그려져 있는가다. `ink`는 직전 자리와 지금
/// 자리의 사각형 둘에서 센 화살표 색 픽셀 수다(`Sprite.ink`).
fn dumpPointerAt(
    fb: drm.Framebuffer,
    state: *const pointer.Pointer,
    round: PointerRound,
    sprite: *const pointer.Sprite,
    before: ?pointer.Spot,
) void {
    const hid = before != null and sprite.at == null;
    if (round.frames == 0 and !hid) return;
    std.debug.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown={d} ink={d}\n", .{
        state.x,                         state.y,                state.buttons.bits(), round.wheel,
        @intFromBool(sprite.at != null), sprite.ink(fb, before),
    });
}
```

### 4-3. `open` 줄의 `shown`(E4)

E4 — `old_string`(기준 파일 1520줄부터):

```zig
    // `shown=0`은 화살표가 아직 안 보인다는 뜻이다. 열린 뒤 움직여야 보인다
    // (design 결정 4의 보이는 조건 2). PD-M0은 아예 안 그리므로 언제나 0이다.
    std.debug.print("terminal: pointer> open {s} kind=mouse shown=0 name={s}\n", .{ path, dev_name });
```

`new_string`:

```zig
    // `shown`은 지금 화면에 화살표가 있는가다(PD-M1, `pointer_drawn`). 첫
    // 장치면 0이다 — 열린 뒤 움직여야 보인다(design 결정 4의 보이는 조건 2).
    // 화살표가 보이는 동안 둘째 장치를 꽂으면 1이다.
    std.debug.print("terminal: pointer> open {s} kind=mouse shown={d} name={s}\n", .{ path, @intFromBool(pointer_drawn), dev_name });
```

### 4-4. 드레인이 `woke`를 세운다(E5)

E5 — `old_string`(기준 파일 1587줄부터):

```zig
            round.wheel +|= e.wheel;
```

`new_string`:

```zig
            round.wheel +|= e.wheel;
            if (e.moved or e.pressed.bits() != 0) round.woke = true;
```

### 4-5. `sprite`와 `pointer_shown`(E6)

E6 — `old_string`(기준 파일 1850줄부터):

```zig
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
```

`new_string`:

```zig
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
    // 화살표와 그 밑의 픽셀(PD-M1, design 결정 4).
    var sprite = pointer.Sprite.init(fb.width, fb.height);
    // 보이는 조건 2 · 3(design 결정 4). 움직이거나 누르면 켜지고, 키보드가
    // PTY에 바이트를 보내면 꺼진다. 장치가 다 빠져도 꺼진다 — 다시 꽂은
    // 장치는 움직여야 보인다. 조건 1(장치가 하나 이상)은 `pointerCount`가 본다.
    var pointer_shown = false;
```

### 4-6. 키를 치면 숨긴다(E7)

E7 — `old_string`(기준 파일 1952줄부터):

```zig
                pty.write(focus.session.master_fd, keys.bytes);
```

`new_string`:

```zig
                pty.write(focus.session.master_fd, keys.bytes);
                // 치는 동안 화살표가 그 줄의 글자를 가리지 않게 숨긴다(보이는
                // 조건 3). 다음 움직임에 다시 보인다. 바이트가 나간 키만이다 —
                // 수정 키 · copy mode 명령 · 스크롤 · 패널 명령은 안 숨긴다.
                pointer_shown = false;
```

### 4-7. 포인터 분기 — `before_spot`, 보이는 조건, 휠(E8 · E9)

E9가 M0의 `at` 줄 블록(주석 넷과 `if` 블록)을 보이는 조건 두 줄과 휠 블록으로 바꾼다. 찍는 일은 `dumpPointerAt`이
루프 끝에서 한다. 핫플러그 드레인 줄(그 바로 앞)은 안 건드린다 — 조건 두 줄이 그 뒤라서, 같은 회차에 꽂힌 장치도
`pointerCount`에 든다.

E8 — `old_string`(기준 파일 2183줄부터):

```zig
        var round: PointerRound = .{};
```

`new_string`:

```zig
        var round: PointerRound = .{};
        // 이 회차 앞의 화살표 자리. `at` 줄의 `ink`가 이 사각형도 센다 — 옛
        // 자리를 못 지웠으면 그 자국이 여기 남는다(design 결정 10).
        const before_spot = sprite.at;
        pointer_drawn = before_spot != null;
```

E9 — `old_string`(기준 파일 2193줄부터):

```zig
        // 회차마다 한 줄이다. 이벤트마다 찍으면 마우스의 보고 빈도(수백 Hz)가
        // 그대로 줄 수가 된다(design 결정 3). PD-M0은 그리지 않으므로
        // `needs_redraw`를 안 켠다 — 화면이 한 픽셀도 안 바뀐다. 그래서
        // `shown`과 `ink`는 상수 0이다. PD-M1이 둘을 채운다(design 결정 10).
        if (round.frames > 0) {
            std.debug.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown=0 ink=0\n", .{
                pointer_state.x, pointer_state.y, pointer_state.buttons.bits(), round.wheel,
            });
        }
```

`new_string`:

```zig
        if (pointerCount(&pointer_devs) == 0) pointer_shown = false;
        if (round.woke) pointer_shown = true;
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
        }
        // `at` 줄은 그린 뒤에 찍는다(`dumpPointerAt`) — `ink`가 그린 결과를 센다.
```

### 4-8. 루프 끝 — 움직임만 있는 회차와 전체 프레임(E10~E12)

E10이 `if (!needs_redraw) continue;` 한 줄을 블록으로 바꾼다(확정 3의 표). E11은 `renderFinish`의 호출, E12는 덤프들
맨 뒤의 `at` 줄이다.

E10 — `old_string`(기준 파일 2311줄부터):

```zig
        if (!needs_redraw) continue;
```

`new_string`:

```zig
        // 화살표가 있어야 할 자리(PD design 결정 4). 보이는 조건 셋이 다
        // 맞아야 한다 — 장치가 있고, 움직였고, 그 뒤로 키를 안 쳤다.
        const want: ?pointer.Spot = if (pointer_shown and pointerCount(&pointer_devs) > 0)
            .{ .x = pointer_state.x, .y = pointer_state.y }
        else
            null;
        // 화면 전체를 다시 그릴 일이 없는 회차. 화살표만 고친다 — 저장한
        // 픽셀을 되돌리고, 새 자리 밑을 저장하고, 그리고, 내보낸다. 렌더도
        // 덤프도 없다(design 결정 4). 자리가 그대로면 아무것도 안 한다.
        if (!needs_redraw) {
            if (!pointer.sameSpot(sprite.at, want)) {
                sprite.restore(fb);
                if (want) |s| sprite.show(fb, s);
                try fb.present();
            }
            dumpPointerAt(fb, &pointer_state, round, &sprite, before_spot);
            continue;
        }
```

E11 — `old_string`(기준 파일 2397줄부터):

```zig
        const prompt_ink = try renderFinish(fb, &cache, prompt, status_line);
```

`new_string`:

```zig
        const prompt_ink = try renderFinish(fb, &cache, prompt, status_line, &sprite, want);
```

E12 — `old_string`(기준 파일 2431줄부터):

```zig
                last_glyph_count, cache.bitmap_bytes,
            });
        }
```

`new_string`:

```zig
                last_glyph_count, cache.bitmap_bytes,
            });
        }
        // 덤프들 뒤다. 게이트는 이 줄이 보이면 같은 프레임의 `scroll>`이 이미
        // 찍혔다고 읽는다(pointer/check.sh 검사 11).
        dumpPointerAt(fb, &pointer_state, round, &sprite, before_spot);
```

### 4-9. 확인

```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | rg '^-[^-]'
python3 /tmp/run/pdm1/anchors.py post "$PWD"
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build > /tmp/b.out 2>&1; echo "build=$?"; grep -a -E "error" -A3 /tmp/b.out | head -20
  zig build test > /tmp/t.out 2>&1; echo "test=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  grep -a -c "^layout_test: hit .* OK$" /tmp/t.out
  grep -a -E "all checks passed|^FAIL" /tmp/t.out'
```

기대.

- `--stat`: `1 file changed, 136 insertions(+), 13 deletions(-)`.
- `rg '^-[^-]'`: 아래 열세 줄이다(사본에서 `git diff --no-index`로 뽑았다). `open` 줄의 주석 둘과 print는 실제 값을
  찍는 줄로, M0의 `at` 줄 블록은 보이는 조건과 휠로, `if (!needs_redraw) continue;`는 블록으로, `renderFinish` 호출은
  인자 둘을 더한 줄로 바뀐다. M0 `at` 줄 블록의 닫는 `}`는 git이 휠 블록의 `}`와 짝지어 `-`로 안 보인다.

  ```
  -    // `shown=0`은 화살표가 아직 안 보인다는 뜻이다. 열린 뒤 움직여야 보인다
  -    // (design 결정 4의 보이는 조건 2). PD-M0은 아예 안 그리므로 언제나 0이다.
  -    std.debug.print("terminal: pointer> open {s} kind=mouse shown=0 name={s}\n", .{ path, dev_name });
  -        // 회차마다 한 줄이다. 이벤트마다 찍으면 마우스의 보고 빈도(수백 Hz)가
  -        // 그대로 줄 수가 된다(design 결정 3). PD-M0은 그리지 않으므로
  -        // `needs_redraw`를 안 켠다 — 화면이 한 픽셀도 안 바뀐다. 그래서
  -        // `shown`과 `ink`는 상수 0이다. PD-M1이 둘을 채운다(design 결정 10).
  -        if (round.frames > 0) {
  -            std.debug.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown=0 ink=0\n", .{
  -                pointer_state.x, pointer_state.y, pointer_state.buttons.bits(), round.wheel,
  -            });
  -        if (!needs_redraw) continue;
  -        const prompt_ink = try renderFinish(fb, &cache, prompt, status_line);
  ```
- `post: 21 edits, 0 bad`(Task 5까지 넣은 뒤에 21이다. 여기서는 `check.sh`의 둘이 아직이라 `check.sh edit 1 · 2`의
  `bad` 두 줄과 `post: 21 edits, 2 bad`가 나온다).
- `build=0`, `test=0`, `69`, `22`, `all checks passed` 셋, `FAIL` 0줄.

`build=0`이 아니면 그 에러 줄을 보고한다. 이 plan의 사본은 `exit=0`이었으므로(확정 10) 에러는 편집이 빗나간 것이다 —
`anchors.py post`가 `bad`라고 한 자리부터 본다.

## Task 5: `pointer/check.sh` · `check.sh`

### 5-1. `pointer/check.sh` — 통째로 다시 쓴다

M0의 머리(빌드 단계 · 포트 · `report_failure` · 도우미)는 거의 그대로이고, `# 검사 7의 재료` 줄부터 끝까지가 새것이다.
바뀐 머리는 넷이다 — 설명 주석, screendump 파일 넷과 `ARROW_INK=118`, 도우미 셋(`scroll_field` · `ppm_arrow` ·
`ppm_diff`)과 `report_failure`의 표식 둘, 부팅 마우스의 `id=pdboot`. 검사의 순서와 이유는 확정 9의 표다.

Write 도구로 아래 내용 그대로 덮어쓴다(실행 권한은 그대로 남는다).

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# PD 체인 — 포인터 장치(PD-M0 · M1). 열아홉번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU가 USB 마우스를 하나 붙인 채 뜬다(-usb -device usb-mouse)
#   → terminal이 uevent netlink 소켓을 열고 /dev/input을 훑는다
#   → 연 fd에 ioctl로 성질을 묻고 pointer.zig의 classify가 마우스만 고른다
#   → HMP mouse_move · mouse_button이 USB HID 보고가 되고 evdev 이벤트가 된다
#   → Mouse 디코더가 SYN_REPORT마다 Frame을 내고 Pointer가 좌표를 clamp한다
#   → poll 회차마다 `pointer> at` 한 줄
#   → 부팅 뒤에 device_add로 꽂은 둘째 마우스를 커널 uevent가 알리고 terminal이 연다
#   → device_del로 뽑으면 그 fd가 POLLHUP을 올리고 terminal이 닫는다
#   → 움직이면 화살표가 따라온다. 움직임만 있는 회차는 화면 전체를 다시
#     그리지 않고 화살표 자리만 고친다(save-under, PD-M1)
#   → 키를 치면 숨고, 휠은 포인터 아래 패널을 세 줄씩 움직인다(PD-M1)
#
# copy · pane 체인에 끼우지 않은 이유는 PD design 결정 10이다. 그 체인들의
# 판정은 포인터가 없는 화면을 전제하고, 이 체인은 PD-M1부터 화살표가 보이는
# 프레임을 일부러 만든다.
#
# 판정의 도구가 셋이다.
#   pointer> 줄 — open · skip · close · at(main.zig). 좌표는 게이트
#                프레임버퍼 1280 × 800에서 나온다. 출발은 가운데(640, 400)다.
#                at 줄의 ink는 terminal이 직전 자리와 지금 자리의 화살표 사각형
#                둘에서 되읽은 화살표 색 픽셀 수다. 다 보이면 118이다.
#   screendump — QEMU가 내보낸 화면이다. at 줄은 terminal이 프레임버퍼에서
#                되읽은 것이라 present가 빠져도 맞는다. 여기는 present가
#                있어야 바뀐다. perl로 화살표 색을 세거나 두 장을 비교한다.
#   scroll> 줄 — 휠이 움직인 뷰포트(검사 11 · 12).
#
# HMP의 대상 마우스. info mice의 별표가 HMP mouse_move가 가는 장치다.
# device_add로 꽂은 마우스가 대상이 되고 device_del 뒤에는 원래 마우스로
# 돌아온다(PD-M0 plan 확정 1). 검사 6이 그것을 쓴다 — 꽂은 뒤의 움직임은 새
# 장치로만 오므로 "새 fd를 읽는다"가 at 줄로 보인다.
#
# 이동은 한 번에 100 이하로 민다. QEMU는 127을 넘는 이동을 보고 여럿으로
# 쪼개 보내므로(plan 확정 2) 큰 수도 합은 같지만, 보고 하나가 명령 하나인
# 편이 로그를 읽기 쉽다.
#
# 디스크를 물지 않는다. 포인터는 설정과 무관하다.
#
# 화살표가 보이는 동안 terminal의 덤프(style> · pixel> · cursor>)는 화살표
# 픽셀을 읽는다(PD design 위험 6). 이 체인은 그 덤프로 판정하지 않는다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 분류 · 디코더 · clamp는 여기서 먼저 걸러진다(pointer_test) — 부팅 전에
# 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 열여덟 체인이 45455~45487을 쓴다. 45489는 PD-M3의 부팅 B 몫이다(design 결정 10).
MONITOR_PORT=45488

REPO_ROOT="$(cd .. && pwd)"
# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로
# 넘긴다. out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다
# (terminal/check.sh와 같은 자리).
SCREENS_DIR="${REPO_ROOT}/out/pd"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
MOVED="${SCREENS_DIR}/moved.ppm"
HIDDEN="${SCREENS_DIR}/hidden.ppm"
GONE="${SCREENS_DIR}/gone.ppm"
rm -f "$BEFORE" "$MOVED" "$HIDDEN" "$GONE"

# 화살표가 다 보일 때의 ink. pointer.zig의 ARROW_INK와 같은 수다(테두리 49 +
# 안쪽 69). 모양을 고치면 함께 고친다 — pointer_test가 그 상수를 먼저 본다.
ARROW_INK=118

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "input: QEMU QEMU USB Mouse" \
    "terminal: screen>" \
    "terminal: pointer> open" \
    "terminal: pointer> skip" \
    "terminal: pointer> at" \
    "terminal: pointer> close" \
    "terminal: scroll>" \
    "terminal: copy> enter" \
    "terminal: pointer> uevent failed" \
    "terminal: pointer> scan failed"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- kernel mouse lines ---"
  grep -aE 'input: QEMU QEMU USB Mouse|USB disconnect' "$LOG" | tr -d '\r'
  echo "--- pointer lines ---"
  grep -a 'terminal: pointer>' "$LOG" | tr -d '\r' | tail -n 30
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# pointer> 줄 중 접두가 맞는 것의 개수. 인자는 `open ` · `close ` · `at `처럼
# 동사와 공백이다.
pointer_count() {
  grep -ac "terminal: pointer> $1" "$LOG" || true
}

# 마지막 at 줄. 값이 줄 끝까지 가므로 \r를 지운다(HI-M1 실측 4).
last_at() {
  grep -a 'terminal: pointer> at ' "$LOG" | tail -n 1 | tr -d '\r'
}

# 커널이 만든 USB 마우스 입력 장치의 수. 검사 6이 "QEMU · 커널이 둘째
# 마우스를 안 만들었다"와 "terminal이 그것을 안 열었다"를 가르는 데 쓴다.
kernel_mice() {
  grep -ac 'input: QEMU QEMU USB Mouse as' "$LOG" || true
}

screen_lines() {
  grep -ac 'terminal: screen>' "$LOG" || true
}

# 마지막 scroll> 줄의 값 하나(copy/check.sh의 scroll_field와 같다).
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | tr -d '\r' | sed -E "s/.*$1=([0-9]+).*/\1/"
}

# screendump(P6) 하나에서 화살표 색(POINTER_FILL FCFCF4 · POINTER_EDGE 040810)인
# 픽셀의 수.
ppm_arrow() {
  perl -e '
    open(my $fh, "<:raw", $ARGV[0]) or die "$ARGV[0]: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+\d+\s+\d+\s+\d+\s//s or die "$ARGV[0]: not a P6 ppm\n";
    my $n = 0;
    for my $p (unpack("(a3)*", $d)) { $n++ if $p eq "\xFC\xFC\xF4" or $p eq "\x04\x08\x10"; }
    print "$n\n";' "$1"
}

# 두 screendump의 차이를 한 줄로 낸다.
#   n=다른 픽셀 수 box=x0,y0 x1,y1(그 경계 사각형, 양 끝 포함) other=둘째 장에서
#   화살표 색이 아닌 것의 수
# 같으면 n=0 box=-1,-1 -1,-1 other=0이다.
ppm_diff() {
  perl -e '
    sub load {
      open(my $fh, "<:raw", $_[0]) or die "$_[0]: $!\n";
      local $/; my $d = <$fh>;
      $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$_[0]: not a P6 ppm\n";
      return ($1, $d);
    }
    my ($w, $a) = load($ARGV[0]);
    my (undef, $b) = load($ARGV[1]);
    die "the two screendumps differ in size\n" if length($a) != length($b);
    my ($n, $other, $x0, $y0, $x1, $y1) = (0, 0, -1, -1, -1, -1);
    for (my $i = 0; $i < length($a); $i += 3) {
      my $q = substr($b, $i, 3);
      next if substr($a, $i, 3) eq $q;
      my $x = ($i / 3) % $w;
      my $y = int($i / 3 / $w);
      $x0 = $x if $x0 < 0 or $x < $x0;
      $x1 = $x if $x > $x1;
      $y0 = $y if $y0 < 0;
      $y1 = $y;
      $n++;
      $other++ unless $q eq "\xFC\xFC\xF4" or $q eq "\x04\x08\x10";
    }
    print "n=$n box=$x0,$y0 $x1,$y1 other=$other\n";' "$1" "$2"
}

# 마지막 at 줄이 패턴(ERE)에 맞을 때까지 기다린다. 있으면 0, 15초가 지나면 1.
# gate_lib.sh의 wait_for_screen과 같은 이유로 고정 sleep을 안 쓴다.
wait_for_at() {
  local pattern="$1" i line
  for i in $(seq 1 150); do
    line="$(last_at)"
    if grep -aqE -- "$pattern" <<<"$line"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초.
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aE -- "$pattern" "$LOG" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 어떤 함수가 돌려주는 수가 기준 이상이 될 때까지 기다린다. 15초.
wait_for_count() {
  local fn="$1" arg="$2" want="$3" i
  for i in $(seq 1 150); do
    if [ "$("$fn" "$arg")" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# HMP 명령 하나. 키와 달리 로그가 자라기를 기다리지 않는다 — 결과는 부르는
# 쪽이 wait_for_at으로 본다.
hmp() {
  echo "$1" >&3
  sleep 0.05
}

# screendump 하나를 뜨고 파일이 생길 때까지 기다린다. 10초.
screendump() {
  local out="$1" i
  echo "screendump ${out}" >&3
  for i in $(seq 1 100); do
    if [ -s "$out" ]; then sleep 0.2; return 0; fi
    sleep 0.1
  done
  return 1
}

qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -usb -device usb-mouse,id=pdboot \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "the shell prompt never showed up"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 검사 1: 부팅 때의 USB 마우스를 열고, 키보드와 전원 버튼은 건너뛴다 ──
#
# 마우스는 terminal보다 먼저 생긴다(plan 확정 3) — 처음 훑기가 연다. 늦게
# 생겨도 uevent가 연다. 어느 쪽이든 같은 줄이다.
#
# "정확히 하나"가 이 검사의 본체다. classify가 EV_KEY만 보면 전원 버튼과
# 키보드도 열려 셋이 된다(mutation 1).
echo "=== boot: the USB mouse is open, the keyboard and the power button are not ==="
wait_for_log 'terminal: pointer> open /dev/input/event[0-9]+ kind=mouse shown=0 name=QEMU QEMU USB Mouse' ||
  report_failure "terminal never opened the USB mouse (no 'pointer> open … kind=mouse shown=0 name=QEMU QEMU USB Mouse')"
OPENS="$(pointer_count 'open ')"
[ "$OPENS" -eq 1 ] ||
  report_failure "expected exactly one 'pointer> open' at boot, got ${OPENS}"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=AT Translated Set 2 keyboard' "$LOG" >/dev/null ||
  report_failure "the AT keyboard was not skipped as kind=none"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=Power Button' "$LOG" >/dev/null ||
  report_failure "the power button was not skipped as kind=none"
[ "$(pointer_count 'close ')" -eq 0 ] ||
  report_failure "a pointer device was closed before anything was unplugged"
[ "$(pointer_count 'at ')" -eq 0 ] ||
  report_failure "an 'at' line showed up before the mouse moved: $(last_at)"
MOUSE_PATH="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*open ([^ ]+) .*/\1/')"
echo "boot mouse: ${MOUSE_PATH}"

# ── 검사 7: 움직이기 전에는 화살표가 없다 ─────────────────────────────
#
# 보이는 조건 2(PD design 결정 4). 장치가 열려 있어도 움직이거나 누르기
# 전에는 안 그린다. 그래서 포인터 장치를 가진 체인도 사람이 손대기 전의
# 화면은 포인터 없는 부팅과 같다. 처음부터 그리면(mutation 1) 첫 프레임이
# 가운데(640, 400)에 화살표를 얹고 여기서 그 픽셀이 세어진다.
#
# pane> 줄이 포인터 없는 부팅의 그것과 글자까지 같은 것도 본다 — 그 값은
# pane/check.sh 검사 1과 PD-M0 plan 확정 3이 본 것이다.
echo "=== before any move: no arrow on the screen ==="
SCREENS_BEFORE_MOVES="$(screen_lines)"
screendump "$BEFORE" || report_failure "screendump did not write ${BEFORE}"
PIX="$(ppm_arrow "$BEFORE")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen has ${PIX} arrow-colored pixels before the mouse moved; the arrow must wait for the first move"
PANE_LINE="$(grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r')"
[ "$PANE_LINE" = "terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 sep ink=0" ] ||
  report_failure "the pane> line is '${PANE_LINE}', not the one a boot without a mouse prints"
echo "no arrow yet: ${PIX} arrow pixels on the screen"

# ── 검사 2 · 8: 움직이면 화살표가 나타나고, 옛 자리는 깨끗하다 ─────────
#
# 출발이 가운데(640, 400)라서 10, 5를 밀면 650, 405다. 첫 움직임에 화살표가
# 다 보인다 — ink가 118이다.
#
# 둘째 움직임은 50, 50이다. 화살표가 19픽셀 높이라 두 사각형이 안 겹친다.
# save-under가 옛 자리를 되돌리지 않으면(mutation 2) 옛 화살표가 남아 ink가
# 236이 된다. 그리고 screendump로 같은 것을 한 번 더 본다 — 움직이기 전
# 화면과 다른 픽셀이 정확히 화살표 118개이고, 전부 700,455의 12 × 19 안이다.
# at 줄은 terminal의 되읽기라 present가 빠져도 맞지만, screendump는 present가
# 있어야 바뀐다.
echo "=== mouse_move 10 5: the arrow shows up ==="
hmp "mouse_move 10 5"
wait_for_at "^terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_move 10 5' the last at line is '$(last_at)', expected 'at x=650 y=405 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}' (start 640,400)"
echo "moved: $(last_at)"

echo "=== mouse_move 50 50: the old spot is clean ==="
hmp "mouse_move 50 50"
wait_for_at '^terminal: pointer> at x=700 y=455 ' ||
  report_failure "after 'mouse_move 50 50' the last at line is '$(last_at)', expected x=700 y=455"
[ "$(last_at)" = "terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after the second move the at line is '$(last_at)'; ink must stay ${ARROW_INK} (more means the old arrow was left behind)"
screendump "$MOVED" || report_failure "screendump did not write ${MOVED}"
DIFF="$(ppm_diff "$BEFORE" "$MOVED")"
[ "$DIFF" = "n=${ARROW_INK} box=700,455 711,473 other=0" ] ||
  report_failure "the screen after two moves differs from the one before them by '${DIFF}', expected 'n=${ARROW_INK} box=700,455 711,473 other=0' (the arrow alone, at 700,455)"
echo "moved again: $(last_at)"
echo "screen diff: ${DIFF}"

# ── 검사 3: 버튼 ──────────────────────────────────────────────────────
#
# HMP mouse_button의 비트(1 왼쪽)가 buttons=의 비트와 같다. 누름 뒤 뗌까지 본다 —
# 누름만 보면 "버튼이 영영 눌린 채"도 통과한다. 자리가 안 바뀌므로 화살표는
# 그대로다.
echo "=== mouse_button 1, then 0 ==="
hmp "mouse_button 1"
wait_for_at "^terminal: pointer> at x=700 y=455 buttons=1 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_button 1' the last at line is '$(last_at)', expected buttons=1 at 700,455 with the arrow shown"
hmp "mouse_button 0"
wait_for_at "^terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_button 0' the last at line is '$(last_at)', expected buttons=0"
echo "button: pressed and released"

# ── 검사 5 · 10: 좌표는 화면 밖으로 안 나가고, 화살표는 가장자리에서 잘린다 ──
#
# 왼쪽 위로 800씩 밀면 0, 0에 붙는다. 화살표는 오른쪽 아래로 뻗으므로 다
# 보인다. 오른쪽 아래로 1300씩 밀면 1279, 799다. 그 자리에서는 hotspot 한
# 픽셀만 화면 안에 남는다 — ink=1이다. 자르기가 없으면 프레임버퍼 밖에 써서
# 게스트가 죽는다(setPixel에 범위 검사가 없다).
echo "=== clamp to the top left and the bottom right ==="
for _ in $(seq 1 8); do hmp "mouse_move -100 -100"; done
wait_for_at "^terminal: pointer> at x=0 y=0 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after eight 'mouse_move -100 -100' the last at line is '$(last_at)', expected x=0 y=0 with the whole arrow"
for _ in $(seq 1 13); do hmp "mouse_move 100 100"; done
wait_for_at '^terminal: pointer> at x=1279 y=799 ' ||
  report_failure "after thirteen 'mouse_move 100 100' the last at line is '$(last_at)', expected x=1279 y=799"
[ "$(last_at)" = "terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1" ] ||
  report_failure "at the bottom right corner the at line is '$(last_at)'; only the tip pixel fits, so ink must be 1"
echo "clamped: $(last_at)"

# ── 검사 7의 둘째: 움직임만으로는 화면 전체를 다시 그리지 않는다 ───────
#
# 여기까지 포인터만 움직였다. save-under는 화살표 자리만 고치고 present한다
# (PD design 결정 4). 화면 전체를 다시 그리면 screen> 줄이 는다.
echo "=== moves alone do not render a frame ==="
[ "$(screen_lines)" -eq "$SCREENS_BEFORE_MOVES" ] ||
  report_failure "pointer moves made the terminal render whole frames (screen> ${SCREENS_BEFORE_MOVES} -> $(screen_lines)); a move alone must only touch the arrow"
echo "no frame: screen> stayed at ${SCREENS_BEFORE_MOVES} across $(pointer_count 'at ') at lines"

# ── 검사 6: 부팅 뒤에 꽂고 뺀다 ───────────────────────────────────────
#
# 꽂으면 커널 uevent(`add` · `DEVNAME=input/event3`)가 오고 terminal이 둘째
# open을 찍는다. 화살표가 오른쪽 아래 끝에 보이는 중이라 그 줄은 shown=1이다.
# 커널 줄을 함께 세는 것은 "QEMU · 커널이 마우스를 안 만들었다"와 "terminal이
# 안 열었다"를 가르기 위해서다.
#
# 빼면 그 fd가 POLLHUP · POLLERR을 올리고 terminal이 close를 찍는다. 마우스가
# 하나 남으므로 화살표는 그대로다.
echo "=== device_add, then device_del ==="
KERNEL_MICE="$(kernel_mice)"
hmp "device_add usb-mouse,id=pdhot"
if ! wait_for_count pointer_count 'open ' 2; then
  if [ "$(kernel_mice)" -le "$KERNEL_MICE" ]; then
    report_failure "device_add did not give the guest a second USB mouse (kernel 'input:' lines stayed at ${KERNEL_MICE})"
  fi
  report_failure "the kernel registered a second mouse but terminal never opened it (no second 'pointer> open')"
fi
NEW_LINE="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r')"
NEW_PATH="$(sed -E 's/.*open ([^ ]+) .*/\1/' <<<"$NEW_LINE")"
case "$NEW_LINE" in
  *" kind=mouse shown=1 name=QEMU QEMU USB Mouse") ;;
  *) report_failure "the hotplugged device opened as '${NEW_LINE}', expected kind=mouse shown=1 (the arrow is on the screen)" ;;
esac
[ "$NEW_PATH" != "$MOUSE_PATH" ] ||
  report_failure "the hotplugged mouse reused the open path ${MOUSE_PATH}"
echo "plugged: ${NEW_LINE}"

# HMP의 대상이 새 마우스로 갔다(PD-M0 plan 확정 1). 이 움직임은 새 fd로만
# 온다. 1269, 789에서는 화살표의 왼쪽 위 11 × 11만 화면 안이다 — 66픽셀이다.
hmp "mouse_move -10 -10"
wait_for_at '^terminal: pointer> at x=1269 y=789 ' ||
  report_failure "a move on the hotplugged mouse never reached the pointer (last at: '$(last_at)')"
[ "$(last_at)" = "terminal: pointer> at x=1269 y=789 buttons=0 wheel=0 shown=1 ink=66" ] ||
  report_failure "at 1269,789 the at line is '$(last_at)'; the arrow's top left 11 x 11 holds 66 arrow pixels"

hmp "device_del pdhot"
wait_for_log "terminal: pointer> close ${NEW_PATH}" ||
  report_failure "the unplugged mouse was never closed (no 'pointer> close ${NEW_PATH}')"
[ "$(pointer_count 'close ')" -eq 1 ] ||
  report_failure "expected one 'pointer> close', got $(pointer_count 'close ')"
echo "unplugged: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

# 대상이 원래 마우스로 돌아왔다. 그 fd가 아직 열려 있고 읽힌다.
hmp "mouse_move 10 10"
wait_for_at "^terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1\$" ||
  report_failure "the boot mouse stopped moving the pointer after the unplug (last at: '$(last_at)')"

# ── 검사 9: 키를 치면 화살표가 숨는다 ─────────────────────────────────
#
# 보이는 조건 3(PD design 결정 4). PTY로 바이트가 나간 회차에 숨는다. 그
# 회차에는 포인터 이벤트가 없지만 숨은 회차라서 at 줄이 한 번 찍힌다
# (main.zig의 dumpPointerAt). ink=0은 옛 자리를 되돌렸다는 뜻이다.
#
# 패널 가운데쯤(679, 499)으로 옮긴 뒤 친다. echo의 출력이 오는 것은 빠진
# 장치 뒤에도 키보드와 PTY가 돈다는 것이기도 하다(검사 6의 마지막 확인).
echo "=== typing hides the arrow ==="
for _ in $(seq 1 6); do hmp "mouse_move -100 -50"; done
wait_for_at "^terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after six 'mouse_move -100 -50' the last at line is '$(last_at)', expected x=679 y=499 with the whole arrow"
ATS="$(pointer_count 'at ')"
type_keys e c h o spc p d minus h i d e minus o k ret
wait_for_screen '\| pd-hide-ok \|' ||
  report_failure "the shell stopped answering after the unplug (no 'pd-hide-ok' output line)"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0" ] ||
  report_failure "after typing the last at line is '$(last_at)', expected 'at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0'"
[ "$(pointer_count 'at ')" -eq "$((ATS + 1))" ] ||
  report_failure "typing printed $(( $(pointer_count 'at ') - ATS )) at lines, expected exactly one (the round that hid the arrow)"
screendump "$HIDDEN" || report_failure "screendump did not write ${HIDDEN}"
PIX="$(ppm_arrow "$HIDDEN")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen still has ${PIX} arrow-colored pixels after typing"
echo "hidden: $(last_at)"

hmp "mouse_move 1 1"
wait_for_at "^terminal: pointer> at x=680 y=500 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "the next move did not bring the arrow back (last at: '$(last_at)')"
echo "shown again: $(last_at)"

# ── 검사 11: 휠은 포인터 아래 패널을 세 줄씩 움직인다 ──────────────────
#
# seq 200으로 스크롤백을 만든다. 바닥에 있으므로 offset은 total - len이다.
# 휠을 앞으로 한 눈금 밀면(REL_WHEEL +1) 위로 세 줄 — offset이 3 준다. 뒤로
# 한 눈금이면 되돌아온다. 휠 부호를 뒤집으면(mutation 3) 바닥에서 아래로
# 가려 하므로 offset이 그대로다. REL_WHEEL_HI_RES도 세면(mutation 4) 한
# 눈금이 120을 넘게 더해져 맨 위까지 간다.
#
# 뷰포트가 바뀌므로 그 회차는 화면 전체를 다시 그린다. at 줄은 덤프들
# 뒤에 찍히므로, 새 at 줄이 보이면 같은 프레임의 scroll> 줄은 이미 있다.
echo "=== wheel over the pane ==="
type_keys s e q spc 2 0 0 ret
wait_for_screen '\| 200 \| root@\(none\) ~#' ||
  report_failure "seq 200 did not finish (no '| 200 | root@(none) ~#' on the screen)"
sleep 1
hmp "mouse_move -1 -1"
wait_for_at "^terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "the move after seq 200 did not show the arrow (last at: '$(last_at)')"
OFF0="$(scroll_field offset)"
[ "$OFF0" -ge 3 ] ||
  report_failure "seq 200 left no scrollback to wheel through (scroll> offset=${OFF0})"

ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch up printed no at line (last at: '$(last_at)')"
OFF1="$(scroll_field offset)"
[ "$OFF1" -eq "$((OFF0 - 3))" ] ||
  report_failure "one wheel notch up moved the viewport from offset ${OFF0} to ${OFF1}, expected $((OFF0 - 3))"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after a wheel notch up the at line is '$(last_at)', expected wheel=1 with the arrow redrawn on the new frame"

ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 -1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch down printed no at line (last at: '$(last_at)')"
OFF2="$(scroll_field offset)"
[ "$OFF2" -eq "$OFF0" ] ||
  report_failure "one wheel notch down moved the viewport from offset ${OFF1} to ${OFF2}, expected back to ${OFF0}"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=-1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after a wheel notch down the at line is '$(last_at)', expected wheel=-1"
echo "wheel: offset ${OFF0} -> ${OFF1} -> ${OFF2}"

# ── 검사 11의 둘째: 키보드 copy mode인 패널에서는 휠을 무시한다 ─────────
#
# copy 커서는 뷰포트 좌표다(PD design 결정 7). 밖에서 뷰포트를 밀면 커서가
# 다른 글자를 가리키는데 선택은 안 따라온다. 그래서 그 패널은 안 움직인다 —
# offset이 그대로이고 화면을 다시 그리지도 않는다. 새 at 줄이 보이면 그
# 회차의 프레임(있었다면)은 이미 찍혔다.
echo "=== wheel in keyboard copy mode is ignored ==="
type_keys meta_l-shift-c
wait_for_log 'terminal: copy> enter' ||
  report_failure "Cmd+Shift+C did not enter copy mode (no 'copy> enter')"
sleep 1
OFF_C="$(scroll_field offset)"
SCREENS_C="$(screen_lines)"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch in copy mode printed no at line (last at: '$(last_at)')"
[ "$(scroll_field offset)" -eq "$OFF_C" ] ||
  report_failure "the wheel moved a pane in keyboard copy mode (offset ${OFF_C} -> $(scroll_field offset))"
[ "$(screen_lines)" -eq "$SCREENS_C" ] ||
  report_failure "the wheel in keyboard copy mode rendered a frame (screen> ${SCREENS_C} -> $(screen_lines))"
type_keys esc
wait_for_log 'terminal: copy> exit' ||
  report_failure "Esc did not leave copy mode (no 'copy> exit')"
echo "copy mode: offset stayed at ${OFF_C}"

# ── 검사 12: 여백 위의 휠은 아무 일도 안 한다 ─────────────────────────
#
# 위 여백(y < 20)으로 옮긴다. 그 픽셀은 어느 격자 칸도 아니라(gridCell이
# null) 휠이 갈 패널이 없다. offset도 screen> 줄 수도 그대로다. 스크롤백이
# 있고 바닥이라 잘못 움직이면 offset이 준다.
echo "=== wheel over the margin does nothing ==="
for _ in $(seq 1 5); do hmp "mouse_move 0 -100"; done
wait_for_at "^terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after five 'mouse_move 0 -100' the last at line is '$(last_at)', expected x=679 y=0"
OFF_M="$(scroll_field offset)"
SCREENS_M="$(screen_lines)"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch over the margin printed no at line (last at: '$(last_at)')"
[ "$(last_at)" = "terminal: pointer> at x=679 y=0 buttons=0 wheel=1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "over the margin the at line is '$(last_at)', expected wheel=1 at 679,0"
[ "$(scroll_field offset)" -eq "$OFF_M" ] ||
  report_failure "a wheel notch over the margin moved the viewport (offset ${OFF_M} -> $(scroll_field offset))"
[ "$(screen_lines)" -eq "$SCREENS_M" ] ||
  report_failure "a wheel notch over the margin rendered a frame (screen> ${SCREENS_M} -> $(screen_lines))"
echo "margin: offset stayed at ${OFF_M}"

# ── 검사 9의 둘째: 마지막 장치가 빠지면 숨는다 ────────────────────────
#
# 보이는 조건 1. 부팅 마우스를 뺀다. 그 회차에는 포인터 이벤트가 없지만
# 숨은 회차라서 at 줄이 한 번 찍힌다.
echo "=== the last mouse goes away ==="
hmp "device_del pdboot"
wait_for_log "terminal: pointer> close ${MOUSE_PATH}" ||
  report_failure "the boot mouse was never closed (no 'pointer> close ${MOUSE_PATH}')"
wait_for_at "^terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=0 ink=0\$" ||
  report_failure "after the last mouse went away the last at line is '$(last_at)', expected shown=0 ink=0"
screendump "$GONE" || report_failure "screendump did not write ${GONE}"
PIX="$(ppm_arrow "$GONE")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen still has ${PIX} arrow-colored pixels after the last mouse went away"
echo "gone: $(last_at)"

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
echo "PD-M1 check PASS"
```

### 5-2. `check.sh` — 문단 한 줄과 `CHAINS`

`old_string`(기준 파일 314줄부터):

```bash
# 움직이며, device_add · device_del로 부팅 뒤에 꽂고 뺀다. 판정은 terminal의
# pointer> 줄과 screendump 둘이다. 회차당 부팅 1회.
```

`new_string`:

```bash
# 움직이며, device_add · device_del로 부팅 뒤에 꽂고 뺀다. PD-M1부터 화살표가
# 포인터를 따라오고 휠이 패널을 움직인다. 판정은 terminal의 pointer> · scroll>
# 줄과 screendump 넷(perl로 화살표 색을 센다)이다. 회차당 부팅 1회.
```

`old_string`(기준 파일 338줄부터):

```bash
  "PD-M0:./pointer/check.sh"
```

`new_string`:

```bash
  "PD-M1:./pointer/check.sh"
```

### 5-3. 확인

```bash
bash -n pointer/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pointer/check.sh && require_no_early_exit_pipe ./pointer/check.sh &&
  require_explicit_nic ./pointer/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
ls -l pointer/check.sh | cut -c1-10
diff pointer/check.sh /tmp/run/pdm1/pointer/check.sh && echo SAME
git diff --stat pointer/check.sh check.sh
python3 /tmp/run/pdm1/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK`, 권한 `-rwxr-xr-x`, `SAME`, `2 files changed, 291 insertions(+),
73 deletions(-)`, `post: 21 edits, 0 bad`. `check.sh`는 `SAME`으로 안 본다 — PD-M0이 같은 파일의 다른 자리를 고쳤을 수
있어서 앵커 검사가 판정이다.

## Task 6: 체인 한 번과 regression 셋

체인은 하나씩 돈다. 넷이 같은 `kernel/initrd.cpio`를 다시 만들므로 겹쳐 돌리지 않는다. 커널은 PD-M0 뒤 그대로라
`kernel/build.sh`는 빌드 없이 지난다.

### 6-1. `pointer` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm1:/tmp/run/pdm1 -w /workspace tars-devcontainer bash -c '
    bash pointer/check.sh > /tmp/run/pdm1/impl/pointer.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^===|^FAIL|^boot mouse|^no arrow|^moved|^screen diff|^button|^clamped|^no frame|^plugged|^unplugged|^hidden|^shown again|^wheel:|^copy mode:|^margin:|^gone:|took about|PD-M1 check' /tmp/run/pdm1/impl/pointer.log
rg -a 'terminal: pointer> (open|skip|close|uevent|scan)' /tmp/run/pdm1/impl/pointer.log
```

기대: `exit=0`. 첫 `rg`는 아래 줄들이다(확정 11의 판이 찍은 그대로). `no frame` · `wheel` · `copy mode` · `margin`의 수는
그 회차의 값이고 판정은 그 수끼리의 관계(같다 · 3 준다)만 본다. 줄 번호와 `took about` 줄은 회차마다 다르다.

```
=== boot: the USB mouse is open, the keyboard and the power button are not ===
boot mouse: /dev/input/event2
=== before any move: no arrow on the screen ===
no arrow yet: 0 arrow pixels on the screen
=== mouse_move 10 5: the arrow shows up ===
moved: terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=118
=== mouse_move 50 50: the old spot is clean ===
moved again: terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=118
screen diff: n=118 box=700,455 711,473 other=0
=== mouse_button 1, then 0 ===
button: pressed and released
=== clamp to the top left and the bottom right ===
clamped: terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1
=== moves alone do not render a frame ===
no frame: screen> stayed at 3 across 25 at lines
=== device_add, then device_del ===
plugged: terminal: pointer> open /dev/input/event3 kind=mouse shown=1 name=QEMU QEMU USB Mouse
unplugged: terminal: pointer> close /dev/input/event3
=== typing hides the arrow ===
hidden: terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0
shown again: terminal: pointer> at x=680 y=500 buttons=0 wheel=0 shown=1 ink=118
=== wheel over the pane ===
wheel: offset 157 -> 154 -> 157
=== wheel in keyboard copy mode is ignored ===
copy mode: offset stayed at 157
=== wheel over the margin does nothing ===
margin: offset stayed at 157
=== the last mouse goes away ===
gone: terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=0 ink=0
PD-M1 check PASS
```

둘째 `rg`는 여섯 줄이다(`open …event2 … shown=0` · `skip` 둘 · `open …event3 … shown=1` · `close …event3` ·
`close …event2`).

### 6-2. regression — `render` · `copy` · `pane`

세 체인에는 포인터 장치가 없다. `pointer_shown`이 한 번도 안 켜지므로 `renderFinish`는 `forget`만 하고 아무것도 안
그린다 — 픽셀 판정이 한 픽셀도 안 바뀌어야 한다(design "검증"의 게이트 절). `render`는 픽셀 판정이 가장 많고, `copy`는
이 plan이 고친 키보드 분기와 `scroll>`을 쓰고, `pane`은 PTY가 여럿이다.

```bash
for ch in render copy pane; do
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm1:/tmp/run/pdm1 -w /workspace tars-devcontainer bash -c "
      bash $ch/check.sh > /tmp/run/pdm1/impl/$ch.log 2>&1; echo exit=\$?" ; } 2>&1 | tail -4
  rg -a 'check PASS|^TR-M2 PASS|^FAIL' /tmp/run/pdm1/impl/$ch.log | cut -c1-60
  rg -a -c 'terminal: pointer> (open|at) ' /tmp/run/pdm1/impl/$ch.log || echo "pointer open/at: 0"
done
```

기대(확정 11에서 본 그대로): 셋 다 `exit=0`. PASS 줄이 `TR-M2 PASS: colors reach the framebuffer, …`(render ·
앞 60자) · `CM-M2 check PASS` · `WP-M2 check PASS`이고, 셋 다 `pointer open/at: 0`이다. 로그의 마지막 줄은 QEMU의
`terminating on signal 15`라서 `tail -1`로 보지 않는다. 시간은 약 1분 47초 · 2분 50초 · 31초다. 빨개지면 그 로그의
`FAIL` 줄을 보고한다.

## Task 7: mutation 다섯

design 결정 10의 M1 네 줄과, 이 plan이 더한 하나(움직임 회차의 `present`를 뺀다 — screendump 판정이 `present`를
보는지 확인한다)다. 확정 12의 방법으로 넣는다. 사본은 `/tmp/run/pdm1/impl/mut/`에 만든다. 넷 다 돌리기 전에
`diff`로 편집이 정확히 한 줄 들어갔는지 본다 — `sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

| mutation | 심는 고장 | 고치는 줄 |
|---|---|---|
| 1 | 보이는 조건 2를 뺀다 — 처음부터 그린다 | `main.zig` `var pointer_shown = false;` → `true` |
| 2 | save-under의 되돌리기를 뺀다 | `main.zig` 움직임 회차의 `sprite.restore(fb);` 앞에 `if (pointer_state.w == 0)` |
| 3 | 휠 부호를 뒤집는다 | `main.zig` `scrollByRows(-WHEEL_ROWS * ` → `scrollByRows(WHEEL_ROWS * ` |
| 4 | `REL_WHEEL_HI_RES`도 센다 | `pointer.zig` `c.REL_WHEEL => …` → `c.REL_WHEEL, c.REL_WHEEL_HI_RES => …` |
| 5 | 움직임 회차의 `present`를 뺀다 | `main.zig` 움직임 회차의 `try fb.present();`(들여쓰기 16칸) 앞에 `if (pointer_state.w == 0)` |

mutation 4는 design이 "M0 디코더의 `else => {}`를 바꾼다"고 적은 것과 효과가 같다. `else => {},`는 `pointer.zig`에 세
번 나와서 `sd -F`로 한 자리만 고칠 수 없다. 그래서 `REL_WHEEL` 갈래에 `REL_WHEEL_HI_RES`를 더해 `else`에서 꺼낸다.

### 7-0. 사본을 만든다

```bash
M=/tmp/run/pdm1/impl/mut; mkdir -p $M
cp terminal/src/main.zig $M/main_m1.zig
cp terminal/src/main.zig $M/main_m2.zig
cp terminal/src/main.zig $M/main_m3.zig
cp terminal/src/pointer.zig $M/pointer_m4.zig
cp terminal/src/main.zig $M/main_m5.zig
cp pointer/check.sh $M/pointer_notest.sh
sd -F 'var pointer_shown = false;' 'var pointer_shown = true;' $M/main_m1.zig
sd -F '                sprite.restore(fb);' '                if (pointer_state.w == 0) sprite.restore(fb);' $M/main_m2.zig
sd -F 'scrollByRows(-WHEEL_ROWS * ' 'scrollByRows(WHEEL_ROWS * ' $M/main_m3.zig
sd -F 'c.REL_WHEEL => self.pending.wheel +|= value,' 'c.REL_WHEEL, c.REL_WHEEL_HI_RES => self.pending.wheel +|= value,' $M/pointer_m4.zig
sd -F '                try fb.present();' '                if (pointer_state.w == 0) try fb.present();' $M/main_m5.zig
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' $M/pointer_notest.sh
chmod +x $M/pointer_notest.sh
bash -c 'M=/tmp/run/pdm1/impl/mut
for p in "main.zig main_m1.zig" "main.zig main_m2.zig" "main.zig main_m3.zig" "pointer.zig pointer_m4.zig" "main.zig main_m5.zig"; do
  set -- $p; echo "== $2"; diff terminal/src/$1 $M/$2
done
echo "== pointer_notest.sh"; diff pointer/check.sh $M/pointer_notest.sh'
```

기대: 여섯 `diff`가 각각 한 줄의 차이다(`8f8a030` + 이 plan에서 `main.zig` 1936 · 2425 · 2301 · 2427줄, `pointer.zig`
189줄, 체인 71줄).

### 7-1. mutation 4 — 먼저 `pointer_test`

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm1/impl/mut/pointer_m4.zig:/workspace/terminal/src/pointer.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c '
  echo "mounted: $(grep -c "REL_WHEEL, c.REL_WHEEL_HI_RES" src/pointer.zig)"
  rm -rf .zig-cache zig-out
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -E "^FAIL|^error: [A-Z]" /tmp/t.out | head -3'
```

기대(확정 10 · 11에서 본 그대로): `mounted: 1`, `exit=1`, `FAIL: mouse_move 0 0 1 drops REL_WHEEL_HI_RES: got .{ .dx = 0, .dy
= 0, .wheel = 121, .buttons = … }, want .{ … .wheel = 1, … }`, `error: WrongFrame`. `121`은 `pointer_test` 검사 6이
먹이는 HI_RES 값 120에 `REL_WHEEL` 1을 더한 것이다.

### 7-2. 체인 넷

mutation 4는 `pointer_test`를 건너뛴 사본 체인으로, 1 · 2 · 3 · 5는 그대로의 체인으로 돌린다.

`-e m=$m`으로 번호를 컨테이너에 넘긴다 — 작은따옴표 안의 `$m`은 컨테이너에서 빈 값이 된다(PE-M1 실측 5). 모양은
PD-M0 plan Task 7-2와 같다.

```bash
M=/tmp/run/pdm1/impl/mut
run_mut() {  # 번호, 덮을 -v 인자들
  local m="$1"; shift
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm1:/tmp/run/pdm1 "$@" -e m="$m" \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: main=$(grep -c -E "var pointer_shown = true;|pointer_state.w == 0\) (sprite.restore|try fb.present)|scrollByRows\(WHEEL_ROWS" terminal/src/main.zig) pointer=$(grep -c "REL_WHEEL, c.REL_WHEEL_HI_RES" terminal/src/pointer.zig) notest=$(grep -c "^if false; then" pointer/check.sh)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash pointer/check.sh > /tmp/run/pdm1/impl/mut/m$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -a -n '^===|^FAIL' $M/m$m.log | tail -3
}
run_mut 1 -v $M/main_m1.zig:/workspace/terminal/src/main.zig:ro
run_mut 2 -v $M/main_m2.zig:/workspace/terminal/src/main.zig:ro
run_mut 3 -v $M/main_m3.zig:/workspace/terminal/src/main.zig:ro
run_mut 4 -v $M/pointer_m4.zig:/workspace/terminal/src/pointer.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 5 -v $M/main_m5.zig:/workspace/terminal/src/main.zig:ro
```

함수 정의가 zsh에서 문제가 되면 `bash -c '…'`로 감싸 친다. 한 판이 1분 20초~1분 30초였다(확정 11) — Bash 도구의 10분
상한 때문에 `run_mut`을 한 번에 하나씩 부른다. 판을 겹치지 않는다. 캐시를 지운 빌드는 Docker VM의 메모리를 거의 다
쓴다 — 로그에 `Killed`가 보이고 `FAIL: terminal build failed`로 끝나면 mutation의 결과가 아니라 메모리다. 다른
컨테이너가 없는지(`docker ps`) 보고 그 판만 다시 돌린다.

기대(확정 11에서 본 그대로. `157` · `154`는 그 회차의 offset이다).

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 처음부터 그린다 | `main=1 pointer=0 notest=0` | 검사 7. 첫 프레임이 (640, 400)에 화살표를 얹는다. 검사 1은 초록이다 — 처음 훑기는 첫 프레임보다 먼저라 `open` 줄은 `shown=0`이다 | `FAIL: the screen has 118 arrow-colored pixels before the mouse moved; the arrow must wait for the first move` |
| 2 되돌리기를 뺀다 | `main=1 pointer=0 notest=0` | 검사 8의 둘째 움직임. 첫 움직임은 지울 옛 자리가 없어 초록이다 | `FAIL: after the second move the at line is 'terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=236'; ink must stay 118 (more means the old arrow was left behind)` |
| 3 휠 부호 | `main=1 pointer=0 notest=0` | 검사 11. 바닥에서 아래로 가려 하므로 offset이 그대로다 | `FAIL: one wheel notch up moved the viewport from offset 157 to 157, expected 154` |
| 4 HI_RES도 센다 | `main=0 pointer=1 notest=1` | 검사 11. 한 눈금이 (1 + 120) × 3 = 363줄이 되어 맨 위까지 간다 | `FAIL: one wheel notch up moved the viewport from offset 157 to 0, expected 154` |
| 5 `present`를 뺀다 | `main=1 pointer=0 notest=0` | 검사 8의 screendump 차이. `at` 줄의 `ink=118`은 초록이다 — terminal의 되읽기는 `present`와 무관하다 | `FAIL: the screen after two moves differs from the one before them by 'n=0 box=-1,-1 -1,-1 other=0', expected 'n=118 box=700,455 711,473 other=0' (the arrow alone, at 700,455)` |

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

기대: `exit=0`, `69`, `initrd exit=0`. `git status`는 `M` 일곱(`check.sh` · `pointer/check.sh` · `terminal/src/layout.zig` ·
`terminal/src/layout_test.zig` · `terminal/src/main.zig` · `terminal/src/pointer.zig` · `terminal/src/pointer_test.zig`)과,
plan이 아직 commit 전이면 `??` 하나뿐이다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트
파일) 그 목록을 보고한다.

### 7-4. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력 넷.
- Task 1~5의 확인 출력(`--stat` · `SAME` · `anchors.py` · OK 줄 수 · `ENTRY-OK`).
- Task 6의 `exit=` · `real` · `rg` 출력.
- Task 7의 `diff` 여섯 · `mounted:` · `exit=` · `real` · `FAIL` 줄, 7-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 8: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고 Task 6의 로그를 대조한다.
2. 루트 게이트. 열아홉 체인 × 3이다. `pointer` 체인의 한 판이 M1에서 약 1분이다(확정 11의
   둘째 판 1분 4초, terminal 증분 빌드 포함). M0 판보다 얼마나 늘었는지는 재지 않았다 — 게이트의 시간으로 본다. `run_in_background`로 돌리고 `{ time …; }`로 감싼다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pd1.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pd1.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 3/3' /tmp/gate_pd1.log`가 19여야 하고 `PD-M1 check PASS`가 셋이어야 한다.
3. 실측 절 채우기.
4. commit. 넣는 것은 일곱 파일과 이 plan이다. `git add`는 경로를 하나씩 지정한다 — `out/pd/*.ppm`은 `out/`가
   gitignore라 안 들어가지만 경로를 좁혀 둔다.

## design과 다르게 적은 것

1. `Hit`이 `pointer.zig`가 아니라 `layout.zig`에 있다(확정 6).
2. `open` 줄의 `shown=`이 상수가 아니라 그 회차 앞의 그려진 상태다(파일 하나의 `pointer_drawn`). 화살표가 보이는 중에 꽂은 장치는 `shown=1`이다
   (확정 4).
3. `at` 줄이 숨은 회차에도 한 번 나온다(확정 5). design은 "포인터 이벤트가 있던 poll 회차마다 하나"였다.
4. 마지막 장치가 빠지면 조건 2도 꺼진다(lead가 정했다, 2026-10-05 — design 결정 4의 덧붙임은 lead가 닫을 때 한다). design의 조건 2는 "열린 뒤"라 적었고 다시 꽂은 경우를 따로 말하지 않았다
   (확정 4).
5. 조건 3을 끄는 자리가 `keys.bytes`의 블록 하나다. `Cmd+V`와 질의의 답은 PTY에 써도 안 숨긴다(확정 4, lead가 정했다, 2026-10-05).
6. 검사 7이 둘로 갈렸고(움직이기 전 화살표 색 0 · 움직임만으로는 `screen>`이 안 는다), M0의 검사 4가 검사 11로
   들어갔다. 더한 것이 둘이다 — 검사 9의 둘째(마지막 장치), 검사 11의 둘째(키보드 copy mode의 휠). 검사 7의
   바이트 비교는 두 screendump의 차이(`ppm_diff`)로 바뀌었다(확정 9).
7. mutation 4가 `else`가 아니라 `REL_WHEEL` 갈래를 고친다(Task 7). 효과는 같다. 그리고 mutation 5(움직임 회차의
   `present`를 뺀다)를 더했다.

## 이 milestone에서 안 하는 것

- 누름 · 끎 · 뗌의 의도 · `Gesture` · `copyEnterAt` · `copyPointTo` · `pointerMode` · 포커스 옮김 · 끄는 동안의 휠(PD-M2).
- 패널이 여럿일 때 휠이 포커스 아닌 패널을 움직이는 것의 게이트 검사. 코드는 이미 그렇게 하지만(확정 7) 체인은
  패널 하나로 본다. 구분선 위의 휠도 같다 — `layout_test`가 `hit`의 null을 본다.
- 터치패드(PD-M3).
- 부분 갱신. 움직임 회차의 save-under만 하고 출력 프레임은 지금처럼 다 그린다(design 위험 1).
- `drm.zig`의 `present`가 찍는 `kms: set crtc` 줄을 줄이는 것. 움직임 회차마다 한 줄이 늘지만 판정에 안 걸린다(확정 8).
- `docs/guides/lessons.md` · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design `Status:`(design "닫을 때").

## PD-M1이 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-05에 plan 그대로 했다. 편집은 plan의 `old_string` · `new_string`과 코드 블록을
스크립트로 뽑아 넣었고, 각 Task 끝의 사본 `diff`와 `anchors.py post`(21 edits, 0 bad)로 확인했다. lead가 파일 일곱을
planner의 검증 사본과 `cmp`해 전부 같음을 봤고, 지운 줄은 `check.sh` 셋 · `main.zig` 열셋 · `pointer/check.sh`의 M0 부분
69줄뿐이었다.

1. 호스트 검사. `pointer_test` OK 75(기준이 plan의 47이 아니라 53이었다 — M0 개정이 uevent 검사 여섯을 더한 뒤의 수.
   증가분 22는 plan과 같다), `layout_test`의 `hit` OK 22, `zig build` · `zig build test` exit 0.
2. `pointer` 체인 26.4초(terminal이 이미 빌드돼 있어 plan의 1분 4초보다 짧다). `at` 줄 — 첫 움직임 `x=650 y=405 shown=1
   ink=118` · 둘째 `x=700 y=455 shown=1 ink=118`(자국 없음) · 오른쪽 아래 끝 `x=1279 y=799 ink=1` · 글자를 친 뒤 `shown=0
   ink=0`. 휠 `offset` 157 → 154 → 157. `screen> stayed at 4`(plan 예시는 3 — 회차마다 다른 수이고 판정은 관계만 본다).
3. regression — `render` 1분 48초 · `copy` 2분 52초 · `pane` 34초, 셋 다 PASS이고 `pointer>` 줄 0.
4. mutation 다섯 전부 빨감, `Killed` 0번.

   | mutation | 잡은 자리 | 문구 | 시간 |
   |---|---|---|---|
   | 1 처음부터 그린다 | 검사 7 | `the screen has 118 arrow-colored pixels before the mouse moved` | 1분 22초 |
   | 2 되돌리기를 뺀다 | 검사 8 | `… shown=1 ink=236'; ink must stay 118 (more means the old arrow was left behind)` | 1분 22초 |
   | 3 휠 부호 반전 | 검사 11 | `one wheel notch up moved the viewport from offset 157 to 157, expected 154` | 1분 32초 |
   | 4 `REL_WHEEL_HI_RES`도 센다 | `pointer_test` 먼저(`.wheel = 121`), 끄면 검사 11 | `… from offset 157 to 0, expected 154` | 1분 24초 |
   | 5 움직임 회차의 `present`를 뺀다 | 검사 7의 screendump 비교 | `differs … by 'n=0 box=-1,-1 -1,-1 other=0', expected 'n=118 box=700,455 711,473 other=0'` | 1분 24초 |

5. plan의 기대와 다른 것은 수 둘(OK 기준 53 · `screen>` 4)과 `run_mut`의 `tail -5`가 `mounted:` 줄을 자르는 것(2번부터
   `tail -6`)뿐이었다.
6. 루트 게이트(3회 — `feedback_gate_runs`대로 3회로 도는 마지막 게이트): 열아홉 체인 3/3, `PD-M1 check PASS` 셋,
   `FAIL` 0줄, 1시간 8분 41초(2026-10-05, docker 작업 없이 단독). PD-M0 게이트의 1시간 8분 39초와 같다 — `pointer`
   체인에 검사 다섯이 늘었지만 부팅은 하나 그대로다.

## 닫을 때

PD-M1은 서브프로젝트를 닫지 않는다. 다음은 PD-M2 plan이다(design 결정 5 · 6, Opus 구현).
