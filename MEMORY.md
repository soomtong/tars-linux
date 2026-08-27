# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 **색인**이다. 본문은
`docs/decisions/`에 한 파일씩 들어 있다. 새 기억은
`docs/decisions/<name>.md`를 만들고 여기에 **한 줄만** 추가한다 — 본문을 이
파일에 쓰지 않는다. 줄이 길어지면 그것은 본문이 색인으로 새어 나온 것이다.

파일 안의 `[[name]]` 링크는 `docs/decisions/`의 같은 이름 파일을 가리킨다.

현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 승인된 뒤의 git commit은 Claude가 만든다
- [Execution scope](docs/decisions/feedback_execution_scope.md) — 빌드·QEMU·게이트 명령은 Claude가 직접 실행하고(2026-08-22 변경), 구현 파일 편집만 사용자에게 남긴다
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 중 기술 선택지를 계속 묻지 말고 추천안으로 정해 진행한다
- [Push policy](docs/decisions/feedback_push_policy.md) — push는 묻지 말고 필요할 때 하고, 미푸시 커밋 수를 보고하지 않는다
- [Plain Korean](docs/decisions/feedback_plain_korean.md) — 비유적 표현을 일반 어휘 자리에 쓰지 않는다. 평범한 한국어가 어색하면 영어를 섞어도 된다. 특히 제목과 첫 문장.

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — 목적은 속도가 아니라 이해다

## 프로젝트 (project)

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮긴 의도와 결말(2026-08-13 완료, 이제 Rust는 없다)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰면 libc를 링크하지 않는다; `@cImport`가 되는 것과 안 되는 것
- [Build host arch](docs/decisions/project_build_host_arch.md) — 호스트는 arm64, 게스트 산출물은 x86_64 크로스; `--platform` 금지
- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식 둘을 감독한다; 감독 루프의 순서가 backoff를 만든다
- [Power management](docs/decisions/project_power_management.md) — ACPI·종료 경로 셋·시그널 핸들러가 없으면 관측조차 안 되는 성질
- [Device discovery](docs/decisions/project_device_discovery.md) — 입력 장치를 번호가 아니라 성질로 찾는다; AT 키보드도 `KEY_POWER`를 갖고 있다
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/config/tars.conf` 하나, 파서는 PID 1 한 벌, 영속성은 두 번 부팅으로만 증명된다
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트에 `PATH`가 없다(외부 명령은 절대 경로); `TERM`은 셸마다 다르고 그 terminfo는 initrd에 직접 넣어야 한다
- [Input policy](docs/decisions/project_input_policy.md) — evdev 코드를 셸이 아는 바이트로 번역하는 세 단계; 키보드 차이는 맨 앞에서 한 번만 보정하고, 반환은 "바이트열 또는 동작"이라 스크롤 키가 PTY로 안 샌다
- [Terminal rendering](docs/decisions/project_terminal_rendering.md) — 색·오프셋·스크롤은 `vt.zig`에서 확정하고 렌더러는 숫자만 받는다; 스크롤백 한도는 값 둘을 함께 줘야 걸린다, 라이브러리에 대해 짐작하면 틀리는 것 셋, NUL이 `grep`을 막는 성질, 죽은 검사가 남기는 구멍
- [Font selection](docs/decisions/project_font_selection.md) — 후보를 가르는 것은 커버리지가 아니라 16px 중간값 비율이다; 현재 폰트(unifont 17.0.03)의 실측값과 다시 바꿀 때 고칠 자리 열
- [Kernel config](docs/decisions/project_kernel_config.md) — `olddefconfig`가 적어 둔 설정과 빌드하는 설정을 가른다; 게이트 시간의 근원은 부팅이 아니라 커널 빌드다
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 체인을 더하고 빼는 규칙; 게이트는 자기가 안 보는 것을 통과시킨다
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 고르고 기억하는 미래 기능(영속 저장소가 선행 조건)
- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위의 vim modal 선택 모드와 Cmd+V; CM-M2(2026-08-26)로 서브프로젝트가 끝났다. Cmd+V가 키 표 **두 곳**에 있어야 한다는 것, 가지치기가 pin을 무효로 만들지 않는다는 것, bracketed paste를 안 쓴다는 것이 여기 있다
- [Copy navigation](docs/decisions/project_copy_navigation.md) — copy 커서에 얹는 이동 수단 둘; CN-M0(2026-08-27)이 단어 이동 `w`/`b`를 끝냈고 CN-M1의 검색이 남았다. 라이브러리의 "단어"에 **공백 덩어리가 포함된다**는 것, `pointFromPin`이 뷰포트 **아래쪽 밖을 안 알려준다**는 것, `Terminal.ScrollViewport`에 `.pin`이 없다는 것이 여기 있다
- [Gate latency](docs/decisions/project_gate_latency.md) — 게이트 54분 15초 → 18분 08초(GL-M0·M1, 2026-08-26); 54분의 8할은 같은 산출물을 24번 빌드하는 비용이었다, "빌드가 최신인가"를 mtime으로 판정하려는 시도는 **두 번 다 실패했고** 내용 해시로 가야 한다, gzip -9는 값을 못 한다
