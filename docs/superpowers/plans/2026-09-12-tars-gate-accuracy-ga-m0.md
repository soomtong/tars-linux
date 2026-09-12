# GA-M0 Implementation Plan — 게이트가 거짓을 말하는 일곱 자리를 없앤다

Design: `docs/superpowers/specs/2026-09-12-tars-gate-accuracy-design.md`
Date: 2026-09-12

## 이 milestone이 하는 일

`machine/check.sh`의 넷과 `config/check.sh`의 셋에서 `-q`를 뺀다. 그리고 두
체인을 단독으로 돌려 판정이 그대로인 것을 본다.

편집은 일곱 줄이고 글자로는 열넷이다. 그런데 이 milestone의 값은 편집이
아니라 판정에 있다 — 고치기 전에도 두 체인이 초록이었으므로(design 실측
3·5) "초록이 됐다"가 증명이 아니다.

## 이 milestone을 지배하는 사실 둘

### 1. 초록은 증명이 아니다

`config/check.sh:915·918`은 현재 로그 크기(앞단 5,710바이트)에서 200/200
초록이고, `machine`의 넷은 앞단이 71~267바이트라 구조적으로 안전하다.
그러니 체인을 돌려 초록을 보는 것은 "안 망가뜨렸다"까지만 말한다.

실제 증명은 design 실측 4가 이미 했다 — 시리얼 콘솔이 fish로 뜬 상황을
합성해서, 지금 코드가 200/200 통과라고 말하고 `-q`를 뺀 코드가 200/200
실패라고 말하는 것을 보았다. 이 Task들은 그 처방을 저장소에 넣는 일이다.

### 2. 판정이 바뀌면 그것이 수확이다

일곱을 고친 뒤 어떤 검사가 빨개지면, 그것은 `-q` 때문에 조용히 통과하던
실패가 드러난 것이다. 그 자리에서 멈추고 무엇이 실제로 틀렸는지 본다
(design 위험 1).

## Task 1: `machine/check.sh` — 네 자리

### 넣을 것 (1/4) — 226

지울 것:

```bash
if ! grep -a "_OSC: OS supports" "$LOG" | grep -aq "MSI"; then
```

넣을 것 — 앞에 주석 넷이 함께 들어간다. 이 파일에서 같은 모양 넷 중 첫
자리이므로 이유가 여기 있고, 나머지 셋은 이 자리를 가리킨다.

```bash
# ⚠ 파이프 뒤의 `grep`에 `-q`를 쓰지 않는다(GA-M0). `-q`는 첫 매치에서
# 즉시 나가고, 아직 출력을 쓰고 있던 앞단이 SIGPIPE로 죽는다. 이 파일 맨
# 위의 `pipefail`이 그 141을 파이프라인 종료 코드로 올리고 `if !`는 그것을
# "안 맞았다"로 읽는다 — 판정 글자가 로그에 멀쩡히 있는데 빨갛다.
#
# 이 파일의 네 자리는 앞단이 부팅당 한두 줄만 내므로 지금은 안 터진다
# (GA design 실측 5). 그래도 고친 이유는 앞단의 패턴이 자라기 때문이다 —
# SC-M0이 `tars-init: config …` 한 줄에 필드를 붙였을 때 hangul 체인이
# 그 줄 끝에 매달려 깨졌고, 같은 변경이 아래 288의 앞단을 넓힌다.
# 아래 셋도 같은 이유로 `-q`가 없다.
if ! grep -a "_OSC: OS supports" "$LOG" | grep -a "MSI" >/dev/null; then
```

### 넣을 것 (2/4) — 241

지울 것:

```bash
if ! grep -a "tars-init: keyboard device" "$LOG" | grep -aq "USB Keyboard"; then
```

넣을 것:

```bash
if ! grep -a "tars-init: keyboard device" "$LOG" | grep -a "USB Keyboard" >/dev/null; then
```

### 넣을 것 (3/4) — 288

지울 것:

```bash
if ! grep -a "tars-init: config " "$LOG" | grep -aq "hangul=sebeol_3p3"; then
```

넣을 것:

```bash
if ! grep -a "tars-init: config " "$LOG" | grep -a "hangul=sebeol_3p3" >/dev/null; then
```

### 넣을 것 (4/4) — 354

지울 것:

```bash
if ! grep -a "terminal: screen>" "$LOG" | tail -20 | grep -aq "usb"; then
```

넣을 것:

```bash
if ! grep -a "terminal: screen>" "$LOG" | tail -20 | grep -a "usb" >/dev/null; then
```

`tail -20`은 그대로 둔다. `tail`은 입력을 끝까지 읽으므로 앞단을 죽이지
않고, 이 자리가 넷 중 가장 안전했던 이유가 그것이다(실측 5).

## Task 2: `config/check.sh` — 세 자리

### 넣을 것 (1/3) — 894, 거짓 초록 쪽

지울 것:

```bash
if grep "Welcome to fish, the friendly interactive shell" "$LOG2" | grep -qv "terminal: screen>"; then
```

넣을 것 — 이 자리의 주석이 가장 길다. 일곱 중 유일하게 거짓 초록이고,
왜 평시 관측으로 못 잡히는지가 여기 있어야 한다.

```bash
# ⚠ 여기가 일곱 중 가장 나빴던 자리다(GA-M0). `!`가 없는 형이라 SIGPIPE의
# 141이 "안 맞았다"가 되고 `if`가 거짓이 되어 조용히 통과한다 — 거짓 빨강이
# 아니라 거짓 초록이다.
#
# 평시에는 앞단 출력이 0줄이다. 2차 부팅은 두 셸이 다 zsh라 fish 인사말이
# 아예 없다. 그래서 "앞단이 작아서 안전하다"로 읽히는데, 이 검사가 관심
# 있는 상황은 평시가 아니다 — 시리얼 콘솔이 정말 fish로 떴다면 화면 셸도
# fish이므로 인사말이 screen> 프레임마다 붙어 앞단이 커진다.
#
# 그 상황을 합성해서 200회씩 쟀다(GA design 실측 4). 화면 인사말이 1,000줄
# 이면 앞단이 97,054바이트이고, `-q`를 쓴 코드는 200회 중 200회 통과라고
# 말했다. `-q`를 뺀 코드는 같은 상황에서 200/200 실패를 말한다.
#
# 검사가 망가지는 조건이 검사가 필요한 조건과 같다 — 그래서 이 병은
# 평시 관측으로 영영 안 드러난다.
if grep "Welcome to fish, the friendly interactive shell" "$LOG2" | grep -v "terminal: screen>" >/dev/null; then
```

### 넣을 것 (2/3) — 915

지울 것:

```bash
if ! grep "tars-rc-alive" "$LOG2" | grep -qv "terminal: screen>"; then
```

넣을 것:

```bash
if ! grep "tars-rc-alive" "$LOG2" | grep -v "terminal: screen>" >/dev/null; then
```

### 넣을 것 (3/3) — 918

지울 것:

```bash
if ! grep -a "terminal: screen>" "$LOG2" | grep -q "tars-rc-alive"; then
```

넣을 것 — 앞에 주석 둘이 함께 들어간다. 이 둘이 일곱 중 앞단이 가장
크게 자라는 자리라 숫자를 적어 둔다.

```bash
# 위 둘이 이 파일에서 앞단이 자라는 자리다(GA-M0). 918의 앞단은 screen>
# 줄 전체이고 매 프레임 47줄이 다시 찍히며, 915의 앞단도 tars-rc-alive가
# 화면에 떠 있는 동안 프레임마다 한 줄씩 늘어난다. 2026-09-12에 쟀을 때
# 둘 다 5.7KB라 200/200 초록이었지만, 네 배면 915는 200회 중 160회,
# 918은 63회 빨개진다(GA design 실측 1).
if ! grep -a "terminal: screen>" "$LOG2" | grep -a "tars-rc-alive" >/dev/null; then
```

## Task 3: 편집을 센다

매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 따로 센다. 이
milestone은 순수 추가가 아니다 — 일곱 줄을 고치고 주석 셋을 더하므로
지운 줄이 정확히 7이어야 하고, 그 일곱이 무엇인지 `git diff | grep '^-'`로
직접 읽는다.

그리고 판정 자리의 글자가 하나도 안 바뀐 것을 따로 본다. 이 편집이
건드려야 하는 것은 `-q`와 `>/dev/null`뿐이고, 찾는 문자열이 바뀌면
검사가 다른 것을 보게 된다.

```bash
git diff -U0 config/check.sh machine/check.sh | grep -E '^[-+]if' 
```

## Task 4: 두 체인을 단독으로 돌려 판정한다

`config`가 부팅 여덟이고 `machine`이 OVMF라 둘 다 background로 돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash config/check.sh  > /tmp/c.out 2>&1; echo "config exit=$?"; tail -5 /tmp/c.out
  bash machine/check.sh > /tmp/m.out 2>&1; echo "machine exit=$?"; tail -5 /tmp/m.out
'
```

기대는 둘 다 `exit=0`이고 `PASS`다. 빨개지면 사실 2에 따라 멈춘다.

## Task 5: 일곱 자리가 남지 않은 것을 확인한다

design 실측 6의 넓은 패턴으로 다시 훑어, 남는 매치가 주석뿐인 것을 본다.

```bash
rg '\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q' --glob '*.sh' -n . | grep -v ':[0-9]*:#'
```

기대는 출력이 0줄이다. 이 확인이 GA-M1의 lint가 할 일을 손으로 한 번 미리
해 보는 것이기도 하다.
