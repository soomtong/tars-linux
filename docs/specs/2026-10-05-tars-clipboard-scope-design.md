# TARS Clipboard Scope — Design

Date: 2026-10-05
Status: 설계 확정(2026-10-05). CB-M0 plan을 썼다. 구현 전이다.

사용자의 요청(2026-10-05)에서 시작한다.

> 터미널 패널이나 워크스페이스 사이 clipboard를 공유해서 사용하는 옵션; 기본적으로 전체 공유 활성화. 현재는 각각의
> 워크스페이스가 독립된 클립보드를 가짐.

## 한 줄 요약

클립보드가 화면(`vt.Screen`) 밖으로 나온다. 기본은 terminal 전체에 하나(`shared`)라서, 한 패널에서 `y`로 잡은 글자를
다른 패널이나 다른 워크스페이스에서 `Cmd+V`로 붙인다. `tars.conf`에 `clipboard=pane`을 적으면 CB 전처럼 패널마다
하나다.

```
clipboard=shared(기본)   패널 A에서 y  →  패널 B · 다른 워크스페이스의 Cmd+V가 그 글자를 붙인다
clipboard=pane           패널 A에서 y  →  패널 B의 Cmd+V는 clip> paste empty, 패널 A의 Cmd+V는 그 글자
```

## 요청의 전제 하나를 바로잡는다 — 지금은 워크스페이스가 아니라 패널마다 따로다

클립보드는 `vt.Screen`의 칸 하나다(`terminal/src/vt.zig`의 `clip: ?[:0]const u8`). CM(2026-08-26)이 그렇게 정했을 때는
화면이 하나였다. WP(2026-10-04)가 패널마다 `Screen`을 하나씩 두면서(`spawnPane`) 클립보드도 패널 수만큼 생겼다.

그래서 같은 워크스페이스 안에서도 나뉘어 있다. 왼쪽 패널에서 `y`하고 오른쪽 패널에서 `Cmd+V`하면 `clip> paste empty`가
찍힌다. 착수 전에 이것을 실행으로 확인했다(아래 "착수 전에 실측한 것" 1). 사용자가 본 "워크스페이스마다 독립"은
워크스페이스마다 패널이 하나뿐일 때의 모습이다.

이 차이가 결정 2(범위의 이름)에 닿는다. CB 전의 동작을 그대로 남기는 범위의 이름은 `workspace`가 아니라 `pane`이다.

## 왜 새 서브프로젝트인가

닫힌 서브프로젝트 둘의 결정을 연다.

- CM design 결정 1("모드는 `input.zig`, 선택과 클립보드는 `vt.zig`")의 뒤 절반. 선택은 그대로 `vt.zig`에 있고, 클립보드의
  주인만 바뀐다(결정 1).
- WP design 비목표 "패널 간 복사 — 클립보드는 `vt.Screen`마다 하나다 … `main.zig`로 올려야 한다". 그 비목표가 예고한
  모양 그대로다.

둘 다 닫혀 있어서 그 design의 milestone으로 이을 수 없다. 크기는 milestone 하나(CB-M0)다.

## 모델

| 이름 | 무엇 | 사는 자리 |
|---|---|---|
| `Clipboard` | 문자열 하나를 소유하는 칸. `set`이 옛것을 해제하고 새것을 받는다 | `terminal/src/clipboard.zig`(새 파일, 순수) |
| 공유 칸 | terminal 프로세스에 하나 | `main.zig`의 `Clips.shared` |
| 패널 칸 | 패널마다 하나. `pane` 범위에서만 쓰인다 | `main.zig`의 `Pane.clip` |
| 범위 | `shared` · `pane`. 부팅에 한 번 정해진다 | `tars.conf` → init → argv 아홉째 칸 → `Clips.scope` |
| 선택 → 문자열 | 선택을 글자로 뽑는 일. CB 전과 같다 | `vt.zig`의 `copyYank` |
| 감싸기(모드 2004) | 붙여넣기의 머리 · 꼬리. 자식이 켜는 모드라 패널마다 따로다 | `vt.zig`의 `pasteParts`(안 바뀐다) |

### 동작 표

| 사람이 한 일 | `shared`(기본) | `pane` |
|---|---|---|
| 패널 A에서 `y`, 같은 패널에서 `Cmd+V` | 붙는다 | 붙는다 |
| 패널 A에서 `y`, 패널 B에서 `Cmd+V` | 붙는다 | `clip> paste empty` |
| 워크스페이스 1에서 `y`, 2에서 `Cmd+V` | 붙는다 | `clip> paste empty` |
| 패널 A를 포인터로 끌어 뗀다(복사), 패널 B에서 `Cmd+V` | 붙는다 | `clip> paste empty` |
| copy mode의 검색창에서 `Cmd+V`(FP) | 공유 칸의 첫 줄 | 그 패널 칸의 첫 줄 |
| 패널 A를 닫는다 | 공유 칸은 그대로 | 패널 A의 칸이 해제된다 |
| 마지막 패널을 닫아 terminal이 되살아난다 | 빈 칸으로 시작 | 빈 칸으로 시작 |

## 결정

### 결정 1 — 클립보드의 주인은 `main.zig`이고, 칸의 모양은 `clipboard.zig`에 있다

| 후보 | 왜 아닌가 |
|---|---|
| `Screen.clip`을 두고, `shared`면 `y`할 때 `main.zig`가 모든 `Screen`에 사본을 넣는다 | 같은 글자가 패널 수만큼(최대 9 × 8) 할당된다. 새로 연 패널은 지난 `y`를 모르므로 열 때 또 복사해야 한다. 칸이 여럿인데 같아야 한다는 규칙을 코드가 아니라 규율로 지킨다 |
| `Screen`에 `*Clipboard` 포인터를 두고 `spawnPane`이 주입한다 | `Screen`이 "누구와 나누는가"를 알게 된다. 그리고 공유 칸의 수명이 `Screen`보다 길어야 한다는 사실이 타입에 안 보인다 — 워크스페이스를 닫으면 `Workspace` 배열이 당겨지는데(WP-M2) 그 안의 포인터가 무엇을 가리키는지 따라가야 한다 |
| 칸을 `Screen` 밖에 두고, `copyYank`와 `findPaste`가 칸이나 글자를 인자로 받는다 | 고른 것 |

`vt.zig`에 남는 일은 "선택을 글자로 뽑는다"와 "그 글자를 needle에 넣는다"다. 어느 칸에 넣고 어느 칸에서 꺼낼지는 화면의
일이 아니라 terminal 프로세스의 일이라서 `main.zig`가 고른다. TR design 결정 1(판단은 `vt.zig`, 렌더러는 숫자만)과
부딪치지 않는다 — 그 결정이 다루는 것은 화면을 그리는 판단이고, 클립보드는 화면 상태가 아니다.

모양은 이렇다.

- `clipboard.zig` — `Clipboard`(할당자 · `?[:0]const u8`, `init` · `set` · `text` · `deinit`)와 `Scope`(`shared` · `pane`),
  그리고 `pick(scope, shared, own)` 한 함수. 시스템 콜도 ghostty도 모르는 순수 모듈이라 `clipboard_test`가 컨테이너에서
  초 단위로 돈다(`layout.zig` · `status.zig`와 같은 자리).
- `vt.Screen.copyYank(clip: *Clipboard)` — 선택 문자열을 `clip.alloc`으로 만들어 `clip.set`에 넘긴다. 할당한 쪽과 해제하는
  쪽이 같은 할당자여야 하기 때문이다. 돌려주는 슬라이스는 `clip`이 소유하고 다음 `set`까지 유효하다(CB 전과 같은 규칙).
- `vt.Screen.findPaste(clip: ?[]const u8)` — 글자를 받는다. null이면 빈 클립보드이고 0을 돌려준다.
- `vt.Screen.clipboard()`는 지운다. 그 함수의 주석(왜 `?[]const u8`인가 · 왜 먼저 풀고 돌려주는가)은
  `Clipboard.text()`로 옮긴다. `Screen.clip` 칸과 `deinit`의 해제 한 줄도 지운다.
- `main.zig`의 `Clips` — 범위 · 공유 칸과 함수 셋. `of(pane)`이 `pick`으로 칸을 고르고, `yank(pane)`이 `y`와 포인터 뗌을,
  `paste(pane)`이 `Cmd+V`의 두 갈래(검색창 · 셸)를 맡는다. 클립보드를 만지는 네 자리가 전부 `yank` · `paste`를 지나므로
  칸을 고르는 판단이 `of` 한 자리에만 있고, 키보드와 포인터가 다른 칸을 볼 수 없다.
- `Pane.clip` — 패널마다의 칸. `spawnPane`이 빈 칸으로 만들고, 패널을 닫는 두 자리(EOF 경로와 끝의 정리 `defer`)가
  `screen`과 함께 해제한다. `shared` 범위에서는 늘 비어 있다.
- `dumpPaste(screen, fd, clip)` · `dumpFindPaste(screen, clip)` — 글자를 인자로 받는다. 찍는 문구는 그대로다(결정 5).

`pasteParts`는 `Screen`에 남는다. 모드 2004는 자식이 켜는 것이고 `Terminal` 하나에 하나라(PE design 실측 2) 패널마다
따로여야 맞다. 공유 칸의 글자를 패널 B에 붙일 때 감쌀지는 패널 B의 자식이 정한다.

### 결정 2 — 범위는 `shared`와 `pane` 둘이고, 기본은 `shared`다

기본값은 사용자가 정했다("기본적으로 전체 공유 활성화"). `net` · `firewall`과 달리 켜는 비용이 없고, `keyboard=apple`처럼
이 기계를 쓰는 사람이 쓰는 것이 기본값이다.

`pane`은 CB 전의 동작 그대로다. 공유가 싫은 사람에게 돌아갈 길이 "옛날과 같다"여야 설명이 짧다.

`workspace`(같은 워크스페이스 안에서만 나눈다)는 두지 않는다(비목표 1). 요청이 말한 "워크스페이스마다 독립"은 실제로는
패널마다였고(위 절), 워크스페이스 단위의 칸은 한 번도 있었던 적이 없는 셋째 동작이다. 두려면 `Workspace`에 칸을 하나 더
두고, 워크스페이스를 닫을 때 배열을 당기는 자리(WP-M2)에서 그 칸을 해제하고, `pick`이 세 갈래가 된다. 쓰는 사람이 생기면
그 세 자리를 고치면 되고, 지금 짓지 않는다.

### 결정 3 — 설정 키는 `clipboard=`이고, terminal에는 argv의 아홉째 칸으로 간다

`init/src/config.zig`에 `ClipboardScope` enum을 더한다. 모양은 `firewall`과 같다 — `stringToEnum` 화이트리스트이고, 모르는
값은 `tars-init: unknown clipboard '…', falling back to shared` 한 줄을 찍고 기본값에 머문다. seed 파일의 끝에 네 줄을 더한다.

```
# clipboard: shared | pane
#   shared면 모든 패널과 워크스페이스가 클립보드 하나를 쓰고,
#   pane이면 패널마다 따로다
clipboard=shared
```

terminal로 가는 길을 셋 견줬다.

| 후보 | 왜 아닌가 |
|---|---|
| 여덟째 칸(한/영 전환 키 목록) 문자열에 끼워 넣는다 | 그 칸은 `input.parseToggles`가 콤마로 읽는 집합이다. 뜻이 다른 값을 섞으면 파서 둘이 한 문자열을 나눠 읽는다 |
| 환경 변수 | PID 1은 커널이 준 envp 블록을 그대로 넘긴다(`init/src/main.zig`의 execve). 항목을 더하려면 블록을 새로 지어야 한다 — HI-M1이 `LANG`을 terminal에서 `setenv`한 이유와 같다 |
| argv 아홉째 칸 | 고른 것. HI-M2 · HI-M3이 자판과 전환 키를 넘긴 길과 같다 |

`Child.argv`의 타입이 `[8:null]`이라 `[9:null]`로 넓힌다. 같은 타입을 쓰는 리터럴과 상수가 다섯이다 — terminal ·
콘솔 셸 · 서비스(`init/src/main.zig`)와 `clock.CHRONYD_ARGV` · `net.DHCPCD_ARGV` · `wifi.WIFI_ARGV`. 배열 리터럴은 길이가
타입과 맞아야 컴파일되므로 하나라도 빠뜨리면 빌드가 막힌다.

로그는 짝 둘이다. `tars-init: config …` 줄의 맨 뒤에 `clipboard=`를 붙이고(init이 파일에서 읽었다), terminal이
`terminal: clipboard scope=shared`를 찍는다(그 값이 argv를 건너 닿았다). `terminal: hangul layout=` 줄과 같은 역할이다
— 앞만 보면 argv 배선이 끊겨도 초록이고, 뒤만 보면 기본값이 우연히 맞아도 초록이다.

이름 둘(`shared` · `pane`)이 `config.ClipboardScope`와 `clipboard.Scope`에 한 벌씩 있다. 둘을 잇는 것이 argv의 문자열뿐이라
컴파일러가 못 잡는다. `config_test`가 `arg()`와 enum 이름이 같은지를, `clipboard_test`가 terminal 쪽 이름을, 게이트의
검사 13이 실제로 닿는지를 본다.

### 결정 4 — 게이트는 `pane/check.sh`에 검사 여섯과 부팅 하나를 더한다

클립보드의 범위는 패널과 워크스페이스 사이의 일이라 패널 체인에 둔다. 새 체인을 만들지 않는다.

| 검사 | 부팅 | 본다 |
|---|---|---|
| 10 | A(디스크 없음) | `tars-init: config … clipboard=shared`와 `terminal: clipboard scope=shared` |
| 11 | A | 오른쪽 패널에서 `echo echo cb-pane`의 출력 줄을 `V` · `y`로 잡고(`clip> len=12 text=echo cb-pane`), `Cmd+[` 뒤 왼쪽 패널에서 `Cmd+V`(`clip> paste len=12 bracketed=1`) · Enter → 왼쪽 패널의 마지막 `screen>`에 `cb-pane`만 있는 줄 |
| 12 | A | 둘째 워크스페이스에서 `echo cb-ws`를 잡고, `Cmd+1` 뒤 첫째에서 같은 일(`len=10`) |
| 13 | B(`clipboard=pane`) | init 줄의 `clipboard=pane`과 `terminal: clipboard scope=pane` |
| 14 | B | 오른쪽 패널에서 `echo cb-own`을 잡고, 왼쪽의 `Cmd+V`가 `clip> paste empty`를 하나 늘리고 `paste len=`은 안 늘린다(음성) |
| 15 | B | 오른쪽으로 돌아가 `Cmd+V`(`paste len=11 bracketed=1`) · Enter → `cb-own`만 있는 줄(14의 대조군) |

판정의 규율 넷.

1. 붙였다는 줄(`clip> paste len=…`)과 붙인 글자가 실행된 결과(포커스 패널의 마지막 `screen>`)를 함께 본다. `clip>` 줄은
   어느 패널의 것인지 말하지 않는다 — 줄만 보면 "썼는데 다른 패널의 PTY에 갔다"가 통과한다. 결과 쪽은 로그 전체가 아니라
   마지막 `screen>` 줄 하나로 본다. `screen>`은 포커스 패널만 찍고(WP design 결정 7), 로그 전체를 보면 어느 패널에 나왔는지를
   못 가른다(`docs/decisions/project_gate_screen_echo.md`).
2. 판정 글자와 친 글자가 안 겹친다. 친 것은 `echo echo cb-pane`이고, 잡는 것은 그 출력 `echo cb-pane`이고, 판정은 붙인
   것을 실행한 출력 `| cb-pane |`다. 앞 둘에는 `| cb-pane |`가 안 생긴다(copy 체인 검사 7~12와 같은 수법).
3. 음성 판정(14)에 양성 신호를 붙인다. `paste len=`이 안 늘었다는 것만 보면 `Cmd+V`가 아예 안 와도 통과하므로,
   `paste empty`가 하나 느는 것을 기다린다. 그리고 대조군(15)이 "y가 아무 데도 안 넣었다"를 막는다.
4. 부팅 B가 심는 값(`pane`)이 기본값과 다르다. 설정이 통째로 무시되는 코드도 `shared`로는 초록이다(HI-M2의 교훈). 검사
   10은 13과 짝일 때만 뜻이 있다 — 10만 보면 아홉째 인자를 안 읽는 terminal도 초록이다.

부팅 B를 `config` 체인의 기존 부팅에 끼우는 길도 견줬다. 그 체인의 부팅 아홉은 "고치고 재부팅하면 남는다"를 보는
자리라, 패널을 가르고 copy mode를 치는 일을 섞으면 그 체인이 무엇을 보는지가 흐려진다. 비용은 부팅 하나다 — 같은 사본에서
pane 체인이 33초에서 43~44초가 됐다(실측 9). 디스크는 `mkfs.ext2 -d`로 굽는다(pointer 체인 부팅 B와 같은 길,
`project_seeding_a_config_disk`). monitor 포트는 45490이다.

### 결정 5 — 로그 문구는 하나도 안 바꾸고 줄 하나를 더한다

`clip> len=… text=…` · `clip> empty` · `clip> paste len=… bracketed=…` · `clip> paste empty` · `find> paste clip=… put=…`는
글자 그대로다. CM design 결정 8대로 이 문구는 `main.zig`와 `copy/check.sh` · `hangul/check.sh` · `pointer/check.sh`에
중복되어 있다. 접두도 `len=`의 뜻(본문 바이트)도 안 바뀐다.

새 줄은 `terminal: clipboard scope=…` 하나다. `tars-init: config` 줄은 맨 뒤에 필드 하나가 붙는다. 그 줄을 grep하는 체인
열(`config` · `hangul` · `input` · `machine` · `net` · `firewall` · `power` · `tools` · `install` · 그리고 `pane`)을 착수 전에
훑었다. 줄 끝에 앵커한 곳은 없고, `hangul/check.sh`의 `toggles=…( |$)`는 뒤에 필드가 와도 맞는다(실측 4).

### 결정 6 — 구현은 서브에이전트가, 게이트 · commit은 lead가 한다

PD 결정 11과 같다. plan의 `old_string` · `new_string`은 저장소 밖 사본에서 컴파일 · 호스트 검사 · 체인 · regression ·
mutation까지 돌린 뒤 기계로 뽑았다. 구현자(Opus)는 그것을 글자 그대로 옮기고, lead(Fable)가 루트 게이트 · 실측 절 ·
commit · 닫기를 한다.

## 검증

### 호스트(모든 체인이 부팅 전에 돌린다)

- `clipboard_test`(새 검사 파일) — 새 칸은 null · `set`이 바꾼다 · 범위가 칸을 고른다(주소로 비교) · 패널 칸에 넣은 것이
  공유 칸에 안 보인다 · 범위 이름이 `shared` · `pane`이고 `workspace`는 없다 · 누수가 없다(`DebugAllocator`).
- `vt_test` — `copyYank`를 부르는 검사(5~8 · 16 · 56 · 58 · 97~101)가 화면마다 칸 하나를 둔다. 검사 97은 두 화면의 글자를
  함께 들고 비교하므로 칸이 둘이다. 검사 10의 대조군은 "y를 한 번도 안 부른 화면"에서 "선택 없는 y는 빈 칸을 안 채운다"로
  바뀐다 — 화면이 칸을 안 가지므로 옛 대조군은 뜻이 없어졌다. 검사 55는 `findPaste(null)`이다.
- `config_test` — `clipboard=pane` · `shared` · `workspace`(모르는 값) · 빈 값, `arg()`가 enum 이름과 같다, 부팅 B가 쓰는
  두 줄. `expect`가 열한째 필드를 비교하고 실패 줄에 찍는다.

### 게이트

결정 4의 표. 부팅이 하나에서 둘이 된다.

## Milestone

### CB-M0 — 클립보드를 밖으로 내고 범위를 고른다

이 서브프로젝트는 milestone 하나다. 고치는 파일은 terminal 넷(`vt.zig` · `vt_test.zig` · `main.zig` · `build.zig`)과
새 파일 둘(`clipboard.zig` · `clipboard_test.zig`), init 여섯(`config.zig` · `config_test.zig` · `main.zig` · `clock.zig` ·
`net.zig` · `wifi.zig`), 게이트 둘(`pane/check.sh` · `check.sh`)이다. plan은
`docs/plans/2026-10-05-tars-clipboard-scope-cb-m0.md`.

## 위험

1. 공유 칸은 한 패널의 글자를 다른 패널로 옮긴다. 한 패널에서 잡은 비밀(토큰 같은 것)이 다른 패널에서 `Cmd+V` 한 번에
   붙는다. 사람이 `Cmd+V`를 눌러야만 일어나는 일이라 iTerm2 · WezTerm의 기본과 같다. 싫으면 `clipboard=pane`이다.
2. `text()`가 준 슬라이스는 다음 `set`까지만 유효하다. `shared`에서는 어느 패널의 `y`든 같은 칸을 바꾸므로, 슬라이스를
   들고 있는 동안 다른 패널이 `y`하면 해제된 메모리를 읽는다. 지금은 그런 자리가 없다 — `yank`는 받은 글자를 바로
   `dumpClip`으로 찍고 버리고, `paste`는 꺼내서 쓰고 찍는 사이에 `set`이 없다. terminal은 스레드 하나다. 새 호출부가
   슬라이스를 오래 들고 싶으면 복사한다.
3. 범위 이름 둘이 init과 terminal에 한 벌씩 있다(결정 3). 한쪽만 고치면 설정이 조용히 기본값으로 떨어진다. 증상이
   "설정을 적었는데 공유된다"라 사람 눈에 늦게 띈다. 게이트의 검사 13이 그 경로를 끝까지 본다.
4. `config` 체인 1차 부팅의 `tars-config`가 seed 파일 전체를 화면에 찍고 `| shell_config=on`을 찾는다. seed가 44줄
   (EL-M0 뒤)에서 48줄이 되어 47줄 화면을 넘는다. 명령줄과 위의 두 줄이 화면 밖으로 밀리지만 `shell_config=on`은 25번째
   줄이라 남는다. 다음에 키를 더하는 사람은 그 검사를 함께 본다. 44줄 판(`5acc735` 위)으로는 regression에서 `config`
   체인이 통과했고, 48줄 판은 구현자의 regression이 처음 본다(plan 확정 1 · 6).
5. 부팅 B의 NUL 검사를 부팅 A처럼 "크기를 두 번 잰다"로 쓰면 그 사이에 게스트가 쓴 줄이 차이로 잡혀 거짓으로
   빨개진다(실측 10). 부팅 B는 NUL 바이트를 한 번의 읽기로 센다.

## 비목표

1. 범위 `workspace`(같은 워크스페이스 안에서만 나눈다). 결정 2. 쓰는 사람이 생기면 `Workspace`의 칸 · 워크스페이스를
   닫는 자리의 해제 · `pick`의 셋째 갈래를 더한다.
2. 클립보드가 terminal의 재시작이나 재부팅을 넘는 것. 공유 칸은 terminal 프로세스와 같은 수명이다. 마지막 패널을 닫으면
   init이 terminal을 되살리고 칸은 비어서 시작한다(CB 전과 같다).
3. OSC 52(자식이 클립보드를 쓰고 읽는다). PD 비목표 16 · PE 비목표 3 그대로다. 클립보드가 화면 밖에서 오게 되면 PE 비목표
   1(`encodePaste`)과 함께 연다.
4. 다른 프로세스와의 클립보드(시리얼 콘솔 셸 · ssh 세션 · 호스트의 시스템 클립보드). 프로세스 사이의 클립보드가 없다
   (CM과 같다).
5. 클립보드 상한. PE design 위험 1 그대로다.
6. 실행 중에 범위를 바꾸는 키나 명령. 범위는 부팅에 한 번 정해진다.
7. 클립보드 기록(여러 칸을 두고 지난 것을 고르는 것).

## 착수 전에 실측한 것

planner가 2026-10-05에 HEAD `5acc735`를 저장소 밖 사본(`/tmp/run/cb0/repo/`)에 떠서 코드를 읽고 쟀다. 같은 날 EL-M0이
`dfd761a`로 commit된 뒤 plan의 편집을 그 HEAD에 맞춰 다시 뽑았다(plan 확정 1). 아래 줄 번호와 값은 `5acc735`의 것이다. 저장소의 작업 트리는
이 design과 plan 말고는 한 글자도 안 바뀌었다. 줄 번호는 HEAD의 값이고 참고용이다.

1. 클립보드는 패널마다 따로다(요청의 전제와 다르다). 근거는 둘이다. 코드 — `vt.Screen.clip`(`vt.zig:294`) 한 칸이고,
   `spawnPane`(`main.zig:1309`)이 패널마다 `vt.Screen.init`을 부른다. 실행 — plan의 mutation 1(`Clips.of`가 범위를 무시하고
   늘 패널 칸을 준다)이 CB 전의 동작과 같고, 그 판에서 같은 워크스페이스의 다른 패널에 `Cmd+V`하면 `clip> paste empty`가
   찍혔다.

2. 만지는 자리. `vt.zig`의 `clip` 칸(294) · `deinit`의 해제(554) · `findPaste`(1291) · `copyYank`(1991) · `clipboard()`(2019).
   `main.zig`의 `dumpPaste`(1218) · `dumpFindPaste`(1249) · 포인터 뗌(2108) · 키보드 `y`(2539) · `Cmd+V`의 갈래(2557~2559)와
   패널을 닫는 두 자리(EOF 경로 · 끝의 `defer`). `vt_test.zig`에서는 lead가 적은 자리(482~594 · 715 · 1783~1880)에 더해
   검사 59의 `findPaste`(1900)와 PD-M2의 검사 97~101(2628~2711)이 `copyYank`를 부른다 — 함께 고쳤다.

3. argv. `Child.argv: [8:null]`(`init/src/main.zig:374`)이고, terminal의 리터럴이 여덟 칸을 다 쓴다. 같은 타입이 콘솔
   셸(1052) · 서비스(1093) · `CHRONYD_ARGV`(`clock.zig:84`) · `DHCPCD_ARGV`(`net.zig:123`) · `WIFI_ARGV`(`wifi.zig:24`)다.
   terminal은 `args[1]`~`args[7]`을 읽는다(`main.zig:2164~2215`). init의 `*_test.zig`에는 argv 길이를 보는 검사가 없다.

4. `tars-init: config` 줄을 grep하는 자리(`rg -n 'tars-init: config|config shell=' */check.sh`). `config` · `net` · `power` ·
   `input` · `firewall` · `hangul`(`.*toggles=…( |$)` 포함) · `machine`(`config ` 뒤 파이프의 `hangul=sebeol_3p3`) · `tools`(실패
   마커)다. `install`이 보는 `config storage …`는 다른 줄이다. 줄 끝에 앵커한 것은 없다. `hangul/check.sh` 314행 근처의 주석이
   적은 일(SC-M0이 줄 끝을 옮겨 그 체인의 끝 앵커가 깨졌다)은 그 뒤 `( |$)` 경계로 고쳐져 있다.

5. seed 파일. `5acc735`에서 `config.save`의 출력이 40줄이었고(머리 1 · 키 열의 주석과 값), EL-M0(`dfd761a`)이 `esc_latin`
   네 줄을 더해 44줄, 이 design이 네 줄을 더해 48줄이다. `MAX_FILE`(4096바이트) 안이다 — `config` 체인 1차 부팅이 seed를
   만들고 `tars-config`로 읽는다(regression).

6. 모드 2004는 `Terminal`마다다(`vt_test` 검사 95 · 96, PE design 실측 2). 그래서 `pasteParts`는 `Screen`에 남는다. pane
   체인의 fish는 두 부팅 모두 모드를 켰다 — `clip> paste len=12 bracketed=1`.

7. 포트. `pane` 45487 · `pointer` 45488 · 45489이고 lessons가 "새 체인은 45490부터"라 적었다. 부팅 B가 45490을 쓴다.

8. 컴파일러가 잡는 것과 못 잡는 것. 리터럴 길이(`[9:null]`에 여덟 칸)는 컴파일 에러다. 범위 이름의 짝(init ↔
   terminal)은 못 잡는다(결정 3).

9. 시간. 같은 사본 · 따뜻한 캐시에서 `pane/check.sh` 한 회전이 HEAD 판 33초, plan 판 43 · 43 · 44초였다. 이 기계에서는
   lessons의 "2~4분"보다 훨씬 짧다 — 값보다 차이(약 10초, 부팅 하나)를 본다.

10. 처음 짠 부팅 B의 NUL 검사가 한 판 거짓으로 빨갰다. 부팅 A의 모양(`tr -d '\0'`의 크기와 `wc -c`의 크기를 따로 잰다)을
    따랐는데, 부팅 B는 마지막 Enter 직후라 두 읽기 사이에 게스트가 프레임 덤프를 썼다. 그 판의 로그를 꺼내 `tr -cd '\000'`로
    세니 NUL은 0이었다. plan은 한 번의 읽기로 센다(위험 5).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄.
- `docs/decisions/project_clipboard_scope.md`를 만들고 `MEMORY.md`에 한 줄. 요청의 전제(워크스페이스)와 실제(패널)의 차이,
  `workspace` 범위를 안 둔 이유를 담는다.
- 다시 연 결정에 한 줄씩 덧붙인다. CM design 결정 1("클립보드의 주인은 CB가 `main.zig`로 옮겼다")과 WP design 비목표
  "패널 간 복사"("CB가 채웠다, 기본 `shared`"). 각각 `[[project_clipboard_scope]]`. `project_copy_mode.md`의 선행 조건 3과
  `project_workspace_panes.md`에도 한 줄.
- `docs/guides/running-tars.md`의 `tars.conf` 키 설명에 `clipboard=`.
- `docs/guides/lessons.md`. 포트 목록(45490은 pane 체인 부팅 B, 새 체인은 45491부터), "로그 문구는 두 곳에 중복된다"에
  `terminal: clipboard scope=`와 `config … clipboard=`, 핵심 파일 지도에 `clipboard.zig`.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 결정 1(선택과 클립보드는 `vt.zig`) · 결정 8(로그 문구). 결정 1이 그
  뒤 절반을 바꾼다
- `docs/specs/2026-10-03-tars-workspace-panes-design.md` — 비목표 "패널 간 복사" · 결정 7(`screen>`은 포커스 패널만)
- `docs/specs/2026-10-04-tars-paste-ergonomics-design.md` — 결정 2 · 3 · 4(`pasteParts` · 세 조각 · `bracketed=`) · 실측 2(모드는
  `Terminal`마다) · 비목표 1 · 3
- `docs/specs/2026-09-09-tars-find-paste-design.md` — `findPaste`가 첫 줄만 넣는 이유
- `docs/specs/2026-08-31-tars-hangul-input-design.md` — 결정 7(argv로 자판을 넘긴다)
- `docs/decisions/project_seeding_a_config_disk.md` — 부팅 B의 디스크
- `docs/decisions/project_gate_screen_echo.md` — 판정 글자와 친 글자
