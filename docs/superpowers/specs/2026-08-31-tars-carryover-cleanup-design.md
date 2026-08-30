# TARS Carryover Cleanup — Design

**Date:** 2026-08-31
**Status:** CC-M0 진행 중 (plan은 `docs/superpowers/plans/2026-08-31-tars-carryover-cleanup-cc-m0.md`)

## 한 줄 요약

**`HANDOFF.md`의 이월 숙제 가운데 "미룬다"로 정하지 않은 셋을 실제로 정리한다.**
커널 `.config`에서 우리가 쓰지 않는 항목 둘을 끄고, 아무도 실행할 수 없게 된
sanity 도구 둘과 그 도구만 쓰던 빌드 산출물을 없애고, 남아 있는 옛 폰트 파일을
지운다.

## 배경

Render Cost(RC-M0)가 2026-08-30에 끝나면서 진행 중인 서브프로젝트가 없어졌다.
2026-08-31에 사용자가 이월 숙제 중 **"작은 정리 묶음"**을 골랐다. 이월 숙제
목록에서 "미룬다"로 이미 결정이 난 것들(부분 갱신, `present`의 모드셋, `?`
검색, `w`의 줄 넘김, 검색 결과의 실시간 갱신)을 빼면 남는 것이 셋이다.

> - [ ] **`ACPI_EC`와 `PNP_DEBUG_MESSAGES` 정리.**
> - [ ] **`terminal/sanity/`의 수동 확인 도구 둘.** x86_64용이라 arm64 gcc로 못
>       만든다. 필요하면 `zig cc -target x86_64-linux-gnu`. **빌드해서 돌려 본
>       적이 없다.**
> - [ ] **`terminal/vendor/fonts/Hanme_8x4x4.ttf`가 남아 있다.** `vendor/`가
>       gitignore라 저장소에는 없다. 지워도 게이트는 안 흔들린다.

**이 서브프로젝트는 배우는 것이 적다.** 사용자도 그렇게 판단했고, 그래서 이번
milestone에 한해 구현 파일 편집까지 Claude Code가 한다(아래 "협업 범위의 예외").

## 착수 전에 조사로 안 것

### 1. QEMU의 게스트에는 Embedded Controller가 없다 — 게스트에게 직접 물었다

`docs/decisions/project_kernel_config.md`가 `ACPI_EC`를 켜 둔 채로 남긴 이유는
분명했다.

> `ACPI_EC`는 **일부러 기본값 `y`로 남겼다.** QEMU의 DSDT를 읽어 본 적이
> 없어서, EC opregion이 있는데 드라이버가 없으면 AML이 부팅 중에 실패하고 그
> 사실은 커널을 한 번 더 빌드하고 나서야 알게 되기 때문이다.

그 조건을 채웠다. `out/probe/acpi_probe.sh`가 ISO로 부팅한 뒤 시리얼 콘솔의
fish에 명령 두 줄을 넣어 `/sys/bus/acpi/devices/`를 받아 왔다. **게스트가 가진
ACPI 장치는 다음이 전부다.**

```
ACPI0010:00  device:00~device:22  LNXCPU:00  LNXPWRBN:00  LNXSYBUS:00
LNXSYBUS:01  LNXSYSTM:00  PNP0A03:00  PNP0A06:00~02  PNP0B00:00
PNP0C0F:00~04  PNP0F13:00  PNP0103:00  PNP0303:00  PNP0400:00
PNP0501:00  PNP0700:00  QEMU0002:00
```

**Embedded Controller의 HID인 `PNP0C09`가 없다.** 물어본 방식 자체가 답이었다 —
`echo /sys/bus/acpi/devices/PNP0C09*`에 fish가
`No matches for wildcard`로 답했다. EC 장치가 없으므로 그 EC를 가리키는
EmbeddedControl opregion을 실행할 AML도 없고, 같은 부팅 로그에 `ACPI Error:`가
한 줄도 없다.

**게스트에 명령을 넣는 길은 `-serial stdio`다.** 게이트 체인들이 쓰는 QEMU
monitor의 `sendkey`는 PS/2 키보드로 가므로 시리얼 콘솔의 fish에는 닿지 않는다.
그래서 FIFO를 QEMU의 stdin에 물리고 거기에 글자를 흘려 넣었다.

### 2. `PNP_DEBUG_MESSAGES`는 켜 두어도 아무것도 안 찍는다

`drivers/pnp/Kconfig`의 도움말이 조건을 그대로 적어 두었다.

> The messages can be enabled at boot-time with the pnp.debug kernel parameter.

`drivers/pnp/core.c:220-223`이 `pnp_debug`를 module parameter로 두고,
`base.h:179`의 `pnp_dbg`가 `if (pnp_debug)`로 감싼다. **우리 커널 cmdline은
`console=ttyS0` 하나뿐이라**(`boot/limine.conf:7`) `pnp.debug`가 켜진 적이
없다. 이 옵션을 끄면 없어지는 것은 실행되지 않는 `dev_printk` 호출과 그
문자열뿐이다.

### 3. 우리 빌드는 vendor된 libghostty-vt **라이브러리**를 안 쓴다

`terminal/build.zig.zon`이 ghostty를 **Zig 패키지**로 잡고
(`.ghostty = .{ .path = "ghostty-src" }`), `build.zig:69`·`:115`가
`ghostty_dep.module("ghostty-vt")`를 import한다. 한편
`terminal/vendor_libghostty_vt.sh:19`는 그와 별개로
`zig build -Demit-lib-vt -Dtarget=x86_64-linux-gnu`를 돌려
`terminal/vendor/libghostty-vt/`에 C 라이브러리를 만든다. **그 산출물을 읽는
자리가 `terminal/sanity/libghostty_vt_main.c` 말고는 저장소에 없다.**
`build.zig`가 include path로 잡는 것은 `vendor` 하나이고
(`:50`·`:149`) 그것은 `stb_truetype.h` 때문이다.

디스크에서 그 산출물은 **98MB**다.

### 4. 그 sanity 도구 둘 중 하나는 이 컨테이너에서 실행할 방법이 아예 없다

| 도구 | 지금 상태 |
|---|---|
| `stb_truetype_check` | 순수 C에 `-lm`뿐이다. **컨테이너 native(arm64)로 빌드해서 그대로 돌릴 수 있다.** |
| `libghostty_vt_check` | x86_64로만 만들어진 vendored 라이브러리에 링크한다. 컨테이너는 arm64이고 `qemu-x86_64`(user mode)가 설치돼 있지 않다. **빌드해도 실행할 수 없다.** |

두 도구가 TF-M0에서 증명하려던 것은 "vendor해 온 것이 실제로 링크되고
동작하는가"였다. **그 질문은 이제 게이트가 매번 답한다** — `vt_test`가
호스트에서 ghostty-vt 모듈로 실제 화면을 만들고, `font_test`가 stb_truetype로
unifont를 구워 글리프 크기를 상수와 비교한다. 둘 다 `zig build test`에 묶여
있어 여덟 체인이 전부 밟는다.

### 5. 옛 폰트 파일은 저장소에도 initrd에도 없다

`kernel/make_initrd.sh:102`가 initrd에 복사하는 폰트는 `unifont.otf`
하나뿐이고, `terminal/vendor_fonts.sh`가 내려받는 것도 unifont 하나다.
`terminal/vendor/`는 `.gitignore` 대상이다. **`Hanme_8x4x4.ttf`는 로컬 디스크의
452KB짜리 잔여물이고, 지우는 것으로 끝난다.**

## 목표와 비범위

**목표.** 위 다섯 사실 위에서 이월 숙제 셋을 실제로 없앤다. 없어졌다는 것을
게이트 한 번으로 확인한다.

**비범위.**

- **게이트에 새 검사를 만들지 않는다.** 이번 변경은 전부 "쓰지 않던 것을
  없애는 것"이라, 지키고 싶은 새 동작이 없다. 커널 `.config` 변경이 지켜야
  하는 것은 이미 여덟 체인이 보고 있는 "부팅이 된다"이다.
- **실머신 부팅을 다루지 않는다.** `ACPI_EC`는 실제 노트북에서는 필요한
  드라이버다(결정 3).
- **`terminal/ghostty-src`(481MB)를 건드리지 않는다.** 그 트리는 우리 빌드의
  입력이다.

## 결정

### 결정 1 — `ACPI_EC`를 끈다

근거는 착수 전 조사 1이다. 게스트에 EC 장치가 없고, EC를 켜 둔 채로 부팅한
로그에 `ACPI Error:`가 없다. `project_kernel_config.md`가 세워 둔 규율
**"이해하는 것은 끄고 이해하지 못하는 것은 남긴다"**에서, 이 항목은 이제
이해한 쪽으로 넘어왔다.

`drivers/acpi/Kconfig:136`이 `bool "Embedded Controller"`로 **프롬프트를
가지므로** `# CONFIG_ACPI_EC is not set`이 `olddefconfig`를 견딘다. 프롬프트가
없는 항목은 눌러도 기본값으로 되돌아온다는 것을 같은 문서가 적어 두었고,
그래서 이 milestone은 **눌린 값이 `build/.config`에 살아남았는지를 직접
확인한다**(검산 1).

### 결정 2 — `PNP_DEBUG_MESSAGES`를 끈다

근거는 착수 전 조사 2다. `CONFIG_PNP` 자체는 그대로 둔다 — `SERIAL_8250_PNP`와
i8042의 PS/2 열거가 그 위에 서 있다.

### 결정 3 — 실머신 부팅을 하게 되면 `ACPI_EC`를 되켠다. 그것을 이월 숙제로 남긴다

**이 결정에는 대가가 있다.** 실제 x86 노트북의 DSDT에는 대개 EC가 있고, 배터리
· 뚜껑 · 밝기 키가 그 위에 있다. 지금 `.config`는 QEMU를 대상으로 좁혀 놓은
설정이라(`NET`도 `THERMAL`도 꺼져 있다) 실머신으로 갈 때 되켤 항목이 어차피
여럿인데, **되켤 목록에 이것이 있다는 사실을 적어 두지 않으면 그때 증상이
"AML이 실패한다"로 나타나고 원인까지 가는 길이 멀다.** 그래서 `HANDOFF.md`의
이월 숙제와 `docs/decisions/project_kernel_config.md` 양쪽에 남긴다.

### 결정 4 — sanity 도구 둘을 지운다. 하나는 지우기 전에 한 번 돌려 본다

`libghostty_vt_check`는 이 컨테이너에서 실행할 수 없고(조사 4), 그것이
증명하려던 것은 게이트가 매번 증명한다. `stb_truetype_check`는 돌릴 수 있지만
**같은 이유로 남길 값이 없다** — `font_test`가 같은 헤더로 같은 폰트를 굽고,
게이트가 매번 돌린다.

**그래도 `stb_truetype_check`는 지우기 전에 한 번 빌드해서 돌린다.** 이월 숙제가
"빌드해서 돌려 본 적이 없다"라고 적어 둔 것을 "돌려 봤고, 돌려 보니 남길 이유가
없더라"로 바꾸는 것과, 안 돌려 본 채로 지우는 것은 다르다. **결과가 이상하면 그
자체가 새 정보다** — 그때는 지우지 않고 멈춘다.

`libghostty_vt_check`는 실행이 불가능하므로 **빌드만 시도한다.** 링크가 되는지
안 되는지는 이번 정리의 판단을 바꾸지 않지만, "왜 못 돌리는가"를 로그로 남겨
두면 다음에 같은 질문이 나왔을 때 조사가 필요 없다.

### 결정 5 — `vendor_libghostty_vt.sh`에서 라이브러리 빌드를 뺀다. 소스 내려받기는 남긴다

도구가 없어지면 그 98MB 산출물을 읽는 자리가 하나도 안 남는다(조사 3). 스크립트
이름은 그대로 두는데, **`terminal/prepare.sh:14`가 그 이름을 부르고 `check.sh`의
`BUILD_STEPS`가 `./prepare.sh`를 보므로** 이름을 바꾸면 고칠 자리가 늘어난다.
하는 일이 바뀐 것은 파일 안의 주석으로 적는다.

**이 변경은 게이트가 밟지 않는 경로에 있다.** `check.sh`의 `clean()`이
`terminal/ghostty-src`를 일부러 남기고, `prepare.sh`는 그 디렉터리가 없을 때만
이 스크립트를 부른다. 그래서 검증을 따로 만든다 — **산출물 디렉터리를 지운 뒤
`prepare.sh`를 돌려 `zig build`가 통과하는 것**이 "빌드가 그것을 안 쓴다"의
증명이다(검산 3).

### 결정 6 — 옛 폰트 파일은 그냥 지운다. 커밋에 아무것도 안 남는다

`terminal/vendor/`가 `.gitignore`라 이 삭제는 `git status`에 나타나지 않는다.
**그래서 이 항목만은 "고쳤다"는 증거가 커밋이 아니라 실행 로그에 있다.**

### 결정 7 — 게이트는 마지막에 한 번 돌린다

커널 `.config`가 바뀌면 여덟 체인이 전부 새 커널로 부팅한다. 그래서 루트
게이트 한 번이 이 milestone의 종료 게이트다. 기준선은 SP-M1 뒤의 **16분
34.78초 · 16분 42.73초 · 16분 42.35초**다.

**시간이 줄어들 것을 기대하지 않는다.** 커널이 조금 작아지지만 게이트 시간의
8할은 빌드이고 그 대부분이 커널 컴파일 자체다. 이 게이트의 잡음이 ±3분이라
어느 쪽이든 읽어 낼 수 없다.

## 검산과 성공 기준

| # | 무엇을 보는가 | 어떻게 |
|---|---|---|
| 1 | 눌린 두 항목이 `olddefconfig`를 견뎠다 | `kernel/build/.config`에 `# CONFIG_ACPI_EC is not set`과 `# CONFIG_PNP_DEBUG_MESSAGES is not set`이 있다 |
| 2 | 부팅이 안 깨졌다 | 새 커널로 부팅한 로그에 `ACPI Error:`가 없고 fish 배너에 도달한다 |
| 3 | 빌드가 vendored 라이브러리를 안 쓴다 | `terminal/vendor/libghostty-vt/`를 지운 뒤 `prepare.sh` → `zig build`가 통과한다 |
| 4 | 지운 것이 그것뿐이다 | 매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 따로 센다 |
| 5 | 종료 게이트 | 루트 게이트 3/3 |

**곁들여 재는 것 둘.** 커널 `.config` 변경 전후의 `bzImage` 크기와, 없어진
디스크 98MB. 둘 다 판정이 아니라 기록이다.

## 위험

**1. 눌린 값이 되돌아온다.** `ACPI_EC`가 `default X86`이라 프롬프트가 없었으면
`olddefconfig`가 되살린다. 검산 1이 이것을 잡는다. **잡히면 그때는 `.config`가
아니라 이유를 다시 봐야 한다.**

**2. EC를 끄면 `ACPI_EC_DEBUGFS`가 함께 없어진다.** 지금 `.config`에
`# CONFIG_ACPI_EC_DEBUGFS is not set`으로 이미 눌려 있는데, `ACPI_EC`가 꺼지면
그 항목이 **존재하지 않게 되어** `olddefconfig`가 줄을 통째로 지운다. 이것은
사고가 아니라 정상이다 — 다만 `.config` diff에 예상보다 한 줄이 더 나오므로
미리 적어 둔다.

**3. `-Demit-lib-vt`를 빼면 새 체크아웃에서 무언가 안 만들어진다.** 검산 3이
현재 트리에서는 이것을 잡지만, **완전히 새로운 체크아웃 경로는 밟지 않는다**
(ghostty 소스 481MB를 다시 받아야 한다). 남는 위험을 그대로 적어 둔다.

## 협업 범위의 예외 (이번 서브프로젝트에 한한다)

`CLAUDE.md`는 구현 파일 편집을 사용자가 하도록 정해 두었다. **2026-08-31에
사용자가 이번 작업에 한해 편집까지 Claude Code가 하도록 정했다** — 근거는
"이번 태스크는 배우는 것이 적다"이고, 그 판단은 위 조사 결과와 맞는다. 이
milestone이 끝나면 원래 규율로 돌아간다.

그 대신 **매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 따로 세고,
지우는 편집은 `git diff | grep '^-'`로 지워진 줄의 내용을 직접 읽는다**(검산 4).
사람이 읽는 자리가 없어졌으므로 그 자리를 기계적인 확인으로 메운다.

## 비워 두는 자리

아래 절은 CC-M0이 끝난 뒤 실측으로 채운다.

## CC-M0이 실측한 것 (2026-08-31)

_(실행 후 채운다)_
