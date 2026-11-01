# BT-M1 — 커널 · firmware · BlueZ · init의 열셋째 키

> M0의 값(design "실측 (M0)")을 그대로 옮겨 적는 milestone이다. 사용자가 외출 중이라 lead가 직접 넣는다
> (최근 서브프로젝트들과 같다). 게이트 체인은 M2다 — 여기서는 호스트 검사와 기존 체인이 초록인 것까지다.

Goal: `bluetooth=on`을 적고 `tars-config reload`를 치면 dbus와 bluetoothd가 떠서 `bluetoothctl`이 어댑터를 보고, 기본값의
기계는 한 글자도 안 바뀐다. 컨테이너 이미지가 새 sysroot(BlueZ · D-Bus)를 담는다.

Architecture: 층마다 한 자리다 — 커널 `.config`(결정 1) · `guest_firmware.sh`(결정 2) · Dockerfile + `guest_tools.sh` +
`make_initrd.sh`(결정 3) · 래퍼 둘 + `bluetooth.zig` + `main.zig`의 칸 둘(결정 4) · `config.zig`의 키와 그 키 수를 아는 자리
여섯(결정 5) · `running-tars.md`(결정 6).

## Task 1: 커널 `.config`

M0이 켠 아홉을 `build/.config`의 해소된 모양으로 되접는다(`project_kernel_config` — `cp kernel/build/.config kernel/.config`,
다시 빌드해 diff가 비는지). 커밋 diff가 "이번 변경이 커널에 들여온 것"의 완전한 목록이 된다.

## Task 2: firmware 목록

M0 Task 3이 더한 Bluetooth 블록 157줄 + 머리말의 "무엇을 넣었나" · "뺀 것". `tools` 체인 1b가 297을 센다.

## Task 3: 사용자 공간

Dockerfile(패키지 13 — 데몬 · 도구 다섯과 라이브러리 여덟), `guest_tools.sh` 층 16(바이너리 다섯), `make_initrd.sh`(설정 넷 ·
`/var/lib/bluetooth` 링크 · 래퍼 둘 · messagebus). 이미지는 `docker rmi tars-devcontainer && make container`로 다시 굽는다 —
태그가 Dockerfile의 해시라 CI도 같은 것을 굽는다(GI-M0).

## Task 4: init

`bluetooth.zig`(`wants` · 경로 · argv) · `bluetooth_test.zig` · `services.zig`의 이름 둘 · `main.zig`의 칸 둘(부팅 · reload) ·
`config.zig`의 `Bluetooth` enum · 필드 · 파서 · seed 글자 · `reload.zig`의 `now` 갈래. 키 수를 아는 자리 — `config_test` ·
`reload_test`(4/3/6) · `config_edit_test`(13) · `config/check.sh`의 `TC_LIST_WANT`. 판정: 컨테이너의 `zig build test`가 PASS.

## Task 5: 문서

`running-tars.md`에 "블루투스" 절, 소리 절의 "기대하지 않는 것" 한 줄. `quick_check.sh`의 shellcheck 대상에 래퍼 둘.

## Task 6: 확인

`make quick`(shellcheck · fmt · ast-check · init 빌드), 컨테이너 `zig build test`, 그리고 `make check CHAIN=config`(열셋 키의
`tars-config list`)와 `CHAIN=tools`(initrd 목록 · firmware 297). 부팅해서 `bluetooth=on` 디스크로 `started service dbus` ·
`started service bluetoothd` · `bluetoothctl list`를 한 번 본다 — 체인은 M2가 만든다.
