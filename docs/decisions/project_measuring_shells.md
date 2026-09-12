---
name: project_measuring_shells
description: "셸의 동작을 재는 환경이 실제로 돌 환경과 다르면 값이 조용히 틀린다는 것 — 2026-09-12에 BH가 하루에 세 번 걸리고 정리했다. 사례 셋이 서로 다른 축이다. (1) 컨테이너에는 `/dev/fd`가 있고 게스트에는 없다 — 그래서 씨앗의 fzf 훅이 게스트에서만 `bash: /dev/fd/63: No such file or directory`를 찍었고, SM-M1이 잰 `관문이 있으면 0바이트`가 게스트에서는 거짓이었다. (2) `script -qfc \"bash -i\"`는 `sh -c` 래퍼를 하나 끼우므로 자식 pid로 찾은 것에 시그널을 보내면 셸이 아니라 래퍼가 받는다 — SD 실측 7의 `bash는 SIGHUP에서 안 쓴다`가 이것 때문에 틀렸다. 처방은 `exec`를 넣는 것과 `/proc/<pid>/cmdline`을 함께 찍는 것이다. (3) 비대화형 bash는 `PROMPT_COMMAND`를 아예 실행하지 않으므로 `bash -c '<줄>'`로는 오타 난 프롬프트 훅도 0바이트로 보인다 — 대화형 세션의 화면 바이트를 재야 한다. 공통 처방은 재는 환경의 차이를 먼저 적고 그 차이가 재려는 값을 바꾸는지 묻는 것이다"
metadata:
  node_type: memory
  type: project
---

BH(Bash History Durability)가 2026-09-12 하루에 같은 종류의 함정에 세 번
걸렸다. 셋 다 증상이 같다 — 에러가 없고, 값이 나오고, 그 값이 틀렸다.

셋을 한 자리에 모아 두는 이유는 다음에 또 걸릴 것이기 때문이다. 이 저장소는
셸 셋(fish·bash·zsh)의 동작에 기대는 층을 계속 쌓고 있고(SC·SM·SD·BH),
그것을 재는 자리는 언제나 게스트가 아니라 컨테이너다. 게스트를 한 번 띄우는
데 5분이 들기 때문이다.

## 1. 컨테이너에는 있고 게스트에는 없는 것 — `/dev/fd`

게스트의 `/dev`는 devtmpfs다. 드라이버가 등록한 장치 노드만 담고, `/dev/fd`
(`/proc/self/fd`로 가는 링크)를 만들어 주는 udev나 init 스크립트를 우리는 안
쓴다. Debian 컨테이너에는 그 링크가 있다.

그래서 bash의 process substitution(`< <(…)`)이 게스트에서만 실패한다.
`fzf --bash` 출력의 마지막 줄이 최상위에서 그것을 쓰므로
(`__fzf_orig_completion < <(complete -p …)`), 씨앗 rc를 읽는 bash가 부팅할
때마다 `bash: /dev/fd/63: No such file or directory` 한 줄을 찍고 있었다.

그 한 줄이 이 저장소가 가장 엄격히 지키는 규칙을 깬다 — 우리가 까는 rc는
부팅할 때 아무것도 안 찍는다. SM-M1이 그 훅을 넣으며 잰 "관문이 있으면 셋 다
0바이트"(SM 실측 23)는 컨테이너에서 잰 값이었다.

게이트가 이것을 오래 못 본 이유는 열한 체인 중 bash로 뜨는 것이 하나도
없었기 때문이다. BH-M2가 7차에 중첩 bash를 띄우면서 처음 드러났다.

처방은 init이 그 링크를 만드는 것이다(`main.zig`의 `linkDevFd()`, BH 결정 9).
훅을 고치지 않은 이유는 없는 링크가 결함이고, 훅을 고치면 그 결함이 다음
도구에서 또 드러나기 때문이다.

## 2. `script`가 끼우는 래퍼 — 시그널이 셸에 안 닿는다

`script -qfc "bash -i" /dev/null`은 `bash`를 바로 띄우지 않는다. `sh -c "bash
-i"` 래퍼를 하나 끼운다. 그래서 `script`의 자식 pid를 찾아 시그널을 보내면
받는 것이 셸이 아니라 래퍼다.

증상이 나쁘다. 래퍼가 죽으면 `script`도 끝나고, `script`가 끝나면 PTY가
닫히고, PTY가 닫히면 안쪽 셸이 SIGHUP을 받는다. 그래서 어떤 시그널을 보내도
결과가 "SIGHUP을 받았다"로 수렴한다.

SD 실측 7의 "bash는 SIGHUP에서도 안 쓴다"가 이것 때문에 틀렸다. BH 실측 10이
정정했다 — bash는 SIGHUP에서 쓴다.

처방 둘. `script -qfc "exec bash -i"`로 래퍼를 없애고,
`/proc/<pid>/cmdline`을 함께 찍어 무엇을 잡았는지 눈으로 본다.

측정 설계에도 같은 종류의 함정이 하나 더 있었다. 시그널을 보낸 뒤 `kill
-KILL`로 PTY 주인을 치우고 나서 파일을 읽으면, 그 정리 자체가 PTY를 닫아
SIGHUP을 만든다. 파일은 정리보다 먼저 읽는다. 그 회차의 오류를 알려 준 것은
SIGKILL 칸이 "써진다"로 나온 것이었다 — 핸들러가 없는 시그널은 정리 동작을
할 수 없다.

## 3. 비대화형 셸은 프롬프트 훅을 안 돈다

씨앗 rc에 새 줄을 들일 때 이 저장소의 절차는 "그 줄이 조용한 것을 먼저
재라"이다. SD가 zsh에 대해 `zsh -c '<줄>'`로 stdout·stderr를 세는 방법을
`KNOWN_HIST_OPTIONS`의 주석에 못 박아 두었다.

bash에서는 그 절차가 무력하다. 비대화형 bash는 `PROMPT_COMMAND`를 아예
실행하지 않으므로 오타가 나도 0바이트다.

| 줄 | `bash -c`의 stdout·stderr |
|---|---|
| `PROMPT_COMMAND='history -a'` | 0 · 0 |
| `PROMPT_COMMAND='histori -a'` | 0 · 0 |

같은 오타를 대화형 세션에서 재면 다르다. 명령 셋을 친 세션의 화면 전체가
123바이트에서 225바이트로 늘고, 늘어난 것은 `bash: histori: command not
found` 세 줄이다 — 한 번이 아니라 프롬프트가 그려질 때마다 찍는다.

zsh의 `setopt` 오타가 기동할 때 한 번 stderr 65바이트인 것과 다르다. 그래서
`KNOWN_HIST_OPTIONS`의 주석이 이제 셸별로 재는 방법을 나눠 적는다(BH 결정 5).

## 공통 처방

재기 전에 "재는 환경과 돌 환경이 무엇이 다른가"를 먼저 적고, 그 차이가
재려는 값을 바꾸는지 묻는다. 답이 "모르겠다"면 게스트에서 한 번 확인한다 —
5분이 든다.

BH-M0이 그렇게 했다. 착수 전 실측 여섯을 컨테이너에서 잰 뒤, M0을 통째로
"그 여섯을 게스트에서 확인하는" milestone으로 썼다. 그 M0이 실측 7·8·9를
얻었고 실측 8이 이 문서의 사례 2를 끌어냈다.

## 관련

- [[project_shell_history]] — SD와 BH가 고친 것
- [[project_shutdown_signals]] — 대화형 셸이 SIGTERM을 무시하는 것과 PTY의 운명
- [[project_build_host_arch]] — 컨테이너가 arm64인 데서 오는 다른 제약
