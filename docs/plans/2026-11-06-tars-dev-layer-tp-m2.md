# TP-M2 — `lang-native` 묶음(zig · rust · go)과 base의 g++

> 2026-11-06, `6185d85` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP design 도구 목록의 "네이티브 언어" 줄을 개발 도구 층에 싣는다. 판정은 design "TP-M2 이후"대로 각 언어의 hello가
devtools 체인에서 망 없이(`-nic none`) 사용자로 도는 것이다. 미뤄 둔 매니페스트 파서의 엄격화(HANDOFF "남은 작업" 첫 줄)를 함께 한다.

사용자 결정(2026-11-06): LLVM 툴체인(LLVM · clang · lld)과 odin을 뺀다. "어차피 GCC가 포함되니까 C나 Assembly 계열의 코드 작성은
문제가 없을 거고, 디버거가 필요한 경우에는 직접 LLVM 툴체인을 설치하도록 합시다." 이어서 tcc도 쓰지 않기로 했다(사용자, 같은 날 —
출처는 확인 7).

## 착수 전 확인 (2026-11-05 ~ 06, 호스트에서 받아서 · 개발 컨테이너의 `readelf`로)

1. 판(각 배포처의 기계용 목록):

   | 도구 | 판 | 받는 것 | 받는 크기 | 풀린 크기 | sha256 출처 |
   |---|---|---|---|---|---|
   | zig | 0.17.1 | `zig-x86_64-linux-0.17.1.tar.xz` | 57,411,036 | 415MiB | `ziglang.org/download/index.json` |
   | rust | 1.99.1 | `rust-1.99.1-x86_64-unknown-linux-gnu.tar.xz`(standalone 설치기) | 210,515,736 | 1,898MiB | `channel-rust-stable.toml`의 `xz_hash` |
   | rust-src | 1.99.1 | `rust-src-1.99.1.tar.xz` | 5,863,216 | — | 같은 toml |
   | go | 1.27.3 | `go1.27.3.linux-amd64.tar.gz` | 70,588,678 | 276MiB | `go.dev/dl/?mode=json` |

   받은 바이트의 sha256이 셋 다 배포처의 값과 같다. rust toml의 `hash`는 `.tar.gz`의 것이고 `.tar.xz`는 `xz_hash`다(처음에 엇갈려 보였다).
2. tarball 모양(맨 위 디렉터리는 셋 다 하나다):
   - go: `go/bin/{go,gofmt}`. 지금의 `build.sh`(맨 위를 벗기고 `bin/*`을 링크) 그대로 된다.
   - zig: `zig-x86_64-linux-0.17.1/zig`와 `lib/` · `doc/langref.html`. 실행 파일이 맨 위에 있고 `bin/`이 없다.
   - rust: 설치기다 — `install.sh`와 컴포넌트 디렉터리 열하나(`rustc` 405MiB · `rust-docs` 902 · `llvm-tools-preview` 221 · `rust-std` 160 ·
     `rust-docs-json-preview` 111 · `rust-analyzer-preview` 41 · `cargo` 36 · 그 밖에 넷). 풀기만 해서는 `bin/`이 서지 않는다. rust-src는
     따로 받는 tarball이고(rust-analyzer가 표준 라이브러리 소스로 쓴다), 같은 설치기 형식이다.
3. zig · go의 실행 파일은 `statically linked`다. rustc는 `librustc_driver-*.so` → `libLLVM.so.23.1-rust-1.99.1-stable`(자기 `lib/`)이고,
   cargo는 libc 계열만 끈다. rust는 자기 LLVM과 `rust-lld`를 품고 있어 LLVM 툴체인 없이 선다.
4. 뺀 LLVM에 대해 잰 것(사용자 결정의 근거로 남긴다): 공식 `LLVM-23.1.5-Linux-X64.tar.zst` 1.2GB, 풀면 11,853MiB. `bin/` 179개가 LLVM을
   각자 정적으로 품는다. 남길 것만 추리면 약 1.1GiB였다. `.tar.zst`는 창이 1GiB라 `zstd -d --long=31`이 필요하다. lldb는
   `libpython3.14.so.1.0`을 끈다. apt.llvm.org의 trixie 23은 매일 빌드 한 판만 내놓아 `=` 고정이 안 된다. odin은 링크에 `clang`을 부른다 —
   LLVM을 빼면 odin도 함께 빠진다.
5. Debian trixie의 g++는 `g++ 4:14.2.0-1`, `g++-14 14.2.0-19`, `libstdc++-14-dev 14.2.0-19`다. base의 gcc-14와 같은 판이다.
6. go의 `go.env`는 `GOPROXY=https://proxy.golang.org,direct` · `GOTOOLCHAIN=auto`다. auto가 새 툴체인을 받는 자리는
   `~/go/pkg/mod`(홈)이고 `/usr`가 아니다. 그래서 design 결정 14(읽기 전용 `/usr`의 자동 갱신)에 걸리지 않는다.
7. 뺀 tcc에 대해 본 것: upstream(savannah)의 마지막 릴리스는 0.9.27(2017)이고, 소스와 Windows 바이너리만 있다. GitHub 미러(TinyCC/tinycc)의 릴리스는 0개다.
   `vendor-repo` · `prebuilt`도 없어 `debian`이다. trixie의 판은 `0.9.27+git20200814.62c30a4a-2`(2020년 스냅숏)이고, 설치하면 827KiB, 의존은 `libc6 (>= 2.38)`이다.
8. 매니페스트 파서는 둘이다. `build.sh`와 `harvest.sh`의 awk는 `NF >= 6`이 아닌 줄을 말없이 건너뛴다. `Makefile`은 매니페스트를 안 읽는다(`DEV_LAYERS`).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. g++는 base에 둔다. 매니페스트에 `debian` 한 줄을 더한다(`g++ 4:14.2.0-1`). lang-native에서
   거두면 trixie-slim 기준의 "새로 생긴 파일"에 gcc-14 · binutils · libc6-dev가 한 벌 더 들어간다(TP-M0 결정 K가 미룬 겹침). base는
   "C · C++ · 어셈블리의 바닥"이 되고, lang-native는 `debian` 줄이 없는 묶음이 된다. base는 줄이 바뀌어 다시 거둬진다.
B. lang-native의 세 도구는 모두 `upstream`이다. 각 도구는 `/usr/local/lib/<도구>-<판>/`에 놓이고, 실행 파일 링크는 `/usr/local/bin/`이다
   (design 결정 2). rust는 링크에 base의 `cc`를 부르고, go의 cgo도 base의 gcc를 쓴다. 이렇게 묶음끼리 기대는 것은 base가 늘 실린다는
   전제 위에 있다(design 결정 6의 릴리스 ISO).
C. 매니페스트는 일곱째 열을 선택으로 받는다. 값은 공백으로 가른 `키=값`이고, 값 안에는 공백을 두지 않는다. 키는 셋이다.
   - `exe=a,b` — 링크할 실행 파일. 도구 디렉터리 기준 경로이고, 없으면 지금처럼 `bin/`의 실행 파일 전부다. zig가 `exe=zig`다.
   - `hook=<이름>` — 받기 · sha256까지만 `build.sh`가 하고, 풀기는 `devlayer/hooks/<이름>.sh <tarball> <뿌리> <도구 디렉터리>`가 한다.
     rust 두 줄이 `hook=rust-installer`다. 훅은 `install.sh --prefix=/<도구 디렉터리> --destdir=<뿌리> --disable-ldconfig
     --components=<허용 목록>`을 돌린다. 허용 목록은 훅 안에 둔다: `rustc` · `cargo` · `rust-std-x86_64-unknown-linux-gnu` ·
     `rustfmt-preview` · `clippy-preview` · `rust-analyzer-preview` · `rust-docs` · `rust-src`. `rust-docs`는 design 결정 19의 오프라인
     문서이고 w3m으로 읽는다. 빼는 것은 `llvm-tools-preview` · `rust-docs-json-preview` · `rust-analysis` · `llvm-bitcode-linker`다.
     설치기는 셸 스크립트라서 arm64 개발 컨테이너에서도 돈다(파일을 복사할 뿐이다).
   - `into=<도구>` — 도구 디렉터리를 다른 줄의 것으로 한다. rust-src가 `into=rust`로 `usr/local/lib/rust-1.99.1/`에 들어간다.
   design 결정 1의 가칭 "묶음별 훅"(`hooks/<묶음>.sh`)은 형식별 훅이 되었다. 절차가 묶음이 아니라 배포 형식(rust 설치기)을 따르기
   때문이다. 키가 다섯을 넘거나 값에 공백이 필요해지면 TSV를 다른 형식으로 옮긴다(HANDOFF의 미룬 것에 적힌 신호).
D. 파서는 `devlayer/manifest.sh` 하나다. `build.sh` · `harvest.sh`가 source한다(거두기 컨테이너에도 bash와 mawk가 있다). 이 파일은 부를 때마다
   매니페스트 전체를 읽는다. 주석 · 빈 줄이 아닌데 열이 6 · 7이 아니면 `manifest.tsv:<줄>: expected 6 or 7 tab-separated columns, got N`, 종류가 넷 밖이면
   `…: unknown kind X`, 일곱째 열에 모르는 키나 `=` 없는 말이 있으면 `…: unknown option X`, 같은 도구 이름이 두 번이면 `…: tool X again`을
   찍고 실패한다. 탭이 공백으로 바뀐 줄은 열이 하나라서 첫째 규칙에 걸린다.
E. 묶음끼리의 겹침 검사. 지금의 결정 4 검사(TP-M0 결정 G)는 묶음을 initrd와만 대조한다. 묶음이 셋이 되면 두 묶음이 같은 경로에 다른 내용을 둘
   수 있다. overlay는 lowerdir 앞의 것(이름 순)을 보이고 경고하지 않는다. 그래서 `build.sh`가 굽고 나서
   `devlayer/build/<묶음>.paths`(경로 · 파일은 sha256 · 링크는 대상, 정렬)를 쓰고, 매니페스트에 있는 다른 묶음의 `.paths`와 대조한다.
   같은 내용이면 개수만 센다(`shared=N`). 다르면 두 묶음 이름과 경로를 찍고 실패한다. 먼저 구운 쪽은 나중 쪽이 대조하므로 한 방향이면 덮인다.
   지금 셋 사이의 예상은 0이다. lang-native는 `/usr/local/lib/<도구>-<판>`과 `/usr/local/bin`의 이름만 쓰고, base는 `/usr/bin` · `/usr/lib`이다.
F. 게이트에서 다시 푸는 비용. `build.sh`는 캐시여도 매번 뿌리를 다시 만들고 verify를 돈다(TP-M0의 설계 — initrd가 바뀌면 겹침이 달라진다).
   lang-native에서는 rust 1.9GB를 풀어 설치기가 복사하는 데와 zig · go 0.7GB, ELF의 `readelf`가 매 게이트에 붙는다. 할 일 3에서 그
   시간을 잰다. 60초를 넘으면 빠른 길을 넣는다. 빠른 길의 열쇠는 지금의 stamp에 "initrd 쪽 입력"을 더한 것이다. initrd 쪽 입력은
   (1) 묶음의 `.paths`에 든 경로마다 initrd의 내용과 (2) initrd 라이브러리 디렉터리 넷의 파일 이름 목록이다. 결정 4는 (1)만, 결정 5는
   (2)만 보기 때문에 이 둘이 같으면 결과도 같다. 열쇠가 같으면 뿌리 만들기 · verify를 건너뛰고 `cached-verified`를 찍는다. 60초 아래면
   넣지 않는다 — 검사가 하나 적은 쪽이 낫다.
G. 체인은 새로 만들지 않고 `devtools`를 넓힌다(design 판정 "devtools 체인에서"). monitor 포트는 그대로 45504다.
   - ISO: `ISO_LAYERS="base lang-jvm lang-native"`. init은 이름 순으로 얹으므로 lowerdir은 `/usr:…/base/usr:…/lang-jvm/usr:…/lang-native/usr`다.
   - 부팅 1: `layers  base lang-jvm lang-native (N MiB)`, 복사 줄 셋, `copied 3 layers`. 부팅 2: `overlay /usr from 3 layers`. 부팅 3:
     lang-jvm이 깨지고 `from 2 layers`(gcc와 go는 돌고 java는 없다). 부팅 4: `3 old layers removed`.
   - 부팅 2에 사용자로, 망 없이, 하나씩 시간을 재며 넣는다(소스는 지금처럼 `printf` 한 겹으로 짓는다 — 게스트에 `base64`가 없다):
     1. `g++ -O2 h.cpp`(`<iostream>` · `std::vector`) 실행
     2. `zig build-exe h.zig` 실행 — 출력에 `builtin.zig_version_string`
     3. `rustc h.rs` 실행, `cargo new --vcs none tpr && cargo build --offline` 뒤 `target/debug/tpr` 실행
     4. `go run h.go`(모듈 없이 파일 하나)와 `go mod init tp && go build`(모듈 하나) 실행 — `runtime.Version()`
   - 시간 상한은 처음 잰 숫자의 세 배다(TP-M1의 규칙). 처음 재기 전에는 하나에 600초로 둔다.
H. design을 고칠 자리: 도구 목록 표의 "네이티브 언어"를 "gcc · g++(base 묶음), zig, rust, go"로, "뺀 것"에 LLVM 툴체인 · odin · tcc(사용자 결정
   2026-11-06, 디버거가 필요하면 사용자가 직접 LLVM 툴체인을 깐다 — Homebrew의 `llvm` 등), 확인 10의 LLVM 어림을 확인 4의 숫자로,
   결정 1에 일곱째 열 · 훅 한 줄. Status 줄은 "TP-M2 끝"이다.

## 할 일

1. 매니페스트(결정 A · B · C): base에 g++ 한 줄, lang-native 네 줄(zig · rust · rust-src · go). `Makefile`의
   `DEV_LAYERS ?= base lang-jvm lang-native`, `help` 줄.
2. `devlayer/manifest.sh`(결정 D)를 만들고 `build.sh` · `harvest.sh`가 쓰게 한다. `build.sh`: 일곱째 열(`exe` · `hook` · `into`), 묶음 사이
   대조(E). `devlayer/hooks/rust-installer.sh`.
3. `make dev-layers` — base 다시 거두기(g++), lang-native 받기 · 굽기. 숫자: 도구별 풀린 크기, 묶음 크기(zstd15), 받기 · 굽기 시간,
   두 번째 실행(캐시)의 시간을 묶음별로 잰다. 결정 F의 60초를 이 숫자로 판단한다.
4. 손으로 한 번, 버리는 amd64 컨테이너에서 풀린 initrd 위에 세 묶음을 덮고 `chroot`한다(TP-M0 결과 4의 모양). 결정 G의 hello 넷을
   체인보다 먼저 거기서 돌려 본다. 거기서 안 되는 것은 체인에서도 안 된다 — 고칠 자리를 부팅 없이 찾는다.
5. 빨강 셋, 되돌리면 초록(`cmp`):
   (a) 매니페스트의 go 줄 탭 하나를 공백으로 바꾸면 `manifest.tsv:<줄>: expected 6 or 7 …`으로 멈춘다(지금은 go가 말없이 빠지고 초록이다).
   (b) go 줄의 일곱째 열에 `bin=go/bin`(모르는 키)을 두면 `…: unknown option bin=go/bin`으로 멈춘다.
   (c) lang-native 뿌리에 base의 `usr/bin/make`를 다른 내용으로 넣으면(훅의 실험용 한 줄) `build.sh lang-native`가 두 묶음 이름을 대고
       멈춘다(결정 E).
6. 체인 `devtools`(결정 G)를 혼자 한 번 돌리고, 숫자를 본 뒤 시간 상한을 고친다. 빨강 하나: `exe=zig`를 지우면 부팅 2가 zig hello에서 멈춘다.
7. `make quick`, 컨테이너의 `zig build test`(init · 설치기 코드는 안 바꿀 것으로 본다 — 바뀌면 그때 넣는다).
8. 루트 게이트(31체인). 어림: 지난 20분 14초에 devtools의 증가분(복사 +0.6GB · hello 넷의 TCG 시간 · build.sh의 다시 풀기)으로 23~26분.
   `time make gate`의 출력은 scratchpad에 둔다.
9. design 고치기(결정 H), HANDOFF.

## 판정

- `make dev-layers`가 세 묶음을 굽고 검사(겹침 · NEEDED · 묶음 사이)가 초록이다. 할 일 5의 빨강 셋과 할 일 6의 빨강 하나를 봤다.
- 체인 `devtools`의 부팅 2에서 hello 넷(g++ · zig · rust/cargo · go)이 망 없이 사용자로 돈다.
- 루트 게이트 31/31, 잘린 줄 0.
- 숫자: lang-native의 풀린 크기와 sqfs 크기(도구별 풀린 크기 포함), base의 증가분(g++), `tars-dev.iso` 크기, 설치기 복사 시간, hello마다
  TCG 시간, `build.sh`의 캐시 실행 시간.

## 위험

1. TCG에서 첫 빌드가 느리다. go는 첫 `go build`에서 표준 라이브러리를 `~/.cache/go-build`로 컴파일하고, zig는 첫 빌드에서 compiler_rt와
   std를 짓는다. 둘 다 qemu64 · 1GiB에서 수십 초에서 분 단위일 수 있다. 상한(결정 G)과 게이트 시간 어림이 이 숫자에 달려 있다.
   1GiB에서 rustc가 메모리를 넘으면 `TP_MEM`을 올리지 않고 그 사실을 적는다(맥북 에어 2011은 2~4GB다).
2. rust 1.90부터 x86_64 리눅스의 기본 링크는 `cc -fuse-ld=lld`(rustc 몫의 `rust-lld`, `gcc-ld/` 감싸개)다. base의 gcc 14가 그 `-B` 길을
   받는지는 할 일 4가 처음 본다(gcc는 9부터 `-fuse-ld=lld`를 `-B` 경로에서 찾는다). 안 되면 사용자에게 옵션을 치게 할 수 없다 —
   cargo 설정은 홈에 있고 묶음이 그 자리를 못 쓴다. 그때 다시 정한다.
3. `tars-dev.iso`가 약 0.9~1.1GB로 커진다. 체인의 부팅 1 · 4(CD에서 복사)와 `make_iso.sh`가 그만큼 길다. 호스트 디스크(HANDOFF의 ENOSPC)는
   `devlayer/cache`에 0.35GB, `devlayer/build`에 lang-native sqfs가 더해진다.

## 확인한 것

(구현 뒤 채운다)

## 결과

(구현 뒤 채운다)
