---
name: project_host_checks
description: "tars-config · tars-install의 시스템 콜 쪽에 남은 순수한 것(argv 가르기 · init 답 읽기 · 조건이 고르는 문장)을 짝(config_edit · config_front_edit · disk)으로 내린 Host Checks(HC-M0~M2, 2026-10-26). 출력 바이트 · exit code · build.zig 0 변경 · 거절도 union의 칸, 시스템 콜과의 순서 때문에 칸을 따로 · 여러 줄은 sink(print가 있는 것) · 검사는 서식 리터럴 집합 diff · want는 옮기기 전 코드에서 · mutation 둘 · 짝 줄 수"
metadata:
  type: project
---

# Host Checks (HC)

2026-10-24 프로젝트 점검이 남긴 셋 가운데 (3)을 사용자가 골랐다(2026-10-25). 설계는
`docs/specs/2026-10-25-tars-host-checks-design.md`, plan은 `docs/plans/2026-10-25-tars-host-checks-hc-m0.md` ·
`docs/plans/2026-10-26-tars-host-checks-hc-m{1,2}.md`.

## 무엇을 세웠나

TC · DI가 이미 "시스템 콜 쪽 ↔ 순수 짝"으로 갈라 둔 세 실행 파일 쪽에서, 아직 시스템 콜 쪽에 남은 순수한 것을 짝으로 내리고 짝의
호스트 검사에 글자를 박았다. 출력 바이트 · exit code · 체인 스크립트 · `build.zig`는 0줄 바뀌었다.

- M0 — `config_cli` → `config_edit`: `parseCommand → Command`(동사 열넷), init 답 읽기 `nowValue` · `screenLine`(검사가
  `reload.configReply`가 지은 답을 그대로 넣어 왕복으로 본다), `changeLine` · `keyTable` · `showKeyLines` · `checkLines`. `main`은
  `switch` 하나.
- M1 — `config_front` → `config_front_edit`: 인자 union 다섯(`wifiArgs` · `sshArgs` · `sshKeyArgs` · `firewallArgs` · `dictationArgs`),
  `firewallChange`(allow는 빈 파일이면 `RULES_HEADER` 위에), `wifiDone` · `firewall22` · `firewallSaid` · `dictationApply` ·
  `dictationUnknown` 등.
- M2 — `install` → `disk`: `sectorsToBytes`, `State` union과 `headState`(문자열 비교 둘이 `switch`로), `listRow` · `planLines` ·
  `toolOk` · `usageLines`. 검사 18이 `install/check.sh`의 `LIST_END=`를 런타임에 읽어 usage 마지막 줄과 견준다.

줄 수 — `config_cli` 622 → 522, `config_front` 639 → 589, `install` 678 → 656. 짝은 `config_edit` 299 → 485, `config_front_edit`
241 → 484, `disk` 270 → 361. 둘이 500에 가깝다 — 다음에 동사를 더해 넘으면 "동사별 파일"을 후보로 적는다(design 위험 6).

## 결정

- 거절도 union의 칸이다. 칸을 거절마다 따로 두는 것은 시스템 콜 쪽이 지금의 순서를 지키게 하려는 것이다 — `ssh foo`는 `needDisk`
  뒤에 usage라 디스크가 없으면 exit 2(`bad_verb`), `dictation set`의 쌍 거절 셋도 `needDisk` 뒤, `firewall`은 파일을 읽은 뒤에
  가른다. 가르기 함수는 순수해서 언제 불러도 같지만 그 결과에 반응하는 순서는 시스템 콜 쪽의 것이다.
- 짧게 끊는 시스템 콜은 안 내려간다. `stateOf`의 앞 둘(매체 경로 비교 · `isInstalled`)은 `install`에 남았다 — `isInstalled`는 p1을
  붙여 보므로 매체 디스크에서 부르면 동작이 바뀐다. design 결정 8의 "순서 전체를 순수 함수로"를 M2 plan 확정 3이 이렇게 고쳤다.
- 여러 줄은 `sink: anytype`(`print(fmt, args)`가 있는 것)다. design 결정 6의 "한 버퍼에 이어 짓고 `writeAll` 한 번"을 M0가 바꿨다 —
  `checkLines`의 출력이 파일 줄 수에 비례해서다. 시스템 콜 쪽은 줄마다 `say` 한 번인 `Say`(`config_cli`의 것을 `pub`으로,
  `install`은 `Say` · `Complain` 따로), 검사는 `control.Out`.
- 경로는 문장 함수의 인자다 — 서식 문자열의 `{s}`가 그대로여야 집합 diff가 빈다. 경로 상수는 여는 쪽에 남는다.

## 함정 · 검사법

- "글자가 그대로"의 기계판은 서식 리터럴 집합 diff다. 정규식
  `\b(say|complain|print|bufPrint)\(\s*(?:[&\w\[\]\.]+,\s*)?"(?:[^"\\]|\\.)*"`를 `rg -o --multiline`으로 뽑아 리터럴만 남기고 `sort`,
  실행 파일 단위 파일 집합(tars-config 넷 · tars-install 둘)으로. 첫 Task(더하기만) 뒤는 `>`만, 둘째 Task(지우기) 뒤는 빈 diff.
  여러 줄 리터럴(`\\`)은 이 정규식에 안 걸린다 — 그래서 usage가 상수가 아니라 `usageLines` 함수다.
- want는 옮기기 전 코드의 서식 문자열에서 베낀다(옮긴 함수의 출력에서 베끼면 tautology). 고정 폭 행은 서식의 칸마다 조각을 `++`로
  이어 적으면 폭이 눈으로 대조된다.
- mutation은 사본을 `-v 사본:/workspace/init/src/x.zig:ro`로 덮어 `zig build test`만 돈다. 비튼 뒤 원본과 `diff`부터 본다 — `sd`에
  개행을 넣은 패턴이 안 맞아 원본 그대로 돈 적이 있다(M2 m1의 첫 시도, exit 0). M1 · M2의 문장 mutation은 게이트가 안 치는
  문장(`not opened by tars-config` · `rest unallocated`)을 호스트에서 잡았다.
- `config_front_edit`가 `config_edit`(→ `config.zig`)를 import해도 `tars-init:` 줄은 안 샌다 — 새 함수가 `parse`를 안 부른다. 검사
  표준 에러의 그 줄 수(58)를 Task마다 셌다.
- service 체인의 ssh 문장은 게스트 로그에 없다 — 검사 27이 ssh로 받은 `$OUT`을 본다. 로그에서 글자를 못 찾으면 체인이 어디서
  읽는지부터 본다.
- 0.17에는 `"a" ** 32`가 없다(lessons "안 되는 접근").
- 루트 게이트는 milestone마다 한 번 — M0 21/22(install 부팅 7, 부하 flake) 뒤 22/22, M1 · M2 첫 회 22/22(9분 44초 · 10분 5초).
