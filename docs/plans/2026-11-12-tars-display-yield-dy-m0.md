# DY-M0 — 양보와 복귀

Date: 2026-11-12
Design: `docs/specs/2026-11-12-tars-display-yield-design.md`
Status: 끝(2026-11-13). plan은 클라우드 세션에서 썼고(design 위험 6) 구현 · 게이트는 로컬 세션이 했다. 결과는 맨 아래.

## 착수 전에 확정한 것

design의 확인 1~16과 결정 1 · 3~7 · 9. 결정 8(입력)과 10(SDL3)은 이 milestone이 아니다. 끝났을 때 되는 것:

```
$ tars-fullscreen tars-kms-fill CC6666 5      ← 화면이 5초 동안 한 색, 그 뒤 프롬프트가 돌아온다
```

양보 중에 키보드는 여전히 terminal의 것이다(친 글자가 뒤의 셸에 들어간다) — 입력 양보는 DY-M1이다. 시험 프로그램은 키를 읽지 않는다.

## Task 1 — `video` 그룹과 `/dev/dri` (commit 하나: 결정 7)

1. `shared/screen_args.zig`: `AUDIO_GID` 옆에 `pub const VIDEO_GID: u32 = 44;`와 한 줄 주석(Debian의 번호, DY design 결정 7).
2. `kernel/make_initrd.sh`의 `/etc/group` heredoc(650-657): `audio:x:29:` 뒤에 `video:x:44:`.
3. `init/src/account.zig:147`: `MEMBER_GROUPS`에 `"video"`. 위 주석의 짝 목록에 `VIDEO_GID`. `account_test`의 기대 글자도.
4. `terminal/src/pty.zig:37`: `groups: [3]c.gid_t`. `terminal/src/main.zig:1676`: `.groups = .{ SUDO_GID, AUDIO_GID, VIDEO_GID }`.
5. `init/src/audio.zig`의 `openToAudio`를 디렉터리 · gid · 로그 이름을 받는 함수 하나(`openNodes(dir, gid, label)`)로 일반화하고 둘이 부른다 —
   `/dev/snd`는 지금과 같은 줄을 찍고(`audio:` 체인이 그 줄을 본다 — 글자가 한 자도 안 바뀌는지 `git diff`로 본다), `/dev/dri`는
   `tars-init: display: N nodes in /dev/dri are root:video 660 (M refused)`. 부르는 때: terminal을 띄우기 전(card0은 그 전에 있다 —
   `tars-init: /dev/dri/card0 exists` 줄이 찍히는 자리 뒤). simpledrm → i915처럼 카드가 뒤에 바뀌는 실기는 Task 5의 실기 확인에서 본다.
6. 검사: init `zig build test`, `make quick`. 부팅해 `id`에 `44(video)`, `ls -l /dev/dri`에 `root video` · `crw-rw----`.

## Task 2 — terminal의 양보 (commit 하나: 결정 3 · 5 · 6 · 9)

1. `shared/display_proto.zig`(새 파일, 순수): `PATH = "/run/tars/display.sock"`, 메시지 글자 `yield` · `ok` · `busy` · `refused`,
   `parseRequest` · `parseReply`. 호스트 시험 `shared/display_proto_test.zig`(`make quick`의 `zig run` 줄에 더한다).
2. `terminal/src/drm.zig`: `pub fn dropMaster(self: Framebuffer) !void`(`DRM_IOCTL_DROP_MASTER` = `_IO('d', 0x1f)`) ·
   `pub fn setMaster(self: Framebuffer) !void`(`_IO('d', 0x1e)`). 인자 없는 ioctl이라 `drmIowr`가 아닌 번호 상수 둘. `setMaster`는
   `EBUSY`를 다른 실패와 갈라 돌려준다(`error.MasterBusy`).
3. `terminal/src/yield.zig`(새 파일): 상태 `{ listen_fd, guest_fd, guest_pid, state: enum { ours, yielded, waiting } }`.
   - `open()`: `/run/tars`가 없으면 만들고(init이 이미 만든다 — 있으면 지나간다), 옛 socket 파일을 지우고, `SOCK_SEQPACKET | NONBLOCK | CLOEXEC`,
     bind, `chown root:video`, `chmod 0660`, `listen(1)`. 실패하면 한 줄 찍고 listen_fd = -1(terminal은 그대로 돈다 — 양보만 없다).
   - `accept`: 손님이 이미 있으면 받아서 `busy`를 보내고 닫는다. 없으면 `SO_PEERCRED`로 pid를 적고 `yield`를 기다린다.
   - `yield` → `fb.dropMaster()` → `ok` → `yielded`. 실패 → `refused` 보내고 닫는다.
   - 손님 fd의 HUP/EOF → `fb.setMaster()`. 성공 → `fb.modeset()` → `ours`, `App`에 통째 그리기를 알린다. `MasterBusy` → `waiting`.
   - `waiting`: poll 시한에 1000ms를 끼워 넣고(`pacing.soonest`) tick마다 `setMaster`를 다시 해 본다.
4. `terminal/src/main.zig`:
   - `fds` 크기 `+ 2`(3602), `arm()` 끝에 listen · guest 두 칸(받아쓰기 쌍의 모양), `tick()`에서 `readDictation()` 뒤에 `readYield()`.
   - present 막기: `presentFrame`의 호출(4897)과 `decideFrame`의 present(4746) 앞에 `if (self.yield.state != .ours)` — 그리지 않고
     `needs_redraw`를 남긴다. 그리는 일(픽셀을 fb에 쓰기)까지 건너뛰어도 되는지는 구현 때 `render`를 읽고 정한다: 건너뛰면 복귀의 통째
     그리기가 다 메우고, 안 건너뛰면 CPU만 쓴다. 결과에 적는다.
   - 복귀: `self.last_tree = null; self.needs_redraw = true;`(확인 9).
   - 로그 넷(결정 9).
5. 검사: terminal `zig build test`(`yield.zig`의 상태 전이는 fd를 주입받는 순수 함수로 떼어 호스트에서 시험한다 — 손님 둘째의 `busy`,
   `yield` 전의 HUP, `MasterBusy` 뒤의 재시도).

## Task 3 — `tars-fullscreen` · `tars-kms-fill` (commit 하나: 결정 4, design Milestone)

1. `init/src/fullscreen_cli.zig` → `tars-fullscreen`(`init/build.zig`에 `tars-service`와 같은 모양으로): 인자가 없으면 쓰는 법.
   connect → `yield` → 답을 읽는다 → `ok`면 `fcntl`로 `CLOEXEC`가 꺼져 있음을 확인하고 `execvp`. `busy` · `refused` · 연결 실패는
   `tars-fullscreen: <까닭>`을 stderr에, 종료값 1. `execvp` 실패는 126/127(셸의 관례) — 이때 프로세스가 끝나며 fd가 닫혀 terminal이 되찾는다.
2. `init/src/kms_fill.zig` → `tars-kms-fill <RRGGBB> <초>`: `card0`을 열고 첫 연결된 connector · 첫 mode · dumb buffer · ADDFB · 한 색으로
   채우기 · SETCRTC, `<초>` 동안 잠들고 끝난다(0이면 신호가 올 때까지). 단계마다 `tars-kms-fill: <단계> ok|errno N`. `drm.zig`를 끌어오지
   않고 필요한 구조체 넷만 직접 둔다(프로브 `display/probe/kms-handover.c`의 `find` · `mkfb` · `setcrtc`가 그 모양이다 —
   GETCONNECTOR는 버퍼 없이 한 번 먼저 불러야 mode가 채워진다).
3. `kernel/make_initrd.sh`: 둘을 `usr/bin/`에(163-173의 모양), `OWN_BINS`(194)에 더한다.
4. `docs/help/`: `tars-fullscreen` 한 줄(어느 파일에 둘지는 구현 때 `tars-help`의 목록을 보고).

## Task 4 — 체인 `display` (commit 하나)

`display/check.sh`. `fullscreen/check.sh`의 `boot` · `wait_for_log` · `screendump` · PPM 읽기를 가져온다(같은 것이 셋째가 되면
`gate_lib.sh`로 올린다 — 지금 몇 벌인지 세어 보고 정한다). monitor 45507. 회차당 부팅 1회.

1. 양보: `tars-fullscreen tars-kms-fill CC6666 6` → `terminal: display> yield pid` 줄 → `screendump`의 가운데 픽셀과 네 귀퉁이가 `CC6666`.
2. 복귀: `terminal: display> reclaim` 줄 → `screendump`에 `CC6666`이 없고 프롬프트의 잉크가 있다. `wait_for_screen`으로 프롬프트.
3. 양보 중의 출력이 남는다: `tars-fullscreen tars-kms-fill 6666CC 3; echo back-$((40+2))` → 복귀 뒤 `back-42`.
4. 죽음: `tars-fullscreen tars-kms-fill 66CC66 0 & sleep 3; kill -9 $!` → `reclaim` 줄과 프롬프트.
5. 둘째 손님: 4의 `sleep` 사이에 `tars-fullscreen true; echo rc=$?` → `terminal: display> busy pid` 줄, 복귀 뒤 화면에 `rc=1`.
6. 살아 있다: 1~5 내내 `tars-init: restarting` 줄이 없다(terminal이 죽지 않았다 — 결정 1의 까닭).
7. 문: `id`에 `44(video)`, `tars-init: display: 1 nodes` 줄(virtio-gpu는 card0 + renderD128이면 2 — 처음 돌려 본 값으로 적는다).

루트 `check.sh`: `CHAINS`에 `"DY-M0:./display/check.sh"`와 위 설명 문단. `HANDOFF.md` · `carryover.md`는 닫을 때.

## Task 5 — 실기 확인 (사용자, 맥북 에어 2011)

`tars-fullscreen tars-kms-fill CC6666 5`. 볼 것: 색이 뜨는가(i915에서 uid 1000의 master), 5초 뒤 콘솔이 깨끗이 돌아오는가(design 위험 1),
`tars-kms-fill`의 단계 줄(실기에는 시리얼이 없으니 `2>/tmp/fill.log`로 받는다). 안 돌아오면 `ssh`로 `terminal: display>` 줄을 본다.

## 결과

commit: `e0d5c0c`(Task 1) · `79b8611`(Task 2) · `d06d91c`(Task 3) · `7f35d6f`(Task 4). 구현은 로컬 세션(2026-11-13)이다.
Task 3과 4는 사용자 지시로 체인이 PASS한 뒤에 함께 commit했다 — commit에는 부팅에서 확인된 것만 담았다. plan과 다른 자리는 넷이다.

1. Task 1: `openNodes`를 `audio.zig`가 아닌 새 파일 `init/src/devnode.zig`에 뒀다(display가 audio 모듈을 부르는 모양을 피했다).
   `/dev/snd`의 두 줄은 글자가 같다. `account.RESERVED`에 `video`를 더했다(같은 이름의 사용자가 그룹과 부딪친다). `login_test`가
   HP-M2 때의 group을 손으로 적고 있어 첫 판에서 빨갰다 — 바탕 group에 video 줄을 더했다. `home` 체인이 `video:x:44:hpuser`도 본다.
2. Task 2: plan에 없던 `drm.open`의 `O_CLOEXEC`. terminal이 card0을 CLOEXEC 없이 열고 `forkpty`의 자식은 fd를 닫지 않아, 화면 셸(uid 1000)과
   그 자손이 master인 drm_file의 fd를 물려받고 있었다 — 양보 없이도 SETCRTC가 됐다. 빨강 판(CLOEXEC를 뺀 display 체인)이 판정 1에서
   `d2-1`로 멈춰 수정 전에 정말 샜음을 보였다.
   "그리는 일까지 건너뛰어도 되는가"의 답: 건너뛴다. 양보 중에는 `tick`이 `decideFrame` · `render`를 통째로 건너뛰어 present 두 자리를 함께
   막는다. 그때 `output_pending`을 `needs_redraw`로 옮긴다 — 남겨 두면 `pacing.wait`가 0을 돌려 poll이 헛돈다. 체인 로그에서 yield 줄과
   reclaim 줄이 바로 붙어 있다(양보 중 `screen>` 덤프 0줄). 로그는 결정 9의 넷에 `listening on …` · `refused pid N (까닭)` ·
   `modeset after reclaim failed`를 더했다. 상태 규칙은 `yield.Machine`이 `ops`(anytype)를 받는 모양이라 `yield_test` 여섯 절이 가짜로 본다.
3. Task 3: 손님 쪽 경합. terminal은 둘째 손님을 받자마자 `busy`를 보내고 닫는데, 그 사이 `tars-fullscreen`의 `send`가 EPIPE로 실패해
   이미 와 있던 답을 안 읽고 "연결이 닫혔다"고 찍었다(종료값 1은 맞았다). display 체인 판정 5가 문장을 보다가 잡았다 — send가 실패해도
   답을 읽는다. 도움말은 `docs/help/desk.md`의 화면 절. Zig 0.17에 `std.fmt.bufPrintZ`가 없다(`bufPrintSentinel`).
4. Task 4: 노드 수는 2다 — virtio-gpu는 `card0` + `renderD128`. 기본 VGA(bochs-drm, `-vga` 지정 없는 체인 · home)는 `card0` 하나라 1이다.
   셸은 사용자 dyuser다(설정 디스크의 `user=` + 라벨 `tars-home`의 ext4 디스크 — `pickUser`가 둘 다 본다). 판정 순서는 문(plan의 7)을
   맨 앞에 두었다. `screendump` · `ppm_ink`는 hidpi · fullscreen에 같은 두 벌이 있어 `gate_lib.sh`로 올렸다(pointer의 `screendump`는 다른
   판이라 그대로). 두 체인을 다시 돌려 PASS. 체인은 글자를 키로 바꾸는 `type_line`을 갖는다 — 첫 두 판이 그것이 모르는 글자(대문자 · `_`)로
   멈췄다(체인의 잘못).
5. display 체인: 부팅 1회, 3분 안팎. 판정 일곱 — 문 · cc6666(가운데와 네 귀퉁이) · 복귀(양보 중 프로그램의 단계 줄 여덟이 화면에) ·
   `back-42` · busy와 `rc=1` · SIGKILL 뒤 복귀 · 재시작 0과 yield 3 · reclaim 3. 확인 3(uid 1000이 연 것만으로 master)이 TARS 커널 6.18의
   virtio-gpu에서도 같았다(`setcrtc ok`).
6. 루트 게이트: 34/34 첫 판 PASS(34분 58초 — prebuild 356초 + lanes 1,597초, 회차 34개 모두 `cut log lines A=0 B=0 C=0`, `out/gate-logs/20261113-103302`).
   DY-M0 45초, devtools 849초.
7. 안 본 것: i915 실기(Task 5, 사용자). 양보 중 `reload terminal`(design 위험 2 — DY-M1). 양보 중 키보드는 여전히 terminal의 것이다(체인은
   그것을 이용해 양보 중에 `kill -9`를 친다).
