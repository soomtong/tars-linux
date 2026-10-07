# TARS Atomic Log Lines — Design

Date: 2026-10-07
Status: 설계. 착수 전 실측까지 끝났고 milestone 둘(AL-M0 terminal · AL-M1 init)의 plan은 아직 없다.

TC(Config Tool)를 닫으며 남긴 후속이다(`HANDOFF.md`, TC-M3 plan의 "닫을 때 lead가 고칠 자리").

> 컨테이너 Zig 0.16의 `std.debug.print`는 64바이트 버퍼로 stderr를 잠그고 `print`하므로 64바이트를 넘는 줄은 write 둘 이상으로 나간다.
> terminal · init 둘 다 `std.debug.print`로 시리얼 줄을 내고, 두 프로세스가 같은 /dev/console(ttyS0)에 쓰니 그 사이에 서로의 write가
> 끼어든다. tty 층은 write() 한 번은 통째로 잠그므로 한 줄을 write 한 번에 내면 사용자 공간 둘 사이의 자름은 사라진다. (lead)

## 한 줄 요약

terminal과 init이 시리얼에 내는 줄을 전부 `logline.zig`의 고정 버퍼에 다 짓고 `write(2, …)` 한 번으로 낸다. 화면 dump처럼 여러 조각으로 짓던 줄도
한 버퍼에 조립한다. 루트 `check.sh`가 회차마다 그 회차의 게스트 로그를 모두 훑어 "남의 줄이 끼어든 줄"을 세고, 하나라도 있으면 그 회차를 빨갛게 한다.

```
AL-M0   terminal — logline.zig(Line · print), std.debug.print 98곳, 화면 dump를 한 버퍼에. 루트 check.sh가 회차별 로그 디렉터리를 갖고
        "terminal 줄 안의 tars-init" 수를 센다(0이 아니면 FAIL). 로그를 지우던 체인 여덟이 안 지운다
AL-M1   init — 같은 logline.zig(사본 · cmp 진입 검사), std.debug.print 153곳, config.zig의 log 싱크. 거꾸로 방향
        "tars-init 줄 안의 terminal"도 FAIL로 올린다. joined_screen_dump의 tars-init 꼬리 떼기를 지운다
```

## 왜 생기나 — 실측으로 이은 사슬

1. `std.debug.print`는 부를 때마다 64바이트 버퍼로 stderr를 잠그고, 다 쓰면 비운다(컨테이너 `/usr/local/zig/lib/std/debug.zig:307`,
   `Io/Threaded.zig:13832`의 `unlockStderr`가 `flush`). 그래서 한 번 부르면 write가 적어도 한 번이고, 64바이트를 넘으면 둘 이상이다.
2. terminal의 화면 dump(`dumpScreen`, `terminal/src/main.zig:677`)는 머리 · 칸 하나 · ` | ` · `\n`을 따로 `print`한다. 화면 한 줄이 글자 수만큼의
   write다. TC-M3 루트 게이트 한 회차(gate4_1)의 `screen>` 줄은 9,652개 · 7,293,617바이트였다 — 칸 하나가 많아야 4바이트이므로 write는 적어도
   180만 번이다.
3. init(PID 1)의 fd 2는 커널이 열어 준 /dev/console이고 terminal은 그것을 물려받는다(`init/src/main.zig`의 `spawn`, terminal 쪽은 fd를
   안 바꾼다). /dev/console의 write는 `redirected_tty_write` → `file_tty_write`로 ttyS0의 tty에 간다(커널 6.18.42 `drivers/tty/tty_io.c:1105`).
4. 그 tty의 `iterate_tty_write`(`tty_io.c:952`)는 write 한 번 내내 `atomic_write_lock`을 쥔다. 2048바이트씩 끊어 line discipline에 넘기지만,
   끊는 자리에서 놓는 것은 처리할 시그널이 걸려 있을 때뿐이다(`signal_pending` → `-ERESTARTSYS`로 그때까지 쓴 만큼 돌려준다).
5. 그러니 write 한 번 안에는 아무도 못 끼어들고, write와 write 사이에는 누구나 끼어든다. 1과 2가 사이를 수천 개 만든다.

자르개는 셋이다. 이 design이 없애는 것은 첫째 둘뿐이다.

| 쓰는 쪽 | 어떻게 자르나 | 이 design 뒤 |
|---|---|---|
| terminal ↔ init | 64바이트 조각 · 칸마다 print 사이에 서로의 write | 사라진다(결정 1 · 2) |
| 커널 printk | 콘솔 드라이버가 UART에 직접 쓴다 — tty 잠금 밖 | 그대로. `joined_screen_dump`가 잇는다(결정 5) |
| 콘솔 셸 · 서비스의 표준 출력 | 줄바꿈 없는 프롬프트 뒤에 남의 온전한 줄이 붙는다 | 그대로(비목표 2) |

## 결정

### 결정 1 — `logline.zig` 하나, 사본 둘. 줄은 2048바이트까지 write 한 번

모양:

```zig
pub const MAX = 2048;          // 커널 tty가 write 한 번을 쪼개는 단위(tty_io.c의 chunk)
pub const CUT = " [cut]\n";    // 넘친 줄의 꼬리

pub const Line = struct {      // 한 줄을 여러 조각으로 짓는 버퍼(결정 2)
    pub fn init(buf: []u8) Line
    pub fn print(self: *Line, comptime fmt: []const u8, args: anytype) void
    pub fn bytes(self: *const Line) []const u8
    pub fn flush(self: *Line) void   // write(2, bytes) 한 번. 짧게 쓰이면 나머지를 마저, EINTR이면 다시, 다른 에러는 버린다
};

pub fn print(comptime fmt: []const u8, args: anytype) void   // 스택의 [MAX]u8 하나에 Line.print 뒤 flush
```

- 이름이 `print`이고 fmt를 그대로 받는다. 바꾸기가 `std.debug.print(` → `logline.print(`의 기계적 치환이 되고, 들어가는 fmt가 같으니 나가는
  바이트도 같다(넘친 줄만 빼고 — 아래).
- 넘치면 자르고 표시한다. `std.Io.Writer.fixed`가 버퍼를 끝까지 채운 뒤 `error.WriteFailed`를 낸다(실측 E) — 그 자리에서 마지막 글자가 다
  들어왔는지 보고(UTF-8 머리 바이트의 길이로) 모자라면 그 글자 앞에서 자른 뒤 ` [cut]\n`을 붙인다. 버퍼는 처음부터 `CUT` 자리를 비워 둔다. 넘친
  뒤의 `print`는 아무것도 안 한다. 그래서 잘린 줄도 늘 `\n`으로 끝나고 다음 줄의 머리를 먹지 않는다.
- 2048인 까닭. 커널은 2048바이트보다 긴 write를 2048씩 끊고, 끊는 자리에서 처리할 시그널이 걸려 있으면 거기서 돌려준다(사슬 4). 2048 이하는 끊을
  자리가 없어 시그널과 무관하게 한 덩이다. init은 SIGTERM · SIGINT 처리기를 단다(`power.zig:62`) — init의 줄을 2048 안에 묶으면 "write 한 번 = 끼어들
  수 없음"이 시그널을 따지지 않고 참이다. 지금 가장 긴 줄은 init 247바이트, terminal의 `screen>` 밖 111바이트다(실측 B).
- 에러는 삼킨다. 로그를 못 쓴 것 때문에 PID 1이 멈추면 안 된다. `catch` 밖으로 에러가 안 나가고, 런타임 값에 `assert` · `unreachable`이 없다 —
  init은 ReleaseSafe라 그 둘이 패닉이고, PID 1의 패닉은 커널 패닉이다. 범위를 넘는 슬라이스가 생길 자리(잘린 자리 계산 · `CUT` 복사)는 호스트 검사가
  경계값으로 덮는다(정확히 맞음 · 하나 넘침 · 한글 가운데 · 빈 fmt · `\n` 없는 fmt).
- 시스템 콜은 `std.os.linux.write`다. init은 libc가 없고 terminal은 libc를 링크하지만 같은 리눅스 시스템 콜을 직접 불러도 된다 — 그래서 두 빌드에
  같은 파일이 그대로 선다.

파일은 둘이다 — `terminal/src/logline.zig`(AL-M0)와 `init/src/logline.zig`(AL-M1)이고, 바이트까지 같다. 루트 `check.sh`의 진입 검사가 `cmp`로
지킨다. 공용 모듈 하나(`b.path("../…")`)도 컨테이너 Zig 0.16에서 선다(실측 F). 그래도 사본을 고른 이유:

- Zig는 모듈 루트 밖의 파일을 `@import("../…")`로 못 읽는다. 공용 모듈이면 그 파일을 import하는 모든 모듈에 `addImport`를 달아야 하는데, init은
  `audio.zig` · `firewall.zig` 같은 모듈을 시험하는 test 모듈이 열다섯이 넘고 terminal은 `vt_test` · `font_test`가 걸린다. 사본이면 `build.zig`가
  한 줄도 안 바뀐다 — 같은 디렉터리의 `@import("logline.zig")`다.
- 저장소에 아직 init과 terminal이 나눠 쓰는 소스가 없다. 첫 공유를 로그 helper로 열 까닭이 없다.
- 어긋남은 `cmp` 한 번으로 0.01초 안에 잡힌다. 같은 글을 두 곳에 두고 손으로 맞추던 앞선 예(`copy/check.sh`와 `dumpClip`의 문구, CM design
  결정 8)와 달리 이쪽은 기계가 본다.

호스트 검사는 `terminal/src/logline_test.zig` 하나(AL-M0, terminal의 `zig build test`)다. init의 사본은 `cmp`가 같다고 말하므로 따로 시험하지
않는다.

### 결정 2 — 여러 조각으로 짓던 줄은 `Line` 하나에. 화면 dump만 큰 버퍼

여러 `print`로 한 줄을 짓는 자리를 기계적으로 찾았다 — 줄바꿈으로 안 끝나는 fmt를 쓰는 `std.debug.print`는 다섯 곳뿐이다(실측 C).

- `terminal/src/main.zig`의 `dumpScreen` 셋(`"terminal: screen> "` · `" | "` · `"{s}"`) — 진짜 여러 조각이다.
- `init/src/main.zig:32`의 `configLog`와 `init/src/config.zig:29`의 `log` — `"tars-init: " ++ fmt ++ "\n"`이라 컴파일 타임에 붙는 한 fmt다. 조각이
  아니다.

`style>` · `pixel>` · `pointer>` · `cursor>` · `ink>`는 줄마다 `print` 한 번이다. 64바이트를 넘는 것이 잘리던 까닭(TC-M3 1회차의 `pointer> … ink=`가
정확히 65바이트째에서 잘렸다)이라 결정 1의 치환만으로 낫는다.

`dumpScreen`은 `Line` 하나에 머리 · 칸 · 구분자 · `\n`을 차례로 `print`하고 끝에 `flush` 한 번이다. 버퍼는 스택이 아니라 격자가 정해지는 자리
(`terminal: grid {d}x{d}` 줄 근처)에서 한 번 할당한다 — 크기는

```
rows × (cols × 4 + 3) + "terminal: screen> ".len + 1
```

칸 하나의 글자가 UTF-8로 많아야 4바이트(`CellGlyph.codepoint`는 u21)이고, 줄이 바뀔 때마다 ` | ` 3바이트, 끝에 `\n`이다. 이 수는 그 화면이 낼 수
있는 가장 긴 dump의 위 한계라 화면 dump는 결코 잘리지 않는다. QEMU의 155×47이면 29,345바이트이고, 지금 가장 긴 dump는 7,172바이트다(실측 B).
실기계의 큰 화면은 격자가 커지는 만큼 버퍼도 커진다. 고정 크기(예: 64KiB)로 두면 4K 화면에서 한글이 꽉 찬 dump가 잘린다 — 게이트는 그 화면을
안 보지만, 잘린 화면 dump는 사람이 실기계 로그를 읽을 때 거짓말을 한다.

화면 dump는 2048을 넘는다(결정 1의 2048은 `print`의 버퍼이지 write의 한계가 아니다). 그래도 끊기지 않는 까닭 — terminal은 시그널 처리기를 하나도
달지 않는다(`sigaction` · `signalfd` 0곳). SIGCHLD는 기본 처리가 "무시"라 걸리지조차 않고, SIGTERM · SIGKILL은 처리기가 없으니 프로세스가 끝난다.
그래서 terminal의 write에는 "처리할 시그널이 걸린 채 2048 경계에 닿는" 일이 없다. terminal에 처리기를 다는 날 이 문단이 거짓이 된다 —
`logline.zig`의 주석에 그 조건을 적는다.

### 결정 3 — 게스트에서 도는 `std.debug.print`는 전부. 진입 검사가 0을 지킨다

바꾸는 것은 `init/src` · `terminal/src`의 `*_test.zig`가 아닌 파일에 있는 `std.debug.print` 전부다.

| 바이너리 | 파일 | 곳 |
|---|---|---|
| terminal | `main.zig` 90 · `drm.zig` 6 · `font.zig` 1 · `vt.zig` 1 | 98 |
| init | `main.zig` 55 · `audio.zig` 23 · `firewall.zig` 14 · `power.zig` 14 · `clock.zig` 11 · `services.zig` 11 · `devices.zig` 7 · `net.zig` 7 · `wifi.zig` 4 · `config.zig` 2 · `control.zig` 2 · `login.zig` 2 · `storage.zig` 1 | 153 |

시리얼로 가는 것만 고르지 않는 까닭. 이 파일들이 `print`하는 곳은 전부 fd 2이고 init · terminal의 fd 2는 언제나 /dev/console이다. 같은 파일이
`tars-config` · `tars-service` · `tars-install`에도 들어가는데(예: `config.zig`), 그쪽 fd 2는 사람의 터미널이고 거기서도 "한 줄 = write 한 번"이
해롭지 않다. 고를 기준이 없으니 고르지 않는다 — 그리고 "0곳"이라야 진입 검사가 한 줄로 선다.

- 진입 검사(루트 `check.sh`). `init/src` · `terminal/src`에서 `*_test.zig`를 뺀 파일의 `std.debug.print`가 0이어야 한다. AL-M0은 `terminal/src`만,
  AL-M1이 `init/src`를 더한다. 새 코드가 `std.debug.print`를 다시 쓰면 게이트가 시작 전에 멈춘다.
- `*_test.zig`의 `print` 1,000여 곳은 대상이 아니다. 호스트 검사의 출력이고 시리얼에 안 간다.
- TC 결정 3의 `config.zig` `log()`. 가로채기(`root.configLog`를 컴파일 타임에 고른다)는 그대로이고 바뀌는 것은 가로채는 쪽이 없을 때의 싱크
  (`std.debug.print` → `logline.print`)와 init 쪽 가로채기(`main.zig`의 `configLog`)의 첫 줄뿐이다. `tars-config`의 `configLog`는 자기 stderr에
  자기 방식으로 쓰므로 안 건드린다.

### 결정 4 — 게이트: 새 체인 없이 루트 `check.sh`가 회차마다 센다

`run_chain`이 회차마다 그 회차만의 로그 디렉터리를 만들어 `TMPDIR`로 체인에 넘긴다 — 체인의 `mktemp`가 전부 그 안에 생긴다. 체인이 끝나면
(통과든 실패든) 그 디렉터리를 `gate_lib.sh`의 새 함수로 훑어 끼어든 줄을 센다.

```
<게이트 TMPDIR>/tars-gate.XXXXXX/<chain>-<run>/tmp.*      예: …/CB-M0-2/tmp.Jt5vgehpSt
```

세는 줄(둘 다 `grep -a`, 디렉터리 아래 모든 일반 파일):

- A — `^terminal: .*tars-init: ` — terminal의 줄 가운데에 init의 줄이 끼었다.
- B — `^tars-init: .*terminal: ` 가운데 `^tars-init: reload terminal: pid `로 시작하지 않는 것 — init의 줄 가운데에 terminal의 줄이 끼었다. 뺀 것은
  init이 제 글로 `terminal: `을 쓰는 유일한 fmt(`init/src/main.zig:639`)다. 이 목록 밖의 init fmt가 `terminal: `을 담게 되면 B가 거짓으로
  빨갛다 — 시끄러운 쪽이라 받아들이고, 그때 목록에 하나 더한다.

판정:

- AL-M0 뒤에는 A가 구조적으로 0이다 — terminal의 줄이 write 한 번이면 그 한가운데에 아무것도 못 들어간다. B는 init이 아직 조각으로 쓰므로 남는다.
  그래서 AL-M0은 A가 하나라도 있으면 그 회차를 FAIL로, B는 수만 찍는다.
- AL-M1 뒤에는 둘 다 0이다. AL-M1이 B도 FAIL로 올린다.
- FAIL이면 그 줄들을 파일 이름과 함께 찍는다. 회차 디렉터리 이름에 체인과 회차가 있으므로 어느 체인의 어느 부팅인지 바로 안다.

로그를 지우던 체인. 셈이 회차 디렉터리를 훑으려면 로그가 남아 있어야 하는데 여덟 체인 열한 자리가 로그를 지운다 — `audio`(cleanup) ·
`dictation`(cleanup · 538행) · `firewall`(cleanup) · `nic`(cleanup) · `service`(cleanup · 348행 · 633행) · `wifi`(cleanup) · `pointer`(1652행), 그리고
`install`은 로그를 `$WORK` 안에 두고 cleanup이 `$WORK`를 지운다. 그 자리에서 로그만 빼고 지운다(`$WORK` · `$SEED`의 디스크 이미지 · WAV는 그대로
지운다. `install`은 로그 경로를 `mktemp`로 옮긴다). 로그의 주인은 이제 루트 `check.sh`의 회차 디렉터리 하나다. 한 회차의 로그는 약 46MB다(실측 A의
gate4_1). 컨테이너는 `--rm`이고, lead가 `-e TMPDIR=`로 bind-mount해 두면 체인별로 나뉜 채 호스트에 남아 사후 조사가 지금보다 쉬워진다.

QEMU 없는 진입 검사. `require_screen_dump_joins`와 같은 모양으로, 실측 A의 실제 줄 넷을 고정 조각으로 두고 세는 함수가 A 1 · B 1 · 0 · 0을 내는지
본다 — 잘린 `pointer>` 줄(A), `login shell … tars-env.conf`에 `screen>`이 붙은 줄(B), 온전한 `reload terminal: pid 39 …` 줄(0), 화면 글자에
`fzf-history-widget: function`이 든 온전한 `screen>` 줄(0).

왜 체인마다가 아니라 루트인가. 체인이 스물하나이고 `mktemp`이 일흔 곳이다. 회차 디렉터리 하나가 그 전부를 한 자리에서 보게 한다 — 체인을 더해도
고칠 자리가 없다. 체인을 혼자 돌릴 때는 이 셈이 안 돈다. 그것은 지금의 진입 검사들과 같은 성질이다.

### 결정 5 — `joined_screen_dump`: 커널 처리와 `tars-init: ` 줄 건너뛰기는 남기고, 꼬리 떼기는 AL-M1이 지운다

`gate_lib.sh:142`의 이어 붙이기가 하는 일 넷 가운데:

| 하는 일 | AL-M1 뒤 | 정한 것 |
|---|---|---|
| 꼬리의 커널 조각(`[ 7.359211] …`)을 떼고 다음 줄을 잇는다 | 여전히 일어난다 | 남긴다 |
| 이을 차례에 오는 온전한 커널 줄을 건너뛴다 | 여전히 일어난다 | 남긴다 |
| 이을 차례에 오는 온전한 `tars-init: ` 줄을 건너뛴다 | 여전히 일어난다 — printk가 화면 줄을 자르고 뒤 조각이 오기 전에 init이 온전한 한 줄을 쓸 수 있다 | 남긴다 |
| 꼬리의 `tars-init: …` 조각을 떼고 잇는다(TC-M3 5b) | 일어날 수 없다 — terminal의 줄은 write 한 번이다 | 지운다 |

넷째를 지우는 까닭. 그 정규식은 줄 머리가 아니라 줄 가운데의 `tars-init: `를 찾으므로, 화면 글자에 `tars-init: `가 그대로 보이는 dump(사람이 패널에서
시리얼 로그를 grep한 화면)의 꼬리를 진짜 글자인데도 떼어 낸다(5b가 주석에 적은 한계). AL-M1 뒤에 그 규칙이 할 수 있는 일은 이 거짓 하나뿐이다.
남겨 두는 것이 "안전"하지도 않다 — 그 모양이 돌아오면(누가 `std.debug.print`를 다시 쓰면) 결정 3의 진입 검사가 시작 전에, 결정 4의 셈이 회차 끝에
빨갛게 말한다. 받아 주는 규칙은 그 회차의 대기 하나를 초록으로 만들 뿐 게이트는 어차피 빨갛다.

진입 검사의 고정 조각도 함께 바꾼다. `init`(꼬리에 init 조각)과 `init2`(조각 + 온전한 줄)는 더는 생길 수 없는 모양이다. 대신 "커널 조각으로 잘리고
그 뒤에 온전한 `tars-init: ` 줄이 오고 나서 뒤 조각" 하나가 같은 한 줄로 이어져야 하고, "화면 글자로 `tars-init: x`가 끝에 있는 온전한 dump"가
그대로 나와야 한다(지금은 꼬리가 떨어진다 — 이것이 지우는 까닭의 시험이다).

### 결정 6 — milestone 둘: terminal 먼저, init 다음

- AL-M0 — terminal. `terminal/src/logline.zig` · `logline_test.zig`, 98곳 치환, `dumpScreen`의 `Line`과 격자 크기 버퍼, 루트 `check.sh`의 회차
  디렉터리 · 셈(A FAIL · B 수) · 셈의 고정 조각 진입 검사 · `terminal/src`의 `std.debug.print` 0 진입 검사, 로그를 지우던 체인 여덟의 열한 자리.
- AL-M1 — init. `init/src/logline.zig`(사본) · `cmp` 진입 검사, 153곳 치환, `config.zig` `log`의 싱크와 `configLog`, 진입 검사에 `init/src`를
  더함, 셈의 B를 FAIL로, `joined_screen_dump`의 꼬리 떼기와 그 고정 조각.

terminal이 먼저인 까닭. 셈의 A가 AL-M0만으로 0이 되므로 M0의 게이트가 "terminal 쪽은 끝났다"를 따로 증명한다. 그리고 바뀌는 바이트가 많은 쪽(화면
dump가 write 수천 번에서 한 번이 된다)을 먼저 게이트에 올려야, 타이밍이 바뀌어 드러나는 경합이 있으면 init을 섞기 전에 그것만 보인다(위험 3).

init의 153곳이 PID 1이라 더 조심스러워 보이지만 바뀌는 것은 fmt가 아니라 싱크다 — 같은 `logline.zig`가 M0에서 이미 게이트를 두 번 지난 뒤에 들어간다.

### 결정 7 — 구현은 서브에이전트, 검증 · 게이트 · commit은 lead

앞선 서브프로젝트들과 같다. 이 design과 plan은 Opus가 쓰고, plan의 `old_string` · `new_string`은 사본(`/tmp/run/al0/`)에서 빌드 · 체인 · 변이로
확인한 뒤 기계로 뽑는다. 치환 251곳은 손으로 옮기지 않는다 — plan이 `sd` 명령과 그 뒤 남은 수를 세는 명령을 함께 준다.

## lead의 전제를 바로잡은 것

1. "지금 그 수가 회차마다 1 ~ 2다" — TC-M3 게이트 로그 여섯 디렉터리에서 A+B는 회차마다 2 ~ 8이었다(실측 A). 그리고 그 수도 아래로 치우쳐 있다 —
   여덟 체인이 로그를 지우므로(결정 4) 셈에 들어간 것은 체인 스물하나 가운데 열셋의 로그뿐이다. 게이트를 빨갛게 만든 것이 회차마다 1 ~ 2였다는
   뜻이라면 맞다 — 대부분의 자름은 판정이 안 보는 줄에 떨어진다.
2. "`^tars-init: ` 줄 안에 `terminal: `가 든 줄" — 그대로 세면 init이 제 글로 쓰는 `reload terminal: pid …` 줄이 끼어든 줄로 잡힌다. 여섯 디렉터리의
   B 열일곱 개 가운데 열여섯이 그것이었다. 결정 4의 B는 그 fmt를 뺀다. A 쪽(`^terminal: .*tars-init: `) 스물여덟 개는 하나하나 읽었고 전부 진짜
   끼어듦이었다.
3. "게이트 67곳이 `grep "terminal: screen>"`를 직접 읽는다" — 세는 법에 따라 다르다. 체인 열아홉 곳에 `grep … terminal: screen>` 줄이 129개,
   `terminal: screen>` 글자가 234번 나온다. 수가 무엇이든 위험 2의 결론은 같다 — 그 줄의 바이트가 안 바뀐다.
4. "init/src/main.zig 55곳 + 모듈들" — 모듈까지 153곳, terminal은 `main.zig` 90곳에 `drm.zig` · `font.zig` · `vt.zig`의 8곳을 더해 98곳이다. `kms: ` ·
   `font: ` 줄도 terminal이 같은 콘솔에 쓰므로 같이 바꾼다.
5. "화면 dump 한 줄 = 47행 × 최대 열 + 구분자" — 칸 하나가 1바이트가 아니라 많아야 4바이트다(한글 3, 이모지 4). 결정 2의 식이 그것을 센다.

## 위험

1. PID 1의 패닉. `logline.zig`가 init 안에서 패닉할 수 있는 자리는 슬라이스 경계뿐이고(결정 1), 호스트 검사가 경계값 다섯으로 덮는다. `Line.init`이
   받는 버퍼가 `CUT`보다 작으면 패닉 대신 "처음부터 넘친 줄"로 다룬다 — 런타임 크기에 `assert`를 두지 않는다. write의 에러(EBADF · EIO)는 버린다.
2. 바뀌는 바이트. `logline.print`의 출력은 2048바이트 안의 줄에서 `std.debug.print`와 바이트까지 같다(같은 fmt를 같은 `std.Io.Writer`가 짓는다).
   바뀌는 것은 2048을 넘는 줄의 꼬리뿐이다. 게이트가 내는 줄 가운데 화면 dump 밖에서 가장 긴 것은 init 247 · terminal 111바이트이고(실측 B),
   2048을 넘을 수 있는 줄은 `clip> … text=`(클립보드는 크기 제한이 없다), `dictate`의 전달 줄(`DICTATE_LINE_MAX` 512라 안 넘는다), 사람이 적은
   설정 값을 되읽는 init의 줄(`MAX_FILE` 4096)이다. 게이트가 보는 클립보드는 가장 긴 것이 77바이트(`pointer` 검사의 `len=77`)다 — 어느 체인의 판정도
   잘린 꼬리를 안 본다. 화면 dump는 결정 2의 버퍼라 안 잘리고, 머리 · 칸 · ` | ` · `\n`의 순서와 글자가 그대로다.
3. 타이밍. 화면 dump가 프레임마다 write 수천 번에서 한 번이 된다. 프레임 루프가 빨라지고 시리얼에 나가는 시점이 몰린다. 게이트의 대기들은
   "줄이 보일 때까지"라 빨라지는 쪽에는 강하지만, 느림에 기대던 숨은 경합이 있으면 드러난다. 그래서 AL-M0이 init보다 먼저이고(결정 6), AL-M0
   plan이 바꾸기 전 · 뒤의 `render> first frame`과 체인별 시간을 같은 세션에서 잰다(IS-M0의 교훈 — 기준선은 같은 세션에서).
4. 2048을 넘는 init의 줄. 결정 1의 자르기가 막는다. 막지 않으면 SIGTERM이 걸린 채 쓰던 init의 긴 줄이 둘로 갈리고, B가 드물게 빨갛다.
5. 시리얼이 꽉 찬 채 init에 시그널. n_tty의 write는 출력 버퍼에 자리가 없으면 기다리다가 처리할 시그널이 오면 그때까지 쓴 만큼 돌려준다. 2048
   안의 줄도 그때는 둘로 갈린다. init에 처리할 시그널이 오는 것은 전원을 끌 때뿐이고 QEMU의 UART는 거의 안 막힌다 — 남는 위험으로 적고 막지 않는다.
   셈(결정 4)이 그 회차를 빨갛게 하면 원인이 여기 적혀 있다.
6. `TMPDIR`이 회차마다 바뀐다. 체인이 컨테이너 쪽 `/tmp`를 글자로 가정한 곳은 없다(`TMPDIR`을 쓰는 체인 0, 체인에 나오는 `/tmp/…`는 전부 게스트 안의 경로, 유닉스 소켓 0 — QEMU monitor는 전부 TCP다).
   그래도 AL-M0 plan의 사본 실측이 체인 스물하나를 한 번씩 돌려 본다.
7. B의 목록. init의 fmt 가운데 `terminal: `을 담는 것이 늘면 B가 거짓으로 빨갛다(결정 4). 시끄러운 쪽이다.

## 비목표

1. 커널 printk의 자름. 콘솔 드라이버가 tty 잠금 밖에서 UART에 쓴다. `joined_screen_dump`가 계속 맡는다(결정 5). `quiet` · `loglevel`로 게스트의
   printk를 줄이는 것은 이 design 밖이다 — 체인 몇이 커널 줄을 판정한다.
2. 콘솔 셸 · 서비스의 표준 출력. 콘솔 셸이 줄바꿈 없는 프롬프트를 쓰면 그 뒤에 terminal의 온전한 줄이 붙어 `^terminal:`로 시작하지 않는다. TC-M3
   로그에서 회차마다 4 ~ 14줄이었다(실측 D). `pointer` 체인의 `^terminal: pointer> … $` 대기가 그 줄을 못 본다. 남의 프로세스의 write를 우리가
   묶을 수 없으므로 고칠 자리는 판정 쪽이다 — 다음에 그 대기가 빨개지면 그때 연다. 이 design의 셈은 이 줄을 세지 않는다(A · B 어느 쪽에도 안
   맞는다).
3. 로그 줄의 모양. 접두사 · fmt를 한 글자도 안 바꾼다. 바꾸면 체인 스물하나의 `grep`이 함께 흔들린다.
4. 호스트 검사의 출력, `tars-config` · `tars-service` · `tars-install`이 사람에게 쓰는 글(그 셋의 `writeAll`).
5. 로그 수준 · 로그 파일. 시리얼이 로그이고(SV 비목표 3) 이 design은 그 바이트가 섞이지 않게만 한다.

## 착수 전에 실측한 것

A. 끼어든 줄의 수. TC-M3 루트 게이트의 로그 디렉터리 여섯(`/tmp/run/tc3/gate_1` · `gate_2` · `gate3_1` · `gate3_2` · `gate4_1` · `gate4_2`). gate_2는
   빨개져 일찍 멈춘 회차라 로그가 스물이다.

| 디렉터리 | 로그 | A | B(전부) | B(`reload terminal: pid` 뺌) | A+B |
|---|---|---|---|---|---|
| gate_1 | 68 | 7 | 3 | 0 | 7 |
| gate_2 | 20 | 2 | 2 | 0 | 2 |
| gate3_1 | 64 | 4 | 2 | 0 | 4 |
| gate3_2 | 68 | 7 | 4 | 1 | 8 |
| gate4_1 | 69 | 6 | 3 | 0 | 6 |
| gate4_2 | 68 | 2 | 3 | 0 | 2 |

   진짜 B 하나는 `tars-init: login shell /usr/bin/bash, ssh env in /etc/ssh/sshd_config.d/tars-env.conf` 바로 뒤에 `terminal: screen> …`이 붙은
   줄이다 — init의 85바이트 줄이 write 여럿으로 나갔고 마지막 `\n` 앞에 terminal의 줄이 왔다. A의 끼어든 init 줄은 `audio: no sound card
   within 5000ms …`이 스물여덟 가운데 열셋으로 가장 잦다(부팅 5초째에 한 번 찍히는 줄이다). 한 회차의 로그는 46MB.

B. 가장 긴 줄(바이트, `\r` 뺌, 끼어든 줄 뺌, 여섯 디렉터리 전체).

| 머리 | 바이트 |
|---|---|
| `terminal: screen> ` | 7,172 |
| `tars-init: ` | 247 |
| `terminal: `(꼬리표 없음) | 111 |
| `terminal: cursor> ` | 106 |
| `terminal: pointer> ` | 97 |
| `terminal: image> ` | 81 |
| `terminal: style> ` | 78 |

   격자는 149번 모두 `155x47 (fb 1280x800)`. 결정 2의 식으로 29,345바이트.

C. 줄바꿈 없는 fmt. `init/src` · `terminal/src`의 시험 아닌 파일에서 `std.debug.print`의 fmt가 `\n"`으로 안 끝나는 것을 perl로 찾았다 — 다섯
   곳(결정 2).

D. 머리가 줄 처음에 없는 terminal 줄(`.terminal: [a-z]+> `가 있는데 `^terminal: ` · `^tars-init: `가 아닌 줄) — gate4_1 4, gate4_2 14, gate3_2 10.
   거의 전부 콘솔 셸(fish · bash)의 프롬프트 뒤였다(비목표 2).

E. `std.Io.Writer.fixed`(컨테이너 Zig 0.16). 10바이트 버퍼에 `"abc{s}xyz"`(`{s}` = 10바이트)를 쓰면 `error.WriteFailed`이고 `end` 10, 버퍼
   `abc0123456` — 끝까지 채우고 실패한다. `std.fmt.bufPrint`는 같은 자리에서 `error.NoSpaceLeft`이고 얼마나 썼는지를 안 돌려준다 — 그래서
   `logline.zig`는 `bufPrint`가 아니라 `Writer.fixed`다.

F. 모듈 루트 밖 파일. `b.createModule(.{ .root_source_file = b.path("../shared/x.zig") })` + `addImport`가 컨테이너 Zig 0.16에서 빌드 · 실행됐다
   (`/tmp/run/al0/exp`). 결정 1이 그래도 사본을 고른 까닭은 거기 있다.

G. 원형. `/tmp/run/al0/proto/src/logline.zig`(결정 1의 모양)와 시험 여섯(맞음 · 조각 잇기 · 정확히 맞음 · 하나 넘침 · 한글 가운데 둘 · 실제 write)이
   aarch64에서 6/6, `-target x86_64-linux-musl -OReleaseSafe`로 컴파일됐다. 첫 원형은 "버퍼가 한글 한 글자에서 정확히 끝나는" 경우에 온전한 글자까지
   떼어 냈다 — 이어짐 바이트만 보고 걷어 냈기 때문이고, 머리 바이트의 길이와 비교하도록 고친 뒤 통과했다. plan의 경계값 시험이 이 자리를 꼭 덮는다.

H. 커널. `kernel/src/linux-6.18.42/drivers/tty/tty_io.c`의 `iterate_tty_write`(952) · `tty_write_lock`(937) · `redirected_tty_write`(1105)를 읽었다
   (사슬 3 · 4). terminal · init 소스에 `sigaction`은 init의 `power.zig`(TERM · INT)와 `install.zig`(PIPE)뿐이다.

## 검증

- 호스트: `terminal/src/logline_test.zig`(경계값 · 조각 · UTF-8 · write). AL-M1은 `cmp`가 init 사본을 같은 시험 아래 둔다.
- 진입 검사(QEMU 없음): `std.debug.print` 0(M0 terminal, M1 + init) · `cmp`(M1) · 셈의 고정 조각(M0) · `joined_screen_dump`의 바뀐 고정 조각(M1).
- 사본 실측(plan마다): 체인 스물하나를 한 번씩, 그 로그의 A · B 수, 바꾸기 전 · 뒤의 `render> first frame`과 체인별 시간을 같은 세션에서.
- 변이: `dumpScreen`을 칸마다 `flush`로 되돌린 사본에서 셈이 빨개지는가(M0) — 셈이 진짜 끼어듦을 잡는지는 실제 부팅으로만 보인다. 끼어듦이
  드물면 한 번에 안 나올 수 있으므로 plan이 몇 번을 돌릴지 정한다.
- 루트 게이트 2회(lead).

## 관련

- TC-M3 plan의 Task 5b · 5c와 "닫을 때 lead가 고칠 자리" — `docs/plans/2026-10-07-tars-config-reload-tc-m3.md`
- `joined_screen_dump`의 자리와 주석 — `gate_lib.sh`
- PID 1의 패닉과 ReleaseSafe — `init/build.zig`의 GL-M1 주석
- 게이트 회차 · 2회 — `docs/decisions/feedback_gate_runs.md`
- 게이트 로그를 호스트로 꺼내는 법 — `docs/decisions/project_input_status.md`의 IS-M0 실측 1
