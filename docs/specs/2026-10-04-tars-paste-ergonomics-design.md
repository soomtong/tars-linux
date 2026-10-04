# TARS Paste Ergonomics — Design

Date: 2026-10-04
Status: 진행 중(2026-10-04 시작). plan은 milestone마다 그때 쓴다.

GE(Guest Ergonomics)가 남긴 것 둘과 루트 게이트를 흔든 체인 경합 하나에서 시작한다.

1. GE 위험 2 · 비목표 4. 우리 터미널은 `Cmd+V`를 bracketed paste로 감싸지 않는다. GE-M1이 vim에
   `autoindent`를 켠 뒤로, insert 모드에서 들여쓴 여러 줄을 붙이면 줄마다 들여쓰기가 더해져 계단이
   된다. 셸에서는 여러 줄을 붙이면 첫 줄이 Enter 없이 실행된다.
2. GE 비목표 2. 사용자 vimrc(`/.vimrc`)가 tmpfs에 있어서 부팅마다 사라진다.
3. `docs/guides/lessons.md` "이월 숙제"의 service 체인 두 항목. 2026-10-04 GE-M1 루트 게이트에서
   부팅 C의 검사 12가, 2026-09-28 WL 루트 게이트에서 부팅 D의 ssh 제어 연결이 한 번씩 죽었다.

## 한 줄 요약

PE-M0은 `service/check.sh`의 `boot_ssh`가 dhcpcd의 `leased` 줄이 아니라 그 뒤의 `adding default
route` 줄을 기다리게 한다. dhcpcd는 주소를 붙이기 전에 `leased`를 찍는다. PE-M1은 자식이 모드
2004를 켠 상태면 `dumpPaste`가 클립보드를 `ESC[200~` · `ESC[201~`로 감싸고, 안 켰으면 지금처럼
그대로 쓴다. PE-M2는 `/.vimrc`를 `/config/vimrc`로 잇는 링크를 initrd에 걸고, 첫 부팅에 `init`이
주석만 든 seed vimrc를 깐다.

```
PE-M0   service 부팅 B·C·D   →  주소가 붙은 뒤에 ssh-keyscan · ssh를 친다
PE-M1   fish에 두 줄 붙이기   →  Enter를 칠 때까지 아무것도 실행되지 않는다
        vim insert에 붙이기   →  들여쓰기 계단이 없다
PE-M2   echo set tabstop=3 >> /.vimrc  →  다음 부팅의 vim에서도 tabstop=3
```

## 왜 셋을 한 서브프로젝트로 묶나

M1과 M2는 둘 다 "사람이 붙이고 고친 것이 사람이 뜻한 대로 남는가"의 일이다. M1은 붙인 글자가 친
글자로 오해되지 않게 하고, M2는 사람이 고친 vim 설정이 재부팅을 넘게 한다. 둘 다 GE가 근거와 함께
비워 둔 자리이고, 둘 다 작다. M1은 우리 코드로 함수 하나와 그것을 부르는 몇 줄이고, M2는 ST-M2가
gitconfig에 대해 이미 세운 모양을 vimrc에 한 번 더 하는 일이다.

M0은 성격이 다르다. 코드가 아니라 게이트의 일이고, 이 서브프로젝트의 내용과도 무관하다. 그래도
여기 둔다. M1과 M2가 각각 루트 게이트(약 1시간 5분)를 돌려야 하는데, 그 게이트가 우리 변경과
무관한 이유로 빨개지면 원인을 가르느라 시간이 든다. GE-M1이 실제로 그랬다 — `service` 체인만 따로
세 번 더 돌려 3/3을 보고서야 닫았다(GE-M1 plan 실측 11).

순서는 M0 → M1 → M2다. M0이 앞인 이유는 위와 같다. M1과 M2는 서로 독립이다(M1은 `terminal`과
`copy` 체인, M2는 `init` · initrd와 `config` 체인). M1을 앞에 두는 것은 그쪽이 이 서브프로젝트의
중심이고, CM 결정 9를 다시 여는 일이라 먼저 결론을 내 두는 편이 낫기 때문이다. 순서를 바꿔도 동작은
같다.

## 결정

### 결정 1 — `boot_ssh`는 `adding default route` 줄까지 기다린다(PE-M0)

lead의 브리핑은 "부팅 B의 329줄에 이미 임대 기다림이 있으니 그 모양을 C와 D에 복제한다"였다.
코드를 보니 전제가 달랐다(실측 7). 329줄은 부팅 B의 본문이 아니라 `boot_ssh` 함수 안에 있고, 부팅
B · C · D가 전부 그 함수로 뜬다. 그 줄은 2026-09-27(`c89157d`)부터 있었다. 그러니 2026-09-28과
2026-10-04의 두 실패는 둘 다 임대 기다림이 있는 상태에서 났다.

`docs/guides/lessons.md`의 진단("검사가 `Server listening`만 기다리고 바로 keyscan을 친다")도
그래서 틀렸다. 실제 순서는 이렇다(실측 7 · 8).

1. `boot_ssh`가 `eth0: leased 10\.0\.2\.15 `를 1초 간격으로 폴링하다가 그 줄을 보고 돌아온다.
2. 검사 12 앞의 `Server listening` 기다림은 이미 참이다(sshd가 5초 먼저 떴다).
3. 곧바로 `ssh-keyscan`이 hostfwd로 붙는다.
4. 그런데 dhcpcd는 `leased`를 찍은 다음에야 주소를 붙이고(`ipv4_applyaddr`), 경로를 만들며
   `adding route to 10.0.2.0/24`와 `adding default route via 10.0.2.2`를 찍는다. 실패한 회차의 시리얼
   로그에서 그 두 줄이 `leased` 바로 뒤에 같은 초(08:17:26)로 있다.

그래서 1과 4 사이에 시간 차(race window)가 있다. 그 사이에 keyscan의 연결이 들어가면 게스트는 아직 10.0.2.15가 아니다.
SLIRP은 호스트 쪽 연결을 바로 받아 주고 게스트로 SYN을 보내는데, 그 SYN이 버려진다. keyscan은
기본 타임아웃 5초 안에 아무것도 못 받고 빈 값을 낸다. 부팅 D의 `Connection timed out during banner
exchange`도 같은 모양이다 — TCP 연결은 SLIRP이 받아서 성공했고, 배너가 `ConnectTimeout=5` 안에 안
왔다. 두 증상이 "호스트 쪽은 붙었는데 게스트 쪽이 아직이다"로 함께 설명되므로 같은 경합으로 판단한다.

SLIRP이 버려진 SYN을 언제 다시 보내는지는 재지 않았다. 다시 보내는 것이 5초 뒤라면 두 증상이
정확히 맞고, 더 일찍이라면 그 시간 차가 그보다 길어야 한다. 어느 쪽이든 고치는 자리는 같다 — 주소가 붙은
뒤에 치면 그 시간 차가 없다. 그래서 그 값을 재는 일은 비목표 6이다.

| 후보 | 왜 아닌가 |
|---|---|
| keyscan과 첫 ssh에 재시도 loop를 둔다 | 부팅 A의 검사 7이 이미 그 모양이다(0.5초 × 20). 그런데 이번 원인은 "아직 안 됐다"가 아니라 "우리가 너무 일찍 쳤다"이고, 그 사실을 아는 자리가 `boot_ssh` 하나다. 재시도는 호출부마다 따로 두어야 하고(검사 12 · 부팅 D의 제어 연결), 둘 다 진짜 회귀가 났을 때 그 시간만큼 늦게 빨개진다 |
| `ConnectTimeout`과 keyscan의 `-T`를 늘린다 | `SSHO`는 검사 11(방화벽이 22를 막는다)도 쓴다. 그 검사는 타임아웃이 나야 초록이라, 늘리면 체인이 그만큼 길어진다. 그리고 시간 차를 없애는 것이 아니라 그보다 오래 기다리는 것이다 |
| `leased` 기다림을 부팅 C · D에 복제한다(브리핑) | 이미 셋 다 기다린다. 이것이 실패를 막지 못했다는 것이 이번 진단의 출발점이다 |
| `boot_ssh`가 `adding default route via 10\.0\.2\.2`까지 기다린다 | 고른 것. 그 줄은 dhcpcd가 주소를 붙인 뒤에만 찍힌다(실측 8의 소스 순서). 고칠 자리가 함수 하나라 부팅 B · C · D가 한 번에 바뀐다 |

`leased` 기다림은 지우지 않고 그 뒤에 한 줄을 더한다. 둘이 다른 실패를 말하기 때문이다. `leased`가
안 오면 "DHCP가 안 됐다"이고, `leased`는 왔는데 경로 줄이 안 오면 "주소를 붙이다 실패했다"다.
`fail`의 메시지와 마커도 각각 둔다.

```bash
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
wait_for_log "eth0: adding default route via 10\.0\.2\.2" 30 \
  || fail "dhcpcd leased but never added the default route" ": leased" "adding"
```

브리핑의 "체인 두 자리"는 "함수 한 자리"가 된다. 코드는 0줄 그대로다.

같은 모양(임대를 기다린 뒤 hostfwd로 붙는다)이 `firewall/check.sh` 304 · 381줄에도 있다. 그쪽은
임대 뒤에 게스트에 리스너 스크립트를 타이핑하고 그 출력을 기다린 다음에 붙으므로 시간 차가 몇 초 전에
지나간다. 그리고 실패가 관측된 적이 없다. 그래서 M0은 손대지 않는다(비목표 6).

### 결정 2 — 감쌀지는 자식이 켠 모드 2004가 정하고, 본문은 바꾸지 않는다(PE-M1)

CM 결정 9가 bracketed paste를 넣지 않은 근거는 "셸이 그 모드를 받는지 확인한 적이 없다"였다. 이번에
쟀다(실측 1 · 4). 게스트의 셸 셋과 vim이 전부 그 모드를 켜고, 감싼 붙여넣기와 감싸지 않은 붙여넣기를
다르게 다룬다.

| 자식 | 프롬프트에서 `ESC[?2004h` | 명령을 띄우기 전에 `ESC[?2004l` | 감싸지 않은 두 줄 | 감싼 두 줄 |
|---|---|---|---|---|
| zsh 5.9(ZLE 모듈) | 보낸다 | 보낸다 | 첫 줄이 바로 실행된다 | Enter 전에는 아무것도 실행되지 않는다 |
| bash 5.2(자기 안의 readline) | 보낸다 | 보낸다 | 첫 줄이 바로 실행된다 | 같다 |
| fish 4.0.2 | 보낸다 | 보낸다 | 첫 줄이 바로 실행된다 | 같다 |
| vim 9.1(GE의 시스템 vimrc) | 기동할 때 보낸다 | — | `autoindent` 계단(4 · 8 · 12칸) | 계단 없음(4 · 4 · 4칸) |

그래서 규칙은 하나다. 붙이는 순간에 그 패널의 터미널에서 모드 2004가 켜져 있으면 감싸고, 꺼져
있으면 지금처럼 그대로 쓴다. 그 모드는 ghostty vt가 자식의 `ESC[?2004h` · `ESC[?2004l`을 받아
`Terminal.modes`에 이미 들고 있다(실측 2). 우리는 읽기만 한다.

모드는 화면별이 아니라 `Terminal` 하나에 하나다(실측 2). vim처럼 대체 화면에 들어간 뒤 모드를 켜는
자식도, 대체 화면에서 나온 뒤에 끄는 자식도 같은 값 하나를 바꾼다. 패널은 패널마다 `vt.Screen`과
`Terminal`이 따로이므로(WP 결정 1) 모드도 패널마다 따로다. 붙여넣기는 포커스 패널로 가고, 그 패널의
모드를 본다.

본문은 한 바이트도 바꾸지 않는다. 라이브러리에 붙여넣기 인코더(`ghostty_vt.input.encodePaste`)가
있고 ghostty 앱이 그것을 쓴다(실측 3). 그 함수는 감싸기 말고 두 가지를 더 한다. 모드가 꺼져 있으면
`\n`을 `\r`로 바꾸고, 어느 쪽이든 제어 바이트 열여섯(NUL · ESC · DEL · Ctrl+C 등)을 공백으로 바꾼다.
둘 다 이번에는 안 한다.

| 후보 | 왜 아닌가 |
|---|---|
| `encodePaste`를 그대로 쓴다 | 모드가 꺼진 갈래의 동작이 바뀐다(`\n` → `\r`). 셸은 둘을 다 Enter로 읽고, canonical 모드의 프로그램은 tty의 `ICRNL`이 `\r`을 `\n`으로 돌리므로 게이트가 그 차이를 볼 자리가 없다. 보고된 문제도 없다. 제어 바이트 치환은 우리 클립보드에서 할 일이 없다 — 클립보드는 `y`가 화면 셀에서 뽑은 글자뿐이고 셀에는 제어 바이트가 없다. 그리고 `const` 입력에 개행이 있으면 `MutableRequired`를 돌려줘서 복사본을 만드는 갈래가 하나 더 생긴다 |
| 감싸기만 우리가 한다 | 고른 것. "모드가 꺼져 있으면 지금처럼"이 글자 그대로 참이다. 두 갈래를 게이트가 다 본다(결정 5) |

라이브러리에서 가져오는 것은 판단의 재료(`modes.get(.bracketed_paste)`)와 모양(머리 · 본문 · 꼬리
세 조각을 차례로 쓴다)이다. 클립보드가 화면 밖에서 오게 되면(OSC 52나 시스템 클립보드) 그때는 제어
바이트 치환이 할 일이 생기고, 그것은 `encodePaste`로 옮길 자리다(비목표 1).

### 결정 3 — 쓰기는 셋이고, 할당을 안 한다(PE-M1)

머리(`ESC[200~`, 6바이트) · 본문 · 꼬리(`ESC[201~`, 6바이트)를 `pty.write` 세 번으로 쓴다. 모드가
꺼져 있으면 머리와 꼬리가 빈 조각이라 한 번이 된다.

한 버퍼에 이어 붙여 한 번에 쓰지 않는 이유는 둘이다.

1. 클립보드에 상한이 없다(실측 5). `copyYank`가 `selectionString`의 할당 결과를 그대로 들고 있어서,
   스크롤백 전체를 잡으면 그만큼 크다. 이어 붙이려면 매번 본문 길이 + 12바이트를 할당해야 한다.
2. 한 번에 써도 자식이 한 번에 읽는다는 보장이 없다. 셸과 vim은 raw 모드로 읽고, tty는 쓰기의 경계를
   보존하지 않는다. 그래서 하나로 쓰는 것이 원자성을 주지 않는다. 세 번의 쓰기는 `poll`로 돌아가지
   않고 연달아 일어나므로 자식이 머리를 읽고 나서 본문을 기다릴 틈이 마이크로초 수준이다. ghostty
   앱도 세 조각을 따로 큐에 넣는다(`Surface.zig`의 `completeClipboardPaste`).

`pty.write`는 master fd가 blocking이라(`O_NONBLOCK` 없음) 다 쓸 때까지 돌고, `write`가 0 이하를
돌려주면 조용히 그만둔다(실측 5). 이 성질은 안 바꾼다. 큰 붙여넣기에서 생길 수 있는 문제는 위험 3이다.

### 결정 4 — 판단은 `vt.zig`의 `pasteParts`에, 쓰기와 로그는 `main.zig`에(PE-M1)

`vt.Screen`에 함수 하나를 더한다.

```zig
/// 붙여넣기가 pty에 쓸 세 조각. 모드 2004가 꺼져 있으면 머리와 꼬리가 비었다.
pub fn pasteParts(self: *const Screen, text: []const u8) [3][]const u8
```

`main.zig`가 `self.term.modes`를 직접 읽지 않는다. TR 결정 1부터 지킨 규율(`main.zig`가 ghostty vt의
타입을 배우지 않는다)이고, `clipboard()` · `findNeedle()`이 같은 이유로 함수다. 그리고 판단이
`vt.zig`에 있으면 호스트의 `vt_test`가 실제로 나갈 바이트를 본다. `bracketedPaste() bool`만 내고
머리 · 꼬리 글자를 `main.zig`에 두면, 그 글자는 게스트에서만 확인된다.

`dumpPaste`는 이렇게 된다.

```zig
const parts = screen.pasteParts(text);
for (parts) |p| if (p.len > 0) pty.write(master_fd, p);
std.debug.print("terminal: clip> paste len={d} bracketed={d}\n", .{
    parts[1].len, @intFromBool(parts[0].len > 0),
});
```

로그 줄은 새로 만들지 않고 넓힌다. 새 필드는 맨 뒤에 붙인다 — `net/check.sh`의 `config shell=` 줄을
넓힐 때와 같은 규칙이다(lessons "로그 문구는 두 곳에 중복된다"). `len=`은 지금처럼 본문의 길이다.
머리와 꼬리의 12바이트를 더하면 `copy/check.sh`의 `len=11` 셋이 전부 `len=23`이 되어야 하고, 그
숫자는 "클립보드에 무엇이 들었나"를 말하지 않게 된다.

그래서 기존 판정은 한 줄도 안 바뀐다.

| 자리 | 지금 보는 것 | M1 뒤의 로그 | 고칠까 |
|---|---|---|---|
| `copy/check.sh` 515줄(검사 11) | `clip> paste len=11` 포함 | `clip> paste len=11 bracketed=1` | 그대로 맞는다 |
| `copy/check.sh` 564 · 567줄(검사 13) | `clip> paste len=11` 줄 수 | 같은 줄 수 | 그대로 맞는다 |
| `copy/check.sh` 460줄(검사 9) | `clip> len=11 text=echo PASTED` | 안 바뀐다(`dumpClip`) | — |
| `hangul/check.sh` 946 · 997줄 | `clip> paste` 줄 수(셸로 안 샜다) | 안 바뀐다(`find>` 갈래) | — |

`bracketed=` 필드 자체는 tautology에 가깝다. 우리 코드가 자기가 내린 판단을 찍는 것이기 때문이다.
그래서 게이트는 그 필드를 갈래를 가리키는 표지로만 쓰고, "감쌌다"는 판정은 화면에서 한다(결정 5).

### 결정 5 — 게이트는 `copy` 체인에 검사 둘을 더하고, 판정은 화면이 한다(PE-M1)

새 체인은 없다. `copy` 체인이 붙여넣기를 보는 자리이고, 설정 디스크 없이 fish로 뜬다. 두 검사가 두
갈래를 하나씩 맡는다. 둘 다 화면에 나타나는 차이로 판정하므로, 어느 갈래를 잘못 구현해도 그 갈래의
검사가 빨개진다.

검사 21 — 모드가 켜진 갈래(fish의 프롬프트).

1. copy mode를 나가고 화면을 지운다. `echo echo PEONE; echo echo PETWO`를 친다. 화면에 `| echo PEONE
   | echo PETWO |`가 연달아 생긴다.
2. copy mode에 들어가 `k` 둘로 `echo PEONE` 줄에 서고, `V` `j` `y`로 두 줄을 잡는다. 기대는
   `clip> len=21 text=echo PEONE`이다(둘째 줄은 개행 뒤 다음 로그 줄로 이어진다 — FP 결정 5의 실측).
3. 대조군. 로그 전체에 `| PEONE |`가 한 번도 없다. 검사 10과 같은 "지금까지 한 번도"의 대조군이다.
4. `Cmd+V`. 기대는 `clip> paste len=21 bracketed=1`과, 붙인 둘째 줄이 fish의 입력줄에 나타나서
   `echo PETWO`의 화면 등장 횟수가 하나 느는 것이다(검사 11과 같은 전후 차이).
5. 판정(음성). 3초 뒤에도 로그 전체에 `| PEONE |`가 없다. 감싸지 않았다면 fish가 첫 줄의 개행을
   Enter로 읽어 `PEONE`만 있는 줄을 곧바로 찍는다(실측 1).
6. 판정(양성). Enter를 치면 `| PEONE | PETWO |`가 연달아 생긴다. 두 줄이 한 입력줄로 들어갔다가 함께
   실행됐다는 뜻이다. 5만 있으면 "붙여넣기가 아예 안 갔다"도 통과하므로 이 줄이 짝이다.

검사 22 — 모드가 꺼진 갈래(`cat`).

1. 화면을 지우고 `cat`을 친다. fish는 `cat`을 띄우기 전에 `ESC[?2004l`을 보낸다(실측 1).
2. `Cmd+V`. 클립보드는 검사 21의 두 줄 그대로다. 기대는 `clip> paste len=21 bracketed=0`이다.
3. 판정(양성). 화면에 `| echo PEONE | echo PEONE | echo PETWO`가 생긴다. tty의 에코 · `cat`의 출력 ·
   아직 개행이 안 온 둘째 줄의 에코다.
4. 판정(음성). 로그의 `screen>` 줄 어디에도 `[200~`가 없다. `cat` 아래에서 감쌌다면 tty가 ESC를
   `ECHOCTL`로 에코해 화면에 `^[[200~echo PEONE`이 찍힌다(실측 4).
5. `Ctrl+C`로 `cat`을 끝낸다.

판정 글자가 친 명령줄과 안 겹친다(`project_gate_screen_echo`). 친 줄에는 `echo echo PEONE;`처럼
`PEONE` 앞에 `echo `가 붙고, `| PEONE |`는 그 글자만 있는 줄이다. `[200~`는 이 체인의 어떤 키도
만들지 않는다.

자리는 검사 20 뒤, 끝의 NUL 음성 검사 앞이다. 클립보드를 바꾸므로 그 뒤에 클립보드를 보는 검사가
없는 자리여야 하고, 검사 20 뒤가 그렇다. 체인이 약 25초 길어진다.

vim의 계단을 게이트에서 보지 않는 이유는 비목표 7에 있다.

`vt_test`에 호스트 검사 넷을 더한다(지금 마지막이 92다).

| 검사 | 본다 |
|---|---|
| 93 | 새 화면의 `pasteParts("ab")`가 `{"", "ab", ""}`다 |
| 94 | `ESC[?2004h`를 먹인 뒤 `{"\x1b[200~", "ab", "\x1b[201~"}`다. 시퀀스를 `ESC[?20`과 `04h` 둘로 쪼개 먹여도 같다 |
| 95 | 켠 채로 대체 화면(`ESC[?1049h`)에 들어가도 켜져 있다. 대체 화면에서 `ESC[?2004l`로 끄고 나와도(`ESC[?1049l`) 꺼져 있다 — 모드가 화면별이 아니다(실측 2) |
| 96 | RIS(`ESC c`)가 모드를 끈다. 그리고 `pasteParts("a\nb")[1]`이 `"a\nb"` 그대로다 — 결정 2가 개행을 안 바꾼다 |

### 결정 6 — copy mode와 검색 프롬프트의 경계(PE-M1)

목적지가 갈리는 자리(`main.zig`의 `.paste =>` 분기)는 안 건드린다.

- 검색 프롬프트가 열려 있으면 `dumpFindPaste`로 간다. 우리 프롬프트이지 자식이 아니므로 감쌀 상대가
  없다. 첫 줄 자르기(FP 결정 5)도 그대로다.
- copy mode 안에서 붙이면 지금처럼 셸로 가고 모드를 안 닫는다(CM-M2). 감쌀지는 그 순간 자식의 모드가
  정한다. copy mode는 우리 쪽 상태라 자식의 모드와 무관하다. `copy` 체인 검사 13이 그 경우를 밟는다 —
  fish의 프롬프트라 감싸서 가고, 한 줄이라 화면의 결과는 지금과 같다.
- ghostty 앱은 붙일 때 뷰포트를 바닥으로 내리지만 우리는 안 내린다. CM-M2가 정한 것이고 이
  서브프로젝트가 다시 열지 않는다.

### 결정 7 — 사용자 vimrc는 링크 하나와 주석만 든 seed다(PE-M2)

ST-M2가 gitconfig에 세운 모양을 그대로 따른다. 다섯 자리다.

| 자리 | 더하는 것 |
|---|---|
| `kernel/make_initrd.sh` | `ln -sf config/vimrc "$WORKDIR/.vimrc"` — `.gitconfig`와 rc 링크들 옆 |
| `init/src/config.zig` | `VIMRC_PATH = "/config/vimrc"` · `VIMRC_SEED` · `seedVimrc()`(`seedOneFile` 한 줄) |
| `init/src/main.zig` | `storage_mounted`일 때 `seedGitconfig()` 뒤에 `seedVimrc()` |
| `init/src/config_test.zig` | seed 검사 하나(결정 8) |
| `config/check.sh` | 1차 · 2차 부팅의 검사(결정 8) |

그리고 `kernel/vim/vimrc` 머리 주석의 `/.vimrc` 세 자리와 `make_initrd.sh` 235줄의 같은 언급을
"`/.vimrc`(설정 디스크의 `/config/vimrc`로 가는 링크)"로 맞춘다.

GE 결정 4의 후보 표는 seed vimrc를 "사용자 vimrc는 사람의 것이다 — 우리가 거기 쓰기 시작하면 사람이
고친 것과 우리가 고친 것이 섞인다"로 뺐다. 이 결정은 그 판단과 부딪치지 않는다. 그때 뺀 것은 모던
설정을 seed에 담는 안이었고, 이번 seed에는 설정이 한 줄도 없다. 우리가 쓰는 것은 처음 한 번의 주석뿐이고,
`O_EXCL` 때문에 그 뒤로는 손대지 않는다.

seed가 왜 있어야 하나. 링크만 걸고 파일을 안 만들면 사람이 `vim ~/.vimrc`로 열어 저장할 때 vim이 링크를
따라 `/config/vimrc`를 만든다(댕글링 링크에 쓰면 대상이 생긴다). 그래서 링크만으로도 영속은 된다. 그래도
seed를 까는 이유는 둘이다.

1. 사람이 그 파일을 열었을 때 무엇이 먼저 읽히는지, 이 파일의 실체가 어디인지를 알려 줄 자리가 그것뿐이다.
   ST-M2의 gitconfig seed가 머리 주석에 같은 것을 적었다.
2. `/.gitconfig`가 댕글링이던 것을 ST-M2가 "링크가 걸려 있는데 실체를 만드는 코드가 없다"로 고쳤다. 같은
   모양을 새로 만들지 않는다.

seed가 생기면 vim이 하나 다르게 한다. 사용자 vimrc가 있으면 `$VIMRUNTIME/defaults.vim`을 안 읽는다(실측
6). 게스트의 `defaults.vim`은 주석뿐인 stub이라(CU 결정 7) 읽든 안 읽든 차이가 없다. stub은 그대로 둔다 —
설정 디스크가 없는 부팅(ISO 세션 · `render` 체인)에서는 링크가 댕글링이고, vim은 그것을 "사용자 vimrc
없음"으로 보고 지금처럼 `defaults.vim`을 찾는다(실측 6).

seed의 내용은 원칙 넷으로 정하고 전문은 M2 plan에 둔다.

1. 모든 줄이 `"` 주석이거나 빈 줄이다. 설정이 한 줄이라도 있으면 GE 결정 4의 판단과 부딪치고,
   결정 8의 게이트가 거짓으로 초록이 될 수 있다(그 결정의 검사가 막는다).
2. 영어 · ASCII다. 같은 종류의 파일인 `kernel/vim/vimrc`와 맞춘다(GE 결정 6 원칙 5). gitconfig seed는
   한국어 주석이지만 그쪽은 git이 읽는 파일이고, vimrc는 같은 vim이 읽는 시스템 vimrc와 나란히
   읽힌다.
3. 적는 것은 셋이다. 이 파일의 실체가 설정 디스크의 `/config/vimrc`라는 것, vim이 시스템 vimrc
   `/etc/vim/vimrc`를 먼저 읽고 이 파일을 뒤에 읽으므로 여기서 그쪽의 줄을 되돌릴 수 있다는 것,
   예시 줄 몇 개(줄 번호 끄기 · 커서 모양 끄기 `set t_SI= t_SR= t_EI=`)다. 예시는 앞의 `"`를 지우면
   쓸 수 있는 모양으로 적는다.
4. `tabstop`이라는 낱말을 안 쓴다. 결정 8의 검사가 사람이 더한 `set tabstop=3`을 `grep tabstop`으로
   되읽으므로, seed에 그 낱말이 있으면 출력이 두 줄이 된다.

### 결정 8 — 게이트는 `config` 체인의 1차와 2차 부팅에서 본다(PE-M2)

새 체인은 없다. `config` 체인은 같은 디스크로 아홉 번 뜨고, 1차가 fish로 빈 디스크에 seed를 까는
부팅이며, 2차가 같은 디스크로 zsh로 뜬다(실측 9). gitconfig의 검사(ST-M2)가 1차에 있다.

| 자리 | 친다 | 기다린다 | 무엇을 말하나 |
|---|---|---|---|
| 1차 훅, gitconfig 검사 뒤 | `vim -e +scriptnames +qa` | `\| +2: ~/\.vimrc` | vim이 링크를 따라 seed를 사용자 vimrc로 읽는다. seed에 에러가 있으면 이 자리에 `E숫자:` 줄이 먼저 나온다 |
| 같은 훅 | `echo set tabstop=3 >> /.vimrc` 뒤 `grep tabstop /config/vimrc` | `\| set tabstop=3` | 링크로 쓴 것이 설정 디스크에 들어간다 |
| 1차의 로그 검사 | — | `tars-init: seeded /config/vimrc` | 깔렸다. gitconfig의 1355줄 옆 |
| 2차 훅(`watch_console_shell`) | `vim -e +'set ts?' +qa` | `\| +tabstop=3` | 사람이 더한 줄이 재부팅을 넘었고, vim이 그 줄을 시스템 vimrc의 `tabstop=8` 뒤에 읽는다 |

판정 글자가 친 명령줄과 안 겹친다. 1차의 `~/.vimrc`는 친 줄(`vim -e +scriptnames +qa`)에 없다. 2차의
`tabstop=3`은 친 줄의 `ts?`와 다르다. 되읽기의 `| set tabstop=3`은 행 머리가 `set`인 줄이고, 친 줄은
프롬프트와 `echo`로 시작한다(그 체인이 쓰는 수법이다).

`tabstop`을 고른 이유가 있다. 시스템 vimrc가 `tabstop=8`을 명시한다. 사람이 3을 적었는데 vim이
3을 말하면, vim이 사용자 vimrc를 시스템 vimrc 뒤에 읽는다는 순서까지 함께 보인다. 시스템 vimrc가 안
건드리는 옵션을 고르면 그 순서는 안 보인다.

이 판정은 `vim -e`에 기댄다. GE 실측 12에서 `vim -es`는 `-u` 없이 vimrc를 안 읽어 쓸 수 없었다. 이번에
재 보니 stdin이 터미널이 아니면 `vim -e`도 vimrc를 안 읽는다(실측 6). 게이트가 치는 셸은 pty 위에
있으므로 stdin이 터미널이고, 그때는 vimrc를 읽은 뒤의 값을 Ex 모드의 출력으로 화면에 찍는다. 대체
화면에 들어가지 않고 줄 단위로 찍으므로 `screen>`에 그대로 남는다.

이미 있는 검사가 고치지 않아도 덮는 것이 둘이다. 2차 · 8차 · 9차의 `tars-init: seeded /config/` 음성
검사(1485 · 1776 · 1853줄)는 접두로 보므로 vimrc를 다시 깔면 빨개진다. 7차의 검사는 이름을 하나씩
보므로 영향이 없다. 다른 체인에 `seeded` 줄 수를 세는 검사는 없다(실측 9).

### 결정 9 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가 한다

GE 결정 8과 같다. plan은 milestone마다 그 시점에 Opus 서브에이전트가 쓴다. 구현은 PE-M0을 Sonnet,
PE-M1을 Opus, PE-M2를 Sonnet 서브에이전트가 plan만 보고 한다. lead(Fable)는 결과 파일을 `Read`로
대조하고, 게이트를 돌리고, commit한다. 그래서 plan은 고칠 파일과 심볼, 편집의 모양, 칠 명령, 기대하는
출력, mutation을 다 적는다.

M1이 Opus인 이유는 그 milestone만 우리 코드의 판단(어느 갈래로 가나)과 게이트의 화면 판정을 함께 새로
만들기 때문이다. M0과 M2는 이미 있는 모양을 옮기는 일이다.

## 검증

### PE-M0 — `service/check.sh`

- `boot_ssh`의 기다림 한 줄(결정 1). 검사 번호는 안 바뀐다.
- mutation 하나. 새 기다림의 패턴을 오지 않을 글자(`adding default route via 10\.0\.2\.9`)로 바꾸면
  부팅 B가 30초 뒤 `dhcpcd leased but never added the default route`로 빨개진다. 그 기다림이 실제로
  돈다는 증명이다. 경합 자체는 재현할 수단이 없어서 mutation으로 못 본다.
- 경합은 반복으로 본다. `service` 체인만 다섯 번 연달아 돌려 5/5를 보고, 각 회차의 시리얼 로그에서 부팅
  B · C · D마다 `adding default route` 줄이 `leased` 줄보다 뒤에 있는 것을 센다(약 6분).

### PE-M1 — `vt_test` · `copy/check.sh`

- `vt_test` 검사 93~96(호스트, 부팅 전).
- `copy` 검사 21(모드 켜짐: 두 줄이 Enter 전에 안 돈다, Enter 뒤에 둘 다 돈다) · 22(모드 꺼짐: `[200~`가
  화면에 없다).
- 기존 판정은 고치지 않는다(결정 4의 표).
- mutation 넷.
  1. `pasteParts`가 모드와 무관하게 머리 · 꼬리를 비운다 → `vt_test` 94가 부팅 전에 빨개진다. `vt_test`를
     건너뛰고 체인을 돌리면 검사 21의 5단계가 `the first line ran before Enter`로 빨개진다.
  2. 언제나 감싼다 → `vt_test` 93이 빨개진다. 체인에서는 검사 22의 3 · 4단계가 `^[[200~` 때문에 빨개진다.
  3. `main.zig`가 머리만 쓰고 꼬리를 빠뜨린다 → `vt_test`는 초록이다(배선의 실수라서). fish가 꼬리를
     기다리며 Enter까지 붙인 글자로 받으므로 검사 21의 6단계가 빨개질 것으로 본다 — fish의 그 동작은 재지
     않았고, M1 plan이 잰다.
  4. 로그의 `bracketed=`를 언제나 1로 찍는다 → 검사 22의 2단계가 빨개진다.

### PE-M2 — `config_test` · `config/check.sh`

- `config_test`의 vimrc seed 검사. 끝에 개행이 있다 · 비지 않은 모든 줄이 `"`로 시작한다 · 모든 바이트가
  ASCII다 · `/etc/vim/vimrc`라는 글자가 있다. 마지막 것은 gitconfig 검사의 `defaultBranch`와 같은
  자리다 — 주석이 하나도 없는 빈 seed가 앞의 셋을 아무것도 안 보고 통과하는 것을 막는다.
- `config` 체인의 네 자리(결정 8의 표).
- mutation 넷.
  1. `make_initrd.sh`의 링크 줄을 지운다 → 1차 훅의 `scriptnames`가 `~/.vimrc`를 안 찍어 빨개진다.
  2. `main.zig`의 `seedVimrc()` 호출을 지운다 → 링크가 댕글링이라 같은 자리가 빨개진다. 훅을 통과하더라도
     1차의 로그 검사가 `first boot did not seed /config/vimrc`로 빨개진다.
  3. seed에 `set tabstop=3` 한 줄을 넣는다 → `config_test`가 부팅 전에 빨개진다. 이 검사가 없으면 2차의
     `tabstop=3`이 사람의 줄이 아니라 seed에서 와도 초록이다 — 검사가 막는 것이 그 거짓 초록이다.
  4. `seedOneFile`의 `O_EXCL`을 지운다(매 부팅 덮어쓴다) → 2차의 `seeded /config/` 음성 검사와
     `tabstop=3` 기다림이 함께 빨개진다.

### 셋 다

루트 게이트 18체인 × 3, 약 1시간 5분(GE-M1 실측). M1과 M2는 둘 다 initrd를 바꾼다 — M1은 `terminal`
바이너리가 initrd의 `/terminal`이고, M2는 `init`과 링크가 바뀐다. 그래서 두 milestone 모두 열여덟
체인이 전부 새 initrd로 부팅한다. M0은 initrd를 안 바꾼다.

## Milestone

### PE-M0 — service 체인의 경합

`service/check.sh`의 `boot_ssh`에 기다림 한 줄. `docs/guides/lessons.md` "이월 숙제"의 service 두
항목을 지우고, 진단이 틀렸던 것과 실제 원인을 `docs/guides/lessons.md`의 "서브프로젝트를 넘어 유효한
실측"에 한 단락으로 옮긴다(dhcpcd는 주소를 붙이기 전에 `leased`를 찍는다 — hostfwd로 붙는 체인은 경로
줄을 기다린다). 이 milestone이 끝나면 부팅 B · C · D의 ssh가 게스트에 주소가 붙은 뒤에만 붙는다.

### PE-M1 — bracketed paste

`vt.zig`의 `pasteParts`, `main.zig`의 `dumpPaste`(본문과 doc 주석), `vt.zig` `findPaste` doc 주석의
"셸 쪽 `dumpPaste`는 개행이 곧 실행이 되는 것을 감수했지만" 문장, `vt_test` 검사 93~96, `copy/check.sh`
검사 21 · 22. 이 milestone이 끝나면 게스트의 zsh · bash · fish에서 여러 줄을 붙여도 Enter 전에는 실행되지
않고, vim insert 모드에서 붙여도 계단이 없다. GE 위험 2의 우회(`:set paste`)가 필요 없어진다.

### PE-M2 — 사용자 vimrc 영속

결정 7의 다섯 자리와 vimrc 주석 두 곳. 이 milestone이 끝나면 설정 디스크가 붙은 기계에서
`~/.vimrc`가 `/config/vimrc`이고, 사람이 고친 vim 설정이 재부팅을 넘는다.

## 위험

1. M0의 원인은 판단이다. 실패한 회차의 로그와 dhcpcd 소스의 순서가 그 판단의 근거이지만, SLIRP이 버려진
   SYN을 언제 다시 보내는지는 재지 않았다(결정 1). M0 뒤에 같은 증상이 다시 나면 이 판단이 틀린
   것이다. 그때는 그 회차의 시리얼 로그에서 `adding default route` 줄과 keyscan 사이에 무엇이 있었는지,
   그리고 sshd가 그 사이에 무슨 줄을 찍었는지부터 본다.
2. 자식이 모드 2004를 켠 채 죽으면(SIGKILL을 받은 vim) 모드가 남는다. 그 뒤에 모드를 모르는 프로그램이
   읽으면 붙인 글자 앞뒤에 `^[[200~` · `^[[201~`가 들어간다. 셋 다 명령을 띄우기 전에 모드를 끄므로
   (실측 1) 셸 아래에서 띄운 프로그램은 안전하다. 남는 경우는 죽은 프로그램의 부모가 셸이 아닐 때다.
   모든 터미널이 같은 성질을 갖고, RIS(`reset` 명령)가 모드를 끈다(`vt_test` 검사 96).
3. 큰 붙여넣기. master fd가 blocking이라 자식이 안 읽으면 `pty.write`가 멈추고, 그동안 우리 루프는
   자식의 출력을 못 읽는다. 자식이 에코로 출력 버퍼를 채우면 둘이 서로를 기다린다. 이것은 PE 전부터
   있던 성질이고 M1이 더하는 것은 12바이트다. 고치는 일은 비목표 5다.
4. 검사 21은 fish 4.0.2가 감싼 붙여넣기를 다루는 방식에 기댄다. fish는 감싼 글자를 입력줄에 넣고
   Enter를 기다린다(실측 1). fish가 그 동작을 바꾸면(예를 들어 붙인 글자를 고쳐 쓰면) 검사 21의
   기대 문구가 바뀐다. 실측은 같은 판의 arm64 fish로 했다 — 게스트에서의 화면 모양(둘째 줄의 들여쓰기
   등)은 M1 plan이 잰다.
5. fish 4.0.2는 `ESC[?2004h`와 함께 확장 키 모드 둘(`ESC[>4;1m` · `ESC[=5u`)을 켠다(실측 1, 바이너리의
   `Enabling extended keys and bracketed paste`). 이 서브프로젝트는 그 둘을 안 다룬다. 우리 터미널이 그
   모드에서 키를 어떻게 보내는지는 IP · TQ의 몫이고 지금까지 문제가 보고되지 않았다.
6. M2의 seed는 설정 디스크가 이미 있는 기계에도 다음 부팅에 한 번 깔린다(`O_EXCL`이 "없다"를 답한다).
   사람이 이미 `/config/vimrc`를 다른 뜻으로 만들어 두었다면 그대로 둔다. 그 이름을 쓴 코드는 지금
   저장소에 없다.
7. M1 · M2의 측정(실측 1 · 4 · 6)은 컨테이너의 arm64 바이너리(게스트와 같은 판)와 python `pty`로 했다.
   우리 터미널 위에서의 실제 화면은 게스트에서만 잴 수 있고 각 plan이 잰다.

## 착수 전에 실측한 것

전부 2026-10-04에 design을 쓰며 `tars-devcontainer` 이미지와 그 위에 zsh · fish · vim · python3을 깐
측정 컨테이너에서 쟀다. 컨테이너의 패키지는 sysroot와 같은 판이다 — zsh `5.9-8+b24`, fish `4.0.2-1`,
vim `2:9.1.1230-2`, bash `5.2.37-2+b10`(arm64). pty는 python의 `pty.fork`에 47 × 100,
`TERM=xterm-256color`, `LANG=C.UTF-8`을 줬다.

1. 셸과 vim이 모드 2004를 켜는가. sysroot의 바이너리에서 `2004h` · `2004l`을 찾았다.

   | 대상 | 들어 있는 자리 | 끄는 설정(문자열로 확인) |
   |---|---|---|
   | zsh | `/usr/bin/zsh` 본체에는 없다. ZLE 모듈 `zsh/5.9/zsh/zle.so`에 `[?2004h` · `[?2004l` | `zle_bracketed_paste` |
   | bash | `/usr/bin/bash` 본체에 있다. bash는 `libreadline`을 링크하지 않는다(`NEEDED`가 `libtinfo` · `libc`뿐) — 자기 안의 readline을 쓴다 | `enable-bracketed-paste`(본체와 `libreadline.so.8` 둘 다에 있다) |
   | fish | `/usr/bin/fish`에 `[?2004h` · `[?2004l` | 따로 된 설정을 못 찾았다. 확장 키와 함께 켜고 끈다(`Enabling extended keys and bracketed paste`) |
   | vim | `/usr/bin/vim.basic`에 `[?2004h` · `[?2004l` | `t_BE` · `t_BD` |

   lead의 브리핑은 bash를 `libreadline`으로 적었다. bash는 그 라이브러리를 안 쓴다. 게스트에
   `libreadline`이 있다면 다른 도구가 끌고 온 것이다.

   동작도 쟀다. 셸마다 `echo PE1\necho PE2`를 그대로 한 번, `ESC[200~` … `ESC[201~`로 감싸 한 번 썼다.
   판정은 ANSI를 걷어낸 출력에서 그 글자만 있는 줄(`PE1`)을 센 것이다.

   ```
   zsh   bracketed=0 2004h_at_prompt=True ran_before_enter=True  2004l_before_cat=True
   zsh   bracketed=1 2004h_at_prompt=True ran_before_enter=False 2004l_before_cat=True
   bash  bracketed=0 2004h_at_prompt=True ran_before_enter=True  2004l_before_cat=True
   bash  bracketed=1 2004h_at_prompt=True ran_before_enter=False 2004l_before_cat=True
   fish  bracketed=0 2004h_at_prompt=True ran_before_enter=True  2004l_before_cat=True
   fish  bracketed=1 2004h_at_prompt=True ran_before_enter=False 2004l_before_cat=True
   ```

   셋 다 감싼 경우에 Enter를 친 뒤 `PE1`과 `PE2`가 한 번씩 나왔다. `2004l_before_cat`은 `cat`을 친 뒤
   `cat`이 뜨기 전에 셸이 모드를 껐다는 뜻이다. zsh와 bash는 감싼 글자를 반전(`ESC[7m`)으로 그렸다.

2. ghostty vt의 모드 2004. `modes.zig` 324줄이 `bracketed_paste = 2004`(기본값 꺼짐)이고, 상태는
   `Terminal.modes: ModeState` 필드 하나(`Terminal.zig` 83줄)다. 화면별 저장이 없다 — 대체 화면 전환은
   같은 `setMode`의 다른 갈래(`switchScreenMode`)이고 `modes`를 안 바꾼다. `ESC[?2004h` · `l`은
   `stream_terminal.zig` 270 · 271줄에서 `setMode(mode, true/false)`로 가고, 그 함수(690줄)가 맨 먼저
   `self.terminal.modes.set(mode, enabled)`를 부른다. `bracketed_paste`에는 그 밖의 처리가 없다. 읽는
   API는 `modes.get(.bracketed_paste)`이고 ghostty 앱이 `input/paste.zig`의 `Options.fromTerminal`에서
   그것을 쓴다. RIS는 `fullReset`이 `modes.reset()`을 불러 끈다(4672줄). 우리 `vt.Screen`의 `stream`은
   `Terminal.vtStream()`이 주는 `TerminalStream`이라 같은 핸들러를 탄다.

3. 라이브러리의 붙여넣기 인코더. `lib_vt.zig`의 `input` 구조체가 `encodePaste` · `isSafePaste` ·
   `PasteOptions`를 내보낸다 — 우리가 import하는 `ghostty-vt` 모듈에서 쓸 수 있다. `encode`는 세 조각
   `[3][]const u8`을 돌려주고, 모드가 켜지면 머리 · 꼬리가 `\x1b[200~` · `\x1b[201~`다. 모드와 무관하게
   제어 바이트 열여섯을 공백으로 바꾸고, 꺼져 있으면 `\n`을 `\r`로 바꾼다. 입력이 `const`인데 바꿀
   것이 있으면 `error.MutableRequired`다. ghostty 앱(`Surface.zig` `completeClipboardPaste`)은 그 에러에서
   복사본을 만들고, 세 조각을 따로 큐에 넣는다.

4. 모드가 꺼진 프로그램이 감싼 글자를 받으면. fish 아래에서 `cat`을 띄우고 `CATLINE`을 그대로 한 번,
   감싸서 한 번 썼다. tty의 에코가 그대로일 때는 `CATLINE`, 감쌌을 때는 `^[[200~CATLINE^[[201~`였다
   (`ECHOCTL`). vim(저장소의 `kernel/vim/vimrc`를 `-u`로 준 것)은 기동할 때 `ESC[?2004h`를 보냈고,
   insert 모드에서 `    alpha\n    beta\n    gamma`를 그대로 쓰면 파일이 4 · 8 · 12칸 들여쓰기의 계단이
   됐고, 감싸면 4 · 4 · 4칸이었다. GE 위험 2를 컨테이너에서 재현하고 감싸기가 그것을 없애는 것을 본
   것이다.

5. 클립보드와 쓰기. `vt.Screen.clip`은 `?[:0]const u8`이고 `copyYank`가 `selectionString`의 할당
   결과를 그대로 들고 있다 — 고정 버퍼도 상한도 없다. `pty.write`(`pty.zig` 131줄)는 다 쓸 때까지
   `write`를 반복하고 0 이하가 오면 조용히 돌아온다. `pty.zig`와 `main.zig`에 `O_NONBLOCK`이 없어서 master
   fd는 blocking이다. 여러 줄 클립보드는 `dumpClip`이 `text=` 뒤에 개행째 찍으므로 둘째 줄이 다음 로그
   줄로 이어진다.

6. vim이 사용자 vimrc를 찾는 법. `vim --version`이 `user vimrc file: "$HOME/.vimrc"`를 첫 자리로
   적는다(둘째 · 셋째는 `~/.vim/vimrc` · `~/.config/vim/vimrc`). 게스트의 `HOME`은 `/`다. 게스트처럼
   꾸민 컨테이너(시스템 vimrc는 저장소의 것, 런타임 대신 stub `defaults.vim`, 빈 `HOME`)에서 pty로
   `vim -e`를 띄웠다. stub에는 이 측정을 위해 `let g:pe_defaults = 1` 한 줄을 넣었다.

   | `~/.vimrc` | `scriptnames` | `set ts?` | `defaults.vim`을 읽었나 |
   |---|---|---|---|
   | 없음 | `/etc/vim/vimrc` · `defaults.vim` | `tabstop=8` | 읽었다 |
   | `config/vimrc`로 가는 댕글링 링크 | 위와 같다 | `tabstop=8` | 읽었다 |
   | 링크 + 주석 한 줄짜리 파일 | `/etc/vim/vimrc` · `~/.vimrc` | `tabstop=8` | 안 읽었다 |
   | 링크 + 주석 + `set tabstop=3` | 위와 같다 | `tabstop=3` | 안 읽었다 |

   댕글링 링크는 "없음"과 같다. 링크로 쓴 `echo … >> ~/.vimrc`는 링크의 대상에 들어갔다. stdin이
   `/dev/null`이면 `vim -e` · `-E` · `-es`가 전부 vimrc를 건너뛰어 `tabstop=8`을 찍었다 — 게이트는 pty
   위의 셸에서 치므로 그 조건이 아니다.

7. service 체인의 기다림. `wait_for_log "eth0: leased 10\.0\.2\.15 " 60`은 329줄의 `boot_ssh()` 함수
   (306~330줄) 안에 있고, 부팅 B · C · D가 343 · 374 · 437줄에서 그 함수를 부른다. `git log -S`로 그
   줄은 `c89157d`(2026-09-27 12:21)에서 들어왔다. 실패 둘(2026-09-28 · 2026-10-04)이 다 그 뒤다. 부팅 A의
   검사 7(248줄)은 같은 기다림 뒤에 0.5초 × 20의 재시도 loop를 갖고 있고, 검사 12의 keyscan과 부팅
   D의 첫 ssh에는 재시도가 없다. GE-M1 루트 게이트의 로그(`/tmp/gate_m1.log`, 그 체인의 실패 덤프)에서
   dhcpcd의 줄은 이 순서였다.

   ```
   08:17:21  eth0: soliciting a DHCP lease / offered 10.0.2.15 / probing address 10.0.2.15/24
   08:17:21  Server listening on 0.0.0.0 port 22.
   08:17:26  eth0: leased 10.0.2.15 for 86400 seconds
   08:17:26  eth0: adding route to 10.0.2.0/24
   08:17:26  eth0: adding default route via 10.0.2.2
   ```

   dhcpcd는 줄마다 두 번 찍는다(stderr의 맨 줄과 `Oct 04 hh:mm:ss [pid]:`가 붙은 줄). 두 패턴 다 맨 줄에
   맞는다.

8. dhcpcd의 순서. Debian 소스 `dhcpcd_10.1.0-11+deb13u4`(sysroot의 `dhcpcd-base`와 같은 판)의
   `src/dhcp.c`에서 `dhcp_bind`가 `loginfox("%s: leased %s for %"PRIu32" seconds", …)`(2326줄)를 먼저
   찍고, 뒤에서 `ipv4_applyaddr(ifp)`(2396줄)를 부른다. `ipv4_applyaddr`(`src/ipv4.c`)는
   `ipv4_daddaddr`로 주소를 붙인 뒤 `rt_build(ifp->ctx, AF_INET)`를 부르고, 그 안에서 `rt_desc("adding",
   …)`가 경로 줄을 찍는다(`src/route.c` 529줄). 그래서 `adding … route` 줄은 주소가 붙은 뒤에만 나온다.

9. `config` 체인의 모양. 같은 디스크로 아홉 번 뜬다. 1차는 빈 디스크에 fish로 떠서 seed를 깔고, 훅이
   `tars-config` · eza 별칭 · `git config --get init.defaultBranch`(ST-M2, 439~453줄) · `tars.conf` 고치기 ·
   zshrc 마커 · `Ctrl+R`을 이 순서로 본다. `Ctrl+R`은 뒤를 흔들어서 맨 끝에 둔다는 주석이 있다. 2차는
   1차가 고친 `shell=zsh`로 뜨고 `watch_console_shell`이 5초를 본 뒤 `shell_config=off`를 친다. 로그
   검사로는 1차가 `seeded /config/{bashrc,zshrc,fish.config}`(1346줄 근처)와 `seeded /config/gitconfig`
   (1355줄)를 보고, 2 · 8 · 9차가 `seeded /config/` 접두가 없는 것을 본다. 7차는 이름을 하나씩 본다.
   `seeded` 줄 수를 세는 검사는 어느 체인에도 없다. `render` 체인의 QEMU 호출(109줄)에는 `-drive`가 없다 —
   그 체인에서 `/.vimrc`는 댕글링이고 vim은 지금과 같다(실측 6의 둘째 줄).

10. 브리핑의 붙여넣기 자리. `copy/check.sh`가 `clip> paste`를 보는 자리는 515 · 564 · 567줄이고 셋 다
    `clip> paste len=11`을 접두로 본다. `hangul/check.sh`는 946 · 997줄에서 `clip> paste` 줄 수만 센다.
    `copy` 체인의 마지막 검사는 20이고 끝에 NUL 음성 검사가 있다. `vt_test`의 마지막 검사는 92다. 기본
    셸은 fish다(`config.zig` 863줄 `shell: Shell = .fish`).

## 비목표

1. 모드가 꺼진 갈래에서 `\n`을 `\r`로 바꾸는 것과 제어 바이트 치환(결정 2). 클립보드가 화면 밖에서 오게
   되면(OSC 52 · 시스템 클립보드) `encodePaste`로 옮기며 함께 연다.
2. 감싸지 않는 여러 줄 붙여넣기를 막거나 묻는 것(ghostty의 `clipboard-paste-protection`). 셸 셋과 vim이
   전부 모드를 켜므로 남는 경우가 모드를 모르는 프로그램뿐이다.
3. OSC 52와 프로세스 사이의 클립보드. CM과 FP의 비목표 그대로다.
4. `/.viminfo`를 `/config`로 남기는 것. GE 결정 6이 적은 대로 지금은 tmpfs라 재부팅에 사라진다.
   사용자 vimrc와 성격이 다르다 — vim이 나올 때마다 쓰는 파일이라 설정 디스크에 쓰기가 는다.
5. 큰 붙여넣기에서 `pty.write`가 멈추는 것(위험 3). non-blocking 쓰기와 남은 바이트의 큐가 필요하고,
   `poll` 루프의 모양이 바뀐다.
6. SLIRP의 SYN 재전송 시각을 재는 것과, 다른 체인의 hostfwd 경합을 훑는 것(결정 1). `firewall` 체인은
   임대 뒤에 타이핑을 먼저 해서 시간 차가 먼저 지나가고, 실패가 관측된 적이 없다.
7. vim의 계단을 게이트에서 보는 것. 들여쓴 줄을 화면에 만들고 잡고 vim에 붙이는 데 타이핑이 많고, 그
   검사가 새로 증명하는 것은 "vim이 감싼 글자를 paste처럼 다룬다"는 vim의 성질이다. 우리 코드의 성질(모드를
   보고 감싼다)은 검사 21 · 22가 본다. 계단이 없어지는 것은 실측 4가 컨테이너에서 봤다.
8. fish의 확장 키 모드(위험 5)와 `tars.conf`로 bracketed paste를 끄고 켜는 것.

## 닫을 때(lead의 몫)

서브프로젝트를 닫을 때 lead가 한다. 구현 서브에이전트는 안 한다.

- 이 design의 `Status:`를 `끝났다(날짜)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄.
- `docs/decisions/project_paste_ergonomics.md`를 만들고 `MEMORY.md`에 한 줄.
- 다시 연 결정에 한 줄씩 덧붙인다. CM design 결정 9와 "비워 둔 자리"의 여러 줄 붙여넣기,
  `docs/decisions/project_copy_mode.md`의 "bracketed paste를 안 쓴다" 절, FP design의 164 · 368줄 근처,
  GE design의 위험 2와 비목표 2 · 4. 각각 "PE-M1(또는 M2)이 이것을 바꿨다"와 `[[project_paste_ergonomics]]`.
- `docs/guides/lessons.md`. "로그 문구는 두 곳에 중복된다"의 `terminal: clip> paste`에 `bracketed=`를
  더한다. "이월 숙제"의 service 두 항목은 M0이 지운다.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-10-04-tars-guest-ergonomics-design.md` — 위험 2(autoindent와 붙여넣기) · 비목표 2 · 4 ·
  결정 4(seed vimrc를 안 고른 이유)
- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 결정 9(bracketed paste를 안 넣었다) · CM-M2(붙여넣기가
  모드를 안 닫는다)
- `docs/specs/2026-09-09-tars-find-paste-design.md` — 결정 3 · 5(검색 프롬프트로 가는 갈래와 첫 줄 자르기)
- `docs/specs/2026-10-04-tars-cursor-shape-design.md` — 결정 7(시스템 vimrc와 stub `defaults.vim`) · 비목표 7
- `docs/specs/2026-09-19-tars-shell-tools-design.md` — 결정 5(gitconfig seed에 `[user]`를 안 넣었다)와 ST-M2의 댕글링 링크
- `docs/decisions/project_gate_screen_echo.md` — 검사 21 · 22와 `config` 판정 글자
- `docs/decisions/project_gate_chain_composition.md` — CM 결정 9가 인용한 부채, 이번에 두 갈래를 다 보는
  이유
- `docs/decisions/project_write_or_reuse.md` — 결정 2에서 `encodePaste`를 안 쓴 저울
