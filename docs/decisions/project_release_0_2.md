---
name: project_release_0_2
description: "0.2.0은 개발 도구 층(TP) 전체를 끝낸 뒤 내는 첫 '쓸 만한' 판이다(사용자 2026-11-06). 0.1.5는 내지 않는다. 그 사이의 실기 확인은 dev-<날짜> 프리릴리스로 한다"
metadata:
  type: project
---

# 0.2.0 = TP 전체

사용자(2026-11-06): "이 작업을 마무리하면 0.2 버전을 정식으로 릴리즈 하겠습니다." 이어서 확인: "TP 전체를 뜻합니다. 즉 이 모두 선행되어야
하겠구나. 0.2는 풍부한 패키지를 포함한 첫 사용 가능한 버전이 될것이다. 신중하게 검토하고 릴리즈 할게."

Why: 0.2는 "설치하면 망 없이 바로 개발할 수 있다"는 TP design의 목표를 처음으로 다 채운 판이어야 한다. 묶음 몇 개만 실린 판을 0.2라고
부르면 그 약속이 흐려진다.

How to apply:

- 0.1.4 다음 번호는 0.2.0이다. TP design의 Milestone 절이 남긴 묶음(JVM 언어 · BEAM · 편집기 · 터미널 유틸리티 · 문서 · 서버 실행 파일 ·
  서버 서비스 · AI)과 base 보강(TP-M4)이 모두 끝나고 design의 "닫을 때" 목록까지 한 뒤에 낸다. 절차는 [[project_release]].
- 그 사이 실기 확인은 프리릴리스로 낸다 — 태그 `dev-<YYYYMMDD>`(annotated), `gh release create … --prerelease --latest=false`,
  파일 `tars-dev-<YYYYMMDD>-x86_64.iso` + `SHA256SUMS`. `VERSION`은 올리지 않으므로 시스템은 `<VERSION>+<sha>`라고 말한다 — 깨끗한
  트리에서 짓는다. 첫 판: `dev-20261106` → `181271e`(묶음 넷, 983,654,400 B,
  sha256 `43abf8f861c75a59a8cdca6cfd44482663fe95efe7b791c25cfeec0442d98a9b`). 둘째 판: `dev-20261108` → `09ec9ef`(묶음 열 · 서버 서비스,
  2,036,891,648 B — 2GiB 한도 안, sha256 `693d08e574b4627707dc2d6931dbf511aca8e34a1cf9552adfa1040edaa8c065`). 사용자 "upload pre-release iso with
  draft" — `--draft`로 올렸다. 공개(draft 풀기)는 사용자가 한다.
  셋째 판: `dev-20261109` → `a146857`(TP-M12 마무리 — initrd의 clear · tput · reset, AI 도구 확인, 거두기 전 slim upgrade. 2,036,903,936 B,
  sha256 `851da397e3c3e8a2871432ae2dd9de3e287e5421499060ef0f8f40cacf3a367c`, smoke `TARS 0.1.4+a146857`). 사용자 "푸시하고 pre release 해줘" —
  draft 아닌 공개 프리릴리스(`--prerelease --latest=false`), 내려받아 `shasum -c` OK.
- 실기 확인(2026-11-09, `dev-20261109`, 사용자의 MacBook Air 2011 — macOS 옆에 `--beside`로 깔린 0.1.4+5d9e766 위에 갱신). 사용자: "많은
  것을 검증했습니다. 그리고 대부분 성공적으로 동작을 확인했습니다. 미완으로 남아있는 문서 내용을 '완료' 상태로 변경해도 될 수준" — 그래서
  TP를 닫았다. 사진으로 함께 본 것:
  - 첫 USB는 용량이 모자라 ISO가 덜 써졌다(사용자 확인). Startup Manager에 "Windows"(BIOS 길) 하나만 보였고 Limine이 `PANIC: iso9660:
    failed to read file data`(`stage3_init` → `iso9660_read`)로 멈췄다. TARS의 결함이 아니다. 다시 쓴 8GB USB(Silicon-Power8G)는 "Windows"와
    "TARS Linux"(UEFI 길, `.disk_label`) 둘이 보였다. 안내는 `running-tars.md` "안 되는 것"의 한 줄.
  - `tars-install /dev/sda`(인자 없이 먼저 쳐 목록을 봤다): `already has TARS` → `boot/` ← 0.1.4+a146857, 옛 판은 `boot/old/`, p4는 안 열고,
    p5의 묶음 8개를 지우고 10개 1,806MiB를 50,110ms에(USB에서 초당 약 36MiB). `updated. remove the boot medium and reboot.`
  - 재부팅 뒤 화면 셸(fish, 사용자 tars): `javac` 25.0.5 · `zig` 0.17.1 · `bun` 1.4.4(baseline — AVX2 없는 CPU) · `cyber` 0.4.3 · `nvim` 0.12.6,
    모두 manifest의 판. `sudo tars-service enable redis` · `mysql` → running, `ps`에서 uid tars · PPID 1, 경로는 묶음의 `/usr/bin` · `/usr/sbin`.
- 프리릴리스도 BB-M0부터 barebone ISO를 함께 올린다 — `tars-dev-<YYYYMMDD>-barebone-x86_64.iso`, 절차는 [[project_release]] 3.
- 프리릴리스 · 0.2 모두 `make iso ISO_LAYERS="<묶음들>"`이다(기본값은 묶음을 안 싣는다). 굽기 전에 `devlayer/build/*.stamp`를 지운다 —
  묶음 안의 출처 기록(`usr/share/tars/layers/<묶음>`의 `git describe --dirty`)은 stamp에 안 들어가서, dirty일 때 구운 묶음이 그대로 남는다.
- 0.2 전에 풀 것: GitHub release는 파일 하나가 2GiB까지다. 묶음 전체의 어림(TP design 확인 10, squashfs 2.5~4GB)이면 ISO 하나로는 못
  올린다(사용자와 아직 안 정했다).
