# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 색인이다. 본문은 `docs/decisions/`에 한 파일씩 들어 있다. 새 기억은
`docs/decisions/<name>.md`를 만들고 여기에 한 줄만 추가한다 — 줄은 "무엇에 대한 기억인가"와 끝난 날까지만 쓰고, 함정 ·
수치 · 처방은 본문에 둔다. 줄이 길어지면 그것은 본문이 색인으로 새어 나온 것이다(2026-09-12 · 10-20 · 11-01에 되돌렸다).

파일 안의 `[[name]]` 링크는 `docs/decisions/`의 같은 이름 파일을 가리킨다. 현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 승인된 뒤의 git commit은 Claude가 만든다, 서브에이전트는 안 한다
- [Execution scope](docs/decisions/feedback_execution_scope.md) — 명령 실행과 구현 파일은 Claude(또는 서브에이전트)가, 사용자의 검토는 읽기다
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 중 기술 선택지를 계속 묻지 말고 추천안으로 정해 진행한다
- [Stepwise report](docs/decisions/feedback_stepwise_report.md) — 조사 · 구현을 단계로 나눠 단계마다 결과를 보고하고 확인받은 뒤 넘어간다(2026-11-06)
- [Push policy](docs/decisions/feedback_push_policy.md) — push는 묻지 말고 필요할 때 하고, 미푸시 커밋 수를 보고하지 않는다
- [Plain Korean](docs/decisions/feedback_plain_korean.md) — 비유를 일반 어휘 자리에 쓰지 않고, 조사 · 어미를 생략하지 않는다
- [No emphasis](docs/decisions/feedback_no_emphasis.md) — 문서와 주석에 `**` 강조를 쓰지 않는다. 내용인 `**`는 남긴다
- [Boot never blocks](docs/decisions/feedback_boot_never_blocks.md) — 네트워크가 꺼져 있거나 안 닿아도 부팅은 평소대로 끝난다
- [Jargon translation](docs/decisions/feedback_jargon_translation.md) — 정착한 영어 jargon(seed · mutation)은 번역하지 않고 조사를 붙인다
- [Gate runs](docs/decisions/feedback_gate_runs.md) — 루트 게이트 반복은 1회, 가끔 `-e RUNS=N`으로 늘린다
- [Scripting runtimes](docs/decisions/feedback_scripting_runtimes.md) — 스크립팅 런타임은 한 묶음으로만 들이고, 지금은 perl로 간다
- [Release 0.2](docs/decisions/project_release_0_2.md) — 0.2.0은 TP 전체를 끝낸 뒤, 그 사이 실기 확인은 `dev-<날짜>` 프리릴리스(2026-11-06)
- [Minimal ISO](docs/decisions/project_minimal_iso.md) — 릴리스마다 barebone ISO도, 납품 실행 파일은 묶음 하나 + 자동 실행 조각, 데모 fakesteak(BB-M0~M1, 2026-11-09)
- [Dev Layer](docs/decisions/project_dev_layer.md) — 묶음 열을 squashfs로 실어 `/usr`에 겹치는 개발 도구 층, 망 없이 개발(TP-M0~M12, 2026-11-09)
- [Manifest Format](docs/decisions/project_manifest_format.md) — 개발 도구의 출처는 `devlayer/manifest.toml`, Zig 변환기가 TSV를 생성(MF-M0, 2026-11-09)
- [Fullscreen](docs/decisions/project_fullscreen.md) — 여백 · 상태 줄 없이, Cmd+Ctrl+F · `fullscreen=` · 패널의 `CSI 10;Ps t`, 조각은 sh -c + trap(FU-M0~M1, 2026-11-09)
- [Server persistence](docs/decisions/project_server_persistence.md) — 서버 다섯은 `tars-service enable`로 서비스, 데이터 `/home/.tars/var`, 조각 `/config/<서버>.d`, CA는 부팅 때 다시 믿는다(TP-M11, 2026-11-08)
- [First steps guide](docs/decisions/project_first_steps_guide.md) — 설치 뒤 '뭘 하지'에 답하는 안내를 기계 안에(Wi-Fi · 블루투스 · config · service · 문서), FS-M0로 끝남(2026-11-07)
- [Release iteration](docs/decisions/feedback_release_iteration.md) — 맥 실기 확인까지 0.1.4를 같은 번호로 거듭 내고, 이전 판의 흔적은 안 남긴다(2026-11-05)
- [Devcontainer additions](docs/decisions/feedback_devcontainer_additions.md) — 개발 컨테이너에 필요한 도구는 묻지 않고 더한다(2026-11-05)
- [Tool sourcing](docs/decisions/feedback_tool_sourcing.md) — 도구의 출처(바닥은 Debian, 유틸리티는 공식 바이너리, 소스 빌드 없음)와 initrd · 개발 도구 층의 기준(2026-11-05)
- [IPv4 only](docs/decisions/feedback_ipv4_only.md) — IPv6는 후보에서 뺐다(2026-10-31). 다시 여는 조건은 IPv6 망의 제품 탑재
- [net · ntp 기본값은 off](docs/decisions/feedback_network_default_stays_off.md) — seed의 `net` · `ntp`는 `off`, 켜는 법은 문서로
- [superpowers 제거](docs/decisions/feedback_superpowers_off.md) — superpowers plugin을 user scope에서 지운 이유(2026-10-03)

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — 목적은 속도가 아니라 이해다
- [Editor use](docs/decisions/user_editor_use.md) — 코드 작업은 neovim · helix, 게스트 vim은 대충 쓴다(VR 취소, 2026-10-27)

## 참고 (reference)

- [ghostty source](docs/decisions/reference_ghostty_source.md) — 참고는 `_study/ghostty`(최신), `terminal/ghostty-src`는 빌드 입력(2026-10-28)

## 프로젝트 (project)

규칙과 판단

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮긴 의도와 결말(2026-08-13 완료)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰면 libc를 링크하지 않는다, fortify를 끌 자리
- [Build host arch](docs/decisions/project_build_host_arch.md) — 호스트는 arm64, 게스트 산출물은 x86_64 크로스, `--platform` 금지
- [Zig 산출물 staleness](docs/decisions/project_zig_out_staleness.md) — 낡은 빌드 산출물이 판정에 쓰이는 일과 캐시 지우기 처방
- [Target hardware](docs/decisions/project_target_hardware.md) — TARS는 노트북 사용을 포함한다(2026-08-31), 그 일은 RM이 했다
- [Write or reuse](docs/decisions/project_write_or_reuse.md) — 직접 짜는 자리는 배울 값이 있거나 원하는 모양이 남의 것과 다른 자리다
- [Measuring tool cost](docs/decisions/project_measuring_tool_cost.md) — 게스트에 도구를 넣기 전에 재귀 `DT_NEEDED`로 비용을 재는 절차
- [Measuring shells](docs/decisions/project_measuring_shells.md) — 셸을 재는 환경이 실제 환경과 다르면 값이 조용히 틀린다
- [Release](docs/decisions/project_release.md) — 0.1.0 · 0.1.1 · 0.1.2 · 0.1.3(2026-11-01) · 0.1.4(2026-11-05) · 0.2.0(2026-11-10, ISO 셋)과 배포 절차 일곱 단계(tag가 `make iso`보다 먼저, 줄끝 CRLF가 만드는 `-dirty`)
- [Build Version](docs/decisions/project_build_version.md) — `VERSION` + git 꼬리표가 `tars-config version`과 부팅 첫 줄에(BV-M0, 2026-10-20)
- [Zig upgrade](docs/decisions/project_zig_upgrade.md) — Zig 0.17 이상, `**` 대신 `@splat` · ghostty를 따라 SHA로 고정, 없어진 std 선언과 대체 표(ZU, 2026-10-24)
- [Lessons Split](docs/decisions/project_lessons_split.md) — lessons.md를 허브와 measurements · dead-ends · carryover · key-files로(LS-M0, 2026-10-26)

게이트

- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 체인을 더하고 빼는 규칙
- [Gate latency](docs/decisions/project_gate_latency.md) — 게이트를 54분에서 16분대로 내린 길과 틀린 접근들(GL-M0~M3, 2026-08-29)
- [Gate accuracy](docs/decisions/project_gate_accuracy.md) — 거짓 판정 일곱 자리와 진입 검사(GA-M0 · M1, 2026-09-12)
- [Gate screen echo](docs/decisions/project_gate_screen_echo.md) — 화면 판정은 자기가 친 명령도 센다(NW-M3, TS-M2, 2026-09-15)
- [Seeding a config disk](docs/decisions/project_seeding_a_config_disk.md) — `debugfs`로 ext2 이미지에 파일을 써서 키를 시험한다(NW-M2, 2026-09-13)
- [Gate Parallel](docs/decisions/project_gate_parallel.md) — prebuild 한 번 뒤 동시 `JOBS`줄, 1시간 → 10분(GP-M0~M2, 2026-10-10)
- [Atomic Log Lines](docs/decisions/project_atomic_log_lines.md) — 시리얼 로그 한 줄을 write 한 번으로(AL-M0 · M1, 2026-10-07)
- [Gate Flakes](docs/decisions/project_gate_flakes.md) — initrd는 prebuild 한 번, 로그는 `out/gate-logs/`에(GF-M0~M2, 2026-10-24)
- [Reserved ports](docs/decisions/project_reserved_ports.md) — 체인 포트 45455~45599를 ephemeral 범위에서 뺐다, `docker run --sysctl`(RP-M0, 2026-11-01)
- [GitHub Actions](docs/decisions/project_github_actions.md) — `checks.yml`의 host · container job, 게이트는 안 돌린다(GH-M0~M1, 2026-10-30) · shellcheck note 판정(SN) · 받는 자리 sha256(VS) · ghcr.io 이미지(GI, 2026-10-31)

init · 설정 · 전원

- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식을 감독한다
- [Power management](docs/decisions/project_power_management.md) — ACPI · 종료 경로 셋 · 시그널 핸들러
- [Device discovery](docs/decisions/project_device_discovery.md) — 입력 장치를 번호가 아니라 성질로 찾는다
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/config/tars.conf` 하나, 파서는 PID 1 한 벌
- [Config fs ext2](docs/decisions/project_config_fs_ext2.md) — `/config`는 ext2, ext4가 아니다 — sync 마운트와 rename 교체가 저널 자리를 지킨다 · ext4로 갈 세 신호(2026-11-02)
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸 선택 요청(2026-08-11)과 미구현 둘(nushell · 자동 기억)
- [Screen Args](docs/decisions/project_screen_args.md) — init → terminal argv 계약은 `shared/screen_args.zig` 한 파일(SA-M0~M1, 2026-10-24)
- [Main Split](docs/decisions/project_main_split.md) — terminal `main`은 `App.open` · `tick` · `close`, init `main`은 `Boot`(MS-M0~M1, 2026-10-25)
- [Host Checks](docs/decisions/project_host_checks.md) — tars-config · tars-install의 순수한 것을 짝 모듈로 내려 호스트 검사에(HC-M0~M2, 2026-10-26)
- [Lean Initrd](docs/decisions/project_lean_initrd.md) — initrd의 우리 바이너리 다섯은 사본만 `--strip-debug`, 주소는 호스트 원본에 `addr2line`(LI-M0~M1, 2026-10-26)
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트에 직접 넣어야 하는 것들(`PATH` · terminfo · 로케일)
- [Kernel config](docs/decisions/project_kernel_config.md) — `olddefconfig`가 적어 둔 설정과 빌드하는 설정을 가른다
- [Real machine](docs/decisions/project_real_machine.md) — 일반 x86_64 노트북에서 뜨는 커널(RM-M0~M3, 2026-09-10)
- [Carryover cleanup](docs/decisions/project_carryover_cleanup.md) — 이월 숙제 셋과 게스트 조작 방법들(CC-M0, 2026-08-31)
- [Shutdown signals](docs/decisions/project_shutdown_signals.md) — 종료 때 무엇이 저장되는지는 누가 먼저 죽는지에 갈린다, TERM 뒤 HUP의 뜻
- [Shutdown latency](docs/decisions/project_shutdown_latency.md) — PID 1이 SIGTERM 뒤에 SIGHUP도 보낸다(2.9초 → 0.13초, SL, 2026-09-13)
- [Disk install](docs/decisions/project_disk_install.md) — `tars-install`이 ESP와 설정 파티션을 만들고 디스크로 뜬다(DI, 2026-09-23) · 설치된 부팅의 5초 기다림 · 4Kn · 옛 ISO 서명(DC, 2026-09-26)
- [Kernel upgrade](docs/decisions/project_kernel_upgrade.md) — 이미지 슬롯 둘 · 1GiB ESP · Limine 메뉴의 old 엔트리, 커널 6.18.60(KU-M0~M1, 2026-11-01)
- [Bluetooth](docs/decisions/project_bluetooth.md) — 커널 BT 스택 + BlueZ · dbus-daemon을 init이 감독, `bluetooth=on`, 키는 `/config/bluetooth`, vhci 게이트(BT-M0~M2, 2026-11-02)
- [Keyboard Hotplug](docs/decisions/project_keyboard_hotplug.md) — terminal이 키보드를 포인터의 길로 열고 여럿이 상태 하나를 쓴다, 빠지면 `releaseHeld`(KH-M0~M2, 2026-11-02)
- [Home Partition](docs/decisions/project_home_partition.md) — p3 ext4 `/home`, 설치 때 계정 하나, 화면 셸은 사용자, `/config` 쓰기는 sudo(HP-M0~M2, 2026-11-03)
- [Package Manager](docs/decisions/project_package_manager.md) — Homebrew 공식 install.sh가 TARS에서 끝까지 가고 bottle이 선다, 시스템 rc의 shellenv, libstdc++ 이름(PM-M0~M1, 2026-11-03)
- [Mise](docs/decisions/project_mise.md) — 공식 mise.run과 mise use -g node@lts가 이미지 변경 0으로 선다, 시스템 rc의 mise activate(MI-M0~M1, 2026-11-03)
- [Init Keyboard](docs/decisions/project_init_keyboard.md) — PID 1의 키보드 고르기 · 3초 · argv 장치 칸을 걷었다, ARGC 9, 체인은 terminal의 keyboard> open으로(IK-M0, 2026-11-03)
- [Device Modifiers](docs/decisions/project_device_modifiers.md) — 수정키 · tap을 키보드 칸마다, 빠진 칸만 푼다, 커널 자동 반복이 결함을 가린다(DM-M0~M1, 2026-11-04)
- [Keyboard Kind](docs/decisions/project_keyboard_kind.md) — keyboard=auto 기본값, 키보드마다 vendor로 Alt · Meta 맞바꿈, Cmd 체인은 keyboard=apple 디스크(KK-M0~M1, 2026-11-04)
- [Pointer Settings](docs/decisions/project_pointer_settings.md) — 휠 방향 · 가속 0~10을 종류마다 칸에, `Ballistics`, 같은 값 조합은 '종류를 안 본다'를 못 잡는다(PS-M0~M1, 2026-11-04)
- [MacBook Hardware](docs/decisions/project_macbook_hardware.md) — 맥 트랙패드는 bcm5974 없이 아예 안 움직인다, ACPI_SBS, HID_APPLE은 끈 채(MB-M0, 2026-11-05)
- [HiDPI Scale](docs/decisions/project_hidpi_scale.md) — 논리 그림자 + 늘리는 present, display_scale(HS-M0, 2026-11-05)
- [Dual Boot](docs/decisions/project_dual_boot.md) — tars-install --beside · 파티션 지정, TARS 파티션은 GPT 이름으로, 포맷 전 대조 둘(DB-M0 · M1, 2026-11-05)
- [Password Feedback](docs/decisions/project_password_feedback.md) — 비밀번호 칸의 `*`, secret.zig, Ctrl+C를 바이트로(PW-M0, 2026-11-05)
- [Power Commands](docs/decisions/project_power_commands.md) — reboot · poweroff · shutdown · suspend 스크립트, 인자가 권한보다 먼저(RB-M0, 2026-11-05)
- [Laptop Power](docs/decisions/project_laptop_power.md) — i915 · S3 · 밝기, rootfs가 tmpfs로 바뀌는 함정(LP-M0~M2, 2026-11-05)
- [Broadcom Wireless](docs/decisions/project_broadcom_wireless.md) — Air4,1 내장 BCM43224를 brcmsmac으로, Pro의 둘은 못 연다(BW-M0, 2026-11-05)
- [Nerd Symbols](docs/decisions/project_nerd_symbols.md) — Powerline 넷을 sprite.zig이 코드로, render 체인 색 셀의 함정 넷(NS-M0, 2026-11-08)
- [Boot services](docs/decisions/project_boot_services.md) — `/config/services.d`를 init이 감독한다, 첫 세입자 sshd(SV-M0~M2, 2026-09-27)
- [Service control](docs/decisions/project_service_control.md) — `tars-service`가 소켓으로 PID 1에게 명령한다(CT-M0~M2, 2026-09-27)
- [Daemon supervision](docs/decisions/project_daemon_supervision.md) — dhcpcd와 chronyd를 감독 목록에(DS-M0~M2, 2026-09-27)
- [Config Tool](docs/decisions/project_config_tool.md) — 게스트의 `tars-config`가 `/config`를 보고 · 고치고 · 적용한다(TC-M0~M3, 2026-10-07)
- [Config reload](docs/decisions/project_config_reload.md) — `tars-config reload`가 재부팅 없이 설정을 다시 읽게 한다(TC-M2 · M3, 2026-10-07)
- [Clock reload](docs/decisions/project_clock_reload.md) — reload의 chronyd restart · stop · start를 net 검사 32가 본다(CR-M0, 2026-10-28)
- [Battery Status](docs/decisions/project_battery_status.md) — 상태 줄 오른쪽 끝의 잔량 칸과 게이트의 가짜 배터리(BS-M0 · M1, 2026-10-09)

네트워크

- [Guest network](docs/decisions/project_guest_network.md) — `net=dhcp`가 게스트에 주소를 붙인다(NW-M0~M3, 2026-09-14)
- [Inbound network](docs/decisions/project_inbound_network.md) — 게스트가 연 포트에 바깥에서 붙는다(IN-M0~M2, 2026-09-14)
- [Time discipline](docs/decisions/project_time_discipline.md) — 시계를 chronyd에게 넘겼다(TD-M0~M2, 2026-09-26)
- [Wired NIC](docs/decisions/project_wired_nic.md) — 노트북형 유선 드라이버와 모든 QEMU 호출의 NIC 명시(WN-M0~M3, 2026-09-26)
- [Loopback](docs/decisions/project_loopback.md) — `lo`를 올리고 `localhost`를 푼다(LB-M0~M3, 2026-09-26)
- [Firewall](docs/decisions/project_firewall.md) — `firewall=on`이 들어오는 것을 기본으로 버린다(FW-M0~M2, 2026-09-27)
- [Wireless](docs/decisions/project_wireless.md) — wpa_supplicant 감독과 PCIe firmware, 게이트는 mac80211_hwsim(WL-M0~M3, 2026-09-28)
- [USB wireless](docs/decisions/project_usb_wireless.md) — 같은 칩 계열의 USB 동글 열하나, 코드 0줄(UW-M0~M2, 2026-09-28)
- [USB dongles B](docs/decisions/project_usb_dongles_b.md) — UW가 남긴 USB 동글 드라이버 여섯, firmware +21, 코드 0줄(UB-M0~M2, 2026-10-31)

terminal · 화면

- [Input policy](docs/decisions/project_input_policy.md) — evdev 코드를 셸이 아는 바이트로 번역하는 세 단계
- [Terminal rendering](docs/decisions/project_terminal_rendering.md) — 색 · 오프셋 · 스크롤은 `vt.zig`가 확정하고 렌더러는 숫자만 받는다
- [Font selection](docs/decisions/project_font_selection.md) — 폰트를 고르는 기준과 현재 폰트 unifont 17.0.03, FR-M0(2026-10-31)부터 저장소에 커밋
- [Render cost](docs/decisions/project_render_cost.md) — 한 프레임의 비용을 구간별로 잰 결과(RC-M0, 2026-08-30)
- [Render Speed](docs/decisions/project_render_speed.md) — 행마다 `@memset` · 16ms 하한 · DIRTYFB(RS-M0~M3, 2026-10-11)
- [Dirty rows](docs/decisions/project_dirty_rows.md) — 부분 갱신: 바뀐 행만 칠하고 clip으로, `cells()`도 증분, 정답지는 fresh 목록과 verify(DR-M0~M3, 2026-10-30)
- [Status band](docs/decisions/project_status_band.md) — 상태 줄 띠는 내용이 바뀐 프레임에만, `StatusMemo` 하나가 정한다(SB-M0, 2026-10-30)
- [Input status](docs/decisions/project_input_status.md) — 화면 맨 아래의 상태 줄(IS-M0 · M1, 2026-09-09)
- [Hangul input](docs/decisions/project_hangul_input.md) — 자판 여섯과 전환 키 넷(HI-M0~M3, 2026-09-01)
- [Escape Latin](docs/decisions/project_escape_latin.md) — 한글 중 Esc는 확정하고 영문으로, `esc_latin`(EL-M0, 2026-10-05)
- [Terminal queries](docs/decisions/project_terminal_queries.md) — 자식의 vt 질의에 terminal이 답한다(TQ-M1, 2026-09-19)
- [Terminal graphics](docs/decisions/project_terminal_graphics.md) — kitty graphics 이미지를 우리 렌더러가 그린다(TG-M0~M3, 2026-10-03)
- [Cursor shape](docs/decisions/project_cursor_shape.md) — DECSCUSR 커서 모양 셋과 게스트 vi를 `vim.basic`으로(CU-M0 · M1, 2026-10-04)
- [Workspace panes](docs/decisions/project_workspace_panes.md) — 워크스페이스 아홉 × 패널 여덟(WP-M0~M2, 2026-10-04) · 방향 포커스 Cmd+Option+화살표(WP-M3, 2026-10-27)
- [Loose ends](docs/decisions/project_loose_ends.md) — 화면이 copy mode를 닫으면 입력 모드도 normal, PTY 픽셀, carryover 정리(LE-M0, 2026-10-27)
- [Pointer devices](docs/decisions/project_pointer_devices.md) — 마우스 · 터치패드와 드래그 선택(PD-M0~M4, 2026-10-05)
- [Multi click](docs/decisions/project_multi_click.md) — 더블클릭 단어 · 트리플클릭 줄, 횟수는 `pointer.Gesture`, 시각은 단조 `ev.time`(MC-M0~M2, 2026-11-01)
- [Shift Extend](docs/decisions/project_shift_extend.md) — 끌어 떼도 선택이 남고 Shift 클릭이 가까운 끝을 옮긴다, 다음 누름이 지운다(SE-M0~M1, 2026-11-01)
- [Extend Repeat](docs/decisions/project_extend_repeat.md) — 남은 선택 위 Shift 더블 · 트리플클릭이 단어 · 줄로 는다, QEMU `sendkey N`은 큐를 2N ms 쥔다(ER-M0, 2026-11-01)

copy mode · 클립보드

- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위의 vim modal 선택과 Cmd+V(CM-M0~M2, 2026-08-26)
- [Copy navigation](docs/decisions/project_copy_navigation.md) — 단어 이동과 검색(CN-M0 · M1, 2026-08-27)
- [Copy search feedback](docs/decisions/project_copy_search_feedback.md) — 하이라이트 · 검색 기록 · "못 찾음"(CS-M0 · M1, 2026-08-28)
- [Search position](docs/decisions/project_search_position.md) — 몇 번째 매치인가와 그 색 · 번호(SP-M0 · M1, 2026-08-30)
- [Search hangul](docs/decisions/project_search_hangul.md) — 검색창에서 한글을 친다(SH-M0~M2, 2026-09-09)
- [Copy indicator](docs/decisions/project_copy_indicator.md) — copy mode 동안 상태 줄의 `COPY` 칸(CI-M0, 2026-10-03)
- [Paste ergonomics](docs/decisions/project_paste_ergonomics.md) — bracketed paste와 `/config/vimrc`(PE-M0~M2, 2026-10-04)
- [Clipboard scope](docs/decisions/project_clipboard_scope.md) — 클립보드가 terminal에 하나, `clipboard=pane`(CB-M0, 2026-10-05)

셸 · 도구

- [Userland tools](docs/decisions/project_userland_tools.md) — 게스트 도구 목록은 `kernel/guest_tools.sh` 하나, `PATH`(UT-M0~M3, 2026-09-11)
- [Shell config](docs/decisions/project_shell_config.md) — 사용자의 rc가 부팅 사이에 살아남는다(SC-M0~M2, 2026-09-11)
- [Shell memory](docs/decisions/project_shell_memory.md) — 자주 간 디렉터리 · 쳤던 명령을 부팅 너머로(SM-M0~M2, 2026-09-12)
- [Shell history](docs/decisions/project_shell_history.md) — 전원 버튼에 사라지던 콘솔 history를 seed rc로 고쳤다, seed 규칙의 정본(SD · BH, 2026-09-12)
- [Bash boot](docs/decisions/project_bash_boot.md) — 게이트에 `shell=bash` 부팅 하나(BB-M0~M2, 2026-09-12)
- [Shell tools](docs/decisions/project_shell_tools.md) — eza 별칭과 gitconfig seed(ST-M0~M2, 2026-09-19)
- [Guest ergonomics](docs/decisions/project_guest_ergonomics.md) — `which`와 모던 시스템 vimrc(GE-M0 · M1, 2026-10-04)
- [Voice dictation](docs/decisions/project_voice_dictation.md) — 오른쪽 Cmd 두 번 → Groq Whisper → 커서 자리에(VD-M0~M2, 2026-10-06)
- [Audio devices](docs/decisions/project_audio_devices.md) — 스피커 · 마이크 · 헤드폰 · USB 헤드셋 · DMIC(AU-M0~M3, 2026-10-06)

조사만 한 것

- [latticedb survey](docs/decisions/project_latticedb_survey.md) — Zig 임베디드 그래프 DB, 한글 FTS가 안 돼 안 쓴다(2026-10-01)
- [termium survey](docs/decisions/project_termium_survey.md) — 터미널 안의 Chromium, 게스트 권한에서 막힌다(2026-10-01)
