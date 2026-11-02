# HP-M1 — 설치 때 계정 하나를 만들고 화면의 셸을 그 사용자로 띄운다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-02
> `653bd75` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 3(뒤 절반) · 5 · 6(해시까지) · 7 · 8 · 12와 위험 2 · 4 · 7 · 9 · 10을 넣는다. 끝나면 새 설치가 이름 · 비밀번호를
묻고(`--yes`면 `tars` · `tars-linux`), p2에 `user=`가 담긴 `tars.conf`와 `/config/shadow`를, p3에 `/home/<이름>`을 만든다.
설치된 디스크로 뜨면 init이 passwd · group · shadow에 그 사용자를 더하고 홈에 dotfile seed를 깔며, terminal의 셸은 uid 1000으로
홈에서 뜬다. `/home`이 없는 부팅(ISO · HP 이전 디스크)은 지금 그대로 root 셸이다. 시리얼 콘솔 셸은 어느 쪽이든 root로 남는다.
sudo는 M2다 — M1이 끝난 기계에서 사용자는 `/config`에 못 쓰고 그 사실을 안다.

Architecture: 순수한 층에 계정의 규칙을 먼저 모은다 — 이름 검증과 passwd · group · shadow 줄 짓기(`init/src/account.zig`),
uid · gid 상수와 terminal에 넘길 칸(`shared/screen_args.zig`), `tars.conf`의 `user=`(`config.zig`). 그 위에 시스템 콜 층 셋이
얹힌다. 설치기는 쓰는 쪽(질문 → 해시 → p2 · p3에 쓰기), init은 매 부팅 tmpfs `/etc`에 짓는 쪽, terminal은 `forkpty` 자식에서
권한을 내리는 쪽이다. 세 프로그램이 같은 상수와 같은 검증 함수를 써야 "설치는 됐는데 셸이 root로 뜬다"의 원인이 갈래로
안 늘어난다.

## 이 plan이 정한 것 (design에 없던 자리)

1. 시리얼 콘솔 셸은 root로 남는다. 게이트의 길이고 화면이 죽었을 때의 복구 길이다. 물리 접근이 곧 root인 것은 지금과 같다.
2. 해시는 Debian `whois`의 `mkpasswd -m yescrypt -s`이고 비밀번호는 stdin으로 준다(위험 2 닫음). init은 musl 정적이라 libcrypt를
   못 부르고, 설치기도 init과 같은 빌드다. `libcrypt1:amd64`는 이미 sysroot에 있다(sshd). 컨테이너 이미지가 바뀐다.
3. 해시는 YES 뒤 · sfdisk 앞에 만든다. 디스크를 지운 뒤 `mkpasswd`가 실패하면 늦다(`prepareConf`와 같은 규칙).
4. 설치기가 `tars.conf` 전체를 `config.save`로 쓴다(`user=` 한 줄만이 아니라). 그래야 첫 부팅에도 주석 달린 파일이 있고
   진실의 출처가 `Config` 하나로 남는다. 그 대가로 설치된 첫 부팅의 `created /config/tars.conf`가 사라진다 — install 체인
   판정 7 · 16이 바뀐다(Task 7).
5. `user=`는 `tars-config set`이 거절한다. 이름을 바꾸면 홈 · shadow와 어긋난다 — 바꾸는 길은 `--wipe`다.
6. 사용자의 보조 그룹은 `audio`(29) 하나이고 `tty`(5) 그룹을 group 파일에 늘 둔다. devpts를 `gid=5,mode=620,ptmxmode=666`로 붙인다.
7. 상태 줄에 `ROOT` 칸은 넣지 않는다(위험 7). bash · zsh · fish의 기본 프롬프트가 이미 root를 `#`로 가르고, ISO 부팅은 늘 root라
   칸이 거의 늘 켜진다. 상태 줄 픽셀을 보는 체인의 기대값도 다 바뀐다. 로그 한 줄로 알린다.
8. 게이트가 사람의 길(질문 셋)도 탄다. 시리얼 콘솔이 tty라 echo 끄기까지 진짜로 지나간다 — design 위험 8의 "게이트가 못 본다"는
   이 plan에서 고친다. install 체인은 `--yes`(기본값), home 체인은 질문 길(다른 이름)이다.

## 무엇을 재나 (design "실측 (M1)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 7 | `mkpasswd` 바이너리와 `DT_NEEDED`, 이미지 · initrd 증가, TCG에서 yescrypt 한 번의 시간 | 위험 2 |
| 8 | 설치된 첫 부팅의 init 로그 줄(계정 · seed)과 늘어난 부팅 시간 | 결정 7 |
| 9 | 사용자 셸의 `/proc/<pid>/status`(Uid · Gid · Groups) · environ · cwd, pty slave의 `stat` | 결정 8 · 위험 4 |
| 10 | 사용자로 쳐서 막히는 목록(위험 10): `aplay -l` · `ping -c1 127.0.0.1` · `dmesg` · `git config --global` · `tars-config get shell` · `ls /config` · `cat /config/shadow` | 위험 10 |
| 11 | 사용자 fish · zsh가 홈에 히스토리를 쓰는 자리, zoxide가 `~/.local/share`를 스스로 만드는가 | 결정 12 |

## Task 0: 이미지 — `mkpasswd` · `setpriv`

- `devcontainer/Dockerfile`의 sysroot 목록(`openssh-server:amd64` 근처)에 `whois:amd64`. 이미지 태그가 바뀐다(`image.sh`의
  sha256 앞 12자) — ghcr에 없으니 로컬로 굽는다. BT 때처럼 몇 분 걸린다. 다른 기계는 `docker rmi tars-devcontainer &&
  make container`(HANDOFF에 적는다).
- `kernel/guest_tools.sh`에 두 줄. `usr/bin/mkpasswd:usr/bin/mkpasswd`(설치기가 부른다), `usr/bin/setpriv:usr/bin/setpriv`
  (util-linux는 이미 있다. 게이트와 사람이 root 셸에서 "사용자로 한 번" 칠 길 — `setpriv --reuid=1000 --regid=1000
  --init-groups <cmd>`). 주석에 HP-M1과 쓰임을 적는다. `tools/check.sh`가 이 목록을 그대로 본다.
- 측정 7: `readelf -d`로 `DT_NEEDED`, initrd 크기 전후, 게스트에서 `time sh -c 'echo x | mkpasswd -m yescrypt -s'`.

## Task 1: 순수한 층

### `shared/screen_args.zig`

- 상수: `USER_UID: u32 = 1000`, `USER_GID: u32 = 1000`, `TTY_GID: u32 = 5`, `AUDIO_GID: u32 = 29`. 주석에 design 결정 5 · 8과
  "init(passwd 줄) · 설치기(chown) · terminal(setuid)이 이 하나를 본다".
- `Slot.user = 9`, `ARGC = 10`. 값은 이름이거나 `none`(root 셸). `Args.user: [*:0]const u8`, `default_user = "none"`.
  `encode` · `decode`와 `screen_args_test.zig`의 왕복 검사에 칸 하나.
- 서비스 셋의 `*_ARGV` 상수가 이 타입이라 null 하나가 늘 뿐인지 컴파일로 본다.

### `init/src/account.zig` + `account_test.zig` (새 파일)

- `validName(name) bool`: `[a-z_][a-z0-9_-]{0,31}`, 그리고 `RESERVED` = `root` · `sshd` · `messagebus` · `nobody` · `linuxbrew` ·
  `audio` · `tty` · `nogroup`(group 이름과 겹쳐도 안 된다 — 사용자 그룹을 같은 이름으로 만든다).
- `passwdLine(buf, name, shell)` → `<이름>:x:1000:1000::/home/<이름>:<shell>`.
- `groupLines(buf, name)` → 사용자 그룹 `<이름>:x:1000:`, 그리고 `audio:x:29:<이름>`으로 바꾼 audio 줄. 정적 group의 audio 줄을
  바꾸는 것은 `login.replaceRootShell`과 같은 모양의 `replaceGroupMembers`로(줄 단위 사본, 자리 모자라면 null).
- `shadowLine(buf, name, hash)` → `<이름>:<hash>:<일수>:0:99999:7:::`. 일수는 0으로 둔다(시계를 안 믿는다 — 0은 "바꿀 것"이 아니라
  `pam_unix`에서 "모름"으로 읽히는지 M2가 본다. M2 전에는 읽는 자가 없다).
- `/config/shadow`의 한 줄 `<이름>:<hash>`를 읽는 `parseShadowStore(text, name) ?[]const u8` — 이름이 다르거나 hash에 `:` · 개행이
  있으면 null.
- 단위 검사(위험 9): `tars` · `a` · `_x` · 32자 통과, `root` · `Tars` · `1abc` · `a:b` · `a b` · `../x` · 빈 줄 · 33자 · `a\n` 거절.
  passwd · group · shadow 줄의 바이트 그대로. `build.zig`의 test 목록에 더한다(`login_test` 옆).

### `init/src/config.zig`

- `Config.user: ?User` — `User`는 `[32]u8` + len(힙 없음). 파싱에서 `account.validName`이 거절하면 로그 `tars.conf user=<값> is not
  a valid user name, shell runs as root` 한 줄과 null. `timezone`처럼 자유 글자 키가 이미 있으면 그 모양을 따른다.
- `save`: `user`가 있으면 `user=<이름>` 줄과 주석 둘(`# user: set by tars-install; the shell runs as this user when /home is
  mounted` · `#   change it with tars-install --wipe, not here`). 없으면 그 키를 안 쓴다 — ISO 부팅의 seed가 바이트 하나 안 바뀌어
  config 체인들의 기대가 그대로다.
- `config_edit`: `set user=…`은 `user is set by tars-install` 줄로 거절. `config_edit_test`에 그 사례.
- `config_test`: `user=tars` · `user=root`(거절) · 키 없음.

```
(cd init && zig build test)     # 컨테이너에서
make quick
```

## Task 2: 설치기 — 질문 셋 · 해시 · p2 · p3에 쓰기

`install.zig`. 갱신(`update`)은 질문도 쓰기도 안 한다 — p2 · p3를 안 건드리는 결정 10 그대로다.

- 질문(새 설치, `!yes`일 때만). 계획 줄 뒤 · `type YES` 앞:
  - `user name [tars]: ` — `readLine`. 빈 줄이면 `tars`. `account.validName`이 거절하면 `tars-install: <값> is not a user name
    (a-z, 0-9, _ and -, up to 32; not root)` 한 줄 뒤 같은 질문. EOF면 `not confirmed; nothing was changed`.
  - `password [tars-linux]: ` — echo 끈 한 줄. `config_front.readSecret`의 termios 몇 줄을 복사한다(install은 init과 같은
    libc 없는 빌드이고 공용 모듈을 안 만드는 규칙). 빈 줄이면 기본값. 개행 · NUL이 든 값은 거절하고 다시 묻는다.
  - `type YES to continue: ` 그대로.
  - `--yes`면 질문 없이 `tars` · `tars-linux`. 계획 출력에 `  user  <이름>  (home /home/<이름>, password <default|set>)` 한 줄을
    더한다 — `--yes` 길에서도 무엇이 만들어지는지 보인다. 비밀번호 글자 자체는 어디에도 안 찍는다.
- 해시(YES 뒤 · sfdisk 앞, 확정 3): `runTool({"/usr/bin/mkpasswd", "-m", "yescrypt", "-s"}, password ++ "\n", WORK_DIR ++
  "/mkpasswd.log")` 뒤 그 로그를 읽어 `$y$`로 시작하는 한 줄을 얻고 로그를 `unlink`한다. `runTool`의 로그 open 모드를 0o600으로
  내린다(모든 도구 — 해시가 0644로 남는 자리를 없앤다). 비밀번호 버퍼는 쓰고 나서 `@memset(…, 0)`.
- p2 쓰기(mkfs 셋 뒤, `fillEsp` 앞): `WORK_DIR/config`에 ext2로 붙이고, `config.save(…/tars.conf, .{ .user = name })`, `shadow`를
  `O_CREAT|O_EXCL` 0600으로 `<이름>:<hash>\n`, `sync`, `umount`. 줄 `tars-install: wrote tars.conf (user=<이름>) and shadow`.
  설치기 root에 `configLog`를 선언해 `config.zig`의 로그가 `tars-install: `로 나가게 한다.
- p3 쓰기: `WORK_DIR/home`에 ext4로 붙이고 `mkdir <이름>` 0700 · `chown 1000:1000`, `umount`. 줄 `tars-install: made
  /home/<이름>`. `mountFs`가 data 인자 없이 되는지(ext4 기본) 그대로 쓴다.
- 실패는 어디서든 `complain` 한 줄과 1. 디스크는 이미 지워졌으니 문구에 `run tars-install <disk> --wipe again`을 붙인다.

## Task 3: init — 계정 · seed · devpts

### 계정(`main.zig` `readConfig` + `login.zig`)

`loadConfig` 뒤, seed 앞에 `setupAccount(home_mounted, cfg)`:

- `/home` 없음 → `tars-init: no tars-home disk, shell runs as root`(design 결정 3 문구). terminal 칸 `none`.
- `/home` 있고 `user` 없음 → `tars-init: no user= in /config/tars.conf, shell runs as root`. `none`.
- 둘 다 있음:
  - `/etc/passwd`에 `account.passwdLine`을 덧붙이고(`login.apply`가 root 셸을 다시 쓰는 같은 자리, 같은 셸 경로),
    `/etc/group`을 `groupLines`로 다시 쓴다.
  - `/config/shadow`를 읽어 `/etc/shadow`(0600, root)에 `root:*:…`와 사용자 줄. 없거나 못 읽으면 사용자 줄의 hash를 `!`(잠김)로
    두고 `tars-init: no password for <이름> in /config/shadow, sudo will refuse` 한 줄. 부팅은 간다.
  - `/home/<이름>`이 없으면 0700 · 1000:1000으로 만든다(디스크를 다른 도구로 비운 경우, 결정 7).
  - 줄 `tars-init: user <이름> uid 1000 home /home/<이름>`. terminal 칸에 이름.
- `make_initrd.sh`의 group heredoc에 `tty:x:5:`(사용자 없는 부팅에도 — devpts의 gid가 이름을 갖는다). 주석에 HP-M1.

### seed(결정 12)

- `config.zig`의 `seedOneFile`을 `seedOneFileAs(path, text, uid, gid)`로 넓힌다(O_EXCL로 만든 fd에 `fchown`). 옛 이름은 root용
  한 줄짜리로 남긴다.
- 사용자가 있으면 `/config`의 seed 다섯 대신 홈에: `~/.bashrc` · `~/.zshrc` · `~/.config/fish/config.fish`(`.config` · `fish`
  디렉터리도 1000 소유) · `~/.gitconfig` · `~/.vimrc`. 글자는 같은 상수다 — 단 rc seed 안에 `/config/…` 경로가 박혀 있으면
  (`rg -n '/config' init/src/config.zig`의 seed 상수) 홈 기준으로 바꿔야 하는지 그 자리에서 본다.
- `makeXdgDir`은 root 셸용으로 그대로 둔다(홈 없는 부팅). 사용자는 `~/.local/share`를 fish · zoxide가 스스로 만드는지
  측정 11이 본다 — 안 만들면 init이 `~/.local/share` 하나를 만든다.
- 사용자가 있는 부팅에도 `/config`의 root용 seed를 계속 까는가: 안 깐다. 그 부팅의 root는 시리얼 셸뿐이고 링크가 댕글링인 것이
  SC-M0의 정상 경로다. ssh(root)는 비목표 4의 자리라 지금 동작이 바뀌는지만 HANDOFF에 적는다.

### devpts(확정 6, 위험 4)

`mountDevpts`가 `mountFs`를 data 없이 부른다. `mountFs`에 `data: ?[*:0]const u8`를 더하거나 이 한 곳만 `linux.mount`를 직접
부른다(호출자가 많으면 후자). data `gid=5,mode=620,ptmxmode=666`. root 셸에는 차이가 없다(소유자는 연 쪽). 로그 줄 그대로.

### terminal 칸

부팅(`placeChildren`의 `screen_args.encode`)과 `doReloadTerminal`(671 근처) 두 자리 모두 `.user`를 넣는다. 탈출로(`Rescue`)는
셸 칸만 덮으므로 사용자는 그대로다 — 탈출로 셸도 사용자로 뜬다는 것을 주석에 적는다.

## Task 4: terminal — 권한을 내리고 홈에서 띄운다

- `main.zig`: `a.user`가 `none`이 아니면 시작 때 한 번 `Account`를 짓는다 — 이름, 홈 `/home/<이름>`, 그리고 envp. envp는
  TERM · LANG · `fish_greeting`의 `setenv` 뒤에 `std.c.environ`을 훑어 짓는다. 빼는 것: `HOME` · `XDG_DATA_HOME` · `HISTFILE`.
  더하는 것: `HOME=/home/<이름>` · `USER=` · `LOGNAME=` · `SHELL=<셸 경로>`, 그리고 원래 `HISTFILE`이 있었으면 같은 파일 이름을
  홈에(`/config/zsh_history` → `/home/<이름>/.zsh_history`). 자식에서 `setenv`를 안 부르는 이유: fork 뒤 malloc을 피한다.
- `pty.spawn`에 `account: ?*const Account`. 자식(`pid == 0`)에서 순서대로 `fchown(0, USER_UID, TTY_GID)` · `fchmod(0, 0o620)`(위험 4
  — 경로 대신 fd라 `ptsname`이 필요 없다), `setgroups([AUDIO_GID])`, `setgid`, `setuid`, `chdir(home)`(실패하면 `/`), `execve(path,
  argv, envp)`. `setgroups` · `setgid` · `setuid` 중 하나라도 실패하면 stderr(이미 pty)에 `terminal: cannot drop to <이름>
  (errno N)`을 쓰고 `_exit(126)` — root로 이어 띄우지 않는다. 패널이 바로 닫히는 증상은 init의 탈출로와 같은 길로 보인다.
  `extern "c"`로 `setgroups` · `setgid` · `setuid` · `fchown` · `fchmod` · `chdir` · `execve`를 선언한다(`project_zig_c_uapi_rule`,
  `kill` · `waitpid`와 같은 수법).
- `spawnFish`(pty_test)는 `null`을 넘겨 그대로다.
- 로그: `terminal: spawned child pid N (<셸>)` 뒤에 사용자면 ` as <이름>`을 붙인다. 앞부분은 terminal 체인이 세는 마커라 그대로.
- 받아쓰기(`DICTATE_PATH` execve)는 root 그대로다 — 손대지 않는다.

```
(cd terminal && zig build test)   # 컨테이너에서
```

## Task 5: 막히는 것 재기와 고치기(위험 10)

home 체인 첫 판을 고치기 전 상태로 한 번 돌려 측정 10의 목록을 `setpriv`로 친다. 고르는 규칙:

- `/dev/snd`가 0600이면: init이 부팅 때 `/dev/snd/*`를 `root:audio 0660`으로 바꾼다. 부팅 뒤 꽂은 USB 헤드셋의 노드는 안 바뀐다 —
  init에 uevent가 없어서다. 그 한계는 `carryover.md`의 HP 절에 적는다(terminal의 uevent 길에 얹을지는 실기가 요구할 때).
- `ping`이 막히면: `/proc/sys/net/ipv4/ping_group_range`에 `0 2147483647`(Debian 기본과 같다)을 init이 쓴다.
- `dmesg`는 Debian 기본(`dmesg_restrict=1`)과 같으면 그대로 둔다 — sudo(M2)의 자리다.
- `bluetoothctl`은 기본 `bluetooth=off`라 이 체인에서 못 잰다. HANDOFF "사용자가 확인할 것"에 넣는다.
- `tars-config set`은 `EACCES` 그대로 둔다 — `try: sudo` 문구는 M2다. 지금 무엇이 찍히는지만 적는다.

## Task 6: 체인 `home/check.sh`를 M1로

monitor 45497 · QMP 45498을 이제 실제로 연다(화면 셸에 `sendkey`). `keyboard/check.sh`의 `type_keys`를 복사한다.

부팅 1(ISO + 5G NVMe + 3G NVMe):

- 판정 7 그대로.
- 판정 9(새). 질문 길로 설치한다 — `tars-install /dev/nvme0n1`(`--yes` 없이) → `user name [tars]:`에 `root`(거절 줄과 같은
  질문이 다시), `hpuser` → `password [tars-linux]:`에 `hp-secret-1` → `type YES` → `YES`. 시리얼 로그에 `hp-secret-1`이 한 번도
  없다(echo가 꺼졌다). `wrote tars.conf (user=hpuser) and shadow` · `made /home/hpuser`.
- ISO 부팅 로그에 `no tars-home disk, shell runs as root`.

부팅 2(NVMe 혼자):

- 판정 2 · 3 그대로.
- 판정 4(사용자로 바뀜). 로그에 `user hpuser uid 1000 home /home/hpuser`와 `spawned child pid … as hpuser`. 시리얼의 root 셸에서
  그 pid의 `/proc/<pid>/status`가 `Uid: 1000`(넷 다) · `Groups: 29`, environ에 `HOME=/home/hpuser` · `USER=hpuser`이고
  `XDG_DATA_HOME`이 없다, `readlink /proc/<pid>/cwd`가 `/home/hpuser`. pty: `stat -c '%U:%G %a' $(readlink /proc/<pid>/fd/0)`이
  `hpuser:tty 620`.
- 판정 10(새). `/etc/shadow` 0600 root이고 `hpuser:$y$`로 시작한다, `/config/shadow` 0600. `/home/hpuser` 0700 hpuser:hpuser,
  seed 다섯이 hpuser 소유.
- 씨앗. 화면 셸에 `sendkey`로 `echo hp-m1 > hp-marker` + Enter(cwd가 홈이라 경로 없이 — cwd 판정의 다른 면). 시리얼에서
  `stat -c %U /home/hpuser/hp-marker`가 `hpuser`. `sync`.
- 측정 10 · 11은 `setpriv --reuid=1000 --regid=1000 --init-groups`로 치고 결과를 로그에 찍는다(판정이 아니라 기록 — Task 5가
  고친 뒤의 것들만 판정으로 올린다).

부팅 3(NVMe + `debian-home`): 판정 5(`hp-marker`가 남았고 소유자도 그대로) · 6 그대로.

`install/check.sh`(Task 7)이 `--yes` 길을 지키므로 기본값 `tars`의 `id`는 그쪽 판정 한 줄로 본다.

## Task 7: `install/check.sh`와 문서

- 판정 7(345행) · 16(608행): 설치기가 `tars.conf`를 쓰므로 첫 부팅에 `created`가 없다. 판정을 `tars-install: wrote tars.conf
  (user=tars)`(설치 로그)와 첫 부팅의 `loaded /config/tars.conf`(실제 문구는 `rg -n 'loaded' init/src/main.zig`로)로 바꾼다.
  16의 "새 p2"는 `di-marker`가 없다는 줄이 이미 증명한다. 기본값 판정 한 줄: 부팅 로그 `user tars uid 1000 home /home/tars`.
- `docs/guides/running-tars.md`: 설치 절에 질문 셋과 기본값, "화면 셸은 사용자 · 시리얼 셸은 root", `/config`는 아직 root만
  쓴다(M2에서 sudo), dotfile이 홈으로 옮겨 간 것. `docs/guides/key-files.md`에 `account.zig`.
- design "실측 (M1)" 절에 측정 7~11. 위험 2 · 4 · 7 · 9 자리에 닫힘 한 줄씩, 위험 10은 목록과 남은 것. 위험 8은 확정 8로 고친다.

## Task 8: 게이트 · 커밋

- `make quick`, init · terminal `zig build test`(컨테이너), `install/check.sh` · `home/check.sh` 혼자 먼저.
- 루트 게이트 `./check.sh`(25체인, 11분쯤 + 이미지가 바뀌었으니 처음의 initrd 다시 굽기). 사용자 없는 부팅이 스물셋이라 그
  체인들은 devpts 옵션과 group 한 줄 말고는 안 바뀌어야 한다 — 빨개지면 그 둘부터 본다.
- `git status`로 산출물이 안 섞였는지 본 뒤 좁혀서 add: `devcontainer/Dockerfile` · `kernel/{guest_tools,make_initrd}.sh` ·
  `shared/screen_args{,_test}.zig` · `init/build.zig` · `init/src/{account,account_test,config,config_test,config_edit,
  config_edit_test,login,install,main}.zig` · `terminal/src/{main,pty}.zig` · `{install,home}/check.sh` · design · 이 plan ·
  `docs/guides/{key-files,running-tars,carryover}.md`.
- HANDOFF: M1 끝남, 다음 M2(sudo), 이미지 태그, 사람이 확인할 것(질문 셋을 실제 키보드로, `bluetoothctl`을 사용자로).

## 시간

- Task 0: 이미지 굽기 몇 분 + initrd.
- Task 1~4: 편집과 단위 검사. 파일이 셋 프로그램에 걸쳐 있어 가장 길다 — 1시간 남짓.
- Task 5 · 6: home 체인이 부팅 셋에 `sendkey`가 더해져 5분쯤.
- Task 8: 루트 게이트 12분 남짓.
