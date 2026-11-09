# TARS Package Manager — Design

접두사: PM

Status: 끝남(2026-11-03, PM-M0~M1). 공식 install.sh가 TARS에서 끝까지 가고, `brew install hello`가 bottle 하나로 서며,
재부팅 뒤 망 없이 뜬 화면 셸에서 `hello`가 이름만으로 불린다.

관련 문서: `2026-11-02-tars-home-partition-design.md`(HP. `/home` ext4 · uid 1000 사용자 · Debian `sudo`, 비목표 1이 이 설계로
넘긴 자리) · `docs/decisions/project_home_partition.md` · `docs/guides/carryover.md`의 이미지 뷰어 항목(기본 이미지에 뷰어를
안 넣고 패키지 매니저로 설치한다, 사용자 결정 2026-10-03) · `2026-09-13-tars-guest-network-design.md`(NW. SLIRP 망) · `2026-09-14-tars-inbound-network-design.md`(IN. guestfwd · hostfwd).

## 한 줄 요약

사용자가 화면 셸에서 공식 Homebrew `install.sh`를 그대로 치면 끝까지 가도록, 그 스크립트가 TARS에서 막히는 자리를 기본
이미지 쪽에서 푼다. prefix는 기본값 `/home/linuxbrew/.linuxbrew`(HP의 ext4 `/home` 위)이고, 게이트는 실제 망으로
GitHub에서 Homebrew를 받아 bottle 하나를 설치하고 실행한다.

## 왜 지금인가

HP가 Homebrew의 두 전제를 세웠다. 디스크 위의 `/home`, 그리고 root가 아니면서 `sudo`를 가진 사용자다(`install.sh`는 root이면
`Don't run this as root!`로 멈춘다). HP 비목표 1은 "`install.sh`를 돌려 막히는 자리를 재는 것은 PM"이라고 넘겼다. 이미지
뷰어처럼 기본 이미지에 넣지 않기로 한 도구들(carryover)도 이 길이 서야 설치할 수 있다.

## 사용자가 정한 것 (2026-11-03)

1. 패키지 매니저는 Homebrew다(Nix 등 다른 후보는 비교하지 않는다).
2. 설치는 사용자가 직접 시작한다 — 공식 `install.sh`를 화면 셸에서 친다. TARS가 감싼 명령이나 `tars-install` 때 미리 까는 것은
   하지 않는다. TARS의 일은 그 스크립트가 막히지 않게 하는 것이다.
3. 게이트는 실제 망으로 끝까지 간다 — 게스트가 GitHub에서 `install.sh`와 Homebrew를 받고 bottle 하나를 설치해 실행한다.

## 착수 전에 아는 것 (2026-11-03에 소스에서 확인)

`install.sh`는 2026-11-03의 HEAD(1,243줄)를 읽었다. HEAD는 움직이므로 숫자는 그날의 것이다.

### 확인 1 — `install.sh`는 Linux에서 `/bin`의 절대 경로를 부른다

`MKDIR=("/bin/mkdir" "-p")` · `CHMOD=("/bin/chmod")` · `CHOWN=("/bin/chown")` · `CHGRP=("/bin/chgrp")` · `TOUCH=("/bin/touch")`,
그리고 `/usr/bin/install` · `/usr/bin/stat` · `/usr/bin/sudo`다. Debian은 usrmerge로 `/bin`이 `usr/bin`을 가리키는 링크라
문제가 없다. TARS의 `/bin`은 진짜 디렉터리이고 `sh` 하나만 산다(`kernel/make_initrd.sh`의 머리 주석, `ln -sf ../usr/bin/bash
"$WORKDIR/bin/sh"`). 첫 `execute_sudo /bin/mkdir`에서 멈춘다.

### 확인 2 — 게스트에 없는 도구

`kernel/guest_tools.sh`의 `GUEST_TOOLS`와 `make_initrd.sh`에서 찾지 못한 것: `chgrp` · `install` · `mktemp`(coreutils), `tar` ·
`gzip`, `ldd`(libc-bin의 bash 스크립트), `file`. 있는 것: `bash` · `git` · `curl` · `which`(debianutils) · `stat` · `chown` ·
`chmod` · `touch` · `mkdir` · `uname` · `id` · `ps` · `sort` · `grep` · `sed`.

`install.sh`가 부르는 자리는 이렇다. `INSTALL=("/usr/bin/install" -d …)`, `find_tool`이 `which -a`, `outdated_glibc`가
`ldd --version`(시스템 Ruby가 없으면 portable-ruby를 쓰고, 그 판정에 glibc 버전을 본다), bottle과 portable-ruby는 `.tar.gz`다.

### 확인 3 — git의 https 헬퍼가 없다

`guest_tools.sh`는 `/usr/lib/git-core`를 싣지 않는다. 근거로 적힌 주석은 "네트워크 헬퍼 일곱 … 이 기계는 `# CONFIG_NET is not set`"인데,
NW 이후로는 낡은 사실이다. `install.sh`는 `git fetch`로 `https://github.com/Homebrew/brew`를 받고, `brew update`도 git을
부른다. `git-remote-https`(실체는 `git-remote-http`)가 없으면 `git: 'remote-https' is not a git command`로 멈춘다.

### 확인 4 — 게스트 glibc는 2.41이다

measurements 43. `REQUIRED_GLIBC_VERSION=2.13`을 넘는다. portable-ruby(`REQUIRED_RUBY_VERSION=3.4`)를 쓸 수 있다.

### 확인 5 — 있는 것

- CA 묶음 `/etc/ssl/certs/ca-certificates.crt`(VD 때 `make_initrd.sh`가 mozilla 인증서로 짓는다). `curl`은 https가 된다.
- `/usr/bin/sudo`, 사용자는 `%sudo`(gid 27) 안에 있다. `sudo -n -k -l` · `sudo -v`가 된다(HP 결정 6, doas를 버린 이유).
- `/home`은 `ext4 rw,nosuid,nodev,relatime`(HP 실측 4). Homebrew는 setuid를 쓰지 않는다.
- `install.sh`는 Homebrew 4 이후 homebrew-core를 clone하지 않는다(`HOMEBREW_NO_INSTALL_FROM_API`가 없을 때). 받는 git 저장소는
  `Homebrew/brew` 하나다.

### 확인 6 — 지금까지 어떤 게이트도 바깥 망에 나가지 않았다

net 체인은 guestfwd로 우리 파일을 흘려 넣고, VD 체인은 Groq 대신 컨테이너의 `stub.pl`을 쓴다. PM 체인이 바깥에 기대는 첫
체인이 된다.

## 결정

### 결정 1 — prefix는 기본값 `/home/linuxbrew/.linuxbrew`이고, TARS는 미리 만들지 않는다

bottle은 기본 prefix일 때만 그대로 쏟아진다(prefix가 다르면 대부분 소스 빌드가 된다). `install.sh`가 `sudo mkdir`과
`chown`으로 `/home/linuxbrew`를 만든다. HP가 사용자 이름에서 `linuxbrew`를 거절해 둔 것이 이 자리다(HP 결정 5). TARS가
경로를 미리 만들면 `install.sh`의 권한 판정과 겹치므로 만들지 않는다.

### 결정 2 — `/bin`은 Debian처럼 `usr/bin`을 가리키는 링크가 된다(usrmerge)

후보는 둘이다. `install.sh`가 부르는 다섯 개만 `/bin`에 링크하거나, `/bin` 자체를 `usr/bin`으로 링크하거나. 뒤를 고른다.
Homebrew의 formula와 스크립트는 Debian 계열을 기준으로 `/bin/…`을 가정한다. 다섯 개만 링크하면 다음에 막힐 자리를 하나씩
다시 찾아야 한다. `/bin/sh`는 `usr/bin/sh` → `bash` 링크로 옮긴다(`/bin/sh`가 언제나 bash라는 기존 약속은 그대로).
`/sbin` · `/lib`은 M0의 실측이 요구할 때만 움직인다.

### 결정 3 — 기본 이미지에 도구를 더한다. 범위는 `install.sh`와 `brew install`(bottle)이 실제로 부르는 것

후보 목록은 확인 2 · 3의 것이다. `chgrp` · `install` · `mktemp` · `tar` · `gzip` · `ldd` · `git-remote-http`(+ `git-remote-https`
링크). 앞의 여섯은 새 라이브러리가 0일 것으로 보지만, `git-remote-http`는 `libcurl3t64-gnutls` 쪽을 끌 수 있다. initrd는 RAM
위에 늘 얹히므로(carryover의 이미지 뷰어 항목에서 44.6MB를 거절한 것과 같은 기준), M0는 하나씩 더할 때마다 initrd 크기와
새 `.so`를 잰다. `file`은 Homebrew 문서의 요구 목록에 있지만, `install.sh`와 bottle 설치 경로가 부르는지는 M0가 실제로
돌려서 본다 — 부르지 않으면 넣지 않는다(libmagic과 `magic.mgc`가 크다).

목록 밖에서 새로 막히는 자리가 나오면 같은 기준으로 판정해 이 결정에 덧붙인다.

M0가 덧붙인 것(체인 셋째 · 다섯째 판): `flock`(brew가 `vendor-install ruby`의 잠금을 ruby · flock · python 중 하나로 건다),
`sha256sum`(portable-ruby의 checksum을 shasum · sha256sum · ruby 중 하나로 본다), `locale`(brew의 `setup-locale`이 `locale
charmap`을 본다). 셋 다 sysroot에 이미 있었고 새 라이브러리는 0이다. `file`은 M0의 경로(`install.sh` · `brew update` ·
`brew config`)가 한 번도 부르지 않아 넣지 않았다(실측 7) — M1의 bottle 경로가 다시 본다.

M1이 닫았다: `brew install hello`(bottle 경로)도 `file`을 부르지 않았다(M1 실측 2). `file`은 넣지 않는다.

### 결정 4 — 컴파일러는 넣지 않는다. bottle만 보증한다

gcc · `build-essential`은 수백 MB이고, 빌드는 RAM 위 initrd가 감당할 몫이 아니다. bottle이 없는 formula나 `--build-from-source`는
비목표 1이다. 그 길은 `brew install gcc`(Homebrew 쪽 컴파일러)가 열 수 있지만, 이 설계는 보증하지 않는다.

덧붙임(2026-11-09): 컴파일러는 TP(`2026-11-05-tars-dev-layer-design.md`, 닫힘)가 다른 자리로 열었다 — initrd가 아니라 설치된 디스크의
개발 도구 층(`base` 묶음의 gcc · g++ · make 등)이다. 이 결정의 "initrd에 넣지 않는다"는 그대로고, bottle이 없는 formula를 Homebrew가
소스로 짓는 길은 여전히 보증하지 않는다.

### 결정 5 — `brew shellenv`는 시스템 rc가 조건부로 부른다

`install.sh`의 "Next steps"는 사용자 rc에 `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`를 더하라고 안내한다.
TARS는 initrd의 시스템 rc(bash · zsh · fish 셋)에 "`brew`가 있으면 shellenv"라는 한 줄을 미리 둔다. 사용자가 rc를 고치지
않아도 설치 직후 새 패널부터 `brew`가 PATH에 있다. HP 결정 12의 홈 dotfile이 아니라 시스템 rc인 이유는 두 가지다. 이미 설치된
홈에도 갱신만으로 닿고, dotfile은 사용자의 것으로 남는다. 안내를 따라 사용자 rc에도 넣으면 두 번 eval되지만, 요즘의 shellenv는
PATH에 prefix가 이미 있으면 건너뛰는 것으로 안다 — 해가 없는지 M1이 확인한다.

M1이 확인하고 정한 것:

- 자리는 셋이 컴파일 때 정해 둔 것 — `/etc/bash.bashrc`(Debian 패치) · `/etc/zsh/zshrc` · `/etc/fish/conf.d/homebrew.fish`.
  fish의 `vendor_conf.d`는 패키지의 자리라 쓰지 않는다. `shell_config=off`면 셸이 이 파일까지 건너뛴다 — 사용자가 고른 것.
- 셸 이름을 인자로 준다(`brew shellenv bash`). 안 주면 shellenv가 `ps -p $PPID` → `$SHELL`로 짐작한다.
- 두 번 eval은 해가 없다. shellenv는 `HOMEBREW_PATH`가 `prefix/bin:prefix/sbin:`로 시작하면 아무것도 안 낸다
  (`cmd/shellenv.sh` 머리) — 체인 P9가 PATH의 prefix를 세어 1이다.
- uid를 보지 않는다(M1 plan "정할 것 하나"). `brew.sh`가 `shellenv`를 root 판정보다 먼저 끝내므로 root 셸에서도 조용하고,
  root의 `brew install`은 brew 스스로 거절한다.
- `if`로 쓴다. `[ -x ] && eval` 꼴은 brew가 없을 때(다른 모든 체인) rc의 마지막 상태를 1로 남긴다.
- 비용은 셸을 열 때마다 0.062초(TCG, M1 실측 3). ruby를 안 띄운다.

### 결정 6 — 게이트는 스물여섯째 체인 `pm/check.sh`이고 실제 망을 쓴다

순서는 이렇다. 새 디스크에 `tars-install --wipe`를 하고 설치된 디스크로 부팅한다. SLIRP 망과 `net=dhcp`를 쓰고, 사용자의
화면 셸에서 `sudo -v`로 timestamp를 만든다(HP-M2의 함정: timestamp가 남은 채 파이프를 쓰면 첫 줄이 명령에게 간다 — 그
줄을 따로 친다). 그 다음 `NONINTERACTIVE=1 bash -c "$(curl -fsSL …/install.sh)"`, `brew install hello`, `hello`, 재부팅 뒤
`hello`를 친다.

- `install.sh`는 HEAD를 받는다. 사용자가 받는 것과 같아야 하기 때문이다. 대신 받은 `install.sh`의 sha256과 `brew --version`을
  로그에 남겨, 빨개졌을 때 저쪽이 바뀐 것인지 가른다.
- 바깥 망이 없는 것과 우리 코드가 틀린 것을 섞지 않는다. 체인은 QEMU를 띄우기 전에 컨테이너에서
  `curl -fsS -o /dev/null https://github.com`과 `https://ghcr.io`를 한 번 친다. 실패하면 `pm: external network unavailable`로
  빨개진다(초록으로 건너뛰지 않는다 — 사용자가 고른 것이 "끝까지"다).
- `CHAINS`에 넣는다. 루트 게이트가 바깥에 기대게 되는 것은 위험 1이다.
- 포트가 필요하면 45499부터(RP-M0 예약 범위). M0의 체인은 포트를 안 쓴다.

M0가 이 결정에 더한 것:

- 사용자는 화면 셸이 아니라 시리얼 root 셸에서 `setpriv`로 된다(HP 체인과 같은 모양). sudo는 `sudo -k`와 `sudo -S -v` 두 번으로
  친다 — 한 번에 `sudo -S -k -v`로 치면 비밀번호는 묻되 timestamp를 남기지 않아(sudo(8)), `install.sh`의 `sudo -n -l mkdir`이
  실패하고 `Insufficient permissions to install Homebrew`로 멈춘다(첫 판).
- 이 체인만 `-cpu max`다. TCG의 기본 모델 qemu64에는 SSSE3가 없고 Homebrew는 x86_64 Linux에서 SSSE3를 요구한다(둘째 판,
  `Homebrew's x86_64 support on Linux requires a CPU with SSSE3 support!`). 실기의 x86-64는 Core 2(2006) 이후 전부 갖고 있다.
- 이 체인만 `-m 1024`다. 512MB에서 `brew update`의 ruby가 OOM으로 죽었다(여섯째 판, 실측 4).

### 결정 7 — glibc는 통째로 싣는다(M0)

initrd의 라이브러리는 지금까지 "우리가 싣는 바이너리가 `NEEDED`로 부르는 것"뿐이었다. Homebrew의 bottle과 portable-ruby는
보통의 glibc 시스템에서 빌드돼 glibc 전체를 가정한다 — portable-ruby 4.0.9가 `libdl.so.2: cannot open shared object file`로
멈췄다(넷째 판). libdl은 2.34부터 `libc.so.6`에 합쳐진 빈 stub이라 우리 바이너리는 아무도 안 불렀다. 하나씩 쫓지 않고
libc6가 담는 것 가운데 프로그램이 `NEEDED`로 부를 수 있는 열하나(`make_initrd.sh`의 `GLIBC_LIBS`)를 싣는다. 새로 든 것은
libdl · libanl · libBrokenLocale · libnsl · libmvec 다섯이고 나머지는 이미 있었다. 디버거 · `LD_PRELOAD`용
(libc_malloc_debug · libthread_db · libmemusage · libpcprofile)은 뺀다.

### 결정 8 — `/etc/os-release`(M0, 사용자 2026-11-03)

brew의 `os.sh`가 `source /etc/os-release`로 `PRETTY_NAME`을 읽는다. 없으면 brew를 칠 때마다 경고가 두 줄이고 OS 이름이 커널
버전이 된다. `NAME="TARS"` · `ID=tars` · `VERSION_ID` · `PRETTY_NAME` 넷을 `make_initrd.sh`가 `../VERSION`(init과 같은 자리)에서
짓는다. `ID_LIKE=debian`은 안 적는다 — 유저랜드가 `.deb`에서 왔어도 apt도 dpkg 데이터베이스도 없어서, 그 말을 믿고 apt를
부르는 스크립트에게 거짓말이 된다.

### 결정 9 — `LANG=C.UTF-8`은 init의 환경이 준다(M0, 사용자 2026-11-03)

brew가 칠 때마다 `setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8)`을 냈다. 원인은 brew가 아니라 TARS였다. 로케일
변수가 하나도 없는 환경에서 뜬 fish는 스스로 `LC_CTYPE=en_US.UTF-8`을 export하는데 게스트에는 그 데이터가 없다 — 그래서
시리얼 콘솔 셸 · ssh 세션 · 서비스에서 띄운 모든 프로그램이 ASCII(`ANSI_X3.4-1968`)로 떨어지고 있었다. 화면 셸만
terminal의 `setenv("LANG", "C.UTF-8")` 덕에 멀쩡했다(HI-M1). `LC_CTYPE`가 `LANG`보다 앞서므로 게이트가 `LANG`을 줘도 안
고쳐졌다(다섯째 판, amd64 chroot에서 재현). `init/src/environ.zig`에 `LANG_ENTRY`를 두어 PATH · XDG · TZ 뒤에 붙이고, ssh
세션의 env 목록(SV-M2 결정 9)에도 같은 값이 간다. 그 파일의 머리 주석이 이미 "LANG은 갈릴 이유가 없는데 terminal에 있다"고
적어 둔 자리다. terminal의 setenv는 같은 값을 다시 쓸 뿐이라 남긴다.

### 결정 10 — libstdc++는 버전이 붙은 진짜 파일과 SONAME 링크로 싣는다(M1, 사용자 2026-11-03)

M1 첫 판에서 의존이 0인 `hello`에 gcc 16(463MB) · binutils(135MB)와 그 의존 여섯이 암묵 의존으로 붙었고, gcc의
post-install이 실패해 `brew install`이 rc 1이었다. Homebrew는 시스템 libstdc++가 CI 기준(`LINUX_LIBSTDCXX_CI_VERSION`
6.0.33, Ubuntu noble)보다 낮으면 모든 formula에 gcc를 붙이는데(`extend/os/linux/dependency_collector.rb`의
`gcc_dep_if_needed` ← `needs_compiler_formula?`), 그 버전을 파일의 realpath 이름에서 읽는다(`os/linux/libstdcxx.rb`).
`copy_lib_deps`는 SONAME 링크를 따라가 내용을 `libstdc++.so.6`이라는 이름으로 복사해 왔으므로 버전이 `6`으로 읽혔다.
sysroot의 실체는 `libstdc++.so.6.0.33`이라 이름만 맞으면 기준과 같다.

후보는 둘이었다. libstdc++ 하나만, 또는 모든 `.so`를 Debian 모양(실체 + SONAME 링크)으로. 사용자가 앞을 골랐다 —
Homebrew가 이름으로 버전을 읽는 것은 libstdc++뿐이고(glibc는 `ldd --version`), 뒤는 initrd의 라이브러리 약 200개의 모양을
바꿔 체인 전부를 영향 범위에 넣는다. `make_initrd.sh`의 `GLIBC_LIBS` 블록 뒤에서 놓는다. 고친 뒤 `brew config`의
`Host libstdc++: 6.0.33`이고, 체인 P7이 hello에 의존이 붙으면 빨갛다.

결정 4(컴파일러 없음)와는 다른 축이다 — gcc가 붙은 이유는 컴파일러가 없어서가 아니라 런타임 libstdc++가 낡아 보여서였다.

## 위험

### 위험 1 — 루트 게이트가 바깥 망과 GitHub에 기댄다

GitHub 장애, rate limit(익명 ghcr.io 토큰 · git fetch), `install.sh` HEAD의 변경이 우리 게이트를 빨갛게 만들 수 있다. 앞의 둘은
결정 6의 사전 확인이 이름을 붙이고, 셋째는 sha256 기록이 가른다. 그래도 자주 빨개지면 이 체인만 `CHAINS` 밖의 별도 명령으로
옮기는 것이 다음 후보다(사용자가 고른 "둘 다" 대신 "끝까지"를 고른 자리라 그때 다시 묻는다).

### 위험 2 — TCG에서의 시간

`git fetch`가 `Homebrew/brew`의 전체 이력을 받는다(태그로 stable을 고르기 때문). index-pack과 portable-ruby 압축 풀기가 TCG에서
몇 분이 될 수 있다. M0가 잰다. 체인 하나가 루트 게이트 전체(지금 약 10분 50초)를 크게 늘리면, prebuild와 lanes의 배치를
다시 본다.

### 위험 3 — initrd가 커진다

결정 3의 도구는 RAM 위에 늘 얹힌다. `git-remote-http`의 라이브러리 사슬이 가장 크다. 한도는 정해 두지 않고 M0의 실측으로
판정한다. 크면 비목표 3(첫 설치 때 디스크에 받는 길)을 다시 연다.

### 위험 4 — 게스트 메모리

portable-ruby와 git index-pack이 함께 돌 때의 RSS가 게이트 QEMU의 `-m`과 tmpfs 루트를 함께 누른다. Homebrew 쪽 파일은 전부
`/home`(디스크)에 놓이지만 `/tmp`는 tmpfs다. `HOMEBREW_TEMP`가 기본 `/tmp`이므로 bottle을 푸는 자리가 RAM이다. M0가 잰다.

### 위험 5 — hostname `(none)`

carryover의 HP 절에 남은 것이다. Homebrew가 hostname으로 무엇을 하는지(analytics · lock 이름) M0가 로그에서 본다. 막히면
이 설계가 hostname을 연다.

### 위험 6 — Homebrew는 사용자가 커널 · 시스템을 고쳐 줄 수 있다고 가정한다

`brew doctor`는 TARS가 Debian이 아니라서 경고를 낼 것이다(`/etc/os-release` 등). 경고는 기록만 하고, `brew install`(bottle)을
막는 것만 고친다.

## 비목표

1. 소스 빌드(컴파일러 · `build-essential`). 결정 4.
2. Homebrew를 이미지나 `tars-install`에 미리 싣는 것. 사용자 결정 2.
3. 결정 3의 도구를 디스크로 옮겨 initrd를 가볍게 하는 것. 위험 3이 요구할 때 연다.
4. cask(Linux에서는 대부분 해당 없음)와 사용자 여럿의 Homebrew 공유.
5. 이미지 뷰어 같은 특정 formula의 동작 보증. 게이트는 `hello` 하나로 길을 본다. 이미지 뷰어(`chafa`)는 PM 뒤에 사용자가
   실기에서 처음 쳐 보는 것으로 남긴다.

## Milestone

- PM-M0: 막히는 자리 실측과 해소. 결정 2(usrmerge) · 결정 3(도구)을 넣고 `install.sh`가 `brew --version`까지 가는 것을 체인
  `pm/check.sh`의 첫 판으로 본다. 위험 2 · 3 · 4 · 5의 숫자를 잰다. `guest_tools.sh`의 낡은 git-core 주석을 고친다.
- PM-M1: bottle 하나. `brew install hello` · `hello`, 결정 5(shellenv)를 새 패널에서, 재부팅 뒤 `hello`가 남는지(`/home` 위),
  `brew doctor`의 출력을 기록한다.

M1의 plan은 M0의 실측을 본 뒤에 쓴다.

## 실측 (M0, 2026-11-03)

`install.sh` sha256 `5f333bbe…08ccb148`(1,243줄), 설치된 brew는 `Homebrew 7.0.12`, portable-ruby 4.0.9. 값은 체인 일곱째 판(첫
초록)의 것이다.

### 실측 1 — initrd는 2,157,333바이트 → 결정 7 뒤 약 3.3MB 커진다(결정 3 · 7, 위험 3)

usrmerge와 층 19의 첫 일곱(`chgrp` · `install` · `mktemp` · `ldd` · `tar` · `gzip` · `git-remote-http`)만 넣었을 때 gzip initrd
119,534,779 → 121,692,112(+1.8%), 첫 archive를 푼 크기 271,351,808 → 275,906,048. 새 라이브러리는 셋 — `libcurl-gnutls.so.4`
963,560 · `libngtcp2.so.16` 301,592 · `libngtcp2_crypto_gnutls.so.8` 43,608. gnutls 사슬(gnutls · nettle · hogweed · gmp ·
p11-kit · tasn1)은 curl → librtmp가 이미 데려와 있었다. 가장 큰 한 파일은 `git-remote-http` 자체(2,399,952)다. 그 뒤
`flock` 35,288 · `sha256sum` 55,752 · `locale` 46,656 · `os-release` 한 장, 결정 7의 다섯(libmvec 1,018,072가 대부분, 합 약
1.16MB)이 더해졌다. 위험 3이 걱정한 "수십 MB"는 아니다.

### 실측 2 — `install.sh`는 TCG 1GiB에서 140초다(위험 2)

`git fetch`(Homebrew/brew 전체 이력) · `brew update` · portable-ruby 받기와 풀기까지 포함한 값이다. 512MB였던 여섯째 판은 커널
시각 1525초에 OOM으로 끝났다 — 메모리가 모자라면 페이지 캐시를 계속 내쫓아 10배 넘게 느려진다.

### 실측 3 — `brew config` 첫 실행 10초(위험 2)

portable-ruby는 `install.sh`의 `brew update`가 이미 받아 두므로 이 값은 ruby를 띄우는 시간이다.

### 실측 4 — 512MB에서 OOM, 1GiB에서 최소 MemAvailable 496,632kB(위험 4)

512MB OOM 순간: ruby anon-rss 151,664kB, `unevictable` 278,368kB(RAM에 풀린 initrd). initrd가 상주하는 TARS에서 brew를 쓰려면
initrd 약 280MB + brew의 ruby 약 150MB + 나머지가 든다. 1GiB에서는 OOM 0, 최소 여유 약 485MB.

### 실측 5 — Homebrew 하나가 `/home`에서 약 270MB(디스크)

`/home/linuxbrew/.linuxbrew` 222,332kB, `~/.cache/Homebrew` 52,256kB, `/home` 사용 276,472kB / 7,125,020kB(5%). 최소
디스크(4GiB)의 `/home` 약 3GiB에 넉넉히 들어간다 — M1에서 체인의 디스크를 줄여도 된다.

### 실측 6 — hostname `(none)`은 brew를 막지 않는다(위험 5)

`(none)`이 나온 27줄은 셸 프롬프트(`root@(none)`)다. brew의 말에는 없었다.

### 실측 7 — `file`은 M0의 경로가 부르지 않는다(결정 3)

`file: command not found`류의 줄 0. M1의 bottle 경로가 다시 본다.

### 실측 8 — 체인 199초, 루트 게이트 26/26 12분 48초(위험 2)

루트 게이트에서 PM-M0은 199초로 TD-M2와 같이 가장 길다. lanes 446초 · prebuild 320초(init과 initrd가 바뀌었다), cut log
lines 전부 0. 체인 하나가 1GiB QEMU라 JOBS 계산(줄 하나 1GiB)에 들어간다. `brew config`의 줄은 `OS: TARS 0.1.3` · `Host glibc:
2.41` · `Homebrew Ruby: 4.0.9 => …/vendor/portable-ruby/4.0.9/bin/ruby` · `gcc: N/A`(결정 4) · `CPU: single-core 64-bit amd_k7`
(TCG가 흉내 내는 이름)이다.

### M0의 판들이 가르친 것

1. `sudo -S -k -v`는 timestamp를 남기지 않는다 — `-k`를 다른 옵션과 함께 쓰면 캐시를 무시하고 갱신도 안 한다. HP-M2의 함정을
   피하려면 `sudo -k`를 먼저 혼자 친다.
2. QEMU TCG의 기본 CPU(qemu64)는 SSSE3가 없다. 바깥에서 받은 x86_64 바이너리를 돌리는 체인은 `-cpu max`가 필요할 수 있다.
3. initrd의 라이브러리 고르기(`copy_lib_deps`)는 "우리가 싣는 것"만 본다. 바깥 바이너리는 glibc 전체를 가정한다(결정 7).
4. fish는 로케일 변수가 없으면 `LC_CTYPE=en_US.UTF-8`을 스스로 export한다. 이 값이 LANG보다 앞서서 아래 프로세스 모두의 로케일을
   깨뜨렸다(결정 9). amd64 컨테이너(OrbStack Rosetta)에 initrd 트리를 풀고 `chroot`하면 QEMU 없이 몇 초에 재현된다.
5. 게이트의 진입 검사가 둘을 잡았다 — `| grep -q`(SIGPIPE와 pipefail), NIC를 `"$@"`로만 넘긴 QEMU 호출(검사기가 못 본다).

## 실측 (M1, 2026-11-03)

값은 체인 둘째 판(첫 초록)의 것이다. `install.sh` sha256은 M0와 같고(`5f333bbe…08ccb148`), brew는 `Homebrew 7.0.12`.

### 실측 M1-1 — `brew install hello` 9초, bottle 하나(결정 4 · 10, 위험 2)

`Pouring hello--2.12.3.x86_64_linux.bottle.1.tar.gz` 하나, `Cellar/hello/2.12.3` 58 files 755.1KB. 자동 갱신 0번(`install.sh`가
막 갱신했다). 결정 10 전의 첫 판은 gcc 16.2.0(2,256 files 463.1MB) · binutils 2.47(135.2MB) · gmp · isl · mpfr · libmpc · lz4 · xz ·
zlib-ng-compat · zstd를 먼저 붓고 gcc의 post-install에서 실패했다.

### 실측 M1-2 — bottle 경로도 `file`을 부르지 않는다(결정 3)

`brew install`의 출력에 `file`이 없다는 줄 0.

### 실측 M1-3 — `brew shellenv bash` 0.062초(결정 5)

셸을 열 때마다 시스템 rc가 더하는 값이다(TCG).

### 실측 M1-4 — `brew doctor`는 rc 1, 경고 셋(위험 6)

판정하지 않고 적는다.

- `No developer tools installed.` — 결정 4 그대로.
- `Landlock is not supported by this Linux kernel.` — 커널에 `CONFIG_SECURITY_LANDLOCK`이 없다. Homebrew의 Linux sandbox가
  꺼지고 `brew install`이 `Sandbox unavailable: processing downloaded files without sandboxing!`를 찍는다. 설치는 막지 않는다
  (`carryover.md`의 PM 절).
- `Homebrew's "bin" was not found in your PATH.` — 게이트가 `doctor`를 비대화형 `bash -c`(PATH `/usr/bin:/bin`)로 돌려서다.
  시스템 rc는 대화형 셸만 읽는다. 화면 셸에서는 P10이 이름으로 `hello`를 부른다.

### 실측 M1-5 — 최소 디스크의 `/home` 10%

디스크 4 GiB + 2 MiB(`MIN_DISK_BYTES`)에서 `/home` 3,021,608kB 중 279,528kB. prefix 224,100kB · `~/.cache/Homebrew` 54,564kB.

### 실측 M1-6 — 체인 226초, 루트 게이트 26/26 13분 24초(위험 2)

M0의 199초에 `brew install` · `doctor` · 부팅 3(망 없음, 화면에 `hello`)이 더해졌다. 메모리 최솟값 MemAvailable 490,788kB, OOM 0.
루트 게이트에서는 233초로 가장 길다. 게이트 전체는 prebuild 323초(initrd가 바뀌었다) + lanes 481초, cut log lines 전부 0.
`CHAINS`의 라벨은 `PM-M0` 그대로다 — 접두사 PM은 2026-08-19의 Power Management와 겹쳐서 `PM-M1`은 이미 `power/check.sh`의 라벨이다.

### M1의 판들이 가르친 것

1. Homebrew가 Linux에서 gcc를 끄는 기준은 컴파일러가 아니라 시스템 libstdc++의 버전이고, 그것을 파일 이름에서 읽는다(결정 10).
   initrd가 라이브러리를 SONAME 이름으로 싣는 것이 바깥 프로그램에게는 "버전 모름"이다.
2. check.sh의 진입 검사(`| grep -q` 찾기)는 글자로 본다 — 줄 머리의 `|| ! grep -q`도 파이프로 읽는다. M0의 판정 줄을
   shellcheck SC2015 때문에 `if ! A || ! B`로 고쳤다가 루트 게이트 첫 판이 진입에서 멈췄다. `if ! { A && B; }`로 썼다.
3. PM-M0의 커밋은 push되지 않아 CI가 그 SC2015(`make quick` 빨강)를 못 봤다. 커밋 전에 `make quick`을 돈다.
