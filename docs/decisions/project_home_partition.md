---
name: project_home_partition
description: "홈 파티션(HP-M0~M2, 2026-11-02~03) — p3 ext4 tars-home을 /home에, 설치 때 계정 하나(uid 1000, 기본 tars · tars-linux), 화면 셸은 사용자, /config 쓰기는 Debian sudo. 함정 — pam_unix 1.7은 setuid 호출자에게 unix_chkpwd를 요구한다(없으면 맞는 비밀번호도 Sorry), 사용자 없는 부팅에도 /etc/shadow가 있어야 root의 sudo가 된다, sudo timestamp가 남으면 파이프의 첫 줄이 명령에게 간다"
metadata:
  node_type: memory
  type: project
---

# Home Partition (HP)

design은 `docs/specs/2026-11-02-tars-home-partition-design.md`, plan은 `docs/plans/2026-11-02-tars-home-partition-hp-m0.md` ·
`-m1.md` · `-m2.md`. 사용자가 "`/config`는 ext2로 두되 홈과 패키지 매니저 자리는 ext4가 맞지 않나"를 내서 시작했다. 파티션 크기
(768 · 256MiB · 나머지), 최소 4GiB, 이름을 설치 때 묻기, 기본 `tars` · `tars-linux`를 사용자가 정했다. Homebrew 설치 자체는 다음
서브프로젝트 PM이다 — 이 서브프로젝트는 그 앞의 둘(디스크 위의 `/home`, root가 아닌 사용자)이다.

## 무엇이 섰나

- M0: 커널 `CONFIG_EXT4_FS=y`(+2.9%), 설치기가 p3 `tars-home`(ext4, `-e remount-ro`)을 굽고 init이 라벨 전체로 찾아 `/home`에
  async · `nosuid,nodev`로 붙인다. 설정 탐색(`tars-` 접두사)은 `tars-home`을 뺀다.
- M1: 설치기가 이름 · 비밀번호를 묻고(`--yes`면 기본값) `mkpasswd -m yescrypt -s`로 해시해 p2에 `tars.conf`(`user=`) · `shadow`,
  p3에 `/home/<이름>`. init이 부팅마다 tmpfs `/etc`의 passwd · group · shadow에 사용자를 넣고 홈에 dotfile seed를 깐다. terminal이
  `forkpty` 자식에서 권한을 내린다(pty는 fd 0의 `fchown`). 시리얼 셸 · ssh는 root.
- M2: Debian `sudo`(doas는 Homebrew의 `sudo -v` · `-l`이 없다). sudoers는 initrd의 정적 파일 하나에 `%sudo`(gid 27), PAM은
  `pam_unix` + `unix_chkpwd`. `tars-config`의 쓰기 · 소켓 실패가 `EACCES`면 `try: sudo tars-config <인자>`와 77, `tars-service`도 같다.
  control 소켓은 root 0600 그대로. `sudo tars-config passwd`가 `/config/shadow`와 `/etc/shadow`를 함께 바꾼다.
- 체인 스물다섯째 `home/check.sh`(판정 1~10, 8은 8a~8f). 화면 셸에 키를 안 치고 그 pid의 `/proc`을 root가 읽으며, 사용자의 일은
  `setpriv --reuid=1000`이다.

## 배운 것 — 다시 조사하지 말 것

- `pam_unix`(Linux-PAM 1.7)는 real uid가 0이 아니면 euid가 0이어도 `/usr/sbin/unix_chkpwd`로 확인한다. 없으면 sudo는 맞는
  비밀번호에도 `Sorry, try again` 한 줄뿐이다. `0755 root`로 충분하다(부르는 쪽이 sudo뿐, shadow는 root 600).
- 게스트에는 strace · syslogd · `getent` · busybox가 없고 `nc`는 `-U`를 모른다. PAM처럼 이유를 syslog에만 말하는 것은 일회용
  amd64 Debian 컨테이너(`--platform linux/amd64`, 조사 전용 — 빌드 이미지 규칙과 별개)에서 같은 설정을 재현해 가른다. 조건을
  하나씩 되돌리는 시험은 상태가 겹치면 거짓을 낸다 — 조합 표가 낫다. init의 정적 바이너리(`tars-config` 등)는 그 컨테이너에서 그대로 돈다.
- sudo는 hostname `(none)`이면 매번 `unable to resolve host`를 찍는다 — sudoers `!fqdn`.
- sudo는 한 번 맞으면 tty에 15분 timestamp를 남긴다. 파이프로 비밀번호를 주는 스크립트는 늘 `-k`(아니면 첫 줄이 명령에게 간다).
  `-S`의 프롬프트는 개행 없이 stderr로 가니 `2>&1`이면 `-p ""`.
- 게스트에 `/usr/bin/true` · `sha256sum`이 없다(fish의 `true`는 내장). 실패의 종료 코드만 보지 말고 이유 줄까지 본다.
- 설치기와 `tars-config`는 서로를 import하지 않는다 — 같은 일(비밀 읽기 · 도구 부르기)을 각자 가진다. 함께 쓰는 것은 순수한
  `account.zig`뿐이다.
- 비밀번호 프롬프트는 echo를 끈 뒤에 찍는다(거꾸로면 보자마자 친 글자가 화면에 찍히고 `.FLUSH`가 버린다).

## 남은 것

`docs/guides/carryover.md`의 HP 절 — 부팅 뒤 꽂은 사운드 노드의 권한, `ping`, 사용자 셸 히스토리 자리, hostname, sudo
timestamp의 범위. 실기에서 볼 것은 HANDOFF의 "사용자가 확인할 것".

관련: [[project_config_fs_ext2]] · [[project_disk_install]] · [[project_kernel_upgrade]] · [[project_measuring_tool_cost]]
