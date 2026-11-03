# IK-M0 — init의 키보드 고르기 · 3초 · argv의 장치 칸을 걷는다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-03
> `273298d` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: IK design 결정 1~4. 끝나면 PID 1은 키보드를 찾지도 기다리지도 않고, terminal argv는 아홉 칸이며, 체인 넷은 terminal의
`keyboard> open` 줄과 init 줄의 부재로 판정한다. 키보드 없는 부팅에서 `Run /init` → `started terminal`이 약 3초 줄어든 것이 design
"실측"에 남는다.

Architecture: 지우는 일이 대부분이다. 층은 넷 — init(`devices.zig` · `main.zig` · 주석), 공용 계약(`shared/screen_args.zig`와 그 검사),
서비스 argv 상수 다섯(길이만), 체인 넷과 `lessons.md`. terminal은 주석 하나만 바뀐다(`readArgs`).

## 착수 전에 확인한 것 (2026-11-03)

design 확인 1~4가 전부다. 덧붙일 것:

- `Args`에는 기본값이 없어서 init이 `.device_path`를 남기면 컴파일이 막히고, `ARGC`를 쓰는 배열 리터럴 다섯도 길이가 틀리면
  막힌다. 지우기를 컴파일러가 따라와 준다.
- `shared/screen_args_test.zig`가 `device_path`를 다섯 자리에서 쓴다 — `Args`를 짓는 둘, 되돌림을 비교하는 셋.
- init의 `zig build test`는 macOS에서 안 끝난다 — 컨테이너에서 돈다(HANDOFF). `make quick`은 `screen_args_test`를 호스트에서 돈다.

## Task 0: 바꾸기 전의 측정(결정 4)

스크래치 스크립트(저장소 밖)로 컨테이너에서 두 부팅을 한 번씩 띄운다. 기계는 `keyboard` 체인의 것에서 monitor · QMP · 설정
디스크를 뺀 모양이다(`-machine q35,i8042=off`, `-kernel` · `-initrd`, `-device qemu-xhci`, `-serial file:`).

- A: 키보드 없음.
- B: `-device usb-kbd,bus=xhci.0`를 더한다.

호스트가 로그를 0.05초마다 보며 `Run /init as init process`와 `tars-init: started terminal`이 처음 나타난 시각을 적고 그 차를 찍는다.
`terminal: screen>`이 나오면 끝낸다. 지금 빌드(`273298d`)로 A · B 각 세 번. 커널 줄의 `[    x.xxxxxx] Run /init`도 함께 적는다.

## Task 1: init(결정 1)

- `devices.zig`: 확인 1의 "걷는다"를 지운다. `MAX_EVENT` · `MAX_NAME` · `devicePath` · `readAttr`는 `openPowerButtons` ·
  `findPowerButtons`가 쓰므로 남는다. `KEYBOARD_WAIT_MS`의 머리 주석(RM-M3의 실측)은 지우되, 그 사실은 KH · RM 문서에 이미 있다.
  `openPowerButtons`의 "resolveKeyboard와 같은 이유" 주석은 이유 자체로 고쳐 쓴다.
- `main.zig`: `Boot.keyboard_path` 필드, 그 필드를 나열하는 주석(1161 근처), `probeDevices`의 호출, `encode`의 `.device_path` 줄,
  `Child.argv` 주석의 칸 이력(IK-M0에서 열에서 아홉으로), `reload terminal`의 SA-M1 주석(`device_path`는 이제 없다 — 안 바꾸는 칸은
  `user`뿐).
- `devices_test.zig`: `findKeyboard` · `resolveKeyboard(Waiting)` · `findKeyboardWaiting`의 검사를 지운다. `looksLikeKeyboard` ·
  `looksLikePowerButton` · 전원 버튼 검사는 남긴다. 지운 뒤 끝 줄(`all checks passed` 류)과 검사 개수를 맞춘다.
- `storage.zig` · `environ.zig` · `services.zig`의 주석이 인용하는 이름을 고친다 — 근거는 그대로 두고 예로 든 이름만 남는 것으로
  바꾼다(`findPowerButtons` 등). 뜻이 바뀌지 않게, 지우기보다 바꿔 쓴다.

## Task 2: argv 계약(결정 2)

- `shared/screen_args.zig`: `Slot.device` 줄과 그 주석을 지우고 뒤 다섯의 번호를 당긴다. `ARGC = 9`. `Args.device_path` ·
  `default_device_path` · `encode` · `decode`의 한 줄씩. `Args` 주석의 "포인터 셋"을 "포인터 둘"로. `decode` 주석의 "장치 경로가 그대로
  되돌아가는 것이…"(plan 확정 4)는 `user` 칸의 이야기로 바꿔 쓴다. `Slot` 위의 칸 역사 주석에 IK-M0 한 줄.
- `shared/screen_args_test.zig`: 다섯 자리를 지운다. 칸 수를 세는 검사가 있으면 9로.
- 서비스 argv 상수 다섯(`clock` · `net` · `wifi` · `bluetooth` 둘): null 하나씩.
- `terminal/src/main.zig` `readArgs`의 주석: 장치 칸이 IK-M0에서 없어졌다는 한 줄로.

## Task 3: 체인 넷과 `lessons.md`(결정 3)

- `device/check.sh`: 진입 목록(89 근처)의 `tars-init: keyboard device /dev/input/event`를 `terminal: keyboard> open /dev/input/event`로.
  판정(148 근처)을 `keyboard> open … name=` 있음 + `tars-init: keyboard device` · `tars-init: no keyboard found` 없음으로. 주석의 근거
  (design 결정 2 — 번호가 아니라 성질)는 terminal의 판정에도 그대로 맞으므로 남긴다.
- `terminal/check.sh`(324 근처): 같은 꼴. HD-M0 · HD-M1의 긴 주석은 "그 증명을 지금은 terminal의 줄이 진다"로 이어 쓴다.
- `machine/check.sh`(262 근처): `terminal: keyboard> open .* name=.*USB Keyboard` + init 줄 부재. 판정 6의 주석(커널 HID 층 · evdev ·
  탐색이 한 줄에)은 탐색의 주인만 바꿔 쓴다.
- `keyboard/check.sh` 판정 1: `no keyboard found`가 있어야 한다는 요구를 "없어야 한다"로 뒤집는다(init이 더는 키보드를 보지 않는다).
  `keyboard> none`과 `terminal: opened` 부재는 그대로. 머리 주석(270 근처)의 "init은 3초를 기다린 뒤 …"를 고친다.
- `docs/guides/lessons.md` 278 근처의 로그 줄 목록: init의 두 줄을 지우고 `terminal: keyboard> open /dev/input/event`를.
- 진입 검사(`| grep -q` 금지 등)를 지킨다 — 둘을 함께 볼 때는 `if ! { A && B; }`, 부재는 `if grep -aq …; then fail`.

## Task 4: 검사

- `make quick`(shellcheck · fmt · ast-check · `screen_args_test` · init 빌드).
- 컨테이너에서 `zig build test`(init · terminal). terminal의 테스트는 `screen_args`를 함께 컴파일하므로 칸이 당겨진 것을 본다.
- 체인 넷을 하나씩 컨테이너에서(`device` · `terminal` · `machine` · `keyboard`). 그 다음 Task 0의 측정을 바꾼 빌드로 다시.

## Task 5: 루트 게이트 `RUNS=3`(위험 1)

`docker run … -e RUNS=3 … bash check.sh`. 지금 한 회차 약 15분 30초라 셋이면 약 45분 — 돌리기 전에 사용자에게 알린다. 어느 체인이
한 회차라도 빨개지면 그 로그에서 "키보드가 열리기 전에 친 글자"인지 본다(`keyboard> open`이 첫 `sendkey`보다 뒤인가). 그렇다면 그
체인이 `keyboard> open`을 기다린 뒤 치게 고치고 그 체인만 다시 `RUNS=3`.

## Task 6: 문서 · 커밋

- design: "실측 (M0)" — Task 0과 Task 4의 측정, 게이트 숫자, 판들이 가르친 것. Status 끝남.
- `carryover.md`의 KH 절 첫 항목을 닫는다(`[x]`와 IK design 포인터).
- 서브프로젝트를 닫는 묶음: `completed.md` 한 행, `docs/decisions/project_init_keyboard.md` + `MEMORY.md` 한 줄, `HANDOFF.md`,
  소개 페이지(`gh-pages`의 `data.js`, 순서는 `site/README.md`) — gh-pages push는 사용자에게 묻는다.
- 커밋 대상을 좁혀서 add한다.

## 시간

코드는 지우기가 대부분이라 작다. 체인 넷 각 1~2분, 측정 두 번 각 몇 분, 루트 게이트 `RUNS=3` 약 45분.
