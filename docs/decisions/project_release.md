---
name: project_release
description: "공개 버전 TARS 0.2.2(2026-11-14, v0.2.2 = 16a1072, ISO 넷 — 기본 · nonative · fakesteak · gpu 데모) · 0.1.0(2026-10-11, tag v0.1.0 = 0a6d4bc) · 0.1.1(2026-10-24, v0.1.1 = 1f2978f) · 0.1.2(2026-10-30, v0.1.2 = d2f9ef7, 부분 갱신) · 0.1.3(2026-11-01, v0.1.3 = 055228d, 마우스 선택) · 0.1.4(2026-11-05, v0.1.4 = d93a8aa, 설치해 쓰는 기계 · 맥북) · 0.2.0(2026-11-10, v0.2.0 = 3d84d27, 개발 도구 층) · 0.2.1(2026-11-12, v0.2.1 = 4a26f01, 컨테이너) — GitHub release에 x86_64 ISO 셋(기본 판 · barebone · fakesteak 납품 데모)과 SHA256SUMS. 배포 절차(VERSION 커밋 → annotated tag → make iso → QEMU smoke → 해시 → push · gh release create → 내려받아 대조)와 소개 페이지의 releases 배열. tag가 make iso보다 먼저인 이유는 BV의 버전 글자"
metadata:
  type: project
---

# Release

사용자의 요청(2026-10-11): "여기에서 첫 번째 버전을 찍으면 좋을 것 같아. 버전 번호는 0.1.0. 리눅스 x86_64 버전만 우리는
제공하는 거고 GitHub의 release 페이지에서 ISO 파일을 다운로드 받아서 사용할 수 있도록 공개하자."

## 0.1.0

| 항목 | 값 |
|---|---|
| tag | `v0.1.0` (annotated) → `0a6d4bc` (RS-M3, 마지막 루트 게이트 22체인 PASS) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.0 (Latest, prerelease 아님) |
| ISO | `tars-0.1.0-x86_64.iso`, 111,071,232 B |
| sha256 | `f9ef7da2fd52a74c893ea80dac669a54959bf52458532ae7c66211bfa9a81686` |

notes는 한국어로 썼다 — 다운로드 · 체크섬 확인, 요구 사항(x86_64 · 메모리 1GB · 실기는 Secure Boot 끔), QEMU · USB `dd` ·
`tars-install`, 기능 갈래, 알려진 한계. 자세한 절차는 tag에 고정된 `docs/guides/running-tars.md` 링크로 넘긴다.

## 0.1.1 (2026-10-24)

| 항목 | 값 |
|---|---|
| tag | `v0.1.1` (annotated) → `1f2978f` (`Release 0.1.1`, ZU-M2 뒤. 그 커밋의 루트 게이트 22/22) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.1 (Latest) |
| ISO | `tars-0.1.1-x86_64.iso`, 112,136,192 B (0.1.0보다 1.0MB 큼 — terminal의 디버그 섹션 4.6MB가 gzip 뒤 그만큼) |
| sha256 | `c749d8fc74d39b3d6627723fc9c52c0bffc9cd5d9b5629ffa4af3320734077be` |

0.1.0 뒤의 세 서브프로젝트(BV · GF · ZU)를 담은 도구 층 갱신이다. 노트는 0.1.0 것을 두고 "0.1.0에서 달라진 것" 절을 앞에 더했다.
절차는 아래 1~6을 그대로 밟았고(1의 게이트는 `VERSION` 커밋에서 다시 돌렸다, 10분 34초), 7(소개 페이지)은 사용자 결정으로 건너뛰었다가 2026-10-27에 사용자의 지시로 `releases`에 넣었다.
smoke 로그 첫 줄이 `tars-init: starting as PID 1 (TARS 0.1.1)`로 꼬리표가 없었다 — BV의 버전 글자가 처음으로 릴리즈에서 쓰였다.

## 0.1.2 (2026-10-30)

| 항목 | 값 |
|---|---|
| tag | `v0.1.2` (annotated) → `d2f9ef7` (`Release 0.1.2`, SB-M0 뒤. 그 커밋의 루트 게이트 22/22, 10분 5초) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.2 (Latest) |
| ISO | `tars-0.1.2-x86_64.iso`, 105,799,680 B (0.1.1보다 6.0MB 작음 — LI-M1이 initrd 사본의 디버그 정보를 뗐다) |
| sha256 | `de72b22e63d942f3bcde81f8c1ab63b3ff1ea211d64d19bdd667fd21009e2a8d` |

0.1.1 뒤의 열 서브프로젝트(SA · MS · HC · LS · LI · WP-M3 · LE · CR · DR · SB)를 담았고 본론은 터미널의 부분 갱신(DR + SB)이다. 노트는
0.1.1의 틀에 "0.1.1에서 달라진 것" 절을 새로 썼고, "알려진 한계"의 "CPU 전체 프레임 갱신" 줄을 "CPU다(GPU 가속 없음), 바뀐 행과 상태
줄만"으로 고쳤다. 절차 1~7을 그대로 밟았다 — 1의 게이트는 `VERSION` 커밋에서 돌렸고, smoke 첫 줄이 `TARS 0.1.2`(꼬리표 없음), 7은
같은 날 `releases`에 넣었다. 사용자 요청은 "release this build to 0.1.2 version into github release"(2026-10-30).

## 0.1.3 (2026-11-01)

| 항목 | 값 |
|---|---|
| tag | `v0.1.3` (annotated) → `055228d` (`Release 0.1.3`, ER-M0과 문서 정리 뒤. 그 커밋의 루트 게이트 22/22, lanes 303초) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.3 (Latest) |
| ISO | `tars-0.1.3-x86_64.iso`, 106,567,680 B (0.1.2보다 768KB 큼 — UB의 firmware 21개와 드라이버 여섯) |
| sha256 | `b7e96c2465f327f426d236f776a9f4de408b3d75ce4060a6b1f74ff6bd1a67b7` |

0.1.2 뒤의 서브프로젝트(GH · FR · SN · VS · GI · UB · RP · MC · SE · ER)를 담았고 본론은 마우스 선택(MC · SE · ER)이다. 노트는
0.1.2의 틀에 "0.1.2에서 달라진 것" 절을 새로 썼다. 사용자 요청은 "release 0.1.3"(2026-11-01).
첫 `make iso`의 smoke가 `TARS 0.1.3+055228d-dirty`였다 — 아래 "재사용할 사실"의 줄끝 함정. 디스크의 파일만 다시 써서(커밋 0)
tag는 그대로 두고 ISO를 다시 만들었다.

## 0.1.4 (2026-11-05)

| 항목 | 값 |
|---|---|
| tag | `v0.1.4` (annotated) → `d93a8aa`. 루트 게이트 29/29를 이 커밋의 코드에서 돌았다 |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.1.4 (Latest) |
| ISO | `tars-0.1.4-x86_64.iso`, 136,474,624 B (0.1.3보다 약 30MB 큼 — BT firmware 157개 · ext4 · PM의 도구 층과 glibc 통째로) |
| sha256 | `00598c665bb71de99db3b54c4ae21abb789d1bc869bc23f62e2e687d63c597ab` |

0.1.3 뒤의 KU · BT · KH · HP · PM · MI · IK · DM · KK · PS와 MB · HS · DB(M0 · M1) · BW와 Air · Pro 실기가 드러낸 수정(오디오 일꾼 · bluetoothctl 감싸개 · tars-config 안내 · Option 화면의 "TARS Linux")을 담았다. 2026-11-01의 "0.1.4는 커널 7.4 뒤" 결정은
사용자 요청(2026-11-04, "여기까지 완료 후 다음 패치 버전 찍기: tag, release & distribute!")이 대신했다 — 7.4 이동은 다음 판의 일이다.
smoke 첫 줄 `TARS 0.1.4`(꼬리표 없음), `kms: scale 1 (1280x800 -> 1280x800)`. 맥 실기 확인이 끝날 때까지 0.1.4는 같은 번호로 거듭 낸다 — 그 방식은 [[feedback_release_iteration]].

## 0.2.0 (2026-11-10)

| 항목 | 값 |
|---|---|
| tag | `v0.2.0` (annotated) → `3d84d27` (`Release 0.2.0`). 그 커밋의 루트 게이트 32/32, 2,096초 |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.2.0 (Latest) |
| ISO | `tars-0.2.0-x86_64.iso` 2,036,928,512 B(개발 도구 묶음 열, 2GiB 한도까지 약 110MB) · `tars-0.2.0-barebone-x86_64.iso` 143,761,408 B · `tars-0.2.0-fakesteak-x86_64.iso` 144,089,088 B |
| sha256 | `d3fe88ae13c307b58292de4f0ea35824a3e72b02fda0846fdf508e802a2137bf` · `d158b1aeffcc3ecc55eed7e54f2b4a588a6bee42acca8343a3c60893ab68f390` · `d2f115dfcc9b38f7fabdd51e29470d485ca6fcc514b5e26752918da6666dd5c5` |

0.1.4 뒤의 PW · RB · LP · FS · NS · TP · BB · MF · FU를 담았고 본론은 개발 도구 층(TP)이다 — [[project_release_0_2]]. 릴리스 직전 사용자가
cyber 0.4.4 · cci 0.6.2를 올리라 했다(`0db7fb0`, devtools 체인 PASS 뒤). 사용자: "0.2 build include 2 iso file, barebone, and basic build" →
이어서 "let's include fakesteak iso file too" — 납품 데모가 셋째 ISO가 됐다(`make dev-layers DEV_LAYERS=fakesteak` — 기본 `DEV_LAYERS`에 없어
stamp를 지워도 다시 안 구워진다). 같은 날 dev 프리릴리스 셋과 `demo-fakesteak-20261109`의 release를 지웠다(태그는 남김).
smoke 세 판 모두 첫 줄 `TARS 0.2.0`(꼬리표 없음), 묶음 안 출처 기록도 `v0.2.0`. 노트는 0.1.4의 틀에 "0.1.4에서 달라진 것"과 납품 데모 절.

## 0.2.1 (2026-11-12)

| 항목 | 값 |
|---|---|
| tag | `v0.2.1` (annotated) → `4a26f01` (cyber 0.4.7, devtools 체인 PASS). 루트 게이트는 `0e1b888`의 코드에서 32/33(34분 51초) — 빨간 pm은 체인의 기대 글자 한 줄이었고 고친 뒤 단독 초록. 그 뒤의 커밋은 그 한 줄 · 문서 · cyber 판뿐이다 |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.2.1 (Latest) |
| ISO | `tars-0.2.1-x86_64.iso` 2,144,473,088 B(묶음 열하나 1,908MiB — 2GiB 한도까지 약 2.9MB) · `tars-0.2.1-barebone-x86_64.iso` 144,596,992 B · `tars-0.2.1-fakesteak-x86_64.iso` 144,924,672 B |
| sha256 | `ad2f2213ff4941bdebbf0c202e3e40ce5d6ca864ea4766513da303926f5a65bc` · `77eee505bf9021ec96152dd40ae9dcb1529843a5e95022dda8ed98d415ce6f74` · `c30399dee001806a54b7a9d96fb03166fa6603f92881bf15c88a937e4f833600` |

0.2.0 뒤의 CO · GV · SS · LT · CE와 cyber 0.4.7을 담았고 본론은 컨테이너(CE)다 — [[project_container_environment]] · [[project_little_things]].
사용자: "이 작업이 완성되면 0.2.1 버전을 릴리즈/배포 합니다"(2026-11-11). smoke 세 판 모두 첫 줄 `TARS 0.2.1`(꼬리표 없음),
`root is a bind mount of the initramfs`, `landlock: Up and running.`, 묶음의 출처 기록 `v0.2.1`. 받아서 `shasum -c` 셋 다 OK.
노트는 0.2.0의 틀에 "0.2.0에서 달라진 것"(컨테이너 · 작은 것 다섯)과 "알려진 한계"의 두 줄(CPU 하나 · `firewall=off`에서의 forward).
절차에서 배운 것: `VERSION` 커밋(`1de4899`) 뒤에 수정 커밋이 더 붙어 태그는 닫기 뒤의 커밋에 달았다 — 다음에는 게이트가 초록인 것을 본 뒤
`VERSION`을 올린다. 기본 판이 2GiB에 닿았으니 다음 판에서 묶음이 자라면 먼저 `carryover.md`의 "묶음 사이 같은 파일 지우기"를 한다.

## 0.2.2 (2026-11-14, 공개 — ISO 넷)

| 항목 | 값 |
|---|---|
| tag | `v0.2.2` (annotated, 2026-11-14 push — `main`도 `4aaeb2d`까지) → `16a1072` (`Release 0.2.2`). 루트 게이트 34/34 첫 판, lanes 1,593초, 잘린 줄 0 |
| ISO | `tars-0.2.2-x86_64.iso` 1,990,055,936 B(server를 뺀 묶음 열둘) · `tars-0.2.2-nonative-x86_64.iso` 1,645,989,888 B(lang-native를 뺀 열둘) · `tars-0.2.2-fakesteak-x86_64.iso` 145,563,648 B · `tars-0.2.2-gpu-x86_64.iso` 474,527,744 B(base · gpu, DY-M3) |
| sha256 | `53b70210…eb04e03c` · `6d7a811d…c06661893` · `a92c8926…8789a706` · `c4bc97d3…b08ba4ba` (SHA256SUMS, 넷) |
| release | https://github.com/soomtong/tars-linux/releases/tag/v0.2.2 (2026-11-14, Latest) — 사용자: "tag 0.2.2 and release and publish them all of 4 iso" |
| 로컬 | `make iso-full` → `out/tars-full.iso` 2,139,080,704 B(열셋, `TARS 0.2.2`), 같은 파일의 하드 링크 `out/tars-0.2.2-full-x86_64.iso`, sha256 `6bce5351…aeb334b` — GitHub에 안 올린다(사용자: 로컬 디스크의 것을 쓴다) |

0.2.1 뒤의 DY · GU · LD · OD · TU를 담았고 본론은 도구 판올림(TU)이다. 사용자가 외출하며 "모든 결정을 위임"했고(2026-11-14), lead는
절차 1~5까지 하고 6(push · `gh release create`)과 7(소개 페이지)은 사용자가 돌아와 정하도록 멈췄다 — 바깥으로 나가는 일이고 `main`의
push도 함께다([[feedback_push_policy]]). ISO · SHA256SUMS · NOTES.md는 `out/release-0.2.2/`에 있다(git이 무시하는 자리 — `make clean`이 지울 수 있으니
그때는 tag에서 절차 3부터 다시). smoke 셋 모두 꼬리표 없는 `TARS 0.2.2` · grid · fish, panic 0. 각 ISO의 `/boot/layers`를
`xorriso -ls`로 대조했다.

### GPU 데모 판 (DY-M3, 2026-11-14)

사용자: "0.2.2 작업의 핵심은 gpu 관련 기능이야. 이 데모를 위해 fakesteak 처럼 하나의 iso 파일을 구워줘." `v0.2.2`와 `main`은 이 앞에 push했다
(사용자 "릴리즈 태그를 붙이도록 할게"). `make iso ISO_LAYERS="base gpu"` → `tars-0.2.2-gpu-x86_64.iso` 474,527,744 B, sha256 `c4bc97d3…b08ba4ba`,
버전 글자 `TARS 0.2.2+c30a838`(tag 뒤 commit — 꼬리가 붙는다). 설치하면 첫 패널이 `tars-gpu-demo`를 화면 가득 띄운다(라이브 부팅에서는 안 뜬다 —
묶음은 설치본의 홈에서 얹힌다). 로컬 `out/release-0.2.2-gpu/`. GitHub에 어떻게 올릴지(0.2.2 release에 더할지, 따로 낼지)는 사용자가 정한다.

## 0.2.2부터의 배포 모양 (사용자 결정 2026-11-14)

GitHub release(파일 하나당 2GiB)에는 ISO 셋만 올린다: 개발 도구 층에서 `server`만 뺀 판, `lang-native`만 뺀 판, fakesteak 납품 데모.
barebone과 묶음 전부 판은 올리지 않는다. 묶음 전부 판은 `make iso-full`(`out/tars-full.iso`)로 로컬에 남겨 `dd`로 쓴다 — 다른 길(외부
호스팅)은 사용자가 정한다. 계기: odin을 더하면 묶음 전부 판이 2GiB까지 약 11.5MiB(OD design "배포"). 아래 절차 3 · 5 · 6은 0.2.2를 낼 때
이 모양으로 고쳤다(2026-11-14) — barebone은 "0.2.1까지"로 남긴다.

## 배포 절차 (다음 버전도 이대로)

BV(2026-10-20)부터 시스템 안에 버전이 있다. 빌드는 HEAD가 `v<VERSION>` 태그이고 추적 파일에 고친 데가 없을 때만 맨 `<ver>`를
박고, 그 밖에는 `+<sha>`(·`-dirty`)를 붙인다(`docs/specs/2026-10-20-tars-build-version-design.md` 결정 2). 그래서 tag가
`make iso`보다 먼저다.

1. 저장소 뿌리의 `VERSION`을 새 번호로 고쳐 커밋한다. 그 커밋에서 루트 게이트가 PASS인지 본다(게이트 이미지는
   `+<sha>`를 단다). 트리는 clean이어야 한다.
2. `git tag -a v<ver> <그 커밋> -m …`. push는 아직 안 한다.
3. (0.2.2부터) 먼저 묶음을 모두 굽는다(아래 문단). 그다음 `make iso ISO_LAYERS="<묶음 전부에서 server를 뺀 것>"` → smoke → 저장소 밖 빈
   디렉터리에 `tars-<ver>-x86_64.iso`(기본 판 — 개발 도구에서 서버만 뺀 것), `make iso ISO_LAYERS="<묶음 전부에서 lang-native를 뺀 것>"` →
   smoke → `tars-<ver>-nonative-x86_64.iso`, 납품 데모는 아래 그대로 `tars-<ver>-fakesteak-x86_64.iso`. `make iso`는 `out/tars.iso`
   하나에 쓰므로 짓고 바로 옮긴다. 묶음 전부 판은 `make iso-full`로 로컬에만 둔다.
   (0.2.1까지) barebone ISO(BB-M0부터 — 개발 도구 층 없음, [[project_minimal_iso]])를 먼저 짓는다: `make iso`(ISO_LAYERS 비움), 절차 4의 smoke, 저장소 밖
   빈 디렉터리에 `tars-<ver>-barebone-x86_64.iso`로 옮긴다(`make iso`는 `out/tars.iso` 하나에 쓰므로 다음 짓기가 덮는다). 같은 트리라
   버전 글자는 묶음 판과 같다. BB-M0 실측: 143,751,168 B, 196초(initrd · kernel 캐시).
   그다음 묶음을 모두 굽는다: `rm -f devlayer/build/*.stamp && make dev-layers`(묶음 안 출처 기록의 `-dirty`가 stamp에 안 들어가 남는다 —
   dev-20261106에서 겪었다). LD-M0(2026-11-12)부터 기본 `DEV_LAYERS`가 fakesteak까지 열둘(DY-M2부터 gpu까지 열셋)이라 따로 굽지 않는다. 굽는 동안 추적 파일을
   고치지 않는다(출처 기록이 `-dirty`가 된다 — [[feedback_release_iteration]]의 함정).
   납품 데모(0.2.0부터 — fakesteak)는 `make iso ISO_LAYERS="fakesteak"`, smoke(base가 없으니 첫 패널에 비가 뜬다), 같은 디렉터리에
   `tars-<ver>-fakesteak-x86_64.iso`. fakesteak은 독립 묶음이라 혼자 실린다(`devlayer/standalone-bundles`).
   기본 판은 `make iso ISO_LAYERS="base container docs editor fakesteak gpu lang-beam lang-jvm lang-native lang-script media server util"`
   (기본값은 묶음을 안 싣는다). base 없이 다른 묶음을 실으면 `make_iso.sh`가 멈춘다 — base와 겹친 파일이 지워져 있다(LD design 결정 1 · 3).
   개발 도구의 판을 올리는 것은 버전을 낼 때 한 번이다(TP design 결정 3): `devlayer/manifest.toml`의 표(version · url · sha256)를 1의 커밋에
   함께 넣고(`make quick`이 검사한다 — MF-M0), 바뀐 표의 묶음만 다시 구워진다. 올리지 않으면 앞 판의 묶음이 그대로 실린다.
   `make iso` — 입력 해시가 같으면 kernel · terminal을 건너뛴다. init은 `zig build`가 git을 다시 물어 버전 글자가 바뀌었으면
   다시 컴파일한다. `out/tars.iso`가 이미 있어도 어느 트리의 것인지 모르므로 다시 만든다.
4. 호스트 QEMU smoke — `qemu-system-x86_64 -m 1024 -cdrom out/tars.iso -display none -serial file:<log>`를 90초 띄우고
   `tars-init: starting as PID 1 (TARS <ver>)`(꼬리표 없이) · `terminal: grid` · `spawned child … fish`가 있고
   `Kernel panic`이 0인지 본다. 설정 디스크를 안 붙여 처음 받은 사람과 같은 기본값 경로를 밟는다. 꼬리표가 붙었거나
   smoke가 실패하면 `git tag -d v<ver>`로 지우고 고친다 — push 전이라 바깥에 안 나갔다.
5. 저장소 밖 빈 디렉터리(3의 ISO가 있는 곳)에서 세 ISO를 한 번에 `shasum -a 256 … > SHA256SUMS`.
6. `git push origin v<ver>` →
   `gh release create v<ver> <iso> <nonative iso> <fakesteak iso> SHA256SUMS --title "TARS <ver>" --notes-file NOTES.md --verify-tag --latest`.
   새 빈 디렉터리에 `gh release download v<ver>` 후 `shasum -a 256 -c SHA256SUMS`가 `OK`인지 본다.
7. 소개 페이지 — `gh-pages`의 `data.js` `releases`에 한 줄(`site/README.md`의 "릴리스를 냈을 때").

## 재사용할 사실

- 버전의 dirty는 컨테이너의 git이 판정한다(`init/build.zig`의 `status --porcelain`). 호스트 `~/.gitconfig`의
  `core.autocrlf=input`은 작업 트리의 CRLF를 비교에서 감춰 호스트에선 깨끗한데, 설정 없는 컨테이너는 그 파일을 수정으로 본다.
  FR-M0의 `terminal/vendor/fonts/OFL-1.1.txt`가 blob은 LF · 디스크는 CRLF여서 그 뒤 모든 빌드가 `-dirty`였다(게이트 이미지는
  어차피 `+<sha>`라 안 보였다). 3단계 전에 `git ls-files --eol | rg 'w/crlf' | rg -v 'i/crlf'`가 비었는지 본다. 고칠 때는 파일을
  지우고 `git checkout -- <파일>`.
- ISO 하나가 BIOS · UEFI 겸용 hybrid라 아키텍처별 · 펌웨어별로 나눌 것이 없다. 이름의 `x86_64`는 arm64 빌드가 없다는 표시다.
- `make iso` 끝의 `No active partition found` · `Reminder: … limine-bios.sys`는 `limine bios-install`의 평소 출력이다.
- 0.1.0 ISO 안에는 버전이 없다 — 그 이미지는 ISO 파일 이름과 sha256만이 버전을 말한다. BV(2026-10-20) 뒤의 빌드는
  `tars-config version`과 부팅 로그 첫 줄 `tars-init: starting as PID 1 (TARS <ver>)`이 말한다.
- 소개 페이지의 숫자 칸 "끝낸 서브프로젝트"는 `timeline.length`다. 그래서 릴리스는 `timeline`이 아니라 별도 `releases`에
  두고, 작업 내역에는 섞어 그리되(`RELEASE` 표시, 같은 날이면 위) 수에는 안 넣는다.

관련: [[project_render_speed]] (0.1.0이 담은 마지막 서브프로젝트), [[feedback_push_policy]]
