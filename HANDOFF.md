# HANDOFF: 열어 둔 서브프로젝트가 없다 — 실기 확인과 다음 후보를 기다린다

## 지금 상태 (2026-10-20)

- 첫 공개 버전 0.1.0(2026-10-11) — tag `v0.1.0` = `0a6d4bc`, GitHub release에 `tars-0.1.0-x86_64.iso`와 `SHA256SUMS`.
  다음 버전은 `docs/decisions/project_release.md`의 절차 일곱 단계대로 한다.
- 마지막으로 닫힌 것은 Render Speed(RS-M0~M3, 2026-10-11)다. 부분 갱신은 안 했다 — 사용자가 다시 판단한다.
  그 전의 서브프로젝트는 `docs/guides/completed.md`의 표에 있다.
- 체인은 스물둘이다(`check.sh`의 `CHAINS`, 마지막이 `BS-M1:./battery/check.sh`). 새 체인의 monitor 포트는 45495부터다.
  마지막 루트 게이트(RS-M3): 22체인 PASS, 9분 30초. 게이트 운영(`RUNS` · `JOBS` · `run_in_background`)은 `docs/guides/lessons.md`의
  "게이트를 돌리고 읽는 법" 절.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다. 그래서 옛 설정 디스크의
  alias 처방(`running-tars.md` "seed는 한 번만 깔린다")은 지금 흐름에 필요 없다.

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

## 다음 후보 (새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

- TODO `tars-config`에 버전 표시 — 시스템 안에 버전이 없어 받은 사람이 자기 ISO가 몇 버전인지 알 길이 없다.
  `tars-config version`(또는 `--version`)이 빌드에 박힌 버전을 찍게 한다. 동사 분기는 `init/src/config_cli.zig`. 정할 것:
  버전의 원천(태그 · 파일 하나 · `build.zig` 옵션)과 부팅 로그의 `tars-init:` 첫 줄에도 찍을지.
- 부분 갱신(dirty 추적) — RS 뒤의 다음 단계. 출발점은 행 단위 셀 비교와 DIRTYFB clip(`project_render_speed`의 "남은 것").
  GPU 가속은 그 뒤다.
- PD 비목표: 더블클릭 단어 선택, `tars.conf`의 휠 방향, 포인터 가속.
- WP-M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor` — `docs/specs/2026-10-03-tars-workspace-panes-design.md`의 Milestone 절).
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저(아래 "이미지 뷰어 메모"), IPv6(방화벽 표를 `inet`으로, FW design 위험 6), USB 동글 층 B,
  vim-runtime 축소(38MB — 문법 색 · filetype만 고르는 길).
- 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

## 열린 대기 조건

- ZU-M2(ghostty의 Zig 0.17 전환)를 여는 신호는 ghostty main의 `build.zig.zon`이 `minimum_zig_version = "0.17.0"`이 되는
  것이다. 확인 명령: `curl -sSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/build.zig.zon | rg minimum_zig`.
  태그 릴리즈는 기다리지 않고 SHA로 고정한다. M2의 할 일은 `docs/specs/2026-10-03-tars-zig-upgrade-design.md`의 Milestone 절에 있다.
  호스트 macOS의 0.17은 `/opt/homebrew/bin/zig`다(`~/.local/bin/zig`는 0.15.2, 빌드는 컨테이너가 한다).
  2026-10-20 확인 때도 신호가 없었다(ghostty main은 `"0.16.0"`, PR #14519는 draft를 벗었지만 아직 open).

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
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons).
- 실칩 무선은 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 동글이 생기면 그것이 새 사실이다.
- decisions 중 10KB를 넘고 아직 함정 · 결정만 남기는 정리를 안 한 것: `project_guest_environment` · `project_input_status` ·
  `project_kernel_config` · `project_shell_history` · `project_init_supervisor` · `project_zig_c_uapi_rule` ·
  `project_config_persistence` · `project_input_policy`. 더 줄일지는 사용자가 고른다.
