# TARS Copy Navigation CN-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** copy mode에서 `/`로 스크롤백을 검색해 커서를 매치로 옮기고, `n`/`N`으로
매치 사이를 왕복한다. 지금은 `hjkl`과 `w`/`b`가 전부라, 1000줄짜리 스크롤백에서
원하는 줄에 닿으려면 화면을 몇십 번 넘겨야 한다.

**Design doc:** `docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`
(결정 4·5·6·7·8·9·10·11이 이 milestone의 몫이다. **design은 승인되어 있으므로
다시 논의하지 않는다.**)

**Tech Stack:** Zig 0.16, libghostty-vt(`search.Screen`), evdev, QEMU monitor
`sendkey`, bash 게이트 스크립트

## 이 milestone은 CN-M0보다 훨씬 크다

CN-M0은 기존 구조에 형제 함수 하나와 표 두 줄을 더하는 일이었다. CN-M1은
**이 시스템에 없던 개념 둘**을 만든다.

1. **화면에 우리 글자를 그리는 일.** 지금까지 프레임버퍼에 나타난 모든 글자는
   `cells()`가 넘긴 셀, 즉 셸의 것이었다. 프롬프트는 처음으로 **우리가 만든
   글자**다.
2. **모드 안의 모드.** copy mode 안에서 키가 명령이 아니라 **글자**가 되는
   구간이 생긴다.

그래서 Task가 여섯이다. **각 Task 끝은 커밋 지점이고, 그 시점에 무언가가 실제로
동작한다** — 중간에 멈춰도 저장소가 반쯤 짜인 상태로 남지 않는다.

| Task | 끝나면 무엇이 되는가 |
|---|---|
| 1 | `Copy`가 `union(enum)`이 된다. **동작은 하나도 안 바뀐다** |
| 2 | `/abc`를 치면 로그에 `find> needle=abc`가 찍힌다(화면엔 아직 안 보인다) |
| 3 | 그 프롬프트가 화면 마지막 줄에 **보인다** |
| 4 | Enter가 검색을 돌려 커서가 매치로 **간다** |
| 5 | `n`/`N`이 매치 사이를 왕복한다 |
| 6 | 게이트가 그것을 게스트에서 보고, 문서가 갱신된다 |

---

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### CN-M0이 실행으로 증명해 둔 것

1. **`copyPlace(pin)`이 이미 있다**(`vt.zig:508`). pin 하나를 받아 커서를 놓고,
   화면 밖이면 뷰포트를 민다. **검색의 커서 이동은 이 함수를 그대로 쓴다** —
   CN-M1이 새로 짤 것이 아니다.
2. **`pointFromPin(.viewport, …)`은 아래쪽 밖을 안 알려준다.** `copyPlace`의
   `if (co.y >= rows) return;`이 그것을 가른다. 이미 들어 있다.
3. **`copyApply`가 모든 이동 수단이 통과하는 문이다**(design 결정 11).
   `n`/`N`도 같은 문을 통과한다.
4. **`main.zig`의 copy switch에 `else`가 없다.** variant를 더하면 컴파일러가
   배선할 자리를 짚는다. **Task 1이 이 신호를 일부러 아껴 둔다** — union 전환과
   variant 추가를 같은 Step에서 하면 컴파일 에러 목록에 두 가지가 섞여 무엇이
   무엇 때문인지 안 갈린다.
5. **검사도 화면을 만든 뒤 `cells()`를 한 번 부르고 시작한다.**
6. **자기 화면을 새로 만든다.** CN-M0의 `wm`이 앞 검사들을 하나도 안 흔든
   이유이고, CN-M1은 `fm`을 만든다.

### 이 plan을 쓰면서 소스에서 확인한 것 아홉

**전부 vendor된 ghostty 소스와 우리 소스를 직접 읽어서 얻었다. 프로브는 돌리지
않았고, 이 사실들은 각 Task의 검사로 옮겨 실행으로 다시 증명한다.**

**1. `search`는 우리 모듈로 공개되어 있다.** `lib_vt.zig:52`가
`pub const search = terminal.search;`다. 그러므로
**`ghostty_vt.search.Screen`이 `ScreenSearch`**다. (`search.Thread`만
`options.artifact`로 막혀 있고 우리는 안 쓴다.)

**2. design 위험 1이 해소됐다 — `ScreenSearch`는 우리 선택을 안 건드린다.**
`selectNext`/`selectPrev`(`search/screen.zig:817`·`:871`)가 하는 일은 tracked
pin을 잡고 `self.selected`를 바꾸는 것뿐이다. `search/screen.zig` ·
`search/pagelist.zig` · `search/active.zig` 셋 전체에 `screen.select(` 도
`screen.selection =` 도 **없다.** 그러므로 `ScreenSearch`를 "매치의 좌표를
알려주는 것"으로만 쓰는 설계가 그대로 성립하고, **우리가 피해 다닐 것이
없다.**

**3. 매치에서 pin을 꺼내는 길이 한 줄이다.** `selectedMatch()`(`:771`)가
`?FlattenedHighlight`를 주고, 그 타입에 `startPin()`(`highlight.zig:174`)이
있다. **`copyPlace`가 받는 타입과 정확히 같다.**

**4. `Select.next`의 주석은 "non-wrapping"이라고 하는데 코드는 감긴다.**
`selectNext`가
`const next_idx = if (prev.idx + 1 >= active_len + history_len) 0 else prev.idx + 1;`
(`:851`)이다. **주석을 믿지 말고 코드를 믿는다.** `n`을 계속 누르면 가장 오래된
매치 다음에 가장 최근 매치로 되돌아온다. 우리는 그것을 감추지 않는다.

**5. needle은 라이브러리가 복사한다.** `SlidingWindow.init`이
`const needle = try alloc.dupe(u8, needle_unowned);`(`sliding_window.zig:122`)다.
**고정 128바이트 버퍼의 슬라이스를 그대로 넘겨도 된다.**

**6. `ScreenSearch`는 `screen: *Screen`을 들고 있다**(`:42`). 대체 화면(vim
등)으로 갈아타면 `term.screens.active`가 달라져 **그 포인터가 낡는다.**
`feed`에서 포인터 하나를 비교해 잡는다 — `pointFromPin`을 부르는 앵커 감시와
달리 **비용이 없다.**

**7. `searchAll()`은 정말로 블로킹이다.** `tick`을 `SearchComplete`가 날
때까지 돌린다(`:269`). 주석이 "for performance, it is recommended to use tick
and feed"라고 권하지만, Enter 확정 방식에서는 한 번뿐이라 그것이 맞다
(design 결정 5). **얼마나 걸리는지는 우리가 재서 로그에 찍는다.**

**8. `render()`가 `fb.present()`로 끝난다**(`main.zig:111`). 그러므로
**오버레이는 `render` 안에서 present 앞에 그려야 한다.** 밖에서 그리면 다음
프레임까지 화면에 안 나온다. design 결정 7이 "격자를 다 그린 뒤에 덮는다"라고만
말하고 present를 안 짚었는데, 실물에서는 이 한 줄이 그 뜻을 정한다.

**9. `pointFromPin(.screen, pin).screen.y`가 절대 행 번호다.** `anchorY`
(`vt.zig:172`)가 이미 쓰고 있다. **매치가 커서보다 위인지를 이 값으로 가른다.**

### 그리고 우리 저장소에서 확인한 것 둘

**`expectCopy`가 `cmd == want`로 비교한다**(`input_test.zig:62`). **Zig에서
union에는 `==`가 없다.** Task 1이 `std.meta.eql`로 바꾼다. 이것이 union 전환이
깨뜨리는 **유일한** 검사 코드다.

**`n`은 `input_test`의 "모르는 키" 목록에 없다.** CN-M0이 `w`에서 겪은 함정이
이번에는 **없다.** 대신 CN-M0이 그 자리에 남긴 예고 주석("`e`와 `n`은 아직
모르는 키이지만 영영 그렇지는 않다")이 이제 절반만 맞게 되므로 **Task 5가 그
주석을 갚는다.**

---

## 이번에 정하는 것 여섯 (design doc이 안 정한 자리)

### 결정 1. 프롬프트 상태가 두 곳에 있고, 그것이 옳다

`input.State.mode`에 `.find`가 생기고, `vt.Screen`에 `find_open`이 생긴다.
같은 사실이 두 곳에 있다.

**중복이 아니라 서로 다른 일이다.** `input.zig`는 **키를 글자로 돌리기 위해**
알아야 하고(그것을 모르면 `n`이 명령인지 글자인지 못 가른다), `vt.zig`는
**그려야 하기 때문에** 알아야 한다. 그리고 `input.zig`는 `vt.zig`를 import하지
않는다(IP design 결정 6) — 물어볼 길이 아예 없다.

**copy mode 자체가 이미 같은 모양이다.** `State.mode == .copy`와
`Screen.copy_cursor != null`이 같은 사실을 두 곳에서 들고 있고, 그것이 CM-M0
이래 문제를 일으킨 적이 없다. 갱신 경로가 `main.zig`의 배선 하나뿐이기
때문이다. **`.find`도 같은 규율을 따른다: `find_open`을 만지는 것은
`findOpen`·`findCancel`·`findSubmit`·`copyExit` 넷뿐이다.**

### 결정 2. Backspace는 빈 프롬프트에서 아무 일도 안 한다

vim은 빈 프롬프트에서 Backspace를 누르면 프롬프트를 닫는다. **우리는 안
닫는다.**

닫으면 Esc와 뜻이 겹치고, 검색어를 지우려고 Backspace를 연타하던 사람이 마지막
한 번에 프롬프트를 잃는다. 그것을 되찾으려면 `/`를 다시 눌러야 하는데, 그때
지난 검색어는 이미 없다(검색 기록은 design이 비워 둔 자리다). **닫는 길은
Esc 하나뿐이고, 그것이 결정 9가 세운 두 겹 구조와도 맞는다.**

### 결정 3. `/`는 커서보다 **위**에 있는 첫 매치로 가고, `n`/`N`은 안 가린다

design 결정 4가 "`/`는 위(과거)로 찾는다"로 정했다. 그런데 라이브러리의
`select(.next)`는 **커서와 무관하게** 목록의 다음 항목을 준다 — 커서를 `k`로
올려 둔 상태에서 `/`를 누르면 커서가 **아래로 뛴다.**

그래서 `/`의 첫 이동만 **매치의 screen y가 커서의 screen y보다 작을 때까지**
넘긴다. 넘기는 횟수는 `matchesLen()`으로 막는다 — 목록이 감기므로(확정 사실 4)
상한이 없으면 영원히 돈다.

**`n`/`N`은 안 가린다.** `/`는 "지금부터 위로 찾아라"이지만 `n`은 "그 목록에서
계속"이다. `n`에도 필터를 걸면 목록의 끝에 닿았을 때 아무 일도 안 일어나고,
사람은 "고장 났다"로 읽는다. **감기는 것이 보이는 편이 낫다.**

### 결정 4. `dumpStyles`는 프롬프트가 덮은 줄을 건너뛴다

`dumpStyles`는 셀마다 두 줄을 찍는다 — 파서가 본 색(`style>`)과 프레임버퍼에서
되읽은 픽셀(`pixel>`)이다. **두 겹인 것에 뜻이 있다**(TR design 결정 7):
`style>`만 찍으면 파서가 옳고 렌더러가 틀렸을 때 게이트가 통과한다.

프롬프트는 그 마지막 줄을 **덮는다.** 그러면 그 줄의 `pixel>`은 셀의 색이
아니라 우리 프롬프트의 색을 말하게 되고, **두 겹 검사의 전제가 그 줄에서만
깨진다.**

지금 이것을 보는 체인은 없다(`pixel>`을 쓰는 것은 `render` 체인 하나뿐이고 그
체인은 copy mode에 안 들어간다). **그러나 게이트가 못 보는 부채를 새로 만들지
않는다**(`project_gate_chain_composition`). 덮은 줄은 아예 건너뛰고, **몇 개를
건너뛰었는지 한 줄로 적는다** — 조용히 자르지 않는 것이 이 파일의 기존
규율이다.

### 결정 5. 검색에 걸린 시간을 `find>` 줄에 찍는다

design 결정 5가 "블로킹이 사람이 느낄 만한지는 CN-M1 계획에서 실측한다"고
남겼다. **프로브를 돌리지 않고 게이트가 재게 한다.**

`main.zig`는 이미 `std.Io.Clock.now(.awake, init.io)`로 첫 프레임을 재고 있다
(`:578`). 같은 시계로 `findSubmit` 앞뒤를 감싸 `us=`를 찍는다. 게이트가 그 값을
로그에서 뽑아 출력하므로, **1000줄 스크롤백에서의 실측값이 회차마다 남는다.**

값을 놓고 무엇을 할지는 그때 정한다 — 이 plan은 재는 데까지만 한다.

### 결정 6. 프롬프트는 반전하지 않고 평범한 색으로 그린다

`v`가 만드는 선택도, copy 커서도 "색 둘을 맞바꾼다"로 나타난다. 프롬프트까지
반전하면 화면 맨 아래에 흰 띠가 생겨 **선택과 구분이 안 된다.**

vim도 less도 `/` 프롬프트를 평범한 색으로 그린다. 앞의 `/` 한 글자가 그것이
프롬프트라는 표시이고, 그 자리는 원래 셸 프롬프트가 있던 줄이라 사람이 이미
보고 있다.

---

## Task 1: `Copy`를 `union(enum)`으로 바꾼다

**Files:**
- Modify: `terminal/src/input.zig` (`Copy` 선언)
- Modify: `terminal/src/input_test.zig` (`expectCopy`의 비교)

**이 Task는 동작을 하나도 안 바꾼다.** variant도 안 더한다. **그것이
요점이다** — 형태 전환과 기능 추가를 같은 Step에 두면 컴파일 에러 목록에 두
가지가 섞여 무엇이 무엇 때문인지 안 갈린다. CN-M0이 "enum 먼저, 그다음 컴파일러가
부르는 자리"로 배운 규율의 한 겹 위다.

### Step 1: `Copy` 선언을 바꾼다 (사용자가 편집)

**지울 것** — `input.zig`의 `Copy` 주석 마지막 문단과 선언 줄.

```zig
/// **CN-M1이 이 타입을 `union(enum)`으로 바꾼다**(design 결정 6). 검색
/// 프롬프트에 친 글자를 실어 나를 payload가 필요하기 때문이고, payload가 없는
/// 지금은 바꾸지 않는다.
pub const Copy = enum {
```

**넣을 것**

```zig
/// **CN-M1이 이것을 `union(enum)`으로 바꿨다**(design 결정 6). 검색 프롬프트에
/// 친 글자를 실어 나를 payload가 필요하기 때문이다. **전환 자체는 아무 동작도
/// 안 바꿨다** — 그때 variant를 함께 더하지 않은 것에 뜻이 있다. 형태 전환과
/// 기능 추가를 한 Step에 두면 컴파일 에러 목록에 둘이 섞여 갈리지 않는다.
///
/// **union에는 `==`가 없다.** 이 타입을 비교하는 자리는
/// `input_test.zig`의 `expectCopy` 하나이고 `std.meta.eql`을 쓴다.
pub const Copy = union(enum) {
```

**나머지는 한 글자도 안 바꾼다.** payload 없는 variant는 `union(enum)` 안에서
그대로 `enter,` 형태로 쓰이고, `.{ .copy = .left }`도 `@tagName(cmd)`도
`switch (cmd)`도 전부 그대로 동작한다.

### Step 2: 컴파일러가 무엇을 요구하는지 본다 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** `input_test.zig`의 `cmd == want`에서 union 비교가 안 된다는 에러
**하나**. 그 밖의 자리는 전부 조용해야 한다.

**다른 자리가 함께 깨지면 그것부터 읽는다.** union 전환이 `main.zig`나
`input.zig` 본문을 건드린다면 그것은 이 plan이 못 본 의존이므로, 고치기 전에
무엇이었는지 적어 둔다.

### Step 3: `expectCopy`를 고친다 (사용자가 편집)

**지울 것** — `input_test.zig:61-62`.

```zig
        .copy => |cmd| {
            if (cmd == want) return;
```

**넣을 것**

```zig
        .copy => |cmd| {
            // **union에는 `==`가 없다**(CN-M1 Task 1). `std.meta.eql`이 태그를
            // 먼저 보고 payload를 그다음에 본다 — `.find_char`가 생기면 글자까지
            // 비교하게 되고, 그것이 우리가 원하는 것이다.
            if (std.meta.eql(cmd, want)) return;
```

### Step 4: 다시 돌린다 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 빌드가 조용히 끝나고, 검사가 **CN-M0까지와 글자 하나 다르지 않은
출력**으로 `PASS`. 새 줄이 생기면 안 된다 — 이 Task는 동작을 안 바꿨다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Turn the copy command into a tagged union"
```

---

## Task 2: 프롬프트가 글자를 받는다 (아직 안 보인다)

**Files:**
- Modify: `terminal/src/input.zig` (`Mode`, `Copy`, copy 표, 새 find 분기)
- Modify: `terminal/src/vt.zig` (needle 버퍼와 네 함수, `copyExit`)
- Modify: `terminal/src/main.zig` (배선과 `dumpFind`)
- Modify: `terminal/src/input_test.zig`, `terminal/src/vt_test.zig` (검사)

이 Task가 끝나면 게스트에서 `/abc`를 쳐도 **화면에는 아무 일도 안 일어나지만**
시리얼 로그에 `terminal: find> type needle=abc len=3`이 찍힌다. 보이게 만드는
것은 Task 3이다.

**둘을 나눈 이유:** 입력 경로와 렌더 경로가 서로 다른 이유로 틀린다. 한꺼번에
넣고 화면에 아무것도 안 나오면 "글자를 못 받은 것"과 "받았는데 못 그린 것"을
가르는 데 부팅 한 바퀴가 든다. **로그가 먼저 서면 그 갈림이 공짜다.**

### Step 1: `input.zig`에 `.find` 모드와 variant 다섯을 더한다 (사용자가 편집)

**넣을 것 ①** — `Copy` union에서 `paste,` 다음, 닫는 `};` 앞이다.

```zig

    // ── CN-M1: 검색 프롬프트 ────────────────────────────────────────────
    //
    // **다섯이 한 덩어리다.** `find_open`이 프롬프트를 열고, `find_char`가
    // 글자를 실어 나르고, `find_erase`가 지우고, `find_cancel`이 닫고,
    // `find_submit`이 확정한다. `find_char`만 payload를 갖는데, **그것 하나
    // 때문에 이 타입이 union이 됐다**(design 결정 6).

    /// `/` — 프롬프트를 연다. **빈 검색어로 시작한다.**
    find_open,
    /// 프롬프트에 글자 하나. 버퍼가 차면 `vt.zig`가 조용히 버린다.
    find_char: u8,
    /// Backspace. **빈 프롬프트에서는 아무 일도 안 한다**(CN-M1 plan 결정 2).
    find_erase,
    /// 프롬프트 중의 Esc. **프롬프트만 닫고 copy mode는 유지한다**
    /// (design 결정 9). Esc를 두 번 눌러야 모드까지 나간다.
    find_cancel,
    /// 프롬프트 중의 Enter. 검색을 돌리고 첫 매치로 커서를 옮긴다.
    find_submit,
```

**편집 ②** — `Mode` 선언. 지금은 **한 줄**이라 늘려야 한다.

**지울 것**

```zig
    pub const Mode = enum { normal, copy };
```

**넣을 것**

```zig
    pub const Mode = enum {
        normal,
        copy,
        /// 검색 프롬프트가 열려 있다. **copy mode 안의 모드다** — Esc로 여기서
        /// 빠지면 `.copy`로 돌아가지 `.normal`이 아니다(design 결정 9).
        ///
        /// 이 상태에서만 **키가 명령이 아니라 글자가 된다.** copy 표가 `n`을
        /// 명령으로 보는 것과, 프롬프트가 `n`을 글자로 보는 것이 갈리는 자리가
        /// 여기이고, 그 갈림은 `handleKey`에서 **어느 분기가 먼저 오는가**로
        /// 정해진다.
        find,
    };
```

**넣을 것 ③** — copy 분기 안, `c.KEY_B` 다음 줄이다.

```zig
                // 검색 프롬프트를 연다(CN-M1). **Shift+/ 는 `?`이고 우리는
                // 아래로 찾지 않으므로**(design 결정 4) 삼킨다 — 여기서
                // `?`도 받으면 방향 상태가 하나 늘고 `n`/`N`의 뜻이 그것에
                // 따라 뒤집힌다.
                c.KEY_SLASH => {
                    if (self.shifted()) return nothing;
                    self.mode = .find;
                    return .{ .copy = .find_open };
                },
```

**넣을 것 ④** — copy 분기(`if (self.mode == .copy) {`) **바로 앞**에 새 분기를
통째로 넣는다.

```zig
        // 1.4번 단계 — 검색 프롬프트(design 결정 7·9). **copy 표보다 앞이다.**
        //
        // 이 분기가 copy 표 앞에 있어야 하는 이유가 이 milestone의 핵심이다.
        // 프롬프트가 열려 있을 때 `n`은 **명령이 아니라 글자**여야 하는데, copy
        // 표가 먼저 보면 `n`을 `.find_next`로 삼켜서 "needle에 n을 못 친다"가
        // 된다. 순서 하나가 그 사고를 막는다.
        //
        // **Ctrl 조합은 여기서 평범한 글자가 된다.** 프롬프트에 제어 문자를
        // 넣을 이유가 없고, chord()까지 흘려보내면 Cmd+V가 프롬프트 안에서
        // 붙여넣기로 동작하게 된다 — 그것은 검색 기록과 같은 종류의 기능이라
        // design이 비워 둔 자리다.
        if (self.mode == .find) {
            switch (code) {
                c.KEY_ESC => {
                    self.mode = .copy;
                    return .{ .copy = .find_cancel };
                },
                c.KEY_ENTER => {
                    self.mode = .copy;
                    return .{ .copy = .find_submit };
                },
                c.KEY_BACKSPACE => return .{ .copy = .find_erase },
                else => {
                    if (code >= keymap.len) return nothing;
                    const ch = keymap[code][if (self.shifted()) 1 else 0];
                    if (ch == 0) return nothing;
                    return .{ .copy = .{ .find_char = ch } };
                },
            }
        }

```

### Step 2: `vt.zig`에 needle 버퍼와 네 함수를 넣는다 (사용자가 편집)

**넣을 것 ①** — 필드. `clip: ?[:0]const u8 = null,` 다음 줄, `pub fn init` 앞이다.

```zig

    /// 검색 프롬프트가 열려 있는가.
    ///
    /// **`input.State.mode`에도 같은 사실이 있다.** 중복처럼 보이지만 각자 다른
    /// 일을 한다(CN-M1 plan 결정 1) — `input.zig`는 키를 글자로 돌리기 위해
    /// 알아야 하고, 여기는 **그려야 하기 때문에** 알아야 한다. 그리고
    /// `input.zig`는 `vt.zig`를 import하지 않으므로(IP design 결정 6) 물어볼
    /// 길이 아예 없다. copy mode 자체가 이미 같은 모양이다
    /// (`State.mode`와 `copy_cursor`).
    ///
    /// **이 값을 만지는 것은 네 함수뿐이다** — findOpen · findCancel ·
    /// findSubmit · copyExit.
    find_open: bool = false,

    /// 검색어(design 결정 8). **고정 128바이트이고 넘치면 더 받지 않는다.**
    ///
    /// 스크롤백이 1000줄인 시스템에서 128자짜리 검색어를 칠 일이 없고, 동적
    /// 할당은 "언제 해제하는가"를 copyExit·재검색·모드 재진입 **세 자리**에
    /// 나눠 놓는다. `clip`이 할당을 쓰는 것과 갈리는 자리인데, 그쪽은 길이를
    /// 우리가 못 정하고(선택한 만큼이다) 이쪽은 정할 수 있다.
    find_buf: [128]u8 = undefined,
    find_len: usize = 0,
```

**넣을 것 ②** — 함수 넷. `copyExit` 바로 뒤, `copyTakePruned` 앞이다.

```zig

    /// `/`. 프롬프트를 연다. **언제나 빈 검색어로 시작한다** — 지난 검색어를
    /// 되부르는 것은 design이 비워 둔 자리다.
    ///
    /// copy mode가 아니면 아무 일도 안 한다. `input.zig`의 표가 이미 그것을
    /// 막지만, **두 곳이 같은 사실을 지키는 것이 이 파일의 규율이다**
    /// (`copyMove`도 `copySelect`도 같은 첫 줄을 갖는다).
    pub fn findOpen(self: *Screen) void {
        if (self.copy_cursor == null) return;
        self.find_open = true;
        self.find_len = 0;
    }

    /// 프롬프트에 글자 하나. **버퍼가 차면 조용히 버린다.**
    ///
    /// 버리는 것을 로그로 알리지 않는 이유는 128자에 닿는 상황이 실전에
    /// 없기 때문이다. 닿았다면 그것은 사람이 친 것이 아니라 키가 붙어 있는
    /// 것이고, 그 증상은 화면에서 바로 보인다.
    pub fn findChar(self: *Screen, ch: u8) void {
        if (!self.find_open) return;
        if (self.find_len >= self.find_buf.len) return;
        self.find_buf[self.find_len] = ch;
        self.find_len += 1;
    }

    /// Backspace. **빈 프롬프트에서는 아무 일도 안 한다**(CN-M1 plan 결정 2).
    ///
    /// vim은 여기서 프롬프트를 닫지만 우리는 안 닫는다. 닫으면 Esc와 뜻이
    /// 겹치고, 지우려고 연타하던 사람이 마지막 한 번에 프롬프트를 잃는다.
    pub fn findErase(self: *Screen) void {
        if (!self.find_open) return;
        if (self.find_len == 0) return;
        self.find_len -= 1;
    }

    /// 프롬프트만 닫는다. **copy mode는 유지한다**(design 결정 9).
    pub fn findCancel(self: *Screen) void {
        self.find_open = false;
        self.find_len = 0;
    }

    /// 지금 프롬프트에 무엇이 쳐져 있는가. 닫혀 있으면 null이다.
    ///
    /// **`main.zig`가 `find_buf`를 직접 읽지 않게 하려고 함수로 낸다** —
    /// `clipboard`·`copyCursor`·`scrollbar`와 같은 규율이다(design 결정 8).
    pub fn findNeedle(self: *const Screen) ?[]const u8 {
        if (!self.find_open) return null;
        return self.find_buf[0..self.find_len];
    }
```

**넣을 것 ③** — `copyExit`에 한 줄. `self.copy_anchor_y = null;` 다음이다.

```zig
        // 프롬프트도 함께 닫는다(design 결정 10). 안 닫으면 모드를 나갔다
        // 다시 들어왔을 때 지난 검색어가 화면에 남는다.
        self.findCancel();
```

### Step 3: `main.zig`가 배선하고 로그를 찍는다 (사용자가 편집)

**넣을 것 ①** — `dumpFind`. `dumpClip` 앞이다.

```zig
/// 검색 프롬프트의 상태를 찍는다.
///
/// **게이트가 프롬프트를 볼 수 있는 유일한 창구다.** 프롬프트는 오버레이라
/// `cells()`의 결과에 안 섞이고(design 결정 7), 그래서 `terminal: screen>` 줄에
/// 절대 안 나타난다. 그 격리가 다섯 체인의 화면 판정을 지키는 대신 관측 수단을
/// 하나 없앤다 — 이 줄이 그 자리를 메운다.
///
/// **`screen>`의 형식을 안 바꾸는 것이 이 설계 전체의 이유다.** 프롬프트를 셀에
/// 섞었다면 로그 한 줄로 끝났겠지만, 그 줄을 보던 체인 다섯이 전부 흔들린다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpFind(screen: *vt.Screen, what: []const u8) void {
    if (screen.findNeedle()) |n| {
        std.debug.print("terminal: find> {s} needle={s} len={d}\n", .{ what, n, n.len });
    } else {
        // 프롬프트가 닫힌 뒤다. cancel과 submit이 여기로 온다.
        std.debug.print("terminal: find> {s}\n", .{what});
    }
}
```

**넣을 것 ②** — copy 배선 switch에서 `.paste` 다음 줄이다.

```zig
                    // 검색 프롬프트(CN-M1). **넷 다 화면 상태를 바꾸지 않는다** —
                    // needle 버퍼만 만지고, 그리는 것은 아래 render가 한다.
                    .find_open => {
                        screen.findOpen();
                        dumpFind(screen, "open");
                    },
                    .find_char => |ch| {
                        screen.findChar(ch);
                        dumpFind(screen, "type");
                    },
                    .find_erase => {
                        screen.findErase();
                        dumpFind(screen, "erase");
                    },
                    .find_cancel => {
                        screen.findCancel();
                        dumpFind(screen, "cancel");
                    },
                    // 확정은 Task 4가 채운다. **지금은 프롬프트만 닫는다** —
                    // 여기를 비워 두면 Enter가 프롬프트를 영영 못 닫아서 그
                    // 뒤의 키가 전부 글자가 된다.
                    .find_submit => {
                        screen.findCancel();
                        dumpFind(screen, "submit (not wired yet)");
                    },
```

### Step 4: 검사를 더한다 (사용자가 편집)

**넣을 것 ①** — `input_test.zig`, CN-M0 검사 16의 끝(`try expectCopy(&cm, K.KEY_ESC, .exit);`)과
`copy mode OK` 사이다.

```zig

    // ── CN-M1: 검색 프롬프트 ────────────────────────────────────────────
    //
    // 검사 17. `/`가 프롬프트를 열고, **그 안에서 키가 글자가 된다.**
    // `n`으로 보는 것이 핵심이다 — 그것은 Task 5에서 copy 표의 명령이 되므로,
    // 표보다 프롬프트가 먼저 보지 않으면 needle에 `n`을 못 치게 된다.
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'n' });
    try expectCopy(&cm, K.KEY_E, .{ .find_char = 'e' });
    try expectCopy(&cm, K.KEY_W, .{ .find_char = 'w' });

    // 검사 18. **Shift가 대문자를 만든다.** 프롬프트는 명령 표가 아니라
    // keymap을 그대로 쓰므로 대소문자가 갈린다 — `w`/`b`가 Shift를 안 가르는
    // 것과 정확히 반대다.
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_A, .{ .find_char = 'A' });
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 19. Backspace와 Enter와 Esc.
    try expectCopy(&cm, K.KEY_BACKSPACE, .find_erase);
    try expectCopy(&cm, K.KEY_ENTER, .find_submit);
    // Enter가 프롬프트를 닫았으므로 여기서 `n`은 다시 **명령 표의 것**이다.
    // Task 5 전까지 `n`은 모르는 키라 삼켜진다.
    try expect(&cm, K.KEY_N, 1, "");

    // 검사 20. **Esc는 프롬프트만 닫는다**(design 결정 9). 이 검사가 없으면
    // "Esc 한 번에 모드까지 나간다"도 통과하고, 그러면 오타를 고치려던 사람이
    // 스크롤 위치와 선택을 잃는다.
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_X, .{ .find_char = 'x' });
    try expectCopy(&cm, K.KEY_ESC, .find_cancel);
    if (cm.mode != .copy) {
        std.debug.print("FAIL: Esc in the find prompt left copy mode\n", .{});
        return error.FindCancelLeftMode;
    }
    // **두 번째 Esc가 모드를 닫는다.**
    try expectCopy(&cm, K.KEY_ESC, .exit);

    // 검사 21. **모드 밖의 `/`는 평범한 글자다.** CN-M0의 검사 14와 같은
    // 대조군이고, 이것이 없으면 셸에 `/`를 못 치게 된 것을 아무도 모른다.
    try expect(&cm, K.KEY_SLASH, 1, "/");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expect(&cm, K.KEY_SLASH, 1, "?");
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
```

**넣을 것 ②** — `vt_test.zig`, CN-M0 검사 16의 끝(`선택이 w를 따라 넓어진다 OK`)과
`PASS` 사이다.

```zig

    // ── CN-M1: 검색 프롬프트 ────────────────────────────────────────────
    //
    // 화면을 따로 만든다(CM-M1 이래의 규율). 여기서는 버퍼만 보므로 작아도 된다.
    const fm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer fm.deinit();
    fm.feed("hello\r\n");
    _ = try fm.cells(&buf);

    // 검사 17. **copy mode가 아니면 프롬프트가 안 열린다.**
    fm.findOpen();
    if (fm.findNeedle() != null) {
        std.debug.print("FAIL: the find prompt opened outside copy mode\n", .{});
        return error.FindOpenedOutsideCopy;
    }

    // 검사 18. 열고, 치고, 지운다.
    fm.copyEnter();
    fm.findOpen();
    fm.findChar('a');
    fm.findChar('b');
    fm.findChar('c');
    var needle = fm.findNeedle() orelse return error.NoFindPrompt;
    if (!std.mem.eql(u8, needle, "abc")) {
        std.debug.print("FAIL: the prompt holds '{s}' (expected 'abc')\n", .{needle});
        return error.FindNeedleWrong;
    }
    fm.findErase();
    needle = fm.findNeedle().?;
    if (!std.mem.eql(u8, needle, "ab")) {
        std.debug.print("FAIL: backspace left '{s}' (expected 'ab')\n", .{needle});
        return error.FindEraseWrong;
    }
    std.debug.print("vt_test: 프롬프트가 글자를 받고 지운다 OK ('{s}')\n", .{needle});

    // 검사 19. **빈 프롬프트에서 Backspace는 프롬프트를 안 닫는다**
    // (plan 결정 2). 이 검사가 없으면 "비면 닫는다"도 통과하고, 그러면
    // 지우려고 연타하던 사람이 마지막 한 번에 프롬프트를 잃는다.
    fm.findErase();
    fm.findErase();
    fm.findErase();
    needle = fm.findNeedle() orelse {
        std.debug.print("FAIL: backspace closed an empty prompt\n", .{});
        return error.FindEraseClosedPrompt;
    };
    if (needle.len != 0) {
        std.debug.print("FAIL: the prompt should be empty, holds '{s}'\n", .{needle});
        return error.FindEraseWrong;
    }
    std.debug.print("vt_test: 빈 프롬프트의 Backspace가 안 닫는다 OK\n", .{});

    // 검사 20. **버퍼가 넘쳐도 무너지지 않는다**(design 결정 8). 128자를 채우고
    // 스무 자를 더 친다.
    var fill: usize = 0;
    while (fill < 148) : (fill += 1) fm.findChar('z');
    needle = fm.findNeedle().?;
    if (needle.len != 128) {
        std.debug.print("FAIL: the needle grew to {d} (expected to stop at 128)\n", .{needle.len});
        return error.FindNeedleOverflow;
    }
    std.debug.print("vt_test: 검색어가 128자에서 멈춘다 OK\n", .{});

    // 검사 21. **copyExit이 프롬프트도 닫는다**(design 결정 10). 안 닫으면
    // 모드를 다시 열었을 때 지난 검색어가 화면에 남는다.
    fm.copyExit();
    if (fm.findNeedle() != null) {
        std.debug.print("FAIL: copyExit left the find prompt open\n", .{});
        return error.FindSurvivedCopyExit;
    }
    std.debug.print("vt_test: copyExit이 프롬프트를 닫는다 OK\n", .{});
```

### Step 5: 빌드와 검사 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**둘 다 돌린다** — `Copy`를 건드렸으므로 HANDOFF 실측 1이 그대로 적용된다.

**기대:** 새 `vt_test` 줄 넷과 함께 `PASS`.

### Step 6: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/vt.zig terminal/src/main.zig \
        terminal/src/input_test.zig terminal/src/vt_test.zig
git commit -m "Take search text in a copy mode prompt"
```

---

## Task 3: 프롬프트가 화면에 보인다

**Files:**
- Modify: `terminal/src/main.zig` (`render`·`dumpStyles`·`poll` 루프)

**이 Task는 검사가 없다.** `vt_test`도 `input_test`도 프레임버퍼를 안 갖기
때문이고, 이 저장소에서 픽셀을 보는 것은 게이트뿐이다. **Task 6이 게스트에서
본다** — 그때까지는 "컴파일이 되고 기존 게이트가 안 깨진다"가 우리가 아는
전부다.

### Step 1: `render`가 프롬프트를 그린다 (사용자가 편집)

**넣을 것 ①** — `drawPrompt`. `render` 앞이다.

```zig
/// 프롬프트 오버레이(design 결정 7). **격자를 다 그린 뒤 마지막 줄만 덮는다.**
///
/// **`render`가 `present()`로 끝나므로 반드시 그 안에서, present 앞에 그려야
/// 한다.** 밖에서 그리면 다음 프레임까지 화면에 안 나온다.
///
/// 줄 전체를 먼저 배경색으로 지운다. 안 지우면 검색어가 짧아졌을 때 지난
/// 프레임의 꼬리가 오른쪽에 남는다 — Backspace를 눌렀는데 글자가 안 지워지는
/// 것처럼 보인다.
///
/// **반전하지 않는다**(CN-M1 plan 결정 6). 선택도 copy 커서도 "색 둘을
/// 맞바꾼다"로 나타나므로, 프롬프트까지 반전하면 화면 맨 아래의 흰 띠가
/// 선택인지 프롬프트인지 갈리지 않는다. 앞의 `/` 한 글자가 그 표시다.
fn drawPrompt(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
) !void {
    if (rows == 0) return;
    const y = GRID_Y + @as(u32, rows - 1) * ROW_HEIGHT;

    var col: u32 = 0;
    while (col < cols) : (col += 1) {
        drawCellBackground(fb, GRID_X + col * CELL_W, y, bg);
    }

    col = 0;
    for (text) |ch| {
        if (col >= cols) break;
        const glyph = try cache.find(ch);
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);
        col += 1;
    }
}
```

**넣을 것 ②** — `render`의 서명과 마지막 부분.

**지울 것**

```zig
fn render(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph) !void {
```

**넣을 것**

```zig
fn render(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
) !void {
```

**지울 것** — `render`의 마지막 두 줄.

```zig
    try fb.present();
}
```

**넣을 것**

```zig
    // 격자를 다 그린 **뒤**, present **앞**이다(확정 사실 8).
    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }

    try fb.present();
}

/// 오버레이 한 줄에 필요한 것 전부.
///
/// 인자를 일곱 개 늘어놓지 않고 묶는 이유는 **호출부가 하나뿐**이기 때문이다.
/// 늘어놓으면 `rows`와 `cols`, `fg`와 `bg`를 뒤바꿔 넣어도 컴파일이 통과한다.
const Prompt = struct {
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
};
```

### Step 2: `dumpStyles`가 덮인 줄을 건너뛴다 (사용자가 편집)

**지울 것** — `dumpStyles`의 서명과 루프 첫머리.

```zig
fn dumpStyles(
    fb: drm.Framebuffer,
    cells: []const vt.CellGlyph,
    default_fg: u32,
    default_bg: u32,
) void {
    var shown: usize = 0;
    var skipped: usize = 0;
    for (cells) |cell| {
        if (cell.fg == default_fg and cell.bg == default_bg) continue;
```

**넣을 것**

```zig
fn dumpStyles(
    fb: drm.Framebuffer,
    cells: []const vt.CellGlyph,
    default_fg: u32,
    default_bg: u32,
    /// 프롬프트가 덮은 행. 없으면 null이다(CN-M1 plan 결정 4).
    overlaid_row: ?u16,
) void {
    var shown: usize = 0;
    var skipped: usize = 0;
    var hidden: usize = 0;
    for (cells) |cell| {
        // **덮인 줄은 아예 건너뛴다.** 이 함수가 두 줄을 찍는 것에 뜻이 있다 —
        // `style>`는 파서가 본 색이고 `pixel>`은 프레임버퍼에서 되읽은 값이며,
        // 둘이 어긋나면 렌더러가 틀렸다는 뜻이다(TR design 결정 7). 우리가 덮은
        // 줄에서는 그 전제가 깨진다: pixel>이 셀이 아니라 프롬프트를 말한다.
        //
        // 지금 이 줄을 보는 체인은 없지만(pixel>을 쓰는 것은 render 체인
        // 하나뿐이고 그 체인은 copy mode에 안 들어간다) **게이트가 못 보는
        // 부채를 새로 만들지 않는다.**
        if (overlaid_row) |r| {
            if (cell.row == r) {
                hidden += 1;
                continue;
            }
        }
        if (cell.fg == default_fg and cell.bg == default_bg) continue;
```

**그리고** 함수 끝의 `skipped` 보고 뒤에 한 줄을 더한다.

```zig
    // 조용히 건너뛰면 "그 줄에 색이 없다"와 "덮여서 안 봤다"를 가를 수 없다.
    if (hidden > 0) {
        std.debug.print("terminal: style> {d} cell(s) hidden by the find prompt\n", .{hidden});
    }
```

### Step 3: `poll` 루프가 프롬프트를 조립해 넘긴다 (사용자가 편집)

**지울 것** — 렌더 부분의 두 줄.

```zig
        const cells = try screen.cells(cell_buf);
        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells);
```

**넣을 것**

```zig
        const cells = try screen.cells(cell_buf);

        // 프롬프트 문자열을 여기서 만든다. **`vt.zig`는 앞의 `/`를 모른다** —
        // 그것은 표현이지 상태가 아니고, TR-M0이 색을 vt.zig에서 확정해 넘긴
        // 것과 반대 방향의 같은 경계다(모양은 main.zig가 정한다).
        //
        // 버퍼가 needle보다 한 칸 크다. `/` 한 글자 때문이다.
        var prompt_buf: [129]u8 = undefined;
        const prompt: ?Prompt = if (screen.findNeedle()) |n| blk: {
            prompt_buf[0] = '/';
            @memcpy(prompt_buf[1 .. 1 + n.len], n);
            break :blk .{
                .text = prompt_buf[0 .. 1 + n.len],
                .rows = rows,
                .cols = cols,
                // **`cells()` 뒤에 읽어야 한다** — `state.colors`는 update()가
                // 채운다(vt.zig의 defaultFg 주석).
                .fg = screen.defaultFg(),
                .bg = screen.defaultBg(),
            };
        } else null;

        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells, prompt);
```

**그리고** `dumpStyles` 호출에 인자 하나를 더한다.

**지울 것**

```zig
        dumpStyles(fb, cells, screen.defaultFg(), screen.defaultBg());
```

**넣을 것**

```zig
        dumpStyles(
            fb,
            cells,
            screen.defaultFg(),
            screen.defaultBg(),
            if (prompt != null) rows - 1 else null,
        );
```

> **주의:** `dumpStyles` 호출 줄의 실제 모양은 이 plan을 쓴 시점의 것이다.
> 인자가 다르면 **지우지 말고 인자 하나만 끝에 더한다.**

### Step 4: 빌드하고 `copy` 체인이 안 깨졌는지 본다 (Claude가 실행, 약 4분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

이어서 게스트에서 프롬프트가 실제로 그려지는지 본다. **`copy` 체인을 그대로
돌리되, 마지막에 `/` 를 쳐 보는 것은 Task 6이 한다** — 지금은 **기존 검사 열넷이
안 깨지는 것**만 확인한다. 오버레이가 격자를 잘못 덮으면 `screen>` 판정이
흔들리므로, 그것이 이 Step의 진짜 목적이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash copy/check.sh' > /tmp/cn-m1-t3.out 2>&1
```

**`run_in_background`로 돌린다.**

**기대:** `CM-M2 check PASS`. **`screen>` 판정이 하나라도 깨지면 오버레이가
`cells()`에 영향을 준 것이고, 그것은 design 결정 7을 어긴 것이다** — 코드를
되돌아본다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Draw the search prompt over the last row"
```

---

## Task 4: Enter가 검색을 돌리고 커서를 옮긴다

**Files:**
- Modify: `terminal/src/vt.zig` (`find` 필드, `findSubmit`·`findStep`, `feed`,
  `copyExit`, `deinit`)
- Modify: `terminal/src/main.zig` (`.find_submit` 배선과 시간 측정)
- Modify: `terminal/src/vt_test.zig` (검사)

### Step 1: `vt.zig`에 검색 상태를 넣는다 (사용자가 편집)

**넣을 것 ①** — 필드. `find_len: usize = 0,` 다음이다.

```zig

    /// 확정된 검색. `findSubmit`이 만들고 `copyExit`이 해제한다(design 결정 10).
    ///
    /// **`ScreenSearch`는 `screen: *ghostty_vt.Screen`을 들고 있다**
    /// (`search/screen.zig:42`). 대체 화면(vim 등)으로 갈아타면
    /// `term.screens.active`가 달라져 그 포인터가 낡는다 — `feed`가 포인터
    /// 하나를 비교해 잡는다. **`pointFromPin`을 부르는 앵커 감시와 달리 비용이
    /// 없다.**
    ///
    /// 이것을 안 해제하면 모드를 나갔다 다시 들어왔을 때 지난 매치 목록이 살아
    /// 있고, 그 pin들은 그 사이 도착한 출력 때문에 이미 엉뚱한 자리를 가리킬 수
    /// 있다. **증상이 "안 된다"가 아니라 "조용히 다른 자리로 간다"이다** —
    /// CM-M1이 앵커에 대해 배운 것과 같은 병이다.
    find: ?ghostty_vt.search.Screen = null,
```

**넣을 것 ②** — `findSubmit`과 `findStep`. `findNeedle` 뒤다.

```zig

    /// 검색 결과. `main.zig`가 로그에 쓴다.
    ///
    /// `matches`와 `moved`를 **따로** 주는 것에 뜻이 있다. 매치가 있는데 못
    /// 옮긴 경우(전부 커서 아래에 있었다)와 매치가 아예 없는 경우는 사람에게
    /// 다른 뜻이고, 하나로 묶으면 게이트가 그 둘을 못 가른다.
    pub const FindResult = struct { matches: usize, moved: bool };

    /// Enter. **검색을 돌리고 첫 매치로 커서를 옮긴다.**
    ///
    /// `searchAll()`은 블로킹이다(design 결정 5). Enter 한 번에 한 번뿐이므로
    /// 그것으로 충분하고, **걸린 시간은 `main.zig`가 재서 `find>` 줄에 찍는다**
    /// (CN-M1 plan 결정 5).
    ///
    /// 빈 검색어로 Enter를 누르면 프롬프트만 닫는다. 지난 검색은 그대로 살아
    /// 있으므로 `n`이 계속 동작한다 — vim과 다른 자리이지만(vim은 지난 검색어를
    /// 다시 쓴다) 검색 기록이 없는 우리에게는 이것이 가장 덜 놀라운 동작이다.
    pub fn findSubmit(self: *Screen) !FindResult {
        const none: FindResult = .{ .matches = 0, .moved = false };
        if (!self.find_open) return none;

        const len = self.find_len;
        self.find_open = false;
        if (len == 0) return none;

        // **옛 검색을 먼저 해제한다.** 안 하면 `/`를 두 번 누를 때마다 매치
        // 목록과 tracked pin이 그대로 샌다.
        if (self.find) |*old| old.deinit();
        self.find = null;

        // **지역 변수에 만들고 나서 옮겨 담는다.** `self.find`가 optional이라
        // `try .init(...)`이 그 껍질을 통과할지가 Zig 버전에 딸린 문제이고,
        // 여기서 그것에 기대고 싶지 않다.
        //
        // **값으로 옮기는 것이 안전하다는 근거는 라이브러리 자신에 있다** —
        // `resetIfDimensionsChanged`가 `self.deinit(); self.* = new;`로 같은
        // 일을 한다(`search/screen.zig:223`). tracked pin은 PageList의 풀을
        // 가리키지 ScreenSearch 자신을 가리키지 않는다.
        const s = self.term.screens.active;
        var fresh: ghostty_vt.search.Screen = try .init(
            self.alloc,
            s,
            self.find_buf[0..len],
        );
        errdefer fresh.deinit();
        try fresh.searchAll();
        self.find = fresh;

        return .{
            .matches = self.find.?.matchesLen(),
            // **첫 이동만 "커서보다 위"를 요구한다**(CN-M1 plan 결정 3).
            .moved = try self.findStep(.next, true),
        };
    }

    /// `n`. 목록의 다음(과거 방향) 매치로.
    ///
    /// **목록 끝에서 감긴다.** 라이브러리의 `Select.next` 주석은
    /// "non-wrapping"이라고 하는데 `selectNext`의 코드는 감는다
    /// (`search/screen.zig:851`). **주석이 아니라 코드가 맞다.** 감기는 것을
    /// 감추지 않는 이유는, 막으려면 "끝에 닿았다"는 상태가 하나 늘고 그것을
    /// 사람에게 알릴 자리가 또 필요하기 때문이다.
    pub fn findNext(self: *Screen) !bool {
        return self.findStep(.next, false);
    }

    /// `N`. 목록의 이전(미래 방향) 매치로.
    pub fn findPrev(self: *Screen) !bool {
        return self.findStep(.prev, false);
    }

    /// `/`의 첫 이동과 `n`/`N`이 함께 쓰는 한 자리.
    ///
    /// `above_only`가 참이면 **커서보다 위에 있는 매치를 만날 때까지 넘긴다.**
    /// design 결정 4가 "`/`는 위로 찾는다"로 정했는데 라이브러리의 `select`는
    /// 커서를 모르기 때문이다 — 커서를 `k`로 올려 둔 자리에서 `/`를 누르면 그
    /// 필터가 없을 때 커서가 **아래로 뛴다.**
    ///
    /// **넘기는 횟수를 `matchesLen()`으로 막는 것이 필수다.** 목록이 감기므로
    /// 상한이 없으면 "위에 아무것도 없는" 검색어에서 영원히 돈다.
    ///
    /// 마지막 네 줄이 `copyMove`·`copyMoveWord`와 글자 그대로 같다 —
    /// **모든 이동 수단이 `copyApply`라는 문 하나를 통과한다**(design 결정 11).
    fn findStep(
        self: *Screen,
        dir: ghostty_vt.search.Screen.Select,
        above_only: bool,
    ) !bool {
        if (self.find == null) return false;
        const f = &self.find.?;
        const s = self.term.screens.active;
        const total = f.matchesLen();
        if (total == 0) return false;

        const from = self.copyPin() orelse return false;
        const from_pt = s.pages.pointFromPin(.screen, from) orelse return false;

        var tried: usize = 0;
        while (tried < total) : (tried += 1) {
            if (!try f.select(dir)) return false;
            const hl = f.selectedMatch() orelse return false;
            const pin = hl.startPin();

            if (above_only) {
                const pt = s.pages.pointFromPin(.screen, pin) orelse continue;
                if (pt.screen.y >= from_pt.screen.y) continue;
            }

            self.copyPlace(pin);

            if (self.copy_kind == null) return true;
            const sel = s.selection orelse return true;
            const cursor = self.copyPin() orelse return true;
            try self.copyApply(sel.start(), cursor);
            return true;
        }
        return false;
    }
```

**넣을 것 ③** — `copyExit`에서 `self.findCancel();` 다음 줄이다.

```zig
        // 매치 목록도 함께 버린다(design 결정 10). tracked pin을 들고 있으므로
        // **screen이 살아 있는 동안** 해제해야 한다.
        if (self.find) |*f| f.deinit();
        self.find = null;
```

**넣을 것 ④** — `deinit`에서 `self.state.deinit(alloc);` **앞**이다.

```zig
        // **term보다 먼저다.** ScreenSearch가 든 tracked pin은 PageList의
        // 풀에서 왔으므로, term을 먼저 버리면 이미 없는 풀을 건드린다.
        if (self.find) |*f| f.deinit();
```

**넣을 것 ⑤** — `feed`에서 `self.stream.nextSlice(bytes);` 다음 줄이다.

```zig
        // 대체 화면으로 갈아탔으면 ScreenSearch가 든 포인터가 낡는다
        // (확정 사실 6). **포인터 비교라 비용이 없다** — 아래 앵커 감시가
        // `pointFromPin`을 부르는 것과 다르다.
        //
        // 앵커 감시는 선택 중일 때만 도는데(copy_anchor_y가 null이면 빠진다)
        // 검색은 선택 없이도 살아 있을 수 있어서 **여기서 따로 본다.**
        if (self.find) |*f| {
            if (f.screen != self.term.screens.active) {
                self.copyExit();
                self.copy_pruned = true;
                return;
            }
        }
```

### Step 2: `main.zig`가 확정을 배선하고 시간을 잰다 (사용자가 편집)

**지울 것** — Task 2가 넣은 임시 배선.

```zig
                    // 확정은 Task 4가 채운다. **지금은 프롬프트만 닫는다** —
                    // 여기를 비워 두면 Enter가 프롬프트를 영영 못 닫아서 그
                    // 뒤의 키가 전부 글자가 된다.
                    .find_submit => {
                        screen.findCancel();
                        dumpFind(screen, "submit (not wired yet)");
                    },
```

**넣을 것**

```zig
                    // **이 milestone에서 유일하게 시간이 걸리는 명령이다.**
                    // searchAll()이 스크롤백 전체를 훑는 동안 화면이 멈춘다
                    // (design 결정 5). 얼마나 멈추는지를 여기서 재서 찍는다 —
                    // 그 값이 "증분으로 바꿔야 하는가"를 나중에 가른다.
                    .find_submit => {
                        const t0 = std.Io.Clock.now(.awake, init.io);
                        const r = try screen.findSubmit();
                        std.debug.print(
                            "terminal: find> submit matches={d} moved={} us={d}\n",
                            .{
                                r.matches,
                                r.moved,
                                @divTrunc(t0.untilNow(init.io, .awake).nanoseconds, 1000),
                            },
                        );
                    },
```

### Step 3: `vt_test.zig`에 검사를 더한다 (사용자가 편집)

**넣을 것** — Task 2가 넣은 검사 21(`copyExit이 프롬프트를 닫는다 OK`) 뒤다.

```zig

    // 검사 22~25. **실제로 찾아서 커서를 옮긴다.**
    //
    // 스크롤백을 가진 화면을 새로 만든다. 20칸 5줄에 60줄을 먹이면 위쪽
    // 55줄이 history로 간다.
    //
    //   L1 … L9  MARK  L11 … L29  MARK  L31 … L60
    //            (10)            (30)
    //
    // **MARK가 둘인 것이 요점이다.** 하나면 `n`이 감기는지 옮기는지 갈리지
    // 않는다.
    const fs = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer fs.deinit();
    var fl: usize = 1;
    while (fl <= 60) : (fl += 1) {
        if (fl == 10 or fl == 30) {
            fs.feed("MARK\r\n");
        } else {
            fs.feed(std.fmt.bufPrint(&line, "L{d}\r\n", .{fl}) catch unreachable);
        }
    }
    _ = try fs.cells(&buf);
    fs.copyEnter();

    // 검사 22. `/MARK` + Enter가 **가장 최근** MARK(30번째 줄)로 간다.
    fs.findOpen();
    for ("MARK") |ch| fs.findChar(ch);
    const hit = try fs.findSubmit();
    if (hit.matches != 2) {
        std.debug.print("FAIL: found {d} match(es) for MARK (expected 2)\n", .{hit.matches});
        return error.FindMatchCountWrong;
    }
    if (!hit.moved) {
        std.debug.print("FAIL: the cursor did not move to a match\n", .{});
        return error.FindDidNotMove;
    }
    // 커서가 선 줄의 글자를 읽어 확인한다. **좌표가 아니라 내용을 본다** —
    // 뷰포트가 어디로 밀렸는지는 화면 크기에 딸린 값이라 바뀌기 쉽다.
    var cur = fs.copyCursor() orelse return error.NoCopyCursor;
    var text = rowText(try fs.cells(&buf), cur.y, &line);
    if (!std.mem.startsWith(u8, text, "MARK")) {
        std.debug.print("FAIL: / landed on '{s}' (expected a MARK row)\n", .{text});
        return error.FindLandedWrong;
    }
    std.debug.print("vt_test: /가 매치로 커서를 옮긴다 OK (matches={d})\n", .{hit.matches});

    // 검사 23. **프롬프트가 닫혔다.** Enter가 안 닫으면 그 뒤의 키가 전부
    // 글자가 되어 copy mode가 먹통이 된다.
    if (fs.findNeedle() != null) {
        std.debug.print("FAIL: Enter left the find prompt open\n", .{});
        return error.FindSubmitLeftPromptOpen;
    }

    // 검사 24. `n`이 **더 위의** MARK(10번째 줄)로 간다.
    const prev_y = fs.scrollbar().offset + cur.y;
    if (!try fs.findNext()) {
        std.debug.print("FAIL: n did not move\n", .{});
        return error.FindNextDidNotMove;
    }
    cur = fs.copyCursor().?;
    text = rowText(try fs.cells(&buf), cur.y, &line);
    if (!std.mem.startsWith(u8, text, "MARK")) {
        std.debug.print("FAIL: n landed on '{s}' (expected a MARK row)\n", .{text});
        return error.FindNextLandedWrong;
    }
    const next_y = fs.scrollbar().offset + cur.y;
    if (next_y >= prev_y) {
        std.debug.print(
            "FAIL: n went down or stayed ({d} -> {d}), expected up\n",
            .{ prev_y, next_y },
        );
        return error.FindNextWrongDirection;
    }
    std.debug.print("vt_test: n이 더 위의 매치로 간다 OK ({d} -> {d})\n", .{ prev_y, next_y });

    // 검사 25. **매치가 없으면 커서가 안 움직인다.**
    //
    // **`before`/`after`라는 이름을 못 쓴다** — 이 파일의 CM-M0 검사가
    // `:327`·`:329`에서 이미 쓰고 있고, Zig는 같은 함수 안의 shadowing을
    // 컴파일 에러로 막는다.
    const miss_from = fs.copyCursor().?;
    fs.findOpen();
    for ("NOSUCHTHING") |ch| fs.findChar(ch);
    const miss = try fs.findSubmit();
    if (miss.matches != 0 or miss.moved) {
        std.debug.print(
            "FAIL: a bogus needle reported matches={d} moved={}\n",
            .{ miss.matches, miss.moved },
        );
        return error.FindFalsePositive;
    }
    const miss_to = fs.copyCursor().?;
    if (miss_to.x != miss_from.x or miss_to.y != miss_from.y) {
        std.debug.print("FAIL: a failed search moved the cursor\n", .{});
        return error.FindMissMovedCursor;
    }
    std.debug.print("vt_test: 매치가 없으면 커서가 안 움직인다 OK\n", .{});
```

> **`line`과 `rowText`는 이 파일에 이미 있다.** `line`은 `pruned` 검사가 쓰는
> 버퍼이고 `rowText`는 파일 맨 위의 헬퍼다. **이름이 다르면 그것부터 확인한다.**

### Step 4: 빌드와 검사 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 셋과 함께 `PASS`.

**여기서 처음으로 라이브러리 검색 API가 실제로 도는 것을 본다.** 실패하면
**API 사용이 틀렸는지**(컴파일 에러·잘못된 인자)와 **우리 로직이 틀렸는지**
(매치 수는 맞는데 자리가 틀림)를 먼저 가른다. `matches != 2`면 전자에 가깝고,
`matches == 2`인데 자리가 틀리면 후자다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/main.zig terminal/src/vt_test.zig
git commit -m "Run the search and move the copy cursor to a match"
```

---

## Task 5: `n`/`N`이 키에 붙는다

**Files:**
- Modify: `terminal/src/input.zig` (`Copy`, copy 표)
- Modify: `terminal/src/input_test.zig` (예고 주석과 검사)
- Modify: `terminal/src/main.zig` (배선)

`findNext`/`findPrev`는 Task 4에서 이미 만들었고 `vt_test`가 밟고 있다. **이
Task는 그것을 키에 잇는 일만 한다.**

### Step 1: `Copy`에 variant 둘 (사용자가 편집)

**넣을 것** — `find_submit,` 다음이다.

```zig
    /// `n` — 목록의 다음(과거 방향) 매치로. **끝에서 감긴다**(CN-M1).
    find_next,
    /// `N` — 목록의 이전(미래 방향) 매치로.
    find_prev,
```

### Step 2: copy 표에 한 줄 (사용자가 편집)

**넣을 것** — `c.KEY_SLASH` 분기 다음이다.

```zig
                // `n`/`N`(CN-M1). **Shift 하나로 방향이 갈린다** — `w`/`b`가
                // Shift를 안 가르는 것과 반대이고, 그것은 vim의 `W`를 안
                // 만들었기 때문이다(design 결정 2). 여기서는 대문자 자체가
                // 뜻을 갖는다.
                //
                // **프롬프트가 열려 있으면 이 줄에 닿지 않는다.** find 분기가
                // copy 표보다 앞이라 `n`이 글자가 된다 — 순서가 그것을 정한다.
                c.KEY_N => return .{
                    .copy = if (self.shifted()) .find_prev else .find_next,
                },
```

### Step 3: `main.zig` 배선 (사용자가 편집)

**넣을 것** — `.find_submit` 분기 다음이다.

```zig
                    // **결과를 버리지 않고 찍는다.** 못 옮긴 것과 옮긴 것은
                    // 사람에게 다른 뜻이고, 아래 dumpCopy의 좌표만으로는
                    // "안 움직였다"와 "같은 자리가 맞다"를 못 가른다.
                    .find_next => std.debug.print(
                        "terminal: find> next moved={}\n",
                        .{try screen.findNext()},
                    ),
                    .find_prev => std.debug.print(
                        "terminal: find> prev moved={}\n",
                        .{try screen.findPrev()},
                    ),
```

### Step 4: `input_test.zig` — 예고를 갚고 검사를 더한다 (사용자가 편집)

**지울 것** — CN-M0이 남긴 예고 주석 두 줄.

```zig
    // **`e`와 `n`은 아직 모르는 키이지만 영영 그렇지는 않다.** `e`는 CN이
    // 일부러 안 만든 단어 이동이고(design 결정 2), `n`은 CN-M1의 검색이
    // 가져간다. **그때 이 줄들이 바뀐다** — CM-M2가 `Cmd+V`에 대해 남긴
    // 예고를 여기서 갚는다.
```

**넣을 것**

```zig
    // **`n`은 CN-M1의 검색이 가져갔다.** CN-M0이 여기 남긴 예고가 그것이었고,
    // 이 목록에 `n`이 없었던 덕에 이번에는 아무 줄도 안 깨졌다 — `w`를 배선할
    // 때와 갈리는 자리다.
    //
    // **`e`는 아직 모르는 키다.** CN이 일부러 안 만든 단어 이동이고
    // (design 결정 2), 누군가 `e`를 더하면 그때 이 줄이 바뀐다.
```

**그리고** Task 2가 넣은 검사 21 뒤에 아래를 더한다.

```zig

    // 검사 22. **`n`/`N`이 모드 안에서 명령이고 밖에서는 글자다.**
    try expect(&cm, K.KEY_N, 1, "n");
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&cm, K.KEY_N, .find_next);
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_N, .find_prev);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 23. **프롬프트 안에서는 `n`이 다시 글자다.** 이것이 이 milestone에서
    // 순서 하나가 정하는 사실이고, 깨지면 "검색어에 n을 못 친다"가 된다.
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'n' });
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'N' });
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_ESC, .find_cancel);
    // 프롬프트를 닫았으니 `n`은 다시 명령이다.
    try expectCopy(&cm, K.KEY_N, .find_next);
    try expectCopy(&cm, K.KEY_ESC, .exit);
```

### Step 5: 빌드와 검사 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

### Step 6: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig terminal/src/main.zig
git commit -m "Bind n and N to walk the search matches"
```

---

## Task 6: 게이트와 문서

**Files:**
- Modify: `copy/check.sh` (검사 15)
- Modify: design doc의 `Status:`, `docs/decisions/project_copy_navigation.md`,
  `MEMORY.md`, `HANDOFF.md`

### Step 1: 게이트 검사 15 (사용자가 편집)

**넣을 것** — `copy/check.sh`의 `# ── 음성 검사: 로그에 NUL이 섞이지 않았다` 앞이다.

```bash
# ── 검사 15: 스크롤백 검색 (CN-M1) ─────────────────────────────────────
#
# **design이 정한 완료 조건을 그대로 밟는다**: `/`로 스크롤백 위쪽의 글자를
# 찾아 커서가 그리로 옮겨진 것을 보고, 그 자리에서 V·y로 잡은 줄이 clip>에
# 나온다.
#
# 표적을 둘 만든다. 하나면 n이 "옮겼다"와 "감겼다"를 못 가른다.
echo "=== planting two search targets ==="
type_keys e c h o spc F I N D M E ret
sleep 2
type_keys s e q spc 1 0 0 ret
sleep 4
type_keys e c h o spc F I N D M E ret
sleep 2
type_keys s e q spc 1 0 0 ret
sleep 4

# 표적이 스크롤백으로 밀려 **화면에서 사라졌는지** 확인한다. 화면에 남아
# 있으면 이 검사는 "검색"이 아니라 "화면 안에서 커서 옮기기"가 된다.
if [ "$(screen_count 'FINDME')" -ne 0 ]; then
  report_failure "FINDME is still on screen; the search would not exercise scrollback"
fi

echo "=== searching backwards for FINDME ==="
type_keys meta_l-shift-c
sleep 2

FIND_BEFORE="$(key_lines)"

# `/` 를 열고 needle을 친다. **프롬프트가 화면에 나타나는지는 find> 줄로 본다** —
# 오버레이는 cells()에 안 섞이므로 screen> 에는 영영 안 나온다(design 결정 7).
type_keys slash
sleep 1
if ! grep -aq 'terminal: find> open' "$LOG"; then
  report_failure "/ did not open the find prompt"
fi

type_keys F I N D M E
sleep 1
if ! grep -aq 'terminal: find> type needle=FINDME len=6' "$LOG"; then
  echo "--- find> lines so far ---"
  grep -a 'terminal: find>' "$LOG" | tail -n 8
  report_failure "the prompt did not accumulate 'FINDME'"
fi

type_keys ret
sleep 3

SUBMIT="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1)"
case "$SUBMIT" in
  *"matches=2"*) ;;
  *) report_failure "expected two matches, got: ${SUBMIT}" ;;
esac
case "$SUBMIT" in
  *"moved=true"*) ;;
  *) report_failure "the search found matches but did not move the cursor: ${SUBMIT}" ;;
esac
# design 결정 5의 실측이다. **판정하지 않고 기록만 한다** — 값을 놓고 무엇을
# 할지는 사람이 정한다.
echo "search over the full scrollback: ${SUBMIT}"

# **판정(음성).** 프롬프트에 친 여섯 글자와 `/`·Enter가 PTY로 안 나갔다.
# 이것이 이 기능의 가장 흔한 실패 방식이다 — 검색어가 셸의 입력줄에 도착한다.
FIND_AFTER="$(key_lines)"
if [ "$FIND_AFTER" -ne "$FIND_BEFORE" ]; then
  report_failure "the find prompt leaked to the PTY (key> ${FIND_BEFORE} -> ${FIND_AFTER})"
fi

# **판정.** 커서가 선 줄을 줄 단위로 잡아 복사하면 FINDME가 나온다.
type_keys shift-v
sleep 1
type_keys y
sleep 2
if ! grep -aq 'terminal: clip> len=6 text=FINDME' "$LOG"; then
  echo "--- clip> lines ---"
  grep -a 'terminal: clip>' "$LOG" | tail -n 5
  report_failure "the yanked line was not 'FINDME'"
fi
echo "the search reached scrollback and the yanked line was FINDME"

# **판정.** n이 더 위의 매치로 간다. y가 모드를 닫았으므로 다시 들어간다 —
# 그런데 copyExit이 검색 상태를 버렸으므로(design 결정 10) 검색부터 다시 한다.
# **그 버림이 곧 이 판정의 대상이다.**
echo "=== n walks to the older match ==="
type_keys meta_l-shift-c
sleep 2
type_keys slash F I N D M E ret
sleep 3
ROW_FIRST="$(copy_value row)"
type_keys n
sleep 2
if ! grep -aq 'terminal: find> next moved=true' "$LOG"; then
  grep -a 'terminal: find> next' "$LOG" | tail -n 3
  report_failure "n did not move to another match"
fi
ROW_SECOND="$(copy_value row)"
echo "n moved the cursor from row ${ROW_FIRST} to row ${ROW_SECOND}"

type_keys esc
sleep 1
```

> **`slash`와 `shift-v`가 QEMU monitor의 키 이름이다.** `sendkey`가 받는 이름은
> `qemu-system-x86_64`의 표에 있고, CM-M2가 `meta_l-shift-c`로 세 키 조합이
> 도달하는 것을 이미 확인했다. **`slash`가 안 먹으면 그것부터 로그로 확인한다** —
> `find> open`이 안 나오는 것이 그 증상이다.

### Step 2: `copy` 체인을 돌린다 (Claude가 실행, 약 4분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash copy/check.sh' > /tmp/cn-m1-copy.out 2>&1
```

**`run_in_background`로 돌린다.** `| tail -N`을 붙이지 않는다.

**기대:** 마지막 줄이 `CM-M2 check PASS`이고, 그 앞에

```
search over the full scrollback: terminal: find> submit matches=2 moved=true us=…
the search reached scrollback and the yanked line was FINDME
n moved the cursor from row … to row …
```

**`us=` 값을 반드시 읽는다.** design 결정 5가 "블로킹이 느껴지는가"를 여기서
재기로 한 값이다. 수만 마이크로초(수십 밀리초)면 사람이 못 느끼고, 수십만
(수백 밀리초)이면 이월 숙제로 남긴다.

### Step 3: 루트 게이트 (Claude가 실행, 약 22분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/cn-m1-gate.out 2>&1
```

**`--platform`을 붙이지 않는다**(`project_build_host_arch`).
**`run_in_background`로 돌린다.**

**기대:** 여덟 체인 3/3.

**시간 해석.** 기준선은 **19분 01초**다(2026-08-27, CN-M0 이후). 이번에 더한
타이핑을 세면:

| | 키 |
|---|---|
| `echo FINDME` ×2 | 24 |
| `seq 100` ×2 | 18 |
| 모드 진입 ×2 | 2 |
| `/` + `FINDME` + Enter ×2 | 16 |
| `shift-v` · `y` · `n` · `esc` | 4 |
| **합** | **64** |

**64키 × 0.3초 ≈ 19초**, 여기에 `sleep` 합 약 26초와 `seq 100` 두 번의 출력
시간을 더해 **회차당 약 50초**다. copy 체인은 3회 부팅이므로 **약 2분 30초
증가**를 예상한다.

**이 게이트의 잡음이 ±3분이므로 2분 30초는 여전히 측정으로 갈리지 않는다.**
값을 기록하되 "우리 코드가 2분 30초를 더했다"고 주장하지 않는다. 다만 **CN-M0의
53초보다는 예상이 크므로, 실측이 22분을 넘으면 `sleep 0.3` 이월 숙제의 값이
그만큼 커진 것으로 적어 둔다.**

값이 25분을 크게 넘으면 **코드를 의심하기 전에 기계를 먼저 의심한다.**

### Step 4: 문서 (Claude가 편집)

1. **design doc의 `Status:`** 를
   `**Status:** 설계 확정. **CN-M0·CN-M1 완료(2026-08-27)**. Copy Navigation 종료`
   로 바꾼다. **이월 숙제의 "`Status:` 줄이 낡았다"를 새로 늘리지 않는다.**
2. **`docs/decisions/project_copy_navigation.md`** 에 CN-M1 절을 더한다.
   최소한 이 다섯을 적는다.
   - `Select.next`의 주석이 코드와 다르다(**감긴다**).
   - `ScreenSearch`는 우리 선택을 안 건드린다 — design 위험 1이 해소된 방식.
   - `ScreenSearch`가 `*Screen`을 들고 있어 대체 화면 전환에 낡는다.
   - 프롬프트 상태가 두 곳에 있는 것이 옳은 이유.
   - `searchAll`의 실측 시간(Step 2·3에서 얻은 `us=` 값).
3. **`MEMORY.md`** 의 Copy navigation 줄을 CN-M1 완료로 고친다.
4. **`HANDOFF.md`** 를 갱신한다. 최소한 이 다섯을 반영한다.
   - 제목과 "지금 어디인가"를 **Copy Navigation 종료, 진행 중인 것 없음**으로.
     다음 후보는 이월 숙제에서 고른다.
   - 게이트 기준선을 Step 3의 실측값으로. **잡음 범위를 함께 적는다.**
   - 로그 문구 목록에 **`terminal: find>` 여섯 형태**를 더한다
     (`open` · `type` · `erase` · `cancel` · `submit` · `next`/`prev`).
   - 핵심 파일의 줄 번호를 **전부 다시 센다.** `input.zig`와 `vt.zig`와
     `main.zig`가 크게 밀렸다.
   - `Copy`가 **`union(enum)`이고 variant가 열아홉**이라고 고친다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add copy/check.sh \
        docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md \
        docs/superpowers/plans/2026-08-27-tars-copy-navigation-cn-m1.md \
        docs/decisions/ MEMORY.md HANDOFF.md
git commit -m "Close out CN-M1"
```

**`git add` 전에 `git status`로 `M`과 신규를 가른다**(HANDOFF).

---

## 이 plan이 일부러 하지 않는 것

- **`?`(아래로 검색)** — design 결정 4. 더하려면 "방향"이라는 상태가 하나 늘고
  `n`/`N`의 뜻이 그것에 따라 뒤집힌다.
- **증분 검색** — design 결정 5. `us=` 실측이 크게 나오면 그때 옮긴다.
  `ScreenSearch`가 `tick`/`feed`로 이미 지원한다.
- **매치 하이라이트** — 화면의 모든 매치를 표시하는 것. `ViewportSearch`가 그
  용도로 있지만 `cells()`가 넘기는 색 결정에 손을 대야 한다.
- **검색 기록** — `/`를 다시 열었을 때 지난 needle을 되부르는 것. 그래서 빈
  검색어로 Enter를 눌러도 vim처럼 지난 검색어를 다시 쓰지 않는다.
- **프롬프트 안의 커서 이동과 붙여넣기** — 프롬프트는 끝에 붙이고 끝에서
  지우는 것만 한다. `←`로 가운데를 고치는 것은 편집기이지 프롬프트가 아니다.
- **`n`이 커서 위쪽만 고르게 하기** — CN-M1 plan 결정 3. `/`만 가린다.
- **매치를 못 찾았을 때 화면에 알리기** — 로그에는 `matches=0`이 남지만 사람은
  프롬프트가 닫히는 것 말고 아무 신호도 못 받는다. 상태줄이 없기 때문이고,
  그것을 만드는 것은 design 결정 7이 버린 안이다.
