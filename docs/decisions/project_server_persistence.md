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
- 같은 milestone에 더할 것(사용자 2026-11-08, "ssl-cert 같은 툴도" → "둘 다"): 서비스가 쓸 기계별 자체 서명 인증서(거두기 컨테이너의 snakeoil은 모든
  기계가 같은 비밀 키라 TP-M10에서 뺐다 — 기계마다 한 번 만들어 남는 자리에), 시스템 신뢰(`/usr/local/share/ca-certificates/*.crt`를 부팅 때 CA 묶음에
  덧붙이기 — `mkcert -install`이 이어진다). 사용자용 mkcert는 TP-M10 덧붙임으로 util에 들어갔다.
- 바뀐 방향(사용자 2026-11-08, TP-M11 조사 뒤 — 셋 다 Claude 추천): (a)의 링크 · 디렉터리 · 첫 초기화는 init이 아니라 서비스 템플릿
  (`/etc/tars/services/<서버>`, sshd와 같은 모양)이 한다 — init 코드 0줄. 서버는 TARS 사용자(uid 1000)로 돈다(서비스 계정 없음). 켜고 끄기는
  `tars-service enable|disable <이름>`(services.d 링크 + reload). init을 고치는 곳은 시스템 신뢰 하나다. plan `docs/plans/2026-11-08-tars-dev-layer-tp-m11.md`.
