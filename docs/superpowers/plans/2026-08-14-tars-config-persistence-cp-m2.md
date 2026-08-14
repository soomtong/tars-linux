# TARS Config Persistence CP-M2 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 설정 파일의 값이 **실제 동작을 바꾼다.** 게스트 안에서
`echo shell=zsh > /config/tars.conf`를 타이핑하고 재부팅하면, 다음 부팅의 셸이
fish가 아니라 zsh다. 2026-08-11의 원래 요청(`project_boot_shell_selection`)이
여기서 완성된다.

**Design doc:** `docs/superpowers/specs/2026-08-14-tars-config-persistence-design.md`
(승인 완료 — 설계를 다시 열지 않는다)

**Tech Stack:** Zig 0.16.0, Debian trixie amd64 sysroot, bash, QEMU(monitor
`sendkey`), Docker(`tars-devcontainer`, arm64)

---

## design doc보다 넓힌 것 하나 (2026-08-14 사용자 승인)

design doc과 CP-M1의 인수인계 문서는 CP-M2를 "`Kind.path()`가 상수 대신
`cfg.shell`을 본다"로 적었다. 그런데 지금 TARS에는 셸이 **두 개** 뜬다.

| 셸 | 누가 띄우나 | 어디에 보이나 |
|---|---|---|
| 콘솔 셸 | `init`이 직접 fork (`Kind.path()`) | 시리얼(`/dev/console`) — 디버그용 |
| 터미널 셸 | `/terminal`이 PTY로 fork (`pty.spawn`) | DRM 화면 — **사용자가 실제로 보는 것** |

`Kind.path()`만 고치면 **시리얼 콘솔의 셸만** 바뀌고 화면의 셸은 fish 상수로
남는다. 사용자가 "부팅 셸을 고른다"고 할 때 보는 것은 후자이므로, 이번에 둘 다
바꾼다. 설계 결정을 바꾸는 것이 아니라 **같은 결정을 한 곳 더 적용하는 것**이라
design doc은 다시 열지 않는다.

전달 방법은 아래 "설계 결정 2"에 있다.

---

## 이번에 정해야 했던 설계 결정 둘

CP-M1이 남긴 숙제는 "`cfg`가 `main`의 지역 변수인데 `spawn`까지 어떻게
내려보낼 것인가"였다.

### 1. 전역 변수도, 인자 릴레이도 아니라 `Child`에 싣는다

세 가지가 가능했다.

| 안 | 내용 | 판단 |
|---|---|---|
| A. 모듈 전역 `var cfg` | 아무 데서나 읽는다 | 탈락 — 누가 언제 바꿀 수 있는지가 타입에 안 드러난다 |
| B. `supervise`→`start`→`spawn`으로 인자 전달 | 감독 루프가 설정을 들고 다닌다 | 탈락 — 감독은 설정과 무관한 일인데 시그니처가 오염된다 |
| **C. `Child`가 실행할 것을 들고 있는다** | `main`에서 한 번 정해 넣는다 | **채택** |

C를 고르는 진짜 이유는 코드 길이가 아니라 **"설정은 부팅 시점에 한 번만
읽는다"는 정책을 타입으로 표현하기 때문**이다. 감독 루프는 설정을 아예 모른다 —
자식이 죽어서 재시작할 때도 `Child`에 적힌 그것을 다시 띄운다. 그래서 "재시작할
때 설정을 다시 읽어야 하나?"라는 질문이 성립하지 않는다. 설정 변경은 재부팅으로
반영한다는 design doc의 결정이 코드 구조에 박힌다.

### 2. 터미널 셸은 `init`이 argv로 넘긴다

`terminal`이 `/config/tars.conf`를 직접 읽게 하면 파서가 두 벌이 되고, 두
프로세스가 서로 다른 시점에 같은 파일을 읽어 **다른 답을 얻을 수 있다.** 설정을
읽는 것은 PID 1의 일로 두고, `init`이 `/terminal`을 exec할 때 결정을 실어
보낸다.

```
execve("/terminal", ["/terminal", "/usr/bin/zsh", "-f"], envp)
                                   └── argv[1] 셸 경로   └── argv[2] no-config 플래그
```

`terminal`은 그 둘을 `pty.spawn`에 그대로 넘기기만 한다 — **셸이 무엇인지 알
필요가 없다.** 덕분에 "이름 → 경로 → 플래그" 매핑이 `init/src/config.zig` 한
곳에만 있다.

플래그가 필요한 이유는 셋의 철자가 전부 다르기 때문이다:
fish `--no-config`, bash `--norc`, zsh `-f`. initrd에는 `~/.bashrc`도
`~/.zshrc`도 없어서 지금은 있으나 없으나 동작이 같지만, **프롬프트가 예측
가능해야 게이트가 화면을 검사할 수 있다**(TF-M3이 fish에 `--no-config`를 준
이유가 그것이다).

---

## 왜 이 순서인가

```
Dockerfile        bash/zsh/zsh-common/libtinfo6/libcap2 → amd64 sysroot   ← Task 1 (네트워크)
  ↓
make_initrd.sh    바이너리 둘 + zsh 모듈 트리 + /usr/share/zsh            ← Task 2
  ↓
config.zig        Shell.path() / Shell.noConfigFlag()                      ← Task 3
main.zig          Child가 argv를 들고, 로그에 경로를 찍는다
  ↓
terminal/main.zig argv[1..2]를 pty.spawn으로                               ← Task 4
  ↓
config/check.sh   monitor + sendkey로 게스트에서 편집 → 2차 부팅 검사      ← Task 5
  ↓
check.sh 라벨 + BF/TF 회귀 + 전체 게이트                                    ← Task 6
```

**바이너리가 코드보다 먼저인 이유**는 CP-M1 plan이 이미 적어뒀다 — 설정에
`shell=zsh`를 써도 지금은 아무 일이 안 일어나 안전하지만, **경로를 잇는 순간
그 자리에 실제 파일이 있어야 한다.** 순서를 뒤집으면 "설정은 맞는데 셸이 안
뜨는" 상태를 디버깅하게 되고, 그때 원인이 파싱인지 배선인지 패키징인지 구분이
안 된다.

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

이번 milestone은 **Task 1에서 딱 한 번 네트워크가 필요하다**(이미지 재빌드).
그 뒤의 게이트 실행은 여전히 전부 오프라인이다.

---

## Task 1: 게스트용 셸 패키지를 sysroot에 굽는다

**Files:**
- Modify: `devcontainer/Dockerfile` (아래쪽 `apt-get download` 목록)

위쪽 `apt-get install`이 **아니다.** 그것은 컨테이너(arm64)가 실행할 도구이고,
우리가 넣으려는 것은 **게스트(x86_64)가 실행할 것**이다
(`project_build_host_arch`의 규칙 3).

- [ ] **Step 1: `apt-get download` 목록에 다섯 줄 추가**

`devcontainer/Dockerfile:48-56`. 바꾸기 전:

```dockerfile
    && (cd /tmp/debs && apt-get download \
        fish:amd64 \
        fish-common \
        coreutils:amd64 \
        libc6:amd64 \
        libgcc-s1:amd64 \
        libpcre2-8-0:amd64 \
        libpcre2-32-0:amd64 \
        libselinux1:amd64) \
```

바꾼 뒤:

```dockerfile
    && (cd /tmp/debs && apt-get download \
        fish:amd64 \
        fish-common \
        bash:amd64 \
        zsh:amd64 \
        zsh-common \
        libtinfo6:amd64 \
        libcap2:amd64 \
        coreutils:amd64 \
        libc6:amd64 \
        libgcc-s1:amd64 \
        libpcre2-8-0:amd64 \
        libpcre2-32-0:amd64 \
        libselinux1:amd64) \
```

그리고 그 위 주석 블록(`devcontainer/Dockerfile:38-42`)의 끝에 문단 하나를
덧붙인다 — 이 목록이 왜 이 모양인지가 이 저장소에서 계속 되묻게 되는 지점이다.

```dockerfile
# CP-M2가 셋을 더한다. bash는 libtinfo6만 있으면 되고, zsh는 libtinfo6 +
# libcap2를 요구한다. zsh-common은 fish-common과 같은 구조로 arch: all이라
# :amd64를 붙이지 않는다 — /usr/share/zsh의 함수들이 거기 있다. apt-get
# download는 의존을 따라가지 않으므로 이 목록은 언제나 명시적이다.
```

- [ ] **Step 2: 이미지 재빌드 (네트워크 필요, 몇 분)**

Run:
```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile . 2>&1 | tail -20
```

Expected: 마지막에 `naming to docker.io/library/tars-devcontainer`. `--platform`을
붙이지 않았는지 확인할 것.

- [ ] **Step 3: sysroot 실측 — 경로·버전·의존을 눈으로 본다**

**이 Step이 Task 2의 입력이다.** Debian trixie는 usrmerge가 끝난 릴리스라
bash/zsh가 `/usr/bin`에 있을 것으로 보지만, 추측 대신 확인한다. zsh 모듈
디렉터리의 **버전 번호**도 여기서만 알 수 있다.

Run:
```bash
docker run --rm tars-devcontainer bash -c '
  echo "=== binaries ==="
  ls -l $AMD64_SYSROOT/usr/bin/bash $AMD64_SYSROOT/usr/bin/zsh \
        $AMD64_SYSROOT/bin/bash $AMD64_SYSROOT/bin/zsh 2>&1
  echo "=== zsh module dir ==="
  ls -d $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/zsh/*
  find $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/zsh -name "*.so" | wc -l
  echo "=== NEEDED of bash/zsh ==="
  for f in $AMD64_SYSROOT/usr/bin/bash $AMD64_SYSROOT/usr/bin/zsh; do
    echo "-- $f"
    readelf -d $f | sed -n "s/.*(NEEDED).*\[\(.*\)\]/\1/p"
  done
  echo "=== NEEDED of all zsh modules (union) ==="
  find $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/zsh -name "*.so" -exec readelf -d {} \; \
    | sed -n "s/.*(NEEDED).*\[\(.*\)\]/\1/p" | sort -u
  echo "=== sizes ==="
  du -sh $AMD64_SYSROOT/usr/share/zsh $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/zsh
'
```

Expected(예상이며, 다르면 Task 2의 해당 경로만 고친다):

- `/usr/bin/bash`, `/usr/bin/zsh`가 존재하고 `/bin/...`은 없다
- 모듈 디렉터리는 `.../zsh/5.9` 같은 **버전 이름 하나**
- bash: `libtinfo.so.6`, `libc.so.6`
- zsh: `libcap.so.2`, `libtinfo.so.6`, `libc.so.6`
- 모듈 union: 위와 같거나 여기에 `libgdbm.so.6`, `libpcre2-8.so.0` 등이 더 붙음
- `/usr/share/zsh` 몇 MB, 모듈 디렉터리 1~3MB

**출력 전체를 붙여서 알릴 것.** 특히 모듈 union에 위 목록 밖의 소네임이 있으면
Task 2에서 `make_initrd.sh`가 그 이름을 찍고 죽는다 — 그때 대응은 둘이다.
(a) 해당 패키지를 Dockerfile 목록에 추가, (b) 그 모듈을 initrd에서 제외.
설정 파일 하나 읽는 셸에 `zsh/db/gdbm`은 필요 없으므로 (b)가 보통 맞다.

**실측 결과 (2026-08-14) — Task 2는 이 값을 쓴다:**

| 항목 | 값 |
|---|---|
| bash / zsh | `/usr/bin/bash` 1.3MB, `/usr/bin/zsh` 0.9MB (`/bin/...`은 없다) |
| 모듈 디렉터리 | `.../zsh/5.9`, `.so` 38개, 합계 1.5MB |
| bash NEEDED | `libtinfo.so.6`, `libc.so.6` |
| zsh NEEDED | `libcap.so.2`, `libtinfo.so.6`, `libm.so.6`, `libc.so.6` |
| 모듈 NEEDED 합집합 | 위 + `libgdbm.so.6`, `libncursesw.so.6`, `libpcre2-8.so.0` |
| `/usr/share/zsh` | **17MB** |

두 가지가 plan의 예상과 달랐고, 둘 다 "넣지 않는다"로 정했다.

1. **`libgdbm.so.6`(`zsh/db/gdbm.so`)와 `libncursesw.so.6`(`zsh/curses.so`)가
   sysroot에 없다.** 38개 중 둘뿐이고 `zmodload`로 이름을 대고 부를 때만 열리는
   선택적 모듈이다 — 위 (b)를 고른다.
2. **`/usr/share/zsh`가 17MB다.** design doc은 fish-common과 같은 규모로 보고
   "함께 필요하다"고 적었지만, 실측은 initrd(gzip 11.8MB)를 흔드는 크기다.
   내용은 전부 fpath에서 autoload되는 함수이고 `~/.zshrc`가 없는 우리 게스트는
   `compinit`도 부르지 않으므로 **없어도 zsh는 조용히 시작한다.** 패키지는
   sysroot에 그대로 둬서(이미 받아 놓았다) 필요해지면 네트워크 없이 한 줄로
   켤 수 있게 한다. 이 판단은 design doc "미리 알고 들어가는 위험 3"(initrd
   크기)이 예고한 그 자리다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 2: initrd에 셸 셋을 담는다

**Files:**
- Modify: `kernel/make_initrd.sh`

fish 하나만 복사하던 스크립트에 둘을 더한다. **zsh는 바이너리 하나가
아니라는 것**이 이 Task의 내용 전부다.

- [ ] **Step 1: 바이너리 복사 + 의존 추적**

`kernel/make_initrd.sh:96-97`의 fish 복사 **바로 아래**에 넣는다.

```bash
# CP-M2: 설정으로 고를 수 있는 셸 셋. initrd 안의 자리는 sysroot의 원래
# 자리(usrmerge 여부)와 무관하게 우리가 정한다 — init/src/config.zig의
# Shell.path()가 여기와 같은 경로를 돌려줘야 한다. 둘이 어긋나면 부팅 후
# "execve failed"로만 나타난다.
cp "$SYSROOT/usr/bin/bash" "$WORKDIR/usr/bin/bash"
cp "$SYSROOT/usr/bin/zsh" "$WORKDIR/usr/bin/zsh"
chmod 0755 "$WORKDIR/usr/bin/bash" "$WORKDIR/usr/bin/zsh"
```

그리고 `copy_lib_deps` 묶음(`kernel/make_initrd.sh:106-110`)에 두 줄 추가:

```bash
copy_lib_deps "$WORKDIR/usr/bin/bash"
copy_lib_deps "$WORKDIR/usr/bin/zsh"
```

- [ ] **Step 2: zsh 모듈 트리 — 유일하게 경로를 보존해야 하는 것**

`/usr/share/fish` 복사 블록(`kernel/make_initrd.sh:112-116`) 아래에 넣는다.
**버전 번호(`5.9`)를 적지 않는다** — 와일드카드로 통째로 복사하므로 패키지가
올라가도 이 스크립트는 그대로다.

```bash
# zsh는 바이너리 하나가 아니다. zle(줄 편집), complete, parameter 같은
# "내장처럼 보이는" 기능 대부분이 실행 중에 dlopen되는 .so 모듈이고, 그것을
# 찾을 자리(module_path)는 zsh 안에 컴파일 타임에 박혀 있다. 그래서 이 트리만은
# initrd 안에서도 **sysroot와 같은 경로**를 유지해야 한다 — 다른 라이브러리처럼
# /lib/x86_64-linux-gnu로 모으면 zsh가 영영 못 찾는다.
mkdir -p "$WORKDIR/usr/lib/x86_64-linux-gnu"
cp -r "$SYSROOT/usr/lib/x86_64-linux-gnu/zsh" "$WORKDIR/usr/lib/x86_64-linux-gnu/"

# 38개 중 둘만 sysroot에 없는 라이브러리를 요구한다(2026-08-14 실측):
# zsh/curses는 libncursesw.so.6, zsh/db/gdbm은 libgdbm.so.6. 둘 다 zmodload로
# 이름을 대고 부를 때만 열리는 선택적 모듈이라 우리 셸은 부를 일이 없다.
# 라이브러리 두 개를 게스트에 들이는 대신 모듈을 뺀다 — 남겨두면 아래
# copy_lib_deps가 그 소네임을 찍고 즉시 죽는다(그게 정상 동작이다).
rm -f  "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/curses.so
rm -rf "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/db

# 모듈도 각자 동적 의존을 갖는다. 바이너리에만 copy_lib_deps를 돌리면 빠진
# 라이브러리가 **부팅 후 dlopen 시점에야** 드러나고, 그 실패는 로그에서
# 알아보기 어렵다. 여기서 돌려야 make_initrd.sh가 소네임을 찍고 즉시 죽는다.
while IFS= read -r mod; do
  copy_lib_deps "$mod"
done < <(find "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh" -name '*.so')

# /usr/share/zsh(zsh-common)는 **넣지 않는다.** fish가 fish-common을 필요로
# 했던 것과 같은 구조이긴 한데 크기가 다르다 — 17MB이고 대부분이 완성
# 함수(Completion)다. zsh는 이 트리가 없어도 조용히 시작한다: 여기 있는 것은
# 전부 fpath에서 autoload되는 함수이고, ~/.zshrc가 없는 우리 게스트에서는
# compinit도 promptinit도 불리지 않는다. 필요해지면 아래 한 줄을 살린다
# (패키지는 이미 sysroot에 구워져 있으므로 네트워크 없이 켤 수 있다).
#
#   cp -r "$SYSROOT/usr/share/zsh" "$WORKDIR/usr/share/"
```

- [ ] **Step 3: initrd를 만들어 본다**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'cd kernel && ./make_initrd.sh && ls -l initrd.cpio'
```

Expected: 에러 없이 끝나고 `initrd.cpio`가 **12.5~14MB**(CP-M1까지 11.8MB).
더해지는 것은 bash 1.3MB + zsh 0.9MB + 모듈 1.5MB + libtinfo/libcap ~1MB이고,
gzip 뒤에는 그 절반 이하로 줄어든다.

실패한다면 십중팔구 이 모양이다:

```
make_initrd: cannot resolve libgdbm.so.6 (needed by .../zsh/5.9/zsh/db/gdbm.so) in /usr/local/amd64-sysroot
             add the package that provides it to devcontainer/Dockerfile
```

**이건 고장이 아니라 설계된 동작이다**(`project_build_host_arch`). Step 2의 두
`rm`이 이미 알려진 두 모듈을 빼므로 이 메시지가 나온다면 **다른 소네임**일
것이다 — 그대로 알릴 것. 대응은 (a) 패키지를 Dockerfile 목록에 추가,
(b) 그 모듈을 `rm` 줄에 추가. 선택적 모듈이면 (b)가 맞다.

- [ ] **Step 4: 셋이 실제로 들어갔는지 목록으로 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'zcat kernel/initrd.cpio | cpio -t --quiet 2>/dev/null > /tmp/list.txt
   grep -E "usr/bin/(bash|zsh|fish)$|libtinfo|libcap" /tmp/list.txt
   echo "--- zsh modules ---"
   grep -c "lib/x86_64-linux-gnu/zsh/.*\.so$" /tmp/list.txt
   echo "--- must be empty (removed modules) ---"
   grep -E "zsh/curses\.so|zsh/db/" /tmp/list.txt
   echo "--- must be empty (share tree not shipped) ---"
   grep "usr/share/zsh" /tmp/list.txt'
```

Expected: `usr/bin/bash`, `usr/bin/zsh`, `usr/bin/fish` 세 줄과
`lib/x86_64-linux-gnu/libtinfo.so.6`, `libcap.so.2`. 모듈 개수는 **36**
(38에서 `curses.so`와 `db/gdbm.so`를 뺀 값). 마지막 두 블록은 출력이 없어야
한다.

**`usr/bin/`으로 시작하는지 확인할 것.** `./usr/bin/bash` 앞의 `.`은 cpio가
붙이는 것이라 정상이다.

- [ ] **Step 5: Commit**

Claude가 수행한다.

---

## Task 3: `init`이 설정대로 셸을 고른다

**Files:**
- Modify: `init/src/config.zig` (`Shell`에 메서드 둘)
- Modify: `init/src/main.zig` (`Kind.path()` 제거, `Child`에 실행 정보, 폴백 하나)

- [ ] **Step 1: `config.zig`의 `Shell`에 메서드 둘을 추가**

`init/src/config.zig:16-20`. 바꾸기 전:

```zig
pub const Shell = enum {
    fish,
    bash,
    zsh,
};
```

바꾼 뒤(주석 첫 문단의 마지막 문장 "이름을 실제 경로로 바꿔 셸을 띄우는 것은
CP-M2의 일이다"도 지운다 — 이제 그 일이 이 파일 안에 있다):

```zig
/// 셸 화이트리스트. 설정 파일에 적을 수 있는 것은 **이름**뿐이고 경로가
/// 아니다 — `shell=/etc/passwd` 같은 입력이 애초에 성립하지 않는다
/// (design doc "5. 설정 하나로 부팅이 막히지 않게 하는 세 장치"의 1번).
pub const Shell = enum {
    fish,
    bash,
    zsh,

    /// 이름 → initrd 안의 바이너리 경로. 화이트리스트의 나머지 절반이다:
    /// enum이 "무엇을 적을 수 있는가"를, 이 switch가 "그것이 무엇을
    /// 실행하는가"를 정한다. 둘을 붙여 두면 Shell에 이름을 하나 더 넣는 순간
    /// switch가 컴파일 에러를 내서 경로를 빼먹을 수 없다.
    ///
    /// 여기 적힌 경로는 kernel/make_initrd.sh가 복사해 넣는 자리와 **같아야
    /// 한다.** 어긋나면 부팅 후 execve 실패로만 드러난다.
    pub fn path(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "/usr/bin/fish",
            .bash => "/usr/bin/bash",
            .zsh => "/usr/bin/zsh",
        };
    }

    /// "사용자 설정 파일을 읽지 말라"는 플래그. 셋의 철자가 전부 다르다.
    /// initrd에는 ~/.bashrc도 ~/.zshrc도 없어서 지금은 있으나 없으나 동작이
    /// 같지만, 프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있다
    /// (TF-M3이 fish에 --no-config를 준 이유가 그것이다).
    pub fn noConfigFlag(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "--no-config",
            .bash => "--norc",
            .zsh => "-f",
        };
    }
};
```

- [ ] **Step 2: `main.zig`의 `Kind`에서 `path()`를 걷어낸다**

`init/src/main.zig:129-148`. 바꾸기 전은 `Kind`에 `name()`과 `path()`가 있고
위에 "설정 파일에서 목록을 읽는 것은 다음 서브프로젝트의 일이다"라는 주석이
붙어 있다. 바꾼 뒤:

```zig
/// 감독 대상의 종류. **무엇을 실행할지는 여기 없다** — 그것은 Child가
/// 들고 있고, 설정을 읽은 뒤 main에서 한 번 정해진다. Kind는 "이 자식이
/// 제어 터미널을 잡아야 하는가"와 로그 이름만 결정한다.
const Kind = enum {
    terminal,
    console_shell,

    fn name(self: Kind) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .console_shell => "console shell",
        };
    }
};

/// terminal은 우리가 빌드해 initrd 루트에 넣는 것이라 설정 대상이 아니다.
const TERMINAL_PATH: [:0]const u8 = "/terminal";
```

- [ ] **Step 3: `Child`가 실행할 것을 들고 있게 한다**

`init/src/main.zig:156-163`. 바꾼 뒤:

```zig
const Child = struct {
    kind: Kind,
    /// 실행할 바이너리. 로그에 찍는 것도 이 값이다.
    path: [:0]const u8,
    /// execve에 그대로 넘길 argv. argv[0]은 path와 같고 남는 자리는 null이다 —
    /// execve는 첫 null에서 멈추므로 인자가 하나인 자식도 같은 배열 타입을
    /// 쓸 수 있다. 힙이 없어서 길이를 컴파일 타임에 고정한다.
    argv: [3:null]?[*:0]const u8,
    /// -1이면 지금 돌고 있지 않다는 뜻이다.
    pid: linux.pid_t = -1,
    started_at: isize = 0,
    fast_restarts: u32 = 0,
    given_up: bool = false,
};
```

- [ ] **Step 4: `spawn`/`start`가 `Child`를 통째로 본다**

`init/src/main.zig:176-203`. 바꾼 뒤:

```zig
fn spawn(c: *const Child, envp: [*:null]const ?[*:0]const u8) linux.pid_t {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for {s} failed (errno {d})\n", .{
            c.kind.name(), @intFromEnum(e),
        });
        return -1;
    }
    if (pid == 0) {
        // 여기부터는 자식이다.
        if (c.kind == .console_shell) setupControllingTerminal();
        _ = linux.execve(c.path.ptr, &c.argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve {s} failed\n", .{c.path});
        linux.exit(127);
    }
    return @intCast(pid);
}

fn start(c: *Child, envp: [*:null]const ?[*:0]const u8) void {
    const pid = spawn(c, envp);
    if (pid < 0) return; // 다음 바퀴에서 다시 시도한다
    c.pid = pid;
    c.started_at = monotonicSeconds();
    // 경로까지 찍는다. "셸이 바뀌었는가"를 게이트가 확인할 수 있는 유일한
    // 줄이다 — 프로세스가 무엇을 exec했는지는 밖에서 볼 방법이 없다.
    std.debug.print("tars-init: started {s} (pid {d}, {s})\n", .{
        c.kind.name(), pid, c.path,
    });
}
```

**로그 문자열 주의:** `tars-init: started terminal`은 `terminal/check.sh:170`이
grep하는 마커다. 뒤에 `, /terminal)`이 붙어도 부분 문자열이라 계속 맞는다 —
**앞부분을 바꾸지 않는 것**이 조건이다.

- [ ] **Step 5: 없는 셸로 부팅이 막히지 않게 하는 폴백**

`loadConfig` 바로 아래에 넣는다.

```zig
/// 설정이 고른 셸의 바이너리가 정말 있는지 확인하고, 없으면 기본값으로
/// 내려온다. design doc의 "세 장치" 중 2번(모르는 값 → 기본값)의 연장이다 —
/// 이름은 화이트리스트가 막아주지만 **initrd에 안 들어간 셸**은 이름이
/// 맞아도 실행되지 않는다.
///
/// 이 함수가 없으면 그 상황이 이렇게 나타난다: execve가 127로 죽고, 감독
/// 루프가 1초 간격으로 세 번 재시작한 뒤 포기하고, **셸이 하나도 없는 부팅**이
/// 된다. 원인은 로그 깊숙한 곳의 execve 한 줄뿐이다. 미리 확인하면 한 줄로
/// 드러나고 부팅은 계속된다.
fn resolveShell(want: config.Shell) config.Shell {
    if (failed(linux.access(want.path().ptr, linux.X_OK)) == null) return want;

    const fallback = config.Config{};
    std.debug.print("tars-init: shell {s} is not executable, falling back to {s}\n", .{
        want.path(), @tagName(fallback.shell),
    });
    return fallback.shell;
}
```

- [ ] **Step 6: `main`에서 잇는다**

`init/src/main.zig:292-302`. 바꾼 뒤:

```zig
    const storage_mounted = mountConfig();
    const cfg = loadConfig(storage_mounted);
    std.debug.print("tars-init: config shell={s}\n", .{@tagName(cfg.shell)});

    logDrmDevicePresence();

    // 설정이 실제 동작이 되는 유일한 자리. 여기서 한 번 정해지면 감독 루프는
    // 설정을 모른 채 이 값을 반복해서 띄운다 — 재시작이 설정을 다시 읽지
    // 않는다는 뜻이고, "고치고 재부팅해야 반영된다"는 정책이 그래서 지켜진다.
    const shell = resolveShell(cfg.shell);
    const shell_path = shell.path();
    const shell_flag = shell.noConfigFlag();

    var children = [_]Child{
        .{
            .kind = .terminal,
            .path = TERMINAL_PATH,
            // terminal은 설정 파일을 읽지 않는다. 어느 셸을 PTY에 띄울지를
            // PID 1이 정해서 인자로 넘긴다 — 파서가 두 벌이 되면 두
            // 프로세스가 서로 다른 답을 얻을 수 있다.
            .argv = .{ TERMINAL_PATH.ptr, shell_path.ptr, shell_flag.ptr },
        },
        .{
            .kind = .console_shell,
            .path = shell_path,
            // 콘솔 셸에는 플래그를 주지 않는다. 이쪽은 사용자가 직접 쓰는
            // 자리이므로, 나중에 설정 파일이 생기면 그것을 읽는 편이 맞다.
            .argv = .{ shell_path.ptr, null, null },
        },
    };
    supervise(&children, envp);
```

- [ ] **Step 7: 빌드 + 정적 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'cd init && zig build && readelf -d zig-out/bin/init | grep -c NEEDED; ls -l init/zig-out/bin/init'
```

Expected: `0`(동적 의존 없음), 12MB 안팎.

에러가 나면 후보는 셋이다.
- `[3:null]?[*:0]const u8`의 초기화 문법 — `.{ a, null, null }`이 안 되면
  `[_:null]?[*:0]const u8{ ... }`로 명시.
- `&c.argv`가 `[*:null]const ?[*:0]const u8`로 coerce되지 않는 경우.
- `linux.access`의 두 번째 인자 타입(`linux.X_OK`는 std 0.16.0에 `= 1`로 있는
  것을 확인했다).

전문을 붙여서 알릴 것.

- [ ] **Step 8: Commit**

Claude가 수행한다.

---

## Task 4: `terminal`이 받은 셸을 띄운다

**Files:**
- Modify: `terminal/src/main.zig:104-109`

- [ ] **Step 1: argv에서 셸을 읽는다**

바꾸기 전:

```zig
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // `--no-config`는 유지한다(사용자 설정 파일이 initrd에 없기도 하고,
    // 프롬프트가 예측 가능해야 검증이 쉽다).
    const argv = [_:null]?[*:0]const u8{ "fish", "--no-config" };
    const session = try pty.spawn("/usr/bin/fish", &argv, cols, rows);
    std.debug.print("terminal: spawned child pid {d}\n", .{session.child_pid});
```

바꾼 뒤:

```zig
    // 어느 셸을 띄울지는 init이 정해서 argv로 넘겨준다(CP-M2). 설정 파일을
    // 읽는 것은 PID 1의 일이고, terminal은 그 결정을 실행만 한다 — 파서가 두
    // 벌이 되면 두 프로세스가 같은 파일에서 서로 다른 답을 얻을 수 있다.
    // 인자 없이 손으로 실행할 때를 위해 기본값은 남긴다.
    //
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // no-config 플래그(fish --no-config / bash --norc / zsh -f)를 계속 주는
    // 이유는 프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있기 때문이다.
    const args = init.minimal.args.vector;
    const shell_path: [*:0]const u8 = if (args.len > 1) args[1] else "/usr/bin/fish";
    const shell_flag: [*:0]const u8 = if (args.len > 2) args[2] else "--no-config";

    const argv = [_:null]?[*:0]const u8{ shell_path, shell_flag };
    const session = try pty.spawn(shell_path, &argv, cols, rows);
    // 경로까지 찍는다. 게이트가 "화면의 셸도 바뀌었는가"를 볼 수 있는 유일한
    // 줄이다. 앞부분("terminal: spawned child pid ")은 terminal/check.sh가
    // 개수를 세는 마커라 **그대로 둔다**.
    std.debug.print("terminal: spawned child pid {d} ({s})\n", .{
        session.child_pid, shell_path,
    });
```

argv[0]이 예전에는 `"fish"`(basename)였고 이제 전체 경로다. 셸 셋 다 argv[0]을
"앞에 `-`가 붙었으면 로그인 셸"로만 보므로 동작이 달라지지 않는다.

- [ ] **Step 2: 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'cd terminal && ./prepare.sh 2>&1 | tail -5'
```

Expected: 에러 없이 끝난다.

에러가 나면 `init.minimal.args.vector`가 후보다. Zig 0.16.0의
`std.process.Init`은 `.minimal: Minimal`을 품고 `Minimal.args: Args`,
`Args.vector`가 리눅스에서 `[]const [*:0]const u8`인 것을 확인했지만,
`main(init: std.process.Init)` 쪽에서 필드 이름이 다르면 여기서 잡힌다.

- [ ] **Step 3: Commit**

Claude가 수행한다.

---

## Task 5: 게이트가 게스트 안에서 설정을 고친다

**Files:**
- Modify: `config/check.sh`

**이 Task가 CP-M2의 진짜 작업량이다.** CP-M1의 게이트는 "1차가 쓴 것을 2차가
읽는다"였다. 이제 **쓰는 주체가 init이 아니라 사람(을 흉내낸 sendkey)**이 된다.

design doc 6번이 호스트에서 `debugfs`로 이미지를 편집하는 쉬운 길을 버린 이유가
여기서 값을 한다 — 호스트 편집은 "게스트가 쓴 것이 디스크에 도달했는가"라는
경로(파일시스템 쓰기 + `MS_SYNCHRONOUS`)를 통째로 건너뛴다.

- [ ] **Step 1: `config/check.sh`를 아래 내용으로 교체**

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# 빌드 순서는 TF 체인과 같다(kernel → init → terminal → initrd).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 디스크는 매 회차 새로 굽는다. 남은 이미지를 재사용하면 "빈 디스크로 첫
# 부팅"이라는 전제가 무너지고, 1차 부팅이 검증할 seeding 경로가 다시는
# 실행되지 않은 채 게이트가 자기를 속이게 된다.
#
# 반대로 **두 부팅 사이에서는 절대 다시 부르지 않는다.** 그게 이 체인의 검증
# 그 자체다 — 1차에서 사람이 고친 것을 2차가 읽어야 한다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

# TF 체인은 45455를 쓴다. 다른 번호를 쓰는 이유는 어느 한쪽이 죽다 만 QEMU를
# 남겼을 때 엉뚱한 게스트에 키를 보내지 않기 위해서다.
MONITOR_PORT=45456

LOG1="$(mktemp)"
LOG2="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 게스트 셸에 한 글자씩 타이핑한다.
#
# sendkey가 보내는 것은 **문자가 아니라 키**다. 그래서 '='는 equal, '>'는
# shift-dot, '/'는 slash로 적어야 하고, 게스트 쪽에서 evdev 이벤트를 다시
# 문자로 바꾸는 것은 우리 코드다(terminal/src/input.zig의 keymap). 두 겹이 다
# 맞아야 파일에 한 줄이 써진다 — 이 게이트는 그 두 겹까지 검사하는 셈이다.
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# echo shell=zsh > /config/tars.conf
EDIT_KEYS=(e c h o spc s h e l l equal z s h spc shift-dot spc
           slash c o n f i g slash t a r s dot c o n f ret)
# cat /config/tars.conf
READBACK_KEYS=(c a t spc slash c o n f i g slash t a r s dot c o n f ret)

# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
# 설정을 바꾼다.
edit_config_in_guest() {
  local log="$1"

  # 프롬프트가 그려진 뒤에 쳐야 한다. "terminal: screen>" 첫 줄이 곧 DRM 열기 +
  # 폰트 래스터라이즈 + evdev 열기 + 셸 spawn + 첫 렌더가 전부 끝났다는
  # 신호다(TF 체인과 같은 신호를 쓴다).
  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 1): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi
  sleep 1

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 1): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${EDIT_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  # 되읽기 확인. dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다.
  # 그래서 **행의 첫머리가 shell=zsh인 것**이 cat의 출력이다 — 방금 타이핑한
  # 명령줄에도 shell=zsh가 들어 있지만 그 행은 프롬프트와 echo로 시작한다.
  #
  # 이 검사가 통과하면 "키가 게스트에 도달했고, 셸이 명령을 실행했고, 파일에
  # 써졌고, 다시 읽힌다"까지가 한꺼번에 확인된다.
  local wrote=0
  for _ in $(seq 1 30); do
    if grep -q "terminal: screen>.*| shell=zsh" "$log"; then wrote=1; break; fi
    sleep 1
  done

  exec 3<&-
  exec 3>&-

  if [ "$wrote" != "1" ]; then
    echo "FAIL(boot 1): typed the edit but /config/tars.conf never read back as shell=zsh"
    return 1
  fi
  echo "boot 1: typed the edit in the guest and read it back (shell=zsh)"
  return 0
}

# 2차 부팅에서 마커를 본 뒤 하는 일. 여기서 확인할 것 중 몇 개는 **없어야 할
# 것**(셸이 죽지 않았다)이라 관측 창이 필요하다. 부재는 폴링으로 증명할 수
# 없으므로 이 5초만 고정 대기다 — 재시작 backoff가 1초이므로 세 번 죽고 포기하는
# 데 3초면 충분하다.
watch_console_shell() {
  sleep 5
  return 0
}

# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커, $3 = (선택) 마커를 본 뒤
# QEMU를 죽이기 전에 부를 함수.
boot_once() {
  local log="$1"
  local marker="$2"
  local hook="${3:-}"

  qemu-system-x86_64 \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
    -display none \
    -serial file:"$log" \
    -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
    -no-reboot &
  QEMU_PID=$!

  # 고정 sleep 대신 로그 폴링. 마커가 나오면 즉시 다음으로 간다.
  local found=0
  for _ in $(seq 1 120); do
    if grep -q "$marker" "$log"; then
      found=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  local hook_ok=1
  if [ "$found" = "1" ] && [ -n "$hook" ]; then
    "$hook" "$log" || hook_ok=0
  fi

  # 마커를 봤든 못 봤든 여기서 QEMU를 확실히 끝낸다. wait까지 하는 이유는
  # 다음 부팅이 **같은 디스크 이미지**를 열기 때문이다 — 두 QEMU가 같은
  # 이미지를 동시에 쓰면 파일시스템이 깨지고, 그 실패는 이 체인이 검증하려는
  # 것과 구분이 안 되는 모양으로 나타난다.
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""

  [ "$found" = "1" ] && [ "$hook_ok" = "1" ]
}

# 실패했을 때 "어디까지 갔는가"를 보여준다. 마커 하나하나가 부팅의 단계다.
report_failure() {
  local log="$1"
  local msg="$2"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "\[vda\]" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config" \
    "tars-init: created /config/tars.conf" \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: config shell=" \
    "tars-init: started console shell" \
    "tars-init: shell .* is not executable" \
    "terminal: spawned child pid" \
    "terminal: screen>"; do
    if grep -q "$marker" "$log"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- tail ---"
  tail -n 60 "$log"
  exit 1
}

# ---------------------------------------------------------------- 1차 부팅
# 빈 디스크. init이 씨앗을 심고(fish), 그 다음 사람이 zsh로 고친다.
echo "=== boot 1/2: empty disk, seed the config then edit it from inside the guest ==="
if ! boot_once "$LOG1" "tars-init: created /config/tars.conf" edit_config_in_guest; then
  report_failure "$LOG1" "first boot did not seed and edit /config/tars.conf"
fi

if ! grep -q "\[vda\]" "$LOG1"; then
  report_failure "$LOG1" "kernel never reported a [vda] block device on the first boot"
fi

# 빈 디스크였는데 loaded가 나왔다면 make_disk.sh가 안 돌았거나 이전 회차의
# 이미지가 남아 있는 것이다.
if grep -q "tars-init: loaded /config/tars.conf" "$LOG1"; then
  report_failure "$LOG1" "first boot loaded an existing config; the disk was not empty"
fi

# 씨앗은 언제나 기본값이다. 1차 부팅의 셸은 아직 fish여야 한다 — 여기가
# zsh였다면 디스크가 비어 있지 않았다는 뜻이다.
if ! grep -q "tars-init: config shell=fish" "$LOG1"; then
  report_failure "$LOG1" "first boot did not start from the default (fish)"
fi

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: seeded with fish, then edited to zsh from inside the guest"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
echo "=== boot 2/2: same image, the guest-written config should pick the shell ==="
if ! boot_once "$LOG2" "tars-init: started console shell" watch_console_shell; then
  report_failure "$LOG2" "second boot never started a console shell"
fi

if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot did not load /config/tars.conf"
fi

# 1차가 쓴 파일이 살아남았는지. CP-M1부터 이 게이트의 핵심인 부정 검사다.
if grep -q "tars-init: created /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot re-created the config file; nothing persisted"
fi

# ★ CP-M2가 증명하려는 것. 파일을 읽었다 → 값이 파싱됐다 → 그 값이 실제로
#   exec된 바이너리를 바꿨다. 세 줄이 각각 그 세 단계다.
if ! grep -q "tars-init: config shell=zsh" "$LOG2"; then
  report_failure "$LOG2" "second boot did not parse shell=zsh out of the config file"
fi

if ! grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$LOG2"; then
  report_failure "$LOG2" "second boot parsed zsh but did not exec /usr/bin/zsh"
fi

if ! grep -q "terminal: spawned child pid .*(/usr/bin/zsh)" "$LOG2"; then
  report_failure "$LOG2" "the terminal did not spawn zsh in its PTY"
fi

# 폴백이 발동했다면 initrd에 zsh가 안 들어간 것이다. 부팅은 계속되므로 위
# 검사만으로는 원인이 안 보인다 — 이 줄이 그 자리를 가리킨다.
if grep -q "tars-init: shell .* is not executable" "$LOG2"; then
  report_failure "$LOG2" "the configured shell was missing from the initrd (init fell back)"
fi

if grep -q "tars-init: execve /usr/bin/zsh failed" "$LOG2"; then
  report_failure "$LOG2" "execve of /usr/bin/zsh failed (missing loader or library?)"
fi

# zsh가 떴다가 바로 죽는 경우. terminfo가 없어 zle가 깨지는 상황이 여기로 온다.
if grep -q "tars-init: giving up on console shell" "$LOG2"; then
  report_failure "$LOG2" "the console shell kept dying; init gave up on it"
fi

# 시리얼 콘솔이 정말 fish가 아닌지. 화면 덤프(terminal: screen>) 안의 문자열은
# 터미널이 렌더링한 픽셀의 텍스트일 뿐이라 제외한다.
if grep "Welcome to fish, the friendly interactive shell" "$LOG2" | grep -qv "terminal: screen>"; then
  report_failure "$LOG2" "the serial console still ran fish on the second boot"
fi

if grep -q "Attempted to kill init" "$LOG2"; then
  report_failure "$LOG2" "kernel panicked because PID 1 exited on the second boot"
fi
echo "boot 2: the config written inside the guest selected zsh for both shells"

# 정보성. ext2가 "not clean"이라고 말하는 것은 예상된 결과다(1차를 kill했다).
if grep -q "mounting unchecked fs" "$LOG2"; then
  echo "note: ext2 reported an unclean superblock on boot 2 (expected: boot 1 was killed)"
fi

# 성공해도 시리얼 로그의 init 줄은 남긴다. 루트 게이트가 만드는 통합 로그에서
# 이 체인이 무엇을 봤는지 나중에 확인할 수 있어야 한다.
echo "--- init log (boot 1) ---"
grep 'tars-init:' "$LOG1" || true
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true

echo "PASS"
exit 0
```

- [ ] **Step 2: 실행 권한 확인**

Run:
```bash
ls -l config/check.sh config/make_disk.sh
```

Expected: 둘 다 `-rwxr-xr-x`. 아니면 `chmod +x config/check.sh`.

- [ ] **Step 3: CP 체인 단독 실행**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash config/check.sh 2>&1 | tee /tmp/cp-m2.log
```

Expected 마지막:

```
boot 1: seeded with fish, then edited to zsh from inside the guest
boot 2: the config written inside the guest selected zsh for both shells
--- init log (boot 1) ---
...
--- init log (boot 2) ---
...
PASS
```

**이번 milestone에서 가장 깨지기 쉬운 지점이다.** 실패하면 `--- markers ---`와
`--- tail ---`를 통째로 붙여서 알릴 것. 아래 "대비해 둔 실패 갈래"에 원인별
대응이 있다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 6: 루트 게이트와 회귀

**Files:**
- Modify: `check.sh:44-49` (주석 + 라벨)

`init`과 `terminal` 바이너리가 둘 다 바뀌었고 initrd가 커졌으므로 세 체인을 다
돌린다.

- [ ] **Step 1: 루트 게이트 라벨**

바꾼 뒤:

```bash
# CP-M1부터 이 체인만 회차당 QEMU를 **두 번** 띄운다. 영속성은 한 번의
# 부팅으로 증명할 수 없기 때문이다 — 1차가 쓴 파일을 2차가 읽는다. 그래서
# 루트 게이트 한 번의 총 부팅 횟수는 9회가 아니라 12회다.
#
# CP-M2부터는 그 1차 부팅에서 monitor sendkey로 **게스트 셸에 직접 타이핑**해
# 설정을 고친다. 그래서 이 체인만 회차당 20초쯤 더 걸린다.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
```

- [ ] **Step 2: BF 체인 — 디스크가 없어도, initrd가 커져도 통과해야 한다**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh 2>&1 | tee /tmp/cp-m2-bf.log
```

Expected: `PASS`, 그리고 `Boot reached the fish banner after ~Ns`.

**BF에서 봐야 할 것은 두 가지다.**

1. 여전히 fish다. 디스크가 없으니 `no config storage, using defaults` →
   `config shell=fish` → `started console shell (pid N, /usr/bin/fish)`.
2. **`~Ns`가 CP-M1 때보다 얼마나 늘었는가.** initrd가 커졌고, BF만 limine의
   BIOS INT13h로 ISO에서 읽는다(`kernel/make_initrd.sh:118-122`의 주석). 이
   숫자를 알려줄 것 — 크게 늘면 `init`을 `ReleaseSafe`로 바꾸는 카드를 꺼낼
   시점이다.

확인:
```bash
grep -c 'tars-init: started console shell (pid .*, /usr/bin/fish)' /tmp/cp-m2-bf.log
grep -c 'tars-init: shell .* is not executable' /tmp/cp-m2-bf.log
```

Expected: `1`, `0`.

- [ ] **Step 3: TF 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/cp-m2-tf.log
```

Expected: `PASS`. TF도 `-drive`가 없으므로 전부 fish다. 이 체인이 특히 중요한
이유는 **`terminal`의 argv 처리와 재시작 경로를 동시에 지나기 때문**이다 —
`exit`로 셸을 죽이고 다시 뜨는 그 자리에서 argv가 두 번째로 쓰인다.

- [ ] **Step 4: 루트 게이트 전체**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/cp-m2-gate.log
```

Expected 마지막 줄:

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

CP-M1이 **13분 14초**였다. 늘어나는 것은 회차당 타이핑 ~20초 + 관측 5초이므로
**14분 30초 안팎**을 예상한다. 실제 시간을 알릴 것.

- [ ] **Step 5: 통합 로그에서 숫자 확인**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/cp-m2-gate.log
grep -c 'tars-init: config shell=fish' /tmp/cp-m2-gate.log
grep -c 'tars-init: config shell=zsh' /tmp/cp-m2-gate.log
grep -c 'tars-init: started console shell (pid .*, /usr/bin/fish)' /tmp/cp-m2-gate.log
grep -c 'tars-init: started console shell (pid .*, /usr/bin/zsh)' /tmp/cp-m2-gate.log
grep -c 'tars-init: created /config/tars.conf' /tmp/cp-m2-gate.log
grep -c 'tars-init: loaded /config/tars.conf' /tmp/cp-m2-gate.log
grep -c 'tars-init: shell .* is not executable' /tmp/cp-m2-gate.log
grep -c 'tars-init: giving up on console shell' /tmp/cp-m2-gate.log
grep -c 'Attempted to kill init' /tmp/cp-m2-gate.log
```

Expected: `12`, `9`, `3`, `9`, `3`, `3`, `3`, `0`, `0`, `0`.

각 숫자의 뜻:

- **12** — 부팅 12회(BF 3 + TF 3 + CP 3회차×2). CP-M1과 같다.
- **9 / 3** — fish로 간 부팅 9회(BF 3 + TF 3 + CP 1차 3), zsh로 간 부팅 3회
  (CP 2차). **이 두 숫자가 이 milestone의 요약이다.**
- **9 / 3** — 위와 정확히 짝을 이뤄야 한다. 짝이 안 맞으면 파싱과 exec 사이가
  끊어진 것이다(설정은 읽었는데 다른 것을 띄웠다).
- **3 / 3** — seeding은 회차당 1차에서만, load는 2차에서만.
- **0** — 폴백이 한 번도 발동하지 않았다 = 세 셸이 다 initrd에 있다.
- **0** — 셸이 죽어서 포기한 적이 없다 = zsh가 terminfo 없이도 살아 있다.
- **0** — 패닉 없음.

- [ ] **Step 6: Commit**

Claude가 수행한다.

---

## Task 7: 문서와 기억

**Files:**
- Create: `docs/decisions/project_config_persistence.md` (CP 서브프로젝트 기억)
- Modify: `MEMORY.md` (색인 한 줄)
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점")

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 Task 6까지의 결과만 전달하면 된다.

기억 파일은 **CP-M0~M2가 다 실행돼 본 뒤에 쓴다**는 CP-M1의 결정에 따라
여기서 처음 쓴다. 담을 것(후보):

- 왜 동기 마운트인가, 그리고 그것이 "쓰고 바로 kill"하는 게이트와 어떻게
  맞물리는가
- 한 스크립트에서 QEMU를 두 번 띄우는 게이트 모양과 부정 검사(2차에 `created`가
  없어야 한다)
- 설정이 깨져도 부팅이 막히지 않게 하는 장치들 — 화이트리스트(enum),
  모르는 값 폴백, 마운트 실패 허용, 그리고 CP-M2가 더한 **바이너리 부재 폴백**
- 설정을 읽는 것은 PID 1 하나이고, 결정은 argv로 흘러간다는 구조

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 대비해 둔 실패 갈래

CP-M0과 CP-M1은 준비한 실패가 하나도 안 났다. 이번은 셸 두 개를 새로 들여오고
게이트가 처음으로 게스트에 타이핑하므로 그럴 가능성이 낮다.

### A. zsh가 terminfo를 못 찾는다 (가장 가능성이 높다)

증상: 2차 로그에 `zsh: can't find terminal definition for linux` 같은 줄, 또는
`giving up on console shell`.

**커널은 PID 1에게 `HOME=/`와 `TERM=linux`를 넘긴다**(`init/main.c`의
`envp_init`). `init`은 그 envp를 자식에게 그대로 물려주므로 `TERM`은 **이미
설정돼 있다** — `HANDOFF.md`의 숙제 "TERM이 아무 데도 설정되지 않는다"는
정확히는 "우리가 설정하지 않는다"이고, fish가 잘 돌던 이유가 여기 있을 수
있다. 문제는 terminfo **데이터베이스**가 initrd에 없다는 것이다.

대응(필요할 때만):

```dockerfile
        ncurses-base \
```
를 Dockerfile의 download 목록에 추가(arch: all이라 `:amd64` 없음), 그리고
`make_initrd.sh`에:

```bash
# TERM=linux는 커널이 PID 1에게 준 것을 그대로 물려받는다. 그 이름에 해당하는
# terminfo 항목이 없으면 zle(zsh)·readline(bash)이 화면 제어를 포기한다.
mkdir -p "$WORKDIR/usr/share/terminfo/l"
cp "$SYSROOT/usr/share/terminfo/l/linux" "$WORKDIR/usr/share/terminfo/l/"
```

**깨지는 것을 보고 나서 넣는다** — design doc이 그렇게 정했고, 안 깨지면
불필요한 짐이다.

### B. `make_initrd.sh`가 소네임을 찍고 죽는다

Task 2 Step 3에서 다룬다. 설계된 동작이므로 당황하지 말 것 — 이름이 곧 답이다.

### C. sendkey가 게스트에 안 닿는다

증상: 1차에서 `terminal never rendered a prompt`(모니터 연결 전) 또는
`never read back as shell=zsh`(연결은 됐는데 화면이 안 바뀜).

확인 순서:
1. `terminal: screen>` 줄이 로그에 있는가 — 없으면 sendkey 이전 문제(DRM/evdev).
2. 있는데 화면 내용이 안 바뀌는가 — `sendkey` 이름 오타를 의심한다
   (`shift-dot`, `equal`, `slash`, `spc`, `ret`).
3. 명령줄은 보이는데 `| shell=zsh` 행이 없는가 — **`>` 리다이렉션이 실패한
   것**이다. `/config`가 읽기 전용으로 붙었을 때가 이 모양이고, 그러면 1차
   로그에 `created`가 나온 것과 모순되므로 그 위를 다시 본다.

### D. initrd가 커져 BF가 느려진다

Task 6 Step 2에서 숫자로 본다. 대응은 `init`을 `ReleaseSafe`로 빌드하는 것
(현재 12MB, `HANDOFF.md`의 숙제).

### E. zsh가 뜨긴 하는데 화면이 이상하다

2차 부팅에서 화면 검사를 하지 않는 것이 의도적이다 — **CP-M2가 증명하려는 것은
"어느 바이너리를 exec했는가"이지 "그 셸이 예쁘게 그려지는가"가 아니다.** 화면이
깨져 보인다면 그것은 `TERM`/terminfo 또는 우리 VT의 미구현 시퀀스 문제이고,
별도 주제로 `HANDOFF.md`에 남긴다.

---

## 이번 milestone에서 하지 않는 것

- **nushell.** Debian 아카이브에 없다(design doc 비목표).
- **게스트 안에서 셸을 고르는 명령·메뉴.** `tars-config shell zsh` 같은 CLI는
  design doc 비목표. 이번 종료점은 "파일을 고치고 재부팅"이다.
- **게스트 안에서의 재부팅.** PID 1에 시그널 처리가 없다. 게이트는 QEMU를
  죽였다 다시 띄우는 것으로 대신한다(design doc 비목표).
- **`parse`의 단위 테스트.** 키가 하나뿐인 상태가 유지되므로 CP-M1의 결정을
  그대로 둔다 — "이 저장소에 테스트를 들일 것인가"는 별도 결정.
- **콘솔 셸에 no-config 플래그 주기.** 터미널 쪽에만 준다. 콘솔은 사용자가 직접
  쓰는 자리이므로 나중에 설정 파일이 생기면 읽는 편이 맞다.
- **`/etc/passwd`·`$HOME`·프롬프트 다듬기.** 셸 셋이 뜨기만 하면 이번 목표는
  끝이다.
