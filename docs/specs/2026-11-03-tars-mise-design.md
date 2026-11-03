# TARS Mise — Design

접두사: MI

Status: MI-M0 끝남(2026-11-03). 공식 `mise.run` → `mise use -g node@lts` → node 26이 기본 이미지를 하나도 안 고치고 섰다.
MI-M1(activate)의 plan을 쓴다.

관련 문서: `2026-11-03-tars-package-manager-design.md`(PM. 같은 모양 — 공식 설치 길이 막히지 않게 기본 이미지 쪽을 푼다 · 바깥
망 체인 · 시스템 rc의 shellenv) · `2026-11-02-tars-home-partition-design.md`(HP. `/home` ext4 · uid 1000 사용자) ·
`docs/guides/carryover.md`의 PM 절(mise 검토 메모, 2026-11-03) · `docs/decisions/project_package_manager.md`.

## 한 줄 요약

사용자가 화면 셸에서 공식 `curl https://mise.run | sh`를 치고 `mise use -g node@lts`로 node를 받으면 그 node가 뜨도록, 막히는
자리를 기본 이미지 쪽에서 푼다. mise 자체는 initrd에 싣지 않는다. 게이트는 실제 망으로 mise와 node를 받아 실행한다.

## 왜 지금인가

PM이 Homebrew의 길을 세우면서 mise가 부르는 도구(`curl` · `tar` · `sha256sum` · `ldd`)와 바깥 바이너리가 가정하는 glibc 전체
(PM 결정 7) · libstdc++의 이름(PM 결정 10)이 이미 섰다. 2026-11-03에 mise를 검토하고 initrd에 싣지 않기로 했으므로(176MB, RAM 상주),
남은 일은 사용자가 홈에 까는 길을 끝까지 확인하는 것이다. 아직 TARS에서 한 번도 돌려 보지 않았다.

## 사용자가 정한 것 (2026-11-03)

1. initrd에는 mise를 싣지 않는다(검토 때 결정). v2026.10.25 Linux x64가 176MB이고(BOLT가 원본 `.bolt.org.text` 89MB ·
   `.bolt.org.rodata` 25MB를 품는다) gzip해도 60MB, musl 판도 158MB다. `NEEDED`는 libc · libm · libgcc_s · libdl · librt ·
   libpthread, `GLIBC_2.18`.
2. 설치 길은 공식 `mise.run` 하나만 보증한다. `brew install mise`는 보증하지 않는다(비목표 1).
3. 게이트가 받아 실행할 런타임은 `node@lts`다.
4. `mise activate`를 어디에 둘지(시스템 rc · shims · 사용자 rc)는 M0의 실측을 본 뒤 M1에서 정한다.

## 착수 전에 아는 것 (2026-11-03에 소스에서 확인)

`mise.run`은 그날의 판(482줄, 내장 버전 v2026.10.25, sha256 `61cb4d61…`)을 읽었다. 움직이는 스크립트라 숫자는 그날의 것이다.

### 확인 1 — `mise.run`이 부르는 것은 PM-M0 뒤로 다 있다

- libc 판정: `type ldd`가 있으면 `ldd /bin/ls`의 출력에서 `musl`을 찾는다. `ldd`는 PM-M0이 실었고, `/bin`은 usrmerge로
  `usr/bin`을 가리키며 `ls`는 `GUEST_TOOLS`에 있다. glibc 판(`linux-x64`)을 고른다.
- 압축: `zstd`가 없으면 `.tar.gz`로 내려간다. 게스트에 `zstd` 명령은 없다 — 이 길이 정상 경로다.
- 받기: `curl --compressed -fsSL`. `mise.jdx.dev`가 먼저이고 실패하면 GitHub Releases로 간다.
- 검증: checksum이 스크립트에 박혀 있고 `shasum` 또는 `sha256sum -c`로 본다. `sha256sum`은 PM-M0이 실었다.
- 풀기: `mktemp -d` · `tar --no-same-owner -xf` · `mv`로 `~/.local/bin/mise`. 전부 있다.
- 끝: `$SHELL`을 보고 rc에 넣을 activate 줄을 안내한다. 화면 셸의 `SHELL`은 terminal이 준다.

### 확인 2 — mise는 node를 `.tar.gz`로 받고, 기본으로 gpg 검증을 한다

`src/plugins/core/node.rs`(main): 미리 빌드된 판을 `node-v{v}-linux-x64.tar.gz`로 nodejs.org에서 받고 `SHASUMS256.txt`로 본다.
`node.gpg_verify`가 `false`가 아니면 `SHASUMS256.txt.sig`로 gpg 검증을 한다(`gpg::verify_node`, `mise_util` 크레이트).
그 검증이 바깥 `gpg` 명령을 부르는지는 소스만으로 정하지 않았다 — M0가 실제로 돌려서 본다. 게스트에 `gpg`는 없다.

M0가 닫았다: 바깥 `gpg`를 부르지 않는다. 서명 패킷의 덤프(`IssuerFingerprint` · `SignatureCreationTime`)가 찍힌 뒤 `checksum`
단계로 갔고 `gpg`를 찾는 줄은 0이다(실측 5). 검증은 꺼지지 않은 채로 돈다.

### 확인 3 — node LTS는 v26이다

nodejs.org `index.json`의 첫 LTS는 v26.13.0(2026-11-03)이고 `linux-x64` 판이 있다. M0 Task 0이 컨테이너에서 그 tarball(62,893,692
바이트)을 읽었다. `bin/node` 150,319,296바이트, `NEEDED`는 여덟 — `libatomic.so.1` · `libdl.so.2` · `libm.so.6` · `libstdc++.so.6` ·
`libgcc_s.so.1` · `libpthread.so.0` · `libc.so.6` · `ld-linux-x86-64.so.2`. 요구는 `GLIBC_2.28` · `GLIBCXX_3.4.21` · `CXXABI_1.3.11`이고
게스트는 2.41 · 6.0.33이다. `libatomic`은 BT 때 `bluetoothd`가 데려왔고(`guest_tools.sh`의 BT 블록), `libdl`은 PM 결정 7이 실었다.

### 확인 4 — mise의 파일은 전부 홈에 놓인다

바이너리 `~/.local/bin/mise`, 런타임 `~/.local/share/mise/installs/`, 받은 파일 `~/.cache/mise`, 전역 설정
`~/.config/mise/config.toml`. `/home`은 ext4(HP)라 RAM이 아니다. 받는 중의 임시 자리가 tmpfs `/tmp`인지는 M0가 본다(PM 위험 4와 같은
자리).

M0가 닫았다: `mise use`(node)는 `~/.cache/mise`에 받고 `/tmp`를 안 쓴다. 그러나 `mise.run`은 `mktemp -d`로 `/tmp`에 tarball과 푼
바이너리를 함께 둔다 — 약 230MB가 잠깐 RAM에 놓인다(위험 3, 실측 6).

또 하나: 콘솔 셸(init의 환경)에는 `XDG_DATA_HOME=/config/xdg`가 있고 화면 셸에는 없다(terminal의 `buildAccount`가 뺀다, HP). mise는
이 변수를 따르므로 콘솔에서 `setpriv`로 사용자가 되면 `/config/xdg/mise`에 깔려다 Permission denied로 멈춘다(M0 첫 판). 사용자의
길(화면 셸)에는 없는 막힘이라 체인의 `as_tars`가 이 변수를 뺀다.

## 결정

### 결정 1 — mise도 node도 기본 이미지에 싣지 않는다. TARS의 일은 막히는 자리를 푸는 것이다

PM 결정 3과 같은 기준이다. 막히는 자리가 나오면 기본 이미지에 무엇을 더할지 하나씩 판정하고, initrd 크기와 새 `.so`를 잰다.
`mise.run`이 이미 다 있다면(확인 1) 이 서브프로젝트의 코드 변경은 게이트와 시스템 rc(M1)뿐일 수 있다 — 그것도 결과다.

M0의 결과가 그랬다. 기본 이미지에 더한 것은 0이다 — PM-M0의 도구 · glibc 통째로 · libstdc++의 이름과 BT의 `libatomic`이 이미
mise와 node의 길을 덮고 있었다.

### 결정 2 — 게이트는 스물일곱째 체인 `mise/check.sh`이고 실제 망을 쓴다

모양은 `pm/check.sh`의 것이다. 새 디스크에 `tars-install --yes`를 하고 설치된 디스크로 SLIRP 망과 `net=dhcp`로 다시 부팅한다.
시리얼 root 셸에서 `setpriv`로 사용자 `tars`가 되어 다음을 친다.

1. `curl https://mise.run | sh` — 받은 스크립트의 sha256과 줄 수를 로그에 남긴다(PM 결정 6과 같은 이유).
2. `~/.local/bin/mise --version`
3. `~/.local/bin/mise use -g node@lts`
4. `~/.local/bin/mise exec -- node --version`과 `node -e` 한 줄(실제로 V8이 돈다)
5. `~/.local/bin/mise doctor` — 판정하지 않고 적는다.

- 바깥 망이 없는 것과 우리 코드가 틀린 것을 섞지 않는다. QEMU를 띄우기 전에 컨테이너에서 `https://mise.run` ·
  `https://mise.jdx.dev` · `https://github.com` · `https://nodejs.org`를 한 번 친다. 실패하면 `mise: external network unavailable`로
  빨개진다(PM과 같이 초록으로 건너뛰지 않는다).
- sudo는 쓰지 않는다. mise는 홈에만 쓰므로 PM 체인의 `sudo -k` · `sudo -S -v` 단계가 없다.
- `-cpu max` · `-m 1024`는 PM 체인에서 그대로 가져온다. 더 작은 값으로 되는지는 M0가 본다(위험 3).
  M0가 정했다: `-cpu`는 다른 체인과 같은 qemu64다(위험 4). `-m`은 1024 그대로다(위험 3).
- `CHAINS`에 넣는다. 라벨은 `MI-M0`. M0의 부팅은 포트를 안 쓴다. M1이 화면 부팅을 더하면 monitor는 45500부터(RP-M0 예약 범위,
  PM이 45499까지 썼다).

### 결정 3 — activate는 M1이 정한다(사용자 결정 4)

후보는 셋이다.

- 시스템 rc가 `mise activate <shell>`을 부른다. PM 결정 5의 `brew shellenv`와 같은 자리(`/etc/bash.bashrc` · `/etc/zsh/zshrc` ·
  `/etc/fish/conf.d/`)이고, 디렉터리마다 다른 버전이 된다. 프롬프트마다 `mise hook-env`가 176MB 바이너리를 띄운다.
- 시스템 rc가 shims 디렉터리(`~/.local/share/mise/shims`)만 PATH에 둔다. 프롬프트 비용은 0이고, 대신 `node`를 칠 때마다
  mise를 한 번 거친다. 디렉터리별 환경 변수(`[env]`)는 shims로는 덜 된다.
- TARS는 rc를 안 건드리고 `mise.run`의 안내대로 사용자가 넣는다.

시스템 rc가 다루는 경로는 사용자마다 다르다(`$HOME/.local/bin/mise`) — brew의 고정 prefix와 다른 점이다. M0는 판정에 쓸 숫자 —
`mise hook-env`의 시간, shim으로 부른 `node --version`의 시간, 직접 부른 시간 — 를 잰다.

사용자가 골랐다(2026-11-03, M0 실측 8을 보고): 첫째 후보 — 시스템 rc가 `$HOME/.local/bin/mise`가 있을 때만 `mise activate <셸>`을
부른다. PM 결정 5와 같은 원칙(설치 직후 새 패널부터)이고, 프로젝트별 `mise.toml`이 `[env]`까지 온전히 된다. activate는 mise의
디렉터리(`~/.local/bin`)도 PATH에 넣으므로(`src/cli/activate.rs`) 한 줄이 `mise`와 `node`를 함께 세운다. 실측 9의 `failed to load
settings`는 `mise doctor`가 자식으로 `mise`를 이름으로 부르는데 PATH에 없어서였다 — 이 결정이 함께 닫는다.

## 위험

### 위험 1 — 루트 게이트가 바깥 망에 하나 더 기댄다

PM 위험 1에 mise.jdx.dev · nodejs.org가 더해진다. 사전 확인이 이름을 붙인다. mise.run의 내장 버전과 node LTS는 날마다 움직이므로
로그에 `mise --version` · `node --version` · `mise.run` sha256을 남겨 빨개진 회차가 저쪽 변화인지 가른다. 바깥 체인 둘이 자주
빨개지면 PM 위험 1의 다음 후보(`CHAINS` 밖 별도 명령)를 둘에 함께 묻는다.

### 위험 2 — 바깥 바이너리가 initrd에 없는 것을 부른다

PM의 portable-ruby가 `libdl`로, brew가 libstdc++의 이름으로 막혔던 것과 같은 종류다. 후보는 node의 `NEEDED`, mise의 gpg 검증
(확인 2), mise가 런타임을 풀 때 부를 수 있는 바깥 명령(`xz` · `unzip` 등)이다. 막히면 결정 1의 기준으로 판정한다. gpg 명령이
필요하다면 그것을 initrd에 실을지, `node.gpg_verify=false`를 시스템 설정으로 둘지는 사용자에게 묻는다(검증을 끄는 일이라서).

### 위험 3 — TCG에서의 시간과 메모리

mise 바이너리 176MB를 디스크에서 처음 띄우는 시간, node 약 30MB를 받아 약 190MB로 푸는 시간, V8을 TCG에서 띄우는 시간을 M0가
잰다. node는 V8이 큰 가상 공간을 잡지만 RSS는 작을 것으로 본다. 512MB로 되는지도 한 번 본다 — 되면 체인의 메모리를 줄인다.

M0가 잰 것: 시간은 TCG에서 `mise.run` 19초 · `mise use -g node@lts` 19.5초(tarball 62.9MB, 풀린 자리 234,732kB)로 작다(실측 1 · 3).
512MB에서는 안 된다 — 막힌 자리는 node가 아니라 `mise.run`의 `/tmp`다(실측 6). 1GiB는 PM과 같은 요구라 고치지 않고 적는다
(`carryover.md`의 MI 절).

### 위험 4 — `-cpu`

qemu64에 없는 명령어(SSSE3 · SSE4.x · AVX)를 mise나 node가 요구할 수 있다. PM 결정 6처럼 `-cpu max`로 시작하고, 기본 모델에서
어떻게 멈추는지는 한 판만 본다(실기에는 해당 없음 — 기록용).

M0가 닫았다: qemu64에서 끝까지 초록이다(실측 7). Homebrew와 달리 이 길에는 CPU 요구가 없다.

## 비목표

1. `brew install mise`(사용자 결정 2). Homebrew 위의 mise는 brew가 shellenv로 PATH를 주므로 따로 막힐 자리가 적다고 본다.
2. node 외 런타임의 보증(python · go · ruby · java 등). 게이트는 node 하나로 길을 본다. 다른 런타임은 사용자가 실기에서 처음 친다.
3. 소스에서 런타임을 빌드하는 길(`node.compile`, python의 소스 빌드 등). PM 결정 4와 같이 컴파일러는 없다.
4. mise를 이미지나 `tars-install`에 미리 싣는 것(사용자 결정 1).
5. 프로젝트별 `mise.toml`의 `[env]` · `[tasks]` 같은 기능의 동작 보증.

## Milestone

- MI-M0: 체인 `mise/check.sh` 첫 판. `mise.run` → `mise use -g node@lts` → `node`가 도는 것까지 막히는 자리를 실측하고 푼다.
  위험 2 · 3 · 4의 숫자와 결정 3이 쓸 시간 셋을 잰다.
- MI-M1: 결정 3(activate)을 정해 넣는다. 재부팅 뒤 망 없이 뜬 화면 셸에서 `node`가 이름만으로 불리는지 본다.

M1의 plan은 M0의 실측을 본 뒤에 쓴다.

## 실측 (M0, 2026-11-03)

`mise.run` sha256 `61cb4d61…0d32cd2202a414`(482줄), 설치된 mise는 `2026.10.25 linux-x64 (2026-10-31)`, node v26.13.0 · npm 11.20.0.
값은 체인 둘째 판(첫 초록, `-cpu max -m 1024`)의 것이고 측정 11의 두 판을 따로 적는다.

### 실측 1 — `mise.run` 18.9초, `.tar.gz`, mise.jdx.dev에서(확인 1)

`mise-v2026.10.25-linux-x64.tar.gz`(`zstd`가 없어 `.tar.zst`가 아니다). GitHub으로 내려간 줄 0. `~/.local/bin/mise` 172,220kB.

### 실측 2 — `mise --version` 처음 1,140ms, 두 번째 48ms(결정 3)

첫 판(1,150 · 50)과 같다. 디스크에서 172MB를 처음 읽는 비용이 약 1.1초이고, 페이지 캐시에 오른 뒤에는 수십 ms다.

### 실측 3 — `mise use -g node@lts` 19.5초, `/home` 17%(위험 3)

`~/.local/share/mise` 234,732kB, `~/.cache/mise` 61,516kB(받은 tarball이 남는다), 최소 디스크의 `/home` 3,021,608kB 가운데 469,368kB.
mise 스스로 `node -v` · `npm -v`를 돌려 확인한다(`[3/3]`).

### 실측 4 — node의 `ldd`에 `not found` 0, `node -p` 505ms(위험 2)

여덟이 전부 `/lib/x86_64-linux-gnu`에서 풀린다(확인 3). `mise exec -- node -p`가 V8 버전과 `42`를 찍는다.

### 실측 5 — gpg 검증은 mise 안에서 끝난다(확인 2, 위험 2)

`MISE_DEBUG=1`의 `mise use`에 서명 패킷 덤프가 찍히고(측정 11 qemu64 판에서 그 줄 625개) `checksum` 단계로 간다. `gpg`를 찾는 줄 0.

### 실측 6 — 512MB에서 `mise.run`이 기계를 굳힌다, 1GiB의 최소 MemAvailable 391,904kB(위험 3)

`MI_MEM=512` 판은 `validating checksum` 뒤 MemAvailable이 2,236kB에 붙어 600초 상한에 걸렸다. `mise.run`이 `mktemp -d`(tmpfs `/tmp`)에
tarball 약 60MB와 푼 `mise` 172MB를 함께 두고, RAM에 풀린 initrd 약 280MB(PM 실측 4)와 합쳐 512MB를 넘는다. tmpfs는 swap 없이는
내쫓을 수 없다. 1GiB의 최솟값 391,904kB도 이 순간이다. 끝난 뒤 `/tmp`는 452kB — 스크립트가 지운다. OOM 0.

### 실측 7 — qemu64에서 끝까지 초록(위험 4)

`MI_CPU=qemu64` 판: `mise.run` 48.7초(받기 시간의 흔들림), `--version` 1,160 · 45ms, `mise use` 23.8초, `node -p` 322ms, 체인 116초.
체인의 기본값을 qemu64로 바꿨다.

### 실측 8 — activate 후보의 시간(결정 3)

| | max 판 | qemu64 판 |
|---|---|---|
| `mise hook-env -s bash`(activate가 프롬프트마다) | 87ms | 71ms |
| shim으로 `node --version` | 114ms | 81ms |
| 경로로 `node --version` | 33ms | 27ms |

shim이 더하는 것은 50~80ms다. 모두 페이지 캐시가 따뜻한 뒤의 값이고, 부팅 뒤 처음 한 번은 실측 2의 1.1초가 더해진다.

### 실측 9 — `mise doctor` rc 1, 문제 둘

1. `mise is not activated` — M1의 일이다. mise는 비대화형에는 shims를 권한다고 덧붙인다.
2. `failed to load settings: No such file or directory (os error 2)` — 어느 파일인지 말하지 않는다. node 설치 · 실행은 막지 않는다. M1이
   activate와 함께 본다.

### 실측 10 — 체인 88초(빌드 뒤), 루트 게이트 27/27 15분 0초(위험 1)

루트 게이트에서 MI-M0은 86초로 열째다(가장 긴 것은 PM-M0 236초). prebuild 329초 · lanes 569초(PM-M1 회차 481초), cut log lines
전부 0. 기본 이미지가 안 바뀌어 prebuild는 PM-M1 회차(323초)와 같다.

### M0의 판들이 가르친 것

1. 콘솔 셸과 화면 셸은 환경이 다르다 — `XDG_DATA_HOME`. XDG를 따르는 프로그램을 콘솔에서 `setpriv`로 사용자로 돌리는 체인은
   이 변수를 빼야 사용자의 길과 같다(첫 판, 확인 4).
2. 설치 스크립트는 `mktemp`로 tmpfs `/tmp`를 쓴다. TARS에서는 그것이 RAM이라, 큰 바이너리를 받는 스크립트의 메모리 요구는 받는
   크기 + 푼 크기다(실측 6).
3. 바깥 바이너리의 `NEEDED`는 컨테이너에서 tarball을 받아 `readelf -d`로 미리 읽으면 체인 한 판을 아낀다(Task 0).
