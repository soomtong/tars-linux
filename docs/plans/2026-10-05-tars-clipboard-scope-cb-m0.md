# CB-M0 — 클립보드를 화면 밖으로 내고, `tars.conf`의 범위로 고른다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-clipboard-scope-design.md`
Status: 끝났다(2026-10-05). 실측은 맨 아래 "CB-M0이 실측한 것" 절에 있다. 이것으로 CB가 닫혔다.

## 누가 무엇을 하나

design 결정 6. Task 0~6은 구현 서브에이전트(Opus)가 main 작업 트리에서 직접 편집한다. Task 7(루트 게이트 2회 · 실측 절 ·
commit · 닫기)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령
출력을 그대로 보고한다. mutation(Task 6)도 구현자가 돌린다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/cb0/repo/`)에 먼저 넣어 컴파일 · 호스트 검사 · 체인 · regression · mutation까지
돌렸고, 아래의 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/cb0/render.py`). 기준은 HEAD `dfd761a`의
파일(`/tmp/run/cb0/base/`, 확정 1)이고 편집 뒤의 파일은 `/tmp/run/cb0/new/`다. 새 파일 둘은 전문을 적었다. 구현자는 코드를 새로 짓지
않는다. 편집은 Edit 도구에 글자 그대로 넣고, 각 Task 끝에서 `new/`와 `diff`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의
글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/clipboard.zig` | 새 파일 — `Scope` · `Clipboard` · `pick` | +87 |
| `terminal/src/clipboard_test.zig` | 새 파일 — 검사 다섯과 누수 판정 | +83 |
| `terminal/build.zig` | 편집 둘 — `clipboard_test` 산출물과 test step | +14 |
| `terminal/src/vt.zig` | 편집 열 — `clip` 칸 · `clipboard()`를 지우고 `copyYank(clip)` · `findPaste(clip)` | +24 −39 |
| `terminal/src/vt_test.zig` | 편집 스물여덟 — 화면마다 칸 하나, 새 시그니처 | +47 −26 |
| `terminal/src/main.zig` | 편집 열여섯 — `Pane.clip` · `Clips` · 범위 읽기 · `clipboard scope=` 줄 · 네 자리 | +80 −15 |
| `init/src/config.zig` | 편집 다섯 — `ClipboardScope` · 필드 · `parse` · seed 네 줄 | +39 |
| `init/src/config_test.zig` | 편집 다섯 — `expect`의 열한째 필드와 CB-M0 검사 | +27 −2 |
| `init/src/main.zig` | 편집 일곱 — `[9:null]` · config 줄 · 아홉째 칸 · 리터럴 둘 | +15 −9 |
| `init/src/clock.zig` · `net.zig` · `wifi.zig` | 하나씩 — `[9:null]`과 `null` 하나 | +5 −5 |
| `pane/check.sh` | 편집 열 — 머리 주석 · 표식 · 포트 · 도구 넷 · 검사 10~12 · 부팅 B와 검사 13~15 | +275 −3 |
| `check.sh` | 편집 둘 — 체인 설명 문단과 `CHAINS`의 `"WP-M2:…"` → `"CB-M0:…"` | +6 −1 |

`terminal/src/input.zig` · `layout.zig` · `pointer.zig` · 커널 · initrd 목록은 안 고친다. `copy` · `hangul` · `pointer` 체인의
`clip>` 판정도 안 고친다 — 로그 문구가 그대로다(design 결정 5).

`docs/guides/lessons.md` · design의 `Status:` · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · CM · WP design의
덧붙임은 구현자가 안 고친다. lead가 Task 7에서 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/cb0/impl/` 아래에 둔다.
`/tmp/run/cb0/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽는다(PD-M1 plan 확정 11). 컨테이너는
언제나 하나씩 돌린다.

## 이 milestone이 끝나면

- 클립보드가 `vt.Screen` 밖에 산다. `terminal/src/clipboard.zig`의 `Clipboard`가 문자열 하나를 소유하고, `main.zig`가 공유 칸
  하나(`Clips.shared`)와 패널마다의 칸(`Pane.clip`)을 든다.
- `tars.conf`에 `clipboard=` 키가 생긴다. 값은 `shared`(기본) · `pane`이다. 모르는 값은 로그 한 줄을 찍고 `shared`에 머문다.
  첫 부팅의 seed 파일 끝에 네 줄(주석 셋 · 값 하나)이 더해진다.
- `shared`면 한 패널에서 `y`(또는 포인터 끌기)로 잡은 글자를 다른 패널 · 다른 워크스페이스에서 `Cmd+V`로 붙인다. copy mode
  검색창의 `Cmd+V`(FP)도 같은 칸을 본다. `pane`이면 CB 전과 같다.
- init이 범위를 terminal argv의 아홉째 칸으로 넘긴다. `Child.argv`가 `[9:null]`이 된다.
- `pane/check.sh`에 검사 10~15와 부팅 B(설정 디스크 `clipboard=pane`)가 더해진다. 체인 수는 그대로이고 그 체인의 부팅이
  하나에서 둘이 된다. 호스트 검사 실행 파일이 하나 는다(`clipboard_test`).

로그 줄(정본 — 코드와 `pane/check.sh`가 이 글자를 쓴다). 새 줄은 하나이고 init 줄은 끝에 필드 하나가 붙는다.

```
tars-init: config shell=fish keyboard=apple … firewall=off clipboard=shared
terminal: clipboard scope=shared
tars-init: unknown clipboard 'workspace', falling back to shared
```

`clip>` · `find> paste` 줄은 글자 하나 안 바뀐다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 코드를 읽어 정했고, 저장소 사본(`/tmp/run/cb0/repo/`)에서 쟀다. 저장소의 작업 트리는 design 파일과
이 plan 말고는 한 글자도 안 바꿨다.

1. 기준 트리. 이 plan의 편집은 HEAD `dfd761a`(EL-M0)의 파일에 맞춰 다시 뽑았다. 처음에는 `5acc735`에 맞춰 뽑았고 사본의 컴파일 ·
   호스트 검사 · 체인 · regression · mutation은 그 판에서 돌았다. EL-M0이 commit된 뒤 사본의 `base/`를 `git archive dfd761a`로
   바꾸고 편집 스크립트(`/tmp/run/cb0/edit/e_*.py`)를 다시 돌렸다. EL과 글자가 겹친 자리는 셋이고 손으로 맞췄다.
   - `tars-init: config` 줄 — `esc_latin={s}` 뒤에 `clipboard={s}`, 값 목록도 `@tagName(cfg.esc_latin)` 뒤.
   - terminal argv — 여덟째 칸이 `terminal_toggle_arg.ptr`이 됐고 그 뒤에 `clipboard_arg.ptr`.
   - `config_test`의 `expect` — `got.esc_latin == want.esc_latin` 뒤에 열두째 필드, 실패 줄의 두 형식 문자열과 값 목록은
     `esc_latin` 뒤에 `clipboard`.
   그 밖에 자리만 옮긴 것이 셋이다. `ClipboardScope`는 `EscLatin` 뒤에, `Config.clipboard`는 `esc_latin` 필드 뒤에, `parse`의
   갈래는 `esc_latin` 갈래 뒤에 선다. 의미가 부딪치는 자리는 없다 — EL은 argv 칸을 안 늘리고 여덟째 칸의 내용을 바꿨고,
   CB는 아홉째 칸을 더한다. `dfd761a`의 판은 planner가 컨테이너에서 다시 컴파일하지 않았다(그 시간에 루트 게이트가 돌았다).
   컴파일과 체인은 구현자의 Task 1~5가 처음 본다. 겹친 셋의 판은 `5acc735`의 판과 글자가 그 자리만 다르다.
2. 칸의 모양(design 결정 1). `Clipboard{ alloc, buf: ?[:0]const u8 }`과 `init` · `set` · `text` · `deinit`. `deinit`은 값으로
   받는다 — `main.zig`의 정리 `defer`가 패널을 값으로 훑기(`for (w.panes) |maybe|`) 때문이다. `copyYank(clip: *Clipboard)`는
   선택 문자열을 `clip.alloc`으로 만들어 `clip.set`에 넘긴다. `findPaste(clip: ?[]const u8)`. `Screen.clipboard()`와
   `Screen.clip`은 지운다.

3. 네 자리를 지나는 길. `main.zig`의 `Clips`에 `of` · `yank` · `paste`. `y`는 `clips.yank(focus)`, 포인터 뗌은
   `self.clips.yank(p)`(`PointerWire`에 `clips: *Clips` 칸), `Cmd+V`는 `clips.paste(focus)`이고 그 안에서 검색창 · 셸이 갈린다.
   칸을 고르는 판단은 `of`의 `clipboard.pick` 한 줄이다. `.paste` 위의 긴 주석은 남기고 "여기서 갈린다"만 "`Clips.paste`에서
   갈린다"로 고쳤다.

4. `vt_test`. `copyYank`를 부르는 화면마다 칸을 하나 둔다(`cm_clip` · `wm_clip` · `pm_clip` · `pd_kb_clip` · `pd_pt_clip` ·
   `pd_sc_clip`). 검사 97은 두 화면의 글자를 함께 들고 비교하므로 칸이 둘이어야 한다 — 한 칸이면 둘째 `y`가 첫째 글자를
   해제한다. 검사 10의 대조군은 "선택 없는 `y`가 새 칸을 안 채운다"(`never`)로, 검사 55는 `findPaste(null)`로 바뀐다.
   `vt_test`의 OK 줄 수는 그대로다(확정 11).

5. argv. `Child.argv`와 같은 타입을 쓰는 자리가 여섯이다 — `Child.argv` 선언 · terminal 리터럴 · 콘솔 셸 리터럴 · 서비스
   리터럴(`init/src/main.zig`)과 `clock.CHRONYD_ARGV` · `net.DHCPCD_ARGV` · `wifi.WIFI_ARGV`. 배열 리터럴의 길이가 타입과
   다르면 컴파일 에러라 빠뜨리면 빌드가 막힌다. terminal은 `args.len > 8`일 때 `args[8]`을 읽고 `stringToEnum`으로 되돌린다.
   없거나 모르는 값이면 `shared`다(손으로 띄울 때).

6. seed. `config.save`의 출력이 44줄(EL-M0이 40줄에서 넷을 더했다)에서 48줄이 된다. `config` 체인 1차 부팅의 `tars-config`가
   그 파일 전체를 47줄 화면에 찍고 `| shell_config=on`을 찾는다. 명령줄 · 48줄 · 프롬프트라 위의 셋이 화면 밖으로 밀리지만
   `shell_config=on`은 25번째 줄이라 남는다. `5acc735` 판(44줄)으로는 regression에서 통과했다(확정 9). 48줄 판은 Task 5-2가
   처음 본다.

7. 게이트(design 결정 4). 검사 10~12는 부팅 A, 13~15는 부팅 B다. 새 도구 넷 — `clip_count` · `wait_for_clip` ·
   `wait_for_last_screen` · `yank_line_above_prompt`. 부팅 B의 디스크는 `mkfs.ext2 -d`로 `out/cb-pane.img`에 굽고 monitor는
   45490이다. 검사 11은 4c 뒤 · 5 앞(포커스가 오른쪽에 돌아온 채로 끝난다 — 5 · 6이 오른쪽 패널을 가른다는 전제를 지킨다),
   12의 잡기는 7b 뒤, 붙이기는 8 뒤다(8a가 둘째 워크스페이스의 `ws-two`를 그대로 본다).

8. 부팅 B의 NUL 검사는 NUL을 한 번의 읽기로 센다(`tr -cd '\000' < "$LOG" | wc -c`). 처음에 부팅 A의 모양(크기 두 번)을
   따랐다가 한 판 거짓으로 빨갰다 — 마지막 Enter 직후라 두 읽기 사이에 게스트가 프레임 덤프를 썼다. 그 판의 로그에 NUL은
   0이었다(design 실측 10).

9. 체인과 regression(사본, 같은 컨테이너 이미지). 시간은 그 판의 `docker run` 하나를 감싼 값이다.

   | 체인 | 결과 | 시간 |
   |---|---|---|
   | `pane`(HEAD 판, 따뜻한 캐시) | `WP-M2 check PASS` | 33초 |
   | `pane`(이 plan, 따뜻한 캐시, 세 판) | `CB-M0 check PASS` | 44 · 43 · 43초 |
   | `copy` | `CM-M2 check PASS` | 2분 52초 |
   | `hangul` | `HI check PASS` | 1분 4초 |
   | `config` | `PASS`(seed 44줄의 `tars-config` 포함) | 2분 42초 |
   | `pointer` | `PD-M4 check PASS` | 1분 14초 |
   | `tools` | `PASS` | 59초 |
   | `net` | `PASS` | 2분 52초 |
   | `service` | `SV chain PASS` | 1분 23초 |
   | `wifi` | `WL-M3 PASS` | 1분 43초 |
   | `firewall` | `FW chain PASS` | 49초 |
   | `input` | `PASS` | 42초 |
   | `power` | `PM-M1 PASS` | 52초 |

   `tars-init: config` 줄을 보는 체인 가운데 `machine`(UEFI 부팅이라 느리다)을 뺀 전부와, 클립보드를 보는 체인(`copy` ·
   `hangul` · `pointer`), 감독 목록의 argv를 쓰는 체인(`net` · `service` · `wifi`)을 함께 돌렸다. `machine` · `install` · `nic` · `render` · `terminal` · `device` · `boot`는 안 돌렸다 — 루트 게이트가
   본다.

10. mutation 넷(Task 6). 셋은 배선이라 호스트 검사를 지나 체인이 잡고, 하나는 칸 자체라 `clipboard_test`가 잡는다.

    | mutation | 바꾸는 줄 | 잡은 자리 | `FAIL` 줄 | 시간 |
    |---|---|---|---|---|
    | 1 범위를 무시하고 늘 패널 칸(CB 전의 동작) | `main.zig`의 `Clips.of` — `pick(self.scope, …)` → `pick(.pane, …)` | 검사 11 | `Cmd+V in the left pane did not write the 12 bytes the right pane yanked (paste empty 0 -> 1)` | 2분 9초 |
    | 2 범위를 무시하고 늘 공유 칸 | 같은 줄 — `pick(.shared, …)` | 검사 14 | `boot B: Cmd+V in the left pane did not report an empty clipboard (paste len= 0 -> 1)` | 2분 31초 |
    | 3 init이 argv에 늘 기본값을 넣는다 | `init/src/main.zig` — `cfg.clipboard.arg()` → `config.ClipboardScope.shared.arg()` | 검사 13 | `boot B: init read clipboard=pane but terminal says 'terminal: clipboard scope=shared'` | 2분 9초 |
    | H1 `set`이 옛것을 안 해제한다 | `clipboard.zig` — `\|old\| self.alloc.free(old);` → `\|old\| _ = old;` | `clipboard_test`(부팅 전) | `FAIL: the clipboards leaked` | 19초 |

    시간은 캐시를 지운 빌드를 포함한다. 1은 CB 전의 동작을 재현한 것이기도 하다 — 같은 워크스페이스의 다른 패널에서 `Cmd+V`가
    `clip> paste empty`를 찍는다(design 실측 1). 3은 검사 10(부팅 A의 `shared`)을 지난다 — 기본값이 우연히 맞기 때문이고, 그래서
    부팅 B가 기본값과 다른 값을 심는다(design 결정 4의 규율 4). H1에서 `vt_test`도 `DebugAllocator`의 누수 줄(`error(DebugAllocator):
    memory address … leaked`)을 찍는다 — `init.gpa`가 같은 할당자다. 판정은 `clipboard_test`의 `FAIL` 줄이다.

11. 호스트 검사의 수(HEAD → 이 plan). `vt_test` OK 82 → 82(검사를 고쳤지 더하지 않았다), `clipboard_test` OK 0 → 7(둘은 값에
    개행이 있어 `OK`가 다음 줄에 붙는다 — 그래서 열이 아니라 일곱이다), `all checks passed`와 `PASS` 합 9 → 10. init의
    `zig build test`에서 `unknown clipboard` 줄이 0 → 2다. `config_test`의 검사 줄 수는 `PASS` 하나라 따로 안 센다.

12. 앵커. 편집 여든여덟의 `old_string`이 HEAD `dfd761a`의 작업 트리에 정확히 한 번씩 있고(`python3 /tmp/run/cb0/anchors.py pre
    /Users/dp/Repository/tars-linux` → `pre: 88 edits, 0 bad`), `new_string`이 `new/`에 정확히 한 번씩 있다(`post: 88 edits,
    0 bad`). `5acc735` 판의 사본은 `/tmp/run/cb0/base_5acc735/` · `new_5acc735/`에 남겨 두었다.

13. 흔들림 하나. 시간을 재려고 사본의 파일을 HEAD 판과 이 plan의 판으로 번갈아 바꿔 넣는 동안, 바꾼 직후의 한 판이
    `FAIL: init build failed`로 3초 만에 끝났다. 같은 순서를 두 번 다시 해서는 안 나왔다. 호스트에서 파일을 바꾼 직후 컨테이너가
    옛 내용을 본 것으로 보고(lessons "캐시는 컨테이너 안에서 지운다"와 같은 종류), 코드와 무관하다. 구현자는 파일을 번갈아
    바꾸지 않으므로 이 자리를 지나지 않는다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: `git status`는 이 plan과 design이 commit 전이면 그 둘뿐이고, lead가 고치는 중일 수 있는 `HANDOFF.md`가 더 있을 수
   있다. `M`으로 시작하는 소스 파일이 있으면 멈추고 보고한다(확정 1).

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 12).

   ```bash
   python3 /tmp/run/cb0/anchors.py pre "$PWD"
   ```

   기대: `pre: 88 edits, 0 bad`. 하나라도 `bad`면 그 줄을 보고하고 멈춘다. 앵커는 EL-M0 뒤의 HEAD `dfd761a`에 맞춰 다시
   뽑았다(확정 1). 그 뒤에 이 plan의 파일을 고친 commit이 또 들어왔으면 여기서 빨갛고, 그때 lead가 같은 절차로 다시 뽑는다 —
   `base/`를 새 HEAD로 바꾸고, `edit/e_*.py`를 다시 돌려 `new/`를 만들고, 겹친 자리를 손으로 맞춘 뒤 `render.py`로 이 plan의
   블록과 `anchors.json`을 다시 뽑는다.

4. 호스트 검사의 지금 값을 본다.

   ```bash
   mkdir -p /tmp/run/cb0/impl
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
     (cd terminal && zig build test > /tmp/t.out 2>&1); echo "terminal exit=$?"
     grep -a -c "^vt_test: .* OK$" /tmp/t.out
     grep -a -c "^clipboard_test: .* OK$" /tmp/t.out
     grep -a -E -c "all checks passed|^PASS$" /tmp/t.out
     (cd init && zig build test > /tmp/i.out 2>&1); echo "init exit=$?"
     grep -a -c "unknown clipboard" /tmp/i.out'
   ```

   기대: `terminal exit=0`, `vt_test` OK 82, `clipboard_test` OK 0, `all checks passed` · `PASS` 합 9,
   `init exit=0`, `unknown clipboard` 0.

## Task 1: `clipboard.zig` · `clipboard_test.zig` · `build.zig` — 칸과 그 검사

design 결정 1의 순수 층이다. 아직 아무도 이 파일을 import하지 않으므로 이 Task만으로 빌드가 그대로 지난다.

### 1-1. `terminal/src/clipboard.zig` — 새 파일

Write 도구로 이 글자 그대로 만든다.

```zig
//! 클립보드와 그 범위(CB design 결정 1 · 2).
//!
//! 순수 모듈이다. 시스템 콜도 ghostty도 모른다 — `layout.zig` · `status.zig`가
//! 따로 서는 이유와 같다. 그래서 `clipboard_test`가 컨테이너에서 초 단위로
//! 돌고, 소유권(옛것을 해제한다 · 빈 것은 null이다)과 범위 고르기를 부팅
//! 없이 본다.
//!
//! CB 전에는 클립보드가 `vt.Screen`의 칸 하나(`clip`)였다. CM design 결정 1이
//! 그렇게 정했을 때는 화면이 하나였고, WP가 패널마다 `Screen`을 하나씩 두면서
//! 클립보드도 패널 수만큼 생겼다. 그것을 밖으로 낸 것이 이 파일이다 —
//! 선택을 문자열로 만드는 일은 여전히 `vt.zig`(`copyYank`)이고, 그 문자열을
//! 누가 갖는지가 여기다.

const std = @import("std");

/// 클립보드를 누구와 나누는가(CB design 결정 2). `tars.conf`의
/// `clipboard=` 값이고, init이 argv의 아홉째 칸으로 넘긴다.
///
/// 이름이 `init/src/config.zig`의 `ClipboardScope`와 짝이어야 한다. 둘을
/// 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다 — 자판 이름
/// (`HangulLayout` ↔ `hangul.Layout`)과 같은 자리다. 어긋나면 증상은 "설정을
/// 적었는데 기본값으로 뜬다"이고, 부팅 로그의 `terminal: clipboard scope=`
/// 줄이 그것을 보인다.
pub const Scope = enum {
    /// 모든 패널과 모든 워크스페이스가 하나를 쓴다. 기본값이다.
    shared,
    /// 패널마다 하나다. CB 전의 동작과 같다.
    pane,
};

/// 문자열 하나를 소유하는 칸.
///
/// `set`이 옛것을 해제하고 새것을 받는다. 그래서 문자열은 다음 `set`까지만
/// 유효하다 — `text()`가 돌려준 슬라이스를 `set` 뒤에 쓰면 해제된 메모리다.
/// `main.zig`는 `y` 한 번에 `copyYank` → `dumpClip`으로 바로 찍고 버리므로
/// 그 사이에 `set`이 끼지 않는다.
pub const Clipboard = struct {
    /// 문자열을 할당하고 해제하는 쪽. `copyYank`가 이것으로 선택 문자열을
    /// 만든다 — 할당한 쪽과 해제하는 쪽이 같은 할당자여야 하기 때문이다.
    alloc: std.mem.Allocator,
    /// sentinel이 있는 것은 라이브러리의 `selectionString`이 그렇게 주기
    /// 때문이다. 밖에는 `text()`가 sentinel을 뗀 슬라이스로 낸다.
    buf: ?[:0]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) Clipboard {
        return .{ .alloc = alloc };
    }

    /// `owned`를 받는다. `owned`는 `self.alloc`으로 할당한 것이어야 한다.
    /// 옛것이 있으면 해제한다.
    pub fn set(self: *Clipboard, owned: [:0]const u8) void {
        if (self.buf) |old| self.alloc.free(old);
        self.buf = owned;
    }

    /// 지금 내용. 한 번도 `set`하지 않았으면 null이다.
    ///
    /// 반환 타입이 `?[]const u8`인 이유는 CB 전의 `Screen.clipboard()`와
    /// 같다 — sentinel을 밖으로 내보내면 호출부가 그것을 직접 free해도 되는
    /// 값으로 오해할 여지가 생긴다. 먼저 풀고 나서 돌려주는 것도 같은
    /// 이유다(optional 껍질째로는 sentinel을 떼는 coercion이 안 된다).
    pub fn text(self: *const Clipboard) ?[]const u8 {
        const t = self.buf orelse return null;
        return t;
    }

    /// 값으로 받는다. `main.zig`의 정리 `defer`가 패널을 값으로 훑으므로
    /// (`for (w.panes) |maybe|`) 포인터를 요구하면 그 자리에서 부를 수 없다.
    /// 해제한 뒤의 칸은 다시 쓰지 않는다 — 패널을 닫는 자리는 바로 뒤에 그
    /// 칸을 null로 지운다.
    pub fn deinit(self: Clipboard) void {
        if (self.buf) |t| self.alloc.free(t);
    }
};

/// 범위가 고르는 칸(CB design 결정 2). `shared`면 공유 칸, `pane`이면 그
/// 패널의 칸이다.
///
/// `main.zig`의 네 자리(`y` · 포인터 뗌 · `Cmd+V` · 검색창의 `Cmd+V`)가
/// 전부 이것을 지난다. 판단이 여기 한 줄이라 `clipboard_test`가 부팅 전에
/// 본다.
pub fn pick(scope: Scope, shared: *Clipboard, own: *Clipboard) *Clipboard {
    return switch (scope) {
        .shared => shared,
        .pane => own,
    };
}
```

### 1-2. `terminal/src/clipboard_test.zig` — 새 파일

검사 다섯과 누수 판정이다. 누수는 `DebugAllocator`의 `deinit()`이 본다 — `set`이 옛것을 안 해제하면 `.leak`이다(mutation
H1).

```zig
const std = @import("std");
const clipboard = @import("clipboard.zig");

const Clipboard = clipboard.Clipboard;

/// `alloc`으로 `s`의 사본을 만든다. `copyYank`가 `selectionString`으로 하는
/// 일과 같은 모양 — 할당자가 준 sentinel 슬라이스다.
fn dup(alloc: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    return try alloc.dupeZ(u8, s);
}

fn expectText(what: []const u8, got: ?[]const u8, want: ?[]const u8) !void {
    const same = if (got == null or want == null) got == null and want == null else std.mem.eql(u8, got.?, want.?);
    if (same) {
        std.debug.print("clipboard_test: {s} = {?s} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = {?s}, want {?s}\n", .{ what, got, want });
    return error.WrongClipText;
}

fn expectPick(what: []const u8, got: *Clipboard, want: *Clipboard) !void {
    if (got == want) {
        std.debug.print("clipboard_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s} picked the other clipboard\n", .{what});
    return error.WrongPick;
}

pub fn main() !void {
    // 누수를 이 할당자가 센다. `set`이 옛것을 안 해제하거나 `deinit`이
    // 남기면 맨 끝의 `deinit()`이 `.leak`을 돌려준다 — 검사 2 · 5가 보는
    // 것이 그 하나다.
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();

    // 검사 1. 새 칸은 비었다. 대조군이다 — 이것이 없으면 아래 검사들이
    // "언제나 무언가를 준다"도 통과한다.
    var a = Clipboard.init(alloc);
    try expectText("a fresh clipboard", a.text(), null);

    // 검사 2. `set`한 것이 그대로 나오고, 다음 `set`이 옛것을 바꾼다.
    // 옛것의 해제는 맨 끝의 누수 판정이 본다.
    a.set(try dup(alloc, "echo cb-pane"));
    try expectText("after one set", a.text(), "echo cb-pane");
    a.set(try dup(alloc, "가나\n다라"));
    try expectText("after a second set", a.text(), "가나\n다라");

    // 검사 3. 범위가 칸을 고른다. `shared`면 공유 칸, `pane`이면 그 패널의
    // 칸이다. 칸 둘의 주소로 본다 — 내용으로 보면 둘이 우연히 같을 때 못
    // 가른다.
    var own = Clipboard.init(alloc);
    try expectPick("shared picks the shared clipboard", clipboard.pick(.shared, &a, &own), &a);
    try expectPick("pane picks the pane's own clipboard", clipboard.pick(.pane, &a, &own), &own);

    // 검사 4. 패널 칸에 넣은 것은 공유 칸에 안 보인다. `main.zig`가 패널마다
    // 칸을 하나씩 들고 `pick`으로 고른다는 모양이 이 성질 위에 서 있다.
    clipboard.pick(.pane, &a, &own).set(try dup(alloc, "only here"));
    try expectText("the pane's own clipboard", own.text(), "only here");
    try expectText("the shared clipboard after a pane set", a.text(), "가나\n다라");

    // 검사 5. 범위 이름이 `tars.conf`의 값과 같다. init이 argv로 보낸 글자를
    // `main.zig`가 `stringToEnum`으로 되돌리므로, 이름이 바뀌면 설정이 조용히
    // 기본값으로 떨어진다.
    if (std.meta.stringToEnum(clipboard.Scope, "shared") != .shared or
        std.meta.stringToEnum(clipboard.Scope, "pane") != .pane or
        std.meta.stringToEnum(clipboard.Scope, "workspace") != null)
    {
        std.debug.print("FAIL: the scope names are not exactly shared and pane\n", .{});
        return error.WrongScopeNames;
    }
    std.debug.print("clipboard_test: scope names shared · pane OK\n", .{});

    a.deinit();
    own.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("FAIL: the clipboards leaked\n", .{});
        return error.Leak;
    }
    std.debug.print("clipboard_test: no leak OK\n", .{});
    std.debug.print("clipboard_test: all checks passed\n", .{});
}
```

### 1-3. `terminal/build.zig` — 편집 둘

E1 — `old_string`(기준 파일 317줄부터):

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

`new_string`:

```zig
    // clipboard_test도 호스트에서 돈다(CB-M0). `layout_test`와 같은 자리다 —
    // 문자열 하나를 소유하는 칸과 범위 고르기라 libc도 번역도 필요 없다.
    const clipboard_test_mod = b.createModule(.{
        .root_source_file = b.path("src/clipboard_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const clipboard_test = b.addExecutable(.{
        .name = "clipboard_test",
        .root_module = clipboard_test_mod,
    });
    b.installArtifact(clipboard_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

E2 — `old_string`(기준 파일 333줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(touchpad_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(touchpad_test).step);
    test_step.dependOn(&b.addRunArtifact(clipboard_test).step);
```

### 1-4. 확인

```bash
for f in clipboard clipboard_test; do diff terminal/src/$f.zig /tmp/run/cb0/new/terminal/src/$f.zig && echo SAME-$f; done
diff terminal/build.zig /tmp/run/cb0/new/terminal/build.zig && echo SAME-build
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a "^clipboard_test:" /tmp/t.out
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대: `SAME-` 셋, `exit=0`. 가운데 `grep`은 이렇다(셋째와 일곱째 값은 개행이 든 글자라 다음 줄에 `다라 OK`가 이어진다 —
`grep`이 그 줄을 안 보여 준다).

```
clipboard_test: a fresh clipboard = null OK
clipboard_test: after one set = echo cb-pane OK
clipboard_test: after a second set = 가나
clipboard_test: shared picks the shared clipboard OK
clipboard_test: pane picks the pane's own clipboard OK
clipboard_test: the pane's own clipboard = only here OK
clipboard_test: the shared clipboard after a pane set = 가나
clipboard_test: scope names shared · pane OK
clipboard_test: no leak OK
clipboard_test: all checks passed
```

마지막 `grep`은 0줄이다.

## Task 2: `vt.zig` · `vt_test.zig` · `main.zig` — 칸을 밖으로 내고 네 자리를 잇는다

셋을 한 Task로 묶는 이유는 `copyYank` · `findPaste`의 시그니처가 바뀌어서다. `vt.zig`만 고치면 `main.zig`와 `vt_test.zig`가
컴파일되지 않는다. 셋을 다 넣은 뒤에 확인한다.

### 2-1. `vt.zig` — 편집 열

E1이 import, E2가 `clip` 칸을 지우고, E3 · E6 · E7 · E10이 주석의 `clipboard` 언급, E4가 `deinit`의 해제, E5가 `findPaste`,
E8 · E9가 `copyYank`와 `clipboard()`다.

E1 — `old_string`(기준 파일 3줄부터):

```zig
const png = @import("png.zig");
```

`new_string`:

```zig
const png = @import("png.zig");
const clipboard = @import("clipboard.zig");
```

E2 — `old_string`(기준 파일 290줄부터):

```zig
    /// 클립보드. `y`가 만든 문자열을 소유한다.
    ///
    /// 프로세스 하나가 디스플레이를 독점하는 구조(TF design 결정 1)에서는
    /// 버퍼 하나로 충분하다(`project_copy_mode`). 다음 `y`가 옛것을 해제한다.
    clip: ?[:0]const u8 = null,

    /// 검색 프롬프트가 열려 있는가.
```

`new_string`:

```zig
    /// 검색 프롬프트가 열려 있는가.
```

E3 — `old_string`(기준 파일 313줄부터):

```zig
    /// 나눠 놓는다. `clip`이 할당을 쓰는 것과 갈리는 자리인데, 그쪽은 길이를
```

`new_string`:

```zig
    /// 나눠 놓는다. 클립보드(`clipboard.zig`)가 할당을 쓰는 것과 갈리는 자리인데, 그쪽은 길이를
```

E4 — `old_string`(기준 파일 553줄부터):

```zig
        const alloc = self.alloc;
        if (self.clip) |text| alloc.free(text);
```

`new_string`:

```zig
        const alloc = self.alloc;
```

E5 — `old_string`(기준 파일 1291줄부터):

```zig
    pub fn findPaste(self: *Screen) usize {
        const text = self.clip orelse return 0;
```

`new_string`:

```zig
    ///
    /// 클립보드를 인자로 받는다(CB design 결정 1). 화면은 클립보드를 갖지
    /// 않는다 — 어느 클립보드인지는 범위에 따라 `main.zig`가 고른다. null이면
    /// 빈 클립보드이고 0을 돌려준다.
    pub fn findPaste(self: *Screen, clip: ?[]const u8) usize {
        const text = clip orelse return 0;
```

E6 — `old_string`(기준 파일 1308줄부터):

```zig
    /// `clipboard`·`copyCursor`·`scrollbar`와 같은 규율이다(design 결정 8).
```

`new_string`:

```zig
    /// `copyCursor`·`scrollbar`와 같은 규율이다(design 결정 8).
```

E7 — `old_string`(기준 파일 1320줄부터):

```zig
    /// `findNeedle`·`clipboard`·`copyCursor`와 같은 규율이다.
```

`new_string`:

```zig
    /// `findNeedle`·`copyCursor`와 같은 규율이다.
```

E8 — `old_string`(기준 파일 1987줄부터):

```zig
    /// `y`. 선택을 클립보드로 옮기고 모드를 나간다.
    ///
    /// 돌려주는 슬라이스는 `self.clip`이 소유한다 — 다음 `y`까지만 유효하다.
    /// 선택이 없으면 null을 돌려주고 클립보드는 그대로 둔다(모드는 나간다).
    pub fn copyYank(self: *Screen) !?[]const u8 {
```

`new_string`:

```zig
    /// `y`. 선택을 `clip`으로 옮기고 모드를 나간다.
    ///
    /// 클립보드는 화면 밖에 산다(CB design 결정 1). CB 전에는 `Screen`의 칸
    /// 하나였고, 패널마다 `Screen`이 따로라 클립보드도 패널마다 따로였다.
    /// 어느 클립보드에 넣을지는 범위에 따라 `main.zig`가 고른다 — 여기는 선택을
    /// 문자열로 만드는 일까지다.
    ///
    /// 문자열은 `clip.alloc`으로 만든다. 해제하는 쪽이 `clip`이므로 할당자가
    /// 같아야 한다. 돌려주는 슬라이스는 `clip`이 소유한다 — 다음 `set`까지만
    /// 유효하다. 선택이 없으면 null을 돌려주고 클립보드는 그대로 둔다(모드는
    /// 나간다).
    pub fn copyYank(self: *Screen, clip: *clipboard.Clipboard) !?[]const u8 {
```

E9 — `old_string`(기준 파일 1997줄부터):

```zig
        const text = try s.selectionString(self.alloc, .{ .sel = sel });
        if (self.clip) |old| self.alloc.free(old);
        self.clip = text;
        // copyExit이 선택을 지우므로 문자열을 먼저 뽑아 둔 뒤에 부른다.
        self.copyExit();
        return text;
    }

    /// 클립보드의 지금 내용. `y`를 한 번도 안 눌렀으면 null이다.
    ///
    /// `main.zig`가 `self.clip`을 직접 읽지 않게 하려고 함수로 낸다 —
    /// `copyCursor`·`scrollbar`와 같은 규율이다(TR design 결정 1).
    ///
    /// 반환 타입이 `?[]const u8`인 것에 뜻이 있다. `clip`은 실제로
    /// `?[:0]const u8`인데, sentinel을 밖으로 내보내면 호출부가 그것을 직접
    /// free해도 되는 값으로 오해할 여지가 생긴다. 소유권은 `Screen`에 있고
    /// 다음 `y`가 옛것을 해제한다.
    ///
    /// `return self.clip;` 한 줄로 줄이지 않는다. 그렇게 쓰면 `?[:0]const u8`을
    /// `?[]const u8`로 바꾸는 일을 optional 껍질을 쓴 채 요구하게 된다.
    /// 먼저 풀고 나서 돌려주면 sentinel을 떼는 평범한 슬라이스 coercion이 되고,
    /// 그 형태는 바로 위 `copyYank`가 이미 쓰고 있는 것이다.
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
```

`new_string`:

```zig
        const text = try s.selectionString(clip.alloc, .{ .sel = sel });
        clip.set(text);
        // copyExit이 선택을 지우므로 문자열을 먼저 뽑아 둔 뒤에 부른다.
        self.copyExit();
```

E10 — `old_string`(기준 파일 2037줄부터):

```zig
    /// `clipboard`·`findNeedle`과 같은 규율이다(TR design 결정 1). 판단과
```

`new_string`:

```zig
    /// `findNeedle`과 같은 규율이다(TR design 결정 1). 판단과
```

### 2-2. `vt_test.zig` — 편집 스물여덟

화면마다 칸 하나를 두고(확정 4), `copyYank()` · `findPaste()` · `clipboard()`를 새 꼴로 바꾼다. 한 줄짜리가 대부분이다.

E1 — `old_string`(기준 파일 3줄부터):

```zig
const png = @import("png.zig");
```

`new_string`:

```zig
const png = @import("png.zig");
const clipboard = @import("clipboard.zig");
```

E2 — `old_string`(기준 파일 421줄부터):

```zig
    defer cm.deinit();
```

`new_string`:

```zig
    defer cm.deinit();
    // 클립보드는 화면 밖에 산다(CB design 결정 1). 검사마다 화면 하나에 칸
    // 하나를 둔다 — CB 전에 화면이 칸을 하나씩 갖던 것과 같은 모양이다.
    var cm_clip = clipboard.Clipboard.init(init.gpa);
    defer cm_clip.deinit();
```

E3 — `old_string`(기준 파일 482줄부터):

```zig
    const yanked = (try cm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const yanked = (try cm.copyYank(&cm_clip)) orelse return error.NothingYanked;
```

E4 — `old_string`(기준 파일 504줄부터):

```zig
    const backward = (try cm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const backward = (try cm.copyYank(&cm_clip)) orelse return error.NothingYanked;
```

E5 — `old_string`(기준 파일 516줄부터):

```zig
    const whole_line = (try cm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const whole_line = (try cm.copyYank(&cm_clip)) orelse return error.NothingYanked;
```

E6 — `old_string`(기준 파일 528줄부터):

```zig
    if ((try cm.copyYank()) != null) {
```

`new_string`:

```zig
    if ((try cm.copyYank(&cm_clip)) != null) {
```

E7 — `old_string`(기준 파일 578줄부터):

```zig
    // 검사 10. `clipboard()`가 마지막 y의 결과를 그대로 들고 있다.
```

`new_string`:

```zig
    // 검사 10. 클립보드가 마지막 y의 결과를 그대로 들고 있다.
```

E8 — `old_string`(기준 파일 583줄부터):

```zig
    const held = cm.clipboard() orelse {
```

`new_string`:

```zig
    const held = cm_clip.text() orelse {
```

E9 — `old_string`(기준 파일 592줄부터):

```zig
    // 대조군. y를 한 번도 안 부른 화면의 클립보드는 null이다. 이것이 없으면
    // "clipboard()가 언제나 무언가를 준다"도 통과한다.
    if (pruned.clipboard() != null) {
        std.debug.print("FAIL: a screen that never yanked already has a clipboard\n", .{});
```

`new_string`:

```zig
    // 대조군. 선택 없는 y는 빈 클립보드를 채우지 않는다. 이것이 없으면
    // "y가 언제나 무언가를 넣는다"도 통과한다. CB 전에는 y를 한 번도 안 부른
    // 화면을 봤는데, 클립보드가 화면 밖으로 나가서 칸 하나를 새로 만들어 본다.
    var never = clipboard.Clipboard.init(init.gpa);
    defer never.deinit();
    pruned.copyEnter();
    if ((try pruned.copyYank(&never)) != null or never.text() != null) {
        std.debug.print("FAIL: a yank without a selection filled an empty clipboard\n", .{});
```

E10 — `old_string`(기준 파일 616줄부터):

```zig
    defer wm.deinit();
```

`new_string`:

```zig
    defer wm.deinit();
    var wm_clip = clipboard.Clipboard.init(init.gpa);
    defer wm_clip.deinit();
```

E11 — `old_string`(기준 파일 715줄부터):

```zig
    const grabbed = (try wm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const grabbed = (try wm.copyYank(&wm_clip)) orelse return error.NothingYanked;
```

E12 — `old_string`(기준 파일 1778줄부터):

```zig
    // 검사 55. 대조군. `um`은 한 번도 y를 안 눌렀다. 빈 클립보드에
    // 붙여넣기를 하면 0을 돌려주고 needle이 안 자란다.
```

`new_string`:

```zig
    // 검사 55. 대조군. 빈 클립보드(null)를 붙여넣으면 0을 돌려주고 needle이
    // 안 자란다.
```

E13 — `old_string`(기준 파일 1784줄부터):

```zig
    if (um.findPaste() != 0) {
```

`new_string`:

```zig
    if (um.findPaste(null) != 0) {
```

E14 — `old_string`(기준 파일 1800줄부터):

```zig
    defer pm.deinit();
```

`new_string`:

```zig
    defer pm.deinit();
    var pm_clip = clipboard.Clipboard.init(init.gpa);
    defer pm_clip.deinit();
```

E15 — `old_string`(기준 파일 1812줄부터):

```zig
    const one = (try pm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const one = (try pm.copyYank(&pm_clip)) orelse return error.NothingYanked;
```

E16 — `old_string`(기준 파일 1819줄부터):

```zig
    var put = pm.findPaste();
```

`new_string`:

```zig
    var put = pm.findPaste(pm_clip.text());
```

E17 — `old_string`(기준 파일 1835줄부터):

```zig
    pm.findBytes("가");
    put = pm.findPaste();
```

`new_string`:

```zig
    pm.findBytes("가");
    put = pm.findPaste(pm_clip.text());
```

E18 — `old_string`(기준 파일 1866줄부터):

```zig
    const many = (try pm.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const many = (try pm.copyYank(&pm_clip)) orelse return error.NothingYanked;
```

E19 — `old_string`(기준 파일 1879줄부터):

```zig
    pm.findOpen();
    put = pm.findPaste();
```

`new_string`:

```zig
    pm.findOpen();
    put = pm.findPaste(pm_clip.text());
```

E20 — `old_string`(기준 파일 1899줄부터):

```zig
    while (pad2 < 126) : (pad2 += 1) pm.findChar('z');
    put = pm.findPaste();
```

`new_string`:

```zig
    while (pad2 < 126) : (pad2 += 1) pm.findChar('z');
    put = pm.findPaste(pm_clip.text());
```

E21 — `old_string`(기준 파일 2614줄부터):

```zig
    defer pd_pt.deinit();
```

`new_string`:

```zig
    defer pd_pt.deinit();
    // 칸이 둘이다. 아래에서 두 화면의 글자를 함께 들고 비교하므로, 한 칸에
    // 넣으면 둘째 y가 첫째 글자를 해제한다.
    var pd_kb_clip = clipboard.Clipboard.init(init.gpa);
    defer pd_kb_clip.deinit();
    var pd_pt_clip = clipboard.Clipboard.init(init.gpa);
    defer pd_pt_clip.deinit();
```

E22 — `old_string`(기준 파일 2628줄부터):

```zig
    const pd_kb_text = (try pd_kb.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const pd_kb_text = (try pd_kb.copyYank(&pd_kb_clip)) orelse return error.NothingYanked;
```

E23 — `old_string`(기준 파일 2636줄부터):

```zig
    const pd_pt_text = (try pd_pt.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const pd_pt_text = (try pd_pt.copyYank(&pd_pt_clip)) orelse return error.NothingYanked;
```

E24 — `old_string`(기준 파일 2650줄부터):

```zig
    const pd_back = (try pd_pt.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const pd_back = (try pd_pt.copyYank(&pd_pt_clip)) orelse return error.NothingYanked;
```

E25 — `old_string`(기준 파일 2665줄부터):

```zig
    const pd_over = (try pd_pt.copyYank()) orelse {
```

`new_string`:

```zig
    const pd_over = (try pd_pt.copyYank(&pd_pt_clip)) orelse {
```

E26 — `old_string`(기준 파일 2684줄부터):

```zig
    const pd_wide = (try pd_pt.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const pd_wide = (try pd_pt.copyYank(&pd_pt_clip)) orelse return error.NothingYanked;
```

E27 — `old_string`(기준 파일 2699줄부터):

```zig
    defer pd_sc.deinit();
```

`new_string`:

```zig
    defer pd_sc.deinit();
    var pd_sc_clip = clipboard.Clipboard.init(init.gpa);
    defer pd_sc_clip.deinit();
```

E28 — `old_string`(기준 파일 2711줄부터):

```zig
    const pd_long = (try pd_sc.copyYank()) orelse return error.NothingYanked;
```

`new_string`:

```zig
    const pd_long = (try pd_sc.copyYank(&pd_sc_clip)) orelse return error.NothingYanked;
```

### 2-3. `main.zig` — 편집 열여섯

확정 3의 배선이다. 순서대로 넣는다 — import · `dumpPaste` · `dumpFindPaste` · `Pane.clip`과 `Clips` · `spawnPane` · `PointerWire`의
칸 · 포인터 뗌 · 범위 읽기 · `clips` 변수 · 정리 `defer` · `clipboard scope=` 줄 · EOF 경로 · 키 분기의 `y` · `Cmd+V` 주석 ·
`Cmd+V` · `PointerWire` 생성.

E1 — `old_string`(기준 파일 1줄부터):

```zig
const std = @import("std");
```

`new_string`:

```zig
const std = @import("std");
const clipboard = @import("clipboard.zig");
```

E2 — `old_string`(기준 파일 1218줄부터):

```zig
fn dumpPaste(screen: *vt.Screen, master_fd: c_int) void {
    const text = screen.clipboard() orelse {
```

`new_string`:

```zig
///
/// 클립보드는 인자로 받는다(CB design 결정 1). 어느 칸인지는 `Clips.of`가
/// 범위에 따라 고르고, 여기는 받은 글자를 쓰기만 한다. 그래서 `clip> paste
/// empty`는 "고른 칸이 비었다"다 — `clipboard=pane`에서 다른 패널이 복사한
/// 것은 여기 안 온다.
fn dumpPaste(screen: *vt.Screen, master_fd: c_int, clip: ?[]const u8) void {
    const text = clip orelse {
```

E3 — `old_string`(기준 파일 1249줄부터):

```zig
fn dumpFindPaste(screen: *vt.Screen) void {
    const clip_len = if (screen.clipboard()) |t| t.len else 0;
    const put = screen.findPaste();
```

`new_string`:

```zig
///
/// 클립보드를 인자로 받는 것은 `dumpPaste`와 같다(CB design 결정 1).
fn dumpFindPaste(screen: *vt.Screen, clip: ?[]const u8) void {
    const clip_len = if (clip) |t| t.len else 0;
    const put = screen.findPaste(clip);
```

E4 — `old_string`(기준 파일 1260줄부터):

```zig
    /// 격자 안의 자리(셀 단위). 하나뿐이면 격자 전체다.
    rect: layout.Rect,
```

`new_string`:

```zig
    /// 격자 안의 자리(셀 단위). 하나뿐이면 격자 전체다.
    rect: layout.Rect,
    /// 이 패널만의 클립보드(CB design 결정 1). `clipboard=pane`일 때만 쓰이고,
    /// `shared`면 비어 있다. 패널을 닫는 자리가 `screen`과 함께 해제한다.
    clip: clipboard.Clipboard,
};

/// 클립보드 둘과 그중 무엇을 쓸지(CB design 결정 1 · 2).
///
/// 공유 칸 하나는 여기 있고 패널의 칸은 `Pane.clip`에 있다. 범위는 부팅에
/// argv로 한 번 정해지고 바뀌지 않는다.
///
/// 클립보드를 만지는 네 자리(`y` · 포인터 뗌 · `Cmd+V` · 검색창의 `Cmd+V`)가
/// 전부 이 구조의 `yank` · `paste`를 지난다. 그래서 칸을 고르는 판단이 `of`
/// 한 자리에만 있고, 키보드와 포인터가 다른 칸을 볼 수 없다.
const Clips = struct {
    scope: clipboard.Scope,
    shared: clipboard.Clipboard,

    fn of(self: *Clips, pane: *Pane) *clipboard.Clipboard {
        return clipboard.pick(self.scope, &self.shared, &pane.clip);
    }

    /// `y`와 포인터 뗌. 선택을 고른 칸에 넣고 `clip>` 줄을 찍는다.
    fn yank(self: *Clips, pane: *Pane) !void {
        dumpClip(try pane.screen.copyYank(self.of(pane)));
    }

    /// `Cmd+V`. 목적지가 여기서 갈린다(FP design 결정 3) — 검색 프롬프트가
    /// 열려 있으면 needle에, 아니면 셸에 쓴다. 판단 근거가 `input.State`의
    /// 모드가 아니라 `findNeedle()`인 이유는 키 분기의 `.paste` 주석에 있다.
    fn paste(self: *Clips, pane: *Pane) void {
        const text = self.of(pane).text();
        if (pane.screen.findNeedle() != null)
            dumpFindPaste(pane.screen, text)
        else
            dumpPaste(pane.screen, pane.session.master_fd, text);
    }
```

E5 — `old_string`(기준 파일 1318줄부터):

```zig
    return .{ .screen = screen, .session = session, .rect = rect };
```

`new_string`:

```zig
    return .{ .screen = screen, .session = session, .rect = rect, .clip = .init(alloc) };
```

E6 — `old_string`(기준 파일 1853줄부터):

```zig
    mods: input.State.Modifiers,
```

`new_string`:

```zig
    mods: input.State.Modifiers,
    /// 뗌이 복사할 칸을 고른다(CB design 결정 1). 키보드의 `y`와 같은 길이다.
    clips: *Clips,
```

E7 — `old_string`(기준 파일 2108줄부터):

```zig
                    dumpClip(try p.screen.copyYank());
```

`new_string`:

```zig
                    try self.clips.yank(p);
```

E8 — `old_string`(기준 파일 2220줄부터):

```zig
    // TERM은 지금까지 거짓말을 하고 있었다. 커널의 envp_init이 준
```

`new_string`:

```zig
    // 아홉째가 클립보드의 범위다(CB-M0, design 결정 3). 자판 둘과 같은
    // 모양이다 — init이 `tars.conf`의 화이트리스트를 이미 거쳤으므로 여기
    // 도착하는 값은 언제나 맞고, fallback은 terminal을 손으로 띄울 때를 위한
    // 것이다. 기본값이 `shared`인 것은 사용자가 정했다(2026-10-05).
    const clip_arg: []const u8 = if (args.len > 8) std.mem.span(args[8]) else "shared";
    const clip_scope = std.meta.stringToEnum(clipboard.Scope, clip_arg) orelse .shared;

    // TERM은 지금까지 거짓말을 하고 있었다. 커널의 envp_init이 준
```

E9 — `old_string`(기준 파일 2279줄부터):

```zig
    // 부팅은 패널 하나짜리 워크스페이스 하나다(WP-M0). 패널의 사각형도
```

`new_string`:

```zig
    // 공유 칸은 패널보다 오래 산다 — 마지막 패널이 닫히면 terminal이 끝나므로
    // 프로세스와 같은 수명이다(CB design 비목표 2: terminal이 되살아나면 빈
    // 칸으로 시작한다).
    var clips: Clips = .{ .scope = clip_scope, .shared = .init(allocator) };
    defer clips.shared.deinit();

    // 부팅은 패널 하나짜리 워크스페이스 하나다(WP-M0). 패널의 사각형도
```

E10 — `old_string`(기준 파일 2296줄부터):

```zig
            if (maybe) |pane| pane.screen.deinit();
```

`new_string`:

```zig
            if (maybe) |pane| {
                pane.screen.deinit();
                pane.clip.deinit();
            }
```

E11 — `old_string`(기준 파일 2323줄부터):

```zig
        input.togglesArg(toggles, &toggle_buf),
    });
```

`new_string`:

```zig
        input.togglesArg(toggles, &toggle_buf),
    });
    // 같은 이유의 줄이 클립보드에도 하나 필요하다(CB-M0). `tars-init: config`
    // 줄의 `clipboard=`는 "init이 파일에서 읽었다"를, 이 줄은 "argv를 건너
    // 여기 닿았다"를 말한다. 위 `hangul layout=` 줄과 같은 짝이다.
    std.debug.print("terminal: clipboard scope={s}\n", .{@tagName(clip_scope)});
```

E12 — `old_string`(기준 파일 2541줄부터):

```zig
                    .yank => dumpClip(try focus.screen.copyYank()),
```

`new_string`:

```zig
                    .yank => try clips.yank(focus),
```

E13 — `old_string`(기준 파일 2547줄부터):

```zig
                    // 목적지가 여기서 갈린다(FP design 결정 3). `input.zig`는
                    // `vt.zig`를 import하지 않으므로(IP design 결정 6) 이 갈래는
                    // 여기에만 설 수 있다 — 저쪽은 `Cmd+V`가 눌렸다는 것까지만
```

`new_string`:

```zig
                    // 목적지가 `Clips.paste`에서 갈린다(FP design 결정 3). `input.zig`는
                    // `vt.zig`를 import하지 않으므로(IP design 결정 6) 이 갈래는
                    // 이 파일에만 설 수 있다 — 저쪽은 `Cmd+V`가 눌렸다는 것까지만
```

E14 — `old_string`(기준 파일 2558줄부터):

```zig
                    .paste => if (focus.screen.findNeedle() != null)
                        dumpFindPaste(focus.screen)
                    else
                        dumpPaste(focus.screen, focus.session.master_fd),
```

`new_string`:

```zig
                    .paste => clips.paste(focus),
```

E15 — `old_string`(기준 파일 2770줄부터):

```zig
                .mods = key_state.modifiers(),
```

`new_string`:

```zig
                .mods = key_state.modifiers(),
                .clips = &clips,
```

E16 — `old_string`(기준 파일 2806줄부터):

```zig
                w.panes[ref.leaf] = null;
```

`new_string`:

```zig
                pane.clip.deinit();
                w.panes[ref.leaf] = null;
```

### 2-4. 확인

```bash
for f in vt vt_test main; do diff terminal/src/$f.zig /tmp/run/cb0/new/terminal/src/$f.zig && echo SAME-$f; done
rg -n 'copyYank\(\)|findPaste\(\)|\.clipboard\(\)|self\.clip\b' terminal/src/ || echo NO-OLD-CALLS
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  ./prepare.sh > /tmp/p.out 2>&1; echo "prepare exit=$?"
  zig build test > /tmp/t.out 2>&1; echo "test exit=$?"
  grep -a -c "^vt_test: .* OK$" /tmp/t.out
  grep -a -E "클립보드를 되읽는다|빈 클립보드는 needle|포인터로 고른 선택" /tmp/t.out
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대: `SAME-` 셋, `NO-OLD-CALLS`, `prepare exit=0` · `test exit=0`, `vt_test` OK 82(Task 0과 같다). 가운데 `grep`은 셋이다.

```
vt_test: 클립보드를 되읽는다 OK ('second line')
vt_test: 빈 클립보드는 needle을 안 건드린다 OK
vt_test: 포인터로 고른 선택이 키보드로 고른 것과 같은 글자를 준다 OK
```

마지막 `grep`은 0줄이다.

## Task 3: init — 키 · seed · 로그 · argv 아홉째 칸

### 3-1. `init/src/config.zig` — 편집 다섯

E1이 `ClipboardScope`, E2가 `Config`의 필드, E3이 `parse`의 갈래, E4 · E5가 seed의 네 줄과 그 값이다.

E1 — `old_string`(기준 파일 62줄부터):

```zig
pub const EscLatin = enum {
    on,
    off,
```

`new_string`:

```zig
pub const EscLatin = enum {
    on,
    off,
};

/// terminal의 클립보드를 누구와 나누는가(CB design 결정 2). `shared`면 모든
/// 패널과 워크스페이스가 하나를 쓰고, `pane`이면 패널마다 따로다.
///
/// 기본값이 `shared`인 것은 사용자가 정했다(2026-10-05). `net`·`firewall`과
/// 달리 켜는 비용이 없고, `keyboard`·`hangul_layout`처럼 이 기계를 쓰는
/// 사람이 쓰는 것이 기본값이다.
///
/// 이름이 `terminal/src/clipboard.zig`의 `Scope`와 짝이어야 한다. 둘을 잇는
/// 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다 — `HangulLayout`과 같은
/// 자리이고, 부팅 로그의 `terminal: clipboard scope=` 줄이 그것을 보인다.
pub const ClipboardScope = enum {
    shared,
    pane,

    /// terminal에 argv로 넘길 문자열. `HangulLayout.arg`와 같은 이유로
    /// sentinel이 있는 리터럴을 돌려준다.
    pub fn arg(self: ClipboardScope) [:0]const u8 {
        return switch (self) {
            .shared => "shared",
            .pane => "pane",
        };
    }
```

E2 — `old_string`(기준 파일 929줄부터):

```zig
    esc_latin: EscLatin = .on,
```

`new_string`:

```zig
    esc_latin: EscLatin = .on,
    /// 근거는 위 `ClipboardScope`의 문서 주석에 있다(CB-M0).
    clipboard: ClipboardScope = .shared,
```

E3 — `old_string`(기준 파일 1116줄부터):

```zig
        } else {
```

`new_string`:

```zig
        } else if (std.mem.eql(u8, key, "clipboard")) {
            // firewall · esc_latin과 완전히 같은 모양이다(CB-M0).
            c.clipboard = std.meta.stringToEnum(ClipboardScope, value) orelse {
                std.debug.print("tars-init: unknown clipboard '{s}', falling back to {s}\n", .{
                    value, @tagName(c.clipboard),
                });
                continue;
            };
        } else {
```

E4 — `old_string`(기준 파일 1190줄부터):

```zig
        \\firewall={s}
```

`new_string`:

```zig
        \\firewall={s}
        \\# clipboard: shared | pane
        \\#   shared면 모든 패널과 워크스페이스가 클립보드 하나를 쓰고,
        \\#   pane이면 패널마다 따로다
        \\clipboard={s}
```

E5 — `old_string`(기준 파일 1203줄부터):

```zig
        @tagName(c.firewall),
```

`new_string`:

```zig
        @tagName(c.firewall),
        @tagName(c.clipboard),
```

### 3-2. `init/src/config_test.zig` — 편집 다섯

`expect`가 열한째 필드를 비교하고 실패 줄에 찍고(E1~E4), FW-M1 검사 뒤에 CB-M0 검사가 붙는다(E5).

E1 — `old_string`(기준 파일 102줄부터):

```zig
        got.esc_latin == want.esc_latin and
```

`new_string`:

```zig
        got.esc_latin == want.esc_latin and
        // CB-M0: 열두째 필드. 이 줄이 없으면 아래 clipboard 검사가 아무것도
        // 안 보고 초록이다.
        got.clipboard == want.clipboard and
```

E2 — `old_string`(기준 파일 111줄부터):

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n",
```

`new_string`:

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s} clipboard={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s} clipboard={s}\n",
```

E3 — `old_string`(기준 파일 125줄부터):

```zig
            @tagName(got.esc_latin),
```

`new_string`:

```zig
            @tagName(got.esc_latin),
            @tagName(got.clipboard),
```

E4 — `old_string`(기준 파일 136줄부터):

```zig
            @tagName(want.esc_latin),
```

`new_string`:

```zig
            @tagName(want.esc_latin),
            @tagName(want.clipboard),
```

E5 — `old_string`(기준 파일 1061줄부터):

```zig
    // ── EL-M0: esc_latin ────────────────────────────────────────────────
```

`new_string`:

```zig
    // ── CB-M0: clipboard ───────────────────────────────────────────────
    //
    // firewall과 같은 모양의 enum 키다. 기본값이 shared인 것은 사용자가
    // 정했다(CB design 결정 2). `workspace`는 이름이 없다(CB design 비목표 1).
    try expect("clipboard=pane\n", .{ .clipboard = .pane });
    try expect("clipboard=shared\n", .{});
    try expect("clipboard=workspace\n", .{}); // enum에 없는 값
    try expect("clipboard=\n", .{}); // 값 없음
    // 이름이 argv로 그대로 간다. terminal의 `clipboard.Scope`가 같은 이름을
    // `stringToEnum`으로 되돌리므로, `arg()`가 enum 이름과 다르면 설정이
    // 조용히 기본값으로 떨어진다.
    for (std.enums.values(config.ClipboardScope)) |scope| {
        if (!std.mem.eql(u8, scope.arg(), @tagName(scope))) {
            std.debug.print("FAIL: ClipboardScope.arg gave \"{s}\" for {s}\n", .{ scope.arg(), @tagName(scope) });
            return error.UnexpectedClipboardArg;
        }
    }
    // pane 체인의 부팅 B가 쓰는 줄이다.
    try expect("shell=fish\nclipboard=pane\n", .{ .clipboard = .pane });

    // ── EL-M0: esc_latin ────────────────────────────────────────────────
```

### 3-3. `init/src/main.zig` — 편집 일곱

E1이 `Child.argv`의 타입, E2 · E3이 config 로그 줄, E4 · E5가 terminal의 아홉째 칸, E6 · E7이 콘솔 셸과 서비스의 리터럴이다.

E1 — `old_string`(기준 파일 370줄부터):

```zig
    /// 다섯에서 일곱으로, HI-M3에서 일곱에서 여덟으로 늘었다. terminal이
    /// 받는 넷째가 keyboard, 다섯째가 키보드 장치 경로, 여섯째가 한글 자판,
    /// 일곱째가 영문 자판, 여덟째가 한/영 전환 키 목록이고, 콘솔 셸은 그
    /// 자리를 전부 null로 둔다.
    argv: [8:null]?[*:0]const u8,
```

`new_string`:

```zig
    /// 다섯에서 일곱으로, HI-M3에서 일곱에서 여덟으로, CB-M0에서 여덟에서
    /// 아홉으로 늘었다. terminal이 받는 넷째가 keyboard, 다섯째가 키보드 장치
    /// 경로, 여섯째가 한글 자판, 일곱째가 영문 자판, 여덟째가 한/영 전환 키
    /// 목록, 아홉째가 클립보드 범위이고, 콘솔 셸은 그 자리를 전부 null로 둔다.
    /// 같은 타입을 쓰는 상수가 셋 더 있다(`clock.CHRONYD_ARGV` ·
    /// `net.DHCPCD_ARGV` · `wifi.WIFI_ARGV`). 늘릴 때 함께 늘린다.
    argv: [9:null]?[*:0]const u8,
```

E2 — `old_string`(기준 파일 829줄부터):

```zig
    // 그 뒤에 붙였다.
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s}\n",
```

`new_string`:

```zig
    // 그 뒤에 붙였다. CB-M0의 `clipboard=`는 다시 그 뒤다.
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s} firewall={s} esc_latin={s} clipboard={s}\n",
```

E3 — `old_string`(기준 파일 844줄부터):

```zig
            @tagName(cfg.esc_latin),
```

`new_string`:

```zig
            @tagName(cfg.esc_latin),
            @tagName(cfg.clipboard),
```

E4 — `old_string`(기준 파일 1021줄부터):

```zig
    const latin_arg = cfg.latin_layout.arg();
```

`new_string`:

```zig
    const latin_arg = cfg.latin_layout.arg();
    // 클립보드 범위도 같은 성질이다(CB-M0).
    const clipboard_arg = cfg.clipboard.arg();
```

E5 — `old_string`(기준 파일 1046줄부터):

```zig
            terminal_toggle_arg.ptr,
```

`new_string`:

```zig
            terminal_toggle_arg.ptr,
            clipboard_arg.ptr,
```

E6 — `old_string`(기준 파일 1059줄부터):

```zig
        .argv = .{ shell_path.ptr, console_flag, null, null, null, null, null, null },
```

`new_string`:

```zig
        .argv = .{ shell_path.ptr, console_flag, null, null, null, null, null, null, null },
```

E7 — `old_string`(기준 파일 1100줄부터):

```zig
            .argv = .{ s.path().ptr, null, null, null, null, null, null, null },
```

`new_string`:

```zig
            .argv = .{ s.path().ptr, null, null, null, null, null, null, null, null },
```

### 3-4. `clock.zig` · `net.zig` · `wifi.zig` — 하나씩

E1 — `old_string`(기준 파일 84줄부터):

```zig
pub const CHRONYD_ARGV = [8:null]?[*:0]const u8{
    CHRONYD_PATH.ptr, "-d", "-u", "root", "-f", CONF_PATH.ptr, null, null,
```

`new_string`:

```zig
pub const CHRONYD_ARGV = [9:null]?[*:0]const u8{
    CHRONYD_PATH.ptr, "-d", "-u", "root", "-f", CONF_PATH.ptr, null, null, null,
```

E1 — `old_string`(기준 파일 123줄부터):

```zig
pub const DHCPCD_ARGV = [8:null]?[*:0]const u8{
    DHCPCD_PATH.ptr, "-B", "-j", "/dev/console", "-o", "ntp_servers", null, null,
```

`new_string`:

```zig
pub const DHCPCD_ARGV = [9:null]?[*:0]const u8{
    DHCPCD_PATH.ptr, "-B", "-j", "/dev/console", "-o", "ntp_servers", null, null, null,
```

E1 — `old_string`(기준 파일 24줄부터):

```zig
pub const WIFI_ARGV = [8:null]?[*:0]const u8{ WIFI_PATH.ptr, null, null, null, null, null, null, null };
```

`new_string`:

```zig
pub const WIFI_ARGV = [9:null]?[*:0]const u8{ WIFI_PATH.ptr, null, null, null, null, null, null, null, null };
```

### 3-5. 확인

```bash
for f in config config_test main clock net wifi; do diff init/src/$f.zig /tmp/run/cb0/new/init/src/$f.zig && echo SAME-$f; done
rg -n '\[8:null\]' init/src || echo NO-8-SLOTS
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c '
  zig build > /tmp/b.out 2>&1; echo "build exit=$?"
  zig build test > /tmp/i.out 2>&1; echo "test exit=$?"
  grep -a "clipboard" /tmp/i.out
  grep -a -E "^FAIL|error:" /tmp/b.out /tmp/i.out | head -5'
```

기대: `SAME-` 여섯, `NO-8-SLOTS`, `build exit=0` · `test exit=0`. 가운데 `grep`은 둘이다.

```
tars-init: unknown clipboard 'workspace', falling back to shared
tars-init: unknown clipboard '', falling back to shared
```

마지막 `grep`은 0줄이다.

## Task 4: `pane/check.sh` · `check.sh`

### 4-1. `pane/check.sh` — 편집 열

E1이 머리 주석, E2 · E3이 `report_failure`의 표식과 `clip` 줄, E4가 포트 · `REPO_ROOT`, E5가 도구 넷, E6이 검사 10, E7이
검사 11, E8이 검사 12의 잡기, E9가 검사 12의 붙이기, E10이 부팅 B(검사 13~15)와 PASS 줄이다.

E1 — `old_string`(기준 파일 34줄부터):

```bash
# 디스크를 물지 않는다. 패널은 설정과 무관하다.
```

`new_string`:

```bash
# 부팅 A는 디스크를 물지 않는다. 패널은 설정과 무관하다.
#
# CB-M0이 클립보드를 더했다(CB design 결정 4). 클립보드의 범위는 패널과
# 워크스페이스 사이의 일이라 이 체인에 둔다.
#   검사 10 — 부팅 A의 범위가 기본값 shared다(init 줄과 terminal 줄 둘).
#   검사 11 — 한 패널에서 y로 잡은 줄을 다른 패널에서 Cmd+V로 붙여 실행한다.
#   검사 12 — 같은 일을 워크스페이스를 건너서 한다.
#   부팅 B — 설정 디스크의 clipboard=pane. 검사 13이 범위를 보고, 14가
#            다른 패널의 Cmd+V가 빈 것을(음성), 15가 같은 패널의 Cmd+V가
#            그 글자를 붙이는 것을(대조군) 본다.
# 판정은 clip> 줄과 마지막 screen> 줄이다. clip> 줄은 어느 패널의 것인지
# 말하지 않으므로, 붙인 글자가 실행되어 포커스 패널의 화면에 나오는 것을
# 함께 본다.
```

E2 — `old_string`(기준 파일 69줄부터):

```bash
# QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45487
```

`new_string`:

```bash
# QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다. 45488 ·
# 45489는 pointer 체인의 것이고, 부팅 B(CB-M0)가 45490을 쓴다.
MONITOR_PORT=45487
MONITOR_PORT_B=45490

REPO_ROOT="$(cd .. && pwd)"
```

E3 — `old_string`(기준 파일 93줄부터):

```bash
    "terminal: child exited (pty EOF)" \
```

`new_string`:

```bash
    "terminal: child exited (pty EOF)" \
    "terminal: clipboard scope=" \
    "terminal: clip>" \
```

E4 — `old_string`(기준 파일 102줄부터):

```bash
  grep -a 'terminal: pane>' "$LOG" | tail -n 20
```

`new_string`:

```bash
  grep -a 'terminal: pane>' "$LOG" | tail -n 20
  echo "--- clip lines ---"
  grep -a -e 'terminal: clip' -e 'tars-init: config shell=' "$LOG" | tail -n 10
```

E5 — `old_string`(기준 파일 169줄부터):

```bash
# 어떤 줄의 개수가 기준보다 커질 때까지 기다린다. 60초 — init이 terminal을
```

`new_string`:

```bash
# 클립보드 줄의 개수(CB-M0). 패턴은 고정 문자열이다. 붙여넣기는 key> 줄을
# 안 만들므로(copy 체인 검사 11) 이 개수가 "Cmd+V가 닿았다"의 증거다.
clip_count() {
  grep -acF "terminal: clip> $1" "$LOG" || true
}

# clip_count가 기준보다 커질 때까지 기다린다. 있으면 0, 15초가 지나면 1.
wait_for_clip() {
  local what="$1" before="$2" i
  for i in $(seq 1 150); do
    if [ "$(clip_count "$what")" -gt "$before" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 마지막 screen> 줄(포커스 패널)이 패턴에 맞을 때까지 기다린다. 있으면 0,
# 15초가 지나면 1. wait_for_screen은 로그 전체를 보므로 "어느 패널에
# 나왔는가"를 못 가른다(project_gate_screen_echo).
wait_for_last_screen() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(last_screen)"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# copy mode에 들어가 프롬프트 바로 위 줄을 V로 잡고 y로 복사한다(CB-M0).
# copy 커서는 셸 커서(프롬프트 줄)에서 시작하므로 k 한 번이 바로 위의
# 출력 줄이다(copy 체인 검사 8과 같은 키). 들어간 것을 copy> enter 줄 수로
# 기다린다 — 안 들어갔는데 k를 치면 셸이 k를 받는다.
yank_line_above_prompt() {
  local enters i
  enters="$(grep -ac 'terminal: copy> enter row=' "$LOG" || true)"
  type_keys meta_l-shift-c
  for i in $(seq 1 150); do
    [ "$(grep -ac 'terminal: copy> enter row=' "$LOG" || true)" -gt "$enters" ] && break
    sleep 0.1
  done
  type_keys k
  type_keys shift-v
  type_keys y
}

# 어떤 줄의 개수가 기준보다 커질 때까지 기다린다. 60초 — init이 terminal을
```

E6 — `old_string`(기준 파일 220줄부터):

```bash
echo "boot: $(last_pane_line)"
```

`new_string`:

```bash
echo "boot: $(last_pane_line)"

# ── 검사 10: 디스크가 없으면 클립보드는 shared다(CB-M0) ────────────────
#
# 줄 둘을 짝으로 본다(CB design 결정 3). init 줄은 "설정을 읽었다"를,
# terminal 줄은 "그 값이 argv를 건너 닿았다"를 말한다. 기본값이 그대로
# 닿는 것은 부팅 B의 pane이 함께 있어야 뜻이 있다 — 여기만 보면 argv를
# 안 읽는 terminal도 초록이다.
echo "=== boot: the clipboard is shared ==="
grep -aE 'tars-init: config shell=.* clipboard=shared' "$LOG" >/dev/null ||
  report_failure "the tars-init: config line does not end with clipboard=shared"
grep -aF 'terminal: clipboard scope=shared' "$LOG" >/dev/null ||
  report_failure "no 'terminal: clipboard scope=shared' line"
echo "boot: clipboard=shared reached the terminal"
```

E7 — `old_string`(기준 파일 314줄부터):

```bash
echo "copy mode swallowed Cmd+D: still $(pane_value panes) panes"
```

`new_string`:

```bash
echo "copy mode swallowed Cmd+D: still $(pane_value panes) panes"

# ── 검사 11: 오른쪽 패널에서 잡은 줄을 왼쪽 패널에 붙인다(CB-M0) ──────
#
# copy 체인의 검사 7~12와 같은 왕복을 패널 둘에 걸친다. 셋을 본다.
#   1. y가 그 줄을 잡았다(clip> len=12 text=echo cb-pane).
#   2. 왼쪽의 Cmd+V가 같은 12바이트를 썼다(clip> paste len=12). CB 전에는
#      여기서 clip> paste empty였다 — 클립보드가 패널마다 하나였다.
#   3. 붙인 줄이 왼쪽 셸에서 실행되어 cb-pane만 있는 줄이 왼쪽 화면에
#      나온다. 2만 보면 "썼는데 다른 패널의 PTY에 갔다"가 통과한다.
# 대조군은 붙이기 전의 왼쪽 화면이다. cb-pane만 있는 줄이 없어야 한다.
echo "=== CB: a line yanked in the right pane pastes in the left pane ==="
type_keys e c h o spc e c h o spc c b minus p a n e ret
wait_for_last_screen '\| echo cb-pane \|' ||
  report_failure "the right pane's shell did not print 'echo cb-pane'"
YANKS_BEFORE="$(clip_count 'len=12 text=echo cb-pane')"
yank_line_above_prompt
wait_for_clip 'len=12 text=echo cb-pane' "$YANKS_BEFORE" ||
  report_failure "V then y in the right pane did not put 'echo cb-pane' on the clipboard"
type_keys meta_l-bracket_left
wait_for_pane 'panes=2 focus=0 rect=0,0 ' ||
  report_failure "Cmd+[ did not move the focus to the left pane"
case "$(last_screen)" in
  *"| cb-pane |"*) report_failure "the left pane already shows a cb-pane line before any paste" ;;
esac
PASTES_BEFORE="$(clip_count 'paste len=12 bracketed=1')"
EMPTY_BEFORE="$(clip_count 'paste empty')"
type_keys meta_l-v
wait_for_clip 'paste len=12 bracketed=1' "$PASTES_BEFORE" ||
  report_failure "Cmd+V in the left pane did not write the 12 bytes the right pane yanked (paste empty ${EMPTY_BEFORE} -> $(clip_count 'paste empty'))"
type_keys ret
wait_for_last_screen '\| cb-pane \|' ||
  report_failure "the pasted line did not run in the left pane (no cb-pane line on the left pane's screen)"
type_keys meta_l-bracket_right
wait_for_pane 'panes=2 focus=1 ' ||
  report_failure "Cmd+] did not move the focus back to the right pane"
echo "a line yanked on the right ran on the left"
```

E8 — `old_string`(기준 파일 460줄부터):

```bash
# ── 검사 8: Cmd+1이 첫 워크스페이스로 간다 ────────────────────────────
```

`new_string`:

```bash
# ── 검사 12의 앞: 둘째 워크스페이스에서 줄 하나를 잡는다(CB-M0) ───────
#
# 9b가 terminal을 되살렸으므로 검사 11의 클립보드는 이미 없다. 새 글자로
# 잡는다 — 검사 11의 글자가 남아 있었다면 검사 12가 무엇을 붙였는지 안
# 갈린다.
echo "=== CB: yank a line in the second workspace ==="
type_keys e c h o spc e c h o spc c b minus w s ret
wait_for_last_screen '\| echo cb-ws \|' ||
  report_failure "the second workspace's shell did not print 'echo cb-ws'"
YANKS_BEFORE="$(clip_count 'len=10 text=echo cb-ws')"
yank_line_above_prompt
wait_for_clip 'len=10 text=echo cb-ws' "$YANKS_BEFORE" ||
  report_failure "V then y in the second workspace did not put 'echo cb-ws' on the clipboard"
echo "the second workspace yanked: echo cb-ws"

# ── 검사 8: Cmd+1이 첫 워크스페이스로 간다 ────────────────────────────
```

E9 — `old_string`(기준 파일 477줄부터):

```bash
echo "first workspace: $(last_pane_line), status \"${TEXT}\""
```

`new_string`:

```bash
echo "first workspace: $(last_pane_line), status \"${TEXT}\""

# ── 검사 12: 둘째 워크스페이스에서 잡은 줄을 첫째에 붙인다(CB-M0) ─────
#
# 검사 11과 같은 셋을 워크스페이스를 건너 본다. 워크스페이스마다의
# 클립보드는 두지 않았으므로(CB design 비목표 1) 이것이 통과하면 패널 칸이
# 아니라 공유 칸을 썼다는 것이다.
echo "=== CB: the line pastes in the first workspace ==="
case "$(last_screen)" in
  *"| cb-ws |"*) report_failure "the first workspace already shows a cb-ws line before any paste" ;;
esac
PASTES_BEFORE="$(clip_count 'paste len=10 bracketed=1')"
EMPTY_BEFORE="$(clip_count 'paste empty')"
type_keys meta_l-v
wait_for_clip 'paste len=10 bracketed=1' "$PASTES_BEFORE" ||
  report_failure "Cmd+V in the first workspace did not write the 10 bytes the second yanked (paste empty ${EMPTY_BEFORE} -> $(clip_count 'paste empty'))"
type_keys ret
wait_for_last_screen '\| cb-ws \|' ||
  report_failure "the pasted line did not run in the first workspace (no cb-ws line on its screen)"
echo "a line yanked in workspace 2 ran in workspace 1"
```

E10 — `old_string`(기준 파일 518줄부터):

```bash
echo "WP-M2 check PASS"
```

`new_string`:

```bash
echo "clip> lines:"
grep -a 'terminal: clip>' "$LOG" | tr -d '\r'

# ══ 부팅 B: clipboard=pane (CB-M0) ═══════════════════════════════════════
#
# 부팅 A를 끄고 설정 디스크 하나를 물려 다시 뜬다. 디스크는 debugfs 없이
# mkfs.ext2 -d로 굽는다(pointer 체인 부팅 B와 같은 길). 심는 값이 기본값과
# 달라야 한다 — 설정이 통째로 무시되는 코드도 shared로는 초록이 된다(HI-M2).
exec 3<&- 2>/dev/null
exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

SEED="$(mktemp -d)"
printf 'shell=fish\nclipboard=pane\n' > "$SEED/tars.conf"
mkdir -p "${REPO_ROOT}/out"
DISK_B="${REPO_ROOT}/out/cb-pane.img"
rm -f "$DISK_B"
truncate -s 16M "$DISK_B"
mkfs.ext2 -F -q -m 0 -L tars-cb -d "$SEED" "$DISK_B"
rm -rf "$SEED"

LOG_A="$LOG"
LOG="$(mktemp)"
echo "=== boot B: clipboard=pane ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK_B",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot B: terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot B: the shell prompt never showed up"
grep -a 'tars-init: mounted ext2 at /config' "$LOG" >/dev/null ||
  report_failure "boot B: the config disk was not mounted at /config"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "boot B: could not connect to the QEMU monitor"

# ── 검사 13: 디스크의 clipboard=pane이 terminal까지 닿는다 ─────────────
#
# 검사 10의 짝이다. 둘이 함께 있어야 "argv를 읽는다"가 판정된다 — terminal이
# 아홉째 인자를 안 읽으면 여기서 scope=shared가 찍힌다.
echo "=== boot B: the clipboard is per pane ==="
grep -aE 'tars-init: config shell=.* clipboard=pane' "$LOG" >/dev/null ||
  report_failure "boot B: the tars-init: config line does not end with clipboard=pane"
grep -aF 'terminal: clipboard scope=pane' "$LOG" >/dev/null ||
  report_failure "boot B: init read clipboard=pane but terminal says '$(grep -a 'terminal: clipboard scope=' "$LOG" | tail -n 1 | tr -d '\r')'"
echo "boot B: clipboard=pane reached the terminal"

# ── 검사 14(음성): 다른 패널의 Cmd+V는 빈 클립보드다 ───────────────────
#
# 음성 판정에 양성 신호를 붙인다. "paste len 줄이 안 늘었다"만 보면 Cmd+V가
# 아예 안 왔어도 통과하므로, clip> paste empty 줄이 하나 느는 것을 본다.
echo "=== boot B: Cmd+V in the other pane finds nothing ==="
type_keys meta_l-d
wait_for_pane 'panes=2 focus=1 ' ||
  report_failure "boot B: Cmd+D did not give 'panes=2 focus=1'"
type_keys e c h o spc e c h o spc c b minus o w n ret
wait_for_last_screen '\| echo cb-own \|' ||
  report_failure "boot B: the right pane's shell did not print 'echo cb-own'"
YANKS_BEFORE="$(clip_count 'len=11 text=echo cb-own')"
yank_line_above_prompt
wait_for_clip 'len=11 text=echo cb-own' "$YANKS_BEFORE" ||
  report_failure "boot B: V then y did not put 'echo cb-own' on the right pane's clipboard"
type_keys meta_l-bracket_left
wait_for_pane 'panes=2 focus=0 rect=0,0 ' ||
  report_failure "boot B: Cmd+[ did not move the focus to the left pane"
EMPTY_BEFORE="$(clip_count 'paste empty')"
PASTES_BEFORE="$(clip_count 'paste len=')"
type_keys meta_l-v
wait_for_clip 'paste empty' "$EMPTY_BEFORE" ||
  report_failure "boot B: Cmd+V in the left pane did not report an empty clipboard (paste len= ${PASTES_BEFORE} -> $(clip_count 'paste len='))"
[ "$(clip_count 'paste len=')" -eq "$PASTES_BEFORE" ] ||
  report_failure "boot B: Cmd+V in the left pane wrote the right pane's clipboard"
echo "boot B: the left pane's clipboard is empty"

# ── 검사 15: 같은 패널의 Cmd+V는 그 글자를 붙인다 ──────────────────────
#
# 검사 14의 대조군이다. 이것이 없으면 "y가 아무 데도 안 넣었다"나 "pane이면
# 붙이기가 늘 비었다"도 14를 통과한다.
echo "=== boot B: Cmd+V in the pane that yanked pastes it ==="
type_keys meta_l-bracket_right
wait_for_pane 'panes=2 focus=1 ' ||
  report_failure "boot B: Cmd+] did not move the focus back to the right pane"
PASTES_BEFORE="$(clip_count 'paste len=11 bracketed=1')"
type_keys meta_l-v
wait_for_clip 'paste len=11 bracketed=1' "$PASTES_BEFORE" ||
  report_failure "boot B: Cmd+V in the right pane did not write its own 11 bytes"
type_keys ret
wait_for_last_screen '\| cb-own \|' ||
  report_failure "boot B: the pasted line did not run in the right pane (no cb-own line)"
echo "boot B: the right pane pasted its own line"

# NUL 바이트를 한 번의 읽기로 센다. 부팅 A의 검사처럼 크기를 두 번 재면
# 그 사이에 게스트가 쓴 줄(방금 친 Enter의 프레임)이 차이로 잡힌다.
if [ "$(tr -cd '\000' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "boot B: the serial log contains NUL bytes"
fi

echo "boot B clip> lines:"
grep -a 'terminal: clip>' "$LOG" | tr -d '\r'
echo "CB-M0 check PASS"
```

### 4-2. `check.sh` — 문단과 `CHAINS`

E1 — `old_string`(기준 파일 333줄부터):

```bash
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

`new_string`:

```bash
# WP 체인은 패널 분할 · 닫기 · 순환과 워크스페이스를 본다. CB-M0이 클립보드의
# 범위를 더했다 — 부팅 A(디스크 없음, shared)에서 한 패널 · 워크스페이스에서
# 잡은 줄을 다른 곳에 붙여 실행하고, 부팅 B(설정 디스크의 clipboard=pane)에서
# 다른 패널의 Cmd+V가 비는 것을 본다. 회차당 부팅 2회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

E2 — `old_string`(기준 파일 353줄부터):

```bash
  "WP-M2:./pane/check.sh"
```

`new_string`:

```bash
  "CB-M0:./pane/check.sh"
```

### 4-3. 확인

```bash
bash -n pane/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pane/check.sh && require_no_early_exit_pipe ./pane/check.sh &&
  require_explicit_nic ./pane/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
diff pane/check.sh /tmp/run/cb0/new/pane/check.sh && echo SAME
diff check.sh /tmp/run/cb0/new/check.sh && echo SAME-root
python3 /tmp/run/cb0/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK` · `SAME` · `SAME-root` · `post: 88 edits, 0 bad`.

## Task 5: 체인 한 번과 regression

체인은 하나씩 돈다. 전부 같은 `kernel/initrd.cpio`를 다시 만들고, VM의 메모리가 4GB다.

### 5-1. `pane` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/cb0:/tmp/run/cb0 -w /workspace tars-devcontainer bash -c '
    bash pane/check.sh > /tmp/run/cb0/impl/pane.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a '^=== (boot: the clipboard|CB:|boot B)|^boot: clipboard|^a line|^the second workspace yanked|^boot B: |^terminal: clip>|check PASS|^FAIL' /tmp/run/cb0/impl/pane.log
```

기대: `exit=0`. `rg`는 이렇다(사본의 판).

```
=== boot: the clipboard is shared ===
boot: clipboard=shared reached the terminal
=== CB: a line yanked in the right pane pastes in the left pane ===
a line yanked on the right ran on the left
=== CB: yank a line in the second workspace ===
the second workspace yanked: echo cb-ws
=== CB: the line pastes in the first workspace ===
a line yanked in workspace 2 ran in workspace 1
terminal: clip> len=12 text=echo cb-pane
terminal: clip> paste len=12 bracketed=1
terminal: clip> len=10 text=echo cb-ws
terminal: clip> paste len=10 bracketed=1
=== boot B: clipboard=pane ===
=== boot B: the clipboard is per pane ===
boot B: clipboard=pane reached the terminal
=== boot B: Cmd+V in the other pane finds nothing ===
boot B: the left pane's clipboard is empty
=== boot B: Cmd+V in the pane that yanked pastes it ===
boot B: the right pane pasted its own line
terminal: clip> len=11 text=echo cb-own
terminal: clip> paste empty
terminal: clip> paste len=11 bracketed=1
CB-M0 check PASS
```

첫 판은 terminal을 다시 빌드하므로 1~2분 더 걸린다. 빨개지면 `report_failure`가 찍는 표식 · `clip lines` · 마지막 40줄을
그대로 보고한다.

### 5-2. regression

`tars-init: config` 줄을 보는 체인과 클립보드를 보는 체인, 감독 목록의 argv를 쓰는 체인이다(확정 9). 한 컨테이너에서 차례로
돈다. 사본에서 합 약 17분이었다.

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/cb0:/tmp/run/cb0 -w /workspace tars-devcontainer bash -c '
    for c in copy hangul config pointer tools net service wifi firewall input power; do s=$(date +%s)
      bash $c/check.sh > /tmp/run/cb0/impl/reg_$c.log 2>&1
      echo "$c exit=$? $(( $(date +%s) - s ))s"; done' ; } 2>&1 | tail -14
```

기대: 열하나 다 `exit=0`.

## Task 6: mutation 넷

확정 10의 표다. 사본은 `/tmp/run/cb0/impl/mut/`에 만든다. 돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 —
`sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

### 6-0. 사본을 만든다

```bash
M=/tmp/run/cb0/impl/mut; mkdir -p $M
cp terminal/src/main.zig $M/main_m1.zig; cp terminal/src/main.zig $M/main_m2.zig
cp init/src/main.zig $M/init_main_m3.zig; cp terminal/src/clipboard.zig $M/clipboard_h1.zig
sd -F '        return clipboard.pick(self.scope, &self.shared, &pane.clip);' '        return clipboard.pick(.pane, &self.shared, &pane.clip);' $M/main_m1.zig
sd -F '        return clipboard.pick(self.scope, &self.shared, &pane.clip);' '        return clipboard.pick(.shared, &self.shared, &pane.clip);' $M/main_m2.zig
sd -F '    const clipboard_arg = cfg.clipboard.arg();' '    const clipboard_arg = config.ClipboardScope.shared.arg();' $M/init_main_m3.zig
sd -F '        if (self.buf) |old| self.alloc.free(old);' '        if (self.buf) |old| _ = old;' $M/clipboard_h1.zig
bash -c 'M=/tmp/run/cb0/impl/mut; diff terminal/src/main.zig $M/main_m1.zig; diff terminal/src/main.zig $M/main_m2.zig
  diff init/src/main.zig $M/init_main_m3.zig; diff terminal/src/clipboard.zig $M/clipboard_h1.zig'
```

기대: 네 `diff`가 각각 한 줄의 차이다. 넷 다 바꾼 줄 밖에서 쓰이는 이름만 남기므로(`self.scope`는 필드라 안 써도 되고,
`cfg.clipboard`는 로그 줄이 쓴다) 안 쓰는 변수의 컴파일 에러가 안 난다.

### 6-1. 체인 셋과 호스트 하나

캐시 삭제는 같은 `docker run` 안에서 한다(`project_zig_out_staleness`).

```bash
bash -c 'cd /Users/dp/Repository/tars-linux; M=/tmp/run/cb0/impl/mut
for m in 1 2 3; do
  case $m in
    1|2) OV="-v $M/main_m$m.zig:/workspace/terminal/src/main.zig:ro" ;;
    3)   OV="-v $M/init_main_m3.zig:/workspace/init/src/main.zig:ro" ;;
  esac
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/cb0:/tmp/run/cb0 $OV \
      -w /workspace tars-devcontainer bash -c "
    echo \"mounted: m1=\$(grep -c \"pick(.pane, &self.shared\" terminal/src/main.zig) m2=\$(grep -c \"pick(.shared, &self.shared\" terminal/src/main.zig) m3=\$(grep -c \"ClipboardScope.shared.arg()\" init/src/main.zig)\"
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash pane/check.sh > $M/m$m.log 2>&1; echo \"exit=\$?\"" ; } 2>&1 | tail -6
  rg -a -n "^===|^FAIL" $M/m$m.log | tail -2
done
echo "== host mutation h1"
{ time docker run --rm -v "$PWD":/workspace -v $M/clipboard_h1.zig:/workspace/terminal/src/clipboard.zig:ro \
    -w /workspace/terminal tars-devcontainer bash -c "
  echo \"mounted: h1=\$(grep -c \"|old| _ = old;\" src/clipboard.zig)\"
  zig build test > /tmp/t.out 2>&1; echo \"exit=\$?\"
  grep -a -E \"^FAIL|^clipboard_test: no leak|leaked|^vt_test: copy selection OK\" /tmp/t.out | head -8" ; } 2>&1 | tail -16'
```

로그에 `Killed`가 보이고 `FAIL: terminal build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지
보고 그 판만 다시 돈다.

기대(확정 10에서 본 그대로). `mounted:`는 그 번호 자리만 1이다.

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 | `m1=1 m2=0 m3=0` | 검사 11 | `FAIL: Cmd+V in the left pane did not write the 12 bytes the right pane yanked (paste empty 0 -> 1)` |
| 2 | `m1=0 m2=1 m3=0` | 검사 14 | `FAIL: boot B: Cmd+V in the left pane did not report an empty clipboard (paste len= 0 -> 1)` |
| 3 | `m1=0 m2=0 m3=1` | 검사 13 | `FAIL: boot B: init read clipboard=pane but terminal says 'terminal: clipboard scope=shared'` |
| H1 | `h1=1` | `clipboard_test` | `exit=1`, `FAIL: the clipboards leaked`. `vt_test: copy selection OK`와 `error(DebugAllocator): … leaked` 줄들이 함께 나온다 |

체인 판마다 2분 10초~2분 30초다(캐시를 지워 다시 빌드한다). H1은 20초 안팎이다.

mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다
(`project_zig_out_staleness` — 캐시 삭제가 같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 6-2. 되돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
  (cd init && zig build > /tmp/i.out 2>&1 && zig build test >> /tmp/i.out 2>&1); echo "init exit=$?"
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "terminal exit=$?"
  (cd kernel && ./make_initrd.sh > /tmp/k.out 2>&1); echo "initrd exit=$?"'
git status --short
```

기대: 셋 다 `exit=0`. `git status`는 `M` 열둘(`check.sh` · `pane/check.sh` · `terminal/build.zig` · `terminal/src/`의 셋 ·
`init/src/`의 여섯)과 `??` 둘(`terminal/src/clipboard.zig` · `clipboard_test.zig`)이고, plan과 design이 commit 전이면 그 둘이
더 있다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 6-3. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력.
- Task 1~4의 확인 출력(`SAME` · OK 줄 수 · `ENTRY-OK` · `anchors.py`).
- Task 5의 `exit=` · `real` · `rg` 출력과 regression 열하나의 줄.
- Task 6의 `diff` 넷 · `mounted:` · `exit=` · `real` · `FAIL` 줄, 6-2의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 7: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 파일 전부를 이 plan의 사본(`/tmp/run/cb0/new/`)과 `cmp`한다. Task 5의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 열아홉 체인 × 2다. 판정은 `PASS: 2/2` × 19와 `CB-M0 check PASS` 둘이다. `pane`
   체인이 판마다 부팅 하나(사본에서 약 10초)를 더한다. `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와
   겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_cb0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_cb0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 2/2' /tmp/gate_cb0.log`가 19, `rg -c 'CB-M0 check PASS' /tmp/gate_cb0.log`가 2여야 한다.
3. 실측 절 채우기.
4. commit. 넣는 것은 `terminal/src/clipboard.zig` · `clipboard_test.zig` · `vt.zig` · `vt_test.zig` · `main.zig` ·
   `terminal/build.zig` · `init/src/`의 여섯 · `pane/check.sh` · `check.sh` · 이 plan이고, design이 commit 전이면 함께 넣는다.
   `git add`는 경로를 하나씩 지정한다.
5. 닫기. design의 "닫을 때" 목록이다. 서브프로젝트를 닫는 commit은 CB-M0 commit과 따로 만든다.

## design과 다르게 적은 것

design과 이 plan은 같은 날 함께 썼고, design의 실측 절이 이 plan의 사본에서 잰 값을 담는다. 다른 것은 없다.

## 이 milestone에서 안 하는 것

- 범위 `workspace` · 클립보드가 재시작을 넘는 것 · OSC 52 · 다른 프로세스와의 클립보드 · 상한 · 실행 중 범위 바꾸기 ·
  클립보드 기록(design 비목표 1~7).
- 포인터 끌기로 잡은 글자가 다른 패널에 붙는 것의 게이트. 키보드 `y`와 같은 `Clips.yank`를 지나므로(확정 3) 따로 보지
  않는다. 포인터의 뗌이 `clip>` 줄을 찍는 것은 `pointer` 체인이 이미 본다.
- 부팅 A의 NUL 검사(크기를 두 번 잰다)를 확정 8의 모양으로 바꾸는 것. 그 검사 앞에는 `sleep 2`가 있어 지금까지 흔들린 적이
  없고, 이 milestone의 일이 아니다.

## CB-M0이 실측한 것

2026-10-05. 구현은 Opus 서브에이전트가, 대조 · 루트 게이트 · commit은 lead(Fable)가 했다.

1. 편집 여든여덟과 새 파일 둘이 전부 글자 그대로 들어갔다. 구현자는 plan 본문에서 블록을 기계로 뽑아 planner의
   `anchors.json`과 대조한 뒤(차이 0) 적용했다. lead가 열네 파일을 `/tmp/run/cb0/new/`와 `cmp`하니 바이트까지 같았다.
   지운 줄은 전부 의도한 것이다 — 옛 `clip` 칸과 `clipboard()` · 옛 시그니처 호출 · `[8:null]` 여섯 자리 · 로그 포맷
   문자열 · `WP-M2` 표식과 `CHAINS` 항목.
2. EL-M0과 겹친 블록 셋(새 HEAD 기준으로 다시 뽑은 것)은 이 구현에서 처음 컴파일됐고 에러가 없었다. `init` · `terminal`의
   `zig build` · `zig build test` 전부 exit 0. `vt_test` OK 82 그대로, `clipboard_test` OK 7(새 파일), `config_test`에
   `unknown clipboard` 두 줄(기대한 음성).
3. pane 체인(구현자의 판) 43초, 마지막 줄 `CB-M0 check PASS`. 확인 출력이 plan의 기대 블록과 줄마다 같았다.
4. regression 11체인 중 hangul 하나가 처음에 18초 만에 빨갰다 — plan 밖의 문제다. EL-M0이 넣은 판정
   `grep -aE "tars-init: config .* esc_latin=on\$"`가 줄 끝에 고정돼 있었고 CB가 그 뒤에 `clipboard=shared`를 붙였다.
   planner의 regression은 `5acc735` 판이라 그 판정이 없었다. lead가 처방을 정했고(바로 위 `toggles=` 판정과 같은
   `( |\$)` 경계, 주석 한 문단) 구현자가 넣었다 — plan 밖 편집 하나, `hangul/check.sh` +4 −2. 그 뒤 hangul 체인
   2분 54초 PASS. 저장소에서 config 줄을 줄 끝에 고정한 자리는 그 하나뿐이었다. lessons의 "키를 더할 때는 맨 뒤에
   붙인다"는 앵커를 줄 끝에 두지 말라는 뜻도 된다 — 닫기에서 lessons에 적는다.
   나머지 열은 전부 PASS — `copy` 171초 · `config` 163초(seed 48줄로 처음 돌았고 design 위험 4는 일어나지 않았다) ·
   `pointer` 74초 · `tools` 60초 · `net` 174초 · `service` 74초 · `wifi` 103초 · `firewall` 52초 · `input` 38초 · `power` 51초.
5. mutation 넷이 전부 확정의 표와 같은 검사에서 같은 메시지로 빨갰다 — 1은 검사 11(`Cmd+V in the left pane did not write
   the 12 bytes the right pane yanked`), 2는 검사 14(`did not report an empty clipboard`), 3은 검사 13(`init read
   clipboard=pane but terminal says 'terminal: clipboard scope=shared'`), H1은 `clipboard_test`의 `the clipboards leaked`.
6. 루트 게이트 19체인 2/2, 51분 15초(`/tmp/gate_cb0.log`). EL-M0의 50분 58초에 17초를 더했다 — pane 부팅 B 하나 × 2.
   `CB-M0 check PASS` 둘, `HI check PASS` 둘, `FAIL` · `Killed` 0줄. 두 회차 모두 `terminal: clipboard scope=shared`(부팅 A)와
   `clip> len=12 text=echo cb-pane` · `clip> len=10 text=echo cb-ws`가 찍혔다.
7. 컨테이너 lock(`/tmp/run/docker.lock`)은 EL 때처럼 지켜졌고 `Killed`는 없었다. 다만 이번에는 구현자 혼자 컨테이너를
   썼다 — 사용자의 "안전하게 순차 진행" 결정으로 CB 구현은 EL commit 뒤에 시작했다.
