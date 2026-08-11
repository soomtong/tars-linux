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
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — `init`/`kms`의 Rust 코드는 결국 Zig로 재작성 예정; 현재 혼용은 과도기, 동기는 Zig 학습
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 bash/zsh/fish/nushell 중 선택하고 마지막 것을 기억하는 미래 기능; 영속 저장소가 선행 조건(현재 initrd는 tmpfs)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 커널 UAPI 구조체는 `@cImport`로 그대로, ioctl 매크로·가변 인자 함수만 손으로 선언
