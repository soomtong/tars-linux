---
name: project_package_manager
description: "패키지 매니저(PM-M0~M1, 2026-11-03 끝남) — Homebrew를 공식 install.sh 그대로, 사용자가 직접 친다. TARS는 막히는 자리만 푼다. M0: usrmerge /bin, 층 19 도구, glibc 통째로, /etc/os-release, init의 LANG=C.UTF-8. M1: 시스템 rc 셋의 shellenv, libstdc++를 실체+SONAME 링크로. 함정 — sudo -S -k -v는 timestamp를 안 남긴다, TCG qemu64에 SSSE3가 없다, 바깥 바이너리는 glibc 전체를 가정한다, 로케일 변수 없는 fish는 LC_CTYPE=en_US.UTF-8을 export한다, Homebrew는 libstdc++ 버전을 파일 이름에서 읽어 낮으면 gcc를 붙인다"
metadata:
  node_type: memory
  type: project
---

# Package Manager (PM)

design은 `docs/specs/2026-11-03-tars-package-manager-design.md`, plan은 `docs/plans/2026-11-03-tars-package-manager-pm-m0.md` ·
`-pm-m1.md`. HP가 `/home`(ext4)과 sudo를 가진 사용자를 세운 뒤 이어서 시작했다. 사용자가 정한 셋(2026-11-03): Homebrew, 사용자가
공식 `install.sh`를 직접 친다(TARS는 감싸지 않는다), 게이트는 실제 망으로 끝까지 간다.

## 결정

- prefix는 기본값 `/home/linuxbrew/.linuxbrew`, TARS는 미리 안 만든다(design 결정 1).
- `/bin`은 `usr/bin`으로의 링크(usrmerge, 결정 2). `install.sh`가 `/bin/mkdir` 등을 절대 경로로 부른다.
- 기본 이미지에 넣는 기준은 "install.sh와 brew가 실제로 부르는 것"(결정 3). 컴파일러는 안 넣는다(결정 4). `file`은 끝까지 안 불렸다.
- glibc는 통째로(결정 7), `/etc/os-release`(결정 8, `ID_LIKE` 없음), `LANG=C.UTF-8`은 init의 환경 블록(결정 9) — 둘은 사용자가
  "넣어요"로 정했다.
- shellenv는 시스템 rc 셋(`/etc/bash.bashrc` · `/etc/zsh/zshrc` · `/etc/fish/conf.d/homebrew.fish`)이 brew가 있을 때만, 셸 이름을
  인자로, uid와 무관하게 부른다(결정 5). 두 번 eval은 빈 출력이다.
- libstdc++만 실체(`libstdc++.so.6.0.33`) + SONAME 링크로 싣는다(결정 10, 사용자가 "libstdc++만"을 골랐다).
- 체인 `pm/check.sh`는 바깥 망에 기대는 첫 체인이다. 사전 확인으로 망 실패를 이름 붙이고, 이 체인만 `-cpu max` · `-m 1024`,
  최소 디스크, 부팅 3만 monitor 45499(화면에 `hello`).

## 함정

1. `sudo -S -k -v`는 비밀번호를 묻되 timestamp를 남기지 않는다. `sudo -k`를 먼저 혼자 친다.
2. QEMU TCG의 기본 CPU에는 SSSE3가 없고 Homebrew는 그것을 요구한다.
3. `copy_lib_deps`는 우리 바이너리의 NEEDED만 따라간다. 바깥 바이너리는 libdl 같은 glibc stub을 부른다.
4. 로케일 변수가 없는 환경의 fish는 `LC_CTYPE=en_US.UTF-8`을 export하고, 그것이 LANG보다 앞서 아래 프로세스의 로케일을 깬다.
   initrd 트리를 amd64 컨테이너(OrbStack Rosetta)에 풀고 `chroot`하면 QEMU 없이 재현된다.
5. 512MB 게스트는 initrd 278MB가 상주해 brew의 ruby(약 150MB)가 OOM이다.
6. Homebrew는 시스템 libstdc++의 버전을 realpath 파일 이름에서 읽고, CI 기준(6.0.33)보다 낮으면 모든 formula에 gcc(463MB)를
   붙인다. SONAME 이름으로만 실은 라이브러리는 바깥 프로그램에게 "버전 모름"이다.
7. check.sh 진입 검사는 줄 머리의 `|| ! grep -q`도 `| grep -q`로 읽는다 — `if ! { A && B; }`로 쓴다.

숫자는 design의 실측 1~8과 실측 M1-1~6. 남긴 것은 `carryover.md`의 PM 절(Landlock, 다음 후보 매니저).
