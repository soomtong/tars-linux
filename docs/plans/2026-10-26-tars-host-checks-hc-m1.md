# HC-M1 — 앞문 다섯의 가르기와 문장을 `config_front_edit`로 내린다

Date: 2026-10-26
Design: `docs/specs/2026-10-25-tars-host-checks-design.md` 결정 1 · 2 · 5 · 6 · 9 ~ 12
Status: 초안 — HC-M0 루트 게이트가 도는 동안 썼다. 게이트 결과와 대조한 뒤 구현에 넘긴다.

## 누가 무엇을 하나

고치는 파일은 셋이다 — `init/src/config_front_edit.zig`(더한다) · `init/src/config_front_edit_test.zig`(더한다) ·
`init/src/config_front.zig`(뺀다). `build.zig`는 0줄이다 — `config_front_edit_test` 모듈에 `screen_args`가 이미 걸려 있어
`config_front_edit`가 `config_edit`(→ `config.zig` → `screen_args`)를 import해도 그대로 컴파일된다(2026-10-26 `build.zig` 320줄 확인).
lead가 직접 넣는다(M0와 같은 이유). Task마다 commit 하나다.

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | `config_front_edit`에 인자 union 다섯 · 판정 · 문장 함수, `config_front_edit_test`에 검사 5 ~ 9. `config_front`는 그대로 | `zig build test` · (a) `>`만 |
| 2 | `config_front`가 그 함수를 부른다 | 빌드 · (a) 빈 diff · `--color-moved` · 체인 넷 |
| 3 | 호스트 `fmt` · `ast-check`, mutation 둘, 루트 게이트, 실측 | 22/22 |

## 착수 전에 확정한 것

1. 검사 명령은 M0의 것 그대로다 — `/tmp/hc-fmt.sh`(M0 plan 확정 1, 리터럴만 견주는 판). 네 파일 합이라 M0 뒤의 기준선도
   151줄이다(M0가 집합을 안 바꿨다). Task 1 전에 다시 뽑는다.

   체인은 넷이다 — `make check CHAIN=wifi` · `service` · `firewall` · `dictation`. 그 체인이 이 milestone의 글자를 보는 자리:
   `wifi: tars-wl replaced in /config/wpa_supplicant.conf` · `apply now: tars-service restart wpa_supplicant`(wifi 296),
   `ssh-key: added 256 SHA256:… (ED25519)` · `ssh-key: already there` · `tars-config: ssh-keygen does not read this as a public key` ·
   `sshd: off — tars-config reload stops it now`(service 572 ~ 602), `applied now: nft -f /etc/tars/firewall.nft`(firewall 364),
   `dictation: wrote /config/groq.key (0600, 7 characters)` · `dictation: transcribe_url=…|dictation: max_seconds=1|` ·
   `tars-config: unknown dictation key 'colour'`(dictation 448 ~ 453). 안 잡히는 것 — `--country`, `deny`, `firewall=off`의 말, `ssh on`의
   여러 갈래, `wifiStatus`, `firewall` 상태, check의 dictation 줄. 그것은 Task 1의 want가 유일한 그물이다(design 확인 7).

2. 순서의 함정. 가르기 함수는 순수하므로 언제 불러도 같지만, 시스템 콜 쪽이 갈래마다 반응하는 순서는 지금 코드 그대로여야 한다.
   지금 코드에서 시스템 콜이 인자 검사보다 앞서는 자리가 둘이다.

   - `ssh` — `args.len > 1`이면 usage, 0이면 상태, 그다음 `needDisk()`, 그다음에야 `on` · `off` 아닌 동사가 usage다. 그래서
     `ssh foo`는 디스크가 없으면 "no config disk"(exit 2), 있으면 usage(64)다. union에 `bad_verb`를 `usage`와 따로 두고 시스템 콜
     쪽은 `needDisk` 뒤에 `bad_verb`를 usage로 돌린다.
   - `firewall` — `tarsConf()`와 `readOr(NFT_PATH)`가 인자 검사 앞이다. 파일을 못 읽으면 `firewall x`도 exit 2다. 시스템 콜 쪽은
     읽기를 먼저 두고 그 뒤에 `firewallArgs`를 부른다.

   `wifi`(나라 → SSID → 디스크), `ssh-key`(모양 → 디스크 → 키 줄), `dictation`(모양 → 디스크 → 쌍마다 `=` · 이름 · 제어 문자)은
   인자 검사가 앞이라 그대로 옮겨도 순서가 같다. 다만 `dictation set`의 쌍 검사는 `needDisk` 뒤다 — union의 쌍 거절 칸은 시스템 콜
   쪽이 `needDisk` 뒤의 `switch`에서 다룬다.

3. 인자 union 다섯(design 결정 5). 모두 `config_front_edit.zig`의 `pub`이고 인자는 `[]const [*:0]const u8`(동사 뒤)다.

   ```zig
   pub const WifiArgs = union(enum) {
       status,
       add: struct { ssid: []const u8, country: ?[]const u8 },
       usage,
       /// `--country` 뒤가 대문자 둘이 아니다.
       bad_country,
       /// SSID가 0바이트 · 32바이트 넘음 · 제어 문자.
       bad_ssid,
   };
   pub const SshArgs = union(enum) { status, on, off, usage, bad_verb };
   pub const SshKeyArgs = union(enum) { list, add: ?[]const u8, usage };   // add의 null은 표준 입력
   pub const FirewallArgs = union(enum) { status, change: struct { allow: bool, spec: PortSpec }, usage, bad_port };
   pub const DictationArgs = union(enum) {
       status,
       key: ?[]const u8,                   // null은 표준 입력
       set: []const [*:0]const u8,         // 쌍 검사를 지난 인자
       usage,
       no_equals: []const u8,              // 그 인자
       unknown_key: []const u8,            // 그 키
       control_byte: []const u8,           // 그 키
   };
   ```

   `wifiArgs`는 나라를 SSID보다 먼저 본다(지금 순서). `dictationArgs`는 쌍을 앞에서부터 보고 처음 걸린 것에서 멈추며, 한 쌍 안에서는
   `=` → 이름 → 제어 문자 순이다(지금 순서).

4. 판정 · 글자 함수. 한 줄짜리 판정은 반환값, 여러 줄은 `sink: anytype`(M0 plan 확정 3). 경로는 인자로 받는다 — 서식 문자열의
   `{s}`가 그대로여야 (a)가 빈 diff다. 경로 상수는 `config_front`에 남는다(여는 쪽의 것).

   | 함수 | 지금 자리 | 서명 |
   |---|---|---|
   | `keyLine` | `sshKey` 402 ~ 403 | `fn keyLine(raw: []const u8) ?[]const u8` — trim, 비지 않음, 개행 · 제어 문자 없음 |
   | `Sshd` · `sshdText` | `sshdLinked`의 enum · `ssh` 상태의 `switch` | `enum { none, template, other }`, `fn sshdText(s: Sshd) []const u8` |
   | `wifiStatusLines` | `wifiStatus`의 `while` | `fn wifiStatusLines(sink: anytype, conf: []const u8) void` |
   | `wifiDone` | `wifi` 259 ~ 271 | `fn wifiDone(sink: anytype, ssid, path, replaced: bool, with_country: bool, net_off: bool, existed: bool) void` |
   | `firewall22` | `sayFirewall22`의 `if` | `fn firewall22(sink: anytype, nft_text: []const u8, nft_dir: []const u8) void` |
   | `firewallRules` | `firewall` 상태의 `while` | `fn firewallRules(sink: anytype, text: []const u8) usize` |
   | `FirewallChange` · `firewallChange` | `firewall` 477 ~ 482 | `union { same, changed: []const u8, overflow }`, `fn firewallChange(out: []u8, text, allow: bool, rule) FirewallChange` |
   | `firewallSaid` | `firewall` 486 ~ 489 | `fn firewallSaid(sink: anytype, allow: bool, rule, changed: bool, nft_dir) void` |
   | `dictationApply` | `dictation` 569 ~ 582 | `fn dictationApply(sink: anytype, work: *[2][]u8, text, args) ?[]const u8` — 넘치면 null(그 전의 줄은 이미 찍혔다, 지금과 같다) |
   | `dictationUnknown` | `check` 623 ~ 637 | `fn dictationUnknown(sink: anytype, text, path) usize` |

   `firewallChange`의 `allow`는 빈 파일이면 `RULES_HEADER` 위에 더한다 — 지금의 `base`다. `overflow`는 지금처럼 말 없이 exit 1이다
   (그 동작을 바꾸지 않는다, design 비목표 2). `dictationApply`가 `config_edit.setLine`을 부르므로 `config_front_edit`가
   `config_edit`를 import한다 — 지금 `dictation` 안의 함수 지역 `@import`가 파일 머리로 간다(design 위험 4). `setLine`은 `parse`를
   부르지 않으므로 `config_front_edit_test`에 `configLog`가 없어도 표준 에러로 새는 줄이 없다 — Task 1에서 `zig build test`의
   출력에 `tars-init:` 줄이 늘지 않았는지 본다.

   안 내려가는 것 — `check`의 wpa · sshd · 모드 · firewall 줄(조건이 `fileExists` · `readlink` · `statx`의 결과다. 조건 하나에 문장
   하나라 함수로 빼도 볼 것이 없다), `ssh on`의 `switch`(갈래마다 `symlink` · `unlink`가 끼어 있다), `dictation` 상태(파일 존재 하나),
   `firewall=off` 줄 · `applied now` · nft 실패 줄(조건 없이 한 줄이거나 `run`의 결과).

5. 검사 5 ~ 9의 want는 Task 1에서 지금의 `config_front.zig`에서 베낀다(design 결정 9).

   | 검사 | 무엇을 | 베끼는 줄 |
   |---|---|---|
   | 5 인자 union 다섯 | 동사마다 받는 모양 · 거절 칸 · 처음 걸린 것에서 멈춤 | 196 ~ 210 · 306 ~ 361 · 378 ~ 393 · 465 ~ 472 · 527 ~ 566 |
   | 6 wifi | `wifiStatusLines`(psk 줄이 안 나온다), `wifiDone`의 갈래 열여섯 가운데 넷 | 286 · 259 ~ 271 |
   | 7 ssh | `keyLine`, `sshdText` 셋, `firewall22` 둘 | 312 ~ 314 · 370 ~ 374 · 402 ~ 403 |
   | 8 firewall | `firewallRules`(주석 · 빈 줄 제외), `firewallChange` 넷(allow 새 · allow 있음 · deny 있음 · deny 없음), `firewallSaid` 넷 | 453 ~ 460 · 477 ~ 489 |
   | 9 dictation | `dictationApply`(줄마다 한 줄 · 넘침), `dictationUnknown`(줄 번호 · 주석 · `=` 없는 줄 건너뜀) | 569 ~ 582 · 623 ~ 637 |

6. mutation 둘(Task 3, design 결정 10).

   | mutation | 비틀 것 | 잡아야 할 검사 |
   |---|---|---|
   | m1 가르기 | `wifiArgs`가 `--country`를 `args[2]`에서 찾는다(위치를 바꾼다) | 5 — `wifi tars-wl --country KR`이 `.add`에 나라 `KR` |
   | m2 문장 | `firewallSaid`의 `"not opened by tars-config"`를 `"not open"`으로 | 8 — deny 없음의 글자 |

## Task 1: `config_front_edit`에 더하고 검사 5 ~ 9

`config_front.zig`는 한 줄도 안 고친다. (1) `/tmp/hc-tc-before.txt`를 다시 뽑는다(151줄). (2) `config_front_edit.zig`에 확정 3 · 4를
절마다 넣는다 — 인자 union은 새 절 "── 인자 ──", 나머지는 이미 있는 절(방화벽 · 무선 · ssh · 받아쓰기) 끝. 주석도 함께 간다(`wifi`의
"wpa_passphrase가 표준 입력에서 읽는다"는 남는다 — 시스템 콜 쪽의 일이다. `wifiStatus`의 "망의 이름만 보인다", `dictation`의 "이름만
거른다" · "같은 문법이라"는 간다). (3) 검사 5 ~ 9.

검사 — `zig build test` PASS, 표준 에러의 `tars-init:` 줄 수가 M0와 같음, (a) `>`만, `git diff --stat`의 지운 줄 0.
commit: `HC-M1: Add the front verbs' argument parsers and sentence functions to config_front_edit`.

## Task 2: `config_front`가 부른다

동사 다섯의 머리를 `switch (fe.xxxArgs(args))`로 바꾸고(확정 2의 순서), 옮긴 조각을 부르는 자리로 바꾼다. `sshdLinked`는 `fe.Sshd`를
돌려준다. 지우는 편집이라 `git diff | rg '^-'`로 지운 줄을 읽는다. 검사 — 빌드, (a) 빈 diff, 체인 넷(확정 1의 자리).
commit: `HC-M1: Route the front verbs through their argument parsers and the moved sentences`.

## Task 3: 호스트 검사 · mutation · 루트 게이트

M0 Task 3과 같다. 루트 게이트가 도는 동안 HC-M2 plan을 쓴다.

## HC-M1이 실측한 것

(Task 3 뒤에 채운다.)
