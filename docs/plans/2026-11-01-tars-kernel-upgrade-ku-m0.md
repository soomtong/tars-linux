# KU-M0 — ESP에 이미지 슬롯 둘, 1GiB ESP

Goal: `tars-install`의 갱신이 부트 파일을 제자리에서 덮지 않고 회전시킨다. 지금 이미지는 `boot/old/`로 가고 새 이미지가 `boot/`에
들어간다. ESP의 `limine.conf`에는 엔트리가 둘 생기고 메뉴가 3초 보인다. 새 설치의 ESP는 1GiB다(KU design 결정 1~8). 호스트 테스트와
install 체인(`DC-M2`)의 판정으로 보고, 루트 게이트로 닫는다. 커널 버전은 그대로다(KU-M1의 몫).

Architecture: 순수 규칙은 `disk.zig`에 둔다 — ESP conf 짓기(`espConf`), 회전 여부 판정(`rotation`), 회전의 순서(`ROTATION`),
최소 디스크 크기, 계획 문구. `install.zig`는 그 규칙대로 p1을 붙이고 읽고 쓴다. 회전 순서가 "어느 순간에 끊겨도 엔트리 하나는
뜬다"를 지키는지는, `ROTATION` 배열을 작은 상태 모형 위에서 한 단계씩 돌리는 호스트 테스트가 본다.

---

## 착수 전에 확정한 것

2026-11-01, HEAD `ff9390c`.

1. `build_info`(버전 글자)는 지금 `exe_mod`(init)와 `config_cli_mod`(tars-config)에만 붙는다(`init/build.zig` 111~114줄). `install_mod`에
   `addOptions("build_info", build_info)` 한 줄을 더한다. `build_info`가 만들어지는 자리가 `install_mod`보다 뒤라서, 그 줄은 114줄
   다음에 둔다.
2. Zig 0.17의 `std.os.linux`에는 `rename` · `unlink`가 있고 `statfs`가 없다. 빈 자리는 `linux.syscall2(.statfs, …)`로 직접 읽는다.
   x86_64의 `struct statfs`는 120바이트이고 `f_bsize`가 8바이트째, `f_bavail`이 32바이트째다. 구조체는 `install.zig`에 두고, 크기를
   `comptime` 단언으로 못 박는다.
3. 게스트에는 `mount` · `dd`가 없다. 이것은 제품 이미지의 일이라 게이트를 위해 넣지 않는다. 컨테이너에도 mtools가 없었는데, 그것은
   우리 Dockerfile이 안 넣었을 뿐이다(사용자 지적, 2026-11-01). Task 0이 `mtools`를 넣는다. 그러면 체인이 호스트에서 디스크 이미지의
   p1에 직접 파일을 넣고 지울 수 있다. "ESP가 모자라 멈춘다"는 갈래를 진짜 FAT로 만드는 부팅 3a와 판정 19a가 그 위에 선다. 같은
   Dockerfile 변경에 `netcat-openbsd` · `iproute2`(`ss`)를 함께 넣는다. 그동안 perl로 우회해 온 것들이고, 이미지를 다시 굽는 일은
   한 번에 모으는 편이 싸다. `python3`는 넣지 않는다(크고, perl로 모자란 적이 없다).
4. install 체인에는 64MiB scratch 디스크(`nvme1n1`, 4Kn)가 이미 부팅 1에 붙어 있다. 최소 크기 거절 판정(4d)을 거기서 한다. 설치
   대상이 아니므로 판정이 틀려도 지워지는 것은 scratch뿐이다.
5. 갱신 계획의 첫 줄 `already has TARS. p1 will be updated, p2 (your settings) is kept.`는 그대로 둔다. 판정 12가 이 문자열을 보고, 뜻도
   여전히 맞다. 슬롯을 말하는 줄은 그 아래에 더한다.
6. Limine 메뉴 고르기는 KU design "M0 전에 잰 것"대로 한다. escape를 걷은 로그에 `Booting automatically`가 보이면 `ESC [ B`, 0.5초
   뒤 `CR`. 날 로그로 보면 영영 안 보인다.
7. 체인 시간. 지난 루트 게이트에서 `DC-M2`는 105초였다. 부팅 둘(3a · 4b)과 Limine 대기 3초 × 넷이 더해져 약 150초가 된다.
8. p1의 자리. sfdisk의 기본 정렬로 첫 파티션은 2048섹터(1MiB)에서 시작한다. mtools는 `-i "$DISK@@1M"`로 그 자리의 FAT를 연다.
   Task 0에서 진짜 설치된 이미지에 `mdir`을 쳐서 이 오프셋을 확인한다.

## Task 0: 컨테이너에 mtools · netcat · iproute2

- `devcontainer/Dockerfile`의 `apt-get install` 목록에 `mtools` · `netcat-openbsd` · `iproute2`. 태그는 Dockerfile의 해시라
  새 태그가 된다(GI-M0).
- 로컬: `docker rmi tars-devcontainer && make container`. ghcr에 새 태그가 아직 없으므로 굽는 쪽으로 간다. 걸린 시간을 결과 절에 적는다.
- 확인: 컨테이너에서 `mcopy --version` · `nc -h` · `ss -V`. 그리고 install 체인을 돌린 뒤 남은 디스크 이미지(또는 같은 배치로 손으로
  만든 이미지)에 `mdir -i <img>@@1M ::/boot`를 쳐서 확정 8을 본다.
- 옛 기록을 고친다. `docs/guides/measurements.md` 41(없다 → Task 0에서 넣었다), `docs/guides/dead-ends.md` 197(`nc`로 monitor —
  이제 된다), `docs/decisions/project_reserved_ports.md`의 "`nc` · `ss` · `python3`가 없다" 줄.
- CI: main에 push하면 `checks.yml`이 새 태그를 굽고 올린다. 그 run이 초록인지 본다.

## 정한 값과 문자열

게이트와 호스트 테스트가 보는 글자라 여기서 못 박는다.

| 무엇 | 값 |
| --- | --- |
| p1 | `size=1GiB, type=uefi, name=TARS-BOOT` |
| 최소 디스크 | `MIN_DISK_BYTES = 2 GiB + 2 MiB` (p1 · p2에 GPT 앞 1MiB 정렬과 뒤 헤더) |
| 슬롯 파일 | `bzImage` · `initrd.cpio` · `version` (`version`은 맨 마지막에 쓴다) |
| old 자리 | `boot/old/` (`ESP_DIRS`에 더한다) |
| 여유 | `need = 매체의 bzImage + initrd.cpio + 1 MiB` (conf · version · FAT 클러스터 반올림) |
| ESP conf | `timeout: 3`. 엔트리 `/TARS <new>`와 `/TARS <old> (old)`. old의 경로는 `boot():/boot/old/`, cmdline 끝에 `tars.slot=old` |
| 너무 작은 디스크 | `<path> is <size>; TARS needs more than 2 GiB` (`complain`, YES 전). `formatSize`는 10진 버림이라 최소 크기와 2GB 스틱이 둘 다 `2 GB`로 찍힌다 — 그래서 최소는 글자로 적는다 |
| 빈 자리 줄 | `tars-install: p1 has <free> bytes free and <old> bytes in boot/old; the new image needs <need>` |
| 자리 부족 | `tars-install: p1 has no room for two images; nothing was changed.` (YES 전) |
| 회전 줄 | `tars-install: moving the current image to boot/old` 뒤 파일마다 `  boot/<f> -> boot/old/<f>` |
| 계획의 슬롯 줄(회전) | `  boot/      <- TARS <new>` · `  boot/old/  <- TARS <cur>, for the boot menu if the new one fails` |
| 계획의 슬롯 줄(덮기) | `  boot/      <- TARS <new>` · `  boot/old/  <- left as it is` |

## Task 1: 순수 층과 호스트 테스트 (`disk.zig` · `disk_test.zig`)

`disk.zig`.

- `SFDISK_SCRIPT`의 p1을 `1GiB`로. `MIN_DISK_BYTES`와 `bigEnough(bytes) bool`.
- `OLD_DIR = "boot/old"`, `SLOT_FILES = .{ "bzImage", "initrd.cpio", "version" }`, `ESP_DIRS`에 `"boot/old"`(부모 `boot` 뒤).
- `espConf(out, iso_conf, new_ver, old_ver: ?[]const u8) ?[]const u8`로 넓힌다. ISO conf를 첫 엔트리(`/`로 시작하는 줄) 앞의 전역 줄과
  엔트리 블록으로 가른다.
  - 전역 줄: `timeout:` 줄의 값을 `3`으로 바꾼다. 없으면 null(ISO conf에는 늘 있다 — 없으면 모양이 바뀐 것이다).
  - 엔트리 블록을 한 번 쓴다. 제목 줄은 `/TARS <new_ver>`, `cmdline:` 줄 끝에 `tars.installed`(지금 규칙 그대로).
  - `old_ver`가 있으면 빈 줄 하나 뒤 블록을 다시 쓴다. 제목은 `/TARS <old_ver> (old)`, `kernel_path:` · `module_path:` 값의
    `boot():/boot/`를 `boot():/boot/old/`로, `cmdline:` 끝에 `tars.installed tars.slot=old`.
  - 엔트리가 둘 이상인 ISO conf는 null. 지금의 null 조건(cmdline 줄 없음 · 버퍼 모자람)은 그대로다.
- `pub const Rotation = enum { rotate, overwrite, no_room };`
  `rotation(has_version: bool, free: u64, old_slot: u64, cur_slot: u64, need: u64) Rotation`.
  `has_version`이면 `free + old_slot >= need`일 때 rotate, 아니면 no_room. 없으면 `free + cur_slot >= need`일 때 overwrite(지금 이미지를
  `O_TRUNC`로 덮으므로 그 몫이 풀린다), 아니면 no_room(design 결정 5, 위험 2).
- `pub const Op = enum { clear_old, write_conf, move_to_old, copy_new, write_version };`
  `pub const ROTATION = [_]Op{ .clear_old, .write_conf, .move_to_old, .copy_new, .write_version };` — `install.zig`가 이 배열을 그대로
  돈다. 순서의 이유(design 결정 4)를 주석에 옮긴다.
- `planLines`에 `new_ver: []const u8, cur_ver: ?[]const u8, rot: Rotation`을 더한다. 새 설치의 p1 줄은 `1 GiB`. 갱신은 첫 줄 뒤에 위
  표의 슬롯 줄 둘(`rot`이 rotate면 회전, overwrite면 덮기). 갱신 줄에서 크기 칸은 뺀다(256MiB로 깔린 디스크도 갱신되기 때문이다).

`disk_test.zig`.

- 10을 고친다: 엔트리 하나(old 없음)의 결과 전체를 글자로 비교하고, 둘(old 있음)의 결과도 글자로 비교한다. 다시 넣으면 표지가 두 번
  안 붙는다는 지금의 검사는 엔트리 하나 쪽에 남긴다. 엔트리가 둘인 ISO conf · `timeout:` 없는 conf가 null인지.
- 16을 고친다: 새 설치의 `1 GiB`, 갱신 회전 · 덮기의 슬롯 줄.
- 19 새로: `bigEnough` — 2 GiB는 거짓, `MIN_DISK_BYTES`는 참, 64 MiB · 2,000,000,000(2GB 스틱)은 거짓.
- 20 새로: `rotation`의 여섯 칸 — 버전 있음 × (자리 넉넉 · old를 비워야 맞음 · 모자람), 버전 없음 × (맞음 · cur를 덮어야 맞음 ·
  모자람). 경계는 `==`에서 참.
- 21 새로: 끊김 모형. 상태는 `new_dir`(current · empty · partial · next) · `old_dir`(prev · empty · current) · `conf`(one · two)이고,
  엔트리가 뜨는 조건은 "conf에 있고 그 디렉터리가 partial도 empty도 아니다"다. 시작 상태 둘(옛 conf 엔트리 하나 + old 없음,
  엔트리 둘 + old 있음)에서 `ROTATION`을 한 op씩 적용하고, 매 op 뒤와 `copy_new` 도중(new = partial)에 뜨는 엔트리가 하나 이상인지
  본다. 끝 상태는 new = next, old = current, conf = two.

판정: `zig build test`(컨테이너).

## Task 2: `install.zig` · `build.zig`

- `build.zig`: 확정 1.
- `isInstalled`: `boot/bzImage` 또는 `boot/old/bzImage`가 있으면 참(design 결정 6).
- `readSlots(p1) ?Slots`: p1을 읽기 전용으로 붙여 `boot/version` · `boot/old/version`의 글자(개행 벗김), 두 슬롯의 bzImage + initrd
  크기, `statfs`의 `f_bavail * f_bsize`를 읽고 뗀다(확정 2). `isInstalled`와 같은 붙이기 · `defer umount` 모양이다.
- `install()`의 순서. YES 전에 다 판단한다(DI의 "디스크를 건드리기 전에 본다").
  1. 새 설치(`!update`)면 `bigEnough`가 거짓일 때 위 표의 줄로 거절, 1을 돌려준다.
  2. 갱신이면 `readSlots` → `need` 계산 → `rotation`. no_room이면 빈 자리 줄과 자리 부족 줄을 찍고 1. 아니면 빈 자리 줄을 찍는다.
  3. `planLines`. `prepareConf`는 이 판단 뒤로 옮겨 old 버전을 안다 — rotate면 old = `boot/version`의 글자, overwrite면
     `boot/old/version`의 글자(있을 때), 새 설치면 null.
- `fillEsp`를 둘로 가른다. 새 설치는 지금 길(디렉터리 · 복사) 뒤 `boot/version`을 마지막에 쓴다. 갱신 rotate는 `disk.ROTATION`을
  돌며 op마다 `linux.sync()`.
  - `clear_old`: `boot/old/`의 슬롯 파일 셋을 unlink(없으면 넘어간다, ENOENT만).
  - `write_conf`: `limine.conf.tmp`에 쓰고 `rename`. vfat가 있는 이름 위로의 rename을 거부하면(EEXIST) unlink 뒤 rename으로 바꾸고
    plan 결과 절에 적는다.
  - `move_to_old`: 셋을 rename, 줄마다 `  boot/<f> -> boot/old/<f>`.
  - `copy_new`: bzImage · initrd.cpio를 지금의 `copyFile`로. EFI 파일도 이 자리에서 덮는다(Limine 판이 바뀔 수 있다).
  - `write_version`: `build_info.version` + `\n`.
  갱신 overwrite는 지금의 갱신 길에 conf 쓰기만 위 규칙(old 엔트리는 `boot/old/version`이 있을 때)으로, 끝에 version.
- 복사 줄 `  boot/version <n> bytes`도 찍는다(판정 5 · 12가 센다).
- `fillEsp` 위의 "제자리에서 덮는다 … 이번에는 안 한다" 주석을 이 milestone의 사실로 고친다.

판정: `make quick`, 컨테이너의 `zig build`.

## Task 3: install 체인 (`install/check.sh`)

- 디스크는 그대로 `truncate -s 2G` → `3G`, 46줄 주석을 1GiB + 1GiB로.
- `boot_guest`에 `PICK_OLD=1`일 때만 도는 갈래: 대기 루프에서 `clean | grep -aqF "Booting automatically"`가 처음 참이면 0.5초 뒤
  `printf '\033[B' >&4`, 0.5초 뒤 `printf '\r' >&4`. 보냈는지 한 줄 찍는다.
- 판정 4d(부팅 1, 4c 뒤): `tars-install /dev/nvme1n1 --yes` → `is 67 MB; TARS needs more than 2 GiB`, `writing the partition table` 줄이
  없고, 다시 찍은 목록에서 `nvme1n1`이 여전히 `foreign (gpt)`.
- 판정 5 · 12의 복사 목록에 `boot/version`.
- 판정 18(부팅 2): cmdline에 `tars.slot=old`가 없다. escape를 걷은 로그에 `Booting automatically`가 있고(timeout 3이 ESP에 갔다)
  `(old)`가 없다(첫 설치는 엔트리 하나).
- 부팅 3a 새로(2 뒤, 3 앞) — ESP가 모자라는 갱신. QEMU가 꺼진 사이 호스트에서 `mdir -i "$DISK@@1M" ::/`의 끝 줄로 빈 바이트를 읽고,
  `빈 자리 - 50 MB` 크기의 파일(`fallocate`)을 `mcopy`로 p1의 `::/ku-fill`에 넣는다. 그러면 빈 자리는 약 50MB이고 old는 0이라 `need`
  (약 103MB)에 모자란다. `boot_guest 3a -cdrom ../out/tars.iso`. 판정 19a: `tars-install /dev/nvme0n1 --yes` → 빈 자리 줄과
  `p1 has no room for two images; nothing was changed.`, `moving the current image` · `copying the boot files` 줄이 없다. 끈 뒤
  호스트에서 `mdel`로 `ku-fill`을 지우고, `mdir`로 `boot/version`이 그대로이고 `boot/old`가 비어 있는지 본다(아무것도 안 바뀌었다).
  `mcopy`는 약 900MB를 실제로 쓰므로 이미지가 그만큼 커진다. `$WORK`와 함께 지워진다.
- 판정 19(부팅 3, 12 뒤): 빈 자리 줄이 있고, 빈 자리 · need는 0보다 크고 old는 0이다(첫 갱신이라 `boot/old`가 비어 있다). `moving the current image to boot/old`와 `-> boot/old/` 줄 셋.
  계획에 `boot/old/  <- TARS `.
- 판정 20(부팅 4, 13 · 14 앞): cmdline에 `tars.slot=old`가 없고, 걷은 로그에 `(old)`가 있다(메뉴에 엔트리 둘).
- 부팅 4b 새로(4 뒤, 5 앞): `PICK_OLD=1 boot_guest 4b`. 판정 21: cmdline에 `tars.installed`와 `tars.slot=old`, `$WANT_DISK`,
  `loaded /config/tars.conf`, 마커 `di-marker:kept`(old도 같은 설정을 본다).
- 판정 22(부팅 6, 16 뒤): 걷은 로그에 `(old)`가 없다(`--wipe`가 슬롯을 비웠다).
- 판정 21a(부팅 5, `--wipe` 앞) — 회전 3단계 뒤에 끊긴 디스크(design 결정 6). 4b를 끈 뒤 호스트에서 `mdel -i "$DISK@@1M"
  ::/boot/bzImage`. 부팅 5에서 `tars-install` 목록이 `nvme0n1`을 여전히 `TARS installed`로 읽는다(`boot/old/bzImage`가 있어서다).
  그 다음은 지금의 `--wipe`(판정 15)이고, 이 디스크도 통째로 다시 깔린다.
- 머리 주석의 부팅 표에 3a · 4b를 더한다.

## Task 4: 문서

- `docs/guides/running-tars.md` 216줄의 256MiB를 1GiB로. 그 절 끝에 "새 버전이 안 뜰 때" 단락: 부팅 메뉴가 3초 보이고, 아래
  화살표로 `(old)`를 골라 Enter. new의 커널을 못 읽으면 `Press a key to return to menu.`에서 키 하나로 메뉴에 돌아간다. old로 뜬 것은 그
  부팅 한 번뿐이다.
- KU design: 위험 2의 마지막 문장에 "부팅 3a가 mtools로 채운 ESP에서 본다"를, "게이트" 절을 Task 3의 판정 번호로 고친다.
- `docs/guides/key-files.md`의 `install.zig` · `disk.zig` 항목에 슬롯 한 줄.

## Task 5: 판정

1. `make quick`.
2. install 체인 단독(`make check CHAIN=install`, 약 2분 30초).
3. mutation 일곱(되돌린다). 1~3은 호스트 테스트가 잡아야 하고, 4~7은 `zig build test` 줄을 `if false`로 바꾼 `check.sh` 사본을
   마운트해 install 체인으로 보낸다.
   1. `ROTATION`에서 `write_conf`와 `move_to_old`를 바꿈 → 검사 21(엔트리 하나에서 시작한 쪽).
   2. `rotation`이 `has_version`을 안 봄 → 검사 20.
   3. `rotation`이 `old_slot`을 안 더함 → 검사 20.
   4. old 엔트리에 `tars.slot=old`를 안 붙임 → 판정 21.
   5. `bigEnough` 검사를 뺌 → 판정 4d(`writing the partition table`이 나온다).
   6. `install.zig`가 `rotation`의 no_room을 무시하고 회전함 → 판정 19a(`moving the current image`가 나오고 복사가 `ENOSPC`로 실패).
      호스트 검사 20은 이것을 못 잡는다 — 판정은 맞는데 쓰는 쪽이 안 따르는 퇴행이라서다.
   7. `isInstalled`가 `boot/bzImage`만 봄 → 판정 21a(목록이 `foreign (gpt)`).
4. 루트 게이트(`make gate`, 약 11분).

## Task 6: 닫기 (M0)

- plan 끝에 "결과" 절: 이미지 굽는 시간(Task 0), 체인 시간, 게이트 시간 · 줄 수, mutation 결과, rename 위 덮어쓰기(Task 2)의 실제 동작.
- KU design `Status:`에 KU-M0 끝남. 서브프로젝트는 KU-M1이 남아 있으므로 `completed.md` · 기억 파일 · 소개 페이지는 아직이다.
- `HANDOFF.md`: 다음 일은 KU-M1 plan.
- 사용자가 결과를 승인한 뒤 commit.

## 하지 않는 것

- 실기 확인. 메뉴 3초가 손에 맞는지, 실제 펌웨어에서 old가 뜨는지는 사용자 몫이다(HANDOFF "사용자가 확인할 것"에 한 줄).
- 끊김의 실제 재현(전원을 끊는 것). 결정 4의 표는 검사 21의 모형이 본다. 끊긴 뒤의 디스크 모양 하나(결정 6)는 판정 21a가 mtools로
  만들어 본다.
