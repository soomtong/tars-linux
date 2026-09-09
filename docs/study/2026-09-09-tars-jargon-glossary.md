---
aliases: [TARS 용어집, jargon glossary]
tags:
  - study
  - glossary
---

# TARS 프로젝트 용어집

> 대상: 대화·문서·커밋 메시지에 자주 나오지만 어디서도 한자리에 정리되지
> 않았던 말들. 원래 `docs/study/note.md`에 흩어져 있던 두 항목(UART 계열,
> KMS)을 여기로 옮기고, 서브프로젝트 약어와 반복해서 쓰는 기술 용어를
> 더했다.
>
> 각 항목의 뜻은 이 저장소가 실제로 그 말을 쓰는 맥락에 맞춰 적었다 —
> 사전적 정의가 아니라 "TARS에서는 이게 왜 이 뜻으로 쓰이는가"다.

---

## 1. 서브프로젝트 약어

TARS는 큰 기능을 한 번에 설계하지 않고, 작은 서브프로젝트로 쪼개 순서대로
끝낸다(왜 그런지는 `CLAUDE.md`의 "왜 이런 규칙이 필요한가" 참고). 각
서브프로젝트는 두세 글자 약어를 갖고, 그 약어 뒤에 `-M0`, `-M1`처럼
milestone 번호를 붙여 부른다.

| 약어 | 풀네임 | 무엇을 했는가 |
|---|---|---|
| BF | Boot Foundation | 커널이 QEMU에서 부팅해 시리얼로 로그를 찍는 것까지 |
| DF | Display Foundation | KMS로 virtio-gpu 프레임버퍼에 단색을 칠하는 것까지 |
| TF | Terminal Foundation | 프레임버퍼 위에 폰트 글리프로 텍스트를 그리는 것까지 |
| ZM | Zig Migration | Rust로 만든 것(kms 등)을 Zig로 다시 짠 재작성 |
| CP | Config Persistence | `/config/tars.conf`에 `key=value` 설정을 남기고 부팅 사이에 읽기 |
| IP | Input Policy | evdev 코드를 셸이 아는 바이트로 번역하는 정책층 |
| PM | Power Management | 시그널·전원 버튼으로 끄고 되살리는 경로 |
| HD | Hardware Discovery | 키보드를 번호가 아니라 capability로 찾고 전원 버튼에 응답 |
| TR | Terminal Rendering | 색·오프셋·스크롤을 `vt.zig`가 정하고 렌더러는 숫자만 받게 분리 |
| CM | Copy Mode | 스크롤백 위에서 vim 모달 선택 모드와 Cmd+V |
| CN | Copy Navigation | copy 커서에 단어 이동(`w`/`b`)을 얹은 것 |
| CS | Copy Search Feedback | 검색 매치 하이라이트·기록·"못 찾음" 메시지 |
| SP | Search Position | 현재 매치를 다른 색으로, `/needle [3/12]` 표시 |
| GL | Gate Latency | 게이트(아래 3절) 실행 시간을 줄이는 작업 |
| RC | Render Cost | 프레임 하나를 그리는 비용을 구간별로 재는 것(코드는 안 고쳤다) |
| CC | Carryover Cleanup | 이월 숙제(안 쓰는 config·도구·파일)를 없앤 정리 |
| HI | Hangul Input | 한글 자판 넷과 영문 자판 둘, 한/영 전환 키 넷 |
| IS | Input Status | 화면 맨 아래 여백에 한/영·자판·대문자 잠금을 보여주는 상태 줄 |
| SH | Search Hangul | copy mode 검색창(`/`)에서 한글을 칠 수 있게 하는 것(진행 중) |

`-M0`, `-M1`, `-M2`처럼 뒤에 붙는 숫자는 그 서브프로젝트 안의 milestone
순번이다. 숫자 자체에 뜻이 있는 게 아니라 이 서브프로젝트를 몇 단계로
쪼갰고 지금 몇 번째인가를 가리킨다. 예를 들어 HI-M3는 Hangul Input의 네
번째 milestone이고, HI가 끝났다는 것은 HI-M0부터 HI-M3까지 계획한
milestone을 전부 마쳤다는 뜻이다.

## 2. 프로젝트 운영 용어

- design doc — 서브프로젝트를 시작하기 전에 왜 필요한지·어떻게 나눌지
  적는 문서. `docs/superpowers/specs/`에 날짜순으로 쌓인다.
- plan — design doc을 milestone 단위로 쪼갠 실행 순서. `docs/
  superpowers/plans/`에 있고, 한 milestone이 끝나야 다음 milestone의 plan을
  새로 쓴다(전체를 미리 다 설계하지 않는다).
- HANDOFF.md — 지금 세션이 끝나는 시점에 어디까지 했고 다음에 뭘 하면
  되는지를 적어 두는 파일. 다음 세션은 여기서부터 이어받는다.
- MEMORY.md / `docs/decisions/` — 세션을 넘어 유지하는 기억의 색인과
  본문. `MEMORY.md`는 한 줄 색인만 갖고, 실제 내용은
  `docs/decisions/<name>.md` 한 파일에 하나씩 있다.

## 3. 게이트(gate)와 체인(chain)

- 게이트(gate) — 루트의 `check.sh`가 서브프로젝트별 `check.sh`를 전부
  모아 돌리는 통합 검증. "게이트를 돌린다"는 이 스크립트 전체를 실행한다는
  뜻이다.
- 체인(chain) — `check.sh`의 `CHAINS` 배열 항목 하나. `"HI-M3:./
  hangul/check.sh"`처럼 이름:실행할 스크립트 경로 쌍이며, 각 체인은
  실제로 커널을 빌드해 QEMU를 부팅한 뒤 결과를 검사한다. 게이트는 이
  체인들을 전부, 각각 3회 연속 성공할 때까지 돌린다(부팅과 게스트 입력의
  flakiness를 잡기 위해서다 — 빌드 재현성 문제는 3회 반복으로 잡히지
  않는다).
- 진입 검사(entry check) — 체인을 실제로 돌리기 전에, 아홉 체인 전부가
  부팅할 것을 실제로 빌드하는지를 먼저 훑는 사전 검증. 하나라도 빠지면
  게이트를 아예 시작하지 않는다.

## 4. 하드웨어·커널 용어

### UART / 8250 / 16550

간단히 답하면: 8250은 리눅스 커널 드라이버 이름(`CONFIG_SERIAL_8250`)이고,
16550은 그 드라이버가 다루는 실제 UART 하드웨어 칩 계열의 이름이다.
둘은 계층이 다를 뿐 같은 것을 가리킨다.

역사적으로:

- 8250 UART: 원조 IBM PC 시절의 UART 칩. FIFO 버퍼가 없어서 인터럽트
  부하가 컸다.
- 16450: 8250을 약간 개선한 버전.
- 16550(A): 8250/16450 계열의 후속으로, 16바이트 송수신 FIFO를 추가해
  인터럽트 오버헤드를 줄였다. 이후 사실상의 표준이 되어, PC 호환 시스템의
  COM 포트는 대부분 16550A 호환 칩으로 구현된다.

Linux 커널은 이 계열 전체(8250, 16450, 16550, 16650, 16750 등)를 하나의
드라이버로 지원하며, 그 소스 파일/설정 옵션 이름이 역사적으로 가장 먼저
나온 "8250"을 따서 `drivers/tty/serial/8250/`, `CONFIG_SERIAL_8250`으로
명명되어 있다.

BF-M1 맥락에서: QEMU가 `-serial stdio`로 노출하는 가상 시리얼 포트(COM1,
I/O 포트 0x3F8)는 16550A 호환 UART로 에뮬레이션된다 — BF-M0의 `kmain.c`가
이미 포트 0x3F8을 직접 두드려 검증한 바로 그 장치다. 커널이 이 포트로 부팅
로그(`console=ttyS0`)를 내보내려면, 그 하드웨어를 다루는 커널 드라이버인
`CONFIG_SERIAL_8250`(+ 콘솔로 등록하는 `CONFIG_SERIAL_8250_CONSOLE`)이
켜져 있어야 한다.

정리하면, "16550"은 우리가 다루는 물리(가상) 칩이고, "SERIAL_8250"은 그
칩을 다루는 커널 쪽 드라이버/설정 이름이다.

### KMS / DRM

KMS는 Kernel Mode Setting의 약자다. 리눅스 커널이 디스플레이 해상도,
색상 깊이, 리프레시 레이트 같은 화면 출력 모드를 부팅 초기부터 커널
레벨에서 직접 설정하는 기능이다. GPU 드라이버가 `/dev/dri/card0` 같은
DRM(Direct Rendering Manager) 디바이스 노드를 통해 이 기능을 노출하며,
사용자 공간 프로그램은 `ioctl` 호출로 이 디바이스와 통신해서 다음 작업을
한다.

- 사용 가능한 커넥터(모니터 등), CRTC, 인코더 같은 디스플레이 리소스 조회
- 해상도/모드 설정
- 프레임버퍼(실제 픽셀이 저장되는 메모리 버퍼) 생성 및 `mmap`
- 그 프레임버퍼를 특정 CRTC에 연결해서 화면에 출력

Display Foundation에서 이 raw DRM ioctl들을 직접 구현해 QEMU의 virtio-gpu
가상 GPU 위에 단색 프레임버퍼를 띄우는 것까지 검증했고(원래 Rust,
ZM에서 Zig로 재작성), Terminal Foundation이 그 프레임버퍼 위에 폰트
글리프로 텍스트를 그리는 것을 맡았다.

### PID 1 / init supervisor

리눅스에서 커널이 부팅 후 가장 먼저 실행하는 프로세스. TARS에서는
`tars-init`이 이 자리를 맡는다. `execve`로 자신을 셸로 덮어쓰지 않고,
`fork`한 자식 둘(terminal, 그 안의 셸)을 `waitpid`로 계속 감독한다 — PID
1은 절대 반환하지 않는(`noreturn`) 감독 루프다. 자식이 죽으면 backoff
규칙(10초 미만 연속 3회 재시작이면 포기)에 따라 되살린다.

### ACPI

Advanced Configuration and Power Interface. 전원 상태(끄기·재부팅·잠자기)와
전원 버튼 같은 이벤트를 운영체제에 알려주는 표준. TARS 커널에 ACPI를 켜기
전에는 `reboot(POWER_OFF)`이 HALT로 강등돼 QEMU가 스스로 끝나지 못했다
(HD-M1에서 해결). ACPI를 켜면 전원 버튼이 evdev의 별도 이벤트 장치로
등록되면서 키보드 장치 번호가 밀리는 부작용도 있어, 장치를 번호가 아니라
capability로 찾는 이유가 된다([[project_device_discovery]] 참고).

### evdev

Linux의 범용 입력 이벤트 인터페이스(`/dev/input/eventN`). 키보드·마우스·
전원 버튼 등 종류가 다른 입력 장치를 같은 이벤트 구조체로 읽을 수 있게
한다. Input Policy는 이 evdev 코드를 셸이 이미 아는 바이트(ASCII, 이스케이프
시퀀스)로 번역하는 계층이다.

### PTY

Pseudo Terminal. 커널이 제공하는 가상 터미널 장치 쌍(master/slave)으로,
바이트 스트림 하나일 뿐 구조체도 메시지 경계도 없다. `terminal`
프로세스가 master 쪽을 쥐고 fish 같은 셸을 slave 쪽에 붙인다. 방향키·F키처럼
문자 하나로 표현 못 하는 키를 이스케이프 시퀀스로 묶어 이 파이프에 흘려
보내는 이유가 여기서 나온다(자세한 내용은 `2026-08-15-keyboard-escape-
sequence-crash-course.md` 참고).

### initrd

initial RAM disk. 커널이 진짜 루트 파일시스템을 마운트하기 전에 메모리에
풀어 쓰는 임시 파일시스템. TARS의 `/init`(PID 1), 셸, terminfo 파일 등은
전부 이 initrd 안에 들어가 부팅 때 함께 올라온다.

### FIFO

Named pipe. 게이트가 QEMU 게스트에 자동으로 명령을 입력할 때, `-serial
stdio`로 노출된 시리얼 콘솔에 문자를 흘려 넣는 통로로 쓴다. 읽기·쓰기
겸용(`exec 4<>"$FIFO"`)으로 열어야 한다 — 쓰기 전용으로 열면 반대쪽 읽는
프로세스가 없어서 그 자리에서 멈춘다.

### TCG

Tiny Code Generator. QEMU가 하드웨어 가상화(KVM 등) 없이 명령어를 소프트웨어로
번역해 실행하는 방식. arm64 호스트 위에서 `qemu-system-x86_64`를 돌릴 때
쓰이며, 같은 동작을 반복 측정해도 첫 번째 값에 번역 비용이 섞여 유독 크게
나온다(같은 검색이 첫 번째 62ms, 세 번째 19ms).

## 5. 한글 입력 용어 (Hangul Input)

- 초성 / 중성 / 종성 — 한글 음절을 이루는 세 자리. 초성(첫 자음),
  중성(모음), 종성(받침, 없을 수 있음). 두벌식은 초성과 종성이 같은 키를
  공유하고(겹침 19개), 신세벌 계열은 중성과 종성이 겹친다(겹침 15개) —
  이 겹침 방향이 자판마다 반대라서 자판이 후보를 주고 조합 상태가
  우선순위로 고른다는 설계가 나왔다.
- 호환 자모(compatibility jamo) — 완성된 음절이 아니라 낱자 하나만
  독립적으로 표현하는 유니코드 코드포인트(예: `ㄳ`, `ㄺ`). 조합 중이거나
  종성만 있는 상태를 화면에 그릴 때 이 코드포인트를 쓴다.
- 첫가끝(초성·중성·종성 자모) — 유니코드가 한글 자모를 초성/중성/종성
  세 영역으로 나눠 정의한 코드 블록. unifont에 이 글리프가 있어도, 호환
  자모와 폭·오프셋이 같아 겹쳐 그리면 글자가 포개져 보인다 — TARS가
  모아쓰기(첫가끝 조합)를 뺀 이유다.
- preedit / 조합 중 — 아직 확정되지 않고 조합기 안에서 자모가 붙었다
  떨어졌다 하는 중간 상태. TARS는 이 상태를 PTY로 셸에 보내지 않고,
  커서 자리에 우리가 직접 반전으로 그린다.
- 자판 이름 — TARS가 지원하는 한글 자판 넷: 두벌식, 공세벌 3-P3, 신세벌
  P2, 신세벌 PCS(기본값). 영문 자판은 쿼티(기본값)와 드보락 둘.
- 한/영 전환 키 — 한글 입력을 켜고 끄는 키 넷: 한/영 키, Shift+Space,
  짧은 CapsLock, 짧은 왼쪽 Ctrl. 긴 CapsLock은 전환이 아니라 대문자
  잠금이다(뗄 때 뒤집는 방식이라 tap과 hold를 구분할 수 있다).

## 6. 빌드·도구 용어

- comptime — Zig에서 컴파일 시점에 평가되는 코드 블록. TARS는 배열
  길이나 이름 표처럼 런타임에만 드러나면 위험한 규약을 comptime으로
  못 박아, 항목을 추가하면 컴파일 에러로 드러나게 만든다(예: `MAX_LEN`이
  자판 이름 표에서 comptime에 계산된다).
- olddefconfig — 커널 `.config`를 현재 소스 트리에 맞춰 최소한으로
  갱신하는 make 타겟. `build.sh`가 저장소의 `.config`를 복사한 뒤 이걸
  돌리므로, 저장소에 커밋된 파일과 실제로 빌드에 쓰이는 설정이 다를 수
  있다 — 그래서 `.config`는 `olddefconfig` 출력으로 되접어 고정점으로
  유지한다.
- BRE — Basic Regular Expression. GNU `grep`이 `-P`(Perl 호환) 없이
  기본으로 쓰는 정규식 문법. `\r`처럼 확장 정규식(ERE)에서 뜻이 있는
  이스케이프도 BRE에서는 리터럴 `r`로 읽히는 등, 몇몇 표기가 조용히
  다르게 동작한다.
- backoff — 실패나 재시작을 곧바로 반복하지 않고 일정 조건을 걸어
  늦추는 규칙. `tars-init`은 자식이 10초 미만 연속 3회 죽으면 재시작을
  포기한다.
