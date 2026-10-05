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
2. 파일 편집은 Claude가 — 구현 파일도 Claude Code가 직접 넣고, 사용자는
   만들어진 코드를 읽으며 따라간다(`docs/decisions/feedback_execution_scope.md`).
   검토 지점은 타이핑이 아니라 읽기에 있다 — 그래서 Claude는 매 편집 뒤
   `git diff --stat`으로 더한 줄과 지운 줄을 따로 세고, 지우는 편집은
   `git diff | rg '^-'`로 내용을 직접 읽어 의도한 줄만 지워졌는지 본다.
   그리고 큰 편집은 무엇이 어떤 모양으로 들어가는지 먼저 설명한다.
3. 명령 실행은 Claude가 — 빌드·QEMU 부팅·게이트·조사성 명령은 Claude Code가
   직접 실행한다. 같은 명령을 옮겨 치는 데서 오는 이해는 없고, 이해는 설명을
   읽고 결과 해석을 따라가는 데서 온다
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

다음 단계로 넘어가기 전에 `Read`로 실제 파일이 만들어졌는지, 내용이 맞는지
확인한다 — 내가 편집했든, subagent가 했든, 사용자가 "done"이라고 했든 같다.
"만들었다"는 보고와 실제 파일이 어긋난 적이 있기 때문이다(BF-M0에서
`check.sh`만 있고 `Makefile`은 없었다).

## Commit 전 git status 확인

`git add`로 디렉터리를 통째로 추가하기 전에 무엇이 포함되는지 확인한다.
BF-M0에서 `git add devcontainer/sanity/`로 빌드 산출물(`*.o`,
`sanity.elf`)까지 실수로 커밋된 적이 있다 — 이후 `.gitignore`로 빌드
산출물을 미리 배제하고, add 대상을 항상 좁혀서 지정한다. 이 저장소는
kernel/init/bootloader를 직접 빌드하므로 바이너리 산출물이 계속
생성된다 — 소스와 산출물을 구분하는 습관이 특히 중요하다.

## Milestone 단위 작업

각 서브프로젝트는 `docs/specs/`에 design doc, `docs/plans/`에
milestone별 plan을 작성한다 (예:
`2026-08-01-tars-boot-foundation-design.md`,
`2026-08-01-tars-boot-foundation-bf-m0.md`). 한 milestone이 끝나면 다음
milestone의 plan은 그 시점에 새로 작성한다 — 전체 milestone을 한 번에
미리 상세 설계하지 않는다 (이해가 쌓이면서 다음 단계의 구체적 결정이
바뀔 수 있기 때문).

## 참고

- 최종 비전 전체 배경(왜 여러 서브프로젝트로 나뉘는지, 후보 목록):
  `docs/specs/2026-08-01-tars-boot-foundation-design.md`의
  "배경" 절
- 현재 진행 상황: `HANDOFF.md`
- 서브프로젝트를 넘어 유효한 작업 요령(게이트 운영 · 다시 조사하지 말 실측 ·
  안 되는 접근 · 핵심 파일 지도): `docs/guides/lessons.md`
- 세션을 넘어 유지되는 기억: `MEMORY.md`(색인) + `docs/decisions/`(본문
  한 파일당 하나). 2026-08-11에 `~/.claude/projects/.../memory/`에서 이리로
  옮겼다 — 저장소 밖이 아니라 저장소 안에 두어 히스토리에 남기기 위함이다.
  새 기억은 `docs/decisions/<name>.md`를 만들고 `MEMORY.md`에 한 줄 추가.
- 서브프로젝트를 끝내면 그 design doc의 `Status:` 줄을 함께 고친다.
  milestone을 다 끝내 놓고 표시만 빠뜨리기 쉽다.
- 서브프로젝트의 실제 상태는 `check.sh`의 `CHAINS` 배열이 가장 정확하다 —
  게이트가 매번 돌리는 목록이라 낡을 수가 없다.

### 완료된 서브프로젝트

design doc은 전부 `docs/specs/`에 날짜순으로, 기억은
`docs/decisions/`에 있다. "무엇을 배웠나"는 그 두 곳에 있고 이 표에는 없다.
각 행은 끝난 날의 상태다. 숫자(게이트 시간 · 검사 수 등)는 뒤 서브프로젝트가
바꿨을 수 있으니, 지금 값은 `check.sh`의 `CHAINS`와 최신 design doc의 `Status:`에서 본다.

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
| Shell History Durability (SD-M0~M2) | 2026-09-12 | 콘솔 셸에 친 명령이 전원 버튼과 함께 사라지지 않는다 — seed rc의 `setopt INC_APPEND_HISTORY` 한 줄 |
| Bash History Durability (BH-M0~M2) | 2026-09-12 | 같은 일을 bash에 했다 — `PROMPT_COMMAND='history -a'` 한 줄이 zoxide 훅보다 먼저. 덤으로 게스트에 없던 `/dev/fd`를 세웠다 |
| Bash Boot (BB-M0~M2) | 2026-09-12 | `config` 체인이 부팅 아홉이 됐고 아홉째가 `shell=bash`로 뜬다 — 중첩으로는 볼 수 없던 여섯을 본다 |
| Shutdown Latency (SL-M0~M2) | 2026-09-13 | PID 1이 SIGTERM 뒤에 SIGHUP도 보낸다. 콘솔 셸이 유예를 꽉 쓰던 2.9초가 0.13초가 됐다 |
| Guest Network (NW-M0~M3) | 2026-09-14 | `tars.conf`의 `net=dhcp`가 게스트에 주소를 붙인다. 우리 코드는 링크를 올리고 dhcpcd를 띄우는 것까지고 나머지는 dhcpcd다. 판정은 SLIRP 안에서 닫힌다 — 열두번째 체인 `net/check.sh` |
| Inbound Network (IN-M0~M2) | 2026-09-14 | 게스트가 연 포트에 바깥에서 붙어 바이트를 읽는다. 우리 코드는 0줄이고 `net/check.sh`가 검사 열여섯이 됐다 |
| Time Sync (TS-M0~M3) | 2026-09-19 | 부팅에 SNTP로 한 번 묻고 시계를 뛰었다(우리 SNTP는 TD가 chronyd로 바꿨다). 상대는 설정의 주소든 DHCP가 알려 준 것이든 되고, `timezone=Asia/Seoul`이 그 시각을 사람이 읽는 모양으로 만든다. 네트워크가 없어도 부팅은 평소대로 끝난다 — `net/check.sh`가 검사 스물넷에 부팅 셋 |
| Shell Tools (ST-M0~M2)|2026-09-19|깔려 있던 도구를 셸이 쓴다 — seed rc가 eza 별칭 넷을 정의하고(`ls`가 eza로 가는 것이 유일한 셰도다), `/config/gitconfig`가 생겨 `/.gitconfig` 링크가 더 이상 끊기지 않는다|
| Terminal Queries (TQ-M1)|2026-09-19|터미널이 자식의 질의(커서 위치·상태 보고)에 답한다 — `effects.write_pty` 한 칸과 그 답이 pty로 돌아가는 길. ST-M3이 넣은 `--no-height` 우회를 지웠다|
| Disk Install (DI-M0~M2) | 2026-09-23 | USB로 뜬 기계에서 `tars-install`이 내장 디스크에 ESP와 설정 파티션을 만들고 USB 없이 뜬다. 새 ISO로 갱신해도 설정이 남고 `--wipe`가 통째로 지운다. 열세번째 체인 `install/check.sh` |
| Disk Install Carryover (DC-M0~M2) | 2026-09-26 | 설치된 부팅이 늦게 생기는 설정 파티션을 5초까지 기다린다. DI의 작은 것 다섯(4Kn GPT · 옛 ISO 서명 · 넘치는 줄 · 쪼개진 YES · PVD 음성)을 치웠다. install 체인이 부팅 일곱이 됐다 |
| Time Discipline (TD-M0~M2) | 2026-09-26 | 시계를 chronyd가 만진다 — 우리 SNTP를 지우고 `init`은 fork · 설정 · execve 배관만 한다. `/config`가 붙으면 배운 drift가 `/config/chrony.drift`로 부팅을 넘고, 사람은 `/config/chrony.d/`에 서버를 적는다. `net/check.sh`가 부팅 다섯 |
| Wired NIC (WN-M0~M3) | 2026-09-26 | 노트북형 유선 드라이버 여섯과 USB 동글 셋이 켜졌다. 모든 QEMU 호출이 `-nic none`/`-netdev`를 명시하고 진입 검사가 지킨다. `init`은 dhcpcd를 띄우기만 하고 인터페이스는 dhcpcd가 고른다 — 부팅 뒤 꽂은 USB 동글도 잡는다. 열네번째 체인 `nic/check.sh` |
| Loopback (LB-M0~M3) | 2026-09-26 | `init`이 설정을 읽기 전에 `lo`를 올리고, `localhost`와 `아무거나.localhost`가 `net`과 무관하게 `127.0.0.1`로 풀린다 — `/etc/hosts` · `nsswitch.conf` · `libnss_myhostname`. 새 체인 없이 `tools` · `net` 체인이 이름 셋으로 게스트 안 TCP 왕복을 본다 |
| Firewall (FW-M0~M2) | 2026-09-27 | `tars.conf`의 `firewall=on`이 들어오는 것을 기본으로 버리고, 사람은 `/config/nftables.d/*.nft`에 연다. `init`은 `net.bringUp` 앞에서 `nft -f`를 기다리고, 사람의 파일이 틀리면 기본 규칙만 올린다. 열다섯번째 체인 `firewall/check.sh` |
| Boot Services (SV-M0~M2) | 2026-09-27 | `/config/services.d`에 둔 실행 파일을 `init`이 이름순으로 여덟까지 띄우고 감독한다. 첫 세입자 sshd는 템플릿 링크 하나와 공개 키 하나로 켜지고, ssh 세션은 콘솔과 같은 셸 · env다 — `init`이 부팅 때 `passwd`의 셸 자리와 sshd의 `SetEnv`를 쓴다. 열여섯번째 체인 `service/check.sh` |
| Service Control (CT-M0~M2) | 2026-09-27 | `tars-service`의 동사 넷(status · stop · start · restart)이 `/run/tars/init.sock`으로 PID 1에게 말한다. 시그널은 서비스의 프로세스 그룹에 가고, 사람이 요청한 죽음은 빨리 죽음으로 세지 않는다. SIGTERM을 무시하면 3초 뒤 SIGKILL. 새 체인 없이 `service/check.sh`가 부팅 넷이 됐다 |
| Daemon Supervision (DS-M0~M2) | 2026-09-27 | dhcpcd와 chronyd가 감독 목록에 들어갔다 — 죽으면 다시 뜨고 `tars-service`로 다룬다. dhcpcd는 `-B`, chronyd 앞의 30초 기다림은 chrony `sourcedir`로 바뀌었다. 덤으로 버튼 fd에 `CLOEXEC`. 새 체인 없이 net · service 체인이 본다 |
| Wireless (WL-M0~M3) | 2026-09-28 | 노트북 내장 무선(Intel · Realtek · MediaTek · Qualcomm)이 붙는다. `/config/wpa_supplicant.conf`가 있으면 `init`이 `tars-wifi`(→ exec wpa_supplicant)를 감독하고, 늦게 생긴 인터페이스는 dhcpcd hook이 넘긴다. firmware 74개가 initrd 꼬리에 붙는다. 게이트는 mac80211_hwsim — 열일곱번째 체인 `wifi/check.sh` |
| USB Wireless (UW-M0~M2) | 2026-09-28 | 같은 칩 계열의 USB 동글 열하나(rtw88 일곱 · rtw89 둘 · MT7921U · MT7925U)가 켜졌다. 우리 코드는 0줄, firmware는 77개. QEMU에 USB 무선이 없어서 `wifi/check.sh`가 심볼 · modinfo alias · 부팅 로그의 usbcore 등록 줄을 본다 |
| Terminal Graphics (TG-M0~M3) | 2026-10-03 | 자식이 kitty graphics로 보낸 이미지를 우리 렌더러가 그린다 — 해석과 저장은 ghostty vt, 우리 몫은 셀 픽셀 크기 · 픽셀 사각형(`vt.zig`) · 그리기(`image.zig`) · PNG(`stb_image`). 새 체인 없이 `render` 체인이 사분면 픽셀로 본다 |
| Copy Indicator (CI-M0) | 2026-10-03 | copy mode에 있는 동안 상태 줄 꼬리에 `COPY`가 뜬다. 앞 넷은 안 움직이고 색은 전용이다. 새 체인 없이 `copy` 체인이 글자와 픽셀을 짝으로 본다 |
| Workspace Panes (WP-M0~M2) | 2026-10-04 | 화면 하나가 셸 여럿을 담는다 — 워크스페이스(탭) 아홉 × 패널 여덟, 키는 iTerm2 그대로(`Cmd+D` · `Cmd+Shift+D` · `Cmd+W` · `Cmd+[` · `Cmd+]` · `Cmd+T` · `Cmd+1~9`). 패널은 PTY · `vt.Screen` · 사각형이고 레이아웃은 순수 `layout.zig`. 설계는 Fable, 구현은 Opus 서브에이전트. 열여덟번째 체인 `pane/check.sh` |
| Cursor Shape (CU-M0·M1) | 2026-10-04 | vim의 insert는 bar, replace는 underline, normal은 block이다 — 렌더러가 DECSCUSR 모양 셋을 그리고, 게스트 vi를 `vim.basic`으로 바꿔 시스템 vimrc 세 줄을 initrd에 넣었다. 새 체인 없이 `render` 체인이 본다 |
| Guest Ergonomics (GE-M0·M1) | 2026-10-04 | 게스트에 `which`가 섰다(debianutils의 `#!/bin/sh` 스크립트 — 목록의 첫 비ELF, `copy_lib_deps`가 ELF magic으로 건너뛴다). 시스템 vimrc가 커서 세 줄에서 plugin · 런타임 없는 모던 설정 한 벌이 됐다 — 첫 줄 `set nocompatible`, 줄 번호 · 상태 줄 · 빠른 Esc. 설계 · plan은 Opus, 구현은 M0 Sonnet · M1 Opus 서브에이전트. 새 체인 없이 `tools` · `render` 체인이 본다 |
| Paste Ergonomics (PE-M0~M2) | 2026-10-04 | 자식이 모드 2004를 켰으면 `Cmd+V`를 `ESC[200~` · `ESC[201~`로 감싼다 — CM 결정 9를 실측으로 다시 열었다. 셸에서 여러 줄을 붙여도 Enter 전에는 안 돌고 vim의 `autoindent` 계단이 없다. `/.vimrc`가 `/config/vimrc`로 가는 링크이고 `init`이 주석뿐인 seed를 깐다(gitconfig와 같은 모양). 덤으로 `service` 체인이 dhcpcd의 `adding default route` 줄까지 기다린다(`leased`는 주소가 붙기 전에 찍힌다). 설계 · plan은 Opus, 구현은 M0 · M2 Sonnet · M1 Opus 서브에이전트. 새 체인 없이 `copy` 검사 21 · 22와 `config` 1 · 2차가 본다 |
| Pointer Devices (PD-M0~M4) | 2026-10-05 | 마우스와 터치패드가 화살표 하나를 움직인다. terminal이 uevent로 장치를 찾고(핫플러그), 화살표는 save-under, 누르고 끌어 뗀 글자가 클립보드에(copy mode의 기계 그대로), 휠은 포인터 아래 패널. 터치패드는 `touchpad.zig`가 MT 프로토콜 B를 번역하고 커널 심볼 41개(PS/2 · SMBus · I2C-HID · THC)가 켜졌다. M4가 마우스 보고를 더했다 — 자식이 마우스 모드를 켰으면 ghostty `encodeMouse`로 PTY에 보내고 우리 선택은 Shift 끌기, 게스트 vimrc는 `mouse=a`. 게이트는 uinput 가짜 패드와 bash `read -N` 프로브 — 열아홉번째 체인 `pointer/check.sh`. 설계 · plan 다섯은 Opus, 구현은 M1 Sonnet · 나머지 Opus 서브에이전트. 루트 게이트는 M2부터 2회 |
| Escape Latin (EL-M0) | 2026-10-05 | 한글을 치다가 수정키 없는 Esc를 누르면 조합을 확정하고 영문으로 돌아온다 — vim의 insert에서 나오면 다음 키가 명령이다. Esc는 그대로 프로그램에 간다. `tars.conf`의 `esc_latin=on\|off`(기본 on)는 `hangul_toggle` 목록이 아니라 따로 있는 키라 옛 설정 파일에서도 켜진다(seed가 목록 넷을 글자 그대로 적어 두기 때문). argv는 그 목록 끝에 이름을 붙여 간다. 다시 그리기는 `readKeys`가 `hangul_on`의 앞뒤를 비교한다. 설계 · plan은 Opus, 구현은 Sonnet 서브에이전트. 새 체인 없이 `hangul` 검사 21~24가 vim으로 본다 |
