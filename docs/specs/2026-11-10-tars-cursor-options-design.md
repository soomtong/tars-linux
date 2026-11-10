# TARS Cursor Options — Design

접두사: CO

Date: 2026-11-10
Status: 초안(2026-11-10). plan은 `docs/plans/2026-11-10-tars-cursor-options-co-m0.md` · `docs/plans/2026-11-10-tars-cursor-options-co-m1.md`.

계기: 사용자(2026-11-10, fakesteak 데모를 점검하다가): "full screen mode에서 cursor가 계속 빠르게 깜빡이는게 눈에 거슬리는데 기술적으로
쉽게 해결할 수 있는 방법이 있을까? 1. 커서 숨김 모드를 제공 2. 내가 모르는 어떤 스펙이 있는지 확인". 조사 결과 2였다 — 표준 시퀀스
DECTCEM이 있고 fakesteak은 이미 보내는데 우리 렌더러가 안 본다. 사용자가 그 방향을 골랐다("좋아"). 이어서 깜빡임과 모양 변경의 분량을
물은 뒤 정했다(2026-11-10): "CPU 비용을 아끼는 것은 중요하다. 깜빡임 기능은 제외하고, 커서 모양 변경 기능은 이번 태스크에 포함하자."

관련 문서: CU design(`2026-10-04-tars-cursor-shape-design.md` — 비목표 1 깜빡임 · 4 DECTCEM · 9 `tars.conf` 키가 이 일의 출발점), HI design
결정 4(preedit 두 칸 반전), DR-M3 plan(커서 층의 dirty 행), FU design(화면 키 하나가 init → argv → terminal로 가는 가장 최근 선례),
BS design 결정 8(이벤트가 없으면 CPU를 안 쓴다).

## 한 줄 요약

둘이다. 패널의 프로그램이 `CSI ? 25 l`로 커서를 숨기면 셸 커서를 그리지 않는다(CO-M0). 프로그램이 모양을 정하지 않았을 때의 모양을
사용자가 `tars.conf`의 `cursor_shape=block|bar|underline`으로 고른다(CO-M1). 깜빡임은 하지 않는다.

## 확인 (2026-11-10, HEAD `ae3dca6`)

1. fakesteak(soomtong/fakesteak = domsson/fakesteak 0.2.4와 같은 소스)은 `cli_setup()`에서 `ESC[?25l`, `cli_reset()`에서 `ESC[?25h`를
   보낸다. 프레임마다 `ESC[H` 하나를 보내고 칸 전체를 줄바꿈 없이 쓴다(자동 줄바꿈에 기댄다). 기본 `-s 10`이면 100ms마다 한 프레임.
   커서 표시에 관한 옵션은 없다.
2. lib-vt는 DECTCEM을 모드 25(`cursor_visible`, 기본 true, `ghostty-src/src/terminal/modes.zig:376`)로 기록하고,
   `RenderState.update`가 매 프레임 `state.cursor.visible`에 옮긴다(`render.zig:608`).
3. 우리 렌더러는 그 값을 안 본다. 셸 커서는 `vt.Screen.computeShellCursor`(`terminal/src/vt.zig:1086`) 하나가 정하고, 반전(block)과
   `main.zig`의 띠(bar · underline)와 `cursor>` 로그가 모두 그 결과(`shell_cursor`)를 본다(CU design 결정 3).
4. 우리 terminal에는 깜빡임 타이머가 없다(CU 비목표 1). 사용자가 본 "빠른 깜빡임"은 깜빡임이 아니라 커서 자리의 이동으로 본다 —
   한 프레임(160×50칸과 색 시퀀스, 수 KB)이 PTY read 여러 번에 나뉘어 들어오고 read마다 그리면, 그 순간의 커서 자리(쓰는 중인 칸,
   또는 `ESC[H`의 왼쪽 위)에 흰 반전 칸이 찍힌다. `-b`의 검은 바탕 위라 더 잘 보인다. 이 추정은 결정과 상관없다 — 숨긴 커서를
   안 그리면 어느 쪽이든 사라진다.
5. preedit 글자의 치환(`cp = pcp`)은 `shell_cursor`와 상관없이 커서 자리에 일어나고, 두 칸 반전만 `invert_cursor`(곧 `shell_cursor`)가
   정한다(`vt.zig` `cells()`의 커서 층).
6. 커서 층의 dirty 행은 `cur_spot`(`shell_cursor`에서 나온다)의 변화로 잡힌다(DR-M3). `dirty_test.zig:169`가 이미 `?25l/h`를 무작위로
   먹인다 — 지금까지는 그 조작이 층을 안 바꿨고, 이제부터 바꾼다.
7. lib-vt의 `Terminal.Options`에 `default_cursor_style`(기본 `.block`, `Terminal.zig:301`)이 있다. DECSCUSR `0`(과 빈 인자) · RIS · DECSTR이
   이 값으로 돌아간다(`setCursorStyle(.default)`, `:440`). 실행 중에 바꾸는 `setDefaultCursorStyle`(`:466`)도 있다 — 프로그램이 모양을
   정해 둔 동안에는 그 모양을 안 덮고 다음 `0`까지 기억만 한다. 우리 `vt.Screen.init`은 이 옵션을 안 준다(`vt.zig:539`).
8. 모양은 화면(기본 · 대체)마다 따로다(CU 실측 10). 1049로 대체 화면에 들어가면 기본 화면의 커서를 복사하고, 나올 때 기본 화면의
   `cursor_style`은 건드리지 않는다. 그래서 vim이 대체 화면에서 무엇을 남겨도 셸 프롬프트는 들어가기 전의 모양이다.
9. `tars.conf`의 화면 키는 다섯 자리를 지난다(FU-M0의 `fullscreen=`): `shared/screen_args.zig`(`Slot` 14번까지, `ARGC = 15`) ·
   `init/src/config.zig`(필드 · 파싱 · 기본 파일의 주석 줄) · `init/src/reload.zig`의 `term` 갈래(빠뜨리면 컴파일 에러) · `init/src/main.zig`
   (argv · `config` 줄 · `reload terminal` 줄) · terminal(argv를 읽어 쓰는 자리). terminal에서 `vt.Screen.init`을 부르는 자리는
   `spawnPane`(`main.zig:1696`) 하나다.
10. 깜빡임의 비용(사용자에게 보인 검토, 2026-11-10). 그리는 일은 싸다(CO-M0의 숨김과 같은 조건 · 커서 한 행의 부분 갱신). 비싼 것은
    가만히 있는 동안에도 초당 두 번 깨는 것(BS 결정 8), 그 프레임마다 시리얼 콘솔에 덤프 열두 가지가 나가는 것(`dumpFrame`
    `main.zig:5070`), 그리고 "할 일이 없으면 로그가 조용하다"는 게이트의 전제(CU 결정 2)다.

## 결정

1. `computeShellCursor`에 조건 하나: `state.cursor.visible`이 false이고 preedit이 없으면 null. 놓는 자리는 copy mode · 포커스 · 뷰포트
   검사 뒤, 모양 계산 앞이다. null이면 반전도 띠도 없고, `cursor>` 줄은 지금 있는 꼴 그대로 `vt=<모양> drawn=none`이다.
2. preedit이 있으면 숨김을 무시하고 두 칸 block을 그린다. 두 칸 반전은 커서이기 전에 "아직 확정 안 된 글자"의 표시다(HI 결정 4) —
   반전이 빠지면 조합 중인 글자가 화면의 글자와 구별이 안 된다. 커서를 숨긴 프로그램 위에서 한글을 조합하는 일은 드물지만, 그때
   글자가 안 보이는 것보다 커서 모양이 보이는 쪽이 낫다.
3. copy 커서는 숨김과도 기본 모양과도 상관없다. copy mode는 우리 기능이고 언제나 block이다(CU 결정 4).
4. 로그 형식은 바꾸지 않는다. `vt=block drawn=none`이 "라이브러리는 block을 들었는데 우리가 안 그렸다"를 이미 말한다 — 이유가 포커스
   없음인지 숨김인지는 게이트가 앞뒤 사건으로 구분한다.
5. 키는 `cursor_shape`, 값은 `block | bar | underline`, 기본 `block`(CO 전과 같다). 이름은 DECSCUSR의 모양 이름 그대로다. 화면 키라
   `reload terminal` 갈래이고 argv의 새 칸 하나(15번, `ARGC = 16`)다.
6. terminal은 그 값을 lib-vt의 `default_cursor_style`로 준다. 우리 렌더러는 손대지 않는다 — 렌더러는 이미 lib-vt가 든 모양을 그린다.
   그러니 뜻은 xterm과 같다: 프로그램이 DECSCUSR로 모양을 정하면 그것을 따르고, `CSI 0 SP q`(와 빈 인자) · RIS가 오면 사용자의 모양으로
   돌아간다. vim(CU-M1의 시스템 vimrc)은 대체 화면에서만 모양을 바꾸므로 vim을 나오면 프롬프트는 사용자의 모양이다(확인 8).
7. 깜빡임은 하지 않는다 — 사용자의 결정. DECSCUSR의 깜빡임 번호와 모드 12는 지금처럼 같은 모양을 가만히 그린다(CU 결정 2). 기본
   파일의 주석에 "깜빡이지 않는다"를 적지 않는다 — 없는 기능을 안내하지 않는다.

## 비목표

- 깜빡임(결정 7). 다시 열려면 확인 10의 셋을 먼저 풀어야 한다.
- 커서 숨김을 `tars.conf`의 키로 강제하는 것(사용자가 처음 낸 1안). 셸 커서까지 사라진다. DECTCEM으로 지금 문제가 풀린다.
- 두께 · 색을 키로 빼는 것(CU 비목표 9의 나머지). 두께 2px · `CURSOR_COLOR`는 게이트의 ink 값이 기대는 상수다(CU 결정 1).
- 실행 중에 단축키로 모양을 바꾸는 것. lib-vt의 `setDefaultCursorStyle`이 있어 길은 열려 있지만 쓰는 사람이 없다.
- 포커스 없는 패널의 속 빈 커서(CU 비목표 5), OSC 12 커서 색(CU 비목표 3).
- fakesteak 쪽을 고치는 것. 이미 표준대로 보낸다.

## 위험

1. 셸(fish)이 `?25l`을 남긴 채 프롬프트로 돌아오는 경우가 있으면, "셸 커서 반전 셀이 정확히 1개"를 세는 게이트(render 검사 3 · 20,
   hangul 등)가 0을 본다. 지금은 렌더러가 숨김을 무시해서 이 일이 가려져 있을 수 있다. 루트 게이트 한 판이 판정이다.
2. 프로그램이 숨긴 채 죽으면(SIGKILL 등) 셸 커서가 계속 안 보인다. xterm · ghostty와 같은 동작이고, `reset` 또는 `printf '\e[?25h'`로
   돌아온다. 받아들인다.
3. 셸이나 rc가 DECSCUSR을 보내면 사용자의 모양을 덮는다. 셸 셋은 안 보낸다(CU 실측 8, render 검사 20이 지킨다). 그래도 덮는 프로그램이
   생기면 그것은 그 프로그램의 요청이라 따르는 것이 맞다.
4. 기본 모양이 bar · underline이면 게스트의 게이트가 세는 "셸 커서 반전 1개"가 0이 된다. 기본값이 block이고 게이트의 부팅은 그 키를
   안 쓰므로(CO-M1의 부팅만 쓴다) 기존 판정은 그대로다.

## Milestone

- CO-M0: 결정 1~4. 호스트 검사(vt_test), render 체인 판정 둘, fakesteak QEMU probe.
- CO-M1: 결정 5~7. 설정 키 다섯 자리, 호스트 검사(config · screen_args · vt), 설정 디스크로 띄우는 부팅 하나, 안내 `docs/help/config.md`.
