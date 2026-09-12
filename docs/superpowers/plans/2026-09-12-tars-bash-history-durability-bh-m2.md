# BH-M2 — 게이트가 그 줄을 본다

Design: `docs/superpowers/specs/2026-09-12-tars-bash-history-durability-design.md`

M1의 초록은 "그 줄이 씨앗에 있다"까지만 말한다. 게이트에는 bash로 뜨는
자리가 하나도 없어서(확인 4) 그 줄이 게스트에서 무엇을 하는지 아무도 안 본다.
이 milestone이 그 자리를 만든다.

방법은 SD-M2와 같다 — 7차 부팅에 중첩 셸 둘을 띄워 음성·양성 대조군을
만들고, 우리가 만든 글자로 판정한다. 다른 것은 셋이다.

1. 중첩이 zsh가 아니라 bash다. 씨앗 rc는 `~/.bashrc` 링크를 통해 그대로
   읽힌다(`make_initrd.sh:228`).
2. 첫 명령이 `HISTFILE=/config/bash_history`다. 7차는 zsh로 떴으므로 env의
   `HISTFILE`이 zsh 것이고, 그것을 안 맞추면 검사가 zsh 히스토리 파일에 섞인
   평문을 세게 된다(위험 4).
3. 음성이 옵션을 끄는 방법이 `unsetopt`가 아니라 `PROMPT_COMMAND=`다.

## 판정 글자 셋

```
(none)# bash                              ← 중첩 bash. 프롬프트가 bash-5.2#로 바뀐다
bash-5.2# HISTFILE=/config/bash_history
bash-5.2# PROMPT_COMMAND=
bash-5.2# bnegmark=1
bash-5.2# echo bneg$(grep -cx bnegmark=1 /config/bash_history)
bneg0                                     ← 훅을 끈 세션은 안 쓴다
bash-5.2# exit
(none)# echo baft$(grep -cx bnegmark=1 /config/bash_history)
baft1                                     ← 그 명령은 분명히 쳐졌다
(none)# bash
bash-5.2# HISTFILE=/config/bash_history
bash-5.2# bposmark=1
bash-5.2# echo bpos$(grep -cx bposmark=1 /config/bash_history)
bpos1                                     ← 씨앗의 훅이 그 자리에서 쓴다
```

앞에 `b`를 붙이는 것은 7차가 이미 `neg0`·`aft1`·`pos1`을 쓰고 있기 때문이다.
`wait_for_screen`은 마지막 프레임이 아니라 로그 전체를 보므로(HANDOFF 실측
26) 같은 글자를 두 번 쓰면 뒤엣것이 앞엣것에 걸린다.

앵커(`grep -cx`)를 붙이는 이유가 zsh와 다르다. zsh에서는 `grep` 명령줄이
실행 전에 파일에 써져서 자기를 세는데(SD 실측 24), bash는 `PROMPT_COMMAND`가
직전 명령까지만 쓰므로 자기 줄이 아직 없다(BH 실측 4). 그래도 앵커는 붙인다 —
앵커 없는 패턴이 의도한 것보다 많이 세는 것은 같고, 양성에서 `bposa2`가
나오는 것을 실제로 봤다.

## bash 판정을 zsh 판정 앞에 둔다

SD-M2가 "7차에 명령을 더하는 사람은 이 수를 다시 세야 한다"고 경고한
자리다. 8차가 `history`(최근 16개)에서 `posmark=1`을 찾는데, 7차에 줄이
붙으면 그 글자가 창 밖으로 밀린다.

bash 중첩 안에서 친 명령은 zsh 히스토리에 안 들어간다 — zsh가 읽는 입력이
아니기 때문이다. 그래서 7차의 zsh 히스토리에 실제로 더해지는 것은 셋뿐이다.

| 더해지는 줄 | 어디서 |
|---|---|
| `bash` | 음성 중첩을 띄운다 |
| `echo baft$(...)` | 음성이 나간 뒤 zsh에서 센다 |
| `bash` | 양성 중첩을 띄운다 |

그 셋을 zsh 판정 앞에 두면 `posmark=1`이 파일 끝에서 두 번째가 되고, 뒤에
두면 다섯 번째가 된다. 앞에 둔다.

## Task 1: 키 배열 여덟을 더한다

Files: `config/check.sh`

`EXIT_KEYS` 정의 아래, `# ── 8차 부팅이 치는 셋` 주석 앞에 둔다.

- [x] Step 1: 배열을 쓴다

```bash
# ── BH-M2 ───────────────────────────────────────────────────────────────
#
# 같은 실험을 bash로 한 번 더 한다. SD-M2가 zsh에 대해 세운 구조를 그대로
# 쓰되 셋이 다르다.
#
#   1. 중첩이 bash다. 씨앗은 `~/.bashrc` 링크로 그대로 읽힌다.
#   2. 첫 명령이 HISTFILE 대입이다. 이 부팅은 zsh로 떴으므로 env의 HISTFILE이
#      zsh 것이고, 안 맞추면 이 검사가 zsh 파일에 섞인 평문을 센다.
#   3. 옵션을 끄는 방법이 `PROMPT_COMMAND=`다. bash에는 `unsetopt`가 없다.
#
# 이 셋이 zsh 판정보다 앞에 있는 이유는 8차다. bash 중첩 안에서 친 것은 zsh
# 히스토리에 안 들어가므로 여기서 느는 것은 세 줄뿐인데(`bash` 둘과 `echo
# baft`), 그 셋이 `posmark=1` 뒤에 오면 8차의 `history` 16줄 창에서 그 글자를
# 민다.
BNEST_KEYS=(b a s h ret)
# HISTFILE=/config/bash_history — 대문자는 shift-<글자>, 밑줄은 shift-minus다.
BHISTFILE_KEYS=(shift-h shift-i shift-s shift-t shift-f shift-i shift-l shift-e
                equal slash c o n f i g slash b a s h shift-minus
                h i s t o r y ret)
# PROMPT_COMMAND= — 음성 세션의 첫 훅 끄기. 빈 값 대입이라 화면에 안 찍힌다.
BNEG_UNSET_KEYS=(shift-p shift-r shift-o shift-m shift-p shift-t shift-minus
                 shift-c shift-o shift-m shift-m shift-a shift-n shift-d
                 equal ret)
# bnegmark=1 / bposmark=1 — 세는 대상. 변수 대입이라 화면에 한 글자도 안 찍고,
# 공백이 없어서 `grep -x`의 패턴에 따옴표가 필요 없다.
BNEG_MARK_KEYS=(b n e g m a r k equal 1 ret)
BPOS_MARK_KEYS=(b p o s m a r k equal 1 ret)
# echo bneg$(grep -cx bnegmark=1 /config/bash_history) — 판정 글자를 우리가
# 만든다. zsh 쪽의 같은 배열과 다른 것은 표적과 파일 이름뿐이다.
BNEG_COUNT_KEYS=(e c h o spc b n e g shift-4 shift-9
                 g r e p spc minus c x spc b n e g m a r k equal 1 spc
                 slash c o n f i g slash b a s h shift-minus h i s t o r y
                 shift-0 ret)
# echo baft$(grep -cx bnegmark=1 /config/bash_history) — 음성이 나간 뒤 같은
# 표적을 한 번 더 센다. 이 명령은 bash가 아니라 zsh에서 친다(음성 세션은
# 이미 나갔다). 문법이 셋 다 같아서 그대로 돈다.
BAFT_COUNT_KEYS=(e c h o spc b a f t shift-4 shift-9
                 g r e p spc minus c x spc b n e g m a r k equal 1 spc
                 slash c o n f i g slash b a s h shift-minus h i s t o r y
                 shift-0 ret)
BPOS_COUNT_KEYS=(e c h o spc b p o s shift-4 shift-9
                 g r e p spc minus c x spc b p o s m a r k equal 1 spc
                 slash c o n f i g slash b a s h shift-minus h i s t o r y
                 shift-0 ret)
```

- [x] Step 2: 넣은 것을 `rg`로 확인한다

```bash
rg -n 'BNEST_KEYS|BHISTFILE_KEYS|BNEG_|BPOS_|BAFT_' config/check.sh
```

## Task 2: `probe_shell_hooks`에 판정 셋을 끼운다

Files: `config/check.sh`

fzf 위젯 판정이 끝난 자리(`echo "boot 7: the fzf integration defined its
Ctrl+R widget without the gate pressing Ctrl+R"`) 바로 뒤, `# ── SD-M2:` 주석
앞에 끼운다. 순수 삽입이고 기존 줄은 한 줄도 안 지운다.

- [x] Step 1: 판정 셋을 쓴다

```bash
  # ── BH-M2: bash 씨앗의 한 줄이 게스트에서 하는 일을 본다 ──────────────
  #
  # 구조가 아래 SD-M2의 것과 같다. 중첩 둘이 음성·양성이고 둘 다 같은 씨앗
  # rc를 읽으며, 다른 것은 음성이 훅을 끄는 한 줄뿐이다.
  #
  #   bneg0  훅을 끈 세션이 친 명령은 살아 있는 동안 파일에 없다
  #   baft1  그 세션이 나가면서 썼다 — 그러니 그 명령은 분명히 쳐졌다
  #   bpos1  씨앗의 훅이 살아 있는 세션은 치는 그 자리에서 파일에 쓴다
  #
  # ⚠ HISTFILE 대입을 지우지 말 것. 이 부팅은 zsh로 떴으므로 env의 HISTFILE이
  #   /config/zsh_history이고, 그것을 안 맞추면 아래 grep이 zsh 형식 파일에
  #   섞인 평문을 센다 — 양성이 우연히 통과할 수 있다.
  type_keys "${BNEST_KEYS[@]}"
  type_keys "${BHISTFILE_KEYS[@]}"
  type_keys "${BNEG_UNSET_KEYS[@]}"
  type_keys "${BNEG_MARK_KEYS[@]}"
  type_keys "${BNEG_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| bneg0'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): the bash session with its prompt hook cleared still wrote its command to the history file"
    echo "  화면에 bneg1이 있으면 PROMPT_COMMAND= 가 안 먹은 것이다."
    echo "  bneg라는 글자가 숫자 없이 있으면 /config/bash_history가 아직 없어서"
    echo "  grep이 에러를 낸 것이고, 그것은 씨앗의 그 줄이 안 걸렸다는 뜻이다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: with the prompt hook cleared, a typed command is not in the bash history while that session lives"

  type_keys "${EXIT_KEYS[@]}"
  type_keys "${BAFT_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| baft1'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): the negative bash session's command never reached the file, so the check above saw nothing"
    echo "  화면에 baft0이 있으면 그 명령이 애초에 안 쳐진 것이고, 그러면"
    echo "  위의 bneg0은 씨앗의 줄과 아무 상관이 없다. 중첩 bash가 떴는지부터"
    echo "  본다 — 프롬프트가 bash-5.2#로 바뀌었어야 한다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: that same command did land when the bash session left, so the zero above meant 'not yet written'"

  type_keys "${BNEST_KEYS[@]}"
  type_keys "${BHISTFILE_KEYS[@]}"
  type_keys "${BPOS_MARK_KEYS[@]}"
  type_keys "${BPOS_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| bpos1'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): with the seeded prompt hook on, a typed command was not in the bash history file yet"
    echo "  화면에 bpos0이 있으면 씨앗의 PROMPT_COMMAND 줄이 안 걸린 것이다 —"
    echo "  그 줄이 없거나(rcSeed의 bash 갈래), bash가 /config/bashrc를 안"
    echo "  읽었거나, 뒤에 오는 zoxide 훅이 그 변수를 덮어쓴 것이다."
    echo "  이 줄이 BH가 넣은 그 한 줄을 게이트가 보는 유일한 자리다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the seeded prompt hook put a typed command on the config disk the moment it was typed"

  type_keys "${EXIT_KEYS[@]}"
```

마지막 `EXIT_KEYS`가 중요하다. 양성 bash에서 나와야 아래 zsh 판정이 zsh
세션에서 돈다.

- [x] Step 2: 끼운 자리를 확인한다

```bash
rg -n 'BH-M2|SD-M2' config/check.sh | head
git diff config/check.sh | grep '^-' | grep -v '^---'
```

지운 줄이 0이어야 한다. 순수 삽입이다.

## Task 3: config 체인을 돌린다

- [x] Step 1: 체인 단독으로 돌린다 (약 2분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh ; } > /tmp/bh_m2.log 2>/tmp/bh_m2.time
tail -30 /tmp/bh_m2.log; tail -3 /tmp/bh_m2.time
```

보는 것이 셋이다.

1. 7차의 새 판정 셋이 전부 통과하는가
2. 8차의 `posmark=1`이 여전히 `history` 창 안에 있는가
3. 시간이 얼마나 늘었는가(타이핑 약 200키 — SD-M2의 100키가 10.4초였다)

- [x] Step 2: 8차가 깨지면 세는 자리를 옮긴다

`history`는 zsh에서 최근 16개만 찍는다. 밀렸으면 `history 1`로 전부 찍게
하거나 판정 글자를 파일 끝에 더 가까운 것으로 바꾼다. 먼저 실제 화면을
보고 몇 줄이 밀렸는지 센다.

```bash
grep -a "terminal: screen>" /tmp/bh_m2.log | tail -1
```

## Task 3.5: 계획에 없던 것 — 게스트에 `/dev/fd`가 없다

Task 3의 첫 회차가 통과했는데, 화면에 예상하지 않은 것이 있었다.

```
(none)# bash | HISbash: /dev/fd/63: No such file or directory | TF...bash-5.2# HISTFI
```

`bash`를 친 직후 씨앗의 fzf 훅이 에러 한 줄을 찍고, 그 사이에 `HISTFILE=`
타이핑이 끼어들어 글자가 쪼개졌다. 그 회차는 결국 통과했지만 운이다.

design 실측 13과 결정 9가 이 내용이다. 요약하면 `fzf --bash` 출력의 마지막
줄이 최상위에서 process substitution을 돌고, 게스트에 `/dev/fd`가 없어서
실패한다. devtmpfs는 그 링크를 안 만들고 우리는 udev를 안 쓴다.

- [x] Step 1: `main.zig`에 `linkDevFd()`를 넣는다

`/proc`과 `/dev`가 둘 다 붙은 뒤 `symlink("/proc/self/fd", "/dev/fd")`를
한다. `mountDevpts()` 바로 뒤가 그 자리다. 로그 한 줄을 찍는다.

- [x] Step 2: `config/check.sh`의 1차 부팅이 그 로그를 보게 한다

```bash
if ! grep -q "tars-init: linked /dev/fd to /proc/self/fd" "$LOG1"; then
  report_failure "$LOG1" "first boot did not link /dev/fd; bash process substitution will fail in the seeded rc"
fi
```

- [x] Step 3: 첫 중첩 bash 뒤에 프롬프트를 기다리는 코드를 넣는다

`type_keys "${BNEST_KEYS[@]}"` 뒤에 `wait_for_screen 'bash-5\.2#'`다. 중첩
zsh로는 못 하던 것이다 — zsh는 프롬프트가 바깥과 같다(SD 실측 12).

둘째 중첩에는 못 넣는다. `wait_for_screen`이 로그 전체를 보므로 같은 글자가
앞선 프레임에 이미 있다. 대신 둘째가 흔들리면 `bpos`가 숫자 없이 나와 검사가
죽으므로 조용하지는 않고, 그 가능성을 진단 메시지에 적었다.

- [x] Step 4: 다시 돌려 에러가 사라진 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash config/check.sh > /tmp/chain.out 2>&1
  grep -ah "dev/fd/63" /tmp/tmp.*
'
```

아무것도 안 나와야 한다. 통과한 체인은 시리얼 로그를 안 뿜으므로 한 번의
`docker run` 안에서 `/tmp/tmp.*`를 뒤져야 한다.

## Task 4: 반사실로 값을 증명한다

씨앗에서 그 줄만 뺀 사본을 마운트하면 체인이 7차에서 죽어야 한다.

SD-M2가 배운 것이 여기서도 필요하다 — 호스트 검사가 부팅 전에 먼저 죽이므로
마운트가 둘이다. 씨앗에서 그 줄을 빼면 `config_test.zig`의 역방향 검사가
막고, BH는 순서 검사도 있으므로 눕힐 자리가 더 있을 수 있다.

- [x] Step 1: 사본 둘을 만든다

`config.zig`는 씨앗의 그 줄만 뺀다. `config_test.zig`는 그 줄이 없어도
통과하게 만든다 — 역방향 loop 한 줄(`if (seen_opt[i] or true) continue;`)과
`expectHistOptions`의 bash 개수(1 → 0), 그리고 순서 검사의 이른 반환이다.

`HIST_OPTIONS_BASH`도 함께 비워야 정방향이 안 걸린다.

- [x] Step 2: 돌린다 (약 2분)

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/cf_config.zig:/workspace/init/src/config.zig:ro \
  -v /tmp/cf_config_test.zig:/workspace/init/src/config_test.zig:ro \
  -w /workspace tars-devcontainer bash config/check.sh > /tmp/bh_cf.log 2>&1
tail -20 /tmp/bh_cf.log
```

- [x] Step 3: 어디서 죽었는지 본다

기대는 `bpos1`에서 죽는 것이다. SD-M2에서는 예상한 `pos1`이 아니라 첫째
`neg0`에서 죽었는데, 그 이유는 옵션이 없으면 그 시점에 파일이 아예 없어서
`grep`이 에러를 냈기 때문이었다.

BH는 다르게 나올 수 있다. 음성 세션의 첫 명령이 `HISTFILE=` 대입이고, 씨앗의
훅이 있으면 그 대입 직후에 파일이 생긴다 — 훅이 없으면 그 시점에도 파일이
없으므로 SD-M2와 같은 모양이 된다. 실제로 어느 쪽인지 보고 적는다.

## Task 5: 루트 게이트를 돌린다

- [x] Step 1: 백그라운드로 돌린다 (약 29분)

Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [x] Step 2: 3/3과 시간을 본다

기준선은 SD-M2 뒤의 28분 14.55초다. BH-M2가 7차에 200키쯤 더하므로 config
체인 단독이 20초쯤 늘고 게이트가 그것을 세 번 돈다 — 60초가 설명되는 값이다.
이 게이트의 잡음이 ±3분이라 그보다 작은 차이는 갈렸다고 말하지 않는다.

## Task 6: design·HANDOFF·MEMORY를 갱신하고 커밋한다

- [x] Step 1: design에 BH-M2 절과 실측 12를 적는다

실측 12는 M2 착수 전에 잰 것이다 — `history -a`를 쓰는 세션이 정상 종료해도
남의 줄을 안 지운다(`histappend`를 켜든 끄든). 결정 1이 그 위에 선다.

- [x] Step 2: `Status:`를 완료로 고친다

- [x] Step 3: `docs/decisions/project_shell_history.md`에 BH를 더한다

SD의 기억 파일에 이어 적는다 — 같은 주제이고 파일을 새로 만들 만큼 다르지
않다. `MEMORY.md`의 그 줄도 함께 본다.

- [x] Step 4: `CLAUDE.md`의 완료 표에 한 줄, `HANDOFF.md`를 다시 쓴다

HANDOFF에 새로 적을 것이 셋이다.

- 실측 11(복사해 온 `.zig-cache`가 소스 변경을 가린다)은 서브프로젝트를
  넘어 유효하다. "다시 조사하지 말 것" 목록에 넣는다.
- SD 실측 7이 틀렸던 이유(`script`의 래퍼에 시그널이 간다)도 같은 목록에
  넣는다. 이 저장소가 PTY 하네스를 계속 쓰므로 다시 걸릴 자리다.
- 이월 숙제에서 "bash의 히스토리"를 지운 숙제로 옮긴다.

- [x] Step 5: 커밋한다
