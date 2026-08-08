# TARS Terminal Foundation — Design

**Date:** 2026-08-08
**Status:** Design approved, awaiting TF-M0 plan

## 배경

Display Foundation(DF-M0~M3, `2026-08-07-tars-display-foundation-design.md`,
2026-08-08 완료)이 QEMU 가상 GPU에 KMS/DRM으로 픽셀을 띄우는 것까지
끝냈다. 최종 비전 후보(compositor/KMS, PTY/terminal, input policy, IME,
패키지 관리자, AI 도구 통합) 중 다음 서브프로젝트를 고르면서, 처음에는
"Compositor"가 자연스러운 다음 계층으로 보였다.

그런데 실제 요구사항을 짚어보니 범위가 달랐다. TARS에서 화면에 그림을
그릴 프로세스는 **터미널 앱 하나뿐**이다 — homebrew 스타일 패키지
관리자로 설치하는 TUI 앱(vim, htop 등)은 PTY를 통해 텍스트(ANSI
이스케이프)만 주고받고, 여러 탭(cmd+1~9 전환)도 터미널 프로세스 내부
상태일 뿐이며, 터미널 대신 다른 독립 애플리케이션을 구동할 계획이
없다. `/dev/dri/card0`는 한 번에 한 프로세스만 독점할 수 있는데, 그
독점자가 앞으로도 하나뿐이라면 여러 독립 프로세스의 화면 점유를
중재하는 Wayland 스타일 compositor 프로토콜은 애초에 필요 없다.

그래서 이 서브프로젝트는 **Terminal Foundation**으로 이름 붙인다 —
Display Foundation이 이름을 "Compositor"에서 좁혔던 것과 같은 이유다.
다루는 것은 최종 비전의 "ghostty 기반 내장 terminal" 항목이며, 실제
compositor(여러 독립 클라이언트 간 화면 중재)는 애초에 이 프로젝트
범위에 들어오지 않는다.

## 목표 (MVP)

QEMU에서 Terminal Foundation 앱이 KMS/DRM 프레임버퍼에 폰트로 shell
prompt 텍스트를 렌더링하고, 키보드 입력을 PTY로 전달하는 경로까지
갖춘 상태를 **screendump 자동 검증**으로 확인한다. Display
Foundation이 "단색 픽셀"까지였다면, Terminal Foundation은 "읽을 수
있는 텍스트"가 결과물이라는 점이 핵심 차이다.

## 비목표

- 마우스 입력, 탭 전환(cmd+1~9), 여러 TUI 앱 동시 실행 — 이번
  서브프로젝트가 다루는 기능이지만 MVP의 자동 검증 게이트에는 넣지
  않는다(수동 확인만). MVP 이후 milestone에서 다룬다.
- 시스템 수준 compositor(여러 독립 프로세스 간 화면 중재), Wayland/X11
  프로토콜 — 위 배경에서 설명한 대로 애초에 불필요하다고 판단해 범위
  자체에서 제외한다.
- 터미널 안에서 웹 페이지 렌더링 — 최종 비전에 있는 먼 미래 항목,
  이번 서브프로젝트 범위 밖.
- CJK 입력기(IME) 자체 — 폰트가 한글 조합형 글리프를 지원할 뿐,
  실제 조합 입력 로직(자모 조합 상태 머신, 입력 전환 등)은 별도 후속
  서브프로젝트.
- GPU 가속 텍스트 렌더링 — glyph cache에서 프레임버퍼로 CPU blit만
  다룬다.

## 핵심 설계 결정

### 1. 아키텍처: 단일 프로세스가 디스플레이 독점

Terminal Foundation 앱 하나가 `/dev/dri/card0`를 열고 부팅부터
종료까지 독점한다. 여러 탭이나 PTY 세션은 이 프로세스 내부의 상태
(예: 탭 배열 중 현재 활성 인덱스)로 관리하며, 별도 compositor
프로세스나 클라이언트-서버 프로토콜은 두지 않는다. tmux가 터미널
하나 안에서 pane을 나누는 것과 같은 모델이다.

### 2. 터미널 코어: `libghostty-vt`

ANSI/VT 이스케이프 파싱과 터미널 상태 관리는 Ghostty 프로젝트의
`libghostty-vt`(Zig/C, zero-dependency)를 쓴다. 조사 결과(2026-08-08
기준), Ghostty의 전체 embedding API(`libghostty`, 폰트 렌더링·GPU
렌더링까지 포함)는 아직 general-purpose embedding용으로 안정화되지
않았다고 공식 문서가 명시한다. 반면 `libghostty-vt`는 Ghostty GUI
안에서 수년간 검증된 core logic을 떼어낸 하위 컴포넌트로, 기능 자체는
"extremely stable"이고 IDE/CI 도구가 자체 ANSI 파서 대신 embed하도록
공식 권장되는 상태다(API 함수 시그니처는 아직 유동적이라 버전을 고정
해두고 필요시 업데이트한다).

즉 "ghostty 기반"이라는 최종 비전을 만족시키면서, TARS가 어차피 직접
하려던 KMS/DRM 렌더링·폰트 래스터라이징·PTY 관리·입력 처리는 그대로
유지하고, 정말 위험한 "수십 년치 xterm 호환성 엣지케이스"만 검증된
코드에 맡기는 조합이다.

### 3. 구현 언어: Zig (이 서브프로젝트부터 도입)

`kernel`/`init`/`kms`는 Rust로 유지하지만, Terminal Foundation 앱은
Zig로 작성한다. `libghostty-vt`가 Zig 네이티브 라이브러리이므로 FFI
경계 없이 바로 호출할 수 있고, 저장소에 Rust와 Zig 두 생태계가
공존하게 된다(devcontainer에 Zig 툴체인 추가 필요).

### 4. 폰트: `8x4x4-fonts` + `stb_truetype` 1회 래스터라이징

폰트는 [iolo/8x4x4-fonts](https://github.com/iolo/8x4x4-fonts)를 쓴다
(MIT/OFL-1.1 듀얼 라이선스). 원본은 영문 8x16, 한글 16x16 고정 grid
비트맵 폰트(초성 8벌·중성 4벌·종성 4벌 조합형)이며, TTF로 변환되어
배포된다. 고정 grid 디자인이라 매 프레임 곡선을 계산하는 일반 TTF
렌더링만큼 무겁지 않으면서, 한글 조합형을 처음부터 지원한다.

렌더링은 프로그램 시작 시 `stb_truetype`(단일 헤더 C 라이브러리,
FFI)으로 필요한 글리프를 한 번만 고정 픽셀 크기로 래스터라이징해
glyph cache(비트맵 배열)를 만들고, 실제 렌더링은 이 캐시에서 단순
blit만 한다.

### 5. PTY: libc `openpty()`/`forkpty()`

PTY 생성은 `/dev/ptmx` open → `grantpt`/`unlockpt` ioctl → fork →
`TIOCSCTTY` 순서를 손으로 재현하는 대신, 이미 링크되어 있는 libc의
`openpty()`/`forkpty()`를 쓴다(`kms`가 이미 `libc::mmap`/`libc::ioctl`을
쓰는 것과 같은 수준의 libc 호출이라 새 외부 의존성은 아니다). 이
순서는 DRM 모드셋팅처럼 이 서브프로젝트가 배우려는 대상 자체가
아니라, 텍스트 렌더링 + 터미널 코어라는 목적을 위한 보일러플레이트에
가깝다고 판단했다.

### 6. 입력: `libevdev` + 직접 짠 modifier/조합 dispatch

evdev 프로토콜 파싱(장치 capability bitmask, `EV_SYN` 동기화 등
실수하기 쉬운 부분)은 작은 C 헬퍼 `libevdev`(FFI)에 맡긴다. 반면 키맵
번역, modifier 상태 추적, 조합 인식·라우팅 같은 **정책**은 직접
구현한다 — `libinput`처럼 X11/Wayland 표준 키맵 정책을 통째로 가져오면
최종 비전에 있는 "macOS 키바인딩 의미론" 같은 커스텀 정책을 넣기
어려워지기 때문이다.

macOS 스타일 조합(cmd+1~9 탭 전환 등)을 인식하려면 세 조각이 필요하다:

1. **Modifier 상태 추적** — `KEY_LEFTMETA`/`KEY_RIGHTMETA`(Cmd에 대응)
   등 modifier 키의 up/down을 bitmask로 유지하는 작은 구조체.
2. **키코드 → 문자 매핑** — `KEY_1`~`KEY_9` 등 evdev 코드를 실제
   문자로 바꾸는 테이블(지금은 US QWERTY 레이아웃 하나만 하드코딩).
   이건 macOS 의미론과 무관하게 일반 타이핑 자체에 필요한 부분이다.
3. **조합 → 액션 dispatch** — `(modifier bitmask, keycode)` 조합을 보고
   "탭 N 전환" 같은 액션을 찾는 테이블. 매치되면 액션을 실행하고 PTY로
   보내지 않고, 매치되지 않으면 평소처럼 문자를 PTY로 전달한다.

Cmd(Meta)를 조합 키로 쓰는 것은 실용적으로도 유리하다 — `Ctrl+C`/
`Ctrl+D`/`Ctrl+Z` 같은 기존 쉘 제어 문자와 충돌하지 않아 "가로채기 vs
PTY로 통과"를 구분하기 쉽다. 단, 이 dispatch 테이블은 Terminal
Foundation 자체 기능(탭 전환 등)을 위한 하드코딩된 작은 테이블이지,
사용자가 임의로 키를 재배치하는 범용 키바인딩 엔진이 아니다 — 그건
최종 비전의 별도 "input policy" 서브프로젝트 몫으로 남는다.

## Milestones (초안)

- **TF-M0** — 검증 파이프라인 확장: devcontainer에 Zig 툴체인 추가,
  `libghostty-vt` 빌드/링크 sanity check, `8x4x4-fonts` 폰트 파일
  확보, `stb_truetype` FFI 연결 확인
- **TF-M1** — 프레임버퍼 텍스트 렌더링: glyph cache 구축 + 고정
  문자열을 KMS 프레임버퍼에 렌더링(아직 PTY 없음), screendump로 검증
- **TF-M2** — PTY + `libghostty-vt` 연동: 쉘(fish)을 PTY로 실행, 출력을
  `libghostty-vt`로 파싱해 터미널 셀 상태를 화면에 렌더링
- **TF-M3** — 키보드 입력: evdev로 키보드 이벤트를 읽어 PTY로 전달
  (MVP 종료점)
- **TF-M4** — 종료 게이트: 전체 체인을 스크립트로 묶어 3회 연속 검증
  (BF-M4/DF-M3와 동일한 패턴)

각 milestone이 끝난 뒤에야 다음 milestone의 상세 plan을 작성한다 —
전체를 한 번에 미리 설계하지 않는다(Boot/Display Foundation과 동일한
방식).

## 저장소 구조 (추가분)

```text
tars-linux/
├── terminal/         # Zig 프로젝트, Terminal Foundation 앱 (TF-M0~)
└── devcontainer/      # Zig 툴체인, stb_truetype, 8x4x4-fonts 추가 (TF-M0)
```

세부 디렉터리/파일명은 구현 단계에서 조정될 수 있다.

## 검증 방법

각 milestone의 exit gate는 Boot/Display Foundation과 동일하게 QEMU
screendump(PPM) + ImageMagick 픽셀 검사, 그리고 serial dmesg 로그
grep을 조합해 자동화한다. MVP 게이트(TF-M3)는 "화면 특정 좌표 영역에
shell prompt에 해당하는 글리프 패턴이 렌더링되어 있는가"를 검사하는
방식이 될 것으로 예상하나, 정확한 검사 방법(문자열 매칭 vs 픽셀 패턴
비교)은 TF-M0~M1 진행 중 구체화한다.
