# TARS Disk Install Carryover — Design

접두사: DC

Status: M0 끝(2026-09-25). M1이 다음이다.

관련 문서: `2026-09-19-tars-disk-install-design.md`(DI. 이 서브프로젝트가 받는
이월 여섯이 그 문서의 실측 15와 19에 있다. 아래에서 "DI 결정 N"은 그 문서의
것이다) · `2026-09-09-tars-real-machine-design.md`(RM. `init`의 설정 디스크
훑기를 세웠다) · HD design(키보드를 한정해 기다리는 `findKeyboardWaiting`).

## 한 줄 요약

설치된 디스크로 뜬 기계에서, 커널이 설정 파티션을 PID 1보다 늦게 만들어도
`init`이 그것을 찾는다. 그 뒤에 DI가 남긴 작은 것 다섯을 치운다.

## 왜 지금인가

DI가 2026-09-24에 닫히며 이월 여섯을 남겼다. 2026-09-25에 사용자가 그 목록을
보고 "1번부터 순서대로"를 골랐다. 1번은 HANDOFF가 "실기에서 설정을 못 찾으면
먼저 의심할 자리"라고 적어 둔 것이고, 나머지 다섯은 `disk.zig`와 `install.zig`의
작은 결함이다.

1번은 원래 "`nvme0n1`은 보이는데 `p2`는 아직 없는 틈"으로 적혀 있었다. 이 문서를
쓰며 커널 소스를 읽어 보니 틈이 그보다 넓다(확인 2).

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — `init`은 후보를 한 번만 훑고 넘어간다

`main.zig`의 `mountConfig`는 `storage.findConfigDisk`를 한 번 부르고, 못 찾으면
`no disk labelled tars-* among N candidates`를 찍고 기본값으로 간다. 기다리는
코드는 `init`에 둘 있다 — `devices.zig`의 `findKeyboardWaiting`(3초, 25ms 간격,
HD-M2)과 `install.zig`의 `waitForNode`(3초, 100ms 간격, DI 위험 2). 설정 디스크를
찾는 길에는 없다.

### 확인 2 — 커널은 PID 1을 띄우기 전에 디스크를 기다려 주지 않는다

커널 6.18.42 소스에서 읽었다.

- `init/main.c:1439`의 `async_synchronize_full()`은 async 도메인에 올라간 일만
  기다린다.
- NVMe 드라이버는 `PROBE_PREFER_ASYNCHRONOUS`(`drivers/nvme/host/pci.c:4014`)라
  probe는 거기에 걸린다. 그런데 probe는 디스크를 만들지 않는다. 컨트롤러 리셋과
  namespace 스캔이 `nvme_wq` 워크큐에서 돈다(`core.c:164`의 `nvme_queue_scan`).
  워크큐는 async 도메인이 아니다.
- 그래서 실기에서는 `p2`만이 아니라 `nvme0n1` 자체가 PID 1보다 늦을 수 있다.
  디스크 노드는 `device_add`(`block/genhd.c:492`)에서, 파티션은 그 뒤
  `disk_scan_partitions`(`:412`)에서 생기므로 원래 적힌 좁은 틈도 있다.
- usb-storage는 장치를 붙이고 `delay_use`(기본 1초, `drivers/usb/storage/usb.c:71`)를
  기다린 뒤에 SCSI 스캔을 한다. USB 디스크는 한 번 훑는 방식에 사실상 늘 늦는다.

게이트에서 안 드러난 이유는 QEMU의 NVMe가 워크큐를 PID 1보다 먼저 끝낼 만큼
빨라서일 것이다. RM-M3이 USB 키보드에서 본 "스무 번에 한 번"과 같은 종류다.

### 확인 3 — 커널에 저장장치 드라이버가 전부 들어 있다

`kernel/.config`에 `BLK_DEV_NVME` · `SATA_AHCI` · `VIRTIO_BLK` · `USB_STORAGE` ·
`EFI_PARTITION`이 전부 `=y`다. 모듈을 싣는 순서 문제는 없고 순전히 "언제 노드가
생기나"의 문제다.

### 확인 4 — 470바이트는 인자 검사가 아니라 메시지 버퍼다

`install.zig:40-50`의 `say`와 `complain`이 512바이트 버퍼에 `bufPrint`하고 넘치면
`catch return`한다. 긴 인자를 되풀이하는 에러 줄은 통째로 사라지고 종료 코드만
남는다.

## 결정

### 결정 1 — `tars.installed`일 때만 기다린다 — 사용자가 골랐다

설치된 디스크로 떴다는 표지는 "p2가 반드시 있다"는 뜻이다. 그때 못 찾은 것은
"없다"가 아니라 "아직 없다"다. 표지가 없는 부팅(게이트의 `-kernel` 체인 · ISO로
뜬 설치 세션 · 디스크 없는 BF 체인)은 지금처럼 즉시 넘어간다.

고르지 않은 둘. 늘 기다리기는 디스크 없는 부팅마다 상한만큼 늦는다. 늦게 나타난
디스크를 나중에 붙이는 hotplug는 셸 · 자판 같은 설정이 이미 기본값으로 정해진
뒤라 반쪽이고 훨씬 크다.

### 결정 2 — 상한까지 100ms 간격으로 후보 전체를 다시 훑는다 — Claude가 정했다

모양은 `waitForNode`와 같다. 매번 마흔둘 전체를 다시 훑으므로 "먼저 찾은 것이
이긴다"는 지금의 규칙이 그대로다. 기다린 적이 있을 때만 한 줄을 더 찍는다
(`tars-init: config storage appeared after N ms`) — HD-M2의 규칙이다. 상한에
닿으면 지금과 같은 `no disk labelled` 줄로 떨어지고 부팅은 계속된다.

상한은 초안 5초다. 키보드의 3초보다 넉넉한 것은 NVMe 컨트롤러 리셋이 실기에서
초 단위일 수 있고, 설정을 못 찾는 대가(설정이 통째로 사라진 것처럼 보인다)가
키보드를 잘못 고르는 대가보다 커서다. M0의 실측이 이 값을 확정한다.

기다리는 함수는 상한을 인자로 받는다 — 호스트 검사가 초 단위로 자지 않게 하는
`findKeyboardWaiting`의 이유와 같다.

### 결정 3 — 틈은 `usb-storage.delay_use`로 벌려서 잰다 — Claude가 정했다

QEMU NVMe를 늦출 파라미터는 없다. 대신 usb-storage의 `delay_use`는 커널
cmdline으로 정할 수 있다. `-kernel` 부팅의 cmdline에 `tars.installed
usb-storage.delay_use=3`을 주고, p2에 `tars-` 라벨이 있는 GPT 디스크를
`usb-storage`로 붙이면 `/dev/sda2`가 PID 1보다 적어도 3초 늦게 생긴다.

`init`이 보는 것은 "후보 이름의 노드가 늦게 생긴다" 하나뿐이고 디스크 종류는
모른다. 그래서 USB로 잰 것이 NVMe의 틈도 증명한다.

### 결정 4 — 판정은 `install/check.sh`에 부팅 하나를 더한다 — Claude가 정했다

DI의 체인이고, 이미 GPT에 p2를 가진 디스크를 만드는 코드가 있다. 새 체인을
세우지 않는다. 판정은 `config storage /dev/sda2 (label tars-…)`와 `appeared
after`가 있는 것이다. 반사실은 기다림을 뺀 `init`이 `among 42 candidates`로
빨강이 되는 것이다.

### 결정 5 — 나머지 다섯은 M2 하나에서 순서대로 한다 — 사용자가 골랐다

DI 실측 15의 순서대로.

1. 4Kn GPT — `disk.zig`가 GPT 헤더를 512에서만 찾아 4096바이트 섹터 디스크를
   `foreign (mbr)`로 읽는다. 4096에서도 본다. QEMU의
   `logical_block_size=4096`으로 실제 디스크를 만들 수 있으면 체인이 보고, 아니면
   호스트 검사가 본다(plan에서 정한다).
2. 옛 ISO 서명 — ISO를 구웠다가 GPT로 다시 파티션한 스틱에 PVD가 남아
   `foreign (iso9660 TARS)`로 읽힐 수 있다. GPT가 있으면 GPT를 믿는 순서를
   정한다. 하이브리드 ISO 자신도 GPT를 갖고 있는지를 먼저 확인해야 하는
   결정이다 — plan이 `make_iso.sh`의 출력을 보고 정한다.
3. 긴 인자 — `say`/`complain`이 넘치면 앞부분을 잘라서라도 찍는다.
4. YES를 줄 단위로 — `read` 한 번이 줄을 쪼개 받거나 여러 줄을 받으면
   지금은 거절한다(안전한 쪽). 개행까지 모아 읽는다.
5. `disk_test`의 음성 둘 — PVD type 바이트가 틀린 볼륨, 32바이트를 꽉 채운
   볼륨 ID.

## 비목표

1. hotplug — 결정 1이 뺐다.
2. 표지 없는 부팅의 USB 설정 스틱 — 여전히 한 번만 훑으므로 `delay_use` 뒤에
   생기는 USB는 못 본다. 게이트의 디스크는 전부 virtio라 영향이 없다.
3. 갱신이 파일을 제자리에서 덮는 것(O_TRUNC) — DI 실측 19가 "같은 명령을 다시
   친다"로 닫았다.

## 위험

### 위험 1 — `delay_use`가 cmdline에서 안 먹을 수 있다

`module_param_cb`라 built-in이어도 `usb-storage.delay_use=`로 받아야 한다. 6.18은
값에 `ms` 접미사도 받는다(`delay_use_set`). 안 먹으면 M0이 그것부터 보여 준다 —
그때는 QEMU monitor의 `device_add`로 늦게 꽂는다.

### 위험 2 — 기다림이 정상 설치 부팅을 늦출 수 있다

기다림은 못 찾았을 때만 돈다. 설치된 기계에서 p2가 제때 있으면 첫 훑기에서
찾으므로 비용이 0이다. install 체인의 부팅 2·4·6이 그 증거가 된다(부팅 시간이
DI-M2의 6~7초에서 안 변해야 한다).

### 위험 3 — 부팅이 하나 늘어 게이트가 길어진다

USB 부팅은 `delay_use=3` 때문에 적어도 3초를 더 쓴다. 회차 셋이면 30초 안쪽이다.

## 마일스톤

- DC-M0 — 재기만 한다. 위 하네스로 틈을 재현하고, 늦춘 USB의 `sda2`와 지연 없는
  QEMU NVMe의 `nvme0n1p2`가 PID 1 기준 몇 ms에 생기는지 잰다. 상한을 확정한다.
- DC-M1 — 결정 1·2의 기다림과 결정 4의 부팅. 반사실을 돌린다.
- DC-M2 — 결정 5의 다섯.

## DC-M0이 실행으로 증명한 것

plan은 `docs/superpowers/plans/2026-09-25-tars-disk-carryover-dc-m0.md`다. 코드는
안 고쳤다. 하네스(`/tmp/dcm0/probe.sh`, 전문은 plan에)를 시제품으로 한 번, plan대로
한 번 돌렸고 두 판이 같은 모양이었다. 아래 수는 둘째 판이다.

### 실측 1 — 틈이 재현됐다

`-kernel` 부팅, cmdline에 `tars.installed`, 64MiB 디스크(MBR, p2가 라벨
`tars-dcm0`의 ext2)를 붙였다.

| 부팅 | 설정 노드 | `Run /init` | `init` |
|---|---|---|---|
| usb-storage, `delay_use=3` | `sda: sda1 sda2` 4.049초 | 2.327초 | `no disk labelled tars-* among 42 candidates` |
| usb-storage, 기본값(1초) | 1.805초 | 2.197초 | `config storage /dev/sda2` |
| nvme × 5 | `nvme0n1: p1 p2` 0.560~0.604초 | 2.272~2.328초 | `config storage /dev/nvme0n1p2` |

첫 줄이 이월 1번의 실물이다. 설정 파티션이 멀쩡히 있는데 `init`이 훑은 뒤
1.72초에 생겨서 기계가 기본값으로 떴다. 시제품 판은 1.69초였다. `Command line:`에
`usb-storage.delay_use=3`이 그대로 있고 `sda`가 그만큼 늦었으므로 위험 1(파라미터가
안 먹을 수 있다)은 닫혔다.

### 실측 2 — 틈을 덮던 것은 NVMe의 속도가 아니라 initramfs 풀기다

확인 2는 "QEMU의 NVMe가 빨라서"라고 추측했는데 틀렸다. `Run /init` 바로 앞에
`Freeing initrd memory: 41788K`가 2.285초에 있다. 커널이 42MB initramfs를 푸는
데 약 1.7초를 쓰고, `init`은 그 뒤에야 뜬다. NVMe(0.56초)도 기본값 USB(1.8초)도
그 사이에 다 붙는다.

게이트는 arm64 호스트 위의 x86 TCG라 이 풀기가 느리다. 실기의 네이티브 CPU에서는
훨씬 짧을 것이므로, 1초를 쉬는 USB는 거의 늘 늦고 느린 NVMe 컨트롤러도 늦을 수
있다. 게이트가 이 틈을 못 본 것은 틈이 없어서가 아니라 에뮬레이션이 느려서다 —
그래서 M1의 판정은 `delay_use`로 틈을 일부러 벌려야 한다(결정 3이 맞았다).

### 실측 3 — 상한은 5초로 확정한다

게이트에서 벌린 틈이 1.72초다. 결정 2의 5초는 그 세 배에 가깝고, 실기의 USB
(`delay_use` 1초 + 열거)와 느린 NVMe 리셋을 덮는다. M1의 판정이 `appeared after
N ms`의 N으로 이 값을 다시 보여 줄 것이다.
