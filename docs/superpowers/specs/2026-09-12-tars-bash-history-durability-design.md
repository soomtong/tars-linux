# TARS Bash History Durability — Design

Date: 2026-09-12
Status: 착수 — M0부터 시작한다.

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

bash는 zsh보다 나쁘다. SD 실측 7이 `exit`에서만 쓰고 SIGTERM과 SIGHUP
둘 다에서 안 쓴다고 쟀다. zsh는 SIGHUP에서 쓰므로 화면 셸만큼은 우연히
살아남았는데, bash는 그 우연조차 없다.

SD가 그 값에 유보를 하나 달아 두었다. "Debian의 `/etc/bash.bashrc`가
`histappend`를 켜는 것에 기댈 수 있어서, bash를 정말로 고치는 사람은
게스트의 그 파일을 먼저 봐야 한다"였다. 착수 전 실측 1·2가 그 유보를
지웠다.

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
옮기면 조용히 깨진다. `config_test.zig`에 검사를 하나 더 둔다 — 씨앗에서
`histOptionLines()`의 모든 줄이 `hookLines()`의 모든 줄보다 앞선 줄 번호에
있는가.

셸 셋 전부에 건다. 지금 조건을 만족하는 것은 bash 하나뿐이지만(zsh는 옵션
줄이 있고 fish는 없다), 검사를 셋에 걸어 두면 나중에 zsh 씨앗의 줄을 옮기는
편집도 잡힌다. zsh의 `setopt`는 순서와 무관하지만, 무관한 것을 지키는
비용이 0이다.

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

## 위험

### 위험 1 — 순서 검사가 zsh와 fish에서 공허하게 통과한다

결정 4가 셸 셋 전부에 거는데, 조건을 만족할 줄이 실제로 있는 것은 bash
하나뿐이다. fish는 옵션 줄이 0이라 "모든 옵션 줄이 훅보다 앞선다"가 공허하게
참이다.

이 저장소가 반복해서 부딪친 자리다(SP-M0 실측 4 — 통과했다와 볼 것이
없었다를 가르는 것). 처방은 검사가 실제로 무엇을 보았는지를 세고, 본 것이
0이면 그 사실을 화면에 적는 것이다. 검사가 조용히 초록이 되지 않게 한다.

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
