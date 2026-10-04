# WL-M1 — 커널이 무선을 알고 initrd가 firmware를 싣는다

> 사용자가 2026-09-28에 결정을 전부 위임해서 plan을 먼저 쓰지 않고 실행한 기록으로
> 쓴다. 측정 하네스는 `/tmp/wl/`이고 저장소에 안 들어갔다.

Goal: WL design 결정 1~3을 커밋한다 — 무선 스택과 네 계열의 PCIe 드라이버 · hwsim(라디오 0이
기본) · 목록으로 고른 firmware를 initrd 꼬리에.

## 바뀐 것

| 파일 | 무엇 |
|---|---|
| `kernel/.config` | M0이 해소한 모양 그대로(+388 −13, 지운 13줄은 "is not set" 주석과 머리 주석) |
| `kernel/guest_firmware.sh` | 목록 74줄. `<출처>/<tarball 안 경로>:<initrd 안 경로>`. 데이터만 |
| `kernel/vendor_firmware.sh` | tarball 둘을 `kernel/src/firmware/`에 받고 sha256 확인, 목록대로 골라 `firmware.cpio.gz`. 목록과 자기 해시로 스탬프 |
| `kernel/make_initrd.sh` | 시작에서 `vendor_firmware.sh`, 끝에서 `cat firmware.cpio.gz >> initrd.cpio` |
| `tools/check.sh` | 검사 1b — 꼬리의 바이트 대조와 cpio 안의 목록 |

## 확인

- `boot` 체인 — 86MB initrd가 ISO · limine BIOS로 뜬다(실측 10).
- `tools` 체인 — 검사 1b가 "74 files". mutation: 이어 붙이는 줄을 뺀 사본으로 덮으면 1b만
  빨갛다(실측 11).
- `nic` · `net` 체인 — 모든 부팅에 생기는 `hwsim0`이 판정을 안 바꾼다.
- 위험 5 — `MemAvailable` 309MB → 213MB(실측 12).
