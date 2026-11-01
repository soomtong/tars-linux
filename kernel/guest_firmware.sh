# shellcheck shell=bash
# 게스트에 들어가는 무선 · 소리 firmware 목록 — 이것이 사는 유일한 자리다(WL-M1 ·
# AU-M3).
#
# guest_tools.sh와 같은 규칙이다. 데이터만 있고 명령을 하나도 실행하지 않는다.
# vendor_firmware.sh가 이 목록대로 tarball에서 파일을 골라 cpio를 만들고,
# tools/check.sh가 같은 파일을 source해서 initrd 안에 전부 있는지 센다.
#
# ── 형식 ────────────────────────────────────────────────────────────────
#
#   <출처>/<tarball 안의 경로> : <initrd 안의 경로>      (둘 다 앞의 / 없이)
#
# 출처는 셋이다. linux-firmware와 wireless-regdb, 그리고 sof-bin(AU-M3) — 버전은
# 이름에 없고 vendor_firmware.sh에 있다. 둘이 다를 수 있는 것이 이 형식의 이유다(WL
# design 실측 3). iwlwifi 파일은 tarball 안에서 intel/iwlwifi/에 있는데 드라이버는
# /lib/firmware/ 맨 위를 찾는다. linux-firmware의 설치 스크립트가 WHENCE의
# `Link:` 줄로 그 링크를 만들고 tarball에는 링크가 없다. ath11k의
# WCN6855/hw2.1도 hw2.0을 가리키는 `Link:`다 — 그래서 같은 원본이 두 번 나온다.
#
# ── 무엇을 넣었나 ───────────────────────────────────────────────────────
#
# kernel/.config가 켠 PCIe 무선 드라이버(WL design 결정 1)와 USB 동글(UW design
# 결정 1)이 찾는 것. USB 동글이 새로 찾는 것은 rtw88의 `…a_fw.bin` 셋뿐이다.
# UB(층 B 다섯 + rtl8xxxu, UB design 결정 1)가 21개를 더했다 — UB 실측 2.
# BT(BT design 결정 2)가 Bluetooth 157개를 더했다 — Intel 84 · Realtek 31 · MediaTek 4 ·
# Qualcomm 38, 합 약 32MB(gzip 뒤 약 23MB, BT-M0 실측 3). 규칙은 배열 끝 Bluetooth 블록의 주석에 있다.
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
# ncm865). 서버용(ath11k QCN9074). `rtlwifi/rtl8723bu_bt.bin`은 이 릴리스에 없고
# 6.18의 rtl8xxxu가 요청하지도 않는 죽은 이름이다(UB 위험 3). `mt7662u.bin` ·
# `htc_9271.fw`는 이름이 비슷해도 6.18이 요청하지 않는다(UB 비목표 4).
# Bluetooth(BT-M1)에서 뺀 것 — btrtl 표의 이름 50 중 이 릴리스에 없는 19(거의 `*_config.bin`,
# 드라이버가 없으면 그냥 넘어간다 — `rtl8723b_config` · `rtl8723d_config` · `rtl8852bs_*` 등),
# tarball에만 있고 6.18이 요청하지 않는 `rtl8192ee_fw` · `rtl8192eu_fw` · `rtl8812ae_fw`,
# 무선을 안 싣는 칩의 MediaTek 둘(`MT7902` · `MT7927`의 `MT6639`), Broadcom `brcm/BCM*.hcd`
# (BT 비목표 4).
#
# ── 커널이나 linux-firmware를 올릴 때 ───────────────────────────────────
#
# 이 목록은 커널 6.18.42와 linux-firmware-20260916에 대해 고른 것이다(Bluetooth 블록은
# 6.18.60, BT-M1). Intel BT는 iwlwifi처럼 hw_variant 표가 커널에 있어 커널을 올리면 다시 본다. 커널을
# 6.18.60으로 올릴 때 iwlwifi의 API_MAX와 트리 전체의 MODULE_FIRMWARE를 대조해
# 그대로 두었다(KU-M1 plan 확정 4 · 5). 둘 중 하나를 올리면 iwlwifi 줄을
# 다시 골라야 한다 — 커널의 최대 API가 오르면 더 새 파일을 받기 시작하고,
# 옛 파일이 linux-firmware에서 빠지면 여기 줄이 가리키는 것이 없어진다.
# 뒤쪽은 vendor_firmware.sh가 빌드 때 잡는다(없는 파일이면 죽는다). 앞쪽은
# 아무도 안 잡는다 — 옛 파일로도 칩은 뜬다.

# shellcheck disable=SC2034
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

  # Realtek — rtw88 · rtw89 · rtl8xxxu(UB)
  linux-firmware/rtw88/rtw8723d_fw.bin:lib/firmware/rtw88/rtw8723d_fw.bin
  linux-firmware/rtw88/rtw8812a_fw.bin:lib/firmware/rtw88/rtw8812a_fw.bin
  linux-firmware/rtw88/rtw8814a_fw.bin:lib/firmware/rtw88/rtw8814a_fw.bin
  linux-firmware/rtw88/rtw8821a_fw.bin:lib/firmware/rtw88/rtw8821a_fw.bin
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
  linux-firmware/rtlwifi/rtl8188eufw.bin:lib/firmware/rtlwifi/rtl8188eufw.bin
  linux-firmware/rtlwifi/rtl8188fufw.bin:lib/firmware/rtlwifi/rtl8188fufw.bin
  linux-firmware/rtlwifi/rtl8192cufw_A.bin:lib/firmware/rtlwifi/rtl8192cufw_A.bin
  linux-firmware/rtlwifi/rtl8192cufw_B.bin:lib/firmware/rtlwifi/rtl8192cufw_B.bin
  linux-firmware/rtlwifi/rtl8192cufw_TMSC.bin:lib/firmware/rtlwifi/rtl8192cufw_TMSC.bin
  linux-firmware/rtlwifi/rtl8192eu_nic.bin:lib/firmware/rtlwifi/rtl8192eu_nic.bin
  linux-firmware/rtlwifi/rtl8192fufw.bin:lib/firmware/rtlwifi/rtl8192fufw.bin
  linux-firmware/rtlwifi/rtl8710bufw_SMIC.bin:lib/firmware/rtlwifi/rtl8710bufw_SMIC.bin
  linux-firmware/rtlwifi/rtl8710bufw_UMC.bin:lib/firmware/rtlwifi/rtl8710bufw_UMC.bin
  linux-firmware/rtlwifi/rtl8723aufw_A.bin:lib/firmware/rtlwifi/rtl8723aufw_A.bin
  linux-firmware/rtlwifi/rtl8723aufw_B.bin:lib/firmware/rtlwifi/rtl8723aufw_B.bin
  linux-firmware/rtlwifi/rtl8723aufw_B_NoBT.bin:lib/firmware/rtlwifi/rtl8723aufw_B_NoBT.bin
  linux-firmware/rtlwifi/rtl8723bu_nic.bin:lib/firmware/rtlwifi/rtl8723bu_nic.bin

  # MediaTek — mt7921e(MT7921 · MT7922) · mt7925e · mt7601u · mt76x0u · mt76x2u(UB)
  # 맨 위 이름 셋(mt7601u.bin · mt7662.bin · mt7662_rom_patch.bin)은 WHENCE의 Link:라
  # 출처는 mediatek/ 아래다. mt76x0u는 mt7610e.bin을 먼저 찾고 없으면 mt7610u.bin이다.
  linux-firmware/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin:lib/firmware/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin
  linux-firmware/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin:lib/firmware/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin
  linux-firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin:lib/firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin
  linux-firmware/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin:lib/firmware/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin
  linux-firmware/mediatek/WIFI_MT7961_patch_mcu_1a_2_hdr.bin:lib/firmware/mediatek/WIFI_MT7961_patch_mcu_1a_2_hdr.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7961_1.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1.bin
  linux-firmware/mediatek/WIFI_RAM_CODE_MT7961_1a.bin:lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1a.bin
  linux-firmware/mediatek/mt7601u.bin:lib/firmware/mt7601u.bin
  linux-firmware/mediatek/mt7610e.bin:lib/firmware/mediatek/mt7610e.bin
  linux-firmware/mediatek/mt7610u.bin:lib/firmware/mediatek/mt7610u.bin
  linux-firmware/mediatek/mt7662.bin:lib/firmware/mt7662.bin
  linux-firmware/mediatek/mt7662_rom_patch.bin:lib/firmware/mt7662_rom_patch.bin

  # Ralink — rt2800usb(UB)
  linux-firmware/rt2870.bin:lib/firmware/rt2870.bin

  # Qualcomm · Atheros — ath11k · ath12k · ath9k_htc(UB)
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
  linux-firmware/ath9k_htc/htc_7010-1.4.0.fw:lib/firmware/ath9k_htc/htc_7010-1.4.0.fw
  linux-firmware/ath9k_htc/htc_9271-1.4.0.fw:lib/firmware/ath9k_htc/htc_9271-1.4.0.fw

  # 규제 db — cfg80211
  wireless-regdb/regulatory.db:lib/firmware/regulatory.db
  wireless-regdb/regulatory.db.p7s:lib/firmware/regulatory.db.p7s

  # ── 소리 — Intel SOF(AU-M3) ─────────────────────────────────────────────
  #
  # 내장 디지털 마이크(DMIC)가 있는 Intel 노트북은 커널이 HDA 대신 SOF로 간다
  # (sound/hda/core/intel-dsp-config.c). 그때 firmware나 topology가 없으면 SOF는
  # HDA로 돌아오지 않고 카드를 아예 안 만든다 — 스피커까지 조용해진다. 그래서 커널이
  # 켠 세대마다 그 이름이 여기 있어야 하고, audio 체인의 검사 1이 커널 안의 이름
  # (`sof-*.ri`)을 전부 이 목록에서 찾는다.
  #
  # firmware. 세대마다 기본 IPC가 정한 자리 하나다 — CNL ~ RPL은 IPC3이라
  # intel/sof/, MTL 이후는 IPC4라 intel/sof-ipc4/<세대>/. sof-bin 안의 링크(cfl ·
  # cml → cnl, rpl → adl, arl → mtl)는 실체를 가리켜 적는다(tar -T가 링크의 대상을
  # 안 따라간다). intel-signed만 넣는다 — community 서명은 Chromebook과 UP 보드의
  # 것이다(sof-pci-dev.c). LNL은 topology가 부르는 DRC 모듈이 따로 있다(UUID 이름).
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cnl.ri
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cfl.ri
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cml.ri
  sof-bin/sof/intel-signed/sof-icl.ri:lib/firmware/intel/sof/sof-icl.ri
  sof-bin/sof/intel-signed/sof-jsl.ri:lib/firmware/intel/sof/sof-jsl.ri
  sof-bin/sof/intel-signed/sof-tgl.ri:lib/firmware/intel/sof/sof-tgl.ri
  sof-bin/sof/intel-signed/sof-tgl-h.ri:lib/firmware/intel/sof/sof-tgl-h.ri
  sof-bin/sof/intel-signed/sof-ehl.ri:lib/firmware/intel/sof/sof-ehl.ri
  sof-bin/sof/intel-signed/sof-adl.ri:lib/firmware/intel/sof/sof-adl.ri
  sof-bin/sof/intel-signed/sof-adl-s.ri:lib/firmware/intel/sof/sof-adl-s.ri
  sof-bin/sof/intel-signed/sof-adl-n.ri:lib/firmware/intel/sof/sof-adl-n.ri
  sof-bin/sof/intel-signed/sof-adl.ri:lib/firmware/intel/sof/sof-rpl.ri
  sof-bin/sof/intel-signed/sof-adl-s.ri:lib/firmware/intel/sof/sof-rpl-s.ri
  sof-bin/sof-ipc4/mtl/intel-signed/sof-mtl.ri:lib/firmware/intel/sof-ipc4/mtl/sof-mtl.ri
  sof-bin/sof-ipc4/mtl/intel-signed/sof-mtl.ri:lib/firmware/intel/sof-ipc4/arl/sof-arl.ri
  sof-bin/sof-ipc4/arl-s/intel-signed/sof-arl-s.ri:lib/firmware/intel/sof-ipc4/arl-s/sof-arl-s.ri
  sof-bin/sof-ipc4/lnl/intel-signed/sof-lnl.ri:lib/firmware/intel/sof-ipc4/lnl/sof-lnl.ri
  sof-bin/sof-ipc4/ptl/intel-signed/sof-ptl.ri:lib/firmware/intel/sof-ipc4/ptl/sof-ptl.ri
  sof-bin/sof-ipc4/wcl/intel-signed/sof-wcl.ri:lib/firmware/intel/sof-ipc4/wcl/sof-wcl.ri
  sof-bin/sof-ipc4-lib/lnl/intel-signed/drc.llext:lib/firmware/intel/sof-ipc4-lib/lnl/B36EE4DA-006F-47F9-A06D-FECBE2D8B6CE.bin
  #
  # topology. HDA 코덱 + DMIC 노트북은 범용 machine(skl_hda_dsp_generic) 하나가 받고,
  # 커널이 이름을 "sof-hda-generic" + (HDMI 코덱뿐이면 "-idisp") + (DMIC 수 N이면
  # "-Nch")로 짓는다(sof/intel/hda.c). 그 이름들만 넣는다. IPC3은 intel/sof-tplg,
  # MTL · ARL은 intel/sof-ace-tplg, LNL 이후는 intel/sof-ipc4-tplg다 — 뒤 둘은 sof-bin
  # 안에서 같은 디렉터리라 같은 원본이 두 자리로 간다. IPC4 쪽에는 3ch가 없다.
  # SoundWire 코덱(sof_sdw)의 기계별 topology 수백은 넣지 않는다(AU-M3 비목표).
  sof-bin/sof-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic.tplg
  sof-bin/sof-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-3ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-3ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg
  # ── Bluetooth(BT-M1) ────────────────────────────────────────────────────
  #
  # 계열마다 규칙이 다르다(BT design 결정 2 · 실측 2). Realtek(btrtl)은 소스의 칩 표
  # (ic_id_table의 fw_name · cfg_name)가 이름을 다 적고 있어 거기서 셌다 — MODULE_FIRMWARE
  # 50줄은 그 표의 부분집합이다. tarball에 없는 이름(주로 *_config.bin — 드라이버가
  # 없으면 그냥 넘어간다)은 뺐다. Intel(btintel · btintel_pcie)은 iwlwifi처럼 실행 중에
  # 이름을 만든다(ibt-<hw>-<rev>.sfi · .ddc, ROM 세대는 ibt-hw-37.x*.bseq) —
  # MODULE_FIRMWARE는 넷뿐이라 modinfo로 못 세고, hw_variant 표(WP ~ Scorpious Peak)가
  # 우리가 싣는 iwlwifi 세대 전부와 겹쳐 intel/ibt-*를 전부 넣는다. 이것이 initrd 증분의
  # 거의 전부다(BT design 위험 1). MediaTek(btmtk)은 BT_RAM_CODE_MT<칩>_1_<rev>_hdr.bin을
  # 만들고, 우리가 무선을 싣는 MT7921(7961 · 7961 1a) · MT7922 · MT7925만 넣는다(MT7902 ·
  # MT7927은 무선을 안 싣는 칩, MT7927의 것은 이 릴리스에 없기도 하다). Qualcomm(btusb)은
  # qca/rampatch_usb_<id>.bin · nvm_usb_<id>*.bin을 만든다 — nvm은 보드 변형이라 다 넣는다.
  #
  # Realtek — btrtl
  linux-firmware/rtl_bt/rtl8723a_fw.bin:lib/firmware/rtl_bt/rtl8723a_fw.bin
  linux-firmware/rtl_bt/rtl8723b_fw.bin:lib/firmware/rtl_bt/rtl8723b_fw.bin
  linux-firmware/rtl_bt/rtl8723bs_config.bin:lib/firmware/rtl_bt/rtl8723bs_config.bin
  linux-firmware/rtl_bt/rtl8723bs_fw.bin:lib/firmware/rtl_bt/rtl8723bs_fw.bin
  linux-firmware/rtl_bt/rtl8723cs_xx_config.bin:lib/firmware/rtl_bt/rtl8723cs_xx_config.bin
  linux-firmware/rtl_bt/rtl8723cs_xx_fw.bin:lib/firmware/rtl_bt/rtl8723cs_xx_fw.bin
  linux-firmware/rtl_bt/rtl8723d_fw.bin:lib/firmware/rtl_bt/rtl8723d_fw.bin
  linux-firmware/rtl_bt/rtl8761a_fw.bin:lib/firmware/rtl_bt/rtl8761a_fw.bin
  linux-firmware/rtl_bt/rtl8761b_config.bin:lib/firmware/rtl_bt/rtl8761b_config.bin
  linux-firmware/rtl_bt/rtl8761b_fw.bin:lib/firmware/rtl_bt/rtl8761b_fw.bin
  linux-firmware/rtl_bt/rtl8761bu_config.bin:lib/firmware/rtl_bt/rtl8761bu_config.bin
  linux-firmware/rtl_bt/rtl8761bu_fw.bin:lib/firmware/rtl_bt/rtl8761bu_fw.bin
  linux-firmware/rtl_bt/rtl8761cu_config.bin:lib/firmware/rtl_bt/rtl8761cu_config.bin
  linux-firmware/rtl_bt/rtl8761cu_fw.bin:lib/firmware/rtl_bt/rtl8761cu_fw.bin
  linux-firmware/rtl_bt/rtl8821a_fw.bin:lib/firmware/rtl_bt/rtl8821a_fw.bin
  linux-firmware/rtl_bt/rtl8821c_config.bin:lib/firmware/rtl_bt/rtl8821c_config.bin
  linux-firmware/rtl_bt/rtl8821c_fw.bin:lib/firmware/rtl_bt/rtl8821c_fw.bin
  linux-firmware/rtl_bt/rtl8821cs_fw.bin:lib/firmware/rtl_bt/rtl8821cs_fw.bin
  linux-firmware/rtl_bt/rtl8822b_config.bin:lib/firmware/rtl_bt/rtl8822b_config.bin
  linux-firmware/rtl_bt/rtl8822b_fw.bin:lib/firmware/rtl_bt/rtl8822b_fw.bin
  linux-firmware/rtl_bt/rtl8822cs_config.bin:lib/firmware/rtl_bt/rtl8822cs_config.bin
  linux-firmware/rtl_bt/rtl8822cs_fw.bin:lib/firmware/rtl_bt/rtl8822cs_fw.bin
  linux-firmware/rtl_bt/rtl8822cu_fw.bin:lib/firmware/rtl_bt/rtl8822cu_fw.bin
  linux-firmware/rtl_bt/rtl8851bu_fw.bin:lib/firmware/rtl_bt/rtl8851bu_fw.bin
  linux-firmware/rtl_bt/rtl8852au_fw.bin:lib/firmware/rtl_bt/rtl8852au_fw.bin
  linux-firmware/rtl_bt/rtl8852btu_fw.bin:lib/firmware/rtl_bt/rtl8852btu_fw.bin
  linux-firmware/rtl_bt/rtl8852bu_fw.bin:lib/firmware/rtl_bt/rtl8852bu_fw.bin
  linux-firmware/rtl_bt/rtl8852cu_fw_v2.bin:lib/firmware/rtl_bt/rtl8852cu_fw_v2.bin
  linux-firmware/rtl_bt/rtl8852cu_fw.bin:lib/firmware/rtl_bt/rtl8852cu_fw.bin
  linux-firmware/rtl_bt/rtl8922au_config.bin:lib/firmware/rtl_bt/rtl8922au_config.bin
  linux-firmware/rtl_bt/rtl8922au_fw.bin:lib/firmware/rtl_bt/rtl8922au_fw.bin
  # Intel — btintel · btintel_pcie
  linux-firmware/intel/ibt-0040-0041.ddc:lib/firmware/intel/ibt-0040-0041.ddc
  linux-firmware/intel/ibt-0040-0041.sfi:lib/firmware/intel/ibt-0040-0041.sfi
  linux-firmware/intel/ibt-0040-1020.ddc:lib/firmware/intel/ibt-0040-1020.ddc
  linux-firmware/intel/ibt-0040-1020.sfi:lib/firmware/intel/ibt-0040-1020.sfi
  linux-firmware/intel/ibt-0041-0041.ddc:lib/firmware/intel/ibt-0041-0041.ddc
  linux-firmware/intel/ibt-0041-0041.sfi:lib/firmware/intel/ibt-0041-0041.sfi
  linux-firmware/intel/ibt-0093-0041.ddc:lib/firmware/intel/ibt-0093-0041.ddc
  linux-firmware/intel/ibt-0093-0041.sfi:lib/firmware/intel/ibt-0093-0041.sfi
  linux-firmware/intel/ibt-0093-0291.ddc:lib/firmware/intel/ibt-0093-0291.ddc
  linux-firmware/intel/ibt-0093-0291.sfi:lib/firmware/intel/ibt-0093-0291.sfi
  linux-firmware/intel/ibt-0093-1050.ddc:lib/firmware/intel/ibt-0093-1050.ddc
  linux-firmware/intel/ibt-0093-1050.sfi:lib/firmware/intel/ibt-0093-1050.sfi
  linux-firmware/intel/ibt-0093-4150.ddc:lib/firmware/intel/ibt-0093-4150.ddc
  linux-firmware/intel/ibt-0093-4150.sfi:lib/firmware/intel/ibt-0093-4150.sfi
  linux-firmware/intel/ibt-00a0-0041-iml.sfi:lib/firmware/intel/ibt-00a0-0041-iml.sfi
  linux-firmware/intel/ibt-00a0-0041-pci.ddc:lib/firmware/intel/ibt-00a0-0041-pci.ddc
  linux-firmware/intel/ibt-00a0-0041-pci.sfi:lib/firmware/intel/ibt-00a0-0041-pci.sfi
  linux-firmware/intel/ibt-00a0-01a1-iml.sfi:lib/firmware/intel/ibt-00a0-01a1-iml.sfi
  linux-firmware/intel/ibt-00a0-01a1-pci.ddc:lib/firmware/intel/ibt-00a0-01a1-pci.ddc
  linux-firmware/intel/ibt-00a0-01a1-pci.sfi:lib/firmware/intel/ibt-00a0-01a1-pci.sfi
  linux-firmware/intel/ibt-00a0-0291-iml.sfi:lib/firmware/intel/ibt-00a0-0291-iml.sfi
  linux-firmware/intel/ibt-00a0-0291-pci.ddc:lib/firmware/intel/ibt-00a0-0291-pci.ddc
  linux-firmware/intel/ibt-00a0-0291-pci.sfi:lib/firmware/intel/ibt-00a0-0291-pci.sfi
  linux-firmware/intel/ibt-0180-0041.ddc:lib/firmware/intel/ibt-0180-0041.ddc
  linux-firmware/intel/ibt-0180-0041.sfi:lib/firmware/intel/ibt-0180-0041.sfi
  linux-firmware/intel/ibt-0180-1050.ddc:lib/firmware/intel/ibt-0180-1050.ddc
  linux-firmware/intel/ibt-0180-1050.sfi:lib/firmware/intel/ibt-0180-1050.sfi
  linux-firmware/intel/ibt-0180-4150.ddc:lib/firmware/intel/ibt-0180-4150.ddc
  linux-firmware/intel/ibt-0180-4150.sfi:lib/firmware/intel/ibt-0180-4150.sfi
  linux-firmware/intel/ibt-0190-0041-iml.sfi:lib/firmware/intel/ibt-0190-0041-iml.sfi
  linux-firmware/intel/ibt-0190-0041-pci.ddc:lib/firmware/intel/ibt-0190-0041-pci.ddc
  linux-firmware/intel/ibt-0190-0041-pci.sfi:lib/firmware/intel/ibt-0190-0041-pci.sfi
  linux-firmware/intel/ibt-0190-0041-usb.ddc:lib/firmware/intel/ibt-0190-0041-usb.ddc
  linux-firmware/intel/ibt-0190-0041-usb.sfi:lib/firmware/intel/ibt-0190-0041-usb.sfi
  linux-firmware/intel/ibt-0190-0291-iml.sfi:lib/firmware/intel/ibt-0190-0291-iml.sfi
  linux-firmware/intel/ibt-0190-0291-pci.ddc:lib/firmware/intel/ibt-0190-0291-pci.ddc
  linux-firmware/intel/ibt-0190-0291-pci.sfi:lib/firmware/intel/ibt-0190-0291-pci.sfi
  linux-firmware/intel/ibt-0190-0291-usb.ddc:lib/firmware/intel/ibt-0190-0291-usb.ddc
  linux-firmware/intel/ibt-0190-0291-usb.sfi:lib/firmware/intel/ibt-0190-0291-usb.sfi
  linux-firmware/intel/ibt-0190-0291.ddc:lib/firmware/intel/ibt-0190-0291.ddc
  linux-firmware/intel/ibt-0190-0291.sfi:lib/firmware/intel/ibt-0190-0291.sfi
  linux-firmware/intel/ibt-0291-0291.ddc:lib/firmware/intel/ibt-0291-0291.ddc
  linux-firmware/intel/ibt-0291-0291.sfi:lib/firmware/intel/ibt-0291-0291.sfi
  linux-firmware/intel/ibt-1040-0041.ddc:lib/firmware/intel/ibt-1040-0041.ddc
  linux-firmware/intel/ibt-1040-0041.sfi:lib/firmware/intel/ibt-1040-0041.sfi
  linux-firmware/intel/ibt-1040-1020.ddc:lib/firmware/intel/ibt-1040-1020.ddc
  linux-firmware/intel/ibt-1040-1020.sfi:lib/firmware/intel/ibt-1040-1020.sfi
  linux-firmware/intel/ibt-11-5.ddc:lib/firmware/intel/ibt-11-5.ddc
  linux-firmware/intel/ibt-11-5.sfi:lib/firmware/intel/ibt-11-5.sfi
  linux-firmware/intel/ibt-1190-0041-iml.sfi:lib/firmware/intel/ibt-1190-0041-iml.sfi
  linux-firmware/intel/ibt-1190-0041-pci.ddc:lib/firmware/intel/ibt-1190-0041-pci.ddc
  linux-firmware/intel/ibt-1190-0041-pci.sfi:lib/firmware/intel/ibt-1190-0041-pci.sfi
  linux-firmware/intel/ibt-1190-0041-usb.ddc:lib/firmware/intel/ibt-1190-0041-usb.ddc
  linux-firmware/intel/ibt-1190-0041-usb.sfi:lib/firmware/intel/ibt-1190-0041-usb.sfi
  linux-firmware/intel/ibt-1190-01a1-iml.sfi:lib/firmware/intel/ibt-1190-01a1-iml.sfi
  linux-firmware/intel/ibt-1190-01a1-pci.ddc:lib/firmware/intel/ibt-1190-01a1-pci.ddc
  linux-firmware/intel/ibt-1190-01a1-pci.sfi:lib/firmware/intel/ibt-1190-01a1-pci.sfi
  linux-firmware/intel/ibt-12-16.ddc:lib/firmware/intel/ibt-12-16.ddc
  linux-firmware/intel/ibt-12-16.sfi:lib/firmware/intel/ibt-12-16.sfi
  linux-firmware/intel/ibt-17-0-1.ddc:lib/firmware/intel/ibt-17-0-1.ddc
  linux-firmware/intel/ibt-17-0-1.sfi:lib/firmware/intel/ibt-17-0-1.sfi
  linux-firmware/intel/ibt-17-16-1.ddc:lib/firmware/intel/ibt-17-16-1.ddc
  linux-firmware/intel/ibt-17-16-1.sfi:lib/firmware/intel/ibt-17-16-1.sfi
  linux-firmware/intel/ibt-18-0-1.ddc:lib/firmware/intel/ibt-18-0-1.ddc
  linux-firmware/intel/ibt-18-0-1.sfi:lib/firmware/intel/ibt-18-0-1.sfi
  linux-firmware/intel/ibt-18-16-1.ddc:lib/firmware/intel/ibt-18-16-1.ddc
  linux-firmware/intel/ibt-18-16-1.sfi:lib/firmware/intel/ibt-18-16-1.sfi
  linux-firmware/intel/ibt-19-0-4.ddc:lib/firmware/intel/ibt-19-0-4.ddc
  linux-firmware/intel/ibt-19-0-4.sfi:lib/firmware/intel/ibt-19-0-4.sfi
  linux-firmware/intel/ibt-20-0-3.ddc:lib/firmware/intel/ibt-20-0-3.ddc
  linux-firmware/intel/ibt-20-0-3.sfi:lib/firmware/intel/ibt-20-0-3.sfi
  linux-firmware/intel/ibt-20-1-3.ddc:lib/firmware/intel/ibt-20-1-3.ddc
  linux-firmware/intel/ibt-20-1-3.sfi:lib/firmware/intel/ibt-20-1-3.sfi
  linux-firmware/intel/ibt-20-1-4.ddc:lib/firmware/intel/ibt-20-1-4.ddc
  linux-firmware/intel/ibt-20-1-4.sfi:lib/firmware/intel/ibt-20-1-4.sfi
  linux-firmware/intel/ibt-hw-37.7.10-fw-1.0.1.2d.d.bseq:lib/firmware/intel/ibt-hw-37.7.10-fw-1.0.1.2d.d.bseq
  linux-firmware/intel/ibt-hw-37.7.10-fw-1.0.2.3.d.bseq:lib/firmware/intel/ibt-hw-37.7.10-fw-1.0.2.3.d.bseq
  linux-firmware/intel/ibt-hw-37.7.10-fw-1.80.1.2d.d.bseq:lib/firmware/intel/ibt-hw-37.7.10-fw-1.80.1.2d.d.bseq
  linux-firmware/intel/ibt-hw-37.7.10-fw-1.80.2.3.d.bseq:lib/firmware/intel/ibt-hw-37.7.10-fw-1.80.2.3.d.bseq
  linux-firmware/intel/ibt-hw-37.7.bseq:lib/firmware/intel/ibt-hw-37.7.bseq
  linux-firmware/intel/ibt-hw-37.8.10-fw-1.10.2.27.d.bseq:lib/firmware/intel/ibt-hw-37.8.10-fw-1.10.2.27.d.bseq
  linux-firmware/intel/ibt-hw-37.8.10-fw-1.10.3.11.e.bseq:lib/firmware/intel/ibt-hw-37.8.10-fw-1.10.3.11.e.bseq
  linux-firmware/intel/ibt-hw-37.8.10-fw-22.50.19.14.f.bseq:lib/firmware/intel/ibt-hw-37.8.10-fw-22.50.19.14.f.bseq
  linux-firmware/intel/ibt-hw-37.8.bseq:lib/firmware/intel/ibt-hw-37.8.bseq
  # MediaTek — btmtk(btusb)
  linux-firmware/mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin:lib/firmware/mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin
  linux-firmware/mediatek/BT_RAM_CODE_MT7961_1a_2_hdr.bin:lib/firmware/mediatek/BT_RAM_CODE_MT7961_1a_2_hdr.bin
  linux-firmware/mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin:lib/firmware/mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin
  linux-firmware/mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin:lib/firmware/mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin
  # Qualcomm — btusb
  linux-firmware/qca/nvm_usb_00000200.bin:lib/firmware/qca/nvm_usb_00000200.bin
  linux-firmware/qca/nvm_usb_00000201.bin:lib/firmware/qca/nvm_usb_00000201.bin
  linux-firmware/qca/nvm_usb_00000300.bin:lib/firmware/qca/nvm_usb_00000300.bin
  linux-firmware/qca/nvm_usb_00000302_eu.bin:lib/firmware/qca/nvm_usb_00000302_eu.bin
  linux-firmware/qca/nvm_usb_00000302.bin:lib/firmware/qca/nvm_usb_00000302.bin
  linux-firmware/qca/nvm_usb_00130200_0104.bin:lib/firmware/qca/nvm_usb_00130200_0104.bin
  linux-firmware/qca/nvm_usb_00130200_0105.bin:lib/firmware/qca/nvm_usb_00130200_0105.bin
  linux-firmware/qca/nvm_usb_00130200_0106.bin:lib/firmware/qca/nvm_usb_00130200_0106.bin
  linux-firmware/qca/nvm_usb_00130200_0107.bin:lib/firmware/qca/nvm_usb_00130200_0107.bin
  linux-firmware/qca/nvm_usb_00130200_0109.bin:lib/firmware/qca/nvm_usb_00130200_0109.bin
  linux-firmware/qca/nvm_usb_00130200_0110.bin:lib/firmware/qca/nvm_usb_00130200_0110.bin
  linux-firmware/qca/nvm_usb_00130200.bin:lib/firmware/qca/nvm_usb_00130200.bin
  linux-firmware/qca/nvm_usb_00130201_010a.bin:lib/firmware/qca/nvm_usb_00130201_010a.bin
  linux-firmware/qca/nvm_usb_00130201_010b.bin:lib/firmware/qca/nvm_usb_00130201_010b.bin
  linux-firmware/qca/nvm_usb_00130201_0303.bin:lib/firmware/qca/nvm_usb_00130201_0303.bin
  linux-firmware/qca/nvm_usb_00130201_gf_010a.bin:lib/firmware/qca/nvm_usb_00130201_gf_010a.bin
  linux-firmware/qca/nvm_usb_00130201_gf_010b.bin:lib/firmware/qca/nvm_usb_00130201_gf_010b.bin
  linux-firmware/qca/nvm_usb_00130201_gf_0303.bin:lib/firmware/qca/nvm_usb_00130201_gf_0303.bin
  linux-firmware/qca/nvm_usb_00130201_gf.bin:lib/firmware/qca/nvm_usb_00130201_gf.bin
  linux-firmware/qca/nvm_usb_00130201.bin:lib/firmware/qca/nvm_usb_00130201.bin
  linux-firmware/qca/nvm_usb_00190200_0104.bin:lib/firmware/qca/nvm_usb_00190200_0104.bin
  linux-firmware/qca/nvm_usb_00190200_0106.bin:lib/firmware/qca/nvm_usb_00190200_0106.bin
  linux-firmware/qca/nvm_usb_00190200_0108.bin:lib/firmware/qca/nvm_usb_00190200_0108.bin
  linux-firmware/qca/nvm_usb_00190200_0109.bin:lib/firmware/qca/nvm_usb_00190200_0109.bin
  linux-firmware/qca/nvm_usb_00190200_010a.bin:lib/firmware/qca/nvm_usb_00190200_010a.bin
  linux-firmware/qca/nvm_usb_00190200_010c.bin:lib/firmware/qca/nvm_usb_00190200_010c.bin
  linux-firmware/qca/nvm_usb_00190200_010e.bin:lib/firmware/qca/nvm_usb_00190200_010e.bin
  linux-firmware/qca/nvm_usb_00190200_0110.bin:lib/firmware/qca/nvm_usb_00190200_0110.bin
  linux-firmware/qca/nvm_usb_00190200_0111.bin:lib/firmware/qca/nvm_usb_00190200_0111.bin
  linux-firmware/qca/nvm_usb_00190200_0112.bin:lib/firmware/qca/nvm_usb_00190200_0112.bin
  linux-firmware/qca/nvm_usb_00190200.bin:lib/firmware/qca/nvm_usb_00190200.bin
  linux-firmware/qca/rampatch_usb_00000200.bin:lib/firmware/qca/rampatch_usb_00000200.bin
  linux-firmware/qca/rampatch_usb_00000201.bin:lib/firmware/qca/rampatch_usb_00000201.bin
  linux-firmware/qca/rampatch_usb_00000300.bin:lib/firmware/qca/rampatch_usb_00000300.bin
  linux-firmware/qca/rampatch_usb_00000302.bin:lib/firmware/qca/rampatch_usb_00000302.bin
  linux-firmware/qca/rampatch_usb_00130200.bin:lib/firmware/qca/rampatch_usb_00130200.bin
  linux-firmware/qca/rampatch_usb_00130201.bin:lib/firmware/qca/rampatch_usb_00130201.bin
  linux-firmware/qca/rampatch_usb_00190200.bin:lib/firmware/qca/rampatch_usb_00190200.bin
)
