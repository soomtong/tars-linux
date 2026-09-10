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

/// 새 블록에 들어갈 수 있는 항목 수. 커널이 주는 것은 둘이고 커널 상수
/// MAX_INIT_ENVS까지 늘 수 있다. 여유를 크게 둔다 — 이 배열은 main()의
/// 스택에 살고 한 항목이 포인터 8바이트라 128바이트다.
pub const MAX_ENTRIES: usize = 16;

/// 부르는 쪽이 스택에 잡아 주는 자리. main()의 지역 변수여야 한다 —
/// supervise()가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다
/// (main.zig의 keyboard_path·argv와 같은 근거다).
pub const Block = [MAX_ENTRIES:null]?[*:0]const u8;

/// 커널이 준 블록을 buf에 복사하고 끝에 PATH를 붙인 뒤 buf를 돌려준다.
///
/// **자리가 모자라면 커널 블록을 그대로 돌려준다.** PATH가 없는 게스트는
/// 불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다.
/// HD 결정 6("못 찾아도 부팅을 막지 않는다")과 같은 종류의 선택이다.
pub fn withPath(
    kernel: [*:null]const ?[*:0]const u8,
    buf: *Block,
) [*:null]const ?[*:0]const u8 {
    var n: usize = 0;
    while (kernel[n]) |entry| : (n += 1) {
        // buf[n]에 이 항목, buf[n+1]에 PATH, buf[n+2]에 닫는 null이
        // 들어가야 한다. 셋이 다 안 들어가면 아예 손대지 않는다.
        if (n + 2 >= MAX_ENTRIES) return kernel;
        buf[n] = entry;
    }
    buf[n] = PATH_ENTRY.ptr;
    buf[n + 1] = null;
    return buf;
}
