# CR-M1 — snapshot 고정 · 묶음 `browser` · `tars-browser` · 체인 `browser`

Date: 2026-11-22
Design: `docs/specs/2026-11-22-tars-chromium-design.md`(확인 1~13, 결정 1~9, milestone 표 CR-M1), 요구사항 R-CR-1~5, 결정 8
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `cr-m1`, 세션 scratchpad `cr1/research.md` — HEAD `ea8b8f4`, 작업 사본에서 거두고 구워 QEMU로 띄움)

- 저장소 전체의 문제가 먼저 있다: 2026-11-21의 Debian point release로 manifest의 debian 줄 52개 가운데 `libc6-dev=2.41-12+deb13u4` · `patch=2.8-2`가 live 미러에서
  사라졌다 — 캐시 없는 기계의 `make dev-layers`는 오늘 base에서 깨진다. 전에도 같은 일이 있었고(TP-M12 · TP-M3 · TP-M10의 기록) 매번 "버전을 낼 때 올린다"로 넘겼다.
- 지금의 harvest 그대로는 browser가 verify에서 멈춘다: (가) live의 libc6 · libssl `+deb13u5`가 initrd(`+deb13u4`)와 바이트가 다르다, (나) chromium → dbus-user-session →
  systemd가 끌려와 `/dev/null` · `/proc` · `/etc/environment`로 가는 링크 7개가 끊긴다, (다) systemd의 `libsystemd-core`가 RUNPATH 없이 `libsystemd-shared`를 NEEDED한다.
- `snapshot.debian.org`의 한 시각(20261121T000000Z — point release 직전)으로 sources를 바꾸면: `apt-get update` 10초 · Release 서명은 slim의 keyring으로 그대로 검증,
  사라진 둘이 있고, chromium 156.0.8078.79-1~deb13u1 · fonts-noto-cjk를 1분 44초에 받는다. security · updates의 Release는 약 1주로 만료돼 `check-valid-until=no`가
  필요하다(만료만 안 보고 서명은 본다). browser에만 snapshot을 쓰는 길은 성립하지 않는다 — 다른 묶음이 live면 같은 의존(freetype)의 판이 갈라져 묶음끼리 대조에 걸린다.
- snapshot + systemd 넷 skip + 빼기 규칙 셋으로 거둔 browser: `verify> browser: differs=0 dangling=0 unresolved=0`, needed-ignore 줄은 하나도 필요 없다.
  postinst 캐시(gschemas · gdk-pixbuf · gio · mime · 아이콘)는 설치 전후 비교가 싣는다. systemd postinst가 만든 `/etc/machine-id`가 실릴 뻔했다(모든 TARS에 같은 값).
- `harvest.sh` · `harvest-skip.tsv`를 고치면 모든 debian 묶음의 harvest 캐시 해시가 바뀐다 — 전부 다시 거둔다.
- 크기: `build> browser: files=2811 unpacked=740MiB zstd15=294MiB shared=4454 deduped=763`. `deduped`는 base와 같은 것만 지운다 — gpu의 libLLVM(124 MiB) 등은 browser에
  또 실린다(gpu · media와 겹친 것까지 지우면 228 MiB, noto Serif를 빼면 188). 기본 ISO(1.99 GB)에는 못 들어간다(파일당 2 GiB).
- 묶음이 직접 싣는 실행 파일의 선례는 `devlayer/files/<묶음>/usr/local/bin/`(`tars-docs`). hook은 upstream 줄에만 붙는다.
- 게스트 실측(`-m 2048`, 설정 디스크 `user=tars`, 홈 디스크에 base · gpu · media · browser): `overlay /usr from 4 layers in 45ms`, 화면 셸에서 시제품 `tars-browser
  file://…` → 콜드 22초에 `wl> commit id=1 buf=636x772`, `menu> bar id=1 name=chromium-browser titles=-`, 페이지 좌표 색 정확, 한글 · 한자가 noto-cjk로 그려짐.
  렌더러 `Seccomp: 2 NoNewPrivs: 1`에 브라우저와 다른 user · pid · net ns. `Cmd+Q` → `wl> close` · `ping` · `unmap` · `gone`(kill 없음), 남는 프로세스 0. used 539 MiB.
  root로는 Chromium이 스스로 끝난다(`Running as root without --no-sandbox is not supported`).
- `/dev/shm`: CR-M0의 "없어서 `/tmp`를 쓴다"는 틀린 읽기였다. `/tmp/org.chromium.Chromium.*`은 ProcessSingleton 소켓 자리이고 공유 메모리는 memfd다 — `/dev/shm`을
  붙여도 Chromium은 그 안에 아무것도 안 만든다.
- 체인의 틀: 게스트 메모리 기본 512(`gate_lib.sh`), monitor 포트 다음 번호 45510, `CHAINS` 36, 진입 검사 셋(BUILD_STEPS · 파이프 끝 `grep -q` · `-nic none`), 묶음 상한
  `MAX = 16`(지금 14 + browser = 15). display 체인 부팅 3이 `user=` 설정 디스크 + 홈 디스크의 묶음이라는 같은 모양이다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `cr-m1`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 거두기의 고정과 묶음: 할 일 1~4.
- 단계 B — 문 · 체인 · 문서: 할 일 5~8. 루트 게이트는 B 뒤 한 번(A는 묶음을 쓰는 체인들로 확인).

## 착수 전에 확정한 것

1. snapshot을 저장소 전체(모든 debian 줄)에 쓴다. 시각은 한 줄 파일 `devlayer/snapshot`(지금 `20261121T000000Z`, 까닭은 주석 대신 이 plan과 `lessons.md`에 — 파일은 값만)에
   두고 harvest 캐시 해시에 넣는다. Makefile 변수로 덮어쓸 수 있다. sources는 `deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/<시각>/ trixie main` ·
   `… trixie-updates main` · `…/debian-security/<시각>/ trixie-security main`, slim의 `debian.sources`는 지운다. vendor-repo 넷(`repos.tsv`)은 그대로.
2. 규칙: snapshot 시각 · `libc6-dev` 줄 · 개발 컨테이너 이미지(initrd의 glibc)는 함께 올린다 — TARS 버전을 낼 때. 시각은 "chromium 판이 security에 있고 initrd의 glibc
   판과 같은 시각"으로 고른다.
3. harvest에서 빼는 것: `^/usr/lib/(systemd|environment\.d)/` · `^/etc/(machine-id|mtab)$` · `^/etc/xdg/systemd`(모든 묶음에 맞는 규칙), `harvest-skip.tsv`에 `systemd` ·
   `systemd-sysv` · `libpam-systemd` · `libsystemd-shared`(TARS에 systemd가 없다).
4. manifest에 두 줄: `chromium` 156.0.8078.79-1~deb13u1 · `fonts-noto-cjk` 1:20240730+repack1-1, 묶음 `browser`(일반 묶음 — base 위). 폐포는 apt가 푼다.
   gpu · media와 겹친 파일 지우기와 noto Serif 빼기는 하지 않는다(carryover — 새 "묶음 사이 의존"을 init · `make_iso.sh` · build에 들여야 한다). 294 MiB를 받아들인다.
5. browser는 게이트가 굽는 묶음 목록에 든다. 기본 ISO에는 싣지 않는다(2 GiB) — 지금 ISO가 묶음을 고르는 길을 단계 A가 확인해 기본 판의 내용이 안 바뀌게 한다.
   릴리스에 어떻게 실을지는 CR-M1이 정하지 않는다(`project_release`에 위험 한 줄).
6. `/dev/shm`은 CR에서 뺀다(design 결정 6을 고친다 — Chromium과 무관). POSIX shm의 관행으로 넣을 값은 carryover에.
7. `tars-browser`: `devlayer/files/browser/usr/local/bin/tars-browser`, bash. 묶음 없음 · uid 0 · Wayland 없음을 각각 한 줄로 알리고 1, 아니면
   `exec /usr/lib/chromium/chromium --ozone-platform=wayland --disable-gpu --no-first-run --no-default-browser-check "$@"`. Debian 래퍼 · API 키 env는 안 쓴다.
8. 체인 `browser/check.sh`(monitor 45510, `CHAINS` 37번째 `CR-M1`): display 체인 부팅 3의 모양으로 부팅 하나 — 설정 디스크 `user=` + 홈 디스크에 base · gpu · media ·
   browser와 체인이 쓰는 단색 HTML, `-m 2048 -nic none`. 판정:
   - 1 `overlay /usr from 4 layers` · `layer browser: N files into /etc`.
   - 2 화면 셸의 `tars-browser file://…` → `wl> title id=N app_id=chromium-browser` · `menu> bar id=N name=chromium-browser` · `wl> keys to=N mode=compat` ·
     `wl> commit id=N buf=636x772 scale=1`(상한 60초 — 게이트 부하에서의 여유를 잰다).
   - 3 페이지 제목이 `wl> title`로 오고, screendump의 상자 셋(색 상자 · 바탕 · 한글 글자 잉크 > 0 — 색은 테마 · 다른 체인 색과 안 겹치게), 두 장이 같을 때까지.
   - 4 sandbox: 렌더러의 `Seccomp: 2`와 새 user ns — 화면 셸(tars)의 권한으로 읽히는 길(`status`의 `Seccomp` · `NSpid`, `uid_map`, `ns/user`)을 재서 정한다.
     안 되면 시리얼(root) 입력 길을 체인에 둔다.
   - 5 `Cmd+Q` → `wl> close` · `wl> gone`, `wl> kill` 0, 남는 chromium 프로세스 0.
   - 6 문의 안내: Wayland 없이 부르면 한 줄과 종료 코드 1.
   이미지 버전(묶음의 `version`)을 부팅 하나에서 얻는 길은 단계 B가 싼 쪽으로 정한다.
9. 도움말 `docs/help/desk.md`에 `tars-browser [URL] &` 한 줄 — browser 묶음, 사용자(`user=`) 화면 셸에서, `Cmd+Q`로 끝, 주소창 타이핑은 아직 죽는다(WY-M7 전)를 숨기지 않는다.

## 할 일

1. (A) `devlayer/snapshot` · `harvest.sh`의 sources 바꾸기와 해시 · Makefile 변수(확정 1), 빼기 규칙과 skip(확정 3).
2. (A) manifest 두 줄 · 묶음 목록(확정 4 · 5).
3. (A) `make dev-layers` 한 판 — 모든 debian 묶음을 snapshot에서 다시 거두고 굽는다. 묶음마다 `differs=0 dangling=0 unresolved=0`, 크기 변화 표.
4. (A) 묶음을 쓰는 체인으로 확인: devtools · display · wayland(하나씩). 기본 ISO의 묶음 목록이 그대로인지.
5. (B) `tars-browser`(확정 7).
6. (B) `browser/check.sh` · 루트 `check.sh`의 `CHAINS`와 머리 주석 · Makefile의 dev-layers 목록 · 게이트의 메모리 셈(`-m 2048` lane)(확정 8).
7. (B) `docs/help/desk.md`, `measurements.md` 115(콜드 · 웜 · 크기 · 메모리 · harvest 시간), `lessons.md`(snapshot · Valid-Until · harvest.sh를 고치면 전부 다시 거둔다),
   `dead-ends.md`(live 미러의 `=판` 고정은 point release 날 깨진다), `key-files.md`.
8. lead: 단계마다 대조 · commit, B 뒤 루트 게이트(37), design 고침(확인 11 · 결정 2 · 3 · 6), carryover · 기억 · HANDOFF.

## 판정

- `make dev-layers`(모든 묶음 verify 통과), `make quick`, 체인 devtools · display · wayland · browser(두 번 연속) PASS, 루트 게이트 37/37, verify mismatch 0.

## plan에서 실측할 것

1. snapshot 시각으로 모든 debian 묶음을 다시 거둔 시간과 각 묶음의 크기 · `differs` 변화. 2. 화면 셸(tars)에서 렌더러의 `ns/user` · `uid_map` · `NSpid`가 읽히는가.
3. 게이트 부하 아래의 콜드 첫 화면 시간(60초 상한의 여유). 4. noto-cjk가 없을 때 한글 상자의 잉크 — 판정이 두부와 글자를 가르는가(가르지 못하면 판정을 바꾼다).
5. 체인 QEMU의 RSS(`-m 2048`)와 게이트 JOBS 셈. 6. `--no-first-run` 없이 첫 실행 창이 뜨는가. 7. 체인 단독 시간과 루트 게이트의 끝 시각 변화.

## 결과

구현은 `cr-m1`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `3fc9e75`: `devlayer/snapshot`(값 한 줄) · `harvest.sh`(sources를 그 시각으로 · 캐시 해시에 시각 · 빼기 규칙 셋) · `harvest-skip.tsv`(systemd 넷) · manifest의
   browser 두 줄 · Makefile(`DEV_LAYERS`에 browser · `DEV_SNAPSHOT`). `make dev-layers`: 묶음 15개 모두 `differs=0 dangling=0 unresolved=0`, browser
   `files=2810 unpacked=740MiB zstd15=294MiB`. 체인 devtools(1,133초) · display(482초) · wayland(528초) PASS, verify mismatch 0.
   다시 구운 debian 묶음 여덟은 옛 것과 크기가 같다 — 달라진 것은 사라진 `usr/lib/systemd/…` 경로(base 18 · server 15 · media 2 · lang-script 2, 새 빼기 규칙의 몫 — TARS에
   systemd가 없어 읽는 것이 없다)와 base의 `linux-libc-dev` 6.12.116 → 6.12.117(의존으로 오는 것) 하나다. 거두기는 아홉 묶음에 약 21분, 캐시 상태의 `make dev-layers`는
   149 → 156초(게이트가 매번 더하는 것 약 7초).
   plan과 달라진 것: (가) snapshot 시각은 `20261119T120000Z`다(plan의 21일 0시가 아니라). 21일에는 `php8.4-cli=8.4.27`이 없다(11-19 18시에 8.4.28로 바뀜) — 시각은
   "manifest의 모든 판이 함께 있는 가장 늦은 시각"이어야 한다는 규칙이 여기서 나왔다. chromium 156과 initrd의 glibc `+deb13u4`는 이 시각에도 맞다.
   (나) server의 pgdg 의존 넷(`postgresql-client-18` · `libpq5` 18.7-1.pgdg13+2, `postgresql-common` · `postgresql-client-common` 295.pgdg13+1)을 manifest에 판 고정으로
   더했다 — snapshot과 무관한 live vendor-repo의 재빌드(`+2` → `+5`)로 `postgresql-18 +2`가 "held broken packages"에 걸렸다. 옛 캐시가 가려 온 것을 모두 다시 거두며
   처음 봤다.
   ISO: `make iso`는 `ISO_LAYERS`만 보고 릴리스의 판들은 묶음을 이름으로 적으므로 기본 판의 내용은 그대로다. `make iso-full`(로컬 전용)만 browser까지 싣는다.
