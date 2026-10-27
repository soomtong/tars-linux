---
name: user-editor-use
description: 사용자는 실제 코드 작업을 neovim · helix로 한다. 게스트 vim은 대충 쓰는 보조 편집기다
metadata:
  type: user
---

# 편집기 사용

사용자는 실제 코드 작업을 neovim과 helix로 한다. 게스트의 vim은 설정 파일을 고치거나 `git commit` 메시지를 쓰는 정도로 대충 쓰는
편집기다(사용자, 2026-10-27).

Why: Vim Runtime(VR) design을 쓴 뒤에 나온 말이고, 이 말로 VR을 착수 전에 취소했다. 게스트 vim에 문법 색 · filetype을 넣는 값(RAM
+12.8MB · 이미지 재빌드 · render 검사)을 치를 쓰임이 없다. 실측과 범위 결정은 `docs/specs/2026-10-27-tars-vim-runtime-design.md`에
그대로 남겼다.

How to apply: 게스트 vim의 기능을 늘리는 후보(런타임 · 플러그인 · colorscheme)는 사용자가 먼저 말하기 전에는 올리지 않는다. 지금의
vimrc(컴파일된 옵션과 `:highlight`만)로 충분하다. neovim · helix를 게스트에 싣는 일은 다른 질문이다 — helix는 trixie에 없고 neovim은
런타임 24MB였다([[project_userland_tools]]). 이것도 사용자가 꺼낼 때 다시 본다.
