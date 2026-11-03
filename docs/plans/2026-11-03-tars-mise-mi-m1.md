# MI-M1 — 시스템 rc가 `mise activate`를 부르고, 재부팅 뒤 화면 셸에서 `node`가 이름으로 불린다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-03
> `8b7b1a7` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 3을 후보 A로 닫는다(사용자 결정 2026-11-03). 시스템 rc 셋이 `$HOME/.local/bin/mise`가 있을 때만
`mise activate <셸>`을 부른다. 끝나면 사용자는 `mise.run`과 `mise use -g node@lts` 뒤 rc를 하나도 안 고친 채 새 패널에서 `mise` ·
`node`를 이름으로 부르고, 재부팅 뒤 망 없이 뜬 화면 셸에서도 그렇다. 안내대로 자기 rc에도 넣었을 때 해가 없는지를 체인이 본다.

Architecture: 바꾸는 층은 하나다 — `kernel/make_initrd.sh`가 짓는 시스템 rc 셋(PM-M1의 자리). 체인 `mise/check.sh`는 판정을 더하고
부팅 3(화면, monitor 45500)을 얻는다. 우리 Zig 코드는 안 바뀐다.

## 착수 전에 확인한 것 (2026-11-03, MI-M0 뒤)

- 시스템 rc 셋은 `/etc/bash.bashrc` · `/etc/zsh/zshrc` · `/etc/fish/conf.d/homebrew.fish`이고 `make_initrd.sh`의 PM-M1 블록이 짓는다.
  지금은 brew shellenv만 있다. 이 파일들은 아무것도 찍지 않는다는 규칙이 있다(화면 좌표로 판정하는 체인, `config.zig` rcSeed).
- init이 주는 PATH는 `/usr/bin:/bin`뿐이고 `~/.local/bin`은 어디에도 없다. 그래서 지금은 `mise.run` 뒤 `mise`를 전체 경로로만 친다.
- `mise activate`는 기본이든 `--shims`든 mise 바이너리의 디렉터리를 PATH 앞에 넣는다(`src/cli/activate.rs`의 `prepend_path(exe_dir)`).
  그러므로 activate 한 줄이 `mise`와 `node`를 함께 PATH에 둔다.
- MI-M0 실측 9의 `failed to load settings`는 `mise doctor`가 자식으로 `mise settings`를 이름으로 부르는데(`cmd!("mise", "settings")`)
  PATH에 `mise`가 없어서였다. activate 뒤에는 사라질 것이다 — 체인이 본다.
- `mise.run`의 끝 안내는 전체 경로다 — fish `~/.local/bin/mise activate fish | source`, bash · zsh
  `eval "$(~/.local/bin/mise activate bash)"`. 사용자가 이것도 넣으면 activate가 두 번 돈다.
- MI-M0 실측: `mise --version` 처음 1,140ms · 두 번째 48ms, `hook-env` 71~87ms(TCG).

## 정할 것 하나 — 셸이 뜰 때 바로 PATH가 서는가

activate는 프롬프트 훅(bash `PROMPT_COMMAND` · zsh `precmd` · fish `fish_prompt` 이벤트)으로 `hook-env`를 부른다. 활성화 순간에도 한 번
부르는지는 셸마다 다를 수 있다. 부르지 않으면 `bash -i -c "command -v node"`처럼 프롬프트 없는 대화형 셸에서는 node가 안 보이고
`mise`만 보인다. 사용자의 길(화면의 프롬프트)에는 상관없지만 체인의 판정 모양이 달라진다 — Task 2의 M6이 처음 판에서 보고 판정을
정한다. 화면에서의 판정(M8)은 그것과 무관하게 선다.

## 무엇을 재나 (design "실측 (M1)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | 셸 하나가 뜰 때 시스템 rc의 mise 줄이 더하는 시간 — `mise activate bash`의 시간, 처음과 두 번째 | 결정 3 |
| 2 | 재부팅 뒤 화면 셸의 첫 프롬프트까지(`terminal: spawned child` 줄 → 프롬프트가 화면에 그려진 시각), MI-M0 부팅 2와 비교 | 결정 3, 위험 3 |
| 3 | 두 번 activate한 셸의 PATH에 `.local/bin`과 `installs/node`가 몇 번 있나 | 결정 3 |
| 4 | activate 뒤 `mise doctor`의 rc와 문제 목록 | 실측 9 |

## Task 1: `make_initrd.sh` — 시스템 rc 셋에 mise 줄(결정 3)

PM-M1 블록의 heredoc 셋에 brew 다음으로 더한다. brew 다음인 이유: 둘 다 있으면 mise가 PATH의 앞을 잡아, 프로젝트가 고른 버전이
brew가 부은 같은 이름보다 먼저 불린다(mise의 목적). 모양:

```
# bash (/etc/bash.bashrc). zsh는 같은 꼴에 activate zsh.
if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
fi
```

```
# fish (/etc/fish/conf.d/mise.fish — 새 파일. conf.d는 이름 순이라 homebrew.fish 다음이다)
if test -x "$HOME/.local/bin/mise"
    "$HOME/.local/bin/mise" activate fish | source
end
```

- `$HOME`은 셸이 펼친다 — heredoc 안에서 `\$HOME`으로 쓴다(지금 블록의 `\$(…)`와 같다). 경로가 사용자마다 다르다는 것이 brew의 고정
  prefix와 다른 점이다(design 결정 3).
- `if`인 이유와 아무것도 찍지 않는 규칙은 brew 줄과 같다. activate 자체가 무언가 찍는지는 M8이 화면에서 본다.
- uid를 보지 않는다. root의 홈(`/root`)에 mise가 없으면 조건이 거짓일 뿐이다.
- 머리 주석의 "Homebrew가 있으면"을 "Homebrew · mise가 있으면"으로 고치고, PM-M1 블록 주석에 MI-M1 단락을 더한다(이유 셋: 자리,
  순서, `$HOME`).
- `chmod 0644` 줄에 새 fish 파일을 더한다.

## Task 2: 체인 `mise/check.sh` — 판정 M6~M8과 부팅 3

부팅 2(기존 M1~M5 뒤):

- M6 — 대화형 셸 셋이 rc로 mise를 켠다. `as_tars 'bash -i -c "command -v mise; command -v node"'`, zsh · fish도 같은 꼴(PM P8의 모양).
  `mise`는 `/home/tars/.local/bin/mise`여야 한다. `node`는 위 "정할 것"의 결과로 판정한다 — 보이면 `installs/node/`가 들어간 경로,
  안 보이면 그 사실을 design에 적고 node 판정은 M8(화면)에만 둔다. 측정 1을 함께 잰다.
- M7 — 두 번 activate. `bash -i -c`로 `eval "$(~/.local/bin/mise activate bash)"`를 한 번 더 한 뒤(안내대로 넣은 사용자) PATH의
  `.local/bin` 수와 `installs/node` 수를 센다(측정 3). 1이어야 한다. 둘 이상이면 빨강이고 design에 적은 뒤 사용자에게 묻는다.
- 측정 4 — `bash -i -c "mise doctor"`. 판정은 `failed to load settings`가 없다는 것 하나다(activated 여부는 비대화형에서 흔들릴 수 있다).

부팅 3 — NVMe만, 망 없음, monitor 45500(RP-M0 예약 범위, PM이 45499):

- PM 체인의 부팅 3을 가져온다 — `MONITOR=tcp:…`, `exec 3<>/dev/tcp/…` 재시도, `wait_log_re "terminal: spawned child pid … as tars"`,
  `wait_for_screen 'tars@\(none\) ~>'`. `boot_guest`의 `-monitor none`을 `$MONITOR`로 바꾸고 `stop_guest` · `cleanup`이 fd 3도 닫는다.
- M8 — 화면에 `node --version`을 친다(`type_keys n o d e spc minus minus v e r s i o n ret`). `wait_for_screen 'v26\.'` — 친 글자와
  겹치지 않는다. rc가 안 돌았으면 `fish: Unknown command: node`가 나온다.
- 측정 2 — 첫 프롬프트가 그려질 때까지의 시간. mise가 없는 MI-M0 부팅 2와 같은 방식으로 재서 차를 본다.
- 프롬프트 줄에 mise가 무언가 찍었는지 본다 — 첫 프롬프트 위 줄에 `mise` 글자가 있으면 빨강(rc는 아무것도 안 찍는다는 규칙).

## Task 3: 다른 체인

시스템 rc는 모든 부팅에 들어간다. mise가 없으면 `test -x` 하나라 다른 체인의 화면은 안 바뀐다고 본다 — 루트 게이트가 확인한다.
PM 체인의 P8은 `command -v brew`를 보므로 영향이 없다.

## Task 4: 실측 · 문서 · 게이트 · 커밋

- design: 결정 3에 "M1이 정한 것", "실측 (M1)", "M1의 판들이 가르친 것". Status를 끝남으로.
- 서브프로젝트를 닫는 묶음(CLAUDE.md 참고 절): `docs/guides/completed.md` 한 행, `docs/decisions/project_mise.md` + `MEMORY.md` 한 줄,
  `HANDOFF.md`, 소개 페이지(`gh-pages`의 `data.js`, 순서는 `site/README.md`).
- `make quick` → 루트 게이트(약 15분, initrd가 바뀌어 prebuild가 다시 돈다). 사용자에게 시간을 알린다.
- 커밋 대상을 좁혀서 add한다.

## 시간

체인 한 판 약 2.5분(부팅 3이 더해진다), 루트 게이트 약 15분. 닫는 문서 묶음.
