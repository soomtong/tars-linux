# LB-M3 — 게이트가 `lo`와 `.localhost`를 매번 본다

> 이 plan을 실행하는 사람에게: 고치는 것은 `gate_lib.sh`(타이핑 헬퍼 하나) ·
> `tools/check.sh`(검사 20 · 21) · `net/check.sh`(검사 29 · 30)다. 새 체인은 없고
> QEMU 호출도 안 는다(design 결정 6). mutation 둘은 작업 트리에서만 하고 되돌린다.

Goal: `net=off`(`tools` 체인)와 `net=dhcp`(`net` 체인) 두 부팅에서, 게스트 안의 두
프로세스가 `127.0.0.1` · `localhost` · `app.localhost` 세 이름으로 TCP를 주고받는
것을 게이트가 매번 본다.

Architecture: 이름마다 한 번 응답하는 리스너를 배경에 두고(`nc -l -p P < /dev/null >
/tmp/lb-T.txt &`), 그 이름으로 `/etc/passwd`를 흘려 보낸다(`nc -q 1 NAME P <
/etc/passwd`). 마지막에 `grep -c root` 한 번으로 세 파일을 센다 — 출력이
`/tmp/lb-T.txt:N` 꼴이라 이름마다 판정이 갈린다. 타이핑은 두 체인이 같으므로
`gate_lib.sh`의 헬퍼 하나이고, 판정은 각 체인이 한다(그 파일의 규칙 — "부르는 쪽이
`fail()`로 진단을 찍는다").

Tech Stack: bash · QEMU monitor `sendkey` · 게스트 fish · `nc.traditional`

---

## 결정

- M3-A 판정 글자는 `lb-T.txt:1`이다. 친 명령줄에는 `/tmp/lb-T.txt ` 뒤에 공백이
  오므로 `:1`이 안 붙는다 — 에코 함정(NW-M3 실측 2)에 안 걸린다. `:0`이면 받은 것이
  없다는 뜻이고, 그 모양이 M0 실측 2가 정한 "받은 글자가 없다" 판정이다(에러 문구로
  판정하지 않는다 — `net=dhcp`에서는 문구가 없다).
- M3-B 흘려 보내는 것은 `/etc/passwd`이고 `grep -c root`로 센다. 처음 plan은
  `/etc/hosts`와 `grep -c localhost`였는데, mutation 3(그 파일을 비움)에서 세 이름이
  전부 `:0`으로 빨갛게 됐다 — 리스너 셋이 전부 `has ended`라 연결은 됐고, 보낼
  내용이 사라진 것이었다. 게이트가 "loopback을 못 건넜다"고 말하면서 원인은 딴 데
  있는 모양이라, 판정의 재료를 판정 대상과 무관한 파일로 옮겼다. 옮긴 뒤 mutation
  셋을 전부 다시 돌렸다.
- M3-C 리스너의 stdin은 `/dev/null`이다. 배경 job이 터미널을 읽으면 SIGTTIN으로
  멈춘다(`net/check.sh` 검사 14의 주석, TS-M2가 고친 자리).
- M3-D 포트는 9101 · 9102 · 9103. 두 체인의 기존 포트(8080 · 8081, hostfwd 쪽
  45465 등)와 안 겹친다. 이름마다 포트가 달라 앞 연결의 흔적이 다음 리스너를 안 막는다.
- M3-E 왕복 검사가 로그 줄 검사보다 앞이다. mutation 1(`loopbackUp()`을 뺌)에서 빨간
  것이 로그 줄이 아니라 왕복이어야 이 검사가 장식이 아니라는 증거가 된다.
- M3-F `/etc/hosts`의 `localhost` 줄은 게이트가 따로 못 지킨다. `myhostname`도
  `localhost`에 답하므로 그 줄을 지워도 `localhost` 왕복이 초록이다. 그 줄이 필요한
  것은 NSS를 안 거치는 resolver 때문인데 게스트에 그런 클라이언트가 없다(design
  비목표 1). mutation 3으로 그 사실을 한 번 재서 design에 적는다.

## Task 1 — `gate_lib.sh`에 타이핑 헬퍼

**Files:** Modify `gate_lib.sh` — 파일 끝.

- [ ] Step 1: 넣는다

```bash

# ── loopback 왕복 — LB-M3 ────────────────────────────────────────────
#
# 게스트 안의 두 프로세스가 이름 셋으로 TCP를 한 번씩 주고받게 친다.
# tools 체인(net=off)과 net 체인(net=dhcp)이 같은 것을 치므로 여기 있다.
# 판정은 부르는 쪽이 한다 — 마지막 줄의 출력이
#
#   /tmp/lb-ip.txt:1   /tmp/lb-lh.txt:1   /tmp/lb-app.txt:1
#
# 이고, 친 명령줄에는 파일 이름 뒤에 `:`가 안 붙으므로 에코와 안 겹친다.
# 받은 것이 없으면 `:0`이다. 세는 것은 흘려 보낸 /etc/passwd의 `root`다.
#
#   ip   127.0.0.1      lo가 UP인가(init의 loopbackUp)
#   lh   localhost      /etc/hosts 또는 myhostname
#   app  app.localhost  myhostname만 답한다
#
# 리스너의 stdin을 /dev/null로 돌리는 것이 중요하다. 배경 job이 터미널을
# 읽으면 SIGTTIN으로 멈추고 받은 것을 파일에 안 쓴다(net/check.sh 검사 14).
# -q 1은 보내는 쪽 stdin의 EOF 뒤 1초에 닫는다.
#
# 흘려 보내는 것이 /etc/passwd인 데 이유가 있다. 처음에는 /etc/hosts였는데
# mutation(그 파일을 비움)에서 세 이름이 전부 `:0`이 됐다 — 연결은 셋 다
# 됐는데(`has ended`) 보낼 내용이 사라진 것이다(LB design 실측). 게이트가
# "loopback을 못 건넜다"고 말하면서 원인은 딴 데 있는 모양이라, 판정의 재료를
# 판정 대상(이름 풀이)과 무관한 파일로 옮겼다. passwd는 늘 있고 LB가 안
# 만진다.
type_loopback_roundtrips() {
  # nc -l -p 9101 < /dev/null > /tmp/lb-ip.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 1 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus i p dot t x t spc shift-7 ret
  # nc -q 1 127.0.0.1 9101 < /etc/passwd
  type_keys n c spc minus q spc 1 spc 1 2 7 dot 0 dot 0 dot 1 spc 9 1 0 1 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # nc -l -p 9102 < /dev/null > /tmp/lb-lh.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 2 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus l h dot t x t spc shift-7 ret
  # nc -q 1 localhost 9102 < /etc/passwd
  type_keys n c spc minus q spc 1 spc l o c a l h o s t spc 9 1 0 2 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # nc -l -p 9103 < /dev/null > /tmp/lb-app.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 3 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus a p p dot t x t spc shift-7 ret
  # nc -q 1 app.localhost 9103 < /etc/passwd
  type_keys n c spc minus q spc 1 spc a p p dot l o c a l h o s t spc 9 1 0 3 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # grep -c root /tmp/lb-ip.txt /tmp/lb-lh.txt /tmp/lb-app.txt
  type_keys g r e p spc minus c spc r o o t spc \
    slash t m p slash l b minus i p dot t x t spc \
    slash t m p slash l b minus l h dot t x t spc \
    slash t m p slash l b minus a p p dot t x t ret
}
```

## Task 2 — `tools/check.sh` 검사 20 · 21

**Files:** Modify `tools/check.sh` — 검사 18의 `echo "zoxide learned ..."` 다음, 검사
19 주석 블록 앞.

- [ ] Step 1: 넣는다

```bash

# ── 검사 20: 게스트 안의 두 프로세스가 이름 셋으로 주고받나 (LB-M3) ──────
#
# 번호가 19 뒤인데 자리는 19 앞이다. 19는 음성 확인이라 언제나 맨 뒤이고,
# 앞에 무엇이 늘든 늘어난 것까지 함께 본다(그 주석의 규칙) — 여기서 nc를
# 못 찾으면 19가 `Unknown command`로 잡는다.
#
# 이 체인은 설정 디스크가 없어서 net=off이고 NIC도 없다(-nic none). 그래서
# 여기서 서는 것은 전부 기계 안의 길이다. lo를 올리는 것은 init이고(LB
# design 결정 1 · 3), 이름은 initrd의 파일 둘과 myhostname이 푼다(결정 5).
# 셋 중 하나만 빠져도 그 이름의 파일이 `:0`이다.
echo "=== typing three loopback round trips (127.0.0.1 · localhost · app.localhost) ==="
type_loopback_roundtrips
for tag in ip lh app; do
  if ! wait_for_screen "lb-${tag}\.txt:1"; then
    fail "nothing crossed loopback by the name behind lb-${tag}" \
      "lb-[a-z]*\.txt:[0-9]" "tars-init: lo" "forward host lookup failed"
  fi
done
echo "two guest processes talked over 127.0.0.1, localhost and app.localhost"

# ── 검사 21: init이 lo를 올렸다고 말했나 (LB-M3) ───────────────────────
#
# 검사 20 뒤인 이유가 LB-M3 plan 결정 M3-E다. 앞에 두면 mutation(loopbackUp을
# 뺌)에서 이 줄이 먼저 빨갛게 되고, 왕복 검사가 실제로 무엇을 잡는지는 안
# 보인다. 이 줄의 값은 진단이다 — 검사 20이 빨간 날 "init이 시도는 했나"를
# 가른다.
if ! grep -a "tars-init: lo up" "$LOG" >/dev/null; then
  fail "init never said it raised lo" "tars-init: lo" "tars-init: cannot"
fi
echo "init raised lo"
```

## Task 3 — `net/check.sh` 검사 29 · 30

**Files:** Modify `net/check.sh` — 검사 16의 `echo "with no listener the chain read
nothing, as it should"` 다음, `# ── 끈다 ──` 앞.

- [ ] Step 1: 넣는다

```bash

# ── 검사 29: net=dhcp에서도 기계 안의 길이 서나 (LB-M3) ──────────────────
#
# tools/check.sh 검사 20과 같은 것을 친다(gate_lib.sh의 헬퍼). 이 부팅에서
# 따로 보는 이유가 LB-M0 실측 4다 — 파일이 없던 때 net=dhcp에서는 SLIRP
# 너머 호스트 DNS가 `localhost`에 답해서 초록인 척할 수 있었고, net=off에서는
# 못 했다. 두 부팅의 답이 같다는 것이 "이름 풀이가 네트워크에 안 기댄다"의
# 증거다. `app.localhost`는 호스트 DNS가 답하지 않으므로(같은 실측) 여기서
# myhostname이 빠지면 이 부팅에서도 빨갛다.
#
# 이 체인의 번호는 부팅 순서가 아니라 생긴 순서다(검사 23 · 24가 20 앞에
# 있다). 이 둘은 첫 부팅의 끝에 붙는다.
echo "=== typing three loopback round trips (127.0.0.1 · localhost · app.localhost) ==="
type_loopback_roundtrips
for tag in ip lh app; do
  if ! wait_for_screen "lb-${tag}\.txt:1"; then
    fail "nothing crossed loopback by the name behind lb-${tag}" \
      "lb-[a-z]*\.txt:[0-9]" "tars-init: lo" "forward host lookup failed"
  fi
done
echo "two guest processes talked over 127.0.0.1, localhost and app.localhost"

# ── 검사 30: init이 lo를 올렸다고 말했나 (LB-M3) ───────────────────────
# tools/check.sh 검사 21과 같다. net=dhcp라도 lo는 dhcpcd가 아니라 init이
# 올린다 — dhcpcd는 lo를 안 만진다(WN design 덤).
if ! grep -a "tars-init: lo up" "$LOG" >/dev/null; then
  fail "init never said it raised lo" "tars-init: lo" "tars-init: cannot"
fi
echo "init raised lo"
```

- [ ] Step 2: 체인 둘을 돌린다 (약 2분 20초)

```bash
for C in tools net; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash $C/check.sh > /tmp/lb/chain-m3-$C.log 2>&1; echo "$C exit=$?"
  grep -E 'loopback|lo$|raised lo|^FAIL|^PASS' /tmp/lb/chain-m3-$C.log
done
```

기대: 둘 다 `exit=0`, 검사 20/29의 성공 줄과 21/30의 `init raised lo`, `PASS`.

## Task 4 — mutation 셋 (각 약 1분, `tools` 체인)

작업 트리에서만 고치고 매번 되돌린다. 되돌린 뒤 `git diff --stat`이 Task 1~3의 것만
보여야 한다.

- [ ] Step 1: `lo`를 안 올린다

```bash
sd '^    net\.loopbackUp\(\);' '    // net.loopbackUp();' init/src/main.zig
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh > /tmp/lb/cf1.log 2>&1; echo "exit=$?"
grep -A4 '^FAIL' /tmp/lb/cf1.log
git checkout init/src/main.zig
```

기대: `exit=1`, `FAIL: nothing crossed loopback by the name behind lb-ip`. 진단 줄에
`lb-ip.txt:0`이 보인다(`lh` · `app`도 `:0`일 것이다 — 이름이 풀려도 `lo`가 없다).

- [ ] Step 2: `myhostname`을 뺀다

```bash
sd '^hosts: files myhostname dns$' 'hosts: files dns' kernel/make_initrd.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh > /tmp/lb/cf2.log 2>&1; echo "exit=$?"
grep -A4 '^FAIL' /tmp/lb/cf2.log
git checkout kernel/make_initrd.sh
```

기대: `exit=1`, `FAIL: ... lb-app`. `lb-ip.txt:1` · `lb-lh.txt:1`은 초록으로 지나간다.

- [ ] Step 3: `/etc/hosts`를 비운다 (M3-F를 재는 것)

```bash
sd '^127\.0\.0\.1 localhost$' '' kernel/make_initrd.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh > /tmp/lb/cf3.log 2>&1; echo "exit=$?"
tail -2 /tmp/lb/cf3.log
git checkout kernel/make_initrd.sh
```

기대: `exit=0` — `myhostname`이 `localhost`에도 답해서 게이트가 이 줄의 부재를 못
본다. 이 초록이 M3-F의 증거이고 design에 그대로 적는다. 빨갛다면 기대가 틀린 것이고
그것이 더 좋은 소식이다(그 줄을 게이트가 지킨다) — 그때는 무엇이 빨갛게 했는지 적는다.

- [ ] Step 4: 되돌린 것을 확인한다

```bash
git diff --stat
```

기대: `gate_lib.sh` · `tools/check.sh` · `net/check.sh` 셋뿐.

## Task 5 — 루트 게이트 (약 42분)

- [ ] Step 1

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh > /tmp/lb/gate.log 2>&1 ; } 2>&1 | tail -3
grep -c '^FAIL' /tmp/lb/gate.log; tail -3 /tmp/lb/gate.log
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`, `FAIL` 0줄.
`run_in_background`로 돌리면 완료 알림을 믿지 말고
`pgrep -f 'tars-devcontainer bash check.sh'`가 비는 것을 본다(HANDOFF의 주의).

## Task 6 — 문서와 커밋

- [ ] Step 1: design에 "LB-M3이 실행으로 증명한 것"(실측 15부터 — 체인 결과, mutation
  셋, 루트 게이트)을 더하고 `Status:`를 `끝났다(2026-09-26) — M0~M3, 실측 1~N.`으로.
- [ ] Step 2: `docs/decisions/project_loopback.md`를 만들고 `MEMORY.md`에 한 줄.
- [ ] Step 3: `CLAUDE.md`의 완료 표에 한 줄. `HANDOFF.md`를 새 머리로.
- [ ] Step 4

```bash
git status --short
git diff --stat
git add gate_lib.sh tools/check.sh net/check.sh \
        docs/specs/2026-09-26-tars-loopback-design.md \
        docs/plans/2026-09-26-tars-loopback-lb-m3.md \
        docs/decisions/project_loopback.md MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Close LB-M3: the gate sees lo and .localhost in both net modes"
```
