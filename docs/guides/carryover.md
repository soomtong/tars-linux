# 이월 숙제

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.


개발 도구 층 TP-M12(2026-11-08, AI 도구 설치 확인)가 남긴 것.

- [ ] 컨테이너 실행 환경 — 다음 서브프로젝트 후보(사용자 2026-11-08: "컨테이너 환경을 활성화하는 것을 고려해야 됩니다. 개발도구 중에 도커를
      쓰는 경우가 종종 있죠"). 계기: codex의 `codex sandbox linux`가 `bwrap: Creating new namespace failed, likely because the kernel does not
      support user namespaces.`로 rc 1(TP-M12 plan 확인 2) — claude code의 샌드박스도 bwrap이다. user namespace 하나만 켜면 AI 샌드박스는 서지만
      Docker는 여전히 안 서므로 따로 하지 않고 이 서브프로젝트에 묶는다(사용자가 추천에 동의). `kernel/.config`의 그날 상태:
      꺼짐 — `CONFIG_USER_NS` · `CGROUPS` · `UTS_NS` · `PID_NS` · `TIME_NS` · `VETH` · `BRIDGE` · `NF_NAT` · `IP_NF_IPTABLES` · `BPF_SYSCALL` · `SECCOMP` ·
      `POSIX_MQUEUE`, 켜짐 — `IPC_NS` · `NET_NS` · `NETFILTER` · `NF_TABLES` · `OVERLAY_FS` · `KEYS`. rootful dockerd는 USER_NS 없이 서고(cgroups ·
      namespace 전부 · veth/bridge/NAT · seccomp 기본 프로필이 필요), rootless Docker · Podman · bwrap은 USER_NS가 핵심이다. 정할 것: rootful
      dockerd(init 서비스, root 데몬)인가 rootless Podman인가, 런타임 바이너리를 어디서(개발 도구 층의 묶음 · 사용자 설치), 커널 크기 · 부팅
      시간 · 공격 면(USER_NS)의 대가, `CONFIG_MODULES`가 없는 TARS라 전부 내장. 방화벽(FW)의 nftables와 Docker의 iptables(nft 백엔드) 공존.

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
      정할 것: (1) Powerline을 렌더러가 직접 그리기(폰트가 필요 없고 문턱값과 충돌하지 않는다 — 프롬프트 체감은 대부분 여기서 난다), (2) 아이콘
      fallback 폰트 — 먼저 `CozetteVector.ttf`에 중간값 0%가 되는 scale이 있는지 잰다, (3) 폭 규칙 — 1칸 고정(8px 아이콘)인가 ghostty처럼 "다음
      칸이 공백이면 2칸"인가(렌더러 계약이 바뀌므로 design 결정감), (4) 폰트를 둘 싣게 되면 [[project_font_selection]]의 "고칠 자리 열"과
      `terminal/vendor/fonts/README` · initrd 크기.

개발 도구 층 TP-M11 뒤 조사(2026-11-08)가 남긴 것.

- [ ] 묶음 사이 같은 파일 지우기. `devlayer/build.sh`의 묶음끼리 대조(TP-M2 plan 결정 E)는 내용이 다르면 멈추고 같으면 `shared`로 세기만 한다 —
      같은 파일이 두 sqfs에 다 들어간다. base와 겹친 양(거두기 tar 크기, 풀린 것 → tar째 zstd -15): editor 108 → 28MiB(emacs가 끈 gcc 쪽), server
      93 → 22MiB(perl 57MiB — postgres · mysql의 의존, base와 같은 판 · 바이트), lang-script 24 → 6, media 20 → 6, util 18 → 5, docs 10 → 2. 합 약
      270MiB → 69MiB(squashfs는 블록마다라 실제 ISO 감소는 조금 더 클 것). 고치는 길: 나중 묶음에서 앞 묶음과 같은 파일을 지운다(verify.sh가
      initrd와 겹친 것을 지우는 것과 같은 일). 근거는 묶음을 다 함께 깔고(비목표 6) 판이 다르면 안 얹는 것(결정 13). 정할 것: 지운 묶음이 앞
      묶음에 기대게 되므로 base가 안 얹힌 부팅에서 나머지를 어떻게 할지. AI 도구를 싣지 않기로 해(사용자 2026-11-08) 지금은 자리가 급하지 않다 —
      ISO 2GiB에 다시 닿으면 꺼낸다.
      libicu는 줄일 수 없다: Debian `libicu76`(36MiB, `libicudata` 31MiB)은 postgres · initdb의 NEEDED, mysql의 `/usr/lib/mysql/private` ICU 77
      (51MiB)은 mysqld의 NEEDED — 둘은 서로 다른 판이고 묶음 사이 중복도 아니다. 데이터를 깎으려면 소스 빌드(비목표 7).

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
- [ ] `/sys/class/dmi`가 없다(`DMIID` 꺼짐) — 기종 이름을 사람이 확인할 길이 없었다. 진단 때 쓸모가 있다.
- [ ] 게스트에 `ping`이 없다(Debian `iputils-ping`). 실기에서 연결 확인을 `curl`로 했다.

MI-M0(2026-11-03)이 남긴 것.

- [ ] 공식 `mise.run`은 512MB 기계에서 굳는다 — `mktemp -d`(tmpfs `/tmp`)에 tarball 약 60MB와 푼 `mise` 172MB를 함께 두고, RAM에
      풀린 initrd 약 280MB와 합쳐 넘친다(MI 실측 6). Homebrew도 1GiB를 요구하므로(PM 실측 4) 고치지 않았다. 작은 RAM 기계가
      요구하면 사용자 환경의 `TMPDIR`을 디스크(`~/.cache/tmp` 등)로 두는 길이 있다 — 모든 프로그램의 임시 자리가 바뀌는 일이다.

PM(2026-11-03)이 남긴 것.

- [ ] 커널에 Landlock(`CONFIG_SECURITY_LANDLOCK`)이 없다 — Homebrew의 Linux sandbox가 꺼지고 `brew install`마다 `Sandbox
      unavailable … without sandboxing!` 경고, `brew doctor` 경고 하나(PM M1 실측 4). 설치는 막지 않는다. 켜려면 커널 `.config`와
      `lsm=` 순서를 함께 본다.
- [ ] TARS 자체 패키지 매니저는 나중에 다시 논의한다 — 당분간 Homebrew를 쓴다(사용자 결정, 2026-11-03). 그날 정리한 것:
      - 남의 것 중에 완벽히 맞는 것은 없었다. mise · aqua(미리 빌드된 CLI 바이너리, sudo · ruby 없음), micromamba · pixi
        (conda-forge, `~` 아래), Nix(범위 최대 — `/nix`를 디스크에 · daemon · 평가 메모리), 배포판 매니저(apt · xbps — "루트를
        디스크로"가 앞선다).
      - 자체로 만들면 어려운 것은 도구가 아니라 패키지의 출처다. 추천은 Debian trixie `.deb`를 런타임에 받는 것(유저랜드와 같은
        glibc · libstdc++ ABI, `InRelease` 서명, 빌드 서버 불필요 — 빌드 때 Dockerfile + `make_initrd.sh`가 이미 하는 일).
      - design에서 정할 것: 설치 자리(overlayfs로 initrd `/usr` 위에 디스크 층 vs `/home` 아래 prefix), initrd에 있는 패키지를
        "설치됨"으로 보는 목록과 TARS 갱신 때의 어긋남, 설치 권한(root · sudo), `Depends`를 어디까지 따르나, `Packages` 색인의
        RAM 예산. 접두사 후보 `TP`(TARS Package, 미사용).
- [x] mise 지원 — 서브프로젝트 MI로 열었다(2026-11-03, `docs/specs/2026-11-03-tars-mise-design.md`). initrd에는 안 싣는다(176MB).
- [ ] 라이브러리는 libstdc++만 Debian 모양(실체 + SONAME 링크)이다(PM 결정 10). 다른 바깥 프로그램이 다른 `.so`의 이름에서
      버전을 읽으면 그때 같은 판정을 한다.

HP-M1(2026-11-02)이 남긴 것.

- [ ] 부팅 뒤 꽂은 USB 헤드셋 · 사운드 카드의 노드는 root 0600 그대로다 — init의 audio 일꾼이 부팅에 한 번 `/dev/snd/*`를
      `root:audio 660`으로 바꿀 뿐이고 init에는 uevent가 없다. 실기에서 거슬리면 terminal의 uevent 길(포인터 · 키보드가 쓰는 것)에
      `SUBSYSTEM=sound`를 얹거나 init에 작은 uevent 듣기를 둔다.
- [ ] `ping`이 initrd에 없다. 넣으면 사용자는 `ping_group_range`(커널 기본 `1 0`)에 막힌다 — Debian 기본(`0 2147483647`)을
      init이 쓴다.
- [ ] 화면 셸의 히스토리 자리(fish `~/.local/share/fish`)와 zoxide DB가 홈에 생기는지 게이트가 못 봤다(HP 실측 11).

HP-M2(2026-11-03)가 남긴 것.

- [ ] hostname이 없다 — 커널 기본값 `(none)`이다. sudo의 `unable to resolve host (none)`은 sudoers `!fqdn`으로 껐지만 git
      신원은 여전히 `<이름>@(none)`이고 프롬프트도 `(none)`이다. 이름을 `tars.conf`의 키로 둘지(`hostname=`)는 그 쓰임이 생길 때.
- [ ] sudo의 timestamp가 tty 단위 15분(기본값)이다. 화면의 패널마다 따로 묻는다 — 거슬리면 sudoers `timestamp_type=global`.
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
      내려가면 그 신호다(지금 `delay_use=4`에 900ms). 아래 실측 76. 커널을 안 바꿔도 루트 게이트의 동시 부하만으로 창이 닫힌
      적이 있다(HC-M0 첫 회, 2026-10-26 — 풀기 5.5초, `sda2`가 `/init`보다 50ms 먼저). 단독 재실행이 PASS(1300ms)이고 initrd
      크기가 같으면 부하다. 한 번 더 겪으면 `delay_use`를 5로 올리는 것을 본다.

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
