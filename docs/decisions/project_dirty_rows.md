---
name: project_dirty_rows
description: "부분 갱신 서브프로젝트 Dirty Rows(DR-M0~M2, 2026-10-28~30). 패널마다 지난 프레임의 cells() 사본과 행마다 비교해 바뀐 행만 지우고 다시 칠하고 DIRTYFB clip으로 넘긴다. 잔상은 게이트 전 체인에서 켜는 verify 모드(같은 프레임을 그림자에 통째로 그려 비교, clip은 화면 흉내 버퍼로)가 판정한다. 지우는 색은 MARGIN_COLOR, 행 하나는 패널 폭 + 오른쪽 한 칸, 통째 판정은 트리 비교. 키 하나의 그리기 2.45 → 1.36ms, cells()가 46%라 M3(행 dirty 비트)을 제안"
metadata:
  type: project
---

# Dirty Rows (DR)

HANDOFF "다음 후보"의 부분 갱신을 사용자가 2026-10-28에 골랐다. Render Speed([[project_render_speed]])가 "부분 갱신 앞의 축
셋"을 먼저 줄이고 남겨 둔 것이다. ghostty를 참고로 읽었다(`/Users/dp/Repository/_study/ghostty`, [[reference_ghostty_source]]).

- design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`
- plan: `docs/plans/2026-10-28-tars-dirty-rows-dr-m0.md` · `2026-10-29-…-dr-m1.md` · `2026-10-29-…-dr-m2.md` — 값은 각 plan의 결과 절
- 프로브: RS의 `probe/patch.pl`(비교 판, anchor가 그리기 밖이라 그대로) + `probe/split.pl`(진단 판, HEAD마다 anchor를 고른다)

## 모양

- dirty의 출처는 `cells()` 결과의 사본이다(사용자 결정) — 행 dirty 비트(ghostty의 길)가 아니다. 패널마다 셀 목록 두 벌
  (`Pane.cells_buf`)을 두고 `verify.rowStarts` · `dirtyRows`로 행마다 바이트 비교한다. 최종 결과를 비교하므로 `cells()`가 얹는
  층(선택 · 하이라이트 · block 커서 · preedit · 팔레트)이 무엇이든 저절로 잡힌다.
- 통째로 그리는 것은 화면 전체(첫 프레임 · 워크스페이스 전환 · 트리 변경 — `last_current` · `last_tree`와의 비교, 플래그 아님)와
  패널 단위(지난 목록 없음 · 이번 또는 지난 프레임에 이미지 · 행 순서 깨짐)뿐이다.
- overlay(커서 띠 · 프롬프트 · 상태 줄 · 화살표)는 행 dirty와 따로다 — 지난 프레임의 자리 ∪ 이번 자리를 dirty에 더하고, 상태 줄 띠는
  매 프레임, 화살표는 프레임 처음에 `restore`.
- clip은 `drm.ClipList`(64개, 넘으면 경계 상자 하나로 접는다) — 행 run · 통째 패널 · 상태 줄 띠 · 화살표 옛 자리와 새 자리.

## 재사용할 사실

1. 통째 경로의 빈 칸은 `MARGIN_COLOR`다 — `cells()`가 `cp == 0 and bg == default_bg`인 셀을 안 내보내고 `renderPane`은 내보낸 셀만
   칠한다. 부분 경로가 행을 지우는 색도 그래서 `MARGIN_COLOR`이지 패널의 기본 배경이 아니다(OSC 11로 기본 배경을 바꿔도 통째
   경로의 빈 칸은 그대로다 — 그것이 정답지다).
2. 글리프가 격자 밖으로 새는 자리가 하나 있다 — 마지막 열의 preedit(폭 2)과 프롬프트의 조합 글자. 통째 경로는 다음 `fill`이
   지우지만 부분 경로는 행을 다시 칠할 때 패널 오른쪽 한 칸(구분선 또는 여백)을 함께 되돌려야 한다. 트리의 타일링상 그 칸은
   언제나 둘 중 하나다(`stripColor`).
3. verify는 두 가지를 본다. 픽셀(실제 fb vs 그림자에 통째로 그린 것)과 clip(화면 흉내 — `present`가 넘긴 clip 안만 fb에서 복사한
   버퍼 vs fb). 둘째가 필요한 이유는 clip을 빼먹으면 fb는 맞고 화면만 낡아 덤프도 픽셀 비교도 못 보기 때문이다. 각각
   mutation으로 load-bearing임을 봤다(지난 커서 띠 행 뺌 → 126 `mismatch`, 행 run clip 뺌 → 523 `mismatch clip`).
4. mutation은 가려질 수 있다. "지난 프롬프트 행 뺌"은 셸이 맨 아래 줄이라 그 줄이 어차피 dirty여서, "상태 줄 clip 뺌"은 상태 줄이
   같은 글자를 같은 자리에 다시 그려서 안 잡혔다. 잡히는 자리를 골라야 하고, 안 잡히면 왜인지를 먼저 읽는다.
5. 커널 6.18.42의 clip 처리 — virtio-gpu는 clip 전부를 경계 상자 하나로 합쳐(`drm_atomic_helper_damage_merged`) 그 사각형만 host로
   옮기고, simpledrm은 clip마다 `drm_fb_blit`로 VRAM에 복사한다(`sysfb/drm_sysfb_modeset.c`). ioctl 상한은 256. 그래서 QEMU에서는
   clip 개수가 뜻이 없고 상자 크기만, 실기에서는 이웃 행을 합치는 것이 값어치가 있다.
6. `rowStarts`가 false(행 순서가 아님)로 빠지면 `starts`는 반쯤 쓰인 값이다 — 그 패널은 통째로 그린다. 호스트 검사가 그 성질을
   먼저 드러냈다(검사 8의 false 호출이 검사 9의 배열을 덮었다).
7. Zig 0.17: `std.meta.fields`는 deprecated(`@typeInfo(T).@"struct".field_types`), `uintLessThan(u24, 0x1000000)`은 상한이 타입을
   넘어 컴파일 에러(`rnd.int(u24)`), `std.meta.eql`은 `union(enum)`을 태그 → 값 순으로 비교한다.

## 결과 (같은 프로브, 부팅 3회 중앙값)

| | M0 기준선 (`67596a0`) | M2 (`aabd0bc`) |
|---|---|---|
| (a) 키 하나의 frame | 2.45ms | 1.36ms (−45%) |
| (a) 구간 | backdrop 0.72 · cells 0.63 · pane 0.81 · finish 0.29(present 0.21) | others 0.01 · cells 0.63 · pane 0.165(비교 0.03 + 행 0.14) · overlay 0.20 · finish 0.32(present 0.32) |
| (b) `seq 1 200000` | 1,135ms | 1,105ms(잡음 안 — 스크롤은 모든 행이 dirty, 81%가 파서) |

RS-M3의 4.3ms(2026-10-11)와는 섞지 않는다 — 조건이 같다는 보장이 없고 DR-M0이 기준선을 새로 쟀다. verify 한 번은 게이트
TCG에서 약 12ms(픽셀 4MB + 화면 흉내 4MB 비교) — 프로브에서는 꺼져 있다.

남은 것: `cells()`가 frame의 46%다. M3(행 dirty 비트)을 제안했고 사용자가 고른다. 실기 simpledrm의 clip 효과(8MB 복사 → 행
몇 줄)는 QEMU에서 안 보이므로 "사용자가 확인할 것"이다 — QEMU에서는 clip 있는 DIRTYFB가 오히려 0.1ms 더 든다(blob · damage 합치기).
