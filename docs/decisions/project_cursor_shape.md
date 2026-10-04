---
name: project_cursor_shape
description: vim의 insert는 bar, replace는 underline, normal은 block이다 — 렌더러가 DECSCUSR 모양 셋을 그리고(CU-M0), 게스트 vi를 vim.basic으로 바꿔 시스템 vimrc 세 줄과 stub defaults.vim을 initrd에 넣었다(CU-M1). 2026-10-04 종료. 새 체인 없이 render 체인 검사 20~32가 본다
metadata:
  type: project
---

Cursor Shape(CU)는 2026-10-04에 M0 · M1로 닫혔다. 사용자의 요청 한 줄("vi에서
입력 모드에 따른 커서 모양이 항상 동일해서 불편함이 있다")에서 시작했다. 원인은
둘이었고 둘 다 고쳤다.

- design: `docs/specs/2026-10-04-tars-cursor-shape-design.md`
- plan: `docs/plans/2026-10-04-tars-cursor-shape-cu-m0.md` · `docs/plans/2026-10-04-tars-cursor-shape-cu-m1.md`

## 무엇이 바뀌었나

- 렌더러(CU-M0). `vt.zig`의 `cells()`가 셸 커서를 한 번 정해 `shell_cursor`에 두고,
  block이면 반전, bar · underline이면 `main.zig`가 2픽셀 띠를 전용 색
  `CURSOR_COLOR`(`0xF0F0F0`)로 칠한다. 깜빡임은 안 그린다. 게이트는 매 프레임의
  `terminal: cursor> vt=… drawn=… row=… col=… cols=… ink=… box=…`로 세 층을 본다.
- 게스트 vi(CU-M1). sysroot의 `vim-tiny`를 `vim`(바이너리 `vim.basic`)으로 바꿨고
  `libsodium.so.23` · `libgpm.so.2`가 따라온다. `kernel/guest_tools.sh`의 한 줄이
  `usr/bin/vim.basic:usr/bin/vim`이고, `vi` · `editor`는 여전히 링크다.
- 시스템 vimrc. 저장소의 `kernel/vim/vimrc`가 initrd의 `/etc/vim/vimrc`가 된다. 내용은
  `t_SI`(6) · `t_SR`(4) · `t_EI`(2) 세 줄이다. 사용자 vimrc가 없으면 vim은 그대로
  `compatible`이라 커서 말고는 안 바뀐다.
- stub. `kernel/vim/defaults.vim`(주석뿐)이 `/usr/share/vim/vim91/defaults.vim`이 된다.

## 다시 조사하지 말 것

- `vim-tiny`는 `-cursorshape`로 빌드돼 있다. `t_SI`를 어떻게 설정해도 한 바이트도
  안 보낸다. 컴파일 시점의 기능이라 설정으로는 못 켠다(design 실측 2).
- 셸 셋(fish · zsh · bash)은 DECSCUSR을 안 보낸다(design 실측 8). 그래서 셸 커서는
  언제나 block이고, 커서 반전을 세는 검사(`render` 검사 3 · `hangul`의
  `inverted_cells`)가 안 흔들린다. 셸이 언젠가 보내기 시작하면 `render` 검사 20이
  먼저 빨개진다.
- stub이 없으면 vim.basic은 `E1187: Failed to source defaults.vim`과 `Press ENTER`를
  띄우고 키를 기다린다. 시스템 vimrc의 `skip_defaults_vim`으로는 못 막는다 — 그
  변수를 보는 코드가 `defaults.vim` 안에 있다.
- 경로의 `vim91`은 vim 판에 묶여 있다. Debian이 9.2로 올리면 `vim92`가 되어 stub이
  안 읽히고, 그날 `render` 검사 25가 `E1187`로 빨개진다. 그때는 `make_initrd.sh`의
  경로 하나와 `tools/check.sh` 검사 1의 literal 하나를 고친다.
- vim 화면의 `style>` 덤프는 언제나 잘린다. vim이 `~` 줄의 나머지를 NonText 색의
  공백으로 채워서 셀이 6,976개다. 게이트는 "덤프가 커서 칸을 지났다"로 판정한다
  (`render/check.sh`의 `style_covers`).
- vim은 어떤 길로 나가든 마지막에 block을 보낸다. "대체 화면의 모양이 기본 화면으로
  안 샌다"는 vim으로 판정할 수 없고, `render` 검사 32가 printf로 판정한다.
- vim이 켜는 키 모드(DECCKM)는 우리 키 입력에 영향이 없다. vim 안에서도 Esc는 1바이트로
  간다. modifyOtherKeys는 `terminal/src/`가 아예 안 읽는다.
- 무게는 initrd 압축 전 +2,576,384바이트, 풀기 시간 +0.04초다. 부팅 시간에 안 보인다.

## 탈출로

- `vim -u NONE` — vimrc를 아무것도 안 읽는다.
- 사람이 `/.vimrc`에 `set t_SI= t_SR= t_EI=`를 쓰면 끈다. 시스템 vimrc가 먼저 읽히고
  사용자 vimrc가 그 뒤에 읽히기 때문이다. 다만 `/.vimrc`가 생기면 vim이
  `nocompatible`로 뜬다. 그리고 지금 `/.vimrc`는 tmpfs라 재부팅에 사라진다(design 비목표 7).
- 시스템 vimrc는 `/config`가 아니라 initrd에 있어서 `tars.noconfig`와 무관하다.

## 관련

[[project_userland_tools]](vim이 게스트에 들어온 자리) ·
[[project_terminal_rendering]](색과 커서를 `vt.zig`가 해소한다) ·
[[project_hangul_input]](preedit 두 칸 반전은 모양보다 앞선다) ·
[[project_workspace_panes]](포커스 없는 패널에는 커서가 없다)
