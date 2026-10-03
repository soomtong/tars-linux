# HANDOFF: Workspace Panes(WP)가 M1까지 왔다 — 다음은 M2(워크스페이스)

## 지금 어디인가

2026-10-03 사용자의 요청으로 열었다 — "Cmd+1~9 workspace 전환, Cmd+D · Cmd+Shift+D pane
split", 이어서 "Cmd+W로 닫기", "포커스 이동", "Cmd+T 새 탭". 모델은 iTerm2 그대로다:
워크스페이스가 탭(아홉까지), 각 워크스페이스는 패널을 이진 분할로 여덟까지, 패널 하나가
셸 하나(PTY · `vt.Screen` · 격자 안 사각형). design은
`docs/specs/2026-10-03-tars-workspace-panes-design.md`(결정 9 · 위험 6 · milestone 4),
키 표와 체인 검사 아홉이 그 안에 있다.

이 서브프로젝트는 설계를 Fable이, 구현을 Opus 서브에이전트가 한다(사용자의 지시). 서브에이전트는
commit하지 않고 diff · 로그만 보고하며, Fable이 파일을 직접 대조한 뒤 사용자 승인으로 commit한다.

| milestone | 상태 | 무엇 |
|---|---|---|
| WP-M0 | 끝났다(`37798ad`) | `layout.zig`(순수 트리, `layout_test`) · `Pane` · `Workspace` · `spawnPane` · `paneOrigin`. 눈에 보이는 변화 0 — 체인 넷(terminal · render · copy · hangul)과 기준값(`ink fg=383` · `caps ink off=87` · `copy ink=80`)이 그대로 |
| WP-M1 | 끝났다(2026-10-03, 승인 대기) | `Cmd+D` · `Cmd+Shift+D` · `Cmd+W`(SIGHUP, 닫힘은 EOF 경로 하나) · `Cmd+]` · `Cmd+[`. `Screen.resize` · `pty.resize`(TIOCSWINSZ) · 구분선 `SEPARATOR` · `focused` · `pane>` 줄. 열여덟번째 체인 `pane/check.sh`(검사 열하나 — 폭은 `$COLUMNS`로 증명한다) · 루트 게이트 18체인 3/3(1시간 3분 30초) |
| WP-M2 | 다음 | `Cmd+T` · `Cmd+1~9`(있는 것만) · 상태 줄 `W2` 칸(둘 이상일 때만) · 워크스페이스의 마지막 패널이 닫히면 워크스페이스를 지운다 · 닫은 뒤 포커스를 형제로(M1 실측 6, 사용자가 고른다) |
| WP-M3 | 사용자가 고른다 | `Cmd+Option+화살표` 방향 포커스 |

M2를 열 때 plan을 새로 쓴다. M1이 남긴 자리(`current`가 `const` · `PaneRef.ws` · 빈 트리가 남는
갈래 · `input.Pane`에 variant를 더하면 switch가 배선 자리를 알려 주는 것)는 M1 plan의 "M1이
실측한 것" 끝에 있다. M1의 교훈 하나는 체인에 바로 들어갔다 — 크기를 바꿨다는 것은 셀 수가
아니라 셸이 아는 폭(`$COLUMNS`)으로만 증명된다(반사실이 plan의 검사만으로는 통과했다).

### 그 앞 — Zig Upgrade(ZU)가 M1까지 왔다, M2는 ghostty의 Zig 0.17 전환을 기다린다

Zig 0.17.0이 나왔다(2026-10-03). 사용자의 다른 저장소(`_a-book/monorepo`, `3aad8cc`)는 같은 날
올렸지만 이 저장소는 ghostty가 막는다. `terminal`이 ghostty 소스를 패키지로 물고, ghostty의
`requireZig`가 major · minor 정확 일치를 요구한다. 업스트림 0.17 전환은 draft PR #14519 · 이슈
#14518에 있다(2026-10-02 개설, 0.16 때는 석 달 반 걸렸다).

사용자의 결정: 0.16에서 고쳐도 되는 것만 지금 고치고, ghostty가 0.17로 가면 그때 마무리한다.
design은 `docs/specs/2026-10-03-tars-zig-upgrade-design.md`(결정 5 · 위험 3 · 실측 1~5), plan은
`-zu-m0.md` · `-zu-m1.md`다.

| 커밋 | 무엇 |
|---|---|
| `a4953c0` | M0 — 배열 곱 `**` 25줄 → `@splat`(0.17이 문법을 없앴다) |
| `1a71c6c` | M1 — `@cImport` 다섯 → translate-c 패키지(ghostty가 0.16에서 쓰는 `80f8b6e` 판). fortify를 끄는 자리가 셋에서 `c_poll` stub 헤더의 `#undef` 하나로 줄었다 · 루트 게이트 17체인 3/3(1시간 1분 50초) |

0.17 컴파일러로 `ast-check`하면 `init` · `terminal/src` 오류가 0줄이다. 남은 것은 0.16에 없는 이름
(`@backingInt` · `std.lang`)과 버전 줄뿐이다.

### 그 사이 — Copy Indicator(CI)가 M0 하나로 닫혔다

2026-10-03 사용자의 요청 한 줄("copy mode에 있을 때 맨 아랫줄에 표시를")로 열고 같은 날
닫았다. copy mode에 있는 동안 상태 줄(IS) 꼬리에 다섯째 칸 `COPY`가 뜨고 Esc로 나가면
사라진다. 앞 넷은 안 움직이고, 색은 전용 `STATUS_COPY`라 `caps ink` 판정이 그대로 산다.
`status.zig`는 `vt.zig`를 모른 채 `copy: bool` 하나를 더 받는다.

design은 `docs/specs/2026-10-03-tars-copy-indicator-design.md`(결정 6 · 위험 3 · 실측 1~6),
plan은 `-ci-m0.md`, 기억은 `docs/decisions/project_copy_indicator.md`다. 새 체인은 없고
`copy/check.sh`가 검사 2a · 6a(글자와 픽셀을 짝으로)를 더했다. 반사실(`st.copy` 무시)은
`text=`가 맞는데 `ink=0`으로 잡혔다 — 글자만 보는 판정이었으면 통과했을 고장이다.
루트 게이트 17체인 3/3 PASS, 약 1시간 2분(2026-10-03). 커밋 `362e36d`.

사용자가 요청에 적은 진입 키는 `Cmd+Shift+V`였지만 실제 진입 키는 `Cmd+Shift+C`다
(`Cmd+V`는 붙이기). 코드 기준으로 진행했다.

### 그 앞 — Terminal Graphics(TG)가 M3로 닫혔다

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

## 바로 다음에 할 것 — WP-M1 plan을 쓰고 연다 (ZU-M2는 ghostty 대기)

WP-M1의 범위는 맨 위 표에 있다. 아래는 ZU-M2와 그 밖의 후보에 대한 옛 메모다.

ZU-M2를 여는 신호는 ghostty main의 `build.zig.zon`이 `minimum_zig_version = "0.17.0"`이 되는 것이다
(`curl -sSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/build.zig.zon | rg minimum_zig`).
태그 릴리즈는 기다리지 않는다 — SHA로 고정한다. M2가 할 것은 design의 Milestone 절에 있다:
`Dockerfile`의 `ZIG_VERSION` · `vendor_libghostty_vt.sh`의 `GHOSTTY_SHA` · zon의 `minimum_zig_version`과
translate-c URL · hash(codeberg `875969d`) · 0.17 `zig fmt`(원래 있던 fmt 차이 61줄이 섞인다, 실측 2) ·
`std.builtin` → `std.lang` · "0.16"을 적은 문서들. 첫 일은 ghostty `src/terminal`의 API 변화 읽기(위험 2).
호스트 macOS의 0.17은 `~/.local/zig/zig-aarch64-macos-0.17.0/zig`에 있다(빌드는 컨테이너가 한다).

2026-10-03 다시 봤을 때도 신호는 없었다 — ghostty main은 `"0.16.0"`, PR #14519는 draft에 CI 실패
(`test` · `test-lib-vt`). 그 사이 호스트 `PATH`의 첫 `zig`가 `/opt/homebrew/bin/zig` 0.17이 됐다.
호스트에서 `terminal` · `init`을 직접 `zig build`하면 깨질 수 있으니 빌드는 계속 컨테이너에서 한다.

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
