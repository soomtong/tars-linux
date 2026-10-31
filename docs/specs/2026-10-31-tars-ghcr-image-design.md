# TARS Ghcr Image — Design

Date: 2026-10-31
Status: 끝났다 — GI-M0(2026-10-31, `ghcr.io/soomtong/tars-devcontainer:f54d9852ec88`, CI 1회차 built+push · 2회차 pulled(이미지 몫 78 → 25초), 로컬 pull 42초 ID 같음, 패키지는 처음부터 공개, 루트 게이트 22/22 10분 3초(prebuild 299 + lanes 301초), verify 8104줄 전부 통과). plan은 `docs/plans/2026-10-31-tars-ghcr-image-gi-m0.md`

GH-M1이 남긴 다음 후보 가운데 마지막 하나(ghcr.io 이미지). 사용자가 골랐다(2026-10-31, VS-M0을 닫은 뒤).

## 한 줄 요약

컨테이너 이미지를 push마다 · 사람마다 다시 굽는 대신, Dockerfile 내용의 해시를 태그로 삼아 `ghcr.io/soomtong/tars-devcontainer`에
한 번 올려 두고 게이트 · CI · 새 저장소가 같은 이미지를 받는다. 태그가 없으면(Dockerfile이 바뀌었으면) CI가 굽고 올린다. 로컬
태그 `tars-devcontainer`와 그것을 읽는 자리(Makefile · `checks.yml`의 `docker run` 넷 · README)는 그대로다. 코드(Zig) 0줄.

## 배경

- 지금 이미지는 쓰는 자리마다 따로 굽는다 — 사람은 `make container`(없을 때 한 번), CI `container` job은 push마다 깨끗한 runner에서
  `docker build`. Dockerfile이 같아도 구운 날이 다르면 apt 층(824MB)의 패키지 버전이 다르다. VS design 비목표 2가 "베이스 digest 핀은
  뜻이 없고 ghcr.io 이미지가 그 층을 통째로 고정하는 길"이라고 적어 둔 자리다.
- 시간은 이유가 아니다. CI의 `docker build`는 캐시 없이 46~50초이고 `container` job 6분 41초~7분 30초의 나머지는 Zig 빌드다(GH-M0
  "걱정이 틀렸다"). 받기로 바꿔 줄어드는 것은 많아야 30초쯤이다. 얻는 것은 동일성 — 게이트가 22/22를 찍은 이미지와 CI가 초록을
  찍은 이미지와 새 사람이 받는 이미지가 같은 digest라는 것.
- 등록에 장벽은 없다. GitHub 계정이면 되고, 공개 패키지는 저장 · 전송이 무료다. 올리는 데는 `write:packages` 권한이 필요하고 받는 데는
  (공개면) 아무것도 필요 없다.

## 착수 전에 확인한 것

2026-10-31, HEAD `f59c98a`.

1. 이미지. `tars-devcontainer` ID `6c2674d36158`(VS-M0이 구웠다), arm64, 1.54GB. 층은 넷 — debian trixie-slim 101MB · apt 824MB ·
   amd64 sysroot 258MB · Zig 360MB. Dockerfile에 `COPY` · `ADD`가 없다 — 빌드 컨텍스트를 안 읽으므로 Dockerfile 내용 하나가 레시피
   전부다. README의 `-f devcontainer/Dockerfile .`(컨텍스트 루트)과 Makefile · CI의 `devcontainer/`(컨텍스트 폴더)가 같은 이미지를
   만드는 이유이고, 해시를 Dockerfile 한 파일에서 뽑아도 되는 이유다.
2. CI. 최근 세 회차 `container` 6분 41초 · 6분 59초 · 6분 56초, 그 안의 `docker build` 46~50초(GH-M1 plan). runner는 `ubuntu-24.04-arm`
   — 우리 이미지와 같은 arm64라 받은 이미지를 그대로 돌릴 수 있다.
3. 권한. `gh auth status`의 토큰 범위는 `repo` · `read:org` · `gist` · `admin:public_key` — `write:packages`가 없다. 로컬에서 올리려면
   PAT를 따로 만들어야 한다. Actions의 `GITHUB_TOKEN`은 job에 `permissions: packages: write` 한 줄이면 같은 저장소 소유의 패키지에
   올릴 수 있다. 저장소는 공개(`soomtong/tars-linux`, PUBLIC).
4. 이미지 이름이 읽히는 자리. Makefile `CONTAINER ?= tars-devcontainer`(타깃 열 개가 `container`에 의존), `checks.yml`의 `docker build
   -t tars-devcontainer` 하나와 `docker run … tars-devcontainer` 넷, README 다섯 줄(준비 · 빌드 · 게이트 셋), `probe/run.sh` 주석 하나.
   게이트 `check.sh` 자체는 이름을 모른다(밖에서 `docker run`으로 들어온다).
5. 해시 도구. `shasum -a 256`이 macOS(`/usr/bin/shasum`, Perl)와 Linux runner 양쪽에 있다. `sha256sum`은 macOS 기본에 없다(지금은
   `/sbin/sha256sum`이 있지만 coreutils 설치분이다). 오늘 Dockerfile의 앞 12자는 `20da2fc38301` — 결정 2의 LABEL이 들어가면 바뀐다.
6. ghcr.io의 규칙. 이름은 `ghcr.io/<계정>/<이름>`. 이미지에 `org.opencontainers.image.source` 라벨이 저장소 URL이면 패키지가 그
   저장소에 연결돼 저장소 페이지 옆에 보이고, 그 저장소의 Actions 토큰이 올릴 권한을 갖는다. 태그를 덮어쓰는 것을 막는 장치는
   없다(위험 1). 착수 전에는 "첫 push가 만드는 패키지는 비공개라 UI에서 한 번 공개로 바꾼다"라고 적었는데 틀렸다 — 공개 저장소에
   라벨로 연결된 패키지를 그 저장소의 Actions가 처음 올리면 저장소의 공개 여부를 그대로 받는다. GI-M0의 첫 push 직후 익명
   `docker manifest inspect`가 읽혔다(plan 결과). 사람이 할 일은 없었다.
7. 이미지 ID의 동일성. 받은 이미지의 ID는 config의 digest라 올린 쪽과 같아야 한다. 확인은 결정 6의 (f)가 한다 — 다르면 manifest
   digest(`RepoDigests`)로 비교한다.

## 결정

### 결정 1. 태그는 Dockerfile 내용의 sha256 앞 12자

`ghcr.io/soomtong/tars-devcontainer:<shasum -a 256 devcontainer/Dockerfile | cut -c1-12>`. 커밋 SHA가 아니다 — Dockerfile은 드물게
바뀌는데 커밋마다 1.5GB를 올리거나 경로 필터를 두어야 하고, 어느 커밋의 이미지인지보다 "어느 Dockerfile의 이미지인지"가 묻는 것이다.
해시 태그는 그 물음에 바로 답하고, 태그가 없다는 사실이 "이 Dockerfile로는 아직 안 구웠다"를 뜻해 굽는 조건이 따로 필요 없다.
Dockerfile을 한 줄이라도 고치면(주석도) 새 태그가 되고 다음 CI가 굽는다 — 이것이 갱신 정책이다(결정 4).

`latest`도 함께 올린다(같은 층이라 저장이 늘지 않는다). 사람이 `docker pull ghcr.io/soomtong/tars-devcontainer`로 둘러볼 때의 것이고,
스크립트는 `latest`를 읽지 않는다 — 옛 checkout에서 받으면 그 Dockerfile의 것이 아닐 수 있기 때문이다.

### 결정 2. 판단은 `devcontainer/image.sh` 한 곳

`pull` · `build` · `push` 셋을 받는 스크립트 하나. 로컬 태그 `tars-devcontainer`는 그대로 두고 받은 것 · 구운 것을 거기에 붙인다
(`docker tag`). 그래서 `docker run … tars-devcontainer` 줄은 README · `checks.yml` 어디서도 바뀌지 않는다.

- `pull` — `docker pull ghcr.io/…:<태그>` 뒤 `tars-devcontainer`로 태그. 실패(없음 · 네트워크 · 비공개)는 exit 1이고 `image> pull
  failed <태그>` 한 줄.
- `build` — `docker build -t tars-devcontainer devcontainer/`(Makefile · CI의 지금 줄 그대로) 뒤 ghcr 이름으로도 태그.
- `push` — `docker push` 둘(해시 태그 · `latest`). 로그인은 하지 않는다(부르는 쪽, CI만).
- 끝나면 `image> pulled|built <태그> id=<12자>` 한 줄 — 로그에서 어느 길을 탔는지 읽히게.

Makefile `container`는 지금처럼 로컬 이미지가 없을 때만 움직이되, 그때 `./devcontainer/image.sh pull || ./devcontainer/image.sh build`다.
오프라인이거나 아직 안 올라간 태그면 굽는다(지금과 같은 결과). 로컬에 `tars-devcontainer`가 이미 있으면 Dockerfile이 바뀌어도 안
움직인다 — 지금의 규칙 그대로(VS 위험 4)이고, 새 Dockerfile의 이미지를 쓰려면 `docker rmi tars-devcontainer && make container`다.
이것을 자동으로 따라가게(태그 비교) 하지 않는 이유는 `git pull` 한 번에 1.5GB를 받는 일이 사람 모르게 시작되기 때문이다 —
Dockerfile을 바꾸는 사람이 commit 메시지에 적는다(지금도 "image rebuilt"라고 적어 왔다).

### 결정 3. 올리는 쪽은 CI만, `main`의 push만

`checks.yml`의 `container` job에 `permissions: packages: write`(`contents: read`도 같이 — permissions를 적으면 기본값이 없어진다).
`docker build` step이 다음 셋이 된다.

1. `./devcontainer/image.sh pull || ./devcontainer/image.sh build`
2. `if: github.event_name == 'push'` — 구웠을 때만 `docker login ghcr.io`(`GITHUB_TOKEN` · `github.actor`, `--password-stdin`) 뒤
   `./devcontainer/image.sh push`. 받았을 때는 올릴 것이 없다 — 1의 결과를 `$GITHUB_OUTPUT`에 `built=1`로 남겨 조건에 쓴다.

브랜치(`workflow_dispatch`) · PR은 받거나 굽기만 하고 올리지 않는다 — 트리거는 `main` push만이므로 `main`에 들어온 Dockerfile만
ghcr에 간다. fork의 PR은 토큰이 읽기 전용이라 어차피 못 올리고, 그 경우 굽기만 하는 길이 곧 지금의 CI다. 제3자 action은 없다 —
`docker login` · `docker push` 두 명령(GH design "무엇이 도는지 이 파일에서 읽히게").

로컬에서 올리는 길은 만들지 않는다(확인 3 — PAT를 만들고 keychain에 두는 일이고, Actions가 같은 Dockerfile로 어차피 굽는다).

### 결정 4. 갱신은 Dockerfile을 고치는 것으로

이미지는 Dockerfile이 바뀔 때까지 얼어 있다 — apt의 보안 갱신도 들어오지 않는다. 그것을 받고 싶으면 Dockerfile 머리의 한 줄
`# 이미지 세대: 2026-10-31 — 이 줄의 날짜를 바꾸면 해시가 바뀌어 CI가 다시 굽고 올린다`의 날짜를 바꾼다. 패키지 하나를 더할 때는
그 변경 자체가 새 해시다. 옛 태그는 ghcr에 남는다(위험 3).

### 결정 5. Dockerfile에 LABEL 하나, README "준비"의 첫 줄

- Dockerfile 끝(`WORKDIR` 뒤)에 `LABEL org.opencontainers.image.source=https://github.com/soomtong/tars-linux`. 끝에 두는 이유는 그
  층만 바뀌어 로컬 재굽기가 캐시로 끝나게(VS-M0의 Zig 층 뒤라 19초 안). 확인 6의 연결이 이것으로 된다.
- README "준비": `docker build …` 한 줄이 `make container`가 된다 — "ghcr.io에서 받는다(1.5GB). 없거나 오프라인이면 굽는다". 게이트 ·
  빌드 줄의 `tars-devcontainer`는 그대로. GH design이 M1 후보에서 "README 준비의 첫 줄이 바뀐다"라고 적어 둔 그 변경이다.
- `probe/run.sh` 주석은 그대로(이름이 안 바뀐다).

### 결정 6. 검증

게이트 입력은 Dockerfile(LABEL)이다 — 이미지가 바뀌므로 루트 게이트를 돈다. 순서가 있다: 첫 push가 패키지를 비공개로 만들므로
공개로 바꾼 뒤에야 로컬이 받을 수 있다.

- (a) `make quick` PASS — shellcheck가 `image.sh`를 본다(51 → 52파일).
- (b) 로컬 `./devcontainer/image.sh pull`이 `pull failed`(아직 없다)로 exit 1, `build`가 LABEL 층만 다시 굽는다(짧다). `docker image
  inspect`로 라벨 확인.
- (c) push → CI 1회차. `container` 로그에 `image> built <태그>`와 push의 digest 줄. `host`는 바뀐 것이 없다.
- (d) 패키지가 공개인지 — 익명 `docker manifest inspect`. (착수 전에는 "사용자가 UI에서 Public으로 한 번"이었는데 공개 저장소의
  Actions가 올린 패키지는 처음부터 공개였다. 확인 6.)
- (e) CI 2회차(`gh workflow run checks.yml --ref main`). 로그에 `image> pulled <태그>`, push step은 건너뜀. `container` 시간을 1회차와
  비교해 적는다(기대: 30초 안의 차이).
- (f) 로컬 `docker rmi tars-devcontainer` → `make container` → `image> pulled`. `docker image inspect --format '{{.Id}}'`가 (c)의 ID와
  같은지(확인 7). 다르면 `RepoDigests`로.
- (g) 받은 이미지로 루트 게이트 1회(약 10분). 22/22, verify 줄 전부 `ok`.

mutation은 따로 두지 않는다 — "태그 없음 → 굽기 → 올리기"는 (c)가, "태그 있음 → 받기"는 (e) · (f)가 그 길 자체다. Dockerfile을
한 글자 바꾸는 mutation은 (c)와 같은 길을 1.5GB 더 올리며 다시 타는 것이라 하지 않는다.

## 위험

1. ghcr.io 장애. CI는 `pull` 실패 → `build` → `push`도 실패해 빨강 — `curl` 빨강과 같은 "우리 코드가 아닌" 종류, `gh run rerun`.
   받기만 실패하고 올리기는 되는 반쪽 장애면 같은 태그를 다른 빌드로 덮어쓴다(확인 6, 막는 장치 없음). 같은 Dockerfile의 다른
   빌드라 깨지는 것은 없고 "그날의 apt"로 바뀌는 것이다 — 패키지 버전 페이지에 두 digest가 남아 알 수 있다. 로컬은 `build`로
   떨어져 지금과 같다.
2. (착수 전의 걱정 — 비공개인 사이에 새 사람이 받으면 `denied` 뒤 굽는다. 패키지가 처음부터 공개여서 그런 사이가 없었다. 남는
   사실 하나: ghcr은 없는 태그도 비공개도 똑같이 `denied`로 답하므로 `pull failed` 메시지가 세 경우를 다 말한다.)
3. 저장이 쌓인다. Dockerfile을 고칠 때마다 1.5GB 버전이 하나 남는다(층을 거의 공유하지 않는다 — apt 층이 매번 새 바이트다). 공개
   패키지는 무료고 지우는 것은 패키지 버전 페이지에서 손으로(비목표 3). 한 해에 열 번 고치면 15GB다 — 지우기 전에는 digest가
   남아 옛 회차를 다시 받을 수 있다는 것이 쌓이는 쪽의 값이다.
4. 받은 이미지와 구운 이미지의 ID가 다를 수 있다(확인 7). 동일성의 기준은 manifest digest로 두면 되고, (f)가 어느 쪽인지 적는다.
5. 로컬이 Dockerfile을 따라가지 않는다(결정 2). 사람이 `git pull`한 뒤 옛 이미지로 게이트를 돌릴 수 있다 — 지금도 같다. Dockerfile
   커밋 메시지에 "image: <새 태그>"를 적는 습관으로 받는다.
6. CI `container`가 1.5GB를 받는 시간이 굽는 46초보다 길 수 있다(압축 전송 약 500MB 어림). (e)가 잰다. 길어도 동일성이 목표라 되돌릴
   이유는 아니지만, 숫자는 적는다.

## 비목표

1. `buildx` 층 캐시 · 다단계 빌드 — 굽는 시간은 문제가 아니다(배경).
2. amd64 이미지. 이미지는 지금처럼 arm64 하나다(ZM-M3의 결정). amd64 호스트의 사람은 지금도 굽지 못한다.
3. 옛 태그 정리의 자동화(위험 3).
4. 서명 · attestation(cosign · `--provenance`). 공개 저장소의 Actions가 구운 것이고 digest가 identity다.
5. `host` job의 shellcheck · Zig x86_64를 이미지에 넣는 것 — `host`는 amd64라 이 이미지를 못 쓴다.
6. Dockerfile의 apt 층을 날짜 스냅샷(`snapshot.debian.org`)으로 고정하는 것 — 이미지를 고정하면 레시피를 고정할 이유가 줄고,
   레시피를 다시 굽는 날은 새 apt를 받고 싶은 날이다(결정 4).

## Milestone

- GI-M0 — 위 결정 전부. lead가 직접 구현한다(작은 일, 파일 다섯). Task 둘.
  1. `devcontainer/image.sh` · Makefile `container` · `checks.yml`의 step 셋과 permissions · Dockerfile LABEL과 세대 줄 · README 준비.
     검증 (a) · (b).
  2. push → (c) → 사용자의 (d) → (e) · (f) → 루트 게이트 (g) → commit → 닫기.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_github_actions.md`의 "남긴 것"에서 ghcr.io 이미지를 지우고 GI-M0 한 단락(이름 · 태그 규칙 · 갱신 정책 ·
  비공개→공개 한 번). `MEMORY.md`의 GitHub Actions 줄에 덧붙인다 — 새 기억 파일은 만들지 않는다.
- `docs/decisions/project_zig_upgrade.md` "고칠 자리"에 "Dockerfile이 바뀌면 CI가 새 태그를 올린다 — 로컬은 `docker rmi` 뒤 `make
  container`" 한 줄.
- `docs/guides/key-files.md` — `devcontainer/image.sh` 줄, Dockerfile 줄에 "해시 태그로 ghcr.io".
- `docs/guides/lessons.md` "범용 명령"에 받는 줄 하나.
- `HANDOFF.md`. 소개 페이지에는 안 넣는다(내부 작업).

## 관련

- `docs/specs/2026-10-30-tars-github-actions-design.md` — M1 후보 "구운 이미지를 ghcr.io에 올려 다음 사람이 굽지 않게" · 위험 2
  (우리 코드가 아닌 빨강) · "제3자 action 없음".
- `docs/specs/2026-10-31-tars-vendor-sha256-design.md` 비목표 2 — 베이스 digest 핀 대신 이미지를 통째로 고정하는 길이 이것이다.
- `docs/decisions/project_build_host_arch.md` — 이미지가 arm64인 이유(ZM-M3).
