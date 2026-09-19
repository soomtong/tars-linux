# ST-M1 — 셋의 씨앗에 eza 별칭 넷을 넣는다

> 이 plan을 실행하는 사람에게: 이 milestone은 코드가 씨앗 문자열과 검사 하나에
> 들어간다. TDD가 아니라 기존 검사(config_test · config 체인 · net 체인)를
> 다시 돌리는 구조다.

Goal: ST design 결정 2·3·4의 별칭 넷을 셋의 씨앗에 넣고, 그 넷이 게이트가
치는 이름을 가리는 유일한 자리(`ls`)가 게이트를 안 깨뜨린다는 것을 부팅으로
확인한다.

Architecture: 씨앗은 `init/src/config.zig`의 `rcSeed()` 문자열 리터럴이다
(SC 결정 7). 별칭 줄은 셸 셋에 각각 문자로 들어간다 — 훅 줄과 달리 배열로
조립하지 않는다. 조립하면 `config_test.zig`의 새 검사("씨앗에 있는 별칭
이름이 허용 목록 안인가")가 tautology가 된다(`hookLines()`의 주석이 적어 둔
자리와 같다).

Tech Stack: Zig 0.16(init 빌드·단위 테스트) · bash(config·net 체인) ·
QEMU(게이트가 띄운다)

---

## Task 1 — 씨앗 셋에 별칭 넷

`init/src/config.zig`의 `rcSeed()` 세 갈래에서 `alias tars-rc=...` 바로 뒤에
같은 넷을 넣는다. 셋의 문법이 같다(`alias 이름='본문'`).

```
alias ls='eza'
alias ll='eza -l --group-directories-first'
alias la='eza -la --group-directories-first'
alias lt='eza --tree --level=2'
```

주석이 본문의 세 배쯤 된다. 담을 것 셋:

1. 이 넷이 왜 여기 있는가 — 도구 65개 중 이름으로만 닿던 것 하나를 습관적인
   이름에 앉힌다(design 결정 2).
2. `ls`가 유일한 셰도이고, 게이트가 치는 자리 셋을 재서 통과시킨 것
   (design 실측 3·4). 새 이름을 더할 때 먼저 볼 것.
3. `--icons`를 안 붙이는 이유(design 실측 4 — 폰트에 PUA 글리프가 0개다).

Acceptance: `zig build test`의 `expectQuietSeed`가 셋 다 통과한다(별칭 줄은
이미 허용 범주다).

## Task 2 — 이름 목록을 테스트가 못 박는다

`init/src/config_test.zig`에 둘을 더한다.

```
const ALLOWED_ALIAS_NAMES = [_][]const u8{
    "tars-config", "tars-rc",          // SC-M1
    "ls", "ll", "la", "lt",            // ST-M1
};
const ALIASED_TOOLS = [_][]const u8{"eza"};
```

- `expectAliasNames(sh)`: 씨앗의 모든 `alias` 줄에서 이름을 뽑아 허용 목록과
  맞춘다. 목록 밖이면 실패하고 허용 목록을 찍는다. 이것이 design 결정 7이다 —
  `expectQuietSeed`는 `alias `로 시작하는 줄을 전부 통과시키므로 이름을
  더하는 일에 저항이 없다.
- `expectAliasesCoverTheTools(sh)`: `ALIASED_TOOLS`의 도구가 씨앗의 별칭 줄
  어딘가에 나오는지 본다. `expectHooksCoverTheTools`와 같은 자리다 — 별칭
  넷을 다 지우고 이 배열도 함께 지우면 정방향·역방향이 다 만족되므로.

Acceptance: `zig build test`가 `PASS`. 별칭 이름 하나를 목록 밖으로 바꾸면
빨개진다(손으로 한 번 해 보고 되돌린다).

## Task 3 — 게이트가 별칭이 도는 것을 본다

`config/check.sh`의 1차 부팅 훅에서 `tars-config` 확인 바로 뒤(EDIT_KEYS
앞)에 한 줄을 친다.

```
EZA_LS_KEYS=(l s spc minus l spc slash c o n f i g slash t a r s dot c o n f ret)
```

판정 글자는 `\.rw-`다. eza의 긴 목록은 파일 종류를 `.`으로 찍고 GNU ls는
`-`으로 찍는다(design 실측 6). 그래서 이 한 줄이 둘을 동시에 본다 — `ls`가
살아 있다는 것과 그것이 eza로 간다는 것. 타이핑한 줄에는 그 글자가 없다.

주석에 담을 것: 왜 화면 판정이 필요한가(별칭이 정의됐다는 것과 도는 것은
다르다 — SM-M1이 위젯에 대해 같은 구분을 했다), 그리고 이 글자가 eza에만
있는 이유.

Acceptance: config 체인 1차 부팅이 이 줄에서 초록.

## Task 4 — README

`### 기계가 기억하는 것 둘` 절에 별칭 넷과 `ls` 셰도를 한 문단으로 적고,
`### 셸 설정을 고쳤는데 셸이 안 뜨면` 절 앞이나 뒤에 한 줄을 더한다 —
씨앗은 이미 있는 파일을 안 덮으므로, 이미 쓰던 기계가 새 별칭을 받으려면
`/config/{bashrc,zshrc,fish.config}`를 지우고 재부팅한다(그 경로는
`config/check.sh`의 6·7차가 매번 밟는다).

## Task 5 — 돌린다

| 순서 | 명령 | 무엇을 보는가 |
|---|---|---|
| 1 | `docker run --rm -v "$PWD/init:/w" -w /w tars-devcontainer zig build test` | 단위 검사 |
| 2 | `docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c './config/check.sh'` | 9부팅. `ls` 자리 셋 중 둘 |
| 3 | `docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c './net/check.sh'` | `ls /sys/class/net` |

3이 초록이면 결정 2의 증거가 선다. 어느 하나가 `ls` 자리에서 죽으면 별칭
넷 중 `ls` 한 줄을 빼고 다시 돌린다 — 나머지 셋(`ll`·`la`·`lt`)은 게이트가
치는 이름이 아니라 안전하고, 그때는 design 결정 2를 "안 가린다"로 고친다.

## 다음

M2 — gitconfig 씨앗.
