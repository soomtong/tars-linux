# TP-M4 — base 보강(빌드 · 디버깅 · 원격 · 오프라인 문서)과 홈에 까는 길

> 2026-11-06, `181271e` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP-M3을 끝낸 뒤 검토에서 나온 빈자리를 메운다. 사용자(2026-11-06): "추천해 준 것 모두 마음에 든다. 모두 설치해줘." design의
Milestone 순서에서 JVM 언어보다 앞에 끼운다. 그래서 JVM 언어 이후는 번호가 하나씩 밀린다(TP-M5가 JVM).

0.2와의 관계: 0.2.0은 TP 전체를 끝낸 뒤에 낸다(`docs/decisions/project_release_0_2.md`). 이 milestone도 그 선행 조건의 하나다.

## 착수 전 확인 (2026-11-06)

1. initrd에 이미 있는 개발 관련 도구: git · curl · less · diff · tar · jq · rg · fd · fzf · bat · htop · tree · vim · nc. 없는 것:
   perl · pkg-config · cmake · ninja · autotools · patch · file · xz · zstd · zip · unzip · ssh · rsync · man · gdb · strace · ltrace · valgrind ·
   xxd · shellcheck · ctags · gpg. `tar -xJf`도 xz가 없어 안 된다. git은 있지만 ssh가 없어 `git clone git@…`이 안 된다.
2. perl은 lang-script에 우연히 실려 있다. php · lua를 거둘 때 딸려 온 `ucf` · `libtext-*-perl`이 `perl-base`에 기대고, harvest의 의존
   폐포 단계가 trixie-slim의 perl-base(5.40.1-6+deb13u1)를 실었다. perl-base에는 `strict` · `warnings` · `File::Temp` · `Getopt::Long` ·
   `List::Util`이 있고, `Data::Dumper` · `JSON::PP` · `Digest::SHA` · `Time::HiRes` · `Test::More` · `IO::Socket::SSL` · `perldoc` · `cpan`은
   없다(chroot에서 확인). 같은 경로로 Debconf의 perl 모듈 101개도 실렸다 — 거두는 컨테이너의 postinst만 쓰는 것이다.
3. trixie의 판(`apt-cache policy`, amd64 slim): perl 5.40.1-6+deb13u1, pkgconf 1.8.1-4, autoconf 2.72-3.1, automake 1:1.17-4,
   libtool 2.5.4-4, patch 2.8-2, file 1:5.46-5, xz-utils 5.8.1-1+deb13u2, zstd 1.5.7+dfsg-1, zip 3.0-15+deb13u1, unzip 6.0-29+deb13u1,
   openssh-client 1:10.0p1-7+deb13u4, rsync 3.5.0+ds1-0+deb13u1, man-db 2.13.1-1, manpages · manpages-dev 6.9.1-1, gdb 16.3-1,
   strace 6.13+ds-1, ltrace 0.7.91~git20230705.8eabf68-4+b1, valgrind 1:3.24.0-3, xxd 2:9.1.1230-2+deb13u1, gnupg 2.4.7-21+deb13u1.
4. upstream이 있는 넷(design 결정 1의 순서로 Debian보다 앞선다):

   | 도구 | 판 | 받는 것 | 크기 | Debian 판 |
   |---|---|---|---|---|
   | cmake | 4.4.5 | `cmake-4.4.5-linux-x86_64.tar.gz` | 64,865,573 | 3.31.6 |
   | ninja | 1.13.2 | `ninja-linux.zip` | 134,040 | 1.12.1 |
   | shellcheck | 0.11.0 | `shellcheck-v0.11.0.linux.x86_64.tar.xz` | 2,559,196 | 0.10.0 |
   | universal-ctags | 2026.10.08 | ctags-nightly-build의 `uctags-2026.10.08-linux-x86_64.release.tar.xz` | 1,763,448 | 5.9.20210829(2021) |

   sha256은 GitHub 자산의 `digest`. ctags는 안정판 바이너리를 내지 않고, 프로젝트 조직(universal-ctags)이 날마다 굽는 판을 낸다 — 그것이
   이 도구의 upstream 바이너리다.
5. trixie-slim의 `/etc/dpkg/dpkg.cfg.d/docker`가 `/usr/share/man/*` · `/usr/share/doc/*`(copyright 빼고) · `/usr/share/info/*` ·
   `/usr/share/locale/*`을 풀지 않는다. 이대로 거두면 `manpages-dev`를 넣어도 man 페이지가 하나도 없다. base의 gcc · make의 man 페이지도
   지금 없다.
6. 시스템 rc는 initrd에 있다(`kernel/make_initrd.sh`가 `/etc/bash.bashrc` · `/etc/zsh/zshrc` · `/etc/fish/conf.d/{homebrew,mise}.fish`를
   짓는다). 묶음의 `etc/`는 init이 `/etc`로 복사하지만 initrd와 같은 경로는 verify가 막는다(design 결정 4). 그래서 묶음이 rc를 고칠 수는
   없고, 새 경로에 조각을 둘 수는 있다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 모두 base에 둔다. base는 "어느 언어를 쓰든 필요한 바닥"이 된다(지금은 C · C++ · 어셈블리). `util` 묶음(design 터미널 유틸리티 표)은 사용자가
   Homebrew 이름으로 준 목록이고 이 milestone의 것과 겹치지 않는다. 겹치는 이름이 나오면 util milestone이 그때 가른다.
   - `debian` 스물두 줄(판은 확인 3 그대로): perl · pkgconf · autoconf · automake · libtool · patch · file · xz-utils · zstd · zip · unzip ·
     openssh-client · rsync · man-db · manpages · manpages-dev · gdb · strace · ltrace · valgrind · xxd · gnupg.
   - `upstream` 넷: cmake(`bin/`의 cmake · ctest · cpack · ccmake), ninja(`strip=0 exe=ninja`), shellcheck(`exe=shellcheck`), ctags.
B. 거두기는 man 페이지를 싣는다. harvest가 `apt-get install` 전에 `docker` 설정에서 `/usr/share/man/*` 제외 한 줄만 지운다. doc · info ·
   locale은 그대로 뺀다(copyright는 지금처럼 남는다). 이 변경으로 base가 다시 거둬지고 gcc · make 등의 man 페이지가 들어온다. initrd의 도구
   man 페이지는 여전히 없다(design 비목표 아님 — initrd 쪽 일이다).
C. Debconf는 싣지 않는다. `harvest-skip.tsv`에 `debconf`(거두는 컨테이너의 postinst만 쓴다)를 더한다. perl-base는 perl이 끌고 오므로 그대로
   싣는다 — base와 lang-script가 같은 판을 실어 `shared`로 센다.
D. 묶음이 직접 싣는 파일: `devlayer/files/<묶음>/`의 트리를 build.sh가 뿌리에 그대로 얹는다(upstream · debian 다음, verify 전). 업스트림에
   없는 파일을 묶음에 넣는 첫 자리다. 그래서 디렉터리 하나로 모으고 stamp에 넣는다. TP-M3 결정 E가 미룬 `EXTERNALLY-MANAGED`가 여기 든다.
E. 홈에 까는 길(TP-M3 결정 E의 후속, 사용자가 이 검토의 추천을 받았다):
   - initrd의 bash · zsh rc가 맨 앞에서 `/etc/tars/rc.d/*.sh`를 읽는다(없으면 아무 일도 없다). 그다음이 지금의 Homebrew · mise 줄이다. 그래서
     PATH의 앞은 mise → Homebrew → 묶음 조각이 넣은 홈 디렉터리 → `/usr/local/bin` 순서가 된다. fish는 `/etc/fish/conf.d/`를 이름 순으로
     읽으므로 조각 이름을 `10-<묶음>.fish`로 해서 homebrew.fish보다 앞에 둔다.
   - lang-script의 조각: `NPM_CONFIG_PREFIX=$HOME/.npm-global`과 그 `bin`, `GEM_HOME=$HOME/.local/share/gem`과 그 `bin`. python에는
     `EXTERNALLY-MANAGED`(venv · `pip install --user`를 안내하는 글)를 `lib/python3.15/`에 둔다.
   - lang-native의 조각: `$HOME/.cargo/bin`, `$HOME/go/bin`(`cargo install` · `go install`이 쓰는 자리 — 이미 홈이라 PATH만).
   - 조각은 홈 디렉터리가 아직 없어도 PATH에 넣는다. 그래야 처음 `npm -g`로 깐 명령이 셸을 다시 열지 않아도 이름으로 선다.
F. 체인: devtools의 부팅 2에 base 보강의 hello를 더한다(망 없이, 사용자로).
   1. `cmake -G Ninja` + `ninja`로 h.c를 짓고 실행
   2. autotools: `configure.ac` · `Makefile.am` 두 줄짜리로 `autoreconf -i && ./configure && make`
   3. `pkg-config --modversion`(홈에 둔 작은 `.pc`를 `PKG_CONFIG_PATH`로)
   4. perl: `Data::Dumper` · `JSON::PP` · `Digest::SHA` · `Test::More`를 쓰는 한 줄, `perldoc -l strict`
   5. `gdb -batch -ex run -ex bt`로 일부러 죽는 프로그램의 백트레이스에 함수 이름, `strace -c` · `ltrace -c`의 요약, `valgrind --leak-check=full
      --error-exitcode=9`가 일부러 새는 프로그램에서 9
   6. 압축 넷(xz · zstd · zip · unzip)의 왕복과 `tar -xJf`, `file`이 ELF를 알아보는지, `patch`, `xxd -r` 왕복
   7. `ssh -V` · `ssh-keygen -t ed25519 -N "" -f …`, `rsync -a` 로컬 복사, `gpg --batch --quick-gen-key`(망 없이)
   8. `man 3 printf`가 `MANPAGER=cat`으로 `printf, fprintf`를 찍는다. `man gcc`도
   9. `shellcheck`가 일부러 틀린 스크립트에서 SC2086, `ctags -x`가 h.c의 `main`
   10. 홈에 까는 길(결정 E): fish로 `echo $NPM_CONFIG_PREFIX` · `gem env gemdir`, 시스템 python으로 `pip install x`가 `externally-managed`로 거절
   시간 상한은 처음에는 하나에 300초, 잰 뒤 세 배(60초 아래로는 안 내린다). valgrind는 TCG에서 느릴 것이다(위험 1).
   체인이 420초를 넘으면(TP-M3 결정 F) lang-script · base 보강의 hello를 새 체인(monitor 45505)으로 뗀다.
G. 릴리스 절차(`project_release.md`)에 두 줄: `make iso ISO_LAYERS=…`, 굽기 전 `devlayer/build/*.stamp` 지우기(dev-20261106에서 겪었다).

## 할 일

1. 매니페스트: base에 debian 스물둘 · upstream 넷(결정 A). `harvest-skip.tsv`에 debconf(결정 C).
2. `harvest.sh`: man 제외 풀기(결정 B). `build.sh`: `devlayer/files/<묶음>/` 얹기와 stamp(결정 D).
3. `kernel/make_initrd.sh`: bash · zsh rc의 rc.d 줄(결정 E). 바꾸기 전에 `rg -n 'bash.bashrc|zshrc' */check.sh`로 rc 내용을 보는 체인을 찾는다.
4. `devlayer/files/lang-script/`와 `devlayer/files/lang-native/`의 조각, `EXTERNALLY-MANAGED`.
5. `make dev-layers` — 숫자: base의 증가분(도구별), man 페이지 수, 받기 · 거두기 · 굽기 시간.
6. chroot로 결정 F의 hello를 먼저 돌린다(TP-M3 할 일 4의 모양 — `/dev/null`을 만들어 둔다, TP-M3에서 perl이 그것으로 넘어졌다).
7. 빨강: (a) harvest의 man 제외를 그대로 두면 체인의 `man 3 printf`가 멈춘다. (b) rc.d 줄을 빼면 결정 F-10이 멈춘다.
8. 체인 혼자 한 번, 숫자로 상한을 고친다. 420초를 넘으면 가른다.
9. `make quick`, 루트 게이트. design 고치기(도구 목록에 base 보강 줄, 결정 1에 `devlayer/files/`, Milestone의 순서), project_release.md, HANDOFF.

## 판정

- `make dev-layers`가 초록이고, base의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 결정 F의 열 덩이가 망 없이 사용자로 돈다. 할 일 7의 빨강 둘을 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 위험

1. valgrind · gdb는 TCG에서 느리다. valgrind는 명령을 다시 번역하는 도구라 TCG 위에서 수십 배일 수 있다. 상한 안에 안 들면 hello를 더 작게
   한다.
2. gdb는 Debian에서 `libpython3.13`에 기댄다. Debian의 python 라이브러리가 `/usr/lib`에 들어온다 — `/usr/bin/python3`는 안 생겨야 한다
   (lang-script의 `/usr/local/bin/python3`와 이름을 다투지 않게). 생기면 harvest-skip이나 PATH로 가른다.
3. base가 크게 는다(어림 풀면 +250MiB, gdb · valgrind · perl · man). ISO가 1GB를 넘는다. GitHub release의 2GiB 한도는 아직 멀다.
4. 시스템 rc를 바꾸면 pm · mise 체인의 PATH 판정이 흔들릴 수 있다 — 그 체인에는 묶음이 없어 rc.d가 비지만, 줄 하나가 늘어난 것을 보는
   검사가 있으면 걸린다(할 일 3).

## 확인한 것

(구현하며 채운다)

## 결과

(구현 뒤 채운다)
