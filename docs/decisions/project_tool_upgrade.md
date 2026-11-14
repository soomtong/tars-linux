---
name: project_tool_upgrade
description: "도구 판올림(TU-M0, 2026-11-14 닫힘) — 0.2.2에 실을 개발 도구 판을 대조해 올린다 · 판올림마다 새 실행 파일의 AVX2 · BMI2를 objdump로 옛 판과 센다(janet 1.43.0이 걸려 1.42.1에 남았다) · pgdg postgresql-common 294+의 systemd 요구는 standalone 둘을 이름으로 · 판이 박힌 devlayer/files 디렉터리는 함께 git mv"
metadata:
  node_type: memory
  type: project
---

TP design 결정 3("개발 도구의 판은 버전을 낼 때 한 번")의 첫 실행. 사용자(2026-11-14): "이번 판올림은 각각의 포함되는 유틸리티
랭귀지 버전을 업그레이드 하는 것으로 의미를 삼으면 되겠다" → 외출하며 "모든 결정을 위임합니다." design
`docs/specs/2026-11-14-tars-tool-upgrade-design.md`, plan `docs/plans/2026-11-14-tars-tool-upgrade-tu-m0.md`.

Why: TCG 체인은 실기에 없는 명령을 못 잡는다(measurements 103). 판올림은 같은 이름의 파일을 바꾸므로 그때 CPU 수준이 말없이 올라간다
(measurements 106).

How to apply: 다음 판올림도 같은 순서 — GitHub 줄은 `gh api …/releases/latest`와 대조(digest가 sha256), debian · vendor-repo 줄은 trixie
컨테이너에 저장소를 붙인 `apt-cache policy`, 그다음 `objdump -d`로 새 · 옛 판의 `%ymm` · `shlx`를 센다. 판이 박힌 `devlayer/files/*/usr/local/lib/<도구>-<판>/`
(gleam · python · ruby · node)은 manifest와 함께 이름을 바꾼다 — build.sh가 멈춰 알려 준다. 체인이 판을 기다리는 줄(go · node · janet · pg · buildx)도.
새 접두사는 `docs/guides/completed.md`와 plan 파일 이름에서 먼저 찾는다 — TR은 Terminal Rendering이 쓰고 있었다.

관련: [[project_odin]] (같은 날 rust 1.100.0), [[project_release]].
