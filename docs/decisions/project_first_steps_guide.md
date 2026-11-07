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

How to apply (Claude가 권한 모양 — 사용자는 아직 고르지 않았다, plan에서 확정):

- 본문은 OS 쪽(initrd `/usr/share/doc/tars/`)에 둔다 — 갱신 때 같이 바뀌고 개발 도구 층이 없는 기계에도 있다. home에 복사하지 않는다:
  seed는 한 번만 깔려(`init`의 `O_EXCL`) 갱신 뒤 낡는다. home에는 그 본문을 가리키는 링크(`~/TARS.md` 꼴) 하나.
- 첫걸음 순서로 쓴다: 망(유선 · Wi-Fi) → 블루투스 → 설정을 남기기(`tars-config`, 설정 디스크) → 서비스(`tars-service`) · 방화벽 · ssh →
  개발 도구와 문서(`tars-docs get`). 내용은 `running-tars.md`에서 사용자용으로 줄여 옮긴다.
- 찾게 하는 길: 첫 셸에 한 줄 안내(예: "처음이라면 `glow ~/TARS.md`")를 둘지, `tars-help` 명령을 둘지는 plan에서. glow는 util 묶음,
  묶음이 없으면 `less`.
- TP-M9(문서 묶음)를 커밋한 뒤 새 milestone으로 — design부터(initrd · init seed를 건드린다).
