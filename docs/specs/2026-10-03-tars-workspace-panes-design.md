# TARS Workspace Panes — Design

Date: 2026-10-03
Status: 진행 중. WP-M0(구조) · WP-M1(분할 · 닫기 · 순환)이 2026-10-03에
끝났다 — plan `docs/plans/2026-10-03-tars-workspace-panes-wp-m0.md` ·
`-wp-m1.md`의 "실측한 것" 절. 열여덟번째 체인 `pane/check.sh`가 섰고 루트
게이트 18체인 3/3. 다음은 WP-M2(워크스페이스).

사용자의 요청(2026-10-03)에서 시작한다. "Cmd+1~9 workspace 전환, Cmd+D ·
Cmd+Shift+D pane split" — 같은 날 "열린 패널을 닫는 것은 Cmd+W", "패널
포커스 이동 기능도 필요하겠지", "Cmd+T로 새 탭을 여는 것도 있구나"가
더해졌다.

## 한 줄 요약

화면 하나가 여러 셸을 담는다. 워크스페이스(= 탭)가 아홉까지 있고, 각
워크스페이스는 패널을 이진 분할로 여덟까지 나눈다. 패널 하나가 셸 하나다 —
PTY · `vt.Screen` · 격자 안의 사각형 하나씩. 키보드는 포커스 패널 하나에만
간다.

```
┌──────────────────────┬──────────────────────┐
│ root@(none) ~# ls    │ root@(none) ~# top   │
│ vendor  src          │ ...                  │
│ root@(none) ~# █     ├──────────────────────┤
│                      │ root@(none) ~#       │
│                      │                      │
└──────────────────────┴──────────────────────┘
  EN  신세벌 PCS  쿼티  CAPS  W2                 ← 워크스페이스 둘 이상이면
```

## 왜 지금인가

TARS의 화면은 지금까지 셸 하나다(TF design 결정 1 — 프로세스 하나가
디스플레이를 독점한다). 셸 안에서 둘을 보려면 tmux가 있어야 하는데, 그
tmux는 또 하나의 터미널 에뮬레이터라 우리 vt(ghostty) 위에 vt를 한 겹 더
얹는다 — kitty graphics(TG)와 질의 답(TQ)이 그 겹에서 끊긴다.

분할과 워크스페이스를 우리 렌더러 층에서 하면 그 겹이 안 생긴다. 패널마다
`vt.Screen` 하나가 서고, 각 패널이 이미 되는 것(색 · 스크롤백 · copy mode ·
한글 · 이미지 · 질의 답)을 그대로 가진다. 그래서 이 서브프로젝트의 본론은
새 기능이 아니라 "하나였던 것을 N개로 만드는 구조 변경"이다 — `main.zig`가
`screen`과 `session` 하나를 변수로 들던 것을 패널의 집합으로 바꾸는 일.

## 모델

iTerm2의 모양을 그대로 따른다. 사용자가 copy mode 진입 키를 iTerm2
(Cmd+Shift+C)에서 가져온 것과 같은 이유다 — 손이 아는 키를 바꾸지 않는다.

| 이름 | 무엇 | 한도 |
|---|---|---|
| 워크스페이스 | iTerm2의 탭. 패널의 트리 하나와 포커스 하나 | 9 (Cmd+1~9가 번호다) |
| 패널 | 셸 하나. PTY · `vt.Screen` · 격자 안의 사각형 | 워크스페이스당 8 |
| 분할 | 패널 하나를 둘로 가른다. 오른쪽 또는 아래 | 이진 트리, 절반씩 |

### 키 표

| 키 | 동작 | 들어가는 milestone |
|---|---|---|
| `Cmd+D` | 포커스 패널을 세로로 갈라 오른쪽에 새 셸 | M1 |
| `Cmd+Shift+D` | 포커스 패널을 가로로 갈라 아래에 새 셸 | M1 |
| `Cmd+W` | 포커스 패널의 셸에 SIGHUP. 셸이 끝나면 패널이 닫힌다 | M1 |
| `Cmd+]` · `Cmd+[` | 다음 · 이전 패널로 포커스(트리의 왼쪽→오른쪽 순, 끝에서 감긴다) | M1 |
| `Cmd+T` | 새 워크스페이스를 끝에 만들고 그리로 간다 | M2 |
| `Cmd+1`~`Cmd+9` | 그 번호의 워크스페이스로. 없으면 아무 일도 안 한다 | M2 |
| `Cmd+Option+←↑↓→` | 그 방향의 이웃 패널로 포커스 | M3(사용자가 고른다) |

Cmd+1~9가 없는 워크스페이스를 만들지 않는 것에 뜻이 있다. Cmd+T가 생기면서
"만든다"의 자리가 하나로 모였다 — 두 자리에서 만들면 "Cmd+5를 눌렀는데 셸이
하나 더 떴다"가 실수의 결과인지 의도인지 사람이 모른다.

워크스페이스 번호는 자리다. 셋 중 둘째를 닫으면 셋째가 둘째가 된다
(iTerm2와 같다). 번호를 고정하면 "W1 W3"처럼 빈 자리가 생기고, 그것을
Cmd+1~9와 맞추려면 번호를 따로 들어야 한다.

## 결정

### 결정 1 — 패널은 `Pane` 하나로 묶이고, `main.zig`는 포커스 패널만 안다

지금 `main.zig`가 변수로 든 것 셋이 그대로 패널의 필드가 된다.

```zig
const Pane = struct {
    screen: *vt.Screen,      // 지금의 `screen`
    session: pty.Session,    // 지금의 `session`
    rect: layout.Rect,       // 격자 안의 자리(셀 단위). 하나뿐이면 격자 전체
};
```

키 입력 분기(`fds[0]`), copy 루프, 프롬프트 · 상태 줄 · 렌더 · 덤프가 보는
것은 전부 "포커스 패널"이다. 그래서 그 코드는 `screen` → `focus.screen`으로
이름만 바뀌고 모양이 안 바뀐다. 바뀌는 자리는 둘뿐이다 — `poll`이 패널마다
fd 하나씩을 보는 것과, `render`가 패널마다 한 번씩 도는 것.

패널 하나짜리 워크스페이스 하나로 부팅하면 지금과 같은 화면이어야 한다.
그것이 WP-M0의 판정이다 — 눈에 보이는 변화가 0이고 기존 체인이 전부 선다.

### 결정 2 — 레이아웃 산수는 `layout.zig`에 순수하게 두고 호스트에서 검사한다

트리와 사각형 산수는 시스템 콜도 ghostty도 모른다. `status.zig`가 따로
서는 이유(IS 결정 5)와 같다 — 순수하면 `layout_test`가 컨테이너에서 초
단위로 돌고, 분할 여덟 · 닫기 · 순환의 경우를 전부 부팅 없이 본다.

```zig
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };
pub const Dir = enum { right, below };

pub const Tree = struct {
    // 노드 풀은 고정이다. 잎 8 + 내부 7 = 15. 동적 할당이 없고 "언제
    // 해제하는가"가 없다 — find_buf가 128바이트 고정인 것과 같은 판단.
    nodes: [15]Node,
    root: ?u4,
    pub fn split(self: *Tree, leaf: u4, dir: Dir, whole: Rect) ?u4;  // 새 잎의 번호. 꽉 찼거나 너무 작으면 null
    pub fn remove(self: *Tree, leaf: u4) void;           // 형제가 부모 자리로 올라간다
    pub fn rects(self: *const Tree, whole: Rect, out: []Rect) void;  // 잎마다 사각형
    pub fn next(self: *const Tree, leaf: u4) u4;          // 왼쪽→오른쪽 순환
    pub fn prev(self: *const Tree, leaf: u4) u4;
};
```

사각형 산수: 가로 `n`칸을 세로로 가르면 구분선 한 칸을 빼고 `first = (n - 1)
/ 2`, `second = n - 1 - first`. 홀수면 오른쪽(아래)이 한 칸 크다. 비율을
안 둔다 — 드래그가 없는 시스템에서 비율은 영영 1/2이다.

구분선은 셀 한 칸(세로) · 한 줄(가로)이다. 픽셀 하나짜리 선은 폭 2 글자의
spacer 규칙과 셀 격자를 흐리게 한다. 색은 전용 `SEPARATOR`(`0x00405060` —
여백 `0x102030`보다 밝고 상태 줄 색 셋과 다르다). 전용 색인 이유는 CI 결정
3과 같다 — 게이트가 그 색만 세어 "구분선이 그 자리에 그려졌는가"를 판정한다.

### 결정 3 — 크기 바꾸기는 `Screen.resize`와 `pty.resize` 둘이고, 영향받는 패널의 copy mode는 닫는다

분할하면 기존 패널이 작아지고, 닫으면 형제가 커진다. 둘 다 같은 함수 둘을
부른다.

- `vt.Screen.resize(cols, rows)` → `term.resize(alloc, .{ .cols, .rows,
  .cell_size_px })`(`Terminal.zig:3775`). `cell_size_px`를 함께 주는 이유는
  TG 결정 2다 — 그것이 `width_px` · `height_px`를 다시 채우고 kitty 이미지와
  `CSI 14t`의 답이 그 값을 본다. 라이브러리가 줄을 다시 접는다(reflow).
- `pty.resize(fd, cols, rows)` → `ioctl(TIOCSWINSZ)`. 커널이 자식에게
  SIGWINCH를 보내므로 우리가 시그널을 만들 자리는 없다. `c_pty` 번역에
  `sys/ioctl.h`가 이미 있다.

영향받는 패널이 copy mode면 먼저 `copyExit()`한다. 접기가 tracked pin을
옮기는 것은 CM-M1이 가지치기에서 배운 것과 같은 병이고(선택이 조용히 다른
자리를 가리킨다), 그것을 감시하느니 모드를 닫는 쪽이 사람에게도 분명하다.
포커스 패널에서는 애초에 못 일어난다 — copy mode 안에서는 패널 명령이
`chord`에 안 닿는다(결정 4).

### 결정 4 — 키는 포커스 패널에만 가고, copy mode 안에서는 패널 명령이 없다

`handleKey`는 copy 분기(`input.zig:1333`)가 `chord`(1406)보다 앞이다. 그래서
copy mode에서 Cmd+D를 누르면 copy 표가 그 키를 삼키고 아무 일도 안 한다.
이것을 고치지 않는다 — "copy mode는 키를 전부 삼킨다"(CM 결정 3)의 한 경우이고,
Esc로 나온 뒤 누르면 된다. 덕분에 "copy mode인 패널에서 다른 패널로
갔다가 돌아오면 모드가 어떤 상태인가"라는 물음이 안 생긴다.

Meta 분기 안에서 Shift를 한 번 더 보는 예외는 지금 `Cmd+Shift+C` 하나다
(CM design 위험 2 — "여기 하나뿐이어야 한다"). `Cmd+Shift+D`가 둘째다.
예외를 둘로 늘리는 대신 모양을 바꾼다 — Meta 분기 첫머리에 `shifted()`
switch 하나를 두고 그 안에 둘을 나란히 적는다. 셋째가 오면 그 switch에 한
줄이다.

조합 중인 한글은 chord가 확정시킨다(HI 결정 6). 확정된 바이트는 `readKeys`의
`out`에 먼저 실리고 `main.zig`가 그것을 PTY에 쓴 뒤에 패널 명령을 처리하므로,
`한` 뒤에 Cmd+]를 누르면 `한`은 떠나기 전 패널의 셸로 간다 — 그 셸에서 치던
글자이니 맞는 자리다. 같은 read에 패널 명령 뒤의 글자까지 실려 오면(자동
반복 · 아주 빠른 입력) 그 글자도 옛 패널로 간다. 스크롤 · copy 명령이 이미
같은 순서이고(바이트 먼저), 그 경우를 고치려면 바이트를 명령 사이에 끼워
나르는 통로가 필요하다 — 생기면 그때 한다.

`Action`에 `pane: Pane` variant가 생기고 `State.panes[8]` · `Keys.panes`가
`scrolls` · `copies`와 같은 모양으로 선다. `Pane`은 `union(enum)`이 아니라
`enum`이면 된다 — 워크스페이스 번호(`workspace_1`~`_9`)를 variant 아홉으로
적는다. payload를 두면 `std.meta.eql`이 필요해지고(`Copy`가 그렇다), 아홉은
적을 수 있는 수다.

### 결정 5 — `Cmd+W`는 SIGHUP을 보내기만 하고, 닫힘은 EOF 경로 하나다

지금 `main.zig`는 PTY EOF에서 `child exited (pty EOF)`를 찍고 루프를 나간다.
패널이 여럿이면 EOF는 "그 패널을 닫는다"가 되고, 마지막 패널의 마지막
워크스페이스였을 때만 지금처럼 루프를 나간다(init이 되살린다 — BF의 감독이
그대로 보인다).

`Cmd+W`는 그 길에 얹는다. `kill(child_pid, SIGHUP)` 한 줄이고, 셸이 죽어
PTY가 EOF를 내면 위 경로가 패널을 닫는다. 닫는 자리가 하나라서 `exit`를
친 것과 `Cmd+W`가 같은 코드를 지난다.

SIGHUP인 이유는 SL이 잰 것 그대로다 — zsh · bash는 SIGTERM을 무시하고
SIGHUP에는 끝난다(`project_shutdown_signals`). 자식이 SIGHUP까지 막으면
패널이 안 닫힌다. 그때는 `exit`를 치면 된다 — 사람이 보는 앞에서 멈춘 것을
3초 뒤 SIGKILL로 치우는 것보다, 안 닫히는 것이 보이는 쪽이 낫다.

닫을 때 `waitpid(child_pid, 0)`로 거둔다. 지금은 셸이 끝나면 terminal도
끝나서 좀비가 문제가 안 됐는데, 패널이 닫혀도 terminal이 살아 있으면 거둬야
한다. EOF는 slave fd가 전부 닫혔다는 뜻이라 자식은 이미 끝났거나 끝나는
중이고, 그래서 막힘이 짧다. 배경 job이 slave를 쥐고 있으면 EOF 자체가 안
오므로 여기 안 온다.

### 결정 6 — 커서는 포커스 패널에만, 이미지는 자기 패널 안에만

`vt.Screen`에 `focused: bool = true`가 생긴다. `cells()`가 셸 커서를 반전하는
자리(`vt.zig:693`)가 이 값이 거짓이면 반전을 건너뛴다. 기본이 참이라
`vt_test`의 화면 서른여 개가 안 바뀐다. copy 커서는 안 가린다 — 포커스
패널에서만 생기는 것이다(결정 4).

이미지의 `clip`은 지금 격자 사각형 하나인데, 패널의 사각형이 된다.
`drawImages`가 받는 `clip`을 패널마다 계산하면 끝이고 `image.zig`는 안
바뀐다.

`render`는 패널마다 `cells` · `images` · `clip`을 받아 격자 원점에 패널의
`rect`를 더해 그린다. 지금 `GRID_X + col * CELL_W`인 산수가
`GRID_X + (rect.col + col) * CELL_W`가 된다. 덤프 넷(`dumpStyles` · `dumpInk`
· `dumpImages` · `dumpPromptInk`)이 프레임버퍼를 셀 좌표로 읽으므로 같은
원점을 받아야 한다 — 안 받으면 패널 하나일 때만 맞는 값이 나온다.

프롬프트 오버레이(`/needle`)는 포커스 패널의 마지막 줄이다. `Prompt.rows` ·
`cols`가 패널의 것이 된다.

### 결정 7 — 로그는 `screen>`을 안 바꾸고 `pane>` 한 줄을 더한다

`screen>`은 포커스 패널의 셀을 패널 좌표로 찍는다. 패널 하나면 지금 로그와
바이트까지 같다 — 열일곱 체인의 `wait_for_screen`이 그대로 선다. 포커스
없는 패널은 안 찍는다. 그 내용을 보려면 게이트가 포커스를 옮긴다 — 사람이
보는 것과 게이트가 보는 것을 같게 둔다.

새 줄 하나가 패널 명령마다 찍힌다.

```
terminal: pane> ws=1/2 panes=2 focus=1 rect=78,0 77x47 sep ink=6016
```

(`sep ink`는 셀 단위라 세로 구분선 하나가 47줄 × 128픽셀이다 — M1 실측 1.)

`ws=현재/전체` · `panes=이 워크스페이스의 패널 수` · `focus=잎 번호` · `rect=`
포커스 패널의 사각형 · `sep ink=` 프레임버퍼의 `SEPARATOR` 픽셀 수. 마지막
값이 CI의 `copy ink`와 같은 자리다 — 트리가 맞아도 구분선을 안 그리면 0이고,
글자만 보는 판정은 그것을 못 잡는다.

`wait_for_screen`은 로그 전체의 `screen>`을 보므로(`project_gate_screen_echo`)
포커스를 옮긴 뒤 "옛 패널의 글자가 없다"는 판정은 그 함수로 못 한다 —
마지막 프레임만 잘라 보는 헬퍼가 `pane/check.sh`에 선다(copy 체인의
`copy_value`가 마지막 줄만 보는 것과 같은 모양).

### 결정 8 — 상태 줄 꼬리에 `W2` 칸, 워크스페이스가 둘 이상일 때만

CI 결정 2의 규칙 그대로다. 하나뿐이면 안 뜨고, 그래서 hangul 체인의 `text=`
비교와 `ink fg=` 기준값이 안 바뀐다. 둘 이상이면 `COPY` 앞에 `  W2`가 붙는다
— `COPY`는 모드라 맨 끝이고, 워크스페이스는 자리라 그 앞이다. 색은
`STATUS_FG`(앞 세 칸과 같다 — 켜고 꺼지는 것이 아니라 자리를 말하는
칸이다).

`statusText`는 `workspace: ?u8`(null이면 안 뜬다)을 받는다. `status.zig`가
`layout.zig`를 import하지 않는 이유는 `vt.zig`를 import하지 않는 이유와
같다 — 순수 계산을 지킨다. `MAX_LEN`이 `GAP.len + 2`만큼 는다.

### 결정 9 — 게이트는 새 체인 `pane/check.sh` 하나(열여덟번째)

copy · render 체인에 끼우지 않는다. 분할 · 닫기 · 워크스페이스는 키가 열
남짓이고 부팅 하나에 다 들어가지만, 기존 체인의 `screen>` 판정이 "격자 전체 =
패널 하나"를 전제하므로 그 체인 안에서 분할하면 뒤 검사가 전부 흔들린다.

| 검사 | 친다 | 본다 |
|---|---|---|
| 1 | 부팅 | `pane> ws=1/1 panes=1` · `sep ink=0` |
| 2 | `Cmd+D` | `panes=2 focus=1` · `sep ink>0` · 왼쪽 `rect=0,0`보다 오른쪽 `rect.col>0` |
| 3 | `echo right-side` Enter | 마지막 프레임의 `screen>`에 `right-side` |
| 4 | `Cmd+[` | `focus=0` · 마지막 프레임에 `right-side`가 없다(음성) · `key>` 줄 수가 안 는다 |
| 5 | `Cmd+Shift+D` | `panes=3` · 새 패널의 `rect.row>0` |
| 6 | `Cmd+W` | `child exited` 한 줄 · `panes=2` · `started terminal` 수가 그대로(terminal이 안 죽었다) |
| 7 | `Cmd+T` | `ws=2/2 panes=1` · 상태 줄 `text=`가 `  W2`로 끝난다 |
| 8 | `Cmd+1` | `ws=1/2 panes=2` · `right-side`가 마지막 프레임에 다시 있다 |
| 9 | `Cmd+W` × 3 | 마지막에 `child exited` 뒤 `started terminal`이 하나 는다(init이 되살렸다) |

검사 6과 9가 짝이다 — 6은 "패널 하나를 닫아도 terminal이 산다", 9는
"마지막까지 닫으면 끝난다". 하나만 보면 "닫기가 늘 terminal을 죽인다"도,
"영영 안 죽는다"도 통과한다.

QEMU `sendkey` 이름: `meta_l-d` · `meta_l-shift-d` · `meta_l-w` ·
`meta_l-bracket_left` · `meta_l-bracket_right` · `meta_l-t` · `meta_l-1`.
전부 QKeyCode에 있다(copy 체인의 `meta_l-shift-c`와 같은 모양).

## 검증

### 호스트

- `layout_test`(새): 분할 여덟 · 사각형 합이 격자와 같다(구분선 포함) ·
  닫으면 형제가 부모 자리 · 순환이 끝에서 감긴다 · 꽉 차면 `null`.
- `input_test`: `Cmd+D` → `.pane = .split_right`, `Cmd+Shift+D` →
  `.split_below`, `Cmd+W` · `Cmd+[` · `Cmd+]` · `Cmd+T` · `Cmd+5`; copy mode
  안에서는 `Cmd+D`가 `nothing`(결정 4의 음성).
- `vt_test`: `resize` 뒤 `cells()`가 새 크기 안에 있다 · `focused=false`면
  커서 반전이 없다.
- `status_test`: `workspace=2`면 `  W2  COPY` 순서 · `null`이면 없다 ·
  `MAX_LEN` 갱신.

### 게이트

결정 9의 체인. 그리고 WP-M0 뒤에 기존 체인 넷(terminal · render · copy ·
hangul)이 그대로 서야 한다 — 구조 변경이 화면을 한 픽셀도 안 바꿨다는
판정이다.

## Milestone

### WP-M0 — 구조: 패널 하나짜리 워크스페이스 하나

`layout.zig` · `layout_test.zig` · `Pane` · `Workspace`가 서고, `main.zig`의
루프가 포커스 패널을 거쳐 돈다. 패널 명령은 없다. 눈에 보이는 변화가 0이고
기존 체인 넷이 그대로 선다. `screen>` 로그가 바이트까지 같다.

### WP-M1 — 분할 · 닫기 · 순환

`Cmd+D` · `Cmd+Shift+D` · `Cmd+W` · `Cmd+]` · `Cmd+[`. `Screen.resize` ·
`pty.resize` · 구분선 · `focused` · `pane>` 줄. 새 체인 `pane/check.sh`
검사 1~6 · 9(워크스페이스가 하나라 7 · 8은 M2).

### WP-M2 — 워크스페이스

`Cmd+T` · `Cmd+1`~`9` · 상태 줄 `W2` 칸. 체인에 검사 7 · 8.

### WP-M3 — 방향 포커스(사용자가 고른다)

`Cmd+Option+화살표`. `layout.Tree.neighbor(leaf, dir)` — 포커스 사각형의
변과 겹치는 이웃 중 가장 가까운 것. 순환만으로 네 패널을 다니는 것이
불편해졌을 때 연다.

## 위험

1. `poll`의 fd 배열이 패널 수를 따라 변한다. 매 바퀴 배열을 다시 짓는다 —
   패널 여덟 × 워크스페이스 아홉이면 72 + 1개이고 그 비용은 없다. 포커스
   없는 워크스페이스의 PTY도 읽어야 한다(안 읽으면 그 셸이 출력 버퍼에
   막혀 멈춘다). 읽어서 `feed`만 하고 안 그린다.
2. 접기(reflow)가 `vt.Screen`의 상태를 흔든다 — `find`의 pin · `hl_spans` ·
   `copy_anchor_y`. 결정 3이 copy mode를 닫아 `find`까지 함께 버린다
   (`copyExit`이 그 둘을 정리한다). 그래도 `resize` 뒤 첫 `cells()`가
   라이브러리 안에서 깨지면 그것이 M1의 첫 실측이다.
3. 메모리. 화면 하나가 스크롤백 1000줄로 약 1.15MB(TR 실측). 72개면 83MB인데
   전부 늦게 만들어지고(사람이 만든 만큼만), 게이트의 512MB와 실기의 RAM
   어느 쪽도 감당한다. firmware 96MB가 늘 있는 것(WL 위험 5)과 합쳐 보면
   128MB 게스트는 이제 안 된다 — 이미 아니다.
4. `cell_buf`는 격자 전체 크기라 어느 패널에도 충분하다. `img_buf` 16칸은
   패널마다 다시 쓴다.
5. 분할 직후 셸이 SIGWINCH를 받고 프롬프트를 다시 그리기 전까지 한 프레임
   동안 옛 줄 접힘이 보인다. 라이브러리의 reflow가 그것을 대부분 덮고, 남는
   것은 셸이 고친다 — iTerm2도 같다.
6. `Cmd+Option+←`는 지금 Meta 분기가 `KEY_LEFT`를 먼저 잡아 `0x01`
   (beginning-of-line)이 된다. M3가 열리면 결정 4의 `shifted()` switch
   옆에 `alted()` switch가 하나 더 선다 — 그 모양을 M1에서 미리 만들지는
   않는다(쓰지 않을 분기를 미리 두지 않는다, CM-M0의 규율).

## 비목표

- 드래그 · 마우스. 입력 장치가 키보드뿐이다.
- 분할 비율 조절(`Cmd+Ctrl+화살표`). 비율은 영영 1/2이다.
- 패널 간 복사 — 클립보드는 `vt.Screen`마다 하나다. 한 패널에서 `y`한 것을
  다른 패널에 `Cmd+V`하려면 클립보드를 `main.zig`로 올려야 한다. 쓰고 싶어지면
  그때 연다.
- 워크스페이스 이름 · 순서 바꾸기.
- 설정 파일로 키 바꾸기.
- 패널 상태의 부팅 넘김(세션 복원).

## 관련

- `docs/specs/2026-08-10-tars-terminal-foundation-design.md` — 결정 1(프로세스
  하나가 디스플레이를 독점한다). 이 design은 그 프로세스 안에서 셸을 N개로
  만든다
- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 결정 3(모드가 키를
  삼킨다) · 위험 2(Meta 분기의 Shift 예외)
- `docs/specs/2026-10-03-tars-copy-indicator-design.md` — 꼬리 칸의 규칙과
  전용 색의 이유. `W2` 칸과 `SEPARATOR`가 그 규칙을 따른다
- `docs/decisions/project_shutdown_signals.md` — `Cmd+W`가 SIGHUP인 이유
- `docs/decisions/project_gate_screen_echo.md` — `wait_for_screen`이 로그
  전체를 보는 성질. 결정 7의 "마지막 프레임" 헬퍼가 필요한 이유
