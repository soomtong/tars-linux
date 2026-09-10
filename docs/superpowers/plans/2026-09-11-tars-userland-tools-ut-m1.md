# UT-M1 Implementation Plan — 목록이 한 자리가 되고, 그 자리에 GNU 한 벌이 선다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 게스트에 GNU 한 벌(coreutils 36 + 별도 패키지 11)을 세운다. 그리고
그 전에 **`make_initrd.sh`가 바이너리를 다루는 모양을 목록 배열로 바꾼다**
(design 결정 7).

**Architecture:** 바이너리 목록을 `kernel/guest_tools.sh` **한 파일**로 뺀다.
`make_initrd.sh`가 그것을 source해서 배열 한 벌을 돌며 `cp`·`chmod`·
`copy_lib_deps` 셋을 하고, **`tools/check.sh`가 같은 파일을 source해서** initrd
목록을 검사한다. 목록에 한 줄을 더하면 게이트가 그 줄을 자동으로 본다 —
목록과 검사가 어긋날 자리가 구조적으로 없어진다.

**Tech Stack:** bash(sourceable 배열) · Debian `.deb`(`apt-get download`) ·
`readelf`(아키텍처 무관 의존 추적) · QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
— 특히 **결정 4 · 결정 7 · 위험 3 · 위험 4**와 최종 목록의 "층 1".

---

## 착수 전에 이 세션이 실측한 것 — **design 실측 3이 두 곳에서 불완전했다**

design 실측 3은 *"새로 필요한 라이브러리는 **둘뿐**이다 — `sed`가
`libacl1`(74KB), `ps`/`top`이 `libproc2`(237KB)"*라고 적었다. **바이너리의
`DT_NEEDED`만 보고 `.so`의 `DT_NEEDED`는 안 봤다.** 2026-09-11에 컨테이너
안에서 다시 쟀다.

```
libacl.so.1.1.2302      38,832   NEEDED: libc.so.6
libproc2.so.0.0.2      207,368   NEEDED: libsystemd.so.0 libc.so.6   ← 안 봤던 줄
libsystemd.so.0.40.0 1,131,784   NEEDED: libcap.so.2 libm.so.6 libc.so.6
```

그리고 coreutils 36개의 `DT_NEEDED` 합집합에 **`libattr.so.1`**이 있다 —
실측 3의 "나머지가 요구하는 넷"(`libpcre2-8`·`libselinux1`·`libtinfo6`·`libm`)에
없던 이름이다.

**그래서 새 라이브러리는 둘이 아니라 넷이다.**

| 새 라이브러리 | 크기 | 누가 데려오나 |
|---|---|---|
| `libacl.so.1` | 38,832 | `sed` · `cp` · `mv` |
| `libattr.so.1` | 약 20,000 | coreutils(`cp`·`mv` 계열) |
| `libproc2.so.0` | 207,368 | `ps` · `top` |
| `libsystemd.so.0` | 1,131,784 | **`libproc2`가 데려온다** |

**`libsystemd`가 lzma·zstd·gcrypt를 안 데려온다.** trixie의 libsystemd는 그
셋을 `dlopen`으로 열고 `DT_NEEDED`에는 `libcap`·`libm`·`libc`뿐이다
(`libcap`은 zsh가 이미 데려와 initrd에 있다). 저널 압축을 쓸 때만 열리는
경로이고 `ps`/`top`은 저널을 안 본다. **`copy_lib_deps`가 따라가는 사슬은
4.2MB가 아니라 1.38MB다.**

**판정: `ps`·`top`을 넣는다.** 실측 15가 "크기의 벽이 없다"를 증명했고,
`ps`는 개발용 기계에서 대체재가 없다.

**`awk`가 `.deb` 안에 없다.** `mawk` 패키지는 `/usr/bin/mawk`만 담고
`/usr/bin/awk`는 Debian의 alternatives가 postinst에서 만든다. **결정 4가
이 자리를 이미 정해 뒀다** — initrd 안의 이름은 우리가 정하므로
`usr/bin/mawk:usr/bin/awk`로 넣는다. 이것이 목록 형식이 `src:dest`여야 하는
**지금 당장의** 이유다(UT-M2의 `fd`·`bat`은 나중 이유다).

**design 최종 목록의 coreutils 35에 `uname`이 빠져 있다.** 지금 initrd에 있는
것이고 빼면 회귀다. **36개로 넣는다.**

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `kernel/guest_tools.sh` | `GUEST_TOOLS` 배열 하나. **바이너리 목록이 사는 유일한 자리** | 새로 만든다 |
| `kernel/make_initrd.sh` | 배열을 돌며 `cp`·`chmod`·`copy_lib_deps`. 손으로 쓴 26줄이 사라진다 | 고친다 |
| `devcontainer/Dockerfile` | `.deb` 여덟 + 라이브러리 넷. **UT가 이 파일을 처음 넓힌다** | 고친다 |
| `tools/check.sh` | 검사 1이 **같은 배열**을 본다. 화면 검사 셋이 는다 | 고친다 |
| `check.sh` | `CHAINS`의 `UT-M0` → `UT-M1` | 고친다(한 줄) |

---

## Task 0: Dockerfile을 넓히고 이미지를 다시 굽는다

**이 Task가 첫째인 이유:** 나머지 전부가 sysroot에 새 파일이 있다는 전제 위에
선다. 그리고 이미지 재빌드는 **네트워크를 쓰는 유일한 단계**다.

**Files:**
- Modify: `devcontainer/Dockerfile`

- [ ] **Step 1: `apt-get download` 목록에 여덟 + 넷을 더한다**

도구를 주는 `.deb` 여덟: `grep` · `findutils` · `sed` · `mawk` · `diffutils` ·
`less` · `procps` · `util-linux`(`dmesg` 하나 때문에).
라이브러리 넷: `libacl1` · `libattr1` · `libproc2-0` · `libsystemd0`.

**`apt-get download`는 의존을 안 따라간다** — 이 목록은 언제나 명시적이다
(그 성질이 지금 값을 낸다: `libsystemd0`을 손으로 적지 않으면
`make_initrd.sh`가 소네임을 찍고 즉시 죽는다).

- [ ] **Step 2: `zstd`를 함께 더한다** — HANDOFF이 남긴 결정

UT-M0의 크기 스파이크가 **세 압축기 중 하나를 못 쟀다**(컨테이너에 없어서).
UT-M2가 27MB를 더하면 그 질문이 다시 살아나는데, 그때 재려면 이미지를 또
구워야 한다. **한 줄이고 게이트에 비용이 0이다** — 어떤 빌드 단계도 이것을
부르지 않는다. `xz-utils`가 이미 같은 층에 있다.

- [ ] **Step 3: 이미지를 굽고 sysroot를 확인한다**

```bash
docker build -t tars-devcontainer devcontainer/
docker run --rm tars-devcontainer bash -c '
  S=/usr/local/amd64-sysroot
  for t in grep find xargs sed mawk diff cmp less ps top dmesg; do
    printf "%-8s %s\n" "$t" "$([ -f $S/usr/bin/$t ] && echo ok || echo MISSING)"
  done
  for so in libacl.so.1 libattr.so.1 libproc2.so.0 libsystemd.so.0; do
    printf "%-18s %s\n" "$so" "$(find $S -name "$so*" | head -1)"
  done
  which zstd'
```

**Verify:** 열한 개가 `ok`, 라이브러리 넷의 경로가 나오고, `zstd`가 있다.

---

## Task 1: 목록을 한 파일로 빼고 `make_initrd.sh`를 그것 위에 다시 세운다 — **결정 7**

**이 Task가 이 milestone의 본체다.** 도구를 더하는 것은 그 다음이다.

**Files:**
- Create: `kernel/guest_tools.sh`
- Modify: `kernel/make_initrd.sh`

- [ ] **Step 1: `kernel/guest_tools.sh`를 만든다**

`GUEST_TOOLS` 배열 하나. 형식은 `sysroot 안의 경로:initrd 안의 경로`.
`SYSROOT`·`WORKDIR`을 참조하지 않는다 — **데이터만 있는 파일**이라
`tools/check.sh`가 부작용 없이 source할 수 있다.

- [ ] **Step 2: `make_initrd.sh`에 `install_tool()`을 만들고 배열을 돌린다**

손으로 쓴 자리(fish·bash·zsh·cat·uname·mkdir·sleep·ls의 `cp` 8줄 +
`chmod` 4줄 + `copy_lib_deps` 9줄 = **26줄**)를 지우고 루프 하나로 바꾼다.

`install_tool()`이 하는 것 넷: 원본이 없으면 **어느 패키지를 Dockerfile에
더하라고 말하며 죽고**, `mkdir -p`, `cp`, `chmod 0755`, `copy_lib_deps`.

**`copy_lib_deps`가 이미 있는 소네임을 건너뛰므로 순서는 상관없다.**

**Verify:** initrd가 만들어지고 목록에 49개가 다 있다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd kernel && ./build.sh) && (cd init && zig build) \
  && (cd terminal && ./prepare.sh) && (cd kernel && ./make_initrd.sh)
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | grep -c "^usr/bin/"
  stat -c%s kernel/initrd.cpio'
```

---

## Task 2: 게이트의 정적 검사가 **같은 배열**을 본다

**Files:**
- Modify: `tools/check.sh`

- [ ] **Step 1: 검사 1이 `GUEST_TOOLS`를 source해서 dest 전부를 확인한다**

뼈대 넷(`bin/sh`·`tmp`·`etc/passwd`·`etc/group`)은 배열에 없으므로 그대로
literal로 둔다. 그 뒤에 배열의 `dest`를 전부 더한다.

**`./` 접두사를 붙이지 않는다**(UT-M0 실측 16). 그 자리에 이미 주석이 있다.

**Verify:** 체인이 `the initrd carries ... and 49 tools from the list`를 찍고
부팅으로 넘어간다.

---

## Task 3: 화면에서 실제로 돈다 — 검사 셋

**이 Task가 위험 3을 정면으로 본다.** 목록 검사는 "파일이 들어갔다"까지이고,
`error while loading shared libraries`는 **게스트가 그 명령을 처음 칠 때**
난다.

**Files:**
- Modify: `tools/check.sh`

- [ ] **Step 1: `ps ax` — 새 사슬 중 가장 긴 것이 런타임에 풀렸다**

`ps` → `libproc2.so.0` → `libsystemd.so.0` → `libcap.so.2`. **이 세 층이
`dlopen`이 아니라 로더가 부팅 시점에 다 풀어야 하는 것들이고, 못 풀면 화면에
로더 에러가 그대로 뜬다.** 판정은 화면 줄에 `/terminal`이 있는가(감독자가
띄운 프로세스가 `ps`에 보인다).

- [ ] **Step 2: `awk /root/ /etc/passwd` — 결정 4의 이름 바꾸기가 실제로 먹었다**

**`mawk`를 `awk`로 넣지 않았으면 이 줄이 `Unknown command`다.** 따옴표 없는
`awk` 프로그램이라 `sendkey`로 칠 수 있다(패턴만 있고 액션이 없으면 맞는 줄을
출력한다). 판정은 `root:x:0:0:root`.

- [ ] **Step 3: `sed s/root/tars/ /etc/group` — `libacl` 사슬**

**출력이 저장소 어디에도 없는 문자열이어야 한다.** `sed -n 1p /etc/group`은
`root:x:0:`을 내는데 그것은 `/etc/passwd`의 앞부분과 겹쳐서 위의 `awk` 검사와
구분이 안 된다. 치환을 시키면 출력이 `tars:x:0:`이고 **그 글자를 만들 수 있는
것은 `sed`뿐이다.**

- [ ] **Step 4: 기존 음성 검사(`Unknown command`)를 셋 뒤로 옮긴다**

지금 검사 4가 `ls` 바로 뒤에 있다. 셋을 다 친 **뒤에** 한 번 보면 넷 전부의
음성 확인이 된다.

**Verify:** 체인 단독 실행이 `PASS`.

---

## Task 4: `CHAINS`를 `UT-M1`로

**Files:**
- Modify: `check.sh`

- [ ] **Step 1: `"UT-M0:./tools/check.sh"` → `"UT-M1:..."`**

`CHAINS` 배열이 **서브프로젝트의 실제 상태를 가장 정확하게 말하는 자리**다
(CLAUDE.md).

---

## Task 5: 음성 확인 — 검사가 진짜인가

**코드를 일부러 뒤로 되돌리는 Task다. 반드시 원상복구한다.**

- [ ] **Step 1: `guest_tools.sh`에서 `usr/bin/ps` 한 줄을 지우고 체인을 돌린다**

**기대:** 검사 1(정적)이 **부팅 전에** `usr/bin/ps is missing from the initrd`로
죽는다. 배열과 검사가 같은 파일을 보므로 이 실패는 논리적으로 안 날 수도
있다 — **그러면 그것이 발견이다**(검사가 목록을 그대로 되읽는 tautology).
아래 Step 2가 그 경우의 진짜 검사다.

- [ ] **Step 2: `install_tool` 루프에서 `copy_lib_deps` 한 줄을 지운다**

**기대:** `make_initrd.sh`는 성공하고, 게스트가 `ps ax`를 칠 때
`error while loading shared libraries: libproc2.so.0`이 뜬다. **이것이 위험
3의 실제 모양이고, 검사 6이 잡아야 하는 것이다.**

- [ ] **Step 3: `git checkout`으로 되돌리고 `rm -rf init/zig-out`**

**UT-M0 실측 18** — 되돌려도 `zig-out`이 안 따라온다.

---

## Task 6: 루트 게이트 + 시간 기록 — **위험 2**

- [ ] **Step 1: 백그라운드로 돌린다(약 20~25분)**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

기준선은 **21분 09.60초**(UT-M0, 열한 체인).

- [ ] **Step 2: 위험 4를 확인한다 — 열한 체인 전부**

UT-M0에서 `/etc/passwd` 한 줄이 CM 체인을 깼다. **이번엔 뼈대를 안 건드리므로
같은 종류는 안 온다**는 것이 design의 예측이다 — 게이트가 그것을 판정한다.

---

## Task 7: 문서

- [ ] design의 `Status:`와 "UT-M1이 실행으로 증명한 것" 절
- [ ] `docs/decisions/project_userland_tools.md`
- [ ] `MEMORY.md` · `CLAUDE.md` · `HANDOFF.md`
