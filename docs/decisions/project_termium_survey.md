---
name: project_termium_survey
description: "termium(headless Chromium의 스크린샷을 kitty graphics · sixel · 반 블록으로 터미널에 그리는 브라우저)을 조사만 했다(2026-10-01). 게스트가 전부 root이고 커널에 USER_NS · PID_NS · SECCOMP가 없어 설치 단계에서 막힌다. 사용자는 그 아래 층인 '터미널이 그림을 그리는 것'을 향후 후보로 남겼다"
metadata:
  type: project
---

# termium 조사 (2026-10-01, 코드 0줄)

사용자가 https://termium.dev/ (저장소 https://github.com/codr1/termium)를 "웃기지만 TARS가
포함해야 할 기능 같다"며 보여 줬다. 조사는 `/tmp`에서 소스와 문서를 읽고 우리 설정과
대조한 것까지다. 게스트에서 띄워 보지는 않았다.

결론은 사용자가 정했다 — 조사만 기록한다. 터미널에 그래픽을 그리는 것은 향후 유용할
것 같다(아래 "남긴 후보").

## termium이 무엇인가

- 세 프로세스다. Go 클라이언트(터미널 UI) ─gRPC─▶ Node 서버(TypeScript) ─Puppeteer/CDP─▶
  headless Chromium. 서버가 스크린샷을 찍어 클라이언트에 보낸다.
- 터미널이 지원하는 가장 좋은 출력을 고른다. kitty graphics(Chromium의 PNG를 그대로 보낸다)
  → sixel → 컬러 반 블록 문자. 페이지 글자도 그림의 일부라 터미널 글자로 선택되지 않는다.
- Vimium이 들어 있어 키보드로 링크 · 탭을 다룬다. ssh 너머에서도 돈다.
- MIT, 조사 시점 v0.2.4. linux-amd64 묶음 압축 171MB(Node · 브라우저 라이브러리 · 폰트),
  Chromium은 설치 때 따로 받는다. glibc는 호스트 것을 쓴다.

## 막히는 곳 — 브라우저면 무엇이든 같은 자리

| 층 | TARS | 요구 |
|---|---|---|
| 사용자 | 게스트가 전부 root(`init/src/login.zig`의 passwd 두 줄) | Chromium은 root에서 `--no-sandbox` 없이 안 뜬다 |
| 커널 | `kernel/.config`에 `# CONFIG_USER_NS` · `# CONFIG_PID_NS` · `# CONFIG_SECCOMP` | 설치기 `server/src/check-install.ts`가 `chrome://sandbox`의 "Seccomp-BPF sandbox Yes"를 요구하고, 아니면 설치를 실패로 끝낸다. sandbox를 끄는 길은 일부러 없다 |
| 저장 · 메모리 | 루트는 RAM 위 initrd, 문서의 QEMU는 `-m 1024` | 수백 MB를 홈에 푼다 — 설치 디스크에 자리가 필요하다 |

non-root 사용자는 TARS 전체 모양을 바꾸는 결정이고, 저장 위치는 패키지 관리자와 겹친다.
브라우저는 그 둘 뒤에 놓는 것이 자연스럽다.

## 남긴 후보 — 터미널 그래픽

이 조사가 남긴 후보("ghostty vt는 `kitty_graphics`가 켜져 들어오고 빠진 것은 우리
렌더러다")는 TG가 2026-10-03에 구현했다([[project_terminal_graphics]]). termium의 최고
화질 모드가 그 위에 서는 것은 그대로다.

남의 것을 쓸지 짤지의 기준은 [[project_write_or_reuse]]. 같은 날 조사만 한 것으로
[[project_latticedb_survey]]가 있다.
