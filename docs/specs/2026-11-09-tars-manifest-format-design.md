# TARS Manifest Format — Design

접두사: MF

Date: 2026-11-09
Status: 닫힘(2026-11-09) — MF-M0. 출처 `devlayer/manifest.toml`(1,199줄), 변환기 `devlayer/manifest-gen.zig`, 묶음 열한 개가 옮기기 전과 내용이 같다(결정 8의 판정은 plan 결과 1 — 출처 기록 한 줄을 빼고 대조). plan `docs/plans/2026-11-09-tars-manifest-format-mf-m0.md`.

계기: 사용자(2026-11-09, BB를 닫은 뒤): "manifest 파일 포맷 개선 — 단순 tsv 충분한가? toml이나 yaml정도? 더 나은 포맷이 있다면
추천". 추천(대화): 사람이 고치는 원본은 TOML로 두고, 개발 컨테이너의 변환기가 지금 모양의 TSV를 산출물로 낸다. 이어서 사용자가 정한
것(2026-11-09): 변환기는 Zig, 생성된 TSV는 커밋하지 않는 산출물, 범위는 `manifest.tsv` 하나. 순서는 manifest 포맷 → 전체 화면 →
0.2.0이다.

관련 문서: TP design(`2026-11-05-tars-dev-layer-design.md`) 결정 1(출처 순서) · 3(판 바꾸기) · 6(바뀐 묶음만 다시 굽기), TP-M2 plan
결정 C · D(선택 열 · `manifest.sh`).

## 한 줄 요약

`devlayer/manifest.toml`이 출처가 되고, `devlayer/manifest-gen.zig`가 그것을 검사해 `devlayer/build/manifest.tsv`를 쓴다. TSV를 읽는
쪽(`manifest.sh` · `harvest.sh` · `build.sh`)은 읽는 자리만 바뀐다. 옮긴 뒤 생성된 TSV는 지금 TSV에서 주석과 빈 줄을 뺀 것과
바이트까지 같아야 하고, 그래서 다시 굽는 묶음이 없다.

## 왜 바꾸나

1. 일곱째 열은 표 안에 숨은 작은 문법이다 — 공백으로 가른 `키=값`, `exe=`의 값은 쉼표로 가른 목록. `dasht` 줄은 이 열 하나가
   300자를 넘는다. 읽기도 고치기도 어렵고, 키가 다섯을 넘으면 옮기자고 `manifest.sh` 주석에 이미 적어 두었다.
2. 탭이 공백으로 바뀌면 줄이 깨진다. `manifest_check`가 줄 번호를 찍고 멈추게 했지만(TP-M2), 편집기 설정에 기대는 형식이다.
3. 자리 채움 값이 있다. debian · vendor-repo 줄의 sha256 자리는 늘 `apt`이고, debian 줄 45개의 URL 자리는 모두 도구 이름과 같다.
   열의 뜻이 종류마다 달라서 머릿줄 주석 없이는 읽을 수 없다.

YAML이 아닌 이유: 따옴표 없는 판 번호(`1.20` · `0.10`)를 숫자로 읽어 끝의 0을 잃는다. JSON은 주석이 없어 지금 줄 위의 이유 주석
(이 파일 내용의 절반)을 둘 자리가 없다. ZON은 Zig가 그대로 읽지만 사람이 고치는 파일로는 TOML보다 낯설다.

## 확인 (2026-11-09, HEAD `71cdc1b`)

1. `devlayer/manifest.tsv` — 230줄(도구 129 · 주석 90 · 빈 줄 11). 종류별로 upstream 72 · debian 45 · vendor-repo 7 · prebuilt 3 · maven 1 · hex 1.
   일곱째 열을 쓰는 줄의 키는 `exe` · `hook` · `into` · `strip` · `man1` 다섯이고, 줄마다 순서가 다르다(`strip=0 exe=ninja`와
   `exe=… strip=…`이 섞여 있다).
2. TSV를 직접 읽는 것은 `devlayer/manifest.sh` 하나다(`DEVLAYER_MANIFEST`, 기본 `devlayer/manifest.tsv`). `build.sh:30`과
   `harvest.sh:25`가 source한다. 훅 다섯(`devlayer/hooks/*.sh`)과 `needed-ignore.tsv` · `Makefile:113`은 주석 · 안내 글자로만 이름을 댄다.
3. `build.sh`의 stamp(`build.sh:300-306`)에 그 묶음의 매니페스트 줄이 원문 그대로 들어간다. harvest의 캐시(`<묶음>.harvest.lines`)도
   줄을 본다. 그러니 생성된 줄이 한 바이트라도 다르면 그 묶음을 다시 거두고 다시 굽는다.
4. `Makefile:245-250` — `dev-layers`는 개발 컨테이너에서 `keys.sh`를 한 번 돌린 뒤, 묶음마다 harvest(amd64 `debian:trixie-slim`, 파서
   없음)와 build(개발 컨테이너)를 번갈아 부른다. `gate`와 `check CHAIN=devtools`는 `dev-layers`에 기댄다.
5. 개발 컨테이너에는 Zig가 있고(`devcontainer/Dockerfile:568-580`) python3는 없다. Zig 표준 라이브러리에는 TOML 파서가 없다.
6. `quick_check.sh`의 단계 넷째가 `shared/`의 순수 검사를 `zig run`으로 돌린다 — 변환기의 단위 검사가 들어갈 자리가 이미 있다.
7. `devlayer/build/`는 `.gitignore` 대상이다.

## 결정

1. 출처는 `devlayer/manifest.toml`이다. 도구 하나가 `[[tool]]` 표 하나다. 지금 TSV의 줄 위 주석은 그 `[[tool]]` 위로 그대로 옮긴다.
   묶음 순서(`manifest_bundles`가 처음 나온 순서를 쓴다)와 도구 순서는 파일에 적힌 순서다.

   ```toml
   [[tool]]
   name = "cmake"
   bundle = "base"
   version = "4.4.5"
   kind = "upstream"
   url = "https://github.com/Kitware/CMake/releases/download/v4.4.5/cmake-4.4.5-linux-x86_64.tar.gz"
   sha256 = "ed85135c5a5135b45e50423cb406dea04ca3338da0b8ef3c9ede963559680be0"
   exe = ["bin/cmake", "bin/ctest", "bin/cpack", "bin/ccmake"]
   ```

2. 키는 종류마다 정해져 있다. 자리 채움 값은 TOML에서 사라지고 변환기가 TSV에 채운다.

   | 종류 | 반드시 | TSV 5열 | TSV 6열 |
   |---|---|---|---|
   | upstream · prebuilt | `url` · `sha256` | `url` | `sha256` |
   | debian | (`package`, 없으면 `name`) | `package` | `apt` |
   | vendor-repo | `repo` · `package` | `repo/package` | `apt` |
   | maven · hex | `lock` · `sha256` | `lock` | `sha256` |

   공통으로 반드시: `name` · `bundle` · `version` · `kind`. 선택: `exe`(문자열 배열) · `hook` · `into` · `man1`(문자열) · `strip`(정수).
   그 밖의 키, 종류에 맞지 않는 키(예: debian 줄의 `url`), 빠진 키는 `파일:줄: 이유`를 찍고 멈춘다.

3. 선택 키는 TOML에 적힌 순서대로 일곱째 열이 된다. `exe = ["a", "b"]`는 `exe=a,b`, `strip = 0`은 `strip=0`. 선택 키가 없으면 열이
   여섯이다. 순서를 정렬하지 않는 이유가 확인 3이다 — 정렬하면 순서가 바뀐 줄의 묶음이 전부 다시 구워진다(내용은 같은데).

4. 변환기는 `devlayer/manifest-gen.zig` 한 파일이다. TOML 전부가 아니라 이 파일이 쓰는 부분집합만 읽고, 그 밖의 문법은 거절한다.
   - 읽는 것: 줄 주석 · 줄 끝 주석(`#`), `[[tool]]`, `키 = "기본 문자열"`, `키 = 정수`, `키 = [문자열, …]`(여러 줄 · 끝 쉼표 ·
     배열 안 주석 허용 — dasht의 `exe`가 아홉 개다).
   - 거절하는 것: `[표]` · 점 키 · 인라인 표 · 작은따옴표 문자열 · 여러 줄 문자열 · 실수 · 날짜 · 불리언, 그리고 문자열 안의 `\`
     이스케이프(지금 값에 `\`가 하나도 없다 — 생기면 그때 연다).
   - 값 검사: 모든 문자열에 탭 · 줄바꿈 · 공백이 없다(TSV 열과 일곱째 열의 구분자다). 옵션 값에 `=`가 없고 `exe` 항목에 `,`가 없다.
     `name`은 한 번만. `kind`는 여섯 중 하나. vendor-repo의 `repo` · `package`는 지금 `manifest_check`의 정규식과 같은 모양.
   - 출력: 머릿줄 주석 한 줄(`# 생성됨 — devlayer/manifest.toml을 고친다`) 뒤에 줄마다 TSV. 임시 파일에 쓰고 `rename`한다 — 실패한
     변환이 반쪽 TSV를 남기지 않는다.

5. 생성된 TSV는 `devlayer/build/manifest.tsv`(커밋하지 않는다). `manifest.sh`의 `DEVLAYER_MANIFEST` 기본값이 그 자리로 바뀌고,
   파일이 없으면 "run make dev-layers"를 찍고 멈춘다. `manifest_check`(awk)는 그대로 둔다 — 변환기가 놓친 것을 harvest 컨테이너에서도
   한 번 더 막는 둘째 방어선이고, 고칠 이유가 없다.

6. `make dev-layers`가 `keys.sh` 옆에서 개발 컨테이너로 변환기를 먼저 한 번 돌린다(`zig run devlayer/manifest-gen.zig -- …`). 그래서
   `gate` · `check CHAIN=devtools`도 따라 생성한다. 지금 `devlayer/manifest.tsv`는 옮긴 커밋에서 지운다 — 출처가 둘이면 어긋난다.

7. 단위 검사는 `zig test devlayer/manifest-gen.zig`가 하고 `quick_check.sh`의 한 단계가 된다. 실제 `manifest.toml`을 변환해 성공하는지도
   같은 단계에서 본다(1초 안쪽, 망 없음). 그러니 TOML을 잘못 고친 것은 `make quick`이 먼저 잡는다.

8. 옮기기는 한 번이다. 지금 TSV를 TOML로 바꾸는 일회성 스크립트는 scratchpad에 두고 커밋하지 않는다. 옮긴 것이 맞다는 판정은
   둘이다.
   - `diff <(rg -v '^#|^\s*$' 옛 manifest.tsv) <(rg -v '^#' devlayer/build/manifest.tsv)`가 비어야 한다.
   - 옮기기 전에 잰 `devlayer/build/*.sqfs` 열한 개(fakesteak 포함)의 sha256이 옮긴 뒤 다시 구운 것과 같다.
   주석이 모두 옮겨졌는지는 사람이 본다(주석 줄 수를 세서 대조).

   (2판 고침, plan을 쓰며 찾은 것) 1판은 "모든 묶음이 `cached`"를 판정으로 삼았다. 그런데 stamp에는 줄만이 아니라
   `devlayer/manifest.sh`의 sha256도 들어간다(`build.sh:305`). 결정 5가 그 파일을 고치므로 묶음 열한 개가 모두 다시 구워진다
   (2026-11-09 09:30~09:33의 기록으로 4분 남짓). 그 대신 굽기가 `-mkfs-time 0 -all-time 0`이라 입력이 같으면 바이트가 같아야
   하므로, sqfs의 sha256 대조가 "cached"보다 강한 판정이다. harvest의 캐시는 `harvest.sh` · `harvest-skip.tsv` · 줄만 보므로
   (`harvest.sh:46`), `harvest.sh`를 고치지 않으면 망을 타는 거두기는 다시 돌지 않는다.

## 비목표

- `repos.tsv` · `harvest-skip.tsv` · `needed-ignore.tsv`(사용자 결정 — 열이 둘~넷이고 숨은 문법이 없다).
- TOML 전부를 읽는 범용 파서.
- harvest 컨테이너가 TOML을 읽는 것 — slim 컨테이너에는 아무것도 깔지 않는다(TP design).
- 선택 키를 새로 더하는 것. 키가 늘어도 이제는 변환기의 표 한 줄과 `manifest.sh`의 정규식 한 자리다.

## 위험

1. 주석의 자리. TSV에서 도구 줄 위에 있던 주석이 다른 `[[tool]]` 위로 붙으면 뜻이 틀어진다. 옮기기 스크립트는 "다음 도구 줄 앞의
   주석은 그 도구의 것"으로 단순히 옮기고, 묶음 머리 주석(`# ── base … ──`)도 다음 도구 위에 놓인다 — 읽는 데 문제가 없다.
2. 파일이 길어진다. 한 줄이던 도구가 다섯~여덟 줄이 된다(약 230줄 → 1,000줄 남짓). 길이 대신 줄마다 키 이름이 보인다는 것을 산다.
3. `zig run`은 컨테이너가 `--rm`이라 매번 컴파일한다(수 초). 캐시 자리를 `devlayer/build/` 아래로 주면 다음부터는 빠르다 — plan에서 잰다.

## Milestone

- MF-M0: 변환기 · 단위 검사 · 옮기기 · `manifest.sh` · `Makefile` · `quick_check.sh` · 안내 글자. 게이트는 결정 8의 판정 둘과
  `make quick`. QEMU 부팅은 없다(묶음이 바이트까지 같으므로).
