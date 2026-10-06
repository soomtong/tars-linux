---
name: feedback_network_default_stays_off
description: tars.conf seed의 net · ntp 기본값은 off로 둔다(2026-10-06 사용자 결정). dhcp로 뒤집는 편집과 세 체인 통과까지 갔다가, 사용자가 "비활성화 상태로 두고 활성화하는 방법을 담은 문서를 남기자"고 해서 되돌렸다. 켜는 길은 running-tars.md의 "네트워크와 시계" 절이다
metadata:
  type: feedback
---

2026-10-06 사용자가 QEMU에서 받아쓰기(VD)를 보려다 `out/tars-config.img`의
`tars.conf`가 `net=off` · `ntp=off`인 것을 보고 처음에는 "기본 seed 값에 net,
ntp 활성화 하자"고 했다. `config.zig`의 구조체 기본값 둘을 `dhcp`로 바꾸고
(구조체 기본값이 곧 seed다 — `save()`가 거기서 만든다) `config_test` ·
`service` 체인의 `ntp=off` 전제를 고쳐 config · tools · service 세 체인이
초록이었고 루트 게이트를 돌리던 중에, 사용자가 "잠시만... 비활성화 상태로
두고 활성화 하는 방법을 담은 문서를 남기는게 어떨까?"로 방향을 바꿨다. 게이트를
멈추고 코드 변경은 전부 되돌렸다. 남은 것은 문서 한 절이다.

## Why

NW design 결정 5 · TS 확인 10의 근거가 아직 선다 — 다른 키는 켜도
부팅에 비용이 없는데 `net`은 부팅마다 dhcpcd가 뜨고, 게이트의 부팅 수십 개가
그 비용을 같이 낸다. `ntp`는 `net` 없이는 할 일이 없다. 실측으로는 NIC 없는
`net=dhcp`가 부팅을 안 늦추지만(nic 체인 검사 6 · net 체인 검사 31), 사용자는
기본값을 뒤집는 것보다 켜는 길을 분명히 적는 쪽을 골랐다. 기본값을 뒤집으면
"키가 없는 옛 파일"과 "설정 디스크 없는 부팅"의 뜻까지 바뀐다는 점도 있다.

## How to apply

`net` · `ntp`의 기본값을 다시 뒤집자는 제안이 나오면 이
결정을 먼저 보인다. 켜는 법 · QEMU에서의 사정(SLIRP는 NTP 서버를 안 알려
준다) · 켜졌는지 보는 법은 `docs/guides/running-tars.md`의 "네트워크와 시계 —
기본은 꺼져 있다" 절에 있고, 새 네트워크 기능이 들어오면 그 절에 한 줄을
더한다. 되돌린 편집의 모양(바꿀 자리 넷: `config.zig` 기본값 둘 · `config_test`
기대값 · `service` 체인의 `ntp=off` 글자 · `tools` 주석)은 이 파일이 기록이다.

관련: [[project_guest_network]] · [[feedback_boot_never_blocks]] ·
[[project_daemon_supervision]] · [[project_voice_dictation]]
