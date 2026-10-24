# GF-M0 — 루트 게이트에서 initrd를 다시 만드는 쪽이 없다

Date: 2026-10-24
Design: `docs/specs/2026-10-24-tars-gate-flakes-design.md`
Status: 끝났다(2026-10-24). 값은 맨 아래 "GF-M0이 실측한 것".

## 누가 무엇을 하나

범위가 작아(편집 셋) lead가 직접 넣는다. 서브에이전트는 안 쓴다. 매 편집 뒤 `git diff --stat`, 지우는 편집은
`git diff | rg '^-'`로 본다.

| 파일 | 무엇을 |
|---|---|
| `kernel/make_initrd.sh` | 맨 앞의 건너뛰기(결정 1), `INITRD_OUT`(결정 3) |
| `check.sh` | prebuild 뒤 `export TARS_PREBUILT_INITRD=1`과 inode 적기, `run_chain`의 inode 대조(결정 2) |
| `tools/check.sh` | 검사 1d가 `TMPDIR` 아래 사본에 `INITRD_OUT`으로 만든다(결정 3) |

체인 스크립트 22개 가운데 tools 말고는 바뀌지 않는다.

## 착수 전에 확정한 것

1. `make_initrd.sh`는 `cd "$(dirname "$0")"` 뒤 `./vendor_firmware.sh`를 먼저 부르고 그 다음이 `WORKDIR` · `OUT`이다.
   건너뛰기는 `vendor_firmware.sh`보다 앞에 둔다 — 그 스크립트는 스탬프가 맞으면 곧바로 끝나지만 부를 이유가 없다.
2. `initrd.cpio`라는 글자가 코드로 쓰이는 자리는 둘이다 — 23줄 `OUT="$(mktemp initrd.cpio.XXXXXX)"`와 747줄 `mv -f "$OUT" initrd.cpio`.
   나머지는 주석이다. 둘을 `INITRD_OUT`으로 바꾼다.
3. `check.sh`는 `set -uo pipefail`이고 `run_chain`은 서브셸 `( run_chain … )`에서 돈다 — 그 안의 `exit 1`은 서브셸만 끝낸다.
   prebuild 뒤에 둔 `export`는 그 서브셸들과 체인 프로세스 전부에 상속된다.
4. inode는 `stat -c %i kernel/initrd.cpio`로 읽는다(컨테이너는 GNU coreutils). tools 1d가 같은 명령을 쓴다.
5. tools 1d의 지금 모양(`tools/check.sh` 299~321줄) — `exec 4< ../kernel/initrd.cpio`로 열어 두고 `make_initrd.sh`를 돌린 뒤
   (a) `stat -L -c %i /dev/fd/4` ≠ `stat -c %i ../kernel/initrd.cpio`, (b) `sha256sum <&4`가 전과 같다, (c) `ls initrd.cpio.*`가 빈다.

## Task 1: `kernel/make_initrd.sh`

`cd` 바로 뒤에 둔다.

```bash
# GF-M0 결정 3. 출력 경로. 기본은 공유 산출물 initrd.cpio이고, tools 검사 1d는 자기 사본을 준다.
INITRD_OUT="${INITRD_OUT:-initrd.cpio}"

# GF-M0 결정 1. 루트 게이트는 prebuild에서 한 번 만든 뒤 이 변수를 둔다. 그 뒤의 체인 22개가 저마다
# 다시 만들면 최대 JOBS개가 같은 파일을 동시에 rename하고, bind mount에서는 그 순간 open()이
# ENOENT를 받는다(BV-M0 루트 게이트 1회차의 PM). 사본을 달라는 호출(INITRD_OUT)은 건너뛰지 않는다.
if [ -n "${TARS_PREBUILT_INITRD:-}" ] && [ "$INITRD_OUT" = initrd.cpio ] && [ -f initrd.cpio ]; then
  echo "skipping initrd (prebuilt by the root gate)"
  exit 0
fi
```

23줄은 `OUT="$(mktemp "${INITRD_OUT}.XXXXXX")"`, 747줄은 `mv -f "$OUT" "$INITRD_OUT"`. 741~746줄 주석에 한 줄 — 경로는
`INITRD_OUT`이고 임시 파일은 그 옆에 만든다(rename은 같은 파일시스템이어야 한다).

## Task 2: `check.sh`

`time: prebuild` 줄 뒤에:

```bash
# GF-M0 결정 1 · 2. 여기부터 initrd는 읽기만 한다. 변수는 체인이 부르는 make_initrd.sh가 보고, inode는
# 회차마다 대조한다 — 글자는 건너뛰었다는 주장이고 inode는 안 썼다는 사실이다.
export TARS_PREBUILT_INITRD=1
INITRD_INODE="$(stat -c %i kernel/initrd.cpio)"
```

`run_chain`의 `count_cut_lines … || ok=0` 뒤에:

```bash
    check_initrd_inode "${name} run ${i}/${RUNS}" || ok=0
```

함수는 `count_cut_lines` 아래에:

```bash
# GF-M0 결정 2. 회차 뒤에도 kernel/initrd.cpio가 prebuild가 만든 그 파일인가. 다르면 누군가 다시
# 만들었다는 뜻이다(rename은 inode를 바꾼다).
check_initrd_inode() {
  local label="$1" now
  now="$(stat -c %i kernel/initrd.cpio)"
  if [ "$now" != "$INITRD_INODE" ]; then
    echo "${label} FAIL: kernel/initrd.cpio was rebuilt during the run (inode ${INITRD_INODE} -> ${now})"
    return 1
  fi
  return 0
}
```

`INITRD_INODE`는 `run_chain`이 서브셸에서 읽는 전역이다 — `export`하지 않아도 서브셸은 부모의 변수를 본다.

## Task 3: `tools/check.sh` 검사 1d

주석에 "루트 게이트에서는 다른 레인이 같은 파일을 읽는다 — 사본에 한다(GF-M0 결정 3)"를 더하고, 본문은:

```bash
INITRD_1D="$(mktemp -d)"
cp ../kernel/initrd.cpio "$INITRD_1D/initrd.cpio"
HELD_SHA_BEFORE="$(sha256sum "$INITRD_1D/initrd.cpio" | cut -d' ' -f1)"
exec 4< "$INITRD_1D/initrd.cpio"
if ! (cd ../kernel && INITRD_OUT="$INITRD_1D/initrd.cpio" ./make_initrd.sh) > /dev/null 2>&1; then
```

그 뒤의 `../kernel/initrd.cpio`는 전부 `"$INITRD_1D/initrd.cpio"`로, (c)는 `ls "$INITRD_1D"/initrd.cpio.*`로. 끝의 통과 메시지에
사본의 경로가 아니라 "on a private copy"를 더한다. 사본은 지우지 않는다 — `TMPDIR` 아래라 회차의 로그와 같은 수명이다.
`cp`가 bind mount에서 overlay(`/tmp`)로 98MB를 옮기는 비용은 실측 절에 적는다.

## Task 4: 검사와 게이트

1. `bash -n`과 `shellcheck -S warning`을 세 파일에.
2. 컨테이너에서 `cd kernel && ./make_initrd.sh`(변수 없음) — 예전처럼 만든다. 그 뒤
   `TARS_PREBUILT_INITRD=1 ./make_initrd.sh` — `skipping initrd` 한 줄, inode 그대로.
   `INITRD_OUT=/tmp/x/initrd.cpio TARS_PREBUILT_INITRD=1 ./make_initrd.sh` — 건너뛰지 않고 그 경로에 만든다.
3. tools 체인 하나(`./tools/check.sh`) — 1d의 새 줄.
4. 루트 게이트(22체인, 약 10분). `TARS check PASS`와 더불어 어느 회차에도 `was rebuilt during the run`이 없다.

## 끝 조건

- 루트 게이트 22/22. 22회차 모두 inode 대조 통과.
- `grep -c 'skipping initrd' <GATE_LOGS>/lane-*.out`의 합이 22다(결정 2의 검사가 본 것을 다른 길로 한 번 더 본다).
- tools 체인 로그에 1d의 통과 줄.

## 닫을 때(lead의 몫)

- design `Status:`의 M0 자리, lessons "이월 숙제" BV 항목.
- GF-M1 plan은 이 게이트가 도는 동안 쓴다.

## GF-M0이 실측한 것

| 항목 | 값 |
|---|---|
| `make_initrd.sh` 평소 빌드(컨테이너, 캐시 적중) | 5~6초 |
| `TARS_PREBUILT_INITRD=1`일 때 | `skipping initrd (prebuilt by the root gate)` 한 줄, inode 그대로 |
| `INITRD_OUT=/tmp/x/initrd.cpio`와 변수를 함께 줬을 때 | 건너뛰지 않고 그 경로에 98,251,056바이트, 공유 파일 inode 그대로, 옆에 임시 파일 없음. 파일 목록은 공유 파일과 같다 |
| `cp initrd.cpio`(bind mount → `/tmp`, 98MB) | 30ms |
| tools 체인 단독 | PASS, 1d `inode 17136107 -> 17136109 … (on a private copy)` |
| 루트 게이트 | 22/22. prebuild 246초, lanes 290초(GF 전 같은 날 322초), 22회차 합 1557초 |
| `skipping initrd` 줄 | 22(체인 수 × RUNS 그대로) |
| `was rebuilt during the run` 줄 | 0 — inode 대조가 22회차 전부 통과 |
| 끼어든 줄 A · B · 잘린 줄 C | 22회차 모두 0 |

구현 중 design과 달라진 자리는 없다. 함정 하나는 도구 쪽이었다 — perl `s|…|…|`의 구분자 `|`가 패턴 안의 `\|\|`(bash의 `||`)와
충돌해 빈 문자열에 맞고, 파일 머리에 치환문이 끼었다. 두 파일을 `git checkout`으로 되돌리고 Edit로 다시 넣었다. 패턴에
`|`가 든 치환은 다른 구분자를 쓰거나 Edit로 한다.
