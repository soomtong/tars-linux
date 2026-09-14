# IN-M2 — 반대 방향과 음성

design: `docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md`

Goal: `net/check.sh`에 `hostfwd` 둘째 줄과 검사 셋을 더해서, 받는 길이 양쪽
방향으로 서는 것과 "안 섰을 때 게이트가 그것을 빨간불로 읽는다"는 것을 매번
확인하게 만든다. 그리고 루트 게이트를 한 판 돌려 열두 체인이 3/3인 것과 시간
증가분을 잰다. 이것이 IN의 마지막 milestone이다.

Architecture: M1과 같다. 우리 코드는 0줄이다 — 듣는 것은 게스트의 `nc`이고
보내는 것은 체인 자신의 bash `/dev/tcp`이며 잇는 것은 QEMU SLIRP의 `hostfwd`
다. 바뀌는 코드 파일은 `net/check.sh` 하나다.

Tech Stack: QEMU SLIRP `hostfwd`, bash의 `/dev/tcp`와 `read -r -t`, 게스트의
`nc.traditional`과 fish의 `>` 리다이렉션, 커널이 직접 만드는 `/proc/net/tcp`.

---

## M1이 이 plan에 넘긴 것

M1 plan 끝의 "IN-M2가 이 자리에서 이어받을 것" 넷과 실측 12다. 여기서 실제로
쓰는 자리를 함께 적는다.

| M1이 넘긴 것 | 이 plan의 어디에 쓰이나 |
|---|---|
| 포트 45466과 게스트 8081(M0 실측 6) | Task 1의 `REVERSE_PORT`·`GUEST_REVERSE_PORT` |
| `hostfwd` 둘을 한 값에 쉼표로 이어 붙일 수 있다(실측 10) | Task 1 |
| 검사 14의 모양은 M0 실측 3b가 정했다 | Task 3의 `nc -l -p 8081 > <파일> &` |
| 음성은 기다릴 필요가 없다(결정 10) | Task 4의 `read -r -t 2` |
| fish의 job 종료 줄이 미뤄져 있다(실측 12) | Task 2 Step 1의 주의와 Task 5 Step 3 |
| 판정은 바이트 수로 한다. `rc`는 음성과 양성이 같다(실측 4) | Task 4의 `[ -z "$NEG_GOT" ]` |
| `bind`는 4~104밀리초에 끝난다(실측 5) | Task 0이 이 값을 근거로 검사를 셋으로 가른다 |
| 통과한 회차의 시리얼 로그도 꺼내 온다(M1의 갈린 자리 1) | Task 5 Step 3이 기본 절차다 |

## Task 0 — 검사를 셋으로 가르고 그 근거를 design에 적는다

design의 M2 절이 검사 둘(14=반대 방향, 15=음성)을 그려 두었다. 이 plan은
셋으로 간다 — 14(게스트가 8081을 열었나) · 15(체인이 보낸 것을 게스트가
받았나) · 16(듣는 것이 없을 때 체인이 그것을 실패로 읽나).

가르는 이유는 M1에 없던 경주가 반대 방향에 하나 있기 때문이다. M1에서는
리스너를 띄우는 타이핑과 체인이 붙는 자리 사이에 검사 12의 타이핑 48키가
통째로 들어가 있어서 `bind`가 끝날 시간이 남아돌았다(실측 7이 "재시도 루프는
한 번도 안 돌았다"고 적은 자리다). 반대 방향에는 그 사이가 없다 — 리스너를
띄우고 곧바로 체인이 보낸다. `bind`가 4~104밀리초 걸리는데(M0 실측 5)
`type_keys`는 마지막 키의 로그가 자란 것만 보고 돌아오므로, 체인이 먼저
보낼 수 있다.

그리고 그 실패가 조용하다. 듣는 것이 없어도 QEMU가 붙여 주고 우리가 쓴
바이트를 그냥 버린다(M0 실측 4). 즉 보내는 쪽에서는 성공과 실패가 구별되지
않고, 게스트 쪽 파일이 빌 뿐이다.

그래서 M1이 실제로 검증한 모양을 그대로 다시 쓴다. 앞의 검사가 LISTEN을
화면으로 확인하고, 그 타이핑 자체가 `bind`의 시간을 만들고, 뒤의 검사가
전달을 본다. 실패했을 때 "게스트가 안 들었다"와 "길이 안 섰다"가 갈리는
것도 M1과 같은 이유로 따라온다.

안 고른 대안 하나를 적어 둔다. 타이핑을 안 늘리고 체인이 같은 줄을 여러 번
보내는 길이 있다(버려지는 연결은 값이 0이므로 해롭지 않다). 그 길을 안
가는 이유는 두 가지다 — 새 모양이라 이 저장소가 한 번도 안 재 봤고,
"몇 번째 시도에서 닿았나"가 로그에 안 남아서 경주가 실제로 있는지를 다음
사람이 다시 못 잰다. M1의 재시도 루프가 "첫 회에 닿았다"를 남긴 것과
반대다.

치르는 값은 타이핑 약 47키(약 2.1초)이고, 게이트가 이 체인을 세 번 도니 약
6.3초다. 게이트 잡음이 ±3분이다.

- [x] Step 1: design의 M2 절을 셋으로 고친다

`### IN-M2 — 반대 방향과 음성` 절의 검사 목록 둘을 아래 셋으로 바꾼다.

```markdown
- 검사 14 — 게스트가 둘째 포트를 열었나. 반대 방향의 리스너를 띄우고
  `/proc/net/tcp`로 `LISTEN`을 화면에서 확인한다. 이 검사가 M1의 검사 12와
  같은 자리이고 같은 일을 둘 한다 — 실패를 갈라 주는 것과, 그 타이핑 자체가
  `bind`가 끝날 시간을 만드는 것. 뒤의 것이 M2에서 더 중요하다(M1에는
  검사 12의 타이핑이 그 사이를 메웠는데 반대 방향에는 그 여유가 없다).
- 검사 15 — 체인이 보낸 `inm2-reverse-ok`를 게스트가 받았나. 게스트 쪽에서
  그것을 파일로 받아 화면으로 확인한다.
- 검사 16 — 듣는 프로세스가 없을 때 체인이 그것을 실패로 읽나. 판정 모양은
  M0의 측정 4가 정한다.
```

그리고 그 절의 끝 기준 문장을 고친다.

```markdown
끝 기준은 검사 다섯(12~16)이 통과하는 것, 반사실 둘이 각각 겨냥한 자리에서
죽는 것, 그리고 게이트가 3/3인 것이다.
```

- [x] Step 2: 결정 11을 더한다

`### 결정 10 — 읽기의 종료 조건은 체인 쪽 read -r -t다 (M1이 골랐다)` 절 바로
뒤, `## 비목표` 절 앞에 넣는다.

```markdown
### 결정 11 — 반대 방향도 LISTEN 확인을 앞에 둔다 (M2가 골랐다)

design이 M2를 검사 둘로 그렸는데 M2가 셋으로 갈랐다. 반대 방향의 리스너를
띄우는 타이핑과 체인이 보내는 자리 사이에, M1이 가졌던 여유가 없기
때문이다 — M1에서는 검사 12의 타이핑 48키가 그 사이를 통째로 메워서
재시도 루프가 한 번도 안 돌았다(실측 7).

그 여유가 없으면 경주가 선다. `bind`가 4~104밀리초 걸리는데(실측 5)
`type_keys`는 마지막 키의 로그가 자란 것만 보고 돌아온다. 그리고 그 실패가
조용하다 — 듣는 것이 없어도 QEMU가 붙여 주고 바이트를 버린다(실측 4).
보내는 쪽에서는 성공과 실패가 같은 모양이고, 게스트의 파일이 빌 뿐이다.

그래서 M1이 실제로 검증한 모양을 그대로 다시 쓴다. 검사 14가 LISTEN을
화면으로 확인하고, 그 타이핑이 bind의 시간을 만들고, 검사 15가 전달을
본다. 치르는 값이 타이핑 약 47키(약 2.1초 × 3회)다.

안 고른 대안은 체인이 같은 줄을 여러 번 보내는 것이었다. 버려지는 연결은
값이 0이라 해롭지 않지만, 이 저장소가 한 번도 안 재 본 모양이고 "몇 번째
시도에서 닿았나"가 로그에 안 남는다.
```

- [x] Step 3: 고쳐진 자리를 확인한다

```bash
grep -n "결정 11\|검사 16 —\|검사 다섯" \
  docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md
```

Expected: 줄 셋. 결정 절의 제목 하나, M2 절의 검사 16 항목 하나, 끝 기준
하나.

## Task 1 — QEMU 줄에 `hostfwd` 하나 더

- [x] Step 1: 포트 상수 둘을 더한다

`net/check.sh:100`의 `GUEST_LISTEN_PORT=8080` 바로 아래에 넣는다.

```bash
# IN-M2. 반대 방향(체인 → 게스트)의 입구다. 45466은 M0의 실측 6이 45465와
# 함께 비어 있는 것을 확인한 번호이고, 게스트 쪽 8081은 M0의 실측 3b가 실제로
# 써 본 포트다.
#
# 방향을 포트로 가르는 이유는 리스너가 한 번만 살기 때문이다(design 결정 7).
# 8080의 리스너는 검사 13이 읽는 순간 죽으므로 같은 포트를 다시 쓰려면
# 리스너를 또 띄워야 하는데, 그러면 두 방향의 실패가 같은 포트에서 겹쳐
# 보인다. 포트가 다르면 /proc/net/tcp의 숫자만으로도 어느 방향인지 갈린다.
REVERSE_PORT=45466
GUEST_REVERSE_PORT=8081
```

- [x] Step 2: `-netdev` 값에 둘째 `hostfwd`를 이어 붙인다

`net/check.sh:183`의 이 줄을

```bash
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${INBOUND_PORT}-10.0.2.15:${GUEST_LISTEN_PORT},guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
```

이것으로 바꾼다.

```bash
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${INBOUND_PORT}-10.0.2.15:${GUEST_LISTEN_PORT},hostfwd=tcp:127.0.0.1:${REVERSE_PORT}-10.0.2.15:${GUEST_REVERSE_PORT},guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
```

`hostfwd` 둘을 한 값에 쉼표로 이어 붙이는 것이 이 QEMU에서 그대로 먹는다 —
M0의 하네스가 정확히 이 형식으로 돌았고(실측 6), M1이 `hostfwd`와 `guestfwd`가
한 값에서 함께 사는 것까지 확인했다(실측 10). `cmd:` 값을 끝에 두는 규칙은
M1이 정한 그대로다.

- [x] Step 3: 그 줄 위의 주석에 한 문장을 더한다

`# IN-M1이 그 -netdev 값에 hostfwd를 하나 더했다.`로 시작하는 문단 끝에
붙인다.

```bash
# IN-M2가 그 옆에 둘째 hostfwd를 놓았다. 앞의 것이 게스트 → 체인 방향의
# 입구이고 뒤의 것이 체인 → 게스트 방향의 입구다. TCP는 한 연결로 양방향을
# 다 쓸 수 있지만 여기서는 포트를 나눴다 — 리스너가 한 번만 사는 것이라
# (결정 7) 방향마다 리스너가 따로 필요하고, 포트가 다르면 /proc/net/tcp의
# 숫자만으로 어느 방향이 안 섰는지가 갈린다.
```

- [x] Step 4: 지운 줄이 의도한 줄 하나뿐인지 본다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 딱 하나이고 그것이 옛 `-netdev` 줄이다. CLAUDE.md 진행
방식 2번이라 매 편집 뒤에 본다.

## Task 2 — 검사 14: 게스트가 둘째 포트를 열었나

검사 13의 마지막 주석(`# 여기서 리스너가 죽고 …`) 뒤, `# ── 끈다 ──` 앞에
넣는다. 아래 Task 3·4도 같은 자리에 차례로 쌓인다.

- [x] Step 1: 리스너를 띄우는 타이핑과 판정을 넣는다

```bash
# ── 검사 14: 게스트가 둘째 포트를 열었나 ──────────────────────────────
# 반대 방향(체인 → 게스트)의 준비다. 검사 12와 같은 모양이고 같은 일을 둘
# 한다 — 실패를 갈라 주는 것과, 이 타이핑 자체가 bind가 끝날 시간을 만드는
# 것. 뒤의 것이 여기서는 더 중요하다(design 결정 11). 검사 13에서는 검사 12의
# 타이핑 48키가 리스너와 체인 사이를 메웠는데, 반대 방향에는 그 여유가 없다.
#
# 리스너의 모양이 M0의 실측 3b가 실제로 돌린 것이다. 받는 것을 화면이 아니라
# 파일로 떨어뜨린다 — 체인이 보낸 글자가 게스트 화면에 곧바로 나오면 그것이
# 검사 15의 판정 글자가 되는데, 그러면 "받았다"와 "nc가 무언가를 찍었다"가
# 안 갈린다. 파일로 받고 사람이 cat으로 꺼내면 그 글자가 확실히 게스트를
# 한 번 지나온 것이 된다.
#
# fish에서 > 는 shift-dot이다(config/check.sh:68의 주석이 같은 자리를 적고
# 있다). & 는 shift-7이고 M1의 실측 9가 그 키 이름이 실제로 도는 것을 봤다.
#
# 8081이 /proc/net/tcp에 1F91로 적힌다. 검사 12의 1F90과 한 글자 차이라
# 눈으로는 헷갈리지만 게이트는 안 헷갈린다 — 두 리스너가 동시에 살아 있는
# 구간이 없기 때문이다(8080의 것은 검사 13이 읽는 순간 죽는다).
#
# 왜 grep -c를 그냥 치지 않는가는 검사 12와 같다. 친 명령의 에코가 화면이므로
# (결정 E) 출력에만 생기는 글자로 판정한다 — inm2-listen=N이다.
echo "=== typing the reverse listener on port ${GUEST_REVERSE_PORT} ==="
type_keys n c spc minus l spc minus p spc 8 0 8 1 spc shift-dot spc \
  slash t m p slash i n m 2 dot t x t spc shift-7 ret

echo "=== typing 'echo inm2-listen=\$(grep -c 1F91 /proc/net/tcp)' ==="
type_keys e c h o spc i n m 2 minus l i s t e n equal \
  shift-4 shift-9 g r e p spc minus c spc 1 shift-f 9 1 spc \
  slash p r o c slash n e t slash t c p shift-0 ret

if ! wait_for_screen "inm2-listen=[1-9]"; then
  fail "the guest never put port ${GUEST_REVERSE_PORT} into LISTEN" \
    "terminal: screen>"
fi
echo "the guest is listening on port ${GUEST_REVERSE_PORT}"
```

이 자리에서 화면에 한 줄이 더 나온다. 검사 13이 읽으면서 8080의 리스너가
죽었는데 fish는 job 종료를 다음 프롬프트에서 보고하므로(M1 실측 12), 위
첫 타이핑이 그 프롬프트를 만들면서 이런 줄이 찍힌다.

```
fish: Job 2, 'echo inm1-inbound-ok | nc -l -…' has ended
```

그 줄에 `inm2-listen=`도 `inm2-reverse-ok`도 없으므로 아래 두 검사의 패턴과
안 부딪친다. `wait_for_screen`이 마지막 프레임이 아니라 로그 전체를 보므로
화면 좌표가 밀리는 것도 문제가 안 된다.

- [x] Step 2: 더한 줄만 들어갔는지 본다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 Task 1에서 본 그 한 줄뿐이다.

## Task 3 — 검사 15: 체인이 보낸 것을 게스트가 받나

- [x] Step 1: 보내고 닫고, 게스트에서 꺼내 본다

```bash
# ── 검사 15: 체인이 보낸 바이트를 게스트가 받나 ───────────────────────
# 받는 길의 반대쪽이다. TCP는 양방향이고 두 방향이 커널에서 다른 버퍼를
# 지난다 — 한 방향만 보고 "길이 섰다"고 말하면 그 말이 실제보다 넓다
# (design 결정 5).
#
# 이 방향만은 화면으로 판정한다(design 결정 3의 단서). 게스트가 받은 것을
# 체인에게 알릴 통로가 화면뿐이기 때문이다. 다만 판정 글자를 우리가 게스트에
# 타이핑하지 않으므로 에코 함정에 안 걸린다 — inm2-reverse-ok는 이 파일이
# 소켓으로 흘려 넣는 글자이고, 게스트 명령줄에는 파일 이름만 나온다.
#
# 보내고 바로 닫는다. 게스트의 nc는 EOF를 봐야 끝나고(M0 실측 3b), 끝나야
# 파일이 확실히 다 써진다. 닫는 것이 늦으면 아래 cat이 빈 파일을 볼 수 있다.
#
# fd가 6인 이유. 3은 monitor이고 5는 검사 13이 썼다(닫혔지만 검사 16이 다시
# 쓴다). 방향마다 번호를 나눠 두면 로그에서 어느 줄이 어느 방향인지 보인다.
#
# 재시도가 없다. 검사 14가 LISTEN을 이미 확인했으므로 여기서 못 닿으면 그것은
# 타이밍이 아니라 길의 문제다. 재시도를 두면 그 구별이 흐려진다.
REVERSE_SENT=0
if exec 6<>"/dev/tcp/127.0.0.1/${REVERSE_PORT}"; then
  printf 'inm2-reverse-ok\n' >&6 && REVERSE_SENT=1
  exec 6<&-
  exec 6>&-
fi

# 실패를 둘로 가른다. 검사 13과 같은 갈래다 — 빈 로컬 포트는 즉시
# Connection refused이고(M0 실측 6) hostfwd 포트는 게스트에 아무도 없어도
# 붙는다(실측 4). 그래서 앞의 것이 "QEMU가 이 입구를 안 열었다"이고 뒤의
# 화면 판정이 "열렸는데 게스트까지 안 닿았다"이다.
[ "$REVERSE_SENT" = "1" ] || \
  fail "nothing accepted on 127.0.0.1:${REVERSE_PORT} — QEMU never opened the second hostfwd port" \
    "terminal: screen>"

echo "=== typing 'cat /tmp/inm2.txt' ==="
type_keys c a t spc slash t m p slash i n m 2 dot t x t ret

if ! wait_for_screen "inm2-reverse-ok"; then
  fail "the guest never received what the chain sent" "terminal: screen>"
fi
echo "the guest received inm2-reverse-ok from the chain"
```

`cat`이 리스너보다 빠를 가능성은 낮다. 체인이 닫은 뒤 그 타이핑이 18키라
수백 밀리초가 걸리고, 게스트의 `nc`는 바이트를 받는 즉시 파일에 쓴다(EOF를
기다리는 것은 종료이지 쓰기가 아니다). 그래도 이 자리에서 빈 화면이 나오면
가장 먼저 의심할 것이 그 순서다 — Task 5 Step 3의 시리얼 로그에서 `cat`의
출력 자리를 본다.

- [x] Step 2: 더한 줄만 들어갔는지 본다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 여전히 그 한 줄뿐이다.

## Task 4 — 검사 16: 듣는 것이 없을 때

design 결정 5의 셋째 근거가 이 자리다. 음성이 없으면 "연결이 됐다"와 "체인이
아무것도 안 했다"가 안 갈린다.

- [x] Step 1: 음성 검사를 넣는다

```bash
# ── 검사 16: 듣는 것이 없으면 체인이 그것을 읽어 내나 ─────────────────
# 앞의 검사 넷이 전부 초록인 장식이 아니라는 것을 증명하는 자리다. 여기서
# 붙는 포트가 검사 13과 같은 45465인 이유가 그것이다 — 같은 길, 같은 fd,
# 같은 read인데 게스트 쪽 리스너만 없다. 즉 이것은 검사 13의 음성 대조군이다.
#
# 게스트에 아무것도 안 친다. 8080의 리스너는 한 번만 사는 것이라(결정 7)
# 검사 13이 읽는 순간 이미 죽었고, M0의 실측 1이 그 뒤 /proc/net/tcp의
# 1F90이 0으로 돌아가는 것을 봤다. 그래서 음성을 만들기 위해 할 일이 없다.
#
# 기다리지 않는다(design 결정 10). 듣는 것이 없으면 QEMU가 붙여 주고 곧바로
# 닫으므로 read가 즉시 EOF를 보고 빈 값으로 돌아온다 — M0의 실측 4가 잰
# 값이 3~38밀리초다. -t 2는 그 예상이 틀린 날 게이트가 여기서 매달리지
# 않게 하는 상한이고, 이 값이 실제로 쓰이면 그 자체가 새 사실이다.
#
# 붙는 것에 성공했는지를 따로 본다. 이것이 이 검사에서 가장 중요한 줄이다 —
# 안 보면 hostfwd가 통째로 사라진 날에도 이 검사가 초록이 된다(못 붙어서
# 아무것도 못 읽은 것과 붙었는데 안 온 것이 같은 모양이 되기 때문이다).
# 음성 검사가 거짓 초록이 되는 길은 대개 이렇게 생겼다.
#
# rc는 안 본다. M0의 실측 4가 음성과 양성이 rc에서 같은 값이라고 쟀다.
echo "=== connecting with nothing listening on port ${GUEST_LISTEN_PORT} ==="
NEG_CONNECTED=0
NEG_GOT=""
if exec 5<>"/dev/tcp/127.0.0.1/${INBOUND_PORT}"; then
  NEG_CONNECTED=1
  read -r -t 2 NEG_GOT <&5 || true
  exec 5<&-
  exec 5>&-
fi

[ "$NEG_CONNECTED" = "1" ] || \
  fail "the negative check could not even connect — the hostfwd port is gone" \
    "terminal: screen>"
[ -z "$NEG_GOT" ] || \
  fail "something answered on 127.0.0.1:${INBOUND_PORT} where nothing should be listening (got: [${NEG_GOT}])" \
    "terminal: screen>"
echo "with no listener the chain read nothing, as it should"
```

- [x] Step 2: lint에 안 걸리는지 미리 본다

게이트가 첫 부팅 전에 세우는 검사다(GA-M1의 `require_no_early_exit_pipe`).
이 Task들이 더한 줄에 파이프가 하나도 없지만 확인은 매번 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'grep -n "| *\(g\|r\)\(rep\|g\)" net/check.sh | grep -v "^ *[0-9]*: *#"'
```

Expected: 한 줄도 안 나온다.

- [x] Step 3: 더한 것과 지운 것을 센다

```bash
git diff --stat net/check.sh && git diff net/check.sh | grep '^-'
```

Expected: `-` 줄이 여전히 옛 `-netdev` 한 줄뿐이다.

## Task 5 — 체인을 단독으로 돌린다

- [x] Step 1: 로그를 둘 디렉터리를 만든다

```bash
mkdir -p /tmp/inm2 && ls -ld /tmp/inm2
```

Expected: `drwxr-xr-x` 한 줄.

- [x] Step 2: 돌린다

부팅 하나에 약 32초다(M1이 27.955초였고 타이핑이 약 97키 는다). 빌드
산출물이 낡았으면 커널·initrd 빌드가 앞에 붙는다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } > /tmp/inm2/chain.log 2> /tmp/inm2/chain.time
tail -20 /tmp/inm2/chain.log; cat /tmp/inm2/chain.time
```

Expected: 마지막 줄이 `PASS`이고 그 앞에 이 셋이 있다.

```
the guest is listening on port 8081
the guest received inm2-reverse-ok from the chain
with no listener the chain read nothing, as it should
```

- [x] Step 3: 통과했어도 시리얼 로그를 꺼내 온다

M1의 갈린 자리 1이다. 통과하면 `--rm`과 함께 사라지는데, 실측으로 적을
값(`inm2-listen=`의 실제 숫자 · `>`와 `&`의 에코 · fish의 job 종료 줄이
실제로 나왔는지)이 그 로그에만 있다. 실패 대비가 아니라 기본 절차다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/inm2:/tmp/inm2 -w /workspace \
  tars-devcontainer bash -c '
  bash net/check.sh > /tmp/inm2/net.log 2>&1; echo "exit=$?"
  for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then cp "$f" /tmp/inm2/serial.log; fi
  done'

perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/inm2/serial.log > /tmp/inm2/serial.clean
grep -n "inm2-listen\|inm2-reverse-ok\|has ended" /tmp/inm2/serial.clean
```

⚠ 마지막 화면을 행으로 복원할 때 `tr '|' '\n'`을 쓰면 명령줄 안의 `|`도
함께 쪼개진다(M1 실측 9). 검사 12의 리스너 명령이 그 문자를 쓰므로 이
체인에서는 늘 그렇게 보인다.

실패 모양별로 볼 곳.

- `the guest never put port 8081 into LISTEN` — 타이핑이 깨진 것인지
  리스너가 안 뜬 것인지를 가른다. `serial.clean`에서 그 명령의 에코를 찾아
  `>`와 `&`가 제대로 찍혔는지 본다. 안 찍혔으면 원인이 `shift-dot`/`shift-7`
  이 아니라 그 앞의 `8 0 8 1`일 가능성이 더 크다 — 키 이름 둘은 이미
  검증돼 있다(config 체인이 `shift-dot`을, M1 실측 9가 `shift-7`을 썼다).
- `nothing accepted on 127.0.0.1:45466` — QEMU가 둘째 `hostfwd`를 안 받았다.
  옵션 문자열이 쪼개졌는지를 본다. 검사 13이 초록이었다면 첫째는 살아 있는
  것이므로 원인이 쉼표 이어 붙이기에 있다.
- `the guest never received what the chain sent` — 길은 섰는데 게스트까지
  안 닿았다. `serial.clean`에서 `cat /tmp/inm2.txt`의 출력 자리를 본다.
  아무것도 안 나왔으면 파일이 빈 것이고, `No such file` 류가 나왔으면
  리스너의 리다이렉션이 안 걸린 것이다(그러면 검사 14가 초록이었던 것이
  이상하므로 그 자리부터 다시 본다).
- `something answered … where nothing should be listening` — 가장 값진
  실패다. 45465에 이 체인이 아닌 무언가가 듣고 있거나, 8080의 리스너가
  한 번으로 안 끝났다는 뜻이다. `grep -c 1F90`을 검사 16 앞에서 한 번 더
  치는 검사를 넣어 갈라야 한다(다만 TIME_WAIT가 그 숫자에 섞일 수 있다 —
  아래 Task 8 Step 1의 실측에 그 사실을 함께 적는다).

- [x] Step 4: 체인 단독 시간을 적어 둔다

`/tmp/inm2/chain.time`의 `real` 값이다. 이 체인의 역사가 8.954 → 17.082 →
22.911 → 27.955로 이어져 있고 이 값이 다섯째다.

## Task 6 — 반사실 둘

design의 M2 끝 기준 둘째다. 새 검사가 무언가를 실제로 보고 있다는 것을
증명한다 — 증명 없이는 언제나 초록인 장식일 수 있다.

- [x] Step 1: 반사실 1 — 둘째 `hostfwd`만 뺀다

```bash
cp net/check.sh /tmp/inm2/check.sh
sd -s 'hostfwd=tcp:127.0.0.1:${REVERSE_PORT}-10.0.2.15:${GUEST_REVERSE_PORT},' \
      '' /tmp/inm2/check.sh
chmod +x /tmp/inm2/check.sh
grep -n "netdev \"user" /tmp/inm2/check.sh
```

`sd`에 `-s`를 주는 것은 글자 그대로 찾게 하기 위해서다(M1 Task 5가 같은
이유를 적었다). 끝의 쉼표까지 함께 지우는 것이 요점이다.

Expected: 그 줄에 `hostfwd`가 하나만 남아 있고 그것이 45465 쪽이다.

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/inm2/check.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh > /tmp/inm2/neg1.log 2>&1
echo "exit=$?"
tail -30 /tmp/inm2/neg1.log
```

Expected: `exit=1`이고 이 줄이 나온다.

```
FAIL: nothing accepted on 127.0.0.1:45466 — QEMU never opened the second hostfwd port
```

그 앞에 `the guest is listening on port 8081`이 있어야 한다. M1의 실측 8이
검사 12에서 같은 것을 봤다 — 게스트가 듣는 것과 QEMU가 길을 내는 것은 서로
안 엮여 있다. 검사 14에서 죽으면 그 사실을 Task 8의 실측에 적는다.

- [x] Step 2: 반사실 2 — 음성 자리에 리스너를 하나 심는다

음성 검사의 반사실은 "그 조건을 깨는 것"이다. 듣는 것이 없어야 할 자리에
듣는 것을 하나 만들면 검사 16이 빨간불이어야 한다.

```bash
cp net/check.sh /tmp/inm2/check2.sh
sd -s 'echo "=== connecting with nothing listening on port ${GUEST_LISTEN_PORT} ==="' \
   'type_keys e c h o spc i n m 2 minus b r o k e n spc shift-backslash spc n c spc minus l spc minus p spc 8 0 8 0 spc shift-7 ret; sleep 2; echo "=== connecting with a listener that should not be there ==="' \
   /tmp/inm2/check2.sh
chmod +x /tmp/inm2/check2.sh
grep -n "inm2-broken" /tmp/inm2/check2.sh
```

한 줄짜리 치환인 이유는 `sd`의 치환 문자열에 개행을 넣는 것보다 `;`로
잇는 것이 무엇이 들어갔는지 사람이 읽기 쉽기 때문이다. `sleep 2`는 `bind`가
끝날 시간이고, 이 사본에서는 검사 14 같은 타이핑이 사이에 없으므로
명시적으로 준다.

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/inm2/check2.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh > /tmp/inm2/neg2.log 2>&1
echo "exit=$?"
tail -30 /tmp/inm2/neg2.log
```

Expected: `exit=1`이고 이 줄이 나온다.

```
FAIL: something answered on 127.0.0.1:45465 where nothing should be listening (got: [inm2-broken])
```

`exit=0`이 나오면 그것이 가장 나쁜 결과다 — 검사 16이 바이트를 안 보고
있다는 뜻이고, 그러면 `read`가 무엇을 받았는지부터 다시 봐야 한다. 그 다음
후보는 심은 리스너가 안 떴다는 것이므로 시리얼 로그에서 그 명령의 에코를
먼저 본다.

- [x] Step 3: 사본을 지우고 저장소가 안 변한 것을 본다

```bash
rm -f /tmp/inm2/check.sh /tmp/inm2/check2.sh
git status --short net/check.sh
```

Expected: `M net/check.sh` 하나. 반사실은 `/tmp` 사본을 `-v`로 덮어씌우는
것이라 저장소 파일을 한 번도 안 건드린다.

## Task 7 — 루트 게이트 한 판

IN이 여는 유일한 게이트다. M0은 파일을 안 바꿨고 M1은 "새 정보 없이 31분을
쓰지 않는다"로 미뤘다.

- [x] Step 1: 돌린다

약 31분이다(기준선이 30분 57.86초). 그 사이에 다른 작업을 겹치지 않는다 —
같은 기계에서 빌드가 돌면 시간 값이 잡음에 묻힌다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/inm2/gate.log 2> /tmp/inm2/gate.time
tail -30 /tmp/inm2/gate.log; cat /tmp/inm2/gate.time
```

Expected: 열두 체인이 전부 `3/3`이고 마지막이 통과다.

- [x] Step 2: 증가분을 계산한다

```bash
grep -c "skipping make" /tmp/inm2/gate.log
grep -E "^(PASS|FAIL|===)" /tmp/inm2/gate.log | tail -20
```

기준선 30분 57.86초에서 얼마나 늘었나를 적는다. 예상 증가분은 체인 단독
증가분 × 3이고, 게이트 잡음이 ±3분이라 그 크기는 게이트에서 안 잡힌다 —
그래서 판정은 "3/3"이고 시간은 참고값이다(design 위험 3).

## Task 8 — 실측을 적고 서브프로젝트를 닫는다

- [x] Step 1: design에 `## IN-M2가 실행으로 증명한 것` 절을 더한다

`## IN-M1이 실행으로 증명한 것` 절의 끝에 이어서 쓴다. 번호는 실측 13부터다.
넣을 것이 여섯이다.

1. 검사 14·15·16이 통과한 값. 화면의 `inm2-listen=N`의 N, `cat`이 찍은 줄,
   그리고 음성이 읽은 것이 비어 있었다는 것.
2. 반사실 1이 어디에서 죽었나. 검사 15면 예상대로이고 검사 14면 그 해석을
   적는다.
3. 반사실 2가 어디에서 죽었나. 검사 16이 실제로 바이트를 보고 있나.
4. fish의 job 종료 줄이 이번에는 나왔나. M1 실측 12가 "미뤄진 것"이라고
   적었고 검사 14의 타이핑이 그 프롬프트를 만든다 — 예측이 맞았는지를 적는다.
   이 저장소에서 예측을 적어 두고 다음 milestone이 확인하는 드문 자리다.
5. 체인 단독 시간. 8.954 → 17.082 → 22.911 → 27.955에 이어지는 다섯째 값.
6. 게이트. 열두 체인 3/3과 시간, `skipping make` 수.

- [x] Step 2: design의 M2 절과 Status 줄을 닫는다

M2 절 끝에 `⚠ 2026-09-14에 끝났다 …` 한 줄을 더하고, 문서 맨 위의

```
Status: 착수(2026-09-14) — M0부터 시작한다.
```

를 이렇게 고친다.

```
Status: 끝났다(2026-09-14). M0~M2. `net/check.sh`가 검사 열여섯이고 받는 길이
양방향으로 서는 것을 게이트가 매번 확인한다.
```

CLAUDE.md가 "서브프로젝트를 끝내면 그 design doc의 Status 줄을 함께 고친다"고
적어 둔 자리다. 2026-08-31에 낡은 것 넷을 한꺼번에 고친 적이 있다.

- [x] Step 3: 기억 파일과 `MEMORY.md` 한 줄

`docs/decisions/project_inbound_network.md`를 새로 만든다. 다른 project
기억과 같은 꼴이고, 넣을 것이 이 넷이다.

- 받는 길의 판정은 `rc`가 아니라 바이트 수다. 왜냐면 QEMU가 호스트 포트를
  스스로 listen해서 게스트에 아무도 없어도 connect가 성공한다(실측 4).
- 체인이 소켓에서 직접 읽어 판정하는 방법. 이 저장소에서 화면도 커널 로그도
  아닌 것으로 판정하는 첫 자리이고, 에코 함정이 원리적으로 성립하지 않는다.
- 음성 검사는 "붙는 것에 성공했는가"를 함께 봐야 한다. 안 보면 길이 통째로
  사라진 날 초록이 된다.
- `hostfwd` 둘과 `guestfwd` 하나가 한 `-netdev` 값에서 함께 산다. 게스트 쪽
  포트가 같아도 `guestfwd`와 `hostfwd`는 서로 다른 자리다(실측 10).

그리고 `MEMORY.md` 맨 끝에 한 줄을 더한다.

```markdown
- [Inbound network](docs/decisions/project_inbound_network.md) — 게스트가 포트를 열면 바깥에서 붙어 바이트를 읽는다; 판정은 `rc`가 아니라 받은 바이트 수이고 우리 코드는 0줄이다(IN-M0~M2, 2026-09-14 종료)
```

- [x] Step 4: CLAUDE.md의 완료 표에 한 줄

`| Guest Network (NW-M0~M3) | …` 줄 아래에 넣는다.

```markdown
| Inbound Network (IN-M0~M2) | 2026-09-14 | 게스트가 연 포트에 바깥에서 붙어 바이트를 읽는다. 우리 코드는 0줄이고 `net/check.sh`가 검사 열여섯이 됐다 |
```

- [x] Step 5: HANDOFF.md를 다시 쓴다

제목이 "IN이 끝났다"가 되고, "바로 다음에 할 것"이 다음 서브프로젝트를 고르는
것이 된다. IN design이 비목표로 미뤄 둔 것들(UDP · 포트 여럿 · 실머신에서
포트를 여는 것 · init이 듣는 것)과 NW가 미뤄 둔 후보들이 그 자리의 재료다.

- [x] Step 6: 무엇이 커밋에 들어가는지 먼저 본다

```bash
git status --short
```

Expected: 다섯 또는 여섯이다.

```
 M CLAUDE.md
 M HANDOFF.md
 M MEMORY.md
 M docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m2.md
 M docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md
 M net/check.sh
?? docs/decisions/project_inbound_network.md
```

이 plan 자신이 `M`인 것은 실행 전에 한 번 커밋되기 때문이다(M1도 그랬다).
Step 8이 그 파일 끝에 "갈린 자리"를 더하므로 여기서 다시 나온다.

`out/net.img`나 빌드 산출물이 보이면 `.gitignore`부터 확인한다. 이 저장소는
kernel/init/bootloader를 직접 빌드하므로 이 확인을 매번 한다(CLAUDE.md).

- [x] Step 7: 커밋을 둘로 나눈다

코드와 실측이 하나, 서브프로젝트를 닫는 문서가 하나다. 앞의 것만 되돌리는
경로가 있어야 하기 때문이다.

```bash
git add net/check.sh \
        docs/superpowers/specs/2026-09-14-tars-inbound-network-design.md \
        docs/superpowers/plans/2026-09-14-tars-inbound-network-in-m2.md
git commit -m "Send a line into the guest and prove the silence too"

git add CLAUDE.md MEMORY.md HANDOFF.md docs/decisions/project_inbound_network.md
git commit -m "Close the inbound network subproject"
```

- [x] Step 8: 이 문서 끝에 갈린 자리를 적는다

M0이 넷, M1이 셋을 적었고 둘 다 다음 세션에 값졌다. 갈린 것이 없으면 "갈린
자리가 없다"고 한 줄 적는다.

## 끝 기준

다섯이다.

1. `net/check.sh`가 단독으로 `PASS`하고, 검사 14·15·16의 초록 줄 셋이 로그에
   있다.
2. 반사실 1(둘째 `hostfwd`를 뺀 것)이 검사 15에서 죽는다. 검사 14에서 죽으면
   그 사실과 해석이 적혀 있다.
3. 반사실 2(음성 자리에 리스너를 심은 것)가 검사 16에서 죽는다.
4. 루트 게이트가 열두 체인 3/3이다.
5. design의 Status와 실측 절, `MEMORY.md`·`CLAUDE.md`·`HANDOFF.md`가 IN이
   끝난 것을 적고 있다.

저장소에서 바뀌는 코드 파일은 `net/check.sh` 하나다. 커널도 `guest_tools.sh`도
`init/`도 IN 내내 한 글자도 안 바뀐다 — 이 사이클이 답한 질문이 우리 코드에
대한 것이 아니었다는 증거다.

## 실제로 돌린 것이 이 plan과 갈린 자리

셋이다. 검사 셋이 첫 회에 다 서서 고친 자리는 없었다.

1. Task 5의 두 부팅 순서가 뒤집혔다. plan이 Step 2(시간)를 먼저, Step 3(로그
   추출)을 나중에 적었는데 실제로는 로그 추출 회차를 먼저 돌리고 순수 시간을
   나중에 쟀다. 이유는 로그 추출 회차가 `for f in /tmp/tmp.*`와 `cp`를 함께
   도는 것이라 그 값이 체인 시간이 아니기 때문이다(실제로 34.618초 대
   33.730초로 갈렸다). 다음에 이 모양을 쓰는 사람은 "시간을 재는 회차"와
   "로그를 꺼내는 회차"를 처음부터 나눠 적는다.

2. Task 6 Step 2의 확인 명령이 애초에 맞을 수 없는 것이었다.
   `grep -n "inm2-broken"`으로 치환을 확인하려 했는데, `type_keys`는 키 이름을
   공백으로 나눠 적으므로 그 연속 문자열이 파일에 없다. 치환은 성공했는데
   확인이 0줄을 내서 잠깐 실패로 읽혔다. 맞는 확인은
   `grep -n "connecting with"`으로 그 줄 자체를 보는 것이다.

3. 실측 15가 plan에 없던 것이다. 로그를 읽다가 fish의 autosuggestion이 화면에
   남는 것을 봤고, 그것이 `project_gate_screen_echo.md`가 적은 함정의 확장판
   이었다. Task 5 Step 3을 "통과해도 로그를 꺼낸다"로 둔 것이 그 값을 만들었다 —
   M1의 갈린 자리 1이 없었으면 이 사실을 못 봤을 것이다.
