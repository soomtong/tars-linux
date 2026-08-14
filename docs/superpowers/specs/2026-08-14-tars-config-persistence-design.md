# TARS Config Persistence — Design

**Date:** 2026-08-14
**Status:** 설계 승인됨, CP-M0 미착수

## 배경

Init Supervisor(IS, 2026-08-14 완료)까지 오면서 TARS는 부팅하고, 화면에
텍스트를 그리고, 키를 받고, 죽은 자식을 되살릴 줄 알게 됐다. 그런데
**아무것도 기억하지 못한다.** 루트 파일시스템이 `kernel/initrd.cpio` =
initramfs(tmpfs)라서 전원이 꺼지면 모든 것이 사라지고, 다음 부팅은 언제나
빌드 시점에 구운 그 상태에서 시작한다.

원래 요청은 "부팅 셸을 bash/zsh/fish/nushell 중에서 고르고, 마지막에 쓴
것을 다음 부팅의 기본값으로 쓰고 싶다"였다
(`docs/decisions/project_boot_shell_selection.md`, 2026-08-11). 이건 단독
기능이 될 수 없다 — "마지막 선택을 기억한다"는 말 자체가 재부팅을 넘어
살아남는 저장소를 전제하기 때문이다. 그래서 이 서브프로젝트는 **설정
영속화**(Config Persistence, CP)로 잡고, 셸 선택은 그 저장소의 **첫 사용
사례**로 다룬다. 폰트 크기·색상·키바인딩 등 앞으로 생길 설정도 전부 여기서
만드는 저장소를 쓰게 된다.

IS는 이 서브프로젝트의 준비운동이었다. PID 1이 `execve`로 셸이 되어버리는
구조에서는 "설정을 읽어서 어느 셸을 띄울지 정한다"를 얹을 자리가 없었다.
지금은 `init/src/main.zig`의 `Kind.path()`가 상수를 반환하는 자리에 주석으로
*"설정 파일에서 목록을 읽는 것은 다음 서브프로젝트(설정 영속화)의 일이다"*
라고 적혀 있다. 이 함수 하나를 바꾸는 것이 CP-M2의 모양이다.

### 출발 시점의 저장소 상태 (2026-08-14 실측)

`kernel/.config`를 읽어 확인한 것:

| 항목 | 현재 값 | 의미 |
|---|---|---|
| `CONFIG_BLOCK` | `y` | 블록 계층 자체는 켜져 있다 |
| `CONFIG_VIRTIO`, `CONFIG_VIRTIO_PCI` | `y` | virtio 버스는 이미 있다(DF에서 GPU 때문에) |
| `CONFIG_BLK_DEV` | **not set** | 블록 *드라이버* 메뉴가 꺼져 있어 `VIRTIO_BLK`이 목록에 나타나지도 않는다 |
| `CONFIG_EXT2_FS`/`EXT4_FS`/`VFAT_FS` | **전부 not set** | 디스크에 쓸 수 있는 파일시스템이 하나도 없다 |

게이트 쪽:

- `boot/check.sh:24` — `-cdrom ../out/tars.iso` (BF 체인). `-drive` 없음.
- `terminal/check.sh:52` — `-kernel`/`-initrd` + `virtio-gpu-pci` (TF 체인).
  `-drive` 없음. 대신 monitor fd 3으로 `sendkey`를 보내 게스트 셸에 실제로
  타이핑하는 인프라가 이미 있다(TF-M3의 `math 6 x 7`, IS의 `exit`).

즉 커널에는 디스크가 들어올 문이 닫혀 있고, 두 게이트 중 어느 쪽도 디스크를
물고 부팅하지 않는다.

## 목표 (MVP)

게스트 안에서 설정 파일을 고치고 재부팅하면 다음 부팅의 셸이 실제로 바뀐다.
이것을 **QEMU를 두 번 띄우는 자동 게이트**로 검증한다. 1차 부팅에서 게스트
셸에 `echo shell=zsh > /config/tars.conf`를 타이핑하고, QEMU를 죽였다가, 같은
디스크 이미지로 2차 부팅해서 셸이 바뀐 것을 확인한다.

BF/TF 게이트가 "1회 부팅 + 로그 grep"이었던 것과 달리 **한 스크립트 안에서
부팅이 두 번 일어나는 것**이 이 서브프로젝트가 만드는 새로운 검증 모양이다.
영속성은 원리적으로 한 번의 부팅으로는 증명할 수 없다.

## 비목표

- **게스트 안에서 셸을 고르는 명령·메뉴.** `tars-config shell zsh` 같은 CLI나
  터미널 안의 선택 UI는 이번 범위 밖이다. 이번 종료점은 "파일을 고치고
  재부팅"이며, 설정을 **누가 어떤 UI로** 쓰는가는 별도 주제다. 저장소와
  읽기/쓰기라는 뼈대를 먼저 완성한다.
- **게스트 안에서의 재부팅.** PID 1에 시그널 처리(SIGTERM)나 `reboot(2)`
  경로를 넣지 않는다. 게이트는 QEMU를 죽였다가 다시 띄우는 방식으로
  재부팅을 대신한다. 전원 관리는 그 자체로 하나의 주제이며 `HANDOFF.md`의
  숙제로 남아 있다.
- **nushell.** Debian 아카이브에 없다(2026-08-14 확인). 넣으려면 벤더 자체
  apt 저장소나 GitHub 릴리스 tarball을 `Dockerfile`에 Debian이 아닌 출처로
  추가해야 하고, 바이너리도 커서 initrd가 눈에 띄게 커진다. 이번에는
  **bash/zsh/fish 셋**만 넣는다 — 셋 다 Debian 아카이브에 있어 기존 sysroot
  방식(`apt-get download`)을 그대로 쓴다. 필요해지면 나중에 추가한다.
- **파티션 테이블.** 디스크 전체(`/dev/vda`)를 파일시스템 하나로 쓴다. MBR/GPT
  파싱은 이 단계에서 배울 대상이 아니다.
- **여러 사용자·권한 모델.** 설정 파일은 root 소유 하나뿐이다.
- **설정 마이그레이션(스키마 버전).** 모르는 키는 무시하고 로그만 남긴다.

## 핵심 설계 결정

### 1. virtio-blk + ext2, 디스크 전체에 파일시스템 하나

세 후보를 놓고 골랐다.

| 안 | 내용 | 판단 |
|---|---|---|
| **A. virtio-blk + ext2** | 디스크 전체에 fs 하나, init이 `/config`에 마운트 | **채택** |
| B. virtio-blk + vfat | 같은 구조에 FAT | 탈락 |
| C. 파일시스템 없이 raw 블록 | 고정 오프셋에 텍스트를 직접 read/write | 탈락 |

**C가 먼저 탈락하는 이유가 범위 결정과 직결된다.** 이번 종료점이 "게스트
안에서 파일을 고치고 재부팅"인데, raw 블록에는 `echo shell=zsh > ...`으로 쓸
대상 자체가 없다. 사용자가 손으로 고칠 수 있어야 한다는 요구가 곧
"파일시스템이 있어야 한다"는 뜻이다. 파일시스템 코드를 아끼는 대신 사용자가
쓸 수 없는 저장소가 된다.

**B(FAT) 대신 A(ext2)인 이유는 둘.** 하나, FAT에는 유닉스 퍼미션·소유자가
없어 마운트 옵션(`uid`/`gid`/`umask`)으로 흉내 내야 하는데 배울 것이 없는
잡음이다. 둘, ext2는 저널이 없어 드라이버가 작고 동작이 투명하다. 저널링
(ext4)은 "전원이 끊겨도 메타데이터가 일관적"을 위한 장치인데, 설정 파일 몇
개를 어쩌다 한 번 쓰는 워크로드에서는 저널이 방어하는 상황 자체가 거의
없다.

커널 config 변경은 세 줄이다.

```
CONFIG_BLK_DEV=y        # 이걸 켜야 블록 드라이버 메뉴가 열린다
CONFIG_VIRTIO_BLK=y
CONFIG_EXT2_FS=y
```

virtio 버스(`CONFIG_VIRTIO_PCI=y`)는 DF에서 GPU 때문에 이미 켜져 있으므로 그
위에 얹히기만 한다. `olddefconfig`이 딸린 심볼을 자동으로 붙일 수 있으니
빌드 후 `.config`를 다시 읽어 실제로 무엇이 켜졌는지 확인한다.

### 2. `MS_SYNCHRONOUS`로 마운트한다

이 설계에서 제일 중요한 한 줄이다.

게스트에서 `echo shell=zsh > /config/tars.conf`를 치면 그 데이터는 **page
cache에만 올라가고 디스크에는 가지 않는다.** 리눅스는 언제 내려보낼지를
알아서 정한다(보통 수십 초 뒤, 또는 `sync`/언마운트 시점). 그 상태로 QEMU를
죽이면 설정이 사라진다 — "영속화를 만들었는데 값이 안 남는다"는, 이 주제에서
가장 헷갈리는 종류의 실패다. 그리고 이번 게이트는 정확히 그 순서(쓰기 → 즉시
kill)로 동작한다.

`MS_SYNCHRONOUS`로 마운트하면 이 파일시스템의 모든 쓰기가 즉시 디스크로
내려간다. 설정 파티션은 트래픽이 사실상 0이라 성능 대가가 없고, 대신
"언제부터 안전한가"를 사용자도 게이트도 신경 쓸 필요가 없어진다. 게스트에
`sync` 바이너리를 넣거나 사용자에게 "쓰고 나서 sync 하세요"라고 안내하는
것보다 훨씬 낫다.

### 3. 설정 파일: `/config/tars.conf`, 한 줄에 `key=value`

```
# TARS configuration. Edit and reboot to apply.
# shell: fish | bash | zsh
shell=fish
```

`#`으로 시작하는 줄은 주석, 빈 줄은 무시, 나머지는 첫 `=`를 기준으로 키와
값으로 나누고 양쪽 공백을 떼어낸다.

키마다 파일 하나(sysfs 스타일, `/config/shell`)도 검토했다. 파서가 아예 필요
없고 `echo zsh > /config/shell`이 더 짧다. 그래도 한 파일을 고른 이유는 이
저장소가 앞으로 담을 것이 셸 하나가 아니라 폰트 크기·색상·키바인딩이기
때문이다. 설정이 열 개가 되면 "지금 무엇이 설정돼 있나"를 `cat` 한 번으로 못
보게 된다. 파서는 libc 없는 Zig에서 30줄 남짓이라 대가가 작다.

### 4. `init/src/config.zig` — 새 모듈 하나

인터페이스는 둘뿐이다.

```zig
pub fn load(path: [:0]const u8) Config;      // 실패해도 기본값을 돌려준다
pub fn save(path: [:0]const u8, c: Config) !void;
```

`main.zig`는 지금 241줄이고 마운트·감독·재시작이라는 한 가지 일
(PID 1 노릇)을 한다. 여기에 파서까지 넣으면 파일 하나가 두 가지 일을 하게
되므로 분리한다.

**`init`이 쓰기까지 하는 이유는 죽은 코드를 만들지 않기 위해서다.** 이번
범위에서 설정을 고치는 주체는 사용자(손으로)이므로, 가만두면 "쓰기"는 아무도
호출하지 않는 기능이 된다. 그래서 쓰기의 실사용을 **first-boot seeding**으로
잡는다 — 빈 디스크로 처음 부팅하면 init이 기본 설정 파일을 주석과 함께
만들어 놓는다. 덕분에 사용자는 빈 파일 앞에서 무엇을 쓸 수 있는지 알게 되고,
게이트는 "1차 부팅에서 생겼다 → 2차 부팅에서 읽혔다"로 영속성을 증명할 수
있다.

### 5. 설정 하나로 부팅이 막히지 않게 하는 세 장치

설정 파일이 PID 1의 동작을 바꾸는 순간, 설정을 잘못 쓰면 부팅이 안 되는
상태가 만들어진다. 셋으로 막는다.

1. **화이트리스트.** `shell` 값은 임의 경로가 아니라 이름(`fish`/`bash`/
   `zsh`)만 받고 init이 경로로 매핑한다. `shell=/etc/passwd` 같은 것이 애초에
   성립하지 않는다.
2. **모르는 값은 기본값으로 폴백 + 로그.** `shell=nushell`이라고 써두면
   `tars-init: unknown shell 'nushell', falling back to fish`를 찍고 부팅을
   계속한다.
3. **마운트 실패는 치명적이지 않다.** 디스크가 없으면 로그만 남기고 내장
   기본값으로 간다. BF 체인이 정확히 이 경우다(ISO 부팅이라 `-drive`가 없다)
   — BF 게이트는 손대지 않아도 계속 통과해야 한다.

이 셋은 "설정이 없거나 깨진 상태가 정상 경로"라는 태도를 코드에 박아두는
것이다. 저장소는 사용자가 손으로 고치는 물건이므로 깨진 입력이 규칙이지
예외가 아니다.

### 6. 게이트: 호스트에서 이미지를 편집하지 않고 게스트에서 타이핑한다

두 부팅 사이에 설정을 바꾸는 방법이 둘 있다.

- **호스트에서** `debugfs -w -R "write ..."`로 ext2 이미지를 직접 편집한다.
  쉽고 결정적이다.
- **게스트 안에서** `sendkey`로 셸에 `echo shell=zsh > /config/tars.conf`를
  타이핑한다. 글자 수만큼 sendkey가 필요하고(`=`는 `equal`, `>`는
  `shift-dot`, `/`는 `slash`) 조금 번거롭다.

**게스트 타이핑을 고른다.** 사용자가 실제로 할 행동이 그것이고, 그래야
"게스트에서 쓴 것이 디스크에 도달했는가"까지 한 번에 검증된다 — 호스트
편집은 이 부분(파일시스템 쓰기 경로 + `MS_SYNCHRONOUS`)을 통째로 건너뛴다.
게이트가 자기가 보지 않는 것을 통과시키는 문제는
`docs/decisions/project_gate_chain_composition.md`에 이미 기록된 이 저장소의
반복되는 함정이다.

키 주입 인프라는 이미 있다. `terminal/check.sh`가 monitor fd 3으로
`sendkey`를 보내 `math 6 x 7`을 치고(TF-M3) `exit`으로 셸을 죽인다(IS). 같은
방식이고, 타이핑 결과는 `terminal: screen>` 로그 줄에 렌더링된 텍스트로
나타나므로 되읽기 확인도 가능하다.

### 7. 세 번째 체인 `config/check.sh`

루트 `check.sh`는 지금 BF·TF 두 체인을 각각 3회 돌린다. 여기에 CP가 세
번째로 붙는다. TF 체인에 얹지 않는 이유는 CP의 검증이 **한 스크립트 안에서
QEMU를 두 번 띄우는** 구조라 기존 1회 부팅 게이트와 모양이 다르기 때문이다.
비용은 회차당 부팅 2회 × 3회 = 부팅 6회가 늘어나는 것이다(ZM-M3 이후 TF
계열 부팅 1회가 수 초 수준이라 감당 가능하다).

## Milestones

| M | 내용 | 게이트가 보는 것 |
|---|---|---|
| **CP-M0** | 커널 config 3줄, `config/make_disk.sh`(16MB raw + `mkfs.ext2`), QEMU `-drive`, init의 `/config` 마운트(`MS_SYNCHRONOUS`), 컨테이너에 `e2fsprogs` 추가 | 1회 부팅 + `tars-init: mounted ext2 at /config`. 디스크 없는 BF 체인도 여전히 통과 |
| **CP-M1** | `init/src/config.zig` — `key=value` 파서 + first-boot seeding | **2회 부팅.** 1차 `created`, 2차 `loaded`. 여기서 영속성이 처음 증명된다 |
| **CP-M2** | `Dockerfile`에 bash/zsh 추가 → sysroot → `make_initrd.sh` → `Kind.path()`가 config를 본다 | 2회 부팅 + 1차에서 sendkey 편집 → 2차에서 셸이 바뀐다 |

각 milestone이 끝난 뒤에 다음 milestone의 상세 plan을 쓴다 — 전체를 미리
설계하지 않는다(이 저장소의 모든 서브프로젝트와 동일).

## 저장소 구조 (추가분)

```text
tars-linux/
├── config/
│   ├── make_disk.sh      # raw 이미지 생성 + mkfs.ext2 (CP-M0)
│   └── check.sh          # 2회 부팅 게이트 (CP-M0~M2)
├── init/src/config.zig   # 설정 파서/기록기 (CP-M1)
└── out/config.img        # .gitignore 대상, 게이트가 매번 새로 굽는다
```

디스크 이미지는 빌드 산출물이므로 `.gitignore`에 넣는다. 게이트는 회차마다
새로 구워 "1차 부팅이 진짜 빈 디스크에서 시작한다"를 보장한다 — 남아 있는
이미지를 재사용하면 seeding 경로가 다시는 실행되지 않아 게이트가 자기를
속이게 된다.

## 미리 알고 들어가는 위험

**1. `TERM`이 없다.** `terminal/src/*.zig`를 grep해도 자식에게 `TERM`을
설정하는 코드가 없고, 그래도 fish는 잘 돈다. 그런데 bash의 readline과 zsh의
zle는 terminfo를 찾는다 — CP-M2에서 zsh를 띄우면
`can't find terminal definition` 류가 나올 수 있다. 대응은 `spawn`에서
`TERM=linux`를 넘기고 `ncurses-base`(arch: all)의 terminfo를 initrd에 넣는
것이다. **실제로 깨지는 것을 보고 나서 넣는다** — 안 깨지면 불필요한 짐이다.

**2. zsh는 바이너리 하나가 아니다.** Debian zsh는
`/usr/lib/x86_64-linux-gnu/zsh/<버전>/`의 모듈 `.so`들과
`zsh-common`(arch: all)의 `/usr/share/zsh` 함수들을 함께 필요로 한다. fish가
`fish-common`을 필요로 했던 것과 같은 구조라 `make_initrd.sh`에 선례가 있다.
`Dockerfile` 추가 목록은 `bash:amd64`, `zsh:amd64`, `zsh-common`,
`libtinfo6:amd64` 정도로 예상하고, 빠진 것이 있으면 `make_initrd.sh`가
소네임을 찍고 즉시 죽는다 — 조용히 통과하지 않도록 이미 그렇게 만들어져
있다([[project_build_host_arch]]).

**3. initrd가 커진다.** 지금 53MB(gzip 11.8MB)이고 대부분이 디버그 심볼
붙은 `terminal` 42MB다. bash/zsh는 각각 1MB 안팎이라 큰 문제는 아니지만, BF
체인이 limine의 BIOS INT13h로 ISO에서 읽는 경로는 크기에 민감하다
(`kernel/make_initrd.sh:117-121`). 부팅 시간이 눈에 띄게 늘면 `init`을
`ReleaseSafe`로 바꾸는 카드가 `HANDOFF.md`에 남아 있다.

## 검증 방법

CP-M1부터 게이트의 뼈대는 이렇다.

```
1차 부팅  디스크 이미지를 새로 굽고 -drive로 물려 부팅
          → "tars-init: mounted ext2 at /config"
          → "tars-init: created /config/tars.conf"   (seeding)
          → (M2) 프롬프트를 기다린 뒤 sendkey로 게스트에서 직접 편집
                 echo shell=zsh > /config/tars.conf ⏎
          → QEMU kill  (MS_SYNCHRONOUS라 이미 디스크에 도달해 있다)
2차 부팅  같은 이미지를 그대로 물리고 부팅
          → "tars-init: loaded /config/tars.conf"
          → (M2) "tars-init: config shell=zsh" + fish 배너가 없다
```

BF/TF와 마찬가지로 로그 폴링으로 진행 시점을 잡고(고정 sleep 금지), 실패
시에는 어떤 마커가 없었는지를 하나씩 출력한다. 루트 `check.sh`는 이 체인도
3회 연속 통과해야 `TARS check PASS`를 낸다.
