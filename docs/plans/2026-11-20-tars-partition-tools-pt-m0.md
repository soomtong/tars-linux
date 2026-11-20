# PT-M0 — fdisk · cfdisk를 initrd에

Date: 2026-11-20
Design: `docs/specs/2026-11-20-tars-partition-tools-design.md`(결정 1~4)
Status: 끝났다(2026-11-20) — 루트 게이트는 사용자의 맥에서 남았다(결과 절).

Goal: Debian trixie `fdisk` 패키지의 `fdisk`(대화형)와 `cfdisk`(화면형)를 initrd의 층 7(`sfdisk` 옆)에 싣고, tools 체인이 게스트에서 두 도구가
파일 이미지의 GPT를 읽고 화면을 그리는 것을 본다. 사용자 요청: "cfdisk와 fdisk 넣는 plan 작성해 주세요. 이어서 구현을 하시고 PR해주세요."

## 착수 전에 확정한 것 (HEAD `8f429eb`)

1. 길은 LT-M0의 ping과 같다 — `devcontainer/Dockerfile`이 `.deb`를 amd64 sysroot에 풀고, `kernel/guest_tools.sh`의 `GUEST_TOOLS`가
   `sysroot 경로:initrd 경로` 한 줄로 고르고, `kernel/make_initrd.sh`의 `copy_lib_deps`가 NEEDED를 따라간다. 이번에는 첫 단계가 없다 —
   `fdisk:amd64`(세 바이너리 전부) · `libmount1:amd64`가 이미 sysroot에 있다(design 확인 3). Dockerfile을 안 고치므로 이미지 태그도 그대로다.
2. `tools/check.sh` 검사 1이 `GUEST_TOOLS`를 되읽으므로 두 줄을 더하면 "initrd에 들었나"는 자동이다. 검사 19(음성 확인, 맨 뒤)는 그 앞에 친
   모든 이름의 `Unknown command`를 함께 잡는다.
3. 게스트 셸은 fish, 512MiB, 디스크 없음(`-nic none`, 블록 장치를 안 붙인다). fdisk 셋은 일반 파일을 디스크처럼 다루므로 `/tmp`(RAM)의
   8MiB 파일이면 된다. initrd에 `truncate` · `dd`가 없다 — `head -c 8M /dev/zero`(coreutils `head`, 층 1)로 만든다.
4. 화면 판정은 `wait_for_screen`(로그 전체의 화면 줄, 15초). 판정 글자는 친 줄의 에코에 없는 글자여야 한다(`measurements.md` 26).
   화면을 통째로 가져가는 대화형(htop · btop · alsamixer)은 지금까지 목록 검사까지만 받았다 — 끝내는 키가 없으면 체인이 매달리기 때문이다.
   cfdisk는 `q` 한 키로 쓰지 않고 끝나므로, 화면을 본 뒤 `q`를 보내고 셸이 돌아왔는지까지 본다.
5. 키 이름의 선례: `|` = `shift-backslash`, `,` = `comma`, `>` = `shift-dot`, `$` = `shift-4`(tools · net 체인).

## Task 1 — `kernel/guest_tools.sh` 층 7에 두 줄

`sfdisk` 줄 옆에 `usr/sbin/fdisk:usr/bin/fdisk` · `usr/sbin/cfdisk:usr/bin/cfdisk`. 층 제목의 수(3 → 5)와 주석 — 무엇을 왜(PT design
결정 1 · 2, 기준 B), 크기와 새 라이브러리(빌드 뒤 센 값으로 채운다). 층 7 주석의 "libmount는 안 온다"는 cfdisk가 바꾸므로 고친다.

## Task 2 — `tools/check.sh` 검사 29

검사 28 뒤, 검사 19(맨 뒤) 앞. 치는 것과 판정(친 줄에 안 생기는 글자):

| 친다 | 판정 |
|---|---|
| `fdisk --version; cfdisk --version` | `(^|\| )fdisk from util-linux` · `cfdisk from util-linux` |
| `head -c 8M /dev/zero > /tmp/pt.img; echo , \| sfdisk -q -X gpt /tmp/pt.img; echo pt-mk=$status` | `pt-mk=0` |
| `fdisk -l /tmp/pt.img` | `Disklabel type: gpt` · `img1[[:space:]]*2048` |
| `cfdisk /tmp/pt.img` | `Label: gpt` (cfdisk 화면의 머리) |
| `q` 뒤 `echo pt-back=$status` | `pt-back=0` |

검사 19의 주석("그 뒤에 더해진 것")에 PT-M0의 둘을 더한다.

## Task 3 — 안내 · 기준 기록

- `docs/help/config.md`에 "디스크와 파티션" 절(design 결정 4) — `sudo fdisk -l`, `sudo cfdisk /dev/sda`, TARS 파티션 이름 셋의 경고.
  `docs/help/check.sh`(make quick 단계 6)는 `tars-config` · `tars-service` · `tars-help`만 대조하므로 새 줄은 사람이 본다.
- `docs/guides/initrd-criteria.md`의 적용 기록에 한 행(기준 B).

## Task 4 — 게이트(lead)

1. `make quick`(`quick_check.sh` — shellcheck · help 대조 등).
2. 체인 tools 단독 — 바꾸기 전 한 판(기준선, initrd 크기), 바꾼 뒤 한 판. 새 라이브러리 수는 두 initrd의 `cpio -t` 차이로 센다.
3. 루트 게이트.

## Task 5 — 닫기

design `Status:`, 이 plan의 결과, `completed.md` 한 행, 기억 한 파일(`project_partition_tools`) · `MEMORY.md` 한 줄, `HANDOFF.md`.
소개 페이지(`gh-pages`의 `data.js`)는 별도 브랜치라 이 PR에 안 든다 — 남은 일로 적는다.

## 판정

- 체인 tools PASS — 검사 1이 두 파일을 initrd에서 보고, 검사 29의 판정 일곱이 서고, 검사 19가 `Unknown command` 0.
- `make quick` PASS.
- 루트 게이트 초록(바뀐 것은 initrd의 파일 둘과 라이브러리뿐이라 다른 체인의 판정은 그대로여야 한다).

## 비목표

design의 비목표 그대로 — gdisk · cgdisk · parted, `lsblk` 등 디스크 진단 도구, 파일 시스템 크기 조절, 개발 도구 층의 최신판.

## 위험

1. cfdisk 화면(design 위험 1). 검사 29가 `Label: gpt`를 못 보면 화면 dump를 읽고 판단한다 — 깨졌으면 그것이 새 사실이다.
2. `q`가 cfdisk가 키를 받기 전에 가면 무시될 수 있다 — 화면 판정 뒤에 보내므로 cfdisk는 이미 입력을 기다리는 중이다.
3. 이 세션(클라우드, amd64 · KVM 없음)에서는 저장소의 arm64 이미지가 돌지 않는다. Dockerfile의 호스트 몫 둘(크로스 gcc 패키지 이름 · zig
   tarball)만 바꾼 amd64 판을 scratchpad에서 구워 게이트를 돌린다 — 게스트 산출물의 출처(amd64 sysroot · 같은 zig 판)는 같다. 다른 점은
   결과 절에 적는다.

## 결과

판정을 지났다(2026-11-20). plan과 다른 자리는 없다 — 검사 29가 첫 판에 초록이었다.

잰 것(기준선 = HEAD `8f429eb`의 tools 체인이 구운 initrd):

| | 고치기 전 | 고친 뒤 |
|---|---|---|
| initrd(gzip) | 128,930,298 B | 129,271,380 B (+341,082) |
| cpio 항목 | 1,301 | 1,304 — `usr/bin/fdisk` · `usr/bin/cfdisk` · `lib/x86_64-linux-gnu/libmount.so.1` |

풀린 크기로는 fdisk 178,616 + cfdisk 113,400 + libmount 502,512 = 794,528 B. libmount 뒤의 libblkid · libselinux · libpcre2-8과
libncursesw는 기준선 initrd에 이미 있었다 — design 확인 2의 예측 그대로 새 라이브러리는 하나다.

게이트(이 세션 — 아래 "환경"):
- 체인 tools: 기준선 PASS(2분 49초) → 고친 뒤 PASS(2분 12초). 검사 29의 다섯 단계가 모두 첫 대기 안에 섰다.
- mutation: 층 7에서 cfdisk 줄 하나를 뺀 판 — 검사 1은 초록(목록을 되읽는다), 검사 29가 화면의 `fdisk from util-linux 2.41.5` 다음
  `fish: Unknown command: cfdisk`로 `FAIL: cfdisk did not print its version`. 되돌린 파일은 `cmp`로 원본과 같다.
- 층 7의 이웃 체인: install PASS(부팅 아홉, 156초) · dualboot PASS(148초, 맥 파티션 바이트 그대로) · home PASS(86초).
- 루트 게이트 입구 검사 셋(`require_build_steps` · `require_no_early_exit_pipe` · `require_explicit_nic`) ENTRY-OK, `make quick` PASS
  (shellcheck 0.11.0 · 96파일).
- 루트 게이트 전체는 돌리지 않았다 — 이 세션에서는 `devtools`(묶음 열셋) · `pm` · `mise`(게스트가 바깥 망으로)가 환경 때문에 못 선다.
  **사용자의 맥에서 루트 게이트를 한 번 돌려야 닫힌다.** 바뀐 것이 initrd의 파일 셋과 안내 한 절뿐이라 다른 체인의 판정이 바뀔 자리는
  initrd 크기(게스트 RAM에 약 0.8MB)뿐이다.

환경: 클라우드 세션(amd64, KVM 없음, 4코어). ghcr의 이미지는 arm64 전용이라 안 돈다 — Dockerfile 사본에서 호스트 몫 둘(`gcc-multilib` ·
zig `x86_64` tarball, sha256은 `checks.yml`의 값)과 세션 프록시 CA 층을 바꿔 구웠다. 게스트 산출물의 출처(amd64 sysroot의 Debian
패키지 · zig 0.17.1)는 같다 — sysroot의 fdisk 셋 크기가 design 확인 1과 바이트까지 같다. 프록시를 지나는 법은 기억
`project_partition_tools`의 "배운 것" 4.
