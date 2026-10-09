---
name: project_terminal_rendering
description: "화면이 색 · 한글 · 스크롤백을 갖게 한 층(TR-M0~M2, 2026-08-23). 색 · 반전 · 커서 · 글리프 오프셋은 vt.zig 하나가 확정하고 렌더러는 숫자만 받는다. 함정 — 팔레트는 xterm 고전값이 아니다 · style_id 0은 읽지 않는다 · inverse는 라이브러리가 안 해 준다 · 스크롤백 한도는 값 둘을 함께 줘야 걸린다 · 새 출력이 뷰포트를 안 내리는 것은 라이브러리의 성질이다 · 폭 2칸과 색은 두 겹으로 본다"
metadata:
  node_type: memory
  type: project
---

TR-M0~M2(2026-08-23)가 세운 것이다. design은
`docs/specs/2026-08-23-tars-terminal-rendering-design.md`. milestone별 경과와
게이트 시간은 2026-10-10에 지웠다(커밋 이력에 있다). 그 뒤 렌더러에 더해진
것 — 그래픽은 [[project_terminal_graphics]], 커서 모양은 [[project_cursor_shape]],
프레임 비용은 [[project_render_cost]], 최적화 모드는 [[project_gate_latency]].

## 색이 해소되는 자리는 `vt.zig` 하나다

렌더러는 팔레트도 SGR도 inverse도 커서도 모른다. `vt.zig`의 `cells()`가
셀마다 `fg` · `bg`를 프레임버퍼와 같은 `0x00RRGGBB`로 확정해 넘기고
`main.zig`는 칠하기만 한다. inverse와 커서가 "두 색을 맞바꾼다"는 같은
연산이라 둘 다 여기서 사라지고, 뷰포트 밖으로 나가면
`state.cursor.viewport`가 null이라 스크롤백을 붙일 때 커서를 다시 손대지
않았다. 글리프 오프셋도 같다 — stb의 `yoff`(baseline 기준 음수)를
`Cache.find`가 `ascent_px`를 더해 셀 위쪽 모서리 기준으로 바꿔 담고 렌더러는
baseline을 모른다.

## 라이브러리에 대해 짐작하면 틀리는 것

- 팔레트가 xterm 고전값이 아니다. 빨강이 `#CD0000`이 아니라 `#CC6666`, 밝은
  빨강이 `#D54E53`이다. 게이트가 기대하는 값이 이것이다.
- `style_id == 0`이면 `style`을 읽으면 안 된다(라이브러리가 계약으로 명시).
  기본값에서 `styles[x]`를 읽으면 쓰레기다. `lib_vt.zig`가 `style` 모듈을
  안 내보내 코드에는 숫자 `0`을 쓰고 출처를 주석으로 적었다.
- `inverse`는 라이브러리가 처리해 주지 않는다. `Style.fg()`도 `Style.bg()`도
  이 플래그를 안 본다 — `\e[7m`은 `fg=#FFFFFF, bg=null, inverse=true`로
  그대로 온다.
- `\e[1;31m`처럼 bold가 붙으면 팔레트 1번이 아니라 9번이다. `Style.fg()`에
  `.bold = .bright`를 준 결과이고, 폰트가 하나라 bold를 표현하는 유일한 길이다.
- `Terminal.Options.max_scrollback_lines`만 주면 아무 일도 안 일어난다. 기본
  `max_scrollback_bytes`(10,000)가 먼저 걸리는데 그 값은 활성 영역의 최소값보다
  작아 처음부터 무시되고 있었다. `bytes = null, lines = 1000`을 함께 준다. 155×47
  격자에서 history가 754~1000줄 사이를 오가는 것은 정상이다 — 가지치기가
  페이지(약 286줄) 통째로 일어난다.
- 새 출력이 뷰포트를 안 내리는 것은 라이브러리의 성질이다. PTY 출력이
  도착하는 자리에서 `scrollToBottom()`을 우리가 부른다. 그 한 줄이 덤으로
  "뷰포트가 history에 머무는 동안 가지치기가 pin을 무효로 만드는" 상황을
  구조적으로 없앤다.
- 스크롤 API의 variant 이름이 층마다 다르다. 부르는 것은
  `Terminal.scrollViewport`(`.bottom` · `.delta` · `.top` · `.row`)이고
  `PageList.Scroll`(`.active` · `.delta_row`)이 아니다. 위치는
  `pages.scrollbar()`의 `{total, offset, len}`이고 "바닥에 있다"는 `offset ==
  total - len`이다 — 게이트와 호스트 검사가 전부 이 식을 쓴다.
- `RenderState`는 뷰포트를 따라간다(`update()`가 `getTopLeft(.viewport)`에서
  시작). 스크롤한 뒤 `cells()`를 부르면 옛 줄이 그대로 나오므로 `cells()`는
  손댈 것이 없었다.

## 문턱값 렌더링은 게이트를 위한 선택이기도 하다

글리프를 알파 블렌딩하지 않고 `coverage > 127`로 찍는다. 비트맵 폰트를
native 16px로 구워 coverage가 이분값인 것이 첫째 이유이고, 블렌딩하면 기대
픽셀 값이 래스터라이저에 매달려 `pixel>` 검사가 상수와 비교할 수 없게 되는
것이 둘째다. 이 선택이 거꾸로 폰트를 고르는 기준이 됐다
([[project_font_selection]]). 이분값 덕에 사슬 전체가 무손실이다 — 호스트에서
구운 `한`의 잉크 개수와 게이트가 게스트 프레임버퍼에서 되읽은 합이 한 개도
안 틀렸다. 같은 이유로 게이트는 글자가 있는 셀이 아니라 배경색을 칠한
공백을 검사한다 — 글자가 있으면 중앙 픽셀이 획일 수 있다.

## 두 겹으로 봐야 하는 것 — 색 · 폭 2칸 · 스크롤

- 한글은 "파서가 폭 2로 셌는가"와 "렌더러가 두 칸을 칠했는가"가 따로 틀리고,
  셀 하나만 보는 검사는 둘째를 못 잡는다(반쪽만 그려도 잉크는 있다). `ink>`가
  셀의 왼쪽 8픽셀과 오른쪽 8픽셀을 따로 세고(`right=0`이면 반쪽), 파서 쪽은
  한글 뒤에 배경색 공백을 붙여 그 `style>` 좌표가 "한글 열 + 2"인지 본다.
- 스크롤은 `scroll>`(위치)과 화면을 나란히 본다. 위치만 보면 뷰포트는
  움직였는데 화면은 그대로인 상태를 못 잡고, 화면만 보면 어디로 갔는지
  모른다. 렌더가 PTY 출력 분기 안에만 있던 것을 `needs_redraw` 플래그와 루프
  끝의 렌더 블록으로 바꾼 이유가 이것이다 — 스크롤은 키로 일어난다. 플래그는
  그리는 횟수를 안 늘리기 위한 것이고([[project_gate_latency]]의 관측 대기가 이
  조용함에 기댄다), modifier 키처럼 아무것도 안 바꾸는 이벤트에서는 안 그린다.
- 배경색이 생긴 뒤로는 글자가 없어도 그릴 것이 있어 `cells()`가 `codepoint ==
  0`인 셀도 내보낸다. 그 결과 `dumpScreen`이 NUL을 로그에 흘린 적이 있고
  `render/check.sh`의 음성 검사가 지킨다. NUL 한 바이트는 `grep`을 통째로
  막으므로(`Binary file ... matches`) 체인의 모든 `grep`에 `-a`를 붙였다. 검출은
  `grep -qP '\x00'`이 아니라(안 잡힌다) 한 번 읽기 `tr -cd '\0' | wc -c`다
  ([[project_atomic_log_lines]]가 두 번 읽기를 거짓 빨강으로 고쳤다).

## 죽은 검사 · 죽은 필드는 틀려도 아무도 모른다

`font_test.zig`는 `build.zig`에 등록조차 안 되어 있었고, `vt_test`는 x86_64로
빌드되어 "빌드만 되고 아무도 실행하지 않는" 채 두 서브프로젝트를 건너왔다
(호스트 타깃으로 옮기자마자 통과했다 — libghostty-vt는 aarch64에서 잘 돈다).
`Glyph.cell_width`의 `> 0x7F` 규칙이 `é`에서 틀려 있었는데 아무도 읽지 않는
필드라 화면에 나타난 적이 없었다. 남은 "빌드만 되는 검사"는 `pty_test`
하나다 — 게스트용 x86_64 fish를 exec하므로 호스트로 못 옮긴다.

## 게이트에서 한글과 긴 출력을 만드는 법

`sendkey`는 ASCII만 치므로 한글은 셸의 `printf`로 만든다 — fish의 `printf`가
`\x`를 해석한다(`printf '\xed\x95\x9c\033[41m \033[0m\n'`). 화면보다 많은 줄은
`seq 200`이다 — 게스트에 `seq` 바이너리는 없어도 fish가 함수로 갖고 있고,
60줄이면 한 번의 `page_up`이 맨 위에 닿아 `.top`과 구분되지 않는다. 화면
내용은 `| 1 |`이 한 줄 전체와 일치한다는 성질로 본다(`dumpScreen`이 행
사이에 ` | `를 넣으므로 `10` · `21`에는 안 걸리고, 첫 행은 `screen> 1 |`).
스크롤 키 이름은 `shift-pgup` · `shift-pgdn` · `shift-home` · `shift-end`다.

## 그 밖의 함정

- `setPixel`도 `getPixel`도 범위 검사를 하지 않는다(`drm.zig`). 오프셋으로
  좌표가 음수가 될 수 있으므로 `drawGlyph`와 `dumpInk`가 호출부에서 막는다.
  `font_test`의 "한글 11172자가 전부 셀 안에 들어간다"는 폰트에 대한 사실이지
  코드의 성질이 아니다.
- 폰트 캐시가 lazy인 이유는 메모리가 아니라 시간이다. 11172자를 전부 구워도
  2.07MB이고 게이트가 실제로 쓴 양은 1,665바이트인데, 굽는 데 Debug 396ms ·
  ReleaseFast 46ms(컨테이너 arm64 native)이고 게스트는 TCG라 그 위에 몇십
  배다. 시간을 적을 때는 최적화 수준을 함께 적는다 — "29.3ms"로만 적어 둔
  ReleaseFast대의 수가 한동안 근거로 남아 있었다.
- 게이트 시간은 기계가 한가할 때만 잰다. TR-M2를 끝내며 처음 잰 값이 8배였고
  Chrome의 영상 재생(`pmset -g log`의 `Video Wake Lock`)이 원인이었다 — 판정은
  멀쩡했다. 값이 기준선에서 크게 벗어나면 코드보다 기계를 먼저 의심한다.
- 체인 하나를 더하는 비용은 커널 빌드만 세면 과소평가한다(TR 체인은 예상의
  두 배였다 — libghostty-vt를 arm64로 한 벌 더 빌드하고 타이핑이 붙는다).
  있는 체인에 검사를 더하는 것은 거의 공짜다.

## 관련 기억

[[project_gate_chain_composition]] · [[project_guest_environment]] ·
[[project_kernel_config]] · [[project_build_host_arch]] · [[project_copy_mode]] ·
[[project_font_selection]] · [[project_terminal_graphics]] ·
[[project_cursor_shape]] · [[project_render_cost]] · [[project_atomic_log_lines]]
