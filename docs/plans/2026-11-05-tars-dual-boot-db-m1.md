# DB-M1 — macOS가 만든 파티션을 골라 그 자리에 깔기

> 구현은 lead가 직접 넣었다(2026-11-05, 사용자 "continue"). 줄 번호는 `d1fa10a` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로
> 다시 찾는다. 결과는 끝의 "결과" 절.

Goal: DB design 비목표 2(Disk Utility가 만든 파티션을 골라 그 자리에 깔기)를 푼다. `tars-install`의 목록이 GPT 디스크의 파티션을 한
줄씩 보이고, `tars-install /dev/sda3`처럼 파티션을 지정하면 그 파티션(과 바로 붙은 빈 자리)을 지우고 TARS 셋을 놓는다. 다른 파티션은
DB-M0과 같이 한 바이트도 안 건드린다.

## 사용자 요청과 검토 (2026-11-05)

요청: "macOS의 diskutil로 파티션을 나눌 때 format을 같이 하기 때문에 새 할당 영역이 free가 아니게 됩니다. 논리 파티션을 지정할 수
있어야 할 듯 합니다. tars-install의 디스크 정보는 전체 디스크만 검토하기 때문에 세부 파티션까지 조회하여 설치하는 기능이 필요합니다."

이 Mac의 `diskutil`(usage 글)로 확인한 것.

1. `diskutil apfs resizeContainer <disk> <size>`는 triple을 생략하면 "the partition map's free space gap"을 남긴다. `resizeVolume`(HFS+)도
   새 파티션은 "optionally"다. 그러니 크기만 주면 빈 자리가 생기고, 포맷이 되는 것은 triple을 붙였거나 디스크 유틸리티의 "파티션"
   버튼을 쓴 경우다. 진단은 반만 맞다.
2. `diskutil eraseVolume free free disk0s3`가 파티션을 지워 빈 자리로 돌린다("pseudo-format of free"). 지금 0.1.4로도 우회가 된다 —
   `running-tars.md`의 macOS 절 2번에 넣었다(이 plan과 같은 커밋).
3. GPT에는 "논리 파티션"(MBR의 확장 파티션 안쪽)이 없다. 여기서는 "기존 파티션 지정"이라 부른다.
4. 목록은 이미 GPT를 읽어 요약한다(`GPT: EFI, macOS (APFS), 1 other; 0 B free`, `disk.gptText`). 파티션 한 줄씩은 없고, 지정할 길도
   없다 — 이 둘이 이번 일이다.

그래도 할 가치: 맥 사용자는 디스크 유틸리티 GUI로 나누는 것이 보통이고, 그 길은 늘 포맷된 파티션을 남긴다. 터미널 명령 하나를 더
치게 하는 것보다 설치기가 그 파티션을 받는 것이 덜 틀린다.

## 결정 (design에 12~16으로 더한다)

12. 지정은 파티션 노드로 한다 — `tars-install /dev/sda3 [--yes]`. 새 플래그는 없다. `/dev/nvme0n1p3` · `/dev/mmcblk0p3`도 같다.
    sysfs(`/sys/class/block/<name>/partition`과 부모 디렉터리)로 디스크와 번호를 얻는다. 파티션 노드에 `--beside` · `--wipe`를 붙이면
    거절한다(뜻이 겹친다).
13. 받는 파티션은 셋뿐이다 — Microsoft Basic Data 타입(`EBD0A0A2-B9E5-4433-87C0-68B6B72699C7`, 디스크 유틸리티의 MS-DOS(FAT) ·
    ExFAT)이면서 머리가 FAT12/16/32 · exFAT인 것, 그리고 머리에 아무 서명도 없는 것. 나머지는 YES 전에 거절하고 이유를 말한다 —
    EFI(펌웨어), APFS · HFS+(macOS일 수 있다, 빈 APFS 컨테이너인지 가리려면 APFS를 읽어야 해서 안 한다), Apple Boot(Recovery),
    NTFS(Boot Camp의 Windows), TARS 이름(`--beside --wipe`로). APFS · HFS+를 거절하는 줄은 `diskutil eraseVolume free free <id>`를 말한다.
14. 자리 = 그 파티션의 구간 + 바로 앞뒤에 붙은 빈 구간(1MiB 정렬). `disk.MIN_DISK_BYTES`보다 작으면 거절. 디스크의 다른 빈 자리는
    안 쓴다 — 사람이 고른 곳에 깐다.
15. 쓰는 법은 DB-M0의 `--beside --wipe`와 같다 — `sfdisk --delete <disk> <N>` 뒤 `--append`로 세 줄. `besidePartitions`의 `wipe_nums`에
    N 하나를 넘기면 된다. 계획 줄은 지울 파티션의 이름 · 파일시스템 · 라벨 · 크기를 말한다(`/dev/sda3 (FAT32 "TARS", 50 GB) will be
    erased; the other partitions are kept`).
16. 목록은 GPT 디스크 밑에 파티션 줄을 단다. 지금의 디스크 줄은 그대로 두고(체인들이 읽는다), 들여 쓴 줄을 더한다.

    ```
    /dev/sda        251 GB  APPLE SSD SM256E   internal   GPT: EFI, macOS (APFS), 1 other; 0 B free
      /dev/sda1     210 MB  EFI
      /dev/sda2     200 GB  macOS (APFS)
      /dev/sda3      50 GB  FAT32 "TARS"       tars-install /dev/sda3 takes it
    ```

    `--beside`의 자리 거절 줄도 받을 수 있는 파티션이 있으면 그 명령을 함께 말한다.

## 할 일

1. `disk.zig`(순수, `disk_test`가 본다)
   - `PartKind`에 `basic` · `apple_boot` · `linux`를 더하고 타입 GUID 표를 넓힌다.
   - `partitionArg(name)` — `sda3` · `nvme0n1p3` · `mmcblk0p3`를 디스크 이름과 번호로(sysfs가 없을 때의 대조용, 실제는 sysfs).
   - `fsOf(head)` — 파티션 머리 4KiB로 FAT12/16/32 · exFAT · NTFS · ext · HFS+ · APFS(`NXSB`) · 서명 없음을 가린다. 라벨도.
   - `takeable(part, fs)` — 결정 13의 표. 거절 이유를 enum으로.
   - `gapAround(g, n)` — 결정 14의 구간.
   - `partRow(sink, …)` · `takeLines(sink, …)` · 거절 줄들.
   - 검사: 맥 모양 셋(APFS · HFS+ + Recovery · Boot Camp)에 FAT32 · exFAT · NTFS · 빈 파티션을 섞은 GPT 바이트, 4Kn 하나.
2. `install.zig`
   - `parseArgs`가 파티션 노드를 받는다(`install.part: ?u8`).
   - `list`가 GPT 디스크마다 파티션 줄을 단다(파티션 머리는 노드를 열어 4KiB).
   - `install`에 `take` 갈래 — `beside_new`와 같은 길을 `gap = gapAround`, `wipe_nums = [N]`으로 탄다. 포맷 전 대조 둘(DB-M0)은
     그대로 지난다.
3. 체인 `dualboot/check.sh`에 판정을 더한다(포트 없음 그대로).
   7. 맥 디스크 둘째 모양 — p1 EFI · p2 APFS 무늬 1GiB · p3 FAT32 `TARS` 5GiB(`mformat`), 빈 자리 없음. 목록에 `/dev/sda3` 줄과
      `takes it`.
   8. `tars-install /dev/sda --beside`가 거절하고 `tars-install /dev/sda3`을 말한다.
   9. `tars-install /dev/sda3 --yes`가 깐다. p1 · p2와 엔트리 1 · 2의 sha256이 설치 전과 같다. 디스크만으로 OVMF 부팅 —
      설정 · 홈을 p4 · p5(또는 sfdisk가 매긴 번호)에서 붙인다.
   10. 음성 — `/dev/sda2`(APFS) · `/dev/sda1`(EFI) · NTFS 무늬 파티션 · 4GiB보다 작은 FAT를 각각 거절하고 디스크가 그대로다.
4. 문서 — `running-tars.md` macOS 절의 2 · 5 · 6번(GUI로 나눈 경우), DB design 비목표 2를 지우고 결정 12~16, `Status:`.

## 위험

1. 남의 파티션을 지운다. 사람이 고른 노드 하나만, 받는 타입을 좁게, 계획 줄이 라벨 · 크기를 말하고 `YES`를 받는다. 판정 9가 나머지를
   바이트로 본다.
2. 디스크 유틸리티가 FAT 파티션을 만들 때 앞뒤에 128MiB쯤 빈 자리를 두는 일이 있다(Apple의 파티션 사이 여유). 결정 14가 그것을
   붙여 쓴다 — 실기 디스크의 실제 모양은 사용자의 `diskutil list`가 말한다.
3. exFAT은 Boot Camp가 아닌 사람의 데이터 볼륨일 수 있다. 라벨을 보이는 것으로 막는다(더 막을 일인지는 실기 뒤에).

## 비목표

- APFS 컨테이너 안의 빈 볼륨을 알아보기, 파티션 크기 줄이기, MBR 디스크의 파티션 지정.

## 결과 (2026-11-05)

- `zig build test`(컨테이너) 초록 — `disk_test` 검사 24(노드 이름 · 서명 아홉 · 받는 표 · GUI 맥의 구간 1225~7936MiB와 번호
  3 · 5 · 6 · 문장 셋). `make quick` 초록.
- 계획에서 바뀐 것
  - 노드 → 디스크 · 번호는 sysfs가 아니라 순수 함수 `disk.splitPartition`이다. `storage.partitionName`으로 이름을 지어 맞추므로
    init이 찾는 이름과 같은 규칙이고 `disk_test`가 본다.
  - GUI 맥의 빈 자리는 "없음"이 아니라 p2 뒤의 128MiB 틈(`134 MB free`)이다. `--beside`는 그 크기로 거절하고 p3을 말한다.
  - 판정 10의 작은 FAT(4GiB 미만) 거절은 체인이 아니라 `disk_test`가 본다(GUI 맥의 p4 구간이 256MiB라 `besideLayout`이 null).
- 지나가며 고친 것: `make quick`의 shellcheck 경고 둘(DB-M0의 `make_mac` SC2015, HS의 `hidpi` SC2054)은 이번 변경 전부터 있었다.
- 첫 판의 빨강 — 부팅 5가 UEFI Shell로 떨어졌다. GUI 맥의 p3은 `TARS-BOOT`로 포맷만 되고 비어 있었다. 체인의 `time_steps`가
  마지막 줄 `tars-install: done.`을 로그 전체에서 찾는데, 같은 부팅의 1c 설치가 이미 그 줄을 찍어 두어 p6 포맷 직후 끝난 것으로 읽혔고,
  `stop_guest`가 ESP 복사 중의 QEMU를 껐다. 명령 뒤의 표지 `db-take-finished`를 마지막으로 기다리고 `done.`이 두 번인지 본다.
  설치기의 결함은 아니다 — 같은 부팅에서 설치를 두 번 하는 체인이 처음이었다.
