# TARS Shell Config — Design

**Date:** 2026-09-11
**Status:** 설계 완료, 착수 전. milestone 셋(SC-M0·M1·M2)을 계획했고
plan은 각 milestone 시작 시점에 따로 쓴다.
착수 전 기준선은 열한 체인 3/3으로 **23분 43.15초**(UT-M3 시점)다.

## 한 줄 요약

**게스트 셸이 사용자의 rc 파일을 읽게 하고, 그 파일이 부팅 사이에 살아남게
한다.** 지금은 `init`이 `--no-config`/`--norc`/`-f`를 **조건 없이** 넘겨서
`~/.bashrc`도 `config.fish`도 영영 안 읽힌다. 이 서브프로젝트가 끝나면
`/config`의 rc 파일 셋이 링크로 홈에 이어지고, `tars.conf`의 새 키
`shell_config`가 그것을 켜고 끈다.

## 왜 지금인가

**UT가 이 문을 지목하고 갔다.** UT design 실측 10이 `init/src/main.zig`의 한
줄을 인용하며 *"조건 없이 붙는다 — `zoxide`도 `fzf`도 걸 자리가 없다"*고
적었고, 비목표 6이 그 둘을 떨어뜨리면서 **"셸 설정을 다루는 서브프로젝트가
생기면 그때 함께 온다"**고 남겼다.

그리고 **UT-M3이 길을 절반쯤 내 놓았다.** 결정 8이 `/.gitconfig`를
`/config/gitconfig`로 이으면서 **"사용자 파일을 `/config`에 두고 링크로
홈에 잇는다"**는 모양을 처음 세웠다. rc 파일은 그 모양을 셋으로 늘리는
일이고, 새로 발명할 것이 없다.

**사용자가 2026-09-11에 UT가 남긴 후보 넷 중 이것을 골랐다.**

## 착수 전에 실측한 것 — **다시 조사하지 말 것**

### 1. 플래그가 가는 길은 한 줄기이고 분기가 하나도 없다

```zig
// init/src/config.zig:39
pub fn noConfigFlag(self: Shell) [:0]const u8 {
    return switch (self) {
        .fish => "--no-config",
        .bash => "--norc",
        .zsh  => "-f",
    };
}
```

```zig
// init/src/main.zig:503
const shell_flag = shell.noConfigFlag();
```

그 값이 `terminal`의 argv 셋째 자리로 가고(`main.zig:526`),
`terminal/src/main.zig:964`가 그것을 받아 셸의 argv에 그대로 붙인다
(`main.zig:1030`). **세 파일을 지나는 동안 조건이 한 군데도 없다.**

### 2. 셸이 둘인데 플래그를 받는 것은 하나뿐이다

`init`이 띄우는 자식은 둘이다 — `terminal`(화면)과 `console_shell`(시리얼).
**콘솔 셸에는 지금도 플래그가 없다.** `main.zig:537`의 주석이 그 이유를 이미
적어 두었다:

> 콘솔 셸에는 플래그를 주지 않는다. 이쪽은 사용자가 직접 쓰는 자리이므로,
> 나중에 설정 파일이 생기면 그것을 읽는 편이 맞다.

즉 **시리얼 콘솔 셸은 이미 rc를 읽을 준비가 돼 있고 읽을 파일이 없을
뿐이다.** `HOME=/`이고 `/`는 tmpfs라 아무것도 없다.

### 3. 영속하는 자리는 `/config` 하나이고 읽기·쓰기다

`init/src/main.zig:93`이 ext2를 `MS_SYNCHRONOUS`로 붙이고 `MS_RDONLY`는 안
준다. UT design 실측 8이 같은 것을 쟀다. **`fsync`를 따로 안 부르는 것이
실수가 아니라 그 플래그의 값어치다**(`config.zig:432`의 주석).

### 4. 게이트 열한 체인 중 설정 디스크를 붙이는 것은 다섯이다

| 디스크 있음 | 디스크 없음 |
|---|---|
| `config` · `hangul` · `input` · `machine` · `power` | `boot` · `copy` · `device` · `render` · `terminal` · `tools` |

**여섯은 `/config`가 initrd 안의 빈 디렉터리로 남는다** — 씨앗 rc가 생길
자리가 없으니 rc에 관한 한 지금과 동작이 같다. 반대로 다섯은 init이 씨앗을
깔면 셸이 그것을 읽는다.

### 5. fish는 인사말을 찍는다 — **그리고 게이트가 그것을 마커로 쓰고 있다**

`/usr/share/fish/config.fish`는 이미 initrd에 있고(`make_initrd.sh:235`),
그 파일이 첫 프롬프트에서 `__fish_config_interactive`를 부르고
(`__fish_config_interactive.fish:115`) 그것이 `fish_greeting`을 부른다.
문구는 두 줄이다:

```
Welcome to fish, the friendly interactive shell
Type help for instructions on how to use fish
```

**이것은 미래형이 아니라 현재형이다.** 콘솔 셸은 플래그가 없어서 지금도
이 두 줄을 시리얼에 찍고 있고, **`machine/check.sh:117`이 그 문구를 UEFI
부팅의 완료 마커로 grep한다.**

```bash
if grep -aq "Welcome to fish, the friendly interactive shell" "$LOG"; then
  FOUND=1
```

그래서 **`/etc/fish/config.fish`로 시스템 전체의 인사말을 끄면 그 마커가
사라진다.** 이 사실 하나가 결정 6을 정했다.

### 6. `/etc/fish`는 fish 바이너리에 박혀 있고 initrd에는 없다

```
$ strings usr/bin/fish | grep etc/fish
?bin/fishetc/fish
```

`__fish_sysconf_dir`가 `/etc/fish`라는 뜻이다. sysroot에는
`/etc/fish/{config.fish,conf.d,completions,functions}`가 있지만
**`make_initrd.sh`가 그 트리를 복사하지 않는다** — 게스트에는 없다.

### 7. bash는 안전하다

`--norc`를 빼면 bash는 `/etc/bash.bashrc`와 `~/.bashrc`를 읽는데
**게스트에 둘 다 없다.** sysroot에는 `/etc/bash.bashrc`가 있지만
`make_initrd.sh`가 복사하지 않는다. 프롬프트도 rc와 무관한 내장 기본값이라
플래그를 빼도 안 바뀐다.

### 8. zsh는 안 안전하다 — 마법사가 뜬다

sysroot에 `usr/share/zsh/functions/Newuser/zsh-newuser-install`이 있다.
zsh는 `-f` 없이 뜨면서 `$ZDOTDIR`의 `.zshrc`·`.zshenv`·`.zprofile`·`.zlogin`이
**하나도 없으면** 그 마법사를 띄우고 입력을 기다린다.

**우리가 놓을 `/.zshrc`는 심볼릭 링크이고, 설정 디스크가 없으면 끊어진
링크다.** zsh는 `stat`으로 보므로 끊어진 링크는 "없는 것"이다. 증상은
실패가 아니라 **타임아웃으로 매달리는 것**이고, UT-M1 실측 4의
`less`·`top`과 같은 종류다.

### 9. 프롬프트는 게이트의 좌표계다

`copy/check.sh:758`:

> 20은 `root@(none) ~# echo `의 길이다.

`copy/check.sh:762`가 그 수가 한 번 바뀐 적이 있다고 적고 있다 —
`@(none) ~#`에서 `root@(none) ~#`으로 **게스트의 사용자 데이터베이스를
건드렸을 때** 네 글자가 길어졌다. **프롬프트 글자 수가 게이트에 박혀 있고,
그것을 움직이는 것은 이 저장소에서 이미 한 번 비용을 치른 일이다.**

### 10. `config/check.sh`는 같은 디스크로 두 번 부팅하는 유일한 체인이다

1차는 빈 디스크로 떠서 init이 씨앗을 심고, **게스트 셸에 직접 타이핑해서**
`tars.conf`를 `shell=zsh`로 고친다. 2차는 `make_disk.sh`를 **안 부르고**
같은 이미지를 그대로 물려 "1차에서 사람이 고친 것을 2차가 읽는다"를
증명한다(`config/check.sh:37-42`).

**rc 파일이 증명해야 하는 것과 글자 그대로 같은 모양이다.** 열두번째 체인을
만들 이유가 없다.

### 11. 감독자는 빨리 죽는 것이 3회면 포기한다

```zig
// init/src/main.zig:356
if (c.fast_restarts >= MAX_FAST_RESTARTS) {
    c.given_up = true;
```

`FAST_EXIT_SECONDS = 10`, `MAX_FAST_RESTARTS = 3`. **rc가 셸을 죽이면 이
길로 온다** — 세 번 죽고 나면 그 자식은 영영 안 뜬다.

### 12. 실기는 limine으로 부팅한다 — cmdline을 고칠 수 있다

`machine/check.sh:10-12`가 아홉 체인은 `-kernel`로 limine을 통째로 건너뛰고
이 체인만 부트로더를 지난다고 적고 있다. **실기는 limine의 부팅 메뉴를
지나므로 커널 cmdline을 사람이 그 자리에서 고칠 수 있다.** 이것이 탈출로
2를 가능하게 한다.

### 13. `/proc`은 설정을 읽기 전에 이미 붙어 있다

`main.zig:454`가 `/proc`을, `:459`가 `/config`를 붙인다. **`/proc/cmdline`을
읽는 코드가 `loadConfig()`보다 앞에 설 수 있다** — 우선순위를 만들 자리가
이미 있다.

## 비목표

**1. `zoxide`·`fzf`를 넣는 것.** 훅을 걸 자리가 생기면 사용자가 rc에 쓰면
되지만, **도구 조달은 UT의 일이다** — `.deb` 목록 · 라이브러리 closure ·
`guest_tools.sh` · `tools/check.sh`의 검사를 다시 여는 일이고 UT가 세운
절차가 그대로 적용된다. **SC가 끝나면 그것이 다음 후보로 서고, 그때는
"자리가 없다"는 이유가 사라져 있다.** UT 비목표 6을 이 문단이 잇는다.

**2. 셸 히스토리를 영속시키는 것.** rc와 같은 자리에 둘 수 있지만 파일이
계속 자라고 `/config`는 작은 ext2다. **크기 정책이 본체라 따로 판단한다** —
rc는 사람이 쓰는 만큼만 자라고 히스토리는 기계가 자라게 한다.

**3. 쓸 수 있는 `/home`.** UT 비목표 2가 지목한 후보 1이고, 디스크
레이아웃·파티션·마운트 정책이 본체다. **SC는 `/config`에 파일을 더할 뿐
레이아웃을 안 건드린다.**

**4. 터미널 대신 앱이 도는 init 1.** 사용자가 `shell_config=off`의 근거로
"향후 embedded 장비의 init 1으로 쓰일 수 있고, 그때는 항상 도는 application
하나가 전부라 설정이 없는 쪽이 안전하다"고 말했다. **그 근거는 키 하나를
정당화하는 데까지만 쓴다.** 이 서브프로젝트는 `off`가 rc를 확실히 막는다는
것까지만 책임지고, 셸 대신 앱을 띄우는 설계는 안 한다.

**5. 프롬프트를 우리가 정하는 것.** 씨앗이 사용자 취향을 미리 정하지
않는다. 실측 9가 비용을 적고 있고, 그 비용은 사용자가 자기 rc에 프롬프트를
쓸 때 **자기 기계에서만** 치르면 된다.

**6. `/etc/fish/conf.d` 같은 시스템 설정을 사용자에게 여는 것.** 사용자가
고치는 자리는 `/config` 하나다. initrd 안의 파일은 우리가 쓰고 사용자는 안
본다 — `/etc/passwd`와 같은 성격이다.

**7. 셸을 셋보다 늘리는 것.** `Shell` enum은 fish·bash·zsh 그대로다.

**8. rc를 런타임에 다시 읽는 것.** CP가 정한 "고치고 재부팅해야 반영된다"가
그대로다(`main.zig:498`의 주석). 셸에서 `source`하는 것은 사용자의 일이다.

## 결정

### 결정 1 — `/config`의 rc 파일을 **링크**로 홈에 잇는다

UT-M3 결정 8을 그대로 되풀이한다. `make_initrd.sh`가 링크 셋을 놓는다.

| 홈의 이름 | 링크가 가리키는 것 | 실제 파일 |
|---|---|---|
| `/.bashrc` | `config/bashrc` | `/config/bashrc` |
| `/.zshrc` | `config/zshrc` | `/config/zshrc` |
| `/.config/fish/config.fish` | `../../config/fish.config` | `/config/fish.config` |

**안 고른 쪽 둘.**

`HOME=/config`로 바꾸는 것 — 링크가 아예 필요 없어지고 `/.gitconfig` 링크도
지울 수 있어 가장 깔끔해 보인다. 그런데 **프롬프트가 `~#`에서 `/config#`으로
바뀐다**(실측 9). 그리고 `environ.withPath`는 항목을 **더하기**만 하지
**덮어쓰기**는 안 하므로 커널이 준 `HOME=/`를 이기려면 새 코드가 든다.

셸별 환경변수(`XDG_CONFIG_HOME`·`ZDOTDIR`) — **bash는 대화형 rc 경로를 바꾸는
변수가 없어서 셋 중 하나가 구멍이다.**

**링크 이름을 `fish.config`로 적은 것에 뜻이 있다.** `/config` 안이 평평해야
`gitconfig`·`bashrc`·`zshrc`와 같은 층에 선다 — `/config/fish/config.fish`로
두면 디렉터리를 하나 더 만들어야 하고 그 디렉터리는 fish만 쓴다.

### 결정 2 — `tars.conf`에 `shell_config` 키를 더한다. 기본값은 `on`

```
# shell_config: on | off
#   on이면 셸이 홈의 rc 파일을 읽는다(/config에 링크로 이어져 있다)
shell_config=on
```

**`bool`이 아니라 enum이다.** `config.zig`의 다섯 키가 전부
`stringToEnum` 화이트리스트이고, 그 모양을 따르면 "모르는 값은 로그만 남기고
기본값에 머문다"는 규칙이 공짜로 따라온다. 여섯째 키만 다른 모양일 이유가
없다.

**기본값이 `on`인 근거는 `keyboard=apple`·`hangul_layout=shin_pcs`와 같다** —
`config.zig:229`가 *"이 기계를 쓰는 사람이 쓰는 것이 기본값이다"*라고 적어
두었다. 이 기계는 개발용이다. embedded는 `keyboard=pc`를 적듯 `off`를
명시적으로 적는다.

`tars-init: config shell=...` 로그 줄을 **넓혀서** `shell_config=`를 붙인다.
새 줄을 안 만드는 것은 HI-M2가 같은 줄에 한 것과 같은 이유다 — 다른 체인이
그 줄의 앞부분으로 grep한다(`main.zig:461`의 주석).

### 결정 3 — 플래그를 없애지 않고 **조건부**로 쓴다. `on`이면 `"none"`

`noConfigFlag()`는 그대로 두고, `off`일 때만 그 값을 쓴다. `on`이면
`terminal`에 **`"none"`**을 넘기고 terminal이 그 값을 보면 셸 argv에 안
붙인다.

**`Toggles.arg`가 빈 집합에 `none`을 쓰는 선례가 그대로 있다**
(`config.zig:189`):

> 하나도 안 켜졌으면 `none`이다 — 빈 문자열을 argv에 넣으면 terminal 쪽에서
> "인자가 없다"와 구분이 안 된다.

argv 슬롯을 비우거나 배열 길이를 바꾸는 대신 **값 하나로 말하는 것**이 이
저장소가 이미 고른 방식이다. terminal의 손수 실행용 fallback
(`args.len > 2`가 아닐 때의 `--no-config`)은 그대로 둔다.

**콘솔 셸은 `"none"`을 안 쓴다.** 그쪽은 init이 셸을 직접 exec하므로 argv를
init이 짓는다 — `on`이면 슬롯이 `null`(인자가 아예 없다), `off`면 플래그가
들어간다. **`"none"`이 필요한 것은 argv를 짓는 쪽과 쓰는 쪽이 다른 화면 셸
하나뿐이다.**

### 결정 4 — 콘솔 셸도 같은 설정을 따른다

`off`면 시리얼 콘솔 셸의 argv에도 플래그가 붙는다. **이것은 동작 변화다** —
지금 콘솔 셸은 플래그가 없어 rc를 읽으려 한다(읽을 파일이 없을 뿐이다).

`main.zig:537`의 주석이 예고한 것을 실행하는 자리이고, **"같은 기계 안에서 두
셸이 같은 설정을 따른다"**가 읽기에 맞다. `shell`·`keyboard`·자판 둘이 이미
그렇다.

### 결정 5 — initrd에 빈 `/.zshenv` 실체 파일을 놓는다

실측 8의 마법사를 막는다. **링크가 아니라 실체 파일이어야 한다** — 끊어진
링크는 zsh에게 "없는 것"이라 목적을 못 이룬다.

파일 하나로 네 이름(`.zshrc`·`.zshenv`·`.zprofile`·`.zlogin`) 중 하나가
언제나 존재하게 되고, 그것이 마법사의 조건을 깬다. **내용은 비어 있다** —
zsh가 이 파일을 매 부팅 읽지만 할 일이 없다.

### 결정 6 — 인사말은 `terminal`의 `setenv`로 **화면 셸만** 끈다

실측 5가 이유다. `/etc/fish/config.fish`로 시스템 전체를 끄면
`machine/check.sh`의 마커가 사라진다.

```zig
// terminal/src/main.zig, TERM·LANG 옆
_ = setenv("fish_greeting", "", 1);
```

fish의 `fish_greeting` 함수는 `set -q fish_greeting`이 참이면 기본 문구를 안
만들고, 값이 비어 있으면 `test -n` 이 거짓이라 아무것도 안 찍는다. **환경
변수는 fish에서 전역 변수로 보이므로 `set -q`가 참이 된다.**

**자리가 `terminal`인 근거가 이미 문서화돼 있다.** `terminal/src/main.zig:1004`:

> 이 setenv가 PID 1이 아니라 여기 있는 이유는 시리얼 콘솔 셸 때문이다 —
> 그쪽은 정말로 커널 콘솔이라 TERM=linux가 맞다. **같은 기계 안에서 두 셸의
> TERM이 다른 것이 정상이다.**

인사말도 정확히 같은 성질이다 — 화면은 TARS의 화면이라 다른 제품의 배너가
뜰 자리가 아니고, 시리얼은 fish를 그대로 보는 자리다. **그리고 게이트를 한
줄도 안 고친다.**

`bash`·`zsh`는 `fish_greeting`이라는 환경 변수를 무시하므로 조건 없이 넣는다.

### 결정 7 — 씨앗은 셋 다, 없는 것만. 프롬프트를 안 건드린다

init이 `/config`를 마운트했을 때만 `bashrc`·`zshrc`·`fish.config`를 각각
"없으면 만든다". `config.save()`가 `tars.conf`에 대해 하는 것과 같은 모양이고,
같은 이유로 죽은 코드가 안 된다.

**셋 다인 근거** — `tars.conf`의 `shell`은 언제든 바뀔 수 있고, 바뀐 뒤에야
씨앗이 생기면 "고치고 재부팅했는데 rc가 없다"가 된다. 그리고 셋의 문법 차이를
나란히 두면 사용자가 그것을 읽고 고를 수 있다. 비용은 부팅마다 `open()` 셋이다.

**내용은 주석과 무해한 alias 몇이고 프롬프트를 안 건드린다.** 실측 9가
이유이고, 비목표 5가 같은 것을 말한다.

### 결정 8 — 탈출로 1: 감독자가 포기하기 직전에 rc 없이 한 번 더 띄운다

실측 11의 자리다. `given_up`을 세우기 전에 **한 번만** argv의 플래그 슬롯을
`off`의 값으로 바꾸고 `fast_restarts`를 0으로 되돌린다.

**`resolveShell()`이 이미 하는 폴백과 같은 모양이다** — 설정이 가리키는
것이 실제로 안 되면 되는 것으로 떨어진다. 로그를 크게 찍어서 "왜 내 rc가 안
먹지"가 로그 한 줄로 답이 되게 한다.

**덮는 것은 "죽는 rc"까지다.** 매달리는 rc(`read` 한 줄, 무한 루프)는 자식이
안 죽으니 이 길로 안 온다 — 그것이 탈출로 2가 따로 있는 이유다.

### 결정 9 — 탈출로 2: `/proc/cmdline`의 `tars.noconfig`가 `tars.conf`를 이긴다

실측 12·13이 근거다. `loadConfig()` 뒤에 한 줄이 서고, 그 토큰이 있으면
`shell_config`를 `off`로 덮는다.

**죽는 rc도 매달리는 rc도 덮는다.** 대가는 사람이 부팅 순간에 개입해야
한다는 것이고, 자기치유가 없다. **둘의 성격이 달라 서로를 대체하지
않는다** — 그래서 둘 다 만든다(사용자가 2026-09-11에 정했다).

**우선순위가 둘이 되는 것을 설계에 못 박는다: cmdline > `tars.conf` >
기본값.** `tars.conf`의 다른 키는 cmdline을 안 본다 — 이 키 하나만 예외이고,
그 예외의 근거는 "`tars.conf`를 고칠 셸이 없을 때 쓰는 것"이다.

### 결정 10 — 게이트는 `config/check.sh`가 맡고 부팅을 셋으로 늘린다

실측 10이 이유다. 열두번째 체인을 안 만들어 게이트 +2분을 안 쓴다.

| 부팅 | 무엇 | 무엇을 본다 |
|---|---|---|
| 1차 | 빈 디스크. init이 `tars.conf`와 rc 셋을 심는다. 사람이 `tars.conf`를 `shell=zsh`로 고치고 `/config/zshrc`에 줄을 더한다 | 씨앗 넷이 생겼다 |
| 2차 | 같은 이미지. zsh가 뜬다 | **rc가 실제로 읽혔다** |
| 3차 | 같은 이미지에 `shell_config=off` | **같은 rc가 안 읽힌다** — 부정 검사 |

**3차가 이 설계에서 가장 강한 검사다.** 2차만 있으면 "rc를 읽는다"까지만
증명되고 "`off`가 그것을 막는다"는 로그 수준에 머문다. 부정 검사가 있어야
`off`가 tautology가 아니게 된다 — **UT-M1과 UT-M3의 음성 확인이 같은 것을 두
번 가르쳤다**(목록과 검사가 같은 것을 보면 초록인데 아무것도 안 보는 검사가
된다).

## Milestone 셋

| | 무엇 | 검증 |
|---|---|---|
| **SC-M0** | 자리 — 결정 2·3·4·5·6과 결정 1의 링크 셋 | `tars-init: config ... shell_config=on` 줄이 뜬다 · **열한 체인 3/3이 안 깨진다** |
| **SC-M1** | 씨앗(결정 7) + 게이트(결정 10) | `config/check.sh` 세 부팅이 초록 |
| **SC-M2** | 탈출로 둘(결정 8·9) | 일부러 죽는 rc를 깔면 감독자가 되살린다 · `tars.noconfig`가 `tars.conf`를 이긴다 |

**SC-M0의 검증이 "아무 일도 안 일어난다"인 것이 이상해 보이지만 그것이
정확하다** — 플래그를 빼는 순간 fish가 두 줄을 더 찍을 수 있고(실측 5) zsh가
매달릴 수 있다(실측 8). 열한 체인 3/3은 **그 둘이 다 막혔다는 뜻**이고, M0이
증명할 것은 그것 하나다.

plan은 각 milestone 시작 시점에 따로 쓴다(`CLAUDE.md`).

## 위험

### 위험 1 — 결정 6의 `fish_greeting` 환경 변수가 안 먹을 수 있다

fish 소스가 아니라 **함수 스크립트를 읽고 추론한 것**이다. 안 먹으면 화면에
두 줄이 더 뜨고, 그 순간 화면을 grep하는 여섯 체인이 전부 위험해진다.

**SC-M0의 첫 일은 이것을 부팅해서 확인하는 것이다.** UT-M3의 교훈("착수 전
프로브가 계획을 넷 바꿨다")이 그대로 적용된다. 안 먹으면 대안은
`/etc/fish/config.fish`이고, 그때는 `machine/check.sh:117`의 마커를 함께
옮긴다(fish의 프롬프트가 시리얼 로그에 그대로 찍히므로 마커가 있다).

### 위험 2 — 결정 5의 마법사가 실제로는 안 뜰 수도 있다

실측 8은 zsh의 문서화된 동작과 sysroot의 파일 존재로부터 추론한 것이고,
**끊어진 링크를 zsh가 어떻게 보는지는 부팅해서 안 봤다.** 안 뜨면 `/.zshenv`는
불필요한 파일이 된다 — 해롭지는 않지만 근거 없는 파일이 initrd에 남는다.

**M0에서 `/.zshenv` 없이 `shell=zsh`로 한 번 띄워 본다.** 매달리면 넣고,
안 매달리면 결정 5를 철회하고 그 사실을 실측에 적는다.

### 위험 3 — rc가 깨지면 그것을 고칠 셸이 없다

CP가 `tars.conf`에 대해 만든 "설정 하나로 부팅이 막히지 않게 하는 세 장치"
(화이트리스트 · 모르는 값 무시 · 읽기 실패 시 덮어쓰지 않기)는 **rc에는 안
통한다.** rc는 우리가 파싱하는 것이 아니라 셸에게 통째로 넘기는 코드이고,
거기에 무엇이 들었는지 우리는 모른다.

결정 8·9가 이 위험에 대한 답이고, **SC-M2까지는 이 위험이 열려 있다.**
M0·M1 동안 rc를 깨뜨리면 탈출로는 호스트에서 ext2 이미지를 직접 고치는
것뿐이다. **M1의 씨앗이 무해한 이유가 여기에 있다** — 우리가 까는 것은
절대로 셸을 죽이지 않아야 한다.

### 위험 4 — 게이트가 길어진다

`config/check.sh`에 부팅이 하나 늘어 체인이 약 20초 길어지고, 게이트는
회차마다 그것을 세 번 돈다 — **약 +1분**. 착수 전 23분 43.15초에서 잡음
±3분 안이지만, GL이 네 milestone을 써서 줄인 값 위에 얹는 것이라 **적어
둔다.**

**열두번째 체인을 안 만드는 것이 이 위험을 이미 절반으로 줄인 선택이다** —
새 체인은 커널·init·terminal 빌드와 부팅 하나를 통째로 더하므로 +2분이다.
