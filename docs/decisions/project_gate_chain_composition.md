---
name: project_gate_chain_composition
description: "루트 check.sh의 체인 구성 원칙 — 낡은 게이트는 되살리지 말고 은퇴; clean()은 빌드 산출물만; initrd 크기는 BF에서만 병목이나 크기가 곧 시간은 아니다; 게이트는 자기가 안 보는 것을 통과시키므로 재작성 전에 검사부터 추가한다"
metadata:
  node_type: memory
  type: project
---

2026-08-12 TF-M4에서 루트 `check.sh`를 **BF + TF 두 체인**으로 재구성했다.
DF 체인(`display/check.sh`)은 은퇴시켰다.

## 낡은 게이트는 되살리지 않고 은퇴시킨다

DF 게이트는 "화면 (10,10)이 kms가 칠한 빨강인가"를 본다. TF-M2에서
`kernel/make_initrd.sh`가 initrd에 kms 대신 terminal을 넣고
`init/src/main.rs`가 `/terminal`을 fork하도록 바뀌면서, 부팅된 시스템에 kms가
존재하지 않게 됐다. 되살리려면 커널 cmdline으로 무엇을 띄울지 고르는 부팅
모드 스위치를 새로 만들어야 하는데, DF가 검증하던 DRM/KMS present 경로는 TF
체인이 매 회차 실제로 픽셀을 띄우며 이미 검증한다. **죽은 테스트를 살리려고
제품 코드(부팅 경로)에 분기를 넣지 않는다.**

남긴 두 체인의 역할 분담: BF는 limine ISO 부팅 경로를, TF는 부팅 이후의
런타임 전체(DRM 렌더링 + evdev 입력 + PTY 셸)를 본다. TF가 BF를 대신하지
못하는 유일한 지점이 부트로더다 — TF는 `-kernel`/`-initrd` 직접 부팅이다.

## `make_initrd.sh`의 복사 목록이 바뀌면 다른 체인이 조용히 깨진다

같은 사고가 **두 번** 났다. DF-M3에서는 `make_initrd.sh`가 kms를 복사하기
시작했는데 `boot/check.sh`가 kms를 빌드하지 않아 깨졌고, TF-M4에서는 terminal
바이너리로 똑같이 깨졌다(`cp: cannot stat
'../terminal/zig-out/bin/terminal'`). 둘 다 "그 체인을 한동안 아무도 돌리지
않아서" 몇 milestone 동안 드러나지 않았다.

TF-M4의 대응: vendor 준비 + `zig build`를 `terminal/prepare.sh`로 뽑아
`boot/check.sh`와 `terminal/check.sh`가 함께 부르게 했다. `make_initrd.sh`가
직접 그걸 부르게 하지는 않았다 — 그 스크립트는 init·fish·폰트 중 아무것도
빌드하지 않는 순수 조립 스크립트인데 terminal만 예외로 두면 비대칭이 생긴다.
재발 방지는 **루트 게이트가 모든 체인을 매번 돌리는 것** 자체가 맡는다.

## `clean()`이 지워도 되는 것은 빌드 산출물뿐

`terminal/ghostty-src`(GitHub tarball), `terminal/vendor`(폰트·헤더·libghostty-vt
산출물), `terminal/zig-pkg`(Zig 0.16의 프로젝트 로컬 패키지 캐시)는 전부
`.gitignore` 대상이라 눈에 안 띄지만 **네트워크에서만 복구된다.** clean 목록에
넣으면 3회 반복의 첫 회차가 나머지를 오프라인에서 복구 불가능하게 만든다.
`.zig-cache`(컴파일 캐시, 지워도 됨)와 `zig-pkg`(패키지 캐시, 지우면 안 됨)는
이름이 비슷하고 성격이 반대다.

## initrd 크기는 BF 체인에서만 병목이다

TF-M4에서 BF가 부팅조차 못 하고 120초를 넘겼다(serial 출력 0바이트). 원인은
initrd 53MB — Debug 빌드 terminal이 42MB였고 그 대부분이 디버그 심볼이다.
같은 initrd로 TF 체인은 멀쩡히 부팅한다. **로딩 경로가 다르기 때문이다**:
TF는 QEMU가 `-initrd`로 호스트 파일을 게스트 메모리에 직접 복사하지만, BF는
limine이 BIOS INT13h로 ISO9660에서 읽으며 이 경로가 에뮬레이션에서 극단적으로
느리다.

해결은 `make_initrd.sh`에서 **cpio를 gzip으로 압축**한 것이다(53MB →
11.8MB, BF 부팅 ~34초). 최적화 모드를 낮추는 방법은 `@cImport`가 깨져서 못
썼다([[project_zig_c_uapi_rule]]).

**strip은 쓰지 않기로 했다.** 측정은 해봤다 — initrd에 넣는 복사본만
strip하면 6.5MB, 부팅 25초로 더 낫다(gzip 대비 5MB, 9초 이득). 그런데 Zig의
에러 트레이스는 **바이너리 자체의 디버그 정보를 런타임에 읽어** 만들기
때문에, strip하면 게스트 안에서 트레이스를 되살릴 방법이 원리적으로
사라진다(호스트에 심볼 있는 사본을 둬도 소용없다). 5MB와 9초는 그 가능성을
영구히 포기할 값이 아니다.

단, **심볼이 있다고 트레이스가 바로 읽히지는 않았다.** 같은 크래시
(`/dev/dri/card0`이 없는 BF 부팅에서 terminal이 `error: OpenFailed`로 죽는
경로)에서 strip 버전은 `???:?:?: 0x12716d8 in ???` 두 줄을 찍었고 심볼
버전은 트레이스를 아예 안 찍었다. 원인 미규명 — 실제 버그를 쫓게 될 때 파고들
거리로 남겨뒀다. 지금의 선택은 "트레이스가 잘 나와서"가 아니라 "strip하면
고칠 여지 자체가 없어서"다.

**크기가 곧 시간은 아니다(2026-08-13 ZM-M1 실측).** initrd가 11.8MB에서
14MB로 19% 늘었는데 BF 부팅 시간은 34/33/33초로 **변하지 않았다**. 단독
1회 실행에서 39초가 나와 크기 탓으로 의심했으나 3회 반복에서 사라진
노이즈였다. 53MB에서 못 부팅한 것은 선형적인 느려짐이 아니라 다른 종류의
벽이었다는 뜻이다. **크기 회귀를 의심할 때는 단발 측정을 믿지 말 것.**

## 게이트는 자기가 안 보는 것을 통과시킨다

ZM-M1에서 드러났다. BF는 fish 배너를, TF는 `terminal: screen>`을 grep한다.
둘 다 **PID 1이 무엇을 했는지는 전혀 보지 않는다.** `init`이 `/proc` 하나
못 붙여도 fish만 뜨면 두 체인 모두 PASS다. PID 1을 Rust에서 Zig로 통째로
다시 쓰는 작업에서 이 사각지대는 실제 위험이었다.

대응은 두 체인에 `tars-init: mounted ...` 네 줄 검사를 넣은 것이다.
처음에는 "사람이 로그를 눈으로 확인"으로 plan을 썼는데, 그 방식은 (a) TF의
serial 로그가 컨테이너 안 `mktemp` 파일이라 `--rm`과 함께 사라져서 애초에
불가능했고, (b) 가능했더라도 다음 milestone부터는 아무도 안 본다.
**검증 절차를 사람 눈에 맡기는 설계는 그 자리에서 스크립트로 옮길 것.**

마커 문자열이 `init/src/main.zig`와 두 check 스크립트에 중복된다. 공유
파일로 빼지 않은 것은 두 체인이 각자 단독 실행 가능해야 한다는 설계 때문이다
— 대신 **init의 출력 문자열을 바꾸면 두 스크립트를 같이 고쳐야 한다.**

**How to apply:** 부팅 경로나 initrd 구성을 바꾸면 (1) 다른 체인의 빌드
단계가 뒤처지지 않았는지, (2) initrd가 커져서 BF의 ISO 로딩이 느려지지
않았는지 두 가지를 먼저 확인한다. 새 게이트를 추가할 때는 clean 대상에
vendor 트리·패키지 캐시가 섞이지 않았는지 확인한다. 어떤 컴포넌트를 다시
쓰는 작업을 시작할 때는 **"게이트가 이 컴포넌트의 무엇을 실제로 보는가"를
먼저 확인한다** — 안 보고 있으면 그 검사를 먼저 추가하고 재작성에 들어간다.

관련: [[project_zig_c_uapi_rule]], [[project_zig_rewrite_intent]]
