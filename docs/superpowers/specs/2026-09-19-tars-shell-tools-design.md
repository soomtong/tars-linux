# TARS Shell Tools — Design

접두사: ST

Status: 열렸다(2026-09-19). 착수 전 프로브를 이미 돌렸고 그 결과가 아래 실측
절에 있다. 같은 날 M0·M1·M2를 연달아 끝냈다 — "M1·M2가 실행으로 증명한 것"
절에 있다.

관련 문서: `2026-09-11-tars-shell-config-design.md`(SC. 씨앗 rc와 `shell_config`
탈출로를 세운 문서 — 아래에서 "SC 결정 N"은 그 문서의 것이다) ·
`2026-09-11-tars-shell-memory-design.md`(SM. 훅 둘과 히스토리 env) ·
`2026-09-12-tars-shell-history-durability-design.md`(SD) ·
`2026-09-12-tars-bash-history-durability-design.md`(BH) ·
`2026-09-10-tars-userland-tools-design.md`(UT. 게스트에 실린 도구 65개) ·
`2026-09-12-tars-gate-accuracy-design.md`(GA. 게이트가 거짓을 말하지 않게 하는
규칙) · `2026-09-19-tars-disk-install-design.md`(DI. 아직 진행 중)

## 한 줄 요약

깔려 있는데 아무도 안 부르는 도구를 셸이 쓰게 만든다 — 셋의 씨앗 rc에 eza
별칭을 넣고(`ls`를 eza로 가리는 것이 그 하나), `gitconfig`를 심어서
`/.gitconfig`가 가리키는 자리를 실체로 채운다.

## 왜 지금인가

UT가 유저랜드 도구 65개를 세웠고 SM이 그중 둘(zoxide·fzf)에 훅을 걸었다.
그런데 eza·bat·fd·rg·sd·jq·tree·duf·ncdu·htop·btop·hyperfine은 여전히
이름으로 직접 부르는 것까지다. 씨앗이 정의한 별칭은 둘(`tars-config` ·
`tars-rc`)뿐이고, 그 둘은 설정 파일을 여는 도구지 일상 도구가 아니다.

사용자가 2026-09-19에 물었다 — *"부팅 후 점검할 수 있는 config 폴더에 fish의
설정만 있고 bash·zsh의 설정 정보가 없고 gitconfig 심볼릭 링크도 깨져 있다.
기본으로 설치하는 추가 유틸리티를 확인해서 적당한 셸 설정을 구성하자."*
재 보니 절반은 사실이 아니고 절반은 사실이다(실측 1). 씨앗 셋은 다 깔린다.
`gitconfig`는 정말로 없고, 그것을 만드는 코드가 저장소에 한 줄도 없다.

이 서브프로젝트가 답하는 질문은 "이 기계의 셸이 깔린 도구를 쓰는가" 하나다.
그 답이 서면 사용자가 자기 rc를 손대지 않아도 되는 부분이 늘어난다.

## 착수 전에 잰 것 — 프로브 부팅 셋

프로브 하네스는 저장소 밖(`/tmp/probe/`)에 있다. `config/make_disk.sh`와 같은
방식으로 빈 ext2를 라벨 `tars-config`로 굽고, `kernel/build/arch/x86/boot/bzImage`
+ `kernel/initrd.cpio`를 `-append console=ttyS0`로 띄운 뒤 QEMU monitor의
`sendkey`로 게스트 셸에 명령을 넣는다(`gate_lib.sh`의 `type_keys`를 그대로
쓴다). 부팅 한 번이 약 30초다.

### 실측 1 — 씨앗 셋은 다 깔린다. 없는 것은 gitconfig 하나다

빈 디스크로 첫 부팅:

```
tars-init: mounted ext2 at /config
tars-init: created /config/tars.conf
tars-init: seeded /config/fish.config
tars-init: seeded /config/bashrc
tars-init: seeded /config/zshrc
```

게스트의 `/config`: `bashrc`(2233B) · `fish.config`(1397B) · `zshrc`(1813B) ·
`tars.conf` · `xdg/` · `lost+found/`. 저장소의 디스크 이미지 일곱
(`config` · `hangul` · `input` · `net` · `net-ntp` · `net-ntp-dhcp` · `power`)을
`debugfs`로 열어도 일곱 다 같은 셋을 갖고 있다. 그중 어느 것에도 `gitconfig`가
없다 — `initrd`의 `/.gitconfig`는 `config/gitconfig`를 가리키는데 그 실체를
만드는 코드가 없기 때문이다(`tools/check.sh`의 검사 13만 그것을 만든다).

사용자가 본 "fish 설정만"은 `/config`가 아니라 `/.config`다. 거기에 fish만
있는 것은 SC 결정 1이 정한 자리다 — bash·zsh의 rc는 홈의 `/.bashrc` ·
`/.zshrc`로 가는 링크이고, XDG 자리에는 fish만 산다.

### 실측 2 — 게이트가 rc 켜진 셸에 실제로 치는 이름

설정 디스크를 붙이는 체인은 여섯이다(`-drive file=` 개수로 셌다):
config · input · power · hangul · net · machine. 나머지 여섯(boot · terminal ·
device · render · copy · tools)은 디스크를 안 붙이므로 셸이 씨앗을 안 읽는다 —
그 체인들에서는 어떤 별칭도 안 돌아간다.

그 여섯이 `type_keys`로 치는 명령의 첫 낱말:

| 체인 | 치는 것 |
|---|---|
| config | `tars-config` · `echo` · `cat` · `grep` · `rm` · `ls` · `cd` · `pwd` · `z` · `whence` · `bash` · `zsh` · `unsetopt` · `history` · `exit` |
| net | `ls` · `cat` · `ip` · `nc` · `echo` |
| power | `kill` · `echo` |
| input | `echo` · `/usr/bin/bash`(절대 경로) |
| hangul | `echo` (나머지는 copy mode의 키와 검색어다) |
| machine | `u` `s` `b` 세 글자 — 실행이 아니라 입력줄 에코다 |

### 실측 3 — 이름이 겹치는 자리는 `ls`와 `cat`뿐이다

`ls`가 돌아가는 자리가 셋이다.

| 자리 | 지금 나오는 판정 글자 |
|---|---|
| `config/check.sh` 6차 — `ls /config/zshrc` | `No such file` |
| `config/check.sh` 8차 — `ls /config/xdg/zoxide` | `db.zo` |
| `net/check.sh` 검사 2 — `ls /sys/class/net` | `eth0` |

셋 다 "이름이 화면에 찍혔는가"를 본다. `cat`이 돌아가는 자리는 config에 넷 ·
net에 둘이다. 나머지 이름(`echo` · `grep` · `rm` · `cd` · `pwd` · `kill` · `ip` ·
`nc` · `z` · `bash` · `zsh`)은 판정의 대상이거나 셸 자체다.

### 실측 4 — eza는 이 화면에서 이렇게 보인다

| 잰 것 | 결과 |
|---|---|
| 격자 | `155x47` (fb 1280x800, `terminal: grid 155x47 (fb 1280x800)`) |
| 판 | `eza - A modern, maintained replacement for ls` / `v0.21.0 [+git]` |
| `eza --icons /` | 아이콘 코드포인트가 나오지만(`U+E5FF` · `U+F016` …) unifont에 PUA 글리프가 0개다(cmap 58,910자 중 `U+E000`–`U+F8FF` 없음). `font.zig`는 폰트에 없는 글자를 null로 돌려주고 아무것도 안 그린다 — 아이콘은 빈 칸이 된다 |
| `eza /config/nope-zzz` | `"/config/nope-zzz": No such file or directory (os error 2)` — `No such file`이 들어 있다 |
| `eza /sys/class/net` | 이름을 그대로 찍는다(`lo`. 그 프로브에는 NIC가 없었다) |
| `eza --tree --level=1 /config` | 상자 그리기 문자로 트리를 그린다 |
| `eza -la --group-directories-first /config` | 크기는 사람이 읽는 단위(`2.2k`)가 기본이다 |
| `bat --style=plain --paging=never /config/tars.conf` | 파일 내용을 장식 없이 낸다 |

### 실측 5 — git은 지금 이 상태다

`git var -l`이 답한 것:

```
GIT_DEFAULT_BRANCH=master
GIT_EDITOR=editor          (/usr/bin/editor → vim.tiny. UT-M3의 링크다)
GIT_PAGER=pager
GIT_CONFIG_SYSTEM=/etc/gitconfig
GIT_CONFIG_GLOBAL=/.config/git/config
GIT_CONFIG_GLOBAL=/.gitconfig
GIT_AUTHOR_IDENT=root <root@(none).(none)>
```

`git config --list`는 빈 출력이다. 즉 지금 git은 설정이 하나도 없고, 신원은
`/etc/passwd`에서 유도하며, 새 저장소의 기본 브랜치는 `master`다.

### 실측 6 — 후보 별칭 넷은 셸 셋에서 0바이트다

`/tmp/probe/m0/boot-m0.sh`가 후보 줄 넷(`cand.{fish,bash,zsh}`)과 빈 파일을
설정 디스크에 실어 부팅하고, 게스트에서 셋에게 각각 먹여 출력을 `wc -c`로
셌다.

| 준 것 | zsh | bash | fish |
|---|---|---|---|
| 후보 별칭 넷 | 0 | 0 | 0 |
| 빈 파일(기준선) | 0 | 0 | 0 |

후보의 값은 기준선과의 차이이고, 그 차이가 0이다. 비대화형 실행으로 쟀다 —
후보가 별칭 정의뿐이라 이 조건에서 갈리지 않는다. 훅이었다면 대화형으로
재야 한다(SD 실측 9가 그 구분을 적고 있다).

같은 부팅에서 별칭 본문 넷을 직접 쳐 봤다(측정 3): `eza` ·
`eza -l --group-directories-first` · `eza -la --group-directories-first` ·
`eza --tree --level=2` 넷 다 목록을 낸다. 트리 갈래는 상자 그리기 문자를
쓰고, 긴 목록의 파일 종류는 `.`으로 시작한다(`.rw-r--r--` — GNU ls의
`-rw-r--r--`와 다르다. M1의 게이트 확인이 이 차이를 판정 글자로 쓴다).

### 실측 7 — 하네스를 다시 돌리는 방법

`/tmp/probe/tars-probe{,2,3}.sh`가 그 셋이고, 시리얼 로그는
`/tmp/probe/serial{,2,3}.log`다. 셋 다 저장소를 안 건드린다(디스크 이미지도
`/tmp/probe/`에 굽는다). 저장소가 지워지면 이 스크립트는 다시 쓴다 — 이
문서의 실측 절이 그 비용을 다시 안 치르게 하는 자리다.

## M1·M2가 실행으로 증명한 것 — 다시 조사하지 말 것

### 1. 별칭이 도는 것을 게이트가 본다

`config/check.sh` 1차 부팅이 이 세 줄을 찍는다.

```
boot 1: the seeded 'ls' alias runs eza (file modes start with a dot)
boot 1: git read init.defaultBranch=main out of the seeded /config/gitconfig
boot 1: init seeded the gitconfig too (the .gitconfig link has a target now)
```

첫 줄의 판정 글자는 `\.rw-`다 — eza의 긴 목록은 파일 종류를 `.`으로 찍고
GNU ls는 `-`으로 찍는다. 그래서 이 줄이 "별칭이 정의됐다"가 아니라 "별칭이
돈다"를 본다. 셋째 줄의 짝은 시리얼 로그의 `tars-init: seeded
/config/gitconfig`이고, 둘째 줄이 그 값이 git에 닿는 것까지 본다.

### 2. `ls` 셰도가 게이트를 안 깼다

`ls`가 돌아가는 자리 셋이 전부 초록이다 — config 체인의 6차(`ls
/config/zshrc` → `No such file`)와 8차(`ls /config/xdg/zoxide` → `db.zo`),
그리고 net 체인의 `ls /sys/class/net`(→ `eth0`). 설계할 때 잰 그대로였다.

### 3. 씨앗 단위 검사가 양방향으로 돈다

- gitconfig 씨앗에 `=` 없는 줄을 심으면 그 자리에서 빨개진다(직접 심어 봤다).
- 별칭 이름을 `alias cat='bat'`으로 바꾸면 `ALLOWED_ALIAS_NAMES`가 잡는다
  (직접 바꿔 봤다).
- "볼 것이 없었다"로 통과하지 않는 것도 확인했다 — 절과 키가 0이면 실패다.
- 검사가 씨앗의 주석에 걸린 적이 한 번 있다. `[user]`를 글자로 찾는 검사가
  씨앗의 설명문에 있는 같은 글자를 잡아서, 지금은 주석 줄을 건너뛰고 절과
  키를 파싱한다.

### 4. tools 검사 13은 그대로다

그 체인에는 설정 디스크가 없어 씨앗이 안 깔린다. 그래서 검사 13이 증명하는
경로("git이 링크를 풀어 /config에 썼다")가 안 바뀌고, tools 체인이 초록이다.
`[user]` 절을 안 넣은 결정 5가 그 초록을 값싸게 만든다.

### 5. Zig의 multiline 문자열은 탭을 거부한다

```
src/config.zig:1228:7: error: string literal contains invalid byte: '\t'
```

gitconfig 씨앗의 들여쓰기가 공백 넷인 이유다. git은 둘 다 받고,
`git config --global`이 이 파일을 다시 쓸 때는 자기가 탭으로 쓴다 — 언젠가
둘이 섞이는 것이 정상이다.

### 6. 루트 게이트

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

12체인 × 3회, `FAIL` 0줄. 이번 판은 34분 걸렸는데 그 수를 기준선(16분 01~11초,
GL-M3)과 견주지 않는다 — 같은 시간에 다른 컨테이너 몇이 함께 돌고 있었다.
바뀐 것은 게이트 시간이 아니라 무엇을 판정하는가다.

## 결정

### 1. 셰도 규칙 — 게이트가 치는 이름과 겹치지 않는다

별칭은 그 이름을 치는 모든 곳에서 돈다. 씨앗 rc를 읽는 셸에 게이트가 명령을
넣으므로(실측 2), 별칭 하나가 게이트의 판정 글자를 바꿀 수 있다. 그래서
기본값은 "안 가린다"이고, 예외는 재서 통과한 것만이다. 실측 3의 표가 그
예외의 후보 목록이다.

이 규칙이 SC·SM이 세운 것과 같은 종류다. 저쪽은 씨앗이 무언가를 찍으면
화면 좌표가 밀린다고 정했고, 이쪽은 이름을 가리면 판정 글자가 바뀐다고
정한다. 둘 다 대가를 재고 나서 정한 것이다.

### 2. `ls`는 eza로 가린다 — 예외 하나

가리는 대신 지는 것: 실측 3의 세 자리가 eza의 출력으로 판정된다. 넷째
프로브가 그 셋을 미리 쟀다 — eza는 이름을 그대로 찍고, 없는 경로에는
`No such file`을 포함한 문구를 낸다. 그래서 셋 다 산다. 이 결정의 최종
증거는 `config/check.sh`(9부팅)와 `net/check.sh`(3부팅+)의 초록이다.

가리는 이유: `ls`를 안 가리면 eza는 `ll`·`la`·`lt`라는 새 이름으로만
닿는다. 도구를 실은 값의 대부분은 습관적으로 치는 이름이 그 도구로 가는
데서 나오고, 이 기계는 "개발용"이라고 불리는 기계다(UT-M3이 git을 조건으로
들인 이유와 같은 자리).

### 3. `cat`·`find`·`grep`·`sed`·`du`·`df`·`top`은 안 가린다

- `cat`: 실측 3의 여섯 자리. bat은 tty에서 장식을 붙이고(`--style=plain`을
  쓰면 붙지 않는다) 호출마다 플래그를 달고 다니는 별칭은 `cat`의 뜻이 아니다.
- `find`·`grep`·`sed`: `fd`·`rg`·`sd`는 플래그 의미가 다르다. `grep -r`과
  `rg`의 차이는 조용히 다른 결과를 낸다 — 별칭이 아니라 함정이다.
- `du`·`df`·`top`: `ncdu`·`duf`·`btop`은 화면을 통째로 가져가는 TUI다.
  프롬프트가 TUI로 바뀌는 것은 별칭이 할 일이 아니다.

### 4. 별칭이 담는 것은 eza 넷이다

셋 다 같은 뜻으로 이 넷을 정의한다.

| 별칭 | 뜻 |
|---|---|
| `ls` | `eza` |
| `ll` | `eza -l --group-directories-first` |
| `la` | `eza -la --group-directories-first` |
| `lt` | `eza --tree --level=2` |

`--icons`는 안 붙인다(실측 4 — 폰트에 글리프가 없어 빈 칸이 된다). 실측 4가
확인한 플래그만 쓴다.

### 5. gitconfig는 씨앗으로 만든다 — 링크를 실체로 채운다

`/.gitconfig` → `/config/gitconfig` 링크는 UT-M3 결정 8이 세운 것이고 그대로
둔다. 우리가 안 세운 것은 그 자리에 들어갈 파일이다. init이 rc 셋을 깔 때
같이 깐다(`O_EXCL` — 있으면 안 건드린다).

내용은 여섯 줄 남짓이다.

```
[init]
	defaultBranch = main
[core]
	pager = less -FRX
[color]
	ui = auto
[alias]
	st = status -sb
	lg = log --oneline --graph --decorate
```

- `init.defaultBranch`: 실측 5가 지금 `master`인 것을 보여준다. 새 저장소가
  `main`으로 뜨는 것이 요즘 기본값이다.
- `core.pager`: `-X`가 요점이다. less가 alternate screen을 안 쓰면 `git log`의
  출력이 우리 화면의 스크롤백에 남고, 그러면 CM·CN·CS가 세운 copy mode로
  Git 로그를 훑을 수 있다. `-F`는 한 화면이면 pager를 안 띄우는 것이다.
- `color.ui`: 지금도 `auto`가 기본이지만 적어 둔다 — 사용자가 끄고 켤 자리를
  `tars-config`가 가리키는 파일 안에 두는 것이 이 파일의 목적이다.
- `[user]`는 안 넣는다. 실측 5가 신원이 이미 `/etc/passwd`에서 나오는 것을
  보여준다. 그리고 넣으면 `tools/check.sh` 검사 13의 판정 값(`email = tars`)과
  겹칠 수 있다 — 그 검사는 "git이 링크를 풀어 /config에 썼다"를 보는 것이고,
  씨앗에 같은 값이 있으면 검사가 거짓으로 초록이 된다(GA가 없애려는 모양).

### 6. 배포는 씨앗 리터럴이다. 기존 디스크는 지우고 재부팅이 이전 경로다

씨앗은 `init/src/config.zig`의 문자열 리터럴로 남는다. `O_EXCL`이라 이미
있는 파일은 안 덮으므로, 이 변경은 새 디스크와 rc를 지운 디스크에만 간다.
그 경로는 이미 검증돼 있다 — `config/check.sh`의 6차가 `/config/zshrc`를
지우고 7차가 새 씨앗을 받는다.

대안(씨앗이 managed 파일을 `source`)은 안 쓴다. 파일이 둘로 늘고, 그 파일도
"한 글자도 안 찍는다"를 새로 재야 하며, 얻는 것은 기존 디스크로의 자동
업그레이드 하나다. 셸 설정이 자주 바뀌기 시작하면 그때 이 결정을 다시 본다.

### 7. 별칭 이름 목록을 테스트가 못 박는다

`config_test.zig`의 `expectQuietSeed`는 `alias`로 시작하는 줄을 전부
통과시킨다. 그래서 이름 하나를 더하는 일에는 아무 저항이 없다 — 저항이
없으면 게이트가 치는 이름을 가리는 별칭이 조용히 들어온다. 허용된 이름
목록을 배열로 두고 그 밖의 이름은 실패하게 한다(`HOOKED_TOOLS`가 훅에 대해
하는 것과 같은 자리).

### 8. fzf의 env 줄은 이번에 안 넣는다

`FZF_DEFAULT_COMMAND`(fd로 파일 찾기) · `FZF_DEFAULT_OPTS`(높이와 테두리)는
씨앗의 허용 범주를 하나 늘리는 일이다(`export` 줄은 지금 셋 다 거부된다).
후보이지만 이 milestone의 질문("깔린 도구를 셸이 쓰는가")에 답하는 데
필요하지 않다. 다음에 이 서브프로젝트를 여는 사람의 첫 후보로 적어 둔다.

## 비목표

1. 프롬프트. SC 비목표 5 그대로다. 프롬프트는 게이트의 좌표계이고, 바꾸는
   값은 사용자가 자기 기계에서 치른다.
2. zsh 자동완성. `/usr/share/zsh` 트리를 initrd에 안 실었다. 넣으려면
   `make_initrd.sh`의 주석에 적힌 한 줄을 살리고 `compinit`을 씨앗에 더하는
   일인데, 그 두 줄이 initrd 크기와 기동 시간을 함께 바꾼다. 이번 질문과
   무관하다.
3. 셸을 셋보다 늘리는 것 · 새 패키지를 싣는 것. UT의 목록이 그대로다 —
   이 서브프로젝트는 이미 실린 것만 쓴다.
4. TUI 도구를 이름으로 가리는 것(결정 3).
5. fzf env(결정 8).
6. 실기 판정. RM·DI와 같다 — 판정은 QEMU 안에서 닫는다.

## 위험

1. 별칭이 게이트 판정을 흔든다. 방어는 실측 3의 표와 결정 1이고, 최종
   판정은 루트 게이트 한 판이다. `ls` 하나가 걸리는 자리는 셋뿐이다.
2. 씨앗이 한 글자라도 찍으면 설정 디스크를 붙이는 여섯 체인의 화면 좌표가
   밀린다. 별칭 정의는 정의할 때 아무것도 안 찍지만, 그것을 가정하지 않고
   M0가 줄마다 0바이트를 잰다(SM 실측 23의 방식).
3. gitconfig 씨앗이 `tools/check.sh` 검사 13을 거짓으로 만든다. 그 체인에는
   설정 디스크가 없어 씨앗이 안 깔리므로 검사의 전제가 안 바뀐다. 그래도
   `[user]` 절을 안 넣어(결정 5) 겹칠 값을 아예 안 만든다.
4. eza의 색이 화면 스타일 예산(`STYLE_DUMP_LIMIT=96`)을 먹는다. 색을 세는
   체인은 render와 copy인데 둘 다 설정 디스크를 안 붙인다(실측 2) — 별칭이
   거기서 안 돌아간다.
5. 기존 디스크에는 새 별칭이 안 간다. 결정 6이 그 답이고, README에 그 한
   줄을 적는다.
6. `eza`가 없는 기계. 게스트에서 eza를 빼면 `ls`가 아무것도 안 낸다 —
   셸이 "command not found"를 찍는다. 지금 `ls`는 coreutils가 주는 실체다.
   그래서 `ls` 셰도만은 관문을 달 수 없다는 것을 알고 둔다(훅 둘은
   `command -v` 관문이 있고, 그 관문이 SM 결정 11이었다). 대가는 eza를
   빼는 사람이 이 줄도 함께 봐야 한다는 것이고, `guest_tools.sh`가 그
   자리를 이미 문서화하고 있다.

## Milestone

| | 무엇 | 판정 |
|---|---|---|
| M0 | 새 줄의 조용함과 eza의 플래그를 잰다. 제품 코드 0줄 | 재는 것 자체가 산출물 |
| M1 | 셋의 씨앗에 별칭 넷. `config_test.zig`의 이름 목록, `config/check.sh`에 확인 | config·net 체인 |
| M2 | gitconfig 씨앗 + 게이트 확인 한 줄 | config·tools 체인 |

## 바뀌는 파일

| 파일 | 무엇 |
|---|---|
| `init/src/config.zig` | `rcSeed()` 세 갈래에 별칭 넷 · `GITCONFIG_PATH`/`GITCONFIG_SEED` · 씨앗 함수 일반화 |
| `init/src/config_test.zig` | 별칭 이름 허용 목록 · gitconfig 씨앗 검사 |
| `init/src/main.zig` | gitconfig 씨앗 호출(M2) |
| `config/check.sh` | 별칭이 실제로 정의됐는가 · gitconfig가 깔렸는가 |
| `README.md` | 기존 디스크가 새 씨앗을 받는 방법 한 줄 |
| `docs/decisions/project_shell_tools.md` | 세션을 넘는 기억 |

## 다음

M0의 plan. 그 뒤 M1, M2 순서로 plan을 새로 쓴다(한 milestone이 끝나면 다음
plan을 그 시점에 쓴다 — 이 저장소의 규칙).
