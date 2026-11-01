---
name: project_measuring_shells
description: "셸의 동작을 재는 환경(컨테이너)이 실제로 돌 환경(게스트)과 다르면 값이 조용히 틀린다 — BH가 2026-09-12 하루에 세 번 걸렸다(measurements 27 · 28 · 31). 공통 처방은 재는 환경의 차이를 먼저 적고 그 차이가 재려는 값을 바꾸는지 묻는 것, 모르겠으면 게스트에서 5분"
metadata:
  type: project
---

BH(Bash History Durability)가 2026-09-12 하루에 같은 종류의 함정에 세 번 걸렸다. 셋 다 증상이 같다 — 에러가
없고, 값이 나오고, 그 값이 틀렸다. 이 저장소는 셸 셋(fish · bash · zsh)의 동작에 기대는 층을 계속 쌓고
있고(SC · SM · SD · BH), 그것을 재는 자리는 언제나 게스트가 아니라 컨테이너다 — 게스트를 한 번 띄우는 데
5분이 들기 때문이다. 그래서 다음에 또 걸린다.

사례 셋은 `docs/guides/measurements.md`에 있다 — 서로 다른 축이다.

1. 컨테이너에는 있고 게스트에는 없는 것(`/dev/fd`) — measurements 27. 처방은 훅을 고치는 것이 아니라 init이 그
   링크를 만드는 것이었다(`linkDevFd()`, BH 결정 9). 없는 링크가 결함이고, 훅을 고치면 다음 도구에서 또 드러난다.
2. 측정 도구가 끼우는 층(`script`의 `sh -c` 래퍼가 시그널을 받는다) — measurements 28, 정리가 측정을 바꾸는 것은 29.
3. 재는 모드가 돌 모드와 다른 것(비대화형 bash는 `PROMPT_COMMAND`를 안 돈다) — measurements 31. 그래서
   `KNOWN_HIST_OPTIONS`의 주석이 셸별로 재는 방법을 나눠 적는다(BH 결정 5).

## 공통 처방

재기 전에 "재는 환경과 돌 환경이 무엇이 다른가"를 먼저 적고, 그 차이가 재려는 값을 바꾸는지 묻는다. 답이
"모르겠다"면 게스트에서 한 번 확인한다 — 5분이 든다. BH-M0이 그렇게 했다. 착수 전 실측 여섯을 컨테이너에서 잰
뒤, M0을 통째로 "그 여섯을 게스트에서 확인하는" milestone으로 썼고 그 M0이 사례 2를 끌어냈다.

관련: [[project_shell_history]] · [[project_shutdown_signals]] · [[project_build_host_arch]]
