---
name: project_manifest_format
description: "개발 도구 층 매니페스트의 출처가 devlayer/manifest.toml이 됐다(MF-M0, 2026-11-09). Zig 변환기가 make dev-layers 첫 단계로 devlayer/build/manifest.tsv를 쓰고, TSV를 읽는 쪽은 그대로다"
metadata:
  type: project
---

# Manifest Format (MF)

사용자(2026-11-09): "단순 tsv 충분한가? toml이나 yaml정도?" — 사용자가 정한 것: 변환기는 Zig, 생성 TSV는 커밋하지 않는 산출물,
범위는 manifest 하나(`repos.tsv` · `harvest-skip.tsv` · `needed-ignore.tsv`는 TSV 그대로). design `docs/specs/2026-11-09-tars-manifest-format-design.md`,
plan `docs/plans/2026-11-09-tars-manifest-format-mf-m0.md`.

- 도구를 더하거나 판을 올릴 때 고치는 것은 `devlayer/manifest.toml`이다. 키 표는 그 파일의 머리 주석. `make quick`이 바로 검사한다.
- 선택 키(`exe` · `hook` · `into` · `strip` · `man1`)는 적힌 순서대로 TSV 일곱째 열이 된다. 순서만 바꿔도 그 묶음의 stamp가 바뀌어 다시 굽는다.
- 묶음 sqfs의 sha256은 커밋마다 다르다 — `usr/share/tars/layers/<묶음>`에 `git describe --dirty`가 들어간다. "같은 묶음인가"는 그 한 파일을
  빼고 풀어서 대조한다(MF-M0 plan 결과 1의 방식). describe까지 같으면 바이트가 같다(굽기는 결정적).
- `devlayer/manifest.sh`나 `build.sh` · 훅을 고치면(주석 한 자도) 묶음 열한 개를 다시 굽는다(3분 반). `harvest.sh` · `harvest-skip.tsv`를 고치면
  debian · vendor-repo 묶음을 망으로 다시 거둔다.

관련: [[project_dev_layer]] · [[project_release]]
