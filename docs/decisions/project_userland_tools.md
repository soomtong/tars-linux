---
name: project_userland_tools
description: "게스트에서 쓸 도구 한 벌(GNU + 모던 + git)을 세우고 그 이름이 PATH로 손에 닿게 하는 층(UT) — UT-M0(2026-09-10)이 PATH와 뼈대 넷을 세웠고, 조달은 Debian .deb 하나로 통일하며 libgit2 사슬 11.4MB를 감수한다"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-10에 기계를 **실제로 써 보고** 지목했다 — *"터미널 환경에서
기본적인 unix/linux utilities가 부족하다. 예를 들면 `ls` 같은 것들이 없다."*
조건이 둘 붙었다: *"gnu 기본 유틸리티도 좋지만 **modern alternative가 기본
탑재**되면 좋겠다"* · *"tars-linux는 거의 **개발용**으로 사용되기 때문에
**git은 필수** 도구가 될 것"*.

design은 `docs/superpowers/specs/2026-09-10-tars-userland-tools-design.md`,
milestone 넷(UT-M0~M3)이고 **UT-M0이 2026-09-10에 끝났다.**

## 다시 조사하지 말 것 — 착수 전 실측

**1. 진짜 벽은 `ls`가 없는 것이 아니라 `PATH`가 없는 것이었다.** 자세히는
[[project_guest_environment]]의 결과 1. UT-M0이 그것을 닫았다.

**2. GNU는 이미 저장소 안에 있다.** `devcontainer/Dockerfile:82`가
`coreutils:amd64`를 통째로 받아 sysroot에 풀어 뒀고 `make_initrd.sh`가 넷만
복사하고 있었다. 바이너리 하나가 42~154KB이고, coreutils 35개 합계 2,490KB다.
**`grep`·`find`·`sed`·`awk`·`diff`·`less`·`ps`는 coreutils가 아니라 별도
패키지라** sysroot에 없다 — Dockerfile에 더해야 한다(합계 1,621KB, 새
라이브러리는 `libacl1` 74KB와 `libproc2` 237KB 둘뿐).

**3. 모던 도구 열둘 중 열이 새 라이브러리를 하나도 안 부른다.**
`rg`·`fd`·`sd`·`procs`·`duf`·`tree`·`hyperfine`이 공짜다(`duf`는 Go 정적이라
`DT_NEEDED`가 비어 있다). `htop`·`ncdu`가 `libncursesw6` 419KB를,
`jq`가 `libjq` 434 + `libonig` 677KB를 데려온다.

**4. `eza`와 `bat` 둘만이 비싸다 — `libgit2` 사슬 15개 11.4MB다.**
`libcrypto.so.3` 6,364KB(OpenSSL) + Kerberos 한 벌 여섯 + mbedTLS 셋 +
`libssh2`·`libzstd`·`libz`·`libhttp_parser`. **네트워크가 없는 기계에 TLS·
Kerberos·SSH 스택이다.** 사용자가 이 대가를 알고 **Debian `.deb` 하나로
조달을 통일**하기로 정했다(upstream musl 정적을 쓰면 의존이 0이 되지만 경로가
둘로 갈린다). 그리고 **git이 필수가 되면서 대가의 성격이 바뀌었다** —
`eza --git`과 `bat`의 변경 줄 표시가 실제로 쓸모를 갖는다.

**5. git이 그 사슬보다 싸다.** 바이너리 3,987KB에 `NEEDED`가
`libpcre2-8`(이미 있음)과 `libz` 둘뿐이다. `/usr/lib/git-core`가 25MB로
보이지만 **168개 중 대부분이 `git` 자신에 대한 하드링크**이고 별도 실체는
**네트워크 헬퍼 일곱 약 16MB**다(`git-daemon`·`git-http-backend`·
`git-http-fetch`·`git-http-push`·`git-imap-send`·`git-remote-http`·
`git-sh-i18n--envsubst`). **`# CONFIG_NET is not set`이라 한 줄도 안 돈다 —
안 넣는다.** "쓸 수 있는데 안 넣는다"가 아니라 "못 쓰는 것을 안 넣는다"이고,
네트워킹 서브프로젝트가 서면 일곱이 같이 온다.

**6. 게스트에 네트워크가 아예 없다.** 그래서 이번 git은 **로컬 전용**이다 —
`clone`·`fetch`·`push`·`pull`이 안 되고 `init`·`add`·`commit`·`log`·`diff`·
`branch`·`stash`가 된다. 네트워킹은 별도 서브프로젝트로 미뤘다(사용자가
정했다).

**7. 셸이 무조건 no-config로 뜬다.** `init/src/main.zig`가 조건 없이
`--no-config`/`--norc`/`-f`를 넘긴다. **그래서 `zoxide`와 `fzf`는 훅을 걸
자리가 없어 넣어도 안 돈다** — 셸 설정을 다루는 서브프로젝트가 생기면 그때
함께 온다.

**8. Debian이 이름을 바꿔 놓은 것이 둘이다.** `bat`은 `/usr/bin/batcat`이고,
`fd`의 실체는 **`/usr/lib/cargo/bin/fd`**이며 `/usr/bin/fdfind`는 심볼릭
링크다 — **실체를 복사해야 한다**(링크를 복사하면 initrd 안에서 끊어진다).
initrd 안의 이름은 우리가 `bat`·`fd`로 정한다.

**9. trixie에 없는 것 셋** — `helix`·`dust`·`bottom`. `helix`는 upstream
release로만 받을 수 있어 **조달 경로 하나 규칙을 깨는 유일한 항목**이다.
편집기는 `vim.tiny`로 정했다(`neovim`은 라이브러리 9 + 런타임 24MB로 UT
전체보다 무겁다).

**10. 패키지 매니저는 안 만든다.** 사용자가 `herdr`(https://herdr.dev)를
언급하며 "Homebrew for Linux로 관리된다, 지금은 건너뛴다"고 정했다.
**이 방향이 UT의 크기를 정해 준다 — 지금은 바탕 한 벌만 굽고 긴 꼬리는
나중에 패키지 매니저가 맡는다.** 그리고 Homebrew는 네트워크와 git을 둘 다
요구하므로 네트워킹 뒤다.

## UT-M0이 실행으로 증명한 것

**1. 크기의 벽이 없었다 — 위험 1이 거짓이었다.** TF-M2 시절 **53MB에서
부팅조차 못 한 벽**이 있어서 M0의 첫 Task가 크기 스파이크였다. 실제 `.deb`
스물넷을 풀어 밸러스트로 얹으니 트리 **78,328,591바이트**, gzip
**30,019,165바이트**(design의 "약 30MB" 추정이 정확했다). 그 initrd로 실제
부팅해 재니 **원본 4초, 밸러스트 5초 — 1초 차이다.**

```
gzip     30019165 bytes    2843 ms
xz       19662776 bytes   30941 ms      ← 9MB 작지만 압축에 31초
zstd     (컨테이너에 없다 — Dockerfile에 zstd가 빠져 있다)
```

**그래서 `gzip -6`을 유지한다.** `xz`는 부팅이 더 느려도 되면 쓸 카드로 남아
있고(커널이 `CONFIG_RD_XZ`·`CONFIG_RD_ZSTD`를 이미 켜 뒀다) 압축기를 바꾸는
데 커널 재설정이 필요 없다. **`gzip -9`는 답이 아니다** — GL-M1이 재 봤다.

**밸러스트는 반드시 진짜 바이너리여야 한다.** 난수는 안 줄고 0은 통째로
사라져서 압축률이 실제와 달라진다 — 답이 통째로 틀린다.

**2. cpio 목록에 `./` 접두사가 없다.** `make_initrd.sh`가 만든 아카이브의
항목 이름은 `usr/bin/ls`이지 `./usr/bin/ls`가 아니다. plan이 `./`를 붙여 적어
뒀는데 그대로 썼으면 **초록이 아니라 언제나 빨강**이었을 검사다 —
`input/check.sh:83`이 이미 접두사 없이 맞추고 있는 것이 실제 기준이다.
**initrd 목록을 보는 새 검사를 쓸 때는 그 파일을 먼저 본다.**

**3. `/etc/passwd`를 넣으니 프롬프트가 네 글자 길어졌다 — 그리고 다른 체인이
깨졌다.** fish가 uid 0을 이름으로 풀 수 있게 되면서 `@(none) ~#`이
**`root@(none) ~#`**이 됐고, `copy/check.sh`가 박아 둔 `col 16`
(=`@(none) ~# echo `의 길이)이 **20**이 됐다.

```
FAIL: / should land on target 2's command line (col 16), got col 20
```

**design 위험 4가 예고한 종류가 실제로 일어난 것**이고, 저장소에서 프롬프트
폭에 기대는 자리는 **그 한 줄뿐이었다**(`rg`로 세어 확인했다). 바로 위의
`w`/`b` 검사가 `h`를 마흔 번 눌러 col 0에서 시작하는 것은 CN-M1이 같은
함정을 **의도적으로** 피한 것이다 — 그 주석이 "프롬프트 길이에 기대지 않는
것이 요점이다"라고 적어 뒀다.

**게스트의 사용자 데이터베이스를 건드리는 사람은 `copy/check.sh`의 그 수도
함께 본다.** 증상은 CM 체인의 FAIL 한 줄이고 원인은 `make_initrd.sh`에 있어서
서로 멀다.

**4. `git checkout`으로 소스를 되돌려도 `zig-out`의 산출물이 안 따라온다.**
음성 확인(코드를 옛 모양으로 되돌려 체인이 빨개지는지 보기)을 마치고
`git checkout init/src/main.zig`로 복구했는데 체인이 **계속 빨간 채로** 남았다.

```
zig-out/bin/init  3,360,856 bytes   ← 음성 확인용으로 빌드한 것이 그대로
rm -rf zig-out && zig build
zig-out/bin/init  3,363,824 bytes   ← 제대로 된 것
```

소스 mtime이 산출물보다 **더 새것인데도** 그랬다. **게이트 체인이 부팅하는
것은 `zig-out`의 바이너리이므로, 되돌린 뒤에는 `rm -rf zig-out`을 한 번
한다.** 안 하면 "고쳤는데 게이트가 빨갛다"로 나타나고 원인이 소스에 없어서
찾기 어렵다 — RM-M3의 "초록이 내가 본 것조차 아니었다"의 **거울상**이다.

**5. 실패의 모양이 예측한 그대로였다.** `environ_test.zig`를 먼저 쓰고
돌리니 `unable to load 'environ.zig': FileNotFound` — 부를 것이 없는 실패이지
뜻이 틀린 실패가 아니다(SH-M0 실측 2와 같은 종류). 그리고 음성 확인은 검사
2에서 정확히 죽으며 `tars-init: env unchanged (no room for PATH)`를 그대로
보여 줬다.

## UT-M0이 세운 것

| 무엇 | 어디 |
|---|---|
| `PATH=/usr/bin:/bin`을 붙인 블록을 짓는 순수 함수 | `init/src/environ.zig` |
| 그 함수의 호스트 검사 넷(0.1초) | `init/src/environ_test.zig` |
| 블록을 `main()`의 스택에 잡고 자식 둘에게 넘기기 | `init/src/main.zig` |
| `/bin/sh`(→`../usr/bin/bash`) · `/tmp`(1777) · `/etc/passwd` · `/etc/group` · `/usr/bin/ls` | `kernel/make_initrd.sh` |
| 열한번째 체인 — 게스트에 **절대 경로 없이** `ls`를 친다 | `tools/check.sh` |

**`ls` 하나만 넣은 것이 M0의 모양이다.** 통로가 열렸는지를 도구 50개와 섞지
않는다 — 실패하면 원인이 하나뿐이다.

**How to apply:** 게스트에 도구를 더할 때는 **바이너리 크기가 아니라
`DT_NEEDED`가 데려오는 라이브러리**를 먼저 본다 — `make_initrd.sh`의
`copy_lib_deps`가 재귀로 따라가므로 그것이 진짜 비용이다. 조달은 Debian
`.deb` 하나로 통일하고(`devcontainer/Dockerfile`의 `apt-get download` 목록),
Debian이 이름을 바꿔 둔 것(`batcat`·`fdfind`)은 **실체를 찾아** 복사한다.
**게스트 화면에 나오는 글자를 바꾸는 변경은 열한 체인을 전부 돌려 본다** —
위 3이 그것을 안 했으면 CM 체인이 빨간 채로 커밋됐을 자리다.

관련: [[project_guest_environment]], [[project_gate_chain_composition]],
[[project_kernel_config]], [[project_gate_latency]]
