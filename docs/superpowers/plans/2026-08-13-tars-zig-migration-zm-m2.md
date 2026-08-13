# TARS Zig Migration — ZM-M2 Rust 흔적 제거 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md` 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** 저장소와 빌드 이미지에서 Rust를 완전히 없앤다. 소스(`init`의 Cargo
파일과 `main.rs`, `kms/` 전체)와 그 소스를 빌드하던 죽은 게이트
(`display/check.sh`, `kernel/check.sh`), 그리고 `devcontainer/Dockerfile`의
rustup 설치를 지운다. 관측 가능한 동작은 한 줄도 바뀌지 않는다.

**Architecture:** 이 milestone은 **코드를 쓰지 않고 지우기만 한다.** 지우는
대상은 셋으로 나뉘고, 셋 다 "지금 아무도 실행하지 않는 것"임을 먼저 확인한
뒤에 지운다.

1. **Rust 소스** — `init/Cargo.toml`·`Cargo.lock`·`src/main.rs`, `kms/` 전체.
   ZM-M1에서 부팅 경로가 `init/zig-out/bin/init`으로 옮겨졌으므로 이 파일들을
   읽는 것은 아무것도 없다. 빌드 산출물 `init/target/`도 아직 디스크에 남아
   있으므로 함께 지운다 — **`.gitignore`에서 그 줄을 빼기 전에** 지워야
   `git status`에 갑자기 나타나지 않는다(`kms/target/`은 `kms/`를 통째로
   지우면서 함께 사라진다).
2. **죽은 게이트** — `display/check.sh`(TF-M4에서 은퇴, 실행하면 반드시 FAIL),
   그리고 **`kernel/check.sh`**. 후자는 design doc에 안 적혀 있던 항목이다.
   아래 "설계 문서에 없던 항목" 절 참고.
3. **툴체인** — `Dockerfile:25-31`의 rustup 설치. 이미지를 재빌드해야 실제로
   사라진다.

순서는 **소스 → 이미지**다. 소스 삭제 후 옛 이미지(Rust가 아직 있는)로 TF
체인을 한 번 돌려 "지운 것 때문에 깨진 게 없다"를 먼저 확정하고, 그 다음
이미지를 바꾼다. 이렇게 하면 최종 게이트가 깨졌을 때 원인이 파일 삭제인지
이미지 변경인지 바로 갈린다. `make_initrd.sh` 복사 목록 때문에 다른 체인이
조용히 깨진 사고가 이 저장소에 두 번 있었다
([[project_gate_chain_composition]]).

**Tech Stack:** git, bash, Docker(`tars-devcontainer` 이미지), QEMU

---

## 설계 문서에 없던 항목: `kernel/check.sh`

design doc의 ZM-M2 범위에는 `kernel/check.sh`가 빠져 있는데, 이 파일 7번째
줄에 `(cd ../init && cargo build --release)`가 남아 있다. design doc이 정한
완료 조건 1번(`cargo|rustup` 검색 결과 0건)이 이 파일 때문에 성립하지 않으므로
이번에 처리해야 한다. 선택지는 둘이었다.

- **(A) `zig build`로 고쳐서 살린다.**
- **(B) 파일을 지운다.** ← 이걸 택한다.

B인 이유가 셋이다.

1. **이미 깨져 있다.** 이 스크립트는 `./build.sh` → `cargo build` →
   `./make_initrd.sh` 순으로 도는데, 지금 `make_initrd.sh:29`는
   `../terminal/zig-out/bin/terminal`을 복사한다. `kernel/check.sh`는
   `terminal/prepare.sh`를 부르지 않으므로 clean 트리에서는 `cp: cannot stat`으로
   죽는다. `cargo`를 `zig build`로 바꿔도 여전히 죽는다 — 살리려면 TF의
   준비 단계를 통째로 복제해야 한다.
2. **살려도 새로 보는 게 없다.** 이 게이트가 보는 것은 "직접 부팅 →
   fish 배너"인데, 그건 TF 체인이 매 회차 더 강하게(픽셀 + 입력 + PTY까지)
   검증한다. 마지막 커밋이 `083fbbe`(BF-M2 시절)이고 루트 `check.sh`의 체인
   목록에도 없다.
3. **저장소 원칙에 맞는다.** [[project_gate_chain_composition]]의 "낡은
   게이트는 되살리지 않고 은퇴시킨다"가 정확히 이 상황을 위해 적힌 것이다.
   `display/check.sh`와 같은 처분이다.

이 결정으로 design doc의 ZM-M2 절이 바뀌므로 Task 4에서 함께 갱신한다.

## 지우지 않는 것

- **`init/src/main.zig`의 "Rust판" 언급 주석 3곳**(29·90·110번째 줄 근처).
  "왜 이 코드가 이렇게 생겼는가"를 설명하는 주석이고, 완료 조건이 금지하는
  것은 `cargo`/`rustup`이지 Rust라는 단어가 아니다. 지우면 `mkdir`이 `EXIST`를
  무시하는 이유 같은 맥락이 사라진다.
- **`terminal/check.sh:194`의 ZM-M1 경위 주석.** 같은 이유다.
- **`kernel/check-virtio-gpu.sh`.** `kernel/check.sh`와 이름이 비슷하지만
  성격이 다르다 — 아무것도 빌드하지 않고, 이미 만들어진 `bzImage`/`initrd.cpio`로
  virtio-gpu를 붙여 부팅해 `tars-init: /dev/dri/card0 exists`만 확인하는 수동
  도구다. Rust와 무관하고 지금도 동작하므로 건드리지 않는다.
- **`MEMORY.md` / `docs/**` / `HANDOFF.md`의 Rust 언급.** 기록이다. 단,
  `MEMORY.md`가 가리키는 `project_zig_rewrite_intent`는 "재작성 예정"이라고
  쓰여 있어 사실과 어긋나게 되므로 Task 4에서 갱신한다.

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
시작 상태는 ZM-M1 완료 직후다 — `main` 브랜치, working tree 깨끗함,
`origin/main`보다 7 커밋 앞섬(push 안 함), 마지막 커밋 `61dccc9`.

Task 2에 **네트워크가 필요하다**(Docker 이미지 재빌드에서 apt와 Zig
tarball을 다시 받는다). 오프라인이면 Task 1까지만 하고 멈춘다.

---

## Task 1: Rust 소스와 죽은 게이트 삭제

**Files:**
- Delete: `init/Cargo.toml`, `init/Cargo.lock`, `init/src/main.rs`, `init/target/`
- Delete: `kms/` (`Cargo.toml`, `Cargo.lock`, `src/main.rs`, 그리고 추적되지
  않는 빈 디렉터리 `kms/src/kms/`)
- Delete: `display/` (`check.sh` 하나뿐)
- Delete: `kernel/check.sh`
- Modify: `.gitignore:10`, `.gitignore:13`
- Modify: `check.sh:15-16`, `check.sh:38-40`

- [ ] **Step 1: 지우기 전에 "아무도 안 읽는다"를 확인**

지우는 것이 목적인 Task라 되돌리기가 쉽지 않다. 먼저 참조가 없다는 근거를
남긴다.

Run:
```bash
rg -n 'Cargo|main\.rs|kms/|display/|kernel/check' \
  --glob '!docs/**' --glob '!terminal/ghostty-src/**' \
  --glob '!HANDOFF.md' --glob '!MEMORY.md' .
```

Expected — 나오는 줄은 **지울 파일 자신과 지울 주석뿐**이어야 한다:

```
display/check.sh:16:# 파일과 kms/ 크레이트를 남겨두는 것은 Rust로 쓴 DRM 참조 구현으로서의
check.sh:15:# kms/target은 목록에서 빠졌다 — TF-M2 이후 kms를 빌드하는 체인이 없다
check.sh:39:# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. DF 체인(display/check.sh)은
.gitignore:13:kms/target/
```

`boot/check.sh`·`terminal/check.sh`·`kernel/make_initrd.sh`·`kernel/build.sh`
중 하나라도 여기 나오면 멈추고 알릴 것 — 살아 있는 체인이 지울 대상을
읽고 있다는 뜻이다.

- [ ] **Step 2: 파일 삭제**

Run:
```bash
rm -f init/Cargo.toml init/Cargo.lock init/src/main.rs
rm -rf init/target kms display
rm -f kernel/check.sh
```

`init/target`은 `.gitignore` 대상이라 `fd`/`rg`의 기본 검색에 안 잡힌다
(무시 목록을 보려면 `-I`가 필요하다). 실제로는 `release/`와 `.rustc_info.json`이
들어 있는 채로 남아 있었다.

- [ ] **Step 3: 삭제 결과 확인**

Run:
```bash
ls init init/src kernel
ls kms display 2>&1
```

Expected:
- `init` → `build.zig`, `src`(그리고 있다면 `zig-out`/`.zig-cache`)
- `init/src` → `main.zig` 하나
- `kernel` → `build.sh`, `make_initrd.sh` (`check.sh` 없음)
- 마지막 줄 → `No such file or directory` 두 번

- [ ] **Step 4: `.gitignore`에서 Rust 산출물 경로 제거**

`init/target/`(10번째 줄)과 `kms/target/`(13번째 줄)을 지운다. 수정 후 해당
블록은 이렇게 된다:

```gitignore
kernel/src/
kernel/build/
kernel/initrd.cpio

init/zig-out/
init/.zig-cache/

boot/limine-binary/
```

- [ ] **Step 5: 루트 `check.sh`의 주석 두 곳 정리**

첫째, `clean()` 바로 위 15~16번째 줄을 **삭제**한다. kms가 없어졌으므로
"kms/target은 목록에서 빠졌다"는 설명 자체가 의미를 잃는다.

```bash
# kms/target은 목록에서 빠졌다 — TF-M2 이후 kms를 빌드하는 체인이 없다
# (2026-08-12, TF-M4).
```

지우고 나면 그 위의 빈 주석 줄(`#`)도 함께 지워, `clean()` 앞 주석 블록이
아래처럼 vendor 트리 설명에서 바로 끝나게 한다:

```bash
# 이 셋은 네트워크가 있어야만 복구되므로, clean 대상에 넣으면 매 회차 수백
# MB를 다시 받고 오프라인에서는 아예 복구가 불가능하다.
clean() {
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
}
```

둘째, 체인 목록 위 38~40번째 줄을 다음으로 바꾼다. 없어진 파일을 "그 파일
머리말 참고"라고 가리키고 있으므로 그대로 두면 다음 사람이 헛걸음한다.

수정 전:
```bash
# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. DF 체인(display/check.sh)은
# TF-M4에서 은퇴했다 — 이유는 그 파일 머리말 참고.
```

수정 후:
```bash
# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. 한때 있던 DF 체인
# (display/check.sh)과 kernel/check.sh는 ZM-M2에서 파일까지 지웠다 — 은퇴
# 사유는 docs/decisions/project_gate_chain_composition.md 참고.
```

- [ ] **Step 6: 소스 쪽 완료 조건 확인**

design doc 완료 조건 1번을 소스 트리에 대해 먼저 건다. 이 시점에 남아 있어야
하는 것은 `Dockerfile`뿐이다.

Run:
```bash
rg -n 'cargo|rustup' \
  --glob '!docs/**' --glob '!terminal/ghostty-src/**' \
  --glob '!HANDOFF.md' --glob '!MEMORY.md' .
```

Expected — 정확히 이 네 줄:

```
devcontainer/Dockerfile:25:ENV RUSTUP_HOME=/usr/local/rustup \
devcontainer/Dockerfile:26:    CARGO_HOME=/usr/local/cargo \
devcontainer/Dockerfile:27:    PATH=/usr/local/cargo/bin:$PATH
devcontainer/Dockerfile:29:RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
```

`--glob`으로 뺀 넷은 문서·기록이거나(`docs/`, `HANDOFF.md`, `MEMORY.md`)
우리 코드가 아니다(`terminal/ghostty-src`는 vendor된 ghostty 소스).

- [ ] **Step 7: TF 체인 1회 — 지운 것 때문에 깨진 게 없는지**

**이 Step을 건너뛰고 Task 2로 가지 말 것.** 여기서 통과해 두어야 이미지를
바꾼 뒤 게이트가 깨졌을 때 "삭제 때문"을 후보에서 뺄 수 있다. 아직 옛
이미지(Rust가 들어 있는)를 쓴다 — 그게 이 Step의 요점이다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/zm-m2-tf.log
```

Expected: 마지막 줄이 `PASS`. 그 직전에 이 두 줄이 보여야 한다.

```
--- init log ---
...
init mounted all four filesystems
```

`cp: cannot stat` 류의 에러가 나오면 지우면 안 되는 것을 지운 것이다 —
`git status`와 함께 그대로 알릴 것.

- [ ] **Step 8: Commit**

Claude가 수행한다(`docs/decisions/feedback_commit_delegation.md`). 커밋 전에
`git status`로 삭제 목록이 예상과 같은지 확인한다 — 지워진 파일은 7개
(`init` 3, `kms` 3, `display/check.sh`), 수정된 파일은 2개(`.gitignore`,
`check.sh`), `kernel/check.sh`까지 8개 삭제다.

---

## Task 2: Dockerfile에서 rustup 제거하고 이미지 재빌드

**Files:**
- Modify: `devcontainer/Dockerfile:25-31`

- [ ] **Step 1: 되돌아갈 이미지를 태그로 남긴다**

재빌드는 `debian:trixie-slim`과 apt 패키지를 다시 받는다. 그 사이에 fish나
QEMU 버전이 올라가 있으면 게이트 실패 원인이 우리 변경이 아닐 수 있다. 옛
이미지를 이름 하나로 붙잡아 두면 그 비교가 가능해진다(비용은 태그 하나뿐,
레이어는 이미 디스크에 있다).

Run:
```bash
docker tag tars-devcontainer tars-devcontainer:pre-zm-m2
docker images tars-devcontainer
```

Expected: `latest`와 `pre-zm-m2` 두 줄이 같은 IMAGE ID로 나온다. **SIZE 값을
기록해 둘 것** — rustup minimal이 빠지면 얼마나 줄어드는지 Step 4에서 비교한다.

- [ ] **Step 2: `Dockerfile`에서 rustup 블록 삭제**

25~31번째 줄(ENV 블록 3줄 + 빈 줄 + RUN 3줄)을 지운다. 수정 후 그 부분은
apt 블록 끝에서 Zig 설치로 바로 이어진다:

```dockerfile
        unzip \
    && rm -rf /var/lib/apt/lists/*

ENV ZIG_VERSION=0.16.0 \
    PATH=/usr/local/zig:$PATH

RUN curl -sSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /usr/local/zig \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz
```

`curl`은 지우지 않는다 — Zig tarball을 받는 데 그대로 쓴다.

- [ ] **Step 3: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0, 마지막에 `naming to docker.io/library/tars-devcontainer:latest done`
(또는 `Successfully tagged tars-devcontainer:latest`).

apt 레이어는 캐시가 살아 있으면 재사용된다. rustup 줄이 사라졌으므로 그
아래(Zig 설치)는 반드시 다시 실행된다 — Zig tarball을 다시 받는다.

- [ ] **Step 4: Rust가 정말 없는지 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer bash -c \
  'command -v cargo rustc rustup; echo "exit=$?"; zig version; ls /usr/local/cargo /usr/local/rustup 2>&1'
docker images tars-devcontainer
```

Expected:
- `command -v`가 아무 경로도 출력하지 않고 `exit=1`
- `zig version` → `0.16.0`
- `ls` → `No such file or directory` 두 번
- `docker images` → `latest`의 SIZE가 Step 1보다 작다. **두 숫자를 기록할 것**
  (rustup minimal + stable 툴체인이라 수백 MB 줄어들 것으로 본다).

`exit=0`이 나오면 rustup이 어딘가 남은 것이다 — 그 경로를 알릴 것.

- [ ] **Step 5: Commit**

Claude가 수행한다. 이 시점에는 게이트를 아직 안 돌렸지만, `Dockerfile`
변경 자체는 확인이 끝났으므로(Step 4) 따로 커밋해 둔다 — Task 3에서 게이트가
깨지면 이 커밋만 되돌리면 된다.

---

## Task 3: 종료 게이트 3/3 (Rust 없는 이미지에서)

design doc이 정한 ZM-M2 완료 조건 그 자체다.

**Files:** 없음(확인만)

- [ ] **Step 1: 루트 게이트 전체 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/zm-m2-gate.log
```

Expected 마지막 줄:
```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

BF 3회 + TF 3회이고 매 회차 `clean()` 후 커널부터 다시 빌드하므로 오래
걸린다. ZM-M1 기준 BF 부팅은 회차당 33~34초였다.

- [ ] **Step 2: 6회 전부에서 init이 제 일을 했는지**

게이트가 PASS해도 이 숫자가 안 맞으면 실패로 본다
([[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다").

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/zm-m2-gate.log
grep -c 'init mounted all four filesystems' /tmp/zm-m2-gate.log
grep -c 'tars-init: failed' /tmp/zm-m2-gate.log
```

Expected: `6`, `6`, `0`.

앞의 두 숫자가 6인 이유는 BF가 끝에서 serial 로그를 `cat`하고
(`boot/check.sh`) TF는 `--- init log ---` 아래 `tars-init:` 줄을 출력하기
때문이다(`terminal/check.sh:195-196`) — 두 체인 3회씩 합쳐 6이다.

- [ ] **Step 3: initrd 크기 확인**

Run:
```bash
ls -l kernel/initrd.cpio
```

Expected: 14MB 근처(ZM-M1 종료 시점 값). **이번 milestone은 initrd에 들어가는
것을 하나도 바꾸지 않았으므로 값이 달라지면 안 된다.** 달라졌다면 이미지
재빌드로 fish나 glibc 버전이 올라간 것이다 — 그 자체가 실패는 아니지만
Task 4에 기록해야 하므로 알릴 것.

---

## Task 4: 문서와 기억 갱신

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-tars-zig-migration-design.md`
- Modify: `docs/decisions/project_zig_rewrite_intent.md`
- Modify: `docs/decisions/project_gate_chain_composition.md`
- Modify: `MEMORY.md`
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 Task 3까지의 결과(특히 Task 2 Step 1·4의 이미지 크기 두 숫자,
Task 3 Step 2의 세 숫자)만 전달하면 된다.

갱신 내용:

- **design doc** — Status를 `ZM-M2 complete`로. ZM-M2 절에 `kernel/check.sh`
  삭제를 추가(원래 범위에 없었다는 사실과 판단 근거를 함께). 완료 조건 1번의
  검색 명령을 실제로 쓴 형태(`--glob`으로 문서·vendor 제외)로 정정.
- **`project_zig_rewrite_intent`** — "`init`/`kms`의 Rust 코드는 결국 Zig로
  재작성 예정"이 이제 사실과 다르다. `init`은 옮겼고 `kms`는 옮기지 않고
  지웠다는 결말을 적는다. `MEMORY.md`의 해당 한 줄 요약도 같이 고친다.
- **`project_gate_chain_composition`** — "낡은 게이트는 은퇴시킨다" 절에
  `kernel/check.sh`를 추가한다. 은퇴한 게이트를 **파일까지 지우는** 것이
  이번에 처음이므로, 주석으로 남겨두는 방식(display가 그랬다)과 무엇이 달랐는지
  한 줄 적는다.
- **`HANDOFF.md`** — ZM-M3 기준으로 다시 쓴다.
- **이 plan 말미** — "실제 실행에서 plan과 달라진 점". 다음 세션이 가장 먼저
  읽는 절이므로 빠짐없이 적는다.

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **`Dockerfile:1`의 `--platform=linux/amd64` 제거와 Zig 설치 URL 변경** —
  ZM-M3. 같은 파일을 건드리지만 실패 모드가 완전히 다르다(빌드 환경 전체가
  바뀐다). 섞으면 게이트가 깨졌을 때 원인 후보가 넓어진다.
- **`devcontainer`에 `file` 패키지 추가** — ZM-M3에서 arm64 전환과 함께
  한다(ZM-M1에서 `file`이 없어 확인 하나를 건너뛰었다). 지금 넣으면 이미지를
  두 번 재빌드해야 한다.
- **`init`의 최적화 모드 변경(`ReleaseSafe`)** — 여전히 보류. 크기가 실제
  문제가 될 때 꺼낼 카드다.
- **`origin/main`으로 push** — ZM-M1 커밋들도 아직 안 올렸다. 사용자가
  지시할 때 한다.
- **PID 1 기능 보강(좀비 수거, 셸 종료 처리)** — design doc의 비목표.
