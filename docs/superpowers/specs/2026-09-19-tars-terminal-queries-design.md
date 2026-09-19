# TARS Terminal Queries — Design

접두사: TQ

Status: 열렸다(2026-09-19). 착수 전 조사가 끝났다(ST-M3이 이 자리를 찾았다) —
아래 "착수 전에 읽은 것"이 그 결과다. M1부터.

관련 문서: `2026-09-19-tars-shell-tools-design.md`(ST. 증상을 재고 우회를 넣은
서브프로젝트 — 아래에서 "ST-M3"은 그 milestone이다) ·
`2026-09-11-tars-terminal-foundation-design.md`(TF. terminal 바이너리와 PTY) ·
`2026-09-13-tars-terminal-rendering-design.md`(TR. vt와 렌더러) ·
`docs/decisions/project_terminal_queries.md`(증상·측정을 적어 둔 기억)

## 한 줄 요약

터미널이 자식의 질의에 답하게 한다 — 커서 위치(`ESC[6n`)·장치 속성(DA1) 등.
그러면 fzf의 `--height` 상자가 돌아오고, ST-M3이 넣은 우회 한 줄을 지운다.

## 왜 지금인가

ST-M3이 사용자의 신고("Ctrl+R을 두 번 눌러야 열린다")를 재서 원인을 찾았다 —
fzf는 `--height`일 때 터미널에 커서 위치를 묻고 답이 올 때까지 그리지 않는데,
우리 terminal이 **vt의 질의 콜백을 하나도 등록하지 않아** 답이 없다. 그때는
씨앗에 `FZF_DEFAULT_OPTS --no-height`를 넣어 우회했고, zoxide의 `zi`는 그
우회도 안 먹어서 아직 첫 누름에 멈춘다(ST-M3 실측: `_ZO_FZF_OPTS`로만 산다).

우회의 대가는 셋이다. picker가 전체 화면이 되고, `zi`는 따로 손대야 하고,
질의를 쓰는 다른 도구(vim의 색 질의 등)는 그대로 멈춘다. 셋 다 없애는 것이
이 서브프로젝트다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — 창구는 라이브러리에 이미 있다

우리가 쓰는 Zig 바인딩은 vendored ghostty의 `src/lib_vt.zig`이고, 그 안의
`TerminalStream`(= `stream.Stream(Handler)`)이 handler를 공개 필드로 들고 있다
(`stream.zig:477`). 그 handler에 effect 콜백 묶음이 있다.

```
stream_terminal.zig:73   pub const Effects = struct {
stream_terminal.zig:78       write_pty: ?*const fn (*Handler, [:0]const u8) void,
stream_terminal.zig:155      .write_pty = null,      ← 기본값(.readonly)
```

`write_pty`가 null이면 라이브러리가 답을 **아예 만들지 않는다** — 응답 갈래
여럿이 이 한 필드를 문지기로 본다(`stream_terminal.zig:186` · `:365` ·
`:523` · `:841` · `:928` · `:966` · `:983`). 그래서 고치는 일이 "그 한 칸을
채우는 것"으로 좁혀진다.

### 확인 2 — 답의 내용은 우리가 만들지 않는다

포맷(CPR의 행·열, DA1의 문자열)은 라이브러리 몫이다. 벤더 예제가 그 사용법을
그대로 보여준다 — `example/c-vt-effects/src/main.c:8`의 `on_write_pty`와,
"Feed VT data that triggers effects … triggers write_pty with the response"
(같은 파일 `:110`). 우리가 지는 것은 **바이트를 자식에게 전달하는 일**뿐이다.

### 확인 3 — 전달할 길도 이미 있다

```
terminal/src/pty.zig:86     pub fn write(fd: c_int, bytes: []const u8) void
terminal/src/main.zig:1325  screen.feed(out);          ← 여기가 답이 생기는 자리
terminal/src/main.zig:1165  pty.write(session.master_fd, keys.bytes);   ← 키가 나가는 길
```

`screen.feed(out)`은 poll 루프 안이고, 그 자리에서 `session.master_fd`도 손에
있다. 그래서 새 자리를 만들 필요가 없고, **pty에 쓰는 주체도 늘지 않는다**
(feed 직후 그 자리에서 쓰면 된다 — 순서가 자연스럽다: 질의의 답이 그 뒤에
친 키보다 먼저 나간다).

### 확인 5 — DA1은 라이브러리가 못 만든다 (실측)

`write_pty`만 채운 상태에서 `ESC[6n`(커서 위치)은 답이 오고 `ESC[5n`(상태
보고)도 오는데, `ESC[c`(DA1)는 **0바이트**다. DA1의 답은 임베더가 자기
장치 속성을 선언해야 만들어진다 — 그래서 비목표 1로 뺐다. M1이 답하는 것은
"답이 나가는 길이 열렸다"까지이고, 그 길로 나가는 답 중 fzf가 쓰는 것은
커서 위치다.

### 확인 4 — 우리 handler의 주소에서 Screen을 되찾을 수 있다

콜백은 `*Handler`를 받는다. `Screen.init`이 `self.stream = self.term.vtStream()`
로 만들므로 `handler.terminal`은 `&self.term`이다 — `@fieldParentPtr("term",
h.terminal)`로 `*Screen`이 나온다. 전역 변수 하나를 두지 않아도 된다.

## 결정

### 1. `write_pty` 하나만 채운다

다른 effect(벨·클립보드·알림·진행률·제목)는 안 건드린다. 지금 동작이 그대로
유지되고, 그중 제목 보고(`title_report`)는 라이브러리 기본이 꺼짐이다 —
pty로 제목을 되돌려 보내는 것은 입력 스트림에 글자를 심는 일이라 켜지 않는다.

### 2. 답은 Screen 안의 고정 버퍼에 모은다 — 힙을 안 쓴다

답 하나는 십여 바이트이고, 답이 쌓이는 것은 프로그램이 질의를 몰아칠 때뿐이다.
512바이트 고정 버퍼로 두고, 통째로 안 들어가면 **버리고 로그를 남긴다**.
반쪽 답을 넣는 것이 더 나쁘다 — 파서가 그 반쪽을 답으로 읽어 도구가 어긋난다.

### 3. pty에 쓰는 자리는 하나로 유지한다

답은 `screen.feed(out)` 바로 뒤에서 `pty.write`로 나간다. 새 스레드도 새 큐도
없다. 확인 3이 그 자리가 이미 있다는 것을 보여준다.

### 4. 씨앗의 우회를 지운다

ST-M3이 넣은 `FZF_DEFAULT_OPTS --no-height`를 세 씨앗에서 지우고
`KNOWN_SEED_ENV` 기계도 함께 지운다. ST-M3의 게이트 검사("첫 Ctrl+R에 picker가
뜬다")는 **그대로 둔다** — 그때는 그것이 40% 상자를 뜻하게 된다(그 검사가
`--no-height`를 전제하지 않는다는 것이 M3 설계의 값이다).

### 5. 게이트는 답 자체를 본다

`terminal/check.sh`가 게스트에서 `printf '\033[6n'`을 치고 `read -t 2 -n 20`으로
답을 받아 **길이**를 찍는다(`R<n>`). 답이 오면 `n > 0`, 안 오면 0이다.
정확한 문자열을 박지 않는 이유: 포맷은 라이브러리 몫이라 정확 문자열을 박으면
우리가 아니라 vendored 코드를 검사하게 된다. 답이 왔다는 사실이 우리 몫이다.

## 비목표

1. **장치 속성(DA1/DA2/DA3)·XTVERSION 보고.** 이것들은 라이브러리가 만들지
   못한다 — 임베더가 "나는 무엇인가"를 선언해야 만들어진다(장치 속성 콜백).
   실측: `write_pty`만 채운 상태에서 `ESC[c`의 답은 **0바이트**다. 선언은
   도구에게 기능을 켜게 하는 일이라(vim·tmux가 DA1을 보고 갈래를 고른다),
   무엇을 주장할지 정하는 것이 이 서브프로젝트보다 큰 물음이다.
2. **XTWINOPS 크기 보고**(in-band resize, mode 2048). 그 답은 `resize()`가
   만들어지는데 우리는 pty 크기를 시작할 때 한 번 정하고 안 바꾼다.
2. 벨·클립보드·데스크톱 알림·진행률·제목 보고. 지금 동작 그대로 둔다.
3. kitty graphics·마우스·포커스 이벤트(`lib_vt`가 갖고 있지만 이 기계의
   화면에는 그 도구가 없다).
4. 실기·게이트 밖의 검증. RM·DI와 같다 — 판정은 QEMU 안에서 닫는다.

## 위험

1. **답이 화면에 새는가.** 답은 자식에게 가는 입력이라 화면에 안 그려진다.
   게이트가 그것을 함께 본다(`R<n>`이 화면에 찍히는 것은 *우리가* 친 명령의
   출력이고, 답 바이트 자체는 화면 어디에도 안 나타난다).
2. **재진입.** 콜백은 `feed`가 도는 동안 불린다. 큐에 쓰기만 하고, 큐를 읽는
   것은 `feed`가 끝난 뒤다 — 순서가 코드 모양으로 고정된다.
3. **넘칠 때 조용한가.** 드롭은 로그 한 줄을 남긴다. 그 줄이 보이면 그때
   버퍼를 키운다(지금 크기의 근거는 "질의 하나의 답이 십여 바이트"다).
4. **우회를 지운 뒤의 40% 상자.** 그 상자는 프레임을 더 그리므로 렌더 비용이
   는다(RC-M0이 `fill`이 한 프레임의 84.7%라고 쟀다). 체감은 실측으로 남긴다.

## Milestone

| | 무엇 | 판정 |
|---|---|---|
| M1 | `effects.write_pty`를 채우고 답을 pty로 보낸다 · 단위 검사 · 게이트 검사 하나 · 씨앗 우회 제거 | terminal·config 체인 · 루트 게이트 |

## 다음

M1의 plan. 실측이 더 필요하면(예: vim이 실제로 질의를 하는가) 그때 잰다.
