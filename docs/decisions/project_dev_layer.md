---
name: project_dev_layer
description: "개발 도구 층(TP-M0~M12, 2026-11-09 닫힘) — 매니페스트대로 받은 도구를 묶음 열 개의 squashfs로 굽고, ISO에 싣고, tars-install이 p3로 옮기고, init이 /usr에 읽기 전용으로 겹친다. 망 없이 개발한다. 프리릴리스 dev-20261109를 맥북 에어 실기에서 확인"
metadata:
  type: project
---

# Dev Layer (TP)

사용자 요청(2026-11-05): "타스 리눅스를 설치하고 기본적으로 바로 뭔가를 컴파일하거나 자바 서버를 구동하고 싶다. 부팅 디스크(initrd)에
담는 것은 원하지 않는다. 네트워크가 없는 곳에서도 코딩 · 개발을 할 수 있는 환경을 만들자." design은
`docs/specs/2026-11-05-tars-dev-layer-design.md`(닫힘 2026-11-09), milestone마다 plan `docs/plans/2026-11-0[5-8]-tars-dev-layer-tp-m*.md`.

무엇이 섰나:

- 출처는 `devlayer/manifest.toml` 한 파일(MF-M0부터 — 그 전은 `manifest.tsv`, 이제 `make dev-layers`가 `devlayer/build/manifest.tsv`로 생성) — 도구마다 `[[tool]]` 하나(버전 · URL · sha256), 종류 순서 upstream → vendor-repo → prebuilt → debian
  (+ maven · hex). 소스 빌드는 없다([[feedback_tool_sourcing]]).
- 묶음 열: base · docs · editor · lang-beam · lang-jvm · lang-native · lang-script · media · server · util(zstd 15 squashfs, 합 1,806MiB).
  `make dev-layers`로 굽고 `make iso ISO_LAYERS="…"`로 싣는다 — 기본 `make iso`는 안 싣는다(그래서 barebone ISO가 공짜다, [[project_minimal_iso]]).
- `tars-install`이 p3 `/home/.tars/layers`로 옮기고 `version` 한 줄을 끝에 쓴다. init(`init/src/layers.zig`)이 부팅마다 loop · squashfs ·
  overlay로 `/usr`에 겹친다. 버전이 init과 다르면 건너뛰고 부팅은 간다. `/usr/local`만 쓰기 가능(p3 `/home/.tars/local`).
- 묶음은 `/etc` 몫(`etc/`)을 싣고 init이 tmpfs `/etc`로 복사한다 — 셸 조각(`etc/fish/conf.d` · `etc/tars/rc.d`)과 서비스 템플릿
  (`etc/tars/services`)이 이 길이다. 서버 다섯은 [[project_server_persistence]].
- AI 도구는 싣지 않고 공식 설치 길만 확인했다(TP-M12).

Why: initrd는 RAM이라 GB 단위 도구를 둘 수 없고, 망 없는 곳에서도 개발해야 한다. 설치 USB에 싣고 디스크로 옮기는 것이 둘을 다 푼다.

How to apply:

- 도구를 더하거나 판을 올리는 것은 manifest 줄 하나다. 판 올리기는 버전을 낼 때 한 번([[project_release]] 절차 3).
- 묶음을 실은 ISO는 2GiB 가까이다(GitHub release 파일 한도 2GiB, [[project_release_0_2]]). USB가 작으면 덜 써져 Limine이 멈춘다.
- 묶음은 설치 뒤에만 붙는다 — USB 라이브 부팅에서는 initrd의 도구뿐이다.
- 실기 확인 기록은 [[project_release_0_2]]의 "실기 확인".
