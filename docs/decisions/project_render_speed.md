---
name: project_render_speed
description: "GPU 전에 그리기를 빠르게 한 서브프로젝트 Render Speed(RS-M0~M3, 2026-10-11). 같은 프로브(probe/)로 전후를 쟀다 — seq 1 200000이 5.5 → 2.2초(남은 81%는 VT 파서), 키 하나의 그리기 11.6 → 4.3ms. 84.7%가 fill이던 것은 픽셀 수가 아니라 쓰는 방식(volatile 4바이트씩)이었다. CPU 하나인 게스트에서 poll(0)로 더 읽기는 운이고, 그리기를 미뤄 poll에서 막혀야 자식이 돈다. 부분 갱신은 그 뒤 DR(2026-10-30)이 했다"
metadata:
  type: project
---

# Render Speed (RS)

사용자의 요청(2026-10-10): "GPU 가속을 도입하기 전에 시도할 만한 것들을 추려보자 … 가장 쉬운 접근은 부분 갱신(dirty 추적)
작업이라고 생각하는데 전체적인 검토 부탁해." 검토가 "부분 갱신은 가장 쉬운 길이 아니고, 그 앞에 더 싼 축이 셋 있다"를 내고,
사용자가 "부분 갱신 전에 먼저 할 수 있는 것을 해결합시다"로 정했다(2026-10-11).

- design: `docs/specs/2026-10-11-tars-render-speed-design.md`
- plan: `docs/plans/2026-10-11-tars-render-speed-rs-m0.md` ~ `-rs-m3.md` — 값은 각 plan의 결과 절에 있다
- 프로브: `probe/patch.pl` · `run.sh` · `report.pl`. 돌리는 법은 M0 plan. milestone마다 같은 판으로 다시 잰다

## 결과 (같은 프로브, 부팅 3회 중앙값)

| | M0 | M1 memset | M2 frame cap | M3 DIRTYFB |
|---|---|---|---|---|
| (b) `seq 1 200000` | 5,501ms | 2,959ms | 2,207ms | 2,184ms |
| (b) 프레임 | 365 | 367 | 126 | 126 |
| (b) 파서(`other`) | 1,783ms | 1,809ms | 1,787ms | 1,762ms |
| (a) 키 하나의 frame | 11.6ms | 4.9ms | 4.7ms | 4.3ms |

RC-M0([[project_render_cost]])의 21.3ms와는 조건(호스트 · 측정 경계 · `kms:` 줄)이 달라 섞지 않는다.

## 재사용할 사실

1. 프레임버퍼 쓰기의 비용은 픽셀 수보다 쓰는 방식이었다. `*volatile u32`로 픽셀마다 주소를 셈하고(ReleaseSafe의 overflow
   검사 포함) 4바이트씩 쓰던 것을 행마다 `@memset` 한 번으로 바꾸자 그리기 합이 79% 줄었다. dumb buffer는 MAP_SHARED 보통
   메모리라 `volatile`이 지키는 것이 없다 — 포인터가 `mmap`에서 왔으므로 컴파일러는 `ioctl`이 읽을 수 있다고 봐야 한다.
2. 출력이 쏟아질 때 프레임 수 = PTY 읽기 수였다. 커널 n_tty 버퍼가 4KB라 읽기가 늘 4,095바이트다.
3. 게스트는 CPU 하나(`# CONFIG_SMP is not set`) · `PREEMPT_NONE` · `HZ=250`이다. 자식과 터미널이 CPU를 나눠 쓰므로 "읽은 뒤
   `poll(0)`으로 더 있나 묻고 더 읽기"는 묻는 동안 CPU를 안 놓아 답이 틱과 `feed`의 위상에 달린다 — 같은 코드가 시계 호출
   몇 개로 2.1초와 5.6초로 갈렸다. 그리기를 미루고 `poll`에서 막혀야 자식이 돌아 버퍼를 채운다(`pacing.zig`, 16ms).
4. 덤프는 생각보다 싸다(M0에서 (b)의 7%). 프레임이 빨라지면 다음 덤프가 앞 덤프의 시리얼 배출을 기다리는 듯 키 하나의
   덤프가 2.6 → 4.5ms로 늘었다(가설, 안 쟀다).
5. virtio-gpu · simpledrm 둘 다 DIRTYFB를 받는다(`drm_atomic_helper_dirtyfb`). QEMU에서 SETCRTC → DIRTYFB의 차이는 잡음 안이다.
   simpledrm이 VRAM으로 옮기는 양을 줄이는 것은 clip이고, clip은 부분 갱신이 생길 때 `present`에 넘긴다.

## 게이트에서 드러난 것 — 콘솔 fish의 프롬프트에 terminal 줄이 붙는다

M2가 프레임을 줄이자 드러났다. 모양과 처방(`joined_screen_dump` · `from_terminal`)은
`docs/guides/lessons.md`의 "커널 printk가 terminal의 화면 줄을 가운데서 자른다" 절의 RS-M2 · M3 덧붙임에 있다.

## 방법

- 측정 → 변경 → 같은 프로브로 재측정. 프로브는 원본을 안 바꾸는 패치 사본이고 anchor는 정확히 한 번이어야 한다.
- 결과가 판마다 갈리면 구간을 더 쪼갠 진단 판(저장소 밖 `/tmp`)으로 잰다. M2의 drain을 버린 근거가 그것이다.
- 루트 게이트의 `clean()`이 `out/`을 지운다. 프로브 로그는 게이트 전에 옮긴다. 체인 하나의 시리얼 로그는 GF-M1부터
  `make check CHAIN=x`가 `out/gate-logs/<체인>/`에 남긴다(`docs/guides/lessons.md`의 "회차의 로그는 out/gate-logs…" 절).

## 그 뒤

- 부분 갱신은 Dirty Rows(DR-M0~M3, 2026-10-30, [[project_dirty_rows]])가 했다 — 출발점은 여기 적어 둔 그대로("지난 프레임의
  셀 격자와 이번 `cells()`를 행 단위로 비교", 손상 사각형을 DIRTYFB clip으로). 키 하나의 그리기 2.45 → 0.92ms(measurements 96 · 97),
  상태 줄 띠까지 하면 0.42ms(SB-M0, measurements 98).
- 덤프가 프레임과 비슷한 크기가 됐다((a) 4ms 안팎). 끄는 길은 전 체인에 걸친다(design 결정 5).
