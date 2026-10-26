# LI-M0 — 패닉 trace와 크기를 잰다

Date: 2026-10-26
Design: `docs/specs/2026-10-26-tars-lean-initrd-design.md` 결정 5 · 6
Status: 완료(2026-10-26, 코드 0줄이라 게이트 없음). design 결정 5의 갈림(A는 파일:줄, B는 `???`만)은 안 생겼다 — M1로 간다.

## 누가 무엇을 하나

저장소의 코드 · 스크립트는 0줄이다. 프로브 판은 사본에 만들고(`/tmp/li-m0/`), 컨테이너에 읽기 전용으로 마운트한다(RS의 방법,
`probe/run.sh`의 머리 주석). lead가 직접 돌린다. commit은 이 plan과 실측을 담은 하나다.

| Task | 무엇을 | 남는 것 |
|---|---|---|
| 1 | 다섯 바이너리의 크기, sysroot 바이너리의 `.debug_info` 유무 | 실측 1 · 2 |
| 2 | 판 A — 원본 그대로 패닉 | `out/li-m0/a.log` |
| 3 | 판 B — terminal 사본만 `--strip-debug`하고 패닉 | `out/li-m0/b.log` |
| 4 | B의 주소를 A 빌드의 원본에 `addr2line` | 실측 3 |
| 5 | 정상 빌드로 되돌리기, 실측 적기, commit | — |

## 착수 전에 확정한 것

1. 주입 자리는 `terminal/src/main.zig`의 `dumpScreen`이다. `line.flush()` 앞에서 그 줄에 셸 프롬프트(`~# `)가 있는지 보고, flush 뒤에
   `@panic("LI-M0 probe")`한다. 시리얼에 화면 줄이 이미 나온 뒤라 콘솔은 살아 있고(design 위험 2), trace는 `dumpScreen` ← `dumpFrame`
   쪽 ← `App.tick` ← `main`으로 여러 줄일 것이다. anchor `    line.print("\n", .{});\n    line.flush();\n}\n\n/// \`cols\``는 한 번만
   나온다. perl 한 줄로 바꾸고, 바뀐 횟수가 1이 아니면 멈춘다.
2. 우리 코드에 panic handler 재정의가 없다(`rg 'pub const panic|std_options' terminal/src init/src shared`가 config의 주석 하나뿐).
   그래서 출력은 std의 기본 handler — `panic: LI-M0 probe` 뒤의 trace — 다.
3. terminal이 죽으면 init이 다시 띄우므로 패닉이 되풀이된다. 첫 trace만 쓴다. 부팅 러너는 `LI-M0 probe`가 보인 뒤 5초를 더 기다려
   trace가 다 나오게 하고 QEMU를 끈다. 120초 안에 안 보이면 실패다.
4. 판 B는 판 A 빌드의 `zig-out/bin/terminal`을 `/tmp/li-m0/terminal.probe`로 복사해 두고, 그 사본을 strip한
   `/tmp/li-m0/terminal.sd`를 `terminal/zig-out/bin/terminal` 위에 읽기 전용으로 마운트해 `make_initrd.sh`만 다시 돈다. 원본은 안
   바뀐다. Task 4의 `addr2line`은 `terminal.probe`에 한다 — B의 `.text`는 A와 같은 바이트다(strip은 `.debug_*`만 뗀다).
5. 부팅 명령은 `probe/run.sh`의 QEMU 줄을 그대로 쓴다(포트만 45591, 게이트 범위 밖). `GUEST_MEM`은 `gate_lib.sh`에서 온다.
6. 판 A의 빌드는 `terminal/prepare.sh`(프로브 `main.zig`가 마운트돼 다시 컴파일된다). Task 5에서 마운트 없이 `prepare.sh`와
   `make_initrd.sh`를 다시 돌아 `zig-out`과 `kernel/initrd.cpio`를 정상 판으로 되돌린다.

## Task 1: 크기

컨테이너에서 `x86_64-linux-gnu-strip --strip-debug` 사본으로 다섯 바이너리(terminal · init · tars-install · tars-service · tars-config)의
원본 / strip-debug / gzip -6(`make_initrd.sh`의 수준) 크기를 잰다. `guest_tools.sh`의 `GUEST_TOOLS`를 source해 sysroot 쪽 원본마다
`readelf -S`에 `.debug_info`가 있는지 센다(design 결정 3의 "이미 strip돼 있을 것").

## Task 2 · 3: 판 A · B

`/tmp/li-m0/patch.sh`가 프로브 `main.zig`를, `/tmp/li-m0/boot.sh <label>`이 부팅 한 번을 맡는다. 로그는 `out/li-m0/<label>.log`.

## Task 4: 호스트에서 푼다

B의 trace 줄에서 `0x…`를 뽑아 `x86_64-linux-gnu-addr2line -f -i -C -e /tmp/li-m0/terminal.probe <주소…>`. A의 파일:줄과 나란히 놓는다.

## Task 5: 되돌리고 적는다

정상 빌드, 아래 "실측" 절, design의 결정 1 · 3 · 5 중 바뀔 것이 있으면 design도. design 결정 5의 갈림(A가 파일:줄을 내고 B가 `???`만
낸다)이면 M1 전에 사용자에게 묻는다.

## LI-M0이 실측한 것

### 실측 1 — 다섯 바이너리가 RAM에서 24.8MB, initrd(gzip)에서 6.3MB다

HEAD `c86d561`의 `zig-out`. gzip은 `make_initrd.sh`와 같은 `-6`.

| | 원본 | `--strip-debug` | gzip -6 원본 | gzip -6 strip-debug |
|---|---|---|---|---|
| terminal | 14,565,904 | 3,006,576 | 4,139,950 | 1,180,099 |
| init | 4,723,400 | 775,696 | 1,259,194 | 292,010 |
| tars-install | 3,611,240 | 542,632 | 1,004,802 | 219,854 |
| tars-service | 3,389,472 | 503,792 | 953,324 | 206,336 |
| tars-config | 3,956,328 | 627,128 | 1,102,563 | 252,403 |
| 합 | 30,246,344 | 5,455,824 | 8,459,833 | 2,150,702 |

HANDOFF의 "4.6MB"는 ZU가 terminal에 더한 몫이었고, 다섯 전부의 디버그 섹션은 그보다 크다. 판 A · B의 `initrd.cpio`(두 archive 합,
firmware 포함)는 99,263,297 → 96,307,487바이트 — terminal 하나만 strip해 2,955,810 줄었다(위 표의 terminal gzip 차 2,959,851과 4KB 안쪽).

### 실측 2 — sysroot 바이너리는 이미 strip돼 있다

`GUEST_TOOLS`의 원본 가운데 ELF 91개, `.debug_info`가 있는 것 0개. design 결정 3의 추측대로다.

### 실측 3 — 원본 판은 파일:줄을 낸다. strip-debug 판은 함수 이름을, 호스트 `addr2line`은 그 이상을 낸다

같은 프로브 빌드(`dumpScreen`의 `@panic`), 시리얼 `out/li-m0/{a,b}.log`의 첫 trace. 색 escape는 뺐다.

판 A(원본):

```
thread 39 panic: LI-M0 probe
/workspace/terminal/src/main.zig:731:19: 0x1190982 in dumpScreen (terminal)
/workspace/terminal/src/main.zig:4111:23: 0x112b42d in tick (terminal)
/workspace/terminal/src/main.zig:4119:24: 0x112dffc in main (terminal)
???:?:?: 0x7f15c4b4bca7 in ??? (/lib/x86_64-linux-gnu/libc.so.6)
???:?:?: 0x7f15c4b4bd64 in ??? (/lib/x86_64-linux-gnu/libc.so.6)
/usr/local/zig/lib/libc/glibc/sysdeps/x86_64/start-2.33.S:120: 0x1085c69 in ??? (…/start-2.33.S)
tars-init: terminal killed (pid 39, signal 6, lived 2s)
```

판 B(terminal 사본만 `--strip-debug`):

```
thread 39 panic: LI-M0 probe
???:?:?: 0x1190982 in main.App.dumpFrame (???)
???:?:?: 0x112b42d in main.App.tick (???)
???:?:?: 0x112dffc in start.main (???)
???:?:?: 0x7f45452bbca7 in ??? (/lib/x86_64-linux-gnu/libc.so.6)
???:?:?: 0x7f45452bbd64 in ??? (/lib/x86_64-linux-gnu/libc.so.6)
???:?:?: 0x1085c69 in _start (???)
```

B의 주소를 호스트에서(`x86_64-linux-gnu-addr2line -f -i -C -e <A 빌드의 원본> 0x1190982 0x112b42d 0x112dffc 0x1085c69`):

```
main.dumpScreen          main.zig:731
main.App.dumpFrame       main.zig:4040
main.App.tick            main.zig:4111
main.main                main.zig:4119
start.callMain           std/start.zig:827
start.callMainWithArgs   std/start.zig:729
start.main               std/start.zig:754
_start                   start-2.33.S:120
```

- TF-M4의 "심볼 판은 trace 자체가 없었다"는 0.17 · ReleaseSafe에서 재현되지 않는다(design 비목표 3은 이것으로 끝).
- 주소는 A · B가 같다(strip은 `.text`를 안 건드린다, unwind는 `.eh_frame`). non-PIE라 그대로 `addr2line`에 들어간다.
- B는 inline된 맨 안쪽 함수를 잃는다 — `dumpScreen`이 `dumpFrame` 안에 inline돼 symtab은 바깥 이름만 안다. 대신 이름이
  완전하다(`main.App.tick`, A는 `tick`).
- 호스트 `addr2line -i`는 A가 건너뛴 inline 사슬(`dumpFrame` 4040, `start.zig` 셋)까지 낸다. B + 원본 ⊇ A다.
- libc의 두 줄은 A에서도 `???`다(Debian `.so`는 strip돼 있다, 실측 2).
- panic은 SIGABRT(signal 6)이고 init이 1초 뒤 다시 띄워 같은 패닉을 되풀이한다 — 프로브가 의도한 것이다.

### 실측 4 — 컨테이너의 `strip`은 x86_64를 못 읽는다

컨테이너가 arm64라 `strip`은 `Unable to recognise the format of the input file`이다. `x86_64-linux-gnu-strip` ·
`x86_64-linux-gnu-addr2line` · `x86_64-linux-gnu-readelf`를 쓴다. 호스트의 `/tmp`는 컨테이너에 없으므로 프로브 파일은 `-v`로 따로
마운트한다(`-v /tmp/li-m0:/li`).
