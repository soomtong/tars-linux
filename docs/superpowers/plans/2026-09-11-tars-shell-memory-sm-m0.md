# SM-M0 Implementation Plan — 도구 둘이 서고, 훅은 아직 없다

> **완료: 2026-09-11.** Task 일곱 전부. **이 plan이 세 군데에서 틀렸고 지우지
> 않고 그 자리에 적어 두었다** — 각 Task 안의 `⚠ plan이 틀렸다` 블록을 볼 것.
> 요약:
>
> 1. **Task 3의 `zoxide query terminfo`가 영원히 못 찾는다.** zoxide는
>    마지막 키워드가 경로의 **마지막 컴포넌트**와 맞아야 한다. `terminfo x`로
>    고쳤다.
> 2. **Task 5 되돌림 2의 예상이 반대였다.** "검사 18은 거짓말하고 맨 뒤
>    그물이 잡는다"가 아니라 **체인 전체가 PASS**했다 — 그물이 `grep -q`의
>    SIGPIPE와 `pipefail` 때문에 **쓰인 날부터 죽어 있었다.** 이것이 이
>    milestone에서 가장 값진 발견이고 **새 도구와 아무 상관이 없다.**
> 3. **Task 2의 gzip 증가 예측 "+2MB 안쪽"이 살짝 빗나갔다**(+2,292,528).
>    푼 크기는 312바이트 차이로 맞았다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** `zoxide`와 `fzf`를 게스트에 세운다. **훅은 안 건다** — 씨앗 rc는 한
글자도 안 바뀌고, 사람이 `zoxide`·`fzf`를 **직접 이름으로 불러서** 둘이 도는
것까지가 이 milestone이다.

**Architecture:** 새 파일이 하나도 없다. 고치는 파일이 셋이고 각각 한 가지
일만 한다 — `devcontainer/Dockerfile`이 `.deb` 둘을 sysroot로 받고,
`kernel/guest_tools.sh`가 그 둘을 initrd 목록에 얹고(**`make_initrd.sh`는 한
글자도 안 고친다** — UT-M1 결정 7), `tools/check.sh`가 게스트에서 둘을
타이핑한다. **Zig 코드를 한 줄도 안 건드린다.**

**Tech Stack:** Debian `.deb`(trixie) · bash(게이트 체인) · QEMU monitor
`sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md`
— 특히 **실측 2(새 라이브러리가 0이다) · 실측 7(`--filter`가 TUI 함정을 비켜
간다) · 실측 15(zoxide가 경로를 정규화한다) · 결정 7(fzf 통합은 바이너리
내장을 쓴다) · 결정 8(게이트를 둘로 나눈다) · Milestone 절의 "M0이 훅 없이 한
단계인 이유"**.

그리고 `kernel/guest_tools.sh`의 머리 주석 전체. **그 파일이 자기 형식과 "지울
때 보아야 할 것"을 스스로 적고 있다.**

---

## 이 milestone을 지배하는 사실 하나

> **판정 글자가 타이핑한 명령줄에 있으면, 그 검사는 도구가 죽어도 초록이다.**

UT는 이 함정을 세 번 만났다. `bat`은 **낼 수 있는 글자가 전부 다른 검사와
겹쳐서 검사를 아예 못 만들었고**(UT design 실측 26), 정적 목록 검사는
**목록과 같은 파일을 봐서 tautology**였다(UT-M1).

SM-M0의 도구 둘은 그 함정에 특히 취약하다. **둘 다 경로를 찍는 도구**이고,
경로는 우리가 방금 타이핑한 것이기 때문이다.

| 순진한 프로브 | 왜 가짜인가 |
|---|---|
| `zoxide add /tmp` → `zoxide query tmp` → `/tmp`을 찾는다 | `/tmp`은 프롬프트에도 있고 검사 12가 이미 쳤다 |
| `fzf --filter=zshrc --walker-root=/config` | 이 체인엔 디스크가 없어 `/config`가 **빈 디렉터리**다 |
| `fzf --filter=description …` → `description`을 찾는다 | **타이핑한 줄에 그 글자가 있다** |

**처방 둘.**

1. **fzf:** 검색어와 판정 글자를 **다르게** 한다 — `descr`을 치고
   `templates/description`을 본다.
2. **zoxide:** `..`를 지나는 경로를 친다 — zoxide가 **정규화해서** 저장하므로
   (design 실측 15) DB가 돌려주는 글자는 화면의 다른 어디에도 없다.

**Task 5의 음성 확인이 이 둘을 실제로 깨뜨려 본다.**

---

## 파일 구조 — 무엇이 무엇을 책임지나

| 파일 | 이 milestone에서 하는 일 | 줄 수 |
|---|---|---|
| `devcontainer/Dockerfile` | `.deb` 둘을 amd64 sysroot에 푼다 | **+2** |
| `kernel/guest_tools.sh` | 그 둘을 initrd 목록에 얹는다 | +2 (주석 포함 약 +30) |
| `tools/check.sh` | 게스트에서 둘을 타이핑한다(검사 17·18) | 약 +60 |
| `kernel/make_initrd.sh` | **안 고친다** | 0 |
| `init/` · `terminal/` | **안 고친다** | 0 |

**`make_initrd.sh`가 0인 것이 이 milestone의 성적표다** — UT-M2가 같은 것을
증명했고(모던 열셋을 더하면서 한 글자도 안 고쳤다), M0은 그 구조가 **바깥에서
온 새 도구에도** 적용되는지를 본다.

---

## Task 1: `.deb` 둘을 sysroot에 들인다

**Files:**
- Modify: `devcontainer/Dockerfile:180`(`vim-tiny:amd64 \`) **바로 뒤**

- [x] **Step 1: 고치기 전 상태를 기록한다**

```bash
cd /Users/dp/Repository/tars-linux
grep -n "vim-tiny:amd64" devcontainer/Dockerfile
stat -f "%z" kernel/initrd.cpio          # 기준선: 34,869,668
zcat -f kernel/initrd.cpio | wc -c       # 기준선: 90,329,088
```

**기대:** `vim-tiny:amd64 \`가 한 줄 나온다. 크기 둘을 적어 둔다 — Task 2가
이 수와 비교한다.

- [x] **Step 2: Dockerfile에 두 줄을 넣는다**

`vim-tiny:amd64 \` 줄 **바로 뒤**에 넣는다.

**넣을 것:**

```dockerfile
        zoxide:amd64 \
        fzf:amd64 \
```

**자리에 뜻이 있다.** 이 목록은 `guest_tools.sh`의 층 순서를 따라간다 —
층 3(`git`·`vim-tiny`) 뒤가 SM이 더하는 층이고, 라이브러리 목록(`libgit2-1.9`
부터)보다 **앞**이다. 라이브러리 칸에 넣으면 "이건 도구인가 사슬인가"가
흐려진다.

- [x] **Step 3: 이미지를 다시 빌드한다**

```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile . 2>&1 | tail -20
```

**기대:** `naming to docker.io/library/tars-devcontainer`로 끝난다. `.deb`를
예순 몇 개 다시 받으므로 **몇 분 걸린다** — 캐시가 `apt-get download` 줄에서
깨진다.

**실패했을 때 볼 곳:** `E: Unable to locate package`가 나오면 패키지 이름이
trixie에 없다는 뜻이다. 그럴 리 없다는 것을 착수 전에 확인했다(design 실측
1 — 둘 다 `main`에 있다).

- [x] **Step 4: sysroot에 실체가 들어왔는지 확인하고 amd64로 다시 잰다**

```bash
docker run --rm tars-devcontainer bash -c '
S="$AMD64_SYSROOT"          # Dockerfile:143이 /usr/local/amd64-sysroot로 둔다
ls -l $S/usr/bin/zoxide $S/usr/bin/fzf
for b in $S/usr/bin/zoxide $S/usr/bin/fzf; do
  printf "%s: " "$(basename $b)"
  readelf -d "$b" | grep NEEDED | sed "s/.*\[\(.*\)\]/\1/" | tr "\n" " "; echo
done
echo "--- 그 라이브러리들이 sysroot에 있나"
for l in libgcc_s.so.1 libm.so.6 libc.so.6; do
  printf "%s: " "$l"
  ls $S/usr/lib/x86_64-linux-gnu/$l >/dev/null 2>&1 && echo ok || echo MISSING
done'
```

**기대 (design 실측 2가 예측한 것):**

```
zoxide  1173976    libgcc_s.so.1 libm.so.6 libc.so.6
fzf     4368112    libc.so.6
libgcc_s.so.1: ok
libm.so.6: ok
libc.so.6: ok
```

**`MISSING`이 하나라도 나오면 멈춘다.** `copy_lib_deps`는 재귀로 따라가다 못
찾으면 죽으므로 Task 2가 그 자리에서 실패하지만, **원인에서 가장 가까운
자리는 여기다.**

- [x] **Step 5: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Bring two tools that learn into the sysroot"
```

---

## Task 2: initrd 목록에 두 줄을 얹는다

**Files:**
- Modify: `kernel/guest_tools.sh` (배열의 맨 끝, `usr/bin/vim.tiny:usr/bin/vim` 뒤)

- [x] **Step 1: 배열 끝에 층 하나를 더한다**

`usr/bin/vim.tiny:usr/bin/vim` 줄과 닫는 `)` **사이**에 넣는다.

**넣을 것:**

```bash
  # ── 층 4 · 셸 메모리 2 ─────────────────────────────────────────────────
  # SM-M0. 기계가 사용자에게서 배운 것을 뒤지는 도구 둘이다 — zoxide는 어느
  # 디렉터리에 자주 갔는지를, fzf는 무엇을 쳤는지를(Ctrl+R) 뒤진다.
  #
  # **UT 비목표 6이 이 둘을 여기까지 미뤄 둔 이유는 크기가 아니라 훅이었다** —
  # 셸이 무조건 no-config로 뜨는 한 rc에 훅을 걸 자리가 없었다. SC가 그 자리를
  # 만들었고(/config의 rc 셋), **SM-M1이 거기에 훅을 건다. M0에는 아직
  # 없다** — 사람이 이름으로 직접 부르는 것까지다.
  #
  # **새 라이브러리가 0이다.** zoxide는 libgcc_s·libm·libc를, fzf는 libc만
  # 부른다. libgcc_s는 btop의 libstdc++가, libm은 vim.tiny가 이미 데려왔다
  # (2026-09-11 amd64 .deb의 DT_NEEDED로 확인). **그래서 이 둘에 대해서는
  # copy_lib_deps를 빼도 게스트가 멀쩡하다** — design 위험이 하나 없는
  # milestone이고, 그것을 아는 것이 모르는 것보다 낫다.
  #
  # **fzf의 .deb가 데려오는 나머지는 안 넣는다.**
  #   usr/bin/fzf-tmux                              tmux가 없다
  #   usr/share/doc/fzf/examples/key-bindings.*      결정 7이 이유다
  #   usr/share/fish/vendor_functions.d/fzf_*.fish   같은 이유
  # fzf 0.60에는 `--zsh`/`--bash`/`--fish`가 내장돼 있고 그쪽이 자동완성까지
  # 함께 낸다. **SM-M1의 훅이 파일이 아니라 그 플래그를 쓴다.**
  #
  # **게이트는 둘 다 친다.** fzf는 TUI라 그냥 치면 매달리지만(less·top·htop·
  # btop·ncdu와 같은 자리) `--filter`가 찍고 즉시 끝난다 — **이 저장소에서
  # 처음으로, 대화형 도구를 비대화형 모드로 쳐서 보는 자리다.**
  usr/bin/zoxide:usr/bin/zoxide
  usr/bin/fzf:usr/bin/fzf
```

- [x] **Step 2: `make_initrd.sh`가 목록만 보고 둘을 넣는지 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./make_initrd.sh' 2>&1 | tail -5
```

**기대:** 마지막 줄이 cpio의 blocks 수다. 에러가 없어야 한다.

**`cp: cannot stat`가 나오면 Task 1이 안 끝난 것이다** — sysroot에 파일이
없다는 뜻이고, 이미지를 다시 빌드했는지 확인한다.

- [x] **Step 3: cpio 안에 우리가 정한 이름으로 있는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'zcat kernel/initrd.cpio | cpio -t 2>/dev/null | grep -E "^usr/bin/(fzf|zoxide)$"'
```

**기대:**

```
usr/bin/fzf
usr/bin/zoxide
```

**접두사 `./`가 없는 것이 정상이다**(UT-M0 실측). 이 목록은 `find .`이 아닌
방식으로 만들어진다.

- [x] **Step 4: 위험 4를 잰다 — 크기와 프롬프트까지의 시간**

```bash
stat -f "%z" kernel/initrd.cpio                            # gzip 뒤
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'zcat kernel/initrd.cpio | wc -c'                # 푼 크기
```

**기준선과 비교한다.**

| | Task 1 Step 1의 값 | 늘어난 양의 상한 |
|---|---|---|
| gzip | 34,869,668 | 바이너리 둘이 이미 압축된 Go/Rust라 **+2MB 안쪽**으로 본다 |
| 푼 것 | 90,329,088 | **+5,542,088**(design 실측 2) |

> ⚠ **plan이 틀렸다 (작은 쪽, 2026-09-11).** 실측은 gzip **37,162,196**
> (**+2,292,528** = 2.19 MiB로 "+2MB 안쪽"을 살짝 넘겼다) · 푼 것
> **95,871,488**(**+5,542,400**, 예측과 **312바이트** 차이 = cpio 헤더
> 패딩). 방향이 안전한 쪽이라 아무것도 안 바꿨다. **tmpfs 벽(RAM 512의
> 절반 = 256MiB)까지 여유 약 165MiB.**

**푼 크기가 그대로 RAM에 남는다** — initramfs는 tmpfs다(UT-M2가 128MiB에서
`System is deadlocked on memory`를 본 자리). `gate_lib.sh`의 `GUEST_MEM=512`가
이미 서 있어서 96MB는 문제가 아니지만, **수를 적어 두는 것이 다음 사람이 그
벽에 얼마나 남았는지 아는 유일한 방법이다**(UT design 실측 34가 그 여유를 안
쟀던 것을 자기비판으로 적고 있다).

- [x] **Step 5: 커밋**

```bash
git add kernel/guest_tools.sh
git commit -m "Put the two learning tools on the list and change nothing else"
```

`git status --short`가 비어 있어야 한다 — **`kernel/initrd.cpio`는
`.gitignore`에 있다.** 안 비어 있으면 `make_initrd.sh`가 산출물을 저장소에
남긴 것이고, 커밋하기 전에 확인한다(CLAUDE.md의 "Commit 전 git status 확인").

---

## Task 3: 게이트가 둘을 친다 — 검사 17·18

**Files:**
- Modify: `tools/check.sh:573` 부근 — `# ── 검사 17: 음성 확인` **앞**에 둘을
  넣고 그 검사의 번호를 **19**로 민다

- [x] **Step 1: 검사 17을 넣는다 — fzf**

`# ── 검사 17: 음성 확인 — **위의 아홉 전부에 대해** ───` 줄 **바로 앞**에
넣는다.

**넣을 것:**

```bash
# ── 검사 17: fzf가 돈다 — **비대화형 필터 모드** ────────────────────────
#
# fzf는 화면을 통째로 가져가는 TUI다. 그냥 치면 이 체인이 실패가 아니라
# **타임아웃**으로 죽는다 — less·top·htop·btop·ncdu가 목록 검사까지만 받는
# 이유와 같다(UT design 실측 26).
#
# **`--filter`가 그 함정을 비켜 간다.** 매치를 찍고 즉시 끝나고, stdin이
# tty면 내장 walker로 파일 트리를 훑는다(SM design 실측 7). 게스트 셸의
# stdin은 terminal이 만든 PTY라 tty이고, 그래서 **파이프도 따옴표도 필요
# 없다** — sendkey로 `|`와 `"`를 만들지 않아도 된다.
#
# **walker root를 /config로 잡으면 안 된다.** 이 체인에는 설정 디스크가
# 없어서 거기가 빈 디렉터리이고 fzf는 아무것도 못 찾는다(exit 1).
# /usr/share/git-core/templates는 UT-M3이 git의 경고를 없애려고 넣은 것이고
# **디스크 없이도 항상 거기 있다.**
#
# **검색어와 판정 글자가 다른 것이 이 프로브의 설계다.** `descr`을 치고
# `templates/description`을 본다 — 판정 글자가 타이핑한 명령줄에 있으면 그
# 검사는 도구가 죽어도 초록이다(SM design 실측 15). 이 저장소가 같은 함정에
# 세 번 걸렸다: bat은 그래서 검사를 아예 못 만들었고, 정적 목록 검사는 그래서
# tautology다.
echo "=== typing 'fzf --filter=descr --walker-root=/usr/share/git-core' ==="
type_keys f z f spc minus minus f i l t e r equal d e s c r spc \
          minus minus w a l k e r minus r o o t equal \
          slash u s r slash s h a r e slash g i t minus c o r e ret

if ! wait_for_screen "templates/description"; then
  fail "fzf did not filter the git template tree" \
    "terminal: screen>" "Unknown command" "error while loading"
fi
echo "fzf filtered a file tree without taking the screen"

# ── 검사 18: zoxide가 배우고 돌려준다 — **DB 왕복** ─────────────────────
#
# 두 명령이 한 사실을 증명한다 — 쓰고(add) 읽는다(query). **M0에는 훅이
# 없으니 셸이 대신 불러 주지 않는다** — 사람이 직접 두 번 부른다. 훅이
# `chpwd`에 걸려 `cd` 한 번으로 add가 일어나는 것은 SM-M1이 본다.
#
# **치는 경로에 `..`가 있는 것이 이 검사의 핵심이다.** zoxide는 경로를
# 정규화해서 저장하므로(SM design 실측 15) DB가 돌려주는
# `/usr/share/terminfo/x`는 **화면의 다른 어디에도 없는 글자**다 — 타이핑한
# 명령줄에도 없다. **zoxide가 그 글자를 만든 유일한 주체가 된다.**
#
# terminfo를 고른 이유는 다른 검사와 안 겹치기 때문이다. vendor/fonts는
# 검사 8·9가 이미 판정에 쓰고 있고, 검사 둘이 같은 글자를 보면 하나가 죽어도
# 둘 다 초록일 수 있다(검사 7·8의 주석과 같은 이유).
#
# DB는 `$HOME/.local/share/zoxide/db.zo`에 생긴다. 홈(/)은 tmpfs라 이 부팅과
# 함께 사라지고 **M0에서는 그것이 맞다** — 부팅을 넘어 남게 하는 것은 SM-M2이고
# 그때 XDG_DATA_HOME이 이 자리를 /config로 옮긴다. **이 검사의 판정 글자는
# 그때도 안 바뀐다.**
echo "=== typing 'zoxide add /usr/bin/../share/terminfo/x' ==="
type_keys z o x i d e spc a d d spc \
          slash u s r slash b i n slash dot dot slash s h a r e \
          slash t e r m i n f o slash x ret

echo "=== typing 'zoxide query terminfo' ==="
type_keys z o x i d e spc q u e r y spc t e r m i n f o ret

if ! wait_for_screen "/usr/share/terminfo/x"; then
  fail "zoxide did not give back the directory it had just learned" \
    "terminal: screen>" "Unknown command" "error while loading" \
    "no match found"
fi
echo "zoxide learned a directory and gave it back normalized"

```

> ⚠ **plan이 틀렸다 (2026-09-11).** 위의 `zoxide query terminfo`는
> **영원히 `no match found`다.** zoxide는 **마지막 키워드가 경로의 마지막
> 컴포넌트와 맞을 것을 요구하고**, 저장된 것은 `/usr/share/terminfo/x`라
> 마지막 컴포넌트가 `x`다. arm64 0.9.7로 좁혔다:
>
> ```
> $ zoxide query --list     → /usr/share/terminfo/x   ← 정규화는 맞았다
> $ zoxide query terminfo   → zoxide: no match found  rc=1
> $ zoxide query x          → /usr/share/terminfo/x   rc=0
> $ zoxide query terminfo x → /usr/share/terminfo/x   rc=0
> ```
>
> **design 실측 15가 틀린 것이 아니다** — 그때는 `fonts`로 쟀고 마지막
> 컴포넌트가 마침 `fonts`였다. **정규화는 이름 붙였는데 그 옆의 불변식은
> 이름 붙이지 않았고**, plan이 겹침을 피하려고 경로를 바꿀 때 이름 없는
> 쪽이 깨졌다. **`terminfo x`로 고쳤다**(`x` 하나로도 맞지만 M2가 DB를
> 남기면 `x`로 끝나는 경로가 여럿일 수 있다).

- [x] **Step 2: 음성 확인의 번호를 19로 민다**

**지울 것:**

```bash
# ── 검사 17: 음성 확인 — **위의 아홉 전부에 대해** ──────────────────────
#
# fish는 못 찾은 명령에 `Unknown command`를 낸다. 이 검사가 맨 뒤에 있는
# 이유가 그것이다 — ls · ps · awk · sed · eza · fd · jq · git · vi 아홉을
# 다 친 뒤에 한 번 보면 아홉 전부의 음성 확인이 된다. UT-M0 때는 ls
# 하나뿐이라 바로 뒤에 있었다.
#
# **번호가 11에서 17로 뛴 것은 UT-M3이 검사 다섯을 앞에 끼웠기 때문이다** —
# 음성 확인은 언제나 맨 뒤이고, 앞에 무엇이 늘든 이 검사는 늘어난 것까지
# 함께 본다. 그것이 이 자리의 값이다.
```

**넣을 것:**

```bash
# ── 검사 19: 음성 확인 — **위의 열하나 전부에 대해** ────────────────────
#
# fish는 못 찾은 명령에 `Unknown command`를 낸다. 이 검사가 맨 뒤에 있는
# 이유가 그것이다 — ls · ps · awk · sed · eza · fd · jq · git · vi · fzf ·
# zoxide 열하나를 다 친 뒤에 한 번 보면 열하나 전부의 음성 확인이 된다.
# UT-M0 때는 ls 하나뿐이라 바로 뒤에 있었다.
#
# **번호가 11 → 17 → 19로 뛴 것은 앞에 검사가 끼워졌기 때문이다**(UT-M3이
# 다섯, SM-M0이 둘). 음성 확인은 언제나 맨 뒤이고, 앞에 무엇이 늘든 이 검사는
# **늘어난 것까지 함께 본다.** 그것이 이 자리의 값이다 — SM-M0은 이 검사를
# 한 글자도 고치지 않고 새 도구 둘의 음성 확인을 얻는다.
```

- [x] **Step 3: 체인의 머리 주석에 한 문단을 더한다**

`# **열 체인 중 어느 것도 이것을 못 본다.**` 줄 **바로 앞**에 넣는다.

**넣을 것:**

```bash
# **SM-M0이 도구 둘(zoxide · fzf)을 더하고 검사 둘을 더 친다** — 훅은 아직
# 없으므로 사람이 이름으로 직접 부르는 것까지다. 둘 다 경로를 찍는 도구라
# **판정 글자를 타이핑한 명령줄과 겹치지 않게 만드는 것**이 이 둘의 설계
# 전부다: fzf는 검색어(`descr`)와 판정(`templates/description`)을 다르게
# 하고, zoxide는 `..`를 지나는 경로를 쳐서 **정규화된 답만** 판정으로 쓴다.
#
```

- [x] **Step 4: bash 문법만 먼저 본다 — 부팅 20초를 쓰기 전에**

```bash
bash -n tools/check.sh && echo "syntax ok"
```

**기대:** `syntax ok`. `type_keys`의 줄 이음(`\`)을 잘못 쓰면 여기서 죽는다.

- [x] **Step 5: 커밋**

```bash
git add tools/check.sh
git commit -m "Type two tools that print paths, and judge on what only they can say"
```

---

## Task 4: UT 체인 단독 실행

- [x] **Step 1: 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -40
```

**얼마나 걸리나:** 캐시가 살아 있으면 약 30초, 커널을 다시 빌드하면 몇 분.

- [x] **Step 2: 초록인지, 그리고 **새 줄 둘**이 찍혔는지 본다**

**기대(마지막 다섯 줄):**

```
fzf filtered a file tree without taking the screen
=== typing 'zoxide add /usr/bin/../share/terminfo/x' ===
=== typing 'zoxide query terminfo' ===
zoxide learned a directory and gave it back normalized
PASS
```

- [x] **Step 3: 실패했을 때 어디를 보나**

| 증상 | 첫 의심 |
|---|---|
| `Unknown command` | `guest_tools.sh`의 dest 이름 또는 Task 1의 이미지 |
| `error while loading` | `copy_lib_deps` — 하지만 새 라이브러리가 0이라 **이럴 리 없다.** 나오면 실측 2가 틀린 것이고 design을 고친다 |
| fzf에서 **타임아웃**(150 × 0.1초) | `--filter`가 안 먹었다 = fzf가 TUI로 떴다. 화면 덤프를 보면 안다 |
| fzf만 빨갛고 화면에 프롬프트가 멀쩡 | walker가 아무것도 못 찾았다 — `/usr/share/git-core/templates/description`이 initrd에 있는지 `cpio -t`로 확인 |
| zoxide에서 `no match found` | add가 실패했다. `not a directory`가 화면에 있으면 경로 오타다 |

**`sendkey`가 못 치는 글자가 있는지도 여기서 드러난다** — 타이핑한 명령줄이
화면에 **온전히** 찍혔는지를 먼저 본다(UT-M3이 대문자로 배운 자리).

- [x] **Step 4: 커밋 없음**

이 Task는 관측만 한다.

---

## Task 5: 음성 확인 — **셋을, 각각 두 번씩**

> ⚠ **한 번의 결과로 판정하지 말 것.** `zig build test`의 낡은 결과가 SC-M1과
> SC-M2에서 세 번 나왔고 원인을 못 찾았다(SC design 실측 26·34). **M0은 Zig를
> 안 건드리지만 게이트 체인 자체를 두 번씩 돌리는 규칙은 그대로 적용한다.**

각 되돌림은 **고치고 → 돌리고 → `git checkout`으로 복구하고 → 다시 한 번**
이다.

- [x] **되돌림 1: `guest_tools.sh`에서 `fzf` 줄을 지운다**

```bash
# usr/bin/fzf:usr/bin/fzf 줄을 지우고
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -15
git checkout kernel/guest_tools.sh
```

**예상:** **검사 1(정적)은 초록이고 검사 17이 빨갛다.**

```
FAIL: fzf did not filter the git template tree
  ... Unknown command
```

**이것이 UT-M1의 tautology를 실연하는 자리다** — 정적 검사는 목록과 같은
파일을 보므로 줄을 지우면 **찾을 것도 함께 없어진다.** 목록의 완전함을
증명하는 것은 정적 검사가 아니라 **타이핑**이다.

- [x] **되돌림 2: zoxide의 판정을 일부러 가짜로 만든다 — 이 milestone에서 가장 값진 확인**

두 곳을 동시에 고친다.

```bash
# (가) guest_tools.sh에서 usr/bin/zoxide 줄을 지운다
# (나) tools/check.sh의 검사 18에서 `..`를 뺀다:
#      type_keys z o x i d e spc a d d spc \
#                slash u s r slash s h a r e slash t e r m i n f o slash x ret
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -15
git checkout kernel/guest_tools.sh tools/check.sh
```

**예상:** **검사 18 자신은 초록으로 지나가고**, 맨 뒤의 검사 19가 잡는다.

```
zoxide learned a directory and gave it back normalized     ← 거짓말이다
FAIL: the shell said it could not find one of the commands
```

**도구가 아예 없는데 그 도구의 검사가 초록인 것을 실행으로 보는 자리다.**
`..`가 없으면 판정 글자가 타이핑한 명령줄에 그대로 있고, `wait_for_screen`은
그 줄을 찾아 만족한다. **`..` 셋 글자가 이 검사를 진짜로 만드는 전부다.**

그리고 이것이 **맨 뒤의 음성 확인이 왜 그 자리에 있는지**를 함께 보여 준다 —
개별 검사가 가짜여도 그 검사가 그물에 걸린다.

> ⚠ **plan이 틀렸다 — 그리고 이것이 M0에서 가장 값진 발견이 됐다
> (2026-09-11).** 위 예상의 앞 절반은 맞았고(검사 18이 초록으로 거짓말한다)
> **뒤 절반이 틀렸다. 체인 전체가 PASS했다 — 세 번 돌려 세 번 다.**
>
> 첫 의심은 경합이었고 근거도 있었다. 시리얼 로그에서 판정 글자가 처음 뜬
> 줄이 **69421**(타이핑한 줄의 에코), `Unknown command`가 처음 뜬 줄이
> **69813**으로 **392줄이 비어 있었다.**
>
> **그런데 그것이 원인이 아니었다.** 로그에는 `Unknown command`와
> `terminal: screen>`를 **함께 단 줄이 스물** 있었다. 검사 19의 조건이
> 그 스물을 못 본 것이다:
>
> ```
> $ bash -c 'grep -a "…screen>" serial.log | grep -aq "Unknown command"; echo $?'
> 0      ← pipefail 없이
> $ bash -c 'set -uo pipefail; … | grep -aq …; echo $?'
> 141    ← 5회 중 5회
> ```
>
> **`grep -q`가 첫 매치에 즉시 나가고, 3.7MB를 아직 쏟던 앞단 grep이
> SIGPIPE로 죽는다. `set -uo pipefail`이 그 141을 파이프라인 코드로 올리고
> `if`가 "안 맞았다"로 읽는다** — **매치할수록 초록이 되는 검사**였다.
> **그물은 쓰인 날부터 죽어 있었고, 새 도구와 아무 상관이 없다.**
>
> **이 파일이 자기 함정에 걸렸다** — 같은 스크립트 검사 1의 주석,
> `fail()`의 `|| true`(RM-M2), `gate_lib.sh:108`이 전부 이 함정을
> 경고하고 있다. `-q`를 빼서 고쳤고, 고친 뒤 되돌림 2는 두 번 다 예상대로
> 나온다. **같은 모양이 저장소에 다섯 더 있다**(design 실측 19의 표).
>
> 검사 19 앞에 배수 관문(`uname -o` → `GNU/Linux`)도 넣었는데, **정직하게
> 그것은 고친 것이 아니라 보장한 것이다** — SIGPIPE를 고친 뒤에는 관문을
> 꺼도 잡힌다(grep이 3.7MB를 읽는 동안 로그가 자라서다. 우연한 성질이다).

- [x] **되돌림 3: fzf의 walker root를 `/config`로 바꾼다**

```bash
# 검사 17의 마지막 인자를 slash c o n f i g 로 바꾼다
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -15
git checkout tools/check.sh
```

**예상:** 검사 17이 빨갛고, **화면에는 에러가 한 줄도 없다** — fzf가 빈
디렉터리를 훑고 조용히 `exit 1`한다. design 실측 7의 경고를 실행으로 보는
자리이고, **"실패했는데 아무 말도 없는" 실패의 모양**이다.

- [x] **안 하는 되돌림 하나를 적어 둔다**

**`copy_lib_deps`를 zoxide에만 건너뛰게 하는 것은 안 한다.** 새 라이브러리가
0이라(실측 2) **아무것도 안 깨진다** — 되돌림이 아무 것도 안 죽이면 그것은
음성 확인이 아니다. UT-M1·M2에서 이 되돌림이 값을 냈던 것은 그때 사슬이
열여섯·셋이었기 때문이다.

- [x] **결과를 적는다**

여섯 번의 실행 결과(셋 × 두 번)를 design의 실측 절에 쓸 수 있게 정리한다.
**예상과 다른 것이 하나라도 있으면 그것이 이 milestone에서 가장 중요한
발견이다** — SC-M0은 되돌림 셋이 전부 예상과 달랐다.

---

## Task 6: 루트 게이트

- [x] **Step 1: 백그라운드로 돌린다**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

**얼마나 걸리나: 26분 안팎이다.** 기준선은 SC-M2의 **열한 체인 3/3 = 25분
58.09초**이고, M0은 부팅을 하나도 안 더하므로 **잡음(±3분) 안에 있어야
한다.**

- [x] **Step 2: 체인 열하나가 3/3인지 본다**

```bash
grep -c "^PASS" /tmp/gate.log
grep -aE "^(PASS|FAIL)" /tmp/gate.log | sort | uniq -c
tail -5 /tmp/gate.time
```

**`terminal` 쪽 `PASS`가 넷인 것이 정상이다** — 다섯 바이너리가 다 돌지만
`status_test.zig`만 `PASS`를 안 찍는다. **세는 것으로 판정하지 말 것.**

- [x] **Step 3: 새 도구가 다른 체인을 안 건드렸는지 수로 확인한다**

```bash
grep -ac "Unknown command" /tmp/gate.log          # 0이어야 한다
grep -ac "error while loading shared libraries" /tmp/gate.log   # 0
grep -ac "templates/description" /tmp/gate.log    # 3 (tools 체인 × 세 회차)
grep -ac "/usr/share/terminfo/x" /tmp/gate.log    # 3 (같다)
grep -ac "not a directory" /tmp/gate.log          # 0 (zoxide add가 다 성공했다)
grep -ac "Welcome to fish" /tmp/gate.log          # 6 — M0·M1·M2와 같아야 한다
```

**마지막 줄이 회귀 감지다.** SC-M0이 만든 수이고, 이 도구 둘은 셸의 뜨는
방식을 안 건드리므로 **6이 그대로여야 한다.** 달라지면 우리가 모르는 영향이
있는 것이다.

> ⚠ **plan이 틀렸다 (작은 쪽, 2026-09-11).** `templates/description`과
> `/usr/share/terminfo/x`는 **3이 아니라 0이다.** 그 글자는 게스트
> **화면**에 있고, 화면 덤프는 체인이 컨테이너 안에 만드는 `$LOG`에 살며
> **실패했을 때만** 루트 게이트의 stdout으로 나온다. 초록일 때 루트 로그에
> 남는 것은 체인이 스스로 찍는 `echo` 줄뿐이다 — **대신 셀 것**:
>
> ```
> fzf filtered a file tree                 3
> zoxide learned a directory               3
> to drain the guest before the net reads  3
> all 67 tools the list names              3
> ```
>
> 나머지 넷(`Unknown command` 0 · `error while loading` 0 ·
> `not a directory` 0 · `Welcome to fish` **6**)은 예상대로였다.
> **실측: 26분 27.84초, 18 PASS / 0 FAIL, 첫 회차에 통과**(기준선
> 25분 58.09초에서 +29.75초).

- [x] **Step 4: 커밋 없음**

관측만 한다.

---

## Task 7: 문서

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md`
  (`## SM-M0이 실행으로 증명한 것` 절을 **새로 만든다**, 실측 16부터)
- Modify: `docs/decisions/project_shell_memory.md` (**새 파일**)
- Modify: `MEMORY.md` (한 줄 추가)
- Modify: `CLAUDE.md` (완료된 서브프로젝트 목록 — **SM은 아직 진행 중이므로
  "진행 중"으로 적는다**)
- Modify: `HANDOFF.md` (맨 앞에 SM-M0 절을 넣고 그 아래로 SC-M2를 민다)
- Modify: `docs/superpowers/plans/2026-09-11-tars-shell-memory-sm-m0.md`
  (체크박스를 채운다)

- [x] **Step 1: design에 실측을 더한다**

`## 비목표` 절 **앞**에 새 절을 만든다. 실측 번호는 **16**에서 시작한다
(1~15는 착수 전 실측이다).

무엇을 적나:

| 실측 | 내용 |
|---|---|
| 16 | amd64 sysroot의 실제 크기·`DT_NEEDED`와 **예측이 맞았는지** |
| 17 | initrd 크기 전후(gzip·푼 것)와 **tmpfs 벽까지 남은 여유** |
| 18 | **`..` 셋 글자가 검사를 진짜로 만든다** — 되돌림 2의 결과 |
| 19 | 되돌림 1·3의 결과(tautology의 실연 · 조용한 실패의 모양) |
| 20 | 게이트 시간과 수 여섯(Task 6 Step 3) |

**예상과 달랐던 것을 먼저 쓴다.** 이 저장소의 design은 "맞았다"보다 "틀렸다"를
더 길게 적는다 — 다음 사람이 쓰는 것이 그쪽이기 때문이다.

- [x] **Step 2: 기억 파일을 만든다**

`docs/decisions/project_shell_memory.md`. `project_shell_config.md`와 같은
모양으로 쓰고, **다시 캐지 말 것**을 맨 위에 둔다. 반드시 들어갈 것 셋:

1. **SC 결정 1의 링크 패턴을 SM이 기각했다는 것**과 그 근거(댕글링 링크에서
   zoxide가 `cd`마다 에러 두 줄)
2. **판정 글자가 타이핑한 줄과 겹치면 검사가 가짜라는 것**과 `..`가 그
   처방이라는 것
3. **fzf 0.60에 셸 통합이 내장돼 있어 `.deb`의 예제를 안 넣는다는 것**

- [x] **Step 3: `MEMORY.md`에 한 줄**

```markdown
- [Shell memory](docs/decisions/project_shell_memory.md) — 기계가 배운 것을 /config에 남기고 fzf가 그것을 뒤지는 층(SM, 2026-09-11 착수 · M0 완료) …
```

- [x] **Step 4: `CLAUDE.md`의 목록에 SM을 더한다**

"완료된 서브프로젝트" 문단 끝에 **진행 중**으로 적는다. `Shell
Config(SC-M0~M2)` 바로 뒤다.

- [x] **Step 5: `HANDOFF.md`를 새로 쓴다**

맨 앞에 SM-M0 절을 넣고 기존 SC-M2 절을 `## 그 앞의 milestone —`으로 민다.
**"바로 다음에 할 것"은 SM-M1의 plan을 쓰는 것이다**(훅 두 줄 · 결정 6의
허용 목록 · `config/check.sh`의 6차 부팅).

- [x] **Step 6: 이 plan의 체크박스를 채우고, 틀린 자리를 표시한다**

**plan이 틀렸던 자리를 지우지 말고 그 위에 적는다** — SC-M2의 마지막 커밋이
`Tick off the plan and note where it guessed wrong`인 이유다.

- [x] **Step 7: 커밋**

```bash
git add docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md \
        docs/decisions/project_shell_memory.md \
        docs/superpowers/plans/2026-09-11-tars-shell-memory-sm-m0.md \
        MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Write down what two tools that print paths taught the gate"
```

---

## 이 milestone이 끝나도 **안 되는 것** — 알고 둔다

| 안 되는 것 | 언제 |
|---|---|
| `z tmp`로 디렉터리를 옮기는 것 | **SM-M1.** 훅이 없으면 `z`라는 함수가 아예 없다 |
| `Ctrl+R`로 히스토리를 뒤지는 것 | **SM-M1**(위젯) + **SM-M2**(히스토리가 남는 것) |
| 재부팅 뒤에도 기억하는 것 | **SM-M2.** M0의 DB는 tmpfs에 있다 |
| bash·fish에서 둘이 도는 것 | 게이트가 치는 것은 **fish 하나**다(이 체인의 셸이다). `zoxide`·`fzf` 바이너리는 셸과 무관하지만 **훅은 셸마다 다르고**, 그것은 M1의 한계로 넘어간다 |
| `zi`(대화형 선택) | 비목표 5. 되지만 게이트가 안 본다 |

---

## Self-review 메모 — 이 plan이 spec을 어디까지 덮나

| spec의 요구 | 이 plan의 자리 |
|---|---|
| 결정 7(fzf 통합은 바이너리 내장) | Task 2 Step 1의 주석이 `.deb`의 예제 셋을 **안 넣는 이유**로 적는다 |
| 결정 8(게이트를 둘로 나눈다) — `tools/check.sh` 쪽 | Task 3 |
| 결정 8 — `config/check.sh` 쪽 부팅 6·7차 | **SM-M1·M2다.** M0은 안 건드린다 |
| 실측 2(새 라이브러리 0) | Task 1 Step 4가 확인하고, Task 5가 **그래서 되돌림 하나를 안 한다**고 적는다 |
| 실측 15(정규화) | Task 3 검사 18 · Task 5 되돌림 2 |
| 위험 4(initrd 크기) | Task 2 Step 4 |
| 위험 5(게이트 시간) | Task 6 Step 1 |
| 위험 1·2·3 | **M1·M2다.** 훅과 히스토리가 없으면 그 위험이 아직 없다 |
| 비목표 전부 | 위의 "안 되는 것" 표 |
