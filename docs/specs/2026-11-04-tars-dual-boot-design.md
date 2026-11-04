# TARS Dual Boot — Design

접두사: DB

Status: 닫힘(2026-11-05) — DB-M0 GPT 엔트리를 이름으로 읽기 · `--beside` · `--beside --wipe` · init 후보 126, `dualboot` 체인(포트 없음).

사용자의 요청(2026-11-04, MB design 머리의 인용)에서 "인스톨러 개선: 대상 디스크 고르기 beside macOS partition (or volume), dual
booting 가능해야 해"를 받는다.

관련 문서: DI design(`2026-09-19-tars-disk-install-design.md` — 설치는 디스크 통째, 표지 `tars.installed`), DC design(설치된 부팅의
기다림), KU design(ESP의 슬롯 둘과 회전), HP design(p3 `/home`, 768 + 256MiB + 나머지, 최소 4GiB), MB design(맥 기종).

## 한 줄 요약

`tars-install <disk> --beside`가 디스크의 기존 파티션을 한 바이트도 안 건드리고 가장 큰 빈 공간에 TARS-BOOT · TARS-CONFIG · TARS-HOME을
덧붙인다. 설치기와 init이 TARS 파티션을 번호(p1~p3)가 아니라 GPT 파티션 이름으로 찾는다. 맥에서는 전원을 켤 때 Option 키를 쥐고 "EFI
Boot"를 고른다 — 기본 부팅은 macOS 그대로다.

## 착수 전에 확인한 것 (2026-11-04, `2ea12b8` 위)

1. 설치기는 디스크를 통째로 쓴다. `disk.SFDISK_SCRIPT`(`label: gpt` + 셋)를 `sfdisk --wipe always --wipe-partitions always <disk>`에
   먹인다. 설치 여부(`install.isInstalled`)와 갱신(`readSlots(p1)`)과 새 설치의 포맷은 전부 `storage.partitionName(disk, 1|2|3)`이다.
2. init의 설정 · 홈 후보는 디스크 열넷과 각 디스크의 첫 세 파티션이다(`storage.CANDIDATES = DISKS ++ PARTITIONS`, `tars.installed`일
   때만). 라벨(`tars-` 접두사 · `tars-home`)로 고르므로 번호는 후보 목록의 범위만 정한다.
3. GPT 파티션 이름은 DI-M1(2026-09-23)부터 `TARS-BOOT` · `TARS-CONFIG`, HP-M0(2026-11-02)부터 `TARS-HOME`이다. 지금 깔린 디스크는
   전부 이름을 갖고 있다.
4. ESP의 `limine.conf`는 `boot():/boot/bzImage`처럼 Limine이 뜬 볼륨을 기준으로 쓴다 — 파티션 번호가 conf에 없다.
5. 맥 디스크의 흔한 모양(GPT).
   | 기계 | 파티션 |
   |---|---|
   | APFS(10.13+) | p1 EFI 200MiB · p2 APFS 컨테이너 |
   | HFS+(MacBookAir4,1의 10.7~10.12) | p1 EFI · p2 HFS+ · p3 Recovery HD |
   | 위 + Boot Camp | 그 뒤에 BOOTCAMP(NTFS) 하나 |
   TARS는 p3~p5, p4~p6, p5~p7 중 하나에 놓인다.
6. Apple 펌웨어의 부팅 선택 화면(Option)은 FAT 볼륨의 `\EFI\BOOT\BOOTX64.EFI`를 "EFI Boot"로 보인다. TARS-BOOT가 그 파일을 갖고
   있다(DI). OVMF도 같은 removable 경로로 고른다.

## 결정

1. 플래그 `--beside`. `tars-install <disk> --beside [--yes] [--wipe]`. 없으면 지금 그대로(통째).
2. `--beside`는 GPT 디스크에서만 된다. 빈 디스크 · MBR · iso9660은 YES 전에 거절한다 — 통째 설치를 쓰라고 말한다.
3. 자리: GPT 엔트리에서 빈 구간(1MiB 정렬)을 모두 구하고 가장 큰 것을 고른다. 그 구간이 `disk.MIN_DISK_BYTES`(4GiB + 2MiB)보다
   작으면 YES 전에 거절한다. 거절 줄은 macOS에서 자리를 내는 명령을 함께 말한다(`diskutil apfs resizeContainer disk0s2 <크기>`).
4. 쓰는 법: `sfdisk --append --wipe-partitions always <disk>`에 세 줄을 넘긴다. 세 줄 모두 `start=` · `size=`를 섹터로 적는다 — 생략하면
   sfdisk가 첫 빈 자리를 고를 수 있어 우리가 고른 구간과 갈린다. `--wipe always`는 안 쓴다(디스크 머리의 서명을 지우는 옵션이다).
   크기는 통째 설치와 같다(768MiB · 256MiB · 구간의 나머지). 파티션 번호는 sfdisk가 비어 있는 엔트리에 매기므로, 쓴 뒤 GPT를 다시
   읽어 이름으로 번호를 찾는다.
5. TARS 파티션은 이름으로 찾는다. `disk.zig`에 GPT 엔트리를 읽는 순수 함수(이름 · 시작 · 끝 · 타입 GUID)를 두고 `disk_test`가 본다.
   `TARS-BOOT` · `TARS-CONFIG`가 있으면 설치된 디스크다(`TARS-HOME`은 있으면 쓴다). 통째 설치 디스크도 같은 길로 읽힌다 — 이름이
   p1~p3에 있을 뿐이다. 이름을 못 찾는 GPT는 설치되지 않은 디스크다.
6. 갱신은 지금과 같다 — TARS-BOOT만 쓴다. `--beside`가 있든 없든 설치된 디스크는 갱신이다.
7. `--beside --wipe`는 TARS 파티션 셋만 지우고(`sfdisk --delete`) 그 자리에 새로 놓는다. 다른 파티션은 안 건드린다. `--wipe`만 쓰면
   지금처럼 디스크 전체다 — 계획 줄이 지금 디스크에 있는 것(아래 결정 9)을 말한다.
8. init의 후보는 각 디스크의 첫 여덟 파티션으로 넓힌다(`PARTITIONS`). Boot Camp까지 있는 HFS+ 맥이 p7까지 쓴다. 고르는 것은 여전히
   라벨이다.
9. 목록과 계획은 GPT 디스크의 파티션을 말한다 — 타입 GUID로 macOS를 알아본다(APFS `7C3457EF-0000-11AA-AA11-00306543ECAC`, HFS+
   `48465300-0000-11AA-AA11-00306543ECAC`, EFI `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`). 상태 칸 예: `GPT: EFI, macOS (APFS); 40 GB free`.
   통째 설치의 계획이 macOS가 있는 디스크를 지운다고 말할 때 그 이름이 보이게 한다.
10. TARS-BOOT의 타입은 통째 설치와 같은 EFI System이다. macOS가 EFI 타입을 자동으로 붙이지 않으므로 Finder에 안 뜨고, Apple 펌웨어는
    FAT 볼륨이면 타입과 상관없이 고른다.
11. 부팅 기본값은 건드리지 않는다. NVRAM(`BootOrder`)도 `bless`도 안 쓴다. 매번 Option으로 고른다. TARS를 기본으로 하고 싶은 사람을 위한
    macOS 쪽 명령은 문서(`docs/guides/running-tars.md`)에 적는다.

## 게이트

새 체인 `dualboot/check.sh`(DB-M0). 호스트가 "맥 디스크"를 굽는다 — GPT, p1 FAT32 `EFI`(이름 `EFI System Partition`, `EFI/APPLE` 디렉터리만),
p2 APFS 타입 GUID에 정해진 무늬를 채운 1GiB, 나머지 빈 공간. OVMF로 판정한다.

1. ISO + 맥 디스크: 목록이 `macOS (APFS)`와 빈 자리를 말한다. `--beside --yes`가 설치한다.
2. 호스트가 p1 · p2의 바이트와 GPT 엔트리 1 · 2가 설치 전과 같은지 sha256으로 본다(이 서브프로젝트의 심장).
3. 디스크만으로 OVMF 부팅: TARS-BOOT에서 떴고(`tars.installed`), 설정을 p4에서 · 홈을 p5에서 붙였다.
4. ISO + 설치된 맥 디스크: 목록이 `TARS installed`, 갱신이 TARS-BOOT만 쓴다. p1 · p2는 여전히 같다.
5. 음성: 빈 자리가 4GiB보다 작은 맥 디스크에서 `--beside`가 YES 전에 거절하고 아무것도 안 바꾼다.
6. `--beside --wipe`가 TARS 셋만 다시 만든다(p1 · p2는 같다, 설정은 새것).

## 위험

1. 남의 디스크를 쓰는 일이다. 판정 2가 "안 건드렸다"를 바이트로 본다. 실기에서는 사용자가 먼저 Time Machine 백업을 해야 한다(문서에
   적는다).
2. 4Kn 디스크의 GPT(엔트리가 4096에서). DC-M2가 통째 설치에서 본 경우다. 순수 함수가 섹터 크기를 받는다.
3. Apple 펌웨어가 두 번째 EFI System 파티션을 어떻게 다루는지는 실기가 말한다. 안 보이면 타입을 Basic data로 바꾸는 것이 다음 수다.
4. macOS 업데이트가 GPT를 다시 쓰며 TARS 파티션을 지울 가능성. 알려진 사례는 Boot Camp가 아닌 파티션을 그대로 두는 쪽이다.

## 비목표

1. APFS · HFS+ 크기 줄이기. macOS의 `diskutil`이 한다.
2. Disk Utility가 만든 파티션(예: MS-DOS "TARS")을 골라 그 자리에 깔기. 지금은 빈 자리만 받는다 — 그 파티션을 지우면 빈 자리가 된다.
3. 부팅 관리자(rEFInd 등) · 기본 부팅 바꾸기.
4. Windows(Boot Camp) 옆, 다른 Linux 옆 — 같은 길로 될 것이지만 판정은 macOS 모양 하나다.

## Milestone

- DB-M0 — GPT 엔트리 읽기 · 이름으로 찾기 · `--beside` · `--beside --wipe` · init 후보 여덟, `dualboot` 체인.
