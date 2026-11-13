# DY-M1 — 입력 양보 · 탈출 조합 · 기다리는 terminal

Date: 2026-11-13
Design: `docs/specs/2026-11-12-tars-display-yield-design.md`
Status: 끝(2026-11-13). 결과는 맨 아래.

## 착수 전에 확정한 것

design 결정 8a(키보드는 양보 동안만 손님의 uid에게 — `input` 그룹 없음) · 8b(탈출 조합 `Ctrl+Cmd+Backspace`) · 11(master가 아닌 채 뜬
terminal은 기다린다). 사용자 2026-11-13 — 추천안 둘에 동의. 끝났을 때 되는 것:

```
$ tars-fullscreen tars-kms-fill CC6666 0 --keys   ← 화면이 한 색. 친 키는 셸이 아니라 앱에게 간다. Esc를 치면 앱이 끝나고 콘솔이 돌아온다
$ tars-fullscreen <멈춘 앱>                        ← Ctrl+Cmd+Backspace(PC: Ctrl+Alt+Backspace)로 SIGTERM, 2초 뒤 SIGKILL, 콘솔이 돌아온다
$ stat -c %U /dev/input/event0                     ← 평소에는 root(600) — 사용자 프로세스는 키를 못 읽는다
```

DY-M0에서 확인한 것(기억 `project_display_yield` 1~11)은 다시 재지 않는다. 특히 확인 1 — master가 아닌 fd도 dumb buffer · ADDFB는 되고
SETCRTC · DIRTYFB만 `EACCES`다(프로브 T1 · T2). 그래서 master 없이 뜬 terminal은 `drm.open`까지는 서고, DIRTYFB를 묻는 자리가 틀린 답을 얻는다.

## Task 1 — `input.zig`: 양보 중의 좁은 읽기 (commit 하나)

1. `pub fn watchEscape(self: *State, fd: c_int, ctx: Context) struct { escape: bool, gone: bool }` — `readKeys`와 같이 이벤트를 다 읽되
   수정키(shift · ctrl · alt · meta, `swap_alt_meta` 보정 뒤)만 `mods[dev]`에 적고, `KEY_BACKSPACE`의 누름(value 1)이 `ctrled() and metaed()`이면
   `escape`. 나머지는 버린다 — 바이트 · 한/영 tap · 받아쓰기 더블 탭 · 밝기 · copy를 건드리지 않는다(게임 중의 Ctrl tap이 한/영을 바꾸면 안 된다).
   tap의 진행 상태(`taps[dev]`)와 `dictate_tap`은 들어갈 때 버린다(양보 전에 반쯤 누른 것이 복귀 뒤에 판정되지 않게).
2. `SYN_DROPPED`는 `readKeys`와 같이 다룬다. `BTN_MISC` 이상은 거른다.
3. `input_test`: Apple(`meta_l`)과 PC(`alt_l` → Cmd) 둘에서 조합이 잡힌다 · Backspace만 · Ctrl+Backspace · Cmd+Backspace는 아니다 · 자동 반복(2)과
   뗌(0)은 아니다 · 양보 중에 뗀 수정키가 복귀 뒤 눌린 채로 남지 않는다 · `lctrl` tap이 한/영을 안 바꾼다.

## Task 2 — terminal: 양보 중의 키 · 포인터와 탈출 (commit 하나: 결정 8 · 8b)

1. `readKeyboards`: `yield_state`가 `yielded`면 `readKeyboard` 대신 `watchEscape`. 포인터 fd는 읽어서 버린다(읽지 않으면 POLLIN이 남아 poll이
   헛돈다) — 화살표 자리도 안 옮긴다. `waiting`(손님이 떠난 뒤)도 같다. 결정 11의 "손님 없이 기다림"은 키를 셸에 넣는다(Task 4).
2. `yield.Machine`: `escape(ops, now_ms)` — `yielded`일 때 손님에게 SIGTERM, 기한 `now + 2000`을 적는다. `timeout()`은 기한까지의 밀리초도 돌려준다.
   `retry`가 기한을 넘겼으면 SIGKILL(한 번). 신호의 대상: 손님 pid의 프로세스 그룹이 그 pid 자신이면(`getpgid(pid) == pid` — 셸의 job은 그렇다)
   그룹 전체, 아니면 pid 하나 — terminal이나 셸의 그룹을 죽이지 않기 위해서다. ops에 `kill(pid, sig)` · `pgid(pid)`를 더한다.
3. 로그: `terminal: display> escape pid N (SIGTERM)` · `terminal: display> escape pid N (SIGKILL)`. 복귀는 M0의 `reclaim` 그대로.
4. `yield_test`: 조합 → SIGTERM(그룹), 2초 전 HUP → SIGKILL 없음, 기한 지남 → SIGKILL 한 번, 그룹 리더가 아니면 pid 하나, `ours`에서 조합은 없음.

## Task 3 — terminal: 키보드의 문 (commit 하나: 결정 8a)

1. `yield.Guest`에 `uid`(같은 `SO_PEERCRED`).
2. `yield.zig`의 socket 절에 `handInputs(uid)` · `takeInputs()`: `/dev/input`의 `event*`를 훑어 `fchownat(uid, 0)` / `(0, 0)`, 모드는 600 그대로.
   `/dev/snd`의 `openNodes`와 같은 모양이고 줄 하나: `terminal: display> inputs N to uid U (M refused)` · `terminal: display> inputs N back to root`.
3. 순서: `yield` → `dropMaster` → `handInputs` → `ok`. 되찾을 때 `takeInputs` → `setMaster`(`waiting`으로 남아도 키는 먼저 되돌린다). 실패한
   노드가 있어도 양보는 한다 — 키 없는 앱(영상)은 M0처럼 돈다.
4. terminal이 뜰 때 `takeInputs()` 한 번 — 양보 중에 terminal이 죽었으면 노드가 사용자 것으로 남아 있다(결정 11의 길).
5. 손님이 root(uid 0)이면 바꿀 것이 없다(줄은 찍는다).
6. 양보 중에 꽂은 키보드는 root 600으로 남는다(init에 uevent가 없다) — 결과에 적고 막지 않는다.

## Task 4 — terminal: master 없이 뜨기 (commit 하나: 결정 11)

1. `drm.open`: DIRTYFB를 묻는 답이 `EACCES`면 `dirty`를 정하지 않는다(`?bool` 또는 `dirty_known: bool`) — `setMaster`가 성공한 뒤 다시 묻는다.
   지금은 `EACCES`가 "DIRTYFB 없음 → 프레임마다 SETCRTC"로 굳는다(확인 1의 T1에서 읽힌다).
2. `openScreen`: `modeset`이 `EACCES`면 에러로 끝내지 않고 `yield_state.state = .waiting`(손님 없음), 로그 `terminal: display> waiting for master`
   (M0의 줄 그대로). 다른 에러는 지금처럼 끝난다.
3. 손님 없는 `waiting`은 키를 셸에 넣는다(Task 2의 "버린다"와 갈린다 — 손님이 없으니 그 키를 볼 앱이 우리 쪽에 없다). 탈출 조합도 없다(누구에게
   신호를 보낼지 모른다). 화면은 여전히 그리지 않는다.
4. 되찾으면 `modeset` · DIRTYFB 다시 묻기 · 통째 그리기. M0의 `reclaim`.

## Task 5 — `tars-kms-fill --keys` (commit 하나)

1. 세 번째 인자 `--keys`: setcrtc 뒤 `/dev/input/event*`를 모두 `O_RDONLY | O_NONBLOCK`으로 열어 본다 — 단계 줄 `tars-kms-fill: input eventN ok|errno N`.
   연 것 가운데 `EV_KEY`를 내는 것을 poll하고 `KEY_ESC` 누름이면 `tars-kms-fill: esc` 뒤 0으로 끝난다. 초가 0이 아니면 그 시한도 같이 본다.
2. 체인이 "앱이 키를 받는다"를 이것으로 본다. 실기에서도 같다 — 사람이 Esc로 끝낸다.
3. `docs/help/desk.md`: 탈출 조합 한 줄과 `--keys`.

## Task 6 — 체인 `display` (commit 하나)

M0의 판정 중 "양보 중에 셸에 친다"를 쓰던 것(5 · 6의 `tars-fullscreen true` · `kill -9 $last_pid`)은 키가 셸로 안 가므로 다시 짠다 — 둘째 요청은
양보 전에 한 줄로 친다(`tars-fullscreen tars-kms-fill 66cc66 4 & sleep 2; tars-fullscreen true; echo rc=$status`), 죽이는 것은 탈출 조합이 한다.
`type_line`에 `'`(apostrophe) · `"`(shift-apostrophe).

부팅 1(사용자 dyuser, keyboard=apple — QEMU 키보드는 PC라 Cmd가 `meta_l`이 되게):
1. M0의 문 · 색 · 복귀 · `back-42` · busy(위처럼)는 그대로.
2. 키의 문: 양보 전 `stat -c %U /dev/input/event0`이 root, `--keys` 앱의 단계 줄에 `input event… ok`(키보드), 복귀 뒤 다시 root.
3. 키가 앱에게 간다: `tars-fullscreen tars-kms-fill cc6666 0 --keys` → 양보 → `x y z`를 치고 Esc → 앱 `esc`로 끝 → 복귀 → 셸 줄에 `xyz`가 없다
   (`echo k1-…`로 다음 줄을 확인).
4. 탈출: `sh -c 'trap "" TERM; exec tars-fullscreen tars-kms-fill 66cc66 0'` → 양보 → `ctrl-meta_l-backspace` → `escape … (SIGTERM)` →
   2초 뒤 `escape … (SIGKILL)` → `reclaim`. SIGTERM이 듣는 앱(trap 없이)은 `SIGTERM` 줄 뒤 SIGKILL 없이 `reclaim`.
5. 살아 있다: `tars-init: restarting` 없음.

부팅 2(root 셸 — 설정 디스크만, 홈 디스크 없음): 결정 11.
6. 한 줄로: `sh -c 'echo $$ > /tmp/dy.pid; trap "" HUP; exec tars-fullscreen tars-kms-fill 66cc66 0' & sleep 2; tars-config reload terminal` →
   `tars-init: restarting terminal on request` → 새 terminal의 `display> waiting for master`(죽지 않는다 — `given_up` 없음) → 화면은 66cc66 그대로 →
   보이지 않는 셸에 `kill -9 (cat /tmp/dy.pid)` → `reclaim` → 프롬프트.
7. `/dev/input/event*`가 root다(새 terminal이 뜰 때 되돌렸다 — 부팅 2는 root 손님이라 바뀐 적이 없어 이 판정은 줄 `inputs N back to root`로 본다).

## Task 7 — 조사: SDL3과 `EVIOCGRAB` (코드 없음, 결과 절에)

SDL3의 evdev 경로(`src/core/linux/SDL_evdev.c`)가 키보드를 독점하는지, 끄는 힌트가 있는지. 독점하면 탈출 조합이 안 닿는다 — DY-M2 plan이
그 힌트를 데모의 기본값으로 둔다. 출처(파일 · 판)를 적는다.

## 결과

commit: `c712a42`(Task 1) · `72b854f`(Task 2 · 3 · 4 — 같은 파일의 얽힌 자리라 하나로) · `7ca3cbb`(Task 5) · `31b877b`(Task 6). 2026-11-13 로컬 세션.
Task 2부터는 M0 체인의 판정 5 · 6이 깨지므로(양보 중 키가 셸로 안 간다) M0 때처럼 체인이 PASS한 뒤에 commit했다.

1. Task 1: `watchEscape`는 매 배치 `taps`와 `dictate_tap`을 버린다(들어갈 때만이 아니라 — 양보 중에는 둘이 쓰일 일이 없다). 수정키
   여덟을 따라가 복귀 뒤 눌린 채로 남지 않는다(`input_test` 두 절).
2. Task 2: 포인터는 읽되(`readPointers`) `wirePointer`만 건너뛴다 — 좌표는 따라가고 화살표는 복귀 뒤 그 자리에 뜬다. 판정은
   `ownsScreen`이 아니라 `holdsInput`(Task 4의 손님 없는 기다림이 키를 셸에 넣으므로). `yield_test`의 기한 셈을 처음에 틀리게 적었다
   (1000 + 2000을 500) — 시험 쪽 잘못.
3. Task 3: `/dev/input`의 `event*`(체인의 QEMU에서 셋 — 무엇인지는 세지 않았다)를 `ok` 앞에 손님 uid로, 되찾기 앞에 root로.
   terminal이 뜰 때도 한 번 되돌린다(`inputs 3 back to root`).
4. Task 4: `drm.zig`의 ioctl이 `EACCES`면 `error.NotMaster`. `drm.open`의 DIRTYFB 물음이 그 답이면 `dirty_known = false`로 두고
   (`kms: present by ? (not master yet)`) `YieldOps.modeset`이 되찾은 뒤 다시 묻는다. 손님 없는 기다림은 `Machine.blind`.
5. Task 6: 판정 열, 부팅 둘. `reload terminal`은 init에 대기 중인 설정이 없으면 아무것도 안 한다(`nothing pending`) — 첫 판이 판정 10에서
   그것으로 멈췄고, `cursor_shape=bar`를 `set` · `reload`한 뒤 치게 고쳤다(fullscreen 체인 판정 8과 같은 길). 둘째 판 PASS(3분 58초).
   부팅 2의 줄: `yield pid 233` → `reload terminal` → `kms: present by ? (not master yet)` → `display> waiting for master` → 새 셸 →
   `inputs 3 back to root` → (보이지 않는 셸에 `kill -9`) → `kms: present by dirtyfb` → `reclaim`, `giving up` 없음. 고치기 전 코드로 빨강
   판은 돌리지 않았다.
6. Task 7(조사, 출처: libsdl-org/SDL `main`의 `src/core/linux/SDL_evdev.c` · `SDL_evdev_kbd.c`, 2026-11-13에 읽음 — commit은 못 고정했다):
   - `EVIOCGRAB`가 없다 — SDL3의 evdev 키보드는 장치를 독점하지 않는다. 탈출 조합이 SDL 앱 앞에서도 terminal에 닿는다.
   - `SDL_EVDEV_kbd_init`이 `/dev/tty`를 열어 VT(`KDGKBTYPE`가 KB_101 · KB_84)일 때만 `KDSKBMODE K_OFF`로 콘솔 키를 끈다
     (`SDL_HINT_MUTE_CONSOLE_KEYBOARD`, 기본 켬). TARS 앱의 `/dev/tty`는 pty라 지나간다 — 해가 없다.
   - libudev 없이는 `/dev/input`을 훑지 않는다(`SDL_EVDEV_Init`의 `#else` 갈래 — `// TODO: Scan the devices manually, like a caveman`).
     `SDL_EVDEV_DEVICES` 힌트(`kbd:/dev/input/eventN,mouse:…`)만 읽는다. TARS에는 udevd가 없으니 DY-M2에서 키를 받으려면 이 힌트가
     있어야 한다 — `tars-fullscreen`이 exec 앞에 채우는 길이 후보다(M2 plan이 정한다).
   - 못 본 것: KMSDRM 백엔드(`SDL_kmsdrmvideo.c`)가 `SDL_EVDEV_Init`을 부르는지, `SDL_udev.c`.
7. 루트 게이트: 34/34 첫 판 PASS(34분 29초 — prebuild 348초 + lanes 1,578초, 회차 34개 모두 `cut log lines A=0 B=0 C=0`, `out/gate-logs/20261113-120251`).
   DY 98초(부팅 둘), devtools 841초. 체인 이름은 게이트 뒤에 `DY-M0` → `DY-M1`로 바꿨다(닫기 commit).
8. 안 본 것: i915 실기(M0 Task 5와 함께). 양보 중에 꽂은 키보드는 root 600으로 남는다(init에 uevent가 없다).
