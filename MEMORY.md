# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 색인이다. 본문은
`docs/decisions/`에 한 파일씩 들어 있다. 새 기억은
`docs/decisions/<name>.md`를 만들고 여기에 한 줄만 추가한다 — 본문을 이
파일에 쓰지 않는다. 줄이 길어지면 그것은 본문이 색인으로 새어 나온 것이다.

2026-09-12에 이 규칙대로 되돌렸다. 줄 여덟이 2~15KB까지 자라 본문을 통째로
복제하고 있었다(가장 긴 줄이 14,963바이트였고 본문 파일은 27,837바이트였다).
지운 내용은 전부 본문 파일에 있고, 지우기 전에 대조해서 확인했다.

파일 안의 `[[name]]` 링크는 `docs/decisions/`의 같은 이름 파일을 가리킨다.

현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 승인된 뒤의 git commit은 Claude가 만든다
- [Execution scope](docs/decisions/feedback_execution_scope.md) — 빌드·QEMU·게이트 명령은 Claude가 직접 실행하고(2026-08-22 변경), 구현 파일 편집만 사용자에게 남긴다
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 중 기술 선택지를 계속 묻지 말고 추천안으로 정해 진행한다
- [Push policy](docs/decisions/feedback_push_policy.md) — push는 묻지 말고 필요할 때 하고, 미푸시 커밋 수를 보고하지 않는다
- [Plain Korean](docs/decisions/feedback_plain_korean.md) — 비유를 일반 어휘 자리에 쓰지 않고, 조사·어미를 생략하지 않는다. 특히 제목과 첫 문장
- [No emphasis](docs/decisions/feedback_no_emphasis.md) — 문서와 주석에 `**` 강조를 쓰지 않는다(2026-09-12). 내용인 `**`는 남긴다 — md의 코드 블록과 Zig의 배열 반복 연산자
- [Boot never blocks](docs/decisions/feedback_boot_never_blocks.md) — 네트워크가 꺼져 있거나 안 닿아도 부팅은 평소대로 끝난다(2026-09-15). 타임아웃 위에 `fork`를 한 겹 더 덮고, 음성 검사로 증명한다

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — 목적은 속도가 아니라 이해다

## 프로젝트 (project)

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮긴 의도와 결말(2026-08-13 완료, 이제 Rust는 없다)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰면 libc를 링크하지 않는다; fortify를 끌 자리는 한 파일이 아니라 glibc를 읽는 블록 전부다
- [Build host arch](docs/decisions/project_build_host_arch.md) — 호스트는 arm64, 게스트 산출물은 x86_64 크로스; `--platform` 금지
- [Zig 산출물 staleness](docs/decisions/project_zig_out_staleness.md) — 빌드 산출물이 소스보다 낡은 채로 판정에 쓰인다(증상이 양쪽으로 난다); 처방은 음성 확인 전에 캐시를 컨테이너 안에서 지우는 것이다
- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식 둘을 감독한다; 감독 루프의 순서가 backoff를 만든다
- [Power management](docs/decisions/project_power_management.md) — ACPI·종료 경로 셋·시그널 핸들러가 없으면 관측조차 안 되는 성질
- [Device discovery](docs/decisions/project_device_discovery.md) — 입력 장치를 번호가 아니라 성질로 찾는다; 탐색은 버그 없이도 실패한다(USB는 비동기 열거라 3초까지 다시 본다)
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/config/tars.conf` 하나, 파서는 PID 1 한 벌, 영속성은 두 번 부팅으로만 증명된다
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트에 없어서 직접 넣어야 하는 것들(`PATH` · terminfo · 로케일)과 각각이 없을 때의 증상
- [Input policy](docs/decisions/project_input_policy.md) — evdev 코드를 셸이 아는 바이트로 번역하는 세 단계; 반환이 "바이트열 또는 동작"이라 스크롤 키가 PTY로 안 샌다
- [Terminal rendering](docs/decisions/project_terminal_rendering.md) — 색·오프셋·스크롤은 `vt.zig`에서 확정하고 렌더러는 숫자만 받는다; 라이브러리에 대해 짐작하면 틀리는 것들
- [Font selection](docs/decisions/project_font_selection.md) — 후보를 가르는 것은 커버리지가 아니라 16px 중간값 비율이다; 현재 폰트는 unifont 17.0.03
- [Kernel config](docs/decisions/project_kernel_config.md) — `olddefconfig`가 적어 둔 설정과 빌드하는 설정을 가른다; 게이트 시간의 근원은 부팅이 아니라 커널 빌드다
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 체인을 더하고 빼는 규칙; 게이트는 자기가 안 보는 것을 통과시킨다
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 고르고 기억하는 기능의 배경
- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위의 vim modal 선택 모드와 Cmd+V(CM-M0~M2, 2026-08-26 종료)
- [Copy navigation](docs/decisions/project_copy_navigation.md) — copy 커서에 얹은 이동 수단 둘 — 단어 이동과 검색(CN-M0·M1, 2026-08-27 종료)
- [Copy search feedback](docs/decisions/project_copy_search_feedback.md) — 검색이 사람에게 보이게 만든 층 — 하이라이트·검색 기록·"못 찾음"(CS-M0·M1, 2026-08-28 종료)
- [Search position](docs/decisions/project_search_position.md) — "지금 몇 번째 매치인가"를 꺼내는 자리와 그 위의 색·번호(SP-M0·M1, 2026-08-30 종료)
- [Gate latency](docs/decisions/project_gate_latency.md) — 게이트 54분 15초를 16분대로 내린 길과 그 과정에서 틀린 접근들(GL-M0~M3, 2026-08-29 종료)
- [Render cost](docs/decisions/project_render_cost.md) — 한 프레임의 비용을 구간별로 갈라 잰 결과 — 답은 `fill` 84.7%(RC-M0, 2026-08-30 종료, 코드는 안 고쳤다)
- [Target hardware](docs/decisions/project_target_hardware.md) — TARS는 노트북 사용을 포함한다(사용자, 2026-08-31); 실머신 `.config`가 서브프로젝트 하나라는 판단의 근거 — 그 일은 RM이 했다
- [Carryover cleanup](docs/decisions/project_carryover_cleanup.md) — 이월 숙제 셋을 없앤 CC-M0(2026-08-31)과 그때 배운 게스트 조작 방법들
- [Hangul input](docs/decisions/project_hangul_input.md) — 한글을 치는 층 — 자판 여섯과 전환 키 넷(HI-M0~M3, 2026-09-01 종료)
- [Input status](docs/decisions/project_input_status.md) — 화면 맨 아래 여백의 상태 줄 한 줄(IS-M0·M1, 2026-09-09 종료)
- [Search hangul](docs/decisions/project_search_hangul.md) — copy mode 검색창에서 한글을 치는 층(SH-M0~M2, 2026-09-09 종료)
- [Real machine](docs/decisions/project_real_machine.md) — 일반 x86_64 노트북에서 뜨는 커널 — UEFI·simpledrm·USB 키보드·NVMe(RM-M0~M3, 2026-09-10 종료)
- [Userland tools](docs/decisions/project_userland_tools.md) — 게스트 도구 65개와 그 이름이 손에 닿게 한 `PATH`(UT-M0~M3, 2026-09-11 종료)
- [Shell config](docs/decisions/project_shell_config.md) — 셸이 사용자의 rc를 읽고 그 파일이 부팅 사이에 살아남게 한 층(SC-M0~M2, 2026-09-11 종료)
- [Shell memory](docs/decisions/project_shell_memory.md) — 기계가 배운 것 둘(자주 간 디렉터리 · 쳤던 명령)을 부팅 너머로 남기는 층(SM-M0~M2, 2026-09-12 종료)
- [Gate accuracy](docs/decisions/project_gate_accuracy.md) — 게이트가 거짓 판정을 내던 일곱 자리와 그것을 막는 진입 검사(GA-M0·M1, 2026-09-12 종료)
- [Shutdown signals](docs/decisions/project_shutdown_signals.md) — zsh와 bash는 SIGTERM을 무시하고 fish는 안 무시한다; 종료 경로에서 무엇이 저장되는지는 누가 먼저 죽어 PTY를 닫는지에 갈린다
- [Shutdown latency](docs/decisions/project_shutdown_latency.md) — PID 1이 SIGTERM 뒤에 SIGHUP도 보낸다; 콘솔 셸이 유예를 꽉 쓰던 2.9초가 0.13초가 됐다
- [Shell history](docs/decisions/project_shell_history.md) — 콘솔 셸에 친 명령이 전원 버튼과 함께 사라지던 것을 씨앗 rc의 한 줄로 고친 층. zsh는 `setopt INC_APPEND_HISTORY`(SD-M0~M2), bash는 `PROMPT_COMMAND='history -a'`(BH-M0~M2), 둘 다 2026-09-12 종료
- [Measuring shells](docs/decisions/project_measuring_shells.md) — 셸을 재는 환경이 실제로 돌 환경과 다르면 값이 조용히 틀린다. 게스트에 `/dev/fd`가 없는 것 · `script`가 끼우는 래퍼 · 비대화형 셸이 프롬프트 훅을 안 도는 것
- [Bash boot](docs/decisions/project_bash_boot.md) — 게이트가 `shell=bash`로 뜨는 부팅을 하나 갖게 된 일. `config` 체인이 부팅 아홉이 됐고, 중첩 bash로는 정의상 볼 수 없던 여섯을 그 아홉째가 본다(BB-M0~M2, 2026-09-12 종료)
- [Write or reuse](docs/decisions/project_write_or_reuse.md) — "커널 다음은 전부 내 코드"는 절대 원칙이 아니다; 직접 짜는 자리는 배울 값이 있거나 원하는 모양이 남의 것과 다른 자리다(NW 설계 중 사용자가 정했다, 2026-09-13)
- [Measuring tool cost](docs/decisions/project_measuring_tool_cost.md) — 게스트에 도구를 넣기 전에 실제 비용을 재는 절차. 패키지 의존이 아니라 재귀 `DT_NEEDED`를 본다; `curl` 하나가 13MB 중 86%였다(NW-M0, 2026-09-13)
- [Seeding a config disk](docs/decisions/project_seeding_a_config_disk.md) — `debugfs`가 마운트도 특권도 없이 ext2 이미지에 파일을 쓴다; 체인이 부팅 하나로 `tars.conf`의 키를 시험할 수 있다(NW-M2, 2026-09-13)
- [게이트의 화면 판정은 자기가 친 명령도 화면으로 센다](docs/decisions/project_gate_screen_echo.md) — `wait_for_screen`이 로그 전체의 `screen>` 줄을 보므로 판정 글자는 출력에만 있어야 한다(NW-M3, 2026-09-14). 게스트에 배경으로 심는 job은 stdin을 `< /dev/null`로 끊고, 로그에서 찾는 이름은 숫자만으로 되면 안 된다(TS-M2, 2026-09-15)
- [Guest network](docs/decisions/project_guest_network.md) — `tars.conf`의 `net=dhcp`가 게스트에 주소를 붙인다; 우리 코드는 링크를 올리고 dhcpcd를 띄우는 두 줄이고 게이트 판정은 SLIRP 안에서 닫힌다(NW-M0~M3, 2026-09-14 종료)
- [Inbound network](docs/decisions/project_inbound_network.md) — 게스트가 연 포트에 바깥에서 붙어 바이트를 읽는다; 판정은 `rc`가 아니라 받은 바이트 수이고 우리 코드는 0줄이다(IN-M0~M2, 2026-09-14 종료)
- [터미널 질의](docs/decisions/project_terminal_queries.md) — terminal이 자식의 vt 질의(커서 위치·상태 보고)에 답한다; `effects.write_pty` 한 칸이 전부이고 답은 라이브러리가 만든다. 그래서 fzf의 `--height` 상자가 첫 Ctrl+R에 뜬다(TQ-M1, 2026-09-19 종료. ST-M3의 `--no-height` 우회는 지웠다)
- [Shell tools](docs/decisions/project_shell_tools.md) — 깔려 있던 도구를 셸이 쓴다 — eza 별칭 넷(`ls` 셰도)과 `[user]` 없는 gitconfig 씨앗, 그리고 그 둘을 재는 검사 둘(ST-M0~M2, 2026-09-19 종료)
- [Disk install](docs/decisions/project_disk_install.md) — `tars-install`이 GPT에 ESP(p1)와 `tars-config`(p2)를 만들고 USB 없이 뜬다; `init`의 후보가 디스크 다음 파티션이 됐고 안전은 라벨이 지킨다. ISO 부팅은 표지 `tars.installed`가 없어 p2를 안 붙이고, 갱신은 설정을 남긴다(DI-M1·M2, 2026-09-23)
- [Disk carryover](docs/decisions/project_disk_carryover.md) — 설치된 부팅이 설정 파티션을 최대 5초 기다린다(게이트의 틈은 TCG의 initramfs 풀기가 덮고 있었다 — `delay_use=3`으로 벌려 판정); 4Kn GPT · 옛 ISO 서명 · 넘치는 줄 · YES를 줄로(DC-M0~M2, 2026-09-26 종료)
- [Time discipline](docs/decisions/project_time_discipline.md) — 시계를 chronyd에게 넘겼다; init은 fork · 설정 · execve 배관만. 커널이 주파수를 기억하고, 같은 server는 먼저 적힌 쪽이 이기며, chrony는 주소 전의 실패를 iburst로 안 센다(TD-M0·M1, 2026-09-26)
