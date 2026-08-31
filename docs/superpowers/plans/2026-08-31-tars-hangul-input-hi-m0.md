# HI-M0 — 바닥을 재고 오토마타를 세운다

**Date:** 2026-08-31
**Design:** `docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`
**Status:** 착수 전.

## 이 milestone이 끝나면

- **`sendkey lang1`이 게스트의 evdev까지 닿는지 안다.** 닿으면
  `KEY_HANGEUL`(122)이 보이고, 안 닿으면 HI-M3의 전환 키 설계가 바뀐다.
- **`sendkey <key> <hold_ms>`가 누른 시간을 실제로 가르는지 안다.** tap-vs-hold
  전체가 이 값에 걸려 있다.
- **호환 자모와 완성형이 화면에 그려지는 것을 실행으로 봤다.** design 결정 3의
  근거가 굳는다.
- **`terminal/src/hangul.zig`가 있고 두벌식으로 한글을 조합한다.**
  `hangul_test`가 `zig build test`에 붙어 호스트에서 돈다.
- **게스트의 동작은 하나도 안 바뀐다.** `hangul.zig`를 부르는 코드가 아직 없다.
  게이트 체인도 여덟 그대로다.

**편집은 사용자가 한다.** CC-M0의 예외는 그 milestone으로 끝났다(`CLAUDE.md`의
협업 방식 표). 100줄이 넘는 덩어리는 Claude가 `/tmp`에 파일로 만들어 `cp`로
넣는다.

## 왜 이 순서인가

**Task 1과 2가 재기만 하고 저장소를 안 바꾼다.** 실측 1이 빨간불이면 HI-M3의
모양이 바뀌는데, 그것을 오토마타를 다 만든 뒤에 아는 것보다 먼저 아는 것이 낫다.

**Task 3부터 8이 오토마타를 한 겹씩 쌓는다.** 표 → 조합 상태 → 자판 → 기본
전이 → 겹자모 → 지우기 → 불변식 순서다. CS-M0의 실측 9가 적어 둔 것과 같은
이유로 가른다 — 뒤 단계가 틀렸을 때 앞 단계를 의심할 필요가 없어진다.

**게이트는 Task 9 하나다.** 게스트로 가는 코드가 안 바뀌므로 게이트는 회귀만
본다. 다만 `build.zig`가 바뀌므로 안 돌릴 수는 없다.

## 착수 전에 실측으로 확정한 것 (2026-08-31)

**아래 코드는 전부 컨테이너에서 컴파일하고 돌려 본 것이다.** 짐작으로 적은
줄이 없다.

### 1. evdev 이벤트의 시각 필드는 `time.tv_sec` · `time.tv_usec`이다

컨테이너에서 `@cImport("linux/input.h")` 뒤에 그 이름으로 읽고 쓰는 코드가
컴파일되고 실행됐다. `@sizeOf`가 **24**로 나와서 `input.zig:786`의 주석
("timeval 16 + type 2 + code 2 + value 4")과 정확히 맞는다.

### 2. `sendkey`에 `hold_ms` 인자가 있다

```
sendkey keys [hold_ms] -- send keys to the VM (e.g. 'sendkey ctrl-alt-f1', default hold time=100 ms)
```

### 3. QKeyCode 목록에 `lang1`과 `lang2`가 있다

QEMU 10.0.11 바이너리에서 확인했다. 일본어 쪽(`henkan` · `muhenkan` ·
`katakanahiragana`)이 같은 목록에 함께 있다.

### 4. 오토마타가 두벌식을 맞게 조합한다 — 열일곱을 돌려 봤다

| 친 것 | 나온 것 | 어느 갈래인가 |
|---|---|---|
| `g` | ㅎ | 초성만 (호환 자모) |
| `k` | ㅏ | 중성만 (호환 자모) |
| `rk` | 가 | 초성+중성 |
| `gr` | ㅎㄱ | 초성 뒤에 자음이 와서 확정 |
| `rkt` | 갓 | 받침 붙이기 |
| `rkE` | 가ㄸ | 받침이 될 수 없는 자음이 와서 확정 |
| `rkk` | 가ㅏ | 중성 뒤에 모음이 와서 확정 |
| `gksrmf` | 한글 | 여러 음절 |
| `rkrk` | 가가 | 받침 넘기기 |
| `dksk` | 아나 | 받침 넘기기 |
| `dksek` | 안다 | 받침 뒤에 자음 |
| `dkswrj` | 앉거 | 겹받침 만들기 |
| `dkswj` | 안저 | 겹받침 넘기기 (중간에 `앉`) |
| `rhk` | 과 | 복합 모음 |
| `ghk` | 화 | 같은 자리, 다른 초성 |
| `rml` | 긔 | ㅡ+ㅣ |
| `Rk` | 까 | 쌍자음 |

**위의 여덟은 Task 5의 부분 구현으로도 같은 값이 나온다.** 받침 넘기기와
겹모음을 안 밟기 때문이고, 그래서 Task 5의 검사로 쓸 수 있다.

**기대값을 두 번 틀렸고 코드는 맞았다.** `ghk`를 `과`로 적었는데 두벌식에서
`g`는 ㄱ이 아니라 **ㅎ**이라 `화`가 맞다. `과`는 `rhk`다. **표를 옮겨 적을 때
사람이 틀리는 자리가 정확히 여기라서**, Task 4의 자판 표에 `comptime` 앵커를
건다(design 위험 1).

### 5. 그릴 수 없는 상태를 오토마타가 한 번도 안 만든다

두벌식 키 서른셋을 3-순열로 전부 먹여 매 단계를 봤다. **107,811단계에서 0번**이다
(위 실측은 키 목록에 `t`가 겹쳐 34개로 돌아 117,912단계였고 결과는 같았다).
design 결정 3이 코드로 지켜진다는 뜻이고, Task 8이 이 검사를 저장소에 남긴다.

### 6. `erase`가 자모를 하나씩 뺀다

`단` → `다` → `ㄷ` → 빈 상태 → `null`(조합 중이 아니다). 겹받침
`앉` → `안`(U+C548), 복합 모음 `과` → `고`(U+ACE0).

---

## Task 1 — `sendkey lang1`과 `hold_ms`를 잰다 (실측 1·2)

**Files:** `terminal/src/input.zig` (프로브를 넣었다가 되돌린다)

프로브는 저장소에 남기지 않는다. **넣고, 재고, `git checkout`으로 되돌린다.**

### Step 1: 시작 전에 working tree가 깨끗한지 본다

Run:
```bash
git status --short
```
Expected: 아무것도 안 나온다. 나오면 Task 1을 시작하지 않는다 — 되돌릴 때
사용자의 편집까지 함께 날아간다.

### Step 2: 프로브 세 줄을 넣는다

`terminal/src/input.zig:754`

지울 것:
```zig
        if (ev.@"type" != c.EV_KEY) continue;
```

넣을 것:
```zig
        if (ev.@"type" != c.EV_KEY) continue;
        std.debug.print("probe> code={d} value={d} sec={d} usec={d}\n", .{
            ev.code, ev.value, ev.time.tv_sec, ev.time.tv_usec,
        });
```

**`value`가 셋이다** — 1이 누름, 0이 뗌, 2가 자동 반복이다. 셋을 다 찍어야
"눌렀다 뗀 간격"을 잴 수 있다.

### Step 3: 프로브가 들어갔는지 본다

Run:
```bash
git diff --stat terminal/src/input.zig
```
Expected: `1 file changed, 3 insertions(+)`. 지운 줄이 0이어야 한다.

### Step 4: 빌드하고 게스트를 띄워 키를 보낸다 (Claude가 실행, 약 3분)

Claude가 `/tmp/hi-probe.sh`를 만들어 컨테이너 안에서 돌린다.

```bash
#!/bin/bash
set -eu
cd /workspace/terminal && ./prepare.sh
cd /workspace/kernel && ./make_initrd.sh
cd /workspace/terminal

MONITOR_PORT=45999
LOG="$(mktemp)"
qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

for _ in $(seq 1 120); do
  grep -q "terminal: screen>" "$LOG" && break
  sleep 1
done
sleep 1
exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"

# 대조군: 이 키는 반드시 보인다. 안 보이면 프로브 자체가 고장 난 것이다.
echo "sendkey a 100" >&3;      sleep 1
# 실측 1: 한/영 키와 한자 키
echo "sendkey lang1 100" >&3;  sleep 1
echo "sendkey lang2 100" >&3;  sleep 1
# 실측 2: 같은 키를 짧게와 길게
echo "sendkey shift 50" >&3;   sleep 1
echo "sendkey shift 500" >&3;  sleep 1
# CapsLock도 evdev까지 오는지 함께 본다 (HI-M3이 쓴다)
echo "sendkey caps_lock 50" >&3;  sleep 1
echo "sendkey caps_lock 500" >&3; sleep 1

sleep 1
exec 3<&- ; exec 3>&-
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

mkdir -p /workspace/out/probe
grep -a 'probe>' "$LOG" > /workspace/out/probe/hi-m0-keys.txt || true
cat /workspace/out/probe/hi-m0-keys.txt
```

**`shift`로 시간을 재는 이유가 있다.** `a`처럼 문자를 만드는 키는 뗄 때
아무것도 안 하지만 프로브는 `value=0`도 찍으므로 어느 키든 된다. 그런데
modifier 키가 HI-M3이 실제로 다룰 대상이라 그쪽으로 잰다.

**`out/`은 gitignore다.** 그리고 **루트 게이트를 돌리면 `clean()`이 `out`을
통째로 지운다**(`check.sh:15`). 그래서 Task 9보다 먼저 여기서 읽어 둔다.

### Step 5: 결과를 읽는다

읽는 것 셋.

1. `sendkey a`가 `code=30`(KEY_A)을 냈는가 — 프로브가 살아 있다는 대조군.
2. `sendkey lang1`이 **`code=122`**를 냈는가. 냈으면 실측 1이 초록이다.
   아무 줄도 안 나오면 PS/2 경로에서 사라진 것이고, HI-M3은 한/영 키를
   실기용으로만 남긴다.
3. 같은 키의 `value=1`과 `value=0` 사이의 `sec`·`usec` 차이가 **50밀리초
   언저리와 500밀리초 언저리로 갈리는가.** 갈리면 실측 2가 초록이다.

### Step 6: 프로브를 되돌린다

Run:
```bash
git checkout -- terminal/src/input.zig
git status --short
```
Expected: 두 번째 명령이 아무것도 안 낸다.

**이 Step을 빠뜨리면 프로브가 저장소에 들어간다.** Task 9의 게이트는
`probe>` 줄이 늘어도 통과하므로 게이트가 안 잡아 준다.

### Step 7: 커밋할 것이 없다

이 Task는 저장소를 안 바꾼다. 읽은 값은 Task 10에서 design과 `HANDOFF.md`에
적는다.

---

## Task 2 — 호환 자모와 완성형이 그려지는지 본다 (실측 3)

**Files:** 없음. Claude가 컨테이너에서 재고 값만 가져온다.

**게스트가 필요 없다.** 폰트 래스터라이저는 하드웨어와 무관한 순수 계산이고
(`build.zig:134`의 주석), `font_test`가 이미 그 사실 위에 서 있다.

### Step 1: 여섯 코드포인트를 굽는다 (Claude가 실행, 약 30초)

Claude가 `font_test`와 같은 방식으로 부르는 작은 드라이버를 `/tmp`에 만들어
돌린다. 볼 것은 여섯이다.

| 코드포인트 | 무엇 | 왜 보는가 |
|---|---|---|
| U+3137 `ㄷ` | 호환 자모 닿소리 | 초성만 있는 상태를 그린다 |
| U+314F `ㅏ` | 호환 자모 홀소리 | 중성만 있는 상태를 그린다 |
| U+B2E4 `다` | 완성형, 받침 없음 | 초성+중성 |
| U+B2E8 `단` | 완성형, 받침 있음 | 초성+중성+종성 |
| U+1103 `ᄃ` | 첫가끝 초성 | **모아주기를 못 하는 근거다** |
| U+11AB `ᆫ` | 첫가끝 종성 | 같은 이유 |

### Step 2: 결과를 읽는다

- 앞의 넷은 **`bitmap != null`이고 `cell_width`가 나와야** 한다. 호환 자모가
  1칸인지 2칸인지도 여기서 처음 안다 — HI-M1이 preedit을 몇 칸으로 그릴지가
  이 값에 딸린다.
- 뒤의 둘은 **모양이 나오더라도 겹쳐 그려지지 않는다.** unifont가 첫가끝
  자모에 글리프를 갖고 있어도 우리 렌더러는 셀 하나에 글자 하나를 찍을 뿐이다.
  **"글리프가 있다"와 "모아주기를 그릴 수 있다"가 다르다는 것**을 값으로
  적어 둔다.

### Step 3: 커밋할 것이 없다

값은 Task 10에서 design에 적는다.

---

## Task 3 — `hangul.zig`의 표 셋과 조합 상태

**Files:**
- Create: `terminal/src/hangul.zig`
- Create: `terminal/src/hangul_test.zig`
- Modify: `terminal/build.zig`

### Step 1: `hangul.zig`를 만든다

**100줄이 넘으므로 Claude가 `/tmp/hangul_task3.zig`에 만들어 둔다.**

```bash
cp /tmp/hangul_task3.zig terminal/src/hangul.zig
```

내용:

```zig
const std = @import("std");

/// 한글 조합. **시스템 콜도 `vt.zig`도 `drm.zig`도 안 본다**(design 결정 1).
/// 그 대가로 `hangul_test.zig`가 호스트에서 돈다 — 게이트 16분이 아니라
/// `zig build test` 9.5초로 오토마타를 돌려볼 수 있고, 이 서브프로젝트에서
/// 가장 크고 가장 틀리기 쉬운 부분이 오토마타이므로 그 자리가 값을 한다.

/// 초성 열아홉의 순서. **완성형 계산의 첫째 자리다.**
///
/// 값은 첫가끝 자모(U+1100대)가 아니라 **호환 자모**(U+3131대)의
/// 코드포인트다. 초성만 있는 상태를 그릴 때 그대로 쓰기 때문이고, 완성형
/// 계산은 값이 아니라 **인덱스**로 하므로 값이 무엇이든 상관이 없다.
pub const CHO: [19]u21 = .{
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
};

/// 중성 스물하나. 값이 호환 자모인 이유는 CHO와 같다.
pub const JUNG: [21]u21 = .{
    'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ',
    'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
};

/// 종성 스물여덟. **0번 칸은 자리만 채운다.**
///
/// 완성형 계산이 0을 "받침 없음"으로 쓰기 때문에 표의 인덱스를 그 규약에
/// 맞춘다. 그래서 이 칸의 값은 아무도 안 읽는다 — `Syllable.jong`이 `?u5`라
/// "없음"을 null로 적고 0을 안 쓴다.
pub const JONG: [28]u21 = .{
    0,    'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ',
    'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
};

// 위 세 표의 규약은 "N번째 칸이 인덱스 N"인데, 그것을 지켜 주는 것은 주석뿐이다.
// 중간에 한 칸이 끼면 뒤가 전부 밀리고, 그래도 **컴파일은 통과하며**, 증상은
// "치면 다른 글자가 나온다"로만 나타난다. `input.zig:98`이 `keymap`에 같은 못을
// 박았고 이유도 같다.
//
// 양끝과 가운데를 잡는 이유는, 한 칸이 끼면 그 뒤의 앵커가 **반드시** 하나는
// 어긋나기 때문이다.
comptime {
    if (CHO.len != 19) @compileError("CHO must have 19 entries");
    if (JUNG.len != 21) @compileError("JUNG must have 21 entries");
    if (JONG.len != 28) @compileError("JONG must have 28 entries");
    if (CHO[0] != 'ㄱ' or CHO[11] != 'ㅇ' or CHO[18] != 'ㅎ')
        @compileError("CHO table drifted");
    if (JUNG[0] != 'ㅏ' or JUNG[8] != 'ㅗ' or JUNG[20] != 'ㅣ')
        @compileError("JUNG table drifted");
    if (JONG[0] != 0 or JONG[8] != 'ㄹ' or JONG[27] != 'ㅎ')
        @compileError("JONG table drifted");
}

/// 조합 중인 음절 하나.
///
/// **코드포인트가 아니라 인덱스를 담는다.** 완성형 계산이 인덱스로 하고,
/// 그리는 데 쓸 코드포인트는 위의 세 표가 준다.
pub const Syllable = struct {
    cho: ?u5 = null,
    jung: ?u5 = null,
    /// **null이 "받침 없음"이다.** `JONG[0]`은 표의 자리만 채우는 값이라
    /// 여기서 0을 쓰지 않는다 — "없음"을 두 가지로 적을 수 있게 두면
    /// 비교하는 자리마다 둘을 다 봐야 한다.
    jong: ?u5 = null,

    pub fn isEmpty(self: Syllable) bool {
        return self.cho == null and self.jung == null and self.jong == null;
    }

    /// 지금 상태를 화면에 그릴 글자 하나. **못 그리는 조합이면 null이다.**
    ///
    /// 못 그리는 것이 셋이다(design 결정 3): 초성+종성 · 중성+종성 · 종성만.
    /// 완성형에 그런 글자가 없고 unifont가 첫가끝 자모를 겹쳐 그려 주지도
    /// 않는다. **오토마타는 그 셋을 절대 안 만들며** `hangul_test`의 검사
    /// 여섯이 그것을 확인한다 — 여기서 null을 주는 것은 방어가 아니라
    /// **타입이 표현할 수 있는 여덟 조합을 빠짐없이 덮는 것**이다.
    ///
    /// 빈 상태도 null이다. 그 성질을 `feedConsonant`가 쓴다 — 확정할 것이
    /// 없는 경우를 따로 갈라 적지 않아도 된다.
    pub fn codepoint(self: Syllable) ?u21 {
        const c = self.cho orelse {
            if (self.jong != null) return null;
            const v = self.jung orelse return null;
            return JUNG[v];
        };
        const v = self.jung orelse {
            if (self.jong != null) return null;
            return CHO[c];
        };
        const j: u21 = if (self.jong) |x| x else 0;
        return 0xAC00 + (@as(u21, c) * 21 + @as(u21, v)) * 28 + j;
    }
};
```

### Step 2: `hangul_test.zig`를 만든다

`input_test.zig`와 같이 **`init` 인자가 없는 `main`**이다. 파일도 폰트도 안
읽는 순수 계산이기 때문이다(`vt_test`·`font_test`는 `std.process.Init`를 받는다).

```zig
const std = @import("std");
const hangul = @import("hangul.zig");

/// 한글 오토마타의 검사. **부팅도 폰트도 안 쓴다** — 자모를 넣고 코드포인트를
/// 받는 순수 계산이라 게스트가 볼 것이 하나도 없다.
pub fn main() !void {
    // ── 1. 그릴 수 있는 네 상태 ───────────────────────────────────────
    const Want = struct { s: hangul.Syllable, cp: u21, what: []const u8 };
    const wants = [_]Want{
        .{ .s = .{ .cho = 3 }, .cp = 'ㄷ', .what = "초성만은 호환 자모" },
        .{ .s = .{ .jung = 0 }, .cp = 'ㅏ', .what = "중성만은 호환 자모" },
        .{ .s = .{ .cho = 3, .jung = 0 }, .cp = '다', .what = "초성+중성은 완성형" },
        .{ .s = .{ .cho = 3, .jung = 0, .jong = 4 }, .cp = '단', .what = "받침까지 완성형" },
    };
    for (wants) |want| {
        const got = want.s.codepoint();
        if (got == null or got.? != want.cp) {
            std.debug.print("FAIL: {s}: got {?d}, want U+{X}\n", .{ want.what, got, want.cp });
            return error.WrongCodepoint;
        }
        std.debug.print("hangul_test: {s} OK\n", .{want.what});
    }

    // ── 2. 그릴 수 없는 세 상태 (design 결정 3) ───────────────────────
    //
    // **모아주기를 뺀 것이 여기서 코드가 된다.** 완성형에 없는 조합이고
    // unifont가 첫가끝 자모를 겹쳐 그려 주지 않는다. 아래 검사 6이
    // "오토마타가 이 상태를 만들지 않는다"까지 본다.
    const cannot = [_]hangul.Syllable{
        .{ .cho = 3, .jong = 4 },
        .{ .jung = 0, .jong = 4 },
        .{ .jong = 4 },
    };
    for (cannot) |s| {
        if (s.codepoint() != null) {
            std.debug.print("FAIL: 그릴 수 없는 조합이 코드포인트를 냈다\n", .{});
            return error.UnexpectedCodepoint;
        }
    }
    std.debug.print("hangul_test: 모아주기 상태 셋은 그릴 것이 없다 OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

### Step 3: `build.zig`에 붙인다

`terminal/build.zig:160` 다음(= `font_test`의 `installArtifact` 바로 뒤)

넣을 것:
```zig
    // hangul_test도 호스트에서 돈다. **input_test와 같은 자리다** — 자모를
    // 넣고 코드포인트를 받는 순수 계산이라 파일도 폰트도 안 읽는다.
    // libc도 필요 없다(input_test는 `@cImport("linux/input.h")` 때문에
    // link_libc를 켠다).
    const hangul_test_mod = b.createModule(.{
        .root_source_file = b.path("src/hangul_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const hangul_test = b.addExecutable(.{
        .name = "hangul_test",
        .root_module = hangul_test_mod,
    });
    b.installArtifact(hangul_test);
```

`terminal/build.zig:172`

지울 것:
```zig
    test_step.dependOn(&b.addRunArtifact(font_test).step);
```

넣을 것:
```zig
    test_step.dependOn(&b.addRunArtifact(font_test).step);
    test_step.dependOn(&b.addRunArtifact(hangul_test).step);
```

### Step 4: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c './prepare.sh >/dev/null && zig build test'
```
Expected: `hangul_test:` 줄 다섯과 `PASS`가 나오고, `input_test`·`vt_test`·
`font_test`의 기존 출력도 그대로 나온다.

### Step 5: 커밋

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig terminal/build.zig
git commit -m "Add the hangul jamo tables and the composing syllable"
```

---

## Task 4 — 두벌식 자판 표

**Files:** Modify `terminal/src/hangul.zig`, `terminal/src/hangul_test.zig`

### Step 1: `Jamo`와 두벌식 표를 더한다

`hangul.zig`의 `Syllable` 정의 **뒤**에 넣는다.

넣을 것:
```zig
/// 자판이 키 하나에서 뽑아낸 자모.
///
/// **variant가 둘뿐인 것이 지금 쓰는 전부다.** 세벌식은 초성 전용·종성 전용
/// 키가 있고 신세벌식은 조합 상태에 따라 중성과 종성이 갈리므로, HI-M2에서
/// 이 union이 넓어진다. **미리 만들어 두지 않는 이유는** `feed`의 switch가
/// `else` 없이 닫혀 있어서 variant를 더하는 순간 컴파일러가 배선할 자리를
/// 알려주기 때문이다(CM-M0부터 지켜 온 규율).
pub const Jamo = union(enum) {
    /// 자음 하나. **두벌식은 같은 키가 초성도 종성도 되므로 둘을 함께 나른다.**
    /// `jong`이 null인 것은 ㄸ·ㅃ·ㅉ 셋뿐이다 — 받침이 될 수 없는 자음이다.
    consonant: struct { cho: u5, jong: ?u5 },
    /// 모음 하나. 중성 인덱스다.
    vowel: u5,
};

fn cons(cho: u5, jong: ?u5) Jamo {
    return .{ .consonant = .{ .cho = cho, .jong = jong } };
}

/// 두벌식(KS X 5002). **인자는 쿼티 배치의 문자다.**
///
/// `"r"`은 "r이라는 글자"가 아니라 **"쿼티에서 r이 있는 자리의 키"**를 부르는
/// 이름이다. Patal의 자판 맵이 쓰는 규약과 같고(`KeyCodeMapper.swift:11`),
/// TARS에서 그 문자를 만드는 것은 `input.zig`의 `keymap` 배열(`:28`)이다.
/// **그래서 한글 자판은 영문 배열이 쿼티든 드보락이든 안 흔들린다.**
pub fn dubeol(ch: u8) ?Jamo {
    return switch (ch) {
        // 닿소리 열아홉 — {초성 인덱스, 종성 인덱스}
        'r' => cons(0, 1), // ㄱ
        'R' => cons(1, 2), // ㄲ
        's' => cons(2, 4), // ㄴ
        'e' => cons(3, 7), // ㄷ
        'E' => cons(4, null), // ㄸ — 받침이 될 수 없다
        'f' => cons(5, 8), // ㄹ
        'a' => cons(6, 16), // ㅁ
        'q' => cons(7, 17), // ㅂ
        'Q' => cons(8, null), // ㅃ
        't' => cons(9, 19), // ㅅ
        'T' => cons(10, 20), // ㅆ
        'd' => cons(11, 21), // ㅇ
        'w' => cons(12, 22), // ㅈ
        'W' => cons(13, null), // ㅉ
        'c' => cons(14, 23), // ㅊ
        'z' => cons(15, 24), // ㅋ
        'x' => cons(16, 25), // ㅌ
        'v' => cons(17, 26), // ㅍ
        'g' => cons(18, 27), // ㅎ
        // 홀소리 열넷 — 겹모음은 키가 없고 조합으로 만든다
        'k' => .{ .vowel = 0 }, // ㅏ
        'o' => .{ .vowel = 1 }, // ㅐ
        'i' => .{ .vowel = 2 }, // ㅑ
        'O' => .{ .vowel = 3 }, // ㅒ
        'j' => .{ .vowel = 4 }, // ㅓ
        'p' => .{ .vowel = 5 }, // ㅔ
        'u' => .{ .vowel = 6 }, // ㅕ
        'P' => .{ .vowel = 7 }, // ㅖ
        'h' => .{ .vowel = 8 }, // ㅗ
        'y' => .{ .vowel = 12 }, // ㅛ
        'n' => .{ .vowel = 13 }, // ㅜ
        'b' => .{ .vowel = 17 }, // ㅠ
        'm' => .{ .vowel = 18 }, // ㅡ
        'l' => .{ .vowel = 20 }, // ㅣ
        else => null,
    };
}

// 표를 옮겨 적을 때 사람이 틀리는 자리에 못을 박는다. **착수 전 실측에서
// 실제로 두 번 틀렸다** — `g`를 ㄱ으로 읽어 `ghk`를 "과"로 적었는데 `g`는
// ㅎ이라 "화"가 맞다. 아래 넷은 그 종류의 착각이 컴파일을 통과하지 못하게
// 한다.
comptime {
    if (CHO[dubeol('r').?.consonant.cho] != 'ㄱ')
        @compileError("dubeol: r must be the initial of GIYEOK");
    if (CHO[dubeol('g').?.consonant.cho] != 'ㅎ')
        @compileError("dubeol: g must be the initial of HIEUH");
    if (JUNG[dubeol('k').?.vowel] != 'ㅏ')
        @compileError("dubeol: k must be the vowel A");
    if (JUNG[dubeol('l').?.vowel] != 'ㅣ')
        @compileError("dubeol: l must be the vowel I");
}
```

### Step 2: 검사를 더한다

`hangul_test.zig`의 검사 2 **뒤**, `PASS` **앞**에 넣는다.

넣을 것:
```zig
    // ── 3. 두벌식 표 ─────────────────────────────────────────────────
    //
    // **`jong`이 null인 키를 함께 본다.** ㄸ·ㅃ·ㅉ은 받침이 될 수 없고,
    // 그것을 빠뜨리면 "앋ㄸ" 같은 자리에서만 증상이 나온다.
    if (hangul.dubeol('E').?.consonant.jong != null) {
        std.debug.print("FAIL: ㄸ이 받침이 될 수 있다고 되어 있다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('R').?.consonant.jong.? != 2) {
        std.debug.print("FAIL: ㄲ의 받침 인덱스가 2가 아니다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('1') != null) {
        std.debug.print("FAIL: 숫자 키가 자모를 냈다\n", .{});
        return error.NotAJamoKey;
    }
    std.debug.print("hangul_test: 두벌식 표 OK\n", .{});
```

### Step 3: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: `hangul_test: 두벌식 표 OK`가 늘고 `PASS`.

### Step 4: 커밋

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Add the dubeolsik layout table"
```

---

## Task 5 — `feed`의 기본 전이

**Files:** Modify `terminal/src/hangul.zig`, `terminal/src/hangul_test.zig`

**겹자모와 받침 넘기기는 Task 6이다.** 여기서는 "초성을 놓고, 중성을 붙이고,
받침을 붙이고, 안 되면 확정한다"까지만 만든다.

### Step 1: `Step`과 `feed`를 더한다

`hangul.zig`의 `dubeol` **뒤**에 넣는다.

넣을 것:
```zig
/// 자모 하나를 먹인 결과.
pub const Step = struct {
    /// 확정돼서 PTY로 갈 글자. 없으면 null이다.
    commit: ?u21 = null,
    /// 확정하고 남은 조합 상태.
    buf: Syllable = .{},
};

/// 자모 하나를 조합 버퍼에 먹인다. **두벌식의 규칙이다.**
///
/// 세벌식·신세벌식이 들어오는 HI-M2에서 이 함수가 자판을 인자로 받게 된다.
/// switch에 `else`가 없으므로 `Jamo`에 variant를 더하면 여기가 컴파일 에러를
/// 낸다.
pub fn feed(buf: Syllable, jamo: Jamo) Step {
    return switch (jamo) {
        .consonant => |c| feedConsonant(buf, c.cho, c.jong),
        .vowel => |v| feedVowel(buf, v),
    };
}

fn feedConsonant(buf: Syllable, cho: u5, jong: ?u5) Step {
    if (buf.jong != null) {
        // Task 6이 여기에 겹받침을 넣는다.
    } else if (buf.cho != null and buf.jung != null) {
        // 초성+중성이 서 있으면 받침으로 붙는다. ㄸ·ㅃ·ㅉ만 못 붙는다.
        if (jong) |j| {
            return .{ .buf = .{ .cho = buf.cho, .jung = buf.jung, .jong = j } };
        }
    }
    // 나머지는 전부 "앞을 확정하고 새 초성으로 시작한다"이다.
    // **빈 버퍼도 이 갈래로 온다** — `codepoint()`가 null을 주므로 확정될
    // 것이 없고, 그래서 빈 경우를 따로 적지 않는다.
    return .{ .commit = buf.codepoint(), .buf = .{ .cho = cho } };
}

fn feedVowel(buf: Syllable, v: u5) Step {
    if (buf.jong != null) {
        // Task 6이 여기에 받침 넘기기를 넣는다.
    }
    if (buf.jung == null) {
        if (buf.cho) |c| return .{ .buf = .{ .cho = c, .jung = v } };
        return .{ .buf = .{ .jung = v } };
    }
    // 중성이 이미 있고 겹모음이 안 되면 앞을 확정하고 **중성만 있는 상태**로
    // 남는다. 모아주기를 뺐으므로 이 상태는 그릴 수 있다(design 결정 3의 표).
    return .{ .commit = buf.codepoint(), .buf = .{ .jung = v } };
}
```

### Step 2: 검사와 헬퍼를 더한다

`hangul_test.zig`의 `main` **앞**에 헬퍼를 넣는다.

넣을 것:
```zig
/// 두벌식으로 문자열을 통째로 치고 나온 글자를 모은다.
/// **마지막에 남은 조합도 확정한다** — 사람이 Enter를 치는 자리에 해당한다.
fn typeAll(keys: []const u8, out: []u8) ![]const u8 {
    var buf = hangul.Syllable{};
    var len: usize = 0;
    for (keys) |ch| {
        const jamo = hangul.dubeol(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, jamo);
        if (step.commit) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
        buf = step.buf;
    }
    if (buf.codepoint()) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
    return out[0..len];
}

/// 친 것과 나온 것을 짝지어 본다.
fn expectTyped(keys: []const u8, want: []const u8) !void {
    var out: [64]u8 = undefined;
    const got = try typeAll(keys, &out);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("hangul_test: \"{s}\" -> \"{s}\" OK\n", .{ keys, want });
        return;
    }
    std.debug.print("FAIL: \"{s}\" -> \"{s}\", want \"{s}\"\n", .{ keys, got, want });
    return error.WrongComposition;
}
```

검사 3 **뒤**에 넣을 것:
```zig
    // ── 4. 기본 전이 ─────────────────────────────────────────────────
    //
    // **여덟이 서로 다른 갈래를 밟는다.** 초성만 · 중성만 · 초성+중성 ·
    // 초성 뒤에 자음이 와서 확정 · 받침 붙이기 · 받침이 될 수 없는 자음이
    // 와서 확정 · 중성 뒤에 모음이 와서 확정 · 여러 음절.
    //
    // **받침 넘기기가 필요한 것은 여기 없다.** `rkrk`("가가")처럼 받침 뒤에
    // 모음이 오는 경우는 Task 6이 들어와야 맞게 나온다 — 지금 넣으면
    // "각ㅏ"가 나온다.
    try expectTyped("g", "ㅎ");
    try expectTyped("k", "ㅏ");
    try expectTyped("rk", "가");
    try expectTyped("gr", "ㅎㄱ");
    try expectTyped("rkt", "갓");
    try expectTyped("rkE", "가ㄸ");
    try expectTyped("rkk", "가ㅏ");
    try expectTyped("gksrmf", "한글");
```

### Step 3: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: 위 다섯 줄이 전부 OK로 나오고 `PASS`.

**`gksrmf`가 "한글"이 되는 것에 산수가 있다.** `ㅎㅏㄴ`까지 받침이 붙어 `한`이
되고, 다음 `ㄱ`은 `ㄴ`과 겹받침이 안 되므로 `한`을 확정하고 새 초성이 된다.
`ㅡㄹ`이 붙어 `글`이 되고 마지막에 확정된다.

### Step 4: 커밋

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Compose a syllable from initial, vowel and final"
```

---

## Task 6 — 겹자모와 받침 넘기기

**Files:** Modify `terminal/src/hangul.zig`, `terminal/src/hangul_test.zig`

### Step 1: 합치고 가르는 표 넷을 더한다

`hangul.zig`의 `Step` 정의 **앞**에 넣는다.

넣을 것:
```zig
/// 복합 모음. (앞, 뒤) → 합친 것. 안 되면 null.
fn joinVowel(a: u5, b: u5) ?u5 {
    return switch (a) {
        8 => switch (b) { 0 => 9, 1 => 10, 20 => 11, else => null }, // ㅗ+ㅏㅐㅣ
        13 => switch (b) { 4 => 14, 5 => 15, 20 => 16, else => null }, // ㅜ+ㅓㅔㅣ
        18 => switch (b) { 20 => 19, else => null }, // ㅡ+ㅣ = ㅢ
        else => null,
    };
}

/// 복합 모음의 **앞 모음만** 준다. 홑모음이면 null.
/// **뒤 모음은 쓰는 자리가 없어서 안 만든다** — `erase`가 앞만 남기기 때문이다.
fn splitVowel(v: u5) ?u5 {
    return switch (v) {
        9, 10, 11 => 8, // ㅘㅙㅚ → ㅗ
        14, 15, 16 => 13, // ㅝㅞㅟ → ㅜ
        19 => 18, // ㅢ → ㅡ
        else => null,
    };
}

/// 겹받침. (앞, 뒤) → 합친 것. 안 되면 null.
fn joinFinal(a: u5, b: u5) ?u5 {
    return switch (a) {
        1 => switch (b) { 19 => 3, else => null }, // ㄱ+ㅅ = ㄳ
        4 => switch (b) { 22 => 5, 27 => 6, else => null }, // ㄴ+ㅈㅎ
        8 => switch (b) { // ㄹ
            1 => 9, 16 => 10, 17 => 11, 19 => 12,
            25 => 13, 26 => 14, 27 => 15,
            else => null,
        },
        17 => switch (b) { 19 => 18, else => null }, // ㅂ+ㅅ = ㅄ
        else => null,
    };
}

const FinalPair = struct { head: u5, tail: u5 };

/// 겹받침을 (앞, 뒤)로 가른다. 홑받침이면 null.
/// **여기는 앞뒤가 둘 다 필요하다** — 받침 넘기기가 앞은 남기고 뒤만 넘긴다.
fn splitFinal(j: u5) ?FinalPair {
    return switch (j) {
        3 => .{ .head = 1, .tail = 19 }, // ㄳ
        5 => .{ .head = 4, .tail = 22 }, // ㄵ
        6 => .{ .head = 4, .tail = 27 }, // ㄶ
        9 => .{ .head = 8, .tail = 1 }, // ㄺ
        10 => .{ .head = 8, .tail = 16 }, // ㄻ
        11 => .{ .head = 8, .tail = 17 }, // ㄼ
        12 => .{ .head = 8, .tail = 19 }, // ㄽ
        13 => .{ .head = 8, .tail = 25 }, // ㄾ
        14 => .{ .head = 8, .tail = 26 }, // ㄿ
        15 => .{ .head = 8, .tail = 27 }, // ㅀ
        18 => .{ .head = 17, .tail = 19 }, // ㅄ
        else => null,
    };
}

/// 종성 인덱스를 초성 인덱스로. **겹받침은 여기 안 온다** — `splitFinal`이
/// 먼저 갈라서 뒷자만 넘긴다. 그리고 종성에는 ㄸ·ㅃ·ㅉ이 없으므로 초성
/// 4·8·13은 이 함수에서 안 나온다.
fn finalToInitial(j: u5) ?u5 {
    return switch (j) {
        1 => 0, 2 => 1, 4 => 2, 7 => 3, 8 => 5, 16 => 6, 17 => 7,
        19 => 9, 20 => 10, 21 => 11, 22 => 12, 23 => 14, 24 => 15,
        25 => 16, 26 => 17, 27 => 18,
        else => null,
    };
}
```

### Step 2: `feedConsonant`의 빈 갈래를 채운다

`hangul.zig`의 `feedConsonant`

지울 것:
```zig
    if (buf.jong != null) {
        // Task 6이 여기에 겹받침을 넣는다.
    } else if (buf.cho != null and buf.jung != null) {
```

넣을 것:
```zig
    if (buf.jong) |cur| {
        // 받침 자리가 찼으면 겹받침이 되는지 본다.
        if (jong) |j| {
            if (joinFinal(cur, j)) |merged| {
                return .{ .buf = .{ .cho = buf.cho, .jung = buf.jung, .jong = merged } };
            }
        }
    } else if (buf.cho != null and buf.jung != null) {
```

### Step 3: `feedVowel`의 빈 갈래를 채운다

`hangul.zig`의 `feedVowel`

지울 것:
```zig
    if (buf.jong != null) {
        // Task 6이 여기에 받침 넘기기를 넣는다.
    }
    if (buf.jung == null) {
```

넣을 것:
```zig
    // 받침이 있는데 모음이 왔다 — 그 받침을 다음 음절의 초성으로 넘긴다.
    // **두벌식의 핵심이고, 겹받침은 뒷자만 넘어간다**(앉 + ㅓ → 안 + 저).
    //
    // `.?` 둘이 단언이다. `splitFinal`의 tail도, 홑받침도 전부
    // `finalToInitial`의 표에 있다 — 종성 스물일곱 중 겹받침 열하나는 위
    // 갈래로 빠지고 나머지 열여섯이 표에 그대로 있다.
    if (buf.jong) |j| {
        if (splitFinal(j)) |pair| {
            const head = Syllable{ .cho = buf.cho, .jung = buf.jung, .jong = pair.head };
            return .{
                .commit = head.codepoint(),
                .buf = .{ .cho = finalToInitial(pair.tail).?, .jung = v },
            };
        }
        const head = Syllable{ .cho = buf.cho, .jung = buf.jung };
        return .{
            .commit = head.codepoint(),
            .buf = .{ .cho = finalToInitial(j).?, .jung = v },
        };
    }
    if (buf.jung == null) {
```

### Step 4: 겹모음을 `feedVowel` 끝에 넣는다

`hangul.zig`의 `feedVowel`

지울 것:
```zig
    // 중성이 이미 있고 겹모음이 안 되면 앞을 확정하고 **중성만 있는 상태**로
    // 남는다. 모아주기를 뺐으므로 이 상태는 그릴 수 있다(design 결정 3의 표).
    return .{ .commit = buf.codepoint(), .buf = .{ .jung = v } };
```

넣을 것:
```zig
    // 중성이 이미 있다 — 복합 모음이 되는지 먼저 본다.
    if (joinVowel(buf.jung.?, v)) |merged| {
        return .{ .buf = .{ .cho = buf.cho, .jung = merged } };
    }
    // 안 되면 앞을 확정하고 **중성만 있는 상태**로 남는다. 모아주기를
    // 뺐으므로 이 상태는 그릴 수 있다(design 결정 3의 표).
    return .{ .commit = buf.codepoint(), .buf = .{ .jung = v } };
```

### Step 5: 검사를 더한다

`hangul_test.zig`의 검사 4 **뒤**에 넣을 것:
```zig
    // ── 5. 겹자모와 받침 넘기기 ───────────────────────────────────────
    //
    // **여섯이 서로 다른 갈래를 밟는다.** 복합 모음 · ㅡㅣ · 홑받침 넘기기 ·
    // 겹받침 만들기 · 겹받침 넘기기 · 쌍자음.
    try expectTyped("rhk", "과");
    try expectTyped("rml", "긔");
    try expectTyped("dksk", "아나");
    try expectTyped("dkswrj", "앉거");
    try expectTyped("dkswj", "안저");
    try expectTyped("Rk", "까");
```

### Step 6: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: 위 여섯 줄이 전부 OK로 나오고 `PASS`.

**`dkswj`가 "안저"인 것이 이 Task에서 가장 볼 만한 값이다.** `ㅇㅏㄴ`이 `안`이
되고, `ㅈ`이 `ㄴ`과 만나 겹받침 `ㄵ`이 되어 화면에는 `앉`이 뜬다. 그 뒤 `ㅓ`가
오면 `ㄵ`이 갈려 `ㄴ`은 남고 `ㅈ`이 넘어가 `안` + `저`가 된다.

### Step 7: 커밋

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Join compound jamo and carry the final over to the next syllable"
```

---

## Task 7 — Backspace로 자모를 하나 뺀다

**Files:** Modify `terminal/src/hangul.zig`, `terminal/src/hangul_test.zig`

### Step 1: `erase`를 더한다

`hangul.zig`의 맨 끝에 넣을 것:
```zig
/// Backspace. 조합 중이면 **자모를 하나** 뺀다(design 결정 6).
///
/// **null은 "조합 중이 아니다"라는 뜻이다.** 그때는 부르는 쪽이 지금처럼
/// DEL(0x7F)을 PTY로 보낸다. 음절을 통째로 지우는 것은 Patal의 `글자단위삭제`
/// trait이고 안 옮긴다(design 비목표).
pub fn erase(buf: Syllable) ?Syllable {
    if (buf.jong) |j| {
        if (splitFinal(j)) |pair| {
            return .{ .cho = buf.cho, .jung = buf.jung, .jong = pair.head };
        }
        return .{ .cho = buf.cho, .jung = buf.jung };
    }
    if (buf.jung) |v| {
        if (splitVowel(v)) |head| return .{ .cho = buf.cho, .jung = head };
        return .{ .cho = buf.cho };
    }
    if (buf.cho != null) return .{};
    return null;
}
```

### Step 2: 검사를 더한다

`hangul_test.zig`의 검사 5 **뒤**에 넣을 것:
```zig
    // ── 6. Backspace ─────────────────────────────────────────────────
    //
    // `단`을 네 번 지운다: 단 → 다 → ㄷ → 빈 상태 → null.
    // **마지막 null이 "조합 중이 아니다"이고**, 그때 부르는 쪽이 DEL을 보낸다.
    var b = hangul.Syllable{ .cho = 3, .jung = 0, .jong = 4 };
    const steps = [_]?u21{ '다', 'ㄷ', null };
    for (steps) |want| {
        const next = hangul.erase(b) orelse {
            std.debug.print("FAIL: 조합 중인데 erase가 null을 냈다\n", .{});
            return error.UnexpectedEnd;
        };
        const got = next.codepoint();
        if (!std.meta.eql(got, want)) {
            std.debug.print("FAIL: erase -> {?d}, want {?d}\n", .{ got, want });
            return error.WrongErase;
        }
        b = next;
    }
    if (hangul.erase(b) != null) {
        std.debug.print("FAIL: 빈 상태에서 erase가 null이 아니다\n", .{});
        return error.UnexpectedErase;
    }
    std.debug.print("hangul_test: 단 -> 다 -> ㄷ -> 빈 상태 -> null OK\n", .{});

    // 겹자모는 **한 겹만** 벗는다. 앉 → 안, 과 → 고.
    if (hangul.erase(.{ .cho = 11, .jung = 0, .jong = 5 }).?.codepoint().? != '안') {
        std.debug.print("FAIL: 앉을 지웠는데 안이 안 나온다\n", .{});
        return error.WrongErase;
    }
    if (hangul.erase(.{ .cho = 0, .jung = 9 }).?.codepoint().? != '고') {
        std.debug.print("FAIL: 과를 지웠는데 고가 안 나온다\n", .{});
        return error.WrongErase;
    }
    std.debug.print("hangul_test: 겹받침과 복합 모음은 한 겹만 벗는다 OK\n", .{});
```

### Step 3: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: 두 줄이 OK로 나오고 `PASS`.

### Step 4: 커밋

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Remove one jamo at a time on backspace"
```

---

## Task 8 — 그릴 수 없는 상태를 만들지 않는다

**Files:** Modify `terminal/src/hangul_test.zig`

**design 결정 3을 코드로 못 박는 검사다.** 앞의 검사 2는 "그런 상태는 그릴
것이 없다"만 말하고, 이 검사가 **"오토마타가 그런 상태를 애초에 안 만든다"**를
말한다. 둘이 함께 있어야 모아주기를 뺀 것이 안전하다는 근거가 선다.

### Step 1: 검사를 더한다

`hangul_test.zig`의 검사 6 **뒤**, `PASS` **앞**에 넣을 것:
```zig
    // ── 7. 오토마타는 그릴 수 없는 상태를 만들지 않는다 (design 결정 3) ─
    //
    // 두벌식 키 서른셋을 3-순열로 전부 먹이고 **매 단계**를 본다. 마지막
    // 상태만 보면 안 된다 — 중간에 한 번 지나가는 것만으로도 화면에서
    // 글자가 사라진다.
    //
    // **셋이면 충분한 이유가 있다.** 조합 상태는 (초, 중, 종) 셋이라 넷째
    // 키부터는 앞의 상태가 되풀이된다.
    const keys = "rRseEfaqQtTdwWczxvgkoiOjpuPhynbml";
    var bad: usize = 0;
    var seen: usize = 0;
    for (keys) |k1| for (keys) |k2| for (keys) |k3| {
        var s = hangul.Syllable{};
        for ([_]u8{ k1, k2, k3 }) |ch| {
            s = hangul.feed(s, hangul.dubeol(ch).?).buf;
            seen += 1;
            if (!s.isEmpty() and s.codepoint() == null) bad += 1;
        }
    };
    if (bad != 0) {
        std.debug.print("FAIL: {d}단계 중 {d}번 그릴 수 없는 상태가 됐다\n", .{ seen, bad });
        return error.UnreachableStateReached;
    }
    std.debug.print(
        "hangul_test: 3-순열 {d}단계에서 그릴 수 없는 상태가 0번 OK\n",
        .{seen},
    );
```

### Step 2: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: `3-순열 107811단계에서 그릴 수 없는 상태가 0번 OK`.

**107,811은 33 × 33 × 33 × 3이다.** 이 숫자가 다르게 나오면 `keys` 문자열에
글자가 겹치거나 빠진 것이다 — 착수 전 실측에서 실제로 `t`가 겹쳐 34개로
돌았고 117,912가 나왔다.

### Step 3: 커밋

```bash
git add terminal/src/hangul_test.zig
git commit -m "Prove the automaton never reaches an undrawable state"
```

---

## Task 9 — 루트 게이트

### Step 1: 돌린다 (Claude가 실행, 약 16분)

**Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash ./check.sh
```
Expected: `TARS check PASS: all chains 3/3 consecutive runs succeeded`

**게스트로 가는 코드가 하나도 안 바뀌었으므로 회귀만 본다.** 그래도 돌리는
이유는 `build.zig`가 바뀌었기 때문이다 — 여섯 체인이 전부 `prepare.sh`를
거쳐 `zig build`를 부른다.

### Step 2: 걸린 시간을 적어 둔다

체인이 여덟 그대로이므로 **기준선(16분 01~11초)과 같아야 한다.** 갈리면
`hangul_test`가 `zig build test`에 붙은 값이고, 그 값을 Task 10에서 적는다.

---

## Task 10 — 문서를 맞춘다

**Files:** design doc · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/`

### Step 1: design doc에 실측 절을 더한다

`docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`의 `Status:`를
고치고 **"HI-M0이 실측한 것"** 절을 더한다. 적을 것 넷.

1. `sendkey lang1`이 evdev에 닿았는가 (Task 1). **닿지 않았으면 위험 4가
   현실이 된 것이므로 HI-M3의 모양을 함께 고친다.**
2. `hold_ms`가 실제로 갈렸는가와 그 값 (Task 1).
3. 호환 자모·완성형·첫가끝의 굽기 결과와 **호환 자모가 몇 칸인지** (Task 2).
4. 게이트 시간 (Task 9).

### Step 2: `HANDOFF.md`를 고친다

- 맨 위를 **"HI-M0이 끝났다"**로 바꾼다.
- **"HI-M0이 실행으로 증명한 것 — 다시 조사하지 말 것"** 절을 만든다.
- 이월 숙제에 design 비목표에서 온 항목 넷을 더한다: 기호 확장 · Patal의
  나머지 trait들 · copy mode 검색창의 한글 · 입력기 상태 표시.
- **"핵심 파일" 절에 `hangul.zig`와 `hangul_test.zig`를 더한다.** 줄 번호는
  이 시점에 `rg`로 다시 잰다.

### Step 3: 기억을 남긴다

`docs/decisions/project_hangul_input.md`를 만들고 `MEMORY.md`에 한 줄 더한다.

### Step 4: `CLAUDE.md`의 완료 목록은 아직 안 고친다

**서브프로젝트가 안 끝났다.** HI-M3까지 끝나는 시점에 고친다. 대신
"진행 중인 서브프로젝트가 없다"는 문장은 **지금 틀린 말이 되므로** Hangul
Input이 진행 중이라고 고친다.

### Step 5: 커밋

```bash
git add docs/ HANDOFF.md MEMORY.md CLAUDE.md
git commit -m "Close out HI-M0"
```
