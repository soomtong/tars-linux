# LT-M0 — ping · hostname · DMI · Landlock · sudo timestamp

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-little-things-design.md`(결정 1~5)
Status: 끝났다(2026-11-12). 결정은 사용자 위임(2026-11-11).

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

구현 `903bd81`(커널) · `3c71b5f`(나머지, 서브에이전트) · `0e1b888` · pm 한 줄. plan과 다른 자리:

1. reload 갈래는 `next_spawn`이 아니라 `now`다 — terminal argv에 안 들고 `sethostname`이 곧바로 먹는다(design 결정 2를 고쳤다).
2. 기본 이름 `tars`가 프롬프트를 두 칸 줄여(`root@(none) ~#` → `root@tars ~#`) plan에 없던 체인 열하나의 프롬프트 판정과 칸 수 둘
   (cursor `col=15 → 13`, copy `col 20 → 18`)을 고쳤다. pm 체인 한 자리는 놓쳤고 루트 게이트가 찾았다.
3. `config.MAX_FILE` 4096 → 8192. seed에 두 줄이 늘자 설치기의 `user=` 꼬리와 합쳐 넘었다(`config.save`가 실패해 설치기가 `tars.conf`를
   못 쓴다). CO-M1의 seed도 32자 사용자 이름이면 1바이트 넘쳤다 — `config_test`에 그 검사를 더했다.
4. sudo 판정(home 8g)은 두 tty로 실제 동작을 본다 — 시리얼(ttyS0)에서 `sudo -v` 뒤, `sudo -u hpuser`가 주는 새 pty에서 `sudo -n id -u`가 0.
5. 체인에 `getent`가 없어 `grep air /etc/hosts`.
6. 해소본이 따라 켠 것: `SECURITY_NETWORK` · `SECURITY_PATH`(Landlock의 select). `INTEGRITY`는 `default y`라 껐다.

첫 판에 빨갰던 판정 셋 — 모두 게이트 쪽이었다:
- tools 검사 24와 config의 `/etc/hosts` 판정: 화면 dump는 탭이 건너뛴 칸을 싣지 않아 `0\t2147483647`이 `02147483647`,
  `127.0.1.1\tair`가 `127.0.1.1air`로 붙는다. `[[:space:]]+`를 `*`로.
- config 체인의 `if ! grep -q … || ! grep -q …`가 루트 게이트의 입구 검사(일찍 끝나는 grep)에 걸렸다 — 체인 단독 실행은 그 검사를
  안 지난다. 새 체인 줄은 lessons의 입구 검사 한 줄에 먼저 대 본다.

잰 것: bzImage 11,437,056 → 11,486,208 B(+48KiB). `ping`은 새 라이브러리 0개(libcap · libidn2는 initrd에 있었다).
게이트가 덤으로 본 것: pm 체인의 `brew install hello`가 `Sandbox unavailable` 대신 `Landlock ABI: 7`과
`Landlock ABI 10 or later is required to deny all network access; found ABI 7. Applying the network restrictions supported by this kernel.`를
찍었다 — Homebrew의 샌드박스가 섰다(망 전부를 막는 것은 ABI 10부터라 6.18에서는 일부만).

게이트: 컨테이너 init `zig build test` 47/47, `make quick` PASS, 체인 tools · home · config 단독 PASS.
루트 게이트(2026-11-12, `0e1b888`의 코드): 32/33 — 34분 51초(prebuild 344초 + lanes 1,614초), 잘린 줄 0, `out/gate-logs/20261111-162704`. 빨간 하나는 pm(PM-M0)의 화면 판정이 옛 프롬프트 `tars@(none) ~>`를 기다린 것(LT-M0이 놓친 자리)이고, 그 한 줄을 고친 뒤 pm 단독이 초록이었다. 커널 · init · initrd는 그 사이 바뀌지 않아 게이트를 통째로 다시 돌리지 않았다.
