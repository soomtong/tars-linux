const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

/// 렌더러에게 넘기는 셀 하나.
///
/// `fg`·`bg`는 프레임버퍼와 같은 `0x00RRGGBB` 형식으로 **이미 해소된** 값이다.
/// `Style`을 그대로 흘려보내지 않는 이유가 design 결정 1이다 — 색을 푸는 데
/// 필요한 것(팔레트, 기본 fg/bg, bold 옵션)이 전부 여기 `RenderState`에 있고,
/// 렌더러는 팔레트도 SGR도 몰라야 한다. inverse와 커서도 여기서 두 색을
/// 맞바꿔 해소하므로 `main.zig`는 "반전"이라는 개념 자체를 배우지 않는다.
pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
    fg: u32,
    bg: u32,
};

/// 매치 하이라이트의 행별 범위 하나. **양 끝을 포함한다** — 라이브러리가
/// `row_sels`로 주는 선택 범위와 같은 규약이다(design 결정 4).
///
/// **`Screen` 안이 아니라 여기 있는 이유**는 Zig가 struct의 필드 사이에 선언을
/// 끼우는 것을 막기 때문이다. `Screen`의 기존 선언들(`Cursor`·`SelectKind`)이
/// 전부 필드 뒤에 있는 것도 같은 규칙이고, `CellGlyph`처럼 바깥이 보는 타입은
/// 파일 스코프가 자리가 맞다.
pub const RowSpan = struct {
    row: u16,
    x0: u16,
    x1: u16,
    /// 이 범위가 **지금 선택된 매치**인가(SP design 결정 2).
    ///
    /// **기본값을 안 주는 것에 뜻이 있다**(plan 결정 2). 만드는 자리가
    /// `findSpans` 하나뿐인데, 기본값이 있으면 두 번째 자리가 생겼을 때
    /// 정하는 것을 잊어도 컴파일이 통과한다.
    current: bool,

    fn lessThan(_: void, a: RowSpan, b: RowSpan) bool {
        if (a.row != b.row) return a.row < b.row;
        return a.x0 < b.x0;
    }
};

/// 마지막 `cells()`가 만든 하이라이트의 실측(design 결정 5).
///
/// **상한을 안 두기로 한 결정의 근거를 남기는 값이다.** `us`가 밀리초 단위로
/// 커지면 그때 상한을 논의한다.

/// `cur`은 **현재 매치가 칠한 셀 수**다(SP-M0). `cells`는 뜻을 안 바꾼다 —
/// 여전히 보이는 매치 **전부**의 셀 수이고, 게이트의 검사 16이 그 뜻에 기대
/// "needle 길이의 배수"를 본다.
pub const HlStats = struct { spans: usize, cells: usize, cur: usize, us: i64 };

/// 매치 하이라이트의 바탕색(design 결정 1). **맞바꿈이 아니라 값이다.**
///
/// 배경 `#102030`과도 반전된 흰색과도 멀어야 사람이 넷을 가릴 수 있고, 색이
/// **하나**여야 게이트가 `style>` 줄에서 셀 수 있다. 어두운 앰버를 골랐다.
///
/// | 상태 | 바탕 | 글자 |
/// |---|---|---|
/// | 기본 | `#102030` | 흰색 |
/// | 선택 | 흰색 | `#102030` |
/// | 매치 | `#705000` | 흰색 |
/// | 선택 안의 매치 | 흰색 | `#705000` |
///
/// 상수가 `main.zig`가 아니라 여기 있는 이유는 색을 확정하는 것이 이 파일의
/// 일이기 때문이다(TR design 결정 1). `pub`인 것은 `vt_test`가 본다.
pub const MATCH_BG: u32 = 0x00705000;

/// 지금 선택된 매치의 바탕색(SP design 결정 4). **`MATCH_BG`와 같은 계열의
/// 더 밝은 색이다.**
///
/// 색상 계열을 같게 두고 밝기만 올리는 것에 뜻이 있다 — "같은 종류인데 이것이
/// 지금 것"이라는 뜻을 밝기 차이가 전달한다. 다른 계열을 고르면 두 색이 서로
/// 다른 것을 뜻하는 것처럼 보인다.
///
/// | 상태 | 바탕 | 글자 |
/// |---|---|---|
/// | 기본 | `#102030` | 흰색 |
/// | 선택 | 흰색 | `#102030` |
/// | 매치 | `#705000` | 흰색 |
/// | **현재 매치** | **`#C08000`** | 흰색 |
/// | 선택 안의 매치 | 흰색 | `#705000` |
///
/// **`fg`는 여전히 안 건드린다.** 그래서 CS design 결정 1의 "매치는 바탕만
/// 정한다"가 한 줄 그대로 남는다.
pub const CURRENT_BG: u32 = 0x00C08000;

/// `color.RGB`를 프레임버퍼의 XRGB8888 한 워드로 만든다.
fn packRgb(c: ghostty_vt.color.RGB) u32 {
    return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
}

/// 터미널 상태를 **계속 들고 있는** 화면.
///
/// TF-M2의 `parseToCells`는 호출할 때마다 Terminal을 새로 만들고 버렸다.
/// 입력이 생기면 PTY 출력이 여러 조각으로 나눠 도착하므로, 조각마다 새
/// Terminal을 만들면 앞 내용이 사라질 뿐 아니라 이스케이프 시퀀스가 조각
/// 경계에서 잘렸을 때 파서 상태도 잃는다. 그래서 Terminal과 Stream을
/// 프로그램 수명 내내 유지한다.
///
/// **반드시 힙에 두고 포인터로 다뤄야 한다.** `Terminal.vtStream()`이
/// 돌려주는 Stream은 내부에 `&terminal` 포인터를 담고 있어서
/// (`Terminal.zig:374-377`), Screen 값이 복사·이동되면 그 포인터가 옛 주소를
/// 가리키게 된다. `init`이 `*Screen`을 돌려주는 이유가 이것이다.
pub const Screen = struct {
    alloc: std.mem.Allocator,
    /// 시간을 재기 위해 들고 있는다(plan 결정 1). `init`이 `Terminal`에 넘기고
    /// 버리던 값이다.
    ///
    /// `cells()`에 인자로 넘기지 않는 이유는 그 호출부가 `vt_test`에만 열댓 곳
    /// 있기 때문이다 — 이 milestone과 무관한 diff가 그만큼 생긴다.
    io: std.Io,
    term: ghostty_vt.Terminal,
    /// `ghostty_vt.Stream`이 아니다 — 그쪽은 핸들러 타입을 받는 제네릭
    /// 함수(`stream.Stream(Handler)`)라서 필드 타입으로 못 쓴다.
    /// Terminal용으로 인스턴스화된 것이 `TerminalStream`이며
    /// (`stream_terminal.zig:26`), `Terminal.vtStream()`의 반환 타입이
    /// 정확히 이것이다(`Terminal.zig:30`).
    stream: ghostty_vt.TerminalStream,
    state: ghostty_vt.RenderState,
    /// copy mode의 커서. null이면 copy mode가 아니다.
    ///
    /// **뷰포트 좌표다**(0이 화면 맨 윗줄). 절대 행이 아닌 이유는 이동이
    /// 화면 위의 일이기 때문이다 — 뷰포트가 한 줄 올라가면 커서는 화면의
    /// 같은 자리에 남고, 그래서 가리키는 내용이 한 줄 위가 된다. 그것이
    /// 화면 끝에서 계속 움직였을 때 사람이 기대하는 동작이다.
    ///
    /// 앵커(선택의 시작점)는 여기 두지 않는다. 라이브러리의 tracked
    /// selection이 든다(design 결정 5) — 뷰포트가 움직여도 저절로 따라간다.
    copy_cursor: ?Cursor = null,

    /// 지금 무엇을 잡고 있는가. null이면 커서만 움직이는 중이다.
    copy_kind: ?SelectKind = null,

    /// 앵커의 **screen 좌표 y**. 가지치기 감시용이다(CM-M1).
    ///
    /// 이 값이 왜 필요한지가 이 milestone에서 가장 미묘한 자리다.
    /// `main.zig`가 copy mode 중에 `scrollToBottom()`을 억제하므로, 뷰포트가
    /// history에 머무는 동안 가지치기가 일어날 수 있다(design 위험 1).
    /// **그때 라이브러리는 선택을 null로 만들지 않는다** — tracked pin을
    /// 살아 있는 이웃 페이지의 왼쪽 위로 옮긴다
    /// (`PageList.erasePage`, `PageList.eraseRows`). 선택은 멀쩡히 존재하고
    /// 가리키는 내용만 달라진다. 그래서 "selection이 null인가"로는 절대 못
    /// 잡고, 조용히 엉뚱한 자리를 복사하게 된다.
    ///
    /// screen 좌표는 목록 맨 위에서부터 세는 절대 좌표라 **아래에 줄이 붙는
    /// 것으로는 안 변한다.** 변하는 경우가 앞에서 줄이 지워졌을 때와 pin이
    /// 옮겨졌을 때뿐이고, 그 둘이 정확히 우리가 잡고 싶은 것이다.
    copy_anchor_y: ?u32 = null,

    /// 가지치기 때문에 모드가 끊겼다는 것을 `main.zig`가 한 번 가져간다.
    copy_pruned: bool = false,

    /// 클립보드. `y`가 만든 문자열을 **소유한다.**
    ///
    /// 프로세스 하나가 디스플레이를 독점하는 구조(TF design 결정 1)에서는
    /// 버퍼 하나로 충분하다(`project_copy_mode`). 다음 `y`가 옛것을 해제한다.
    clip: ?[:0]const u8 = null,

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
    /// 마지막으로 확정한 검색어(design 결정 8). **`copyExit`이 지우지 않는
    /// 유일한 검색 상태다.**
    ///
    /// 빈 Enter가 이것을 다시 쓴다. **모드를 나갔다 다시 들어와도 `/`+Enter가
    /// 동작하는 것이 이 기능의 전부다** — 그래서 `copyExit`의 정리 목록에서
    /// 이것만 빠진다.
    ///
    /// `find_buf`와 같은 고정 128바이트이고 같은 이유다 — 동적 할당은 "언제
    /// 해제하는가"를 여러 자리에 나눠 놓는다.
    ///
    /// **성공·실패를 안 가리고 남긴다.** 못 찾은 검색어를 고쳐 다시 치는 것이
    /// 흔한 일이고, vim도 그렇게 한다.
    find_last: [128]u8 = undefined,
    find_last_len: usize = 0,

    /// 마지막 검색이 아무것도 못 찾았는가(design 결정 9). **오버레이 한 줄에
    /// `/needle: not found`를 쓰는 조건이다.**
    ///
    /// `findSubmit`이 정하고, **`main.zig`가 copy 명령을 처리하기 직전 한
    /// 자리에서 끈다.** 시계를 안 들여오는 이유는 poll 루프가 지금 시각을 안
    /// 보기 때문이고, 다음 키까지 떠 있으면 사람이 메시지를 못 보고 넘길 일도
    /// 없다.
    ///
    /// **메시지에 쓸 글자는 `find_last`에서 온다.** 메시지가 뜰 때는 프롬프트가
    /// 이미 닫혀 있어서 `findNeedle()`이 null을 주기 때문이다 — 결정 8과 9가
    /// 맞물리는 자리가 여기다.
    find_missed: bool = false,

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
    /// 확정된 검색의 매치 **전부**. `findSubmit`이 만들고 `copyExit`이 버린다.
    ///
    /// **`ScreenSearch.matches()`가 주는 것은 얕은 복사다**
    /// (`search/screen.zig:234`가 `@memcpy`로 구조체만 옮긴다). 각 `Flattened`의
    /// `chunks`는 ScreenSearch 내부 버퍼를 그대로 가리키므로, **원소를
    /// `deinit`하면 이중 해제**다. `alloc.free(slice)` 하나만 부른다
    /// (design 결정 6).
    ///
    /// `find`와 **언제나 나란히** 다룬다 — 한쪽만 남은 상태를 만들지 않는다.
    /// 해제 자리가 셋이고 `find`의 것과 정확히 같다: `findSubmit`의 옛것 정리 ·
    /// `copyExit` · `deinit`.
    ///
    /// 왜 `find`에게 매번 물어보지 않고 슬라이스를 들고 있는가: `matches()`가
    /// 부를 때마다 할당한다. 매 프레임 부르는 자리(`cells`)가 생기므로 한 번만
    /// 받아 둔다. **목록은 `searchAll()` 시점의 스냅숏이고 갱신하지 않는다**
    /// (design 결정 7).
    find_matches: ?[]ghostty_vt.highlight.Flattened = null,

    /// 하이라이트의 행별 범위. **매 `cells()`가 다시 만든다.**
    ///
    /// 매치 목록은 스냅숏이지만(design 결정 7) 좌표는 아니다 — 뷰포트가 움직이면
    /// 같은 매치가 다른 행에 온다. 버퍼를 들고 있는 이유는 프레임마다 새로
    /// 할당하지 않기 위해서다(`clearRetainingCapacity`).
    hl_spans: std.ArrayListUnmanaged(RowSpan) = .empty,
    hl_stats: HlStats = .{ .spans = 0, .cells = 0, .cur = 0, .us = 0 },

    pub fn init(
        io: std.Io,
        alloc: std.mem.Allocator,
        cols: u16,
        rows: u16,
    ) !*Screen {
        const self = try alloc.create(Screen);
        self.* = .{
            .alloc = alloc,
            .io = io,
            // 기본 색을 여기서 준다(design 결정 5). 값은 main.zig가 쓰던
            // 상수와 같게 유지한다 — 이번 변경이 화면의 색을 바꾸는 일이 되면
            // 게이트의 회귀와 우리 변경을 가르기 어려워진다.
            //
            // `.init`은 "OSC로 덮어쓸 수 있는 기본값"이라는 뜻이다
            // (`color.zig:337`). 그래서 셸이 OSC 10/11로 배경·전경을 바꾸는
            // 것이 저절로 동작한다. `.unset`이면 라이브러리 기본값
            // (fg=#FFFFFF, bg=#000000)이 나온다.
            .term = try .init(io, alloc, .{
                .cols = cols,
                .rows = rows,
                // 스크롤백 한도(design 결정 10). **두 값을 함께 줘야 한다.**
                //
                // 결정 10은 max_scrollback_lines만 말했는데, 그것만 주면
                // 아무것도 바뀌지 않는다 — 기본 max_scrollback_bytes(10,000)가
                // 먼저 걸려서 155x47 격자에서 history가 454줄에 멈춘다
                // (2026-08-23 실측). 효력 있는 한도는 `max(준 값, 활성 영역을
                // 담을 최소값)`이라(PageList.Limits.max) 10,000바이트는 처음부터
                // 무시되고 있었다.
                //
                // 바이트가 아니라 줄로 세는 이유는 그것이 사람이 생각하는
                // 단위이고, 게이트가 "N줄 찍고 올라가서 첫 줄을 본다"로
                // 검사하기 쉽기 때문이다. 실제로 남는 history는 754~1000줄을
                // 오간다 — 가지치기가 페이지 통째로 일어나기 때문이고,
                // 1.15MB라 128MB 게스트가 감당한다.
                .max_scrollback_bytes = null,
                .max_scrollback_lines = 1000,
                .colors = .{
                    .background = .init(.{ .r = 0x10, .g = 0x20, .b = 0x30 }),
                    .foreground = .init(.{ .r = 0xFF, .g = 0xFF, .b = 0xFF }),
                    .cursor = .unset,
                    .palette = .default,
                },
            }),
            .stream = undefined,
            .state = .empty,
        };
        // term이 최종 주소에 자리잡은 **뒤에** stream을 만든다.
        self.stream = self.term.vtStream();
        return self;
    }

    pub fn deinit(self: *Screen) void {
        const alloc = self.alloc;
        if (self.clip) |text| alloc.free(text);
        // **term보다 먼저다.** ScreenSearch가 든 tracked pin은 PageList의
        // 풀에서 왔으므로, term을 먼저 버리면 이미 없는 풀을 건드린다.
        if (self.find) |*f| f.deinit();
        // **바깥 슬라이스만 해제한다**(design 결정 6). 원소의 `chunks`는 위
        // `f.deinit()`이 이미 해제한 버퍼를 가리키는 얕은 복사다.
        if (self.find_matches) |m| alloc.free(m);
        self.hl_spans.deinit(alloc);
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }

    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    ///
    /// **먹인 뒤에 앵커가 제자리에 있는지 본다**(CM-M1, design 위험 1).
    /// 어긋났으면 모드를 통째로 닫는다 — 조용히 엉뚱한 자리를 복사하는 것보다
    /// 낫고, 사람은 다시 `Cmd+Shift+C`를 누르면 된다.
    ///
    /// 대체 화면(vim 등)으로 갈아타서 `selection`이 사라지는 경우도 같은
    /// 조건에 걸린다. 그때 나가는 것도 옳다.
    ///
    /// 선택 중이 아니면(`copy_anchor_y`가 null이면) 아무 일도 안 한다.
    /// 커서만 있는 상태에서는 잘못 복사될 것이 없기 때문이다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);

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

        const want = self.copy_anchor_y orelse return;
        const now = anchorY(self.term.screens.active);
        if (now != null and now.? == want) return;

        self.copyExit();
        self.copy_pruned = true;
    }

    /// 지금 선택의 앵커가 screen 좌표로 몇 번째 행에 있는가.
    ///
    /// 선택이 없으면 null이다. `pointFromPin`은 라이브러리가 스스로 "느리다"고
    /// 적어 둔 함수라(`Selection.zig`의 NOTE) 셀마다 부르면 안 되지만, 여기는
    /// **선택이 있을 때 PTY 출력 한 조각에 한 번**이라 문제가 되지 않는다.
    fn anchorY(s: *ghostty_vt.Screen) ?u32 {
        const sel = s.selection orelse return null;
        const pt = s.pages.pointFromPin(.screen, sel.start()) orelse return null;
        return pt.screen.y;
    }

    /// 그릴 것이 있는 셀을 out에 채워 반환한다. out은 최소 cols*rows
    /// 크기여야 안전하다.
    ///
    /// **글자가 없어도 색이 있으면 내보낸다**(design 결정 3). 배경색이
    /// 생긴 뒤로는 빈 셀도 그릴 것이 있기 때문이다 — `ls` 출력의 색 띠,
    /// 커서 자리, 그리고 나중의 선택 영역이 그렇다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        // update()는 beginUpdate() + endUpdate()다(`render.zig:326`).
        // 셀별 style은 endUpdate에서 채워지므로 이 호출 뒤에 읽어도 된다.
        try self.state.update(self.alloc, &self.term);

        // 매치 하이라이트의 좌표를 먼저 푼다(CS-M0). 검색이 없으면 곧바로
        // 돌아온다.
        try self.findSpans();

        const colors = &self.state.colors;
        const default_fg = packRgb(colors.foreground);
        const default_bg = packRgb(colors.background);
        const cursor = self.state.cursor.viewport;

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        // 그 행에서 선택된 x 범위. **라이브러리가 채워 준다**
        // (`render.zig`가 `sel.topLeft()`/`bottomRight()`로 계산한다). 절대 행
        // 번호를 우리가 세지 않는 이유가 이것이다(design 결정 6).
        const row_sels = row_data.items(.selection);
        // 정렬된 범위 목록을 **앞으로만** 미는 커서다(design 결정 4). 셀마다
        // 목록을 훑지 않으므로 전체가 O(범위 수)다.
        const spans = self.hl_spans.items;
        var hl_at: usize = 0;

        for (0..self.state.rows) |y| {
            // `@as(usize, ...)`는 이 파일의 기존 규율이다 — 아래 선택 범위를
            // 보는 자리가 `x >= @as(usize, range[0])`으로 쓴다.
            while (hl_at < spans.len and
                @as(usize, spans[hl_at].row) < y) : (hl_at += 1)
            {}
            var hl_end = hl_at;
            while (hl_end < spans.len and
                @as(usize, spans[hl_end].row) == y) : (hl_end += 1)
            {}
            const row_spans = spans[hl_at..hl_end];

            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            const styles = cells_slice.items(.style);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];

                const raw = raws[x];
                const cp = raw.codepoint();

                var fg = default_fg;
                var bg = default_bg;

                // style_id가 기본값(0, `style.zig:17`의 default_id)일 때
                // style을 읽으면 쓰레기다. 라이브러리가 계약으로 명시한
                // 자리다(`render.zig:260-262`).
                if (raw.style_id != 0) {
                    const st = styles[x];
                    fg = packRgb(st.fg(.{
                        .default = colors.foreground,
                        .palette = &colors.palette,
                        // bold를 밝은 색으로 바꾸는 일을 라이브러리가 대신
                        // 해 준다(`style.zig:172-181`). 폰트가 하나뿐이라
                        // 굵은 자체가 없는 우리에게는 이것이 유일한 길이다.
                        .bold = .bright,
                    }));
                    // null이 "기본 배경"이라는 뜻이다(`style.zig:120`).
                    if (st.bg(&raw, &colors.palette)) |b| bg = packRgb(b);
                    // inverse는 아무도 처리해 주지 않는다 — fg()도 bg()도
                    // 이 플래그를 안 본다.
                    if (st.flags.inverse) std.mem.swap(u32, &fg, &bg);
                }

                // 매치 하이라이트(CS-M0 design 결정 1). **맞바꿈이 아니라 값을
                // 정한다.** 맞바꿈이면 선택 안의 매치가 아래에서 두 번 뒤집혀
                // 원래 색으로 돌아와 안 보이고, 반전된 띠가 선택인지 매치인지
                // 사람도 게이트도 못 가른다.
                //
                // **inverse 뒤·선택 앞이 이 층의 자리다.** inverse는 셀이 원래
                // 가진 성질이라 매치가 덮어써야 하고, 선택과 커서는 사람이 지금
                // 하는 동작이라 매치 **위에** 얹혀야 한다.
                //
                // **`fg`는 안 건드린다** — 매치가 원래 무슨 색 글자였는지를
                // 지우지 않기 위해서다. 그래서 이 층은 한 줄로 말할 수 있다:
                // "매치는 바탕만 정한다".

                // **먼저 걸린 것에서 멈추지 않는다**(plan 결정 3). 색이 하나일
                // 때는 그 `break`가 순수한 최적화였지만, 둘이 되면 **목록
                // 순서가 색을 정하는 것**이 된다. 매치끼리 겹칠 일이 없다고
                // 믿고 있지만 증명한 적이 없으므로, 겹치면 **현재 매치가
                // 이기게** 한다.
                //
                // `current`를 만났을 때는 더 볼 것이 없으므로 그때만 멈춘다.
                var hit_match = false;
                var hit_current = false;
                for (row_spans) |sp| {
                    if (x >= @as(usize, sp.x0) and x <= @as(usize, sp.x1)) {
                        hit_match = true;
                        if (sp.current) {
                            hit_current = true;
                            break;
                        }
                    }
                }
                if (hit_match) bg = if (hit_current) CURRENT_BG else MATCH_BG;

                // 선택 영역도 inverse·커서와 **같은 연산**이다(design 결정 6).
                // 그래서 렌더러는 "선택"이라는 말을 배우지 않는다. 양 끝을
                // 포함하는 범위다(`render.zig`가 `start.x <= end.x`를 단언한
                // 뒤 그대로 담는다).
                if (row_sels[y]) |range| {
                    if (x >= @as(usize, range[0]) and x <= @as(usize, range[1])) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                //
                // **copy mode 중에는 셸 커서를 그리지 않는다**(CM-M0). 반전된
                // 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다.
                //
                // 커서가 선택 안에 있으면 위에서 한 번, 여기서 또 한 번
                // 맞바뀌어 **원래 색으로 돌아온다**(CM-M1). 예외를 두지 않는다 —
                // 반전된 띠 가운데 뚫린 구멍이 곧 커서라 오히려 잘 보이고,
                // 예외를 넣으면 "선택"이 렌더 쪽으로 새어 나간다.
                if (self.copy_cursor) |cc| {
                    if (@as(usize, cc.x) == x and @as(usize, cc.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                } else if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 그릴 글자도 없고 칠할 색도 기본인 셀만 건너뛴다.
                if (cp == 0 and bg == default_bg) continue;

                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                    .fg = fg,
                    .bg = bg,
                };
                n += 1;
            }
        }
        return out[0..n];
    }

    /// 기본 전경/배경을 프레임버퍼 형식으로 돌려준다.
    ///
    /// `main.zig`가 같은 상수를 다시 적지 않게 하려고 여기서 내보낸다.
    /// 로그 문구가 두 곳에 중복되어 어긋난 사고가 이 저장소에 이미 있었고
    /// (`HANDOFF.md`), 색 상수도 같은 함정이다 — `init`이 Terminal에 넣은
    /// 값을 `RenderState`가 되돌려준 것이므로 이쪽이 언제나 실제로 쓰이는
    /// 값이다.
    ///
    /// **`cells()` 뒤에 부를 것.** `state.colors`는 `update()`가 채운다.
    pub fn defaultFg(self: *const Screen) u32 {
        return packRgb(self.state.colors.foreground);
    }

    pub fn defaultBg(self: *const Screen) u32 {
        return packRgb(self.state.colors.background);
    }

    /// 뷰포트 좌표 한 쌍. 로그와 검사가 함께 쓴다.
    pub const Cursor = struct { x: u16, y: u16 };

    /// copy mode에 들어간다. 커서는 셸 커서 자리에서 시작한다.
    ///
    /// 셸 커서가 뷰포트 밖에 있으면(스크롤백을 올려다보는 중이면) 화면 맨
    /// 왼쪽 위에서 시작한다 — 안 보이는 자리에 커서를 두면 사람이 무엇을
    /// 움직이는지 알 수 없다.
    pub fn copyEnter(self: *Screen) void {
        self.copy_cursor = if (self.state.cursor.viewport) |vp|
            .{ .x = vp.x, .y = vp.y }
        else
            .{ .x = 0, .y = 0 };
    }

    /// copy mode를 나간다. **선택도 함께 지운다** — 안 지우면 모드를 나간 뒤에도
    /// 반전된 띠가 화면에 남는다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
        self.copy_kind = null;
        self.copy_anchor_y = null;
        // 프롬프트도 함께 닫는다(design 결정 10). 안 닫으면 모드를 나갔다
        // 다시 들어왔을 때 지난 검색어가 화면에 남는다.
        self.findCancel();
        // 매치 목록도 함께 버린다(design 결정 10). tracked pin을 들고 있으므로
        // **screen이 살아 있는 동안** 해제해야 한다.
        if (self.find) |*f| f.deinit();
        self.find = null;
        // 매치 목록도 같은 자리에서 버린다(design 결정 6). **바깥 슬라이스만**
        // 해제한다 — 원소는 방금 `f.deinit()`이 해제한 버퍼를 가리킨다.
        if (self.find_matches) |m| self.alloc.free(m);
        self.find_matches = null;
        // 좌표도 함께 비운다. 안 비우면 모드를 나간 프레임에 지난 범위가 한 번
        // 더 칠해진다 — 게이트의 음성 검사(plan 결정 4)가 그것을 본다.
        self.hl_spans.clearRetainingCapacity();
        // "못 찾았다" 메시지도 끈다(design 결정 9). 안 끄면 모드를 나간 뒤에도
        // 화면 아랫줄에 메시지가 남는다.
        //
        // **`find_last`는 여기서 안 지운다**(design 결정 8). 이 함수가 검색
        // 상태를 전부 버리는 자리인데 그것 하나만 빠지는 것이고, **모드를
        // 나갔다 들어와도 `/`+Enter가 동작하는 것이 CS-M1의 전부다.**
        // 검사 33이 이 예외를 본다.
        self.find_missed = false;
        self.term.screens.active.clearSelection();
    }

    /// `/`. 프롬프트를 연다. **언제나 빈 검색어로 시작한다**(design 결정 8) —
    /// 미리 채우면 전혀 다른 것을 찾을 때 먼저 여러 번 지워야 한다.
    ///
    /// 지난 검색어를 다시 쓰는 길은 **빈 Enter**이고 `findSubmit`이 그 자리다.
    /// 프롬프트에서 `↑`로 되부르는 것은 design이 비워 둔 자리로 남는다.
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

    /// 못 찾은 검색어. **메시지가 꺼져 있으면 null이다**(design 결정 9).
    ///
    /// `findNeedle`과 짝이다 — 그쪽은 "지금 치고 있는 것", 이쪽은 "방금 못 찾은
    /// 것"이고, 오버레이 한 줄을 두 갈래로 가르는 것이 이 둘이다.
    ///
    /// **`main.zig`가 `find_last`를 직접 읽지 않게 하려고 함수로 낸다** —
    /// `findNeedle`·`clipboard`·`copyCursor`와 같은 규율이다.
    pub fn findMissed(self: *const Screen) ?[]const u8 {
        if (!self.find_missed) return null;
        return self.find_last[0..self.find_last_len];
    }

    /// "못 찾았다" 메시지를 끈다. **`main.zig`가 copy 명령을 처리하기 직전
    /// 한 자리에서 부른다**(design 결정 9).
    ///
    /// 끄는 것이 명령 처리보다 **앞**이라, 새로 실패한 검색의 메시지는
    /// `findSubmit`이 그 뒤에 다시 켜서 살아남는다. 순서 하나로 "다음 키에
    /// 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다(plan 결정 2).
    pub fn findClearMissed(self: *Screen) void {
        self.find_missed = false;
    }

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
    /// **빈 검색어로 Enter를 누르면 지난 검색어를 다시 쓴다**(CS-M1, design
    /// 결정 8). vim과 같은 동작이다. 되부를 것이 아예 없으면 예전처럼 프롬프트만
    /// 닫고, 그때도 지난 검색은 살아 있으므로 `n`이 계속 동작한다.
    pub fn findSubmit(self: *Screen) !FindResult {
        const none: FindResult = .{ .matches = 0, .moved = false };
        if (!self.find_open) return none;

        self.find_open = false;

        // **빈 Enter는 지난 검색어를 다시 쓴다**(design 결정 8). CN-M1이
        // 프롬프트만 닫던 자리이고, 그때 "검색 기록이 없어서"라고 적어 두었다.
        //
        // 되부를 것이 아예 없으면 그대로 프롬프트만 닫는다 — 부팅 직후 `/`를
        // 열고 그냥 Enter를 누른 경우다.
        var len = self.find_len;
        if (len == 0) {
            if (self.find_last_len == 0) return none;
            len = self.find_last_len;
            @memcpy(self.find_buf[0..len], self.find_last[0..len]);
        }

        // **성공·실패와 무관하게 남긴다**(design 결정 8). 못 찾은 검색어를 고쳐
        // 다시 치는 것이 흔한 일이고, 그러려면 실패한 것도 기억해야 한다.
        //
        // 위에서 되부른 경우에는 같은 값을 도로 쓰는 셈인데, 그래도 분기를
        // 안 만든다 — `find_buf`와 `find_last`는 **서로 다른 배열**이라 겹칠
        // 일이 없고, 규칙이 하나면 빠뜨릴 자리도 없다.
        @memcpy(self.find_last[0..len], self.find_buf[0..len]);
        self.find_last_len = len;

        // **옛 검색을 먼저 해제한다.** 안 하면 `/`를 두 번 누를 때마다 매치
        // 목록과 tracked pin이 그대로 샌다.
        if (self.find) |*old| old.deinit();
        self.find = null;
        if (self.find_matches) |m| self.alloc.free(m);
        self.find_matches = null;

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

        // **첫 이동만 "커서보다 위"를 요구한다**(CN-M1 plan 결정 3).
        const moved = try self.findStep(.next, true);
        // **이동 뒤에 스냅숏을 뜬다.** 왜 뒤여야 하는지는 `refreshMatches`에
        // 적혀 있다 — `select()`가 앞의 목록을 해제한다.
        try self.refreshMatches();

        const count = self.find.?.matchesLen();
        // **켜기만 하지 않고 매번 값을 정한다**(CS-M1 plan 결정 1). design은
        // "0이면 켠다"라고 적었는데, 그대로 하면 끄는 자리가 `main.zig` 하나뿐이
        // 되어 **성공한 검색이 앞의 실패를 안 지우는 경로**가 생긴다. poll 루프를
        // 안 거치는 호출자(`vt_test`)가 그렇다.
        //
        // 켜는 자리와 끄는 자리를 안 가르는 것이 요점이고, CS-M0이
        // `refreshMatches`를 셋 다에서 부른 것과 같은 규율이다.
        self.find_missed = count == 0;
        return .{ .matches = count, .moved = moved };
    }

    /// 보관 중인 매치가 몇 개인가. 검색이 없으면 0이다.
    ///
    /// **`matchesLen()`과 언제나 같아야 한다.** 다르면 슬라이스가 낡은 것이고,
    /// 그것은 곧 `find`와 `find_matches`가 따로 놀았다는 뜻이다. 검사 26이 이
    /// 등식을 본다.
    pub fn findMatchCount(self: *const Screen) usize {
        const m = self.find_matches orelse return 0;
        return m.len;
    }

    /// 지금 선택된 매치가 `find_matches`의 몇 번째인가. 없으면 null이다.
    ///
    /// **라이브러리의 내부 필드를 읽는 유일한 자리다**(SP design 결정 1).
    /// `ScreenSearch`에 `selectedIndex()` 같은 공개 함수가 없어서 `selected.idx`를
    /// 직접 본다. 한 함수로 감싸 두는 이유는 나중에 라이브러리에 함수가 생기거나
    /// 다른 방법으로 바꿀 때 고칠 자리를 하나로 두기 위해서다 — `findMissed`가
    /// `find_last`를 감싼 것과 같은 경계다.
    ///
    /// **`idx`가 `find_matches`의 인덱스와 같은 좌표계라는 것이 이 함수의
    /// 전제다.** `selectedMatch()`와 `matches()`가 같은 색인 규칙을 쓴다
    /// (`search/screen.zig:771`과 `:234`) — 활성 영역은 뒤집어 담고 history는
    /// 그대로 이어 붙이는 그 규칙이다. **그 전제가 조용히 깨지면 증상이 "번호가
    /// 거꾸로 나온다"라 눈에 안 띄므로 `vt_test`의 검사 37·38이 뜻을 고정한다.**
    ///
    /// 범위를 함께 보는 이유는 라이브러리도 그렇게 하기 때문이다
    /// (`selectedMatch()`가 `:783`에서 null을 준다). `select()`가
    /// `reloadActive()`·`pruneHistory()`를 먼저 부르므로 목록이 줄어들 수 있고,
    /// 그때 낡은 `idx`를 그대로 쓰면 범위를 벗어난다. **넷을 전부 null 하나로
    /// 접는 것이 요점이다**(plan 결정 1) — 부르는 쪽은 "현재 매치가 없다"만
    /// 알면 된다.
    pub fn findCurrentIndex(self: *const Screen) ?usize {
        if (self.find == null) return null;
        const sel = self.find.?.selected orelse return null;
        const m = self.find_matches orelse return null;
        if (sel.idx >= m.len) return null;
        return sel.idx;
    }

    /// 매치 목록 스냅숏을 다시 뜬다. **`select()`를 부른 직후에 부른다.**
    ///
    /// **`select()`가 앞의 목록을 무효로 만든다.** 그것이 먼저 `reloadActive()`를
    /// 부르는데, 그 함수가 `active_results`의 원소를 전부 `deinit`한 뒤 활성
    /// 영역을 다시 찾는다(`search/screen.zig:682-683`). `pruneHistory()`도
    /// history 쪽에 같은 일을 한다(`:402`). 그래서 `matches()`가 준 얕은 복사는
    /// **다음 `select()`까지만** 유효하고, 그 뒤에 읽으면 해제된 메모리다 —
    /// 디버그 allocator에서 0xAA로 나타난다.
    ///
    /// 깊은 복사(`Flattened.clone`)로 가지 않는 이유는 그러면 하이라이트가 낡은
    /// 목록을, `n`이 새 목록을 보게 되기 때문이다. **어긋남을 만들지 않는 것이
    /// design 결정 2의 요점이다.**
    ///
    /// `select`를 부르는 자리는 `findStep` 하나이고, 그것을 부르는 것은
    /// `findSubmit`·`findNext`·`findPrev` **셋뿐이다.** 셋 다 끝에서 이것을
    /// 부른다.
    fn refreshMatches(self: *Screen) !void {
        if (self.find_matches) |m| self.alloc.free(m);
        self.find_matches = null;
        if (self.find) |*f| self.find_matches = try f.matches(self.alloc);
    }

    /// 화면에 보이는 매치를 행별 범위로 푼다. **`cells()`가 매 프레임 부른다.**
    ///
    /// **매치마다 `pointFromPin`을 부르지 않는다**(design 결정 3). 그 함수는
    /// 뷰포트 top-left에서 `node.next`를 따라 앞으로 훑고, 뷰포트보다 **위**에
    /// 있는 pin은 목록 끝까지 훑은 뒤에야 null이 된다 — copy mode에서 매치
    /// 대부분이 거기 있다. 라이브러리도 `Pin.before`에 "very expensive... should
    /// not be called in performance critical paths"라고 적어 두었고 `isBetween`도
    /// 같은 성질이라, 싼 pin 순서 비교는 애초에 없다.
    ///
    /// 그래서 방향을 뒤집는다. 뷰포트가 덮는 page node를 **한 번만** 훑고, 매치
    /// 쪽은 `chunks`가 이미 든 `{node, serial, start, end}`와 비교만 한다.
    /// 뷰포트가 걸치는 node는 보통 한두 개다.
    ///
    /// **매치 쪽 node 포인터를 역참조하는 자리가 이 함수에 없다**(design 위험 2).
    /// 비교에만 쓴다 — 가지치기된 페이지를 읽지 않기 위해서이고, `Flattened`가
    /// 그런 모양인 이유가 정확히 그것이다(`highlight.zig:107`). `serial`까지
    /// 비교하는 것은 주소가 재사용된 경우를 거르기 위해서다.
    fn findSpans(self: *Screen) !void {
        self.hl_spans.clearRetainingCapacity();
        self.hl_stats = .{ .spans = 0, .cells = 0, .cur = 0, .us = 0 };

        const matches = self.find_matches orelse return;
        const pages = &self.term.screens.active.pages;
        const rows = pages.rows;
        const cols = pages.cols;
        // **격자를 `state`가 아니라 `pages`에서 읽는다**(CM-M1이 `copyMove`에서
        // 고친 것과 같다). `state`는 마지막 `cells()`의 스냅숏이라 첫 프레임에
        // 0이고, 그러면 이 함수가 조용히 아무 일도 안 한다.
        if (rows == 0 or cols == 0) return;

        // **루프 밖에서 한 번만 읽는다.** 매치마다 부르면 같은 값을 매치 수만큼
        // 다시 구하는 셈이고, 이 함수는 매 프레임 돈다.
        const cur_i = self.findCurrentIndex();

        const t0 = std.Io.Clock.now(.awake, self.io);

        const tl = pages.getTopLeft(.viewport);
        // `row0`은 지금 노드의 첫 보이는 행이 화면 몇 번째 행인가,
        // `y`는 지금 노드에서 몇 번째 행부터 보이는가다.
        var row0: u16 = 0;
        var y: u16 = tl.y;
        var node_: ?*ghostty_vt.PageList.List.Node = tl.node;
        while (node_) |node| : (node_ = node.next) {
            if (row0 >= rows) break;
            const take = @min(node.rows() - y, rows - row0);

            for (matches, 0..) |m, mi| {
                const chunks = m.chunks.slice();
                if (chunks.len == 0) continue;
                const c_nodes = chunks.items(.node);
                const c_serials = chunks.items(.serial);
                const c_starts = chunks.items(.start);
                const c_ends = chunks.items(.end);
                for (0..chunks.len) |ci| {
                    // **역참조가 아니라 비교다.** `c_nodes[ci]`가 가리키는
                    // 메모리를 읽지 않는다 — 그것이 가지치기된 페이지일 수 있다.
                    if (c_nodes[ci] != node) continue;
                    if (c_serials[ci] != node.serial) continue;

                    // `end`는 제외다(`endPin`이 `ends[last] - 1`을 쓴다).
                    var ry = @max(c_starts[ci], y);
                    const ry_end = @min(c_ends[ci], y + take);
                    while (ry < ry_end) : (ry += 1) {
                        // 첫 행만 `top_x`에서 시작하고 끝 행만 `bot_x`에서
                        // 끝난다. soft wrap으로 여러 줄이 된 매치의 가운데
                        // 줄은 줄 전체다.
                        const is_first = ci == 0 and ry == c_starts[0];
                        const is_last = ci == chunks.len - 1 and
                            ry == c_ends[chunks.len - 1] - 1;
                        try self.hl_spans.append(self.alloc, .{
                            .row = row0 + (ry - y),
                            .x0 = if (is_first) m.top_x else 0,
                            .x1 = if (is_last) m.bot_x else cols - 1,
                            // **좌표를 두 번 풀지 않는 것이 요점이다**(SP design
                            // 결정 2). 현재 매치만 따로 다시 푸는 길로 가면 같은
                            // 계산이 두 벌이 되고, 어긋났을 때 증상이 "색만
                            // 엉뚱한 자리에 있다"라 조사하기 나쁘다.
                            // **capture를 안 만든다.** 이 자리의 바깥 루프가
                            // 이미 `ci`를 쓰고 있고(`for (0..chunks.len) |ci|`)
                            // Zig는 shadowing을 컴파일 에러로 막는다. 이름을
                            // 새로 고르는 대신 optional을 그대로 비교하면
                            // 같은 실수가 다시 날 자리가 없어진다.
                            .current = cur_i != null and cur_i.? == mi,
                        });
                    }
                }
            }

            row0 += take;
            y = 0;
        }

        // **`cells()`가 커서 하나로 따라갈 수 있게 정렬한다**(design 결정 4).
        // 노드 사이는 이미 오름차순이지만 한 노드 안에서는 매치가 최신→오래된
        // 순, 곧 행 내림차순으로 들어온다.
        std.mem.sort(RowSpan, self.hl_spans.items, {}, RowSpan.lessThan);

        var painted: usize = 0;
        var painted_cur: usize = 0;
        for (self.hl_spans.items) |sp| {
            const w = @as(usize, sp.x1 - sp.x0) + 1;
            painted += w;
            if (sp.current) painted_cur += w;
        }
        self.hl_stats = .{
            .spans = self.hl_spans.items.len,
            .cells = painted,
            .cur = painted_cur,
            .us = @intCast(@divTrunc(t0.untilNow(self.io, .awake).nanoseconds, 1000)),
        };
    }

    /// 마지막 `cells()`가 만든 하이라이트의 실측. **검색이 없으면 null이다** —
    /// `main.zig`가 이 null로 "찍을 것이 없다"를 판정한다(plan 결정 2).
    pub fn hlStats(self: *const Screen) ?HlStats {
        if (self.find == null) return null;
        return self.hl_stats;
    }

    /// 하이라이트의 행별 범위. **검사가 좌표를 직접 보는 창구다.**
    ///
    /// `main.zig`는 이것을 안 쓴다 — 색은 `cells()`가 이미 해소해서 넘긴다
    /// (TR design 결정 1).
    pub fn hlSpans(self: *const Screen) []const RowSpan {
        return self.hl_spans.items;
    }

    /// `n`. 목록의 다음(과거 방향) 매치로.
    ///
    /// **목록 끝에서 감긴다.** 라이브러리의 `Select.next` 주석은
    /// "non-wrapping"이라고 하는데 `selectNext`의 코드는 감는다
    /// (`search/screen.zig:851`). **주석이 아니라 코드가 맞다.** 감기는 것을
    /// 감추지 않는 이유는, 막으려면 "끝에 닿았다"는 상태가 하나 늘고 그것을
    /// 사람에게 알릴 자리가 또 필요하기 때문이다.
    pub fn findNext(self: *Screen) !bool {
        const moved = try self.findStep(.next, false);
        try self.refreshMatches();
        return moved;
    }

    /// `N`. 목록의 이전(미래 방향) 매치로.
    pub fn findPrev(self: *Screen) !bool {
        const moved = try self.findStep(.prev, false);
        try self.refreshMatches();
        return moved;
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

    /// 가지치기로 모드가 끊겼다는 사실을 **한 번만** 돌려준다.
    /// `main.zig`가 로그 한 줄을 찍는 데 쓴다.
    pub fn copyTakePruned(self: *Screen) bool {
        defer self.copy_pruned = false;
        return self.copy_pruned;
    }

    pub fn copyActive(self: *const Screen) bool {
        return self.copy_cursor != null;
    }

    pub fn copyCursor(self: *const Screen) ?Cursor {
        return self.copy_cursor;
    }

    /// 커서를 옮긴다. **화면 끝을 넘으면 뷰포트가 대신 움직인다.**
    ///
    /// 좌우는 화면 안에서 멈춘다(줄을 넘나들지 않는다). 위아래는 화면 끝에서
    /// 뷰포트를 한 줄 밀고 커서는 그 끝에 남는다 — 스크롤백을 거슬러 올라가며
    /// 훑는 동작이 이것으로 만들어진다.
    ///
    /// **격자 크기를 `state`가 아니라 `pages`에서 읽는다**(CM-M1에서 고쳤다).
    /// `state`는 마지막 `cells()`가 찍은 스냅숏이라, 한 번도 그리지 않은
    /// 화면에서는 `cols`·`rows`가 0이고 그러면 이 함수가 **조용히 아무 일도
    /// 안 한다.** CM-M0의 주석은 "cells()보다 먼저 불려도 안전하다"고 적었는데,
    /// 크래시가 안 난다는 뜻으로는 맞지만 동작한다는 뜻으로는 틀렸다 —
    /// 실전에서 안 드러난 이유는 main.zig가 키를 받기 전에 이미 한 프레임을
    /// 그렸기 때문이다. `pages`는 언제나 살아 있는 값이다.
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) !void {
        const cur = self.copy_cursor orelse return;
        const pages = &self.term.screens.active.pages;
        if (pages.cols == 0 or pages.rows == 0) return;

        const max_x: i32 = @as(i32, pages.cols) - 1;
        const max_y: i32 = @as(i32, pages.rows) - 1;

        var x: i32 = @as(i32, cur.x) + dx;
        if (x < 0) x = 0;
        if (x > max_x) x = max_x;

        var y: i32 = @as(i32, cur.y) + dy;
        if (y < 0) {
            self.scrollByRows(-1);
            y = 0;
        } else if (y > max_y) {
            self.scrollByRows(1);
            y = max_y;
        }

        self.copy_cursor = .{ .x = @intCast(x), .y = @intCast(y) };

        // 선택 중이면 커서를 따라 넓힌다. 앵커는 우리가 안 들고 있고
        // **지금 선택의 start가 곧 앵커다**(design 결정 5). 줄 선택일 때 그
        // start는 앵커 줄 위의 어느 pin이므로, selectLine이 같은 줄을 다시
        // 돌려준다.
        if (self.copy_kind == null) return;
        const sel = self.term.screens.active.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 단어 경계로 치는 코드포인트.
    ///
    /// **값은 ghostty 자신의 검사가 쓰는 기본값과 같다**(`Screen.zig:9800`).
    /// 라이브러리는 이 목록을 설정에서 받도록 되어 있는데
    /// (`Surface.zig:1217`의 `selection_word_chars`) 우리에게는 설정이 없으므로
    /// 상수로 둔다. `/config/tars.conf`로 뺄 수 있는 자리이지만 바꾸고 싶어 한
    /// 사람이 없다 — 필요해지면 그때 뺀다.
    const WORD_BOUNDARY = [_]u21{
        0,   ' ', '\t', '\'', '"',
        '│',
        '`', '|', ':',  ';',  ',',
        '(', ')', '[',  ']',  '{',
        '}', '<', '>',  '$',
    };

    /// 단어 이동의 방향. `w`가 next, `b`가 prev다.
    pub const WordDir = enum { next, prev };

    /// 그 자리에 글자가 쓰였는가. **한 번도 안 쓰인 셀과 공백은 다르다** —
    /// `"alpha"` 뒤의 공백은 쓰인 셀이고, 줄 끝의 남은 칸은 아니다.
    /// `selectWord`가 후자에서 null을 주므로(plan 확정 사실 3) 우리도 그
    /// 경계를 같은 기준으로 본다.
    fn written(pin: ghostty_vt.Pin) bool {
        return pin.rowAndCell().cell.hasText();
    }

    /// 그 자리가 단어 경계인가. **쓰이지 않은 셀도 경계로 친다.**
    fn boundaryAt(pin: ghostty_vt.Pin) bool {
        const cell = pin.rowAndCell().cell;
        if (!cell.hasText()) return true;
        return std.mem.indexOfScalar(
            u21,
            &WORD_BOUNDARY,
            cell.content.codepoint.data,
        ) != null;
    }

    /// 두 pin이 같은 자리인가. `Pin`은 `{ node, y, x }`라 셋을 본다.
    fn samePin(a: ghostty_vt.Pin, b: ghostty_vt.Pin) bool {
        return a.node == b.node and a.y == b.y and a.x == b.x;
    }

    /// `w`/`b`. **커서를 단어 단위로 옮긴다.**
    ///
    /// **라이브러리가 세는 "단어"와 vim의 `w`는 다르다**(design 결정 3).
    /// `selectWord`는 공백 덩어리도 한 단어로 세므로(`"ABC  DEF"`가 셋),
    /// 공백에 내려앉으면 한 번 더 건너뛰는 일을 우리가 한다. **경계 판정이라는
    /// 어려운 부분은 끝까지 라이브러리에 남는다** — 우리가 정하는 것은 "어느
    /// 방향으로 몇 번 부르는가"뿐이다.
    ///
    /// 쓰이지 않은 자리에 닿으면 **움직이지 않는다**(CN-M0 plan 결정 1).
    /// vim은 다음 줄의 첫 단어로 가지만, 줄 사이 이동은 `j`/`k`가 이미 한다.
    pub fn copyMoveWord(self: *Screen, dir: WordDir) !void {
        if (self.copy_cursor == null) return;
        const s = self.term.screens.active;
        const from = self.copyPin() orelse return;

        const target = switch (dir) {
            .next => wordNext(s, from),
            .prev => wordPrev(s, from),
        } orelse return;

        self.copyPlace(target);

        // 선택 중이면 커서를 따라 넓힌다. **`copyMove`와 같은 문을 통과한다**
        // (design 결정 11) — 이동 수단마다 선택 갱신을 따로 짜면 그중 하나만
        // 어긋나도 "어떤 키로 움직였느냐에 따라 복사되는 글자가 다르다"가 된다.
        if (self.copy_kind == null) return;
        const sel = s.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 다음 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **두 번까지만 건너뛴다.** 지금 단어에서 한 번, 그것이 공백 덩어리면 한
    /// 번 더다. 세 번째는 있을 수 없다 — 경계 문자들이 연달아 오면 라이브러리가
    /// 그것을 **한 덩어리로** 묶기 때문이다(`expect_boundary` 로직).
    fn wordNext(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        var pin = from;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            pin = word.end().rightWrap(1) orelse return null;
            if (!written(pin)) return null;
            if (!boundaryAt(pin)) return pin;
        }
        return pin;
    }

    /// 이전 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **커서가 단어 중간이면 그 단어의 시작으로 간다**(vim과 같다,
    /// CN-M0 plan 결정 2). 그러지 않으면 `w`로 간 자리에서 `b`를 눌러도 원래
    /// 자리로 안 돌아온다.
    fn wordPrev(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        if (s.selectWord(from, &WORD_BOUNDARY)) |word| {
            const st = word.start();
            if (!samePin(st, from)) return st;
        }

        var pin = from.leftWrap(1) orelse return null;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            if (!written(pin)) return null;
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            if (!boundaryAt(pin)) return word.start();
            pin = word.start().leftWrap(1) orelse return null;
        }
        return pin;
    }

    /// 목표 pin에 커서를 놓는다. **화면 밖이면 뷰포트를 옮긴다.**
    ///
    /// `pointFromPin(.viewport, …)`이 뷰포트 **위쪽** 밖은 null로 알려주지만
    /// **아래쪽 밖은 알려주지 않는다** — 노드를 계속 따라가며 y를 더해서
    /// `rows`보다 큰 값을 그냥 돌려준다(`PageList.zig:5614`). 그래서 아래쪽은
    /// 우리가 가른다. **이것을 빠뜨리면 커서가 화면 밖 좌표를 갖고, 증상은
    /// 크래시가 아니라 "커서가 안 보인다"가 된다.**
    ///
    /// 뷰포트를 미는 두 경로가 모두 `Screen.scroll`을 통과하는 것에 뜻이 있다.
    /// `pages.scroll`을 직접 부르면 `assertIntegrity`와 kitty dirty 표시를
    /// 건너뛴다(`Screen.zig:1576`). **`Terminal.ScrollViewport`에는 `.pin`이
    /// 없어서**(`Terminal.zig:2504`) 기존 `scrollByRows`로는 위쪽을 못 다룬다.
    fn copyPlace(self: *Screen, pin: ghostty_vt.Pin) void {
        const s = self.term.screens.active;
        const rows: u32 = s.pages.rows;

        if (s.pages.pointFromPin(.viewport, pin)) |pt| {
            const co = pt.coord();
            if (co.y < rows) {
                self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
                return;
            }
            // 뷰포트 **아래**다. 최소한만 민다 — 목표가 맨 아랫줄이 된다.
            s.scroll(.{ .delta_row = @intCast(co.y - rows + 1) });
        } else {
            // 뷰포트 **위**다. 목표를 화면 맨 윗줄로 올린다.
            s.scroll(.{ .pin = pin });
        }

        const pt = s.pages.pointFromPin(.viewport, pin) orelse return;
        const co = pt.coord();
        if (co.y >= rows) return;
        self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
    }

    /// 선택 방식. `v`가 char, `V`가 line이다.
    pub const SelectKind = enum { char, line };

    /// 지금 커서 자리를 라이브러리의 pin으로 바꾼다.
    ///
    /// 뷰포트 좌표를 그대로 넘길 수 있는 것이 요점이다 — 절대 행 번호를 우리가
    /// 셀 필요가 없다. 뷰포트 밖이거나 폭이 줄어든 페이지면 null이다.
    fn copyPin(self: *Screen) ?ghostty_vt.Pin {
        const cc = self.copy_cursor orelse return null;
        return self.term.screens.active.pages.pin(.{
            .viewport = .{ .x = cc.x, .y = cc.y },
        });
    }

    /// `v`/`V`. **같은 방식을 다시 누르면 푼다.**
    ///
    /// 다른 방식을 누르면 앵커를 지금 커서 자리로 새로 잡는다. vim은 앵커를
    /// 유지하지만, 그러려면 "문자 앵커를 줄 앵커로 승격하는" 자리가 하나 더
    /// 생긴다 — 게이트가 볼 수 없는 표를 늘리는 일이라 지금 하지 않는다.
    pub fn copySelect(self: *Screen, kind: SelectKind) !void {
        if (self.copy_cursor == null) return;
        if (self.copy_kind) |cur| {
            if (cur == kind) {
                self.copy_kind = null;
                self.copy_anchor_y = null;
                self.term.screens.active.clearSelection();
                return;
            }
        }
        self.copy_kind = kind;
        const pin = self.copyPin() orelse return;
        try self.copyApply(pin, pin);
    }

    /// 앵커와 커서로 선택을 다시 만들어 화면에 넘긴다.
    ///
    /// **역방향(앵커보다 커서가 앞)을 우리가 정렬하지 않는다**(design 위험 3의
    /// 답). `selectionString`은 `sel.topLeft()`/`bottomRight()`를 쓰고
    /// (`formatter.zig`), 렌더도 같은 둘을 쓴다(`render.zig`). 그래서
    /// `ordered()`를 부를 자리가 없다.
    fn copyApply(
        self: *Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) !void {
        const s = self.term.screens.active;
        const kind = self.copy_kind orelse return;

        const sel: ghostty_vt.Selection = switch (kind) {
            .char => .init(anchor, cursor, false),
            // 줄 선택은 양 끝을 줄 전체로 넓힌다. **줄 끝 공백 트림을 손으로
            // 짜지 않는다** — selectLine이 이미 한다.
            .line => copyLineSel(s, anchor, cursor) orelse .init(anchor, cursor, false),
        };
        try s.select(sel);
        self.copy_anchor_y = anchorY(s);
    }

    /// 앵커 줄과 커서 줄을 합친 선택.
    ///
    /// 어느 쪽이 위인지를 **라이브러리에게 묻는다**. 화면 좌표를 우리가 세면
    /// 스크롤백 위에서 틀린다 — 앵커가 뷰포트 밖에 있을 수 있기 때문이다.
    fn copyLineSel(
        s: *ghostty_vt.Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) ?ghostty_vt.Selection {
        const a = s.selectLine(.{ .pin = anchor }) orelse return null;
        const b = s.selectLine(.{ .pin = cursor }) orelse return null;
        const probe: ghostty_vt.Selection = .init(a.start(), b.start(), false);
        return switch (probe.order(s)) {
            // 앵커 줄이 아래에 있다. 위아래를 뒤집어 담는다.
            .reverse => .init(a.end(), b.start(), false),
            else => .init(a.start(), b.end(), false),
        };
    }

    /// `y`. 선택을 클립보드로 옮기고 **모드를 나간다.**
    ///
    /// 돌려주는 슬라이스는 `self.clip`이 소유한다 — 다음 `y`까지만 유효하다.
    /// 선택이 없으면 null을 돌려주고 클립보드는 그대로 둔다(모드는 나간다).
    pub fn copyYank(self: *Screen) !?[]const u8 {
        const s = self.term.screens.active;
        const sel = s.selection orelse {
            self.copyExit();
            return null;
        };
        const text = try s.selectionString(self.alloc, .{ .sel = sel });
        if (self.clip) |old| self.alloc.free(old);
        self.clip = text;
        // copyExit이 선택을 지우므로 **문자열을 먼저 뽑아 둔 뒤에** 부른다.
        self.copyExit();
        return text;
    }

    /// 클립보드의 지금 내용. `y`를 한 번도 안 눌렀으면 null이다.
    ///
    /// `main.zig`가 `self.clip`을 직접 읽지 않게 하려고 함수로 낸다 —
    /// `copyCursor`·`scrollbar`와 같은 규율이다(TR design 결정 1).
    ///
    /// 반환 타입이 `?[]const u8`인 것에 뜻이 있다. `clip`은 실제로
    /// `?[:0]const u8`인데, sentinel을 밖으로 내보내면 호출부가 그것을 직접
    /// free해도 되는 값으로 오해할 여지가 생긴다. **소유권은 `Screen`에 있고
    /// 다음 `y`가 옛것을 해제한다.**
    ///
    /// `return self.clip;` 한 줄로 줄이지 않는다. 그렇게 쓰면 `?[:0]const u8`을
    /// `?[]const u8`로 바꾸는 일을 **optional 껍질을 쓴 채** 요구하게 된다.
    /// 먼저 풀고 나서 돌려주면 sentinel을 떼는 평범한 슬라이스 coercion이 되고,
    /// 그 형태는 바로 위 `copyYank`가 이미 쓰고 있는 것이다.
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
        return text;
    }

    /// 뷰포트가 스크롤백의 어디에 있는지.
    ///
    /// `total`은 스크롤 가능한 전체 행 수, `offset`은 뷰포트 맨 윗줄이 그중
    /// 몇 번째인가, `len`은 언제나 `rows`다. **"바닥에 있다"는
    /// `offset == total - len`이다.**
    ///
    /// 라이브러리 타입을 그대로 흘려보내지 않고 우리 struct로 옮겨 담는
    /// 이유는 TR-M0이 색에 대해 한 것과 같다(design 결정 1) — `main.zig`가
    /// `ghostty-vt`의 타입을 배우지 않게 한다.
    pub const Scrollbar = struct {
        total: usize,
        offset: usize,
        len: usize,
    };

    pub fn scrollbar(self: *Screen) Scrollbar {
        const sb = self.term.screens.active.pages.scrollbar();
        return .{ .total = sb.total, .offset = sb.offset, .len = sb.len };
    }

    /// 스크롤백의 맨 위로.
    pub fn scrollToTop(self: *Screen) void {
        self.term.scrollViewport(.top);
    }

    /// 활성 영역의 맨 위로 = 평소 상태로.
    ///
    /// **PTY 출력이 도착할 때마다 불러야 한다**(design 결정 13). 라이브러리는
    /// 그 일을 해 주지 않는다 — 올라간 상태에서 출력을 먹여도 뷰포트가
    /// 그대로라는 것을 2026-08-23에 실측했고, `vt_test`가 그 사실을 못 박고
    /// 있다.
    pub fn scrollToBottom(self: *Screen) void {
        self.term.scrollViewport(.bottom);
    }

    /// 상대 이동. **위가 음수다.**
    ///
    /// 몇 줄이 한 화면인지는 여기서 정하지 않는다. 격자 크기를 아는 것은
    /// `main.zig`이고, 그쪽이 `rows`를 넘겨준다.
    pub fn scrollByRows(self: *Screen, delta: isize) void {
        self.term.scrollViewport(.{ .delta = delta });
    }
};
