# GE-M0 — 게스트에 `which`를 싣는다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-guest-ergonomics-design.md`
Status: 착수 전. 실측은 맨 아래 "GE-M0이 실측한 것" 절에 구현자가 채운다.

## 누가 무엇을 하나

design 결정 8. Task 0~4와 Task 6은 구현 서브에이전트(Sonnet)가 한다. Task 5(체인 · mutation ·
루트 게이트)는 lead가 한다. 다만 구현자는 Task 4 끝에 `tools` 체인을 한 번(약 1분) 돌려 초록인지
보고한다. commit은 lead가 한다 — 구현자는 commit하지 않는다.

이 plan은 코드 파일 넷과 문서 둘을 고친다. 고치는 자리는 줄 번호가 아니라 심볼과 `rg` 패턴으로
적는다.

| 파일 | 무엇을 |
|---|---|
| `devcontainer/Dockerfile` | `debianutils:amd64` 한 줄과 주석 블록 |
| `kernel/make_initrd.sh` | `copy_lib_deps` 맨 앞의 ELF 검사 |
| `kernel/guest_tools.sh` | 층 13과 한 줄, 머리 주석 한 문장 |
| `tools/check.sh` | 빌드 줄의 stderr 담기, 검사 1c · 22, 주석 둘 |
| `docs/guides/lessons.md` | `tools/check.sh` 항목 |
| 이 plan | 맨 아래 실측 절 |

## 이 milestone이 끝나면

- 게스트의 `/usr/bin/which`가 debianutils의 `which.debianutils`(1,080바이트 POSIX sh
  스크립트)다. fish와 bash에서 `which <이름>`이 `PATH`(`/usr/bin:/bin`)의 첫 실행 파일 경로를
  찍고, 못 찾으면 아무것도 안 찍고 1로 끝난다. zsh에서는 zsh의 builtin이 이것을 가린다(design
  결정 1).
- `copy_lib_deps`가 ELF가 아닌 파일을 처음에 건너뛴다. `make_initrd.sh`의 stderr에
  `readelf: Error`가 없다.
- `tools/check.sh`에 검사 1c(부팅 전)와 22(부팅 뒤)가 생긴다. 새 체인은 없다.

## 착수 전에 확정한 것

1. 이미지 재빌드는 돌고 있는 게이트가 없을 때만 한다. `docker build`가 `tars-devcontainer`
   태그를 옮기면 돌고 있는 게이트의 다음 `docker run`이 새 sysroot를 본다. 시작 전에
   `pgrep -fl 'tars-devcontainer'`가 비었는지 본다(CU-M1 plan 확정 2와 같다).
2. sysroot에 `which`가 없고 debianutils가 `usr/bin/which.debianutils`로 담는다(design 실측 1).
   `install_tool`은 `[ -f "$src" ]`로 원본을 찾고 `cp`가 링크를 따라가므로, 원본이 일반
   파일인 이것은 손볼 것이 없다.
3. 스크립트가 쓰는 것은 `/bin/sh`(뼈대, bash 링크)뿐이다. `copy_lib_deps`가 인터프리터를 안
   따라가도 `tools/check.sh` 검사 1의 `WANT`가 `bin/sh`를 literal로 본다.
4. ELF 검사의 모양은 design 결정 2다. 함수 맨 앞에서 4바이트를 `od`로 16진수로 바꿔
   `7f454c46`과 비교한다. `head -c 4`의 출력을 바로 비교하지 않는 이유는, 첫 4바이트에 NUL이
   있는 파일이면 bash가 명령 치환에서 `ignored null byte` 경고를 찍기 때문이다.
5. 검사 22의 판정 글자는 출력에만 생긴다(`project_gate_screen_echo`).
   - `which which`의 출력은 `/usr/bin/which`다. 친 줄에는 슬래시가 없다. 같은 부팅의 앞 검사들이
     화면에 내는 것(`ls` · `ls -l /bin` · `ps ax` · `/etc/passwd` · `/etc/group` · eza · fd · jq ·
     git · `vi --version` · fzf · zoxide · loopback 왕복) 어디에도 `/usr/bin/which`가 없다.
   - `which ge-none; echo ge-rc=$status`의 출력은 `ge-rc=1`이다. 친 줄에는 `ge-rc=$status`가
     있고 `ge-rc=1`이 없다. fish가 `which`를 못 찾았다면 `ge-rc=127`이므로, 패턴은
     `ge-rc=1( |$)`로 `1` 뒤에 공백이나 줄 끝을 요구한다. `screen>` 줄은 행을 ` | `로 잇는다.
   - fish의 종료 코드 변수는 `$status`다. `$?`를 치면 fish가 에러를 낸다.
6. 키 이름(lessons 실측 6 — 전부 소문자, 공백은 `spc`). `$`는 `shift-4`, `;`는 `semicolon`,
   `-`는 `minus`, `=`는 `equal`이다. `tools/check.sh`에는 `type_text`가 없으므로(그것은
   `render/check.sh`에만 있다) `type_keys`에 키 이름을 나열한다. 검사 18이 같은 모양이다.
7. `tools/check.sh`의 빌드 줄을 바꿔도 진입 검사는 그대로 통과해야 한다.
   `require_build_steps`는 본문에서 `./make_initrd.sh`라는 부분 문자열을 찾는다. 새 모양에도 그
   글자가 있다. 검사 1c의 `grep`은 파이프 뒤가 아니라서 `require_no_early_exit_pipe`와 무관하다.
   Task 4 끝에 lessons의 `ENTRY-OK` 명령으로 확인한다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다.

   ```bash
   pgrep -fl 'tars-devcontainer'
   ```

   아무것도 안 나와야 한다.
2. sysroot에 `which`가 없는 것을 본다.

   ```bash
   docker run --rm tars-devcontainer bash -c 'ls "$AMD64_SYSROOT"/usr/bin | grep -c "^which" || true'
   ```

   기대: `0`.
3. 지금의 `make_initrd.sh`가 `readelf: Error`를 하나도 안 내는 것과 initrd 크기를 잰다.
   `make_initrd.sh`는 `init/zig-out` · `terminal/zig-out`의 산출물을 복사하므로 그것이 저장소에
   있어야 한다. 없어서 `cp: cannot stat`으로 죽으면 `tools/check.sh`를 한 번 돌린 뒤(약 1분)
   다시 한다.

   ```bash
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
     (cd kernel && ./make_initrd.sh) > /dev/null 2> /tmp/e.txt; echo "rc=$?"
     echo "readelf errors: $(grep -c "readelf: Error" /tmp/e.txt)"'
   ls -l kernel/initrd.cpio
   gzip -dc kernel/initrd.cpio | wc -c
   ```

   기대: `rc=0`, `readelf errors: 0`. 0이 아니면 멈추고 그 줄을 실측 절에 적는다 — 검사 1c의
   전제가 깨진 것이다. 크기 둘은 Task 3에서 다시 잰다(`gzip -dc`는 firmware 꼬리까지 함께 푼다.
   차이만 볼 것이라 상관없다).

## Task 1: `devcontainer/Dockerfile`

1. sysroot `RUN`의 `apt-get download` 목록에서 `coreutils:amd64 \` 바로 다음 줄에 더한다.

   ```
           debianutils:amd64 \
   ```

   들여쓰기는 이웃 줄과 같은 공백 여덟이다.
2. 주석 블록을 하나 더한다. 자리는 `# ── CU-M1: 층 3의 편집기를 vim.basic으로` 블록의 끝,
   `ENV AMD64_SYSROOT=` 바로 위다(`rg -n 'ENV AMD64_SYSROOT' devcontainer/Dockerfile`). 이 내용
   그대로 넣는다.

   ```
   # ── GE-M0: 층 13(which) ───────────────────────────────────────────────
   #
   # debianutils는 which를 /usr/bin/which.debianutils라는 1,080바이트짜리 #! /bin/sh
   # 스크립트로 담는다. /usr/bin/which는 postinst가 alternatives로 만드는 링크라서
   # dpkg -x로 푼 여기에는 없다 — guest_tools.sh가 실체를 /usr/bin/which로 싣는다
   # (mawk→awk와 같은 자리). 패키지의 나머지(run-parts · savelog · ischroot ·
   # add-shell · remove-shell · update-shells · installkernel)는 sysroot에만 풀리고
   # initrd에는 안 들어간다. 라이브러리는 0개다 — 스크립트다.
   ```
3. 이미지를 다시 굽는다(확정 1을 먼저 본다). 선례는 27.1초(CU-M1)다.

   ```bash
   { time docker build -t tars-devcontainer devcontainer/ ; } 2>&1 | tail -3
   ```

4. sysroot에 실체가 생겼는지 본다.

   ```bash
   docker run --rm tars-devcontainer bash -c '
     ls -l "$AMD64_SYSROOT"/usr/bin/which.debianutils
     head -1 "$AMD64_SYSROOT"/usr/bin/which.debianutils
     ls "$AMD64_SYSROOT"/usr/bin/which 2>&1'
   ```

   기대: 크기 `1080`, 첫 줄 `#! /bin/sh`, 마지막 줄은 `No such file or directory`(링크가 없다).
   크기가 다르면 그 값을 실측 절에 적고 계속한다 — debianutils 판이 바뀐 것이다.

## Task 2: `kernel/make_initrd.sh` — `copy_lib_deps`의 ELF 검사

`copy_lib_deps()`의 `local bin="$1" interp src soname dest` 줄 바로 다음, `interp="$(readelf -p
.interp …` 줄 앞에 넣는다(`rg -n 'copy_lib_deps\(\)' kernel/make_initrd.sh`).

```bash
  # GE-M0. ELF가 아닌 파일은 따라갈 DT_NEEDED가 없다. guest_tools.sh의 which는
  # #! /bin/sh 스크립트라서, 이 검사 없이 들어오면 빌드는 살지만 아래 readelf -d가
  # `readelf: Error: …: Failed to read file header`를 stderr에 찍는다. 빌드가 사는
  # 것은 우연이다 — .interp 줄은 2>/dev/null || true로 막혀 있고, readelf -d는
  # for의 단어 목록 안이라 set -e가 그 실패를 안 본다. 실패가 아닌데 실패처럼 생긴
  # 줄이 빌드 로그에 남으면 진짜 에러가 그 사이에 묻힌다.
  #
  # magic 4바이트(7f 45 4c 46)만 본다. readelf -h로 묻지 않는 이유는 망가진
  # ELF(복사가 끊긴 바이너리)까지 조용히 건너뛰기 때문이다 — 그런 파일은 지금처럼
  # 아래 readelf까지 가서 에러를 내야 한다. od를 거치는 이유는 첫 4바이트에 NUL이
  # 있는 파일이면 bash가 명령 치환에서 `ignored null byte` 경고를 찍기 때문이다.
  # 스크립트의 인터프리터(#! 줄)는 따라가지 않는다(GE design 결정 2 · 비목표 3).
  # tools/check.sh 검사 1c가 이 검사를 지킨다.
  if [ "$(head -c 4 "$bin" | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then
    return 0
  fi
```

들여쓰기는 함수 본문과 같은 공백 둘이다. 편집 뒤 `git diff --stat`이 이 파일에 더한 줄만
보여야 한다(지운 줄 0).

## Task 3: `kernel/guest_tools.sh`

1. `GUEST_TOOLS` 배열의 맨 끝, `usr/sbin/iw:usr/bin/iw` 줄 뒤이자 닫는 `)` 앞에 빈 줄 하나와 이
   블록을 넣는다.

   ```bash
     # ── 층 13 · 셸 편의(GE-M0) ─────────────────────────────────────────────
     # 사용자가 2026-10-04에 요청했다. debianutils의 which.debianutils를 /usr/bin/which로
     # 싣는다. 왼쪽과 오른쪽이 다른 다섯째 자리다(mawk→awk · fdfind→fd · vim.basic→vim ·
     # dhcpcd에 이어). 이유는 mawk와 같다 — /usr/bin/which는 postinst가 alternatives로
     # 만드는 링크라 dpkg -x로 푼 sysroot에 없다.
     #
     # 이 목록에서 ELF가 아닌 첫 줄이다. 1,080바이트짜리 #! /bin/sh 스크립트라 라이브러리가
     # 0개이고, 인터프리터 /bin/sh는 뼈대다(bash 링크, 결정 6). install_tool이 부르는
     # copy_lib_deps는 ELF magic을 보고 이것을 건너뛴다(GE design 결정 2).
     #
     # fish와 bash에는 which builtin이 없어서 이 스크립트가 돈다. zsh에서는 zsh의 builtin이
     # 이것을 가린다 — `command which`나 /usr/bin/which로 부른다(GE design 결정 1).
     # tools/check.sh 검사 22가 fish에서 친다.
     usr/bin/which.debianutils:usr/bin/which
   ```

2. 머리 주석의 "형식" 절, "UT-M2의 `fdfind`→`fd`, `batcat`→`bat`도 같은 자리를 쓴다." 문장
   (`rg -n 'batcat.→.bat.도 같은 자리' kernel/guest_tools.sh`) 바로 뒤에 한 문장을 붙인다.

   ```
   # GE-M0의 `which.debianutils`→`which`는 mawk와 이유까지 같다(alternatives).
   ```

3. dhcpcd 블록의 "넷째 자리다(mawk→awk · fdfind→fd · vim.basic→vim에 이어)"는 그대로 둔다. 그
   시점의 순서를 적은 것이고 지금도 맞다.
4. 확인한다. 배열이 source되고 길이가 하나 늘어야 한다.

   ```bash
   git show HEAD:kernel/guest_tools.sh > /tmp/gt_old.sh
   bash -c '. /tmp/gt_old.sh; echo "before ${#GUEST_TOOLS[@]}"; . kernel/guest_tools.sh; echo "after ${#GUEST_TOOLS[@]}"'
   ```

   기대: after가 before보다 1 크다(CU-M1 실측 4에서 86이었다).
5. initrd를 다시 만들어 Task 0과 비교한다.

   ```bash
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
     (cd kernel && ./make_initrd.sh) > /dev/null 2> /tmp/e.txt; echo "rc=$?"
     echo "readelf errors: $(grep -c "readelf: Error" /tmp/e.txt)"
     gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | grep -x "usr/bin/which"'
   ls -l kernel/initrd.cpio
   gzip -dc kernel/initrd.cpio | wc -c
   ```

   기대: `rc=0`, `readelf errors: 0`, `usr/bin/which` 한 줄. 압축 전 크기는 1,080바이트와 cpio
   머리만큼 는다 — 잰 값을 실측 절에 적는다.
6. Task 2가 없었다면 어땠는지를 같은 자리에서 한 번 본다(design 실측 2의 재현). 저장소 파일은
   안 고치고 사본을 덮는다.

   ```bash
   mkdir -p /tmp/run
   cp kernel/make_initrd.sh /tmp/run/make_initrd.sh
   sd -F 'if [ "$(head -c 4 "$bin"' 'if false && [ "$(head -c 4 "$bin"' /tmp/run/make_initrd.sh
   chmod +x /tmp/run/make_initrd.sh; diff kernel/make_initrd.sh /tmp/run/make_initrd.sh
   docker run --rm -v "$PWD":/workspace \
     -v /tmp/run/make_initrd.sh:/workspace/kernel/make_initrd.sh:ro \
     -w /workspace tars-devcontainer bash -c '
     (cd kernel && ./make_initrd.sh) > /dev/null 2> /tmp/e.txt; echo "rc=$?"
     grep "readelf: Error" /tmp/e.txt'
   ```

   기대: `diff`가 한 줄의 차이를 보이고, `rc=0`이며, `readelf: Error: …/usr/bin/which: Failed to
   read file header` 한 줄. 끝나면 저장소의 `kernel/initrd.cpio`가 이 사본으로 만든 판이지만
   내용은 같고(검사만 꺼졌다) 다음 빌드가 다시 만든다.

## Task 4: `tools/check.sh`

### 4-1. 빌드 줄이 stderr를 파일에 담는다

`rg -n 'make_initrd.sh\); then' tools/check.sh`로 찾는 블록을 바꾼다.

지금:

```bash
if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi
```

바꾼 뒤:

```bash
# GE-M0: stderr를 파일에 담아 검사 1c가 읽는다. 사람이 보던 출력은 그대로
# 보이도록 끝에 다시 뿜는다. 실패했을 때도 먼저 뿜어야 원인이 보인다.
INITRD_ERR="$(mktemp)"
if ! (cd ../kernel && ./make_initrd.sh) 2> "$INITRD_ERR"; then
  cat "$INITRD_ERR"
  echo "FAIL: initrd build failed"
  exit 1
fi
cat "$INITRD_ERR" >&2
```

### 4-2. 검사 1c — 빌드가 `readelf` 에러를 안 냈다(부팅 전)

검사 1b의 마지막 `echo "the initrd ends with the firmware cpio …"` 줄 뒤, `qemu-system-x86_64`
앞에 넣는다.

```bash
# ── 검사 1c: make_initrd.sh가 readelf 에러를 안 냈다 (GE-M0, 정적) ──────
#
# copy_lib_deps는 ELF가 아닌 파일(which 스크립트)을 맨 앞에서 건너뛴다(GE design
# 결정 2). 그 검사를 누가 지우면 빌드는 여전히 초록이다 — readelf -d가 for의 단어
# 목록 안에 있어서 set -e가 실패를 안 보기 때문이다. 그래서 여기서 본다. 덤으로
# 망가진 ELF가 내는 같은 에러도 여기서 빨개진다. 지금까지는 그 경우에도 빌드가
# 초록이었다.
#
# -q를 쓰지 않는다. 파이프가 아니라 파일을 읽으므로 SIGPIPE는 없지만, 찾은 줄이
# 실패 메시지와 함께 보이는 것이 진단이다.
if grep -a "readelf: Error" "$INITRD_ERR"; then
  echo "FAIL: make_initrd.sh printed a readelf error (copy_lib_deps read a file it should have skipped, or an ELF is broken)"
  exit 1
fi
echo "make_initrd.sh printed no readelf error"
```

### 4-3. 검사 22 — `which`가 `PATH`를 훑는다(부팅 뒤)

검사 21의 마지막 `echo "init raised lo"` 뒤, `# ── 검사 19: 음성 확인` 앞에 넣는다.

```bash
# ── 검사 22: which가 PATH를 훑는다 (GE-M0) ──────────────────────────────
#
# 번호가 21 뒤이고 자리는 19 앞이다. 19는 음성 확인이라 언제나 맨 뒤다 — 여기서
# which를 못 찾으면 19가 `Unknown command`로 함께 잡는다.
#
# 이 체인의 셸은 fish이고 fish에는 which builtin이 없다. 그래서 여기서 도는 것은
# debianutils의 스크립트다(GE design 결정 1). zsh였다면 builtin이 가렸다.
#
# 판정 글자는 출력에만 생긴다(docs/decisions/project_gate_screen_echo.md).
#   which which                      친 줄에 슬래시가 없다. 출력은 /usr/bin/which
#   which ge-none; echo ge-rc=$status 친 줄에는 $status가 있다. 출력은 ge-rc=1
# 둘째 줄은 종료 코드의 약속을 본다 — 못 찾으면 아무것도 안 찍고 1. 스크립트가
# `if which foo >/dev/null`로 쓰는 것이 그 약속이다. fish가 which 자체를 못
# 찾았다면 127이므로 패턴이 1 뒤에 공백이나 줄 끝을 요구한다. fish의 종료 코드
# 변수는 $status다($?를 치면 fish가 에러를 낸다).
echo "=== typing 'which which' ==="
type_keys w h i c h spc w h i c h ret

if ! wait_for_screen "/usr/bin/which"; then
  fail "which did not find itself on PATH" \
    "terminal: screen>" "Unknown command"
fi

echo "=== typing 'which ge-none; echo ge-rc=\$status' ==="
type_keys w h i c h spc g e minus n o n e semicolon spc \
          e c h o spc g e minus r c equal shift-4 s t a t u s ret

if ! wait_for_screen 'ge-rc=1( |$)'; then
  fail "which did not exit 1 for a name that is not on PATH" \
    "terminal: screen>" "ge-rc=" "Unknown command"
fi
echo "which found itself on PATH and exited 1 for a name it could not find"
```

### 4-4. 주석 둘

- 파일 머리의 체인 설명(`# SM-M0이 도구 둘(zoxide · fzf)을 더하고` 문단) 뒤에 한 문단을 붙인다.

  ```
  # GE-M0이 which를 더하고 검사 둘을 더한다 — 1c는 부팅 전에 make_initrd.sh의
  # stderr에 readelf 에러가 없는 것을, 22는 부팅 뒤에 which가 PATH를 훑고 못 찾으면
  # 1로 끝나는 것을 본다. which는 이 목록에서 ELF가 아닌 첫 도구다.
  ```

- 검사 19의 주석 "ls · ps · awk · sed · eza · fd · jq · git · vi · fzf · zoxide 열하나를 다 친 뒤에"
  문단 끝에 한 문장을 붙인다. 개수는 다시 세지 않는다.

  ```
  # 그 뒤에 더해진 것(LB-M3의 nc, GE-M0의 which)도 같은 그물에 걸린다.
  ```

### 4-5. 진입 검사와 체인 한 번

lessons "게이트를 돌리고 읽는 법"의 `ENTRY-OK` 명령을 `X`를 `tools`로 바꿔 친다.

```bash
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./tools/check.sh && require_no_early_exit_pipe ./tools/check.sh &&
  require_explicit_nic ./tools/check.sh && echo ENTRY-OK'
```

기대: `ENTRY-OK`. 그다음 체인을 한 번 돌린다(약 1분, CU-M1 실측 4에서 57.0초).

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./tools/check.sh > /tmp/tools.log 2>&1 ; } 2> /tmp/tools.time
tail -5 /tmp/tools.log; cat /tmp/tools.time
grep -E 'readelf|which|ge-rc|tools the list names' /tmp/tools.log
```

기대하는 줄:

```
the initrd carries the four bones and all 87 tools the list names
make_initrd.sh printed no readelf error
which found itself on PATH and exited 1 for a name it could not find
PASS
```

`87`은 Task 3의 4에서 잰 값이다(86 + 1이라는 셈). 구현자는 여기까지 하고 결과를 보고한다.

## Task 5: 게이트와 mutation(lead)

모두 컨테이너에서 한다. 체인은 하나씩, 겹치지 않게 돌린다.

1. `tools/check.sh` 한 번(Task 4-5와 같은 명령). 통과한 회차의 화면을 확인하려면 lessons "범용
   명령"의 첫 블록(`net/check.sh`를 `tools/check.sh`로 바꾼다)으로 시리얼 로그를 꺼내 검사 22
   자리의 마지막 `screen>` 줄을 행으로 풀어 실측 절에 옮긴다.
2. mutation 둘. 저장소 파일은 안 고치고 사본을 `-v`로 덮는다. 돌리기 전에 `diff`로 사본에
   편집이 들어갔는지 본다(lessons 실측 52).

   (a) ELF 검사를 끈다. Task 3의 6과 같은 사본이다.

   ```bash
   mkdir -p /tmp/run
   cp kernel/make_initrd.sh /tmp/run/make_initrd.sh
   sd -F 'if [ "$(head -c 4 "$bin"' 'if false && [ "$(head -c 4 "$bin"' /tmp/run/make_initrd.sh
   chmod +x /tmp/run/make_initrd.sh; diff kernel/make_initrd.sh /tmp/run/make_initrd.sh
   docker run --rm -v "$PWD":/workspace \
     -v /tmp/run/make_initrd.sh:/workspace/kernel/make_initrd.sh:ro \
     -w /workspace tars-devcontainer ./tools/check.sh > /tmp/mut_a.log 2>&1; echo "exit=$?"
   tail -4 /tmp/mut_a.log
   ```

   기대: 부팅 전에 검사 1c가 빨갛다(1분 안).

   ```
   readelf: Error: Not an ELF file - it has the wrong magic bytes at the start
   FAIL: make_initrd.sh printed a readelf error (copy_lib_deps read a file it should have skipped, or an ELF is broken)
   ```

   (b) `which` 줄을 지운다. `make_initrd.sh`와 `tools/check.sh`가 같은 사본을 source한다.

   ```bash
   cp kernel/guest_tools.sh /tmp/run/guest_tools.sh
   sd -F '  usr/bin/which.debianutils:usr/bin/which' '' /tmp/run/guest_tools.sh
   diff kernel/guest_tools.sh /tmp/run/guest_tools.sh
   docker run --rm -v "$PWD":/workspace \
     -v /tmp/run/guest_tools.sh:/workspace/kernel/guest_tools.sh:ro \
     -w /workspace tars-devcontainer ./tools/check.sh > /tmp/mut_b.log 2>&1; echo "exit=$?"
   grep -E 'tools the list names|readelf|FAIL' /tmp/mut_b.log
   ```

   기대: 검사 1은 초록이고 도구 수가 하나 적다(목록을 되읽는 tautology라서 — 그 검사의 주석이
   말하는 그대로다). 검사 1c도 초록이다. 검사 22가 15초를 다 쓰고 빨갛고, 화면 줄에 fish의
   `Unknown command: which`가 보인다.

   ```
   FAIL: which did not find itself on PATH
   ```

   mutation이 예상과 다른 검사에서 죽거나 통과하면 그대로 적는다. 특히 (b)가 초록이면 fish에
   `which`라는 이름의 무언가가 있다는 뜻이고, 결정 3의 전제가 틀린 것이다.
3. regression은 루트 게이트가 맡는다. initrd가 바뀌므로 열여덟 체인이 전부 새 initrd로
   부팅한다. 18체인 × 3, 약 1시간 5분. `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 완료
   알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 본다.

## Task 6: 문서(구현자)

- `docs/guides/lessons.md`의 "핵심 파일" 절, `tools/check.sh` 항목(`rg -n 'tools/check.sh. — 검사'
  docs/guides/lessons.md`). 끝에 한 문장을 붙인다: "GE-M0이 검사 1c(부팅 전, `make_initrd.sh`의
  stderr에 `readelf: Error`가 없다)와 22(`which`)를 더했다. `copy_lib_deps`는 ELF magic이 아닌
  파일을 건너뛰므로 스크립트도 `GUEST_TOOLS`에 넣을 수 있다 — 인터프리터는 따라가지 않는다."
- 이 plan의 "GE-M0이 실측한 것" 절. Task 0 · 1 · 3의 값, Task 4-5의 체인 시간과 기대 줄의 실제
  모양, 이미지 재빌드 시간. lead가 Task 5를 끝내면 mutation 둘과 루트 게이트 시간을 lead가
  더한다.
- `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · design의 `Status:`는 손대지 않는다(design "닫을 때").

## GE-M0이 실측한 것

구현자(Sonnet)가 2026-10-04에 쟀다. Task 5(mutation 둘 · 루트 게이트)의 값은 lead가 이 절에
더한다.

1. Task 0. 돌고 있는 게이트는 없었다(`pgrep` 빈 출력). sysroot의 `usr/bin`에서 `^which`로
   시작하는 파일은 0개였다. 바꾸기 전의 `make_initrd.sh`는 `rc=0`, `readelf errors: 0`이었다.
   `kernel/initrd.cpio`는 압축된 채 89,583,793바이트, `gzip -dc`로 풀면 230,445,056바이트였다.
2. Task 1. 이미지 재빌드는 29.9초였다(선례 27.1초). sysroot의
   `usr/bin/which.debianutils`는 1,080바이트(`-rwxr-xr-x`)이고 첫 줄은 `#! /bin/sh`이며,
   `usr/bin/which`는 `No such file or directory`였다. 전부 기대와 같다.
3. Task 3. `GUEST_TOOLS`는 86개에서 87개가 됐다. 새 `make_initrd.sh`는 `rc=0`, `readelf
   errors: 0`이고 `cpio -it`에 `usr/bin/which`가 한 줄 있다. initrd는 압축된 채 89,579,576바이트
   (4,217바이트 줄었다 — gzip 압축률의 흔들림으로 보이고 재현하려고 하지 않았다), 풀면
   230,446,080바이트다. 압축 전은 정확히 1,024바이트 늘었다(1,080바이트 스크립트 + cpio 머리,
   512바이트 정렬).
4. Task 3의 6(ELF 검사를 끈 사본). `diff`는 한 줄(`if false && …`)이고 `rc=0`이며 `readelf:
   Error`는 한 줄이다. 그러나 plan의 기대와 글자가 다르다. 실제로 나온 줄은
   `readelf: Error: Not an ELF file - it has the wrong magic bytes at the start`이고,
   `Failed to read file header`도 파일 경로(`…/usr/bin/which`)도 없다. 검사 1c의 패턴
   `readelf: Error`는 두 모양 다 잡으므로 판정에는 영향이 없다. Task 5의 mutation (a)가
   기대하는 출력 줄도 이 모양이어야 한다.
5. Task 4-5. 진입 검사는 `ENTRY-OK`였다. `tools` 체인은 58.5초(`docker run` 전체)에 `PASS`로
   끝났고 `FAIL`은 0줄이다(선례 57.0초). 기대한 줄이 그대로 나왔다.

   ```
   the initrd carries the four bones and all 87 tools the list names
   make_initrd.sh printed no readelf error
   which found itself on PATH and exited 1 for a name it could not find
   PASS
   ```

6. Task 5의 mutation 둘(lead, 2026-10-04). 둘 다 사본을 `-v`로 덮었고 `diff`가 한 줄씩이었다.
   - (a) ELF 검사를 끈 사본. 부팅 전에 검사 1c가 빨갰다 — `docker run` 전체가 8.23초, `exit=1`.
     마지막 네 줄은 검사 1(87개) · 검사 1b(firmware 77개)의 초록 줄 뒤에
     `readelf: Error: Not an ELF file - it has the wrong magic bytes at the start`와
     `FAIL: make_initrd.sh printed a readelf error (copy_lib_deps read a file it should have
     skipped, or an ELF is broken)`이다. 실측 4대로 메시지는 `wrong magic bytes` 모양이었다.
   - (b) `which` 줄을 지운 사본. 1분 15.87초, `exit=1`. 검사 1은 초록이고 도구 수가 86이었다
     (tautology — 목록을 되읽는다). 검사 1c도 초록(`make_initrd.sh printed no readelf error`).
     검사 22가 15초를 다 쓰고 `FAIL: which did not find itself on PATH`로 빨갰고, 마지막 `screen>`
     줄의 끝이 `root@(none) /t/r (main)# which which | fish: Unknown command: which |
     root@(none) /t/r (main) [127]#`이다. 결정 3의 전제(fish에 `which`가 없다)가 그대로 맞다.
7. 루트 게이트(lead, 2026-10-04). 18체인 × 3이 전부 통과했다 — `TARS check PASS: all chains 3/3
   consecutive runs succeeded`, 1시간 5분 51.88초(선례 CU-M1 1시간 5분 31초). `skipping make`는
   53회로 18 × 3 − 1과 같다. `FAIL` 줄은 0이다. M1 구현자는 이 게이트가 도는 동안 별도 worktree에서
   편집만 했고 docker는 돌리지 않았다.
