# WL-M2 — init이 wpa_supplicant를 감독하고 hook이 늦은 인터페이스를 넣는다

> 사용자가 2026-09-28에 결정을 전부 위임해서 plan을 먼저 쓰지 않고 실행한 기록으로
> 쓴다. 확인 부팅의 하네스는 `/tmp/wl/m2.sh` · `m2.probe`이고 저장소에 안 들어갔다.

Goal: WL design 결정 4 · 5(M0 뒤에 고친 모양)를 커밋한다.

## 바뀐 것

| 파일 | 무엇 |
|---|---|
| `init/src/wifi.zig` | `CONF_PATH` · `WIFI_PATH` · `WIFI_ARGV` · `wants(net, mounted, conf)` — 넣지 않을 때도 이유 한 줄 |
| `init/src/wifi_test.zig` · `init/build.zig` | `wants`의 네 갈래 |
| `init/src/services.zig` · `services_test.zig` | 예약 이름 셋째 `wpa_supplicant` |
| `init/src/main.zig` | `want_wifi`와 dhcpcd 앞 칸 |
| `kernel/wifi/tars-wifi` | `phy80211`로 세고 `wpa_supplicant -g -O -c -i … -N …`를 exec. 줄 `tars-wifi: wpa_supplicant on …` |
| `kernel/dhcpcd-hooks/10-tars-wifi` | `PREINIT` · `ifwireless=1` · 파일이 있으면 배경에서 `interface_add`, 소켓이 없을 때만 0.5초 × 20. 줄 `tars-wifi: handed … to wpa_supplicant` |
| `kernel/make_initrd.sh` | 위 둘을 `/usr/lib/tars/`(0755)와 hook 디렉터리(0644)에 |
| `kernel/guest_tools.sh` | 층 12 — wpa_supplicant · wpa_cli · wpa_passphrase · iw |
| `devcontainer/Dockerfile` | 층 12의 패키지 아홉. hostapd · busybox는 게이트 전용 |

## 확인

- `zig build test` — `wifi_test`의 네 줄과 `services_test`의 예약 이름.
- 제품 initrd 부팅 하나(실측 13) — pid가 곧 wpa_supplicant, lease, `country KR`,
  `tars-service restart`, 시작 중 사라진 인터페이스(255 → 되살아남)와 잡은 뒤 사라진
  인터페이스(같은 pid).

늦은 인터페이스의 hook 경로(`handed … to wpa_supplicant`)는 이 부팅에서 안 밟았다 — wifi
체인(M3)이 `phy`를 되돌려서 밟는다. M0 실측 7이 측정용 hook으로 같은 경로를 이미 봤다.
