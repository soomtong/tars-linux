---
name: project_lean_initrd
description: "initrd의 우리 바이너리 다섯(terminal · init · tars-install · tars-service · tars-config)을 사본만 --strip-debug한 Lean Initrd(LI-M0~M1, 2026-10-26). RAM −24.8MB · initrd −6.3MB, 게스트 trace는 함수 이름까지, 파일:줄은 호스트 zig-out 원본에 addr2line -i. TF-M4의 '심볼 판은 trace가 없다'는 0.17에서 재현 안 됨"
metadata:
  type: project
---

# Lean Initrd (LI)

HANDOFF 후보 "terminal 바이너리의 디버그 섹션"을 사용자가 골랐다(2026-10-26). 설계는
`docs/specs/2026-10-26-tars-lean-initrd-design.md`, plan은 `docs/plans/2026-10-26-tars-lean-initrd-li-m0.md`(실측) ·
`-li-m1.md`(구현).

## 무엇을 세웠나

`kernel/make_initrd.sh`가 `OWN_BINS` 다섯을 `$WORKDIR`에 놓은 뒤 `x86_64-linux-gnu-strip --strip-debug`한다. `zig-out/bin/`의 원본과
`build.zig`는 그대로다. initrd 99,264,851 → 92,957,200바이트, 게스트 RAM(풀린 rootfs) −24.8MB. 루트 게이트 22/22.
commit은 design `c86d561` · M0 `c700113` · M1 `74e4733`(스크립트) · `e534da3`(주석 · decisions · lessons) · 닫기.

## 결정과 그 이유

- 사본만 뗀다 — 원본이 호스트에서 주소를 푸는 재료다. 바이너리가 non-PIE라 게스트 trace의 주소를
  `x86_64-linux-gnu-addr2line -f -i -C -e terminal/zig-out/bin/terminal 0x…`에 그대로 넣는다(lessons "범용 명령").
  `-i`가 게스트 trace에 없던 inline 사슬까지 내므로 strip 판 + 원본 ⊇ 원본 판이다(LI-M0 실측 3).
- `--strip-debug`다(전부 strip이 아님). `.symtab`이 0.3MB이고 Zig 0.17이 DWARF 없이 그것으로 함수 이름을 찍는다
  (`???:?:?: 0x1190982 in main.App.dumpFrame`). 잃는 것은 게스트 로그의 파일:줄과 inline된 맨 안쪽 함수 이름이다.
- sysroot(Debian) 도구는 대상이 아니다 — ELF 91개 모두 이미 `.debug_info`가 없다.
- 이것으로 TF-M4(2026-08-12)의 "strip하면 고칠 여지가 없다"를 뒤집었다. 그 판단과 이유는 [[project_gate_chain_composition]]에
  남기고 LI 문단을 붙였다.

## 함정

- 컨테이너가 arm64라 그냥 `strip` · `readelf` · `addr2line`은 x86_64 ELF를 못 읽는다. `x86_64-linux-gnu-` 접두사를 쓴다.
- `addr2line`은 그 로그를 낸 빌드의 `zig-out`이어야 한다. 다시 빌드하면 주소가 바뀐다. 게이트 로그는 그 회차의 빌드라 맞지만
  공개 ISO의 패닉은 그 빌드의 원본을 남겨 두지 않으면 못 푼다(design 비목표 2 — 실기 패닉이 생기면 다시 본다).
- 호스트의 `/tmp`는 컨테이너에 안 보인다. 프로브 파일은 `-v /tmp/li-m0:/li`처럼 따로 마운트한다.
- 게이트 시간은 줄지 않았다(prebuild 402 + lanes 334초, 단발). prebuild는 cold build라 흔들리고, 체인 대부분은 QEMU `-initrd`로
  싣는다. 크기 효과는 RAM과 ISO · 설치 디스크 쪽이다.

## 관련

[[project_gate_chain_composition]] — 뒤집은 TF-M4의 strip 문단. [[project_gate_latency]] — GL-M3의 "strip은 안 한다".
[[project_zig_upgrade]] — 출발점(ZU design 실측 9).
