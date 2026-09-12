# TARS Bash Boot — Design

Date: 2026-09-12
Status: 진행 중 — M0(측정)을 끝냈다. 실측 열둘이 아래 있고, 그중 실측 6이
결정 6을 고쳤다(인자 하나인 `z`는 DB를 안 본다). M1·M2가 남았다.

BH(Bash History Durability)가 자기 결정 6에서 열어 둔 문이다. BH는 씨앗 rc의
bash 갈래에 한 줄을 넣고 그 줄이 게스트에서 하는 일을 7차 부팅의 중첩 bash로
판정했다. 그 선택은 부팅 하나를 아끼는 값이 있었고 지금도 유효하지만, 중첩이
볼 수 없는 자리를 여섯 남겼다. 이 문서는 그 여섯이 무엇인지 적고, 게이트에
`shell=bash`로 뜨는 부팅 하나를 세워 그것을 보게 한다.

## 한 줄 요약

`config` 체인에 9차 부팅을 더한다. 그 부팅만 `shell=bash`로 떠서, 지금까지
어느 부팅도 밟은 적이 없는 bash의 production 경로 — 셸 해석 · 히스토리 env ·
씨앗 rc · 훅 둘 · 콘솔 셸 — 를 게이트가 판정한다.

## 왜 지금인가

게이트의 열한 체인 중 bash로 뜨는 부팅이 하나도 없다. `config` 체인의 부팅
여덟은 1차가 fish이고 2~8차가 zsh다. 다른 체인들은 전부 씨앗의 기본값인
fish로 뜬다.

그런데 `tars.conf`의 `shell`은 값 셋을 받고, 그 셋 중 하나가 한 번도 부팅된
적이 없다. `init/src/config.zig`의 bash 갈래는 일곱 군데에 있다 —
`path()` · `noConfigFlag()` · `rcPath()` · `histEntries()` · `hooks()` ·
`histOptionLines()` · `rcSeed()`. 이 중 씨앗 rc의 내용만 중첩 bash가 읽었고,
나머지는 호스트 검사가 글자를 대조하는 것으로 끝나 있다. 글자가 맞는 것과
그 글자를 받은 기계가 뜨는 것은 다른 주장이다.

BH가 그 차이의 값을 이미 한 번 보여 주었다. 게스트에 `/dev/fd`가 없어서 씨앗의
fzf 훅이 부팅마다 에러 한 줄을 찍고 있었고, 그것을 아무도 못 본 이유가 정확히
"게이트에 bash로 뜨는 자리가 없다"였다. 씨앗은 아무것도 안 찍어야 한다는 이
저장소의 규칙을 깨고 있던 한 줄이 서브프로젝트 넷을 지나며 살아 있었다.

## 중첩 bash가 못 보는 여섯

이 서브프로젝트의 본체다. 하나하나가 9차 부팅의 검사가 된다.

1. `resolveShell(.bash)`. `/usr/bin/bash`가 실행 가능으로 판정되는가.
   아니면 init이 폴백 로그를 찍고 다른 셸로 뜬다(`main.zig:190`). 그 판정이
   bash에 대해 한 번도 돈 적이 없다.
2. 히스토리 env의 bash 갈래(`HIST_BASH`의 둘). 중첩 bash는 `HISTFILE`을 첫
   명령으로 손수 맞췄다 — BH 위험 4가 그래야 하는 이유를 적었고, 그 말은
   production 값이 맞는지는 아무도 안 봤다는 뜻이다.
3. 화면 셸도 bash가 되는 자리. init이 셸 경로와 플래그를 argv로 terminal에
   넘기고(`main.zig:715~719`), terminal이 그것으로 PTY의 자식을 띄운다
   (`terminal/src/main.zig:984·1072`). `configFlag(.on)`이 `"none"`이라
   argv[1]이 null이 되는 갈래도 bash에 대해 안 돌았다.
4. 씨앗 bashrc가 production 부팅에서 몇 바이트를 찍는가. 0이어야 한다.
   `/dev/fd` 한 줄이 정확히 이 자리에 살아 있었다.
5. `PROMPT_COMMAND` 합성의 결과가 둘 다 사는가. 히스토리도 쓰고 zoxide도
   배우는가. 호스트 검사는 씨앗의 줄 순서를 보고 중첩 bash는 히스토리만 봤다 —
   bash에서 `z`가 실제로 도는 것을 본 부팅이 없다. 뒤집혔을 때의 증상이
   조용하다는 것은 BH가 이미 적었다(히스토리는 남고 `z`만 아무것도 안 배운다).
6. 콘솔 셸도 bash로 서는가. `started console shell`이 하나이고 `times fast`가
   없어야 한다. 씨앗을 읽는 셸이 둘인데 중첩은 화면 셸 안에서만 일어났다.

## 착수 전에 읽어 둔 것 — 소스 확인이고 실측이 아니다

### 확인 1 — `config` 체인의 부팅 여덟은 fish 하나와 zsh 일곱이다

1차가 빈 디스크에서 씨앗의 기본값(fish)으로 뜨고, 그 부팅에서 사람이
`echo shell=zsh > /config/tars.conf`를 쳐서 2차부터 zsh가 된다
(`config/check.sh:73~75`). 이후 여섯 부팅은 `shell=zsh`를 로그에서 확인하는
검사를 각각 갖고 있다.

### 확인 2 — `tars.conf`는 마지막 줄이 이긴다

3차 부팅이 `shell_config=on`을 append해서 2차가 쓴 `off`를 되돌리는 것이 그
규칙 위에 서 있고(`config/check.sh:117~120`), `config_test.zig`가 그 규칙을
못 박고 있다. 그래서 9차를 위해 심을 것은 파일을 덮어쓰는 것이 아니라
`shell=bash` 한 줄을 append하는 것이다.

### 확인 3 — 게스트에 `/usr/bin/bash`가 있다

`kernel/guest_tools.sh:52`가 `usr/bin/bash`를 담고 있고, `input/check.sh`가
`/usr/bin/bash --norc`를 게스트에 타이핑해 띄운 적이 있다. 그러니 파일은 확실히
있다. 없는 것은 그 경로가 `resolveShell`을 지나 init의 자식으로 서는 것을 본
부팅이다.

### 확인 4 — bash의 히스토리 env는 둘이고 zsh는 셋이다

`HIST_BASH`가 `HISTFILE=/config/bash_history`와 `HISTSIZE=5000`이고,
`HIST_ZSH`는 거기에 `SAVEHIST=5000`이 더 붙는다(`config.zig:157~170`). 9차에서
`SAVEHIST`가 없어야 하는 것이 정상이고, 그 부재가 "env가 셸별로 갈린다"를
말하는 대조군이 된다 — 7차·8차는 그 셋이 있는 것을 이미 보고 있다.

### 확인 5 — 히스토리 판정에 새 표적이 필요하다

`/config/bash_history`가 9차 시점에 이미 있다. 7차의 중첩 bash가
`bnegmark=1`·`bposmark=1`을 써 두었기 때문이다. 그래서 9차는 그 글자를 세면
안 된다 — 자기가 아무것도 안 써도 초록이 된다. 표적을 새로 만든다.

### 확인 6 — zoxide 판정에도 새 표적이 필요하다

DB에 `/usr/share/terminfo/x`가 이미 있다. 7차가 넣고 8차가 그것을 읽어서 "전원을
넘었다"를 증명했다. 9차가 같은 글자를 쓰면 bash의 훅이 안 걸려도 `z`가 그리로
간다. 이 함정은 확인 5와 성질이 같고, 둘 다 "판정 글자를 만들 수 있는 것이
우리가 보려는 것 하나뿐인가"를 묻는 이 체인의 오래된 규칙에서 나온다.

## 결정

### 결정 1 — 중첩을 늘리지 않고 부팅을 더한다

BH 결정 6이 저울질한 그 둘이다. 그때는 중첩이 이겼고 여기서는 부팅이 이긴다 —
보려는 것이 바뀌었기 때문이다. BH가 보려던 것은 씨앗 rc의 한 줄이 하는 일이고
그것은 중첩으로 볼 수 있었다. 이번에 보려는 것은 위의 여섯이고, 그중 다섯은
"init이 bash를 셸로 골라 띄우는 경로" 자체라서 중첩으로는 정의상 볼 수 없다.

### 결정 2 — `shell=bash`는 8차 훅의 끝에서 타이핑으로 심는다

이 체인의 방식이다. 부팅마다 다음 부팅이 읽을 것을 심고, 심은 것을 그 자리에서
되읽는다.

8차의 판정 셋이 모두 끝난 뒤에 친다. 순서를 뒤집으면 8차의 셋째 판정이 깨질
수 있다 — `history`가 최근 16개만 찍는 창이고, SD-M2와 BH-M2가 그 창을 이미
두 번 밀었다.

### 결정 3 — 되읽기는 `cat`이고 판정 글자는 행의 첫머리 `shell=bash`다

1차 부팅이 `shell=zsh`에 쓴 수법 그대로다(`check.sh:356~362`). 타이핑한 줄에도
`shell=bash`라는 글자가 들어 있지만 그 행은 프롬프트로 시작하므로, 행의 첫머리가
`shell=bash`인 행은 `cat`의 출력뿐이다.

9차 시점의 `tars.conf`는 네 줄이라 `cat` 출력이 한 프레임에 다 들어간다.
`grep`으로 좁힐 이유가 없다.

### 결정 4 — 9차의 판정 글자는 `bprod` 접두사를 쓴다

`wait_for_screen`이 마지막 프레임이 아니라 로그 전체를 본다(실측 26). 7차가 이미
`neg`·`aft`·`pos`와 `bneg`·`baft`·`bpos`를 쓰고 있으므로, 같은 글자를 다시 쓰면
9차의 판정이 자기 로그가 아닌 것에 걸릴 여지가 생긴다. 로그 파일은 부팅마다
다르지만(`LOG9`) 이 규칙은 그것에 기대지 않는다.

`bprod`로 적는 것에 뜻이 있다. 중첩이 아니라 production이라는 것이 이 부팅의
전부다.

### 결정 5 — 히스토리 판정은 env를 손으로 안 맞춘다

BH의 중첩은 `HISTFILE=/config/bash_history`를 첫 명령으로 쳤다. 9차는 그것을
치지 않는다 — 안 치는 것이 요점이다. 그 값이 env로 오는 것이 여기서 검사하려는
것 중 하나이고(못 보는 여섯의 2번), 손으로 맞추면 그 검사가 사라진다.

표적은 `bprodmark=1`이고 세는 방법은 BH-M2와 같다 —
`echo bprod$(grep -cx bprodmark=1 /config/bash_history)`로 `bprod1`을 만든다.
앵커를 붙이는 이유는 BH-M2의 주석에 있다.

### 결정 6 — zoxide 판정은 새 디렉터리 하나로 한다

확인 6이 이유다. 후보 1순위는 `/usr/bin`이다 — 게스트에 확실히 있고, DB에
아직 없고(7차가 `cd /usr/bin/../share/terminfo/x`로 지나갔을 뿐 그 자리에
머문 적이 없다), 7차의 표적과 글자가 겹치지 않는다.

7차의 수법을 그대로 쓴다. `cd /usr/share/../bin`으로 가면 셸이 `$PWD`를
정규화하고 훅이 그 정규형을 DB에 넣는다. 화면에 남는 타이핑은 `..`가 든 쪽이고,
`| /usr/bin`으로 시작하는 행을 만들 수 있는 것은 `pwd`의 출력뿐이다.

훅이 안 걸렸을 때의 모양이 둘로 갈린다. `eval`이 아예 안 돌았으면 `z`가 없는
명령이고, PROMPT_COMMAND가 뒤집혀 훅만 남았으면 `z`는 있는데 DB가 못 배운다.
둘 다 `pwd`가 `/`를 찍는 것으로 끝나므로 판정은 하나로 충분하다.

⚠ M0이 이 결정의 절반을 고쳤다(실측 6). 목표 디렉터리는 `/usr/bin`이 맞지만
질의는 인자 하나(`z bin`)로 하면 안 된다 — zoxide가 DB를 안 보고 현재
디렉터리 아래의 `bin`으로 그냥 `cd`해서, 훅이 안 걸려도 초록이 된다. 질의를
`z usr bin`으로 한다(실측 7).

### 결정 7 — `Ctrl+R`은 치지 않는다

SM 비목표 2가 그대로 유효하다. fzf의 위젯은 TUI라 게이트가 치면 체인이
매달린다. 대신 7차가 zsh에 대해 했던 것처럼 셸에게 이름을 물어보는 한 줄을
쓴다.

M0이 그 이름과 물어보는 방법을 정했다(실측 9·12). 이름은 `__fzf_history__`
(`Ctrl+R`의 위젯)이고, 물어보는 줄은
`echo bprodw$(type -t __fzf_history__)`다 — `declare -F <이름>`은 출력이 이름
그 자체라서 판정 글자로 못 쓴다.

### 결정 8 — bash 프롬프트를 대기에 쓴다

BH-M2가 중첩 bash에서 배운 것이다. bash는 프롬프트가 `bash-5.2#` 모양이라
`wait_for_screen`으로 기다릴 수 있고, 그래서 rc를 읽는 중에 타이핑이 끼어들어
글자가 쪼개지는 것을 막을 수 있다. 9차는 최상위 셸이 bash이므로 이 대기가
7차의 중첩보다 더 자연스럽게 쓰인다. 정확한 글자는 M0이 잰다 — 게스트 bash의
버전이 컨테이너와 다를 수 있다.

### 결정 9 — 9차는 디스크를 원복하지 않는다

마지막 부팅이다. `tars.conf`에 `shell=bash`가 남은 채로 체인이 끝나고, 다음
회차는 `make_disk.sh`가 이미지를 새로 구우므로(`check.sh:37~46`) 이월이 없다.

## 비목표

1. `shell=bash`와 `shell_config=off`를 함께 주는 부팅(`--norc`). 10차를 더하는
   값이 낮다 — 탈출로 둘의 값은 5차·6차가 zsh로 증명했고, bash에 주는 플래그
   글자는 호스트 검사가 본다. 열리는 것은 "그 플래그를 받은 bash가 정말 rc를
   안 읽는가" 하나인데, 그것은 bash의 문서화된 동작이고 우리 코드가 아니다.
2. `Ctrl+R`을 게이트가 치는 것(결정 7).
3. fish로 뜨는 히스토리 부팅. fish는 이 문제가 애초에 없고(SD 실측 8) 1차
   부팅이 이미 fish다.
4. 기본 셸을 bash로 바꾸는 것. 씨앗은 fish 그대로다.
5. 다른 체인에 bash를 들이는 것. 다섯 체인이 화면 좌표로 판정하고 있어서
   프롬프트가 바뀌면 그 좌표가 전부 밀린다.
6. 종료가 3초 걸리는 것(SD 비목표 8). 그대로 이월한다.

## Milestone 셋

SD·BH와 같은 모양이다. 측정 · 부팅 세우기 · 화면 판정.

### BB-M0 — `shell=bash` 부팅을 한 번 띄워서 잰다

게이트에 넣기 전에 한 번 손으로 띄운다. BH가 하루에 세 번 걸린 함정이
"컨테이너에서 잰 값을 게스트 값으로 읽는 것"이었고, 여기서 재려는 것은 전부
게스트에서만 답이 나온다.

디스크를 `mkfs.ext2 -d`로 미리 구워서 `tars.conf`에 `shell=bash`를 담는다.
부팅 둘(고치고 다시 뜨기)이 하나로 줄고, 이 측정이 체인의 디스크 연속성에
기대지 않게 된다.

잴 것 일곱이다.

1. init이 `config shell=bash`를 찍고 폴백 로그가 없는가(못 보는 여섯의 1).
2. env 블록이 `HISTFILE=/config/bash_history`와 `HISTSIZE=5000` 둘이고
   `SAVEHIST`가 없는가(2).
3. 화면 셸과 콘솔 셸이 각각 하나씩 서고 아무도 안 죽는가(3·6).
4. 씨앗 bashrc가 화면과 로그에 몇 바이트를 찍는가. 0이어야 한다(4).
5. 최상위 bash의 프롬프트가 화면에 어떤 글자로 나오는가(결정 8).
6. `cd /usr/share/../bin` → `cd /` → `z bin` → `pwd`가 `/usr/bin`을 찍는가
   (5 · 결정 6).
7. bash의 fzf 통합이 정의하는 이름을 TUI 없이 물어볼 수 있는가(결정 7).

### BB-M1 — 8차의 심기와 9차 부팅의 로그 검사

`config/check.sh`에 9차를 더한다. 8차 훅의 끝에 심기 타이핑 둘(append와
되읽기)이 붙고, 9차는 훅 없이 로그만 본다.

로그 검사는 M0의 1~4가 그대로 온다. 부정 검사 넷도 함께 둔다 — `seeded`가
하나도 없는 것(디스크를 봤다는 뜻) · `times fast` 없음 · `giving up on` 없음 ·
`is not executable` 없음.

체인의 머리 주석과 각 부팅의 제목을 `1/8`에서 `1/9`로 고치는 것도 이
milestone이다. 여덟 자리다.

### BB-M2 — 9차 훅의 화면 판정과 반사실

9차에 훅을 붙여 M0의 5·6·7을 게이트가 보게 한다. 판정 글자는 `bprod` 접두사다.

반사실로 값을 증명한다. 씨앗 bashrc에서 `PROMPT_COMMAND` 줄을 빼거나 훅
뒤로 옮긴 사본을 마운트하면 9차가 죽어야 하고, 어느 검사에서 죽는지를 눈으로
본다. SD-M2와 BH-M2가 배운 것이 여기에도 온다 — 호스트 검사가 먼저 죽이므로
마운트가 둘 필요하고, 순서 검사까지 있으므로 눕힐 자리가 하나 더 있다.

## 위험

### 위험 1 — bash 프롬프트가 9차의 화면 좌표를 바꾼다

9차만 그렇고 다른 체인은 영향이 없다(비목표 5). 그래도 9차 자신의 판정은
프롬프트 길이에 안 걸려야 하므로, 판정을 전부 행의 첫머리나 우리가 만든
글자로 한다 — 이 체인이 이미 쓰는 두 수법이다.

### 위험 2 — 8차에 타이핑을 더해서 8차가 깨진다

결정 2가 순서로 막는다. 그리고 M1을 돌린 뒤 8차의 셋째 판정이 여전히 초록인지
로그에서 직접 확인한다. 이 자리는 SD-M2와 BH-M2가 각각 한 번씩 밀었고, 두 번
다 증상이 "8차가 빨개진다"였다.

### 위험 3 — 9차가 자기가 안 쓴 글자를 세고 초록이 된다

확인 5·6이 이 위험의 두 얼굴이다. 표적을 새로 만드는 것으로 막고, M0이 그
표적이 게스트에서 실제로 비어 있는 것을 확인한다.

### 위험 4 — 9차가 씨앗을 다시 깐다

그럴 이유가 없다. `/config/bashrc`는 1차가 깔고 아무도 안 지웠다. 9차에서
`seeded`가 하나라도 나오면 디스크가 아니라 tmpfs를 보고 있는 것이고, 8차가
같은 검사를 이미 갖고 있다.

### 위험 5 — bash가 `/dev/fd` 같은 것을 하나 더 물고 나온다

이 서브프로젝트가 그것을 찾으려고 있다. 나오면 고치고 design에 적는다 —
BH-M2가 `linkDevFd()`를 그렇게 넣었다.

## BB-M0이 실행으로 증명한 것

plan: `docs/superpowers/plans/2026-09-12-tars-bash-boot-bb-m0.md`

게스트를 세 번 부팅해서 쟀다. 디스크는 회차마다 새로 굽고 `tars.conf`에
`shell=bash` 한 줄을 미리 담았다(실측 11). 시리얼 로그 셋이
`out/bb_m0_serial.log` · `out/bb_m0b_serial.log` · `out/bb_m0c_serial.log`에
남아 있다(git에는 안 들어간다).

### 실측 1 — `shell=bash`가 셸로 선다. 폴백은 안 걸린다

init 로그가 `config shell=bash …  shell_config=on`을 찍고,
`started console shell (pid 32, /usr/bin/bash)`로 끝난다. `is not executable`이
한 번도 안 나왔다. `resolveShell(.bash)`가 처음으로 돌아서 통과한 것이다.

### 실측 2 — bash의 env는 둘이고 `SAVEHIST`가 없다

```
tars-init: env PATH=/usr/bin:/bin XDG_DATA_HOME=/config/xdg
tars-init: env HISTFILE=/config/bash_history
tars-init: env HISTSIZE=5000
```

확인 4대로다. 7차·8차가 보는 셋(`SAVEHIST` 포함)과 다른 것이 이 부팅의
대조군이 된다.

### 실측 3 — 셸 둘이 각각 하나씩 서고 아무도 안 죽는다

`started terminal (pid 31, /terminal)`과 `started console shell (pid 32,
/usr/bin/bash)`이 각각 한 줄이고, `times fast`도 `giving up on`도 없다.
씨앗 bashrc를 읽는 셸이 둘인데 둘 다 재시작 없이 섰다.

### 실측 4 — 씨앗 bashrc는 production 부팅에서 조용하다

시리얼 로그 전체를 `No such file` · `command not found` · `rror` · `warning`
으로 훑어서 걸린 줄이 0이다. BH-M2가 `linkDevFd()`를 넣기 전이라면 여기에
`/dev/fd/63` 한 줄이 있었을 자리다.

### 실측 5 — 최상위 bash의 프롬프트는 `bash-5.2#`다

중첩 bash에서 본 것과 같다(BH-M2). 그래서 결정 8의 대기가 그대로 선다.

### 실측 6 — 인자 하나인 `z`는 DB를 안 보고 그냥 `cd`한다

첫 회차의 판정이 이것 때문에 거짓이 될 수 있었다. `/`에서 `z bin`을 치면
`pwd`가 `/usr/bin`이 아니라 `/bin`을 찍는다. 게스트에는 `/usr/bin`(도구들)과
`/bin`(`sh` 링크 하나)이 서로 다른 실체로 있고(`make_initrd.sh:86·161`),
zoxide는 인자가 하나이고 그것이 현재 디렉터리 아래의 실제 디렉터리면 DB를
안 보고 그리로 간다.

그러면 훅이 안 걸려도 검사가 초록이 된다. 확인 6이 경계한 함정이 다른 얼굴로
한 번 더 나온 것이다 — "판정 글자를 만들 수 있는 것이 우리가 보려는 것
하나뿐인가"를 디렉터리 이름에도 물어야 한다.

7차의 zsh 판정은 이 함정을 안 밟았다. 인자가 둘(`z terminfo x`)이어서다.

### 실측 7 — 인자 둘인 `z`는 DB를 본다. bash에서 훅이 걸린다

`cd /usr/share/../bin` → `cd /` → `z usr bin` → `pwd`가 `/usr/bin`을 찍었다.
디스크가 새것이라 DB에 그 경로를 넣을 수 있는 것은 이 부팅의 훅뿐이다.

못 보는 여섯의 5번 절반이 이것으로 답이 났다 — `PROMPT_COMMAND` 합성 뒤에도
zoxide가 살아 있다. 나머지 절반이 실측 8이다.

### 실측 8 — production env에서 히스토리가 명령마다 써진다

`bprodmark=1`을 치고 `echo bprod$(grep -cx bprodmark=1 /config/bash_history)`가
`bprod1`을 찍었다. `HISTFILE`을 손으로 안 맞춘 상태다 — env로 온 값과 씨앗의
`PROMPT_COMMAND` 줄이 함께 일한 결과이고, BH-M2의 중첩 판정이 못 보던 자리다.

### 실측 9 — `declare -F <이름>`의 출력은 판정 글자가 못 된다

`declare -F __fzf_history__`가 찍는 것은 `__fzf_history__` 한 줄이다. 인자
없이 부를 때와 다르다(그때는 `declare -f <이름>`으로 찍는다). 타이핑한 줄과
글자가 같아서 이 체인의 규칙을 어긴다.

처방은 SD-M2의 수법이다. `echo bprodw$(type -t __fzf_history__)`로
`bprodwfunction`을 만든다 — `type -t`가 `function`을 찍고, 그 앞의 `bprodw`는
우리가 붙인 것이라 타이핑한 줄에는 `bprodw$(type` 까지만 있다.

### 실측 10 — 타이핑이 프롬프트를 앞질러도 명령은 온전하다

화면에 `cbash-5.2#`와 `pbash-5.2#`가 남았다. 앞 명령이 아직 도는 중에 다음
명령의 첫 글자가 tty에 에코된 것이고, 프롬프트가 그려진 뒤 readline이 그
글자를 다시 그려서 명령 자체는 `cd /`·`pwd`로 온전히 실행됐다.

BH-M2가 본 "글자가 쪼개진다"와 다른 현상이다. 그때 깨진 것은 판정 글자가
타이핑한 줄 안에 있었기 때문이고, 판정 글자를 우리가 만드는 규칙이 이것까지
막는다. 그래도 첫 키 앞에서는 프롬프트를 기다린다(결정 8) — 기다리는 값이
공짜다.

### 실측 11 — `mkfs.ext2 -d`가 측정을 부팅 하나로 줄인다

컨테이너의 e2fsprogs가 `-d`를 받는다. `tars.conf` 한 줄을 담은 디렉터리를
그대로 이미지에 넣으므로, 체인처럼 "1차에서 고치고 2차에서 읽는" 두 부팅이
필요 없다. 측정이 체인의 디스크 연속성에 기대지 않는 것이 덤이다.

### 실측 12 — `shift-backslash`가 `|`로 게스트에 닿는다

`declare -F | grep fzf`가 게스트에서 돌았다(`terminal/src/input.zig`의 키맵
43번이 `\`/`|` 쌍이다). 다만 판정에는 쓰지 않는다 — `screen>` 덤프의 행
구분자가 `|`라서 패턴이 모호해진다.

덤으로 fzf 통합이 정의하는 이름 28개를 봤다. `__fzf_history__`(`Ctrl+R`) ·
`fzf-file-widget`(`Ctrl+T`) · `__fzf_cd__`(`Alt+C`)와 자동완성 함수들이다.

### 9차 훅의 예행

셋째 회차가 판정 넷을 위의 순서 그대로 돌려서 전부 초록이었다 — 프롬프트
대기 · `z usr bin` · `bprod1` · `bprodwfunction`. M2는 이 키 배열을 그대로
체인에 옮긴다.

## 참고

- BH design(결정 6이 이 문을 열었다):
  `docs/superpowers/specs/2026-09-12-tars-bash-history-durability-design.md`
- SD design(중첩 판정의 구조와 판정 글자의 규칙):
  `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
- SM design(히스토리 env와 훅 두 벌):
  `docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md`
- SC design(씨앗 rc와 `shell_config`, 탈출로 둘):
  `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
- 셸 측정의 함정 셋: `docs/decisions/project_measuring_shells.md`
