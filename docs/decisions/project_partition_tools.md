---
name: project_partition_tools
description: "사람이 치는 파티션 도구(PT-M0, 2026-11-20) — Debian fdisk 패키지의 fdisk · cfdisk를 initrd 층 7(sfdisk 옆)에, 기준 B, Dockerfile 변경 0, 새 라이브러리는 libmount 하나, tools 체인 검사 29가 /tmp 파일 이미지로 셋을 친다(cfdisk는 화면을 보고 q). 클라우드 세션은 amd64라 Dockerfile의 호스트 몫 둘만 바꾼 판으로 게이트를 돌렸다"
metadata:
  type: project
---

design은 `docs/specs/2026-11-20-tars-partition-tools-design.md`, plan은 `docs/plans/2026-11-20-tars-partition-tools-pt-m0.md`.
계기는 사용자 질문 둘 — "디스크 파티션 프로그램이 탑재되어 있나요?" · "쉽게 쓸 수 있는 파티션 프로그램은?" — 그리고 추천안(cfdisk · fdisk)의 수락.

## 무엇이 섰나

- `kernel/guest_tools.sh` 층 7에 `fdisk`(178,616 B) · `cfdisk`(113,400 B), 오른쪽 `/usr/bin`. 셋(sfdisk 포함)이 한 패키지 · 한 엔진(libfdisk).
- initrd 항목이 정확히 셋 늘었다 — `fdisk` · `cfdisk` · `libmount.so.1`(502,512 B). 압축 initrd 128,930,298 → 129,271,380 B(+341,082).
  libmount 뒤의 libblkid · libselinux · libpcre2-8과 cfdisk의 libncursesw(alsamixer가 들였다)는 이미 있었다.
- `tools/check.sh` 검사 29: `head -c 8M /dev/zero`로 만든 파일에 `sfdisk -X gpt` → `fdisk -l`이 `Disklabel type: gpt` · `img1 … 2048` →
  `cfdisk`가 `Label: gpt`를 그리고 `q`로 끝나 `pt-back=0`. 화면을 가져가는 대화형을 끝까지 친 첫 검사다(htop · btop · alsamixer는 목록까지).
- `docs/help/config.md` "디스크와 파티션" — 세 줄과, TARS 파티션 이름(`TARS-BOOT` · `TARS-CONFIG` · `TARS-HOME`)을 바꾸면
  `isInstalled`(`g.find(.boot)` · `.config`)가 설치된 디스크로 안 보아 갱신 대신 새 설치로 간다는 경고.

## 배운 것

1. fdisk 셋은 일반 파일을 디스크처럼 다룬다 — 블록 장치 없는 체인에서도 파티션 도구를 끝까지 볼 수 있다. initrd에 `truncate` · `dd`가 없어
   `head -c 8M /dev/zero`로 만든다.
2. 대화형 TUI도 "판정 글자를 본 뒤 끝내는 키 한 번 → 셸이 돌아왔다는 표식"이면 게이트가 친다. 화면을 보기 전에 키를 보내지 않는 것이 요점이다.
3. mutation(층 7에서 cfdisk 줄 하나를 뺀 판): 검사 1은 목록을 되읽어 초록, 검사 29가 `fish: Unknown command: cfdisk`로 빨갛다.
4. 클라우드 세션(amd64, KVM 없음)에서 게이트를 돌리는 길 — 저장소의 이미지는 arm64 전용이다. scratchpad의 Dockerfile 사본에서
   `gcc-multilib-x86-64-linux-gnu` → `gcc-multilib`, zig tarball `aarch64` → `x86_64`(sha256은 `checks.yml`의 값), 세션 프록시 CA를
   신뢰시키는 층 하나, `docker build --network host`에 `HTTPS_PROXY`. Docker Hub가 429면 `mirror.gcr.io/library/debian:trixie-slim`을 받아
   `debian:trixie-slim`으로 태그한다. 게이트 안의 내려받기 둘은 프록시를 못 지난다 — ghostty archive(세션이 GitHub archive를 막는다)는
   같은 커밋을 `git fetch` 뒤 `git archive | gzip -cn`으로 만들면 고정된 sha256과 바이트까지 같다. zig 의존(`deps.files.ghostty.org`)은
   zig의 HTTP가 프록시에서 `ConnectionResetByPeer`라 호스트 curl로 받아 `zig fetch <파일>` — 그런데 zig 0.17.1은 로컬 파일을 캐시에 넣을 때
   맨 위 디렉터리를 안 벗겨(해시는 맞게 찍는다) 빌드가 `N-V-…` 해시로 거절한다. 캐시의 `p/<hash>.tar.gz`를 한 단 벗겨 다시 묶으면
   zig가 다시 계산한 해시가 맞아 통과한다. 그 뒤 체인은 `--network none`으로도 선다.
