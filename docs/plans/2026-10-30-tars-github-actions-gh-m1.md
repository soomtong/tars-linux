# GH-M1 — 컨테이너 안 `zig build test`

Date: 2026-10-30
Design: `docs/specs/2026-10-30-tars-github-actions-design.md`의 "GH-M1" 절(결정 8~11)
Status: plan

## 착수 전에 확정한 것

design의 GH-M1 확인 1~6에 더해, plan을 쓰며 읽은 것.

1. 두 줄의 원문은 `check.sh`의 `prebuild()`(727 · 728행)다 — `(cd init && zig build && zig build test)` ·
   `(cd terminal && ./prepare.sh && zig build test)`. `checks.yml`의 `docker run … bash -c '…'` 안에는 괄호 없이 같은 글자를 둔다
   (`bash -c` 하나가 이미 subshell이다).
2. 지금 `container` job의 셋째 step이 `bash -c 'cd init && zig build'`다. 그 줄에 `&& zig build test`를 붙이고, 그 위 주석을
   고친다.
3. init 검사는 `/tmp/tars-test-<pid>`에 쓰고(`test_scratch.zig`), terminal의 `prepare.sh`는 `terminal/ghostty-src` · `vendor/` ·
   `zig-pkg/`에 받는다 — 셋 다 `.gitignore`에 있다. runner의 checkout은 job이 끝나면 버려지므로 지울 것이 없다.
4. 컨테이너는 root로 돈다. `/workspace`에 root가 파일을 써도 job 안에서만 쓰이므로 M0의 `cd init && zig build`와 같은 처지다
   (M0에서 문제가 없었다).
5. mutation 자리.
   - (a) `init/src/version_test.zig:17` — 첫 칸 `"tag, clean"`의 기대값 `"0.1.0"`을 `"0.1.1"`로. 기대 로그는
     `FAIL: tag, clean: got '0.1.0', want '0.1.1'`과 `error.ReleaseNotBare`.
   - (b) `terminal/src/layout_test.zig:66` — `expectCount(&t, 1)`을 `expectCount(&t, 2)`로. 기대 로그는 `FAIL: count = 1, want 2`와
     `error.WrongCount`.
   - 둘 다 기대값만 바꾸므로 컴파일은 된다. 빨강이 검사의 판정이라는 것을 로그의 `FAIL:` 줄로 확인한다.
6. 게이트가 읽는 파일은 0줄 바뀐다(`checks.yml` · README · 문서). 루트 게이트는 돌지 않는다(design 결정 10).

## Task 1 — `checks.yml` · README 한 줄

`.github/workflows/checks.yml`의 머리 주석 `container` 설명과 셋째 step을 바꾸고, 넷째 step을 더한다.

머리 주석(10행 근처):

```yaml
#   container  arm64 runner. devcontainer/Dockerfile이 zig-aarch64를 받으므로(ZM-M3) amd64에서는
#              못 쓴다. 그대로 굽고, 안에서 BF-M0 sanity 부팅과 게이트 prebuild의 두 줄(init · terminal의
#              zig build test, GH-M1)을 돌린다.
```

step:

```yaml
      # 게이트 prebuild(check.sh)의 init 줄과 글자가 같다(GH-M1 design 결정 8). zig build는 이미지 안의
      # zig(aarch64)가 게스트 바이너리 넷을 만들고 — host job의 5단계와 짝 — zig build test는 호스트 검사
      # 열일곱을 이 arm64 Linux에서 돌린다. macOS에서는 init 검사가 안 끝나 quick_check.sh에 없다.
      - name: init build and test
        run: docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c 'cd init && zig build && zig build test'

      # 같은 prebuild의 terminal 줄. prepare.sh가 ghostty · stb 둘 · unifont · zon 의존성을 받는다 —
      # 여기의 빨강이 curl이나 fetching 줄이면 우리 코드가 아니다(gh run rerun). step을 init과 나눈 것은
      # 빨강의 자리를 step 이름이 말하게 하려는 것이다(결정 9).
      - name: terminal prepare and test
        run: docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c 'cd terminal && ./prepare.sh && zig build test'
```

앞의 두 step에는 `name`이 없다. 이번에 더하는 둘에만 이름을 두면 Actions 화면에서 두 이름이 바로 보인다 — 앞 둘은 그대로 둔다
(M0의 줄을 건드리지 않는다).

README 4행:

```markdown
정적 검사 · 컨테이너 빌드 · 호스트 검사(`zig build test`)다 — 부팅 판정인 게이트는 로컬 `make gate`.
```

확인: 로컬에서 `make quick`(shellcheck는 `.yml`을 안 보지만 머리 주석이 바뀐 것과 무관함을 한 번 본다) → commit → push →
`gh run watch`. 두 job 초록, `container`의 step별 시간(build · sanity · init · terminal)을 결과 절에 적는다. 10분을 넘으면 그 숫자를
들고 사용자에게 캐시를 물을 것(design 비목표 9).

## Task 2 — mutation 둘 · 문서 · 닫기

mutation(commit 없음, 브랜치는 지운다):

- 임시 브랜치 `gh-m1-mut-a`: 확정 5의 (a). `git diff`로 한 줄 바뀐 것을 보고 commit · push →
  `gh workflow run checks.yml --ref gh-m1-mut-a` → `container`의 `init build and test`가 빨강, 로그에 `FAIL: tag, clean`. `host` 초록.
- 임시 브랜치 `gh-m1-mut-b`: 확정 5의 (b). 같은 순서 → `terminal prepare and test`가 빨강, 로그에 `FAIL: count = 1, want 2`. `host`
  초록. (a)의 init step은 초록이어야 한다.
- 두 브랜치 삭제(원격 · 로컬).

문서:

- design `Status:` → GH-M1 끝남(숫자).
- `docs/guides/key-files.md`의 `checks.yml` 줄 — `container`의 괄호를 "sanity · prebuild의 두 줄(init · terminal의 `zig build test`)"로.
- `docs/guides/lessons.md` "범용 명령"의 `make quick` 주석 — "호스트 검사(`zig build test`)는 여기에 없고 CI의 container job이
  돈다(GH-M1)" 한 줄.
- `docs/decisions/project_github_actions.md` — GH-M1 절(무엇 · 숫자 · 함정), "남긴 것"에서 이 항목 지우기, description 갱신.
  `MEMORY.md`의 그 줄도.
- `docs/guides/completed.md` — GH 행을 GH-M0~M1로 고치고 M1의 한 줄을 더한다.
- `HANDOFF.md`.

commit 하나(닫기). 소개 페이지에는 안 넣는다(내부 작업).

## 결과

(Task마다 채운다)
