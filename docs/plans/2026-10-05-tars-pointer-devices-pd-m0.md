# PD-M0 — 포인터 장치를 찾아 열고, 움직임을 로그로 말한다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-pointer-devices-design.md`
Status: 끝났다(2026-10-05). 처음 판(inotify)이 루트 게이트에서 빨개져 같은 날 netlink uevent로 개정한 뒤 닫았다(확정 7 · Task R · "PD-M0이 실측한 것" 7~10).

## 누가 무엇을 하나

design 결정 11. Task 0~7은 구현 서브에이전트(Opus)가 main 작업 트리에서 직접 편집한다. Task 8(루트 게이트 ·
실측 절 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` ·
각 Task의 명령 출력을 그대로 보고한다. mutation(Task 7)도 구현자가 돌린다(PE 방식). 이 plan의 "실측한 것" 절은
구현자가 고치지 않는다.

| 파일 | 무엇을 |
|---|---|
| `terminal/src/pointer.zig` | 새 파일. `Caps` · `bitSet` · `classify` · ioctl 번호 넷 · `ueventAddedNode` · `Buttons` · `Frame` · `Mouse` · `Events` · `Pointer` |
| `terminal/src/pointer_test.zig` | 새 파일. `pub fn main` 하나, 검사 열하나(OK 줄 53) |
| `terminal/build.zig` | `pointer_test` 등록 블록(`layout_test` 뒤)과 `test` 스텝 한 줄 |
| `terminal/src/main.zig` | import · `ioctl` · `socket` 선언 · 장치 함수 여섯(`main` 앞) · uevent 소켓과 처음 훑기 · poll 배열 · 포인터 분기 · PTY 루프의 오프셋 |
| `pointer/check.sh` | 새 체인(열아홉번째), 부팅 A, 검사 1~7 |
| `check.sh` | 체인 설명 문단 하나와 `CHAINS`의 `"PD-M0:./pointer/check.sh"` |

커널(`kernel/.config`)은 한 줄도 안 바뀐다(확정 7). `docs/guides/lessons.md` · design `Status:` · `HANDOFF.md`는 이
milestone에서 안 고친다(design "닫을 때").

이 plan은 같은 날 한 번 개정했다. 처음 판은 inotify로 핫플러그를 받았고 구현까지 끝났으나 루트 게이트의 `install`
체인을 빨갛게 했다(확정 7). 개정 판의 코드는 Task 2~5에 있고(HEAD 기준), 이미 처음 판을 넣은 작업 트리를 개정
판으로 바꾸는 편집은 Task R에 따로 있다(지금 작업 트리 기준).

고치는 자리는 심볼과 `rg` 패턴으로 적는다. 줄 번호는 2026-10-05 `0c2e6f5` 기준의 참고값이다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/pdm0/impl/` 아래에 둔다.
`/tmp/run/pdm0/` 바로 아래는 이 plan을 쓰며 잰 것이고, 특히 `/tmp/run/pdm0/term/src/`는 이 plan의 코드를 그대로
넣고 돌려 본 사본이다(확정 10) — Task 4 끝에서 대조에 쓴다. 지우지 않는다.

## 이 milestone이 끝나면

- terminal이 뜨면 커널 uevent를 받는 netlink 소켓(`NETLINK_KOBJECT_UEVENT`)을 열고, 그다음 `/dev/input`을 훑는다. `event`로 시작하는 노드마다
  `O_RDONLY | O_NONBLOCK | O_CLOEXEC`로 열어 ioctl 셋(`EVIOCGBIT` · `EVIOCGPROP` · `EVIOCGNAME`)으로 성질을 묻고,
  `pointer.classify`가 `mouse`라고 한 것만 장치 칸(최대 8)에 남긴다. 나머지는 닫고 `skip` 줄을 찍는다.
- 부팅 뒤에 꽂힌 마우스는 커널의 `add` uevent(`SUBSYSTEM=input` · `DEVNAME=input/eventN`)가 같은 함수로 보낸다. 뽑힌 마우스는 그 fd의 `POLLERR` · `POLLHUP`(또는
  read의 `ENODEV`)로 알고 닫는다.
- 포인터 이벤트가 있던 poll 회차마다 `terminal: pointer> at x=… y=… buttons=… wheel=… shown=0 ink=0` 한 줄이
  찍힌다. 좌표는 프레임버퍼 가운데에서 출발해 `0..w-1` · `0..h-1` 안에 머문다. 버튼은 장치별로 들고 합친다.
- 화면은 한 픽셀도 안 바뀐다. 포인터 이벤트는 `needs_redraw`를 안 켠다. `shown`과 `ink`는 상수 0이다.
- 키보드 경로(init의 `resolveKeyboard`와 `argv[4]`, `input.openDevice`)는 그대로다.
- 게스트 커널은 그대로다. netlink uevent는 `CONFIG_NET=y`만 있으면 되고 이미 켜져 있다.
- 호스트 검사가 여덟이 된다(`pointer_test`). 체인이 열아홉이 된다(`pointer/check.sh`, 부팅 하나, 검사 일곱).

로그 줄(정본 — `main.zig`와 `pointer/check.sh`가 이 글자를 쓴다, 확정 8):

```
terminal: pointer> open /dev/input/event2 kind=mouse shown=0 name=QEMU QEMU USB Mouse
terminal: pointer> skip /dev/input/event1 kind=none name=AT Translated Set 2 keyboard
terminal: pointer> skip /dev/input/event9 full name=…
terminal: pointer> skip /dev/input/event9 error=NOENT
terminal: pointer> skip /dev/input/event9 error=ioctl
terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> close /dev/input/event3
terminal: pointer> uevent failed error=AFNOSUPPORT
terminal: pointer> scan failed error=FileNotFound
```

마지막 둘은 실패할 때만 찍힌다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 쟀다. QEMU 10.0.13 · 커널 6.18.42 · `0c2e6f5`의 bzImage와 initrd다. 측정 스크립트는
lead의 `/tmp/run/mp0/probe.sh`를 고친 `/tmp/run/pdm0/m12.sh`(핫플러그 · 큰 이동) · `m3.sh`(시간) · `caps.sh`(비트맵)이고,
render 체인의 QEMU 호출에 `-usb -device usb-mouse`를 더해 띄웠다. 시리얼 로그는 `/tmp/run/pdm0/m12/serial.log` ·
`m3/*.log`다.

1. 핫플러그는 HMP로 된다. `-display none`에서 `device_add usb-mouse,id=m2`를 보내면 약 0.9초 뒤에 커널이 이렇게
   찍는다.

   ```
   usb 1-2: new full-speed USB device number 3 using uhci_hcd
   usb 1-2.1: new full-speed USB device number 4 using uhci_hcd
   input: QEMU QEMU USB Mouse as /devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4
   hid-generic 0003:0627:0001.0002: input: USB HID v0.01 Mouse [QEMU QEMU USB Mouse] on usb-0000:00:01.2-2.1/input0
   ```

   QEMU가 포트 2에 허브(`QEMU USB Hub`)를 저절로 붙이고 그 아래 2.1에 마우스를 단다(`info usb`). 노드는
   `/dev/input/event3`이다. `device_del m2` 뒤에는 커널이 `usb 1-2.1: USB disconnect, device number 4` 한 줄만 찍고
   `input:` 줄은 없다. `ls /dev/input`에서 `event3`이 사라진다. 게스트에서 `cat /dev/input/event3 > /dev/null &`를
   띄워 두고 뽑으면 `cat: /dev/input/event3: No such device`로 cat이 끝났다 — 열려 있는 fd의 read가 `ENODEV`를
   돌려준다. 다시 꽂으면(`id=m3`) 커널은 `input5`를 만들지만 노드는 다시 `event3`이다 — 번호가 재사용된다.

   `info mice`의 별표(HMP `mouse_move`가 가는 장치)는 이렇게 움직였다. design 위험 8이 걱정한 것과 달리 뽑은
   뒤에 원래 마우스로 돌아온다. 게스트에서 `head -c 72`로 노드를 읽어 실제로 어느 노드에 이벤트가 오는지도 봤다.

   | 순간 | `info mice` | `mouse_move 10 5`가 온 노드 |
   |---|---|---|
   | 부팅 | `* Mouse #3: QEMU HID Mouse` | event2 |
   | `device_add` 뒤 | `* Mouse #4: QEMU HID Mouse`(#3은 별표 없음) | event3 |
   | `device_del` 뒤 | `* Mouse #3: QEMU HID Mouse` | event2 |

   그래서 검사 6을 부팅 A의 맨 끝으로 옮길 필요가 없다. 검사 6은 이 사실을 판정에 쓴다 — 꽂은 뒤의 움직임은
   새 fd로만 오고, 뽑은 뒤의 움직임은 원래 fd로만 온다.

2. 127을 넘는 이동은 쪼개진다. `mouse_move 300 0` · `mouse_move -300 0`을 보낸 동안 게스트의
   `cat /dev/input/event2 > /tmp/ev.bin`이 288바이트(이벤트 12개)를 받았다. `cat -v`로 풀면 REL_X가 127 · 127 · 46,
   그다음 -127 · -127 · -46이고 각각 뒤에 `SYN_REPORT`가 있다. 잘리지 않고 보고 셋으로 나뉜다(합이 보존된다).
   게이트는 그래도 한 번에 100 이하로 민다 — 명령 하나가 보고 하나라서 `at` 줄을 읽기 쉽다. `pointer_test` 검사
   7이 이 세 보고를 그대로 먹인다.

3. `-usb -device usb-mouse`는 부팅을 늦추지 않는다. render 체인의 QEMU 호출로 마우스 없이 · 있게를 번갈아 두
   번씩 띄워 QEMU 시작부터 첫 `terminal: screen>`까지를 쟀다.

   | 부팅 | 첫 `screen>` |
   |---|---|
   | 마우스 없음 1 · 2 | 4.5초 · 4.3초 |
   | 마우스 있음 1 · 2 | 4.5초 · 4.5초 |

   첫 프레임의 덤프 줄(`grid` · `opened` · `status>` · `pane>` · `cursor>`)은 두 부팅이 글자까지 같았다.
   `pane>` 줄은 `terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 sep ink=0`이다 — 검사 7이 이 글자를 본다.
   덤으로 순서 하나. 마우스의 `input: QEMU QEMU USB Mouse as …` 줄(커널 시각 1.10초)이 `tars-init: started
   terminal` 줄보다 35줄 앞이다. 부팅 때의 마우스는 terminal의 처음 훑기가 잡고, uevent는 검사 6의 핫플러그에서만 쓰인다.
   그래서 mutation 2(uevent를 안 읽는다)는 검사 1이 아니라 검사 6에서 잡힌다.

4. 번역과 API. `terminal/build.zig`의 `c_input` 번역 둘(게스트 x86_64 · 호스트 aarch64)에 다음이 전부 넘어온다.
   사본 트리(`/tmp/run/pdm0/term`)에 probe 실행 파일 둘을 등록해 `comptime` 참조로 컴파일했다.

   - 상수: `EV_SYN 0` · `EV_KEY 1` · `EV_REL 2` · `EV_ABS 3` · `EV_MSC 4` · `SYN_REPORT 0` · `SYN_DROPPED 3` · `REL_X 0` ·
     `REL_Y 1` · `REL_HWHEEL 6` · `REL_WHEEL 8` · `REL_WHEEL_HI_RES 11` · `BTN_LEFT 0x110` · `BTN_RIGHT 0x111` ·
     `BTN_MIDDLE 0x112` · `BTN_TOOL_FINGER 0x145` · `INPUT_PROP_POINTER 0` · `INPUT_PROP_DIRECT 1` · `INPUT_PROP_BUTTONPAD 2` ·
     `ABS_X 0` · `ABS_MT_POSITION_X 0x35` · `ABS_MT_POSITION_Y 0x36` · `EV_MAX 0x1f` · `KEY_MAX 0x2ff` · `REL_MAX 0xf` ·
     `ABS_MAX 0x3f` · `INPUT_PROP_MAX 0x1f`.
   - 구조체: `struct_input_absinfo` 24바이트, `struct_input_event` 24바이트.
   - ioctl 매크로가 함수로 넘어온다. design 실측 15(HD 조사 6)는 "`EVIOCGBIT`이 매크로라 translate-c로 안
     넘어온다"였는데, 그것은 `@cImport` 시절의 사실이다. ZU-M1이 옮긴 translate-c 패키지는 `_IOC` 계열을
     `pub inline fn EVIOCGBIT(ev: anytype, len: anytype) …`로 번역한다. 두 번역 모두에서 불러 값을 찍었고,
     컨테이너의 `/usr/include/linux/input.h`를 gcc로 컴파일해 찍은 값과 같았다. design이 적은 비트 배치
     (`nr 8 · type 8 · size 14 · dir 2`, `_IOC_READ = 2`)로 손으로 셈한 값과도 같다.

     | 요청 | 값 |
     |---|---|
     | `EVIOCGBIT(0, 4)` | `0x80044520` |
     | `EVIOCGBIT(EV_KEY, 96)` | `0x80604521` |
     | `EVIOCGBIT(EV_REL, 2)` | `0x80024522` |
     | `EVIOCGBIT(EV_ABS, 8)` | `0x80084523` |
     | `EVIOCGPROP(4)` | `0x80044509` |
     | `EVIOCGNAME(64)` | `0x80404506` |
     | `EVIOCGABS(ABS_MT_POSITION_X)` | `0x80184575` |

     그래서 이 plan은 번호를 손으로 짓지 않고 번역된 매크로를 부른다(`pointer.eviocgbit` 등). 반환 타입이
     매크로마다 다르므로(`EVIOCGBIT`는 `c_uint`, `EVIOCGABS`는 `usize`) `@intCast`로 `c_ulong`에 맞추고, 인자는
     `comptime`으로 받는다 — `anytype` 시프트에 runtime 값을 섞으면 타입이 갈린다. `pointer_test` 검사 5가 위
     표의 값을 그대로 대조한다. 번역 패키지를 0.17 판으로 바꿀 때 이 대조가 첫 경보다.
   - netlink는 번역을 더하지 않는다. Zig 0.16 std가 갖고 있다 — `std.os.linux.AF.NETLINK`(16) ·
     `std.os.linux.SOCK.DGRAM` · `SOCK.NONBLOCK` · `SOCK.CLOEXEC` · `std.os.linux.NETLINK.KOBJECT_UEVENT`(15) ·
     `std.os.linux.sockaddr.nl`(`family` 기본값이 `AF.NETLINK`, `pid` · `groups`) · `std.c.bind`. `socket`은
     `std.c` 안에 있지만 공개가 아니라서 `main.zig`가 `extern "c" fn socket(domain: c_uint, sock_type: c_uint,
     protocol: c_uint) c_int;`를 선언한다. 받는 것은 `recv` 대신 이미 쓰는 `std.c.read`다 — datagram 하나가 read
     하나다. 사본에서 `zig build`(게스트)와 `zig build test`(호스트)로 컴파일을 확인했다(확정 10).
     `open` · `read` · `close` · `errno`도 `std.c`의 것을 쓴다(`std.c.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK =
     true, .CLOEXEC = true })`가 `0o2004000`이다). `ioctl`도 `std.c`에서 공개가 아니라서 `main.zig`가
     `extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;`를 선언한다(`c_drm` 번역의 것과 같은 시그니처).
     처음 판이 쓴 inotify(`std.c.inotify_init1` · `std.os.linux.IN` · `inotify_event`)도 std에 다 있었다 — 막힌 것은
     std가 아니라 커널이었다(확정 7).
     디렉터리 훑기는 `std.Io.Dir.openDirAbsolute(io, "/dev/input", .{ .iterate = true })` · `dir.iterate()` ·
     `it.next(io)`다.

5. 포트와 진입 검사. 체인들이 쓰는 번호는 45455~45487이고(`rg -o '45[0-9]{3}'`로 모든 `*.sh`를 훑었다), 45488 ·
   45489는 비어 있다. 새 체인은 45488(부팅 A)이다. 45489는 PD-M3의 부팅 B 몫이다. 이 plan의 `pointer/check.sh`를
   lessons의 명령(Task 5-3)으로 진입 검사 셋에 대 봤고 `ENTRY-OK`였다. `bash -n`도 통과했다.

6. 분류 표의 실측 데이터. `-usb -device usb-mouse -device usb-tablet`으로 뜬 게스트에서
   `grep -E (string join '|' N: H: B:) /proc/bus/input/devices`를 쳐 화면으로 받았다. `pointer_test` 검사 3이 이 글자를
   그대로 쓴다.

   | 장치 | 노드 | `PROP` | `EV` | `KEY` | `REL` | `ABS` |
   |---|---|---|---|---|---|---|
   | Power Button | event0 | 0 | 3 | `8000 10000000000000 0` | — | — |
   | AT Translated Set 2 keyboard | event1 | 0 | 120013 | `402000007 ff803078f800d001 feffffdfffcfffff fffffffffffffffe` | — | — |
   | QEMU QEMU USB Mouse | event2 | 0 | 17 | `1f0000 0 0 0 0` | 903 | — |
   | QEMU QEMU USB Tablet | event3 | 0 | 1f | `70000 0 0 0 0` | 900 | 3 |

   USB 마우스의 버튼은 다섯이다(`0x110`~`0x114`, LEFT · RIGHT · MIDDLE · SIDE · EXTRA). 디코더는 앞의 셋만 든다.
   이 형식은 "높은 워드가 앞"이고 ioctl은 "낮은 바이트가 앞"이라서, `pointer_test`의 `fromSysfs`가 둘 사이를
   한 자리에서 바꾼다(design 결정 2). 터치패드 · 터치스크린 · TrackPoint는 게스트에 없으므로 흔한 값을 적었고
   검사 4에 "실측 아님"이라 적어 둔다.

7. 핫플러그 알림은 커널 uevent(netlink)로 받는다. inotify는 커널 한 줄을 요구했고, 그 한 줄이 `install` 체인을
   빨갛게 했다. design 결정 1의 inotify 전제가 뒤집힌 과정이 이렇다.

   처음 판은 design 결정 1대로 inotify를 썼다. 그 코드를 처음 돌렸을 때 terminal이 `terminal: pointer> watch failed
   error=NOSYS`를 찍었다 — `kernel/.config` 3029줄이 `# CONFIG_INOTIFY_USER is not set`이다(`DNOTIFY` · `FANOTIFY`도
   꺼져 있다). 그래서 처음 판은 그 한 줄을 켜는 Task 1을 두었다. `olddefconfig`가 `CONFIG_FSNOTIFY=y`를 select로
   따라 켰고 bzImage가 12,288바이트 커졌으며, 그 커널로 `pointer` 체인은 PASS였다.

   lead가 그 구현으로 루트 게이트를 두 번 돌렸고, 둘 다 열세번째 `install` 체인의 부팅 7(`usb-storage.delay_use=3`)이
   `init did not have to wait for the late USB disk`로 빨갰다. 단독 재현도 결정적이었다. 보존한 부팅 7 로그의 커널
   시각이 원인을 말한다("PD-M0이 실측한 것" 7 · 8, lead가 쟀다).

   | 커널 | `Unpacking initramfs` → `Run /init` | 디스크 `sda` | 결과 |
   |---|---|---|---|
   | HEAD(inotify 꺼짐) | 0.46초 → 3.07초(2.6초) | 4.24초 | `config storage appeared after 1100ms`, PASS |
   | 처음 판(`INOTIFY_USER=y` · `FSNOTIFY=y`) | 0.45초 → 4.25초(3.8초) | 4.21초 | init이 디스크보다 늦게 도착, FAIL |

   `FSNOTIFY`가 initramfs 풀기를 TCG에서 1.2초 늦춘다. 부팅 7은 init이 디스크보다 먼저 도착해 기다리는 것을 보는
   체인이라, 그 1.2초가 기다림의 창(HEAD에서 약 1.1초)을 닫는다. 이 체인에는 PD-M0 코드가 닿는 자리가 없다 — 커널 한
   줄이 전부였다. 이 사실은 lessons에 남길 가치가 있다(lead가 닫을 때 옮긴다): 커널 config 한 줄이 무관한 체인의 타이밍
   창을 닫을 수 있고, `install` 부팅 7은 initramfs 풀기 시간에 민감하다.

   lead의 결정(2026-10-05): 커널은 PD-M0에서 한 줄도 안 바꾼다(design의 원래 뜻). 핫플러그 알림은 udev가 듣는 통로인
   `NETLINK_KOBJECT_UEVENT` 소켓으로 받는다. `CONFIG_NET=y`면 되고 이미 켜져 있다. 그 결정에 따라 개정하며 사본에
   uevent 원문을 찍는 디버그 판을 넣어 `pointer` 체인을 돌렸다(`/tmp/run/pdm0/v2/dbg3.log`). `device_add` 뒤 terminal이
   받은 첫 uevent가 이것이었다(NUL을 `|`로 바꿔 적는다).

   ```
   add@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3|ACTION=add|
   DEVPATH=/devices/…/input/input4/event3|SUBSYSTEM=input|MAJOR=13|MINOR=67|DEVNAME=input/event3|SEQNUM=686|
   ```

   그 uevent를 받은 순간 `access("/dev/input/event3")`가 참이었다(`exists=true`). devtmpfs가 `device_add` 안에서 노드를
   만든 뒤에 uevent를 보내므로 `open`이 `ENOENT` 없이 된다. 이어서 `bind`(SUBSYSTEM=hid · usb 인터페이스 · usb
   장치 — 마지막 것은 `DEVNAME=bus/usb/001/004`)가 왔고, `device_del`에는 `remove`(event3 · 노드 없는 input4)와
   `unbind` · `remove`(hid · usb)가 왔다. 메시지는 235~479바이트였고 read마다 하나였으며, 회차는 `EAGAIN`으로 끝났다.
   `ENOBUFS`는 안 났다. `device_add` 앞쪽의 uevent(usb 장치 · 인터페이스 · hid의 `add`)는 그 디버그 회차가 실패
   경로에서 `pointer>` 줄을 마지막 서른 줄만 찍어 못 봤다 — 고르는 조건(`ACTION=add` · `SUBSYSTEM=input` ·
   `DEVNAME=input/event`)이 셋 다 맞는 것은 위의 하나뿐이다. `pointer_test` 검사 11이 이 글자를 그대로 쓴다.

   그 디버그 회차는 끝의 NUL 음성 검사에서 빨갰다 — uevent 원문을 줄마다 수백 바이트씩 시리얼로 쏟은 회차뿐이었다.
   디버그 줄 없는 최종 코드로 두 번 돌린 체인은 둘 다 그 검사까지 초록이었다(확정 10).

   `kernel/.config`의 되접기 drift(PD와 무관하게 `build/.config`와 아홉 줄 — 머리 주석 둘과 UW 때 켠 USB 무선 심볼이
   select로 끌어온 `MT76_USB` · `MT792x_USB` · `RTW88_USB` · `RTW88_88XXA` · `RTW88_8821A` · `RTW88_8812A` ·
   `RTW88_8814A` · `RTW89_USB`)는 그대로 남아 있다. PD-M0은 커널을 안 건드리므로 이 milestone의 일이 아니다(Task 8-5).

8. 로그 줄의 모양. design 결정 10의 예시에서 둘을 바꿨다.
   - `name=`을 언제나 줄 맨 끝에 둔다. design은 `open … kind=mouse name=QEMU QEMU USB Mouse shown=0`이었다. 이름에
     공백이 있어서 뒤에 필드가 오면 어디까지가 이름인지를 정규식이 짐작해야 한다. 맨 끝이면 `name=(.*)$` 하나다.
   - `skip` 줄에도 `name=`을 단다. 검사 1이 "키보드와 전원 버튼이 건너뛰어졌다"를 경로가 아니라 이름으로 본다 —
     event 번호는 기계마다 다르다(design 실측 14가 적은 대로 체인은 번호를 판정에 안 쓴다).
   - 실패 줄 넷(`skip … full` · `skip … error=…` · `uevent failed` · `scan failed`)을 더했다. 정상 부팅에는 안 나온다.
     처음 판의 같은 자리(`watch failed`) 덕분에 확정 7의 `NOSYS`가 한 번에 보였다.

9. poll 배열. 지금은 `fds[0]`이 키보드, `fds[1..nfds]`가 PTY이고 `fd_panes[nfds - 1]`로 패널을 찾는다(`main.zig`
   1676 · 1682 · 1953줄). 이 plan은 `[0]` 키보드 · `[1]` uevent 소켓 · `[2..pty_base]` 열린 포인터 장치 ·
   `[pty_base..nfds]` PTY로 바꾼다. 장치 칸 수가 바퀴마다 다르므로 PTY의 시작 자리를 상수가 아니라 그 바퀴에 지은
   `pty_base`로 든다. 바뀌는 자리는 셋이다 — `fd_panes[nfds - 1]` → `fd_panes[nfds - pty_base]`, PTY 루프의
   `fds[1..nfds], fd_panes[0 .. nfds - 1]` → `fds[pty_base..nfds], fd_panes[0 .. nfds - pty_base]`, 배열 크기
   `1 + 9 × 8` → `2 + 8 + 9 × 8`. 소켓이 실패하면 `fds[1].fd`가 -1이고 poll은 음수 fd를 건너뛴다(revents 0) —
   자리를 비워 두지 않으므로 오프셋 산수가 한 벌이다. 포인터 분기는 키보드 분기 뒤 · PTY 분기 앞이다(design
   결정 3). 그 안에서 빠진 장치를 먼저 닫고 uevent를 나중에 읽는다 — 확정 1대로 번호가 재사용되므로, 반대
   순서면 같은 회차에 빠지고 다시 꽂힌 장치를 "이미 열었다"로 건너뛸 수 있다.

10. 이 plan의 코드는 돌려 봤다. Task 2~5의 코드를 사본 `/tmp/run/pdm0/term/`(저장소의 `terminal/`을 캐시만 빼고
    복사한 것)과 `/tmp/run/pdm0/pointer/check.sh`에 넣고, 사본을 `-v`로 `terminal/src` 자리에 덮어 컨테이너에서
    돌렸다. 처음 판(inotify)은 확정 7대로 돌렸고, 그 처음 판의 사본은 `/tmp/run/pdm0/v1/`에 남겨 두었다 — 지금
    작업 트리의 구현과 글자까지 같다(Task R-0이 대조한다).

    개정 판(uevent)을 돌린 결과. 커널은 HEAD config 그대로이고(`CONFIG_INOTIFY_USER` 0줄), 체인마다 같은 `docker run`
    안에서 캐시를 지웠다.

    | 무엇 | 결과 |
    |---|---|
    | `zig build` · `zig build test` | `exit=0` 둘, `pointer_test` OK 53(검사 11의 여섯이 더해졌다) |
    | `pointer` 체인 두 번 | 둘 다 `PD-M0 check PASS`, 87초 · 86초. 검사 줄은 Task 6-1의 기대와 같다 |
    | mutation 2(uevent를 안 읽는다) | 검사 6에서 `FAIL: the kernel registered a second mouse but terminal never opened it`, 99초 |
    | `install` 체인 한 번 | PASS, 165초. 부팅 7이 `init waited 900ms for the late USB disk and mounted its p2` |

    mutation 1 · 3 · 4는 개정에서 다시 돌리지 않았다. 셋이 심는 자리(`classify` · 닫는 조건 · `REL_Y`)의 글자가
    개정에서 안 바뀌었고, 처음 판에서 셋 다 기대한 검사에서 빨갰다("PD-M0이 실측한 것" 5). 바뀐 것은 그 줄의 번호뿐이다
    (Task 7-0).

    plan의 코드 블록은 기계적으로 대조했다. Task 2 · 3-1 · 5-1의 블록을 뽑은 것과, Task 3-2 · 4 · 5-2의 "바꾸기 전 /
    바꾼 뒤" 쌍을 HEAD 파일에 적용한 것이 사본과 글자까지 같았다. Task R의 쌍을 지금 작업 트리에 적용한 것도 사본과
    같았다. HEAD와 개정 판의 차이는 `main.zig` +268/−10 · `build.zig` +17/−0 · `check.sh` +6/−0이고 새 파일이 셋
    (`pointer.zig` 271줄 · `pointer_test.zig` 305줄 · `pointer/check.sh` 388줄)이다.

11. mutation을 넣는 법. PE-M1 확정 9와 같다. 저장소 파일은 안 고치고, 사본을 `-v`로 그 파일 자리에 덮는다. 같은
    `docker run` 안에서 먼저 `terminal/.zig-cache`와 `terminal/zig-out`을 지운다(lessons "캐시는 컨테이너 안에서
    지운다", `project_zig_out_staleness`). 덮인 사본이 실제로 쓰였는지는 같은 `docker run` 안에서 `grep -c`로
    mutation 글자를 센다. `pointer.zig`를 바꾸는 mutation 1 · 4는 체인이 부팅 전에 돌리는 `zig build test`가 먼저
    잡으므로, 체인의 판정은 그 한 단계만 끈 사본 체인으로 따로 본다. 조건은 runtime 값(`uevent_fd` · `pfd.fd`)을 섞어
    쓴다 — `if (false)`처럼 comptime에 정해지는 조건은 뒤의 줄을 도달 불가로 만들어 컴파일 에러가 날 수 있다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다. Task 6 · 7이 docker로 체인을 돌리므로 겹치면 monitor 포트와 `kernel/build`가
   부딪친다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리가 깨끗한지 본다.

   ```bash
   git status --short
   git log --oneline -1
   ```

   기대: `git status`는 이 plan 파일(`??` 또는 이미 commit됐으면 0줄)뿐, 마지막 commit은 `0c2e6f5` 또는 그 뒤의
   것이다.

3. 고칠 자리가 그대로인지 본다.

   ```bash
   rg -n '^const layout = |^extern "c" fn setenv|^pub fn main|var pty_buf: \[4096\]u8|var fds: \[|fds\[i \+ 1\]|var nfds: usize = 1|fd_panes\[nfds - 1\]|for \(fds\[1\.\.nfds\]|// PTY master는 slave가' terminal/src/main.zig
   rg -n 'CONFIG_INOTIFY_USER' kernel/.config
   rg -n 'b.installArtifact\(layout_test\)|addRunArtifact\(layout_test\)' terminal/build.zig
   rg -n '"WP-M2:./pane/check.sh"|^# 이름과 경로를 한 곳에 모은다' check.sh
   ls terminal/src/pointer.zig terminal/src/pointer_test.zig pointer 2>&1 | tail -3
   ```

   기대(줄 번호는 참고):

   ```
   7:const layout = @import("layout.zig");
   20:extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
   1418:pub fn main(init: std.process.Init) !void {
   1654:    var pty_buf: [4096]u8 = undefined;
   1663:    var fds: [1 + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
   1664:    // `fds[i + 1]`이 어느 패널의 것인지. 패널은 `workspaces` 배열 안에
   1676:        var nfds: usize = 1;
   1682:                fd_panes[nfds - 1] = .{ .pane = pane, .ws = wi, .leaf = @intCast(leaf) };
   1945:        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
   1953:        for (fds[1..nfds], fd_panes[0 .. nfds - 1]) |pfd, ref| {
   3029:# CONFIG_INOTIFY_USER is not set
   283:    b.installArtifact(layout_test);
   299:    test_step.dependOn(&b.addRunArtifact(layout_test).step);
   312:# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
   332:  "WP-M2:./pane/check.sh"
   ```

   마지막 `ls`는 셋 다 없다고 해야 한다(`No such file or directory` — 이 기계의 `ls`는 eza라 모양이
   `"terminal/src/pointer.zig": No such file or directory (os error 2)`이다).

4. 호스트 검사를 한 번 초록으로 본다.

   ```bash
   mkdir -p /tmp/run/pdm0/impl
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
     bash -c 'zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -a -c "^PASS" /tmp/t.out; grep -a -E "all checks passed|FAIL" /tmp/t.out'
   ```

   기대: `exit=0`, `5`, 그리고 `layout_test: all checks passed` · `status_test: all checks passed` 두 줄. `FAIL`은
   0줄.

## Task 1: 커널은 그대로다(개정에서 비웠다)

처음 판의 Task 1은 `kernel/.config`에 `CONFIG_INOTIFY_USER=y`를 켰다. 개정 판은 커널을 한 줄도 안 바꾼다(확정 7).
할 일은 확인 하나다. 번호는 뒤 Task의 참조를 지키려고 남긴다.

```bash
rg -n 'CONFIG_INOTIFY_USER' kernel/.config
git diff --stat kernel/.config
```

기대: `3029:# CONFIG_INOTIFY_USER is not set`, 둘째 명령은 0줄.

## Task 2: `terminal/src/pointer.zig` — 새 파일

Write 도구로 아래 내용 그대로 만든다. 순수 모듈이다 — 시스템 콜도 `vt.zig` · `layout.zig` import도 없다(design
결정 3). `c_input`은 `input.zig`와 같은 번역이고 `build.zig`가 이미 `exe_mod`에 넣고 있으므로 게스트 빌드에는
고칠 것이 없다.

읽을 자리 셋. `classify`의 순서(DIRECT → 터치패드 → 마우스), `Mouse.feed`가 `SYN_REPORT`에서만 `Frame`을 내고
`SYN_DROPPED` 뒤 다음 `SYN_REPORT`까지 버리는 것, `Pointer.merge`가 장치별 버튼의 합이 바뀔 때만 눌림 · 뗌을 내는
것. `forget`은 design에 없던 것이다 — 버튼을 누른 채 뽑힌 장치의 버튼이 영영 눌린 채로 남지 않게 한다.

```zig
//! 포인터 장치(마우스 · 터치패드)의 순수한 층(PD design 결정 2 · 3).
//!
//! 시스템 콜이 없다. `vt.zig` · `layout.zig`도 import하지 않는다. 장치를 찾고
//! 열고 읽는 것은 `main.zig`이고, 이 파일은 그 바이트를 받아 판단만 한다 —
//! 그래서 `pointer_test`가 부팅 없이 같은 판단을 본다.
//!
//! 층은 셋이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼).
//! 누름 · 끎 · 뗌을 의도로 바꾸는 `Gesture`는 PD-M2가 여기에 더한다.
const std = @import("std");

/// `input.zig`의 `c`와 같은 번역(`linux/input.h`)이다. `pub`인 이유도 같다 —
/// `pointer_test`가 커널이 정한 이름(`c.BTN_LEFT`)으로 검사를 쓴다.
pub const c = @import("c_input");

/// 장치 칸의 수(PD design "모델" 절). `Pointer`가 장치별 버튼을 이 수만큼 든다.
pub const MAX_DEVICES = 8;

/// 비트 번호 `max`까지 담는 바이트 수.
fn bytesFor(comptime max: usize) usize {
    return max / 8 + 1;
}

/// 장치의 성질. 연 fd에 ioctl로 묻는 비트맵 다섯이다(PD design 결정 1).
///
/// 크기는 커널의 `*_MAX`에서 나온다 — EV 4 · KEY 96 · REL 2 · ABS 8 · PROP 4
/// 바이트. ioctl에 이 길이를 그대로 넘기므로 커널이 그보다 많이 쓰지 않는다.
pub const Caps = struct {
    ev: [bytesFor(c.EV_MAX)]u8 = @splat(0),
    key: [bytesFor(c.KEY_MAX)]u8 = @splat(0),
    rel: [bytesFor(c.REL_MAX)]u8 = @splat(0),
    abs: [bytesFor(c.ABS_MAX)]u8 = @splat(0),
    prop: [bytesFor(c.INPUT_PROP_MAX)]u8 = @splat(0),
};

/// 비트 `n`이 서 있는가.
///
/// ioctl이 채운 비트맵은 낮은 번호부터다 — 비트 n은 바이트 n/8의 비트 n%8이다.
/// 커널이 `unsigned long` 배열을 그대로 복사하고 x86_64 · aarch64가
/// little-endian이라 그렇다. sysfs의 "높은 워드가 앞" 문자열(init의
/// `devices.zig`)과 순서가 반대라서 그쪽 함수를 옮겨 오지 않는다(design 결정 2).
/// 범위 밖은 거짓이다.
pub fn bitSet(map: []const u8, n: usize) bool {
    if (n / 8 >= map.len) return false;
    return map[n / 8] & (@as(u8, 1) << @intCast(n % 8)) != 0;
}

pub const Kind = enum { mouse, touchpad, none };

/// 이 장치를 포인터로 열 것인가(PD design 결정 2). 이름이 아니라 capability로
/// 가른다(HD 결정 2와 같다).
///
/// 순서에 뜻이 있다. `INPUT_PROP_DIRECT`(터치스크린)는 다른 조건과 상관없이
/// `none`이다. 터치패드를 마우스보다 먼저 본다 — 마우스 모드 노드를 함께 내는
/// 터치패드가 있어서다. usb-tablet은 `ABS_X` · `ABS_Y`가 있어도
/// `INPUT_PROP_POINTER`와 `BTN_TOOL_FINGER`가 없어 `none`이다(design 실측 3).
pub fn classify(caps: *const Caps) Kind {
    if (bitSet(&caps.prop, c.INPUT_PROP_DIRECT)) return .none;
    const has_key = bitSet(&caps.ev, c.EV_KEY);
    if (bitSet(&caps.ev, c.EV_ABS)) {
        const mt = bitSet(&caps.abs, c.ABS_MT_POSITION_X) and bitSet(&caps.abs, c.ABS_MT_POSITION_Y);
        const st = bitSet(&caps.abs, c.ABS_X) and bitSet(&caps.abs, c.ABS_Y);
        const pad = bitSet(&caps.prop, c.INPUT_PROP_POINTER) or
            (has_key and bitSet(&caps.key, c.BTN_TOOL_FINGER));
        if ((mt or st) and pad) return .touchpad;
    }
    if (bitSet(&caps.ev, c.EV_REL) and bitSet(&caps.rel, c.REL_X) and bitSet(&caps.rel, c.REL_Y) and
        has_key and bitSet(&caps.key, c.BTN_LEFT)) return .mouse;
    return .none;
}

/// ioctl 요청 번호 넷(PD design 결정 1). 번역이 `linux/input.h`의 매크로를
/// 함수로 넘겨주므로 그것을 그대로 부른다 — 커널 헤더가 정한 값이 한 벌이다
/// (PD-M0 plan 확정 4). design은 `drm.zig`의 `drmIowr`처럼 손으로 짓기로
/// 했는데, 그것은 `@cImport` 시절 HD 조사 6의 사실이었다.
///
/// 인자가 `comptime`인 이유. 번역된 매크로는 `anytype`이라 runtime 값을 섞으면
/// 시프트의 타입이 갈린다. 부르는 자리는 전부 `Caps`의 배열 길이라 컴파일
/// 때 정해진다. 값은 `pointer_test`가 C 헤더로 잰 수와 대조한다.
pub fn eviocgbit(comptime ev: u16, comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGBIT(ev, len));
}

pub fn eviocgprop(comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGPROP(len));
}

pub fn eviocgname(comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGNAME(len));
}

/// 터치패드의 축 범위를 읽는다. PD-M0은 부르지 않는다 — PD-M3의 터치패드
/// 디코더가 쓴다. 번호만 여기 두고 `pointer_test`가 본다.
pub fn eviocgabs(comptime abs: u16) c_ulong {
    return @intCast(c.EVIOCGABS(abs));
}

/// 커널 uevent 하나에서 새로 생긴 evdev 노드의 이름(`event3`)을 꺼낸다.
/// 아니면 null이다.
///
/// uevent는 NUL로 나뉜 필드들이다 — 머리 `add@/devices/…/event3` 뒤에
/// `ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/event3` 같은 `KEY=value`가
/// 온다(PD-M0 plan 확정 7에서 본 글자). 셋이 다 맞는 것만 고른다. 같은 장치가
/// `input/inputN`(노드 없음) · `hidraw` · `usb` uevent도 함께 내고, `mouseN`은
/// `INPUT_MOUSEDEV`가 꺼져 있어 안 온다. 머리는 `=`가 없어 어느 조건에도 안
/// 걸린다.
///
/// 돌려주는 조각은 `msg` 안을 가리킨다. 부르는 쪽이 경로로 복사한다.
pub fn ueventAddedNode(msg: []const u8) ?[]const u8 {
    var added = false;
    var input = false;
    var node: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, msg, 0);
    while (it.next()) |field| {
        if (std.mem.eql(u8, field, "ACTION=add")) {
            added = true;
        } else if (std.mem.eql(u8, field, "SUBSYSTEM=input")) {
            input = true;
        } else if (std.mem.startsWith(u8, field, "DEVNAME=input/event")) {
            node = field["DEVNAME=input/".len..];
        }
    }
    if (!added or !input) return null;
    return node;
}

/// 버튼 셋. 비트 순서가 QEMU HMP `mouse_button`의 비트(1 왼쪽 · 2 오른쪽 ·
/// 4 가운데)와 같다 — `pointer> at`의 `buttons=`가 그 수로 찍힌다.
pub const Buttons = packed struct(u3) {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub fn bits(self: Buttons) u3 {
        return @bitCast(self);
    }
};

/// 디코더의 출력(PD design 결정 3). 마우스든 터치패드든 이 모양이다.
///
/// `buttons`는 변화가 아니라 그 순간의 상태다. 눌림과 뗌의 전이는
/// `Pointer.apply`가 장치 전체를 합친 뒤에 낸다.
pub const Frame = struct {
    dx: i32 = 0,
    dy: i32 = 0,
    /// `REL_WHEEL`의 눈금. 양수가 휠을 앞으로 민 것이다.
    wheel: i32 = 0,
    buttons: Buttons = .{},
};

/// 마우스 하나의 raw `input_event`를 `Frame`으로 묶는다.
///
/// `SYN_REPORT`를 만나야 `Frame`을 낸다. 그 사이의 이동과 휠은 더해 둔다 —
/// QEMU는 127을 넘는 이동을 보고 여럿으로 쪼개 보내고(PD-M0 plan 확정 2),
/// 커널은 보고 하나를 여러 이벤트로 낸다.
pub const Mouse = struct {
    /// 다음 `SYN_REPORT`까지 모으는 이동과 휠.
    pending: Frame = .{},
    /// 지금 눌린 버튼. 보고를 넘어 유지된다 — 버튼 이벤트는 바뀔 때만 온다.
    held: Buttons = .{},
    /// `SYN_DROPPED`를 받았다. 다음 `SYN_REPORT`까지 버린다(TF 결정 6).
    dropping: bool = false,

    pub fn feed(self: *Mouse, ev_type: u16, code: u16, value: i32) ?Frame {
        if (ev_type == c.EV_SYN) {
            if (code == c.SYN_DROPPED) {
                self.dropping = true;
                self.pending = .{};
                return null;
            }
            if (code != c.SYN_REPORT) return null;
            if (self.dropping) {
                // 버린 구간에 버튼 이벤트가 있었으면 `held`가 낡았다. 마우스는
                // 다음 누름이 그것을 고친다(design 결정 3).
                self.dropping = false;
                self.pending = .{};
                return null;
            }
            var frame = self.pending;
            frame.buttons = self.held;
            self.pending = .{};
            return frame;
        }
        if (self.dropping) return null;
        switch (ev_type) {
            c.EV_REL => switch (code) {
                c.REL_X => self.pending.dx +|= value,
                c.REL_Y => self.pending.dy +|= value,
                c.REL_WHEEL => self.pending.wheel +|= value,
                // `REL_WHEEL_HI_RES`는 버린다. 커널이 120마다 `REL_WHEEL`도
                // 내므로 둘 다 세면 두 번 움직인다(design 결정 7). 가로 휠도
                // 버린다 — 쓰는 자리가 없다.
                else => {},
            },
            c.EV_KEY => switch (code) {
                c.BTN_LEFT => self.held.left = value != 0,
                c.BTN_RIGHT => self.held.right = value != 0,
                c.BTN_MIDDLE => self.held.middle = value != 0,
                // `KEY_*`와 나머지 버튼(BTN_SIDE · BTN_EXTRA 등)은 버린다.
                // 키보드와 마우스를 한 노드로 내는 장치에서 키는 키보드
                // 경로가 읽는다(design 결정 2).
                else => {},
            },
            // `EV_MSC`(`MSC_SCAN`, design 실측 2)와 그 밖은 버린다.
            else => {},
        }
        return null;
    }
};

/// 한 `Frame`을 적용한 결과. 눌림과 뗌은 장치 전체의 합이 바뀔 때만 나온다.
pub const Events = struct {
    pressed: Buttons = .{},
    released: Buttons = .{},
    moved: bool = false,
    wheel: i32 = 0,
};

/// 화면에 하나인 포인터(PD design "모델" 절). 좌표는 프레임버퍼 픽셀이고
/// `0..w-1` · `0..h-1` 안에 머문다. 출발은 가운데다(design 결정 4).
pub const Pointer = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    /// 장치 칸마다 지금 눌린 버튼. 칸 번호는 `main.zig`의 장치 칸 번호다.
    dev_buttons: [MAX_DEVICES]Buttons = @splat(.{}),
    /// 위의 합(OR).
    buttons: Buttons = .{},

    pub fn init(w: u32, h: u32) Pointer {
        return .{ .x = w / 2, .y = h / 2, .w = w, .h = h };
    }

    pub fn apply(self: *Pointer, dev: u3, f: Frame) Events {
        self.x = clampAdd(self.x, f.dx, self.w);
        self.y = clampAdd(self.y, f.dy, self.h);
        self.dev_buttons[dev] = f.buttons;
        var ev = self.merge();
        ev.moved = f.dx != 0 or f.dy != 0;
        ev.wheel = f.wheel;
        return ev;
    }

    /// 장치가 빠졌다. 누른 채 뽑힌 버튼이 영영 눌린 채로 남지 않게 그 칸을
    /// 비운다. 합이 바뀌면 뗌이 나온다.
    pub fn forget(self: *Pointer, dev: u3) Events {
        self.dev_buttons[dev] = .{};
        return self.merge();
    }

    fn merge(self: *Pointer) Events {
        var sum: u3 = 0;
        for (self.dev_buttons) |b| sum |= b.bits();
        const before = self.buttons.bits();
        self.buttons = @bitCast(sum);
        return .{
            .pressed = @bitCast(sum & ~before),
            .released = @bitCast(before & ~sum),
        };
    }
};

/// `pos + delta`를 `0..limit-1` 안에 둔다. 넘침 없이 `i64`로 셈한다.
fn clampAdd(pos: u32, delta: i32, limit: u32) u32 {
    if (limit == 0) return 0;
    const next = @as(i64, pos) + delta;
    if (next < 0) return 0;
    if (next >= limit) return limit - 1;
    return @intCast(next);
}
```

확인은 Task 3에서 컴파일과 함께 한다.

## Task 3: `terminal/src/pointer_test.zig` · `terminal/build.zig`

### 3-1. `pointer_test.zig` — 새 파일

Write 도구로 아래 내용 그대로 만든다. 모양은 `layout_test.zig`를 따른다 — `pub fn main` 하나, 검사마다 OK 줄,
실패는 `FAIL: …` 뒤 `return error.…`, 끝에 `pointer_test: all checks passed`.

검사 열. 1 비트맵 순서 · 2 `fromSysfs` 변환 · 3 게스트 장치 넷(확정 6, 글자 그대로) · 4 게스트에 없는 장치 넷
(흔한 값) · 5 ioctl 번호 일곱(확정 4의 표) · 6 디코더 · 7 쪼개진 큰 이동(확정 2) · 8 `SYN_DROPPED` · 9 좌표와
clamp · 10 장치별 버튼의 합.

```zig
const std = @import("std");
const pointer = @import("pointer.zig");
const c = pointer.c;

/// `/proc/bus/input/devices`의 `B:` 줄(높은 워드가 앞, 워드는 64비트)을
/// ioctl이 채우는 모양(낮은 바이트부터)으로 바꾼다.
///
/// 검사 데이터를 게스트에서 본 글자 그대로 적기 위한 것이다(PD-M0 plan
/// 확정 6). 두 형식이 반대 순서라는 것이 design 결정 2의 요점이고, 이 함수가
/// 그 변환을 한 자리에서 한다 — 틀리면 검사 2가 잡는다.
fn fromSysfs(comptime n: usize, comptime text: []const u8) [n]u8 {
    @setEvalBranchQuota(10_000);
    var out: [n]u8 = @splat(0);
    var words: [16]u64 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |w| : (count += 1) {
        words[count] = std.fmt.parseInt(u64, w, 16) catch unreachable;
    }
    // 마지막 워드가 워드 0이다.
    for (0..count) |i| {
        const word = words[count - 1 - i];
        for (0..8) |b| {
            const at = i * 8 + b;
            if (at < n) out[at] = @truncate(word >> @intCast(b * 8));
        }
    }
    return out;
}

/// 게스트의 `B:` 줄 다섯으로 `Caps`를 만든다. 없는 줄은 `"0"`이다.
fn caps(
    comptime prop: []const u8,
    comptime ev: []const u8,
    comptime key: []const u8,
    comptime rel: []const u8,
    comptime abs: []const u8,
) pointer.Caps {
    const z: pointer.Caps = .{};
    return .{
        .prop = fromSysfs(z.prop.len, prop),
        .ev = fromSysfs(z.ev.len, ev),
        .key = fromSysfs(z.key.len, key),
        .rel = fromSysfs(z.rel.len, rel),
        .abs = fromSysfs(z.abs.len, abs),
    };
}

fn expectKind(what: []const u8, got: pointer.Kind, want: pointer.Kind) !void {
    if (got == want) {
        std.debug.print("pointer_test: {s} is {s} OK\n", .{ what, @tagName(got) });
        return;
    }
    std.debug.print("FAIL: {s} classified as {s}, want {s}\n", .{ what, @tagName(got), @tagName(want) });
    return error.WrongKind;
}

fn expectTrue(what: []const u8, ok: bool) !void {
    if (ok) {
        std.debug.print("pointer_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}\n", .{what});
    return error.CheckFailed;
}

fn expectNum(what: []const u8, got: u64, want: u64) !void {
    if (got == want) {
        std.debug.print("pointer_test: {s} = 0x{x} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = 0x{x}, want 0x{x}\n", .{ what, got, want });
    return error.WrongNumber;
}

fn expectFrame(what: []const u8, got: ?pointer.Frame, want: ?pointer.Frame) !void {
    if (std.meta.eql(got, want)) {
        std.debug.print("pointer_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, got, want });
    return error.WrongFrame;
}

fn expectAt(what: []const u8, p: *const pointer.Pointer, x: u32, y: u32) !void {
    if (p.x == x and p.y == y) {
        std.debug.print("pointer_test: {s} at {d},{d} OK\n", .{ what, x, y });
        return;
    }
    std.debug.print("FAIL: {s}: at {d},{d}, want {d},{d}\n", .{ what, p.x, p.y, x, y });
    return error.WrongPosition;
}

/// 마우스 디코더에 이벤트 하나를 먹이고 결과를 돌려준다. 검사를 이벤트
/// 목록처럼 읽히게 하려는 것이다.
fn feed(m: *pointer.Mouse, ev_type: anytype, code: anytype, value: i32) ?pointer.Frame {
    return m.feed(@intCast(ev_type), @intCast(code), value);
}

/// 포인터 장치의 분류 · 디코더 · 좌표를 본다. 부팅도 fd도 안 쓴다(PD design
/// 결정 3). 게이트(`pointer/check.sh`)가 빨개졌을 때 어느 층인지 가르는 자리다.
pub fn main() !void {
    // ── 검사 1: ioctl 비트맵은 낮은 번호부터다 ─────────────────────────
    {
        const map = [_]u8{ 0b0000_0011, 0b1000_0000 };
        try expectTrue("bit 0 and 1 in byte 0", pointer.bitSet(&map, 0) and pointer.bitSet(&map, 1));
        try expectTrue("bit 2 is clear", !pointer.bitSet(&map, 2));
        try expectTrue("bit 15 is the top of byte 1", pointer.bitSet(&map, 15));
        try expectTrue("bit 16 is past the map", !pointer.bitSet(&map, 16));
    }

    // ── 검사 2: 게스트의 B: 줄을 바꾼 결과 ───────────────────────────
    //
    // USB 마우스의 `KEY=1f0000 0 0 0 0`은 워드 4의 비트 16~20이다 —
    // 4 × 64 + 16 = 0x110 = BTN_LEFT부터 다섯(BTN_EXTRA 0x114까지).
    {
        const key = fromSysfs((pointer.Caps{}).key.len, "1f0000 0 0 0 0");
        try expectTrue("mouse KEY has BTN_LEFT", pointer.bitSet(&key, c.BTN_LEFT));
        try expectTrue("mouse KEY has BTN_EXTRA (0x114)", pointer.bitSet(&key, 0x114));
        try expectTrue("mouse KEY lacks 0x115", !pointer.bitSet(&key, 0x115));
        try expectTrue("mouse KEY lacks KEY_A", !pointer.bitSet(&key, c.KEY_A));
    }

    // ── 검사 3: 게스트에서 본 장치 넷(PD-M0 plan 확정 6) ─────────────
    //
    // 2026-10-05, `-usb -device usb-mouse -device usb-tablet`으로 뜬 게스트의
    // `/proc/bus/input/devices`. 글자 그대로다.
    try expectKind("Power Button", pointer.classify(&caps("0", "3", "8000 10000000000000 0", "0", "0")), .none);
    try expectKind("AT Translated Set 2 keyboard", pointer.classify(&caps(
        "0",
        "120013",
        "402000007 ff803078f800d001 feffffdfffcfffff fffffffffffffffe",
        "0",
        "0",
    )), .none);
    try expectKind("QEMU QEMU USB Mouse", pointer.classify(&caps("0", "17", "1f0000 0 0 0 0", "903", "0")), .mouse);
    try expectKind("QEMU QEMU USB Tablet", pointer.classify(&caps("0", "1f", "70000 0 0 0 0", "900", "3")), .none);

    // ── 검사 4: 게스트에 없는 장치(흔한 값, 실측 아님) ─────────────────
    //
    // PS/2 Synaptics 터치패드: PROP=5(POINTER · BUTTONPAD), ABS에 X · Y ·
    // PRESSURE · TOOL_WIDTH · MT_SLOT · MT_POSITION_X/Y · TRACKING_ID ·
    // MT_PRESSURE, KEY에 BTN_LEFT · BTN_TOOL_FINGER · BTN_TOUCH · TOOL_*TAP.
    try expectKind("Synaptics touchpad", pointer.classify(&caps(
        "5",
        "b",
        "e520 10000 0 0 0 0",
        "0",
        "660800011000003",
    )), .touchpad);
    // PROP가 0이어도 BTN_TOOL_FINGER가 있으면 터치패드다(design 결정 2의 "또는").
    try expectKind("touchpad without INPUT_PROP_POINTER", pointer.classify(&caps(
        "0",
        "b",
        "e520 10000 0 0 0 0",
        "0",
        "660800011000003",
    )), .touchpad);
    // 터치스크린: PROP=2(DIRECT). ABS_MT가 있어도 none이다(비목표 4).
    try expectKind("touchscreen", pointer.classify(&caps("2", "b", "400 0 0 0 0 0", "0", "260800000000003")), .none);
    // TrackPoint: PROP=21(POINTER · POINTING_STICK)이지만 ABS가 없다 — 마우스다.
    try expectKind("TrackPoint", pointer.classify(&caps("21", "7", "70000 0 0 0 0", "3", "0")), .mouse);

    // ── 검사 5: ioctl 요청 번호 ───────────────────────────────────────
    //
    // 오른쪽은 컨테이너의 `/usr/include/linux/input.h`를 C로 컴파일해 찍은
    // 값이다(PD-M0 plan 확정 4). x86_64와 aarch64가 같은 `asm-generic/ioctl.h`
    // 배치를 쓴다.
    {
        const z: pointer.Caps = .{};
        try expectNum("EVIOCGBIT(0, 4)", pointer.eviocgbit(0, z.ev.len), 0x80044520);
        try expectNum("EVIOCGBIT(EV_KEY, 96)", pointer.eviocgbit(c.EV_KEY, z.key.len), 0x80604521);
        try expectNum("EVIOCGBIT(EV_REL, 2)", pointer.eviocgbit(c.EV_REL, z.rel.len), 0x80024522);
        try expectNum("EVIOCGBIT(EV_ABS, 8)", pointer.eviocgbit(c.EV_ABS, z.abs.len), 0x80084523);
        try expectNum("EVIOCGPROP(4)", pointer.eviocgprop(z.prop.len), 0x80044509);
        try expectNum("EVIOCGNAME(64)", pointer.eviocgname(64), 0x80404506);
        try expectNum("EVIOCGABS(ABS_MT_POSITION_X)", pointer.eviocgabs(c.ABS_MT_POSITION_X), 0x80184575);
    }

    // ── 검사 6: 디코더는 SYN_REPORT에 한 Frame을 낸다 ──────────────────
    //
    // 이벤트의 순서는 게스트에서 읽은 바이트 그대로다(PD design 실측 2).
    {
        var m: pointer.Mouse = .{};
        try expectFrame("REL_X 10 is held until SYN", feed(&m, c.EV_REL, c.REL_X, 10), null);
        _ = feed(&m, c.EV_REL, c.REL_Y, 5);
        try expectFrame("mouse_move 10 5", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 10, .dy = 5 });

        _ = feed(&m, c.EV_MSC, c.MSC_SCAN, 0x90001);
        _ = feed(&m, c.EV_KEY, c.BTN_LEFT, 1);
        try expectFrame("mouse_button 1", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .buttons = .{ .left = true } });
        // 버튼은 보고를 넘어 유지된다.
        _ = feed(&m, c.EV_REL, c.REL_X, 1);
        try expectFrame("a move keeps the held button", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 1, .buttons = .{ .left = true } });
        _ = feed(&m, c.EV_MSC, c.MSC_SCAN, 0x90001);
        _ = feed(&m, c.EV_KEY, c.BTN_LEFT, 0);
        try expectFrame("mouse_button 0", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{});

        // 커널은 고해상도 휠을 함께 낸다. 그것을 세면 휠이 두 번 움직인다.
        _ = feed(&m, c.EV_REL, c.REL_WHEEL, 1);
        _ = feed(&m, c.EV_REL, c.REL_WHEEL_HI_RES, 120);
        try expectFrame("mouse_move 0 0 1 drops REL_WHEEL_HI_RES", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .wheel = 1 });

        // 오른쪽 · 가운데는 상태만 든다. 키 코드와 BTN_SIDE는 버린다.
        _ = feed(&m, c.EV_KEY, c.BTN_RIGHT, 1);
        _ = feed(&m, c.EV_KEY, c.BTN_MIDDLE, 1);
        _ = feed(&m, c.EV_KEY, c.BTN_SIDE, 1);
        _ = feed(&m, c.EV_KEY, c.KEY_A, 1);
        try expectFrame("right and middle, no KEY_A or BTN_SIDE", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .buttons = .{ .right = true, .middle = true } });
        _ = feed(&m, c.EV_KEY, c.BTN_RIGHT, 0);
        _ = feed(&m, c.EV_KEY, c.BTN_MIDDLE, 0);
        _ = feed(&m, c.EV_SYN, c.SYN_REPORT, 0);
    }

    // ── 검사 7: QEMU가 쪼갠 큰 이동은 보고 셋이다(plan 확정 2) ─────────
    {
        var m: pointer.Mouse = .{};
        var sum: i32 = 0;
        var frames: usize = 0;
        for ([_]i32{ 127, 127, 46 }) |dx| {
            _ = feed(&m, c.EV_REL, c.REL_X, dx);
            if (feed(&m, c.EV_SYN, c.SYN_REPORT, 0)) |f| {
                sum += f.dx;
                frames += 1;
            }
        }
        try expectTrue("mouse_move 300 0 arrives as three frames summing to 300", frames == 3 and sum == 300);
    }

    // ── 검사 8: SYN_DROPPED 뒤에는 다음 SYN_REPORT까지 버린다 ─────────
    {
        var m: pointer.Mouse = .{};
        _ = feed(&m, c.EV_REL, c.REL_X, 7);
        try expectFrame("SYN_DROPPED itself", feed(&m, c.EV_SYN, c.SYN_DROPPED, 0), null);
        _ = feed(&m, c.EV_REL, c.REL_X, 3);
        try expectFrame("the report after SYN_DROPPED is dropped", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), null);
        _ = feed(&m, c.EV_REL, c.REL_X, 2);
        try expectFrame("the next report is whole again", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 2 });
    }

    // ── 검사 9: 좌표는 가운데에서 출발하고 화면 안에 머문다 ─────────────
    //
    // 게이트의 프레임버퍼는 1280 × 800이다. 체인 검사 2 · 5가 같은 수를 본다.
    {
        var p = pointer.Pointer.init(1280, 800);
        try expectAt("start", &p, 640, 400);
        const e = p.apply(0, .{ .dx = 10, .dy = 5 });
        try expectAt("after 10,5", &p, 650, 405);
        try expectTrue("a move is a move", e.moved and e.wheel == 0);
        _ = p.apply(0, .{ .dx = -2000, .dy = -2000 });
        try expectAt("clamped to the top left", &p, 0, 0);
        _ = p.apply(0, .{ .dx = 5000, .dy = 5000 });
        try expectAt("clamped to the bottom right", &p, 1279, 799);
        const w = p.apply(0, .{ .wheel = -1 });
        try expectTrue("a wheel frame is not a move", !w.moved and w.wheel == -1);
        _ = p.apply(0, .{ .dx = std.math.minInt(i32), .dy = std.math.maxInt(i32) });
        try expectAt("extreme deltas do not overflow", &p, 0, 799);
    }

    // ── 검사 10: 버튼은 장치별로 들고 합이 바뀔 때만 눌림 · 뗌이 나온다 ──
    //
    // 마우스로 누른 채 다른 장치로 눌렀다 떼도 뗌이 한 번이다(design 결정 3).
    {
        var p = pointer.Pointer.init(1280, 800);
        const left: pointer.Buttons = .{ .left = true };
        var e = p.apply(0, .{ .buttons = left });
        try expectTrue("device 0 presses left", e.pressed.left and !e.released.left and p.buttons.left);
        e = p.apply(1, .{ .buttons = left });
        try expectTrue("device 1 pressing too is not a second press", !e.pressed.left);
        e = p.apply(0, .{});
        try expectTrue("device 0 lets go, device 1 still holds", !e.released.left and p.buttons.left);
        e = p.apply(1, .{});
        try expectTrue("the last one lets go: one release", e.released.left and !p.buttons.left);

        _ = p.apply(2, .{ .buttons = .{ .right = true } });
        e = p.forget(2);
        try expectTrue("a device pulled while holding releases its button", e.released.right and p.buttons.bits() == 0);
        try expectTrue("bits follow QEMU mouse_button (1 left, 2 right, 4 middle)", (pointer.Buttons{ .left = true }).bits() == 1 and
            (pointer.Buttons{ .right = true }).bits() == 2 and (pointer.Buttons{ .middle = true }).bits() == 4);
    }

    // ── 검사 11: uevent에서 새 evdev 노드만 고른다 ─────────────────────────
    //
    // 앞의 넷은 2026-10-05 `pointer` 체인의 `device_add` · `device_del`이 낸
    // uevent 그대로다(PD-M0 plan 확정 7, NUL이 필드 사이와 끝에 있다). 뒤의
    // 둘은 같은 모양으로 만든 것이다 — 노드 없는 `inputN`의 `add`와, 이
    // 커널에서는 안 오는 `mouseN`.
    {
        const add_event3 = "add@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=add\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=686\x00";
        const remove_event3 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=690\x00";
        const remove_input4 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00SUBSYSTEM=input\x00PRODUCT=3/627/1/1\x00NAME=\"QEMU QEMU USB Mouse\"\x00PROP=0\x00EV=17\x00KEY=1f0000 0 0 0 0\x00REL=903\x00MSC=10\x00SEQNUM=691\x00";
        const bind_usb = "bind@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00ACTION=bind\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00SUBSYSTEM=usb\x00MAJOR=189\x00MINOR=3\x00DEVNAME=bus/usb/001/004\x00DEVTYPE=usb_device\x00DRIVER=usb\x00SEQNUM=689\x00";
        const add_input4 = "add@/devices/virtual/input/input4\x00ACTION=add\x00SUBSYSTEM=input\x00NAME=\"QEMU QEMU USB Mouse\"\x00SEQNUM=685\x00";
        const add_mouse0 = "add@/devices/virtual/input/input4/mouse0\x00ACTION=add\x00SUBSYSTEM=input\x00DEVNAME=input/mouse0\x00SEQNUM=687\x00";
        const got = pointer.ueventAddedNode(add_event3);
        try expectTrue("uevent add of input/event3 names event3", got != null and std.mem.eql(u8, got.?, "event3"));
        try expectTrue("uevent remove of the same node is ignored", pointer.ueventAddedNode(remove_event3) == null);
        try expectTrue("uevent remove of inputN (no node) is ignored", pointer.ueventAddedNode(remove_input4) == null);
        try expectTrue("uevent of a usb device node is ignored", pointer.ueventAddedNode(bind_usb) == null);
        try expectTrue("uevent add of inputN (no DEVNAME) is ignored", pointer.ueventAddedNode(add_input4) == null);
        try expectTrue("uevent add of input/mouse0 is ignored", pointer.ueventAddedNode(add_mouse0) == null);
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
}
```

### 3-2. `build.zig` — 등록

`b.installArtifact(layout_test);`(283줄) 바로 뒤, 빈 줄 하나를 두고 `// \`zig build test\` = 호스트에서 도는 검사만`
앞에 넣는다. `status_test`와 같은 모양이다 — `pointer.zig`가 `c_input`을 쓰므로 `link_libc`와 `c_input_host`가
필요하다.

바꾸기 전:

```zig
    const layout_test = b.addExecutable(.{
        .name = "layout_test",
        .root_module = layout_test_mod,
    });
    b.installArtifact(layout_test);
```

바꾼 뒤:

```zig
    const layout_test = b.addExecutable(.{
        .name = "layout_test",
        .root_module = layout_test_mod,
    });
    b.installArtifact(layout_test);

    // pointer_test도 호스트에서 돈다(PD-M0). `status_test`와 같은 자리다 —
    // `pointer.zig`가 `c_input`(linux/input.h 번역)을 쓰므로 libc가 따라온다.
    // 분류 · 디코더 · 좌표의 산수만 보고 fd는 안 연다.
    const pointer_test_mod = b.createModule(.{
        .root_source_file = b.path("src/pointer_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    pointer_test_mod.link_libc = true;
    pointer_test_mod.addImport("c_input", c_input_host.mod);
    const pointer_test = b.addExecutable(.{
        .name = "pointer_test",
        .root_module = pointer_test_mod,
    });
    b.installArtifact(pointer_test);
```

그리고 `test` 스텝의 마지막 줄 뒤에 한 줄.

바꾸기 전:

```zig
    test_step.dependOn(&b.addRunArtifact(layout_test).step);
```

바꾼 뒤:

```zig
    test_step.dependOn(&b.addRunArtifact(layout_test).step);
    test_step.dependOn(&b.addRunArtifact(pointer_test).step);
```

### 3-3. 확인

```bash
git diff --stat terminal/build.zig
git diff terminal/build.zig | rg '^-'
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out; grep -a -c "^PASS" /tmp/t.out
  grep -a -E "all checks passed|FAIL|error:" /tmp/t.out
  zig build > /tmp/b.out 2>&1; echo "build exit=$?"'
```

기대: `1 file changed, 17 insertions(+)`, 둘째 명령은 `--- a/terminal/build.zig` 한 줄. 컨테이너는 `exit=0`, `53`,
`5`, `all checks passed` 셋(`layout_test` · `pointer_test` · `status_test`), `FAIL` · `error:` 0줄, `build exit=0`.
`zig build`를 함께 돌리는 것은 lessons 실측 1 때문이다 — 이 단계에서 `main.zig`는 아직 `pointer.zig`를 안 부르지만,
`exe_mod`가 깨지지 않았는지 지금 본다.

## Task 4: `terminal/src/main.zig`

일곱 자리다(4-2에 `socket` 선언, 4-3 · 4-4에 uevent 소켓이 들어 있다). Edit 도구로 한다(또는 python 정확 치환 — 치환마다 대상이 정확히 한 번 있는지 확인한다). 4-3 · 4-4는
새 글자를 넣기만 하고, 4-5 · 4-6 · 4-7이 기존 줄을 바꾼다. 지우는 줄은 전부 열이다(4-8의 기대).

### 4-1. import

바꾸기 전:

```zig
const layout = @import("layout.zig");
```

바꾼 뒤:

```zig
const layout = @import("layout.zig");
const pointer = @import("pointer.zig");
```

### 4-2. `ioctl` 선언 — `setenv` 선언 바로 뒤

바꾸기 전:

```zig
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
```

바꾼 뒤:

```zig
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

/// ioctl도 같은 이유로 직접 선언한다(PD-M0). 시그니처는 `drm.zig`가 받는
/// `c_drm` 번역의 것과 같다. 요청 번호는 `pointer.zig`가 번역된 매크로로 짓는다.
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

/// socket도 직접 선언한다. `std.c`에 있지만 공개가 아니다(PD-M0 plan 확정 4).
/// 부팅 뒤에 꽂힌 포인터 장치를 커널의 uevent netlink 소켓으로 안다.
extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;
```

### 4-3. 장치 함수 여섯 — `pub fn main` 바로 앞

`dumpPane`의 끝과 `pub fn main(init: std.process.Init) !void {` 사이다. 상수 셋 · 구조체 둘 · 함수 여섯
(`readCaps` · `tryOpenPointer` · `scanPointers` · `drainUevents` · `drainPointer` · `closePointer`)이고, 시스템 콜은 전부
여기 있다. 판단은 `pointer.zig`에 맡긴다.

읽을 자리 넷. `tryOpenPointer`의 중복 건너뛰기(경로 비교)와 `O_NONBLOCK`의 이유. `scanPointers`가 `event`로
시작하는 이름만 보는 것. `drainUevents`가 `remove`를 안 보는 이유(빠진 장치는 fd 쪽에서 안다)와 `ENOBUFS`에서 다시
훑는 것. `drainPointer`의
read 열여섯 번 상한.

바꾸기 전:

```zig
pub fn main(init: std.process.Init) !void {
```

바꾼 뒤:

```zig
// ── 포인터 장치(PD-M0) ───────────────────────────────────────────────
//
// 찾고 열고 읽고 닫는 시스템 콜 쪽이다. 판단(분류 · 디코딩 · 좌표)은 전부
// `pointer.zig`에 있고 여기는 fd와 로그만 다룬다(PD design 결정 3).

/// 포인터 장치를 찾는 디렉터리. 처음 훑기가 이것을 읽는다(design 결정 1).
const POINTER_DIR = "/dev/input";
/// `/dev/input/eventN`의 경로 버퍼. `event` 뒤 번호가 몇 자리여도 넉넉하다.
const POINTER_PATH_MAX = 64;
/// 장치 이름(`EVIOCGNAME`)의 버퍼. 로그에 찍기만 한다 — 판정은 이름을 안 본다.
const POINTER_NAME_MAX = 64;

/// 장치 칸 하나. 경로를 드는 이유는 둘이다 — 처음 훑기와 uevent가 겹쳐
/// 같은 경로가 두 번 오면 건너뛰려고, 그리고 `close` 줄에 찍으려고.
const PointerDev = struct {
    fd: c_int,
    path: [POINTER_PATH_MAX]u8,
    path_len: usize,
    mouse: pointer.Mouse = .{},

    fn pathSlice(self: *const PointerDev) []const u8 {
        return self.path[0..self.path_len];
    }
};

/// 한 poll 회차의 포인터 이벤트 요약. 회차가 끝나면 `at` 줄 하나가 된다.
const PointerRound = struct {
    frames: usize = 0,
    wheel: i32 = 0,
};

/// 연 fd에 성질을 묻는다. 하나라도 실패하면 null이다 — 분류할 수 없는
/// 장치라 열지 않는다. sysfs가 아니라 ioctl인 이유는 design 결정 1이다.
fn readCaps(fd: c_int) ?pointer.Caps {
    var caps: pointer.Caps = .{};
    if (ioctl(fd, pointer.eviocgbit(0, caps.ev.len), &caps.ev) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_KEY, caps.key.len), &caps.key) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_REL, caps.rel.len), &caps.rel) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_ABS, caps.abs.len), &caps.abs) < 0) return null;
    if (ioctl(fd, pointer.eviocgprop(caps.prop.len), &caps.prop) < 0) return null;
    return caps;
}

/// `/dev/input/<name>`을 열어 보고 마우스면 빈 칸에 넣는다(design 결정 1 · 2).
/// 처음 훑기와 uevent의 `add`가 이 함수 하나를 지난다.
///
/// `O_NONBLOCK`인 이유. 키보드(`input.openDevice`)는 블로킹이고 poll이 깨운
/// 뒤 한 번만 읽는다. 포인터는 한 회차에 쌓인 것을 다 읽고 `EAGAIN`에서
/// 멈춰야 회차마다 `at` 줄이 하나다(design 결정 3). `O_CLOEXEC`는 패널의
/// 셸이 이 fd를 물려받지 않게 한다.
///
/// 줄의 `name=`은 언제나 맨 끝이다. 이름에 공백이 들어 있어서다.
///
/// PD-M0은 마우스만 연다. 분류가 `touchpad`를 내도 `skip`이다 — 터치패드
/// 디코더는 PD-M3이 더한다.
fn tryOpenPointer(devs: *[pointer.MAX_DEVICES]?PointerDev, name: []const u8) void {
    var path_buf: [POINTER_PATH_MAX]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, POINTER_DIR ++ "/{s}", .{name}) catch return;
    for (devs) |slot| {
        const d = slot orelse continue;
        if (std.mem.eql(u8, d.pathSlice(), path)) return;
    }
    const fd = std.c.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true });
    if (fd < 0) {
        std.debug.print("terminal: pointer> skip {s} error={s}\n", .{ path, @tagName(std.c.errno(fd)) });
        return;
    }
    const caps = readCaps(fd) orelse {
        std.debug.print("terminal: pointer> skip {s} error=ioctl\n", .{path});
        _ = std.c.close(fd);
        return;
    };
    var name_buf: [POINTER_NAME_MAX]u8 = @splat(0);
    _ = ioctl(fd, pointer.eviocgname(name_buf.len), &name_buf);
    // 커널은 NUL까지 쓰지만, 이름이 버퍼보다 길면 잘린 채 NUL이 없다.
    name_buf[name_buf.len - 1] = 0;
    const dev_name = std.mem.sliceTo(&name_buf, 0);

    const kind = pointer.classify(&caps);
    if (kind != .mouse) {
        std.debug.print("terminal: pointer> skip {s} kind={s} name={s}\n", .{ path, @tagName(kind), dev_name });
        _ = std.c.close(fd);
        return;
    }
    const free = for (devs, 0..) |slot, i| {
        if (slot == null) break i;
    } else {
        std.debug.print("terminal: pointer> skip {s} full name={s}\n", .{ path, dev_name });
        _ = std.c.close(fd);
        return;
    };
    devs[free] = .{ .fd = fd, .path = undefined, .path_len = path.len };
    @memcpy(devs[free].?.path[0..path.len], path);
    // `shown=0`은 화살표가 아직 안 보인다는 뜻이다. 열린 뒤 움직여야 보인다
    // (design 결정 4의 보이는 조건 2). PD-M0은 아예 안 그리므로 언제나 0이다.
    std.debug.print("terminal: pointer> open {s} kind=mouse shown=0 name={s}\n", .{ path, dev_name });
}

/// 부팅 때 이미 있던 장치를 훑는다. uevent 소켓을 연 뒤에 부른다 — 반대면
/// 훑은 뒤 소켓을 열기 전에 생긴 장치를 놓친다(design 결정 1). 실패해도 terminal은
/// 산다. 포인터 없이 키보드만으로 지금처럼 쓴다.
fn scanPointers(io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    var dir = std.Io.Dir.openDirAbsolute(io, POINTER_DIR, .{ .iterate = true }) catch |err| {
        std.debug.print("terminal: pointer> scan failed error={s}\n", .{@errorName(err)});
        return;
    };
    defer dir.close(io);
    var it = dir.iterate();
    // `event`로 시작하는 이름만 본다. `mice` · `mouseN`은 evdev 이전의
    // 통로이고 `INPUT_MOUSEDEV`가 꺼져 있어 생기지도 않는다(design 실측 6).
    while (it.next(io) catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "event")) tryOpenPointer(devs, entry.name);
    }
}

/// uevent 소켓에 쌓인 것을 다 읽는다. 부팅 뒤에 꽂힌 장치가 여기로 온다.
///
/// datagram 하나가 uevent 하나다. 무엇을 열지는 `pointer.ueventAddedNode`가
/// 가른다(`ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/eventN`).
/// devtmpfs는 노드를 만든 뒤에 uevent를 보내므로 그때 노드가 이미 있다
/// (PD-M0 plan 확정 7).
///
/// `remove`는 안 본다. 빠진 장치는 그 fd의 `POLLERR` · `POLLHUP` · `ENODEV`로
/// 안다(design 결정 1). read가 `ENOBUFS`면 소켓 버퍼가 넘쳐 커널이 메시지를
/// 버린 것이다 — 놓친 장치가 있을 수 있으므로 디렉터리를 다시 훑는다. 이미
/// 연 경로는 건너뛴다.
fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    // 커널 uevent 하나는 `UEVENT_BUFFER_SIZE`(2048바이트) 안이다.
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
            scanPointers(io, devs);
            continue;
        }
        if (n == 0) return;
        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
        tryOpenPointer(devs, name);
    }
}

/// 열린 장치에서 읽을 것을 다 읽어 `Pointer`에 적용한다. `EAGAIN`에서 멈춘다.
/// 장치가 사라졌으면(`ENODEV` 등) `.gone`이다.
///
/// read를 열여섯 번까지만 한다. 장치가 쉬지 않고 이벤트를 내도 이 회차가
/// 끝나야 키보드와 PTY가 돈다 — 남은 것은 다음 poll이 다시 알린다.
fn drainPointer(dev: *PointerDev, slot: u3, state: *pointer.Pointer, round: *PointerRound) enum { open, gone } {
    const ev_size = @sizeOf(pointer.c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;
    for (0..16) |_| {
        const n = std.c.read(dev.fd, &raw, raw.len);
        if (n < 0) return if (std.c.errno(n) == .AGAIN) .open else .gone;
        if (n == 0) return .gone;
        const count = @as(usize, @intCast(n)) / ev_size;
        for (0..count) |i| {
            const ev: *align(1) const pointer.c.struct_input_event = @ptrCast(&raw[i * ev_size]);
            const frame = dev.mouse.feed(ev.type, ev.code, ev.value) orelse continue;
            const e = state.apply(slot, frame);
            round.frames += 1;
            round.wheel +|= e.wheel;
        }
    }
    return .open;
}

/// 장치 칸을 비운다. 그 장치가 누르고 있던 버튼도 놓는다(`Pointer.forget`).
fn closePointer(devs: *[pointer.MAX_DEVICES]?PointerDev, slot: usize, state: *pointer.Pointer) void {
    const d = &devs[slot].?;
    std.debug.print("terminal: pointer> close {s}\n", .{d.pathSlice()});
    _ = std.c.close(d.fd);
    _ = state.forget(@intCast(slot));
    devs[slot] = null;
}

pub fn main(init: std.process.Init) !void {
```

### 4-4. uevent 소켓과 처음 훑기 — `pty_buf` 선언 뒤

`main()` 안, `var pty_buf: [4096]u8 = undefined;` 바로 뒤 · poll 배열의 주석 앞이다. 패널의 첫 셸을 띄운 뒤라서
`open` 줄이 `spawned child pid` 줄보다 뒤에 찍힌다.

바꾸기 전:

```zig
    var key_buf: [64]u8 = undefined;
    var pty_buf: [4096]u8 = undefined;
```

바꾼 뒤:

```zig
    var key_buf: [64]u8 = undefined;
    var pty_buf: [4096]u8 = undefined;

    // 포인터 장치(PD-M0). 키보드와 달리 terminal이 스스로 찾고, 부팅 뒤에
    // 꽂힌 것도 잡는다(PD design 결정 1). init의 `argv[4]`는 그대로다.
    //
    // 부팅 뒤의 장치는 커널의 uevent로 안다. udev가 듣는 것과 같은 netlink
    // 소켓이고 커널 config가 더 필요 없다 — inotify를 켜면 initramfs 풀기가
    // 느려진다(PD-M0 plan 확정 7). 소켓을 먼저 열고 그다음에 훑는다.
    //
    // 소켓이 실패해도 terminal은 산다 — 부팅 때 있던 장치만 쓰고 핫플러그를
    // 잃는다. 그때 `uevent_fd`는 -1이고 poll은 음수 fd를 건너뛴다.
    var pointer_devs: [pointer.MAX_DEVICES]?PointerDev = @splat(null);
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
    const uevent_fd: c_int = uevent: {
        const linux = std.os.linux;
        const fd = socket(linux.AF.NETLINK, linux.SOCK.DGRAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, linux.NETLINK.KOBJECT_UEVENT);
        if (fd < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(fd))});
            break :uevent -1;
        }
        // 그룹 1이 커널이 보내는 uevent다(그룹 2는 udevd가 다시 보내는 것). pid
        // 0은 소켓의 주소를 커널이 고르게 한다.
        const addr: linux.sockaddr.nl = .{ .pid = 0, .groups = 1 };
        const rc = std.c.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.nl));
        if (rc < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(rc))});
            _ = std.c.close(fd);
            break :uevent -1;
        }
        break :uevent fd;
    };
    scanPointers(init.io, &pointer_devs);
```

### 4-5. poll 배열의 선언

확정 9. 주석 · 크기 · `fd_devs` 한 벌 · `fd_panes` 주석의 첫 줄이 바뀐다.

바꾸기 전:

```zig
    // poll이 보는 fd. 키보드 하나와 모든 워크스페이스의 모든 패널이다
    // (WP design 위험 1). 포커스 없는 워크스페이스의 PTY도 읽어야 한다 —
    // 안 읽으면 그 셸이 출력 버퍼에 막혀 멈춘다.
    //
    // 크기는 상한(1 + 9 × 8)으로 고정하고 쓴 길이만 넘긴다. 패널 수가
    // 분할 · 닫기로 바뀌므로 매 바퀴 다시 짓는다 — 73칸을 채우는 비용은 없고,
    // "언제 고쳐 쓰는가"를 따로 들 필요가 없어진다.
    var fds: [1 + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
    // `fds[i + 1]`이 어느 패널의 것인지. 패널은 `workspaces` 배열 안에
```

바꾼 뒤:

```zig
    // poll이 보는 fd. 키보드 하나, uevent 소켓 하나(PD-M0), 열린 포인터 장치,
    // 그리고 모든 워크스페이스의 모든 패널이다(WP design 위험 1). 포커스 없는
    // 워크스페이스의 PTY도 읽어야 한다 — 안 읽으면 그 셸이 출력 버퍼에 막혀
    // 멈춘다.
    //
    // 크기는 상한(1 + 1 + 8 + 9 × 8)으로 고정하고 쓴 길이만 넘긴다. 패널 수와
    // 장치 수가 바뀌므로 매 바퀴 다시 짓는다 — 82칸을 채우는 비용은 없고,
    // "언제 고쳐 쓰는가"를 따로 들 필요가 없어진다.
    //
    // 자리는 `[0]` 키보드 · `[1]` uevent 소켓 · `[2..pty_base]` 포인터 장치 ·
    // `[pty_base..nfds]` PTY다. PD 전에는 PTY가 `[1..]`이었다 — 그 오프셋이
    // 이제 바퀴마다 다르므로 `pty_base`로 든다.
    var fds: [2 + pointer.MAX_DEVICES + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
    // `fds[2 + k]`가 어느 장치 칸의 것인지.
    var fd_devs: [pointer.MAX_DEVICES]usize = undefined;
    // `fds[pty_base + i]`가 어느 패널의 것인지. 패널은 `workspaces` 배열 안에
```

### 4-6. 루프 머리에서 배열을 짓는 자리

바꾸기 전:

```zig
        fds[0] = .{ .fd = keyboard_fd, .events = c.POLLIN, .revents = 0 };
        var nfds: usize = 1;
        for (&workspaces, 0..) |*slot, wi| {
            const w = if (slot.*) |*w| w else continue;
            for (&w.panes, 0..) |*pane_slot, leaf| {
                const pane = if (pane_slot.*) |*pane| pane else continue;
                fds[nfds] = .{ .fd = pane.session.master_fd, .events = c.POLLIN, .revents = 0 };
                fd_panes[nfds - 1] = .{ .pane = pane, .ws = wi, .leaf = @intCast(leaf) };
                nfds += 1;
            }
        }
```

바꾼 뒤:

```zig
        fds[0] = .{ .fd = keyboard_fd, .events = c.POLLIN, .revents = 0 };
        fds[1] = .{ .fd = uevent_fd, .events = c.POLLIN, .revents = 0 };
        var nfds: usize = 2;
        for (&pointer_devs, 0..) |*slot, di| {
            const d = if (slot.*) |*d| d else continue;
            fds[nfds] = .{ .fd = d.fd, .events = c.POLLIN, .revents = 0 };
            fd_devs[nfds - 2] = di;
            nfds += 1;
        }
        const pty_base = nfds;
        for (&workspaces, 0..) |*slot, wi| {
            const w = if (slot.*) |*w| w else continue;
            for (&w.panes, 0..) |*pane_slot, leaf| {
                const pane = if (pane_slot.*) |*pane| pane else continue;
                fds[nfds] = .{ .fd = pane.session.master_fd, .events = c.POLLIN, .revents = 0 };
                fd_panes[nfds - pty_base] = .{ .pane = pane, .ws = wi, .leaf = @intCast(leaf) };
                nfds += 1;
            }
        }
```

### 4-7. 포인터 분기와 PTY 루프의 오프셋

키보드 분기(`if (fds[0].revents & c.POLLIN != 0) { … }`)가 끝난 뒤, PTY 분기의 머리 주석 앞에 포인터 분기를
넣는다. 그리고 PTY 루프의 머리 한 줄을 바꾼다. 두 편집이다.

첫째 — 넣는다.

바꾸기 전:

```zig
        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
```

바꾼 뒤:

```zig
        // 포인터 장치(PD-M0). 키보드 뒤 · PTY 앞이다(design 결정 3).
        //
        // 빠진 장치를 uevent보다 먼저 닫는다. 빠진 번호가 곧바로 다시 쓰이면
        // 옛 칸의 경로가 남아 새 장치를 "이미 열었다"로 건너뛰기 때문이다.
        //
        // `POLLERR` · `POLLHUP`이면 읽지 않고 닫는다. 이것을 빠뜨리면 poll이
        // 그 fd에 대해 매 바퀴 즉시 돌아와 terminal이 CPU를 다 쓴다(design
        // 결정 1).
        var round: PointerRound = .{};
        for (fds[2..pty_base], fd_devs[0 .. pty_base - 2]) |pfd, di| {
            if (pfd.revents == 0) continue;
            var gone = pfd.revents & (c.POLLERR | c.POLLHUP) != 0;
            if (!gone and pfd.revents & c.POLLIN != 0) {
                gone = drainPointer(&pointer_devs[di].?, @intCast(di), &pointer_state, &round) == .gone;
            }
            if (gone) closePointer(&pointer_devs, di, &pointer_state);
        }
        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
        // 회차마다 한 줄이다. 이벤트마다 찍으면 마우스의 보고 빈도(수백 Hz)가
        // 그대로 줄 수가 된다(design 결정 3). PD-M0은 그리지 않으므로
        // `needs_redraw`를 안 켠다 — 화면이 한 픽셀도 안 바뀐다. 그래서
        // `shown`과 `ink`는 상수 0이다. PD-M1이 둘을 채운다(design 결정 10).
        if (round.frames > 0) {
            std.debug.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown=0 ink=0\n", .{
                pointer_state.x, pointer_state.y, pointer_state.buttons.bits(), round.wheel,
            });
        }

        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
```

둘째 — 바꾼다(PTY 루프의 머리, `rg -n 'for \(fds\[1\.\.nfds\]' terminal/src/main.zig`).

바꾸기 전:

```zig
        for (fds[1..nfds], fd_panes[0 .. nfds - 1]) |pfd, ref| {
```

바꾼 뒤:

```zig
        for (fds[pty_base..nfds], fd_panes[0 .. nfds - pty_base]) |pfd, ref| {
```

### 4-8. 확인

```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | rg '^-'
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build > /tmp/b.out 2>&1; echo "build exit=$?"; grep -a -E "error" /tmp/b.out | head -5
  zig build test > /tmp/t.out 2>&1; echo "test exit=$?"; grep -a -c "^pointer_test: .* OK$" /tmp/t.out'
for f in src/pointer.zig src/pointer_test.zig src/main.zig build.zig; do
  echo "== $f"; diff terminal/$f /tmp/run/pdm0/term/$f && echo SAME
done
```

기대: `1 file changed, 268 insertions(+), 10 deletions(-)`. 둘째 명령은 `--- a/terminal/src/main.zig`와 이 열 줄이다.

```
-    // poll이 보는 fd. 키보드 하나와 모든 워크스페이스의 모든 패널이다
-    // (WP design 위험 1). 포커스 없는 워크스페이스의 PTY도 읽어야 한다 —
-    // 안 읽으면 그 셸이 출력 버퍼에 막혀 멈춘다.
-    // 크기는 상한(1 + 9 × 8)으로 고정하고 쓴 길이만 넘긴다. 패널 수가
-    // 분할 · 닫기로 바뀌므로 매 바퀴 다시 짓는다 — 73칸을 채우는 비용은 없고,
-    var fds: [1 + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
-    // `fds[i + 1]`이 어느 패널의 것인지. 패널은 `workspaces` 배열 안에
-        var nfds: usize = 1;
-                fd_panes[nfds - 1] = .{ .pane = pane, .ws = wi, .leaf = @intCast(leaf) };
-        for (fds[1..nfds], fd_panes[0 .. nfds - 1]) |pfd, ref| {
```

다른 줄이 `-`로 나오면 편집이 다른 줄을 건드린 것이다 — 되돌리고 다시 한다. 컨테이너는 `build exit=0`(error 0줄),
`test exit=0`, `53`. 마지막 루프는 넷 다 `SAME`이어야 한다 — 확정 10의 사본은 이 plan의 코드를 그대로 넣고 체인까지
돌린 것이다. 다르면 그 `diff`를 보고에 붙이고, 다름이 plan의 코드 블록과 사본 중 어느 쪽의 잘못인지 적는다(plan의
코드 블록이 정본이다).

## Task 5: `pointer/check.sh` · `check.sh`

### 5-1. `pointer/check.sh` — 새 파일

`mkdir pointer` 뒤 Write 도구로 아래 내용 그대로 만들고 `chmod +x pointer/check.sh`. 뼈대(빌드 여섯 단계 · `cleanup` ·
`report_failure` · `source ../gate_lib.sh` · QEMU 호출 · 프롬프트 대기 · monitor 연결)는 `pane/check.sh`를 따른다.
다른 것은 QEMU 호출의 `-usb -device usb-mouse`, `MONITOR_PORT=45488`, screendump 둘(`terminal/check.sh`처럼
`${REPO_ROOT}/out/pd/`), 헬퍼 일곱이다.

검사 순서가 번호와 다르다. 검사 7(화면이 그대로다)을 검사 6(핫플러그)보다 먼저 판정한다 — 검사 6이 `echo`를 쳐서
화면을 바꾸기 때문이다. 번호는 design 결정 10의 것을 그대로 둔다.

| 검사 | 친다 | 본다 | 빨개지는 문구(머리) |
|---|---|---|---|
| 1 | 부팅 | `open … kind=mouse shown=0 name=QEMU QEMU USB Mouse` · `open` 정확히 하나 · 키보드와 전원 버튼의 `skip … kind=none name=…` · `close` 0 · `at` 0 | `terminal never opened the USB mouse` · `expected exactly one 'pointer> open' at boot, got N` |
| 2 | `mouse_move 10 5` | 마지막 `at`가 `x=650 y=405 buttons=0 wheel=0 shown=0 ink=0` | `after 'mouse_move 10 5' the last at line is …` |
| 3 | `mouse_button 1` · `0` | `buttons=1` 뒤 `buttons=0`(좌표 그대로) | `after 'mouse_button 1' …` |
| 4 | `mouse_move 0 0 1` | `wheel=1`(좌표 그대로) | `after 'mouse_move 0 0 1' …` |
| 5 | `mouse_move -100 -100` × 8 · `mouse_move 100 100` × 13 | `x=0 y=0` 뒤 `x=1279 y=799` | `after eight 'mouse_move -100 -100' …` |
| 7 | (검사 5 뒤) | `at` 줄 전부 `shown=0 ink=0` · `screen>` 줄 수가 움직이기 전과 같다 · screendump 둘이 바이트까지 같다 · 마지막 `pane>`가 확정 3의 글자 | `PD-M0 must not draw` · `pointer events made the terminal render` · `the framebuffer changed` |
| 6 | `device_add usb-mouse,id=pdhot` · `mouse_move -10 -10` · `device_del pdhot` · `mouse_move 10 10` · `echo pd-hotplug-ok` | 둘째 `open`(다른 경로, `kind=mouse`) · `x=1269 y=789` · 그 경로의 `close`(정확히 하나) · `x=1279 y=799` · 출력줄 `\| pd-hotplug-ok \|` | `terminal never opened it` · `was never closed` · `the shell stopped answering` |

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# PD 체인 — 포인터 장치(PD-M0). 열아홉번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU가 USB 마우스를 하나 붙인 채 뜬다(-usb -device usb-mouse)
#   → terminal이 uevent netlink 소켓을 열고 /dev/input을 훑는다
#   → 연 fd에 ioctl로 성질을 묻고 pointer.zig의 classify가 마우스만 고른다
#   → HMP mouse_move · mouse_button이 USB HID 보고가 되고 evdev 이벤트가 된다
#   → Mouse 디코더가 SYN_REPORT마다 Frame을 내고 Pointer가 좌표를 clamp한다
#   → poll 회차마다 `pointer> at` 한 줄
#   → 부팅 뒤에 device_add로 꽂은 둘째 마우스를 커널 uevent가 알리고 terminal이 연다
#   → device_del로 뽑으면 그 fd가 POLLHUP을 올리고 terminal이 닫는다
#   → 그동안 화면은 한 픽셀도 안 바뀐다(PD-M0은 그리지 않는다)
#
# copy · pane 체인에 끼우지 않은 이유는 PD design 결정 10이다. 그 체인들의
# 판정은 포인터가 없는 화면을 전제하고, 이 체인은 PD-M1부터 화살표가 보이는
# 프레임을 일부러 만든다.
#
# 판정의 도구가 둘이다.
#   pointer> 줄 — open · skip · close · at(main.zig). 좌표는 게이트
#                프레임버퍼 1280 × 800에서 나온다. 출발은 가운데(640, 400)다.
#   screendump 둘 — 움직이기 전과 뒤의 프레임버퍼가 바이트까지 같다(검사 7).
#
# HMP의 대상 마우스. info mice의 별표가 HMP mouse_move가 가는 장치다.
# device_add로 꽂은 마우스가 대상이 되고 device_del 뒤에는 원래 마우스로
# 돌아온다(PD-M0 plan 확정 1). 검사 6이 그것을 쓴다 — 꽂은 뒤의 움직임은 새
# 장치로만 오므로 "새 fd를 읽는다"가 at 줄로 보인다.
#
# 이동은 한 번에 100 이하로 민다. QEMU는 127을 넘는 이동을 보고 여럿으로
# 쪼개 보내므로(plan 확정 2) 큰 수도 합은 같지만, 보고 하나가 명령 하나인
# 편이 로그를 읽기 쉽다.
#
# 디스크를 물지 않는다. 포인터는 설정과 무관하다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 분류 · 디코더 · clamp는 여기서 먼저 걸러진다(pointer_test) — 부팅 전에
# 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 열여덟 체인이 45455~45487을 쓴다. 45489는 PD-M3의 부팅 B 몫이다(design 결정 10).
MONITOR_PORT=45488

REPO_ROOT="$(cd .. && pwd)"
# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로
# 넘긴다. out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다
# (terminal/check.sh와 같은 자리).
SCREENS_DIR="${REPO_ROOT}/out/pd"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
AFTER="${SCREENS_DIR}/after.ppm"
rm -f "$BEFORE" "$AFTER"

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "input: QEMU QEMU USB Mouse" \
    "terminal: screen>" \
    "terminal: pointer> open" \
    "terminal: pointer> skip" \
    "terminal: pointer> at" \
    "terminal: pointer> close" \
    "terminal: pointer> uevent failed" \
    "terminal: pointer> scan failed"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- kernel mouse lines ---"
  grep -aE 'input: QEMU QEMU USB Mouse|USB disconnect' "$LOG" | tr -d '\r'
  echo "--- pointer lines ---"
  grep -a 'terminal: pointer>' "$LOG" | tr -d '\r' | tail -n 30
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# pointer> 줄 중 접두가 맞는 것의 개수. 인자는 `open ` · `close ` · `at `처럼
# 동사와 공백이다.
pointer_count() {
  grep -ac "terminal: pointer> $1" "$LOG" || true
}

# 마지막 at 줄. 값이 줄 끝까지 가므로 \r를 지운다(HI-M1 실측 4).
last_at() {
  grep -a 'terminal: pointer> at ' "$LOG" | tail -n 1 | tr -d '\r'
}

# 커널이 만든 USB 마우스 입력 장치의 수. 검사 6이 "QEMU · 커널이 둘째
# 마우스를 안 만들었다"와 "terminal이 그것을 안 열었다"를 가르는 데 쓴다.
kernel_mice() {
  grep -ac 'input: QEMU QEMU USB Mouse as' "$LOG" || true
}

screen_lines() {
  grep -ac 'terminal: screen>' "$LOG" || true
}

# 마지막 at 줄이 패턴(ERE)에 맞을 때까지 기다린다. 있으면 0, 15초가 지나면 1.
# gate_lib.sh의 wait_for_screen과 같은 이유로 고정 sleep을 안 쓴다.
wait_for_at() {
  local pattern="$1" i line
  for i in $(seq 1 150); do
    line="$(last_at)"
    if grep -aqE -- "$pattern" <<<"$line"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초.
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aE -- "$pattern" "$LOG" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 어떤 함수가 돌려주는 수가 기준 이상이 될 때까지 기다린다. 15초.
wait_for_count() {
  local fn="$1" arg="$2" want="$3" i
  for i in $(seq 1 150); do
    if [ "$("$fn" "$arg")" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# HMP 명령 하나. 키와 달리 로그가 자라기를 기다리지 않는다 — 결과는 부르는
# 쪽이 wait_for_at으로 본다.
hmp() {
  echo "$1" >&3
  sleep 0.05
}

# screendump 하나를 뜨고 파일이 생길 때까지 기다린다. 10초.
screendump() {
  local out="$1" i
  echo "screendump ${out}" >&3
  for i in $(seq 1 100); do
    if [ -s "$out" ]; then sleep 0.2; return 0; fi
    sleep 0.1
  done
  return 1
}

qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -usb -device usb-mouse \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "the shell prompt never showed up"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 검사 1: 부팅 때의 USB 마우스를 열고, 키보드와 전원 버튼은 건너뛴다 ──
#
# 마우스는 terminal보다 먼저 생긴다(plan 확정 3) — 처음 훑기가 연다. 늦게
# 생겨도 uevent가 연다. 어느 쪽이든 같은 줄이다.
#
# "정확히 하나"가 이 검사의 본체다. classify가 EV_KEY만 보면 전원 버튼과
# 키보드도 열려 셋이 된다(mutation 1).
echo "=== boot: the USB mouse is open, the keyboard and the power button are not ==="
wait_for_log 'terminal: pointer> open /dev/input/event[0-9]+ kind=mouse shown=0 name=QEMU QEMU USB Mouse' ||
  report_failure "terminal never opened the USB mouse (no 'pointer> open … kind=mouse shown=0 name=QEMU QEMU USB Mouse')"
OPENS="$(pointer_count 'open ')"
[ "$OPENS" -eq 1 ] ||
  report_failure "expected exactly one 'pointer> open' at boot, got ${OPENS}"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=AT Translated Set 2 keyboard' "$LOG" >/dev/null ||
  report_failure "the AT keyboard was not skipped as kind=none"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=Power Button' "$LOG" >/dev/null ||
  report_failure "the power button was not skipped as kind=none"
[ "$(pointer_count 'close ')" -eq 0 ] ||
  report_failure "a pointer device was closed before anything was unplugged"
[ "$(pointer_count 'at ')" -eq 0 ] ||
  report_failure "an 'at' line showed up before the mouse moved: $(last_at)"
MOUSE_PATH="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*open ([^ ]+) .*/\1/')"
echo "boot mouse: ${MOUSE_PATH}"

# 검사 7의 재료. 움직이기 전의 프레임버퍼와 screen> 줄 수.
SCREENS_BEFORE_MOVES="$(screen_lines)"
screendump "$BEFORE" || report_failure "screendump did not write ${BEFORE}"

# ── 검사 2: 움직임이 좌표가 된다 ──────────────────────────────────────
#
# 출발이 가운데(640, 400)라서 10, 5를 밀면 650, 405다. y의 부호가 뒤집히면
# 395가 된다(mutation 4).
echo "=== mouse_move 10 5 ==="
hmp "mouse_move 10 5"
wait_for_at '^terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=0 ink=0$' ||
  report_failure "after 'mouse_move 10 5' the last at line is '$(last_at)', expected 'at x=650 y=405 buttons=0 wheel=0 shown=0 ink=0' (start 640,400)"
echo "moved: $(last_at)"

# ── 검사 3: 버튼 ──────────────────────────────────────────────────────
#
# HMP mouse_button의 비트(1 왼쪽)가 buttons=의 비트와 같다. 누름 뒤 뗌까지 본다 —
# 누름만 보면 "버튼이 영영 눌린 채"도 통과한다.
echo "=== mouse_button 1, then 0 ==="
hmp "mouse_button 1"
wait_for_at '^terminal: pointer> at x=650 y=405 buttons=1 wheel=0 ' ||
  report_failure "after 'mouse_button 1' the last at line is '$(last_at)', expected buttons=1 at 650,405"
hmp "mouse_button 0"
wait_for_at '^terminal: pointer> at x=650 y=405 buttons=0 wheel=0 ' ||
  report_failure "after 'mouse_button 0' the last at line is '$(last_at)', expected buttons=0"
echo "button: pressed and released"

# ── 검사 4: 휠 한 눈금 ────────────────────────────────────────────────
#
# 커널은 REL_WHEEL 1과 함께 REL_WHEEL_HI_RES 120을 낸다. 디코더가 앞의 것만
# 세므로 1이다. wheel=은 그 회차의 합이고 좌표는 그대로다.
echo "=== mouse_move 0 0 1 ==="
hmp "mouse_move 0 0 1"
wait_for_at '^terminal: pointer> at x=650 y=405 buttons=0 wheel=1 ' ||
  report_failure "after 'mouse_move 0 0 1' the last at line is '$(last_at)', expected wheel=1 at 650,405"
echo "wheel: $(last_at)"

# ── 검사 5: 좌표는 화면 밖으로 안 나간다 ──────────────────────────────
#
# 왼쪽 위로 800씩 밀면 0, 0에 붙는다. 오른쪽 아래로 1300씩 밀면 1279, 799다.
# clamp가 없으면 u32가 감겨 큰 수가 되거나 1300 근처가 찍힌다.
echo "=== clamp to the top left and the bottom right ==="
for _ in $(seq 1 8); do hmp "mouse_move -100 -100"; done
wait_for_at '^terminal: pointer> at x=0 y=0 ' ||
  report_failure "after eight 'mouse_move -100 -100' the last at line is '$(last_at)', expected x=0 y=0"
for _ in $(seq 1 13); do hmp "mouse_move 100 100"; done
wait_for_at '^terminal: pointer> at x=1279 y=799 ' ||
  report_failure "after thirteen 'mouse_move 100 100' the last at line is '$(last_at)', expected x=1279 y=799"
echo "clamped: $(last_at)"

# ── 검사 7: 화면은 그대로다 ───────────────────────────────────────────
#
# 검사 6보다 먼저 판정한다. 검사 6이 echo를 쳐서 화면을 바꾸기 때문이다.
#
# 셋을 본다. at 줄이 전부 shown=0 ink=0이다(PD-M0은 그리지 않는다). 포인터
# 이벤트가 렌더를 일으키지 않았다(screen> 줄 수). 프레임버퍼가 바이트까지
# 같다. 그리고 pane> 줄이 포인터 없는 부팅의 그것과 글자까지 같다 — 그 값은
# pane/check.sh 검사 1과 plan 확정 3이 본 것이다.
echo "=== the screen did not change ==="
AT_LINES="$(pointer_count 'at ')"
AT_DARK="$(grep -a 'terminal: pointer> at ' "$LOG" | tr -d '\r' | grep -cE ' shown=0 ink=0$' || true)"
[ "$AT_LINES" -eq "$AT_DARK" ] ||
  report_failure "${AT_LINES} at lines but only ${AT_DARK} say 'shown=0 ink=0'; PD-M0 must not draw"
[ "$(screen_lines)" -eq "$SCREENS_BEFORE_MOVES" ] ||
  report_failure "pointer events made the terminal render (screen> ${SCREENS_BEFORE_MOVES} -> $(screen_lines))"
screendump "$AFTER" || report_failure "screendump did not write ${AFTER}"
cmp -s "$BEFORE" "$AFTER" ||
  report_failure "the framebuffer changed while only the mouse moved (${BEFORE} vs ${AFTER})"
PANE_LINE="$(grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r')"
[ "$PANE_LINE" = "terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 sep ink=0" ] ||
  report_failure "the pane> line is '${PANE_LINE}', not the one a boot without a mouse prints"
echo "unchanged: ${AT_LINES} at lines, screen> ${SCREENS_BEFORE_MOVES}, framebuffer identical"

# ── 검사 6: 부팅 뒤에 꽂고 뺀다 ───────────────────────────────────────
#
# 꽂으면 커널 uevent(`add` · `DEVNAME=input/event3`)가 오고 terminal이 둘째
# open을 찍는다. uevent를 안 읽으면 여기서 멈춘다(mutation 2). 커널 줄을 함께
# 세는 것은 "QEMU · 커널이 마우스를
# 안 만들었다"와 "terminal이 안 열었다"를 가르기 위해서다.
#
# 빼면 그 fd가 POLLHUP · POLLERR을 올리고 terminal이 close를 찍는다. 닫지
# 않으면 close 줄이 없고, poll이 그 fd 때문에 매 바퀴 즉시 돌아온다(mutation 3).
#
# 마지막의 echo는 그 뒤에도 키보드와 PTY가 돈다는 것이다. 빠진 장치의 read에
# 막히거나 poll 배열의 오프셋이 어긋나면 셸의 출력이 안 온다.
echo "=== device_add, then device_del ==="
KERNEL_MICE="$(kernel_mice)"
hmp "device_add usb-mouse,id=pdhot"
if ! wait_for_count pointer_count 'open ' 2; then
  if [ "$(kernel_mice)" -le "$KERNEL_MICE" ]; then
    report_failure "device_add did not give the guest a second USB mouse (kernel 'input:' lines stayed at ${KERNEL_MICE})"
  fi
  report_failure "the kernel registered a second mouse but terminal never opened it (no second 'pointer> open')"
fi
NEW_LINE="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r')"
NEW_PATH="$(sed -E 's/.*open ([^ ]+) .*/\1/' <<<"$NEW_LINE")"
case "$NEW_LINE" in
  *" kind=mouse shown=0 name=QEMU QEMU USB Mouse") ;;
  *) report_failure "the hotplugged device opened as '${NEW_LINE}'" ;;
esac
[ "$NEW_PATH" != "$MOUSE_PATH" ] ||
  report_failure "the hotplugged mouse reused the open path ${MOUSE_PATH}"
echo "plugged: ${NEW_LINE}"

# HMP의 대상이 새 마우스로 갔다(plan 확정 1). 이 움직임은 새 fd로만 온다.
hmp "mouse_move -10 -10"
wait_for_at '^terminal: pointer> at x=1269 y=789 ' ||
  report_failure "a move on the hotplugged mouse never reached the pointer (last at: '$(last_at)')"

hmp "device_del pdhot"
wait_for_log "terminal: pointer> close ${NEW_PATH}" ||
  report_failure "the unplugged mouse was never closed (no 'pointer> close ${NEW_PATH}')"
[ "$(pointer_count 'close ')" -eq 1 ] ||
  report_failure "expected one 'pointer> close', got $(pointer_count 'close ')"
echo "unplugged: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

# 대상이 원래 마우스로 돌아왔다. 그 fd가 아직 열려 있고 읽힌다.
hmp "mouse_move 10 10"
wait_for_at '^terminal: pointer> at x=1279 y=799 ' ||
  report_failure "the boot mouse stopped moving the pointer after the unplug (last at: '$(last_at)')"

type_keys e c h o spc p d minus h o t p l u g minus o k ret
wait_for_screen '\| pd-hotplug-ok \|' ||
  report_failure "the shell stopped answering after the unplug (no 'pd-hotplug-ok' output line)"
echo "the shell still answers after the unplug"

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
echo "PD-M0 check PASS"
```

### 5-2. `check.sh` — 문단 하나와 `CHAINS` 한 줄

체인 설명 문단(SV 문단 뒤, `# 이름과 경로를 한 곳에 모은다.` 앞)과 `CHAINS`의 끝이다. Edit 도구로 두 번 한다.

바꾸기 전:

```bash
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

바꾼 뒤:

```bash
# PD 체인은 terminal이 포인터 장치를 스스로 찾아 열고 닫는가를 본다. USB 마우스를
# 하나 붙여 뜨고(-usb -device usb-mouse) monitor의 mouse_move · mouse_button으로
# 움직이며, device_add · device_del로 부팅 뒤에 꽂고 뺀다. 판정은 terminal의
# pointer> 줄과 screendump 둘이다. 회차당 부팅 1회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

바꾸기 전:

```bash
  "WP-M2:./pane/check.sh"
)
```

바꾼 뒤:

```bash
  "WP-M2:./pane/check.sh"
  "PD-M0:./pointer/check.sh"
)
```

### 5-3. 확인

```bash
bash -n pointer/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pointer/check.sh && require_no_early_exit_pipe ./pointer/check.sh &&
  require_explicit_nic ./pointer/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
ls -l pointer/check.sh | cut -c1-10
diff pointer/check.sh /tmp/run/pdm0/pointer/check.sh && echo SAME
git diff --stat check.sh
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK`, 권한 `-rwxr-xr-x`, `SAME`, `1 file changed, 6 insertions(+)`.
진입 검사가 실패하면 그 문구를 보고한다 — 파이프 뒤 `grep -q`를 쓰지 않는다(lessons 152행).

## Task 6: 체인 한 번과 regression 둘

체인은 하나씩 돈다. 셋이 같은 `kernel/initrd.cpio`를 다시 만들므로 겹쳐 돌리지 않는다(WP-M0 실측 8).
`pointer`는 캐시가 따뜻하면 1분 안팎이다. 커널은 HEAD 그대로라 그 단계는 건너뛴다.

### 6-1. `pointer` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm0:/tmp/run/pdm0 -w /workspace tars-devcontainer bash -c '
    bash pointer/check.sh > /tmp/run/pdm0/impl/pointer.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^===|^FAIL|^boot mouse|^moved|^button|^wheel|^clamped|^unchanged|^plugged|^unplugged|the shell still|took about|PD-M0 check' /tmp/run/pdm0/impl/pointer.log
rg -a '^terminal: pointer> (open|skip|close|uevent|scan)' /tmp/run/pdm0/impl/pointer.log
```

기대: `exit=0`. `rg`의 첫 출력은 이 열아홉 줄이다(확정 10의 두 번째 회차가 찍은 그대로).

```
=== boot: the USB mouse is open, the keyboard and the power button are not ===
boot mouse: /dev/input/event2
=== mouse_move 10 5 ===
moved: terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=0 ink=0
=== mouse_button 1, then 0 ===
button: pressed and released
=== mouse_move 0 0 1 ===
wheel: terminal: pointer> at x=650 y=405 buttons=0 wheel=1 shown=0 ink=0
=== clamp to the top left and the bottom right ===
clamped: terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=0 ink=0
=== the screen did not change ===
unchanged: 25 at lines, screen> 3, framebuffer identical
=== device_add, then device_del ===
plugged: terminal: pointer> open /dev/input/event3 kind=mouse shown=0 name=QEMU QEMU USB Mouse
unplugged: terminal: pointer> close /dev/input/event3
the shell still answers after the unplug
PD-M0 check PASS
```

`at` 줄 수(25)와 `screen>` 수(3)는 그 회차의 값이다 — 판정은 이 수를 안 본다. 둘째 `rg`는 다섯 줄이다
(`open …event2` · `skip …event1 … AT Translated Set 2 keyboard` · `skip …event0 … Power Button` ·
`open …event3` · `close …event3`). 디렉터리 순서라 앞의 셋은 순서가 다를 수 있다.

### 6-2. regression — `pane`과 `render`

poll 배열의 오프셋을 바꿨으므로 PTY가 여럿인 체인이 첫째 대상이다(`pane`, 약 1분 30초). `render`는 픽셀
판정이 가장 많은 체인이고 PD-M0의 "화면 그대로"를 기존 판정으로 한 번 더 본다(약 2분). 두 체인의 부팅에는
포인터 장치가 없다 — terminal은 `skip` 둘만 찍고 `fds[2..pty_base]`가 빈다.

```bash
for ch in pane render; do
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm0:/tmp/run/pdm0 -w /workspace tars-devcontainer bash -c "
      bash $ch/check.sh > /tmp/run/pdm0/impl/$ch.log 2>&1; echo exit=\$?" ; } 2>&1 | tail -4
  tail -1 /tmp/run/pdm0/impl/$ch.log
done
```

기대: 둘 다 `exit=0`, 마지막 줄 `WP-M2 check PASS` · render 체인의 PASS 줄. 빨개지면 그 로그의 `FAIL` 줄과 `rg -a
'terminal: pointer>' /tmp/run/pdm0/impl/$ch.log`를 보고한다.

## Task 7: mutation 넷

design 결정 10의 M0 네 줄이다. 확정 11의 방법으로 넣는다. 사본은 `/tmp/run/pdm0/impl/mut/`에 만든다. 넷 다 돌리기
전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 — `sd -F`가 빗나가도 에러가 없다(lessons 실측 52). 한 줄이
아니면 돌리지 말고 보고한다.

캐시를 지운 체인 한 판은 약 1분 25초다(확정 10에서 mutation 없이 잰 값이 83초, mutation 판은 74~100초였다. 커널은
건너뛴다). Bash 도구의 10분 상한 안이다.

### 7-0. 사본을 만든다

```bash
M=/tmp/run/pdm0/impl/mut; mkdir -p $M
cp terminal/src/pointer.zig $M/pointer_m1.zig
cp terminal/src/pointer.zig $M/pointer_m4.zig
cp terminal/src/main.zig $M/main_m2.zig
cp terminal/src/main.zig $M/main_m3.zig
cp pointer/check.sh $M/pointer_notest.sh
# mutation 1 — classify가 EV_KEY만 있어도 마우스라고 한다
sd -F 'if (bitSet(&caps.ev, c.EV_REL) and bitSet(&caps.rel, c.REL_X)' 'if (bitSet(&caps.ev, c.EV_KEY) or bitSet(&caps.ev, c.EV_REL) and bitSet(&caps.rel, c.REL_X)' $M/pointer_m1.zig
# mutation 2 — uevent를 안 읽는다(소켓이 열렸으면 uevent_fd는 음수가 아니다)
sd -F 'if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);' 'if (fds[1].revents & c.POLLIN != 0 and uevent_fd < 0) drainUevents(uevent_fd, init.io, &pointer_devs);' $M/main_m2.zig
# mutation 3 — 빠진 장치를 닫지 않는다(열린 fd는 음수가 아니다)
sd -F 'if (gone) closePointer(&pointer_devs, di, &pointer_state);' 'if (gone and pfd.fd < 0) closePointer(&pointer_devs, di, &pointer_state);' $M/main_m3.zig
# mutation 4 — REL_Y의 부호를 뒤집는다
sd -F 'c.REL_Y => self.pending.dy +|= value,' 'c.REL_Y => self.pending.dy -|= value,' $M/pointer_m4.zig
# mutation 1 · 4의 체인 판정용 — 부팅 전의 terminal 호스트 검사 한 단계만 끈다
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' $M/pointer_notest.sh
chmod +x $M/pointer_notest.sh
bash -c 'M=/tmp/run/pdm0/impl/mut
for p in "pointer.zig pointer_m1.zig" "pointer.zig pointer_m4.zig" "main.zig main_m2.zig" "main.zig main_m3.zig"; do
  set -- $p; echo "== $2"; diff terminal/src/$1 $M/$2
done
echo "== pointer_notest.sh"; diff pointer/check.sh $M/pointer_notest.sh'
```

기대: 다섯 `diff`가 각각 한 줄의 차이다(개정 판의 사본에서 `pointer.zig` 67 · 188줄, `main.zig` 2192 · 2190줄, 체인 61줄).
루프를 `bash -c`로 감싼 것은 호스트 zsh에서 `set -- $p`가 단어를 안 가르기 때문이다(lessons 실측 69).

### 7-1. mutation 1 · 4 — 먼저 `pointer_test`

```bash
for m in 1 4; do
  echo "== mutation $m"
  docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm0/impl/mut/pointer_m$m.zig:/workspace/terminal/src/pointer.zig:ro \
    -w /workspace/terminal tars-devcontainer bash -c '
    echo "mounted: $(grep -c -E "EV_KEY\) or bitSet|dy -\|= value" src/pointer.zig)"
    rm -rf .zig-cache zig-out
    zig build test > /tmp/t.out 2>&1; echo "exit=$?"
    grep -a -E "^FAIL|^error: [A-Z]" /tmp/t.out | head -3'
done
```

기대(확정 10에서 본 그대로).

| mutation | 기대 |
|---|---|
| 1 | `mounted: 1`, `exit=1`, `FAIL: Power Button classified as mouse, want none`, `error: WrongKind` |
| 4 | `mounted: 1`, `exit=1`, `FAIL: mouse_move 10 5: got .{ .dx = 10, .dy = -5, … }, want .{ .dx = 10, .dy = 5, … }`, `error: WrongFrame` |

`mounted:`가 0이면 사본이 안 덮인 것이다 — 멈추고 보고한다.

### 7-2. 체인 넷

mutation 1 · 4는 `pointer_test`를 건너뛴 사본 체인으로, 2 · 3은 그대로의 체인으로 돌린다. `-e m=$m`으로 번호를
컨테이너에 넘긴다 — 작은따옴표 안의 `$m`은 컨테이너에서 빈 값이 된다(PE-M1 실측 5).

```bash
M=/tmp/run/pdm0/impl/mut
run_mut() {  # 번호, 덮을 -v 인자들
  local m="$1"; shift
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm0:/tmp/run/pdm0 "$@" -e m="$m" \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: pointer=$(grep -c -E "EV_KEY\) or bitSet|dy -\|= value" terminal/src/pointer.zig) main=$(grep -c -E "uevent_fd < 0\) drainUevents|gone and pfd.fd < 0" terminal/src/main.zig) notest=$(grep -c "^if false; then" pointer/check.sh)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash pointer/check.sh > /tmp/run/pdm0/impl/mut/m$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -a -n '^===|^FAIL' $M/m$m.log | tail -3
}
run_mut 1 -v $M/pointer_m1.zig:/workspace/terminal/src/pointer.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 4 -v $M/pointer_m4.zig:/workspace/terminal/src/pointer.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 2 -v $M/main_m2.zig:/workspace/terminal/src/main.zig:ro
run_mut 3 -v $M/main_m3.zig:/workspace/terminal/src/main.zig:ro
```

함수 정의가 zsh에서 문제가 되면 `bash -c '…'`로 감싸 친다.

기대(확정 10에서 본 그대로).

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 `EV_KEY`만 보고 마우스 | `pointer=1 main=0 notest=1` | 검사 1의 "정확히 하나". 전원 버튼 · 키보드 · 마우스 셋이 열린다 | `FAIL: expected exactly one 'pointer> open' at boot, got 3` |
| 2 uevent를 안 읽는다 | `pointer=0 main=1 notest=0` | 검사 6. 커널은 둘째 마우스를 만들었는데 terminal이 안 연다. 소켓이 읽히지 않은 채 남아 poll이 매 바퀴 돌아온다 | `FAIL: the kernel registered a second mouse but terminal never opened it (no second 'pointer> open')` |
| 3 빠진 장치를 안 닫는다 | `pointer=0 main=1 notest=0` | 검사 6의 `close` 기다림(15초). 그 앞의 `plugged:`와 새 마우스의 움직임은 초록이다 | `FAIL: the unplugged mouse was never closed (no 'pointer> close /dev/input/event3')` |
| 4 `REL_Y` 부호 | `pointer=1 main=0 notest=1` | 검사 2. 검사 1은 초록이다 | `FAIL: after 'mouse_move 10 5' the last at line is 'terminal: pointer> at x=650 y=395 buttons=0 wheel=0 shown=0 ink=0', expected 'at x=650 y=405 buttons=0 wheel=0 shown=0 ink=0' (start 640,400)` |

mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다
(`project_zig_out_staleness` — 캐시 삭제가 같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 7-3. 되돌린다

mutation 체인은 저장소의 `terminal/zig-out`과 `kernel/initrd.cpio`(둘 다 gitignore 대상)에 망가진 판을 남긴다.
캐시를 컨테이너 안에서 지우고, 체인의 terminal 빌드와 initrd를 고친 소스로 다시 만든다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "exit=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  (cd kernel && ./make_initrd.sh > /tmp/i.out 2>&1); echo "initrd exit=$?"'
git status --short
```

기대: `exit=0`, `53`, `initrd exit=0`. `git status`는 `M` 셋(`check.sh` · `terminal/build.zig` ·
`terminal/src/main.zig`)과 `??` 넷(`pointer/` · `terminal/src/pointer.zig` · `terminal/src/pointer_test.zig` ·
이 plan, plan이 이미 commit됐으면 셋)뿐이다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트
파일) 그 목록을 보고한다.

### 7-4. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체), 새 파일 셋의 `wc -l`.
- Task 0의 출력 넷.
- Task 1의 출력 둘.
- Task 3-3 · 4-8 · 5-3의 확인 출력(`--stat` · `rg '^-'` · OK 줄 수 · `SAME` 넷과 하나 · `ENTRY-OK`).
- Task 6의 `exit=` · `real` · `rg` 출력 셋.
- Task 7의 `diff` 다섯 · 넷의 `mounted:` · `exit=` · `real` · `FAIL` 줄, 7-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task R: 개정 — 작업 트리의 inotify 판을 uevent 판으로(2026-10-05)

처음 판(inotify)을 이미 넣은 작업 트리에 개정을 적용하는 Task다. 처음부터 개정 판으로 구현하는 사람은 Task 2~5를
그대로 하면 되고 이 Task는 건너뛴다. "바꾸기 전"은 지금 작업 트리의 글자다(HEAD가 아니다). 구현자가 한다.

### R-0. 기준을 확인한다

```bash
git status --short
rg -n 'CONFIG_INOTIFY_USER' kernel/.config
for f in main.zig pointer.zig pointer_test.zig; do cmp -s terminal/src/$f /tmp/run/pdm0/v1/src/$f && echo "v1 $f"; done
cmp -s pointer/check.sh /tmp/run/pdm0/v1/check.sh && echo "v1 check.sh"
```

기대: `M check.sh` · `M terminal/build.zig` · `M terminal/src/main.zig`와 `??` 넷(이 plan · `pointer/` · `pointer.zig` ·
`pointer_test.zig`), `3029:# CONFIG_INOTIFY_USER is not set`(lead가 이미 되돌렸다), `v1` 넷. `v1`이 하나라도 안 나오면
작업 트리가 처음 판과 다르다 — 그 `diff`를 보고하고 멈춘다. `terminal/build.zig` · `check.sh`는 개정에서 안 바뀐다.

### R-1. `terminal/src/main.zig`

열두 쌍이다. 지우는 것은 `drainWatch` 함수 통째와 watch 블록이고, 나머지는 주석 · 이름 · 선언 한 줄씩이다.

바꾸기 전:

```zig
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
```

바꾼 뒤:

```zig
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

/// socket도 직접 선언한다. `std.c`에 있지만 공개가 아니다(PD-M0 plan 확정 4).
/// 부팅 뒤에 꽂힌 포인터 장치를 커널의 uevent netlink 소켓으로 안다.
extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;
```

바꾸기 전:

```zig
/// 포인터 장치를 찾는 디렉터리. inotify가 이것 하나를 본다(design 결정 1).
```

바꾼 뒤:

```zig
/// 포인터 장치를 찾는 디렉터리. 처음 훑기가 이것을 읽는다(design 결정 1).
```

바꾸기 전:

```zig
/// 장치 칸 하나. 경로를 드는 이유는 둘이다 — 처음 훑기와 `IN_CREATE`가
/// 겹쳐 같은 경로가 두 번 오면 건너뛰려고, 그리고 `close` 줄에 찍으려고.
```

바꾼 뒤:

```zig
/// 장치 칸 하나. 경로를 드는 이유는 둘이다 — 처음 훑기와 uevent가 겹쳐
/// 같은 경로가 두 번 오면 건너뛰려고, 그리고 `close` 줄에 찍으려고.
```

바꾸기 전:

```zig
/// 처음 훑기와 `IN_CREATE`가 이 함수 하나를 지난다.
```

바꾼 뒤:

```zig
/// 처음 훑기와 uevent의 `add`가 이 함수 하나를 지난다.
```

바꾸기 전:

```zig
/// 부팅 때 이미 있던 장치를 훑는다. watch를 건 뒤에 부른다 — 반대면 훑은 뒤
/// watch를 걸기 전에 생긴 장치를 놓친다(design 결정 1). 실패해도 terminal은
```

바꾼 뒤:

```zig
/// 부팅 때 이미 있던 장치를 훑는다. uevent 소켓을 연 뒤에 부른다 — 반대면
/// 훑은 뒤 소켓을 열기 전에 생긴 장치를 놓친다(design 결정 1). 실패해도 terminal은
```

바꾸기 전:

```zig
/// inotify fd에 쌓인 것을 다 읽는다. 부팅 뒤에 꽂힌 장치가 여기로 온다.
///
/// `IN_DELETE`는 안 본다. 빠진 장치는 그 fd의 `POLLERR` · `POLLHUP` ·
/// `ENODEV`로 안다(design 결정 1). 큐가 넘쳤으면(`IN_Q_OVERFLOW`) 놓친 것이
/// 있을 수 있으므로 디렉터리를 다시 훑는다 — 이미 연 경로는 건너뛴다.
fn drainWatch(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    const Event = std.os.linux.inotify_event;
    const IN = std.os.linux.IN;
    var buf: [4096]u8 align(@alignOf(Event)) = undefined;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n <= 0) return; // EAGAIN — 다 읽었다
        const len: usize = @intCast(n);
        var off: usize = 0;
        while (off + @sizeOf(Event) <= len) {
            const ev: *const Event = @ptrCast(@alignCast(&buf[off]));
            off += @sizeOf(Event) + ev.len;
            if (ev.mask & IN.Q_OVERFLOW != 0) {
                scanPointers(io, devs);
                continue;
            }
            if (ev.mask & IN.CREATE == 0) continue;
            const name = ev.getName() orelse continue;
            if (std.mem.startsWith(u8, name, "event")) tryOpenPointer(devs, name);
        }
    }
}
```

바꾼 뒤:

```zig
/// uevent 소켓에 쌓인 것을 다 읽는다. 부팅 뒤에 꽂힌 장치가 여기로 온다.
///
/// datagram 하나가 uevent 하나다. 무엇을 열지는 `pointer.ueventAddedNode`가
/// 가른다(`ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/eventN`).
/// devtmpfs는 노드를 만든 뒤에 uevent를 보내므로 그때 노드가 이미 있다
/// (PD-M0 plan 확정 7).
///
/// `remove`는 안 본다. 빠진 장치는 그 fd의 `POLLERR` · `POLLHUP` · `ENODEV`로
/// 안다(design 결정 1). read가 `ENOBUFS`면 소켓 버퍼가 넘쳐 커널이 메시지를
/// 버린 것이다 — 놓친 장치가 있을 수 있으므로 디렉터리를 다시 훑는다. 이미
/// 연 경로는 건너뛴다.
fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    // 커널 uevent 하나는 `UEVENT_BUFFER_SIZE`(2048바이트) 안이다.
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
            scanPointers(io, devs);
            continue;
        }
        if (n == 0) return;
        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
        tryOpenPointer(devs, name);
    }
}
```

바꾸기 전:

```zig
    // watch를 먼저 걸고 그다음에 훑는다. inotify가 실패해도 terminal은 산다 —
    // 부팅 때 있던 장치만 쓰고 핫플러그를 잃는다. 그때 `watch_fd`는 -1이고
    // poll은 음수 fd를 건너뛴다.
    var pointer_devs: [pointer.MAX_DEVICES]?PointerDev = @splat(null);
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
    const watch_fd: c_int = watch: {
        const IN = std.os.linux.IN;
        const fd = std.c.inotify_init1(IN.NONBLOCK | IN.CLOEXEC);
        if (fd < 0) {
            std.debug.print("terminal: pointer> watch failed error={s}\n", .{@tagName(std.c.errno(fd))});
            break :watch -1;
        }
        const wd = std.c.inotify_add_watch(fd, POINTER_DIR, IN.CREATE);
        if (wd < 0) {
            std.debug.print("terminal: pointer> watch failed error={s}\n", .{@tagName(std.c.errno(wd))});
            _ = std.c.close(fd);
            break :watch -1;
        }
        break :watch fd;
    };
```

바꾼 뒤:

```zig
    // 부팅 뒤의 장치는 커널의 uevent로 안다. udev가 듣는 것과 같은 netlink
    // 소켓이고 커널 config가 더 필요 없다 — inotify를 켜면 initramfs 풀기가
    // 느려진다(PD-M0 plan 확정 7). 소켓을 먼저 열고 그다음에 훑는다.
    //
    // 소켓이 실패해도 terminal은 산다 — 부팅 때 있던 장치만 쓰고 핫플러그를
    // 잃는다. 그때 `uevent_fd`는 -1이고 poll은 음수 fd를 건너뛴다.
    var pointer_devs: [pointer.MAX_DEVICES]?PointerDev = @splat(null);
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
    const uevent_fd: c_int = uevent: {
        const linux = std.os.linux;
        const fd = socket(linux.AF.NETLINK, linux.SOCK.DGRAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, linux.NETLINK.KOBJECT_UEVENT);
        if (fd < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(fd))});
            break :uevent -1;
        }
        // 그룹 1이 커널이 보내는 uevent다(그룹 2는 udevd가 다시 보내는 것). pid
        // 0은 소켓의 주소를 커널이 고르게 한다.
        const addr: linux.sockaddr.nl = .{ .pid = 0, .groups = 1 };
        const rc = std.c.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.nl));
        if (rc < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(rc))});
            _ = std.c.close(fd);
            break :uevent -1;
        }
        break :uevent fd;
    };
```

바꾸기 전:

```zig
    // poll이 보는 fd. 키보드 하나, inotify 하나(PD-M0), 열린 포인터 장치,
```

바꾼 뒤:

```zig
    // poll이 보는 fd. 키보드 하나, uevent 소켓 하나(PD-M0), 열린 포인터 장치,
```

바꾸기 전:

```zig
    // 자리는 `[0]` 키보드 · `[1]` inotify · `[2..pty_base]` 포인터 장치 ·
```

바꾼 뒤:

```zig
    // 자리는 `[0]` 키보드 · `[1]` uevent 소켓 · `[2..pty_base]` 포인터 장치 ·
```

바꾸기 전:

```zig
        fds[1] = .{ .fd = watch_fd, .events = c.POLLIN, .revents = 0 };
```

바꾼 뒤:

```zig
        fds[1] = .{ .fd = uevent_fd, .events = c.POLLIN, .revents = 0 };
```

바꾸기 전:

```zig
        // 빠진 장치를 inotify보다 먼저 닫는다. 빠진 번호가 곧바로 다시 쓰이면
```

바꾼 뒤:

```zig
        // 빠진 장치를 uevent보다 먼저 닫는다. 빠진 번호가 곧바로 다시 쓰이면
```

바꾸기 전:

```zig
        if (fds[1].revents & c.POLLIN != 0) drainWatch(watch_fd, init.io, &pointer_devs);
```

바꾼 뒤:

```zig
        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
```

### R-2. `terminal/src/pointer.zig`

`ueventAddedNode`를 `eviocgabs` 뒤 · `Buttons` 앞에 넣는다. 지우는 줄은 없다.

바꾸기 전:

```zig
/// 버튼 셋. 비트 순서가 QEMU HMP `mouse_button`의 비트(1 왼쪽 · 2 오른쪽 ·
```

바꾼 뒤:

```zig
/// 커널 uevent 하나에서 새로 생긴 evdev 노드의 이름(`event3`)을 꺼낸다.
/// 아니면 null이다.
///
/// uevent는 NUL로 나뉜 필드들이다 — 머리 `add@/devices/…/event3` 뒤에
/// `ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/event3` 같은 `KEY=value`가
/// 온다(PD-M0 plan 확정 7에서 본 글자). 셋이 다 맞는 것만 고른다. 같은 장치가
/// `input/inputN`(노드 없음) · `hidraw` · `usb` uevent도 함께 내고, `mouseN`은
/// `INPUT_MOUSEDEV`가 꺼져 있어 안 온다. 머리는 `=`가 없어 어느 조건에도 안
/// 걸린다.
///
/// 돌려주는 조각은 `msg` 안을 가리킨다. 부르는 쪽이 경로로 복사한다.
pub fn ueventAddedNode(msg: []const u8) ?[]const u8 {
    var added = false;
    var input = false;
    var node: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, msg, 0);
    while (it.next()) |field| {
        if (std.mem.eql(u8, field, "ACTION=add")) {
            added = true;
        } else if (std.mem.eql(u8, field, "SUBSYSTEM=input")) {
            input = true;
        } else if (std.mem.startsWith(u8, field, "DEVNAME=input/event")) {
            node = field["DEVNAME=input/".len..];
        }
    }
    if (!added or !input) return null;
    return node;
}

/// 버튼 셋. 비트 순서가 QEMU HMP `mouse_button`의 비트(1 왼쪽 · 2 오른쪽 ·
```

### R-3. `terminal/src/pointer_test.zig`

검사 11을 마지막 `all checks passed` 앞에 넣는다. 지우는 줄은 없다.

바꾸기 전:

```zig
    std.debug.print("pointer_test: all checks passed\n", .{});
```

바꾼 뒤:

```zig
    // ── 검사 11: uevent에서 새 evdev 노드만 고른다 ─────────────────────────
    //
    // 앞의 넷은 2026-10-05 `pointer` 체인의 `device_add` · `device_del`이 낸
    // uevent 그대로다(PD-M0 plan 확정 7, NUL이 필드 사이와 끝에 있다). 뒤의
    // 둘은 같은 모양으로 만든 것이다 — 노드 없는 `inputN`의 `add`와, 이
    // 커널에서는 안 오는 `mouseN`.
    {
        const add_event3 = "add@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=add\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=686\x00";
        const remove_event3 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=690\x00";
        const remove_input4 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00SUBSYSTEM=input\x00PRODUCT=3/627/1/1\x00NAME=\"QEMU QEMU USB Mouse\"\x00PROP=0\x00EV=17\x00KEY=1f0000 0 0 0 0\x00REL=903\x00MSC=10\x00SEQNUM=691\x00";
        const bind_usb = "bind@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00ACTION=bind\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00SUBSYSTEM=usb\x00MAJOR=189\x00MINOR=3\x00DEVNAME=bus/usb/001/004\x00DEVTYPE=usb_device\x00DRIVER=usb\x00SEQNUM=689\x00";
        const add_input4 = "add@/devices/virtual/input/input4\x00ACTION=add\x00SUBSYSTEM=input\x00NAME=\"QEMU QEMU USB Mouse\"\x00SEQNUM=685\x00";
        const add_mouse0 = "add@/devices/virtual/input/input4/mouse0\x00ACTION=add\x00SUBSYSTEM=input\x00DEVNAME=input/mouse0\x00SEQNUM=687\x00";
        const got = pointer.ueventAddedNode(add_event3);
        try expectTrue("uevent add of input/event3 names event3", got != null and std.mem.eql(u8, got.?, "event3"));
        try expectTrue("uevent remove of the same node is ignored", pointer.ueventAddedNode(remove_event3) == null);
        try expectTrue("uevent remove of inputN (no node) is ignored", pointer.ueventAddedNode(remove_input4) == null);
        try expectTrue("uevent of a usb device node is ignored", pointer.ueventAddedNode(bind_usb) == null);
        try expectTrue("uevent add of inputN (no DEVNAME) is ignored", pointer.ueventAddedNode(add_input4) == null);
        try expectTrue("uevent add of input/mouse0 is ignored", pointer.ueventAddedNode(add_mouse0) == null);
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
```

### R-4. `pointer/check.sh`

주석 넷과 실패 표지 하나다. 판정 줄은 안 바뀐다.

바꾸기 전:

```bash
#   → terminal이 /dev/input에 inotify를 걸고 디렉터리를 훑는다
```

바꾼 뒤:

```bash
#   → terminal이 uevent netlink 소켓을 열고 /dev/input을 훑는다
```

바꾸기 전:

```bash
#   → 부팅 뒤에 device_add로 꽂은 둘째 마우스를 IN_CREATE가 알리고 terminal이 연다
```

바꾼 뒤:

```bash
#   → 부팅 뒤에 device_add로 꽂은 둘째 마우스를 커널 uevent가 알리고 terminal이 연다
```

바꾸기 전:

```bash
    "terminal: pointer> watch failed" \
```

바꾼 뒤:

```bash
    "terminal: pointer> uevent failed" \
```

바꾸기 전:

```bash
# 생겨도 IN_CREATE가 연다. 어느 쪽이든 같은 줄이다.
```

바꾼 뒤:

```bash
# 생겨도 uevent가 연다. 어느 쪽이든 같은 줄이다.
```

바꾸기 전:

```bash
# 꽂으면 IN_CREATE가 오고 terminal이 둘째 open을 찍는다. IN_CREATE를 안 보면
# 여기서 멈춘다(mutation 2). 커널 줄을 함께 세는 것은 "QEMU · 커널이 마우스를
```

바꾼 뒤:

```bash
# 꽂으면 커널 uevent(`add` · `DEVNAME=input/event3`)가 오고 terminal이 둘째
# open을 찍는다. uevent를 안 읽으면 여기서 멈춘다(mutation 2). 커널 줄을 함께
# 세는 것은 "QEMU · 커널이 마우스를
```

### R-5. 확인

```bash
git diff --stat
for f in src/pointer.zig src/pointer_test.zig src/main.zig build.zig; do
  echo "== $f"; diff terminal/$f /tmp/run/pdm0/term/$f && echo SAME
done
diff pointer/check.sh /tmp/run/pdm0/pointer/check.sh && echo SAME
rg -n 'inotify|IN_CREATE|drainWatch|watch_fd' terminal/src/main.zig terminal/src/pointer.zig pointer/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  rm -rf .zig-cache zig-out
  zig build > /tmp/b.out 2>&1; echo "build exit=$?"
  zig build test > /tmp/t.out 2>&1; echo "test exit=$?"; grep -a -c "^pointer_test: .* OK$" /tmp/t.out'
```

기대: `--stat`은 `check.sh | 6` · `terminal/build.zig | 17` · `terminal/src/main.zig | 278`(+268/−10)이고, 새 파일은
`--stat`에 안 나온다. `SAME` 다섯. `rg`는 한 줄 — 4-4의 주석 `… inotify를 켜면 initramfs 풀기가`. 컨테이너는
`build exit=0` · `test exit=0` · `53`.

### R-6. 체인과 mutation을 다시 돈다

Task 6(체인 한 번과 regression 둘)과 Task 7(mutation 넷)을 그대로 다시 한다. Task 7의 mutation 2는 이제 "uevent를
안 읽는다"이고 사본의 대상 줄 번호가 바뀌었다(7-0). 그리고 처음 판을 빨갛게 한 `install` 체인을 한 번 돈다(약 2분 45초).

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm0:/tmp/run/pdm0 -w /workspace tars-devcontainer bash -c '
    bash install/check.sh > /tmp/run/pdm0/impl/install.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^=== boot 7|late USB disk|^PASS|^FAIL' /tmp/run/pdm0/impl/install.log
```

기대: `exit=0`, `=== boot 7: the installed disk over USB, three seconds late ===` 뒤에 `init waited …ms for the late USB disk
and mounted its p2`, 마지막 줄 `PASS`. 확정 10에서는 900ms였다 — 수는 회차마다 다르다.

보고는 7-4의 목록에 R-0 · R-5 · R-6의 출력을 더한다.

## Task 8: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고(`git diff`, 새 파일 셋은 `Read`), Task 6의 로그를 대조한다.
2. 루트 게이트. 열아홉 체인 × 3이다. GE-M1 · PE의 열여덟 체인이 약 1시간 5~7분이고, `pointer` 체인이 한 판에 약
   1분을 더한다(따뜻한 캐시 기준 — 루트 게이트는 `clean()` 뒤 첫 체인만 빌드를 치른다). 커널은 HEAD 그대로지만
   `clean()`이 `kernel/build`를 지우므로 첫 체인이 커널 전체 빌드를 치르는 것은 늘 같다. 합해 약 1시간 10분이다. Bash
   도구의 10분 상한을 넘으므로 `run_in_background`로 돌리고 `{ time …; }`로 감싼다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pd0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pd0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 3/3' /tmp/gate_pd0.log`가 19여야 하고, `PD-M0 check PASS`가 셋이어야 한다. 처음 판을 빨갛게 한
   `install`(DC-M2)이 3/3인 것이 확정 7의 답이다.
3. 실측 절 채우기. 구현자의 보고와 루트 게이트의 시간 · 결과를 아래 "PD-M0이 실측한 것"에 적는다.
4. commit. 넣는 것은 `terminal/src/pointer.zig` · `terminal/src/pointer_test.zig` · `terminal/build.zig` ·
   `terminal/src/main.zig` · `pointer/check.sh` · `check.sh` · 이 plan이다. `kernel/.config`는 안 들어간다(`git diff
   --stat kernel/.config`가 0줄인지 commit 전에 본다). `git add`는 이 일곱
   경로를 하나씩 지정한다(CLAUDE.md "Commit 전 git status 확인") — `out/pd/*.ppm`은 `out/`가 gitignore라 안 들어가지만
   경로를 좁혀 둔다.
5. `kernel/.config`의 되접기(확정 7). PD와 무관한 기존 drift 아홉 줄을 따로 되접을지 정한다. PD-M0의 일은
   아니다 — 되접는다면 HD-M1처럼 별도 commit이 맞다(`project_kernel_config`).
6. design에 한 줄씩 덧붙일 것(닫을 때 몫이지만 지금 적어 둘 수 있다). 결정 1의 "ioctl 넷을 같은 모양으로 짓는다"가
   번역된 매크로로 바뀐 것(확정 4), 결정 1의 inotify가 커널 한 줄을 요구했고 그 한 줄이 `install` 체인을 빨갛게 해 netlink uevent로 바뀐 것(확정 7), 위험 8이 실측으로 풀린 것
   (확정 1).

## design과 다르게 적은 것

1. ioctl 번호를 손으로 짓지 않는다(design 결정 1 · 실측 15). translate-c 패키지가 `EVIOCGBIT` 등을 함수로 넘겨주므로
   그것을 부르고, `pointer_test` 검사 5가 C 헤더의 값과 대조한다(확정 4).
2. 핫플러그 알림이 inotify가 아니라 netlink uevent다(design 결정 1). inotify는 게스트 커널에서 꺼져 있고, 켜면
   `FSNOTIFY`가 initramfs 풀기를 1.2초 늦춰 `install` 체인이 빨개졌다(확정 7). uevent는 커널 config 없이 되므로 design의
   "커널은 PD-M3에서만 바꾼다"는 그대로 지켜진다. 결정 1의 순서(먼저 알림 통로를 열고 그다음 훑는다) · 중복 경로
   건너뛰기 · 빠진 장치는 fd로 안다는 그대로다.
3. 로그 줄. `name=`이 맨 끝으로 갔고 `skip` 줄에도 붙는다. 실패 줄 넷을 더했다(확정 8).
4. 검사 7을 검사 6보다 먼저 판정하고, design보다 강하게 본다 — `ink=0`과 `pane>` 글자에 더해 `screen>` 줄 수와
   screendump 둘의 바이트 비교. PD-M0이 "화면 변화 0"이라는 것을 픽셀로 본다.
5. 검사 6에 움직임 둘을 더했다. 꽂은 뒤의 움직임(새 fd를 읽는가)과 뺀 뒤의 움직임(원래 fd가 살아 있는가). 확정 1의
   HMP 대상 이동이 그것을 가능하게 한다. design 위험 8의 대안(검사 6을 맨 끝으로)은 필요 없다.
6. PD-M0은 마우스만 연다. `classify`는 `touchpad`를 내지만 `main.zig`가 `skip`한다 — 디코더가 없는 장치를 열어
   두지 않는다. PD-M3이 그 갈래를 잇는다.
7. design에 없던 것 넷. `Pointer.forget`(누른 채 뽑힌 장치의 버튼을 놓는다), uevent 소켓이 `ENOBUFS`면 다시 훑기,
   `drainPointer`의 read 열여섯 번 상한, `Events`의 모양(`pressed` · `released` · `moved` · `wheel`). 이름은 design이
   "plan이 확정한다"로 남긴 것이다.

## 이 milestone에서 안 하는 것

- 화살표 그리기 · save-under · 보이는 조건 · 휠 스크롤 · `layout.Tree.hit`(PD-M1).
- 누름 · 끎 · 뗌의 의도 · `Gesture` · `copyEnterAt` · `pointerMode`(PD-M2). 지금 버튼은 `at` 줄에만 나온다.
- 터치패드 디코더 · `EVIOCGABS` 호출 · 터치패드 커널 config · uinput 되감기 도구 · 부팅 B(PD-M3).
- `input_test`의 "키보드 fd로 온 `BTN_LEFT`가 아무것도 안 만든다"(design 결정 2) — 그 검사는 키보드와 마우스를 한
  노드로 내는 장치의 일이고 PD-M0의 배관과 무관하다. PD-M2가 `input.zig`를 만질 때 함께 넣는다.
- 키보드 핫플러그(비목표 9). uevent 소켓은 이제 있지만 키보드는 `argv[4]` 그대로다.
- 커널 config의 어떤 변경도(확정 7). 기존 drift의 되접기도 이 milestone의 일이 아니다(Task 8-5).
- `docs/guides/lessons.md` · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design `Status:`(design "닫을 때").

## PD-M0이 실측한 것

구현은 Opus 서브에이전트가 2026-10-05에 plan 그대로 했다. plan의 코드 블록을 줄 범위로 그대로 뽑아 넣었고(`main.zig`
여덟 치환은 정확 일치 치환), 확정 10의 사본과 넷 다 `SAME`이었다. plan 코드를 고친 곳은 없다. lead가 파일 · diff ·
로그를 대조했다 — `git diff | rg '^-'`는 Task 4-8이 기대한 열 줄과 `kernel/.config` 한 줄이 전부였다.

1. 커널 증분 빌드 1분 41초. `build/.config`에 `CONFIG_INOTIFY_USER=y` · `CONFIG_FSNOTIFY=y`, bzImage 7,447,552바이트
   (확정 7과 같다).
2. 호스트 검사. `pointer_test` OK 47, `zig build test` exit 0, `init` 검사 PASS 5.
3. `pointer` 체인 21.8초(캐시 전부 따뜻). 열일곱 줄이 Task 6-1의 기대와 글자까지 같았다. `pointer>` 줄은 `open event2` ·
   `skip event1`(AT 키보드) · `skip event0`(Power Button) · `open event3`(핫플러그) · `close event3`.
4. 회귀 — `pane` 33.2초 PASS · `render` 1분 50.6초 PASS. 두 체인의 부팅에는 포인터 장치가 없고 `pointer>` 줄이 0이다.
5. mutation 넷 전부 빨감.

   | mutation | 잡은 자리 | 문구 | 시간 |
   |---|---|---|---|
   | 1 `classify`가 `EV_KEY`만 본다 | `pointer_test` 먼저(`Power Button classified as mouse, want none`), 건너뛰면 검사 1 | `expected exactly one 'pointer> open' at boot, got 3` | 1분 17초 |
   | 2 `IN_CREATE`를 안 본다 | 검사 6 | `the kernel registered a second mouse but terminal never opened it` | 1분 39초 |
   | 3 `POLLHUP`에 닫지 않는다 | 검사 6 | `the unplugged mouse was never closed (no 'pointer> close /dev/input/event3')` | 1분 39초 |
   | 4 `REL_Y` 부호 반전 | `pointer_test` 먼저(`got … .dy = -5`), 건너뛰면 검사 2 | `the last at line is '… x=650 y=395 …', expected 'at x=650 y=405 …'` | 1분 34초 |

6. plan의 기대와 다른 것은 글자 수와 출력 모양뿐이었다. Task 6-1 둘째 `rg`는 앵커가 없어 체인의 `plugged:` ·
   `unplugged:` 줄까지 잡아 일곱 줄(기대 다섯) · 첫 `rg`의 기대 블록은 열아홉 줄이 아니라 열일곱 줄이고 실제도 열일곱 ·
   mutation의 `tail -5`가 bash의 `time` 네 줄에 `mounted:` 줄을 잘라 따로 확인 · 회귀 로그의 마지막 줄은 PASS가 아니라
   QEMU의 `terminating on signal 15` · 이 기계의 `ls`는 eza라 권한은 `/bin/ls`로 봤다.
7. 루트 게이트 1회차(51분 28초)는 열두 체인이 3/3을 지난 뒤 열세번째 `install`의 부팅 7에서 빨갰다 —
   `init did not have to wait for the late USB disk, or never found it`. 부팅 7은 `usb-storage.delay_use=3`으로 디스크를
   3초 늦게 보이게 해 init의 기다림을 보는데, 이 회차에는 init이 처음 훑기 전에 디스크가 이미 있었다(셸이 다른 회차의
   8~9초가 아니라 5초에 떴다). 게이트가 도는 동안 PD-M1 planner가 저장소 밖 사본에서 `zig build test`를 돌려 호스트
   부하가 겹쳤다. 이 체인은 DRI가 없어 `terminal`이 `error: OpenFailed`로 세 번 죽고 init이 포기하는 체인이라(1회차
   이전 게이트들과 같은 모양) PD-M0 코드가 닿는 자리가 없다. 부하 없이 다시 돌렸다 — 아래 8.
8. 루트 게이트 2회차(51분 25초, 부하 없음)도 같은 자리에서 같은 문구로 빨갰다. 7의 부하 가설이 틀렸다. `install`
   체인만 따로 돌려(`rm -rf "$WORK"`를 뺀 사본을 덮어 시리얼 로그를 남겼다) 재현이 결정적임을 보고, `kernel/.config`를
   HEAD 것으로 되돌려 증분 빌드한 뒤 한 번 더 돌리니 PASS였다. 보존한 부팅 7 로그의 커널 시각이 원인을 말한다.

   | 커널 | `Unpacking initramfs` | `Run /init` | 풀기 | 디스크 `sda` | 결과 |
   |---|---|---|---|---|---|
   | HEAD(`INOTIFY_USER` 꺼짐) | 0.46초 | 3.07초 | 2.6초 | 4.24초 | `config storage appeared after 1100ms`, PASS |
   | PD-M0(`INOTIFY_USER=y`, `FSNOTIFY=y`) | 0.45초 | 4.25초 | 3.8초 | 4.21초 | init이 디스크 뒤에 도착, 기다림 없음, FAIL |

   `INOTIFY_USER`가 select로 켠 `FSNOTIFY`가 initramfs의 파일마다 훅을 더해 TCG에서 풀기를 1.2초 늦춘다. 그만큼
   모든 체인의 모든 부팅이 늦어지고, `install` 부팅 7은 DC-M1 때 1.6~1.7초였던 여유(WL이 firmware 96MB를 더한 뒤
   1.1초)가 음수가 된다. 이 체인에는 PD-M0 코드가 닿는 자리가 없다 — 커널 한 줄이 전부였다.

   lead의 결정(2026-10-05): inotify를 버린다. 핫플러그 알림은 커널 config 없이 되는 netlink uevent
   (`NETLINK_KOBJECT_UEVENT`)로 받고, PD-M0은 커널을 한 줄도 바꾸지 않는다(design의 원래 뜻). plan의 Task 1과
   watch 부분을 planner가 고쳐 쓰고 구현자가 반영한 뒤 루트 게이트를 다시 돈다 — 아래 9.
9. netlink 판(Task R)을 같은 구현자가 작업 트리에 적용했다 — "바꾸기 전 / 바꾼 뒤" 열아홉 쌍을 정확 치환, 사본과 `SAME`
   다섯, `pointer_test` OK 53, `kernel/.config`는 HEAD 그대로(diff 0줄). v1 판에서 지운 것은 `main.zig` 46줄(`drainWatch`와
   watch 블록)과 `pointer/check.sh` 6줄이다.

   | 실행 | 결과 | 시간 |
   |---|---|---|
   | `pointer` 체인 | PD-M0 check PASS, 열일곱 줄 글자 같음 | 21.5초 |
   | `pane` · `render` | PASS · PASS | 32.4초 · 1분 49초 |
   | `install` 체인 | PASS, 부팅 7 `init waited 800ms for the late USB disk` | 1분 49초 |
   | mutation 1 · 2(uevent를 안 읽는다) · 3 · 4 | 전부 빨감, 문구는 5의 표와 같다 | 1분 15초 · 1분 38초 · 1분 40초 · 1분 35초 |

   덤으로 둘. 캐시를 지운 `zig build`가 OrbStack VM(4GB)에서 다른 컨테이너(PD-M1 planner의 QEMU · 빌드)와 겹치자 두 번
   `Killed`(exit 137)였고 VM이 한 번 재시작됐다 — cold `zig build`가 3GB 안팎을 쓴다. 그 뒤로 docker 작업은 한 번에
   하나만 돌렸다(lessons에 남길 것). `-j4`로는 겹쳐도 지나갔다.
10. 루트 게이트 3회차(netlink 판, docker 작업 없이 단독): 열아홉 체인 3/3, `PD-M0 check PASS` 셋, `FAIL` 0줄,
    1시간 8분 39초(2026-10-05). 1 · 2회차의 51분은 열세번째 체인에서 멈춘 시간이라 비교값이 아니다 — 열여덟 체인이던
    PE-M1의 1시간 7분 14초에 `pointer` 체인이 한 판 20여 초씩을 더한 것이 이 수다. `install` 부팅 7은 세 회차 다 지났다.

## 닫을 때

PD-M0은 서브프로젝트를 닫지 않는다. 다음은 PD-M1 plan이다(design 결정 4 · 7, Sonnet 구현).
