# 게스트에 들어가는 무선 firmware 목록 — 이것이 사는 유일한 자리다(WL-M1).
#
# guest_tools.sh와 같은 규칙이다. 데이터만 있고 명령을 하나도 실행하지 않는다.
# vendor_firmware.sh가 이 목록대로 tarball에서 파일을 골라 cpio를 만들고,
# tools/check.sh가 같은 파일을 source해서 initrd 안에 전부 있는지 센다.
#
# ── 형식 ────────────────────────────────────────────────────────────────
#
#   <출처>/<tarball 안의 경로> : <initrd 안의 경로>      (둘 다 앞의 / 없이)
#
# 출처는 둘이다. linux-firmware와 wireless-regdb — 버전은 이름에 없고
# vendor_firmware.sh에 있다. 둘이 다를 수 있는 것이 이 형식의 이유다(WL design
# 실측 3). iwlwifi 파일은 tarball 안에서 intel/iwlwifi/에 있는데 드라이버는
# /lib/firmware/ 맨 위를 찾는다. linux-firmware의 설치 스크립트가 WHENCE의
# `Link:` 줄로 그 링크를 만들고 tarball에는 링크가 없다. ath11k의
# WCN6855/hw2.1도 hw2.0을 가리키는 `Link:`다 — 그래서 같은 원본이 두 번 나온다.
#
# ── 무엇을 넣었나 ───────────────────────────────────────────────────────
#
# kernel/.config가 켠 PCIe 무선 드라이버가 찾는 것(WL design 결정 1).
# 드라이버가 찾는 이름은 빌드 산출물 kernel/build/modules.builtin.modinfo의
# `firmware=` 줄이다. 짐작하지 않고 거기서 센다.
#
# iwlwifi는 그 줄을 그대로 쓰면 안 된다. 드라이버가 실행 중에 칩의 MAC ·
# stepping · RF로 접두사를 만들고(iwl_drv_get_fwname_pre), 커널의 최대 API
# 번호부터 아래로 내려가며 요청한다. `c99` 다음은 `101`이다
# (iwl_request_firmware). 그래서 접두사마다 그 순서에서 처음 만나는 실제 파일
# 하나를 골랐다. linux-firmware의 더 새 파일(`c101`~`c107`)은 커널 6.18이 절대
# 요청하지 않는다 — "가장 새 파일"을 넣으면 안 올라가는 파일만 넣는 것이다.
#
# 뺀 것. r8169 · r8152의 Realtek 유선 firmware(WN 비목표 1). 2012년 이전 Intel
# 칩(IWLDVM · iwlegacy를 안 켰다). 받을 번호의 파일이 이 릴리스에 없는 Intel
# 둘(BE201 `bz-b0-wh-b0` · `sc-a0-fm-c0`). 보드별 변형(ath11k nfa765 · ath12k
# ncm865). 서버용(ath11k QCN9074).
#
# ── 커널이나 linux-firmware를 올릴 때 ───────────────────────────────────
#
# 이 목록은 커널 6.18.42와 linux-firmware-20260916에 대해 고른 것이다. 둘 중
# 하나를 올리면 iwlwifi 줄을 다시 골라야 한다 — 커널의 최대 API가 오르면 더
# 새 파일을 받기 시작하고, 옛 파일이 linux-firmware에서 빠지면 여기 줄이
# 가리키는 것이 없어진다. 뒤쪽은 vendor_firmware.sh가 빌드 때 잡는다(없는
# 파일이면 죽는다). 앞쪽은 아무도 안 잡는다 — 옛 파일로도 칩은 뜬다.

GUEST_FIRMWARE=(
  # Intel — iwlwifi
  linux-firmware/intel/iwlwifi/iwlwifi-3160-17.ucode:lib/firmware/iwlwifi-3160-17.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-3168-29.ucode:lib/firmware/iwlwifi-3168-29.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-7260-17.ucode:lib/firmware/iwlwifi-7260-17.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-7265D-29.ucode:lib/firmware/iwlwifi-7265D-29.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-7265-17.ucode:lib/firmware/iwlwifi-7265-17.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-8000C-36.ucode:lib/firmware/iwlwifi-8000C-36.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-8265-36.ucode:lib/firmware/iwlwifi-8265-36.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-9000-pu-b0-jf-b0-46.ucode:lib/firmware/iwlwifi-9000-pu-b0-jf-b0-46.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-9260-th-b0-jf-b0-46.ucode:lib/firmware/iwlwifi-9260-th-b0-jf-b0-46.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode:lib/firmware/iwlwifi-QuZ-a0-hr-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-QuZ-a0-jf-b0-77.ucode:lib/firmware/iwlwifi-QuZ-a0-jf-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-Qu-b0-hr-b0-77.ucode:lib/firmware/iwlwifi-Qu-b0-hr-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-Qu-b0-jf-b0-77.ucode:lib/firmware/iwlwifi-Qu-b0-jf-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-Qu-c0-hr-b0-77.ucode:lib/firmware/iwlwifi-Qu-c0-hr-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-Qu-c0-jf-b0-77.ucode:lib/firmware/iwlwifi-Qu-c0-jf-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-fm-c0.pnvm:lib/firmware/iwlwifi-bz-b0-fm-c0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-fm-c0-101.ucode:lib/firmware/iwlwifi-bz-b0-fm-c0-101.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-gf-a0.pnvm:lib/firmware/iwlwifi-bz-b0-gf-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-gf-a0-100.ucode:lib/firmware/iwlwifi-bz-b0-gf-a0-100.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-hr-b0.pnvm:lib/firmware/iwlwifi-bz-b0-hr-b0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-bz-b0-hr-b0-100.ucode:lib/firmware/iwlwifi-bz-b0-hr-b0-100.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-cc-a0-77.ucode:lib/firmware/iwlwifi-cc-a0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-gl-c0-fm-c0.pnvm:lib/firmware/iwlwifi-gl-c0-fm-c0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-gl-c0-fm-c0-101.ucode:lib/firmware/iwlwifi-gl-c0-fm-c0-101.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-ma-b0-gf4-a0.pnvm:lib/firmware/iwlwifi-ma-b0-gf4-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-ma-b0-gf4-a0-89.ucode:lib/firmware/iwlwifi-ma-b0-gf4-a0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-ma-b0-gf-a0.pnvm:lib/firmware/iwlwifi-ma-b0-gf-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-ma-b0-gf-a0-89.ucode:lib/firmware/iwlwifi-ma-b0-gf-a0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-ma-b0-hr-b0-89.ucode:lib/firmware/iwlwifi-ma-b0-hr-b0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-sc-a0-gf-a0-100.ucode:lib/firmware/iwlwifi-sc-a0-gf-a0-100.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-sc-a0-wh-b0-101.ucode:lib/firmware/iwlwifi-sc-a0-wh-b0-101.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-gf4-a0.pnvm:lib/firmware/iwlwifi-so-a0-gf4-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-gf4-a0-89.ucode:lib/firmware/iwlwifi-so-a0-gf4-a0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-gf-a0.pnvm:lib/firmware/iwlwifi-so-a0-gf-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-gf-a0-89.ucode:lib/firmware/iwlwifi-so-a0-gf-a0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-hr-b0-89.ucode:lib/firmware/iwlwifi-so-a0-hr-b0-89.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-so-a0-jf-b0-77.ucode:lib/firmware/iwlwifi-so-a0-jf-b0-77.ucode
  linux-firmware/intel/iwlwifi/iwlwifi-ty-a0-gf-a0.pnvm:lib/firmware/iwlwifi-ty-a0-gf-a0.pnvm
  linux-firmware/intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode:lib/firmware/iwlwifi-ty-a0-gf-a0-89.ucode

  # Realtek — rtw88 · rtw89
  linux-firmware/rtw88/rtw8723d_fw.bin:lib/firmware/rtw88/rtw8723d_fw.bin
  linux-firmware/rtw88/rtw8821c_fw.bin:lib/firmware/rtw88/rtw8821c_fw.bin
  linux-firmware/rtw88/rtw8822b_fw.bin:lib/firmware/rtw88/rtw8822b_fw.bin
  linux-firmware/rtw88/rtw8822c_fw.bin:lib/firmware/rtw88/rtw8822c_fw.bin
  linux-firmware/rtw88/rtw8822c_wow_fw.bin:lib/firmware/rtw88/rtw8822c_wow_fw.bin
  linux-firmware/rtw89/rtw8851b_fw.bin:lib/firmware/rtw89/rtw8851b_fw.bin
  linux-firmware/rtw89/rtw8852a_fw.bin:lib/firmware/rtw89/rtw8852a_fw.bin
  linux-firmware/rtw89/rtw8852b_fw-1.bin:lib/firmware/rtw89/rtw8852b_fw-1.bin
  linux-firmware/rtw89/rtw8852bt_fw.bin:lib/firmware/rtw89/rtw8852bt_fw.bin
  linux-firmware/rtw89/rtw8852c_fw-2.bin:lib/firmware/rtw89/rtw8852c_fw-2.bin
  linux-firmware/rtw89/rtw8922a_fw-4.bin:lib/firmware/rtw89/rtw8922a_fw-4.bin

  # MediaTek — mt7921e(MT7921 · MT7922) · mt7925e
  linux-firmware/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin:lib/firmware/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin
  linux-firmware/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin:lib/firmware/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin
  linux-firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin:lib/firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin
  linux-firmware/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin:lib/firmware/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin
  linux-firmware/mediatek/WIFI_MT7961_patch_mcu_1a_2_hdr.bin:lib/firmware/mediatek/WIFI_MT7961_patch_mcu_1a_2_hdr.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7961_1.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7961_1a.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1a.bin

  # Qualcomm — ath11k · ath12k
  linux-firmware/ath11k/QCA6390/hw2.0/amss.bin:lib/firmware/ath11k/QCA6390/hw2.0/amss.bin
  linux-firmware/ath11k/QCA6390/hw2.0/board-2.bin:lib/firmware/ath11k/QCA6390/hw2.0/board-2.bin
  linux-firmware/ath11k/QCA6390/hw2.0/m3.bin:lib/firmware/ath11k/QCA6390/hw2.0/m3.bin
  linux-firmware/ath11k/WCN6855/hw2.0/amss.bin:lib/firmware/ath11k/WCN6855/hw2.0/amss.bin
  linux-firmware/ath11k/WCN6855/hw2.0/board-2.bin:lib/firmware/ath11k/WCN6855/hw2.0/board-2.bin
  linux-firmware/ath11k/WCN6855/hw2.0/m3.bin:lib/firmware/ath11k/WCN6855/hw2.0/m3.bin
  linux-firmware/ath11k/WCN6855/hw2.0/regdb.bin:lib/firmware/ath11k/WCN6855/hw2.0/regdb.bin
  linux-firmware/ath12k/WCN7850/hw2.0/amss.bin:lib/firmware/ath12k/WCN7850/hw2.0/amss.bin
  linux-firmware/ath12k/WCN7850/hw2.0/board-2.bin:lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
  linux-firmware/ath12k/WCN7850/hw2.0/m3.bin:lib/firmware/ath12k/WCN7850/hw2.0/m3.bin
  linux-firmware/ath11k/WCN6855/hw2.0/amss.bin:lib/firmware/ath11k/WCN6855/hw2.1/amss.bin
  linux-firmware/ath11k/WCN6855/hw2.0/board-2.bin:lib/firmware/ath11k/WCN6855/hw2.1/board-2.bin
  linux-firmware/ath11k/WCN6855/hw2.0/m3.bin:lib/firmware/ath11k/WCN6855/hw2.1/m3.bin
  linux-firmware/ath11k/WCN6855/hw2.0/regdb.bin:lib/firmware/ath11k/WCN6855/hw2.1/regdb.bin

  # 규제 db — cfg80211
  wireless-regdb/regulatory.db:lib/firmware/regulatory.db
  wireless-regdb/regulatory.db.p7s:lib/firmware/regulatory.db.p7s
)
