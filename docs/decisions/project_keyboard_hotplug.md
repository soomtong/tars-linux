---
name: project_keyboard_hotplug
description: "키보드 핫플러그(KH-M0~M2, 2026-11-02) — terminal이 키보드를 포인터의 길(처음 훑기 + uevent)로 스스로 열고, 여럿이 key_state 하나를 같이 쓰고, 빠지면 fd를 닫고 releaseHeld. 함정 — 키보드 fd의 POLLERR를 안 보면 CPU 하나를 다 쓴다, QMP input-send-event의 device는 화면 장치다, 커널이 해제 때 뗌을 흉내 내 보내서 releaseHeld를 빼도 보통은 안 보인다"
metadata:
  node_type: memory
  type: project
---

# Keyboard Hotplug (KH)

design은 `docs/specs/2026-11-02-tars-keyboard-hotplug-design.md`, plan은 `docs/plans/2026-11-02-tars-keyboard-hotplug-kh-m0.md` ·
`-m1.md` · `-m2.md`. BT를 닫은 자리에서 첫 후보로 둔 것을 사용자가 골랐다(BT 키보드가 페어링은 되는데 글자를 못 쳤다). 여러
키보드를 함께 쓰는 시나리오 검토(S1~S13)는 사용자가 요청해 design에 절로 들어갔다.

## 무엇이 섰나

- terminal이 키보드를 스스로 찾는다. `tryOpenInput`이 노드를 한 번 열어 성질을 묻고 `takePointer` · `takeKeyboard`로 칸을 가른다.
  키보드이자 포인터인 노드는 `open`을 두 번 한다(`dup`은 이벤트 큐를 나눠 빼앗는다). 판정은 init과 같은 기준(`EV_KEY` +
  `KEY_ESC`~`KEY_D`)의 `pointer.looksLikeKeyboard`.
- 키보드 칸 여덟, fd는 `O_NONBLOCK | O_CLOEXEC`에 `CLOCK_MONOTONIC`(tap 판정이 장치를 건너도 같은 시계).
- `input.State`는 하나를 모든 키보드가 같이 쓴다 — 한/영 · 조합 · CapsLock · copy mode는 사람 하나의 것이고 수정키도 합친다(X11 ·
  macOS와 같다). 빠지면 `closeKeyboard`가 `releaseHeld`(수정키 여덟 · tap 둘 · 받아쓰기 탭)를 부른다.
- argv의 `device_path`는 읽기만 한다. `terminal: opened` 줄과 `FATAL` 갈래가 없어졌고 키보드가 0개여도 뜬다(`keyboard> none`).
  init의 고르기와 3초 기다림은 그대로다(비목표 2, `carryover.md`).
- 로그 `terminal: keyboard> open|close|skip|none|clock`. `pointer>` 줄은 키보드 노드에서도 그대로(`pointer/check.sh`가 본다).
- 체인 스물넷째 `keyboard/check.sh` — PS/2를 끈 q35에 키보드 없이 부팅, k1은 HMP `sendkey`, k2는 화면에 묶어 QMP로.

## 배운 것 — 다시 조사하지 말 것

- 키보드 fd의 `POLLERR` · `POLLHUP`을 안 보면 부팅 키보드를 뺀 순간 terminal이 1초에 약 100틱을 쓰고 로그는 조용하다(KH-M0 실측 4).
  PD가 포인터에 대해 적어 둔 함정이 키보드에 열려 있었다.
- QEMU: `sendkey`는 화면에 안 묶인 키보드 중 마지막에 꽂은 것으로 간다. QMP `input-send-event`의 `device`는 화면 장치라 키보드를
  `display=gpu`로 묶어야 하고(usb-kbd에 `head`가 없다), `-parallel none` 없이 `device`를 주면 QEMU가 abort한다(measurements 100 · 101).
- 커널은 장치를 해제할 때 눌린 키마다 뗌을 흉내 내 보낸다(`input_disconnect_device`). evdev의 죽은 표시 전에 terminal이 읽으면
  거기서 풀리므로 `releaseHeld`를 빼는 mutation이 "Shift를 쥔 채 빼기"를 지나쳤다. reader를 SIGSTOP한 채 빼야 `releaseHeld`만
  남는다(판정 7b, measurements 102).
- `input_test`의 검사 번호는 이미 겹쳐 있었다(84 · 85가 둘). 새 번호는 쓰인 것 가운데 가장 큰 수 뒤로.
- 셸 heredoc 안에 `<<'EOF'`를 품은 텍스트를 넣으면 바깥 heredoc이 그 줄에서 끝난다 — 끝 표식을 다르게 하거나 파일로 쓴다.

## 남은 것

`carryover.md`의 KH 절 — init의 3초 · `device_path`, 장치별 수정키(S5), 반복 섞임(S7) · 칸 순서(위험 7) · 두 노드(위험 6),
키보드마다의 `keyboard=`. 관련: [[project_pointer_devices]] · [[project_bluetooth]] · [[project_device_discovery]].
