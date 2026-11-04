# DB-M0 — macOS 옆에 깔기, 이름으로 찾기

> 구현 파일은 서브에이전트가 `db` worktree에 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `ec94555` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: DB design의 M0 전부. GPT 엔트리를 읽는 순수 함수, 설치기와 init이 TARS 파티션을 번호가 아니라 GPT 이름으로 찾기,
`tars-install <disk> --beside [--yes] [--wipe]`, init 후보를 디스크마다 첫 여덟 파티션으로, 새 체인 `dualboot`(DB-M0).
통째 설치는 글자 한 줄 안 바뀌고 같은 길(이름으로 찾기)을 지난다 — `install` · `home` 체인이 그것을 본다.

Architecture: 순수한 쪽은 `disk.zig`의 새 절 "GPT 엔트리 (DB-M0)" — `parseGpt` · `largestGap` · `freeNumbers` · `besideLayout` ·
`appendScript` · `gptText` · `roomRefusal` · `besideLines`. 시스템 콜 쪽은 `install.zig`의 `readGpt`(앞머리 + sysfs 섹터 크기) ·
`isInstalled` · `settingsOn` · `headText` · `install`의 `beside_new` 갈래 · `besidePartitions` · `nodeAt`. init은 `storage.PARTITIONS`가
112개로 는 것뿐이다(판정은 그대로 라벨).

## 착수 전에 확인한 것 (2026-11-04, `ec94555`)

1. 게이트 컨테이너(aarch64)에는 `sfdisk` · `mkfs.fat` · `python3`이 없다. 게스트의 `sfdisk`는 amd64 sysroot의 util-linux
   2.41.5다(`/usr/local/amd64-sysroot/usr/share/doc/util-linux/changelog.Debian.gz`). 그래서 호스트가 맥 디스크의 GPT를 손으로
   써야 한다 — perl(`Compress::Zlib::crc32`)이 있다. `mformat -i img@@1M -F -T 409600`이 오프셋의 FAT32를 굽는다(0.01초).
2. 체인 밖의 실험 자리: Docker Desktop의 amd64 에뮬레이션(`docker run --platform linux/amd64 debian:trixie`)에 sysroot의 `sfdisk`와
   라이브러리 아홉을 붙이면 2.41.5가 돈다. 체인에는 안 쓴다(CI의 바탕이 다를 수 있다) — 바이트를 받아 오는 데만 썼다.
3. 그 sfdisk로 `dualboot/mac_gpt.pl`이 쓴 7GiB 맥 디스크를 봤다.
   - `sfdisk -V`: `No errors detected`. `-F`: 빈 자리 2508800~14680030(5.8GiB). perl의 GPT가 규격대로다.
   - `--append --wipe never --wipe-partitions always`에 `start=` · `size=`를 적은 세 줄 → p3 · p4 · p5(비어 있는 첫 엔트리 셋).
     엔트리 1 · 2의 바이트는 그대로다.
   - 남의 자리와 겹치는 `start=2506752`: `Sector 2506752 already used.` · `Failed to add #3 partition` · 종료 1, 표는 그대로.
     우리 셈이 틀려도 sfdisk가 마지막 문이다.
   - `sfdisk --delete <img> 3 4 5`: 종료 0, 엔트리 1 · 2만 남는다.
   - append 뒤의 LBA 1 앞 92바이트와 LBA 2의 엔트리 다섯을 `disk_test` 검사 22의 `REAL_HEADER` · `REAL_ENTRIES`로 옮겼다.
4. `HEAD_BYTES`(34816) 안에 엔트리 128개가 든다 — 512바이트 섹터면 1024~17408, 4Kn이면 8192~24576.
5. init이 설정 · 홈을 붙일 때 찍는 줄은 `tars-init: config storage <node> (label tars-config)` · `tars-init: home storage <node>
   (label tars-home)`. 체인이 이 둘로 p4 · p5를 본다.
6. 체인 포트: 이 체인은 키를 안 보내고(시리얼 FIFO) `-monitor none`이라 포트를 안 쓴다. 45503은 안 썼다.

## 확정 (design을 코드로 옮기며 정한 것)

1. `--wipe never`를 명시한다(design 결정 4는 "`--wipe always`를 안 쓴다"까지). sfdisk의 기본 `auto`가 append에서 머리를 안 지우는
   것은 맞지만 기본값에 기대지 않는다.
2. GPT는 CRC가 둘 다 맞아야 읽는다(헤더 · 엔트리). 안 맞으면 커널과 sfdisk는 백업을 믿으므로 우리가 본 엔트리와 갈린다. 엔트리가
   `first_usable..last_usable` 밖이거나, 엔트리 크기가 128이 아니거나, 엔트리 배열이 앞머리 밖이면 null — `--beside`는 "cannot
   read the GPT partition entries"로 거절, 목록은 `foreign (gpt)` 그대로.
3. 섹터 크기는 `/sys/block/<disk>/queue/logical_block_size`에서 받는다(design 위험 2). `parseGpt(head, sector)`는 512 · 4096만 받는다.
4. 이름은 UTF-16LE 72바이트 전체가 같아야 한다(뒤는 0). `TARS-BOOTX`는 TARS가 아니다. 같은 이름이 둘이면 `find`가 null이다 — 설치된
   디스크로 안 보이고, `--beside`는 "TARS partitions that are not a whole install"로 거절, `--beside --wipe`만 받는다(TARS 이름 전부를
   지운다, 셋을 넘으면 거절).
5. 빈 자리는 시작을 1MiB 위로, 끝을 1MiB 아래로 맞춘 뒤 가장 큰 것. `--beside --wipe`는 TARS 이름의 셋을 없는 것으로 치고 고른다.
   번호는 sfdisk처럼 비어 있는 첫 엔트리 셋으로 미리 말한다(계획 줄). 실제 번호는 sfdisk 뒤에 GPT를 다시 읽어 이름으로 찾는다.
6. sfdisk 뒤 포맷 전에 두 겹을 더 본다. (a) 다시 읽은 GPT의 세 파티션이 계획한 start · size와 같은가(`--beside`). (b) 커널의 노드가
   그 자리인가 — `/sys/block/<disk>/<part>/start`(512 단위)가 GPT의 first × 섹터와 같은가(통째 설치도). 커널이 표를 다시 못 읽었으면
   노드는 옛 표의 것이고 거기 mkfs를 하면 남의 파티션을 지운다. 어긋나면 "nothing was formatted"로 멈춘다.
7. 상태 칸. 읽히는 GPT면 `GPT: <이름들>; <빈 자리> free`. 이름은 번호 순 — EFI · `macOS (APFS)` · `macOS (HFS+)`, TARS 이름의 셋은
   `TARS` 하나, 나머지는 끝에 `N other`. 파티션이 없으면 `no partitions`, 빈 자리가 1MiB도 없으면 `no free space`. `install` 체인 판정
   4a · 4d의 `foreign (gpt)`는 `GPT: no partitions; [0-9]+ MB free`로 바뀌었다(4Kn 게스트에서 `parseGpt(…, 4096)`이 도는 자리가 됐다).
8. 통째 설치의 계획은 설치된 디스크여도 `TARS installed`가 아니라 그 안의 GPT를 말한다(design 결정 7) — macOS 옆에 깐 디스크에
   `--wipe`만 주면 `it now holds: GPT: EFI, macOS (APFS), TARS; …`가 보인다. 갱신 계획은 번호를 이름에서 받고(`p3 will be updated,
   p4 (your settings) is kept.`), TARS 아닌 파티션이 있으면 다시 까는 길로 `--beside --wipe`를 말한다. 통째 설치의 글자는 그대로다.
9. `roomLines`는 TARS-BOOT의 번호를 받는다(`p3 has … bytes free`). 통째 설치는 `p1` 그대로.
10. 쓰는 법에 한 줄 — `tars-install <disk> --beside  keep what <disk> has; install into its largest free space`. 마지막 줄(`--wipe`)이
    체인들의 `LIST_END`라 그 앞에 넣었다.
11. 자리 거절은 두 줄(`Complain`): `the largest free space on <disk> is <N GB>; TARS needs more than 4 GiB; nothing was changed.` ·
    `make room in macOS first: diskutil apfs resizeContainer disk0s2 <smaller size> (see diskutil list)`. HFS+ 타입이 있으면
    `diskutil resizeVolume`이다.
12. init 후보 126(디스크 14 + 파티션 112). `storage_test` 검사 10이 9배와 규칙을 본다. 체인들은 후보 수를 글자로 안 본다
    (`rg 'among (42|56)'` 0건).
13. 체인의 맥 디스크는 무늬를 채운다 — p1의 `EFI/APPLE/filler` 150MiB(`tars-db-esp-filler` 반복), p2 1GiB 전부
    (`tars-db-apfs-pattern` 반복). 0인 자리에 0을 쓰는 사고(서명 지우기)는 해시를 안 바꾸기 때문이다.

## Task

1. `disk.zig` — 위 순수 함수, `Command.install.beside`, `parseArgs`(인자 넷까지), `usageLines`, `planLines`(settings_on · nums ·
   beside), `roomLines`(esp 번호). `disk_test` — 검사 4에 `--beside`, 16 · 18 · 20의 새 인자, 검사 22(진짜 sfdisk 바이트: 엔트리 다섯,
   GUID 순서, CRC 둘, 4Kn, 맥 디스크, 가운데 파티션, 범위 밖, 같은 이름 둘), 23(경계 · 거절 줄 · 계획 · `SFDISK_SCRIPT`의 이름).
2. `install.zig` — 이름으로 찾기(`isInstalled` · `settingsOn` · 갱신 · 새 설치 뒤), `--beside`(YES 전 판단 · `besidePartitions` ·
   `nodeAt`), 상태 칸(`headText`).
3. `storage.zig` 여덟, `storage_test` 검사 10, `main.zig` 주석의 수.
4. `dualboot/mac_gpt.pl` · `dualboot/check.sh`, 루트 `check.sh`의 `CHAINS`에 `DB-M0:./dualboot/check.sh`.
5. `install/check.sh` 판정 4a · 4d의 글자(확정 7).
6. `docs/guides/running-tars.md` — "macOS 옆에 설치하기 — 맥에서 듀얼 부팅", 목록 예의 상태 칸, 쓰는 법 줄, "안 되는 것".

## 결과

### 단위 검사

컨테이너 `zig build test` 초록. `disk_test: GPT entries as sfdisk writes them (512 and 4Kn), names, the largest free space and the beside
plan hold` · `storage_test: … (126 candidates)`. 첫 판은 `guidBytes`가 `comptime { … return }`이라 컴파일이 안 됐다(런타임에서 부른
함수가 comptime 블록에서 값을 돌려줄 수 없다) — `return comptime blk: { … }`로 고쳤다.

### `dualboot` 체인

PASS. 최종 판(mutation 뒤 `fail` 보강 · 부팅 1 목록 판정 뺌) 217초, 그 앞 판 233초 — 빌드 단계는 스탬프로 넘어가고 ISO만 다시
굽는다. 부팅 넷의 콘솔 셸까지 10~13초.

| 판정 | 증거 줄 |
|---|---|
| 1 목록 | `/dev/nvme0n1 7 GB … internal GPT: EFI, macOS (APFS); 6 GB free`, 작은 맥은 `1 GB free` |
| 1 통째 계획 | `will be erased. it now holds: GPT: EFI, macOS (APFS); 6 GB free`, `no`로 멈춤 |
| 1 설치 | `TARS goes into the free space from MiB 1225 to MiB 7167` · `formatting /dev/nvme0n1p3 (FAT32, TARS-BOOT)` · p4 ext2 · p5 ext4 · `done.` (목록의 `TARS installed`는 부팅 3) |
| 2 바이트 | 부팅마다 `p1, p2 and GPT entries 1-2 are byte for byte as built` (네 번) |
| 3 디스크만 | cmdline에 `tars.installed`, `config storage /dev/nvme0n1p4 (label tars-config)`, `home storage /dev/nvme0n1p5 (label tars-home)`, `user tars uid 1000` |
| 4 갱신 | `already has TARS. p3 will be updated, p4 (your settings) is kept.` · `p3 has 671367168 bytes free` · 게스트 안 `sha256sum /dev/nvme0n1p4`가 갱신 앞뒤 같다 |
| 5 음성 | `the largest free space on /dev/nvme1n1 is 1 GB; …` · `diskutil apfs resizeContainer disk0s2` · 빈 디스크 `--beside needs a GPT disk; /dev/nvme2n1 holds blank.` · 두 디스크 통째 sha256이 그대로 |
| 6 다시 깔기 | `the TARS partitions are erased first …: p3 p4 p5` · `deleting the TARS partitions p3 p4 p5` · 부팅 4에 마커가 없고 여전히 p4 · p5 |

단계 시간(체인의 `time_steps`, 0.1초 단위, TCG):

| 단계 | `--beside` | `--beside --wipe` |
|---|---|---|
| 계획 → 파티션 줄(mkpasswd yescrypt) | 2.0초 | 1.7초 |
| sfdisk `--delete` | — | 0.4초 |
| sfdisk `--append` + 다시 읽기 + 노드 대기 | 0.7초 | 0.3초 |
| mkfs.vfat · mke2fs ext2 | 0.1초 · 0.1초 | 둘이 0.2초 |
| mke2fs ext4 + 계정 | 0.1초 | (아래 줄에 든다) |
| 복사 + sync | 1.5초 | ext4 + 계정까지 1.2초 |

첫 판의 실패 둘(둘 다 체인 쪽): `yes | head`가 pipefail 아래 141로 체인을 말없이 끝냈다(rc 141, 판정 전) — 그 두 줄만 `set +o
pipefail` subshell. `grep -aqF "$want"`의 `$want`가 `--beside`로 시작해 grep 옵션으로 읽혔다 — `--`를 붙였다.

### 다시 돈 체인

- `install`(DC-M2) PASS 288초. 4a의 4Kn 디스크가 `GPT: no partitions; … MB free`로 읽혔다 — 게스트에서 `parseGpt(…, 4096)`이 진짜
  sfdisk의 4Kn 표를 읽은 첫 자리다. 갱신 · `--wipe` · 늦은 USB(1100ms)가 전과 같다.
- `home`(HP-M2) PASS 213초. `config storage /dev/nvme0n1p2` · `home storage /dev/nvme0n1p3`, 남의 `debian-home`은 그대로.
- 진입 검사(빌드 스텝 넷 · `EARLY_EXIT_PIPE` · `-nic none`)를 `dualboot/check.sh`에 따로 돌려 통과. 루트 게이트는 lead 몫이다.

### mutation

한 번에 하나씩 넣고 `dualboot`만 돌린 뒤 되돌렸다(`shasum -c`로 원본과 같은지 확인).

| | 망가뜨린 것 | 결과 |
|---|---|---|
| a1 | `--append`에 `--wipe never` 대신 `--wipe always` | 안 잡혔다(PASS 230초). 아래 |
| a2 | TARS-CONFIG의 노드를 이름이 아니라 번호 2로(옛 코드의 모양) + `nodeAt` 끔 | 잡혔다. mke2fs가 APFS(p2)에 돌았고 단계 줄(`formatting /dev/nvme0n1p2`)이 먼저 빨갰고, `fail`이 `FAIL: and the Mac partitions changed:`(p2 59d255… ≠ 93ad1d…)를 덧붙였다 |
| a3 | a2에서 `nodeAt`만 켬 | 잡혔다, 포맷 전에. `the kernel has /dev/nvme0n1p2 at byte 210763776, the GPT says 2089811968; nothing was formatted` |
| b | init 후보를 디스크마다 첫 셋으로 | 잡혔다. 부팅 1은 초록(바이트 그대로), 부팅 2가 `no disk labelled tars-* among 56 candidates` · `config storage /dev/nvme0n1p4`가 없다 |

a1이 안 잡힌 까닭. `--wipe always`는 디스크 장치에서 libblkid가 찾은 서명을 지운다. GPT 디스크에서 장치 수준의 서명은 파티션 표
(보호 MBR의 55 AA · `EFI PART`)뿐이고 — 파티션 안의 파일시스템은 장치 수준 탐색에 안 걸린다 — sfdisk는 그 표를 곧바로 다시 쓴다.
그래서 p1 · p2와 엔트리 1 · 2의 바이트가 그대로였다. 실기에서 해가 없다는 뜻이지 쓸 이유가 생긴 것은 아니다 — 확정 1(`--wipe never`)은
그대로 둔다. 바이트 판정이 볼 수 있는 "p2를 쓰는 사고"는 a2가 증명했다.

a2를 처음 돌렸을 때는 `fail`이 단계 줄에서 끝나 바이트가 어떤지 안 찍혔다. 그래서 `fail`이 어느 판정에서 멈추든 QEMU를 끄고 맥의
해시를 비교해 한 줄을 더하게 했다. 그리고 부팅 1의 `TARS installed` 목록 판정을 뺐다 — 부팅 3이 같은 것을 보고, 설치 뒤 첫 판정이
바이트여야 p2에 쓰는 사고가 이 판정에 먼저 걸린다.

### 숫자

- 체인 217초(최종 판). 부팅 넷이 콘솔 셸까지 10~13초, 나머지는 해시(맥 디스크 1.2GiB를 다섯 번, 약 1초씩)와 단계다.
- 맥 디스크 굽기: perl GPT · mformat · mcopy 150MiB · p2 1GiB 무늬 합쳐 약 2초(호스트).
- 게스트 sha256 256MiB(p4) — 판정 4의 두 번이 각각 수 초 안이었다(wait_re 120초 상한 안).

## design과 달라진 것

없다 — 확정 1(`--wipe never` 명시)은 결정 4를 좁힌 것이고, 확정 7의 `no partitions` · `no free space` · `N other`는 결정 9의 예를
채운 것이다. design은 고치지 않았다.

## 남은 것

- 실기. Apple 펌웨어가 두 번째 EFI System 파티션을 Option 화면에 "EFI Boot"로 보이는지(design 위험 3)는 게이트가 못 본다.
- 4Kn 맥 디스크의 `--beside` 끝까지는 단위 검사(검사 22 · 23)뿐이다. 게스트의 4Kn은 `install` 4a의 목록까지다.
- HFS+ 맥(Recovery HD가 p3)의 모양은 체인이 안 본다 — 체인은 APFS 모양 하나다(design 비목표 4와 같은 선). 거절 줄의
  `resizeVolume` 갈래(HFS+ 타입이 있을 때)는 단위 검사도 없다.
