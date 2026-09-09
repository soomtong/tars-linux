# TARS Find Paste — Design

**Date:** 2026-09-09
**Status:** 착수 — FP-M0 · FP-M1 둘. plan은 milestone이 시작될 때 쓴다.

Search Hangul(SH-M0~M2, 2026-09-09)이 **다음 후보로 지목해 두고 근거까지 모아
둔 것**을 집는다 — 검색 프롬프트의 붙여넣기다. SH design의 비목표 절이
"SH가 놓는 두 층 위에 정확히 얹힌다"고 적었고, 이 문서는 그 자리에서
시작한다.

**이름이 Search Paste가 아닌 이유.** `SP`는 이미 Search Position(2026-08-29·30)이
쓴다. 그리고 코드의 어휘가 search가 아니라 find다 — `find_open`·`findBytes`·
`findNeedle`·`find_buf`. 저장소가 쓰는 말을 따라 **Find Paste (FP)**로 부른다.

## 한 줄 요약

**`/` 프롬프트에서 `Cmd+V`가 클립보드를 검색어에 붙인다.** 화면에서 본 것을
눈으로 읽어 손으로 다시 칠 필요가 없어진다.

```
  copy mode에서 한글을 잡는다 → y     ← 클립보드에 `한글서버`
  /                                    ← 프롬프트를 연다
  Cmd+V                                ← /한글서버
  Enter                                ← 찾는다
```

## 왜 지금인가

**작업 흐름이 여기서 닫힌다.** CM이 yank를 만들고 CN이 검색을 만들고 SH가
프롬프트의 한글을 만들었는데, 그 셋을 잇는 한 걸음이 없다. 지금은 화면에서
본 한글을 **눈으로 읽고 손으로 다시 쳐야 한다** — SH가 없앤 것은 "영문으로
옮겨 적기"였고 "다시 치기"는 남아 있다.

**SH 없이는 성립하지 않았다.** 붙여넣기가 needle에 들어가려면 `find_buf`가
글자 단위여야 하고(SH-M0의 `findBytes`), 붙인 한글이 보이려면 `drawPrompt`가
폭 2를 알아야 한다(SH-M2). 둘 다 이미 서 있다.

**그리고 SH 결정 7의 가드가 왜 저 모양인지가 여기서 드러난다.** 128바이트
경계는 손으로 쳐서는 사실상 안 닿는데(한글 42자) **yank한 줄 하나가 한 번에
닿는다.** `findBytes`가 "통째로 받거나 거절한다"로 지어진 이유가 이
서브프로젝트다.

## 이미 서 있는 것 — 받는 쪽은 다 됐다

| 자리 | 무엇 |
|---|---|
| `vt.zig:702 findBytes` | 바이트 여럿을 **통째로 받거나 거절한다.** 넘침 규칙이 한 자리다 |
| `vt.zig:1459 clipboard()` | `y`가 채운 것. 소유권은 `Screen`이고 다음 `y`가 옛것을 해제한다 |
| `main.zig:873 dumpPaste` | 지금은 PTY로만 쓴다 |

**새로 만들 것은 함수 하나와 갈래 하나다.** 그것이 이 서브프로젝트의 크기를
정한다.

## 막혀 있는 것 — `Cmd+V`가 프롬프트에 안 닿는다

`handleKey`의 단계 순서가 전부다.

```
0     키보드 보정 · tap 소비 표시
1     modifier switch (Meta/Ctrl/CapsLock …)   ← metaed()가 여기서 채워진다
1.3   뗄 때는 여기서 끝난다 (value == 0)
1.4   find 분기      (mode == .find)   ── Esc/Enter → hangulLayer → ASCII
1.5   copy 표        (mode == .copy)   ── c.KEY_V: metaed면 .copy = .paste
1.7   hangulLayer    (normal)
2     chord()                           ── Meta 분기의 c.KEY_V: .copy = .paste
```

find 분기가 둘보다 **앞**이라 `Cmd+V`가 ①에도 ②에도 안 닿는다. 그래서
`latinChar()`가 `v`를 돌려주고 **needle에 글자 `v`가 들어간다.** 이것이 지금
동작이다.

그리고 `.copy = .paste`가 적힌 자리가 **둘**이다. CM 결정 4가 그 중복을 적어
두면서 "한쪽만 넣으면 나머지 모드에서 조용히 안 먹는다"고 경고했다.

## 결정 여섯

### 결정 1 — `Cmd+V`의 판단을 **한 자리**로 모은다

사용자가 골랐다. 셋째 자리를 더하는 쪽과 견줬다.

`1.3번 단계` 바로 뒤, **모드 분기 셋보다 앞**에 한 자리를 만든다.

```zig
// 1.35번 단계 — 붙여넣기. **모드 셋이 같은 키를 쓰고 목적지만 갈린다.**
if (self.metaed() and code == c.KEY_V) {
    self.commitHangul();
    return .{ .copy = .paste };
}
```

그리고 **지운다** — `input.zig:1365`의 `if (self.metaed()) return .{ .copy =
.paste };`와 `input.zig:1074`의 `c.KEY_V => .{ .copy = .paste },`.

**적힌 자리가 2 → 1이다.** 안 고른 쪽(find 분기에 `.find_paste`를 더하기)은
기존 두 줄을 한 글자도 안 건드려 변경 범위가 가장 작지만, 같은 뜻이 적힌
자리를 셋으로 늘린다 — **넷째 모드가 생길 때 빼먹는 것이 다음 사고고**,
IS-M1이 `Action.caps`를 안 만든 이유와 같은 종류다.

**이 저장소가 이미 이 모양을 쓴다.** `readKeys:1484`가
`to_needle = self.mode == .find` 한 줄을 읽어 두고 확정된 음절의 목적지를 그
하나로 가른다(SH 결정 5). "판단은 한 자리, 목적지만 갈린다"가 SH-M1이 세운
것이고 결정 1은 그것과 같은 모양이다.

### 결정 2 — `commitHangul()`을 명시적으로 부른다

끌어올린 자리가 `hangulLayer`보다 **앞**이다. 조합 중에 `Cmd+V`를 누르면
음절이 먼저 확정돼야 하는데, 그 일을 해 주던 층을 지나치게 됐다.

**새 기계가 아니다.** find 분기의 `Enter`가 이미 그 한 줄을 쓴다
(`input.zig:1266`). 그리고 **그 뒤는 저절로 맞는다** — `readKeys:1494`의
`takeCommit()`이 action과 무관하게 돌면서 `to_needle`로 목적지를 가르므로,
셸이면 PTY로 find 모드면 needle로 간다. 통로가 안 는다.

빼먹으면 조합 중 `Cmd+V`가 음절을 잃는다. `input_test` 검사 하나가 그 자리만
본다.

### 결정 3 — 목적지는 `main.zig`가 정한다

```zig
.paste => if (screen.findNeedle() != null)
    dumpFindPaste(screen)                      // needle로
else
    dumpPaste(screen, session.master_fd),      // 셸로
```

`input.zig`는 `vt.zig`를 import하지 않는다(IP 결정 6). 무엇을 보낼지가
클립보드에 달려 있고 클립보드는 `vt.zig`가 드므로, 이 갈래는 `main.zig`에만
설 수 있다.

**판단 근거를 `screen.findNeedle()`로 쓴다.** `input.State`의 모드가 아니라
화면 쪽 사실이다 — `main.zig`가 볼 수 있는 것이 그쪽이고, `findBytes`가
이미 `find_open`을 스스로 지킨다(두 곳이 같은 사실을 지키는 `vt.zig`의
규율).

### 결정 4 — 첫 줄 자르기는 `vt.zig`에 산다

사용자가 골랐다(여러 줄 처리). 클립보드(`self.clip`)와 needle(`find_buf`)이
**둘 다 `Screen`에 살기 때문**이고, 그래서 `main.zig`는 라우터로 남는다.

```zig
/// 클립보드의 **첫 줄**을 needle에 붙인다. 넣은 바이트 수를 돌려준다.
pub fn findPaste(self: *Screen) usize {
    const text = self.clip orelse return 0;
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    const before = self.find_len;
    self.findBytes(text[0..end]);       // 통째로 받거나 거절한다 (SH 결정 7)
    return self.find_len - before;
}
```

**이 자리의 값은 검증 속도다.** 프레임버퍼도 evdev도 안 보므로 `vt_test`가
호스트에서 **초 단위**로 본다 — 18분짜리 게이트에 가기 전에 첫 줄 자르기 ·
넘침 거절 · 빈 클립보드가 전부 판정난다.

### 결정 5 — 여러 줄은 **첫 줄만** 넣는다

사용자가 골랐다. 안 고른 둘: 개행이 있으면 통째로 거절 · 개행을 공백으로
바꾸기.

**화면 셀에는 개행이 없으므로 개행이 든 needle은 영영 안 맞는다.** 증상이
"붙여넣었는데 못 찾음이 뜬다"라 조용하다. `dumpPaste`는 bracketed paste로 안
감싸기로 해서(CM 결정 9) 셸 쪽은 개행이 곧 실행이 되는 것을 감수했지만,
검색은 감수할 수 있는 종류가 아니다 — 셸에서는 잘못 붙은 것이 화면에 보이고
검색에서는 안 보인다.

개행을 공백으로 바꾸는 쪽이 가장 조용한 실패다. 화면에서 줄이 바뀐 자리는
셀에 공백이 아니라 줄 끝이므로 **여전히 안 맞으면서** 겉보기에는 그럴듯한
needle이 된다.

**전제를 실행으로 확인했다(2026-09-09, 임시 프로브).** 여러 줄을 yank하면
개행이 정말 들어가고 `0A` 한 바이트이며 CR이 없다.

```
PROBE: yanked len=13 text='가나\n다라'
PROBE: bytes=EA B0 80 EB 82 98 0A EB 8B A4 EB 9D BC
```

**줄 끝 공백은 `copyYank`가 이미 트림한다** — row 0이 20칸인데 `가나` 여섯
바이트 뒤에 바로 `0A`가 온다. FP가 공백을 따로 다룰 필요가 없다.

**한 줄 yank는 개행이 안 붙는다.** 게이트 로그가
`clip> len=11 text=echo PASTED`로 정확히 11바이트다(`copy/check.sh:391`).
이 결정은 여러 줄을 잡았을 때만 작동한다.

### 결정 6 — 게이트는 두 수를 한 줄에 함께 찍는다

```
terminal: find> paste clip=20 put=20     ← 잘 들어갔다
terminal: find> paste clip=50 put=20     ← 여러 줄이라 첫 줄만 잘렸다
terminal: find> paste clip=0  put=0      ← 클립보드가 비었다
terminal: find> paste clip=200 put=0     ← 128바이트를 넘어 거절됐다
```

**하나만 찍으면 "안 들어갔다"의 네 이유가 안 갈린다.** IS-M1 실측 5가
`on=87 off=87`로 배운 것과 같다 — 값이 같아야 하는(또는 갈려야 하는) 두 수를
한 줄에 함께 찍는 것이 판정을 만든다.

문구가 이 문서와 `main.zig`와 `hangul/check.sh` 셋에 있다 — **한쪽을 고치면
나머지도 고쳐야 한다**(`clip>`가 이미 그런 자리다).

## Milestone 둘 — 아래층부터 올라간다

### FP-M0 — `findPaste`가 첫 줄을 넣는다 (**호스트 초 단위**)

**Task 1** — `vt.zig`에 `findPaste`, `vt_test`에 검사 다섯(55~59).

| 검사 | 무엇을 본다 |
|---|---|
| 55 | **대조군.** 빈 클립보드는 `0`이고 needle이 **안 바뀐다** |
| 56 | 한 줄 클립보드가 **통째로** 들어간다 |
| 57 | 이미 친 글자 **뒤에** 붙는다(`가` + `다라` → `가다라`) |
| 58 | 여러 줄이면 **첫 줄만**(`가나\n다라` → needle이 `가나`) |
| 59 | 128바이트를 넘으면 `0`이고 needle이 **안 바뀐다** |

**대조군이 55로 앞에 온 것은 plan을 쓰다 나온 것이다.** 검사 54가 끝난 자리의
화면(`um`)이 마침 y를 한 번도 안 눌러 클립보드가 비어 있다 — 대조군이 공짜로
나오는 자리이고, 그것을 먼저 두지 않으면 **`findPaste`가 늘 무언가를 넣는
구현도 나머지 넷을 전부 통과한다.**

**배선이 없으므로 동작이 한 글자도 안 바뀐다. 게이트를 안 돌린다.**
SH-M0이 같은 모양이었고, 그 값은 18분에 가기 전에 첫 줄 자르기와 넘침
규칙이 초 단위로 판정난다는 것이다.

### FP-M1 — `Cmd+V`가 프롬프트에 닿는다

**Task 1 — 판단을 한 자리로.** `input_test` 검사 둘(58·59)을 먼저 넣어
실패를 본다(지금은 `.find_char = 'v'`가 돌아온다). 그다음 1.35단계를 넣고
두 줄을 지운다.

판정이 둘이고 **둘 다 기존 검사가 한 글자도 안 바뀐 채 통과하는 것**이다.

**호스트에서 초 단위로 먼저 답한다.** `input_test`의 검사 11(`Cmd+V`가 모드
**밖**에서 붙여넣는다 — `chord()` 쪽)과 검사 12(모드 **안**에서도 붙여넣는다 —
copy 표 쪽)가 지우는 두 줄을 **각각 하나씩** 이미 보고 있다. 검사 12의 주석이
"한쪽만 넣으면 나머지 모드에서 조용히 안 먹는다"라고 적어 둔 그 자리이고,
**결정 1이 없애는 중복이 바로 그것이다.**

그다음 **`copy/check.sh` 한 체인**이 같은 사실을 실기에서 본다
(`391`·`446`·`495~507`). 전체 게이트를 안 돌리고 한 체인만 돌린다.

**Task 2 — 목적지 갈래.** `main.zig`의 `.paste` 갈래와 `dumpFindPaste`.

Task 1과 2 사이에 **의도된 중간 상태**가 있다 — 프롬프트에서 `Cmd+V`가
클립보드를 **셸로** 쓴다. SH-M1이 끝난 시점에 프롬프트의 한글이 글리프
셋으로 깨져 보였던 것과 같은 종류이고, Task 2가 닫는다.

**Task 3 — 게이트.** `hangul/check.sh` 검사 20. 검사 19a가 끝난 자리를
이어받는다(화면에 `가`가 있고 한글이 켜져 있다).

```
한글을 yank → Cmd+Shift+C → / → Cmd+V → Enter
```

판정 넷:

| 줄 | 무엇 |
|---|---|
| `find> paste clip=N put=N` | 클립보드가 needle에 닿았고 잘리지 않았다 |
| `find> overlay text=/가` | **기존 줄을 재사용한다** — needle이 그 글자다 |
| `find> submit … matches≥1` | 붙인 한글이 화면의 한글을 찾았다 |
| `clip> paste` 줄 수가 **안 늘었다** | **셸 갈래를 안 탔다** |

**마지막 음성 검사가 이 설계의 유일한 위험을 정면으로 본다** — 판단을
끌어올린 대가가 "프롬프트에서도 셸로 쓴다"이고, 그 갈래는 `dumpPaste`가
`clip> paste len=N`을 찍는다. 두 갈래가 **다른 접두사를 쓰는 것**이 판정을
만든다.

**`key_lines`를 쓰면 안 된다 — 착수 전에 코드를 읽고 고쳤다.** 검사 18이 쓰는
그 수법이 여기서는 통하지 않는다. `dumpPaste`는 `pty.write`를 **직접** 부르지
`keys.bytes`를 거치지 않으므로 **붙여넣기는 `key>` 줄을 아예 안 만든다** —
`copy/check.sh:439`가 그 사실을 주석에 적어 뒀다. 새는 것을 못 보는 음성
검사를 넣었다면 게이트가 초록인 채로 버그가 남는다.

**Task 4** — 전체 게이트 아홉 체인 3/3.

## 위험 넷

**1. 두 줄을 지우다 회귀한다.** `copy/check.sh`가 셸(391·446)과 copy
mode(495~507) 양쪽의 `Cmd+V`를 이미 본다. **결정 1의 유일한 위험이 정확히
게이트가 덮는 범위 안이다.** Task 1에서 그 체인만 돌려 즉시 잡는다.

**2. `metaed()`가 find 분기 앞에서 참인가.** modifier switch(`input.zig:1184`)가
find 분기(`1233`)보다 앞이므로 참이다. **착수 전에 읽어서 확인했다 — 다시
조사하지 말 것.** 뗄 때 거르는 줄(`1231`)도 그 사이에 있으므로 1.35단계는
누름과 자동 반복에서만 돈다.

**3. 게이트의 클립보드를 결정적으로 만들기.** 무엇을 yank하느냐로 `clip=N`이
갈린다. 줄 선택(`V`)은 줄 전체가 딸려 와 값이 흔들리므로 문자 선택(`v`)으로
`가` 하나를 잡는 쪽이 안전하다 — 키 순서는 plan이 정한다.

**4. `commitHangul()`을 빼먹으면** 조합 중 `Cmd+V`가 음절을 잃는다.
`input_test` 검사 59가 그 자리만 본다.

## 비목표

- **bracketed paste** — CM 결정 9가 근거를 대고 비워 둔 자리이고 FP가
  뒤집지 않는다. 셸이 그 모드를 받는지 확인한 적이 없다.
- **시스템 클립보드(OSC 52)** — TARS의 클립보드는 `y`가 채우는 것 하나다.
- **검색 기록 `↑`** — CN-M1이 근거를 대고 비워 뒀다. 지난 검색어를 다시 쓰는
  길은 **빈 `Enter`**이고 그것으로 충분하다.
- **프롬프트 안의 커서 이동·편집** — 지금도 끝에서만 지운다(`findErase`).
  붙여넣기가 그 규칙을 안 흔든다.
- **HI가 남긴 둘** — 기호 확장과 Patal의 옵션 trait들 · 모아주기(첫가끝
  조합, HI 결정 3이 근거를 대고 뺐다).

## 참고

- Search Hangul: `docs/superpowers/specs/2026-09-09-tars-search-hangul-design.md`
  (결정 열 · 비목표 절이 이 서브프로젝트를 지목했다)
- Copy Mode: `.../2026-08-24-tars-copy-mode-design.md`(결정 4가 `.paste`의 두
  자리를, 결정 9가 bracketed paste를 적었다)
- Copy Navigation: `.../2026-08-26-tars-copy-navigation-design.md`(검색
  프롬프트를 세운 곳)
- Input Status: `.../2026-09-02-tars-input-status-design.md`(IS-M1 실측 5 —
  두 수를 한 줄에)
- 기억: `docs/decisions/project_search_hangul.md`(SH의 것. FP의 기억은
  서브프로젝트를 닫을 때 새로 쓴다)

**검사 번호는 착수 전에 세어서 확인했다** — `vt_test`가 54까지, `input_test`가
57까지, `hangul/check.sh`가 19a까지다. 위 표의 번호가 그 다음이다.
