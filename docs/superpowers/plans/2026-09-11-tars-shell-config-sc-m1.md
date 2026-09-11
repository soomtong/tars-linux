# SC-M1 Implementation Plan — 씨앗을 깔고, 그것이 읽혔다는 것을 본다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** init이 `/config`를 마운트했을 때 rc 파일 셋(`bashrc`·`zshrc`·
`fish.config`)을 **없으면 만들고**, `config/check.sh`의 부팅을 셋으로 늘려
**rc가 실제로 읽힌다**와 **`shell_config=off`가 그것을 막는다**를 증명한다.

**Architecture:** 새 파일이 하나도 없다. SC-M0이 링크를 걸어 둔 자리에 파일을
놓는 일이고, `config.save()`가 `tars.conf`에 대해 하는 것과 **글자 그대로 같은
모양**이다 — 다른 점은 `O_EXCL`뿐이다(`tars.conf`는 "파일이 없다"를 `load`가
이미 답했지만 rc는 그 질문을 커널에게 직접 한다).

**Tech Stack:** Zig(init) · bash(게이트 체인) · QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
— 특히 **결정 7(씨앗) · 결정 10(부팅 셋)** 과 **실측 4(디스크를 붙이는 체인이
다섯이다) · 실측 9(프롬프트는 게이트의 좌표계다) · 위험 3(rc가 깨지면 고칠
셸이 없다)**.

---

## 이 milestone을 지배하는 사실 하나

> **씨앗은 부팅할 때 한 글자도 찍으면 안 된다.**

설정 디스크를 붙이는 체인이 다섯이다(design 실측 4) — `config` · `hangul` ·
`input` · `machine` · `power`. SC-M0 뒤로 그 다섯의 셸은 **rc를 읽으려 하고**
지금까지는 읽을 파일이 없어서 아무 일도 안 일어났다. **M1이 그 파일을
만드는 순간 다섯 체인의 화면이 씨앗의 내용을 따라간다.**

`hangul`·`input`은 화면의 **셀 좌표**로 판정하고(`copy/check.sh`의 `col 20`이
같은 종류다) `machine`은 fish 인사말의 위치를 본다. **씨앗이 배너 한 줄을
찍으면 그 좌표가 전부 한 칸씩 밀린다.**

그래서 이 plan의 Task 1이 씨앗 텍스트에 대한 **호스트 검사**부터 만든다:
*"주석이 아닌 줄은 전부 `alias `로 시작한다."* 부팅 20초가 아니라 0.1초로
답이 나오는 자리이고, **나중에 이 파일에 `echo`를 넣는 사람을 막는 것이 이
검사의 진짜 목적이다.**

SC-M0이 배운 것(실측 19)의 다음 판이다 — 그때는 **셸이 색을 쓰기 시작해서**
게이트가 셋 깨졌고, 이번에는 **셸이 파일을 읽기 시작한다.**

---

## 게이트가 무엇을 어떻게 보는가 — 부팅 셋

design 결정 10의 표를 실제 명령으로 옮긴 것이다.

| 부팅 | 디스크 | 셸 | 무엇을 치나 | 무엇을 증명하나 |
|---|---|---|---|---|
| **1차** | 빈 디스크 | fish | `tars-config` → `echo shell=zsh > …conf` → `echo echo tars-rc-alive >> …zshrc` → 되읽기 둘 | 씨앗 셋이 생겼다 · **fish가 `/config/fish.config`를 읽었다** · 사람이 고친 것이 파일에 들어갔다 |
| **2차** | 같은 이미지 | zsh | `echo shell_config=off >> …conf` → 되읽기 | **두 셸이 다 `/config/zshrc`를 읽었다** · 씨앗을 다시 안 만든다 |
| **3차** | 같은 이미지 | zsh | 아무것도 안 친다 | **같은 rc가 안 읽힌다** — 부정 검사 |

**1차의 첫 명령 `tars-config`가 이 설계에서 가장 밀도가 높다.** 그것은 씨앗이
정의한 alias이고, 그 출력은 씨앗 `tars.conf`의 마지막 줄 `shell_config=on`이다.
한 번의 타이핑이 셋을 동시에 증명한다:

1. `/config/fish.config`가 **생겼다**
2. fish가 그것을 **읽었다**(안 읽었으면 `tars-config`는 모르는 명령이다)
3. 씨앗 `tars.conf`가 실제로 `shell_config=on`을 **담고 있다**
   (SC-M0의 게이트는 로그에서 기본값만 봤고 **파일의 내용은 못 봤다**)

**2차·3차의 판정 글자 `tars-rc-alive`는 우리가 아니라 사람이 심는다.** 씨앗에
`echo`를 넣을 수 없기 때문이고(위의 지배적 사실), 그래서 **그 글자는 1차에서
사람이 타이핑한 것**이다. design 결정 10이 *"사람이 `/config/zshrc`에 줄을
더한다"*고 적은 자리가 바로 여기다.

**그 글자를 어디서 보는지가 중요하다.**

| 어디 | 누가 찍나 | 무엇을 뜻하나 |
|---|---|---|
| `terminal: screen>`가 **아닌** 줄 | **시리얼 콘솔 셸** | 결정 4의 절반 — init이 직접 exec한 셸이 rc를 읽었다 |
| `terminal: screen>` 줄 | **화면 셸** | 결정 4의 나머지 절반 — terminal이 띄운 셸이 rc를 읽었다 |

`config/check.sh:314`가 이미 같은 모양의 구분을 쓰고 있다(*"화면 덤프 안의
문자열은 터미널이 렌더링한 픽셀의 텍스트일 뿐이라 제외한다"*). **콘솔 셸에는
타이핑을 못 하지만**(체인이 `-serial file:`, 쓰기 전용) **그 셸이 스스로 찍는
것은 읽을 수 있다** — SC-M0이 "콘솔 셸의 argv를 못 본다"고 적어 둔 자리의
다른 면이다.

---

## File Structure

| 파일 | 무엇을 맡나 | 이 milestone이 하는 일 |
|---|---|---|
| `init/src/config_test.zig` | 시스템 콜 없는 부분을 호스트에서 검증 | **씨앗 텍스트의 불변식 검사**(주석 아니면 alias) |
| `init/src/config.zig` | 설정 파일의 문법·기본값·쓰기 | `Shell.rcPath()` · `Shell.rcSeed()` · `seedRcFiles()` · `writeAll()` 추출 |
| `init/src/main.zig` | PID 1 | 마운트됐으면 씨앗을 깐다(한 줄) |
| `config/check.sh` | CP 체인 | **부팅 셋** · 타이핑 다섯 · 검사 아홉 |

**새 파일이 없고, 새 체인도 없다**(design 결정 10 — 열두번째 체인은 +2분이다).
`kernel/make_initrd.sh`는 **한 글자도 안 고친다** — 링크는 SC-M0이 이미 걸었다.

---

## Task 1: 씨앗 텍스트의 불변식을 먼저 못 박는다 — **실패를 본다**

**Files:** Modify `init/src/config_test.zig`

**왜 이것이 먼저인가.** 위 "지배적 사실"이 전부다. 씨앗이 무엇을 찍는 순간
다섯 체인이 깨지는데, 그 실패는 **부팅 20초 뒤에 화면 좌표가 밀린 모양**으로
온다 — 원인에서 가장 먼 증상이다. **0.1초짜리 호스트 검사가 같은 것을 코드
모양으로 잡는다.**

- [x] **Step 1: 검사 함수와 호출 셋을 `main()` 끝의 `PASS` 앞에 더한다**

`init/src/config_test.zig`의 `std.debug.print("PASS\n", .{});` **앞**에
**넣을 것**:

```zig
    // ── SC-M1: 씨앗 rc의 불변식 ─────────────────────────────────────────
    //
    // **이 검사의 목적은 지금 통과하는 것이 아니라 나중에 막는 것이다.**
    // 설정 디스크를 붙이는 체인이 다섯이고(design 실측 4) 그중 셋이 화면의
    // 셀 좌표로 판정한다. 씨앗이 부팅할 때 한 글자라도 찍으면 그 좌표가
    // 통째로 밀리고, 증상은 **부팅 20초 뒤에 엉뚱한 체인이 깨지는 것**이다.
    //
    // 그래서 규칙을 코드 모양으로 못 박는다: **주석이 아닌 줄은 전부
    // `alias `로 시작한다.** alias는 정의만 하고 아무것도 실행하지 않는
    // 유일한 종류의 줄이다.
    for (std.enums.values(config.Shell)) |sh| try expectQuietSeed(sh);
```

같은 파일의 `expect()` 함수 **뒤**에 **넣을 것**:

```zig
/// 씨앗 rc가 "아무것도 안 찍는다"를 문법으로 확인한다(SC-M1).
///
/// 셋 다 문법이 다른 셸의 파일이라 우리가 파싱할 수는 없다. 대신 **우리가
/// 쓸 수 있는 줄의 종류를 둘로 제한한다** — 주석과 alias. 그 둘은 어느
/// 셸에서도 출력을 만들지 않는다.
///
/// **위험 3의 반쪽이 여기 있다.** design이 *"우리가 까는 것은 절대로 셸을
/// 죽이지 않아야 한다"*고 적었고, 그 "절대로"를 지키는 장치가 이 함수다.
fn expectQuietSeed(sh: config.Shell) !void {
    const text = sh.rcSeed();
    if (text.len == 0 or text[text.len - 1] != '\n') {
        std.debug.print("FAIL: the {s} seed does not end with a newline\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    var aliases: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "alias ")) {
            aliases += 1;
            continue;
        }
        std.debug.print(
            "FAIL: the {s} seed has a line that is neither a comment nor an alias:\n  {s}\n",
            .{ @tagName(sh), line },
        );
        return error.BadSeed;
    }
    // **alias가 하나도 없으면 1차 부팅의 `tars-config`가 무의미해진다.**
    // 게이트는 그 alias가 있다는 것으로 "셸이 이 파일을 읽었다"를 판정한다.
    if (aliases == 0) {
        std.debug.print("FAIL: the {s} seed defines no alias for the gate to find\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    // 씨앗은 자기 파일의 이름을 자기 안에 적는다. 그 이름이 틀리면 사용자가
    // `tars-rc`를 쳤을 때 없는 파일을 cat한다 — **문서가 아니라 실행되는
    // 문장이라 틀린 것이 드러난다.**
    if (std.mem.indexOf(u8, text, sh.rcPath()) == null) {
        std.debug.print("FAIL: the {s} seed never names its own path {s}\n", .{
            @tagName(sh), sh.rcPath(),
        });
        return error.BadSeed;
    }
}
```

- [x] **Step 2: 컴파일 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

**Expected:** FAIL. `Shell`에 `rcSeed`도 `rcPath`도 없으므로 컴파일 에러다
(`no member named 'rcSeed'`). **테스트 실패가 아니라 컴파일 실패인 것이
정상이다** — SC-M0 Task 1과 같은 자리다.

- [x] **Step 3: 아직 커밋하지 않는다**

Task 2와 함께 커밋한다. 컴파일이 안 되는 상태를 히스토리에 남기지 않는다.

---

## Task 2: `config.zig`가 씨앗을 갖고, 없으면 만든다 — **결정 7**

**Files:** Modify `init/src/config.zig`

- [x] **Step 1: `Shell`에 `rcPath()`와 `rcSeed()`를 더한다**

`init/src/config.zig`의 `configFlag` 함수 **바로 뒤**, `Shell`의 닫는 `};`
앞에 **넣을 것**:

```zig
    /// 이 셸의 rc 파일이 **설정 디스크에서** 갖는 이름(SC design 결정 1).
    ///
    /// **홈의 이름이 아니라 여기 이름이다.** 홈에는 링크만 있고
    /// (`kernel/make_initrd.sh`가 건다) 실체는 전부 이 자리다 — 홈(`/`)은
    /// tmpfs라 부팅마다 비워지고, 살아남는 것은 `/config` 하나뿐이다.
    ///
    /// | 홈의 이름 | 여기 |
    /// |---|---|
    /// | `/.bashrc` | `/config/bashrc` |
    /// | `/.zshrc` | `/config/zshrc` |
    /// | `/.config/fish/config.fish` | `/config/fish.config` |
    ///
    /// **`fish.config`로 적은 것에 뜻이 있다** — `/config` 안을 평평하게
    /// 두어 `gitconfig`과 같은 층에 세운다(결정 1).
    ///
    /// `main.zig`의 `CONFIG_PATH`가 같은 `/config`를 알고 있다. 둘을 한
    /// 자리로 모으려면 힙 없이 경로를 조립해야 해서, 지금은 **이름 넷이
    /// `make_initrd.sh`의 링크 넷과 짝이라는 것**을 주석으로 못 박는 쪽을
    /// 고른다 — 어긋나면 증상은 "rc를 고쳤는데 안 읽힌다"이고,
    /// `config/check.sh`의 2차 부팅이 그것을 본다.
    pub fn rcPath(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "/config/fish.config",
            .bash => "/config/bashrc",
            .zsh => "/config/zshrc",
        };
    }

    /// 첫 부팅에 깔아 두는 내용(결정 7).
    ///
    /// **규칙이 하나뿐이다: 아무것도 찍지 않는다.** 설정 디스크를 붙이는
    /// 체인이 다섯이고 그중 셋이 화면의 셀 좌표로 판정한다 — 씨앗이 배너
    /// 한 줄을 찍으면 그 좌표가 통째로 밀린다. 그래서 여기 쓸 수 있는 줄은
    /// **주석과 alias 둘뿐**이고, `config_test.zig`의 `expectQuietSeed`가
    /// 그 규칙을 컴파일 뒤 0.1초에 확인한다.
    ///
    /// **프롬프트를 안 건드린다**(비목표 5). 실측 9가 그 비용을 적고 있고,
    /// 그 비용은 사용자가 자기 rc에 프롬프트를 쓸 때 **자기 기계에서만**
    /// 치르면 된다.
    ///
    /// 셋의 문법 차이를 나란히 두는 것에도 뜻이 있다 — `shell`을 바꾼
    /// 사용자가 새 셸의 파일을 열었을 때 빈 파일이 아니라 읽을 것이 있다.
    pub fn rcSeed(self: Shell) []const u8 {
        return switch (self) {
            .fish =>
            \\# TARS shell config — fish
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/fish.config이고, 홈의
            \\# ~/.config/fish/config.fish는 그리로 가는 링크다. 홈(/)은 tmpfs라
            \\# 부팅마다 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# `source ~/.config/fish/config.fish`.
            \\#
            \\# 여기 있는 것이 주석과 alias뿐인 데 이유가 있다: 이 파일이 부팅할
            \\# 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가 밀린다. 늘리는
            \\# 것도 지우는 것도 마음대로지만, 그 대가는 자기 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/fish.config'
            \\
            ,
            .bash =>
            \\# TARS shell config — bash
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/bashrc이고, 홈의
            \\# ~/.bashrc는 그리로 가는 링크다. 홈(/)은 tmpfs라 부팅마다
            \\# 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# `source ~/.bashrc`.
            \\#
            \\# 여기 있는 것이 주석과 alias뿐인 데 이유가 있다: 이 파일이 부팅할
            \\# 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가 밀린다. 늘리는
            \\# 것도 지우는 것도 마음대로지만, 그 대가는 자기 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/bashrc'
            \\
            ,
            .zsh =>
            \\# TARS shell config — zsh
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/zshrc이고, 홈의
            \\# ~/.zshrc는 그리로 가는 링크다. 홈(/)은 tmpfs라 부팅마다
            \\# 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# `source ~/.zshrc`.
            \\#
            \\# 여기 있는 것이 주석과 alias뿐인 데 이유가 있다: 이 파일이 부팅할
            \\# 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가 밀린다. 늘리는
            \\# 것도 지우는 것도 마음대로지만, 그 대가는 자기 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/zshrc'
            \\
            ,
        };
    }
```

- [x] **Step 2: `save`의 쓰기 루프를 `writeAll`로 뺀다**

`init/src/config.zig`의 `save` 안에서 **지울 것**:

```zig
    // /config는 MS_SYNCHRONOUS로 마운트돼 있다. 그래서 이 write가 돌아온
    // 시점에 데이터도 디렉터리 엔트리도 이미 디스크에 있다 — fsync를 따로
    // 부르지 않는 것이 실수가 아니라 그 마운트 플래그의 값어치다.
    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to write {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}
```

**넣을 것**:

```zig
    return writeAll(fd, text, path);
}

/// fd에 전부 쓴다. **`save`와 `seedRcFiles`가 같은 루프를 쓴다** — SC-M1이
/// 둘째 호출자를 만들면서 뺐다.
///
/// `/config`는 `MS_SYNCHRONOUS`로 마운트돼 있다. 그래서 이 write가 돌아온
/// 시점에 데이터도 디렉터리 엔트리도 이미 디스크에 있다 — fsync를 따로
/// 부르지 않는 것이 실수가 아니라 그 마운트 플래그의 값어치다.
fn writeAll(fd: i32, text: []const u8, path: [:0]const u8) SaveError!void {
    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to write {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}
```

- [x] **Step 3: `seedRcFiles`를 파일 끝에 더한다**

`init/src/config.zig`의 **맨 끝**에 **넣을 것**:

```zig
/// 셸 rc 파일 셋을 "없으면 만든다"(SC design 결정 7).
///
/// **`/config`가 마운트됐을 때만 부른다.** 안 붙은 부팅에서는 `/config`가
/// initrd 안의 빈 디렉터리(tmpfs)이므로, 여기서 만들면 부팅마다 새로 생겼다
/// 사라지는 파일이 되고 "고치고 재부팅하면 남는다"는 약속이 그 부팅에서만
/// 거짓이 된다. **없는 편이 낫다** — 링크가 끊긴 채로 셸이 뜨고, 그것은
/// SC-M0이 이미 여섯 체인에서 확인한 정상 경로다.
///
/// **`shell_config`를 안 본다.** `off`여도 깐다 — 셸이 안 읽을 뿐 파일은
/// 있는 것이 맞고, 나중에 `on`으로 바꾼 사람이 빈 디렉터리를 안 만난다.
/// `shell`도 안 본다: 셋 다 깐다는 결정 7의 근거가 같다 — `tars.conf`의
/// `shell`은 언제든 바뀔 수 있고, 바뀐 뒤에야 씨앗이 생기면 "고치고
/// 재부팅했는데 rc가 없다"가 된다.
///
/// **이미 있으면 손대지 않는다.** 그때부터 그 파일은 사용자의 것이다.
/// `O_EXCL`이 그 질문을 커널에게 한 번에 묻는다 — `save`가 `O_EXCL`을 안
/// 쓰는 것과 다른 이유는, 저쪽은 "파일이 없다"를 `load`가 이미 답했기
/// 때문이다.
pub fn seedRcFiles() void {
    for (std.enums.values(Shell)) |sh| seedRcFile(sh);
}

fn seedRcFile(sh: Shell) void {
    const path = sh.rcPath();
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .EXCL = true,
    }, 0o644);
    if (failed(rc)) |e| {
        // 이미 있다 = 사용자의 파일이다. 조용히 둔다 — 여기서 로그를 찍으면
        // 부팅마다 세 줄이 늘고, 그 셋은 아무것도 알려주지 않는다.
        if (e == .EXIST) return;
        std.debug.print("tars-init: could not seed {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    writeAll(fd, sh.rcSeed(), path) catch return;

    // **`created`가 아니라 `seeded`다.** `tars-init: created /config/tars.conf`
    // 를 config 체인이 1차/2차 부팅의 판정으로 쓰고 있어서, 앞부분이 겹치면
    // 그 검사가 rc 세 줄까지 함께 보게 된다.
    std.debug.print("tars-init: seeded {s}\n", .{path});
}
```

- [x] **Step 4: 호스트 검사가 통과하는지 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

**Expected:** 마지막 줄이 `PASS`, 종료 코드 0. `FAIL:` 줄이 하나도 없어야
한다.

- [x] **Step 5: 커밋**

```bash
git add init/src/config.zig init/src/config_test.zig
git commit -m "Lay down three rc files that say nothing out loud"
```

---

## Task 3: PID 1이 디스크가 있을 때만 씨앗을 깐다

**Files:** Modify `init/src/main.zig`

- [x] **Step 1: `loadConfig` 뒤에 한 줄을 더한다**

`init/src/main.zig`에서 **지울 것**:

```zig
    const storage_mounted = mountConfig();
    const cfg = loadConfig(storage_mounted);
```

**넣을 것**:

```zig
    const storage_mounted = mountConfig();
    const cfg = loadConfig(storage_mounted);
    // SC-M1 결정 7. **`loadConfig`보다 뒤이고 자식을 띄우기보다 앞이다** —
    // 앞이어야 하는 이유는 이 부팅의 셸이 곧바로 이 파일을 읽기 때문이고,
    // `loadConfig` 뒤인 이유는 `tars.conf`의 씨앗이 먼저 생기는 편이 로그의
    // 순서로 읽기에 맞기 때문이다(둘 사이에 의존은 없다).
    //
    // **`cfg`를 안 넘긴다.** 씨앗은 `shell_config`도 `shell`도 안 본다 —
    // 그 근거는 `config.seedRcFiles`의 주석에 있다.
    if (storage_mounted) config.seedRcFiles();
```

- [x] **Step 2: 빌드와 호스트 검사**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

**Expected:** 종료 코드 0.

- [x] **Step 3: 커밋**

```bash
git add init/src/main.zig
git commit -m "Only lay the seeds when there is a disk to keep them"
```

---

## Task 4: 1차 부팅이 씨앗을 보고, 사람이 rc에 줄을 더한다

**Files:** Modify `config/check.sh`

- [x] **Step 1: 타이핑 시퀀스 넷을 더한다**

`config/check.sh`의 `READBACK_KEYS=(...)` 줄 **뒤**에 **넣을 것**:

```bash
# ── SC-M1 ───────────────────────────────────────────────────────────────
# tars-config — **씨앗이 정의한 alias다.** 이 한 명령이 셋을 동시에 본다:
#   1. /config/fish.config가 생겼다
#   2. fish가 그것을 읽었다(안 읽었으면 모르는 명령이다)
#   3. 씨앗 tars.conf가 실제로 shell_config=on을 담고 있다
# SC-M0의 게이트는 로그에서 **기본값**만 봤고 파일의 내용은 못 봤다.
ALIAS_KEYS=(t a r s minus c o n f i g ret)
# echo echo tars-rc-alive >> /config/zshrc
#
# **판정 글자를 사람이 심는 자리다.** 씨앗에는 echo를 넣을 수 없다 — 설정
# 디스크를 붙이는 다섯 체인의 화면 좌표가 밀린다. 그래서 "rc가 읽혔다"를
# 말해 줄 글자는 게이트가 타이핑한다(design 결정 10의 "사람이 줄을 더한다").
#
# >> 는 shift-dot 둘이다. 씨앗을 덮어쓰지 않는 것이 요점이다 — 2차 부팅이
# 읽는 파일은 **씨앗 + 사람이 더한 줄**이어야 한다.
APPEND_KEYS=(e c h o spc e c h o spc t a r s minus r c minus a l i v e spc
             shift-dot shift-dot spc slash c o n f i g slash z s h r c ret)
# grep alive /config/zshrc — 더한 줄이 파일에 들어갔는지 되읽는다.
# cat이 아니라 grep인 이유는 출력이 한 줄이어야 하기 때문이다. 씨앗은
# 열몇 줄이고, UT-M3이 배운 대로 **긴 출력의 첫 줄은 프레임에 안 남는다.**
RC_READBACK_KEYS=(g r e p spc a l i v e spc slash c o n f i g slash z s h r c ret)
```

- [x] **Step 2: 1차 부팅의 훅을 다시 쓴다**

`config/check.sh`의 `edit_config_in_guest()` 안에서, `type_keys`를 부르는
부분을 갈아 끼운다. **지울 것**:

```bash
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
```

**넣을 것**:

```bash
  # ── SC-M1: 씨앗을 먼저 묻는다 ────────────────────────────────────────
  #
  # **고치기 전에 묻는 것이 순서다.** 아래 EDIT_KEYS가 tars.conf를 한 줄로
  # 덮어쓰므로, 씨앗 파일의 내용을 볼 수 있는 것은 지금뿐이다.
  #
  # dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다. 그래서
  # **행의 첫머리**를 보는 것이 출력이고, 방금 타이핑한 명령줄은 프롬프트로
  # 시작하므로 안 걸린다 — 이 파일이 아래에서 오래 쓰고 있는 수법이다.
  type_keys "${ALIAS_KEYS[@]}"
  if ! wait_for_screen '\| shell_config=on'; then
    echo "FAIL(boot 1): 'tars-config' never printed the seeded config"
    echo "  둘 중 하나다 — 씨앗 /config/fish.config가 안 생겼거나, 생겼는데"
    echo "  fish가 그것을 안 읽었다. 아래 마지막 화면에 'Unknown command'가"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: the seeded fish.config defined tars-config, and it printed shell_config=on"

  type_keys "${EDIT_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  # 되읽기 확인. 위와 같은 수법이다 — **행의 첫머리가 shell=zsh인 것**이
  # cat의 출력이고, 방금 타이핑한 명령줄에도 shell=zsh가 들어 있지만 그 행은
  # 프롬프트와 echo로 시작한다.
  #
  # 이 검사가 통과하면 "키가 게스트에 도달했고, 셸이 명령을 실행했고, 파일에
  # 써졌고, 다시 읽힌다"까지가 한꺼번에 확인된다.
  if ! wait_for_screen '\| shell=zsh'; then
    echo "FAIL(boot 1): typed the edit but /config/tars.conf never read back as shell=zsh"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: typed the edit in the guest and read it back (shell=zsh)"

  # ── SC-M1: 2차·3차가 볼 글자를 심는다 ────────────────────────────────
  type_keys "${APPEND_KEYS[@]}"
  type_keys "${RC_READBACK_KEYS[@]}"
  if ! wait_for_screen '\| echo tars-rc-alive'; then
    echo "FAIL(boot 1): the line appended to /config/zshrc did not read back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: appended a marker line to the seeded /config/zshrc"

  exec 3<&-
  exec 3>&-
  return 0
}
```

- [x] **Step 3: 1차 부팅 뒤의 검사에 씨앗 셋을 더한다**

`config/check.sh`에서 `echo "boot 1: init reported shell_config=on (the sixth
key reached the log)"` 줄 **뒤**에 **넣을 것**:

```bash
# SC-M1 결정 7. **씨앗 셋이 로그에 한 줄씩 남는다.** 화면으로 보는 것은
# fish의 것 하나뿐이고(1차 부팅의 셸이 fish다) 나머지 둘은 이 줄이 전부다 —
# bash·zsh의 씨앗이 **읽히는지**는 이 milestone이 zsh에 대해서만 본다.
for rc in /config/bashrc /config/zshrc /config/fish.config; do
  if ! grep -q "tars-init: seeded ${rc}" "$LOG1"; then
    report_failure "$LOG1" "first boot did not seed ${rc}"
  fi
done
echo "boot 1: init seeded all three rc files on the empty disk"
```

- [x] **Step 4: CP 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh
```

**Expected:** 이 시점에는 2차 부팅까지만 있으므로 `PASS`가 나와야 한다. 새
줄 셋이 보인다.

**실패하면 가장 먼저 볼 것:** `tars-config`가 `Unknown command`였는지.
그러면 fish가 씨앗을 안 읽은 것이고, 원인은 (a) 링크가 안 풀렸거나 (b) 씨앗의
fish 문법이 틀렸거나 (c) `shell_config`가 `off`로 읽힌 것이다. 셋이 화면에서
서로 다른 모양으로 나타난다 — (b)는 fish의 문법 에러 메시지가 함께 뜬다.

- [x] **Step 5: 커밋**

```bash
git add config/check.sh
git commit -m "Ask the first boot to read what it just wrote for the shell"
```

---

## Task 5: 2차 부팅이 "rc가 읽혔다"를 보고, `off`를 적는다

**Files:** Modify `config/check.sh`

- [x] **Step 1: 2차 부팅의 훅을 만든다**

`config/check.sh`의 `watch_console_shell()` 함수 **전체를 지우고** **넣을 것**:

```bash
# 2차 부팅에서 마커를 본 뒤 하는 일. 둘이다.
#
#   1. **관측 창** — 여기서 확인할 것 중 몇 개는 **없어야 할 것**(셸이 죽지
#      않았다)이라 시간이 필요하다. 부재는 폴링으로 증명할 수 없다. 재시작
#      backoff가 1초이므로 세 번 죽고 포기하는 데 3초면 충분하다.
#   2. **3차 부팅이 읽을 설정을 심는다**(SC-M1) — tars.conf에
#      shell_config=off 한 줄을 **더한다.** 1차에서 사람이 친 shell=zsh는
#      그대로 남아야 한다: 3차의 부정 검사는 "같은 셸이 같은 rc를 안 읽는다"
#      여야 하고, 셸까지 바뀌면 무엇 때문에 안 읽혔는지 갈리지 않는다.
#
# **이 부팅의 셸은 zsh다.** 프롬프트가 fish의 `root@(none) ~#`가 아니라
# `(none)#`이지만(design 실측 14(e)) 타이핑하는 쪽은 그것을 안 봐도 된다 —
# 판정은 전부 출력의 행 첫머리로 한다.
watch_console_shell() {
  local log="$1"
  LOG="$log"

  sleep 5

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 2): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 2): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${OFF_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  local ok=0
  if wait_for_screen '\| shell_config=off'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 2): typed shell_config=off but /config/tars.conf never read it back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 2: appended shell_config=off to the config for the third boot"
  return 0
}
```

- [x] **Step 2: `OFF_KEYS`를 더한다**

`config/check.sh`의 `RC_READBACK_KEYS=(...)` **뒤**에 **넣을 것**:

```bash
# echo shell_config=off >> /config/tars.conf — 2차 부팅에서 친다.
# 밑줄은 shift-minus다(design 실측 14(f)에서 게스트에 닿는 것을 확인했다).
OFF_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o f f spc
          shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)
```

- [x] **Step 3: 2차 부팅 뒤의 검사에 셋을 더한다**

`config/check.sh`에서 `echo "boot 2: the config written inside the guest
selected zsh for both shells"` 줄 **앞**에 **넣을 것**:

```bash
# ── SC-M1: 이 milestone이 증명하려는 것 ─────────────────────────────────
#
# 1차에서 사람이 /config/zshrc에 더한 `echo tars-rc-alive` 한 줄이 이 부팅의
# 셸에서 실행됐는가. **씨앗을 덮어쓰지 않고 더한 줄이므로, 이 글자가 보이면
# 씨앗 파일 자체가 읽혔다는 뜻이기도 하다.**
#
# **두 자리를 따로 본다**(결정 4).
#
#   terminal: screen> 가 아닌 줄  →  시리얼 콘솔 셸. init이 직접 exec했다
#   terminal: screen> 인 줄        →  화면 셸. terminal이 PTY에 띄웠다
#
# 아래 :314가 이미 같은 구분을 쓰고 있다. 콘솔 셸에는 타이핑을 못 하지만
# (체인이 -serial file:, 쓰기 전용) **그 셸이 스스로 찍는 것은 읽을 수 있다.**
if ! grep "tars-rc-alive" "$LOG2" | grep -qv "terminal: screen>"; then
  report_failure "$LOG2" "the serial console shell never ran the line the user added to /config/zshrc"
fi
if ! grep -a "terminal: screen>" "$LOG2" | grep -q "tars-rc-alive"; then
  report_failure "$LOG2" "the screen shell never ran the line the user added to /config/zshrc"
fi
echo "boot 2: both shells read /config/zshrc (the user's line ran twice)"

# 씨앗은 한 번만 깐다. 이 부정 검사가 없으면 "매 부팅 덮어쓴다"와 구분이
# 안 되고, 그러면 사용자가 rc에 쓴 것이 조용히 사라진다 — 위 :279가
# tars.conf에 대해 CP-M1부터 갖고 있는 검사와 같은 자리다.
if grep -q "tars-init: seeded /config/" "$LOG2"; then
  report_failure "$LOG2" "second boot re-seeded an rc file; the user's edits would be gone"
fi
echo "boot 2: init left the existing rc files alone"
```

- [x] **Step 4: `boot_once` 호출의 주석과 배너를 고친다**

`config/check.sh`에서 **지울 것**:

```bash
echo "=== boot 2/2: same image, the guest-written config should pick the shell ==="
```

**넣을 것**:

```bash
echo "=== boot 2/3: same image, the guest-written config should pick the shell and its rc ==="
```

그리고 파일 위쪽의 **지울 것**:

```bash
echo "=== boot 1/2: empty disk, seed the config then edit it from inside the guest ==="
```

**넣을 것**:

```bash
echo "=== boot 1/3: empty disk, seed the config and the rc files, then edit them from inside ==="
```

- [x] **Step 5: CP 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh
```

**Expected:** `PASS`. 새 줄 셋이 보인다.

- [x] **Step 6: 커밋**

```bash
git add config/check.sh
git commit -m "Watch both shells run a line the user left on the disk"
```

---

## Task 6: 3차 부팅 — **`off`가 그것을 막는가**

**Files:** Modify `config/check.sh`

**design 결정 10이 "이 설계에서 가장 강한 검사"라고 적은 자리다.** 2차만
있으면 "rc를 읽는다"까지이고, `off`가 그것을 막는다는 것은 로그 수준에 머문다.

- [x] **Step 1: `LOG3`을 만든다**

`config/check.sh`에서 **지울 것**:

```bash
LOG1="$(mktemp)"
LOG2="$(mktemp)"
```

**넣을 것**:

```bash
LOG1="$(mktemp)"
LOG2="$(mktemp)"
LOG3="$(mktemp)"
```

- [x] **Step 2: 3차 부팅을 파일 끝의 `--- init log` 절 앞에 더한다**

`config/check.sh`의 `# 정보성. ext2가 "not clean"이라고...` 주석 **앞**에
**넣을 것**:

```bash
# ---------------------------------------------------------------- 3차 부팅
# 또 같은 이미지다. 2차가 tars.conf에 shell_config=off를 더해 두었다.
#
# **이 부팅은 아무것도 안 친다.** 볼 것이 전부 **없어야 할 것**이기 때문이다 —
# 타이핑을 하면 그 글자가 화면에 남고, 판정 글자가 우연히 화면에 생기는 길이
# 하나 늘어난다.
echo "=== boot 3/3: same image with shell_config=off, the rc must not run ==="
if ! boot_once "$LOG3" "tars-init: started console shell" watch_console_shell_quiet; then
  report_failure "$LOG3" "third boot never started a console shell"
fi

# 먼저 이 부팅이 **2차와 같은 기계인지** 확인한다. 아래 부정 검사는 "안
# 보인다"로 판정하므로, 기계가 애초에 안 떴어도 통과한다 — 그 구멍을
# 막는 것이 이 네 줄이다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG3"; then
  report_failure "$LOG3" "third boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=off" "$LOG3"; then
  report_failure "$LOG3" "third boot did not parse the shell_config=off the second boot appended"
fi
if ! grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$LOG3"; then
  report_failure "$LOG3" "third boot did not exec /usr/bin/zsh on the serial console"
fi
if ! grep -q "terminal: screen>" "$LOG3"; then
  report_failure "$LOG3" "the terminal never rendered on the third boot; the negative check would be vacuous"
fi

# ★ SC-M1이 증명하려는 나머지 절반. **같은 디스크, 같은 셸, 같은 rc 파일인데
#   한 줄이 바뀌어서 안 읽힌다.** 2차와 3차 사이에 달라진 것은 tars.conf의
#   마지막 줄 하나뿐이다.
if grep -q "tars-rc-alive" "$LOG3"; then
  report_failure "$LOG3" "shell_config=off did not stop the shells from reading /config/zshrc"
fi
echo "boot 3: shell_config=off kept both shells out of the rc that boot 2 ran"

if grep -q "tars-init: giving up on console shell" "$LOG3"; then
  report_failure "$LOG3" "the console shell kept dying on the third boot"
fi
if grep -q "Attempted to kill init" "$LOG3"; then
  report_failure "$LOG3" "kernel panicked because PID 1 exited on the third boot"
fi
```

- [x] **Step 3: 조용한 관측 훅을 더한다**

`config/check.sh`의 `watch_console_shell()` **뒤**에 **넣을 것**:

```bash
# 3차 부팅의 훅. **타이핑을 안 하므로 관측 창만 있다.** 2차가 쓰는 함수를
# 그대로 쓸 수 없는 이유는 그쪽이 설정을 고치기 때문이다 — 3차가 그것을
# 부르면 tars.conf에 off가 한 줄 더 붙는다(해롭진 않지만 거짓말이 된다).
watch_console_shell_quiet() {
  sleep 5
  return 0
}
```

- [x] **Step 4: 로그 덤프에 3차를 더한다**

`config/check.sh`에서 **지울 것**:

```bash
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true
```

**넣을 것**:

```bash
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true
echo "--- init log (boot 3) ---"
grep 'tars-init:' "$LOG3" || true
```

- [x] **Step 5: CP 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh
```

**Expected:** `PASS`. **부팅이 셋이라 이 체인은 약 1분 30초다.**

- [x] **Step 6: 커밋**

```bash
git add config/check.sh
git commit -m "Turn the key off and watch the same rc stay shut"
```

---

## Task 7: 음성 확인 — **검사가 진짜인가**

**Files:** 없음(되돌렸다가 `git checkout`으로 복구한다)

**왜 이 Task가 있는가.** UT-M1·M2·M3과 SC-M0이 네 번 배웠다. 특히 SC-M0의
실측 16이 남긴 것: **"검사를 넣었으면 그것이 죽는 경우를 직접 만들어 봐야
한다. 다른 검사가 먼저 죽으면 그 검사는 아직 아무것도 증명하지 않았다."**

**커밋하지 않는다.** 각 Step에서 **어느 검사가 죽었는지**를 그대로 기록한다 —
그것이 이 milestone의 실측이 된다.

- [x] **Step 1: 씨앗을 안 깔면 1차가 죽는가**

`init/src/main.zig`의 `if (storage_mounted) config.seedRcFiles();`를 임시로
지운 뒤 체인을 돌린다.

**Expected:** 1차 부팅의 `tars-config`가 모르는 명령이 되어 죽는다. **어느
줄이 먼저 반응하는지 본다** — `seeded` 로그 검사(Step 3에서 더한 것)는 훅보다
**뒤**에 있으므로, 훅 안의 화면 검사가 먼저 죽는 것이 정상이다.

```bash
git checkout init/src/main.zig
```

- [x] **Step 2: 씨앗이 있어도 `alias`가 없으면 죽는가**

`init/src/config.zig`의 fish 씨앗에서 `alias tars-config=...` 한 줄을 임시로
지운다. **`expectQuietSeed`의 "alias가 하나도 없으면" 검사가 호스트에서 먼저
죽는지**를 본다 — fish 씨앗에는 alias가 둘이라 하나를 지워도 호스트 검사는
통과하고, 그러면 화면 검사가 죽어야 한다. **둘 다 확인한다**(하나만 남기고,
그 다음 둘 다 지우고).

```bash
git checkout init/src/config.zig
```

- [x] **Step 3: 씨앗이 무언가를 찍으면 호스트 검사가 죽는가**

`init/src/config.zig`의 zsh 씨앗에 `echo hello` 한 줄을 임시로 더한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

**Expected:** **부팅하기 전에** FAIL —
`the zsh seed has a line that is neither a comment nor an alias`.
**이 Task에서 가장 중요한 Step이다.** 이 검사가 진짜가 아니면 M1이 남기는
것은 "다음 사람이 다섯 체인을 깨뜨릴 자유"뿐이다.

```bash
git checkout init/src/config.zig
```

- [x] **Step 4: `off`가 실제로 플래그를 안 주면 3차가 죽는가**

`init/src/main.zig`의 `console_flag`를 **조건 없이 null**로 되돌린다
(즉 SC-M0의 결정 4를 깨뜨린다).

**Expected:** **3차 부팅의 부정 검사가 죽는다** — 콘솔 zsh가 `-f` 없이 떠서
`tars-rc-alive`를 찍는다. 화면 셸은 여전히 `off`를 따르므로 `screen>` 줄에는
안 나온다. **SC-M0의 `tools/check.sh` 부정 검사가 잡은 것과 같은 결함을 이
체인이 다른 각도에서 잡는다는 뜻이다.**

```bash
git checkout init/src/main.zig
```

- [x] **Step 5: 되돌린 뒤 캐시를 지운다**

```bash
rm -rf init/zig-out terminal/zig-out
```

**Zig를 되돌린 뒤에는 이것을 한 번 한다**(UT design 실측 18). **SC-M1은
Zig를 건드리므로 이 함정이 살아 있다.**

- [x] **Step 6: 커밋하지 않는다**

---

## Task 8: 루트 게이트 3/3

**Files:** 없음

- [x] **Step 1: 백그라운드로 돌린다**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

**약 25분이다.** Bash 도구 상한이 10분이라 **백그라운드로 돌리고 주기적으로
`/tmp/gate.log`를 본다.**

- [x] **Step 2: 결과를 본다**

```bash
tail -30 /tmp/gate.log; cat /tmp/gate.time
```

**Expected:** 열한 체인이 전부 `PASS`, 3/3. 기준선은 SC-M0의
**24분 08.79초**이고, M1은 `config` 체인에 부팅 하나와 타이핑 다섯이 늘어
회차마다 세 번 돈다 — **design 위험 4가 +1분으로 적었고, 실제 수를 잰다.**

**`terminal` 쪽 `PASS`가 넷인 것이 정상이다** — 다섯 바이너리가 다 돌지만
`status_test.zig`만 `PASS`를 안 찍는다. **세는 것으로 판정하지 말 것.**

- [x] **Step 3: 씨앗이 다른 체인의 화면을 안 건드렸는지 직접 확인한다**

게이트가 초록이어도 이것을 따로 본다. **설정 디스크를 붙이는 체인이
다섯이고, 그 다섯의 셸이 이번 milestone부터 파일을 읽는다.**

```bash
grep -ac "tars-init: seeded /config/" /tmp/gate.log
grep -a "terminal: screen>" /tmp/gate.log | grep -c "alias"
grep -aic "syntax error\|parse error\|command not found\|Unknown command" /tmp/gate.log
```

**Expected:** 첫 수는 0보다 크고(다섯 체인 × 3회차 × 파일 셋 중 첫 부팅들),
둘째는 **0**(씨앗의 내용이 화면에 뜬 적이 없다 — 1차 부팅의 `tars-config`는
alias를 **부르지** 정의를 찍지 않는다), 셋째도 **0**이어야 한다.

**셋째 수가 0이 아니면 씨앗의 문법이 어느 셸에서 안 먹은 것이다.**

---

## Task 9: 문서

**Files:**
- Modify `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
- Modify `docs/decisions/project_shell_config.md`
- Modify `MEMORY.md`
- Modify `CLAUDE.md`
- Modify `HANDOFF.md`

- [x] **Step 1: design의 `Status:` 줄과 실측 절을 고친다**

`Status:`를 **SC-M1 완료**로 바꾸고, Task 7의 음성 확인 결과와 Task 8의 게이트
시간을 **"SC-M1이 실행으로 증명한 것"** 절로 더한다(실측 22부터).

- [x] **Step 2: `docs/decisions/project_shell_config.md`에 M1의 기억을 더한다**

**다시 캐지 말 것**: 씨앗이 조용해야 하는 이유와 그것을 지키는 장치,
`tars-config` alias가 게이트의 판정으로도 쓰인다는 것, 판정 글자를 씨앗이
아니라 사람이 심는 이유.

- [x] **Step 3: `MEMORY.md`의 해당 줄을 고친다**

- [x] **Step 4: `CLAUDE.md`의 Shell Config 문단을 고친다**

**SC-M2가 아직 남아 있으므로 여전히 진행 중으로 적는다.**

- [x] **Step 5: `HANDOFF.md`를 새로 쓴다**

맨 위가 SC-M1이고 그 아래가 SC-M0이다.

- [x] **Step 6: 커밋**

```bash
git add docs MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Write down what the shells did with the files we left them"
```

---

## 이 milestone이 게이트로 **못 보는 것** — 알고 둔다

| 못 보는 것 | 왜 |
|---|---|
| **bash·fish의 rc가 읽히는가** | 게이트가 rc를 실제로 읽히는지 보는 것은 **zsh 하나**다(2차·3차 부팅의 셸). fish는 1차의 `tars-config`가 alias 하나로 보지만 **`off`가 그것을 막는지는 안 본다**. bash는 로그의 `seeded` 한 줄이 전부다 |
| 씨앗의 **내용이 맞는가** | 호스트 검사가 보는 것은 **문법 범주**(주석/alias)와 자기 경로 한 줄이다. alias의 명령이 실제로 도는지는 1차의 `tars-config` 하나만 본다 |
| `off`일 때 **씨앗을 여전히 깐다**는 것 | 코드가 `shell_config`를 안 보는 구조라 게이트가 따로 볼 것이 없다. 3차 부팅은 파일이 **이미 있는** 상태라 이 갈래를 안 지난다 |
| rc가 **셸을 죽이면** 어떻게 되는가 | **SC-M2의 일이다**(탈출로 둘). M1까지는 design 위험 3이 열려 있고, 우리가 까는 것이 무해하다는 것만 보장한다 |
| 사용자가 rc를 **지웠을 때** 다시 깔리는가 | 코드로는 깔린다(`O_EXCL`이 ENOENT를 안 낸다). 게이트가 그 갈래를 안 지난다 |
