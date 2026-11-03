# TARS Package Manager — Design

접두사: PM

Status: 승인(2026-11-03) — 진행 중. 다음은 PM-M0 plan.

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

### 결정 4 — 컴파일러는 넣지 않는다. bottle만 보증한다

gcc · `build-essential`은 수백 MB이고, 빌드는 RAM 위 initrd가 감당할 몫이 아니다. bottle이 없는 formula나 `--build-from-source`는
비목표 1이다. 그 길은 `brew install gcc`(Homebrew 쪽 컴파일러)가 열 수 있지만, 이 설계는 보증하지 않는다.

### 결정 5 — `brew shellenv`는 시스템 rc가 조건부로 부른다

`install.sh`의 "Next steps"는 사용자 rc에 `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`를 더하라고 안내한다.
TARS는 initrd의 시스템 rc(bash · zsh · fish 셋)에 "`brew`가 있으면 shellenv"라는 한 줄을 미리 둔다. 사용자가 rc를 고치지
않아도 설치 직후 새 패널부터 `brew`가 PATH에 있다. HP 결정 12의 홈 dotfile이 아니라 시스템 rc인 이유는 두 가지다. 이미 설치된
홈에도 갱신만으로 닿고, dotfile은 사용자의 것으로 남는다. 안내를 따라 사용자 rc에도 넣으면 두 번 eval되지만, 요즘의 shellenv는
PATH에 prefix가 이미 있으면 건너뛰는 것으로 안다 — 해가 없는지 M1이 확인한다.

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
- 포트가 필요하면 45499부터(RP-M0 예약 범위).

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
