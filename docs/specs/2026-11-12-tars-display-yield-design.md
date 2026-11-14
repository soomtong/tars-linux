# TARS Display Yield — Design

접두사: DY

Date: 2026-11-12
Status: 끝(2026-11-14). DY-M0 · M1 · M2(plan 셋의 결과 절, 체인 `display`). 실기(i915 · crocus)는 `carryover.md`의 DY 절.

계기: 사용자(2026-11-12): TARS가 외주 솔루션 · 프로덕트로 납품되는 경우 — 키오스크는 fakesteak으로 1차 확인, 2차 데모는 GPU를 쓰는
애플리케이션. "예전 DOS 시스템처럼 콘솔 화면이 기본이지만 Full screen graphics 프로그램을 만들어 실행시킬 수 있게 확장; KMS master를
terminal이 독점하는 구조를 개선하자." 후보 셋(DROP/SET_MASTER · DRM lease · terminal 없는 boot 모드)과 "메인 터미널을 GPU 기반으로"를
놓고 논의한 뒤: "SDL 3 갑시다. 나머지는 모두 당신의 추천대로 진행합니다."

관련 문서: IS(`project_init_supervisor` — 10초 미만 연속 3회면 포기) · RS-M3(`drm.zig`의 `modeset` 한 번 + DIRTYFB) · FU design(패널의
프로그램이 화면 상태를 요청하는 선례, autorun 조각의 SIGINT 함정) · HP-M1(udev 없이 장치 노드의 그룹을 여는 선례 `openToAudio`) ·
CT design(`/run/tars/init.sock` — SEQPACKET 제어 socket의 선례) · BB design 결정 5(기기를 고치러 온 사람은 셸을 본다).

## 한 줄 요약

terminal은 CPU로 그리는 콘솔 그대로 남고, 프로그램이 요청하면 DRM master를 내려놓는다(DROP_MASTER). 프로그램은 `/dev/dri/card0`을 직접
열어 화면의 주인이 되고, 끝나면(어떻게 죽든) terminal이 master를 되찾아 모드를 다시 걸고 화면을 통째로 그린다. 요청은 unix socket
하나이고 그 연결이 살아 있는 동안이 양보 기간이다. 2차 데모는 그 위의 SDL3 프로그램이다.

## 확인

### 커널 (2026-11-12, 프로브 `display/probe/kms-handover.c`, 기록 `display/probe/kms-handover.log`)

TARS 커널이 아니라 Ubuntu의 6.17.0-42 커널 + `virtio-gpu.ko`를 QEMU 8.2(TCG, `-device virtio-gpu-pci`)에 띄워 쟀다. fbdev 에뮬레이션은
TARS처럼 껐다(`drm_kms_helper.fbdev_emulation=0`, TARS는 `# CONFIG_DRM_FBDEV_EMULATION is not set`). A는 terminal 역(먼저 열어 master),
"앱"은 `card0`을 스스로 여는 자식이다. TARS의 6.18 · i915에서는 DY-M0의 게이트와 실기가 다시 본다(위험 1).

1. A가 master인 동안 다른 프로세스가 `card0`을 열 수는 있다. 그 fd의 SETCRTC는 `EACCES`이고 화면(A의 fb)은 그대로다(T1).
2. A의 `DROP_MASTER`는 성공하고, 그 뒤 A의 DIRTYFB · SETCRTC는 `EACCES`다. 화면은 A의 fb가 걸린 채 남는다 — 놓는다고 꺼지지 않는다(T2).
   지금의 terminal은 `present`가 실패하면 `try`를 타고 죽는다(아래 6) — 양보 중에는 present를 부르지 않아야 한다.
3. master가 없을 때 `card0`을 새로 연 프로세스는 저절로 master다. root도(T3) uid 1000도(T5, 노드가 열려 있을 때) SETCRTC가 성공한다.
   `SET_MASTER`를 부를 필요가 없다 — SDL의 KMSDRM처럼 `card0`을 직접 여는 기성 프로그램이 고치지 않고 돈다.
4. 앱이 master인 동안 A의 `SET_MASTER`는 `EBUSY`다. terminal은 강제로 되찾을 수 없다 — 앱의 fd가 닫혀야 한다(T3).
5. 앱이 죽으면(SIGKILL · 정상 종료 둘 다) 그 fb가 사라지고 CRTC는 `fb_id=0 mode_valid=1` — 모드는 살아 있고 그림이 없다(검은 화면).
   A의 `SET_MASTER`는 성공한다. 그 뒤 DIRTYFB는 성공하지만 A의 fb가 걸려 있지 않아 아무것도 안 바뀌고, SETCRTC를 해야 A의 fb가
   돌아온다(T4 · T5). 사용자의 추정("fd가 닫히면 framebuffer가 정리되면서 화면이 검게")이 복귀 쪽에서 맞았다.
6. lease(T6): `CREATE_LEASE`는 fd를 돌려준다(pid에게 주는 것이 아니다). 임차 fd의 SETCRTC는 성공한다. 그런데 임대 중에도 A의
   DIRTYFB · SETCRTC는 성공해 화면을 도로 가져간다 — lease는 독점이 아니다. `REVOKE_LEASE` 뒤 임차 fd는 자원이 0개로 보이고 SETCRTC는
   `ENOENT`, 화면에는 임차인의 마지막 fb가 A가 SETCRTC할 때까지 남는다.

### 저장소 (HEAD `547c3fc`)

7. terminal은 root로 돌고(`init/src/main.zig`의 `children[0]`) `card0`을 `drm.open`(`terminal/src/drm.zig:432`)으로 한 번 연다 — 처음 여는
   것이라 master다. `modeset`(`:268`, SETCRTC)은 시작에 한 번, 프레임은 `present`(`:293`, DIRTYFB)다.
8. present를 부르는 자리는 둘이다: `presentFrame`(`terminal/src/main.zig:638`, `render`가 `:4897`에서) · 화살표만 옮기는 길(`decideFrame`,
   `:4746`). 둘 다 `try`이고 `main`은 `while (try app.tick()) {}`(`:5172`) — present의 실패는 프로세스의 끝이고 init이 되살린다.
9. 화면을 통째로 다시 그리는 관용구는 `self.last_tree = null; self.needs_redraw = true;`(`setFullscreen`, `main.zig:4300-4315`).
10. poll 배열은 `App.arm()`(`main.zig:4007-4037`)이 매 tick 다시 짠다. 마지막 두 칸은 받아쓰기 자식의 fd이고 없으면 -1이다 — "쓸 때만
    사는 칸"의 선례다. 크기는 `main.zig:3602`의 `… + 2`.
11. 패널의 셸은 uid 1000이다. `pty.dropTo`(`terminal/src/pty.zig:48-57`)가 `setgroups`로 `{SUDO_GID, AUDIO_GID}`를 준다(`main.zig:1676`,
    `pty.zig:37`의 `groups: [2]`). `/etc/group`의 바탕은 `kernel/make_initrd.sh:650-657`(video 없음), 사용자를 넣는 그룹은
    `init/src/account.zig:147`의 `MEMBER_GROUPS = { "audio", "sudo" }`.
12. devtmpfs의 노드는 root 0600이다(프로브의 `ls -l /dev/dri`: `crw------- card0`, `renderD128`). udev가 없어 그룹을 여는 것은 init의
    일이고 선례가 `openToAudio`(`init/src/audio.zig:174-206`, `/dev/snd`를 `root:audio 0660`으로).
13. 제어 socket의 선례: `/run/tars/init.sock`(`init/src/control.zig:16-17`, `AF_UNIX` · `SOCK_SEQPACKET` · `CLOEXEC`).
14. 키 입력은 `readKeyboards` → `input.readKeys` → `State.handleKey`(`terminal/src/input.zig:1403`). "하나만 빼고 다 삼키는" 모드는 없다
    (copy 모드가 가장 가깝다). terminal은 evdev를 `EVIOCGRAB` 없이 읽는다 — 앱이 같은 장치를 열면 둘 다 읽는다.
15. 작은 명령은 `init/build.zig`의 정적 실행 파일 하나씩이다(`tars-service` `:86-91`). initrd에 싣는 자리는 `kernel/make_initrd.sh:163-173`,
    strip 목록은 `:194`의 `OWN_BINS`.
16. 게이트가 화면 자체를 보는 길: QEMU monitor의 `screendump` + PPM 읽기(`fullscreen/check.sh`의 `screendump` `:126` · `ppm_ink` `:139`).
    monitor 포트는 45455-45599에서 고르고 45506까지 쓰였다.

## 결정

1. 길은 DROP_MASTER / SET_MASTER다. terminal은 fd도 fb도 놓지 않고 master 자격만 내려놓는다(확인 2 · 3 · 5). 까닭: 앱 쪽 드라이버가
   필요 없고(확인 3), terminal이 살아 있으니 감독 루프가 건드릴 일이 없다(`given_up` 걱정이 사라진다).
   lease는 고르지 않는다 — 독점이 아니고(확인 6) fd를 받아 쓰는 기성 프로그램이 드물며, 이점(출력별 임대 · 강제 회수)은 출력이 여럿일 때
   것이다. terminal은 출력 하나에 그린다(LP design 비목표 5).
2. terminal은 CPU 렌더 그대로다. GPU 터미널은 열지 않는다 — PID 1의 콘솔이 Mesa에 기대면 GPU 없는 장비와 드라이버가 깨진 장비에서 콘솔을
   잃는다. 키 하나 0.42ms 가운데 0.27이 커널 쪽이라(DR design) 얻을 것도 작다. 아웃라인 폰트 · 알파 블렌딩은 CPU로 되는 일이라
   2026-11-08의 "real font system은 GPU 단계와 함께"는 이 결정과 묶이지 않는다 — 그 서브프로젝트를 열 때 다시 정한다.
3. 요청은 socket이다. terminal이 `/run/tars/display.sock`(`SOCK_SEQPACKET`, `root:video 0660`)을 듣는다. 손님은 한 번에 하나다.
   - 손님 → `yield`. terminal → `ok`(master를 놓았다) · `busy`(이미 양보 중) · `refused`(놓지 못했다 — errno를 로그에).
   - 연결이 살아 있는 동안이 양보 기간이다. 끝내는 메시지는 없다 — 연결이 닫히면(HUP) 되찾는다. 앱이 어떻게 죽든 커널이 fd를 닫으므로
     끄기 신호가 안 도는 일(FU-M1의 SIGINT 함정)이 구조적으로 없다.
   - 패널 출력의 escape sequence로 하지 않는 까닭이 그것이다. 그리고 요청은 패널 밖(ssh · 서비스)에서도 올 수 있어야 한다.
4. 실행기는 `tars-fullscreen <명령> [인자…]`다. socket에 연결해 `yield` → `ok`를 받고, 그 fd를 연 채로(`CLOEXEC` 없이) 명령을 `execvp`한다.
   fork하지 않는다 — 앱이 실행기의 자리(pid · 전경 job)를 그대로 잇고, fd는 앱과 그 자손이 다 죽을 때 닫힌다. `ok`가 아니면 까닭을 찍고
   0이 아닌 값으로 끝난다(앱을 띄우지 않는다). DOS에서 프로그램 이름을 치는 것과 같은 모양이다.
5. 양보 중의 terminal: present를 부르지 않는다(확인 2 · 8 — 두 자리를 한 판정으로 막는다). 그 밖은 평소대로 돈다 — PTY를 읽어 vt 상태에
   쌓고(뒤의 프로그램이 멈추지 않는다) 배터리 · 장치 hotplug도 본다. 그릴 것이 생겼다는 표시(`needs_redraw`)는 남겨 두었다가 복귀 때 쓴다.
6. 복귀: HUP → `SET_MASTER` → `modeset()` → `last_tree = null; needs_redraw = true`(확인 5 · 9). `SET_MASTER`가 `EBUSY`면(연결은 닫혔는데
   누군가 아직 master — 앱이 fd를 스스로 닫고 계속 도는 경우) 양보 상태로 남아 1초마다 다시 해 본다. 그 줄은 처음 한 번만 찍는다.
7. 장치 문: `video` 그룹(gid 44 — Debian의 번호)을 만들고 사용자를 넣는다(확인 11의 세 자리). init이 `/dev/dri`의 노드를
   `root:video 0660`으로 연다(확인 12, `openToAudio`의 모양 — `renderD128`도 함께, DY-M2의 GL이 쓴다). master가 있는 동안 남이 여는
   것은 해가 없다(확인 1).
8. 입력(DY-M1, 사용자 2026-11-13 — 추천안 둘에 동의): 양보 중 terminal은 키를 셸에 넣지 않는다 — 앱이 같은 evdev를 직접 읽는다.
   - 문(8a): `input` 그룹은 만들지 않는다. terminal이 양보를 받는 순간 `/dev/input/event*`의 주인을 손님의 uid로(`SO_PEERCRED`, 모드 600
     그대로) 바꾸고, 되찾을 때와 terminal이 뜰 때 root로 되돌린다. 키를 읽을 수 있는 때가 "그 사람이 띄운 전체 화면 프로그램이 도는 동안"
     뿐이다 — 평소의 sudo 암호는 사용자 프로세스가 못 읽는다(위험 4). 기성 프로그램은 고치지 않고 돈다(그 순간 열려 있을 뿐이다).
     양보 중에 연 fd는 되돌린 뒤에도 유효하다(권한은 open 때만 본다). 양보가 끝났다는 것이 곧 앱과 자손이 다 죽었다는 뜻이라 보통은
     남지 않는다. logind처럼 fd를 넘겨주고 `EVIOCREVOKE`로 끊는 길은 앱이 그 fd를 받도록 고쳐져야 해서 고르지 않는다.
   - 탈출(8b): `Ctrl+Cmd+Backspace`(PC 키보드에서 `Ctrl+Alt+Backspace` — X11의 zap과 같은 자리). 양보 중에도 terminal은 키를 읽고 있으므로
     이 조합만 본다: 손님의 프로세스 그룹에 SIGTERM, 2초 안에 연결이 안 닫히면 SIGKILL. 멈춘 앱에서 다른 패널을 살린 채 콘솔로 돌아오는
     유일한 길이다(확인 4 — 강제로 못 되찾는다. 나머지 길은 ssh · `Ctrl+Alt+Del` 재부팅 · 전원 버튼이다). 앱이 키보드를 독점(`EVIOCGRAB`)하면
     terminal도 이 조합을 못 본다 — SDL3의 evdev는 독점하지 않는다(DY-M1 결과 6).
9. 로그 줄(게이트와 사람이 같은 줄을 본다): `terminal: display> yield pid N` · `terminal: display> busy pid N` ·
   `terminal: display> reclaim` · `terminal: display> waiting for master`.
11. master가 아닌 채 뜬 terminal(DY-M1, 위험 2): 첫 `modeset`이 `EACCES`면 죽지 않고 `waiting`으로 뜬다 — 그리지 않고 1초마다 `SET_MASTER`를
    다시 해 본다. 되찾으면 `modeset` · 통째 그리기. DIRTYFB를 받는지 묻는 것(`drm.open`)도 master가 아니면 `EACCES`라 답이 아니다 — 되찾은
    뒤 다시 묻는다. 이 terminal은 손님을 모른다(옛 연결은 옛 terminal과 함께 닫혔다) — 그래서 키는 셸에 그대로 넣고 탈출 조합도 없다.
10. 2차 데모(DY-M2)는 SDL3 + `SDL_Renderer`(GLES)다. `SDL_GPU`는 쓰지 않는다 — Vulkan이 있어야 하는데 납품 기준 실기(맥북 에어 2011)에는
    없다. Mesa와 SDL3은 개발 도구 층의 새 묶음으로 싣는다. 크기 · 드라이버 · udev 없는 입력은 DY-M2 plan의 조사 몫이다.
    DY-M2가 정한 것: Debian trixie의 패키지 그대로(묶음 `gpu` — SDL3 3.2.10 · Mesa 25.0.7 · LLVM 19, zstd15로 68MiB), 키는 SDL이 libudev로
    `/sys`를 훑어 받는다(힌트 없음), 데모 `tars-gpu-demo`는 initrd에 있고 `libSDL3.so.0`을 dlopen한다.
12. GPU 데모 판(DY-M3, 사용자 2026-11-14: "0.2.2 작업의 핵심은 gpu 관련 기능이야. 이 데모를 위해 fakesteak 처럼 하나의 iso 파일을
    구워줘"). ISO는 base · gpu 두 묶음만 싣는다(gpu는 base에 기대므로 독립 묶음이 될 수 없다 — Mesa · SDL3의 glibc 짝이 base에 있다).
    부팅 뒤 첫 패널이 `tars-fullscreen tars-gpu-demo`를 스스로 띄운다 — 조각은 gpu 묶음의 `etc/tars/rc.d/gpu.sh` ·
    `etc/fish/conf.d/90-gpu-demo.fish`이고, 얹힌 묶음이 base와 gpu 둘뿐일 때만 뜬다(출처 기록 `/usr/share/tars/layers/*`로 판정).
    fakesteak의 조각(BB 결정 6, LD-M0의 "base가 없을 때만")과 같은 넷 — 대화형 · terminal의 패널 · ssh 아님 · 이번 부팅에 처음
    (`/tmp/.tars-autorun`을 함께 쓴다) — 을 본다. 새 묶음을 만들지 않은 것: 묶음은 매니페스트 줄이 있어야 서고(`build.sh`),
    파일만 싣는 묶음의 길은 없다. 개발 도구 묶음이 하나라도 함께 얹힌 판(기본 판 · nonative)에서는 뜨지 않는다.

## 비목표

- DRM lease, 출력 여럿(terminal과 앱이 화면을 나눠 쓰는 것).
- terminal을 안 띄우는 boot 모드(`tars.conf`로 앱을 감독 자식에 두는 것). 순수 키오스크 납품이 실제로 생기면 연다.
- GPU로 그리는 terminal, terminal이 앱의 버퍼를 받아 합성하는 것(컴포지터).
- VT 전환(`CONFIG_VT=y`지만 terminal은 VT를 쓰지 않는다).
- 양보 중 terminal의 알림을 앱 화면 위에 띄우는 것.

## 위험

1. 프로브는 6.17 · virtio-gpu다. i915(실기) · simpledrm에서 앱이 죽은 뒤의 CRTC 상태, DIRTYFB가 없는 드라이버의 길(`present`가 SETCRTC —
   확인 8과 같은 판정으로 막힌다)은 다를 수 있다. DY-M0 게이트가 TARS 커널의 virtio-gpu를, 실기 확인이 i915를 본다.
2. 양보 중에 terminal이 다시 뜨면(`reload terminal` · 죽음) 새 terminal은 master가 아니라 첫 `modeset`이 `EACCES`로 죽고, 그것이 10초 안에
   세 번이면 `given_up`이다. DY-M0은 이 길을 막지 않는다 — DY-M1이 "master가 아니면 기다린다"를 넣는다. 그때까지는 알려진 구멍이다.
3. 앱이 남긴 것: 다른 해상도 · 커서 plane · 감마. `modeset`은 terminal이 기억한 모드를 다시 걸므로 해상도는 돌아온다. 커서 plane과 감마는
   프로브가 보지 않았다 — DY-M2에서 SDL이 남기는지 본다.
4. `video` 그룹의 사용자는 양보 중이 아닐 때도 `card0`을 열 수 있다. master가 아니라 화면은 못 바꾼다(확인 1). 키보드는 무게가 다르다 —
   읽는 프로세스는 sudo 암호를 포함한 모든 키를 본다. 그래서 늘 열린 `input` 그룹 대신 양보 동안만 손님의 uid에게 연다(결정 8a). 남는 틈:
   양보 중에 앱이 남긴 자손이 키보드 fd를 쥔 채 프로세스 그룹을 떠나면 탈출 조합의 신호가 닿지 않는다.
5. 양보 중의 절전(S3) · 덮개. 깨어난 뒤 화면을 다시 거는 것은 master인 앱의 몫이 된다. DY-M0은 보지 않는다.
6. 이 세션(클라우드 컨테이너)에는 devcontainer와 게이트가 없다. 프로브는 여기서 돌렸지만 TARS 빌드와 게이트는 사용자의 기계에서 돈다.

## Milestone

- DY-M0 — 양보와 복귀. `video` 그룹과 `/dev/dri`, socket, `tars-fullscreen`, dumb buffer로 화면을 한 색으로 칠하는 시험 프로그램
  (`tars-kms-fill`, initrd에 싣는다 — 실기에서도 같은 것으로 본다), 새 체인 `display`. Mesa도 SDL도 없다 — 양보의 문제와 GL의 문제를 섞지 않는다.
- DY-M1 — 입력 양보(결정 8a — 양보 동안만 손님의 uid에게)와 탈출 조합(결정 8b), master가 아닌 채 뜬 terminal의 기다림(결정 11).
- DY-M2 — Mesa · SDL3 묶음과 데모 프로그램. plan은 M1의 게이트가 도는 동안 조사부터.
- DY-M3 — GPU 데모 판(결정 12). plan `docs/plans/2026-11-14-tars-display-yield-dy-m3.md`.
