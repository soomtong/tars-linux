---
name: project_mise
description: "mise 지원(MI-M0~M1, 2026-11-03 끝남) — 사용자가 공식 mise.run으로 ~/.local/bin에 깔고 mise use -g node@lts. initrd에는 안 싣는다(176MB). 기본 이미지에 더한 도구 0(PM-M0와 BT의 libatomic이 이미 덮었다), gpg 검증은 mise 안에서 끝난다. M1: 시스템 rc 셋이 ~/.local/bin/mise가 있을 때만 mise activate. 함정 — 콘솔 셸에는 XDG_DATA_HOME=/config/xdg가 있고 화면 셸에는 없다, mise.run은 /tmp(tmpfs)에 약 230MB를 둬 512MB에서 굳는다, activate는 mise를 셸 함수로 정의한다, make quick은 추적 전 파일을 안 본다"
metadata:
  node_type: memory
  type: project
---

# Mise (MI)

design은 `docs/specs/2026-11-03-tars-mise-design.md`, plan은 `docs/plans/2026-11-03-tars-mise-mi-m0.md` · `-mi-m1.md`. PM(Homebrew)
다음으로 사용자가 골랐다. 사용자가 정한 넷(2026-11-03): initrd에 안 싣는다, 설치 길은 공식 `mise.run`만, 게이트 런타임은
`node@lts`, activate 자리는 M0 실측 뒤 — 그리고 M1에서 "시스템 rc가 activate"를 골랐다.

## 결정

- 기본 이미지에 더한 도구는 0이다(design 결정 1). `mise.run`이 부르는 것(`ldd` · `tar` · `sha256sum` · `curl`)은 PM-M0이, node의
  `NEEDED` 여덟은 PM 결정 7(glibc 통째로)과 BT의 `libatomic`이 이미 실었다. `zstd`가 없어 `.tar.gz`로 받는 것이 정상 경로다.
- node의 gpg 검증은 mise가 내장 OpenPGP로 한다 — 게스트에 `gpg`가 없어도 검증이 켜진 채로 선다.
- 시스템 rc 셋(PM-M1의 자리)이 `$HOME/.local/bin/mise`가 있을 때만 `mise activate <셸>`을 부른다. brew 블록 다음, fish는
  `/etc/fish/conf.d/mise.fish`. activate가 `~/.local/bin`도 PATH에 넣는다. 두 번 activate는 해가 없다.
- 체인 `mise/check.sh`(스물일곱째, 라벨 `MI-M0`)는 바깥 망 둘째 체인이다(mise.run · mise.jdx.dev · github.com · nodejs.org 사전
  확인). qemu64 · 1GiB, 부팅 3만 monitor 45500(화면에 `node --version`).

## 함정

1. 콘솔 셸(init의 환경)에는 `XDG_DATA_HOME=/config/xdg`가 있고 화면 셸에는 없다(terminal의 `buildAccount`가 뺀다). XDG를 따르는
   프로그램을 콘솔에서 `setpriv`로 사용자로 돌리면 root 자리에 쓰려다 막힌다 — 체인은 `env -u XDG_DATA_HOME`.
2. 설치 스크립트의 `mktemp`는 tmpfs `/tmp`, 곧 RAM이다. `mise.run`은 받은 것과 푼 것(약 230MB)을 함께 두어 512MB에서 굳는다.
   1GiB는 Homebrew와 같은 요구라 고치지 않았다(`carryover.md`의 MI 절).
3. activate는 `mise`를 셸 함수로 정의한다. bash · zsh의 `command -v mise`는 이름을 찍는다 — `type -P` · `whence -p`로 묻는다.
4. `mise doctor`의 `failed to load settings`는 doctor가 자식으로 `mise`를 이름으로 부르는데 PATH에 없을 때 난다.
5. `make quick`(`quick_check.sh`)은 `git ls-files`로 고른다. 새 `.sh`는 `git add` 뒤에야 shellcheck에 걸린다.
6. 바깥 바이너리의 `NEEDED`는 컨테이너에서 tarball을 받아 `readelf -d`로 먼저 읽으면 체인 한 판을 아낀다.

숫자는 design의 실측 1~10과 M1-1~6. 남긴 것은 `carryover.md`의 MI 절(512MB). 관련: [[project_package_manager]] ·
[[project_home_partition]].
