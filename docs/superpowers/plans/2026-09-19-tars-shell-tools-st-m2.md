# ST-M2 — gitconfig를 씨앗으로 만들어 댕글링 링크를 채운다

> 이 plan을 실행하는 사람에게: 씨앗 하나와 검사 셋이 늘어난다. TDD가 아니라
> 기존 검사(config_test · config 체인 · tools 체인)를 다시 돌리는 구조다.

Goal: `/.gitconfig -> config/gitconfig`가 가리키는 자리를 채운다(design 결정
5). 지금 그 파일을 만드는 코드가 저장소에 한 줄도 없어서, 새 디스크·실기의
그 링크는 영원히 댕글링이다.

Architecture: rc 셋을 깔던 자리를 파일 하나짜리 함수로 좁히고(`seedOneFile`),
gitconfig를 그 위에 얹는다. 씨앗은 `rcSeed()`처럼 문자열 리터럴이다 — 실체는
설정 디스크의 `/config/gitconfig`이고 `O_EXCL`이라 이미 있으면 안 건드린다.

Tech Stack: Zig 0.16 · bash · git(게이트가 친다)

---

## Task 1 — 씨앗 함수를 일반화하고 gitconfig를 더한다

`init/src/config.zig`:

```
pub const GITCONFIG_PATH: [:0]const u8 = "/config/gitconfig";
pub const GITCONFIG_SEED = \\...;
```

내용 여섯 줄 남짓 — `[init] defaultBranch = main` · `[core] pager = less -FRX` ·
`[color] ui = auto` · `[alias] st · lg`. `[user]`는 없다(design 결정 5: 실측 5가
신원이 `/etc/passwd`에서 나오는 것을 보였고, 넣으면 `tools/check.sh` 검사 13의
판정 값과 겹친다).

`seedRcFile(sh)`의 몸통에서 경로와 글자를 인자로 받는 `seedOneFile(path, text)`를
빼고, `seedRcFiles()`와 새 `seedGitconfig()`가 그 위에 선다. 로그 줄은 그대로
`tars-init: seeded <경로>`다 — 게이트가 경로로 grep하기 때문이다.

`init/src/main.zig`: `config.seedRcFiles()` 바로 뒤에 `config.seedGitconfig()`.
조건(`if (storage_mounted)`)이 같아야 한다 — 디스크가 없으면 /config는 tmpfs이고 거기
쓴 것은 재부팅에 사라진다.

## Task 2 — 단위 검사

`init/src/config_test.zig`에 `expectGitconfigSeed`를 더한다. 보는 것 셋:

1. 빈 파일이 아니고 줄바꿈으로 끝난다.
2. `#`과 `[...]` 절을 뺀 모든 줄에 `=`가 있다 — 빠지면 git이 부팅 뒤 매
   명령마다 `bad config line N`을 찍는다. 0.1초에 잡을 수 있는 실패다.
3. `defaultBranch`를 담고 `[user]` 절은 없다 — 3번이 design 결정 5의 두
   근거를 코드 모양으로 못 박는다.

절과 키가 하나도 안 보이면 그것도 실패다("통과했다"와 "볼 것이 없었다"를
가르는 자리).

## Task 3 — 게이트가 본다

`config/check.sh`의 1차 부팅 훅 끝(별칭 확인 바로 뒤)에 한 줄을 친다.

```
GITCONF_KEYS=(g i t spc c o n f i g spc minus minus g e t spc i n i t dot d e f a u l t shift-minus B r a n c h ret)
```

판정 글자는 행 첫머리의 `main`이다(`\| main`). 재는 것이 둘이다 — 파일이
깔렸다는 것과 그 값이 git에 실제로 닿는다는 것. `tars-init: seeded
/config/gitconfig` 줄은 main()의 grep 목록에 따로 더한다.

`B`는 `shift-b`다. `camelCase`를 피해 `defaultbranch`로 쓸 수는 없다 — git의
키 이름은 대소문자를 안 가리지만, 게이트가 재는 것이 "우리가 적은 키"이므로
적은 그대로 친다.

## Task 4 — README

`### 별칭` 절 뒤에 한 문단. `/config/gitconfig`가 무엇을 담는지, `git config
--global`이 링크를 통해 그 파일에 쓰는지, `[user]`가 없는 이유(신원은
`/etc/passwd`에서 나온다 — 바꾸려면 그 파일이나 `git config --global`).

## Task 5 — 돌린다

| 순서 | 명령 | 무엇을 보는가 |
|---|---|---|
| 1 | `zig build test` (컨테이너) | 새 단위 검사 |
| 2 | `./tools/check.sh` | 검사 13이 그대로 초록인가(이 체인엔 설정 디스크가 없어 씨앗이 안 깔린다) |
| 3 | `./config/check.sh` | `main`과 `seeded /config/gitconfig` |
| 4 | `./check.sh` | 루트 게이트 12체인 |

2가 초록이라는 것이 "씨앗이 검사 13을 거짓으로 만들지 않는다"의 증거다.

## 다음

루트 게이트 뒤에 design의 Status와 `docs/decisions/project_shell_tools.md`.
