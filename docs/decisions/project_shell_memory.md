---
name: project_shell_memory
description: "기계가 사용자에게서 배운 것 둘(자주 간 디렉터리 · 쳤던 명령)을 부팅 너머로 남기는 층(SM) — 2026-09-11 착수, SM-M0 완료. M0은 zoxide·fzf를 게스트에 세우기만 하고 훅은 안 건다. M0이 배운 것 셋: SC 결정 1의 링크 패턴을 기각한 근거 · 판정 글자가 타이핑한 줄과 겹치면 검사가 가짜라는 것과 `..`가 그 처방이라는 것 · fzf 0.60에 셸 통합이 내장돼 있어 .deb의 예제를 안 넣는다는 것. 그리고 M0이 게이트 자신에게서 찾은 것 — tools/check.sh의 맨 뒤 음성 확인이 `grep -q`의 SIGPIPE + pipefail로 쓰인 날부터 죽어 있었다"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-11에 SC가 닫히자마자 이어서 골랐다. UT 비목표 6이
*"셸 설정을 다루는 서브프로젝트가 생기면 그때 함께 온다"*고 `zoxide`·`fzf`를
미뤄 둔 그 자리를 SC가 열었고, SM이 그리로 들어간다.

design은 `docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md`,
milestone 셋(SM-M0·M1·M2)이고 **2026-09-11 현재 M0만 끝났다.**

| | 무엇 | 검증 | 상태 |
|---|---|---|---|
| SM-M0 | 도구 둘이 선다. **훅 없음** | `tools/check.sh`가 둘을 타이핑한다 | **완료** |
| SM-M1 | 훅이 걸린다 | `config/check.sh` 6차 부팅에서 `z tmp` | 미착수 |
| SM-M2 | 배운 것이 남는다 | 7차 부팅이 이전 부팅에서 배운 것을 찾는다 | 미착수 |

관련: [[project_shell_config]](훅을 걸 자리 — `/config`의 rc 셋 — 을 만든
층이고, 그 결정 1을 SM이 기각했다) · [[project_userland_tools]](도구가 서는
구조 전부 — `guest_tools.sh` 배열 하나) · [[project_guest_environment]]
(M2가 env 넷을 더할 자리).

## 다시 조사하지 말 것 셋

### 1. **SC 결정 1의 링크 패턴을 SM이 기각했다**

SC는 `/config`의 rc 셋을 홈에 **심볼릭 링크**로 이었다. 설정 디스크가 없는
부팅에서는 그 링크가 댕글링이 되고, 셸은 없는 rc를 조용히 건너뛴다 — SC에게는
그것으로 충분했다.

**zoxide의 DB에는 그 패턴을 못 쓴다.** 댕글링 링크를 DB 자리로 주면
**`cd`마다 에러 두 줄**이 뜬다. 반면 **없는 경로를 env로 주면 zoxide가
`mkdir -p`하고 `exit 0`한다**(design 실측 4).

그래서 M2는 링크가 아니라 **`XDG_DATA_HOME` 환경 변수**로 자리를 옮긴다.
덤으로 **그 변수 하나가 zoxide DB와 fish 히스토리를 동시에 옮긴다**(실측
3·11) — `_ZO_DATA_DIR`이 필요 없다.

### 2. **판정 글자가 타이핑한 명령줄에 있으면, 그 검사는 도구가 죽어도 초록이다**

`zoxide`·`fzf` 둘 다 **경로를 찍는 도구**라 이 함정에 특히 약하다. 경로는
우리가 방금 타이핑한 것이기 때문이다. 처방이 둘이다.

- **fzf:** 검색어(`descr`)와 판정(`templates/description`)을 **다르게** 한다.
- **zoxide:** `..`를 지나는 경로를 친다 — 정규화해서 저장하므로 DB가
  돌려주는 글자가 화면의 다른 어디에도 없다.

**`..` 셋 글자가 그 검사를 진짜로 만드는 전부다.** M0의 되돌림 2가 그것을
실행으로 봤다 — `..`를 빼면 검사가 도구 없이도 초록이다.

**그런데 zoxide에는 이름 없는 불변식이 하나 더 있었다.** `query`의
**마지막 키워드가 경로의 마지막 컴포넌트와 맞아야 한다.**
`add /usr/share/terminfo/x` 뒤의 `query terminfo`는 **영원히 못 찾는다**
(`query x` 또는 `query terminfo x`여야 한다). design 실측 15가 `fonts`로
쟀을 때는 마지막 컴포넌트가 마침 `fonts`라 드러나지 않았다.

### 3. **fzf 0.60에는 셸 통합이 내장돼 있다 — `.deb`의 예제를 안 넣는다**

`fzf --zsh` / `--bash` / `--fish`가 훅과 자동완성을 함께 낸다(실측 6).
그래서 initrd에 `usr/share/doc/fzf/examples/key-bindings.*`도
`usr/share/fish/vendor_functions.d/fzf_*.fish`도 안 넣는다. **M1의 훅이
파일이 아니라 그 플래그를 쓴다.**

같은 이유로 `fzf-tmux`도 안 넣는다 — tmux가 없다.

## M0이 게이트 자신에게서 찾은 것 — **그물이 쓰인 날부터 죽어 있었다**

**새 도구와 아무 상관 없는 발견이고, M0에서 가장 값지다.**

`tools/check.sh`의 맨 뒤 음성 확인이 이렇게 생겨 있었다.

```bash
if grep -a "terminal: screen>" "$LOG" | grep -aq "Unknown command"; then
```

`grep -q`는 **첫 매치에서 즉시 나가고**, 3.7MB짜리 로그를 아직 쏟고 있던
앞단 grep이 SIGPIPE로 죽는다. 스크립트 맨 위의 `set -uo pipefail`이 그 141을
파이프라인 종료 코드로 올리고 `if`는 그것을 **"안 맞았다"로 읽는다** —
**매치할수록 초록이 되는 검사**였다. 5회 중 5회 재현했다.

**이 파일이 자기 함정에 걸린 것이다.** 같은 스크립트의 검사 1 주석이 이
함정을 설명하며 파이프라인 대신 변수와 case를 쓰고, `fail()`의 `|| true`
(RM-M2)와 `gate_lib.sh:108`도 같은 것을 경고한다. **아는 것과 안 밟는 것이
다르다.**

`-q`를 빼면 뒤쪽 grep이 입력을 끝까지 읽어서 앞단이 SIGPIPE를 안 받는다.

**같은 모양이 저장소에 다섯 더 있다**(`rg '\| *grep -[a-z]*q'`).
`config/check.sh:552`가 **유일하게 조용한 쪽**(`!` 없는 형)이고 **다음
후보다.** 나머지 넷(`config/check.sh:573·576`, `machine/check.sh:226·241·
288·354`)은 `!` 형이라 SIGPIPE가 나면 거짓 **빨강**이고 시끄럽다.

**SM-M0은 자기 그물만 고쳤다** — 다섯은 이 milestone이 만든 것이 아니고,
고치면 그 체인들을 다시 돌려 판정해야 한다.

## 게이트가 배수를 하고 나서 읽는다

검사 19 앞에 `uname -o` → `GNU/Linux`를 기다리는 관문을 넣었다. 셸은 명령을
하나씩 처리하므로 **관문의 출력이 뜬 순간 그 앞의 모든 명령은 이미 실행되고
그려졌다.**

**정직하게: 이 관문은 위의 버그를 고친 것이 아니다.** SIGPIPE를 고친 뒤
관문을 꺼도 잡는다. 안 켜도 잡히는 이유는 그 grep이 3.7MB를 읽는 **동안에도
로그가 자라서** 에러 프레임이 결국 읽히기 때문 — "grep이 게스트보다 느리다"는
**우연한 성질**이었다. 관문은 그 우연을 보장으로 바꾼다.

**관문의 판정 글자도 타이핑한 줄과 겹치면 안 된다** — 위의 "다시 조사하지 말
것 2"가 관문 자신에게도 적용된다.

## M0이 안 건드린 것

| | 왜 |
|---|---|
| `kernel/make_initrd.sh` | **한 글자도 안 고쳤다.** 배열에 줄 둘을 더한 것이 전부다 — UT-M1 결정 7의 구조가 바깥에서 온 새 도구에도 선다는 증명 |
| Zig 코드 전부 | M1이 `config.zig`의 `rcSeed()`와 `config_test.zig`의 `expectQuietSeed`를, M2가 `environ.zig`를 건드린다 |
| `config/check.sh`의 6·7차 부팅 | M1·M2의 일이다 |
| `git-delta` | 비목표 1 — 사용자가 이번 범위에서 뺐다 |
