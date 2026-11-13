---
name: project_display_yield
description: "화면 양보(DY, 2026-11-12 열림, M0 2026-11-13 끝) — terminal은 CPU 콘솔 그대로, 프로그램이 socket으로 요청하면 DROP_MASTER로 master만 놓는다 · 연결이 살아 있는 동안이 양보 기간 · 복귀는 SET_MASTER + SETCRTC + 통째 그리기 · lease는 독점이 아니라 안 쓴다 · 2차 데모는 SDL3 + SDL_Renderer · 커널 동작은 프로브로 쟀다 · card0 fd가 셸로 새던 것을 CLOEXEC로 막았다"
metadata:
  node_type: memory
  type: project
---

사용자(2026-11-12)가 납품 시나리오(키오스크 다음의 2차 데모 = GPU를 쓰는 프로그램)를 두고 KMS master 독점을 풀자고 했고,
논의 뒤 "SDL 3 갑시다. 나머지는 모두 당신의 추천대로"로 맡겼다. design은 `docs/specs/2026-11-12-tars-display-yield-design.md`,
DY-M0 plan은 `docs/plans/2026-11-12-tars-display-yield-dy-m0.md`. DY-M0은 2026-11-13 로컬 세션에서 끝났다(체인 `display`) — 다음은 DY-M1.

## 다시 조사하지 말 것 (프로브 `display/probe/kms-handover.c` · `.log`, 6.17 · virtio-gpu · fbdev 에뮬레이션 끔)

1. master가 있는 동안 남이 `card0`을 열면 SETCRTC가 `EACCES`. 화면은 그대로다.
2. `DROP_MASTER` 뒤 놓은 쪽의 DIRTYFB · SETCRTC는 `EACCES`. 화면은 안 꺼진다. terminal의 present는 `try`라 부르면 죽는다.
3. master가 없을 때 `card0`을 새로 여는 프로세스는 저절로 master(uid 1000도). `SET_MASTER`를 부를 필요가 없다 — 기성 프로그램이 그대로 돈다.
4. 남이 master인 동안의 `SET_MASTER`는 `EBUSY`. 강제로 못 되찾는다 — 그 fd가 닫혀야 한다.
5. 앱이 죽으면 CRTC는 `fb_id=0 mode_valid=1`(검은 화면). `SET_MASTER` 뒤 SETCRTC를 해야 돌아온다(DIRTYFB만으로는 안 된다).
6. lease: `CREATE_LEASE`는 fd를 준다. 임대 중에도 임대인의 SETCRTC가 성공한다(독점 아님). 회수 뒤 임차 fd는 자원 0개 · `ENOENT`.
7. 프로브의 함정 둘: GETCONNECTOR는 버퍼 없이 한 번 먼저 불러야 mode가 채워진다 · C의 `printf` 인자는 평가 순서가 없다(ioctl을
   인자 자리에 나란히 두었다가 순서가 뒤집혀 첫 기록을 버렸다).

## DY-M0이 더 잰 것 (TARS 커널 6.18, 체인 `display`)

8. uid 1000이 연 card0만으로 master — 6.18 · virtio-gpu에서도 1 · 3과 같다(`tars-kms-fill: setcrtc ok`).
9. DY 전에는 terminal의 card0 fd가 CLOEXEC 없이 열려 화면 셸과 그 자손(uid 1000)에게 샜다 — master인 drm_file이라 양보 없이 SETCRTC가 됐다.
   `drm.open`이 `O_CLOEXEC`로 막고, display 체인 판정 1(`d2-0`)이 본다. 빨강 판(CLOEXEC 뺌)은 `d2-1`이었다.
10. 둘째 손님은 connect가 accept보다 먼저 서고 terminal이 받자마자 `busy`를 보내고 닫으므로, 손님의 send가 EPIPE일 수 있다 — 그래도 답은
    소켓에 와 있다. `tars-fullscreen`은 send가 실패해도 읽는다.
11. `/dev/dri`의 노드 수: virtio-gpu 2(card0 + renderD128), 기본 VGA(bochs-drm) 1.

## 왜 이렇게 골랐나

- lease가 아니라 DROP_MASTER: 앱 쪽 드라이버가 필요 없고(3), lease의 이점은 출력이 여럿일 때 것이다.
- escape sequence가 아니라 socket: 연결의 수명이 양보의 수명이라 앱이 어떻게 죽든 돌아온다(FU-M1의 SIGINT 함정이 구조적으로 없다).
- GPU 터미널은 안 연다: PID 1의 콘솔이 Mesa에 기대면 안 된다. 폰트(알파 블렌딩)는 CPU로 되는 일이라 따로 정한다.
- `SDL_GPU`가 아니라 `SDL_Renderer`: 맥북 에어 2011에 Vulkan이 없다.

## 양보 중의 terminal

`tick`이 `decideFrame` · `render`를 통째로 건너뛴다(present 두 자리를 한 판정으로). PTY는 계속 읽어 vt에 쌓고, `output_pending`은
`needs_redraw`로 옮긴다 — 남기면 `pacing.wait`가 0이라 poll이 헛돈다. 복귀는 `last_tree = null; needs_redraw = true`.

## 알려진 구멍

양보 중에 terminal이 다시 뜨면(`reload terminal` · 죽음) 새 terminal의 첫 modeset이 `EACCES`로 죽어 `given_up`까지 갈 수 있다.
DY-M1이 "master가 아니면 기다린다"로 막는다(design 위험 2).

## 이 세션의 환경

클라우드 컨테이너(x86_64, KVM · docker 데몬 · zig 없음)에서 썼다. TARS 빌드와 게이트는 못 돌렸고, 프로브는 apt의 QEMU와 Ubuntu 커널로
돌렸다 — 커널의 동작을 묻는 프로브는 TARS 빌드 없이도 이렇게 잴 수 있다.
