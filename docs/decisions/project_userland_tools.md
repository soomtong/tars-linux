---
name: project_userland_tools
description: "게스트에서 쓸 도구 한 벌(GNU + 모던 + git)을 세우고 그 이름이 PATH로 손에 닿게 하는 층(UT) — 2026-09-10·11에 milestone 넷이 다 끝났다. PATH와 뼈대 넷(M0) · 목록 한 자리 kernel/guest_tools.sh와 GNU 50(M1) · 모던 13(M2) · git과 vim.tiny와 링크 넷(M3)으로 도구 65가 선다. 조달은 Debian .deb 하나로 통일하며 libgit2 사슬 11.4MB를 감수한다"
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
milestone 넷(UT-M0~M3)이고 **UT-M0이 2026-09-10에, UT-M1이 2026-09-11에
끝났다.**

## 다시 조사하지 말 것 — 착수 전 실측

**1. 진짜 벽은 `ls`가 없는 것이 아니라 `PATH`가 없는 것이었다.** 자세히는
[[project_guest_environment]]의 결과 1. UT-M0이 그것을 닫았다.

**2. GNU는 이미 저장소 안에 있다.** `devcontainer/Dockerfile:111`가
`coreutils:amd64`를 통째로 받아 sysroot에 풀어 뒀고 `make_initrd.sh`가 넷만
복사하고 있었다. 바이너리 하나가 42~154KB이고, coreutils 35개 합계 2,490KB다.
**`grep`·`find`·`sed`·`awk`·`diff`·`less`·`ps`는 coreutils가 아니라 별도
패키지라** sysroot에 없다 — Dockerfile에 더해야 한다(합계 1,621KB, 새
라이브러리는 `libacl1` 74KB와 `libproc2` 237KB 둘뿐 — **이 문장이 틀렸다.
아래 "UT-M1이 실행으로 증명한 것"의 1을 함께 읽을 것**).

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

## UT-M1이 실행으로 증명한 것 (2026-09-11)

**1. 위 실측 2가 불완전했다 — 새 라이브러리는 둘이 아니라 넷이다.**
`libacl1`·`libproc2`만 적었는데, **`.so`의 `DT_NEEDED`를 안 봤다.**
`libproc2.so.0`이 **`libsystemd.so.0`(1,131,784)**을 데려오고, coreutils가
**`libattr.so.1`**을 요구한다.

**`libsystemd`는 lzma·zstd·gcrypt를 안 데려온다** — trixie는 그 셋을
`dlopen`으로 열고 `DT_NEEDED`에는 `libcap`·`libm`·`libc`뿐이다. 사슬은
4.2MB가 아니라 **1.38MB**다. **이 구분을 안 하면 `ps` 하나 때문에 OpenSSL급
비용을 치른다고 잘못 판단하고 도구를 뺀다.**

**틀린 것은 코드가 아니라 문서였다.** `copy_lib_deps`는 재귀로 따라가고 못
찾으면 SONAME을 찍고 죽는다. 위험한 자리는 **사람이 손으로 적는
`apt-get download` 목록**이고, 그래서 이 실수가 통과할 수 있었다.
**게스트에 도구를 더할 때는 바이너리의 `DT_NEEDED`가 아니라 그것이 부르는
`.so`까지 한 겹 더 본다.**

**2. `awk`는 `.deb` 안에 없다.** `mawk` 패키지는 `/usr/bin/mawk`만 담고
`/usr/bin/awk`는 Debian alternatives가 postinst에서 만드는 링크다. 위 실측 8
(`batcat`·`fdfind`)과 **같은 종류이고, 이미 M1에서 필요했다** — 목록 형식이
`src:dest`여야 하는 지금 당장의 이유다.

**3. 목록과 검사가 같은 파일을 보게 하면 그 검사는 tautology가 된다.**
결정 7이 그것을 값으로 적어 뒀는데, 음성 확인 둘이 경계를 보여 줬다 —
`copy_lib_deps`를 빼도, 목록에서 `ps` 줄을 지워도 **정적 검사는 초록이고
타이핑 검사가 잡는다.**

**그래서 정적 검사가 증명하는 것은 "목록이 완전한가"가 아니라
"`make_initrd.sh`가 목록이 말하는 것을 전부 넣었는가"다.** 목록의 완전성은
게이트가 아니라 design이 답할 질문이다. [[project_gate_chain_composition]]이
모으는 종류의 교훈이고 SH-M2의 "초록은 볼 것을 다 봤다가 아니다"와 같다.

**4. 리팩터가 셸 셋의 실패 반경을 넓혔다.** 루프가 fish·bash·zsh도 함께
다루므로 `copy_lib_deps` 한 줄이 빠지면 **기계 전체가 안 뜬다**(첫 음성
확인이 `/usr/bin/fish: error while loading ... libpcre2-32.so.0`으로 검사 3에서
죽었다). **고칠 자리가 하나가 되는 것의 뒷면이 망가뜨릴 자리도 하나가 되는
것**이고, 그것이 게이트 첫 판정에서 즉시 드러나는 것이 이 구조가 안전한
이유다. 특정 도구를 겨냥한 음성 확인은 **그 도구만 건너뛰게** 해야 한다.

**5. 게이트가 타이핑하면 안 되는 도구가 둘 있다 — `less`·`top`.** 화면을
통째로 가져가는 대화형 프로그램이라 `sendkey`로 치면 체인이 매달리고,
증상이 실패가 아니라 **타임아웃**이라 원인에서 멀다. `dmesg`는 매달리지는
않지만 출력이 커널 로그 전체라 게이트가 grep하는 화면 로그를 뒤덮는다.
**셋 다 목록 검사까지가 게이트가 보는 전부다.**

## UT-M1이 세운 것

| 무엇 | 어디 |
|---|---|
| `GUEST_TOOLS` 배열 — **바이너리 목록이 사는 유일한 자리**(50개) | `kernel/guest_tools.sh` |
| `install_tool()` — `cp`·`chmod`·`copy_lib_deps`를 한 루프에서 | `kernel/make_initrd.sh` |
| `.deb` 여덟 + 라이브러리 넷 + `zstd`(재는 도구) | `devcontainer/Dockerfile` |
| 검사 1이 같은 배열을 읽고, 검사 5~7이 `ps ax`·`awk`·`sed`를 친다 | `tools/check.sh` |

**게이트는 열한 체인 3/3으로 21분 35.63초다**(UT-M0의 21분 09.60초에서
+26.03초 — initrd가 2.29MB 커지고 타이핑 셋이 늘었다. 잡음 ±3분 안이다).
**위험 4가 이번에는 아무 체인도 안 건드렸다** — 도구 45개를 더하고도 나머지
열 체인이 한 글자도 안 갈렸다. 뼈대가 아니라 도구를 더하는 변경이었기
때문이고, UT-M0에서 `/etc/passwd` 한 줄이 CM 체인을 깬 것과 대조된다.

**How to apply:** 게스트에 도구를 더할 때는 **바이너리 크기가 아니라
`DT_NEEDED`가 데려오는 라이브러리**를 먼저 본다 — `make_initrd.sh`의
`copy_lib_deps`가 재귀로 따라가므로 그것이 진짜 비용이다. 조달은 Debian
`.deb` 하나로 통일하고(`devcontainer/Dockerfile`의 `apt-get download` 목록),
Debian이 이름을 바꿔 둔 것(`batcat`·`fdfind`)은 **실체를 찾아** 복사한다.
**게스트 화면에 나오는 글자를 바꾸는 변경은 열한 체인을 전부 돌려 본다** —
위 3이 그것을 안 했으면 CM 체인이 빨간 채로 커밋됐을 자리다.

관련: [[project_guest_environment]], [[project_gate_chain_composition]],
[[project_kernel_config]], [[project_gate_latency]]

---

## UT-M2 (2026-09-11) — 목록이 63이 됐고, **계획 밖 둘이 게이트를 통째로 깼다**

`make_initrd.sh`는 **한 글자도 안 고쳤다.** M1의 결정 7이 값을 낸 자리이고,
이 milestone의 성적표가 그것이다. 그런데 **계획에 없던 것 둘이 나왔고 둘 다
도구가 아니라 게이트 자신의 문제였다.**

**1. 사슬이 15가 아니라 16이다 — 그런데 Dockerfile은 안 고쳤다.**
`libkrb5`가 **`libresolv.so.2`**를 데려오고, `libcrypto`는 `libgit2` 직접이
아니라 **`libssh2`를 거친다.** 그래도 Dockerfile에 안 적는다 — `libresolv`는
`libc6`이 담고 있고, 적으면 apt가 "없는 패키지"라고 죽는다. **착수 전에
`.so`의 `DT_NEEDED`까지 재귀로 재서 `MISSING`이 0인 것을 빌드 전에 알았고,
빌드가 한 번에 통과했다** — M1이 세 번 틀렸던 자리를 30초로 막았다.

**2. `btop`은 4.01MB이고 `libstdc++`의 유일한 사용자다.** 사용자가 2026-09-11에
더했다. **btop을 빼는 사람은 `libstdc++6`도 함께 뺀다** — 그 사실이
`guest_tools.sh`와 Dockerfile 양쪽에 적혀 있다.

**3. 게이트가 타이핑하지 않는 넷의 이유가 각각 다르다.** `htop`·`btop`·`ncdu`는
**대화형이라 매달리고**(M1의 `less`·`top`과 같다), **`bat`은 판정 글자를 못
만든다** — 낼 수 있는 글자가 전부 `awk`·`sed` 검사와 겹치고 헤더의 `File: `
문자열은 바이너리에서 확인되지 않았다. **판정을 만들 수 없는 검사는 안
만든다.** 그 넷이 쓰는 라이브러리 둘(`libncursesw`·`libstdc++`)은 검사 1이
**정적으로만** 본다 — 게이트가 그 넷에 대해 볼 수 있는 전부이고, 알고 두는
것이 낫다.

**4. 계획 밖 1 — QEMU의 기본 메모리 128MiB에서 기계가 안 켜진다.**
첫 체인 실행이 도구가 아니라 **부팅**에서 죽었다
(`Kernel panic - not syncing: System is deadlocked on memory`). initramfs는
tmpfs라 **푼 84MB가 통째로 RAM에 남고**, 커널 코드와 예약 48MB를 빼면 128MiB
안에 자리가 없다. 128은 panic, **256부터 뜬다.**

**UT-M0 실측 15("크기의 벽이 없었다")의 반대편이다** — 그 스파이크도 128MiB
에서 돌았고, 78MB는 되고 84MB는 안 되는 경계 위를 지나온 것이다. **아무도 그
여유를 잰 적이 없었다.**

처방은 `gate_lib.sh`의 **`GUEST_MEM=512`**다. 512인 이유는 256이 뜨긴 하지만
여유가 125MB뿐이고 **UT-M3이 git과 vim.tiny를 더하기** 때문이다. **저장소의
QEMU 호출 열둘 중 `machine/check.sh`만 RM 때부터 `-m 512`를 손으로 갖고
있었다** — 나머지 열하나는 QEMU의 기본값으로 돌고 있었고, 아무도 그 수를
고른 적이 없다는 것이 여기서 처음 드러났다. **실기에는 영향이 없다**(노트북은
GB 단위다) — **게이트만의 제약이라 실기에서는 영원히 안 보였을 것이다.**

**5. 계획 밖 2 — `sleep 2`가 짐작이었고 8회 중 2회 틀렸다.** 체인이 `fd`에서
깨졌다가 `eza`에서 깨졌다가 해서 도구 문제로 보였는데, **깨진 회차의 마지막
화면에 찾던 글자가 정확히 찍혀 있었다.** 출력이 틀린 것이 아니라 **검사가
먼저 본 것**이다. 원인은 `ps ax`가 화면을 통째로 채우는 것이고(RC-M0: 한
프레임의 84.7%가 `fill`), 게이트는 **arm64 호스트에서 x86_64를 TCG로 흉내내는
중**이라 그 한 프레임이 2초를 넘는 회차가 있다. **`fd` 하나만 따로 여덟 번
치면 8/8이다** — 앞의 `ps ax`가 있어야 재현된다.

처방은 `gate_lib.sh`의 **`wait_for_screen`**(15초까지 0.1초 간격, 찾으면 즉시
귀환). **`type_keys`가 GL-M2에서 배운 것과 글자 그대로 같은 교훈이고**
(고정 sleep은 짐작이다) 값도 같은 방향이다 — UT 체인의 고정 sleep 합계 17초가
부팅마다 사라졌으므로 **게이트를 느리게 하지 않고 빠르게 한다.**
**나머지 열 체인은 아직 고정 sleep이다** — 깨지는 것을 본 자리만 고쳤다.

**6. 음성 확인에서 검사 1이 또 tautology였다.** dest를 `fdfind`로 되돌리면
검사 1은 초록이고(같은 배열을 읽는다) 검사 9가 `Unknown command: fd`로
죽는다. `copy_lib_deps`를 eza·bat 둘에만 건너뛰면 검사 8이
`error while loading shared libraries: libgit2.so.1.9`로 죽고 **검사 1~7은
전부 초록으로 지나간다** — "특정 도구를 겨냥한 음성 확인은 그 도구만
건너뛰게 해야 한다"는 M1의 처방이 그대로 먹은 모양이다.

## UT-M2가 세운 것

| 무엇 | 어디 |
|---|---|
| 목록 50 → **63**(층 2 모던 13). `make_initrd.sh`는 **안 고쳤다** | `kernel/guest_tools.sh` |
| `.deb` 13 + 라이브러리 19 | `devcontainer/Dockerfile` |
| **`GUEST_MEM=512`** · **`wait_for_screen`** | `gate_lib.sh` |
| 검사 8·9·10(eza · fd · jq) + 정적 둘 + 고정 sleep 제거 | `tools/check.sh` |
| `-m "$GUEST_MEM"` 열둘 | 열한 체인 전부 |

**게이트는 열한 체인 3/3으로 23분 02.73초다**(UT-M1의 21분 35.63초에서
+1분 27.10초 — initrd가 gzip으로 18.6MB 커졌고 회차마다 39번 부팅한다. 잡음
±3분 안이다). **부팅은 안 느려졌다** — initrd를 2.4배로 키우고도 프롬프트까지
2.24~2.45초다. **위험 4가 이번에도 아무 체인의 판정도 안 건드렸다** — 갈린
것은 판정이 아니라 QEMU 인자 한 줄이었다.

**How to apply:** 게스트 payload를 키우는 변경은 **도구가 도는가보다 먼저
기계가 켜지는가**를 본다 — initramfs는 tmpfs라 푼 크기가 그대로 RAM이고,
게이트의 메모리는 `gate_lib.sh`의 `GUEST_MEM` 한 자리에 있다. 그리고 게이트가
화면을 보는 새 검사를 쓸 때는 **`sleep` 뒤 한 번 grep하지 말고
`wait_for_screen`을 쓴다** — 그 둘의 차이가 8회 중 2회다.

관련: [[project_gate_latency]], [[project_gate_chain_composition]]

---

## UT-M3 (2026-09-11) — **git이 섰고, 이름 둘을 바이너리가 정해 놓았다**

목록이 63에서 **65**가 되고 **링크 넷**이 섰다. 이 milestone의 성격이 앞의
셋과 다르다 — **더한 것의 대부분이 바이너리가 아니라 이름이다.**

**1. 새 라이브러리가 0이다 — 이 예측이 처음 맞았다.** git은 `libpcre2-8`·
`libz`·`libc`를, `vim.tiny`는 `libm`·`libtinfo`·`libselinux`·`libacl`·
`libc`를 부르는데 일곱 다 이미 있었다(`libz`는 M2의 `libgit2` 사슬이,
`libacl`은 `sed`가, `libselinux`는 fish가 데려왔다). **M1·M2에서 두 번 틀린
뒤다**(실측 22·30). **그래도 재고 나서 알았다 — 맞는 날과 틀린 날은 재기
전에 구별되지 않고, 그 확인은 30초다.**

**2. Debian git은 페이저와 편집기를 alternatives 이름으로 부른다.**
게스트에게 `git var -l`로 직접 물었다 — `GIT_PAGER=pager` ·
`GIT_EDITOR=editor`. 둘 다 postinst가 만드는 링크라 `dpkg -x`로 푼 sysroot에
없고, 없으면 이렇게 죽는다.

```
root@(none) /t/r (main)# git log
error: cannot run pager: No such file or directory
```

**매달리는 것이 아니라 죽는다 — 게이트는 안 깨지고 사람만 깨진다.**
`git log`·`git diff`·`git branch -a`가 전부 이 경로이고 `-m` 없는
`git commit`과 `rebase -i`가 `editor` 경로다. **`mawk`→`awk`와 같은
종류인데(결정 4) 그쪽 이름은 우리가 골랐고 이쪽 이름은 바이너리가 정해
놓았다.** 처방은 링크 둘(`pager`→`less` · `editor`→`vim`)이고, **vim은
이제 이름이 셋이고 실체는 하나다.**

**게스트에 새 도구를 넣을 때는 그 도구가 부르는 다른 도구의 이름도 함께
본다** — `DT_NEEDED`는 라이브러리만 말하고, 이 종류는 말하지 않는다.

**3. `/usr/lib/git-core`는 통째로 안 넣는다.** 168 항목 = **심볼릭 링크 141
+ 실체 26**(design 실측 7이 "하드링크"라고 적은 것의 정정. 결론은 같다).
실체 26 중 큰 것 일곱 약 16MB가 네트워크 헬퍼이고, 나머지는 셸 스크립트다.
`init`·`add`·`commit`·`log`·`status`는 전부 builtin이라 **그 트리 없이
돈다** — 부팅해서 확인했다.

**4. 커밋에는 `user.email` 하나가 필수다.** 호스트 이름이 `(none)`이라 git이
이메일을 자동으로 못 만든다(`fatal: unable to auto-detect email address (got
'root@(none).(none)')`). **이름은 `/etc/passwd`의 gecos에서 온다** — UT-M0의
뼈대가 여기서 값을 낸다. 그래서 작성자가 `root <tars>`이고, 게이트의 검사
15가 그 한 줄로 **뼈대와 결정 8을 함께** 본다.

**5. 결정 8이 실제로 돈다.** `git config --global user.email tars` 뒤
`cat /config/gitconfig`가 `email = tars`를 낸다 — git이 `/.gitconfig` 링크를
**풀고 저쪽에** 쓴다. **읽는 자리를 바꿔서 물어야** 링크를 따라간 것과
링크를 덮어쓴 것이 갈린다. **게이트에는 설정 디스크가 없으므로 증명되는
것은 "/config에 쓰인다"까지이고**, 그 디스크가 부팅 사이를 지킨다는 것은
CP 체인이 같은 마운트로 이미 증명한 것이다.

**6. 긴 출력의 첫 줄은 화면 프레임에 안 남는다.** `vi --version`의 판정을
`VIM - Vi IMproved`로 잡았는데 **프레임 어디에도 없었다**(0회). 출력 약
50줄이 한 번에 오고 프레임이 그려질 때는 첫 줄이 이미 스크롤로 사라진
뒤다. **판정은 마지막까지 남는 줄로 잡는다**(`Linking: gcc`). `dmesg`를 안
치는 이유의 뒷면이다.

**7. sendkey에는 대문자가 없다.** `git var GIT_PAGER`를 치면 변수 이름이
**통째로 안 쳐진다.** 대문자는 `shift-g`처럼 보내야 하고 이 저장소의 체인은
그것을 쓴 적이 없다 — **게이트가 칠 명령은 전부 소문자여야 한다.**

**8. 검사 1에 잠복 결함이 있었다 — 아카이브의 마지막 항목을 영영 못 찾는다.**
`PADDED_LIST="$(printf '\n%s\n' "$LIST")"`에서 **명령 치환이 끝의 개행을
도로 지운다.** `.gitconfig`이 마침 마지막 항목이라 드러났다(파일은 분명히
있는데 FAIL). 지금까지 안 드러난 이유는 마지막 항목이 한 번도 `WANT`에 없어서다.
**증상이 조용한 초록이 아니라 설명 안 되는 빨강**이라는 점에서 TR-M2의
글로브와 방향이 반대다. 고침은 명령 치환을 안 쓰는 것.

**9. 음성 확인 셋 — 이번엔 정적 검사가 tautology가 아니었다.**

| 무엇을 되돌렸나 | 검사 1(정적) | 화면 검사 |
|---|---|---|
| `.gitconfig` 링크 | **FAIL**(부팅 전) | 거기까지 못 간다 |
| `pager` 링크(+literal) | 초록 | **전부 초록 — 아무도 못 본다** |
| 목록의 `usr/bin/git` 줄 | 초록 | **검사 12 FAIL**(`Unknown command: git`) |

**링크 넷과 템플릿은 배열이 아니라 `tools/check.sh`에 literal로 적혀 있어서**
`make_initrd.sh`에서 그 줄을 지우면 부팅 전에 죽는다. **목록과 검사가 같은
파일을 보면 tautology가 되고 다른 파일을 보면 진짜 검사가 된다**는 것이 두
줄로 나란히 보였다. 그리고 **`pager`는 게이트가 영영 못 본다** — 게이트는
`--no-pager`로 치기 때문이고, 그것이 그 이름을 정적 검사에 박아 둔 이유다.

## UT-M3이 세운 것

| 무엇 | 어디 |
|---|---|
| 목록 63 → **65**(git · vim.tiny). **새 라이브러리 0** | `kernel/guest_tools.sh` |
| 링크 넷(`vi`·`pager`·`editor`·`.gitconfig`) + git 템플릿 | `kernel/make_initrd.sh` |
| `.deb` 둘. 라이브러리는 **한 줄도 안 더했다** | `devcontainer/Dockerfile` |
| 검사 12~16(git init·config·commit·log·vi) + 정적 다섯 + **패딩 결함 고침** | `tools/check.sh` |

**게이트는 열한 체인 3/3으로 23분 43.15초다**(UT-M2의 23분 02.73초에서
+40.42초 — initrd가 gzip으로 2.85MB 커졌고 UT 체인이 타이핑을 약 150글자
더했다. 잡음 ±3분 안이다). **`wait_for_screen`이 이번에도 한 번도 2초를 안
넘었다**(기다림 열다섯, `the screen took about` 0회). **위험 4가 이번에도
아무 체인도 안 건드렸다** — fish 프롬프트가 저장소 안에서 `(main)`을 붙이는데도
그렇다. 프롬프트 폭에 기대는 자리는 `copy/check.sh`의 `col 20` 하나뿐이고
**CM 체인은 저장소 안으로 들어가지 않는다.**

**How to apply:** 게스트에 도구를 더할 때 `DT_NEEDED`만 보지 말고 **그 도구가
이름으로 부르는 다른 프로그램**(페이저·편집기·헬퍼)도 함께 본다 — Debian은
그것들을 alternatives 링크로 두고 `dpkg -x`는 그 링크를 안 만든다. 그리고
**게이트가 화면에서 긴 출력을 판정할 때는 첫 줄이 아니라 마지막에 남는
줄**을 본다. 게이트가 사람과 **다른 모양으로** 치는 자리(`--no-pager`)가
생기면, 사람 쪽 모양이 성립하는 데 필요한 것은 **정적 검사에 literal로**
박아 둔다 — 타이핑으로는 영영 안 드러난다.

관련: [[project_gate_chain_composition]], [[project_guest_environment]]
