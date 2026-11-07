---
name: project_server_persistence
description: "서버의 데이터 · 설정 · 로그가 재부팅을 넘는 길은 영속성의 문제라 서버(서비스) milestone이 맡는다 — (a) 링크 (b) include (c) stdout 채택, 사용자 2026-11-07"
metadata:
  type: project
---

# 서버 영속성은 서비스 milestone의 몫

사용자(2026-11-07, FS-M0 게이트가 도는 중): Claude가 권한 방향과 시점에 "I agree with you", 이어서 "이거는 가볍게 보면 서비스 마일스톤인
것 같은데? 서버 애플리케이션 설치랑 관련이 있지만 핵심은 이게 영속성을 가지느냐잖아?"

Why: `/`는 ramfs라 `/var` · `/etc`에 생기는 상태가 매 부팅 사라진다. 이것은 서버를 싣는 일(묶음)이 아니라 부팅 경로(init)의 일이고,
블루투스(`/var/lib/bluetooth` 링크) · chrony(`confdir /config/chrony.d`)가 이미 같은 문제를 따로 풀었다.

How to apply:

- TP-M10(서버 실행 파일)은 영속 장치 없이 간다 — 판정은 부팅 하나 안의 응답. 데이터 경로는 사용자가 띄울 때 `~` 아래로 준다고 안내에 한 줄.
- 서버(서비스) milestone이 세운다: (a) `/var/lib/<서버>` → `/home/.tars/var/<서버>` 링크를 init이 묶음이 적은 목록으로, (b) `/etc` 원본은 두고
  `/config/<서버>.d/`를 include(postgres는 설정이 데이터 안이라 (a)), (c) 로그는 stdout으로 init 콘솔.
- 그 plan에서 사용자에게 물을 것: 링크 장치를 서버 다섯 전용으로 할지, 묶음이 목록을 적으면 무엇이든 받는 범용으로 할지(Claude는 범용을 권할 생각).
- 원문은 TP design `docs/specs/2026-11-05-tars-dev-layer-design.md`의 "닫은 것(2026-11-07)". [[project_release_0_2]]
