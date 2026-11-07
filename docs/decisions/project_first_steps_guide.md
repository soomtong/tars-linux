---
name: project_first_steps_guide
description: "설치 직후 '이제 뭘 하지'에 답하는 첫걸음 안내(Wi-Fi · 블루투스 · tars-config · tars-service · 문서)를 기계 안에 둔다 — 사용자 요청 2026-11-07, TP-M9 뒤의 작은 milestone"
metadata:
  type: project
---

# 설치 뒤 첫걸음 안내

사용자(2026-11-07, TP-M9 체인이 도는 중): "home 폴더에 tars install, tars config, tars service 사용 방법을 담은 md 문서를 넣는 것은
어떨까?" 이어서: "설치를 잘 마치고 나니까 뭘 해야 될지 모르겠어서 당황해. 이런 사람들이 많을 거야. 문서를 읽어보고 시스템 세팅을
하면 되겠지. 와이파이도 잡고 블루투스도 잡고."

Why: 설치기가 `done`을 찍은 뒤 첫 셸에서 다음 할 일(망 켜기 · Wi-Fi · 블루투스 · 설정 디스크 · 서비스 · 문서 받기)을 알려 주는 것이 기계
안에 없다. 지금 그 내용은 저장소의 `docs/guides/running-tars.md`에만 있고, 거기에는 체인 · 게이트 같은 개발 사정이 섞여 있다.

How to apply (사용자 결정 2026-11-07 — 앞서 Claude가 권한 "home에 링크 · 첫 셸 한 줄"은 사용자가 고르지 않았다):

- 찾는 길은 `tars-help` 명령 하나다. 셸에 저절로 뜨는 안내 · motd · home 파일은 두지 않는다. 설치기의 `done` 줄 아래에 `tars-help`를 알리는
  한 줄만 더한다.
- 한국어로 쓴다.
- 범위는 넷 다: 망 · Wi-Fi · 블루투스 / 설정 남기기 · 서비스(설정 디스크 · `tars-config` · `tars-service` · 방화벽 · ssh) / 개발 도구 · 문서
  (`tars-docs`, man, Homebrew · mise) / 화면 · 키보드 · 소리(한/영, 클립보드, 밝기 · 절전, 소리, `tars-dictate`).
- 본문은 OS 쪽(initrd)에 둔다 — 갱신 때 같이 바뀌고 개발 도구 층이 없는 기계에도 있다. 내용은 `running-tars.md`에서 사용자용으로 줄여 옮기고
  체인 · 게이트 같은 개발 사정은 뺀다.
- 서브프로젝트 접두사 FS(First Steps), design `docs/specs/2026-11-07-tars-first-steps-design.md`.
