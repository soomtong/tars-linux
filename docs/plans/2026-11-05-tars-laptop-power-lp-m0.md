# LP-M0 — i915 · PM · SUSPEND

> 구현은 lead가 직접 넣었다(2026-11-05, 사용자 요청 "절전 · 밝기"). 줄 번호는 `b13a0be` 기준이라 낡을 수 있다. 결과는 끝의 "결과" 절.

Goal: LP design 결정 1 · 2. 커널만 — 뚜껑 · 밝기 코드는 M1 · M2.

## 할 일

1. 고정점 확인 — `kernel/.config`와 `build/.config`가 같다(같았다).
2. `scripts/config -e PM -e SUSPEND -e DRM_I915` → `build.sh` → `build/.config`로 되접고 다시 빌드해 diff가 빈다.
3. 음성 검사 찾기 — 새로 켜진 50개 심볼로 `*/check.sh`를 찾는다.
4. `machine` 체인 정적 검사 — 심볼 다섯과 맥 GPU 넷의 i915 표 줄.
5. 루트 게이트.

## 확인한 것

1. `olddefconfig`가 `=y` 47줄을 더했다(design 확인 2). 지운 줄은 `is not set` 일곱(`RELAY` · `SUSPEND` · `PM` · `DRM_I915` ·
   `BACKLIGHT_CLASS_DEVICE` · `X86_PLATFORM_DEVICES` · `TMPFS`)뿐.
2. bzImage 9,819,136 → 11,355,136 B(+1,536,000, +15.6%). 증분 빌드 187초(i915와 따라온 것만 컴파일).
3. i915 표에 `8086:0116` · `0166` · `0A2E` · `0D26`이 있다.
4. 음성 검사 하나가 걸렸다 — `audio` 체인이 `SND_HDA_I915`가 꺼져 있기를 요구한다(AU-M3). i915가 그것을 `select`하므로(프롬프트 없음)
   끌 수 없다. 6.18의 `snd_hdac_i915_init`은 Intel 디스플레이가 있는데 컴포넌트가 안 묶였으면 `-EPROBE_DEFER`를 돌려준다 — i915가
   맡지 않는 GPU(Lunar · Panther Lake, `xe` 몫)에서는 영영 안 묶여 HDA · SOF 카드가 안 선다. `snd_hda_core.gpu_bind=0`이면
   `i915_gfx_present()`가 거짓이라 지금까지의 `-ENODEV` 길 그대로다. 내장 `CONFIG_CMDLINE`에 더하고, audio 체인의 음성 검사를 그
   cmdline 검사로 바꿨다. 잃는 것은 HDMI 오디오뿐이고 지금도 없다(`carryover.md`의 그 줄은 그대로 남는다).
5. 첫 루트 게이트가 빨갰다 — 29 가운데 18(dhcpcd 임대 · 설치기 · 클립보드 · vim · git · bluetoothctl · mise, 문구가 제각각).
   공통 원인은 로그 곳곳의 `No space left on device`였다(fish의 `//.config/fish/fishd.tmp…`, mise의 tar). i915가 `TMPFS`를
   select하면 initramfs의 rootfs가 ramfs에서 tmpfs로 바뀌고(`init/do_mounts.c`의 `init_rootfs` — `rootfstype=`가 없으면 tmpfs) tmpfs의
   기본 상한이 RAM의 절반이라 512MB 게스트가 256MB에서 찬다. 내장 cmdline에 `rootfstype=ramfs`를 더해 rootfs를 전처럼 둔다. init은
   tmpfs를 따로 붙이지 않는다(주석의 "tmpfs"는 rootfs를 느슨하게 부른 말이다). `machine` 체인이 그 cmdline을 본다 — 빠지면 열여덟
   체인이 엉뚱한 문구로 빨개지는 대신 이름이 붙은 한 줄로 먼저 잡힌다. tools 체인 하나로 다시 재서 PASS · `No space left` 0.

## 결과

- 루트 게이트 둘째 판 29/29, 17분 25초(첫 판은 위 5의 18 빨강). `CONFIG_PM`의 런타임 PM이 QEMU의 USB 키보드 · 마우스 체인
  (keyboard · pointer · input)을 흔들지 않았다 — design 위험 3은 실기의 USB에 남는다.
