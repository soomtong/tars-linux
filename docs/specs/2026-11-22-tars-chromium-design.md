# TARS Chromium — Design

접두사: CR

Date: 2026-11-22
Status: CR-M1 끝(2026-11-22, `25e81b4` — 묶음 `browser` · `tars-browser` · 체인 `browser`, 루트 게이트 36/37 + 블루투스 체인의 알려진 간헐 크래시 재실행 초록).
사용자 위임(2026-11-18 "주요 결정은 너의 의견에 따를 테니까")으로 Claude가 정했다. 다음은 WY-M7 plan(`wl_subcompositor` → `xdg_popup` → text-input의 surface 귀속).
브랜치 `app-layer-0-3`.

요구사항 `docs/specs/2026-11-18-tars-app-layer-requirements.md`(R-CR-1~6, 결정 3 · 8, 위험 6, 녹화 D), 순서 `docs/plans/2026-11-18-tars-app-layer-roadmap.md`의 4단.

## 배경

App Layer(0.3)의 4단. Wayland 서버(WY-M0~M6)와 툴킷(TK)이 섰고, 남은 것은 "업스트림 Chromium이 수정 없이 뜨고 한글을 치고 셸과 복사 · 붙여넣기를 한다"(녹화 D)다.
요구사항 위험 6이 "Chromium의 요구는 재기 전에는 모른다"고 적었고 로드맵은 CR-M0을 "재기만 한다"로 두었다. 이 문서의 확인 절이 그 결과다.

## 확인(CR-M0, 조사 `cr-m0` — 세션 scratchpad `cr0/research.md`, HEAD `4d4ff99`, 개발 컨테이너의 QEMU TCG · `-m 4096`)

표기: 실측은 명령 · 로그로 본 것, 추정은 그렇게 적는다.

1. 뜬다. Debian trixie의 `chromium` 156.0.8078.79를 그대로, sandbox를 끄지 않고, `tars`(uid 1000)로 우리 compositor의 column에 띄웠다(`--ozone-platform=wayland`).
   `about:blank` · `file://` · HTTPS(DuckDuckGo 첫 페이지 — `net=dhcp` 부팅)가 그려진다.
2. sandbox와 계정(요구사항 결정 8): 커널에 `USER_NS` · `PID_NS` · `NET_NS` · `SECCOMP_FILTER`가 있고 `user.max_user_namespaces` 15196. 렌더러 · storage가 새 user · pid ·
   net namespace 안에서 `Seccomp: 2` · `NoNewPrivs: 1`로 돈다(`/proc/<pid>/status` · `ns/*`). setuid sandbox는 Debian 패키지에 없고 필요 없다. 화면 셸은 이미 `tars`로 뜬다
   (`terminal/src/pty.zig`의 `dropTo`) — 모자란 것이 없다.
3. 치명적인 벽은 하나, `wl_subcompositor`다. 주소창 자동 완성 · F11 안내 같은 bubble 창이 뜨는 순간 브라우저 프로세스가 `ui::WaylandBubble::Show`에서 SIGSEGV로 죽는다
   (minidump 셋을 `chromium-dbgsym`으로 푼 것 — null `wl_subcompositor`에 `get_subsurface`). 주소창에 글자 하나만 쳐도 죽는다. 페이지 안의 입력란은 된다.
4. `xdg_popup`(문맥 메뉴 · 앱 메뉴)은 지금 서버가 곧바로 `popup_done`을 보내 안 보일 뿐 죽지 않는다. positioner 요청은 `set_constraint_adjustment(41)` · anchor · gravity.
5. bind한 global: `wl_shm` 1 · `wl_compositor` 4 · `wl_output` 4 · `wl_seat` 7 · `xdg_wm_base` 5 · `zxdg_decoration_manager_v1` 1 · `wl_data_device_manager` 2 ·
   `zwp_text_input_manager_v3` 1. `tars_menu_manager_v1`은 bind하지 않아 호환 모드(`wl> keys … mode=compat`)다. 없다고 경고만 하고 뜨는 것: `wp_viewporter` ·
   `wp_content_type_v1` · color management 등. `wp_presentation` · dmabuf · `xdg_activation` · primary selection · pointer constraints · cursor shape · fractional scale은 없어도 뜬다.
6. 그리기(R-CR-3): `wl_shm` ARGB 버퍼(그림자 여백 10을 둔 636 × 772, `set_window_geometry(10, 10, 616, 752)`)로 소프트웨어 합성. 캐럿 깜빡임의 damage는 `(22, 108, 1, 33)` —
   서버가 그 사각형만 옮긴다. `--disable-gpu`가 없으면 `libEGL.so.1`을 못 열어 GPU 프로세스가 네 번 죽은 뒤 소프트웨어로 간다. `display_scale=2`에서는 `wl_output.scale(2)`를
   보고 `set_buffer_scale(2)`(`wl_compositor` 4라 `preferred_buffer_scale`은 안 받는다) — 글자가 물리 해상도로 선명하다.
7. 시간과 크기: 명령에서 첫 attach까지 콜드 20.0초 · 웜 6.9~7.8초(`--disable-gpu`, TCG 한 CPU — 커널이 `CONFIG_SMP` 없음). 프로세스 13개, RssAnon 합 약 266 MiB,
   시스템 used 564 MiB / 3925.
8. 입력: 키는 `wl_keyboard`(반복은 Chromium이). 호환 모드에서 `Cmd+A` `C` `V` `N`이 Ctrl로 먹는다 — 다만 Cmd 키 자체는 evdev 125로 가서 페이지가 `key=Meta` keydown을 본다.
   한글: 주소창 · 입력란 포커스에 `zwp_text_input_v3.enable`, 신세벌 `m f s` → preedit `ㅎ` → `하` → `한` → commit. v3로 충분하다(v1 불필요).
   클립보드: Chromium의 `Cmd+C` → `wl> selection … mime=text/plain;charset=utf-8` → 셸 클립보드.
9. 창: toplevel 하나 = 창 하나(탭은 같은 창), `set_app_id("chromium-browser")`, 제목은 탭마다 바뀜, `set_min_size(500, 87)`. `Cmd+N`의 새 창은 두 번째 toplevel → 새 column.
   장식: 서버가 `server_side`로 답해도 Chromium은 탭 줄과 창 단추를 직접 그린다. (고침, WY-M7) 창이 둘일 때 "text-input의 귀속이 어긋난다"고 적었던 것은
   로그를 잘못 읽은 것이다 — 귀속은 이미 surface였고(둘째 창의 한글은 그 창으로 간다) `ti enable` 줄의 `to=`가 첫 창을 찍던 표기만 틀렸다(WY design 결정 55, wayland 판정 43).
10. 빌드와 의존: `.deb` 91.7 MB, `--no-install-recommends` 폐포 170 패키지(받기 203 MiB · 설치 735 MiB). GTK는 `Depends`지만 NEEDED가 아니다(dlopen — 파일 선택 ·
    인쇄 대화상자). base · gpu · media 묶음 위에 얹으면 새로 드는 것은 80 패키지 · 압축 전 450 MiB · zstd15 164 MiB(글꼴 제외). postinst가 만드는 캐시(`gschemas.compiled` ·
    gdk-pixbuf · gio · mime)가 없으면 첫 키에서 죽는다 — harvest는 설치 전후 비교라 이것을 싣는다. 업스트림 스냅샷은 트렁크(160.0.8177.0)이고 261 MiB zip · 의존 수작업.
11. 실행 환경: dbus 없이 뜬다(경고만). `/dev/shm`은 없어도 된다 — 공유 메모리는 memfd이고 `/tmp/org.chromium.Chromium.*`은 ProcessSingleton 소켓 자리다
    (CR-M0은 "없어서 `/tmp`를 쓴다"로 잘못 읽었다 — CR-M1 조사가 `/proc/<pid>/maps`의 `memfd:` 53줄 · `/dev/shm` 0줄로 바로잡았다). Debian 래퍼 `/usr/bin/chromium`은 `--ozone-platform`을 안 붙여 X11을 골라 끝난다(`expr` 없음 경고도).
    fontconfig가 아는 글꼴은 묶음의 것뿐이다 — initrd의 Pretendard · unifont는 경로 밖. `fonts-noto-cjk`를 실은 실험 묶음에서 한글 · 한자 · 가나가 보였다.
    로캘은 `C.utf8`뿐(`--lang=en-US`로 뜸). 프로필은 `~/.config/chromium`(홈 디스크).
12. 보안 갱신: trixie-security의 chromium은 주 1회쯤 올라오고 옛 판은 `deb.debian.org`에서 사라진다(`apt-cache madison`에 한 줄). devlayer의 Debian 줄은 `version=`으로
    고정하고 저장소는 live다.
13. 곁에서 본 것: 묶음 squashfs는 `nosuid`로 붙지만 `/usr` overlay에는 `nosuid`가 없어 묶음에 실린 setuid 비트가 살아난다(같은 모양을 만들어 `sudo`로 확인).

재지 못한 것: 주소창 한글 · 자동 완성 · 권한 bubble(벽 3 때문), `<select>` 펼치기, 서버 chord `Cmd+Ctrl+F`로 Chromium을 풀스크린 workspace로, 셸 → Chromium 붙여넣기,
휠 · 스크롤 중 blit 비용, `libegl1`을 얹었을 때의 llvmpipe 합성, 게이트 부하 아래의 시간.

## 결정

1. 빌드는 Debian trixie의 `chromium`이다. R-CR-1의 "업스트림 빌드가 수정 없이"를 "TARS가 소스를 고치지 않은 Chromium"으로 읽는다 — Debian 판은 서명된 Release로 검증되는
   기존 harvest 길을 그대로 타고 보안 갱신이 매주 온다. 업스트림 스냅샷은 트렁크라 안정판이 아니고 의존을 손으로 채워야 한다.
2. 묶음은 `browser` 하나, base · gpu · media 위에 얹는 일반 묶음이다(R-CR-2 — initrd에 안 들어간다). GTK는 싣는다(대화상자 — Depends를 그대로 따른다).
   판 고정은 `version=`과 `snapshot.debian.org`의 시각 하나(`devlayer/snapshot`)다 — 저장소 전체에 쓴다(CR-M1 조사: browser에만 쓰면 다른 묶음과 같은 의존의 판이
   갈라져 대조에 걸리고, live 미러의 `=판` 고정은 2026-11-21 point release로 이미 base에서 깨져 있었다). 시각은 "manifest의 모든 판이 함께 있는 가장 늦은 시각"
   (지금 `20261119T120000Z`)이고, 그 시각의 InRelease 셋의 sha256을 함께 적어 내용으로 고정한다(http + 만료 끔은 freeze를 못 막는다). 지금 도구는 base와 같은 파일만 지우므로 "gpu · media 위"는
   "gpu · media와 같은 파일을 함께 싣는다"가 된다 — 294 MiB(겹친 것까지 지우면 228, carryover).
3. 한글 · 한자 · 가나 글꼴은 `fonts-noto-cjk`를 같은 묶음에 싣는다(웹 페이지는 한자와 일본어가 섞인다 — Pretendard만으로는 두부가 된다). zstd15로 68 MiB
   (Sans + Serif `.ttc` 넷 — CFF라 거의 안 줄어든다. Serif를 빼면 −40 MiB, carryover).
4. 실행 문은 우리 것 `tars-browser`다 — `--ozone-platform=wayland --disable-gpu`를 붙여 `/usr/lib/chromium/chromium`을 exec한다. Debian 래퍼와 그 Google API 키 env는 쓰지
   않는다. 인자(URL · 파일)는 그대로 넘긴다.
5. 계정과 sandbox는 지금 모양 그대로다(요구사항 결정 8이 이미 선다). `--no-sandbox`를 붙이는 길을 만들지 않는다. 체인은 렌더러의 `Seccomp: 2`와 브라우저 ≠ 렌더러의
   user namespace로 판정한다.
6. (고침, CR-M1) `/dev/shm`은 CR에서 다루지 않는다 — Chromium은 memfd를 쓴다(확인 11). POSIX shm의 관행으로 init이 만들 값은 CR 밖의 carryover다.
7. WY-M7의 범위와 순서: (가) `wl_subcompositor` · `wl_subsurface`(죽음을 없앤다) → (나) `xdg_popup` · `xdg_positioner`(메뉴가 보인다) → (다) text-input의 귀속을
   클라이언트가 아니라 포커스 surface로. 서버 쪽 장식은 뒤로 미룬다 — Chromium이 스스로 그린다. 호환 모드에서 Cmd 키 자체(evdev 125)를 Ctrl로 바꿔 보낼지는
   WY-M7이 재고 정한다(WY 결정 44는 "키 코드 그대로"였다).
8. milestone 순서를 바꾼다: CR-M1(묶음 · 문 · 체인 · 첫 화면)을 WY-M7보다 먼저 한다. 첫 화면은 지금 서버로 이미 뜨고, 묶음과 체인이 먼저 있으면 WY-M7의 결과를
   테스트 클라이언트뿐 아니라 진짜 Chromium으로 바로 검증한다("주소창에 글자를 쳐도 안 죽는다"). 로드맵 5판.
9. 체인 `browser/check.sh`: display 체인 부팅 3의 모양(설정 디스크 `user=` + 홈 디스크의 묶음들), `-m 2048` 이상, 네트워크 없음, 첫 화면 기다림 상한 60초.
   첫 화면은 체인이 쓰는 `file://` 단색 페이지(좌표 색을 정할 수 있다).

## Milestone

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| CR-M0 | 재기만 한다(끝) | 이 문서의 확인 절 |
| CR-M1 | 거두기의 snapshot 고정 · devlayer 묶음 `browser`(+ 글꼴) · `tars-browser` · 체인 `browser` | `file://` 첫 화면의 좌표 색, 렌더러의 sandbox 판정 |
| WY-M7 | `wl_subcompositor` · `xdg_popup`/`xdg_positioner` · text-input의 surface 귀속(WY design에 결정을 더한다) | 테스트 클라이언트의 subsurface · popup 좌표와 grab, browser 체인에서 주소창 타이핑이 안 죽음 |
| CR-M2 | 주소창 한글 · 셸과 클립보드 양방향 · `net` · 풀스크린 workspace | 녹화 D의 장면을 체인 판정으로(녹화 자체는 사람) |

## 위험

1. 주 1회 보안 판과 옛 판 삭제 — 묶음을 다시 굽는 일이 잦다(결정 2의 snapshot 고정이 안 되면 fresh 기계의 `make dev-layers`가 자주 깨진다).
2. `wl_subcompositor` 하나로 "타이핑하면 죽는다"가 풀리는지는 WY-M7 뒤에 다시 재야 안다(bubble이 다른 것을 더 바랄 수 있다 — 추정).
3. 콜드 20초(TCG 한 CPU)가 게이트 부하에서 늘어난다 — 체인 시간과 루트 게이트의 lane.
4. 묶음이 크다(zstd 164 MiB + 글꼴) — `make dev-layers`의 받기와 굽기 시간, 홈 디스크 이미지의 크기.
5. 묶음의 setuid가 overlay로 살아난다(확인 13) — browser 묶음에 setuid 파일이 끌려오는지 CR-M1이 보고, harvest가 지울지는 CR 밖의 결정으로 carryover에 적는다.
