# HANDOFF: Status Band(SB-M0) 닫음(2026-10-30) — 열린 서브프로젝트 없음, 다음 방향은 사용자가 고른다

## 지금 상태 (2026-10-30)

- 열린 서브프로젝트는 없다. 마지막으로 닫은 것은 Status Band(SB-M0, 2026-10-30, DR과 같은 날). design
  `docs/specs/2026-10-30-tars-status-band-design.md`, plan `docs/plans/2026-10-30-tars-status-band-sb-m0.md`, 기억
  `docs/decisions/project_status_band.md`. 격자 아래 띠(1280 × 28)를 매 프레임 지우고 상태 줄을 다시 쓰고 clip으로 넘기던 것을,
  내용(`text` · `caps` · `battery`)이 바뀐 프레임과 통째 프레임에만 하게 바꿨다 — `App.render`가 `drawPrompt`와 `paintBand(…, full or
  frame.status_changed, &clips)`를 따로 부르고, `renderOverlay`는 그림자(verify)용 통째 경로로 남는다. 메모는 `StatusMemo` 하나이고
  `dumpStatus`의 `status>` 줄도 같은 답(`Frame.status_changed`)으로 찍는다(`sameBatteryCell` 삭제). 새 판정 장치는 없다 — 띠를 잘못
  건너뛰면 DR verify가 `mismatch rows=1 first=47`, clip을 빼먹으면 `mismatch clip`(mutation 둘로 확인, hangul 체인).
  - 숫자(같은 프로브, 부팅 3회 중앙값): 키 하나의 그리기 (a) 0.92 → 0.42ms(−54%, DR-M0의 2.45에서 −83%). overlay 0.22 → 0.001,
    present 0.36 → 0.27(띠 clip이 빠져 virtio-gpu의 경계 상자가 작아진 몫 — 기대 밖), cells 0.07 · pane 0.16. `seq`는 잡음 안.
  - 루트 게이트 22/22, 11분 14초(prebuild 364 + lanes 308초), verify 8109프레임 전부 `ok`.
  - 남은 렌더 축: 0.42ms가 present 0.27(커널) · 행 칠하기 0.135 · cells 0.07로 나뉜다. 다음은 GPU 가속(DR design "안 하는 것")이고
    작은 것은 없다 — 상태 줄 띠는 이번에 끝났다. 함정은 띠가 "마지막으로 그린 상태 줄"이 남는 자리가 됐다는 것 — 격자 마지막
    행의 글리프가 아래로 삐져나오면 verify가 `first=47`로 잡고, 그때는 띠를 지우는 조건에 "마지막 행이 dirty"를 더한다.
  - 소개 페이지에는 안 넣었다(내부 작업).
- 그 전에 닫은 것은 Dirty Rows(DR-M0~M3, 2026-10-28~30). design
  `docs/specs/2026-10-28-tars-dirty-rows-design.md`, 기억 `docs/decisions/project_dirty_rows.md`. 패널마다 지난 프레임의 `cells()`
  목록(두 벌 버퍼 `Pane.cells_buf`)과 행마다 비교해(`verify.rowStarts` · `dirtyRows`) 바뀐 행만 지우고 다시 칠하고(`App.paintPane` ·
  `renderRows`) DIRTYFB clip으로 넘긴다(`drm.ClipList`, M2). M3(2026-10-30, 사용자가 골랐다)부터 `cells()`도 증분이다 —
  `vt.Screen.cellsReuse(out, prev)`가 라이브러리의 행 dirty 비트(`RenderState.dirty` · `Row.dirty`, 우리가 `clean()`으로 끈다)와 층
  다섯의 메모(`Drawn`: 검색 하이라이트 · copy 커서 · 셸 커서 반전 · preedit · 기본 색)로 dirty 행을 정하고 나머지는 지난 목록에서
  run째 복사한다. `cells(out)`은 fresh 경로다. 정답지는 fresh 목록 — 호스트 `dirty_test`가 회차마다 바이트 비교, 게스트 verify가
  그림자를 fresh로 그리고 `terminal: verify> mismatch cells`로 따로 말한다(픽셀 · clip보다 먼저). 루트 `check.sh`의
  `check_verify_lines`가 회차마다 센다(`ok`가 아닌 줄은 전부 빨강).
  - 숫자(같은 프로브 `probe/patch.pl` + `split.pl`, 부팅 3회 중앙값): 키 하나의 그리기 (a) frame 2.45(M0) → 1.36(M2) → 0.92ms(M3,
    −62%). M3 구간은 cells 0.12(0.63에서 −81%) · pane 0.18 · overlay 0.22 · finish 0.37(present 0.36). `seq 1 200000`은 잡음 안.
    `cells()` 0.63의 속은 라이브러리 `update` 0.04 · 변환 루프 0.64였다(Task 0, `probe/cells.pl`). 비교 판의 회차별 (a)는 1.84 · 0.58 ·
    0.92로 흔들렸다(한 회차 `n=4`) — 열두 프레임의 중앙값을 읽는다.
  - 루트 게이트 22/22, 9분 41초(prebuild 279 + lanes 299초), verify 8119프레임 전부 `ok`.
  - 상태 줄 띠(overlay 0.22)는 SB-M0이 같은 날 집었다(위).
  - 알아 둘 것: OSC 10 · 11(기본 전경 · 배경)은 라이브러리가 어떤 dirty 플래그도 안 켠다 — `Drawn.fg/bg` 메모가 그 자리다
    (`dirty_test`의 fresh 비교가 첫 판에 잡았다). 증분 호출(`cellsReuse`)이 한 프레임의 첫 `cells()`여야 한다(비트를 끈다). 지우는
    색은 `MARGIN_COLOR`다(실측 94). mutation은 가려질 수 있다 — 체인은 호스트 테스트를 먼저 도므로 게스트 mutation을 보려면
    `check.sh`의 그 단계를 마운트로 건너뛴다(M3 plan 결과 절). ghostty를 참고로 읽을 때는 `/Users/dp/Repository/_study/ghostty`(최신)다.
    `terminal/ghostty-src`는 빌드 입력이다(`docs/decisions/reference_ghostty_source.md`).

- 그 전에 닫은 것은 Clock Reload(CR-M0, 2026-10-28). design `docs/specs/2026-10-27-tars-clock-reload-design.md`, 기억
  `docs/decisions/project_clock_reload.md`. net 부팅 A의 검사 32가 `tars-config set ntp=dhcp|off|10.0.2.2` · `reload`를 차례로 쳐서
  chronyd 칸의 restart · stop · start를 본다(`doReload`가 `clock.prepare`의 답을 `rewrote`로 넘기는 배선 — mutation으로 확인).
  코드 0줄, 낡은 주석 둘(`power.zig` · `firewall.zig`). carryover 항목 하나를 지웠다. 루트 게이트 22/22, 9분 47초(prebuild 289 +
  lanes 296초). net 체인이 181 → 196초로 가장 긴 체인이다. 소개 페이지에는 안 넣었다(내부 작업).
- 그 전에 닫은 것은 Loose Ends(LE-M0, 2026-10-27). design `docs/specs/2026-10-27-tars-loose-ends-design.md`, 기억
  `docs/decisions/project_loose_ends.md`. 이월 숙제 넷: 화면 쪽 copy mode가 가지치기나 포커스 패널의 셸 종료로 닫히면
  `App.resetInputMode`가 입력 모드도 normal로 돌리고 `terminal: input> mode reset from=copy|find`를 찍는다(셸 종료 자리는 LE가
  찾았다). `input.State.pointerMode`는 `forceMode`가 됐다. `pty.winsize`가 `ws_xpixel` · `ws_ypixel`을 채운다(호스트
  `pty_size_test`). `carryover.md`의 닫힌 항목을 지웠다. copy 검사 23 · pane 검사 9a(닫기를 셸 종료로 바꿈). 루트 게이트 22/22,
  9분 50초(prebuild 298 + lanes 291초). 소개 페이지에는 안 넣었다(내부 작업).
- 그 전에 닫은 것은 WP-M3 방향 포커스(2026-10-27). WP design에 이미 있던 milestone이라 새 design 없이 plan
  `docs/plans/2026-10-27-tars-workspace-panes-wp-m3.md`의 "착수 전에 확정한 것"에 결정을 적었다. 기억은
  `docs/decisions/project_workspace_panes.md`에 덧붙였다. `Cmd+Option+←↑↓→` → `layout.Tree.neighbor(whole, leaf, side)`.
  이웃이 여럿이면 변의 시작점과 마주 보는 것, 끝에서는 감기지 않는다(사용자 결정 둘, 2026-10-26). `Cmd+Option+Backspace`는
  이제 맨 Backspace다(`alted()` switch의 null). pane 체인 검사 16, 루트 게이트 22/22(prebuild 322 + lanes 305초).
- 그 전에 닫은 것은 Lean Initrd(LI-M0~M1, 2026-10-26). design `docs/specs/2026-10-26-tars-lean-initrd-design.md`, 기억
  `docs/decisions/project_lean_initrd.md`. `make_initrd.sh`가 우리 바이너리 다섯(terminal · init · tars-install · tars-service ·
  tars-config)의 initrd 사본만 `x86_64-linux-gnu-strip --strip-debug`한다 — initrd 99.3 → 93.0MB, 게스트 RAM −24.8MB. `zig-out` 원본은
  그대로다. 게스트 패닉 trace는 함수 이름까지 찍고(`.symtab`), 파일:줄은 그 빌드의 `zig-out` 원본에 `addr2line -i`(lessons "범용 명령",
  measurements 93). 루트 게이트 22/22, 12분 18초(prebuild 402 + lanes 334초, 단발 — 시간 효과로 읽지 않는다). commit은 design
  `c86d561` · M0 `c700113` · M1 `74e4733` · `e534da3` · 닫기. 소개 페이지에는 안 넣었다(내부 작업).
- 그 전에 닫은 것은 Lessons Split(LS-M0, 2026-10-26). design `docs/specs/2026-10-26-tars-lessons-split-design.md`, 기억
  `docs/decisions/project_lessons_split.md`. `docs/guides/lessons.md`는 허브(규칙 넷 · 옮긴 절 표 · 게이트를 돌리고 읽는 법 · 범용
  명령)이고, 실측은 `measurements.md`(번호 1~92 그대로), 안 되는 접근은 `dead-ends.md`, 이월 숙제는 `carryover.md`, 핵심 파일은
  `key-files.md`다. 옛 문서의 `lessons "<절>"` · `lessons N`은 허브의 표로 찾는다. 글은 옮기기만 했다 — 이월 숙제의 닫힌 `[x]` 셋 같은
  정리는 아직이다. commit `634e886` · `3819dff` · 닫기. 코드 · 스크립트 0줄이라 게이트를 안 돌았다.
- 그 전에 닫은 것은 Host Checks(HC-M0~M2, 2026-10-26). design `docs/specs/2026-10-25-tars-host-checks-design.md`, 기억
  `docs/decisions/project_host_checks.md`. `tars-config` · `tars-install`의 시스템 콜 쪽에 남은 순수한 것이 짝으로 내려갔다 —
  동사 열넷은 `config_edit.parseCommand`, 앞문 다섯의 인자는 `config_front_edit`의 union 다섯, 설치기의 상태 · 행 · 계획 · 도구 실패 ·
  usage는 `disk`. 출력 바이트 · exit code · `build.zig`는 0 변경(서식 리터럴 집합 diff로 확인). commit은 milestone마다 Task 둘
  (M0 `c17e1a5` · `770b3e8`, M1 `dd248de` · `6d1df4b`, M2 `71a471f` · `94ee1e5`). 새 동사 · 새 키는 `Command`의 칸 하나와 검사 몇
  줄로 시작한다. `config_edit` 485 · `config_front_edit` 484줄 — 500을 넘으면 "동사별 파일"이 후보다. 소개 페이지에는 안 넣었다
  (내부 작업).
- 그 전에 닫은 것은 Main Split(MS-M0~M1, 2026-10-25). design
  `docs/specs/2026-10-25-tars-main-split-design.md`, 기억 `docs/decisions/project_main_split.md`. terminal의 `main`은 `App.open`(단계
  다섯) → `tick`(단계 열) → `close`, init의 `main`은 `mountEarly` → `Boot`의 단계 다섯 → `supervise`다. 동작 · 로그 · 체인 스크립트는
  0줄 바뀌었다. commit은 Task마다 하나(M0 `4338581` · `9f87233` · `edf3152` · probe `2d6b91c`, M1 `4e85cad` · `9bda00d`) — 읽는 법은
  design 결정 1(b)(`--color-moved` · `--word-diff`). 다음 기능(부분 갱신 · WP-M3)은 `App`의 `render`/`dumpFrame` · `runPanes`에,
  새 설정 키는 `Boot.placeChildren`에 더하는 자리가 생겼다. `probe/patch.pl`의 anchor는 넷이고 `App`의 자리를 찍는다. 소개 페이지에는
  안 넣었다(내부 작업).
- 그 전에 닫은 것은 Screen Args(SA-M0~M1, 2026-10-24). design
  `docs/specs/2026-10-24-tars-screen-args-design.md`, 기억 `docs/decisions/project_screen_args.md`. init → terminal argv 계약이
  `shared/screen_args.zig` 한 파일이다 — 값의 종류 · `Slot` · 기본값(M0)에 `Args` · `encode` · `decode` · `argvOf` ·
  `TERMINAL_PATH`(M1)까지. init의 부팅은 `encode` 한 번, `doReloadTerminal`은 `decode → 설정 필드 일곱 대입 → encode`, terminal
  `main`은 `decode` 한 줄이다. `Args`에 기본값이 없어 칸을 더하고 init이 안 채우면 컴파일이 막힌다. argv의 모양(위치 아홉 칸)과
  로그 줄은 그대로다. 소개 페이지(`gh-pages` `data.js`)에는 안 넣었다 — 기능 추가가 아닌 내부 작업(ZU · SA)은 타임라인에서
  건너뛴다(사용자 결정, 2026-10-25).
- 최신 공개 버전 0.1.2(2026-10-30) — tag `v0.1.2` = `d2f9ef7`, GitHub release에 `tars-0.1.2-x86_64.iso`(101 MiB)와 `SHA256SUMS`.
  0.1.1 뒤의 열 서브프로젝트(SA~SB)를 담았고 본론은 부분 갱신(DR + SB)이다(`docs/decisions/project_release.md`의 0.1.2 절).
  다음 버전은 `docs/decisions/project_release.md`의 절차 일곱 단계대로 한다 — BV부터 `VERSION` 커밋 → tag → `make iso` 순서다.
- 같은 날 그 앞에 Zig Upgrade(ZU-M2)와 Gate Flakes(GF-M0~M2)를 닫았다 — 컨테이너 Zig 0.17.0, ghostty `3d07ef9`. 호스트 macOS의
  0.17(`/opt/homebrew/bin/zig`)로 `fmt --check` · `ast-check`를 돌릴 수 있고(명령은 lessons "범용 명령", `shared/`도 포함), 0.17
  `zig fmt`는 `@intFromEnum`을 `@backingInt`로 바꾼다. 게이트 로그는 `out/gate-logs/<시각>/`(루트) · `out/gate-logs/<체인>/`(`make check`).
  그 전의 서브프로젝트는 `docs/guides/completed.md`의 표에 있다.
- 체인은 스물둘이다(`check.sh`의 `CHAINS`, 마지막이 `BS-M1:./battery/check.sh`). 새 체인의 monitor 포트는 45495부터다.
  마지막 루트 게이트(SB-M0 닫기): 22/22, 11분 14초(prebuild 364 + lanes 308초), verify 8109프레임 전부 `ok`(prebuild는 cold build라 흔들린다 — DR-M1의 세 회차는 389 · 322 · 288초였다. DR-M3
  닫기는 9분 41초, prebuild 279 + lanes 299초). 루트 게이트는 이제 회차마다 `verify lines N` 줄도 찍는다(DR-M1). 게이트 운영(`RUNS` · `JOBS` ·
  `run_in_background`)은 `docs/guides/lessons.md`의 "게이트를 돌리고 읽는 법" 절 — 요약 로그는 `/tmp/gate.log`에 쓴다(`out/`은
  게이트가 시작에 지운다). 다음에 어느 체인이 빨개지면 `out/gate-logs/`의 그 회차 로그부터 본다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- RS · DR: 로그에 `kms: present by dirtyfb`가 찍히는지, `cat` · 빌드 로그처럼 출력이 쏟아질 때 화면이 매끄럽게 따라오는지,
  키 입력이 늦게 느껴지지 않는지. DR 뒤로 키 하나는 바뀐 행 몇 줄만 VRAM으로 가므로(simpledrm은 clip마다 복사) 체감이 달라야
  한다 — 달라지지 않았으면 그것이 새 사실이다. SB 뒤로는 상태 줄 띠(1280 × 28 = 143KB, 1080p에서 153KB)도 내용이 바뀐
  프레임에만 간다. TCG에서 키 하나의 그리기는 0.42ms다(SB-M0). 한/영 · CapsLock · 배터리가 바뀔 때 상태 줄이 그 프레임에
  바로 따라오는지도 본다(안 따라오면 `StatusMemo`의 비교가 그 칸을 못 보는 것).
- TC: `tars-config wifi …`와 `tars-config dictation key`의 tty 입력(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp`,
  `tars-config reload`, `tars-config reload terminal`. 게이트가 못 보는 것은 tty 질문, `--country`, `firewall deny`,
  `firewall=off`의 말이다.
- AU: `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test`, 헤드폰 잭 · USB 헤드셋. SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- BS: 노트북에서 상태 줄 오른쪽 끝에 칸이 뜨는지, 어댑터를 꽂았다 뺄 때 색이 곧바로 바뀌는지, 방전 중 잔량이 60초 안에
  따라오는지. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`과 로그 `terminal: battery> scan …` 줄(`carryover.md`의 BS 항목).
- WP-M3: `Cmd+Option+화살표`(`keyboard=pc`면 `Alt+Win+화살표`)로 패널 사이를 다닐 때 손에 맞는지, 동률의 "맨 위 · 맨
  왼쪽" 규칙이 어색하지 않은지. 어색하면 최근 포커스(tmux식)가 다른 후보였다.
- VD: `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 첫 연결 지연, `cleanup timed out`이 매번 나면 `cleanup_timeout`을
  늘리거나 끈다, SOF DMIC 앞부분이 0인지(VD design 위험 1).

## 다음 후보 (DR 뒤. 새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

- 2026-10-24 점검이 남긴 것 가운데 남은 하나((3)은 HC, (4)는 LS로 닫았다).
  (5) `.github`가 없다 — Dockerfile 빌드 ·
  호스트 Zig 검사 · shellcheck 정도는 Actions에서 돌릴 수 있다(혼자 작업하는 지금은 선택).
- 부분 갱신은 Dirty Rows(M0~M3)와 Status Band(SB-M0)로 닫았다(위). 남은 렌더 후보는 GPU 가속뿐이다(키 하나 0.42ms 가운데
  present 0.27이 커널 쪽).
- PD 비목표: 더블클릭 단어 선택, `tars.conf`의 휠 방향, 포인터 가속.
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저(아래 "이미지 뷰어 메모"), IPv6(방화벽 표를 `inet`으로, FW design 위험 6), USB 동글 층 B.
- vim 런타임 싣기는 2026-10-27에 착수 전 취소했다. 사용자는 코드 작업을 neovim · helix로 하고 게스트 vim은 대충 쓴다
  (`docs/decisions/user_editor_use.md`). 실측은 `docs/specs/2026-10-27-tars-vim-runtime-design.md`에 남아 있다.
- 작은 것은 `docs/guides/carryover.md`(이월 숙제)에 있다. DR 뒤로 실기 없이 할 수 있는 것은 렌더 쪽 미룬 하나(큰 kitty 이미지)이고, 나머지는 실기나 간헐의 다음 근거를 기다린다.

## 이미지 뷰어 메모 (기본 이미지에 넣지 않는다 — 사용자 결정, 2026-10-03)

- Debian `chafa`(1.14.5)는 바이너리 190KB지만 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를 끈다.
  RAM 위 initrd에 늘 얹기에는 크다.
- 필요한 사람은 패키지 관리자로 설치한다. Homebrew `install.sh`는 root이면 멈추므로 non-root 사용자가 먼저다.
  설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 하고, DI의 설치 디스크 위다.
- `pty.zig`가 `ws_xpixel` · `ws_ypixel`을 칸 수 × 셀 크기로 채운다(LE-M0, 2026-10-27) — 뷰어가 `TIOCGWINSZ`로 셀 크기를 셈할 수 있다.

## 이어받는 사람이 볼 것

- Docker는 OrbStack이다(메모리 12GB). 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소는 이미지부터 굽는다(Dockerfile). 첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받고
  `clean()`이 지우지 않는다. `terminal/prepare.sh`가 `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- `shared/`는 init과 terminal이 함께 컴파일하는 파일의 자리다. 순수해야 한다(libc · 로그 없음) — init이 libc를 안 링크한다.
  그 파일을 고치면 두 빌드가 다시 돈다(`zig build --summary all`로 보인다).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(`measurements.md`).
- 실칩 무선은 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 동글이 생기면 그것이 새 사실이다.
- decisions의 함정 · 결정만 남기는 정리는 2026-10-20에 남은 여덟도 끝냈다. 아직 10KB를 넘는 다섯(`project_real_machine` ·
  `project_gate_chain_composition` · `project_hangul_input` · `project_shell_config` · `project_userland_tools`)은
  2026-10-10에 이미 정리를 거친 것이다. 문서 속 줄 번호 · 배열 길이는 낡으니 인용하기 전에 코드에서 다시 본다.
