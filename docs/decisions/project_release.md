---
name: project_release
description: "첫 공개 버전 TARS 0.1.0(2026-10-11, tag v0.1.0 = 0a6d4bc)과 0.1.1(2026-10-24, tag v0.1.1 = 1f2978f) — GitHub release에 tars-<ver>-x86_64.iso와 SHA256SUMS. x86_64 ISO 하나만 낸다. 배포 절차(VERSION 커밋 → annotated tag → make iso → QEMU smoke → 해시 → push · gh release create → 내려받아 대조)와 소개 페이지의 releases 배열. tag가 make iso보다 먼저인 이유는 BV의 버전 글자"
metadata:
  type: project
---

# Release

사용자의 요청(2026-10-11): "여기에서 첫 번째 버전을 찍으면 좋을 것 같아. 버전 번호는 0.1.0. 리눅스 x86_64 버전만 우리는
제공하는 거고 GitHub의 release 페이지에서 ISO 파일을 다운로드 받아서 사용할 수 있도록 공개하자."

## 0.1.0

| 항목 | 값 |
|---|---|
| tag | `v0.1.0` (annotated) → `0a6d4bc` (RS-M3, 마지막 루트 게이트 22체인 PASS) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.0 (Latest, prerelease 아님) |
| ISO | `tars-0.1.0-x86_64.iso`, 111,071,232 B |
| sha256 | `f9ef7da2fd52a74c893ea80dac669a54959bf52458532ae7c66211bfa9a81686` |

notes는 한국어로 썼다 — 다운로드 · 체크섬 확인, 요구 사항(x86_64 · 메모리 1GB · 실기는 Secure Boot 끔), QEMU · USB `dd` ·
`tars-install`, 기능 갈래, 알려진 한계. 자세한 절차는 tag에 고정된 `docs/guides/running-tars.md` 링크로 넘긴다.

## 0.1.1 (2026-10-24)

| 항목 | 값 |
|---|---|
| tag | `v0.1.1` (annotated) → `1f2978f` (`Release 0.1.1`, ZU-M2 뒤. 그 커밋의 루트 게이트 22/22) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.1 (Latest) |
| ISO | `tars-0.1.1-x86_64.iso`, 112,136,192 B (0.1.0보다 1.0MB 큼 — terminal의 디버그 섹션 4.6MB가 gzip 뒤 그만큼) |
| sha256 | `c749d8fc74d39b3d6627723fc9c52c0bffc9cd5d9b5629ffa4af3320734077be` |

0.1.0 뒤의 세 서브프로젝트(BV · GF · ZU)를 담은 도구 층 갱신이다. 노트는 0.1.0 것을 두고 "0.1.0에서 달라진 것" 절을 앞에 더했다.
절차는 아래 1~6을 그대로 밟았고(1의 게이트는 `VERSION` 커밋에서 다시 돌렸다, 10분 34초), 7(소개 페이지)은 사용자 결정으로 건너뛰었다가 2026-10-27에 사용자의 지시로 `releases`에 넣었다.
smoke 로그 첫 줄이 `tars-init: starting as PID 1 (TARS 0.1.1)`로 꼬리표가 없었다 — BV의 버전 글자가 처음으로 릴리즈에서 쓰였다.

## 배포 절차 (다음 버전도 이대로)

BV(2026-10-20)부터 시스템 안에 버전이 있다. 빌드는 HEAD가 `v<VERSION>` 태그이고 추적 파일에 고친 데가 없을 때만 맨 `<ver>`를
박고, 그 밖에는 `+<sha>`(·`-dirty`)를 붙인다(`docs/specs/2026-10-20-tars-build-version-design.md` 결정 2). 그래서 tag가
`make iso`보다 먼저다.

1. 저장소 뿌리의 `VERSION`을 새 번호로 고쳐 커밋한다. 그 커밋에서 루트 게이트가 PASS인지 본다(게이트 이미지는
   `+<sha>`를 단다). 트리는 clean이어야 한다.
2. `git tag -a v<ver> <그 커밋> -m …`. push는 아직 안 한다.
3. `make iso` — 입력 해시가 같으면 kernel · terminal을 건너뛴다. init은 `zig build`가 git을 다시 물어 버전 글자가 바뀌었으면
   다시 컴파일한다. `out/tars.iso`가 이미 있어도 어느 트리의 것인지 모르므로 다시 만든다.
4. 호스트 QEMU smoke — `qemu-system-x86_64 -m 1024 -cdrom out/tars.iso -display none -serial file:<log>`를 90초 띄우고
   `tars-init: starting as PID 1 (TARS <ver>)`(꼬리표 없이) · `terminal: grid` · `spawned child … fish`가 있고
   `Kernel panic`이 0인지 본다. 설정 디스크를 안 붙여 처음 받은 사람과 같은 기본값 경로를 밟는다. 꼬리표가 붙었거나
   smoke가 실패하면 `git tag -d v<ver>`로 지우고 고친다 — push 전이라 바깥에 안 나갔다.
5. 저장소 밖 빈 디렉터리에 `tars-<ver>-x86_64.iso`로 복사하고 `shasum -a 256 … > SHA256SUMS`.
6. `git push origin v<ver>` →
   `gh release create v<ver> <iso> SHA256SUMS --title "TARS <ver>" --notes-file NOTES.md --verify-tag --latest`.
   새 빈 디렉터리에 `gh release download v<ver>` 후 `shasum -a 256 -c SHA256SUMS`가 `OK`인지 본다.
7. 소개 페이지 — `gh-pages`의 `data.js` `releases`에 한 줄(`site/README.md`의 "릴리스를 냈을 때").

## 재사용할 사실

- ISO 하나가 BIOS · UEFI 겸용 hybrid라 아키텍처별 · 펌웨어별로 나눌 것이 없다. 이름의 `x86_64`는 arm64 빌드가 없다는 표시다.
- `make iso` 끝의 `No active partition found` · `Reminder: … limine-bios.sys`는 `limine bios-install`의 평소 출력이다.
- 0.1.0 ISO 안에는 버전이 없다 — 그 이미지는 ISO 파일 이름과 sha256만이 버전을 말한다. BV(2026-10-20) 뒤의 빌드는
  `tars-config version`과 부팅 로그 첫 줄 `tars-init: starting as PID 1 (TARS <ver>)`이 말한다.
- 소개 페이지의 숫자 칸 "끝낸 서브프로젝트"는 `timeline.length`다. 그래서 릴리스는 `timeline`이 아니라 별도 `releases`에
  두고, 작업 내역에는 섞어 그리되(`RELEASE` 표시, 같은 날이면 위) 수에는 안 넣는다.

관련: [[project_render_speed]] (0.1.0이 담은 마지막 서브프로젝트), [[feedback_push_policy]]
