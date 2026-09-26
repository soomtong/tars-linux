# TD-M2 — drift를 배우고 부팅을 넘긴다

> 이 plan을 실행하는 사람에게: Task마다 `git diff --stat`으로 더한 줄과 지운
> 줄을 세고, 지우는 편집은 `git diff | grep '^-'`로 내용을 읽는다. 반사실은
> 돌리기 전에 `git diff`로 편집이 들어갔는지 먼저 찍는다(TD design 실측 12).

Goal: `/config`가 붙은 부팅에서 chronyd가 `confdir /config/chrony.d`와
`driftfile /config/chrony.drift`를 쓴다. 게이트가 500ppm 빠른 stub을 상대로
배운 값이 전원을 끌 때 디스크에 남고, 다시 켠 부팅이 그 값에서 출발하는 것을
본다.

Architecture: `renderConf`가 `keep`(= `/config`가 붙었나)을 받아 두 줄을 더한다.
`main.zig`는 이미 있는 `storage_mounted`를 넘긴다. 게이트는 부팅 C · D를 더하고,
둘이 같은 디스크 이미지 `out/net-drift.img`를 이어받는다.

Tech Stack: Zig(init) · chrony 4.6.1 · bash · perl · debugfs

---

## 정한 것

### 결정 M2-A — 설정 파일의 모양

`keep`이면:

```
confdir /config/chrony.d
server A.B.C.D iburst
makestep 1 3
driftfile /config/chrony.drift
cmdport 0
```

아니면 M1의 세 줄 그대로다. `confdir`가 맨 앞인 것은 같은 서버가 두 번이면
먼저 적힌 쪽이 이기기 때문이다(M0 실측 9). 가장 긴 모양(255.255.255.255)이
109바이트라 `CONF_MAX = 128`에 든다 — `clock_test`가 그 경우를 직접 본다.

`/config`가 없으면 자식이 로그 한 줄을 남긴다. 붙었으면
`tars-init: chronyd keeps its drift in /config/chrony.drift`, 아니면
`tars-init: no /config, chronyd forgets its drift at power-off`.

### 결정 M2-B — 판정은 디스크에서 읽는다 (design 결정 9 조정)

design 결정 9는 게이트도 `chronyc`로 판정한다고 적었다. 배운 값을 보는 데는
더 곧은 길이 있다 — 전원이 꺼진 뒤 컨테이너가 `debugfs -R "cat /chrony.drift"`로
디스크 이미지를 직접 읽는다. 그 한 번이 "배웠다"와 "끌 때 썼다"를 함께 증명하고,
화면 타이핑(에코 함정)이 없다. `chronyc`는 사람의 창으로 남는다.

### 결정 M2-C — `confdir`의 증거는 stub이 받은 요청 수다

`Could not add source 10.0.2.2`는 증거가 못 된다. 순서가 어느 쪽이든 둘 중 하나가
그 줄을 찍는다(M0 실측 9). 대신 `Selected source` 뒤 20초 동안 stub이 받은
요청을 센다. gate.conf의 `minpoll -2`(0.25초)가 이겼으면 수십 번이고, `init`의
줄(기본 폴링 64초)이 이겼으면 0~1번이다. 문턱은 20이다.

### 결정 M2-D — 부팅 C는 20초 배운다

M0 실측 5에서 500ppm을 8초 안에 잡았다. 20초는 그 두 배 반이고, 판정 창
−550~−450ppm은 잡음(한 자릿수 ppm)의 열 배 넘게 넓다. 그리고 M1 실측 15가 본
"뜨자마자 끈 chronyd는 driftfile을 안 쓴다"를 피한다 — chronyd가 산 지 30초가
넘는다.

### 결정 M2-E — 포트와 이름

monitor는 45469(C) · 45470(D). 둘 다 어느 체인도 안 쓴다. 디스크 라벨은
`tars-drift`.

## Task 1 — `clock.zig`가 `/config`를 넘긴다

Files: Modify `init/src/clock.zig` · `init/src/clock_test.zig` · `init/src/main.zig`

- [ ] Step 1: `clock_test.zig`의 `expectConf`가 `keep`을 받고 경우 넷을 본다

```zig
fn expectConf(server: [4]u8, keep: bool, want: []const u8) !void {
    var buf: [clock.CONF_MAX]u8 = undefined;
    const got = clock.renderConf(&buf, server, keep) orelse {
        std.debug.print("FAIL: the config for {d}.{d}.{d}.{d} (keep={}) did not fit\n", .{
            server[0], server[1], server[2], server[3], keep,
        });
        return error.ConfTooLong;
    };
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: got\n{s}---\nwant\n{s}---\n", .{ got, want });
        return error.WrongConf;
    }
}
```

```zig
    try expectConf(.{ 10, 0, 2, 2 }, false, "server 10.0.2.2 iburst\nmakestep 1 3\ncmdport 0\n");
    try expectConf(.{ 255, 255, 255, 255 }, false, "server 255.255.255.255 iburst\nmakestep 1 3\ncmdport 0\n");
    std.debug.print("clock_test: without /config the chrony config names the server, steps once and closes the udp command port\n", .{});

    // TD-M2. /config가 붙은 부팅. confdir가 맨 앞이어야 사람이 적은 같은
    // 서버가 이긴다(TD design 실측 9) — 이 순서를 바꾸는 사람은 게이트의
    // 검사 26이 빨개지는 것을 보게 된다.
    try expectConf(.{ 10, 0, 2, 2 }, true, "confdir /config/chrony.d\nserver 10.0.2.2 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    // 가장 긴 모양. 109바이트라 CONF_MAX(128)에 든다.
    try expectConf(.{ 255, 255, 255, 255 }, true, "confdir /config/chrony.d\nserver 255.255.255.255 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with /config it reads chrony.d first and keeps its drift there\n", .{});
```

- [ ] Step 2: 빨간지 본다 — `renderConf`가 인자 둘이라 컴파일 에러

- [ ] Step 3: `clock.zig`의 `renderConf`

```zig
/// `/config`가 붙은 부팅에서 chronyd가 쓰는 두 자리(TD design 결정 5 · 8).
const CONFIG_CONFDIR = "/config/chrony.d";
const CONFIG_DRIFT = "/config/chrony.drift";

pub fn renderConf(buf: []u8, server: [4]u8, keep: bool) ?[]const u8 {
    const head: []const u8 = if (keep) "confdir " ++ CONFIG_CONFDIR ++ "\n" else "";
    const tail: []const u8 = if (keep) "driftfile " ++ CONFIG_DRIFT ++ "\n" else "";
    return std.fmt.bufPrint(buf, "{s}server {d}.{d}.{d}.{d} iburst\nmakestep 1 3\n{s}cmdport 0\n", .{
        head, server[0], server[1], server[2], server[3], tail,
    }) catch null;
}
```

그 위 doc 주석에 `keep`일 때의 두 줄을 더한다.

- [ ] Step 4: `writeConf(server, keep)` · `start(net, want, keep, envp)`로 인자를 넘기고,
  자식이 `chronyd will ask` 앞에 결정 M2-A의 한 줄을 찍는다.

- [ ] Step 5: `main.zig` — `clock.start(cfg.net, cfg.ntp, storage_mounted, envp);`

- [ ] Step 6: `zig build test` · `zig build` 초록, 커밋
  `Keep chronyd's drift and read chrony.d when /config is there`

## Task 2 — 디스크에 gate.conf를 심는다

Files: Modify `net/make_disk.sh`

- [ ] Step 1: 끝에 더한다

```bash
# TD-M2. 부팅 C · D가 이어받는 디스크. 부팅 C의 chronyd가 끌 때 여기에
# chrony.drift를 쓰고, 부팅 D의 chronyd가 그것을 읽는다 — 체인은 두 부팅
# 사이에 이 이미지를 다시 굽지 않는다.
#
# chrony.d/gate.conf가 폴링을 0.25초로 줄인다(TD design 결정 8). init이 쓰는
# 설정의 server 줄과 주소가 같고, confdir가 맨 앞이라 이쪽이 이긴다(M0 실측 9).
# 사람이 같은 자리에 `pool pool.ntp.org iburst`를 적는 것과 같은 길이다.
bake ../out/net-drift.img tars-drift "net=dhcp
ntp=${NTP_SERVER}
"
GATE_CONF="$(mktemp)"
printf 'server %s iburst minpoll -2 maxpoll -2\n' "$NTP_SERVER" > "$GATE_CONF"
debugfs -w -R "mkdir chrony.d" ../out/net-drift.img 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write ${GATE_CONF} chrony.d/gate.conf" ../out/net-drift.img 2>&1 | grep -v '^debugfs' || true
rm -f "$GATE_CONF"
echo "make_disk: planted chrony.d/gate.conf in ../out/net-drift.img"
```

- [ ] Step 2: 컨테이너에서 굽고 `debugfs -R "cat /chrony.d/gate.conf"`로 확인

## Task 3 — 부팅 C · D

Files: Modify `net/check.sh`

- [ ] Step 1: TS-M2 변수 블록 뒤에 TD-M2 블록(포트 둘 · `DRIFT_PPM=500` · 창
  `-550`~`-450` · `DRIFT_LEARN_SECONDS=20` · `DRIFT_MIN_ANSWERS=20` · `LOGC` · `LOGD` ·
  `QEMU_PID_C` · `QEMU_PID_D`), `cleanup`에 C · D.
- [ ] Step 2: 부팅 B 뒤, `echo "PASS"` 앞에 부팅 C · D와 검사 25~28. 도우미 셋
  (`wait_in_log` · `start_drift_guest` · `power_off_guest`)과 `in_drift_window`(awk).
  - 검사 25 — `tars-init: chronyd keeps its drift in /config/chrony.drift`
  - 검사 26 — `Selected source` 뒤 20초 동안 stub 요청이 20 이상
  - 검사 27 — 끈 뒤 `debugfs`로 읽은 `/chrony.drift`의 첫 수가 창 안
  - 검사 28 — 부팅 D의 `Frequency F +/- S ppm read from /config/chrony.drift`의 F가 창 안
  - C · D 둘 다 `grace period expired`가 없다
- [ ] Step 3: 머리 주석에 TD-M2 절
- [ ] Step 4: 체인 단독, 게스트 로그를 `-v /tmp/tdm2:/tmp`로 남겨 읽는다. 커밋
  `Learn a 500 ppm drift and carry it across a power-off in the network chain`

## Task 4 — 반사실 둘

1. `driftfile` 줄을 뺀다(`clock_test` 기대값도) → 검사 27 빨강
2. `confdir`를 `server` 뒤로 옮긴다(`clock_test` 기대값도) → 검사 26 빨강

## Task 5 — 루트 게이트 3/3, 닫기

`CHAINS`를 `TD-M2`로, design 실측 · Status(끝났다) · 기억 · `CLAUDE.md` 표 한 줄 ·
HANDOFF.
