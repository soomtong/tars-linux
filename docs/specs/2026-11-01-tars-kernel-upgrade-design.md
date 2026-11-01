# TARS Kernel Upgrade — Design

Date: 2026-11-01
Status: KU-M0 끝남(2026-11-01, 슬롯 둘 · 1GiB ESP · 컨테이너에 mtools, `make gate` 22/22 10분 26초, verify 8237줄). KU-M1(커널 버전 올리기) plan 전

사용자가 제안했다(2026-11-01). 설치된 디스크에 부트 엔트리 둘(new · old)을 두고, 새 이미지로 뜬 부팅에 이상이 있으면 old로
돌아간다. 처음 제안에는 그 전 세대를 legacy로 보관하는 것도 있었는데 사용자가 뺐다(아래 비목표 1). 목적은 커널 버전을 올리는 것이지만,
올리는 단위는 커널이 아니라 이미지(`bzImage` + `initrd.cpio` 한 쌍)다(결정 1).

## 한 줄 요약

`tars-install`의 갱신이 ESP의 부트 파일을 제자리에서 덮어쓰지 않고 회전시킨다. 지금 것은 `boot/old/`로 가고 새 것이 `boot/`에
들어간다. ESP의 `limine.conf`에는 엔트리가 둘 생기고 메뉴가 3초 보인다. new가 이상하면 사람이 메뉴에서 old를 고른다(KU-M0). 그
위에서 커널 버전을 올린다(KU-M1).

## 배경

- 지금의 갱신(DI-M2)은 ISO로 뜬 기계에서 `tars-install <disk>`를 치면 p1의 파일 넷을 `O_TRUNC`로 덮는다(`init/src/install.zig`
  `fillEsp`). 새 이미지가 그 기계에서 안 뜨면 돌아갈 곳이 없다. ISO를 다시 꽂고 옛 ISO로 갱신을 한 번 더 해야 한다. 그 옛 ISO가
  손에 있어야 한다.
- 커널 버전은 BF-M1(2026-08-03) 뒤로 `6.18.42` 그대로다(`kernel/build.sh`). 버전을 올리면 실기에서 드라이버 · firmware ·
  simpledrm의 동작이 바뀔 수 있는데, 실기 테스트는 게이트가 못 본다. 이 위험 때문에 돌아갈 자리가 먼저 필요하다.

## 착수 전에 확인한 것

2026-11-01, HEAD `0435bb3`.

1. Limine에는 자동 롤백의 재료가 없다. 우리가 쓰는 태그 `v12.5.2`의 `CONFIG.md`(410줄)를 읽었다. 전역 옵션 가운데 엔트리 선택에
   닿는 것은 `timeout` · `default_entry` · `remember_last_entry` 셋뿐이다.
   - boot counting(시도 횟수를 적어 두고 일정 횟수가 넘으면 다른 엔트리로 넘어가기), fallback 엔트리, 한 번만 쓰는 기본값(one-shot)은
     없다. Limine은 ESP에 아무것도 쓰지 않는다.
   - `remember_last_entry: yes`는 마지막에 고른 엔트리를 UEFI 변수에 적는다(UEFI 전용). 이것도 "실패하면 넘어간다"가 아니라
     "사람이 고른 것을 기억한다"다.
   - 그래서 new가 kernel panic이 나면 다음 부팅도 new다. 자동 롤백은 Limine 혼자서는 안 되고, 부트로더 밖의 장치(UEFI `BootNext`
     등)가 필요하다. 이번 범위에서 뺀다(비목표 2).
   - `timeout`은 소수도 받고, `0`이면 메뉴 없이 기본 엔트리로 바로 간다. 지금 `boot/limine.conf`가 `timeout: 0`이다.
   - 엔트리 제목은 `/` 뒤의 글자 그대로다. `default_entry`가 없으면 첫 엔트리가 기본이다.
2. 시스템 전체가 initramfs에서 돈다(`project_disk_install.md`). 그래서 `bzImage` + `initrd.cpio` 한 쌍이 곧 시스템 한 벌이다.
   initrd에는 firmware(linux-firmware에서 고른 것)와 init · terminal이 들어 있고, firmware는 커널 버전과 짝이 맞아야 한다.
3. 크기. 오늘 빌드의 `bzImage`는 8,958,976바이트, `initrd.cpio`는 93,367,226바이트로 한 벌에 약 102MB다. ESP는
   `disk.zig`의 `SFDISK_SCRIPT`가 정한 `256MiB`(268MB)다. 두 벌(204MB)은 들어가고 세 벌(306MB)은 안 들어간다. `fillEsp` 주석의
   "두 벌이 들 자리(90MB)"는 그때의 값이고 지금은 102MB다.
4. 설정은 세대가 같이 쓴다. p2(`tars-config`)는 갱신이 열지 않는다. old로 뜬 시스템은 new가 쓴 설정을 읽게 되는데, 모르는 키와
   값은 기본값으로 폴백하고 로그를 남기는 것이 이미 정책이다(CP design). 그래서 롤백 때문에 시스템이 죽지는 않는다.
5. 버전 글자는 init과 `tars-install`에 함께 구워진다(`build_info.version`, BV). ISO로 뜬 기계의 `tars-install`은 그 ISO의
   initrd에서 나왔으므로, 자기가 새로 깔 이미지의 버전을 이미 안다.
6. 설치 여부의 판정(`isInstalled`)은 p1에 `boot/bzImage`가 있는지를 본다. 갱신 도중 그 파일이 잠깐 없어지면 다음 실행은 그
   디스크를 "설치 안 됨"으로 보고 새 설치로 간다. 새 설치는 p2까지 지운다(결정 6이 막는다).

## 결정

### 결정 1. 슬롯의 단위는 이미지 한 벌이다

커널만 따로 두 벌 두면 initrd 안의 firmware가 어느 커널과 짝인지 어긋날 수 있다(확인 2). 그리고 버전을 올릴 때 실제로 자주 바뀌는
것은 커널보다 init · terminal이다. 그래서 슬롯 하나가 `bzImage` · `initrd.cpio` · `version` 셋을 갖는다. KU-M1이 커널을 올릴 때도
이 단위 그대로 간다.

### 결정 2. new는 지금 자리 그대로, old만 새 자리

| 슬롯 | 자리 | 엔트리 제목 |
| --- | --- | --- |
| new | `boot/bzImage` · `boot/initrd.cpio` · `boot/version` | `TARS <new 버전>` |
| old | `boot/old/bzImage` · `boot/old/initrd.cpio` · `boot/old/version` | `TARS <old 버전> (old)` |

new를 `boot/new/`로 옮기지 않는 이유는 ISO와 ESP의 경로가 같다는 성질(DI design 확인 1)을 지키기 위해서다. `BOOT_FILES` ·
`MEDIUM_MARK` · ISO 쪽 `limine.conf`가 그대로이고, 이미 설치된 디스크는 옮길 것이 없다.

`boot/version`은 새로 생기는 파일이고 버전 글자 한 줄이다. `tars-install`이 `build_info.version`을 적는다. 엔트리 제목을
`limine.conf`를 파싱해서 얻지 않고 이 파일에서 읽는다. 그리고 이 파일은 "이 슬롯은 끝까지 써졌다"는 표지도 겸한다(결정 5).

old 엔트리의 `cmdline:`에는 `tars.slot=old`를 더 붙인다. init은 이 낱말을 쓰지 않는다. 사람과 게이트가 `/proc/cmdline`으로 "지금 old로
떴다"를 알아보게 하는 용도다.

### 결정 3. 메뉴는 ESP에서만 3초 보인다

ISO의 `limine.conf`는 `timeout: 0` · 엔트리 하나로 그대로 둔다. ISO는 고를 것이 없고, ISO로 뜨는 체인(boot · machine 등)의 시간이
늘면 안 된다. ESP의 conf는 `tars-install`이 ISO의 conf를 바탕으로 짓는다. 지금도 `espConf`가 `cmdline:` 줄에 `tars.installed`를
붙이고 있으므로, 같은 자리가 다음 일을 더 한다.

- `timeout: 0`을 `timeout: 3`으로 바꾼다.
- 엔트리 블록을 두 번 쓴다. 두 번째는 제목에 `(old)`를 붙이고, 경로를 `boot/old/`로 바꾸고, `tars.slot=old`를 붙인다.
- old 슬롯이 없으면(첫 설치) 엔트리는 하나다. 이때도 timeout은 3으로 둔다. 나중에 old 엔트리가 생기는지 여부와 상관없이 부팅
  모양이 같아야 하기 때문이다.

3초는 사용자가 고를 값이다. 실기에서는 부팅마다 이만큼 늦어진다. 대신 `quiet: yes`는 쓰지 않는다. 메뉴가 보여야 고를 수 있다는
것을 사람이 안다.

`remember_last_entry`는 쓰지 않는다. 한 번 old를 고르면 그것이 기본이 되어 new가 깨졌다는 사실이 가려진다. 기본은 늘 new다.

### 결정 4. 회전의 순서 — 어느 순간에 전원이 나가도 엔트리 하나는 뜬다

ESP에는 두 벌만 들어가므로(확인 3) old를 먼저 지워야 한다. 순서는 다음과 같고 단계마다 `sync`한다. vfat의 쓰기는 캐시에서 순서가
바뀔 수 있기 때문이다.

1. `boot/old/`의 파일을 지운다.
2. 새 `limine.conf`를 쓴다(`.tmp`에 쓰고 rename). new 엔트리는 `boot/`(아직 지금 이미지), old 엔트리는 `boot/old/`(비었음)를
   가리킨다.
3. `boot/`의 셋을 `boot/old/`로 rename한다. 같은 파일시스템 안의 rename이라 복사가 없다.
4. 매체에서 `bzImage` · `initrd.cpio`를 `boot/`로 복사한다.
5. `sync`한 뒤 `boot/version`을 쓰고 다시 `sync`한다.

단계 사이에 전원이 나가면 이렇다.

| 끊긴 자리 | new 엔트리 | old 엔트리 |
| --- | --- | --- |
| 1 뒤 | 지금 이미지 — 뜬다 | (옛 conf에 있었다면) 빈 자리 |
| 2 뒤 | 지금 이미지 — 뜬다(제목은 새 버전으로 잘못 붙는다) | 빈 자리 |
| 3 뒤 | 빈 자리 | 지금 이미지 — 뜬다 |
| 4 도중 | 반쪽 | 지금 이미지 — 뜬다 |
| 5 뒤 | 새 이미지 | 지금 이미지 |

2와 3의 순서가 중요하다. 3을 먼저 하면 옛 conf(엔트리 하나)가 빈 `boot/bzImage`를 가리키는 순간이 생긴다.

### 결정 5. `boot/version`이 없는 슬롯은 회전하지 않는다

4 도중에 끊긴 디스크에서 같은 명령을 다시 치면, 회전이 반쪽 new를 old로 보내고 멀쩡한 old를 지운다. 그래서 회전은 `boot/version`이
있을 때만 한다. 없으면 old는 그대로 두고 new 자리만 덮는다(지금의 갱신과 같은 길).

이 규칙의 결과로, 이 기능 전에 설치된 디스크(`boot/version`이 없다)는 첫 갱신에서 old가 생기지 않고 두 번째 갱신부터 생긴다.
옛 설치를 따로 알아보는 규칙을 더 두지 않는 값이다. 테스트 흐름은 매번 `--wipe`로 새로 깔기 때문에 손해가 작다.

### 결정 6. 설치 여부는 두 슬롯 가운데 하나라도 `bzImage`가 있으면이다

확인 6의 처방이다. 결정 4의 3 뒤에 끊긴 디스크는 `boot/bzImage`가 없지만 `boot/old/bzImage`가 있다. 이 디스크가 새 설치(p2 지우기)로
가면 안 된다.

### 결정 7. 롤백은 사람이 메뉴에서 한다

"이상"의 판정은 사람이 한다. new로 떠서 화면이 안 나오거나 키보드가 안 먹으면 재부팅하고 메뉴에서 `(old)`를 고른다. old로 뜬
상태는 그 부팅 한 번뿐이다. 계속 old로 쓰려면 매번 고르거나, 고친 ISO로 다시 갱신한다. 실행 중인 시스템에서 old를 new로 올리는
명령은 만들지 않는다(비목표 3).

### 결정 8. 새 설치의 ESP는 1GiB다

사용자가 정했다(2026-11-01). 슬롯 둘은 ESP 사용량을 두 배로 만든다. 그 비용을 같은 서브프로젝트에서 치른다. 256MiB에서는 한 벌이
약 125MB를 넘는 순간 회전이 멈추는데(위험 2), 지금 한 벌이 102MB라 여유가 23MB뿐이다. 1GiB면 한 벌이 약 500MB가 될 때까지
두 벌이 들어간다.

다른 운영체제와 비교하면 이렇다. Windows는 ESP(100 · 260MB)에 부트 관리자만 두고 커널은 NTFS 파티션에서 읽는다. macOS는
고정 크기 파티션 대신 APFS 볼륨들이 컨테이너의 빈 공간을 나눠 쓴다. TARS는 둘 다 못 한다. Limine이 읽는 파일시스템이
FAT12/16/32와 ISO9660뿐이라서다(v12.5.2 README). 그래서 커널이 FAT 위에 있어야 하고, FAT 파티션의 크기를 넉넉히 잡는 것이
가장 싼 답이다. ESP와 이미지를 가르는 길(systemd의 XBOOTLDR처럼 p3에 큰 FAT를 따로 두기)은 비목표 4에 남긴다.

- `disk.zig`의 `SFDISK_SCRIPT`에서 p1을 `size=1GiB`로 바꾼다. p2(1GiB)는 그대로다.
- 디스크가 배치보다 작으면 디스크를 건드리기 전에, YES를 묻기 전에 거절한다. 지금은 이런 검사가 없다. 최소 크기가 약 1.3GiB에서
  2GiB 남짓으로 커지므로, 2GB USB 스틱에 깔면 확인을 받은 뒤 sfdisk에서 실패하게 된다.
- 사용자의 실제 배치(2026-11-01 확인): 부팅 매체는 2GB 외장 USB(ISO를 그대로 쓴다, 107MB)이고 설치 대상은 내장 SSD 100GB다.
  ESP 크기는 설치 대상에만 닿으므로 그 USB는 영향이 없다. 2GB 스틱을 설치 대상으로 쓰는 경우만 위의 검사가 거절한다. p2(1GiB)를
  줄여 그 경우를 살리는 길도 있었지만(p2는 MB 단위의 설정만 담는다) 그런 사용이 없어서 하지 않는다.
- install 체인의 디스크(`truncate -s 2G`)를 3G로 올린다. 2GiB에는 1GiB + 1GiB에 GPT의 앞뒤 머리가 들어가지 않는다. sparse 파일이라
  호스트 디스크는 거의 쓰지 않는다.
- 사용자 안내(`docs/guides/running-tars.md` 216줄)의 256MiB를 고친다. DI design의 256MiB는 그때의 기록이라 고치지 않는다.
- 이미 설치된 디스크(256MiB)는 `--wipe`로 다시 깔아야 넓어진다. 갱신은 ESP 크기를 바꾸지 않는다(비목표 4). 그런 디스크에서는
  위험 2의 검사가 넘침을 막는다.

## 게이트

install 체인(`install/check.sh`)에 붙인다. 새 체인을 만들지 않는다 — 슬롯은 설치된 디스크에만 있고, 설치된 디스크를 만드는 것은
그 체인뿐이다.

KU-M0에서 실제로 선 판정은 이렇다(plan `docs/plans/2026-11-01-tars-kernel-upgrade-ku-m0.md` Task 3). 컨테이너에 mtools를 넣어
(plan Task 0) QEMU가 꺼진 사이 호스트가 p1을 직접 열 수 있게 한 것이 셋(19a · 21a · 3a 뒤의 확인)을 가능하게 했다.

| 판정 | 부팅 | 무엇 |
| --- | --- | --- |
| 4d | 1 | 배치가 안 들어가는 64MiB 디스크는 YES 전에 크기로 거절되고 그대로 남는다(결정 8) |
| 18 | 2 | 첫 설치: 메뉴 대기가 있고 엔트리는 하나다 |
| 19a | 3a | 호스트가 p1을 채운 ESP: 갱신이 YES 전에 `no room`으로 거절하고, `boot/version`은 그대로, `boot/old`는 빈 채다(위험 2) |
| 19 | 3 | 갱신이 진짜 FAT의 빈 자리를 찍고, 지금 이미지의 셋을 `boot/old/`로 옮긴다(결정 4) |
| 20 | 4 | 엔트리가 둘이고 기본은 new다 |
| 21 | 4b | 메뉴에서 시리얼로 old를 골라 `tars.slot=old`로 뜨고, 같은 p2와 마커를 본다(결정 7, 확인 4) |
| 21a | 5 | 호스트가 `boot/bzImage`를 지운 디스크(회전 3단계 뒤에 끊긴 모양)도 `TARS installed`다(결정 6) |
| 22 | 6 | `--wipe` 뒤로 엔트리가 다시 하나다 |

순수 규칙(ESP conf 짓기, 회전 여부 판정, 회전 순서)은 `disk.zig`에 두고 `disk_test`의 검사 10 · 16 · 19~21이 본다. 결정 4의 끊김 표는
실제로 전원을 끊어 재지 않고, 검사 21이 `disk.ROTATION`을 상태 모형 위에서 한 op씩 돌려 "뜨는 엔트리가 하나 이상인가"를 본다.

## Milestone

- KU-M0 — 슬롯 둘과 1GiB ESP. 결정 1~8과 게이트. 커널 버전은 그대로다. 착수 전 실측 둘은 아래 "M0 전에 잰 것"에 있다.
- KU-M1 — 커널 버전 올리기. 6.18 longterm의 최신 패치로 갈지, 그 다음 longterm으로 갈지는 M0 게이트 뒤에 조사해서 고른다.
  `.config`를 `olddefconfig`로 옮긴 diff를 읽는 일, tarball sha256(VS), 이미지 크기를 다시 재서 ESP 두 벌에 들어가는지 보는 일,
  루트 게이트 22/22가 이 milestone의 몫이다. 실기 확인은 사용자 몫이고, 그때 old 엔트리가 처음으로 실제 쓸모를 갖는다.

## M0 전에 잰 것

2026-11-01, HEAD `2234888`, Limine 12.5.2, 컨테이너의 OVMF(`OVMF_CODE_4M.fd`) + TCG. ESP는 디스크 이미지 대신 QEMU의 vvfat
(`-drive file=fat:<디렉터리>,if=none,readonly=on` + `virtio-blk-pci`)로 흉내 냈다. 기본 IDE 장치는 읽기 전용 vvfat를 `Block node is
read-only`로 거부한다. 엔트리 둘의 cmdline에 `tars.slot=new` · `tars.slot=old`를 두고, 커널의 `Command line:` 줄로 어느 쪽이
떴는지 갈랐다. 엔트리 둘은 같은 `bzImage` · `initrd.cpio`의 복사본이다.

| | conf | 시리얼 입력 | 결과 |
| --- | --- | --- | --- |
| A | 둘 다 있음, `timeout: 3` | 없음 | `tars.slot=new`(기본 엔트리) |
| B | 둘 다 있음, `timeout: 10` | 메뉴가 보이면 `ESC [ B`, 0.5초 뒤 `CR` | `tars.slot=old` |
| C | new의 `kernel_path`가 없는 파일, `timeout: 3` | 없음 | `PANIC: linux: Failed to open kernel with path …` 뒤 `Press a key to return to menu.`에서 멈춰 기다린다 |
| D | C와 같음 | 그 줄이 보이면 공백 하나, 3초 뒤 `ESC [ B` · `CR` | 메뉴로 돌아가 `tars.slot=old` |

1. 시리얼로 메뉴를 조작할 수 있다. `serial: yes`는 입력도 받고, VT100의 아래 화살표(`ESC [ B`)가 먹는다. 게이트의 old 부팅은 이
   방식으로 한다. 함정 하나가 있다. Limine은 메뉴 글자 사이에 커서 이동 escape를 끼우므로 날 로그에서 `TARS old`를 grep하면 영영
   안 나온다(B의 첫 회가 그래서 키를 못 보냈다). install 체인의 `clean()`과 같은 perl로 escape를 걷은 뒤 `Booting automatically`를
   본다.
2. 없는 `kernel_path`는 panic이지만 막다른 길이 아니다. 키 하나로 메뉴에 돌아가고, 돌아간 메뉴에는 카운트다운이 없다
   (`Booting automatically`가 로그 전체에 한 번뿐이다). 사람이 고를 때까지 기다린다. 그래서 결정 4의 표에서 new가 "빈 자리"인
   순간에 끊긴 디스크도 사람이 old를 고를 수 있다. 빈 자리를 만나서 기본 엔트리로 계속 다시 시작하는 일은 없다.
3. 메뉴의 아래 줄은 `ARROWS Select  ENTER Boot  E Edit  S Firmware Setup  B Blank Entry`다. `E`(편집기)는 기본으로 켜져 있다
   (`editor_enabled`). 실기에서 cmdline을 손으로 고칠 길이 이미 있는 셈이다(`project_shell_config.md`의 "실기에서 limine 메뉴로
   토큰을 적는 것").

## 비목표

1. legacy 보관(세 번째 세대). 사용자가 뺐다(2026-11-01). 256MiB ESP에는 크기로도 안 들어갔다(확인 3). 1GiB(결정 8)에는 들어가지만 뺀 결정은 그대로다.
2. 자동 롤백 · boot counting. Limine에 재료가 없다(확인 1). 필요해지면 UEFI `BootNext`와 init의 "부팅 성공" 확정을 묶는 다음
   서브프로젝트다.
3. 실행 중인 시스템에서 슬롯을 바꾸는 명령(`tars-install --rollback` 같은 것). 갱신은 지금처럼 ISO로 뜬 기계에서만 한다.
4. 이미 설치된 디스크의 ESP 키우기, ESP와 이미지 파티션 가르기. 새 설치는 결정 8이 1GiB로 키운다. 이미 설치된 디스크는 파티션을
   옮겨야 하므로 갱신으로 하지 않고 `--wipe`에 맡긴다. 이미지를 p3의 큰 FAT로 옮기는 길(XBOOTLDR식)은 한 벌이 1GiB ESP에도 두 벌
   안 들어갈 만큼 커질 때 연다. 그보다 먼저 쓸 손잡이는 initrd 꼬리의 무선 firmware(`firmware.cpio.gz`, 45MB)다.
5. 네트워크로 받는 갱신, Secure Boot용 경로 hash(`CONFIG.md`의 `#<blake2b>`).

## 위험

1. vfat는 저널이 없다. 단계마다 `sync`해도 rename 도중 전원이 나가면 디렉터리 항목이 깨질 수 있다. 그때는 지금과 같다 — ISO로
   다시 갱신한다.
2. ESP 넘침. 결정 8 이전에 설치된 256MiB ESP에서는 한 벌이 약 125MB를 넘으면 두 벌이 안 들어간다(지금 102MB). 1GiB ESP에서는
   그 문턱이 약 500MB다. 검사 없이 회전하면 1단계에서 old를 지운 뒤 4단계의 복사가 `ENOSPC`로 죽는다. 그러면 new는 반쪽이고 old는
   이미 없어서, 결정 4의 "엔트리 하나는 뜬다"가 깨지는 유일한 길이 된다. 그래서 회전 전에 `ESP의 빈 자리 + old 슬롯의 크기 ≥ 매체의
   두 파일 크기`인지 보고, 모자라면 아무것도 지우지 않고 멈춘다(DI의 "디스크를 건드리기 전에 본다"와 같은 원칙). 판정은
   `disk.rotation`(검사 20)과, 호스트가 mtools로 채운 ESP의 부팅 3a(판정 19a)다.
3. 실기의 3초. 부팅마다 늦어진다. 길게 느껴지면 값만 줄인다(`0.5`도 된다).
