# TARS Laptop Power — Design

접두사: LP

Status: 닫힘(2026-11-05) — LP-M0 i915 · PM · SUSPEND(+`gpu_bind=0` · `rootfstype=ramfs`), LP-M1 뚜껑 · `sudo suspend` · 체인 `sleep`, LP-M2 Apple F1 · F2 밝기. 실기 확인이 남았다.

사용자의 요청(2026-11-05): "맥북 에어에서 본격적인 사용기를 시작하려 한다. 그 전에 맥북의 절전(뚜껑 닫기) 기능을 활성화해주세요.
맥북의 내장 모니터 밝기 조절 기능을 활성화 해주세요. 추가로 안되는 것이라고 적은 문서 갱신까지 완료해주세요."

관련 문서: RM design 결정 3(i915를 안 켠다 — 이 design이 뒤집는다), MB design 비목표 2(밝기 · 절전), PM design(PID 1의 전원 갈래),
RB design(`shutdown` 스크립트), KK design(keyboard 종류), HD design(전원 버튼을 PID 1이 연다).

## 한 줄 요약

`DRM_I915` · `PM` · `SUSPEND`를 켠다. PID 1이 뚜껑 닫힘과 `sudo suspend`에 S3로 잠들고, terminal이 Apple 키보드의 F1 · F2(와 어느 키보드든
밝기 키)로 `intel_backlight`를 16단계로 움직인다.

## 확인 (2026-11-05, `b13a0be`, 커널 6.18.60)

1. 지금 `.config`는 `# CONFIG_DRM_I915 is not set` · `# CONFIG_PM is not set` · `# CONFIG_SUSPEND is not set` · `BACKLIGHT_CLASS_DEVICE`
   꺼짐, `ACPI_BUTTON=y`(뚜껑 이벤트는 이미 온다). 화면은 simpledrm이 펌웨어의 GOP를 그대로 쓴다(RM 실측 3).
2. 시험 켜기(`scripts/config -e PM -e SUSPEND -e DRM_I915` → `olddefconfig`)의 diff는 50줄이다. 의도한 것: `ACPI_SLEEP` · `PM_SLEEP` ·
   `BACKLIGHT_CLASS_DEVICE` · `ACPI_VIDEO` · `SND_HDA_I915`. 따라오는 것: `TMPFS` · `DRM_TTM` · `DRM_BUDDY` · DP/HDMI helper · `MMU_NOTIFIER` ·
   `FREEZER` · `PM_CLK` · `BLK_PM` · `ACPI_WMI` · `X86_PLATFORM_DEVICES` 등.
3. MacBookAir4,1은 Intel HD 3000(Sandy Bridge), MacBookPro11,x는 Haswell. 둘 다 i915가 firmware(GuC · DMC) 없이 돈다.
4. 밝기: 패널 PWM은 GPU 레지스터에 있고 리눅스에서 그것을 `/sys/class/backlight/intel_backlight`(type `raw`)로 여는 것이 i915다.
   `apple_bl`은 2011년 전 기종용이다. 맥의 ACPI `_BCM`(`acpi_video0`, type `firmware`)은 흔히 안 듣는다.
5. 절전: 맥 펌웨어는 S3에서 깨어날 때 화면을 다시 세우지 않는다(simpledrm만으로는 검은 화면이 남는다) — GPU를 다시 세우는 것이 i915다.
6. terminal은 root로 돌고(셸에게만 사용자 uid를 준다) `/dev/dri/card0`을 고정으로 연다. i915가 simpledrm을 밀어내면 비어 있는 가장 낮은
   번호(`card0`)를 받을 것이다 — 실기가 본다(위험 1).
7. 맥 내장 키보드의 윗줄을 밝기 키로 바꾸는 것은 커널의 `hid-apple`이고 TARS는 그것을 끈다(KK 비목표 2). 그래서 윗줄은 F1~F12로 온다.
   PC 키보드의 밝기 키는 `KEY_BRIGHTNESSDOWN`(224) · `KEY_BRIGHTNESSUP`(225)다.
8. PID 1은 `KEY_POWER`를 가진 키보드 아닌 장치를 열어 감독 루프에서 poll한다(`devices.looksLikePowerButton` · `drainButton`). 뚜껑은
   ACPI의 "Lid Switch" 장치가 `EV_SW`의 `SW_LID`(0)로 낸다.
9. QEMU는 S3를 지원한다(`-global ICH9-LPC.disable_s3=0`, q35). 깨우기는 monitor의 `system_wakeup`. 뚜껑과 백라이트는 QEMU에 없다.

## 결정

1. `DRM_I915=y`, `PM=y`, `SUSPEND=y`. 따라오는 것은 되접기 그대로 둔다. `DRM_AMDGPU`는 그대로 끈다. RM 결정 3은 사용자 결정으로 뒤집혔다
   (2026-11-05) — 그 근거 셋(필요 없다 · 게이트가 못 본다 · 빌드 비용) 가운데 첫째가 이 요청으로 사라졌다.
1a. 내장 cmdline에 둘을 더한다(LP-M0에서 드러났다). `snd_hda_core.gpu_bind=0` — i915가 `SND_HDA_I915`를 select하면 HDA · SOF가
   GPU 오디오 컴포넌트를 `-EPROBE_DEFER`로 기다리는데, i915가 맡지 않는 Intel GPU(Lunar · Panther Lake의 `xe`)에서는 영영 안 묶여
   소리가 사라진다. 0이면 지금까지의 `-ENODEV` 길이다(잃는 것은 지금도 없는 HDMI 오디오). `rootfstype=ramfs` — i915가 `TMPFS`를
   select하면 rootfs가 tmpfs(상한 RAM의 절반)로 바뀐다. 전처럼 ramfs로 둔다.
2. simpledrm은 남긴다. i915가 없는 기계(AMD · NVIDIA 단독)는 지금처럼 simpledrm이고, Intel 기계에서는 i915가 넘겨받는다(aperture).
3. 절전은 PID 1의 일이다. 들어오는 길 둘 — 뚜껑이 닫힘(0 → 1 전이만, 부팅 때 닫혀 있는 것은 아무것도 안 한다)과 `SIGUSR1`. 하는 일:
   sync → `/sys/power/mem_sleep`에 `deep`(있으면) → `/sys/power/state`에 `mem`(깨어날 때까지 막힌다) → 깨어난 뒤 한 줄
   (`tars-init: resumed after Nms`). 어댑터가 꽂혀 있어도 잔다(사용자 결정).
4. `sudo suspend` — RB의 `/usr/bin/shutdown`에 이름 `suspend`(→ `SIGUSR1`)를 더하고 링크 하나. 사용자로는 77과 `try: sudo suspend`.
5. 밝기는 terminal의 일이다. `/sys/class/backlight/*` 가운데 type `raw` → `platform` → `firmware` 순으로 하나를 고른다(systemd-backlight와 같은
   순서). 16단계, 가장 낮은 단계는 0이 아니라 1단계(꺼진 화면을 고장으로 오해하지 않게).
6. 키: keyboard 종류가 `apple`인 키보드의 F1(어둡게) · F2(밝게)는 밝기가 된다(사용자 결정 — macOS의 기본 자리). 어느 키보드든
   `KEY_BRIGHTNESSDOWN` · `KEY_BRIGHTNESSUP`도 같다. PC 키보드의 F1 · F2는 그대로다. 앱이 잃는 것은 없다 — terminal은 지금 F1~F12를
   아예 내보내지 않는다(`input_test`의 "특수키 사이의 빈 코드(F1 등)는 조용히 무시된다", 2026-11-05 확인). 누른 채 두면 자동 반복으로
   계속 움직인다.
7. ~~`tars.conf`의 `brightness=`~~ — LP-M2에서 비목표 4로 옮겼다(Claude 결정, 사용자 위임). 부팅 때의 밝기는 펌웨어가 둔 값이고 F1 · F2로
   바꾼 값은 이번 부팅만이다.

## 판정

- LP-M0: `machine` 체인의 커널 표에 `DRM_I915` · `SUSPEND` · `BACKLIGHT_CLASS_DEVICE`, 게스트의 `/sys/power/state`에 `mem`. 루트 게이트 —
  `PM`의 런타임 PM이 QEMU의 USB 키보드 · 마우스 체인을 흔들지 않는지가 이 milestone의 본론이다.
- LP-M1: 새 체인 `sleep`(monitor 45503) — `sudo suspend` → 커널 `PM: suspend entry (deep)` · QEMU `info status`가 suspended → `system_wakeup` →
  `tars-init: resumed after` → 셸이 다시 답한다. `devices_test`가 `SW_LID` 비트맵으로 뚜껑 장치를 고른다(키보드 · 전원 버튼과 갈린다).
- LP-M2: terminal 단위 검사 — 고르는 순서, 단계 계산(최솟값 1단계, 값이 늘 바뀐다), 키 갈래(apple의 F1 · F2, 밝기 키, PC의 F1 · F2는
  그대로). 실제 패널은 실기.

## 비목표

1. 하이버네이트(디스크로). 스왑이 없다.
2. 키보드 백라이트(`applesmc`), 주변광 센서.
3. 유휴 시간 뒤 자동 절전 · 화면 끄기.
4. 밝기 값 저장(F1 · F2로 바꾼 값을 다음 부팅에)과 `tars.conf`의 시작 밝기. 설정 키 하나가 config · reload · screen_args · 테스트 넷을 지나는
   데 비해 얻는 것이 시작 밝기 하나다(LP-M2 plan 확인 2).
5. 외부 모니터 · 모드 바꾸기. i915가 길은 열지만 terminal은 지금처럼 card0의 첫 출력 하나다.
6. GPU 전환(`apple-gmux`, MacBookPro11,3의 NVIDIA).

## 위험

1. i915가 `card0`이 아닌 번호를 받으면 terminal이 화면을 못 연다(확인 6). 실기 첫 부팅이 본다. 그러면 terminal이 `/dev/dri`의 첫 카드를 고른다.
2. 깨어난 뒤 brcmsmac(Air 무선)이 다시 안 붙을 수 있다. 그러면 `tars-config reload`나 PID 1이 깨어난 뒤 무선을 다시 띄우는 것이 다음 일이다.
3. `CONFIG_PM`으로 USB 장치의 자동 절전이 켜진다 — 키보드 첫 키가 깨우기에 먹히는지 실기에서 본다. 게이트는 QEMU의 USB 장치를 본다.
4. 맥의 ACPI가 `deep`을 안 내놓으면(`mem_sleep`에 `s2idle`뿐) 절전이 얕다. 로그 `tars-init: suspend (s2idle)`로 드러난다.
5. 뚜껑을 닫은 채 깨어나면(USB 장치가 깨움) 다시 자지 않는다. 거슬리면 깨어난 뒤 뚜껑 상태를 읽는다.
6. terminal의 배터리 주기는 `.awake` 시계라 자는 동안 멈춘다 — 깨어난 뒤 최대 60초 칸이 옛 값일 수 있다. 깨어날 때 ACPI 배터리의 uevent가
   보통 다시 훑게 한다. 실기에서 칸이 오래 옛 값이면 깨어난 뒤 한 번 훑는 것이 다음 일이다.
7. bash · zsh · fish에 내장 `suspend`가 있다 — sudo 없이 치면 셸이 멈춘다. 가이드가 "언제나 `sudo suspend`"라 적는다(LP-M1 plan 확인 1).

## Milestone

- LP-M0 — 결정 1 · 1a · 2. 커널만. lead 직접.
- LP-M1 — 결정 3 · 4. PID 1 · 스크립트 · 체인 `sleep`. lead 직접.
- LP-M2 — 결정 5 · 6. terminal. lead 직접.
- 닫을 때: `running-tars.md` "안 되는 것" 표의 두 줄, MB design 비목표 2, RM design 결정 3, `carryover.md`의 HDMI 오디오 줄, `project_macbook_hardware`.
