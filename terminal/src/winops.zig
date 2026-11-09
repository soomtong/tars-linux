//! 패널 출력에서 xterm의 `CSI 10 ; Ps t`(전체 화면)를 훑는다(FU-M1, design 결정 4의 셋째 · 5).
//!
//! lib-vt는 XTWINOPS의 10을 경고만 남기고 버린다(design 확인 7). 그래서 terminal이 lib-vt에 넣기 전에
//! 같은 바이트를 한 번 더 본다. 이 모듈은 바이트를 바꾸지도 빼지도 않는다 — 부르는 쪽이 같은 덩이를
//! 그대로 lib-vt에 넘긴다. 그러니 다른 시퀀스의 해석은 한 바이트도 안 바뀐다.
//!
//! 패널마다 하나다. 상태가 `feed` 호출 사이에 남으므로 pty read 경계에서 잘린 시퀀스를 이어 읽는다.
//! 순수하다 — 호스트의 `winops_test`가 본다.

pub const Scanner = struct {
    state: State = .ground,
    /// 매개변수 칸 둘. 셋째 칸이 오면 skip으로 간다(우리 것이 아니다).
    params: [2]u32 = .{ 0, 0 },
    /// 지금 쓰는 칸의 번호(0 또는 1).
    idx: u1 = 0,
    /// 첫 칸에 숫자가 하나라도 왔는가. `CSI ;1t`(첫 칸이 빈)는 10이 아니다.
    first_digit: bool = false,

    const State = enum { ground, esc, csi, skip };

    /// 값이 이보다 크면 10도 0 · 1 · 2도 아니다. 넘침을 막으려고 여기서 멈춘다(그 뒤 숫자는 안 센다).
    const PARAM_CAP: u32 = 100_000;

    /// `bytes`를 훑으며 그 안의 `CSI 10 ; Ps t`를 차례로 `on`에 적용한 결과를 돌려준다.
    /// Ps 0 끄기 · 1 켜기 · 2 바꾸기(xterm과 같은 뜻). 빈 Ps는 0이다(xterm과 같다).
    /// 칸 수가 둘이 아니거나 첫 칸이 10이 아니거나 Ps가 그 밖이면 아무것도 안 한다.
    pub fn feed(self: *Scanner, bytes: []const u8, on: bool) bool {
        var want = on;
        for (bytes) |b| {
            // VT의 규칙: ESC는 어느 상태에서든 새 시퀀스를 열고, CAN · SUB는 시퀀스를 버린다.
            if (b == 0x1b) {
                self.state = .esc;
                continue;
            }
            if (b == 0x18 or b == 0x1a) {
                self.state = .ground;
                continue;
            }
            switch (self.state) {
                .ground => {},
                .esc => {
                    if (b == '[') {
                        self.params = .{ 0, 0 };
                        self.idx = 0;
                        self.first_digit = false;
                        self.state = .csi;
                    } else {
                        // 다른 ESC 시퀀스(`ESC 7`, `ESC ]` 등) — 우리 것이 아니다. 이어지는 바이트는 ground에서
                        // 본다. OSC 문자열 안의 `ESC [`도 VT에서는 CSI를 연다(위 ESC 규칙) — 같은 판정이다.
                        self.state = .ground;
                    }
                },
                .csi => switch (b) {
                    '0'...'9' => {
                        const p = &self.params[self.idx];
                        if (p.* < PARAM_CAP) p.* = p.* * 10 + (b - '0');
                        if (self.idx == 0) self.first_digit = true;
                    },
                    ';' => {
                        if (self.idx == 1) {
                            self.state = .skip; // 셋째 칸
                        } else {
                            self.idx = 1;
                        }
                    },
                    't' => {
                        if (self.idx == 1 and self.first_digit and self.params[0] == 10) {
                            want = switch (self.params[1]) {
                                0 => false,
                                1 => true,
                                2 => !want,
                                else => want,
                            };
                        }
                        self.state = .ground;
                    },
                    // 다른 끝 바이트 — 다른 CSI 시퀀스가 끝났다.
                    0x40...0x73, 0x75...0x7e => self.state = .ground,
                    // 중간 바이트 · 개인 표지 · 부분 매개변수(`:`) — 우리 모양이 아니다. 끝 바이트까지 넘긴다.
                    0x20...0x2f, ':', '<'...'?' => self.state = .skip,
                    // 그 밖의 C0(줄바꿈 등)와 DEL은 시퀀스 안에서도 상태를 안 바꾼다(VT의 규칙).
                    0x00...0x17, 0x19, 0x1c...0x1f, 0x7f => {},
                    // 0x80 이상(UTF-8 글자의 바이트) — 시퀀스가 깨졌다고 본다.
                    else => self.state = .ground,
                },
                .skip => switch (b) {
                    0x40...0x7e => self.state = .ground,
                    else => {},
                },
            }
        }
        return want;
    }
};
