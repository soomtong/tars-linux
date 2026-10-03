# DS-M2 — 게이트가 감독을 판정하고 DS를 닫는다

> 이 plan을 실행하는 사람에게: 코드(`init`)는 안 고친다. 고치는 것은 체인 둘(net ·
> service)과 가이드 · 기억 · 표다. 반사실은 커밋하지 않는 임시 편집이고, 끝나면
> `git diff`가 비었는지 본다.

Goal: DS design 결정 7이 남긴 판정 넷(죽으면 다시 뜬다 · `tars-service`가 다룬다 ·
`ntp=dhcp`에서 재시작이 없다 · 버튼 fd가 안 샌다)을 게이트에 넣고, 반사실 둘로 그
판정이 거짓 초록이 아닌지 보고, 루트 게이트로 닫는다.

Architecture: 새 체인은 없다. net 체인 부팅 A(chronyd가 stub 10.0.2.2를 믿는
부팅)에 검사 29 · 30을, 부팅 B(`ntp=dhcp`, 상대 없음)에 검사 31을 더한다. service 체인
부팅 D의 검사 17(`status` 표)과 26(서비스 자식의 fd)에 줄을 더한다.

Tech Stack: bash(체인) · QEMU monitor의 `sendkey`(`type_keys`) · ssh ControlMaster

---

## 결정 — design이 plan에 맡긴 것

- M2-A — 죽음은 사람이 콘솔에서 `kill -9`로 만든다. `tars-service restart`는 CT가 이미
  범용으로 판정했으므로(service 검사 21), dhcpcd는 감독자의 "죽으면 다시 띄운다" 갈래를
  본다. SIGKILL인 까닭 — SIGTERM이면 dhcpcd가 주소를 지우고 죽어서(M0 실측 3) "다시
  받았다"가 "지운 것을 다시 붙였다"와 섞인다. SIGKILL은 주소를 남기고 가므로 새 dhcpcd의
  lease 줄이 곧 "다시 뜬 것이 일을 한다"의 증거다.
- M2-B — 새 dhcpcd의 lease는 `-j`의 줄머리 `[새 pid]:`로 가른다. 옛 dhcpcd의 lease 줄과
  섞이지 않는다(M0 실측 2가 `-j`를 남긴 이유다).
- M2-C — chronyd는 `tars-service restart chronyd`로 본다. 판정은 `Selected source
  10.0.2.2`가 한 번 더 나오는 것이다. chronyd `-d`는 stderr가 콘솔이라 그 줄이 시리얼에
  온다. 시계는 이미 2031년이라 점프는 안 본다.
- M2-D — 검사 31(`ntp=dhcp`에서 재시작 없음)은 부팅 B가 뜬 지 40초가 지나서 본다. 옛
  코드의 루프 주기가 30초(60 × 0.5초)였으므로 40초면 옛 코드는 적어도 한 번 다시 떴다.
  부팅 B가 그보다 일찍 끝나면 남은 만큼 잔다 — 체인에 최대 약 30초가 는다.
- M2-E — 검사 31의 반사실은 안 돌린다. 되살릴 옛 코드가 `3f56ff9`에서 로그 줄과 함께
  지워졌고, 되살리면 검사 21도 함께 빨개져서 무엇이 잡았는지 안 갈린다. 이 한계는
  design에 적는다.
- M2-F — service 체인 부팅 D의 `tars.conf`는 `ntp`가 없다(기본값 `off`). 그래서 `status`에
  `service dhcpcd`가 있고 `service chronyd`가 없어야 한다. 없는 쪽도 판정이다 — `ntp=off`의
  "안 넣었다"가 표에서 보인다.

## Task 0 — 시작 상태

```bash
git status --short
git log --oneline -1
```

기대: 이 plan만 `??`, 머리가 `648bf9e`.

## Task 1 — net 체인 부팅 A에 검사 29 · 30

File: `net/check.sh` — "검사 24"의 `echo "the guest shows …"` 다음, `# ── 부팅 A를 끈다` 앞.
이 자리에서 fd 3(monitor)이 열려 있고 `LOG="$LOGA"`이며 stub이 살아 있다.

- [ ] Step 1: 넣는다

```bash
# ── 검사 29: 죽은 dhcpcd를 감독자가 되살리고, 새 것이 주소를 받나 (DS-M2) ──
# DS design 결정 1의 한가운데다. 사람이 콘솔에서 dhcpcd를 SIGKILL로 죽인다
# (plan 결정 M2-A — SIGTERM이면 주소를 지우고 가서 판정이 섞인다). 감독자가
# 그 죽음을 거두고 다음 바퀴에 새 pid로 띄우고, 새 dhcpcd가 lease를 받는다.
#
# 새 lease는 `-j`의 줄머리 `[새 pid]:`로 가른다(M2-B). 옛 dhcpcd의 줄과 안 섞인다.
# 이 판정이 -B의 반사실을 받는다 — -B가 없으면 쥔 pid는 배경으로 간 뒤 이미 죽어
# 있어서 "killed (pid 옛, signal 9"가 영영 안 나온다.
OLD_DHCPCD="$(grep -aoE 'tars-init: started service dhcpcd \(pid [0-9]+' "$LOGA" | tail -1 | grep -oE '[0-9]+$')"
[ -n "$OLD_DHCPCD" ] || fail "init never started dhcpcd in the ntp guest" "tars-init: started service"
echo "=== typing 'kill -9 \$(pgrep -x dhcpcd)' (dhcpcd is pid ${OLD_DHCPCD}) ==="
type_keys k i l l spc minus 9 spc shift-4 shift-9 p g r e p spc minus x spc d h c p c d shift-0 ret
wait_log "tars-init: service dhcpcd killed (pid ${OLD_DHCPCD}, signal 9," || \
  fail "init never reaped the killed dhcpcd (pid ${OLD_DHCPCD})" "tars-init: service dhcpcd"
NEW_DHCPCD=""
for _ in $(seq 1 30); do
  NEW_DHCPCD="$(grep -aoE 'tars-init: started service dhcpcd \(pid [0-9]+' "$LOGA" | tail -1 | grep -oE '[0-9]+$')"
  [ "$NEW_DHCPCD" != "$OLD_DHCPCD" ] && break
  sleep 1
done
[ "$NEW_DHCPCD" != "$OLD_DHCPCD" ] || \
  fail "init did not start a new dhcpcd after pid ${OLD_DHCPCD} died" "tars-init: service dhcpcd"
wait_log "\[${NEW_DHCPCD}\]: eth0: leased 10\.0\.2\.15 " || \
  fail "the new dhcpcd (pid ${NEW_DHCPCD}) never leased 10.0.2.15" "\[${NEW_DHCPCD}\]"
echo "a killed dhcpcd (pid ${OLD_DHCPCD}) came back as pid ${NEW_DHCPCD} and leased 10.0.2.15 again"

# ── 검사 30: tars-service restart chronyd 뒤에 chronyd가 다시 서버를 고르나 (DS-M2) ──
# chronyd가 서비스라서 CT의 동사가 그대로 닿는다(DS design 결정 1). 다시 뜬
# chronyd가 설정을 읽고 stub을 다시 믿는 것이 `Selected source` 한 줄 더다(M2-C).
# 판정은 시리얼 로그라서 친 명령이 화면에 남아도 섞이지 않는다.
SELECTED_BEFORE="$(grep -ac "Selected source ${NTP_SERVER}" "$LOGA")"
echo "=== typing 'tars-service restart chronyd' ==="
type_keys t a r s minus s e r v i c e spc r e s t a r t spc c h r o n y d ret
wait_log "tars-init: restarting service chronyd on request" || \
  fail "init did not restart chronyd on request" "tars-init: control" "tars-init: service chronyd"
RESELECTED=0
for _ in $(seq 1 30); do
  if [ "$(grep -ac "Selected source ${NTP_SERVER}" "$LOGA")" -gt "$SELECTED_BEFORE" ]; then RESELECTED=1; break; fi
  sleep 1
done
[ "$RESELECTED" = "1" ] || fail "the restarted chronyd never selected ${NTP_SERVER} again" \
  "Selected source" "tars-init: service chronyd"
echo "tars-service restart chronyd, and the new chronyd selected ${NTP_SERVER} again"
```

`wait_log`은 검사 18이 정의한 함수다(90초, `$LOGA`).

- [ ] Step 2: 체인 머리의 부팅 A 설명(43~52행 근처)에 한 줄을 더한다

```bash
#   → (DS-M2) 사람이 dhcpcd를 죽이면 감독자가 되살리고, chronyd를
#     tars-service로 다시 띄우면 다시 stub을 고른다
```

## Task 2 — net 체인 부팅 B에 검사 31

File: `net/check.sh` — 검사 22의 `echo "the dead ntp server cost …"` 다음, `# ── 부팅 B를 끈다` 앞.

- [ ] Step 1

```bash
# ── 검사 31: ntp=dhcp의 chronyd가 서버 없이 산다 (DS-M2) ─────────────────
# DS design 확인 3이 막으려던 것. 옛 코드는 chronyd 앞에서 서버 파일을 30초
# 기다리고 없으면 exit(0)했다 — 감독 목록에 그대로 넣었으면 30초마다 다시
# 떴다. 지금 chronyd는 sourcedir만 들고 서버 0개로 떠서 산다(결정 3).
#
# 40초를 채우고 본다(plan 결정 M2-D). 옛 주기가 30초이므로 그 안에 적어도
# 한 번은 다시 떴을 시간이다. 이 부팅이 그보다 일찍 여기 오면 남은 만큼 잔다.
#
# 반사실이 없다(M2-E). 옛 코드는 로그 줄과 함께 지워졌다.
B_ELAPSED=$(( $(date +%s) - BOOT_B_START ))
if [ "$B_ELAPSED" -lt 40 ]; then
  echo "waiting $(( 40 - B_ELAPSED ))s so a 30s restart loop would have shown"
  sleep $(( 40 - B_ELAPSED ))
fi
N_CHRONYD="$(grep -ac "tars-init: started service chronyd " "$LOGB")"
[ "$N_CHRONYD" = "1" ] || fail "chronyd started ${N_CHRONYD} times in the ntp=dhcp guest, want 1" \
  "tars-init: service chronyd" "tars-init: started service chronyd"
if grep -aE "tars-init: service chronyd (exited|killed)" "$LOGB" >/dev/null; then
  fail "chronyd died in the ntp=dhcp guest" "tars-init: service chronyd"
fi
echo "after 40s the ntp=dhcp chronyd is still the one started at boot"
```

## Task 3 — service 체인 부팅 D의 검사 17 · 26

File: `service/check.sh`

- [ ] Step 1: 검사 17의 `for want in …` 목록에 한 줄을 더하고, 뒤에 음성 하나

```bash
for want in '^terminal +running +pid [0-9]+' '^console shell +running +pid [0-9]+' \
            '^service dhcpcd +running +pid [0-9]+' \
            '^service flaky +given up$' '^service sleeper +running +pid [0-9]+' \
            '^service sshd +running +pid [0-9]+' '^service stubborn +running +pid [0-9]+'; do
  grep -qE "$want" <<<"$OUT" || fail "status has no line like /${want}/ (got: [${OUT}])"
done
# DS-M2 결정 M2-F. 이 디스크는 ntp가 없다(기본값 off) — chronyd는 목록에 없어야 한다.
if grep -qE '^service chronyd' <<<"$OUT"; then
  fail "status lists chronyd although this disk leaves ntp off (got: [${OUT}])"
fi
echo "status showed the terminal, the console shell, dhcpcd and four services, flaky given up, no chronyd"
```

옛 `echo "status showed …"` 줄은 지운다.

- [ ] Step 2: 검사 26 뒤에 줄 둘

```bash
# DS design 결정 6. 전원 버튼 fd도 안 샌다. CLOEXEC가 빠지면 sleep의 fd 3이
# /dev/input/event0이다(DS-M0의 기준선).
grep -q "/dev/input/event" <<<"$FDS" && fail "sleeper's sleep holds a power button fd (${FDS})"
echo "sleeper's child holds no socket and no power button fd from init"
```

그 위의 `echo "sleeper's child holds no socket from init"`은 지운다.

- [ ] Step 3: 머리 주석 부팅 D 문단 끝에 한 문장

```bash
# DS-M2부터 dhcpcd도 이 목록에 있다(ntp가 없어 chronyd는 없다).
```

## Task 4 — 두 체인을 돌린다 (약 5분)

```bash
for c in net service; do
  s=$(date +%s)
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./$c/check.sh > /tmp/ds2-$c.log 2>&1
  echo "$c exit=$? fails=$(grep -c '^FAIL' /tmp/ds2-$c.log) secs=$(( $(date +%s) - s ))"
done
grep -E "killed dhcpcd|restart chronyd|after 40s|dhcpcd and four|power button" /tmp/ds2-*.log
```

기대: 둘 다 exit 0. net의 시간이 앞 판(118초)보다 최대 30초쯤 는다(M2-D).

## Task 5 — 반사실 둘 (각 약 2분, 커밋하지 않는다)

- [ ] Step 1: `-B`를 뺀다

```bash
sd -F '"-B", "-j"' '"-j"' init/src/net.zig
sd -F '"ntp_servers", null, null,' '"ntp_servers", null, null, null,' init/src/net.zig
git diff --stat
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./net/check.sh > /tmp/ds2-cf-B.log 2>&1; echo "exit=$?"
grep -E "^FAIL" -A12 /tmp/ds2-cf-B.log | head -30
git checkout init/src/net.zig
```

예측: 쥔 pid가 배경으로 간 뒤 exit 0으로 죽고 감독자가 다시 띄운다 — 빨리 죽음 셋에
포기(`giving up on service dhcpcd`). 어느 검사가 먼저 잡는지를 적는다(검사 4는 `started
service dhcpcd` 한 줄만 보므로 초록일 수 있다. 29가 잡는다고 짐작한다).

- [ ] Step 2: `CLOEXEC`를 뺀다

```bash
sd -F '.NONBLOCK = true, .CLOEXEC = true }' '.NONBLOCK = true }' init/src/devices.zig
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./service/check.sh > /tmp/ds2-cf-C.log 2>&1; echo "exit=$?"
grep -E "^FAIL" -A3 /tmp/ds2-cf-C.log | head
git checkout init/src/devices.zig
git status --short
```

예측: 검사 26의 `holds a power button fd`. 끝에 `git status`에 체인 둘과 plan만 있어야 한다.

- [ ] Step 3: 산출물을 되돌린 소스로 다시 빌드한다(`project_zig_out_staleness`) — Task 7의
  루트 게이트가 빌드부터 하므로 따로 안 한다. 반사실 뒤에 체인 하나를 초록으로 다시
  보는 것은 루트 게이트가 겸한다.

## Task 6 — 가이드 · 기억 · 표

- [ ] Step 1: `docs/guides/running-tars.md`

"서비스를 멈추고 다시 띄우기"의 표 예시에 줄 둘을 넣는다.

```
terminal        running   pid 35   up 14s
console shell   running   pid 36   up 14s
service dhcpcd  running   pid 37   up 14s
service chronyd running   pid 38   up 14s
service sshd    running   pid 40   up 14s
service web     stopped
service broken  given up
```

목록에 한 항목:

```
- `service dhcpcd` · `service chronyd`는 `services.d`가 아니라 `tars.conf`에서 온다 —
  `net=dhcp`면 dhcpcd, 거기에 `ntp`가 켜져 있으면 chronyd. 다른 서비스와 똑같이 죽으면
  다시 뜨고 `tars-service`로 다룬다. dhcpcd를 `restart`하면 주소가 약 6초 빠진다(SIGTERM을
  받은 dhcpcd는 주소를 지우고 간다). `services.d`에 같은 이름을 두면 건너뛴다.
```

"네트워크" 표 칸의 "`init`이 dhcpcd를 띄운다(NW)"를 "`init`이 dhcpcd를 띄우고 감독한다
(NW · DS)"로.

- [ ] Step 2: `docs/decisions/project_daemon_supervision.md`

```markdown
---
name: project_daemon_supervision
description: dhcpcd와 chronyd가 감독 목록 안이다 — -B로 pid를 지키고, chronyd의 서버는 sourcedir로 나중에 온다(DS-M0~M2, 2026-09-27 종료)
metadata:
  type: project
---

dhcpcd와 chronyd는 `init`이 스스로 `children`의 2 · 3번 칸에 넣는 `Kind.service`다.
label은 `service dhcpcd` · `service chronyd`이고 `services.d`의 같은 이름은 건너뛴다.

- dhcpcd는 `-B`다. manager mode는 lease 전에 배경으로 가서 PID 1이 쥔 pid가 곧 죽는다.
  `-B`여도 나중에 꽂힌 동글을 같은 pid로 잡는다(DS-M0 실측 7).
- `-j /dev/console`은 남겼다. `-B`에서는 줄이 두 벌이 되지만 `[pid]` 줄머리가 체인의 판정
  근거다.
- chronyd 앞의 30초 기다림을 지웠다. `ntp=dhcp`면 설정이 `sourcedir
  /run/tars/chrony.sources`이고 hook이 `dhcp.sources`를 쓴 뒤 `chronyc -h
  /run/chrony/chronyd.sock reload sources || true`. chronyd는 뜰 때도 그 디렉터리를 읽는다.
- 그룹 SIGTERM은 돌고 있던 dhcpcd hook도 죽인다. 다음 lease가 다시 쓴다.
- 게이트의 SLIRP는 option 42를 안 주므로 hook의 reload 경로는 게이트 안에서 안 돈다 —
  증거는 DS-M0 실측 5 하나다.

**Why:** 두 데몬이 목록 밖이면 죽어도 안 뜨고, 사람이 `tars-service`로 못 다룬다(SV 비목표 5).

**How to apply:** 감독 목록에 넣을 데몬은 갈라지지 않게 띄운다. execve 앞에 우리 코드를
두지 않는다 — 기다림이 필요하면 데몬의 기능(sourcedir 같은)으로 옮긴다. [[project_boot_services]] · [[project_service_control]] · [[project_time_discipline]]
```

`MEMORY.md`의 project 목록 끝에 한 줄:

```
- [Daemon supervision](docs/decisions/project_daemon_supervision.md) — dhcpcd(`-B`)와 chronyd가 감독 목록 안이다; chronyd의 DHCP 서버는 sourcedir와 hook의 `chronyc reload`로 온다(DS-M0~M2, 2026-09-27 종료)
```

- [ ] Step 3: `CLAUDE.md` 완료 표 끝에 한 줄

```
| Daemon Supervision (DS-M0~M2) | 2026-09-27 | dhcpcd와 chronyd가 감독 목록에 들어갔다 — 죽으면 다시 뜨고 `tars-service`로 다룬다. dhcpcd는 `-B`, chronyd 앞의 30초 기다림은 chrony `sourcedir`로 바뀌었다. 덤으로 버튼 fd에 `CLOEXEC`. 새 체인 없이 net · service 체인이 본다 |
```

- [ ] Step 4: `docs/guides/lessons.md`의 이월 숙제에서 버튼 fd `CLOEXEC` 줄을 지운다. "다시
  조사하지 말 실측" 쪽에 둘을 더한다 — `sd -F`는 치환 문자열의 `\n`을 글자 그대로
  넣는다(여러 줄은 python이나 Edit로) · `zig build test`가 `file contents changed during
  update`로 멈추면 편집 직후라서이고 다시 돌리면 된다.

## Task 7 — 루트 게이트 (약 50분, `run_in_background`)

```bash
s=$(date +%s)
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/ds2-gate.log 2>&1
echo "exit=$? secs=$(( $(date +%s) - s ))"
grep -c '^FAIL' /tmp/ds2-gate.log; tail -5 /tmp/ds2-gate.log
```

기대: exit 0, `FAIL` 0줄, 16체인 × 3.

## Task 8 — 닫기

- [ ] Step 1: design에 "DS-M2가 실행으로 증명한 것"(실측 11부터 — 두 체인 · 반사실 둘 ·
  루트 게이트)을 적고, M2-E의 한계를 적고, `Status:`를 "끝났다(2026-09-27) — M0~M2"로.
- [ ] Step 2: `HANDOFF.md`의 맨 위 절을 갈아 끼운다 — DS가 닫혔다 · 다음은 새 서브프로젝트
  (남은 후보: 패키지 매니저 · IPv6).
- [ ] Step 3: 커밋 둘

```bash
git add net/check.sh service/check.sh
git commit -m "Gate DS: a killed dhcpcd comes back, chronyd restarts, no fd leaks"
git add docs/ CLAUDE.md MEMORY.md HANDOFF.md
git status --short
git commit -m "Close DS-M2: daemon supervision, root gate 3/3"
```
