# BB-M0 — barebone ISO를 짓고 배포 절차에 싣는다

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-barebone-design.md`
Status: 끝났다(2026-11-09)

## 착수 전에 확정한 것

design의 확인 1~6에 더해, plan을 쓰며 읽은 것(HEAD `c2d6af0`).

1. 설치기는 매체에 묶음이 없으면 묶음 단계를 통째로 건너뛴다 — `init/src/install.zig:1110-1118`(`ml.list.len > 0`일 때만 `lp`),
   갱신 길 `:1169-1176`(`lp != null`일 때만 `copyLayers`). 그러니 barebone ISO로 새로 깐 기계는 p3에 `/.tars/layers`가 없고, init은
   묶음 없는 부팅을 한다(TP 전과 같다).
2. 그런데 개발 도구 층이 깔린 기계를 barebone ISO로 갱신하면, 옛 묶음 파일과 그 `version`(옛 판)이 p3에 남는다. 새 init의 버전과 달라
   `layers.zig`의 `judgeVersion`이 `.differs`를 내고 묶음 전체를 건너뛴다 — 도구가 사라진 것처럼 보이지만 파일은 남아 1.8GiB를 차지한다.
   이것은 결함이 아니라 뜻에 맞는 동작이다(barebone은 개발 도구가 없는 판). 안내 한 줄과 이 plan의 확인 4로 다룬다. 코드는 안 바꾼다.
3. `make iso`는 `out/tars.iso` 하나에 쓴다. 지금 있는 것은 `dev-20261109`의 2.0GiB 판이다. barebone과 묶음 판을 같은 트리에서 차례로
   지으면 버전 글자(`<VERSION>+<sha>`)가 같다 — 두 ISO는 묶음 유무만 다르다.
4. 설치 로그(2026-11-09 실기)에서 본 크기: `bzImage` 11,437,056 B, `initrd.cpio` 128,069,028 B. barebone ISO는 이것과 Limine · 부트
   파일 정도로 약 140~150MB일 것이다(짓기 전 어림).

## Task 1 — barebone ISO 짓기 · 크기

- `make iso`(ISO_LAYERS 비움). 걸리는 시간: initrd · kernel 입력 해시가 같으면 건너뛰어 몇 분 안쪽일 것이다(어림 — 처음 재는 값).
- `ls -l out/tars.iso`로 크기, `xorriso -indev out/tars.iso -ls /boot`(또는 `isoinfo -l`)로 `boot/layers`가 없는지 본다.
- 저장소 밖 빈 디렉터리에 `tars-<ver>-barebone-x86_64.iso`로 복사해 둔다(Task 2의 smoke와 사용자의 실기용).

## Task 2 — QEMU smoke (`project_release` 절차 4와 같은 판정)

- `qemu-system-x86_64 -m 1024 -cdrom <iso> -display none -serial file:<log>`를 90초.
- 판정: `tars-init: starting as PID 1 (TARS 0.1.4+c2d6af0…)` · `terminal: grid` · `spawned child … fish`가 있고 `Kernel panic`이 0.
- 덧붙여 묶음 쪽 줄이 없는지(`tars-init: layers` 계열 로그를 읽어 USB 라이브에서 묶음을 찾지 않는 것을 본다 — 정확한 문구는 Task 2에서
  로그를 보고 적는다).

## Task 3 — 배포 절차에 barebone 한 단계

`docs/decisions/project_release.md`의 "배포 절차":

- 절차 3을 둘로: 먼저 `make iso`(묶음 없음)를 짓고 smoke(절차 4) 뒤 저장소 밖에 `tars-<ver>-barebone-x86_64.iso`로 옮긴다. 그다음
  `make iso ISO_LAYERS="<묶음들>"`로 묶음 판을 짓는다.
- 절차 5 · 6: 두 ISO를 `SHA256SUMS` 한 파일에, `gh release create`에 둘 다.
- 프리릴리스(`project_release_0_2`)도 같다 — `tars-dev-<날짜>-barebone-x86_64.iso`.
- 소개 페이지의 `releases` 줄은 지금 ISO 하나를 받는 모양이다(`[날짜, 버전, 한 줄, ISO 파일명, sha256]`). barebone을 페이지에 보일지는
  0.2.0을 낼 때 정한다 — 이 milestone은 `app.js`를 안 고친다.

## Task 4 — 안내 한 줄

`docs/guides/running-tars.md`의 설치 절에: "barebone ISO는 개발 도구 층이 없다. 개발 도구가 깔린 기계를 barebone으로 갱신하면 옛 묶음은
판이 달라 붙지 않는다(파일은 남는다 — 지우려면 `sudo rm -rf /home/.tars/layers`)." 확정 2의 내용이다.

## 판정

- barebone ISO가 smoke를 지나고, `boot/layers`가 없고, 크기가 기록됐다.
- `project_release`의 절차가 두 ISO를 내는 모양이 됐다.
- 코드 변경 0 — 루트 게이트는 돌리지 않는다(design 결정: smoke만. 게이트는 TP 닫을 때의 31/31 그대로).

## 비목표

1. 실기(맥북 에어) 설치 — 사용자가 원하면 Task 1의 파일로 한다. 개발 도구 층이 깔린 지금 디스크에 barebone 갱신을 하면 확정 2대로
   도구가 안 붙으니, 해 본다면 그 뒤 묶음 판으로 다시 갱신해 되돌린다.
2. fakesteak 묶음과 자동 실행(BB-M1).
3. 소개 페이지의 barebone 표시(Task 3의 끝).

## 결과

판정을 지났다(HEAD `3a0fae1` — plan 커밋이 확정 3의 `c2d6af0` 뒤에 왔다).

- Task 1: `make iso` 196초(initrd · kernel 캐시), `out/tars.iso` 143,751,168 B — 확정 4의 어림(140~150MB) 안. `bsdtar -tf`로 본 `boot/`는
  `bzImage` · `initrd.cpio` · `limine/`뿐, `boot/layers` 없음. 묶음 판(`dev-20261109`, 2,036,903,936 B)의 7%.
- Task 2: 호스트 QEMU 90초 — `tars-init: starting as PID 1 (TARS 0.1.4+3a0fae1)`, `terminal: grid 155x47 (fb 1280x800)`,
  `terminal: spawned child pid 40 (/usr/bin/fish)`, `Kernel panic` 0. 디스크가 없으니 `no disk labelled tars-home` → 묶음을 찾을 자리
  자체가 없다(묶음은 `/home` 뒤에 붙는다). 사본은 scratchpad의 `tars-0.1.4+3a0fae1-barebone-x86_64.iso`(저장소 밖).
- Task 3: `project_release` 절차 3(barebone 먼저 · 옮겨 두기) · 5(SHA256SUMS에 둘) · 6(`gh release create`에 둘), `project_release_0_2`에 프리릴리스 이름.
- Task 4: `running-tars.md` "안 되는 것"에 barebone 한 줄(확정 2).

