# UT-M0 Implementation Plan — 통로를 연다

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: 게스트 셸이 `/usr/bin/ls`가 아니라 `ls`로 명령을 찾게 하고, git이
딛고 설 뼈대(`/bin/sh` · `/tmp` · `/etc/passwd`)를 세운다.

Architecture: PID 1이 커널의 envp 블록을 복사해 `PATH=/usr/bin:/bin`을 더한
새 블록을 짓고 자식 둘에게 넘긴다(design 결정 1). 블록을 짓는 순수 함수는
`init/src/environ.zig`에 따로 두어 호스트에서 초 단위로 검사한다 —
`config.zig`·`storage.zig`가 이미 그렇게 갈려 있다. `make_initrd.sh`는 뼈대
넷과 `ls` 하나만 넣는다. 열한번째 게이트 체인 `tools/check.sh`가 본다.

Tech Stack: Zig 0.16(자유 서기 PID 1, 힙 없음) · bash · cpio/gzip ·
QEMU monitor `sendkey`

읽고 시작할 것: `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
— 특히 결정 1 · 결정 6 · 위험 1과 "시리얼 셸은 관측하지 않는다" 절.

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `init/src/environ.zig` | 커널 envp 블록에 `PATH` 하나를 더한 블록을 짓는다. 시스템 콜을 안 한다 | 새로 만든다 |
| `init/src/environ_test.zig` | 위 함수의 호스트 검사 넷 | 새로 만든다 |
| `init/build.zig` | `environ_test`를 `zig build test`에 엮는다 | 고친다 |
| `init/src/main.zig` | `environ.withPath`를 부르고 결과를 로그에 찍는다 | 고친다(약 10줄) |
| `kernel/make_initrd.sh` | 뼈대 넷 + `/usr/bin/ls` | 고친다 |
| `tools/check.sh` | 열한번째 체인 | 새로 만든다 |
| `check.sh` | `CHAINS`에 `UT-M0:./tools/check.sh` | 고친다(한 줄 + 주석) |

`environ.zig`를 따로 빼는 이유가 검사다. `main.zig`에는 `*_test.zig`가
없다 — PID 1의 감독 루프는 호스트에서 못 돌린다. 블록을 짓는 일은 시스템 콜이
없는 순수 계산이므로 갈라내면 부팅 20초가 아니라 0.1초로 검사된다.
`devices.zig`가 `bitSet`을 그렇게 가른 것과 같은 선이다.

---

## Task 0: 크기를 먼저 잰다 — 위험 1

이 Task가 첫째인 이유: 답이 "못 뜬다"면 UT-M1~M3의 목록이 통째로 바뀐다.
코드를 한 줄도 안 고친다.

Files:
- Create: `/tmp/ut_m0_spike.sh` (임시. 커밋하지 않는다)

- [ ] Step 1: 지금 initrd의 기준선을 만든다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  (cd kernel && ./build.sh)
  (cd init && zig build)
  (cd terminal && ./prepare.sh)
  (cd kernel && ./make_initrd.sh)
  echo "BASELINE gzip:  $(stat -c %s kernel/initrd.cpio)"
  echo "BASELINE plain: $(gzip -dc kernel/initrd.cpio | wc -c)"
'
```

Expected: `BASELINE gzip: 11076327` 부근, `BASELINE plain: 33371648` 부근.
(design 실측 12와 같은 수여야 한다. 크게 다르면 여기서 멈추고 왜 다른지
먼저 밝힌다 — 기준선이 틀리면 아래 비교가 전부 무의미하다.)

- [ ] Step 2: 스파이크 스크립트를 만든다

`/tmp/ut_m0_spike.sh`에 넣을 것 — 진짜 바이너리를 밸러스트로 쓴다. 난수나
0으로 채우면 압축률이 실제와 달라서 답이 틀린다(난수는 안 줄고 0은 통째로
사라진다).

```bash
#!/usr/bin/env bash
set -euo pipefail

dpkg --add-architecture amd64 >/dev/null 2>&1
apt-get update >/dev/null 2>&1

# **산출물은 /workspace 아래에 둔다.** docker run --rm은 매번 새 컨테이너라
# /tmp에 남긴 것이 다음 실행에서 사라진다 — 그러면 Step 4가 읽을 것이 없다.
OUT=/workspace/ut-spike
rm -rf "$OUT"; mkdir -p "$OUT"

STAGE=/tmp/ut-stage
rm -rf /tmp/ut-debs "$STAGE"; mkdir -p /tmp/ut-debs "$STAGE"

# design의 최종 목록 전부 + 그것이 데려오는 라이브러리.
(cd /tmp/ut-debs && apt-get download -qq \
  eza:amd64 bat:amd64 fd-find:amd64 ripgrep:amd64 sd:amd64 procs:amd64 \
  duf:amd64 htop:amd64 tree:amd64 ncdu:amd64 jq:amd64 hyperfine:amd64 \
  git:amd64 vim-tiny:amd64 \
  grep:amd64 findutils:amd64 sed:amd64 mawk:amd64 diffutils:amd64 \
  procps:amd64 less:amd64 util-linux:amd64 \
  libgit2-1.9:amd64 libssl3t64:amd64 libssh2-1t64:amd64 zlib1g:amd64 \
  libhttp-parser2.9:amd64 libmbedtls21:amd64 libmbedcrypto16:amd64 \
  libmbedx509-7:amd64 libgssapi-krb5-2:amd64 libkrb5-3:amd64 \
  libk5crypto3:amd64 libkrb5support0:amd64 libkeyutils1:amd64 \
  libcom-err2:amd64 libzstd1:amd64 libncursesw6:amd64 libjq1:amd64 \
  libonig5:amd64 libacl1:amd64 libproc2-0:amd64)

for d in /tmp/ut-debs/*.deb; do dpkg -x "$d" "$STAGE"; done

# 지금 initrd를 풀고, 그 위에 밸러스트를 얹는다.
WORK=/tmp/ut-work
rm -rf "$WORK"; mkdir -p "$WORK"
(cd "$WORK" && gzip -dc /workspace/kernel/initrd.cpio | cpio -id --quiet)

mkdir -p "$WORK/usr/bin" "$WORK/lib/x86_64-linux-gnu"

# 바이너리: 우리가 실제로 넣을 것만. git-core의 네트워크 헬퍼 일곱은
# **일부러 뺀다**(design 결정 5) — 넣으면 16MB를 과대 계상한다.
for b in eza batcat rg sd procs duf htop tree ncdu jq hyperfine \
         grep sed mawk less ps top dmesg diff cmp find xargs; do
  f="$(find "$STAGE" -type f -name "$b" | head -1)"
  [ -n "$f" ] && cp "$f" "$WORK/usr/bin/$b"
done
cp "$STAGE/usr/lib/cargo/bin/fd"     "$WORK/usr/bin/fd"
cp "$STAGE/usr/lib/git-core/git"     "$WORK/usr/bin/git"
cp "$STAGE/usr/bin/vim.tiny"         "$WORK/usr/bin/vim"

# coreutils 35개는 sysroot에서 온다(이미 컨테이너에 구워져 있다).
for b in ls cp mv rm ln rmdir head tail sort uniq wc cut tr date df du stat \
         touch chmod chown readlink realpath echo pwd env dirname basename \
         seq id whoami tee sync; do
  cp "/usr/local/amd64-sysroot/usr/bin/$b" "$WORK/usr/bin/$b"
done

# 라이브러리 20개.
for so in libgit2.so.1.9 libcrypto.so.3 libkrb5.so.3 libgssapi_krb5.so.2 \
          libk5crypto.so.3 libkrb5support.so.0 libkeyutils.so.1 \
          libcom_err.so.2 libmbedcrypto.so.16 libmbedtls.so.21 \
          libmbedx509.so.7 libssh2.so.1 libzstd.so.1 libz.so.1 \
          libhttp_parser.so.2.9 libncursesw.so.6 libjq.so.1 libonig.so.5 \
          libacl.so.1 libproc2.so.0; do
  f="$(find "$STAGE" -name "$so" -type f | head -1)"
  [ -n "$f" ] && cp "$f" "$WORK/lib/x86_64-linux-gnu/$so"
done

echo "=== 밸러스트를 얹은 트리 ==="
du -sb "$WORK"

for algo in "gzip -6" "zstd -19 -T0 -q" "xz -9 -T0"; do
  name="${algo%% *}"
  start=$(date +%s%N)
  (cd "$WORK" && find . | cpio -o -H newc --quiet) | $algo > "$OUT/initrd.$name"
  end=$(date +%s%N)
  printf "%-5s  %10d bytes  %6d ms\n" \
    "$name" "$(stat -c %s "$OUT/initrd.$name")" "$(( (end-start)/1000000 ))"
done
```

`zstd`와 `xz`가 컨테이너에 없을 수 있다. `xz-utils`는 Dockerfile에 있고
`zstd`는 없다. 없으면 그 줄만 건너뛰고 `gzip`으로 판정한다 — 스파이크가 그것
때문에 죽으면 안 되므로 위 루프 앞에 한 줄을 둔다.

```bash
command -v zstd >/dev/null || echo "NOTE: zstd is not installed; skipping it"
```

그리고 루프 안 첫 줄에:

```bash
  command -v "$name" >/dev/null || { echo "$name: not installed, skipped"; continue; }
```

- [ ] Step 3: 스파이크를 돌린다

호스트의 `/tmp`는 컨테이너 안에서 안 보인다(마운트되는 것은 저장소뿐이다).
스크립트를 저장소 안에 잠깐 두고 부른다.

```bash
cp /tmp/ut_m0_spike.sh ./ut_m0_spike.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash ut_m0_spike.sh 2>&1 | tail -20
rm -f ./ut_m0_spike.sh
```

`git status --short`를 확인한다. `ut_m0_spike.sh`는 지웠고 `ut-spike/`는
Step 5에서 지운다 — 둘 다 커밋하지 않는다.

Expected: 세 줄이 나온다.

```
gzip     ~30,000,000 bytes   ~5,000 ms
zstd     ~2x,000,000 bytes   ~x,xxx ms
xz       ~2x,000,000 bytes   ~xx,xxx ms
```

숫자를 그대로 적어 둔다. 아래 Step 5가 이것을 쓴다.

- [ ] Step 4: 그 initrd로 실제로 부팅해 시간을 잰다

`boot/check.sh`는 자기 initrd를 다시 만들므로 못 쓴다. 직접 띄운다.

원본 initrd를 저장소 안에 잠깐 치워 둔다 — 컨테이너가 매번 새로 뜨므로
`/tmp`에 두면 안 된다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  cp kernel/initrd.cpio ut-spike/initrd.orig
  for which in orig ut; do
    if [ "$which" = "ut" ]; then cp ut-spike/initrd.gzip kernel/initrd.cpio; fi
    (cd boot && ./build.sh && ./make_iso.sh)
    LOG=$(mktemp)
    S=$(date +%s)
    timeout 300 qemu-system-x86_64 -cdrom out/tars.iso -m 512 \
      -serial file:"$LOG" -display none -no-reboot &
    P=$!
    for _ in $(seq 1 300); do
      grep -aq "Welcome to fish" "$LOG" && break
      kill -0 $P 2>/dev/null || break
      sleep 1
    done
    E=$(date +%s)
    kill $P 2>/dev/null || true; wait $P 2>/dev/null || true
    if grep -aq "Welcome to fish" "$LOG"; then
      echo "RESULT ${which}: booted in $((E-S))s  (initrd $(stat -c %s kernel/initrd.cpio) bytes)"
    else
      echo "RESULT ${which}: DID NOT BOOT in $((E-S))s"
      tail -20 "$LOG"
    fi
  done
  cp ut-spike/initrd.orig kernel/initrd.cpio
'
```

마지막 줄이 원본을 되돌리는 것이 중요하다. 안 되돌리면 다음 Task들이
밸러스트가 든 initrd 위에서 돌고, 그 사실이 어디에도 안 적혀 있어 원인을
찾기 어렵다.

Expected: 두 줄. `RESULT orig: booted in Ns` 와 `RESULT ut: booted in Ms`.

- [ ] Step 5: 판정하고 기록한다

| 결과 | 무엇을 한다 |
|---|---|
| `ut`가 뜨고 `orig`보다 10초 이내로 느리다 | `gzip -6`을 유지한다. 아무것도 안 고친다 |
| `ut`가 뜨는데 크게 느리다 | `zstd`로 바꾼다 — 압축이 작고 푸는 것이 gzip보다 빠르다 |
| `ut`가 안 뜬다 | `xz`로 다시 Step 4를 돌린다. 그래도 안 뜨면 여기서 멈추고 사용자에게 목록 축소를 묻는다 |

`gzip -9`는 답이 아니다. GL-M1이 이미 쟀다 — `-6`보다 1.3% 작아지자고
6.7초를 더 쓰고, 루트 게이트가 그 6.7초를 24회 치른다.

치운다.

```bash
rm -rf ut-spike
git status --short
```

Expected: `git status --short`가 비어 있다. 이 Task는 저장소를 안 고친다 —
비어 있지 않으면 치우다 만 것이 있다.

- [ ] Step 6: 커밋하지 않는다

측정만 했다. 결과는 Task 6에서 design의 실측 절에 적는다.

---

## Task 1: `environ.zig` — 블록을 짓는 순수 함수

Files:
- Create: `init/src/environ.zig`
- Create: `init/src/environ_test.zig`
- Modify: `init/build.zig`

- [ ] Step 1: 검사를 먼저 쓴다

`init/src/environ_test.zig`:

```zig
const std = @import("std");
const environ = @import("environ.zig");

/// 커널이 준 것처럼 생긴 가짜 블록. 실제 커널의 envp_init은 둘이다
/// (`HOME=/` · `TERM=linux`, linux/init/main.c).
var fake: [environ.MAX_ENTRIES:null]?[*:0]const u8 = undefined;

/// entries를 fake에 채우고 null로 닫은 뒤 그 포인터를 돌려준다.
fn kernelBlock(entries: []const [:0]const u8) [*:null]const ?[*:0]const u8 {
    for (entries, 0..) |e, i| fake[i] = e.ptr;
    fake[entries.len] = null;
    return &fake;
}

/// 돌려받은 블록의 항목 수를 센다.
fn count(block: [*:null]const ?[*:0]const u8) usize {
    var n: usize = 0;
    while (block[n] != null) n += 1;
    return n;
}

/// n번째 항목이 want와 같은가.
fn entryIs(block: [*:null]const ?[*:0]const u8, n: usize, want: []const u8) bool {
    const got = block[n] orelse return false;
    return std.mem.eql(u8, std.mem.span(got), want);
}

pub fn main() !void {
    var buf: environ.Block = undefined;

    // ── 1. 정상 경로: 커널이 준 둘 뒤에 PATH가 붙는다 ──────────────────
    //
    // 이것이 이 파일의 심장이다. 순서까지 보는 이유는 덮어쓰는 구현
    // (buf[0]에 PATH를 넣고 나머지를 미는 것)도 개수 검사만으로는 통과하기
    // 때문이다.
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withPath(kernel, &buf);

        if (count(got) != 3) {
            std.debug.print("FAIL: want 3 entries, got {d}\n", .{count(got)});
            return error.WrongCount;
        }
        if (!entryIs(got, 0, "HOME=/") or !entryIs(got, 1, "TERM=linux")) {
            std.debug.print("FAIL: the kernel's own entries did not survive in order\n", .{});
            return error.LostKernelEntries;
        }
        if (!entryIs(got, 2, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: PATH was not appended last\n", .{});
            return error.NoPath;
        }
    }

    // ── 2. 대조군: 커널이 아무것도 안 줬다 ─────────────────────────────
    //
    // 커널은 늘 둘을 주지만, 그 사실에 기대는 구현(예: 무조건 buf[2]에 쓰는
    // 것)을 여기서 잡는다.
    {
        const kernel = kernelBlock(&.{});
        const got = environ.withPath(kernel, &buf);
        if (count(got) != 1 or !entryIs(got, 0, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: an empty kernel block did not yield exactly PATH\n", .{});
            return error.EmptyBlockWrong;
        }
    }

    // ── 3. 넘치면 원본을 그대로 돌려준다 ───────────────────────────────
    //
    // **PATH가 없는 것이 부팅이 안 되는 것보다 낫다.** 버퍼를 넘겨 쓰면
    // PID 1이 스택을 밟고 기계가 아예 안 켜진다 — 증상이 원인에서 가장 먼
    // 종류다.
    {
        var many: [environ.MAX_ENTRIES]([:0]const u8) = undefined;
        for (&many) |*m| m.* = "X=1";
        const kernel = kernelBlock(many[0 .. environ.MAX_ENTRIES - 1]);
        const got = environ.withPath(kernel, &buf);
        if (got != kernel) {
            std.debug.print("FAIL: an oversized block should have been passed through untouched\n", .{});
            return error.OverflowNotPassedThrough;
        }
    }

    // ── 4. PATH 값이 design 결정 1과 같다 ──────────────────────────────
    //
    // 자리가 둘인 것에 뜻이 있다 — 도구는 전부 /usr/bin에 있고 /bin에는
    // sh 하나만 있다(design 결정 6). 이 문자열이 바뀌면 make_initrd.sh가
    // 넣는 자리와 어긋나고, 증상은 "어떤 명령도 안 찾아진다"다.
    if (!std.mem.eql(u8, environ.PATH_ENTRY, "PATH=/usr/bin:/bin")) {
        std.debug.print("FAIL: PATH_ENTRY is '{s}'\n", .{environ.PATH_ENTRY});
        return error.WrongPathValue;
    }

    std.debug.print("environ_test: PATH is appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
}
```

- [ ] Step 2: 검사를 build.zig에 엮는다

`init/build.zig`의 `storage_test` 블록 바로 뒤에 넣을 것:

```zig
    // UT-M0: 커널 envp 블록에 PATH를 더하는 함수의 검사. storage_test와 같은
    // 이유로 host_target이다 — environ.zig는 시스템 콜을 하나도 안 하는 순수
    // 계산이라 게스트가 필요 없다. main.zig에 두면 이 검사가 원리적으로
    // 불가능해진다(PID 1의 감독 루프는 호스트에서 못 돈다).
    const environ_test_mod = b.createModule(.{
        .root_source_file = b.path("src/environ_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const environ_test = b.addExecutable(.{
        .name = "environ_test",
        .root_module = environ_test_mod,
    });
```

그리고 `test_step` 목록의 마지막 줄 뒤에 한 줄:

```zig
    test_step.dependOn(&b.addRunArtifact(environ_test).step);
```

- [ ] Step 3: 검사가 실패하는 것을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build test' 2>&1 | tail -20
```

Expected: 컴파일 에러. `unable to load '.../src/environ.zig'` 또는
`import of file outside module path`. 아직 그 파일이 없다.

이것이 SH-M0 실측 2가 말한 "예측한 그 모양의 실패"다 — 부를 것이 없는
실패이지 뜻이 틀린 실패가 아니다.

- [ ] Step 4: `environ.zig`를 만든다

`init/src/environ.zig`:

```zig
//! 게스트에 넘길 환경 변수 블록.
//!
//! 커널은 PID 1에게 딱 둘을 준다(linux/init/main.c의 envp_init):
//!
//!     const char *envp_init[] = { "HOME=/", "TERM=linux", NULL, };
//!
//! 지금까지 PID 1은 이 블록을 **그대로** 자식에게 넘겼고, 그래서 게스트에
//! PATH가 없었다 — 셸이 명령을 이름으로 못 찾고 절대 경로만 먹었다
//! (docs/decisions/project_guest_environment.md의 "결과 1").
//!
//! **PATH를 PID 1이 더하는 이유**는 그것이 자식마다 갈릴 이유가 없는 값이기
//! 때문이다. TERM은 갈려야 맞아서(화면 셸은 xterm-256color, 시리얼 콘솔 셸은
//! linux) terminal 쪽 setenv에 있고, LANG은 갈릴 이유가 없는데도 거기 있다 —
//! 같은 문서가 그것을 자기비판으로 적어 뒀다. **여기가 그 실수를 반복하지
//! 않는 자리다**(design 결정 1).
//!
//! 시스템 콜을 하나도 안 한다. 그래서 environ_test.zig가 호스트에서 돈다.

const std = @import("std");

/// 게스트의 PATH. **자리가 둘인 것에 뜻이 있다** — 도구는 전부 /usr/bin에
/// 넣고 /bin에는 sh 하나만 둔다(design 결정 6). 이 문자열과
/// kernel/make_initrd.sh가 넣는 자리가 어긋나면 증상은 "어떤 명령도 안
/// 찾아진다"이고 원인에서 멀다.
pub const PATH_ENTRY: [:0]const u8 = "PATH=/usr/bin:/bin";

/// 새 블록에 들어갈 수 있는 항목 수. 커널이 주는 것은 둘이고 커널 상수
/// MAX_INIT_ENVS까지 늘 수 있다. 여유를 크게 둔다 — 이 배열은 main()의
/// 스택에 살고 한 항목이 포인터 8바이트라 128바이트다.
pub const MAX_ENTRIES: usize = 16;

/// 부르는 쪽이 스택에 잡아 주는 자리. main()의 지역 변수여야 한다 —
/// supervise()가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다
/// (main.zig의 keyboard_path·argv와 같은 근거다).
pub const Block = [MAX_ENTRIES:null]?[*:0]const u8;

/// 커널이 준 블록을 buf에 복사하고 끝에 PATH를 붙인 뒤 buf를 돌려준다.
///
/// **자리가 모자라면 커널 블록을 그대로 돌려준다.** PATH가 없는 게스트는
/// 불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다.
/// HD 결정 6("못 찾아도 부팅을 막지 않는다")과 같은 종류의 선택이다.
pub fn withPath(
    kernel: [*:null]const ?[*:0]const u8,
    buf: *Block,
) [*:null]const ?[*:0]const u8 {
    var n: usize = 0;
    while (kernel[n]) |entry| : (n += 1) {
        // buf[n]에 이 항목, buf[n+1]에 PATH, buf[n+2]에 닫는 null이
        // 들어가야 한다. 셋이 다 안 들어가면 아예 손대지 않는다.
        if (n + 2 >= MAX_ENTRIES) return kernel;
        buf[n] = entry;
    }
    buf[n] = PATH_ENTRY.ptr;
    buf[n + 1] = null;
    return buf;
}
```

- [ ] Step 5: 검사가 통과하는 것을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build test' 2>&1 | tail -20
```

Expected: 다섯 줄이 `config_test:` · `power_test:` · `devices_test:` ·
`storage_test:` · `environ_test:` 로 시작하고 종료 코드가 0이다.

마지막 줄이 이래야 한다.

```
environ_test: PATH is appended to the kernel's block (16 slots)
```

- [ ] Step 6: 커밋

```bash
git add init/src/environ.zig init/src/environ_test.zig init/build.zig
git commit -m "Build the guest environment block instead of passing it through"
```

---

## Task 2: `main.zig`가 그 블록을 쓴다

Files:
- Modify: `init/src/main.zig:418` 부근 (envp를 잡는 자리)

- [ ] Step 1: import를 더한다

`init/src/main.zig`의 import 목록에서 `storage` 옆에 넣을 것:

```zig
const environ = @import("environ.zig");
```

(`const config = @import("config.zig");` 같은 줄들이 파일 머리에 모여 있다.
그 무리의 끝에 붙인다.)

- [ ] Step 2: envp를 잡는 두 줄을 바꾼다

지울 것 (`init/src/main.zig:416-418`):

```zig
pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록.
    const envp = init.environ.block.slice.ptr;
```

넣을 것:

```zig
pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록. 커널은 둘만 준다
    // (HOME=/ · TERM=linux) — PATH가 없어서 게스트 셸이 명령을 이름으로
    // 못 찾았다.
    //
    // **이 버퍼가 main()의 스택에 있는 것이 중요하다.** supervise()가 영영
    // 반환하지 않으므로 프로세스 수명 내내 유효하다 — keyboard_path·argv와
    // 같은 근거다. 자식은 fork 뒤 execve로 이 포인터를 읽는다.
    var env_buf: environ.Block = undefined;
    const envp = environ.withPath(init.environ.block.slice.ptr, &env_buf);
```

- [ ] Step 3: 로그 한 줄을 더한다

시리얼 콘솔 셸은 관측할 수 없으므로(design의 "시리얼 셸은 관측하지 않는다"
절) init이 무엇을 넘겼는지를 직접 찍는다. 이것이 게이트가 블록을 보는 유일한
자리다.

`std.debug.print("tars-init: starting as PID 1\n", .{});` 바로 뒤에 넣을 것:

```zig
    // UT-M0: 게이트가 "블록을 제대로 지었는가"를 보는 자리. 자식 둘이 같은
    // 블록을 받는다는 것은 supervise()가 start(c, envp)를 한 루프에서
    // 부르는 코드 구조가 보장한다 — 시리얼 콘솔 셸에 타이핑한 체인이
    // 저장소에 하나도 없어서 그쪽은 관측이 아니라 구조로 안다.
    //
    // withPath가 자리 부족으로 폴백했으면 이 줄이 안 나온다. 그 침묵이
    // 곧 판정이다.
    if (envp != init.environ.block.slice.ptr) {
        std.debug.print("tars-init: env {s}\n", .{environ.PATH_ENTRY});
    } else {
        std.debug.print("tars-init: env unchanged (no room for PATH)\n", .{});
    }
```

- [ ] Step 4: 빌드가 되는지 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build && zig build test' 2>&1 | tail -10
```

Expected: 에러 없음, 검사 다섯 통과.

- [ ] Step 5: 커밋

```bash
git add init/src/main.zig
git commit -m "Hand the children a PATH the kernel never gave us"
```

---

## Task 3: initrd에 뼈대 넷과 `ls` 하나

Files:
- Modify: `kernel/make_initrd.sh`

- [ ] Step 1: 디렉터리를 만드는 줄을 넓힌다

지울 것 (`kernel/make_initrd.sh:78-79`):

```bash
mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev" \
         "$WORKDIR/config"
```

넣을 것:

```bash
# UT-M0이 /bin · /tmp · /etc 셋을 더한다. 지금까지 없었고, 그 없음이 git에
# 그대로 걸린다(design 실측 2).
#
#   /bin   → sh 하나만 산다. #!/bin/sh 스크립트와 git의 셸 서브커맨드가
#            이 경로를 컴파일 타임에 박아 두고 찾는다.
#   /tmp   → git도 편집기도 임시 파일을 여기 만든다. 없으면 조용히 실패한다.
#   /etc   → passwd·group. whoami가 이름을 내고, git이 커밋 작성자를
#            유추할 자리다.
mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev" \
         "$WORKDIR/config" "$WORKDIR/bin" "$WORKDIR/tmp" "$WORKDIR/etc"

# /tmp는 아무나 쓰고 남의 것은 못 지운다. 게스트가 지금은 root 하나뿐이라
# 동작 차이가 없지만, 이 비트가 없는 /tmp를 보고 겁내는 프로그램이 있다.
chmod 1777 "$WORKDIR/tmp"
```

- [ ] Step 2: `ls`를 넣는다

`cp "$SYSROOT/usr/bin/sleep" ...` 줄 바로 뒤, `chmod 0755 ...` 줄 앞에
넣을 것:

```bash
# UT-M0: **`ls` 하나만 넣는다.** 통로(PATH)가 열렸는지를 도구 50개와 섞지
# 않는다 — 실패하면 원인이 하나뿐이다. 나머지는 UT-M1이 목록 배열과 함께
# 가져온다(design 결정 7).
cp "$SYSROOT/usr/bin/ls" "$WORKDIR/usr/bin/ls"
```

그리고 `chmod` 줄과 `copy_lib_deps` 줄에 `ls`를 더한다.

지울 것:

```bash
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" \
           "$WORKDIR/usr/bin/mkdir" "$WORKDIR/usr/bin/sleep"
```

넣을 것:

```bash
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" \
           "$WORKDIR/usr/bin/mkdir" "$WORKDIR/usr/bin/sleep" \
           "$WORKDIR/usr/bin/ls"
```

지울 것:

```bash
copy_lib_deps "$WORKDIR/usr/bin/sleep"
```

넣을 것:

```bash
copy_lib_deps "$WORKDIR/usr/bin/sleep"
# ls는 libselinux1을 요구한다. 이미 initrd에 있지만(fish가 끌고 왔다)
# 그 사실에 기대지 않는다 — copy_lib_deps는 이미 있는 것을 건너뛴다.
copy_lib_deps "$WORKDIR/usr/bin/ls"
```

- [ ] Step 3: `/bin/sh`와 `/etc`를 만든다

`copy_lib_deps` 무리 바로 뒤에 넣을 것:

```bash
# /bin/sh는 **언제나 bash다.** tars.conf의 shell 설정과 무관하다 —
# #!/bin/sh 스크립트의 동작이 사용자의 셸 취향에 따라 달라지면 안 된다
# (design 결정 6). 셋 중 bash만이 POSIX sh 모드를 갖는다.
#
# 상대 경로로 건다. cpio가 링크의 내용을 그대로 담고 게스트의 루트가
# 곧 이 트리라 절대 경로도 맞지만, 상대로 두면 이 트리를 다른 자리에
# 풀어 봐도 끊어지지 않는다.
ln -sf ../usr/bin/bash "$WORKDIR/bin/sh"

# passwd가 없으면 whoami가 이름 대신 "cannot find name for user ID 0"을
# 내고, **git이 커밋 작성자를 유추하려다 실패한다.** 한 줄이면 된다.
#
# 셸을 /bin/sh로 적는 것에 뜻이 있다 — 위의 링크와 같은 자리를 가리켜야
# 하고, tars.conf가 셸을 바꿔도 이 줄은 안 바뀐다.
cat > "$WORKDIR/etc/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
EOF
cat > "$WORKDIR/etc/group" <<'EOF'
root:x:0:
EOF
```

- [ ] Step 4: initrd를 만들고 눈으로 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd kernel && ./build.sh) && (cd init && zig build) &&
  (cd terminal && ./prepare.sh) && (cd kernel && ./make_initrd.sh) &&
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null |
    grep -E "^\./(bin|tmp|etc|usr/bin/ls)" | sort
'
```

Expected: 정확히 다섯 줄.

```
./bin
./bin/sh
./etc
./etc/group
./etc/passwd
./tmp
./usr/bin/ls
```

(일곱 줄이다 — `./bin`과 `./etc`와 `./tmp` 디렉터리 셋이 함께 나온다.)

- [ ] Step 5: 커밋

```bash
git add kernel/make_initrd.sh
git commit -m "Give the guest a /bin/sh, a /tmp, an /etc and one real ls"
```

---

## Task 4: 열한번째 체인 `tools/check.sh`

Files:
- Create: `tools/check.sh`
- Modify: `check.sh`

- [ ] Step 1: 체인을 만든다

`tools/check.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# UT 체인 — 게스트가 명령을 **이름으로** 찾는가.
#
# 이 게이트가 증명하는 사슬 전체:
#   커널이 PID 1에게 envp 둘을 준다(HOME=/ · TERM=linux)
#   → init/src/environ.zig의 withPath가 PATH를 붙인 블록을 짓는다
#   → supervise()가 그 블록을 자식 둘에게 똑같이 넘긴다
#   → terminal이 forkpty 뒤 셸을 exec하며 자기 환경을 물려준다
#   → 셸이 `ls` 세 글자로 /usr/bin/ls를 찾아 실행한다
#
# **열 체인 중 어느 것도 이것을 못 본다.** 나머지는 전부 게스트 명령을 절대
# 경로로 친다 — docs/decisions/project_guest_environment.md가 IP-M0에서
# 그렇게 고치라고 적어 둔 그대로다. 그 문서의 "결과 1"을 닫는 체인이다.
#
# 시리얼 콘솔 셸은 이 체인도 안 본다. 저장소의 열한 체인 전부가
# -serial file:(쓰기 전용)이고 키는 QEMU monitor로 **화면 셸**에만 간다.
# 그쪽은 init이 찍는 `tars-init: env` 한 줄과 코드 구조로 안다
# (design의 "시리얼 셸은 관측하지 않는다" 절).

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
# environ_test가 여기 들어 있다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
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

. ../gate_lib.sh

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM,
# 45462=HI, 45471=RM. 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때
# 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45463

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  for pattern in "$@"; do
    # `|| true`가 없으면 이 루프가 첫 패턴에서 죽는다 — 안 맞는 grep은
    # 종료 코드 1이고 pipefail이 그것을 파이프라인 코드로 올린다.
    # RM-M2가 잡은 잠복 결함이고, 하필 첫 패턴이 "없는 것"인 경우가 가장
    # 흔하다(그것이 실패의 이유라서 목록 앞에 적힌다).
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  exit 1
}

# ── 검사 1: initrd에 뼈대가 들어 있는가 (부팅 전, 정적) ─────────────────
#
# 부팅 20초를 쓰기 전에 본다. 그리고 **줄을 통째로 맞춘다** — TR-M2가
# `*terminfo/x/xterm*` 글로브 하나로 xterm-256color가 없는 것을 두 milestone
# 동안 못 잡은 자리가 있다. 조용한 실패를 막으려고 만든 검사가 조용히
# 실패한 자리였다.
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST="$(printf '\n%s\n' "$INITRD_LIST")"
for want in bin/sh tmp etc/passwd etc/group usr/bin/ls; do
  case "$PADDED_LIST" in
    *$'\n'"./${want}"$'\n'*) ;;
    *)
      echo "FAIL: ./${want} is missing from the initrd"
      echo "--- what is there ---"
      printf '%s\n' "$INITRD_LIST" | grep -E '^\./(bin|tmp|etc|usr/bin)' | head -20
      exit 1
      ;;
  esac
done
echo "the initrd carries /bin/sh, /tmp, /etc/passwd, /etc/group and /usr/bin/ls"

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || fail "the terminal never rendered a prompt" \
  "tars-init: started" "terminal:" "Kernel panic"
sleep 1

# ── 검사 2: init이 블록을 지었다 ────────────────────────────────────────
#
# 이 줄이 없으면 withPath가 자리 부족으로 폴백했거나 main.zig가 아직 옛
# 포인터를 쓰고 있다. 아래 타이핑 검사가 실패하기 **전에** 원인을 가른다.
if ! grep -aq "tars-init: env PATH=/usr/bin:/bin" "$LOG"; then
  fail "init never reported building an environment block with PATH" \
    "tars-init: env" "tars-init: starting as PID 1"
fi
echo "init built an environment block carrying PATH"

# ── 검사 3: 셸이 이름으로 명령을 찾는다 ─────────────────────────────────
#
# **이 milestone의 심장이다.** 앞의 둘은 파일이 있다는 것과 init이 문자열을
# 찍었다는 것이고, 여기부터가 **PATH가 실제로 동작하는가**다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor" "terminal: grid"

echo "=== typing 'ls' with no absolute path ==="
type_keys l s ret
sleep 2

# 게스트 루트에는 vendor 디렉터리가 있다(폰트가 거기 있다). 화면 줄에만
# 있어야 한다 — tars-init: 줄에도 vendor가 나올 수 있으므로 screen>으로
# 먼저 거른다.
if ! grep -a "terminal: screen>" "$LOG" | grep -aq "vendor"; then
  fail "'ls' with no path never listed the guest root (is PATH reaching the shell?)" \
    "terminal: screen>" "tars-init: env"
fi
echo "the shell resolved 'ls' through PATH"

# ── 검사 4: 음성 확인 ───────────────────────────────────────────────────
#
# 검사 3이 초록인데 셸이 사실은 못 찾았을 길이 있는가를 닫는다. fish는 못
# 찾은 명령에 `Unknown command` 를 낸다 — 그 글자가 화면에 있으면 위의
# vendor는 다른 곳에서 온 것이다.
if grep -a "terminal: screen>" "$LOG" | grep -aq "Unknown command"; then
  fail "the shell said it could not find the command" \
    "terminal: screen>" "tars-init: env"
fi

# ── 검사 5: /bin/sh 링크가 살아 있다 ────────────────────────────────────
#
# `ls -l /bin`이 한 줄로 둘을 증명한다 — ls가 플래그와 인자를 받아 돌고,
# 링크가 bash를 가리킨다. 링크가 끊겨 있어도 ls -l은 그 사실을 그대로
# 보여주므로, 여기서 보는 것은 "무엇을 가리키는가"다.
echo "=== typing 'ls -l /bin' ==="
type_keys l s spc minus l spc slash b i n ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "bash"; then
  fail "/bin/sh does not point at bash" \
    "terminal: screen>" "tars-init: env"
fi
echo "/bin/sh points at bash"

echo "PASS"
exit 0
```

- [ ] Step 2: 실행 권한을 준다

```bash
chmod +x tools/check.sh
```

- [ ] Step 3: 체인을 단독으로 돌린다

약 3~4분 걸린다(커널 빌드가 캐시돼 있으면 1분 안).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -30
```

Expected: 마지막 줄이 `PASS`이고 종료 코드가 0. 그 위에 다섯 줄:

```
the initrd carries /bin/sh, /tmp, /etc/passwd, /etc/group and /usr/bin/ls
init built an environment block carrying PATH
the shell resolved 'ls' through PATH
/bin/sh points at bash
PASS
```

- [ ] Step 4: 음성 확인 — 검사가 진짜인지 본다

초록이 "볼 것을 다 봤다"가 아니라는 것을 SH-M2가 겪었고, RM-M3은 초록이
"내가 본 것"조차 아니었다. 그러니 검사가 실패할 수 있는지 확인한다.

`init/src/main.zig`에서 `environ.withPath(...)` 를 잠시 옛 모양으로 되돌린다.

```zig
    const envp = init.environ.block.slice.ptr;   // ← 임시로 이 줄만 쓴다
```

돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -12
```

Expected: exit 1, 그리고 검사 2에서 죽는다.

```
FAIL: init never reported building an environment block with PATH
```

되돌린다. `git checkout init/src/main.zig` 로 원상복구하고 Step 3을 다시
돌려 `PASS`를 확인한 뒤에 진행한다.

- [ ] Step 5: 루트 게이트에 등록한다

`check.sh`의 `CHAINS` 배열 마지막 줄 뒤에 넣을 것:

```bash
  "UT-M0:./tools/check.sh"
```

그리고 `CHAINS=(` 바로 위의 주석 무리 끝(`# 회차당 부팅 1회라 총 부팅 횟수는
33회에서 36회가 된다.` 다음)에 넣을 것:

```bash
# UT 체인은 **게스트가 명령을 이름으로 찾는가**를 본다. 열 체인과 갈리는
# 자리가 하나뿐인데 그것이 크다 — 나머지 열은 게스트 명령을 전부 절대
# 경로로 친다. docs/decisions/project_guest_environment.md가 IP-M0에서
# "PATH가 없으니 절대 경로로 쓰라"고 적은 그대로이고, 이 체인이 그 문서의
# "결과 1"을 닫는다.
#
# 부팅 전에 initrd 목록을 먼저 훑는 것도 여기의 특징이다(IP 체인과 같은
# 수법). 파일이 없으면 부팅 20초를 안 쓰고 그 자리에서 죽는다.
#
# 회차당 부팅 1회라 총 부팅 횟수는 36회에서 39회가 된다.
```

- [ ] Step 6: 진입 검사가 새 체인을 받아들이는지 확인한다

루트 게이트는 첫 부팅 전에 모든 체인이 `BUILD_STEPS` 넷을 부르는지 훑고,
하나라도 없으면 게이트를 시작조차 하지 않는다. 20분을 쓰기 전에 그
부분만 본다.

`check.sh`를 source하면 안 된다 — 게이트가 통째로 돌아 버린다. 진입
검사가 보는 것과 같은 것을 손으로 본다(주석 줄은 세지 않는다).

```bash
body="$(grep -vE '^[[:space:]]*#' tools/check.sh)"
for step in 'cd ../kernel && ./build.sh)' 'cd ../init && zig build)' \
            './prepare.sh' './make_initrd.sh'; do
  case "$body" in
    *"$step"*) echo "ok      $step" ;;
    *)         echo "MISSING $step" ;;
  esac
done
```

Expected: 네 줄 다 `ok`. 하나라도 `MISSING`이면 `tools/check.sh`의 빌드
단계를 그 문자열 그대로 맞춰 고친다.

- [ ] Step 7: 커밋

```bash
git add tools/check.sh check.sh
git commit -m "Watch the guest find a command by name for the first time"
```

---

## Task 5: 루트 게이트 3/3

- [ ] Step 1: 게이트를 백그라운드로 돌린다

약 22~25분 걸린다. Bash 도구의 타임아웃 상한이 10분이라 반드시
백그라운드로 돌린다 — 넘겨 주면 잘려서 exit 143이 된다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [ ] Step 2: 결과를 본다

```bash
tail -5 /tmp/gate.log; echo "--- 시간 ---"; cat /tmp/gate.time
grep -c '^=== .* run [0-9]/3 ===$' /tmp/gate.log
```

Expected: `/tmp/gate.log`의 마지막이 게이트의 통과 메시지, `run` 줄이 33개
(체인 11 × 3회).

- [ ] Step 3: 시간을 기록한다

`real` 값을 적어 둔다. 착수 전 기준선은 20분 29.84초(RM-M3 시점)다.
차이를 Task 6에서 design과 HANDOFF에 남긴다 — design 위험 2가 "언제부터
느려졌나를 캘 수 있게 남긴다"고 적은 자리다.

- [ ] Step 4: 실패하면

체인 이름과 회차를 보고 그 체인만 단독으로 다시 돌린다. 루트 게이트를
반복해서 돌리지 않는다(회당 20분이 넘는다).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash <실패한 체인>/check.sh 2>&1 | tail -40
```

`PATH`가 생기면서 흔들릴 수 있는 것이 셸의 명령 완성과 해시다
(design 위험 4). 열 체인이 전부 절대 경로를 쓰므로 흔들릴 이유가 없지만,
흔들렸다면 그 체인의 어느 줄이 갈렸는지를 먼저 본다.

---

## Task 6: 문서를 닫는다

Files:
- Modify: `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`
- Modify: `HANDOFF.md`
- Modify: `MEMORY.md`
- Create: `docs/decisions/project_userland_tools.md`
- Modify: `docs/decisions/project_guest_environment.md`

- [ ] Step 1: design에 실측 절을 더한다

design 끝에 `## UT-M0이 실행으로 증명한 것 — **다시 조사하지 말 것**`을
만들고 담을 것:

1. Task 0의 세 숫자(gzip · zstd · xz의 크기와 시간)와 부팅 시간
   둘(`orig` 대 `ut`). 위험 1이 참이었는지 거짓이었는지가 여기서 갈린다.
2. 어느 압축기를 골랐고 왜인가.
3. `environ_test`가 실패한 모양(컴파일 에러였는지 런타임이었는지).
4. Task 4 Step 4의 음성 확인 결과.
5. 게이트 시간(11 체인 3/3)과 기준선 20분 29.84초와의 차이.

그리고 `**Status:**` 줄을 고친다 — "설계 완료 — 착수 전"에서
"진행 중 — UT-M0 완료"로.

- [ ] Step 2: `project_guest_environment.md`의 "결과 1"을 닫는다

그 문서의 `## 결과 1: PATH가 없다` 절이 더 이상 참이 아니다. 절을 지우지
말고 `## 결과 2`가 `TERM`에 대해 한 것과 같은 모양으로 닫는다 — 제목을
`## 결과 1: PATH가 없었다 — UT-M0(2026-09-10)에 고쳤다`로 바꾸고, 아래에
무엇이 바뀌었는지와 `How to apply:` 줄을 함께 고친다.

이 단계를 빼먹으면 다음 세션이 "PATH가 없다"를 사실로 읽는다. TR-M0이
`TERM`을 바꾸고 initrd를 안 따라가게 둔 것과 같은 종류의 사고다.

- [ ] Step 3: 새 기억을 만든다

`docs/decisions/project_userland_tools.md`를 만들고 `MEMORY.md`에 한 줄
더한다. 담을 것은 다음 세션이 다시 캐지 않아야 할 것이다 —
`libgit2` 사슬 15개 11.4MB · git의 네트워크 헬퍼 일곱 · `fdfind`/`batcat`
이름 · 셸이 무조건 no-config라 zoxide/fzf가 못 붙는다는 것.

- [ ] Step 4: HANDOFF을 갱신한다

머리를 `# HANDOFF: Userland Tools UT-M0 — 통로가 열렸다`로 바꾸고 지금
어디인가 · UT-M0의 커밋들 · 바로 다음에 할 것(UT-M1) · 게이트 시간을 적는다.

- [ ] Step 5: 커밋

```bash
git add docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md \
        docs/decisions/project_userland_tools.md \
        docs/decisions/project_guest_environment.md \
        MEMORY.md HANDOFF.md
git commit -m "Close UT-M0 with PATH standing and the size question answered"
```

---

## 자기 검토 — 이 plan이 놓치기 쉬운 것

| 함정 | 어디서 잡히나 |
|---|---|
| fish에서 `$PATH`는 리스트라 `echo $PATH`가 `/usr/bin /bin`을 낸다(콜론이 아니다) | 그래서 값 검사를 셸이 아니라 `tars-init: env` 줄로 한다(검사 2) |
| `ls`를 넣고 `copy_lib_deps`를 빼먹기 | 게스트가 `ls`를 처음 칠 때 드러난다 — 검사 3이 그 자리다. UT-M1의 결정 7이 이 실수를 구조적으로 없앤다 |
| Task 0의 밸러스트를 난수나 0으로 채우기 | 압축률이 실제와 달라 답이 통째로 틀린다. Step 2가 진짜 바이너리를 쓴다 |
| `git-core`의 네트워크 헬퍼를 스파이크에 넣기 | 16MB를 과대 계상한다. Step 2의 목록이 `git` 하나만 복사한다 |
| 게이트를 포그라운드로 돌리기 | 10분에 잘려 exit 143 |
| `project_guest_environment`를 안 고치기 | Task 6 Step 2 |
