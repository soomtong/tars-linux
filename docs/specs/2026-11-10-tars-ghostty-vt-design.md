# TARS Ghostty VT 1.0 — Design

접두사: GV

Date: 2026-11-10
Status: 닫힘(2026-11-10, GV-M0 — 루트 게이트 33/33). plan은 `docs/plans/2026-11-10-tars-ghostty-vt-gv-m0.md`.

계기: 사용자(2026-11-10): "zig 0.17.1 빌드 대응, libghostty 1.0 대응."

관련 문서: ZU design(`2026-10-03-tars-zig-upgrade-design.md` — 0.16 → 0.17, ghostty를 SHA로 따라가는 규칙) ·
기억 `project_zig_upgrade`(올릴 때 고칠 자리: Dockerfile `ENV ZIG_VERSION` · `ARG ZIG_SHA256` · `checks.yml`의 `ZIG_SHA256`) ·
VS-M0(vendor tarball의 sha256 고정).

## 한 줄 요약

컨테이너의 Zig를 0.17.0에서 0.17.1로, `terminal`이 잡는 ghostty를 `3d07ef9`(0.17 전환 커밋)에서 태그 `vt-1.0.0`(`0fa3d57`,
libghostty-vt 1.0.0)으로 올린다. 우리 코드에서 고칠 곳은 `terminal/src/vt.zig:191` 한 줄이다.

## 확인 (2026-11-10, HEAD `e4baa09`)

호스트 macOS의 Zig 0.17.1(`/opt/homebrew/bin/zig`)로 `terminal` · `shared` 사본을 scratchpad에 두고 잰 것이다. 저장소는 건드리지 않았다.

1. Zig 0.17.1. 2026-11-02 릴리즈. ziglang.org `index.json`의 shasum은 x86_64-linux `3581863e…e9b17a`, aarch64-linux
   `a1546d56…ed7795`. 사본을 지금 ghostty(`3d07ef9`)로 0.17.1 빌드하면 빨강은 macOS에 없는 헤더 둘(`linux/input.h` · `pty.h`)뿐이다 —
   기억 `project_zig_upgrade` 마지막 절의 한계 그대로이고 0.17.0에서도 같다. 게스트 바이너리 `terminal`(x86_64-linux)은 나온다.
   `input/kk` · `pointer/replay`도 그대로 빌드된다.
2. `make quick`이 `zig-fmt`에서 빨갛다(`init/src/main.zig` · `reload.zig` · `reload_test.zig`). 0.17.1 탓이 아니다 — 0.17.0으로 도는
   CI(`checks`, `e4baa09`)도 같은 세 파일에서 빨갛다. CO-M1(`c3e52ed`)이 열 맞춤이 어긋난 배열 줄을 남겼다. 0.17.1 `zig fmt`의 출력이
   CI 로그가 가리킨 파일과 같다.
3. ghostty `vt-1.0.0` = `0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec`(2026-11-06, "libghostty-vt: prepare for 1.0.0 (#15126)").
   `3d07ef9` 뒤로 381커밋, `src/terminal` 100파일. `build.zig.zon`의 `minimum_zig_version`은 그대로 `0.17.0`이고 `requireZig`는
   major · minor만 보므로 0.17.1이 통과한다. `pkg/translate-c`가 잡는 `translate_c` 패키지(URL · hash)는 우리
   `terminal/build.zig.zon`의 것과 같다 — zon은 안 바뀐다. GitHub archive tarball의 sha256은 `2f38f10e…22b95ea`.
4. vt-1.0.0으로 바꾼 사본에서 컴파일을 깨는 것은 하나다: `vt.zig:191`의 `@fieldParentPtr("term", h.terminal)`이
   "@fieldParentPtr increases pointer alignment"(부모 `*Screen` 정렬 2^3, 필드 `term`이 그만큼으로 묶는다). `Terminal`의 정렬이
   커졌기 때문으로 보인다 — 같은 기간에 `Style`이 `packed u128`이 됐다(`41557e2`). `@alignCast(...)`로 감싸면 남는 빨강은 1의 헤더
   둘뿐이다. ghostty 자신도 같은 꼴을 쓴다(`stream_terminal.zig:2368`의 `@alignCast(@fieldParentPtr("writer", w))`).
5. 호스트에서 도는 terminal 검사 17개를 두 사본(지금 ghostty · vt-1.0.0)에서 돌린 결과가 같다 — 15개 PASS, `logline_test` ABRT ·
   `pty_test` 실행 불가는 두 사본 모두(기억의 호스트 한계). 다른 숫자 하나: `dirty_test`(seed `5441525344524d32`)의 "재사용 행 합"이
   2760 → 2775. 판정(dirty 행만 다시 그린 결과 = 전체 다시 그린 결과)은 둘 다 통과다. ghostty가 dirty를 덜 표시하게 된 것으로 읽는다.

## 결정

### 결정 1 — 한 milestone, 세 commit

깨지는 자리가 4의 한 줄뿐이라 Zig와 ghostty를 milestone으로 나누지 않는다. 대신 commit은 나눈다 — fmt(2) · Zig 0.17.1 · ghostty
vt-1.0.0. fmt를 고침과 섞지 않는 것은 ZU의 규칙이고, Zig와 ghostty를 나누면 게이트가 빨개졌을 때 어느 쪽인지 `git revert` 하나로 가른다.

### 결정 2 — ghostty는 태그가 가리키는 SHA로 고정한다

ZU는 태그를 기다리지 않고 전환 커밋 SHA로 고정했다. 이번에는 태그가 이미 있다. `vendor_libghostty_vt.sh`는 SHA로 받으므로 태그 이름이
아니라 `0fa3d57…`을 적고, 주석에 태그 이름을 둔다(태그는 옮겨질 수 있고 SHA는 안 옮겨진다).

### 결정 3 — `@alignCast`로 고친다

`Screen`은 `alloc.create(Screen)`으로 힙에 놓이므로 `Screen`의 정렬은 보장된다 — `@alignCast`는 그 사실을 적는 것이고 safe 빌드
(게스트는 `ReleaseSafe`)에서는 실제로 검사된다. 필드 순서나 `align(…)`를 바꾸는 길은 ghostty 내부의 정렬을 우리가 따라가야 해서 고르지 않는다.

## 비목표

1. 주석 속 ghostty 파일:줄 참조(`vt.zig`에만 서른 곳 남짓, 예: `Terminal.zig:374-377`)를 1.0 기준으로 다시 맞추기. 그 참조는 적을 때의 SHA
   기준이었고 ZU 때도 안 고쳤다.
2. libghostty-vt 1.0의 새 API(C ABI 등)를 쓰는 일. 우리는 Zig 모듈 `ghostty-vt`만 쓴다.
3. 0.17.1의 새 기능을 쓰는 일. 이번 일은 버전 줄과 깨진 자리만이다.
