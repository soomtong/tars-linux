# IS-M1 — `CAPS` 칸과 갱신 구멍

**Date:** 2026-09-08
**Design:** `docs/superpowers/specs/2026-09-02-tars-input-status-design.md`
**Status:** 착수 전.

## 이 milestone이 끝나면

- **상태 줄의 칸이 넷이 된다** — `EN  공세벌 3-P3  쿼티  CAPS`. 넷째 칸은
  **글자가 안 바뀌고 색만 바뀐다**(결정 3).
- **색이 셋이 된다** — `STATUS_FG`(앞 세 칸) · `STATUS_ON`(잠금 켜짐, 앰버) ·
  `STATUS_OFF`(잠금 꺼짐, 어두운 회색).
- **`Action.hangul`이 `Action.redraw`가 된다**(결정 8). 이름이 넓어지고,
  **긴 CapsLock이 그것을 돌려준다** — 지금은 `nothing`을 돌려서 화면이 안
  갱신된다.
- **게이트가 "키를 하나 더 안 치고 바로 밝아지는가"를 본다.** 이 판정 하나가
  결정 8의 구멍을 보는 유일한 자리다.
- **`MAX_LEN`이 30에서 36이 된다** — `comptime` 계산이라 **손으로 안 늘린다.**
  IS-M0 실측 1이 "그 값이 값을 하는 자리는 아직 오지 않았다"고 적어 둔 것이
  여기서 처음 확인된다.
- **서브프로젝트 IS가 닫힌다.** design의 `Status:` 줄과
  `docs/decisions/project_input_status.md`, `MEMORY.md`를 함께 고친다.

**아직 안 하는 것.** design 비목표 전부 — 마우스로 자판 바꾸기 · 색과 자리를
설정으로 빼기 · 위 여백 쓰기 · 전환 키 목록 표시 · 키보드 LED · HI가 남긴
나머지 숙제(기호 확장 · Patal의 옵션 trait들 · 모아주기 · copy mode 검색창의
한글 입력).

---

## 착수 전에 확정한 것

**1. 자리는 정확히 열넷이고 전부 컴파일러가 잡는다.** 실제로 세어 확인했다.

| 파일 | 자리 |
|---|---|
| `input.zig` | 342(`Action` 선언) · 426(`Keys` 선언) · 818 · 913 · 942 · 1340 · 1396 · 1403 — **여덟** |
| `input.zig`의 지역 변수 `hangul_changed` | 1347 · 1366 · 1396 · 1403 — 넷(이름만, 컴파일러가 안 잡는다) |
| `main.zig` | 1012 `if (keys.hangul)` — 하나 |
| `input_test.zig` | 81 · 120 · 162 · 200의 `.hangul =>` 갈래 — 넷 |

**여덟 + 하나 + 넷 = 열셋이고, 열넷째는 새로 더하는 CapsLock 분기의
`return .redraw;`다.** design이 "자리 열넷"이라고 적은 것과 맞는다. 지역
변수 넷은 컴파일러가 안 잡지만, `hangul_changed`라는 이름이 CapsLock을
나르게 되면 거짓말이 되므로 함께 고친다.

**2. `statusText`는 `caps_lock`을 아예 안 읽는다.** 결정 3("글자를 안 바꾸고
색만 바꾼다")을 **구조로** 못 박는 방법이다. 읽고 나서 무시하는 것보다
안 읽는 편이 낫다 — 나중에 누가 `if (state.caps_lock)`을 넣고 싶어지면 그
자리에 필드가 없다는 것이 먼저 눈에 띈다. 색을 고르는 것은 `main.zig`이고,
그것을 보는 것은 게이트의 `status> caps ink` 줄이다.

**3. `caps ink`는 `CAPS` 칸의 x 범위를 안 잰다 — 띠 전체를 센다.**
design이 "**`CAPS` 칸의 x 범위 하나만 보는 전용 판정**"이라고 적은 것의
목적은 `INK_DUMP_LIMIT` 같은 상한에 걸려 **엉뚱한 것을 보고 통과**하는 일을
막는 것이었다(2026-09-02 실측 5). 그 목적은 **색으로 이미 달성된다** —
`STATUS_ON`과 `STATUS_OFF`는 여백 안에서 `CAPS` 칸에만 쓰이므로, 띠 전체에서
그 두 색을 센 값이 곧 `CAPS` 칸의 값이다.

**x 범위를 재는 쪽이 오히려 위험하다.** `drawStatus`와 `dumpStatus`가 y뿐
아니라 **col 전진 산수까지 똑같이** 다시 해야 하고, 어긋나면 언제나 0이
나온다 — 증상이 "안 그렸다"와 똑같아서 원인을 `drawStatus`에서 찾게 된다
(`dumpStatus`의 주석이 y에 대해 이미 경고해 둔 그 함정이다).

**4. 메모에 `caps`를 더해야 한다 — 안 그러면 게이트가 영영 못 본다.**
`dumpStatus`는 지금 **`text`가 바뀌었을 때만** 찍는다(결정 9). 그런데
`CAPS`는 켜지든 꺼지든 **글자가 똑같다**(결정 3). 그래서 메모를 안 넓히면
CapsLock을 눌러도 새 `status>` 줄이 한 줄도 안 찍히고, 게이트의 새 판정은
**부팅 직후의 값을 다시 읽으며** `on=0`으로 실패한다.

**증상이 "구멍이 안 고쳐졌다"와 구별이 안 된다** — 둘 다 `on=0`이다.
그래서 이것을 Task 4에서 `drawStatus`와 **같은 Task에** 넣지 않고,
"찍는 층"을 Task 5로 따로 세운다.

**5. 새 로그 줄은 하나이고, `ink fg=`는 그대로 둔다.** IS-M0의 `ink fg=`는
앞 세 칸의 `STATUS_FG` 픽셀을 세는데, `CAPS`가 다른 색으로 그려지므로
**그 값은 안 바뀐다**(383). 검사 0a가 그것을 `>0`으로만 보므로 그대로
통과한다. 지우면 앞 세 칸이 안 그려진 것을 볼 창구가 사라진다.

**6. 게이트 판정은 `type_keys` 앞에 있어야 한다.** 검사 13이
`hold_key caps_lock 500` 뒤에 `type_keys a b c 1`을 친다. 판정을 그 뒤에
두면 **`Action.redraw`가 없는 코드도 통과한다** — `type_keys`가 만든 다음
프레임에서 `CAPS`가 밝아지기 때문이다. 이 순서 하나가 이 milestone의
검증 전부다.

**7. 짝을 하나 더 넣는다(design은 "판정 하나"라고 적었다).** design의
Milestone 절은 "게이트 판정 하나(긴 CapsLock 뒤)"인데, 이 저장소가 여러 번
값을 본 규율은 **"켜지는 것만 보면 토글이 한 방향으로만 동작해도
통과한다"**이다(게이트 검사 1과 9, 검사 13과 14, `input_test` 검사 46이
전부 그 짝이다). 검사 14가 이미 두 번째 긴 CapsLock을 누르므로
**키를 하나도 안 더하고** 꺼지는 쪽 판정을 얻는다. 그래서 판정을 둘 넣는다.

**8. 편집은 사용자가 한다.** `CLAUDE.md`의 기본 규칙이다. **명령 실행은
Claude Code가 한다.** 지울 것이 있는 편집은 `지울 것`과 `넣을 것`을 따로
표시한다.

**9. `dependOn` 목록 같은 함정을 다시 안 밟는다**(IS-M0 실측 7). 이 plan의
편집 중 **`.hangul =>` 갈래 넷**(`input_test.zig` 81·120·162·200)이 서로
비슷하게 생겼다. 그래서 그 넷은 "지울 줄"이 아니라 **줄 번호와 앞뒤 문맥을
함께** 적는다. 매 Task 끝에 `git diff --stat`으로 더한 줄과 지운 줄을
따로 센다.

---

## 왜 이 순서인가

**Task 1이 동작을 한 글자도 안 바꾼다.** 순수한 이름 바꾸기라 `zig build
test`가 **바뀐 검사 없이** 그대로 초록이어야 한다. 여기서 빨개지면 그것은
이름을 바꾸다 만 것이지 설계가 틀린 것이 아니다.

**Task 2가 새 경로 하나를 넣는다.** 긴 CapsLock이 `.redraw`를 돌려주는 것
하나다. `input_test`의 기존 검사 넷이 **지금 `.bytes ""`를 기대하고 있어서**
실패 지점이 공짜로 있다 — 실패를 먼저 보고 고친다.

**Task 3이 글자를, Task 4가 색을, Task 5가 찍는 것을 맡는다.** 게이트가
실패했을 때 갈리는 자리가 다르다.

| 증상 | 어느 Task |
|---|---|
| `text=`에 `CAPS`가 없다 | Task 3 |
| `text=`는 맞는데 `caps ink` 줄이 아예 없다 | Task 5 |
| `on=0 off=0` (둘 다 0) | Task 4 — `drawStatus`가 `CAPS`를 안 그렸다 |
| 부팅 직후엔 맞는데 CapsLock 뒤에 안 바뀐다 | Task 5의 메모(확정 4) 또는 Task 2 |

**Task 6이 게이트다.** 호스트 검사가 전부 통과한 뒤에 부팅한다.

**컨테이너 한 줄.** 호스트는 macOS aarch64이고 `linux/input.h`가 없으므로
`zig build test`를 호스트에서 직접 돌릴 수 없다.

---

## Task 1: `Action.hangul` → `Action.redraw` (동작은 한 글자도 안 바뀐다)

**Files:**
- Modify: `terminal/src/input.zig` (선언 둘 · `return` 넷 · `readKeys` 넷)
- Modify: `terminal/src/main.zig:1012`
- Modify: `terminal/src/input_test.zig` (`.hangul =>` 갈래 넷)

- [ ] **Step 1: 선언 둘만 먼저 고치고 컴파일러에게 나머지를 물어본다**

**이 Step이 이 Task의 요점이다.** design이 "자리는 열넷인데 **전부 컴파일러가
잡는다**"고 적은 것을 실제로 써먹는다 — 손으로 `rg`를 돌려 찾는 대신
컴파일러가 목록을 준다.

`terminal/src/input.zig`의 `Action` union에서:

**지울 것** (line 329~342, 주석과 variant 이름):

```zig
    /// 한글 층이 이 키를 처리했다(HI-M1). **payload가 없는 것에 뜻이 있다.**
    ///
    /// 나르는 것은 "조합 중인 글자가 바뀌었을 수 있으니 다시 그려라"라는
    /// 사실 하나뿐이다. **값은 `State.preedit()`이 준다** — 조합은 마지막
    /// 하나만 화면에 남으므로 스크롤·copy처럼 순서대로 모을 것이 없다.
    ///
    /// **확정된 글자도 여기 없다.** 그것은 `takeCommit()`이 따로 주며,
    /// 이유는 그 함수의 주석에 있다.
    ///
    /// 이 variant가 없으면 조합 중인 글자가 **영영 화면에 안 나온다.**
    /// 자모 키는 PTY로 아무것도 안 보내고 스크롤도 copy 명령도 안 만들어서
    /// `main.zig`의 `needs_redraw`가 안 켜진다.
    hangul,
```

**넣을 것:**

```zig
    /// 이 키가 **화면을 바꿨다.** PTY로 나갈 바이트도, 모아 둘 스크롤도
    /// copy 명령도 없다 — 다시 그리기만 하면 된다.
    ///
    /// **payload가 없는 것에 뜻이 있다.** 나르는 것은 "다시 그려라"라는
    /// 사실 하나뿐이고, 무엇이 바뀌었는지는 상태를 읽어 알아낸다 —
    /// 조합 중인 글자는 `State.preedit()`이, 대문자 잠금은
    /// `State.caps_lock`이 준다.
    ///
    /// **확정된 글자는 여기 없다.** 그것은 `takeCommit()`이 따로 주며,
    /// 이유는 그 함수의 주석에 있다.
    ///
    /// 이 variant가 없으면 **화면이 영영 안 갱신되는 키가 생긴다.** 자모
    /// 키는 PTY로 아무것도 안 보내고 스크롤도 copy 명령도 안 만들어서
    /// `main.zig`의 `needs_redraw`가 안 켜진다(HI-M1 실측 2).
    ///
    /// **이름이 `hangul`이 아니라 `redraw`인 이유가 IS-M1이다**(IS design
    /// 결정 8). 뜻은 원래부터 "한글"이 아니라 "다시 그려라"였는데, 한글이
    /// 아닌 둘째 호출자(긴 CapsLock)가 생기면서 그 이름이 좁다는 것이
    /// 드러났다. **`Action.caps`를 따로 더하지 않았다** — 셋째 호출자가
    /// 생기면 `main.zig`가 `if (keys.hangul or keys.caps)`가 되고, 그
    /// 조건에 넷째를 빼먹는 것이 다음 사고다.
    redraw,
```

같은 파일의 `Keys` struct에서:

**지울 것** (line 420~426):

```zig
    /// 이 배치에서 조합 중인 글자가 바뀌었는가(HI-M1).
    ///
    /// **값이 아니라 사실만 나른다.** 값은 `State.preedit()`이 주며,
    /// 조합은 마지막 하나만 화면에 남으므로 스크롤·copy처럼 **순서대로 모을
    /// 것이 없다** — 자동 반복으로 자모가 여럿 실려 와도 그려야 할 글자는
    /// 마지막 하나다.
    hangul: bool,
```

**넣을 것:**

```zig
    /// 이 배치가 화면을 바꿨는가(HI-M1 · IS-M1에서 이름이 넓어졌다).
    ///
    /// **값이 아니라 사실만 나른다.** 무엇이 바뀌었는지는 상태를 읽어
    /// 알아내며, 스크롤·copy처럼 **순서대로 모을 것이 없다** — 자동 반복으로
    /// 자모가 여럿 실려 와도 그려야 할 글자는 마지막 하나이고, 대문자 잠금을
    /// 두 번 뒤집으면 마지막 값 하나만 그리면 된다.
    redraw: bool,
```

- [ ] **Step 2: 컴파일러에게 나머지 자리를 물어본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: **컴파일 실패.** `no field named 'hangul'` 계열 에러가 열 몇 줄 나온다.
`input.zig`의 넷(818 · 913 · 942 · 1340 · 1396 · 1403), `main.zig`의 하나,
`input_test.zig`의 넷이 전부 목록에 있어야 한다.

**이 목록을 읽는 것이 이 Step의 값이다.** design이 약속한 "전부 컴파일러가
잡는다"가 사실인지 여기서 확인한다 — 에러 목록에 없는 자리가 있다면 그것은
컴파일러가 못 잡는 자리이고, 그런 자리는 손으로 찾아야 한다.

- [ ] **Step 3: `input.zig`의 나머지 여섯 자리를 고친다**

전부 `.hangul` → `.redraw`이고 한 줄씩이다.

| line | 지금 | 고친 뒤 |
|---|---|---|
| 818 (`toggleHangul`) | `        return .hangul;` | `        return .redraw;` |
| 913 (Backspace) | `            return .hangul;` | `            return .redraw;` |
| 942 (`nonSyllable`) | `            const n = std.unicode.utf8Encode(cp, &self.seq) catch return .hangul;` | `            const n = std.unicode.utf8Encode(cp, &self.seq) catch return .redraw;` |
| 955 (`feed` 뒤) | `        return .hangul;` | `        return .redraw;` |
| 1340 (`readKeys`의 이른 return) | `        .hangul = false,` | `        .redraw = false,` |
| 1403 (`readKeys`의 return) | `        .hangul = hangul_changed,` | `        .redraw = redraw,` |

- [ ] **Step 4: `readKeys`의 지역 변수 이름을 함께 고친다**

**컴파일러가 안 잡는 자리다.** `hangul_changed`라는 이름은 Task 2에서
CapsLock을 나르게 되는 순간 거짓말이 된다.

`terminal/src/input.zig`의 line 1347:

**지울 것:** `    var hangul_changed = false;`
**넣을 것:** `    var redraw = false;`

line 1360~1366의 주석과 대입:

**지울 것:**

```zig
        // 확정이 일어났다는 것은 조합 버퍼가 비었다는 뜻이므로 화면도 다시
        // 그려야 한다 — 그래서 `hangul_changed`를 여기서도 켠다.
        const commit = self.takeCommit();
        if (commit.len > 0) {
            hangul_changed = true;
```

**넣을 것:**

```zig
        // 확정이 일어났다는 것은 조합 버퍼가 비었다는 뜻이므로 화면도 다시
        // 그려야 한다 — 그래서 `redraw`를 여기서도 켠다.
        const commit = self.takeCommit();
        if (commit.len > 0) {
            redraw = true;
```

line 1394~1396의 switch 갈래:

**지울 것:**

```zig
            // 조합만 바뀐 키다. PTY로 나갈 것도 모을 것도 없고, `main.zig`가
            // 다시 그리기만 하면 된다.
            .hangul => hangul_changed = true,
```

**넣을 것:**

```zig
            // 화면만 바뀐 키다. PTY로 나갈 것도 모을 것도 없고, `main.zig`가
            // 다시 그리기만 하면 된다 — 조합 중인 글자(HI-M1)와 대문자
            // 잠금(IS-M1)이 둘 다 이리로 온다.
            .redraw => redraw = true,
```

- [ ] **Step 5: `main.zig`의 한 자리를 고친다**

`terminal/src/main.zig`의 line 1005~1015.

**지울 것:**

```zig
            // **`needs_redraw`를 여기서 켜야 한다.** 조합만 바뀐 키는 PTY로
            // 아무것도 안 보내고 스크롤도 copy 명령도 안 만든다 — 그래서
            // 이 한 줄이 없으면 조합 중인 글자가 **영영 화면에 안 나온다.**
            //
            // copy 루프 **뒤**인 것에도 뜻이 있다. copy mode에 들어가는 키가
            // 조합을 확정시키므로(design 결정 6), 그 확정 결과를 화면에
            // 반영하는 것은 모드 전환이 끝난 뒤여야 한다.
            if (keys.hangul) {
```

**넣을 것:**

```zig
            // **`needs_redraw`를 여기서 켜야 한다.** 화면만 바뀐 키는 PTY로
            // 아무것도 안 보내고 스크롤도 copy 명령도 안 만든다 — 그래서
            // 이 한 줄이 없으면 조합 중인 글자가 **영영 화면에 안 나오고**,
            // 대문자 잠금을 켜도 `CAPS` 칸이 **다음 키를 칠 때까지 안
            // 밝아진다**(IS design 결정 8).
            //
            // copy 루프 **뒤**인 것에도 뜻이 있다. copy mode에 들어가는 키가
            // 조합을 확정시키므로(design 결정 6), 그 확정 결과를 화면에
            // 반영하는 것은 모드 전환이 끝난 뒤여야 한다.
            if (keys.redraw) {
```

**블록 안은 한 글자도 안 바꾼다.** `screen.setPreedit(...)` ·
`dumpHangul(...)` · `needs_redraw = true` 셋이 그대로다. 대문자 잠금만 바뀐
프레임에서도 `setPreedit`은 같은 값을 다시 넣을 뿐이고, `dumpHangul`은
`hangul> on=false preedit=` 한 줄을 더 찍는다 — **게이트 검사 13이 그 줄을
읽는데, 값이 `on=false`라 기대와 같다.** 그 검사의 주석은 Task 6에서 고친다.

- [ ] **Step 6: `input_test.zig`의 갈래 넷을 고친다**

**넷이 서로 비슷하게 생겼다**(확정 9). 각각의 **에러 이름이 다르므로** 그것을
표적으로 삼는다.

| line | `.hangul =>` 뒤에 오는 에러 | 앞 갈래 |
|---|---|---|
| 81 | `error.UnexpectedHangul` (want bytes) | `.copy` |
| 120 | `error.UnexpectedHangul` (want copy) | `.scroll` |
| 162 | `error.UnexpectedHangul` (want scroll) | `.copy` |
| 200 | `.hangul => {},` (한 줄, 본체 없음) | — (첫 갈래) |

**line 81** — `expect` 계열의 갈래.

**지울 것:**

```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} value={d} -> got hangul, want bytes {any}\n",
                .{ code, value, want },
            );
            return error.UnexpectedHangul;
        },
```

**넣을 것:**

```zig
        .redraw => {
            std.debug.print(
                "FAIL: code={d} value={d} -> got redraw, want bytes {any}\n",
                .{ code, value, want },
            );
            return error.UnexpectedRedraw;
        },
```

**line 120** — copy를 기대하는 갈래.

**지울 것:**

```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want copy .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
```

**넣을 것:**

```zig
        .redraw => {
            std.debug.print(
                "FAIL: code={d} -> got redraw, want copy .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedRedraw;
        },
```

**line 162** — scroll을 기대하는 갈래.

**지울 것:**

```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want scroll .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
```

**넣을 것:**

```zig
        .redraw => {
            std.debug.print(
                "FAIL: code={d} -> got redraw, want scroll .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedRedraw;
        },
```

**line 200** — `expectHangulAt`의 첫 갈래. 한 줄이다.

**지울 것:** `        .hangul => {},`
**넣을 것:** `        .redraw => {},`

같은 함수 안에서 아래 `.bytes` 갈래의 메시지가 `want hangul`이라고 적혀
있는데, 그것은 **이 헬퍼가 한글을 기대한다는 뜻**이라 그대로 둔다.

- [ ] **Step 7: 검사가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: 다섯 검사(`input_test` · `vt_test` · `font_test` · `hangul_test` ·
`status_test`)가 전부 통과. **검사 코드를 한 글자도 안 바꿨으므로 초록이
당연하다** — 여기서 빨개지면 이름을 바꾸다 만 것이다.

- [ ] **Step 8: diff를 눈으로 센다**

```bash
git diff --stat
git diff | grep -c '^-[^-]'
git diff | grep -c '^+[^+]'
```

기대: `input.zig` · `main.zig` · `input_test.zig` 셋만 나온다.
**`status.zig`나 `check.sh`가 나오면 잘못 건드린 것이다.**

- [ ] **Step 9: 커밋**

```bash
git add terminal/src/input.zig terminal/src/main.zig terminal/src/input_test.zig
git commit -m "Rename the hangul action to redraw"
```

---

## Task 2: 긴 CapsLock이 화면을 다시 그리게 한다

**Files:**
- Modify: `terminal/src/input_test.zig` (헬퍼 하나 추가 · 검사 46·47·48의 네 줄)
- Modify: `terminal/src/input.zig:1139` 근처

- [ ] **Step 1: 헬퍼를 하나 더한다**

`terminal/src/input_test.zig`의 `expectHangulAt` 함수 **바로 뒤**에 넣는다
(그 함수의 닫는 `}` 다음 줄).

```zig
/// 이 키가 **화면만 다시 그리게** 하기를 기대한다(IS-M1). 확정된 글자도
/// PTY로 나갈 바이트도 없다.
///
/// **긴 CapsLock이 이 모양이다.** 대문자 잠금을 뒤집는 것 말고는 아무 일도
/// 안 하는데, 상태 줄의 `CAPS` 칸이 **그 자리에서** 밝아져야 하므로
/// `nothing`으로는 부족하다 — `main.zig`의 `needs_redraw`가 안 켜져서
/// **다음 키를 칠 때까지 안 밝아진다**(IS design 결정 8).
///
/// 속은 `expectHangulAt`과 같다. **이름을 따로 두는 이유는 읽는 사람을
/// 위해서다** — CapsLock 자리에 "Hangul"이라는 이름이 서 있으면 그것이
/// 한글과 무슨 상관인지 다음 사람이 찾아 헤맨다.
fn expectRedrawAt(state: *input.State, code: u16, value: i32, time_us: u64) !void {
    return expectHangulAt(state, code, value, time_us, "", null);
}
```

- [ ] **Step 2: 검사 넷을 고쳐 실패하게 만든다**

**넷 다 "긴 CapsLock을 뗀다"이고, 지금은 `.bytes ""`를 기대한다.**

**검사 46** (line 1209 · 1227). 앞뒤 줄로 자리를 잡는다.

지금:

```zig
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 3_000_000, "");
    try expectAt(&cl, K.KEY_CAPSLOCK, 0, 3_400_000, "");
    if (cl.hangul_on) {
```

고친 뒤 — **누름(`1`)은 그대로 두고 뗌(`0`)만 바꾼다:**

```zig
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 3_000_000, "");
    // **뗄 때 `.redraw`가 나와야 한다**(IS-M1). 대문자 잠금이 뒤집혔으니
    // 상태 줄의 `CAPS` 칸을 그 자리에서 다시 그려야 한다.
    try expectRedrawAt(&cl, K.KEY_CAPSLOCK, 0, 3_400_000);
    if (cl.hangul_on) {
```

지금:

```zig
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 5_000_000, "");
    try expectAt(&cl, K.KEY_CAPSLOCK, 0, 5_400_000, "");
    try expectAt(&cl, K.KEY_A, 1, 6_000_000, "a");
```

고친 뒤:

```zig
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 5_000_000, "");
    try expectRedrawAt(&cl, K.KEY_CAPSLOCK, 0, 5_400_000);
    try expectAt(&cl, K.KEY_A, 1, 6_000_000, "a");
```

**검사 47** (`cl_off`). 지금:

```zig
    try expectAt(&cl_off, K.KEY_CAPSLOCK, 1, 0, "");
    try expectAt(&cl_off, K.KEY_CAPSLOCK, 0, 100_000, "");
```

고친 뒤 — **`capslock_tap`이 꺼져 있어도 화면은 다시 그려야 한다.** 잠금은
뒤집혔기 때문이다:

```zig
    try expectAt(&cl_off, K.KEY_CAPSLOCK, 1, 0, "");
    // **설정이 꺼져 있어도 `.redraw`다.** 한/영은 안 바뀌지만 대문자 잠금은
    // 바뀌었고, 상태 줄은 그것도 보여 준다.
    try expectRedrawAt(&cl_off, K.KEY_CAPSLOCK, 0, 100_000);
```

**검사 48** (`cl_hg`). 지금:

```zig
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 1, 0, "");
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 0, 400_000, "");
```

고친 뒤:

```zig
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 1, 0, "");
    try expectRedrawAt(&cl_hg, K.KEY_CAPSLOCK, 0, 400_000);
```

**그 아래 `expectHangulAt(&cl_hg, K.KEY_CAPSLOCK, 0, 1_100_000, "", null)`은
안 건드린다** — 그것은 짧은 tap이라 한/영 전환이고, 이름이 맞다.

- [ ] **Step 3: 검사가 실패하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: **`input_test` 실패.**

```
FAIL: code=58 -> got 0 byte(s), want hangul
```

**메시지가 `want hangul`인 것은 헬퍼를 껍데기로 만든 대가다**(`expectHangulAt`
안의 문구를 그대로 쓴다). 코드 58이 `KEY_CAPSLOCK`이라는 것이 이 실패가 맞는
자리라는 신호다.

**이 실패를 굳이 보는 이유.** 다음 Step이 통과했을 때 그것이 **새 `return`
때문임**을 확인하기 위해서다. 실패를 안 보고 넘어가면 헬퍼가 아무것도 안
보는 상태(예: `expectRedrawAt`이 실수로 언제나 통과)여도 초록이다 —
IS-M0 실측 7이 잡은 것과 같은 종류의 구멍이다.

- [ ] **Step 4: CapsLock 분기를 고친다**

`terminal/src/input.zig`의 line 1131~1143.

**지울 것:**

```zig
                    // **`capslock_tap`이 꺼져 있으면 `tapped`가 무엇이든 여기
                    // 온다.** 그때 CapsLock은 그냥 CapsLock이고, 갈래를 나누지
                    // 않으므로 "언제나 뗄 때"라는 규칙이 하나로 선다.
                    self.caps_lock = !self.caps_lock;
                } else {
```

**넣을 것:**

```zig
                    // **`capslock_tap`이 꺼져 있으면 `tapped`가 무엇이든 여기
                    // 온다.** 그때 CapsLock은 그냥 CapsLock이고, 갈래를 나누지
                    // 않으므로 "언제나 뗄 때"라는 규칙이 하나로 선다.
                    self.caps_lock = !self.caps_lock;
                    // **`nothing`이 아니라 `.redraw`다**(IS design 결정 8).
                    // 상태 줄의 `CAPS` 칸이 이 값을 보여 주므로, 여기서
                    // 안 켜면 `main.zig`의 `needs_redraw`가 안 켜지고
                    // **다음 키를 칠 때까지 안 밝아진다.**
                    //
                    // **IS-M1 전까지는 이것이 버그가 아니었다** — 대문자
                    // 잠금은 다음에 치는 글자에서만 드러나고 그 글자가
                    // 어차피 다시 그렸다. 화면에 표시가 생기는 순간
                    // 버그가 됐다.
                    return .redraw;
                } else {
```

- [ ] **Step 5: 검사가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: 다섯 검사 전부 통과. `input_test: capslock OK`가 보인다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Redraw when a long CapsLock flips the capital lock"
```

---

## Task 3: `CAPS` 칸을 상태 줄에 더한다

**Files:**
- Modify: `terminal/src/status.zig`
- Modify: `terminal/src/status_test.zig`

- [ ] **Step 1: 검사를 먼저 고친다 — 기대 문자열 여덟에 `  CAPS`를 붙인다**

`terminal/src/status_test.zig`의 검사 1~8이다. **여덟 줄 전부** 끝에
`  CAPS`가 붙는다(두 칸 공백 + `CAPS`).

**지울 것:**

```zig
    try expectText(.{}, "EN  신세벌 PCS  쿼티");

    // ── 검사 2: 한/영이 첫 칸을 가른다 ───────────────────────────────
    try expectText(.{ .hangul_on = true }, "한  신세벌 PCS  쿼티");
```

**넣을 것:**

```zig
    try expectText(.{}, "EN  신세벌 PCS  쿼티  CAPS");

    // ── 검사 2: 한/영이 첫 칸을 가른다 ───────────────────────────────
    try expectText(.{ .hangul_on = true }, "한  신세벌 PCS  쿼티  CAPS");
```

**지울 것:**

```zig
    try expectText(.{ .hangul_layout = .dubeol }, "EN  두벌식  쿼티");
    try expectText(.{ .hangul_layout = .sebeol_3p3 }, "EN  공세벌 3-P3  쿼티");
    try expectText(.{ .hangul_layout = .shin_p2 }, "EN  신세벌 P2  쿼티");
    try expectText(.{ .hangul_layout = .shin_pcs }, "EN  신세벌 PCS  쿼티");

    // ── 검사 7~8: 영문 자판 둘의 이름 ────────────────────────────────
    try expectText(.{ .latin_layout = .qwerty }, "EN  신세벌 PCS  쿼티");
    try expectText(.{ .latin_layout = .dvorak }, "EN  신세벌 PCS  드보락");
```

**넣을 것:**

```zig
    try expectText(.{ .hangul_layout = .dubeol }, "EN  두벌식  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .sebeol_3p3 }, "EN  공세벌 3-P3  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .shin_p2 }, "EN  신세벌 P2  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .shin_pcs }, "EN  신세벌 PCS  쿼티  CAPS");

    // ── 검사 7~8: 영문 자판 둘의 이름 ────────────────────────────────
    try expectText(.{ .latin_layout = .qwerty }, "EN  신세벌 PCS  쿼티  CAPS");
    try expectText(.{ .latin_layout = .dvorak }, "EN  신세벌 PCS  드보락  CAPS");
```

- [ ] **Step 2: 칸 개수를 셋에서 넷으로 바꾼다**

검사 9의 두 자리다.

**지울 것:**

```zig
        if (fields != 3) {
            std.debug.print("FAIL: {d} field(s) in \"{s}\", want 3\n", .{ fields, line });
            return error.WrongStatusFieldCount;
        }
        std.debug.print("status_test: 3 fields OK\n", .{});
```

**넣을 것:**

```zig
        if (fields != 4) {
            std.debug.print("FAIL: {d} field(s) in \"{s}\", want 4\n", .{ fields, line });
            return error.WrongStatusFieldCount;
        }
        std.debug.print("status_test: 4 fields OK\n", .{});
```

- [ ] **Step 3: 검사 10의 산수 주석을 고친다**

**비교식(`line.len != status.MAX_LEN`)은 안 건드린다** — `MAX_LEN`이
`comptime`에 세지므로 저절로 36이 된다. 주석만 낡는다.

**지울 것:**

```zig
    // 가장 긴 조합은 `한`(3, `EN`보다 길다) + `공세벌 3-P3`(14) +
    // `드보락`(9) + 공백 넷이다.
```

**넣을 것:**

```zig
    // 가장 긴 조합은 `한`(3, `EN`보다 길다) + `공세벌 3-P3`(14) +
    // `드보락`(9) + `CAPS`(4) + 공백 여섯 = **36**이다.
    //
    // **IS-M1에서 이 값이 30에서 36으로 저절로 늘었다.** `statusText`에
    // `GAP + CAPS`를 더하면서 `MAX_LEN`의 산수도 함께 고쳤을 뿐, 버퍼를
    // 손으로 늘린 자리는 한 군데도 없다 — 그것이 이름 표에서 comptime에
    // 세게 한 값이고, IS-M0 실측 1이 "아직 오지 않았다"고 적어 둔 자리다.
```

- [ ] **Step 4: 검사 12를 새로 더한다 — 대문자 잠금은 글자를 안 바꾼다**

검사 11(`if (std.enums.values(hangul.Layout).len != 4)`) **뒤**,
`status_test: all checks passed` 줄 **앞**에 넣는다.

```zig
    // ── 검사 12: 대문자 잠금은 **글자를 안 바꾼다** ──────────────────
    //
    // design 결정 3이다 — `CAPS`와 `caps`는 흘깃 봐서 같아 보이므로 자리를
    // 유지한 채 **색**으로 가른다. 그래서 `statusText`는 `caps_lock`을 아예
    // 안 읽는다.
    //
    // **읽고 나서 무시하는 것보다 안 읽는 편이 낫다.** 나중에 누가 켜졌을 때
    // 글자를 바꾸고 싶어지면, 그 자리에 필드가 없다는 것이 먼저 눈에 띈다.
    //
    // 색을 고르는 것은 `main.zig`이고 그것을 보는 것은 게이트의
    // `status> caps ink` 줄이다 — **이 파일은 색을 볼 수 없다.**
    try expectText(.{ .caps_lock = true }, "EN  신세벌 PCS  쿼티  CAPS");
    try expectText(.{ .caps_lock = false }, "EN  신세벌 PCS  쿼티  CAPS");
```

- [ ] **Step 5: 검사가 실패하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: **`status_test` 실패.**

```
FAIL: got "EN  신세벌 PCS  쿼티", want "EN  신세벌 PCS  쿼티  CAPS"
```

- [ ] **Step 6: `status.zig`에 `CAPS`를 더한다**

`terminal/src/status.zig`의 `latinName` **뒤**, `MAX_LEN` **앞**에 넣는다.

```zig
/// `CAPS` 칸의 글자. **상태와 무관하게 언제나 이 넉 자다**(design 결정 3) —
/// 켜짐과 꺼짐은 글자가 아니라 **색**으로 가른다. `CAPS`와 `caps`로 가르지
/// 않는 것은 흘깃 봐서 같아 보이기 때문이고, 칸을 아예 지우지 않는 것은
/// 문자열 길이가 수시로 바뀌면 눈도 게이트도 어렵기 때문이다(결정 2).
///
/// **`main.zig`가 이 이름을 쓴다.** 상태 줄의 꼬리 `CAPS.len` 바이트만 다른
/// 색으로 그리는데, 그 길이를 저쪽에 4로 다시 적으면 여기를 고친 사람이
/// 저쪽을 안 고쳐도 컴파일이 통과한다.
pub const CAPS = "CAPS";
```

- [ ] **Step 7: `MAX_LEN`의 산수와 주석을 고친다**

**지울 것:**

```zig
/// 한/영 칸은 `한`(3)과 `EN`(2) 중 긴 쪽인 3이다.
///
/// **IS-M1이 여기에 `GAP.len + "CAPS".len`을 더한다** — 30에서 36이 된다.
```

**넣을 것:**

```zig
/// 한/영 칸은 `한`(3)과 `EN`(2) 중 긴 쪽인 3이다. `CAPS` 칸은 길이가 하나뿐
/// 이라 그대로 더한다.
///
/// **IS-M1에서 30이 36이 됐고, 버퍼를 손으로 늘린 자리는 없다.**
```

**지울 것:**

```zig
    break :blk 3 + GAP.len + hl + GAP.len + ll;
```

**넣을 것:**

```zig
    break :blk 3 + GAP.len + hl + GAP.len + ll + GAP.len + CAPS.len;
```

- [ ] **Step 8: `statusText`가 넷째 칸을 쓰게 한다**

**지울 것:**

```zig
    len += put(buf, len, latinName(state.latin_layout));
    return buf[0..len];
```

**넣을 것:**

```zig
    len += put(buf, len, latinName(state.latin_layout));
    len += put(buf, len, GAP);
    // **`state.caps_lock`을 안 읽는다**(design 결정 3). 켜짐과 꺼짐은 글자가
    // 아니라 색으로 갈리며, 색을 고르는 것은 `main.zig`다. `status_test`의
    // 검사 12가 이 사실을 못 박는다.
    len += put(buf, len, CAPS);
    return buf[0..len];
```

- [ ] **Step 9: 검사가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: 다섯 검사 전부 통과. 이 줄이 보여야 한다.

```
status_test: 4 fields OK
status_test: longest line is exactly MAX_LEN=36 OK
```

**36이 아니라 다른 값이 나오면 `MAX_LEN`의 산수와 이름 표가 어긋난 것이다** —
검사 10이 `>=`가 아니라 `==`로 보는 이유가 이것이다.

- [ ] **Step 10: 커밋**

```bash
git add terminal/src/status.zig terminal/src/status_test.zig
git commit -m "Give the status line a fourth field for the capital lock"
```

---

## Task 4: 색 셋으로 그린다

**Files:**
- Modify: `terminal/src/main.zig` (상수 둘 · `drawRun`/`drawStatus` · `Status` ·
  `render` 호출 · 상태 줄을 만드는 자리)

**호스트 검사가 없는 Task다.** `drawStatus`는 `main.zig`의 private이고
프레임버퍼가 필요하다 — 이것을 보는 것은 Task 5의 로그와 Task 6의 게이트다.
그래서 이 Task의 확인은 **컴파일이 되는가**까지다.

- [ ] **Step 1: 색 상수 둘을 더한다**

`terminal/src/main.zig`의 `STATUS_FG` 정의 자리(line 32~36)다.

**지울 것:**

```zig
/// 상태 줄의 글자 색(IS design 결정 7). 여백(`MARGIN_COLOR`) 위에서 읽히되
/// 눈을 안 끄는 회색이다 — 이것은 터미널의 내용이 아니라 창틀이다.
///
/// **IS-M1이 여기에 둘을 더한다**(`STATUS_ON`·`STATUS_OFF`).
const STATUS_FG: u32 = 0x00808890;
```

**넣을 것:**

```zig
/// 상태 줄 앞 세 칸의 글자 색(IS design 결정 7). 여백(`MARGIN_COLOR`) 위에서
/// 읽히되 눈을 안 끄는 회색이다 — 이것은 터미널의 내용이 아니라 창틀이다.
const STATUS_FG: u32 = 0x00808890;

/// 대문자 잠금이 **켜졌을 때** `CAPS` 칸의 색(IS-M1).
///
/// **SP-M0의 `CURRENT_BG`와 같은 앰버다.** 이 저장소는 이미 그 색으로
/// "지금 봐야 할 것"을 뜻한다(검색의 현재 매치) — 켜진 대문자 잠금이
/// 정확히 그런 것이다.
const STATUS_ON: u32 = 0x00C08000;

/// 꺼졌을 때 `CAPS` 칸의 색. 여백(`MARGIN_COLOR` = 0x00102030)보다 조금
/// 밝아 **자리는 보이되 안 읽힌다.**
///
/// **칸을 지우지 않는 이유는 결정 2다** — 문자열 길이가 수시로 바뀌면 눈도
/// 게이트도 어렵다. 그리고 이 색이 **게이트의 대조군**이다: 꺼졌을 때
/// `off>0`을 함께 보지 않으면 "아예 안 그렸다"와 "어둡게 그렸다"가 안
/// 갈린다.
///
/// **`MARGIN_COLOR`와 달라야 한다.** 같으면 `dumpStatus`가 여백 전체를
/// 세면서 픽셀 수만 개를 돌려준다.
const STATUS_OFF: u32 = 0x00303840;
```

- [ ] **Step 2: `Status`에 `caps`를 더한다**

`terminal/src/main.zig`의 `Status` struct(line 250 근처).

**지울 것:**

```zig
const Status = struct {
    text: []const u8,
    rows: u16,
};
```

**넣을 것:**

```zig
const Status = struct {
    text: []const u8,
    rows: u16,
    /// 대문자 잠금이 켜져 있는가(IS-M1).
    ///
    /// **`text`에는 안 들어 있다.** `CAPS` 넉 자는 언제나 그대로이고 이 값은
    /// **색**만 고른다(design 결정 3) — 그래서 `statusText`가 아니라 여기서
    /// 따로 나른다.
    caps: bool,
};
```

- [ ] **Step 3: 그리는 함수를 둘로 가른다**

`drawStatus`의 **본체만** 바꾼다. 위의 doc 주석 열몇 줄은 그대로 둔다.

**지울 것** (`fn drawStatus(` 부터 그 함수의 닫는 `}` 까지 전부):

```zig
fn drawStatus(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    rows: u16,
) !void {
    const grid_bottom = GRID_Y + @as(u32, rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) return;
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // `statusText`가 만든 문자열이라 UTF-8이 깨질 수 없다. 그래도 catch로
    // 받는 것은, 깨졌을 때 터미널이 죽는 대신 상태 줄만 사라지는 쪽이
    // 낫기 때문이다 — `pushCommit`이 인코딩 실패에 대해 고른 것과 같은 판단이다.
    var view = std.unicode.Utf8View.init(text) catch return;
    var it = view.iterator();
    var col: u32 = 0;
    while (it.nextCodepoint()) |cp| {
        const glyph = try cache.find(cp);
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, STATUS_FG);
        // `@max`로 0을 막는다. 폭 0인 글리프가 오면 col이 안 늘어 다음
        // 글자가 같은 자리에 겹쳐 그려지고, 증상이 "글자 하나가 뭉갠 것처럼
        // 보인다"라 원인에서 멀다.
        col += @max(1, glyph.cell_width / CELL_W);
    }
}
```

**넣을 것:**

```zig
fn drawStatus(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    st: Status,
) !void {
    const grid_bottom = GRID_Y + @as(u32, st.rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) return;
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // 꼬리 넉 자가 `CAPS` 칸이다. **길이를 4로 여기 다시 적지 않고
    // `status.CAPS`에서 얻는다** — 이름을 고치는 사람이 이 파일을 안 고쳐도
    // 되게. `statusText`가 언제나 그것으로 끝내므로 이 자름은 항상 맞는다.
    if (st.text.len < status.CAPS.len) return;
    const caps_at = st.text.len - status.CAPS.len;

    // **두 번 나눠 그린다.** 색이 칸마다 다르다고 해서 인덱스를 세며 한 번에
    // 그리면 바이트 위치와 col을 동시에 굴려야 하고, 폭 2 글자에서 어긋나기
    // 쉽다 — 그 어긋남은 "글자가 겹쳐 보인다"로 나타나 원인에서 멀다.
    const col = try drawRun(fb, cache, st.text[0..caps_at], y, STATUS_FG, 0);
    _ = try drawRun(
        fb,
        cache,
        st.text[caps_at..],
        y,
        if (st.caps) STATUS_ON else STATUS_OFF,
        col,
    );
}

/// 상태 줄의 한 토막을 `start_col`부터 한 색으로 그리고, **다음 칸의 col을**
/// 돌려준다.
///
/// `drawStatus`가 이것을 두 번 부른다 — 앞 세 칸은 `STATUS_FG`로, 꼬리의
/// `CAPS`는 잠금 상태에 따라 `STATUS_ON`이나 `STATUS_OFF`로.
///
/// **`drawPrompt`를 재사용하지 않는 이유가 이 함수의 두 줄에 있다**
/// (design 결정 6). 그쪽은 바이트 하나를 글자 하나로 세므로 `한`이 글리프
/// 셋으로 그려진다. 여기는 UTF-8을 디코드하고, 폭 2 글자는 두 칸을 전진한다.
fn drawRun(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    y: u32,
    fg: u32,
    start_col: u32,
) !u32 {
    // `statusText`가 만든 문자열이라 UTF-8이 깨질 수 없다. 그래도 catch로
    // 받는 것은, 깨졌을 때 터미널이 죽는 대신 상태 줄만 사라지는 쪽이
    // 낫기 때문이다 — `pushCommit`이 인코딩 실패에 대해 고른 것과 같은 판단이다.
    var view = std.unicode.Utf8View.init(text) catch return start_col;
    var it = view.iterator();
    var col = start_col;
    while (it.nextCodepoint()) |cp| {
        const glyph = try cache.find(cp);
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);
        // `@max`로 0을 막는다. 폭 0인 글리프가 오면 col이 안 늘어 다음
        // 글자가 같은 자리에 겹쳐 그려지고, 증상이 "글자 하나가 뭉갠 것처럼
        // 보인다"라 원인에서 멀다.
        col += @max(1, glyph.cell_width / CELL_W);
    }
    return col;
}
```

- [ ] **Step 4: `render`의 호출을 고친다**

`terminal/src/main.zig`의 line 228 근처.

**지울 것:**

```zig
    try drawStatus(fb, cache, st.text, st.rows);
```

**넣을 것:**

```zig
    try drawStatus(fb, cache, st);
```

- [ ] **Step 5: 상태 줄을 만드는 자리에 `caps`를 넣는다**

`terminal/src/main.zig`의 line 1096 근처.

**지울 것:**

```zig
        const status_line: Status = .{
            .text = status.statusText(&key_state, &status_buf),
            .rows = rows,
        };
```

**넣을 것:**

```zig
        const status_line: Status = .{
            .text = status.statusText(&key_state, &status_buf),
            .rows = rows,
            // **`statusText`가 아니라 여기서 읽는다**(design 결정 3). 잠금은
            // 글자가 아니라 색을 고르므로 순수 모듈이 알 일이 아니다.
            .caps = key_state.caps_lock,
        };
```

- [ ] **Step 6: 컴파일이 되는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build && zig build test
'
```

기대: 빌드 성공 + 다섯 검사 통과. **검사는 이 Task에서 하나도 안 바뀐다** —
`status_test`는 색을 볼 수 없기 때문이다(그것이 Task 3 Step 4의 주석이 적어
둔 것이다).

- [ ] **Step 7: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Paint the CAPS field bright when the lock is on"
```

---

## Task 5: `CAPS` 칸의 픽셀을 세어 찍는다

**Files:**
- Modify: `terminal/src/main.zig` (`dumpStatus` · 루프 상태 하나 · 호출)

- [ ] **Step 1: `dumpStatus`의 주석에 셋째 줄을 적는다**

`terminal/src/main.zig`의 line 569~574.

**지울 것:**

```zig
/// **줄이 둘인 이유가 이 milestone의 검증 구조다.** 여백은 격자 밖이라
/// `screen>`·`style>`·`ink>`가 하나도 못 본다. `text=`만 있으면 `statusText`가
/// 만든 문자열을 되읽는 것뿐이고 **"글자는 만들었는데 화면에 안 그렸다"를 못
/// 잡는다.** 그래서 띠 안에서 `STATUS_FG`인 픽셀을 직접 센다 — `dumpInk`가
/// `getPixel`로 프레임버퍼를 읽는 것과 같은 방법이다.
```

**넣을 것:**

```zig
/// **줄이 셋인 이유가 이 서브프로젝트의 검증 구조다.** 여백은 격자 밖이라
/// `screen>`·`style>`·`ink>`가 하나도 못 본다. `text=`만 있으면 `statusText`가
/// 만든 문자열을 되읽는 것뿐이고 **"글자는 만들었는데 화면에 안 그렸다"를 못
/// 잡는다.** 그래서 띠 안에서 우리 색인 픽셀을 직접 센다 — `dumpInk`가
/// `getPixel`로 프레임버퍼를 읽는 것과 같은 방법이다.
///
/// **셋째 줄(`caps ink`)은 `text=`가 원리적으로 못 보는 것을 본다**(IS-M1).
/// `CAPS` 칸은 켜지든 꺼지든 **글자가 똑같으므로**(design 결정 3) 갈리는
/// 것은 색뿐이다.
///
/// **x 범위를 안 잰다 — 띠 전체를 세도 답이 같다.** `STATUS_ON`과
/// `STATUS_OFF`는 여백 안에서 `CAPS` 칸에만 쓰이기 때문이다. 범위를 재려
/// 들면 `drawStatus`의 **col 전진 산수까지** 여기서 다시 해야 하고, 어긋나면
/// 언제나 0이 나온다 — 증상이 "안 그렸다"와 똑같아서 원인을 엉뚱한 데서
/// 찾게 된다.
///
/// **메모가 `text`만 보면 안 된다.** `CAPS`는 켜져도 글자가 안 바뀌므로,
/// `caps`를 함께 기억하지 않으면 CapsLock을 눌러도 **새 줄이 한 줄도 안
/// 찍힌다** — 그리고 그 증상은 "구멍이 안 고쳐졌다"와 구별이 안 된다
/// (둘 다 `on=0`이다).
```

- [ ] **Step 2: `dumpStatus`의 시그니처와 본체를 고친다**

**지울 것** (`fn dumpStatus(` 부터 그 함수의 닫는 `}` 까지 전부):

```zig
fn dumpStatus(
    fb: drm.Framebuffer,
    text: []const u8,
    rows: u16,
    last: *[status.MAX_LEN]u8,
    last_len: *?usize,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], text)) return;
    }
    @memcpy(last[0..text.len], text);
    last_len.* = text.len;
    std.debug.print("terminal: status> text={s}\n", .{text});

    // 띠 안에서 우리 색인 픽셀을 센다. `drawStatus`와 **같은 산수로** y를
    // 구해야 한다 — 어긋나면 언제나 0이 나오고, 증상이 "안 그렸다"와 똑같아서
    // 원인을 `drawStatus`에서 찾게 된다.
    const grid_bottom = GRID_Y + @as(u32, rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) {
        std.debug.print("terminal: status> ink fg=0 (no room below the grid)\n", .{});
        return;
    }
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    var count: usize = 0;
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < fb.width) : (col += 1) {
            if (fb.getPixel(col, y + row) & 0x00FFFFFF == STATUS_FG) count += 1;
        }
    }
    std.debug.print("terminal: status> ink fg={d}\n", .{count});
}
```

**넣을 것:**

```zig
fn dumpStatus(
    fb: drm.Framebuffer,
    st: Status,
    last: *[status.MAX_LEN]u8,
    last_len: *?usize,
    last_caps: *bool,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], st.text) and last_caps.* == st.caps) return;
    }
    @memcpy(last[0..st.text.len], st.text);
    last_len.* = st.text.len;
    last_caps.* = st.caps;
    std.debug.print("terminal: status> text={s}\n", .{st.text});

    // 띠 안에서 우리 색인 픽셀을 센다. `drawStatus`와 **같은 산수로** y를
    // 구해야 한다 — 어긋나면 언제나 0이 나오고, 증상이 "안 그렸다"와 똑같아서
    // 원인을 `drawStatus`에서 찾게 된다.
    const grid_bottom = GRID_Y + @as(u32, st.rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) {
        std.debug.print("terminal: status> ink fg=0 (no room below the grid)\n", .{});
        std.debug.print("terminal: status> caps ink on=0 off=0 (no room)\n", .{});
        return;
    }
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // **한 번 훑으며 셋을 함께 센다.** 띠를 세 번 훑을 이유가 없다.
    var fg: usize = 0;
    var on: usize = 0;
    var off: usize = 0;
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < fb.width) : (col += 1) {
            const px = fb.getPixel(col, y + row) & 0x00FFFFFF;
            if (px == STATUS_FG) fg += 1;
            if (px == STATUS_ON) on += 1;
            if (px == STATUS_OFF) off += 1;
        }
    }
    std.debug.print("terminal: status> ink fg={d}\n", .{fg});
    // **`on`과 `off`를 한 줄에 함께 찍는다.** 하나만 보면 "아예 안 그렸다"와
    // "반대 색으로 그렸다"가 안 갈린다 — 게이트가 언제나 둘을 같이 읽는다.
    std.debug.print("terminal: status> caps ink on={d} off={d}\n", .{ on, off });
}
```

- [ ] **Step 3: 루프 상태를 하나 더한다**

`terminal/src/main.zig`의 line 849~852.

**지울 것:**

```zig
    // 마지막으로 찍은 상태 줄. **`?usize`인 것에 뜻이 있다** — 0을 초기값으로
    // 쓰면 "빈 줄을 찍었다"와 "아직 아무것도 안 찍었다"가 안 갈린다.
    var last_status: [status.MAX_LEN]u8 = undefined;
    var last_status_len: ?usize = null;
```

**넣을 것:**

```zig
    // 마지막으로 찍은 상태 줄. **`?usize`인 것에 뜻이 있다** — 0을 초기값으로
    // 쓰면 "빈 줄을 찍었다"와 "아직 아무것도 안 찍었다"가 안 갈린다.
    var last_status: [status.MAX_LEN]u8 = undefined;
    var last_status_len: ?usize = null;
    // **글자와 따로 기억해야 한다**(IS-M1). `CAPS` 칸은 켜져도 글자가 안
    // 바뀌므로, 이 값이 없으면 CapsLock을 눌러도 새 `status>` 줄이 한 줄도
    // 안 찍힌다. 첫 프레임은 `last_status_len`이 null이라 어차피 찍히므로
    // 초기값은 무엇이든 된다.
    var last_status_caps = false;
```

- [ ] **Step 4: 호출을 고친다**

`terminal/src/main.zig`의 line 1113.

**지울 것:**

```zig
        dumpStatus(fb, status_line.text, status_line.rows, &last_status, &last_status_len);
```

**넣을 것:**

```zig
        dumpStatus(fb, status_line, &last_status, &last_status_len, &last_status_caps);
```

- [ ] **Step 5: 컴파일이 되는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build && zig build test
'
```

기대: 빌드 성공 + 다섯 검사 통과.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Count the CAPS field pixels in both colours"
```

---

## Task 6: 게이트가 "키 하나 더 안 치고 밝아지는가"를 본다

**Files:**
- Modify: `hangul/check.sh` (헬퍼 하나 · 검사 0a·2a의 기대값 · 새 판정 둘 ·
  검사 13의 주석)

- [ ] **Step 1: 헬퍼 `status_caps`를 더한다**

`hangul/check.sh`의 `status_ink()` **바로 뒤**(line 166 근처)에 넣는다.

```sh
# 마지막 `status> caps ink` 줄에서 값 하나(`on`이나 `off`)를 뽑는다.
#
# **이 줄이 IS-M1의 판정 전부다.** `CAPS` 칸은 켜지든 꺼지든 글자가 같으므로
# (design 결정 3) `status_text`로는 잠금 상태를 볼 수 없다 — 갈리는 것은
# 색뿐이고, 색은 프레임버퍼를 직접 읽어야 보인다.
#
# `tr -d '\r'`는 `status_text`와 같은 이유다(HI-M1 실측 4). `off=`가 줄 끝이라
# 안 지우면 `"37"`이 아니라 `"37\r"`이 나오고, `[ "$X" -le 0 ]`가
# **"integer expression expected"로 죽는다** — 값이 같아 보이는데 실패하는
# 그 함정의 사촌이다.
status_caps() {
  grep -a 'terminal: status> caps ink ' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}
```

- [ ] **Step 2: 검사 0a의 기대값을 고치고 판정 셋을 얹는다**

**지울 것:**

```sh
echo "=== the status line should be drawn in the bottom margin ==="
TEXT="$(status_text)"
if [ "$TEXT" != "EN  공세벌 3-P3  쿼티" ]; then
  report_failure "the status line reads \"${TEXT}\", expected \"EN  공세벌 3-P3  쿼티\""
fi
INK="$(status_ink)"
if [ -z "$INK" ]; then
  report_failure "no 'status> ink fg=' line at all, so dumpStatus never ran"
fi
if [ "$INK" -le 0 ]; then
  report_failure "the status band has no STATUS_FG pixels (fg=${INK}), so nothing was drawn"
fi
echo "the status line reads \"${TEXT}\" and put ${INK} pixel(s) in the margin"
```

**넣을 것:**

```sh
echo "=== the status line should be drawn in the bottom margin ==="
TEXT="$(status_text)"
if [ "$TEXT" != "EN  공세벌 3-P3  쿼티  CAPS" ]; then
  report_failure "the status line reads \"${TEXT}\", expected \"EN  공세벌 3-P3  쿼티  CAPS\""
fi
INK="$(status_ink)"
if [ -z "$INK" ]; then
  report_failure "no 'status> ink fg=' line at all, so dumpStatus never ran"
fi
if [ "$INK" -le 0 ]; then
  report_failure "the status band has no STATUS_FG pixels (fg=${INK}), so nothing was drawn"
fi
# 부팅 직후에는 대문자 잠금이 꺼져 있다. **둘을 함께 본다** — `on=0`만 보면
# `CAPS` 칸을 **아예 안 그린** 코드도 통과한다(IS-M1).
CAPS_ON="$(status_caps on)"
CAPS_OFF="$(status_caps off)"
if [ -z "$CAPS_ON" ]; then
  report_failure "no 'status> caps ink' line at all, so the CAPS field was never measured"
fi
if [ "$CAPS_ON" -ne 0 ]; then
  report_failure "the CAPS field is lit at boot (on=${CAPS_ON}), expected the dim colour"
fi
if [ "$CAPS_OFF" -le 0 ]; then
  report_failure "the CAPS field has no dim pixels (off=${CAPS_OFF}), so it was never drawn"
fi
echo "the status line reads \"${TEXT}\", ${INK} pixel(s) of text and a dim CAPS (off=${CAPS_OFF})"
```

- [ ] **Step 3: 검사 2a의 기대값을 고친다**

**지울 것:**

```sh
TEXT="$(status_text)"
if [ "$TEXT" != "한  공세벌 3-P3  쿼티" ]; then
  report_failure "after Shift+Space the status line reads \"${TEXT}\", expected \"한  공세벌 3-P3  쿼티\""
fi
```

**넣을 것:**

```sh
TEXT="$(status_text)"
if [ "$TEXT" != "한  공세벌 3-P3  쿼티  CAPS" ]; then
  report_failure "after Shift+Space the status line reads \"${TEXT}\", expected \"한  공세벌 3-P3  쿼티  CAPS\""
fi
```

- [ ] **Step 4: 검사 13의 주석을 고치고 판정을 얹는다**

`Action.hangul`이 `Action.redraw`가 되면서 **긴 CapsLock도 `hangul>` 줄을
찍게 됐다.** 그 사실을 주석에 반영하고, 새 판정을 **`type_keys` 앞에** 넣는다.

**지울 것:**

```sh
# **한/영이 안 바뀐 것도 함께 본다.** `hangul_field`는 마지막 `hangul>` 줄을
# 읽는데, 그 줄은 `Action.hangul`이 나올 때만 찍힌다 — 긴 CapsLock이 잘못
# 전환하면 새 줄이 `on=true`로 찍혀서 여기가 갈린다.
echo "=== sendkey caps_lock 500 (hold) ==="
hold_key caps_lock 500
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a long CapsLock changed hangul to on=${ON}, expected false"
fi
type_keys a b c 1
```

**넣을 것:**

```sh
# **한/영이 안 바뀐 것도 함께 본다.** `hangul_field`는 마지막 `hangul>` 줄을
# 읽는다. **IS-M1 전에는 그 줄이 `Action.hangul`이 나올 때만 찍혔고, 이제는
# 긴 CapsLock도 `Action.redraw`를 돌려주므로 매번 찍힌다** — 값이 `on=false`
# 라 기대는 그대로이고, 잘못 전환하면 `on=true`로 찍혀서 여기가 갈린다.
echo "=== sendkey caps_lock 500 (hold) ==="
hold_key caps_lock 500
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a long CapsLock changed hangul to on=${ON}, expected false"
fi

# ── 검사 13a: 잠금이 **키 하나 더 안 치고** 화면에 뜬다 ─────────────────
#
# **이 자리가 IS-M1의 심장이고, design 결정 8의 구멍을 보는 유일한 판정이다.**
# `Action.redraw`가 없으면 CapsLock을 뗀 프레임에는 아직 어두운 `CAPS`가
# 그려져 있고, 아래 `type_keys`가 만드는 **다음 프레임에서야** 밝아진다.
#
# **그래서 이 판정이 `type_keys`보다 앞이어야 한다.** 뒤에 두면 구멍이 있는
# 코드도 통과한다 — 순서 하나가 이 검사의 전부다.
#
# **`off=0`을 함께 보는 것이 짝이다.** `on>0`만 보면 두 색을 겹쳐 그린
# 코드도 통과한다.
CAPS_ON="$(status_caps on)"
CAPS_OFF="$(status_caps off)"
if [ "$CAPS_ON" -le 0 ]; then
  report_failure "a long CapsLock did not light the CAPS field (on=${CAPS_ON}); Action.redraw is missing"
fi
if [ "$CAPS_OFF" -ne 0 ]; then
  report_failure "the CAPS field still has ${CAPS_OFF} dim pixel(s) after the lock turned on"
fi
echo "the CAPS field lit up (on=${CAPS_ON}) right after the long CapsLock, with no extra key"

type_keys a b c 1
```

- [ ] **Step 5: 검사 14에 짝 판정을 얹는다**

**키를 하나도 안 더한다** — 검사 14가 이미 두 번째 긴 CapsLock을 누른다
(확정 7).

**지울 것:**

```sh
echo "=== sendkey caps_lock 500 again ==="
hold_key caps_lock 500
type_keys a
```

**넣을 것:**

```sh
echo "=== sendkey caps_lock 500 again ==="
hold_key caps_lock 500

# ── 검사 14a: 잠금이 풀리면 `CAPS`도 다시 어두워진다 ────────────────────
#
# **켜지는 것만 보면 토글이 한 방향으로만 동작해도 통과한다** — 검사 13a와
# 이것이 이루는 짝이, 검사 1과 9가 Shift+Space에 대해 이루는 짝과 같다.
# 여기도 `type_keys` **앞**이다.
CAPS_ON="$(status_caps on)"
CAPS_OFF="$(status_caps off)"
if [ "$CAPS_ON" -ne 0 ]; then
  report_failure "the CAPS field is still lit (on=${CAPS_ON}) after the lock was released"
fi
if [ "$CAPS_OFF" -le 0 ]; then
  report_failure "the CAPS field went blank (off=${CAPS_OFF}) instead of dim after release"
fi
echo "the CAPS field went dim again (off=${CAPS_OFF}) right after the second long CapsLock"

type_keys a
```

- [ ] **Step 6: 체인을 단독으로 돌린다**

**약 3~4분** 걸린다(빌드 + 부팅 한 번).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash hangul/check.sh
```

기대: 마지막 줄이 `HI check PASS`. 새 줄 넷이 중간에 보인다.

```
the status line reads "EN  공세벌 3-P3  쿼티  CAPS", NNN pixel(s) of text and a dim CAPS (off=NN)
the status line followed the toggle: "한  공세벌 3-P3  쿼티  CAPS"
the CAPS field lit up (on=NN) right after the long CapsLock, with no extra key
the CAPS field went dim again (off=NN) right after the second long CapsLock
```

**실패했을 때 어디를 보는가.**

| 증상 | 원인 |
|---|---|
| `no 'status> caps ink' line at all` | Task 5 Step 2의 `print`가 안 들어갔다 |
| `text=`에 `CAPS`가 없다 | Task 3 — `statusText`가 넷째 칸을 안 쓴다 |
| 부팅 직후 `on=0 off=0` | **Task 4다** — `drawStatus`가 `CAPS`를 안 그렸다(`caps_at` 자름이나 둘째 `drawRun`) |
| 부팅 직후 `off`가 수만 개 | `STATUS_OFF`가 `MARGIN_COLOR`와 같다 |
| 긴 CapsLock 뒤 `on=0`인데 부팅 직후는 맞다 | **Task 2의 `return .redraw;`** 또는 **Task 5의 `last_caps` 메모**(확정 4) — 둘을 가르려면 시리얼 로그에서 `status>` 줄 수를 센다. 메모가 빠졌으면 CapsLock 뒤에 **새 줄이 아예 없다** |
| `integer expression expected` | `tr -d '\r'`가 빠졌다(HI-M1 실측 4) |
| 검사 13의 `ABC1`이 안 나온다 | 새 판정 둘이 `type_keys` **뒤에** 들어갔다 |

- [ ] **Step 7: 커밋**

```bash
git add hangul/check.sh
git commit -m "Check that the CAPS field lights up with no extra key"
```

---

## Task 7: 루트 게이트 3회전과 문서 갱신

- [ ] **Step 1: 루트 게이트를 돌린다**

**약 19분** 걸린다. 아홉 체인 × 3회.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh ; } 2> /tmp/is-m1.time
tail -3 /tmp/is-m1.time
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간이 얼마나 늘어야 정상인가.** **키를 하나도 안 더했다.** 늘어나는 것은
프레임 몇 개(긴 CapsLock 넷이 이제 다시 그린다)와 `status>` 줄 몇 개뿐이다.
직전 값이 **19분 06.47초**(IS-M0)다. **몇십 초 안의 차이는 잡음이다**
(HI-M2 실측 11: 같은 세션 삼중값의 폭이 2.29초, 다른 날 잡음은 ±3분).

**분 단위로 늘었다면** `status>` 줄이 매 프레임 찍히고 있다는 뜻이다 —
`dumpStatus`의 메모 조건에 `and last_caps.* == st.caps`를 빼먹고 **`or`로**
썼는지 본다.

- [ ] **Step 2: `status>` 줄 수를 세어 "매 프레임 안 찍는다"를 확인한다**

**게이트 시간보다 이쪽이 곧다**(IS-M0 실측 3). 시리얼 로그를 호스트에서
읽는 방법은 IS-M0 실측 4가 찾아 둔 것이다 — **파일을 하나도 안 고친다.**

```bash
mkdir -p out
docker run --rm -e TMPDIR=/workspace/out -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash hangul/check.sh
grep -ac 'terminal: screen>' out/tmp.*
grep -ac 'terminal: status>' out/tmp.*
```

기대: `status>`가 `screen>`의 **세 배보다 훨씬 적다.** IS-M0에서
`screen>` 57번에 `status>` 12줄이었다. 이제 줄이 셋이 됐고 전환이 여덟
번(한/영 여섯 + 대문자 잠금 둘)이므로 **24줄 안팎**이 기대값이다.
매 프레임 찍히면 171줄(57×3)이다.

**세고 나면 `out/`을 지운다** — 빌드 산출물처럼 저장소에 남기지 않는다.

```bash
rm -rf out
```

- [ ] **Step 3: design의 `Status:` 줄을 고친다**

`docs/superpowers/specs/2026-09-02-tars-input-status-design.md`의 line 4~8.

**지울 것:**

```markdown
**Status:** **IS-M0 완료(2026-09-02).** 상태 줄이 아래 여백에 뜨고 칸이 셋이다
(한/영 · 한글 자판 · 영문 자판). 게이트 아홉 체인 3/3으로 **19분 06.47초**.
plan은 `docs/superpowers/plans/2026-09-02-tars-input-status-is-m0.md`이고 값은
아래 "IS-M0이 실측한 것" 절에 있다. **다음은 IS-M1이고 plan은 그 시점에 새로
쓴다.**
```

**넣을 것** (게이트 시간은 Step 1의 실제 값으로 채운다):

```markdown
**Status:** **완료(IS-M0 2026-09-02 · IS-M1 2026-09-08).** 상태 줄이 아래
여백에 뜨고 칸이 넷이다(한/영 · 한글 자판 · 영문 자판 · `CAPS`).
`Action.hangul`이 `Action.redraw`가 되어 **긴 CapsLock이 그 자리에서 화면을
다시 그린다.** 게이트 아홉 체인 3/3으로 **NN분 NN초**. plan은
`docs/superpowers/plans/2026-09-02-tars-input-status-is-m0.md`와
`.../2026-09-08-tars-input-status-is-m1.md`이고, 값은 아래 "IS-M0이 실측한
것"·"IS-M1이 실측한 것" 절에 있다.
```

- [ ] **Step 4: design에 "IS-M1이 실측한 것" 절을 더한다**

"IS-M0이 실측한 것" 절 **뒤**, "비목표" 절 **앞**에 넣는다. **실행하며 실제로
관찰한 것만 적는다** — 아래는 자리를 잡아 두는 목록이고, 값은 그때 채운다.

적을 것 후보(실제로 일어난 것만 남긴다):

- **`MAX_LEN`이 손을 안 대고 30에서 36이 됐다.** IS-M0 실측 1이 "그 값이
  값을 하는 자리는 아직 오지 않았다"고 적어 둔 것의 결말이다. 검사 10이
  `==`로 보므로 산수가 어긋났으면 그 자리에서 갈렸다.
- **컴파일러가 알려준 자리가 정확히 몇 개였는가.** Task 1 Step 2의 에러
  목록이 design의 "열넷"과 맞았는지, 빠진 자리가 있었는지.
- **`dumpStatus`의 메모에 `caps`를 안 더했다면 어떻게 됐는가.** 실제로
  밟았다면 증상을 적는다 — 안 밟았으면 "plan이 예측해서 안 밟았다"를 적는다
  (HI-M3 실측 2가 같은 종류다).
- **`caps ink` 값 셋**(`off` 기준선 · `on` 기준선 · 세 번의 회전에서 같았는가).
- **게이트 시간**과 그 차이가 설명되는지.
- **`status>` 줄 수**(Step 2의 값).

- [ ] **Step 5: `docs/decisions/project_input_status.md`를 고친다**

**새로 만들지 않는다 — 이미 있다.** IS-M0까지의 내용이 들어 있고, 그중 한
문장이 **지금 낡았다**:

> **`Action.hangul`의 갱신 구멍이 아직 열려 있고 지금은 버그가 아니라는 것**

이것을 "IS-M1이 `.redraw`로 넓혀 닫았다"로 고치고, 서브프로젝트 상태를
**완료**로 바꾼다. IS-M1이 새로 배운 것(Step 4의 목록에서 살아남은 것)을
덧붙인다.

- [ ] **Step 6: `MEMORY.md`의 IS 줄을 고친다**

마지막 줄(`- [Input status](docs/decisions/project_input_status.md) — …`)의
**`IS-M0 완료`, 다음은 IS-M1**을 **완료(IS-M0~M1)**로 바꾸고, 낡은
"구멍이 아직 열려 있다"를 고친다. **줄을 새로 더하지 않는다** — 색인은 한
서브프로젝트에 한 줄이다.

- [ ] **Step 7: `HANDOFF.md`를 다시 쓴다**

맨 위 절을 IS-M1 완료 기준으로 바꾼다. **다음 서브프로젝트는 아직
정하지 않았다** — HI가 남긴 이월 숙제 넷(기호 확장 · Patal의 옵션 trait들 ·
모아주기 · copy mode 검색창의 한글 입력)과 `project_target_hardware.md`가
가리키는 실머신 커널 `.config`가 후보라는 것만 적는다.

- [ ] **Step 8: 문서를 커밋한다**

```bash
git add docs/superpowers/specs/2026-09-02-tars-input-status-design.md \
        docs/decisions/project_input_status.md MEMORY.md HANDOFF.md
git commit -m "Close out IS-M1 with the CAPS field on screen"
```

---

## 이 plan이 미리 짚어 두는 함정

**1. `.hangul =>` 갈래 넷이 서로 비슷하게 생겼다**(확정 9 · IS-M0 실측 7).
`input_test.zig`의 81·120·162·200이다. **에러 메시지의 `want ...` 부분이
넷 다 다르므로** 그것을 표적으로 삼는다. 편집 뒤
`rg -n '\.hangul' terminal/src/`가 **아무것도 안 나와야 한다**(주석의
`hangul_layout` 같은 것은 `.hangul`이 아니다).

**2. 게이트 판정이 `type_keys` 뒤로 밀리면 아무것도 안 본다.** 이 milestone
전체가 "그 자리에서 밝아지는가"이고, 다음 키가 어차피 다시 그린다.
**증상이 없다** — 통과한다.

**3. `dumpStatus`의 메모.** `text`만 비교하면 CapsLock이 새 줄을 못 만든다
(확정 4).

**4. `STATUS_OFF`가 `MARGIN_COLOR`와 가깝다.** 0x00303840과 0x00102030이다.
**같으면** 여백 전체가 세어져 `off`가 수만 개로 나온다 — 값이 "0이 아니다"만
보는 판정은 그것도 통과시킨다. 그래서 검사 13a가 **`off=0`을 정확히** 본다.

**5. `hangul>` 줄이 늘어난다.** 긴 CapsLock이 `.redraw`를 돌려주면
`main.zig`가 `dumpHangul`을 부르므로 `hangul> on=false preedit=` 한 줄이
더 찍힌다. 게이트 검사 13·14가 그 줄을 읽는데 **값이 기대와 같아** 안
깨진다. 주석만 낡으므로 Task 6 Step 4에서 고친다.

**6. `drawRun`의 반환값을 버리면 `CAPS`가 첫 칸에 겹쳐 그려진다.**
`const col = try drawRun(...)`의 `col`을 둘째 호출에 안 넘기면 상태 줄
전체가 뭉개진다 — 증상이 화면에만 나타나고 `text=`는 멀쩡하다.
게이트에서는 `ink fg=`가 확 줄고 `off`가 겹침만큼 줄어든다.
