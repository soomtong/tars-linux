---
name: project_wireless
description: "노트북 내장 무선을 켠 서브프로젝트(WL-M0~M3, 2026-09-28). PCIe 네 계열 드라이버와 linux-firmware에서 고른 firmware 74개가 initrd 꼬리에 붙고, /config/wpa_supplicant.conf가 있으면 init이 tars-wifi(→ exec wpa_supplicant)를 감독하며, 늦은 인터페이스는 dhcpcd hook이 interface_add로 넘긴다. 게이트는 mac80211_hwsim — 열일곱번째 체인 wifi/check.sh"
metadata:
  node_type: memory
  type: project
---

# 무선 (WL)

design은 `docs/specs/2026-09-28-tars-wireless-design.md`(결정 7 · 위험 6 · 실측
1~14). 사용자가 2026-09-27에 후보 넷 중 무선을 골랐고, 드라이버는 "노트북형으로 넓게",
자격 증명은 "wpa_supplicant 원래 형식 파일", 데몬은 "init이 감독"을 골랐다. 2026-09-28에
나머지 결정을 전부 위임하고 자러 갔다 — M0 이후의 결정은 Claude가 했다.

무엇이 섰나.

- `kernel/.config` — `CFG80211` · `MAC80211` · `RFKILL`, Intel(iwlwifi mvm · mld) · Realtek
  (rtw88 넷 · rtw89 여섯) · MediaTek(MT7921E · MT7925E) · Qualcomm(ath11k PCI · ath12k),
  `MAC80211_HWSIM`, `CONFIG_CMDLINE="mac80211_hwsim.radios=0"`. 이 커널에 crypto 층이
  처음 들어왔다(`CONFIG_CRYPTO=y` — WPA2의 CCMP).
- `kernel/guest_firmware.sh`(목록 74) · `kernel/vendor_firmware.sh`(받고 · 확인하고 · 골라
  cpio). `make_initrd.sh`의 마지막 줄이 그 cpio를 이어 붙인다. initrd 47MB → 86MB.
- `init/src/wifi.zig` · `kernel/wifi/tars-wifi` · `kernel/dhcpcd-hooks/10-tars-wifi`.
- 게스트 도구 넷(wpa_supplicant · wpa_cli · wpa_passphrase · iw)과 새 라이브러리 다섯.
- `wifi/check.sh` — 부팅 셋 · 검사 열.

Why: 대상에 노트북이 있고(`project_target_hardware`) 요즘 노트북에는 유선 포트가 드물다.
무선이 없으면 NW부터 DS까지의 네트워크 기능이 동글 없이는 전부 꺼져 있었다.

How to apply:

- 이 서브프로젝트의 모양은 WN · TD · DS가 세운 방향 그대로다 — 어려운 일은 도구가 하고
  init은 배관만 한다. 연결은 wpa_supplicant, 주소는 dhcpcd(carrier가 서면 스스로 받는다).
  우리가 새로 쓴 것은 "파일이 있으면 감독 목록에 넣는다"와 "늦은 인터페이스를 넘긴다"
  둘이다.
- argv를 init이 못 짓는 데몬은 wrapper 셸이 짓고 `exec`한다. exec을 빼면 연결은 똑같이
  서고 pid 대조만 틀린다(M3 mutation) — DS의 `-B`와 같은 교훈이다(lessons 61).
- Debian 빌드에 무엇이 켜져 있는지는 짐작하지 말고 도움말 문자열로 본다 — `-M`이 없었다.
- firmware 이름은 `modules.builtin.modinfo`가 말한다. 단 iwlwifi는 요청 순서를 따라
  고른다(lessons 63). 커널이나 linux-firmware를 올리면 iwlwifi 줄을 다시 고른다.
- 게이트 전용 커널 드라이버는 모듈이 없어도 넣을 수 있다 — 내장 cmdline으로 기본값을
  끄고 체인이 뒤에 덮는다. 그리고 "파라미터를 안 준 부팅"을 반드시 하나 둔다. 그 부팅만이
  기본값을 지킨다(M3 mutation 3에서 부팅 A · B는 초록이었다).
- 판정에 쓸 줄은 콘솔에 앵커 없이 grep한다(lessons 68).

관련: [[project_wired_nic]] · [[project_daemon_supervision]] · [[project_service_control]] ·
[[project_target_hardware]] · [[feedback_boot_never_blocks]] · [[project_measuring_tool_cost]]
