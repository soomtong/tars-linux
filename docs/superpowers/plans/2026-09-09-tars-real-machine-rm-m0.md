# RM-M0 Implementation Plan — UEFI로 뜬다

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 파일 편집 → 명령 실행은
> Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가
> 만든다. 체크박스는 진행 추적용이다.
>
> **이 milestone은 편집을 Claude Code가 한다** — 사용자가 2026-09-09에
> "자러 가니까 이번 태스크의 모든 작업을 마무리해줘"라고 위임했다. SH·FP
> 세션의 예외와 같은 종류다.

**Goal:** 게이트에 열번째 체인이 생기고, 그 체인이 **UEFI 펌웨어(OVMF)로**
같은 ISO를 부팅해 **EFI GOP 프레임버퍼 위의 simpledrm**에 격자를 그린다.

**Architecture:** 기존 아홉 체인은 한 글자도 안 건드린다(design 결정 2).
새 체인만 `-cdrom` + pflash 둘로 OVMF를 물고, `make_iso.sh`가 굽는 ISO는
하나인 채로 **부트 카탈로그에 BIOS·UEFI 항목 둘**을 담는다(결정 5). 커널은
`RELOCATABLE`이 켜져야 UEFI에서 실린다(실측 2).

**Tech Stack:** `devcontainer/Dockerfile` · `kernel/.config` ·
`boot/limine.conf` · `boot/make_iso.sh` · `machine/check.sh`(새 파일) ·
`check.sh`

---

## 착수 전에 스파이크로 확인한 것 — **다시 조사하지 말 것**

전문은 design의 **"착수 전에 실측한 것"** 절(항목 다섯)에 있다. 이 plan이
기대는 넷.

**1. `RELOCATABLE`이 진짜 벽이다.** `EFI`만 켜면 시리얼이 320바이트에서 멈춘다.
limine이 `PANIC: linux: Non-relocatable kernel could not be loaded at required
address 0x100000`을 찍는데 **그 말이 GOP 콘솔로만 가서 안 보인다.**
`serial: yes`가 그것을 들리게 한다.

**2. `.config`를 켜는 데 층이 있다.** `USB_SUPPORT`를 켜도 `USB`는 안 켜지고,
`USB`를 켜야 `USB_XHCI_HCD` 줄이 `.config`에 나타난다. **M0의 넷은 다행히
한 층이다** — `EFI`·`RELOCATABLE`·`SYSFB_SIMPLEFB`·`DRM_SIMPLEDRM` 전부
`# CONFIG_X is not set` 줄이 이미 있다. 층이 문제가 되는 것은 RM-M1이다.

**3. 프레임버퍼가 1024x768이 아니라 1280x800이다.** OVMF의 GOP 기본 모드이고
격자가 `155x47`이다. **다른 체인의 격자 수를 베껴 오면 안 된다.**

**4. `--protective-msdos-label`은 대시 둘이다.** 하나면
`xorriso : FAILURE : -as mkisofs: Unrecognized option '-protective-msdos-label'`
이다.

## 착수 전에 코드를 읽고 확인한 것

**5. `boot/check.sh`는 `last_frame` 같은 헬퍼를 안 쓴다.** 판정이
`grep -q "Welcome to fish, the friendly interactive shell"` 하나뿐이다
(`boot/check.sh:37`). 그래서 design 위험 3(`serial: yes`가 로그를 시끄럽게
만든다)이 기존 체인에 닿지 않는다 — **부분 문자열 매치이고, 우리 쪽 줄에는
limine의 escape가 안 붙는다.**

**6. 커널 빌드가 안 늘어난다.** `check.sh:15`의 `clean()`이 회차마다
`kernel/build`를 지우지만 `build.sh`의 스탬프(`.config`와 `build.sh`의 sha256)
때문에 **회차 안에서는 첫 체인만 진짜로 빌드한다.** 열번째 체인이 더하는 것은
자기 부팅 시간뿐이다.

**7. `require_build_steps`가 새 체인도 검사한다.** `check.sh:173`의 진입 검사가
`CHAINS`를 훑어 "부팅하는 것을 빌드하지 않는 체인"을 거른다. 새 체인이 무엇을
빌드해야 하는지는 그 함수를 읽고 맞춘다 — **`check.sh`를 고치기 전에
`require_build_steps`를 먼저 읽는다.**

---

## Task 1 — 이미지에 OVMF를 넣는다

**넣을 것:** `devcontainer/Dockerfile`의 첫 `RUN` 패키지 목록에 `ovmf` 한 줄과
그 앞의 설명 주석.

**왜 주석이 그 모양인가.** 이 파일의 관례는 "설명은 그 `RUN` 앞에"다. 적을 것은
셋이다 — 아홉 체인이 SeaBIOS로 뜨는데 노트북은 UEFI라는 것, `Architecture:
all`이라 arm64 컨테이너에 그대로 깔린다는 것, 크기가 3.6MB라는 것.

**이미지를 다시 빌드해야 한다**(design 위험 5). `ovmf`가 첫 `RUN`에 들어가므로
뒤의 레이어(amd64 sysroot · Zig)가 전부 다시 돈다.

```bash
docker build -t tars-devcontainer devcontainer/
docker run --rm tars-devcontainer bash -c \
  'ls /usr/share/OVMF/OVMF_CODE_4M.fd && zig version'
```

**판정:** 파일이 있고 Zig가 `0.16.0`이다.

- [ ] Task 1

## Task 2 — 커널을 UEFI에서 실릴 수 있게 만든다

**넣을 것:** `kernel/.config`에서 넷을 켠 뒤 되접은 고정점.

```
# CONFIG_EFI is not set            → CONFIG_EFI=y
# CONFIG_RELOCATABLE is not set    → CONFIG_RELOCATABLE=y
# CONFIG_SYSFB_SIMPLEFB is not set → CONFIG_SYSFB_SIMPLEFB=y
# CONFIG_DRM_SIMPLEDRM is not set  → CONFIG_DRM_SIMPLEDRM=y
```

**왜 이 넷인가.**

| | 없으면 |
|---|---|
| `EFI` | 커널이 UEFI 핸드오프(메모리 맵·시스템 테이블)를 모른다 |
| `RELOCATABLE` | **limine이 0x100000에 못 실어서 부팅이 시작도 안 된다**(실측 1) |
| `SYSFB_SIMPLEFB` | `screen_info`에서 `simple-framebuffer` 플랫폼 장치가 안 만들어진다 |
| `DRM_SIMPLEDRM` | 그 장치에 붙어 `/dev/dri/card0`을 낼 드라이버가 없다 |

**넷이 한 벌이다.** 하나만 빠지면 조용히 깨진다 — HI가 UTF-8 로케일 셋에 대해
적은 것과 같은 종류다.

**되접기가 `project_kernel_config`의 규칙이다.** 켜고 빌드한 뒤
`cp kernel/build/.config kernel/.config`, 다시 빌드해 `diff`가 비는지 확인한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  ./kernel/build.sh >/dev/null 2>&1
  cp kernel/build/.config kernel/.config
  ./kernel/build.sh >/dev/null 2>&1
  diff kernel/.config kernel/build/.config && echo "fixpoint OK"'
```

**정규화 커밋을 따로 안 나눈다** — 착수 전 `.config`가 이미 고정점이었다
(스파이크에서 확인했다). 그래서 이 커밋의 diff가 곧 "이번 변경이 커널에
들여온 것"의 완전한 목록이다.

**판정:** `fixpoint OK`. 그리고 diff가 40줄 추가·6줄 삭제이고, 추가된 `=y`
안에 `RANDOMIZE_BASE`·`SYSFB`·`EFI_ESRT`·`DRM_SYSFB_HELPER`가 있다.

**KASLR이 저절로 켜지는 것을 누르지 않는다**(design 결정 6).

- [ ] Task 2

## Task 3 — 부트로더가 실패하면 시리얼로 말하게 한다

**넣을 것:** `boot/limine.conf`의 맨 앞에 `serial: yes`.

**왜 맨 앞인가.** limine의 전역 설정은 첫 항목(`/TARS`) 앞에 와야 한다.
`timeout: 0`이 이미 그 자리에 있다.

**대가를 미리 안다**(design 결정 4) — limine이 글자마다 `ESC[01;NNH`를 찍는다.
기존 체인 중 ISO를 부팅하는 것은 `boot/check.sh` 하나이고 그 판정은 부분 문자열
매치라 안 흔들린다(실측 5).

**판정은 Task 5에서 함께 받는다** — 이 줄이 없으면 Task 5의 실패 원인을 볼 수
없으므로 순서가 이것이 먼저다.

- [ ] Task 3

## Task 4 — ISO 하나가 BIOS·UEFI를 둘 다 태우게 한다

**넣을 것:** `boot/make_iso.sh`에 셋.

1. 스테이지에 `EFI/BOOT/` 디렉터리와 `BOOTX64.EFI`
2. 스테이지의 `boot/limine/`에 `limine-uefi-cd.bin`
3. `xorriso` 인자에 `--efi-boot boot/limine/limine-uefi-cd.bin`
   `-efi-boot-part --efi-boot-image --protective-msdos-label`

**두 파일이 다른 경로다**(design 결정 5). `limine-uefi-cd.bin`은 El Torito
부트 카탈로그가 가리키는 FAT 이미지이고, 트리의 `EFI/BOOT/BOOTX64.EFI`는
이 ISO를 USB에 dd로 쓴 뒤 펌웨어가 **파일로** 찾을 때 쓰인다.

**`limine bios-install`은 그대로 둔다.** UEFI를 더하는 것이 BIOS 경로를
빼앗지 않는다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  './kernel/build.sh && ./kernel/make_initrd.sh && ./boot/make_iso.sh && \
   xorriso -indev out/tars.iso -report_el_torito plain 2>&1 | tail -20'
```

**판정:** `-report_el_torito`가 부트 카탈로그 항목 **둘**을 보고하고 하나가
`platform_id 0xef`(UEFI)다. 그리고 `boot/check.sh`가 여전히 통과한다 —
**BIOS 경로를 안 깼다는 증거를 UEFI를 켜기 전에 받는다.**

- [ ] Task 4

## Task 5 — 열번째 체인을 만든다

**넣을 것:** `machine/check.sh`(새 파일). 골격은 `boot/check.sh`를 따르고
판정 헬퍼는 `hangul/check.sh`를 따른다.

**QEMU 인자.**

```bash
qemu-system-x86_64 -machine q35 -m 512 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,unit=1,file="$VARS" \
  -cdrom ../out/tars.iso \
  -serial file:"$LOG" -display none -no-reboot
```

**`VARS`는 매번 복사한다.** `OVMF_VARS_4M.fd`는 펌웨어가 NVRAM 변수를 쓰는
곳이라 읽기 전용으로 물리면 부트 항목을 못 만든다. `mktemp`로 만든다.

**virtio-gpu를 안 물린다.** 그것이 이 체인의 요점이다 — 픽셀이 GOP에서만
온다.

**판정 셋**(design "RM-M0의 모양"의 표). 하나만 보면 "안 뜬다"의 이유가 안
갈린다.

| 보는 것 | 없으면 무엇이 틀렸나 |
|---|---|
| `efi: EFI v` | OVMF가 아니라 SeaBIOS로 떴다 (pflash 인자가 안 먹었다) |
| `Initialized simpledrm` | GOP에서 `card0`을 못 만들었다 (`SYSFB_SIMPLEFB` 또는 `DRM_SIMPLEDRM`) |
| `terminal: grid 155x47 (fb 1280x800)` | 모드가 갈렸다 |

**`Welcome to fish`만 보면 안 된다** — simpledrm이 실패해도 `init`이 시리얼
콘솔 셸로 폴백해서 그 줄이 나온다. **증상이 성공과 똑같아지는 자리다**
(CC-M0 · IS-M0이 겪은 것과 같은 종류).

**실패 메시지에 로그의 관련 줄을 함께 찍는다.** IS-M1 실측 5의 규율이다 —
"무엇이 없다"와 "그래서 어디로 갔는가"가 한 화면에 있어야 한다.

**timeout은 고정하지 않는다**(design 위험 1). `boot/check.sh`의 수법 그대로 —
배너가 나오면 즉시 끝내고 최대 120초 기다린다.

**`chmod +x`를 잊지 않는다.** 체인 아홉이 전부 실행 비트가 있다.

- [ ] Task 5

## Task 6 — 게이트가 그 체인을 돌게 한다

**넣을 것:** `check.sh`의 `CHAINS` 배열에 `"RM-M0:./machine/check.sh"` 한 줄.

**착수 전에 `require_build_steps`를 읽는다**(실측 7) — 진입 검사가 새 체인에
무엇을 요구하는지 확인하고 `machine/check.sh`가 그것을 만족하는지 본다.
만족하지 않으면 게이트가 **첫 부팅 전에** 멈춘다.

**배열의 어디에 넣는가.** 맨 뒤다. `boot` → … → `hangul` 순서가 서브프로젝트
연대순이고 RM이 가장 나중이다.

**게이트는 20분이 넘으므로 백그라운드로 돌린다** — Bash 도구의 타임아웃 상한이
10분이다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/gate.time
```

**판정:** `TARS check PASS: all chains 3/3 consecutive runs succeeded`.
그리고 시간을 착수 전 기준선 **19분 40.02초**와 비교해 적는다 — 잡음이 ±3분
이므로(IS-M0 실측 3) 단일 값으로 판정하지 않고 **설명되는 값인지**만 본다
(체인 하나 × 3회 + 커널 빌드가 커진 만큼).

- [ ] Task 6

## Task 7 — 음성 확인

**넣은 검사가 진짜로 무언가를 보는지 확인한다.** SH-M2 · FP-M1이 쓴 규율이다.

`kernel/.config`의 `CONFIG_RELOCATABLE=y`를 `# CONFIG_RELOCATABLE is not set`으로
되돌리고 **`machine/check.sh` 하나만** 돌린다.

**기대하는 실패:** limine이 `PANIC: linux: Non-relocatable kernel`을 찍고,
체인이 `efi: EFI v`를 못 찾아 exit 1이다. **`serial: yes`가 없으면 이 확인이
"조용히 timeout"으로 보인다** — Task 3이 왜 Task 5보다 먼저인지가 여기서
증명된다.

되돌린 뒤 다시 켜고 그 체인만 한 번 더 돌려 초록을 확인한다.

- [ ] Task 7

## Task 8 — 커밋과 문서

**커밋은 둘로 나눈다.**

1. 이미지·커널·부트로더·ISO(Task 1~4) — "부팅할 수 있게 만든 것"
2. 체인과 게이트(Task 5~6) — "그것을 보는 자리"

**`git status --short`를 먼저 본다.** `kernel/build/`와 `out/`이 커밋에 들어가지
않는지 확인한다 — `.gitignore`에 있어야 한다. BF-M0에서 빌드 산출물이 실수로
커밋된 적이 있다.

**design의 `Status:` 줄을 고친다** — RM-M0 완료와 게이트 실측치.

- [ ] Task 8

---

## 위험 요약

| | 위험 | 처방 |
|---|---|---|
| 1 | OVMF가 느려 timeout | 고정 timeout 없이 배너 폴링, 최대 120초 |
| 2 | 커널이 커져 게이트가 느려짐 | 커널 빌드 시간을 따로 재서 적는다 |
| 3 | `serial: yes`가 기존 판정을 흔든다 | 실측 5에서 확인했다. `boot/check.sh`가 여전히 초록인지 Task 4에서 본다 |
| 4 | GOP 기본 모드가 QEMU 버전에 딸림 | 정확한 수를 본다. 깨지면 조용하지 않다(exit 1) |
| 5 | 이미지 재빌드가 apt 버전을 바꾼다 | Zig는 못으로 박혀 있다. 재빌드 뒤 `zig version`을 확인한다 |
| 6 | `require_build_steps`가 새 체인을 거부 | Task 6 전에 그 함수를 읽는다 |
