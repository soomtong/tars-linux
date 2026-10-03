# Copy Indicator (CI) — copy mode를 상태 줄에 보여 주는 칸

착수 2026-10-03. 완료 2026-10-03 (CI-M0).

사용자의 요청 한 줄에서 시작했다 — "copy mode에 있을 때 화면 맨 아랫줄에
copy mode 표시를 보여 달라." copy mode는 키를 전부 삼키는데(CM design
결정 3) 모드에 들어갔다는 표시가 반전된 copy 커서 한 칸뿐이어서, 사람에게
그 상태는 "셸이 멈췄다"로 보였다.

- design: `docs/specs/2026-10-03-tars-copy-indicator-design.md`
- plan: `docs/plans/2026-10-03-tars-copy-indicator-ci-m0.md`

## 왜 상태 줄의 꼬리인가

IS가 세운 아래 여백의 상태 줄에 다섯째 칸 `COPY`를 더했다. 꼬리에 둔
이유는 앞 넷(`EN  신세벌 PCS  쿼티  CAPS`)이 한 칸도 안 움직이기 때문이다 —
IS 결정 2(자리 고정)가 그대로 서고, hangul 체인이 copy mode 밖에서 `text=`를
글자 그대로 비교하는 검사 셋도 그대로 선다.

맨 앞에 두면 모드에 들어가는 순간 넷이 여섯 칸 밀리고, 격자 마지막 줄의
오버레이에 두면 검색 프롬프트와 같은 줄이라 copy mode 안에서 `/`를 열면
겹친다.

## 왜 `CAPS`처럼 자리를 남기지 않는가

`CAPS`는 늘 두고 색만 바꾼다(IS 결정 3). `COPY`는 켜질 때만 뜬다. 둘은
성질이 다르다 — 대문자 잠금은 켜 둔 것을 잊어도 다른 흔적이 없어서 자리를
남겨야 했고, copy mode는 켜졌을 때만 뜻이 있는 모드다. vim이 normal에서
모드 이름을 안 적는 것과 같다.

실용적인 이유도 있다. 늘 두면 hangul 체인의 `text=` 비교 셋과 `ink fg=`
기준값이 전부 바뀐다. 켜질 때만 두면 copy mode 밖의 화면이 한 픽셀도 안
바뀐다.

## 왜 앰버를 재사용하지 않는가

`dumpStatus`는 띠 전체의 `STATUS_ON` · `STATUS_OFF` 픽셀을 세고 그 값을
`CAPS` 칸의 값으로 읽는다. 그 전제는 "여백 안에서 그 두 색은 `CAPS` 칸에만
쓰인다"다(IS-M1 plan 확정 3). `COPY`에 앰버를 쓰면 copy mode 안에서
`CAPS`가 꺼져 있어도 `on`이 0이 아니게 되고, 그 전제가 조용히 거짓이 된다.
그래서 전용 색 `STATUS_COPY`(`0x00E0E8F0`)다 — 그 덕에 게이트가 `COPY`
칸만 세는 넷째 줄 `status> copy ink=N`을 같은 방법으로 얻는다.

같은 색을 두 칸이 나눠 쓰면 "띠 전체를 센 값이 곧 그 칸의 값"이라는 싼
판정이 깨진다. 칸을 더할 때마다 색도 하나 더한다 — 그것이 x 범위를 재는
것보다 싸고 안전하다(IS-M1이 x 범위를 재지 않기로 한 이유가 그대로 유효하다).

## 순수 모듈은 bool을 받는다

`status.zig`는 `vt.zig`를 import하지 않는다. `*vt.Screen`을 받으면
`status_test`가 ghostty 패키지를 링크해야 하고 "상태를 넣고 문자열을 받는
순수 계산"이 깨진다. 그래서 `statusText(state, copy, buf)`이고, 값은
`main.zig`가 `screen.copyActive()`에서 읽는다. `Status` 구조체에도 같은
bool이 있다 — `drawStatus`가 `CAPS` 칸의 시작을 꼬리에서 세는데, 꼬리에
`COPY`가 붙어 있으면 `COPY_TAIL.len`만큼 더 물러나야 하기 때문이다. 이것을
문자열을 되읽어 `COPY`로 끝나는지로 알아내면 자판 이름에 그 넉 자가 들어오는
날 조용히 틀린다.

`MAX_LEN`은 36에서 42가 됐고, 버퍼를 손으로 늘린 자리는 없다 — IS 결정 5의
comptime 셈이 두 번째로 값을 한 자리다.

## 갱신 경로는 새로 없었다

copy 명령은 전부 `main.zig`의 copy 루프 끝에서 `needs_redraw`를 켠다. 들어가는
`.enter`, 나가는 `.exit` · `.yank`, 가지치기로 끊기는 `pruned` 전부가 그
프레임에 `statusText`를 다시 만든다. IS-M1이 `CAPS`에서 겪은 갱신 구멍은
여기 없었고, `dumpStatus`의 메모를 넓힐 일도 없었다 — `CAPS`와 달리 `COPY`는
글자 자체가 생기고 사라져서 `text`가 바뀐다.

## 검증 구조 — 판정이 짝이고 둘씩이다

| 자리 | 본다 |
|---|---|
| copy 체인 검사 2a(Cmd+Shift+C 뒤) | `text=`가 `  COPY`로 끝난다 · `copy ink>0` |
| copy 체인 검사 6a(Esc 뒤) | `text=`에 `COPY`가 없다 · `copy ink=0` |

켜지는 것만 보면 "영영 붙어 있는" 코드도 통과한다(IS-M1 plan 확정 7).
`text=`와 `ink`를 함께 보는 이유는 IS-M0의 검증 구조다 — `text=`만 보면
`drawStatus`가 꼬리를 안 그려도, `CAPS`의 색으로 한 칸 밀려 그려도 초록이다.
호스트에서는 `status_test` 검사 13(붙는다) · 14(밖에서는 어디에도 없다)가
같은 짝이다.

## CI-M0이 실행으로 증명한 것

값과 근거 전문은 design의 "CI-M0이 실측한 것" 절에 있다. 코드를 읽어서는
알 수 없는 것만 여기 남긴다.

1. 글자가 맞아도 색은 밀릴 수 있고, 그것은 `text=`로 안 보인다. 반사실에서
`drawStatus`가 `st.copy`를 무시하게 하자 `text=`는 `…CAPS  COPY`로 정확했고
`COPY`는 `CAPS`의 색으로 그려졌다. 잡은 것은 `copy ink=0`이다. 상태 줄처럼
"문자열을 만드는 층"과 "색을 고르는 층"이 갈린 자리에서는 판정도 둘이어야
한다 — IS-M0이 `ink fg=`를 넣은 이유가 칸 하나 더할 때 그대로 되풀이됐다.

2. 칸을 더할 때 색도 더해야 싼 판정이 산다. 띠 전체를 센 값을 "그 칸의 값"
으로 읽는 것은 그 색이 그 칸에만 쓰일 때만 맞다. 앰버를 재사용했으면
copy mode 안에서 `caps ink on`이 거짓이 됐고, 그것을 알아채는 검사는 없었다
(hangul 체인은 copy mode 안에서 `caps`를 안 본다).

3. "꺼진 화면이 안 바뀐다"는 기준값으로 증명된다. hangul 체인의 383 · 87이
그대로라는 것이 결정 2의 증거이고, 그 수가 바뀌었으면 꼬리에만 붙였다는
말이 틀린 것이다.

4. 한 번에 고치면 예고한 빨강을 못 본다. plan이 적어 둔 첫 실패(검사 10의
36 ≠ 42)는 `status.zig`와 `status_test.zig`를 함께 고쳐서 나타나지 않았다.
그래도 반사실 한 회전이 "일부러 실패를 본다"의 자리를 맡았다 — 그 빨강은
산수가 아니라 게이트의 눈을 증명하므로 더 값지다.

## 관련

- [[project_input_status]] — 상태 줄의 자리 · 색 · 검증 구조. 이 칸은 그 위에
  얹혔다
- [[project_copy_mode]] — 모드가 키를 삼키는 결정이 이 표시가 필요한 이유다
- [[project_gate_chain_composition]] — "게이트는 자기가 안 보는 것을
  통과시킨다". `text=`만으로는 색이 밀린 것을 못 본다
