# KU-M1 — 커널 6.18.42 → 6.18.60

Goal: 커널을 같은 longterm 줄기의 최신 패치 6.18.60으로 올린다(KU design Milestone 절). tarball sha256을 갈고, `.config`를
`olddefconfig`로 옮긴 diff를 읽고, 이미지 크기를 다시 재서 1GiB ESP에 두 벌이 들어가는지 보고, 루트 게이트 22/22로 닫는다.
실기 확인은 사용자 몫이다 — KU-M0이 만든 old 엔트리가 그때 처음 실제 쓸모를 갖는다(이 ISO로 갱신하면 old가 6.18.42다).

Architecture: 바뀌는 것은 `kernel/build.sh`의 두 값과 `kernel/.config`의 세 줄뿐이다. 코드 경로는 그대로다. 판단의 무게는 "패치
18번이 우리가 기대는 동작을 바꿨는가"를 소스에서 미리 읽는 쪽에 있다(아래 확정 4~7).

---

## 버전을 고른 이유

2026-11-01 kernel.org `releases.json`: mainline 7.3(10-18), stable 7.3.1, longterm 6.18.60 · 6.12.115 · 6.6.161 …, 7.2는 오늘 EOL.

design은 "6.18의 최신 패치 또는 다음 longterm"을 고르라고 했다. 다음 longterm은 아직 없다 — 관례상 그해 마지막 릴리스가 되므로
7.4(12월 중순 예상)다. 사용자가 6.18.60을 골랐다(2026-11-01). 이유는 둘이다.

- 업그레이드 경로(sha256 · olddefconfig · 크기 · 게이트 · 실기의 old 엔트리)를 위험이 작은 변화로 한 번 끝까지 밟는다.
- 7.3.1은 longterm이 아니라 곧 7.4로 다시 올려야 한다. 7.4 LTS 이동은 나온 뒤에 따로 연다(아래 "하지 않는 것" 1).

## 착수 전에 확정한 것

2026-11-01, HEAD `5a2219f`. 소스 비교는 컨테이너 안에서 했다(macOS 파일시스템은 대소문자만 다른 커널 파일을 겹친다).

1. sha256. `cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc`에서 `linux-6.18.60.tar.xz`는
   `3c2f44ef6acc021a7ad444d9a2e6ec1ef488ff09368793d0004a6080f69d621e`. 받은 파일(154,827,264바이트)의 `shasum -a 256`이 같다. 같은
   파일의 6.18.42 값이 `build.sh`에 박힌 값과 같아서, VS-M0이 읽은 자리와 같은 출처임도 확인했다. `KERNEL_MAJOR="6.x"`는 그대로다.
2. `.config` diff. 커밋된 `kernel/.config`를 6.18.42 소스에 대고 `olddefconfig`한 결과가 커밋된 파일과 바이트로 같다 — 지금 config는
   섞인 변화가 없다. 6.18.60 소스에 대고 돌리면 차이는 셋이다.
   - 3줄 머리 `# Linux/x86_64 6.18.60 Kernel Configuration`.
   - `CONFIG_CC_OPT_INLINE_MEMSET="-finline-stringops=memset"`. `init/Kconfig`의 prompt 없는 string으로, 컴파일러가 그 옵션을 받는지
     `cc-option`으로 시험해 채운다. x86에서는 `arch/x86/entry/vdso/Makefile`만 쓴다 — vDSO의 memset을 libc 없이 인라인으로 푼다.
   - `CONFIG_HAVE_ARCH_GET_SECUREBOOT=y`. `arch/Kconfig`의 `def_bool EFI`라 저절로 켜진다. 동작을 고르지 않는 표지다.
   둘 다 사람이 고르는 옵션이 아니다. 그래서 Task 1은 `olddefconfig`의 결과를 그대로 커밋한다 — 커밋된 config가 olddefconfig의 고정점
   이라는 성질을 이어 간다.
3. 다른 자리의 버전 글자. 저장소에서 `6.18.42`를 쓰는 곳 가운데 지금 상태를 말하는 것은 `kernel/build.sh` 6줄, `kernel/.config` 3줄,
   `kernel/guest_firmware.sh` 44줄, `Makefile` 87줄(help), `terminal/src/drm.zig` 122줄(MAX_CLIPS 주석)이다. `measurements.md` 95 ·
   `project_kernel_config.md` · `project_dirty_rows.md`와 plan · spec 38개는 그때의 기록이라 고치지 않는다. 커널 소스 경로를 쓰는 것은
   `build.sh`뿐이다. CI(`checks.yml`)는 커널을 빌드하지 않는다.
4. iwlwifi. `guest_firmware.sh`는 "커널을 올리면 iwlwifi 줄을 다시 골라야 한다"고 적었다. `drivers/net/wireless/intel/iwlwifi`의
   `*_UCODE_API_MAX` 스물네 줄이 두 버전에서 같다(정렬해서 비교 — 정렬 안 한 첫 비교는 `grep -r`의 순서 차이를 diff로 보였다).
   요청하는 파일 번호가 그대로이므로 목록을 다시 고르지 않는다.
5. 요청하는 firmware 이름. `drivers` · `sound`의 `MODULE_FIRMWARE`를 모아 정렬해 비교하면 새로 생긴 것이 넷이다 —
   `rtl_bt/rtl8761cu_{config,fw}.bin`(btrtl) · `FIRMWARE_MT7920` · `FIRMWARE_MT7927`(btmtk). 모두 `drivers/bluetooth/`이고 우리
   `.config`에 `CONFIG_BT`가 없다. 빠진 것은 없다. `vendor_firmware.sh`는 linux-firmware 릴리스에 묶여 있어 커널과 상관없다.
6. 화면 경로. `drm.zig`의 MAX_CLIPS 주석이 기대는 `virtio/virtgpu_plane.c` · `drm_damage_helper.c` · `drm_format_helper.c`는 두 버전이
   바이트로 같다. `sysfb/simpledrm.c`는 바뀌었다 — width · height를 `U16_MAX`로 묶는 검증, stride 계산의 넘침 검사(`u64` 뒤
   `INT_MAX`), OF 패널의 `width-mm` · `height-mm` 읽기(x86에는 없는 경로)다. clip마다 blit하는 자리는 그대로다.
7. 바뀐 파일은 트리 전체에서 5,246개다(패치 18번의 누적). 4~6은 그 가운데 우리 동작에 닿는 자리를 골라 읽은 것이고, 나머지는 게이트가
   본다. 게이트는 virtio · NVMe · USB · HDA · 입력을 QEMU로 보지만 실칩 드라이버(SOF · 실제 무선 · i915 등)는 못 본다 — 그것이 실기
   확인과 old 엔트리의 몫이다.
8. 빌드 스탬프. `build.sh`의 스탬프 해시는 `.config`와 `build.sh` 자신이다. 버전 글자가 `build.sh`에 있으므로 버전을 올리면 해시가 바뀌어
   증분 빌드도 다시 make한다 — GL-M1이 미리 짚어 둔 경로를 이번에 처음 밟는다. 루트 게이트는 `clean()`이 `kernel/build`를 지우므로
   어차피 처음부터 빌드한다.
9. `build.sh` 24~37줄의 주석은 GL-M1 첫 방식(mtime 비교)의 잔재다. "mtime을 보는 것은 make가 쓰던 기준 그대로다"라고 하는데 바로 뒤
   38~58줄이 "mtime으로 판정하지 않는다"이다. 둘 다 `e9b79e4`에서 들어왔다. 같은 파일을 고치는 김에 앞 단락을 지우고, 앞 단락에만
   있던 "틀렸을 때의 증상은 조용하지 않다 …" 두 줄은 뒤 단락 끝(clean() 문장 앞)으로 옮긴다.
10. 옛 소스. `kernel/src/linux-6.18.42`는 1.6GB이고 `clean()`이 지우지 않는다(`.gitignore` 대상). 게이트가 끝나면 지운다 — 되돌릴
    일이 생기면 `build.sh`가 tarball을 다시 받는다.

## Task 1: 버전 · sha256 · config (lead가 직접)

- `kernel/build.sh`: `KERNEL_VERSION="6.18.60"`, `KERNEL_SHA256`을 확정 1의 값으로. 확정 9의 주석 정리.
- `kernel/.config`: 확정 2의 세 줄. 손으로 치지 않고 컨테이너의 `olddefconfig` 결과를 복사한다.
- `kernel/guest_firmware.sh` 44줄: "커널 6.18.42와 …에 대해 고른 것이다"를 "6.18.42에서 고르고 6.18.60에서 API_MAX와 MODULE_FIRMWARE를
  대조해 그대로 둔 것이다(KU-M1)"로.
- `Makefile` 87줄 help의 버전.
- `terminal/src/drm.zig` 122줄: "커널 6.18.42의 두 드라이버다"를 "커널 6.18의 두 드라이버다(6.18.42에서 읽고 6.18.60에서 같은 자리를
  확인, KU-M1)"로. 주석만이라 terminal의 동작은 그대로다.
- 확인: `git diff --stat`, 지운 줄은 `git diff | rg '^-'`로 읽는다. `make quick`.

## Task 2: 빌드와 크기

- `make kernel` 뒤 `make iso`(또는 `make initrd`). 로그에 `Downloading … linux-6.18.60.tar.xz`와 `sha256sum -c`의 `OK`가 찍히는지.
- 크기: `bzImage` · `initrd.cpio`의 바이트. 지난 값은 8,958,976 · 93,367,226(한 벌 약 102MB, KU design 확인 3). 두 벌이 1GiB ESP의
  빈 자리(첫 설치 뒤 968,904,704바이트, KU-M0 결과 2)에 들어가는지, 256MiB로 깔린 디스크의 문턱(한 벌 약 125MB, 위험 2) 아래인지.
  initrd는 커널과 무관해 거의 같을 것이고, `bzImage`만 수 KB 움직일 것으로 본다.
- 부팅 한 번: `make boot-qemu`의 로그에서 `Linux version 6.18.60`.

## Task 3: 루트 게이트

- `make gate`. 지난 회차 10분 26초에 커널 첫 빌드와 tarball 받기가 더해진다 — 약 12분으로 본다.
- 판정 바깥의 확인: 22/22, verify 줄 수(지난 8237)가 크게 다르지 않은지, dmesg 쪽 경고가 새로 늘었는지(어느 체인이든 `WARNING:` ·
  `BUG:`를 로그 전체에서 센다 — 지난 회차 로그 `out/gate-logs/20261101-130913/`와 비교).
- 통과하면 확정 10의 옛 소스를 지운다.

## Task 4: 닫기

KU 서브프로젝트가 이 milestone으로 끝난다.

- design `Status:` 줄. Milestone 절의 KU-M1 줄에 고른 버전과 이유 한 줄.
- `docs/guides/completed.md` 표 끝에 한 행.
- `docs/decisions/project_kernel_upgrade.md`(새로) — 슬롯 둘 · 1GiB ESP · 메뉴 3초 · pipefail 함정 · 6.18.60 · 7.4 LTS는 나온 뒤에 따로.
  `MEMORY.md` 한 줄. `docs/guides/carryover.md`에 "7.4 longterm이 지정되면 이동" 한 항목.
- 소개 페이지(`gh-pages`의 `data.js`) — `site/README.md`의 순서대로.
- `HANDOFF.md`.
- 버전을 낼지(0.1.4)는 사용자에게 묻는다. 내면 `project_release.md`의 일곱 단계.

## 하지 않는 것

1. 7.x 이동. 7.4가 longterm으로 지정된 뒤 새 milestone이나 서브프로젝트로 연다. 그때는 `KERNEL_MAJOR`가 `7.x`가 되고, config diff가
   크며, 툴체인 최소 버전과 iwlwifi API_MAX를 다시 본다(이번 확정 4~6을 같은 방법으로).
2. config 다듬기. 새 옵션을 켜거나 끄지 않는다. olddefconfig의 결과만 받는다.
3. 게이트가 old 슬롯에 옛 커널이 있는 상태를 보는 판정. install 체인은 같은 ISO로 두 번 깔므로 두 슬롯의 커널이 같다. 서로 다른 버전의
   두 슬롯은 실기에서 사용자가 본다.

## 결과

2026-11-01.

1. Task 1. 바뀐 파일 다섯, +20 −26. `make quick` PASS(31초). 이어 붙인 주석 두 자리가 한 줄로 길어져 두 번 다시 접었다 — 지운 줄을
   `git diff | rg '^-'`로 읽는 것과 함께 더한 줄도 읽어야 잡힌다.
2. Task 2. `make iso` 411초(커널 처음부터). `sha256sum -c`가 `OK`, 빌드 스탬프가 버전 변경을 보고 make를 다시 불렀다(`bzImage is ready
   (#2)`, 확정 8). `warning:` 줄은 없다.

   | | 6.18.42 | 6.18.60 | 차이 |
   | --- | --- | --- | --- |
   | `bzImage` | 8,958,976 | 8,983,552 | +24,576 |
   | `initrd.cpio` | 93,367,226 | 93,378,546 | +11,320 |
   | 한 벌 | 102,326,202 | 102,362,098 | +35,896 |

   두 벌 약 204.7MB는 첫 설치 뒤 1GiB ESP의 빈 자리 968,904,704바이트에 들고, 256MiB 디스크의 문턱(한 벌 약 125MB)보다 23MB 아래다.
   initrd가 커널과 상관없이 11KB 늘었는데 옛 initrd가 남아 있지 않아 원인을 보지 않았다. ISO 106,602,496바이트.
3. 부팅 한 번. `make run-qemu CONFIG_DISK= QEMU_DISPLAY="-display none"`(설정 디스크는 지난 게이트의 `clean()`이 지웠다). `Linux version
   6.18.60`, simpledrm 초기화, terminal의 `kms: present by dirtyfb`. 경고 둘(`fail to add MMCONFIG`, `Processor Platform Limit`)은 지난
   게이트(6.18.42) 로그에도 41 · 59개 파일에 있던 것이다. 함정 하나 — `perl -e 'alarm 90; exec @ARGV' make …`는 make만 끊고 QEMU는
   init(ppid 1)의 자식으로 남는다. 손으로 껐다.
4. Task 3. 루트 게이트 22/22, 10분 30초(prebuild 322 + lanes 306초), verify 8214줄. 로그 `out/gate-logs/20261101-140738/`.
   - 커널 첫 빌드가 들었는데도 prebuild가 지난 회차(320초)와 같다. tarball은 Task 2가 이미 받아 `kernel/src/`에 풀어 두었고(`clean()`은
     `kernel/build`만 지운다), 커널 빌드는 게이트마다 원래 처음부터였다. plan의 "약 12분" 어림이 틀린 이유다.
   - 로그 전체에 `Linux version 6.18.60`이 61번이고 다른 버전은 없다. `] WARNING:` · `] BUG:` · `Oops` · `Kernel panic` · `Call Trace`는
     0이다.
   - 지난 회차와의 dmesg 비교는 못 했다. `clean()`이 `out/`을 통째로 지우므로 `out/gate-logs`에는 마지막 회차만 남는다 — Task 2의
     경고 대조는 게이트 전이라 지난 로그가 있었다. 다음에 비교가 필요하면 게이트 전에 그 디렉터리를 scratch로 옮긴다.
   - verify 합계는 ER-M0 닫기 8218 → KU-M0 8237 → 이번 8214로 회차마다 움직인다. 체인별 지난 값이 남아 있지 않아 어느 체인이 23줄
     적은지는 가리지 못했다. 판정은 전부 통과했다.
5. 확정 10대로 `kernel/src/linux-6.18.42`(1.6GB, `.gitignore`의 `kernel/src/`)를 지웠다.
