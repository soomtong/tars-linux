# GI-M0 — 컨테이너 이미지를 ghcr.io에서 받는다

Date: 2026-10-31
Design: `docs/specs/2026-10-31-tars-ghcr-image-design.md`
Status: 착수

## 착수 전에 확정한 것

design의 확인 1~7에 더해, plan을 쓰며 읽은 것.

1. `quick_check.sh`의 shellcheck 대상은 "추적 중인 `*.sh` 전부"(`git ls-files`)다. 새 `devcontainer/image.sh`는 `git add` 뒤에야
   검사에 든다 — Task 1의 확인 (a)는 add 뒤에 돈다. 51 → 52파일.
2. Dockerfile의 첫 줄은 ZM-M3 주석 다섯 줄 뒤 `FROM`이다. 세대 줄(design 결정 4)은 그 주석 위, 파일 첫 줄에 둔다 — 갱신하려는
   사람이 처음 보는 자리. LABEL은 마지막 `WORKDIR /workspace` 뒤.
3. `checks.yml`의 `container` job은 지금 `permissions`가 없다(워크플로 기본값 = 쓰기 전부). job에 `permissions:`를 적는 순간 적은
   것만 남으므로 `contents: read`를 함께 적는다. `host` job은 손대지 않는다.
4. 이미지 이름 · 태그 계산은 `image.sh` 안에만 있다. Makefile · `checks.yml`은 이름을 모르고 스크립트만 부른다 — 이름을 바꾸는 날
   고칠 자리가 하나다.
5. 로컬 ID `6c2674d36158`는 (f)에서 `docker rmi`로 사라진다. 그 전에 (b)의 build가 LABEL 층을 더한 새 로컬 이미지를 만들므로
   `6c2674d36158`는 (b)에서 이미 태그를 잃는다(dangling) — 게이트 (g)는 받은 이미지로 돈다.

## Task 1 — 스크립트 · Makefile · CI · Dockerfile · README

`devcontainer/image.sh`(새 파일, bash, `set -euo pipefail`):

```
IMAGE=ghcr.io/soomtong/tars-devcontainer
LOCAL=tars-devcontainer
TAG="$(shasum -a 256 devcontainer/Dockerfile | cut -c1-12)"
```

- 저장소 루트에서 부른다(Makefile · CI가 그렇다). `cd "$(dirname "$0")/.."`로 스스로 루트에 선다 — 어디서 불러도 같은 해시.
- `pull` — `docker pull "$IMAGE:$TAG"` 성공이면 `docker tag` → `$LOCAL`, `image> pulled $TAG id=…`. 실패면 `image> pull failed $TAG`
  (stderr) exit 1.
- `build` — `docker build -t "$LOCAL" devcontainer/` 뒤 `docker tag "$LOCAL" "$IMAGE:$TAG"`와 `:latest`. `image> built $TAG id=…`.
- `push` — `docker push "$IMAGE:$TAG"` · `docker push "$IMAGE:latest"`. 로그인은 안 한다.
- `tag` — 태그 문자열만 찍는다(사람이 ghcr에서 찾을 때 · commit 메시지에 적을 때).
- 인자가 없거나 다르면 usage, exit 2.

`Makefile` — `container` 타깃의 `docker build` 줄이 `./devcontainer/image.sh pull || ./devcontainer/image.sh build`. 메시지
"devcontainer/에서 굽는다 (처음 한 번, 몇 분)" → "ghcr.io에서 받는다(1.5GB). 없거나 오프라인이면 굽는다". help의 두 줄도 같은 말로.

`.github/workflows/checks.yml` — `container` job:

```
permissions:
  contents: read
  packages: write
```

`docker build` step 하나가 셋이 된다.

```
- name: image (pull or build)
  id: image
  run: |
    if ./devcontainer/image.sh pull; then echo built=0 >> "$GITHUB_OUTPUT"
    else ./devcontainer/image.sh build && echo built=1 >> "$GITHUB_OUTPUT"; fi
- name: image push
  if: github.event_name == 'push' && steps.image.outputs.built == '1'
  run: |
    echo "${{ github.token }}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin
    ./devcontainer/image.sh push
```

주석은 design을 가리키고 "받으면 올릴 것이 없다 · 브랜치 · PR은 올리지 않는다 · 제3자 action 없음"을 적는다. 머리 주석의 `container`
설명 한 줄("그대로 굽고")도 "ghcr.io에서 받거나 굽고"로.

`devcontainer/Dockerfile` — 첫 줄에 세대 줄, 끝에 LABEL.

```
# 이미지 세대: 2026-10-31. 이 파일의 sha256 앞 12자가 ghcr.io 태그다(devcontainer/image.sh) —
# 이 날짜를 바꾸면 해시가 바뀌어 CI가 다시 굽고 올린다(apt 갱신을 받는 길). GI design 결정 4.
```

```
# ghcr.io 패키지를 이 저장소에 연결한다(GI design 확인 6). 끝에 두어 이 층만 다시 굽힌다.
LABEL org.opencontainers.image.source=https://github.com/soomtong/tars-linux
```

`README.md` "준비" — `docker build …` 한 줄이 `make container`. 아래 "`--platform`을 붙이지 않는다" 단락은 그대로(굽는 길이 남아 있다).

확인:

- `git diff --stat`, `git diff | rg '^-[^-]'`로 지운 줄 전부(Makefile 두 줄 · `checks.yml`의 `docker build` 줄과 주석 · README 한 줄).
- (a) `git add devcontainer/image.sh` 뒤 `make quick` PASS, `shellcheck 52 files`.
- (b) `./devcontainer/image.sh tag` → 12자. `pull` → `pull failed`, rc 1. `build` → LABEL 층만(캐시), `image> built`. `docker image inspect
  tars-devcontainer --format '{{index .Config.Labels "org.opencontainers.image.source"}}'` → 저장소 URL. `docker image ls`에 ghcr
  이름 둘(해시 · latest)이 같은 ID.

## Task 2 — CI 두 회차 · 공개 전환 · 로컬 받기 · 게이트 · 닫기

- commit(Task 1) → push → `gh run watch`. (c) `container` 로그의 `image (pull or build)` step에 `pull failed` 뒤 `image> built <태그>`,
  `image push` step에 digest 줄. `host` 초록. 시간을 적는다.
- (d) 사용자: https://github.com/users/soomtong/packages/container/tars-devcontainer/settings 에서 Change visibility → Public.
  저장소 페이지 Packages 칸에 뜨는지.
- (e) `gh workflow run checks.yml --ref main` → `image> pulled <태그>`, `image push` skipped. `container` 시간을 (c)와 비교.
- (f) 로컬 `docker rmi tars-devcontainer ghcr.io/soomtong/tars-devcontainer:<태그> ghcr.io/soomtong/tars-devcontainer:latest` →
  `make container` → `image> pulled`. `docker image inspect --format '{{.Id}}'`를 (c)의 ID와 비교, 다르면 `{{.RepoDigests}}`.
- (g) 루트 게이트 1회(약 10분, `/tmp/gate.log`, `run_in_background`). 22/22, verify 줄 전부 `ok`.
- 문서(design "닫을 때"): design `Status:` · `completed.md` 한 행 · `project_github_actions.md` "남긴 것"과 GI-M0 단락 · `MEMORY.md` ·
  `project_zig_upgrade.md` 한 줄 · `key-files.md` · `lessons.md` 범용 명령 · `HANDOFF.md`. commit(닫기), push → CI 초록(세 번째 회차,
  `pulled`).

## 결과

(Task마다 적는다)
