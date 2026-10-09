---
name: project_shell_memory
description: "기계가 사용자에게서 배운 것 둘(자주 간 디렉터리 · 쳤던 명령)을 부팅 너머로 남기는 층(SM-M0~M2, 2026-09-11·12) — zoxide · fzf가 서고 seed rc의 훅이 걸리며 XDG_DATA_HOME 하나가 둘을 /config로 옮긴다. 함정 — 댕글링 링크는 DB 자리가 못 된다 · 판정 글자가 타이핑한 줄에 있으면 검사는 가짜다 · 훅 줄에는 command -v 관문이 붙는다 · 허용 목록을 seed에서 조립하면 역방향 검사가 tautology다 · 한 부팅 안에서 되는 것과 부팅을 넘어 되는 것은 다른 검사다"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-11에 SC가 닫히자마자 골랐다 — UT가 "셸 설정을 다루는
서브프로젝트가 생기면 그때 함께 온다"고 미뤄 둔 `zoxide` · `fzf`다. design은
`docs/specs/2026-09-11-tars-shell-memory-design.md`, SM-M0~M2가 2026-09-12에 끝났다.
milestone별 경과와 게이트 시간은 2026-10-10에 지웠다(커밋 이력에 있다). 여기에는
결정과 다시 밟지 말 함정만 남긴다.

관련: [[project_shell_config]](훅을 걸 자리 — `/config`의 rc 셋 — 을 만든 층이고 그
결정 1을 SM이 기각했다) · [[project_userland_tools]](도구가 서는 구조 —
`guest_tools.sh` 배열 하나, `make_initrd.sh`는 한 글자도 안 고쳤다) ·
[[project_guest_environment]](env 블록) · [[project_shell_history]](히스토리가 전원을
넘는 것은 SD · BH가 따로 했다).

## 결정

- `/config`의 DB 자리는 링크가 아니라 `XDG_DATA_HOME` 환경 변수다. SC의 링크
  패턴은 설정 디스크가 없는 부팅에서 댕글링이 되고 셸은 없는 rc를 조용히 건너뛰어
  충분했지만, zoxide에 댕글링 링크를 DB 자리로 주면 `cd`마다 에러 두 줄이 뜬다.
  없는 경로를 env로 주면 zoxide가 `mkdir -p`하고 `exit 0`한다. 덤으로 그 변수 하나가
  zoxide DB와 fish 히스토리를 동시에 옮긴다 — `_ZO_DATA_DIR`이 필요 없다.
- env 블록은 `environ.withTarsEnv`가 `resolveShell` 뒤에 짓는다 — `HISTFILE`이 셸마다
  다른 파일이라 셸이 정해져 있어야 한다(`cfg.shell`이 아니라 폴백 뒤의 `shell`).
- fzf 0.60에는 셸 통합이 내장돼 있다(`fzf --zsh` / `--bash` / `--fish`). `.deb`의 예제
  파일과 `fzf-tmux`는 안 넣는다.
- `git-delta`와 게이트가 `Ctrl+R`을 치는 것은 비목표다(TUI가 화면을 가져가 체인이
  매달린다). 게이트가 보는 것은 `whence -w fzf-history-widget`이 `function`을 내는
  것까지다 — `widget`이 아니라 `function`이다.
- `makeXdgDir()`은 기능이 아니라 실패의 자리를 정하는 것이다. zoxide가 없는 경로를
  스스로 만들어 그 호출을 지워도 초록이지만, 디스크가 붙었는데 거기에 못 쓰면 로그
  한 줄이 남는 편이 나중에 셸에서 "기억이 안 남는다"를 조사하는 것보다 낫다. 초록인
  것을 알고 남긴 줄과 모르고 남긴 줄은 다르다.

## 훅 줄에는 관문이 붙는다 — 없으면 체인 넷이 밀린다

```
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"    # zsh · bash
type -q zoxide && zoxide init fish | source                  # fish
```

관문이 있으면 셋 다 0바이트이고, 없으면 도구가 없는 기계에서 찍는다(fish는 6줄).
설정 디스크를 붙이는 체인 중 셋이 화면의 셀 좌표로 판정하므로 그 한 줄이 SM과
무관한 체인을 깨뜨린다. 관문의 값은 "도구가 없어도 도는 것"이 아니라 "실패의 자리를
정하는 것"이다 — 도구가 사라진 기계는 조용히 기억을 잃고 그 사실을 말하는 자리는
`config/check.sh`의 7차 부팅 하나다.

셸 셋의 훅 자리가 다르다 — zsh는 `chpwd_functions`, fish는 `--on-variable PWD`,
bash는 `PROMPT_COMMAND`(프롬프트마다). 그래서 `bash -i -c '…'`으로는 훅을 확인할 수
없다 — 프롬프트를 안 그리므로 `PROMPT_COMMAND`가 한 번도 안 돈다
([[project_measuring_shells]]).

## 허용 목록을 seed에서 조립하면 역방향 검사가 tautology다

`config_test.zig`의 `expectQuietSeed`가 셋을 본다 — 정방향(비주석 · 비`alias` 줄은
`hookLines()`의 한 줄과 글자 그대로 같다) · 역방향(`hookLines()`의 전부가 seed에 있다) ·
덮개(훅 목록이 `zoxide` · `fzf` 둘을 다 덮는다). 그래서 seed의 훅 글자와 `hookLines()`의
글자를 두 벌로 둔다 — `++`로 조립하면 역방향이 언제나 참이다(UT-M1의 정적 목록
검사가 같은 이유로 가짜였다). `startsWith`가 아니라 `eql`인 것도 같은 종류다 —
접두사로 보면 `command -v zoxide >/dev/null && rm -rf /`가 통과한다.

## 판정 글자가 타이핑한 명령줄에 있으면 그 검사는 도구가 죽어도 초록이다

`zoxide` · `fzf` 둘 다 경로를 찍는 도구라 특히 약하다 — 경로는 우리가 방금 타이핑한
것이다. 처방 둘 — fzf는 검색어와 판정 글자를 다르게 하고, zoxide는 `..`를 지나는
경로를 친다(정규화해서 저장하므로 DB가 돌려주는 글자가 화면의 다른 어디에도 없다).

```
cd /usr/bin/../share/terminfo/x     ← 훅이 여기서 배운다(chpwd)
cd /
z terminfo x
pwd  →  /usr/share/terminfo/x       ← 이 글자를 만들 수 있는 것은 DB 하나뿐
```

아무도 `zoxide add`를 안 친다 — 사람이 쳐 주는 `tools` 체인의 검사와의 차이가 정확히
"훅"이다. zoxide의 이름 없는 불변식 하나 — `query`의 마지막 키워드가 경로의 마지막
컴포넌트와 맞아야 한다. `add /usr/share/terminfo/x` 뒤의 `query terminfo`는 영원히 못
찾는다(`query x`나 `query terminfo x`). 인자 하나인 `z`가 실제 디렉터리면 DB를 안 보고
그냥 `cd`하는 것도 같은 자리다(lessons 실측 33). 배수 관문(`uname -o` → `GNU/Linux`)의
판정 글자도 타이핑한 줄과 겹치면 안 된다.

## 한 부팅 안에서 되는 것과 부팅을 넘어 되는 것은 다른 검사다

되돌림 D(`XDG_DATA_DIR`을 `/tmp/xdg`로)가 그 모양을 보여 줬다 — 7차("훅이 배웠다")는
초록, 8차("이전 부팅에서 배운 것을 찾는다")만 빨강. 훅은 걸렸고 DB도 쓰였고 틀린 것은
그 DB가 어느 디스크에 있는가뿐이며, 그것은 기계를 한 번 꺼 봐야 드러난다. 8차 부팅이
존재하는 이유 전부가 이 한 줄이다.

"부팅 사이에 남는다"를 적을 때는 기계를 어떻게 끄는지 함께 적는다. 게이트의
`boot_once`는 `kill "$QEMU_PID"`로 전원을 뽑으므로 셸이 나갈 때 하는 일이 하나도 안
일어난다. SM-M2는 7차가 `fc -W`를 직접 치게 했는데 그 우회는 SD-M2가 뺐다 — seed의
`setopt INC_APPEND_HISTORY`가 칠 때마다 쓰므로 필요 없고, `fc -W`는 메모리의 목록으로
파일을 통째로 덮어 다른 세션의 줄을 지운다. 그리고 "실기는 PID 1의 SIGTERM이 있어
안전하다"도 틀렸다 — 대화형 셸은 SIGTERM을 무시한다([[project_shutdown_signals]] ·
[[project_shell_history]]).

## design이 부팅을 세면서 앞 부팅이 남긴 디스크 상태를 안 봤다

M1은 부팅 하나를 더한다고 적었는데 둘이다 — 3차가 심은 `exit`가 `/config/zshrc`에
남아 있고 그것을 읽는 부팅은 셸이 죽어 탈출로가 rc 없이 되살리므로 훅도 안 걸린다.
6차(`tars.noconfig`)가 `rm /config/zshrc`로 수리만 하고 7차에서 init이 그것만 다시
깔아(`O_EXCL`) seed의 훅이 돈다. 한 줄만 지우지 않고 파일을 통째로 지운 것이 요점이다 —
7차의 rc가 정확히 `rcSeed()`의 내용이 되고 `O_EXCL`의 계약을 빈 디스크가 아닌 자리에서
다시 증명한다. 6차는 SC-M2가 `tars.noconfig`를 만든 근거("설정을 고칠 셸이 없을 때")
그대로의 용도다.

## 게이트 자신에게서 찾은 것 — `| grep -q`의 SIGPIPE

`tools/check.sh`의 맨 뒤 음성 확인이 `grep -a … | grep -aq …`였다. `grep -q`는 첫
매치에서 즉시 나가고 아직 로그를 쏟던 앞단이 SIGPIPE로 죽으며, `set -uo pipefail`이
그 141을 파이프라인 코드로 올려 `if`가 "안 맞았다"로 읽는다 — 매치할수록 초록이 되는
검사였고 쓰인 날부터 죽어 있었다. 같은 파일의 다른 검사 주석이 이 함정을 설명하고
있었다 — 아는 것과 안 밟는 것이 다르다. `!` 형이면 거짓 빨강이다(`hangul/check.sh`가
루트 게이트에서 그렇게 죽었다 — 크기가 아니라 경주라 회차마다 갈린다). 처방은 `-q`를
빼서 뒤쪽 grep이 입력을 끝까지 읽게 하는 것.

SM-M0이 센 목록이 `hangul`의 자리를 못 센 이유는 `rg` 패턴이 플래그 끝이 `q`인 것만
찾았는데 그 자리는 `-aqE`였기 때문이다 — "목록을 만들었다"와 "목록이 완전하다"는
다르다. 남은 자리들은 GA가 전부 없앴고 루트 `check.sh`의 진입 검사가 재발을 막는다
([[project_gate_accuracy]]).

## 음성 확인의 첫 회차를 믿을 수 없다

"깨뜨렸는데 첫 회차가 초록"이 따뜻한 캐시에서 5회 중 1회이고, 처방은 두 번 돌리는
것이 아니라 음성 확인 전에 `.zig-cache`와 `zig-out`을 함께 지우는 것이다 — 단, 컨테이너
안에서 지운다(호스트에서 지우면 뒤이은 `zig build`가 9회 중 2회 `error: FileNotFound`로
죽고 그 모양이 컴파일 에러와 구분이 안 된다). 본문은 [[project_zig_out_staleness]].
여기서 한 번 틀리게 적었다가 고쳤다 — "범인은 install 단계"라고 결론 냈는데
`init/build.zig`가 `config_test`를 install하지 않는다. 인과를 문서에 적기 전에 그것이
코드에서 가능한지 먼저 본다.
