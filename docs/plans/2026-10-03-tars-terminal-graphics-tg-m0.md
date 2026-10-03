# TG-M0 — 그리기 전에 다섯을 잰다

> 이 milestone은 커밋되는 코드를 한 줄도 안 고친다. 탐침은 작업 트리에서만
> `terminal/src/tg_probe.zig`와 `terminal/build.zig`의 실행 파일 하나로 두고, 끝나면 지운다.
> 저장소에 들어가는 것은 design의 "실측 (M0)" 절과 이 plan이다.

Goal: design 결정 2 · 3 · 5 · 7이 기다리는 사실 다섯을 잰다. M1이 그 값을 옮겨 적기만 하면
되게 한다.

Architecture: 호스트(컨테이너, arm64)에서 도는 탐침 하나가 `vt.Screen`을 만들고 kitty
명령을 `feed`한 뒤, `screen.term.screens.active.kitty_images`를 직접 읽어 찍는다. ghostty
렌더러의 `prepKittyPlacement`(`ghostty-src/src/renderer/image.zig`)가 쓰는 API를 그대로
부른다. 게스트의 여유 메모리만 부팅 한 번으로 본다.

---

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | raw RGBA 명령 하나가 저장소에 이미지 하나 · placement 하나로 들어가는가 | 착수 전 1 · 결정 1 |
| 2 | `width_px`가 0일 때와 채웠을 때 `c=` · `r=`로 크기를 준 placement의 픽셀 크기 | 결정 2 |
| 3 | 질의(`a=q`)와 전송의 답이 `takeReplies`로 나오는가, 그 바이트 모양 | 결정 7 · 위험 2 |
| 4 | placement → viewport 좌표. 스크롤해서 viewport가 움직였을 때의 y | 결정 3 · 위험 3 |
| 5 | 게스트의 `MemTotal` · `MemAvailable` | 결정 5 |

PNG 명령(`f=100`)이 무엇을 답하는지도 측정 3에 함께 본다 — 결정 6 전의 동작이다.

## Task 1: 탐침을 만든다

`terminal/src/tg_probe.zig` — `vt.Screen.init(io, gpa, 20, 5)`로 화면을 만들고 다음을
차례로 `feed`한다. 2×2 RGBA(빨강 · 초록 · 파랑 · 반투명 흰색)를 base64로 싣는다.

```
ESC _G a=T,f=32,s=2,v=2,i=1 ; <base64 16바이트> ESC \          # 측정 1
ESC _G a=T,f=32,s=2,v=2,i=2,c=4,r=2 ; <같은 것> ESC \           # 측정 2 (셀 크기로 지정)
ESC _G a=q,f=32,s=1,v=1,i=3 ; <4바이트> ESC \                   # 측정 3
ESC _G a=T,f=100,i=4 ; <아무 바이트> ESC \                     # 측정 3 (PNG)
```

각 단계 뒤에 찍는 것: 이미지 수 · placement 수 · 각 placement의 `pixelSize` · `rect`의
`top_left`/`bottom_right` · `pointFromPin(.screen, …)`의 y · viewport 꼭대기의 y ·
`takeReplies()`의 바이트(이스케이프는 `\x1b`로). 측정 2는 같은 명령을 `width_px = 20×8`,
`height_px = 5×16`을 넣은 뒤 한 번 더 보낸다. 측정 4는 줄바꿈 열 개를 `feed`해 이미지를
스크롤백으로 밀어 올린 뒤 같은 것을 다시 찍는다.

`terminal/build.zig`에는 `vt_test`와 같은 모양(호스트 target · `ghostty_host_dep`)으로
실행 파일 `tg_probe`를 하나 더한다.

## Task 2: 탐침을 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && ./zig-out/bin/tg_probe' 2>&1 | tee /tmp/tg/probe.log
```

## Task 3: 게스트의 메모리를 본다(측정 5)

`docs/guides/running-tars.md`의 방법으로 한 번 띄우고 `/proc/meminfo`의 두 줄을 읽는다.
게이트가 쓰는 QEMU `-m` 값과 실기의 값이 다르면 둘 다 적는다.

## Task 4: 탐침을 지우고 결과를 적는다

`git status`로 탐침 두 자리만 바뀌었는지 보고 되돌린다. design의 "실측 (M0)"에 측정마다
한 절을 쓴다. 결정과 어긋난 것이 있으면 결정을 고치고 그 자리를 실측에 적는다.

## 끝났다고 말할 조건

- 실측 다섯이 design에 있다.
- `git status`에 design과 이 plan 말고는 바뀐 것이 없다.
- 결정 7의 "어느 체인" 질문에 답할 수 있다 — 아니면 그것을 M1 plan의 첫 일로 넘긴다고
  적는다.

## 한 대로 (2026-10-03)

Task 1 · 2 · 4는 plan대로 했다. Task 3은 부팅하지 않았다 — `docs/guides/lessons.md`에 WL 때
잰 `MemAvailable` 213MB가 있어서 그것을 썼다(design 실측 5). 결정 7의 "어느 체인"은 M0이
체인 시간을 안 봐서 답하지 못했고, M2 plan의 첫 일로 넘겼다.
