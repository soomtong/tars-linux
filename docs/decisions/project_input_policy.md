---
name: project_input_policy
description: "키 입력은 evdev 코드를 셸이 이미 아는 바이트로 번역한다(IP-M0~M2, TR-M2) · macOS 조합은 readline · zle 기본 바인딩으로(A안, 설정 없이 동작해야 게이트가 본다) · chord가 specialKey보다 먼저 · 키보드 차이는 맨 앞의 코드 교환(56↔125, 100↔126) 한 번 · 설정 파서는 PID 1 한 벌 · 반환은 바이트열 또는 동작 · Ctrl/Shift+방향키와 Cmd+C/V는 일부러 비어 있다"
metadata:
  node_type: memory
  type: project
---

Input Policy(IP-M0~M2, 2026-08-19)가 세웠고 TR-M2가 반환 타입을 넓혔다.
코드는 `terminal/src/input.zig`(`handleKey` · `chord` · `specialKey`), 호스트
검사는 `terminal/src/input_test.zig` · `init/src/config_test.zig`, 게이트는
`input/check.sh`다. 설계 전문은 `docs/specs/2026-08-15-tars-input-policy-design.md`.
milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋 이력에 있다).

## 번역의 기준은 "셸이 이미 아는 언어"다

`Option+←`를 `ESC b`로, `Cmd+←`를 `0x01`로 보낸다. 그것이 readline · zle의
기본 바인딩이기 때문이다. 우리가 새 시퀀스를 정하고 셸 설정으로 받게 하는
방식을 버린 이유는 검증이다 — A안만이 `--no-config` / `--norc` / `-f`로 뜬
셸에서 설정 파일 없이 동작하고, 그래야 게이트가 화면 덤프로 증명할 수 있다.

알고 들어간 어긋남: `Cmd+Backspace`의 `0x15`는 bash에서 커서 앞까지, zsh에서
줄 전체를 지운다. macOS는 bash 쪽이다. 셸을 바꿔 끼울 수 있는 시스템에서 A안의
대가이고 `chord()` 주석에 적어 뒀다.

## 파이프라인의 순서가 곧 정책이다

```
0. 키보드 보정(swapAltMeta)  ← ctx.swap_alt_meta일 때만
1. modifier 갱신             ← 물리 키 하나당 비트 하나, 좌우 독립 여덟 개
2. 조합 dispatch(chord)      ← 가로챌 것만 가로챈다
3. 기본 번역(specialKey → keymap)
```

2번이 3번보다 먼저여야 한다. 뒤에 두면 `Cmd+←`가 dispatch에 닿기 전에 `ESC [
D`로 번역돼 샌다. 이 순서를 지키는 검사가 따로 있다 — DECCKM이 켜진 문맥에서도
`Option+←`가 `ESC O D`가 아니라 `ESC b`인지 본다.

0번이 맨 앞이라 나머지가 키보드를 모른다. Apple과 PC는 스페이스 옆 두 키의
순서가 뒤집혀 있을 뿐이라(56↔125, 100↔126) 맨 앞에서 코드를 한 번 교환하면
`chord` · `keymap` · `specialKey`를 고칠 것이 없다. 인자는 `raw_code`, 보정된
값은 `code`로 둬서 보정 전 값을 쓰는 것이 의도인지 실수인지가 이름에 드러난다.

표에 없는 조합은 modifier를 무시하고 원래 키를 보낸다(`Option+b` → `b`,
`Cmd+C` → `c`). Ctrl이 마스크 대상이 아닌 문자를 다루는 규칙(`Ctrl+1` →
`1`)과 같다. Cmd와 Option이 둘 다 눌리면 Cmd가 이긴다 — 임의지만 결정적이어야
해서 `chord`가 Meta를 먼저 보는 한 곳에서 정하고 테스트가 못 박는다.

## 설정 파서는 한 벌뿐이다 (CP 구조의 두 번째 시험)

"파일을 읽는 것은 PID 1 하나"([[project_config_persistence]])를 지킨다.
`init`이 `Keyboard` enum으로 검증한 뒤 `apple`/`pc` 하나만 argv 넷째 자리에
넣고, `terminal`은 `std.mem.eql(u8, kb, "pc")` 한 줄로 받는다. enum을 복사하면
파서가 두 벌이 되고 두 프로세스가 같은 파일에서 다른 답을 얻을 수 있다.

`Child.argv`의 넷째 자리를 콘솔 셸은 `null`로 둔다 — execve가
첫 null에서 멈추므로 인자 수가 다른 자식이 같은 배열 타입을 쓴다. 이 인자가
셸로 새지 않는 것은 `terminal`이 셸 argv를 `{shell_path, shell_flag}`로 따로
조립하기 때문이다.

`config.zig`의 `parse`는 시스템 콜 없는 순수 함수라 `config_test.zig`(`zig
build test`)가 깨진 입력 아홉 가지가 전부 기본값으로 떨어지는 것("설정 하나로
부팅이 막히지 않는다")을 QEMU 없이 확인한다.

## TR-M2에서 반환이 "바이트열 또는 동작"으로 넓어졌다

스크롤 키는 바이트가 아니라 동작이고 PTY로 새면 안 된다.

```zig
pub const Scroll = enum { top, bottom, page_up, page_down };
pub const Action = union(enum) { bytes: []const u8, scroll: Scroll };
```

`Scroll`에 화면 크기가 없는 것이 요점이다. `page_up`이 몇 줄인지는
`input.zig`가 모르고 `main.zig`가 `rows`만큼의 delta로 바꾼다 — "`input.zig`는
`vt.zig`를 import하지 않는다"(design 결정 6)는 경계를 지킨다. 넓힌 것은
통로이고 모드 상태는 안 들어갔다([[project_copy_mode]]가 variant를 더한다).

가로채는 자리는 `chord()`의 Meta · Alt 분기보다 뒤다. 위 두 분기는 표에 없어도
`null`로 `chord`를 끝내므로 Cmd+Shift+PageUp은 스크롤하지 않고 맨 PageUp이
된다. Cmd는 copy mode가 예약한 자리라 여기서 뜻을 더하지 않았다.

`readKeys`의 두 결정:

- 스크롤을 배열로 모은다(`State.scrolls`, 여덟 칸, `seq`처럼 힙을 안 쓴다).
  마지막 하나만 남기면 자동 반복으로 여러 번 눌러도 한 화면만 올라간다.
- 루프 조건에서 `written < out.len`을 뺐다. 바이트 버퍼가 차서 이벤트 처리가
  멈추면 뒤따른 스크롤 키가 통째로 사라진다. 바이트를 버리는 것과 동작을 못
  보는 것은 다른 손실이다.

호스트 검사의 `expectCtx`는 `.scroll`이 오면 실패로 취급한다 — 무시하면
스크롤 키가 실수로 PTY 쪽 표에 들어가도 조용히 통과한다. "Shift를 떼면
PageUp/PageDown/Home/End가 원래대로 나간다" 네 줄이 없으면 셸이 Home/End를
영영 못 받는 회귀를 놓친다.

## 일부러 비워둔 자리

- `Ctrl+←`/`Shift+←`는 맨 `ESC [ D`로 샌다. `ESC [ 1 ; 5 D`가 필요한 TUI 앱이
  아직 없다. `State.seq` 8바이트 중 쓰는 것은 4바이트까지이고 6바이트 자리가
  이 형태의 몫이다.
- `Cmd+C`/`Cmd+V`가 `c`/`v`를 찍는다. 복사 · 붙여넣기는
  [[project_copy_mode]]의 몫이고 그때 `chord`의 Meta 갈래에 두 줄이 붙는다.
- `Option+글자`는 modifier가 무시된다. xterm의 `metaSendsEscape`냐 macOS
  특수문자 흉내냐는 비-US 레이아웃과 함께 볼 문제다.
- 시리얼 콘솔 셸은 이 정책을 안 받는다(커널 tty 계층이 처리한다). 두 셸의
  `TERM`이 다른 것(`xterm` vs `linux`)도 같은 이유다 —
  [[project_guest_environment]].
- 범용 키바인딩 엔진은 만들지 않았다. `keyboard=apple|pc`는 재배치가 아니라
  "스페이스 옆 두 키가 어느 순서인가"라는 하드웨어 선언이다.

## 게이트를 짤 때 쓸 수 있는 실측 사실

- QEMU `sendkey meta_l`은 게스트에 `KEY_LEFTMETA`(125)로 온전히 닿는다.
- `bash --norc`도 `fish --no-config`처럼 `smkx`를 안 보낸다. 게이트 로그는
  매번 `DECCKM stayed off`이고 `ESC O` 분기는 부팅 게이트가 못 밟는다. 처방은
  [[project_gate_chain_composition]].
- `terminal: key> N byte(s)`의 N이 경로를 특정한다 — 1 = 평문 또는 Cmd 조합,
  2 = Option 조합뿐, 3 = 맨 커서키, 4 = 틸드 계열. 화면이 맞아 보여도 우리가 안
  보냈을 가능성을 이 한 줄이 배제한다.
- 줄 처음에 무언가를 끼워 넣어 증명할 때는 `echo `를 끼운다. 글자 하나(`Y`)면
  `Yecho ...`가 되어 `command not found`라 화면 증거가 없다. 끼운 것이 명령
  자체가 되면 출력 행이 곧 증거이고 성공 경로가 하나뿐이다.

관련: [[project_gate_chain_composition]], [[project_config_persistence]],
[[project_guest_environment]], [[project_copy_mode]]
