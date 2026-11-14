# DY-M3 — GPU 데모 판

Date: 2026-11-14
Design: `docs/specs/2026-11-12-tars-display-yield-design.md` 결정 12
Status: 끝났다(2026-11-14). commit `c30a838`

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

1. 첫 display 체인은 부팅 3의 `boot`에서 멈췄다 — `terminal never rendered a prompt`. 조각이 terminal의 첫 `screen>` 찍기보다 먼저
   양보를 받아(`display> yield pid 50`) 그 줄도 프롬프트도 데모가 끝나기 전에는 안 온다. 조각은 맞게 떴다. `boot --autorun`이
   yield 줄을 기다리고 프롬프트는 (12a)가 Esc 뒤에 본다. 둘째 판 PASS — `(12a) the first panel ran tars-gpu-demo full screen by itself;
   Esc gave the shell back`, (13)~(15)도 올린 셈 그대로.
2. 묶음 `gpu.sqfs` 71,798,784 → 71,802,880 B(파일 768). 체인 뒤 commit에서 stamp를 지우고 base · gpu를 다시 구웠다 — 캐시를 탄 판은
   출처 기록이 commit 전의 `-dirty`였다.
3. ISO `tars-0.2.2-gpu-x86_64.iso` 474,527,744 B(base 257,486,848 · gpu 71,802,880), sha256
   `c4bc97d3010e462a420dd4593a4553375bf17359738c0fbd292d0cc3b08ba4ba`. 버전 글자 `TARS 0.2.2+c30a838`(tag 뒤 commit). 로컬 `out/release-0.2.2-gpu/`.
4. 라이브 부팅(매체만)에서는 묶음이 안 얹힌다 — init은 홈 디스크가 있을 때만 `.tars/layers`를 얹는다(`init/src/main.zig:1275`). 매체만으로는
   `tars-home`이 없어 셸이 root이고 `overlay` 줄이 없었다. 데모는 설치본에서 뜬다.
5. 설치 smoke(`out/gpu-install-smoke.sh` — devtools 체인의 부팅 모양, OVMF · NVMe 16GiB · SandyBridge): `tars-install --yes`가
   `copied 2 layers (315 MiB) in 1953ms`, 디스크 부팅에서 `overlay /usr from 2 layers in 38ms` → `spawned child … as tars` →
   `display> yield pid 63`. 45초 뒤 screendump 둘의 가운데 색이 다르다(`64,146,109` → `86,64,169`) — 색 띠가 화면 가득 움직인다.
6. 안 본 것: 실기(맥북 에어 2011, i915 · crocus)의 설치 부팅.
