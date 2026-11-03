# MI-M0 — `mise.run` → `mise use -g node@lts` → `node`가 TARS에서 돈다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-03
> `70fac71` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 2의 체인 스물일곱째 `mise/check.sh` 첫 판을 세운다. 끝나면 설치된 디스크로 뜬 TARS에서 사용자 `tars`가 공식
`mise.run`으로 `~/.local/bin/mise`를 깔고, `mise use -g node@lts`가 node를 받으며, `mise exec -- node`가 JavaScript 한 줄을 돌린다.
위험 2 · 3 · 4의 숫자와 결정 3(activate)이 쓸 시간 셋이 design "실측 (M0)"에 남는다. activate와 재부팅 뒤 화면 셸은 M1이다.

Architecture: 처음 판은 체인만 더한다. design 확인 1에 따르면 `mise.run`이 부르는 것은 PM-M0 뒤로 다 있으므로 기본 이미지는 안
바뀔 수 있다. 막히는 자리가 나오면 그때 PM 결정 3의 기준(한 개씩 더하고 initrd 크기와 새 `.so`를 잰다)으로 `guest_tools.sh` ·
`make_initrd.sh`에 더하고 이 plan의 Task 3에 적는다. 우리 Zig 코드는 안 바뀐다.

## 착수 전에 확인한 것 (2026-11-03)

- `mise.run`(482줄, 내장 v2026.10.25)이 부르는 것: `uname` · `ldd /bin/ls` · `tar --version` · `command -v zstd` · `curl` ·
  `sha256sum -c` · `mktemp -d` · `tar --no-same-owner -xf` · `mv` · `chmod`. 게스트에 `zstd`만 없고, 그때 `.tar.gz`로 간다.
- 받는 자리: `mise.jdx.dev`가 먼저, 실패하면 `github.com`의 Releases.
- mise는 node를 nodejs.org에서 `node-v{v}-linux-x64.tar.gz`로 받고 `SHASUMS256.txt`로 본다. `node.gpg_verify`가 `false`가 아니면
  `.sig`로 gpg 검증을 한다 — 바깥 `gpg`를 부르는지 모른다(design 확인 2). 게스트에 `gpg`는 없다.
- node LTS는 v26.13.0이다.
- `pm/check.sh`의 부팅 1(ISO로 `tars-install --yes`) · 부팅 2(SLIRP · `net=dhcp`) · `as_tars` · `wait_log` · `fail`을 그대로 가져온다.
  sudo 단계는 없다(mise는 홈에만 쓴다).
- check.sh의 진입 검사가 `| grep -q`를 글자로 거른다(PM M1 교훈 2) — 판정은 `grep -aq … "$LOG"` 꼴로 쓰고, 둘을 함께 볼 때는
  `if ! { A && B; }`로 쓴다.

## 무엇을 재나 (design "실측 (M0)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `mise.run` 전체 시간, 받은 형식(`.tar.gz` · `.tar.zst`), 받은 곳(jdx.dev · GitHub), `~/.local/bin/mise` 바이트 | 확인 1, 위험 3 |
| 2 | `mise --version` 첫 실행(디스크에서 176MB를 처음 띄움)과 둘째 실행의 시간 | 위험 3, 결정 3 |
| 3 | `mise use -g node@lts` 시간, 설치된 node 버전, `du` — `~/.local/share/mise` · `~/.cache/mise`, `df /home` | 위험 3 |
| 4 | node의 `ldd` 출력(빠진 `.so`가 `not found`로 보인다), `node -e` 한 줄의 시간 | 위험 2 · 3 |
| 5 | gpg — `MISE_DEBUG=1`로 돌린 `mise use`의 로그에서 gpg에 관한 줄, `gpg` 명령을 찾다 실패한 줄 | 확인 2, 위험 2 |
| 6 | 설치 내내 5초마다 본 `MemAvailable`의 최솟값, OOM이 있었나 | 위험 3 |
| 7 | `mise use` 중 `/tmp`(tmpfs)에 남은 것 — 끝난 뒤 `du -s /tmp`, 도는 중의 최댓값은 측정 6의 표본에 함께 | 확인 4 |
| 8 | 결정 3의 셋: `mise hook-env -s bash`의 시간, shim으로 부른 `node --version`(`mise reshim` 뒤), 설치 자리를 직접 부른 시간 | 결정 3 |
| 9 | `mise doctor`의 출력(판정하지 않는다) | 결정 2 |
| 10 | 체인 전체 시간과 루트 게이트 전체 시간의 변화 | 위험 1 · 3 |
| 11 | 한 번만: `-m 512`로 도나, `-cpu` 기본(qemu64)에서 어디서 멈추나. 체인을 `MI_MEM` · `MI_CPU` 환경 변수로 돌린다 | 위험 3 · 4 |

## Task 0: 기준값

- 루트 게이트를 다시 돌리지 않는다 — PM-M1의 마지막 회차(26/26, 13분 24초)가 기준이다. 체인 하나만 돌릴 때는 `mise/check.sh`를
  컨테이너에서 직접 부른다(`docs/guides/lessons.md`의 체인 하나 돌리기).
- 컨테이너에서 node 판 tarball을 한 번 받아 `readelf -d` · `objdump -T`로 `NEEDED`와 가장 높은 `GLIBC_` · `GLIBCXX_` 버전을 읽어
  둔다. 측정 4의 기대값이다(게스트는 glibc 2.41 · libstdc++ 6.0.33).

## Task 1: 체인 스물일곱째 `mise/check.sh`

`pm/check.sh`를 바탕으로 하되 PM에만 있는 것(P1 usrmerge · P2 도구 · sudo · brew 전부 · 부팅 3 · monitor)은 뺀다. 머리 주석에
체인이 무엇을 보는지와 PM과 다른 점을 적는다.

- 사전 확인: 컨테이너에서 `https://mise.run` · `https://mise.jdx.dev` · `https://github.com` · `https://nodejs.org`를 `curl -fsS`로
  친다. 실패하면 `FAIL: mise: external network unavailable (<url>)`. `mise.run`을 받아 sha256과 줄 수를 찍는다.
- 디스크: 최소 크기(`truncate -s 4098M`). node와 mise가 `/home`에 든다(측정 3이 확인).
- QEMU: `-cpu "${MI_CPU:-max}"` · `-m "${MI_MEM:-1024}"`(측정 11). 기본값이 PM과 같은 이유를 주석에 적는다.
- `as_tars`: PM의 것에서 `HOMEBREW_NO_ANALYTICS`를 빼고 `PATH=/usr/bin:/bin`. mise의 텔레메트리 · 갱신 확인을 끄는 환경 변수가
  있으면 이유와 함께 하나만 더한다(사용자의 길과 다른 변수는 적을수록 좋다).
- `fail`의 꼬리 패턴: `mise`, `mise ERROR`, `curl:`, `Error`, `not found`.
- 판정(접두사 `mi-`):
  - M1 — `mise.run`: `curl -fsSL -o /tmp/mi-install.sh https://mise.run && sh /tmp/mi-install.sh; echo mi-install-rc-$?`.
    rc 0과 `mise: installed successfully to /home/tars/.local/bin/mise`. 측정 1.
  - M2 — `~/.local/bin/mise --version`이 `2026.` 꼴로 답한다. 두 번 쳐서 측정 2.
  - M3 — `mise use -g node@lts`(`MISE_DEBUG=1`로, 출력은 `mi-use:` 접두사). rc 0, `~/.config/mise/config.toml`에 `node`. 측정 3 · 5 · 7.
  - M4 — `ldd "$(mise which node)"`에 `not found`가 없다. `mise exec -- node --version`이 `v26.` 꼴, `mise exec -- node -e` 로
    `process.versions.v8`과 계산 한 줄을 찍는다. 측정 4.
  - M5 — 결정 3의 셋(측정 8). 이 판정은 시간이 숫자로 나오는지만 본다. 값의 판정은 M1의 일이다.
  - 그 뒤 `mise doctor`(측정 9), `du` · `df`, MemAvailable 최솟값, `dmesg`의 `Out of memory`(있으면 빨강).
- 마지막 줄에 체인 시간(측정 10)을 찍는다.

## Task 2: `check.sh`의 `CHAINS`

마지막에 `MI-M0:./mise/check.sh`를 더한다. 바깥 망 체인 둘(PM · MI)이 루트 게이트에 들어간다(design 위험 1). 1GiB QEMU이므로
lanes의 JOBS 계산에 들어간다 — PM과 같다.

## Task 3: 체인을 돌려 막히는 자리를 푼다

체인을 컨테이너에서 하나만 돌린다(한 판 약 3~5분 예상). 빨개지면 그 판의 로그에서 원인을 읽고, 고친 것과 판 번호를 design
"M0의 판들이 가르친 것"에 적는다. 예상되는 자리와 처리:

- node의 `.so`가 없다 → `make_initrd.sh`에 더한다(PM 결정 7 · 10의 방식). 결정 1의 기준으로 크기를 잰다.
- gpg 명령이 필요하다 → 멈추고 사용자에게 묻는다(design 위험 2 — 검증을 끄는 일이라서).
- `/tmp`가 모자라거나 OOM → 측정 6 · 7의 숫자와 함께 design 위험 3에 적고, 체인의 `-m`을 정한다.
- qemu64에서 멈추는 자리(측정 11)는 고치지 않고 기록만 한다.

## Task 4: 실측 · 문서 · 게이트 · 커밋

- design에 "실측 (M0)"과 "M0의 판들이 가르친 것"을 쓴다. 기본 이미지가 바뀌었다면 결정 1에 덧붙인다.
- `make quick`(shellcheck note까지)을 먼저 돈다(PM M1 교훈 3).
- 루트 게이트(`./check.sh`). 지금 약 13분 24초에 이 체인이 더해진다 — 돌리기 전에 사용자에게 시간을 알린다.
- 커밋 대상: `mise/check.sh` · `check.sh` · design · 이 plan, 그리고 Task 3이 고친 파일. `git status`로 산출물이 없는지 본 뒤 좁혀서
  add한다.

## 시간

체인 한 판 3~5분(mise 받기 · node 받기 · TCG의 V8), 막히는 자리 하나마다 한 판. 루트 게이트 약 15분.
