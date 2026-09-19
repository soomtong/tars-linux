# TQ-M1 — 터미널이 질의에 답하게 하고, 씨앗의 우회를 지운다

> 이 plan을 실행하는 사람에게: 이 milestone은 **한 번 시작했다가 되돌린** 것이다
> (2026-09-19, 사용자가 "구현은 다음 세션에"라고 해서 코드를 커밋 `be9eab3`
> 상태로 되돌렸다). 아래 "이미 밟은 함정 둘"은 그때 실제로 막혔던 자리이고,
> 그 둘만 피하면 나머지는 설계대로 간다. 조사와 실측은 끝났다.

Goal: `effects.write_pty`를 채워 터미널이 자식의 질의(`ESC[6n` 커서 위치 등)에
답하게 하고, ST-M3이 넣은 우회(`FZF_DEFAULT_OPTS --no-height`)를 지운다.

Architecture: vendored ghostty의 `TerminalStream` handler에 이미 있는 한 칸을
채우고, 그 콜백이 만든 바이트를 자식에게 돌려준다. 답의 내용은 라이브러리
몫이고(포맷을 우리가 안 만든다), 우리 몫은 "답이 나가는 길"과 "무엇을 주장하는가"
(후자는 비목표).

Tech Stack: Zig 0.16(terminal) · 게이트는 bash + QEMU(sendkey) · initrd에 스크립트 하나

---

## Task 1 — effect를 걸고 답을 모은다

`terminal/src/vt.zig`:

```
const Handler = @FieldType(ghostty_vt.TerminalStream, "handler");
pub const REPLY_MAX = 512;
```

- `Screen`에 `reply_buf: [REPLY_MAX]u8` · `reply_len: usize` · `reply_dropped: usize`.
- `init`에서 `self.stream = self.term.vtStream();` **뒤에**
  `self.stream.handler.effects.write_pty = &onWritePty;`
  (라이브러리는 이 칸이 비면 답을 아예 안 만든다.)
- `onWritePty(h: *Handler, bytes: [:0]const u8)`는
  `@fieldParentPtr("term", h.terminal)`로 Screen을 되찾아 큐에 복사한다.
- `pushReply`: 들어갈 자리가 없으면 **통째로 버리고** `reply_dropped`를 세고
  로그 한 줄. 반쪽 답은 넣지 않는다.
- `pub fn takeReplies(self: *Screen) []const u8` — 전부 돌려주고 비운다.

## Task 2 — 자식에게 돌려준다

`terminal/src/main.zig`의 `screen.feed(out);` **바로 뒤**:

```
const replies = screen.takeReplies();
if (replies.len > 0) pty.write(session.master_fd, replies);
```

pty에 쓰는 자리가 여기 하나뿐이라 순서 문제가 없다(질의의 답이 그 뒤에 친
키보다 먼저 나간다).

## Task 3 — 단위 검사 (`terminal/src/vt_test.zig`)

이번에 이미 써서 통과시킨 넷을 그대로 넣는다(되돌렸으므로 다시 쓴다).

1. `ESC[6n` → 답이 **CPR 모양**(`ESC[`, `;` 포함, `R`로 끝남). 길이 6바이트였다.
2. `ESC[5n` → 답이 `ESC[0n` 꼴(4바이트).
3. 평범한 출력(`hello`) → 답 0바이트. 이 검사가 없으면 "모든 출력마다 답을
   만든다"가 위 둘을 통과한다.
4. `ESC[6n`을 200번 몰아치고 한 번도 안 비우면 → `reply_dropped > 0`이고
   남은 것이 `REPLY_MAX` 이하다. 그리고 그 뒤 `takeReplies()`가 0이다.

DA1(`ESC[c`)은 **검사에 넣지 않는다** — 답을 라이브러리가 못 만든다(임베더가
장치 속성을 선언해야 한다). design 비목표 1.

## Task 4 — 게이트 검사 (이번에 막힌 자리)

게스트가 질의를 보내고 답을 받는지 본다. `terminal/check.sh`의 `math 6 x 7`
검사 뒤, `exit`(재시작 경로) 앞에 넣는다.

**함정 1 — 질의 바이트를 타이핑으로 만들지 말 것.** `printf \033[6n`을
`type_keys`로 치면 이스케이프가 층층이 죽는다. 실측 화면:

```
root@(none) ~# bash -c 'printf \033[6n; read -n 20 -t 2 r; echo ${#r}'
033[6n0
```

리터럴 `033[6n`이 나갔다(ESC가 아니라 글자 여섯 개). 그래서 **ESC가 든 작은
스크립트를 initrd에 실어** 그 경로를 치게 한다 — `kernel/make_initrd.sh`가
dhcpcd hook을 싣는 것과 같은 방식이다.

새 파일 `tools/tq-probe.sh`(이름은 자유, 자리는 정한다):

```sh
#!/bin/sh
# 터미널이 질의에 답하는가 — 물어보기와 읽기가 같은 프로세스 안에 있어야 한다.
printf '\033[6n'
read -n 20 -t 2 r
printf 'len%d\n' "${#r}"
```

`make_initrd.sh`가 그것을 `$WORKDIR/usr/bin/tq-probe`(0755)로 넣고,
게이트는 경로만 친다:

```
type_keys t q minus p r o b e ret     ← /usr/bin/tq-probe 가 PATH에 있으므로 이름으로
```

판정 글자는 `\| len[1-9]`다. 답이 오면 `len6` 꼴, 안 오면 `len0`이다.

**함정 2 — 물어보기와 읽기가 같은 프로세스 안에 있어야 한다.** fish가 묻고
bash가 읽게 했더니 `len0`이 나왔다. 답은 pty의 **입력**이고, 그 사이에 프롬프트로
돌아온 셸의 라인 편집기가 먼저 가져가기 때문이다. 위 스크립트가 `printf`와
`read`를 한 프로세스에서 하므로 이 함정을 피한다.

## Task 5 — 우회를 지운다

- `init/src/config.zig`: 씨앗 셋에서 `set -gx FZF_DEFAULT_OPTS --no-height` ·
  `export FZF_DEFAULT_OPTS='--no-height'`와 그 주석 블록을 지운다.
- `init/src/config_test.zig`: `KNOWN_SEED_ENV`와 `envs` 계상·검사를 지운다
  (그 줄이 없으면 `envs == 0`이 실패하게 되어 있다).
- `config/check.sh`의 ST-M3 picker 검사는 **그대로 둔다** — 이제 그것이
  "40% 상자가 뜬다"를 뜻한다(그 검사가 `--no-height`를 전제하지 않는다).

## Task 6 — 돌린다

| 순서 | 명령 | 무엇을 보는가 |
|---|---|---|
| 1 | `docker run ... -w /workspace/terminal ... zig build test` | 새 단위 검사 넷 |
| 2 | `./terminal/check.sh` | 호스트 검사 + 부팅 1에서 `len[1-9]` |
| 3 | `./config/check.sh` | picker가 첫 Ctrl+R에 뜬다(우회 없이) |
| 4 | `./check.sh` | 루트 게이트 12체인 × 3회 |

2가 초록이면 이 서브프로젝트의 질문("터미널이 답하는가")이 닫힌다. 3이 초록이면
그 답이 fzf의 `--height`를 실제로 살렸다는 증거다.

## 이번에 확인된 것 (다시 재지 말 것)

- `write_pty` 한 칸이면 CPR(`ESC[6n`)과 DSR(`ESC[5n`)의 답이 나온다 — 단위
  검사로 확인했다(6바이트·4바이트).
- DA1(`ESC[c`)은 그 한 칸으로 **안 된다**(0바이트). 임베더가 장치 속성을
  선언해야 만든다 — design 비목표 1.
- `time fzf --version`은 34ms다(게스트 TCG). fzf가 멈추는 것은 느려서가 아니라
  답을 기다려서다(ST-M3 실측).
