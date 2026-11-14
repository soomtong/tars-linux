# TARS Odin — Design

접두사: OD

Date: 2026-11-14
Status: 진행 중(OD-M0).

계기: TP-M2(2026-11-06)가 LLVM 툴체인을 빼면서 odin도 함께 뺐다 — "odin은 링크에 `clang`을 부른다"(TP-M2 plan 확인 4). 2026-11-14에
사용자가 다시 넣을 때의 용량을 물었고, 조사에서 `ODIN_CLANG_PATH`로 base의 gcc가 링크를 맡는 것이 섰다(`measurements.md` 104).
같은 날 배포의 모양이 바뀌었고(아래 "배포"), 사용자: "이제 odin을 native lang에 그대로 포함해보자."

관련 문서: TP design(`2026-11-05-tars-dev-layer-design.md` — 도구 목록의 "네이티브 언어"와 "뺀 것", 결정 1의 `hook=`) · TP-M2 plan 확인 4 ·
`measurements.md` 104(odin 실측) · 105(묶음의 자리 검토) · 기억 `project_release`.

## 한 줄 요약

odin `dev-2026-11a`를 `lang-native` 묶음에 그대로 싣고(풀린 250MiB, zstd15 약 65MiB), 얇은 런처가 `ODIN_CLANG_PATH`를 비어 있을 때만
`gcc`로 채워 clang 없이 링크한다.

## 확인 (2026-11-14, HEAD `238bb5d`)

1. 릴리스 `dev-2026-11a`(2026-11-03)의 `odin-linux-amd64-dev-2026-11a.tar.gz` 76,175,813 B. 맨 위 디렉터리 하나
   (`odin-linux-amd64-nightly+2026-11-03/`) 아래 `odin`(실행 파일, LLVM을 품은 `statically linked`, not stripped) · `base` · `core` ·
   `vendor` · `shared` · `examples` · `LICENSE`. `bin/`이 없다.
2. `odin`은 링크 드라이버로 `clang`을 부르고 `ODIN_CLANG_PATH`로 바꾼다. `gcc`로 hello와 `-debug` 빌드가 섰다 — 넘기는
   `-Wno-unused-command-line-argument`는 gcc가 무시한다. clang도 변수도 없으면 `Could not spawn subprocess`.
3. Odin은 자기 자리를 실행 파일의 진짜 경로에서 찾는다. `/usr/local/bin/odin` → 링크 → 런처 → 진짜 `odin`을 거쳐도 `odin root`가
   `/usr/local/lib/odin-dev-2026-11a/`이고 `core:fmt`가 풀렸다(amd64 trixie 컨테이너, 사용자 uid). `odin version`은 argv[0]을 그대로
   찍는다 — 런처가 `exec -a odin`으로 넘긴다.
4. 기본 판 ISO(묶음 열셋)는 2,064,445,440 B, odin을 더하면 약 2,133,090,304 B로 2GiB(2,147,483,648) 아래다.

## 결정

### 결정 1 — `lang-native`의 `upstream` 줄, hook `odin`

판 이름은 태그 그대로 `dev-2026-11a`(자리 `/usr/local/lib/odin-dev-2026-11a/`). `devlayer/hooks/odin.sh`가 tarball을 풀어(맨 위 한 단을
벗긴다) 도구 디렉터리에 옮기고 `bin/odin` 런처를 쓴다. 링크는 build.sh의 기본 규칙(`bin/`의 실행 파일 → `/usr/local/bin`)이 만든다.
hook이 tarball의 맨 위 목록이 아는 일곱(`LICENSE base core examples odin shared vendor`)과 다르면 멈춘다 — 판이 바뀌면 사람이 본다.
아무것도 빼지 않는다(사용자 "그대로", `measurements.md` 105의 결정과 같은 결).

### 결정 2 — 런처가 `ODIN_CLANG_PATH`의 기본값을 정한다

rc.d · fish 조각의 환경 변수는 대화형 셸에만 닿는다 — `bash -c`, 편집기의 빌드 작업, 체인의 `as_tars`가 놓친다. 그래서 실행 파일 자리에
런처를 둔다(gleam의 런처와 같은 결, TP-M6). 런처는 bash 넷째 줄이다: 변수가 비어 있으면 `gcc`, 이미 있으면 그대로(사용자가 Homebrew 등으로
clang을 깔고 `ODIN_CLANG_PATH=clang`을 주면 그쪽), 진짜 실행 파일은 hook이 아는 절대 경로로 `exec -a odin`. `/usr/local/bin/clang`
같은 링크는 두지 않는다 — cmake 등이 진짜 clang으로 안다.

### 결정 3 — 체인 `devtools`의 부팅 2에 odin hello

zig 줄 뒤에 `odin run`으로 `ODIN_VERSION`을 찍는 hello 하나. 상한은 TP-M1의 규칙(처음 잰 숫자의 세 배, 60초 아래로는 안 내린다).
처음 판의 숫자를 이 design과 plan에 남긴다.

## 배포 (사용자 결정 2026-11-14)

GitHub release(파일 하나당 2GiB)에는 ISO 셋만 올린다: 개발 도구 층에서 `server`만 뺀 판, `lang-native`만 뺀 판, fakesteak 납품 데모.
묶음 전부를 실은 판은 GitHub에 올리지 않는다 — 다른 길은 사용자가 정하고, 그때까지는 로컬에 빌드를 남겨 `dd`로 쓴다. 이 결정은
odin과 따로 섰지만 odin이 그 이유를 키운다(묶음 전부 판이 2GiB까지 약 14MiB). 다음 판을 낼 때 기억 `project_release`의 절차에 반영한다
(이 design의 범위 밖 — OD-M0은 묶음과 체인만 고친다).

## 비목표

1. LLVM 툴체인 · lld · clang(TP-M2의 결정 그대로).
2. ols(Odin language server) — 따로 받는 도구다. 필요해지면 따로 묻는다.
3. `vendor`의 C 라이브러리(raylib · SDL3 등)가 gcc 링크로 서는지의 확인. hello(`core:`)만 체인이 본다.

## Milestone

- OD-M0 — 결정 1~3. plan `docs/plans/2026-11-14-tars-odin-od-m0.md`.
