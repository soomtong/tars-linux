---
name: project_input_policy
description: "키 입력은 evdev 코드를 셸이 이미 아는 바이트로 번역하는 일이다 — macOS 조합은 ESC 접두사/제어 문자로 옮기고(A안), 물리 키보드 차이는 파이프라인 맨 앞의 코드 교환 한 번으로 흡수하며, 설정 파서는 PID 1 한 벌만 두고 argv로 흘린다; 범용 키바인딩 엔진은 만들지 않았고 Ctrl/Shift+방향키와 Cmd+C/V 자리는 일부러 비어 있다"
metadata:
  node_type: memory
  type: project
---

Input Policy(IP-M0~M2)가 2026-08-19에 끝났다. 시작 시점의 TARS 키보드는
Shift 하나만 아는 상태였고, 끝난 시점에는 Ctrl 제어 문자 · 특수키 ·
`TERM=xterm` · macOS 편집 의미론 · `keyboard=apple|pc`가 전부 게이트로
증명된다. 설계 전문은
`docs/superpowers/specs/2026-08-15-tars-input-policy-design.md`.

## 번역의 기준은 "셸이 이미 아는 언어"다

`Option+←`를 `ESC b`로, `Cmd+←`를 `0x01`로 보낸다. 이 매핑에 무슨 대응
관계가 있어서가 아니라 **그것이 readline·zle의 기본 바인딩이기 때문**이다.
후보였던 다른 방식(우리가 새 시퀀스를 정하고 셸 설정으로 받게 하는 것)을
버린 결정적 이유는 **검증**이다 — A안만이 `--no-config`/`--norc`/`-f`로 뜬
셸에서 설정 파일 없이 동작하고, 그래야 게이트가 화면 덤프로 증명할 수 있다.
프롬프트를 예측 가능하게 하려고 no-config로 띄우는 것과 같은 제약이
매핑 설계까지 규정한 셈이다.

**알고 들어간 어긋남 하나:** `Cmd+Backspace`가 보내는 `0x15`는 bash에서
커서 앞까지, zsh에서는 줄 전체를 지운다. macOS는 bash 쪽 동작이다. 셸을
바꿔 끼울 수 있는 시스템에서 이것이 A안의 대가이고, 감추지 않고
`chord()` 주석에 적어뒀다.

## 파이프라인의 순서가 곧 정책이다

`handleKey`는 네 단계를 이 순서로 지난다.

```
0. 키보드 보정(swapAltMeta)  ← ctx.swap_alt_meta일 때만
1. modifier 갱신             ← 물리 키 하나당 비트 하나, 좌우 독립 여덟 개
2. 조합 dispatch(chord)      ← 가로챌 것만 가로챈다
3. 기본 번역(specialKey → keymap)
```

**2번이 3번보다 먼저여야 한다.** 뒤에 두면 `Cmd+←`가 dispatch에 닿기 전에
특수키 조회에서 `ESC [ D`로 번역돼 새어 나간다. 이 순서를 지키는지 검사하는
줄이 따로 있다 — DECCKM이 켜진 문맥에서도 `Option+←`가 `ESC b`이지
`ESC O D`가 아니라는 검사다. 순서가 뒤집히면 그 줄이 먼저 터진다.

**0번이 맨 앞이라 나머지가 키보드를 모른다.** Apple과 PC는 스페이스 옆 두
키의 순서가 정확히 뒤집혀 있을 뿐이므로(56↔125, 100↔126), 맨 앞에서 코드를
한 번 교환하면 `chord`도 `keymap`도 `specialKey`도 고칠 것이 없다. 뒤로
갈수록 "여기도 보정해야 하나"를 물어야 하는 곳이 늘어난다. 인자 이름을
`raw_code`로 바꾸고 보정된 값을 `code`로 둔 것은, 아래에서 보정 전 값을
쓰는 것이 의도인지 실수인지가 이름에 드러나게 하기 위해서다.

**표에 없는 조합은 modifier를 무시하고 원래 키를 보낸다.** `Option+b`는
`b`, `Cmd+C`는 `c`다. Ctrl이 마스크 대상이 아닌 문자를 다루는 방식
(`Ctrl+1` → `1`)과 같은 규칙이다. **Cmd와 Option이 둘 다 눌리면 Cmd가
이긴다** — 임의의 선택이지만 결정적이어야 해서 `chord`가 Meta를 먼저 보는
것 한 곳에서만 정하고, 테스트가 그 순서를 못 박는다.

## 설정 파서는 한 벌뿐이다 (CP 구조의 두 번째 시험)

`keyboard=apple|pc`를 더하면서 CP가 정한 "파일을 읽는 것은 PID 1 하나"가
두 번째 키에도 버티는지 확인됐다. `init`이 `Keyboard` enum으로 검증한 뒤
`apple`/`pc` 둘 중 하나만 argv 넷째 자리에 넣고, `terminal`은
`std.mem.eql(u8, kb, "pc")` **한 줄**로 받는다 — enum을 복사하면 그 순간
파서가 두 벌이 되고 두 프로세스가 같은 파일에서 다른 답을 얻을 수 있다.

`Child.argv`가 `[3:null]`에서 `[4:null]`로 늘었지만 콘솔 셸은 그 자리를
`null`로 둔다. execve가 첫 null에서 멈추므로 인자 수가 다른 자식이 같은
배열 타입을 쓸 수 있다. 이 인자가 셸로 새지 않는 이유는 `terminal`이 셸에
넘기는 argv를 `{shell_path, shell_flag}` 둘로 **따로 조립**하기 때문이다.

**`config.zig`의 `parse`에 단위 검사가 생긴 것이 부수 소득이다**
(`init/src/config_test.zig`, `zig build test`). 시스템 콜이 없는 순수
함수인데 그때까지 QEMU를 띄워야만 검증됐다. 깨진 입력 아홉 가지가 전부
기본값으로 떨어지는 것 — CP가 "설정 하나로 부팅이 막히지 않게 하는 장치"라고
부른 성질 — 을 0.1초에 확인한다. 처음 돌렸을 때 잠복 버그는 없었다.

## 일부러 비워둔 자리

- **`Ctrl+←`/`Shift+←`는 여전히 맨 `ESC [ D`로 샌다.** `ESC [ 1 ; 5 D`를
  넣을 이유가 있는 TUI 앱이 아직 하나도 없다. `State.seq`가 8바이트인데
  실제로 쓰는 것은 4바이트까지이고, 6바이트 자리가 이 형태의 몫이다.
  **IP-M1의 주석이 "M2가 이 줄을 바꾼다"고 예고했으나 틀렸다** — M2도 안
  했고, 그 주석을 고치는 것이 M2의 Step 하나였다.
- **`Cmd+C`/`Cmd+V`가 `c`/`v`를 찍는다.** 복사·붙여넣기는 스크롤백과
  클립보드가 선행 조건이라 [[project_copy_mode]]의 몫이고, 그때 `chord`의
  Meta 갈래에 두 줄이 붙는다.
- **`Option+글자`는 modifier가 무시된다.** xterm의 `metaSendsEscape`를 켤지
  macOS의 특수문자 입력을 흉내낼지는 비-US 키보드 레이아웃과 함께 볼 문제다.
- **시리얼 콘솔 셸은 이 정책을 전혀 안 받는다.** 그쪽 입력은 커널 tty 계층이
  처리하며 우리 코드를 지나지 않는다. 같은 기계 안에서 두 셸의 `TERM`이
  다른 것(`xterm` vs `linux`)도 같은 이유다 — [[project_guest_environment]].
- **범용 키바인딩 엔진은 만들지 않았다.** `keyboard=apple|pc`는 재배치가
  아니라 **하드웨어 선언**이다 — "스페이스 옆 두 키가 어느 순서인가"라는
  사실 하나를 알려주는 것이지 사용자가 키를 임의로 옮기는 문이 아니다.

## 게이트를 짤 때 쓸 수 있는 실측 사실

- **QEMU `sendkey meta_l`은 게스트에 `KEY_LEFTMETA`(125)로 온전히 닿는다.**
  IP-M2 착수 시점의 최대 미지수였는데 1차 부팅에서 바로 확인됐다.
- **`bash --norc`도 `smkx`를 보내지 않는다.** `fish --no-config`와 같다 —
  게이트 로그는 매번 `DECCKM stayed off`이고 `ESC O` 분기는 부팅 게이트가
  영영 못 밟는다. 처방은 [[project_gate_chain_composition]].
- **`terminal: key> N byte(s)` 줄의 N이 경로를 특정한다.** 이 범위에서
  1 = 평문 또는 Cmd 조합, 2 = **Option 조합뿐**, 3 = 맨 커서키, 4 = 틸드
  계열이다. 화면이 맞아 보여도 우리가 안 보냈을 가능성을 이 한 줄이 배제한다.
- **게이트에서 무언가를 줄 처음에 끼워 넣어 증명할 때는 `echo `를 끼운다.**
  글자 하나(`Y`)를 끼우면 `Yecho ...`가 되어 `command not found`가 나므로
  "제대로 동작했다"의 화면 증거가 없다. 끼운 것이 명령 자체가 되면 출력 행이
  곧 증거이고 성공 경로가 하나뿐이 된다.

관련: [[project_gate_chain_composition]], [[project_config_persistence]],
[[project_guest_environment]], [[project_copy_mode]]
