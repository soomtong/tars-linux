---
name: project_chromium
description: Chromium(CR-M0~M2, 2026-11-22, 브랜치 app-layer-0-3)이 끝났다 — Debian trixie의 chromium이 수정 없이 sandbox를 켠 채 사용자로 TARS compositor에 뜨고 주소창 한글 · 클립보드 양방향 · 메뉴 · 풀스크린(자기 workspace)이 된다. 묶음 browser · tars-browser · 체인 browser. 거두기는 snapshot.debian.org의 한 시각 + InRelease sha256으로 고정. 함정 아홉
metadata:
  type: project
---

App Layer(0.3)의 4단. design `docs/specs/2026-11-22-tars-chromium-design.md`(확인 1~13 · 결정 1~9), plan `docs/plans/2026-11-22-tars-chromium-cr-m1.md`.
결정은 위임받아 Claude가 정했다([[project_app_layer_vision]]).

무엇이 섰나: devlayer 묶음 `browser`(Debian `chromium` 156 + `fonts-noto-cjk`, zstd15 294 MiB, base 위), 실행 문 `tars-browser`(`--ozone-platform=wayland --disable-gpu
--no-first-run --no-default-browser-check`), 체인 `browser/check.sh`(37번째 — 첫 화면의 좌표 색 · 렌더러의 `Seccomp: 2`와 다른 user namespace · `Cmd+Q`).
이미 되는 것: HTTPS · 한글 preedit(text-input v3) · 호환 모드 Cmd → Ctrl · 클립보드 · `display_scale=2`.

다시 겪지 않을 것:

- 치명적 벽은 `wl_subcompositor` 하나다 — 주소창에 글자를 치면 bubble이 `get_subsurface`를 null에 부르고 죽는다. `xdg_popup`은 안 보일 뿐이다. 그래서 순서를
  CR-M1 → WY-M7 → CR-M2로 바꿨다(묶음과 체인이 먼저 있으면 WY-M7을 진짜 Chromium으로 검증한다).
- live Debian 미러의 `=판` 고정은 point release 날 깨진다(2026-11-21에 `libc6-dev` · `patch`가 사라져 캐시 없는 기계의 `make dev-layers`가 base에서 멈췄다 —
  이 기계는 캐시가 가려 줬다). 모든 debian 줄을 `snapshot.debian.org`의 한 시각(`devlayer/snapshot`)에서 거둔다. 시각은 "manifest의 모든 판이 함께 있는 가장 늦은 시각".
  한 묶음에만 snapshot을 쓰는 길은 없다(같은 의존의 판이 갈라져 묶음끼리 대조에 걸린다).
- http + `check-valid-until=no`는 freeze/replay를 못 막는다 — 서명은 "Debian이 언젠가 낸 것"만 지킨다. 그 시각의 InRelease 셋의 sha256을 파일에 적어 깔기 전에
  대조한다(폐포 전체가 내용으로 고정된다). 이것은 commit 뒤의 자동 보안 검토가 짚었고 타당했다.
- `harvest.sh` · `harvest-skip.tsv` · `devlayer/snapshot`을 고치면(주석 한 줄이라도) debian 묶음 아홉을 다시 거둔다(약 21분) — 고침을 모아서 한 번에.
- 옛 캐시가 문제를 가린다: 모두 다시 거두자 pgdg의 재빌드(`+2` → `+5`)가 드러났다(의존 넷을 판 고정).
- Chromium은 sandbox 때문에 root로 안 뜬다 — 체인은 설정 디스크에 `user=`를 둔 부팅이어야 한다. `/dev/shm`은 필요 없다(memfd). postinst가 만드는 캐시
  (gschemas 등)가 묶음에 없으면 첫 키에서 죽는다(harvest의 설치 전후 비교가 싣는다).
- 화면의 글자 판정은 잉크 수로 못 한다 — 두부(빈 사각형)도 잉크가 같다. 잉크의 색 가짓수(안티에일리어싱)로 가른다.

- (CR-M2) 요구사항에 적어 둔 결정이 코드에 없을 수 있다 — "앱의 풀스크린은 자기 workspace"(요구사항 결정 1 · 6)는 WY-M0~M7을 지나며 "첫 commit 전의 것만"으로 남아
  있었고, 조사가 `Cmd+Ctrl+F` · F11을 실제로 눌러 보고서야 드러났다. milestone의 조사는 녹화 장면을 그대로 쳐 본다.
- (CR-M2) 클라이언트에 주는 상태가 앱의 화면을 바꾼다 — Chromium은 `fullscreen` 상태에 탭 줄 · 주소창을 감춘다. `Cmd+Ctrl+F`(TARS의 chrome을 끄는 것)는 `maximized`,
  F11(앱이 청한 것)은 `fullscreen`으로 갈랐다(WY design 결정 58). 정하기 전에 시제품으로 두 상태의 화면을 본다.

CR-M2(plan `docs/plans/2026-11-22-tars-chromium-cr-m2.md`)로 선 것: 앱 풀스크린 ↔ 자기 workspace(`enterOwn` · `leaveOwn`, 돌아갈 곳은 workspace의 `uid`), browser 체인의
판정 7~11(셸 → Chromium 붙여넣기 · 주소창 한글 · `restrict=on` SLIRP의 http stub 페이지 · Chromium → 셸 · `Cmd+Ctrl+F`와 F11 왕복), wayland 판정 45~47.

배포(사용자 2026-11-22): "browser가 포함된 묶음은 web 식별자를 달아서 별도 빌드. lang native 없어도 됨" — browser는 기본 판에 넣지 않고 `tars-<ver>-web-x86_64.iso`로
따로 낸다(lang-native 뺌, 절차는 [[project_release]]).

남긴 것: 녹화 D(사람), web 판 ISO, `docs/guides/carryover.md`의 "CR-M0 · CR-M1이 남긴 것" · "CR-M2가 남긴 것". 실측은 `measurements.md` 115 · 118.

관련: [[project_dev_layer]] · [[project_ui_toolkit]] · [[project_wayland_server]] · [[project_release]]
