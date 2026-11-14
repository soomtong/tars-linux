---
name: project_odin
description: "odin(OD-M0, 2026-11-14 닫힘) — lang-native에 그대로 싣고, clang 대신 base의 gcc가 링크한다(hook이 쓴 bin/odin 런처가 ODIN_CLANG_PATH를 비었을 때만 gcc로) · vendor의 raylib .so는 NEEDED 예외(GUI · foreign-arch) · 같은 milestone에 rust 1.100.0과 make iso-full"
metadata:
  node_type: memory
  type: project
---

TP-M2(2026-11-06)가 LLVM 툴체인을 빼며 odin도 뺐다 — 링크에 `clang`을 부르기 때문이었다. 2026-11-14 사용자가 다시 넣을 때의 용량을
물었고, `ODIN_CLANG_PATH`로 gcc가 링크를 맡는 것이 섰다(`measurements.md` 104). 같은 날 "이제 odin을 native lang에 그대로 포함해보자."
design `docs/specs/2026-11-14-tars-odin-design.md`, plan `docs/plans/2026-11-14-tars-odin-od-m0.md`.

Why: rc 조각의 환경 변수는 대화형 셸에만 닿는다 — `bash -c`, 편집기의 빌드, 체인의 `as_tars`가 놓친다. 그래서 실행 파일 자리에
런처를 둔다(gleam 런처와 같은 결). odin은 자기 자리를 진짜 실행 파일의 경로에서 찾으므로 런처를 거쳐도 `core:`가 풀린다.

How to apply: odin 판을 올리면 hook(`devlayer/hooks/odin.sh`)이 tarball 맨 위 일곱(`LICENSE base core examples odin shared vendor`)을
대조해 다르면 멈춘다. `vendor`의 C 라이브러리 링크(raylib · SDL3)는 체인이 안 본다(비목표 3). 사용자가 clang을 깔면
`ODIN_CLANG_PATH=clang`이 이긴다. `/usr/local/bin/clang` 같은 링크는 두지 않는다.

숫자: lang-native +65.5MiB(odin), +2.2MiB(rust 1.100.0), 묶음 열셋 1,898MiB, `odin run` hello 11.1초(TCG SandyBridge).
배포 모양의 바뀜(GitHub에 ISO 셋 · 묶음 전부 판은 `make iso-full`로 로컬)은 [[project_release]].
