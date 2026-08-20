# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 색인이다. 각 항목의 본문은
`docs/decisions/`에 한 파일씩 들어 있다. 새 기억을 추가할 때는
`docs/decisions/<name>.md`를 만들고 여기에 한 줄을 추가한다 — 본문을 이
파일에 쓰지 않는다.

파일 안의 `[[name]]` 링크는 `docs/decisions/` 안의 같은 이름 파일을 가리킨다.

현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 파일 작성·명령 실행은 사용자, 승인된 뒤의 git commit은 Claude
- [Execution scope](docs/decisions/feedback_execution_scope.md) — Claude는 build/QEMU/조사 명령을 직접 실행하지 않고 구현 파일도 쓰지 않는다; 확인은 `find`/`Read`로만
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 단계에서 기술적 선택지를 계속 묻지 말 것; 추천안으로 정해서 진행하되 설명은 그대로 유지

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — TARS 작업의 목적은 속도가 아니라 이해; why 설명을 충실히, pair-programming 방식 유지

## 프로젝트 (project)

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — TARS를 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮기려던 의도와 결말(2026-08-13 완료): `init`은 이식, `kms`는 중복이라 삭제, 툴체인도 제거 — 이제 Rust는 없다
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 bash/zsh/fish/nushell 중 선택하고 마지막 것을 기억하는 미래 기능; 영속 저장소가 선행 조건(현재 initrd는 tmpfs)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰는 컴포넌트는 libc를 링크하지 말고 `std.os.linux`로; libc가 필요할 때만 `@cImport`(구조체는 되고 ioctl 매크로는 안 되며 최적화 모드에서 fortify로 깨진다)
- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식 둘을 감독한다(`waitpid(-1)`로 고아까지 수거, 1초 backoff + 연속 3회면 포기, `noreturn`); 재시작을 관측하려면 `terminal`이 죽어줘야 한다는 결합과 `POLLHUP` 사각지대
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 루트 `check.sh`는 BF+TF 두 체인; 무의미해진 게이트는 주석만 남기지 말고 파일째 은퇴, `clean()`은 vendor 트리를 안 건드림, 게이트는 자기가 안 보는 것을 통과시키므로 재작성 전에 검사부터 추가
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/dev/vda`의 ext2를 `MS_SYNCHRONOUS`로 붙인 `/config/tars.conf` 하나; PID 1이 부팅 시점에 한 번 읽어 argv로 흘려보내고, 깨진 설정으로 부팅이 막히지 않게 하는 장치가 넷, 영속성은 QEMU를 두 번 띄우는 게이트로만 증명된다
- [Input policy](docs/decisions/project_input_policy.md) — 키 입력은 evdev 코드를 셸이 이미 아는 바이트로 번역하는 일: macOS 조합은 `ESC` 접두사·제어 문자로(A안, 이유는 검증 가능성), 키보드 차이는 파이프라인 맨 앞의 코드 교환 한 번으로, 설정 파서는 PID 1 한 벌만; 비워둔 자리와 게이트용 실측 사실도 함께
- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위에서 vim modal 방식 선택 모드(v/V로 영역 선택 → 복사)와 Cmd+V 붙여넣기; 스크롤백·색상 렌더링·클립보드가 선행 조건이라 "터미널 완성도" 뒤에 온다
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트 환경변수는 커널이 준 `HOME=/`·`TERM=linux` 둘뿐: `PATH`가 없어 외부 명령은 절대 경로로, `TERM`은 IP-M1이 `terminal` 쪽 `setenv`로 `xterm`으로 고쳤다(시리얼 셸은 `linux` 유지)
- [Power management](docs/decisions/project_power_management.md) — 커널에 ACPI가 없어 `reboot(POWER_OFF)`이 HALT로 강등되고 QEMU가 스스로 안 끝난다; **ACPI를 켜려면 `terminal`의 `/dev/input/event0` 상수부터 고칠 것**(Power Button이 장치를 하나 더 등록해 TF·IP가 조용히 깨진다); PID 1의 시그널은 핸들러가 없으면 관측조차 안 되고, `SA_RESTART`를 켜면 플래그를 세워도 감독 루프가 못 깨어나며, 대화형 셸이 `SIGTERM`을 무시하므로 `SIGKILL`은 정상 경로다; 커널의 `C_A_D` 기본값이 1이라 Ctrl+Alt+Del은 구현 없이도 재부팅을 일으키고, `CAD_OFF` 호출은 호스트 검사가 `reboot(2)`에 닿지 않게 `install()`과 분리한다
- [Build host arch](docs/decisions/project_build_host_arch.md) — 빌드 호스트는 arm64, 게스트 산출물은 전부 x86_64 크로스(2026-08-13 ZM-M3): `--platform` 금지, 의존은 `ldd`가 아니라 `readelf`, initrd 유저랜드는 amd64 sysroot에서, 호스트용 도구는 호스트 아키텍처로 다시 빌드