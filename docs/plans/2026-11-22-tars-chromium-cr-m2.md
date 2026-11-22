# CR-M2 — 앱 풀스크린 = 자기 workspace · 주소창 한글 · 클립보드 양방향 · `net` 페이지

Date: 2026-11-22
Design: CR design `docs/specs/2026-11-22-tars-chromium-design.md`(milestone 표 CR-M2, 결정 9 고침 · 10), WY design `docs/specs/2026-11-19-tars-wayland-server-design.md`
(결정 56~58), 요구사항 결정 1 · 6 · R-WIN-2~4 · R-CR-5 · 녹화 D
Status: 끝(2026-11-22 — 단계 A `1965553` · B `7fc4142`, 루트 게이트 둘 다 37/37 첫 판). 브랜치 `app-layer-0-3`.

녹화 D: Chromium이 column으로 열린다 → `Cmd+Ctrl+F`로 자기 workspace → 페이지를 열고 URL을 복사해 셸에 붙인다(반대도) → 주소창에 한글.
끝나는 조건은 그 장면들이 `browser/check.sh`의 판정으로 도는 것이다(녹화 자체는 사람).

## 확인(조사 `cr-m2`, 세션 scratchpad `cr2/research.md` — HEAD `f0f3524`. 1부는 읽기, 2부는 체인 밖 시험 VM)

- 주소창 한글은 이미 된다(WY-M7 조사의 로그: `wl> ti content purpose=5` · `ti enable to=1` · `ime to=1 … preedit=ㅎ/하/한` · `commit=한`). 모자란 것은 "주소창에 들어갔다"를
  체인이 보는 길이다 — `wl> ime` 줄은 "서버가 보냈다"까지다.
- `wl> title` 줄은 창마다 4줄(`server.zig`의 `TITLE_LINES`)이고 browser 체인이 이미 셋을 쓴다. 어느 체인도 title 줄 수를 세지 않는다.
- 클립보드 양방향은 서버 · App에 고칠 것이 없다(WY-M4의 길 — `wl> selection` → `clip>` / `wl> offer` → `wl> receive`). 셸 쪽 복사는 copy mode
  (`Cmd+Shift+C` · `k` · `Shift+V` · `y`)나 포인터 끌기다.
- `Cmd+Ctrl+F`는 app column에서 "자기 workspace로 옮기기"가 아니다 — `main.zig`의 `.fullscreen_toggle`은 늘 `setFullscreen(self.current, …)`(셸 workspace의 chrome 토글, FU)이고
  앞이 app workspace면 아무 일도 없다. 매핑 뒤의 `set_fullscreen` · `unset_fullscreen`(Chromium의 F11)은 `want_fullscreen`만 바꾸고 App에 안 알린다 — Chromium이 자기 버퍼
  안에서만 풀스크린처럼 그린다. 요구사항 결정 1 · 6이 코드에 없다. CR-M2의 유일한 큰 코드 거리다.
- 있는 부품: `srv.placeWorkspace(id)`는 이미 매핑된 창에도 맞고(크기가 바뀌면 popup을 닫는다), `configureColumn`이 되돌린다. App의 `openApp`(끝에 app workspace) ·
  `closeSlot`(strip에서 빼기) · `removeWorkspace`. popup은 자기 workspace에서도 된다(`renderApp`의 경계가 화면 전체).
- 체인의 망: `net` · `service` · `firewall`은 SLIRP + `net=dhcp`, dictation은 `guestfwd=tcp:10.0.2.100:8080-cmd:perl stub`(연결마다 perl). 컨테이너에 python3은 없다.
  진입 검사 `require_explicit_nic`가 QEMU 줄에 `-nic none`이나 `-netdev`를 요구한다.
- 2부(시험 VM)의 실측은 아래 "조사 2부의 값"에 옮긴다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(Opus)에 두 단계로. lead는 plan · 대조 · 게이트 · commit. 루트 게이트는 단계 A 뒤(서버 · App의 workspace 길을 건드린다)와 B 뒤.

- 단계 A — 앱 풀스크린(서버 · App · 테스트 클라이언트 · wayland 판정): 할 일 1~4.
- 단계 B — browser 체인의 장면 다섯: 할 일 5~8.

## 착수 전에 확정한 것(WY design 결정 56~58, CR design 결정 9 고침 · 10)

1. 앱의 풀스크린은 그 창을 자기 workspace로 옮긴다(결정 56 — 요구사항 결정 1 · 6). 들어가는 길 둘: (가) 셸 workspace의 포커스 slot이 창일 때 `Cmd+Ctrl+F`,
   (나) column 창이 매핑 뒤에 보낸 `xdg_toplevel.set_fullscreen`(Chromium의 F11). slot을 strip에서 빼고(창은 산다 — `closeSlot`의 strip 쪽 절반) 끝에 `.app` workspace를
   더해 `placeWorkspace` · `enterWorkspace`. 포커스 slot이 셸 패널이면 `Cmd+Ctrl+F`는 FU 그대로다.
2. 아홉이 다 찼으면 거절한다(결정 6) — 제자리에서 그 column의 폭을 가장 넓은 preset으로(`Cmd+R`의 끝 값) 하고, (나)였으면 fullscreen 없는 configure로 답한다
   (xdg-shell: `set_fullscreen`에는 configure로 답한다). 줄 `wl> fullscreen id=N refused`.
3. 돌아갈 자리는 workspace의 정체로 기억한다(결정 57). `ShellWs`에 서버 수명 동안 느는 번호 `uid`를 두고 `AppWs.home`에 적는다(번호 = 자리는 workspace가 닫히면 당겨진다).
   나오는 길 둘: (가) home이 있는 app workspace에서 `Cmd+Ctrl+F`, (나) 클라이언트가 스스로 들어갔던 창의 `unset_fullscreen`. home workspace가 살아 있으면 그 포커스 column의
   오른쪽에(`openApp`의 column 길), 없어졌으면 가장 가까운 왼쪽 셸 workspace(없으면 첫 셸 workspace)의 오른쪽 끝에 놓고, 그 workspace를 앞에 두고 포커스는 그 slot.
   받을 셸 workspace가 없거나 strip이 거절하면(slot 여덟 · 너무 좁음) 아무 일도 없다(그대로 풀스크린). app workspace는 지운다.
4. 처음부터 자기 workspace로 뜬 창(첫 commit 전의 `set_fullscreen` — 둠, 또는 앞이 app workspace일 때 뜬 창)은 home이 없다 — `Cmd+Ctrl+F`와 `unset_fullscreen`은 지금처럼
   아무 일도 없다(둠은 화면 전체를 전제한다).
5. configure의 상태(결정 58): 클라이언트가 청한 풀스크린(F11 · 둠)은 `fullscreen` + `activated`, `Cmd+Ctrl+F`로 옮긴 창은 `maximized` + `activated`와 화면 크기다 —
   녹화 D는 자기 workspace에서 주소창을 쓴다(Chromium은 `fullscreen` 상태면 탭 줄 · 주소창을 감춘다). 자기 workspace에서 클라이언트가 `set_fullscreen`을 보내면 자리는 그대로
   상태만 `fullscreen`으로, `unset_fullscreen`이면 `Cmd+Ctrl+F`로 온 창은 `maximized`로 남고 스스로 온 창은 column으로 돌아간다. column으로 돌아간 창은 지금의 column
   configure(tiled)다. 단계 A가 맨 먼저 시제품으로 잰다 — `maximized` configure에 Chromium이 그림자 여백 · geometry · 탭 줄을 어떻게 하는지, `fullscreen`과 무엇이 다른지.
   Chromium이 `maximized`에서 주소창을 잃거나 그림이 어긋나면 lead에게 알리고 멈춘다(결정을 다시 한다).
6. 옮길 때의 포커스와 조합: 같은 창이 포커스를 계속 가지므로 키보드 leave · enter를 보내지 않는다. 셸 쪽 한글 조합은 `openApp`처럼 확정할 것이 없다(포커스가 창이다) —
   그 창에 보내던 조합(`ime`)은 옮기기 앞에서 확정한다(`focusTo`가 포커스를 잃는 창에 하는 것과 같은 함수). popup은 크기가 바뀌므로 닫힌다(`done why=resize` — 결정 53).
7. 줄: `wl> fullscreen id=N on ws=W from=H by=key|client` · `off ws=W slot=S by=key|client` · `refused` · `state id=N fullscreen=0|1`(자리 그대로 상태만). `TITLE_LINES` 4 → 16.
8. 순수한 부분은 호스트 검사로: "돌아갈 workspace 고르기"(home uid · 살아 있는 셸 workspace 목록 · 지금 자리 → 색인 또는 없음)를 `wl_logic.zig`에 함수로 두고 표로 검사한다.
9. 테스트 클라이언트: `tars-wl-test --fullscreen-later`(매핑 뒤 키 `f`에 `set_fullscreen`, `u`에 `unset_fullscreen`, configure의 states를 로그에).
10. 체인 wayland(판정 45~, 44 · 40~42 뒤 · 9 앞, 좌표는 단계가 실제 덤프로): 45 column 창에서 `Cmd+Ctrl+F` → `wl> fullscreen … on … by=key` · `configure w=1280 h=800` ·
    화면 전체가 창 색 · 셸 workspace의 `pane>` 줄에 slot이 없음 → 다시 `Cmd+Ctrl+F` → `off` · 원래 workspace의 column · configure가 pane 크기. 46 `f` 키(클라이언트 요청) →
    `by=client` · states에 fullscreen, `u` → 돌아옴. home workspace를 닫은 뒤 나오기(다른 셸 workspace의 오른쪽 끝). 47 workspace 아홉에서 거절 — `refused`와 column 폭.
    둠의 판정 10~15(처음부터 풀스크린)는 그대로다.
11. 체인의 망(CR design 결정 10 — 결정 9의 "네트워크 없음"을 고친다): browser 체인의 부팅 하나에 `net=dhcp`와
    `-netdev user,id=n0,restrict=on,guestfwd=tcp:10.0.2.100:80-cmd:perl <http_stub.pl> <log>` + `virtio-net-pci`. `restrict=on`이라 게스트는 바깥(인터넷 · 컨테이너)에 못
    나가고 stub 하나만 본다 — Chromium의 배경 요청이 회선에 안 기대고 컨테이너 포트(`RESERVED_PORTS`)를 안 쓴다. stub `browser/http_stub.pl`은 요청 줄을 로그에 적고 고정
    HTML(제목 `tars-net` · 바탕색)을 준다. HTTPS는 게이트 밖이다(자기 서명 인증서를 믿게 하는 길이 문 `tars-browser`를 나쁜 쪽으로 바꾼다 — 사람 녹화가 바깥 망으로 본다).
12. 체인 browser(판정 7~11, 3b 뒤 · 4 앞 — 부팅은 하나): 체인의 `page.html`에 스크립트(`?q=`를 읽어 제목 `q-<값>`, 값이 `한`이면 바탕색을 바꾼다 — 첫 화면은
    `location.search`가 비어 그대로). `type_line`에 `?`.
    - 7 셸 → Chromium: 셸에서 `echo file:///…/page.html?q=cr` → copy mode로 그 줄 복사(`clip> len=`) → `Cmd+]` → `wl> offer` → `Cmd+L`(`ti enable` 기다림) → `Cmd+V` →
      `wl> receive` → Enter → `wl> title … title=q-cr - Chromium`.
    - 8 주소창 한글: `Cmd+L` → `file:///…/page.html?q=` → Shift+Space → `m f s`(`wl> ime … preedit=한`) → Shift+Space(`commit=한`) → Enter → `title=q-한 - Chromium`과 바탕 좌표 색.
    - 9 `net` 페이지: 주소창에 `10.0.2.100/net.html` Enter → stub 로그의 `GET /net.html` · `title=tars-net - Chromium` · 바탕 좌표 색.
    - 10 Chromium → 셸: `Cmd+L` · `Cmd+C` → `wl> selection from=` · `clip> … text=http://10.0.2.100/net.html` → `Cmd+[` → `echo ` + `Cmd+V` Enter → 화면에 그 주소.
    - 11 풀스크린: Chromium column에서 `Cmd+Ctrl+F` → `wl> fullscreen … on … by=key` · 화면 전체의 좌표 색(페이지 바탕이 옛 셸 column 자리에) · 주소창이 산다(`Cmd+L`에
      `ti enable`) · 오른쪽 누름 메뉴가 자기 workspace에서 뜬다(`wl> popup … new`) → Esc → `Cmd+Ctrl+F` → `off` · column의 첫 화면 좌표. F11 → `by=client` → F11 → `off`.
    좌표 · 색 · 기다림 상한은 조사 2부와 단계 B의 실제 덤프로 정한다.
13. 문서: `docs/help/desk.md`(`Cmd+Ctrl+F` 줄 — 셸에서는 여백과 상태 줄, 앱 창에서는 자기 workspace · `tars-browser` 줄 — 주소창 한글 · 풀스크린 · `net=dhcp`),
    `measurements.md` 118(풀스크린 옮기기의 프레임 · Chromium의 첫 화면 시간(net 켠 부팅) · 체인 시간).

## 할 일

1. (A) 시제품으로 재기(확정 5): `maximized` · `fullscreen` configure에 대한 Chromium의 버퍼 · geometry · 탭 줄. report에 표로.
2. (A) 서버: 매핑 뒤 `set_fullscreen` · `unset_fullscreen`의 `Event`, 상태를 고른 configure(`placeWorkspace`에 상태 인자), 줄, `TITLE_LINES`.
3. (A) App: 옮기기 · 되돌리기 · home · 거절(확정 1~6), 순수 함수와 호스트 검사(확정 8).
4. (A) `tars-wl-test --fullscreen-later`, wayland 판정 45~47, `docs/help/desk.md`의 `Cmd+Ctrl+F` 줄.
5. (B) `browser/http_stub.pl` · QEMU의 망 줄 · 설정 디스크 `net=dhcp`(확정 11), `page.html` 스크립트 · `?`.
6. (B) 판정 7~11(확정 12), 머리 주석.
7. (B) `docs/help/desk.md`의 `tars-browser` 줄, `measurements.md` 118.
8. (B) carryover에 넘길 것 · 녹화 D의 순서(사람이 따라 칠 키 목록)를 report에.
9. lead: 단계마다 대조 · commit · 루트 게이트(37), 끝에 CR design Status · `completed.md` · 기억 `project_chromium` · carryover · 로드맵 · HANDOFF.

## 판정

- 호스트 검사, `make quick`, 단계 A: 체인 wayland 두 번 연속 · terminal · fullscreen · pane · toolkit · hidpi · pointer · display · browser PASS. 단계 B: browser 두 번 연속 ·
  wayland PASS. 단계마다 루트 게이트 37/37, verify mismatch 0.

## plan에서 실측할 것

1. `maximized` 대 `fullscreen` configure의 Chromium(확정 5). 2. 옮기는 프레임의 시간과 그 뒤 첫 commit까지. 3. 부모 크기 바뀜에 닫힌 popup을 Chromium이 다시 여는가
(WY-M7 실측 5 — 풀스크린 옮기기가 그 장면이다). 4. `restrict=on`에서 DHCP · guestfwd가 도는가, Chromium의 배경 요청이 첫 화면을 늦추는가. 5. `10.0.2.100/net.html`에
HTTPS-Upgrades의 되돌림이 끼는가(시간). 6. 배율 2에서 자기 workspace의 Chromium(논리 640 × 400 — `set_min_size(500)`을 넘는가). 7. browser 체인의 시간(지금 단독 414초).

## 조사 2부의 값

시험 VM(게이트가 지은 HEAD `f0f3524`의 이미지, TCG 한 CPU · `-m 2048` · 1280 × 800 배율 1, `shell=fish keyboard=apple user=tars net=dhcp`, 부팅 하나에 장면 전부).
시간에는 도구의 키 간격과 screendump가 섞여 있다 — 기다림 상한의 위쪽 값으로 읽는다.

- 망: `restrict=on`에서도 SLIRP DHCP가 돈다(`eth0: offered 10.0.2.15 from 10.0.2.2`). 기다릴 줄은 `terminal: link> state eth0 up=1 v4=1 ssid=-`(셸 프롬프트 전에 선다).
  게스트의 `curl -m 5 http://1.1.1.1/`은 곧바로 종료 코드 7, `curl http://10.0.2.100/net.html`은 받는다. net이 첫 화면을 안 바꾼다(명령 → `commit buf=636x772` 약 24초,
  좌표 색은 판정 3 그대로).
- 주소창 한글: `Cmd+L` → `ti enable to=1`(1.1초 안) → `…?q=` · Shift+Space · `m f s` → `ime to=1 commit=(none) preedit=ㅎ` · `하` · `한` → Shift+Space →
  `ime to=1 commit=한 preedit=(none)` · `hangul> on=false` · 곧 `ti disable to=1` → Enter → 1.1초 안에 `title=q-한 - Chromium` · 바탕 (1000, 400) `4169e1`. 인라인 자동 완성은
  안 붙었다. 주소창 글자 상자는 색 37가지(판정 3의 하한 60을 못 쓴다) — 픽셀 판정은 넣지 않고 PNG 둘만 남긴다(확정이 주소로 돌아 제목 · 색에 나오는 것이 더 강하다).
- Chromium → 셸: `Cmd+L` · `Cmd+C` → 1.2초 안 `wl> selection from=1 mime=text/plain;charset=utf-8` · `clip> len=43 text=file:///…/page.html?q=%ED%95%9C` — 복사된 주소는
  퍼센트 인코딩이다. net 페이지에서는 `clip> len=26 text=http://10.0.2.100/net.html`(scheme이 붙는다) → 셸 `Cmd+V` → `clip> paste len=26 bracketed=1`.
- 셸 → Chromium: copy mode(`meta_l-shift-c` · `k` · `shift-v` · `y`) → `clip> len=36 text=file:///…/page.html?q=cr` → `Cmd+]` → `wl> offer to=1 len=36` → `Cmd+L` · `Cmd+V` →
  `wl> receive to=1 mime=text/plain;charset=utf-8 len=36 first=36` → Enter → 바탕 `8e44ad`. 제목 `q-cr`의 `wl> title` 줄은 안 나왔다 — 다섯째 제목이라 `TITLE_LINES = 4`에 막혔다.
  fish는 `?`를 글롭으로 안 읽는다.
- net 페이지: Enter 0.4초 뒤 stub에 `GET /net.html HTTP/1.1`, 1.1초 뒤 `GET /favicon.ico`. HTTPS를 먼저 시도한 흔적이 없다(실측 5 닫힘). 바탕 `d35400`까지 5.5초 이하.
- 지금 코드의 `Cmd+Ctrl+F`(Chromium column 포커스): `fullscreen> on grid 160x50` · `wl> configure id=1 w=640 h=800` · `buf=660x820` — 셸 workspace의 chrome만 꺼지고 Chromium은
  오른쪽 반 column 그대로다. F11: 서버에는 키와 안내 bubble(subsurface 397 × 51)뿐이고 configure가 없다 — Chromium은 툴바를 감추고 그림자 여백 없이 버퍼 전체를 칠해 페이지가
  왼쪽 · 위로 10픽셀 잘린다(geometry가 버퍼 전체가 되는데 서버는 옛 fit 자리에 둔다 [추정]).
- 게이트: lane 0(ISO + 큰 메모리 — devtools 914초 · browser 76초 등 합 1,785초)이 가장 긴 lane이라 browser에 더하는 초가 게이트 끝을 그대로 민다. 짐작으로 단독 414 → 약 490초,
  게이트 안 76 → 약 150초.
- 시제품: `cr2/scripts/http_stub.pl`(요청 줄을 적고 `/net.html`에 바탕 `d35400` · 제목 `tars-net`, 그 밖은 404) · `cr2/page/page.html`(`?q=` 스크립트 — `한`이면 `4169e1`, 그 밖의 값이면
  `8e44ad`). 단계 B가 그대로 옮긴다.

확정 12에 더한다: 판정 7의 끝에 바탕 `8e44ad`, 9의 바탕 `d35400`, 망 판정 앞에 `link> state eth0 up=1 v4=1`, 판정 순서는 1 · 6 · 2 · 3 · 3a · 3b · 7 · 8 · 9 · 10 · 11 · 4 · 5,
판정마다 셸에 칠 것이 있으면 한글을 끈다, 실패 줄이 장면 번호를 말한다. `docs/help/network.md`에는 Chromium을 적지 않는다(서핑은 사람의 바깥 망 — R-CR-5).

## 결과

구현은 `cr-m2a`(Herdr, Opus), 조사는 `cr-m2`. lead는 plan · 대조 · 게이트 · commit.

1. 단계 A `1965553`: `wl_logic`의 `Place`를 `fullscreen · maximized · column` 셋으로(`toplevelStates`의 maximized 갈래) · 순수 함수 `pickReturn`(호스트 표 다섯) ·
   서버의 `Event.fullscreen`(매핑 뒤의 `set_fullscreen` · `unset_fullscreen`) · `placeWorkspace(id, state)` · `setWorkspaceState` · `answerFullscreen` · `TITLE_LINES` 16 ·
   App의 `ShellWs.uid` · `AppWs.home` · `by`, `enterOwn`(옮기기 · 아홉이면 거절과 폭 최대) · `leaveOwn`(되돌리기) · `fullscreenRequest` · `runPanes`의 `Cmd+Ctrl+F` 앱 갈래 ·
   `settleAppPreedit`(옮기기 앞의 조합 확정 — `focusTo`의 블록을 함수로) · `layout.Strip.lastColumnTop` · `tars-wl-test --fullscreen-later` · 도움말.
   확정 5의 실측(Chromium 156, 시험 VM): `maximized` configure(1280 × 800, states `1,4`)에 Chromium은 그림자를 버린 `buf=1280x800 at=0,0`을 그리고 탭 줄(y 0..40)과
   주소창(y 40..87)이 산다 — 페이지 원점 (0, 88). `fullscreen`(F11, states `2,4`)은 탭 줄 · 주소창을 감추고 페이지 원점 (0, 0). 되돌리면 처음 column과 픽셀까지 같다.
   조사가 본 "F11에 페이지가 10픽셀 잘림"은 사라졌다(이제 F11이 configure를 받는다). 결정 58 그대로 갔다.
   판정의 실제 값(wayland): 45 `ctrl-alt-f` → `wl> fullscreen id=23 on ws=2 from=1 by=key` · `configure id=23 w=1280 h=800 act=1` · `commit … buf=1280x800 … at=0,0` · 상자 다섯이
   `3366cc` · `Cmd+1`의 `pane> ws=1/2 panes=1` → 다시 `ctrl-alt-f` → `off ws=1 slot=1 by=key` · `configure … w=616 h=752`. 46 `f` → `by=client`(states `2,4`) · `u` → `off … by=client`,
   둘째 셸 workspace에서 옮긴 창(`from=2`)은 그 셸을 `exit`로 닫은 뒤 `u`에 `off ws=1 slot=1`(왼쪽 셸 workspace의 오른쪽 끝). 47 workspace 아홉에서 `refused` 둘 ·
   `configure … w=1240 h=752` 둘(F에도 답한다). 클라이언트 로그 `c45-1-1-1-0`.
   체인 wayland 두 번 연속 · terminal · fullscreen · pane · toolkit · hidpi · pointer · display · browser PASS, verify mismatch 0. wayland 첫 판은 FAIL(46) — 판정 쪽:
   `disown`한 클라이언트가 PTY를 표준 입력 · 에러로 물고 있어 `exit`한 셸 pane의 EOF가 안 왔다(`2>&1 < /dev/null & disown`으로 고침).
   실측: 옮긴 프레임 12 ~ 19 ms · 그 뒤 Chromium의 첫 1280 × 800 commit까지 218 ~ 290 ms(나오기 38 ~ 71 ms · 292 ~ 398 ms). 옮긴 첫 프레임은 옛 버퍼를 새 자리 가운데에 그린다.
   부모 크기 바뀜에 닫힌 popup을 Chromium은 다시 열지 않는다(WY-M7 실측 5 닫힘). 배율 2의 자기 workspace(논리 640 × 400)는 `set_min_size(500)`을 넘어 주소창이 산다(실측 6 닫힘).
   조합 중 `Cmd+Ctrl+F`는 옮기기 앞에 `commit=한`을 보내고, 옮긴 뒤 같은 창에서 조합이 이어진다(leave · enter 없음).
   plan과 달라진 것: (가) 실측 줄 `wl> fullscreen frame us=` · `commit ms=`(옮긴 뒤 한 번씩 — 판정은 안 쓴다). (나) 거절의 "가장 넓은 폭"은 `cycleWidth`를 `full`까지 돌린다.
   (다) 옮길 때의 조합 확정은 그 창이 키보드 포커스일 때만. (라) app workspace 프레임은 메뉴 바를 안 그려 `menu> bar hidden` 줄이 없다(판정에서 뺌).
   lead의 대조: 확정 1~10 · 결정 56~58과 맞다, 지운 51줄은 다시 쓴 선언 · 주석과 함수로 뽑은 블록. 화면 판정 — maximized의 Chromium이 탭 줄 · 주소창이 산 채 화면 전체.
   루트 게이트 37/37 첫 판(`out/gate-logs/20261122-052448`, lanes 1,657초 — wayland 353초 · browser 76초), verify mismatch 0.
2. 단계 B `7fc4142`: `browser/http_stub.pl`(guestfwd의 cmd — 요청 줄을 로그에, `/net.html`에 제목 `tars-net` · 바탕 `d35400`, 그 밖은 404) · QEMU의 망 줄
   (`restrict=on` SLIRP + `guestfwd=tcp:10.0.2.100:80`) · 설정 디스크 `net=dhcp` · 페이지의 `?q=` 스크립트 · `type_chars`(Enter 없이)와 `?` · 판정 7~11 · 도움말 ·
   `measurements.md` 118. 체인 browser 두 번 연속(391 · 389초) · wayland · display PASS, verify mismatch 0.
   판정의 실제 값: 7 copy mode로 `clip> len=30 text=file:///home/cr/page.html?q=cr` → `wl> offer to=1 len=30` → `Cmd+L` · `Cmd+V` → `wl> receive … len=30 first=30` →
   자동 완성 bubble의 `map` → Enter → `title=q-cr - Chromium` · 바탕 (1000, 400) `8e44ad`. 8 `…?q=` · Shift+Space · `m f s` → `wl> ime to=1 commit=(none) preedit=한` →
   Shift+Space → `commit=한 preedit=(none)` → Enter → `title=q-한 - Chromium` · `4169e1`. 9 `link> state eth0 up=1 v4=1` · `10.0.2.100/net.html` → stub 로그
   `GET /net.html HTTP/1.1` · `title=tars-net - Chromium` · `d35400`. 10 `Cmd+L` · `Cmd+C` → `wl> selection from=1 …` · `clip> len=26 text=http://10.0.2.100/net.html` →
   셸 `Cmd+V` → `clip> paste len=26 bracketed=1` · 화면에 그 주소. 11 `meta_l-ctrl-f` → `wl> fullscreen id=1 on ws=2 from=1 by=key` · `configure … w=1280 h=800` ·
   `commit … buf=1280x800 … at=0,0` · 옛 셸 column 자리 (100, 600, 200 × 150)까지 페이지 색 · 탭 줄 상자 (1000, 20, 200 × 20)는 페이지 색이 아님 · `Cmd+L`에 `ti enable` ·
   오른쪽 누름 `wl> popup … new parent=main at=700,401` → Esc → `gone` → `off ws=1 slot=1 by=key` · column configure. F11 → `by=client` · 탭 줄 상자까지 페이지 색 → F11 →
   `off … by=client`. `wl> gone pid=` 0.
   plan과 달라진 것: (가) 판정 7은 `receive` 뒤 자동 완성 bubble의 `map`을 기다린 뒤 Enter — 붙인 글이 비동기로 들어가 첫 판에서 Enter가 빈 주소창에 닿았다(판정 쪽 빨강).
   (나) 판정 10은 `Cmd+C` 뒤 Esc. (다) 11의 좌표는 그 시점의 net 페이지(`d35400`)에 맞췄고, 탭 줄이 사는지 · 사라지는지를 같은 상자 하나로 본다. (라) 체인 머리의
   `perl -c`(`make quick`은 perl을 안 본다). (마) 사람용 PNG(preedit 밑줄 · 확정 뒤 · maximized · 메뉴 · F11)는 다시 그릴 때까지 3초를 둔다.
   lead의 대조: 확정 11~13과 맞다, 지운 줄은 머리 주석과 둘로 나눈 `type_line`. 화면 판정 — 주소창의 `한`에 밑줄이 서고 자동 완성 줄에도 한글이 보인다.
   실측(`measurements.md` 118): 장면 7 · 8 · 9 · 10 · 11이 5 ~ 6 · 6 ~ 10 · 4 ~ 5 · 1 ~ 2 · 4 ~ 5초, 체인 단독 389 ~ 441초. 실측 4 · 5 닫힘(`restrict=on`에서 DHCP · guestfwd가 돌고
   HTTPS를 먼저 시도하지 않는다).
   루트 게이트 37/37 첫 판(`out/gate-logs/20261122-070015`, lanes 1,749초 — browser 76 → 101초 · wayland 353초), verify mismatch 0.
3. 마감: CR design Status "끝" · `completed.md` · 기억 `project_chromium` · carryover "CR-M2가 남긴 것" · lessons 둘(`disown`한 클라이언트의 PTY · 붙여넣기의 비동기) · 로드맵 6판.
   서브에이전트 pane 둘(`cr-m2` · `cr-m2a`)은 닫았다.
4. 녹화 D — 사람이 따라 칠 키(배율 1, 설정 `net=dhcp`, 바깥 망, apple 키보드):
   `tars-browser https://duckduckgo.com &`(오른쪽 열, 콜드 약 25초) → `Cmd+Ctrl+F`(자기 워크스페이스 — 탭 줄 · 주소창이 산다) → `Cmd+L` · 주소 · Enter → `Cmd+L` · `Cmd+C` · `Esc` ·
   `Cmd+1` · `echo ` · `Cmd+V` · Enter(셸에 주소) → 셸에서 `echo https://duckduckgo.com/?q=tars` · `Cmd+Shift+C` · `k` · `Shift+V` · `y` · `Cmd+2` · `Cmd+L` · `Cmd+V` · Enter →
   `Cmd+L` · `https://duckduckgo.com/?q=` · `Shift+Space` · 신세벌로 한글 · `Shift+Space` · Enter → 오른쪽 누름(메뉴) · `Esc` → `F11` 왕복 → `Cmd+Ctrl+F`(원래 열) → `Cmd+Q`.
