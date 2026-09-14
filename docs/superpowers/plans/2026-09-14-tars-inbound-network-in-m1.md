# IN-M1 — 게스트가 듣고 체인이 읽는다

design: `docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md`

Goal: `net/check.sh`에 `hostfwd` 한 줄과 검사 둘을 더해서, 게스트가 포트를
열고 바깥에서 붙어 바이트를 읽는 것을 게이트가 매번 확인하게 만든다.

Architecture: 우리 코드는 0줄이다. 듣는 것은 게스트의 `nc`이고, 거는 것은
체인 자신의 bash `/dev/tcp`이며, 그 둘을 잇는 것은 QEMU SLIRP의 `hostfwd`
하나다. 그래서 이 milestone이 바꾸는 저장소 파일은 `net/check.sh` 한 개다.

Tech Stack: QEMU SLIRP `hostfwd`, bash의 `/dev/tcp`와 `read -r -t`, 게스트의
`nc.traditional`, 커널이 직접 만드는 `/proc/net/tcp`.

---

## M0이 이 plan에 넘긴 것

일곱이고 전부 design의 "M0이 M1에 넘기는 것"에 있다. 여기서 실제로 쓰는
자리를 함께 적는다.

| M0이 넘긴 것 | 이 plan의 어디에 쓰이나 |
|---|---|
| 판정은 바이트 수로 한다(실측 4) | Task 3의 `case "$INBOUND_GOT" in` |
| 읽기의 종료 조건을 정해야 한다(실측 5·위험 7) | Task 0이 정한다 |
| 재시도는 짧아도 된다(실측 5) | Task 3의 10회 × 0.2초 |
| 검사 12는 `1F90`을 세면 된다(실측 1) | Task 2 |
| 커널·도구를 안 건드린다 | 바꾸는 파일이 `net/check.sh` 하나다 |
| 포트는 45465·45466(실측 6) | Task 1이 45465를, M2가 45466을 쓴다 |
| 리스너가 끝날 때 fish가 job 줄을 찍는다(실측 2) | Task 3 끝의 주의 |

## Task 0 — 읽기의 종료 조건을 정하고 design에 적는다

design 위험 7이 처방 후보 둘을 열어 두었고 M1이 고르기로 돼 있다. 고르는
것이 첫 Task인 이유는 이 결정이 Task 2의 타이핑과 Task 3의 읽기 모양을 둘 다
정하기 때문이다.

고른 것은 체인 쪽 `read -r -t`다. 근거 셋.

하나, 게스트에 요구하는 것이 없다. `nc -q 0`은 `nc.traditional`이 그 옵션을
실제로 받는지가 미확인이고, 안 받으면 `nc`가 usage를 찍고 죽는다. 그 증상은
"받는 길이 안 섰다"와 화면에서 구별되지 않는다 — 이 사이클이 가장 피해야
하는 모양이다. 확인하려면 부팅이 한 번 더 든다.

둘, 형식 가정의 양쪽 끝이 같은 파일 안에 있다. `read`가 가정하는 것은 "판정
글자가 개행으로 끝나는 한 줄"인데, 그 한 줄을 만드는 `echo inm1-inbound-ok`를
체인 자신이 타이핑한다. 조용히 깨질 자리가 없다.

셋, 음성 쪽이 함께 싸진다. 듣는 것이 없으면 QEMU가 붙여 주고 곧바로
닫으므로(실측 4) `read`가 즉시 EOF를 보고 빈 값으로 돌아온다. IN-M2의 검사
15가 기다릴 필요가 없어진다.

- [x] Step 1: design에 결정 10을 더한다

`### 결정 9 — 커널 .config는 안 건드린다. 다만 M0이 확인한다` 절 바로 뒤,
`## 비목표` 절 앞에 아래를 넣는다.

```markdown
### 결정 10 — 읽기의 종료 조건은 체인 쪽 `read -r -t`다 (M1이 골랐다)

위험 7이 열어 둔 후보 둘 중 앞의 것이다. 체인이 `cat <&3`로 끝까지 읽지
않고 `read -r -t <초>`로 한 줄만 읽고 닫는다.

`nc -q 0`을 안 고른 이유가 셋이다. 하나, `nc.traditional`이 그 옵션을 실제로
받는지가 미확인이고 안 받으면 `nc`가 usage를 찍고 죽는데 그 증상이 "받는
길이 안 섰다"와 화면에서 안 갈린다. 둘, 확인하려면 부팅이 한 번 더 든다.
셋, 게이트가 치는 명령이 길어진다.

치르는 값은 체인이 "판정 글자가 개행으로 끝나는 한 줄"이라는 형식을
가정하게 되는 것이다. 그 가정이 안전한 이유는 그 한 줄을 만드는
`echo inm1-inbound-ok`를 체인 자신이 타이핑하기 때문이다 — 가정의 양쪽 끝이
같은 파일 안에 있으므로 한쪽만 바뀌는 경로가 없다.

덤으로 음성 쪽이 싸졌다. 듣는 것이 없으면 QEMU가 붙여 주고 곧바로 닫으므로
(실측 4) `read`가 즉시 EOF를 보고 빈 값으로 돌아온다. IN-M2의 검사 15가
상한을 기다릴 필요가 없다.
```

- [x] Step 2: 위험 7에 처방이 정해졌다는 표시를 단다

`### 위험 7 — 받은 쪽이 연결을 안 닫는다 (M0이 찾았다)` 절의 마지막 문단
뒤에 한 줄을 더한다.

```markdown
⚠ M1이 앞의 것을 골랐다(결정 10). 게스트 쪽 `nc`는 그대로 두고 체인이
`read -r -t`로 한 줄만 읽는다.
```

- [x] Step 3: 고쳐진 자리를 확인한다

```bash
grep -n "결정 10\|M1이 앞의 것을 골랐다" \
  docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md
```

Expected: 줄 둘. 하나는 결정 절의 제목이고 하나는 위험 7의 `⚠` 줄이다.

## Task 1 — QEMU 줄에 `hostfwd` 하나

- [x] Step 1: 포트 상수 둘을 `MONITOR_PORT` 옆에 둔다

`net/check.sh:75`의 `MONITOR_PORT=45464` 바로 아래에 넣는다.

```bash
# IN-M1. 바깥에서 게스트로 들어오는 입구다. 45465는 monitor 대역
# (45455~45464 · 45471) 밖이고, M0의 실측 6이 컨테이너 안에서 이 번호가
# 비어 있는 것을 실제로 열어 보고 확인했다. 45466은 IN-M2의 반대 방향 몫이다.
#
# 127.0.0.1에 묶는 것이 design 결정 6이다. 호스트 주소를 비우면 QEMU가 모든
# 인터페이스에 묶는데, 체인이 붙는 자리가 127.0.0.1이므로 기능상 손해가 없고
# 이 컨테이너가 어떤 네트워크에 놓여 있든 포트가 밖으로 안 샌다.
INBOUND_PORT=45465
GUEST_LISTEN_PORT=8080
```

게스트 쪽 8080이 아래 `guestfwd`의 8080과 겹쳐 보이지만 다른 자리다.
`guestfwd`가 가로채는 것은 게스트가 `10.0.2.100:8080`으로 거는 것이고, 이
`hostfwd`가 잇는 것은 게스트 자신의 주소 `10.0.2.15`의 8080이다. 방향도
주소도 다르다 — 그래도 이것은 아직 추론이고, Task 4의 실행이 답한다.

- [x] Step 2: `-netdev` 값에 `hostfwd`를 더한다

`net/check.sh:152`의 이 줄을

```bash
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
```

이것으로 바꾼다.

```bash
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${INBOUND_PORT}-10.0.2.15:${GUEST_LISTEN_PORT},guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
```

`hostfwd`를 `guestfwd` 앞에 둔다. QEMU의 옵션 문자열은 쉼표로 갈리므로 순서
자체는 상관이 없지만, `cmd:` 값만 길이가 변하는 조각이라 그것을 끝에 두면
사람이 이 줄을 읽을 때 경계가 어디인지 눈에 보인다. 위의 주석이 이미 "경로에
쉼표가 없다는 것에 기댄다"고 적어 둔 자리가 그 조각이다.

값 형식은 `tcp:<호스트주소>:<호스트포트>-<게스트주소>:<게스트포트>`이고 쉼표가
안 들어간다(design 확인 7). M0의 하네스가 같은 형식으로 둘을 이어 붙여 돌렸다
(실측 6).

- [x] Step 3: 그 줄 위의 주석에 한 문단을 더한다

`# 결정 4의 두 줄이 아래 -netdev과 -device다.`로 시작하는 문단 뒤에 넣는다.

```bash
# IN-M1이 그 -netdev 값에 hostfwd를 하나 더했다. guestfwd가 게스트 → 바깥
# 방향이고 hostfwd가 그 반대다. 이 한 줄이 없으면 바깥에서 게스트로 들어오는
# 입구가 아예 존재하지 않는다 — 검사 13의 반사실이 그것을 확인한 자리다.
```

- [x] Step 4: 지운 줄이 의도한 줄 하나뿐인지 본다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 딱 하나이고 그것이 옛 `-netdev` 줄이다. 이 저장소의 규칙
(CLAUDE.md 진행 방식 2번)이라 매 편집 뒤에 본다.

## Task 2 — 검사 12: 게스트가 포트를 열었나

검사 11(`no driver we did not turn on appeared`)을 찍는 `echo` 줄 뒤,
`# ── 끈다 ──`로 시작하는 절 앞에 넣는다.

이 검사가 검사 13보다 반드시 앞이어야 한다. 리스너가 한 번만 사는 것이라
(design 결정 7) 체인이 붙는 순간 죽고, 그 뒤에는 `/proc/net/tcp`에서 사라진다.
M0의 실측 1이 세 자리에서 0 · 0 · 1로 갈린 것이 그 증거다.

- [x] Step 1: 리스너를 띄우는 타이핑과 판정을 넣는다

```bash
# ── 검사 12: 게스트가 포트를 열었나 ───────────────────────────────────
# IN-M1이 더한 검사 둘 중 앞의 것이다. 이 검사가 있어야 아래 검사 13이
# 실패했을 때 원인이 "게스트가 안 들었다"인지 "길이 안 섰다"인지 갈린다.
# 없으면 둘이 같은 빨간불이고, 그 둘은 고치는 자리가 완전히 다르다.
#
# 한 번 응답하고 끝나는 리스너다(design 결정 7). echo가 만든 한 줄을 nc가
# 연결에 흘려 넣고 닫는다. 연결 하나를 받고 끝나므로 체인이 정리할 프로세스가
# 안 남는다 — 위 guestfwd가 "듣는 프로세스가 없다"로 얻은 성질을 게스트
# 쪽에서 얻는 방법이 이것이다.
#
# 배경(&)에 두는 것이 M0의 실측 2다. fish에서 프롬프트가 그대로 돌아오고,
# 리스너가 사는 동안 화면에 한 글자도 안 찍는다.
#
# 판정을 /proc/net/tcp로 하는 이유는 그것이 커널이 직접 만드는 것이라
# 게스트에 도구가 하나도 필요 없기 때문이다. 검사 2가 /sys/class/net에
# 기댄 것과 같은 근거다. 포트가 16진수로 적혀서 8080이 1F90이다.
#
# 왜 grep -c를 그냥 치지 않는가. 친 명령의 에코가 화면이므로(결정 E,
# NW-M3 실측 2) 1F90을 그대로 치면 연결이 하나도 안 돼도 그 글자가 화면에
# 있다. 그래서 출력에만 생기는 글자로 판정한다 — 명령 치환의 결과가 붙는
# inm1-listen=N이다. 검사 10의 dhcpcd-alive=N과 같은 모양이고 치환 문법도
# 같다($(가 shift-4 shift-9, )가 shift-0).
#
# 이 두 타이핑 사이의 시간이 design 위험 1을 통째로 없앤다. bind는 명령이
# 실행된 뒤 4~104밀리초에 끝나는데(M0 실측 5) 아래 타이핑이 45키가 넘어서
# 초 단위로 걸린다. 즉 검사 13이 붙을 때 리스너는 이미 오래 서 있다.
echo "=== typing the one-shot listener on port ${GUEST_LISTEN_PORT} ==="
type_keys e c h o spc i n m 1 minus i n b o u n d minus o k spc \
  shift-backslash spc n c spc minus l spc minus p spc 8 0 8 0 spc shift-7 ret

echo "=== typing 'echo inm1-listen=\$(grep -c 1F90 /proc/net/tcp)' ==="
type_keys e c h o spc i n m 1 minus l i s t e n equal \
  shift-4 shift-9 g r e p spc minus c spc 1 shift-f 9 0 spc \
  slash p r o c slash n e t slash t c p shift-0 ret

if ! wait_for_screen "inm1-listen=[1-9]"; then
  fail "the guest never put port ${GUEST_LISTEN_PORT} into LISTEN" \
    "terminal: screen>"
fi
echo "the guest is listening on port ${GUEST_LISTEN_PORT}"
```

키 이름 둘이 이 저장소에서 처음 쓰인다 — `shift-backslash`(`|`)와
`shift-7`(`&`). 둘 다 우리 키맵에 자리가 있다(`terminal/src/input.zig`의
`qwerty_keymap` 43번 칸이 `{ '\\', '|' }`, 8번 칸이 `{ '7', '&' }`). QEMU의
`sendkey`가 그 이름으로 그 evdev 코드를 보내는지는 Task 4의 실행이 답한다.
틀리면 증상이 크다 — 화면에 엉뚱한 글자가 찍히고 명령이 통째로 안 돈다.

- [x] Step 2: 더한 줄만 들어갔는지 본다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 Task 1에서 본 그 한 줄뿐이다. 이 Task는 지우는 것이 없다.

## Task 3 — 검사 13: 체인이 붙어 바이트를 읽는다

검사 12 바로 뒤, `# ── 끈다 ──` 앞에 넣는다.

- [x] Step 1: 붙어서 한 줄을 읽는 루프를 넣는다

```bash
# ── 검사 13: 바깥에서 붙어 게스트가 보낸 바이트를 읽나 ────────────────
# 이 체인이 처음으로 화면도 커널 로그도 아닌 것으로 판정하는 자리다
# (design 결정 3). 앞의 검사 열둘은 전부 시리얼 로그의 글자를 보는데,
# 이 검사가 보는 것은 체인 자신이 소켓에서 받은 바이트다.
#
# 그 차이가 값진 이유가 NW-M3 실측 2다. wait_for_screen은 마지막 프레임이
# 아니라 로그 전체의 screen> 줄을 보므로 우리가 친 명령의 에코도 화면이고,
# 그래서 판정 글자를 고를 때마다 "이 글자가 명령줄에 없나"를 따져야 한다.
# 체인이 읽은 바이트는 애초에 게스트 화면을 안 지나가므로 그 함정이 성립하지
# 않는다.
#
# rc로 판정하지 않는다. M0의 실측 4가 가장 값진 것을 여기서 쟀다 — 게스트에
# 듣는 프로세스가 하나도 없어도 이 connect는 rc=0으로 성공한다. QEMU가 호스트
# 포트를 스스로 listen하고 있어서 붙는 것은 언제나 되고, 게스트 쪽에 받을
# 것이 없으면 그냥 닫기 때문이다. 즉 "붙었다"와 "받았다"가 완전히 다른
# 사실이고, 음성과 양성이 rc에서 같은 값이다.
#
# cat이 아니라 read인 이유가 design 결정 10이다. nc.traditional은 바이트를
# 보낸 뒤에도 연결을 안 닫아서 cat <&5가 EOF를 못 보고 매달린다(M0 실측 5에서
# 10초 timeout을 다 썼다). 게이트는 이 체인을 세 번 도니 그대로 두면 30초다.
# read가 가정하는 것은 "판정 글자가 개행으로 끝나는 한 줄"인데, 그 한 줄을
# 만드는 echo를 바로 위 검사 12가 타이핑하므로 가정의 양쪽 끝이 이 파일 안에
# 있다.
#
# fd가 3이 아니라 5인 이유. 3은 이 체인이 QEMU monitor에 쓰고 있고 아래
# system_powerdown이 아직 그 fd로 간다.
#
# 재시도 10회 × 0.2초는 넉넉하게 잡은 값이다. M0 실측 5로는 bind가 100밀리초
# 안에 끝나고, 게다가 검사 12의 타이핑이 그 사이에 통째로 들어가 있다.
# 첫 회에 닿는 것이 정상이고 루프는 보험이다.
INBOUND_CONNECTED=0
INBOUND_OK=0
INBOUND_GOT=""
for _ in $(seq 1 10); do
  if exec 5<>"/dev/tcp/127.0.0.1/${INBOUND_PORT}"; then
    INBOUND_CONNECTED=1
    INBOUND_GOT=""
    read -r -t 5 INBOUND_GOT <&5 || true
    exec 5<&-
    exec 5>&-
    case "$INBOUND_GOT" in
      *inm1-inbound-ok*) INBOUND_OK=1; break ;;
    esac
  fi
  sleep 0.2
done

# 실패를 둘로 가른다. 앞은 QEMU가 그 포트를 아예 안 열었다는 뜻이고(hostfwd
# 줄이 없거나 QEMU가 그것을 안 받았다), 뒤는 열렸는데 게스트 쪽에서 아무것도
# 안 왔다는 뜻이다. M0 실측 6이 그 둘이 bash에서 완전히 다르게 보인다고 쟀다 —
# 빈 로컬 포트는 즉시 Connection refused이고, hostfwd 포트는 게스트에 아무도
# 없어도 붙는다.
if [ "$INBOUND_CONNECTED" = "0" ]; then
  fail "nothing accepted on 127.0.0.1:${INBOUND_PORT} — QEMU never opened the hostfwd port" \
    "terminal: screen>"
fi
[ "$INBOUND_OK" = "1" ] || \
  fail "the hostfwd port accepted us but the guest sent nothing we know (got: [${INBOUND_GOT}])" \
    "terminal: screen>"
echo "the chain read inm1-inbound-ok off the guest's listener"
```

- [x] Step 2: 검사 12의 주석에 fish의 job 줄을 적는다

M0 실측 2가 찾은 것이다. 리스너가 응답하고 죽으면 fish가 화면에 이 줄을 찍는다.

```
fish: Job 2, 'echo inm1-inbound-ok | nc -l -…' has ended
```

M1에서는 그 뒤에 화면을 보는 검사가 하나도 없어서 아무것도 안 민다. 다만
IN-M2가 검사 14를 그 뒤에 놓으므로 지금 적어 둔다. 검사 13의 마지막 `echo`
줄 뒤에 붙인다.

```bash
# 여기서 리스너가 죽고, 그때 fish가 `fish: Job N, '...' has ended`를 화면에
# 찍는다(M0 실측 2). M1에는 그 뒤에 화면을 보는 검사가 하나도 없어서 아무것도
# 안 민다 — 검사 14를 이 뒤에 놓는 IN-M2가 그 한 줄을 고려해야 한다.
```

- [x] Step 3: `require_no_early_exit_pipe`에 안 걸리는지 본다

이 Task가 더한 줄에 파이프가 하나도 없지만, 검사 12의 타이핑이 `|`를 문자로
친다. lint가 보는 것은 셸 파이프이므로 `shift-backslash`라는 키 이름은 안
걸린다. 그래도 게이트가 첫 부팅 전에 세우는 검사라 미리 확인한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'grep -n "| *g\(rep\)\?" net/check.sh | grep -v "^ *[0-9]*: *#"'
```

Expected: 한 줄도 안 나온다.

- [x] Step 4: 더한 것과 지운 것을 센다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 여전히 그 한 줄(옛 `-netdev`)뿐이다.

## Task 4 — 체인을 단독으로 돌린다

- [x] Step 1: 로그를 둘 디렉터리를 만든다

호스트에 만든다. 이 Task는 컨테이너에 물리지 않고 `docker run`의 출력을
호스트 쪽으로 흘려받기만 하므로 `-v`가 필요 없다(Step 2는 다르다).

```bash
mkdir -p /tmp/inm1 && ls -ld /tmp/inm1
```

Expected: `drwxr-xr-x` 한 줄.

- [x] Step 2: 돌린다

부팅 하나에 약 25~30초다(M3 때 22.911초였고 타이핑이 약 85키 는다). 빌드
산출물이 낡았으면 커널·initrd 빌드가 앞에 붙는다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } > /tmp/inm1/chain.log 2> /tmp/inm1/chain.time
tail -20 /tmp/inm1/chain.log; cat /tmp/inm1/chain.time
```

Expected: 마지막 줄이 `PASS`이고, 그 앞에 이 둘이 있다.

```
the guest is listening on port 8080
the chain read inm1-inbound-ok off the guest's listener
```

- [x] Step 3: 실패했으면 시리얼 로그를 꺼내 온다

통과하면 `--rm`과 함께 사라지므로, 실패한 회차에서만 필요하다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/inm1:/tmp/inm1 -w /workspace \
  tars-devcontainer bash -c '
  bash net/check.sh > /tmp/inm1/net.log 2>&1; echo "exit=$?"
  for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then cp "$f" /tmp/inm1/serial.log; fi
  done'
```

그 로그를 읽을 때는 ANSI를 먼저 걷어낸다. 그리고 fish의 에코 방식 때문에
`grep -c`의 출력 숫자가 명령 에코와 여러 줄 떨어져 있으므로 앞이 아니라
뒤에서 본다(M0의 갈린 자리 4).

```bash
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/inm1/serial.log > /tmp/inm1/serial.clean
grep -n "inm1-listen" /tmp/inm1/serial.clean
```

실패 모양별로 볼 곳.

- `the guest never put port 8080 into LISTEN` — 타이핑이 깨진 것인지
  리스너가 안 뜬 것인지를 가른다. `serial.clean`에서 우리가 친 두 줄의
  에코를 찾아 `|`와 `&`가 제대로 찍혔는지 본다. 안 찍혔으면 원인이
  `shift-backslash`/`shift-7` 키 이름이다.
- `nothing accepted on 127.0.0.1:45465` — QEMU가 `hostfwd`를 안 받았다.
  이 경우 대개 QEMU 자체가 안 떠서 앞 검사에서 먼저 죽는다. 그런데도 여기까지
  왔다면 옵션 문자열이 쪼개진 것이고, 그때는 `guestfwd`와 나란히 둔 것이
  원인이므로 순서를 바꿔 본다.
- `the hostfwd port accepted us but the guest sent nothing we know` —
  `hostfwd`는 섰는데 게스트 쪽이 비었다. 검사 12가 초록이었으므로 리스너는
  있었다는 뜻이고, 그러면 남은 후보는 `hostfwd`의 게스트 주소(`10.0.2.15`)가
  실제 주소와 다른 것이다. 검사 6의 출력이 그 자리에 있다.

- [x] Step 4: 체인 단독 시간을 적어 둔다

`/tmp/inm1/chain.time`의 `real` 값이다. 이 체인의 역사가 8.954초 → 17.082초
→ 22.911초로 이어져 있고 이 값이 넷째다. design 위험 3이 "예상이 아니라
실제로 잰다"고 적어 둔 자리다.

## Task 5 — 반사실: `hostfwd`를 뺀다

design의 M1 끝 기준 둘 중 뒤의 것이다. 검사 13이 실제로 그 한 줄을 보고
있다는 것을 증명한다 — 증명 없이는 이 검사가 언제나 초록인 장식일 수 있다.

- [x] Step 1: 사본을 만들고 그 한 줄만 되돌린다

저장소 파일은 한 글자도 안 건드린다. `/tmp` 사본을 `-v`로 덮어씌우는 것이
NW가 세 번 쓴 방법이다.

```bash
cp net/check.sh /tmp/inm1/check.sh
sd -s 'hostfwd=tcp:127.0.0.1:${INBOUND_PORT}-10.0.2.15:${GUEST_LISTEN_PORT},' \
      '' /tmp/inm1/check.sh
chmod +x /tmp/inm1/check.sh
grep -n "netdev \"user" /tmp/inm1/check.sh
```

`sd`에 `-s`를 주는 것은 이 문자열을 정규식이 아니라 글자 그대로 찾게 하기
위해서다. 안 주면 `.`이 아무 글자나 되고 `${...}`의 중괄호가 반복 횟수로
읽혀서, 맞기는 맞아도 무엇을 지웠는지 사람이 못 읽는다. 끝의 쉼표까지 함께
지우는 것이 요점이다 — 안 지우면 `-netdev` 값에 빈 항목이 남는다.

Expected: 마지막 `grep`이 찍는 줄에 `hostfwd`가 없고 `guestfwd`만 남아 있다.
없으면 `sd`의 패턴이 안 맞은 것이므로 그 줄을 눈으로 보고 고친다.

`chmod +x`는 실제로는 필요 없다 — 게이트가 이 파일을 `bash net/check.sh`로
부른다. 그래도 붙이는 이유는 NW-M2 실측 22가 `make_disk.sh` 사본에서 그것을
빼먹고 엉뚱한 자리에서 죽은 적이 있어서, 사본을 만들 때 함께 치는 습관을
유지하기 위해서다.

- [x] Step 2: 그 사본으로 체인을 돌린다

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/inm1/check.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh > /tmp/inm1/neg.log 2>&1
echo "exit=$?"
tail -30 /tmp/inm1/neg.log
```

Expected: `exit=1`이고 이 줄이 나온다.

```
FAIL: nothing accepted on 127.0.0.1:45465 — QEMU never opened the hostfwd port
```

그 앞에 `the guest is listening on port 8080`이 있어야 한다. 검사 12는
`hostfwd`와 무관하게 통과하는 것이 맞다 — 게스트가 듣는 것과 바깥에서 길이
있는 것은 다른 사실이고, 이 둘을 나눈 것이 검사를 둘로 쪼갠 이유다.

- [x] Step 3: 만약 검사 12에서 죽으면 그것을 적는다

design의 M1 끝 기준이 그 경우를 미리 열어 두었다. 검사 12에서 죽으면
"게스트가 듣는 것과 QEMU가 길을 내는 것이 서로 엮여 있다"는 뜻이고, 그것도
값진 결과다. 그때는 아래 Task 6의 실측 절에 그 사실을 적고, 검사를 둘로 쪼갠
근거를 다시 쓴다.

`exit=0`이 나오면 그것이 가장 나쁜 결과다 — 검사 13이 `hostfwd` 없이도
초록이라는 뜻이고, 그러면 그 검사가 무엇을 보고 있는지부터 다시 봐야 한다.
후보는 하나다: 45465에 이 체인이 아닌 무언가가 듣고 있다.

- [x] Step 4: 사본을 지운다

```bash
rm -f /tmp/inm1/check.sh
git status --short net/check.sh
```

저장소 파일을 한 번도 안 바꿨으므로 되돌릴 것이 없다. `git status`가 찍는
것은 이 milestone이 의도한 `M net/check.sh` 하나뿐이어야 한다.

## Task 6 — 실측을 design에 적고 커밋한다

- [x] Step 1: design에 `## IN-M1이 실행으로 증명한 것` 절을 더한다

`## IN-M0이 실행으로 증명한 것` 절의 끝(`### M0이 M1에 넘기는 것` 뒤)에
이어서 쓴다. 넣을 것이 다섯이다.

1. 검사 12와 13이 실제로 통과한 값. 화면에 나온 `inm1-listen=N`의 N과,
   체인이 읽은 글자.
2. 반사실이 어디에서 죽었나. 검사 13이면 예상대로이고, 검사 12면 그 사실과
   해석을 적는다.
3. `shift-backslash`와 `shift-7`이 실제로 `|`와 `&`를 만들었나. 이 저장소에서
   처음 쓴 키 이름 둘이다.
4. `hostfwd`와 `guestfwd`가 한 `-netdev` 값에서 함께 도나. Task 1 Step 1이
   추론으로 남겨 둔 자리다.
5. 체인 단독 시간. 8.954 → 17.082 → 22.911에 이어지는 넷째 값이다.

각 실측은 `### 실측 N — <한 줄 결론>` 꼴이고 M0의 번호를 이어서 실측 7부터
쓴다.

- [x] Step 2: design의 M1 절에 끝난 표시를 단다

`### IN-M1 — 게스트가 듣고 체인이 읽는다` 절의 끝에 한 줄을 더한다.

```markdown
⚠ 2026-09-14에 끝났다. 검사 12·13이 섰고 반사실이 검사 13에서 죽었다
(실측 7~11). `net/check.sh`가 검사 열셋이 됐다.
```

반사실이 검사 12에서 죽었으면 그 문장을 사실에 맞게 고친다.

- [x] Step 3: 무엇이 커밋에 들어가는지 먼저 본다

```bash
git status --short
```

Expected: 셋이다.

```
 M docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md
 M net/check.sh
?? docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m1.md
```

`out/net.img`나 빌드 산출물이 보이면 `.gitignore`부터 확인한다 — 컨테이너가
만든 것이라 나와서는 안 된다. 이 저장소는 kernel/init/bootloader를 직접
빌드하므로 이 확인을 매번 한다(CLAUDE.md).

- [x] Step 4: 커밋한다

```bash
git add docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md \
        docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m1.md \
        net/check.sh
git commit -m "Open a port in the guest and read it from outside"
```

- [x] Step 5: 이 문서 끝에 갈린 자리를 적는다

M0이 넷을 적었고 그것이 이 세션에 값졌다. 갈린 것이 없으면 "갈린 자리가
없다"고 한 줄 적는다.

## 끝 기준

넷이다.

1. `net/check.sh`가 단독으로 `PASS`하고, 검사 12와 13의 초록 줄 둘이 로그에
   있다.
2. `hostfwd` 줄만 뺀 반사실이 검사 13에서 죽는다(또는 검사 12에서 죽고 그
   사실이 적혀 있다).
3. design에 실측 절이 생기고 M1 절에 끝난 표시가 있다.
4. 저장소에서 바뀐 코드 파일이 `net/check.sh` 하나다. 커널도
   `guest_tools.sh`도 `init/`도 한 글자도 안 바뀐다.

루트 게이트는 안 돌린다. IN-M2가 검사 14·15를 더한 뒤에 한 번 돌리는 것이
design의 계획이고, 그 사이에 두 번 돌리면 31분을 아무 새 정보 없이 쓴다.

## IN-M2가 이 자리에서 이어받을 것

- 포트 45466과 게스트 8081. `hostfwd` 둘째 줄을 같은 `-netdev` 값에 쉼표로
  이어 붙인다(M0 실측 6이 그 형식이 먹는 것을 확인했다).
- 검사 14의 모양은 M0의 실측 3b가 이미 정했다. 둘째 리스너를
  `nc -l -p 8081 > /tmp/<파일> &`로 띄우고, 체인이 `inm2-reverse-ok`를 보내고
  바로 닫은 뒤, 게스트에서 그 파일을 `cat`해서 화면으로 판정한다.
- 검사 15(음성)는 기다릴 필요가 없다. 결정 10 덕분에 `read`가 즉시 EOF를
  보고 빈 값으로 돌아온다. 판정은 `INBOUND_GOT`이 비어 있는 것이다.
- 검사 14를 검사 13 뒤에 놓으면 그 사이에 fish의 job 종료 줄이 하나 낀다
  (M0 실측 2). `wait_for_screen`의 패턴이 그 줄과 안 부딪치는지 본다.
  ⚠ M1에서는 그 줄이 한 번도 안 나왔다(실측 12). 사라진 것이 아니라 미뤄진
  것이다 — fish가 job 종료를 다음 프롬프트에서 보고하는데 검사 13 뒤에
  타이핑이 없었기 때문이고, 검사 14의 타이핑이 바로 그 프롬프트를 만든다.

## 실제로 돌린 것이 이 plan과 갈린 자리

셋이다. 전부 작고, plan을 고쳐야 할 만큼 틀린 자리는 없었다.

1. Task 4가 부팅 하나가 아니라 둘이었다. 첫 회가 통과하면 시리얼 로그가
   `--rm`과 함께 사라지는데, 실측으로 적을 값(`inm1-listen=`의 실제 숫자와
   `|`·`&`의 에코)이 그 로그에만 있다. plan의 Step 3이 그 추출을 "실패했으면"
   으로 적어 두었는데, 통과한 회차에서도 필요했다. 다음에 새 화면 판정을
   넣는 사람은 그 추출을 실패 대비가 아니라 기본 절차로 둔다.

2. Task 4 Step 3의 로그 읽기 한 줄이 잘못을 하나 만들었다.
   `tr '|' '\n'`으로 화면 행을 복원했는데, 시리얼 로그가 행을 ` | `로 이어
   붙이므로 명령줄 안의 `|` 문자도 함께 쪼개져서 리스너 명령이 두 줄로
   보였다. 잠깐 "파이프가 안 들어갔나"로 읽힌다. 실측 9가 그 자리다.

3. Task 5의 `sd` 패턴이 한 번에 맞았다. `-s`로 글자 그대로 찾은 것이
   주효했고, 사본의 `-netdev` 줄이 M1 이전의 모양과 바이트까지 같았다.
   plan이 미리 적어 둔 확인(`grep -n 'netdev "user'`)이 그것을 한눈에 보여
   줬다.
