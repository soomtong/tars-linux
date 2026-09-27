# CT-M2 — `service/check.sh`의 부팅 D · 반사실 · 가이드

> 이 plan을 실행하는 사람에게: 코드는 Claude Code가 넣는다. 매 편집 뒤 `git diff
> --stat`, 지우는 편집은 `git diff | grep '^-'`. 반사실은 커밋하지 않는다 — 고치고,
> 체인을 돌리고, 되돌리고, `git diff`가 비었는지 본다.

Goal: CT-M1이 눈으로 본 판정(design 실측 9)을 게이트로 옮긴다. `service/check.sh`에 부팅
D를 더하고, 결정 4의 규칙과 위험 2를 겨냥한 반사실 넷이 각각 겨냥한 검사에서 빨개지는
것을 보고, 사람이 읽는 가이드를 쓰고, 루트 게이트 3/3으로 CT를 닫는다.

Architecture: 부팅 D는 부팅 C가 쓴 디스크(키 · `ssh.nft`가 있다)에 서비스 셋을 더해
뜬다. 게스트에 치는 명령은 전부 ssh `ControlMaster` 연결 하나 위로 간다. 그 연결은 제
세션을 가진 `sshd-session`이 들고 있어 sshd를 멈춰도 산다(CT-M0 실측 4) — `stop sshd`
뒤에 새 ssh가 거절되는 것(멈춤의 증거)과 같은 연결로 `start sshd`를 치는 것을 한
부팅에서 본다. 판정은 `tars-service`의 종료 코드 · 출력과 시리얼 로그다.

Tech Stack: bash · `ssh -o ControlMaster` · `debugfs` · QEMU

---

## 부팅 D의 디스크

부팅 C 뒤의 `$SSH_DISK`(`net=dhcp` · `shell=zsh` · `firewall=on` · `ssh.nft` · 호스트 키 ·
`services.d/sshd`)에 셋을 더한다.

| 서비스 | 모양 | 무엇을 보려고 |
|---|---|---|
| `sleeper` | `exec` 없이 `sleep`을 자식으로 둔다 | 그룹에 보내야 고아가 안 남는다(CT-M0 실측 5) |
| `stubborn` | `trap '' TERM` | 유예 뒤 SIGKILL(실측 5) |
| `flaky` | `/run/flaky-ok`가 없으면 `exit 3` | 포기된 뒤 `start`로 되살린다 |

## 검사 (16~26)

| # | 무엇 | 반사실이 겨냥하는가 |
|---|---|---|
| 16 | `tars-init: control socket /run/tars/init.sock` | |
| 17 | `status`가 여섯 줄 — terminal · console shell · 서비스 넷, `flaky`는 `given up` | |
| 18 | `stop sleeper` rc 0 · `stopped` · ppid 1인 `sleep`이 0 · `stopped on request` | CF2 · CF3 |
| 19 | 3초 뒤에도 `stopped`이고 `started service sleeper`가 한 번뿐 | CF2 |
| 20 | `start sleeper` rc 0 · `running` | |
| 21 | `restart sshd` 넷이 전부 rc 0 · pid가 매번 다르다 · `giving up on service sshd`가 없다 | CF1 |
| 22 | `stop sshd` 뒤 새 ssh가 255 · 같은 연결로 `start sshd` · 새 ssh가 0 | |
| 23 | `stop stubborn` rc 0 · `outlived SIGTERM by 3s, sent SIGKILL to group` | |
| 24 | `/run/flaky-ok`를 만들고 `start flaky` rc 0 · `running` | |
| 25 | 음성 다섯 — `nope` · `terminal` · `'a b'` · 70바이트 이름 · `bogus` | |
| 26 | `sleeper`의 `sleep`이 든 fd에 `socket:`이 없다 | CF4 |

반사실 넷(커밋 안 함):

- CF1 `control.reaped`가 늘 `.normal` — 규칙 2를 뺀다. 기대: 21.
- CF2 `control.wantsRunning`에서 `c.hold != .stop`을 뺀다 — 규칙 1을 뺀다. 기대: 18(`stopped`에
  못 닿아 rc 3).
- CF3 `main.zig`의 `answer`에서 `kill(-pid, .TERM)`을 `kill(pid, .TERM)`으로. 기대: 18의 고아.
- CF4 `control.open`의 `SOCK.CLOEXEC`를 뺀다. 기대: 26.

## Task 1 — 부팅 D를 쓴다

- [ ] Step 1: 체인 머리 주석에 부팅 D를 더한다

`service/check.sh`의 머리 주석, "세션이 콘솔과 같은 것을 본다." 줄 뒤에:

```bash
#
# 부팅 D(CT-M2)는 C 뒤의 같은 디스크에 서비스 셋(sleeper · stubborn · flaky)을 더해
# 뜨고, ssh ControlMaster 연결 하나 위로 tars-service를 친다. 그 연결은 제 세션을 가진
# sshd-session이 들고 있어 sshd를 멈춰도 산다(CT-M0 실측 4) — stop sshd 뒤에 같은
# 연결로 start sshd를 친다.
```

그리고 "우리 코드는 …" 줄을:

```bash
# 우리 코드는 init/src/services.zig(고르기) · main.zig의 감독 루프(띄우기)와
# init/src/control.zig · service_cli.zig(멈추고 다시 띄우기)다.
```

- [ ] Step 2: 부팅 D의 본문

`stop_ssh`(부팅 C 끝) 뒤, `rm -f "$B_LOG"` 앞에:

```bash

# ── 부팅 D: tars-service (CT-M2) ─────────────────────────────────────
MONITOR_PORT_D=45486
DSEED="$(mktemp -d)"
cat > "$DSEED/sleeper" <<'EOF'
#!/bin/sh
# exec 없이 sleep을 자식으로 둔다. 리더에게만 보내면 sleep이 고아로 남는다(CT-M0 실측 5).
sleep 100000
EOF
cat > "$DSEED/stubborn" <<'EOF'
#!/bin/sh
# SIGTERM을 무시한다. 무시는 exec를 넘어 sleep에도 간다.
trap '' TERM
while :; do sleep 1; done
EOF
cat > "$DSEED/flaky" <<'EOF'
#!/bin/sh
# 표지 파일이 없으면 곧바로 죽는다 — 셋 뜨고 포기된다. 사람이 만든 뒤 start하면 산다.
[ -e /run/flaky-ok ] || exit 3
exec sleep 100000
EOF
chmod 755 "$DSEED/sleeper" "$DSEED/stubborn" "$DSEED/flaky"
for s in sleeper stubborn flaky; do sdbg "write $DSEED/$s services.d/$s"; done
rm -rf "$DSEED"

echo "=== boot D: the same disk plus sleeper, stubborn and flaky; tars-service over ssh ==="
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_D"
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 || fail "sshd never listened" "sshd:"

CTL="$KEYS/ctl"
ssh "${SSHO[@]}" -i "$KEYS/good" -o ControlMaster=yes -o ControlPath="$CTL" -o ControlPersist=yes \
  -fN root@127.0.0.1 || fail "could not open the ssh control connection" "sshd"
# 연결 위로 tars-service를 친다. 출력은 OUT, 종료 코드는 RC. 인자는 원격 셸이 가른다 —
# 공백 든 이름은 따옴표째 넘긴다.
ts() {
  OUT="$(ssh "${SSHO[@]}" -o ControlPath="$CTL" root@127.0.0.1 "tars-service $*" 2>&1)"
  RC=$?
}
on_guest() { ssh "${SSHO[@]}" -o ControlPath="$CTL" root@127.0.0.1 "$@" 2>/dev/null; }
fresh_ssh() { ssh "${SSHO[@]}" -i "$KEYS/good" -o ControlPath=none root@127.0.0.1 true >/dev/null 2>&1; }
# 마지막 줄(클라이언트가 기다린 끝의 status 한 줄)의 pid.
last_pid() { tail -1 <<<"$OUT" | sed -nE 's/.* pid ([0-9]+).*/\1/p'; }

# ── 검사 16: 통로가 섰다 ─────────────────────────────────────────────────
grep -a "tars-init: control socket /run/tars/init.sock" "$LOG" >/dev/null \
  || fail "init did not open the control socket" "control"
echo "init opened /run/tars/init.sock"

# ── 검사 17: status가 전부를 보인다 ──────────────────────────────────────
wait_for_log "tars-init: giving up on service flaky after 3 fast exits" 30 \
  || fail "flaky was never given up on" "flaky"
ts status
[ "$RC" = "0" ] || fail "status gave rc ${RC} (${OUT})"
for want in '^terminal +running +pid [0-9]+' '^console shell +running +pid [0-9]+' \
            '^service flaky +given up$' '^service sleeper +running +pid [0-9]+' \
            '^service sshd +running +pid [0-9]+' '^service stubborn +running +pid [0-9]+'; do
  grep -qE "$want" <<<"$OUT" || fail "status has no line like /${want}/ (got: [${OUT}])"
done
echo "status showed the terminal, the console shell and four services, flaky given up"

# ── 검사 18: stop이 그룹을 멈춘다 ────────────────────────────────────────
ts stop sleeper
[ "$RC" = "0" ] || fail "stop sleeper gave rc ${RC} (${OUT})" "sleeper"
tail -1 <<<"$OUT" | grep -qE '^service sleeper +stopped$' || fail "stop sleeper did not end stopped (${OUT})"
ORPHANS="$(on_guest 'ps -eo ppid=,comm=' | grep -cE '^ *1 sleep$')"
[ "$ORPHANS" = "0" ] || fail "stop sleeper left ${ORPHANS} sleep under pid 1" "sleeper"
grep -a "tars-init: service sleeper stopped on request" "$LOG" >/dev/null \
  || fail "init did not log the stop" "sleeper"
echo "stop sleeper ended stopped and took its child sleep with it"

# ── 검사 19: 멈춘 것은 되살아나지 않는다 ───────────────────────────────────
sleep 3
ts status sleeper
grep -qE '^service sleeper +stopped$' <<<"$OUT" || fail "sleeper did not stay stopped (${OUT})" "sleeper"
N="$(grep -ac "tars-init: started service sleeper " "$LOG")"
[ "$N" = "1" ] || fail "sleeper started ${N} times, want 1" "sleeper"
echo "sleeper stayed stopped"

# ── 검사 20: start가 다시 띄운다 ────────────────────────────────────────
ts start sleeper
[ "$RC" = "0" ] || fail "start sleeper gave rc ${RC} (${OUT})" "sleeper"
tail -1 <<<"$OUT" | grep -qE '^service sleeper +running +pid [0-9]+$' || fail "start sleeper did not end running (${OUT})"
echo "start sleeper brought it back"

# ── 검사 21: restart는 빨리 죽음으로 세지 않는다 ──────────────────────────
# 넷이다 — 셋이면 세는 쪽으로 틀려도 포기 직전에서 멈춘다(CT-M0 실측 6).
PREV=""
for i in 1 2 3 4; do
  ts restart sshd
  [ "$RC" = "0" ] || fail "restart sshd #${i} gave rc ${RC} (${OUT})" "sshd"
  P="$(last_pid)"
  [ -n "$P" ] && [ "$P" != "$PREV" ] || fail "restart sshd #${i} did not change the pid (${OUT})" "sshd"
  PREV="$P"
done
if grep -a "tars-init: giving up on service sshd" "$LOG" >/dev/null; then
  fail "four restarts made init give up on sshd" "sshd"
fi
N="$(grep -ac "tars-init: restarting service sshd on request" "$LOG")"
[ "$N" = "4" ] || fail "init logged ${N} requested restarts of sshd, want 4" "sshd"
echo "four restarts of sshd, four new pids, no giving up"

# ── 검사 22: sshd를 멈추면 새 ssh가 거절되고, 열어 둔 연결로 되살린다 ─────────
ts stop sshd
[ "$RC" = "0" ] || fail "stop sshd gave rc ${RC} (${OUT})" "sshd"
fresh_ssh && fail "a new ssh got in while sshd was stopped"
ts start sshd
[ "$RC" = "0" ] || fail "start sshd over the kept connection gave rc ${RC} (${OUT})" "sshd"
ok=0
for _ in $(seq 1 10); do
  if fresh_ssh; then ok=1; break; fi
  sleep 0.5
done
[ "$ok" = "1" ] || fail "a new ssh did not get in after start sshd" "sshd"
echo "stop sshd shut new logins out, the kept connection started it again"

# ── 검사 23: SIGTERM을 무시하면 유예 뒤 SIGKILL ───────────────────────────
ts stop stubborn
[ "$RC" = "0" ] || fail "stop stubborn gave rc ${RC} (${OUT})" "stubborn"
tail -1 <<<"$OUT" | grep -qE '^service stubborn +stopped$' || fail "stop stubborn did not end stopped (${OUT})"
grep -aE "tars-init: service stubborn outlived SIGTERM by 3s, sent SIGKILL to group [0-9]+" "$LOG" >/dev/null \
  || fail "init did not send SIGKILL to stubborn" "stubborn"
echo "stubborn ignored SIGTERM and was stopped by SIGKILL"

# ── 검사 24: 포기된 것도 start로 되살린다 ─────────────────────────────────
on_guest 'touch /run/flaky-ok'
ts start flaky
[ "$RC" = "0" ] || fail "start flaky gave rc ${RC} (${OUT})" "flaky"
tail -1 <<<"$OUT" | grep -qE '^service flaky +running +pid [0-9]+$' || fail "start flaky did not end running (${OUT})"
echo "start flaky revived a given-up service"

# ── 검사 25: 거절 다섯 ─────────────────────────────────────────────────
LONG="$(printf 'x%.0s' $(seq 1 70))"
expect_refused() {  # $1 = 인자, $2 = 원하는 rc, $3 = 원하는 첫 줄
  ts "$1"
  [ "$RC" = "$2" ] || fail "tars-service $1 gave rc ${RC}, want $2 (${OUT})"
  [ "$(head -1 <<<"$OUT")" = "$3" ] || fail "tars-service $1 said [$(head -1 <<<"$OUT")], want [$3]"
}
expect_refused "stop nope" 1 "error: no service named nope"
expect_refused "stop terminal" 1 "error: no service named terminal"
expect_refused "stop 'a b'" 1 "error: bad request"
expect_refused "stop ${LONG}" 1 "error: request of 75 bytes, at most 64"
expect_refused "bogus" 64 "usage: tars-service status [NAME]"
echo "unknown names, the terminal, a bad request, a long request and bad usage were refused"

# ── 검사 26: 통로의 fd가 서비스로 새지 않는다 ──────────────────────────────
FDS="$(on_guest 'ls -l /proc/$(pgrep -x sleep -P $(pgrep -x sleeper))/fd')"
[ -n "$FDS" ] || fail "could not list the fds of sleeper's sleep"
grep -q "socket:" <<<"$FDS" && fail "sleeper's sleep holds a socket (${FDS})"
echo "sleeper's child holds no socket from init"

ssh -o ControlPath="$CTL" -O exit root@127.0.0.1 2>/dev/null || true
stop_ssh
rm -f "$LOG"
```

`fresh_ssh && fail …`은 `set -e`가 없는 체인이라 그대로 쓴다(ssh가 실패하면 `&&`가 넘어간다).

- [ ] Step 3: `check.sh`의 체인 설명과 이름표

`check.sh`의 SV 체인 설명 끝("총 부팅 횟수가 아홉 는다.")을:

```bash
# 본다. device 체인처럼 판정이 시리얼 로그와 바깥에서 붙은 TCP다. SV-M2가 sshd 부팅
# 둘을, CT-M2가 tars-service 부팅 하나를 더해 회차당 부팅 4회(합 3분 안팎)다 — 총
# 부팅 횟수가 열둘 는다.
```

(원래 두 줄 "본다. device 체인처럼 … 붙은 TCP 한 줄이다. SV-M2가 sshd 부팅 둘을 더해
회차당 부팅 3회(합 2분 / 안팎)다 — 총 부팅 횟수가 아홉 는다."를 바꾼다.) 그리고
`"SV-M2:./service/check.sh"`를 `"CT-M2:./service/check.sh"`로.

- [ ] Step 4: 체인을 돌린다 (약 3분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./service/check.sh > /tmp/ct/m2.log 2>&1; } 2> /tmp/ct/m2.time
echo "exit=$?"; grep -E "^(===|FAIL|SV chain)|^[a-z].*(showed|ended|stayed|brought|restarts|shut|stopped by|revived|refused|holds|opened)" /tmp/ct/m2.log; cat /tmp/ct/m2.time
```

기대: 부팅 넷, 검사 26까지 한 줄씩, `SV chain PASS`.

- [ ] Step 5: 커밋

```bash
git diff --stat
git diff | grep '^-' | grep -v '^---'
git add service/check.sh check.sh
git commit -m "Add boot D to the service chain: tars-service over a kept ssh connection"
```

## Task 2 — 반사실 넷 (각 약 3분)

각각: 고친다 → 체인을 돌린다 → `FAIL:` 줄과 그 검사 번호를 적는다 → `git checkout`으로
되돌린다 → `git diff --stat`이 빈 것을 본다.

```bash
cf() {  # $1 = 이름. 고친 뒤에 부른다
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./service/check.sh > /tmp/ct/$1.log 2>&1
  echo "$1 exit=$? $(grep -m1 '^FAIL:' /tmp/ct/$1.log)"
  git checkout -- init/src && git diff --stat
}
```

- [ ] CF1 — `control.zig`의 `reaped` 첫 줄 뒤에 `if (true) return .normal;`

```bash
sd -F '    c.kill_at = 0;
    return switch (c.hold) {' '    c.kill_at = 0;
    if (true) return .normal;
    return switch (c.hold) {' init/src/control.zig && git diff --stat && cf cf1
```

기대: 검사 21의 FAIL — 둘째 restart가 시한 초과(규칙 2가 없으면 `hold`가 `.restart`로
남아 둘째 요청이 SIGTERM을 안 보낸다)이거나 `giving up on service sshd`.

- [ ] CF2 — `wantsRunning`에서 `hold` 조건을 뺀다

```bash
sd -F 'return c.pid < 0 and !c.given_up and c.hold != .stop;' 'return c.pid < 0 and !c.given_up;' init/src/control.zig && git diff --stat && cf cf2
```

기대: 검사 18 — `stop sleeper did not end stopped`(rc 3).

- [ ] CF3 — 리더에게만 보낸다

```bash
sd -F 'if (done.signal) _ = linux.kill(-pid, .TERM);' 'if (done.signal) _ = linux.kill(pid, .TERM);' init/src/main.zig && git diff --stat && cf cf3
```

기대: 검사 18 — `stop sleeper left 1 sleep under pid 1`.

- [ ] CF4 — listen fd의 `CLOEXEC`를 뺀다

```bash
sd -F 'linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return noSocket("socket", e);' 'linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK, 0);
    if (failed(rc)) |e| return noSocket("socket", e);' init/src/control.zig && git diff --stat && cf cf4
```

기대: 검사 26 — `sleeper's sleep holds a socket`.

반사실이 겨냥한 검사보다 앞에서 죽으면(SV-M2 실측 18처럼) 그 사실과 까닭을 적는다.
겨냥한 검사를 못 밟은 것이지 반사실이 무효인 것은 아니다 — 앞의 검사가 같은 결함을
먼저 잡은 것인지를 본다.

## Task 3 — 가이드

`docs/guides/running-tars.md`의 "부팅 때 뜨는 서비스" 절의 표 뒤, "ssh로 붙기" 앞에:

````markdown
### 서비스를 멈추고 다시 띄우기

`tars-service`가 `init`에게 묻고 시킨다. 콘솔에서도 ssh에서도 같다.

```sh
tars-service status            # 전부 — terminal과 콘솔 셸까지
tars-service status sshd
tars-service stop sshd
tars-service start sshd
tars-service restart sshd
```

```
terminal        running   pid 35   up 14s
console shell   running   pid 36   up 14s
service sshd    running   pid 38   up 14s
service web     stopped
service broken  given up
```

- 멈춘 것은 이 부팅이 끝날 때까지 멈춰 있다. 다음 부팅은 `services.d` 그대로 다시
  띄운다 — 영영 끄려면 `services.d`에서 지운다.
- `stop`은 서비스의 프로세스 그룹 전체에 SIGTERM을 보내고, 3초 안에 안 죽으면
  SIGKILL을 보낸다. `exec` 없이 쓴 스크립트의 자식까지 함께 멈춘다.
- `start`는 포기된(`given up`) 서비스도 다시 띄운다. `restart`와 `stop`으로 죽은 것은
  "빨리 죽었다"로 세지 않는다.
- ssh로 붙어서 `stop sshd`를 쳐도 지금 세션은 안 끊긴다. 새 접속만 막힌다.
- terminal과 콘솔 셸은 보이기만 한다. 멈추면 명령을 칠 자리가 사라진다.
- 명령은 원하는 상태가 될 때까지 8초까지 기다린다. 종료 코드: 0 됐다 · 1 `init`이
  거절했다(`error: …`) · 2 `init`에 닿지 못했다 · 3 시간 안에 안 됐다 · 64 사용법.

부팅 로그에 남는 줄.

| 줄 | 뜻 |
|---|---|
| `tars-init: control: stop service sshd -> stopping` | 요청 하나와 그 결과 |
| `tars-init: service sshd stopped on request` | 사람이 멈춘 것이 거둬졌다 |
| `tars-init: restarting service sshd on request` | 사람이 다시 띄운 것 |
| `tars-init: service web outlived SIGTERM by 3s, sent SIGKILL to group 71` | SIGTERM을 무시했다 |
| `tars-init: no control socket (bind errno 98)` | 통로를 못 열었다. 부팅은 평소대로고 `tars-service`만 안 된다 |
````

그리고 그 절의 "죽으면 1초 뒤에 다시 띄우고 …" 문단 끝에 한 문장:

```markdown
멈추고 다시 띄우는 것은 아래 "서비스를 멈추고 다시 띄우기"에 있다.
```

커밋:

```bash
git add docs/guides/running-tars.md
git commit -m "Guide: stopping and starting services with tars-service"
```

## Task 4 — 루트 게이트 3/3 (약 55분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate.log 2>&1; } 2> /tmp/gate.time
echo "exit=$?"; grep -c '^FAIL' /tmp/gate.log; tail -3 /tmp/gate.log; cat /tmp/gate.time
```

기대: `CT-M2 PASS: 3/3 consecutive runs succeeded`, `FAIL` 0줄. 시간은 SV-M2의 49분 25초에
부팅 D 세 번(각 1분 안팎)이 더해진 52~53분 언저리. 크게 벗어나면 기계부터 의심한다
(`docs/guides/lessons.md`).

## Task 5 — 닫는다

- [ ] design: "CT-M2가 실행으로 증명한 것" 절(체인의 첫 판 · 반사실 넷 · 루트 게이트),
  `Status: 끝났다(2026-09-27) — M0~M2 …`.
- [ ] `docs/decisions/project_service_control.md` 새 기억 — 통로 · 규칙 · 그룹 · 예측과
  달랐던 것(12ms 멈춤 · `zig build test`의 끝줄). `MEMORY.md`에 한 줄.
- [ ] `CLAUDE.md`의 완료 표에 한 줄.
- [ ] `HANDOFF.md`의 맨 위 절을 갈아 끼운다.

```bash
git status --short
git diff --stat
git add docs/superpowers/specs/2026-09-27-tars-service-control-design.md \
        docs/superpowers/plans/2026-09-27-tars-service-control-ct-m2.md \
        docs/decisions/project_service_control.md MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Close CT-M2: tars-service in the service chain, root gate 3/3"
```
