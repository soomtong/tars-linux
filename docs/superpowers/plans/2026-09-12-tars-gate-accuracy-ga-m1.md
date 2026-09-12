# GA-M1 Implementation Plan — 네 번째가 없도록 게이트가 스스로 막는다

Design: `docs/superpowers/specs/2026-09-12-tars-gate-accuracy-design.md`
Date: 2026-09-12

## 이 milestone이 하는 일

`check.sh`의 진입 검사에 함수 하나를 더해, 파이프 뒤에서 조기 종료하는
`grep`이 들어오면 첫 부팅 전에 게이트를 세운다.

GA-M0이 일곱을 고쳤지만 그것만으로는 네 번째가 막히지 않는다. 이 저장소는
같은 함정에 세 번 걸렸고, 세 번 모두 사람이 나중에 찾았다 — 주석으로
경고를 다섯 군데 적어 두었는데도 SM-M0이 그 경고를 쓴 파일 안에서 다시
밟았다. `tools/check.sh`의 주석이 그것을 이렇게 적었다.

> 이 파일이 자기 함정에 걸린 것이다. … 아는 것과 안 밟는 것이 다르다는
> 자리다.

그래서 아는 것을 주석이 아니라 실행에 옮긴다.

## 이 milestone을 지배하는 사실 셋

### 1. 줄 번호를 살리려면 `grep -n`을 먼저 걸어야 한다

`require_build_steps`는 주석을 먼저 지우고(`grep -vE '^[[:space:]]*#'`) 본문을
본다. 그 순서가 가능했던 이유는 줄 번호를 안 쓰기 때문이다 — 빌드 스텝이
없다는 것만 말하면 되고 몇 번째 줄인지는 의미가 없다.

이 검사는 고칠 자리를 가리켜야 한다. 주석을 먼저 지우면 번호가 원본과
어긋나므로 순서를 뒤집는다. `grep -n`으로 번호를 붙인 뒤, `번호:공백*#` 꼴을
걸러 주석 줄을 뺀다.

### 2. 주석이 이 패턴을 여덟 군데 설명하고 있다

GA design 실측 6이 센 것이다. `gate_lib.sh` 하나 · `tools/check.sh` 다섯 ·
`input/check.sh` 하나 · `render/check.sh` 하나. 여덟 전부 줄머리가 `#`라
사실 1의 필터에 걸러진다. 이것을 확인하지 않고 lint를 넣으면 게이트가
시작조차 안 된다(design 위험 3).

### 3. 이 검사가 자기 자신을 잡을 수 있다

lint 대상에 `check.sh`를 넣으면, 그 안의 패턴 문자열이 자기 패턴에 매치될
수 있다. 현재 패턴은 매치되지 않는다 — 문자열 안에 `\b(grep|rg)\b` 뒤로
`-`와 `q`가 연달아 오는 자리가 없다. 실행으로 확인한다.

그래도 `check.sh`를 대상에서 빼지 않는다. 넣어 두면 미래에 패턴을 고쳐
자기를 잡는 순간 게이트가 즉시 빨개져서 드러나고, 빼 두면 `check.sh`에
새로 들어오는 파이프라인을 아무도 안 본다. 조용한 쪽보다 시끄러운 쪽이
낫다는 것이 이 서브프로젝트 전체의 주제다.

## Task 1: `check.sh` — 패턴과 함수

`BUILD_STEPS`/`require_build_steps` 바로 아래에 넣는다. 같은 성질의 검사
둘이 나란히 있는 것이 읽는 사람에게 맞다.

넣을 것:

```bash
# GA-M1: 파이프 뒤에서 조기 종료하는 grep을 막는다.
#
# `grep -q`는 첫 매치에서 즉시 나가고, 아직 출력을 쓰고 있던 앞단이
# SIGPIPE로 죽는다. 체인들이 맨 위에 `set -uo pipefail`을 두므로 그 141이
# 파이프라인 전체의 종료 코드가 되고, `if`가 그것을 "안 맞았다"로 읽는다.
# `!`가 붙은 형은 거짓 빨강이 되고 안 붙은 형은 거짓 초록이 된다.
#
# 이 저장소가 같은 함정에 세 번 걸렸다 — tools/check.sh(SM-M0) ·
# hangul/check.sh(SM-M2) · 그리고 GA-M0이 고친 일곱. 세 번 다 주석으로
# 경고를 적어 둔 뒤에 다시 밟았다. 그래서 주석이 아니라 실행으로 막는다.
#
# 패턴을 좁게 쓰면 못 찾는다. SM-M0이 쓴 `\| *grep -[a-z]*q`는 플래그 끝이
# `q`인 것만 찾아 `-aqE` 한 자리를 놓쳤고, 그 한 자리가 2026-09-12의 루트
# 게이트를 빨갛게 만들었다. 그래서 `q`가 플래그 가운데 있어도 잡는다.
#
# `tail`은 대상이 아니다 — 입력을 끝까지 읽으므로 앞단을 죽이지 않는다.
# `head`와 `grep -m N`도 같은 병을 만들지만 이 저장소에 쓰인 자리가 없어
# 범위에 안 넣었다(GA design 결정 3).
EARLY_EXIT_PIPE='\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q'

require_no_early_exit_pipe() {
  local script="$1"
  local hits

  # `grep -n`을 먼저 걸고 주석을 나중에 거른다. 순서를 뒤집으면 번호가
  # 원본과 어긋나서 고칠 자리를 못 가리킨다 — require_build_steps가 반대
  # 순서여도 괜찮았던 것은 그 검사가 번호를 안 쓰기 때문이다.
  #
  # 매치가 0이거나 전부 주석이면 이 파이프라인이 0이 아닌 코드로 끝나고,
  # 그것이 "위반 없음"의 정상 경로다. 뒤단에 `-q`가 없으므로 이 줄 자신은
  # 이 검사가 막는 모양이 아니다.
  hits="$(grep -nE "$EARLY_EXIT_PIPE" "$script" | grep -vE '^[0-9]+:[[:space:]]*#')" \
    || return 0

  echo "check FAIL: ${script} pipes into a grep that exits early:" >&2
  echo "$hits" >&2
  echo "  SIGPIPE kills the upstream and pipefail turns 141 into a false verdict." >&2
  echo "  drop the -q and redirect the output to /dev/null instead (GA-M0)." >&2
  return 1
}
```

## Task 2: `check.sh` — 진입 루프와 실패 문구

지울 것:

```bash
entry_failed=0
for entry in "${CHAINS[@]}"; do
  require_build_steps "${entry#*:}" || entry_failed=1
done
if [ "$entry_failed" -ne 0 ]; then
  echo "TARS check FAIL: a chain would have run without building what it boots" >&2
  exit 1
fi
```

넣을 것:

```bash
entry_failed=0
for entry in "${CHAINS[@]}"; do
  require_build_steps "${entry#*:}" || entry_failed=1
  require_no_early_exit_pipe "${entry#*:}" || entry_failed=1
done

# 체인이 source하는 공용 파일과 이 파일 자신도 같은 규칙을 받는다.
# 자기를 넣는 이유는 GA-M1 plan 사실 3에 있다.
for extra in ./gate_lib.sh ./check.sh; do
  require_no_early_exit_pipe "$extra" || entry_failed=1
done

if [ "$entry_failed" -ne 0 ]; then
  echo "TARS check FAIL: the entry checks found something that would make a run lie" >&2
  exit 1
fi
```

실패 문구를 바꾼 이유는 출구가 이제 둘을 덮기 때문이다. 빌드 스텝을
빠뜨린 체인은 남이 만들어 둔 산출물로 거짓 초록이 되고, 조기 종료 파이프는
거짓 판정이 된다 — 둘 다 "게이트가 거짓을 말한다"의 한 종류다.

## Task 3: 양성 확인 — 지금 저장소가 통과한다

진입 검사만 돌려 본다. 부팅 없이 몇 초다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash -n check.sh && echo "syntax OK"
  sed -n "/^clean$/q;p" check.sh > /tmp/entry.sh
  bash /tmp/entry.sh && echo "entry checks PASS"
'
```

`clean` 호출 앞까지 잘라내 진입 검사만 돌린다. 이렇게 하면 커널 빌드도
부팅도 안 하므로 lint의 거짓 양성을 몇 초 안에 본다.

## Task 4: 음성 확인 — 일부러 심고 잡히는 것을 본다

이 검사 자신이 아무것도 안 보는 검사가 되는 것을 막는 유일한 방법이다.
SP-M0이 *"한 색만 세는 음성 검사를 그대로 두기"*로 적어 둔 함정의 같은
종류이고, 안 고쳐도 초록이라 조용히 지나간다.

저장소 파일을 건드리지 않고 `/tmp`의 사본에 심는다. 세 모양을 각각 본다 —
`-q` · `-aq`(플래그 끝) · `-aqE`(플래그 가운데, SM-M0의 패턴이 놓친 모양).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  sed -n "/^clean$/q;p" check.sh > /tmp/entry.sh
  for form in "grep -q X" "grep -aq X" "grep -aqE X"; do
    cp config/check.sh /tmp/bait.sh
    echo "echo hi | ${form}" >> /tmp/bait.sh
    sed "s#\./config/check.sh#/tmp/bait.sh#" /tmp/entry.sh > /tmp/entry_bait.sh
    if bash /tmp/entry_bait.sh >/tmp/bait.out 2>&1; then
      echo "NEGATIVE TEST FAILED: [${form}] slipped through"
    else
      echo "caught [${form}]:"; grep -a "bait.sh" /tmp/bait.out | head -2
    fi
  done
'
```

기대는 셋 다 `caught`이고, 각각 심은 줄의 번호를 가리키는 것이다.

## Task 5: 루트 게이트 3/3

약 28분이라 `run_in_background`로 돌린다. 이 변경은 빌드도 부팅도 하나
안 더하므로 기준선 27분 35.11초에서 잡음(±3분) 안이어야 한다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

판정은 `TARS check PASS`와 FAIL 0이다. 그리고 진입 검사가 실제로 돌았는지를
로그 맨 앞에서 확인한다 — 통과하면 아무 말도 안 하는 검사이므로, 돌았다는
증거는 "게이트가 첫 부팅으로 넘어갔다"는 것뿐이다.
