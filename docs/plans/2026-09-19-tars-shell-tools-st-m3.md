# ST-M3 — fzf의 `--height`를 끄고, 그 이유를 게이트가 지키게 한다

> 이 plan을 실행하는 사람에게: 이것은 **우회**다. 진짜 수리(터미널이 vt 질의에
> 답하는 것)는 다음 서브프로젝트로 미뤘다 — 그 근거와 잰 값이 design과
> `docs/decisions/project_terminal_queries.md`에 있다.

Goal: Ctrl+R이 **첫 누름에** picker를 열게 한다. 지금은 첫 누름에 멈추고
두 번째 키가 와야 뜬다 — fzf가 `--height`일 때 터미널에 커서 위치를 묻고,
우리 terminal이 그 질의에 답하지 않기 때문이다.

Architecture: 씨앗 rc에 fzf 옵션 줄 하나를 더한다(fish `set -gx`,
bash·zsh `export`). `config_test.zig`의 씨앗 허용 목록에 그 줄을 **정확한
줄**로 넣고(접두사로 열지 않는다 — `export A=$(...)`가 명령을 숨긴다),
`config/check.sh` 1차 부팅이 "첫 Ctrl+R에 picker가 뜬다"를 판정한다.

Tech Stack: Zig(씨앗·단위 검사) · bash(config 체인) · QEMU(sendkey ctrl-r)

---

## Task 1 — 재기 (M0와 같은 방식)

| 잰 것 | 결과 |
|---|---|
| 기본값(`--height 40%`)에서 Ctrl+R 한 번, 키를 안 누르고 12초 | 프레임이 **한 장도 안 늘어난다** |
| `FZF_CTRL_R_OPTS=--no-height` | 프레임 5 → 52, picker가 첫 누름에 뜬다 |
| `echo hi \| fzf` (통합 없이 직접) | 즉시 뜬다(전체 화면이라 질의가 없다) |
| `time fzf --version` | 34ms — 기다리는 것이지 느린 것이 아니다 |
| `terminal/src`에 vt 질의 콜백 등록 | **0개**(lib-vt는 창구를 갖고 있다) |

`FZF_DEFAULT_OPTS=--no-height` 형태는 **안 먹는다**(같은 껍데기로 재 봤더니
picker가 여전히 늦게 떴다) — fzf의 fish 통합이 위젯 옵션에 `--height`를
앞세우기 때문이다. 그래서 씨앗은 `FZF_DEFAULT_OPTS`가 아니라 **위젯이 마지막에
읽는 자리**… 를 노린 한 줄이 아니라, 실측으로 통과한 형태를 쓴다.

## Task 2 — 씨앗 셋에 한 줄

```
set -gx FZF_DEFAULT_OPTS --no-height          (fish)
export FZF_DEFAULT_OPTS='--no-height'         (bash · zsh)
```

주석에 담을 것: 왜 이 줄이 필요한가(위 실측), 대가가 무엇인가(picker가 전체
화면), 진짜 수리가 무엇인가(terminal의 질의 응답).

## Task 3 — 검사 둘

1. `config_test.zig`: `KNOWN_SEED_ENV`에 두 줄을 적고, `expectQuietSeed`가
   그 줄을 허용하며, 씨앗마다 그런 줄이 **하나도 없으면 실패**한다(볼 것이
   없었다를 가른다). 접두사가 아니라 정확한 줄인 이유를 주석에 적는다.
2. `config/check.sh` 1차 부팅 훅의 **맨 끝**: `type_keys ctrl-r` →
   `wait_for_screen '\| >'` → `type_keys esc`.
   끝에 두는 이유가 실측이다 — 중간에 두었더니 picker를 닫는 중인 fzf로 다음
   타이핑이 새어 되읽기(`shell=zsh`)가 깨졌다.

## Task 4 — 돌린다

| 순서 | 결과 |
|---|---|
| `zig build test` | PASS |
| `config/check.sh` | PASS, `boot 1: one Ctrl+R opened the fzf picker (the seeded --no-height reached it)` |
| 루트 게이트 | design의 "M3가 실행으로 증명한 것"에 적는다 |

## 다음

진짜 수리 — `terminal`이 lib-vt의 콜백(커서 위치 보고 · DA1/DA2 · 모드·색
질의)을 등록해 pty로 답을 쓴다. 그러면 fzf가 40% 상자로 돌아오고, 이 씨앗
줄은 지울 수 있다.
