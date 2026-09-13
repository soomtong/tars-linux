# NW-M3 — 게이트가 판정한다

Date: 2026-09-14
design: `docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`
앞 milestone: `docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m2.md`

M2가 세운 것은 "게스트에 주소가 붙는다" 하나다. `net/check.sh`가 검사 여덟으로
그 사슬을 보지만, 그 체인은 아직 `check.sh`의 `CHAINS` 밖에 있어서 루트
게이트가 한 번도 안 돌린다. 그리고 그 여덟 중 어느 것도 "그 주소로 무언가를
한다"를 묻지 않는다 — 주소가 인터페이스에 있는지, `/etc/resolv.conf`에 줄이
있는지까지다.

M3가 얹는 것이 그 둘이다.

1. 판정을 연결까지 늘린다. 게스트가 TCP로 상대에 붙어 우리가 정한 글자를
   읽는다. 상대는 바깥 인터넷이 아니라 QEMU 자신이다(design 결정 7).
2. 그 체인을 `CHAINS`에 들인다. 열두번째 체인이 되고 루트 게이트의 총 부팅이
   39회에서 42회가 된다.

우리 코드는 한 줄도 안 바뀐다. `init/src/net.zig`도 `config.zig`도
`guest_tools.sh`도 그대로다 — M3에서 바뀌는 파일은 `net/check.sh`와
`check.sh` 둘뿐이고, 나머지는 문서다. 이것이 이 milestone의 성질이다:
새로 만드는 것이 아니라 이미 선 것을 게이트가 매번 보게 하는 것.

## M3가 정하고 들어가는 것 일곱

design과 M0~M2가 여섯 자리에 이미 숫자를 붙였다(design 끝의 "M2가 M3에
넘기는 것"). 그중 넷이 여기서 값으로 확정되고, 셋은 M3에서 처음 정한다.

### 결정 A — 판정 상대는 QEMU다 (design 결정 7의 실행)

`-netdev user,id=n0`에 `guestfwd` 옵션을 덧붙인다.

```
guestfwd=tcp:10.0.2.100:8080-cmd:cat /tmp/tmp.XXXXXXXX
```

게스트가 `10.0.2.100:8080`으로 TCP를 걸면 QEMU가 그 연결을 가로채 지정한
명령을 실행하고 그 출력을 흘려 넣는다. M0의 실측 5가 이 QEMU에서 실제로
도는 것을 봤다.

왜 바깥으로 안 나가는가. 게이트는 같은 입력에 늘 같은 답을 내야 한다.
`google.com`으로 판정하면 회선이 흔들리는 날마다 우리 코드가 멀쩡한데도
빨간불이 되고, 그러면 게이트가 말하는 것이 "코드가 맞나"가 아니라 "오늘
인터넷이 되나"가 된다. 이 저장소는 이 원칙을 이미 여러 번 지불했다 —
SL-M2가 시간이 아니라 로그 줄로 판정한 것도 같은 이유다.

덤이 하나 있다. 리스너를 따로 띄우는 방식은 그 프로세스를 언제 죽일지,
죽었는데 체인이 안 죽는 경우를 어떻게 다룰지가 따라붙는데, `guestfwd`는
QEMU의 수명 안에 있어서 QEMU가 사라지면 함께 사라진다. 체인이 관리할
상태가 하나도 안 는다.

### 결정 B — 흘려 넣을 글자는 체인이 `mktemp`로 만든다

`$LOG`와 같은 방식이다. 파일을 `mktemp`로 만들고 `cleanup` trap에 `rm -f`를
한 줄 더한다. 저장소에 payload 파일을 두지 않는다 — 내용이 한 줄이고 그
한 줄을 아는 것은 이 체인뿐이라, 파일로 두면 "어디서 오는 글자인가"를 두
자리에서 봐야 한다.

경로에 쉼표가 없어야 한다. QEMU의 옵션 문자열이 쉼표로 갈리므로 값 안의
쉼표는 두 번 적어야 하는데, `mktemp`가 주는 `/tmp/tmp.XXXXXXXX`에는 쉼표가
없다. 이 성질에 기대는 것을 주석으로 적어 둔다.

글자는 `nwm3-outbound-ok`다. 조건이 하나뿐이다 — 게스트에 치는 명령줄에
없는 글자여야 한다(결정 E).

### 결정 C — 게스트 쪽 도구는 `nc`다

M0의 실측 5는 두 가지로 붙었다. bash의 `/dev/tcp`와 `nc.traditional`.

이 부팅의 셸은 fish다(설정 디스크가 `net=dhcp` 한 줄뿐이라 `shell`이
기본값이다). fish에는 `/dev/tcp`가 없다 — 그것은 bash의 기능이지 커널의
것이 아니다. 그래서 `nc`를 쓴다.

`nc`는 M2가 이미 넣었고 이름도 선다. `guest_tools.sh`가 실체
(`nc.traditional`)를 넣고 `make_initrd.sh`의 링크 한 줄이 `nc`라는 이름을
만든다. 즉 M3는 게스트에 아무것도 새로 안 넣는다.

`-w 5`를 준다. 상대가 끝내 안 닫는 날 체인이 거기서 매달리지 않게 하는
것이고, 실측 5에서 `nc.traditional`은 상대가 닫자마자 나왔고 뒤 명령이
정상으로 이어졌다.

`curl`은 안 친다. 실측 5에서 `curl`만 조용했는데 그것이 실패가 아니라
예상된 일이다 — `guestfwd`가 실행하는 것이 `cat`이라 HTTP 응답 형식이
아니다. `curl`은 M2가 사용자의 결정으로 넣었고(비용의 86%였다) 게이트는
그것을 한 번도 안 친다. 이 사실을 체인 주석에 남긴다.

### 결정 D — 기본 경로는 따로 본다

이 결정이 M3에서 새로 생긴 것이고, 정직함의 문제다.

`guestfwd`의 상대 `10.0.2.100`은 게스트 주소 `10.0.2.15/24`와 같은
서브넷이다. 즉 그 연결은 기본 경로를 한 번도 안 밟는다. 검사 하나로
"밖으로 나가는 길이 있다"까지 주장하면 그것은 게이트가 거짓을 말하는
것이고, GA가 일곱 자리에서 고친 것이 정확히 그 종류의 거짓이다.

그래서 둘로 가른다.

| 검사 | 무엇을 증명하나 | 무엇을 증명하지 않나 |
|---|---|---|
| `ip -4 route show` | dhcpcd가 기본 경로를 깔았다 | 그 경로로 실제 패킷이 갔다 |
| `nc 10.0.2.100 8080` | 게스트의 TCP 스택이 실제로 연결을 연다 | 그 연결이 게이트웨이를 지났다 |

둘을 더해도 "인터넷에 나간다"는 아니다. 그것은 이 게이트가 일부러 안
보는 것이고(결정 A), 사람이 손으로 `curl`을 쳐서 보는 자리는 M0의 실측
6에 남아 있다.

### 결정 E — 판정 글자는 명령줄의 에코와 안 겹쳐야 한다

`wait_for_screen`은 마지막 프레임이 아니라 로그 전체의 `screen>` 줄을
본다(`gate_lib.sh:117`). 게스트에 친 명령은 에코로 화면에 찍히므로, 패턴이
명령줄 안에 있으면 명령이 아무 일도 안 해도 초록이 된다.

이 함정을 M3의 검사 셋이 전부 밟을 수 있는 자리에 있다.

| 치는 것 | 순진한 패턴 | 왜 안 되나 | 쓰는 패턴 |
|---|---|---|---|
| `ip -4 route show` | — | 명령줄에 주소가 없다 | `default via 10\.0\.2\.2` |
| `nc -w 5 10.0.2.100 8080` | `10\.0\.2\.100` | 명령줄에 그대로 있다 | `nwm3-outbound-ok` |
| `pgrep -l dhcpcd` | `dhcpcd` | 명령줄에 그대로 있다 | `dhcpcd-alive=[1-9]` |

셋째가 이 결정이 실제로 값을 하는 자리다. `pgrep -l dhcpcd`의 출력을
`dhcpcd`로 판정하면 dhcpcd가 죽어 있어도 초록이다. 그래서 출력에만
생기는 글자를 만든다 — 명령 치환의 결과가 붙는 `dhcpcd-alive=N`이다.

치환 문법은 `config/check.sh`의 `NEG_COUNT_KEYS`와 글자 그대로 같은
모양이다(`$(`가 `shift-4 shift-9`, `)`가 `shift-0`). fish가 `$(...)`를
읽는다는 것은 그 체인이 이미 여러 판 증명했다.

### 결정 F — dhcpcd의 생존은 개수가 아니라 0인지로 본다

`pgrep -c dhcpcd`가 1을 준다고 박지 않는다. dhcpcd 10은 특권 분리를 해서
자식을 더 띄울 수 있고, 그 개수는 우리가 고른 값이 아니라 dhcpcd의 내부
사정이다. 우리가 묻는 것은 "아직 있나" 하나이므로 패턴이 `[1-9]`다.

실제 개수는 Task 2에서 시리얼 로그로 한 번 눈으로 본다. 그 값을 검사에
박지는 않고, 주석에 "이때 N이었다"로만 남긴다 — 박으면 dhcpcd를 올리는
날 이 체인이 이유 없이 빨개진다.

### 결정 G — 체인 이름은 `NW-M3`이고 배열의 맨 끝에 붙는다

`CHAINS`의 순서는 대체로 이 저장소가 그 체인을 만든 순서다. 맨 끝에 붙이면
게이트 로그의 순서가 그 역사와 같고, 실패가 났을 때 "새로 들어온 것이
어디였나"가 로그에서 바로 보인다.

`RM-M1`이 `UT-M3` 앞에 있는 것만 예외인데 그것은 RM이 먼저 끝났기
때문이다. 즉 규칙은 "끝난 순서"이고 NW가 맨 끝이 맞다.

## 고칠 파일

| 파일 | 무엇 |
|---|---|
| `net/check.sh` | payload를 만들고 QEMU 줄에 `guestfwd`를 단다. 검사 셋을 더하고 기존 검사 8의 번호를 11로 민다. 머리 주석의 "아직 CHAINS 밖이다"를 고친다 |
| `check.sh` | `CHAINS`에 `NW-M3:./net/check.sh` 한 줄. 그 위 주석 블록에 이 체인이 무엇을 보는지 한 문단 |
| design | `Status:` 줄, NW-M3 절의 결과, 실측 25~ |
| `HANDOFF.md` | 게이트 현황(열두 체인) · NW 커밋 표 · 다음에 할 것 |
| `CLAUDE.md` | 완료된 서브프로젝트 표에 Guest Network 한 줄 |
| `MEMORY.md` + `docs/decisions/` | 결정 D·E가 남길 것 하나 |

`init/` 아래는 한 글자도 안 고친다. `zig build test`가 이 milestone에서
새로 보는 것은 없다 — 그래서 Task마다 그것을 돌리기는 하되 그것이 판정하는
것은 "우리가 딴 것을 안 깨뜨렸다"뿐이다.

## Task 0 — baseline을 적어 두고 지금 상태를 확인한다

- [ ] Step 1: 저장소가 깨끗한지 본다

```bash
git -C /Users/dp/Repository/tars-linux status --short
```

기대: 아무 줄도 안 나온다. 줄이 있으면 앞 세션이 안 끝난 것이므로 먼저
무엇인지 읽는다.

- [ ] Step 2: 체인이 지금 그대로 도는지, 시간이 얼마인지 잰다

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } > /tmp/nwm3/base.log 2> /tmp/nwm3/base.time
```

먼저 `mkdir -p /tmp/nwm3`을 친다. 기대: `base.log`의 마지막 줄이 `PASS`이고
`base.time`의 `real`이 17초 안팎이다(M2에서 17.082초였다).

이 값이 Task 2 뒤의 값과 비교되는 기준선이다. 타이핑을 78키 더하므로
늘어나는 것이 정상이고, 얼마나 느는지가 Task 5에서 게이트 증가분을
설명할 수 있는지를 가른다.

- [ ] Step 3: 지금 체인 개수와 총 부팅 수를 적어 둔다

```bash
grep -c ':\./' check.sh
```

기대: `11`. 이 수가 Task 4 뒤에 12가 된다.

## Task 1 — payload를 만들고 QEMU 줄에 `guestfwd`를 단다

검사를 아직 안 더한다. 이 Task가 가르는 것은 하나다 — 이 QEMU가 우리가 적은
옵션 문자열을 받아들이는가. 문법이 틀리면 QEMU가 아예 안 뜨고, 그러면
검사를 함께 넣었을 때 "연결이 안 된다"와 "기계가 안 켜졌다"가 안 갈린다.

**Files:**
- Modify: `net/check.sh:73-82`(payload와 cleanup), `net/check.sh:131`(QEMU 줄)

- [ ] Step 1: payload를 만드는 줄을 `$LOG` 옆에 더한다

`net/check.sh`에서 이 부분을

```bash
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
```

이렇게 고친다.

```bash
LOG="$(mktemp)"
QEMU_PID=""

# NW-M3 결정 A·B. 게스트가 10.0.2.100:8080에 붙으면 QEMU가 이 파일을 cat해서
# 연결에 흘려 넣는다(아래 -netdev의 guestfwd). 듣는 프로세스가 없으므로
# 체인이 관리할 상태가 안 늘고, QEMU가 사라지면 그 자리도 함께 사라진다.
#
# 저장소에 두지 않는 이유는 이 한 줄을 아는 것이 이 체인뿐이기 때문이다.
# 파일로 두면 "무슨 글자가 오는가"를 두 자리에서 봐야 한다.
#
# 경로에 쉼표가 없다는 것에 기댄다. QEMU의 옵션 문자열은 쉼표로 갈리므로
# 값 안의 쉼표는 두 번 적어야 하는데, mktemp가 주는 이름에는 쉼표가 없다.
#
# 글자의 유일한 조건은 게스트에 치는 명령줄에 없어야 한다는 것이다
# (결정 E). wait_for_screen이 로그 전체의 screen> 줄을 보므로 명령의
# 에코도 화면이고, 패턴이 거기 있으면 연결이 하나도 안 돼도 초록이 된다.
PAYLOAD="$(mktemp)"
printf 'nwm3-outbound-ok\n' > "$PAYLOAD"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$PAYLOAD"
}
trap cleanup EXIT
```

- [ ] Step 2: QEMU의 `-netdev` 줄에 옵션을 덧붙인다

이 한 줄을

```bash
  -netdev user,id=n0 \
```

이렇게 고친다.

```bash
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
```

따옴표가 필요한 이유는 값 안에 공백이 있기 때문이다(`cat /tmp/tmp.XXXX`).
따옴표 없이 두면 셸이 거기서 인자를 갈라 QEMU가 `cat`을 옵션으로 읽는다.

- [ ] Step 3: 체인을 돌려 QEMU가 그 옵션을 받는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh > /tmp/nwm3/t1.log 2>&1; echo "exit=$?"
```

기대: `exit=0`이고 마지막 줄이 `PASS`다. 검사를 아직 안 더했으므로 통과
내용은 Task 0과 같고, 달라진 것은 QEMU가 옵션 하나를 더 받았다는 것뿐이다.

실패하면 거의 확실히 문법이다. 그때 `t1.log`의 맨 위를 본다 —
`qemu-system-x86_64: -netdev ...: ...` 한 줄이 이유를 말하고, 그 경우
`terminal never rendered a prompt`가 아니라 QEMU 자신의 에러가 먼저 찍힌다.

- [ ] Step 4: 커밋

```bash
git add net/check.sh
git commit -m "Let QEMU answer the guest on a fixed address"
```

## Task 2 — 검사 셋을 더한다

**Files:**
- Modify: `net/check.sh:247-274`(검사 7 뒤에 셋을 넣고 기존 8의 번호를 민다)

- [ ] Step 1: 검사 7(`/etc/resolv.conf`) 바로 뒤에 검사 8·9·10을 넣는다

`echo "the hook wrote /etc/resolv.conf"` 줄 다음, `# ── 검사 8: QEMU가 붙인
기본 NIC는 안 보인다` 줄 앞에 이것을 넣는다.

```bash
# ── 검사 8: 기본 경로가 생겼나 ────────────────────────────────────────
# 이 검사는 아래 검사 9가 무엇을 증명하고 무엇을 증명하지 않는지를 가른다.
#
# guestfwd의 상대 10.0.2.100은 게스트 주소 10.0.2.15/24와 같은 서브넷이라,
# 그 연결은 기본 경로를 한 번도 안 밟는다. 그러니까 검사 9 하나로 "밖으로
# 나가는 길이 있다"까지 말하면 게이트가 거짓을 말하는 것이다. 그 길은
# 여기서 따로 본다.
#
# 이 줄도 우리 코드가 아니라 dhcpcd가 쓴 것이다(design 결정 6의 경계).
# 값이 고정인 이유는 SLIRP의 규칙이 고정이기 때문이다 — 게이트웨이가
# 10.0.2.2다(design 결정 4).
#
# 둘을 더해도 "인터넷에 나간다"는 아니다. 그것은 이 게이트가 일부러 안
# 보는 것이고(design 결정 7), 사람이 손으로 확인한 자리는 M0의 실측 6이다.
echo "=== typing 'ip -4 route show' ==="
type_keys i p spc minus 4 spc r o u t e spc s h o w ret

if ! wait_for_screen "default via 10\.0\.2\.2"; then
  fail "dhcpcd never installed a default route" "terminal: screen>"
fi
echo "the guest has a default route via 10.0.2.2"

# ── 검사 9: 게스트가 TCP로 상대에 붙나 ────────────────────────────────
# design 결정 7이 이 자리다. 판정을 SLIRP 경계 안에서 닫는 이유는 게이트가
# 같은 입력에 늘 같은 답을 내야 하기 때문이다 — google.com으로 판정하면
# 회선이 흔들리는 날마다 우리 코드가 멀쩡한데 빨간불이 되고, 그러면 이
# 게이트가 말하는 것이 "코드가 맞나"가 아니라 "오늘 인터넷이 되나"가 된다.
#
# 듣는 프로세스는 없다. QEMU가 10.0.2.100:8080으로 오는 연결을 가로채
# 우리가 만든 파일을 흘려 넣는다(위 -netdev의 guestfwd, M0 실측 5).
#
# 게스트 쪽 도구가 nc인 이유. 실측 5는 bash의 /dev/tcp로도 붙었지만 이
# 부팅의 셸은 fish이고(설정 디스크에 net=dhcp 한 줄뿐이라 shell이 기본값
# 이다) fish에는 그 경로가 없다 — 그것은 bash의 기능이지 커널의 것이 아니다.
# nc는 M2가 넣었고 이름은 make_initrd.sh의 링크가 세운다(실체는
# nc.traditional). 즉 이 검사는 게스트에 아무것도 새로 요구하지 않는다.
#
# -w 5는 상대가 끝내 안 닫는 날 여기서 매달리지 않기 위한 것이다. 실측
# 5에서 nc.traditional은 상대가 닫자마자 나왔고 뒤 명령이 정상으로 이어졌다.
#
# curl은 안 친다. 실측 5에서 curl만 조용했는데 그것이 실패가 아니라 예상된
# 일이다 — guestfwd가 실행하는 것이 cat이라 HTTP 응답 형식이 아니다. curl은
# 게스트에 있지만(M2 결정 E) 이 게이트는 한 번도 안 친다.
#
# 판정 글자가 명령줄에 없는 글자여야 한다(결정 E). wait_for_screen은 마지막
# 프레임이 아니라 로그 전체의 screen> 줄을 보므로 친 명령의 에코도 화면이다.
# 10.0.2.100으로 판정하면 연결이 하나도 안 돼도 초록이 된다.
echo "=== typing 'nc -w 5 10.0.2.100 8080' ==="
type_keys n c spc minus w spc 5 spc 1 0 dot 0 dot 2 dot 1 0 0 spc 8 0 8 0 ret

if ! wait_for_screen "nwm3-outbound-ok"; then
  fail "the guest could not open a TCP connection through SLIRP" \
    "terminal: screen>"
fi
echo "the guest read our payload over TCP"

# ── 검사 10: dhcpcd가 아직 살아 있나 ──────────────────────────────────
# 리스는 한 번 받고 끝이 아니다. dhcpcd가 배경에 남아 갱신을 맡는다(M0
# 실측 4가 그 프로세스가 PID 1에 재부모화되는 것을 봤다). 받자마자 죽어도
# 검사 5·6·7은 전부 초록이므로 그 실패는 이 자리에서만 보인다.
#
# 그리고 이 검사가 아래 종료 검사의 뜻을 만든다. 유예 음성 검사(grace
# period expired)는 "SIGTERM을 안 받은 것이 없다"는 말인데, 그때 dhcpcd가
# 이미 죽어 있었으면 그 초록이 아무것도 증명하지 않는다.
#
# 개수를 1로 박지 않는다(결정 F). dhcpcd 10은 특권 분리로 자식을 더 띄울
# 수 있고 그 수는 우리가 고른 값이 아니다. 우리가 묻는 것은 "아직 있나"
# 하나다.
#
# 왜 pgrep -l이 아닌가. 친 명령의 에코가 화면이고 거기에 dhcpcd가 이미
# 있다(결정 E). 그래서 출력에만 생기는 글자로 판정한다 — 명령 치환의
# 결과가 붙는 dhcpcd-alive=N이다. 치환 문법은 config/check.sh의
# NEG_COUNT_KEYS와 같은 모양이고($(가 shift-4 shift-9, )가 shift-0),
# fish가 그것을 읽는다.
echo "=== typing 'echo dhcpcd-alive=\$(pgrep -c dhcpcd)' ==="
type_keys e c h o spc d h c p c d minus a l i v e equal \
  shift-4 shift-9 p g r e p spc minus c spc d h c p c d shift-0 ret

if ! wait_for_screen "dhcpcd-alive=[1-9]"; then
  fail "dhcpcd is not running any more" "terminal: screen>"
fi
echo "dhcpcd is still running"
```

- [ ] Step 2: 기존 검사 8의 번호를 11로 민다

이 줄

```bash
# ── 검사 8: QEMU가 붙인 기본 NIC는 안 보인다 ──────────────────────────
```

을 이렇게 고친다. 본문은 한 글자도 안 건드린다.

```bash
# ── 검사 11: QEMU가 붙인 기본 NIC는 안 보인다 ─────────────────────────
```

- [ ] Step 3: 머리 주석에서 검사 개수를 고친다

파일 맨 위의 이 문단

```bash
# 이 체인은 아직 check.sh의 CHAINS에 없다. 게이트에 들이는 것은 NW-M3이고
# 그때 판정이 주소와 바깥 연결까지 늘어난다. 지금은 단독으로 돌린다.
```

을 이렇게 고친다. (`CHAINS`에 실제로 들어가는 것은 Task 4다. 여기서는
검사가 늘어난 것만 적는다.)

```bash
# M3가 판정을 연결까지 늘렸다. 검사 8이 기본 경로를, 검사 9가 실제 TCP
# 연결을, 검사 10이 dhcpcd의 생존을 본다. 상대는 바깥 인터넷이 아니라
# QEMU 자신이다(design 결정 7) — 회선이 흔들려도 이 게이트의 답은 안 바뀐다.
#
# 이 체인은 Task 4에서 check.sh의 CHAINS에 들어간다. 그때까지는 단독으로
# 돌린다.
```

- [ ] Step 4: 체인을 돌려 검사 셋이 다 초록인지 본다

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } > /tmp/nwm3/t2.log 2> /tmp/nwm3/t2.time
tail -20 /tmp/nwm3/t2.log; tail -3 /tmp/nwm3/t2.time
```

기대 출력 중 새로 생기는 줄 셋:

```
the guest has a default route via 10.0.2.2
the guest read our payload over TCP
dhcpcd is still running
```

그리고 마지막이 `PASS`다. 시간은 Task 0의 17초에서 늘어난다 — 타이핑 78키가
늘었으니 20~28초 사이면 예상 안이다. `t2.time`의 값을 적어 둔다(Task 5에서
게이트 증가분을 설명할 때 쓴다).

첫 회차가 검사 9에서 죽으면 `t2.log` 끝의 `--- last 60 lines ---`를 읽는다.
`nc: ... Connection refused`면 guestfwd가 안 붙은 것이고, 아무 말도 없으면
`-w 5`가 먼저 끝난 것이다.

- [ ] Step 5: dhcpcd 프로세스가 실제로 몇 개였는지 눈으로 본다

이것은 검사에 박지 않고 주석에만 남길 값이다(결정 F).

```bash
grep -a "dhcpcd-alive=" /tmp/nwm3/t2.log
```

`t2.log`에는 화면이 안 남으므로 안 나오는 것이 정상이다. 값을 보려면
시리얼 로그를 꺼내야 한다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/nwm3:/tmp/nwm3 -w /workspace \
  tars-devcontainer bash -c '
  bash net/check.sh > /tmp/nwm3/t2b.log 2>&1; echo "exit=$?"
  for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then cp "$f" /tmp/nwm3/serial.log; fi
  done'
grep -ao "dhcpcd-alive=[0-9]" /tmp/nwm3/serial.log | tail -1
```

기대: `dhcpcd-alive=1` 또는 `=2`. 나온 값을 검사 10의 주석 끝에 한 줄로
적는다 — 예: `# 2026-09-14에 이 값이 1이었다.`

- [ ] Step 6: 커밋

```bash
git add net/check.sh
git commit -m "Ask the guest to open a connection and read what comes back"
```

## Task 3 — 반사실 하나로 검사 9가 진짜 보는지 확인한다

이 저장소의 규칙이다. 검사를 더하면 그 검사가 없을 때 빨간불이 되는 것을
한 번 본다. 안 보면 "늘 초록인 검사"를 하나 더 만든 것과 구별이 안 된다.

방법은 `/tmp` 사본을 `-v`로 덮어씌우는 것이다 — 저장소 파일이 한 번도 안
바뀌므로 되돌리는 것을 잊는 경로가 없다.

- [ ] Step 1: guestfwd가 듣는 포트만 옮긴 사본을 만든다

```bash
mkdir -p /tmp/nwm3
sed 's/8080-cmd/18080-cmd/' net/check.sh > /tmp/nwm3/check.sh
chmod +x /tmp/nwm3/check.sh
grep -n "guestfwd" /tmp/nwm3/check.sh
```

기대: `guestfwd=tcp:10.0.2.100:18080-cmd:cat ${PAYLOAD}`. 게스트는 여전히
8080으로 걸므로 아무도 안 받는다.

`chmod +x`를 함께 치는 것은 M2 실측 22의 함정 때문이다. 여기서는 `bash
net/check.sh`로 부르므로 실행 비트가 필요 없지만, 습관을 유지한다 —
`./`로 부르는 자리에서 그것을 빼면 엉뚱한 메시지로 죽는다.

- [ ] Step 2: 그 사본으로 돌린다

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/nwm3/check.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh \
  > /tmp/nwm3/cf.log 2>&1; echo "exit=$?"
grep -a "^FAIL\|^the guest\|^dhcpcd" /tmp/nwm3/cf.log
```

기대: `exit=1`이고

```
FAIL: the guest could not open a TCP connection through SLIRP
```

앞의 검사 여덟은 전부 초록이어야 한다. 만약 검사 8(기본 경로)에서 먼저
죽으면 사본이 포트 말고 다른 것도 건드린 것이므로 `sed` 결과를 다시 본다.

- [ ] Step 3: 왜 검사 8·10의 반사실은 안 하는지 적어 둔다

검사 8(기본 경로)을 겨냥하려면 SLIRP의 게이트웨이를 옮겨야 하는데
(`-netdev user,net=10.0.3.0/24`), 그러면 게스트 주소도 함께 바뀌어 검사
5(`eth0: leased 10.0.2.15`)가 먼저 죽는다. 겨냥한 검사가 아니라 앞의
검사에 걸리는 것이고, SL-M2 실측 3이 글자 그대로 같은 것을 겪었다.

검사 10(dhcpcd 생존)을 겨냥하려면 게스트에서 dhcpcd를 죽여야 하는데, 그
타이핑을 체인 사본에 넣는 것은 검사를 바꾸는 것이 아니라 게스트를 바꾸는
것이라 반사실의 모양이 아니다.

둘 다 안 하는 대신 그 이유를 plan의 이 자리와 design의 실측 절에 남긴다.
새 검사 셋 중 반사실을 본 것은 검사 9 하나다.

- [ ] Step 4: 사본을 지운다

```bash
rm -f /tmp/nwm3/check.sh
git status --short
```

기대: `git status`가 아무 줄도 안 낸다. 저장소 파일은 애초에 안 건드렸다.

## Task 4 — 체인을 `CHAINS`에 들인다

**Files:**
- Modify: `check.sh:224-239`(주석 한 문단과 배열 한 줄)
- Modify: `net/check.sh`(머리 주석의 "Task 4에서 들어간다"를 지운다)

- [ ] Step 1: `check.sh`의 주석 블록 끝에 이 체인의 문단을 더한다

`# 회차당 부팅 1회라 총 부팅 횟수는 36회에서 39회가 된다.`(UT 문단의 끝)
다음, `# 이름과 경로를 한 곳에 모은다.` 앞에 넣는다.

```bash
# NW 체인은 게스트의 네트워크를 본다. 열두 체인 중 유일하게 -netdev를 달고
# 뜬다 — 나머지 열하나는 NIC가 아예 없다. 커널에 virtio-net 하나만 켜고
# e1000도 r8169도 안 켠 것이 그 성질을 지탱한다(NW design 결정 3). 이 체인의
# 검사 11이 그 음성을 매번 확인한다.
#
# 설정을 주는 방식도 이 체인만 다르다. 다른 체인들은 빈 디스크를 물리거나
# 게스트에서 타이핑으로 쓰는데, 이 체인은 net=dhcp 한 줄을 미리 담아 굽는다
# (net/make_disk.sh의 debugfs). 그래서 부팅 하나로 tars.conf의 키를 실제로
# 읽는다.
#
# 판정이 바깥 인터넷에 안 닿는다. QEMU의 guestfwd가 10.0.2.100:8080으로
# 오는 연결을 가로채 체인이 만든 파일을 흘려 넣고, 게스트가 nc로 그 글자를
# 읽는다 — 회선이 흔들려도 이 게이트의 답은 안 바뀐다(NW design 결정 7).
#
# 우리 코드가 하는 일은 로그 두 줄이 전부다(net link eth0 is up ·
# started dhcpcd on eth0). 주소도 기본 경로도 /etc/resolv.conf도 dhcpcd가
# 쓴다. 그래서 이 체인의 검사 대부분은 우리 코드가 아니라 그 경계가 제대로
# 그어졌는지를 본다.
#
# 회차당 부팅 1회라 총 부팅 횟수는 39회에서 42회가 된다.
```

- [ ] Step 2: 배열에 한 줄을 더한다

```bash
  "UT-M3:./tools/check.sh"
  "NW-M3:./net/check.sh"
)
```

- [ ] Step 3: 진입 검사가 이 체인을 통과시키는지 먼저 본다

게이트 전체(30분)를 돌리기 전에 진입 검사만 확인한다. `net/check.sh`는
빌드 스텝 넷을 전부 부르고 파이프 뒤 `grep -q`가 없어야 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  grep -vE "^[[:space:]]*#" net/check.sh | grep -c "cd ../kernel && ./build.sh)"
  grep -vE "^[[:space:]]*#" net/check.sh | grep -c "cd ../init && zig build)"
  grep -vE "^[[:space:]]*#" net/check.sh | grep -c "./prepare.sh"
  grep -vE "^[[:space:]]*#" net/check.sh | grep -c "./make_initrd.sh"
  grep -nE "\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q" net/check.sh | \
    grep -vE "^[0-9]+:[[:space:]]*#" ; echo "pipe hits done"'
```

기대: 앞의 넷이 전부 1 이상이고, 마지막 `grep`이 아무 줄도 안 낸 뒤
`pipe hits done`만 찍힌다.

- [ ] Step 4: `net/check.sh` 머리 주석에서 Task 4 문장을 지운다

Task 2 Step 3에서 넣은 두 줄

```bash
# 이 체인은 Task 4에서 check.sh의 CHAINS에 들어간다. 그때까지는 단독으로
# 돌린다.
```

을 이것으로 바꾼다.

```bash
# 이 체인은 check.sh의 CHAINS에 열두번째로 들어 있다. 단독으로도 돌아간다
# (docker run ... bash net/check.sh).
```

- [ ] Step 5: 체인 수가 12인지 확인하고 커밋

```bash
grep -c ':\./' check.sh
git add check.sh net/check.sh
git commit -m "Put the network chain in front of the gate"
```

기대: `12`.

## Task 5 — 루트 게이트를 돌린다

이 milestone의 끝났다 기준이다 — 루트 게이트가 열두 체인을 돌고 3/3이다.
약 31분 걸린다(직전 기준선 29분 53.84초 + NW 체인 3회).

- [ ] Step 1: 게이트를 돌린다

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

`| tail`을 붙이지 않는다 — 파이프가 닫힐 때까지 아무것도 안 나와서 진행을
못 본다. 30분 넘게 걸리므로 사용자에게 먼저 알린다.

- [ ] Step 2: 판정과 시간을 읽는다

```bash
tail -3 /tmp/gate.log
tail -5 /tmp/gate.time
grep -c "PASS: 3/3" /tmp/gate.log
```

기대: 마지막 줄이 `TARS check PASS: all chains 3/3 consecutive runs succeeded`,
`PASS: 3/3`이 12줄, `real`이 31분 안팎.

- [ ] Step 3: 커널을 다시 안 구웠는지 확인한다

```bash
grep -c "skipping make" /tmp/gate.log
```

기대: `35`. 규칙이 `체인 수 × 3 − 1`이고 이제 체인이 열둘이다(GL-M1).
34면 clean이 지운 자리를 한 번 더 빌드한 것이고, 36이면 clean이 지운
자리에서도 건너뛴 것이라 잘못이다.

- [ ] Step 4: 증가분이 설명되는 값인지 본다

Task 2에서 잰 체인 단독 시간 × 3이 게이트 증가분과 맞는지 본다. 예를 들어
체인이 24초면 72초이고, 기준선 29분 53.84초에 더하면 31분 06초쯤이다.

이 게이트의 잡음이 ±3분이라 그보다 작은 차이는 갈렸다고 말하지 않는다.
즉 증가분이 예상과 30초쯤 어긋나도 그것은 발견이 아니다 — 판정은 "설명
가능한 크기인가"이지 "정확히 맞나"가 아니다.

크게 벗어나면(예: 40분) 코드보다 기계를 먼저 의심한다(TR-M2의 6시간
12분이 Chrome이었다).

- [ ] Step 5: 커밋할 것이 없는지 확인한다

```bash
git status --short
```

기대: 아무 줄도 안 나온다. 게이트는 저장소 파일을 안 바꾼다.

## Task 6 — 문서를 닫고 기억을 남긴다

- [ ] Step 1: design의 `Status:` 줄을 고친다

`docs/superpowers/specs/2026-09-13-tars-guest-network-design.md:4`

```
Status: 완료(2026-09-14) — M0~M3을 전부 끝냈다. 열두번째 체인이 게이트 안에 있다.
```

- [ ] Step 2: design의 NW-M3 절에 결과를 적는다

`### NW-M3 — 게이트가 판정한다` 절의 끝 기준 문장 다음에 붙인다.

```
⚠ 2026-09-14에 끝났다. 체인이 검사 열하나가 됐고 CHAINS의 열두번째다.
M3에서 새로 정한 것은 결정 D(기본 경로를 따로 본다)와 결정 E(판정 글자가
명령줄의 에코와 안 겹쳐야 한다)이고, 둘 다 "게이트가 거짓을 말하지 않게
하는" 같은 종류의 결정이다.
```

- [ ] Step 3: design의 실측 절에 M3가 잰 것을 더한다

`## NW-M2가 실행으로 증명한 것` 절 뒤에 새 절을 만든다. 실측 번호는
25부터다. 적을 것은 Task 2·3·5에서 실제로 나온 값들이다.

```
## NW-M3가 실행으로 증명한 것

### 실측 25 — guestfwd 판정이 체인 안에서 선다
(Task 2 Step 4의 실제 출력 셋과 체인 단독 시간을 적는다)

### 실측 26 — 반사실이 검사 9에서 정확히 죽는다
(Task 3 Step 2의 FAIL 줄과, 앞 검사 여덟이 초록이었다는 것을 적는다)

### 실측 27 — 게이트가 열둘이 되고 시간이 얼마가 됐다
(Task 5의 real 값, PASS 12줄, skipping make 35를 적는다)
```

- [ ] Step 4: `CLAUDE.md`의 완료 표에 한 줄을 더한다

`| Shutdown Latency (SL-M0~M2) | 2026-09-13 | ... |` 다음에.

```
| Guest Network (NW-M0~M3) | 2026-09-14 | `tars.conf`의 `net=dhcp`가 게스트에 주소를 붙인다. 판정은 SLIRP 안에서 닫힌다. 열두번째 체인 `net/check.sh` |
```

- [ ] Step 5: 기억을 하나 남긴다

`docs/decisions/project_gate_screen_echo.md`를 만든다. 내용은 결정 E다 —
`wait_for_screen`이 로그 전체의 `screen>` 줄을 보므로 친 명령의 에코도
화면이고, 판정 패턴이 명령줄 안에 있으면 그 검사는 늘 초록이다. 처방은
출력에만 생기는 글자를 만드는 것이고(`dhcpcd-alive=$(pgrep -c dhcpcd)`),
같은 함정을 `config/check.sh`의 `NEG_COUNT_KEYS`가 이미 다른 이유로
(SD 실측 11의 `grep -x`) 피해 갔다는 것을 링크한다.

`MEMORY.md`에 한 줄을 더한다.

```
- [게이트 화면 판정은 자기가 친 명령도 화면으로 센다](docs/decisions/project_gate_screen_echo.md) — 판정 글자는 출력에만 있어야 한다
```

- [ ] Step 6: `HANDOFF.md`를 고친다

고칠 자리 넷이다.

1. 제목과 "지금 어디인가" — NW가 닫혔다. 다음 방향은 사용자가 고른다.
2. NW 커밋 표에 M3의 커밋 넷을 더한다.
3. "게이트 현황" — 열두 체인, `CHAINS` 목록에 `NW-M3`, 새 `real` 값,
   `⚠ net/check.sh는 CHAINS 밖이다` 문단을 지운다, monitor 포트 목록에
   45464가 이미 있다.
4. "바로 다음에 할 것" — NW-M3 자리를 지우고, 이월 숙제에서 고를 다음
   후보를 사용자에게 묻는 자리로 바꾼다.

- [ ] Step 7: 커밋

```bash
git add docs CLAUDE.md MEMORY.md HANDOFF.md
git commit -m "Close the guest network with a gate that sees it"
```

## 이 plan이 안 하는 것

- `curl`을 게이트가 치게 하지 않는다. 실측 5가 `guestfwd`로는 HTTP가 안
  된다고 쟀고, 진짜 HTTP를 치려면 바깥으로 나가야 하는데 그것이 결정 A가
  버린 것이다.
- dhcpcd를 감독 목록에 넣지 않는다. design 결정 9의 갈래 A 그대로다 —
  "죽으면 다시 띄운다"는 별개의 이유로 여는 문이고, 지금은 그 이유가 없다.
- IPv6을 안 본다. 커널에 `CONFIG_IPV6`가 없고 SLIRP의 IPv6도 안 켰다.
- 실기(RM 체인)에서 네트워크를 안 본다. 그 기계의 NIC는 virtio-net이
  아니고, 드라이버를 켜는 것은 이 서브프로젝트의 범위 밖이다.
