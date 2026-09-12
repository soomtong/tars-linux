# TARS 작업 규칙

이 파일은 이 저장소(`tars-linux`)에서만 적용되는 협업 규칙입니다. 전역
규칙(`~/.claude/CLAUDE.md`: 응답 언어, 커밋 스타일, 도구 환경, Handoff/
Memory 저장 위치)은 항상 함께 적용됩니다.

## 왜 이런 규칙이 필요한가

TARS는 이전 저장소(`tars.git`)에서 "이해 없이 코드만 쌓이는" 문제로 막혀서
완전히 새로 시작한 프로젝트입니다. 이번 재시작의 핵심 목표는 속도가
아니라 이해입니다. 커널이 어디까지 책임지고 어디서부터 우리 코드인지,
왜 이 명령이 이렇게 동작하는지를 매 단계 몸으로 확인하면서 진행합니다.
아래 규칙은 이 목표를 지키기 위한 것이며, 임의로 생략하지 않습니다.

## 진행 방식 (설명 → 실행 → 설명)

매 작업 단계는 다음 순서를 따릅니다.

1. 설명 먼저 — 지금 무엇을 만들고 왜 필요한지 사용자가 이해할 수 있게
   먼저 설명한다. 코드를 던지기 전에 "이게 왜 이렇게 생겼는지"를 말한다.
2. 파일 편집은 사용자가 — 구현 파일은 Claude가 "넣을 것"을 제시하고
   사용자가 직접 넣는다. 이것은 노동 분담이 아니라 검토 지점이다 —
   코드가 저장소에 들어가기 전에 사람이 한 번 읽는 자리다. 지울 것이 있는
   편집은 `지울 것`과 `넣을 것`을 따로 표시하고, 100줄이 넘으면 Claude가
   `/tmp`에 원본을 만들어 사용자가 `cp`로 넣는다.
3. 명령 실행은 Claude가 (2026-08-22 변경) — 빌드·QEMU 부팅·게이트·조사성
   명령은 Claude Code가 직접 실행한다. 그 전까지는 사용자가 직접 쳤는데,
   같은 `docker run` 한 줄을 옮겨 치는 데서 오는 이해가 없다는 판단으로
   바꿨다. 이해는 설명을 읽고 결과 해석을 따라가는 데서 온다
   (`docs/decisions/feedback_execution_scope.md`). 긴 명령(루트 게이트 등)은
   실행 전에 얼마나 걸리는지 알린다.
4. 결과를 상세히 설명 — 실행 결과(로그, 에러, 경고)가 왜 그렇게
   나왔는지 줄 단위로 설명한다. 로그를 붙이고 끝내지 않는다. 특히 "실패가
   정상인 단계"(예: BF-M1의 init 없는 kernel panic)는 왜 실패가 의도된
   결과인지 명확히 짚는다.

## Commit은 Claude Code가 수행

사용자가 결과를 승인한 뒤의 git commit은 Claude Code가 대신 만든다
(2026-08-02 합의). 사용자에게 `git add`/`git commit`을 실행하라고 안내하지
않는다.

## 진행 전 검증은 Claude Code 책임

사용자가 "done"이라고 답해도, 다음 단계로 넘어가기 전에 반드시
`find`/`Read`로 실제 파일이 만들어졌는지, 내용이 맞는지 확인한다. BF-M0
진행 중 `check.sh`만 만들어지고 `Makefile`은 안 만들어졌는데도 "done"이라고
답한 적이 있었다 — 이후 매번 파일 존재를 먼저 확인하고 나서 다음 명령을
안내한다.

## Commit 전 git status 확인

`git add`로 디렉터리를 통째로 추가하기 전에 무엇이 포함되는지 확인한다.
BF-M0에서 `git add devcontainer/sanity/`로 빌드 산출물(`*.o`,
`sanity.elf`)까지 실수로 커밋된 적이 있다 — 이후 `.gitignore`로 빌드
산출물을 미리 배제하고, add 대상을 항상 좁혀서 지정한다. 이 저장소는
kernel/init/bootloader를 직접 빌드하므로 바이너리 산출물이 계속
생성된다 — 소스와 산출물을 구분하는 습관이 특히 중요하다.

## Milestone 단위 작업

각 서브프로젝트는 `docs/superpowers/specs/`에 design doc, `docs/
superpowers/plans/`에 milestone별 plan을 작성한다 (예:
`2026-08-01-tars-boot-foundation-design.md`,
`2026-08-01-tars-boot-foundation-bf-m0.md`). 한 milestone이 끝나면 다음
milestone의 plan은 그 시점에 새로 작성한다 — 전체 milestone을 한 번에
미리 상세 설계하지 않는다 (이해가 쌓이면서 다음 단계의 구체적 결정이
바뀔 수 있기 때문).

## 참고

- 최종 비전 전체 배경(왜 여러 서브프로젝트로 나뉘는지, 후보 목록):
  `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`의
  "배경" 절
- 현재 진행 상황: `HANDOFF.md`
- 세션을 넘어 유지되는 기억: `MEMORY.md`(색인) + `docs/decisions/`(본문
  한 파일당 하나). 2026-08-11에 `~/.claude/projects/.../memory/`에서 이리로
  옮겼다 — 저장소 밖이 아니라 저장소 안에 두어 히스토리에 남기기 위함이다.
  새 기억은 `docs/decisions/<name>.md`를 만들고 `MEMORY.md`에 한 줄 추가.
- 서브프로젝트를 끝내면 그 design doc의 `Status:` 줄을 함께 고친다.
  2026-08-31에 낡은 것 넷을 한꺼번에 고쳤는데, 넷 다 "중간에 멈춘 것"이 아니라
  계획한 milestone을 전부 끝내 놓고 표시만 안 한 것이었다.
- 서브프로젝트의 실제 상태는 `check.sh`의 `CHAINS` 배열이 가장 정확하다 —
  게이트가 매번 돌리는 목록이라 낡을 수가 없다.

### 완료된 서브프로젝트

design doc은 전부 `docs/superpowers/specs/`에 날짜순으로, 기억은
`docs/decisions/`에 있다. "무엇을 배웠나"는 그 두 곳에 있고 이 표에는 없다.

| 서브프로젝트 | 끝난 날 | 무엇이 섰나 |
|---|---|---|
| Boot Foundation (BF-M0~M4) | 2026-08-07 | 커널을 직접 빌드해 QEMU에서 띄우고 PID 1이 자식을 감독한다 |
| Display Foundation (DF-M0~M3) | 2026-08-08 | 프레임버퍼에 픽셀을 직접 찍는다 |
| Terminal Foundation (TF-M0~M4) | 2026-08-13 | PTY 위의 터미널이 글자를 그린다 |
| Zig Migration (ZM-M1~M3) | 2026-08-13 | Rust를 Zig로 옮겼다. 이제 Rust는 없다 |
| Config Persistence (CP-M0~M2) | 2026-08-15 | ext2 디스크의 `key=value` 설정을 부팅 사이에 읽는다 |
| Input Policy (IP-M0~M2) | 2026-08-19 | evdev 코드를 셸이 아는 바이트로 번역한다 |
| Power Management (PM-M0·M1) | 2026-08-20 | 시그널로 끄고 되살린다 |
| Hardware Discovery (HD-M0~M2) | 2026-08-22 | 키보드를 capability로 찾고 전원 버튼에 응답한다 |
| Terminal Rendering (TR-M0~M2) | 2026-08-24 | 색·스크롤·오프셋을 `vt.zig`가 확정한다 |
| Copy Mode (CM-M0~M2) | 2026-08-26 | 스크롤백 위의 vim modal 선택과 `Cmd+V` |
| Copy Navigation (CN-M0·M1) | 2026-08-27 | 단어 이동 `w`/`b`와 스크롤백 검색 `/`·`n`·`N` |
| Copy Search Feedback (CS-M0·M1) | 2026-08-28 | 매치 하이라이트 · 검색 기록 · "못 찾음" 메시지 |
| Gate Latency (GL-M0~M3) | 2026-08-29 | 루트 게이트 54분 15초 → 16분 01~11초 |
| Search Position (SP-M0·M1) | 2026-08-30 | 현재 매치를 밝은 앰버로, 오버레이에 `/needle [3/12]` |
| Render Cost (RC-M0) | 2026-08-30 | 한 프레임의 84.7%가 `fill`이라는 것을 재기만 했다(코드는 안 고쳤다) |
| Carryover Cleanup (CC-M0) | 2026-08-31 | 이월 숙제 셋을 없앴다(커널 config 둘 · sanity 도구 둘과 98MB 산출물 · 옛 폰트) |
| Hangul Input (HI-M0~M3) | 2026-09-01 | 한글 자판 넷과 영문 자판 둘, 한/영 전환 키 넷을 `tars.conf`가 고른다 |
| Input Status (IS-M0·M1) | 2026-09-09 | 화면 맨 아래 여백의 상태 줄 — 한/영 · 자판 · 대문자 잠금 |
| Search Hangul (SH-M0~M2) | 2026-09-09 | copy mode 검색창에서 한글을 친다 |
| Find Paste (FP-M0·M1) | 2026-09-09 | copy mode에서 잡은 글자를 `/` 프롬프트에 `Cmd+V`로 붙인다 |
| Real Machine (RM-M0~M3) | 2026-09-10 | 일반 x86_64 노트북에서 뜬다 — UEFI · simpledrm · USB 키보드 · NVMe. 설정 디스크는 ext2 라벨 `tars-`로 찾는다. 열번째 체인 `machine/check.sh` |
| Userland Tools (UT-M0~M3) | 2026-09-11 | 게스트에 도구 65개가 서고 `PATH`로 이름이 손에 닿는다. 목록은 `kernel/guest_tools.sh` 한 파일. 열한번째 체인 `tools/check.sh` |
| Shell Config (SC-M0~M2) | 2026-09-11 | `tars.conf`의 `shell_config`가 rc를 켜고 끄고, 탈출로 둘(rc 없이 한 번 더 · 커널 cmdline `tars.noconfig`)이 섰다 |
| Shell Memory (SM-M0~M2) | 2026-09-12 | `zoxide`·`fzf`와 히스토리 env로 기계가 배운 것 둘이 부팅을 넘는다 |
| Gate Accuracy (GA-M0·M1) | 2026-09-12 | 게이트가 거짓을 말하던 일곱 자리를 없애고 `check.sh`의 진입 검사가 재발을 막는다 |

위 표의 서브프로젝트 여럿은 "파일 편집은 사용자가"의 예외였다. HI는
사용자가 "macOS용 한글 입력기를 직접 만들어 본 영역이라 코드를 읽는 자리의 값이
낮다"고 정해서, CC-M0은 "배우는 것이 적으니 전부 네가 써라"로, SH·FP·RM·UT·SC·SM은
사용자가 외출하며 "이번 세션의 구현 결정을 전부 위임한다"고 정해서 Claude Code가
편집까지 했다. 그 위임은 전부 세션(또는 milestone) 단위였고 끝나면 위의 기본
규칙으로 돌아온다 — 새 세션의 기본값은 언제나 "파일 편집은 사용자가"다.
