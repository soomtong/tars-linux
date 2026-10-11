//! 그리는 간격의 하한(RS-M2). 순수 모듈이고 `pacing_test`가 호스트에서 본다.
//!
//! 출력이 쏟아질 때 PTY 읽기 한 번(4KB)마다 화면 전체를 그리던 것을 끊는다(RS-M0:
//! 프레임 365 = 읽기 365). 화면을 바꿀 일이 생겨도 마지막 프레임 뒤로 `MIN_GAP_MS`가
//! 안 지났으면 그리지 않고 `poll`로 돌아가 남은 시간만큼 기다린다.
//!
//! 기다리는 자리가 `poll`이라는 것이 요점이다. 게스트는 CPU가 하나이고(`# CONFIG_SMP is
//! not set`) 출력을 만드는 자식과 우리가 그것을 나눠 쓴다. 우리가 막혀야 자식이 돌아
//! 커널의 PTY 버퍼(4KB)를 다시 채운다. 처음 구현은 "읽은 뒤 `poll(0)`으로 더 있나 묻고
//! 더 읽기"였는데, 묻는 동안 CPU를 안 놓으므로 답이 틱(4ms)과 `feed`의 위상에 달려
//! 같은 코드가 2.1초와 5.6초로 갈렸다(RS-M2 plan "첫 구현").
//!
//! 키 하나의 지연은 안 는다 — 마지막 프레임이 `MIN_GAP_MS`보다 오래전이면 곧바로 그린다.
const std = @import("std");

/// 프레임 사이의 최소 간격(밀리초). 초당 약 60번이다.
pub const MIN_GAP_MS: i64 = 16;

/// `poll`에 줄 timeout(밀리초). 그릴 것이 없으면(`pending`이 false) -1(무한)이다 —
/// 기다릴 프레임이 없다. 있으면 지금 그려도 될 때 0, 아니면 하한까지 남은 시간이다.
/// 처음 프레임(`last_ms`가 null)은 기다리지 않는다.
///
/// 부르는 쪽은 이 값이 0보다 크면 그리기를 미룬다. 그래서 "미룰까"와 "얼마나 기다릴까"가
/// 한 계산이다 — 둘을 따로 셈하면 어긋나 미뤘는데 무한히 기다리는 회차가 생긴다.
pub fn wait(now_ms: i64, last_ms: ?i64, pending: bool) c_int {
    if (!pending) return -1;
    const last = last_ms orelse return 0;
    const left = last + MIN_GAP_MS - now_ms;
    if (left <= 0) return 0;
    return @intCast(left);
}

/// 두 `poll` timeout 중 먼저 오는 것. -1은 무한이라 `@min`을 그대로 쓰면 언제나 -1이
/// 이긴다 — 그러면 미룬 프레임이 다른 이벤트가 올 때까지 안 그려진다.
pub fn soonest(a: c_int, b: c_int) c_int {
    if (a < 0) return b;
    if (b < 0) return a;
    return @min(a, b);
}
