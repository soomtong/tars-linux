---
name: project_gate_flakes
description: 게이트의 간헐 실패를 닫은 서브프로젝트 Gate Flakes(GF-M0 · M1, 2026-10-24). 루트 게이트에서 initrd를 다시 만드는 쪽을 없애고(prebuild 하나, inode 대조), 게이트 로그가 컨테이너보다 오래 살게 했다(out/gate-logs/). 원인 모르는 간헐은 판정을 안 넓혔다
metadata:
  type: project
---

Gate Flakes(GF)는 2026-10-24의 프로젝트 점검(진행 상황 · 품질 검토)에서 둘째 항목으로 사용자가 골랐다. design은
`docs/specs/2026-10-24-tars-gate-flakes-design.md`, plan은 `-gf-m0.md`(initrd) · `-gf-m1.md`(로그)이고 값은 각 plan의 실측 절에
있다. lead가 직접 구현했다(서브에이전트 없음).

## 결정

1. 루트 게이트가 도는 동안 `kernel/initrd.cpio`에 쓰는 것은 prebuild 하나다. `check.sh`가 prebuild 뒤 `export TARS_PREBUILT_INITRD=1`을
   두고, 체인이 부르는 `make_initrd.sh`가 그 변수와 파일의 존재를 보면 `skipping initrd` 한 줄로 끝난다. 체인 스크립트 22개는 안
   바뀌었고, 체인 하나를 손으로 돌리면 변수가 없어 예전처럼 매번 만든다. 입력 해시로 건너뛰기([[project_gate_parallel]] 결정 6)는
   여전히 안 한다 — 필요한 말은 "같은 게이트 안에서 두 번 만들지 않는다"뿐이고 변수 하나가 그 말을 한다.
2. 건너뛰었다는 글자가 아니라 inode를 본다. `run_chain`이 회차마다 `stat -c %i`로 prebuild 직후와 견주고 다르면 FAIL이다
   ([[project_gate_accuracy]] — 게이트가 못 보는 것은 게이트가 통과시킨다).
3. `make_initrd.sh`는 `INITRD_OUT`(기본 `initrd.cpio`)을 받는다. tools 검사 1d는 `TMPDIR` 아래 사본에 그것으로 만들어 rename의 세 성질을
   본다 — 공유 파일을 안 건드리고, (c)의 "남은 임시 파일"이 자기 디렉터리라 남의 것을 셀 일이 없다. `INITRD_OUT`을 준 호출은
   건너뛰지 않는다.
4. 루트 게이트의 로그 트리(`/tmp/tars-gate.XXXXXX`)는 EXIT trap이 끝에 `out/gate-logs/<시작 시각>/`으로 옮긴다. 초록 · 빨강 · Ctrl+C
   모두 같다. 통과한 판도 남는다 — 간헐은 통과한 판과 빨간 판을 나란히 놓고 보는 것이다. 처음부터 bind mount에 쓰지 않는 이유는
   QEMU `-serial file:`의 작은 write가 많기 때문이고, 체인이 부르는 `make_initrd.sh`의 작업 디렉터리도 `mktemp -d`라 bind mount로 가면
   sysroot 수천 파일 복사가 느려진다.
5. `make check CHAIN=x`도 같은 모양이다 — 컨테이너 `/tmp/gate-logs/<체인>`에 쓰고 끝에 `out/gate-logs/<체인>/`으로 옮긴다(앞 판은 지운다).
   `render/check.sh`의 `report_failure`가 실패 로그를 `out/`에 복사하던 세 줄은 지웠다.
6. 원인을 아는 간헐만 고쳤다. dictation B4의 둘째 `got[]` 창을 10초에서 20초로(같은 검사의 앞 기다림과 같다). render 28 · net 31은
   원인을 모르니 판정을 안 넓혔다 — 모르는 판정을 넓히면 진짜 회귀를 가린다. 다음에 빨개지면 결정 4가 남긴 로그부터 본다.

## 함정

- bind mount(OrbStack)에서는 rename의 두 순간 사이가 보인다. 리눅스 로컬 파일시스템은 rename 중의 `open()`에 옛 inode나 새 inode를
  주지만, BV-M0 루트 게이트의 PM은 `-initrd ../kernel/initrd.cpio`에서 ENOENT를 받았다. GP-M1의 rename은 "읽던 쪽"은 지키지만 "여는
  순간"은 못 지킨다. 처방은 rename을 더 고치는 것이 아니라 동시에 쓰는 쪽을 없애는 것이다.
- 체인이 initrd의 입력을 바꾸는 자리는 없다. 체인이 `../kernel/` 아래를 만지는 곳은 전부 읽기였다(`build/modules.builtin.modinfo` ·
  `build/vmlinux` · `dhcpcd-hooks/` · `dictation/tars-dictate`의 `bash -n`). 그래서 prebuild의 initrd가 어느 체인에게도 낡지 않는다.
  체인이 initrd 입력을 바꾸는 날 결정 1은 그 체인만 변수를 지우고 불러야 한다.
- perl `s|…|…|`의 구분자 `|`는 패턴 안의 `\|\|`(bash의 `||`)와 충돌한다 — 구분자가 먼저 벗겨져 regex 교대(`||`)가 되고 빈 문자열에
  맞아 파일 머리에 치환문이 낀다. 패턴에 `|`가 들면 다른 구분자를 쓰거나 Edit로 한다.
- `make check`가 로그를 남기지만 `docker run … bash x/check.sh`로 직접 돌리면 `TMPDIR`을 주는 쪽이 없어 예전처럼 사라진다.
