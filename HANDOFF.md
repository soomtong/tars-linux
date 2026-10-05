# HANDOFF: Pointer Devices(PD)가 열렸다 — M0 · M1이 닫혔고 M2 plan이 측정 대기 중

## 지금 어디인가(2026-10-05, 진행 중)

사용자의 요청("마우스 포인터 · 드래그 선택 · 터치패드")으로 2026-10-05에 열었다. 사용자는 결정권을 lead(Fable)에게
위임하고 자리를 비웠다. design은 `docs/specs/2026-10-05-tars-pointer-devices-design.md`(Opus 서브에이전트가 썼고
lead가 `ink` 정의 하나를 고쳤다, commit `0c2e6f5`, 결정 11 · 위험 8 · 비목표 13 · 실측 15). Milestone은 M0 탐색 ·
읽기 · 로그 / M1 화살표 · 휠 / M2 클릭 · 드래그 · 복사 / M3 터치패드(커널 + 상태 기계 + uinput 게이트).

| 커밋 | 무엇 |
|---|---|
| `0c2e6f5` | design |
| `8f8a030` | PD-M0 — `pointer.zig`(`classify` · `Mouse` 디코더 · `Pointer` clamp · `ueventAddedNode`) · `pointer_test`(OK 53) · `main.zig`의 netlink uevent 소켓 · 장치 칸 여덟 · poll 배열 `pty_base` · `pointer>` 줄 넷 · 열아홉번째 체인 `pointer/check.sh`(포트 45488, 검사 1~7) · 루트 게이트 19체인 3/3(1시간 8분 39초). 커널은 안 바뀌었다 |
| (M1 커밋) | PD-M1 — `pointer.zig` 화살표 절(12 × 19, `POINTER_FILL` · `POINTER_EDGE`, `Sprite` save-under, `ink` 118) · `layout.Tree.hit` · `main.zig` 편집 열둘(보이는 조건 셋 · 움직임만 있는 회차는 restore → show → present · 휠 `WHEEL_ROWS=3` 포인터 아래 패널) · `pointer/check.sh` 검사 8~12 · `pointer_test` OK 75 · `layout_test` hit 22 · 루트 게이트 19체인 3/3(1시간 8분 41초, 마지막 3회 게이트). 구현은 Sonnet |

M0에서 배운 것 하나가 크다. plan의 처음 판은 핫플러그를 inotify로 받았고 게스트 커널에 `INOTIFY_USER`가 없어 한 줄을
켰는데, 그것이 `FSNOTIFY`를 끌어와 initramfs 풀기를 TCG에서 2.6초 → 3.8초로 늦췄고 `install` 체인 부팅 7
(`usb-storage.delay_use=3`)의 창이 닫혀 루트 게이트가 두 번 빨갰다. lead의 결정으로 netlink uevent(`NETLINK_KOBJECT_UEVENT`,
커널 config 불필요)로 바꿨다. 과정과 표는 M0 plan "착수 전에 확정한 것" 7과 "PD-M0이 실측한 것" 7~10에 있다.

바로 다음: PD-M2(클릭 포커스 · 드래그 선택 · 뗌 = 복사, Opus 구현). plan 초안은 `/tmp/run/pdm2/plan.md`(Opus planner,
2,383줄, 측정 대기)이고 M1 commit 뒤 planner가 사본 컴파일 · 체인 · regression · mutation 넷을 돌려 `docs/plans/
2026-10-05-tars-pointer-devices-pd-m2.md`로 옮긴다. lead가 M2에서 정한 것 다섯은 그 plan "design과 다르게 적은 것"에
"lead가 정했다(2026-10-05)"로 있다. M1에서 정한 것 둘: 화살표를 숨기는 자리는 `keys.bytes` 하나(`Cmd+V` · 질의 답은 안
숨긴다) · 마지막 장치가 빠지면 "움직였다" 조건도 꺼진다(design 결정 4에 닫을 때 덧붙인다).
사용자의 결정(2026-10-05): 루트 게이트는 M1까지 3회, M2부터 2회(`docs/decisions/feedback_gate_runs.md`) — M1 commit 바로
뒤의 별도 commit이 `check.sh`를 고친다.

측정 파일: `/tmp/run/mp0`(lead 실측) · `/tmp/run/pdm0`(M0 planner · 구현자 · `inst/`에 install 재현 로그) ·
`/tmp/run/pdm1`(M1 planner, 저장소 사본 `repo/`).

lessons에 남길 것(닫을 때): `INOTIFY_USER`를 켜면 `FSNOTIFY`가 initramfs 풀기를 1.2초 늦춰 `install` 부팅 7의 창이 닫힌다 ·
OrbStack VM 4GB에서 cold `zig build`(약 3GB)와 다른 컨테이너의 QEMU가 겹치면 OOM(exit 137)이나 VM 재시작 — docker 작업은
한 번에 하나 · `sendkey colon`은 없는 이름(`shift-semicolon`) · 게스트에 `od` · `xxd` · `timeout`이 없어 바이트는
`head -c N | cat -v` · `install` 체인의 시리얼 로그를 남기려면 `rm -rf "$WORK"`를 뺀 사본을 덮는다 · 새 체인 포트는
45488부터(45481~45487은 service · pane이 쓴다) · ioctl 매크로(`EVIOCGBIT` 등)는 ZU-M1의 translate-c가 inline fn으로
넘긴다(HD 조사 6은 `@cImport` 시절의 사실).

### 그 앞 — Paste Ergonomics(PE)가 M0~M2로 닫혔다


2026-10-04 GE를 닫은 직후 열어 같은 날 닫았다. GE가 남긴 둘(터미널의 bracketed paste · 사용자 vimrc
영속)에 루트 게이트를 흔들던 `service` 체인 경합 하나를 M0으로 묶었다. design은
`docs/specs/2026-10-04-tars-paste-ergonomics-design.md`(결정 9 · 위험 7 · 실측 10, `Status: 끝났다`),
plan은 `-pe-m0.md` · `-pe-m1.md` · `-pe-m2.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은
`docs/decisions/project_paste_ergonomics.md`.

사용자의 지시("계획 수립과 구현을 목적에 맞는 model을 선택하고 sub agents를 사용하여")로 design과
plan 셋은 Opus 서브에이전트가, 구현은 M0 · M2(이미 있는 모양을 옮긴다)를 Sonnet · M1(판단과 화면
판정을 새로 만든다)을 Opus 서브에이전트가 했고 Fable이 사실 조사 · 대조 · 루트 게이트 · commit을
맡았다. 이번에는 mutation도 구현자가 돌리고 Fable은 로그를 읽었다. 구현자는 전부 main 작업 트리에서
편집했다(루트 게이트와 겹치지 않게 순서를 두었다 — M2 planner만 M1의 게이트가 도는 동안 썼고, 그때
빌드 · QEMU · 저장소 편집을 금지했다).

planner들이 lead · design의 전제를 여럿 바로잡았다. 이것이 이 방식의 값이었다.
- M0: "부팅 C · D가 임대를 안 기다린다"가 아니라 셋 다 `boot_ssh`에서 기다리고 있었고, 원인은 dhcpcd가
  `leased`를 주소를 붙이기 전에 찍는 것이었다(lessons 실측 73). 이월 숙제의 진단이 틀렸던 것이다.
- M1: 꼬리 `ESC[201~`를 빠뜨리면 fish가 그 뒤의 키를 전부 삼킨다(mutation 3이 새 검사가 아니라 기존
  검사 11에서 잡혔다) · fish 4.0.2는 인자를 치는 중에 모드 2004를 끈다(design 위험 4에 덧붙였다) ·
  `cat` 아래의 에코와 출력 순서는 스케줄이 정한다(화면 모양 대신 개수로 판정).
- M2: `vim -e`가 `xterm-256color`에서 대체 화면에 찍어 출력이 사라진다(`-T dumb`, lessons 실측 74) ·
  `HOME=/`에서는 `~/.vimrc`가 아니라 `/.vimrc`로 찍힌다 · `seedOneFile`에 `O_TRUNC`가 없어 `.EXCL`만
  빼는 mutation은 잡히지 않는다(`.TRUNC`로 바꿨다). design 실측의 pyte가 대체 화면을 구현하지 않아
  첫째를 놓쳤다 — pyte로 잰 화면은 대체 화면에 대해 믿지 않는다.

| 커밋 | 무엇 |
|---|---|
| `d237fb2` | M0 — `service/check.sh`의 `boot_ssh`가 `leased` 뒤에 `eth0: adding default route via 10.0.2.2`를 30초까지 더 기다린다. 코드 0줄. 루트 게이트 대신 `service` 체인 5/5(1분 11~15초), 스무 로그 중 순서가 뒤바뀐 것 0 |
| `2c0443e` | M1 — `vt.Screen.pasteParts`(모드 2004를 보고 머리 · 본문 · 꼬리 셋) · `dumpPaste`가 `pty.write` 세 번, 로그 `clip> paste len=N bracketed=0\|1`(`len=`은 본문 그대로라 기존 판정 안 바뀜) · `vt_test` 93~96 · `copy/check.sh` 검사 21(fish 프롬프트에 두 줄 — Enter 전에 안 돌고 뒤에 둘 다 돈다) · 22(`cat` 아래 — 화면에 `[200~` 없음). mutation 넷 전부 빨감. 루트 게이트 18체인 3/3(1시간 7분 14초, M0의 기록도 됨) |
| (이 커밋) | M2 — initrd 링크 `/.vimrc -> config/vimrc` · `init`의 `VIMRC_SEED`(주석 21줄 843바이트) · `seedVimrc()` · `config_test`의 `expectVimrcSeed`(규칙 다섯) · `kernel/vim/vimrc` 주석 · `config/check.sh` 1차 셋(`vim -T dumb -e +scriptnames +qa` → `2: /.vimrc` · 에러 없음 · `>> /.vimrc` 되읽기) + 2차 하나(`+'set ts?'` → `tabstop=3`) · `tools/check.sh` `WANT`에 `.vimrc`. mutation 다섯 전부 빨감. 루트 게이트는 M2 plan 실측 7 |

열지 않은 것(design 비목표): 모드가 꺼진 갈래의 `\n` → `\r`과 제어 바이트 치환(`encodePaste`로 옮길
자리 — 클립보드가 화면 밖에서 오게 되면) · 감싸지 않는 여러 줄 붙여넣기를 막거나 묻는 것 · OSC 52 ·
`/.viminfo`를 `/config`로 · 큰 붙여넣기에서 `pty.write`가 멈추는 것(non-blocking 쓰기와 큐) · SLIRP의
SYN 재전송 시각 · vim의 계단을 게이트에서 보는 것 · fish의 확장 키 모드 · `tars.conf`로 bracketed
paste를 끄고 켜는 것.

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

후보는 아래 "그 다음 후보" 절(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB
동글 층 B)과 WP-M3(방향 포커스), GE가 남긴 `vim-runtime`(38MB — 문법 색 · filetype, syntax 파일 몇
개만 고르는 길과 함께)이다. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다 — PE-M0이
service 두 항목을 지워서 지금 그 목록에 체인 경합은 없다.

### 그 앞 — Guest Ergonomics(GE)가 M0 · M1로 닫혔다

2026-10-04 같은 날 PE 바로 앞에 닫았다. `which`(debianutils의 sh 스크립트, `copy_lib_deps`의 ELF magic
검사, M0 `a53f57b`)와 plugin · 런타임 없는 모던 시스템 vimrc(M1 `48431e7`). design은
`docs/specs/2026-10-04-tars-guest-ergonomics-design.md`, 기억은 `docs/decisions/project_guest_ergonomics.md`.
GE가 비워 둔 위험 2(autoindent 계단)와 비목표 2(사용자 vimrc) · 4(bracketed paste)를 PE가 채웠다.

### 그 앞 — Cursor Shape(CU)가 M0 · M1로 닫혔다

2026-10-04 같은 날 GE 바로 앞에 닫았다. 우리 렌더러가 DECSCUSR 모양 셋을 그리고(M0, `8d65077`),
게스트 vi를 `vim-tiny`(`-cursorshape`)에서 `vim.basic`으로 바꿔 시스템 vimrc 세 줄과 stub
`defaults.vim`을 initrd에 넣었다(M1, `9f97b4b`). 그 vimrc를 GE-M1이 넓혔다. design은
`docs/specs/2026-10-04-tars-cursor-shape-design.md`, 기억은 `docs/decisions/project_cursor_shape.md`.

### 그 앞 — Workspace Panes(WP)가 M0~M2로 닫혔다

2026-10-03 사용자의 요청으로 열어 2026-10-04에 닫았다 — "Cmd+1~9 workspace 전환, Cmd+D ·
Cmd+Shift+D pane split", 이어서 "Cmd+W로 닫기", "포커스 이동", "Cmd+T 새 탭". 모델은 iTerm2
그대로다: 워크스페이스가 탭(아홉까지), 각 워크스페이스는 패널을 이진 분할로 여덟까지, 패널
하나가 셸 하나(PTY · `vt.Screen` · 격자 안 사각형). design은
`docs/specs/2026-10-03-tars-workspace-panes-design.md`(`Status: 끝났다`), 기억은
`docs/decisions/project_workspace_panes.md`, plan은 `-wp-m0.md` · `-wp-m1.md` · `-wp-m2.md`이고
각 plan의 "실측한 것" 절이 값이다.

이 서브프로젝트는 설계를 Fable이, 구현을 Opus 서브에이전트가 했다(사용자의 지시). 서브에이전트는
commit하지 않고 diff · 로그만 보고했고, Fable이 파일 · 로그를 직접 대조한 뒤 commit했다. 세
milestone 모두 보고와 파일이 어긋난 자리는 없었다. 관찰: 서브에이전트가 mutation에서 plan의 구멍을
둘 찾아 검사를 스스로 더했다(`$COLUMNS` · `caps ink off=`) — 그것이 이 방식의 값이었다.

| 커밋 | 무엇 |
|---|---|
| `37798ad` | M0 — `layout.zig`(순수 트리) · `Pane` · `Workspace` · `spawnPane` · `paneOrigin`. 눈에 보이는 변화 0 |
| `ef0f0c3` | M1 — `Cmd+D` · `Cmd+Shift+D` · `Cmd+W`(SIGHUP, 닫힘은 EOF 경로 하나) · `Cmd+]` · `Cmd+[` · `Screen.resize` · `pty.resize` · 구분선 · `pane>` 줄 · 열여덟번째 체인 `pane/check.sh` |
| `778f5bb` | M2 — `Cmd+T` · `Cmd+1~9` · 상태 줄 `W2` 칸 · 워크스페이스 삭제 · 닫은 뒤 포커스를 형제로(`Tree.heir`). `pane/check.sh` 검사 열여섯 · 루트 게이트 18체인 3/3(1시간 4분 30초) |

열지 않은 것: WP-M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor` — design Milestone 절에
모양이 있다. 순환만으로 네 패널을 다니는 것이 불편해지면 연다) · 패널 간 클립보드 · 비율 조절.
사용자가 그대로 두기로 한 것: M1이 바꾼 `Cmd+Shift+←·→·Backspace`(Shift를 무시하던 것이 맨
키로 나간다).

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
`copy/check.sh`가 검사 2a · 6a(글자와 픽셀을 짝으로)를 더했다. mutation(`st.copy` 무시)은
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
| `cc934d9` | M3 — PNG(`stb_image`) · `vt_test` 75~77 · 검사 19 · mutation · 루트 게이트 · 문서 |

새 체인은 없다. 루트 게이트 17체인 3/3(1시간 1분 25초, `FAIL` 0줄, 2026-10-03). mutation(PNG
디코더 설치 줄 빼기)은 `vt_test` 75가 부팅 전에 잡았다.

superpowers 없이 연 첫 서브프로젝트였다. 관찰은 `docs/decisions/feedback_superpowers_off.md`
끝에 있다 — plugin이 막았을 누락은 못 봤다.

### 그 다음 후보 — 새 서브프로젝트를 고른다 (ZU-M2는 ghostty 대기)

WP-M3(방향 포커스)은 맨 위 절에 있다. 아래는 ZU-M2와 그 밖의 후보에 대한 메모다.

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
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열여덟) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
