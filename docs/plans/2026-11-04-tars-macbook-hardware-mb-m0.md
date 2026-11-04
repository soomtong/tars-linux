# MB-M0 — 맥북 트랙패드와 SBS 배터리를 커널에

> lead가 직접 넣었다(코드 0줄). design은 `docs/specs/2026-11-04-tars-macbook-hardware-design.md`.

Goal: design 결정 2 · 4. `.config` 두 줄과 `machine/check.sh`의 판정 둘.

## Task

1. `kernel/.config`: `CONFIG_MOUSE_BCM5974=y` · `CONFIG_ACPI_SBS=y`. 빌드 뒤 `diff kernel/.config kernel/build/.config`가 빈다.
   - 되접기가 HP 때 빠뜨린 ext4 줄 여섯을 드러냈다. 정규화는 따로 커밋했다(`Fold kernel config: …`).
2. `machine/check.sh` 부팅 전: `modules.builtin.modinfo`에 `bcm5974.alias=usb:v05ACp0249d` · `…0262d` · `…0290d` ·
   `sbs.alias=acpi*:ACPI0002:`(부분 일치 — 별칭 줄 뒤에 `*dc*…`가 붙는다. 처음 `grep -x`로 써서 거짓 빨강이 났다).
3. `machine/check.sh` 판정 13 뒤: `usbcore: registered new interface driver bcm5974`.

## 결과 (2026-11-04)

- 커널 증분 빌드 24초. 되접기 diff는 켠 두 줄뿐(`POWER_SUPPLY`는 이미 `y`).
- machine 체인 PASS — 등록 줄은 `[0.824048]`.
- mutation: 0290 별칭 줄을 뺀 표를 정적 검사에 먹이자 `FAIL … p0290d`로 잡혔다.
