# LT-M0 — ping · hostname · DMI · Landlock · sudo timestamp

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-little-things-design.md`(결정 1~5)
Status: 진행 중. 결정은 사용자 위임(2026-11-11).

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `2814b47`).

1. 게스트 도구의 길: `devcontainer/Dockerfile`이 `.deb`를 amd64 sysroot에 풀고, `kernel/guest_tools.sh`의 `GUEST_TOOLS`가
   `sysroot 경로:initrd 경로` 한 줄로 고른다. `tools/check.sh`가 그 목록을 source해 검사한다. Dockerfile을 고치면 이미지를 다시
   굽는다(`./devcontainer/image.sh build`) — 태그가 바뀌고 push 뒤 CI가 같은 것을 굽는다.
2. 문자열 값 키의 선례는 `timezone`(`config.zig`의 `Timezone` · parse · seed 견본 · `config shell=` 로그 줄, `reload.zig`의
   `groupOf` — 필드를 더하고 빠뜨리면 컴파일 에러, `config_edit` · `config_edit_test`의 키 수 · hint, `reload_test`). CO-M1 plan의
   결과 절이 "키를 더할 때 게이트가 찾은 짝 셋"을 적어 두었다 — argv 리터럴은 이번에 해당 없다(terminal argv에 안 든다).
3. `config shell=…` 로그 줄은 여러 체인이 정규식으로 본다. 새 칸은 줄 끝에 더한다(앞 칸을 보는 판정이 그대로 통과한다).
4. sudoers는 `kernel/make_initrd.sh`의 heredoc 하나다. `home/check.sh`의 판정 8이 sudo를 본다 — 비밀번호를 파이프로 주는 sudo는
   언제나 `-k`를 쓴다(그 체인의 주석). `timestamp_type=global`은 `-k`가 지우는 대상도 전역으로 바꾼다 — 판정이 그대로 통과하는지 본다.
5. 커널 옵션은 `kernel/.config`(커밋된 해소본)를 고친다. `kernel/build.sh`가 `olddefconfig` 뒤 빌드한다.

## Task 1 — 커널(lead)

`CONFIG_DMIID=y`, `CONFIG_SECURITY=y` · `CONFIG_SECURITYFS=y` · `CONFIG_SECURITY_LANDLOCK=y` · `CONFIG_LSM="landlock"`.
`scripts/config`로 켜고 `olddefconfig`로 해소한 뒤 `=y`를 센다 — 따라 켜진 것이 있으면 적는다. bzImage 크기를 앞뒤로 잰다.

## Task 2 — ping

- Dockerfile: `iputils-ping:amd64`를 sysroot에(가까운 층에 붙인다). `guest_tools.sh`에 `usr/bin/ping:usr/bin/ping`과 까닭 주석.
- init: 부팅에 `/proc/sys/net/ipv4/ping_group_range` ← `0 2147483647`. 성공은 조용히, 실패는
  `tars-init: cannot open ping to users (errno N)`. 자리는 망 데몬을 띄우기 전 어디든.
- 체인 `tools`: 사용자 없는 부팅의 root라 권한 판정은 못 한다 — `ping -c 1 -W 2 127.0.0.1`이 rc 0이고
  `cat /proc/sys/net/ipv4/ping_group_range`가 `0	2147483647`인지 본다. uid 1000의 ping은 `home` 체인(사용자가 있는 부팅)에 판정 하나.

## Task 3 — hostname

- `config.zig`: `Hostname`(길이 63, `parse`는 design 결정 2의 규칙, 기본 `tars`), 필드 `hostname`, 파서 갈래
  (`unknown hostname '{s}', falling back to {s}`), seed 견본 두 줄(`# hostname: …` · `hostname={s}`), `config shell=` 줄 끝에 `hostname=`.
- `reload.zig`: `next_spawn` 갈래. `main.zig`: 부팅(`loadConfig` 뒤 · 자식을 띄우기 전)과 reload에서 `applyHostname` —
  `sethostname`(syscall), `/etc/hostname`, `/etc/hosts`(localhost 줄 + `127.0.1.1 <이름>`). 로그 `tars-init: hostname NAME`.
- `config_edit` · `tars-config`: 키 목록 · hint(`a name: a-z 0-9 -, up to 63`) · 거절 글자. 검사: `config_test`(옳은 값 · 틀린 값 일곱 —
  빈 값 · 64자 · 대문자 · `_` · 앞 `-` · 뒤 `-` · 점), `config_edit_test`(키 수 · seed 글자), `reload_test`.
- `devlayer/files/server/etc/tars/server/common.sh`의 CN은 그대로 둔다(이제 이름이 `tars`이거나 사람이 준 것이다).
- 체인: `config`(또는 키를 보는 체인)에서 기본 부팅의 `tars-init: hostname tars` · `uname -n`, 설정 디스크에 `hostname=air`를 둔 부팅의
  `uname -n` = `air`와 `getent hosts air`(없으면 `grep air /etc/hosts`). `tars-config set hostname=Bad`의 거절.
- 안내: `docs/help/config.md`에 한 줄(키 이름 · 규칙 · reload).

## Task 4 — sudo timestamp

- `make_initrd.sh`의 sudoers에 `Defaults timestamp_type=global`과 주석(까닭 · 15분 그대로).
- 체인 `home`: 판정 8 가운데 — 한 tty에서 비밀번호로 `sudo -v`가 통한 뒤 다른 tty(화면의 셸과 시리얼 콘솔이 서로 다른 tty다)에서
  `sudo -n id -u`가 `0`. 두 tty를 쓰는 판정이 체인 구조에 안 맞으면 `sudoers` 내용 판정으로 물러서고 그 까닭을 보고한다.
  기존 판정 8의 `-k`가 여전히 맞는지 읽는다.

## Task 5 — 판정 줄 둘(커널)

체인 `tools`(또는 `boot`): 시리얼 로그의 `landlock: Up and running`, `cat /sys/class/dmi/id/sys_vendor`가 `QEMU`.

## Task 6 — 게이트(lead)

`make quick` · 컨테이너 init `zig build test` · 체인 tools · home · config 단독 · 루트 게이트(CE와 함께).

## Task 7 — 닫기

design Status · 이 plan의 결과 · `completed.md` · `carryover.md`의 다섯 항목 지우기 · 기억 한 파일 · `running-tars.md`(해당 줄) · 소개 페이지.

## 결과

(구현 뒤 적는다.)
