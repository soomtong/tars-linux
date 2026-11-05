# LP-M2 — 밝기(F1 · F2)

> 구현은 lead가 직접 넣었다(2026-11-05). 사용자가 외출하며 남은 결정을 위임했다. 결과는 끝의 "결과" 절.

Goal: LP design 결정 5 · 6. 결정 7(`tars.conf`의 `brightness=`)은 비목표로 옮겼다(아래 확인 2).

## 할 일

1. `terminal/src/backlight.zig`(순수) — `rank`(raw 0 · platform 1 · firmware 2), `pick`(순위, 같으면 이름), `parseLevel`, `step`(16단계, 단계 k =
   round(max·k/16) ≥ 1, 값이 바뀌는 단계까지 건너뛴다, 0에서 올리면 첫 단계). `backlight_test`.
2. `input.zig` — `Action.brightness`, `brightnessKey`(밝기 키 둘 + Apple 칸의 F1 · F2), `handleKey`의 switch 앞(모드 · 수정키보다 먼저),
   `Keys.brightness`(순증감).
3. `main.zig` — 밝기 절(`scanBacklight` · `stepBacklight`), 첫 밝기 키에서 훑는다. 로그 `terminal: backlight> pick=… of N` ·
   `backlight> <이름> <전> -> <후> of <max>`.

## 확인한 것

1. terminal은 원래 F1~F12를 앱에 안 보낸다(`input_test`의 "특수키 사이의 빈 코드(F1 등)는 조용히 무시된다"). Apple 칸의 F1 · F2를 밝기로
   써도 앱이 잃는 것이 없다. 그 검사는 PC 칸(`swap_alt_meta = true`)으로 옮겼다 — 지키는 뜻이 "PC 키보드의 F1은 조용하다"라서.
2. `brightness=` 키는 `touchpad_accel` 하나가 지나는 자리(config.zig 파싱 · seed · reload.zig · init main · screen_args ARGC · 테스트 넷)를
   다 지난다. 얻는 것은 부팅 때의 시작 밝기 하나라 이번에는 안 한다(Claude 결정, 위임) — design 비목표 4에 합쳤다.
3. Apple 칸 = `!swap_alt_meta`. 그 값은 칸을 열 때 `kind == .pc`로 정해진다(KK) — 새 칸을 안 더했다.
4. 배터리 절의 주석 "커널에 `SUSPEND`가 없어서 잠든 시간은 따질 일이 없다"가 LP-M0부터 틀렸다. `.awake` 시계는 자는 동안 멈춰 깨어난 뒤
   최대 60초 칸이 옛 값일 수 있다 — 주석을 사실로 고치고 design 위험 6에 적었다(깨어날 때 ACPI 배터리의 uevent가 보통 다시 훑게 한다).

## 결과

- `backlight_test` · `input_test`(밝기 여덟 경우) 통과, terminal 빌드.
- QEMU에 백라이트가 없어 게이트는 키 갈래와 산수까지다. 실제 패널(`intel_backlight`의 max, 단계의 느낌)은 실기.
- 루트 게이트 30/30(M1 · M2 함께, 새 체인 `sleep` 14초), 17분 28초, 잘린 줄 0.
