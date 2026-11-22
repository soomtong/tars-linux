# 이월 숙제

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.


도구 판올림 TU-M0(2026-11-14)이 남긴 것.

- [ ] janet 1.43.0을 못 올렸다 — 배포 실행 파일이 AVX2 · BMI2를 쓴다(measurements 106). 다음 판에서 다시 세거나, upstream에 x86-64 기본
      빌드를 묻거나, 소스로 지을지(TP 비목표 7 — 소스 빌드는 안 한다) 정한다.
- [ ] mitos 0.1.3 → 0.2.1(주 편집기)은 따로 — 바뀐 것과 `runtime/grammars` 크기를 함께 본다(아래 LD 절).

화면 양보 DY-M0~M2(2026-11-13~14)가 남긴 것. 서브프로젝트는 닫혔다.

- [ ] i915 실기(맥북 에어 2011)에서 양보와 복귀를 아직 안 봤다(DY-M0 plan Task 5): `tars-fullscreen tars-kms-fill CC6666 5 2>/tmp/fill.log`.
      볼 것 — 색이 뜨는가, 5초 뒤 콘솔이 깨끗이 돌아오는가(design 위험 1 — 앱이 죽은 뒤의 CRTC 상태), simpledrm → i915로 카드가 바뀌는
      부팅에서 `tars-init: display:` 줄이 무엇을 셌는가(init은 terminal을 띄우기 전에 한 번만 연다).
- [ ] 부팅 뒤 생긴 DRM 노드(USB 디스플레이 등)는 root 600으로 남는다 — `/dev/snd`와 같은 까닭(init에 uevent가 없다, HP 절).
      양보 중에 꽂은 키보드도 같다(DY-M1): 손님 uid에게 안 넘어가 그 앱은 그 키보드를 못 연다.
- [ ] 실기에서 키 · 탈출을 볼 것(DY-M1): `tars-fullscreen tars-kms-fill CC6666 0 --keys`에서 친 키가 셸에 안 들어가고 Esc로 끝나는가,
      `Ctrl+Cmd+Backspace`(Apple 자판)로 `tars-fullscreen tars-kms-fill CC6666 0`이 끝나는가.
- [ ] 실기에서 GPU 데모를 볼 것(DY-M2, 기본 판 다음 판부터 gpu 묶음이 실린다): `tars-fullscreen tars-gpu-demo 2>/tmp/gpu.log` —
      `gl` 줄이 crocus(Sandy Bridge HD 3000)인가, `frames N in Mms`(Esc로 끝낸 뒤), 탈출 조합으로 끝날 때 `shut down`이 2초 안인가.
- [ ] SDL3 앱이 `main`에서 돌아가면 Mesa · LLVM의 전역 소멸자로 끝내기가 느리다(TCG에서 2초를 넘겨 SIGKILL — DY-M2 plan 결과 4).
      기성 SDL 앱을 탈출 조합으로 끝낼 때 SIGKILL이 자주 가면 terminal의 기한(2초)을 늘릴지 본다.

컨테이너 실행 환경 CE(2026-11-12)가 남긴 것. TP-M12의 "컨테이너 실행 환경" 항목은 CE가 닫았다
(`docs/specs/2026-11-11-tars-container-environment-design.md`).

- [ ] SMP. 커널이 CPU 하나만 쓴다(`# CONFIG_SMP is not set`, `NR_CPUS=1` — BF 때부터). 코어가 여럿인 실기에서 컴파일 · 컨테이너가 한
      코어에 줄을 선다. `docker info`의 `No cpuset support`도 이것이다(`CPUSETS`가 SMP에 기댄다). 켜면 커널 전체가 다시 빌드되고
      init · terminal의 "CPU 하나" 가정(`key-files.md`의 poll 자리, RS 실측 3)과 게이트의 타이밍을 다시 봐야 한다 — 서브프로젝트 크기다.
- [ ] ISO가 GitHub release의 2GiB 한도에 닿았다. `container` 묶음 101MiB를 실으며 `ctr`을 뺐다. 다음에 묶음이 자라면 아래 "묶음 사이 같은
      파일 지우기"(약 200MiB)를 꺼내거나 기본 판 ISO에서 묶음 하나를 뺀다.
- [ ] `/config`(ext2, 저널 없음)는 전원이 갑자기 끊기면 방금 쓴 것이 깨질 수 있다. CE-M2 프로브를 QEMU 죽이기로 끝냈더니 다음 부팅에서
      `/config/services.d/docker`가 `ext2_lookup: deleted inode referenced`로 안 읽혔다(QEMU가 쓰기 캐시를 버렸다 — `MS_SYNCHRONOUS`는
      게스트 쪽 약속이다). 실기에서 배터리가 빠지는 것과 같은 종류다. 고치는 길: p2를 ext4로(설치기 · 갱신 · `mountConfig`), 또는
      부팅 때 `e2fsck -p`. 실기에서 겪으면 연다.
- [ ] rootless Docker · Podman(CE 비목표 2). `USER_NS`는 있다. 더 필요한 것은 `newuidmap` setuid · `/etc/subuid` · `TUN`(pasta) ·
      사용자별 런타임 디렉터리다.
- [ ] Docker의 nftables 백엔드는 문서 표시가 아직 experimental이다(29.9). Docker 판을 올릴 때 릴리스 노트의 그 절을 본다 — 표 이름
      (`ip docker-bridges`)이나 `nft` 호출 방식이 바뀌면 devtools 체인의 방화벽 공존 판정이 먼저 빨개진다.
- [ ] 실기에서 처음 볼 것: Docker가 실제 NIC(유선 · 무선) 위에서 밖으로 나가는지(QEMU는 SLIRP였다), 맥북 에어 2011(Sandy Bridge)에서
      이미지 받기 · 풀기의 속도, `claude` 샌드박스(`/sandbox`)가 `bwrap` · `socat`으로 서는지(codex는 게스트에서 봤다).

TP-M12 뒤 조사(2026-11-08, Nerd Font 기호)가 남긴 것.

- [ ] Nerd Font 기호 — Powerline은 직접 그리고, 아이콘은 비트맵 fallback으로. 계기: omp의 첫 화면 `Tip: Please use nerdfont`(TP-M12 plan
      확인 4). unifont 17.0.03에서 Nerd 코드포인트 21개(Powerline E0B0 · E0A0, Devicons E725 · E73C, FA F113 · F07B, Octicons F489, MDI F0001 ·
      F1AB6 등)가 모두 `stbtt_FindGlyphIndex` = 0 — 화면에는 `.notdef`의 6x11 상자가 찍힌다. [[project_font_selection]]의 "폰트에 없는 글자가
      존재하지 않는다"는 화면에서만 맞고, gid 0으로 없는 글자를 가릴 수 있으므로 `font.zig`의 `find()`가 gid 0일 때 다음 폰트를 보는 자리가 있다.
      실측(TARS의 `terminal/vendor/stb_truetype.h`, 문턱값 `> 127`): SymbolsNerdFontMono 3.4.0은 중간값 비율 60.0%(16px) · 56.1%(14px),
      SymbolsNerdFont는 63.9% — Powerline 삼각형 · 폴더처럼 면이 넓은 것만 살고 git branch(E0A0) · Tux(F17C) · 체크(F00C)의 가는 획은 끊기거나
      뭉친다. 16px 그대로면 높이 17행이라 셀을 1행 넘는다(14px이면 들어간다). 아웃라인 기호 폰트를 그대로 싣는 것은 design 결정 4(알파 블렌딩
      없음)를 뒤집는 일이라 MonoplexNerd가 탈락한 이유와 같다.
      ghostty가 하는 것(`_study/ghostty`): 기호 전용 폰트를 내장해 마지막 fallback으로 붙이고(`src/font/embedded.zig` · `SharedGridSet.zig`),
      Powerline E0B0~E0BF · E0D2 · E0D4는 폰트 없이 코드로 그리며(`src/font/sprite/draw/powerline.zig` — 박스 드로잉 · 점자도 같은 길), PUA는
      vt에서 폭 1이지만 다음 칸이 비고 앞 글자가 기호가 아니면 2칸까지 넘쳐 그린다(`src/renderer/cell.zig`의 `constraintWidth`, 크기 · 정렬은
      `src/font/nerd_font_attributes.zig`의 코드포인트별 constraint 표).
      걸리는 자리: TARS의 `main.zig`는 그리는 폭을 폰트 advance(`glyph.cell_width / CELL_W`)에서 얻는데 Symbols Mono의 advance가 16px에서 16이라
      2칸으로 그려진다 — vt(libghostty-vt)는 1칸으로 세므로 폭 규칙 없이 얹으면 아이콘이 옆 글자를 덮는다.
      후보: Cozette 1.30.0(손으로 그린 6x13 비트맵, Nerd 아이콘 다수, MIT — "Nerd Fonts의 비트맵 대안"이 목표라고 README에 적혀 있다).
      `.otb`는 비트맵 전용 sfnt라 stb가 못 읽으므로 `CozetteVector.ttf`를 픽셀 격자에 맞는 scale로 읽거나 `.bdf`/`.psf` 로더가 필요하고, 8x16
      격자에서는 작게 여백을 두고 앉는다. 그날 GitHub 릴리스가 504라(TP-M12의 opencode와 같은 장애) 재지 못했다 — jsdelivr로는 원본 `.sfd`만
      받을 수 있었다.
      → NS-M0(2026-11-08)이 (1)의 넷(E0B0~E0B3)을 했다 — `terminal/src/sprite.zig`, [[project_nerd_symbols]]. 남은 Powerline(E0B4~E0BF · E0D2 ·
      E0D4)은 그 switch에 줄을 더하는 일이고, E0A0(git branch)은 손으로 그린 비트맵이 된다.
      사용자 결정(2026-11-08, NS-M0 뒤 `eza --icons` 화면을 보고): "real font system should go with gpu accel stage" — 아이콘 fallback 폰트 ·
      폭 규칙 · 아웃라인 폰트(알파 블렌딩)는 GPU 가속 서브프로젝트와 함께 연다. 그 전에는 sprite에 Powerline 줄을 더하는 것까지만.
      정할 것: (1) Powerline을 렌더러가 직접 그리기(폰트가 필요 없고 문턱값과 충돌하지 않는다 — 프롬프트 체감은 대부분 여기서 난다), (2) 아이콘
      fallback 폰트 — 먼저 `CozetteVector.ttf`에 중간값 0%가 되는 scale이 있는지 잰다, (3) 폭 규칙 — 1칸 고정(8px 아이콘)인가 ghostty처럼 "다음
      칸이 공백이면 2칸"인가(렌더러 계약이 바뀌므로 design 결정감), (4) 폰트를 둘 싣게 되면 [[project_font_selection]]의 "고칠 자리 열"과
      `terminal/vendor/fonts/README` · initrd 크기.

개발 도구 층 TP-M11 뒤 조사(2026-11-08)가 남긴 것.

- [x] 묶음 사이 같은 파일 지우기 — LD-M0(2026-11-12)이 닫았다: base 아닌 묶음은 굽기 직전에 base와 같은 것을 지우고 init은 base가 못 서면
      아무것도 안 얹는다, emacs-nox도 뺐다. 묶음 1,908 → 1,762MiB, 기본 판 구성 ISO 1,992,007,680 B(2GiB까지 148MiB). 아래는 그 전의 기록이다.
      `devlayer/build.sh`의 묶음끼리 대조(TP-M2 plan 결정 E)는 내용이 다르면 멈추고 같으면 `shared`로 세기만 한다 —
      같은 파일이 두 sqfs에 다 들어간다. base와 겹친 양(거두기 tar 크기, 풀린 것 → tar째 zstd -15): editor 108 → 28MiB(emacs가 끈 gcc 쪽), server
      93 → 22MiB(perl 57MiB — postgres · mysql의 의존, base와 같은 판 · 바이트), lang-script 24 → 6, media 20 → 6, util 18 → 5, docs 10 → 2. 합 약
      270MiB → 69MiB(squashfs는 블록마다라 실제 ISO 감소는 조금 더 클 것). 고치는 길: 나중 묶음에서 앞 묶음과 같은 파일을 지운다(verify.sh가
      initrd와 겹친 것을 지우는 것과 같은 일). 근거는 묶음을 다 함께 깔고(비목표 6) 판이 다르면 안 얹는 것(결정 13). 정할 것: 지운 묶음이 앞
      묶음에 기대게 되므로 base가 안 얹힌 부팅에서 나머지를 어떻게 할지. AI 도구를 싣지 않기로 해(사용자 2026-11-08) 지금은 자리가 급하지 않다 —
      ISO 2GiB에 다시 닿으면 꺼낸다.
      libicu는 줄일 수 없다: Debian `libicu76`(36MiB, `libicudata` 31MiB)은 postgres · initdb의 NEEDED, mysql의 `/usr/lib/mysql/private` ICU 77
      (51MiB)은 mysqld의 NEEDED — 둘은 서로 다른 판이고 묶음 사이 중복도 아니다. 데이터를 깎으려면 소스 빌드(비목표 7).

개발 도구 층 LD-M0(2026-11-12, 묶음 사이 중복 · emacs · fakesteak)이 남긴 것.

- [ ] "base가 못 서면 아무 묶음도 안 얹는다"(LD design 결정 2)는 체인의 부팅으로는 안 봤다 — 부팅 3이 깨뜨리는 것은 lang-jvm이다. `baseIndex`는
      `layers_test`가 본다. 볼 때: devtools 체인에 base를 깨뜨리는 부팅을 하나 더(게이트 시간이 는다) 또는 부팅 3의 대상을 바꾸기.
- [ ] mitos가 editor의 풀린 285MiB(압축 뒤 editor 47MiB의 대부분)다 — 줄일 길(`runtime/grammars` 301개 중 쓰는 것만 등)을 따로 본다.
- [ ] 경로가 다르고 내용이 같은 파일 32MiB(묶음 사이) — overlay로는 못 지운다(LD 비목표 1).

개발 도구 층 TP-M8(2026-11-07, 터미널 유틸리티 · media)이 남긴 것.

- [ ] 셸 완성. util의 12개 도구(bat · fd · hyperfine · rg · glow · hurl · sd · xh · yazi · go-task · fastfetch 등)와 mitos(`contrib/completion`)가 완성
      파일을 싣지만 잇는 자리가 없다 — initrd의 zsh는 Completion 트리(`/usr/share/zsh`, 17MB)를 싣지 않고 `compinit`도 부르지 않으며(`kernel/make_initrd.sh`의
      주석), bash에는 `bash-completion`이 없다. 이으려면 그 둘부터(base 묶음의 `debian` 줄이 후보 — 묶음 없는 부팅과 갈린다), TCG에서 `compinit`이 셸
      시작을 얼마나 늦추는지 재고, 도구마다 다른 자리(`autocomplete/` · `completions/` · `complete/`)를 `/usr/local/share/{zsh/site-functions,bash-completion/completions,
      fish/vendor_completions.d}`로 링크하는 길(매니페스트 선택 키는 다섯 — 한도)을 정한다. TP-M7 · M8 plan의 맡아 정한 것 3.
- [ ] 묶음 실행 파일의 CPU 수준을 verify가 보게 하기. 지금은 받을 때 사람이 `objdump`의 `%ymm`을 센다 — DuckDB 2.0은 CLI를 x86-64-v3로 빌드해
      함수의 20%에 AVX2 · FMA가 퍼져 있었고(TP-M8 plan 확인 11, 1.5.6을 실었다), 실행 중 고르기(ripgrep · uv · ffmpeg)는 몇 함수에 모인다. QEMU TCG는 CPUID에
      없는 AVX2도 실행해 체인으로는 못 잡는다(TP-M3 확인 8). 후보: 심볼이 있는 ELF에서 ymm 정수 · FMA 명령이 든 함수의 비율이 문턱을 넘으면 멈추기
      (벗겨진 ELF는 따로). upstream이 판을 올릴 때 같은 일이 또 생긴다.

LT(2026-11-12)가 남긴 것. 위 다섯(ping · hostname · DMI id · Landlock · sudo timestamp)은 LT-M0이 닫았다.

- [ ] Homebrew의 Landlock 샌드박스는 선다(pm 체인의 `brew install hello`가 `Landlock ABI: 7`을 찍었다). 다만 그 경고대로 망 전부를
      막는 것은 Landlock ABI 10부터다 — 6.18은 7이라 일부만 막는다. 커널을 올리면 풀린다(KU의 7.4 이동).
- [ ] git의 기본 신원은 여전히 도메인이 없다(`<이름>@tars.(none)`으로 읽었다 — 게스트에서 재지는 않았다). `[user]`를 주면 상관없다.
- [ ] hostname을 DHCP 요청에 싣기 · mDNS(`<이름>.local`)는 LT 비목표다.

맥 실기(2026-11-05)가 남긴 것.

- [ ] MacBook Pro 2013 내장 Wi-Fi — 사용자 결정으로 대기(2026-11-05). 기종이 갈린다(`/sys/class/dmi/id/product_name`).
      - MacBookPro10,1 · BCM4331: 커널 `b43`(지금 `# CONFIG_B43 is not set`). firmware는 Broadcom 독점 드라이버에서 `b43-fwcutter`로
        잘라야 하고 재배포가 분명하지 않다. b43는 인터페이스를 올릴 때 firmware를 읽으므로 `/config`에 둬도 된다. 추천은 ISO에
        `b43-fwcutter`만 싣고 사용자가 드라이버 tarball을 USB로 옮겨 `tars-config wifi-firmware <파일>`로 한 번 자르는 길.
      - MacBookPro11,2 · 11,3 · BCM4360(`14e4:43a0`): 커널의 AC-PHY는 `BROKEN`, 독점 `wl`은 외부 모듈 — `CONFIG_MODULES`가 없는 TARS에
        모듈 적재(init) · 6.18용 패치 · 독점 바이너리 배포를 함께 들여야 하는 새 서브프로젝트 크기다. USB 무선 동글이 싼 대안.
- [x] MacBook Pro 2013 소리가 안 났다 — 카드 0(HDMI 쪽 HDA)이 안 서서 init의 오디오 일꾼이 포기했다. 일꾼이 아무 카드나 기다리게 고쳤다
      (AU design 위험 14의 덧붙임). HDMI 오디오 자체는 여전히 없다 — LP-M0부터 `SND_HDA_I915`는 서 있지만 내장 cmdline의 `snd_hda_core.gpu_bind=0`이
      GPU 쪽을 안 본다(xe 몫인 Intel GPU에서 소리가 사라지지 않게, LP design 결정 1a). 외장 모니터로 소리를 낼 일이 생기면 그때.

MI-M0(2026-11-03)이 남긴 것.

- [ ] 공식 `mise.run`은 512MB 기계에서 굳는다 — `mktemp -d`(tmpfs `/tmp`)에 tarball 약 60MB와 푼 `mise` 172MB를 함께 두고, RAM에
      풀린 initrd 약 280MB와 합쳐 넘친다(MI 실측 6). Homebrew도 1GiB를 요구하므로(PM 실측 4) 고치지 않았다. 작은 RAM 기계가
      요구하면 사용자 환경의 `TMPDIR`을 디스크(`~/.cache/tmp` 등)로 두는 길이 있다 — 모든 프로그램의 임시 자리가 바뀌는 일이다.

PM(2026-11-03)이 남긴 것.

- [ ] TARS 자체 패키지 매니저는 나중에 다시 논의한다 — 당분간 Homebrew를 쓴다(사용자 결정, 2026-11-03). 그날 정리한 것:
      - 남의 것 중에 완벽히 맞는 것은 없었다. mise · aqua(미리 빌드된 CLI 바이너리, sudo · ruby 없음), micromamba · pixi
        (conda-forge, `~` 아래), Nix(범위 최대 — `/nix`를 디스크에 · daemon · 평가 메모리), 배포판 매니저(apt · xbps — "루트를
        디스크로"가 앞선다).
      - 자체로 만들면 어려운 것은 도구가 아니라 패키지의 출처다. 추천은 Debian trixie `.deb`를 런타임에 받는 것(유저랜드와 같은
        glibc · libstdc++ ABI, `InRelease` 서명, 빌드 서버 불필요 — 빌드 때 Dockerfile + `make_initrd.sh`가 이미 하는 일).
      - design에서 정할 것: 설치 자리(overlayfs로 initrd `/usr` 위에 디스크 층 vs `/home` 아래 prefix), initrd에 있는 패키지를
        "설치됨"으로 보는 목록과 TARS 갱신 때의 어긋남, 설치 권한(root · sudo), `Depends`를 어디까지 따르나, `Packages` 색인의
        RAM 예산. 접두사 후보 `TP`(TARS Package, 미사용).
      - 2026-11-09: 접두사 `TP`는 개발 도구 층(TP, 닫힘)이 썼다 — 이 항목을 열 때는 다른 접두사를 고른다. TP는 런타임에 받는 매니저가
        아니라, 빌드 때 매니페스트대로 받은 도구를 묶음(squashfs)으로 실어 망 없이 쓰게 한 것이다. 그래서 "설치된 패키지 목록"과 "TARS
        갱신 때의 어긋남" 문제는 묶음 쪽에서는 `.tars/layers/version` 한 줄로 풀렸고(갱신이 묶음을 통째로 바꾼다), 런타임 매니저의 질문은 그대로 열려 있다.
- [x] mise 지원 — 서브프로젝트 MI로 열었다(2026-11-03, `docs/specs/2026-11-03-tars-mise-design.md`). initrd에는 안 싣는다(176MB).
- [ ] 라이브러리는 libstdc++만 Debian 모양(실체 + SONAME 링크)이다(PM 결정 10). 다른 바깥 프로그램이 다른 `.so`의 이름에서
      버전을 읽으면 그때 같은 판정을 한다.

HP-M1(2026-11-02)이 남긴 것.

- [ ] 부팅 뒤 꽂은 USB 헤드셋 · 사운드 카드의 노드는 root 0600 그대로다 — init의 audio 일꾼이 부팅에 한 번 `/dev/snd/*`를
      `root:audio 660`으로 바꿀 뿐이고 init에는 uevent가 없다. 실기에서 거슬리면 terminal의 uevent 길(포인터 · 키보드가 쓰는 것)에
      `SUBSYSTEM=sound`를 얹거나 init에 작은 uevent 듣기를 둔다.
- [ ] 화면 셸의 히스토리 자리(fish `~/.local/share/fish`)와 zoxide DB가 홈에 생기는지 게이트가 못 봤다(HP 실측 11).

HP-M2(2026-11-03)가 남긴 것.

- [ ] 사용자의 `tars-config dictation key`는 키를 다 친 뒤에야 `try: sudo`를 듣는다(쓰기 자리에서 고르므로). 비밀 입력 앞에서 쓰기
      권한을 먼저 보는 것은 실기에서 거슬리면.

KH(2026-11-02)가 남긴 것.

- [x] init의 키보드 고르기 · 3초 기다림 · argv의 `device_path` 칸은 이제 terminal이 안 쓴다(KH 비목표 2). 키보드 없이 부팅하면 3초가
      늦다(KH 실측 3). 걷으려면 PID 1과 `device` · `machine` 체인의 판정 줄(`tars-init: keyboard device`)을 함께 고친다.
      → IK-M0(2026-11-03)이 걷었다. `ARGC` 9, 체인 넷은 terminal의 `keyboard> open`으로 판정, 키보드 없는 부팅이 3.33초 빨라졌다
      (`docs/specs/2026-11-03-tars-init-keyboard-design.md` 실측 1).
- [x] 장치별 수정키(KH 비목표 5, 시나리오 S5). 같은 수정키를 두 키보드에서 겹쳐 쥐었다가 한쪽에서 떼면 둘 다 풀리고, 한쪽이
      빠지면 남은 쪽의 수정키도 풀린다. 실기에서 거슬리면 장치마다 "이 장치가 누른 수정키" 비트 여덟.
      → DM(2026-11-04)이 닫았다. 수정키 · tap을 칸마다 들고, 겹친 tap 키의 누름은 소비로 시작한다. 커널 자동 반복이 쥔 수정키를
      다시 켜 결함을 반쯤 가렸다 — 드러나는 것은 그 키보드로 다른 키를 하나 친 뒤다
      (`docs/specs/2026-11-04-tars-device-modifiers-design.md` 실측 1).
- [ ] 두 키보드의 자동 반복이 섞인다(시나리오 S7) · 한 바퀴 안의 두 키보드는 칸 순서로 읽힌다(위험 7) · 키 하나를 두 노드로
      내는 키보드는 글자가 두 번이다(위험 6). 셋 다 실기의 근거를 기다린다. 위험 6의 첫 단서는 같은 `name=`의 `keyboard> open` 둘.
- [x] 키보드마다 다른 `keyboard=apple|pc`(KH 비목표 1). Mac 키보드와 PC 키보드를 함께 쓰면 한쪽의 Option · Cmd가 어긋난다.
      → KK(2026-11-04)가 닫았다. `keyboard=auto`(새 기본값)가 키보드를 열 때 vendor로 고른다(Apple 0x05ac · BT 0x004c면 apple).
      남은 것은 vendor가 배열을 말하지 않는 서드파티 Mac 배열 키보드 — 아래 KK 절.

KK(2026-11-04)가 남긴 것.

- [ ] vendor가 배열을 말하지 않는 키보드(KK design 위험 1 · 비목표 1). Mac 배열인데 Apple vendor가 아닌 서드파티 키보드는 `auto`에서
      `pc`로 읽힌다 — 그 키보드 하나만 쓰면 `keyboard=apple`을 적으면 되지만, PC 키보드와 함께 쓰면 고칠 길이 없다. 실기에서 그런
      키보드가 생기면 이름이나 vendor를 설정에 적는 키. 판단의 근거는 `keyboard> open … kind= bus= vendor=` 줄이다.

BT(2026-11-02)가 남긴 것.

- [ ] 실기에서 처음 볼 것: `bluetoothctl list`에 내장 어댑터가 뜨는지(안 뜨면 `dmesg | grep -i bluetooth` — firmware 이름이
      목록에 없으면 그 이름을 `guest_firmware.sh`에), BLE 마우스를 `pair` · `trust` · `connect`한 뒤 화살표가 움직이는지(uhid →
      evdev → terminal의 pointer hotplug), 재부팅 뒤 마우스가 스스로 다시 붙는지(`/config/bluetooth`의 키). BLE HID의 uhid 길은
      게이트가 못 본다(BT design 위험 4).
- [ ] `bluetooth` 체인의 `btvirt` crash 간헐(KH-M1 루트 게이트 1회차, 2026-11-02). 페어링 직후 `traps: btvirt[107] general
      protection fault`로 죽어 가상 컨트롤러 둘이 사라졌고, 재시작한 bluetoothd가 `controllers 0`을 봤다(`after the restart
      bluetoothd does not know the pairing`). 같은 산출물로 체인만 다시 돌린 두 판은 crash 없이 초록이다. Debian `bluez-test-tools`의
      바이너리이고 게이트 전용이다(initrd에 없다). 다시 나면 `/tmp/btvirt.log`를 콘솔로 꺼내는 것부터.
      두 번째(KK-M0 루트 게이트, 2026-11-04): `btvirt[105]`, 같은 서명. 체인만 다시 돌린 판은 초록이다. 둘 다 루트 게이트의
      동시 레인 안에서만 났다 — 부하와 상관이 있는지가 다음 단서다.
      세 번째(TP-M6 루트 게이트, 2026-11-06, lane 20): `btvirt[106]`, 같은 서명(`controllers 0 paired`). 체인만 다시 돌린 판은 초록(3분 38초)이다.
      셋 다 동시 레인 안이다. 이 게이트는 lanes 1,462초로 지금까지 가장 길었다(lane-0의 devtools가 716초).
      다섯 번째(SW-M1 루트 게이트, 2026-11-18, 다시 lane 20): 같은 서명(`services.d/bt` 53행 `Segmentation fault`,
      `controllers 0 paired`). 체인만 다시 돌린 판은 초록(206초). 네 번째는 아래 pointer 항목에 잘못 들어간 PS-M0의 것이다.
      여섯 번째(WY-M0 루트 게이트 둘째 판, 2026-11-19): `btvirt[94]`, 같은 서명. 체인만 다시 돌린 판은 초록(3분 22초).
      일곱 번째(WY-M4 루트 게이트, 2026-11-20): `btvirt[108]` general protection fault(segfault가 아닌 다른 꼴, 같은 btvirt). 체인만 다시 돌린 판은 초록(3분 25초).
      여덟 번째(CR-M1 루트 게이트, 2026-11-22): `btvirt[107]` general protection fault, 같은 `controllers 0 paired`. 체인만 다시 돌린 판은 초록.
- [ ] `pointer`(PD-M4) 부팅 C의 말없는 끝(TP-M2 루트 게이트 2회차, 2026-11-06, lane 16). `(라)`의 `=== … ===` 줄 바로 뒤에
      `report_failure` 없이 체인이 끝났다. 시리얼 로그는 `(나)`가 친 `/config/pd/tp-replay`의 메아리와 그 뒤 몇 줄에서 멎었고 패닉
      줄은 없다. lane 출력에도 셸 오류가 없다. `set -e`가 꺼진 체인이 말없이 끝나는 길은 SIGPIPE다 — QEMU(`-no-reboot`)가 사라진 뒤
      `replay`의 `type_keys`가 monitor 소켓에 쓴 것으로 본다(추정). OrbStack VM의 dmesg에 OOM은 없다. 같은 게이트의 1회차와 3회차는
      초록이고, TP-M2는 커널 · init · terminal을 안 바꿨다. 이 게이트부터 devtools 체인이 TCG에서 zig · go 첫 빌드(수십 초씩)로 CPU를
      더 쓴다 — 다시 나면 QEMU의 종료 코드를 체인이 찍게 하는 것부터(`wait "$QEMU_PID"; echo $?`).
      세 번째(PS-M0 루트 게이트, 2026-11-04): `btvirt[104]`, 같은 서명(`ip:f3b9349de916e1ad`, `services.d/bt` 53행 `Segmentation
      fault`). 체인만 다시 돌린 판은 초록이다(214초). 셋 다 루트 게이트의 동시 레인 안이다.
      네 번째(FS-M0 루트 게이트 1회차, 2026-11-07, 다시 lane 16): 부팅 B의 "two fingers scroll" — 시리얼 로그 끝이
      `scroll> total=212 offset=162 len=47`(6줄 기대에 3줄)이고 lane 출력에 `report_failure`의 `FAIL:` 줄이 없다(말없는 끝, 부팅 B는 처음).
      체인 혼자는 초록(4분 38초, 같은 검사가 `offset=159` · wheel 2). FS-M0은 pointer · terminal · 커널을 안 바꿨다.
- [ ] Intel BT firmware 28MB를 전부 싣는다(BT design 결정 2). 실기가 쓰는 칩이 몇 개로 정해지면 그 `ibt-<hw>` 계열만 남겨
      initrd를 20MB 줄일 수 있다 — 지금은 근거가 없어 전부다.

KU(2026-11-01)가 남긴 것.

- [ ] 7.4가 longterm으로 지정되면(12월 중순 예상, kernel.org `releases.json`의 `moniker`) 6.18에서 옮긴다. 메이저가 바뀌어
      `KERNEL_MAJOR`가 `7.x`이고 config diff가 크다. KU-M1 plan 확정 1~7을 같은 방법으로 다시 본다(`project_kernel_upgrade.md`
      배운 것 4) — 툴체인 최소 버전도 더한다.
- [ ] 실기에서 처음 볼 것: 메뉴 3초가 손에 맞는지, 0.1.3 이하로 깔린 디스크를 새 ISO로 갱신한 뒤 메뉴의 `(old)`가 옛 커널로 뜨는지(이미
      깔린 디스크는 `boot/version`이 없어 첫 갱신에 old가 안 생긴다 — 두 번째 갱신부터, 또는 `--wipe`로 다시 깐 뒤), Limine 메뉴가
      GOP 화면에 보이는지.

BS(2026-10-09)가 남긴 것.

- [ ] 실기 노트북에서 볼 것 셋. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`으로 `Battery`가 있는지 본다(로그
      `terminal: battery> scan seen=… present=… pick=…`도 같은 것을 말한다). `capacity` 파일이 없는 배터리는 칸이 `  ?%`인 것이
      정상이다(ACPI의 `full_cap_broken`). 어댑터를 꽂았다 뺄 때 색이 곧바로 초록 · 회색으로 바뀌는지 본다 — 바뀌지 않으면 firmware가
      ACPI notify를 안 보내는 기계이고 60초 주기가 받는다.

VD(2026-10-06)가 남긴 것.

- [ ] `render` 검사 28(vim의 `R` 뒤 underline 커서)이 VD-M2의 루트 게이트 2회차에서 한 번 빨갰다(`vt=block`인 채 15초). 앞선 루트 게이트
      여섯(열두 회차)과 그 뒤의 재실행은 초록이었고 M2는 terminal · 커널 · initrd 내용을 안 바꿨다 — 간헐이다. 시리얼 로그가 `mktemp`라
      `R`이 vim에 닿았는지(`key>` 줄 · `-- REPLACE --`)를 못 봤다. GF-M1(2026-10-24)부터 모든 체인의 로그가 `out/gate-logs/`에
      남는다(루트 게이트는 `<시각>/TR-M2-<회차>/`) — 다음에 빨개지면 그 로그에서 `key>` 줄과 `-- REPLACE --`부터 본다. 판정은 안
      넓혔다(원인을 모른다).
- [ ] 정리의 상한 `cleanup_timeout`(기본 1.5초)이 실기의 첫 연결(DNS · TLS)을 덮는지는 게이트로 못 잰다. 실기에서 `cleanup timed out`이
      매번이면 값을 늘리거나 `cleanup = off`. 크면 연결을 붙잡아 두는 상주 프로세스(VD design 결정 1의 (d) · 위험 5)를 다시 연다.
- [ ] 비밀번호 판정(`ICANON && !ECHO`)이 못 보는 자리 — 자기 편집기로 가리는 프롬프트(fish의 `read -s`)에는 글자가 들어간다(Enter는 안
      붙는다). 겪으면 그 프로그램의 모양을 적는다.

AU(2026-10-06)가 남긴 것.

- [ ] 늦은 내장 카드(AU design 위험 14). 일꾼은 첫 `controlC<N>`이 서는 순간 있는 카드만 `alsactl init`한다(2026-11-05부터 카드 0이 아니어도 된다 —
      MacBookPro11,x 실기). 카드가 여럿인 AMD
      노트북이나 SOF가 firmware를 늦게 올리는 Intel 노트북에서 늦은 카드가 꺼진 채 남으면 — 일꾼이 `/dev/snd`가 잠잠해질 때까지
      기다리거나 `follow`가 새 카드에 `alsactl -U init N`을 부른다. 실기에서 겪은 뒤 정한다.
- [ ] firmware가 게스트 RAM에 늘 있다(WL 위험 5 · AU 위험 16). 무선 77 + 소리 42 = 119개일 때 512MB 게스트의 `MemAvailable`이
      약 183MB였고, UB(2026-10-31)가 21개를 더해 140개다. 다음에 firmware를 더하는 일은 이것을 함께 본다 — 초기 ramfs에서 빼서
      늦게 붙이는 길이 있는지. 체인이 메모리로 흔들리면 여기부터 본다.
- [ ] `audio` 검사 5의 사각파 하한 40,000은 부하 아래 최소 47,425에서 정했다(AU design 실측 17). 루트 게이트가 `tone`으로 빨개지면
      dmix xrun이 더 커진 것이다 — `doubled` · `zero`를 먼저 본다.
- [ ] `audio` 부팅 A의 `speaker-test` 간헐(UB-M2 루트 게이트 1회차, 2026-10-31, lane 17). 출력이 `0 - Front Left|Write error: -32,Broken
      pipe| 1 - Front Right`라 판정 줄 `[ 0 - Front Left| 1 - Front Right]`와 안 맞았다 — ALSA underrun(EPIPE)이 두 목소리 사이에
      끼었고 같은 부팅의 `aplay` 사각파(tone=47952 · doubled=0)와 그 뒤 두 채널 판정은 멀쩡했다. 단독 재실행 PASS, 2회차 루트
      게이트도 본다. 로그 `out/gate-logs/20261031-140338/AU-M3-1/`. 판정은 안 넓혔다 — 한 번 더 겪으면 `speaker-test` 줄에서
      `Write error` 토막을 빼고 보는 것(underrun은 소리가 끊긴 것이지 채널이 바뀐 것이 아니다)이 후보다.
- [ ] 실기에서 볼 것 — `running-tars.md`의 소리 절. SOF 노트북에서 `Firmware file:` · `Topology file:` 두 줄, IPC4 `-3ch` topology 없음
      (위험 12), 잭 입력 장치가 키보드 · 포인터 판정에 안 걸리는지(위험 2).

PD(2026-10-05)가 남긴 것.

- [ ] 터치패드 출발값 셋(180ms · 2% · 배율)을 실기에서 손으로 본다(PD design 위험 3). 고친 값은 `touchpad_test`에도.
- [ ] 누름과 첫 칸 이동 사이에 출력이 오면 선택이 한 줄 어긋날 수 있다(PD design 위험 2). 겪으면 tracked pin으로.
- [ ] 커널 코드 배치가 TCG의 initramfs 풀기 시간을 움직인다. 커널을 바꾼 뒤 `install` 부팅 7의 `init waited`가 500ms 아래로
      내려가면 그 신호다(PD 때 `delay_use=4`에 900ms). 아래 실측 76. 커널을 안 바꿔도 루트 게이트의 동시 부하만으로 창이 닫힌
      적이 있다(HC-M0 첫 회, 2026-10-26 — 풀기 5.5초, `sda2`가 `/init`보다 50ms 먼저). 단독 재실행이 PASS(1300ms)이고 initrd
      크기가 같으면 부하다. 한 번 더 겪으면 `delay_use`를 5로 올리는 것을 본다.
      두 번째(2026-11-22, TK-M6의 루트 게이트 — 풀기 5.1초, `/init`이 `sda2`보다 66ms 늦음)에 5로 올렸다(`caa718d`). initrd가 128 MB로 커지며
      여유가 600~800ms로 얇아져 있었다. 지금 기다림은 단독 1900~2000ms · 게이트 부하 아래 1700ms. 풀기 시간이 지연과 같아지는 initrd 크기는
      약 145 MB(1 MB에 약 35ms) — initrd가 그만큼 커지면 다시 본다.

서브프로젝트 후보(패키지 매니저 · GPU 가속 · PD · SE 비목표)는 `HANDOFF.md`의 "다음 후보"에 있다. IPv6는 후보가
아니다(`docs/decisions/feedback_ipv4_only.md`). 여기는 그보다 작은 것과, 닫아 두어서 다시 열려면 근거가 필요한 결정이다. 끝난
서브프로젝트는 `docs/guides/completed.md`의 완료 표가 목록이다.

미룬 것.

- [ ] `git-delta`(SM 비목표 1) · `Ctrl+R`을 게이트가 치는 것(SM 비목표 2 — TUI라
      체인이 매달린다. 안 하는 쪽에 근거가 쌓여 있다).
- [ ] 무선의 남은 것(WL 비목표). Intel BE201과 `sc-a0-fm-c0`(커널 6.18이 받는 번호의
      firmware가 linux-firmware-20260916에 없다 — 커널을 올릴 때 같이 본다) · 보드별 변형
      firmware(ath11k `nfa765` · ath12k `ncm865`) · WPA-Enterprise · 실칩 판정(실기가 생기면).
- [ ] USB 무선 동글의 나머지. 층 A는 UW(2026-09-28), 층 B 다섯과 `RTL8XXXU`는 UB(2026-10-31)가 켰다.
      남은 것은 드라이버 작성자가 안 본 장치 목록(`RT2800USB_UNKNOWN` · `RTL8XXXU_UNTESTED`)과
      다른 계열(`rtl8187` · `zd1211rw` · `carl9170` · `ar5523` · `p54usb` · brcmfmac USB)이다 — 실제
      동글이 그 목록에 있을 때 켠다(UB design 비목표 2 · 5). 켜는 법은 UB와 같다: 부모 메뉴까지
      `-k`로 켜고 해소본에서 `=y`를 센 뒤 `firmware=` 줄에서 이름을 센다.
- [ ] 실기에서 LAN의 다른 컴퓨터가 게스트 포트에 붙는 것. 게이트는 SLIRP 안에서만
      판정한다(IN 비목표 3 · FW 비목표 3).
- [ ] net 검사 31의 간헐(TC-M2 루트 게이트 두 판, 셋 중 둘)의 진짜 원인. Task 5b가 set의 답을 기다리고 진단을 찍게 했고 그 뒤 4판 초록이다.
      다시 빨개지면 진단의 세 덩어리(마지막 화면 · `cat /config/tars.conf` · `reload of` 뒤 tars-init 줄)로 가린다 — 가설은 "set이 파일을 못
      바꿨거나 늦었다"(빨갰던 회차의 시리얼에 `reload of`만 있고 steer 줄이 없었다. 단독에서는 넷 중 영). GF-M1부터 그 회차의
      시리얼 로그가 `out/gate-logs/<시각>/TD-M2-<회차>/`에 남으니 진단 출력과 로그를 함께 본다.
- [ ] firewall 검사 18의 간헐(DR-M1 루트 게이트 셋 중 하나, 2026-10-29). `tars-config firewall allow 7072` 뒤 호스트가 붙었는데
      빈 값이고 열 번의 `read -t 5`가 timeout 없이 곧바로 끝났다(회차 35초 — 통과한 회차는 58초). 7072의 리스너는 `nc -l -p 7072` 한
      번짜리다. 읽히는 모양은 검사 8이 막힌 포트에 붙었을 때 SLIRP이 버린 SYN을 재전송하다가 allow로 포트가 열린 순간 닿아 `nc`가 그
      묵은 연결을 받고 끝난 것(실측 73이 "언제 다시 보내는지는 재지 않았다"고 남긴 자리). 혼자 3/3은 초록이었다. 고치는 길은 검사
      18이 검사 8이 건드린 적 없는 포트를 열어 보거나, 7072의 리스너를 다시 듣는 꼴로 두는 것. 다음에 빨개지면 그 회차 로그의
      `fwm2-tcp-7072` 줄 뒤 `/proc/net/tcp`를 먼저 본다 — DR-M1 plan의 결과 절에 분석이 있다.

HI가 남긴 것 둘은 2026-09-13에 사용자가 뺐다. "한글 기호 확장은 당분간
마일스톤에서 제거한다. 팥알입력기의 나머지 trait도 당분간 고려 대상 아님."
다시 집게 되면 `docs/specs/2026-08-31-tars-hangul-input-design.md`
의 비목표 절이 그 둘을 그대로 갖고 있다. 그중 `ESC라틴` trait은 2026-10-05에
사용자가 다시 집어 EL-M0이 했다(`esc_latin=on|off`, [[project_escape_latin]]).

렌더 쪽 — 미룬 것이고 근거가 있다. 부분 갱신은 Dirty Rows(DR-M0~M2, 2026-10-30)가 했다([[project_dirty_rows]]).

- [ ] 큰 kitty 이미지의 그리기 비용. 화면 가득한 이미지가 게이트에서 프레임을 9.6 → 69.7ms로
      늘린다(TG 실측 7). `image.draw`가 픽셀마다 64비트 나눗셈 둘로 원본 좌표를 구하는 것이
      원인으로 보이고, 줄마다 열 대응표를 한 번 만들면 줄일 자리다. DR 뒤로 이미지가 있는 패널은 매
      프레임 통째로 그리므로(design 결정 3) 이미지가 떠 있는 동안은 부분 갱신의 이득도 없다 — 다시 집을
      신호는 실기에서 이미지가 뜬 채 화면이 느린 것이다.

닫아 둔 결정들 — 다시 열려면 근거가 필요하다.

- [ ] 붙여넣기가 모드를 닫아야 하는가. CM-M2가 "안 닫는다"로 정했다.
- [ ] `w`가 줄을 넘어 다음 줄의 첫 단어로 가야 하는가. CN-M0이 "안 간다"로 정했다.
- [ ] `?`(아래로 검색). CN design 결정 4가 뺐다.
- [ ] 검색 결과의 실시간 갱신. CS design 결정 7이 "안 한다"로 정했다.
- [ ] init이 직접 포트를 듣는 것. IN 비목표 5 — 다시 열릴 조건은 "게스트가
      무엇을 서빙해야 하는지가 정해지는 것".
- [ ] 이미지 뷰어를 기본 이미지에 넣지 않는다(사용자 결정, 2026-10-03). Debian `chafa`(1.14.5)는 바이너리 190KB지만 재귀
      `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를 끈다 — RAM 위 initrd에 늘 얹기에는 크다. 필요한 사람은 패키지 관리자로
      설치한다. Homebrew `install.sh`는 root이면 멈추므로 non-root 사용자가 먼저고, 설치물은 디스크의 prefix
      (`/home/linuxbrew/.linuxbrew`)에 놓여야 하며 그것은 DI의 설치 디스크 위다. 뷰어가 셀 크기를 셈할 전제(`TIOCGWINSZ`의
      `ws_xpixel` · `ws_ypixel`)는 LE-M0(2026-10-27)이 채웠다. 다시 여는 자리는 "패키지 매니저" 서브프로젝트다.

## IP-M2가 남긴 것 (그대로 이월)

- `Ctrl+←`/`Shift+←`는 여전히 맨 `ESC [ D`로 샌다. TUI 앱이 생기면 그때.
- DECCKM(`ESC O` 분기)은 부팅 게이트가 영영 못 밟는다. `input_test`가
  `Context.cursor_keys`를 주입해 대신 본다.
- `keymap`에 comptime 앵커가 박혔다. 표 중간에 줄을 끼우면 컴파일이 막힌다.
  `KEY_Z`도 그 앵커 중 하나다.

## TR-M2가 남긴 것 (그대로 이월)

- `Terminal.ScrollViewport`의 이름이 `PageList.Scroll`과 다르다.
  `.bottom`·`.delta`이지 `.active`·`.delta_row`가 아니다. 그리고 `.pin`이
  아예 없다.
- 렌더가 PTY 분기 안에만 있었다. `needs_redraw`로 루프 끝에 뺐다.

## WY-M2 ~ WY-M6이 남긴 것 (Wayland 서버, 그대로 이월)

- SDL은 렌더러가 GL 창을 바라 창을 한 번 지웠다 다시 짓는다 — column이 한 번 깜빡인다. 첫 commit 뒤 한 바퀴 기다려 자리를 정하면 줄 수 있다.
- vsync SDL 창은 숨은 동안 frame `done`을 못 받아 swap에서 멈춘다 — 숨은 창의 `Cmd+Q`는 ping에 못 답해 SIGKILL이 된다.
- 커서 surface의 그림은 합성하지 않는다(terminal의 화살표 그대로, `set_cursor(NULL)`이면 숨김).
- `invalid_size`(버퍼가 buffer_scale의 배수가 아님)는 xml대로 모든 surface에 강제한다. SDL은 커서 surface에 `set_buffer_scale(S)`를 보낸다 —
  테마 커서 크기가 배율의 배수가 아니면 배율 2 화면에서 그 SDL 창이 끊긴다. 체인은 배율 1의 SDL만 본다. 실기 hidpi에서 SDL 창이 뜨면 볼 자리.
- SDL exclusive fullscreen(viewport 없음)은 `set_buffer_scale(mode.w / output_w)`를 보낸다 — 우리 `output_w`는 논리라 모드가 그 정수 배가
  아니면 `invalid_size`. 쓰는 클라이언트가 없다(viewporter는 결정 31로 안 낸다).
- 배율 2 화면의 bs 1 · bs 2 column 통째 프레임 시간을 같은 조건에서 맞댄 숫자는 없다(TCG에서 셸 다시 그리기 50~67 ms에 묻힌다).
- 클립보드 이어 쓰기(64 KiB 넘는 글, `Outgo`)는 체인이 안 탄다 — 판정 글은 9바이트. 1 MiB · 2초 한도와 writable 콜백은 코드로만 맞췄다.
- SDL 앱으로 실제 붙여넣기를 재지 않았다 — app pane의 `Cmd`는 `Super`로 가서 SDL의 `Ctrl+V`가 아니다(WY-M6 호환 모드). SDL은 파이프를 14 ms만
  기다린다 — 서버는 `receive`를 요청 처리기 안에서 쓰지만(`first=` 전부), TCG에서 바퀴가 길면 요청 처리 자체가 늦을 수 있다.
- `clipboard=pane` 범위의 Wayland 쪽(셸과 안 이음)은 게이트가 안 본다. 판 2의 `start_drag` → `cancelled`도 쓰는 클라이언트가 없어 런타임으로 안 봤다.
- 한글(WY-M5): 켠 창에서 조합 중 Backspace를 쥐면 자모 하나만 빠진다(먹은 키라 클라이언트가 반복을 모른다 — 셸은 반복마다 뺀다). 창이 조합 중에
  text_input을 끄면 그 조합은 다음 배치에서 말없이 버려진다. CapsLock 잠금이 켠 창에서는 뗄 때, 켜지 않은 창에서는 누를 때 뒤집힌다(값은 하나).
  `content_type`의 password · pin에서 조합을 끄지 않는다(받기만). 키보드 둘 · 포인터가 한 바퀴에 섞이면 첫 배치가 켜지지 않은 길로 갈 수 있다.
  SDL의 텍스트 입력은 저장소에 쓰는 앱이 없어 소스 사실로만 선다. 녹화 B(사람 녹화)는 아직.
- 호환 · damage(WY-M6): SDL이 호환 모드의 Ctrl+V로 붙이는지는 저장소에 SDL 붙여넣기 앱이 없어 소스 사실로만 선다. damage는 합집합 하나라 멀리 떨어진 작은
  damage 둘은 그 사이 전체를 옮긴다(목록은 TK-M1의 숫자를 보고). WY-M7의 popup · 장식이 창 자리를 가렸다 비키면 `damage_whole`을 세워야 한다.

## TK-M0 · TK-M1이 남긴 것 (툴킷, 그대로 이월)

- `/vendor/fonts/Pretendard-Regular.otf`가 로그인 사용자 uid로 읽히는지는 체인(root 셸)이 못 본다 — 설치된 기계에서 `tars-tk-demo`를 사용자로 띄워 본다.
- `toolkit` 체인 판정 2의 대각선 중간값은 z2d v0.13.2에서 한 칸이다 — z2d 판을 올리면 모서리 12 × 12 상자의 중간값 수로 바꾼다.
- 저장소에 `THIRD_PARTY` 고지 파일이 없다 — z2d(MPL-2.0)는 `toolkit/build.zig.zon` 주석, Pretendard(OFL)는 `toolkit/vendor/fonts/README`가 고지 자리다.
  배포물(ISO)에 고지 묶음을 만드는 일은 릴리스 절차(`project_release`)에서 본다.
- 불투명도는 누적 알파 곱이라 자식이 겹치는 그룹에서는 겹친 자리가 두 번 섞인다(TK-M1 확정 4). 정확한 그룹 불투명도는 `Painter`의 작은 임시 판 + `compositeOver`
  장치로 더한다 — 필요해지는 위젯(겹친 카드의 사라짐 등)이 생길 때.
- 창 층의 `Canvas.wrap`이 z2d `ImageSurface`의 공개 필드를 직접 채운다 — z2d 판을 올리면 그 모양을 다시 본다(호스트 검사의 "부분 = 통째"가 잡는다).

## TK-M2가 남긴 것 (툴킷, 그대로 이월)

- 스크롤 한 프레임(리스트 통째)이 TCG에서 16 ms를 자주 넘는다(416 × 752 4.7~27.7 ms, 1240 폭 중앙 26 ms, 네이티브 0.45 ms — `measurements.md` 109). R-KIT-4의
  남은 몫이다. 후보: (가) 루트와 컨테이너가 같은 `TK_BG`를 두 번 칠한다 — 하나로(네이티브 454 → 348 µs), (나) 버퍼 안 복사 스크롤(네이티브 57 µs — 버퍼 나이 2라
  버퍼마다 "그린 오프셋"이 필요), (다) 더티가 판 대부분이면 임시 판 대신 판에 바로. 게스트/네이티브 비가 10~60배로 흔들리는 까닭은 모른다. 실기에서 먼저 잰다.
- 부드러운 스크롤(오프셋 애니메이션)과 터치패드의 소수 `dy`는 없다 — 휠은 칸당 3행, `dy`는 반올림.
- 서버의 창마다 `wl> blit` 줄 상한 16이 체인에서 스크롤 프레임의 blit을 못 보게 한다(강조 애니메이션이 먼저 다 쓴다) — 측정은 순서를 바꾼 임시 스크립트로 했다.
- 리스트의 데이터는 고정이다 — count가 바뀔 때 `selected` · `offset`을 자르는 자리와 안정 선택(R-FM-6)은 TK-M3.
- 키 뗌은 뷰에 가지 않는다, 포인터 드래그(막대 끌기)도 없다. 일반 포커스 링 토큰은 버튼 · 텍스트 필드가 올 때.
- 글자 키의 문자 표(xkb 없이 evdev 코드 → 문자)는 TK-M4의 텍스트 필드가 만든다 — 서버 키맵이 us 고정인 동안만 맞는 길이다(design 결정 13).
- 같은 작업 트리에서 체인 둘을 동시에 돌리면 `terminal/.zig-cache` 빌드가 경합한다(`libhighway.a`를 못 엶) — 체인은 하나씩.

## TK-M3가 남긴 것 (툴킷 · `tars-files`, 그대로 이월)

- 큰 디렉터리의 병합 비용: 조각마다 O(n) 병합이라 10만 항목에서 게스트 1.2초(끝 1.67초의 72%, `measurements.md` 110). 후보 — idle 한 번에 getdents 여러 번,
  첫 화면 뒤에는 모았다가 끝에 한 번 정렬 · 병합, 정렬된 덩어리 여럿을 k-way로.
- (끝남, TK-M6) 미리보기를 레이어 셋으로 나눠 `↓`의 더티가 창 전체에서 0,0,616,360으로 줄었다.
- getdents 한 번이 막히는 파일 시스템(네트워크 · 멈춘 장치)에서는 메인 루프가 멈춘다 — 스레드 읽기는 그때.
- 자동 갱신(inotify) · 손 키 갱신 · 숨김 파일 토글 · 부모 경로로 올라가는 키 · 자동 따라가기(선택만으로 오른쪽 열)는 없다. 링크는 따라가 종류만 정한다(표시 없음).
- 가로 스크롤 애니메이션 없음. 열 폭 끌기 · 분할 뷰 끌기 없음. 열 풀의 깊이 32를 넘는 `→`는 거절한다.
- 넘치는 이름은 열의 masks가 자르고 `›`와 겹칠 수 있다 — 가운데 생략(R-TXT-1)은 TK-M4.
- (끝남, TK-M4) 가운데 생략과 `ColumnView.setColumns`는 TK-M4가 넣었다.

## TK-M4가 남긴 것 (툴킷 · `tars-files`, 그대로 이월)

- 표시: NFD 이름의 정렬은 바이트 그대로라 같은 이름의 NFC/NFD가 다른 자리에 선다. 결합 표시는 U+0300~036F만 앞 글자에 붙고 옛 자모 · 한자는 `□`다(Pretendard에 없다 —
  글꼴 대체 사슬이 없다). 줄 나누기(`layout.wrap`)의 소비자는 TK-M6의 텍스트 미리보기다. 잘못된 바이트는 `?`로 보인다.
- 편집: 캐럿은 깜빡이지 않는다(idle commit 0과 덤프 판정 — 깜빡임은 창 층의 "다음 기한" 타이머와 "입력 없이 N초 뒤 멈춤"을 함께 넣을 때). 붙여넣기는 동기(1초 poll),
  복사 상한 4096. 필드 클릭은 캐럿만(끌어 선택 · 두 번 클릭 없음 — 포인터 드래그가 툴킷에 없다). 되돌리기는 한 단계.
- 서버의 "enable에서 앱 조합을 버림"(xml: enable resets state)이 없다 — 한 창에 필드가 둘이 되면 disable과 다음 키 배치 사이에 다른 필드가 enable할 때 옛 음절이
  이어진다. 지금은 바 하나를 모드가 나눠 써서 안 생긴다.
- 경로 바의 오류는 로그 줄뿐이다(빨강 토큰 없음 — 사용자는 바가 안 닫히는 것으로만 안다). 자동 완성 없음. `tk> field text=` 등 줄은 256바이트를 넘으면 안 찍힌다.
- 검색: 점수 매기기가 글자마다 동기다 — 20만 항목의 첫 글자는 게스트에서 초 단위로 짐작된다(idle 조각으로 나누거나 글자 사이에 미루기). 결과 리스트가 글자마다 통째
  다시 그려진다(게스트 10~33 ms). 초성 검색 · 결과 미리보기 · 결과 클릭 · 필터의 fuzzy 없음. 걷기 뿌리는 열 0 — 디스크가 붙은 기계의 `/`는 상한(20만 · 10초)에
  닿는다(실기에서 잰다).
- 필터는 포커스 열 하나만이고, 바를 닫으면 필터가 걸린 열임을 알리는 표시가 없다(TK-M6의 상태 표시 자리).
- `sendkey` → preedit 그림까지의 지연은 로그에 시각이 없어 못 쟀다. 서버의 창마다 `wl> blit` 줄 상한 16이 여기서도 측정을 막는다.
- (끝남, TK-M6) 단축키의 정의는 메뉴 모델 하나(`toolkit/src/files/menus.zig`)다 — action을 responder chain이 받는다.

## TK-M5가 남긴 것 (서버 쪽 메뉴 바, 그대로 이월)

- 한 read 배치 안에서 여는 chord(`Cmd+Shift+/`) 뒤에 온 키는 메뉴가 아니라 창으로 간다(`readKeysApp`이 배치를 다 돈 뒤 `runPanes`가 연다) — 사람 손으로는 드물다.
- 글자로 항목 건너뛰기 · 누름-끌기-뗌으로 고르기 · `↓`의 자동 반복 · 메뉴 안 휠 스크롤 · 제목 위로 포인터를 옮겨 메뉴 바꾸기(클릭해야 옮긴다)가 없다.
- 드롭다운이 화면 아래에서 잘리면 그 칸은 보이지도 고를 수도 없다(스크롤 없음 — 메뉴당 32항목 × 16 = 512 px라 1280 × 800에서는 안 생긴다).
- 단축키 글은 ASCII(`Cmd+O`)다. unifont에 ⌘ ⇧ ⌥ ⌃가 있다 — 바꾸면 폭과 판정 좌표가 달라진다.
- 열고 · 닫고 · 옮길 때 통째 프레임(TCG 22~25 ms) — 밑 픽셀 저장으로 줄일 수 있다(`measurements.md` 113).
- 프로토콜에 메뉴가 열리고 닫힌다는 사건(`opened`/`closed`)이 없다 — 앱이 열릴 때 모델을 고칠 길이 없고, 모델을 다시 commit하면 열린 메뉴가 닫힌다(판 3 거리).
- 바의 앱 이름은 app_id 우선 · 24칸, title/app_id는 64바이트. title 변화는 바에 안 보인다(title은 WY-M7의 장식이 쓴다).
- `menu> draw` 줄은 갈래마다 처음 여덟 — 강조만 바뀌는 프레임의 시간은 따로 못 쟀다. hidpi 7b2의 음성 시험(다시 늘리기를 뺀 판)은 안 돌렸다.
- (끝남, TK-M6) 툴킷이 판 2로 bind해 모델을 보낸다 — `tars-files`의 바에 File · Edit · View · Go.

## TK-M6이 남긴 것 (메뉴 모델 · 미리보기, 그대로 이월)

- 메뉴 활성 비트는 입력(수정키 아닌 키 · 버튼 누름 · 포커스 · menu) 뒤에만 다시 셈한다 — idle(로딩 끝)과 ime에서는 안 셈해, 첫 열 로딩 전에 본 "복사"가 다음 키까지
  비활성으로 남을 수 있다. 서버에 `opened` 이벤트가 없어 열 때 셈하는 꼴은 프로토콜 판 3 거리다.
- 모델 없는 `Root`의 기본 표는 chain의 누군가가 그 action을 알 때만 단축키다. 항목의 글은 고정(필드 포커스에 따라 "복사"/"경로 복사"로 안 바꾼다).
- 메뉴로 고른 동작의 클립보드 serial은 마지막 키의 것이다(`activated`에 serial이 없다 — 서버는 serial을 안 본다).
- 디코드 한 장은 쪼갤 수 없다 — 상한 안의 큰 JPEG는 메인 루프를 그만큼 막는다. 게스트의 큰 그림 디코드 · 박스 축소 시간을 아직 못 쟀다(체인 그림은 맞춤 안).
  스레드나 R-FM-7의 격리 프로세스가 같은 자리다(design 결정 17 — 원칙만, 구현 없음, 퍼징 안 함).
- 텍스트 미리보기는 앞 16 KiB · UTF-8만 · 스크롤 없음(판 높이에서 끊김), 인코딩 판정 없음. 디렉터리 미리보기는 아이콘뿐(항목 수 없음), 자동 따라가기 없음.
- JPEG의 EXIF 방향 무시, CMYK JPEG의 색은 안 봤다, 뒤가 잘린 JPEG는 stb가 남은 칸을 채워 그림으로 보인다. 그림은 확대하지 않는다.
- 미리보기는 같은 경로의 파일이 바뀌어도 다시 읽지 않는다(열쇠가 경로 · 배율). 디렉터리 로딩 중에는 미리보기를 미룬다.
- 요구사항 가운데 TK가 안 채운 것: R-KIT-3의 레이블 · 버튼 · 스크롤 뷰 위젯, R-ARCH-2의 임의 경로 `fill_path` · 일반 `transform`, R-CG-1의 선 · 그림자, R-TKW-3의
  앱 안 팝업 레이어, R-TXT-4의 `shape` 자리, R-FM-2의 Strata 키 문서 대조(저장소에 없다).
- 녹화 C(사람 녹화)는 남았다 — "선택 강조가 짧게 움직인다"만 덤프 하나로 안 보이고 나머지 장면은 toolkit 체인 판정 15~34가 돈다.

## CR-M0 · CR-M1이 남긴 것 (Chromium · 거두기의 고정, 그대로 이월)

- (풀림, WY-M7 `9b945c7` · `f0f3524`) Chromium이 주소창에 글자를 치면 죽던 것(`wl_subcompositor` 없음)과 안 보이던 문맥 메뉴 · 앱 메뉴(`xdg_popup`).
- 묶음 browser 294 MiB: gpu · media와 겹친 파일 지우기(→ 228)와 noto Serif CJK 빼기(−40)는 안 했다 — 새 "묶음 사이 의존"을 init · `make_iso.sh` · build에 들여야 한다.
  기본 판 ISO에는 못 들어간다(2 GiB). 배포는 web 판(사용자 2026-11-22 — browser를 실은 ISO는 `web` 식별자로 따로 짓고 lang-native를 뺀다, `project_release` 절차 3).
  셈으로 약 1.87 GiB — 첫 web 판을 낼 때 실제 크기와 설치 smoke를 본다. 묶음 수 15 / init의 `MAX = 16`.
- 판올림은 넷을 함께: `devlayer/snapshot`의 시각과 InRelease sha256 셋 · chromium 판 · `libc6-dev`와 개발 컨테이너 이미지(initrd의 glibc) · pgdg 의존 넷. Debian chromium은
  주 1회쯤 보안 판이 온다. vendor-repo(pgdg)는 snapshot 밖이라 재빌드로 같은 판 문자열의 짝이 또 바뀔 수 있다.
- setuid: base 묶음이 이미 4755 일곱(`mount` · `umount` · `passwd` · `chfn` · `chsh` · `gpasswd` · `ssh-keysign`)과 setgid 셋을 싣고, 묶음 squashfs는 `nosuid`로 붙지만 `/usr`
  overlay에 `nosuid`가 없어 살아 있다(CR design 확인 13). browser에는 `dbus-daemon-launch-helper` · `unix_chkpwd`가 더 온다. harvest가 setuid를 지울지는 CR 밖의 결정이다.
- `/etc/pam.d/common-session`이 `pam_systemd.so` 줄을 단 채 browser 묶음으로 `/etc`에 간다(지금 initrd의 `pam.d/sudo`는 그 파일을 include하지 않아 해가 없다).
- `/dev/shm`이 없다(POSIX shm의 관행 — Chromium은 memfd라 무관, CR에서 뺐다). dbus 없음(stderr에 경고 반복). 로캘은 `C.utf8`뿐(한국어 UI `chromium-l10n` 안 실음).
- Chromium은 `--disable-gpu`로 뜬다 — gpu 묶음의 `libegl1`로 llvmpipe 합성을 할지는 안 쟀다. 휠 · 스크롤 중 blit 비용도 안 쟀다.
- root 화면 셸(설정 디스크에 `user=` 없음)에서는 Chromium이 안 뜬다(sandbox — 문이 안내한다). 창이 둘일 때 text-input이 첫 창으로 간다던 것은 표기뿐이었다(WY 결정 55 — WY-M7이 고침).
- (풀림, WY 결정 54) 호환 모드에서 Cmd 키 자체가 evdev 125로 가서 페이지가 `key=Meta` keydown을 보던 것 — 호환 창에는 125 · 126을 안 보낸다.
- 루트 게이트의 lane: 게스트 메모리가 큰 체인(devtools · browser)을 한 lane에 묶었다 — 그 lane이 가장 길어지면 lane에 무게를 주는 스케줄러로 바꾼다.
- `tars-docs`는 shellcheck 대상이 아니다(`tars-browser`만 넣었다).

## WY-M7이 남긴 것 (subsurface · popup, 그대로 이월)

- subsurface 합성의 섞기는 1:1 길(k == bs)이 아니면 픽셀마다 나눗셈이다(`measurements.md` 116의 0.4 µs/px) — 늘린 창(k > 1)이나 bs ≠ k인 자식. 지금 쓰는 클라이언트에는 없다.
- subsurface가 창 사각형 밖으로 나가면 그 자식의 damage는 통째로 간다. 입력 영역의 `subtract`는 받기만 한다(넓게 잡는다).
- 안 잰 것(plan 실측 2 · 4 · 5 · 6): Chromium 배율 2 bubble의 물리 1:1, 자식에 `wl_surface.enter`를 안 보낼 때의 차이, 부모 크기 바뀜(`Cmd+R`)에 닫힌 popup을 Chromium이
  다시 여는지, SDL 앱의 Cmd 조합.
- popup이 보이는 동안 프레임은 늘 통째다(26 ~ 54 ms, TCG — `measurements.md` 117). 메뉴를 연 채 셸이 바쁘게 출력하면 그 프레임마다 통째다. 부분 프레임으로 가려면 popup 밑을
  다시 칠하지 않은 clip(화살표를 되돌린 자리 등)에서 그림자가 두 번 섞이지 않게 해야 한다.
- 배율 2에서 셸 pane 위로 나간 popup은 그림자에서 늘린 그림(2 × 2 블록)이다 — 물리로 다시 섞는 것은 창 사각형 안뿐이라 bs 2 popup의 그 부분은 흐리다.
- 배율 2의 논리 화면(640 × 400)은 Chromium 메뉴에 작다 — 문맥 메뉴가 resize_y로 줄어 스크롤 화살표가 붙는다. 그리고 그 pane(논리 296폭)은 Chromium의
  `set_min_size(500)`보다 좁아 창이 가운데로 잘린다(서버는 min_size를 받기만 한다).
- 화면 밖 column으로 밀린 창(포커스는 그대로)의 popup은 서버가 안 닫는다 — 결정 53의 "숨음"은 포커스 이동으로만 잡는다(strip scroll로 포커스 창이 밀리는 길은 지금 없다).
- popup에 키보드 포커스를 안 옮긴다(결정 53) — grab하고 키를 popup surface로 기대하는 클라이언트(GTK 메뉴 등)는 키가 부모로 간다. Chromium은 부모로 받는다.
- `xdg_popup.destroy`는 자식 popup이 살아 있으면(서버가 이미 닫은 것이라도) `not_the_topmost_popup`이다(xml 그대로) — 닫힌 자식보다 부모를 먼저 지우는 클라이언트는 죽는다.
  Chromium은 위에서부터 지운다(체인 · 시험 VM에서 `wl> gone pid=` 0).
- `wl> popup` 줄은 창마다 64줄까지다 — Chromium은 단추 위에 머물 때마다 툴팁 popup을 만든다. 오래 쓰면 줄이 끊긴다(상한이 그 뜻).
- 서버 쪽 장식(포커스 테두리 · 빈 칸 이름)은 하지 않았다(결정 55) — Chromium의 탭 줄이 그 자리다.

## CR-M2가 남긴 것 (앱 풀스크린 · browser 체인의 장면, 그대로 이월)

- 클라이언트가 청한 나오기(`unset_fullscreen`)가 갈 곳이 없어 실패하면(셸 workspace 없음 · strip에 slot 여덟 · 너무 좁음) configure로 답하지 않는다 — 창은 fullscreen
  그대로다. xdg-shell은 답을 바란다(지금 상태의 configure를 한 번 더 보내면 된다).
- 옮긴 첫 프레임은 옛 버퍼를 새 자리 가운데에 그린다 — Chromium이 새 크기를 그릴 때까지 0.15 ~ 0.4초(체인 부하에서 1.1초). 검정 한 프레임으로 숨길지는 정하지 않았다.
- 크기가 바뀌어 닫힌 popup(`done why=resize`)을 Chromium은 다시 열지 않는다 — 사람이 다시 누른다(WY 결정 53 그대로).
- 실측 줄 `wl> fullscreen frame us=` · `commit ms=`는 남겨 두었다(판정은 안 쓴다).
- 처음부터 자기 workspace로 뜬 창(둠)은 `Cmd+Ctrl+F`로 column이 되지 않는다(home이 없다 — WY 결정 57).
- HTTPS는 게이트 밖이다(사람 녹화 D) — 체인의 망은 `restrict=on` SLIRP의 http stub 하나다. Chromium의 미리 연결(요청 줄 없는 연결)이 stub에 한 번 온다(로그에 빈 줄).
- browser 체인은 부팅 하나에 판정 열셋이다 — 앞 장면이 깨지면 뒤가 안 돈다. 게이트의 가장 긴 lane(ISO + 큰 메모리)에 있어 더한 초가 게이트 끝을 그대로 민다.
- 배율 2: column의 Chromium(논리 296폭)은 여전히 `set_min_size(500)`보다 좁다 — `Cmd+Ctrl+F`의 자기 workspace(640 × 400)에서는 된다. 메뉴는 여전히 작다(resize_y).
- 녹화 D는 아직 안 찍었다(사람) — 따라 칠 키 열 줄은 CR-M2 plan의 결과 절.
