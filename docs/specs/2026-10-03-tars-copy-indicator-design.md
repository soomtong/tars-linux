# TARS Copy Indicator — Design

Date: 2026-10-03
Status: 끝났다(CI-M0, 2026-10-03). copy mode에 있는 동안 상태 줄 꼬리에
`COPY`가 뜨고 Esc로 나가면 사라진다. plan은
`docs/plans/2026-10-03-tars-copy-indicator-ci-m0.md`, 값은 아래 "CI-M0이
실측한 것" 절에 있다.

사용자의 요청 한 줄에서 시작한다(2026-10-03): "copy mode에 있을 때 화면
맨 아랫줄에 copy mode 표시를 보여 달라."

## 한 줄 요약

copy mode에 있는 동안 상태 줄(IS)의 꼬리에 다섯째 칸 `COPY`가 뜬다. 모드를
나가면 사라진다. 앞 넷은 한 칸도 안 움직인다.

```
  EN  신세벌 PCS  쿼티  CAPS            ← 평소
  EN  신세벌 PCS  쿼티  CAPS  COPY      ← copy mode
```

## 왜 지금인가

copy mode는 키를 전부 삼킨다(CM design 결정 3 — `q w e r t`도 Enter도 PTY로
안 나간다). 그런데 모드에 들어갔다는 표시는 반전된 copy 커서 한 칸뿐이다.
커서가 스크롤백 위쪽에 있거나 셀 하나의 반전을 못 알아보면, 사람에게 그
상태는 "셸이 멈췄다"로 보인다. Cmd+Shift+C를 모르고 눌렀을 때가 특히 그렇다.

IS가 아래 여백에 상태 줄을 세워 뒀고(2026-09-09), 그 줄은 이미 "지금 켜져
있는 것을 잊었다"를 푸는 자리다. copy mode는 그 줄이 보여 줄 넷째 상태다.

## 결정

### 결정 1 — 자리는 상태 줄의 꼬리이고, 앞 넷은 안 움직인다

| 후보 | 왜 아닌가 |
|---|---|
| 격자 마지막 줄의 오버레이(`find> overlay`처럼) | 검색 프롬프트와 같은 줄이다. copy mode 안에서 `/`를 열면 둘이 겹친다 |
| 상태 줄 맨 앞 | 모드에 들어가는 순간 앞 넷이 여섯 칸 밀린다. IS 결정 2(자리 고정)가 깨지고, 사람이 늘 보던 자리가 흔들린다 |
| 상태 줄 꼬리 | 앞 넷이 그대로다. hangul 체인이 copy mode 밖에서 `text=`를 글자 그대로 비교하는 검사 셋(`hangul/check.sh` 366 · 448)도 그대로 선다 |

### 결정 2 — 켜질 때만 뜬다. `CAPS`처럼 자리를 남기지 않는다

IS 결정 3은 `CAPS`를 늘 두고 색만 바꿨다. 여기서는 그 길을 안 간다.

둘은 성질이 다르다. 대문자 잠금은 켜 둔 것을 잊어도 다른 흔적이 없어서
자리를 남겨야 했다. copy mode는 켜졌을 때만 뜻이 있는 모드이고, 꺼진 모드의
자리를 남겨 봐야 "지금 normal이다"를 말하는 것뿐이다 — vim이 normal에서
모드 이름을 안 적는 것과 같다.

실용적인 이유도 있다. 늘 두면 hangul 체인의 `text=` 비교 셋과 `ink fg=`
기준값(383 · 381)이 전부 바뀌어 다시 재야 한다. 꼬리에 켜질 때만 두면 copy
mode 밖의 화면이 한 픽셀도 안 바뀐다.

### 결정 3 — 색은 새 상수 `STATUS_COPY`다. 앰버를 재사용하지 않는다

IS-M1의 `caps ink` 판정은 띠 전체에서 `STATUS_ON` · `STATUS_OFF` 픽셀을
세고, 그 값을 `CAPS` 칸의 값으로 읽는다. 그 전제는 "여백 안에서 그 두 색은
`CAPS` 칸에만 쓰인다"다(`dumpStatus` 주석 · IS-M1 plan 확정 3). `COPY`에
앰버를 쓰면 copy mode 안에서 `on`이 `CAPS`가 꺼져 있어도 0이 아니게 되고,
그 전제가 조용히 거짓이 된다.

전용 색이면 게이트가 `COPY` 칸만 세는 넷째 줄 `status> copy ink=N`을
같은 방법으로 얻는다. 값은 `0x00E0E8F0`이다 — 여백(`0x102030`)과
`STATUS_FG`(`0x808890`)보다 밝아 눈에 띄되, 셀의 기본 전경(`0xFFFFFF`)과는
다른 값이라 격자 안 글자와 섞여 세이지 않는다(상태 줄은 격자 밖이라 섞일
일이 없지만, 같은 값을 피하는 쪽이 조사할 때 덜 헷갈린다).

### 결정 4 — `statusText`가 `copy: bool`을 하나 더 받는다

`status.zig`는 `vt.zig`를 import하지 않는다. `*vt.Screen`을 받으면
`status_test`가 ghostty 패키지를 링크해야 하고, "상태를 넣고 문자열을 받는
순수 계산"(IS 결정 5)이 깨진다. bool 하나면 `status_test`가 지금처럼
호스트에서 초 단위로 돈다.

값은 `main.zig`가 `screen.copyActive()`에서 읽어 넘긴다. `Status` 구조체에도
`copy: bool`이 생긴다 — `drawStatus`가 `CAPS` 칸의 시작을 꼬리에서 세는데,
꼬리에 `COPY`가 붙어 있으면 그 길이만큼 더 물러나야 하기 때문이다.

`MAX_LEN`은 36에서 42가 된다. 이름 표에서 comptime에 세는 값이라 버퍼를
손으로 늘리는 자리는 없다(IS 결정 5의 못이 여기서 한 번 더 값을 한다).

### 결정 5 — 갱신 경로는 새로 안 만든다

copy 명령은 전부 `needs_redraw`를 켠다(`main.zig`의 copy 루프 끝). 들어가는
`.enter`, 나가는 `.exit` · `.yank`, 가지치기로 끊기는 `pruned`(render 안에서
처리된다) 전부가 그 프레임에 `statusText`를 다시 만든다. IS-M1이 `CAPS`에서
겪은 갱신 구멍(`Action.hangul`이 `nothing`을 돌려줘 안 다시 그린 것)은 여기
없다.

### 결정 6 — 로그는 넷째 줄 하나, 판정은 copy 체인에 짝으로

`dumpStatus`가 찍을 때(값이 바뀔 때, IS 결정 9) `status> copy ink=N`을
함께 찍는다. 들어가고 나가는 것이 `text=`를 바꾸므로 메모를 넓힐 일은
없다 — IS-M1의 `caps` 메모가 필요했던 것은 `CAPS`가 글자를 안 바꿨기
때문이고, `COPY`는 글자 자체가 생기고 사라진다.

판정은 `copy/check.sh`에 둘이다.

| 자리 | 본다 |
|---|---|
| 검사 2 뒤(Cmd+Shift+C 뒤) | 마지막 `text=`가 `  COPY`로 끝난다 · `copy ink>0` |
| 검사 6 뒤(Esc 뒤) | 마지막 `text=`에 `COPY`가 없다 · `copy ink=0` |

둘이 짝이어야 하는 이유는 IS-M1 plan 확정 7과 같다 — 켜지는 것만 보면
"영영 켜져 있는" 코드도 통과한다. `text=`와 `ink`를 함께 보는 이유는 IS-M0의
검증 구조다 — `text=`만 보면 `drawStatus`가 꼬리를 안 그려도 초록이다.

## 검증

### 호스트 — `status_test`

- 검사 13: `copy=true`면 줄이 `  COPY`로 끝나고 칸이 다섯이다.
- 검사 14: `copy=false`면 `COPY`가 어디에도 없다(검사 1~12는 전부 이 쪽이다).
- 검사 10을 고친다: 가장 긴 줄은 `copy=true`일 때이고 그것이 `MAX_LEN`과
  정확히 같다(42).

### 게이트 — `copy/check.sh`에 판정 둘(결정 6). 키를 하나도 안 더한다

진입과 Esc는 이미 체인에 있다. 판정만 그 자리 뒤에 끼운다.

hangul 체인도 copy mode에 들어간다(SH 검사, 823행 뒤). 그 뒤에는 `status>`
판정이 없으므로 깨질 자리가 없다 — 그래도 체인을 한 번 돌려 확인한다.

## Milestone

### CI-M0 — `COPY` 칸이 뜨고 사라진다

이 서브프로젝트는 milestone 하나다. `status.zig` · `status_test.zig` ·
`main.zig` · `copy/check.sh` 넷을 고치고 루트 게이트를 돈다.

## 위험

1. hangul 체인이 copy mode 안에서 `status_text`를 비교하는 자리가 있으면
   그 검사의 기대값이 틀려진다. 착수 전에 확인했다 — 비교 셋(366 · 448)과
   `caps` 판정 넷(379 · 668 · 697)은 전부 823행(첫 `meta_l-shift-c`) 앞이다.
2. `drawStatus`가 꼬리에서 `CAPS`의 시작을 세는 산수가 `copy`를 안 보면
   copy mode 안에서 `CAPS` 넉 자가 `STATUS_FG`로, `COPY`가 `CAPS`의 색으로
   그려진다. 증상이 "색이 한 칸 밀렸다"라 글자만 보면 안 보인다 — copy
   체인의 `copy ink>0` 판정이 이것을 잡는다(그 색으로 그려진 픽셀이 0이 된다).
3. 첫 프레임 비용은 안 늘어난다. `COPY`는 ASCII 넉 자이고 부팅 직후에는
   안 그려진다.

## CI-M0이 실측한 것

2026-10-03. 값은 `copy/check.sh` 한 회전과 `hangul/check.sh` 한 회전, mutation
한 회전, 루트 게이트에서 왔다.

1. `COPY` 칸의 픽셀은 80이다(`status> copy ink=80`). `CAPS` 칸의 `off=87`과
   같은 자릿수다 — 둘 다 ASCII 넉 자를 같은 `drawRun`으로 그린 값이고, 차이
   7은 글리프 모양(`C O P Y`와 `C A P S`)의 차이다. Esc 뒤에는 0이다.

2. mutation이 위험 2를 그대로 재현했다. `drawStatus`의 `tail_len`을 0으로
   박아 `st.copy`를 무시하게 하고 캐시를 컨테이너 안에서 지운 뒤 copy 체인을
   한 번 돌렸다. `text=`는 `EN  신세벌 PCS  쿼티  CAPS  COPY`로 맞게 찍혔고,
   검사 2a가 `ink=0`으로 빨갰다 — `COPY` 넉 자가 `CAPS`의 색으로 그려진
   것이다. `text=`만 보는 판정이었으면 이 고장이 초록으로 통과했다. 결정 6이
   `text=`와 `ink`를 함께 보게 한 이유가 값으로 확인됐다.

3. copy mode 밖의 화면은 한 픽셀도 안 바뀌었다(결정 2). hangul 체인의
   기준값 `ink fg=383` · `caps ink off=87`이 착수 전과 같다.

4. plan이 예고한 첫 빨강(검사 10의 36 ≠ 42)은 보지 않았다. `status.zig`와
   `status_test.zig`를 한 번에 고쳐서 빨간 상태가 없었다. 대신 mutation(2)이
   "일부러 실패를 본다"의 자리를 맡았다 — 호스트 검사의 빨강은 산수가
   맞는지를, mutation의 빨강은 게이트가 무엇을 보는지를 말하므로 뒤의 것이
   더 값지다.

5. 갱신 경로를 하나도 안 만들었다는 것이 로그 줄 수로 보인다. copy 체인
   한 회전에서 `status>` 줄은 들어갈 때와 나올 때만 바뀌었고, 메모를 넓힌
   자리가 없다 — `COPY`는 글자가 생기고 사라져서 `text`가 바뀌기 때문이다.

6. 루트 게이트: 17체인 3/3 PASS(`FAIL` 0줄), 약 1시간 2분(mutation 끝 18:45:51 → 게이트 끝 19:48:02로 셌다 — 게이트 로그에 시각이 없다). TG-M3 뒤의 1시간 1분 25초와 같은 자리다. copy 체인 세 회전 모두 `COPY` 픽셀 80 → 0

## 비목표

- 검색 프롬프트가 열려 있음(`find` 모드)을 따로 표시하기 — 프롬프트 자체가
  화면에 있다.
- 선택 중(`v` · `V`)을 표시하기 — 선택이 반전으로 보인다.
- 색 · 글자를 설정으로 빼기.

## 관련

- `docs/specs/2026-09-02-tars-input-status-design.md` — 상태 줄의 자리 · 색 ·
  검증 구조. 이 design은 그 위에 칸 하나를 더한다
- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 모드가 키를 삼키는 결정 3
- `docs/decisions/project_input_status.md` — `status.zig`가 따로 서는 이유
