# TARS Shellcheck Notes — Design

Date: 2026-10-31
Status: 진행 중 — SN-M0

GH-M1이 남긴 다음 후보 셋 가운데 "shellcheck note 46"에서 시작한다. 사용자가 골랐다(2026-10-31).

## 한 줄 요약

`quick_check.sh`가 판정하지 않고 수만 찍던 shellcheck note 46건을 0으로 만들고, 판정 수준을 `-S warning`에서 `-S style`로 내려
note도 빨강으로 친다. 46건 가운데 18건은 출력이 같은 정석 형태로 고치고, 28건은 의도한 것이라 그 자리에 지시자와 이유를 단다.
동작 · 로그 바이트는 0 변경이다.

## 배경

- GH-M0(2026-10-30)이 `quick_check.sh`의 shellcheck를 warning 이상으로 판정하게 했고, note는 "기준선 46"으로 수만 찍게 했다
  (`quick_check: shellcheck notes: N`). 수만 찍는 줄은 아무도 안 본다 — 47이 되어도 초록이다.
- note가 0이면 판정을 한 단계 내릴 수 있고, 그 뒤로 새 note는 push마다 CI의 `host` job이 잡는다.

## 착수 전에 확인한 것

2026-10-31, HEAD `75a15e7`, shellcheck 0.11.0(호스트 Homebrew = CI tarball). 대상 51파일(`git ls-files '*.sh'` + 게스트 스크립트 둘).

1. 46건 전부 gcc 형식의 `note`다(style · info 수준이 gcc 형식에서 `note`로 찍힌다). 코드별: SC2329 19 · SC2028 7 · SC2086 5 ·
   SC2012 5 · SC2016 3 · SC1003 2 · SC2162 · SC2116 · SC2059 · SC2019 · SC2018 각 1. 파일별로는 `config/check.sh` 10 ·
   `render/check.sh` 8 · `site/capture.sh` 5가 크고 나머지 열여섯 파일에 1~3.
2. SC2329("This function is never invoked") 19건은 전부 간접 호출이다 — trap 핸들러 열(`cleanup` 여덟 · `tars-dictate`의
   `on_int` · `on_term`)와 `config/check.sh`의 `boot_once "$LOG" "<표식>" <함수>`로 이름을 넘기는 콜백 아홉.
3. 그런데 같은 `trap cleanup EXIT`을 가진 다른 체인 열몇은 안 걸린다. 차이를 잘라 가며 찾았다: 파일의 마지막 최상위 명령이
   `exit`이면 걸린다. 최소 예제로 재현 —

   ```
   cleanup() { echo "$P"; }      cleanup() { echo "$P"; }
   trap cleanup EXIT              trap cleanup EXIT
   echo hi                        echo hi
                                  exit 1
   → 조용                          → SC2329
   ```

   이름으로 넘기는 콜백(`run() { "$1"; }; run f`)도 같다. shellcheck가 trap · 간접 호출을 "스크립트 끝에서 불린다"로 셈하는데,
   끝이 `exit`라 도달하지 않는다고 보는 것으로 읽힌다. 진짜 죽은 함수가 아니다.
4. 지시자는 함수 정의 바로 위 한 줄로 그 함수에만 걸린다. `# shellcheck disable=SC2329 # 이유` 꼴로 뒤에 이유를 붙일 수 있다
   (`kernel/tq-probe.sh:27`이 이미 이 꼴). 저장소의 지시자는 지금 열한 곳.
5. `.shellcheckrc`는 없다.

## 결정

### 결정 1. 판정은 `-S style` 한 번 — 수 세는 줄을 지운다

`quick_check.sh`의 1단계를 `shellcheck -x -P SCRIPTDIR -S style "${sh_files[@]}"` 하나로 바꾼다. 실패하면 `failed+=(shellcheck)`.
`notes=…` 두 줄과 "기준선 46" 주석은 지운다. CI는 같은 파일을 돌리므로 `checks.yml`은 0줄이다.

### 결정 2. SC2329 19건은 함수 위 지시자

```
# shellcheck disable=SC2329 # trap cleanup EXIT이 부른다
cleanup() {
```

`boot_once` 콜백은 `# … # boot_once가 이름으로 부른다`. 다른 길 둘을 버린 이유:

- `.shellcheckrc`에서 SC2329를 전역으로 끄기 — 한 줄이지만 진짜 죽은 함수(체인을 고치다 남는 것)도 함께 못 보게 된다.
  SC2329는 끝이 `exit`인 파일에서만 헛짚으므로 그 자리만 표시한다.
- 끝의 `exit 1`을 다른 꼴로 바꿔 shellcheck를 피하기 — 체인의 종료 코드는 루트 게이트가 읽는 계약이다. 도구의 버릇 때문에
  계약의 모양을 바꾸지 않는다.

### 결정 3. 의도한 것 9건도 지시자 — SC2016 · SC2059 · SC2012

- SC2016 3건(`dictation/check.sh` 2, `service/check.sh` 1): 작은따옴표 안의 `$x` · `$(…)`은 호스트가 아니라 게스트 셸이 펼칠
  글이다. 지시자 이유: "게스트가 펼친다".
- SC2059 1건(`tars-dictate`의 `le32`): `printf "$(printf '\\x%02x…')"`는 format 자리의 `\xHH`로 WAV 머리의 바이트를 내는 것이
  목적이다. `printf '%b'`가 정석이지만 바이너리를 쓰는 게스트 코드라 이번 일에서 손대지 않는다(지시자 이유: "바이트를 내는
  format").
- SC2012 5건(`ls` 대신 `find`): 이름이 정해진 자리다 — 게스트의 `/dev/snd` · `/tmp/tars-dictate.*.wav`, sysroot의
  `mozilla/*.crt`, `site/capture.sh`가 스스로 만든 프레임 `*.ppm`. 공백 · 줄바꿈이 들어올 길이 없다. 지시자 이유: "이름은
  정해져 있다(…)".

### 결정 4. 고칠 수 있는 18건은 출력이 같은 정석 형태로

| 코드 | 자리 | 지금 | 고친 뒤 |
|------|------|------|---------|
| SC2086 × 3 | `firewall` · `net` · `service` 체인의 QEMU `-monitor` | `tcp:127.0.0.1:$1,server,nowait` | `tcp:127.0.0.1:"$1",server,nowait` |
| SC2086 + SC2116 | `check.sh:133` | `$(echo $hits)` | `${hits//$'\n'/ }` |
| SC2086 | `audio/check.sh:300` | `printf '%s\n' $SOF_NAMES \| wc -l` | `wc -l <<<"$SOF_NAMES"` |
| SC2028 × 7 | `render/check.sh`의 `echo "=== typing printf '\\033…' ==="` | `echo "…"` | `printf '%s\n' "…"` |
| SC1003 × 2 | `render/check.sh` · `site/capture.sh`의 `case` | `'\')` | `\\)` |
| SC2162 | `kernel/tq-probe.sh:28` | `read -n 20 -t 2 r` | `read -r -n 20 -t 2 r` |
| SC2018 · SC2019 | `site/capture.sh:121` | `tr 'A-Z' 'a-z'` | `tr '[:upper:]' '[:lower:]'` |

출력이 같은 이유 —

- `-monitor`의 포트는 숫자다. 따옴표는 셸이 벗긴다.
- `$hits`는 awk가 찍은 줄 번호(숫자 한 줄씩)다. `echo $hits`의 단어 쪼개기와 줄바꿈 → 공백 치환은 같은 글을 낸다.
- `$SOF_NAMES`는 `comm` 출력(한 줄에 이름 하나, 끝 줄바꿈은 `$(…)`이 뗐다)이다. here-string이 줄바꿈 하나를 붙여 `wc -l`이 같다.
  비어 있을 때도 둘 다 1이다(빈 줄 하나).
- bash의 `echo`는 `-e` 없이 백슬래시를 안 푼다(`xpg_echo` 꺼짐). `printf '%s\n'`도 인자를 그대로 낸다. design을 쓰며
  scratchpad에서 두 줄을 나란히 돌려 같은 글을 확인했다.
- `case`의 `\\)`는 백슬래시 한 글자와 맞는다(같이 확인).
- tq-probe가 읽는 것은 터미널의 커서 위치 응답 `ESC [ 행 ; 열 R`이다 — 백슬래시가 없다. 게스트 `/bin/sh`는 bash라 `-r`이 된다.
- `$ch`는 `[A-Z]`에 걸린 ASCII 한 글자다.

### 결정 5. 검증

게이트 입력(체인 스크립트 · `kernel/tq-probe.sh` · `kernel/dictation/tars-dictate`)이 바뀌므로 루트 게이트를 돈다.

1. `make quick` PASS — 새 판정(`-S style`)에서 note 0.
2. mutation 하나 — 아무 체인에 따옴표 없는 변수 한 줄(note 수준)을 넣으면 `make quick`이 `FAIL: shellcheck`. 되돌린다.
3. 루트 게이트 1회(약 10분). 22/22, verify 줄 전부 `ok`. `render`의 `=== typing …` 줄이 바뀌기 전 로그와 같은지 한 줄 대조.
4. push 뒤 CI 한 회차 — `host` job이 새 판정으로 초록.

`site/capture.sh`는 게이트 밖이다(소개 페이지 녹화). `bash -n`과 바꾼 두 줄의 조각 실행으로 본다.

## 위험

1. shellcheck를 올리면 새 note가 나와 `make quick`과 CI가 빨개질 수 있다. 그것이 이번 일의 뜻이다 — 버전은
   `quick_check.sh`의 `SHELLCHECK_VERSION`과 `checks.yml`이 고정하므로 올리는 사람이 그때 함께 본다.
2. 호스트 Homebrew가 shellcheck를 먼저 올리면 로컬만 빨개질 수 있다. 지금도 버전이 다르면 한 줄 찍는다(`quick_check:
   shellcheck is …`) — 그 줄이 이유다.
3. SC2329 지시자는 shellcheck의 버릇을 덮는다. 다음 버전이 고치면 지시자가 쓸모없어지지만 해롭지 않다(shellcheck에는 "쓰이지
   않는 지시자" 경고가 없다). 대신 그 함수가 정말 죽어도 못 본다 — 지시자 이유에 부르는 자리를 적어 두어 사람이 대조할 수 있게 한다.

## 비목표

1. `tars-dictate` `le32`를 `printf '%b'`로 바꾸기(결정 3).
2. `ls`를 `find`로 바꾸기(결정 3).
3. 루트 게이트 안에서 shellcheck를 돌리기. 게이트는 부팅 판정이고 shellcheck는 `make quick` · CI의 몫이다(GH-M0 결정).

## Milestone

- SN-M0 — 위 결정 전부. Task 둘.
  1. 지시자 28 · 고침 18 · `quick_check.sh` 판정, 낡은 글. 확인 1 · 2와 capture 조각.
  2. 루트 게이트(확인 3) → commit → push · CI(확인 4) → 닫기.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_github_actions.md`에 SN-M0 한 단락(다음 후보에서 "note 46" 지우기). 새 기억 파일은 만들지 않는다(작은
  일이다) — `MEMORY.md`의 GitHub Actions 줄에 덧붙인다.
- `docs/guides/lessons.md`의 `make quick` 주석("판정이 아니다(기준선 46)"), `Makefile` 도움말.
- `HANDOFF.md`. 소개 페이지에는 안 넣는다(내부 작업).

## 관련

- `docs/specs/2026-10-30-tars-github-actions-design.md` — `quick_check.sh`와 `-S warning`을 정한 곳.
- `docs/decisions/project_github_actions.md` — "note 46은 판정하지 않고 수만 찍는다".
