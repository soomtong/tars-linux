---
name: project_config_fs_ext2
description: "/config는 ext2이고 ext4가 아니다(CP-M0 결정, 2026-11-02에 다시 따짐) — 저널이 지킬 자리를 MS_SYNCHRONOUS와 rename 교체가 이미 지키고, 1GiB에 파일 수백이라 extent·htree·fsck가 걸리지 않는다. 사용자 데이터가 /config에 살기 시작하거나 sync 마운트가 체감되면 ext4로 간다"
metadata:
  type: project
---

# `/config`는 ext2다 — ext4가 아닌 이유와 ext4로 갈 때

CP-M0(2026-08-14)이 ext2를 골랐고(design "1. virtio-blk + ext2"), 2026-11-02에
사용자가 "실기에 설치해 운영하면 ext4가 더 보편적이지 않나"를 물어 다시
따졌다. 결론은 유지다. 보편성 기준으로는 ext4가 맞지만, `/config`는 범용
루트가 아니라 "작고, 드물게 쓰고, 동기 마운트에 원자적 교체"라는 특수한
자리라서 ext4가 더해 주는 것이 걸리지 않는다.

## 어디에 쓰이나

- QEMU 체인과 USB 설정 스틱: 파티션 없이 디스크 전체가 ext2 하나.
  `mkfs.ext2 -d`로 파일을 담아 굽는다(measurements 34).
- 설치된 디스크(`tars-install`): GPT p1은 1GiB ESP(FAT32 `TARS-BOOT`),
  p2는 1GiB ext2 `tars-config`. `install.zig`가 `mke2fs -t ext2`로 만든다.
- `main.zig`가 `MS_SYNCHRONOUS | MS_NOSUID | MS_NODEV`로 `/config`에 붙인다.
  커널은 `CONFIG_EXT2_FS=y`만 켜고 EXT4는 꺼져 있다.

## ext4가 더해 주는 것 넷을 이 워크로드에 대 보면

| ext4의 장점 | `/config`에서 | 판단 |
|---|---|---|
| 저널링 | `MS_SYNCHRONOUS`라 write·rename이 돌아온 때 이미 디스크에 있고, `tars.conf`는 `.tars.conf.new`에 쓴 뒤 `rename`으로 교체한다(config_cli 결정 5). 종료는 `filesystems synced`를 찍고 내려간다 | 저널이 막을 "메타데이터 반쯤 쓰인 상태"를 응용 계층이 이미 막는다 |
| extent | 큰 파일이 없다. 설정 · rc · 히스토리 · 서비스 스크립트 · 키 | 안 걸린다 |
| htree 디렉터리 인덱스 | 파일 수백을 넘지 않는다 | 안 걸린다. 오히려 ext2의 `getdents64`가 만든 순서를 돌려주는 성질(measurements 57)에 서비스 순서 실측이 기대고 있다 |
| 빠른 fsck | 1GiB ext2의 fsck는 몇 초다 | 큰 디스크에서 ext2가 괴로운 이유가 여기선 안 생긴다 |

## ext2를 유지해서 얻는 것

- 투명성. 저널 없이 superblock · inode · 블록 비트맵만으로 돌아서 "커널이
  어디까지 책임지는가"를 따라가기 쉽다. 이 재시작의 목표가 속도가 아니라
  이해다(`CLAUDE.md`).
- `storage.zig`가 오프셋 1024의 superblock에서 `s_volume_name`을 직접 읽어
  라벨을 찾는다. ext4도 같은 자리라 바꿔도 깨지지는 않지만, 지금 코드가
  ext2 레이아웃을 전제로 설명되어 있다.
- 호스트의 탈출로와 게이트 도구(`debugfs` · `mkfs.ext2 -d`,
  [[project_seeding_a_config_disk]])가 e2fsprogs라 ext4로 가도 그대로지만,
  바꿔서 얻는 이득이 없다.
- 커널 크기. `CONFIG_EXT4_FS`는 jbd2를 끌어와 ext2 드라이버보다 눈에 띄게
  크다. 부팅 시간을 재는 게이트가 있어 공짜가 아니다.

## ext4로 갈 때

요구가 바뀌면 간다. 세 신호 중 하나면 다시 연다.

1. `/config`에 사용자 데이터(문서 · 녹음 · 대용량 로그)가 살기 시작한다.
2. 쓰기가 잦아져 `sync` 마운트의 비용이 체감된다(저널 + 비동기로 바꾸는 쪽이
   맞아진다).
3. 설정 파티션을 수십 GiB로 키운다.

전환은 작다. 커널 config 한 줄, `install.zig`의 `mke2fs -t ext2`와
`main.zig`의 `mountFs(..., "ext2", ...)` 문자열, `config_edit_test`의 mounts
줄, 게이트의 `mounted ext2 at /config` 판정 문구. ext4 드라이버는 ext2
이미지도 마운트하므로 이미 설치된 디스크와의 호환은 깨지지 않는다.

관련: [[project_config_persistence]] · [[project_disk_install]] ·
[[project_seeding_a_config_disk]]
