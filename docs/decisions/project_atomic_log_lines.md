---
name: project_atomic_log_lines
description: terminal과 init의 시리얼 로그 줄을 write 한 번으로 내는 서브프로젝트 Atomic Log Lines(AL-M0 · M1, 2026-10-07). Zig 0.16 std.debug.print는 호출마다 64바이트 버퍼로 stderr를 잠그고 비워 한 줄이 write 여럿이고, 두 프로세스가 같은 콘솔에 쓰면 호출 사이가 끼어들 틈이다. logline.zig 사본 둘(2048바이트까지 write 한 번, 넘치면 UTF-8 경계에서 자르고 [cut]), 루트 check.sh가 회차마다 끼어든 줄 A · B와 잘린 줄 C를 세어 FAIL, 로그의 주인은 회차 디렉터리
metadata:
  type: project
---

Atomic Log Lines(AL)는 TC-M3의 루트 게이트가 하룻밤에 두 번 빨개진 자리에서 열었다(2026-10-07). design은
`docs/specs/2026-10-07-tars-atomic-log-lines-design.md`(결정 7 · 전제 정정 3 · 실측 F), plan은
`docs/plans/2026-10-07-tars-atomic-log-lines-al-m0.md`(terminal) · `-al-m1.md`(init)이고 각 끝의 "실측한 것" 절이 값이다. planner Opus
(`tc-design`) · 구현자 Sonnet(`tc-m0-impl`)이 TC에서 이어서 했고 plan 코드를 고친 곳은 0이다.

## 사슬 — 다시 조사하지 말 것

- 컨테이너 Zig 0.16의 `std.debug.print`는 `var buffer: [64]u8`로 stderr writer를 잠그고 `print`한다. 64바이트를 넘는 줄은 write 둘 이상으로
  나간다(TC-M3 게이트의 `pointer>` 줄이 정확히 65바이트째에서 잘렸다). terminal의 화면 dump는 `screen> ` · 칸마다 · ` | ` · `\n`을 따로
  print해 한 프레임이 write 수천이었다(회차당 180만).
- terminal과 init은 같은 `/dev/console`(ttyS0)에 쓴다. tty 층은 write() 한 번을 `atomic_write_lock`으로 통째로 묶으므로 사용자 공간 둘 사이의
  자름은 write 사이에서만 난다. 커널 printk는 UART에 직접 써서 write 안도 자른다 — 그것은 `joined_screen_dump`의 커널 조각 처리가 맡는다.
- 2048은 커널 tty가 write 한 번을 쪼개는 chunk다(`tty_io.c`의 `iterate_tty_write`). 그 안의 줄은 시그널이 걸려도 안 끊긴다. init은 시그널 처리기가
  `SA_RESTART` 없이 달려 있어 EINTR이 실제로 생길 수 있고 `flush`가 재시도와 이어 쓰기로 받는다. terminal은 처리기가 0개라 화면 dump(격자
  크기 버퍼, 155×47이면 29,345바이트)가 2048을 넘어도 안 끊긴다.
- 끼어듦은 드물다 — TC-M3 게이트 한 판(42회차)에 2 ~ 8. 그래서 "치환 하나를 되돌리면 런타임에 잡히는가"는 운이고(AL-M0 확정 8의 m1은 네 판
  초록), 되돌린 치환은 루트 `check.sh`의 진입 검사(게스트 파일의 `std.debug.print` 0곳 · 사본 둘의 cmp)가 결정적으로 지킨다. 진짜 끼어듦은
  셈이 잡는다(심은 줄 m2 → `A=2`로 FAIL).

## 결정

- `logline.zig` 하나를 `init/src` · `terminal/src`에 바이트까지 같은 사본 둘로(결정 1). 공용 모듈도 서지만 그 파일을 import하는 호스트 검사
  열다섯에 `addImport`가 필요해서다. API는 `print(fmt, args)`(std.debug.print와 같은 fmt — perl 한 줄 치환)와 조각용 `Line`(init · print ·
  bytes · flush). `Writer.fixed`를 쓴다(`bufPrint`는 얼마나 썼는지를 안 돌려준다). 에러는 삼키고 런타임 값에 assert는 없다.
- 여러 조각으로 짓던 줄은 `dumpScreen` 하나뿐이라 그것만 `Line`에(결정 2). 바이트는 전과 같다 — 같은 부팅에서 옛 · 새 모양을 둘 다 찍어
  1,220프레임을 견줬다(한글 음절 76 포함).
- 게스트 파일의 `std.debug.print`는 전부(terminal 98 · init 151 — design의 153은 주석 둘을 센 것). `config.zig`의 `log()`와 `configLog`
  가로채기(TC 결정 3)는 그대로, 싱크만 바뀐다.
- 게이트(결정 4): 새 체인 없이 루트 `check.sh`의 `run_chain`이 회차마다 `TMPDIR=<GATE_LOGS>/<체인>-<회차>`를 주고 끝나면 `cut_log_lines`로
  센다 — A(`terminal:` 줄 안의 `tars-init:`), B(반대 — init 고유 `reload terminal: pid ` 줄 제외), C(` [cut]`으로 끝난 줄). 셋 다 FAIL. 로그를
  지우던 8체인 14자리가 로그를 남긴다 — audio는 부팅 넷이 같은 파일을 덮어 써 마지막 하나만 남아 있었다.
- `joined_screen_dump`(결정 5): 커널 조각 처리와 온전한 `tars-init:` 줄 건너뛰기는 남기고, TC-M3 5b의 `tars-init:` 꼬리 떼기는 M1이 지웠다 —
  AL 뒤에는 그 규칙이 화면 글자의 꼬리를 떼는 거짓만 만들 수 있다.
- 덤(M1 Task 3-3): pointer · copy · render · pane의 NUL 검사가 파일을 두 번 읽어(`tr -d` 길이와 `wc -c`) QEMU가 아직 쓰는 중이면 거짓 빨강이
  났다. 한 번 읽기(`tr -cd '\0' | wc -c`)로 바꿨다.

## 남긴 것

커널 printk와 콘솔 셸 프롬프트 뒤에 붙는 줄(회차당 4 ~ 14줄 — pointer의 `^terminal: pointer>` 대기가 약하다)은 범위 밖이다.
`tars-config` · `tars-service` · `tars-install`이 사람에게 쓰는 글(`writeAll`)은 대상이 아니다. init ReleaseSafe 바이너리가 8.7% 커졌다(fmt마다
펼쳐지는 `logline.print`).

관련: [[project_config_reload]] · [[project_audio_devices]](AU-M2의 printk 자름과 `joined_screen_dump`) · [[project_gate_accuracy]]
