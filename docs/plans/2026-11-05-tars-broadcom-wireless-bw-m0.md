# BW-M0 — MacBookAir4,1 내장 무선(brcmsmac)

> lead가 직접 넣었다(코드 0줄). design은 `docs/specs/2026-11-05-tars-broadcom-wireless-design.md`.

## Task

1. `kernel/.config`: `CONFIG_BRCMSMAC=y` → 빌드 → `cp kernel/build/.config kernel/.config`(되접기 16줄: `BRCMUTIL` · `BCMA` · `BCMA_HOST_PCI` ·
   `BCMA_DRIVER_PCI` · `CORDIC`과 not set 줄).
2. `kernel/guest_firmware.sh`: Broadcom 블록 두 줄.
3. `wifi/check.sh` 검사 1: 심볼 `BCMA` · `BRCMSMAC`, 별칭 둘(`bcma` PCI 4353 · `brcmsmac` bcma 0812 rev 17).

## 결과 (2026-11-05)

- 커널 표: `bcma.alias=pci:v000014E4d00004353…`(4331 · 43a0도), `brcmsmac.alias=bcma:m04BFid0812rev17cl*`(rev 11 · 18도),
  `brcmsmac.firmware=` 둘.
- 루트 게이트 결과는 completed 행과 release 기억에.
