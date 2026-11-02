# KH-M0 — 고치기 전에 재고, 키 하나가 어느 장치로 가는지 본다

> 커밋되는 코드는 0줄이다. 하네스는 세션 scratchpad의 `kh/` 아래. 저장소에 들어가는 것은 design의 "실측 (M0)"
> 절과 이 plan이다.

Goal: design 위험 1(QEMU가 키를 어느 키보드로 주는가) · 위험 2(키보드 없는 부팅의 3초) · 확인 4(부팅 키보드를 뽑으면
바쁜 루프)의 답, 부팅 뒤에 꽂은 usb-kbd의 노드와 uevent 글자, 지금 게스트의 노드마다 결정 2의 판정을 잰다. 그리고 결정 8의
게이트 6(장치를 건너는 조합)을 QMP로 할 수 있는지 본다.

Architecture: M0에서는 terminal이 아직 부팅 뒤의 키보드를 안 읽는다. 그래서 게스트 셸에 명령을 칠 수 없다 — 관찰은 설정
디스크의 `services.d/kh` 스크립트가 하고 콘솔에 `kh-m0:` 줄로 찍는다(BT-M0 · WL의 모양). 호스트 하네스는 시리얼 로그에서
`kh-m0: ready <단계>` 줄을 기다렸다가 HMP(`sendkey` · `device_add` · `device_del`)와 QMP(`input-send-event`)를 보낸다. 디스크는
`mkfs.ext2` + `debugfs write`(SV 체인과 같다). 셋 다 `make iso`로 만든 지금 ISO를 쓴다.

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | 키보드 없는 q35 `i8042=off` 부팅에서 init의 `no keyboard found … in 3000ms` 줄, 부팅이 몇 초 늦는가, terminal이 연 `event0`의 이름 | 확인 1 · 위험 2 |
| 2 | 부팅 때 있는 `/sys/class/input/event*`마다 `name` · `capabilities/ev` · `capabilities/key`. 호스트에서 결정 2의 기준(`EV_KEY` + 1~32 전부)을 대 본 표 | 결정 2 · 위험 3 |
| 3 | `device_add usb-kbd,id=k1`가 만드는 노드의 수와 이름, 그 노드의 `uevent` 파일(`DEVNAME=input/eventN`), 꽂고 노드가 생기기까지의 시간 | 결정 1 · 확인 2 |
| 4 | 키보드가 둘 이상일 때 HMP `sendkey`가 어느 노드로 가는가 — 꽂기 전 · k1 뒤 · k2 뒤 · k2를 뺀 뒤 | 위험 1 |
| 5 | QMP `input-send-event`의 `device` 인자가 고른 장치로 가는가. k1에 Shift 누름, k2에 `a` 누르고 떼기, k1에 Shift 뗌이 순서대로 게스트에 오는가 | 결정 8의 6 · 시나리오 S2 |
| 6 | 부팅 때 꽂은 usb-kbd를 terminal이 연 상태에서 `device_del`하면 terminal의 CPU 시간이 1초에 얼마씩 느는가(전과 후) | 확인 4 |

## Task 1: 하네스

scratchpad `kh/`에:

- `probe.sh` — 게스트 `services.d/kh`가 될 스크립트(`#!/bin/sh`, 게스트의 sh는 bash). 하는 일:
  - 시작하면 측정 2의 표를 찍는다. 줄 모양은 `kh-m0: node event0 ev=… key=… name=…`.
  - 단계마다 `kh-m0: ready <단계>`를 찍고 `/sys/class/input`이 바뀌기를(또는 정해진 초를) 기다린다. 새 노드가 생기면 그 노드의
    `name` · `uevent`, 그리고 `ready`부터 몇 ms 뒤에 보였는지를 찍는다(측정 3).
  - 측정 4 · 5의 단계에서는 `event*` 노드마다 `head -c 24 /dev/input/eventN > /tmp/kh.N &`로 첫 이벤트 하나를 받는 reader를
    띄운다. 하네스가 키를 보낸 뒤 2초 기다렸다가 reader마다 받은 바이트 수를 `kh-m0: got eventN bytes=…`로 찍는다. 24바이트가
    `input_event` 하나다. evdev는 fd마다 따로 내주므로 terminal이 같은 노드를 읽고 있어도 reader의 몫이 줄지 않는다.
  - 측정 5에서는 `head -c 24`가 아니라 k1 · k2 노드에서 이벤트 여럿을 받고, 받은 바이트를 `cat -v`로 찍는다. 순서와 type ·
    code · value를 호스트에서 푼다(게스트에 `od`가 없다 — measurements 80).
  - 측정 6에서는 `/proc/*/comm`으로 terminal의 pid를 찾고, `/proc/<pid>/stat`의 utime + stime(14 · 15번째 칸)을 1초마다 다섯 번
    찍는다 — `device_del` 앞과 뒤에.
- `run.sh` — 부팅 하나를 띄우고 로그를 따라간다. HMP는 `-monitor tcp:127.0.0.1:45590`(probe 포트, 체인 범위 밖), QMP는
  `-qmp tcp:127.0.0.1:45591`. QMP는 `qmp_capabilities`를 먼저 보낸 뒤에 명령이 먹는다. 둘 다 bash `/dev/tcp`로 연다(체인과 같다).
- 디스크: `mkfs.ext2` 뒤 `debugfs write`로 `tars.conf`(빈 파일) · `services.d/kh`(실행 비트는 호스트의 `chmod +x`).

## Task 2: 부팅 A — 키보드 없는 q35

`-machine q35,i8042=off` · `qemu-xhci` · 설정 디스크, 키보드 없음. 측정 1 · 2를 보고, 이어서:

1. `device_add usb-kbd,bus=xhci.0,id=k1` → 측정 3.
2. `sendkey a` → 측정 4(키보드가 k1 하나뿐일 때 — 이것은 반드시 k1이다. reader가 제대로 도는지를 여기서 확인한다).
3. `device_add usb-kbd,bus=xhci.0,id=k2` → 측정 3 다시, 그리고 `sendkey a` → 측정 4.
4. QMP `input-send-event` `device: k1`으로 `a`, 그다음 `device: k2`로 `a` → 측정 5의 앞 절반(고른 장치로 가는가).
5. k1 Shift 누름 → k2 `a` → k1 Shift 뗌 → 측정 5의 뒤 절반(순서).
6. `device_del k2` 뒤 `sendkey a` → 측정 4(뺀 뒤에는 어디로 가는가).

판정: 측정 1에서 부팅이 3초 늦다는 것이 로그의 커널 시각으로 보인다. 측정 4의 첫 단계에서 k1이 24바이트를 받는다. 나머지는
보이는 대로 적는다 — 결정을 바꾸는 값이다.

## Task 3: 부팅 B — PS/2가 있는 pc

체인 대부분이 쓰는 기계다(PS/2 키보드가 늘 있다). 꽂기 전 · `device_add usb-kbd,id=k1` 뒤 · `device_del k1` 뒤에 `sendkey a`가
어느 노드로 가는지(측정 4). 이 답이 다른 체인을 건드리는지 정한다 — 앞으로 PS/2 기계에 usb-kbd를 꽂는 체인이 생기면 그
체인의 `sendkey`가 어디로 가는가.

## Task 4: 부팅 C — 부팅 키보드를 뽑는다

`-machine q35,i8042=off` · 부팅 때 `-device usb-kbd,bus=xhci.0,id=k0`. init이 k0을 고르고 terminal이 연다(`machine` 체인과
같은 기계). 측정 6: 5초 동안 CPU 시간을 찍고, `device_del k0`, 다시 5초. 바쁜 루프면 뒤의 5초 동안 1초에 100틱 가까이 는다
(`CLK_TCK` 100). 그 뒤에 terminal 로그가 무엇을 찍는지(아무것도 안 찍는다고 보고 있다)도 본다.

## Task 5: 기록하고 커밋한다

design에 "## 실측 (M0, 2026-11-02)"을 더하고, 값에 따라 바뀌는 결정을 고친다. 바뀔 수 있는 자리는 다음과 같다.

- 위험 1의 답이 결정 8의 2 · 3 · 5를 정한다.
- 측정 5가 안 되면 게이트 6을 뺀다.
- 측정 2에서 키보드로 판정되는 노드가 생각보다 많으면 결정 2 · 위험 3을 고친다.
- 측정 6이 바쁜 루프가 아니면 확인 4를 고친다.

그다음 M1 plan을 쓴다. 커밋은 design + 이 plan + M1 plan이다. 하네스는 scratchpad에 남고 커밋하지 않는다. 재연이 필요한 것은
실측 절에 명령으로 적는다.

## 시간

부팅 셋, 각 1~2분, 그리고 하네스를 맞추는 시간. ISO가 지금 것이 아니면 `make iso`가 먼저다(prebuild 약 5분).
