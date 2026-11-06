# TP-M5 — JVM 언어(kotlin · clojure)와 util 묶음의 시작(cci · glc)

> 2026-11-06, `fde161a` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design "Milestone"의 순서대로 JVM 계열을 `lang-jvm` 묶음에 더한다. 판정은 design 결정 15 — 미리 넣은 jar로 망 없이 한 번 돈다.
같은 milestone에 사용자 요청(2026-11-06, 이 plan을 쓰는 중) 하나를 더한다: "add soomtong/tap/cci, soomtong/tap/glc I added linux build of them."
design의 "뺀 것"(cci · glc · tsl — 미리 빌드된 linux 바이너리가 없었다)에서 cci · glc를 되돌린다. tsl은 그대로 뺀다.

사용자 결정(2026-11-06, 착수 전 확인을 보고):
- scala3를 뺀다. "스칼라를 공부하는 건 좋지만 스칼라 컴파일 서버가 스칼라 2로 만들어졌다는 것도 마음에 안 들고, 여러모로 아직은 스칼라를
  나는 본격적으로 사용하는 게 아니어서" — 망 없이 `scala run`을 세우려면 Bloop까지 실어야 했다(확인 3). design 11판이 도구 목록 · 결정 15 ·
  결정 19(docset)에서 뺐다. 필요해지면 Homebrew로 깐다.
- cci · glc는 이 milestone에서 `util` 묶음을 열어 둔다(결정 E).

## 착수 전 확인 (2026-11-06)

amd64 trixie-slim 컨테이너(Rosetta)에 이 저장소의 `lang-jvm.sqfs`(Temurin 25.0.5+8)를 풀고, 망을 끊고(`--network none`) 돌렸다.

1. 판과 sha256(GitHub 자산의 `digest`, 받은 파일과 대조함):

   | 도구 | 판 | 받는 것 | 크기 | 풀린 크기 |
   |---|---|---|---|---|
   | kotlin | 2.4.21 | `kotlin-compiler-2.4.21.zip` | 89,733,618 | 93MiB |
   | clojure | 1.12.6.1673 | `clojure-tools-1.12.6.1673.tar.gz`(clojure/brew-install) | 12,327,673 | 13MiB |
   | cci | 0.6.1 | `cci_0.6.1_linux_amd64.tar.gz`(soomtong/claude-code-history-viewer) | 4,376,022 | 12MiB |
   | glc | 0.19.3 | `glc-0.19.3-linux-x86_64.tar.gz`(soomtong/gluck) | 11,413,695 | 59MiB |

2. kotlin: `kotlinc h.kt -include-runtime -d h.jar && java -jar h.jar`가 망 없이 된다(Rosetta 23초). zip은 jar와 셸 스크립트뿐이다.
   Kotlin/Native(`kotlin-native-prebuilt`, 220MB)는 첫 실행에 LLVM 툴체인을 따로 받는다 — 싣지 않는다.
3. scala3 3.10.0(뺀 근거 — 다시 넣을 때 여기서 시작한다): linux tarball(103MB, 풀면 199MiB)의 `bin/scala`는 scala-cli(GraalVM native,
   `NEEDED` libz · libc, `%ymm` · `%zmm` 0)를 동봉 `maven2/` 저장소(`-r`)와 함께 부른다.
   - `scalac` · `scala run --server=false` · `scala repl`은 망 없이 된다(각 27초).
   - 기본 `scala run`은 컴파일 서버 Bloop(`bloop-frontend_2.12` 2.1.2)을 Maven Central에서 받으려다 `Error getting Bloop class path`로 멈춘다.
     Bloop 받기는 `-r` 저장소를 보지 않는다(Bloop의 파일을 동봉 `maven2`에 합쳐도 같은 오류). `COURSIER_REPOSITORIES="file://…|central"`은
     다른 해석 경로로 `reactive-streams` pom에서 멈춘다.
   - 사용자 캐시 `~/.cache/coursier/v1/https/repo1.maven.org/maven2/`를 미리 채우면 망 없이 선다 — 첫 실행 44.6초, 두 번째 5.1초. 채울 것은
     jar 134 · pom 166, 111MiB(Bloop이 Scala 2.12로 쓰여 그 런타임 · Zinc · monix · BSP · 디버그 어댑터를 끌고 온다).
   - Bloop 서버의 상주 메모리(VmRSS) 585MiB, `-Xmx` 없이 ZGC.
   - 서버를 기본으로 끄는 전역 설정 키는 없다(`scala config`의 키에 server가 없다). 런처의 옵션 줄에 `--server=false`를 끼우면 그 뒤의 런처
     옵션을 못 읽어 모든 명령이 `Unrecognized argument: --cli-default-scala-version`으로 깨진다.
4. clojure: tarball은 설치 스크립트(`install.sh`)가 `clojure`의 `PREFIX` · `clj`의 `BINDIR`을 ruby로 바꿔 넣는 모양이다. 그대로 두면
   `cp: cannot stat 'PREFIX/example-deps.edn'`.
   - 바꿔 넣으면 첫 실행이 `org.clojure/clojure 1.12.6` · `spec.alpha 0.5.238` · `core.specs.alpha 0.4.74`(jar 셋 + 부모 pom `pom.contrib 1.2.0`까지
     pom 넷, 4.7MiB)를 `~/.m2/repository`로 받는다. 받는 자리는 Java의 `user.home`(`/etc/passwd`의 홈)이지 `$HOME`이 아니다.
   - root deps는 tools jar 안(`clojure/tools/deps/deps.edn`)에 있고, 설치 디렉터리의 `deps.edn`이 그 위에 합쳐진다.
   - 설치 디렉터리 `deps.edn`에 `file://` 저장소를 앞세워도, 셋을 `:local/root` jar로 적어도 망 없이 안 된다 — tools.deps는 `central`부터 찾고
     망 오류(이름 풀기 실패)를 "없음"이 아니라 실패로 다룬다.
   - `~/.m2/repository`에 그 일곱 파일을 미리 채우면 `clojure -M -e` · `clojure -M -m hello.core`가 망 없이 된다(11 · 14초).
   - `clojure -X:deps tree`는 `tools.deps.cli`(Maven 해석기 묶음)를 따로 받는다 — 의존 해석 도구라 망과 짝이다. 비목표.
   - `clj`는 `rlwrap`이 없으면 `Please install rlwrap …`을 찍고 멈춘다. trixie의 `rlwrap` 0.46.1-1+b1은 perl · python3(필터 스크립트)에 기댄다.
5. cci: Go 1.26.10, `CGO_ENABLED=0`, `GOAMD64=v1`, 정적. glc: Rust 1.99.1(Ubuntu 22.04의 GCC 11), `NEEDED` libstdc++ · libz · libgcc_s ·
   libm · libc, GLIBC 2.34까지, ELF에 ISA 요구 note 없음. 둘 다 `%ymm`이 있지만 Go 런타임 · Rust의 CPUID 분기 경로로 본다 — x86-64 v1
   빌드다. 실기(에어 2011, SandyBridge)에서 한 번 띄우는 것은 사용자 확인으로 남긴다(TCG는 AVX2를 못 잡는다, measurements 103).
6. 체인 시간: TP-M4 끝 377초. kotlin · clojure의 hello는 Rosetta에서 하나에 11~23초다. TCG에서는 몇 배가 된다(javac가 TCG 11초).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. kotlin은 `upstream` 한 줄. 풀린 `kotlinc/`를 `/usr/local/lib/kotlinc-2.4.21`에 두고 `exe=`로 `kotlinc` · `kotlin` · `kotlinc-jvm` ·
   `kapt`를 링크한다. `kotlinc-js` · `kotlinc-wasm`은 싣되 링크하지 않는다(JVM 묶음의 몫이 아니다). Kotlin/Native는 싣지 않는다(확인 2).
B. 새 종류 `maven`. 매니페스트 한 줄의 URL 자리는 잠금 파일(`devlayer/maven/<이름>.lock`)이고, sha256 자리는 그 잠금 파일의 sha256이다.
   잠금 파일은 한 줄에 `<maven2 아래 경로> <sha256>`이다. build.sh는 줄마다 `https://repo1.maven.org/maven2/<경로>`를 받아 sha256을 대조하고
   `devlayer/cache/<sha256>`에 둔다(upstream과 같은 캐시). `into=`가 가리키는 도구 디렉터리 아래 `seed/m2/`에 Maven 로컬 저장소 모양으로 놓는다.
   - Central은 sha1만 낸다. 잠금 파일은 처음 받을 때 Central의 `.sha1`과 대조한 뒤 sha256을 적는다 — upstream의 GitHub `digest`와 같은 자리
     (처음 받을 때 배포처가 낸 값으로 확인하고 고정한다). 일곱 줄이라 손으로 만들고, 만든 방법을 잠금 파일 머리 주석에 적는다.
   - 종류의 순서(design 결정 1): Maven Central은 그 프로젝트가 직접 내는 배포처라 `upstream`과 같은 줄에 선다. 다른 종류로 둔 이유는 받는
     모양(파일 하나가 아니라 여럿)뿐이다. 구현이 서면 design 결정 1에 한 줄 더한다.
   - 매니페스트의 선택 키는 그대로 넷이다.
C. clojure는 `upstream` 한 줄과 `maven` 한 줄(`clojure-m2`, `into=clojure`). 풀기는 새 훅 `devlayer/hooks/clojure-tools.sh`:
   `install.sh`가 하는 일(`deps.edn` · `example-deps.edn` · `tools.edn`을 뿌리에, jar를 `libexec/`, `PREFIX` · `BINDIR`을 `sed`로, man 둘을
   `share/man/man1`)을 `/usr/local/lib/clojure-1.12.6.1673`에 한다. `exe=bin/clojure bin/clj`.
   man은 `/usr/local/share/man/man1`에 링크해 `man clojure`가 서게 한다(man-db가 그 자리를 보는지 구현 때 확인).
   - `rlwrap`은 `debian` 줄로 lang-jvm에 싣는다. 의존의 python3는 `harvest-skip.tsv`에 더해 뺀다(lang-script의 python과 이름을 다투지 않게,
     TP-M4 위험 2와 같은 결). perl은 base와 같은 판이라 묶음 사이 대조가 `shared`로 센다. python3가 빠져 `rlwrap -z`(필터)는 안 된다 —
     `clj`는 필터를 안 쓴다.
D. 첫 실행 시드. 훅이 `bin/clojure`의 맨 앞(셸 코드)에 몇 줄을 넣는다 — `${HOME}/.m2/repository/org/clojure/clojure/1.12.6/clojure-1.12.6.jar`가
   없으면 `seed/m2/.`를 `${HOME}/.m2/repository/`로 `cp -rn`(이미 있는 파일은 건드리지 않는다).
   - 환경 변수나 시스템 rc가 아니라 런처에 두는 이유: clojure를 쓰는 사람만, 쓰는 순간에만 복사가 일어난다. `sudo`로 불러도 root의 홈에 같은
     일이 일어난다.
   - 사용자가 캐시를 지우면 다음 실행에 다시 채운다. 캐시 자리를 `:mvn/local-repo` 등으로 바꾼 사용자에게는 시드가 안 닿는다 — 그 사람은 망이
     있을 때 한 번 받는다. 비목표 3.
   - `$HOME`과 Java의 `user.home`이 다른 경우(확인 4)는 TARS에서 생기지 않는다 — 계정의 홈이 `$HOME`이다. 체인이 사용자로 그것을 본다.
E. `util` 묶음을 연다(사용자 결정). cci · glc 두 줄(`upstream`). cci는 `strip=1 exe=cci`, glc는 `strip=0 exe=glc`. 묶음은
   `DEV_LAYERS` · 체인의 `LAYERS` · `ISO_LAYERS`에서 지금 순서(`base lang-jvm lang-native lang-script`)의 맨 뒤에 선다. 나머지 util 도구는 util
   milestone(편집기 · 터미널 유틸리티 · 문서)의 몫이다. tap의 Homebrew formula는 아직 macOS만 적는다 — 출처는 각 저장소의 GitHub release다.
F. 체인: devtools 부팅 2에 더한다(망 없이, 사용자로).
   1. kotlin: `kotlinc h.kt -include-runtime -d h.jar && java -jar h.jar`
   2. clojure: `clojure -M -e`(spec 요구 포함, 시드가 `~/.m2`에 채워졌는지도), `clj`가 `rlwrap` 안내 없이 REPL을 연다(입력 한 줄 `(+ 40 2)`)
   3. cci `--version` · glc `--help`
   4. `man clojure`
   시간 상한은 처음에는 하나에 300초, 잰 뒤 세 배(60초 아래로는 안 내린다). 체인이 420초를 넘으면(TP-M3 결정 F) JVM 둘의 hello를 새 체인
   (monitor 45505)으로 뗀다.

## 할 일

1. 매니페스트: lang-jvm에 kotlin · clojure · clojure-m2(`maven`) · rlwrap(`debian`), util에 cci · glc. `harvest-skip.tsv`에 python3(rlwrap 몫).
2. `devlayer/manifest.sh` · `build.sh`: 종류 `maven`(결정 B)과 잠금 파일 `devlayer/maven/clojure-m2.lock`(Central `.sha1` 대조 뒤).
3. 훅 `clojure-tools.sh`(결정 C · D). 훅의 해시는 stamp에 이미 든다(`devlayer/hooks/*.sh`).
4. `util` 묶음을 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `LAYERS` · lowerdir 판정 · `overlay /usr from N layers`
   판정, 그 밖에 묶음 이름 목록을 따로 든 곳을 `rg -n 'lang-script'`로 한 번 더 본다.
5. `make dev-layers` — 숫자: lang-jvm · util의 풀린 크기 · zstd 크기 · 받기 시간, NEEDED 예외(glc가 initrd의 libstdc++로 풀리는지).
6. chroot로 결정 F의 hello를 먼저 돌린다(`/dev/null` mknod — TP-M4 요령).
7. 빨강: 훅의 시드 줄을 빼면 결정 F-2의 `clojure -M -e`가 망 오류로 멈춘다.
8. 체인 혼자 한 번, 숫자로 상한을 고친다. 420초를 넘으면 가른다.
9. `make quick`, 루트 게이트. design(결정 1의 `maven`, Milestone), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, lang-jvm · util의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 결정 F의 네 덩이가 망 없이 사용자로 돈다(design 결정 15의 판정). 할 일 7의 빨강을 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. Kotlin/Native(첫 실행에 툴체인을 받는다). scala3(사용자 결정, 확인 3).
2. 빌드 도구(gradle · maven · leiningen)와 그 의존 캐시. design 비목표 2(생태계 미러)의 범위다.
3. 캐시 자리를 바꾼 사용자에게 시드를 닿게 하기(결정 D).
4. `clojure -X:deps …`(확인 4).

## 위험

1. TCG에서 JVM 둘이 느리다. 하나에 수십 초 이상이면 체인이 420초를 넘는다 — 새 체인으로 뗀다(결정 F).
2. lang-jvm이 는다(126 → 어림 풀면 240MiB, kotlin의 jar는 이미 압축돼 있어 거의 안 준다). util은 70MiB 안팎. ISO는 1.15GB에서 1.3GB 안팎이
   된다. GitHub release의 파일당 2GiB 한도는 아직 남는다(`project_release_0_2.md`의 사용자 결정 대기).
3. 시드는 clojure의 판에 묶인다(root deps의 `org.clojure/clojure` 판). clojure를 올리면 잠금 파일도 다시 만든다 — 어긋나면 시드가 있어도 망을
   찾는다. 체인이 그것을 본다(결정 F-2가 망 없이 돈다).
4. glc의 CPU 수준(확인 5)은 체인으로 못 잡는다 — 실기 확인 목록에 넣는다.

## 확인한 것

(구현 중 채운다)

## 결과

(구현 뒤 채운다)
