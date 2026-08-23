# Terminal rendering

TR-M0(2026-08-23)에서 화면이 색을 갖게 만들면서 알아낸 것들이다. 설계 전체는
`docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`에 있고,
이 파일은 **다시 조사하면 시간이 드는 사실**과 **모르면 같은 함정에 다시
빠지는 것**만 담는다.

## 색이 해소되는 자리는 `vt.zig` 하나다

렌더러는 팔레트도 SGR도 inverse도 커서도 모른다. `vt.zig`의 `cells()`가
셀마다 `fg`·`bg` 두 숫자를 프레임버퍼와 같은 `0x00RRGGBB` 형식으로 확정해서
넘기고, `main.zig`는 그것을 칠하기만 한다.

**inverse와 커서가 "두 색을 맞바꾼다"는 같은 연산이라 둘 다 여기서
사라진다.** 그래서 `main.zig`는 "반전"이라는 개념 자체를 배우지 않았고,
TR-M2가 스크롤백을 붙일 때도 커서 처리를 다시 손댈 필요가 없다 — 뷰포트
밖으로 나가면 `state.cursor.viewport`가 null이 되기 때문이다.

## 팔레트가 xterm 고전값이 아니다

**빨강이 `#CD0000`이 아니라 `#CC6666`이고, 밝은 빨강이 `#D54E53`이다.**
게이트(`render/check.sh`)가 기대하는 값이 이것이다. 짐작으로 적으면 틀린다.

`\e[1;31m`처럼 bold가 붙으면 팔레트 1번이 아니라 9번이 나온다. 이것은
`Style.fg()`에 `.bold = .bright`를 준 결과이고, 폰트가 하나뿐이라 굵은
자체(字體)가 없는 우리에게는 bold를 표현하는 유일한 길이다.

## `style_id == 0`이면 `style`을 읽으면 안 된다

라이브러리가 계약으로 명시한 자리다(`render.zig:260-262`). 기본값 `0`은
`style.zig:17`의 `default_id`이고, 그 상태에서 `styles[x]`를 읽으면 쓰레기가
나온다. `lib_vt.zig`가 `style` 모듈을 네임스페이스로 내보내지 않으므로
코드에서는 숫자 `0`을 쓰고 출처를 주석으로 적었다.

## `inverse`는 라이브러리가 처리해 주지 않는다

`Style.fg()`도 `Style.bg()`도 이 플래그를 보지 않는다. `\e[7m`을 먹이면
`fg=#FFFFFF, bg=null, inverse=true`가 그대로 나온다 — 색을 맞바꾸는 것은
우리 몫이다.

## libghostty-vt는 aarch64에서 돈다

`terminal/build.zig`가 "arm64로 빌드해야 하는데 검증된 적이 없다
(`src/simd/` 아래에 벡터 코드가 있다)"고 주석으로 적어 둔 채, **`vt_test`를
아무도 실행하지 않는 상태로 두 서브프로젝트를 건너왔다.** TR-M0이 호스트
타깃으로 옮겨 살렸고, 옮기자마자 기존 세 검사가 전부 통과했다. simd는 Google
Highway를 쓰고 ghostty 자체가 Apple Silicon에서 도는 프로그램이라 놀랄 일은
아니었다.

**남은 "빌드만 되는 검사"는 `pty_test` 하나다.** `/usr/bin/fish`를 exec하는데
그 fish가 게스트용 x86_64라 호스트로 옮길 수 없다.

## 문턱값 렌더링은 게이트를 위한 선택이기도 하다

글리프를 알파 블렌딩하지 않고 `coverage > 127`로 찍는다. 8x4x4 폰트를 자기
native 크기인 16px로 굽는 것이라 coverage가 이미 거의 이분값이라는 것이
첫째 이유이고, **블렌딩하면 기대 픽셀 값이 래스터라이저의 안티앨리어싱에
매달려 `pixel>` 검사가 정확한 상수와 비교할 수 없게 된다**는 것이 둘째다.

같은 이유로 게이트는 글자가 있는 셀이 아니라 **배경색을 칠한 공백**을
검사한다. 공백이면 셀 전체가 배경색이라 어느 픽셀을 읽어도 같지만, 글자가
있으면 중앙 픽셀이 글리프의 획일 수 있다.

## 빈 셀이 결과에 들어오기 시작했다

배경색이 생긴 뒤로는 글자가 없어도 그릴 것이 있다(`ls` 출력의 색 띠, 커서
자리, 나중의 선택 영역). 그래서 `cells()`가 `codepoint == 0`인 셀도
내보낸다.

**그 결과 `dumpScreen`이 `utf8Encode(0)`으로 NUL 바이트를 로그에 흘렸다.**
가정이 아니라 실제로 관측했다 — Task 4를 부팅했을 때 시리얼 로그 15,566
바이트 중 2바이트가 NUL이었다. `render/check.sh`의 음성 검사가 이것을
지킨다.

## `grep -qP '\x00'`은 NUL을 못 잡는다

GNU grep 3.11에서 NUL이 든 파일에도 **매치되지 않는다.** 그대로 뒀으면
항상 통과하는 가짜 검사가 게이트에 들어갈 뻔했다. 쓸 것은 바이트 수 비교다.

```bash
[ "$(tr -d '\0' < "$f" | wc -c)" -ne "$(wc -c < "$f")" ]
```

## NUL 한 바이트가 `grep`을 통째로 막는다

위와 짝이 되는 사실이고, 이쪽은 **조사할 때 실제로 막혔다.** 로그에 NUL이
하나라도 있으면 `grep`이 파일을 binary로 취급해 `Binary file ... matches`만
뱉고 내용을 안 준다. 게이트에서 이 일이 벌어지면
`STYLE_LINE="$(grep -E ...)"`가 그 문구를 담게 되고, 뒤따르는 `sed` 좌표
파싱이 조용히 엉뚱한 값을 낸다. NUL 음성 검사는 스크립트 뒤쪽에 있어서
그때는 이미 늦다.

**그래서 `render/check.sh`의 모든 `grep`에 `-a`를 붙였다.** plan에는 없던
보강이다.

## 체인의 시리얼 로그는 통과하면 사라진다

각 `check.sh`가 `-serial file:"$(mktemp)"`로 로그를 받고 **실패했을 때만**
`tail`로 뿜는다. 통과하면 `docker run --rm`과 함께 사라지므로, 로그의 특정
줄을 조사하려면 **한 번의 `docker run` 안에서** 게이트를 돌리고 `/tmp/tmp.*`를
뒤져야 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash device/check.sh > /tmp/gate.out 2>&1
  grep -ah "찾을 문구" /tmp/tmp.*
'
```

## Zig 0.16에는 `std.time.Timer`가 없다

`std.posix.clock_gettime`도 없다. 시간은 `std.Io`를 거친다.

```zig
const t0 = std.Io.Clock.now(.awake, io);
const elapsed_ns = t0.untilNow(io, .awake).nanoseconds;
```

**단조 시계의 이름이 `.monotonic`이 아니라 `.awake`다.**

## 첫 프레임 렌더 시간과 그것이 아직 못 정하는 것

design 위험 2가 "재는 것을 TR-M0의 일로 남긴다"고 한 자리다. 실측값은
**208,835µs = 209밀리초**(1280×800, 첫 프레임).

**이 숫자를 실기 성능으로 읽으면 안 된다.** 근거 셋이다.

- 컨테이너가 arm64인데 `qemu-system-x86_64`를 돌린다. KVM이 아니라 TCG
  명령어 번역이라 게스트의 모든 픽셀 쓰기가 번역을 거친다.
- `fb.fill()`이 1280×800 = 102만 번의 volatile 쓰기다. 셀 배경 칠하기가
  더한 몫보다 이 전면 클리어가 압도적으로 클 가능성이 높다. **즉 부분
  갱신을 도입해도 `fill`을 그대로 두면 별로 안 줄어든다.**
- 첫 프레임이라 글리프 캐시도 페이지도 차갑다. 의도적으로 상한을 쟀다.

그래서 이 숫자가 정당화하는 결론은 "부분 갱신이 필요하다"가 아니라
**"어디에 시간이 드는지 아직 안 갈랐다"**이다. 가르려면 `fill` 하나만 따로
재거나 실기에서 봐야 한다.

## 체인 하나의 값은 예상의 두 배가 넘었다

2026-08-23 실측이다.

| 구성 | 시간 |
|---|---|
| 여섯 체인 (2026-08-22 기준선) | 37분 43초 |
| 여섯 체인 (`TERM` 변경 후 회귀 확인) | 39분 51초 |
| **일곱 체인 (TR 등록 후)** | **46분 4초** |

**체인 하나가 더한 비용이 6분 13초다.** plan은 "커널 빌드 3회 = 약 2분
40초"로 예상했는데 그 두 배가 넘는다. 차이는 TR 체인에만 있는 항목들이다.

- `vt_test`를 위해 libghostty-vt를 **arm64로도** 빌드한다(게스트용 x86_64와
  별개로 한 벌 더).
- 회차마다 `sendkey`를 28타 치는데 타마다 `sleep 0.3`이라 8.4초, 그 뒤에
  `sleep 3`이 붙는다. 3회면 이것만 35초다.

`clean()`에서 커널을 빼는 논의가 여전히 게이트 시간의 가장 큰 단일 항목이라는
사실은 [[project_kernel_config]]에 있고, 이 표는 **체인을 하나 더할 때
커널 빌드만 세면 과소평가한다**는 것을 보탠다.

## 관련 기억

[[project_gate_chain_composition]] · [[project_guest_environment]] ·
[[project_kernel_config]] · [[project_build_host_arch]] · [[project_copy_mode]]
