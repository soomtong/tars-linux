---
name: project_minimal_iso
description: "배포판을 낼 때 개발 도구 층을 뺀 minimal ISO도 함께 지어 같이 올린다(사용자 2026-11-09). 임베디드 기기에 납품하는 프로젝트가 최종 실행 파일만 싣고 배포할 때 쓰는 판이다. BB(2026-11-09)가 절차에 넣었고 fakesteak 데모를 냈다"
metadata:
  type: project
---

# Minimal ISO

사용자(2026-11-09, `dev-20261109` 실기 설치 테스트 중): "배포판을 만들 때 개발도구 층을 제외한 minimal 버전의 iso 파일도
생성해서 같이 업로드 해야겠다. 임베디드 기기에 납품되는 프로젝트의 최종 실행 파일만 포함해서 배포하는 경우 사용할거야.
개발툴, 서버 이런 것들 필요 없는 형태인거지."

Why: 개발 도구 층(TP 묶음 · 서버 실행 파일 · 서버 서비스)을 실은 ISO는 "설치하면 망 없이 바로 개발한다"를 위한 판이다.
임베디드 납품에서는 그 묶음이 쓸모가 없고, 납품할 프로젝트의 최종 실행 파일만 얹을 바닥이 필요하다.

How to apply:

- 릴리스(정식 · `dev-<날짜>` 프리릴리스 모두)마다 ISO 두 개를 같은 release에 올린다 — 묶음을 실은 판과 묶음을 뺀 minimal 판.
  SHA256SUMS에는 둘 다 넣는다.
- [[project_release_0_2]]에 따르면 `make iso`의 기본값은 묶음을 싣지 않는다(`ISO_LAYERS`를 줄 때만 싣는다). minimal 판은 이
  기본값으로 지을 수 있을 것으로 보이나, 아직 확인하지 않았다.
- 빼는 "서버"는 개발 도구 층의 서버 묶음이다. initrd에 든 sshd 같은 기본 데몬은 minimal 판에도 남긴다(사용자 2026-11-09:
  "sshd 같은 기본 데몬은 포함합니다.").
- 파일 이름은 `tars-<ver>-barebone-x86_64.iso`다(사용자 2026-11-09). 프리릴리스라면 `<ver>` 자리에 `dev-<날짜>`가 들어가
  `tars-dev-<날짜>-barebone-x86_64.iso`가 된다.
- 첫 데모용 실행 파일은 https://github.com/domsson/fakesteak 이다(사용자 2026-11-09: 설치해 사용할 계획, 준비 중).
  barebone 판에 이것을 올려 "최종 실행 파일만 싣는 배포"를 처음 확인한다. 원본에는 미리 빌드된 바이너리가 없어서(그래서 TP에서
  뺐다), 사용자가 fork(`soomtong/fakesteak`)해 linux-amd64 릴리스를 낸다(사용자 2026-11-09) — cci · glc와 같은 길, 소스 빌드 금지를 지킨다.
- 얹는 방법은 BB design(`docs/specs/2026-11-09-tars-barebone-design.md`)이 정한다. 정해지면 [[project_release]]의 배포 절차에 단계를 더한다.

## 결과 (BB, 2026-11-09 닫힘)

- barebone ISO = `make iso`(묶음 없음), 143,751,168 B. 배포 절차 3이 먼저 짓고 옮겨 둔다([[project_release]]).
- 얹는 방법: 납품 프로젝트는 묶음 하나(`make dev-layers DEV_LAYERS=<이름>` → `make iso ISO_LAYERS="<이름>"`). 부팅 때 자동 실행은 그 묶음의
  셸 조각(`etc/tars/rc.d/<이름>.sh` · `etc/fish/conf.d/90-<이름>.fish`) — 본보기는 `devlayer/files/fakesteak/`.
- 데모 릴리스 `demo-fakesteak-20261109`(프리릴리스, 144,082,944 B). 정식 버전 release에는 섞지 않는다.
- 함정 둘: 개발 도구 층이 깔린 디스크를 barebone으로 갱신하면 옛 묶음이 판이 달라 안 붙고(파일은 남는다), 납품 ISO로 갱신하면 옛 묶음이
  지워진다. 셸 없는 키오스크(init이 앱을 감독)는 실제 납품이 요구할 때 연다.

