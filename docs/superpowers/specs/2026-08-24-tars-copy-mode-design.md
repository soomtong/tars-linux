# TARS Copy Mode — Design

**Date:** 2026-08-24
**Status:** 설계 확정. **CM-M0 완료(2026-08-24)**, 다음은 CM-M1

## 한 줄 요약

**스크롤백 위에서 vim 방식으로 영역을 잡아 복사하고 `Cmd+V`로 셸에
붙여넣는다** — 그리고 그것을 왕복으로 증명한다. 복사한 글자가 붙여넣기를
거쳐 셸의 에코로 화면에 다시 나타나는 것까지 게이트가 본다.

## 배경

Terminal Rendering(TR-M0~M2)이 2026-08-24에 끝나면서 진행 중인 서브프로젝트가
없어졌다. `HANDOFF.md`가 남긴 후보 셋(copy mode · 빌드 크기와 게이트 시간 ·
렌더 성능 조사) 중 copy mode를 골랐다.

고른 이유는 셋이다.

1. **사용자가 직접 요청한 기능이고**(2026-08-15, `project_copy_mode`),
   그 문서가 적어 둔 선행 조건 셋 중 둘이 끝났다. 남은 것은 클립보드
   하나였다.
2. **통로가 이미 넓혀져 있다.** TR-M2가 `handleKey`의 반환을
   `Action = union(enum) { bytes, scroll }`로 넓혀 "PTY로 안 보내고 우리가
   처리한다"를 표현할 타입을 만들어 두었다. copy mode는 여기에 variant를
   더한다.
3. **커널을 안 건드린다.** 전부 게스트 사용자 공간 안이라 기존 일곱 체인에
   주는 충격이 작다.

## 출발 시점의 저장소 상태 (2026-08-24 실측)

- **`input.State`에 모드라는 개념이 없다.** `chord()`는 `Meta → Alt → Shift`
  순으로 보고, 앞 분기가 표에 없는 조합을 만나면 `null`로 끝낸다
  (`input.zig:366-411`). `Cmd`와 문자 키의 조합은 전부 비어 있다 — IP가
  이 자리를 일부러 지켜 왔다.
- **`vt.Screen`에 선택도 클립보드도 없다.** 뷰포트 조작
  (`scrollToTop`·`scrollToBottom`·`scrollByRows`·`scrollbar`)만 있다.
- **`main.zig`는 PTY 출력이 도착할 때마다 `scrollToBottom()`을 부른다**
  (`main.zig:450`, TR design 결정 13). 그 자리의 주석이 부수 효과를 하나
  적어 두었다 — **뷰포트가 history에 머무는 동안 가지치기가 일어나는 상황이
  이 한 줄로 구조적으로 안 생긴다.** copy mode는 이 호출을 억제해야 하므로,
  그 창을 여는 일이 된다(아래 위험 1).
- **`cells()`는 셀마다 `fg`·`bg`를 확정해서 넘긴다.** 커서와 `inverse`를
  "색 둘을 맞바꾼다"는 한 연산으로 이미 해소하고 있다(TR design 결정 1·2).
  선택 영역도 정확히 같은 연산이다.

## 착수 전 조사로 확정한 사실 (2026-08-24)

`vt_test.zig` 자리에 조사용 파일을 마운트해 `zig build test`로 돌려서
확인했다(`HANDOFF.md`의 "조사용 Zig 프로그램을 저장소 밖에서 돌리는 법").
**라이브러리에 선택 개념이 이미 전부 있다.**

| 확인한 것 | 결과 |
|---|---|
| `Screen.select()`에 untracked `Selection`을 넘기면 | 화면이 tracked로 바꿔서 소유권을 가져간다 (`tracked=true`) |
| `Screen.selectionString(alloc, .{ .sel = … })` | `[hello]` len=5 |
| `RenderState.Row.selection` (`render.zig:234`) | `row 0 selection={ 0, 4 }` — 라이브러리가 알아서 채운다 (`render.zig:633-650`) |
| `Screen.selectLine(.{ .pin = … })` | `[hello world]` — 줄 끝 공백을 알아서 트림한다 |
| 여섯 줄을 더 먹여 뷰포트가 밀린 뒤 | `total=9 offset=4`인데 선택은 여전히 `[hello]` |

`Selection`·`Pin`·`Point`는 전부 모듈 루트(`lib_vt.zig:68-73`)에서 나온다.
`screens.active`는 **이미 포인터**다(`&`를 붙이면 `**Screen`이 되어 컴파일이
막힌다).

이 조사가 설계를 크게 줄였다. 조사 전의 초안은 절대 행 번호를 우리가 세고,
셀 codepoint를 우리가 UTF-8로 인코딩하고, 가지치기로 좌표가 밀리면 모드를
나가는 것이었다. **TR이 남긴 교훈("라이브러리에 대해 짐작하면 틀리는 것
셋")을 그대로 다시 밟을 뻔했다.**

## 결정

### 결정 1. 모드는 `input.zig`, 선택과 클립보드는 `vt.zig`

`input.State`에 `mode: enum { normal, copy }`를 둔다. `handleKey`는
modifier를 갱신한 **직후**, `chord()`보다 앞에서 copy 분기로 빠진다.

모드가 `input`에 있어야 하는 이유는 "지금 이 키를 어떻게 해석하는가"가
번역의 문제이기 때문이다. 선택 좌표가 `vt`에 있어야 하는 이유는 그것이
화면 상태이기 때문이다. 이 분업이 지켜지면 `main.zig`는 배선만 한다.

`Screen`이 모드까지 들고 `handleKey`를 그대로 두는 안도 있었으나 버렸다 —
그러면 copy mode 중에도 `handleKey`가 `h`에 대해 바이트를 만들어 돌려주고
호출부가 그것을 버려야 한다. "PTY로 안 보낸다"를 타입이 아니라 규율로
지키는 셈이라 IP·TR이 쌓아 온 방향과 어긋난다.

### 결정 2. `Action`에 variant 하나를 더한다

```zig
pub const Action = union(enum) {
    bytes: []const u8,
    scroll: Scroll,
    copy: Copy,   // ← 더하는 것
};

pub const Copy = enum {
    enter, exit,
    left, down, up, right,
    select_char, select_line,
    yank, paste,
};
```

`project_copy_mode`가 "IP의 dispatch 단계가 그대로 진입점"이라고 예약해 둔
자리를 여기서 쓴다.

### 결정 3. 모드 안에서는 어떤 키도 PTY로 나가지 않는 것이 **기본값**이다

copy 분기는 아는 키만 `Action.copy`로 바꾸고 **나머지는 전부 `nothing`을
돌려준다.** "모르는 키는 흘려보낸다"가 아니라 "모르는 키는 삼킨다"이다.
전자를 고르면 모드 안에서 친 `e`가 셸에 도착하는 사고가 조용히 난다.

이 성질이 게이트의 음성 검사 대상이다(결정 7).

### 결정 4. 키 표

| 키 | 하는 일 |
|---|---|
| `Cmd+Shift+C` | copy mode 진입 (커서는 셸 커서 자리에서 시작) |
| `h` `j` `k` `l` | 이동. 뷰포트 위/아래 끝을 넘으면 뷰포트가 한 줄 따라 움직인다 |
| `v` | 문자 단위 선택 시작/해제 |
| `V` | 줄 단위 선택 시작/해제 |
| `y` | 선택 영역을 클립보드로 복사하고 모드를 나간다 |
| `Cmd+C` | copy mode 안에서만 `y`의 별칭 |
| `Esc` | 복사하지 않고 나간다 |
| `Cmd+V` | 어느 모드에서든 클립보드를 PTY에 쓴다 |

`Cmd+Shift+C`를 고른 것은 iTerm2의 copy mode 진입키와 같아서다. `chord()`의
Meta 분기 안에서 `shifted()`를 한 번 더 보는 예외가 생기는데, 그 예외를
감수하고 익숙한 키를 택했다.

`Cmd+C`를 별칭으로 둔 것은 macOS 사용자의 기대가 강하고 비용이 표 한 줄이기
때문이다. **normal 모드의 `Cmd+C`는 계속 비워 둔다** — 선택이 없을 때 복사는
뜻이 없고, IP가 지켜 온 "Cmd+문자는 copy mode가 가져간다"를 여기서 깨지
않는다.

### 결정 5. 앵커는 라이브러리의 tracked selection이 들고, 커서만 우리가 든다

`vt.Screen`이 드는 것은 **뷰포트 좌표의 커서 하나**다. 앵커는 따로 안 든다 —
`s.selection.?.startPtr().*`가 언제나 현재 앵커이고, 뷰포트가 움직여도
라이브러리가 따라간다(조사 6번).

- `v`: 현재 커서 위치의 pin으로 `Selection.init(pin, pin, false)`를 만들어
  `select()`에 넘긴다. untracked로 넘겨도 화면이 tracked로 바꿔 준다.
- 이동: 커서를 옮기고, 선택 중이면 `select(init(앵커, 새 커서 pin, false))`로
  갱신한다.
- `V`: 앵커 줄과 커서 줄에 각각 `selectLine`을 걸어 합친다. 줄 끝 공백
  트림을 손으로 짜지 않는다.
- `y`: `selectionString`의 결과를 클립보드 버퍼로 옮겨 담고 라이브러리
  할당을 해제한다.

클립보드는 `Screen` 안의 버퍼 하나다. `project_copy_mode`가 판단한 대로,
단일 프로세스가 디스플레이를 독점하는 구조(TF design 결정 1)에서는 이것으로
충분하다.

### 결정 6. 선택 렌더는 `RenderState.Row.selection`을 읽는 것으로 끝낸다

`cells()`가 `row_data.items(.selection)`에서 그 행의 `[start, end]`를 읽고,
범위 안의 셀에서 `fg`·`bg`를 맞바꾼다. **커서·inverse와 같은 연산이므로
렌더러는 "선택"이라는 말을 배우지 않는다**(TR design 결정 1·2의 연장).

라이브러리가 이 필드를 채우는 것은 조사 3번에서 확인했다.

### 결정 7. 새 체인 `copy/check.sh` (monitor 45461)

TR 체인에 얹지 않는다. TR은 이미 검사 열넷이 든 470줄이고, copy mode는 부팅
시나리오 자체가 다르다. 45461은 `HANDOFF.md`가 비어 있다고 적어 둔 포트다.

시나리오는 이렇다. 복사 대상을 `echo echo PASTED`의 **출력 줄**로 만드는
것이 요령이다 — QEMU `sendkey`로 따옴표를 치지 않아도 된다.

1. 부팅해서 fish 프롬프트를 확인한다.
2. `echo echo PASTED` + Enter → 출력 줄에 `echo PASTED`가 생긴다.
3. `Cmd+Shift+C` → `terminal: copy> enter row=R col=C`.
4. **음성 검사.** 모드 안에서 `q` `w` `e` `r` `t`를 치고 Enter를 누른다. 이
   다섯은 copy mode 명령이 아니므로 아무 일도 없어야 한다. `screen>`에
   `qwert`가 **없어야** 하고 새 프롬프트도 생기지 않아야 한다. 결정 3이
   증명되는 자리다.
5. `k`로 출력 줄까지 올라가고 `V`로 줄을 잡고 `y` →
   `terminal: clip> len=11 text=echo PASTED`, 이어서 `copy> exit`.
6. **대조군.** 이 시점의 `screen>`에 `| PASTED |`(그 글자만 있는 줄)가
   **없음**을 확인한다.
7. `Cmd+V` → 입력줄에 `echo PASTED`가 에코된다. Enter → 셸이 실행해서 새
   줄에 `PASTED`만 남는다.
8. **판정.** `screen>`에 `| PASTED |`가 나타난다.

6과 8이 짝을 이루는 것이 핵심이다. 8만 보면 "원래부터 화면에 있었다"는
경로로도 통과한다 — IP-M0이 `sleep`에서 데인 것과 같은 병이고,
`project_gate_chain_composition`이 "성공 경로가 하나뿐인가"를 물으라고 적어
둔 자리다.

`screen>`은 한 줄이고 행 사이를 ` | `로 구분하므로(`main.zig:126-132`),
"어떤 줄에 그 글자만 있다"는 `| PASTED |`로 쓸 수 있다.

### 결정 8. 새 로그 줄은 `copy>`와 `clip>` 둘뿐

`terminal: screen>`의 형식은 건드리지 않는다 — 다섯 체인이 그 줄로 화면을
판정한다.

로그 문구가 `main.zig`와 `copy/check.sh` 양쪽에 중복된다. 기존 체인들과 같은
구조이고, 같은 이유(체인의 단독 실행 가능성)로 공유 파일로 빼지 않는다.
**한쪽을 고치면 다른 쪽도 고쳐야 한다.**

### 결정 9. bracketed paste는 넣지 않는다

여러 줄을 붙여넣으면 개행이 곧 실행이 된다. 감수한다. 셸이 bracketed
paste를 받는지 확인한 적이 없고, 확인 없이 넣으면 게이트가 못 보는 코드가
느는 것이 `project_gate_chain_composition`이 경고한 부채 그대로다. 필요해지면
그때 실측하고 넣는다.

## milestone 구성

| | 내용 | 게이트가 새로 보는 것 |
|---|---|---|
| **CM-M0** | 모드 진입·이탈, `hjkl` 이동, 커서 반전, 뷰포트 추종, `scrollToBottom` 억제 | 체인 신설. `copy> enter`/`exit`, **음성 검사(`qwert` 안 샘)** |
| **CM-M1** | `v`/`V` 선택, 선택 영역 렌더, `y` 복사, `Cmd+C` 별칭 | `clip> len=… text=…`, 선택 셀의 색(`style>`) |
| **CM-M2** | `Cmd+V` 붙여넣기 | 왕복(`\| PASTED \|`)과 대조군 |

plan은 저장소 규칙대로 **한 milestone이 끝난 시점에 다음 것을 쓴다.**

> **CM-M0 완료 (2026-08-24).** 여덟 체인 24회가 전부 통과했고 루트 게이트는
> **51분 20초**다. 직전 기준선 45분 41초에서 **5분 39초**가 늘었으니 CM 체인
> 1회가 약 1분 53초다(위험 5의 실측값).
>
> **위험 4가 해소됐다.** QEMU `sendkey meta_l-shift-c`가 세 키 조합을
> 게스트까지 옮긴다 — 첫 시도에 `terminal: copy> enter row=46 col=11`이
> 찍혔고, 진입키를 두 키 조합으로 바꿀 필요가 없었다. 결정 4는 그대로다.
>
> **음성 검사가 실제로 값을 했다.** 모드 안에서 `q w e r t`와 Enter를 쳤을 때
> `terminal: key>` 줄이 10에서 움직이지 않았다. 앞뒤 대조군(모드 밖 8→9,
> 나온 뒤 10→11)이 함께 있어야 이 "안 움직였다"가 뜻을 가진다.
>
> **설계가 실측에서 배운 것 넷.**
>
> 1. **copy 커서는 언제나 화면 맨 아랫줄에서 시작한다.** 셸 프롬프트가 거기
>    있기 때문이다(`row=46`, 화면은 47줄). 그래서 **`j`를 첫 이동 검사로 쓸 수
>    없다** — 커서가 이미 `max_y`이고 뷰포트도 바닥이라 아무 데도 못 간다.
>    게이트는 `k`로 올라갔다가 `j`로 되돌아오는 순서로 바꿨고, 그 편이 위아래
>    양쪽을 정확한 값으로 보므로 더 강한 검사가 됐다.
> 2. **`copyEnter`의 "뷰포트 밖이면 왼쪽 위" 가지가 죽은 코드가 아니다.**
>    `vt_test`에서 실제로 밟혔다 — 스크롤백을 올려다보는 중에는
>    `state.cursor.viewport`가 null이다.
> 3. **`sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.** 커서를
>    46줄 올리고 뷰포트를 34줄 밀었으니 46 + 34 = 80이 정확히 맞았다.
>    체인들의 `sleep 0.3`을 줄일 수 있다는 방증이다(이월 숙제).
> 4. **`Action`에 variant를 더할 때 `zig build test`만으로는 모자란다.**
>    Zig가 참조되지 않는 함수를 분석하지 않아서, `readKeys`가 쓰는
>    `State.scrolls` 필드가 통째로 사라진 것을 호스트 검사가 두 번 놓쳤다.
>    `input_test`는 `handleKey`만 부른다. **`zig build`가 잡았다** — 앞으로
>    `input.Action`이나 `Keys`를 건드리는 변경은 둘을 함께 돌려야 한다.

## 테스트 전략

게이트가 보는 것과 호스트 단위 검사가 보는 것을 나눈다.

- **`input_test`** — 모드 분기. 모드 안의 `h`가 바이트를 안 만드는 것,
  `Cmd+Shift+C`가 `.copy = .enter`를 내는 것, 모드 안의 모르는 키가
  `nothing`인 것(결정 3).
- **`vt_test`** — 커서 이동의 경계(화면 끝에서 더 가면 어떻게 되는가),
  선택이 걸린 뒤 `cells()`가 그 셀의 색을 맞바꾸는 것, `y`가 만든 클립보드
  문자열.
- **`copy/check.sh`** — 결정 7의 여덟 단계. 실제 키보드에서 실제 셸까지
  이어지는 것은 여기서만 증명된다.

## 위험

**1. `scrollToBottom` 억제가 가지치기의 창을 연다.** `main.zig:447-450`의
주석이 적어 둔 그대로다. copy mode 중 출력이 1000줄 넘게 쏟아지면 tracked
pin이 어떻게 되는지 확인하지 않았다 — 조사 6번이 증명한 것은 "스크롤 뒤에도
살아 있다"이지 "가지치기 뒤에도 살아 있다"가 아니다. 게이트로 만들 값은
아니라고 보고(1000줄이 쏟아져야 닿는다), 대신 **매 프레임 `selection`이
null이 됐는지 보고 그러면 모드를 나가는** 방어를 넣는다. 조용히 어긋난 것을
복사하는 것보다 낫다.

**2. `Cmd+Shift+C`가 `chord()`의 Meta 분기에 예외를 만든다.** Meta 분기는
지금 "표에 없으면 `null`"이라 단순한데, 여기에 Shift 조건이 하나 붙는다.
결정 4에서 감수하기로 한 비용이고, 그 예외는 이 한 줄뿐이어야 한다.

**3. 선택의 방향.** 앵커보다 커서가 앞에 있는 역방향 선택을
`selectionString`이 어떻게 다루는지 조사에서 확인하지 않았다(정방향만
봤다). CM-M1에서 실측하고, 라이브러리가 정렬해 주지 않으면 `ordered()`를
쓴다.

**~~4. QEMU `sendkey`의 세 키 조합.~~ — CM-M0에서 해소됐다.**
`meta_l-shift-c`가 게스트까지 도착한다. 진입키를 바꾸지 않았다.

**~~5. 게이트 시간이 는다.~~ — CM-M0에서 실측했다.** 45분 41초 → **51분
20초**, 증가분 5분 39초(CM 체인 1회당 약 1분 53초). 다른 일곱 체인은 흔들리지
않았다. **값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저
의심한다**는 규칙은 그대로 유효하다.

**6. copy mode 중의 가지치기는 여전히 안 봤다.** 위험 1과 같은 자리이지만,
CM-M0이 `scrollToBottom` 억제를 실제로 넣었으므로 **창이 이미 열렸다.**
방어는 CM-M1의 몫이다.

## 비워 두는 자리

- **단어 이동(`w`/`b`)과 검색(`/`).** 라이브러리에 `selectWord`도
  `search`도 있어서 나중에 붙이기 쉽다. 지금 넣지 않는 이유는 게이트가 볼
  표를 늘리는 것이기 때문이다.
- **마우스.** 마우스라는 개념 자체가 이 시스템에 아직 없다.
- **프로세스 간 클립보드와 OSC 52.** 셸이 OSC 52로 클립보드를 쓰려 할 때
  어떻게 할지는 정하지 않았다.
- **normal 모드의 `Cmd+C`.**

## 참고

- 기억: `project_copy_mode`, `project_input_policy`,
  `project_terminal_rendering`, `project_gate_chain_composition`,
  `project_guest_environment`
- 앞 서브프로젝트: `2026-08-23-tars-terminal-rendering-design.md`
