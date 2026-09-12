# TARS Bash History Durability — Design

Date: 2026-09-12
Status: 완료(2026-09-12) — M0·M1·M2를 다 했다. 씨앗 rc의 bash 갈래가
`PROMPT_COMMAND='history -a'` 한 줄을 훅보다 먼저 담고, 호스트 검사 다섯이
그 줄과 그 자리를 지키고, 게이트의 7차 부팅이 중첩 bash 둘로 그 줄이
게스트에서 하는 일을 판정한다(`bneg0` · `baft1` · `bpos1`). 실측 열셋이 아래
있다.

M2가 계획에 없던 것을 하나 고쳤다 — 게스트에 `/dev/fd`가 없어서 씨앗의 fzf
훅이 부팅할 때 에러 한 줄을 찍고 있었다(실측 13 · 결정 9).

SD(Shell History Durability)가 zsh에 대해 한 일을 bash에 대해 한다. SD가
자기 비목표 1로 남긴 것이고, 그 비목표가 남긴 이유는 "bash에는 `setopt` 한
줄에 대응하는 것이 없다"였다. 이 문서는 그 대응물이 무엇인지 재서 정하고,
그것이 zsh의 한 줄과 어디에서 다르게 구는지를 적는다.

## 한 줄 요약

`shell=bash`인 기계에서 콘솔 셸에 친 명령은 전원 버튼과 함께 사라진다.
씨앗 rc의 bash 갈래에 `PROMPT_COMMAND='history -a'` 한 줄을 넣어, 히스토리
파일에 글자가 닿는 시점을 종료 경로에서 떼어 낸다.

## 왜 지금인가

SD가 zsh에 대해 고친 문제는 셸을 가리지 않는다. 파일에 글자가 닿는 시점이
"셸이 죽으면서 스스로 쓸 때"뿐이면, 그 시점이 오지 않는 종료 경로에서는
통째로 잃는다. 콘솔 셸이 정확히 그 경로에 있다 — 시그널 핸들러를 가진 주인이
없어서 SIGTERM을 무시한 채 3초를 버티다 SIGKILL에 죽는다(SD 실측 4·14).

이 문서를 열 때는 bash가 zsh보다 나쁠 것으로 보았다. SD 실측 7이 bash는
`exit`에서만 쓰고 SIGTERM과 SIGHUP 둘 다에서 안 쓴다고 쟀기 때문이다. zsh는
SIGHUP에서 쓰므로 화면 셸만큼은 우연히 살아남는데 bash는 그 우연조차 없다는
읽기였다.

BH-M0이 그 값을 정정했다. bash도 SIGHUP에서 쓴다(실측 10). SD의 하네스가
`script`의 래퍼에 시그널을 보내서 셸에 안 닿았던 것으로 보이고, 그래서
게스트에서 두 셸의 운명이 zsh와 같은 모양으로 갈린다 — 콘솔 0, 화면 1
(실측 8).

고칠 것은 그래도 같다. 콘솔 셸이 잃는다는 사실이 이 서브프로젝트의 전제이고,
그 전제는 실측 8이 게스트에서 직접 확인했다.

SD가 자기 값에 유보를 하나 달아 두었다. "Debian의 `/etc/bash.bashrc`가
`histappend`를 켜는 것에 기댈 수 있어서, bash를 정말로 고치는 사람은
게스트의 그 파일을 먼저 봐야 한다"였다. 착수 전 실측 1·2와 BH-M0의 실측 7이
그 유보를 지웠다 — 그 파일은 `histappend`를 켜지도 않고 게스트에 있지도
않다.

## 착수 전에 실측한 것 — 다시 조사하지 말 것

전부 2026-09-12에 `tars-devcontainer`(bash 5.2.37, aarch64)에서 쟀다.
하네스는 SD-M0과 같은 모양이다 — `script -qfc "bash -i"`에 fifo를 물리고
`exec 4<>`로 연다.

### 실측 1 — 게스트에는 `SYS_BASHRC`가 없다

게스트 `/etc`에 있는 것은 `passwd`와 `group` 둘뿐이다
(`kernel/make_initrd.sh:245~250`). bash가 컴파일할 때 정한 `SYS_BASHRC`는
`/etc/bash.bashrc`이고(바이너리 안에 그 문자열이 있다), 게스트에 그 파일이
없으므로 bash는 그냥 건너뛴다.

그래서 게스트 bash의 동작은 컴파일 기본값과 우리 씨앗 rc뿐이다. 컨테이너에서
잰 값을 게스트에 옮기려면 `/etc/bash.bashrc`를 비우고 재야 한다 — 아래 측정이
전부 그 조건이다.

### 실측 2 — Debian의 `/etc/bash.bashrc`에도 `histappend`는 없다

컨테이너의 그 파일(1,997바이트)에서 주석을 뺀 실행 줄은 `checkwinsize` ·
`debian_chroot` · `PS1` · `command_not_found_handle`뿐이다. `hist`로 걸리는
줄은 주석 하나(`PROMPT_COMMAND` 예시)다.

그러므로 SD 실측 7의 값은 시스템 rc가 도운 값이 아니라 bash의 순수 기본값이다.
Debian이 `histappend`를 켜는 자리는 `/etc/skel/.bashrc`이고, 그것은 사용자 홈에
복사되는 파일이라 게스트와는 상관이 없다 — 게스트의 `~/.bashrc`는
`/config/bashrc`로 가는 링크다(`make_initrd.sh:228`).

### 실측 3 — `PROMPT_COMMAND='history -a'`는 명령마다 쓴다

중첩 세션 둘로 쟀다. 씨앗을 흉내 낸 rc(주석 · alias · 그 한 줄)를 읽는
세션 안에서 `bash`를 쳐서 자식 세션을 띄우고, 하나는 `PROMPT_COMMAND=`로
훅을 끄고 다른 하나는 그대로 둔다.

| 시점 | 파일의 줄 수 |
|---|---|
| 기동 직후 | 파일 없음 |
| 바깥 세션이 `echo outer_one`을 쳤다 | 1 |
| 중첩 세션 기동 | 1 |
| 중첩이 `PROMPT_COMMAND=`를 쳤다 | 1 |
| 중첩이 `echo negmark=1`을 쳤다 | 1 |
| 중첩이 나갔다 | 7 |
| 둘째 중첩 기동 | 8 |
| 둘째 중첩이 `echo posmark=1`을 쳤다 | 9 |

훅을 끈 세션은 살아 있는 동안 한 줄도 안 쓰고, 훅이 켜진 세션은 친
그 자리에서 쓴다. SD 실측 11과 같은 모양이고 같은 결론이다 — 음성 대조군이
성립하고, 음성 판정은 그 세션이 살아 있는 동안 해야 한다. 나간 뒤에 세면
1에서 7로 뛰는 자리에 걸린다.

### 실측 4 — 쓰는 타이밍이 zsh와 다르다. 자기 명령줄은 아직 없다

SD 실측 24가 zsh에 대해 "`grep` 명령줄이 실행 전에 파일에 써지므로 판정
패턴에 앵커를 붙여야 한다"를 남겼다. bash는 그렇지 않다.

| 친 명령 | 화면 |
|---|---|
| `echo neg$(grep -cx "echo negmark=1" $H)` | `neg0` |
| `echo nega$(grep -c negmark $H)` | `nega0` |
| `echo pos$(grep -cx "echo posmark=1" $H)` | `pos1` |
| `echo posa$(grep -c posmark $H)` | `posa2` |

음성에서 앵커를 빼도 0이다. `history -a`가 `PROMPT_COMMAND`에서 도는데, 그
자리는 명령이 끝난 뒤 다음 프롬프트를 그리기 직전이라 실행 중인 명령은 아직
파일에 없다. 양성의 `posa2`는 자기 줄이 아니라 앞선 두 줄
(`echo posmark=1`과 그것을 세는 `echo pos$(...)`)을 센 값이다.

앵커는 그래도 붙인다. 이유가 "자기를 센다"에서 "앞선 줄을 센다"로 바뀔 뿐,
앵커 없는 패턴이 의도한 것보다 많이 세는 것은 같다.

### 실측 5 — 오타가 비대화형에서는 안 보이고 대화형에서는 프롬프트마다 보인다

이것이 이 서브프로젝트에서 가장 값진 측정이다.

`bash -c '<줄>'`로 stdout과 stderr를 센 값이다.

| 줄 | stdout | stderr |
|---|---|---|
| `PROMPT_COMMAND='history -a'` | 0 | 0 |
| `shopt -s histappend` | 0 | 0 |
| `PROMPT_COMMAND='histori -a'`(일부러 낸 오타) | 0 | 0 |

셋이 같다. `bash -c`는 비대화형이라 `PROMPT_COMMAND`를 아예 실행하지 않기
때문이다.

같은 오타를 대화형 세션에서 재면 다르다. 명령 셋(`echo one` · `echo two` ·
`exit`)을 친 세션의 화면 전체가 이렇게 나온다.

| rc의 줄 | 화면 바이트 |
|---|---|
| `PROMPT_COMMAND='history -a'` | 123 |
| `PROMPT_COMMAND='histori -a'` | 225 |

늘어난 102바이트는 `bash: histori: command not found` 세 줄이다. 한 번이
아니라 프롬프트가 그려질 때마다 찍는다.

zsh의 `setopt` 오타는 기동할 때 1회 stderr 65바이트였다(SD 실측 9).
bash의 오타는 계속 찍으므로 더 나쁘고, 무엇보다 SD 결정 4가 못 박아 둔
검증 절차로는 안 잡힌다. 그 절차가 "`bash -c`로 0바이트인 것을 재고
`KNOWN_HIST_OPTIONS`에 적어라"이기 때문이다. 결정 5가 이것을 고친다.

### 실측 6 — `zoxide init bash`가 `PROMPT_COMMAND`를 앞에 붙인다

zoxide 0.9.7의 `init bash` 출력은 151줄이고, 그중 `PROMPT_COMMAND`를
건드리는 자리가 이렇다.

```bash
if [[ ${PROMPT_COMMAND:=} != *'__zoxide_hook'* ]]; then
    PROMPT_COMMAND="__zoxide_hook;${PROMPT_COMMAND#;}"
fi
```

기존 값을 보존하며 앞에 붙인다. 그래서 씨앗에서 줄의 순서가 결과를 가른다.

| 씨앗의 순서 | 최종 `PROMPT_COMMAND` | 결과 |
|---|---|---|
| 우리 줄이 먼저, 훅이 나중 | `__zoxide_hook;history -a` | 둘 다 산다 |
| 훅이 먼저, 우리 줄이 나중 | `history -a` | zoxide 훅이 죽는다 |

zsh에는 없던 축이다. `setopt`는 다른 줄과 안 부딪치는데 `PROMPT_COMMAND`는
하나뿐인 변수라 마지막 대입이 이긴다. 결정 3이 이것이다.

arm64 패키지로 쟀다. 게스트의 zoxide는 amd64라 컨테이너에서 못 돌지만
(`project_build_host_arch`), `init bash`가 뱉는 것은 아키텍처와 무관한 셸
스크립트다. 같은 버전인 것은 `devcontainer/Dockerfile:181`이 `zoxide:amd64`를
같은 trixie 스냅샷에서 받는 것으로 확인한다. 게스트에서 다시 확인하는 것은
BH-M0의 일이다.

## 소스를 읽어 얻은 것 — 실측과 섞지 않는다

### 확인 1 — 자리는 이미 뚫려 있다

`config.zig:251`의 `histOptionLines()`가 셸 셋의 갈래를 이미 갖고 있고 bash가
빈 목록이다. `HIST_OPTIONS_ZSH` 옆에 `HIST_OPTIONS_BASH`를 두면 된다.
`histEntries()`도 이미 bash 갈래를 갖고 있다(`HISTFILE=/config/bash_history` ·
`HISTSIZE=5000`).

### 확인 2 — 허용 목록에 새 범주가 필요하지 않다

`expectQuietSeed`가 통과시키는 것은 주석(`#`) · `alias `(접두사) ·
`hookLines()`의 한 줄과 정확히 같은 줄 · `histOptionLines()`의 한 줄과 정확히
같은 줄이다(`config_test.zig:151~188`). `PROMPT_COMMAND=...`는 넷째로 들어간다 —
`histOptionLines()`가 그 줄을 담으면 검사가 저절로 통과시킨다.

SD 비목표 1이 "허용 목록을 한 범주 더 넓히는 일"이라고 적어 두었는데,
소스를 읽으면 그렇지 않다. 넓힐 것은 범주가 아니라 목록의 원소다.

### 확인 3 — 순서를 보는 검사가 없다

`expectQuietSeed`는 씨앗을 줄 단위로 훑으며 "이 줄이 허용되는가"만 본다.
어느 줄이 어느 줄보다 먼저 오는지는 안 본다. 실측 6이 순서를 요구하므로
검사가 하나 더 필요하다. 결정 4다.

### 확인 4 — 게이트가 bash 씨앗을 보는 자리는 로그 한 줄뿐이다

`config/check.sh:918`이 1차 부팅 로그에서 `tars-init: seeded /config/bashrc`를
찾는 것이 전부다. 열한 체인 중 bash로 부팅하는 것이 하나도 없다 —
`input/check.sh`가 `/usr/bin/bash --norc`를 타이핑하는데 `--norc`라서 씨앗을
안 읽는다.

그래서 "이 줄이 게스트에서 일한다"를 게이트가 보게 하려면 부팅을 더하거나
중첩 셸을 쓰거나 둘 중 하나다. 결정 6이 고른다.

### 확인 5 — `shell_config=off`는 bash에 `--norc`를 준다

`config.zig`의 `noConfigFlag()`가 bash에 주는 것이 `--norc`다. zsh의 `-f`와
같은 자리이고, 같은 이유로 "사용자 rc와 독립된 파일에 훅만 둔다"는 후보에
이점이 없다. 결정 2가 이 사실 위에 선다.

## 결정

### 결정 1 — 훅은 `PROMPT_COMMAND='history -a'` 하나다

후보가 둘이었다.

`shopt -s histappend`는 아니다. 그 옵션이 정하는 것은 셸이 끝날 때 파일을
덮어쓸 것인가 이어 쓸 것인가이고, 쓰는 시점을 안 옮긴다. 우리가 지려는
싸움은 "끝날 때가 아예 안 온다"이므로 이 옵션은 그 자리에 없다. 그리고
`history -a`는 언제나 append라서 함께 켤 이유도 없다.

`PROMPT_COMMAND='history -a'`가 실측 3에서 명령마다 쓰는 것을 보였다. 살아
있는 동안 이미 파일에 있으므로 SIGKILL에도 남는다 — SD 실측 6이 zsh에 대해
같은 논리를 썼다.

`history -a`가 쓰는 것은 "이번 세션에서 아직 안 쓴 줄"이고, 쓴 뒤에는 그
표시를 옮긴다. 그래서 매번 전체를 다시 쓰지 않는다.

### 결정 2 — 그 줄은 씨앗 rc에 둔다

`setopt`와 같은 자리다. `PROMPT_COMMAND`를 나르는 환경 변수가 없으므로
`environ.zig`로는 못 준다. 독립 파일로 빼는 것은 확인 5가 지운다 —
`shell_config=off`이면 `--norc`라서 어느 rc도 안 읽힌다.

### 결정 3 — 씨앗에서 그 줄은 훅 줄보다 먼저 온다

실측 6이 근거다. 우리 줄이 뒤에 오면 `zoxide init bash`가 건 `__zoxide_hook`을
통째로 지우고, 증상은 "히스토리는 남는데 `z`가 아무 디렉터리도 안 배운다"가
된다. 조용해서 나쁘다.

반대 순서에는 단점이 없다. zoxide가 우리 값을 보존하며 앞에 붙이므로
`__zoxide_hook;history -a`가 되고 둘 다 돈다.

`command -v zoxide` 관문이 막아서 훅이 안 돌 때도 우리 줄은 그대로 남는다.
게스트에 zoxide가 있는 것은 UT-M2가 넣은 사실이지만, 이 순서는 없을 때도
맞다.

### 결정 4 — 그 순서를 검사가 못 박는다

확인 3이 근거다. 순서는 코드를 보면 맞는데, 씨앗을 고치는 사람이 줄을
옮기면 조용히 깨진다. `config_test.zig`에 검사를 하나 더 둔다.

검사가 보는 것을 고를 때 한 번 틀렸다가 고쳤다. 처음에는 "`histOptionLines()`의
모든 줄이 `hookLines()`의 모든 줄보다 앞선다"로 적었는데, 소스를 읽으니 zsh
씨앗의 `setopt INC_APPEND_HISTORY`가 훅 두 줄보다 뒤에 있다
(`config.zig:369~377`). 셸 셋에 그대로 걸면 zsh가 그 자리에서 빨개진다.

zsh 씨앗을 옮기는 것은 안 한다. 순서를 요구하는 근거는 "옵션 줄이라서"가
아니라 "`PROMPT_COMMAND`가 하나뿐인 변수라서"이고, `setopt`는 다른 줄과 안
부딪친다. 옮기면 규칙과 근거가 어긋난 채로 남는다.

그래서 검사는 이렇게 읽는다 — 씨앗에서 `PROMPT_COMMAND`를 건드리는 줄이
있으면, 그 줄은 그 셸의 모든 훅 줄보다 앞선 줄 번호에 있어야 한다.

셸 셋 전부에 건다. 지금 대상이 있는 것은 bash 하나지만, 이 모양이면 나중에
누가 zsh나 fish 씨앗에 `PROMPT_COMMAND`를 넣어도 같은 못에 걸린다 —
위험 3이 말하는 것이 정확히 그 경우다.

### 결정 5 — 새 줄을 들이는 검증 절차를 고친다

SD 결정 4가 `KNOWN_HIST_OPTIONS`의 머리 주석에 이렇게 적어 두었다.

> 새 `setopt` 줄을 씨앗에 넣으려면 먼저 SD 실측 9와 같은 방법으로 그
> 줄의 stdout·stderr가 0바이트인 것을 재고 여기 적어야 한다.

실측 5가 그 절차를 무력화한다. `bash -c`로 재면 오타 난 `PROMPT_COMMAND`도
0바이트다. 절차를 "대화형 세션의 화면 바이트를 재라"로 고치고 그 이유를
주석에 적는다.

이것은 코드를 안 바꾸는 결정이다. 바꾸는 것은 주석이고, 바꾸는 이유는 다음에
이 자리를 여는 사람이 잘못된 절차를 그대로 따르지 않게 하기 위함이다.

### 결정 6 — 게이트 판정은 7차 부팅의 중첩 bash로 한다

확인 4가 선택지 둘을 놓았다.

9차 부팅을 더하는 쪽은 정확하다. `shell=bash`로 진짜로 띄우므로 env도 rc도
production과 같다. 대신 체인이 부팅 하나만큼 길어지고, 게이트는 그것을 세 번
돈다. config 체인이 지금 1분 36초이고 부팅 하나가 10초쯤이라 게이트에 30초가
붙는다.

중첩 bash를 쓰는 쪽이 싸다. 7차 부팅은 이미 zsh로 떠 있고 중첩 zsh 둘을
띄우고 있다. 거기에 `bash`를 한 번 더 치면 그 셸이 `~/.bashrc`를 읽는다 —
그 링크의 실체가 `/config/bashrc`이므로 씨앗 그대로다.

production과 다른 것이 하나다. env의 `HISTFILE`이 zsh용
(`/config/zsh_history`)이라 중첩 bash가 그 파일에 평문을 섞는다. 중첩 세션의
첫 명령으로 `HISTFILE=/config/bash_history`를 치면 production과 같아진다.
한 줄 더 치는 값으로 부팅 하나를 아낀다.

중첩 쪽을 고른다. 대신 "이 판정이 보는 것은 씨앗 rc이지 `shell=bash`인
기계의 env가 아니다"를 체인 주석에 적는다. env 쪽은 SM-M2가 이미 보고
있다(`tars-init: env HISTFILE=`).

판정 글자는 SD-M2의 모양을 그대로 쓴다 — 음성 `bneg0` · 중간 `baft1` ·
양성 `bpos1`. 앞에 `b`를 붙이는 것은 7차가 이미 `neg0`·`aft1`·`pos1`을
쓰고 있기 때문이다. `wait_for_screen`이 마지막 프레임이 아니라 로그 전체를
보므로(실측 26), 같은 글자를 두 번 쓰면 뒤엣것이 앞엣것에 걸린다.

### 결정 7 — bash만 고친다

zsh는 SD가 끝냈다. fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이
애초에 없다(SD 실측 8).

### 결정 8 — PID 1의 시그널 경로는 안 건드린다

SD 결정 8과 같다. 대화형 셸이 SIGTERM을 무시하는 것을 고치는 길
(PID 1이 SIGHUP을 보내는 것)은 PM·BF 체인이 보는 종료 로그와 감독 루프의
계약을 다시 여는 일이라 이 서브프로젝트의 크기가 아니다. 그 일은 SD 비목표 8로
남아 있고 여기서도 남긴다.

## 비목표

1. 종료가 늘 3초 걸리는 것. SD 비목표 8을 그대로 이월한다(결정 8).
2. `HISTSIZE`·`HISTFILESIZE` 값을 바꾸는 것. SM 결정 4가 5,000으로 정했고
   bash는 `HISTFILESIZE`를 안 줘도 그 수로 파일까지 자른다(SM 실측 37).
3. 배열 형태의 `PROMPT_COMMAND`(bash 5.1+). 게스트 bash가 5.2라 쓸 수는
   있지만, zoxide가 `${PROMPT_COMMAND:=}`로 문자열 확장을 하므로 섞으면
   첫 원소만 보게 된다. 문자열 하나로 둔다.
4. bash 프롬프트를 꾸미는 것. SD 비목표 5와 같은 이유다 — 씨앗은 아무것도
   찍지 않는다.
5. 이미 설정 디스크를 가진 기계에 새 줄을 밀어 넣는 것. 씨앗은 파일이 없을
   때만 깔린다(SD 확인 5). 게이트는 7차를 위해 rc를 지우므로 영향이 없다.
6. `shell=bash`로 게이트를 한 회차 더 도는 것. 결정 6이 중첩으로 갈음한다.

## Milestone 셋

SD와 같은 모양이다. 측정 · 씨앗과 호스트 검사 · 게이트 판정.

### BH-M0 — 게스트에서 재고 컨테이너 값을 옮겨도 되는지 본다

착수 전 실측 여섯은 전부 컨테이너에서 잰 값이다. 게스트에서 확인할 것이 셋
있다.

1. 게스트 bash도 `/etc/bash.bashrc`를 안 읽는가(실측 1의 게스트 확인).
2. `shell=bash`로 부팅한 게스트에서 전원 버튼을 누르면 콘솔 셸의 히스토리가
   실제로 사라지는가. SD 실측 14의 bash 판이다 — 고치기 전의 값을 먼저
   손에 쥔다.
3. 게스트의 zoxide(amd64 0.9.7)가 실측 6과 같은 `PROMPT_COMMAND` 취급을
   하는가.

### BH-M1 — 씨앗 한 줄과 호스트 검사

`config.zig`에 `HIST_OPTIONS_BASH`를 두고 `histOptionLines()`의 bash 갈래가
그것을 돌려준다. 씨앗 `rcSeed()`의 bash 갈래가 그 글자를 따로 한 벌 더 적되
훅 두 줄보다 먼저 적는다(결정 3).

`config_test.zig`에 `KNOWN_HIST_OPTIONS`의 원소를 더하고, 순서를 보는 검사를
새로 둔다(결정 4). `KNOWN_HIST_OPTIONS`의 머리 주석을 결정 5대로 고친다.

되돌림 다섯으로 검사가 일하는 것을 확인한다 — 씨앗의 그 줄을 다른 글자로 ·
씨앗에서만 지우기 · 씨앗과 목록에서 함께 지우기 · 둘을 함께 오타로 ·
씨앗에서 순서를 뒤집기. 다섯이 각각 다른 줄에서 죽어야 한다.

### BH-M2 — 게이트가 그 줄을 본다

`config/check.sh` 7차 부팅에 중첩 bash 둘을 더한다. 판정 글자는
`bneg0` · `baft1` · `bpos1`이다(결정 6).

8차의 판정 글자가 또 밀릴 수 있다. SD-M2가 7차에 중첩 zsh 둘을 더하면서 8차의
판정을 `whence -w fzf-history-widget`에서 `posmark=1`로 옮겼는데, 그 이유가
`history`가 최근 16개만 찍는 것이었다. 7차에 중첩 셸이 둘 더 붙으면 그 창이
또 밀린다. M2는 이 수를 먼저 세고 시작한다.

반사실로 값을 증명한다. 씨앗에서 그 줄만 뺀 사본을 마운트하면 체인이 7차에서
죽어야 한다. 호스트 검사가 먼저 죽이므로 마운트가 둘 필요하다는 것은 SD-M2가
배운 것이고(`config_test.zig`의 역방향 loop 한 줄도 함께 눕힌다), 여기서는
순서 검사까지 있으므로 눕힐 자리가 하나 더 있을 수 있다.

## BH-M0이 실행으로 증명한 것

plan: `docs/superpowers/plans/2026-09-12-tars-bash-history-durability-bh-m0.md`

실측 7·8·9는 게스트를 세 번 부팅해서 쟀다. 실측 10은 컨테이너에서 쟀고,
실측 8의 결과를 설명하려다 나왔다.

### 실측 7 — 게스트에 `SYS_BASHRC`가 없다. 경로는 맞다

`ls -a /etc`의 출력이 `.` · `..` · `group` · `passwd` 넷이다. 착수 전 실측 1이
소스로 본 것과 같다.

경로가 맞는지도 함께 쟀다. 게스트에서 `/etc/bash.bashrc`를 만들어
`echo BHSYSRCWASREAD` 한 줄을 넣고 bash를 둘 띄웠다 — 비대화형
(`bash -c true`)과 대화형(`bash -i -c true`)이다. 그 글자가 한 번만 찍혔다.
경로는 `/etc/bash.bashrc`가 맞고, 읽는 것은 대화형일 때뿐이다.

`/etc`는 tmpfs라 그 파일이 이 부팅에서만 살고 다음 부팅에 안 따라간다.
측정이 게스트 상태를 안 더럽힌다.

### 실측 8 — 콘솔 셸이 잃고 화면 셸이 남는다. zsh와 같은 모양이다

`shell=bash`로 부팅한 게스트에서 콘솔 셸에 `echo bhconsolemarker`를 치고,
화면 셸에 `sendkey`로 `echo bhscreenmarker`를 친 뒤 `system_powerdown`을
눌렀다. 다시 부팅해 `/config/bash_history`를 읽었다.

| | 값 |
|---|---|
| 파일이 있는가 | `BHFILE=yes` |
| 콘솔 셸의 마커 | `BHCON=0` |
| 화면 셸의 마커 | `BHSCR=1` |

파일 전체가 `echo bhscreenmarker` 한 줄이다. 콘솔 셸이 친 것은 하나도 없다.

"안 쳐졌다"와 "잃었다"를 먼저 갈랐다. 콘솔 쪽은 `bhconsolemarker` 에코가
시리얼 로그에 있고, 화면 쪽은 `terminal: key>` 줄이 20개로 보낸 키 수와
정확히 같다(`e c h o spc b h s c r e e n m a r k e r ret`). 둘 다 분명히
쳐졌다.

종료 경로도 확인했다 — `sent SIGTERM` · `grace period expired (reaped 2)` ·
`sent SIGKILL` · `calling reboot(POWER_OFF)`가 전부 로그에 있다.

이 값이 SD 실측 14(zsh — 콘솔 0, 화면 1)와 글자 그대로 같다. 이 문서가
예상한 "둘 다 0"이 아니다. 왜 화면 셸이 남았는지를 실측 10이 답한다.

### 실측 9 — 게스트 zoxide도 `PROMPT_COMMAND`를 앞에 붙인다

게스트의 zoxide는 0.9.7이고, `zoxide init bash | grep -n PROMPT_COMMAND`의
출력이 착수 전 실측 6과 글자 그대로 같다.

```
39:if [[ ${PROMPT_COMMAND:=} != *'__zoxide_hook'* ]]; then
40:    PROMPT_COMMAND="__zoxide_hook;${PROMPT_COMMAND#;}"
46:    [[ ${PROMPT_COMMAND:=} != *'__zoxide_hook'* ]] || return 0
```

arm64로 잰 값을 amd64 게스트에 옮겨도 되는 것이 확인됐다. 결정 3의 순서는
그대로 선다.

### 실측 10 — bash는 SIGHUP에서 쓴다. SD 실측 7이 틀렸다

실측 8이 예상과 어긋나서 컨테이너에서 다시 쟀다. `SYS_BASHRC`를 비운 조건
(`: > /etc/bash.bashrc`)에서 대화형 bash를 다섯 번 띄우고 각각 다르게
끝냈다.

| 끝나는 방법 | bash가 살아남았나 | 히스토리 |
|---|---|---|
| `exit` | 죽었다 | 써진다 |
| SIGHUP을 셸에 직접 | 죽었다 | 써진다 |
| SIGTERM을 셸에 직접 | 살아 있다 | 파일이 없다 |
| SIGKILL을 셸에 직접 | 죽었다 | 파일이 없다 |
| PTY 주인을 SIGTERM | 죽었다 | 파일이 없다 |

SIGHUP 행이 SD 실측 7과 다르다. bash는 SIGHUP에서 쓴다. 그래서 실측 8의
화면 셸이 남은 것이 설명된다 — `terminal`이 SIGTERM에 죽고 PTY가 닫히면서
안쪽 bash가 SIGHUP을 받는다.

SIGTERM 행은 HANDOFF 실측 22와 같다. 대화형 셸은 자기에게 온 SIGTERM을
무시하고 살아남는다. 콘솔 셸이 잃는 이유가 이 한 칸이다 — 무시한 채 3초를
버티다 SIGKILL에 죽고, SIGKILL 칸에는 쓸 기회가 없다.

이 표를 얻기까지 회차 둘을 설계 오류로 버렸고, 버린 이유가 다음 사람에게
값지다.

첫 회차는 정리 코드가 측정을 오염시켰다. 시그널을 보낸 뒤 `kill -KILL`로
PTY 주인을 치우고 나서 파일을 읽었는데, 그 정리 자체가 PTY를 닫아 SIGHUP을
만든다. 다섯 칸이 전부 "써진다"로 나왔고 SIGKILL 칸까지 그랬다 — 핸들러가
없는 시그널이 정리 동작을 할 수 없으므로 그 한 칸이 오류의 증거였다.

둘째 회차는 시그널이 셸에 안 닿았다. `script -qfc "bash -i"`는 `bash`를 바로
띄우지 않고 `sh -c "bash -i"` 래퍼를 하나 끼운다. 자식 pid를 찾으면 그 래퍼가
잡히고, 거기에 시그널을 보내면 래퍼가 죽으면서 `script`도 끝나 PTY가 닫힌다 —
결과가 또 전부 SIGHUP이 된다. 처방은 `script -qfc "exec bash -i"`이고, 진단은
`/proc/<pid>/cmdline`을 함께 찍는 것이다.

SD 실측 7이 틀린 것도 같은 함정으로 보인다. 그 하네스가 `exec` 없는
`script -qfc "zsh -i"` 모양이었다.

## BH-M1이 넣은 것 (끝났다)

plan: `docs/superpowers/plans/2026-09-12-tars-bash-history-durability-bh-m1.md`

`config.zig`에 `HIST_OPTIONS_BASH`가 섰고 `histOptionLines()`의 bash 갈래가
그것을 돌려준다(zsh 1 · bash 1 · fish 0). 씨앗 `rcSeed()`의 bash 갈래가 그
글자를 따로 한 벌 더 적되 훅 두 줄보다 먼저 적는다 — 씨앗에서 그 줄이
366번, zoxide 훅이 371번이다.

`config_test.zig`는 `KNOWN_HIST_OPTIONS`에 원소를 하나 더 받았고,
`expectHistOptions`의 bash 개수가 0에서 1이 됐고, 새 검사
`expectPromptCommandBeforeHooks`가 섰다. `KNOWN_HIST_OPTIONS`의 머리 주석이
결정 5대로 바뀌었다 — 재는 방법이 셸마다 다르다는 것을 그 자리에 적었다.

`config.zig`가 +37 −6, `config_test.zig`가 +86 −12다. 지운 18줄은 전부 낡은
주석과 `.bash => 0` 두 줄이다.

### 되돌림 다섯이 각각 다른 줄에서 죽었다

이것이 검사가 값을 한다는 증거다.

| | 무엇을 망가뜨렸나 | 죽은 자리 | 에러 |
|---|---|---|---|
| 1 | 씨앗의 그 줄만 오타로 | `expectQuietSeed` 정방향 | `BadSeed` |
| 2 | 씨앗에서만 지우기 | `expectQuietSeed` 역방향 | `BadSeed` |
| 3 | 씨앗과 `HIST_OPTIONS_BASH`에서 함께 지우기 | `expectHistOptions` 개수 | `BadHistOption` |
| 4 | 둘을 함께 오타로 | `KNOWN_HIST_OPTIONS` | `BadHistOption` |
| 5 | 씨앗에서 훅 두 줄 아래로 옮기기 | `expectPromptCommandBeforeHooks` | `BadSeedOrder` |

5번의 메시지가 이 milestone이 새로 얻은 것이다.

```
FAIL: the bash seed assigns PROMPT_COMMAND on line 38, after its first hook on line 36
      that assignment wipes the zoxide hook; move it above the hooks
```

### 실측 11 — 복사해 온 `.zig-cache`는 소스 변경을 가린다

되돌림 회차를 통째로 한 번 버리고 얻은 값이다.

되돌림 다섯을 한 컨테이너 안에서 돌리려고 `cp -r /workspace/init /tmp/w`로
복사한 뒤 거기서 소스를 바꿔 가며 `zig build test`를 돌렸다. 다섯이 전부
`PASS`로 나왔다 — 검사가 안 죽은 것이 아니라 새 코드가 아예 안 돌았다.
`init/.zig-cache`와 `zig-out`이 함께 복사되면서 zig가 옛 산출물을 다시
실행했다.

증상이 나쁘다. 에러도 경고도 없고, `PASS` 한 줄이 정상 통과와 글자 그대로
같다. 되돌림 검증에서 이것이 나면 "검사가 값을 안 한다"로 읽히므로 결론이
정확히 거꾸로 뒤집힌다.

처방은 복사 직후 `rm -rf .zig-cache zig-out` 한 줄이다. 같은 자리에서 소스만
바꾸는 것은 zig가 정상으로 감지하므로, 회차마다 지울 필요는 없고 복사 직후
한 번이면 된다.

`project_zig_out_staleness`의 처방("음성 확인 전에 캐시를 지운다")과 같은
뿌리인데, 그 기억은 같은 자리에서 빌드하는 경우를 적었고 이쪽은 캐시를 다른
디렉터리로 옮기는 경우다.

### config 체인은 안 길어졌다

부팅 여덟이 1분 35.77초에 `FAIL` 없이 끝났다. SD-M2의 1분 36.42초와 같다 —
M1이 타이핑을 안 더했으므로 안 늘어야 맞다. 씨앗이 열한 줄 커졌는데 화면
좌표를 보는 검사가 하나도 안 밀렸다.

그 초록이 "그 줄이 게스트에서 일한다"를 뜻하지는 않는다. 게이트에는 아직
bash로 뜨는 자리가 없다(확인 4). 그것을 세우는 것이 BH-M2다.

## BH-M2가 넣은 것 (끝났다)

plan: `docs/superpowers/plans/2026-09-12-tars-bash-history-durability-bh-m2.md`

`config/check.sh` 7차 부팅이 중첩 bash 둘을 띄운다. 둘 다 같은 씨앗 rc를
읽고, 다른 것은 음성이 첫 명령으로 `PROMPT_COMMAND=`를 치는 것 하나뿐이다.
판정 셋이 화면의 글자다.

```
(none)# bash
bash-5.2# HISTFILE=/config/bash_history
bash-5.2# PROMPT_COMMAND=
bash-5.2# bnegmark=1
bash-5.2# echo bneg$(grep -cx bnegmark=1 /config/bash_history)
bneg0                                   ← 훅을 끈 세션은 안 쓴다
bash-5.2# exit
(none)# echo baft$(grep -cx bnegmark=1 /config/bash_history)
baft1                                   ← 그 명령은 분명히 쳐졌다
(none)# bash
bash-5.2# HISTFILE=/config/bash_history
bash-5.2# bposmark=1
bash-5.2# echo bpos$(grep -cx bposmark=1 /config/bash_history)
bpos1                                   ← 씨앗의 훅이 그 자리에서 쓴다
```

bash 판정이 zsh 판정보다 앞에 있다. bash 중첩 안에서 친 것은 zsh 히스토리에
안 들어가므로 7차가 zsh 파일에 더하는 것은 세 줄뿐인데(`bash` 둘과
`echo baft`), 그 셋이 `posmark=1` 뒤에 오면 8차의 `history` 16줄 창에서 그
글자를 민다. 앞에 두어 `posmark=1`을 파일 끝에서 두 번째에 남겼다.

config 체인 단독이 1분 52.64초다(M1의 1분 35.77초에서 +16.9초. 7차에 타이핑이
200키쯤 늘어난 값이다).

### 실측 12 — `history -a`를 쓰는 세션은 나가면서 남의 줄을 안 지운다

M2에 들어가기 전에 결정 1을 한 번 의심했다. bash는 `histappend`가 꺼져
있으면 종료할 때 `$HISTFILE`을 자기 메모리 목록으로 덮어쓰므로, 다른 세션이
써 둔 줄을 지울 수 있어 보였다 — SD 실측 10이 zsh의 `fc -W`에 대해 잰 것과
같은 구조다.

세션 둘이 같은 `HISTFILE`을 보게 하고 한쪽을 `exit`으로 내보냈다.

| `histappend` | A가 나가기 전 | A가 나간 뒤 |
|---|---|---|
| 꺼짐 | `amark=1` · `bmark=1` | `amark=1` · `bmark=1` |
| 켜짐 | `amark=1` · `bmark=1` | `amark=1` · `bmark=1` |

안 지운다. `history -a`가 이미 append해 두면 bash가 종료 시 다시 쓸 것이
없기 때문이다. 결정 1("`histappend`는 안 쓴다")이 그대로 선다.

### 실측 13 — 게스트에 `/dev/fd`가 없었다. 씨앗이 그래서 한 줄을 찍고 있었다

M2가 계획에 없이 찾은 것이고, 이 milestone에서 가장 값진 발견이다.

7차에 중첩 bash를 띄우자 화면이 이렇게 나왔다.

```
(none)# bash | HISbash: /dev/fd/63: No such file or directory | TF...bash-5.2# HISTFI
```

`bash`를 친 직후 씨앗의 fzf 훅이 에러 한 줄을 찍고, 그 사이에 `HISTFILE=`
타이핑이 끼어들어 `HIS` · `TF` · `HISTFI`로 쪼개졌다. 그 회차는 결국
통과했지만 운이었다.

원인이 셋으로 나뉜다.

1. `fzf --bash` 출력의 마지막 줄이 최상위에서 process substitution을 돈다 —
   `__fzf_orig_completion < <(complete -p …)`. 함수 안이 아니라 `eval`하는
   그 자리에서 실행된다.
2. process substitution은 `/dev/fd/63` 같은 경로를 연다.
3. 게스트에 `/dev/fd`가 없다. devtmpfs는 드라이버가 등록한 장치 노드만
   담고, 보통 그 링크를 만들어 주는 udev나 init 스크립트를 우리는 안 쓴다.

이 한 줄이 씨앗의 규칙을 깬다 — 우리가 까는 rc는 부팅할 때 아무것도 안
찍어야 하고, 그 규칙을 지키려고 `expectQuietSeed`가 있다. 그런데 그 검사는
글자를 보지 실행을 안 해 본다.

SM-M1이 그 훅을 넣을 때 잰 "관문이 있으면 셋 다 0바이트"(SM 실측 23)도
컨테이너에서 잰 값이었다. 컨테이너에는 `/dev/fd`가 있다. BH 실측 5·10이
드러낸 것과 같은 종류다 — 컨테이너 값을 게스트 값으로 읽으면 틀린다.

게이트가 이것을 오래 못 본 이유는 열한 체인 중 bash로 뜨는 것이 하나도
없었기 때문이다(확인 4). `input/check.sh`가 bash를 치기는 하는데 `--norc`라
씨앗을 안 읽는다.

### 결정 9 — `/dev/fd` 링크는 init이 만든다 (M2에서 더했다)

고칠 자리가 둘이었다. bash의 fzf 훅을 바꾸는 것과, 없는 링크를 만드는 것이다.

링크를 만든다. 보통의 리눅스 시스템에 있는 것이 우리 게스트에 없는 것이
결함이고, 훅을 바꾸면 그 결함이 다음 도구에서 또 드러난다.

`main.zig`에 `linkDevFd()`가 서서 `/proc`과 `/dev`가 둘 다 붙은 뒤
`symlink("/proc/self/fd", "/dev/fd")`를 한다. 로그 한 줄
(`tars-init: linked /dev/fd to /proc/self/fd`)을 찍고 `config/check.sh`의 1차
부팅이 그 줄을 본다.

이것이 BH의 범위를 넘는다는 반론이 가능하다. 넘지 않는다고 본 이유는
M2의 검사가 그 에러와 같은 화면에서 돌기 때문이다 — 안 고치면 이
milestone이 세운 판정 셋이 타이밍에 따라 흔들린다.

### 중첩 bash는 프롬프트로 기다릴 수 있다

같은 화면이 가르쳐 준 것이 하나 더 있다. 중첩 zsh는 프롬프트가 바깥과 같아서
"떴는가"를 아무것도 못 가르는데(SD 실측 12), bash는 `bash-5.2#`로 바뀐다.
그래서 첫 중첩 뒤에 `wait_for_screen 'bash-5\.2#'`를 넣어 rc를 다 읽을
때까지 기다린다.

둘째 중첩에는 못 넣는다. `wait_for_screen`은 마지막 프레임이 아니라 로그
전체를 보므로(HANDOFF 실측 26) 같은 글자가 앞선 프레임에 이미 있다. 대신
둘째가 흔들리면 `bpos`가 숫자 없이 나와 검사가 죽으므로 조용하지는 않다.

### 반사실 — 씨앗에서 그 줄만 빼면 7차가 죽는다

마운트가 둘 필요하다. 씨앗에서 그 줄을 빼면 `config_test.zig`의 역방향
검사가 부팅 전에 막으므로, 그 loop 한 줄(`if (seen_opt[i] or true) continue;`)도
함께 눕힌 사본을 둘째 마운트로 준다. SD-M2가 배운 것과 같다.

체인이 7차에서 죽는데, 예상한 `bpos1`이 아니라 첫째 `bneg0`에서 죽는다.

```
bash-5.2# echo bneg$(grep -cx bnegmark=1 /config/bash_history)
grep: /config/bash_history: No such file or directory
bneg
```

씨앗의 훅이 없으면 `HISTFILE=` 대입 뒤에도 파일이 안 생긴다 — 파일을 만드는
것이 그 훅이기 때문이다. 고친 것의 크기가 "늦게 쓴다"가 아니라 "파일이
없다"이고, SD-M2가 zsh에서 본 것과 글자 그대로 같은 모양이다.

### 실측 14 — 루트 게이트가 28분 55.53초에 11체인 3/3

기준선이 SD-M2 뒤의 28분 14.55초이고 41초 늘었다. config 체인 단독이
16.9초 길어졌고 게이트가 그것을 세 번 도니 51초가 설명되는 값이라 나머지는
잡음이다. 이 게이트의 잡음이 ±3분이므로 갈렸다고 말하지 않는다.

`skipping make`가 32회다. 기대값이 `체인 수 × 3 − 1` = 32이므로 커널 빌드
캐시(GL-M1)도 정상이다.

`/dev/fd` 링크가 열한 체인 어디도 안 깨뜨렸다. init의 로그가 한 줄 늘었는데,
그 줄은 시리얼로 가지 프레임버퍼로 안 가므로 화면 좌표를 보는 검사와는
애초에 다른 층이다.

## 위험

### 위험 1 — 순서 검사가 zsh와 fish에서 공허하게 통과한다

결정 4가 셸 셋 전부에 거는데, `PROMPT_COMMAND`를 건드리는 줄이 실제로 있는
것은 bash 하나뿐이다. zsh와 fish에서는 볼 줄이 없으므로 "그 줄이 훅보다
앞선다"가 공허하게 참이 된다.

이 저장소가 반복해서 부딪친 자리다(SP-M0 실측 4 — 통과했다와 볼 것이
없었다를 가르는 것). 처방은 검사가 실제로 무엇을 보았는지를 세고, 본 것이
0이면 그 사실을 화면에 적는 것이다. 검사가 조용히 초록이 되지 않게 한다.

M1이 그 처방을 넣었다. `zig build test`가 이제 두 줄을 찍는다.

```
note: the fish seed touches PROMPT_COMMAND on no line; nothing to order
note: the zsh seed touches PROMPT_COMMAND on no line; nothing to order
```

bash에 대해서는 이 줄이 없다 — 볼 것이 있었고 실제로 봤다는 뜻이다. 그
줄이 셋으로 늘면 bash의 씨앗에서 그 줄이 사라진 것이므로, 다른 검사가
죽기 전에 이 줄 수가 먼저 말해 준다.

### 위험 2 — 7차 부팅이 길어지고 8차의 화면 좌표가 밀린다

SD-M2가 7차에 타이핑을 100키쯤 더해 config 체인이 10.4초 길어졌다.
BH-M2가 비슷한 크기를 더하면 게이트에 다시 30초가 붙는다. 게이트 잡음이
±3분이라 갈리지는 않지만, 쌓이는 것이라 적어 둔다.

화면 좌표 쪽이 더 위험하다. 8차의 판정이 `history`의 최근 16개 창에 기대고
있어서, 7차에 줄이 더 붙으면 창 밖으로 밀린다. M2가 먼저 세야 하는 수다.

### 위험 3 — `PROMPT_COMMAND`는 하나뿐인 변수라 다음 사람이 덮어쓴다

실측 6이 zoxide에 대해 본 것이 일반적인 위험이다. 씨앗에 `PROMPT_COMMAND`를
쓰는 줄이 나중에 하나 더 들어오면 순서 검사만으로는 부족하다 — 검사가 보는
것은 옵션 줄과 훅 줄의 상대 순서이지 "누가 누구를 덮어쓰는가"가 아니다.

지금 넣을 방어는 주석이다. 씨앗의 그 줄 위에 "이 변수는 하나뿐이고 마지막
대입이 이긴다. 아래 훅보다 먼저 있어야 한다"를 적는다. 코드로 막는 것은
`PROMPT_COMMAND` 문법을 파싱하는 일이 되어 씨앗 검사의 성격(문법을 안
파싱한다)과 어긋난다.

### 위험 4 — 중첩 bash의 판정이 production과 다른 것을 본다

결정 6이 이미 적었다. env의 `HISTFILE`을 손으로 맞추므로 차이가 사라지지만,
그 한 줄을 빠뜨리면 검사가 zsh 히스토리 파일에 섞인 평문을 세게 된다.
그러면 양성이 우연히 통과할 수 있다.

처방은 중첩 세션의 첫 명령이 `HISTFILE=` 대입인 것을 체인 주석에 적고, 판정
글자를 `/config/bash_history`에서 세는 것이다. 그 파일은 7차 시점에 아예
없어야 정상이므로(zsh로 부팅했다), 음성 판정이 SD-M2의 `neg0`처럼
"파일이 없다"에서 죽는 모양이 될 수 있다. M2가 그 자리를 눈으로 본다.

## 참고

- SD design: `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
- SD 본문 요약: `docs/decisions/project_shell_history.md`
- SM design(히스토리 env와 훅 두 벌의 구조):
  `docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md`
- SC design(씨앗 rc와 `shell_config`):
  `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
