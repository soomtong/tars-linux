# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 색인이다. 각 항목의 본문은
`docs/decisions/`에 한 파일씩 들어 있다. 새 기억을 추가할 때는
`docs/decisions/<name>.md`를 만들고 여기에 한 줄을 추가한다 — 본문을 이
파일에 쓰지 않는다.

파일 안의 `[[name]]` 링크는 `docs/decisions/` 안의 같은 이름 파일을 가리킨다.

현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 파일 작성·명령 실행은 사용자, 승인된 뒤의 git commit은 Claude
- [Execution scope](docs/decisions/feedback_execution_scope.md) — 2026-08-22부터 build/QEMU/게이트 명령은 **Claude가 직접 실행한다**(그 전에는 금지였다); 구현 파일 편집은 검토 지점이라 사용자에게 남고, 설명 먼저·결과 해석은 그대로
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 단계에서 기술적 선택지를 계속 묻지 말 것; 추천안으로 정해서 진행하되 설명은 그대로 유지

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — TARS 작업의 목적은 속도가 아니라 이해; why 설명을 충실히, pair-programming 방식 유지

## 프로젝트 (project)

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — TARS를 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮기려던 의도와 결말(2026-08-13 완료): `init`은 이식, `kms`는 중복이라 삭제, 툴체인도 제거 — 이제 Rust는 없다
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 bash/zsh/fish/nushell 중 선택하고 마지막 것을 기억하는 미래 기능; 영속 저장소가 선행 조건(현재 initrd는 tmpfs)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰는 컴포넌트는 libc를 링크하지 말고 `std.os.linux`로; libc가 필요할 때만 `@cImport`(구조체는 되고 ioctl 매크로는 안 되며 최적화 모드에서 fortify로 깨진다)
- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식 둘을 감독한다(`waitpid(-1)`로 고아까지 수거, 연속 3회면 포기, `noreturn`); HD-M2가 감독 루프를 `poll`(전원 버튼 fd, 1초) + `waitpid(WNOHANG)` 구조로 바꿨고 **거두기를 `poll`보다 앞에 둔 순서가 1초 backoff를 대신한다**; 이 코드의 진짜 계약은 BF의 "3회"와 PM의 "되살리지 않는다"에 있다
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 루트 `check.sh`는 BF+TF 두 체인; 무의미해진 게이트는 주석만 남기지 말고 파일째 은퇴, `clean()`은 vendor 트리를 안 건드림, 게이트는 자기가 안 보는 것을 통과시키므로 재작성 전에 검사부터 추가
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/dev/vda`의 ext2를 `MS_SYNCHRONOUS`로 붙인 `/config/tars.conf` 하나; PID 1이 부팅 시점에 한 번 읽어 argv로 흘려보내고, 깨진 설정으로 부팅이 막히지 않게 하는 장치가 넷, 영속성은 QEMU를 두 번 띄우는 게이트로만 증명된다
- [Input policy](docs/decisions/project_input_policy.md) — 키 입력은 evdev 코드를 셸이 이미 아는 바이트로 번역하는 일: macOS 조합은 `ESC` 접두사·제어 문자로(A안, 이유는 검증 가능성), 키보드 차이는 파이프라인 맨 앞의 코드 교환 한 번으로, 설정 파서는 PID 1 한 벌만; 비워둔 자리와 게이트용 실측 사실도 함께
- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위에서 vim modal 방식 선택 모드(v/V로 영역 선택 → 복사)와 Cmd+V 붙여넣기; 스크롤백·색상 렌더링·클립보드가 선행 조건이라 "터미널 완성도" 뒤에 온다
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트 환경변수는 커널이 준 `HOME=/`·`TERM=linux` 둘뿐: `PATH`가 없어 외부 명령은 절대 경로로, `TERM`은 IP-M1이 `terminal` 쪽 `setenv`로 `xterm`으로 고쳤다(시리얼 셸은 `linux` 유지)
- [Power management](docs/decisions/project_power_management.md) — HD-M1이 ACPI를 켜서 `reboot(POWER_OFF)`의 HALT 강등이 사라졌고 QEMU가 스스로 끝난다(전원 차단은 `ACPI_SLEEP`이 아니라 `ACPI_SYSTEM_POWER_STATES_SUPPORT`에 매달려 있어 `SUSPEND`를 끈 채로도 산다); Power Button이 `event0`을 차지해 키보드가 `event1`로 밀렸지만 탐색기가 견뎠고, power 게이트 부팅 1의 통과 조건은 이제 QEMU 프로세스의 소멸이다; PID 1의 시그널은 핸들러가 없으면 관측조차 안 되고, `SA_RESTART`를 켜면 플래그를 세워도 감독 루프가 못 깨어나며(`poll`로 바꾼 뒤에도 그대로다), bash·zsh는 `SIGTERM`을 무시하지만 **fish는 죽는다**(HD-M2 실측 — 그전엔 셋 다 무시한다고 잘못 적혀 있었다); 종료를 시작하는 경로가 셋(SIGTERM·SIGINT·전원 버튼)인데 전부 `power.request()`의 같은 플래그를 지난다; 커널의 `C_A_D` 기본값이 1이라 Ctrl+Alt+Del은 구현 없이도 재부팅을 일으키고, `CAD_OFF` 호출은 호스트 검사가 `reboot(2)`에 닿지 않게 `install()`과 분리한다
- [Device discovery](docs/decisions/project_device_discovery.md) — 입력 장치를 번호가 아니라 성질로 찾는다: sysfs 비트맵은 뒤에서부터 세고(`EV_KEY`는 1번), 판정은 이름이 아니라 `KEY_ESC`~`KEY_D`, 탐색 함수는 뿌리 경로를 인자로 받아 검사가 개발 기계의 `/sys`를 안 읽게 하며, 부팅을 막지 않는 폴백이 게이트에 만드는 사각지대는 `no keyboard found`가 없어야 한다는 둘째 검사로 닫는다; **AT 키보드도 `KEY_POWER`를 갖고 있어서 전원 버튼 판정에 "키보드가 아니다"를 더해야 하고, 안 더해도 종료는 동작하므로 게이트가 `watching` 개수를 세지 않으면 아무도 모른다**
- [Kernel config](docs/decisions/project_kernel_config.md) — `build.sh`가 `olddefconfig`를 돌리므로 적어 둔 설정과 빌드하는 설정이 다를 수 있다: `.config`를 `olddefconfig` 출력으로 되접어 고정점으로 유지하고(주석은 지워지므로 설명은 기억 파일에), 프롬프트가 있는 항목만 끌 수 있으며, 한 항목을 켜면 무관해 보이는 것들이 함께 움직인다; 빌드 시간 증가분은 루트 게이트에서 15배가 된다; **2026-08-22에 `PRINTK_TIME`을 켜서 부팅을 갈랐다 — 커널이 `/init`에 넘기는 시각이 1.12초이고 그중 51%가 initrd 압축 해제이며 부팅 전체가 1.5초 안에 끝나므로, 게이트 36분의 근원은 부팅이 아니라 커널 빌드 18회다**
- [Build host arch](docs/decisions/project_build_host_arch.md) — 빌드 호스트는 arm64, 게스트 산출물은 전부 x86_64 크로스(2026-08-13 ZM-M3): `--platform` 금지, 의존은 `ldd`가 아니라 `readelf`, initrd 유저랜드는 amd64 sysroot에서, 호스트용 도구는 호스트 아키텍처로 다시 빌드