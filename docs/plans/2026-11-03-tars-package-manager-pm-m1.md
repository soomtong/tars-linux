# PM-M1 — bottle 하나: `brew install hello` · 시스템 rc의 shellenv · 재부팅 뒤 화면 셸의 `hello`

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-03
> `4b2e677` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design의 PM-M1을 닫는다. 끝나면 (1) 사용자 `tars`가 `brew install hello`로 bottle을 붓고 `hello`가 `Hello, world!`를
낸다, (2) 결정 5의 시스템 rc 셋(bash · zsh · fish)이 `brew`가 있을 때만 shellenv를 부르고 없을 때는 아무것도 안 한다, (3) 재부팅
뒤 망 없이 뜬 화면 셸(fish, uid 1000)에 `hello`를 치면 화면에 `Hello, world!`가 나온다 — 사용자가 rc를 한 줄도 안 고친 채로.
`brew doctor`의 출력은 판정 없이 design "실측 (M1)"에 적는다(위험 6).

Architecture: 바꾸는 층은 둘이다. initrd의 `/etc`에 시스템 rc 파일 셋(`kernel/make_initrd.sh`), 체인 `pm/check.sh`의 둘째 판.
우리 Zig 코드는 안 바뀐다. 체인은 부팅이 셋이 된다 — 셋째 부팅이 화면에 키를 치므로 이 체인이 처음으로 monitor 포트 45499를 쓴다.

## 착수 전에 확인한 것 (2026-11-03)

- 세 셸이 컴파일 때 정해 둔 시스템 rc(sysroot의 바이너리 `strings`와 `__fish_build_paths.fish`):
  - bash `/etc/bash.bashrc` — Debian 패치. 대화형 non-login 셸이 `~/.bashrc`보다 먼저 읽는다.
  - zsh `/etc/zsh/zshrc` — 대화형 셸이 `~/.zshrc`보다 먼저 읽는다.
  - fish `/etc/fish/conf.d/*.fish`(sysconfdir) — 그리고 `/usr/share/fish/vendor_conf.d`. 둘 다 사용자 `config.fish`보다 먼저다.
  - initrd에는 셋 다 아직 없다(`rg 'WORKDIR/etc' kernel/make_initrd.sh`).
- 화면 셸은 rc를 읽는다 — `shell_config`의 기본값이 `.on`이다(`init/src/config.zig`). `off`면 `--no-config` · `--norc` · `-f`가
  시스템 rc까지 건너뛴다. 그것은 사용자가 고른 것이라 그대로 둔다.
- `brew shellenv`(Homebrew/brew HEAD `Library/Homebrew/cmd/shellenv.sh`, 71줄):
  - 셸 이름을 첫 인자로 받는다. 없으면 `/bin/ps -p $PPID`로 짐작하고, 그것도 안 되면 `$SHELL`을 본다 — 시스템 rc는 짐작에 기대지
    않고 이름을 준다.
  - `HOMEBREW_PATH`(brew가 받은 PATH)가 `prefix/bin:prefix/sbin:`로 시작하면 아무것도 안 내고 돌아간다. 그래서 시스템 rc가 먼저
    eval한 셸에서 사용자가 안내대로 `~/.bashrc`에 같은 줄을 넣어도 둘째 eval은 빈 출력이다(결정 5가 "M1이 확인한다"고 남긴 자리).
    fish 갈래는 `fish_add_path --move`라 어차피 겹치지 않는다.
  - `brew.sh`가 `shellenv`를 81줄에서 끝내고 root 판정(`check-run-command-as-root`, 612줄)은 그 뒤다 — root 셸에서도 조용히 돈다.
  - ruby를 안 띄운다(bash만). 그래도 셸을 열 때마다 `bin/brew` → `brew.sh` 앞부분이 도는 비용이 있다 — 측정 3.
- `hello` 2.12.3: 의존 0, `x86_64_linux` bottle이 있다(`formulae.brew.sh/api/formula/hello.json`).
- `tars-install`의 최소 디스크는 `MIN_DISK_BYTES = 4 GiB + 2 MiB`(`init/src/disk.zig`). 실측 5의 약 270MB가 그 디스크의 `/home`에
  들어가는지를 체인이 직접 보도록 디스크를 그 크기로 줄인다.
- 화면에 키를 치는 길은 이미 있다 — `gate_lib.sh`의 `type_keys`(monitor `sendkey`)와 `wait_for_screen`(terminal의 `screen>` 줄).
  monitor를 붙이는 모양은 `keyboard/check.sh`(`-monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait`, `exec 3<>/dev/tcp/…`)다.
  `type_keys`는 fd 3에 쓰므로, 이 체인의 시리얼 FIFO가 쓰는 fd 4와 안 겹친다.

## 정할 것 하나 (plan에서 고른 안 — 뒤집으려면 이 절)

시스템 rc의 조건은 "`brew`가 실행 가능하면"뿐이고 uid를 보지 않는다. 그래서 시리얼 콘솔 · ssh의 root 셸에도 prefix가 PATH에
든다. root가 `hello`처럼 부은 프로그램을 쓰는 것은 되고, root가 `brew install`을 치면 brew 스스로 `Running Homebrew as root is
extremely dangerous`로 거절한다 — TARS가 막을 몫이 아니다. 다른 안(uid 0이면 건너뛰기)은 root가 부은 도구를 못 쓰게 하면서
얻는 것이 없다.

## 무엇을 재나 (design "실측 (M1)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `brew install hello` 전체 시간(TCG), `Pouring hello--2.12.3` 줄이 있나(bottle이었나), 자동 갱신(`Auto-updated`)이 돌았나 | 위험 2, 결정 4 |
| 2 | `brew install` 중 `file`이 없다는 줄(M0 측정 7과 같은 grep) | 결정 3의 `file` 판정, 실측 7 |
| 3 | `brew shellenv bash` 한 번의 시간(셸을 열 때마다 더해지는 값) | 결정 5 |
| 4 | `brew doctor`의 rc와 `Warning:` 제목 줄 전부 | 위험 6 |
| 5 | 4 GiB + 2 MiB 디스크에서 설치 뒤 `df /home` | 실측 5 |
| 6 | 체인 전체 시간과 루트 게이트 전체 시간의 변화 | 위험 2 |

## Task 1: `make_initrd.sh` — 시스템 rc 셋(결정 5)

`/etc/os-release` 블록 근처(셸이 아니라 "TARS가 시스템으로서 주는 파일" 무리)에 한 블록. 머리 주석에 PM design 결정 5와 위의
"착수 전" 사실(자리 셋, 이름을 인자로 주는 이유, 두 번 eval이 빈 출력인 이유, 아무것도 안 찍는 규칙)을 적는다.

```
/etc/bash.bashrc
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
  fi

/etc/zsh/zshrc
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
  fi

/etc/fish/conf.d/homebrew.fish
  if test -x /home/linuxbrew/.linuxbrew/bin/brew
      /home/linuxbrew/.linuxbrew/bin/brew shellenv fish | source
  end
```

- `[ -x ] && eval …` 한 줄이 아니라 `if`인 이유: brew가 없을 때 `&&` 꼴은 rc의 마지막 상태를 1로 남긴다. 그 1이 첫 프롬프트의
  `$?`(fish는 `$status`)로 보여 프롬프트가 실패 표시를 그릴 수 있다 — 다른 체인의 화면 좌표 · 글자가 바뀐다.
- 셋 다 `0644`, 주인 root. 파일 하나에 한 줄 주석(이 파일이 무엇이고 어디서 왔나 — `make_initrd.sh`, 부팅마다 initrd에서 온다).
- `vendor_conf.d`가 아니라 `/etc/fish/conf.d`인 이유: vendor 자리는 패키지(fzf 등)가 쓰는 곳이고, 이 줄은 배포판(TARS)이 시스템으로서
  두는 것이라 bash · zsh와 같은 `/etc` 층에 둔다.
- 끝나면 `rg -n 'linuxbrew' kernel/make_initrd.sh`로 경로 글자가 셋 다 같은지 본다.

이 파일들은 brew가 없는 모든 체인에서 `-x` 검사 하나만 한다. 그래도 rc를 읽는 셸이 뜨는 체인이 많으므로 Task 4의 루트 게이트가
"아무것도 바뀌지 않았다"의 근거다.

## Task 2: `pm/check.sh` 둘째 판

머리 주석의 부팅 표를 셋으로 고치고 "PM-M1이 더한 것"을 적는다. M0의 P1~P6은 그대로 둔다(같은 부팅 안에서 몇 초다).

디스크: `truncate -s 4098M`(= `MIN_DISK_BYTES`). 8GiB 주석을 "최소 디스크에서 Homebrew와 bottle이 들어가는가(실측 5)"로 바꾼다.

### 부팅 2에 더한다 (P6 뒤, 측정 줄 앞)

- P7 bottle: `as_tars`로 `${PREFIX}/bin/brew install hello 2>&1 | sed "s/^/pm-inst: /"; echo "pm-p7-rc-${PIPESTATUS[0]}"`.
  한도 900초. rc 0, `pm-inst: .*Pouring hello--` 줄이 있어야 초록(bottle이 아니면 결정 4를 벗어난 것이므로 빨강).
  그 다음 `${PREFIX}/bin/hello | sed "s/^/pm-p7-hello=/"` → `pm-p7-hello=Hello, world!`.
- P8 시스템 rc: 셋 다 `as_tars`로 대화형 셸을 띄워 `brew`를 찾는다. 판정 글자는 에코와 겹치지 않게 sed 접두사 뒤의 값이다.
  - `bash -i -c "command -v brew" 2>&1 | sed "s/^/pm-p8-bash=/"` → `pm-p8-bash=/home/linuxbrew/.linuxbrew/bin/brew`
  - `zsh -i -c "command -v brew" 2>&1 | sed "s/^/pm-p8-zsh=/"` → 같은 경로
  - `fish -i -c "command -v brew" 2>&1 | sed "s/^/pm-p8-fish=/"` → 같은 경로
  - `as_tars`의 인자는 작은따옴표를 못 담으므로(콘솔 fish 규칙) 안쪽은 큰따옴표다. `bash -i`는 tty가 없으면 job control 경고를
    낼 수 있다 — 그 줄은 `2>&1`로 같이 접두사가 붙어 판정을 안 흔든다(판정은 경로 줄 하나를 찾는다).
- P9 두 번 eval: `bash -i -c "eval \"\$(${PREFIX}/bin/brew shellenv bash)\"; echo \"\$PATH\" | tr : \"\\n\" | grep -c linuxbrew/bin"`에
  접두사 `pm-p9-count=` → `pm-p9-count=1`. 따옴표가 세 겹이라 가장 깨지기 쉬운 줄이다 — 구현자는 이 한 줄만 먼저 게스트 없이
  호스트 bash에서 `as_tars`가 만드는 글자를 `printf`로 찍어 확인한다.
- 측정 2: M0 측정 7의 grep을 `pm-inst:` 줄에 다시 쓴다.
- 측정 3: `bash -c "TIMEFORMAT=%R; time ${PREFIX}/bin/brew shellenv bash >/dev/null" 2>&1 | sed "s/^/pm-m3-shellenv=/"`.
- 측정 4: `${PREFIX}/bin/brew doctor 2>&1 | sed "s/^/pm-doc: /"; echo "pm-doc-rc-${PIPESTATUS[0]}"`(한도 300초). 판정 안 한다 — rc와
  `pm-doc: Warning:` 줄을 체인 출력에 그대로 낸다.
- 측정 5: M0의 `pm-m5-` 줄을 그대로 쓴다(디스크만 작아졌다).

### 부팅 3 — NVMe만, NIC 없음, monitor 45499

```
=== boot 3: the NVMe again, no network, typing on the screen ===
```

- `boot_guest 3 -monitor tcp:127.0.0.1:45499,server,nowait` 꼴. `boot_guest`가 이미 `-monitor none`을 붙이므로, 인자로 monitor를 줄 수
  있게 고친다(`MONITOR` 변수를 두고 기본 `none`). NIC가 없다 — `hello`가 `/home`(디스크)만으로 서는지 본다.
- `exec 3<>/dev/tcp/127.0.0.1/45499`(keyboard 체인처럼 몇 번 재시도), `stop_guest`와 `cleanup`이 fd 3도 닫는다.
- 화면 셸이 tars로 떴는지는 HP 체인의 줄로 본다 — `terminal: spawned child pid N (…) as tars`.
- P10 화면: `type_keys h e l l o ret` 뒤 `wait_for_screen 'Hello, world!'`. 친 글자(`hello`)와 기다리는 글자(출력)가 달라 에코와
  안 겹친다. 판정은 이 하나다 — `hello`가 이름만으로 불렸다는 것이 곧 fish의 시스템 rc가 PATH를 넣었다는 뜻이다. rc가 안
  돌았으면 화면에 `fish: Unknown command: hello`가 나오므로 그 글자를 빨강의 문맥으로 낸다.
- 키 이름은 `keyboard/check.sh`가 쓰는 `sendkey` 이름 그대로(`ret`). 화면 셸이 프롬프트를 그린 뒤에 친다 — 다른 체인이
  기다리는 프롬프트 글자(`tars@`)를 `wait_for_screen`으로 먼저 본다. hostname이 `(none)`이라 프롬프트는 `tars@(none)`이다(실측 6).

## Task 3: 체인 단독 실행

```
docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace tars-devcontainer ./pm/check.sh > <scratchpad>/pm.log 2>&1
```

(`docs/guides/lessons.md`의 "체인 하나"와 같은 줄.)

예상 시간: M0의 199초 + `brew install` · `doctor`(모름 — 측정 1 · 4) + 부팅 하나(약 30초). 5분 안팎으로 본다. 첫 판이 빨개지면 그
판의 FAIL 줄과 문맥을 읽고 고친다 — 판마다 "무엇이 가르쳤나"를 design 실측 끝에 적는다(M0의 모양).

## Task 4: 루트 게이트 · 문서 · 커밋

- 루트 게이트(약 13~15분, initrd가 바뀌므로 prebuild가 다시 돈다). 26/26, cut log lines 0. 시스템 rc를 읽는 셸이 뜨는 체인이
  하나도 안 흔들려야 Task 1의 "아무것도 안 찍는다"가 선다.
- design: `Status:`(PM 끝남), 결정 5에 "M1이 확인한 것"(두 번 eval이 빈 출력, root도 같은 길, 측정 3), "실측 (M1)", 비목표 5의
  `chafa` 줄은 그대로.
- 서브프로젝트를 닫는 묶음(CLAUDE.md "서브프로젝트를 끝내면"): `docs/guides/completed.md` 한 행, `gh-pages`의 `data.js`
  (`site/README.md` 순서), `docs/decisions/project_package_manager.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`.
- HANDOFF의 "사용자가 확인할 것"의 PM 항목: "Next steps" 안내 뒤 사용자 rc에 eval을 넣지 않아도 새 패널에서 `brew`가 되는지로
  고친다.
- 커밋 둘: 이 plan, 그리고 구현(`PM-M1: …`). `git status`로 대상을 좁혀 add한다.

## 하지 않는 것

- `brew` 자체의 자동 갱신 끄기(`HOMEBREW_NO_AUTO_UPDATE`) — 사용자의 길과 같아야 한다. 측정 1이 그것이 돌았는지만 적는다.
- `file`을 넣는 것 — 측정 2가 부르는 줄을 찾을 때만 다시 연다.
- 사용자 rc(seed)에 shellenv를 넣는 것 — 결정 5가 시스템 rc를 고른 이유(이미 설치된 홈에도 갱신만으로 닿는다).
