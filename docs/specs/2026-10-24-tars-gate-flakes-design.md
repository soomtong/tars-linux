# TARS Gate Flakes — Design

Date: 2026-10-24
Status: GF-M0 끝(2026-10-24, 루트 게이트 22/22, `skipping initrd` 22줄, inode 대조 22회차 통과). GF-M1은
`docs/plans/2026-10-24-tars-gate-flakes-gf-m1.md`.

2026-10-24의 프로젝트 점검에서 사용자가 골랐다. 점검이 찾은 "보강할 것" 여덟 가운데 둘째다 — 첫째(문서 · 스크립트 정리)는
`5dd567c` · `523c909`로 끝났다.

> 게이트의 간헐 실패 네 자리가 "다시 빨개지면"으로 열려 있다. 그중 initrd 경합은 원인과 처방 후보가 적혀 있어 닫을 수
> 있고, 나머지는 증거(실패한 판의 시리얼 로그)가 남아야 조사할 수 있다.

## 한 줄 요약

루트 게이트가 돌 때 initrd를 다시 만드는 쪽이 하나도 없게 하고(prebuild 한 번이 전부), 게이트가 남긴 시리얼 로그가 컨테이너와
함께 사라지지 않게 한다. 간헐 셋 가운데 원인이 보인 하나(dictation B4)는 창을 넓히고, 안 보인 둘(render 28 · net 31)은
판정을 건드리지 않는다 — 다음에 빨개질 때 볼 로그가 남는 것이 이 서브프로젝트의 몫이다.

## 배경

`docs/guides/lessons.md` "이월 숙제"에 게이트 간헐이 넷 적혀 있다(2026-10-24 기준).

| 자리 | 언제 | 무엇 | 원인을 아는가 |
|---|---|---|---|
| PM-M1 · UT-M3 | BV-M0 루트 게이트 1회차(2026-10-20) | PM은 QEMU가 `../kernel/initrd.cpio`를 못 열었다(ENOENT). UT는 검사 1d(c)가 남의 임시 파일 `initrd.cpio.7IetxQ`를 셌다 | 안다 — 병렬 레인이 같은 파일을 동시에 다시 만든다 |
| dictation B4 | BS-M0 루트 게이트 1회차(2026-10-09) | `read -s got something`. 로그에는 둘째 `got[]`가 `ret` 바로 다음 프레임에 있었다 | 안다 — 게이트의 10초 창을 놓쳤다 |
| render 28 | VD-M2 루트 게이트 2회차(2026-10-06) | vim의 `R` 뒤 underline 커서가 15초 동안 `vt=block` | 모른다 — 로그가 `mktemp`라 보지 못했다 |
| net 31 | TC-M2 루트 게이트 두 판(2026-10-07) | `reload of` 뒤에 steer 줄이 없었다 | 가설만 있다 — TC-M2가 진단 셋을 넣었고 그 뒤 초록 |

넷 모두 "그 체인만 다시 돌리면 초록"이었다. 그래서 지금까지는 한 번 더 돌려 넘겼다. 그 비용은 10분짜리 게이트를 두 번
돌리는 것이고, 더 큰 비용은 빨간 판의 로그가 `docker run --rm`과 함께 사라져서 다음에도 같은 자리에서 같은 짐작을 하는 것이다.

## 착수 전에 확인한 것

2026-10-24, HEAD `523c909`.

1. 체인 22개 전부가 시작할 때 `(cd ../kernel && ./make_initrd.sh)`를 부른다. 조건 없이 매번이다. GP design 결정 6이 "같은
   내용이면 건너뛰기"를 안 한 것은 아낄 시간이 2분 남짓이라 잡음 안이었기 때문이고, 그때는 올바름의 문제가 아니었다.
2. 루트 `check.sh`의 `prebuild`가 `make_initrd.sh`를 한 번 돌린 뒤 체인을 `JOBS`줄(12GB OrbStack에서 6)로 동시에 띄운다. 그러면
   최대 여섯 체인이 같은 `kernel/initrd.cpio`를 각자 임시 파일에 만들어 `mv -f`로 바꿔치기한다(GP-M1). 한 체인이 `mv`하는
   순간 다른 체인의 QEMU가 `-initrd ../kernel/initrd.cpio`를 연다.
3. 저장소는 OrbStack의 bind mount(`-v "$PWD":/workspace`)다. 리눅스 로컬 파일시스템의 rename은 `open()`에 옛 inode나 새 inode
   둘 중 하나를 주고 ENOENT를 주지 않지만, PM-M1이 본 것은 ENOENT였다 — 이 mount에서는 rename의 두 순간 사이가 보인다.
   GP-M1의 rename은 "읽던 쪽이 옛 파일을 끝까지 읽는다"를 지키지만 "여는 순간"을 지키지 못한다. 처방은 rename을 더 고치는 것이
   아니라 동시에 쓰는 쪽을 없애는 것이다.
4. 체인이 `make_initrd.sh`의 입력을 바꾸는 자리는 없다. 체인이 `../kernel/` 아래를 만지는 곳은 전부 읽기다 — `build/modules.builtin.modinfo`
   (audio · pointer · wifi), `build/vmlinux`(audio), `dhcpcd-hooks/30-tars-ntp`(net), `dictation/tars-dictate`의 `bash -n`(dictation).
   그래서 prebuild가 만든 initrd는 어느 체인에게도 낡지 않는다.
5. `tools/check.sh` 검사 1d는 initrd를 일부러 한 번 더 만든다 — 열어 둔 fd의 inode와 경로의 inode가 다른지(a), 열어 둔 fd가 옛
   바이트를 그대로 읽는지(b), `kernel/initrd.cpio.*`가 안 남았는지(c)를 본다. (c)는 `ls initrd.cpio.*`라 다른 레인이 쓰는 중인 임시
   파일까지 센다. 1d의 두 번째 빌드 자체도 "동시에 쓰는 쪽" 하나다.
6. `make_initrd.sh`는 `OUT="$(mktemp initrd.cpio.XXXXXX)"`에 만들고 끝에서 `mv -f "$OUT" initrd.cpio`한다. 출력 경로가 글자로
   박혀 있고 바꿀 손잡이가 없다.
7. 루트 `check.sh`는 회차마다 `TMPDIR=<GATE_LOGS>/<체인>-<회차>`를 주고(AL-M0) 체인은 로그를 지우지 않는다. `GATE_LOGS`는
   컨테이너의 `/tmp/tars-gate.XXXXXX`다. 컨테이너는 `--rm`이라 `/tmp`를 호스트에 묶지 않으면 게이트가 끝나는 순간 전부 사라진다.
   lessons는 "lead가 `-v <호스트>:/tmp`로 돌린다"고 적었지만 `make gate` · README · lessons의 명령 셋 어디에도 그 `-v`가 없다.
   `render/check.sh`만 `report_failure`가 로그를 `out/render-failed-serial.log`로 복사한다(VD-M2 뒤에 넣었다).
8. 체인 하나를 돌리는 `make check CHAIN=x`는 `TMPDIR`을 주지 않는다. 그 로그는 컨테이너 `/tmp/tmp.XXXXXX`이고 역시 사라진다.
9. dictation B4의 둘째 `got[]` 기다림은 `for _ in $(seq 1 100); do … sleep 0.1; done`으로 10초다. 바로 위의 `refused password at=insert`
   기다림은 20초(`wait_count … 1 20`)다. 같은 검사 안에서 창의 길이가 다른 이유는 없다.
10. `check.sh` 590줄의 주석은 "prebuild 뒤에는 `skipping make`가 체인 수 × RUNS여야 한다"고 적었지만 그것을 세는 코드는 없다.

## 목표

1. 루트 게이트가 도는 동안 `kernel/initrd.cpio`에 쓰는 프로세스가 prebuild 하나뿐이다. 체인은 그것을 읽기만 한다.
2. tools 검사 1d는 rename의 세 성질을 그대로 보되 실제 initrd를 건드리지 않는다.
3. 게이트(루트 · 체인 하나)가 남긴 시리얼 로그가 컨테이너가 사라진 뒤에도 호스트에 남는다. 통과한 판도 남는다 — 간헐은 통과한 판과
   빨간 판을 나란히 놓고 보는 것이다.
4. 알려진 원인 하나(B4의 창)를 고친다. 원인을 모르는 둘은 건드리지 않는다.

## 결정

### 결정 1. 루트 게이트는 환경 변수로 "initrd는 이미 만들었다"를 체인에 알린다

`check.sh`가 `prebuild`를 마친 뒤 `export TARS_PREBUILT_INITRD=1`을 둔다. `make_initrd.sh`가 맨 앞에서 그 변수와 `initrd.cpio`의
존재를 함께 보고, 둘 다 참이면 `skipping initrd (prebuilt by the root gate)` 한 줄을 찍고 0으로 끝난다.

- 체인 스크립트 22개는 한 글자도 안 바뀐다. 체인이 빌드를 부르는 구조(`require_build_steps`의 진입 검사)도 그대로다.
- 체인 하나를 손으로 돌릴 때(`make check`, `docker run … bash copy/check.sh`)는 변수가 없으니 예전처럼 매번 만든다 — 그 체인이
  고친 것을 스스로 굽는 성질이 산다.
- 입력의 해시로 건너뛰는 길(GP 결정 6이 미룬 것)은 여전히 안 한다. 입력이 sysroot 수백 파일이라 해시가 비싸고, 지금 필요한 것은
  "같은 게이트 안에서 두 번 만들지 않는다"뿐이다. 변수 하나가 그 말을 정확히 한다.

### 결정 2. 루트 게이트는 initrd의 inode가 안 바뀌었는지 회차마다 본다

`check.sh`가 prebuild 직후 `kernel/initrd.cpio`의 inode를 적어 두고, `run_chain`이 회차가 끝날 때마다 다시 읽어 견준다.
다르면 그 회차는 FAIL이다 — 누군가 initrd를 다시 만들었다는 뜻이고(rename은 inode를 바꾼다, GP-M1), 그것이 바로 이
서브프로젝트가 없애는 경합이다. 출력에서 `skipping initrd` 줄을 세는 것보다 직접적이다 — 글자는 건너뛰었다는 주장이고
inode는 안 썼다는 사실이다. GA의 원칙("게이트가 못 보는 것은 게이트가 통과시킨다")을 여기에도 둔다. 확인 10의
`skipping make` 주석은 그대로 둔다(커널 빌드는 `.config` 해시로 이미 건너뛰고, 이 서브프로젝트의 자리가 아니다).

### 결정 3. `make_initrd.sh`는 출력 경로를 받고, tools 1d는 자기 사본에 그것을 쓴다

`make_initrd.sh`에 `INITRD_OUT`(기본 `initrd.cpio`)을 둔다. 임시 파일은 `mktemp "${INITRD_OUT}.XXXXXX"`로 그 옆에 만든다 —
rename이 같은 파일시스템이어야 하는 것은 그대로다. `INITRD_OUT`을 받은 호출은 결정 1의 건너뛰기를 적용하지 않는다(사본을
달라고 한 것이지 공유 산출물을 달라고 한 것이 아니다).

tools 1d는 `cp ../kernel/initrd.cpio "$T/initrd.cpio"`로 사본을 만들고(`T`는 `mktemp -d`, 회차의 `TMPDIR` 아래), 그 사본을 열어 둔
채 `INITRD_OUT="$T/initrd.cpio" ./make_initrd.sh`를 돌린다. (a) · (b)는 그대로이고 (c)는 `$T/initrd.cpio.*`를 본다 — 자기 디렉터리라
남의 임시 파일이 있을 수 없다. 1d가 보는 성질은 rename의 성질이고 경로가 어디든 같다.

### 결정 4. 루트 게이트의 로그는 끝날 때 저장소의 `out/gate-logs/`로 옮긴다

`GATE_LOGS`는 지금처럼 컨테이너 `/tmp`에 둔다(overlay, 빠르다). `check.sh`가 EXIT trap으로 그 디렉터리를 통째로
`out/gate-logs/<시작 시각>/`에 옮긴다(`mv`, bind mount를 넘으니 실제로는 복사 뒤 삭제). 통과 · 실패 · 중단 모두 같다. 마지막 줄의
`(logs in …)`은 옮긴 뒤의 호스트 경로를 찍는다.

- `out/`은 `.gitignore`에 있고 `clean()`이 게이트 시작에 지운다 — 다음 게이트가 앞 게이트의 로그를 지우는 것은 지금 `/tmp`가
  사라지는 것과 같은 수명이다. 남기고 싶은 판은 사람이 밖으로 옮긴다(지금은 그 기회가 없다).
- 로그를 처음부터 bind mount에 쓰지 않는 이유는 QEMU `-serial file:`이 작은 write를 많이 내기 때문이다. 그 비용은 재지 않았고
  (위험 1), 끝에 한 번 옮기는 것은 재지 않아도 안전하다.
- `render/check.sh`의 `report_failure` 복사는 지운다 — 루트 게이트에서는 결정 4가, 체인 하나에서는 결정 5가 대신한다.

### 결정 5. `make check CHAIN=x`도 `/tmp`에 쓰고 끝에 `out/gate-logs/<체인>/`으로 옮긴다

Makefile의 `check` 타깃이 컨테이너 안에서 `TMPDIR=/tmp/gate-logs/<체인>`을 주어 체인을 돌리고, 종료 코드를 잡아 둔 뒤 그
디렉터리를 `out/gate-logs/<체인>/`으로 옮긴다(앞 판의 것은 지운다). 체인의 `mktemp`가 전부 `TMPDIR`을 따르므로 시리얼 로그 ·
SEED · 디스크 이미지 사본이 남는다. `TMPDIR`을 bind mount로 바로 주지 않는 이유는 체인이 부르는 `make_initrd.sh`의 작업
디렉터리도 `mktemp -d`라서다 — sysroot 수천 파일을 bind mount에 복사하게 된다. 루트 게이트(결정 4)와 같은 모양이다.

### 결정 6. dictation B4의 둘째 `got[]` 창은 20초다

같은 검사의 앞 기다림과 같은 길이로 맞춘다. 판정 글자는 그대로다. 이것만이 이 서브프로젝트가 고치는 판정이고, 근거는 BS 때 읽은
로그다(`got[]`가 `ret`의 바로 다음 프레임에 있었다 — 글자가 비밀번호 프롬프트에 들어간 것이 아니다).

### 결정 7. render 28과 net 31은 건드리지 않는다

원인을 모르는 판정을 넓히면 진짜 회귀를 가린다. 둘은 lessons "이월 숙제"에 그대로 두고, 다음에 빨개지면 결정 4가 남긴 로그부터
본다. 그때 할 일(어느 줄을 볼지)은 이미 lessons에 있다.

## Milestone

- GF-M0 — initrd를 다시 만드는 쪽이 없다. 결정 1 · 2 · 3. 판정은 루트 게이트다 — 경합은 체인 하나로는 볼 수 없다. 끝 조건은
  22/22와, 회차 22개 모두에서 `kernel/initrd.cpio`의 inode가 prebuild 직후와 같다는 것(결정 2의 검사가 그것을 찍는다).
- GF-M1 — 로그가 남는다. 결정 4 · 5 · 6과 render의 복사 삭제, lessons · README의 로그 절 갱신. 끝 조건은 루트 게이트 뒤
  `out/gate-logs/<시각>/`에 22체인의 디렉터리와 `times.tsv` · `prebuild.out`이 있고, `make check CHAIN=device` 뒤 `out/gate-logs/device/`에
  시리얼 로그가 있는 것. 통과한 체인도 남는다.

## 위험

1. 옮기는 트리의 크기. 체인 하나가 남기는 것은 시리얼 로그 몇 개와 tools 1d의 initrd 사본 98MB다. 루트 게이트는 그것의 22배가
   아니라(사본은 tools만) 로그 22벌이다. M1이 둘의 크기와 옮기는 시간을 실측 절에 적는다.
2. 결정 1의 변수가 체인 밖으로 새는 것. `check.sh`가 `export`하면 체인이 띄우는 모든 자식에 간다 — 체인이 `make_initrd.sh` 말고
   그 변수를 볼 곳은 없지만, 이름을 `TARS_`로 시작해 우연한 충돌을 피한다.
3. 결정 4의 `mv`가 큰 트리를 bind mount로 옮기는 시간. 22체인의 로그 합이 수백 MB면 수 초다. 게이트 끝의 `time:` 줄에 그 시간을
   따로 찍어 잡음인지 본다.
4. 결정 3이 `make_initrd.sh`에 분기를 하나 더한다. `INITRD_OUT`을 준 호출이 건너뛰기를 안 한다는 것을 tools 1d가 매번 증명한다
   (건너뛰면 사본의 inode가 안 바뀌어 (a)에서 빨갛다).

## 비목표

1. 입력 해시로 initrd 빌드를 건너뛰는 것(GP 결정 6). 이 서브프로젝트 뒤에도 체인 하나는 매번 만든다.
2. render 28 · net 31의 판정 변경(결정 7).
3. `/tmp`를 호스트에 묶는 `docker run` 옵션을 표준 명령에 넣는 것. 결정 4가 옵션 없이 같은 결과를 준다.
4. 로그를 게이트 사이에 보존하는 것. `clean()`의 수명이 그대로다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행, 소개 페이지 `data.js`.
- lessons "이월 숙제"의 BV · BS 항목을 지우고, render 28 · net 31 항목에 "로그는 `out/gate-logs/`에 남는다"를 더한다.
  "게이트 로그를 조사하는 법" 절의 `docker run … grep /tmp/tmp.*` 처방을 새 경로로 바꾼다.
- `docs/decisions/project_gate_flakes.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`.

## 관련

- `docs/specs/2026-10-10-tars-gate-parallel-design.md` — 병렬 레인과 rename(GP-M1)이 선 자리.
- `docs/specs/2026-10-07-tars-atomic-log-lines-design.md` — 회차별 `TMPDIR`(AL-M0)이 선 자리.
- `docs/decisions/project_gate_accuracy.md` — "게이트가 못 보는 것은 게이트가 통과시킨다".
