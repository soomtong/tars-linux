# CE-M0 — init이 루트를 자기 자신의 bind mount로 덮는다

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-container-environment-design.md`(결정 1)
Status: 진행 중. 결정은 사용자 위임(2026-11-11).

## 착수 전에 확정한 것

1. 실측(design 확인 1): 정적 프로브(`unshare(CLONE_NEWNS)` → tmpfs → `pivot_root`)가 지금 게스트에서 `Invalid argument`, 같은 프로브가
   루트를 자기 bind로 덮은 뒤에는 성공. 프로브는 initrd 뒤에 cpio 하나를 덧붙여 넣었다 — 덧붙이는 archive는 512바이트 경계에서 시작해야
   한다(안 맞추면 `Initramfs unpacking failed: invalid magic at start of compressed archive`).
2. 자리: `init/src/main.zig`의 `mountEarly` — `power.install` · `disableCtrlAltDel` 뒤, `/proc` 앞. 이때 붙어 있는 것은 rootfs 하나라
   bind는 재귀(`MS_REC`)가 아니어도 된다.
3. 빈 디렉터리는 `/run/.root`(initrd의 `/run`은 ramfs의 진짜 디렉터리다). 옮긴 뒤에는 빈 디렉터리로 남는다.
4. Zig 0.17.1의 `std.os.linux`에 `mount` · `chdir` · `chroot` · `mkdir`이 있다 — raw syscall을 쓸 일이 없다.

## Task 1 — `rebindRoot`

`mkdir` → `mount("/", D, MS_BIND)` → `chdir(D)` → `mount(".", "/", MS_MOVE)` → `chroot(".")` → `chdir("/")`. 성공 줄
`tars-init: root is a bind mount of the initramfs (pivot_root works)`, 실패 줄 `tars-init: cannot rebind the root (STEP failed), containers
will not start`. 실패해도 부팅은 간다.

## Task 2 — 판정

체인 `tools`: 성공 줄이 있고, `/proc/self/mountinfo`에서 mount point가 `/`인 줄의 부모 id가 자기 id와 다르다(덮기 전에는 `1 1`).
`pivot_root` 자체는 CE-M2의 bwrap 판정이 밟는다(initrd에 `pivot_root`를 부를 도구가 없다).

## Task 3 — 게이트

루트 게이트 — 이 변경은 모든 체인의 모든 부팅이 지난다. 특히 볼 것: firmware를 읽는 체인(wifi · bluetooth · audio — 커널은 옛
rootfs에서 `/lib/firmware`를 찾는다), 설치(install · dualboot · devtools — `/proc/mounts`를 읽는 코드), 전원(power · sleep).

## 결과

(게이트 뒤 적는다.)
