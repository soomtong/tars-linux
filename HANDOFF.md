# HANDOFF: Screen Args(SA)가 열려 있다 — M0을 닫았고 M1 plan 초안이 있다

## 지금 상태 (2026-10-24)

- 열린 서브프로젝트는 Screen Args(SA)다. design `docs/specs/2026-10-24-tars-screen-args-design.md`, 기억
  `docs/decisions/project_screen_args.md`. SA-M0(2026-10-24, 루트 게이트 22/22)이 init → terminal argv 계약을
  `shared/screen_args.zig` 한 파일로 모았다 — 두 build.zig가 `b.path("../shared/…")`로 named module로 붙이고, 양쪽은 옛 이름을
  별명으로 다시 내보낸다. argv의 모양(위치 아홉 칸)과 로그 줄은 그대로다.
- 다음은 SA-M1 — `docs/plans/2026-10-24-tars-screen-args-sa-m1.md`가 초안이다(M0 게이트가 도는 동안 썼다. 게이트 결과로 바뀔 자리는
  없었다). `Args` 구조체와 `encode` · `decode`를 공유 파일에 더해 init의 쓰는 자리 둘(부팅 · `doReloadTerminal`)과 terminal의 읽는
  자리가 한 함수 쌍을 거치게 한다. 걸리는 자리는 reload가 장치 경로 칸을 그대로 되돌려 넣어야 한다는 것(plan 확정 4)과
  `TERMINAL_PATH`를 공유 파일로 옮기는 것(Task 2)이다. 구현 전에 plan을 한 번 더 읽고 시작한다.
- 최신 공개 버전 0.1.1(2026-10-24) — tag `v0.1.1` = `1f2978f`, GitHub release에 `tars-0.1.1-x86_64.iso`(107 MiB)와 `SHA256SUMS`.
  다음 버전은 `docs/decisions/project_release.md`의 절차 일곱 단계대로 한다 — BV부터 `VERSION` 커밋 → tag → `make iso` 순서다.
- 같은 날 그 앞에 Zig Upgrade(ZU-M2)와 Gate Flakes(GF-M0~M2)를 닫았다 — 컨테이너 Zig 0.17.0, ghostty `3d07ef9`. 호스트 macOS의
  0.17(`/opt/homebrew/bin/zig`)로 `fmt --check` · `ast-check`를 돌릴 수 있고(명령은 lessons "범용 명령", `shared/`도 포함), 0.17
  `zig fmt`는 `@intFromEnum`을 `@backingInt`로 바꾼다. 게이트 로그는 `out/gate-logs/<시각>/`(루트) · `out/gate-logs/<체인>/`(`make check`).
  그 전의 서브프로젝트는 `docs/guides/completed.md`의 표에 있다.
- 체인은 스물둘이다(`check.sh`의 `CHAINS`, 마지막이 `BS-M1:./battery/check.sh`). 새 체인의 monitor 포트는 45495부터다.
  마지막 루트 게이트(SA-M0): 22/22, prebuild 339초 + lanes 294초. 게이트 운영(`RUNS` · `JOBS` · `run_in_background`)은
  `docs/guides/lessons.md`의 "게이트를 돌리고 읽는 법" 절. 다음에 어느 체인이 빨개지면 `out/gate-logs/`의 그 회차 로그부터 본다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- RS: 로그에 `kms: present by dirtyfb`가 찍히는지, `cat` · 빌드 로그처럼 출력이 쏟아질 때 화면이 매끄럽게 따라오는지,
  키 입력이 늦게 느껴지지 않는지. 느리면 그때가 부분 갱신을 다시 집을 신호다.
- TC: `tars-config wifi …`와 `tars-config dictation key`의 tty 입력(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp`,
  `tars-config reload`, `tars-config reload terminal`. 게이트가 못 보는 것은 tty 질문, `--country`, `firewall deny`,
  `firewall=off`의 말이다.
- AU: `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test`, 헤드폰 잭 · USB 헤드셋. SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- BS: 노트북에서 상태 줄 오른쪽 끝에 칸이 뜨는지, 어댑터를 꽂았다 뺄 때 색이 곧바로 바뀌는지, 방전 중 잔량이 60초 안에
  따라오는지. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`과 로그 `terminal: battery> scan …` 줄(lessons "이월 숙제" BS 항목).
- VD: `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 첫 연결 지연, `cleanup timed out`이 매번 나면 `cleanup_timeout`을
  늘리거나 끈다, SOF DMIC 앞부분이 0인지(VD design 위험 1).

## 다음 후보 (SA 뒤. 새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

- 2026-10-24 점검이 남긴 것 가운데 남은 넷, 추천 순서대로. (2) `terminal/src/main.zig`의 `main`이 1,100줄쯤, init의 `main`이
  400줄쯤 — 설정 꺼내기 · 장치 열기 · 이벤트 루프로 나눈다. 다음 기능(부분 갱신 · WP-M3)이 전부 이 함수에 더해질 자리다.
  SA-M1이 끝나면 terminal `main`의 argv 읽는 자리가 `decode` 한 줄이라 그 출발점이 된다. (3) 호스트 검사가 없는 큰 파일 셋
  `config_cli.zig` 622 · `config_front.zig` 639 · `install.zig` 679 — 인자 파싱과 문장 조립은 호스트 검사로 내려올 수 있다.
  (4) `lessons.md` 1,700줄 — "이월 숙제" · "핵심 파일" 절은 각자 문서 하나 분량이다. (5) `.github`가 없다 — Dockerfile 빌드 ·
  호스트 Zig 검사 · shellcheck 정도는 Actions에서 돌릴 수 있다(혼자 작업하는 지금은 선택).
- 부분 갱신(dirty 추적) — RS 뒤의 다음 단계. 출발점은 행 단위 셀 비교와 DIRTYFB clip(`project_render_speed`의 "남은 것").
  GPU 가속은 그 뒤다.
- PD 비목표: 더블클릭 단어 선택, `tars.conf`의 휠 방향, 포인터 가속.
- WP-M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor` — `docs/specs/2026-10-03-tars-workspace-panes-design.md`의 Milestone 절).
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저(아래 "이미지 뷰어 메모"), IPv6(방화벽 표를 `inet`으로, FW design 위험 6), USB 동글 층 B,
  vim-runtime 축소(38MB — 문법 색 · filetype만 고르는 길).
- terminal 바이너리의 디버그 섹션 — 0.17에서 15.2MB 가운데 `.debug_*`가 12.0MB(`.debug_loc` 5.8MB)이고 `make_initrd.sh:154`가
  strip을 안 해 initrd에 그대로 실린다(ZU design 실측 9). `strip --strip-debug`(심볼은 남긴다)로 패닉 trace가 그대로 읽히는지 재고,
  그렇다면 initrd 4.6MB를 되찾는다. init 바이너리도 같이 본다.
- 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

## 이미지 뷰어 메모 (기본 이미지에 넣지 않는다 — 사용자 결정, 2026-10-03)

- Debian `chafa`(1.14.5)는 바이너리 190KB지만 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를 끈다.
  RAM 위 initrd에 늘 얹기에는 크다.
- 필요한 사람은 패키지 관리자로 설치한다. Homebrew `install.sh`는 root이면 멈추므로 non-root 사용자가 먼저다.
  설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 하고, DI의 설치 디스크 위다.
- 어느 뷰어든 `pty.zig`의 `ws_xpixel` · `ws_ypixel`(지금 0)을 우리가 채워야 한다(이월 숙제).

## 이어받는 사람이 볼 것

- Docker는 OrbStack이다(메모리 12GB). 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소는 이미지부터 굽는다(Dockerfile). 첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받고
  `clean()`이 지우지 않는다. `terminal/prepare.sh`가 `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- `shared/`는 init과 terminal이 함께 컴파일하는 파일의 자리다. 순수해야 한다(libc · 로그 없음) — init이 libc를 안 링크한다.
  그 파일을 고치면 두 빌드가 다시 돈다(`zig build --summary all`로 보인다).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons).
- 실칩 무선은 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 동글이 생기면 그것이 새 사실이다.
- decisions의 함정 · 결정만 남기는 정리는 2026-10-20에 남은 여덟도 끝냈다. 아직 10KB를 넘는 다섯(`project_real_machine` ·
  `project_gate_chain_composition` · `project_hangul_input` · `project_shell_config` · `project_userland_tools`)은
  2026-10-10에 이미 정리를 거친 것이다. 문서 속 줄 번호 · 배열 길이는 낡으니 인용하기 전에 코드에서 다시 본다.
