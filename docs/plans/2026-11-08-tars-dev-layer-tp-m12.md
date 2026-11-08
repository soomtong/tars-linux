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

1. 할 일 1(2026-11-08, 호스트에서 받아 읽기만 — 실행하지 않았다). codex의 URL은 openai/codex README가 `curl -fsSL https://chatgpt.com/codex/install.sh | sh`로 적는다.

   | 도구 | 스크립트(sha256 앞 16 · 줄) | 두는 곳 | libc 판정 · 판 | 받은 파일 자리 | PATH를 고치는 곳 |
   |---|---|---|---|---|---|
   | claude | `3a68d3406cf674e1` · 260 | `claude install`이 `~/.local/bin/claude` | `ldd /bin/ls`에 musl이 없으면 glibc 판 | `~/.claude/downloads`(홈) | 스크립트는 안 고친다 |
   | codex | `44ac252c1b9a68c0` · 1,500 | `~/.local/bin/codex` → `~/.codex/packages/standalone` | 늘 musl 정적 판, `codex-resources/bwrap`을 함께 싣는다 | `mktemp -d`(`/tmp`) | `$SHELL`이 zsh · bash가 아니면 `~/.profile` — fish는 안 읽는다 |
   | opencode | `a2dd59522b9a091b` · 484 | 늘 `~/.opencode/bin`(검색 결과의 `XDG_BIN_DIR`은 이 판에 없다) | `/proc/cpuinfo`에 avx2가 없으면 `-baseline` — SandyBridge 맞춤 | `${TMPDIR:-/tmp}` | fish면 `~/.config/fish/config.fish`가 이미 있을 때만 `fish_add_path` |
   | omp | `cd8f77920da58c6f` · 389 | bun이 있고 아키텍처가 맞으면 `bun install -g` → `~/.bun/bin/omp`, 없으면 `~/.local/bin/omp` | bun 길이면 해당 없음 | bun 길은 bun의 캐시 | 안 고친다(안내 한 줄) |

   예상(할 일 2가 확인한다):
   - TARS에는 bun 1.4.4(lang-script)가 있고 omp의 `MIN_BUN_VERSION`이 정확히 1.4.4다 — omp는 bun 길로 간다. `~/.bun/bin`은 TARS PATH에 없다.
     이것은 AI와 상관없이 `bun install -g`가 이름으로 안 서는 빈자리다 — lang-native의 rc 조각이 `~/.cargo/bin` · `~/go/bin`을 넣는 것과 짝이 안 맞는다.
   - `~/.local/bin`은 mise가 있을 때만 PATH에 든다(착수 전 확인 2) — claude · codex가 화면 셸에서 이름으로 안 설 것이다.
   - opencode는 seed의 `config.fish`(`/config/fish.config`로의 링크, `init/src/config.zig`)가 있으면 그 파일에 `fish_add_path`를 쓴다 — 서는지는 실제로 본다.
   - codex의 `bwrap`은 사용자 이름공간이 있어야 돈다 — `CONFIG_USER_NS`가 꺼진 TARS에서 명령 실행이 막힐 것이다(착수 전 확인 3).
   - 받을 때 `/tmp`(RAM)를 쓰는 것은 codex · opencode. claude는 홈, 설치에 빈 메모리 약 512MB를 요구한다(스크립트의 137 안내).
2. 할 일 2, 확인 한 판(`out/tp-m12/probe.sh` — 저장소 밖, ISO `09ec9ef`, SandyBridge · 2GiB, 부팅 셋 441초). 첫 판은 codex 설치기가 끝에서
   "Start Codex now? [y/N]"를 `/dev/tty`(콘솔)로 물어 20분을 기다렸다 — 확인 스크립트의 일이다. 둘째 판은 설치기가 밝힌 `CODEX_NON_INTERACTIVE=1`(N과 같다).
   - claude: rc 0, 89초. 2.1.319, `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.319`(340MB, glibc 동적, 빠진 `.so` 0). 설치기가 스스로
     "~/.local/bin is not in your PATH"라 하고 fish용 한 줄(`config.fish`에 `export PATH=…`)을 안내한다 — 고치지는 않는다.
   - codex: rc 0, 48초. 0.167.0, `~/.local/bin/codex` → `~/.codex/packages/standalone/releases/0.167.0-x86_64-unknown-linux-musl`(321MB, static-pie).
     PATH 줄은 `~/.profile`에 썼다(fish · 대화형 bash는 안 읽는다). `codex sandbox linux -- echo …`는 rc 1 —
     `bwrap: Creating new namespace failed, likely because the kernel does not support user namespaces.` 확인 3의 예상대로다.
   - opencode: rc 2, 14초. 설치기가 고른 판은 1.19.5다 — npm `opencode-ai`의 latest(OpenCode 1). 설치기 주석: "OpenCode 2 ships as @opencode/cli", GitHub의
     Latest는 v2.2.6. 실패는 `gzip: stdin: not in gzip format` — 그 시각 GitHub 릴리스 내려받기가 `504 Gateway Time-out`(92바이트 HTML)을 냈다(호스트에서도
     같은 URL과 codex의 GitHub 자산이 504, 2026-11-08 09:23 UTC). 설치기의 `curl -# -L`에 `-f`가 없어 그 HTML을 tarball로 저장했다. TARS의 일이 아니다 —
     GitHub가 돌아오면 다시 본다.
   - omp: rc 0, 24초. bun 길(`bun add` · 63 패키지) → `~/.bun/bin/omp` → `@oh-my-pi/pi-coding-agent@18.18.1/dist/cli.js`(TARS의 bun 1.4.4로 돈다). bun이
     "add the global bin folder to $PATH: fish_add_path /home/tars/.bun/bin"을 안내한다.
   - 이름으로: 대화형 bash · zsh · fish 셋 모두 넷 다 못 찾았다. 망 없는 부팅 3의 화면 셸(fish)에서 `claude --version` · `codex --version` ·
     `omp --version`이 모두 `fish: Unknown command` — 확인 1의 예상대로다. 실행 파일은 재부팅 뒤 홈에 그대로 있다(경로로 부르면 판을 찍는다 — 부팅 2).
   - 홈 크기: `~/.local` 325M · `~/.codex` 516M · `~/.bun` 477M. OOM 0.
   - 사용자 tars는 이미 `~/.config/fish/config.fish`(seed)를 가진다 — opencode 설치기는 여기에 `fish_add_path`를 쓸 것이다(다시 볼 때 확인).
3. 고친 것(결정 D): 시스템 rc 셋(`kernel/make_initrd.sh` — bash.bashrc · zshrc 끝, fish `conf.d/user-bin.fish`)이 `~/.local/bin`이 있으면 PATH 맨 앞에
   넣는다(없으면 안 넣는다 — root와 다른 체인의 PATH는 그대로, mise가 넣었으면 그대로). lang-script 묶음에 `~/.bun/bin` 조각 둘(`etc/tars/rc.d/lang-script.sh` ·
   `etc/fish/conf.d/10-lang-script.fish`, lang-native의 cargo · go와 짝 — AI와 상관없이 `bun install -g`의 빈자리였다). devtools 체인 B2에 넷(fish · bash에서
   `~/.bun/bin`이 있고, 만든 `~/.local/bin`이 맨 앞). `make quick` PASS(shellcheck 87파일).
4. 고친 ISO로 다시(`out/tars-dev.iso` — devtools 체인이 굽는 쪽. 셋째 판은 옛 `out/tars.iso`를 써서 그대로 `Unknown command`였다, 확인 스크립트의 실수).
   넷째 판: 망 없는 부팅 3의 화면 셸(fish)에서 `claude --version` → `2.1.319 (Claude Code)`, `codex --version` → `codex-cli 0.167.0`, `omp`는 이름으로
   불렸으나 bun이 `pi_natives.linux-x64-baseline.node`를 읽다 SIGBUS. 다섯째 판에서 부팅 2 끝에 `sync`를 넣자 `omp/18.18.1` — 넷째 판의 SIGBUS는 확인
   스크립트가 QEMU를 죽여(전원 끊김) 막 쓴 `.node`가 디스크에 덜 내려간 것이었다(mmap한 파일의 빈 자리). 첫 화면: claude는 로고 뒤 `Unable to connect to
   Anthropic services … EAI_AGAIN`(망 없음 — 맞다), codex는 점자 로고와 `Sign in with ChatGPT` 고르기, omp는 로고와 `Tip: Please use nerdfont` — TARS
   터미널에서 셋 다 깨지지 않았다. codex의 우회는 `-s, --sandbox <SANDBOX_MODE>`와 `--dangerously-bypass-approvals-and-sandbox`(`codex --help`).
   opencode는 다섯째 판에도 게스트가 받은 것이 `HTTP/2 504` HTML 92바이트였다 — 같은 시각 호스트 · 컨테이너에서도 opencode의 다른 자산과
   `cli/cli`의 릴리스 파일까지 504(2026-11-08 10:10 UTC 무렵, GitHub 릴리스 내려받기 장애). GitHub가 돌아오면 opencode 하나만 다시 본다.
   곁가지: 화면 셸에 `clear`가 없었다(`fish: Unknown command: clear`) — 사용자 "add clear into base" → initrd 기준 C(셸의 일상 기본, 개발 도구 층
   없는 부팅에도)로 다시 보고 initrd에 싣기로 했다(사용자 "ok agree with you"): Debian `ncurses-bin`의 clear · tput · tset(→ `reset` 이름),
   셋 다 libtinfo · libc뿐(이미 initrd에 있다). `devcontainer/Dockerfile` sysroot 목록 한 줄 + `kernel/guest_tools.sh` 층 13에 세 줄 — 이미지를 다시
   구워야 하는데 층 597(lsoff · doge)이 GitHub에서 받으므로 GitHub 장애가 풀린 뒤.
5. codex 샌드박스(사용자 2026-11-08): 이번에는 커널을 바꾸지 않는다 — 안내에 "TARS에서는 codex 샌드박스가 서지 않는다". user namespace만 켜면 AI 샌드박스는
   서지만 Docker는 안 서므로, 컨테이너 실행 환경(cgroups · namespace 전부 · veth/bridge/NAT · seccomp · USER_NS)을 다음 서브프로젝트 후보로
   `carryover.md`에 옮겼다(그날의 커널 옵션 표와 함께). 사용자: "개발도구 중에 도커를 쓰는 경우가 종종 있죠".

6. clear를 initrd에 싣기 위해 개발 컨테이너 이미지를 다시 구웠다(2026-11-08 밤, `3a1634a5a5d6`) — 그 뒤 devtools 체인이 `make dev-layers`에서 멈췄다:
   `base and docs both carry /usr/lib/x86_64-linux-gnu/libz.so.1.3.1 with different contents`(이에 앞서 verify의 결정 4). 원인은 거두는 이미지
   `debian:trixie-slim`(스냅숏 2026-10-27)에 처음부터 깔린 zlib1g `-1+b1`이다. 그 이미지의 sources에는 trixie-security가 있지만 `apt-get install`은
   이미 깔린 의존을 올리지 않고, harvest.sh의 의존 폐포 단계가 그 옛 파일을 싣는다. 새로 구운 개발 컨테이너의 sysroot(= initrd)는 trixie-security의
   `+deb13u1`을 받았다. 같은 날 `apt list --upgradable`에는 apt · tzdata도 있었다 — TP-M3의 tzdata 어긋남(`harvest-skip.tsv`)도 같은 뿌리였다.
   고친 것: harvest.sh가 "설치 전" 스냅숏 앞에 `apt-get update` · `apt-get upgrade`(새 패키지를 들이지 않는다). zlib1g 하나를 skip에 넣는 길은 다음
   security 갱신에서 또 멈춘다. 고친 뒤 첫 `make dev-layers`가 한 번 더 같은 줄로 멈췄다 — base만 새로 굽고 아직 안 구운 묶음의 `.paths`(옛 해시
   `85590d…`)와 대조해서다. 그 여섯의 `.paths`를 지우자 열 묶음 모두 `differs=0`, libz를 싣는 일곱이 같은 `6c139317…`. devtools 체인 PASS(빌드 뒤 671초).
   곁가지: `devlayer/manifest.tsv`의 xxd `deb13u1` → `deb13u2`(미러가 옛 판을 내렸다).
7. 다시 한 판(2026-11-09, 확인 스크립트 셋 sha256 · 줄 수가 11-08과 같다 — codex `44ac252c` · omp `cd8f7792` · opencode `a2dd5952`, ISO는 위 devtools
   체인이 구운 `out/tars-dev.iso`, 부팅 셋 565초, `out/tp-m12/run-20261108-234431`). claude는 넷째 판에서 끝났으므로 이번 순서는 codex → omp → opencode
   (opencode를 끝에 두어 TUI가 다른 도구를 삼키지 않게, 끝내기는 `/exit`). 이름 확인의 따옴표 버그(바깥 bash가 `$c`를 빈 값으로 펼쳤다)를 고쳤다.
   - codex: rc 0, 43.6초, 0.167.0. opencode: rc 0, 16.6초, 1.19.5(`~/.opencode/bin/opencode` 214MB, 빠진 `.so` 0) — GitHub 장애가 풀려 섰다.
     omp: rc 0, 20.8초, 18.18.2(하루 사이 18.18.1에서 올랐다).
   - 이름으로: codex · omp는 bash · zsh · fish 셋 다(확인한 것 3의 시스템 rc와 `~/.bun/bin` 조각). opencode는 fish에서만 — 설치기가 `$SHELL`(fish)을 보고
     `~/.config/fish/config.fish` 끝에 `# opencode` · `fish_add_path /home/tars/.opencode/bin`을 썼다. 화면 셸이 fish라 판정 B는 지난다. bash · zsh에서
     쓰려면 `~/.opencode/bin`을 PATH에 넣어야 한다(안내 한 줄). codex는 여전히 `~/.profile`에도 PATH 줄을 쓴다(시스템 rc가 이미 넣으므로 무해).
   - 망 없는 부팅 3의 화면 셸: `codex --version` → `codex-cli 0.167.0`, `omp --version` → `omp/18.18.2`. `opencode --version`은 8초 안에 줄이 비었다 —
     같은 셸에서 이름으로 띄운 opencode TUI가 30초 화면은 비었고 60 · 120초에 로고 · 입력란 · `1.19.5`를 그렸으므로, 망 없는 첫 실행이 느린 것이지
     안 서는 것이 아니다. `/exit`로 프롬프트가 돌아왔다.
   - clear: 친 뒤 화면 맨 위가 프롬프트 한 줄. `tput cols` → 155. initrd(층 13)에서 섰다.
   - codex `--sandbox`: 틀린 값에 clap이 `[possible values: read-only, workspace-write, danger-full-access]`, `danger-full-access`면 rc 0 — 안내의 값이
     맞다. `codex sandbox linux`는 여전히 bwrap의 user namespace 실패(rc 1, 확인한 것 5).
   - omp nerd(`~/nerd/.omp/config.yml`의 `symbolPreset: nerd`): 상태 줄의 Powerline 화살표는 NS-M0의 그림으로 섰고, Nerd Font 아이콘(U+F0000대 등)은
     자리표 `?` — NS design이 진짜 글꼴 체계를 GPU 단계로 이월한 그대로다.
   - 홈: `~/.codex` 516M · `~/.opencode` 205M · `~/.bun` 477M. OOM 0.

## 결과

판정을 지났다. AI 도구 넷은 개발 도구 층에 싣지 않고, 공식 설치 길로 홈에 깔려 화면 셸(fish)에서 이름으로 불리며 망 없는 재부팅 뒤에도 돈다
(claude 2.1.319 · codex 0.167.0 · opencode 1.19.5 · omp 18.18.2, 2026-11-08 · 09). 판정 B를 막은 것은 셋이었고 모두 TARS 쪽에서 고쳤다(결정 D).

- 시스템 rc 셋이 `~/.local/bin`이 있으면 PATH 앞에(claude · codex), lang-script가 `~/.bun/bin`(omp — `bun install -g` 전반의 빈자리).
- 화면 셸의 `clear`가 없었다 — `clear` · `tput` · `reset`(tset)을 initrd에(사용자 동의).
- 그 이미지를 다시 굽다 드러난 거두기의 판 어긋남 — harvest.sh가 slim을 먼저 `apt-get upgrade`(확인한 것 6).

남긴 것(우회 길과 함께 안내에 있다): codex 샌드박스는 커널에 user namespace가 없어 서지 않는다 — `--sandbox danger-full-access`(사용자 결정, 컨테이너
실행 환경은 `carryover.md`). opencode는 fish에만 PATH를 쓴다. omp의 Nerd Font 아이콘은 자리표. 게이트 체인은 두지 않았다(사용자 결정 — `CHAINS` 31 그대로).
