# FS-M0 — `tars-help`와 첫걸음 안내 일곱 장

> 2026-11-07, `b276ba9` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design `docs/specs/2026-11-07-tars-first-steps-design.md`의 결정 1~6 전부. 설치를 마치고 재부팅한 사람이 `tars-help`를 치면
한국어로 처음 할 일이 나오고, `tars-help network`의 순서대로 치면 Wi-Fi가 잡힌다.

## 착수 전 확인 (2026-11-07)

1. 같은 모양이 이미 있다 — `tars-dictate`: 저장소의 bash 스크립트(`kernel/dictation/tars-dictate`)를 `kernel/make_initrd.sh`가
   `/usr/bin`에 복사하고(`cp` + `chmod 0755`), `quick_check.sh`의 shellcheck 목록(`sh_files+=`)이 확장자 없는 그 파일을 따로 든다.
2. initrd에 `less`가 있고(`kernel/guest_tools.sh`), `LANG=C.UTF-8`(`init/src/environ.zig`의 `LANG_ENTRY`)과 그 로케일 데이터가 실린다(HI-M1) —
   한글이 `less`로 그대로 보일 조건이다. glow는 util 묶음(TP-M8)에만 있다.
3. 하위 명령의 출처: `tars-config`는 `init/src/config_cli.zig`의 `USAGE`(get · set · reset · check · list · reload · version · passwd · help · wifi · ssh ·
   ssh-key · firewall · dictation, 인자 없으면 보기), `tars-service`는 `init/src/service_cli.zig`의 `usage()`(status · stop · start · restart).
   `tars-config help`의 끝 "turning things on"이 Wi-Fi(`set net=dhcp` → `wifi SSID` → `reload`) · 블루투스(`set bluetooth=on` → `reload` →
   `bluetoothctl`)의 순서를 이미 적는다(모두 `sudo`).
4. 설치기의 끝 줄은 `init/src/install.zig`의 `say("tars-install: done. remove the boot medium and reboot.\n")` 하나다. 그 줄을 기다리는 체인은
   `install` · `devtools` · `dualboot`(`grep -c`로 두 번을 세는 자리 포함) — 줄을 바꾸지 않고 다음 줄을 더하면 모두 그대로다. 갱신(`updated.`)
   줄에는 더하지 않는다(이미 쓰던 사람).
5. `tools` 체인은 TARS 화면에 키를 쳐서(`type_keys`) 화면 덤프(`wait_for_screen`)로 본다 — 사람이 치는 길 그대로다. 화면 덤프에서 한글을
   판정 글자로 쓰지 않는다(글자 폭 · 덤프의 모양이 걸린다) — ASCII 주제 이름과 rc로 본다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 자리: 본문 `docs/help/{index,network,bluetooth,config,services,devtools,desk}.md`(저장소), 명령 `kernel/help/tars-help`(bash). `make_initrd.sh`가
   본문을 `/usr/share/doc/tars/`, 명령을 `/usr/bin/tars-help`에 둔다(tars-dictate 옆).
B. `tars-help`:
   - 인자 없음 → `index.md`, `<주제>` → `<주제>.md`, `--list` → 주제 이름과 각 장의 첫 제목 줄(`# …`), `-h`/`--help` → 쓰는 법 세 줄.
   - 없는 주제 → stderr에 `tars-help: no topic <x>` 와 목록, rc 1.
   - 그리기: stdout이 터미널이고 `glow`가 있으면 `glow -p`, 터미널이고 glow가 없으면 `less -R`, 터미널이 아니면 `cat`(파이프 · 체인).
   - 문서 자리는 `TARS_HELP_DIR`(기본 `/usr/share/doc/tars`) — 호스트 시험과 quick 검사가 저장소의 `docs/help/`로 돌린다.
C. 설치기: `done` 줄 바로 다음에 `tars-install: after the reboot, type tars-help for the first steps.\n`. 새 설치만.
D. 문서 검사 `docs/help/check.sh`(quick_check의 새 단계): `docs/help/*.md`의 코드 블록 안에서 `tars-config <단어>` · `tars-service <단어>`
   (앞의 `sudo` 허용)를 모아, 단어가 3의 `USAGE` · `usage()`에서 뽑은 하위 명령 목록에 있는지 본다. 없으면 파일 · 줄 · 단어를 대고 실패.
   `tars-help <주제>`도 같은 방식으로 실제 파일이 있는지 본다. 인자 없는 `tars-config`는 통과.
E. 본문의 모양(일곱 장 공통): 맨 위 `# 제목` 한 줄(--list가 쓴다) → 한두 줄 "무엇을 하는 장" → 순서대로 할 일(번호 목록, 명령은 코드 블록) →
   "잘 안 되면"(확인 명령 두셋) → 다른 장으로 가는 길(`tars-help config`). 개발 사정(체인 · 결정 번호 · 로그 줄 해설 · milestone)은 쓰지 않는다.
   예시 값은 한국 기준(design 열린 질문 3).
F. 장마다 옮길 것(`running-tars.md`의 절 — design 결정 1의 표):
   - `index` — 처음 할 일 다섯(망 → 블루투스 → 설정 남기기 → 서비스 → 개발 도구), 장 목록, `tars-config help`가 있다는 것.
   - `network` — 기본은 망이 꺼져 있다 → `sudo tars-config set net=dhcp` → 유선은 reload로 끝, Wi-Fi는 `sudo tars-config wifi '집 와이파이' --country KR`
     → `sudo tars-config reload`. 확인 `wpa_cli -i wlan0 status` · `iw reg get` · `ip addr`. 시계(망이 있으면 맞춰진다).
   - `bluetooth` — `sudo tars-config set bluetooth=on` → reload → `bluetoothctl`(scan on · pair · trust · connect). 오디오는 안 된다.
   - `config` — 설정 디스크(`/config`)에 남는 것과 재부팅에 사라지는 것, `tars-config`(보기 · get · set · list · check · reload), 셸 rc · 별칭 · seed는
     한 번만, 셸이 안 뜰 때의 탈출로, sudo 비밀번호(`passwd`).
   - `services` — `tars-service status` · `restart`, 방화벽(`tars-config firewall allow 22`), ssh(`tars-config ssh on` · `ssh-key add`).
   - `devtools` — 개발 도구 층이 있으면 무엇이 깔려 있나(언어 · 편집기 · 유틸), `/usr`는 읽기 전용 · `sudo`로 깐 것은 `/usr/local`, 홈의 `~/.cargo` 등,
     Homebrew · mise, 문서(`tars-docs` · `dasht` · man). 묶음이 없는 설치에서는 이 장이 그 사실부터 말한다.
   - `desk` — 한/영 전환, 키보드, 클립보드, 배터리 · 밝기 · 절전, 소리, 받아쓰기(`tars-dictate` · `tars-config dictation`).

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. `tars-help`는 bash다(tars-dictate와 같다). 셋 갈래뿐이라 Zig 바이너리로 만들 까닭이 없다.
2. glow에 `-p`만 준다. 너비 · 스타일은 glow 기본(`--style auto`)이다 — 실기에서 어긋나면 고친다(design 위험 3).
3. 장 일곱의 글쓰기는 서브에이전트에 맡길 수 있다(CLAUDE.md 진행 방식 2). 그때 lead는 각 장의 명령을 3의 실제 하위 명령 · 키 이름(`tars-config list`의
   출력)과 대조하고 D의 검사를 돌린다.

## 할 일

1. `kernel/help/tars-help`와 호스트 시험(`TARS_HELP_DIR=docs/help`): 인자 없음 · 주제 · `--list` · 없는 주제 rc 1 · 파이프는 cat.
2. `docs/help/check.sh`(결정 D)와 `quick_check.sh` 연결 — 빨강: 장 하나에 `tars-config wfi`를 넣으면 이름을 대고 멈춘다, `tars-help nope`도.
3. 장 일곱(결정 E · F). 각 장 뒤 D를 돌린다.
4. `kernel/make_initrd.sh`(본문 · 명령), `quick_check.sh`의 shellcheck 목록에 `kernel/help/tars-help`.
5. `init/src/install.zig`의 한 줄(결정 C), `install` 체인이 그 줄을 본다.
6. `tools` 체인: `tars-help --list`의 주제 이름(ASCII) · `tars-help network | head -1`이 `#`으로 시작 · `tars-help nope; echo rc=$?`.
   판정 글자는 친 명령 줄과 겹치지 않게(`tars-help --list`의 출력에만 있는 것 — 예: `desk`가 `--list`에만 나온다).
7. `make quick`, 체인 `tools` · `install` 혼자, 루트 게이트.
8. design Status, `docs/guides/completed.md` 한 행, CLAUDE.md "서브프로젝트를 끝내면 함께 고칠 것"에 `docs/help/` 한 줄, `running-tars.md` 맨 위에
   "기계 안에서는 `tars-help`", 기억 파일, HANDOFF. 소개 페이지(`gh-pages`의 `data.js`)의 기능 목록에 한 줄(`site/README.md`의 순서).

## 판정

- `make quick`이 D의 검사로 문서의 하위 명령 · 주제를 실제와 대조하고, 할 일 2의 빨강 둘을 봤다.
- `tools` 체인이 TARS 화면에서 `tars-help`의 목록 · 장 하나 · 없는 주제를 본다. `install` 체인이 설치기의 새 줄을 본다.
- 루트 게이트 초록, 잘린 줄 0.
- 실기(사용자): 설치 직후 `tars-help` → `tars-help network`대로 Wi-Fi, `tars-help bluetooth`대로 키보드.

## 비목표

1. 셸 시작 안내 · motd · home 파일(design 비목표 1), 영어판(비목표 2), 설정 마법사(비목표 3), man 페이지(비목표 4).
2. 문서의 옵션 · 키 이름 · 순서까지의 자동 대조 — D는 하위 명령 이름과 주제만 본다(design 위험 1).
3. 화면 덤프로 한글 본문을 판정하기(확인 5).

## 위험

1. 장 일곱을 쓰는 동안 `running-tars.md`의 오래된 설명(바뀐 기능)을 그대로 옮길 수 있다 — 장마다 그 기능의 현재 `--help` · 소스와 대조한다(맡아 정한 것 3).
2. `tools` 체인의 시간이 조금 는다(명령 셋). 
3. glow -p가 TARS 터미널에서 어긋나는 것은 체인이 못 본다(파이프면 cat) — 실기.

## 확인한 것

## 결과
