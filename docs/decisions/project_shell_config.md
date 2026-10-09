---
name: project_shell_config
description: "게스트 셸이 사용자의 rc를 읽게 하고 그 파일이 부팅 사이에 살아남게 한 층(SC-M0~M2, 2026-09-11). tars.conf의 shell_config가 no-config 플래그를 켜고 끄고, /config의 rc 셋이 링크로 홈에 이어지며 init이 없으면 seed를 깐다. 탈출로 둘 — 감독자가 포기 직전에 rc 없이 한 번 더, 커널 cmdline의 tars.noconfig. 함정 — seed는 한 글자도 찍으면 안 된다 · 셸이 색을 쓰는 순간 화면 색에 기댄 판정이 깨진다 · 설정 디스크가 없는 부팅에는 탈출로를 안 준다"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-11에 UT가 남긴 후보 넷 중 이것을 골랐다 — `init`이 셸에 조건 없이
`--no-config` · `--norc` · `-f`를 넘겨 `zoxide`도 `fzf`도 걸 자리가 없던 문이다. design은
`docs/specs/2026-09-11-tars-shell-config-design.md`, SC-M0~M2가 같은 날 끝났다.
milestone별 경과와 게이트 시간은 2026-10-10에 지웠다(커밋 이력에 있다). 여기에는
결정과 다시 밟지 말 함정만 남긴다.

관련: [[project_userland_tools]](결정 8이 `/config`에 사용자 파일을 두는 첫 선례) ·
[[project_config_persistence]](`tars.conf`의 파서는 PID 1 한 벌) ·
[[project_guest_environment]](`TERM` · `LANG`이 사는 자리를 `fish_greeting`이 셋째로
쓴다).

## 사용자가 정한 것 — 다시 논의하지 말 것

| | 정한 것 | 안 고른 쪽 |
|---|---|---|
| 잇는 방법 | 링크 셋 — `/config` 아래 평평하게 | `HOME=/config`(프롬프트가 바뀐다) · 셸별 환경변수(bash가 구멍) |
| 설정 키 | `shell_config` enum `{on, off}`, 기본 `on` | `bool` · 기본 `off` |
| 왜 끌 수 있어야 하나 | embedded 장비의 init 1으로 쓸 때 — 앱 하나가 도는 기계에서는 설정이 없는 쪽이 안전하다 | 언제나 켜기 |
| seed | 셋 다, 프롬프트를 안 건드린다 | 현재 셸만 · 주석만 · 프롬프트를 우리가 정하기 |
| 탈출로 | 둘 다 — 감독자의 마지막 한 번 + `tars.noconfig` | 하나만 |
| 게이트 | `config/check.sh`에 부팅을 더한다 | 열두번째 체인 |

## 착수 전 프로브가 닫은 것

- fish는 인사말을 찍고 빈 `fish_greeting` 환경 변수가 그것을 막는다. 그런데 그 인사말을
  `machine/check.sh`가 UEFI 부팅의 마커로 grep한다 — `/etc/fish/config.fish`로 시스템
  전체를 끄면 그 마커가 죽는다. 처방은 `terminal`의 `setenv("fish_greeting", "", 1)` —
  화면 셸만 조용해지고 시리얼 콘솔 셸은 그대로 찍는다. 인사말을 건드리는 사람은
  `machine/check.sh`의 그 마커를 함께 본다.
- 설정을 다 읽은 fish의 기본 프롬프트가 `--no-config`로 뜬 것과 글자까지 같다 — 게이트
  좌표계가 그대로 선다. 다만 "프롬프트가 안 움직인다"가 덮는 범위는 글자뿐이었다(아래).
- zsh의 newuser 마법사는 안 뜬다. sysroot에 `zsh-newuser-install`이 있다는 사실로 세운
  추론이었는데 initrd에 안 들어갔다. `/.zshenv`를 만들지 말 것.
- `ps ax`가 셸의 argv를 화면에 보여 준다 — 부팅을 더 안 쓰고 플래그 변경을 본다.

## `"none"` 토큰이 왜 필요한가

`on`일 때 `init`은 `terminal`에 문자열 `"none"`을 넘기고 terminal이 그 값을 보면 셸
argv에 아무것도 안 붙인다. 빈 문자열도 null도 아닌 이유는 argv를 짓는 쪽(PID 1)과
쓰는 쪽(terminal)이 프로세스 경계로 갈려 있어서다 — "인자가 없다"를 포인터로 못 보내고
빈 문자열은 저쪽에서 "안 받았다"와 구분이 안 된다. `Toggles.arg`가 빈 집합에 `none`을
쓰는 것과 같은 이유다. 콘솔 셸은 init이 직접 exec하므로 슬롯을 null로 두면 그만이다.

fish는 `none`을 스크립트 파일 이름으로 읽는다 — terminal의 가로채기 한 줄을 지우면
`error: Error reading script file 'none'`로 대화형 셸이 아예 안 뜬다. 약속이 깨지면
조용한 오작동이 아니라 기계가 안 쓰인다.

## 셸이 색을 쓰기 시작했다 — 화면 색에 기댄 판정이 셋 깨졌다

`--no-config`로 뜬 fish는 구문 강조를 하나도 안 한다(A/B로 쟀다 — row 0의 색 있는 셀이
0 대 32). 게이트가 화면의 색을 판정에 쓰는 자리는 전부 "셸이 색을 안 쓴다"를 조용히
전제하고 있었고, 그 전제가 몇 개나 있는지는 플래그를 떼기 전에는 아무도 셀 수 없었다.
루트 게이트가 세 번 깨졌다.

- `style>` 덤프 상한이 16이라 색칠된 명령줄 32칸이 예산을 다 쓰고 아래 줄이 통째로
  잘렸다. 진단은 `terminal: style> 16 more cell(s) not shown` 한 줄 — 자르는 것을
  조용히 하지 않기로 한 TR-M2의 선택이 값을 냈다. 상한을 96으로.
- 로그 줄을 넓히면 앞과 뒤를 동시에 건드린다. `tars-init: config shell=` 줄을 `$`로
  뒤에 매달아 잡던 자리가 하나 있었다. 처방은 끝 대신 경계(`( |$)`).
- "반전됐다"를 색 두 개(`fg=102030 bg=FFFFFF`)로 박아 두면 셸이 글자에 색을 쓰는 순간
  틀린다. 반전의 표식은 `fg`가 기본 배경색이라는 것 하나이고 `bg`는 그 글자가 원래 갖던
  색이라 검사가 알 바가 아니다. 같은 가정을 쓰는 셋(`hangul` · `copy` · `render`)을 다
  고쳤다. `copy/check.sh`의 앰버 하이라이트 계수(`fg=FFFFFF bg=C08000`)는 우리가
  칠하는 색이라 안 고쳤다 — 알고 두는 부채다.

## seed는 한 글자도 찍으면 안 된다

설정 디스크를 붙이는 체인 중 셋이 화면의 셀 좌표로 판정한다. seed 파일이 생기는 순간
그 체인들의 화면이 seed의 내용을 따라간다. 그래서 seed에 쓸 수 있는 줄은 주석과
`alias`뿐이고 `init/src/config_test.zig`의 `expectQuietSeed`가 호스트에서 0.1초에
확인한다(줄의 종류 · alias 최소 하나 · seed가 자기 경로를 적었는가). 이 검사의 목적은
지금 통과하는 것이 아니라 나중에 막는 것이다 — seed를 늘리는 사람이 보는 것은 부팅
20초 뒤에 밀린 화면 좌표가 아니라 이 줄이다.

판정 글자 `tars-rc-alive`는 seed가 아니라 게이트가 1차 부팅에서 `/config/zshrc`에
더한다(덮어쓰지 않는다 — 2차가 읽는 것이 seed + 그 줄이어야 한다). SC-M1의 seed alias
`tars-config`(`cat /config/tars.conf`)는 TC-M0이 같은 이름의 실행 파일로 바꾸면서
지웠다([[project_config_tool]]).

## 결정 4의 두 절반 — `terminal: screen>`가 그 경계다

| 어디 | 누가 찍나 |
|---|---|
| `terminal: screen>`가 아닌 줄 | 시리얼 콘솔 셸 — init이 직접 exec했다 |
| `terminal: screen>` 줄 | 화면 셸 — terminal이 PTY에 띄웠다 |

콘솔 셸에는 타이핑을 못 하지만(`-serial file:`은 쓰기 전용) 그 셸이 스스로 찍는 것은
읽을 수 있다. `terminal:` 디버그 줄 중 셸의 텍스트를 나르는 것은 `screen>` 하나뿐이라
이 구분이 정확하다.

`init/src/main.zig`의 `console_flag` 한 줄을 세 상태로 두면 세 검사에 각각 걸린다 —
조건 없이 플래그면 2차의 시리얼 검사만, 조건 없이 null이면 3차의 부정 검사만, 설정대로면
아무것도 안 죽는다. 1차 · 2차가 전부 통과하는 결함이 실제로 있고 3차만 그것을 본다.
부정 검사는 그것이 죽는 경우를 직접 만들어 봐야 한다 — plan의 되돌림 셋 중 어느 것도
부정을 건드리지 못해 네 번째를 만들었다. 다른 검사가 먼저 죽으면 그 검사는 아직
아무것도 증명하지 않았다.

## 설정 디스크가 없는 부팅에는 탈출로를 안 준다 (SC-M2)

감독자는 자식이 왜 죽었는지 모른다 — `fast_restarts >= 3`만으로는 "사용자의 rc가 셸을
죽였다"와 "GPU가 없어 terminal이 못 뜬다"를 못 가른다. 둘째 경우에 탈출로가 발동하면
`boot/check.sh`가 정확히 3으로 세는 재시작이 6이 된다. 처방은 조건 하나 — 설정 디스크가
안 붙은 부팅에는 탈출로가 없다. 그런 기계에는 rc 실체가 없어서(홈의 링크가 끊어져
있다) 자식이 죽는 이유가 rc일 수 없다. plan을 쓰면서 `giving up`을 grep하는 자리 넷을
먼저 훑어 찾았고 음성 확인(`started the terminal 6 times, want exactly 3`)이 확인했다.

| | 발동 조건 | 덮는 것 | 대가 |
|---|---|---|---|
| 결정 8(감독자) | 자식이 죽어야 한다 | 죽는 rc | 자동. 매달리는 rc는 못 본다 |
| 결정 9(cmdline) | 사람이 부팅 순간에 적는다 | 죽는 것도 매달리는 것도 | 사람이 그 자리에 있어야 한다 |

우선순위는 cmdline > `tars.conf` > 기본값이고 이 키만 cmdline을 본다 — 근거는
"`tars.conf`를 고칠 셸이 없을 때 쓰는 것". 토큰은 부분 문자열이 아니라 토큰으로 보고
(`tars.noconfigured`가 안 걸린다) 값이 붙어도 받는다(`tars.noconfig=1`). 끄는 방법은
`=0`이 아니라 안 적는 것이다.

게이트는 3차(`off`)에서 `/config/zshrc` 끝에 `exit`을 심고 4차의 수 셋으로 본다 —
`tars-rc-alive` 3(rc를 세 번 읽었고 그 끝이 `exit`이라 "읽었다"와 "죽었다"가 같은 사실) ·
`started console shell` · `started terminal` 각 4(셋은 죽고 넷째가 rc 없이 산다) ·
`giving up on` 0. 하나만 보면 갈리지 않는다. 5차는 같은 함정에 cmdline 한 단어만 다르고
`started`가 각 1이다. 죽는 셸은 첫 렌더보다 먼저 죽어 `terminal: screen>`가 한 줄도 없는
구간이 생기고, 되살아난 뒤 그 줄이 있다는 것이 검사 하나다.

## 컨테이너의 첫 읽기가 낡은 파일을 봤다 — 원인 미상

`zig build test`가 세 번, 직전 내용의 결과를 냈다(깨뜨린 첫 실행이 `PASS`, 둘째가 옳은
`FAIL`). 같은 컨테이너 안에서 `md5sum`이 옛 내용을, 밀리초 뒤의 `grep`이 새 내용을 본
것이 증거다 — zig 캐시가 아니라 bind mount의 첫 읽기다. 재현은 서른 판에서 못 했다.
처방은 음성 확인을 한 번으로 판정하지 않는 것이다([[project_zig_out_staleness]]와 다른
병이지만 증상은 같다).

## `debugfs`로 이미지에 직접 묻는다

게이트 로그에 `tars-init: seeded`가 일부 체인에만 보여도 seed가 안 깔린 것이 아니라 그
체인이 성공했을 때 첫 부팅의 로그를 안 찍는 것일 수 있다 — 로그에 없는 것과 안 일어난
것이 다르다. `debugfs -R 'cat /zshrc' out/config.img`로 파일시스템에 직접 묻는다
([[project_seeding_a_config_disk]]).

## 게이트로 못 보는 것

| 못 보는 것 | 왜 |
|---|---|
| bash · fish의 rc가 읽히는가, 그 셸에서 죽는 rc | rc가 읽히는 것을 보는 셸은 zsh 하나다. bash는 로그의 `seeded` 한 줄이 전부 |
| seed의 내용이 맞는가 | 호스트 검사가 보는 것은 문법 범주와 자기 경로다 |
| `off`일 때도 seed를 깐다는 것 · 사용자가 rc를 지웠을 때 다시 깔리는가 | 코드로는 그렇다(`O_EXCL`). 게이트가 그 갈래를 안 지난다 |
| 매달리는 rc | 게이트는 죽는 rc만 심는다. 매달리는 rc를 심으면 그 부팅의 타임아웃이 체인의 타임아웃이고 "매달렸다"와 "느리다"가 안 갈린다 |
| 탈출로 1이 두 번 안 도는가 | 코드로는 `c.rescue = null` 한 줄이다. 게이트는 rc 없이 뜬 셸이 안 죽으므로 그 갈래를 안 지난다 |
| 실기에서 limine 메뉴로 토큰을 적는 것 | 게이트는 `-append`로 심는다 |
| 인사말이 화면에 없다 | 어느 체인도 판정으로 안 갖는다. `grep -a "terminal: screen>" \| grep -c "Welcome to fish"`로 한 번 보는 것이 전부 |
