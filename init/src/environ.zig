//! 게스트에 넘길 환경 변수 블록.
//!
//! 커널은 PID 1에게 딱 둘을 준다(linux/init/main.c의 envp_init):
//!
//!     const char *envp_init[] = { "HOME=/", "TERM=linux", NULL, };
//!
//! 지금까지 PID 1은 이 블록을 **그대로** 자식에게 넘겼고, 그래서 게스트에
//! PATH가 없었다 — 셸이 명령을 이름으로 못 찾고 절대 경로만 먹었다
//! (docs/decisions/project_guest_environment.md의 "결과 1").
//!
//! **PATH를 PID 1이 더하는 이유**는 그것이 자식마다 갈릴 이유가 없는 값이기
//! 때문이다. TERM은 갈려야 맞아서(화면 셸은 xterm-256color, 시리얼 콘솔 셸은
//! linux) terminal 쪽 setenv에 있고, LANG은 갈릴 이유가 없는데도 거기 있다 —
//! 같은 문서가 그것을 자기비판으로 적어 뒀다. **여기가 그 실수를 반복하지
//! 않는 자리다**(design 결정 1).
//!
//! 시스템 콜을 하나도 안 한다. 그래서 environ_test.zig가 호스트에서 돈다.

const std = @import("std");

/// 게스트의 PATH. **자리가 둘인 것에 뜻이 있다** — 도구는 전부 /usr/bin에
/// 넣고 /bin에는 sh 하나만 둔다(design 결정 6). 이 문자열과
/// kernel/make_initrd.sh가 넣는 자리가 어긋나면 증상은 "어떤 명령도 안
/// 찾아진다"이고 원인에서 멀다.
pub const PATH_ENTRY: [:0]const u8 = "PATH=/usr/bin:/bin";

/// `XDG_DATA_HOME`이 가리키는 자리(SM design 결정 2). **이 한 경로가 둘을
/// 옮긴다** — `zoxide`의 `db.zo`와 fish의 `fish_history`(실측 3·11·38·40).
///
/// **`_ZO_DATA_DIR`을 안 쓴 이유**는 fish에 경로 변수가 없기 때문이다.
/// `XDG_DATA_HOME`이 유일한 지렛대이고, 그것을 쓰면 zoxide가 공짜로 따라온다.
///
/// **링크가 아니라 환경 변수인 이유**(SC 결정 1과 갈린 자리)는 실측 4다 —
/// 설정 디스크가 없는 여섯 체인에서 `/config/…`를 가리키는 링크는 댕글링이고,
/// 그때 zoxide는 `cd`마다 에러 두 줄을 찍는다. 없는 경로를 env로 주면
/// **`mkdir -p`하고 조용히 성공한다.**
///
/// 두 줄이 한 글자를 공유하는 것에 뜻이 있다 — `main.zig`가 만드는
/// 디렉터리와 셸이 받는 값이 어긋나면 증상은 "기억이 가끔 안 남는다"이고
/// 원인에서 아주 멀다. **여기서는 `++`로 컴파일러가 잇는다**(훅 두 벌과
/// 반대다 — 저쪽은 검사가 tautology가 되므로 일부러 안 이었다).
pub const XDG_DATA_DIR = "/config/xdg";
pub const XDG_ENTRY: [:0]const u8 = "XDG_DATA_HOME=" ++ XDG_DATA_DIR;

/// 새 블록에 들어갈 수 있는 항목 수. 커널이 주는 것은 둘이고 커널 상수
/// MAX_INIT_ENVS까지 늘 수 있다. 여유를 크게 둔다 — 이 배열은 main()의
/// 스택에 살고 한 항목이 포인터 8바이트라 128바이트다.
pub const MAX_ENTRIES: usize = 16;

/// 부르는 쪽이 스택에 잡아 주는 자리. main()의 지역 변수여야 한다 —
/// supervise()가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다
/// (main.zig의 keyboard_path·argv와 같은 근거다).
pub const Block = [MAX_ENTRIES:null]?[*:0]const u8;

/// 커널이 준 블록을 buf에 복사하고 **우리 것을 뒤에 붙인 뒤** buf를 돌려준다.
///
/// 붙이는 것이 셋이다.
///
///   PATH             자식마다 갈릴 이유가 없다(UT-M0)
///   XDG_DATA_HOME    같다. 배운 것 둘이 여기로 간다(SM-M2 결정 2)
///   hist             **셸마다 갈린다** — `config.Shell.histEntries()`가 준다
///
/// **셋째가 인자인 것이 이 함수의 전부다.** 이 파일은 `config.zig`를 모른 채
/// 있어야 하고(그래야 호스트 검사가 순수 계산으로 남는다), 그래서 "어느 셸인가"
/// 대신 "무엇을 붙일까"를 받는다. 부르는 쪽은 `main.zig` 하나다.
///
/// **자리가 모자라면 커널 블록을 그대로 돌려준다.** PATH가 없는 게스트는
/// 불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다.
/// HD 결정 6("못 찾아도 부팅을 막지 않는다")과 같은 종류의 선택이다.
pub fn withTarsEnv(
    kernel: [*:null]const ?[*:0]const u8,
    buf: *Block,
    hist: []const [:0]const u8,
) [*:null]const ?[*:0]const u8 {
    var n: usize = 0;
    while (kernel[n] != null) n += 1;

    // 우리가 더하는 수. 셸마다 2(fish) · 4(bash) · 5(zsh)다.
    const added = 2 + hist.len;
    // 마지막으로 쓰는 자리가 buf[n + added](닫는 null)이고, 그 자리가 배열의
    // sentinel 자리(MAX_ENTRIES)를 넘으면 안 된다.
    if (n + added >= MAX_ENTRIES) return kernel;

    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = kernel[i];
    buf[n] = PATH_ENTRY.ptr;
    buf[n + 1] = XDG_ENTRY.ptr;
    for (hist, 0..) |entry, j| buf[n + 2 + j] = entry.ptr;
    buf[n + added] = null;
    return buf;
}
