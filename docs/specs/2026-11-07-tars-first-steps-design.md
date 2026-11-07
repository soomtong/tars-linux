# TARS First Steps — Design

접두사: FS (First Steps)

Status: 끝났다 — FS-M0(2026-11-07). 루트 게이트 31/31(2회차, 1회차는 PD-M4 간헐), 잘린 줄 0. plan은 `docs/plans/2026-11-07-tars-first-steps-fs-m0.md`. 기억: `docs/decisions/project_first_steps_guide.md`.

## 배경

사용자(2026-11-07, TP-M9 중): "설치를 잘 마치고 나니까 뭘 해야 될지 모르겠어서 당황해. 이런 사람들이 많을 거야. 문서를 읽어보고
시스템 세팅을 하면 되겠지. 와이파이도 잡고 블루투스도 잡고."

설치기는 `tars-install: done. remove the boot medium and reboot.`로 끝난다. 재부팅하면 셸 프롬프트만 있다. 다음에 할 일(망 켜기 → Wi-Fi →
블루투스 → 설정 남기기 …)은 저장소의 `docs/guides/running-tars.md`에만 있고, 그 문서는 체인 · 게이트 · 결정 번호 같은 개발 사정과 섞여 있다.
기계 안에는 아무 안내도 없다. 예를 들어 Wi-Fi는 `tars.conf`의 `net=dhcp` → `tars-config wifi '<SSID>' --country KR` → `tars-config reload`
순서인데(모두 `sudo`), 첫 칸(`net`이 기본 off)을 아는 길은 `tars-config help` 끝의 "turning things on" 두 줄뿐이다 — 그것이 있다는 것을
모르면 닿지 않는다. 이 안내의 망 · 블루투스 장은 그 순서를 따른다.

## 한 줄 요약

`tars-help`를 치면 한국어 첫걸음 안내가 나온다. 본문은 initrd의 `/usr/share/doc/tars/`에 있는 Markdown 몇 장이고, 설치기의 마지막 줄이
`tars-help`를 알린다.

## 사용자 결정 (2026-11-07)

1. 찾는 길은 `tars-help` 명령 하나다. 셸이 뜰 때 저절로 보이는 안내 · motd · home의 파일은 두지 않는다. 설치기의 `done` 줄 아래에 한 줄만 더한다.
2. 한국어로 쓴다. 말투는 존댓말(합니다체)이다(사용자, FS-M0 구현 중 — "한다. → 합니다. 존댓말로 작성해주세요"). 표 칸과 코드 블록의
   한국어 주석도 같다. 명령 · 키 · 값은 그대로다.
3. 범위는 넷 다 — 망 · Wi-Fi · 블루투스 / 설정 남기기 · 서비스 / 개발 도구 · 문서 / 화면 · 키보드 · 소리.

## 결정 (이 design이 제안한다 — 뒤집을 것이 있으면 번호로)

1. 본문은 주제마다 Markdown 한 장, initrd의 `/usr/share/doc/tars/`. 저장소의 출처는 `docs/help/`(`kernel/make_initrd.sh`가 복사). 이름은 ASCII다 —
   셸에서 치기 쉽게, 그리고 `tars-help <주제>`의 인자가 된다.

   | 파일 | 주제 | 옮겨 올 `running-tars.md`의 절 |
   |---|---|---|
   | `index.md` | 처음 할 일 순서(아래 다섯 장의 차례와 한 줄씩), "이 안내는 `tars-help <주제>`" | — |
   | `network.md` | 망 켜기(`net=dhcp`), 유선, Wi-Fi(`tars-config wifi` · reload · 확인 명령), 시계 | 네트워크와 시계, 무선에 붙기 |
   | `bluetooth.md` | 키보드 · 마우스 짝 맞추기, 안 되는 것(오디오) | 블루투스 |
   | `config.md` | 설정 디스크와 남는 것 · 안 남는 것, `tars-config`(인자 없이 · get · set · list · reload), 셸 설정 · 별칭 · seed, 셸이 안 뜰 때 | 설정을 남기려면, 기계가 기억하는 것, 설정, 별칭, seed, 셸이 안 뜨면 |
   | `services.md` | `tars-service`(목록 · 멈춤 · 다시), 방화벽, ssh로 붙기 | 방화벽, 부팅 때 뜨는 서비스, 서비스를 멈추고, ssh |
   | `devtools.md` | 깔린 언어 · 도구(개발 도구 층), `/usr`는 읽기 전용 · `/usr/local`, Homebrew · mise, `tars-docs` · `dasht` · man | 문서, "안 되는 것" 표의 `/usr`에 쓰기 |
   | `desk.md` | 한/영 전환, 키보드, 클립보드, 배터리 · 밝기 · 절전, 소리, 받아쓰기(`tars-dictate`) | 한/영, 키보드, 클립보드, 배터리, 밝기와 절전, 소리, 받아쓰기 |

   체인 · 게이트 · design 번호 · 로그 줄의 뜻 같은 개발 사정은 옮기지 않는다. `running-tars.md`는 저장소의 긴 안내서로 그대로 둔다.
2. `tars-help`는 initrd의 셸 스크립트(`/usr/bin/tars-help`)다. `tars-help`는 `index.md`, `tars-help <주제>`는 그 장, `tars-help --list`는 주제 이름과
   한 줄. 없는 주제는 목록을 보이고 1로 끝난다. 그리기는 `glow`가 있으면 `glow -p`(util 묶음, 열린 질문 2), 없으면 `less`(initrd), 터미널이 아니면 `cat` —
   개발 도구 층이 없는 기계에서도 읽힌다.
3. 설치기는 `done` 줄 다음에 `tars-install: after the reboot, type tars-help for the first steps.`를 찍는다. 설치기의 다른 줄처럼 영어다(로그 줄의
   규칙). `done` 줄은 그대로 두어 그 줄을 기다리는 체인(`install` · `devtools` 등)이 바뀌지 않는다.
4. 문서와 명령이 어긋나지 않게: 문서 안 코드 블록의 `tars-config <하위 명령>` · `tars-service <하위 명령>`이 실제 하위 명령인지 `make quick`이
   본다(하위 명령 목록은 그 명령의 `--help` 출력 또는 소스의 표에서 — 방법은 plan). 기능이 바뀌면 `docs/help/`도 고친다는 것을 CLAUDE.md의
   "서브프로젝트를 끝내면 함께 고칠 것"에 한 줄 더한다.
5. 체인: 이미 initrd로 셸을 띄우는 체인 하나(후보 `tools`)에 `tars-help --list` · `tars-help network | head` · 없는 주제의 rc 1을 더한다.
   새 체인은 만들지 않는다. 설치기의 새 줄은 `install` 체인이 본다.
6. initrd 크기: Markdown 일곱 장, 수십 KB. `initrd-criteria.md`의 기준(부팅 없이 쓸모가 있는가)에는 "설치 직후 망 없이 읽는 안내"로 든다.

## 열린 질문 (사용자가 정한다)

없다(2026-11-07, 사용자 "agree all"). 닫은 것:

1. 주제는 일곱 장(결정 1) — `tars-help network`처럼 바로 간다.
2. glow는 페이저로(`glow -p`) — 긴 장이 화면을 넘는다.
3. 예시 값은 한국 기준(`--country KR` 등) 그대로 — 한국어 문서와 맞다.

## 판정

- 설치 뒤 재부팅한 셸에서 `tars-help`가 처음 할 일을 보이고, `tars-help network`의 순서대로 치면 Wi-Fi가 잡힌다(실기 — 사용자).
- 체인: `tars-help`의 목록 · 장 하나 · 없는 주제, 설치기의 새 줄. `make quick`: 문서 안 하위 명령이 실제와 맞다.
- 루트 게이트 초록.

## 비목표

1. 셸이 뜰 때 저절로 보이는 안내 · motd · home의 파일(사용자 결정 1).
2. 영어판(사용자 결정 2). 나중에 더하면 `docs/help/en/`과 `tars-help --lang`.
3. 대화형 설정 마법사(`tars-setup` 같은 것) — 이 안내가 가리키는 명령들이 이미 있다. 실기에서 안내만으로 부족하면 그때 다시 논의한다.
4. man 페이지(`man tars-config`). 각 명령의 `--help`는 그대로다.

## 위험

1. 문서가 기능보다 늦게 고쳐진다. 결정 4의 검사는 하위 명령 이름만 본다 — 옵션 · 순서 · 키 이름은 사람이 본다.
2. `running-tars.md`와 내용이 두 벌이 된다. 어느 쪽이 기준인지 정해 둔다: 기계 안의 `docs/help/`가 사용자용 기준, `running-tars.md`는 개발 · 실기 메모.
3. glow의 그리기가 TARS 터미널에서 어긋날 수 있다(표 · 색). 실기에서 보고, 문제면 `less`로 바꾼다(결정 2의 순서만 바꾼다).

## Milestone

- FS-M0 — 결정 1~6 전부. 장 일곱의 내용이 대부분의 일이다. 커널 · init 무변경(설치기의 한 줄은 `init/src/install.zig`).
