# KH-M2 — 체인 `keyboard/check.sh`, mutation, 닫기

> 체인은 Claude(또는 서브에이전트)가 쓰고, lead가 대조 · 게이트 · commit한다. 이 plan은 KH-M1의 루트 게이트가 도는 동안
> 썼다 — 게이트 결과로 바뀌는 자리가 있으면 구현 전에 고친다(CLAUDE.md의 "Milestone 단위 작업").

Goal: design 결정 8의 일곱 단계를 스물넷째 체인으로 세우고, mutation 셋이 각각 잡히는지 보고, 루트 게이트 24/24 뒤에
서브프로젝트를 닫는다.

## Task 1: 체인

`keyboard/check.sh`. 모양은 `pointer/check.sh`(`-kernel` 직접 부팅 · `gate_lib.sh`)를 따르고, 기계는 `machine` 체인처럼 PS/2를 끈다.

- QEMU: `-machine q35,i8042=off` · `-parallel none` · `-vga none -device virtio-gpu-pci,id=gpu` · `-device qemu-xhci,id=xhci` ·
  `-monitor tcp:127.0.0.1:45495` · `-qmp tcp:127.0.0.1:45496` · 설정 디스크(아래). 부팅 때 키보드는 없다.
- 설정 디스크: `tars.conf` 빈 파일, `kh-cpu` 스크립트 하나 — terminal의 `/proc/<pid>/stat` utime + stime을 1초 간격으로 두 번
  찍는다(`kh-cpu: ticks A B`). 셸에서 `/config/kh-cpu` 한 단어로 친다. 디스크는 `debugfs write`로 채운다(SV 체인과 같다).
- QMP 도우미 `qmp_key <dev|-> <qcode> <true|false>` — `-`면 `device` 없이(묶이지 않은 k1로), `gpu`면 k2로(실측 2). 접속 뒤
  `qmp_capabilities`를 한 번. `gate_lib.sh`에 넣을지는 쓰는 체인이 둘째가 될 때 정한다. 지금은 체인 안에 둔다.

판정(결정 8 · 아래 7은 이 plan이 더한다):

1. `terminal: keyboard> none`이 있고 `screen>`이 나온다. `terminal: opened`는 없다.
2. `device_add usb-kbd,bus=xhci.0,id=k1` → `keyboard> open /dev/input/eventN name=QEMU QEMU USB Keyboard`. `type_keys`로
   `echo kh1` → 화면에 `kh1`이 명령줄과 출력에 한 번씩(`project_gate_screen_echo`). 같은 글자가 세 번이면 두 번 열린 것이다(위험 5).
3. `device_add usb-kbd,bus=xhci.0,id=k2,display=gpu` → 둘째 `open`. QMP `gpu`로 `echo kh2` 한 줄. 이어서 `type_keys`로 `echo kh3`.
   둘 다 화면에 나온다.
4. 장치를 건너는 조합. QMP `gpu` Shift 누름 → QMP `-` `a` 누르고 떼기 → QMP `gpu` Shift 뗌 → `ret`. 화면의 프롬프트 뒤에 `A`.
5. 장치를 건너는 한글. 한/영 키는 `hangul/check.sh`가 쓰는 것을 따른다. k1로 켜고 `r`(ㄱ) → k2로 `k`(ㅏ) → Space. 화면에 `가`.
   그다음 한/영을 끈다.
6. `device_del k2` → `keyboard> close /dev/input/eventM`. `type_keys`로 `/config/kh-cpu` → 두 수의 차가 30 미만(바쁜 루프면 약
   100, 실측 4).
7. 빠진 키보드의 Shift. `device_add … id=k2,display=gpu` 다시 → `open`. QMP `gpu` Shift 누름 → (뗌 없이) `device_del k2` →
   `close` → `type_keys`로 `echo x` `ret`. 화면에 `x`이고 `X`가 아니다(결정 4).

시간 상한은 `screen>` 120초, 단계마다 노드 생김 · 지움 5초, 화면 10초. init이 키보드를 3초 기다리므로 부팅이 다른 체인보다 3초
길다(실측 3).

`check.sh`의 `CHAINS` 끝에 `"KH-M2:./keyboard/check.sh"`. 진입 검사(`require_build_steps`)가 읽는 빌드 스텝 넷을 체인 머리에 둔다.

## Task 2: mutation 셋

각각 한 줄을 깨고 체인 하나만 돌려(`make chain CHAIN=keyboard`) 기대한 판정에서 빨개지는지 본다. 끝나면 되돌리고 `git diff`가 빈지 본다.

| | 깨는 것 | 잡혀야 하는 판정 |
|---|---|---|
| M-a | `tryOpenInput`이 키보드 칸에 안 넣는다(`looksLikeKeyboard`를 `false`로) | 2 |
| M-b | `readKeyboards`가 `POLLERR` · `POLLHUP`을 안 본다 | 6 |
| M-c | `closeKeyboard`가 `releaseHeld`를 안 부른다 | 7 |

M-b는 `POLLHUP`이 먼저 오는지 read가 `ENODEV`로 먼저 끝나는지에 따라 안 잡힐 수 있다 — 그때는 read 쪽(`gone`)도 함께 깨서
"둘 중 하나가 있으면 닫힌다"를 적는다.

## Task 3: 루트 게이트와 닫기

1. 루트 게이트 24체인(약 11분).
2. design: Status · M2 실측(체인 몇 판에 초록, mutation 결과, 게이트 시간) · 결정 8의 일곱째.
3. BT design 확인 7 · 비목표 1과 `carryover.md`의 BT 항목의 "BT 키보드는 아직 못 친다"를 고친다. 소개 페이지 · AU · VD 문서
   중 키보드 하나를 전제로 한 문장이 있으면 함께(`rg -n '키보드 하나'`).
4. `carryover.md`에 KH가 남긴 것: init의 3초 · `device_path` 칸(비목표 2), 장치별 수정키(S5), 반복 섞임(S7), 두 노드(위험 6).
5. `docs/guides/completed.md` 한 행, 소개 페이지(`gh-pages`의 `data.js`, 순서는 `site/README.md`), `docs/decisions/
   project_keyboard_hotplug.md` + `MEMORY.md` 한 줄, `HANDOFF.md`, `key-files.md`의 terminal 입력 줄.
