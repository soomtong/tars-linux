---
name: project_latticedb_survey
description: "latticedb(Zig 임베디드 그래프 DB · 벡터 · FTS)를 TARS에 붙일 수 있는지 조사만 했다(2026-10-01). 빌드는 되지만 FTS 토크나이저가 한글을 토큰 0개로 버려서, 한글 문제가 풀리기 전까지 쓰지 않는다고 사용자가 정했다"
metadata:
  type: project
---

# latticedb 조사 (2026-10-01, 코드 0줄)

사용자가 https://github.com/jeffhajewski/latticedb 를 "우리 프로젝트에 적용할 방법"으로
조사해 달라고 했다. 조사는 `/tmp`에서만 했고 저장소에 넣은 코드는 없다.

결론은 사용자가 정했다 — 한글 문제가 해결되기 전까지는 쓸 수 없다. 서브프로젝트로
열지 않고 이 기록만 남긴다.

## latticedb가 무엇인가

- 파일 하나(+ 옆의 `-wal`)에 담기는 임베디드 property graph DB. 질의는 Cypher 하나로
  그래프 탐색 · HNSW 벡터 유사도 · BM25 전문 검색을 함께 한다.
- 저자가 내세우는 쓰임은 Graph RAG · agent memory · 로컬 지식 도구다.
- MIT, 조사 시점 v0.15.0, 마지막 커밋 2026-09-23. CLI 하위 명령은 `create` · `exec` ·
  `query`(REPL) · `import`/`export` · `check` · `replicate`/`restore` 등이다.

## 실측 — 붙는 쪽

- `build.zig.zon`의 `minimum_zig_version = "0.16.0"`이 우리 `terminal`과 같다.
- 호스트 zig 0.16.0으로 `zig build -Dtarget=x86_64-linux-gnu.2.41 -Doptimize=ReleaseSafe`가
  경고 없이 59초. 컨테이너에서는 안 돌렸다(그날 OrbStack이 꺼져 있었다).
- 공유 라이브러리 의존은 `libc.so.6` 하나, 요구 심볼은 `GLIBC_2.36`까지 — 게스트 glibc
  2.41로 충분하다. `lattice` CLI 16MB(디버그 정보 포함), `liblattice.so` 14MB.
- 그래프 질의는 한글 속성값을 그대로 다룬다. `WHERE a.text STARTS WITH '커널'`로 관계를
  따라간 결과가 맞았다.

## 실측 — 막히는 쪽

1. 한글 FTS가 없다. `src/fts/tokenizer.zig`의 `isWordChar`가
   `std.ascii.isAlphanumeric(c) or c == '_'`뿐이라 UTF-8 바이트가 전부 구분자다.
   토크나이저에 직접 넣은 결과:
   ```
   [커널 패닉 로그]   ->                         (토큰 0개)
   [kernel panic log] -> <kernel> <panic> <log>
   [Linux커널]        -> <Linux>
   ```
   CLI 표 출력도 칸 폭을 바이트로 세서 한글 칸이 어긋난다.
2. 벡터 검색은 진짜 임베딩 모델이 있어야 의미가 있다. 예제의 `hash_embed`는 README가
   스스로 자리표시라고 한다. 게스트에는 모델을 돌릴 런타임이 없다.
3. "single file"이지만 쓰면 `<db>-wal`이 옆에 생긴다. `/config`(ext2)에 둔다면 전원
   버튼과 WAL 내구성을 두 번 부팅으로 증명해야 한다([[project_shell_history]]와 같은 종류).
4. FTS 색인 선언은 CLI에 없고 C API(`createNodeFtsIndex`)와 바인딩에만 있다.

## 붙일 자리로 본 셋

- 게스트 도구로 싣기(UT · UW 패턴, 코드 0줄) — 쓰는 곳이 없어 가치가 낮다.
- 패키지 관리자의 메타데이터(패키지 → 의존 → 패키지) — 모양은 맞지만 v0.15의 파일
  형식을 시스템의 뿌리 데이터로 삼기에는 이르다.
- AI 코딩 도구 통합의 로컬 기억 — latticedb가 원래 겨냥한 자리. 위 1과 2 때문에 지금은
  그래프만 남는다.

`init`이나 `terminal`에 링크하는 길은 없다. DB가 필요한 일이 없고 `init`은
[[project_zig_c_uapi_rule]] 쪽이다.

## 다시 꺼낼 때

- 조건은 한글이다. 업스트림 토크나이저가 UTF-8을 단어 문자로 인정하고(띄어쓰기 없는
  검색을 위해서는 bigram 같은 CJK 분할까지) 고쳐졌는지 먼저 본다. 우리가 고쳐서
  올리는 것도 길이다 — [[project_hangul_input]]을 해 본 영역이다.
- 다시 꺼낼 자연스러운 때는 최종 비전의 "AI 코딩 도구 통합" 서브프로젝트를 열 때다.
- 남의 것을 쓸지 정하는 기준은 [[project_write_or_reuse]].
