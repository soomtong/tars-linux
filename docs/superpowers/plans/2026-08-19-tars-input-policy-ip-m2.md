# TARS Input Policy IP-M2 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 이 서브프로젝트를 시작한 **원래 동기**를 채운다. `Option+←/→`로
단어를 건너뛰고, `Cmd+←/→`로 줄 처음과 끝에 가고, `Option+Backspace`로 단어를
지운다. 그리고 그 의미론이 **어느 물리 키보드를 쓰는지에 따라 자리를 바꾼다** —
`/config/tars.conf`의 `keyboard=apple|pc` 한 줄이 Alt와 Meta를 맞바꾼다.
이 milestone이 끝나면 design doc의 목표 다섯이 전부 게이트로 증명된다.

**Design doc:** `docs/superpowers/specs/2026-08-15-tars-input-policy-design.md`
(결정 4의 나머지 절반, 결정 8·9가 이 milestone의 몫)

**배경 자료:** `docs/study/2026-08-15-keyboard-escape-sequence-crash-course.md`

**Tech Stack:** Zig 0.16.0, bash readline, QEMU monitor `sendkey`,
`mkfs.ext2 -d`, Docker(`tars-devcontainer`, arm64)

---

## 왜 이 순서인가

```
Task 1   pub const c + comptime 앵커                  ← 저울을 먼저 고친다
  ↓      동작 불변. 표가 밀리면 컴파일이 막힌다
Task 2   modifier 여덟 + Option/Cmd dispatch 표        ← 이 milestone의 본체
  ↓      design doc 결정 2의 "2번 단계"가 드디어 채워진다
Task 3   Alt↔Meta swap                                 ← swap_alt_meta의 첫 독자
  ↓      아직 아무도 true를 넣어주지 않는다(테스트만 넣는다)
Task 4   config.zig Keyboard enum + argv 넷째 자리     ← 설정이 코드에 닿는다
  ↓      init의 첫 호스트 단위 검사도 여기서 생긴다
Task 5   게이트 1차 부팅 — bash에서 Option/Cmd         ← apple 의미론 증명
  ↓
Task 6   게이트 2차 부팅 — keyboard=pc 디스크          ← swap 증명
  ↓
Task 7   루트 게이트 4체인 3/3
```

**Task 1이 맨 앞인 이유**는 IP-M2가 `keymap` 배열 **밖의** 코드를 처음으로
정면으로 다루기 때문이다. `KEY_LEFTMETA`는 125이고 `keymap.len`은 58이다.
지금 그 표의 N번째 칸이 evdev 코드 N이라는 것을 지켜주는 것은 **주석뿐**이고,
중간에 한 줄이 끼면 뒤가 전부 밀리면서 **컴파일은 통과한다.** 표를 늘리기
직전이 그 못을 박을 자리다.

**Task 2가 modifier와 dispatch를 한 Task에 묶는 이유**는 관측 가능성이다.
IP-M1은 "시그니처 넓히기"와 "동작 바꾸기"를 갈랐지만, 여기서 그렇게 나누면
가른 앞쪽을 **테스트가 볼 방법이 없다.** `KEY_LEFTALT`(56)는 지금도 keymap에
`.{ 0, 0 }`이라 `""`를 돌려주고, `KEY_LEFTMETA`(125)는 `keymap.len` 밖이라
역시 `""`다. modifier 비트만 추가하면 `handleKey`의 반환값이 **한 글자도 안
바뀐다.** IP-M0가 Alt/Meta 넷을 "관측 가능해지는 시점에 넣는다"며 미룬 이유가
정확히 이것이고, 그 시점이 dispatch 표가 생기는 순간이다.

**Task 3이 Task 2 뒤인 이유**는 반대다. swap은 dispatch가 있어야 관측된다 —
`swap_alt_meta=true`에서 `Alt+←`가 `ESC b`가 아니라 `0x01`이 되는 것이
증거인데, 그 둘이 다 존재해야 비교가 성립한다.

**Task 4가 Task 3 뒤인 이유**는 CP-M2에서 배운 것이다. 설정 경로(파일 → PID 1
→ argv → terminal)는 네 컴포넌트를 지나므로 **도착지가 이미 동작할 때** 깔아야
실패를 한 곳으로 좁힐 수 있다. Task 3까지 끝나면 `Context.swap_alt_meta = true`가
무슨 일을 하는지 호스트 테스트가 이미 다 알고 있고, Task 4의 실패는 오직
"그 true가 도착하지 않았다"뿐이다.

**Task 5와 6을 나누는 이유**는 게이트가 커지기 때문이다. 5는 기존 부팅에
sendkey를 더하는 것이고(빠른 되먹임), 6은 부팅을 하나 더 붙이는 구조 변경이다.
한 번에 하면 실패했을 때 "타이핑이 틀렸나, 디스크가 안 붙었나"를 못 가른다.

## 설계에서 조정한 것 둘

**1. IP 체인이 디스크를 문다 — design doc 결정 11의 수정.**

결정 11은 "IP가 증명할 것은 전부 한 세션 안에 있으니 부팅 한 번, 디스크는
물리지 않는다"고 적었다. 그런데 같은 문서의 **목표 5**는 이렇게 적었다.

> 5. **키보드 종류를 설정으로 고른다** — `/config/tars.conf`의
>    `keyboard=apple|pc`가 Alt↔Meta 보정을 켜고 끈다.
>
> 그리고 이 다섯이 **게이트로 증명된다**

디스크가 없으면 `/config` mount가 실패하고 `loadConfig`가 기본값을 돌려주므로
**설정은 영원히 `apple`이다.** `pc` 경로는 게이트가 한 번도 밟지 않는다.
IP-M1의 DECCKM과 정확히 같은 병 — `project_gate_chain_composition`의
"게이트가 **구조적으로** 밟을 수 없는 경로"다.

그때의 대응은 "호스트 단위 검사가 대신 본다 + 로그로 어느 쪽이었는지 남긴다"
였다. 여기서는 그 대응을 쓰지 않는다. **DECCKM은 우리가 켤 수 없는 것(셸이
`smkx`를 보내야 한다)이지만, `keyboard=pc`는 우리가 파일 한 줄로 켤 수 있기
때문이다.** 켤 수 있는 것을 안 켜고 "게이트가 못 본다"고 적는 것은 게으름이지
구조적 한계가 아니다.

비용은 작다. CP처럼 게스트에 타이핑해서 설정을 고칠 필요가 없다 —
`mkfs.ext2 -d`로 **내용이 이미 든 이미지**를 구우면 2차 부팅은 그냥 읽기만
한다. 부팅 1회(~4초) + sendkey 25개(~7.5초)다.

디스크 없는 부팅도 **1차로 그대로 남는다.** 결정 11이 "폴백 경로를 덤으로 한 번
더 밟는다"고 적은 그 성질은 1차 부팅이 계속 지킨다.

**2. `Ctrl+←`는 이번에도 안 한다.**

IP-M1 plan이 `input_test`에 남긴 주석은 "M2의 조합 dispatch가 이 위에 얹히면서
이 줄이 바뀐다"였다. **바뀌지 않는다.** 결정 8의 표에 있는 것은 Option과 Cmd
일곱 줄뿐이고 Ctrl+방향키(`ESC [ 1 ; 5 D`)는 거기 없다. 누를 이유가 있는 앱이
아직 없고, design doc 비목표의 "게이트가 볼 수 없는 표를 늘리지 않는다"가 그대로
적용된다.

그래서 Task 2에서 **그 주석을 고친다.** 지금 그대로 두면 다음 세션이 "M2가
빼먹었나"를 의심하게 된다. `State.seq`가 8바이트인데 이번에도 가장 긴 시퀀스는
4바이트(`ESC [ 3 ~`)이고, 6바이트는 여전히 미사용으로 남는다.

## 이번에 정하는 것 셋 (design doc이 안 정한 자리)

**1. 표에 없는 Option/Cmd 조합은 modifier를 무시하고 원래 키를 보낸다.**

`Option+b`는 macOS에서 `∫`를 찍고, xterm에서는 `metaSendsEscape`로 `ESC b`가
된다. 어느 쪽도 이번 범위가 아니다. 기존 Ctrl이 마스크 대상이 아닌 문자
(`Ctrl+1` → `1`)를 다루는 방식과 **같은 규칙**을 쓴다: 가로챌 것만 가로채고
나머지는 평소대로.

이 규칙이 `Cmd+C`/`Cmd+V`에도 적용된다 — design doc 비목표가 "다른 용도로 쓰지
않고 비워둔다"고 한 그 자리다. 지금은 `c`/`v`가 찍힌다.
`project_copy_mode`가 그 자리를 가져갈 때 이 줄들이 바뀐다.

**2. Cmd와 Option이 동시에 눌리면 Cmd가 이긴다.**

임의의 선택이지만 **결정적**이어야 한다(같은 입력에 늘 같은 출력).
macOS에서도 Cmd가 더 강한 modifier라는 직관과 맞는다. 코드에서는 `chord`가
Meta를 먼저 보는 것으로 표현되고, 테스트가 그 순서를 못 박는다.

**3. `terminal`은 `keyboard` 값을 파싱하지 않는다 — `"pc"`와 문자열 비교만 한다.**

CP가 정한 "파서는 한 벌"(PID 1만 설정을 읽는다)을 지킨다. `init`이 enum으로
검증한 뒤 `apple`/`pc` 둘 중 하나만 argv에 넣으므로, `terminal` 쪽에서는
`std.mem.eql(u8, kb, "pc")` 한 줄이면 되고 그 외 모든 값은 `apple`로 떨어진다.
`Keyboard` enum을 `terminal`에도 복사하면 그 순간 파서가 두 벌이 된다.

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이번에 `/tmp` + `cp` + `diff` 경로를 쓰는 파일은 둘이다** —
`terminal/src/input_test.zig`(Task 1, 전면 치환이라 100줄을 넘는다)와
`input/check.sh`(Task 6, 부팅 구조가 바뀐다). 나머지는 전부 30~60줄 블록
교체라 인라인으로 제시한다.

**이미지 재빌드는 필요 없다.** bash는 이미 initrd에 들어간다
(`kernel/make_initrd.sh:103`), terminfo도 IP-M1이 넣었다.

---

## Task 1: 표를 커널의 이름에 못 박는다

사용자가 IP-M1 때 요청한 검토 셋 중 1번과 3번이다. **동작은 하나도 바뀌지
않는다.**

지금 `terminal/src/input.zig:19-78`의 `keymap`은 "N번째 칸이 evdev 코드 N"이라는
규약 위에 서 있는데, 그것을 지켜주는 것이 **주석뿐**이다. 중간에 한 줄이 끼면
뒤가 전부 한 칸씩 밀리고, `keymap[30]`이 더 이상 `a`가 아니게 되며,
**컴파일은 멀쩡히 통과한다.** 주석만 거짓말이 된 채로.

IP-M2는 `KEY_LEFTMETA`(125)처럼 이 표 **밖의** 코드를 처음으로 정면으로
다루므로, 표를 건드리기 직전인 지금이 못을 박을 자리다.

같은 한 단어(`const c` → `pub const c`)가 검토 1번도 연다. `input_test.zig`의
숫자 리터럴이 숫자인 이유는 `linux/input.h`에 닿을 방법이 없어서였는데,
`input.zig`가 이미 `@cImport`로 가져와 두고 private으로 잠가 뒀을 뿐이다.

**"테스트가 구현과 같은 출처를 쓰면 독립성을 잃는다"는 반론은 여기서 성립하지
않는다.** "103이 정말 ←인가"에 답하는 것은 부팅 게이트(QEMU `sendkey left` →
스캔코드 → atkbd → evdev)이고, 단위 검사가 답하는 것은 "`KEY_LEFT`가
`ESC [ D`가 되는가"다. 두 질문은 서로 다른 층에 있다.

**검토 2번(ASCII 이스케이프 바이트)은 그대로 둔다.** 테스트의 `"\x1b[A"`는
와이어 포맷 자체라 쪼개면 오히려 안 보인다. 구현의 `0x1b`만 `const ESC`로 뺀
IP-M1의 선이 적정선이다.

**Files:**
- Modify: `terminal/src/input.zig:3` (`pub const c`), keymap 뒤에 comptime 블록
- Rewrite: `terminal/src/input_test.zig` (키코드 리터럴 → 심볼)

- [ ] **Step 1: `c`를 공개한다**

`terminal/src/input.zig:3`의

```zig
const c = @cImport({
```

을 이것으로.

```zig
/// `pub`인 이유는 `input_test.zig`가 `input.c.KEY_LEFT`처럼 커널이 정한
/// 이름으로 검사를 쓰기 위해서다. IP-M1까지 테스트는 103/105 같은 숫자
/// 리터럴을 썼는데, 그건 테스트가 `linux/input.h`에 닿을 방법이 없어서였다 —
/// 실은 이 파일이 이미 가져와 두고 잠가 뒀을 뿐이었다.
///
/// "테스트가 구현과 같은 출처를 쓰면 독립성을 잃는다"는 반론은 여기서
/// 성립하지 않는다. "103이 정말 ←인가"에 답하는 것은 부팅 게이트이고
/// (sendkey → 스캔코드 → atkbd → evdev), 단위 검사가 답하는 것은
/// "KEY_LEFT가 ESC [ D가 되는가"다.
pub const c = @cImport({
```

- [ ] **Step 2: keymap 뒤에 comptime 앵커를 박는다**

`terminal/src/input.zig:78`의 `};`(keymap 배열 닫는 줄) **바로 뒤에** 넣는다.

```zig

/// 위 표의 규약은 "N번째 칸이 evdev 코드 N"인데, IP-M1까지 그것을 지켜주는
/// 것은 주석뿐이었다. 중간에 한 줄이 끼면 뒤가 전부 한 칸씩 밀리고, 그래도
/// **컴파일은 통과하며**, 주석만 거짓말이 된다. 증상은 "게스트에서 a를 쳤는데
/// s가 나온다"로 나타나므로 원인을 찾는 데 부팅 한 바퀴가 든다.
///
/// 그래서 표의 양끝과 가운데를 커널의 이름에 못 박는다. 다섯 줄로 표 전체의
/// 정렬을 잡는 이유는, 한 줄이 끼면 그 뒤의 앵커가 **반드시** 하나는 어긋나기
/// 때문이다. IP-M2가 이 표 밖의 코드(KEY_LEFTMETA=125)를 처음 다루므로
/// 지금이 못을 박을 자리다.
comptime {
    if (keymap.len != c.KEY_SPACE + 1)
        @compileError("keymap must end exactly at KEY_SPACE");
    if (keymap[c.KEY_1][0] != '1') @compileError("keymap drifted at KEY_1");
    if (keymap[c.KEY_ENTER][0] != '\r') @compileError("keymap drifted at KEY_ENTER");
    if (keymap[c.KEY_A][0] != 'a') @compileError("keymap drifted at KEY_A");
    if (keymap[c.KEY_Z][0] != 'z') @compileError("keymap drifted at KEY_Z");
}
```

- [ ] **Step 3: 앵커가 실제로 무는지 확인한다 (일부러 깨뜨려 본다)**

이 Step을 건너뛰지 말 것. **못이 박혔는지 확인하는 유일한 방법은 한 번
때려보는 것이다.** IP-M0/M1에서 "테스트 먼저 → 실패 확인"이 두 번 잘 통한 것과
같은 이유다.

`terminal/src/input.zig:20`의

```zig
    .{ 0, 0 }, //  0: (없음)
```

바로 뒤에 한 줄을 **임시로** 끼운다.

```zig
    .{ 0, 0 }, // (일부러 끼운 줄 — 다음 Step에서 지운다)
```

그리고:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: **컴파일 에러 두 개.**

```
error: keymap must end exactly at KEY_SPACE
error: keymap drifted at KEY_1
```

`KEY_ENTER`/`KEY_A`/`KEY_Z` 앵커도 함께 터질 수 있다. 몇 개가 터지든 상관없고,
**하나라도 안 터지면 앵커가 헐거운 것**이니 알려 달라.

- [ ] **Step 4: 끼운 줄을 지운다**

Step 3에서 넣은 한 줄을 지우고 다시 돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대:

```
input_event size = 24 (expected 24)
PASS
```

- [ ] **Step 5: `input_test.zig`의 키코드를 이름으로 바꾼다**

파일 전체에 걸친 치환이라 **`/tmp` 경로를 쓴다**(CP-M2에서 정한 100줄 규칙).
Claude가 `/tmp/input_test.zig`를 만들어 두면 사용자가 이렇게 한다.

```bash
cp /tmp/input_test.zig terminal/src/input_test.zig
diff /tmp/input_test.zig terminal/src/input_test.zig && echo "identical"
```

바뀌는 것은 두 가지뿐이다.

```zig
// 파일 앞부분에 별칭 하나
/// evdev 키코드를 커널이 정한 이름으로 쓴다. `input.c`는 input.zig가
/// @cImport("linux/input.h")한 것을 그대로 공개한 것이다(IP-M2).
/// 숫자를 남겨두면 "105가 ←였나 →였나"를 매번 헤아려야 하는데, 이 파일은
/// IP-M2에서 검사가 두 배로 는다.
const K = input.c;
```

```zig
// 그리고 모든 호출의 첫 인자
try expect(&state, 35, 1, "h");   →   try expect(&state, K.KEY_H, 1, "h");
try expect(&state, 105, 1, "\x1b[D"); → try expect(&state, K.KEY_LEFT, 1, "\x1b[D");
```

**바이트 쪽(`"\x1b[D"`, `"\x03"`)은 한 글자도 안 건드린다.** 거기서는 그것이
와이어 포맷 자체이고, 쪼개는 순간 무슨 바이트가 나가는지 안 보인다(검토 2번).

`try expect(&state, 200, 1, "");`("표에 없는 키코드")의 200은 **숫자로 남긴다.**
그 줄의 요점이 "이름이 없는 코드"라서 이름을 붙이면 뜻이 사라진다. 주석으로
`// 이름 없는 코드 — 조용히 무시된다`를 붙인다.

- [ ] **Step 6: 통과 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: `PASS`. 검사 내용이 하나도 안 바뀌었으므로 출력도 IP-M1과 같아야 한다.

**`error: root struct of file 'input' has no member named 'c'`가 나오면**
Step 1의 `pub`이 안 들어간 것이다. **`error: 'KEY_H' is not a member`가 나오면**
컨테이너의 `linux-libc-dev`가 그 상수를 안 준다는 뜻이니 알려 달라 — IP-M1에서
`KEY_UP`~`KEY_PAGEDOWN` 아홉 개는 전부 들어오는 것을 이미 확인했으므로 그럴
가능성은 낮다.

- [ ] **Step 7: Commit**

Claude가 수행한다. 커밋 메시지: `Anchor the keymap to the kernel's key names`

---

## Task 2: Option과 Cmd가 무슨 뜻인지 가르친다

이 milestone의 본체다. design doc 결정 2가 그린 세 단계 중 **2번(조합
dispatch)** 이 드디어 채워진다. TF design doc이 "여긴 나중에"라고 비워둔 뒤로
두 서브프로젝트를 건너온 자리다.

```
evdev fd ──poll──> readKeys ──> handleKey ──┐
                                            │  0. 키보드 보정      (Task 3)
                                            │  1. modifier 갱신    ← 넷 → 여덟
                                            │  2. 조합 dispatch    ← 이번에 생긴다
                                            │  3. 기본 번역
                                            └──> []const u8 ──> pty.write
```

**2번이 3번보다 먼저여야 한다.** 뒤에 두면 `Cmd+←`가 dispatch에 닿기 전에
3번에서 그냥 `←`(`ESC [ D`)로 번역돼 새어 나간다. IP-M1이 특수키 조회를
`keymap` 조회보다 앞에 둔 것과 같은 규칙이고, 이번에는 그 특수키 조회보다도
**더 앞**에 놓는다.

**결정 8의 표를 그대로 옮긴다.**

| 조합 | 보내는 바이트 | 길이 | readline에서의 뜻 |
|---|---|---|---|
| Option+← | `ESC b` | 2 | backward-word |
| Option+→ | `ESC f` | 2 | forward-word |
| Option+Backspace | `ESC 0x7F` | 2 | backward-kill-word |
| Option+Delete | `ESC d` | 2 | kill-word |
| Cmd+← | `0x01` | 1 | beginning-of-line |
| Cmd+→ | `0x05` | 1 | end-of-line |
| Cmd+Backspace | `0x15` | 1 | 줄 앞부분 삭제 |

**길이 칸을 적어둔 이유가 있다.** `main.zig:183`이 매 키마다
`terminal: key> {d} byte(s)`를 찍는데, 이번 범위에서 **2바이트를 만드는 것은
Option 조합뿐**이다(맨 방향키는 3, 평문은 1). 그래서 게이트 로그의
`2 byte(s)` 한 줄이 "Option 경로를 실제로 밟았다"의 유일무이한 증거가 된다 —
Task 5가 이것을 쓴다.

**Files:**
- Modify: `terminal/src/input_test.zig` (검사 추가, M1 주석 수정)
- Modify: `terminal/src/input.zig` (modifier 넷, `chord`, `escPrefixed`, `handleKey`)

- [ ] **Step 1: 실패하는 검사를 먼저 추가**

`terminal/src/input_test.zig`의 "── 아직 안 하는 것을 적어둔다 ──" 블록
(`:161-179`)을 통째로 이것으로 바꾼다. 그 블록의 절반은 이제 사실이 아니게
되므로 지우는 것이 아니라 **갱신**이다.

```zig
    // ── modifier가 넷에서 여덟으로 (IP-M2, design doc 결정 4) ────────────
    //
    // Alt 좌우(56/100)와 Meta 좌우(125/126)가 들어온다. IP-M0가 이 넷을
    // "관측 가능해지는 시점에 넣는다"며 미룬 이유가 아래 두 줄이다 —
    // modifier 비트만 있으면 반환값이 한 글자도 안 바뀌어서 검사가 성립하지
    // 않는다. 그 시점이 바로 다음 블록(조합 dispatch)이다.
    try expect(&state, K.KEY_LEFTALT, 1, ""); // 그 자체는 문자가 없다
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFTMETA, 1, ""); // 125는 keymap.len(58) 밖이다
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    // ── Option 조합 (design doc 결정 8) ─────────────────────────────────
    //
    // 셸이 **이미 아는 언어**로 번역한다(A안). ESC 접두사는 터미널에서
    // "Meta+그 글자"를 뜻하는 오래된 관례이고, readline/zle/fish가 전부
    // 기본값으로 안다 — 설정 파일 없이 동작한다는 것이 A안을 고른 결정적
    // 이유였다(그래야 --no-config로 뜬 셸에서 게이트가 증명할 수 있다).
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // backward-word
    try expect(&state, K.KEY_RIGHT, 1, "\x1bf"); // forward-word
    try expect(&state, K.KEY_BACKSPACE, 1, "\x1b\x7f"); // backward-kill-word
    try expect(&state, K.KEY_DELETE, 1, "\x1bd"); // kill-word

    // 표에 없는 조합은 modifier를 무시하고 원래 키를 보낸다. Ctrl이 마스크
    // 대상이 아닌 문자(Ctrl+1 → '1')를 다루는 방식과 같은 규칙이다 —
    // 가로챌 것만 가로채고 나머지는 평소대로.
    try expect(&state, K.KEY_B, 1, "b"); // Option+b는 이번 범위가 아니다
    try expect(&state, K.KEY_UP, 1, "\x1b[A"); // Option+↑도 그냥 ↑
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // 오른쪽 Alt(100)도 같다. 좌우를 따로 추적하는 이유는 Shift/Ctrl과
    // 같다 — 하나를 누른 채 다른 하나를 눌렀다 떼도 풀리면 안 된다.
    try expect(&state, K.KEY_RIGHTALT, 1, "");
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_RIGHTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // 여전히 Option
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 이제 맨 ←

    // ── Cmd 조합 ────────────────────────────────────────────────────────
    //
    // 이쪽은 ESC 접두사가 아니라 **제어 문자 한 바이트**다. Cmd+←가 0x01
    // (Ctrl+A)인 이유는 그것이 readline의 beginning-of-line이기 때문이지
    // 무슨 대응 관계가 있어서가 아니다 — "셸이 이미 아는 언어"라는 것이
    // 유일한 기준이다.
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // beginning-of-line
    try expect(&state, K.KEY_RIGHT, 1, "\x05"); // end-of-line
    try expect(&state, K.KEY_BACKSPACE, 1, "\x15"); // 줄 앞부분 삭제

    // Cmd+Delete는 표에 없다 → 맨 Delete가 나간다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    // Cmd+C / Cmd+V는 **일부러 비워둔 자리**다(design doc 비목표).
    // 복사·붙여넣기는 스크롤백과 클립보드가 선행 조건이라
    // project_copy_mode의 몫이고, 그때 이 두 줄이 바뀐다.
    try expect(&state, K.KEY_C, 1, "c");
    try expect(&state, K.KEY_V, 1, "v");
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    try expect(&state, K.KEY_RIGHTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // 오른쪽 Meta(126)도 같다
    try expect(&state, K.KEY_RIGHTMETA, 0, "");

    // ── 둘 다 눌리면 Cmd가 이긴다 ───────────────────────────────────────
    //
    // 임의의 선택이지만 **결정적**이어야 한다. macOS에서 Cmd가 더 강한
    // modifier라는 직관과 맞고, 코드에서는 chord가 Meta를 먼저 보는 것으로
    // 표현된다. 이 줄이 그 순서를 못 박는다.
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expect(&state, K.KEY_LEFTMETA, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // Meta를 떼면 Option으로
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // ── 조합은 DECCKM보다 강하다 ────────────────────────────────────────
    //
    // dispatch가 특수키 조회보다 **먼저** 오기 때문이다(design doc 결정 2의
    // "가로챌 것을 먼저"). Option+←는 DECCKM이 켜져 있어도 ESC b이고,
    // ESC O D로 바뀌지 않는다. 순서가 뒤집히면 이 줄이 먼저 터진다.
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 0, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bOD"); // 조합이 없으면 다시 DECCKM

    // ── 여전히 안 하는 것 ───────────────────────────────────────────────
    //
    // Ctrl+방향키(`ESC [ 1 ; 5 D`)와 Shift+방향키는 **IP-M2도 하지 않는다.**
    // IP-M1의 주석은 "M2의 조합 dispatch가 이 위에 얹히면서 바뀐다"고 적었지만
    // 그렇지 않았다 — 결정 8의 표에 있는 것은 Option과 Cmd 일곱 줄뿐이고,
    // Ctrl+방향키를 누를 이유가 있는 앱이 아직 하나도 없다(design doc 비목표:
    // "게이트가 볼 수 없는 표를 늘리지 않는다").
    //
    // 그래서 State.seq의 8바이트 중 이번에도 4바이트까지만 쓴다. 6바이트를
    // 쓰는 형태가 바로 이 `ESC [ 1 ; 5 D`다.
    try expect(&state, K.KEY_LEFTCTRL, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Ctrl+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTCTRL, 0, "");

    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Shift+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    // 특수키 사이의 빈 코드(F1 등)는 여전히 조용히 무시된다.
    try expect(&state, K.KEY_F1, 1, "");
    try expect(&state, K.KEY_INSERT, 1, "");
```

`ckm`은 IP-M1이 만든 `const ckm = input.Context{ .cursor_keys = true };`
(`:147`)를 그대로 쓴다.

- [ ] **Step 2: 실패하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: 컴파일은 되고 **실행이 실패**한다. 첫 실패는 이것이어야 한다.

```
FAIL: code=105 value=1 ckm=false -> got={ 27, 91, 68 }, want={ 27, 98 }
```

`{27, 91, 68}`이 `ESC [ D`(맨 ←)이고 `{27, 98}`이 `ESC b`다. 지금 Alt는
modifier로 추적되지도 않고 dispatch 표도 없으니, `Option+←`가 그냥 `←`로
새어 나간다 — **HANDOFF의 "알아둘 것 4"가 말한 그 누수를 눈으로 보는
자리다.**

`code=56`(`KEY_LEFTALT` press)에서 먼저 실패하지 **않는** 것도 확인한다.
56은 keymap에 `.{ 0, 0 }`이라 이미 `""`를 돌려주기 때문이다 — 그것이 이
Task에서 modifier와 dispatch를 한데 묶은 이유다.

- [ ] **Step 3: `State`에 modifier 넷을 더한다**

`terminal/src/input.zig:150-151`의 `ctrl_left`/`ctrl_right` 정의 **뒤에** 넣는다.

```zig
    // Alt(Option)와 Meta(Cmd). design doc 결정 4의 여덟 중 나머지 넷이고,
    // IP-M0가 "관측 가능해지는 시점에 넣는다"며 미뤄둔 것이다. 그 시점이
    // 아래 chord()가 생기는 지금이다 — 비트만 있으면 반환값이 안 바뀌어서
    // 검사할 수가 없었다.
    //
    // 이름을 alt/meta로 붙이는 것은 **물리 키 이름**을 따른 것이다.
    // 어느 것이 Option이고 어느 것이 Cmd인지는 키보드 종류가 정하며,
    // 그 보정은 handleKey 맨 앞에서 코드를 맞바꾸는 것으로 끝난다(결정 9).
    // 여기까지 내려오면 "왼쪽 Alt 키가 눌려 있다"는 사실만 남는다.
    alt_left: bool = false,
    alt_right: bool = false,
    meta_left: bool = false,
    meta_right: bool = false,
```

그리고 `:161-167`의 `shifted`/`ctrled` **뒤에** 둘을 더한다.

```zig
    fn alted(self: State) bool {
        return self.alt_left or self.alt_right;
    }

    fn metaed(self: State) bool {
        return self.meta_left or self.meta_right;
    }
```

- [ ] **Step 4: `escPrefixed`와 `chord`를 추가**

`input.zig`의 `escape` 함수(`:192-210`) **바로 뒤에** 넣는다.

```zig
    /// `ESC <byte>` 두 바이트. 터미널에서 "Meta+그 글자"를 뜻하는 오래된
    /// 관례이고, readline·zle·fish가 전부 기본값으로 안다.
    ///
    /// 이 ESC는 `Ctrl+[`가 만드는 것과 **완전히 같은 바이트**다. 그래서
    /// 받는 쪽은 ESC 다음 바이트를 잠깐 기다려서 "Meta 조합"인지 "혼자 온
    /// ESC"인지 가른다(readline의 keyseq-timeout). 우리 쪽에서 지켜야 할
    /// 것은 **두 바이트를 한 번의 write로 보내는 것**뿐인데, readKeys가
    /// out에 모아 main.zig가 한 번 pty.write하는 지금 구조가 이미 그렇다.
    fn escPrefixed(self: *State, byte: u8) []const u8 {
        self.seq[0] = ESC;
        self.seq[1] = byte;
        return self.seq[0..2];
    }

    /// design doc 결정 2의 **2번 단계 — 조합 dispatch**. TF design doc이
    /// "여긴 나중에"라고 비워두고 두 서브프로젝트를 건너온 자리다.
    ///
    /// 여기가 3번(기본 번역)보다 **먼저** 불려야 한다. 뒤에 두면 Cmd+←가
    /// 여기 닿기 전에 특수키 조회에서 그냥 ESC [ D로 번역돼 새어 나간다.
    /// "가로챌 것을 먼저 가로채고, 남은 것만 평소대로"가 규칙이다.
    ///
    /// 표에 없는 조합(Option+b, Cmd+C 등)은 null을 돌려주고 modifier가
    /// 없었던 것처럼 흘러간다. Ctrl이 마스크 대상이 아닌 문자를 다루는
    /// 방식(Ctrl+1 → '1')과 같은 규칙이다.
    ///
    /// Meta를 먼저 보는 것은 **둘 다 눌렸을 때 Cmd가 이긴다**는 뜻이고,
    /// 임의의 선택이지만 결정적이어야 해서 여기 한 곳에서만 정한다.
    fn chord(self: *State, code: u16) ?[]const u8 {
        if (self.metaed()) {
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
                c.KEY_LEFT => self.one(0x01), // Ctrl+A: beginning-of-line
                c.KEY_RIGHT => self.one(0x05), // Ctrl+E: end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => self.one(0x15),
                else => null,
            };
        }
        if (self.alted()) {
            return switch (code) {
                c.KEY_LEFT => self.escPrefixed('b'), // backward-word
                c.KEY_RIGHT => self.escPrefixed('f'), // forward-word
                c.KEY_BACKSPACE => self.escPrefixed(0x7f), // backward-kill-word
                c.KEY_DELETE => self.escPrefixed('d'), // kill-word
                else => null,
            };
        }
        return null;
    }
```

- [ ] **Step 5: `handleKey`가 여덟을 추적하고 dispatch를 먼저 본다**

`input.zig:216-234`의 modifier switch에 네 갈래를 더한다.
`c.KEY_RIGHTCTRL` 갈래 **뒤에**, `else => {}` **앞에** 넣는다.

```zig
            c.KEY_LEFTALT => {
                self.alt_left = value != 0;
                return none;
            },
            c.KEY_RIGHTALT => {
                self.alt_right = value != 0;
                return none;
            },
            c.KEY_LEFTMETA => {
                self.meta_left = value != 0;
                return none;
            },
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return none;
            },
```

그리고 `:236`의 `if (value == 0) return none;` **뒤**, `:237`의 특수키 주석
**앞에** 조합 dispatch를 끼운다.

```zig
        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        // 뒤에 두면 Cmd+←가 여기 닿기 전에 ESC [ D로 번역돼 새어 나간다.
        if (self.chord(code)) |bytes| return bytes;

```

바뀐 뒤 `handleKey`의 아랫부분은 이렇게 된다.

```zig
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        if (self.chord(code)) |bytes| return bytes;

        // 특수키를 keymap 조회보다 먼저 본다. ...
        if (specialKey(code)) |key| return self.escape(key, ctx);

        if (code >= keymap.len) return none;
        ...
```

`keymap`의 56번 칸 주석도 고친다. `input.zig:76`의

```zig
    .{ 0, 0 }, // 56: KEY_LEFTALT
```

을

```zig
    .{ 0, 0 }, // 56: KEY_LEFTALT — modifier로 처리한다(IP-M2)
```

로. 29번(`KEY_LEFTCTRL`)이 이미 그렇게 적혀 있으니 맞추는 것이다.

- [ ] **Step 6: 통과 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test && ./prepare.sh"
```

기대: `PASS`, 그리고 x86_64 본체 빌드도 에러 없이 끝난다.

실패하면 구분할 것이 셋이다.

- **`code=105 ... got={27,91,68}, want={27,98}`이 남아 있다** → dispatch가
  안 불리고 있다. `chord` 호출이 `specialKey` 조회 **뒤에** 들어갔는지 본다.
- **`code=105 ckm=true`에서 `got={27,79,68}, want={27,98}`** → 같은 원인이
  DECCKM 검사에서 드러난 것이다. 순서 문제다.
- **`code=45`(`KEY_X`) 같은 평범한 글자가 깨진다** → `chord`의 `else => null`이
  빠졌거나 `one()`이 seq를 덮어쓰는 순서가 꼬인 것이다.

- [ ] **Step 7: Commit**

Claude가 수행한다. 커밋 메시지: `Teach the terminal what Option and Command mean`

---

## Task 3: PC 키보드가 Alt와 Meta를 맞바꾼다

design doc 결정 9다. `Context.swap_alt_meta`는 IP-M1에 자리만 만들어 두고
**아무도 읽지 않는 필드**로 남아 있었다. 여기가 첫 독자다.

```
Apple:  [Ctrl] [Option] [Cmd]    [Space]
         29      56      125
PC:     [Ctrl] [Win]   [Alt]     [Space]
         29     125      56
```

스페이스 옆 두 키의 **순서가 정확히 뒤집혀** 있다. 그래서 하는 일은
"modifier 상태를 기록하기 전에 56↔125, 100↔126을 맞바꾸는 것"뿐이다.
파이프라인 맨 앞에서 한 번 교환하면 **그 뒤 로직은 어느 키보드인지 전혀 몰라도
된다** — `chord`도, `keymap`도, `specialKey`도 고칠 것이 없다.

이 milestone에서 아직 `true`를 넣어주는 사람은 없다(Task 4가 넣는다). 지금은
테스트가 유일한 독자다.

**Files:**
- Modify: `terminal/src/input_test.zig` (검사 추가)
- Modify: `terminal/src/input.zig` (`swapAltMeta`, `handleKey` 첫 줄)

- [ ] **Step 1: 실패하는 검사를 먼저 추가**

Task 2가 넣은 "── 여전히 안 하는 것 ──" 블록 **앞에** 넣는다.

```zig
    // ── keyboard=pc: Alt와 Meta를 맞바꾼다 (IP-M2, design doc 결정 9) ────
    //
    // 스페이스 옆 두 키의 순서가 Apple과 PC에서 정확히 뒤집혀 있다.
    //   Apple: [Ctrl] [Option 56] [Cmd 125]
    //   PC:    [Ctrl] [Win 125]   [Alt 56]
    // 그래서 하는 일은 modifier를 기록하기 **전에** 코드를 맞바꾸는 것뿐이고,
    // 그 뒤 로직(chord, keymap, specialKey)은 어느 키보드인지 전혀 모른다.
    //
    // 이 검사가 게이트보다 중요한 이유가 하나 있다: 게이트는 QEMU가 보내는
    // 물리 키 하나만 볼 수 있지만, 여기서는 네 키를 다 볼 수 있다.
    const pc = input.Context{ .swap_alt_meta = true };

    // 물리 Alt(56)를 누르면 Meta로 기록된다 → Cmd 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expectCtx(&state, pc, K.KEY_RIGHT, 1, "\x05");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");

    // 물리 Meta(125)를 누르면 Alt로 기록된다 → Option 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb"); // 0x01이 아니라 ESC b
    try expectCtx(&state, pc, K.KEY_BACKSPACE, 1, "\x1b\x7f");
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 0, "");

    // 오른쪽 짝(100↔126)도 같이 바뀐다. 왼쪽만 고치는 실수를 여기서 잡는다.
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01");
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 0, "");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 0, "");

    // 교환은 **modifier 키에만** 일어난다. 글자 키는 그대로다.
    try expectCtx(&state, pc, K.KEY_A, 1, "a");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1b[D");

    // 뗌 이벤트도 같은 ctx로 들어오므로 짝이 맞는다. 부팅 중에 keyboard
    // 설정이 바뀌는 일은 없다 — PID 1이 부팅 시점에 한 번 정해서 argv로
    // 넘기고, 그 값은 프로세스가 사는 동안 상수다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 아무 modifier도 안 남았다
```

- [ ] **Step 2: 실패하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: 첫 실패가 이것이다.

```
FAIL: code=105 value=1 ckm=false -> got={ 27, 98 }, want={ 1 }
```

`swap_alt_meta`를 아직 아무도 안 읽으니 물리 Alt가 그냥 Option으로 동작한다 —
`ESC b`(=`{27, 98}`)가 나왔다.

`ckm=false`만 찍히는 것이 아쉬우면 `expectCtx`의 진단 문자열에
`swap={}`을 덧붙여도 된다. **다만 이번 Task 안에서는 고치지 말고**, 실패를
보고 나서 Step 3과 함께 넣는다(진단 출력을 바꾸면 "무엇이 실패였는지"의
기준이 중간에 달라진다).

- [ ] **Step 3: `swapAltMeta`를 추가하고 `handleKey` 맨 앞에서 부른다**

`input.zig`의 `specialKey` 함수(`:124-137`) **뒤에** 넣는다.

```zig
/// PC 키보드 보정(design doc 결정 9). 스페이스 옆 두 키의 순서가 Apple과
/// 정확히 뒤집혀 있으므로 코드를 맞바꾼다.
///
/// **파이프라인의 맨 앞에서 한 번만 부른다.** 그러면 그 뒤 로직은 어느
/// 키보드인지 전혀 몰라도 된다 — chord도 keymap도 specialKey도 고칠 것이
/// 없다는 것이 이 자리를 고른 이유다. 뒤로 갈수록 "여기도 보정해야 하나"를
/// 물어야 하는 곳이 늘어난다.
///
/// 문자 키는 건드리지 않는다. 두 키보드에서 실제로 자리가 다른 것은 이 넷뿐이다.
fn swapAltMeta(code: u16) u16 {
    return switch (code) {
        c.KEY_LEFTALT => c.KEY_LEFTMETA,
        c.KEY_LEFTMETA => c.KEY_LEFTALT,
        c.KEY_RIGHTALT => c.KEY_RIGHTMETA,
        c.KEY_RIGHTMETA => c.KEY_RIGHTALT,
        else => code,
    };
}
```

그리고 `handleKey`의 시그니처와 첫 줄을 바꾼다. `input.zig:215-216`의

```zig
    pub fn handleKey(self: *State, code: u16, value: i32, ctx: Context) []const u8 {
        switch (code) {
```

을 이것으로.

```zig
    pub fn handleKey(self: *State, raw_code: u16, value: i32, ctx: Context) []const u8 {
        // 0번 단계 — 키보드 보정. modifier를 **기록하기 전에** 맞바꾼다.
        // 인자 이름을 raw_code로 바꾼 것은 실수를 막기 위해서다: 아래에서
        // 실수로 raw_code를 다시 쓰면 보정이 빠진 코드가 흘러가는데, 이름이
        // 다르면 그 실수가 눈에 띈다.
        const code = if (ctx.swap_alt_meta) swapAltMeta(raw_code) else raw_code;

        switch (code) {
```

- [ ] **Step 4: 통과 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test && ./prepare.sh"
```

기대: `PASS` + 빌드 성공.

**`error: unused function parameter`가 나오면** `raw_code`를 어디서도 안 쓴
것이 아니라 반대다 — Zig는 안 쓰는 인자를 에러로 낸다는 것을 IP-M1에서 배웠고,
여기서는 `raw_code`를 `const code` 계산에 쓰므로 걸릴 일이 없다. 그래도 나오면
`swapAltMeta` 호출이 빠진 것이다.

- [ ] **Step 5: Commit**

Claude가 수행한다. 커밋 메시지: `Let a PC keyboard swap its Alt and Meta keys`

---

## Task 4: 설정이 코드에 닿는다

`keyboard=pc` 한 줄이 `/config/tars.conf`에서 `Context.swap_alt_meta`까지
가는 길을 깐다. CP가 깔아둔 길을 **한 글자도 바꾸지 않고** 그대로 쓴다.

```
/config/tars.conf ──읽는 것은 PID 1 하나뿐──> init/src/config.zig
   shell=bash                                   Shell    enum (있음)
   keyboard=pc                                  Keyboard enum (추가)
                                                    │ argv로 흘려보낸다
                                                    ▼
   /terminal <셸 경로> <no-config 플래그> <keyboard>
                                                    │
                                                    ▼
                                       input.Context{ .swap_alt_meta = ... }
```

**`terminal`은 여전히 설정 파일을 읽지 않는다.** CP가 "파서가 두 벌이 되면 두
프로세스가 같은 파일에서 서로 다른 답을 얻을 수 있다"는 이유로 정한 원칙이고,
**이번이 그 구조가 두 번째 키에도 버티는지 보는 첫 시험이다.** 그래서
`terminal` 쪽에는 enum을 복사하지 않고 `"pc"` 문자열 비교 한 줄만 둔다.

**그리고 여기서 HANDOFF의 오래된 숙제 하나를 닫는다** — `config.zig`의 `parse`에
단위 테스트가 없다. 시스템 콜이 하나도 없는 순수 함수인데도 지금은 QEMU를 띄워야
검증된다. `keyboard` 키가 들어오면서 파서의 분기가 둘이 되는 지금이 그 기회다.

**Files:**
- Modify: `init/src/config.zig` (`Keyboard` enum, `Config`, `parse`, `save`, `pub fn parse`)
- Create: `init/src/config_test.zig`
- Modify: `init/build.zig` (host 타깃 + `test` step)
- Modify: `init/src/main.zig` (argv 넷째 자리, 로그)
- Modify: `terminal/src/main.zig` (`args[3]` 읽기, `Context`에 채우기)
- Modify: `config/check.sh`, `input/check.sh` (`zig build test` 호출)

- [ ] **Step 1: `Keyboard` enum과 `Config` 필드**

`init/src/config.zig:46`(`Shell` enum 닫는 `};`) **뒤에** 넣는다.

```zig

/// 물리 키보드 종류. **재배치가 아니라 하드웨어 선언이다** — 사용자가 키를
/// 임의로 옮기는 문이 아니라, "스페이스 옆 두 키가 어느 순서인가"라는 사실
/// 하나를 알려주는 것이다(design doc 비목표: 범용 키바인딩 엔진은 안 만든다).
///
/// Shell과 같은 화이트리스트 구조다. enum에 없는 이름은 파싱을 통과할 수
/// 없으므로 검사 목록을 따로 유지할 필요가 없다.
pub const Keyboard = enum {
    apple,
    pc,

    /// terminal에 argv로 넘길 문자열. @tagName은 sentinel이 없는 슬라이스를
    /// 주는데 execve의 argv는 널 종료 문자열이 필요하다 — Shell.path()가
    /// 경로를 [:0]const u8로 돌려주는 것과 같은 이유로 여기서 짝을 맞춘다.
    ///
    /// enum에 이름을 하나 더 넣으면 이 switch가 컴파일 에러를 내서
    /// 빠뜨릴 수 없다.
    pub fn arg(self: Keyboard) [:0]const u8 {
        return switch (self) {
            .apple => "apple",
            .pc => "pc",
        };
    }
};
```

그리고 `:49-51`의 `Config`를 이것으로.

```zig
/// 설정 전체. 필드의 기본값이 곧 "설정 파일이 없을 때의 TARS"다.
///
/// keyboard의 기본값이 apple인 이유는 이 기계를 쓰는 사람이 Apple 키보드를
/// 먼저 꽂기 때문이다. pc는 보정을 **켜는** 쪽이라 명시적으로 적어야 한다.
pub const Config = struct {
    shell: Shell = .fish,
    keyboard: Keyboard = .apple,
};
```

- [ ] **Step 2: `parse`를 공개하고 `keyboard` 갈래를 더한다**

`config.zig:109`의

```zig
fn parse(text: []const u8) Config {
```

을 이것으로(주석 문단은 그대로 두고 시그니처만).

```zig
/// **pub인 이유는 config_test.zig가 부르기 때문이다.** 이 파일에서 유일하게
/// 시스템 콜이 없는 함수이고, 그래서 유일하게 게스트를 띄우지 않고 검증할 수
/// 있는 부분이다 — IP-M2가 그 검사를 실제로 만들었다.
pub fn parse(text: []const u8) Config {
```

그리고 `:136-138`의

```zig
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

앞에 갈래를 하나 끼운다.

```zig
        } else if (std.mem.eql(u8, key, "keyboard")) {
            // shell과 완전히 같은 모양이다. 모르는 값은 로그만 남기고
            // 기본값(apple)에 머문다 — 설정 파일은 사용자가 손으로 고치는
            // 물건이라 깨진 입력이 예외가 아니라 규칙이다.
            c.keyboard = std.meta.stringToEnum(Keyboard, value) orelse {
                std.debug.print("tars-init: unknown keyboard '{s}', falling back to {s}\n", .{
                    value, @tagName(c.keyboard),
                });
                continue;
            };
        } else {
```

- [ ] **Step 3: 씨앗 파일에도 keyboard를 적는다**

`config.zig:160-165`의 `save` 안 템플릿을 이것으로.

```zig
    const text = std.fmt.bufPrint(&buf,
        \\# TARS configuration. Edit and reboot to apply.
        \\# shell: fish | bash | zsh
        \\shell={s}
        \\# keyboard: apple | pc
        \\#   apple = [Ctrl][Option][Cmd], pc = [Ctrl][Win][Alt]
        \\keyboard={s}
        \\
    , .{ @tagName(c.shell), @tagName(c.keyboard) }) catch return error.FormatFailed;
```

**여기서 `@tagName`을 쓰는 것은 맞다.** 파일에 적는 것은 널 종료가 필요 없는
바이트열이고, `arg()`는 execve용이다.

CP 체인이 이 변경에 걸리지 않는지 확인해 둔다. `config/check.sh`가 보는 것은
1차 부팅에서 사람이 `echo shell=zsh > /config/tars.conf`로 **덮어쓴** 파일의
되읽기(`| shell=zsh`)라, 씨앗 파일에 줄이 늘어도 그 검사는 그대로다. 2차
부팅은 그 덮어쓴 파일(=`shell=zsh` 한 줄)을 읽으므로 keyboard는 기본값 apple로
떨어진다 — 이것도 정상이다.

- [ ] **Step 4: 파서에 저울을 놓는다**

`init/src/config_test.zig`를 새로 만든다.

```zig
const std = @import("std");
const config = @import("config.zig");

/// config.zig에서 유일하게 시스템 콜이 없는 함수가 parse다. HANDOFF가
/// "단위 테스트가 없다"고 오래 적어두고 있었는데, keyboard 키가 들어오면서
/// 파서의 분기가 둘이 된 지금이 그 저울을 놓을 자리다.
///
/// terminal/src/input_test.zig와 같은 모양(호스트 아키텍처 실행 파일,
/// 실패하면 0이 아닌 종료 코드)으로 맞춘다 — 체인 스크립트가 둘을 똑같이
/// 다룰 수 있어야 한다.
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard) return;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s}\n  want shell={s} keyboard={s}\n",
        .{
            text,          @tagName(got.shell),  @tagName(got.keyboard),
            @tagName(want.shell), @tagName(want.keyboard),
        },
    );
    return error.UnexpectedConfig;
}

pub fn main() !void {
    // 빈 입력은 기본값이다. 이 한 줄이 "설정 파일이 없을 때의 TARS"를 못
    // 박는다 — Config의 기본값을 바꾸면 여기가 먼저 터진다.
    try expect("", .{});

    // 각 키 하나씩.
    try expect("shell=zsh\n", .{ .shell = .zsh });
    try expect("keyboard=pc\n", .{ .keyboard = .pc });

    // 둘이 함께. IP 체인의 2차 부팅이 실제로 쓰는 조합이다.
    try expect("shell=bash\nkeyboard=pc\n", .{ .shell = .bash, .keyboard = .pc });

    // 주석·빈 줄·양쪽 공백. 사람이 손으로 고치는 파일이라 이 셋이 규칙이다.
    try expect("# a comment\n\n  shell = zsh  \n", .{ .shell = .zsh });

    // CRLF. 호스트에서 편집한 파일을 넣었을 때 값이 "zsh\r"이 되면 원인을
    // 찾기 어렵다 — trim이 \r까지 떼는 이유다.
    try expect("shell=zsh\r\nkeyboard=pc\r\n", .{ .shell = .zsh, .keyboard = .pc });

    // 마지막 줄에 개행이 없어도 된다.
    try expect("keyboard=pc", .{ .keyboard = .pc });

    // ── 깨진 입력은 전부 기본값으로 떨어진다 ────────────────────────────
    //
    // 이것이 CP design doc의 "설정 하나로 부팅이 막히지 않게 하는 장치"다.
    // 어느 줄도 예외를 던지지 않고, 어느 줄도 부팅을 멈추지 않는다.
    try expect("shell=nushell\n", .{}); // enum에 없는 셸
    try expect("keyboard=dvorak\n", .{}); // enum에 없는 키보드
    try expect("colour=red\n", .{}); // 모르는 키
    try expect("no equals here\n", .{}); // '=' 없음
    try expect("=value\n", .{}); // 키 없음
    try expect("shell=\n", .{}); // 값 없음

    // shell=/etc/passwd 같은 입력이 애초에 성립하지 않는다는 것 —
    // 화이트리스트가 이름만 받고 경로를 안 받는다는 설계의 증거다.
    try expect("shell=/usr/bin/fish\n", .{});

    // 첫 번째 '='에서만 나눈다. 값 쪽에 '='가 남으면 enum에 없는 이름이 된다.
    try expect("shell=zsh=extra\n", .{});

    // 뒤에 오는 줄이 이긴다. "마지막이 이긴다"는 정책을 못 박아 둔다.
    try expect("shell=zsh\nshell=bash\n", .{ .shell = .bash });

    // 한 줄이 깨져도 나머지 줄은 살아남는다. 이 성질이 없으면 오타 하나가
    // 파일 전체를 무효로 만든다.
    try expect("shell=nope\nkeyboard=pc\n", .{ .keyboard = .pc });

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 5: `init/build.zig`에 호스트 타깃을 더한다**

`init/build.zig:31`의 `b.installArtifact(exe);` **뒤에** 넣는다.

```zig

    // ── 여기서부터는 게스트가 아니라 **빌드 호스트**가 실행한다 ──────────
    //
    // project_build_host_arch의 4번 규칙: "이 산출물은 누가 실행하는가"를
    // 먼저 묻는다. config_test는 QEMU 게스트가 아니라 컨테이너가 직접
    // 실행하므로 컨테이너의 아키텍처(arm64)로 빌드해야 한다. 위의 target
    // (x86_64-musl 고정)을 그대로 쓰면 빌드는 되지만 실행이 안 된다.
    //
    // 빈 쿼리 `.{}`가 네이티브다. config.zig는 std.os.linux만 쓰므로
    // 호스트에서도 libc 없이 그대로 컴파일된다.
    const host_target = b.resolveTargetQuery(.{});

    const config_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_test = b.addExecutable(.{
        .name = "config_test",
        .root_module = config_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
    // 부르는데, 그건 TF-M3 시절 손으로 ./zig-out/bin/input_test를 돌리던
    // 잔재다. 여기는 처음부터 `zig build test`로만 도므로 install할 이유가
    // 없고, 네 체인이 전부 부르는 `zig build`를 무겁게 하지 않는다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
```

- [ ] **Step 6: 저울이 실제로 도는지 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대:

```
PASS
```

**여기서 실패하면 그것이 이 Step의 값어치다.** `parse`가 처음으로 QEMU 없이
검증받는 자리이므로, IP-M2 이전부터 있던 버그가 지금 드러날 수 있다.
실패 줄(`got` / `want`)을 그대로 붙여 달라 — 고칠 곳이 테스트인지 파서인지
같이 판단한다.

**`error: 'parse' is not marked pub`이 나오면** Step 2가 빠진 것이다.

- [ ] **Step 7: 두 체인이 이 검사를 돌리게 한다**

`config/check.sh:17`의 init 빌드 블록 **뒤에** 넣는다.

```bash

# 호스트에서 도는 순수 로직 검사(config.zig의 parse). terminal/check.sh가
# input_test를 부팅 앞에서 돌리는 것과 같은 자리다 — 부팅 20초를 쓰기 전에
# 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: config_test failed"
  exit 1
fi
```

같은 블록을 `input/check.sh:29`의 init 빌드 뒤에도 넣는다. 두 체인에 같은
네 줄이 중복되지만, **각 체인이 단독으로 실행 가능해야 한다**는 이 저장소의
설계를 따른 것이다(마커 문자열이 중복되는 것과 같은 이유). IP-M2가
`keyboard=` 파싱을 더하므로 IP 체인도 자기 회귀를 스스로 잡아야 한다.

- [ ] **Step 8: PID 1이 keyboard를 argv로 흘려보낸다**

`init/src/main.zig:179`의

```zig
    argv: [3:null]?[*:0]const u8,
```

을 이것으로.

```zig
    /// IP-M2에서 셋에서 넷으로 늘었다. terminal이 받는 넷째 자리가
    /// keyboard이고, 콘솔 셸은 그 자리를 null로 둔다 — execve는 첫 null에서
    /// 멈추므로 인자 수가 다른 자식이 같은 배열 타입을 쓸 수 있다.
    argv: [4:null]?[*:0]const u8,
```

`:318`의 로그를 이것으로.

```zig
    std.debug.print("tars-init: config shell={s} keyboard={s}\n", .{
        @tagName(cfg.shell), @tagName(cfg.keyboard),
    });
```

**CP 체인이 `grep "tars-init: config shell=fish"`와 `"...shell=zsh"`를 보는데,
둘 다 접두사 일치라 그대로 통과한다.** 뒤에 붙는 것이라 안전하다.

`:325-327` 뒤에 한 줄을 더한다.

```zig
    const shell = resolveShell(cfg.shell);
    const shell_path = shell.path();
    const shell_flag = shell.noConfigFlag();
    // 셸과 달리 폴백 검사(resolveShell 같은 것)가 없다. 키보드 종류는
    // 파일시스템에 존재를 확인할 대상이 아니고, enum이 이미 화이트리스트다.
    const keyboard_arg = cfg.keyboard.arg();
```

`:336`과 `:343`의 argv를 넷으로.

```zig
            // terminal은 설정 파일을 읽지 않는다. 어느 셸을 PTY에 띄울지와
            // 어느 키보드인지를 PID 1이 정해서 인자로 넘긴다 — 파서가 두
            // 벌이 되면 두 프로세스가 서로 다른 답을 얻을 수 있다.
            //
            // 넷째 자리를 쓰는 것이 안전한 이유는 terminal이 셸에 넘기는
            // argv를 {shell_path, shell_flag} 둘로 따로 조립하기 때문이다 —
            // 이 인자는 셸로 새지 않는다.
            .argv = .{ TERMINAL_PATH.ptr, shell_path.ptr, shell_flag.ptr, keyboard_arg.ptr },
```

```zig
            .argv = .{ shell_path.ptr, null, null, null },
```

- [ ] **Step 9: `terminal`이 그 값을 읽어 `Context`에 채운다**

`terminal/src/main.zig:119` 뒤(`shell_flag` 정의 뒤)에 넣는다.

```zig
    // 넷째 인자가 키보드 종류다(IP-M2, design doc 결정 9). enum을 여기 다시
    // 정의하지 않고 문자열 하나만 비교하는 것이 요점이다 — CP가 정한
    // "파서는 한 벌"을 지킨다. init이 enum으로 이미 걸렀으므로 여기 도착하는
    // 값은 apple 아니면 pc이고, 그 외 무엇이 오더라도 apple로 떨어진다.
    const keyboard: [*:0]const u8 = if (args.len > 3) args[3] else "apple";
    const swap_alt_meta = std.mem.eql(u8, std.mem.span(keyboard), "pc");
```

그리고 `:144-146`의 spawn 로그 **뒤에** 한 줄을 더한다.

```zig
    // 게이트가 "설정이 여기까지 왔는가"를 볼 수 있는 유일한 줄이다.
    // 이 값이 실제로 무슨 일을 하는지는 화면으로만 증명되지만(input/check.sh의
    // 2차 부팅), 그 화면이 틀렸을 때 "설정이 안 왔다"와 "설정은 왔는데 뜻이
    // 틀렸다"를 가르는 것이 이 줄이다.
    std.debug.print("terminal: keyboard={s} (swap_alt_meta={})\n", .{
        keyboard, swap_alt_meta,
    });
```

마지막으로 `:174-176`의 `Context`에 채운다.

```zig
            const ctx = input.Context{
                .cursor_keys = screen.term.modes.get(.cursor_keys),
                // DECCKM과 달리 이 값은 부팅 내내 상수다. 매 키마다 다시
                // 넣는 것은 Context를 한 자리에서 조립하기 위해서일 뿐이다.
                .swap_alt_meta = swap_alt_meta,
            };
```

- [ ] **Step 10: 빌드와 기존 체인 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd init && zig build && zig build test && cd ../terminal && ./prepare.sh && zig build test"
```

기대: 에러 없이 끝나고 `PASS` 두 번.

이어서 **CP 체인이 안 깨졌는지** 본다. argv 배열의 길이와 init의 로그 형식을
동시에 바꿨으므로 여기가 가장 위험한 자리다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash config/check.sh
```

기대: `PASS`, 그리고 `--- init log (boot 2) ---` 아래에
`tars-init: config shell=zsh keyboard=apple`이 보인다.

**깨진다면 구분할 것이 둘이다.**

- `MISSING tars-init: config shell=` → 로그 형식을 잘못 고쳤다.
- `terminal: spawned child pid` 이후가 없다 → argv 배열이 잘못됐다.
  `[4:null]`인데 원소를 셋만 넣었거나, sentinel이 빠졌다.

- [ ] **Step 11: Commit**

Claude가 수행한다. 커밋 메시지:
`Carry the keyboard kind from the config file to the terminal`

---

## Task 5: 게이트가 bash 프롬프트에서 Option과 Cmd를 증명한다

부팅은 아직 **한 번**이다. IP-M1 게이트가 방향키 검사를 끝낸 그 자리에서
이어서 친다.

**bash로 들어가는 이유**는 design doc 위험 2다. 결정 8의 표는 readline과 zle의
문서로 확실하지만 fish는 자체 에디터라 기본 바인딩이 어긋날 수 있다. `PATH`가
없으므로 `/usr/bin/bash`로 쳐야 한다(`project_guest_environment`).

**게이트가 헛되게 통과하지 않게 하는 장치를 이번에도 넣는다.** IP-M0의
`notdead`, IP-M1의 `abcX`와 같은 종류이고, 이번에는 **실패 모양이 둘**이라
음성 검사도 둘이다.

```
echo aa bb  치고 → Option+← → X → Enter

  제대로 동작    → echo aa Xbb → 출력 행 "aa Xbb"
  아무것도 안 감 → echo aa bbX → 출력 행 "aa bbX"
  맨 ←가 샜다    → echo aa bXb → 출력 행 "aa bXb"   ← IP-M1의 현재 동작
```

세 번째가 특히 중요하다. **IP-M1까지 `Option+←`는 실제로 맨 `←`를 보내고
있었다**(HANDOFF "알아둘 것 4"). 그 상태와 구분되지 않으면 이 게이트는
아무것도 증명하지 않는다.

**`Cmd+←`는 방향을 뒤집어서 검사한다.** 줄 처음으로 가는 것을 증명하려면
"줄 처음에 무언가를 끼워 넣고 그것이 명령이 되는 것"을 보는 편이 낫다.

```
cc dd  치고 → Cmd+← → "echo " 치고 → Enter

  제대로 동작 → echo cc dd  → 출력 행 "cc dd"
  실패        → cc ddecho   → bash: cc: command not found
```

성공 경로가 하나뿐이다. 출력 행의 첫머리가 `cc dd`가 되려면 `echo`가 줄
**맨 앞**에 들어가는 수밖에 없다.

**Files:**
- Modify: `input/check.sh` (검사 셋 추가)

- [ ] **Step 1: 방향키 검사 뒤에 bash 진입을 붙인다**

`input/check.sh:274`(`echo "the arrow keys moved the cursor inside the line"`)
**뒤에** 넣는다. 단, `:261-266`의 monitor 닫기 + QEMU 죽이기 블록을 **아래로
미뤄야 한다** — 아직 더 칠 것이 있다. `:261-266`을 잘라내서 이 Task가 넣는
검사들 뒤로 옮긴다.

```bash

# ── 7) bash로 들어간다 (IP-M2) ────────────────────────────────────────
# 결정 8의 표는 readline과 zle의 문서로 확실하지만 fish는 자체 에디터라
# 기본 바인딩이 어긋날 수 있다(design doc 위험 2). 그래서 macOS 의미론
# 검사는 readline 지형에서 한다.
#
# 절대 경로인 이유는 PATH다. 커널의 envp_init은 HOME과 TERM 둘뿐이다
# (docs/decisions/project_guest_environment.md).
#
# --norc를 주는 이유는 다른 셸에 no-config 플래그를 주는 이유와 같다 —
# 프롬프트가 예측 가능해야 화면을 검사할 수 있다. initrd에 /.bashrc가
# 없어서 지금은 있으나 없으나 같지만, 생기는 날 조용히 달라지지 않는다.
echo "=== typing '/usr/bin/bash --norc' ==="
type_keys slash u s r slash b i n slash b a s h spc minus minus n o r c ret

# bash가 정말 떴는지. --norc로 뜬 bash의 기본 PS1은 `\s-\v\$`라 화면에
# `bash-5.2$` 같은 프롬프트가 그려진다. 방금 타이핑한 명령줄 행에는
# `bash `까지만 있고 `bash-`는 없으므로 이 패턴은 프롬프트만 잡는다.
#
# 시리얼 로그에도 bash 프롬프트가 있을 수 있지만(콘솔 셸), 패턴이
# `terminal: screen>`로 시작하므로 화면 덤프만 본다.
BASH_OK=0
for _ in $(seq 1 20); do
  if grep -q "terminal: screen>.*bash-" "$LOG"; then BASH_OK=1; break; fi
  sleep 1
done
if [ "$BASH_OK" != "1" ]; then
  report_failure "bash never drew a prompt inside the pty (is /usr/bin/bash in the initrd?)"
fi
echo "the pty shell is now bash (readline territory)"

# ── 8) Option+← = 단어 단위 왼쪽 이동 (design doc 결정 8) ──────────────
# `echo aa bb`를 친 뒤 Option+←로 단어 하나를 건너뛰고 X를 끼운다.
#
#   제대로 동작    → echo aa Xbb → 출력 행 "aa Xbb"
#   아무것도 안 감 → echo aa bbX → 출력 행 "aa bbX"
#   맨 ←가 샜다    → echo aa bXb → 출력 행 "aa bXb"
#
# 세 번째가 이 검사의 핵심이다. **IP-M1까지 Option+←는 실제로 맨 ←를
# 보내고 있었다** — Alt가 modifier로 추적되지도 않았기 때문이다. 그
# 상태와 구분되지 않으면 이 게이트는 아무것도 증명하지 않는다
# (docs/decisions/project_gate_chain_composition.md).
echo "=== typing 'echo aa bb', then alt-left X ==="
type_keys e c h o spc a a spc b b
type_keys alt-left
type_keys shift-x
type_keys ret

OPT_OK=0
OPT_NOTHING=0
OPT_PLAIN=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| aa Xbb" "$LOG"; then OPT_OK=1; break; fi
  if grep -q "terminal: screen>.*| aa bbX" "$LOG"; then OPT_NOTHING=1; break; fi
  if grep -q "terminal: screen>.*| aa bXb" "$LOG"; then OPT_PLAIN=1; break; fi
  sleep 1
done
if [ "$OPT_NOTHING" = "1" ]; then
  report_failure "alt-left produced nothing: the line ran as 'echo aa bbX'"
fi
if [ "$OPT_PLAIN" = "1" ]; then
  report_failure "alt-left leaked a bare arrow key: the line ran as 'echo aa bXb' (the chord dispatch did not intercept it)"
fi
if [ "$OPT_OK" != "1" ]; then
  report_failure "none of 'aa Xbb' / 'aa bbX' / 'aa bXb' appeared: the cursor went somewhere unexpected"
fi
echo "option+left moved the cursor by a word"

# 부수적이지만 결정적인 증거 하나. main.zig가 매 키마다 바이트 수를 찍는데,
# 이번 범위에서 **2바이트를 만드는 것은 Option 조합뿐**이다(맨 방향키는 3,
# 평문은 1). 그래서 이 한 줄이 "ESC b 경로를 실제로 밟았다"를 말한다.
if ! grep -q "terminal: key> 2 byte(s)" "$LOG"; then
  report_failure "the screen looks right but no 2-byte sequence was ever sent; something else moved the cursor"
fi

# ── 9) Cmd+← = 줄 처음으로 ────────────────────────────────────────────
# 방향을 뒤집어서 검사한다. 줄 처음에 `echo `를 끼워 넣어 그것이 명령이
# 되는 것을 본다 — 출력 행의 첫머리가 "cc dd"가 되려면 echo가 줄 **맨
# 앞**에 들어가는 수밖에 없으므로 성공 경로가 하나뿐이다.
#
#   제대로 동작 → echo cc dd → 출력 행 "cc dd"
#   실패        → cc ddecho  → bash: cc: command not found
echo "=== typing 'cc dd', then meta_l-left 'echo ' ==="
type_keys c c spc d d
type_keys meta_l-left
type_keys e c h o spc
type_keys ret

CMD_OK=0
CMD_FAILED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| cc dd" "$LOG"; then CMD_OK=1; break; fi
  if grep -q "terminal: screen>.*command not found" "$LOG"; then CMD_FAILED=1; break; fi
  sleep 1
done
if [ "$CMD_FAILED" = "1" ]; then
  report_failure "meta_l-left did not reach the start of the line; bash tried to run 'cc' (does QEMU sendkey meta_l arrive as KEY_LEFTMETA?)"
fi
if [ "$CMD_OK" != "1" ]; then
  report_failure "'cc dd' never appeared as an output row after meta_l-left"
fi
echo "cmd+left jumped to the beginning of the line"
```

그리고 여기 **뒤에** 아까 잘라낸 블록을 붙인다.

```bash

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""
```

- [ ] **Step 2: 1차 부팅이 기본값으로 떴는지도 확인한다**

`input/check.sh`의 DECCKM 관측 블록(`:276-284`) **뒤에** 넣는다.

```bash

# 디스크를 안 물었으므로 /config mount가 실패하고 설정은 전부 기본값이다.
# 이 줄이 그것을 못 박는다 — 2차 부팅의 keyboard=pc와 대조군이 된다.
if ! grep -q "tars-init: config shell=fish keyboard=apple" "$LOG"; then
  report_failure "the diskless boot did not fall back to the default config"
fi
if ! grep -q "terminal: keyboard=apple (swap_alt_meta=false)" "$LOG"; then
  report_failure "the terminal did not receive keyboard=apple on its argv"
fi
```

`report_failure`의 마커 목록(`:98-104`)에도 한 줄 더한다. `"TERM"` 뒤에:

```bash
    "TERM" \
    "terminal: keyboard="; do
```

- [ ] **Step 3: IP 체인을 단독으로 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash input/check.sh
```

기대: 맨 끝에 `PASS`, 그 앞에 이 줄들이 순서대로.

```
the foreground child is blocking the shell
ctrl-c killed the foreground child and the shell came back
TERM is xterm inside the pty shell
the arrow keys moved the cursor inside the line
the pty shell is now bash (readline territory)
option+left moved the cursor by a word
cmd+left jumped to the beginning of the line
DECCKM ...
```

**DECCKM 줄을 눈여겨볼 것.** HANDOFF의 "알아둘 것 1"이 적었듯이, bash의
readline은 fish와 달리 `smkx`를 보낼 수 있다. `DECCKM was on`이 처음으로
찍히면 design doc 위험 4가 해소된 것이다 — 그 경우 **방향키 검사(6번)는
여전히 fish 아래에서 돌았으므로 통과하고**, bash로 들어간 뒤의 검사만
`ESC O` 지형이 된다. Option/Cmd 조합은 dispatch가 먼저 가로채므로 DECCKM에
흔들리지 않는다(Task 2의 테스트가 그것을 못 박았다).

**실패하면 구분할 것이 다섯이다.**

- `bash never drew a prompt` → 타이핑이 틀렸거나 bash가 initrd에 없다.
  화면 덤프의 명령줄 행을 보면 무엇이 찍혔는지 바로 보인다. `minus`가
  QEMU에서 다른 이름일 가능성도 여기서 드러난다.
- `alt-left leaked a bare arrow key` → **`chord`가 안 불렸다.** dispatch가
  `specialKey` 뒤에 있거나, `KEY_LEFTALT` 갈래가 modifier switch에 안 들어갔다.
  `terminal: key>` 줄의 바이트 수가 3이면 확정이다.
- `alt-left produced nothing` → Alt는 추적됐는데 `chord`가 null을 돌려줬다.
  `c.KEY_LEFT`를 `c.KEY_LEFTALT`로 잘못 적는 종류의 실수다.
- `meta_l-left did not reach the start of the line` → **design doc 위험 1이
  현실이 됐을 가능성이 가장 크다.** QEMU `sendkey meta_l`이 게스트에
  `KEY_LEFTMETA`로 도달하지 않는 것이다. 확인 방법: `terminal: key>` 줄에서
  그 시점의 바이트 수가 **1**이면 도달한 것이고(0x01을 보냈다), **3**이면
  Meta가 통째로 사라지고 맨 ←만 온 것이다. 후자라면 우회가 있다 — 이 검사를
  Task 6(2차 부팅, `keyboard=pc`)으로 옮기고 `alt-left`로 치면 된다.
  `pc`에서는 물리 Alt가 Cmd 의미를 갖기 때문이다.
- `the screen looks right but no 2-byte sequence` → 화면은 맞는데 우리가 안
  보냈다는 뜻이다. 셸이 스스로 뭔가 한 것이므로 검사 자체를 다시 봐야 한다.

- [ ] **Step 4: Commit**

Claude가 수행한다. 커밋 메시지:
`Prove Option and Command editing at a bash prompt`

---

## Task 6: 게이트가 PC 키보드로 한 번 더 부팅한다

design doc 목표 5(`keyboard=apple|pc`가 보정을 켜고 끈다)를 게이트가 실제로
증명하게 한다. 디스크가 없으면 설정은 영원히 `apple`이라 `pc` 경로를 한 번도
밟지 못한다 — 그 이유와 결정 11을 조정한 근거는 이 문서 앞의 "설계에서 조정한
것"에 적었다.

**2차 부팅의 디스크에는 두 줄이 미리 들어 있다.**

```
shell=bash
keyboard=pc
```

`shell=bash`를 함께 심는 이유가 둘이다. (1) PTY 셸이 처음부터 bash라 1차
부팅처럼 21키를 쳐서 들어갈 필요가 없다. (2) 한 파일에서 **두 키가 함께**
파싱되는 것이 확인된다 — `config_test`가 호스트에서 보는 것과 같은 조합을
게스트가 실제로 밟는다.

**검사 둘 다 "1차 부팅과 정반대"라는 모양이다.**

| | 1차 (apple) | 2차 (pc) |
|---|---|---|
| `alt-left` | 단어 이동(`ESC b`) | **줄 처음(`0x01`)** |
| `meta_l-left` | 줄 처음(`0x01`) | **단어 이동(`ESC b`)** |

둘을 다 검사하는 이유는 "swap이 정말 교환인가"를 보기 위해서다. 한쪽만 보면
"Alt를 Cmd로 바꿨을 뿐 Meta는 그대로"인 구현도 통과한다.

**Files:**
- Create: `input/make_disk.sh`
- Rewrite: `input/check.sh` (부팅 구조가 바뀐다 — `/tmp` 경로)

- [ ] **Step 1: 내용이 든 디스크를 굽는 스크립트**

`input/make_disk.sh`를 새로 만든다.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# IP 체인 2차 부팅용 설정 디스크.
#
# CP의 make_disk.sh와 다른 점은 **빈 파일시스템이 아니라 내용이 든 것을
# 굽는다**는 것뿐이다. CP는 "빈 디스크로 첫 부팅 → init이 씨앗을 심는다 →
# 사람이 게스트 안에서 고친다 → 다시 부팅해서 읽는다"를 증명해야 해서 그
# 네 단계를 다 밟아야 했지만, IP가 증명할 것은 "이 값이 키 해석을 바꾸는가"
# 하나다. 이미 든 파일을 읽기만 하면 되므로 부팅 한 번과 sendkey 25개로 끝난다.
#
# mkfs.ext2의 -d는 디렉터리 하나를 파일시스템 루트로 채워 넣는다
# (e2fsprogs 1.43+). 이것이 없었다면 CP처럼 부팅해서 타이핑하는 수밖에
# 없었고, 이 체인이 부팅 셋을 써야 했다.
SIZE=16M
IMG=../out/input.img

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "설정이 정말 이
# 파일에서 왔는가"가 흐려진다 — CP가 같은 이유로 매번 새로 굽는다.
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# IP 체인이 미리 심어 두는 설정. 게스트는 이 파일을 읽기만 한다.
#
# shell=bash  — PTY 셸을 처음부터 readline 지형으로 띄운다. design doc
#               위험 2가 "fish 바인딩은 미검증이니 bash에서 검사하라"고 했다.
# keyboard=pc — 이 한 줄이 Alt와 Meta를 맞바꾼다(design doc 결정 9).
shell=bash
keyboard=pc
EOF

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-input -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, shell=bash keyboard=pc)"
```

실행 권한을 준다.

```bash
chmod +x input/make_disk.sh
```

- [ ] **Step 2: 디스크가 제대로 구워지는지 먼저 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/input \
  tars-devcontainer bash -c "./make_disk.sh && debugfs -R 'cat tars.conf' ../out/input.img 2>/dev/null"
```

기대: 방금 심은 파일 내용이 그대로 나온다.

```
# IP 체인이 미리 심어 두는 설정. ...
shell=bash
keyboard=pc
```

**`mkfs.ext2: invalid option -- 'd'`가 나오면** 컨테이너의 e2fsprogs가 너무
오래된 것이다(1.43 미만). 그 경우 우회는 CP 방식 — 빈 디스크로 부팅해서
게스트 안에서 `echo keyboard=pc > /config/tars.conf`를 치고 재부팅하는
것인데, 부팅이 셋으로 늘어난다. 알려 달라.

**`debugfs`가 없으면** 그 확인만 건너뛴다. 2차 부팅의
`tars-init: loaded /config/tars.conf` 로그가 같은 것을 말해준다.

- [ ] **Step 3: `input/check.sh`를 두 부팅 구조로 바꾼다**

**`/tmp` 경로를 쓴다.** 부팅 하나를 붙이면서 QEMU 실행 블록을 함수로 뽑고
로그 파일이 둘이 되므로 100줄을 넘는다. Claude가 `/tmp/input_check.sh`를
만들어 두면 사용자가 이렇게 한다.

```bash
cp /tmp/input_check.sh input/check.sh
diff /tmp/input_check.sh input/check.sh && echo "identical"
chmod +x input/check.sh
```

구조 변경은 셋이다. **검사 내용은 한 줄도 바뀌지 않는다.**

1. **로그가 둘이 된다.** `LOG1`/`LOG2`를 만들고 `LOG`가 "지금 보고 있는
   로그"를 가리킨다. `report_failure`를 비롯한 기존 호출부를 **하나도 안
   고치고** 두 번째 부팅을 붙이는 가장 작은 변경이다.

   ```bash
   LOG1="$(mktemp)"
   LOG2="$(mktemp)"
   # 아래 검사들은 전부 $LOG를 본다. 부팅이 둘이 되면서 이 변수가 "지금
   # 보고 있는 로그"를 가리키게 했다 — 2차 부팅 앞에서 LOG="$LOG2" 한 줄만
   # 놓으면 되고, report_failure는 언제나 현재 부팅의 로그를 보여준다.
   LOG="$LOG1"
   ```

2. **QEMU 실행 + 프롬프트 대기 + monitor 연결을 함수로 뽑는다.** 두 부팅이
   같은 일을 하고 2차만 `-drive`가 붙기 때문이다.

   ```bash
   # 게스트를 띄우고 프롬프트가 그려질 때까지 기다린 뒤 monitor를 연결한다.
   # $1 = 시리얼 로그, 나머지 = 추가 QEMU 인자(2차 부팅의 -drive).
   #
   # "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev
   # 열기 + 셸 spawn + 첫 렌더가 전부 끝났다는 신호다(TF/CP와 같은 신호).
   start_guest() {
     local log="$1"; shift
     qemu-system-x86_64 \
       -kernel ../kernel/build/arch/x86/boot/bzImage \
       -initrd ../kernel/initrd.cpio \
       -append "console=ttyS0" \
       -vga none \
       -device virtio-gpu-pci \
       -display none \
       -serial file:"$log" \
       -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
       -no-reboot "$@" &
     QEMU_PID=$!

     local ready=0
     for _ in $(seq 1 120); do
       if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
       if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
       sleep 1
     done
     if [ "$ready" != "1" ]; then
       report_failure "terminal never rendered a prompt; there was nothing to type into"
     fi
     sleep 1

     local connected=0
     for _ in $(seq 1 20); do
       if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
       sleep 0.5
     done
     if [ "$connected" != "1" ]; then
       report_failure "could not connect to QEMU monitor on port ${MONITOR_PORT}"
     fi
   }

   # monitor를 닫고 QEMU를 확실히 끝낸다. 2차 부팅이 같은 monitor 포트를
   # 다시 열기 때문에 wait까지 한다 — 죽다 만 QEMU가 남아 있으면 2차의
   # sendkey가 어디로 가는지 알 수 없다.
   stop_guest() {
     exec 3<&-
     exec 3>&-
     kill "$QEMU_PID" 2>/dev/null
     wait "$QEMU_PID" 2>/dev/null
     QEMU_PID=""
   }
   ```

3. **1차 부팅 끝에 `stop_guest`를 부르고, 2차 블록을 붙인다.**

- [ ] **Step 4: 2차 부팅 블록의 내용**

1차 부팅의 마지막 검사(`terminal: keyboard=apple`)와 init 로그 출력 뒤에
붙는다.

```bash
# ══════════════════════════════════════════════════════ 2차 부팅 (keyboard=pc)
#
# 여기서 증명하는 것은 design doc 목표 5다 — /config/tars.conf의 한 줄이
# Alt와 Meta의 의미를 맞바꾼다. 1차 부팅은 디스크가 없어 설정이 언제나
# 기본값(apple)이라, 이 경로를 밟을 방법이 구조적으로 없었다
# (docs/decisions/project_gate_chain_composition.md의 "게이트가 구조적으로
# 밟을 수 없는 경로"). DECCKM과 달리 이건 **우리가 켤 수 있는 것**이므로
# 부팅을 하나 더 붙였다.
#
# 두 검사는 1차 부팅과 정확히 반대 모양이다.
#     alt-left     : 1차 = 단어 이동 → 2차 = 줄 처음
#     meta_l-left  : 1차 = 줄 처음   → 2차 = 단어 이동
# 둘 다 보는 이유는 "정말 교환인가"를 보기 위해서다. 한쪽만 보면 "Alt를
# Cmd로 바꿨을 뿐 Meta는 그대로"인 구현도 통과한다.
echo "=== boot 2/2: same kernel, a disk that says keyboard=pc ==="

if ! ./make_disk.sh; then
  echo "FAIL: input disk image build failed"
  exit 1
fi

LOG="$LOG2"
start_guest "$LOG" -drive file="${REPO_ROOT}/out/input.img",if=virtio,format=raw

# 설정이 파일 → PID 1 → argv → terminal로 흘렀는지를 로그 두 줄로 본다.
# 화면 검사가 실패했을 때 "설정이 안 왔다"와 "설정은 왔는데 뜻이 틀렸다"를
# 가르는 것이 이 둘이다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG"; then
  report_failure "the second boot did not load /config/tars.conf (did the disk attach?)"
fi
if ! grep -q "tars-init: config shell=bash keyboard=pc" "$LOG"; then
  report_failure "the second boot did not parse both keys out of the config file"
fi
if ! grep -q "terminal: keyboard=pc (swap_alt_meta=true)" "$LOG"; then
  report_failure "the terminal did not receive keyboard=pc on its argv"
fi
if ! grep -q "terminal: spawned child pid .*(/usr/bin/bash)" "$LOG"; then
  report_failure "the pty shell is not bash on the second boot"
fi
echo "boot 2: the config on disk selected bash and a pc keyboard"

# ── 10) pc에서 alt-left는 Cmd 의미(줄 처음)다 ─────────────────────────
# 1차 부팅에서 이 키는 단어 이동이었다. 같은 물리 키가 반대로 동작하는
# 것이 곧 교환의 증거다.
#
#   swap 동작   → echo gg hh → 출력 행 "gg hh"
#   swap 안 됨  → gg echo hh → bash: gg: command not found
echo "=== typing 'gg hh', then alt-left 'echo ' ==="
type_keys g g spc h h
type_keys alt-left
type_keys e c h o spc
type_keys ret

PC_CMD_OK=0
PC_CMD_FAILED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| gg hh" "$LOG"; then PC_CMD_OK=1; break; fi
  if grep -q "terminal: screen>.*command not found" "$LOG"; then PC_CMD_FAILED=1; break; fi
  sleep 1
done
if [ "$PC_CMD_FAILED" = "1" ]; then
  report_failure "alt-left still moved by a word on a pc keyboard; the swap did not happen"
fi
if [ "$PC_CMD_OK" != "1" ]; then
  report_failure "'gg hh' never appeared as an output row after alt-left"
fi
echo "on a pc keyboard, alt+left means beginning-of-line"

# ── 11) pc에서 meta_l-left는 Option 의미(단어 이동)다 ─────────────────
#   swap 동작   → echo ii Xjj → 출력 행 "ii Xjj"
#   swap 안 됨  → Xecho ii jj → bash: Xecho: command not found
#   맨 ←가 샜다 → echo ii jXj → 출력 행 "ii jXj"
echo "=== typing 'echo ii jj', then meta_l-left X ==="
type_keys e c h o spc i i spc j j
type_keys meta_l-left
type_keys shift-x
type_keys ret

PC_OPT_OK=0
PC_OPT_PLAIN=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| ii Xjj" "$LOG"; then PC_OPT_OK=1; break; fi
  if grep -q "terminal: screen>.*| ii jXj" "$LOG"; then PC_OPT_PLAIN=1; break; fi
  sleep 1
done

stop_guest

if [ "$PC_OPT_PLAIN" = "1" ]; then
  report_failure "meta_l-left leaked a bare arrow key on the second boot"
fi
if [ "$PC_OPT_OK" != "1" ]; then
  report_failure "meta_l-left did not move by a word on a pc keyboard; the swap is one-way, not a swap"
fi
echo "on a pc keyboard, meta+left means backward-word"

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "kernel panicked because PID 1 exited on the second boot"
fi

echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG" || true
```

`REPO_ROOT`는 `config/check.sh:6`처럼 파일 앞부분에서 잡는다.

```bash
REPO_ROOT="$(cd .. && pwd)"
```

- [ ] **Step 5: IP 체인 단독 실행**

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash input/check.sh
```

기대: `PASS`. 1차 부팅의 일곱 줄 뒤에 이 넷이 더 나온다.

```
boot 2: the config on disk selected bash and a pc keyboard
on a pc keyboard, alt+left means beginning-of-line
on a pc keyboard, meta+left means backward-word
```

**시간을 기록해 달라.** IP-M1의 이 체인은 단독으로 ~1분대였고, 2차 부팅이
붙으면서 부팅 1회(~4초) + sendkey 25개(~7.5초) + 대기가 는다.

**실패하면 구분할 것이 넷이다.**

- `did not load /config/tars.conf` → 디스크가 안 붙었다. `-drive` 경로와
  `${REPO_ROOT}/out/input.img`가 실제로 있는지 본다. 커널 로그에 `[vda]`가
  있는지도 함께 본다(CP 체인이 같은 것을 검사한다).
- `did not parse both keys` → `config_test`가 통과했는데 게스트가 다르게
  읽었다면 파일 내용이 예상과 다른 것이다. `debugfs -R 'cat tars.conf'`로
  다시 본다.
- `alt-left still moved by a word` → swap이 안 걸렸다. `terminal: keyboard=pc
  (swap_alt_meta=true)` 줄이 있는데도 이러면 `handleKey`의 0번 단계가
  빠졌거나 `Context`에 안 채워진 것이다.
- `the swap is one-way, not a swap` → `KEY_LEFTMETA → KEY_LEFTALT` 방향만
  빠진 것이다. `swapAltMeta`의 네 갈래를 다시 본다.

- [ ] **Step 6: Commit**

Claude가 수행한다. 커밋 메시지:
`Boot the gate a second time with a PC keyboard`

---

## Task 7: 루트 게이트 전체

**Files:**
- Modify: `check.sh:44-62`

- [ ] **Step 1: 체인 이름과 주석을 갱신**

`check.sh:62`의

```bash
run_chain "IP-M1" ./input/check.sh
```

를

```bash
run_chain "IP-M2" ./input/check.sh
```

로 바꾸고, 그 위 IP 문단(`:56-61`)을 이것으로 바꾼다.

```bash
# IP 체인은 키보드 입력 정책을 본다. CP처럼 monitor sendkey로 게스트에
# 타이핑한다.
#
# IP-M2부터 이 체인도 회차당 QEMU를 **두 번** 띄운다. 1차는 디스크 없이
# 떠서 Ctrl+C · TERM · 방향키 · Option/Cmd를 보고, 2차는 keyboard=pc가 이미
# 적힌 디스크를 물고 떠서 그 한 줄이 Alt와 Meta를 맞바꾸는 것을 본다.
# 부팅을 하나 더 붙인 이유는 디스크가 없으면 설정이 영원히 기본값(apple)이라
# pc 경로를 **구조적으로** 밟을 수 없기 때문이다 — 게이트가 못 보는 것은
# 게이트가 통과시킨다.
#
# 그래서 루트 게이트 한 번의 총 부팅 횟수는 15회에서 18회가 된다.
# 이 체인에서 비싼 쪽은 부팅(~4초)이 아니라 타이핑(글자당 0.3초)이다.
```

- [ ] **Step 2: 전체 게이트 (오래 걸린다 — 23분 안팎)**

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

기대: 마지막 줄이
`TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**측정값을 기록해 달라** — IP-M1이 20분 37초였다. 늘어난 분량의 예상 내역은
회차당 (부팅 1회 ≈ 4초 + 대기 ≈ 8초 + sendkey 71개 × 0.3초 ≈ 21초) ≈ 33초,
3회면 ≈ 100초다. **22~23분이면 예상대로이고, 26분을 넘으면 따로 봐야 한다** —
그 경우 첫 손잡이는 `type_keys`의 `sleep 0.3`이다(design doc 위험 5).

- [ ] **Step 3: Commit + push**

Claude가 수행한다. 커밋 메시지: `Retarget the aggregate gate at IP-M2`

---

## 완료 조건

- [ ] `keymap`이 밀리면 **컴파일이 막힌다**(일부러 깨뜨려 확인했다)
- [ ] `input_test`가 evdev 코드를 커널의 이름(`K.KEY_LEFT`)으로 쓴다
- [ ] modifier 여덟 개가 전부 좌우 독립으로 추적된다
- [ ] `Option+←/→/BS/Del`이 `ESC b`/`ESC f`/`ESC 0x7F`/`ESC d`를 보낸다
- [ ] `Cmd+←/→/BS`가 `0x01`/`0x05`/`0x15`를 보낸다
- [ ] 표에 없는 조합(`Option+b`, `Cmd+C`)은 modifier를 무시하고 원래 키를 보낸다
- [ ] 조합 dispatch가 특수키 조회보다 **먼저** 온다(DECCKM이 켜져도 `ESC b`)
- [ ] `swap_alt_meta`가 56↔125, 100↔126을 **양방향으로** 맞바꾼다
- [ ] `config.zig`에 `Keyboard` enum이 있고 `parse`에 단위 검사가 생겼다
- [ ] `keyboard=`가 파일 → PID 1 → argv → `Context`까지 흐른다
- [ ] 게이트가 bash 프롬프트에서 `echo aa bb` → `Option+←` → `X` →
      `aa Xbb`를 증명하고, `aa bbX`와 **`aa bXb`가 없음**을 함께 확인한다
- [ ] 게이트가 `keyboard=pc` 디스크로 한 번 더 떠서 같은 물리 키가 **반대로**
      동작하는 것을 양방향으로 확인한다
- [ ] 루트 게이트가 4체인 3/3으로 PASS한다

## 이 milestone이 남기는 것

- **`Ctrl+←`/`Shift+←`가 여전히 맨 `ESC [ D`로 샌다.** design doc 비목표
  그대로이고, `State.seq`의 6바이트 자리는 이번에도 안 쓴다. TUI 앱이 생기면
  그때 `ESC [ 1 ; 5 D`를 넣는다.
- **`Cmd+C`/`Cmd+V`가 `c`/`v`를 찍는다.** `project_copy_mode`가 그 자리를
  가져갈 때 `chord`의 Meta 갈래에 두 줄이 붙는다.
- **`Option+글자`(`Option+b` 등)는 modifier가 무시된다.** xterm의
  `metaSendsEscape`를 켜는 것과 macOS의 특수문자 입력 중 무엇을 할지는
  키보드 레이아웃(비-US)과 함께 볼 문제다.
- **시리얼 콘솔 셸은 이 정책을 전혀 안 받는다.** 그쪽 입력은 커널 tty
  계층이 처리하며 우리 코드를 지나지 않는다(design doc 비목표).
- **`keyboard`를 게스트 안에서 바꾸는 수단이 여전히 `echo ... > /config/tars.conf`
  하나다.** `tars-config` 명령은 HANDOFF의 이월 숙제로 남는다.
- **IP 서브프로젝트가 여기서 끝난다.** design doc의 목표 다섯이 전부 게이트로
  증명되면 다음 서브프로젝트를 고르는 자리다.
