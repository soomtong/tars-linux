# HP-M2 — sudo: 비밀번호의 첫 쓰임과 `/config`에 쓰는 길

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-02
> `7f349f6` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: design 결정 6(뒤 절반) · 9와 위험 3, 판정 8을 넣는다. 끝나면 화면 셸의 사용자(uid 1000)가 `sudo <명령>`에 설치 때 정한
비밀번호를 쳐서 root로 한 번 실행할 수 있다. `tars-config set` · `reload` 같은 쓰기를 사용자로 치면 `permission denied` 뒤에
`try: sudo tars-config …` 한 줄이 나온다. `sudo tars-config passwd`가 비밀번호를 바꾸고 그 값은 재부팅 뒤에도 남는다.
sshd는 여전히 키 전용이다(비밀번호를 받는 원격 길이 안 생긴다). 이것으로 HP가 끝나고 PM design을 연다.

Architecture: 실체는 Debian `sudo`이고 판단은 PAM이 아니라 sudoers가 한다 — "누가 root가 될 수 있나"는 `%sudo` 그룹 한 줄,
"그 사람이 맞나"는 `pam_unix`가 `/etc/shadow`(M1이 부팅마다 짓는 것)를 읽는다. 모든 설정 파일(`/etc/sudoers` · `/etc/pam.d/sudo`)은
initrd의 정적 파일이고, 부팅마다 바뀌는 것은 M1과 같이 group의 멤버 줄과 shadow뿐이다. 비밀번호 입력과 해시는 설치기 안에 있던
것을 한 파일로 옮겨 설치기와 `tars-config passwd`가 같은 함수를 쓴다.

## 착수 전 실측 (2026-11-02, 컨테이너 `80a4c6be0eba` + trixie 패키지, `--rm`이라 이미지는 그대로)

기준은 HP-M1 루트 게이트의 initrd(라이브러리 137개).

| 후보 | 새 파일(바이트) | 새 라이브러리 |
|---|---|---|
| Debian `sudo` 1.9.16p2 | `usr/bin/sudo` 306,456 · `libsudo_util.so.0` 137,912 · `sudoers.so` 695,872 — 합 1,140,240 | 0 |
| `opendoas` 6.8.2 | `usr/bin/doas` 43,184 | 0 |
| PAM 모듈(둘 다 필요) | `pam_unix.so` 55,376 · `pam_permit.so` 14,336 · `pam_deny.so` 14,040 | 0 |

sudo가 끄는 `libaudit` · `libselinux` · `libapparmor` · `libssl` · `libz` · `libcrypto` · `libpam` · `libcrypt`이 전부 sshd ·
curl · `mkpasswd`가 이미 데려왔다. design 위험 3이 걱정한 "PAM 사슬의 라이브러리"는 이미 치른 비용이었고 차이는 본체 약
1.1MB(initrd의 1%)다. `/etc/pam.d`와 PAM 모듈은 지금 initrd에 없다(sshd는 `UsePAM no`).

## 이 plan이 정한 것 (design에 없던 자리)

1. 실체는 Debian `sudo`다(위험 3 닫음). doas는 1.1MB 작지만 Homebrew `install.sh`가 `/usr/bin/sudo -v`와 `sudo -l mkdir`로
   권한을 확인하는데 doas에 그 플래그가 없다 — `sudo` 이름을 씌워도 PM의 첫 줄에서 막힌다. 싣는 것은 `sudo` · `libsudo_util.so.0` ·
   `sudoers.so` 셋이다. `sesh` · `sudo_intercept.so` · `sudo_noexec.so` · `audit_json.so` · `group_file.so` · `system_group.so` ·
   `sudoreplay` · `visudo`는 안 싣는다(sudoers는 이미지가 굽는 정적 파일이라 사람이 고치지 않는다). `/etc/sudo.conf`도 없다 —
   기본 plugin 경로가 `/usr/libexec/sudo/sudoers.so`인지 Task 0이 `strings`로 확인한다.
2. sudoers는 initrd의 정적 파일 하나(`/etc/sudoers`, root 0440)이고 권한은 그룹으로 준다.

   ```
   Defaults secure_path="/usr/bin:/bin"
   Defaults lecture=never
   Defaults !syslog
   root  ALL=(ALL:ALL) ALL
   %sudo ALL=(ALL:ALL) ALL
   ```

   `secure_path`는 게스트 `PATH`와 같다(`environ.zig`의 `PATH_ENTRY`). `lecture=never`는 lecture 표시 파일이 tmpfs라 부팅마다
   다시 뜨는 것을 막는다. syslog 소켓이 없으므로 `!syslog`(있으면 조용히 실패하지만 소리 없는 실패를 남기지 않는다).
   timestamp는 기본(15분, `/run/sudo/ts` — tmpfs라 재부팅이 지운다)이다.
3. 그룹 `sudo`(gid 27, Debian과 같은 번호)를 initrd의 group에 늘 두고, init이 사용자를 `audio`와 함께 그 멤버로 넣는다. terminal의
   `setgroups`는 `[27, 29]`. 사용자 이름을 sudoers에 쓰는 길(init이 부팅마다 짓기)은 고르지 않았다 — 파일이 정적이면 0440 소유를
   initrd가 한 번 정하고, `id`가 Debian처럼 `27(sudo)`를 보인다. 상수는 `screen_args.SUDO_GID`.
4. PAM 사슬은 `/etc/pam.d/sudo` 넷째 줄까지다.

   ```
   auth     required pam_unix.so
   account  required pam_unix.so
   session  required pam_permit.so
   password required pam_deny.so
   ```

   그리고 `/etc/pam.d/other`는 넷 다 `pam_deny.so`(모르는 서비스 이름이 열리지 않게). `unix_chkpwd`는 안 싣는다 — sudo는 setuid라
   PAM을 root로 돌리고 `pam_unix`가 `/etc/shadow`를 직접 읽는다. 모듈 경로는 libpam에 컴파일된 값을 Task 0이 `strings`로
   확인해 그 자리에 둔다(trixie는 `/usr/lib/x86_64-linux-gnu/security`가 기대값이고, initrd의 `/lib`는 링크가 아니라 진짜
   디렉터리다).
5. `try: sudo` 안내는 명령 이름이 아니라 실패한 자리에서 한다. `tars-config`의 앞문 명령(wifi · ssh · firewall · dictation)에는 읽기
   하위 명령이 섞여 있어 "쓰기 명령 목록"을 따로 두면 낡는다. `config_cli`에 `denied(e) bool` 하나 — `e`가 `ACCES` · `PERM`이면
   `tars-config: permission denied (only root writes /config); try: sudo tars-config <받은 인자 그대로>`를 찍고 true. 쓰기 실패를
   말하던 자리(temp 만들기 · rename · mkdir · symlink · unlink)가 각자의 `complain` 앞에서 그것을 먼저 부른다. 종료 코드는 기존
   `EXIT_IO`가 아니라 새 `EXIT_DENIED`(값은 Task 2가 기존 코드와 안 겹치게 고른다).
6. control 소켓은 root 0600 그대로다(결정 9의 "M2가 본다"를 닫음). 열면 사용자가 init에게 재시작 · reload를 시킬 수 있는데, 그
   권한은 sudo가 이미 준다. 사용자의 `tars-config reload` · `tars-service …`는 `connect`의 `EACCES`를 5번의 안내로 바꾼다
   (`tars-service`는 `try: sudo tars-service …`).
7. `tars-config passwd`는 root만 한다(`geteuid() != 0`이면 5번의 안내). 사용자의 옛 비밀번호는 다시 묻지 않는다 — sudo가 방금
   확인했다. 새 비밀번호를 echo 없이 두 번 묻고(`new password:` · `again:`) 다르면 아무것도 안 바꾸고 2로 끝난다. 빈 값도 거절한다
   (설치기의 Enter = 기본값은 설치에만 있는 규칙이다). 해시는 설치기와 같은 `mkpasswd -m yescrypt -s`. `/config/shadow`를 temp +
   rename(0600)으로 바꾸고, 같은 프로세스가 `/etc/shadow`도 `account.shadowFile`로 다시 써서 재부팅 없이 다음 `sudo`부터 새 값이다.
   `user=`가 없는 기계(홈 없는 부팅 · ISO)는 `no user account on this machine (tars.conf has no user=)`로 2.
8. 비밀번호 입력 · 해시를 `init/src/secret.zig`(새 파일)로 옮긴다 — `install.zig`의 `readSecretAnswer`와 `mkpasswd` 부르기. 설치기의
   `password hashed (yescrypt) in Nms` 줄과 모드 0600 로그는 그대로 남는다(install 체인 판정이 그 줄을 본다).

## 무엇을 재나 (design "실측 (M2)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 12 | 위 착수 전 표, 그리고 실제 initrd 증가(압축 · `.so` 수) | 위험 3 |
| 13 | TCG에서 `sudo -S true` 한 번의 시간(yescrypt 검증 — 설치 때 해시 2.1초와 비교) | 결정 6 |
| 14 | 사용자로 `sudo`를 칠 때 나오는 줄들(경고 · `unable to resolve host` 같은 것이 섞이는가) | 결정 6 |

## Task 0: 이미지 — sysroot에 sudo · PAM 모듈

- 지금 sysroot에는 `usr/bin/sudo`도 `security/pam_unix.so`도 없다(2026-11-02 확인). `devcontainer/Dockerfile`의 sysroot 목록
  (`whois:amd64` 옆)에 `sudo:amd64` · `libpam-modules:amd64`를 더하고 주석에 HP-M2 확정 1 · 4. 이미지 태그가 바뀐다(`image.sh`의
  sha256 앞 12자) — ghcr에 없으니 로컬로 굽고, HANDOFF에 `docker rmi tars-devcontainer && make container`.
- `strings`로 둘을 확인한다: `sudo`의 기본 plugin 경로(`/usr/libexec/sudo/sudoers.so`), libpam의 모듈 디렉터리. `readelf -d`로 `sudo` ·
  `sudoers.so`의 `RUNPATH`(`/usr/libexec/sudo`가 기대값) — 그래서 `libsudo_util.so.0`은 `copy_lib_deps`의 표준 경로 탐색이 아니라 그
  자리에 직접 둔다.
- `kernel/guest_tools.sh`에 `usr/bin/sudo:usr/bin/sudo`. `make_initrd.sh`에 sudo 절 — `usr/libexec/sudo/{libsudo_util.so.0,sudoers.so}`
  복사와 `copy_lib_deps`, PAM 모듈 셋, `chmod 4755 usr/bin/sudo`(`cp`가 setuid를 남기는지에 기대지 않는다), `etc/sudoers` 0440 ·
  `etc/pam.d/{sudo,other}` 0644 heredoc, group에 `sudo:x:27:`. 주석에 HP-M2와 확정 1~4.
- `tools/check.sh`가 guest_tools 목록을 그대로 보므로 `sudo --version`이 거기서 돈다 — 실패하면 plugin · `RUNPATH` 자리부터 본다.
- 측정 12.

## Task 1: 순수한 층

- `shared/screen_args.zig`: `SUDO_GID: u32 = 27`과 주석(확정 3).
- `init/src/account.zig`: group의 `audio` 줄을 바꾸던 함수가 `sudo` 줄도 같은 방식으로 `sudo:x:27:<이름>`으로 바꾼다. 단위 검사에
  두 줄이 다 바뀐 group 파일 바이트 그대로, 그리고 정적 group에 `sudo` 줄이 없으면 null(initrd와 코드가 어긋난 것을 부팅 로그로
  드러낸다 — 조용히 넘어가지 않는다).
- `init/src/secret.zig`(새, 확정 8): `readSecret(prompt, buf) Answer`와 `hash(password, out) ?[]const u8`. 설치기 쪽 함수를 옮기기만
  하고 바꾸지 않는다 — echo 끄기 → 프롬프트 → 읽기 → `.NOW`로 되돌리기의 순서(M1의 첫 판들이 가르친 것)를 주석째 옮긴다.
- `account.zig`의 `RESERVED`에 `sudo`(같은 이름의 사용자 그룹이 생기면 안 된다). 단위 검사 한 줄.

```
(cd init && zig build test)   # 컨테이너에서
```

## Task 2: `tars-config` — 안내와 `passwd`

- `config_cli.zig`: `main`이 받은 인자를 모듈 변수에 두고, `denied(e)`(확정 5)와 `EXIT_DENIED`. 쓰기 실패 자리들(`config_cli`의 temp ·
  rename, `config_front`의 temp · rename · mkdir · symlink · unlink)이 `if (cli.denied(e)) return EXIT_DENIED;`를 먼저 한다.
  `reloadInit`의 `connect`도.
- `config_edit.zig`의 `parseCommand`에 `passwd`(인자 없음, 남으면 usage). `help`와 usage 줄에 한 줄.
- `passwd` 본체(확정 7). `/etc/shadow`를 다시 쓸 때 root 줄은 지금 파일의 것을 그대로 쓰지 않고 `shadowFile`이 짓는다(M1과 같은
  바이트) — `/etc/shadow`의 진실은 init이 짓는 모양 하나다.
- `service_cli.zig`: `connect`의 `EACCES` → `try: sudo tars-service <인자>`.
- `config_edit_test`에 `passwd` 파싱 둘(맨몸 · 인자 남음).

## Task 3: init과 terminal의 그룹

- init: M1의 계정 짓기가 그대로 새 group 함수를 쓴다. 로그 줄 `<이름> is in /etc/passwd, /etc/group and /etc/shadow`는 그대로.
- terminal `main.zig`: `.groups = .{ screen_args.SUDO_GID, screen_args.AUDIO_GID }`. `pty.zig`의 `setgroups`는 길이를 받으므로
  그대로다.

## Task 4: 체인 `home/check.sh`를 M2로

부팅 2(NVMe 혼자, 질문 길로 `hpuser` · `hp-secret-1`로 깐 디스크)에 판정 8을 더한다. 모두 시리얼 root 셸에서
`setpriv --reuid=1000 --regid=1000 --init-groups`로 사용자가 되어 친다(M1과 같은 길, 화면 셸에 `sendkey` 없음).

- 8a. 파일: `stat -c '%u:%g %a'`가 `/usr/bin/sudo` `0:0 4755`, `/etc/sudoers` `0:0 440`. group에 `sudo:x:27:hpuser`. 판정 4의 화면 셸
  `Groups:`가 `27 29`(M1의 `29`에서 바뀐다).
- 8b. `sudo -n true`가 0이 아니다(비밀번호가 필요하다). `printf 'wrong\n' | sudo -S true`가 0이 아니다.
  `printf 'hp-secret-1\n' | sudo -S id -u`가 `0`. 측정 13은 이 한 번의 시간.
- 8c. 사용자로 `tars-config set ntp=off`가 `try: sudo tars-config set ntp=off`를 찍고 `EXIT_DENIED`, `tars.conf`가 그대로다(sha256
  전후). `tars-config reload`도 `try: sudo`. `printf 'hp-secret-1\n' | sudo -S tars-config set ntp=off`는 0이고 파일이 바뀐다.
- 8d. `printf 'hp-secret-1\nhp-secret-2\nhp-secret-2\n' | sudo -S -k tars-config passwd`가 0(sudo가 첫 줄만 먹는지 — 아니면 sudo의
  timestamp를 먼저 세우고 `passwd`만 따로 넣는다. Task 4의 첫 판이 정한다). 그 뒤 `-k`로 timestamp를 버리고 옛 비밀번호는 실패 ·
  새 비밀번호는 `0`. 다른 두 값을 주면 2이고 `/config/shadow`의 sha256이 그대로. 사용자로 `tars-config passwd`는 `try: sudo`.
- 8e. 부팅 3(재부팅)에서 `hp-secret-2`가 `sudo -S`를 통과한다(`/config/shadow`가 영속했다).

판정 9의 질문 길은 그대로다. 시리얼 로그에 `hp-secret-` 글자가 echo로 찍히지 않는다는 줄은 `printf` 파이프의 타이핑 자체가 로그에
남으므로 부팅 1의 설치 구간에만 건다 — 8b~8e의 줄은 그 grep 범위 밖에 둔다(`cut` 범위를 체인에 적는다).

## Task 5: 문서

- design: Status 줄(HP 끝남), 위험 3 닫음 한 줄, 결정 9 끝에 control 소켓 확정 6, "실측 (M2)" 절에 12~14와 첫 판들이 가르친 것.
- `docs/guides/running-tars.md`의 사용자 절: `sudo`, `sudo tars-config passwd`, 시리얼 셸은 root라 sudo가 필요 없다는 것.
- `docs/guides/completed.md` 표 끝 한 행, `docs/decisions/project_home_partition.md`(새 기억)와 `MEMORY.md` 한 줄, HANDOFF.
- 소개 페이지(`gh-pages`의 `data.js`)는 `site/README.md`의 순서대로 — 기준일 · 타임라인 · 기능 목록에 "설치 때 계정 · ext4 홈 · sudo".
- `docs/guides/key-files.md`에 `secret.zig`.

## Task 6: 게이트 · 커밋

- `make quick`, init · terminal `zig build test`(컨테이너), `tools/check.sh` · `home/check.sh` · `install/check.sh` 혼자 먼저.
- 루트 게이트 `./check.sh`(25체인, initrd가 바뀌니 prebuild 포함 12분쯤). 사용자 없는 부팅은 group 한 줄과 initrd 1.2MB 말고는
  안 바뀌어야 한다.
- `git status`로 산출물이 안 섞였는지 본 뒤 좁혀서 add: `devcontainer/Dockerfile` · `kernel/{guest_tools,make_initrd}.sh` · `shared/screen_args.zig` ·
  `init/build.zig`(secret을 테스트 목록에 넣었다면) · `init/src/{account,account_test,secret,install,config_cli,config_front,
  config_edit,config_edit_test,service_cli}.zig` · `terminal/src/main.zig` · `home/check.sh` · design · 이 plan · 문서들.

## 시간

- Task 0: 이미지 굽기 몇 분 + initrd 한 번(5분).
- Task 1~3: 편집과 단위 검사, 40분 남짓.
- Task 4: home 체인 첫 판들 — sudo `-S`와 파이프의 상호작용을 재는 자리라 판이 몇 번 돈다.
- Task 6: 루트 게이트 12분 남짓.
