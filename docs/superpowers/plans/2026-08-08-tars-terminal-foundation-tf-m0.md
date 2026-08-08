# TARS Terminal Foundation — TF-M0 Verification Pipeline Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** TF-M0를 완료한다 — devcontainer에 Zig 툴체인을 추가하고,
`libghostty-vt`(ANSI/VT 파싱 코어)와 `8x4x4-fonts`(한글 조합형 지원
비트맵 폰트), `stb_truetype`(TTF 래스터라이저)를 각각 가져와 빌드/링크가
실제로 동작함을 작은 sanity check 프로그램으로 확인한다. TF-M1부터는
이 세 가지를 조합해 실제 KMS 프레임버퍼에 텍스트를 렌더링한다.

**Architecture:** 새 최상위 디렉터리 `terminal/`을 만든다. 외부
소스(`libghostty-vt`, `8x4x4-fonts`, `stb_truetype.h`)는 `boot/build.sh`가
Limine을, `kernel/build.sh`가 커널 소스를 받아오는 것과 같은 패턴으로
—버전을 고정한 채 스크립트로 받아 `terminal/ghostty-src/`,
`terminal/vendor/`에 두고 git에는 커밋하지 않는다(스크립트만 커밋).
`libghostty-vt`는 `zig build -Demit-lib-vt`로 static 라이브러리+헤더를
뽑아내고, `8x4x4-fonts`는 GitHub 릴리스 zip에서 `Hanme_8x4x4.ttf` 하나만
꺼내며, `stb_truetype.h`는 단일 헤더 파일을 그대로 받는다. 각각에 대해
`zig cc`로 컴파일한 작은 C sanity check 프로그램을 `terminal/sanity/`에
두고 실행 결과로 "링크와 기본 동작이 실제로 되는가"를 확인한다.

**Tech Stack:** Zig 0.16.0(C 컴파일러로도 사용), `libghostty-vt`(Zig/C,
ghostty-org/ghostty 저장소 커밋 `2602886144c7e95099c9e2ba07f181c69e7276f3`
고정), `8x4x4-fonts`(iolo, 릴리스 태그 `v0.0.7` 고정, MIT/OFL-1.1),
`stb_truetype.h`(nothings/stb, 커밋
`2c980bb59875b0d32144a71867fbdebb2f77cd20` 고정), 기존 devcontainer(Docker,
`tars-devcontainer` 이미지)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 빌드 명령은 devcontainer 컨테이너 안에서 돈다(Boot/Display
Foundation과 동일). `tars-devcontainer` 이미지가 이미 빌드돼 있어야 한다.

**Design doc과의 관계:**
[2026-08-08-tars-terminal-foundation-design.md](../specs/2026-08-08-tars-terminal-foundation-design.md)
TF-M0 절의 네 항목(Zig 툴체인, `libghostty-vt` 빌드/링크 sanity check,
`8x4x4-fonts` 폰트 파일 확보, `stb_truetype` FFI 연결 확인)을 각각
Task로 나눈다. design doc의 5번 결정(PTY: `libc openpty()/forkpty()`)과
6번 결정(입력: raw evdev)은 TF-M2~M3에서 다루므로 이 plan에는 없다.

**버전 고정 이유:** `libghostty-vt`는 API가 아직 유동적이라고 design
doc이 명시하므로, 재현 가능한 빌드를 위해 이 plan을 쓴 시점(2026-08-08)의
`main` 브랜치 HEAD 커밋을 그대로 고정한다. `8x4x4-fonts`는 안정된 릴리스
태그를 쓴다. `stb_truetype.h`는 태그가 거의 없는 저장소라 커밋 SHA로
고정한다.

---

### Task 1: devcontainer에 Zig 0.16.0 + 압축 도구 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [ ] **Step 1: Dockerfile에 `xz-utils`/`unzip` 패키지와 Zig 설치 추가**

`devcontainer/Dockerfile` 전체를 다음으로 교체한다(`imagemagick` 다음 줄에
`xz-utils`, `unzip` 추가, Rust 설치 블록 뒤에 Zig 설치 블록 추가):

```dockerfile
FROM --platform=linux/amd64 debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib \
        binutils \
        qemu-system-x86 \
        git \
        ca-certificates \
        flex \
        bison \
        bc \
        libssl-dev \
        libelf-dev \
        curl \
        cpio \
        rsync \
        fish \
        xorriso \
        imagemagick \
        xz-utils \
        unzip \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
        -y --default-toolchain stable --profile minimal \
        --target x86_64-unknown-linux-gnu

ENV ZIG_VERSION=0.16.0 \
    PATH=/usr/local/zig:$PATH

RUN curl -sSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /usr/local/zig \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /workspace
```

`xz-utils`는 Zig 배포 tarball(`.tar.xz`)을 풀기 위해, `unzip`은 Task 4에서
받을 `8x4x4-fonts` 릴리스가 `.zip`이라 필요하다 — Docker 이미지 재빌드를
한 번만 하도록 두 패키지를 이번에 함께 추가한다. `--strip-components=1`은
tarball 안의 최상위 `zig-x86_64-linux-0.16.0/` 디렉터리 한 겹을 벗겨서
`/usr/local/zig` 바로 아래에 `zig` 실행 파일이 오도록 한다.

- [ ] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [ ] **Step 3: Zig 버전 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer zig version
```

Expected: `0.16.0` 한 줄 출력.

- [ ] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add Zig 0.16.0 toolchain and xz-utils/unzip to devcontainer"
```

---

### Task 2: `libghostty-vt` 벤더링 스크립트 + 빌드

**Files:**
- Create: `terminal/vendor_libghostty_vt.sh`
- Modify: `.gitignore`

- [ ] **Step 1: `.gitignore`에 `terminal/` 산출물 경로 추가**

`.gitignore` 끝에 다음을 추가한다:

```gitignore

terminal/ghostty-src/
terminal/vendor/
terminal/sanity/libghostty_vt_check
terminal/sanity/stb_truetype_check
```

`libghostty_vt_check`/`stb_truetype_check`는 Task 3/5에서 만들 컴파일
결과물 경로를 미리 등록해 둔 것이다(`boot/limine-binary/`가 실제로
받아지기 전에도 `.gitignore`에 이미 있던 것과 같은 패턴).

- [ ] **Step 2: `terminal/vendor_libghostty_vt.sh` 작성**

`terminal/vendor_libghostty_vt.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GHOSTTY_SHA="2602886144c7e95099c9e2ba07f181c69e7276f3"
SRC_DIR="ghostty-src"
URL="https://github.com/ghostty-org/ghostty/archive/${GHOSTTY_SHA}.tar.gz"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o ghostty-src.tar.gz "$URL"
  mkdir -p "$SRC_DIR"
  tar -xzf ghostty-src.tar.gz -C "$SRC_DIR" --strip-components=1
  rm ghostty-src.tar.gz
fi

mkdir -p vendor
(cd "$SRC_DIR" && zig build -Demit-lib-vt -Dtarget=x86_64-linux-gnu \
    --prefix ../vendor/libghostty-vt)
```

`kernel/build.sh`, `boot/build.sh`와 같은 패턴이다 — 소스 디렉터리가 이미
있으면 재다운로드하지 않고, 매번 빌드만 다시 돈다. `-Demit-lib-vt`는
Ghostty 전체(GUI, 폰트 렌더링 포함)가 아니라 ANSI/VT 파싱 코어만 static
라이브러리로 뽑아내는 빌드 플래그다(design doc 2번 항목 참고).

- [ ] **Step 3: 실행 권한 부여**

```bash
chmod +x terminal/vendor_libghostty_vt.sh
```

- [ ] **Step 4: 빌드 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/vendor_libghostty_vt.sh
```

Expected: 종료 코드 0. `uucode`(유니코드 폭 테이블) 등 lazy가 아닌
의존성을 zig가 자동으로 내려받는 로그가 보일 수 있다 — 네트워크가
필요한 정상 동작이다. 처음 실행 시 소스 다운로드+빌드로 수 분 걸릴 수
있다. `docker run --rm`이라 컨테이너가 매번 새로 시작되므로, zig의
전역 패키지 캐시도 매번 비어 있다 — 이 스크립트를 다시 실행하면
`uucode` 등을 매번 다시 내려받는다(정상, `ghostty-src/`가 이미 있으면
소스 자체는 재다운로드하지 않는다).

**만약 `--prefix ../vendor/libghostty-vt` 관련 에러가 나면:** 절대 경로로
바꿔서 다시 시도한다 — `--prefix "$(pwd)/../vendor/libghostty-vt"`처럼
`ghostty-src` 안에서 절대 경로를 만들어 넘긴다.

- [ ] **Step 5: 산출물 확인**

Run:
```bash
ls terminal/vendor/libghostty-vt/include/ghostty/ terminal/vendor/libghostty-vt/lib/
```

Expected: `include/ghostty/` 아래 `vt.h`가 있고, `lib/` 아래
`libghostty-vt.a` 또는 `libghostty-vt.so`(둘 중 하나, zig가 기본으로
만드는 형식)가 있다.

- [ ] **Step 6: 커밋**

```bash
git add .gitignore terminal/vendor_libghostty_vt.sh
git commit -m "Add libghostty-vt vendoring script"
```

---

### Task 3: `libghostty-vt` 링크 sanity check

**Files:**
- Create: `terminal/sanity/libghostty_vt_main.c`

- [ ] **Step 1: sanity check 프로그램 작성**

`terminal/sanity/libghostty_vt_main.c`(Ghostty 공식 예제
`example/c-vt/src/main.c`를 기반으로, 실패 시 0이 아닌 값을 반환하도록
`return 1;`을 추가한 버전 — OSC "change window title" 시퀀스
`\x1b]0;hello\x07`를 한 글자씩 파싱기에 먹여서 제목 문자열 "hello"를
정확히 추출하는지 확인한다):

```c
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <ghostty/vt.h>

int main() {
  GhosttyOscParser parser;
  if (ghostty_osc_new(NULL, &parser) != GHOSTTY_SUCCESS) {
    fprintf(stderr, "ghostty_osc_new failed\n");
    return 1;
  }

  // "change window title" 명령(OSC 0): ESC ] 0 ; hello BEL
  ghostty_osc_next(parser, '0');
  ghostty_osc_next(parser, ';');
  const char *title = "hello";
  for (size_t i = 0; i < strlen(title); i++) {
    ghostty_osc_next(parser, title[i]);
  }

  GhosttyOscCommand command = ghostty_osc_end(parser, 0);
  GhosttyOscCommandType type = ghostty_osc_command_type(command);
  printf("Command type: %d\n", type);

  if (ghostty_osc_command_data(command, GHOSTTY_OSC_DATA_CHANGE_WINDOW_TITLE_STR, &title)) {
    printf("Extracted title: %s\n", title);
  } else {
    fprintf(stderr, "Failed to extract title\n");
    ghostty_osc_free(parser);
    return 1;
  }

  ghostty_osc_free(parser);
  return 0;
}
```

- [ ] **Step 2: 컴파일**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer zig cc \
  -I terminal/vendor/libghostty-vt/include \
  -L terminal/vendor/libghostty-vt/lib -lghostty-vt \
  -o terminal/sanity/libghostty_vt_check \
  terminal/sanity/libghostty_vt_main.c
```

Expected: 종료 코드 0, 에러 없이 `terminal/sanity/libghostty_vt_check`
바이너리 생성. 링크 에러(`undefined reference` 등)가 나면 Task 2 Step 5의
`lib/` 안 파일명이 `libghostty-vt.a`/`.so`가 아닌 다른 이름인지 다시
확인한다.

- [ ] **Step 3: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer terminal/sanity/libghostty_vt_check
```

Expected:
```
Command type: <정수>
Extracted title: hello
```
종료 코드 0. 두 번째 줄이 정확히 `Extracted title: hello`인 것이 핵심 —
`libghostty-vt`가 OSC 이스케이프 시퀀스를 실제로 파싱해 문자열을
복원했다는 뜻이다.

- [ ] **Step 4: 커밋**

```bash
git add terminal/sanity/libghostty_vt_main.c
git commit -m "Add libghostty-vt link sanity check"
```

---

### Task 4: `8x4x4-fonts` 폰트 파일 확보

**Files:**
- Create: `terminal/vendor_fonts.sh`

- [ ] **Step 1: `terminal/vendor_fonts.sh` 작성**

`terminal/vendor_fonts.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

FONTS_TAG="v0.0.7"
URL="https://github.com/iolo/8x4x4-fonts/releases/download/${FONTS_TAG}/8x4x4-fonts-all.zip"
FONT_FILE="vendor/fonts/Hanme_8x4x4.ttf"

if [ ! -f "$FONT_FILE" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor/fonts
  curl -sSL -o /tmp/8x4x4-fonts-all.zip "$URL"
  unzip -p /tmp/8x4x4-fonts-all.zip Hanme_8x4x4.ttf > "$FONT_FILE"
  rm /tmp/8x4x4-fonts-all.zip
fi
```

릴리스 zip(`8x4x4-fonts-all.zip`, v0.0.7 기준 약 20MB)에는 12개 폰트
계열 × 여러 포맷(ttf/otf/woff/woff2/bdf)이 전부 들어 있다 —
`unzip -p ... Hanme_8x4x4.ttf`로 필요한 파일 하나(`Hanme_8x4x4.ttf`,
약 450KB)만 스트리밍해서 꺼내고 zip 전체는 버린다. 라이선스는
[iolo/8x4x4-fonts](https://github.com/iolo/8x4x4-fonts) 저장소의
MIT/OFL-1.1 듀얼 라이선스를 따른다(design doc 4번 항목 참고).

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x terminal/vendor_fonts.sh
```

- [ ] **Step 3: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/vendor_fonts.sh
```

Expected: 종료 코드 0.

- [ ] **Step 4: 파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "file terminal/vendor/fonts/Hanme_8x4x4.ttf"
```

Expected: 출력에 `TrueType Font data`가 포함된다.

- [ ] **Step 5: 커밋**

```bash
git add terminal/vendor_fonts.sh
git commit -m "Add 8x4x4-fonts vendoring script"
```

---

### Task 5: `stb_truetype` FFI 연결 확인

**Files:**
- Create: `terminal/vendor_stb_truetype.sh`
- Create: `terminal/sanity/stb_truetype_main.c`

- [ ] **Step 1: `terminal/vendor_stb_truetype.sh` 작성**

`terminal/vendor_stb_truetype.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

STB_SHA="2c980bb59875b0d32144a71867fbdebb2f77cd20"
URL="https://raw.githubusercontent.com/nothings/stb/${STB_SHA}/stb_truetype.h"
DEST="vendor/stb_truetype.h"

if [ ! -f "$DEST" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor
  curl -sSL -o "$DEST" "$URL"
fi
```

- [ ] **Step 2: sanity check 프로그램 작성**

`terminal/sanity/stb_truetype_main.c`(Task 4에서 받은 `Hanme_8x4x4.ttf`를
읽어 알파벳 'A' 글리프 하나를 실제로 래스터라이징하고, 픽셀이 실제로
채워졌는지 확인한다):

```c
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include <stdio.h>
#include <stdlib.h>

int main(void) {
  FILE *f = fopen("vendor/fonts/Hanme_8x4x4.ttf", "rb");
  if (!f) {
    perror("fopen");
    return 1;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);

  unsigned char *data = malloc((size_t)size);
  if (fread(data, 1, (size_t)size, f) != (size_t)size) {
    fprintf(stderr, "short read\n");
    fclose(f);
    return 1;
  }
  fclose(f);

  stbtt_fontinfo font;
  if (!stbtt_InitFont(&font, data, 0)) {
    fprintf(stderr, "stbtt_InitFont failed\n");
    return 1;
  }

  float scale = stbtt_ScaleForPixelHeight(&font, 16.0f);
  int w, h, xoff, yoff;
  unsigned char *bitmap =
      stbtt_GetCodepointBitmap(&font, scale, scale, 'A', &w, &h, &xoff, &yoff);
  if (!bitmap) {
    fprintf(stderr, "stbtt_GetCodepointBitmap failed\n");
    return 1;
  }

  int nonzero = 0;
  for (int i = 0; i < w * h; i++) {
    if (bitmap[i] > 0) {
      nonzero++;
    }
  }

  printf("glyph 'A': %dx%d pixels, %d non-zero\n", w, h, nonzero);

  stbtt_FreeBitmap(bitmap, NULL);
  free(data);

  return nonzero > 0 ? 0 : 1;
}
```

`STB_TRUETYPE_IMPLEMENTATION`을 이 파일에서 정의해 헤더 하나만으로
구현체까지 컴파일되게 한다(design doc 4번 항목의 "단일 헤더 C
라이브러리" 방식). `nonzero > 0`을 종료 코드로 삼아 "글리프가 실제로
그려졌는가"를 PASS/FAIL로 판단한다.

- [ ] **Step 3: 실행 권한 부여**

```bash
chmod +x terminal/vendor_stb_truetype.sh
```

- [ ] **Step 4: `stb_truetype.h` 받기**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/vendor_stb_truetype.sh
```

Expected: 종료 코드 0. `terminal/vendor/stb_truetype.h` 생성.

- [ ] **Step 5: 컴파일**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer zig cc \
  -I terminal/vendor \
  -o terminal/sanity/stb_truetype_check \
  terminal/sanity/stb_truetype_main.c -lm
```

Expected: 종료 코드 0, 경고 없이(또는 무해한 경고만) 바이너리 생성.
`-lm`은 `stb_truetype.h`가 내부적으로 쓰는 `floor`/`ceil`/`sqrt` 등을
위한 수학 라이브러리 링크다.

- [ ] **Step 6: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd terminal && ./sanity/stb_truetype_check"
```

Expected: `glyph 'A': WxH pixels, N non-zero`(W, H, N은 모두 0보다 큰
정수) 출력, 종료 코드 0.

- [ ] **Step 7: 커밋**

```bash
git add terminal/vendor_stb_truetype.sh terminal/sanity/stb_truetype_main.c
git commit -m "Add stb_truetype FFI sanity check"
```

---

## TF-M0 완료 확인

Task 3 Step 3과 Task 5 Step 6이 모두 기대한 출력과 종료 코드 0으로
끝나면 design doc 기준 TF-M0의 네 항목(Zig 툴체인, `libghostty-vt`
빌드/링크, `8x4x4-fonts` 확보, `stb_truetype` FFI 연결)이 모두
확인된다. 이 시점에서 TF-M1(프레임버퍼 텍스트 렌더링) plan을 별도로
작성한다.
