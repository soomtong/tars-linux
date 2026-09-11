# UT-M2 Implementation Plan — 목록에 열셋을 더하고, 그 값을 M1이 낸다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 게스트에 모던 도구 한 벌(design 최종 목록의 층 2 열둘 + **사용자가
2026-09-11에 더한 `btop`**)을 세운다. 이름은 `fd`·`bat`처럼 **우리가 정한
것**으로 선다.

**Architecture:** **새 구조를 만들지 않는다.** UT-M1이 `kernel/guest_tools.sh`
한 파일을 세워 두었으므로 이 milestone은 그 배열에 **열세 줄**을 더하고,
`devcontainer/Dockerfile`의 `apt-get download` 목록을 넓히고, `tools/check.sh`에
화면 검사 셋을 더하는 일이다. **M1이 치른 리팩터 비용이 여기서 값을 낸다** —
`make_initrd.sh`는 한 글자도 안 고친다.

**Tech Stack:** bash(sourceable 배열) · Debian `.deb`(`apt-get download`) ·
`readelf`(아키텍처 무관 의존 추적) · QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
— 특히 **결정 3(libgit2 11.4MB를 감수한다) · 결정 4(이름은 우리가 정한다) ·
실측 4·5·9 · 위험 3**, 그리고 **실측 24·26**(정적 검사는 tautology다 ·
게이트가 타이핑하면 안 되는 도구가 있다).

---

## 착수 전에 이 세션이 실측한 것 — **design 실측 5의 사슬이 15가 아니라 16이다**

2026-09-11에 컨테이너 안에서 `.deb` 서른을 풀고, `make_initrd.sh`의
`copy_lib_deps`와 **같은 규칙**(`readelf -d`의 `DT_NEEDED`를 `.so`까지 재귀,
`find_in_sysroot`의 디렉터리 넷)으로 폐포를 다시 쟀다. HANDOFF이 "30초짜리
보험"이라고 지목한 자리다 — UT-M1에서 틀린 것이 정확히 여기였다(실측 22).

### 1. `MISSING`이 0이다

아래 패키지 목록이면 `make_initrd.sh`가 소네임을 못 찾아 죽는 일이 없다.
**빌드가 통과할 것을 빌드 전에 안다.**

### 2. `libresolv.so.2`가 design 표에 없다

```
libgit2.so.1.9  →  libgssapi_krb5.so.2  →  libkrb5.so.3  →  libresolv.so.2   63,936
                                                         →  libcom_err.so.2   18,344
                                                         →  libkeyutils.so.1  22,448
                →  libssh2.so.1         →  libcrypto.so.3            6,517,312
                                                         →  libz.so.1        125,376
                                                         →  libzstd.so.1     825,336
```

design 실측 5의 표는 `libcrypto`를 `libgit2`가 직접 끄는 것처럼 적었지만
실제로는 **`libssh2`를 거친다**. 그리고 **`libresolv.so.2`가 그 표에 아예
없다** — Kerberos가 이름을 풀려고 데려온다.

**그런데 이번엔 Dockerfile을 안 고쳐도 된다.** `libresolv`는 `libc6`이 담고
있고 `libc6:amd64`는 이미 sysroot에 있다. **라이브러리 패키지는 예상대로
열여덟이고, `btop` 때문에 열아홉이 된다.**

### 3. 크기

| | 바이트 |
|---|---|
| 바이너리 열둘 | 28,593,592 |
| 새 라이브러리 19 소네임 | 12,969,880 |
| `btop` + `libstdc++.so.6` | 1,510,496 + 2,497,768 |
| **합계** | **약 45.6 MB** |

design의 "층 2 = 27.3MB"는 `.deb` 압축 크기가 섞인 값이다. **그래도 넣는다** —
UT-M0 실측 15가 78MB 트리로 부팅해서 **1초** 차이를 봤고, 그것이 이 방향의
전제다.

### 4. `.deb` 안의 실제 경로 — 실측 9가 맞다

```
eza      ./usr/bin/eza            1,563,784    (./usr/bin/exa 는 심볼릭 링크)
bat      ./usr/bin/batcat         5,574,496
fd-find  ./usr/lib/cargo/bin/fd   3,504,736    ← 실체
         ./usr/bin/fdfind                      → ../lib/cargo/bin/fd (심볼릭 링크)
```

**`fd`는 심볼릭 링크가 아니라 실체를 복사한다.** `usr/bin/fdfind`를 src로
적으면 `cp`가 따라가서 내용은 맞지만, 원본이 상대 링크라 sysroot 구조가
바뀌면 조용히 깨진다. 실체의 경로를 적는다.

### 5. `btop` — 사용자가 2026-09-11에 추가를 요청했고, 재 보고 넣는다

| | |
|---|---|
| trixie | **있다** (1.3.2-0.1) |
| 바이너리 | 1,510,496 |
| 새 라이브러리 | **`libstdc++.so.6` 2,497,768 하나** |
| 합계 | **4.01 MB** |
| 테마 | `/usr/share/btop/themes` 63,503바이트. **안 넣는다** — 내장 Default로 돈다 |
| UTF-8 | **통과한다.** btop은 로케일이 UTF-8이 아니면 거절하는데, terminal이 `LANG=C.UTF-8`을 넘기고(`terminal/src/main.zig:1028`) `usr/lib/locale/C.utf8`이 initrd에 이미 있다(HI-M1) |

**`btop`이 게스트에서 `libstdc++`의 유일한 사용자다** — 기존 50개와 새 열둘
전부의 `DT_NEEDED`를 확인했다. **나중에 btop을 빼는 사람은 `libstdc++6`도
함께 빼야 한다.** 그 사실이 이 문서와 Dockerfile 주석 양쪽에 있어야 한다.

**`btop`은 게이트가 타이핑하지 않는다** — 실측 26의 그 이유(대화형 전체 화면)
그대로다. `htop`·`ncdu`도 같다.

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `devcontainer/Dockerfile` | `apt-get download` 목록에 **도구 13 + 라이브러리 19** | 고친다 |
| `kernel/guest_tools.sh` | `GUEST_TOOLS`에 **층 2 열세 줄**. 그중 둘이 이름을 바꾼다 | 고친다 |
| `tools/check.sh` | 검사 1에 정적 둘 + **화면 검사 셋**(eza · fd · jq) | 고친다 |
| `check.sh` | `CHAINS`의 `UT-M1` → `UT-M2` | 고친다(한 줄) |
| `kernel/make_initrd.sh` | **안 고친다.** M1이 만든 루프가 열세 줄을 그대로 받는다 | 그대로 |

**`make_initrd.sh`를 안 고치는 것이 이 milestone의 성적표다.** 고쳐야 한다면
M1의 결정 7이 값을 못 낸 것이다.

---

## Task 0: Dockerfile을 넓히고 이미지를 다시 굽는다

**이 Task가 첫째인 이유:** 나머지 전부가 sysroot에 새 파일이 있다는 전제 위에
선다. 그리고 이미지 재빌드는 **네트워크를 쓰는 유일한 단계**이고 3~5분 걸린다.

**Files:**
- Modify: `devcontainer/Dockerfile:99-131`

- [ ] **Step 1: 주석을 먼저 고친다** — 라이브러리가 왜 이만큼인지

`devcontainer/Dockerfile:80-96`의 주석 블록(UT-M1이 "라이브러리 넷"을 설명한
자리) **아래에** 이어 붙인다. **지울 것 없음.**

```dockerfile
#
# ── UT-M2: 층 2(모던 13개)와 라이브러리 열아홉 ──────────────────────────
#
# 도구 13에 딸려 오는 새 소네임을 2026-09-11에 컨테이너 안에서 다시 쟀다.
# 바이너리의 DT_NEEDED만 보지 않고 **.so의 DT_NEEDED까지 재귀로** 봤다 —
# UT-M1이 libsystemd를 놓쳤던 자리이고(design 실측 22), M2는 라이브러리를
# 열아홉 더하므로 같은 누락의 값이 훨씬 비싸다.
#
#   libgit2 사슬 16   eza · bat 둘이 데려온다. design 실측 5는 15라고 적었고
#                     그 표에 libresolv.so.2가 없다 — libkrb5가 데려온다.
#                     **libresolv는 libc6이 담고 있어 여기 안 적는다.**
#   libncursesw6      htop · ncdu
#   libjq1 · libonig5 jq (libonig는 libjq가 데려온다)
#   libstdc++6        **btop 하나뿐이다.** btop을 빼는 사람은 이 줄도 뺀다
#
# libcrypto.so.3 하나가 6.5MB로 가장 크다. **네트워크가 없는 기계가 TLS·
# Kerberos·SSH 스택을 지는 것**이고, 사용자가 그 대가를 알고 Debian 경로를
# 유지하기로 정했다(design 결정 3).
#
# **버전이 이름에 박힌 패키지가 넷이다**(libgit2-1.9 · libssh2-1t64 ·
# libssl3t64 · libmbedtls21/libmbedx509-7/libmbedcrypto16). trixie가 올라가면
# apt가 "없는 패키지"라고 죽는다 — 그때는 `apt-cache search` 한 번으로 새
# 이름을 찾아 여기를 고치면 된다. 조용히 실패하지 않는다.
```

- [ ] **Step 2: `apt-get download` 목록에 열셋 + 열아홉을 더한다**

`devcontainer/Dockerfile:119`의 `util-linux:amd64 \` 줄 **뒤에** 넣는다.
**지울 것 없음.**

```dockerfile
        eza:amd64 \
        bat:amd64 \
        fd-find:amd64 \
        ripgrep:amd64 \
        sd:amd64 \
        procs:amd64 \
        htop:amd64 \
        btop:amd64 \
        tree:amd64 \
        duf:amd64 \
        ncdu:amd64 \
        jq:amd64 \
        hyperfine:amd64 \
        libgit2-1.9:amd64 \
        libgssapi-krb5-2:amd64 \
        libkrb5-3:amd64 \
        libk5crypto3:amd64 \
        libkrb5support0:amd64 \
        libcom-err2:amd64 \
        libkeyutils1:amd64 \
        libmbedtls21:amd64 \
        libmbedx509-7:amd64 \
        libmbedcrypto16:amd64 \
        libhttp-parser2.9:amd64 \
        libssh2-1t64:amd64 \
        libssl3t64:amd64 \
        libzstd1:amd64 \
        zlib1g:amd64 \
        libncursesw6:amd64 \
        libjq1:amd64 \
        libonig5:amd64 \
        libstdc++6:amd64 \
```

- [ ] **Step 3: 이미지를 굽는다**

```bash
docker build -t tars-devcontainer devcontainer/
```

**Expected:** 3~5분. `apt-get download`가 서른둘을 받고 `dpkg -x`가 푼다.

- [ ] **Step 4: sysroot에 열셋과 라이브러리가 섰는지 본다**

```bash
docker run --rm tars-devcontainer bash -c '
  S=/usr/local/amd64-sysroot
  for t in eza batcat rg sd procs htop btop tree duf ncdu jq hyperfine; do
    printf "%-10s %s\n" "$t" "$([ -f $S/usr/bin/$t ] && echo ok || echo MISSING)"
  done
  printf "%-10s %s\n" fd "$([ -f $S/usr/lib/cargo/bin/fd ] && echo ok || echo MISSING)"
  for so in libgit2.so.1.9 libcrypto.so.3 libresolv.so.2 libncursesw.so.6 \
            libjq.so.1 libonig.so.5 libstdc++.so.6; do
    printf "%-18s %s\n" "$so" "$(find $S -name "$so" | head -1)"
  done'
```

**Verify:** 열셋이 `ok`, 소네임 일곱의 경로가 전부 나온다. `libresolv.so.2`가
`libc6`에서 이미 와 있다는 것을 여기서 눈으로 본다.

- [ ] **Step 5: Commit**

```bash
git add devcontainer/Dockerfile
git commit -m "Widen the sysroot with the modern layer and nineteen libraries"
```

---

## Task 1: 목록에 열세 줄을 더한다 — **이 milestone의 본체**

**Files:**
- Modify: `kernel/guest_tools.sh:123` 뒤

- [ ] **Step 1: `GUEST_TOOLS` 배열의 `usr/bin/dmesg` 줄 뒤에 넣는다**

`kernel/guest_tools.sh`의 `usr/bin/dmesg:usr/bin/dmesg` 다음 줄, 닫는 `)`
**앞에** 넣는다. **지울 것 없음.**

```bash

  # ── 층 2 · 모던 13 ─────────────────────────────────────────────────────
  # design 최종 목록의 층 2 열둘에 **btop**을 더한 것이다(사용자가 2026-09-11에
  # 요청했다). 라이브러리 열아홉이 딸려 오고, 그중 열여섯이 eza·bat 둘이
  # 데려오는 libgit2 사슬이다 — **네트워크가 없는 기계의 TLS·Kerberos·SSH
  # 스택**이고 design 결정 3이 그 대가를 명시적으로 감수했다.
  #
  # **게이트가 타이핑하는 것은 eza·fd·jq 셋뿐이다.** htop·btop·ncdu는 화면을
  # 통째로 가져가는 대화형이라 sendkey로 치면 체인이 타임아웃으로 매달린다
  # (design 실측 26 — less·top이 같은 이유로 빠져 있다). bat은 매달리지는
  # 않지만 화면에 내는 글자가 전부 다른 검사와 겹쳐서 판정을 못 만든다
  # (아래 tools/check.sh의 주석).
  usr/bin/eza:usr/bin/eza

  # 이름을 바꾸는 둘 — **결정 4**. Debian이 이름 충돌을 피하려고 바꿔 놓은
  # 것이고(design 실측 9), 우리 initrd에는 그 제약이 없다. mawk→awk와 같은
  # 자리다.
  #
  # **fd는 심볼릭 링크가 아니라 실체를 적는다.** .deb 안에서
  # usr/bin/fdfind는 ../lib/cargo/bin/fd를 가리키는 상대 링크이고, cp가
  # 따라가 주기는 하지만 sysroot 구조가 바뀌면 조용히 깨진다.
  usr/bin/batcat:usr/bin/bat
  usr/lib/cargo/bin/fd:usr/bin/fd

  usr/bin/rg:usr/bin/rg
  usr/bin/sd:usr/bin/sd
  usr/bin/procs:usr/bin/procs
  usr/bin/htop:usr/bin/htop

  # btop은 게스트에서 **libstdc++.so.6의 유일한 사용자다**(기존 50개와 층 2의
  # 나머지 열둘 전부의 DT_NEEDED를 2026-09-11에 확인했다). 이 줄을 지우는
  # 사람은 devcontainer/Dockerfile의 libstdc++6도 함께 지운다.
  #
  # 테마(/usr/share/btop/themes 63,503바이트)는 안 넣는다 — 내장 Default로
  # 돈다. btop이 UTF-8 로케일을 요구하는 것은 terminal이 LANG=C.UTF-8을
  # 넘기고 usr/lib/locale/C.utf8이 initrd에 있어서 이미 충족돼 있다(HI-M1).
  usr/bin/btop:usr/bin/btop

  usr/bin/tree:usr/bin/tree
  usr/bin/duf:usr/bin/duf
  usr/bin/ncdu:usr/bin/ncdu
  usr/bin/jq:usr/bin/jq
  usr/bin/hyperfine:usr/bin/hyperfine
```

- [ ] **Step 2: initrd를 굽고 크기와 시간을 잰다** — **`make_initrd.sh`는 안 고친다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel
  ls -l initrd.cpio
  time ./make_initrd.sh
  ls -l initrd.cpio
  gzip -dc initrd.cpio | wc -c'
```

**Expected:** 죽지 않는다(Task 0이 라이브러리 열아홉을 sysroot에 세웠으므로
`copy_lib_deps`가 소네임을 다 푼다). gzip 13.4MB → **30MB 안팎**, 푼 크기
약 78MB. `gzip -6`에 드는 시간이 얼마나 느는지를 이 자리에서 본다 —
**UT-M0 실측 15가 압축기 교체 카드를 열어 뒀고, 재기 전에는 안 쓴다.**

- [ ] **Step 3: 목록의 63개가 실제로 들어갔는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  . kernel/guest_tools.sh
  echo "list says: ${#GUEST_TOOLS[@]}"
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null > /tmp/l
  miss=0
  for e in "${GUEST_TOOLS[@]}"; do
    grep -qx "${e#*:}" /tmp/l || { echo "MISSING ${e#*:}"; miss=1; }
  done
  for l in lib/x86_64-linux-gnu/libgit2.so.1.9 lib/x86_64-linux-gnu/libstdc++.so.6 \
           lib/x86_64-linux-gnu/libresolv.so.2 lib/x86_64-linux-gnu/libonig.so.5; do
    grep -qx "$l" /tmp/l || { echo "MISSING $l"; miss=1; }
  done
  [ $miss = 0 ] && echo "all there"'
```

**Verify:** `list says: 63`과 `all there`.

- [ ] **Step 4: Commit**

```bash
git add kernel/guest_tools.sh
git commit -m "Add the modern layer of thirteen to the one list"
```

---

## Task 2: 게이트가 셋을 치고, 못 치는 둘을 정적으로 본다

**Files:**
- Modify: `tools/check.sh`

- [ ] **Step 1: 검사 1에 정적 둘을 더한다**

`tools/check.sh:123`의 `done` 다음, `INITRD_LIST=` 줄 **앞에** 넣는다.
**지울 것 없음.**

```bash
# **타이핑으로는 절대 증명할 수 없는 라이브러리 둘.** 이 둘을 쓰는 도구가
# htop·ncdu·btop뿐인데 셋 다 대화형이라 게이트가 못 친다(실측 26). 파일이
# 들어갔다는 것까지가 게이트가 이 셋에 대해 볼 수 있는 전부이고, 그 사실을
# 알고 두는 것이 낫다.
#
# 라이브러리가 아예 없는 경우는 사실 여기까지 못 온다 — copy_lib_deps가
# 소네임을 못 풀면 **빌드 때** 죽는다. 이 둘이 잡는 것은 그 다음이다:
# LIB_DEST가 바뀌었거나 cpio가 떨어뜨린 경우.
WANT+=(lib/x86_64-linux-gnu/libncursesw.so.6 lib/x86_64-linux-gnu/libstdc++.so.6)
```

- [ ] **Step 2: 화면 검사 셋을 더한다** — 음성 확인(지금의 검사 8) **앞에**

`tools/check.sh:278`의 `echo "sed rewrote a line"` 다음, `# ── 검사 8` 주석
**앞에** 넣는다. **지울 것 없음.**

```bash
# ── 검사 8: eza가 돈다 — **libgit2 사슬 열여섯** ────────────────────────
#
# **UT-M2의 심장이다.** eza·bat이 데려오는 사슬이 저장소에서 가장 길다.
#
#   eza → libgit2.so.1.9 → libssh2 → libcrypto.so.3 → libz · libzstd
#                        → libgssapi_krb5 → libkrb5 → libresolv · libcom_err
#                                                   · libkeyutils · libk5crypto
#                        → libmbedtls → libmbedx509 → libmbedcrypto
#                        → libhttp_parser
#
# 열여섯 전부를 로더가 실행 시점에 풀어야 한다(dlopen이 아니다). M1의
# `ps ax`가 libproc2→libsystemd→libcap 셋을 보던 자리를 이것이 이어받는다.
#
# 판정 글자를 `fonts`로 잡는다. 게스트 루트에 vendor/fonts가 있고, **화면
# 어느 프레임에도 그 글자가 없다** — 검사 3의 `ls`는 루트 항목만 냈고
# 타이핑한 명령줄 자체는 `eza vendor`다. 검사 둘이 같은 글자를 보면 하나가
# 죽어도 둘 다 초록일 수 있다(검사 7의 주석과 같은 이유).
echo "=== typing 'eza vendor' ==="
type_keys e z a spc v e n d o r ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "fonts"; then
  fail "eza did not list the vendor directory (did the libgit2 chain resolve?)" \
    "terminal: screen>" "error while loading"
fi
echo "eza listed a directory through the sixteen-library libgit2 chain"

# ── 검사 9: fd가 **우리가 준 이름으로** 돈다 — 결정 4 ───────────────────
#
# .deb 안에서 실체는 /usr/lib/cargo/bin/fd이고 /usr/bin/fdfind가 그것을
# 가리키는 심볼릭 링크다. guest_tools.sh가 `usr/lib/cargo/bin/fd:usr/bin/fd`로
# 넣지 않았으면 이 줄이 `Unknown command`다 — mawk→awk와 같은 자리이고,
# **initrd 안의 이름은 우리가 정한다는 결정 4를 M2에서 보는 자리다.**
#
# **인자로 vendor를 주는 것이 중요하다.** fd는 인자가 없으면 현재 디렉터리
# 아래를 전부 훑는데, 게스트의 cwd가 / 이고 거기에 /proc·/sys가 있다.
# 훑는 데 오래 걸리고 출력이 화면을 뒤덮는다 — less·top이 매달리는 것과
# 종류는 다르지만 게이트에 미치는 결과가 같다.
echo "=== typing 'fd otf vendor' ==="
type_keys f d spc o t f spc v e n d o r ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "unifont"; then
  fail "fd did not find the font under the name we gave it" \
    "terminal: screen>" "Unknown command"
fi
echo "fd ran under the name we gave it"

# ── 검사 10: jq가 돈다 — libjq → libonig ────────────────────────────────
#
# 게스트에 JSON 파일이 하나도 없고, 게이트에 파일을 만들어 넣는 것은 이
# 검사 하나를 위해 initrd를 넓히는 일이다. `--version`으로 충분한 이유는
# **이 검사가 보는 것이 파싱이 아니라 동적 링크**이기 때문이다 — libjq도
# libonig도 DT_NEEDED라 로더가 exec 시점에 둘 다 풀어야 하고, 못 풀면
# 한 글자도 안 찍고 죽는다.
#
# 버전을 `jq-1.7`로 박지 않고 `jq-[0-9]`로 보는 것은 trixie가 올라가면
# 갈릴 자리라서다. 타이핑한 명령줄은 `jq --version`이라 이 정규식과 안
# 겹친다.
echo "=== typing 'jq --version' ==="
type_keys j q spc minus minus v e r s i o n ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aqE "jq-[0-9]"; then
  fail "jq did not print its version (did libjq/libonig resolve?)" \
    "terminal: screen>" "error while loading"
fi
echo "jq loaded libjq and libonig"

# **bat은 일부러 안 친다.** 매달리지는 않지만(-P로 페이저를 끌 수 있다)
# 화면에 내는 글자가 문제다 — /etc/passwd도 /etc/group도 검사 6·7이 이미
# 본 글자이고, 헤더의 `File: ` 문자열은 바이너리 안에서 확인되지 않았다
# (2026-09-11, `strings`로 확인). **판정을 만들 수 없는 검사는 안 만든다.**
# bat이 잃는 것은 크지 않다 — 라이브러리는 eza와 같은 사슬이라 검사 8이
# 보고, 이름은 검사 1이 dest로 본다.
```

- [ ] **Step 3: 음성 확인 주석의 "넷"을 고친다**

`tools/check.sh:279-283`의 검사 8 주석에서 **지울 것**:

```
# 이유가 그것이다 — ls · ps · awk · sed 넷을 다 친 뒤에 한 번 보면 넷
# 전부의 음성 확인이 된다. UT-M0 때는 ls 하나뿐이라 바로 뒤에 있었다.
```

**넣을 것**(검사 번호도 8 → 11로 고친다):

```
# 이유가 그것이다 — ls · ps · awk · sed · eza · fd · jq 일곱을 다 친 뒤에
# 한 번 보면 일곱 전부의 음성 확인이 된다. UT-M0 때는 ls 하나뿐이라 바로
# 뒤에 있었다.
```

- [ ] **Step 4: 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** 마지막이 `PASS`. 첫 줄이
`the initrd carries the four bones and all 63 tools the list names`.
**약 3~5분**(커널이 캐시돼 있으면).

- [ ] **Step 5: Commit**

```bash
git add tools/check.sh
git commit -m "Let the gate type eza, fd and jq and watch two silent libraries"
```

---

## Task 3: `CHAINS`를 `UT-M2`로

**Files:**
- Modify: `check.sh:197`

- [ ] **Step 1: 한 줄**

**지울 것:**

```bash
  "UT-M1:./tools/check.sh"
```

**넣을 것:**

```bash
  "UT-M2:./tools/check.sh"
```

- [ ] **Step 2: Commit**

```bash
git add check.sh
git commit -m "Name the eleventh chain UT-M2"
```

---

## Task 4: 음성 확인 — 검사가 진짜인가

**커밋하지 않는다.** 코드를 일부러 뒤로 되돌렸다가 `git checkout`으로
복구한다. M2는 Zig를 한 글자도 안 건드리므로 **실측 18의 `zig-out` 함정은
이번에 없다** — 그래도 복구 뒤 체인을 한 번 돌려 초록을 확인한다.

- [ ] **Step 1: 이름 바꾸기를 되돌린다 — 검사 9가 잡아야 한다**

`kernel/guest_tools.sh`에서 `usr/lib/cargo/bin/fd:usr/bin/fd`를
`usr/lib/cargo/bin/fd:usr/bin/fdfind`로 바꾸고 체인을 돌린다.

**Expected:** **검사 1은 초록이다**(같은 배열을 읽으므로 `usr/bin/fdfind`를
찾고 그것이 거기 있다 — design 실측 24의 tautology가 여기서 다시 보인다).
**검사 9가 FAIL**하고 진단에 `Unknown command`가 뜬다.

```bash
git checkout kernel/guest_tools.sh
```

- [ ] **Step 2: libgit2 사슬을 끊는다 — 검사 8이 잡아야 한다**

`kernel/make_initrd.sh`의 `install_tool()`에서 `copy_lib_deps "$dest"`를
**eza와 bat 둘에 대해서만** 건너뛴다.

```bash
  case "$2" in
    usr/bin/eza|usr/bin/bat) ;;
    *) copy_lib_deps "$dest" ;;
  esac
```

**둘 다 건너뛰어야 하는 것이 M1이 배운 것이다**(실측 25) — 하나만 빼면
나머지 하나가 같은 사슬을 데려와서 아무것도 안 드러난다. `ps`와 `top`이
`libproc2`에 대해 같았다.

**Expected:** 검사 8이 FAIL하고 화면에
`eza: error while loading shared libraries: libgit2.so.1.9`가 뜬다.
**검사 1~7은 전부 초록으로 지나간다** — 셸 셋도 GNU도 안 건드렸으므로
실패 반경이 이번엔 좁다. 그것이 "특정 도구를 겨냥한 음성 확인"의 모양이다.

```bash
git checkout kernel/make_initrd.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Verify:** 복구 뒤 `PASS`.

---

## Task 5: 루트 게이트 + 시간 기록 — **위험 2**

- [ ] **Step 1: 백그라운드로 돌린다**

**약 22~25분 걸린다.** Bash 도구의 상한이 10분이므로 백그라운드로 돌린다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [ ] **Step 2: 결과를 읽는다**

```bash
tail -20 /tmp/gate.log; cat /tmp/gate.time
```

**Expected:** 열한 체인 **3/3**. 시간은 UT-M1의 **21분 35.63초**에서 얼마나
늘었는지로 읽는다 — initrd가 약 17MB 커지고(gzip) UT 체인이 타이핑 셋을
더했다. **잡음 ±3분 안이면 설명된 값이다.**

**`terminal` 쪽 `PASS`가 넷인 것이 정상이다** — 다섯 바이너리가 다 돌지만
`status_test.zig`만 `PASS`를 안 찍는다. **세는 것으로 판정하지 말 것.**

- [ ] **Step 3: 부팅이 느려졌는지 본다** — UT-M0 실측 15의 후속

게이트 로그에서 체인들의 부팅 시간을 본다. **1~2초 안이면 실측 15가
재현된 것이고, 그보다 크면 압축기 카드를 꺼낸다**(`CONFIG_RD_ZSTD`가 켜져
있고 UT-M1이 컨테이너에 `zstd`를 넣어 뒀다).

---

## Task 6: 문서

- [ ] **Step 1: design에 "UT-M2가 실행으로 증명한 것" 절을 더한다**

`docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`의 맨 뒤에
실측 30부터 잇는다. 최소한 이 다섯:

- **실측 30** — 사슬이 15가 아니라 16이다(`libresolv`). `libcrypto`는
  `libgit2`가 아니라 `libssh2`가 끈다. **그런데 Dockerfile은 안 고쳤다** —
  `libc6`이 이미 담고 있다.
- **실측 31** — `btop`의 값(4.01MB, `libstdc++`의 유일 사용자).
- **실측 32** — 크기와 부팅 시간의 실제 값(Task 1 Step 2 · Task 5 Step 3).
- **실측 33** — 음성 확인 둘의 결과(Task 4). **검사 1이 또 tautology였다.**
- **실측 34** — 게이트 시간.

그리고 milestone 표의 **UT-M2에 ✅**를 붙인다.

- [ ] **Step 2: `docs/decisions/project_userland_tools.md`에 M2를 더한다**

다시 캐지 말아야 할 것: 사슬 16 · `btop`과 `libstdc++`의 짝 · 게이트가
타이핑하지 않는 넷(`htop`·`btop`·`ncdu`·`bat`)과 **각각의 이유가 다르다는 것**.

- [ ] **Step 3: `MEMORY.md` · `CLAUDE.md` · `HANDOFF.md`**

`CLAUDE.md`의 "완료된 서브프로젝트" 절에서 UT의 진행 상태를 M2까지로 고치고,
**남은 것이 UT-M3(git · `vim.tiny` · 결정 8) 하나**임을 적는다.

- [ ] **Step 4: Commit**

```bash
git add docs/ MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Close UT-M2 with the modern thirteen and a sixteen-link chain"
```

---

## 이 plan이 일부러 안 하는 것

| | 왜 |
|---|---|
| `make_initrd.sh` 수정 | **고쳐야 하면 M1의 결정 7이 값을 못 낸 것이다.** 배열에 줄만 더한다 |
| `btop` 테마 넣기 | 내장 Default로 돈다. 63KB가 아까운 게 아니라 **안 쓰는 것을 안 넣는 것**이다 |
| `bat` 타이핑 | 판정 글자를 만들 수 없다(위 검사 10 뒤의 주석) |
| 압축기 교체 | **재기 전에는 안 고친다.** Task 5 Step 3이 그 판단 자리다 |
| `exa` 심볼릭 링크 | Debian이 옛 이름을 남긴 것이고 우리에겐 이유가 없다 |
| `libresolv`를 Dockerfile에 적기 | `libc6`이 담고 있다. 적으면 없는 패키지라 apt가 죽는다 |
