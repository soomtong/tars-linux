# 화면 · 키보드 · 한/영 · 소리

아래의 `Cmd`는 Mac 키보드의 Cmd이고, PC 키보드에서는 `Alt`입니다(PC의 Ctrl · Win · Alt가 Mac의 Ctrl · Option · Cmd 자리입니다).

## 화면 나누기와 탭

| 키 | 하는 일 |
|---|---|
| `Cmd+D` · `Cmd+Shift+D` | 오른쪽 · 아래에 새 셸. 아래로는 한 열(column)에 셋까지 |
| `Cmd+]` · `Cmd+[` | 다음 · 앞 패널 |
| `Cmd+Option+화살표` | 그 방향의 패널로 |
| `Cmd+W` | 지금 패널 닫기 |
| `Cmd+R` | 지금 열(column)의 폭 — 80칸 · 120칸 · 절반 · 전체를 돈다 |
| `Cmd+T` · `Cmd+1`~`9` | 새 탭(워크스페이스) · 그 번호의 탭으로 |
| `Cmd+Shift+C` | copy mode — `/` 검색, `n` · `N` 다음 · 앞, `y` 복사, `Esc` 나가기 |
| `Cmd+Ctrl+F` | 전체 화면 — 둘레 여백과 아래 상태 줄을 감춥니다. 다시 누르면 돌아옵니다 |
| `Cmd+Q` | 앱(창) 끝내기 — 2초 안에 안 끝나면 강제로 끝냅니다. 셸에서는 아무 일도 하지 않습니다 |
| `Cmd+Shift+/` | 앱의 메뉴 열기 — 화면 맨 위 줄의 메뉴(File · Edit …). `←` `→` 메뉴, `↑` `↓` 항목, `Enter` 고르기, `Esc` 닫기. 제목을 클릭해도 열립니다 |

셸에서는 표에 없는 `Cmd+글자`(`Cmd+C` 등)가 아무것도 치지 않습니다. 줄 처음 · 끝(`Cmd+←` · `→`), 줄 앞 지우기(`Cmd+Backspace`),
붙여넣기(`Cmd+V`)는 그대로입니다.

열(column)이 화면에 다 들어가지 않으면 들어가는 만큼만 보이고(절반 폭이면 둘), `Cmd+Option+←` · `→`로 옮겨 다니면 화면이 따라갑니다. 상태 줄의 `2/3`이 지금 열과 전체 열 수입니다(화면 밖에 열이 있을 때만 보입니다).
열이 하나뿐이면 언제나 전체 폭이라 `Cmd+R`은 아무 일도 하지 않습니다. 보이는 열 오른쪽에 빈 칸이 남고 그다음 열이 있으면, 빈 칸 첫 줄에 그 열에서 돌고 있는 프로그램 이름(`fish` · `vim`)이 흐리게 보입니다.

부팅할 때부터 전체 화면으로 시작하려면 `sudo tars-config set fullscreen=on` 뒤 `sudo tars-config reload terminal`(열린 패널이 닫힙니다).
패널 안의 프로그램도 켜고 끌 수 있습니다 — `printf '\033[10;1t'`(켜기) · `printf '\033[10;0t'`(끄기) · `printf '\033[10;2t'`(바꾸기), xterm과 같은 시퀀스입니다.

Wayland 앱은 셸에서 그냥 띄웁니다(`WAYLAND_DISPLAY`가 잡혀 있습니다). 앱의 창은 셸 오른쪽에 새 열(column)로 열리고 키는 그
앱으로 갑니다 — 위 표의 키(`Cmd+[` · `Cmd+]` · `Cmd+R` · `Cmd+1`~`9` · `Cmd+Q` …)만 빼고요(`Cmd+W` · `Cmd+T`는 앱의 것입니다).
창이나 셸을 클릭하면 그쪽이 키를 받고, 휠도 포인터 아래 창으로 갑니다. 앱이 키를 받는 동안 화면 맨 위 줄에 그 앱의 이름과 메뉴가 보입니다(셸이 키를 받으면 비어 있습니다). 전체 화면을 바라는 앱(둠, `--fullscreen`)은 끝에 새
탭이 되어 화면 전체에 뜹니다 — `Cmd+1`로 셸에 돌아옵니다. 앱이 끝나면 그 열이나 탭이 사라집니다.
`tars-wl-test --color 3366CC &`는 한 색 창을 띄우고 받은 키 · 포인터를 찍는 시험입니다. gpu 묶음이 있으면
`tars-gpu-demo --window 640x400 &`가 SDL3 창으로 같은 자리에 뜹니다.
`tars-files [경로] &`는 파일 관리자입니다 — `↑` `↓`로 고르고 `→`(또는 `Enter`)로 디렉터리를 오른쪽 열에 열고 `←`로 돌아옵니다. 창에 다시 오면 목록을 새로 읽습니다.
`Cmd+C`는 고른 항목의 경로를 클립보드에 넣고(셸에서 `Cmd+V`), `Cmd+L`은 창 위에 경로 칸을 엽니다 — 경로를 치고 `Enter`면 그 자리로 열이 다시 서고 `Esc`면 닫힙니다.
경로 칸에서는 한글(`Shift+Space`)을 칠 수 있고, `←` `→`(`Shift`로 선택) · `Opt+←` `→`(낱말) · `Ctrl+A` `Ctrl+E` · `Cmd+A` · `Cmd+C` `X` `V` · `Cmd+Z`가 됩니다.
`Cmd+F`는 지금 열을 이름으로 거르고(`Enter`면 거른 채 닫고 `Esc`면 풉니다), `Cmd+K`는 첫 열 아래의 이름 · 경로를 찾습니다 — `↑` `↓`로 고르고 `Enter`면 그 자리로 갑니다.
이 키들은 맨 위 줄의 메뉴(File · Edit · View · Go)에도 있습니다 — `Cmd+Shift+/`로 열어 같은 일을 고를 수 있고, 지금 안 되는 항목(경로 칸이 아닐 때의 붙여넣기 등)은 흐리게 보입니다. 오른쪽 미리보기 판에는 고른 항목이 보입니다 — 글 파일은 앞부분의 줄들(1 MiB까지), PNG · JPEG는 그림(판에 맞게 줄여서), 그 밖의 파일과 디렉터리는 아이콘과 한 줄입니다. `Space`는 그 판을 감추고 다시 보입니다.
`tars-doom &`는 둠(Freedoom Phase 1, doom 묶음)입니다 — 화살표로 걷고 `Ctrl` 쏘기 · `Space` 문 열기 · `Shift` 달리기 · `,` `.` 옆걸음 · `1`~`7` 무기 · `Esc` 메뉴, `Cmd+Q`로 끝냅니다.

화면을 직접 그리는 프로그램(`/dev/dri/card0`을 여는 것)은 `tars-fullscreen <명령>`으로 띄웁니다. 그 프로그램이 끝나면 셸 화면이
돌아옵니다. 그동안 키보드와 마우스는 그 프로그램의 것입니다(셸에는 안 들어갑니다). 프로그램이 멈추면 `Ctrl+Cmd+Backspace`
(PC 키보드는 `Ctrl+Alt+Backspace` — `Del`이 아닙니다, `Ctrl+Alt+Del`은 재부팅입니다)로 끝내고 셸로 돌아옵니다.
`tars-fullscreen tars-kms-fill CC6666 5`는 화면을 5초 동안 한 색으로 칠하는 시험이고, `tars-kms-fill CC6666 0 --keys`는 `Esc`를 칠 때까지입니다.
`tars-fullscreen tars-gpu-demo`는 SDL3 · OpenGL ES로 움직이는 색 띠를 그리고 친 키의 이름을 보여 줍니다(`Esc`로 끝). gpu 묶음(SDL3 · Mesa)이
있어야 하고, SDL3로 만든 다른 프로그램도 같은 길로 뜹니다. 그린 드라이버는 `tars-gpu-demo 2>/tmp/gpu.log`의 `gl` 줄에 있습니다.
GPU 데모 판(묶음이 base와 gpu 둘뿐인 기계)은 부팅하면 첫 패널이 이 데모를 스스로 띄웁니다. `Esc`로 끝내면 셸이 남고, 그때의 줄은 `/tmp/gpu-demo.log`에 있습니다.

## 한/영

한/영 키, `Shift+Space`, 짧게 누른 `CapsLock`, 짧게 누른 왼쪽 `Ctrl` — 넷 다 한/영을 바꿉니다. 화면 아래 상태 줄의 첫 칸이 지금
상태입니다(`한` / `EN`). 한글을 치다 `Esc`를 누르면 영문으로 돌아옵니다(vim에서 편합니다).
텍스트 입력을 켠 앱(창)에서는 한/영 전환과 조합이 셸과 같습니다 — 조합 중인 글자는 앱이 그리고, 다른 곳을 누르거나 키를 옮기면
그 앱에 확정됩니다. 텍스트 입력을 켜지 않은 앱(둠 같은 게임)에는 지금처럼 키가 그대로 갑니다.

```sh
sudo tars-config set hangul_layout=dubeol            # 두벌식. 기본은 신세벌식(shin_pcs)
sudo tars-config set hangul_toggle=hangul_key,shift_space   # 바꾸는 키를 고릅니다(hangul_key · shift_space · capslock_tap · lctrl_tap)
sudo tars-config set esc_latin=off                   # Esc로 영문 돌아오기를 끕니다
sudo tars-config reload terminal                     # 화면을 다시 띄워 반영 — 열린 패널이 닫힙니다
```

## 키보드

키보드는 부팅 뒤에 꽂아도, 여럿 꽂아도 바로 칠 수 있습니다. Mac 키보드와 PC 키보드는 Option · Cmd 자리가 다릅니다 — 저절로
고르지만 틀리면 정해 주세요.

```sh
sudo tars-config set keyboard=apple      # 또는 pc
sudo tars-config reload terminal
```

## 복사와 붙여넣기

copy mode(`Cmd+Shift+C`)에서 `y`(또는 마우스로 끌어 놓기)로 잡은 글자는 어느 패널에서든 `Cmd+V`로 붙습니다. 클립보드는 화면이
다시 뜨거나 재부팅하면 비워집니다.
셸에서 복사한 것은 Wayland 앱이 붙이고, 앱에서 복사한 것은 셸이 붙입니다(앱을 닫은 뒤에도). 앱 안의 복사 · 붙여넣기 키는 앱의 것입니다 — 앱에는 `Cmd`가 `Ctrl`로 가므로(TARS 툴킷 앱은 `Cmd` 그대로) SDL · GTK 앱에서도 `Cmd+C` · `Cmd+V`를 칩니다.

## 배터리 · 밝기 · 절전

- 노트북이면 상태 줄 오른쪽 끝에 배터리 잔량이 보입니다. 초록은 충전 중, 빨강은 15% 이하입니다.
- 네트워크에 붙어 있으면 그 왼쪽에 Wi-Fi 이름이나 `LAN`(유선)이 보입니다. 흐린 색이면 아직 주소를 기다리는 중입니다.
- 밝기는 Apple 키보드의 F1 · F2, PC 키보드의 밝기 키(Fn 조합)로 바꿉니다.
- 뚜껑을 닫으면 잠자고 열면 깹니다. 셸에서는 `sudo suspend`를 칩니다(sudo 없이 치면 셸 자신이 멈춥니다).

## 소리

```sh
amixer sset Master 80%                    # 볼륨 — 끌 때 저장됩니다
alsamixer                                 # 화면으로 볼륨 · 음소거(M 키)
speaker-test -c 2 -t wav -l 1             # 왼쪽 · 오른쪽 스피커 시험
arecord -d 3 -f cd /tmp/m.wav && aplay /tmp/m.wav   # 마이크 시험
```

USB 헤드셋은 꽂으면 그쪽으로 바뀌고 뽑으면 돌아옵니다. 블루투스 이어폰은 되지 않습니다.

## 받아쓰기

말한 것을 커서 자리에 글자로 넣습니다. 망과 Groq API 키(무료, https://console.groq.com/keys)가 있어야 합니다.

```sh
sudo tars-config dictation key           # 키를 묻습니다
```

그 뒤 오른쪽 `Cmd`(PC 키보드는 오른쪽 `Alt`)를 빠르게 두 번 누르고 말합니다. 상태 줄 끝에 `REC`가 보입니다. 다시 두 번 누르면
받아 적어 커서 자리에 넣습니다. 녹음 중 `Esc`는 취소입니다.

처음으로: `tars-help`
