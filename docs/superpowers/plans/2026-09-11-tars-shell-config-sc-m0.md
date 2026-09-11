# SC-M0 Implementation Plan — 셸이 rc를 읽을 자리를 만든다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `tars.conf`의 새 키 `shell_config`가 셸의 no-config 플래그를
켜고 끄고, `/config`의 rc 파일 셋이 링크로 홈에 이어진다. **파일은 아직 안
깐다**(그것은 SC-M1이다) — 이 milestone이 세우는 것은 **자리**다.

**Architecture:** 새 파일이 하나도 없다. 고치는 것은 다섯이고 그중 넷이
이미 같은 일을 하고 있는 자리다 — `config.zig`에 여섯째 키를 더하고
(다섯이 전부 같은 enum 화이트리스트 모양이다), `main.zig`가 그 값을 argv로
옮기고, `terminal`이 그것을 받아 셸에 붙일지 말지 정하고,
`make_initrd.sh`가 링크 셋을 건다(UT-M3이 `.gitconfig`에 한 것과 같은
자리). **`"none"` 토큰 하나가 이 설계의 이음매다** —
`Toggles.arg`가 빈 집합에 쓰는 이름과 같은 모양이고, argv를 짓는 쪽과 쓰는
쪽이 다른 화면 셸에만 필요하다.

**Tech Stack:** Zig(init · terminal) · bash(`make_initrd.sh` · 게이트 체인)
· QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
— 특히 **결정 1·2·3·4·6**과 **실측 9(프롬프트는 게이트의 좌표계다) ·
실측 14(프로브)**. 결정 5는 **철회됐다** — 그 자리를 읽고 `/.zshenv`를
만들지 말 것.

---

## 착수 전에 이 세션이 실측한 것 — **위험 둘을 닫았고 하나가 기각됐다**

전문은 design의 실측 14다. 여기에는 **이 plan을 바꾼 것**만 적는다.

### 1. 인사말은 뜨고, 빈 환경 변수가 그것을 막는다

```
root@(none) ~# fish | Welcome to fish, the friendly interactive shell | Type help for ...
root@(none) ~# env fish_greeting= fish | root@(none) ~#
```

첫 줄은 플래그 없이 띄운 fish이고 둘째 줄은 `fish_greeting`을 빈 값으로 준
것이다. **Task 4의 `setenv` 한 줄이 이 관측 위에 선다.**

### 2. **프롬프트가 안 움직인다** — 이것이 이 milestone의 위험을 절반으로 줄였다

위 둘째 줄의 `root@(none) ~#`는 **안쪽 fish가 그린 것**이다. 설정을 다 읽은
fish의 기본 프롬프트가 `--no-config`로 뜬 것과 **글자까지 같다.**

**그래서 화면을 grep하는 여섯 체인이 안 흔들린다.** design 실측 9가 걱정한
좌표계(`copy/check.sh`의 `col 20`)가 그대로 선다. 재기 전에는 추론이었다.

### 3. zsh 마법사는 안 뜬다 — **결정 5가 철회됐다**

```
root@(none) ~# zsh | (none)#
```

`/.zshrc`도 `/.zshenv`도 없는 게스트에서 `-f` 없이 띄운 zsh가 곧바로
프롬프트를 냈다. **`/.zshenv`를 만드는 Task가 이 plan에 없는 이유다.**

### 4. `sendkey`의 `shift-minus`가 게스트에 닿는다

밑줄이 제대로 쳐졌다(`fish_greeting=`). UT-M3 실측 9가 *"이 저장소의 체인은
그것을 쓴 적이 없다"*고만 적은 것에 대한 답이다. **이 plan은 그래도 안
쓴다** — 칠 것이 전부 소문자와 공백이다.

### 5. **`ps ax`가 셸의 argv를 화면에 보여 준다** — M0이 게이트로 증명할 수 있다

UT-M1이 이미 그것을 친다(`tools/check.sh` 검사 5). 지금 화면에 이렇게 나온다:

```
31 ?      S    0:00 /terminal /usr/bin/fish --no-config apple ...
33 pts/0  Ssl  0:00 /usr/bin/fish --no-config
```

**SC-M0 뒤에는 저 두 줄에서 `--no-config`가 사라지고 첫 줄에 `none`이
선다.** 플래그 변경이 로그가 아니라 **화면에서** 보인다는 뜻이고, Task 6이
그것을 검사로 만든다. 이 사실을 안 찾았으면 M0의 게이트는 정적 검사와 로그
한 줄뿐이었을 것이다.

### 6. cpio 안의 이름에는 `./`가 없다

```
$ gzip -dc kernel/initrd.cpio | cpio -it | grep -E '^(bin/sh|etc/passwd|\.gitconfig)$'
bin/sh
etc/passwd
.gitconfig
```

**Task 6의 `WANT` 항목을 `.bashrc`로 적지 `./` 를 붙이지 않는다.**
`tools/check.sh:120`의 주석이 같은 것을 적고 있다.

---

## File Structure

| 파일 | 무엇을 맡나 | 이 milestone이 하는 일 |
|---|---|---|
| `init/src/config.zig` | 설정 파일의 문법과 기본값. **파서는 여기 한 벌뿐이다** | `ShellConfig` enum · `Config`의 여섯째 필드 · `parse` 분기 · `save` 씨앗 텍스트 · `Shell.configFlag()` |
| `init/src/config_test.zig` | 위 파일에서 시스템 콜이 없는 `parse`를 호스트에서 검증 | `expect()`를 **여섯 필드로 넓히고** 검사 다섯을 더한다 |
| `init/src/main.zig` | PID 1. 설정을 읽어 argv로 옮기고 자식 둘을 감독 | 로그 줄 넓히기 · 자식 둘의 플래그 슬롯 |
| `terminal/src/main.zig` | 화면 셸을 PTY에 띄운다 | `"none"`을 받으면 셸 argv에 안 붙인다 · `fish_greeting` |
| `kernel/make_initrd.sh` | initrd 트리를 손으로 짓는다 | 링크 셋과 디렉터리 하나 |
| `tools/check.sh` | UT 체인 | 정적 검사에 셋 추가 · `ps ax` 화면 검사 |
| `config/check.sh` | CP 체인 | 1차 부팅 로그에 `shell_config=on` |

**새 파일이 없고, 새 체인도 없다.**

---

## Task 1: `config_test.zig`를 먼저 넓힌다 — **실패를 본다**

**Files:** Modify `init/src/config_test.zig`

**왜 이것이 먼저인가.** 이 파일의 주석이 이미 답을 적어 두었다 —
*"필드 넷을 전부 비교한다. HI-M2가 둘을 더하면서 넓혔는데, 안 넓혔다면 새
키의 검사가 아무것도 안 보고 초록이 떴을 것이다."* **`expect()`를 안 넓히고
검사만 더하면 그 검사는 tautology다.**

- [ ] **Step 1: `expect()`의 비교와 출력에 여섯째 필드를 더한다**

`init/src/config_test.zig`의 비교 조건에서 **지울 것**:

```zig
        got.latin_layout == want.latin_layout and
```

**넣을 것**:

```zig
        got.latin_layout == want.latin_layout and
        // **SC-M0: 여섯째 필드.** 이 줄이 없으면 아래 shell_config 검사가
        // 아무것도 안 보고 초록으로 지나간다 — 이 함수의 머리 주석이
        // HI-M2에 대해 적어 둔 것과 글자 그대로 같은 자리다.
        got.shell_config == want.shell_config and
```

같은 파일의 `std.debug.print` 포맷에서 **지울 것**:

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n",
```

**넣을 것**:

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n",
```

인자 목록에서 **지울 것**(두 자리):

```zig
            got.hangul_toggle.arg(&got_buf),
```

**넣을 것**:

```zig
            got.hangul_toggle.arg(&got_buf),
            @tagName(got.shell_config),
```

그리고 **지울 것**:

```zig
            want.hangul_toggle.arg(&want_buf),
```

**넣을 것**:

```zig
            want.hangul_toggle.arg(&want_buf),
            @tagName(want.shell_config),
```

- [ ] **Step 2: 검사 다섯을 `main()` 끝에 더한다**

`init/src/config_test.zig`의 `pub fn main()` 안, 마지막 `try expect(...)`
뒤에 **넣을 것**:

```zig
    // ── SC-M0: 여섯째 키 ────────────────────────────────────────────────
    //
    // **앞의 다섯과 완전히 같은 모양이다**(hangul_toggle만 다르다).
    // enum이 화이트리스트이고, 모르는 값은 기본값에 머문다.
    try expect("shell_config=off\n", .{ .shell_config = .off });
    // 기본값을 명시적으로 적는 것도 통과한다. 씨앗 파일이 실제로 그렇게
    // 생겼으므로 이 왕복이 참이어야 한다.
    try expect("shell_config=on\n", .{});
    try expect("shell_config=yes\n", .{}); // enum에 없는 값
    try expect("shell_config=\n", .{}); // 값 없음
    // 다른 키와 섞여도 각자 선다. 깨진 줄 하나가 파일 전체를 무효로 만들지
    // 않는다는 성질이 여섯째 키에도 그대로 적용된다.
    try expect("shell=zsh\nshell_config=off\n", .{ .shell = .zsh, .shell_config = .off });
```

- [ ] **Step 3: 컴파일 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

**Expected:** FAIL. `Config`에 `shell_config` 필드가 없으므로
`got.shell_config`와 `.{ .shell_config = .off }`가 전부 컴파일 에러다
(`no field named 'shell_config'`). **테스트 실패가 아니라 컴파일 실패인
것이 정상이다** — Zig에서 구조체 필드는 타입이라 런타임까지 안 간다.

- [ ] **Step 4: 아직 커밋하지 않는다**

Task 2와 함께 커밋한다. 컴파일이 안 되는 상태를 히스토리에 남기지 않는다.

---

## Task 2: `config.zig`에 여섯째 키를 더한다 — **결정 2·3**

**Files:** Modify `init/src/config.zig`

- [ ] **Step 1: `ShellConfig` enum을 `Shell` 위에 더한다**

`init/src/config.zig`의 `pub const Shell = enum {` **바로 앞**에 **넣을 것**:

```zig
/// 셸이 사용자의 rc 파일을 읽을 것인가(SC design 결정 2).
///
/// **`bool`이 아니라 enum인 데 뜻이 있다.** 이 파일의 다른 키가 전부
/// `stringToEnum` 화이트리스트이고, 그 모양을 따르면 "모르는 값은 로그만
/// 남기고 기본값에 머문다"는 규칙이 공짜로 따라온다. 여섯째 키만 다른
/// 모양일 이유가 없다.
pub const ShellConfig = enum {
    on,
    off,
};
```

- [ ] **Step 2: `Shell`에 `configFlag()`를 더한다**

`init/src/config.zig`의 `noConfigFlag` 함수 **바로 뒤**, `Shell`의 닫는
`};` 앞에 **넣을 것**:

```zig
    /// terminal의 argv에 넣을 값(SC design 결정 3). `off`면 위 플래그이고,
    /// `on`이면 **`"none"`**이다.
    ///
    /// **왜 빈 문자열이나 null이 아닌가.** terminal은 argv를 **짓는 쪽과
    /// 쓰는 쪽이 다르다** — 이 값이 프로세스 경계를 문자열로 건너가므로
    /// "인자가 없다"를 포인터로 표현할 수 없고, 빈 문자열을 넣으면 저쪽에서
    /// "인자를 안 받았다"와 구분이 안 된다. `Toggles.arg`가 빈 집합에
    /// `none`을 쓰는 것과 **글자 그대로 같은 이유다**(아래 그 주석을 볼 것).
    ///
    /// 콘솔 셸은 이 함수를 안 쓴다. 그쪽은 init이 argv를 직접 짓기 때문에
    /// 슬롯을 null로 두면 그만이다.
    pub fn configFlag(self: Shell, sc: ShellConfig) [:0]const u8 {
        return switch (sc) {
            .off => self.noConfigFlag(),
            .on => "none",
        };
    }
```

- [ ] **Step 3: `Config`에 필드를 더한다**

`init/src/config.zig`의 `hangul_toggle: Toggles = .{` 블록이 끝나는 `},`
**뒤**, `Config`의 닫는 `};` 앞에 **넣을 것**:

```zig
    /// **기본값이 `on`인 근거는 위 `keyboard`·`hangul_layout`과 같다** —
    /// 이 기계를 쓰는 사람이 쓰는 것이 기본값이고, 이 기계는 개발용이다.
    /// embedded 장비의 init 1으로 쓰는 사람은 `keyboard=pc`를 적듯 `off`를
    /// 명시적으로 적는다(design 비목표 4).
    shell_config: ShellConfig = .on,
```

- [ ] **Step 4: `parse`에 분기를 더한다**

`init/src/config.zig`의 `parse` 안에서 **지울 것**:

```zig
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

**넣을 것**:

```zig
        } else if (std.mem.eql(u8, key, "shell_config")) {
            // shell·keyboard·자판 둘과 완전히 같은 모양이다. `hangul_toggle`만
            // 집합이라 다르고, 여섯째 키는 다시 enum 하나다.
            c.shell_config = std.meta.stringToEnum(ShellConfig, value) orelse {
                std.debug.print("tars-init: unknown shell_config '{s}', falling back to {s}\n", .{
                    value, @tagName(c.shell_config),
                });
                continue;
            };
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

- [ ] **Step 5: `save`의 씨앗 텍스트에 두 줄을 더한다**

`init/src/config.zig`의 `save` 안 `bufPrint` 템플릿에서 **지울 것**:

```zig
        \\hangul_toggle={s}
        \\
    , .{
```

**넣을 것**:

```zig
        \\hangul_toggle={s}
        \\# shell_config: on | off
        \\#   on이면 셸이 홈의 rc 파일을 읽는다. 그 파일들은 /config에 있고
        \\#   홈에는 링크만 있다 — /config/bashrc · /config/zshrc ·
        \\#   /config/fish.config. off면 셸이 설정 없이 뜬다
        \\shell_config={s}
        \\
    , .{
```

같은 `bufPrint`의 인자 목록에서 **지울 것**:

```zig
        c.hangul_toggle.arg(&toggle_buf),
    }) catch return error.FormatFailed;
```

**넣을 것**:

```zig
        c.hangul_toggle.arg(&toggle_buf),
        @tagName(c.shell_config),
    }) catch return error.FormatFailed;
```

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

**Expected:** 아무 출력 없이 종료 코드 0. `FAIL: input=` 줄이 하나도 없어야
한다.

- [ ] **Step 7: 커밋**

```bash
git add init/src/config.zig init/src/config_test.zig
git commit -m "Give the config file a sixth key and the shells a choice"
```

---

## Task 3: PID 1이 그 값을 자식 둘에게 나른다 — **결정 3·4**

**Files:** Modify `init/src/main.zig`

- [ ] **Step 1: 플래그 둘을 만든다**

`init/src/main.zig`에서 **지울 것**:

```zig
    const shell_flag = shell.noConfigFlag();
```

**넣을 것**:

```zig
    // SC-M0 결정 3. `off`면 지금까지의 플래그이고, `on`이면 `"none"`이다 —
    // terminal이 그 값을 보면 셸 argv에 아무것도 안 붙인다.
    const shell_flag = shell.configFlag(cfg.shell_config);
    // **콘솔 셸은 `"none"`을 안 쓴다**(결정 4). 이쪽은 init이 셸을 직접
    // exec하므로 argv를 짓는 쪽과 쓰는 쪽이 같다 — "인자가 없다"를 null
    // 슬롯으로 그대로 말할 수 있다. 지금까지 이 자리는 **조건 없이 null**
    // 이었고, `main.zig`의 아래 주석이 *"나중에 설정 파일이 생기면 그것을
    // 읽는 편이 맞다"*고 예고해 둔 자리다.
    const console_flag: ?[*:0]const u8 = switch (cfg.shell_config) {
        .on => null,
        .off => shell.noConfigFlag().ptr,
    };
```

- [ ] **Step 2: 로그 줄을 넓힌다**

`init/src/main.zig`의 `std.debug.print`에서 **지울 것**:

```zig
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n",
```

**넣을 것**:

```zig
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n",
```

같은 호출의 인자 목록에서 **지울 것**:

```zig
            toggle_arg,
        },
    );
```

**넣을 것**:

```zig
            toggle_arg,
            @tagName(cfg.shell_config),
        },
    );
```

**새 줄을 만들지 않는 것이 요점이다.** 다른 체인들이
`tars-init: config shell=`으로 grep하고 있어서 앞부분이 안 바뀌어야 한다 —
이 줄 바로 위의 주석이 HI-M2에 대해 같은 것을 적고 있다.

- [ ] **Step 3: 콘솔 셸의 argv 슬롯을 쓴다**

`init/src/main.zig`의 `children` 배열에서 **지울 것**:

```zig
            // 콘솔 셸에는 플래그를 주지 않는다. 이쪽은 사용자가 직접 쓰는
            // 자리이므로, 나중에 설정 파일이 생기면 그것을 읽는 편이 맞다.
            .argv = .{ shell_path.ptr, null, null, null, null, null, null, null },
```

**넣을 것**:

```zig
            // **위 주석이 예고한 것을 SC-M0이 실행한 자리다.** 그때 적어
            // 둔 것은 *"나중에 설정 파일이 생기면 그것을 읽는 편이 맞다"*
            // 였고, 이제 설정 파일이 생겼다. `on`이면 이 슬롯이 null이라
            // 지금까지와 같고, `off`면 플래그가 들어간다 — **두 셸이 같은
            // 설정을 따른다**(결정 4).
            .argv = .{ shell_path.ptr, console_flag, null, null, null, null, null, null },
```

- [ ] **Step 4: 빌드와 호스트 테스트**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

**Expected:** 종료 코드 0, 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add init/src/main.zig
git commit -m "Carry the new key to both children and say it in one line"
```

---

## Task 4: terminal이 `"none"`을 읽고, 인사말을 끈다 — **결정 3·6**

**Files:** Modify `terminal/src/main.zig`

- [ ] **Step 1: 인사말을 끈다**

`terminal/src/main.zig`의 `_ = setenv("LANG", "C.UTF-8", 1);` **바로 뒤**에
**넣을 것**:

```zig
    // SC-M0 결정 6. **TERM·LANG과 같은 자리에 있는 이유가 TERM과 같다** —
    // 값이 두 셸에서 갈려야 해서 여기 있다. 화면은 TARS의 화면이라 다른
    // 제품의 배너가 뜰 자리가 아니고, 시리얼 콘솔은 fish를 그대로 보는
    // 자리다(machine/check.sh:117이 그 인사말을 UEFI 부팅의 마커로 쓴다 —
    // **여기서 끄면 그 마커가 살고, /etc/fish/config.fish로 끄면 죽는다**).
    //
    // fish의 `fish_greeting` 함수는 `set -q fish_greeting`이 참이면 기본
    // 문구를 안 만들고, 값이 비어 있으면 아무것도 안 찍는다. 환경 변수는
    // fish에서 전역 변수로 보이므로 `set -q`가 참이 된다. 2026-09-11에
    // 게스트에서 확인했다(design 실측 14(b)).
    //
    // bash·zsh는 이런 이름의 환경 변수를 모른다 — 조건 없이 넣는다.
    _ = setenv("fish_greeting", "", 1);
```

- [ ] **Step 2: `"none"`이면 셸 argv에 안 붙인다**

`terminal/src/main.zig`에서 **지울 것**:

```zig
    const argv = [_:null]?[*:0]const u8{ shell_path, shell_flag };
```

**넣을 것**:

```zig
    // SC-M0 결정 3. init이 `"none"`을 넘기면 셸에 플래그를 안 붙인다 —
    // 슬롯을 null로 덮으면 execv가 거기서 멈추므로 배열 길이를 안 바꿔도
    // 된다(sentinel은 그대로 배열 끝에 있다).
    //
    // **문자열 하나로 말하는 이유**는 `config.zig`의 `configFlag` 주석에
    // 있다 — argv를 짓는 쪽(PID 1)과 쓰는 쪽(여기)이 프로세스 경계로
    // 갈려 있어서 "인자가 없다"를 포인터로 못 보낸다.
    var argv = [_:null]?[*:0]const u8{ shell_path, shell_flag };
    if (std.mem.eql(u8, std.mem.span(shell_flag), "none")) argv[1] = null;
```

`shell_flag`를 선언하는 줄의 주석에서 **지울 것**:

```zig
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // no-config 플래그(fish --no-config / bash --norc / zsh -f)를 계속 주는
    // 이유는 프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있기 때문이다.
```

**넣을 것**:

```zig
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    //
    // **SC-M0 전에는 이 플래그가 조건 없이 붙었다.** 이유로 적혀 있던 것은
    // "프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있다"였는데,
    // 2026-09-11에 재 보니 **설정을 다 읽은 fish의 프롬프트가 `--no-config`로
    // 뜬 것과 글자까지 같았다**(design 실측 14(c)). 그 이유는 이제 없다.
    //
    // 인자 없이 손으로 실행할 때의 기본값은 `--no-config`로 남긴다 — 그때는
    // init이 없어서 `"none"`을 넘겨줄 사람이 없다.
```

- [ ] **Step 3: 빌드**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh'
```

**Expected:** 종료 코드 0. `prepare.sh`가 다섯 바이너리를 빌드한다.

- [ ] **Step 4: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Let none mean no flag, and hush a banner meant for someone else"
```

---

## Task 5: 링크 셋을 건다 — **결정 1**

**Files:** Modify `kernel/make_initrd.sh`

- [ ] **Step 1: `.gitconfig` 링크 뒤에 링크 셋을 더한다**

`kernel/make_initrd.sh`의 `ln -sf config/gitconfig "$WORKDIR/.gitconfig"`
줄 **바로 뒤**에 **넣을 것**:

```bash
# SC-M0 결정 1. **위 .gitconfig과 글자 그대로 같은 문제에 같은 답이다** —
# 셸의 rc 파일도 $HOME에서 읽히고 게스트의 HOME은 / 이며 /는 tmpfs다.
# 영속하는 것은 /config 하나뿐이다.
#
# **/config 안은 평평하다.** fish만 홈에서 한 단 더 깊은 자리를 쓰는데
# ($XDG_CONFIG_HOME/fish/config.fish, 즉 /.config/fish/config.fish),
# 대상 이름을 fish.config로 두어 gitconfig·bashrc·zshrc와 같은 층에
# 세운다 — /config/fish/ 디렉터리를 만들면 그 디렉터리는 fish만 쓴다.
#
# **파일은 여기서 안 만든다.** initrd에 넣으면 tmpfs에 생겨서 부팅마다
# 초기화되고, 그러면 링크가 가리키는 자리와 파일이 있는 자리가 갈린다.
# 씨앗은 init이 /config를 마운트한 뒤에 깐다(SC-M1).
#
# **설정 디스크를 못 찾으면?** .gitconfig과 같다 — 링크가 initrd 안의 빈
# /config를 가리키고 셸은 rc가 없는 채로 뜬다. **부팅을 안 막는다.**
mkdir -p "$WORKDIR/.config/fish"
ln -sf ../../config/fish.config "$WORKDIR/.config/fish/config.fish"
ln -sf config/bashrc "$WORKDIR/.bashrc"
ln -sf config/zshrc "$WORKDIR/.zshrc"
```

- [ ] **Step 2: initrd를 짓고 링크 셋을 눈으로 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./make_initrd.sh && gzip -dc initrd.cpio | cpio -it 2>/dev/null | grep -E "^(\.bashrc|\.zshrc|\.config/fish/config\.fish|\.gitconfig)$"'
```

**Expected:** 네 줄이 나온다.

```
.gitconfig
.config/fish/config.fish
.bashrc
.zshrc
```

순서는 다를 수 있다. **`./` 접두사가 붙어 있으면 안 된다**(실측 6).

- [ ] **Step 3: 커밋**

```bash
git add kernel/make_initrd.sh
git commit -m "Point three rc names at the only disk that survives"
```

---

## Task 6: 게이트가 링크 셋과 argv를 본다

**Files:** Modify `tools/check.sh`

- [ ] **Step 1: 정적 검사에 링크 셋을 더한다**

`tools/check.sh`에서 **지울 것**:

```bash
WANT+=(usr/bin/vi usr/bin/pager usr/bin/editor .gitconfig
       usr/share/git-core/templates/info/exclude)
```

**넣을 것**:

```bash
WANT+=(usr/bin/vi usr/bin/pager usr/bin/editor .gitconfig
       usr/share/git-core/templates/info/exclude)

# **SC-M0: 링크 셋.** 위 .gitconfig과 같은 자리이고 같은 이유로 여기
# literal이다 — 배열(guest_tools.sh)은 바이너리만 알고 이 셋은 make_initrd.sh가
# 손으로 건다. 그래서 **이 셋에 대해서는 검사 1이 tautology가 아니다.**
#
# 가리키는 대상(/config/bashrc 등)은 여기서 안 본다. 그 파일은 initrd가
# 아니라 **설정 디스크**에 있고, 이 체인에는 디스크가 없다(SC-M1이
# config 체인에서 그것을 본다).
WANT+=(.bashrc .zshrc .config/fish/config.fish)
```

- [ ] **Step 2: `ps ax` 검사에 argv 판정을 더한다**

`tools/check.sh`에서 이 줄을 찾는다(검사 5의 마지막 줄이다):

```bash
echo "ps walked /proc and found the supervised terminal"
```

**그 줄 바로 뒤**, `# ── 검사 6: awk가 돈다` 주석 **앞**에 **넣을 것**:

```bash
# ── SC-M0: 같은 화면으로 플래그를 본다 ─────────────────────────────────
#
# **`ps ax`가 자식 둘의 argv를 그대로 보여 준다.** SC-M0 전에는 이렇게
# 나왔다:
#
#   31 ?      S    0:00 /terminal /usr/bin/fish --no-config apple ...
#   33 pts/0  Ssl  0:00 /usr/bin/fish --no-config
#
# 기본값이 shell_config=on이므로 이제 첫 줄의 셋째 인자가 `none`이고
# 둘째 줄에는 인자가 아예 없다. **부팅을 더 안 쓰고 플래그 변경을 화면에서
# 증명한다** — 이 체인이 이미 치는 명령의 출력을 한 번 더 보는 것뿐이다.
#
# 긍정과 부정을 둘 다 본다. 긍정만 보면 init이 `none`을 넘겼다는 것까지이고,
# **부정이 있어야 terminal이 그것을 실제로 안 붙였다는 것까지** 간다.
# 파이프 대신 here-string을 쓰는 것은 이 스크립트의 pipefail 때문이다
# (gate_lib.sh:107의 주석과 같다). 이름을 PS_SCREEN으로 두는 것은
# gate_lib.sh의 wait_for_screen이 `screen`이라는 지역 변수를 쓰고 있어서다.
PS_SCREEN="$(grep -a "terminal: screen>" "$LOG")"
if ! grep -aq -- "/usr/bin/fish none" <<<"$PS_SCREEN"; then
  fail "init did not pass 'none' to the terminal; shell_config never reached argv" \
    "terminal: screen>" "tars-init: config shell="
fi
if grep -aq -- "--no-config" <<<"$PS_SCREEN"; then
  fail "a shell still carries --no-config even though shell_config defaults to on" \
    "terminal: screen>"
fi
echo "both children run without a no-config flag (shell_config=on reached argv)"
```

- [ ] **Step 3: UT 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** 마지막 줄이 `PASS`. 새 줄 둘이 보인다 —
`the initrd carries the four bones and all 65 tools the list names`와
`both children run without a no-config flag (shell_config=on reached argv)`.

**실패하면 가장 먼저 볼 것:** `ps ax` 출력이 80칸에서 잘렸는지.
`grep -a "terminal: screen>" "$LOG" | tail -1`로 마지막 프레임을 찍어
`/usr/bin/fish` 뒤에 무엇이 있는지 눈으로 본다 — **판정 문자열을
`/usr/bin/fish none`으로 잡은 것이 `/terminal`을 뺀 이유가 그 폭이다**
(`/terminal`은 바로 앞 검사가 이미 본다).

- [ ] **Step 4: 커밋**

```bash
git add tools/check.sh
git commit -m "Read the flag off the screen the chain already prints"
```

---

## Task 7: CP 체인이 새 키를 로그에서 본다

**Files:** Modify `config/check.sh`

- [ ] **Step 1: 1차 부팅 판정에 한 줄을 더한다**

`config/check.sh`에서 **지울 것**:

```bash
if ! grep -q "tars-init: config shell=fish" "$LOG1"; then
```

이 검사 블록(`report_failure`와 그 아래 `fi`까지)은 그대로 두고, **그 `fi`
바로 뒤**에 **넣을 것**:

```bash
# SC-M0. **같은 줄을 넓혀서 본다** — 새 줄을 안 만든 이유는 이 파일과
# 다른 체인들이 `tars-init: config shell=`을 앞부분으로 grep하고 있기
# 때문이다(main.zig의 그 자리 주석이 HI-M2에 대해 같은 것을 적고 있다).
#
# **여기가 게이트에서 기본값을 보는 유일한 자리다.** 씨앗 파일이 실제로
# `shell_config=on`을 담았다는 것은 SC-M1이 2차 부팅으로 본다 — 이 검사가
# 보는 것은 **파서가 그 키를 알고, 기본값이 on이라는 것**까지다.
if ! grep -q "tars-init: config shell=fish.*shell_config=on" "$LOG1"; then
  report_failure "$LOG1" "first boot did not report the default shell_config=on"
fi
echo "boot 1: init reported shell_config=on (the sixth key reached the log)"
```

- [ ] **Step 2: CP 체인 단독 실행**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh
```

**Expected:** 마지막 줄이 `PASS`. 새 줄
`boot 1: init reported shell_config=on (the sixth key reached the log)`이
보인다. **부팅이 둘이라 이 체인은 약 1분이다.**

- [ ] **Step 3: 커밋**

```bash
git add config/check.sh
git commit -m "Ask the first boot which way the sixth key points"
```

---

## Task 8: 음성 확인 — **검사가 진짜인가**

**Files:** 없음(되돌렸다가 `git checkout`으로 복구한다)

**왜 이 Task가 있는가.** UT-M1·M2·M3이 세 번 다 배운 것이다 — 목록과 검사가
같은 파일을 보면 그 검사는 초록인데 아무것도 안 보는 검사다. **커밋하지
않는다.**

- [ ] **Step 1: 링크 하나를 지우고 정적 검사가 죽는지 본다**

`kernel/make_initrd.sh`에서 `ln -sf config/bashrc "$WORKDIR/.bashrc"` 한
줄을 임시로 지운 뒤:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** **부팅하기 전에** FAIL. 메시지에 `.bashrc`가 보인다.

```bash
git checkout kernel/make_initrd.sh
```

- [ ] **Step 2: terminal의 `"none"` 처리를 지우고 화면 검사가 죽는지 본다**

`terminal/src/main.zig`에서 다음 한 줄을 임시로 지운다:

```zig
    if (std.mem.eql(u8, std.mem.span(shell_flag), "none")) argv[1] = null;
```

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** FAIL. **정적 검사 1은 초록으로 지나가고** `ps ax` 검사가
죽는다 — 셸 argv에 `none`이 문자 그대로 붙어 있을 것이고(fish는 모르는
인자를 파일 이름으로 본다), 긍정 검사는 통과하지만 그 앞의 검사들이 먼저
반응할 수 있다. **어느 검사가 죽었는지 메시지를 그대로 기록한다** — 그것이
이 milestone의 실측이 된다.

```bash
git checkout terminal/src/main.zig
```

- [ ] **Step 3: `Config`의 기본값을 `off`로 바꾸고 둘이 다 죽는지 본다**

`init/src/config.zig`에서 `shell_config: ShellConfig = .on,`을
`.off,`로 임시로 바꾼 뒤:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh
```

**Expected:** FAIL — `ps ax` 화면에 `--no-config`가 돌아온다.

```bash
git checkout init/src/config.zig
```

- [ ] **Step 4: 되돌린 뒤 캐시를 지운다**

```bash
rm -rf init/zig-out terminal/zig-out
```

**Zig를 되돌린 뒤에는 이것을 한 번 한다**(UT design 실측 18). M1·M2·M3은
Zig를 안 건드려서 이 함정이 없었는데, **SC-M0은 Zig를 건드린다.**

- [ ] **Step 5: 커밋하지 않는다**

결과는 design의 실측 절에 문장으로 적는다(Task 10).

---

## Task 9: 루트 게이트 3/3

**Files:** 없음

- [ ] **Step 1: 백그라운드로 돌린다**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

**약 24분이다.** 호스트에서 `make`를 직접 부르면 안 된다 — 호스트 make가
3.81이라 커널 Makefile이 거절한다. Bash 도구 상한이 10분이라
**백그라운드로 돌리고 주기적으로 `/tmp/gate.log`를 본다.**

- [ ] **Step 2: 결과를 본다**

```bash
tail -30 /tmp/gate.log; cat /tmp/gate.time
```

**Expected:** 열한 체인이 전부 `PASS`, 3/3. 기준선은 UT-M3의
**23분 43.15초**이고, SC-M0은 initrd가 링크 셋만 늘어서 **잡음 ±3분 안**이어야
한다.

**`terminal` 쪽 `PASS`가 넷인 것이 정상이다** — 다섯 바이너리가 다 돌지만
`status_test.zig`만 `PASS`를 안 찍는다. **세는 것으로 판정하지 말 것.**

- [ ] **Step 3: 인사말이 화면에 없는지 직접 확인한다**

게이트가 초록이어도 이것을 따로 본다 — **어느 체인도 "인사말이 없다"를
판정으로 갖고 있지 않다.**

```bash
grep -c "Welcome to fish" /tmp/gate.log
```

**Expected:** 0보다 크다(시리얼 콘솔 셸이 찍는 것과 `machine/check.sh`의
마커가 있다). **화면 줄에는 없어야 한다:**

```bash
grep -a "terminal: screen>" /tmp/gate.log | grep -c "Welcome to fish"
```

**Expected:** `0`. **이 수가 0이 아니면 결정 6이 안 먹은 것이고, 그때는
`/etc/fish/config.fish`로 옮기고 `machine/check.sh:117`의 마커를 fish
프롬프트로 바꾼다.**

---

## Task 10: 문서

**Files:**
- Modify `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
- Create `docs/decisions/project_shell_config.md`
- Modify `MEMORY.md`
- Modify `CLAUDE.md`
- Modify `HANDOFF.md`

- [ ] **Step 1: design의 `Status:` 줄과 실측 절을 고친다**

`Status:`를 **SC-M0 완료**로 바꾸고, Task 8의 음성 확인 결과와 Task 9의
게이트 시간을 **"SC-M0이 실행으로 증명한 것"** 절로 더한다. 특히 Task 8
Step 2에서 **어느 검사가 죽었는지**를 그대로 적는다.

- [ ] **Step 2: `docs/decisions/project_shell_config.md`를 만든다**

이 서브프로젝트의 기억. **다시 캐지 말 것**이 여기 들어간다 — 프로브 결과
넷(인사말 · 프롬프트가 안 움직인다 · zsh 마법사가 없다 · `shift-minus`),
`"none"` 토큰이 왜 필요한지, `machine/check.sh:117`이 인사말에 매달려
있다는 것.

- [ ] **Step 3: `MEMORY.md`에 한 줄을 더한다**

- [ ] **Step 4: `CLAUDE.md`의 완료 목록에 Shell Config를 더한다**

**SC-M1·M2가 아직 남아 있으므로 "완료"가 아니라 진행 중으로 적는다.**

- [ ] **Step 5: `HANDOFF.md`를 새로 쓴다**

맨 위가 SC-M0이고 그 아래가 UT-M3이다.

- [ ] **Step 6: 커밋**

```bash
git add docs MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Write down what the guest said before we forget it"
```

---

## 이 milestone이 게이트로 **못 보는 것** — 알고 둔다

| 못 보는 것 | 왜 |
|---|---|
| rc 파일이 **실제로 읽히는가** | 파일이 아직 없다. SC-M1이 `config/check.sh` 2차 부팅으로 본다 |
| `shell_config=off`가 rc를 **막는가** | 같은 이유. SC-M1의 3차 부팅이 부정 검사로 본다 |
| 링크가 가리키는 **대상**이 맞는가 | `tools/check.sh`에는 디스크가 없어 `/config`가 빈 디렉터리다. 링크의 **존재**까지만 본다 |
| 콘솔 셸의 argv | 열한 체인 전부가 `-serial file:`(쓰기 전용)이라 그쪽에 타이핑을 못 한다. **다만 `ps ax`가 그 프로세스를 화면에서 보여 준다** — Task 6의 부정 검사가 그 줄도 함께 본다 |
| 인사말이 화면에 없다 | **어느 체인도 이것을 판정으로 안 갖는다.** Task 9 Step 3이 사람이 한 번 보는 자리이고, 그것이 이 milestone에서 이 사실에 대한 전부다 |
