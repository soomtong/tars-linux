# TARS Home Partition — Design

접두사: HP

Status: M0 끝남(2026-11-02) — p3 ext4 `tars-home`이 `/home`에 붙고 재부팅을 넘어 남는다. 체인 스물다섯째 `home/check.sh`(판정 1 · 2 · 3 ·
5 · 6 · 7). 결정 11 · 위험 9(1 · 6은 M0이 닫았다) · 실측 1~6. 다음은 M1(계정).

관련 문서: `docs/decisions/project_config_fs_ext2.md`(`/config`가 ext2에 머무는 이유와 ext4로 갈 세 신호 — 이 설계가 그
신호를 `/home`에서 켠다) · `2026-09-23-tars-disk-install-design.md`(DI. `tars-install`과 p1 · p2) ·
`2026-11-01-tars-kernel-upgrade-design.md`(KU. ESP의 슬롯 둘, ESP 1GiB는 사용자가 정했고 이 설계가 768MiB로 바꾼다) ·
`2026-08-14-tars-config-persistence-design.md`(CP. 설정 디스크를 `MS_SYNCHRONOUS`로 붙인 이유) ·
`docs/guides/carryover.md`의 이미지 뷰어 항목(Homebrew는 non-root 사용자와 디스크 위의 prefix가 먼저라고 적어 둔 자리).

## 한 줄 요약

설치 디스크에 셋째 파티션 `tars-home`(ext4, 나머지 전부)을 만들어 `/home`에 붙이고, 설치 때 물은 이름으로 사용자 계정
하나(uid 1000)를 만들어 셸을 그 사용자로 띄운다. 설정은 ext2 `/config`에 그대로 두고, 사용자 데이터와 앞으로의
Homebrew prefix(`/home/linuxbrew/.linuxbrew`)는 ext4 `/home`에 산다. 비밀번호의 쓰임은 `sudo`다.

## 왜 지금인가

2026-11-02 사용자가 "`/config`는 ext2로 두되 홈과 패키지 매니저 자리는 ext4가 맞지 않나"를 냈다. 어제 `project_config_fs_ext2.md`에
적은 "ext4로 갈 세 신호"(사용자 데이터가 살기 시작 · 쓰기가 잦아짐 · 수십 GiB)가 Homebrew를 들이는 순간 셋 다 켜진다.
Homebrew의 Cellar는 파일 수만 개와 git 저장소 여럿이고 bottle 하나가 수십 MB다. 그 전에 둘이 먼저 서야 한다 — 디스크 위의
`/home`, 그리고 root가 아닌 사용자(Homebrew `install.sh`는 root이면 멈춘다). 이 서브프로젝트가 그 둘이고, Homebrew 설치
자체는 다음 서브프로젝트(Package Manager, PM)다.

## 착수 전에 아는 것 (2026-11-02에 소스에서 확인)

### 확인 1 — 설치 디스크는 p1 · p2뿐이고 나머지는 비어 있다

`disk.zig`의 `SFDISK_SCRIPT`가 GPT에 `size=1GiB, type=uefi, name=TARS-BOOT`와 `size=1GiB, type=linux, name=TARS-CONFIG`
둘을 만든다. `MIN_DISK_BYTES`는 2GiB + 2MiB(GPT 정렬과 백업 헤더 몫). `install.zig`는 `mkfs.vfat -F 32`와
`mke2fs -q -t ext2 -L tars-config`를 `wait4`로 기다린다. TARS가 있는 디스크에 `--wipe` 없이 들어가면 갱신이라 p1만 갈고
p2는 남긴다(DI 결정 8).

### 확인 2 — 루트는 tmpfs이고 `/etc/passwd`는 initrd의 정적 파일이다

initramfs 119MB가 루트다. `make_initrd.sh`가 `/etc/passwd` · `/etc/group`을 heredoc으로 굽는다(root · messagebus · nogroup 등).
`/home`은 없다. `/config`가 안 붙은 부팅은 tmpfs의 빈 `/config`에 써지고 재부팅하면 사라진다 — CP가 "가짜 영속성"으로
이름 붙인 함정이고, `/home`에도 같은 함정이 생긴다.

### 확인 3 — 모든 것이 root다

init · terminal · 서비스 · 셸이 전부 uid 0이다. terminal은 `forkpty`로 셸을 띄운다(`terminal/src/pty.zig:56`). git 신원은
`/etc/passwd`에서 `root@(none)`으로 유도된다(`config.zig:1227`). `tars-config`는 `/config/tars.conf`를 임시 파일에 쓰고
`rename`으로 교체한다.

### 확인 4 — 커널에 ext4가 없다

`kernel/build/.config`: `CONFIG_EXT2_FS=y`, `CONFIG_EXT4_FS is not set`, `CONFIG_VFAT_FS=y`, `CONFIG_ISO9660_FS=y`.
`storage.zig`는 오프셋 1024의 superblock에서 `s_volume_name`(오프셋 120)을 직접 읽는다 — ext2/3/4가 같은 자리라 ext4 라벨도
지금 코드가 읽는다(`storage.zig:160`의 주석이 그렇게 적혀 있다).

### 확인 5 — 게스트에 있는 도구

`guest_tools.sh`: git · curl · ps · bash · chown · mke2fs · mkfs.vfat. `mke2fs -t ext4`는 같은 바이너리다. sudo · doas ·
libpam · `mkpasswd`는 없다. sshd는 키 전용이다(`make_initrd.sh:618` "비밀번호는 없다", 키는 `/config/ssh/authorized_keys`).

### 확인 6 — 설치기의 질문 자리

`install.zig:657`이 계획을 찍고 `type YES to continue: `를 묻는다. `--yes`가 건너뛴다. `readLine`은 fd 0에서 한 줄을 읽는다.
echo 없이 읽는 길은 `tars-config dictation key`가 이미 갖고 있다(termios).

### 확인 7 — KU의 슬롯이 ESP를 쓰는 양

한 벌(`bzImage` · `initrd.cpio` · `version`)이 102,362,098바이트(6.18.60)였고 BT firmware로 약 23MB가 더해져 약 125MB다.
슬롯 둘이면 약 250MB. 1GiB ESP는 사용자가 정한 값이었다(KU).

## 사용자가 정한 것 (2026-11-02)

1. p1 768MiB · p2 256MiB · p3 나머지 전부(처음 512MiB · 512MiB로 냈다가 같은 날 고쳤다).
2. 최소 디스크 4GiB를 보장한다. "아직 어떤 임베디드에 들어갈지 모른다."
3. 사용자 이름은 설치 시점에 묻는다. 기본값(placeholder)을 보여 주고 그냥 Enter면 기본값을 쓴다.
4. 기본 계정 이름 `tars`.
5. 기본 비밀번호 `tars-linux`.

## 결정

### 결정 1 — 두 층이다. `/config`는 ext2 · sync, `/home`은 ext4 · async

`/config`는 바뀌지 않는다(`project_config_fs_ext2.md`). `/home`은 ext4를 `data=ordered` 기본 저널로, `MS_SYNCHRONOUS` 없이,
`MS_NODEV | MS_NOSUID`, `relatime`, `errors=remount-ro`로 붙인다. ext2 쪽은 응용 계층(rename 교체 · sync)이 일관성을 지키고
ext4 쪽은 파일시스템(저널)이 지킨다 — 쓰기 성질이 반대라 수단도 반대다. `nosuid`는 Homebrew가 setuid를 안 쓴다는 전제이고
M0이 `brew`가 아니라 PM이 확인한다. 걸리면 그때 뺀다.

### 결정 2 — 파티션 배치와 최소 디스크

```
label: gpt
size=768MiB, type=uefi,  name=TARS-BOOT
size=256MiB, type=linux, name=TARS-CONFIG
            type=linux, name=TARS-HOME       # 나머지 전부
```

`MIN_DISK_BYTES` = 4GiB + 2MiB. p3는 최소 3GiB 남짓이 된다. `MIN_DISK_WORDS`는 "more than 4 GiB". 거절은 지금처럼 YES 전이다.

### 결정 3 — `/home`은 라벨 `tars-home`으로 찾고, 안 붙으면 사용자를 안 만든다

`storage.zig`의 탐색을 한 번 더 돌린다. 접두사가 아니라 라벨 전체 `tars-home`을 본다(`tars-` 접두사 탐색은 설정 디스크의
것이고, `tars-home`이 거기 먼저 잡히면 안 되므로 설정 탐색에서 `tars-home`을 제외한다 — 위험 5). 설치된 부팅의 5초 기다림(DC)을
`/home`에도 같은 시계로 적용한다. 로그는 `tars-init: mounted ext4 at /home` 한 줄.

안 붙으면 `/home`은 tmpfs의 빈 디렉터리다. 거기에 홈을 만들면 가짜 영속성이다(확인 2). 그래서 `/home`이 없는 부팅은 사용자
계정을 만들지 않고 지금처럼 root 셸로 뜬다. 로그 `tars-init: no tars-home disk, shell runs as root`. HP 이전에 설치된
디스크(p3 없음)가 정확히 이 모양이고, 처방은 `tars-install <disk> --wipe`다(결정 10).

### 결정 4 — 커널에 ext4를 더하고 ext2는 그대로 둔다

`CONFIG_EXT4_FS=y`(jbd2가 딸려 온다). `CONFIG_EXT2_FS`는 그대로다. 하나로 합치는 `CONFIG_EXT4_USE_FOR_EXT2`는 M0이 bzImage
크기와 부팅 시간을 재고 나서 따로 정한다 — 둘을 켜면 코드가 두 벌이지만 `/config` 쪽 설명이 ext2 드라이버에 그대로 붙어
있고, 합치면 `mounted ext2 at /config` 줄의 뜻이 바뀐다(ext4 드라이버가 ext2를 붙이는 것). 처음엔 투명성을 택한다.

### 결정 5 — 계정은 하나, uid · gid 1000, 이름은 설치 때 묻는다

TARS는 한 사람의 기계다. 사용자는 하나이고 uid 1000 · gid 1000(같은 이름의 그룹), 홈은 `/home/<이름>`, 셸은 `tars.conf`의
`shell=` 그대로다. 설치기가 계획을 찍은 뒤 YES 전에 묻는다.

```
user name [tars]:
password [tars-linux]:
type YES to continue:
```

Enter만 치면 괄호의 기본값이다. 비밀번호는 echo 없이 받는다(확인 6의 길). `--yes`는 질문 셋을 다 건너뛰고 기본값을 쓴다 —
게이트가 그 길을 탄다. 이름 규칙은 `[a-z_][a-z0-9_-]{0,31}`이고 `root` · `messagebus` · `nobody` · `linuxbrew`는 거절한다.
거절하면 같은 질문을 다시 묻는다.

### 결정 6 — 비밀번호의 쓰임은 `sudo`다. sshd는 키 전용 그대로

지금 TARS에는 비밀번호를 확인하는 자리가 없다(로그인 화면 없음, sshd 키 전용). 이 설계가 비밀번호에 주는 첫 자리는
`sudo`다. Homebrew `install.sh`가 `sudo`를 부르고, 사용자가 `/config`에 쓸 때(결정 9)도 `sudo tars-config …`다. sshd는
비밀번호를 계속 안 받는다 — 기본 비밀번호 `tars-linux`가 공개된 값이어도 원격에서 들어올 길이 안 생긴다.

해시는 `/config/shadow`(root 600, 한 줄 `<이름>:<해시>`)에 둔다. `tars.conf`는 사람이 읽고 고치는 평문 설정이라 해시의 자리가
아니다. 바꾸는 명령은 `sudo tars-config passwd`(M2). sudo 실체(Debian `sudo`인지 `doas`에 `sudo` 이름을 씌운 것인지)와 PAM
사슬은 M2가 크기를 재고 정한다(위험 3).

### 결정 7 — passwd · group · shadow는 부팅마다 tmpfs `/etc`에 만든다

영속되는 것은 `tars.conf`의 `user=<이름>`과 `/config/shadow` 둘뿐이다. init이 부팅 때 initrd의 정적 `/etc/passwd` ·
`/etc/group`에 사용자 줄을 덧붙이고 `/etc/shadow`를 쓴다. 계정 파일을 디스크에 영속시키지 않는 것은 "설정은 `tars.conf` 하나"
(CP)와 같은 결이다. 홈 디렉터리 `/home/<이름>`은 설치기가 p3를 만들 때 함께 만들고(700, 1000:1000), init은 없으면 만든다
(디스크를 다른 도구로 비운 경우). git 신원은 그 passwd 줄에서 `<이름>@<hostname>`으로 유도된다.

### 결정 8 — 셸은 사용자로 뜬다. terminal · init · 서비스는 root로 남는다

terminal의 `forkpty` 자식이 `execve` 전에 `setgroups([1000])` · `setgid(1000)` · `setuid(1000)`을 부르고 환경에 `HOME` ·
`USER` · `LOGNAME` · `SHELL`을 넣고 홈으로 `chdir`한다. pty slave는 `forkpty`가 연 뒤 root 소유라 사용자가 `tty`를 못 쓰므로
terminal(root)이 slave를 1000:5(tty)로 `chown`하고 620으로 `chmod`한다(위험 4). terminal은 입력 장치와 DRM을 열어야 해서
root로 남고, init과 `/config/services`의 서비스도 지금처럼 root다. `/home`이 없는 부팅은 결정 3대로 root 셸이다.

### 결정 9 — `/config`는 root 소유 그대로, 쓰기는 `sudo tars-config`

세 길(`/config`를 1000 소유로 굽기 · sudo · init의 control 소켓으로 쓰기 요청)에서 sudo를 고른다. 비밀번호의 쓰임(결정 6)과
Homebrew의 요구가 같은 도구를 가리키고, `/config`의 소유를 바꾸면 `tars.conf`를 지키던 것(root만 쓴다)이 약해진다. 읽기는
그대로 모두 된다. `tars-config set …`을 사용자로 치면 `EACCES`를 `permission denied, try: sudo tars-config …`로 바꿔 말한다.
`tars-config reload`는 control 소켓으로 가므로 소켓 권한을 M2가 본다.

### 결정 10 — 갱신은 p3를 건드리지 않고, `--wipe`만 새 배치로 간다

TARS가 있는 디스크의 갱신(DI 결정 8)은 p1만 간다 — p2도 p3도 그대로다. HP 이전 디스크(p1 1GiB · p2 1GiB · p3 없음)는 갱신으로
p3가 생기지 않는다. 빈 자리에 p3만 더하는 길은 비목표 5다. 새 배치를 원하면 `--wipe`이고, `--wipe`는 p3(홈 · Homebrew)도
지운다는 것을 계획 출력에 한 줄 더 적는다: `  p3  rest  Linux  ext4  tars-home  <- your home, erased by --wipe`.

### 결정 11 — 게이트는 스물다섯째 체인 `home/check.sh`다

포트 monitor 45497 · QMP 45498(예약 범위 45455~45599, RP-M0). 설치 체인(`install/check.sh`, DC)이 이미 가상 디스크에
`tars-install --yes`를 치고 그 디스크로 다시 뜨는 길을 갖고 있으므로 그 모양을 따른다. 판정은 여덟이다.

1. 새 설치 뒤 `sfdisk -l`에 p1 768MiB · p2 256MiB · p3 나머지가 보인다.
2. 디스크로 뜬 로그에 `mounted ext2 at /config`와 `mounted ext4 at /home` 둘 다 있다.
3. `/proc/mounts`의 `/home` 줄이 `ext4 rw,nosuid,nodev,relatime`이고 `sync`가 없다.
4. `id`가 `uid=1000(tars) gid=1000(tars)`이고 `echo $HOME`이 `/home/tars`다.
5. `/home/tars`에 파일을 쓰고 재부팅하면 남아 있다(두 번째 부팅에 `created`가 없다 — CP의 증명 방식).
6. 라벨 `debian-home`인 ext4 디스크를 하나 더 붙여도 `/home`이 되지 않는다(위험 5).
7. 4GiB보다 작은 디스크는 YES 전에 거절한다(`more than 4 GiB`).
8. (M2) `sudo -n true`가 실패하고 비밀번호를 주면 성공한다. `tars-config set`을 사용자로 치면 `try: sudo` 줄이 나온다.

## 위험

### 위험 1 — 768MiB ESP에 슬롯 둘

한 벌 약 125MB(확인 7), 둘이면 약 250MB, 여유 약 500MB. 한 벌이 384MB를 넘으면 old 슬롯이 안 들어간다. M0이 설치 뒤 ESP의
빈 자리를 바이트로 적고(KU 실측처럼), KU의 갱신 코드가 "자리가 모자라면 old를 버리고 new만 쓴다"로 되어 있는지 본다 — 아니면
그 분기를 더한다. 사용자 결정이므로 크기는 바꾸지 않는다.

M0이 닫았다(실측 2). 설치 직후 빈 자리 674,811,904바이트 — 한 벌과 limine이 약 130MB를 쓴다. 둘째 슬롯이 들어가고도 약 545MB가
남는다. KU의 갱신은 자리가 모자라면 YES 전에 거절한다(`Rotation.no_room`, install 체인 판정 19a) — old를 버리는 분기는 없고, 여유가
세 배라 더하지 않는다.

### 위험 2 — 비밀번호 해시를 만드는 도구

게스트에 `mkpasswd`도 `openssl` CLI도 없다(확인 5). 길은 셋 — Debian `whois`의 `mkpasswd`(작다, libcrypt) · `openssl passwd -6`
(libcrypto는 이미 있고 CLI만 더한다) · Zig로 `crypt_r` 호출(glibc libcrypt, `$6$` 또는 `$y$`). 셋째가 외부 도구가 없고
설치기 · `tars-config passwd` 둘이 같은 함수를 쓴다. M1이 잰다.

### 위험 3 — sudo의 크기와 PAM 사슬

Debian `sudo`는 libpam · libaudit · libselinux 등을 끈다. `doas`는 작지만 역시 libpam이고 Homebrew는 `sudo`라는 이름을
부른다. PAM은 `/etc/pam.d/sudo`와 `pam_unix.so`가 `/etc/shadow`를 읽는 사슬이다. M2가 둘의 `DT_NEEDED` 합과 initrd 증가를
재고 고른다. `doas`에 `sudo` 이름의 심볼릭 링크를 주는 길(Alpine 방식)도 후보다.

### 위험 4 — pty slave의 소유권

`forkpty`가 `openpty`로 연 slave는 root 소유 620이다. 사용자 셸이 `tty` · `stty`는 되지만(fd는 이미 열려 있다) `script` ·
`tmux`처럼 경로로 다시 여는 도구는 `EACCES`다. terminal이 자식 pid를 받은 뒤 `ptsname`으로 경로를 얻어 `chown` · `chmod`한다.
devpts가 `gid=5,mode=620`으로 붙어 있는지 `main.zig`의 `/dev/pts` 마운트 옵션을 M1이 본다.

### 위험 5 — 라벨 탐색 둘이 서로를 잡는다

설정 탐색은 접두사 `tars-`라 `tars-home`도 설정 후보다. 설정 탐색에서 `tars-home`을 제외하고, 홈 탐색은 라벨 전체 일치만
본다. 게이트 판정 6이 남의 ext4(`debian-home`)를, 기존 설정 체인들이 `tars-config`만 잡히는지를 계속 지킨다.

### 위험 6 — `mke2fs -t ext4`와 `/etc/mke2fs.conf`

`-t ext4`는 `/etc/mke2fs.conf`의 `[fs_types] ext4` 절에서 feature 목록을 읽는다. initrd에 그 파일이 없으면 기본값으로 가는데
그 기본이 has_journal · extent를 켜는지 M0이 `dumpe2fs -h`로 확인한다. 없으면 파일을 굽거나 `-O` 목록을 명시한다.

M0이 닫았다(실측 3). 파일 없이도 e2fsprogs의 내장 기본값이 `has_journal ext_attr resize_inode dir_index orphan_file filetype
extent 64bit flex_bg metadata_csum_seed sparse_super large_file huge_file dir_nlink extra_isize metadata_csum`을 켠다 — Debian의
`mke2fs.conf`가 주는 ext4 목록과 같다. `-O`를 명시하지 않는다. `-e remount-ro`는 `Errors behavior: Remount read-only`로 들어갔다.

### 위험 7 — 홈 없는 부팅의 모양

결정 3이 root 셸로 떨어뜨리는데, 사용자가 `/home/tars`에 무언가를 쓰면 tmpfs다. 셸 프롬프트와 로그 둘 다에서 알게 한다 —
init 로그 한 줄과, terminal의 상태 줄에 `ROOT`를 보이는 것을 M1이 검토한다(상태 줄은 SB 설계의 칸 규칙을 따른다).

### 위험 8 — 설치 질문이 들어가면 `install/check.sh`의 타이핑이 바뀐다

DC 체인은 `--yes`로 돌므로 질문이 안 나온다. 사람의 길(질문 셋)은 게이트가 못 본다 — HANDOFF의 "사용자가 확인할 것"에 적는다.

### 위험 9 — 사용자 이름이 라벨 · 경로 · passwd 줄에 들어간다

콜론 · 개행 · 공백이 passwd 줄을 깨고, `..`가 경로를 깬다. 결정 5의 정규식이 그것을 막는다. `config_edit_test`가 하듯 거절 사례
(`/etc/passwd` · `a:b` · 빈 줄 · 33자)를 단위 테스트로 둔다.

## 비목표

1. Homebrew 설치 자체. `install.sh`를 돌려 막히는 자리(ca-certificates · `file` 명령 · gcc · portable-ruby)를 재는 것은
   PM(Package Manager)이다. `/home/linuxbrew/.linuxbrew`를 미리 만들지도 않는다 — 그 경로는 PM의 결정이다.
2. 다중 사용자. uid 1000 하나다.
3. 로그인 화면 · 화면 잠금. 비밀번호는 sudo의 것이다.
4. ssh로 사용자 계정에 들어오기. sshd의 키는 `/config/ssh/authorized_keys`로 root의 것 그대로다. 사용자 로그인은 PM 뒤에 따로.
5. 기존 디스크의 빈 자리에 p3만 더하기. `--wipe`뿐이다.
6. 쿼터 · 암호화(LUKS) · `/var` · `/opt`를 따로 떼기. 쓰임이 생기면 그때.

## Milestone

- M0 — 디스크. 커널 `CONFIG_EXT4_FS=y`(bzImage 크기 · 부팅 시간 실측), `SFDISK_SCRIPT` 셋째 줄과 768MiB · 256MiB · `MIN_DISK_BYTES`
  4GiB, `mke2fs -t ext4 -L tars-home`, `storage.zig` 둘째 탐색과 제외, `/home` 마운트와 로그, `home/check.sh` 판정 1~3 · 5 · 6 · 7.
  여전히 root 셸이다.
- M1 — 계정. 설치기의 질문 셋과 `--yes` 기본값, 이름 검증, 해시(위험 2), `tars.conf`의 `user=`와 `/config/shadow`, init의
  passwd · group · shadow 생성, 홈 디렉터리, terminal의 setuid · 환경 · chdir · pty chown, 홈 없는 부팅의 root 셸과 표시.
  판정 4 · 5가 사용자로 바뀐다.
- M2 — sudo. 실체 선택(위험 3), `/etc/pam.d`, `sudo tars-config passwd`, `tars-config set`의 `try: sudo` 안내, control 소켓
  권한. 판정 8. 끝나면 PM design을 연다.

## 실측 (M0, 2026-11-02)

### 실측 1 — ext4는 bzImage를 274,432바이트(2.9%) 키우고 부팅 시간은 안 바꾼다(결정 4)

`CONFIG_EXT4_FS=y` 한 줄에 `olddefconfig`가 `CONFIG_JBD2=y` · `CONFIG_FS_MBCACHE=y`를 더했다(`CRC16`은 이미 y). bzImage
9,335,808 → 9,610,240바이트. 빌드는 증분이라 30초였다. 부팅 시간은 install 체인의 콘솔 셸까지가 전후 모두 7~12초, boot 체인의
fish 배너까지 약 16초로 차이가 없다. `CONFIG_EXT2_FS`는 그대로 y이고 `/config`는 여전히 ext2 드라이버가 붙인다(`mounted ext2 at
/config` 그대로). 둘을 합치는 `EXT4_USE_FOR_EXT2`는 열지 않는다 — 2.9%는 투명성의 값으로 싸다.

### 실측 2 — 768MiB ESP의 빈 자리는 674,811,904바이트(위험 1)

설치 직후 `mdir`. 한 벌(bzImage · initrd.cpio · limine · conf · version)과 FAT 구조가 약 130MB. 둘째 슬롯이 들어가고 약 545MB가
남는다. 위험 1을 닫았다.

### 실측 3 — `mke2fs -t ext4`는 3GiB를 4.2초에 굽고, 설치 전체는 13.8초다(위험 6)

TCG. 설치기와 같은 명령(`-q -t ext4 -e remount-ro -L`)으로 3GiB 디스크를 굽는 데 4,195ms. `tars-install --yes` 전체(sfdisk ·
FAT32 · ext2 · ext4 · ESP 복사 · sync)는 13,843ms — DI-M0 실측 8의 ext2 4초 · sfdisk 3.5초에 ext4 4초가 더해진 모양이다. feature
목록은 위험 6 자리에 적었다 — `mke2fs.conf` 없이도 Debian의 ext4 목록 그대로다. lazy_itable_init이 기본이라 inode 표는 마운트
뒤 커널 스레드(`ext4lazyinit`)가 채운다.

### 실측 4 — `/home`의 마운트 줄(결정 1)

`/proc/mounts`: `/dev/nvme0n1p3 /home ext4 rw,nosuid,nodev,relatime` — `sync`가 없다. `/proc/fs/ext4/nvme0n1p3/options`에
`errors=remount-ro` · `data=ordered`. superblock에 심은 오류 동작이 마운트 옵션 문자열 없이 커널에 보인다 — `mountFs`에 data 인자를
더하지 않은 것이 맞았다.

### 실측 5 — 후보는 56이고 ISO 부팅은 한 줄만 는다(결정 3)

설치된 부팅의 후보가 14 + 42 = 56. ISO 부팅(디스크 없음)의 로그는 `no disk labelled tars-* among 14 candidates` 바로 아래
`no disk labelled tars-home among 14 candidates` 한 줄이 늘었고 기다림은 0이다(`max_ms`가 설치된 부팅에만 5000). 다른 스물넷 체인은
이 줄을 판정하지 않으므로 한 줄도 안 바뀌었다(install 체인의 `no disk labelled tars-* among 14` grep은 `-F`라 `tars-home` 줄에 안
걸린다).

### 실측 6 — 라벨 필터가 남의 ext4를 거른다(위험 5, 판정 6)

디스크 전체가 ext4이고 라벨이 `debian-home`인 NVMe를 p3보다 먼저 읽히는 자리(`nvme1n1`, 후보 순서가 디스크 전체 → 파티션)에
붙여도 `home storage /dev/nvme0n1p3 (label tars-home)` 그대로이고 `config storage /dev/nvme0n1p2` 그대로다. `tars-home`이 설정
탐색의 접두사 규칙에 걸리지만 `tarsLabel`이 그 이름만 뺀다 — 단위 검사 8a(`tars-home` · `tars-homex` · `debian-home`)가 그 경계를
본다.

### 게이트가 가르친 것 둘

- 돌고 있는 체인 스크립트를 편집하면 그 체인이 깨진다. bash는 스크립트를 조금씩 읽으며 실행하므로 Task 0의 기준 회차가 Task 5의
  `install/check.sh` 편집 때문에 부팅 4b 뒤 `syntax error near unexpected token`으로 죽었다. 체인이 끝날 때까지 그 파일은 안
  건드린다(`docs/guides/lessons.md`에 적었다).
- 기다리는 글자가 타이핑한 줄에 들어 있으면 에코에서 바로 돌아온다. `hp-mkfs-ms=` · `hp-geo-` · `hp-mounts: `로 기다린 첫 판이
  출력 전에 돌아와 `did not say done`으로 죽었다(`project_gate_screen_echo`의 또 하나). printf의 `%s`가 숫자로 바뀐 완성형이나
  정규식(`hp-mkfs-[0-9]+-ms`)으로 기다린다.
