---
name: project_package_manager
description: "패키지 매니저(PM, 2026-11-03~) — Homebrew를 공식 install.sh 그대로, 사용자가 직접 친다. TARS는 막히는 자리만 푼다. M0: usrmerge /bin, 층 19 도구, glibc 통째로, /etc/os-release, init의 LANG=C.UTF-8. 함정 — sudo -S -k -v는 timestamp를 안 남긴다, TCG qemu64에 SSSE3가 없다, 바깥 바이너리는 glibc 전체(libdl stub)를 가정한다, 로케일 변수 없는 fish는 LC_CTYPE=en_US.UTF-8을 export한다"
metadata:
  node_type: memory
  type: project
---

# Package Manager (PM)

design은 `docs/specs/2026-11-03-tars-package-manager-design.md`, plan은 `docs/plans/2026-11-03-tars-package-manager-pm-m0.md`.
HP가 `/home`(ext4)과 sudo를 가진 사용자를 세운 뒤 이어서 시작했다. 사용자가 정한 셋(2026-11-03): Homebrew, 사용자가 공식
`install.sh`를 직접 친다(TARS는 감싸지 않는다), 게이트는 실제 망으로 끝까지 간다.

## 결정

- prefix는 기본값 `/home/linuxbrew/.linuxbrew`, TARS는 미리 안 만든다(design 결정 1).
- `/bin`은 `usr/bin`으로의 링크(usrmerge, 결정 2). `install.sh`가 `/bin/mkdir` 등을 절대 경로로 부른다.
- 기본 이미지에 넣는 기준은 "install.sh와 brew가 실제로 부르는 것"(결정 3). 컴파일러는 안 넣는다(결정 4).
- glibc는 통째로(결정 7), `/etc/os-release`(결정 8, `ID_LIKE` 없음), `LANG=C.UTF-8`은 init의 환경 블록(결정 9) — 둘은 사용자가
  "넣어요"로 정했다.
- 체인 `pm/check.sh`는 바깥 망에 기대는 첫 체인이다. 사전 확인으로 망 실패를 이름 붙이고, 이 체인만 `-cpu max` · `-m 1024`다.

## 함정 (M0)

1. `sudo -S -k -v`는 비밀번호를 묻되 timestamp를 남기지 않는다. `sudo -k`를 먼저 혼자 친다.
2. QEMU TCG의 기본 CPU에는 SSSE3가 없고 Homebrew는 그것을 요구한다.
3. `copy_lib_deps`는 우리 바이너리의 NEEDED만 따라간다. 바깥 바이너리는 libdl 같은 glibc stub을 부른다.
4. 로케일 변수가 없는 환경의 fish는 `LC_CTYPE=en_US.UTF-8`을 export하고, 그것이 LANG보다 앞서 아래 프로세스의 로케일을 깬다.
   initrd 트리를 amd64 컨테이너(OrbStack Rosetta)에 풀고 `chroot`하면 QEMU 없이 재현된다.
5. 512MB 게스트는 initrd 278MB가 상주해 brew의 ruby(약 150MB)가 OOM이다.

숫자는 design의 실측 1~8.
