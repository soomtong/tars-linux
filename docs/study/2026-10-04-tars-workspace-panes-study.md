---
aliases: [워크스페이스 패널 학습 가이드, WP 스터디]
tags:
  - study
  - terminal
  - layout
  - pty
  - workspace
---

# TARS Workspace Panes 학습 가이드

> 대상: 화면 하나였던 terminal이 어떻게 셸 여럿(워크스페이스 × 패널)을
> 담게 됐는지, 어느 코드가 무엇을 맡는지 바닥부터 이해하기.
> 원문: `docs/specs/2026-10-03-tars-workspace-panes-design.md`,
> plan `docs/plans/2026-10-03-tars-workspace-panes-wp-m0.md` · `-m1.md` · `-m2.md`,
> 기억 `docs/decisions/project_workspace_panes.md`.
> 예제는 이 저장소의 실제 코드에서 가져왔다 — 파일명:줄번호로 표기했다
> (2026-10-04 `778f5bb` 기준).

---

## 한줄 요약

패널(pane) 하나는 "PTY + `vt.Screen` + 격자 안 사각형" 셋을 묶은 값이고,
워크스페이스(workspace)는 그 패널들을 이진 트리로 배치한 것이며, `main.zig`의
루프는 포커스 패널 하나만 보고 돌기 때문에 셸이 하나에서 72개가 되어도 키 ·
copy mode · 프롬프트 · 덤프 코드는 이름만 바뀌었다.

---

## 1. 왜 이것이 필요한가?

### 문제: 셸이 하나뿐이었다

TF(Terminal Foundation) 이후 TARS의 화면은 셸 하나였다. 프로세스 하나가
디스플레이를 독점하고(`/dev/dri/card0`), PTY 하나를 열어 셸 하나를 띄우고,
그 출력을 `vt.Screen` 하나가 해석해 프레임버퍼에 그렸다. 둘을 나란히 보려면
셸 안에서 tmux를 띄워야 하는데, 그러면 터미널 에뮬레이터가 두 겹이 된다 —
우리 vt(ghostty) 위에 tmux의 vt가 한 겹 더 얹히고, kitty graphics(TG)와
자식의 질의 답(TQ)이 그 겹에서 끊긴다.

### 해법: 렌더러 층에서 N개로

분할과 워크스페이스를 우리 렌더러 층에서 하면 겹이 안 생긴다. 패널마다
`vt.Screen`이 하나씩 서므로, 각 패널은 이미 되는 것(256색 · 스크롤백 · copy
mode · 한글 조합 · 이미지 · 질의 답)을 그대로 가진다. 그래서 이 서브프로젝트의
본론은 새 기능이 아니라 "하나였던 것을 N개로 만드는 구조 변경"이었다.

### 모델은 iTerm2 그대로

| 이름 | 무엇 | 한도 |
|---|---|---|
| 워크스페이스 | iTerm2의 탭. 패널 트리 하나와 포커스 하나 | 9 (`Cmd+1~9`가 번호) |
| 패널 | 셸 하나 | 워크스페이스당 8 |
| 분할 | 패널 하나를 둘로 가른다. 오른쪽 또는 아래, 비율은 영영 1/2 | 이진 트리 |

| 키 | 동작 |
|---|---|
| `Cmd+D` / `Cmd+Shift+D` | 포커스 패널을 세로/가로로 갈라 오른쪽/아래에 새 셸 |
| `Cmd+W` | 포커스 패널의 셸에 SIGHUP. 셸이 끝나면 패널이 닫힌다 |
| `Cmd+]` / `Cmd+[` | 다음/이전 패널로 포커스(끝에서 감긴다) |
| `Cmd+T` | 새 워크스페이스를 끝에 만든다 |
| `Cmd+1`~`9` | 있는 워크스페이스로. 없으면 아무 일도 안 한다 |

손이 아는 키를 바꾸지 않는다는 것이 이유다 — copy mode 진입 키를
iTerm2(`Cmd+Shift+C`)에서 가져온 것과 같다.

---

## 2. 근본적인 동작 원리

### 2.1 세 층과 그 사이의 경계

```
  evdev ──▶ input.zig ──▶ main.zig ──▶ layout.zig
   (키)      (Action)      (루프)        (트리 · 사각형)
                              │
                              ├──▶ pty.zig    (spawn · resize · hangup · close)
                              ├──▶ vt.zig     (Screen: feed · cells · resize · focused)
                              └──▶ drm.zig    (프레임버퍼)
```

- `input.zig`는 키를 `Action`으로 바꾼다. 패널 명령은 `Action.pane`
  (`input.zig:352`)이고 payload 없는 enum이다(`input.zig:364`). `input.zig`는
  `vt.zig`도 `layout.zig`도 import하지 않는다 — "Cmd+D가 눌렸다"까지만 안다.
- `layout.zig`는 트리와 사각형 산수만 한다. 시스템 콜도 ghostty도 모르는
  순수 모듈이라 `layout_test`가 호스트에서 초 단위로 돈다(`status.zig`가
  따로 서는 이유와 같다).
- `main.zig`가 둘을 잇고 PTY · Screen · 프레임버퍼를 다룬다. 패널 명령의
  뜻("가른다" = 트리를 바꾸고 → 기존 패널 크기를 고치고 → 새 셸을 띄운다)은
  여기에만 있다.

### 2.2 패널과 워크스페이스는 값이다

```zig
// main.zig:1126
const Pane = struct {
    screen: *vt.Screen,      // WP 전 main의 변수 `screen`
    session: pty.Session,    // WP 전 main의 변수 `session`
    rect: layout.Rect,       // 격자 안의 자리(셀 단위). 하나뿐이면 격자 전체
};

// main.zig:1137
const Workspace = struct {
    tree: layout.Tree,
    panes: [layout.MAX_LEAVES]?Pane,   // 잎 번호로 인덱싱
    focus: u4,                         // 키보드가 가는 잎 번호
};

var workspaces: [MAX_WORKSPACES]?Workspace;   // 아홉 칸, 쓰는 만큼만 non-null
var current: usize;                           // 지금 보이는 워크스페이스
```

동적 할당이 없다. 워크스페이스 아홉 · 패널 여덟 · 트리 노드 열다섯이 전부
고정 배열이고, 쓰이지 않는 칸은 `null` 또는 `.free`다. "언제 해제하는가"가
없어진다 — `find_buf`가 128바이트 고정인 것과 같은 판단이다. `vt.Screen`만
`alloc.create`로 만드는데, 그것은 WP 전부터 그랬다(ghostty 상태가 크다).

### 2.3 트리 — 잎 번호와 노드 번호를 가른다

```zig
// layout.zig:28
const Node = union(enum) {
    free,
    leaf: u4,                                           // 잎 번호 0..7
    split: struct { dir: Dir, first: u4, second: u4 },  // 자식 노드 번호
};

pub const Tree = struct {
    nodes: [15]Node,   // 잎 8 + 내부 7
    root: ?u4,
    ...
};
```

노드 번호(0..14)와 잎 번호(0..7)가 다른 것이 요점이다. `Workspace.panes`가
잎 번호로 인덱싱되므로 분할해도 기존 패널의 번호가 안 바뀌어야 한다 — 바뀌면
`focus`가 조용히 다른 패널을 가리킨다.

분할(`layout.zig:58`)은 옛 잎의 노드를 그 자리에서 내부 노드로 바꾸고, 옛
잎과 새 잎을 빈 노드 둘로 내린다. 부모가 가리키던 번호가 그대로라 부모를
고칠 일이 없다.

```
  분할 전             Cmd+D 뒤                    Cmd+Shift+D 뒤(잎 1에서)
  n0: leaf 0          n0: split(right, n1, n2)    n0: split(right, n1, n2)
                      n1: leaf 0                  n1: leaf 0
                      n2: leaf 1                  n2: split(below, n3, n4)
                                                  n3: leaf 1
                                                  n4: leaf 2
  ┌──────────┐        ┌─────┬─────┐               ┌─────┬─────┐
  │    0     │        │  0  │  1  │               │  0  │  1  │
  │          │        │     │     │               │     ├─────┤
  │          │        │     │     │               │     │  2  │
  └──────────┘        └─────┴─────┘               └─────┴─────┘
```

닫기(`layout.zig:85`)는 반대다 — 형제의 내용을 부모 노드에 덮고 형제의 옛
노드를 비운다. 할아버지가 가리키던 번호가 그대로다.

사각형(`layout.zig:106`)은 뿌리부터 내려가며 재귀로 나눈다. 가로 `n`칸을
세로로 가르면 구분선 한 칸을 빼고 `first = (n - 1) / 2`, `second = n - 1 -
first`. 155칸이면 77 + 1 + 77이다. 트리는 자기 크기를 모르므로 `split`이
격자 전체 사각형을 받아 "가를 수 없을 만큼 작다"(가르는 방향이 3칸 미만)를
판정한다 — 아래로만 다섯 번 가르면 47 → 23 → 11 → 5 → 2로 실제로 닿는
경계다.

### 2.4 루프 — 포커스 패널 하나만 본다

WP 전 `main.zig`의 루프는 `screen` · `session` 변수를 직접 썼다. 지금은 매
바퀴 두 가지를 한다.

1. `poll`의 fd 배열을 다시 짓는다(`main.zig:1564` 근처). 키보드 하나 + 모든
   워크스페이스의 모든 패널. 포커스 없는 워크스페이스의 PTY도 읽어야 한다 —
   안 읽으면 그 셸이 출력 버퍼에 막혀 멈춘다. 73칸을 채우는 비용은 없고,
   "언제 고쳐 쓰는가"를 따로 들 필요가 없다.
2. `ws = &workspaces[current].?`, `focus = &ws.panes[ws.focus].?`를 구한다.
   키 입력 · copy 루프 · 프롬프트 · 상태 줄 · 덤프가 보는 것은 전부 `focus`다.

```
   poll ─▶ 키보드 revents ──▶ readKeys ──▶ bytes → focus.session (PTY)
                                       ├─▶ scrolls → focus.screen
                                       ├─▶ copies  → focus.screen
                                       └─▶ panes   → ws.tree / workspaces   ← 새 통로
        ─▶ 패널마다 revents ─▶ readSome ─▶ pane.screen.feed  (포커스 아니어도)
                                 └─ EOF ─▶ 그 패널 닫기(아래 2.6)
        ─▶ needs_redraw ─▶ render(모든 패널, 포커스는 마지막) ─▶ 덤프(포커스)
```

그래서 M0(구조만 바꾼 milestone)의 판정이 "눈에 보이는 변화 0 · `screen>`
로그가 바이트까지 같다"였다. 패널 하나면 `rect`가 격자 전체라 산수 결과가
WP 전과 같다.

### 2.5 분할 — 트리 · 크기 · 새 셸의 순서

```zig
// main.zig:1771 — 패널 명령 루프
.split_right, .split_below => {
    const leaf = ws.tree.split(ws.focus, dir, whole) orelse {
        std.debug.print("terminal: pane> split refused\n", .{});
        continue;
    };
    const rs = try applyLayout(ws, whole);        // 1. 기존 패널 크기 고치기
    ws.panes[leaf] = try spawnPane(..., rs[leaf]); // 2. 새 셸
    ws.focus = leaf;                               // 3. 포커스
},
```

`applyLayout`(`main.zig:1226`)은 "rect가 바뀐 패널만 다시 잰다"는 규칙
하나다. 분할 뒤(옛 패널이 작아진다)와 닫기 뒤(형제가 커진다)를 같은 함수가
덮는다. 다시 재는 것은 둘이다.

- `vt.Screen.resize`(`vt.zig:485`) → ghostty `Terminal.resize(alloc, .{ .cols,
  .rows, .cell_size_px })`. `cell_size_px`를 함께 주는 이유는 TG 결정 2 —
  그것이 `width_px` · `height_px`를 채우고 kitty 이미지와 `CSI 14t`의 답이 그
  값을 본다. 라이브러리가 줄을 다시 접는다(reflow). copy mode면 먼저
  `copyExit()` — 접기가 tracked pin을 옮기는 것은 CM-M1이 가지치기에서 배운
  병과 같다.
- `pty.resize`(`pty.zig:63`) → `ioctl(TIOCSWINSZ)`. 커널이 자식에게 SIGWINCH를
  보내므로 우리가 시그널을 만들 자리는 없다.

`spawnPane`(`main.zig:1178`)은 부팅의 첫 패널과 분할이 같이 부른다. PTY의
winsize와 `Screen`의 크기가 같은 `rect`에서 나오므로 셸이 아는 폭과 우리가
그리는 폭이 어긋날 수 없다.

### 2.6 닫기 — 길은 하나다

```
  Cmd+W ──▶ pty.hangup(session)  = kill(child_pid, SIGHUP)   (main.zig:1793)
                 │
                 ▼  셸이 끝나 slave가 전부 닫힌다
          PTY master EOF ──▶ pane> closed  (main.zig:1855)
                              pty.close    = close(master_fd) + waitpid
                              screen.deinit · panes[leaf] = null
                              focus = tree.heir(leaf)   (지우기 전에 묻는다)
                              tree.remove(leaf) · applyLayout
                              워크스페이스의 마지막 패널이면 → 워크스페이스 삭제
                              전체의 마지막 패널이면      → terminal 종료(init이 되살린다)
```

`Cmd+W`는 SIGHUP 한 줄이고 닫는 코드는 EOF 경로에만 있다. 그래서 `exit`를
친 것과 `Cmd+W`가 같은 코드를 지난다. SIGHUP인 이유는 SL이 잰 것 — zsh ·
bash는 SIGTERM을 무시하고 SIGHUP에는 끝난다. `waitpid`로 거두는 이유는 WP
전에는 셸이 끝나면 terminal도 끝나 좀비가 문제가 안 됐지만, 이제 terminal이
살아 있기 때문이다.

워크스페이스를 지우면 배열이 한 칸 당겨진다(`main.zig:1871`). 그 바퀴에
지은 `fd_panes`의 `ws` 번호가 낡으므로 지운 직후 PTY 루프를 `break`한다 —
안 읽은 출력은 다음 `poll`이 다시 알린다.

### 2.7 그리기 — 원점 하나, 포커스는 마지막

```zig
// main.zig:1154
fn paneOrigin(rect: layout.Rect) Origin {
    return .{
        .x = GRID_X + @as(u32, rect.col) * CELL_W,
        .y = GRID_Y + @as(u32, rect.row) * ROW_HEIGHT,
    };
}
```

WP 전의 `GRID_X + col * CELL_W`가 `GRID_X + (rect.col + col) * CELL_W`가 된
자리다. 그리는 함수(`renderPane` · `drawPrompt` · `drawImages`)와 프레임버퍼를
되읽는 덤프(`dumpStyles` · `dumpInk` · `dumpImages`)가 전부 이 함수를 부르므로
둘이 다른 원점을 볼 수 없다.

렌더는 셋으로 갈렸다 — `renderBackdrop`(`main.zig:360`, 여백 fill + 구분선)
· `renderPane`(`:382`, 패널 하나의 배경 · 이미지 · 글리프) · `renderFinish`
(`:433`, 프롬프트 + 상태 줄 + `present`). 포커스 패널을 마지막에 그리는
이유는 `cell_buf` · `img_buf`가 하나뿐이라 그래야 덤프가 포커스 패널의 것을
읽기 때문이다.

구분선은 `tree.separators`(`layout.zig:121`)가 내부 노드마다 사각형 하나씩
돌려주고 `renderBackdrop`이 셀 단위로 칠한다. 격자를 통째로 구분선 색으로
칠하고 패널이 덮게 둘 수 없다 — `cells()`는 글자도 색도 없는 셀을 안
내보내므로 빈 셀이 구분선 색이 된다. 색은 전용 `SEPARATOR`(`main.zig:77`)다.
게이트가 그 색만 세어 "구분선이 그 자리에 그려졌는가"를 판정한다(`sep ink`).

셸 커서는 포커스 패널에만 보인다 — `Screen.focused`(`vt.zig:375`)가 거짓이면
`cells()`가 커서 반전을 건너뛴다. 렌더 직전에 `pane.screen.focused = (leaf ==
ws.focus)`로 매 프레임 맞춘다(상태를 두 자리에 두지 않는다).

### 2.8 키 — Meta 분기의 Shift switch

```zig
// input.zig:1106
if (self.shifted()) return switch (code) {
    c.KEY_C => blk: { self.mode = .copy; break :blk .{ .copy = .enter }; },
    c.KEY_D => .{ .pane = .split_below },
    else => null,
};
return switch (code) {
    c.KEY_D => .{ .pane = .split_right },
    c.KEY_W => .{ .pane = .close },
    c.KEY_RIGHTBRACE => .{ .pane = .focus_next },
    c.KEY_LEFTBRACE => .{ .pane = .focus_prev },
    c.KEY_T => .{ .pane = .new_workspace },
    c.KEY_1 => .{ .pane = .workspace_1 },
    ...
};
```

CM이 "Meta 분기 안에서 Shift를 한 번 더 보는 예외는 하나뿐이어야 한다"고
했는데 `Cmd+Shift+D`가 둘째였다. 예외를 `if`로 하나씩 늘리지 않고 switch
하나에 나란히 적었다 — 셋째가 오면 한 줄이다. 대가로 `Cmd+Shift+←·→·Backspace`
가 바뀌었다(전에는 Shift를 무시하고 `0x01` 등, 지금은 맨 키). 사용자가
그대로 두기로 했다.

copy mode 안에서는 이 키들이 아무 일도 안 한다. `handleKey`의 copy 분기가
`chord`보다 앞이라 copy 표가 먼저 삼키기 때문이고, 코드를 안 고치고 그렇게
됐다. 덕분에 "copy mode인 패널을 떠났다 돌아오면 모드가 어떤 상태인가"라는
물음이 안 생긴다.

### 2.9 상태 줄 — 둘 이상일 때만 `W2`

`statusText(state, copy, workspace: ?u8, buf)`(`status.zig:125`). 워크스페이스가
둘 이상일 때만 `CAPS` 뒤 · `COPY` 앞에 `  W2`가 붙는다. 하나뿐이면 글자도
픽셀도 WP 전과 같아서 hangul 체인의 `text=` 비교와 `caps ink` 기준값이 안
바뀐다 — CI가 `COPY`를 켜질 때만 둔 것과 같은 규칙이다. `drawStatus`는
꼬리에서 `CAPS`의 시작을 세므로 꼬리 둘(`W2` · `COPY`)의 길이만큼 물러난다.

---

## 3. 핵심 개념 정리

| 개념 | 어디 | 요점 |
|---|---|---|
| `Pane` | `main.zig:1126` | 셸 하나 = PTY + Screen + rect. 값이고 고정 배열의 칸 |
| `Workspace` | `main.zig:1137` | 트리 + 패널 여덟 + 포커스. 번호는 자리(둘째를 닫으면 셋째가 둘째) |
| `layout.Tree` | `layout.zig:34` | 노드 15 고정. 잎 번호 ≠ 노드 번호. `split` · `remove` · `rects` · `separators` · `next` · `prev` · `heir` |
| `Action.pane` | `input.zig:352` | payload 없는 enum 열넷. `readKeys`가 `scrolls` · `copies`처럼 순서대로 모은다 |
| `applyLayout` | `main.zig:1226` | rect가 바뀐 패널만 `Screen.resize` + `pty.resize` |
| `paneOrigin` | `main.zig:1154` | 셀 → 픽셀 원점. 그리기와 덤프가 같은 함수 |
| `Screen.focused` | `vt.zig:375` | 거짓이면 커서 반전 없음. 기본 참이라 `vt_test` 안 바뀜 |
| `pty.hangup` · `close` | `pty.zig:79` · `:91` | SIGHUP / `close` + `waitpid`. `kill` · `waitpid`는 `extern "c"` |
| `pane>` 줄 | `main.zig:1274` | `ws=1/2 panes=2 focus=1 rect=78,0 77x47 sep ink=6016`. 서명이 바뀐 프레임에만 |
| `pane/check.sh` | 열여덟번째 체인 | 검사 열여섯. 폭은 `$COLUMNS`로, 생존은 `spawned child pid` 수로 |

개념 사이의 관계 — 트리는 "누가 어디에"만 알고(`layout`), 패널은 "무엇이"를
들고(`Pane`), 루프는 "지금 누구에게"를 정한다(`focus`). 셋이 갈려 있어서
트리 산수는 부팅 없이 검사하고, 패널은 값으로 옮기며, 루프는 WP 전 코드를
이름만 바꿔 쓴다.

---

## 4. 이해도 확인 Q&A

### Q1. `Workspace.panes`를 잎 번호로 인덱싱하는데, 왜 트리의 노드 번호를 그대로 패널의 이름으로 쓰지 않는가?

A: 분할이 옛 잎의 노드를 내부 노드로 바꾸고 잎을 새 노드로 내리기 때문이다.
노드 번호를 이름으로 쓰면 분할할 때마다 기존 패널의 이름이 바뀌고, 그것을
들고 있던 `focus`가 조용히 다른 패널을 가리킨다. 잎 번호를 따로 두면 분할이
기존 패널을 한 번도 건드리지 않는다 — 부모가 가리키던 노드 번호도 그대로라
부모를 고칠 일이 없다.

### Q2. `Cmd+W`가 패널을 직접 닫지 않고 SIGHUP만 보내는 이유는? 자식이 SIGHUP을 무시하면 어떻게 되는가?

A: 닫는 길을 하나로 두기 위해서다. 셸에 `exit`를 치면 PTY가 EOF를 내고 그
경로가 패널을 닫는데, `Cmd+W`도 셸을 끝내기만 하면 같은 경로를 지난다 —
닫기 코드가 두 벌이면 한쪽만 고치는 사고가 난다. 자식이 SIGHUP까지 막으면
패널이 안 닫히고, 그때는 사람이 `exit`를 친다. 3초 뒤 SIGKILL로 치우는
것보다 안 닫히는 것이 보이는 쪽을 골랐다.

### Q3. 분할 직후 기존 패널에서 다시 재야 하는 것이 둘인데, 하나만 하면 각각 어떤 증상이 나는가?

A: `Screen.resize`만 하고 `pty.resize`(TIOCSWINSZ)를 빼면 셸은 여전히 155칸이라
믿고 프롬프트와 긴 줄을 그 폭으로 그린다 — 우리 화면은 77칸에서 접는다.
짧은 `echo` 출력은 똑같이 보여서 M1의 반사실이 plan의 검사를 통과했고, fish의
`$COLUMNS`를 찍게 하자 `left-side 155`로 잡혔다. 반대로 `pty.resize`만 하고
`Screen.resize`를 빼면 셸은 77칸으로 그리는데 우리 Screen은 155칸이라 셀이
패널 사각형 밖으로 넘친다.

### Q4. 포커스 없는 워크스페이스의 PTY도 매 바퀴 읽는 이유는? 읽기만 하고 그리지 않는 것이 왜 괜찮은가?

A: 안 읽으면 그 셸이 출력 버퍼(PTY의 커널 버퍼)에 막혀 `write`에서 멈춘다 —
돌아왔을 때 그제야 깨어나는 셸을 보게 된다. 읽어서 `feed`하면 `vt.Screen`이
스크롤백에 쌓아 두고, 그 워크스페이스로 돌아온 프레임에 `cells()`가 지금 상태를
준다. 그리는 것은 보이는 워크스페이스뿐이라 비용이 늘지 않는다.

### Q5. 격자 전체를 구분선 색으로 칠한 뒤 패널이 덮게 두면 코드가 더 짧다. 왜 그렇게 하지 않았는가?

A: `cells()`가 글자도 색도 없는 셀을 안 내보내기 때문이다(TR 결정 3 — 그릴 것이
있는 셀만). 그러면 빈 셀의 자리는 아무도 안 덮어서 구분선 색이 그대로 보인다.
WP 전에 여백 색(`MARGIN_COLOR`)과 기본 배경색이 같은 값이라 이 성질이 안
드러났을 뿐이다. 그래서 구분선은 트리에서 사각형 목록으로 꺼내 따로 칠한다.

### Q6. 워크스페이스를 지운 직후 PTY 루프를 `break`하는 이유는? 안 하면 어떤 고장이 나는가?

A: `fd_panes`는 바퀴 시작에 지은 배열이고 각 항목이 `ws` 번호를 든다.
워크스페이스를 지우면 배열이 한 칸 당겨져서 같은 바퀴의 뒤 항목이 든 `ws`
번호가 낡는다 — 그 항목에 EOF가 함께 왔다면 엉뚱한 워크스페이스의 트리에서
잎을 지운다. `break`하면 안 읽은 출력은 커널 버퍼에 남아 다음 `poll`이
다시 알리므로 잃는 것이 없다.

### Q7. M0은 눈에 보이는 변화가 0인 milestone이었다. 그런 milestone을 따로 두고 체인 넷을 돌린 값은 무엇인가?

A: 구조 변경과 기능 추가를 한 번에 하면 체인이 빨개졌을 때 "구조를 잘못
옮겼다"와 "새 기능이 틀렸다"가 안 갈린다. M0은 `screen` → `focus.screen`,
원점 산수 → `paneOrigin`, fd 둘 → fd 배열이라는 세 변경을 "패널 하나면 WP
전과 바이트까지 같다"로 못 박았다. 그 뒤 M1의 빨강은 전부 새 기능의 것이다.

### Q8. "terminal이 살아 있다"를 `pane> ws=1/1 panes=1` 줄로 판정하면 왜 틀리는가?

A: terminal이 죽으면 init이 되살리고, 되살아난 terminal의 첫 프레임이 정확히
그 줄을 찍는다. M2의 반사실(워크스페이스를 지우는 갈래를 끔)에서 빈 트리의
워크스페이스가 남아 렌더 앞 `ws.panes[ws.focus].?`에서 죽었는데, plan이
기대한 `wait_for_pane 'ws=1/1 panes=1'`은 새 terminal의 줄로 통과했다. 생존은
`spawned child pid` 줄의 개수로 본다 — 부팅의 첫 패널만 그 줄을 찍고 분할은
안 찍기 때문에 그 수는 "terminal이 몇 번 떴는가"다.

### Q9. 글자가 맞는데 색만 밀리는 고장은 어디서 생기고 게이트는 무엇으로 잡는가?

A: `drawStatus`가 꼬리에서 `CAPS`의 시작을 세는데, `W2` 칸의 길이만큼 안
물러나면 `CAPS` 넉 자가 앞 세 칸의 색으로, `W2`가 `CAPS`의 색으로 그려진다.
`text=`는 맞다. 게이트는 `CAPS` 칸의 켜짐/꺼짐 색 픽셀 수(`caps ink off=`)가
워크스페이스 하나일 때(87)와 같은지 본다 — 반사실에서 49(`W2` 두 글자의
픽셀)로 잡혔다. CI가 `copy ink`로 같은 병을 잡은 것과 같은 모양이다.

---

## 5. 더 알아보기

### 이 저장소 안에서

- `docs/specs/2026-10-03-tars-workspace-panes-design.md` — 결정 아홉 · 위험
  여섯 · 체인 검사 표. 2.x 절의 "왜"가 전부 여기서 왔다.
- `docs/plans/2026-10-03-tars-workspace-panes-wp-m1.md` "M1이 실측한 것" —
  `$COLUMNS` 반사실, 렌더를 셋으로 가른 이유, 패널 명령 루프가 `keys.redraw`
  뒤인 이유(조합 중인 한글이 떠나는 패널에 남지 않게).
- `docs/plans/2026-10-03-tars-workspace-panes-wp-m2.md` "M2가 실측한 것" —
  되살아난 terminal의 `pane>` 함정, `PaneSig`에 `total`이 든 이유.
- `docs/decisions/project_copy_mode.md` — reflow가 pin을 옮기는 병의 원형
  (가지치기).
- `docs/decisions/project_shutdown_signals.md` — SIGHUP을 고른 근거.
- `pane/check.sh` — 검사 열여섯. 음성 검사(포커스를 옮긴 뒤 옛 패널의 글자가
  마지막 프레임에 없다 · copy mode 안의 `Cmd+D`가 아무 일도 안 한다)가 값이다.

### 바깥에서

- iTerm2의 Split Panes · Tabs 문서 — 키와 모델의 출처.
- tmux의 `layout-custom` 문자열 — 같은 이진 트리를 문자열로 적는 모양.
  세션 복원(WP 비목표)을 열게 되면 참고가 된다.
- `tty_ioctl(4)`의 `TIOCSWINSZ` · `signal(7)`의 SIGWINCH — 크기 알림의 커널
  쪽 반.
- ghostty `src/terminal/Terminal.zig`의 `resize` — reflow가 무엇을 보존하고
  무엇을 버리는지.

### 열지 않은 것

- WP-M3 방향 포커스(`Cmd+Option+화살표`). `Tree.neighbor(leaf, dir)` — 포커스
  사각형의 변과 겹치는 이웃 중 가장 가까운 것. 순환만으로 네 패널을 다니는
  것이 불편해지면 연다.
- 패널 간 클립보드. 지금은 `vt.Screen`마다 하나라 한 패널에서 `y`한 것을
  다른 패널에 `Cmd+V`할 수 없다. 클립보드를 `main.zig`로 올리면 된다.
