# TARS Host Checks — Design

Date: 2026-10-25
Status: 진행 중 — HC-M0 · HC-M1 완료(2026-10-26, 루트 게이트 22/22 각각). plan은 milestone마다 하나 — `docs/plans/2026-10-25-tars-host-checks-hc-m0.md` · `docs/plans/2026-10-26-tars-host-checks-hc-m1.md` · `docs/plans/2026-10-26-tars-host-checks-hc-m2.md`(초안).

HANDOFF "다음 후보"의 첫 항목에서 시작한다(2026-10-24 프로젝트 점검이 남긴 셋 가운데 추천 1순위. 사용자가 2026-10-25에 골랐다).

> 호스트 검사가 없는 큰 파일 셋 `config_cli.zig` 622 · `config_front.zig` 639 · `install.zig` 679 — 인자 파싱과 문장 조립은 호스트
> 검사로 내려올 수 있다.

## 한 줄 요약

세 파일은 TC와 DI가 이미 "시스템 콜 쪽"으로 갈라 둔 쪽이고, 순수한 짝(`config_edit.zig` · `config_front_edit.zig` · `disk.zig`)과 그
호스트 검사 셋(`config_edit_test` · `config_front_edit_test` · `disk_test`)이 이미 있다. 이번 일은 시스템 콜 쪽에 아직 남아 있는
순수한 것 — argv 가르기 · init의 답과 파일 글자 읽기 · 사람에게 찍는 문장 조립 — 을 그 짝으로 내리고, 짝의 검사에 그 글자를 박는 것이다.
출력 바이트와 exit code는 하나도 바뀌지 않고, 새 파일도 `build.zig`의 새 줄도 없다.

## 배경

### 세 파일은 설계대로 "시스템 콜 쪽"이다

점검은 줄 수로 봤고 그 수는 맞다. 다만 세 파일의 머리 주석이 말하듯 그것은 가름의 결과다 — TC-M0가 `config_cli` ↔ `config_edit`,
TC-M1이 `config_front` ↔ `config_front_edit`, DI-M1이 `install` ↔ `disk`를 갈랐고, 순수한 쪽만 호스트가 본다. 그러니 질문은 "검사가
없다"가 아니라 "시스템 콜 쪽에 순수한 것이 얼마나 남았나"다.

| 파일 | 줄 | `say` | `complain` | `linux.` 호출 | 순수 짝 (줄) | 짝의 검사 (줄) |
|---|---|---|---|---|---|---|
| `config_cli.zig` | 622 | 36 | 25 | 14 | `config_edit.zig` 299 | `config_edit_test.zig` 269 |
| `config_front.zig` | 639 | 41 | 36 | 34 | `config_front_edit.zig` 241 | `config_front_edit_test.zig` 164 |
| `install.zig` | 678 | 29 | 25 | 57 | `disk.zig` 270 | `disk_test.zig` 339 |

`say` · `complain`이 셋 합쳐 192자리다. 그 서식 문자열이 사람이 읽는 답이고 게이트 여섯 체인이 보는 글자인데, 그 글자를 지키는
호스트 검사가 없다 — 지금은 게이트가 유일한 그물이고, 게이트가 안 치는 문장(아래 확인 7)은 그물이 없다.

### 시스템 콜 쪽에 남아 있는 순수한 것

`config_cli.zig`:

- `main`(550~622줄, 73줄) — 동사 열넷의 가르기. `help` · `-h` · `--help`, `version` · `--version` · `-V`, `list`, `unset`(거절과 한 줄),
  `reload [terminal]`, `check`, 앞문 다섯, `get KEY`, `set KEY=VALUE…` · `reset KEY…`(쌍 가르기 — 첫 `=` · 양쪽 공백 · `PAIRS_MAX`).
  `disk.parseArgs → Command`가 같은 일을 이미 순수하게 하는 선례다.
- `nowValue(reply, key)` · `screenLine(reply)` — init의 `config` 답을 읽는 둘. 답을 짓는 쪽은 `reload.configReply`(순수, `reload_test`가
  본다)인데 읽는 쪽은 검사가 없다 — 두 벌이 어긋나면 게스트에서만 드러난다.
- `change`의 판정 다섯 갈래의 문장과 결과 문장(`{key}: {old}{ (default)} -> {new}` · `(unchanged)`), `show`의 키 줄
  (`{mark}{key}={value}` · `init uses … now`), `check`의 글자만 보는 셋(길이 · 줄마다 `parse` · 같은 키 여러 줄 `is on N lines (1, 3)`),
  `keyTable`.

`config_front.zig`:

- 동사 다섯의 인자 가르기 — `wifi SSID [--country CC]`(위치 셋 고정 · SSID 1~32바이트 · 제어 문자), `ssh [on|off]`,
  `ssh-key list | add [KEY]`(한 줄 검증), `firewall [allow|deny PORT]`(`parsePort`는 이미 순수), `dictation [key [KEY] | set K=V…]`
  (쌍마다 `=` · 키 이름 여덟 · 제어 문자).
- 글자만 보는 것 — `wifiStatus`의 줄 고르기(`ssid=` · `country=`만), `firewall` 상태의 줄 고르기(주석 · 빈 줄 제외), `firewall`의 바뀜
  계산(allow: 있으면 null 아니면 `RULES_HEADER` 위에 더함, deny: 없으면 null 아니면 뺌), `dictation set`의 `setLine` 루프,
  `check`의 `dictation.conf` 모르는 키 줄 번호.
- 문장 — 동사마다 "다음에 무엇을 하면 되는지"의 줄들(`apply now: …` · `net=off: …` · `sshd is off: …`). 같은 조건이 같은 문장을 고르는
  것이 호스트에서 볼 것이다.

`install.zig`:

- 이미 `disk.zig`에 내려간 것이 많다 — `parseArgs` · `confirmed` · `formatSize` · `stateText` · `espConf` · `clip` · `knownDisk` · `sysName`.
- 남은 것 — `sizeBytes`의 `sectors * 512`(글자 → 바이트), `stateOf`의 순서(매체 경로와 같다 → `boot medium`, 설치됨 → `TARS installed`,
  TARS ISO → `boot medium`, 그 밖은 `stateText`), `list`의 행 서식(`{s:<14} {s:>7}  {s:<22} {s:<9}  {s}` · `removable`의 `"1"` →
  `removable`/`internal`), `install`의 계획 문장(갱신 · 새 설치 · `p2HasSettings`에 따라 넷~여섯 줄), `runTool`의 실패 문장
  (`failed (exit N)` · `was killed (signal N)` — `audio.outcome(status)`가 같은 판정을 순수하게 한 선례), `printUsage` 세 줄(install
  체인이 마지막 줄을 목록의 끝으로 기다린다).

### 왜 지금

MS가 두 `main`을 쪼개 "다음 기능이 들어갈 자리"를 만든 것처럼, 이것은 "다음 동사 · 다음 키가 들어갈 자리"를 만드는 일이다. 지금
`tars-config`에 동사를 하나 더하면 `main`의 `if` 사다리에 줄이 늘고 그 문장은 게이트가 부팅해야 본다. 가르기와 문장이 순수 쪽에 있으면
새 동사는 `Command`의 칸 하나와 검사 몇 줄로 시작한다. 그리고 TC design 결정 3 · 10이 "글자는 순수 쪽, 시스템 콜은 이쪽"이라 적었는데
그 선이 지금 코드에서 흐려진 자리를 되찾는 일이기도 하다.

## 착수 전에 확인한 것

2026-10-25, HEAD `b88ad8d`.

1. 줄 수 · `say` · `complain` · `linux.` 수는 위 표다(`wc -l` · `rg -c`).
2. 이 저장소의 호스트 검사는 `test` 블록이 아니라 `main`이 있는 실행 파일이다(`rg '^test ' init/src/*_test.zig`가 0줄). 실패하면
   `FAIL:` 줄과 0이 아닌 코드, 끝에 `PASS`. `build.zig`가 `addExecutable` + `addRunArtifact`로 `test` step에 건다. 검사 열일곱이
   걸려 있고, 세 짝의 검사는 그 안에 있다 — 새 검사 파일을 만들면 `build.zig`에 모듈 하나(열 줄쯤)가 늘고, 기존 파일에 더하면 0줄이다.
3. `config_edit_test.zig`는 root이고 `pub const configLog = edit.configLog`를 선언해 `config.zig`의 로그를 가로챈다(`judge`가 듣는 길).
   `config_front_edit_test.zig`는 선언하지 않는다 — `config_front_edit.zig`가 `config.zig`를 import하지 않아서다. `config_front.zig`의
   `dictation`은 함수 안에서 `@import("config_edit.zig")`를 한다 — `setLine`을 쓰기 위해서다.
4. `disk.parseArgs(args) → Command`(union: `list` · `install{disk, yes, wipe}` · `usage`)가 argv 가르기의 선례다. 가른 슬라이스는 argv를
   가리키고 argv는 프로세스 수명이다. `disk_test`가 열 갈래쯤 본다.
5. `reload.configReply(out, live, screen)`가 `config` 답을 짓고 `screenLines`가 `screen …` 줄을 짓는다 — 둘 다 순수(`control.Out`에
   쓴다). `config_cli`의 `nowValue` · `screenLine`은 그 답을 읽는 쪽이다. 한 검사가 둘을 왕복으로 볼 수 있다(SA-M0의 `encode` ↔ `decode`
   검사와 같은 모양).
6. 문장을 버퍼에 짓는 선례 — `disk.stateText(buf, seen)` · `disk.clip(buf, fmt, args)` · `fe.ruleLine(buf, spec)` ·
   `audio.outcome(status) → Outcome`(판정을 돌려주고 글자는 부르는 쪽). 여러 줄을 짓는 선례 — `reload.keyLines(out: *Out, …)`.
7. 게이트가 보는 문장. `rg -l`로 `*/check.sh`를 뒤진 결과 — 잡히는 것: `nothing was written` · `init would say` · `init reads every line`
   (config), `wifi: `(wifi), `sshd: ` · `ssh-key: `(service), `firewall: `(firewall), `dictation: ` · `wrote /config/groq.key`(dictation),
   `type YES` · `already has TARS` · `not confirmed` · usage 마지막 줄(install). 안 잡히는 것: `will be erased` ·
   `is not a disk tars-install knows` · `problem(s)` · `is on N lines` · `apply it now` · `has no '='` · `unset`의 한 줄 · `--country` ·
   `deny` · `firewall=off`의 말(TC 기억 "남긴 것"의 넷). 안 잡히는 문장의 그물은 지금 없다.
8. `tars-config`를 치는 체인은 config · wifi · service · firewall · dictation 다섯, `tars-install`은 install 하나다. 다른 열여섯 체인은
   두 바이너리를 initrd에 싣기만 한다.
9. 작은 헬퍼의 중복 — `failed`가 `config_cli` · `install` · `main` · `storage`에, `writeAll`이 `config_cli` · `install`에, `fileExists`가
   `config_cli` · `config_front`에 각자 있다. `devices.zig` 372줄의 규칙("세 줄짜리 헬퍼 하나 때문에 공용 모듈을 만들지 않는다")이
   그것을 허용한다. 이번 일과 무관하다(비목표 1).
10. `say`가 한 줄마다 `write` 한 번이다. 출력은 셸의 PTY로 가고 게이트는 화면 · 시리얼에서 읽는다 — `write`가 몇 번인지는 어디에도
    안 보인다. 여러 줄을 버퍼 하나에 지어 한 번에 써도 바이트는 같다.
11. `config_front.zig`의 `firewall`이 `fe.keyCount(text)`를 `check`에서 nft 파일의 규칙 수로 쓴다 — `keyCount`는 "주석 · 빈 줄 아닌 줄의
    수"라 맞게 동작하지만 이름이 다른 파일의 것이다. 옮기면서 이름을 고칠 자리가 아니다(동작 0줄, 비목표 2) — 기억에 적는다.

## 결정

### 결정 1. 내려가는 것의 기준은 "시스템 콜이 없고, 입력이 바이트, 출력이 판정이나 글자"다

함수 하나가 내려가는 조건은 셋이 다 맞을 때다 — `linux.`를 부르지 않는다, 입력이 argv · 파일 글자 · init의 답 같은 바이트다, 출력이
union/enum의 판정이거나 호출자가 준 버퍼 속 글자다. 한 함수 안에 둘이 섞였으면(`change` · `wifi` · `install`) 가른다 — 순수한 반을 함수로
빼고 시스템 콜 쪽은 그 함수를 부른 뒤 결과를 `say`한다. 시스템 콜 쪽에 남는 것은 열고 · 읽고 · 쓰고 · fork하고 · 묻는 것과 그 사이의 순서다.

이 기준에서 안 내려가는 것 — `readSecret`(termios) · `run` · `runTool`(fork) · `replace` · `ensureDir` · `findMedium` · `isInstalled` ·
`fillEsp` · `copyFile`. 그리고 `show` · `check`처럼 시스템 콜 결과 여럿을 순서대로 엮는 함수의 뼈대는 남고, 그 안의 글자 조각만 내려간다.

### 결정 2. 출력 바이트 · exit code는 0 변경이다. 검사는 셋이다

`say` · `complain`의 서식 문자열과 그 순서, exit code가 그대로다. 체인 스크립트는 편집하지 않는다. "그대로"를 보는 길은 셋이다.

- (a) 서식 문자열 집합의 전후 `diff`. 실행 파일 단위로 묶어 뽑는다 — `tars-config`는 네 파일(`config_cli` · `config_edit` ·
  `config_front` · `config_front_edit`), `tars-install`은 두 파일(`install` · `disk`). 문장이 파일 사이를 옮기므로 파일 단위 집합은 바뀌고
  실행 파일 단위 집합은 안 바뀌어야 한다. 뽑는 명령은 plan이 정한다(`rg -o` · `sort`).
- (b) `git diff --color-moved=dimmed-zebra`. 옮긴 줄은 흐리고 새로 쓴 줄(함수 머리 · `Command` 칸 · 검사)만 진하다 — MS design 결정 1(b)의
  읽는 법 그대로다. 다만 이번은 파일 사이의 이동이라 `--color-moved`가 짝을 짓는 범위를 `-M`이 아니라 diff 전체로 둔다(기본값이 그렇다).
- (c) 호스트 검사가 문장을 글자 그대로 박고, 그 실행 파일을 치는 체인(확인 8)이 게스트에서 같은 글자를 본다.

### 결정 3. 새 파일은 만들지 않는다. `build.zig`는 0줄이다

내려가는 자리는 이미 있는 짝 셋이고 검사도 이미 있는 셋에 더한다.

| 시스템 콜 쪽 | → 순수 짝 | 검사 |
|---|---|---|
| `config_cli.zig` | `config_edit.zig` | `config_edit_test.zig` |
| `config_front.zig` | `config_front_edit.zig` | `config_front_edit_test.zig` |
| `install.zig` | `disk.zig` | `disk_test.zig` |

이유는 둘이다. 짝의 머리 주석이 이미 "글자를 다루는 것은 전부 여기"라 적혀 있어 자리가 그곳이고, 검사 파일을 새로 내면 `build.zig`에
모듈이 늘고(확인 2) `GP-M2`의 `scratch.enter` 같은 관례를 하나 더 챙겨야 한다. 짝이 커지는 것(`config_edit` 299 → 450줄쯤)은 받는다 —
순수 파일은 길어도 호스트가 0.1초에 다 본다.

### 결정 4. argv는 `Command` union 하나로 가른다 — `disk.parseArgs`의 모양

`config_edit.parseCommand(argv[1..]) → Command`가 `tars-config`의 동사 열넷을 가른다. 칸은 동사마다 하나이고, 거절도 칸이다 —
`usage`, `unset`(한 줄과 usage), `no_equals: []const u8`(`'{s}' has no '='`), `unknown_key: []const u8`(reset의 모르는 키). 시스템 콜
쪽의 `main`은 `switch (cmd)` 하나가 되고 갈래마다 지금 부르는 함수를 부른다. 앞문 다섯은 `front_*: []const [*:0]const u8`로 나머지
인자를 그대로 넘긴다 — 그 안의 가르기는 결정 5다.

슬라이스는 argv를 가리킨다(프로세스 수명, 확인 4). `reset`의 기본값 글자는 지금처럼 호출자의 `default_bufs`에 짓는다 — `parseCommand`가
버퍼를 인자로 받는다. `set`의 쌍은 `edit.Pair`로 지금과 같다.

### 결정 5. 앞문 다섯의 인자도 각자 `Command`다

`config_front_edit`에 `wifiArgs` · `sshArgs` · `sshKeyArgs` · `firewallArgs` · `dictationArgs`가 들어가고 각자 union을 돌려준다.
거절의 이유가 칸이다 — `wifi`의 `bad_country` · `bad_ssid`, `ssh-key add`의 `bad_line`, `firewall`의 `bad_port`, `dictation set`의
`no_equals` · `unknown_key` · `control_byte`. 지금 `complain`이 찍는 문장은 시스템 콜 쪽의 `switch`에 그대로 남는다 — 문장은 사람에게
가는 것이고 판정은 검사가 보는 것이라, 둘을 가르면 검사가 문장 글자 대신 판정을 본다.

문장도 보고 싶은 자리(게이트가 안 치는 `--country` · `deny` · `firewall=off`, 확인 7)는 결정 6의 문장 함수로 내린다.

### 결정 6. 문장은 호출자의 버퍼에 짓고, 여러 줄은 한 버퍼에 이어 짓는다

한 줄은 `disk.stateText(buf, seen)`의 모양 — `fn x(buf: []u8, …) []const u8`. 여러 줄(install의 계획 넷~여섯 줄 · `check`의 중복 키 줄 ·
`list`의 표)은 같은 모양으로 한 `[]u8`에 이어 짓고 시스템 콜 쪽이 `writeAll(1, text)` 한 번으로 쓴다(확인 10 — 바이트는 같다). `say`의
버퍼 상한(`READ_MAX + 256` · install은 512)은 그대로 두고, 여러 줄 함수의 `out`은 그 줄 수에 맞게 호출자가 잡는다.

내려가는 문장의 기준은 "조건이 문장을 고른다"다 — `if (update) … else …`, `if (existed) … else …`, `placed.replaced ? "replaced" :
"added"`. 조건 없이 늘 같은 한 줄(`say("tars-install: syncing\n")`)은 옮기지 않는다 — 검사가 볼 것이 없다.

### 결정 7. init의 답을 읽는 둘은 짓는 쪽과 왕복으로 본다

`nowValue` · `screenLine`은 `config_edit`로 가고, 검사는 `reload.configReply` · `reload.screenLines`가 지은 답을 그대로 넣어 읽는다
(확인 5). 두 벌이 어긋나면 — 답의 모양을 reload 쪽에서 바꾸고 읽는 쪽을 잊으면 — 게스트가 아니라 호스트에서 빨개진다. `config_edit`가
`reload.zig`를 import하지는 않는다(의존 방향 — reload는 PID 1의 것). 검사 파일만 둘을 함께 import한다.

### 결정 8. install의 것은 `disk.zig`로 — 판정은 enum, 글자는 버퍼

- `sectorsToBytes(text) ?u64` — `sizeBytes`의 글자 쪽. 공백 벗기기 · `parseInt` · `* 512`.
- `State` enum { medium, installed, other }와 `stateOf`의 순서를 정하는 순수 함수 — 입력은 `is_medium_path: bool` · `installed: bool` ·
  `seen: Seen`. `STATE_MEDIUM` · `STATE_INSTALLED` 글자가 `disk.zig`로 간다(install이 그 글자로 갈래를 고르므로 한 곳에).
- `listRow(buf, path, size, model, removable_text, state)` — 행 서식과 `"1"` → `removable`.
- `planText(buf, …)` — 갱신 · 새 설치의 넷~여섯 줄. `type YES to continue: `는 그 뒤의 별도 `say`로 남는다(개행 없이 끝나는 질문이라 따로다).
- `toolFailure(buf, tool, status)` — `audio.outcome`의 모양으로 `failed (exit N)` · `was killed (signal N)`.
- `USAGE` 세 줄 — `printUsage`의 글자. install 체인이 마지막 줄을 기다리므로 검사가 마지막 줄을 글자 그대로 박는다.

### 결정 9. 검사의 want는 옮기기 전의 코드에서 베낀다

호스트 검사의 기대 글자는 옮긴 뒤의 함수 출력에서 베끼지 않는다 — 그러면 tautology다(lessons "폭 고정 칸의 기대 글자는 검사 출력에서
베낀다"의 반대 방향 주의). plan의 첫 Task가 옮기기 전 코드의 서식 문자열을 그대로 want로 적고, 둘째 Task가 옮기고, 셋째가 검사를 돌린다.
게이트가 안 치는 문장(확인 7)은 이 want가 유일한 그물이 된다.

### 결정 10. mutation으로 그물을 한 번 당겨 본다

milestone마다 둘 — 가르기 하나(예: `--country`의 위치를 바꾼다)와 문장 하나(예: `(default)`를 지운다)를 사본에서 비틀어 `zig build test`가
먼저 빨개지는 것을 본다. TC-M1 plan Task 4의 방식(사본 · 되돌림 포함)이고, 게이트까지 가지 않는다 — 호스트 검사가 부팅 앞에서 잡는 것을
보는 것이 이 서브프로젝트의 뜻이다.

### 결정 11. 게이트 — 반복은 `zig build test`와 체인 하나, 닫기는 루트 게이트

편집 사이의 반복은 컨테이너의 `zig build test`(초 단위)와 그 실행 파일을 치는 체인 하나(`make check CHAIN=config` 등)다. milestone을
닫을 때는 루트 게이트 한 번(22/22, 10분쯤) — 바이너리가 모든 체인의 initrd에 실리므로 MS와 같은 규칙이다. 호스트 0.17의
`zig fmt --check` · `ast-check`는 컨테이너 빌드 앞에 돈다.

### 결정 12. 주석은 함께 간다

`say`의 조건 위에 붙은 주석(어느 milestone이 왜 이 문장을 골랐나)은 문장 함수의 문서 주석으로 간다. `main`의 `unset` 주석("언세팅은
reset이다")은 `Command.unset` 칸의 주석으로. 지우는 것은 없다. 세 파일의 머리 주석은 "글자를 다루는 것은 전부 짝"이라 이미 적혀 있어
고칠 것이 없다.

## Milestone

- HC-M0 — `tars-config`의 뼈대(결정 4 · 7 · 2 · 6의 `config_cli` 쪽). `parseCommand` · `nowValue` · `screenLine` · `change`의 결과
  문장 · `check`의 중복 키 문장 · `show`의 키 줄. 체인은 config.
- HC-M1 — 앞문 다섯(결정 5 · 6의 `config_front` 쪽). 인자 union 다섯 · 상태의 줄 고르기 둘 · firewall의 바뀜 계산 · dictation set의
  판정 · check의 모르는 키. 체인은 wifi · service · firewall · dictation.
- HC-M2 — `tars-install`(결정 8). 체인은 install. plan은 앞 milestone의 게이트가 끝난 뒤 쓴다.

순서의 이유 — M0가 `Command` union의 모양을 정하고 M1 · M2가 그 모양을 따른다. 셋 중 install이 마지막인 것은 `disk.zig`에 이미 가장 많이
내려가 있어 남은 것이 가장 적기 때문이다.

## 위험

1. 문장 글자가 바뀐다. 가장 큰 위험이고 컴파일러가 못 잡는다 — 서식 문자열을 옮기며 공백 하나 · 개행 하나가 달라지는 것. 막는 길은 결정
   2(a)의 집합 diff와 결정 9의 "옮기기 전에 베낀 want"다. 게이트가 치는 문장은 체인이 한 번 더 본다.
2. 순서가 바뀐다. `check`에서 중복 키 줄은 `bootRefuses` 앞 · 줄마다 `parse` 뒤다. `show`에서 `init uses … now` 줄은 그 키 줄 바로 밑이다.
   문장 조각을 함수로 빼도 부르는 자리는 그대로여야 한다 — 결정 2(b)로 읽는다.
3. `edit.heard`는 전역이다. `check`의 줄마다 `parse`가 `heard`를 매번 비우고 읽는다. 그 루프를 `config_edit`로 내리면 전역을 만지는
   자리가 순수 파일 안이 되는데, `judge`가 이미 그렇게 하므로 새 모양은 아니다. 검사 파일이 root로서 `configLog`를 선언해야 하고
   `config_edit_test`는 이미 한다(확인 3).
4. `config_front_edit`가 `config_edit`를 import하게 된다(`dictation set`의 `setLine`, 확인 3). 순수 ↔ 순수라 괜찮지만
   `config_front_edit_test`가 `configLog`를 선언하지 않아 `config.zig`의 로그가 표준 에러로 새어 나올 수 있다 — `setLine`은 `parse`를
   부르지 않으므로 새지 않을 것이다. plan이 `zig build test`의 표준 에러를 한 번 본다.
5. 슬라이스 수명. `Command`의 슬라이스는 argv를, 문장은 호출자 버퍼를 가리킨다 — 지금 지역 변수가 가리키는 것과 같다. `disk.parseArgs`가
   같은 모양으로 이미 산다(확인 4).
6. 짝이 커진다. `config_edit` 299 → 450줄쯤, `config_front_edit` 241 → 400줄쯤. 순수 파일이라 받는다(결정 3). 500줄을 넘으면 그때
   "동사별 파일"을 다음 후보로 적는다.
7. 문서가 함수 이름을 인용한다 — lessons "핵심 파일"의 `config_cli` · `config_front` · `install` 줄, `project_config_tool`의 "자리" 절.
   닫을 때 lessons의 세 줄은 고치고 decisions는 찾아다니지 않는다.

## 비목표

1. 작은 헬퍼의 통합(`failed` · `writeAll` · `fileExists`, 확인 9). `devices.zig`의 규칙 그대로다.
2. 문장 · 동작 · exit code의 변경. `keyCount`의 이름(확인 11)도, `has no '='`의 말도 그대로다.
3. 시스템 콜 쪽 함수의 모양(`run` · `runTool` · `readSecret` · `replace` · `findMedium` · `isInstalled`). 이미 함수다.
4. 새 체인 · 새 검사 파일 · `build.zig` 편집.
5. 소개 페이지(`gh-pages` `data.js`). 기능이 아닌 내부 작업은 타임라인에서 건너뛴다(사용자 결정, 2026-10-25).
6. 점검의 나머지 둘(lessons 분할 · `.github`). 각자 서브프로젝트다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_host_checks.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`의 후보 (3) 지우기.
- lessons "핵심 파일"의 세 줄 — `config_cli` · `config_edit`의 줄에 `parseCommand` · 답 읽기 둘을, `config_front` · `config_front_edit`의
  줄에 인자 union 다섯을, `install`의 줄에 `disk.zig`로 간 것을.

## 관련

- `docs/decisions/project_config_tool.md` — 순수 ↔ 시스템 콜의 가름(TC 결정 3 · 10)과 게이트가 못 보는 넷. 이번의 출발점.
- `docs/decisions/project_disk_install.md` — `disk.zig`가 `install.zig`에서 갈라진 이유와 `parseArgs`의 모양.
- `docs/decisions/project_main_split.md` — 동작 0줄 변경과 `--color-moved`로 읽는 법. 이번의 검사 (a) · (b)가 그것이다.
- `docs/decisions/project_audio_devices.md` — `outcome(status)`, wait status를 순수하게 판정한 선례.
- `docs/decisions/project_config_reload.md` — `configReply` · `screenLines`, 이번에 읽는 쪽과 왕복으로 보는 짓는 쪽.
- `docs/decisions/feedback_execution_scope.md` — 구현은 Claude가, 사용자의 검토는 읽기. 결정 2(b)가 그 읽기의 도구다.
