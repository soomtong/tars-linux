---
name: project_device_modifiers
description: "Device Modifiers(DM-M0~M1, 2026-11-04 끝남) — 수정키 여덟과 tap 둘을 키보드 칸마다 들고(읽기는 OR), 빠진 키보드는 그 칸만 푼다. 겹친 tap 키의 누름은 소비로 시작한다. 함정 — 커널 자동 반복이 쥔 수정키 비트를 다시 켜 결함을 가린다, 판정은 같은 장치의 다른 키를 떼 반복을 멈춘 뒤 본다"
metadata:
  node_type: memory
  type: project
---

# Device Modifiers (DM)

design은 `docs/specs/2026-11-04-tars-device-modifiers-design.md`, plan은 `docs/plans/2026-11-04-tars-device-modifiers-dm-m0.md` ·
`-dm-m1.md`. `carryover.md` KH 절의 둘째 항목(KH 비목표 5, 시나리오 S5)이었다. 사용자가 IK 다음으로 골랐고, M0부터 닫기까지를
Claude에게 맡기고 외출했다(2026-11-04).

## 사용자가 정한 것 (2026-11-04)

design의 결정 1~7을 추천안 그대로. 겹친 tap 키의 누름은 처음부터 소비(결정 2)와 그 판정 10을 둔다. 키보드별
`keyboard=apple|pc`는 범위 밖(비목표 1).

## 결정

- `input.State`의 수정키는 `mods: [MAX_KEYBOARDS]Mods`(`packed struct(u8)`), tap은 `taps: [MAX_KEYBOARDS]Taps`. 읽는 자리는 모두
  `anyMods()`(OR)를 거친다 — 장치를 건너는 조합(KH 결정 3)은 그대로다.
- 칸 번호는 `Context.device`. `main.zig`의 키보드 칸 번호(`readKeyboards`의 `ki`)를 그대로 싣는다. `MAX_KEYBOARDS`는
  `input.zig`가 정하고 `main.zig`는 별칭이다.
- 소비(`markTapConsumed`)는 칸을 건넌다. 빼는 것은 같은 칸의 같은 키뿐이다. 다른 칸이 같은 tap 키를 쥐고 있을 때의 누름은
  `consumed`로 시작한다 — 키보드가 하나면 생길 수 없는 경우라 단일 키보드 동작은 안 바뀐다.
- `releaseDevice(slot)`은 그 칸만 처음으로. 받아쓰기 더블 탭(하나다)은 그 칸이 오른쪽 Meta를 쥐었을 때만 버린다.

## 함정

1. 커널 input core는 장치마다 마지막에 누른 키를 250ms 뒤부터 33ms마다 value=2로 반복하고, 수정키도 반복한다. `handleKey`가
   `bit = value != 0`이라 반복이 지워진 비트를 다시 켠다. 그래서 M0의 첫 판에서 판정 8 · 9가 고치기 전 코드에서도 초록이었다.
   같은 장치에서 아무 키나 떼면 반복이 멈춘다(`input_stop_autorepeat`) — 체인의 `stop_repeat`이 오른쪽 Ctrl을 눌렀다 뗀다.
   수정키 상태를 보는 판정을 새로 쓸 때는 이 반복을 먼저 생각한다.
2. 실기에서 결함이 드러나는 모양도 그래서 "Shift를 쥔 채 그 키보드로 다른 키를 하나 친 뒤"다.
3. 고칠 결함을 체인에 먼저 붙박은 M0(지금 코드에서 빨강)은 `report_failure`가 첫 빨강에서 끝내므로, 셋을 한 판에 보려면 실패를
   `echo`로 바꾼 일회용 사본이 필요했다(같은 디렉터리에 두고, 끝나면 지운다).
4. 체인의 새 판정에 `… | grep -aq`를 쓰면 루트 게이트 진입 검사가 막는다(SIGPIPE + `pipefail`, GA-M0). `make quick`은 이것을
   안 보므로 체인 하나만 돌려서는 모른다 — `grep -a … >/dev/null`로 쓴다.

숫자는 design의 실측 1~5(5가 루트 게이트 27/27). 관련: [[project_keyboard_hotplug]] · [[project_init_keyboard]].
