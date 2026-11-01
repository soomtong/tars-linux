# BT-M2 — 스물셋째 체인, mutation 셋, 루트 게이트, 닫기

> lead가 직접 넣는다. M1까지의 작업 트리 위에서 체인을 만들고, 루트 게이트 23/23 뒤에 문서를 닫는다.

Goal: `bluetooth/check.sh`가 design 결정 8의 검사 아홉을 매 회차 보고, mutation 셋이 예측한 검사에서 잡히고, 루트 게이트가
23/23이다. 닫을 때 확인 8의 문서들과 소개 페이지 · completed · decisions · HANDOFF를 고친다.

## Task 1: 체인

`bluetooth/check.sh`(정적 검사 1, 부팅 A의 검사 2~8, 부팅 B의 검사 9)와 게스트 쪽 `bluetooth/bt.sh`(services.d/bt — 컨트롤러 둘 ·
페어링 · 재시작 · 끄기를 `bt-probe:` 줄로). 루트 `check.sh`의 `CHAINS`에 `BT-M2:./bluetooth/check.sh`, 체인 소개 단락 하나,
"스물두 체인" 주석. lessons의 포트 목록에 "BT는 포트를 안 쓴다". `make check CHAIN=bluetooth`가 PASS.

## Task 2: mutation 셋

| mutation | 잡아야 하는 검사 |
|---|---|
| `kernel/.config`의 `CONFIG_BT=y`를 `# CONFIG_BT is not set`으로 | 검사 1(부팅 전) |
| `bluetooth.zig`의 `wants`가 `.off`를 무시 | 검사 9(부팅 B — 데몬이 떴다) |
| `make_initrd.sh`의 `/var/lib/bluetooth` 링크 줄 제거 | 검사 1(initrd에 링크 없음) |

둘째는 `bluetooth_test`(호스트)가 먼저 잡는다 — 그러면 체인은 `zig build`에서 멈춘다. 그것도 적는다.

## Task 3: 루트 게이트

`docker run --rm --sysctl … tars-devcontainer bash check.sh`, 약 11분. 23/23과 verify 줄을 본다. 빨간 체인이 BT 밖의 간헐이면
`carryover.md`의 간헐 목록과 대조하고 한 번 더 돈다.

## Task 4: 닫기

design `Status:`, 확인 8의 문서 넷(AU · VD · UB · BS design), `running-tars.md`(M1에서 썼다), `completed.md` 한 행,
`docs/decisions/project_bluetooth.md` + `MEMORY.md` 한 줄, `carryover.md`(Keyboard Hotplug · 실기 · Intel firmware),
`key-files.md`, 소개 페이지 `data.js`(asOf · latest · timeline · features의 "부팅 · 하드웨어" note와 항목 · 설정 키 열셋 ·
stats), `HANDOFF.md`.
