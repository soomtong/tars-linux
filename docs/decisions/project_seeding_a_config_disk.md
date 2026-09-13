# 설정 디스크를 미리 굽는다 — `debugfs`

NW-M2(2026-09-13)에서 정했다. 체인이 게스트에 설정을 주는 방법이 지금까지 둘
뿐이었고 둘 다 대가가 있었는데, 셋째 길이 그 갈림을 없앴다.

## 무엇을 하는가

`debugfs`는 마운트도 loop 장치도 특권도 없이 ext2 이미지에 파일을 쓴다.
이미지 파일을 파일로 읽고 쓸 뿐이다.

```bash
truncate -s 16M net.img
mkfs.ext2 -F -q -m 0 -L tars-net net.img
printf 'net=dhcp\n' > /tmp/c.conf
debugfs -w -R "write /tmp/c.conf tars.conf" net.img
```

`Allocated inode: 12`가 나오면 들어간 것이고 `debugfs -R "cat tars.conf"`로
읽어 확인한다. 실물이 `net/make_disk.sh`다.

`e2fsprogs`에 들어 있어서 따로 받을 것이 없다 — 이 저장소는 `mkfs.ext2`를
이미 쓰고 있었고(`config/make_disk.sh`) 같은 패키지다.

## 왜 이것이 값을 하는가

체인이 `tars.conf`의 키를 시험하려면 게스트가 그 파일을 읽어야 한다. 그
파일을 주는 길이 둘이었다.

| 무엇 | cmdline | 디스크 + 타이핑 | 디스크 + `debugfs` |
|---|---|---|---|
| 부팅 수 | 하나 | 둘 | 하나 |
| 타이핑 | 없음 | 백 키 남짓 | 없음 |
| `tars.conf`의 키를 읽는가 | 아니다 | 그렇다 | 그렇다 |

마지막 줄이 핵심이다. cmdline으로 주면 게이트가 증명하는 것과 사람이 쓰는
길이 갈린다 — "설정 파일의 키인데 체인은 파일로 안 준다"가 된다. 타이핑으로
쓰면 부팅이 둘로 늘고 그만큼 게이트가 길어진다(`config` 체인이 부팅 아홉인
이유가 그 비용의 누적이다).

특권이 안 드는 것도 조건이다. 이 게이트는 아무 특권 없이 도는 성질을 갖고
있고(그래서 NW가 tap 대신 SLIRP를 골랐다), loop 마운트는 그것을 버리는 일이다.

## 언제 쓰나

체인이 게스트에 "처음부터 있어야 하는 파일"을 주어야 할 때. 설정에 한정되지
않는다 — 라벨 접두사가 `tars-`이면 `storage.zig`가 잡는다(`LABEL_PREFIX`,
RM-M2).

쓰지 않을 자리도 분명하다. 부팅 뒤에 바뀌는 것을 보려는 체인은 여전히
타이핑으로 고쳐야 한다. `config` 체인의 2차 부팅이 그 자리다 — "고치고
재부팅하면 남는다"를 증명하려면 게스트 안에서 고치는 과정 자체가 판정이다.

관련: [[project_config_persistence]] · [[project_gate_chain_composition]] ·
[[project_real_machine]]
