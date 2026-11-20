# TARS Partition Tools — Design

접두사: PT

Date: 2026-11-20
Status: 닫힘(2026-11-20, PT-M0 — 체인 tools · install · dualboot · home PASS, `make quick` PASS). plan은
`docs/plans/2026-11-20-tars-partition-tools-pt-m0.md`. 루트 게이트는 사용자의 맥에서 한 번 남았다(클라우드 세션에서는 devtools · pm · mise가
환경 때문에 못 선다).

계기: 사용자 — "우리 tars linux에 디스크 파티션 프로그램이 탑재되어 있나요?" → initrd에는 `sfdisk` 하나뿐이고 그것은 `tars-install`이
부르려고 실은 것(DI-M0, 층 7)이라는 답 → "쉽게 쓸 수 있는 파티션 프로그램은 어떤 것이 있을까요? 터미널 기반입니다." → 후보 다섯(cfdisk ·
fdisk · cgdisk · gdisk · parted)을 견준 답의 추천 → "cfdisk와 fdisk 넣는 plan 작성해 주세요. 이어서 구현을 하시고 PR해주세요."

관련 문서: DI design(`2026-09-19-tars-disk-install-design.md` — 층 7) · DB design(`2026-11-04-tars-dual-boot-design.md` 결정 4 — TARS
파티션을 GPT 이름으로 찾는다) · `docs/guides/initrd-criteria.md`.

## 한 줄 요약

Debian trixie `fdisk` 패키지의 나머지 둘 — 대화형 `fdisk`와 화면형 `cfdisk` — 를 `sfdisk` 옆(층 7)에 싣는다. 패키지는 이미 sysroot에 있어
Dockerfile은 안 바뀐다.

## 확인 (2026-11-20, HEAD `8f429eb`)

1. Debian trixie `fdisk_2.41.5-0+deb13u1_amd64.deb`를 받아 풀었다. 한 패키지에 셋이 있고 셋 다 `libfdisk` 위에 선다.

   | 바이너리 | 크기(B) | NEEDED |
   |---|---|---|
   | `usr/sbin/sfdisk` | 162,184 | libfdisk · libsmartcols · libtinfo · libreadline · libc |
   | `usr/sbin/fdisk` | 178,616 | libfdisk · libsmartcols · libtinfo · libreadline · libc |
   | `usr/sbin/cfdisk` | 113,400 | libsmartcols · libfdisk · **libmount** · libncursesw · libtinfo · libc |

   `sfdisk`가 162,184 B로 `guest_tools.sh` 층 7 주석의 DI-M0 실측과 같다 — 이미지의 sysroot와 같은 판이다.
2. `fdisk`의 NEEDED는 `sfdisk`와 같다 — initrd에 새 라이브러리 0개. `cfdisk`는 libmount가 새로 온다(층 7 주석: "libmount는 안 온다 —
   libfdisk가 안 부른다"). libncursesw는 alsamixer(층 14, AU-M0)가 이미 initrd에 들였다. libmount의 사슬(libblkid · libselinux 쪽)은
   `copy_lib_deps`가 따라가고, 실제 수는 PT-M0이 initrd를 구워 센다.
3. `devcontainer/Dockerfile`이 `fdisk:amd64`와 `libmount1:amd64`를 이미 sysroot에 받는다(DI-M0 · 층 7). 바이너리 둘과 라이브러리가 이미
   거기 있으므로 이미지를 다시 굽지 않는다 — Dockerfile을 한 글자라도 고치면 태그가 바뀌어 CI가 다시 굽는다(`devcontainer/image.sh`).
4. 견준 나머지(같은 날 trixie 패키지에서): `cgdisk` 231,840 B · `gdisk` 240,032 B(C++ — libstdc++ · libuuid · libncursesw), `parted` 88,400 B +
   `libparted` 332,288 B(libdevmapper가 새 사슬). 셋 다 이번에는 안 싣는다(비목표).

## 결정

### 결정 1 — `fdisk`와 `cfdisk` 둘, `fdisk` 패키지에서

- `cfdisk`: 사람에게 쉬운 쪽. 표와 빈 공간이 화면에 보이고 방향키로 고르며, `Write`에 `yes`를 쳐야만 디스크에 쓴다.
- `fdisk`: 한 글자 명령의 대화형. `fdisk -l`이 디스크 목록과 표를 한 번에 보인다 — initrd에 `lsblk`가 없는 지금 "디스크 이름이 무엇인가"의
  답이기도 하다.
- 셋(`sfdisk` 포함)이 한 엔진(libfdisk)이다. 사람이 보는 표와 `tars-install`이 쓰고 다시 읽는 표가 같은 코드로 읽힌다.
- gdisk · cgdisk · parted는 안 싣는다 — 같은 일을 하는 도구가 이미 있으면 안 넣는다(initrd 기준의 "함께 보는 것" 첫째). parted는
  즉시 반영이라 되돌릴 수 없는 것도 이유다.

### 결정 2 — initrd(기준 B), 층 7

`docs/guides/initrd-criteria.md`의 기준 B — 라이브 USB · 설치 전 · 개발 도구 층이 깨진 부팅에서 복구 · 설치에 쓰는 것. 파티션을 고칠 일은
설치 전(`tars-install --beside`로 둘 자리를 만들기)과 복구 때 생기고, 그때 개발 도구 층은 없거나 못 믿는다. 자리는 `guest_tools.sh` 층 7
(디스크를 만드는 도구) — 같은 패키지의 `sfdisk` 옆이고, 오른쪽은 `/usr/bin`(PATH가 `/usr/local/bin:/usr/bin:/bin`, 층 7의 다른 셋과 같은
까닭). 새 공용 라이브러리 사슬은 libmount 하나다(기준의 "함께 보는 것" 둘째 — 그 사실을 여기 적는다).

### 결정 3 — 게이트: tools 체인 검사 하나

`tools/check.sh`의 검사 1은 목록을 되읽어 initrd에 두 파일이 든 것을 자동으로 본다. 게스트에서 도는지는 새 검사 하나(29)가 본다 —
`/tmp`(RAM)의 파일 이미지에 `sfdisk`로 GPT 한 칸을 만들고, `fdisk -l`이 그 표를 읽고, `cfdisk`가 화면을 그린 뒤 `q`로 셸에 돌아온다.
디스크를 붙이지 않는다 — fdisk 셋은 일반 파일도 디스크처럼 다룬다. 못 찾은 이름은 맨 뒤의 검사 19(음성 확인)가 함께 잡는다.

### 결정 4 — 안내

`docs/help/config.md`에 "디스크와 파티션" 절 — 두 명령의 한 줄씩, 그리고 TARS가 자기 파티션을 GPT 이름(`TARS-BOOT` · `TARS-CONFIG` ·
`TARS-HOME`)으로 찾으므로 그 셋의 이름을 바꾸거나 지우면 갱신 설치가 다르게 판단한다는 경고(DB design 결정 4).

## 비목표

1. gdisk · cgdisk · parted(결정 1).
2. `lsblk` · `blkid` · `wipefs` · `e2fsck` · `resize2fs` — 파티션을 만드는 것과 별개의 질문이다. 필요해지면 따로.
3. 파일 시스템 크기 조절 · 파티션 옮기기. cfdisk의 Resize는 표의 숫자만 바꾼다.
4. 개발 도구 층의 최신판 — initrd의 trixie 판으로 충분하다(util-linux 2.41).

## 위험

1. cfdisk의 화면이 TARS 터미널(xterm-256color, lib-vt)에서 깨질 수 있다. htop · btop · alsamixer가 같은 ncurses로 서 있으므로 낮다고 보고,
   검사 29가 화면 글자를 본다.
2. libmount가 끌고 오는 사슬이 생각보다 길 수 있다 — PT-M0이 initrd 크기를 앞뒤로 재어 적는다.
