# TARS Layer Dedup — Design

접두사: LD

Date: 2026-11-12
Status: 닫힘(2026-11-12, LD-M0 — 루트 게이트 33/33). plan은 `docs/plans/2026-11-12-tars-layer-dedup-ld-m0.md`.

계기: 사용자(2026-11-12): "묶음 사이 같은 파일 지우기부터 조사해줘. emacs, doom custom 잘 안쓰는거 같아. 그리고, tars-agent(claude code,
codex, pi 같은 것)를 만들건데 그렇게 되면 에디터는 더 안쓰게 될거야." 조사 중에 "기본판에 fakesteak 추가하자 심심할 때 켜두면 재밌더라."
조사 보고 뒤 "emacs 빼고 나머지는 권고대로, design 써줘. 그리고 플랜도 쭉 써서 임플리멘테이션까지 진행해 줘." — 결정은 lead에게 맡겨졌다.

관련 문서: TP design(`2026-11-05-tars-dev-layer-design.md` — 결정 9 lowerdir, 결정 13 버전 한 줄, 비목표 6 묶음은 함께 깐다) ·
TP-M2 plan 결정 E(묶음끼리의 대조) · BB design(`2026-11-09-tars-barebone-design.md` 결정 5 · 6 — fakesteak 납품 데모와 첫 패널 자동 실행) ·
`carryover.md`의 "묶음 사이 같은 파일 지우기"(TP-M11 뒤 조사, 2026-11-08) · 기억 `project_release`(0.2.1 기본 판 2GiB까지 약 2.9MB).

## 한 줄 요약

base 아닌 묶음에서 base와 경로 · 내용이 같은 파일을 굽기 직전에 지우고(약 85MiB), editor에서 emacs-nox를 빼고(약 61MiB 더), init은
base가 못 서면 아무 묶음도 안 얹는다. fakesteak 묶음을 기본 판에도 싣고, 첫 패널 자동 실행은 base가 없는 납품 데모 판에서만 돈다.

## 확인 (2026-11-12, HEAD `d74fd8d`의 `devlayer/build/*.sqfs`)

컨테이너에서 열한 묶음을 docker volume(Linux 파일 시스템 — macOS 바인드는 `xt_CONNMARK.h` · `xt_connmark.h`가 부딪힌다)에 풀어 쟀다.

1. 파일 163,125개, 풀린 합 약 7.1GiB(lang-native 2,318MiB가 가장 크다). 크기가 같은 파일이 다른 묶음에도 있는 135,763개만 sha256을 매겼다.
2. 같은 경로 · 같은 내용이 둘 이상의 묶음에 있는 것: 풀린 288MiB, 파일 8,278개, 모두 base와 겹친 것이다(나중 묶음이 base의 파일을 또
   들고 있다). 같은 경로 · 다른 내용은 0 — `build.sh`의 대조(TP-M2 plan 결정 E)가 막고 있다. 그래서 나중 쪽을 지워도 overlay가 보이는 것은 같다.
   경로가 다르고 내용이 같은 것은 32MiB — overlay로는 못 지운다(비목표 1).
3. base와 겹친 파일을 뺀 묶음을 `build.sh`와 같은 압축(`zstd -Xcompression-level 15`, `-all-root -mkfs-time 0 -all-time 0`)으로 다시 구운 크기:

   | 묶음 | 지금 MiB | 뺀 판 MiB | 줄어든 MiB |
   |---|---|---|---|
   | editor | 140.7 | 108.3 | 32.5 |
   | server | 166.2 | 141.8 | 24.4 |
   | lang-script | 190.9 | 182.9 | 8.0 |
   | media | 106.2 | 99.1 | 7.1 |
   | util | 239.1 | 232.7 | 6.4 |
   | container | 101.7 | 98.4 | 3.3 |
   | docs | 4.8 | 1.6 | 3.2 |
   | 합 | | | 84.8 |

4. editor 621MiB(풀린)의 속: mitos 285 · emacs 본체 약 176(`usr/share/emacs` 96 · `libgccjit` 37 · `usr/lib/emacs` 17 · `usr/libexec/emacs` 16 ·
   `emacs-nox` 10) · neovim 34 · ttt 16. 3의 editor 겹침 107MiB(gcc 런타임 · sanitizer · `libc.a` · 헤더)는 `libgccjit`의 Debian 의존이 끈 것이다.
   emacs를 뺀 editor(`usr/local` · 출처 기록만)는 47.3MiB — 지금보다 93.4, 3의 뺀 판보다 60.9 작다. 3과 함께면 약 145.7MiB가 준다.
   Doom은 묶음에 없다 — 사용자가 망에서 깐다(manifest의 emacs 주석).
5. `init/src/layers.zig`의 `mountAll`은 묶음마다 따로 붙이고 실패한 것만 건너뛴다. 2의 파일을 지우면 나머지 묶음이 base의 라이브러리
   (server의 perl, editor의 gcc 쪽 등)에 기대므로, base만 못 선 부팅에서 그 실행 파일들이 깨진다. 묶음은 늘 함께 깔리고(TP 비목표 6)
   버전 줄도 하나라(결정 13) 이런 부팅은 고장 때뿐이다. 선례: `verify.sh`가 이미 initrd와 겹친 것을 지운다 — 묶음은 initrd에 기댄다.
6. `devlayer/files/fakesteak/etc/`의 조각 둘(`tars/rc.d/fakesteak.sh` · `fish/conf.d/90-fakesteak.fish`)은 부팅마다 첫 패널에 fakesteak을
   띄운다(BB design 결정 6). fakesteak 묶음을 그대로 기본 판에 넣으면 기본 판도 부팅마다 비가 내린다. 묶음은 0.3MB(323,584 B).
   `manifest-gen.zig`의 `emit`은 도구 이름이 두 번 나오면 멈춘다(`tool fakesteak again`, 구현 중 `make quick`이 드러냈다 — 조사 때는 못 찾았다).
   base가 얹힌 기계에는 그 출처 기록 `/usr/share/tars/layers/base`가 있고, 납품 데모 판(fakesteak만 싣는다)에는 없다.
7. `build.sh`는 묶음마다 경로 표 `devlayer/build/<묶음>.paths`(파일은 sha256, 링크는 대상)를 남기고 굽기 전에 다른 묶음의 표와 맞춘다.
   stamp는 매니페스트 줄 · harvest 결과 · 스크립트 · 압축 · `files/` · verify가 지운 목록이다 — base의 내용은 안 들어간다.
   verify(NEEDED 대조)는 묶음 안의 라이브러리를 보므로 base와 겹친 것을 verify 전에 지우면 빨개진다.
8. devtools 체인(`devtools/check.sh:61`)이 묶음 열하나를 다 실은 `out/tars-dev.iso`를 짓는다 — 줄어든 ISO 크기를 그것으로 잰다.

## 결정

### 결정 1 — 굽기 직전에 base와 같은 것을 지운다, 지운 목록은 stamp에 든다

`build.sh`는 verify와 묶음끼리의 대조 뒤, stamp 앞에서 base와 독립 묶음(결정 3)이 아닌 묶음의 뿌리에서 `base.paths`와 줄이 같은
경로(같은 파일 sha256, 같은 링크 대상)를 지운다. 확인 7 때문에 이 자리다 — verify는 온전한 뿌리를 보고, `.paths`도 지우기 전의 온전한 표를
남겨 다른 묶음의 대조가 그대로 돈다. 지운 목록을 stamp에 넣는다 — base가 바뀌면 지울 것이 바뀌고 그 묶음도 다시 구워진다. 빈 디렉터리는
안 지운다(지운 것 때문에 빈 것과 원래 빈 것을 가르지 않아도 되게 — overlay에서 빈 디렉터리는 해가 없다). `base.paths`가 없으면 멈춘다
(`make dev-layers`의 기본 순서는 base가 먼저다). 요약 줄에 `deduped=N`을 더하고 `files` · `unpacked`는 지운 뒤의 값으로 찍는다.

경로가 다르고 내용이 같은 것(확인 2의 32MiB)은 안 다룬다 — 하드링크는 sqfs 사이에 안 서고, 링크로 바꾸면 도구가 자기 자리를 읽는 꼴을 깬다.

### 결정 2 — base가 못 서면 아무 묶음도 안 얹는다

`mountAll`은 목록에 base가 있으면 그것을 먼저 붙인다. 실패하면 한 줄(`tars-init: layers: base failed, none mounted (the others lean on it)`)을
남기고 아무것도 안 얹는다 — 반쪽 `/usr`로 실행 파일이 이상하게 깨지는 것보다 "개발 도구 층 없음"이 알아보기 쉽다(버전이 다를 때와 같은 모양).
목록에 base가 없으면 지금처럼 붙인다(납품 데모 판은 fakesteak 하나뿐이다). base의 자리를 찾는 일은 순수 함수(`baseIndex`)로 두어
`layers_test`가 본다. lowerdir의 순서(이름 순)는 그대로다 — 같은 경로에 다른 내용이 없으므로(확인 2) 순서가 결과를 안 바꾼다.

### 결정 3 — 독립 묶음은 목록 하나로, ISO도 그것을 지킨다

base 없이 실리는 묶음(지금은 fakesteak)은 `devlayer/standalone-bundles` 한 파일에 한 줄씩 적는다. `build.sh`(결정 1에서 안 지운다)와
`boot/make_iso.sh`가 같은 파일을 읽는다. `make_iso.sh`는 `ISO_LAYERS`에 base도 독립도 아닌 묶음이 있는데 base가 없으면 멈춘다 — 결정 1의
묶음은 base 없이 온전하지 않다. 바깥 manifest에 속성을 더하는 길은 고르지 않는다(생성기 · 검사 · 문서가 함께 바뀐다).

### 결정 4 — emacs-nox를 뺀다

editor는 mitos · neovim · ttt만 남는다. tars-agent가 오면 편집기는 덜 쓰인다(사용자). 고칠 자리: `manifest.toml`의 emacs-nox 줄과 editor 머리
주석, devtools 체인의 emacs 확인 · `man emacs`(`check.sh:14` · `:526~530` · `:538~543`) — 대신 `command -v emacs`가 비었는지 본다,
`docs/help/devtools.md`의 editor 줄. `harvest.sh:155`의 alternatives 처리(emacs-nox의 `ctags` 등)는 범용이라 둔다 — 체인의 `ctags`가
universal-ctags인지 보는 줄도 그대로 둔다. Doom 안내는 기계 안 문서에 없다.

### 결정 5 — fakesteak 묶음을 기본 판에도, 자동 실행은 base가 없을 때만

fakesteak 묶음을 `DEV_LAYERS` 기본값과 기본 판의 묶음 목록에 더한다. 확인 6의 조각 둘에 조건 하나 — `/usr/share/tars/layers/base`가 없을
때만 — 를 더해, 저절로 뜨는 것은 납품 데모 판(`ISO_LAYERS="fakesteak"`)뿐이고 기본 판에서는 `fakesteak`을 손으로 친다. fakesteak은 독립
묶음이라(결정 3) base와 겹쳐도 안 지운다(0.3MB). 체인은 기본 판의 부팅 뒤 `command -v fakesteak`이 있고 `/tmp/.tars-autorun`이 없는지 보고,
묶음 수를 세는 자리(설치 · overlay · 갱신 줄)는 열둘로 고친다. `docs/help/devtools.md`의 표에 fakesteak 줄을 더한다.

처음 고른 길(util 묶음에 같은 도구 줄을 하나 더)은 확인 6의 이름 중복 검사에 막혔다. 이름만 바꾸면 설치 자리(`/usr/local/lib/<이름>-<판>`)가
달라져 두 묶음의 `/usr/local/bin/fakesteak` 링크 대상이 어긋나고, 묶음끼리의 대조가 멈춘다. 생성기의 규칙을 푸는 길은 넓다.

### 결정 6 — milestone 하나

결정 1~5를 한 milestone(LD-M0)으로, commit은 셋으로 나눈다 — 지우기(결정 1 · 2 · 3) · emacs(결정 4) · fakesteak(결정 5). 게이트는 루트
게이트 전체다(init이 바뀐다). 묶음 stamp에 `build.sh`의 해시가 들어 있으므로 묶음 열하나가 모두 다시 구워진다 — prebuild가 길다.

## 비목표

1. 경로가 다르고 내용이 같은 파일(확인 2, 32MiB).
2. base 밖 묶음끼리의 겹침 — 확인 2에서 0이다. 생기면 결정 1을 넓힌다.
3. mitos(풀린 285MiB)를 줄이는 일 — 따로 본다.
4. 판을 내는 일. 다음 판(0.2.2)에 ghostty vt-1.0.1(GU-M0)과 함께 실린다.
5. Doom · emacs를 망에서 까는 안내 — 사용자가 원하면 그때.
