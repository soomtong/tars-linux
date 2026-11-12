# DY-M0 — 양보와 복귀

Date: 2026-11-12
Design: `docs/specs/2026-11-12-tars-display-yield-design.md`
Status: plan만 있다(구현 전). 이 plan은 클라우드 세션에서 썼다 — devcontainer와 게이트가 없어 구현 · 게이트는 사용자의 기계에서 도는
세션이 잇는다(design 위험 6).

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

(구현 뒤에 적는다.)
