---
name: project_cursor_options
description: "커서 옵션(CO-M0~M1, 2026-11-10): DECTCEM ?25l이면 셸 커서를 안 그린다, tars.conf cursor_shape=block|bar|underline(argv 15번 칸). 깜빡임은 안 한다(CPU). fish는 명령마다 ?25h를 보낸다"
metadata:
  type: project
---

# Cursor Options (CO)

사용자(2026-11-10, fakesteak 데모 점검): "full screen mode에서 cursor가 계속 빠르게 깜빡이는게 눈에 거슬리는데". 이어서 "CPU 비용을 아끼는 것은
중요하다. 깜빡임 기능은 제외하고, 커서 모양 변경 기능은 이번 태스크에 포함하자." design `docs/specs/2026-11-10-tars-cursor-options-design.md`,
plan `docs/plans/2026-11-10-tars-cursor-options-co-m0.md` · `-co-m1.md`.

- "깜빡임"의 정체: 깜빡임이 아니라 커서 자리의 이동이었다. fakesteak은 `?25l`을 보내는데 렌더러가 안 봤고, 한 프레임을 쓰는 도중의 커서 칸이
  매 프레임 다른 자리에서 반전됐다(5초 70프레임, 70곳). 이제 `computeShellCursor`가 `state.cursor.visible`을 본다 — preedit 중에는 무시한다.
- fish 4.0.2는 명령이 끝날 때마다 `ESC[?25h`를 보낸다(바이너리에 문자열 상수). 그래서 숨김은 명령이 도는 동안에만 보인다 — 게이트는
  `printf …?25l; sleep 5`로 본다(render 검사 38 · 39). 숨긴 커서가 셸까지 새어 나오는 위험은 fish에서는 없다.
- `cursor_shape`는 lib-vt의 `default_cursor_style`이다(`vt.Screen.setDefaultShape`, `spawnPane`이 패널마다 준다). 렌더러는 그대로.
  DECSCUSR이 이기고 `CSI 0 SP q` · RIS가 돌아온다(xterm과 같다). 시스템 vimrc의 `let &t_ti .= "\e[2 q"`가 vim의 normal을 처음부터 block으로 —
  vim은 기동 때 `t_SI` · `t_SR` · `t_EI`를 안 보낸다.
- argv 칸을 더할 때 고칠 자리(CO-M1에서 놓친 것 셋): init의 null로 채운 `ARGC` 길이 argv 리터럴 일곱(`rg '(null, ){8,}null' init/src`) —
  호스트 검사가 안 잡고 init 본 빌드가 잡는다. 키 수를 글자로 박은 검사(reload_test의 `OTHER` 비트 · config_edit_test의 `showKeyLines`
  기대 글자 · screen_args_test의 `argvOf` 마지막 칸). 그리고 init 로그 줄 끝에 칸을 붙이면 `gate_lib.sh` `cut_log_lines`의 B 예외 정규식과
  루트 `check.sh`의 견본 `legit` 줄 — 안 고치면 `reload terminal`을 치는 체인 여섯이 "serial lines were cut"으로 빨갛다.
- 깜빡임(CU 비목표 1)은 다시 열지 않는다 — 열려면 design 확인 10의 셋(초당 두 번 깨기 · 프레임마다 시리얼 덤프 · "로그가 조용하다"는 게이트
  전제)을 먼저 푼다.
- DC-M2 boot 7("USB 디스크를 4초 늦게")은 호스트 부하에 민감하다 — initramfs 풀기(같은 initrd로 4초 ~ 7초)가 USB 지연을 넘기면 init이
  기다릴 일이 없어 빨갛다. CO-M1에서 세 번 빨갰고 원인은 변경이 아니라 부하였다(같은 조건에서 두 initrd를 번갈아 재 차이 0). 그 부하의
  하나는 이 저장소의 예전 세션이 macOS에서 돌린 init `services_test`가 끝나지 못한 채 10일 넘게 CPU 하나를 먹던 고아 프로세스였다 —
  init 검사는 macOS에서 끝나지 않으므로([[project_github_actions]]) 컨테이너에서만 돌리고, 게이트가 이상하게 느리면 `ps -Ao pid,pcpu,etime,comm -r`부터 본다.

관련: [[project_fullscreen]] · [[project_minimal_iso]]
