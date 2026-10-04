# PE-M0 — service 체인이 주소가 붙은 뒤에 ssh를 친다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
Status: 끝났다(2026-10-04). 실측은 맨 아래 "PE-M0이 실측한 것" 절에 있다.

## 누가 무엇을 하나

design 결정 9. Task 0~3은 구현 서브에이전트(Sonnet)가 한다. Task 4(다섯 번 연달아 돌리기와
루트 게이트 판단)는 lead가 한다. commit은 lead가 한다 — 구현자는 commit하지 않고, 끝에
`git diff --stat`과 `git diff`의 출력, 그리고 Task 3에서 잰 값을 그대로 보고한다. 이 plan의
"실측한 것" 절은 구현자가 고치지 않는다. lead가 보고를 받아 채운다.

이 plan은 파일 둘을 고친다. 고치는 자리는 줄 번호가 아니라 심볼과 `rg` 패턴으로 적는다. 줄 번호는
2026-10-04 `48431e7` 기준의 참고값이다.

| 파일 | 무엇을 |
|---|---|
| `service/check.sh` | `boot_ssh()` 안의 기다림 한 줄과 그 주석 |
| `docs/guides/lessons.md` | "이월 숙제"의 service 두 항목을 지우고, "서브프로젝트를 넘어 유효한 실측"에 73번을 더한다 |

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로
명령 앞에 `cd /Users/dp/Repository/tars-linux &&`를 붙인다.

## 이 milestone이 끝나면

- `boot_ssh()`가 dhcpcd의 `eth0: leased 10.0.2.15` 줄을 본 뒤에 `eth0: adding default route via
  10.0.2.2` 줄까지 기다리고 돌아온다. 부팅 B · C · D가 전부 이 함수로 뜨므로 셋의 ssh ·
  `ssh-keyscan`이 게스트에 주소가 붙은 뒤에만 붙는다.
- 검사 번호와 개수는 그대로다. 코드(`init` · `terminal`)와 initrd는 안 바뀐다.
- `docs/guides/lessons.md`의 "이월 숙제"에서 service 두 항목이 빠지고, 틀렸던 진단과 실제 원인이
  실측 73번이 된다.

## 착수 전에 확정한 것

1. 기다림은 이미 셋 다에 있다(design 결정 1 · 실측 7). `wait_for_log "eth0: leased 10\.0\.2\.15 "
   60`은 `boot_ssh()`(306~330줄)의 마지막 줄(329줄)이고, 부팅 B · C · D가 343 · 374 · 437줄에서 그
   함수를 부른다. 그 줄은 `c89157d`(2026-09-27)에서 들어왔다(`git log -S`로 확인). 그래서 고칠 자리는
   함수 하나다.
2. `fail()`(81줄)의 인자. 첫 인자는 메시지이고 `FAIL: $1`로 찍힌다. 그 뒤 `shift`하고, 나머지
   인자(`"$@"`) 각각은 마커가 아니라 grep 패턴이다 — `grep -a "$pattern" "$LOG" | head -5`로 맞는 줄을
   다섯까지 찍는다. 마커 목록은 함수 안에 고정돼 있고(여섯 개) 그중 하나가 `": leased"`다. design의
   코드 블록에서 `": leased" "adding"`은 둘째 · 셋째 인자이고 패턴이다. 실패하면 `leased` 줄과
   `adding …` 줄이 덤프에 함께 나와서, "경로 줄이 늦었다"와 "경로 줄이 아예 없다"가 화면에서
   갈린다. 인자 모양은 design 그대로 맞다.
3. `wait_for_log()`(110줄)의 둘째 인자는 반복 횟수이고 한 번에 `sleep 1`이다 — 사실상 초 단위다
   (grep 시간만큼 조금 길다). 패턴은 `grep -aE`(확장 정규식)로 본다. QEMU가 죽으면 기다리지 않고
   곧바로 1을 돌려준다. 그래서 `30`은 "약 30초"다.
4. 패턴의 글자. dhcpcd는 줄마다 두 번 찍는다 — 맨 줄과 `Oct 04 hh:mm:ss [pid]: ` 접두가 붙은 줄.
   2026-10-04 GE-M1 루트 게이트의 실패 덤프(`/tmp/gate_m1.log` 20409~20414줄)에서 글자를 확인했다.

   ```
   eth0: leased 10.0.2.15 for 86400 seconds
   Oct 04 08:17:26 [41]: eth0: leased 10.0.2.15 for 86400 seconds
   eth0: adding route to 10.0.2.0/24
   Oct 04 08:17:26 [41]: eth0: adding route to 10.0.2.0/24
   eth0: adding default route via 10.0.2.2
   Oct 04 08:17:26 [41]: eth0: adding default route via 10.0.2.2
   ```

   패턴 `eth0: adding default route via 10\.0\.2\.2`는 두 모양 다에 맞는다. IPv6 경로가 생기더라도
   `via 10\.0\.2\.2`가 있어서 그 줄과는 안 맞는다.
5. 통과한 회차의 시리얼 로그는 셋 중 하나만 남는다. design 검증 절은 "각 회차의 시리얼 로그에서 부팅
   B · C · D마다 센다"고 적었지만, 체인이 통과하면 로그를 지운다.

   | 로그 | 지우는 자리 |
   |---|---|
   | 부팅 A | 341줄 `rm -f "$LOG"` — 부팅 B를 띄우기 직전 |
   | 부팅 B | 572줄 `rm -f "$B_LOG"` — 맨 끝 |
   | 부팅 C | 안 지운다(373줄에서 `LOG`가 새 `mktemp`로 바뀐 뒤 아무도 안 지운다) |
   | 부팅 D | 571줄 `rm -f "$LOG"`와 `cleanup` |

   그래서 lessons "범용 명령"의 첫 블록(체인이 끝난 뒤 `/tmp/tmp.*`를 복사)으로는 부팅 C의 로그
   하나만 얻는다. 이 plan은 체인을 배경으로 돌리며 1초마다 `/tmp/tmp.*`를 복사하는 명령을 쓴다
   (Task 3-3). 체인 파일을 덮어 지우기를 끄는 길도 있지만, 그러면 게이트가 돌리는 파일과 다른 것을
   돌리게 되므로 고르지 않았다.
6. 로그가 어느 부팅의 것인지는 내용으로 가른다. 부팅 A만 `started service a-greet`를, 부팅 D만
   `started service sleeper`를, 부팅 B만 `sshd: generated a host key`를 찍는다(검사 12가 C에서 그
   줄이 없는 것을 본다. D는 같은 디스크라 키가 이미 있다). 셋 다 아니면 C다. 부팅 A는 `boot_ssh`를
   안 쓰지만 같은 순서를 보는 참고로 함께 센다.
7. `firewall/check.sh`의 304 · 381줄도 임대를 기다린 뒤 hostfwd로 붙는다. design 결정 1과 비목표
   6대로 손대지 않는다.
8. 진입 검사. 새 줄에는 파이프도 QEMU 호출도 없으므로 `require_no_early_exit_pipe` ·
   `require_explicit_nic`과 무관하다. 그래도 Task 3-2에서 `ENTRY-OK`로 확인한다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다. Task 3이 docker를 쓰므로 겹치면 포트(45481~45486)가 부딪친다.

   ```bash
   pgrep -fl 'tars-devcontainer'
   ```

   아무것도 안 나와야 한다. 나오면 멈추고 보고한다.
2. 고칠 자리가 그대로인지 본다.

   ```bash
   rg -n 'boot_ssh|eth0: leased|adding default route' service/check.sh
   ```

   기대(줄 번호는 참고):

   ```
   248:wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
   306:boot_ssh() {  # $1 = monitor 포트
   329:  wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
   343:boot_ssh "$MONITOR_PORT_B"
   374:boot_ssh "$MONITOR_PORT_C"
   437:boot_ssh "$MONITOR_PORT_D"
   ```

   `adding default route`는 0줄이어야 한다.
3. 작업 트리가 깨끗한지 본다. `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`와 이 plan이
   untracked로 보이는 것은 정상이다.

   ```bash
   git status --short
   ```

## Task 1: `service/check.sh` — `boot_ssh`의 기다림

`boot_ssh()` 안의 마지막 줄(`rg -n 'never leased an address" ": leased"$' service/check.sh`) 바로
다음, 함수를 닫는 `}` 앞에 주석 다섯 줄과 기다림 두 줄을 넣는다. 들여쓰기는 함수 본문과 같은
공백 둘이고, 이어지는 줄(`||`)은 공백 넷이다. 기존 `leased` 줄은 고치지 않는다.

바꾸기 전:

```bash
  [ "$ok" = "1" ] || fail "could not connect to the QEMU monitor"
  wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
}
```

바꾼 뒤:

```bash
  [ "$ok" = "1" ] || fail "could not connect to the QEMU monitor"
  wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
  # PE-M0. dhcpcd는 leased를 찍은 다음에 주소를 붙이고(ipv4_applyaddr) 경로 줄을 찍는다.
  # 그 사이에 hostfwd로 붙으면 SLIRP은 호스트 쪽 연결을 받아 주지만, 아직 10.0.2.15가 아닌
  # 게스트가 SYN을 버린다 — 부팅 C의 keyscan이 빈 값으로, 부팅 D의 제어 연결이 banner exchange
  # 타임아웃으로 한 번씩 죽은 경합이다. 경로 줄은 주소가 붙은 뒤에만 나온다. leased 기다림을
  # 남기는 것은 "DHCP가 안 됐다"와 "주소를 붙이다 실패했다"를 다른 FAIL로 가르기 위해서다.
  wait_for_log "eth0: adding default route via 10\.0\.2\.2" 30 \
    || fail "dhcpcd leased but never added the default route" ": leased" "adding"
}
```

design 결정 1의 코드 블록과 다른 점은 둘이다. 함수 안이라 들여쓰기가 붙었고, 주석 다섯 줄이
더해졌다. 기다림의 글자 · 초 · 메시지 · 패턴은 design 그대로다.

편집은 Edit 도구로 한다(`sd -F`는 치환 문자열의 `\n`을 글자로 넣는다 — lessons 실측 59). 편집 뒤에
확인한다.

```bash
git diff --stat service/check.sh
git diff service/check.sh | rg '^-' 
bash -n service/check.sh && echo SYNTAX-OK
```

기대: `1 file changed, 7 insertions(+)`(지운 줄 0), 둘째 명령은 `--- a/service/check.sh` 한 줄만,
셋째는 `SYNTAX-OK`.

## Task 2: `docs/guides/lessons.md`

지우는 편집과 더하는 편집이 하나씩이다. 둘 다 Edit 도구로 한다.

### 2-1. "이월 숙제"의 service 두 항목을 지운다

`## 이월 숙제` 절의 "미룬 것." 목록에서 아래 두 항목을 통째로 지운다
(`rg -n '^- \[ \] service 체인 부팅' docs/guides/lessons.md`로 두 줄머리를 찾는다. 2026-10-04 기준
936 · 941줄). 앞 항목(USB 무선 동글)과 뒤 항목(`firmware 96MB`)은 그대로 둔다. 지우는 것은 아래
열다섯 줄이다.

```
- [ ] service 체인 부팅 D의 ssh 제어 연결이 한 번 `Connection timed out during banner
      exchange`로 죽었다(2026-09-28 WL 루트 게이트 1차, CT-M2 3/3회차). 평소에는 firmware가
      있든 없든 0.3초 안팎이고(각 3회, 259~377ms) 한도는 `ConnectTimeout=5`다. 한 번뿐이라
      한도를 안 고쳤다. 또 나면 그 회차의 시리얼 로그에서 sshd가 `Server listening` 뒤에
      무엇을 했는지부터 본다.
- [ ] service 체인 부팅 C의 검사 12(`ssh-keyscan`)가 한 번 빈 값으로 죽었다(2026-10-04 GE-M1
      루트 게이트, CT-M2 3/3회차 — `FAIL: ssh-keyscan saw , the guest printed SHA256:…`). 그
      회차의 시리얼 로그에서 `Server listening`은 08:17:21, dhcpcd의 `eth0: leased 10.0.2.15`는
      08:17:26이었다. 검사가 `Server listening`만 기다리고 바로 keyscan을 치는데, hostfwd는
      게스트가 그 주소를 갖기 전에는 안 닿는다. 그래서 sshd가 임대보다 5초 이상 앞서면 빈
      값이다 — 코드와 무관한 체인의 경합이다. 고치는 자리는 `service/check.sh` 검사 12 앞에
      `wait_for_log "eth0: leased"`(부팅 D의 ssh 제어 연결에도 같은 기다림이 맞다 — 위 항목의
      banner exchange 타임아웃도 같은 경합일 수 있다). 그날은 `service` 체인만 따로 세 번 돌려
      3/3을 봤다(GE-M1 plan 실측 11).
```

### 2-2. "서브프로젝트를 넘어 유효한 실측"에 73번을 더한다

그 절의 마지막 항목 72번(`rg -n '^72\. ' docs/guides/lessons.md` — "vendor된 ghostty의
`src/terminal/c/*.zig`(C API)는 …"로 시작하고 "`placement_render_info`를 옮겨 적었다(TG-M1)."로
끝난다) 뒤, 빈 줄 하나를 두고, `## 시도했으나 안 되는 접근` 제목 앞의 빈 줄은 그대로 남게 넣는다.
이 내용 그대로 넣는다.

```
73. dhcpcd는 `eth0: leased 10.0.2.15 for … seconds`를 찍은 다음에 주소를 인터페이스에 붙이고,
경로를 만들며 `eth0: adding route to 10.0.2.0/24`와 `eth0: adding default route via 10.0.2.2`를
찍는다(PE design 실측 8 — `dhcp_bind`가 로그를 먼저 찍고 `ipv4_applyaddr`를 뒤에 부른다). 그래서
`leased` 줄을 본 순간의 게스트는 아직 10.0.2.15가 아닐 수 있다. 그 사이에 hostfwd로 붙으면 SLIRP은
호스트 쪽 연결을 받아 주지만 게스트가 SYN을 버려서, `ssh-keyscan`은 빈 값을 내고 ssh는
`Connection timed out during banner exchange`로 죽는다. hostfwd로 게스트에 붙는 체인은
`eth0: adding default route via 10\.0\.2\.2` 줄까지 기다린다 — `service/check.sh`의 `boot_ssh`가
그 모양이다(PE-M0, 2026-10-04). 2026-09-28과 2026-10-04의 service 실패 둘을 처음에는 "검사가
`Server listening`만 기다리고 바로 keyscan을 친다"로 진단했는데, 그 진단이 틀렸다. `boot_ssh`는
2026-09-27(`c89157d`)부터 `leased`를 기다리고 있었고, 두 실패 다 그 기다림 뒤에 났다. 같은
모양(임대를 기다린 뒤 hostfwd)이 `firewall/check.sh`에도 있지만, 그쪽은 붙기 전에 게스트에 타이핑을
먼저 해서 그 시간 차가 지나가고 실패가 관측된 적이 없어 그대로 두었다(PE 비목표 6). SLIRP이 버려진
SYN을 언제 다시 보내는지는 재지 않았다. PE-M0 뒤에 같은 증상이 다시 나면 이 판단이 틀린 것이다 —
그 회차의 시리얼 로그에서 `adding default route` 줄과 ssh 사이에 sshd가 무엇을 찍었는지부터 본다
(PE 위험 1).
```

### 2-3. 확인

```bash
git diff --stat docs/guides/lessons.md
git diff docs/guides/lessons.md | rg '^-'
git diff docs/guides/lessons.md | rg '^\+' | head -20
```

기대.

- `--stat`은 더한 줄 16(73번 열다섯 줄과 빈 줄 하나)과 지운 줄 15다. 빈 줄을 다르게 두었으면
  더한 줄이 하나 다를 수 있다 — 그 경우 `git diff`를 읽어 빈 줄의 자리를 보고한다.
- 둘째 명령의 출력은 `--- a/docs/guides/lessons.md` 한 줄과 2-1의 열다섯 줄뿐이어야 한다. 다른
  줄이 `-`로 나오면 편집이 다른 줄을 건드린 것이다 — 되돌리고 다시 한다.
- 셋째 명령의 `+`줄은 73번의 글자뿐이다.

## Task 3: 검증(구현자)

### 3-1. 문법

```bash
bash -n service/check.sh && echo SYNTAX-OK
```

### 3-2. 진입 검사

lessons "게이트를 돌리고 읽는 법"의 명령을 `X`를 `service`로 바꿔 친다.

```bash
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./service/check.sh && require_no_early_exit_pipe ./service/check.sh &&
  require_explicit_nic ./service/check.sh && echo ENTRY-OK'
```

기대: `ENTRY-OK`.

### 3-3. `service` 체인 한 번과 시리얼 로그 넷

약 1분 10초다(GE-M1 plan 실측 11의 세 회차가 1분 9.93초 ~ 1분 12.86초). 체인을 컨테이너 안에서
배경으로 돌리고, 끝날 때까지 1초마다 `tars-init`이 든 `/tmp/tmp.*`를 `/tmp/run/pe0`로 복사한다
(확정 5 — 체인이 끝난 뒤에 복사하면 부팅 C 하나만 남는다). 복사본의 이름은 `mktemp`의 꼬리를
쓰므로 부팅마다 파일 하나다.

```bash
rm -rf /tmp/run/pe0; mkdir -p /tmp/run/pe0
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run:/tmp/run -e PE_OUT=/tmp/run/pe0 \
    -w /workspace tars-devcontainer bash -c '
  bash service/check.sh > "$PE_OUT/chain.log" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    for f in /tmp/tmp.*; do
      [ -f "$f" ] && grep -aq "tars-init" "$f" && cp "$f" "$PE_OUT/serial_${f#/tmp/tmp.}.log"
    done
    sleep 1
  done
  wait "$pid"; echo "exit=$?"' ; } 2> /tmp/run/pe0/time
tail -3 /tmp/run/pe0/chain.log; cat /tmp/run/pe0/time
rg -c '^FAIL' /tmp/run/pe0/chain.log || echo "FAIL lines: 0"
ls /tmp/run/pe0/serial_*.log | wc -l
```

기대: `exit=0`, 마지막 줄 `SV chain PASS`, `FAIL lines: 0`, 시리얼 로그 `4`. 넷이 아니면 그 수를
그대로 보고한다(복사 loop가 놓친 부팅이 있다는 뜻이다).

순서를 센다. 부팅마다 `leased`의 첫 줄 번호가 `adding default route`의 첫 줄 번호보다 작아야
한다. 호스트 셸이 zsh라서 `bash -c`로 감싼다(lessons 실측 69).

```bash
bash -c 'for f in /tmp/run/pe0/serial_*.log; do
  if rg -aq "started service a-greet" "$f"; then b=A
  elif rg -aq "started service sleeper" "$f"; then b=D
  elif rg -aq "sshd: generated a host key" "$f"; then b=B
  else b=C; fi
  l=$(rg -a -n -m1 "eth0: leased 10\.0\.2\.15 " "$f" | cut -d: -f1)
  r=$(rg -a -n -m1 "eth0: adding default route via 10\.0\.2\.2" "$f" | cut -d: -f1)
  if [ -n "$l" ] && [ -n "$r" ] && [ "$l" -lt "$r" ]; then v=ok; else v=BAD; fi
  echo "boot $b leased@$l route@$r $v"
done | sort'
```

기대: `boot A` · `boot B` · `boot C` · `boot D` 네 줄이 다 `ok`다. 줄 번호는 회차마다 다르다.

그리고 부팅 B · C · D 각각에서 dhcpcd 줄을 그대로 보인다(보고에 붙인다).

```bash
bash -c 'for f in /tmp/run/pe0/serial_*.log; do
  echo "== $f"; rg -a -n "eth0: (leased|adding)" "$f" | head -6
done'
```

기대: 파일마다 `leased` · `adding route to 10.0.2.0/24` · `adding default route via 10.0.2.2`가 이
순서로, 각각 맨 줄과 `Oct 04 …` 줄 두 번씩.

### 3-4. mutation — 새 기다림이 실제로 돈다

저장소 파일은 안 고치고 사본을 `-v`로 덮는다(lessons "범용 명령"의 mutation 모양). 패턴을 오지
않을 글자(`10\.0\.2\.9`)로 바꾸면 부팅 A는 초록으로 지나가고(그 부팅은 `boot_ssh`를 안 쓴다),
부팅 B가 약 30초 기다린 뒤 빨개져야 한다.

```bash
mkdir -p /tmp/run
cp service/check.sh /tmp/run/service_check.sh
sd -F 'default route via 10\.0\.2\.2"' 'default route via 10\.0\.2\.9"' /tmp/run/service_check.sh
chmod +x /tmp/run/service_check.sh
diff service/check.sh /tmp/run/service_check.sh
{ time docker run --rm -v "$PWD":/workspace \
    -v /tmp/run/service_check.sh:/workspace/service/check.sh:ro \
    -w /workspace tars-devcontainer bash service/check.sh > /tmp/run/pe_mut.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/run/pe_mut.time
cat /tmp/run/pe_mut.time
rg -n '^=== boot|^FAIL|a-greet answered|adding' /tmp/run/pe_mut.log
```

기대.

- `diff`가 한 줄의 차이를 보인다(`10\.0\.2\.2"` → `10\.0\.2\.9"`). 주석 줄은 `10.0.2.15`만 적고
  `10\.0\.2\.2"`를 안 가지므로 안 바뀐다. 차이가 한 줄이 아니면 돌리지 말고 보고한다.
- `exit=1`.
- `rg` 출력에 부팅 A의 `a-greet answered from outside with init's PATH`, `=== boot B: …`, 그리고
  `FAIL: dhcpcd leased but never added the default route`가 있다. `=== boot C`는 없다.
- 덤프의 패턴 줄에 `eth0: adding route to 10.0.2.0/24`와 `eth0: adding default route via 10.0.2.2`가
  보인다 — 진짜 줄은 있었고 패턴만 틀렸다는 것이 화면에서 드러난다. `fail`의 셋째 인자(`"adding"`)가
  이 진단을 위한 것이다.

mutation이 다른 자리에서 죽거나(예: 부팅 A) 통과하면 그대로 적어 보고한다. 통과했다면 새 줄이
`boot_ssh` 밖에 들어갔거나 사본이 덮이지 않은 것이다.

### 3-5. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff`(전체).
- `git diff | rg '^-'`의 출력.
- 3-1 · 3-2의 출력, 3-3의 `exit=` · 마지막 세 줄 · `time` · 시리얼 로그 수 · 순서 네 줄 · dhcpcd 줄,
  3-4의 `diff` · `exit=` · `time` · `rg` 출력.
- plan의 기대와 글자가 다른 것이 있으면 그 줄을 그대로.

## Task 4: lead가 하는 것

### 4-1. `service` 체인 다섯 번 연달아

design 검증 절의 "경합은 반복으로 본다". 5 × 약 1분 10초, 약 6분이다. Bash 도구의 10분 상한 안이지만
여유가 적으므로 `run_in_background`로 돌린다. 회차마다 Task 3-3과 같은 수집을 `/tmp/run/pe$i`로 한다.

```bash
for i in 1 2 3 4 5; do
  rm -rf /tmp/run/pe$i; mkdir -p /tmp/run/pe$i
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run:/tmp/run -e PE_OUT=/tmp/run/pe$i \
      -w /workspace tars-devcontainer bash -c '
    bash service/check.sh > "$PE_OUT/chain.log" 2>&1 & pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      for f in /tmp/tmp.*; do
        [ -f "$f" ] && grep -aq "tars-init" "$f" && cp "$f" "$PE_OUT/serial_${f#/tmp/tmp.}.log"
      done
      sleep 1
    done
    wait "$pid"; echo "exit=$?"' ; } 2> /tmp/run/pe$i/time
done
```

끝나면 회차마다 통과 여부 · 시간 · 로그 수를 본다.

```bash
bash -c 'for i in 1 2 3 4 5; do
  d=/tmp/run/pe$i
  echo "run $i: $(tail -1 $d/chain.log) | $(rg real $d/time) | logs $(ls $d/serial_*.log | wc -l)"
done'
```

기대: 다섯 줄 다 `SV chain PASS`, 로그 `4`.

순서를 한꺼번에 센다. Task 3-3의 셈을 다섯 디렉터리에 돌린다.

```bash
bash -c 'for f in /tmp/run/pe[1-5]/serial_*.log; do
  if rg -aq "started service a-greet" "$f"; then b=A
  elif rg -aq "started service sleeper" "$f"; then b=D
  elif rg -aq "sshd: generated a host key" "$f"; then b=B
  else b=C; fi
  l=$(rg -a -n -m1 "eth0: leased 10\.0\.2\.15 " "$f" | cut -d: -f1)
  r=$(rg -a -n -m1 "eth0: adding default route via 10\.0\.2\.2" "$f" | cut -d: -f1)
  if [ -n "$l" ] && [ -n "$r" ] && [ "$l" -lt "$r" ]; then v=ok; else v=BAD; fi
  echo "$b $v"
done | sort | uniq -c'
```

기대: `5 A ok` · `5 B ok` · `5 C ok` · `5 D ok`. `BAD`가 하나라도 있으면 그 파일을 열어 dhcpcd 줄의
순서를 실측 절에 그대로 옮긴다 — design 실측 8(소스의 순서)과 어긋난다는 뜻이다.

다섯 번 다 초록이라는 것이 경합이 없어졌다는 증명은 아니다. 관측된 옛 실패는 2026-09-28 WL 루트
게이트와 2026-10-04 GE-M1 루트 게이트의 한 번씩뿐이고, 그 사이에도 `service`는 여러 번 초록이었다.
그래서 다섯 번의 초록은 고치기 전에도 흔히 나왔을 결과다. 다섯 번이 보는 것은 새 기다림이 회귀를
만들지 않는다는 것과, 순서가 다섯 회차 × 부팅 넷에서 소스대로라는 것이다.
경합이 실제로 닫혔는지는 이후의 루트 게이트들이 보인다(design 위험 1).

### 4-2. 루트 게이트를 이 milestone에서 돌릴지(lead의 판단)

design 검증 절은 "셋 다 루트 게이트"라고 적었다. 이 plan은 M0에서는 돌리지 않고 M1의 루트 게이트에
맡기는 쪽을 권한다. 근거는 셋이다.

1. M0이 바꾸는 실행 파일은 `service/check.sh` 하나다. 루트 `check.sh` · `gate_lib.sh` · 다른 체인 ·
   `init` · `terminal` · initrd는 안 바뀐다. design도 "M0은 initrd를 안 바꾼다"고 적었다. 그래서 다른
   열일곱 체인의 결과는 `48431e7`(GE-M1)의 루트 게이트와 같은 입력으로 돈다.
2. `service` 체인 자체는 4-1이 다섯 번 본다. 루트 게이트는 그 체인을 세 번 돌리므로 M0에 대해서는
   4-1보다 적게 본다.
3. M1과 M2는 둘 다 initrd를 바꿔서 어차피 루트 게이트를 돌린다. 거기서 `service`가 3/3이면 M0의
   변경이 M1 · M2와 함께 섞여도 깨지지 않는다는 것까지 본다. 약 1시간 5분을 한 번 아낀다.

반대쪽 근거도 적는다. 이 저장소는 milestone마다 루트 게이트로 닫아 왔고, M0 commit만 루트 게이트
기록이 없게 된다. lead가 그 일관성을 더 무겁게 보면 4-1 뒤에 루트 게이트를 돌린다(18체인 × 3,
약 1시간 5분, `run_in_background`, 완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가
비었는지 먼저 본다).

### 4-3. 실측 절과 commit

보고와 4-1의 값을 아래 "실측한 것" 절에 채우고 commit한다. commit에 넣는 것은 `service/check.sh` ·
`docs/guides/lessons.md` · 이 plan · design이다. design은 아직 untracked이므로 이 commit에 함께 넣을지
lead가 정한다.

## 이 milestone에서 안 하는 것

- `firewall/check.sh`의 같은 모양(확정 7).
- SLIRP의 SYN 재전송 시각 재기(design 비목표 6).
- 부팅 A 검사 7의 재시도 loop를 없애는 것. 그 loop는 a-greet가 `nc -l`을 다시 여는 사이를 메우는
  것이기도 해서 이번 경합과 다른 일이다.
- 체인이 통과한 회차의 로그를 지우는 동작(확정 5)을 바꾸는 것. 이 plan의 수집 명령으로 충분하다.
- `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design의 `Status:`(design "닫을 때").

## PE-M0이 실측한 것

2026-10-04. Task 0~3은 Sonnet 서브에이전트가 하고 보고했고, lead가 diff와 로그를 직접 읽어
대조했다. Task 4는 lead가 했다.

1. Task 0의 기준값. 돌고 있는 게이트는 없었고, `boot_ssh` · 호출 셋 · `leased` 기다림의 자리가 plan의
   참고 줄 번호 그대로였다. `adding default route`는 0줄이었다.
2. Task 1 · 2의 diff. `service/check.sh`는 더한 줄 7 · 지운 줄 0이고 `rg '^-'`는 `--- a/` 한 줄뿐이었다.
   `docs/guides/lessons.md`는 더한 줄 16 · 지운 줄 14다 — plan 2-1이 "열다섯 줄"이라 적었지만 두 항목은
   5줄 + 9줄 = 14줄이었다(plan의 셈이 틀렸고 지운 글자는 plan의 인용 그대로다). `rg '^-'`에 다른 줄은
   없었다. 더한 16은 73번 열다섯 줄과 빈 줄 하나다.
3. Task 3-3의 체인 한 번. `SYNTAX-OK` · `ENTRY-OK`. 1분 13.14초, `exit=0`, `SV chain PASS`, `FAIL` 0줄,
   시리얼 로그 넷. 순서는 B `leased@362 route@366`, C `leased@358 route@362`, D `leased@369 route@373`로
   셋 다 `ok`. 부팅 A는 `BAD`로 나왔는데 변경과 무관한 수집 한계다 — 체인이 341줄에서 부팅 A의 로그를
   지우기 때문에 1초 간격 복사본(385줄)이 `soliciting a DHCP lease`에서 끊겨 `leased` 줄이 없다. 부팅
   A는 `boot_ssh`를 안 쓴다. B · C · D의 dhcpcd 줄은 셋 다 `leased` → `adding route to 10.0.2.0/24` →
   `adding default route via 10.0.2.2` 순서로 맨 줄과 `Oct 04 …` 줄 두 번씩이고 같은 초에 찍혔다(B
   09:57:42 · C 09:58:00 · D 09:58:13).
4. Task 3-4의 mutation. 사본의 차이는 335줄 하나(`10\.0\.2\.2"` → `10\.0\.2\.9"`). 1분 01.65초,
   `exit=1`. 부팅 A는 `a-greet answered from outside with init's PATH`로 지나갔고 `=== boot B` 바로 다음
   줄이 `FAIL: dhcpcd leased but never added the default route`였다. 덤프의 마커 여섯이 전부 `found`이고
   그 아래 패턴 줄에 `eth0: adding route to 10.0.2.0/24`와 `eth0: adding default route via 10.0.2.2`가
   두 번씩 보였다 — 진짜 줄은 있었고 패턴만 틀렸다는 것이 화면에서 갈렸다. `=== boot C`는 없었다.
5. Task 4-1의 다섯 회차. 다섯 다 `SV chain PASS` · `FAIL` 0줄 · 시리얼 로그 넷이고 시간은 1분 11.18초 ~
   1분 15.25초(1:13.05 · 1:12.34 · 1:11.18 · 1:12.19 · 1:15.25)다. 순서 세기의 `uniq -c`는 `5 B ok` ·
   `5 C ok` · `5 D ok`, 그리고 `2 A ok` · `3 A BAD`다. A의 `BAD` 셋은 3-3과 같은 수집 한계다 — 그 셋은
   전부 385줄에 `probing address`로 끊겨 `leased`도 `adding` 줄도 0개이고, `ok` 둘은 391줄까지 담겨
   순서가 소스대로였다. 순서가 뒤바뀐 로그는 스무 개 중 하나도 없었다.
   `rm -rf /tmp/run/pe$i`는 Claude Code의 안전 검사가 막아서(쉘 변수가 든 재귀 삭제) 지우는 줄 없이
   `mkdir -p`만으로 돌렸다 — 디렉터리가 아직 없어서 결과는 같다.
6. Task 4-2의 판단. 루트 게이트는 이 milestone에서 돌리지 않고 PE-M1의 루트 게이트에 맡긴다. plan의
   근거 셋을 그대로 받았다 — 바뀐 실행 파일이 `service/check.sh` 하나이고 initrd · 다른 체인은
   `48431e7`과 같은 입력이며, `service` 자체는 5-1이 루트 게이트의 셋보다 많이 봤다. PE-M1의 루트 게이트에서
   `service`가 3/3이면 그것이 M0의 루트 게이트 기록이다.

## 닫을 때

PE-M0은 서브프로젝트를 닫지 않는다. design "닫을 때"의 lessons 항목 중 "이월 숙제의 service 두
항목은 M0이 지운다"가 Task 2-1로 끝난다. 다음은 PE-M1 plan이다(design 결정 2~6, Opus 구현).
