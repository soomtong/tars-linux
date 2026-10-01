# HANDOFF: USB Wireless(UW)가 M2로 닫혔다 — 같은 칩 계열의 USB 동글이 붙는다

## 지금 어디인가

UW가 2026-09-28 하루에 M0~M2로 닫혔다(design `Status: 끝났다`). 사용자가 후보 셋(IPv6 ·
패키지 매니저 · USB 무선 동글 층 A) 중 이것을 골랐다. WL 비목표 5의 USB 절반 중 층 A다.
다음 할 일은 새 서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-28-tars-usb-wireless-design.md`(결정 3 · 위험 2 ·
실측 1~6), plan은 `plans/2026-09-28-tars-usb-wireless-uw-m0.md` ~ `-uw-m2.md`, 기억은
`docs/decisions/project_usb_wireless.md`다.

| 커밋 | 무엇 |
|---|---|
| `ff67042` · `82d2cde` | design · M0 실측(코드 0줄) |
| `1ad272b` | M1 — 커널 config 열하나 · firmware 셋(74→77) · wifi 검사 1 · 11 |
| `ba0e085` | M2 — 반사실 · 루트 게이트 · 문서 |

우리 게스트 코드는 0줄이다. `tars-wifi`와 hook이 드라이버를 안 가린다. 게이트는 심볼 ·
modinfo alias · 부팅 C 로그의 `usbcore: registered new interface driver` 줄까지 본다 — QEMU에
USB 무선이 없어서 실제 동글의 probe와 firmware 로딩은 못 본다. 루트 게이트 17체인 3/3
(1시간 1분 25초, `FAIL` 0줄, 2026-09-28). 반사실(`RTW88_8812AU` 끄기)은 검사 1에서 잡혔다.

⚠ 다음 사람이 먼저 볼 것 — WL이 남긴 넷은 그대로다.
- Dockerfile 층 12(WL). 새로 받은 저장소면 이미지부터 굽는다.
- 첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받는다. `clean()`이 안 지운다.
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons 62).
- 실칩은 PCIe도 USB도 한 번도 안 떴다 — 실기와 실제 동글이 생기면 그것이 새 사실이다.

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 터미널 그래픽(우리 렌더러가 kitty graphics 이미지를 그린다. 2026-10-01 termium
조사에서 나왔다 — `docs/decisions/project_termium_survey.md`) · 패키지 매니저(DI가 비워 둔 p3) · IPv6(커널에 아직 없다. 켜는 사이클이 방화벽
표를 `inet`으로 바꿔야 한다 — FW design 위험 6. sshd가 떠 있으니 그 조건이 무겁다). USB 동글의
층 B · `RTL8XXXU`와 무선의 나머지, 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

2026-09-30에 이월 숙제(`docs/guides/lessons.md`)를 다시 읽었다. CC처럼 한 번에 치울 작은
것은 없다 — 남은 항목은 실기나 실제 동글이 필요하거나, 안 하기로 근거가 쌓였거나
(dirty 추적 · `Ctrl+R` 게이트), 커널을 올릴 때 같이 볼 것이거나(BE201 · `sc-a0-fm-c0`),
한 번 나고 재현 안 된 것(ssh 배너 타임아웃)이다. 다시 조사하지 않는다. 사용자가 새
서브프로젝트를 열지 않고 멈췄다. 이어 간다면 가장 작은 출발점은 USB 동글 층 B(우리 코드
0줄, UW 패턴 그대로)이고, `RTL8XXXU`는 `HID_APPLE`을 먼저 정해야 한다.

## 어디를 보면 되는가

2026-09-27에 이 파일을 193KB에서 줄였다. 서브프로젝트마다 쌓이던 "그 앞" 절들
(SD부터 LB까지)은 지웠다 — 각 서브프로젝트의 경과는 그 design의 실측 절과
`docs/decisions/`의 기억에 있고, 지운 원문은 `git show 76c668e:HANDOFF.md`로 본다.

| 무엇 | 어디 |
|---|---|
| 협업 규칙 · 끝난 서브프로젝트 표 | `CLAUDE.md` |
| 세션을 넘는 기억(색인) | `MEMORY.md` → `docs/decisions/` |
| 게이트를 돌리고 읽는 법 · 범용 명령 · 다시 조사하지 말 실측 · 안 되는 접근 · 이월 숙제 · 핵심 파일 지도 | `docs/guides/lessons.md` |
| 사람이 TARS를 띄우는 법 | `docs/guides/running-tars.md` |
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열일곱) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
