# EL-M0 — Esc가 조합을 확정하고 한글을 끈다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-escape-latin-design.md`
Status: 끝났다(2026-10-05). 실측은 맨 아래 "EL-M0이 실측한 것" 절에 있다. 이것으로 EL이 닫혔다.

## 누가 무엇을 하나

Task 0~6은 구현 서브에이전트(Sonnet)가 main 작업 트리에서 직접 편집하고 돌린다. Task 7(루트 게이트 2회 · 실측 절 ·
commit · 닫기)은 lead가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령
출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/el0/repo/`)에 먼저 넣어 컴파일 · 호스트 검사 · 체인 · regression ·
mutation까지 돌렸고, 아래의 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/el0/render.py`).
기준은 HEAD `5acc735`의 파일(`/tmp/run/el0/base/`)이고 편집 뒤의 파일은 `/tmp/run/el0/new/`다. 구현자는 코드를 새로
짓지 않는다. 편집은 Edit 도구에 글자 그대로 넣고, 각 Task 끝에서 `new/`와 `diff`해 같은지 본다. 다르면 편집이 빗나간
것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다.

편집은 한 파일 안에서 E1부터 차례로 넣는다. 앞 편집이 들어간 뒤에야 뒤 편집의 `old_string`이 한 번만 나오는 자리가
있다(`hunks.py`가 그 순서로 뽑았다).

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/input.zig` | 편집 열 — `Toggles.esc_latin` · `ToggleKey` · `parseToggles` · `togglesArg` · `Keys.redraw` 주석 · `State.toggles` 기본값 · `hangulLayer`의 Esc 갈래 · `readKeys`의 앞뒤 비교 | +57 −4 |
| `terminal/src/input_test.zig` | 검사 69~74 | +180 |
| `terminal/src/main.zig` | argv가 없을 때의 기본 목록 | +4 −2 |
| `init/src/config.zig` | 편집 아홉 — `EscLatin` · `TOGGLE_ARG_MAX` 주석과 `longest` · `Toggles.esc_latin` · `arg` · `Config.esc_latin` · `terminalToggles` · `parse` 갈래 · seed 세 줄 | +59 −3 |
| `init/src/config_test.zig` | `expect`의 비교와 출력 · EL-M0 절 | +54 −2 |
| `init/src/main.zig` | argv에 `terminalToggles` · 로그 줄 끝에 `esc_latin=` | +10 −3 |
| `hangul/make_disk.sh` | 주석 한 문단(디스크 내용은 그대로) | +5 |
| `hangul/check.sh` | 머리 주석 · 헬퍼 넷 · 검사 0 · 검사 21~24 | +201 −3 |

`check.sh`(루트) · `hangul/make_disk.sh`의 heredoc · `kernel/` · 다른 체인은 안 고친다. 새 체인이 없으므로 `CHAINS`
배열도 그대로다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · HI design · `HANDOFF.md`는
구현자가 안 고친다. lead가 Task 7에서 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/el0/impl/` 아래에 둔다.
`/tmp/run/el0/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(PD-M1 plan
확정 11). 컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으면 모든 `docker run`을 아래로
감싼다. 명령이 실패해도 lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

## 이 milestone이 끝나면

- 한글을 치다가 수정키 없는 Esc를 누르면 조합 중이던 음절이 확정되고, Esc는 평소처럼 PTY에 가고, 한/영이 영문이
  된다. 조합 중이었으면 음절 세 바이트와 ESC가 한 write로 간다(design 결정 2).
- copy mode와 검색 프롬프트의 Esc, Shift · Ctrl · Alt · Cmd를 누른 Esc, 한글이 꺼진 상태의 Esc는 EL 전과 같다.
- 조합 중이 아닌 Esc로 한글이 꺼져도 상태 줄 첫 칸이 그 프레임에 `EN`이 된다 — `readKeys`가 `hangul_on`의 앞뒤를
  비교해 `redraw`를 켠다(design 결정 3).
- `tars.conf`에 새 키 `esc_latin=on|off`가 생긴다. 기본값은 `on`이고, 그 줄이 없는 옛 설정 파일에서도 켜진다. 새로
  만드는 seed에는 `hangul_toggle=` 바로 뒤에 주석 두 줄과 `esc_latin=on`이 들어간다(design 결정 1).
- terminal은 argv 여덟째의 목록에서 `esc_latin`을 읽는다. init이 `hangul_toggle`의 목록 끝에 붙여 넘긴다
  (`Config.terminalToggles`).
- hangul 체인에 검사 21~24가 더해지고 검사 0이 두 줄을 더 본다. 부팅 수와 체인 수는 그대로다. 호스트 검사는
  `input_test`의 OK 줄이 넷 늘고 `config_test`에 EL-M0 절이 생긴다.

로그 줄(정본 — 코드와 `hangul/check.sh`가 이 글자를 쓴다). 새 줄은 없고 두 줄의 끝이 바뀐다.

```
tars-init: config shell=fish keyboard=apple hangul=sebeol_3p3 latin=qwerty toggles=shift_space,capslock_tap,lctrl_tap shell_config=on net=off ntp=off timezone=UTC firewall=off esc_latin=on
terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=shift_space,capslock_tap,lctrl_tap,esc_latin
```

init의 `toggles=`는 파일의 `hangul_toggle` 줄 그대로이고, terminal의 `toggles=`는 init이 argv로 넘긴 합친 목록이다.
조합 중의 Esc는 `terminal: key> 4 byte(s) decckm=…` 한 줄과 `terminal: hangul> on=false preedit=(none)` 한 줄을, 조합
없는 Esc는 `key> 1 byte(s)` 한 줄과 같은 `hangul>` 한 줄을 만든다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 코드를 읽어 정했고, 저장소 사본(`/tmp/run/el0/repo/`)에서 쟀다. 저장소의 작업 트리는
design 파일과 이 plan 말고는 한 글자도 안 바뀌었다.

1. normal 모드의 Esc 경로. `hangulLayer`가 한글이 켜져 있으면 `qwerty_keymap[KEY_ESC]`(0x1b)를 `nonSyllable` ·
   `lookup`에 물어 둘 다 null을 받고 `commitHangul()` 뒤 null을 돌려준다. 그 뒤 `chord`가 null, `specialKey`에는
   Esc가 없고, `keymap`이 `one(0x1b)`를 낸다. 새 갈래는 이 길의 맨 앞(Ctrl · Alt · Meta 갈래 바로 뒤)에서 확정 · 끄기만
   하고 같은 null을 돌려준다 — 그래서 PTY로 가는 바이트는 EL 전과 같다.

2. copy · find 모드의 Esc는 새 갈래에 안 닿는다. `handleKey`에서 find 분기(Esc를 `hangulLayer`보다 먼저 가로챈다,
   SH design 결정 3)와 copy 분기(`.copy = .exit`)가 한글 층보다 앞이다. `input_test` 검사 29가 HI 때부터 "copy mode를
   나와도 한글이 켜진 채다"를 보고 있고, 새 검사 73이 find와 copy를 나란히 본다.

3. 설정의 모양(design 결정 1). `save()`가 쓰는 seed에 `hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap`이
   글자 그대로 있다. 목록에 이름을 더하면 그 파일에서는 꺼진 채가 되므로 따로 있는 키로 했다. hangul 체인의 설정
   디스크가 바로 그 모양(목록은 있고 `esc_latin=` 줄은 없다)이라 디스크를 안 고친다. seed는 1,969 → 2,191바이트이고
   `MAX_FILE`(4096) 안이다.

4. argv. init의 `Child.argv`는 `[8:null]`이고 terminal에 여덟 칸을 다 쓴다. 칸을 늘리지 않고 여덟째 목록 끝에
   `esc_latin`을 붙인다. 가장 긴 목록이 55바이트라 `TOGGLE_ARG_MAX`(64)는 그대로이고, `config.zig`의 `comptime`이
   `longest`로 그것을 못 박는다. init의 로그는 `toggle_arg`(파일의 목록)를 그대로 찍고, argv에는 새 버퍼의
   `terminal_toggle_arg`가 간다.

5. 게이트의 모양. 사본의 plan 판 시리얼 로그에서 본 것이다.
   - 검사 20은 copy mode 안에서 끝난다(find 제출 뒤 모드가 `.copy`). 그래서 검사 21의 Esc가 `terminal: copy> exit`를
     만든다. 그 Esc는 `hangul>` 줄을 안 만든다 — 한/영이 안 바뀌어 `redraw`가 안 켜진다.
   - fish는 혼자 온 Esc를 명령줄에 안 쓴다. 검사 22는 그래도 `ctrl-c`로 명령줄을 비운 뒤 친다. 마지막 화면이
     `root@(none) ~# echo el-ok | el-ok | root@(none) ~#`였다.
   - vim의 상태 줄에는 `unix  `(공백 둘)이, insert에서는 `-- INSERT --`가 보인다. vim이 끝난 뒤 마지막 화면은
     `root@(none) ~# vim /tmp/el.txt | root@(none) ~# cat /tmp/el.txt | 닷 | root@(none) ~#`였다. 검사 24 앞의 `ctrl-l`이
     옛 글자를 지워서 이 줄이 화면의 첫 행부터다.
   - `wait_for_screen`은 로그의 모든 `screen>`을 본다. 검사 24는 PD-M4의 `wait_for_new_screen`을 그대로 옮겨 기준점
     뒤의 화면만 본다.
   - 3-P3에서 `u f q`가 `닷`이다. 사본에서 `hangul>` 줄이 `ㄷ` → `닷`으로 찍혔다(`f`와 `q`가 한 read에 실려 와 중간의
     `다`가 안 찍힐 수 있다). `:wq`의 `w`와 `q`도 한 read에 실려 `key> 2 byte(s)`가 될 수 있다. 판정은 둘 다 안 센다.

6. mutation. 다섯 판이다 — 호스트 검사가 잡는 둘과 체인이 잡는 셋. 사본에서 전부 돌렸다.

   | mutation | 바꾸는 줄 | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|
   | 1 `readKeys`가 한/영의 앞뒤를 안 비교한다 | `input.zig`: `if (self.hangul_on != was_on) redraw = true;` → `_ = was_on;` | 호스트 `input_test` 검사 74 | `FAIL: Esc with hangul on gave 1 byte(s), redraw=false, hangul_on=false; want 1, true, false` | 43초 |
   | 1(호스트 검사를 건너뛴 체인) | 같다 | 체인 검사 23 | `FAIL: Esc turned hangul off without a redraw (no new hangul> line); readKeys did not compare hangul_on` | 2분 39초 |
   | 2 Esc 갈래가 설정을 안 본다 | `input.zig`: `… and self.toggles.esc_latin and !self.shifted()` → `… and !self.shifted()` | 호스트 `input_test` 검사 72 | `FAIL: Esc turned hangul off with esc_latin off` | 40초 |
   | 3 terminal이 목록의 `esc_latin`을 버린다 | `input.zig`: `.esc_latin => t.esc_latin = true,` → `.esc_latin => {},` | 체인 검사 0 | `FAIL: the toggle list did not reach terminal through argv (expected shift_space,capslock_tap,lctrl_tap,esc_latin)` | 1분 53초 |
   | 4 init이 argv에 파일의 목록만 넘긴다 | `init/src/main.zig`: `cfg.terminalToggles(&terminal_toggle_buf)` → `cfg.hangul_toggle.arg(&terminal_toggle_buf)` | 체인 검사 0 | 3과 같은 줄 | 1분 50초 |

   시간은 캐시를 지운 빌드를 포함한다. 읽을 것 셋.
   - 1의 체인 판이 design 결정 3의 구멍을 그대로 보였다. 검사 22(조합 중)는 확정분이 `redraw`를 켜서 지났고, 검사
     23에서 마지막 `hangul>` 줄이 Shift+Space의 `on=true` 그대로, 상태 줄이 `한  공세벌 3-P3  쿼티  CAPS` 그대로였다.
     안에서는 한글이 꺼졌는데 화면과 로그에는 그것이 안 나타난다.
   - 2는 체인이 못 잡는다. 디스크에 `esc_latin=` 줄이 없어 기본값 `on`으로 도므로, 설정을 무시해도 동작이 같다.
     `off` 갈래를 보는 것은 호스트 검사뿐이다(design 결정 4).
   - 3 · 4는 호스트 검사가 지난다. terminal의 `parseToggles`에는 호스트 검사가 없고(HI-M3 때부터 argv 배선은 게이트가
     본다), init의 `main.zig`는 `config_test` 밖이다. 둘 다 체인 검사 0의 terminal 줄이 잡는다.

7. regression. vim과 Esc와 seed를 쓰는 체인 셋을 사본에서 돌렸다. 셋 다 exit 0이다.

   | 체인 | 시간 | 왜 돌렸나 |
   |---|---|---|
   | `config` | 2분 43초 | seed `tars.conf`가 세 줄 늘었고 init 로그 줄 끝이 바뀌었다. `tars-config`가 seed를 화면에 찍는다 |
   | `render` | 1분 48초 | vim 안에서 Esc를 친다(그때 한글은 꺼져 있다) |
   | `copy` | 2분 51초 | copy mode의 Esc를 가장 많이 친다 |

   한글을 켜는 체인은 hangul 하나뿐이라(`shift-spc`를 치는 체인이 없다) 나머지 체인의 Esc는 EL 전과 같은 길을 간다.
   `readKeys`의 비교는 한/영이 안 바뀌면 아무것도 안 한다. 루트 게이트가 전부를 본다.

8. 시간. 같은 사본에서 판마다 `init` · `terminal`의 `.zig-cache` · `zig-out`을 컨테이너 안에서 지우고 한 번 데운
   뒤 잰 두 번째 판이다. hangul 체인이 HEAD 판 65초, 이 plan의 판 81초다 — 검사 21~24가 16초를 더한다(데우는 판은
   153초 · 169초). 루트 게이트는 체인을 두 번 돌리므로 PD-M4 뒤의 값에 30초 남짓을 더한 것으로 본다.

9. 낡은 산출물의 함정을 이 plan을 쓰며 한 번 밟았다. HEAD 판을 처음 잴 때 `init/zig-out`을 안 지웠더니, 소스는
   HEAD로 되돌렸는데 부팅한 init이 plan 판이었다(로그 줄 끝에 `esc_latin=on`이 있었다). `project_zig_out_staleness`
   그대로다. 아래 Task 5 · 6의 명령은 전부 캐시 삭제를 같은 `docker run` 안에 둔다.

10. 앵커. 편집 서른여섯의 `old_string`이 HEAD 파일에 정확히 한 번씩 있고(`python3 /tmp/run/el0/anchors.py pre
    "$PWD"` → `pre: 36 edits, 0 bad`), `new_string`이 사본에 정확히 한 번씩 있다(`post: 36 edits, 0 bad`).

11. 호스트 검사의 수(HEAD → 이 plan). `input_test` OK 16 → 20. `zig build test`(terminal)의 `all checks passed` 넷과
    `PASS` 다섯은 그대로다. `init`의 `zig build test`는 `PASS` 둘 그대로다(`config_test`는 OK 줄을 따로 안 찍는다).

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

   컨테이너가 있으면 그것이 끝나기를 기다린다(위 lock 절차). 남의 컨테이너를 죽이지 않는다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: `git status`는 이 plan과 design(`docs/specs/2026-10-05-tars-escape-latin-design.md`)이 commit 전이면 그 둘뿐이고,
   lead가 고치는 중일 수 있는 `HANDOFF.md`와, 같은 날 다른 planner가 쓴 문서(`docs/specs/2026-10-05-tars-clipboard-scope-design.md`
   같은 것)가 더 있을 수 있다. 맨 위 commit이 `5acc735 Close pointer devices again after PD-M4: …`이거나 그 위에 lead의
   commit이 있다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 10).

   ```bash
   python3 /tmp/run/el0/anchors.py pre "$PWD"
   ```

   기대: `pre: 36 edits, 0 bad`. 하나라도 `bad`면 그 줄을 보고하고 멈춘다.

4. 호스트 검사의 지금 값을 본다.

   ```bash
   mkdir -p /tmp/run/el0/impl
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
     rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
     (cd terminal && zig build test > /tmp/t.out 2>&1); echo "terminal exit=$?"
     grep -a -c "^input_test: .* OK$" /tmp/t.out
     grep -a -c "all checks passed" /tmp/t.out
     grep -a -c "^PASS$" /tmp/t.out
     (cd init && zig build test > /tmp/i.out 2>&1); echo "init exit=$?"
     grep -a -c "^PASS$" /tmp/i.out
     grep -a -E "FAIL|error:" /tmp/t.out /tmp/i.out | head -5'; rc=$?
   rmdir /tmp/run/docker.lock
   ```

   기대: `terminal exit=0`, 그 아래 `16` · `4` · `5`, `init exit=0`, `2`, 마지막 `grep` 0줄. 캐시를 지웠으므로 2~3분
   걸린다.

## Task 1: `terminal/src/input.zig` · `input_test.zig` — Esc 갈래와 앞뒤 비교

design 결정 1 · 2 · 3. `input.zig`의 E1~E5가 `Toggles` · `ToggleKey` · 파서 · 정규형에 이름 하나를, E6이 `Keys.redraw`
주석을, E7 · E8이 `State.toggles` 기본값을, E9가 `hangulLayer`의 Esc 갈래를, E10이 `readKeys`의 비교를 넣는다.

### 1-1. `input.zig` — 편집 열

E1 — `old_string`(기준 파일 165줄부터):

```zig
/// `config_test`의 `arg` → `parse` 왕복 검사다.
```

`new_string`:

```zig
/// `config_test`의 `arg` → `parse` 왕복 검사다.
///
/// 다섯째 `esc_latin`(EL-M0)은 설정 파일에서 오는 길이 다르다. 앞의 넷은
/// `hangul_toggle` 목록의 이름이고 `esc_latin`은 따로 있는 키(`esc_latin=on`)인데,
/// init이 둘을 argv 문자열 하나로 합쳐 넘긴다(`Config.terminalToggles`, EL design
/// 결정 1). 그래서 이 구조체가 담는 것은 "설정 파일의 한 줄"이 아니라 "argv로 온
/// 목록"이다.
```

E2 — `old_string`(기준 파일 170줄부터):

```zig
    lctrl_tap: bool = false,
```

`new_string`:

```zig
    lctrl_tap: bool = false,
    /// 한글을 치다가 수정키 없는 Esc를 누르면 영문으로 돌아온다(EL design
    /// 결정 2). 앞의 넷과 달리 한 방향이다 — 끄기만 하고 켜지는 않는다.
    esc_latin: bool = false,
```

E3 — `old_string`(기준 파일 177줄부터):

```zig
/// `parseToggles`가 이름을 거르는 화이트리스트. `config.zig`의 `ToggleKey`와
/// 이름이 같아야 한다.
const ToggleKey = enum { hangul_key, shift_space, capslock_tap, lctrl_tap };
```

`new_string`:

```zig
/// `parseToggles`가 이름을 거르는 화이트리스트. 앞의 넷은 `config.zig`의
/// `ToggleKey`와 이름이 같아야 한다. `esc_latin`은 그쪽 목록에 없고
/// `Config.terminalToggles`가 붙인다(EL design 결정 1).
const ToggleKey = enum { hangul_key, shift_space, capslock_tap, lctrl_tap, esc_latin };
```

E4 — `old_string`(기준 파일 198줄부터):

```zig
            .lctrl_tap => t.lctrl_tap = true,
```

`new_string`:

```zig
            .lctrl_tap => t.lctrl_tap = true,
            .esc_latin => t.esc_latin = true,
```

E5 — `old_string`(기준 파일 216줄부터):

```zig
    if (t.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
```

`new_string`:

```zig
    if (t.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
    if (t.esc_latin) appendToggleName(buf, &len, "esc_latin");
```

E6 — `old_string`(기준 파일 517줄부터):

```zig
    /// 두 번 뒤집으면 마지막 값 하나만 그리면 된다.
```

`new_string`:

```zig
    /// 두 번 뒤집으면 마지막 값 하나만 그리면 된다.
    ///
    /// 켜는 자리가 셋이다. 키가 `.redraw`를 돌려줬을 때, 확정된 글자가
    /// 있을 때, 그리고 키가 `hangul_on`을 바꿨을 때다(EL-M0). 셋째는 바이트를
    /// 함께 내보내는 키(Esc)를 위한 것이다 — `readKeys`의 주석에 있다.
```

E7 — `old_string`(기준 파일 715줄부터):

```zig
    /// 사람이 어느 쪽이 기본인지 알 수 없다.
```

`new_string`:

```zig
    /// 사람이 어느 쪽이 기본인지 알 수 없다. `esc_latin`의 짝은 `hangul_toggle`이
    /// 아니라 `Config.esc_latin`(기본 `on`)이다.
```

E8 — `old_string`(기준 파일 720줄부터):

```zig
        .lctrl_tap = true,
```

`new_string`:

```zig
        .lctrl_tap = true,
        .esc_latin = true,
```

E9 — `old_string`(기준 파일 1067줄부터):

```zig
        if (self.ctrled() or self.alted() or self.metaed()) {
            self.commitHangul();
```

`new_string`:

```zig
        if (self.ctrled() or self.alted() or self.metaed()) {
            self.commitHangul();
            return null;
        }

        // Esc가 한글을 끈다(EL design 결정 2). vim의 insert에서 한글을 치다가
        // Esc로 normal에 나오면 다음 키는 명령이고, 명령은 라틴 글자다 — 이
        // 갈래가 없으면 `j`가 자모가 된다. 사용자의 macOS 입력기 Patal의
        // `ESC라틴`과 같은 동작이다.
        //
        // 확정하고, 끄고, null을 돌려준다. null이므로 Esc는 평소의 길
        // (`keymap`)로 0x1b 한 바이트가 되어 PTY로 나가고, 확정된 글자는
        // `readKeys`가 그 바이트보다 먼저 쓴다 — vim은 글자를 받은 뒤에 Esc를
        // 받는다. 확정이 끄기보다 먼저인 것은 `toggleHangul`과 같은 불변식
        // ("`hangul_buf`가 비지 않았으면 `hangul_on`이 참") 때문이다.
        //
        // `Action`은 하나만 나르므로 여기서 `.redraw`를 함께 돌려줄 수 없다.
        // 상태 줄을 다시 그려야 한다는 사실은 `readKeys`가 `hangul_on`의 앞뒤를
        // 비교해서 안다(EL design 결정 3).
        //
        // Shift+Esc는 안 끈다. Patal이 수정키 없는 Esc만 보는 것을 따른다.
        // Ctrl · Alt · Meta는 바로 위 갈래가 이미 가져갔다.
        //
        // copy mode와 검색 프롬프트의 Esc는 여기 안 온다. 두 분기가 `handleKey`에서
        // 이 함수보다 앞에 있고 Esc를 먼저 가로챈다(CM design 결정 3 · SH design
        // 결정 3). 그래서 이 갈래가 도는 것은 normal 모드뿐이다.
        if (code == c.KEY_ESC and self.toggles.esc_latin and !self.shifted()) {
            self.commitHangul();
            self.hangul_on = false;
```

E10 — `old_string`(기준 파일 1621줄부터):

```zig
        const action = self.handleKey(ev.code, ev.value, eventMicros(ev), ctx);
```

`new_string`:

```zig
        // 한/영도 `handleKey` 앞에서 읽는다(EL design 결정 3). Esc가 한글을 끄는
        // 키는 바이트(0x1b)를 내보내야 해서 `.redraw`를 돌려줄 수 없다 —
        // `Action`은 하나만 나른다. 그래서 바뀌었는지를 여기서 앞뒤로 비교한다.
        // 비교하지 않으면 조합 중이 아닐 때의 Esc가 `redraw`를 안 켜고, 상태
        // 줄의 `한`이 다음 프레임까지 남는다. `Action`에 variant를 더하지 않는
        // 것은 IS-M1이 `Action.caps`를 안 만든 것과 같은 판단이다.
        const was_on = self.hangul_on;
        const action = self.handleKey(ev.code, ev.value, eventMicros(ev), ctx);
        if (self.hangul_on != was_on) redraw = true;
```

### 1-2. `input_test.zig` — 검사 69~74

`main()`의 맨 끝, `PASS` 줄 앞에 들어간다. 변수 이름이 전부 `el_`로 시작하는 것은 `main()`의 다른 이름과 안 겹치게
하려는 것이다(Zig는 바깥 이름을 가리는 것을 막는다 — HI-M1 실측 8).

E1 — `old_string`(기준 파일 1838줄부터):

```zig
    std.debug.print("PASS\n", .{});
```

`new_string`:

```zig
    // ── EL-M0: Esc가 한글을 끈다 ─────────────────────────────────────────
    //
    // 검사 69. 조합 중에 Esc를 치면 확정하고, Esc 바이트가 나가고, 한글이
    // 꺼진다(EL design 결정 2). 셋을 한 자리에서 본다 — 바이트가 `\x1b`
    // 하나이고, 확정분이 그보다 먼저 나갈 통로(`commit_buf`)에 있고, 그 뒤의
    // `r`이 라틴 글자다. `readKeys`가 확정분을 바이트보다 먼저 쓰므로(검사
    // 27) vim은 `가`를 받은 뒤에 Esc를 받는다.
    {
        var el_c: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expectHangul(&el_c, K.KEY_R, "", 'ㄱ');
        try expectHangul(&el_c, K.KEY_K, "", '가');
        try expect(&el_c, K.KEY_ESC, 1, "\x1b");
        try expectCommit(&el_c, K.KEY_ESC, "가");
        try expectPreedit(&el_c, K.KEY_ESC, null);
        if (el_c.hangul_on) {
            std.debug.print("FAIL: Esc while composing left hangul on\n", .{});
            return error.EscLatinFailed;
        }
        try expect(&el_c, K.KEY_R, 1, "r");

        // 검사 70. 조합 중이 아니어도 끈다. 확정분은 없다.
        el_c.hangul_on = true;
        try expect(&el_c, K.KEY_ESC, 1, "\x1b");
        try expectCommit(&el_c, K.KEY_ESC, "");
        if (el_c.hangul_on) {
            std.debug.print("FAIL: Esc with nothing composing left hangul on\n", .{});
            return error.EscLatinFailed;
        }

        // 검사 71. 한글이 꺼져 있으면 Esc는 EL 전과 같다 — 한 바이트이고
        // 아무것도 안 켠다. 한 방향이라는 것이 이 줄이다.
        try expect(&el_c, K.KEY_ESC, 1, "\x1b");
        if (el_c.hangul_on) {
            std.debug.print("FAIL: Esc turned hangul on\n", .{});
            return error.EscLatinFailed;
        }
    }
    std.debug.print("input_test: Esc가 조합을 확정하고 한글을 끈다 OK\n", .{});

    // 검사 72. 수정키가 있거나 설정이 끄면 Esc는 한글을 안 끈다. Shift+Esc는
    // Patal을 따른 것이고(EL design 결정 2), Ctrl+Esc는 `hangulLayer`의 Ctrl
    // 갈래가 먼저 가져간다. 셋 다 Esc 바이트는 그대로 나가고 조합은 확정된다 —
    // EL 전과 같은 동작이다.
    {
        var el_s: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expectHangul(&el_s, K.KEY_R, "", 'ㄱ');
        try expect(&el_s, K.KEY_LEFTSHIFT, 1, "");
        try expect(&el_s, K.KEY_ESC, 1, "\x1b");
        try expectCommit(&el_s, K.KEY_ESC, "ㄱ");
        try expect(&el_s, K.KEY_LEFTSHIFT, 0, "");
        if (!el_s.hangul_on) {
            std.debug.print("FAIL: Shift+Esc turned hangul off\n", .{});
            return error.EscLatinModifier;
        }
        try expect(&el_s, K.KEY_LEFTCTRL, 1, "");
        try expect(&el_s, K.KEY_ESC, 1, "\x1b");
        try expect(&el_s, K.KEY_LEFTCTRL, 0, "");
        if (!el_s.hangul_on) {
            std.debug.print("FAIL: Ctrl+Esc turned hangul off\n", .{});
            return error.EscLatinModifier;
        }

        // 설정에서 껐다(`esc_latin=off` → argv 목록에 이름이 없다). 전환 키
        // 넷은 켜 둔다 — 이 검사가 보는 것은 `esc_latin` 하나다.
        var el_o: input.State = .{
            .hangul_layout = .dubeol,
            .hangul_on = true,
            .toggles = .{
                .hangul_key = true,
                .shift_space = true,
                .capslock_tap = true,
                .lctrl_tap = true,
            },
        };
        try expectHangul(&el_o, K.KEY_R, "", 'ㄱ');
        try expect(&el_o, K.KEY_ESC, 1, "\x1b");
        try expectCommit(&el_o, K.KEY_ESC, "ㄱ");
        if (!el_o.hangul_on) {
            std.debug.print("FAIL: Esc turned hangul off with esc_latin off\n", .{});
            return error.EscLatinIgnoredSetting;
        }
    }
    std.debug.print("input_test: 수정키가 있거나 설정이 끄면 Esc는 한글을 안 끈다 OK\n", .{});

    // 검사 73. copy mode와 검색 프롬프트의 Esc는 한글을 안 끈다(EL design
    // 결정 2). 두 모드의 Esc는 한 겹을 벗기는 명령이고, 한/영은 그 모드에
    // 들어가기 전의 상태로 남는다 — 검색어를 한글로 치던 사람이 프롬프트를
    // 닫았다 다시 열면 한글이다. 검사 29가 copy mode 쪽을 HI 때부터 보고
    // 있고, 여기서는 둘을 나란히 본 뒤 셸로 돌아온 Esc가 끄는 것까지 본다.
    {
        var el_m: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        try expect(&el_m, K.KEY_LEFTMETA, 1, "");
        try expect(&el_m, K.KEY_LEFTSHIFT, 1, "");
        try expectCopy(&el_m, K.KEY_C, .enter);
        try expect(&el_m, K.KEY_LEFTSHIFT, 0, "");
        try expect(&el_m, K.KEY_LEFTMETA, 0, "");
        try expectCopy(&el_m, K.KEY_SLASH, .find_open);
        try expectCopy(&el_m, K.KEY_ESC, .find_cancel);
        if (!el_m.hangul_on) {
            std.debug.print("FAIL: the Esc that closed the find prompt turned hangul off\n", .{});
            return error.EscLatinInMode;
        }
        try expectCopy(&el_m, K.KEY_ESC, .exit);
        if (!el_m.hangul_on) {
            std.debug.print("FAIL: the Esc that left copy mode turned hangul off\n", .{});
            return error.EscLatinInMode;
        }
        // 셸로 돌아온 뒤의 Esc는 끈다. 모드가 갈래를 가른다는 것의 짝이다.
        try expect(&el_m, K.KEY_ESC, 1, "\x1b");
        if (el_m.hangul_on) {
            std.debug.print("FAIL: Esc back in the shell left hangul on\n", .{});
            return error.EscLatinFailed;
        }
    }
    std.debug.print("input_test: copy mode와 검색 프롬프트의 Esc는 한글을 안 끈다 OK\n", .{});

    // 검사 74. `readKeys`가 `redraw`를 켠다(EL design 결정 3).
    //
    // 첫째가 심장이다. 조합 중이 아니면 확정분이 없어서 `takeCommit` 갈래가
    // `redraw`를 안 켜고, Esc는 `.bytes`라 `.redraw` 갈래도 안 탄다. 남은 것은
    // `hangul_on`의 앞뒤 비교 한 줄뿐이다 — 그 줄이 없으면 상태 줄의 `한`이
    // 다음 키를 칠 때까지 남는다(IS design 결정 8과 같은 종류의 구멍).
    {
        var el_r: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        const evs = [_]input.c.struct_input_event{
            keyEvent(K.KEY_ESC, 1), keyEvent(K.KEY_ESC, 0),
        };
        const fds = try feedEvents(&evs);
        defer _ = close(fds[0]);
        var out: [64]u8 = undefined;
        const keys = input.readKeys(&el_r, fds[0], &out, .{});
        if (!std.mem.eql(u8, keys.bytes, "\x1b") or !keys.redraw or el_r.hangul_on) {
            std.debug.print(
                "FAIL: Esc with hangul on gave {d} byte(s), redraw={}, hangul_on={}; want 1, true, false\n",
                .{ keys.bytes.len, keys.redraw, el_r.hangul_on },
            );
            return error.EscLatinRedraw;
        }
    }
    // 대조군 — 한글이 꺼져 있으면 Esc는 `redraw`를 안 켠다. 이것이 없으면
    // "Esc는 언제나 다시 그린다"도 위 검사를 통과하고, 그 구현은 vim에서
    // Esc를 칠 때마다 화면 전체를 다시 그린다.
    {
        var el_q: input.State = .{};
        const evs = [_]input.c.struct_input_event{
            keyEvent(K.KEY_ESC, 1), keyEvent(K.KEY_ESC, 0),
        };
        const fds = try feedEvents(&evs);
        defer _ = close(fds[0]);
        var out: [64]u8 = undefined;
        const keys = input.readKeys(&el_q, fds[0], &out, .{});
        if (!std.mem.eql(u8, keys.bytes, "\x1b") or keys.redraw) {
            std.debug.print(
                "FAIL: Esc with hangul off gave {d} byte(s), redraw={}; want 1, false\n",
                .{ keys.bytes.len, keys.redraw },
            );
            return error.EscLatinRedraw;
        }
    }
    // 조합 중이면 확정분이 Esc보다 먼저 한 write에 실린다. vim이 받는 순서이고,
    // 게이트의 `key> 4 byte(s)`가 보는 것이 이 넷이다.
    {
        var el_p: input.State = .{ .hangul_layout = .dubeol, .hangul_on = true };
        const evs = [_]input.c.struct_input_event{
            keyEvent(K.KEY_R, 1), keyEvent(K.KEY_K, 1), keyEvent(K.KEY_ESC, 1),
        };
        const fds = try feedEvents(&evs);
        defer _ = close(fds[0]);
        var out: [64]u8 = undefined;
        const keys = input.readKeys(&el_p, fds[0], &out, .{});
        if (!std.mem.eql(u8, keys.bytes, "가\x1b") or !keys.redraw or el_p.hangul_on) {
            std.debug.print(
                "FAIL: 가 then Esc gave {any}, redraw={}, hangul_on={}; want 가 then 0x1b, true, false\n",
                .{ keys.bytes, keys.redraw, el_p.hangul_on },
            );
            return error.EscLatinOrder;
        }
    }
    std.debug.print("input_test: Esc가 한글을 끄면 readKeys가 다시 그리게 한다 OK\n", .{});

    std.debug.print("PASS\n", .{});
```

### 1-3. 확인

```bash
diff terminal/src/input.zig /tmp/run/el0/new/terminal/src/input.zig && echo SAME-input
diff terminal/src/input_test.zig /tmp/run/el0/new/terminal/src/input_test.zig && echo SAME-input_test
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  rm -rf .zig-cache zig-out
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -c "^input_test: .* OK$" /tmp/t.out
  grep -a -E "^input_test: (Esc|수정키|copy mode와)" /tmp/t.out
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'; rc=$?
rmdir /tmp/run/docker.lock
```

기대: `SAME-input` · `SAME-input_test`, `exit=0`, `20`, 그리고 넷 줄이다. 마지막 `grep`은 0줄이다. 캐시를 지우는
것은 낡은 실행 파일이 거짓 초록을 내는 것을 막기 위해서다(확정 9). 2분 안팎이다.

```
input_test: Esc가 조합을 확정하고 한글을 끈다 OK
input_test: 수정키가 있거나 설정이 끄면 Esc는 한글을 안 끈다 OK
input_test: copy mode와 검색 프롬프트의 Esc는 한글을 안 끈다 OK
input_test: Esc가 한글을 끄면 readKeys가 다시 그리게 한다 OK
```

## Task 2: `terminal/src/main.zig` — argv가 없을 때의 기본 목록

terminal을 손으로 띄울 때만 쓰이는 값이다. `config.zig`의 기본값과 눈으로 대조할 수 있게 같은 모양으로 둔다.

E1 — `old_string`(기준 파일 2211줄부터):

```zig
    // 대조할 형태가 설정 파일과 같아진다.
    const toggle_arg: []const u8 = if (args.len > 7)
        std.mem.span(args[7])
    else
        "hangul_key,shift_space,capslock_tap,lctrl_tap";
```

`new_string`:

```zig
    // 대조할 형태가 설정 파일과 같아진다. 끝의 `esc_latin`은 설정 파일의
    // `hangul_toggle`이 아니라 `esc_latin=on`에서 온다 — init이 둘을 합쳐 이
    // 자리에 넣는다(EL design 결정 1).
    const toggle_arg: []const u8 = if (args.len > 7)
        std.mem.span(args[7])
    else
        "hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin";
```

### 2-1. 확인

```bash
diff terminal/src/main.zig /tmp/run/el0/new/terminal/src/main.zig && echo SAME-main
```

기대: `SAME-main`. 빌드는 Task 5의 체인이 한다(`prepare.sh`).

## Task 3: `init/src/config.zig` · `config_test.zig` · `main.zig` — 설정 키와 argv

design 결정 1. `config.zig`의 E1이 `EscLatin`, E2가 `TOGGLE_ARG_MAX`의 주석과 `longest`, E3이 `Toggles.esc_latin`,
E4 · E5가 `arg`의 주석과 본문, E6이 `Config.esc_latin`과 `terminalToggles`, E7이 `parse`의 갈래, E8 · E9가 seed 세 줄과
그 인자다.

### 3-1. `config.zig` — 편집 아홉

E1 — `old_string`(기준 파일 45줄부터):

```zig
    off,
    on,
```

`new_string`:

```zig
    off,
    on,
};

/// 한글을 치다가 Esc를 누르면 영문으로 돌아오는가(EL design 결정 1).
///
/// `hangul_toggle` 목록의 다섯째 이름이 아니라 따로 있는 키인 이유가 둘이다.
/// 하나는 성질이다 — 그 목록은 한/영을 뒤집는 키의 집합인데 Esc는 끄기만
/// 한다. 다른 하나는 이미 만들어진 설정 파일이다. seed가 `hangul_toggle=`에
/// 넷을 글자 그대로 적어 두었으므로(`save`), 목록에 이름을 더하면 EL 전에
/// 만든 모든 `/config/tars.conf`에서 이 기능이 꺼진 채로 뜬다. 따로 있는
/// 키는 그 줄이 없는 파일에서 기본값(`on`)이 된다.
///
/// terminal에는 argv 한 칸을 따로 쓰지 않는다. 여덟 칸이 이미 다
/// 찼고(`main.zig`의 `Child.argv`), terminal은 이 값을 전환 키와 같은
/// 자리(`hangulLayer`)에서 읽으므로 `Config.terminalToggles`가 목록 문자열
/// 끝에 이름을 붙인다.
pub const EscLatin = enum {
    on,
    off,
```

E2 — `old_string`(기준 파일 768줄부터):

```zig
/// 45바이트이고 NUL 하나가 더 든다.
pub const TOGGLE_ARG_MAX = 64;

comptime {
    const longest = "hangul_key,shift_space,capslock_tap,lctrl_tap";
```

`new_string`:

```zig
/// 45바이트이고, `Config.terminalToggles`가 `,esc_latin` 열 바이트를 붙이면
/// 55바이트다. NUL 하나가 더 든다.
pub const TOGGLE_ARG_MAX = 64;

comptime {
    const longest = "hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin";
```

E3 — `old_string`(기준 파일 782줄부터):

```zig
    lctrl_tap: bool = false,
```

`new_string`:

```zig
    lctrl_tap: bool = false,
    /// `hangul_toggle` 목록으로는 못 켠다 — `ToggleKey`에 이 이름이 없다.
    /// 켜는 것은 `Config.terminalToggles` 하나이고, 그 값은 설정 파일의
    /// `esc_latin=` 줄에서 온다(EL design 결정 1). `parse`가 만드는 값에서는
    /// 언제나 거짓이므로 `arg` → `parse` 왕복이 그대로 맞는다.
    esc_latin: bool = false,
```

E4 — `old_string`(기준 파일 819줄부터):

```zig
    /// 없다(조합이 열여섯 가지다).
```

`new_string`:

```zig
    /// 없다(조합이 서른두 가지다).
```

E5 — `old_string`(기준 파일 832줄부터):

```zig
        if (self.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
```

`new_string`:

```zig
        if (self.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
        if (self.esc_latin) appendToggleName(buf, &len, "esc_latin");
```

E6 — `old_string`(기준 파일 899줄부터):

```zig
    firewall: Firewall = .off,
```

`new_string`:

```zig
    firewall: Firewall = .off,
    /// 기본값이 `on`인 근거는 `keyboard`·`hangul_layout`과 같다 — 이 기계를
    /// 쓰는 사람이 쓰는 것이 기본값이다(2026-10-05에 사용자가 요청했다).
    /// 이 키가 없는 파일에서도 켜진다. 그것이 이 값이 `hangul_toggle` 목록이
    /// 아니라 따로 있는 키인 이유다(위 `EscLatin`).
    esc_latin: EscLatin = .on,

    /// terminal의 argv로 넘기는 목록(EL design 결정 1). `hangul_toggle`의
    /// 정규형에 `esc_latin`을 더한다 — 켜져 있으면 맨 뒤에 그 이름이 붙는다.
    ///
    /// 로그의 `toggles=`는 이것이 아니라 `hangul_toggle.arg()`를 찍는다. 그
    /// 자리는 "파일의 `hangul_toggle`에 무엇이 적혔나"이고 `esc_latin=`은 줄
    /// 끝에 따로 찍힌다. 둘을 합친 모양은 terminal의 `hangul layout=… toggles=`
    /// 줄이 보여 준다.
    pub fn terminalToggles(self: Config, buf: []u8) [:0]const u8 {
        var t = self.hangul_toggle;
        t.esc_latin = self.esc_latin == .on;
        return t.arg(buf);
    }
```

E7 — `old_string`(기준 파일 1065줄부터):

```zig
        } else {
```

`new_string`:

```zig
        } else if (std.mem.eql(u8, key, "esc_latin")) {
            // shell_config와 완전히 같은 모양이다(EL design 결정 1).
            c.esc_latin = std.meta.stringToEnum(EscLatin, value) orelse {
                std.debug.print("tars-init: unknown esc_latin '{s}', falling back to {s}\n", .{
                    value, @tagName(c.esc_latin),
                });
                continue;
            };
        } else {
```

E8 — `old_string`(기준 파일 1111줄부터):

```zig
        \\hangul_toggle={s}
```

`new_string`:

```zig
        \\hangul_toggle={s}
        \\# esc_latin: on | off
        \\#   on이면 한글을 치다가 Esc를 눌렀을 때 영문으로 돌아온다. Esc는
        \\#   그대로 프로그램에 간다 — vim의 insert에서 나오면 다음 키가 명령이다
        \\esc_latin={s}
```

E9 — `old_string`(기준 파일 1142줄부터):

```zig
        c.hangul_toggle.arg(&toggle_buf),
```

`new_string`:

```zig
        c.hangul_toggle.arg(&toggle_buf),
        @tagName(c.esc_latin),
```

### 3-2. `config_test.zig` — 비교 · 출력 · EL-M0 절

E1 — `old_string`(기준 파일 100줄부터):

```zig
        got.firewall == want.firewall and
```

`new_string`:

```zig
        got.firewall == want.firewall and
        // EL-M0: 열한째 필드. FW-M1이 열째에 대해 적어 둔 것과 같은 자리다.
        got.esc_latin == want.esc_latin and
```

E2 — `old_string`(기준 파일 109줄부터):

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s}\n",
```

`new_string`:

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n",
```

E3 — `old_string`(기준 파일 122줄부터):

```zig
            @tagName(got.firewall),
```

`new_string`:

```zig
            @tagName(got.firewall),
            @tagName(got.esc_latin),
```

E4 — `old_string`(기준 파일 132줄부터):

```zig
            @tagName(want.firewall),
```

`new_string`:

```zig
            @tagName(want.firewall),
            @tagName(want.esc_latin),
```

E5 — `old_string`(기준 파일 1057줄부터):

```zig
    // ── `arg()` → `parse()` 왕복 ────────────────────────────────────────
```

`new_string`:

```zig
    // ── EL-M0: esc_latin ────────────────────────────────────────────────
    //
    // shell_config와 같은 모양이다. 기본값이 `on`이라 끄는 쪽을 적어야 값이
    // 갈린다.
    try expect("esc_latin=off\n", .{ .esc_latin = .off });
    try expect("esc_latin=on\n", .{});
    try expect("esc_latin=yes\n", .{}); // enum에 없는 값
    try expect("esc_latin=\n", .{}); // 값 없음
    // 목록의 이름으로는 못 켜고 못 끈다(EL design 결정 1). `esc_latin`은
    // `hangul_toggle`에서 모르는 이름이라 버려지고, 나머지 이름은 산다.
    try expect("hangul_toggle=shift_space,esc_latin\n", .{
        .hangul_toggle = .{ .shift_space = true },
    });
    // EL 전의 seed가 적어 둔 줄 그대로다. 이 파일에는 `esc_latin=` 줄이 없고,
    // 그래서 켜진 채로 읽힌다 — 이 키를 목록이 아니라 따로 둔 이유가 이 한
    // 줄이다.
    try expect("hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\n", .{
        .esc_latin = .on,
    });

    // `terminalToggles` — terminal의 argv로 가는 목록. 이 문자열이 init과
    // terminal을 잇는 유일한 것이라(`arg` → `parse` 왕복과 같은 자리) 넷을 다
    // 본다: 기본값, HI 게이트의 디스크, 끈 것, 목록이 빈 것.
    {
        const Case = struct { text: []const u8, want: []const u8 };
        const cases = [_]Case{
            .{ .text = "", .want = "hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin" },
            .{ .text = "hangul_toggle=shift_space,capslock_tap,lctrl_tap\n", .want = "shift_space,capslock_tap,lctrl_tap,esc_latin" },
            .{ .text = "esc_latin=off\n", .want = "hangul_key,shift_space,capslock_tap,lctrl_tap" },
            .{ .text = "hangul_toggle=\n", .want = "esc_latin" },
            .{ .text = "hangul_toggle=\nesc_latin=off\n", .want = "none" },
        };
        for (cases) |tc| {
            const cfg = config.parse(tc.text);
            var tbuf: [config.TOGGLE_ARG_MAX]u8 = undefined;
            const got = cfg.terminalToggles(&tbuf);
            if (!std.mem.eql(u8, got, tc.want)) {
                std.debug.print("FAIL: terminalToggles for [{s}] gave \"{s}\", want \"{s}\"\n", .{ tc.text, got, tc.want });
                return error.UnexpectedToggleArg;
            }
            // 파일의 `hangul_toggle`은 그대로다 — 이 함수가 `Config`를 안 바꾼다.
            if (cfg.hangul_toggle.esc_latin) {
                std.debug.print("FAIL: parse put esc_latin into hangul_toggle for [{s}]\n", .{tc.text});
                return error.UnexpectedToggleArg;
            }
        }
    }

    // ── `arg()` → `parse()` 왕복 ────────────────────────────────────────
```

### 3-3. `main.zig` — argv와 로그 줄

E1 — `old_string`(기준 파일 818줄부터):

```zig
    const toggle_arg = cfg.hangul_toggle.arg(&toggle_buf);
```

`new_string`:

```zig
    const toggle_arg = cfg.hangul_toggle.arg(&toggle_buf);
    // terminal에 가는 것은 위 목록에 `esc_latin`을 더한 것이다(EL design
    // 결정 1). 로그는 파일에 적힌 두 키를 따로 찍고, argv는 합친 것을 쓴다.
    // 수명은 `toggle_buf`와 같다.
    var terminal_toggle_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const terminal_toggle_arg = cfg.terminalToggles(&terminal_toggle_buf);
```

E2 — `old_string`(기준 파일 823줄부터):

```zig
    // FW-M1도 같은 이유로 `firewall=`을 맨 뒤에 붙였다.
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s}\n",
```

`new_string`:

```zig
    // FW-M1도 같은 이유로 `firewall=`을 맨 뒤에 붙였고, EL-M0이 `esc_latin=`을
    // 그 뒤에 붙였다.
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n",
```

E3 — `old_string`(기준 파일 837줄부터):

```zig
            @tagName(cfg.firewall),
```

`new_string`:

```zig
            @tagName(cfg.firewall),
            @tagName(cfg.esc_latin),
```

E4 — `old_string`(기준 파일 1039줄부터):

```zig
            toggle_arg.ptr,
```

`new_string`:

```zig
            terminal_toggle_arg.ptr,
```

### 3-4. 확인

```bash
for f in config config_test main; do diff init/src/$f.zig /tmp/run/el0/new/init/src/$f.zig && echo SAME-$f; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  rm -rf .zig-cache zig-out
  zig build test > /tmp/i.out 2>&1; echo "test exit=$?"
  grep -a -c "^PASS$" /tmp/i.out
  grep -a -E "FAIL|error:" /tmp/i.out | head -5
  zig build > /tmp/b.out 2>&1; echo "build exit=$?"; grep -a -E "error:" /tmp/b.out | head -5'; rc=$?
rmdir /tmp/run/docker.lock
```

기대: `SAME-config` · `SAME-config_test` · `SAME-main`, `test exit=0`, `2`, `FAIL` · `error:` 0줄, `build exit=0`, 0줄.
`config_test`가 일부러 깨진 값을 먹이므로 `/tmp/i.out`에 `tars-init: unknown esc_latin 'yes', falling back to on` ·
`tars-init: unknown hangul_toggle 'esc_latin', ignored` 같은 줄이 섞이는 것은 정상이다.

## Task 4: `hangul/make_disk.sh` · `hangul/check.sh`

design 결정 4. `make_disk.sh`는 머리 주석만 고친다 — heredoc(디스크에 들어갈 `tars.conf`)은 한 글자도 안 바뀐다.
`check.sh`의 E1이 머리 주석, E2가 헬퍼 넷(`key_lines_of` · `hangul_lines` · `screen_lines` · `wait_for_new_screen`),
E3 · E4가 검사 0, E5가 검사 21~24다.

### 4-1. `make_disk.sh` — 주석 한 문단

E1 — `old_string`(기준 파일 30줄부터):

```bash
# 문자열에 `hangul_key`가 없다는 것 자체가 "설정이 그것을 껐다"의 증거다.
```

`new_string`:

```bash
# 문자열에 `hangul_key`가 없다는 것 자체가 "설정이 그것을 껐다"의 증거다.
#
# `esc_latin=` 줄은 일부러 없다(EL-M0). EL 전의 seed가 만든 파일이 전부 그렇게
# 생겼고(`hangul_toggle`에 목록을 적고 `esc_latin`은 모른다), 그런 파일에서도
# Esc가 한글을 끄는지가 EL design 결정 1의 질문이다. 체인의 검사 0이
# `esc_latin=on`을, 검사 22~24가 그 동작을 본다.
```

### 4-2. `check.sh` — 편집 다섯

E1 — `old_string`(기준 파일 16줄부터):

```bash
#   → Shift+Space를 다시 누르면 영문으로 돌아온다
```

`new_string`:

```bash
#   → Shift+Space를 다시 누르면 영문으로 돌아온다
#   → 한글을 치다가 Esc를 누르면 조합이 확정되고 Esc가 셸(vim)에 가고
#     영문으로 돌아온다(EL-M0, 검사 21~24)
```

E2 — `old_string`(기준 파일 243줄부터):

```bash
qemu-system-x86_64 \
```

`new_string`:

```bash
# 바이트 수가 정확히 N인 `key>` 줄이 지금까지 몇 개인가(EL-M0). 한 write의
# 크기가 판정이다 — 확정된 음절과 Esc가 함께 나가면 4, Esc만이면 1이다.
key_lines_of() {
  grep -ac "terminal: key> $1 byte(s)" "$LOG" || true
}

# `hangul>` 줄이 지금까지 몇 개인가(EL-M0). 그 줄은 `keys.redraw`일 때만
# 찍히므로(main.zig), 개수가 늘었다는 것이 "다시 그리는 길을 탔다"이다.
hangul_lines() {
  grep -ac 'terminal: hangul>' "$LOG" || true
}

# `screen>` 줄이 지금까지 몇 개인가. 아래 `wait_for_new_screen`의 기준점이다.
screen_lines() {
  grep -ac 'terminal: screen>' "$LOG" || true
}

# N번째 뒤의 `screen>`에 패턴이 나타날 때까지 기다린다(EL-M0, pointer 체인의
# 것과 같다). `wait_for_screen`은 로그의 모든 `screen>`을 보므로, 옛 화면에
# 있던 글자가 바로 맞는다 — vim이 끝나고 돌아온 화면만 보려면 기준점이
# 필요하다. 있으면 0, 15초가 지나면 1.
wait_for_new_screen() {
  local n="$1" pattern="$2" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(grep -a 'terminal: screen>' "$LOG" | tail -n "+$((n + 1))")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

qemu-system-x86_64 \
```

E3 — `old_string`(기준 파일 321줄부터):

```bash
# 그래서 끝 대신 경계를 본다: 목록 다음에 공백이 오거나 줄이 끝난다.
```

`new_string`:

```bash
# 그래서 끝 대신 경계를 본다: 목록 다음에 공백이 오거나 줄이 끝난다.
# EL-M0이 그 줄 끝에 `esc_latin=on`을 붙였을 때 이 판정은 한 글자도 안
# 바뀌었다 — 이 처방이 값을 한 자리다.
```

E4 — `old_string`(기준 파일 345줄부터):

```bash
if ! tr -d '\r' < "$LOG" |
  grep -a "terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=${EXPECT_TOGGLES}\$" >/dev/null; then
  report_failure "the toggle list did not reach terminal through argv"
fi
echo "three toggle keys came from the config file; hangul_key is off"
```

`new_string`:

```bash
# EL-M0. 디스크의 `tars.conf`에는 `esc_latin=` 줄이 없다(make_disk.sh). EL 전에
# 만든 설정 파일이 모두 그렇게 생겼고, 그런 파일에서도 기본값 `on`이 산다는
# 것이 EL design 결정 1이다. init은 그 값을 줄 끝에 따로 찍고, terminal에는
# 목록 끝에 이름을 붙여 넘긴다(`Config.terminalToggles`). 그래서 init의
# `toggles=`는 셋 그대로이고 terminal의 목록만 넷이 된다.
if ! tr -d '\r' < "$LOG" |
  grep -aE "tars-init: config .* esc_latin=on\$" >/dev/null; then
  report_failure "init did not report esc_latin=on (the disk has no esc_latin line, so this is the default)"
fi
if ! tr -d '\r' < "$LOG" |
  grep -a "terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=${EXPECT_TOGGLES},esc_latin\$" >/dev/null; then
  report_failure "the toggle list did not reach terminal through argv (expected ${EXPECT_TOGGLES},esc_latin)"
fi
echo "three toggle keys came from the config file; hangul_key is off; esc_latin is on by default"
```

E5 — `old_string`(기준 파일 1019줄부터):

```bash
echo "HI check PASS"
```

`new_string`:

```bash
# ── 검사 21: copy mode의 Esc는 한/영을 안 바꾼다 (EL-M0) ──────────────
#
# 검사 20이 copy mode 안에서 끝났다(제출한 뒤 프롬프트만 닫혔다). 한글은
# 검사 15가 켠 그대로다. 이 Esc는 copy mode를 닫는 명령이고 한글을 끄면 안
# 된다(EL design 결정 2) — 검색어를 한글로 치던 사람이 셸로 돌아와도 한글이다.
#
# 판정은 마지막 `hangul>` 줄이다. 끄는 코드가 이 갈래로 새면 `readKeys`가
# 앞뒤 비교로 `redraw`를 켜고 `on=false` 줄을 새로 찍는다. 상태 줄은 `COPY`가
# 빠지면서 새로 찍히므로, 첫 칸이 `한`인 것을 함께 본다.
echo "=== Esc leaves copy mode and keeps hangul on ==="
EXITS_BEFORE="$(grep -ac 'terminal: copy> exit' "$LOG" || true)"
type_keys esc
sleep 1
EXITS_AFTER="$(grep -ac 'terminal: copy> exit' "$LOG" || true)"
if [ "$EXITS_AFTER" -le "$EXITS_BEFORE" ]; then
  report_failure "Esc did not leave copy mode (copy> exit ${EXITS_BEFORE} -> ${EXITS_AFTER}), so this check saw nothing"
fi
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "the Esc that left copy mode turned hangul off (on=${ON})"
fi
TEXT="$(status_text)"
if [ "$TEXT" != "한  공세벌 3-P3  쿼티  CAPS" ]; then
  report_failure "after leaving copy mode the status line reads \"${TEXT}\", expected \"한  공세벌 3-P3  쿼티  CAPS\""
fi
echo "copy mode closed and hangul stayed on: \"${TEXT}\""

# ── 검사 22: 조합 중의 Esc — 확정하고, Esc가 나가고, 영문이 된다 ────────
#
# `key> 4 byte(s)`가 판정의 심장이다. 확정된 `ㄱ`(UTF-8 세 바이트)과 Esc
# 하나가 같은 write로 나갔다는 뜻이고, 그 순서가 vim이 글자를 받은 뒤에
# normal로 나가는 순서다. 검사 6이 Enter에 대해 본 것과 같은 계약이다.
#
# 그리고 뒤에 친 글자가 영문으로 셸에 닿아야 한다. 3-P3에서 `e c h o`는
# 자모라, 한글이 안 꺼졌으면 `el-ok`가 화면에 안 나온다.
echo "=== compose ㄱ, then Esc ==="
type_keys ctrl-c
sleep 1
type_keys k
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "ㄱ" ]; then
  report_failure "typing 'k' composed preedit=${PRE}, expected ㄱ"
fi
FOURS_BEFORE="$(key_lines_of 4)"
type_keys esc
sleep 1
FOURS_AFTER="$(key_lines_of 4)"
if [ "$FOURS_AFTER" -ne $((FOURS_BEFORE + 1)) ]; then
  report_failure "Esc did not send the committed ㄱ and ESC as one 4-byte write (key> 4 byte(s) ${FOURS_BEFORE} -> ${FOURS_AFTER})"
fi
ON="$(hangul_field on)"
PRE="$(hangul_field preedit)"
if [ "$ON" != "false" ] || [ "$PRE" != "(none)" ]; then
  report_failure "Esc while composing left hangul on=${ON} preedit=${PRE}, expected on=false preedit=(none)"
fi
TEXT="$(status_text)"
if [ "$TEXT" != "EN  공세벌 3-P3  쿼티  CAPS" ]; then
  report_failure "after Esc the status line reads \"${TEXT}\", expected \"EN  공세벌 3-P3  쿼티  CAPS\""
fi
# 셸에 남은 `ㄱ`을 지우고 영문을 친다. fish는 혼자 온 Esc를 명령줄에 안 쓴다.
type_keys ctrl-c
sleep 1
type_keys e c h o spc e l minus o k ret
sleep 2
if [ "$(screen_count 'el-ok')" -lt 2 ]; then
  report_failure "after Esc the keys did not reach the shell as latin (el-ok is not on the command line and in the output)"
fi
echo "Esc committed ㄱ with ESC in one 4-byte write, turned hangul off, and latin is back"

# ── 검사 23: 조합 중이 아닌 Esc도 끄고, 상태 줄이 바로 따라온다 ────────
#
# 이 검사가 EL design 결정 3을 보는 자리다. 확정할 글자가 없으면
# `takeCommit`이 `redraw`를 안 켜고, Esc는 `.bytes`라 `.redraw`도 아니다.
# `readKeys`의 앞뒤 비교가 없으면 `hangul>` 줄이 안 찍히고 상태 줄의 `한`이
# 다음 키를 칠 때까지 남는다 — 그래서 판정이 둘 다 다른 키를 치기 전이다.
echo "=== Shift+Space, then Esc with nothing composing ==="
type_keys shift-spc
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Shift+Space left hangul on=${ON}, expected true"
fi
ONES_BEFORE="$(key_lines_of 1)"
HANGUL_BEFORE="$(hangul_lines)"
type_keys esc
sleep 1
ONES_AFTER="$(key_lines_of 1)"
HANGUL_AFTER="$(hangul_lines)"
if [ "$ONES_AFTER" -ne $((ONES_BEFORE + 1)) ]; then
  report_failure "Esc with nothing composing did not send exactly one byte (key> 1 byte(s) ${ONES_BEFORE} -> ${ONES_AFTER})"
fi
if [ "$HANGUL_AFTER" -le "$HANGUL_BEFORE" ]; then
  report_failure "Esc turned hangul off without a redraw (no new hangul> line); readKeys did not compare hangul_on"
fi
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "Esc with nothing composing left hangul on=${ON}, expected false"
fi
TEXT="$(status_text)"
if [ "$TEXT" != "EN  공세벌 3-P3  쿼티  CAPS" ]; then
  report_failure "after a bare Esc the status line reads \"${TEXT}\", expected \"EN  공세벌 3-P3  쿼티  CAPS\""
fi
echo "a bare Esc sent one byte, turned hangul off, and the status line followed at once"

# ── 검사 24: vim — insert에서 한글을 치고 Esc, 그 뒤 :wq가 영문이다 ──────
#
# 사용자의 요청 그대로다(2026-10-05). insert에서 `닷`을 조합하다가 Esc를
# 치면, vim은 `닷`을 받고 normal로 나가고, 우리는 영문으로 돌아온다. 그래서
# 바로 친 `:wq`가 명령이 되어 파일을 쓰고 나간다. 셋 중 하나라도 어긋나면
# 셸 화면이 안 돌아오거나 파일에 `닷`이 없다.
#
# 3-P3에서 `u`가 초성 ㄷ, `f`가 중성 ㅏ, `q`가 종성 ㅅ이다. 이 체인의 앞
# 검사들이 안 쓴 글자를 고른 것은 화면에 남은 옛 글자와 안 섞이게 하려는
# 것이다.
echo "=== vim: type 닷 in insert mode, Esc, then :wq ==="
type_keys ctrl-l
sleep 1
SCREENS_N="$(screen_lines)"
type_keys v i m spc slash t m p slash e l dot t x t ret
wait_for_new_screen "$SCREENS_N" 'unix  ' || report_failure "vim did not open /tmp/el.txt"
type_keys i
wait_for_new_screen "$SCREENS_N" 'INSERT' || report_failure "vim did not enter insert mode"
type_keys shift-spc
sleep 1
type_keys u f q
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "닷" ]; then
  report_failure "typing 'ufq' in vim composed preedit=${PRE}, expected 닷"
fi
FOURS_BEFORE="$(key_lines_of 4)"
type_keys esc
sleep 1
FOURS_AFTER="$(key_lines_of 4)"
if [ "$FOURS_AFTER" -ne $((FOURS_BEFORE + 1)) ]; then
  report_failure "Esc in vim did not send 닷 and ESC as one 4-byte write (key> 4 byte(s) ${FOURS_BEFORE} -> ${FOURS_AFTER})"
fi
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "Esc in vim left hangul on=${ON}, expected false"
fi
# vim이 끝나기 전에 친 글자는 vim이 먹는다(PD-M4 실측). 돌아온 셸이 vim을 친
# 명령줄 다음에 새 프롬프트를 그릴 때까지 기다린다 — 그 화면은 vim이 도는
# 동안(대체 화면)에는 안 보인다.
SCREENS_N="$(screen_lines)"
type_keys shift-semicolon w q ret
wait_for_new_screen "$SCREENS_N" '~# vim /tmp/el\.txt \| root@' ||
  report_failure "vim did not write and quit after Esc and :wq (the keys after Esc were not latin, or Esc did not reach vim)"
SCREENS_N="$(screen_lines)"
type_keys c a t spc slash t m p slash e l dot t x t ret
wait_for_new_screen "$SCREENS_N" '~# cat /tmp/el\.txt \| 닷 \| root@' ||
  report_failure "/tmp/el.txt does not hold 닷 (vim did not get the committed syllable before ESC)"
echo "vim got 닷 before ESC, left insert mode, and took :wq in latin"

echo "HI check PASS"
```

### 4-3. 확인

```bash
bash -n hangul/check.sh && echo SYNTAX-OK
bash -n hangul/make_disk.sh && echo DISK-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./hangul/check.sh && require_no_early_exit_pipe ./hangul/check.sh &&
  require_explicit_nic ./hangul/check.sh && echo ENTRY-OK'
diff hangul/check.sh /tmp/run/el0/new/hangul/check.sh && echo SAME-check
diff hangul/make_disk.sh /tmp/run/el0/new/hangul/make_disk.sh && echo SAME-disk
python3 /tmp/run/el0/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `DISK-SYNTAX-OK` · `ENTRY-OK` · `SAME-check` · `SAME-disk` · `post: 36 edits, 0 bad`.

## Task 5: 체인 한 번과 regression

체인은 하나씩 돈다. 전부 같은 `kernel/initrd.cpio`를 다시 만들고, VM의 메모리가 4GB다. 캐시 삭제를 같은 `docker run`
안에 둔다(확정 9).

### 5-1. `hangul` 체인

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/el0:/tmp/run/el0 -w /workspace tars-devcontainer bash -c '
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash hangul/check.sh > /tmp/run/el0/impl/hangul.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
rg -a -n '^=== (Esc leaves|compose ㄱ|Shift\+Space, then Esc|vim: type)|^FAIL|esc_latin is on|^copy mode closed|^Esc committed|^a bare Esc|^vim got|^HI check' /tmp/run/el0/impl/hangul.log
```

기대: `exit=0`, 캐시를 지웠으므로 `real`이 2분 50초 안팎이다. `rg`는 이렇다(사본의 판).

```
three toggle keys came from the config file; hangul_key is off; esc_latin is on by default
=== Esc leaves copy mode and keeps hangul on ===
copy mode closed and hangul stayed on: "한  공세벌 3-P3  쿼티  CAPS"
=== compose ㄱ, then Esc ===
Esc committed ㄱ with ESC in one 4-byte write, turned hangul off, and latin is back
=== Shift+Space, then Esc with nothing composing ===
a bare Esc sent one byte, turned hangul off, and the status line followed at once
=== vim: type 닷 in insert mode, Esc, then :wq ===
vim got 닷 before ESC, left insert mode, and took :wq in latin
HI check PASS
```

줄 번호는 보고에 그대로 붙인다. 빨개지면 `report_failure`가 찍는 표식과 마지막 40줄을 그대로 보고한다.

### 5-2. regression — `config` · `render` · `copy`

확정 7의 셋이다. 한 컨테이너에서 차례로 돈다. 약 7분 반이다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/el0:/tmp/run/el0 -w /workspace tars-devcontainer bash -c '
    for c in config render copy; do s=$(date +%s); bash $c/check.sh > /tmp/run/el0/impl/reg_$c.log 2>&1
      echo "$c exit=$? $(( $(date +%s) - s ))s"; done' ; } 2>&1 | tail -6
rmdir /tmp/run/docker.lock
```

기대: 셋 다 `exit=0`. 사본에서는 163 · 108 · 171초였다.

## Task 6: mutation

확정 6의 표다. 사본은 `/tmp/run/el0/impl/mut/`에 만든다. 돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 —
`sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

### 6-0. 사본을 만든다

```bash
M=/tmp/run/el0/impl/mut; mkdir -p $M
for i in 1 2 3; do cp terminal/src/input.zig $M/input_m$i.zig; done
cp init/src/main.zig $M/init_main_m4.zig
cp hangul/check.sh $M/hangul_notest.sh
sd -F '        if (self.hangul_on != was_on) redraw = true;' '        _ = was_on;' $M/input_m1.zig
sd -F '        if (code == c.KEY_ESC and self.toggles.esc_latin and !self.shifted()) {' '        if (code == c.KEY_ESC and !self.shifted()) {' $M/input_m2.zig
sd -F '            .esc_latin => t.esc_latin = true,' '            .esc_latin => {},' $M/input_m3.zig
sd -F '    const terminal_toggle_arg = cfg.terminalToggles(&terminal_toggle_buf);' '    const terminal_toggle_arg = cfg.hangul_toggle.arg(&terminal_toggle_buf);' $M/init_main_m4.zig
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' $M/hangul_notest.sh
chmod +x $M/hangul_notest.sh
bash -c 'M=/tmp/run/el0/impl/mut; cd /Users/dp/Repository/tars-linux
  for i in 1 2 3; do echo "== m$i"; diff terminal/src/input.zig $M/input_m$i.zig; done
  echo "== m4"; diff init/src/main.zig $M/init_main_m4.zig
  echo "== notest"; diff hangul/check.sh $M/hangul_notest.sh'
```

기대: 다섯 `diff`가 각각 한 줄의 차이다. mutation 1은 `was_on`을 `_ =`로 버려서 안 쓰는 변수의 컴파일 에러를 피한다.

### 6-1. 호스트 검사가 잡는 둘 — mutation 1 · 2

`zig build test`만 돌린다. 부팅이 필요 없다.

```bash
bash -c 'cd /Users/dp/Repository/tars-linux
for m in 1 2; do
  echo "== mutation $m"
  until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
  docker run --rm -v "$PWD":/workspace -v /tmp/run/el0/impl/mut/input_m$m.zig:/workspace/terminal/src/input.zig:ro \
      -w /workspace/terminal tars-devcontainer bash -c "
    rm -rf .zig-cache zig-out
    zig build test > /tmp/t.out 2>&1; echo \"exit=\$?\"
    grep -a -E \"^FAIL\" /tmp/t.out | head -3"
  rmdir /tmp/run/docker.lock
done'
```

기대는 확정 6의 표에서 "호스트"인 두 줄이다.

### 6-2. 체인이 잡는 셋 — mutation 1(호스트 검사를 건너뛴 체인) · 3 · 4

mutation 1은 호스트 검사가 먼저 잡으므로, 게이트의 검사 23이 혼자서도 잡는지를 `zig build test`를 건너뛴 사본
체인으로 본다(PD-M1 · M3 plan과 같은 방법). `-e m=$m`으로 번호를 컨테이너에 넘긴다.

```bash
bash -c 'cd /Users/dp/Repository/tars-linux; M=/tmp/run/el0/impl/mut
run() { # $1 번호, $2 그 판의 -v 인자들, $3 체인 파일
  echo "== mutation $1"
  until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/el0:/tmp/run/el0 $2 -e m=$1 -w /workspace tars-devcontainer bash -c "
    echo \"mounted: m1=\$(grep -c \"        _ = was_on;\" terminal/src/input.zig) m3=\$(grep -c \".esc_latin => {},\" terminal/src/input.zig) m4=\$(grep -c \"cfg.hangul_toggle.arg(&terminal_toggle_buf)\" init/src/main.zig)\"
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash $3 > /tmp/run/el0/impl/mut/m\$m.log 2>&1; echo \"exit=\$?\"" ; } 2>&1 | tail -5
  rmdir /tmp/run/docker.lock
  rg -a -n "^===|^FAIL" $M/m$1.log | tail -2
}
run 1 "-v $M/input_m1.zig:/workspace/terminal/src/input.zig:ro -v $M/hangul_notest.sh:/workspace/hangul/check.sh:ro" hangul/check.sh
run 3 "-v $M/input_m3.zig:/workspace/terminal/src/input.zig:ro" hangul/check.sh
run 4 "-v $M/init_main_m4.zig:/workspace/init/src/main.zig:ro" hangul/check.sh'
```

로그에 `Killed`가 보이고 `FAIL: … build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지
보고 그 판만 다시 돈다.

기대는 확정 6의 표에서 "체인"인 세 줄이다. `mounted:`는 그 번호 자리만 1이다. mutation이 예상과 다른 자리에서
죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다(`project_zig_out_staleness` — 캐시 삭제가
같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 6-3. 되돌린다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. 산출물만 지금 소스로 다시 만든다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "terminal exit=$?"
  grep -a -c "^input_test: .* OK$" /tmp/t.out
  (cd init && zig build > /tmp/b.out 2>&1); echo "init exit=$?"
  (cd kernel && ./make_initrd.sh > /tmp/i.out 2>&1); echo "initrd exit=$?"'; rc=$?
rmdir /tmp/run/docker.lock
git status --short
```

기대: `terminal exit=0`, `20`, `init exit=0`, `initrd exit=0`. `git status`는 `M` 여덟(`hangul/check.sh` ·
`hangul/make_disk.sh` · `init/src/`의 셋 · `terminal/src/`의 셋)이고, plan과 design이 commit 전이면 그 둘이 더 있다.
다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 6-4. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `8 files changed, 570 insertions(+), 17 deletions(-)`였고,
  지운 줄 열일곱은 이렇다(파일 머리의 `---` 줄은 빼고). 이것과 다른 줄이 있으면 그 줄을 따로 적는다.

  ```
  -/// `parseToggles`가 이름을 거르는 화이트리스트. `config.zig`의 `ToggleKey`와
  -/// 이름이 같아야 한다.
  -const ToggleKey = enum { hangul_key, shift_space, capslock_tap, lctrl_tap };
  -    /// 사람이 어느 쪽이 기본인지 알 수 없다.
  -    // 대조할 형태가 설정 파일과 같아진다.
  -        "hangul_key,shift_space,capslock_tap,lctrl_tap";
  -/// 45바이트이고 NUL 하나가 더 든다.
  -    const longest = "hangul_key,shift_space,capslock_tap,lctrl_tap";
  -    /// 없다(조합이 열여섯 가지다).
  -        "FAIL: input={s}\n  got  shell={s} … firewall={s}\n" ++
  -            "  want shell={s} … firewall={s}\n",
  -    // FW-M1도 같은 이유로 `firewall=`을 맨 뒤에 붙였다.
  -        "tars-init: config shell={s} … firewall={s}\n",
  -            toggle_arg.ptr,
  -  grep -a "terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=${EXPECT_TOGGLES}\$" >/dev/null; then
  -  report_failure "the toggle list did not reach terminal through argv"
  -echo "three toggle keys came from the config file; hangul_key is off"
  ```

  가운데 셋은 줄이 길어 `…`로 줄였다. 실제 줄은 `toggles={s} shell_config={s} net={s} ntp={s} timezone={s}`가
  들어 있는 원래의 한 줄이다.
- Task 0의 출력.
- Task 1~4의 확인 출력(`SAME` · OK 줄 수 · `ENTRY-OK` · `anchors.py`).
- Task 5의 `exit=` · `real` · `rg` 출력과 regression 셋의 줄.
- Task 6의 `diff` 다섯 · `exit=` · `mounted:` · `real` · `FAIL` 줄, 6-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 7: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 파일 전부를 이 plan의 사본(`/tmp/run/el0/new/`)과 `cmp`한다. Task 5의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 열아홉 체인 × 2다. 판정은 `PASS: 2/2` × 19와 `HI check PASS` 둘이다. 커널을
   안 바꾸므로 첫 체인이 커널 전체 빌드를 치르는 것은 PD-M4와 같다. `run_in_background`로 돌리고 `{ time …; }`로 감싼다.
   다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_el0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_el0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 2/2' /tmp/gate_el0.log`가 19, `rg -c 'HI check PASS' /tmp/gate_el0.log`가 2여야 한다.
3. 실측 절 채우기.
4. commit. 넣는 것은 `terminal/src/input.zig` · `input_test.zig` · `main.zig` · `init/src/config.zig` · `config_test.zig` ·
   `main.zig` · `hangul/check.sh` · `hangul/make_disk.sh` · 이 plan이고, design이 commit 전이면 함께 넣는다. `git add`는
   경로를 하나씩 지정한다.
5. 닫기. design의 "닫을 때(lead의 몫)" 목록이다. 서브프로젝트를 닫는 commit은 EL-M0 commit과 따로 만든다.

## design과 다르게 적은 것

없다. design은 이 plan과 같은 날 함께 썼고, 이 plan이 사본에서 잰 것을 반영했다. lead가 보낸 전제와 다른 둘(설정
파일의 모양, 디스크를 고칠 자리)은 design의 "착수 전에 실측한 것" 5 · 6에 있다.

## 이 milestone에서 안 하는 것

- design 비목표 1~6(copy · find의 Esc, Shift+Esc와 `Ctrl+[`, 반대 방향, 패널마다 한/영, `esc_latin=off` 부팅,
  상태 표시 추가).
- `running-tars.md`와 HI design의 덧붙임. lead가 닫을 때 한다.
- seed `tars.conf`의 `ntp:` 주석이 TD 전의 설명("부팅할 때 한 번만 묻고")으로 남아 있는 것. 이 milestone과 무관하고,
  고치면 seed의 글자가 바뀌어 `config` 체인을 다시 봐야 한다. lead에게 넘긴다.

## EL-M0이 실측한 것

2026-10-05. 구현은 Sonnet 서브에이전트가, 대조 · 루트 게이트 · commit은 lead(Fable)가 했다.

1. 편집 서른여섯이 전부 글자 그대로 들어갔다. 구현자는 Edit 도구 대신 plan 본문에서 `old_string` · `new_string`을
   기계로 뽑아 적용하는 스크립트(`/tmp/run/el0/impl/apply.py`)를 썼고, 서른여섯이 저마다 정확히 한 번 맞았다. lead가
   여덟 파일을 `/tmp/run/el0/new/`와 `cmp`하니 바이트까지 같았다. `git diff --stat`은 570줄 더함 · 17줄 지움이고, 지운
   17줄은 6-4의 목록과 같았다(옛 화이트리스트 · 옛 `longest` · 로그 포맷 문자열 셋 · 주석).
2. 호스트 검사. `input_test` OK 16 → 20, `all checks passed` 넷과 `PASS` 다섯 그대로. `init`의 `zig build test`는 `PASS` 둘.
3. hangul 체인(구현자의 판, 캐시 삭제 포함) 2분 52초, `HI check PASS`. 새 검사 21~24의 PASS 줄 넷이 전부 찍혔다.
   regression은 `render` 108초 · `copy` 171초 · `config` 약 162초(총 시간에서 역산), 셋 다 PASS.
4. mutation 다섯 판이 전부 확정 6의 표와 같은 검사에서 같은 메시지로 빨갰다 — 1은 호스트 검사 74와(호스트 검사를 건너뛴
   체인에서는) 검사 23, 2는 호스트 검사 72, 3 · 4는 체인 검사 0. 로그는 `/tmp/run/el0/impl/mut/`.
5. 루트 게이트 19체인 2/2, 50분 58초(`/tmp/gate_el0.log`). PD-M4의 49분 56초에 62초를 더했다 — 확정 8이 "30초 남짓 × 2"로
   본 것과 맞는다. `HI check PASS` 둘, `FAIL` · `Killed` 0줄. 두 회차 모두 검사 0의
   `three toggle keys came from the config file; hangul_key is off; esc_latin is on by default`와 검사 21~24의 PASS 줄이
   찍혔다.
6. Task 0의 편집 전 기준값(16/4/5/2)은 구현자가 안 쟀다 — 컨테이너 lock을 기다리는 동안 편집을 먼저 넣었다. 확정 11의
   사본 값으로 대신한다. 편집 뒤의 값은 2와 같다.
7. 구현자는 다른 서브에이전트(CB planner)와 컨테이너 lock(`/tmp/run/docker.lock`)을 번갈아 쥐었고 `Killed`는 한 번도
   안 났다. 컨테이너를 하나씩만 돌리는 규칙이 lock 디렉터리 하나로 지켜졌다.
