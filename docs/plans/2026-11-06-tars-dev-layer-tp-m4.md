# TP-M4 — base 보강(빌드 · 디버깅 · 원격 · 오프라인 문서)과 홈에 까는 길

> 2026-11-06, `181271e` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP-M3을 끝낸 뒤 검토에서 나온 빈자리를 메운다. 사용자(2026-11-06): "추천해 준 것 모두 마음에 든다. 모두 설치해줘." design의
Milestone 순서에서 JVM 언어보다 앞에 끼운다. 그래서 JVM 언어 이후는 번호가 하나씩 밀린다(TP-M5가 JVM).

사용자 결정(2026-11-06, plan을 쓰는 중): "보통 /usr 은 읽기 전용이어도 /usr/local 은 쓰기 가능이니까 우리도 그 관행을 따르자." 이어서 고른
것: 쓰기 층은 디스크 p3에(재부팅에도 남는다), 쓰는 것은 root만(sudo), 패키지 관리자의 전역 설치는 `/usr/local`로 통일. TP design 결정 9
("`/usr`는 읽기 전용")와 비목표 3("사용자가 개발 도구 층을 고치는 것")을 `/usr/local`에 한해 뒤집는다 — 결정 H.

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
   없는 파일을 묶음에 넣는 첫 자리다. 그래서 디렉터리 하나로 모으고 stamp에 넣는다. 결정 E의 설정 파일과 rc 조각이 여기 든다.
E. 전역 설치는 `/usr/local`로(사용자 결정, 결정 H 위에서). root가 `sudo`로 깐 것은 실행 파일이 `/usr/local/bin`에 서고, 라이브러리는
   묶음의 도구 디렉터리가 아니라 `/usr/local` 아래 판에 묶이지 않는 자리에 놓인다 — 그래야 묶음이 새 판(예: python 3.15.3)으로 바뀌어도
   깐 것이 남는다. 설정은 각 도구가 스스로 읽는 자리에 두고 환경 변수로 하지 않는다(`sudo`가 환경을 지운다).
   - npm: 묶음 안 npm의 builtin 설정(`lib/node_modules/npm/npmrc`)에 `prefix=/usr/local`. `npm i -g`가 `/usr/local/lib/node_modules`와
     `/usr/local/bin`에 쓴다(Debian · Homebrew의 node와 같은 모양).
   - gem: ruby의 시스템 gemrc(rv-ruby의 sysconfdir — 구현 때 `ruby -e 'p Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE'`로 자리를 본다)에
     `gem: --bindir /usr/local/bin`과 `GEM_HOME` 대신 `install: --install-dir /usr/local/lib/ruby/gems/4.0.0`, 그 자리를 `GEM_PATH`에 넣는
     방법은 구현 때 고른다(`Gem.default_dir`을 바꾸는 `operating_system.rb`가 후보).
   - pip: python의 site 설정(`<sys.prefix>/pip.conf`)에 `[install] prefix = /usr/local`. 그리고 묶음의 site-packages에 `tars-local.pth`
     한 줄(`/usr/local/lib/python3.15/site-packages`)을 둬서 그 자리가 `sys.path`에 든다. venv는 자기 `sys.prefix`를 보므로 이 설정을 안 탄다.
   - 셋 다 `sudo` 없이 사용자가 부르면 `/usr/local`에 못 써서 실패한다 — 관행대로다. 사용자 자리는 각 도구의 `--user` · venv · `npm prefix`다.
   - initrd의 bash · zsh rc가 맨 앞에서 `/etc/tars/rc.d/*.sh`를 읽는다(없으면 아무 일도 없다). fish는 `/etc/fish/conf.d/`를 이름 순으로 읽으므로
     조각 이름을 `10-<묶음>.fish`로 해서 homebrew.fish보다 앞에 둔다. 조각은 lang-native의 `$HOME/.cargo/bin` · `$HOME/go/bin`뿐이다
     (`cargo install` · `go install`은 원래 홈에 쓴다). 홈 디렉터리가 아직 없어도 넣는다 — 처음 깐 명령이 셸을 다시 열지 않아도 선다.
   - TP-M3 결정 E의 `EXTERNALLY-MANAGED`는 넣지 않는다.
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
   10. `/usr/local`(결정 E · H): root가 망 없이 로컬 패키지 하나씩을 전역으로 깐다 — `npm pack`한 tarball을 `npm i -g`, `gem build`한 .gem을
       `gem install --local`, 손으로 지은 wheel을 `pip install --no-index`. 셋의 명령이 `/usr/local/bin`에 서고 사용자로 돈다. 사용자 tars의
       `touch /usr/local/x`는 `Permission denied`, `/usr/bin`은 여전히 `Read-only file system`. fish의 PATH에 `~/.cargo/bin`.
       부팅 3(lang-jvm이 깨진 부팅)에서도 셋이 그대로 있다 — 디스크에 남는다.
   시간 상한은 처음에는 하나에 300초, 잰 뒤 세 배(60초 아래로는 안 내린다). valgrind는 TCG에서 느릴 것이다(위험 1).
   체인이 420초를 넘으면(TP-M3 결정 F) lang-script · base 보강의 hello를 새 체인(monitor 45505)으로 뗀다.
H. `/usr/local`의 쓰기 층(사용자 결정). init의 `layers.mountAll`이 `/usr` overlay 뒤에(묶음이 없어서 `/usr` overlay가 없을 때도, p3가
   붙은 부팅이면) `/usr/local`에 overlay를 하나 더 건다: `lowerdir=/usr/local,upperdir=/home/.tars/local/upper,workdir=/home/.tars/local/work`.
   upper · work는 없으면 init이 root 0755로 만든다. 묶음이 없는 부팅에서 `/usr/local`이 없으면 만든다(그때 `/usr`는 initrd의 RAM이다).
   - overlay를 overlay 위에 쌓는 것은 커널의 쌓기 한도(2) 안이다. mount 자리와 lowerdir이 같은 경로여도 lower는 mount 전에 풀린다.
   - p3는 `nosuid,nodev`로 붙어 있다 — `/usr/local`의 setuid는 서지 않는다. 그대로 둔다(개발 도구에 setuid가 필요한 일은 드물다).
   - 실패하면 `/usr/local`은 지금처럼 읽기 전용이고 `tars-init: /usr/local: <이유>` 한 줄. 부팅은 간다(design 결정 11의 결).
   - 묶음 갱신(`tars-install`)은 upper를 건드리지 않는다. 같은 경로면 upper(사용자가 깐 것)가 묶음의 것을 가린다 — 관행의 `/usr/local`과
     같다. 비우는 길은 `sudo rm -rf /home/.tars/local`(다음 부팅에 빈 upper)이다. 이 한 줄을 `running-tars.md`에 둔다.
   - 로그: `tars-init: /usr/local writable (upper on /home/.tars/local)`.
G. 릴리스 절차(`project_release.md`)에 두 줄: `make iso ISO_LAYERS=…`, 굽기 전 `devlayer/build/*.stamp` 지우기(dev-20261106에서 겪었다).

## 할 일

1. 매니페스트: base에 debian 스물둘 · upstream 넷(결정 A). `harvest-skip.tsv`에 debconf(결정 C).
2. `harvest.sh`: man 제외 풀기(결정 B). `build.sh`: `devlayer/files/<묶음>/` 얹기와 stamp(결정 D).
3. init `layers.zig`: `/usr/local` overlay(결정 H)와 순수한 판단의 호스트 검사. `kernel/make_initrd.sh`: bash · zsh rc의 rc.d 줄(결정 E). 바꾸기 전에 `rg -n 'bash.bashrc|zshrc' */check.sh`로 rc 내용을 보는 체인을 찾는다.
4. `devlayer/files/lang-script/`(npmrc · gemrc 또는 operating_system.rb · pip.conf · tars-local.pth)와 `devlayer/files/lang-native/`의 조각.
5. `make dev-layers` — 숫자: base의 증가분(도구별), man 페이지 수, 받기 · 거두기 · 굽기 시간.
6. chroot로 결정 F의 hello를 먼저 돌린다(TP-M3 할 일 4의 모양 — `/dev/null`을 만들어 둔다, TP-M3에서 perl이 그것으로 넘어졌다).
7. 빨강: (a) harvest의 man 제외를 그대로 두면 체인의 `man 3 printf`가 멈춘다. (b) init의 `/usr/local` overlay를 끄면 결정 F-10의 `npm i -g`가 멈춘다.
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
5. `/usr/local` upper가 디스크에 남으므로, 체인의 부팅 4(갱신) 뒤에도 남는다. 갱신 판정이 upper를 안 지우는지(사용자 파일이다) 본다.
6. TP design 위험 1("`/usr`에 쓰는 TARS 코드")은 `/usr/local`에 대해서는 풀린다. 다른 체인은 묶음이 없고 p3가 있는 경우(home · pm · mise ·
   dualboot 등)에 `/usr/local` overlay가 새로 생긴다 — 루트 게이트가 그것을 본다.

## 확인한 것

1. cmake의 `bin/`에는 `cmake-gui`(Qt — `libxcb` · `libfontconfig` · `libfreetype`)가 있다. 링크하지 않고(`exe=` 넷) NEEDED는 GUI 예외 셋으로 둔다.
2. 거두기 첫 판이 둘로 멈췄다. `/etc/group`이 initrd와 달랐다 — openssh-client의 postinst가 `_ssh` 그룹을 더했다. 계정 파일 넷과 그 백업,
   그리고 sysvinit · cron · apparmor · logcheck의 자리를 싣지 않게 했다(TARS의 계정은 init이 만들고, 그 자리를 읽는 것이 없다).
   `usr/share/misc/magic -> ../file/magic`이 대상 없는 링크였다 — 목록이 파일 · 링크뿐이라 빈 디렉터리가 빠졌다. 디렉터리를 가리키는
   링크는 그 디렉터리도 싣는다.
3. gdb는 Debian의 `libpython3.13`과 표준 라이브러리 657개를 `/usr/lib/python3.13`에 끌고 왔다. `/usr/bin/python3`는 생기지 않았다(위험 2는
   안 일어났다). man 페이지는 3,669개.
4. chroot에서 `./configure`가 `expr: command not found`로 13분 돌다 segfault였다. initrd는 coreutils의 일부만 싣는다 — configure가 부르는
   `expr` · `od` · `paste` · `join` · `comm` · `nproc` · `md5sum` · `tac` · `fold` · `split` · `dd`와 외부 `test` · `true` · `false` · `printf`, 그리고
   `bzip2` · `hostname` · `bison` · `flex` · `msgfmt`가 없었다. base에 coreutils · bzip2 · hostname · m4 · bison · flex · gettext를 더했다
   (coreutils · hostname은 slim에 있어 의존 폐포 단계가 싣고, initrd와 같은 40개는 verify가 뺐다). grep은 판이 initrd(3.11-4+b1)와
   slim(3.11-4)이 달라 넣지 않았다 — `egrep` · `fgrep`은 `grep -E` · `-F`다. `perldoc`은 Debian이 `perl-doc`으로 나눈다 — 더했다.
   `man gcc`는 없다: Debian은 gcc의 man 페이지를 GFDL 때문에 non-free의 `gcc-doc`으로 뺀다. 체인은 `man 1 ssh`를 본다.
5. Rosetta 위 chroot에서는 gdb · strace · ltrace가 ptrace를 못 받는다(`PTRACE_TRACEME: Function not implemented`). 판정은 체인(진짜 커널)이 했다.
6. pip: site `pip.conf`의 `prefix=/usr/local`은 root 설치는 맞게 보내지만 사용자의 `pip install --user`가 `Can not combine '--user' and
   '--prefix'`로 막힌다. 그래서 Debian의 `posix_local`과 같은 일을 묶음 python의 `sitecustomize.py`가 한다 — venv가 아닐 때 `prefix` scheme만
   `/usr/local`로 바꾸고 그 site-packages를 `sys.path`에 넣는다. root · `--user` · 옵션 없는 사용자(`Defaulting to user installation`) · venv
   넷이 다 맞다. 대가는 python 시작마다 `sysconfig` import(Rosetta 18ms). python 3.15의 `sysconfig.get_paths()` 기본값은
   `get_preferred_scheme`을 안 거친다 — 판정은 깐 모듈의 자리로 한다.
7. gem: 시스템 gemrc는 `<ruby>/etc/gemrc`(load-relative)이고, bindir만 바꾸는 길은 RubyGems의 `rubygems/defaults/operating_system.rb`
   (`Gem.default_bindir`)다. gem 자체는 ruby의 기본 자리(묶음 안, `/usr/local` upper 덕에 root가 쓴다)에 놓인다 — ruby 판이 바뀌면 다시 깐다.
   npm: builtin `lib/node_modules/npm/npmrc`(원래 없다)에 `prefix=/usr/local`.
8. init의 `/etc` 복사(`copyTree`)가 링크를 건너뛰고 있었다(TP-M1부터) — php의 `conf.d/*.ini`는 `phpenmod`가 만든 링크라 TP-M3의 php는
   확장 열아홉(ctype · opcache · pdo 등)이 하나도 안 켜졌다. TP-M3 hello는 core의 `json_encode`만 써서 지나갔다. 링크를 같은 대상의 링크로
   두게 고쳤고, 체인의 php hello에 `ctype_digit`을, 부팅 2에 "`etc/`에서 건너뛴 것이 없다"를 더했다.
9. 체인의 함정 둘(그 체인 고유): (a) 기다리는 표시 글자가 명령 줄에 그대로 있으면 콘솔이 되비춘 명령에 `wait_log`가 맞아 출력 전에
   넘어간다 — `printf "tp-m4-%s\n" xxd-ok` 꼴과 실제 출력만 가질 글자(`=/[a-z]`)로 기다린다. (b) 판독: 출력 줄을 ANSI가 섞인 채로 걸러 "출력이
   없다"고 잘못 읽은 판이 있었다 — 로그는 바이트로 읽는다(`tp-m4-pk`가 실제로는 디렉터리 이름까지 찍고 있었다).
10. 빨강 (b): init의 `mountLocal`을 막으면 `FAIL: init did not make /usr/local writable`.
11. 빨강 (a): harvest의 man 제외 풀기를 막으면 base의 경로가 14,916에서 10,282로 준다(man 4,634개). 체인은 `FAIL: man 3 printf did not show
    the C library page (manpages-dev)`.

## 결과

1. `make dev-layers`가 초록. base: 패키지 153 · 경로 14,916(man 3,669) · 파일 20,658 · 풀린 크기 738MiB(251에서) · zstd15 238MiB(81에서) ·
   ELF 1,177 · 예외 3(cmake-gui의 GUI) · initrd와 같아 뺀 것 130. lang-native는 rc 조각 둘, lang-script는 설정 셋이 더해졌다(debconf가 빠졌다).
2. 체인 `devtools`(SandyBridge · 1GiB)가 초록, 빌드 뒤 377초(TP-M3 305초) — 420초 아래라 하나로 둔다. 묶음 넷 958MiB, `tars-dev.iso`
   1,148,049,408바이트, 설치기 복사 5.3초. TCG 숫자: cmake+ninja 2.5초, autotools 13.7초, perl 0.6초, gdb 3.6초, valgrind 4.4초, gpg 0.6초,
   root의 전역 설치 셋 24.3초. 상한은 그 세 배(60초 아래로는 안 내린다): 전역 설치 80초, 나머지 60초.
3. 빨강 둘(확인한 것 10 · 11).
4. 루트 게이트 한 판: 31/31, 32분 47초(lanes 1,193초 — base를 다시 거둔 4분 남짓 포함), 31회차 모두 `cut log lines A=0 B=0 C=0`. p3가 있는
   체인(home · pm · mise · dualboot 등)이 이제 `/usr/local` overlay를 걸고도 초록이다(위험 6).
5. 위험 1(valgrind · gdb의 TCG 속도)은 4초 안팎으로 작았다. 위험 2(Debian python)는 `/usr/bin/python3` 없이 라이브러리만. 위험 3: ISO가
   1.15GB가 됐다 — GitHub의 2GiB 한도까지 0.85GB가 남았다(`project_release_0_2.md`).
