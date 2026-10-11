---
name: project_release
description: "첫 공개 버전 TARS 0.1.0(2026-10-11) — tag v0.1.0 = 0a6d4bc, GitHub release에 tars-0.1.0-x86_64.iso와 SHA256SUMS. x86_64 ISO 하나만 낸다. 배포 절차(make iso → QEMU smoke → 이름 바꿔 해시 → annotated tag → gh release create → 내려받아 대조)와 소개 페이지의 releases 배열. 시스템 안에는 아직 버전 표시가 없다"
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

## 배포 절차 (다음 버전도 이대로)

1. 트리가 clean이고 그 커밋에서 루트 게이트가 PASS였는지 본다. 게이트를 릴리스 때 다시 돌리지는 않았다(0.1.0).
2. `make iso` — 입력 해시가 같으면 kernel · init · terminal · initrd를 건너뛰고 ISO만 다시 조립한다(0.1.0에서 8초).
   `out/tars.iso`가 이미 있어도 어느 트리의 것인지 모르므로 다시 만든다.
3. 호스트 QEMU smoke — `qemu-system-x86_64 -m 1024 -cdrom out/tars.iso -display none -serial file:<log>`를 90초 띄우고
   `tars-init: starting as PID 1` · `terminal: grid` · `spawned child … fish`가 있고 `Kernel panic`이 0인지 본다.
   설정 디스크를 안 붙여 처음 받은 사람과 같은 기본값 경로를 밟는다.
4. 저장소 밖 빈 디렉터리에 `tars-<ver>-x86_64.iso`로 복사하고 `shasum -a 256 … > SHA256SUMS`.
5. `git tag -a v<ver> <커밋> -m …` → `git push origin v<ver>` →
   `gh release create v<ver> <iso> SHA256SUMS --title "TARS <ver>" --notes-file NOTES.md --verify-tag --latest`.
6. 새 빈 디렉터리에 `gh release download v<ver>` 후 `shasum -a 256 -c SHA256SUMS`가 `OK`인지 본다.
7. 소개 페이지 — `gh-pages`의 `data.js` `releases`에 한 줄(`site/README.md`의 "릴리스를 냈을 때").

## 재사용할 사실

- ISO 하나가 BIOS · UEFI 겸용 hybrid라 아키텍처별 · 펌웨어별로 나눌 것이 없다. 이름의 `x86_64`는 arm64 빌드가 없다는 표시다.
- `make iso` 끝의 `No active partition found` · `Reminder: … limine-bios.sys`는 `limine bios-install`의 평소 출력이다.
- 시스템 안에는 버전이 없다 — `tars-config`에 버전을 넣는 일은 HANDOFF "다음 후보"의 TODO. 그 전까지는 ISO 파일 이름과
  sha256만이 버전을 말한다.
- 소개 페이지의 숫자 칸 "끝낸 서브프로젝트"는 `timeline.length`다. 그래서 릴리스는 `timeline`이 아니라 별도 `releases`에
  두고, 작업 내역에는 섞어 그리되(`RELEASE` 표시, 같은 날이면 위) 수에는 안 넣는다.

관련: [[project_render_speed]] (0.1.0이 담은 마지막 서브프로젝트), [[feedback_push_policy]]
