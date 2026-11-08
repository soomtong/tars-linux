# TP-M12 — AI 도구: 싣지 않고, 공식 설치 길이 TARS에서 서는지 한 번 확인한다

> 2026-11-08, `2a3c883` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP design의 마지막 milestone. AI 도구 넷(claude code · codex · opencode · oh-my-pi `omp`)을 개발 도구 층에 싣지 않는다. 사용자가 망이 있을 때
각 도구의 공식 설치 길로 홈에 깔고, 그 도구가 화면 셸에서 이름으로 불리는지를 한 번 확인한다. 막히는 자리가 TARS 쪽이면 기본 이미지 쪽을 푼다
(PM · MI와 같은 모양). 이 milestone이 끝나면 TP 서브프로젝트를 닫고 0.2.0을 낸다.

사용자 결정(2026-11-08):
- "AI 도구는 설치만 가능한지 검토하는 것으로 끝내자. homebrew, mise와 같은 맥락이다. 사용자가 설치하는 것이지. 어짜피 네트워크 연결이 없으면
  사용하지 못한다." — design 결정 17 · 14를 18판에서 고쳤다.
- 확인은 한 번만 한다. 게이트 체인을 두지 않는다(남의 설치 스크립트 넷이 자주 바뀌어 우리 코드와 상관없이 빨개진다).
- 묶음 사이 중복 지우기(약 70MB)는 `carryover.md`로 이월했다 — AI를 싣지 않아 ISO 2GiB 자리가 급하지 않다.

## 착수 전 확인 (2026-11-08)

1. 공식 길(각 프로젝트 문서 · README, 2026-11-08 검색 — 착수 때 스크립트를 받아 읽고 sha256 · 줄 수를 적는다):
   - claude code: `curl -fsSL https://claude.ai/install.sh | bash` → `~/.local/bin/claude`.
   - codex: 공식 설치 스크립트(Node 없이 단독 바이너리, releases.openai.com 먼저 · GitHub Releases로 내려감 — URL은 착수 때 확인).
     다른 길은 GitHub Releases의 `codex-x86_64-unknown-linux-musl.tar.gz`, `npm i -g @openai/codex`(Node 22+).
   - opencode: `curl -fsSL https://opencode.ai/install | bash` → `OPENCODE_INSTALL_DIR` · `XDG_BIN_DIR` · `~/bin` 차례로 보고 없으면 `~/.opencode/bin`.
     `--no-modify-path`가 있다.
   - omp: `curl -fsSL https://omp.sh/install | sh`. README가 권하는 길은 `bun install -g @oh-my-pi/pi-coding-agent`(bun 1.3.14 이상 — lang-script의 bun 판을
     착수 때 대조). `mise use -g github:can1357/oh-my-pi`도 있다.
2. PATH: 시스템 rc 셋(`kernel/make_initrd.sh`의 bash.bashrc · zshrc · fish conf.d)은 `~/.local/bin`을 따로 넣지 않는다 — mise가 있을 때 `mise activate`가
   넣을 뿐이다(MI-M1). 그래서 mise 없는 기계에서 claude의 `~/.local/bin/claude`는 이름으로 안 불릴 것이다. 화면 셸은 fish이고, 설치 스크립트가 고치는
   rc는 `$SHELL`을 보고 고르거나(opencode) 안내만 한다(claude) — 실제로 무엇을 쓰는지는 착수 때 스크립트에서 본다.
3. 커널(`kernel/.config`): `# CONFIG_USER_NS is not set`(163) · `# CONFIG_SECCOMP is not set`(588), Landlock 줄 없음. codex는 셸 명령을 샌드박스 안에서
   돌리는데 Linux의 길이 Landlock · seccomp 또는 bubblewrap(사용자 이름공간)이다 — TARS에는 셋 다 없다. claude code의 샌드박스(선택 기능)도 bubblewrap이다.
   설치 · `--version`에는 상관없고, 도구가 명령을 실행하는 순간에 드러날 것이다.
4. 망을 쓰는 체인의 선례: `mise/check.sh`(MI-M0) — ISO로 설치 → NVMe + SLIRP NIC 부팅에서 root 콘솔 셸에 시리얼로 한 줄씩, "사용자로"는 `setpriv`,
   화면 셸은 monitor `sendkey`. 이번 확인은 그 모양을 빌려 쓴다.
5. `/tmp`는 RAM이다. 설치 스크립트가 받은 파일을 `/tmp`에 두면 게스트 RAM을 먹는다(carryover의 MI-M0 항목 — mise는 512MB에서 굳었다).
   확인은 devtools 체인과 같은 2GiB 게스트로 한다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 확인 대상은 도구마다 공식 문서가 맨 앞에 두는 길 하나다 — claude · opencode · omp는 curl 설치 스크립트, codex는 공식 설치 스크립트. npm · bun · Homebrew ·
   mise 길은 보증하지 않는다(MI design 결정 2와 같은 선). 단, omp의 스크립트가 bun을 요구하면 개발 도구 층의 bun으로 서는지까지 본다.
B. 판정(도구마다): 망 있는 부팅에서 사용자 tars로 설치가 rc 0 → `<도구> --version`이 판을 찍는다 → 화면 셸(fish)에서 이름만으로 불린다.
   재부팅 뒤 망 없는 부팅에서도 `--version`이 돈다(홈에 남는가). 로그인 · 모델 호출은 보지 않는다 — 계정이 필요하다.
   덧붙여 화면 터미널에 첫 화면(로그인 · 테마 고르기)을 띄워 monitor `screendump`로 남긴다 — TARS 터미널에서 TUI가 깨지지 않는지 사람이 본다.
C. 확인 스크립트는 저장소에 넣지 않는다 — `mise/check.sh`를 빌려 scratchpad에서 한 번 돌리고, 친 명령과 결과를 이 plan의 "확인한 것"에 적는다.
   다시 볼 일이 생기면 그 절이 절차다. `check.sh`의 `CHAINS`는 그대로(31).
D. 막히는 자리를 고치는 선: TARS 쪽(기본 이미지 · 시스템 rc · 개발 도구 층)이면 이 milestone이 고치고 게이트를 돈다. 착수 전 확인 2가 맞으면
   후보는 시스템 rc가 `~/.local/bin`이 있을 때 PATH 앞에 넣는 것(XDG의 사용자 실행 파일 자리, Debian `~/.profile`과 같은 일 — claude · mise ·
   pipx · uv가 쓴다)이다. 커널 설정(확인 3)은 이 milestone이 바꾸지 않는다 — 결과를 들고 사용자에게 묻는다(보안 · 크기 · 부팅 경로의 결정).
E. 안내: `tars-help devtools`의 "더 깔기"에 AI 도구 넷의 설치 한 줄씩과 "망이 있어야 쓴다"(Homebrew · mise 줄 옆). 확인에서 막힌 것이 남으면 그 한 줄.
   `running-tars.md`의 같은 자리.
F. TP 닫기(CLAUDE.md의 "서브프로젝트를 끝내면"): design `Status:` 끝남, `completed.md` 한 행, 소개 페이지(`gh-pages`의 `data.js`), 기억 한 파일 ·
   `MEMORY.md`, `HANDOFF.md`, design의 "닫을 때" 줄(PM design 결정 4로의 한 줄 · `carryover.md` 패키지 매니저 항목 · `running-tars.md` "안 되는 것" ·
   `project_release.md`). 그 뒤 0.2.0 릴리스는 `project_release.md`의 일곱 단계 — 사용자 확인을 받고.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. 넷을 한 게스트에 차례로 깐다(도구끼리 서로 막는지도 보인다). 순서는 claude → codex → opencode → omp.
2. 설치 스크립트가 rc를 고치겠다고 물으면 기본값을 따른다 — 사람이 처음 치는 그대로. 고친 rc가 fish에도 닿는지를 판정 B의 "이름만으로"가 본다.
3. 각 스크립트의 sha256 · 줄 수 · 받은 바이너리 크기 · `NEEDED`(glibc 판인지 musl 판인지)를 적는다 — 다음에 깨졌을 때 무엇이 바뀌었는지 대조할 숫자.

## 할 일

1. 설치 스크립트 넷을 호스트에서 받아 읽는다 — 받는 곳 · 두는 곳 · 부르는 명령(`unzip` · `bun` 등) · libc 판정 · 고치는 rc. 착수 전 확인 1 · 2를 고친다.
2. 확인 한 판(결정 B · C): 설치 부팅(망) → 재부팅(망 없음) → 화면 셸.
3. 막힌 것이 TARS 쪽이면 고친다(결정 D). 고쳤으면 다시 한 판, `make quick`, 루트 게이트.
4. 커널 쪽(확인 3)이 실제로 막았으면 무엇이 안 되는지(예: codex가 명령을 못 돌림, 어떤 플래그로 피해지는지)를 적고 사용자에게 묻는다.
5. 안내(결정 E), TP 닫기(결정 F).

## 판정

- 넷 모두 판정 B를 지나거나, 지나지 못한 것은 그 이유와 우회 길이 plan과 안내에 적혔다.
- TARS 쪽을 고쳤다면 루트 게이트 초록, 잘린 줄 0. 안 고쳤다면 게이트는 TP-M11의 31/31이 그대로다(바뀐 코드 없음 — 문서만).

## 비목표

1. AI 도구를 개발 도구 층 · initrd에 싣는 것(사용자 결정).
2. 게이트 체인(사용자 결정 — 한 번만).
3. 로그인 · API 키 · 모델 호출, 도구의 기능 검사.
4. npm · bun · Homebrew · mise 길의 보증(결정 A).
5. 커널 설정 변경(결정 D — 필요하면 따로 묻는다).

## 위험

1. 설치 스크립트가 움직인다 — 확인한 날의 sha256을 적고, 그 날의 결과로만 말한다.
2. RAM: 받은 tarball과 푼 바이너리가 `/tmp`(RAM)에 함께 있으면 작은 기계에서 넘친다(확인 5). 2GiB 게스트에서 서도 에어 2011의 바닥과 같을 뿐이다.
3. 샌드박스(확인 3): codex가 기본 설정으로 명령을 못 돌리면 "설치는 되나 쓰기 어렵다"가 된다 — 그 판단과 커널 옵션은 사용자 몫이다.
4. 바깥 망: 확인 전에 호스트에서 각 URL을 한 번 친다(MI 체인의 사전 확인과 같다). 안 닿으면 그 이름으로 멈춘다.

## 확인한 것

(구현 뒤 채운다)

## 결과

(구현 뒤 채운다)
