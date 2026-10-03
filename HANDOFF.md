# HANDOFF: Terminal Graphics(TG)가 M3로 닫혔다 — 이미지 뷰어는 패키지 매니저로 넘겼다

## 지금 어디인가

TG가 2026-10-03 하루에 M0~M3로 닫혔다(design `Status: 끝났다`). 자식이 kitty graphics로 보낸
이미지를 우리 렌더러가 그린다. 해석과 저장은 ghostty vt가 하고, 우리 몫은 셀 픽셀 크기 알리기 ·
placement를 픽셀 사각형으로 바꾸기(`vt.zig`) · 그리기(`image.zig`) · PNG 디코더(`png.zig`,
`stb_image`)다.

design은 `docs/specs/2026-10-03-tars-terminal-graphics-design.md`(결정 7 · 위험 3 · 실측 1~9),
plan은 `docs/plans/2026-10-03-tars-terminal-graphics-tg-m0.md` ~ `-tg-m3.md`, 기억은
`docs/decisions/project_terminal_graphics.md`다.

| 커밋 | 무엇 |
|---|---|
| `b90a7d0` | design · M0 실측(코드 0줄) |
| `4cda837` | M1 — `CellPx` · `Screen.images()` · `vt_test` 65~74 |
| `a8a68d0` | M2 — `image.zig` · `render()`의 층 셋 · `render` 체인 검사 15~18 |
| `cc934d9` | M3 — PNG(`stb_image`) · `vt_test` 75~77 · 검사 19 · 반사실 · 루트 게이트 · 문서 |

새 체인은 없다. 루트 게이트 17체인 3/3(1시간 1분 25초, `FAIL` 0줄, 2026-10-03). 반사실(PNG
디코더 설치 줄 빼기)은 `vt_test` 75가 부팅 전에 잡았다.

superpowers 없이 연 첫 서브프로젝트였다. 관찰은 `docs/decisions/feedback_superpowers_off.md`
끝에 있다 — plugin이 막았을 누락은 못 봤다.

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

TG를 닫은 뒤 이미지 뷰어를 다음으로 열려 했다가 2026-10-03에 사용자가 접었다. 재 보니 Debian
`chafa`(1.14.5)는 바이너리가 190KB인데 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를
끌고 온다 — `libSvtAv1Enc` 7.8MB · `librsvg-2` 6.1MB · `libaom` 5.5MB · `librav1e` 3.2MB(AVIF ·
SVG 로더 때문) · glib · cairo · X11 · harfbuzz. RAM 위 initrd에 늘 얹기에는 크다.

사용자의 결정: 뷰어는 기본 이미지에 넣지 않고, 필요한 사람이 패키지 관리자(brew)로 설치하게
남긴다. 그래서 이 일은 후보 "패키지 매니저"의 본론이 된다. brew 쪽에서 확인한 사실:
- Homebrew `install.sh`의 `check_run_command_as_root`가 root이면 `Don't run this as root!`로
  멈춘다. 예외는 컨테이너 표지(`/.dockerenv` · `/run/.containerenv` · cgroup 이름)뿐이다.
  게스트는 전부 root다 — termium이 막힌 자리와 같다. non-root 사용자가 먼저다.
- 설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 한다. DI의 설치 디스크 위다.

어느 뷰어든 `pty.zig`의 `ws_xpixel` · `ws_ypixel`(지금 0)은 우리가 채워야 한다 — 이월 숙제에 있다.

남은 후보 — 패키지 매니저(위의 brew · non-root · 디스크 prefix) · IPv6(방화벽 표를 `inet`으로,
FW design 위험 6) · USB 동글 층 B. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

⚠ 이어받는 사람이 볼 것:
- Docker는 OrbStack이다. 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소면 이미지부터 굽는다(Dockerfile 층 12, WL). 첫 빌드가 linux-firmware
  662MB를 `kernel/src/firmware/`에 받고 `clean()`이 안 지운다. TG-M3부터 `prepare.sh`가
  `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons 62).
- 실칩 무선은 PCIe도 USB도 한 번도 안 떴다 — 실기와 실제 동글이 생기면 그것이 새 사실이다.

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
