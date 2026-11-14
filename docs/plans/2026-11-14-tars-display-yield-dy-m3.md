# DY-M3 — GPU 데모 판

Date: 2026-11-14
Design: `docs/specs/2026-11-12-tars-display-yield-design.md` 결정 12
Status: 진행 중

## 착수 전에 확정한 것

사용자(2026-11-14): "0.2.2 작업의 핵심은 gpu 관련 기능이야. 이 데모를 위해 fakesteak 처럼 하나의 iso 파일을 구워줘. 이 빌드를 설치하면
fakesteak 처럼 fullscreen gpu 구동 화면이 동작해야해."

1. gpu 묶음은 독립 묶음이 아니다 — 굽기에서 base와 겹친 파일 108개가 지워지고(DY-M2 결과 1), `make_iso.sh`는 base 없이 싣지 않는다.
   그래서 ISO는 base · gpu 둘이다.
2. 설치(`tars-install`)는 매체의 `boot/layers/*.sqfs`를 p3의 `/.tars/layers`로 옮긴다 — 설치본도 같은 두 묶음을 얹는다.
3. display 체인의 부팅 3이 바로 base · gpu 둘이다 — 조각이 거기서도 뜬다. 체인이 그것을 판정으로 받는다(12a).

## Task 1 — 조각 (commit 하나)

1. `devlayer/files/gpu/etc/tars/rc.d/gpu.sh`(bash · zsh) · `devlayer/files/gpu/etc/fish/conf.d/90-gpu-demo.fish`. fakesteak 조각의 넷에
   더해 `/usr/share/tars/layers/*`가 `base` · `base.pkgs` · `gpu` · `gpu.pkgs`뿐일 때 `tars-fullscreen tars-gpu-demo 2>/tmp/gpu-demo.log`.
2. `display/check.sh` 부팅 3: 판정 (12) 뒤 (12a) — yield 1 · 화면이 움직인다 · Esc → reclaim 1 · `/tmp/gpu-demo.log`에 `video kmsdrm`.
   뒤 판정의 셈(yield · reclaim · inputs)을 하나씩 올린다.
3. `docs/help/desk.md`에 한 줄, design 결정 12와 milestone 줄.
4. 검사: shellcheck · `fish -n`(fish 4.0.2), `make quick`, `make dev-layers DEV_LAYERS="base gpu"`, `make check CHAIN=display`.

## Task 2 — ISO

commit 뒤(출처 기록이 dirty가 아니게) `make iso ISO_LAYERS="base gpu"`를 `tars-0.2.2-gpu-x86_64.iso`로. 버전 글자는 tag `v0.2.2` 뒤의
commit이라 꼬리가 붙는다. QEMU(virtio-gpu)로 부팅해 첫 패널에 데모가 뜨는지 screendump로 본다. 설치 뒤의 부팅은 실기(맥북 에어 2011)의 몫.

## 결과
