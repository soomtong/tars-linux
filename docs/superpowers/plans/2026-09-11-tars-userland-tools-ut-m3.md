# UT-M3 Implementation Plan — git이 서고, 이름 넷을 우리가 건다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 게스트에서 `git init` → `add` → `commit` → `log`가 한 번에 돌고,
전역 설정이 `/config`에 남는다(design 결정 8). 편집기는 `vim.tiny`이고
이름은 `vim`·`vi`·`editor` 셋이다.

**Architecture:** **M1·M2와 같다** — `kernel/guest_tools.sh`에 줄 **둘**을
더하고 `devcontainer/Dockerfile`을 넓힌다. 다른 것은
**`kernel/make_initrd.sh`를 이번엔 고친다**는 점이고, 더하는 것이 바이너리가
아니라 **링크 넷과 트리 하나**라서다(`usr/bin/vi` · `usr/bin/pager` ·
`usr/bin/editor` · `/.gitconfig` · git 템플릿). 그 파일이 자기 자리를 그렇게
갈라 놓고 있다 — *"뼈대(결정 6)와 특수 트리는 여전히 손으로 쓴다."*
**M2의 성적표("make_initrd.sh를 한 글자도 안 고쳤다")를 깨는 것이 아니라,
M2가 더한 것이 바이너리뿐이었다는 뜻이다.**

**Tech Stack:** bash(sourceable 배열) · Debian `.deb`(`apt-get download`) ·
`readelf`(아키텍처 무관 의존 추적) · QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
— 특히 **결정 4(이름은 우리가 정한다) · 결정 5(네트워크 헬퍼 일곱을 뺀다) ·
결정 6(뼈대 넷) · 결정 8(`/.gitconfig` → `/config/gitconfig`) · 실측 2·7·8**,
그리고 **실측 24·26·33**(정적 검사는 tautology다 · 게이트가 타이핑하면 안
되는 도구가 있다).

---

## 착수 전에 이 세션이 실측한 것 — **열 가지, 넷이 계획을 바꿨다**

HANDOFF이 "UT-M3 착수 전에 **반드시 먼저 할 것**"으로 지목한 폐포 재기부터
했다. **M1이 그것을 안 해서 라이브러리 둘을 놓쳤고 M2가 30초 들여 막았다.**
이번에는 재는 데서 끝나지 않고 **게스트에서 직접 쳐 봤다** — 부팅 프로브
셋이 계획을 넷 바꿨다.

### 1. **새 라이브러리가 0이다** — design의 그 문장이 처음 맞았다

`.deb` 둘을 풀고 `copy_lib_deps`와 **같은 규칙**(`readelf -d`의 `DT_NEEDED`를
`.so`까지 재귀, `find_in_sysroot`의 디렉터리 넷)으로 쟀다.

```
git        libpcre2-8.so.0 · libz.so.1 · libc.so.6                이미 있다
vim.tiny   libm · libtinfo · libselinux · libacl · libc           이미 있다
MISSING: 0
```

`libz`는 M2의 `libgit2` 사슬이, `libacl`은 `sed`가, `libselinux`는 fish가
이미 데려와 있다. **design의 "층 3은 새 라이브러리가 없다"가 M1·M2에서는
두 번 다 틀렸고 여기서 처음 맞았다** — 그래도 **재고 나서 알았다**는 것이
요지다. 맞는 날과 틀린 날은 재기 전에 구별되지 않는다.

### 2. 크기와 시간

| | M2 | M3 | 차이 |
|---|---|---|---|
| initrd gzip | 32,007,022 | **34,857,872** | +2,850,850 |
| initrd 푼 것 | 84,417,024 | **90,291,712** | +5,874,688 |
| `make_initrd.sh` 전체 | 3.449초 | **3.656초** | +0.2초 |
| 프롬프트까지 | 2.24~2.45초 | **약 3초**(1초 해상도) | — |

**`GUEST_MEM=512`가 이 수를 미리 보고 고른 값이었다**(M2 실측 34). 푼 것이
90MB이고 512MiB 안이라 여유가 넉넉하다 — 256을 골랐으면 여유가 165MB였다.

### 3. `/usr/lib/git-core`는 안 넣어도 된다 — **부팅으로 증명했다**

design 실측 7은 "168개 중 대부분은 `git` 자신에 대한 **하드링크**"라고
적었다. 실제로는 **심볼릭 링크 141 + 실체 26**이고(trixie 2.47.3), 실체 26
중 큰 것 일곱 약 16MB가 결정 5가 뺀 네트워크 헬퍼다. **결론은 같고 이유의
모양만 다르다.**

그리고 **그 트리를 통째로 안 넣고도** `init`·`add`·`commit`·`log`·`status`가
게스트에서 전부 돌았다 — 전부 `git` 바이너리 안의 builtin이다.

### 4. **신원이 없으면 commit이 죽는다 — `user.email` 하나가 필수다**

```
root@(none) /t/r (main)# git commit -m one
Author identity unknown
*** Please tell me who you are.
fatal: unable to auto-detect email address (got 'root@(none).(none)')
```

호스트 이름이 `(none)`이라 자동 감지가 bogus로 판정된다. **이름은 필요
없다** — `/etc/passwd`의 gecos에서 `root`가 나오고 그것은 implicit이어도
허용된다(UT-M0의 뼈대가 여기서 값을 낸다). 그래서 게이트가 치는 것은
`user.email` 하나이고, 커밋의 작성자는 **`root <tars>`**가 된다 — **한 줄이
뼈대(`/etc/passwd`)와 결정 8(`/config/gitconfig`)을 동시에 증명한다.**

### 5. **결정 8이 실제로 돈다**

```
root@(none) /t/r (main)# git config --global user.email tars
root@(none) /t/r (main)# cat /config/gitconfig
[user]
    email = tars
```

`HOME=/` → `/.gitconfig` → `config/gitconfig`. git이 심볼릭 링크를 풀고
그쪽에 락을 잡아 쓴다. **게이트에는 설정 디스크가 없으므로 `/config`는
initrd의 빈 디렉터리(tmpfs)이고, 이 검사가 증명하는 것은 "링크가 풀려
`/config`에 쓰인다"까지다.** 그 디스크가 부팅 사이에 파일을 지킨다는 것은
CP 체인이 `tars.conf`로 이미 증명한 **같은 마운트**의 성질이다 — 알고 둔다.

### 6. **Debian git은 페이저와 편집기를 alternatives 이름으로 부른다**

게스트에게 직접 물었다.

```
root@(none) ~# git var -l
GIT_EDITOR=editor        GIT_SEQUENCE_EDITOR=editor        GIT_PAGER=pager
```

`pager`도 `editor`도 Debian alternatives가 **postinst에서** 만드는 링크라
`dpkg -x`로 푼 sysroot에 없다. 없을 때 무슨 일이 나는지도 봤다.

```
root@(none) /t/r (main)# git log
error: cannot run pager: No such file or directory
fatal: unable to execute pager 'pager'
```

**매달리는 것이 아니라 죽는다** — 그래서 게이트는 안 깨지고 사람만 깨진다.
`git log`·`git diff`·`git branch -a`가 전부 이 경로이고, `-m` 없는
`git commit`과 `git rebase -i`가 `editor` 경로다. **`mawk`→`awk`와 같은
종류(결정 4)인데, 이름을 우리가 고른 것이 아니라 git 바이너리가 컴파일
타임에 박아 뒀다는 점만 다르다.** 링크 둘로 닫는다.

### 7. 템플릿 26,140바이트 — 넣는다

없으면 `git init`이 **매번** `warning: templates not found in
/usr/share/git-core/templates`를 찍는다. **btop 테마를 뺀 판단과 다른 이유는
쓰임이다** — 저쪽은 안 쓰는 것이고 이쪽은 `git init`이 매번 쓴다. 개발용이라
부르는 기계가 `git init`마다 경고를 내는 것은 고장으로 보인다.

### 8. **긴 출력의 첫 줄은 화면 프레임에 안 남는다** — 판정을 바꿨다

`vi --version`을 치고 `VIM - Vi IMproved`를 찾았는데 **프레임 어디에도
없었다**(0회). 출력 약 50줄이 한 번에 와서 첫 줄이 **프레임이 그려지기 전에**
스크롤로 사라진다.

**판정은 출력의 첫 줄이 아니라 마지막까지 남는 줄로 잡는다** — `vi --version`
의 마지막 줄인 `Linking: gcc`다. 이 저장소에 없던 교훈이고, `dmesg`를 안
치는 이유(출력이 화면을 뒤덮는다)의 **뒷면**이다.

### 9. **sendkey에는 대문자가 없다**

`git var GIT_PAGER`를 치니 변수 이름이 **통째로 안 쳐졌다**(`git var  `).
대문자는 `shift-g`처럼 보내야 하고 우리 체인은 그것을 쓴 적이 없다.
**체인이 칠 명령은 전부 소문자여야 한다** — 아래 검사 열둘~열여섯이 그렇다.

### 10. fish 프롬프트가 저장소 안에서 길어진다

```
root@(none) /t/r (main)#           ← 저장소 안
root@(none) /t/r (main) [128]#     ← 직전 명령이 실패한 뒤
```

**UT-M0이 `/etc/passwd`로 프롬프트를 네 글자 늘려 CM 체인을 깼던 것과 같은
종류다**(실측 17). 이번엔 안 깨진다 — 프롬프트 폭에 기대는 자리는
`copy/check.sh`의 `col 20` 하나뿐이고 **CM 체인은 저장소 안으로 들어가지
않는다.** UT 체인만 들어가고, UT 체인은 열을 안 센다.

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `devcontainer/Dockerfile` | `apt-get download`에 **`git` · `vim-tiny` 둘**. 라이브러리는 **0** | 고친다 |
| `kernel/guest_tools.sh` | `GUEST_TOOLS`에 **두 줄**(`git` · `vim.tiny`→`vim`) | 고친다 |
| `kernel/make_initrd.sh` | 링크 넷(`vi` · `pager` · `editor` · `.gitconfig`) + 템플릿 트리 | **고친다** |
| `tools/check.sh` | 검사 1에 정적 다섯 + **화면 검사 다섯**(git 넷 + vi) | 고친다 |
| `check.sh` | `CHAINS`의 `UT-M2` → `UT-M3` | 고친다(한 줄) |

---

## Task 0: Dockerfile을 넓히고 이미지를 다시 굽는다

**Files:** Modify `devcontainer/Dockerfile`

- [ ] **Step 1: 주석을 먼저 더한다** — 왜 라이브러리가 0인지

`ENV AMD64_SYSROOT=` 줄 **앞에** UT-M3 절을 잇는다. 새 소네임이 하나도 없다는
것과 `/usr/lib/git-core`를 안 쓰는 이유를 적는다(실측 1·3).

- [ ] **Step 2: `hyperfine:amd64 \` 뒤에 두 줄**

```dockerfile
        git:amd64 \
        vim-tiny:amd64 \
```

- [ ] **Step 3: 굽는다**

```bash
docker build -t tars-devcontainer devcontainer/
```

**Expected:** `.deb` 둘이 더 받아진다(git 8.9MB · vim-tiny 776KB).

- [ ] **Step 4: sysroot에 둘이 섰는지 본다**

```bash
docker run --rm tars-devcontainer bash -c '
  S=/usr/local/amd64-sysroot
  for p in usr/bin/git usr/bin/vim.tiny; do
    printf "%-18s %10s\n" "$p" "$(stat -c%s $S/$p 2>/dev/null || echo MISSING)"; done
  du -sb $S/usr/share/git-core/templates'
```

**Verify:** 4,082,768 · 1,761,704 · 26,140.

- [ ] **Step 5: Commit**

```bash
git add devcontainer/Dockerfile
git commit -m "Widen the sysroot with git and vim.tiny and no new libraries"
```

---

## Task 1: 목록에 두 줄을 더한다

**Files:** Modify `kernel/guest_tools.sh`

- [ ] **Step 1: `usr/bin/hyperfine` 뒤, 닫는 `)` 앞에 층 3 절을 넣는다**

```bash
  usr/bin/git:usr/bin/git
  usr/bin/vim.tiny:usr/bin/vim
```

주석에 적을 것 셋: **새 라이브러리가 0이라는 것**(실측 1) ·
**`/usr/lib/git-core`를 안 넣는 이유**(실측 3) · **`vi`는 여기가 아니라
`make_initrd.sh`가 링크로 건다는 것**(줄을 둘 적으면 1.76MB 사본이 두 벌
생긴다).

- [ ] **Step 2: Commit**

```bash
git add kernel/guest_tools.sh
git commit -m "Add git and vim.tiny to the one list"
```

---

## Task 2: 링크 넷과 템플릿 트리 — **결정 4·6·8**

**Files:** Modify `kernel/make_initrd.sh`

- [ ] **Step 1: `ln -sf ../usr/bin/bash "$WORKDIR/bin/sh"` 뒤에 잇는다**

```bash
ln -sf vim "$WORKDIR/usr/bin/vi"
ln -sf less "$WORKDIR/usr/bin/pager"
ln -sf vim "$WORKDIR/usr/bin/editor"
ln -sf config/gitconfig "$WORKDIR/.gitconfig"

mkdir -p "$WORKDIR/usr/share/git-core"
cp -r "$SYSROOT/usr/share/git-core/templates" "$WORKDIR/usr/share/git-core/"
```

각 줄이 왜 있는지를 주석으로 적는다 — `vi`(사본 둘을 안 만든다) ·
`pager`/`editor`(실측 6, **게스트가 직접 답한 이름**) · `.gitconfig`
(결정 8, 상대 경로, 디스크가 없을 때의 폴백) · 템플릿(실측 7).

- [ ] **Step 2: 구워서 링크가 링크로 담겼는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./make_initrd.sh && ls -l initrd.cpio
  gzip -dc initrd.cpio | cpio -itv 2>/dev/null | grep -E "usr/bin/(vi|pager|editor) |gitconfig|usr/bin/(git|vim)$"'
```

**Verify:** 링크 넷이 `lrwxrwxrwx`이고 `usr/bin/git` 4,082,768 ·
`usr/bin/vim` 1,761,704. gzip 약 34.9MB.

- [ ] **Step 3: Commit**

```bash
git add kernel/make_initrd.sh
git commit -m "Link vi, pager, editor and the global gitconfig into place"
```

---

## Task 3: 게이트가 git을 친다 — 검사 다섯

**Files:** Modify `tools/check.sh`

- [ ] **Step 1: 검사 1에 정적 다섯을 더한다**

`WANT+=(lib/...libncursesw...)` 줄 뒤에 잇는다. 배열이 안 보는 것들이다 —
링크 셋과 `.gitconfig`, 그리고 템플릿 트리의 잎 하나.

```bash
WANT+=(usr/bin/vi usr/bin/pager usr/bin/editor .gitconfig
       usr/share/git-core/templates/info/exclude)
```

- [ ] **Step 2: 화면 검사 다섯을 검사 11(음성 확인) 앞에 넣는다**

치는 순서와 판정 글자. **전부 소문자다**(실측 9).

| | 치는 것 | 판정 | 무엇을 보나 |
|---|---|---|---|
| 12 | `cd /tmp` · `git init -b main r` | `Initialized empty` | git이 돈다 · **`/tmp`(M0의 뼈대)가 쓸 수 있다** · 템플릿이 있다 |
| 13 | `git config --global user.email tars` · `cat /config/gitconfig` | `email = tars` | **결정 8** — 링크가 `/config`로 풀린다 |
| 14 | `cd r` · `touch a` · `git add a` · `git commit -m one` | `root-commit` | add→commit이 돈다. **git만 만들 수 있는 글자다** |
| 15 | `git --no-pager log` | `Author: root <tars>` | 한 줄이 **뼈대(`/etc/passwd`의 gecos)와 결정 8을 함께** 증명한다 |
| 16 | `vi --version` | `Linking: gcc` | vim.tiny가 **우리가 준 이름으로** 돈다. 첫 줄이 아니라 **마지막 줄**을 본다(실측 8) |

`-b main`을 주는 이유는 기본 브랜치 이름 힌트 다섯 줄을 안 만들기
위해서다. `--no-pager`를 주는 이유는 `pager`가 이제 `less`이고 **less가
화면을 가져가면 체인이 매달리기** 때문이다(실측 6 · design 실측 26).

- [ ] **Step 3: 음성 확인 주석의 "일곱"을 고친다**

`ls · ps · awk · sed · eza · fd · jq` → **`git`과 `vi`를 더해 아홉**.

- [ ] **Step 4: 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** 마지막이 `PASS`, 첫 줄이
`the initrd carries the four bones and all 65 tools the list names`.

- [ ] **Step 5: Commit**

```bash
git add tools/check.sh
git commit -m "Let the gate commit to a repository and ask vi its version"
```

---

## Task 4: `CHAINS`를 `UT-M3`으로

- [ ] **Step 1:** `check.sh`의 `"UT-M2:./tools/check.sh"` → `"UT-M3:..."`
- [ ] **Step 2:** `git commit -m "Name the eleventh chain UT-M3"`

---

## Task 5: 음성 확인 — 검사가 진짜인가

**커밋하지 않는다.** 되돌렸다가 `git checkout`으로 복구한다. **Zig를 한
글자도 안 건드리므로 실측 18의 `zig-out` 함정은 이번에도 없다.**

- [ ] **Step 1: `.gitconfig` 링크를 뺀다 — 검사 13이 잡아야 한다**

`make_initrd.sh`의 그 한 줄을 지운다. **검사 1이 `.gitconfig`를 못 찾고
부팅 전에 죽을 것이다** — 이번에는 정적 검사가 tautology가 **아니다**(배열이
아니라 literal이라서). 그 차이를 보는 것이 이 확인의 값이다.

- [ ] **Step 2: `pager` 링크를 뺀다 — 아무도 안 잡는 것을 본다**

**검사 1의 literal을 함께 지우고** 돌린다. **체인은 초록이다** — 게이트가
`--no-pager`로 치기 때문이다. **게이트가 못 보는 자리를 손으로 확인한다**:
프로브에서 `git log`가 `cannot run pager`로 죽는 것을 이미 봤다(실측 6).
**알고 두는 것이 낫다.**

- [ ] **Step 3: git의 `copy_lib_deps`를 건너뛴다 — 검사 12가 잡아야 한다**

`install_tool`에서 `usr/bin/git`에만 건너뛴다(M1 실측 25의 처방 — 겨냥한
것만).

**Expected:** 검사 12가 FAIL하고 화면에
`git: error while loading shared libraries`가 뜬다. **검사 1~11은 초록이다.**

```bash
git checkout kernel/make_initrd.sh tools/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash tools/check.sh
```

---

## Task 6: 루트 게이트 + 시간 기록 — **위험 2**

- [ ] **Step 1: 백그라운드로**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [ ] **Step 2:** `tail -20 /tmp/gate.log; cat /tmp/gate.time`

**Expected:** 열한 체인 **3/3**. 기준선은 UT-M2의 **23분 02.73초**이고
initrd가 gzip으로 2.85MB 커졌다(M2는 18.6MB가 커져 +1분 27초였다). UT 체인이
타이핑을 약 150글자 더한다. **잡음 ±3분 안이면 설명된 값이다.**

**`terminal` 쪽 `PASS`가 넷인 것이 정상이다.**

---

## Task 7: 문서 — **서브프로젝트가 닫힌다**

- [ ] **Step 1: design** — "UT-M3이 실행으로 증명한 것"(실측 38~)을 잇고,
  milestone 표의 **UT-M3에 ✅**, 맨 위 `Status:`를 **완료**로 고친다.
  실측 7("168개는 하드링크")과 최종 목록의 층 3 문장을 **정정**한다.
- [ ] **Step 2: `docs/decisions/project_userland_tools.md`에 M3를 더한다.**
  다시 캐지 말 것: alternatives 이름 셋(`pager`·`editor`·`awk`) ·
  git-core를 안 넣는다 · `user.email` 하나가 필수 · 긴 출력의 첫 줄은 프레임에
  안 남는다 · sendkey에 대문자가 없다.
- [ ] **Step 3: `MEMORY.md` · `CLAUDE.md` · `HANDOFF.md`** — UT를 **완료**로
  옮기고 다음 후보를 적는다(RM이 남긴 여섯 + UT가 남긴 비목표).
- [ ] **Step 4: Commit**

```bash
git add docs/ MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Close Userland Tools with git standing on four links"
```

---

## 이 plan이 일부러 안 하는 것

| | 왜 |
|---|---|
| `/usr/lib/git-core` 넣기 | 실체 26 중 일곱이 네트워크 헬퍼이고, 나머지는 builtin이라 **없어도 돈다**(실측 3) |
| 네트워크 헬퍼 일곱 | design 결정 5. `# CONFIG_NET is not set`인 기계에서 한 줄도 안 돈다 |
| `/config` 디스크를 UT 체인에 붙이기 | 부팅이 하나 더 는다. `/config`가 부팅 사이를 지킨다는 것은 **CP 체인이 같은 마운트로 이미 증명**했다 |
| 게이트가 `vi`를 **열기** | 대화형이라 매달린다(less·top·htop·btop·ncdu와 같다). `--version`까지가 볼 수 있는 전부다 |
| `git log`를 페이저 없이 치지 **않기** | 그것이 사람이 치는 모양이지만 less가 화면을 가져간다. 게이트는 `--no-pager`로 친다 |
| `git-delta` · `neovim` | design 비목표 4·5. 사용자가 고른 목록에 없다 |
| 압축기 교체 | M0·M2가 두 번 안 썼다. 이번엔 gzip이 2.85MB 늘 뿐이다 |
