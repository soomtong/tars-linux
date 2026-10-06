const std = @import("std");

// 받아쓰기의 순수한 층(VD-M1, VD design 결정 10 · 11). 시스템 콜도 `vt.zig`도
// 프레임버퍼도 안 본다 — 시각 · 단계 · 종료 코드를 받아 판단을 돌려주는 계산이라
// `dictation_test`가 호스트에서 전부 본다. fork · 파이프 · 시그널 · PTY 쓰기는
// `main.zig`의 받아쓰기 절에 있다(pointer.zig와 main.zig의 경계와 같다).
//
// 녹음 · 전사 · 기록은 게스트의 `tars-dictate`가 한다(VD-M0). 이 파일이 아는 그
// 프로그램의 계약은 셋이다 — 종료 코드(`outcome`), 표준 에러의 두 줄(`phaseAfter`),
// 표준 출력이 넣을 글자라는 것(`sanitize`).

/// 더블 탭의 창(Voxio D6의 `doubleTapWindowMs` 기본값, VD design 결정 10).
///
/// 첫 누름에서 둘째 누름까지를 잰다. 닫힌 구간이라 정확히 300ms는 발동한다
/// (Voxio `isWithinWindow`). `input.zig`의 `TAP_MAX_US`와 수가 같지만 재는 것이
/// 다르다 — 그쪽은 한 번 누른 길이이고 이쪽은 두 누름 사이다.
///
/// 설정으로 안 뺀다(design 결정 3의 표 — `trigger.doubleTapWindowMs`는 상수로 간다).
pub const WINDOW_US: u64 = 300_000;

/// 트리거 키의 더블 탭 판정기(Voxio `DoubleTapDetector`의 toggle 모드).
///
/// 녹음 중인지를 모른다 — Voxio와 갈리는 자리다(design 결정 10의 함정 3). Voxio는
/// 판정기가 `recording`을 들고 있다가 키 없이 끝나는 길마다 `syncToIdle`을 불러야
/// 했고, 하나를 빠뜨리면 다음 더블 탭이 "끝내라"로 읽혔다(V17). 여기서는 그 상태가
/// 아예 없다. 판정기는 "두 번 눌렸다"만 말하고, 그것이 시작인지 끝인지는
/// `onTap`이 자식의 단계로 정한다 — 자식이 스스로 끝나면 단계가 사라지므로 맞출
/// 것이 남지 않는다.
///
/// 자동 반복(value 2)은 부르는 쪽이 안 넣는다(함정 1). 커널 입력 코어는 상태가
/// 바뀔 때만 1을 보내므로 같은 누름이 두 번 오는 일은 2 말고는 없다.
pub const DoubleTap = struct {
    step: Step = .idle,
    /// 첫 누름의 시각. `step`이 `idle`이 아닐 때만 뜻이 있다.
    first_down_us: u64 = 0,

    const Step = enum {
        idle,
        /// 첫 누름을 봤고 뗌을 기다린다.
        first_down,
        /// 누름 → 뗌이 끝났고 둘째 누름을 기다린다.
        first_up,
    };

    /// 트리거 키의 누름. 더블 탭이 완성됐으면 참이다.
    ///
    /// `combined`는 다른 수정키가 눌려 있는가다. 그러면 이 누름은 조합의 일부이고
    /// 진행 중이던 판정도 버린다(Voxio `downWithForeignModifierIsNotFed`). 새 판정의
    /// 시작으로도 안 친다 — Shift를 잡은 채 누른 것을 첫 탭으로 세면, Shift를 놓고
    /// 한 번 더 누르는 것이 더블 탭이 된다.
    ///
    /// 창을 넘긴 둘째 누름은 버리지 않고 새 판정의 첫 누름으로 본다(Voxio
    /// `lateSecondTapBecomesNewSequence`). 시각이 거꾸로 가면 창 밖이다.
    pub fn down(self: *DoubleTap, time_us: u64, combined: bool) bool {
        if (combined) {
            self.step = .idle;
            return false;
        }
        if (self.step == .first_up and time_us >= self.first_down_us and
            time_us - self.first_down_us <= WINDOW_US)
        {
            self.step = .idle;
            return true;
        }
        self.step = .first_down;
        self.first_down_us = time_us;
        return false;
    }

    /// 트리거 키의 뗌. 첫 누름 뒤의 뗌만 판정을 앞으로 보낸다 — 그 밖의 뗌은
    /// 짝이 없다(terminal이 뜨기 전부터 눌려 있던 키의 뗌 등).
    pub fn up(self: *DoubleTap) void {
        if (self.step == .first_down) self.step = .first_up;
    }

    /// 진행 중인 판정을 버린다. 다른 키의 누름(조합의 신호, Voxio
    /// `otherKeyDownDiscardsPendingTap`)과 `SYN_DROPPED`(그 사이의 뗌을 잃었을 수
    /// 있다 — design 결정 10의 함정 2)가 부른다.
    pub fn reset(self: *DoubleTap) void {
        self.step = .idle;
    }
};

/// 자식(`tars-dictate`) 하나의 단계. 자식이 없으면 `?Phase`의 null이다.
///
/// 단계를 키 순서가 아니라 자식에게서 읽는 것이 design 결정 10의 함정 3이다.
/// `starting` → `recording`과 `recording` → `transcribing`은 자식의 표준 에러가
/// 옮기고(`phaseAfter`), null로 되돌리는 것은 자식의 끝(표준 출력 · 표준 에러의
/// EOF) 하나뿐이다.
pub const Phase = enum {
    /// 띄웠고 자식이 아직 "recording" 줄을 안 찍었다. 설정과 키를 읽는 중이다 —
    /// 키가 없으면 여기서 끝난다(exit 3).
    starting,
    /// 마이크가 열렸다(`tars-dictate: recording; …`).
    recording,
    /// 녹음이 끝나고 전사 중이다. 둘째 더블 탭이 SIGINT를 보냈거나 자식이
    /// `max_seconds`에서 스스로 멈췄다(`tars-dictate: recording stopped …`).
    transcribing,
    /// Esc가 SIGTERM을 보냈다. 끝나기를 기다린다.
    cancelling,
};

/// 더블 탭이 할 일.
pub const TapAction = enum {
    /// 자식이 없다 — 띄운다.
    start,
    /// 녹음 중이다 — 그룹에 SIGINT(녹음 끝, 전사로).
    stop,
    /// 그 밖 — 아무것도 안 한다.
    ignore,
};

/// 더블 탭의 뜻을 단계로 정한다(Voxio D6 — 시작과 끝이 같은 제스처).
///
/// `starting`의 더블 탭을 무시하는 이유. `tars-dictate`는 `arecord`가 돌기 전에
/// 받은 SIGINT를 "녹음을 끝내라"로 기억만 하고 그 뒤에 `arecord`를 상한(300초)까지
/// 돌린다(M0의 `on_int`). 띄운 직후 수십 ms 안의 둘째 더블 탭이 그 길을 밟으면
/// 사람은 녹음을 끝냈는데 마이크가 5분 열려 있다. "recording" 줄을 본 뒤에만
/// 끝낸다.
///
/// 전사 중의 더블 탭도 무시한다. 그때의 SIGINT는 `tars-dictate`에게 취소다(exit
/// 130) — 말을 다 하고 한 번 더 두드린 손이 받아 적힌 것을 버리게 하지 않는다.
pub fn onTap(phase: ?Phase) TapAction {
    const p = phase orelse return .start;
    return switch (p) {
        .recording => .stop,
        .starting, .transcribing, .cancelling => .ignore,
    };
}

/// 이 단계에서 Esc가 받아쓰기의 것인가(Voxio D11a — 마이크가 열려 있거나 열리는
/// 중일 때만). 참이면 Esc는 취소이고 PTY로 안 간다. 전사 중의 Esc는 뒤의 프로그램의
/// 것이다 — 거기서 먹으면 취소도 안 되면서 vim의 Esc만 사라진다(Voxio
/// `isCapturing`의 주석).
pub fn escCancels(phase: ?Phase) bool {
    const p = phase orelse return false;
    return switch (p) {
        .starting, .recording => true,
        .transcribing, .cancelling => false,
    };
}

/// 자식이 표준 에러에 찍은 한 줄로 단계를 옮긴다. 줄의 글자는 M0의 정본이다
/// (M0 plan "이 milestone이 끝나면"의 로그 줄) — 그쪽을 고치면 여기도 고친다.
///
/// 앞으로만 간다. `transcribing`에서 "recording" 줄을 다시 봐도 안 돌아가고,
/// `cancelling`은 어떤 줄로도 안 바뀐다.
pub fn phaseAfter(phase: Phase, line: []const u8) Phase {
    return switch (phase) {
        .starting => if (std.mem.startsWith(u8, line, "tars-dictate: recording; "))
            .recording
        else
            .starting,
        .recording => if (std.mem.startsWith(u8, line, "tars-dictate: recording stopped "))
            .transcribing
        else
            .recording,
        .transcribing, .cancelling => phase,
    };
}

/// 상태 줄 꼬리의 받아쓰기 칸이 무엇을 말하는가(design 결정 11). 글자는
/// `status.zig`의 `dictWord`가 정한다 — 이 파일은 글자를 모른다.
pub const Show = enum {
    /// 마이크가 열려 있거나 열리는 중이다(`starting` · `recording`).
    rec,
    /// 전사 중이다(`transcribing`).
    wait,
    /// 녹음을 못 했다(exit 1).
    no_mic,
    /// API 키가 없다(exit 3).
    no_key,
    /// 전사가 실패했다(exit 4 · 그 밖의 코드 · 시그널 · 글자가 너무 길다).
    failed,
    /// 비밀번호 프롬프트라 마이크를 안 열었거나 글자를 안 넣었다.
    password,
    /// 트리거를 누른 패널이 그사이 닫혔다. 글자는 기록에 있다.
    no_pane,
};

/// 단계가 보이는 모양. 취소 중에는 아무것도 안 보인다 — 사람이 Esc로 이미 끝낸
/// 것이다.
pub fn showOf(phase: Phase) ?Show {
    return switch (phase) {
        .starting, .recording => .rec,
        .transcribing => .wait,
        .cancelling => null,
    };
}

/// 자식이 끝난 뒤 할 일.
pub const Outcome = union(enum) {
    /// 모은 표준 출력을 대상 패널에 넣는다.
    insert,
    /// 아무것도 안 한다. 상태 줄도 비운다.
    quiet,
    /// 상태 줄에 알린다. 다음 키에 사라진다.
    notice: Show,
};

/// 종료 코드를 읽는다(design 결정 6의 표 — M0 `tars-dictate`의 머리 주석이 정본).
///
/// `code`가 null이면 자식이 시그널로 죽었다(`tars-dictate`는 INT · TERM을 trap하므로
/// 그 둘로는 이렇게 안 끝난다 — SIGKILL 등이다). 취소 중이었으면 무엇으로 끝났든
/// 조용하다 — 사람이 끝낸 것이다.
///
/// 2(무음 · 0바이트)와 130 · 143(취소)은 조용하다. 64(인자)와 127(`execve` 실패,
/// `main.zig`의 자식이 그 값으로 나간다)은 사람이 고칠 수 있는 설정 문제가 아니라서
/// 전사 실패와 같은 칸이다 — 자세한 것은 시리얼 로그의 `dictate> exit` 줄에 있다.
pub fn outcome(phase: Phase, code: ?u8) Outcome {
    if (phase == .cancelling) return .quiet;
    const c = code orelse return .{ .notice = .failed };
    return switch (c) {
        0 => .insert,
        2, 130, 143 => .quiet,
        1 => .{ .notice = .no_mic },
        3 => .{ .notice = .no_key },
        else => .{ .notice = .failed },
    };
}

/// 비밀번호 프롬프트인가(design 위험 2). ghostty와 같은 판정이다
/// (`termio/Exec.zig` — `mode.canonical and !mode.echo`).
///
/// `ECHO`만 보면 안 된다. 셸의 줄 편집기(readline · zle · fish)와 vim은 글자를 자기가
/// 그리므로 `ECHO`를 끄고 `ICANON`도 끈다 — `ECHO`만 보면 모든 셸 프롬프트가
/// 비밀번호다. `sudo` · `ssh` · `bash`의 `read -s`처럼 줄 단위로 읽으면서 안 보여 주는
/// 것만 `ICANON`이 켜지고 `ECHO`가 꺼진다.
///
/// 이 판정이 못 보는 것 — 자기 편집기로 가리는 프로그램(fish의 `read -s`가 그렇다,
/// 글자를 •로 그린다). 그런 프롬프트에는 글자가 들어간다(Enter는 안 붙는다).
pub fn isPasswordPrompt(canonical: bool, echo: bool) bool {
    return canonical and !echo;
}

/// 넣기 전에 한 번 더 거른다(design 결정 11 — "방어 한 겹"을 고른다).
///
/// 규칙은 `tars-dictate`의 `printable | strip`과 같다. 탭과 개행만 남기고 C0 · DEL ·
/// C1을 지운 뒤, 앞뒤의 공백 · 탭 · 개행을 뗀다. 두 번 거르는 이유는 이 자리가
/// 돌이킬 수 없는 유일한 자리이기 때문이다 — ESC 하나가 살면 `ESC[201~`로 bracketed
/// paste를 닫고 뒤를 명령으로 흘릴 수 있고(Voxio 94e0e64), 끝의 개행은 Enter다.
/// 표준 출력을 만든 쪽이 무엇이든(사람이 `/usr/bin/tars-dictate`를 바꿨든) 이 규칙은
/// terminal이 지킨다.
///
/// UTF-8을 풀지 않는다. C1(U+0080~U+009F)은 UTF-8로 `C2 80` ~ `C2 9F` 두 바이트이고,
/// 0x80~0x9F 홀로는 다른 글자의 꼬리 바이트라 지우면 안 된다(`한`의 꼬리가 0x9C다).
/// 그래서 `C2` 뒤의 그 범위만 짝으로 지운다.
///
/// 제자리에서 고치고 남은 조각을 돌려준다(시작이 `buf[0]`이 아닐 수 있다).
pub fn sanitize(buf: []u8) []const u8 {
    var w: usize = 0;
    var i: usize = 0;
    while (i < buf.len) {
        const b = buf[i];
        if (b == 0xC2 and i + 1 < buf.len and buf[i + 1] >= 0x80 and buf[i + 1] <= 0x9F) {
            i += 2;
            continue;
        }
        if ((b < 0x20 and b != '\t' and b != '\n') or b == 0x7F) {
            i += 1;
            continue;
        }
        buf[w] = b;
        w += 1;
        i += 1;
    }
    return std.mem.trim(u8, buf[0..w], " \t\n");
}
