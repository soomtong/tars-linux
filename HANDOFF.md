# HANDOFF: 열어 둔 서브프로젝트가 없다 — 실기 확인과 다음 후보를 기다린다

## 지금 상태 (2026-10-09)

- 마지막으로 닫힌 것은 Battery Status(BS-M0 · M1)다(2026-10-09). 배터리가 있는 기계에서 상태 줄 오른쪽 끝에 폭 4의
  잔량 칸이 뜬다. 기억은 `docs/decisions/project_battery_status.md`, design은
  `docs/specs/2026-10-08-tars-battery-status-design.md`다.
- 커밋 다섯 — design · M0 plan `272065f`, BS-M0 `2ff5108`, M1 plan `b1b1c5b`, BS-M1 `000e562`, 닫는 문서 `0412237`.
  작업 트리는 깨끗하다.
- BS-M1 루트 게이트(22체인 × 2): 22체인 전부 `PASS: 2/2`, 1시간 00분 18초, `skipping make` 43, 44회차 전부 `A=0 B=0 C=0`, hangul `383 … (off=87)` 두 번, 빨간 줄 0
- 체인은 이제 스물둘이다(`check.sh`의 `CHAINS`, 마지막이 `BS-M1:./battery/check.sh`). 새 체인의 monitor 포트는 45495부터다.
- 그 전에 닫힌 것은 Config Tool(TC-M0~M3)과 Atomic Log Lines(AL-M0 · M1)다(2026-10-07, `f3b677c`).
- 문서 감사(2026-10-08)의 남은 제거 후보는 "남은 정리" 절에 있다. 그중 낡은 수치(lessons · running-tars의 체인 수와 게이트
  시간)는 BS를 닫으며 고쳤다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다. 그래서 옛 설정 디스크의
  alias 처방(`running-tars.md` "seed는 한 번만 깔린다")은 지금 흐름에 필요 없다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- TC: `tars-config wifi …`와 `tars-config dictation key`의 tty 입력(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp`,
  `tars-config reload`, `tars-config reload terminal`. 게이트가 못 보는 것은 tty 질문, `--country`, `firewall deny`,
  `firewall=off`의 말이다.
- AU: `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test`, 헤드폰 잭 · USB 헤드셋. SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- BS: 노트북에서 상태 줄 오른쪽 끝에 칸이 뜨는지, 어댑터를 꽂았다 뺄 때 색이 곧바로 초록 · 회색으로 바뀌는지, 방전 중 잔량이
  60초 안에 따라오는지. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`과 로그 `terminal: battery> scan …` 줄. `capacity`
  파일이 없는 배터리는 `  ?%`가 정상이다. 게이트가 못 보는 것은 ACPI 배터리의 값 그 자체다(`docs/guides/lessons.md`의 "이월 숙제" BS 항목).
- VD: `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 첫 연결 지연, `cleanup timed out`이 매번 나면 `cleanup_timeout`을
  늘리거나 끈다, SOF DMIC 앞부분이 0인지(VD design 위험 1).

## 다음 후보 (새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

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
  호스트 macOS의 0.17은 `~/.local/zig/zig-aarch64-macos-0.17.0/zig`에 있다(빌드는 컨테이너가 한다).
  2026-10-03 확인 때는 신호가 없었다(ghostty main은 `"0.16.0"`, PR #14519는 draft).

## 이미지 뷰어 메모 (기본 이미지에 넣지 않는다 — 사용자 결정, 2026-10-03)

- Debian `chafa`(1.14.5)는 바이너리 190KB지만 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를 끈다
  (`libSvtAv1Enc` · `librsvg-2` · `libaom` · `librav1e` 등). RAM 위 initrd에 늘 얹기에는 크다.
- 필요한 사람은 패키지 관리자로 설치한다. Homebrew `install.sh`는 root이면 멈추므로 non-root 사용자가 먼저다.
  설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 하고, DI의 설치 디스크 위다.
- 어느 뷰어든 `pty.zig`의 `ws_xpixel` · `ws_ypixel`(지금 0)을 우리가 채워야 한다(이월 숙제).

## 이어받는 사람이 볼 것

- Docker는 OrbStack이다. 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소는 이미지부터 굽는다(Dockerfile). 첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받고
  `clean()`이 지우지 않는다. `terminal/prepare.sh`가 `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons).
- 실칩 무선은 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 동글이 생기면 그것이 새 사실이다.
- 측정 파일(저장소 밖, 지워도 된다): `/tmp/run/*`, `/tmp/gate_*.log`. 디스크 여유는 충분하다. BS의 측정은
  `/tmp/run/bs0/`(사본 실측 `measure.out` · M0 루트 게이트 `gate.log` · dictation 재실행 `vd-rerun*.log`)과
  `/tmp/run/bs1/`(체인 `chain-*.log` · mutation `mut/` · 주기 경로 `m2period.out` · M1 루트 게이트 `gate.log`)에 있다.

## 남은 정리 (문서 감사에서 나온 것, 아직 적용 안 함)

- CLAUDE.md 완료 표(약 18KB)를 "서브프로젝트 · 끝난 날 · 한 줄 요약"으로 줄이거나 없앤다.
- lessons.md의 서브프로젝트별 "잰 것" 절(PD · AU · VD · TC · AL)은 함정만 주제별로 옮긴다.
- docs/decisions의 경과 절(gate_latency · userland_tools · shell_config 등)은 함정만 남긴다.
- CLAUDE.md의 두 규칙이 실제 관행과 어긋난다("구현 파일은 Claude가" vs 서브에이전트 구현, "다음 plan은 그 시점에" vs 앞 게이트 중 미리 쓰기). 어느 쪽이 기준인지 정해야 한다.
