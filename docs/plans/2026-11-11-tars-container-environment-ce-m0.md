# CE-M0 — init이 루트를 자기 자신의 bind mount로 덮는다

Date: 2026-11-11
Design: `docs/specs/2026-11-11-tars-container-environment-design.md`(결정 1)
Status: 끝났다(2026-11-12). 결정은 사용자 위임(2026-11-11).

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

구현 `c410002`(CE-M1과 한 커밋). plan 그대로다.

- 게스트: `tars-init: root is a bind mount of the initramfs (pivot_root works)`, `/proc/self/mountinfo`의 첫 줄이 `1 1 0:2 / /`에서
  `18 1 0:2 / / rw - rootfs rootfs rw`로. 같은 프로브의 `pivot_root`가 `Invalid argument` → `OK`.
- 실제로 `pivot_root`를 부르는 것: devtools 체인의 사용자 `bwrap --unshare-all`과 runc(컨테이너 둘).
- 다른 체인: firmware를 읽는 wifi · bluetooth · audio, 설치(install · dualboot · devtools · home · mise · pm), 전원(power · sleep) 모두 초록 —
  루트가 한 겹 얹힌 것을 본 체인이 없었다. tools 검사 27이 줄과 mountinfo를 판정한다.

루트 게이트(2026-11-12, `0e1b888`의 코드): 32/33 — 34분 51초(prebuild 344초 + lanes 1,614초), 잘린 줄 0, `out/gate-logs/20261111-162704`. 빨간 하나는 pm(PM-M0)의 화면 판정이 옛 프롬프트 `tars@(none) ~>`를 기다린 것(LT-M0이 놓친 자리)이고, 그 한 줄을 고친 뒤 pm 단독이 초록이었다. 커널 · init · initrd는 그 사이 바뀌지 않아 게이트를 통째로 다시 돌리지 않았다.
