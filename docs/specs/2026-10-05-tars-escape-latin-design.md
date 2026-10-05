# TARS Escape Latin — Design

Date: 2026-10-05
Status: 끝났다(2026-10-05, EL-M0). plan은 `docs/plans/2026-10-05-tars-escape-latin-el-m0.md`이고 끝의 "실측한 것" 절이
값이다. 루트 게이트 19체인 2/2, 50분 58초. 기억은 `docs/decisions/project_escape_latin.md`.

사용자의 요청 한 줄에서 시작한다(2026-10-05).

> esc키 누르면 한글 자판인 경우 영문자판으로 전환; vim 사용할 때 큰 도움이 됨.

## 한 줄 요약

한글을 치다가 수정키 없는 Esc를 누르면, 조합 중이던 글자를 확정하고 Esc는
평소처럼 프로그램에 보내고 한/영을 영문으로 돌린다. normal 모드에서만 그렇고,
`tars.conf`의 새 키 `esc_latin=on|off`가 켜고 끈다. 기본값은 `on`이다.

```
vim의 insert, 한글:   …닷▮   ──Esc──▶   vim이 받는 바이트: 닷(3) + ESC(1), 한 write
                                         상태 줄: 한 → EN
                                         바로 친 :wq 가 영문이라 명령이 된다
```

## 왜 새 서브프로젝트인가

Hangul Input(HI)은 2026-09-01에 닫혔다. 그때 만든 한/영 전환 키 넷(한/영 키 ·
Shift+Space · 짧은 CapsLock · 짧은 왼쪽 Ctrl)은 전부 한/영을 뒤집는 키이고,
`tars.conf`의 `hangul_toggle` 목록이 그중 무엇을 켤지 고른다(HI design 결정 7).
이번 요청은 그 목록에 다섯째 키를 더하는 일처럼 보이지만 성질이 다르다 — Esc는
뒤집지 않고 끄기만 하며, Esc 자체는 한글 층이 삼키지 않고 프로그램에 가야 한다.

참고 구현이 있다. 사용자의 macOS 입력기 Patal의 `ESC라틴` trait이다
(`PatalInputController.swift`의 `canESC라틴` 갈래). "조합을 확정하고 라틴 자판으로
빠져나간다(vi 노멀 모드 진입용)"이고 ESC 자체는 앱이 받는다. 2026-09-13에 사용자가
"팥알입력기의 나머지 trait도 당분간 고려 대상 아님"이라고 정해 두었는데
(`docs/guides/lessons.md`의 이월 숙제), 이번 요청이 그중 하나를 다시 집은 것이다.

milestone은 하나(EL-M0)다. 크기는 Copy Indicator(CI) 정도다.

## 모델

| 모드 | 한/영 | 키 | PTY로 가는 것 | 뒤의 한/영 |
|---|---|---|---|---|
| normal | 한글, 조합 중 | Esc | 확정된 음절 + ESC, 한 write | 영문 |
| normal | 한글, 조합 없음 | Esc | ESC | 영문 |
| normal | 한글 | Shift+Esc | (조합 중이면 음절 +) ESC | 한글 그대로 |
| normal | 한글 | Ctrl · Alt · Cmd + Esc | EL 전과 같다 | 한글 그대로 |
| normal | 영문 | Esc | ESC | 영문(EL 전과 같다) |
| copy | 한글 | Esc | 없음 — copy mode를 닫는다 | 한글 그대로 |
| find | 한글 | Esc | 없음 — 조합을 버리거나 프롬프트를 닫는다 | 한글 그대로 |

`esc_latin=off`이면 표 전체가 EL 전과 같다. 첫 줄의 Esc도 음절을 확정하고 ESC를
보내지만(HI design 결정 6 — 자모가 아닌 키는 확정을 부른다) 한글은 켜진 채다.

한/영 상태는 터미널 전체에 하나다(`main.zig`의 `key_state` 하나를 패널 전부가
쓴다). 그래서 어느 패널의 vim에서 Esc를 치든 터미널 전체가 영문이 된다. 지금까지
Shift+Space가 그랬던 것과 같다.

## 결정

### 결정 1 — 설정은 따로 있는 키 `esc_latin=on|off`이고, terminal에는 전환 키 목록에 이름을 붙여 넘긴다

후보는 셋이었다.

| 후보 | 설정 파일 | terminal로 가는 길 | 왜 아닌가 |
|---|---|---|---|
| (a) `hangul_toggle`의 다섯째 이름 | `hangul_toggle=…,esc_latin` | 지금의 목록 문자열 | 이미 있는 설정 파일에서 꺼진 채로 뜬다(아래) |
| (b) 따로 있는 키, argv 새 칸 | `esc_latin=on` | argv 아홉째 칸 | `Child.argv`가 `[8:null]`로 꽉 찼다. 넓히려면 그 타입을 쓰는 `CHRONYD_ARGV` · `DHCPCD_ARGV` · `WIFI_ARGV`까지 고친다 |
| (c) 따로 있는 키, 목록 문자열에 실어 보낸다 | `esc_latin=on` | 지금의 목록 문자열 끝에 `esc_latin` | 고른 것 |

(a)가 안 되는 이유가 이 결정의 중심이다. init은 설정 디스크가 비어 있으면 첫
부팅에 `save()`로 seed `tars.conf`를 쓰는데, 그 파일에는 모든 키가 기본값으로
글자 그대로 적힌다. HI-M3 뒤에 만들어진 모든 `/config/tars.conf`에
`hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap`이 있다는 뜻이다.
목록에 이름을 더하면 새 기본값은 새로 만든 파일에만 들어가고, 이미 쓰고 있는
기계(설치한 노트북의 설정 파티션은 ISO를 갈아도 남는다 — DI design)에서는 이
기능이 꺼진 채로 뜬다. 요청한 사람의 기계가 바로 그 기계다. 따로 있는 키는 그
줄이 없는 파일에서 기본값(`on`)이 된다 — `shell_config` · `net` · `firewall`을
더할 때마다 써 온 성질이다.

성질도 (c) 쪽이다. `hangul_toggle`은 "한/영을 뒤집는 키의 집합"이고 Esc는 끄기만
한다. 설정 파일을 읽는 사람에게 둘이 다른 줄인 것이 맞다.

argv는 lead가 권한 길 그대로다. terminal 쪽은 Esc를 전환 키와 같은 자리
(`hangulLayer`)에서 읽으므로 `input.Toggles`에 `esc_latin` 칸을 두고, init이 목록
문자열 끝에 이름을 붙인다. 그 조립은 순수 함수 `Config.terminalToggles`이고
`config_test`가 본다.

그래서 이름 하나가 두 뜻을 갖게 된다. init의 `Toggles`는 "파일의 `hangul_toggle`
줄"이고 terminal의 `Toggles`는 "argv로 온 목록"이다. terminal 쪽에서 한 방향
동작이 "toggle"이라는 이름 아래 들어가는 것을 받아들인다. 이름을 바꾸면 HI의
식별자와 로그 줄(`terminal: hangul layout=… toggles=…`)과 그것을 보는 게이트
판정이 함께 바뀌는데, 그 값을 치를 만큼 헷갈리는 자리는 아니다. 두 구조체의
주석이 차이를 적는다.

| 자리 | 모양 |
|---|---|
| init `config.zig` | `EscLatin = enum { on, off }`, `Config.esc_latin = .on`, `parse`에 `esc_latin` 갈래(`shell_config`와 같은 모양), `Toggles`에 `esc_latin` 칸(목록으로는 못 켠다 — `ToggleKey`에 없다), `Config.terminalToggles` |
| seed `tars.conf` | `hangul_toggle=` 바로 뒤에 주석 두 줄과 `esc_latin=on`. 1,969 → 2,191바이트(`MAX_FILE` 4096) |
| init 로그 | `tars-init: config … firewall=off esc_latin=on` — 키를 더할 때는 맨 뒤에 붙인다(`lessons.md`). `toggles=`는 파일의 목록 그대로다 |
| argv 여덟째 | `Config.terminalToggles` — 기본값이면 `hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin`. 길이 55, `TOGGLE_ARG_MAX` 64 그대로 |
| terminal 로그 | `terminal: hangul layout=… toggles=…,esc_latin` |
| terminal `input.zig` | `Toggles.esc_latin`, `ToggleKey`에 이름, `parseToggles` · `togglesArg` 한 줄씩, `State.toggles` 기본값 켜짐 |
| terminal `main.zig` | argv가 없을 때의 기본 문자열 끝에 `,esc_latin` |

기본값이 `on`인 근거는 `keyboard=apple` · `hangul_layout=shin_pcs` · 전환 키 넷 기본
켜짐과 같다 — 이 기계를 쓰는 사람이 쓰는 것이 기본값이다. Patal에서는 이 trait이
기본 꺼짐이지만 TARS에서는 사용자가 요청한 동작이다. HI-M3이 적어 둔 "전환 키가
많아서 곤란한 경우는 없고 없어서 곤란한 경우는 있다"와 같은 종류의 판단이다.

### 결정 2 — Esc가 한글을 끄는 것은 normal 모드 · 수정키 없음 · 한글이 켜졌을 때뿐이다

자리는 `hangulLayer` 안, Ctrl · Alt · Meta 갈래 바로 뒤다. 하는 일은 셋이다.

1. `commitHangul()` — 조합 중인 음절을 확정 통로(`commit_buf`)에 넣는다.
2. `hangul_on = false`.
3. `null`을 돌려준다 — 그래서 Esc는 평소의 길(`chord` → `specialKey` → `keymap`)로
   0x1b 한 바이트가 되어 `.bytes`로 나간다.

`readKeys`가 확정분을 그 키의 바이트보다 먼저 쓰므로(HI design 결정 6) 조합
중이었으면 한 write에 "음절 세 바이트 + ESC"가 실린다(`key> 4 byte(s)`). vim은
음절을 insert한 뒤에 Esc를 받는다. 확정이 끄기보다 먼저인 것은
`toggleHangul`이 지키는 불변식("`hangul_buf`가 비지 않았으면 `hangul_on`이 참")
때문이다.

copy mode와 검색 프롬프트의 Esc는 이 갈래에 닿지 않는다. `handleKey`에서 find
분기(SH design 결정 3)와 copy 분기(CM design 결정 3)가 한글 층보다 앞에 있고
둘 다 Esc를 먼저 가로챈다. 바꾸지 않는 이유가 있다. 두 모드의 Esc는 한 겹을 벗기는
명령이지 프로그램에 가는 Esc가 아니고, 한/영은 셸에 칠 글자의 상태라 그 모드에
들어갔다 나와도 그대로여야 한다(HI design 결정 5의 직교성). 검색어를 한글로 치던
사람이 프롬프트를 닫았다 다시 열면 한글이어야 한다.

Shift+Esc는 안 끈다. Patal이 수정키 없는 Esc만 보는 것을 따른다. 수정키가 있는
Esc는 다른 키 조합으로 다루는 쪽이 규칙이 하나다. Ctrl · Alt · Cmd + Esc는 바로 위
갈래가 이미 가져간다(확정만 하고 흘려보낸다). 대문자 잠금은 누르고 있는 키가 아니라
상태라 조건에 안 들어간다.

한글이 꺼져 있으면 `hangulLayer`가 이 갈래 앞에서 `null`을 돌려주므로 한 글자도 안
바뀐다. 자동 반복은 첫 누름이 끄고, 나머지는 꺼진 상태의 Esc다.

### 결정 3 — 다시 그리기는 `readKeys`가 `hangul_on`의 앞뒤를 비교해서 켠다

Esc는 `.bytes`로 나가야 vim이 받는다. `Action`은 union이라 하나만 나르므로
`.redraw`를 함께 돌려줄 수 없다. 조합 중이었으면 `takeCommit()`이 비지 않아
`readKeys`가 `redraw`를 켜지만, 조합 중이 아니면 아무것도 안 켠다. 그러면
두 가지가 빠진다.

- 상태 줄 첫 칸의 `한`이 다음 프레임까지 남는다. IS design 결정 8이 긴 CapsLock에서
  겪은 것과 같은 종류의 구멍이다.
- 게이트의 유일한 창구인 `terminal: hangul> on=… preedit=…` 줄이 안 찍힌다. 그
  줄은 `keys.redraw`일 때만 찍힌다.

| 후보 | 왜 아닌가 |
|---|---|
| `Action`에 "바이트 + 다시 그리기" variant를 더한다 | `Action`을 빠짐없이 switch하는 자리(`readKeys`, `input_test`의 헬퍼 다섯)가 전부 바뀐다. IS-M1이 `Action.caps`를 안 만든 것과 반대 방향이다 |
| `main.zig`가 지난 `hangul_on`을 기억해 비교한다 | 비교가 `input.zig` 밖으로 나가서 호스트 검사가 못 본다 |
| `readKeys`가 `handleKey` 앞에서 `hangul_on`을 읽고 뒤와 비교한다 | 고른 것. 한 줄이고, `to_needle`을 `handleKey` 앞에서 읽는 것(SH design 결정 5)과 같은 자리다 |

전환 키 넷은 이미 `.redraw`를 돌려주므로 이 비교가 더하는 것이 없다. 앞으로
`hangul_on`을 바꾸는 길이 또 생겨도 이 한 줄이 다시 그리기를 켠다. 한글이
꺼진 채 친 Esc는 비교가 같으므로 `redraw`를 안 켠다 — vim에서 Esc를 칠 때마다
화면 전체를 다시 그리지 않는다(`input_test` 검사 74의 대조군).

### 결정 4 — 새 체인 없이 hangul 체인이 본다. 설정 디스크는 안 고친다

hangul 체인(`hangul/check.sh`, monitor 45462)이 한글을 켜는 유일한 체인이다. 그
체인의 설정 디스크(`hangul/make_disk.sh`)에는 `hangul_toggle=shift_space,capslock_tap,lctrl_tap`
이 있고 `esc_latin=` 줄은 없다. 이것이 EL 전에 만든 설정 파일의 모양 그대로라서,
디스크를 고치지 않는 것 자체가 결정 1의 질문("옛 파일에서도 켜지는가")을 게이트가
보게 한다.

| 자리 | 본다 |
|---|---|
| 검사 0(고친다) | init 줄 끝이 `esc_latin=on`이다. init의 `toggles=`는 셋 그대로이고, terminal 줄이 `toggles=shift_space,capslock_tap,lctrl_tap,esc_latin`이다 |
| 검사 21(새) | 검사 20이 끝난 copy mode에서 Esc — `copy> exit`가 찍히고 `hangul> on`은 `true` 그대로, 상태 줄은 `한  공세벌 3-P3  쿼티  CAPS` |
| 검사 22(새) | normal에서 `ㄱ`을 조합하고 Esc — `key> 4 byte(s)`가 하나 늘고 `on=false preedit=(none)`, 상태 줄 `EN`, 그 뒤 친 `echo el-ok`가 셸에 영문으로 닿는다 |
| 검사 23(새) | Shift+Space로 켜고 조합 없이 Esc — `key> 1 byte(s)`가 하나 늘고 `hangul>` 줄이 하나 늘고 `on=false`, 상태 줄 `EN`. 결정 3을 보는 자리다 |
| 검사 24(새) | vim의 insert에서 `닷`을 조합하고 Esc — `key> 4 byte(s)`가 하나 늘고 `on=false`, 바로 친 `:wq`로 셸 화면이 돌아오고, `cat /tmp/el.txt`가 `닷`을 찍는다 |

호스트에서는 `input_test` 검사 69~74와 `config_test`의 EL-M0 절이 본다.

| 검사 | 본다 |
|---|---|
| `input_test` 69 · 70 · 71 | 조합 중의 Esc(바이트 `\x1b`, 확정 `가`, 꺼짐, 뒤의 `r`이 라틴) · 조합 없는 Esc · 꺼진 상태의 Esc(아무것도 안 켠다) |
| `input_test` 72 | Shift+Esc · Ctrl+Esc · `esc_latin`이 빠진 목록에서는 한글이 켜진 채다 |
| `input_test` 73 | find의 Esc · copy의 Esc는 한글을 안 끄고, 셸로 돌아온 Esc는 끈다 |
| `input_test` 74 | `readKeys`의 `redraw` — 조합 없는 Esc가 켜고, 꺼진 상태의 Esc는 안 켜고, 조합 중이면 바이트가 `가` + `\x1b` |
| `config_test` | `esc_latin=off · on · yes · 빈 값`, 목록에 적은 `esc_latin`은 버려진다, 옛 seed의 목록 줄에서도 `on`이다, `terminalToggles`의 다섯 경우 |

`esc_latin=off`를 부팅으로 보는 검사는 안 만든다. 디스크가 하나 더 필요한데, off
갈래는 EL 전의 코드 그대로이고 argv 목록에 이름이 없을 뿐이다. 그 둘을 호스트가
본다(`input_test` 72 · `config_test`).

## 검증

위 결정 4의 두 표가 전부다. 사본(`/tmp/run/el0/repo/`)에서 HEAD 판과 plan 판의
hangul 체인이 둘 다 초록이었고 시간은 65초 → 81초다. mutation과 regression의
값은 EL-M0 plan의 "착수 전에 확정한 것"에 있다.

## Milestone

### EL-M0 — Esc가 한글을 끈다

`terminal/src/input.zig` · `input_test.zig` · `main.zig`, `init/src/config.zig` ·
`config_test.zig` · `main.zig`, `hangul/check.sh` · `hangul/make_disk.sh`(주석만)를
고치고 루트 게이트를 돈다. plan은 `docs/plans/2026-10-05-tars-escape-latin-el-m0.md`.

## 위험

1. 셸에서 한글을 치다가 Esc를 다른 뜻으로 쓰던 사람은 한/영을 다시 켜야 한다. fish의
   자동 완성 제안을 Esc로 닫고 한글을 이어 치는 경우가 그렇다. 대가를 받아들이고 끄는
   길(`esc_latin=off`)을 seed 주석에 적는다. 반대로 readline의 Meta 접두(Esc 다음
   `b`로 단어 뒤로)는 이제 한글 상태에서도 동작한다 — 전에는 `b` 자리가 자모가 됐다.
2. 한/영이 터미널 전체에 하나라서 한 패널의 vim에서 친 Esc가 다른 패널의 셸도
   영문으로 만든다. 지금의 Shift+Space와 같은 성질이고, 패널마다 따로 두는 것은
   비목표 4다.
3. 사람이 `hangul_toggle=…,esc_latin`처럼 목록에 적을 수 있다. 그 이름은 init의
   화이트리스트에 없어서 `tars-init: unknown hangul_toggle 'esc_latin', ignored`가
   찍히고 버려진다. 기본값이 `on`이라 동작은 사람이 원한 대로이고, 끄려는 사람은
   seed 주석에서 `esc_latin=off`를 본다.
4. 확정분과 ESC가 한 write로 간다. vim의 `ttimeoutlen=50`은 ESC 뒤에 바이트가 더
   오는지를 기다리는 것이라 앞의 음절과 상관이 없다. 게이트 검사 24가 이것을 실제
   vim으로 본다.

## 비목표

1. copy mode · 검색 프롬프트의 Esc가 영문으로 돌리는 것(결정 2).
2. Shift+Esc와 `Ctrl+[`. vim에서는 `Ctrl+[`도 Esc와 같은 뜻이지만 Patal을 따라 수정키
   없는 Esc만 본다. 원하게 되면 결정 2의 조건에 한 줄을 더하는 일이다.
3. 반대 방향. Esc가 한글을 켜거나, vim이 insert로 돌아갈 때 한글을 되살리는 것(모드별
   한/영 기억). Patal도 안 한다. 우리는 vim의 모드를 모른다 — CU가 그리는 커서 모양
   (DECSCUSR)으로 짐작할 수는 있지만 그것은 추측이다.
4. 패널마다 한/영을 따로 두는 것.
5. 게이트에서 `esc_latin=off`로 부팅하는 것(결정 4).
6. 상태 표시를 더하는 것. 상태 줄 첫 칸(`한`/`EN`)이 이미 보여 주고, 결정 3이 그 칸을
   바로 갱신한다.

## 착수 전에 실측한 것

2026-10-05, HEAD `5acc735`. lead가 보낸 전제를 코드와 사본의 실행으로 다시 확인했다.

1. 한/영 상태는 터미널 전체에 하나다 — 맞다. `main.zig`의 `var key_state: input.State`
   하나를 `readKeys(&key_state, …)` 한 자리가 쓴다.
2. normal 모드의 Esc 경로 — 맞다. `hangulLayer` → `qwerty_keymap[KEY_ESC]`가 0x1b →
   `nonSyllable` null → `lookup` null → `commitHangul()` → null → `chord` null →
   `specialKey`에 Esc가 없다 → `keymap` → `one(0x1b)`. 사본의 plan 판 시리얼 로그에서
   조합 중의 Esc가 `terminal: key> 4 byte(s)` 한 줄이었다.
3. copy · find 모드의 Esc — 맞다. 그리고 `input_test` 검사 29가 HI 때부터 "copy mode를
   나와도 한글이 켜진 채다"를 보고 있다.
4. `Action`과 `redraw` — 맞다. 조합이 없을 때 아무것도 `redraw`를 안 켜는 것은
   mutation 1이 실제로 보였다(plan 확정 6). 비교를 지운 판에서 검사 23이
   `no new hangul> line`으로 빨갰다.
5. 설정의 모양 — 바로잡았다. argv 여덟 칸이 꽉 찬 것은 맞다(`init/src/main.zig`의
   `argv: [8:null]?[*:0]const u8`). 그러나 목록의 다섯째 이름으로 하면 seed가 네 이름을
   글자 그대로 적어 둔 기존 설정 파일에서 꺼진 채로 뜬다(결정 1). 그래서 설정 파일은
   따로 있는 키이고, argv는 권고대로 목록 문자열에 실어 보낸다.
6. 게이트 함정 — 바로잡았다. 디스크의 목록은 `hangul/check.sh`가 아니라
   `hangul/make_disk.sh`가 굽고, `check.sh`의 `EXPECT_TOGGLES`가 기대값이다. 결정 1의
   모양에서는 디스크를 고치지 않는다. init 줄의 `toggles=`는 셋 그대로이고 terminal 줄만
   `,esc_latin`이 붙는다. `tars-init: config .*toggles=`를 보는 체인은 hangul 하나뿐이고
   (`tools/check.sh`의 것은 주석이다), init 줄 끝에 필드를 붙여도 `config shell=…`을
   앞부분으로 보는 `net` · `firewall` · `power` · `tools` · `machine`의 판정은 안 바뀐다.
7. `input_test`의 Esc 검사 열하나는 전부 copy · find 모드다 — 맞다. normal 모드에서
   한글을 켜고 Esc를 치는 기존 검사는 없다. `State`의 기본값이 `esc_latin` 켜짐이 되어도
   기존 OK 줄 열여섯이 그대로였고 새 넷이 더해졌다.
8. 다른 체인의 Esc. `pane` · `pointer` · `render` · `config` · `copy`가 normal 모드에서
   Esc를 치지만 그때 한글이 꺼져 있다. 한글을 켜는 것(`shift-spc`)은 hangul 체인뿐이다.
   regression 셋(`config` · `render` · `copy`)의 결과는 plan 확정 7에 있다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜, EL-M0)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄. 예: "한글을 치다가 Esc를 누르면 확정하고 영문으로
  돌아온다 — vim의 insert에서 나오면 다음 키가 명령이다. `esc_latin=on|off`(기본 on)는
  따로 있는 키라 옛 `tars.conf`에서도 켜진다. 새 체인 없이 `hangul` 체인이 vim으로 본다".
- `docs/decisions/project_escape_latin.md`를 만들고 `MEMORY.md`에 한 줄. 담을 것 —
  목록이 아니라 따로 있는 키인 이유(옛 seed), argv는 목록 문자열에 실었다, `readKeys`의
  앞뒤 비교, copy · find는 안 바꿨다.
- 다시 연 결정에 한 줄씩. HI design 결정 7(전환 키 넷 — Esc의 한 방향 끄기가 따로 있는
  키로 더해졌다)과 `docs/decisions/project_hangul_input.md`. `lessons.md` 이월 숙제의
  "팥알입력기의 나머지 trait도 당분간 고려 대상 아님" 문단에 `ESC라틴`은 EL이 했다고.
- `docs/guides/lessons.md`. "로그 문구는 두 곳에 중복된다"의 `config shell=… firewall=…`
  뒤에 `esc_latin=…`. hangul 체인도 `wait_for_new_screen`을 갖게 됐다는 것.
- `docs/guides/running-tars.md`. 지금 한/영 전환 설명이 없다. 설정 절에 `hangul_toggle`과
  `esc_latin`을 한 단락으로.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-08-31-tars-hangul-input-design.md` — 결정 5(모드와 한/영의 직교성) ·
  6(확정을 부르는 키, `commit_buf`) · 7(전환 키 넷과 `hangul_toggle`) · 13(한글 자판은 쿼티
  자리)
- `docs/specs/2026-09-02-tars-input-status-design.md` — 결정 8(`Action.redraw`, 상태가
  바뀌면 다시 그려야 한다)
- `docs/specs/2026-09-09-tars-search-hangul-design.md` — 결정 3(find의 Esc) · 5(모드를
  `handleKey` 앞에서 읽는다)
- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 결정 3(copy mode가 키를 삼킨다)
- `docs/decisions/project_hangul_input.md` · `project_input_status.md` ·
  `project_search_hangul.md` · `project_config_persistence.md`
- Patal `macOS/Patal/PatalInputController.swift`의 `ESC라틴` 갈래
