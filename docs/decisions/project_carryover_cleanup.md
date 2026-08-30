# Carryover Cleanup (CC-M0, 2026-08-31)

`HANDOFF.md`의 이월 숙제 가운데 "미룬다"로 결정이 나지 않은 셋을 실제로
없앤 서브프로젝트다. design은
`docs/superpowers/specs/2026-08-31-tars-carryover-cleanup-design.md`,
plan은 `docs/superpowers/plans/2026-08-31-tars-carryover-cleanup-cc-m0.md`.

## 1. 게스트에게 직접 물으면 커널 config 결정이 끝난다

`ACPI_EC`는 HD-M1부터 "QEMU의 DSDT를 안 읽어 봤으니 남긴다"로 켜져 있었다.
**읽는 방법이 어려운 줄 알았는데 게스트가 이미 답을 갖고 있었다** —
`/sys/bus/acpi/devices/`에 ACPI 장치가 전부 들어 있고, 거기에
Embedded Controller의 HID인 `PNP0C09`가 없다.

**게스트에 명령을 넣는 길은 `-serial stdio`다.** 게이트 체인들이 쓰는 QEMU
monitor의 `sendkey`는 PS/2 키보드로 가므로 시리얼 콘솔의 fish에는 닿지
않는다. FIFO를 QEMU의 stdin에 물리고 거기에 글자를 흘려 넣는다.

```bash
mkfifo "$FIFO"
exec 4<>"$FIFO"          # 읽기·쓰기 겸용으로 연다
qemu-system-x86_64 ... -serial stdio -monitor none < "$FIFO" > "$LOG" &
printf 'echo /sys/bus/acpi/devices/*\n' >&4
```

**`exec 4>"$FIFO"`로 쓰면 그 자리에서 멈춘다.** FIFO를 쓰기 전용으로 여는
`open(2)`은 읽는 쪽이 생길 때까지 블록하는데, 그 읽는 쪽인 QEMU는 다음 줄에서야
시작하므로 서로를 기다린다. 읽기·쓰기 겸용(`<>`)은 안 막힌다.

**`-monitor none`을 붙인다.** 안 붙이면 `-display none`일 때 QEMU가 monitor도
stdio로 보내려다 "cannot use stdio by multiple character devices"로 죽는다.

**fish에서 `(...)`는 command substitution이다.** 처음에
`echo TARS-PROBE (/sys/bus/acpi/devices/*)`로 넣었더니 글로브의 첫 경로가
**명령으로 실행**됐고, fish의 implicit cd가 그 디렉터리로 들어갔다. 증상이
"프롬프트의 경로가 바뀐다"라 알아채기 쉬웠다. 괄호 없이 쓴다.

## 2. `PNP_DEBUG_MESSAGES`를 꺼도 우리가 읽던 PNP 줄은 안 없어진다

`drivers/pnp/core.c:220-223`이 `pnp_debug`를 module parameter로 두고
`base.h:179`의 `pnp_dbg`가 `if (pnp_debug)`로 감싼다. 우리 cmdline은
`console=ttyS0` 하나뿐이라(`boot/limine.conf:7`) 켜진 적이 없다.

**끄고 부팅해도 `i8042: PNP: PS/2 Controller [PNP0303:KBD,PNP0f13:MOU]`와
`00:04: ttyS0 at I/O 0x3f8`은 그대로 나온다** — 그 줄들은 `pnp_dbg`가 아니라
보통 `pr_info`다. **옵션 이름이 "PNP debug messages"라고 해서 PNP가 찍는 줄이
전부 그 옵션에 딸린 것은 아니다.**

## 3. vendor한 것이 쓰이는지는 빌드 파일이 답한다

`terminal/vendor_libghostty_vt.sh`가 만들던 `vendor/libghostty-vt/`(98MB)를
읽는 자리가 `terminal/sanity/libghostty_vt_main.c` 하나뿐이었다. 우리 빌드가
쓰는 것은 그 C 라이브러리가 아니라 **ghostty-src를 Zig 패키지로 잡은 쪽**이다 —
`build.zig.zon`의 `.ghostty = .{ .path = "ghostty-src" }`와 `build.zig`의
`ghostty_dep.module("ghostty-vt")`.

**증명은 지우고 빌드해 보는 것이다.** `vendor/libghostty-vt/`를 지운 뒤
`prepare.sh` → `zig build test`가 전부 통과했고 그 디렉터리가 다시 생기지
않았다. **`clean()`이 `terminal/vendor`를 일부러 남기기 때문에 게이트로는 이
경로를 못 밟는다** — 손으로 지워야 한다.

## 4. 도구를 지우기 전에 한 번은 돌려 본다

`stb_truetype_check`는 arm64 컨테이너에서 그대로 돌았고
`glyph 'A': 6x10 pixels, 24 non-zero`를 찍었다. **그 값이 `font_test`의 기대값
표 첫 줄(`'A'`, 6x10)과 정확히 같다** — 도구가 고장 난 것이 아니라 게이트와
겹쳐서 지운 것이라는 근거가 이것이다.

`libghostty_vt_check`는 **링크조차 안 됐다** —
`ld.lld: error: libghostty-vt.so is incompatible with elf64-littleaarch64`.
컨테이너가 arm64이고 그 라이브러리는 x86_64이며 `qemu-x86_64`(user mode)는
설치돼 있지 않다.

**"안 돌려 보고 지웠다"와 "돌려 보니 지울 것이더라"는 다르다.** 후자만이
다음에 같은 질문이 나왔을 때 조사를 없애 준다.

## 5. `ACPI_EC`는 실머신으로 갈 때 되켠다

실제 x86 노트북의 DSDT에는 대개 EC가 있고 배터리·뚜껑·밝기 키가 그 위에 있다.
**되켜지 않았을 때의 증상이 "AML이 실패한다"라서 원인까지 가는 길이 멀다.**
`HANDOFF.md`의 이월 숙제와 [[project_kernel_config]] 양쪽에 적어 두었다.

## 숫자

| 무엇 | 값 |
|---|---|
| bzImage | 2,946,048 → **2,933,760**바이트 (−12,288, 0.42%) |
| 없어진 디스크 | `vendor/libghostty-vt/` **98MB** + `Hanme_8x4x4.ttf` 451,512바이트 |
| 저장소에서 지운 줄 | 97줄(그중 88줄이 sanity `.c` 둘) |

관련: [[project_kernel_config]] · [[project_font_selection]] ·
[[project_build_host_arch]] · [[project_gate_latency]]
