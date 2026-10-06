# TARS Config Tool — Design

Date: 2026-10-06
Status: TC-M0이 끝났다(2026-10-07, plan `docs/plans/2026-10-06-tars-config-tool-tc-m0.md`의 실측 절이 값이다 — 루트 게이트 21체인
2/2 두 번). 사용자가 M1 · M2를 승인했다(2026-10-06 "끝까지 진행해줘"). M1 plan은 `-tc-m1.md`, M2는 따로 design을 쓴다.

사용자의 요청(2026-10-06)에서 시작한다.

> tars-config 실행 파일(또는 스크립트)를 만들어서 시스템 전체 세팅을 할 수 있게 구성하는 것에 대해 검토해. 쉘 스크립트가 아니라면
> 어떤 언어로 짜서 넣어야 할지도 고민해.

lead(Fable)가 검토해 답했고 사용자가 이어서 정했다.

> alias 된 tars-config, tars-rc 는 아직 유용한 단계가 아니다. (실제 cat 하는 것과 뭐가 다른지 모르겠음; 필요한 기능이라면 zig 버전의
> tars-config 에 포함시키는게 좋겠다)
> 계획 수립과 스펙 디자인, 구현 태스크는 목적에 맞는 model을 사용하는 서브에이전트를 호출하여 진행하자.

언어는 Zig로 정해졌다. 이 design은 그 Zig 실행 파일이 무엇을 하고, 무엇을 하지 않고, init과 어떻게 한 벌의 파서를 나눠 쓰는지를 정한다.

## 한 줄 요약

게스트에서 `tars-config`를 치면 `/config/tars.conf`가 init이 읽을 모양으로 보이고, `tars-config set net=dhcp`가 그 키의 줄 하나만
바꾼다. 값이 맞는지는 init이 부팅에 쓰는 바로 그 `config.parse`가 정한다 — 이 명령이 받은 값을 init이 거절하는 일이 구조로 없다.

```
TC-M0   tars-config [get KEY | set KEY=VALUE… | reset KEY… | check | list | help]  →  tars.conf 하나를 보고 고친다. 고친 것은 다음 부팅부터
        게이트: config 체인 1차가 보기 · 거절 · set · get · check를 치고, 2차가 3차를 위해 줄을 더하는 것도 이 명령이다
TC-M1   다른 표면의 앞문 — wifi · ssh 키 · 방화벽 포트 · 받아쓰기. 남의 문법은 다시 짓지 않고 "어느 파일에 어떤 한 줄"까지
TC-M2   reload — init이 부팅 없이 tars.conf를 다시 읽는다(init.sock에 동사 하나). 따로 design을 쓴다
```

## 왜 새 서브프로젝트인가

사람이 손대는 설정은 `/config` 아래 열 곳이 넘고 문법이 넷이다. 그중 우리 문법이고 init이 읽는 것은 `tars.conf` 하나다.

| 표면 | 문법 | 누가 읽나 | 지금 고치는 법 |
|---|---|---|---|
| `tars.conf` — 키 열둘 | 우리 `key=value`(`config.zig`) | init, 부팅에 한 번 | 편집기 · `echo >>` · `sd`. 틀린 값은 부팅 로그에서야 안다 |
| `dictation.conf` — 키 여덟 | 우리 `key=value`(같은 규칙, 다른 파서 — `tars-dictate`의 bash) | `tars-dictate`, 실행마다 | 편집기 |
| `chrony.d/*.conf` · `nftables.d/*.nft` · `wpa_supplicant.conf` · `ssh/authorized_keys` · `gitconfig` · `vimrc` · rc 셋 | 남의 문법 | chronyd · nft · wpa_supplicant · sshd · git · vim · 셸 | 편집기. 틀리면 그 도구가 말한다 |
| `services.d/*` · `groq.key` | 실행 파일 · 링크 · 비밀 한 줄 | init · `tars-dictate` | `ln -s` · `printf` |
| `chrony.drift` · `asound.state` · `dictation.jsonl` · `bash_history` · `zsh_history` · `xdg/` · `ssh/ssh_host_ed25519_key` | 기계가 쓴다 | — | 사람이 고칠 것이 아니다 |

`tars.conf`가 이 서브프로젝트의 첫 자리인 이유가 셋이다. init만 읽으므로 틀린 값을 알려 주는 자리가 부팅 로그 한 줄뿐이다. seed가
48줄(2,408바이트)이라 게스트 화면 47줄을 넘어 `cat`이 첫 줄들을 밀어낸다(lessons 이월 숙제). 그리고 지금 그 파일을 "보여 주는" 것이
seed rc의 별칭 `alias tars-config='cat /config/tars.conf'`인데, 사용자가 그것이 `cat`과 다르지 않다고 했다.

## 모델

`set` 한 번이 지나는 길이다.

```
tars-config set net=dhcp ntp=010.0.2.2
  1. /proc/mounts에 /config가 있나            없으면 거절(exit 2) — 디스크 없는 부팅의 /config는 RAM이고 init은 거기서 안 읽는다
  2. 쌍마다 config.parse("net=dhcp")          parse가 한 말을 configLog로 듣는다. 말이 있으면 거절(exit 1), 아무것도 안 쓴다
     timezone이면 zoneinfo의 TZif도 본다       main.zig의 resolveTimezone이 부팅에 볼 것을 미리
  3. 값을 정규형으로                           010.0.2.2 → 10.0.2.2 (Ntp.arg). 순서 · 공백도 init의 글자로
  4. 파일을 읽는다. 없으면 init의 seed를 짓는다  config.save를 임시 파일에
  5. 쌍마다 그 키의 마지막 줄 하나를 바꾼다       없으면 끝에 더한다. 주석 · 모르는 키 · 앞선 줄은 바이트 하나 안 바뀐다
  6. 4096바이트를 넘으면 거절                  init이 그 뒤를 안 읽는다
  7. /config/.tars.conf.new에 쓰고 rename      쓰다 끊겨도 init이 읽는 파일은 옛것이거나 새것이다
  8. "net: off -> dhcp"와 "reboot to apply"   init은 이 파일을 부팅에만 읽는다
```

인자 없이 치면(`show`) 같은 파서로 읽은 열두 키를 `key=value` 줄로 찍는다. 파일이 정하지 않은 키는 앞에 `#`가 붙는다. QEMU 사본에서
seed 그대로의 디스크를 찍은 것이다.

```
# /config/tars.conf on /dev/vda, as init reads it at boot
# a line starting with # is a default; the file does not set it
shell=fish
keyboard=apple
hangul_layout=shin_pcs
latin_layout=qwerty
hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap
shell_config=on
net=off
ntp=off
timezone=UTC
firewall=off
esc_latin=on
clipboard=shared
# change: tars-config set KEY=VALUE, then reboot (kill -INT 1)
```

## 결정

### 결정 1 — 이름 하나, 동사 여섯

`tars-config` 하나가 인자 없음(보기) · `get` · `set` · `reset` · `check` · `list` · `help`를 받는다. `tars-service`(동사 넷)와 같은 모양이다.
`list`는 수정 1로 더했다(아래 덧붙임).

| 동사 | 하는 일 | 종료 코드 |
|---|---|---|
| (없음) | 열두 키를 init이 읽을 모양으로. 기본값은 `#`. 설정 디스크 · cmdline의 `tars.noconfig` · init이 불평할 줄의 수를 주석으로 | 0 · 2 |
| `get KEY` | 그 키의 값 한 줄(파일이 안 정하면 기본값). 스크립트가 쓴다 | 0 · 2 · 64 |
| `set KEY=VALUE…` | 위 "모델"의 여덟 단계. 쌍 열여섯까지, 하나라도 거절이면 아무것도 안 쓴다 | 0 · 1 · 2 · 64 |
| `reset KEY…` | `set KEY=<기본값>`과 같다. 줄을 지우지 않고 기본값을 적는다 — seed가 열두 키를 다 적어 두는 모양을 지킨다 | 0 · 1 · 2 · 64 |
| `check` | init이 불평할 줄(줄 번호와 init의 말) · 4096 넘음 · 없는 zoneinfo · rc의 옛 별칭을 문제로, 같은 키가 여러 줄인 것을 알림으로 | 0 · 1 · 2 |
| `list` | 열두 키를 `key=기본값`과 받는 값으로 한 줄씩. 파일도 디스크도 안 본다 — 무엇을 적을 수 있는지만 | 0 · 64 |
| `help` | 쓰는 법 + `list`의 표(같은 함수 `keyTable`) | 0 |

종료 코드는 0 성공 · 1 거절(값 · 문제) · 2 설정 디스크가 없거나 파일을 못 읽고 못 씀 · 64 쓰는 법이 틀림이다.

> 수정 1(2026-10-06, 구현과 루트 게이트 1회차 뒤) — `list`. 사용자의 말: "tars-config need a available list command. 어떤 설정 정보를
> 쓸 수 있는지 알아야 세팅을 하거나 언세팅을 할 수 있지 않을까?" 그 표는 이미 `help`의 뒤쪽에 있었다. `list`는 그 표만 찍고, 두 동사가
> 같은 함수(`config_cli.keyTable`)를 부른다. 왼쪽 칸 `key=기본값`이 그대로 `set`에 줄 수 있는 모양이고 `reset`이 적는 값이다. 지금 값은
> `list`가 아니라 인자 없는 `tars-config`가 보인다 — 둘을 한 화면에 섞으면 "기본값"과 "지금 값"을 못 가른다.
>
> "언세팅"은 `reset`이다. 줄을 지우지 않고 그 키의 줄에 기본값을 적는다(이 표의 `reset` 행 · 전제 정정 7). `unset`을 동의어로 받지
> 않는다 — 그 낱말은 "줄을 지운다"로 읽히고, 받으면 같은 일에 이름이 둘이 되며 출력이 늘 "기본값을 적었다"고 변명해야 한다. 대신
> `tars-config unset …`을 친 사람에게 한 줄로 길을 알려 준다(`tars-config: there is no unset; reset KEY writes the default value into
> that key's line (the line stays)`, 그리고 쓰는 법, exit 64). 줄을 정말 지우는 동사는 만들지 않는다 — seed가 열두 키를 다 적어 두는
> 모양이 사람이 "무엇을 바꿀 수 있나"를 파일에서 읽는 자리이고, 지운 키는 다음 기본값 변경을 따라가는데 그 차이를 사람이 볼 길이 없다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) 이름 하나 · 동사 | 고른 것 |
| (b) 표면마다 이름(`tars-net` · `tars-wifi` …) | 표면이 열이 넘는다. `PATH`의 이름은 사람이 외우는 것이고 지금 `tars-` 이름이 넷(`tars-install` · `tars-service` · `tars-dictate` · 이것)이다 |
| (c) 대화형 화면(TUI) | 게이트가 못 친다(fzf · htop과 같은 자리). 그리고 init이 부팅에만 읽는 파일 하나에 화면은 크다 |
| (d) `tars-config edit` — `$EDITOR`로 열고 닫을 때 `check` | 편집기는 이미 있다(`vim /config/tars.conf`). 닫을 때의 검사는 `check`를 따로 치는 것과 같다 |

### 결정 2 — Zig, `init/` 아래의 셋째 실행 파일, 순수한 쪽과 시스템 콜 쪽을 가른다

언어는 사용자가 정했다. 자리는 `tars-install` · `tars-service`와 같다 — `init/build.zig`의 `addExecutable`, x86_64-musl 정적,
ReleaseSafe, `single_threaded`, libc 없음. `make_initrd.sh`가 `/usr/bin/tars-config`로 싣는다.

| 파일 | 무엇 | 검사 |
|---|---|---|
| `init/src/config_cli.zig` | root. 파일 · `/proc/mounts` · zoneinfo · rc를 읽고 쓰는 것, 동사, 출력 | config 체인 |
| `init/src/config_edit.zig` | 시스템 콜이 없는 쪽 — 키 목록 · 값의 글자 · 줄 가르기 · 줄 바꾸기 · 듣기 · 마운트 표 · 옛 별칭 | `config_edit_test`(호스트) |
| `init/src/config.zig` | init과 함께 쓴다. 바뀌는 것은 로그가 가는 자리(결정 3)와 seed의 별칭 둘(결정 6)과 `MAX_FILE`의 `pub` | config_test · 모든 체인 |

`service_cli.zig`(시스템 콜) ↔ `control.zig`(글자)를 가른 선과 같다. 크기는 3,414,368바이트, gzip -9로 962,335바이트이고 initrd가
97,997,614바이트가 됐다(사본, 실측 4).

| 후보 | 왜 아닌가 |
|---|---|
| (a) Zig, `config.zig`를 import | 고른 것. 파서 · 화이트리스트 · IPv4 · 시간대 모양 · 정규형이 init과 한 벌이다 |
| (b) bash 스크립트(`tars-dictate`처럼) | 값 검사를 bash로 두 벌 짜야 한다 — enum 열 개 · `hangul_toggle` 목록 · IPv4(`010`을 10으로) · 시간대 모양. 둘이 갈라지는 날 이 명령은 init이 버릴 값을 써 준다. 그리고 사용자가 정했다 |
| (c) terminal 안의 기능 | 셸 명령이어야 ssh 세션 · 스크립트에서 쓴다 |

### 결정 3 — 값을 받을지는 init의 `parse`에 묻는다: 로그가 root로 간다

`config.parse`는 실패를 돌려주지 않는다. 틀린 값이면 로그 한 줄(`tars-init: unknown shell 'fsh', falling back to fish`)을 찍고 그
키를 기본값(또는 앞 줄의 값)에 둔다 — 부팅이 설정 하나로 막히지 않게 하는 CP의 장치다. 그래서 "이 값을 init이 받는가"의 답은 그
로그 한 줄이 나왔는가다.

`config.zig`의 `std.debug.print("tars-init: …\n", …)` 스물넷을 `log("…", …)` 하나로 모은다. `log`는 root가 `configLog`를 선언했으면
그리로 보내고, 아니면 전과 같이 `tars-init: ` 접두사와 개행을 붙여 찍는다.

```zig
fn log(comptime fmt: []const u8, args: anytype) void {
    const root = @import("root");
    if (@hasDecl(root, "configLog")) return root.configLog(fmt, args);
    std.debug.print("tars-init: " ++ fmt ++ "\n", args);
}
```

`config_cli.zig`와 `config_edit_test.zig`가 `pub const configLog = config_edit.configLog;`를 둔다. `config_edit.judge(key, value)`가
`"key=value"`를 `parse`에 넣고 들은 말이 있으면 그 말을 이유로 거절한다. 사용자에게는 이렇게 보인다.

```
tars-config: shell=fsh: init would say "unknown shell 'fsh', falling back to fish"
tars-config: shell takes fish | bash | zsh
tars-config: nothing was written
```

init은 그대로다. root가 `main.zig`라 `@hasDecl`이 컴파일 타임에 거짓이고, 찍는 바이트가 같다 — config_test가 찍는 `tars-init:` 줄
쉰여덟이 HEAD와 새것에서 정렬해 같았다(실측 3). 바이너리는 3,840,056 → 3,843,696바이트(+3,640)로 같지 않다. 지운 seed 줄과
옮겨진 줄 번호가 ReleaseSafe의 디버그 정보를 바꾼 것으로 보지만 그 안을 가르지는 않았다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) 로그를 root로 — `@import("root")` · `@hasDecl` | 고른 것. `std`가 `std_options`를 root에서 찾는 수법과 같고, init에는 가로채는 갈래가 아예 안 들어간다 |
| (b) 키마다 검사하는 표를 이 명령에 | 두 벌이다. 키를 하나 더한 사람이 이 표를 잊으면 그날부터 어긋난다 |
| (c) `parse`가 결과(어느 줄이 왜 버려졌나)를 돌려주게 리팩터 | init의 파서 모양이 바뀌고 로그 스물넷의 자리가 옮겨 간다. 게이트가 그 글자를 grep한다. 이득은 (a)와 같다 |
| (d) 런타임 변수 `log_sink` | init의 바이너리에 포맷하는 갈래가 로그 자리마다 들어간다. (a)는 컴파일 타임에 고른다 |
| (e) 표준 에러를 파이프로 잡아 `tars-init:`을 바꿔 찍기 | 우회다. 그리고 "말을 했는가"를 바이트 수로 판정하게 된다 |

`parse`가 줄 사이에 상태를 안 갖기 때문에(마지막 줄이 이긴다는 것뿐) 한 줄씩 들어도 init이 파일째 읽을 때와 같은 말을 한다. `check`는
그래서 줄마다 `parse`에 넣어 줄 번호를 붙인다. `config_edit_test`가 줄 열일곱을 두 길(줄 가르기 + `judge` · `parse`)에 함께 넣어
같은 답인지 본다.

`parse`가 안 보고 init이 다른 자리에서 버리는 값이 하나 있다 — `timezone`. `parse`는 모양만 보고, 그 이름의 zoneinfo 파일이 정말
`TZif`인지는 `main.zig`의 `resolveTimezone`이 부팅에 본다. `set`과 `check`가 같은 판정(`config.zoneinfoPath` · `config.looksLikeTzif`)을
게스트에서 한다(`config_cli.bootRefuses`). `shell`도 init이 `access`로 한 번 더 보지만 셋 다 initrd에 늘 있어서 안 본다.

### 결정 4 — 키 목록과 값의 글자는 `Config`의 필드에서 컴파일 타임에 나온다

`config_edit.KEYS`는 `@typeInfo(Config).@"struct".fields`의 이름이다. 값을 글자로 바꾸는 것은 필드 타입마다 config.zig에 이미 있는
것(`@tagName` · `Toggles.arg` · `Ntp.arg` · `Timezone.slice`)을 고를 뿐이고, 모르는 타입의 필드가 생기면 `fieldText`가
`@compileError`를 낸다. `help`의 "받는 값"도 enum이면 이름을 컴파일 타임에 모은다.

그래서 키를 하나 더하는 사람이 할 일이 이 명령에 대해서는 없다. 필드 이름과 `parse`의 키 이름이 같다는 가정 하나는 컴파일러가
못 본다 — `config_edit_test`가 모든 필드를 기본값 · 다른 값으로 `parse`에 넣어 "모르는 키"가 안 나오는지, 되읽은 값이 같은지 본다.
다른 값의 표 `OTHER`가 키 수와 다르면 그 검사가 먼저 멈춘다.

### 결정 5 — `set`은 이기는 줄 하나만 바꾼다

`save()`는 파일 전체를 고정 주석과 함께 다시 쓴다. 그것으로 `set`을 하면 사람이 적어 둔 주석과 모르는 줄이 사라진다. `set`은
`config_edit.setLine`으로 그 키의 마지막 줄 — `parse`에서 이기는 줄 — 하나만 `key=value`로 바꾼다.

- 그 키의 줄이 없으면 끝에 더한다. 끝에 개행이 없던 파일이면 개행을 먼저.
- 앞선 같은 키의 줄은 그대로 둔다. 지는 줄이라 뜻이 없지만 사람이 쓴 것이다. `check`가 "shell is on 3 lines; the last one wins"로 알린다.
- 정규형으로 쓴다 — `ntp=010.0.2.2`는 `ntp=10.0.2.2`, `hangul_toggle= lctrl_tap , shift_space`는 `shift_space,lctrl_tap`, 빈 값은 `none`.
- 파일이 없으면(설정 디스크는 붙었는데 사람이 지웠다) `config.save`로 init의 seed를 임시 파일에 먼저 짓고 거기에 고친다. 한 줄짜리
  파일을 만들면 그 디스크는 seed의 주석을 영영 못 받는다 — init은 파일이 있으면 seed하지 않는다.
- 결과가 `config.MAX_FILE`(4096)을 넘으면 쓰지 않는다. init의 `load`가 그 뒤를 읽지 않으므로 쓰는 순간 사람의 줄이 조용히 무시된다.
- `/config/.tars.conf.new`에 쓰고 `rename`한다. `/config`는 `MS_SYNCHRONOUS`라 둘 다 돌아온 때 디스크에 있다.
- 쌍이 여럿이면 전부 먼저 듣고(결정 3), 하나라도 거절이면 아무것도 안 쓴다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) 이기는 줄 하나 | 고른 것 |
| (b) `save()`로 통째로 | 사람의 주석 · 모르는 키(다음 판의 키일 수도 있다)가 사라진다 |
| (c) 같은 키의 줄을 전부 지우고 하나를 더한다 | 사람이 쓴 줄을 지운다. 그리고 설정 체인의 2 · 3 · 8차가 "줄을 더해 마지막이 이긴다"는 모양에 기대고 있다 |
| (d) 첫 줄을 바꾼다 | 뒤에 같은 키가 있으면 바꾼 것이 진다 |

`config_edit_test`가 진짜 seed(`config.save`가 /tmp에 쓴 2,408바이트)에서 열두 키를 하나씩 바꿔 "한 줄만 다르다 · parse가 새 값을
읽는다 · 나머지 열하나는 기본값 그대로다"를 본다.

### 결정 6 — 별칭 둘은 seed에서 지우고, 옛 디스크의 줄은 알리기만 한다

사용자가 둘 다 지우라고 했다. seed 셋(`rcSeed()`의 fish · bash · zsh)에서 `alias tars-config=…` · `alias tars-rc=…` 두 줄씩을 지운다.
`config_test`의 `ALLOWED_ALIAS_NAMES`에서 두 이름을 빼서 같은 이름의 별칭이 seed에 다시 못 들어온다 — 그 별칭은 대화형 셸에서
`/usr/bin/tars-config`를 가린다. `config_edit_test`가 지금의 seed 셋에 그 줄이 없는 것을 한 번 더 본다.

남는 것은 옛 디스크다. seed는 "없으면 만든다"라서 TC 전에 만든 설정 디스크의 rc에는 그 줄이 그대로 있고, 그 셸에서 `tars-config set
net=dhcp`는 `cat /config/tars.conf set net=dhcp`가 된다(`cat: set: No such file or directory`가 나오고 파일이 찍힌다).

| 후보 | 왜 아닌가 |
|---|---|
| (a) 이 명령은 rc를 안 고친다. `check`가 그 줄을 문제로 알리고, 실행 안내와 HANDOFF가 한 줄짜리 처방을 적는다 | 고른 것 |
| (b) init이 부팅에 정확히 우리가 쓴 그 바이트의 줄만 지운다 | SC design 결정 7 — 깔린 rc는 그때부터 사람의 것이다. 이 저장소가 사람의 파일을 고친 적이 없다 |
| (c) `tars-config`가 rc를 고친다(`fix-rc`) | 같은 이유. 그리고 그 셸에서는 별칭이 이 명령을 가려서 사람이 칠 수가 없다 — `command tars-config`를 알아야 한다 |
| (d) 이름을 바꾼다 | 사용자가 그 이름을 정했다 |

처방은 셋 중 하나다. 어느 것이든 `unalias tars-config` 또는 새 셸부터 듣는다.

```sh
sd 'alias tars-(config|rc)=.*' '' /config/fish.config /config/bashrc /config/zshrc     # 그 두 줄을 빈 줄로
command tars-config check                                                                 # 별칭을 건너뛰고 확인
rm /config/zshrc && kill -INT 1                                                           # 또는 새 seed를 받는다(그 파일에 더한 줄도 사라진다)
```

`tars-rc` 별칭은 가리는 명령이 없어서 남아도 해가 없다. `check`는 `tars-config` 하나만 문제로 센다.

SC-M1의 config 체인 1차가 그 별칭으로 "fish가 seed rc를 읽었다"를 판정했다. 별칭이 실행 파일이 되면 그 판정이 조용히 거짓이 된다 —
rc를 안 읽어도 `tars-config`가 돈다. 그 판정은 바로 뒤의 `ls -l /config`(seed의 `alias ls='eza'`가 있어야 `.rw-`가 나온다)가 이어받는다.

### 결정 7 — 고친 것은 다음 부팅부터, `set`이 매번 말한다

init은 부팅에 `tars.conf`를 한 번 읽고 terminal은 argv로 값을 받는다. 다시 읽는 길이 없다. `set` · `reset`의 마지막 줄이 늘
`init reads /config/tars.conf only at boot; reboot to apply (kill -INT 1)`이다. `kill -INT 1`이 재부팅이다(`power.zig`의 SIGINT →
restart). 게스트에는 `reboot` 도구가 없다.

`show`는 "지금 이 부팅이 쓰는 값"이 아니라 "다음 부팅이 읽을 값"이다. 둘이 다를 때(고치고 아직 재부팅 전) 그것을 알리는 길이
없다 — init이 읽은 값을 어디에도 남기지 않기 때문이다. 시리얼의 `tars-init: config shell=…` 줄이 있지만 게스트의 파일이 아니다. M2의
`reload`가 같은 자리(init이 읽은 값을 묻는 동사)를 다룬다.

### 결정 8 — 보기의 모양: 그대로 `tars.conf`로 쓸 수 있는 줄, 기본값은 `#`

`show`의 출력은 주석 줄과 `key=value` 줄뿐이다. 파일이 정하지 않은 키는 `#key=value`다 — sshd_config가 기본값을 주석으로 보여 주는
관례다. 그래서 출력을 그대로 `tars.conf`로 써도 init이 같은 값을 읽는다.

"파일이 정한다"는 그 키의 줄이 있다는 것이 아니다. 줄이 있어도 init이 그 값을 버리면 기본값(또는 앞 줄의 값)이고, 그때 `#`를 안
붙이면 화면이 거짓말을 한다. `config_edit.setByFile`이 그 키의 줄마다 `judge`로 들어 하나라도 받히면 참이다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) `key=value`, 기본값은 `#` | 고른 것. 게이트도 이 모양에 기댄다 — 1차의 `\| shell_config=on`은 파일이 그 줄을 가질 때만 행 머리에 생긴다 |
| (b) 파일 그대로(`cat`) | 지운 별칭이 하던 일이다. 48줄이라 화면을 넘고, 기본값과 init이 버리는 줄을 못 가른다 |
| (c) 열 맞춘 표(`shell  fish  (default)`) | 복사해 쓸 수 없다. 그리고 `get`의 한 줄과 모양이 갈린다 |

`set`의 답은 `net: off -> dhcp`처럼 `key:`로 시작한다. `key=`로 시작하면 체인이 "파일을 되읽은 줄"과 "명령의 답"을 못 가른다.

### 결정 9 — 게이트는 새 체인 없이 config 체인과 호스트 검사

config 체인이 이미 설정 디스크 · 게스트 타이핑 · "1차가 쓴 것을 2차가 읽는다"를 갖고 있다. 새 체인을 만들면 같은 것을 부팅 하나 더
(30초 남짓 × 2회)로 다시 짓는다.

| 자리 | 무엇 | 사본 |
|---|---|---|
| config 1차(fish) | `tars-config` → `\| shell_config=on`(seed가 그 줄을 정한다), `set shell=fsh` → `tars-config: shell=fsh: init would say "unknown shell 'fsh', …"` · `nothing was written`, `set clipboard=pane` → `clipboard: shared -> pane`, `echo tc$(tars-config get clipboard)` → `tcpane`, `check` → `init reads every line without a complaint`, (수정 1) `list` → 열두 줄 `key=기본값 받는 값` | 초록 |
| config 2차(zsh) | `echo shell_config=off >> /config/tars.conf`가 `tars-config set shell_config=off`가 됐다. 파일은 1차가 덮어쓴 `shell=zsh` 한 줄이라 set이 끝에 더하고, 결과가 echo의 것과 바이트까지 같다 — 3 ~ 9차가 보는 것이 안 바뀐다 | 초록 |
| config 3차 | 그대로의 `tars-init: config shell=zsh.*shell_config=off`가 "이 명령이 쓴 값을 다음 부팅이 읽었다"는 판정이 된다 | 초록 |
| `zig build test` | `config_edit_test` 다섯 묶음(키 열둘 · `judge` · 줄 가르기 · 진짜 seed에서 `setLine` · 마운트 표와 옛 별칭), `config_test`의 별칭 허용 목록 | 초록 |
| tools 체인 검사 1 | initrd에 `usr/bin/tars-config`(literal `WANT`). `all 92 tools`는 그대로 — 그 수는 `guest_tools.sh`의 배열이다 | 초록 |

1차가 바꾼 `clipboard=pane`은 2차로 안 넘어간다 — 그 부팅의 `EDIT_KEYS`가 파일을 `shell=zsh` 한 줄로 덮어쓴다. 1차의 판정은 "쓴다 ·
읽는다"이고 "다음 부팅이 읽는다"는 2 · 3차의 몫이다. 줄 하나만 바꿨는지(더하지 않았는지)는 체인이 아니라 호스트 검사가 본다.

게이트가 못 보는 것 둘 — `timezone`의 zoneinfo 거절(`bootRefuses`)과 `reset`. 둘 다 시스템 콜 몇 줄이고 다른 동사와 같은 길이다.
1차에 줄 하나씩이면 덮을 수 있지만 타이핑이 글자당 0.3초라 넣지 않았다.

### 결정 10 — 남의 문법은 다시 짓지 않는다(M1의 원칙)

chrony · nft · wpa_supplicant · sshd의 문법을 이 명령이 파싱하거나 검증하지 않는다. 그 표면에서 이 명령은 "어느 파일에 어떤 모양으로
한 줄을 적는가"를 알고 그 한 줄을 써 주거나 파일의 자리를 알려 주는 데서 멈춘다. 그 줄이 맞는지는 그 도구가 부팅에 말한다
(`nft -f`가 실패하면 init이 기본 규칙만 올리는 것처럼 — FW 결정 5).

### 결정 11 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가

AU 결정 6 · VD 결정 12와 같다. M0의 구현자는 Sonnet을 권한다(plan "누가 무엇을 하나"에 근거). M1 · M2의 plan은 그때 Opus가 쓴다.

## lead의 전제를 바로잡은 것

1. 설정 표면의 목록에 기계가 쓰는 것이 더 있다 — `bash_history` · `zsh_history` · `xdg/`(zoxide DB · fish 히스토리) ·
   `ssh/ssh_host_ed25519_key`(sshd 템플릿이 처음 한 번 짓는다). 사람의 것에는 `groq.key`가 있다. 키 열둘 · `save()`의 seed는 맞다.
2. 별칭을 지우면 함께 바뀌는 것이 하나 더 있었다 — config 체인 1차가 그 별칭으로 "fish가 rc를 읽었다"를 판정했고, 실행 파일이
   생기면 그 판정이 소리 없이 거짓이 된다(결정 6 끝 문단). `running-tars.md`에는 그 별칭을 안내하는 줄이 없다(`project_shell_config.md`
   기억에는 역사로 있다). `config_test`에서 바뀌는 것은 `ALLOWED_ALIAS_NAMES` · `expectAliasLinesMatch`의 `alias tars-` 건너뛰기 · 주석
   셋이고, `expectHooksCoverTheTools`는 안 바뀐다.
3. `config.zig`는 별도 exe에서 그대로 컴파일된다(`std.os.linux`만 쓰고 libc가 없다). 로그 접두사는 모양의 문제가 아니었다 — `parse`가
   실패를 돌려주지 않으므로 그 로그가 "init이 이 값을 버린다"를 아는 유일한 길이다. 가로채지 않으면 접두사가 섞이는 것으로 끝나지
   않고 `set`이 틀린 값을 쓴다(plan mutation 1). 결정 3.
4. "없으면 끝에 더한다"는 맞다. 바꿀 줄은 첫 줄이 아니라 마지막 줄이어야 하고(마지막이 이긴다), 파일이 아예 없으면 seed를 먼저 짓고,
   4096바이트 상한이 있다(결정 5). `MS_SYNCHRONOUS`는 맞고, 그 위에 `rename`을 둔다.
5. 그대로다. `reboot`는 게스트에 없고 `kill -INT 1`이다. `reload`는 M2(따로 design)다.
6. 그대로다(결정 10).
7. 범위는 그대로이고 둘을 더했다 — `help`, 그리고 `show`의 모양(결정 8). `reset`은 줄을 지우지 않고 기본값을 적는다. 수정 1이 `list`를
   더했다(결정 1의 덧붙임).
8. 그대로다. 이 명령은 게스트 런타임을 하나도 안 부른다.
9. 새 바이너리는 `all 92 tools`를 안 바꾼다. 그 수는 `guest_tools.sh`의 배열 길이이고 `tars-install`은 `tools/check.sh`의 literal
   `WANT`로 따로 본다. `tars-service`는 그 `WANT`에도 없다 — service 체인이 ssh로 쳐서 볼 뿐이다(이 milestone은 안 고친다).
10. 그대로다.

## 검증

사본(`/tmp/run/tc0/repo/`, HEAD `4ed73a9`)에서 돈 값이다. 자세한 것은 plan 확정 절.

| 무엇 | 왜 | 사본의 결과 |
|---|---|---|
| `zig build test` | `config_edit_test` 새로, `config_test` 별칭 목록 | 초록. `config_edit_test` 다섯 줄과 `PASS` |
| `config` 체인 | M0의 모든 것 | 초록, 246초(terminal을 처음부터 짓는 판) |
| `tools` | initrd의 `/usr/bin`에 하나 | 71초, `all 92 tools` |
| `boot` | limine이 BIOS로 initrd를 읽는다. initrd가 1MB 남짓 커졌다 | 26초 |
| `install` | initrd가 바뀌면 부팅 7의 창이 움직인다(lessons PD-3) | 110초, `init waited 1400ms` |

mutation 다섯은 plan 확정 7.

## Milestone

### TC-M0 — `tars.conf` 하나

결정 1 ~ 9. 고치는 파일 일곱(`init/src/config.zig` · `config_test.zig` · `init/build.zig` · `kernel/make_initrd.sh` · `config/check.sh` ·
`tools/check.sh` · `check.sh`)과 새 파일 셋(`init/src/config_cli.zig` · `config_edit.zig` · `config_edit_test.zig`). plan은
`docs/plans/2026-10-06-tars-config-tool-tc-m0.md`.

### TC-M1 — 다른 표면의 앞문

`/config` 아래 남의 문법 파일에 사람이 처음 적는 한 줄을 이 명령이 써 준다. 후보 — `tars-config wifi <SSID>`(비밀번호를 물어
`wpa_passphrase`의 출력을 `wpa_supplicant.conf`에), `tars-config ssh-key add <공개 키>`(`ssh/authorized_keys`에 한 줄, 디렉터리 0700 ·
파일 0600, sshd 링크가 없으면 걸지 묻는다), `tars-config firewall allow <포트>`(`nftables.d/tars-config.nft`에 `tcp dport N accept` 한 줄 —
이 명령이 쓰는 파일을 사람의 파일과 가른다), `tars-config dictation key`(`groq.key` · 0600)와 `dictation set`(`dictation.conf`. 그 파서가
`tars-dictate`의 bash라 이 명령은 키 이름만 안다). 원칙은 결정 10이다. 정할 것 — 표면마다 "이 명령이 쓰는 파일"과 "사람의 파일"을
가를지, 게이트를 어느 체인에 얹을지(wifi · service · firewall · dictation 체인에 하나씩일 것이다).

### TC-M2 — `reload`

init이 재부팅 없이 `tars.conf`를 다시 읽는다. `init.sock`(CT의 SEQPACKET, 동사 넷)에 동사 하나를 더하는 일이지만, 다시 읽어서 무엇이
바뀌는지는 키마다 다르다 — `net` · `ntp` · `firewall`은 init이 서비스를 띄우고 멈추는 길이 있고(DS), `keyboard` · 자판 · `clipboard`는
terminal의 argv라 terminal을 다시 띄워야 하고, `shell`은 떠 있는 셸을 죽일지의 문제다. 따로 design을 쓴다. "지금 이 부팅이 쓰는 값"을
묻는 동사(결정 7)도 같은 자리다.

## 위험

1. 옛 디스크의 별칭(결정 6). 사용자의 `out/tars-config.img`와 실기의 설정 디스크에는 그 줄이 있다. 그 셸에서는 이 명령이 안 보인다.
   처방이 한 줄이지만 사용자가 알아야 한다 — lead가 알리고 running-tars.md에 적는다.
2. 화면 줄을 넘는 값. `hangul_toggle`의 가장 긴 값이 45글자라 `show`가 155열 화면을 안 넘는다. 사람이 적은 긴 `timezone`(64)도 넘지 않는다.
3. 정규형이 사람의 글자를 바꾼다. `set ntp=010.0.2.2`는 `10.0.2.2`를 쓴다. 의도한 것이다(init이 읽는 값이 그것이다).
4. 같은 파일을 동시에 고치는 둘. 셸 둘이 동시에 `set`하면 나중 `rename`이 이기고 앞의 것이 사라진다. 사람 하나가 쓰는 기계라 잠금을 안 둔다.
5. init이 버린 줄의 "앞 줄 값". `shell=zsh` 뒤에 `shell=fsh`가 있으면 init은 zsh를 쓴다. `show`는 zsh를 `#` 없이 보이고 `check`가 둘째 줄을
   알린다. `set shell=bash`는 마지막 줄(`shell=fsh`)을 바꾼다 — 맞다.
6. `tars-config`의 크기. 3.4MB(gzip 0.96MB)가 initrd에 더해진다. `tars-service` · `tars-install`과 같은 몫이다.

## 비목표

1. `reload` · "지금 쓰는 값" 묻기(M2).
2. 남의 문법 파일(M1, 결정 10).
3. `dictation.conf`를 init의 파서로 읽기. 그 파일의 주인은 `tars-dictate`(bash)다 — 문법이 같아도 키와 판정이 다르다.
4. rc 파일을 고치는 것(결정 6).
5. 대화형 화면 · 편집기 띄우기(결정 1).
6. 잠금 · 동시 편집(위험 4).
7. 값의 주석(`net=dhcp  # 집`). init의 `parse`가 줄 끝 주석을 모른다 — 값이 `dhcp  # 집`이 되어 버려진다. 이 명령도 그대로 따른다.
8. seed의 `ntp:` 주석이 TD 전의 설명으로 남은 것(lessons 이월 숙제). seed 글자를 고치는 일이라 따로 한다.

## 착수 전에 실측한 것

저장소 사본(`/tmp/run/tc0/repo/`, HEAD `4ed73a9`)과 이미지 `tars-devcontainer`(zig 0.16.0, aarch64)로 쟀다. 측정 파일은
`/tmp/run/tc0/meas/`(체인 · 시리얼 · regression)와 `/tmp/run/tc0/mut/`(mutation)에 있다.

1. `config.zig`의 `std.debug.print("tars-init: …\n", …)`는 스물넷이고 전부 같은 모양이다. perl 한 줄(plan Task 1)이 스물넷을 다 바꾸고 남는
   `std.debug.print`가 0이다.
2. `config.zig`를 import한 별도 exe(`config_cli.zig` root)가 고칠 것 없이 컴파일됐다. `@import("root")` · `@hasDecl` · `std.Io.Writer.fixed` ·
   `linux.rename`이 0.16에서 그대로 된다.
3. init의 로그. HEAD와 새 것으로 각각 `zig build test`를 돌려 `tars-init:` 줄을 정렬해 비교했다 — 쉰여덟 줄이 같다. init 바이너리는
   3,840,056 → 3,843,696바이트다(같지 않다, 결정 3).
4. 크기. `tars-config` 3,414,368바이트(gzip -9 962,335), initrd 97,997,614 ~ 97,997,632바이트.
5. seed `tars.conf`는 2,408바이트 · 48줄이다(`config.save`가 /tmp에 쓴 것).
6. 화면. 1차 부팅의 화면에서 `show`가 15줄이다. 거절의 둘째 줄 `shell takes fish | bash | zsh`가 화면 줄 이음(" | ")과 섞인다 — 그래서
   되읽기의 판정 글자를 `echo tc$(…)`로 짓는다(plan 확정 5).
7. main 작업 트리의 `kernel/build`가 반쯤 지어진 채다(19:13, `bzImage`도 스탬프도 없고 `net/.socket.o.cmd`가 `wildcard include/config/`에서
   잘렸다). 그것을 rsync한 사본에서 `kernel/build.sh`가 `unterminated call to function 'wildcard'`로 죽었다. 사본은 입력 sha256이 같은
   `/tmp/run/vd2/repo/kernel/build`로 바꿔 진행했다. lead에게 알렸다.
8. `install` 부팅 7의 `init waited`가 1,400ms다(VD-M0 때 1,700ms). initrd가 1MB 커져 창이 움직인 것이고 lessons PD-3의 하한(500ms) 위다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`. M1 · M2를 안 하고 닫으면 그 사실을 한 줄로.
- `CLAUDE.md`의 완료 표에 한 줄. 예: "게스트의 `tars-config`가 `tars.conf`를 init이 읽을 모양으로 보이고 그 키의 줄 하나만 고친다 —
  값은 init의 `parse`가 정한다(로그가 root의 `configLog`로 간다). seed의 별칭 둘을 지웠다. 새 체인 없이 config 체인 1 · 2차가 본다".
- `docs/decisions/project_config_tool.md`와 `MEMORY.md` 한 줄. 담을 것 — 로그 가로채기(결정 3), 이기는 줄 하나(결정 5), 옛 별칭(결정 6).
- `docs/guides/lessons.md`. 핵심 파일 절의 PID 1 쪽에 `config_cli.zig` · `config_edit.zig`, `config.zig` 항목에 `log`. 이월 숙제의 "seed 48줄이
  화면을 넘는다 — config 1차의 25번째 줄"은 지운다(1차가 `cat` 대신 `tars-config`를 보고 그 출력이 15줄이다).
- `docs/guides/running-tars.md`. "네트워크와 시계" 절의 `sd` 세 줄을 `tars-config set net=dhcp ntp=dhcp timezone=Asia/Seoul`로, "seed는 한 번만
  깔린다" 절에 옛 별칭 처방(결정 6), 새 절 "설정 — tars-config".
- `HANDOFF.md`. 사용자에게 알릴 것 — 쓰던 디스크의 rc에는 별칭이 남아 있다(위험 1).

## 관련

- `docs/specs/2026-08-14-tars-config-persistence-design.md` · `docs/decisions/project_config_persistence.md` — `tars.conf`와 "부팅이 설정 하나로 막히지 않는다"
- `docs/specs/2026-09-11-tars-shell-config-design.md` · `docs/decisions/project_shell_config.md` — seed rc와 별칭 `tars-config`의 역사, 사람의 파일(SC 결정 7)
- `docs/specs/2026-09-27-tars-service-control-design.md` — `tars-service` · `init.sock`(M2의 자리)
- `docs/decisions/feedback_network_default_stays_off.md` — `net` · `ntp`의 기본값은 그대로다. 이 명령은 켜는 길을 짧게 할 뿐이다
- `docs/decisions/feedback_scripting_runtimes.md` — 게스트에 런타임을 안 들인다
