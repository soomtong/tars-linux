# TARS Userland Tools — Design

**Date:** 2026-09-10
**Status:** **설계 완료 — 착수 전.** milestone 넷(UT-M0~M3)을 계획했다. 착수 전
게이트 기준선은 열 체인 3/3으로 **20분 29.84초**(RM-M3 시점)다.

사용자가 2026-09-10에 지목했다 — **"터미널 환경에서 기본적인 unix/linux
utilities가 부족하다. 예를 들면 `ls` 같은 것들이 없다."** 그리고 조건을 하나
달았다: **"gnu 기본 유틸리티도 좋지만 modern alternative가 기본 탑재되면
좋겠다."** 세션 중에 하나가 더 붙었다 — **"tars-linux는 거의 개발용으로
사용되기 때문에 git은 필수 도구가 될 것"**이다.

**이름.** 저장소 어휘로 **Userland Tools (UT)**라 부른다. `UT`는 비어 있다
(BF · DF · TF · ZM · CP · IP · PM · HD · TR · CM · GL · CN · CS · SP · RC ·
CC · HI · IS · SH · FP · RM이 쓰인 것 전부다).

## 한 줄 요약

**게스트에서 쓸 도구 한 벌을 세우고, 그 이름이 손에 닿게 한다.**

```
  유틸리티 넷(cat·uname·mkdir·sleep) · PATH 없음      ← 지금
  GNU 한 벌 + 모던 한 벌 + git · PATH 있음            ← UT가 더한다
```

**"넣는다"와 "닿는다"가 다르다.** `ls`를 initrd에 넣어도 `PATH`가 없으면
`/usr/bin/ls`라고 쳐야 한다. 이 서브프로젝트는 두 일이고 **닿는 쪽이 먼저다** —
아래 결정 1과 UT-M0.

## 왜 지금인가

RM이 닫힌 뒤 HANDOFF이 남긴 후보 여섯 중 어느 것도 아니다. **사용자가 기계를
실제로 써 보고 발견한 것**이고, 그 점이 이 후보의 무게다.

앞의 서브프로젝트들은 전부 **기계가 켜지는 쪽**을 만들었다 — 부팅하고, 그리고,
받아치고, 설정을 읽고, 실기에서 뜬다. **그 위에서 무엇을 할 수 있는가는 아무도
안 만들었다.** 그래서 유틸리티가 넷뿐인 채로 스무 개 milestone을 건너왔다.

넷이 어떻게 들어왔는지가 그 사실을 그대로 보여 준다.

| 유틸리티 | 왜 들어왔나 |
|---|---|
| `cat` · `uname` · `mkdir` | 게이트 판정에 필요해서 하나씩 |
| `sleep` | IP-M0이 **Ctrl+C로 죽일 자식**이 필요해서 |

**넷 다 "사람이 쓰라고" 넣은 것이 아니다.** `ls`가 없는 것은 누락이 아니라
아무도 필요하다고 말한 적이 없어서다. 사용자가 처음으로 말했다.

## 착수 전에 실측한 것 — **다시 조사하지 말 것**

전부 2026-09-10에 `tars-devcontainer` 안에서 쟀다.

### 1. `PATH`가 없다 — 이것이 진짜 벽이다

`docs/decisions/project_guest_environment.md`가 2026-08-17에 적어 뒀다.
게스트의 모든 프로세스의 환경변수는 **커널이 PID 1에게 준 두 개**가 전부다.

```c
/* linux/init/main.c */
const char *envp_init[MAX_INIT_ENVS+2] = { "HOME=/", "TERM=linux", NULL, };
```

PID 1이 이 블록을 **그대로 흘려보낸다**(`init/src/main.zig:307`이
`init.environ.block`을 `execve`의 `envp`로 넘긴다). 중간에 아무도 무엇도
추가하지 않는다.

**그 문서가 `PATH`를 안 채운 이유를 이렇게 적어 뒀다** — *"채우는 자리가
PID 1인지, 터미널인지, 셸 설정인지는 **설정 시스템과 함께 결정할 문제**이고,
게이트에 절대 경로를 쓰는 비용은 키 몇 개다."*

**그 설정 시스템이 CP-M2로 2026-08-15에 생겼다. 유예가 만료된 자리다.** 그리고
"키 몇 개"가 더 이상 참이 아니다 — 게이트가 아니라 사람이 쓰는 기계가 됐다.

### 2. initrd에 `/bin`도 `/tmp`도 `/etc`도 없다

```
config  dev  init  lib  lib64  proc  sys  terminal  usr  vendor
```

`kernel/make_initrd.sh`가 만드는 것은 `/usr/bin` · `/proc` · `/sys` · `/dev` ·
`/config` 다섯뿐이다. 이것이 git에 그대로 걸린다.

| 없는 것 | 무엇이 안 되나 |
|---|---|
| `/bin/sh` | git의 셸 기반 서브커맨드(`git mergetool` · `git request-pull` · `git rebase`의 일부)와 모든 `#!/bin/sh` 스크립트 |
| `/tmp` | git이 임시 파일을 못 만든다. 편집기의 스왑·백업도 갈 자리가 없다 |
| `/etc/passwd` | `whoami`가 이름을 못 낸다. **git이 커밋 작성자를 여기서 유추하려다 실패한다** |

### 3. GNU는 이미 저장소 안에 있다 — 비용이 복사 줄뿐이다

`devcontainer/Dockerfile:82`가 **`coreutils:amd64`를 통째로** 받아 sysroot에
풀어 뒀다. `make_initrd.sh`가 그중 넷만 복사하고 있었을 뿐이다.

```
sysroot의 /usr/bin: 124개
```

바이너리 하나가 42~154KB다.

```
ls 154  cp 146  mv 146  rm 74  ln 74  mkdir 86  rmdir 42  cat 46  head 50
tail 78  sort 118  uniq 54  wc 66  cut 54  tr 58  date 98  df 106  du 110
stat 102  touch 86  chmod 70  chown 74  readlink 54  realpath 54  sleep 42
echo 42  pwd 42  env 54  dirname 42  basename 42  seq 46  id 50  whoami 42
tee 46  sync 42                                              합계 2,490 KB
```

**`grep`·`find`·`sed`·`awk`·`diff`는 coreutils가 아니라 별도 패키지다** —
sysroot에 없어서 Dockerfile에 추가해야 한다. 그래도 싸다.

```
grep 198  find 227  xargs 74  sed 127  mawk 166  diff 159  cmp 54
less 243  ps 150  top 135  dmesg 88                          합계 1,621 KB
```

새로 필요한 라이브러리는 **둘뿐**이다 — `sed`가 `libacl1`(74KB),
`ps`/`top`이 `libproc2`(237KB). 나머지가 요구하는 `libpcre2-8` ·
`libselinux1` · `libtinfo6` · `libm`은 **이미 initrd에 있다.**

### 4. 모던 도구가 거의 공짜다 — 둘만 빼고

`make_initrd.sh`의 `copy_lib_deps`가 `DT_NEEDED`를 재귀로 따라가므로, 비용은
바이너리 크기가 아니라 **딸려 오는 라이브러리**다. 바이너리별로 쟀다.

| 도구 | 바이너리 | `DT_NEEDED`(libc 제외) | 새 라이브러리 |
|---|---|---|---|
| `rg` | 5,142 KB | `libpcre2-8` `libgcc_s` | **없음** |
| `fd` | 3,422 KB | `libgcc_s` | **없음** |
| `sd` | 2,470 KB | `libgcc_s` | **없음** |
| `procs` | 5,471 KB | `libgcc_s` `libm` | **없음** |
| `duf` | 2,531 KB | **비어 있음** (Go 정적) | **없음** |
| `tree` | 91 KB | 없음 | **없음** |
| `hyperfine` | 1,346 KB | `libgcc_s` `libm` | **없음** |
| `htop` | 350 KB | `libncursesw` `libtinfo` `libm` | `libncursesw6` 419 KB |
| `ncdu` | 94 KB | `libncursesw` `libtinfo` | (htop과 공유) |
| `jq` | 30 KB | `libjq` | `libjq` 434 + `libonig` 677 KB |
| **`eza`** | 1,527 KB | **`libgit2`** `libgcc_s` `libm` | **아래 사슬** |
| **`bat`** | 5,443 KB | **`libgit2`** `libgcc_s` `libm` | (eza와 공유) |

### 5. `eza`·`bat`이 데려오는 `libgit2` 사슬은 15개 11.4MB다

둘 다 git 저장소 상태를 보여주는 기능 때문에 `libgit2`를 링크한다. **게스트에
git이 없어도 라이브러리는 필요하다** — 동적 링크는 그 기능을 쓰느냐와 무관하다.

```
libgit2.so.1.9        1,268 KB
libcrypto.so.3        6,364 KB   ← OpenSSL
libkrb5.so.3            863 KB   ┐
libgssapi_krb5.so.2     338 KB   │
libk5crypto.so.3        182 KB   ├ Kerberos 한 벌
libkrb5support.so.0      50 KB   │
libkeyutils.so.1         21 KB   │
libcom_err.so.2          17 KB   ┘
libmbedcrypto.so.16     610 KB   ┐
libmbedtls.so.21        309 KB   ├ mbedTLS
libmbedx509.so.7         85 KB   ┘
libssh2.so.1            290 KB
libzstd.so.1            805 KB
libz.so.1               122 KB
libhttp_parser.so.2.9    41 KB
                     ─────────
                     11,375 KB (15개)
```

**네트워크가 없는 기계에 TLS·Kerberos·SSH 스택이다.** 사용자가 이 대가를 알고
Debian 경로를 유지하기로 정했다 — 아래 결정 3.

### 6. 게스트에 네트워크가 없다

```
kernel/.config:  # CONFIG_NET is not set
```

**네트워크 스택이 아예 없다.** 이 사실이 후보 셋을 떨어뜨리고 git의 모양을
정한다.

### 7. git이 생각보다 훨씬 싸다 — 네트워크 헬퍼를 빼면

```
git 바이너리      3,987 KB
git의 NEEDED      libpcre2-8.so.0 (이미 있음) · libz.so.1 (122 KB)
```

**`libgit2` 사슬 15개보다 git 하나가 훨씬 싸다.** `/usr/lib/git-core`가 25MB로
보이지만 **168개 중 대부분은 `git` 자신에 대한 하드링크**이고, 별도 실체인
것은 **네트워크 헬퍼 일곱**이다.

```
git-daemon 2,278  git-http-backend 2,274  git-http-fetch 2,323
git-http-push 2,335  git-imap-send 2,331  git-remote-http 2,343
git-sh-i18n--envsubst 2,262                          합계 약 16 MB
```

**일곱 다 `# CONFIG_NET is not set`인 기계에서 한 줄도 안 돈다.** 안 넣는다 —
결정 5.

### 8. `/config`는 읽기·쓰기로 마운트돼 있다

```zig
// init/src/main.zig:92
return mountFs(found.path, "/config", "ext2", linux.MS.SYNCHRONOUS);
```

`MS_RDONLY`가 아니다. **`git config --global user.name`이 그대로 영속한다** —
결정 8이 이 사실 위에 선다.

### 9. Debian이 이름을 바꿔 놓은 것이 둘이다

```
fd-find:  ./usr/lib/cargo/bin/fd  (실체 3,422 KB)
          ./usr/bin/fdfind -> ../lib/cargo/bin/fd   ← 심볼릭 링크
bat:      ./usr/bin/batcat
```

이름 충돌을 피하려는 Debian의 정책이다. **우리 initrd에서는 그 제약이 없다** —
결정 4.

### 10. 셸이 무조건 no-config로 뜬다 — 이것이 후보 둘을 떨어뜨린다

```zig
// init/src/main.zig:482
const shell_flag = shell.noConfigFlag();   // --no-config / --norc / -f
```

**조건 없이 붙는다.** `zoxide`도 `fzf`도 셸 rc 파일에 훅이나 키바인딩을 걸어야
동작하는데, **걸 자리가 없다.** 넣어도 안 도는 바이너리다.

### 11. 커널이 압축기를 전부 알고 있다

```
CONFIG_RD_GZIP=y  CONFIG_RD_BZIP2=y  CONFIG_RD_LZMA=y  CONFIG_RD_XZ=y
CONFIG_RD_LZO=y   CONFIG_RD_LZ4=y    CONFIG_RD_ZSTD=y
```

**위험 1의 처방이 이미 손에 있다.** `make_initrd.sh`의 `gzip -6`을 바꾸는 데
커널 재설정이 필요 없다.

### 12. 지금 initrd의 크기

```
gzip:        11,076,327 바이트
풀었을 때:   33,371,648 바이트
```

### 13. trixie에 없는 것 셋

`helix` · `dust` · `bottom`이 `apt-cache show`에서 MISSING이다. `helix`는
upstream release(`helix-25.07.1-x86_64-linux.tar.xz`, 16,636,076 바이트)로만
받을 수 있다.

### 14. 편집기 후보를 전부 쟀다

| 후보 | 바이너리 | 새 라이브러리 | 런타임 데이터 | trixie |
|---|---|---|---|---|
| `nano` | 296 KB | `libncursesw6` 419 KB | 없음 | 있음 |
| `vim.tiny` | 1,720 KB | `libacl1`(sed와 공유) | 없음 | 있음 |
| `neovim` | 5,118 KB | **9개** — luajit · luv · lpeg · libuv · msgpack-c · tree-sitter · unibilium · vterm | **24 MB**(syntax 8.1M · doc 5.3M · lua 2.5M · autoload 2.2M) | 있음 |
| `micro` | 14,519 KB | **없음**(Go 정적) | 없음 | 있음 |
| `helix` | — | — | tree-sitter 문법 포함 | **없음** |

## 비목표

**1. 네트워킹.** 사용자가 2026-09-10에 별도 서브프로젝트로 미루기로 정했다.
`CONFIG_NET` · NIC 드라이버 · DHCP · DNS · TLS 인증서까지 층이 두껍고, **게이트가
그것을 어떻게 볼지도 따로 설계해야 한다.** 한 서브프로젝트에 둘을 넣으면 둘 다
엉성해진다. **그때까지 이 기계의 git은 로컬 전용이다** — `clone`·`fetch`·
`push`·`pull`이 안 되고 `init`·`add`·`commit`·`log`·`diff`·`branch`·`stash`가
된다.

**2. 쓸 수 있는 작업 공간(`/home`의 영속화).** initramfs는 tmpfs라 **재부팅하면
사라진다.** 게스트에서 만든 git 저장소도 전원을 끄면 없다. 영속하는 것은
`/config`(ext2 디스크) 하나뿐이고 그건 `tars.conf`용이다. **이것이 이 조사에서
가장 무거운 발견이지만 이번 범위 밖이다** — 디스크 레이아웃 · 파티션 · 마운트
정책이 따로 설계될 크기이고, RM-M2 결정 12("파티션을 안 본다")를 다시 열어야
할 수도 있다. **이번에는 git 설정 하나만 `/config`에 둔다**(결정 8).

**3. 패키지 매니저.** 사용자가 `herdr`(https://herdr.dev)를 언급하며 **"Homebrew
for Linux로 관리된다. 지금은 건너뛴다"**고 정했다. 이 방향이 UT의 크기를
정해 준다 — **지금은 바탕 한 벌만 굽고, 긴 꼬리는 나중에 패키지 매니저가
맡는다.** 그리고 Homebrew는 네트워크와 git을 둘 다 요구하므로 비목표 1 뒤다.

**4. `neovim`·`helix`.** 사용자가 즐겨 쓰는 편집기 둘이지만 이번엔 안 넣는다.
`helix`는 trixie에 없어 **결정 3(조달 경로 하나)을 깨는 유일한 항목**이 되고,
`neovim`은 라이브러리 9개 + 런타임 24MB로 **UT 전체보다 무거운 축**이다.
사용자가 "가벼운 것 하나를 먼저"로 정했다. 편집기를 제대로 올리는 것은 **런타임을
어디서 자를지**가 본체인 별도의 일이다.

**5. `git-delta`.** git이 필수가 되면서 다시 후보가 됐고 `libgit2`를 이미
들이므로 **라이브러리 비용이 0에 가깝다**(바이너리 6,743 KB). 그래도 이번엔 안
고른다 — 사용자가 고른 목록에 없다. **다음에 후보를 찾을 때 이 문단을 먼저
읽을 것.**

**6. `zoxide`·`fzf`.** 실측 10이 이유다. 셸이 무조건 no-config로 뜨는 한 훅을
걸 자리가 없다. **셸 설정을 다루는 서브프로젝트가 생기면 그때 함께 온다.**

**7. `tealdeer`(tldr).** tldr 페이지 캐시를 네트워크로 받아야 한다(실측 6).
비목표 1 뒤다.

**8. GNU와 모던의 이름을 섞기.** `ls`를 치면 `eza`가 뜨게 하는 것 — 결정 2가
안 고른 쪽이다.

## 결정

### 결정 1 — `PATH`는 PID 1이 짓는다. 자식 둘이 다 받는다

`project_guest_environment`가 규칙을 적어 뒀다 — *"새 환경변수가 필요해지면
그것을 넣는 자리가 **`TERM`처럼 자식마다 달라야 하는 값인지** 먼저 판단한다."*

**`PATH`는 갈릴 이유가 없는 값이다.** 화면 셸도 시리얼 콘솔 셸도 같은
`/usr/bin`을 본다. 그래서 `terminal`의 `setenv` 옆이 아니라 **PID 1**이다.

같은 문서가 `LANG`에 대해 자기비판을 적어 뒀다 — *"**TERM이 둘로 갈리는 것과
이유가 다르다** — 그쪽은 갈려야 맞고, 이쪽은 갈릴 이유가 없는데도 갈려 있다."*
**같은 실수를 한 번 더 하지 않는다.**

**대가는 코드다.** PID 1은 지금 커널의 envp 블록을 **그대로** 넘긴다. 항목을
더하려면 블록을 새로 지어야 한다. HI-M1이 `LANG`에서 이 값을 안 치르고
`terminal` 쪽으로 갔던 자리다.

**값은 `PATH=/usr/bin:/bin`이다.** 둘뿐이다 — `/usr/bin`에 전부 넣고 `/bin`은
`sh` 하나를 위해 있다(결정 6). 나중에 패키지 매니저가 생기면 그때 늘린다.

**안 고른 둘.** `terminal`의 `setenv`(=시리얼 셸이 못 받고 `LANG`의 실수가
반복된다) · `tars.conf`의 설정 항목(=고를 이유가 지금 없고, 잘못 고르면 셸이
아무 명령도 못 찾는 뚱을 사용자에게 건넨다).

### 결정 2 — GNU와 모던을 둘 다 넣고, 이름은 각자 그대로 쓴다

사용자가 골랐다. `ls`는 GNU `ls`, `eza`는 `eza`다.

**게이트의 화면 판정을 하나도 안 흔드는 것이 이 선택의 값이다.** 모던 도구는
색·아이콘·정렬을 기본으로 켜므로 `ls`를 `eza`로 덮으면 화면을 grep하는 체인들이
흔들릴 수 있다 — TR design 위험 1이 `TERM`에서 겪은 것과 같은 종류다.

**안 고른 둘.** 모던을 GNU 이름으로 덮어쓰기(=화면 판정이 흔들리고 플래그가
달라 셸 스크립트 호환이 깨진다) · 모던만 넣기(=`cp`·`rm`·`mv`처럼 대체재가 없는
자리가 통째로 비고 사용자의 원래 불만을 절반만 푼다).

### 결정 3 — 조달은 Debian `.deb` 하나로 통일한다. `libgit2` 11.4MB를 감수한다

사용자가 골랐다. **`eza`·`bat`을 upstream musl 정적 빌드로 받으면 의존이 0이
되어 11.4MB가 통째로 사라지지만**(`eza` 1.3MB · `bat` 3.4MB 압축), 조달 경로가
둘로 갈린다.

**하나로 두는 값**: 버전이 trixie에 고정되고, Debian이 검증한 빌드이며,
`apt-get download` 한 자리만 읽으면 무엇이 들어오는지 안다.

**대가**: 네트워크 없는 기계에 OpenSSL 6.4MB와 Kerberos 한 벌이 들어온다.

**그런데 git이 필수가 되면서 대가의 성격이 바뀌었다.** `eza --git`이 파일 상태를
칠하고 `bat`이 변경된 줄을 표시한다 — **게스트에 git 저장소가 있을 때만 의미
있는 기능이었고, 이제 있게 된다.** `libgit2`가 놀고 있는 라이브러리가 아니다.

### 결정 4 — initrd 안의 이름은 우리가 정한다

Debian의 `batcat`·`fdfind`(실측 9)를 **`/usr/bin/bat`·`/usr/bin/fd`**로 넣는다.
`mawk`는 `/usr/bin/awk`로, `vim.tiny`는 `/usr/bin/vi`와 `/usr/bin/vim`으로
넣는다.

**새 규칙이 아니다.** `make_initrd.sh`가 이미 그렇게 쓰여 있다.

```bash
# 찾는 곳: sysroot는 .deb를 푼 자리라 usrmerge 규칙대로 /usr/lib/... 이다.
# 넣는 곳: initrd 안은 /lib/x86_64-linux-gnu로 고정한다
```

`fd`의 실체가 `/usr/lib/cargo/bin/fd`이고 `/usr/bin/fdfind`가 심볼릭 링크이므로,
**실체를 복사한다** — 심볼릭 링크를 복사하면 initrd 안에서 끊어진다.

### 결정 5 — git의 네트워크 헬퍼 일곱은 안 넣는다

실측 7이 근거다. 16MB이고 `# CONFIG_NET is not set`인 기계에서 한 줄도 안 돈다.

**"쓸 수 있는데 안 넣는다"가 아니라 "못 쓰는 것을 안 넣는다"이다.** 비목표 1이
풀리면 그때 이 일곱이 같이 온다 — 그 자리를 여기 적어 둔다.

### 결정 6 — 뼈대 넷을 함께 만든다

실측 2가 근거다. `PATH`만으로는 부족하다.

| 무엇 | 어떻게 |
|---|---|
| `/bin/sh` | `/usr/bin/bash`를 가리키는 심볼릭 링크 |
| `/tmp` | 빈 디렉터리, 모드 `1777` |
| `/etc/passwd` · `/etc/group` | root 한 줄씩. 셸은 `/bin/sh` |
| `/etc` | 위 둘의 자리 |

**`/bin/sh`가 `bash`인 이유**는 셋 중 유일하게 POSIX sh 모드를 갖고 있어서다
(`fish`는 POSIX 호환이 아니고, `zsh`도 `sh`로 불리면 모드를 바꾸지만 셸 선택이
`tars.conf`로 바뀌어도 `/bin/sh`는 고정이어야 한다). **`tars.conf`의
`shell` 설정과 무관하게 언제나 `bash`다** — `#!/bin/sh` 스크립트가 사용자의
셸 취향에 따라 동작이 바뀌면 안 된다.

### 결정 7 — `make_initrd.sh`를 목록 배열로 리팩터한다

지금은 바이너리 하나에 세 줄(`cp` · `chmod` · `copy_lib_deps`)을 손으로 쓴다.
**50개를 그렇게 쓸 수 없다.** 그리고 손으로 쓰는 한 **`cp`는 했는데
`copy_lib_deps`를 빼먹는 실수**가 언제든 난다 — 그 실패는 빌드 때가 아니라
**게스트가 부팅한 뒤 그 명령을 처음 칠 때** 나타난다.

`src:dest` 쌍의 배열 하나를 돌면서 셋을 다 한다. 고칠 자리가 하나가 되고,
`check.sh`의 initrd 목록 검사가 **같은 배열**을 볼 수 있다.

**이것은 "관련 없는 리팩터"가 아니다** — 이 서브프로젝트가 그 파일에 50줄을
더하는 일이고, 그 전에 모양을 바꾸지 않으면 파일이 못 읽게 된다.

### 결정 8 — `/.gitconfig`를 `/config/gitconfig`로 잇는다

git은 전역 설정을 `$HOME/.gitconfig`에서 읽고, 게스트의 `HOME`은 `/`다(실측 1).
그런데 `/`는 tmpfs라 **재부팅하면 사라진다**(비목표 2).

**처방은 심볼릭 링크 하나다.** initrd에 `/.gitconfig -> /config/gitconfig`를
넣는다.

**새 환경변수도 새 코드 경로도 없다.** `GIT_CONFIG_GLOBAL`을 설정하는 쪽은
"어디에 넣을까"(PID 1인지 terminal인지)를 또 정해야 하고, 그것은 결정 1이 이미
치른 비용을 한 번 더 치르는 일이다.

**설정 디스크를 못 찾으면 링크가 끊긴 채로 남는데, 그것이 맞는 폴백이다.**
git은 열리지 않는 설정 파일을 "설정이 없다"로 다룬다 — RM-M2가 라벨을 못
찾았을 때 기본값으로 부팅을 계속하는 것과 같은 모양이다.

**쓰기도 된다**(실측 8). `/config`가 `MS_SYNCHRONOUS`로 읽기·쓰기 마운트라
`git config --global user.name`이 그대로 디스크에 남는다.

### 결정 9 — 게이트에 열한번째 체인 `tools/check.sh`를 만든다

서브프로젝트 하나에 체인 하나가 이 저장소의 규칙이고, `check.sh`의 `CHAINS`
배열이 **서브프로젝트의 실제 상태를 가장 정확하게 말하는 자리**다.

**체인은 UT-M0에서 태어나 milestone마다 자란다.** M0이 "`PATH`가 선다"를 보고,
M1~M3이 각자 검사를 더한다.

## Milestone 넷

| | 무엇 | 검증 |
|---|---|---|
| **UT-M0** | 뼈대 전부(결정 1·6) + `ls` **하나만** + 크기 스파이크 | 게스트 셸에서 절대 경로 없이 `ls`가 돈다. **시리얼 셸에서도** |
| **UT-M1** | 층 1(GNU) + `make_initrd.sh` 리팩터(결정 7) | initrd 목록 검사 + 화면에서 실행 |
| **UT-M2** | 층 2(모던 12개) | `libgit2` 사슬이 실제로 딸려 오는가 · 이름이 `fd`/`bat`인가 |
| **UT-M3** | 층 3(git · `vim.tiny` · 결정 8) | `git init`→`add`→`commit`→`log`가 한 번에 돈다 |

**층 0이 먼저인 것이 구조적이다.** `PATH`가 없으면 층 1~3은 전부 절대 경로로만
부르는 죽은 파일이고, `/bin/sh`가 없으면 git의 셸 서브커맨드가 안 돌고,
`/tmp`가 없으면 git과 편집기가 임시 파일을 못 만든다.

## UT-M0의 모양

**`ls` 하나만 넣는 것이 핵심이다.** 통로(`PATH`)가 열렸는지를 도구 50개와 섞지
않는다 — 실패하면 원인이 하나뿐이다.

M0이 만드는 것.

1. `init/src/main.zig` — 커널 envp 블록을 복사해 `PATH=/usr/bin:/bin`을 더한
   새 블록을 짓고 자식 둘에게 넘긴다.
2. `kernel/make_initrd.sh` — `/bin/sh` 심볼릭 링크 · `/tmp` · `/etc/passwd` ·
   `/etc/group` · `/usr/bin/ls`.
3. `tools/check.sh` — 열한번째 체인. 화면 셸에서 `ls`, 시리얼 셸에서 `ls`,
   `echo $PATH`, `/bin/sh -c 'echo ok'`.

**그리고 크기 스파이크.** 최종 목록만큼(약 50MB)의 더미 바이트를 initrd에 넣고
BF 체인 부팅 시간과 `gzip` 시간을 잰다. **재기 전에는 압축기를 안 고친다** —
위험 1을 보라.

## 최종 목록

**층 1 — GNU (3.8 MB, 새 라이브러리 `libacl1`·`libproc2`)**

```
coreutils 35  ls cp mv rm ln mkdir rmdir cat head tail sort uniq wc cut tr
              date df du stat touch chmod chown readlink realpath sleep echo
              pwd env dirname basename seq id whoami tee sync
별도 패키지   grep find xargs sed awk(mawk) diff cmp less ps top dmesg
```

**층 2 — 모던 (27.3 MB, 새 라이브러리 `libgit2` 사슬 15 · `libncursesw6` ·
`libjq` · `libonig`)**

```
eza  bat  fd  rg  sd  procs  htop  tree  duf  ncdu  jq  hyperfine
```

**층 3 — 개발 (5.6 MB, 새 라이브러리 없음 — `libz`는 `libgit2` 사슬에 이미 있다)**

```
git(네트워크 헬퍼 7개 제외)   vim.tiny → /usr/bin/vi · /usr/bin/vim
```

**합계 약 +49.6 MB**(바이너리 36.7 + 라이브러리 12.9). initrd 33.4 MB →
**약 83 MB**(풀었을 때). **새로 들어오는 라이브러리는 20개다** — `libgit2`
사슬 15 · `libncursesw6` · `libjq` · `libonig` · `libacl1` · `libproc2`.

## 위험

### 위험 1 — initrd가 세 배가 되면 BF 체인이 못 뜰 수 있다

TF-M2 시절 **53MB에서 부팅조차 못 한 벽**이 있었다. limine이 BIOS INT13h로
ISO를 읽는 경로가 에뮬레이션에서 극단적으로 느리기 때문이다
(`kernel/make_initrd.sh`의 주석에 남아 있다).

지금 limine이 읽는 것은 **gzip 11.1MB**이고, 이 계획 뒤에는 **약 30MB**로
추정된다(Rust 바이너리는 이미 밀도가 높아 압축이 잘 안 된다). **벽의 절반을
넘는다.**

**처방은 재고 나서 정한다.** UT-M0의 스파이크가 먼저다. `CONFIG_RD_ZSTD`·
`CONFIG_RD_XZ`가 이미 켜져 있으므로(실측 11) `gzip -6`을 바꾸는 데 커널
재설정이 필요 없다. **`zstd`는 압축률이 gzip보다 좋으면서 푸는 것이 더 빠르고,
`xz`는 가장 작지만 푸는 것이 느리다** — 어느 쪽이 맞는지는 **부팅 시간을 재서**
정한다.

**GL-M1이 남긴 교훈이 여기 그대로 적용된다** — 그때 `gzip -9`가 `-6`보다
1.3% 작아지자고 6.7초를 더 쓰는 것을 재서 `-6`으로 내렸고, 루트 게이트가 그
6.7초를 24회 치르고 있었다. **압축기는 크기만 보고 고르는 것이 아니다.**

### 위험 2 — 게이트가 길어진다

열한번째 체인이 3회 돌고, initrd가 커져 `gzip` 시간과 부팅 시간이 늘어난다.
GL이 54분 15초 → 16분 01초로 줄여 놓은 것을 되돌리는 방향이다.

**매 milestone마다 게이트 시간을 기록한다.** 나중에 "언제부터 느려졌나"를 캘 수
있게 남기는 것이 처방이고, RM이 M0~M3마다 초 단위로 적어 둔 것과 같은 방식이다.

### 위험 3 — 새 라이브러리가 부팅 후에야 드러난다

`copy_lib_deps`를 빼먹으면 **빌드는 성공하고 게스트가 그 명령을 처음 칠 때**
`error while loading shared libraries`가 난다. 도구가 50개면 그중 하나를 게이트가
안 치는 일이 생긴다.

**처방이 결정 7이다.** 배열 하나를 돌면서 `cp`와 `copy_lib_deps`를 함께 하므로
**빼먹을 자리가 없어진다.** `make_initrd.sh`는 소네임을 못 찾으면 즉시 죽는데,
그것이 정상 동작이다.

### 위험 4 — 화면 판정이 흔들린다

도구가 늘면 게스트 화면에 나오는 글자가 달라질 수 있다. TR design 위험 1이
`TERM`에서 겪은 종류다.

**결정 2가 이 위험의 대부분을 이미 막았다** — 기존 이름을 아무것도 덮어쓰지
않으므로, 기존 열 체인이 치는 명령의 출력이 달라질 이유가 없다. **다만 `PATH`가
생기면서 셸의 명령 완성·해시 동작이 달라질 수 있다** — UT-M0이 열 체인을 전부
돌려 확인한다.
