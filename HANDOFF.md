# HANDOFF: Wireless(WL)가 M3로 닫혔다 — 노트북 내장 무선이 붙는다

## 지금 어디인가

WL이 2026-09-28 하루에 M0~M3로 닫혔다(design `Status: 끝났다`). WN 비목표 2를 목표로 옮긴
것이다. 사용자가 후보 넷 중 무선을 골랐고, 드라이버 범위(노트북형으로 넓게) · 자격 증명
(wpa_supplicant 원래 형식 파일) · 데몬(init이 감독)을 정한 뒤 "모든 결정을 위임하고 자러
간다"고 했다. M0 이후의 결정은 Claude가 했고 근거는 design에 있다. 다음 할 일은 새
서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-28-tars-wireless-design.md`(결정 7 · 위험 6 · 실측
1~14), plan은 `plans/2026-09-28-tars-wireless-wl-m0.md` ~ `-wl-m3.md`(위임이라 실행 기록으로
썼다), 기억은 `docs/decisions/project_wireless.md`다.

| 커밋 | 무엇 |
|---|---|
| `74cc5fa` · `49fc2f8` | design · M0 실측(코드 0줄) |
| `2d280c3` | M1 — 커널 config · firmware 목록과 받는 스크립트 · initrd 꼬리 · tools 검사 1b |
| `4267cdf` | M2 — `wifi.zig` · `tars-wifi` · hook `10-tars-wifi` · 게스트 도구 넷 · Dockerfile 층 12 |
| M3 커밋 | 열일곱번째 체인 `wifi/check.sh` · `wifi/ap.sh` · 가이드 · 기억 · 표 |

루트 게이트 17체인 3/3(약 59분 45초, `FAIL` 0줄, 2026-09-28). 1차는 CT-M2 3회차의 ssh 배너 시간
초과 한 번으로 멈췄다 — firmware 유무로 각 3회 재서 평소 0.3초임을 확인하고(한도 5초) 다시
돌려 초록이다. lessons 이월 숙제에 적어 두었다. 반사실 셋(`exec` 없음 · hook 막힘 · 내장
cmdline 비움)이 예측한 검사(3 · 8 · 10)에서 잡혔다.

⚠ 다음 사람이 먼저 볼 것 넷.
- Dockerfile이 바뀌었다(층 12). 새로 받은 저장소면 이미지부터 굽는다.
- 첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받는다. `clean()`이 안 지운다.
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons 62).
- 실칩은 한 번도 안 떴다. 게이트는 hwsim뿐이다 — 실기에 올리면 무엇이 되는지가 새 사실이다.

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 패키지 매니저(DI가 비워 둔 p3) · IPv6(커널에 아직 없다. 켜는 사이클이 방화벽
표를 `inet`으로 바꿔야 한다 — FW design 위험 6. sshd가 떠 있으니 그 조건이 무겁다). 무선의
남은 것(USB 동글 · BE201 · 실기 판정)과 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에
있다.

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
