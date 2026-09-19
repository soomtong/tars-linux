---
name: project_shell_tools
description: 깔린 도구를 셸이 쓰게 만든 층 — eza 별칭 넷(`ls` 셰도)과 gitconfig 씨앗(ST-M0~M2, 2026-09-19)
metadata:
  type: project
---

UT가 게스트에 도구 65개를 세웠지만 그중 대부분은 이름으로만 닿았다. ST는 그
하나(eza)를 습관적인 이름에 앉히고, 저장소에 만들 코드가 없던
`/config/gitconfig`를 씨앗으로 채웠다. 그 결과 `/.gitconfig` 링크가 새
디스크·실기에서 더 이상 댕글링이 아니다.

design은 `docs/superpowers/specs/2026-09-19-tars-shell-tools-design.md`,
plan 셋은 `docs/superpowers/plans/2026-09-19-tars-shell-tools-st-m0.md` ·
`-st-m1.md` · `-st-m2.md`다.

## 씨앗 셋은 다 깔려 있었다 — 없던 것은 gitconfig 하나다

사용자가 "config 폴더에 fish 설정만 있고 bash·zsh 것이 없다"고 물었는데,
재 보니 절반만 사실이었다. 빈 디스크로 부팅하면 `tars-init: seeded`가 세
줄 찍히고 `/config`에 셋이 다 있다. 사용자가 본 것은 `/config`가 아니라
`/.config`였을 것이다 — 거기에 fish만 있는 것은 SC 결정 1이 정한 자리다
(fish만 rc를 XDG 아래에 둔다).

정말 없던 것은 `gitconfig`다. `kernel/make_initrd.sh`가
`/.gitconfig -> config/gitconfig` 링크를 걸어 두는데 그 실체를 만드는 코드가
저장소에 한 줄도 없었다 — `tools/check.sh`의 검사 13만 `git config --global`로
그것을 만들 뿐이고, 그래서 새 디스크의 링크는 영원히 댕글링이었다.

## 별칭을 넣기 전에 잰 것 둘

### 게이트가 rc 켜진 셸에 치는 이름

설정 디스크를 붙이는 체인은 여섯이다(`-drive file=` 개수로 셌다): config ·
input · power · hangul · net · machine. 나머지 여섯(boot · terminal · device ·
render · copy · tools)은 디스크를 안 붙이므로 씨앗 rc를 안 읽고, 따라서
어떤 별칭도 그 체인에서는 안 돈다.

치환의 첫 낱말을 세어 보면 `ls`가 돌아가는 자리가 셋이다 — config 6차
(`ls /config/zshrc` → `No such file`) · config 8차(`ls /config/xdg/zoxide` →
`db.zo`) · net 검사 2(`ls /sys/class/net` → `eth0`). 셋 다 "이름이 화면에
찍혔는가"를 본다.

### eza는 그 셋의 글자를 그대로 낸다

부팅으로 재서 셋을 통과시킨 뒤에 `ls`를 가렸다. 측정은 부팅 하나로 했다 —
`eza /config/nope-zzz`가 `No such file`을 포함한 문구를 내고, `eza DIR`은
이름을 그대로 찍는다.

같은 부팅에서 알게 된 것 하나: `eza --icons`는 이 기계에서 쓸 수 없다.
아이콘 코드포인트(U+E5FF 등)는 나오지만 unifont의 cmap 58,910자에
사설 영역(E000–F8FF) 글리프가 0개다 — 붙이면 이름 앞에 빈 칸만 생긴다.

## 결정 셋이 코드 모양이 된 자리

1. 별칭 이름은 손이 한 번 멈추는 자리를 지난다. `config_test.zig`의
   `ALLOWED_ALIAS_NAMES`가 그 자리다. `expectQuietSeed`는 `alias `로 시작하는
   줄을 전부 통과시키므로(별칭은 문법이 좁고 조용하다) 이름을 더하는 일에
   저항이 없었고, 그 저항이 없으면 게이트가 치는 이름을 가리는 별칭이 조용히
   들어온다. `ALIASED_TOOLS`가 그 짝이다(별칭과 배열을 함께 지우는 길을 막는다).
2. `ls`가 유일한 셰도다. `cat`·`find`·`grep`·`sed`·`du`·`df`·`top`은 안
   가린다 — 앞의 넷은 bat·fd·rg·sd와 플래그 뜻이 달라 조용히 다른 답을 내고,
   뒤의 셋은 화면을 통째로 가져가는 TUI다.
3. gitconfig 씨앗에는 `[user]` 절이 없다. 신원은 git이 `/etc/passwd`에서
   유도하고(`root <root@(none).(none)>`), 넣으면 `tools/check.sh` 검사 13의
   판정 값(`email = tars`)과 겹쳐 그 검사가 거짓으로 초록이 된다.

## 씨앗을 재는 검사에 두 종류가 생겼다

rc 셋은 "한 글자도 안 찍는가"를 재고(`expectQuietSeed`의 범주 검사 + 부팅),
gitconfig는 셸이 안 읽으므로 그 대신 **문법**을 잰다 —
`expectGitconfigSeed`가 주석·절·`키 = 값` 셋 밖의 줄을 거부한다. `=`가 빠진
줄 하나가 부팅 뒤 모든 git 명령에 `bad config line N`을 찍는 실패이고,
그것을 0.1초에 잡는 자리다.

## 판정

config 체인 1차 부팅이 셋을 찍는다 — `the seeded 'ls' alias runs eza (file
modes start with a dot)` · `git read init.defaultBranch=main out of the seeded
/config/gitconfig` · `init seeded the gitconfig too`. `ls`가 돌아가는 자리
셋(config 6·8차, net 검사 2)도 그대로 초록이다. tools 체인은 검사 13이
증명하는 경로가 안 바뀐 채 초록이고, 루트 게이트는 12체인 3/3에 `FAIL` 0줄이다.

## 다시 조사하지 말 것

- Zig의 multiline 문자열 리터럴은 탭을 거부한다(`string literal contains
  invalid byte: '\t'`). gitconfig 씨앗의 들여쓰기가 공백 넷인 이유다. git은
  둘 다 받는다.
- 씨앗은 `O_EXCL`이라 이미 있는 파일을 안 덮는다. 그래서 별칭을 늘려도 이미
  쓰던 설정 디스크는 새 씨앗을 못 받는다 — 지우고 재부팅하면 새 씨앗이
  깔린다(config 체인 6·7차가 그 경로를 매번 밟는다). README에 적어 두었다.
- 검사가 씨앗의 **주석**에 걸린 적이 있다. `[user]`를 글자로 찾는 검사가
  씨앗의 설명문에 있는 같은 글자를 잡았다 — 그래서 `expectGitconfigSeed`는
  주석 줄을 건너뛰고 절·키를 파싱한다.

관련 기억은 [[project_shell_config]](씨앗과 탈출로) ·
[[project_shell_memory]](훅 둘) · [[project_userland_tools]](도구 65개와
`/.gitconfig` 링크) · [[project_gate_accuracy]](게이트가 거짓을 말하지 않게
하는 규칙)다.
