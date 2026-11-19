# WY-M1 — 둠이 Wayland 창으로

Date: 2026-11-19
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(Milestone 표의 WY-M1, 결정 13)
Status: 구현 · 게이트 끝(2026-11-20). 남은 것은 tars-doom의 push · release와 manifest sha256 바꾸기(결과 끝). 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

조사(읽기만)는 Herdr 서브에이전트 `wy-impl`이 했다(세션 scratchpad `wy-m1/research.md`, 근거는 파일:줄). 구현도 서브에이전트에
두 단계로 맡긴다. lead는 plan · 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다(tars-doom 저장소도 같다).

- 단계 A — tars-doom의 포트(`../tars-doom`, 별도 저장소). 할 일 1 · 2.
- 단계 B — TARS 쪽: devlayer 묶음 `doom` · 체인 `wayland`의 부팅 2 · 도움말. 할 일 3 · 4 · 5.

## 이 milestone이 끝나면

- 셸에서 `tars-doom &`을 치면 둠(Freedoom Phase 1)이 새 workspace에 화면 가득(1280x800에서 4배) 뜬다.
- 키가 둠에 간다 — 화살표로 걷고 Ctrl로 쏜다. `Cmd+1`로 셸에 가도 플레이어가 걷던 채로 남지 않는다.
- `Cmd+Q`로 둠이 스스로 끝난다(SIGKILL 없이 — pong과 close를 포트가 받는다).

## 착수 전에 확정한 것

1. 포트는 tars-doom에 `doomgeneric/doomgeneric_wayland.c`와 `Makefile.wayland`(linuxvt 모양 + `-lwayland-client`)를 더한다.
   Wayland 포트는 upstream에도 PR에도 없다(조사 1). xdg-shell 클라이언트 코드는 `wayland-scanner`로 한 번 만들어 커밋한다
   (xml은 우리 `terminal/vendor/wayland/xdg-shell.xml`과 같은 1.44) — 빌드하는 자리에 scanner가 필요 없다.
2. 해상도 `-DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200`. 엔진의 늘리기를 끄고 우리 서버가 정수 배율로 늘린다(결정 9 —
   `wl_logic_test`가 이미 320x200을 검사한다). 버퍼 256,000 B, 형식 `XRGB8888`(엔진 픽셀이 `0x00RRGGBB`, 알파 0 — 조사 1).
3. 그리기(`DG_DrawFrame`)는 막지 않는다. 이벤트를 poll 0으로 읽고, 앞 frame 콜백이 안 왔으면 그 프레임은 버린다. 왔으면
   `release`된 shm 버퍼(둘을 돌려쓴다 — 서버가 commit 때 복사하지 않으므로, 확정 8)에 memcpy → attach · damage · frame · commit.
   막으면 숨은 workspace(`done`이 안 온다)에서 `TryRunTics`가 통째로 서서 pong도 못 한다.
4. 숨으면 쉰다. `leave`를 받은 동안 `DG_SleepMs`가 최소 20ms를 잔다 — 바쁜 둠이 셸(QEMU TCG)을 늦추지 않게. 게임 시간은
   흘러도 된다(키를 안 받으니 플레이어는 서 있다).
5. 키는 xkb 없이 evdev → 둠 키 `switch` 하나(linuxvt의 `convertToDoomKey`를 고쳐 쓴다 — 그 표의 `evdevKeysToASCII3`에 `'i'`가
   끼어 J · K · L · `;` · `'`이 한 칸 밀린 버그를 베끼지 않는다). Ctrl → FIRE, Shift → RSHIFT(달리기), Alt → LALT(옆걸음),
   Super(125 · 126)는 버린다. `keyboard=pc`에서 물리 Alt는 Cmd로 오므로 옆걸음은 물리 Win이 된다 — 받아들이고 `,` · `.`
   (STRAFE_L/R)를 함께 둔다. `leave` 때 쥔 키를 전부 뗀 것으로 큐에 넣는다.
6. `xdg_toplevel.close` → `exit(0)`, ping → pong, 첫 commit은 버퍼 없이 → configure ack 뒤 버퍼(서버의 `onCommit`이 순서를
   강제한다). `set_fullscreen`과 `set_title`("Freedoom")을 부른다.
7. WAD: `-iwad`가 없으면 실행 파일 옆(`/proc/self/exe`의 `../share/doom/freedoom1.wad`)을 기본으로 넣는다 — 셸 셋에 `DOOMWADDIR`을
   까는 것보다 한 자리다. 소리는 끈다(`FEATURE_SOUND` 없음 — SDL_mixer가 따라오지 않는다).
8. 빌드 자리: tars-doom의 GitHub Actions(`container: debian:trixie` x86_64 — glibc 2.41 · libwayland-client 1.23.1이 initrd와 같은
   판), `-O2 -march=x86-64`, tarball `tars-doom-<ver>-linux-x86_64.tar.gz`(`bin/tars-doom` · `LICENSE` · README). 이유: GPL 소스와
   바이너리가 한 저장소(소스 제공이 자명), TARS 빌드에 C 경로를 안 들임, fakesteak이 같은 모양(design 결정 13).
   tars-doom에 push · 태그 · release를 내는 것은 밖으로 나가는 일이라 사용자에게 먼저 묻는다. 그 전의 게이트 개발은 같은 컨테이너
   (`docker run --platform linux/amd64 debian:trixie`)로 로컬에서 만든 tarball을 `devlayer/cache/<sha256>`에 두고 한다.
9. 묶음 `doom`(`devlayer/manifest.toml`): `tars-doom`(kind upstream, exe `bin/tars-doom`) + `freedoom`(upstream, 0.13.0 zip
   `3f9b264f…8f59` — 서명된 CHECKSUM과 받은 파일이 같음, `into = "tars-doom"`, hook `freedoom`이 `freedoom1.wad` · `COPYING.txt` ·
   `CREDITS.txt`만 남긴다 — BSD 고지). `devlayer/standalone-bundles`에 `doom`(initrd 라이브러리만 쓴다). 기본 `DEV_LAYERS`에 넣는다 —
   게이트가 묶음을 굽는 목록이 그것이라서다(gpu와 같은 까닭). 크기는 `DEV_MEASURE=1`로 재 plan 결과에 적는다.
10. 체인은 `wayland/check.sh`에 부팅 2를 더한다(요구사항 결정 12). 모양은 `display/check.sh` 부팅 3 — 홈 디스크에 `doom.sqfs` ·
    `version`, `-nic none`. `Makefile`의 `check`가 `dev-layers`를 먼저 부르는 filter에 `wayland`를 더한다.

## 체인 `wayland` 부팅 2의 판정

`tars-doom -warp 1 1 -skill 1 -nomonsters > /tmp/doom.log &` — 데모 순환(타이틀 4.9초 뒤 데모)을 피해 결정적인 시작.

10. `tars-init: overlay /usr from N layers`, `wl> toplevel id=… ws=2`, `wl> commit id=… buf=320x200 scale=4 at=0,0`.
11. 상태 줄(화면 y 672-799)에서 얼굴을 뺀 고정 상자 하나의 색 — 값은 첫 실측 screendump로 정한다(DY가 tars-kms-fill 색을 정한
    순서). 1초 간격 두 장에서 같아야 한다(멈춘 부분이라는 확인).
12. 키: `sendkey ctrl` → `wl> key code=29 state=1 to=…`, 탄약 숫자 칸(50 → 49)의 픽셀이 바뀐다.
13. `Cmd+1` → 셸(`pane>` 줄) · `echo alive`가 그려진다, `Cmd+2` → 다시 둠.
14. `Cmd+Q` → `wl> close` · `wl> gone`, `wl> kill`은 없다(포트의 pong · close). `ws=1/1`.
15. `wl> key` 줄 수를 plan 결과에 적는다(WY-M0 결과의 걱정 — 누름 · 뗌마다 한 줄).

## 할 일

1. (A) 포트 · Makefile · scanner 산출물 · 키 표, 로컬 컨테이너 빌드(NEEDED가 libc · libm · libwayland-client뿐인지, `%ymm` 0).
2. (A) Actions workflow(`.github/workflows/release.yml`, 태그에서 tarball + 자산). push는 lead가 사용자에게 물은 뒤.
3. (B) manifest 두 줄 · hook `freedoom` · standalone · `DEV_LAYERS` · 로컬 tarball로 `make dev-layers`.
4. (B) 체인 부팅 2 · 판정 10~15 · Makefile filter.
5. (B) 도움말 `docs/help/desk.md`에 `tars-doom` 한 줄(키 · `Cmd+Q`).
6. lead: 체인 `wayland` · `devtools`(묶음 목록 · 수를 박은 판정이 있다 — LD-M0의 교훈), 루트 게이트.

## 판정

- 체인 `wayland`(부팅 1 · 2) PASS, `devtools` PASS, 루트 게이트 35/35, verify mismatch 0.

## 결과

1. 포트(tars-doom 브랜치 `wayland`, 로컬 commit `5179493`, push 안 함): `doomgeneric_wayland.c`(626줄) · `Makefile.wayland` · scanner 산출물 ·
   release workflow · `scripts/build-local.sh`. 첫 컴파일에 오류 없음, 포트 파일의 경고 0(엔진의 upstream 경고 14는 그대로).
   NEEDED는 `libwayland-client.so.0` · `libc.so.6`(libm은 as-needed로 빠짐), 요구 glibc 최고 `GLIBC_2.34`, `%ymm` 0, strip한 실행 파일 488,264 B,
   tarball 약 226 KB. tarball의 mtime이 마지막 commit 시각이라 commit마다 sha256이 바뀐다 — `5179493`의 것이 `0da0b4a7…`.
2. 묶음 `doom`: zstd15 약 9 MiB(`doom.sqfs` 9,408,512 B, 풀면 27 MiB), 기본 ISO가 그만큼 커진다. devtools 체인의 묶음 수 13 → 14.
3. 체인 `wayland` 부팅 2는 설정 디스크 없이 홈 디스크만(root 셸) — init은 계정 없이도 홈 디스크의 묶음을 얹는다. 판정 11의 상자는
   상태 줄 글자판 "HEALTH"(`216 760 160 32`, `bg=1c1c1c ink=4336`) — 처음 고른 자리는 얼굴 테두리와 겹쳐 버렸다. Freedoom 판에 묶인 값이다.
4. 판정 12의 Ctrl은 `sendkey ctrl 300`(0.3초 쥠) — 기본 누름은 누름 · 뗌이 한 tic에 들어 엔진이 못 볼 수 있다. 탄약 칸은 `ppm_ink`가 50과
   49를 못 가를 수 있어 상자 sha1로 본다.
5. `Cmd+Q`에 둠이 스스로 끝났다(`wl> kill` 없음). `wl> key` 줄은 4(Ctrl 누름 · 뗌, Cmd(125) 누름 둘 — app workspace에서 누른 Cmd는
   클라이언트에 가고 포트가 버린다).
6. 체인 단독: wayland 339초 · display 451초 · devtools 1,103초 PASS, verify mismatch 0. 루트 게이트 35/35 첫 판 PASS(prebuild 348초 + lanes 1,552초,
   `out/gate-logs/20261119-155133`, verify 줄 12,858 중 이상 0, 잘린 줄 0). WY-M1 체인 61초. 묶음은 tars-doom `5179493`의 로컬 tarball.

남은 것: tars-doom의 push · `v0.1.0` release(사용자 확인 뒤), 그 뒤 manifest의 sha256을 GitHub 자산의 것으로. 숨은 동안 쥔 키를 떼는
것(`leave`)은 체인이 직접 보지 않는다 — 녹화 A에서 사람이 본다.
