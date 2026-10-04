# PE-M2 — 사용자 vimrc가 재부팅을 넘는다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
Status: 끝났다(2026-10-05 새벽, 루트 게이트는 10-04에 시작). 실측은 맨 아래 "PE-M2가 실측한 것" 절에 있다.

## 누가 무엇을 하나

design 결정 9. Task 0~7은 구현 서브에이전트(Sonnet)가 한다. Task 8(루트 게이트 · 실측 절 · commit ·
서브프로젝트 닫기)은 lead가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` ·
각 Task의 명령 출력을 그대로 보고한다. 이 plan의 "실측한 것" 절은 구현자가 고치지 않는다.

구현자는 main 작업 트리에서 직접 편집한다(그때는 루트 게이트가 돌고 있지 않다 — Task 0-1이 확인한다).

| 파일 | 무엇을 |
|---|---|
| `kernel/make_initrd.sh` | `/.vimrc` 링크 한 줄과 주석(rc 링크 셋 바로 뒤), CU-M1 블록 주석의 `/.vimrc` 언급 |
| `init/src/config.zig` | `VIMRC_PATH` · `VIMRC_SEED` · `seedVimrc`(`seedGitconfig` 바로 뒤) |
| `init/src/main.zig` | `config.seedGitconfig();` 바로 뒤에 `config.seedVimrc();`와 주석 |
| `init/src/config_test.zig` | `expectVimrcSeed`(`expectGitconfigSeed` 바로 뒤)와 그 호출 |
| `kernel/vim/vimrc` | 머리 주석의 둘째 문단 첫 두 줄 |
| `config/check.sh` | 키 배열 넷, 1차 훅의 검사 셋, 1차 로그 검사 하나, 2차 훅의 검사 하나 |
| `tools/check.sh` | 검사 1의 `WANT`에 `.vimrc` |

고치는 자리는 심볼과 `rg` 패턴으로 적는다. 줄 번호는 2026-10-04 PE-M1 commit 기준의 참고값이다
(PE-M1은 이 일곱 파일을 안 건드렸으므로 `d237fb2`의 줄 번호와 같다).

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드는 언제나 컨테이너에서 한다 — 호스트 `PATH`의
zig는 0.17이고 컨테이너는 0.16.0이다. 측정용 파일은 `/tmp/run/pem2i/` 아래에 둔다. `/tmp/run/pem2/`가
아닌 이유는 그 디렉터리에 이 plan을 쓰며 만든 측정 파일(확정 1~5의 하네스 · 편집 조각 · 사본)이 있기
때문이다.

## 이 milestone이 끝나면

- initrd에 `/.vimrc -> config/vimrc` 링크가 있다. 설정 디스크가 붙은 부팅에서 `init`이 `/config/vimrc`가
  없으면 주석뿐인 seed(843바이트)를 깔고 `tars-init: seeded /config/vimrc`를 찍는다. 있으면 손대지 않는다.
- 게스트의 vim이 시스템 vimrc(`/etc/vim/vimrc`) 다음에 그 seed를 사용자 vimrc로 읽는다. seed에는 설정이
  한 줄도 없어서 vim의 동작은 PE-M2 전과 같다.
- 사람이 `/.vimrc`(또는 `/config/vimrc`)에 적은 설정이 재부팅을 넘는다. `config` 체인이 1차에 fish로
  `set tabstop=3`을 더하고 2차에 zsh에서 vim이 `tabstop=3`을 말하는 것을 본다.
- 설정 디스크가 없는 부팅(`render` 체인 · ISO 세션)에서는 링크가 댕글링이고 vim은 지금처럼 stub
  `defaults.vim`을 읽는다(design 실측 6).
- `config_test`가 seed를 다섯 가지로 본다. `tools` 체인 검사 1이 initrd의 `.vimrc`를 본다.

## 착수 전에 확정한 것

1번~5번은 2026-10-04에 이 plan을 쓰며 잰 것이다. 방법은 design 실측 6과 같은 결이다 —
`tars-devcontainer` 이미지에 zsh `5.9-8+b24` · fish `4.0.2-1` · vim `2:9.1.1230-2` · python3-pyte(arm64,
sysroot와 같은 판)를 깐 측정 컨테이너를 게스트처럼 꾸몄다. 시스템 vimrc는 저장소의 `kernel/vim/vimrc`,
`/usr/share/vim/vim91`은 치우고 저장소의 stub `defaults.vim` 하나만, terminfo는 게스트와 같이
`x/xterm` · `x/xterm-256color` 둘만(`make_initrd.sh` 561~564줄), `HOME=/`, `/.vimrc -> config/vimrc`, seed는
`/config/vimrc`. 셸은 python `pty.fork`에 47 × 100, `TERM=xterm-256color`, `LANG=C.UTF-8`로 띄우고, 출력을
pyte에 먹여 행을 ` | `로 이어 찍었다. 하네스는 `/tmp/run/pem2/probe.py`, seed는 `/tmp/run/pem2/seed_vimrc`다.

1. design 결정 8의 명령(`vim -e +scriptnames +qa`)은 대체 화면에 찍는다. design은 "대체 화면에
   들어가지 않고 줄 단위로 찍으므로 `screen>`에 그대로 남는다"고 적었는데, pty의 원본 바이트가 이랬다.

   ```
   \x1b[?1049h\x1b[22;0;0t ... \x1b[47;1H\r\n  1: /etc/vim/vimrc\r\r\n  2: /.vimrc\r ... \x1b[?1049l\x1b[23;0;0t
   ```

   vim은 Ex 모드(`-e`)에서도 terminfo `xterm-256color`의 smcup(`ESC[?1049h`)을 보내 대체 화면에 들어가고,
   거기에 찍은 뒤 rmcup(`ESC[?1049l`)으로 나온다. ghostty vt는 1049를 구현하므로 나오는 순간 원래 화면이
   돌아오고 출력이 화면에서 사라진다. 그 출력이 `screen>` 프레임에 남는지는 우리 터미널이 그 사이에
   렌더하는지에 달려 있다 — vim이 바로 나가므로 대개 한 번의 `read`에 다 들어와서 남지 않을 것이고, 남는
   회차가 있어도 흔들린다. pyte는 1049를 구현하지 않아서 측정 화면에는 출력이 남아 보였다. design 실측
   6이 이것을 놓친 이유도 그것으로 보인다.

   대안 셋을 쟀다.

   | 명령 | `ESC[?1049h` | 결과 |
   |---|---|---|
   | `vim -e +scriptnames +qa \| cat` | 있다 | 대체 화면 그대로다 |
   | `TERM=dumb vim -e +scriptnames +qa` | 없다 | 원래 화면의 맨 아래 행(`ESC[47;1H`)부터 찍는다 |
   | `vim -T dumb -e +scriptnames +qa` | 없다 | 위와 같다 |

   `-T dumb`을 고른다. 대문자가 하나(`shift-t`)이고 fish와 zsh에서 글자 그대로 같다. 게스트에는 `dumb`의
   terminfo가 없는데, 측정 컨테이너의 terminfo를 게스트와 같은 둘로 줄인 상태에서 vim이 에러 없이 내장
   `dumb` 항목으로 넘어갔다. `ESC[47;1H`는 그 내장 항목의 커서 이동이다. vimrc를 읽는 것과 그 순서는
   터미널 이름과 무관하다 — `-T dumb`에서도 `scriptnames`가 `1: /etc/vim/vimrc`를 찍었다.

2. 게스트처럼 `HOME=/`이면 vim이 사용자 vimrc를 `~/.vimrc`가 아니라 `/.vimrc`로 찍는다. design 실측 6은
   `HOME`을 빈 디렉터리로 두었기 때문에 `~` 축약이 나왔다. 그래서 1차의 판정 글자는 design의
   `\| +2: ~/\.vimrc`가 아니라 `\| +2: /\.vimrc`다. fish에서 `-T dumb`으로 잰 `scriptnames`의 행이다.

   | `/.vimrc` | `scriptnames`의 2 |
   |---|---|
   | `config/vimrc`로 가는 댕글링 링크 | `  2: /usr/share/vim/vim91/defaults.vim` |
   | 링크 + seed | `  2: /.vimrc` |

   두 행 다 앞에 공백이 둘이다(`%3d: `). `/.vimrc`는 2차 이전에 1차가 치는 `echo … >> /.vimrc`에도 있지만,
   그 줄은 프롬프트로 시작하고 `scriptnames` 검사보다 뒤에 친다.

3. vimrc에 틀린 줄이 있어도 `scriptnames`는 2 자리에 `/.vimrc`를 찍는다. seed 끝에 `bogus_command_here`를
   더하고 쳤을 때의 화면이다.

   ```
   Error detected while processing /.vimrc: | line   23: | E492: Not an editor command: bogus_command_here |   1: /etc/vim/vimrc |   2: /.vimrc | root@… ~ [1]#
   ```

   design 결정 8의 표는 "seed에 에러가 있으면 이 자리에 `E숫자:` 줄이 먼저 나온다"고 적었다. 그 줄이
   나오는 것은 맞지만 양성 기다림(`2: /.vimrc`)은 그래도 초록이다. 그래서 1차에 음성 검사 하나를 더한다
   — `screen>` 줄 어디에도 `Error detected while processing`이 없다. 이 체인에서 vim을 띄우는 것은 그
   자리가 처음이다. 이 검사는 mutation 5가 확인한다.

4. zsh의 `?`. 2차는 zsh로 뜬다(1차가 `shell=zsh`로 고친다). 따옴표 없이 `vim -T dumb -e +set\ ts? +qa`를
   치면 zsh가 `?`를 glob으로 펴려다 `zsh: no matches found: +set ts?`를 찍고 명령을 안 돌린다.
   `+'set ts?'`로 감싸면 `  tabstop=3`(앞 공백 둘)이 찍힌다. fish 4.0.2에서도 감싼 모양이 그대로 돈다(seed만
   있을 때 `  tabstop=8`).

   키 이름은 전부 저장소에서 이미 쓰인다. 게스트 키맵(`terminal/src/input.zig`의 `qwerty_keymap`)의 13 ·
   40 · 52 · 53번이 `=`/`+` · `'`/`"` · `.`/`>` · `/`/`?`다.

   | 글자 | 키 이름 | 이미 쓰는 자리 |
   |---|---|---|
   | `+` | `shift-equal` | `net/check.sh` 1141줄(`date -u +%Y`, fish) |
   | `'` | `apostrophe` | `render/check.sh` 147 · 468줄(fish) |
   | `?` | `shift-slash` | `render/check.sh` 480줄(`type_text`, 924줄의 `?1049h`를 fish에서 친다) |
   | `T` | `shift-t` | 대문자는 `shift-<글자>`(`config/check.sh`의 `GITCONF_KEYS`가 `shift-b`) |
   | `>` | `shift-dot` | `config/check.sh` 74줄 `EDIT_KEYS` |
   | `3` | `3` | 숫자 키는 이름이 숫자다(`NEG_MARK_KEYS`의 `1`) |

   `~`와 `"`는 칠 일이 없다. `~`(`grave_accent`)는 저장소에서 한 번도 쓴 적이 없어서 피했다 — 그래서
   append의 대상도 `~/.vimrc`가 아니라 `/.vimrc`다.

5. seed 전문(Task 2의 `VIMRC_SEED`)을 그 하네스의 `/config/vimrc`로 두고 1차 · 2차의 흐름을 그대로 쳤다.
   seed는 843바이트 · 21줄 · 가장 긴 줄 75칸 · 전부 ASCII · `tabstop` 0개다.

   ```
   fish:  |   1: /etc/vim/vimrc |   2: /.vimrc | … vim -T dumb -e +'set ts?' +qa |   tabstop=8 | … echo set tabstop=3 >> /.vimrc | … grep tabstop /config/vimrc | set tabstop=3 | …
   zsh:   |   tabstop=3 | f947b3a9f9c7# exit
   ```

   에러 줄은 없었고 `ESC[?1049h`도 없었다. append 뒤 `/config/vimrc`는 857바이트이고 마지막 두 줄이
   `"set nolist`와 `set tabstop=3`이었다(링크로 쓴 것이 대상에 들어갔다). seed의 예시 셋에서 앞의 `"`를
   지운 줄을 붙이고 `+'set nu? rnu? list?'`를 물으면 `nonumber | norelativenumber | nolist`가 에러 없이
   나왔다.

6. `seedOneFile`(`init/src/config.zig` 1287줄). 플래그는 `.ACCMODE = .WRONLY, .CREAT = true, .EXCL = true`이고
   `.TRUNC`는 없다. `EEXIST`면 아무것도 안 찍고 돌아오고, `writeAll`이 성공하면
   `tars-init: seeded {s}`(경로)를 찍는다. 그래서 1차의 로그 검사 글자는 `tars-init: seeded /config/vimrc`다.
   `seedOneFile`은 `pub`이 아니지만 `seedVimrc`가 같은 파일에 있으므로 부를 수 있다.

   design mutation 4("`O_EXCL`을 지운다 → 2차의 `seeded /config/` 음성 검사와 `tabstop=3` 기다림이 함께
   빨개진다")는 코드로 따지면 절반만 맞다. `.EXCL`만 지우면 `O_CREAT | O_WRONLY`가 기존 파일을 오프셋 0에서
   열고, seed 843바이트가 파일 앞의 843바이트(같은 글자)를 덮어쓴다. `O_TRUNC`가 없으므로 그 뒤에 사람이
   더한 `set tabstop=3`은 남는다. 그러면 2차의 `tabstop=3` 기다림은 초록이고, 2차의 `seeded /config/`
   음성 검사(1485줄)만 빨개진다. "매 부팅 덮어쓴다"를 글자 그대로 만들려면 `.EXCL = true`를 `.TRUNC = true`로
   바꿔야 한다. 이 plan의 mutation 4는 그 모양이다(Task 7). 이 단락은 재지 않고 코드로 따진 것이다.

7. `config/check.sh`의 자리(design 실측 9를 다시 봤다).
   - 1차 훅 `edit_config_in_guest`의 순서는 `tars-config`(SC-M1) → `ls -l /config`(ST-M1) → `git config --get
     init.defaultBranch`(ST-M2, 453줄의 `echo "boot 1: git read …"`로 끝난다) → 빈 줄 둘 → `EDIT_KEYS` →
     `APPEND_KEYS` → `Ctrl+R`(맨 끝이어야 한다는 주석이 있다)이다. 새 검사 셋은 453줄 바로 뒤에 든다.
   - 2차 훅 `watch_console_shell`은 `sleep 5` → 프롬프트 대기 → monitor 연결 → `type_keys "${OFF_KEYS[@]}"`
     (560줄) → 되읽기다. 새 검사는 560줄 바로 앞이다. 실패하면 fd 3을 닫고 `return 1`한다(3차 훅
     `plant_broken_rc`의 실패 갈래와 같은 모양).
   - 훅이 1을 돌려주면 `boot_once`가 거짓이 되고, 부르는 쪽이 `report_failure`를 부른다. 1차에서는
     `FAIL(boot 1): …` 다음에 `FAIL: first boot did not seed and edit /config/tars.conf`가, 2차에서는
     `FAIL(boot 2): …` 다음에 `FAIL: second boot never started a console shell`이 나온다(두 번째 문구는
     원인을 말하지 않는다 — 앞 줄이 원인이다).
   - 1차의 로그 검사는 1355~1358줄(gitconfig) 바로 뒤에 든다. 2 · 8 · 9차의 `tars-init: seeded /config/`
     음성 검사(1485 · 1776 · 1853줄)는 접두로 보므로 고치지 않아도 vimrc를 덮고, 7차(1697~1705줄)는
     이름을 하나씩 보므로 영향이 없다. 다른 체인에 `seeded` 줄 수를 세는 검사는 없다(`machine/check.sh`의
     `seeded`는 FAIL 문구 안의 낱말이다).
   - `/config`는 `MS_SYNCHRONOUS`로 마운트된다(`config.zig`의 `writeAll` 주석). 그래서 fish의 `>>`가
     돌아온 순간 그 줄은 디스크에 있고, `boot_once`가 QEMU를 죽여도 2차가 읽는다.
   - 체인이 끝나도 디스크 이미지 `out/config.img`가 저장소에 남는다. 그래서 체인 뒤에 `debugfs`로
     `vimrc`를 읽어 "아홉 부팅 뒤에도 seed + 사람의 줄"인 것을 볼 수 있다(Task 6-3).

8. `kernel/vim/vimrc` 머리 주석의 `/.vimrc`는 세 자리가 아니라 두 자리다(5줄 · 8줄). design 결정 7은
   "세 자리"로 적었다. 5줄은 "user vimrc (/.vimrc)"라 링크의 정체를 적을 자리이고, 8줄("put this in
   /.vimrc")은 사람이 칠 경로라 그대로 둔다. 그래서 5~6줄 두 줄을 네 줄로 바꾼다. 이 파일은 ASCII ·
   영어다.

9. `tools/check.sh` 검사 1의 `WANT`는 `make_initrd.sh`가 손으로 거는 링크를 전부 literal로 적는다
   (`.gitconfig` 183줄, `.bashrc .zshrc .config/fish/config.fish` 193줄). design 결정 7의 다섯 자리에는
   없지만 같은 관습이라 `.vimrc`를 더한다. mutation 1(링크 줄을 지운다)이 `tools` 체인에서는 부팅 전에
   `FAIL: .vimrc is missing from the initrd`로 드러난다.

10. `config` 체인의 시간. 마지막 실측은 2026-09-13의 2분 06.87초 ~ 2분 10.01초다(NW design 1257줄, BB-M2
    뒤). 그 뒤 ST-M2 · ST-M3 · TQ-M1이 1차에 검사를 더했으므로 Task 0-4가 지금 값을 잰다. 이 milestone은
    1차에 타이핑 셋(약 80키)과 기다림 둘, 2차에 타이핑 하나(약 40키)를 더하므로 20초 안팎 길어질 것이다.

11. 이 plan의 편집은 한 번 맞춰 봤다. Task 1~6의 편집 전후를 python 정확 치환(치환마다 맞는 수가 1인지
    확인)으로 저장소 파일의 사본(`/tmp/run/pem2/plan/`)에 적용했다. 사본과 원본의 차이는 아래와 같고,
    셸 사본 셋은 `bash -n`을, `config/check.sh` · `tools/check.sh` 사본은 진입 검사 셋(`ENTRY-OK`)을
    통과했다. Zig 사본 셋은 측정 컨테이너 안에서 `zig ast-check`와 `zig fmt --check`(0.16.0)를 통과했다.
    seed 리터럴을 풀어 낸 글자는 확정 5의 seed와 바이트까지 같았다(843바이트). `zig build`는 안 돌렸다 —
    이 plan을 쓰는 동안 PE-M1의 루트 게이트가 돌고 있어서 빌드를 금지했다. 그래서 컴파일은 Task 4-3이
    처음 한다.

    | 파일 | 더한 줄 | 지운 줄 |
    |---|---|---|
    | `kernel/make_initrd.sh` | 17 | 3 |
    | `init/src/config.zig` | 57 | 0 |
    | `init/src/main.zig` | 4 | 0 |
    | `init/src/config_test.zig` | 64 | 0 |
    | `kernel/vim/vimrc` | 4 | 2 |
    | `config/check.sh` | 107 | 0 |
    | `tools/check.sh` | 6 | 0 |

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트가 없는지 본다. Task 0-4 · 6 · 7이 docker로 `config` 체인을 돌리므로 겹치면 monitor
   포트 45456이 부딪친다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다(측정 컨테이너 `pem2-measure`가 보이면 lead가
   지우지 않은 것이다 — 그 이름 하나만 보이면 `docker rm -f pem2-measure`로 지우고 계속한다).

2. 작업 트리가 깨끗한지 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: `git status`는 0줄(이 plan 파일이 untracked로 보이는 것은 정상), 마지막 commit은 `PE-M1: …`이다.
   PE-M1의 파일(`copy/check.sh` · `terminal/src/*.zig` 등)이 `M`으로 보이면 PE-M1이 아직 commit되지 않은
   것이다 — 멈추고 보고한다.

3. 고칠 자리가 그대로인지 본다.

   ```bash
   rg -n 'VIMRC|seedVimrc|config/vimrc|WORKDIR/\.vimrc' init/src kernel config tools
   rg -n 'ln -sf config/zshrc|사용자 vimrc\(/\.vimrc\)' kernel/make_initrd.sh
   rg -n 'pub fn seedGitconfig|config\.seedGitconfig\(\);|^fn expectGitconfigSeed|try expectGitconfigSeed\(\);|^/// 히스토리 env가 셸의 성질과' init/src
   rg -n '^BPROD_WIDGET_KEYS|^# 1차 부팅에서 QEMU를 죽이기 전에|git read init.defaultBranch=main|type_keys "\$\{OFF_KEYS\[@\]\}"|seeded the gitconfig too' config/check.sh
   rg -n '^WANT\+=\(etc/vim' tools/check.sh
   rg -n '/\.vimrc' kernel/vim/vimrc
   ```

   기대(줄 번호는 참고). 첫 명령은 0줄이다.

   ```
   235:# 사용자 vimrc(/.vimrc)를 이 파일 뒤에 읽으므로 사람이 `set t_SI= t_SR= t_EI=`로
   367:ln -sf config/zshrc "$WORKDIR/.zshrc"
   init/src/config.zig:1276:pub fn seedGitconfig() void {
   init/src/config_test.zig:469:fn expectGitconfigSeed() !void {
   init/src/config_test.zig:535:/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정 3).
   init/src/config_test.zig:1084:    try expectGitconfigSeed();
   init/src/main.zig:800:        config.seedGitconfig();
   366:BPROD_WIDGET_KEYS=(e c h o spc b p r o d w shift-4 shift-9
   371:# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
   453:  echo "boot 1: git read init.defaultBranch=main out of the seeded /config/gitconfig"
   560:  type_keys "${OFF_KEYS[@]}"
   1358:echo "boot 1: init seeded the gitconfig too (the .gitconfig link has a target now)"
   207:WANT+=(etc/vim/vimrc usr/share/vim/vim91/defaults.vim)
   5:" vim reads this file first and the user vimrc (/.vimrc) after it, so any line
   8:" To turn off only the cursor shapes, put this in /.vimrc:
   ```

4. `init`의 호스트 검사와 `config` 체인을 한 번씩 초록으로 본다. 체인은 약 2분 30초다(확정 10). 시리얼
   로그도 받아 둔다 — Task 6에서 PE-M2 전후를 나란히 보기 위해서다.

   ```bash
   mkdir -p /tmp/run/pem2i/base
   docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
     bash -c 'zig build test > /tmp/t.out 2>&1; echo "exit=$?"; grep -ac "^PASS" /tmp/t.out; grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
   { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i -w /workspace \
       tars-devcontainer bash -c '
     bash config/check.sh > /tmp/run/pem2i/base/chain.log 2>&1; echo "exit=$?"
     n=0; for f in /tmp/tmp.*; do
       if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /tmp/run/pem2i/base/serial_$n.log; fi
     done' ; } 2> /tmp/run/pem2i/base/time
   tail -2 /tmp/run/pem2i/base/chain.log; cat /tmp/run/pem2i/base/time
   ls /tmp/run/pem2i/base/ | wc -l
   rg -c --include-zero 'seeded /config/' /tmp/run/pem2i/base/serial_*.log
   ```

   기대: `zig build test`는 `exit=0`, `^PASS` 줄의 수(이 수를 기준값으로 보고한다 — Task 4-3에서 같은 수여야
   한다), `FAIL` · `error:` 0줄. 체인은 `exit=0`, `chain.log`의 마지막 줄 `PASS`, 시리얼 로그 아홉
   (`ls`가 `chain.log` · `time` 포함 11). `seeded /config/`는 1차 로그가 `4`(`bashrc` · `zshrc` ·
   `fish.config` · `gitconfig`), 7차 로그가 `1`(`zshrc`), 나머지 일곱이 `0`이다(파일 이름은 `mktemp`의
   순서라 부팅 순서와 다르다). 넷 · 하나가 아니면 그 출력을 그대로 보고한다. `time`의 `real`을 보고에 적는다.

## Task 1: `kernel/make_initrd.sh`

편집은 Edit 도구로 한다(`sd -F`는 치환 문자열의 `\n`을 글자로 넣는다 — lessons 실측 59). 둘 다 바꾸기
전 글자가 파일에 한 번만 있다.

### 1-1. CU-M1 블록 주석의 `/.vimrc` 언급

`rg -n '사용자 vimrc\(/\.vimrc\)' kernel/make_initrd.sh`(235줄)의 한 줄 위부터 네 줄을 바꾼다.

바꾸기 전:

```bash
# 세션에도, 설정 디스크 없이 뜨는 render 체인에도 /config가 없다. vim은
# 사용자 vimrc(/.vimrc)를 이 파일 뒤에 읽으므로 사람이 `set t_SI= t_SR= t_EI=`로
# 끌 수 있다. 다른 후보(seed vimrc · VIMINIT · EXINIT)가 왜 안 되는지는 CU
# design 결정 7의 후보 표에 있다.
```

바꾼 뒤:

```bash
# 세션에도, 설정 디스크 없이 뜨는 render 체인에도 /config가 없다. vim은
# 사용자 vimrc(/.vimrc — 설정 디스크의 /config/vimrc로 가는 링크, 아래 PE-M2
# 블록)를 이 파일 뒤에 읽으므로 사람이 `set t_SI= t_SR= t_EI=`로 끌 수 있다.
# 다른 후보(seed vimrc · VIMINIT · EXINIT)가 왜 안 되는지는 CU design 결정 7의
# 후보 표에 있다. PE-M2가 까는 seed vimrc는 주석뿐이라 그 판단과 안 부딪친다.
```

첫 줄은 그대로이고, 뒤 세 줄이 네 줄이 된다. 마지막 문장(PE-M2의 seed가 CU 결정 7과 안 부딪친다)은
design 결정 7의 셋째 단락을 그 자리에 한 줄로 옮긴 것이다.

### 1-2. `/.vimrc` 링크

rc 링크 셋의 마지막 줄 `ln -sf config/zshrc "$WORKDIR/.zshrc"`(367줄) 뒤, git 템플릿 블록의 빈 줄 앞에
빈 줄 하나 · 주석 열한 줄 · 링크 한 줄을 넣는다.

바꾸기 전:

```bash
ln -sf config/bashrc "$WORKDIR/.bashrc"
ln -sf config/zshrc "$WORKDIR/.zshrc"
```

바꾼 뒤:

```bash
ln -sf config/bashrc "$WORKDIR/.bashrc"
ln -sf config/zshrc "$WORKDIR/.zshrc"

# PE-M2. vim의 사용자 vimrc도 위 .gitconfig · rc 셋과 같은 문제에 같은 답이다 —
# vim은 $HOME/.vimrc를 읽고(vim --version의 `user vimrc file`) 게스트의 HOME은
# / 이며 /는 tmpfs다. 위 CU-M1 블록의 시스템 vimrc(/etc/vim/vimrc)는 initrd에서
# 와서 부팅마다 같고, 사람이 고쳐서 재부팅 뒤에도 남기는 자리는 이 링크가
# 가리키는 /config/vimrc다.
#
# 파일은 여기서 안 만든다. 주석뿐인 seed를 init이 /config를 마운트한 뒤에
# 깐다(init/src/config.zig의 VIMRC_SEED). 설정 디스크를 못 찾으면 링크가
# initrd 안의 빈 /config를 가리켜 댕글링이고, vim은 그것을 "사용자 vimrc
# 없음"으로 보고 지금처럼 stub defaults.vim을 읽는다(PE design 실측 6) —
# render 체인이 그 부팅이다. 부팅을 안 막는 것도 rc와 같다.
ln -sf config/vimrc "$WORKDIR/.vimrc"
```

### 1-3. 확인

```bash
git diff --stat kernel/make_initrd.sh
git diff kernel/make_initrd.sh | rg '^-'
bash -n kernel/make_initrd.sh && echo SYNTAX-OK
```

기대: `1 file changed, 17 insertions(+), 3 deletions(-)`. 둘째 명령은 이 넉 줄뿐이어야 한다.

```
--- a/kernel/make_initrd.sh
-# 사용자 vimrc(/.vimrc)를 이 파일 뒤에 읽으므로 사람이 `set t_SI= t_SR= t_EI=`로
-# 끌 수 있다. 다른 후보(seed vimrc · VIMINIT · EXINIT)가 왜 안 되는지는 CU
-# design 결정 7의 후보 표에 있다.
```

다른 줄이 `-`로 나오면 되돌리고 다시 한다. 셋째는 `SYNTAX-OK`.

## Task 2: `init/src/config.zig` — `VIMRC_PATH` · `VIMRC_SEED` · `seedVimrc`

`pub fn seedGitconfig() void {`(1276줄)의 함수 끝 `}` 뒤, 빈 줄 하나를 두고 넣는다. 그 뒤의 빈 줄과
`/// seed 파일 하나를 "없으면 만든다".`(`seedOneFile`의 doc 주석)는 그대로 남는다. Edit 도구로 한다.

바꾸기 전:

```zig
/// gitconfig 하나를 rc 셋과 같은 규칙으로 깐다(ST-M2).
pub fn seedGitconfig() void {
    seedOneFile(GITCONFIG_PATH, GITCONFIG_SEED);
}
```

바꾼 뒤:

```zig
/// gitconfig 하나를 rc 셋과 같은 규칙으로 깐다(ST-M2).
pub fn seedGitconfig() void {
    seedOneFile(GITCONFIG_PATH, GITCONFIG_SEED);
}

/// vim의 사용자 vimrc 자리 — `kernel/make_initrd.sh`가 건 링크(`/.vimrc`)가
/// 가리키는 곳이다(PE-M2).
pub const VIMRC_PATH: [:0]const u8 = "/config/vimrc";

/// 첫 부팅에 깔아 두는 사용자 vimrc(PE design 결정 7).
///
/// 설정이 한 줄도 없다. 모든 줄이 `"` 주석이거나 빈 줄이다. 모던 설정은
/// 시스템 vimrc(`kernel/vim/vimrc` → `/etc/vim/vimrc`)의 몫이고 이 파일은
/// 사람의 것이다(GE design 결정 4). 우리가 쓰는 것은 처음 한 번의 안내뿐이고,
/// `O_EXCL` 때문에 그 뒤로는 손대지 않는다.
///
/// 그런데도 까는 이유는 둘이다. 사람이 이 파일을 열었을 때 실체가 어디이고
/// 무엇이 먼저 읽히는지를 알려 줄 자리가 여기뿐이다. 그리고 `/.gitconfig`가
/// 댕글링이던 모양(ST-M2가 고쳤다)을 새로 만들지 않는다.
///
/// 영어 · ASCII다. 같은 vim이 `kernel/vim/vimrc`와 나란히 읽는 파일이라 그쪽과
/// 맞춘다(GE design 결정 6 원칙 5). 한국어인 gitconfig seed와 다른 이유다.
///
/// `tabstop`이라는 낱말을 안 쓴다. `config/check.sh` 1차가 사람이 더한
/// `set tabstop=3`을 `grep tabstop`으로 되읽고 2차가 vim에게 그 값을 묻는다 —
/// seed에 그 낱말이 있으면 되읽기의 출력이 두 줄이 되고, 설정으로 있으면
/// 2차가 사람의 줄 없이도 초록이 된다. `config_test`가 둘 다 막는다.
///
/// 예시는 앞의 `"` 하나를 지우면 그대로 쓸 수 있는 모양이다(PE-M2 plan 확정 5 —
/// 셋 다 지우고 읽혀도 에러가 없었다). seed가 생기면 vim은
/// `$VIMRUNTIME/defaults.vim`을 안 읽는다(PE design 실측 6). 게스트의 그 파일은
/// 주석뿐인 stub이라 차이가 없다.
pub const VIMRC_SEED =
    \\" TARS user vimrc. This file lives on the config disk as /config/vimrc, and
    \\" /.vimrc is a link to it (the home directory is /). The home directory is
    \\" tmpfs and is rebuilt from the initrd on every boot; the config disk keeps
    \\" this file, so what you write here is still here after a reboot.
    \\"
    \\" vim reads the system vimrc /etc/vim/vimrc first and this file after it,
    \\" so a line here can undo any line there. To see what that file sets:
    \\"   vim -R /etc/vim/vimrc
    \\"
    \\" init writes this file only when it is missing and never touches it after
    \\" that. Every line is a comment, so it changes nothing yet. To use one of
    \\" the examples below, delete its leading double quote.
    \\
    \\" Line numbers off:
    \\"set nonumber norelativenumber
    \\
    \\" Cursor shape off (a block in every mode):
    \\"set t_SI= t_SR= t_EI=
    \\
    \\" Tabs and trailing spaces not marked:
    \\"set nolist
    \\
;

/// 사용자 vimrc 하나를 rc 셋 · gitconfig와 같은 규칙으로 깐다(PE-M2).
pub fn seedVimrc() void {
    seedOneFile(VIMRC_PATH, VIMRC_SEED);
}
```

seed는 글자 그대로 넣는다. 지켜야 할 것 넷이다(design 결정 7의 원칙 넷과 확정 5).

- 모든 줄이 `"`로 시작하거나 빈 줄이다. 예시 줄은 `"` 바로 뒤에 `set`이 붙는다(공백 없음) — `"` 하나를
  지우면 그대로 쓰는 모양이다.
- 전부 ASCII다. 이 블록의 doc 주석은 한국어지만 리터럴 안(`\\` 뒤)은 영어다.
- `tabstop`이라는 낱말이 리터럴 안에 없다(doc 주석에는 있다 — 리터럴만 게스트로 간다).
- Zig의 multiline 리터럴은 줄을 `\n`으로 잇고 마지막 줄 뒤에는 개행을 안 붙인다. 그래서 끝의 빈 `\\`
  줄이 파일 끝의 개행이다. 탭은 쓸 수 없다(`string literal contains invalid byte`) — 이 seed에는 탭이
  없다.

확인:

```bash
git diff --stat init/src/config.zig
git diff init/src/config.zig | rg '^-'
```

기대: `1 file changed, 57 insertions(+)`, 둘째 명령은 `--- a/init/src/config.zig` 한 줄만.

## Task 3: `init/src/main.zig` — 호출 한 줄

`storage_mounted` 블록 안의 `config.seedGitconfig();`(800줄) 바로 뒤, `// SM-M2 결정 9.` 주석 앞에 주석
세 줄과 호출 한 줄을 넣는다. 들여쓰기는 공백 여덟이다. Edit 도구로 한다.

바꾸기 전:

```zig
        config.seedGitconfig();
```

바꾼 뒤:

```zig
        config.seedGitconfig();
        // PE-M2. `/.vimrc`가 가리키는 자리를 채운다 — 위 gitconfig와 같은 모양이고
        // 조건도 같다. seed는 주석뿐이라 vim이 읽어도 아무것도 안 바뀐다(PE
        // design 결정 7). 있으면 안 건드리므로 사람이 고친 vimrc가 재부팅을 넘는다.
        config.seedVimrc();
```

순서가 `seedRcFiles` → `seedGitconfig` → `seedVimrc`이므로 1차 로그의 `seeded` 줄도 `bashrc` · `zshrc` ·
`fish.config` · `gitconfig` · `vimrc` 순서다.

확인:

```bash
git diff --stat init/src/main.zig
git diff init/src/main.zig | rg '^-'
```

기대: `1 file changed, 4 insertions(+)`, 둘째 명령은 `--- a/init/src/main.zig` 한 줄만.

## Task 4: `init/src/config_test.zig` — `expectVimrcSeed`

### 4-1. 함수

`expectGitconfigSeed`의 함수 끝 `}`와 빈 줄 뒤, `/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정
3).`(535줄) 앞에 넣는다. 바꾸기 전 글자는 그 한 줄이고, 바꾼 뒤는 새 함수 · 빈 줄 · 그 한 줄이다.

바꾸기 전:

```zig
/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정 3).
```

바꾼 뒤:

```zig
/// vimrc seed가 vim에게 아무것도 시키지 않는가(PE-M2 · design 결정 7).
///
/// gitconfig seed와 재는 것이 반대다. 저쪽은 git이 읽을 변수가 있어야 하고,
/// 이쪽은 vim이 실행할 줄이 하나도 없어야 한다 — 설정은 시스템 vimrc의 몫이고
/// 이 파일은 사람의 것이다(GE design 결정 4).
///
/// 검사가 다섯인 이유는 각각 다른 실수를 막기 때문이다.
///
///   개행     끝 줄에 개행이 없으면 사람이 `echo … >> /.vimrc`로 더한 줄이
///            seed의 마지막 주석 줄에 붙어 주석이 된다
///   ASCII    `kernel/vim/vimrc`와 같은 원칙(GE design 결정 6 원칙 5)
///   주석     `"`로 시작하지 않는 줄은 vim이 실행한다. 그 줄이 설정이면
///            config 체인 2차의 `tabstop=3`이 사람의 줄 없이도 초록이 될 수
///            있고, 틀린 줄이면 vim이 뜰 때마다 에러를 찍는다
///   볼 것    `/etc/vim/vimrc`가 없으면 줄이 하나도 없는 seed가 위 셋을
///            아무것도 안 보고 지나간다 — gitconfig의 `defaultBranch` 자리다
///   낱말     `tabstop` — config 체인 1차의 `grep tabstop` 되읽기가 한 줄이어야
///            한다(design 결정 7 원칙 4)
fn expectVimrcSeed() !void {
    const text = config.VIMRC_SEED;
    if (text.len == 0 or text[text.len - 1] != '\n') {
        std.debug.print("FAIL: the vimrc seed does not end with a newline\n", .{});
        return error.BadSeed;
    }
    for (text, 0..) |b, i| {
        if (b >= 0x80) {
            std.debug.print("FAIL: the vimrc seed has a non-ASCII byte {d} at offset {d}\n", .{ b, i });
            return error.BadSeed;
        }
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] != '"') {
            std.debug.print(
                "FAIL: the vimrc seed has a line vim will run:\n  {s}\n" ++
                    "      seed는 주석뿐이어야 한다(PE design 결정 7). 설정이면 config 체인\n" ++
                    "      2차의 tabstop 검사가 사람의 줄 없이도 초록이 될 수 있다.\n",
                .{line},
            );
            return error.BadSeed;
        }
    }
    if (std.mem.indexOf(u8, text, "/etc/vim/vimrc") == null) {
        std.debug.print("FAIL: the vimrc seed never names /etc/vim/vimrc\n", .{});
        return error.BadSeed;
    }
    if (std.mem.indexOf(u8, text, "tabstop") != null) {
        std.debug.print(
            "FAIL: the vimrc seed mentions tabstop\n" ++
                "      config 체인 1차가 사람이 더한 줄을 grep tabstop으로 되읽는다 — 출력이 한 줄이어야 한다.\n",
            .{},
        );
        return error.BadSeed;
    }
}

/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정 3).
```

design 검증의 PE-M2 절은 검사 넷(개행 · 주석 · ASCII · `/etc/vim/vimrc`)을 적었다. 이 함수는 원칙 4를
지키는 다섯째(`tabstop`)를 더한다 — 원칙 4를 지키는 자리가 사람의 눈뿐이면 seed를 고치는 사람이 그
낱말을 주석에 쓸 수 있다.

### 4-2. 호출

`main()`의 `try expectGitconfigSeed();`(1084줄) 바로 뒤에 넣는다.

바꾸기 전:

```zig
    try expectGitconfigSeed();
```

바꾼 뒤:

```zig
    try expectGitconfigSeed();

    // ── PE-M2: vimrc seed ───────────────────────────────────────────────
    //
    // gitconfig처럼 셸이 안 읽는 파일이다 — vim이 읽는다. 그래서 조용함 검사가
    // 아니라 "vim에게 아무것도 안 시킨다"는 검사를 받는다. 한 번이다.
    try expectVimrcSeed();
```

### 4-3. 확인과 실행

```bash
git diff --stat init/src/config_test.zig
git diff init/src/config_test.zig | rg '^-'
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build > /tmp/b.out 2>&1; echo "build exit=$?"; grep -a -E "error" /tmp/b.out | head -5
           zig build test > /tmp/t.out 2>&1; echo "test exit=$?"; grep -ac "^PASS" /tmp/t.out; grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대.

- `--stat`은 `1 file changed, 64 insertions(+)`(함수 57 · 빈 줄 1 · 호출 블록 6). 둘째 명령은
  `--- a/init/src/config_test.zig` 한 줄만.
- `build exit=0`과 에러 0줄 — `init`(게스트 바이너리, `config.zig` · `main.zig` 포함)이 컴파일된다.
- `test exit=0`, `^PASS` 수가 Task 0-4의 기준값과 같다, `FAIL` · `error:` 0줄.

`zig build test`가 `file contents changed during update`로 멈추면 편집 직후의 파일을 빌드가 읽은 것이다
(lessons 실측 60) — 다시 돌린다. 컴파일 에러가 나면 그 메시지를 그대로 보고한다(확정 11 — 이 plan의 Zig
조각은 `ast-check`까지만 거쳤다). 기대값을 고쳐서 맞추지 않는다.

## Task 5: `kernel/vim/vimrc` — 머리 주석

5줄과 6줄을 네 줄로 바꾼다(확정 8). 8줄(`" To turn off only the cursor shapes, put this in /.vimrc:`)은
그대로 둔다. 이 파일은 ASCII · 영어이고 줄 이음(`\`)을 안 쓴다. Edit 도구로 한다.

바꾸기 전:

```vim
" vim reads this file first and the user vimrc (/.vimrc) after it, so any line
" here can be undone there. To start vim without this file:
```

바꾼 뒤:

```vim
" vim reads this file first and the user vimrc after it, so any line here can
" be undone there. The user vimrc is /.vimrc, a link to /config/vimrc on the
" config disk; with a config disk attached, edits there survive a reboot. To
" start vim without this file:
```

확인:

```bash
git diff --stat kernel/vim/vimrc
git diff kernel/vim/vimrc | rg '^-'
LC_ALL=C rg -n '[^\x00-\x7F]' kernel/vim/vimrc || echo ASCII-ONLY
```

기대: `1 file changed, 4 insertions(+), 2 deletions(-)`. 둘째 명령은 이 세 줄뿐이다.

```
--- a/kernel/vim/vimrc
-" vim reads this file first and the user vimrc (/.vimrc) after it, so any line
-" here can be undone there. To start vim without this file:
```

셋째는 `ASCII-ONLY`.

## Task 6: `config/check.sh` · `tools/check.sh`, 체인 두 번

### 6-1. `config/check.sh` — 넷

전부 Edit 도구로 한다. 넷 다 바꾸기 전 글자가 파일에 한 번만 있다(확정 11이 확인했다).

(a) 키 배열 넷. 키 배열 절의 마지막인 `BPROD_WIDGET_KEYS`(366~369줄)와 `# 1차 부팅에서 QEMU를 죽이기
전에 하는 일` 주석(371줄) 사이에 넣는다. 바꾸기 전 글자는 `BPROD_WIDGET_KEYS`의 마지막 줄 · 빈 줄 · 그
주석의 첫 줄이다.

바꾸기 전:

```bash
                   shift-minus shift-minus shift-0 ret)

# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
```

바꾼 뒤:

```bash
                   shift-minus shift-minus shift-0 ret)

# ── PE-M2 ───────────────────────────────────────────────────────────────
#
# 1차 훅이 치는 셋과 2차 훅이 치는 하나. 사람이 고친 vim 설정이 재부팅을
# 넘는지를 본다(PE design 결정 8).
#
# vim -T dumb -e +scriptnames +qa — vim이 읽은 스크립트를 읽은 순서대로 찍고
# 나간다. +는 shift-equal이고(net/check.sh가 date +%Y에 쓴다) -T의 T는
# shift-t다.
#
# -T dumb이 빠지면 안 된다. 터미널이 주는 TERM=xterm-256color에서는 vim이 Ex
# 모드(-e)에서도 terminfo의 smcup을 보내 대체 화면(ESC[?1049h)에 들어가 거기에
# 찍고, 나가면서 원래 화면으로 돌아간다 — 출력이 screen> 프레임에 남을지가
# 렌더 시점에 달린다(PE-M2 plan 확정 1). 게스트에는 dumb의 terminfo가 없고
# vim은 내장 항목으로 조용히 넘어간다. vimrc를 읽는 것과 그 순서는 터미널
# 이름과 무관하다.
VIM_SCRIPTNAMES_KEYS=(v i m spc minus shift-t spc d u m b spc minus e spc
                      shift-equal s c r i p t n a m e s spc shift-equal q a ret)
# echo set tabstop=3 >> /.vimrc — 사람이 하는 일이다. 링크로 쓰므로 설정
# 디스크의 /config/vimrc에 들어간다. >>는 APPEND_KEYS와 같이 shift-dot 둘이다.
VIM_APPEND_KEYS=(e c h o spc s e t spc t a b s t o p equal 3 spc
                 shift-dot shift-dot spc slash dot v i m r c ret)
# grep tabstop /config/vimrc — 되읽기. 링크가 아니라 실체를 읽는다. seed에는
# tabstop이라는 낱말이 없으므로(config_test가 지킨다) 출력이 한 줄이다.
VIM_READBACK_KEYS=(g r e p spc t a b s t o p spc
                   slash c o n f i g slash v i m r c ret)
# vim -T dumb -e +'set ts?' +qa — 2차(zsh)에서 친다. 작은따옴표는 apostrophe,
# ?는 shift-slash다(render/check.sh의 type_text와 같은 이름). 따옴표가 필요한
# 이유는 zsh다 — 따옴표 없는 ?를 glob으로 펴고, 맞는 파일이 없으면 명령을
# 안 돌리고 `zsh: no matches found: +set ts?`를 찍는다(PE-M2 plan 확정 4).
VIM_TS_KEYS=(v i m spc minus shift-t spc d u m b spc minus e spc
             shift-equal apostrophe s e t spc t s shift-slash apostrophe spc
             shift-equal q a ret)

# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
```

(b) 1차 훅의 검사 셋. `edit_config_in_guest` 안의 gitconfig 검사 끝(453줄) 바로 뒤에 넣는다. 그 뒤의 빈
줄 둘과 `type_keys "${EDIT_KEYS[@]}"`는 그대로 남는다.

바꾸기 전:

```bash
  echo "boot 1: git read init.defaultBranch=main out of the seeded /config/gitconfig"
```

바꾼 뒤:

```bash
  echo "boot 1: git read init.defaultBranch=main out of the seeded /config/gitconfig"

  # ── PE-M2: vim이 링크를 따라 seed를 사용자 vimrc로 읽는가 ─────────────
  #
  # 아래 로그 검사가 "깔렸다"를 보고, 여기서 "vim이 그것을 읽는다"를 본다.
  # scriptnames의 1이 시스템 vimrc(/etc/vim/vimrc), 2가 사용자 vimrc다. 링크가
  # 없거나 댕글링이면 vim은 사용자 vimrc가 없다고 보고 2 자리에 stub
  # defaults.vim을 찍는다(PE design 실측 6).
  #
  # 판정 글자는 `2: /.vimrc`다. 게스트의 HOME이 /라서 vim이 그 경로를 ~로
  # 줄이지 않는다(PE-M2 plan 확정 2). 행 첫머리가 그 글자인 줄은 scriptnames의
  # 출력뿐이고, 친 줄은 프롬프트로 시작한다.
  type_keys "${VIM_SCRIPTNAMES_KEYS[@]}"
  if ! wait_for_screen '\| +2: /\.vimrc'; then
    echo "FAIL(boot 1): vim did not list /.vimrc as its user vimrc"
    echo "  셋 중 하나다 — initrd에 /.vimrc 링크가 없거나, init이 /config/vimrc를"
    echo "  안 깔았거나(둘 다 2 자리에 defaults.vim이 찍힌다), vim이 대체 화면에"
    echo "  찍고 나갔다(-T dumb이 빠지면 화면에 아무것도 안 남을 수 있다)."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  # 위 양성만으로는 vimrc의 에러를 못 본다. vimrc에 틀린 줄이 있어도
  # scriptnames는 2 자리에 /.vimrc를 그대로 찍고, 그 위에 에러 줄이 붙는다
  # (PE-M2 plan 확정 3). 이 체인에서 vim을 띄우는 것은 여기가 처음이다.
  local vim_screen
  vim_screen="$(grep -a "terminal: screen>" "$log")"
  if grep -aF "Error detected while processing" <<<"$vim_screen" >/dev/null; then
    echo "FAIL(boot 1): vim reported an error while reading its vimrc files"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: vim read /etc/vim/vimrc, then the seeded /config/vimrc through /.vimrc, with no error"

  # 사람이 하는 일을 한다. 링크로 쓴 줄이 설정 디스크에 들어가야 2차가 읽는다.
  # 판정 글자 `| set tabstop=3`은 행 머리가 set인 줄이고, 친 줄은 프롬프트와
  # echo로 시작한다.
  type_keys "${VIM_APPEND_KEYS[@]}"
  type_keys "${VIM_READBACK_KEYS[@]}"
  if ! wait_for_screen '\| set tabstop=3'; then
    echo "FAIL(boot 1): the line appended to /.vimrc did not read back from /config/vimrc"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: a line appended to /.vimrc landed in /config/vimrc"
```

`local vim_screen`과 here-string(`<<<`)은 파이프가 아니라서 `require_no_early_exit_pipe`와 무관하다. 그
lint가 막는 것은 파이프 뒤의 `grep -q`다 — 여기서는 `-q` 대신 `>/dev/null`이다.

(c) 2차 훅의 검사 하나. `watch_console_shell` 안의 `type_keys "${OFF_KEYS[@]}"`(560줄) 바로 앞에 넣는다.

바꾸기 전:

```bash
  type_keys "${OFF_KEYS[@]}"
```

바꾼 뒤:

```bash
  # ── PE-M2: 1차가 /.vimrc에 더한 줄이 재부팅을 넘었는가 ────────────────
  #
  # 이 부팅의 셸은 zsh다. VIM_TS_KEYS가 set ts?를 작은따옴표로 감싸는 이유다.
  #
  # 판정 글자 `tabstop=3`은 vim의 출력에만 생긴다. 친 줄에는 `ts?`만 있다.
  # 시스템 vimrc가 tabstop=8을 명시하므로, 3이 나오면 vim이 사용자 vimrc를 그
  # 뒤에 읽었다는 순서까지 함께 보인다(PE design 결정 8). seed에는 tabstop이
  # 없으므로(config_test가 지킨다) 이 3은 사람이 1차에 더한 줄에서만 온다.
  #
  # 아래 OFF_KEYS보다 앞이다. 실패하면 3차가 읽을 설정을 심지 않고 나간다.
  type_keys "${VIM_TS_KEYS[@]}"
  if ! wait_for_screen '\| +tabstop=3'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 2): vim did not see tabstop=3 from /.vimrc after the reboot"
    echo "  화면에 tabstop=8이 있으면 사람의 줄이 사라졌다(seed가 그 파일을 다시"
    echo "  썼거나 다른 디스크다). no matches found가 있으면 ?가 따옴표 밖으로 나갔다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 2: vim read tabstop=3 from /.vimrc, the line the first boot appended"

  type_keys "${OFF_KEYS[@]}"
```

(d) 1차의 로그 검사. gitconfig의 로그 검사 끝(1358줄) 바로 뒤에 넣는다.

바꾸기 전:

```bash
echo "boot 1: init seeded the gitconfig too (the .gitconfig link has a target now)"
```

바꾼 뒤:

```bash
echo "boot 1: init seeded the gitconfig too (the .gitconfig link has a target now)"

# PE-M2. vimrc도 rc가 아니다 — vim이 읽는 파일이고, 이 줄이 보는 것은
# "깔렸는가"까지다. vim이 그것을 읽는 것은 위 훅의 scriptnames가 본다.
# 2 · 8 · 9차의 `seeded /config/` 음성 검사는 접두로 보므로 vimrc를 다시 깔면
# 그쪽이 빨개진다. 7차는 이름을 하나씩 보므로 영향이 없다.
if ! grep -q "tars-init: seeded /config/vimrc" "$LOG1"; then
  report_failure "$LOG1" "first boot did not seed /config/vimrc"
fi
echo "boot 1: init seeded the vimrc too (the /.vimrc link has a target now)"
```

### 6-2. `tools/check.sh` — `WANT`

검사 1의 CU-M1 `WANT` 줄(207줄) 바로 뒤, `INITRD_LIST=` 앞의 빈 줄은 그대로 남게 넣는다.

바꾸기 전:

```bash
WANT+=(etc/vim/vimrc usr/share/vim/vim91/defaults.vim)
```

바꾼 뒤:

```bash
WANT+=(etc/vim/vimrc usr/share/vim/vim91/defaults.vim)

# PE-M2: vim의 사용자 vimrc 링크. 위 .bashrc · .zshrc와 같은 자리이고 같은
# 이유다 — make_initrd.sh가 손으로 거는 링크라 여기 적어야 검사 1이 tautology가
# 아니다. 가리키는 /config/vimrc는 이 체인에 디스크가 없어서 안 보고, config
# 체인이 본다.
WANT+=(.vimrc)
```

### 6-3. 확인과 진입 검사

```bash
git diff --stat config/check.sh tools/check.sh
git diff config/check.sh tools/check.sh | rg '^-'
bash -n config/check.sh && bash -n tools/check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  for f in ./config/check.sh ./tools/check.sh; do
    require_build_steps $f && require_no_early_exit_pipe $f && require_explicit_nic $f && echo "ENTRY-OK $f"
  done'
```

기대: `config/check.sh | 107 +` · `tools/check.sh | 6 +` · `2 files changed, 113 insertions(+)`, 둘째 명령은
`--- a/config/check.sh` · `--- a/tools/check.sh` 두 줄만, `SYNTAX-OK`, `ENTRY-OK ./config/check.sh` ·
`ENTRY-OK ./tools/check.sh`.

### 6-4. `config` 체인 한 번(시리얼 로그와 디스크를 함께 꺼낸다)

약 2분 50초다(Task 0-4의 시간 + 20초 안팎). 새 화면 판정을 넣었으므로 로그 꺼내기가 기본 절차다
(lessons "범용 명령"). 체인이 끝난 뒤 남은 디스크 이미지에서 `vimrc`도 읽는다(확정 7).

```bash
mkdir -p /tmp/run/pem2i/after
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i -w /workspace \
    tars-devcontainer bash -c '
  bash config/check.sh > /tmp/run/pem2i/after/chain.log 2>&1; echo "exit=$?"
  n=0; for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /tmp/run/pem2i/after/serial_$n.log; fi
  done
  debugfs -R "cat vimrc" out/config.img > /tmp/run/pem2i/after/disk_vimrc.txt 2>/dev/null
  debugfs -R "ls -l /" out/config.img > /tmp/run/pem2i/after/disk_ls.txt 2>/dev/null' ; } 2> /tmp/run/pem2i/after/time
cat /tmp/run/pem2i/after/time
rg -n '^=== boot [12]/|^boot [12]: |^FAIL|^PASS' /tmp/run/pem2i/after/chain.log
```

기대. `exit=0`이고 `rg` 출력에 아래 줄들이 이 순서로 있다(1차 · 2차의 다른 `boot` 줄이 사이사이에 더
있다).

```
=== boot 1/9: empty disk, seed the config and the rc files, then edit them from inside ===
boot 1: git read init.defaultBranch=main out of the seeded /config/gitconfig
boot 1: vim read /etc/vim/vimrc, then the seeded /config/vimrc through /.vimrc, with no error
boot 1: a line appended to /.vimrc landed in /config/vimrc
boot 1: typed the edit in the guest and read it back (shell=zsh)
boot 1: one Ctrl+R opened the fzf picker (the terminal answered its query)
boot 1: init seeded the gitconfig too (the .gitconfig link has a target now)
boot 1: init seeded the vimrc too (the /.vimrc link has a target now)
=== boot 2/9: same image, the guest-written config should pick the shell and its rc ===
boot 2: vim read tabstop=3 from /.vimrc, the line the first boot appended
boot 2: appended shell_config=off to the config for the third boot
boot 2: init left the existing rc files alone
PASS
```

`exit=0`이 아니면 `FAIL` 줄과 그 아래 덤프를 그대로 보고하고 6-5의 명령으로 그 순간의 화면을 꺼낸다.
기대값을 고쳐서 초록을 만들지 않는다 — 특히 `2: /.vimrc`(확정 2)와 `-T dumb`(확정 1)은 컨테이너에서 잰
값이고 게스트에서는 처음이다. 하나 짚어 둔다. vim이 맨 아래 행(`ESC[<행>;1H`)으로 커서를 옮기고 찍으므로
그 뒤 1차의 명령들은 화면 맨 아래에서 스크롤하며 찍힌다. 뒤 검사들은 행 첫머리로 판정하므로 위치와
무관할 것으로 보지만, `Ctrl+R` 검사(fzf가 40% 높이 상자를 그린다)가 빨개지면 이 위치가 첫 의심이다.
`time`의 `real`은 Task 0-4와 함께 보고한다.

### 6-5. 시리얼 로그와 디스크에서 꺼낼 것

```bash
cd /tmp/run/pem2i/after && for f in serial_*.log; do
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
            s/\e[()][AB0]//g; s/\r/\n/g' "$f" > "${f%.log}.clean"
done
# (a) seed 줄 — 어느 로그에 몇 번
rg -a -c --include-zero 'tars-init: seeded /config/vimrc' /tmp/run/pem2i/after/serial_*.clean
rg -a -c --include-zero 'tars-init: seeded /config/' /tmp/run/pem2i/after/serial_*.clean
# (b) 1차의 scriptnames 두 행과 되읽기, 2차의 tabstop — 그 글자가 든 프레임 수
rg -a -o '\| +[12]: [^|]*' /tmp/run/pem2i/after/serial_*.clean | sort | uniq -c
rg -a -o '\| set tabstop=3|\| +tabstop=[0-9]+' /tmp/run/pem2i/after/serial_*.clean | sort | uniq -c
rg -a -c --include-zero 'Error detected while processing' /tmp/run/pem2i/after/serial_*.clean
rg -a -c --include-zero '\[\?1049h' /tmp/run/pem2i/after/serial_*.log
# (c) 아홉 부팅 뒤의 디스크
cat /tmp/run/pem2i/after/disk_vimrc.txt | tail -3; wc -c < /tmp/run/pem2i/after/disk_vimrc.txt
rg 'vimrc|gitconfig' /tmp/run/pem2i/after/disk_ls.txt
```

기대.

- (a) `seeded /config/vimrc`는 로그 하나(1차)만 `1`이고 나머지 여덟은 `0`이다. `seeded /config/`는 그
  로그가 `5`(Task 0-4의 넷 + vimrc), 7차 로그가 `1`, 나머지 일곱이 `0`이다.
- (b) 1차 로그에 `|   1: /etc/vim/vimrc`와 `|   2: /.vimrc`가 같은 수(프레임 수)로 있고(`|` 뒤 공백 수는
  `screen>`의 행 이음에 따라 다를 수 있다),
  `|   2: /usr/share/vim/vim91/defaults.vim`은 어느 로그에도 없다. `| set tabstop=3`은 1차 로그에,
  `|   tabstop=3`(또는 공백 수가 다른 같은 모양)은 2차 로그에만 있다. `tabstop=8`은 없다.
- `Error detected while processing`은 아홉 다 `0`이다. 원본 로그(`.log`)의 `ESC[?1049h`도 아홉 다 `0`일
  것이다 — vim이 `-T dumb`으로 대체 화면에 안 들어갔고(확정 1), 1차의 fzf(`Ctrl+R`)는 `--height` 모드라
  대체 화면을 안 쓴다. `0`이 아닌 파일이 있으면 그 파일과 수를 그대로 보고한다(판정과 무관하다).
- (c) 디스크의 `vimrc`는 857바이트이고 마지막 세 줄이 `" Tabs and trailing spaces not marked:` ·
  `"set nolist` · `set tabstop=3`이다. 아홉 부팅 동안 seed가 다시 안 깔렸다는 것이 바이트 수로 보인다.
  `ls -l`에 `gitconfig`와 `vimrc`가 있다.

기대와 다른 모양(프레임의 공백 수, 행이 끊긴 프레임 등)은 판정과 무관해도 그대로 옮겨 보고한다. lead가
실측 절에 적는다. `screen>` 줄이 시리얼에서 중간에 끊겨 있으면(GE-M1 실측 4에서 한 번 있었다) 그다음의
완전한 줄을 고른다.

### 6-6. `tools` 체인 한 번

`WANT`에 `.vimrc`를 더했으므로 한 번 돌린다. 약 2분이다(빌드는 6-4가 데워 둔 캐시를 쓴다).

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash tools/check.sh > /tmp/run/pem2i/tools.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/run/pem2i/tools.time
cat /tmp/run/pem2i/tools.time
rg -n 'four bones|^FAIL|PASS' /tmp/run/pem2i/tools.log | head -5
```

기대: `exit=0`, `the initrd carries the four bones and all … tools the list names` 줄과 마지막 줄 `PASS`,
`FAIL` 0줄.

## Task 7: mutation 다섯

저장소 파일은 안 고치고 사본을 `-v`로 덮는다. 사본은 `/tmp/run/pem2i/mut/`에 만든다. 돌리기 전에
`diff`로 편집이 정확히 한 줄 들어갔는지 본다 — `sd -F`가 빗나가도 에러가 없다(lessons 실측 52). 한 줄이
아니면 돌리지 말고 보고한다.

Zig 파일을 덮는 run은 같은 `docker run` 안에서 먼저 `init/.zig-cache`와 `init/zig-out`을 지운다 — 캐시가
소스보다 낡은 채로 판정에 쓰이는 일이 이 저장소에서 일곱 번 있었고(`project_zig_out_staleness`), 지우는
것도 컨테이너 안에서 해야 한다. 덮인 사본이 실제로 쓰였는지는 같은 `docker run` 안에서 `grep -c`로
mutation 글자를 세어 본다(`mounted:`).

PE-M1 plan 6-2에서 `bash -c '…mut$m.log…'`의 `$m`이 작은따옴표 안이라 컨테이너에서 빈 값이 된 버그가
있었다. 그래서 아래는 loop 변수를 안 쓰고 mutation마다 명령을 따로 적는다. 체인 한 판은 캐시를 지운
뒤라 약 3분 30초이고 넷이면 15분 안팎이다. Bash 도구의 10분 상한을 넘지 않게 한 번에 하나씩 친다.

| mutation | 사본 | 무엇을 | 어디서 빨개지나 |
|---|---|---|---|
| 1 | `make_initrd.sh` | 링크 줄을 지운다 | `config` 1차 훅의 `scriptnames`(2 자리가 `defaults.vim`). `tools` 체인은 부팅 전 검사 1 |
| 2 | `main.zig` | `config.seedVimrc();`를 지운다 | `config` 1차 훅의 `scriptnames`(링크가 댕글링이라 1과 같은 화면) |
| 3 | `config.zig` | seed의 마지막 예시 줄을 `set tabstop=3`으로 | `config_test`(부팅 전) |
| 4 | `config.zig` | `seedOneFile`의 `.EXCL = true,`를 `.TRUNC = true,`로 | `config` 2차 훅의 `tabstop=3`(확정 6) |
| 5 | `config.zig` + `config/check.sh` | seed의 마지막 예시 줄을 `set nolistx`로, 체인의 `config_test` 단계를 끈다 | `config` 1차 훅의 음성 검사(확정 3) |

### 7-0. 사본을 만든다

```bash
mkdir -p /tmp/run/pem2i/mut
cp kernel/make_initrd.sh /tmp/run/pem2i/mut/make_initrd_m1.sh
cp init/src/main.zig /tmp/run/pem2i/mut/main_m2.zig
cp init/src/config.zig /tmp/run/pem2i/mut/config_m3.zig
cp init/src/config.zig /tmp/run/pem2i/mut/config_m4.zig
cp init/src/config.zig /tmp/run/pem2i/mut/config_m5.zig
cp config/check.sh /tmp/run/pem2i/mut/config_check_notest.sh
# mutation 1 — initrd에 /.vimrc 링크가 없다
sd -F 'ln -sf config/vimrc "$WORKDIR/.vimrc"' '' /tmp/run/pem2i/mut/make_initrd_m1.sh
# mutation 2 — init이 vimrc seed를 안 깐다
sd -F '        config.seedVimrc();' '' /tmp/run/pem2i/mut/main_m2.zig
# mutation 3 — seed에 설정이 한 줄 있다
sd -F '    \\"set nolist' '    \\set tabstop=3' /tmp/run/pem2i/mut/config_m3.zig
# mutation 4 — seed가 매 부팅 파일을 비우고 다시 쓴다
sd -F '.EXCL = true,' '.TRUNC = true,' /tmp/run/pem2i/mut/config_m4.zig
# mutation 5 — seed에 vim이 거부하는 줄이 있다(config_test를 끈 체인에서)
sd -F '    \\"set nolist' '    \\set nolistx' /tmp/run/pem2i/mut/config_m5.zig
sd -F 'if ! (cd ../init && zig build test); then' 'if false; then' /tmp/run/pem2i/mut/config_check_notest.sh
chmod +x /tmp/run/pem2i/mut/make_initrd_m1.sh /tmp/run/pem2i/mut/config_check_notest.sh
bash -c 'cd /Users/dp/Repository/tars-linux
  for p in "kernel/make_initrd.sh make_initrd_m1.sh" "init/src/main.zig main_m2.zig" \
           "init/src/config.zig config_m3.zig" "init/src/config.zig config_m4.zig" \
           "init/src/config.zig config_m5.zig" "config/check.sh config_check_notest.sh"; do
    set -- $p; echo "== $2"; diff "$1" "/tmp/run/pem2i/mut/$2"
  done'
```

기대: 여섯 `diff`가 각각 한 줄의 차이(`<` 한 줄과 `>` 한 줄)다. mutation 1 · 2의 `>`는 빈 줄이다.
`sd -F`의 작은따옴표 안 `\\`는 백슬래시 두 글자 그대로이고 Zig 소스의 `\\`와 맞는다. 호스트 셸이 zsh라
`set -- $p`가 단어를 안 가르므로 마지막 loop는 `bash -c`로 감쌌다(lessons 실측 69).

### 7-1. mutation 3 — `config_test`

체인이 필요 없다. 체인도 부팅 전에 같은 `zig build test`에서 `FAIL: config_test failed`로 멈춘다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i/mut/config_m3.zig:/workspace/init/src/config.zig:ro \
  -w /workspace/init tars-devcontainer bash -c '
  echo "mounted: $(grep -c "set tabstop=3$" src/config.zig)"
  rm -rf .zig-cache zig-out
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -E -A1 "^FAIL" /tmp/t.out | head -4; grep -a -c "error: BadSeed" /tmp/t.out'
```

기대: `mounted: 1`(원본의 doc 주석에도 `set tabstop=3`이 있지만 줄 끝이 아니라서 안 센다), `exit=1`,
`FAIL: the vimrc seed has a line vim will run:` 다음 줄 `  set tabstop=3`, `error: BadSeed`가 1 이상.

design 검증은 "이 검사가 없으면 2차의 `tabstop=3`이 사람의 줄이 아니라 seed에서 와도 초록"이라고 적었다.
그 체인 run(`config_test`를 끄고 이 seed로 돌리면 체인 전체가 초록)은 이 plan이 돌리지 않는다. seed의
그 줄이 2차의 `tabstop=3`을 만드는 것은 확정 5의 vim 동작에서 바로 나온다.

### 7-2. mutation 1 — 링크가 없다

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i \
    -v /tmp/run/pem2i/mut/make_initrd_m1.sh:/workspace/kernel/make_initrd.sh:ro \
    -w /workspace tars-devcontainer bash -c '
  echo "mounted: $(grep -c "WORKDIR/.vimrc" kernel/make_initrd.sh)"
  bash config/check.sh > /tmp/run/pem2i/mut/m1_config.log 2>&1; echo "config exit=$?"
  bash tools/check.sh > /tmp/run/pem2i/mut/m1_tools.log 2>&1; echo "tools exit=$?"' ; } 2>&1 | tail -6
rg -n '^=== boot|^boot 1: git read|^FAIL' /tmp/run/pem2i/mut/m1_config.log | head -8
rg -o 'defaults\.vim|2: /\.vimrc' /tmp/run/pem2i/mut/m1_config.log | sort | uniq -c
rg -n '^FAIL' /tmp/run/pem2i/mut/m1_tools.log
```

기대.

- `mounted: 0`, `config exit=1`, `tools exit=1`.
- `config`: `=== boot 1/9` · `boot 1: git read init.defaultBranch=main …` 다음에 약 15초 뒤
  `FAIL(boot 1): vim did not list /.vimrc as its user vimrc`와 한국어 진단 셋, 그다음
  `FAIL: first boot did not seed and edit /config/tars.conf`. `=== boot 2/9`는 없다.
- `FAIL(boot 1)` 아래 찍힌 마지막 화면에 `defaults.vim`이 있고 `2: /.vimrc`는 없다(`rg -o`의 셈).
- `tools`: `FAIL: .vimrc is missing from the initrd`(검사 1, 부팅 전).

### 7-3. mutation 2 — seed를 안 깐다

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i \
    -v /tmp/run/pem2i/mut/main_m2.zig:/workspace/init/src/main.zig:ro \
    -w /workspace tars-devcontainer bash -c '
  echo "mounted: $(grep -c "config.seedVimrc()" init/src/main.zig)"
  rm -rf init/.zig-cache init/zig-out
  bash config/check.sh > /tmp/run/pem2i/mut/m2.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
rg -n '^=== boot|^boot 1: git read|^FAIL' /tmp/run/pem2i/mut/m2.log | head -8
rg -o 'defaults\.vim|2: /\.vimrc' /tmp/run/pem2i/mut/m2.log | sort | uniq -c
```

기대: `mounted: 0`, `exit=1`, 7-2의 `config`와 같은 두 `FAIL` 줄과 같은 화면. design은 "훅을 통과하더라도
1차의 로그 검사가 `first boot did not seed /config/vimrc`로 빨개진다"고 적었다 — 훅이 먼저 빨개지므로
그 로그 검사까지는 안 간다. 그 로그 검사가 도는지는 6-4의 초록 run이 본다.

### 7-4. mutation 4 — 매 부팅 다시 쓴다

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i \
    -v /tmp/run/pem2i/mut/config_m4.zig:/workspace/init/src/config.zig:ro \
    -w /workspace tars-devcontainer bash -c '
  echo "mounted: $(grep -c "EXCL = true" init/src/config.zig)"
  rm -rf init/.zig-cache init/zig-out
  bash config/check.sh > /tmp/run/pem2i/mut/m4.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
rg -n '^=== boot|^boot [12]: (vim|init seeded the vimrc)|^FAIL' /tmp/run/pem2i/mut/m4.log | head -10
rg -o 'tabstop=[0-9]' /tmp/run/pem2i/mut/m4.log | sort | uniq -c
```

기대: `mounted: 0`, `exit=1`. 1차는 전부 초록이다(빈 디스크라 `.TRUNC`가 할 일이 없다) — `boot 1: vim read …` ·
`boot 1: a line appended …` · `boot 1: init seeded the vimrc too …`. 그다음 `=== boot 2/9` 뒤 약 15초에
`FAIL(boot 2): vim did not see tabstop=3 from /.vimrc after the reboot`와 진단 둘, 그다음
`FAIL: second boot never started a console shell`. 마지막 화면에 `tabstop=8`이 있다.

### 7-5. mutation 5 — vim이 거부하는 seed

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pem2i:/tmp/run/pem2i \
    -v /tmp/run/pem2i/mut/config_m5.zig:/workspace/init/src/config.zig:ro \
    -v /tmp/run/pem2i/mut/config_check_notest.sh:/workspace/config/check.sh:ro \
    -w /workspace tars-devcontainer bash -c '
  echo "mounted: $(grep -c "set nolistx$" init/src/config.zig) $(grep -c "if false; then" config/check.sh)"
  rm -rf init/.zig-cache init/zig-out
  bash config/check.sh > /tmp/run/pem2i/mut/m5.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
rg -n '^=== boot|^boot 1: git read|^FAIL' /tmp/run/pem2i/mut/m5.log | head -8
rg -o 'Error detected while processing [^|]*|E[0-9]+: [^|]*|2: /\.vimrc' /tmp/run/pem2i/mut/m5.log | sort | uniq -c
```

기대: `mounted: 1 1`, `exit=1`. `boot 1: git read …` 다음에 기다림 없이 곧바로
`FAIL(boot 1): vim reported an error while reading its vimrc files`, 그다음
`FAIL: first boot did not seed and edit /config/tars.conf`. 마지막 화면에
`Error detected while processing /.vimrc:` · `E518: Unknown option: nolistx` · `2: /.vimrc`가 함께 있다 —
양성 기다림은 초록이었고 음성 검사가 잡았다는 것이 화면에서 보인다(확정 3).

### 7-6. 되돌린다

mutation 체인은 저장소의 `init/zig-out`과 `kernel/initrd.cpio`(둘 다 gitignore 대상)에 망가진 판을
남긴다. 캐시를 컨테이너 안에서 지우고 `init`을 다시 빌드해서, 다음에 체인을 돌리는 사람이 낡은 산출물을
쓰지 않게 한다. initrd는 어느 체인이든 첫 단계에서 다시 만든다. 덮었던 사본은 저장소 밖이라 저장소에 안
남는다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out
  cd init && zig build > /tmp/b.out 2>&1; echo "build exit=$?"
  zig build test > /tmp/t.out 2>&1; echo "test exit=$?"; grep -ac "^PASS" /tmp/t.out'
git status --short
```

기대: `build exit=0`, `test exit=0`, Task 0-4와 같은 `PASS` 수. `git status`는 `M` 일곱(`config/check.sh` ·
`init/src/config.zig` · `init/src/config_test.zig` · `init/src/main.zig` · `kernel/make_initrd.sh` ·
`kernel/vim/vimrc` · `tools/check.sh`)과 이 plan(`??`)뿐이다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어
Docker가 만든 0바이트 파일) 그 목록을 보고한다. `out/config.img`는 gitignore 대상이라 안 보인다.

### 7-7. 보고

구현자는 여기까지 하고 lead에게 보고한다. 보고에 담을 것.

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력(`docker ps` · `git status` · `git log` · `rg` · 기준 `PASS` 수 · 기준 체인의 `exit=` · `real` ·
  `seeded` 셈).
- Task 1~6의 확인 출력(`--stat` · `rg '^-'` · `SYNTAX-OK` · `ENTRY-OK` · `ASCII-ONLY` · `build exit=` · `test exit=`).
- 6-4의 `exit=` · `real` · `rg` 출력, 6-5의 (a)(b)(c) 출력, 6-6의 `exit=` · `real` · `rg` 출력.
- Task 7의 `diff` 여섯, 다섯의 `mounted:` · `exit=` · `real` · `FAIL` 줄 · 화면 셈, 7-6의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 8: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고(`git diff`), Task 6의 로그와 디스크 덤프를 `Read`로 대조한다.
2. 루트 게이트. 18체인 × 3, 약 1시간 5분이다(PE-M1 루트 게이트가 지금 값이다). `init`과 initrd의 링크가
   바뀌므로 열여덟 체인이 전부 새 initrd로 부팅한다(design 검증 "셋 다"). Bash 도구의 10분 상한을
   넘으므로 `run_in_background`로 돌리고 `{ time …; }`로 감싼다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pe2.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pe2.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 3/3' /tmp/gate_pe2.log`가 18이어야 하고, `config`의 회차마다 `boot 1: vim read /etc/vim/vimrc` ·
   `boot 2: vim read tabstop=3`이 한 번씩(합계 각 3) 있어야 한다. 설정 디스크를 붙이는 다른 체인(`tools` ·
   `hangul` · `net` 등)의 1차 부팅도 이제 `seeded /config/vimrc`를 한 줄 더 찍는다 — 그 줄을 세거나 화면
   좌표에 기대는 검사는 없다(확정 7). seed 줄은 시리얼 콘솔로만 가고 화면 셸에는 안 찍힌다.
3. 실측 절 채우기. 구현자의 보고와 루트 게이트의 시간 · 결과를 아래 "PE-M2가 실측한 것"에 적는다.
4. design 고치기. 이 plan이 design과 다르게 적은 것(아래 절)을 design의 해당 자리에 한 줄씩 덧붙인다 —
   특히 결정 8의 표(`-T dumb` · `/.vimrc`)와 그 결정의 "대체 화면에 들어가지 않고" 문장, 검증의 mutation 4,
   결정 7의 "세 자리". PE-M1 plan이 위험 4에 한 단락을 덧붙인 모양을 따른다.
5. commit. 넣는 것은 일곱 파일 · 이 plan · design이다.
6. 서브프로젝트 닫기(design "닫을 때"). 이 milestone이 PE의 마지막이다.
   - design의 `Status:`를 `끝났다(날짜)`로 고친다.
   - `CLAUDE.md`의 완료 표에 한 줄.
   - `docs/decisions/project_paste_ergonomics.md`를 만들고 `MEMORY.md`에 한 줄.
   - 다시 연 결정에 한 줄씩 덧붙인다. CM design 결정 9와 "비워 둔 자리"의 여러 줄 붙여넣기,
     `docs/decisions/project_copy_mode.md`의 "bracketed paste를 안 쓴다" 절, FP design의 164 · 368줄 근처,
     GE design의 위험 2와 비목표 2 · 4. 각각 "PE-M1(또는 M2)이 이것을 바꿨다"와
     `[[project_paste_ergonomics]]`. GE 비목표 2(사용자 vimrc가 tmpfs)는 PE-M2가, 비목표 4(viminfo)는 PE도
     안 했다(PE 비목표 4).
   - `docs/guides/lessons.md`. design "닫을 때"의 `clip> paste` 항목은 PE-M1에서 이미 들어갔으면 건너뛴다.
     이 milestone이 더할 만한 것은 셋이다 — "서브프로젝트를 넘어 유효한 실측"에 `vim -e`가
     `xterm-256color`에서 대체 화면에 찍는다는 것과 `-T dumb`(확정 1), `HOME=/`이면 vim이 `/.vimrc`로
     찍는다는 것(확정 2). "핵심 파일"의 `config/check.sh` 항목에 1 · 2차의 vim 검사, `kernel/vim/` 항목에
     `/.vimrc` 링크와 seed.
   - `HANDOFF.md`.

## design과 다르게 적은 것

1. vim 명령에 `-T dumb`을 붙였다(확정 1). design 결정 8은 `vim -e`가 대체 화면에 안 들어간다고 적었는데,
   `TERM=xterm-256color`에서는 들어가고 나오면서 출력이 사라진다.
2. 1차의 판정 글자가 `\| +2: ~/\.vimrc`가 아니라 `\| +2: /\.vimrc`다(확정 2). 게스트의 `HOME`이 `/`라서
   vim이 `~`로 줄이지 않는다.
3. 1차에 음성 검사(`Error detected while processing`이 화면에 없다)를 더했다(확정 3). design 결정 8의 표는
   에러가 "이 자리에 먼저 나온다"고 적었지만, 양성 기다림은 그래도 초록이다.
4. `config_test`의 검사가 넷이 아니라 다섯이다 — 원칙 4(`tabstop` 금지)를 함수가 지킨다(Task 4-1).
5. `tools/check.sh`의 `WANT`에 `.vimrc`를 더했다(확정 9). design 결정 7의 다섯 자리 밖이다.
6. mutation 4를 `.EXCL` 삭제가 아니라 `.EXCL` → `.TRUNC`로 적었다(확정 6). `.EXCL`만 지우면 seed가 같은
   글자로 파일 앞부분을 덮을 뿐이고 사람의 줄이 남아서 `tabstop=3` 기다림이 초록이다. 그 경우는 2차의
   기존 음성 검사만 잡는다.
7. mutation 5를 더했다. 3의 음성 검사가 실제로 잡는지를 `config_test`를 끈 체인으로 본다.
8. mutation 2가 빨개지는 자리. design은 "훅을 통과하더라도 1차의 로그 검사가"라고 적었는데, 훅이 먼저
   빨개지므로 체인은 로그 검사까지 안 간다(Task 7-3).
9. `kernel/vim/vimrc`의 `/.vimrc`는 두 자리였고 그중 5줄만 고친다(확정 8).
10. 2차 검사의 자리를 `OFF_KEYS` 앞으로 정했다(design은 "2차 훅"까지만 적었다). 실패하면 3차가 읽을
    설정을 심지 않고 나간다.

design의 전제가 코드와 어긋난 것은 셋이다. 결정 8의 "대체 화면에 들어가지 않는다"(확정 1), 실측 6 표의
`~/.vimrc`가 게스트의 `HOME`과 다른 조건에서 잰 값이라는 것(확정 2), 검증 mutation 4의 기대(확정 6 —
`seedOneFile`에 `O_TRUNC`가 없다). 그 밖의 전제 — 링크 · seed · 호출의 자리, `seedOneFile`의 로그 문구,
`seeded /config/` 음성 검사가 접두로 본다는 것, 7차가 이름별이라는 것, `render` 체인에 디스크가 없다는 것 —
는 design대로였다.

## 이 milestone에서 안 하는 것

- `/.viminfo`를 `/config`로 남기는 것(design 비목표 4).
- `config_test`를 끄고 seed에 `set tabstop=3`을 넣은 체인 run(Task 7-1의 끝 단락).
- design mutation 4의 원래 모양(`.EXCL`만 지운다)을 체인으로 돌리는 것(확정 6이 코드로 따졌다).
- vim 런타임(syntax · filetype · plugin)을 싣는 것. 시스템 vimrc가 그것 없이 쓰는 모양은 GE의 결정이다.
- 2 · 8 · 9차 음성 검사의 FAIL 문구("re-seeded an rc file")를 vimrc까지 포함하게 고치는 것. 접두로 보므로
  동작은 맞고, 문구는 그 줄 위의 `seeded` 덤프가 무엇이 다시 깔렸는지 말한다.

## PE-M2가 실측한 것

2026-10-04. Task 0~7은 Sonnet 서브에이전트가 하고 보고했고, lead가 diff(`git diff`) · 체인 로그 · 디스크
덤프를 직접 읽어 대조했다. Task 8은 lead가 했다. plan의 기대와 글자나 수가 다른 것은 시리얼 로그의 번호
(`mktemp` 순서)뿐이었다.

1. Task 0의 기준값. 돌고 있는 docker 없음, 마지막 commit `2c0443e`(PE-M1), `rg` 확인 열 줄이 plan 그대로.
   `init`의 `zig build test`는 `^PASS` 2줄. 기준 `config` 체인은 `exit=0`에 2분 28.44초(확정 10의 2026-09-13
   값 2분 07~10초보다 약 20초 길다 — ST · TQ가 더한 검사). `seeded /config/`는 1차 로그 4 · 7차 로그 1 ·
   나머지 0.
2. Task 1~6의 diff. 일곱 파일이 확정 11의 표와 줄 수까지 같다(+259/−5). 지운 줄은 `make_initrd.sh`의
   CU 주석 세 줄과 `kernel/vim/vimrc`의 머리 주석 두 줄뿐. `SYNTAX-OK` · `ENTRY-OK` 둘 · `ASCII-ONLY`.
   Task 4-3의 첫 컴파일이 `build exit=0` · `test exit=0` · `^PASS` 2줄 — plan의 Zig 조각은 `ast-check`까지만
   거쳤는데(확정 11) 첫 빌드에 통과했다.
3. Task 6-4의 `config` 체인. `exit=0` · `PASS`에 2분 35.61초(기준보다 7.17초 — 확정 10이 예상한 20초보다
   짧다). 1차에 `boot 1: vim read /etc/vim/vimrc, then the seeded /config/vimrc through /.vimrc, with no
   error` · `boot 1: a line appended to /.vimrc landed in /config/vimrc` · `boot 1: init seeded the vimrc
   too`, 2차에 `boot 2: vim read tabstop=3 from /.vimrc, the line the first boot appended`. 그 뒤의 `Ctrl+R`
   검사(fzf 상자)는 vim이 맨 아래 행에 찍은 뒤에도 초록이었다(6-4가 첫 의심으로 적어 둔 자리).
4. Task 6-5의 로그와 디스크. 1차 로그(`serial_9`)에 `seeded /config/vimrc` 1 · `seeded /config/` 5, 7차
   (`serial_1`)에 1, 나머지 0. 1차의 `1: /etc/vim/vimrc`와 `2: /.vimrc` 프레임이 각 209로 같은 수, `set
   tabstop=3` 144, 2차(`serial_3`)의 `tabstop=3` 69. `defaults.vim` · `tabstop=8` · `Error detected while
   processing`은 아홉 로그 다 0, 원본 로그의 `ESC[?1049h`도 아홉 다 0 — `-T dumb`이 대체 화면을 막았다
   (확정 1). 아홉 부팅 뒤 디스크의 `vimrc`는 857바이트(seed 843 + `set tabstop=3\n` 14)이고 마지막 세 줄이
   `" Tabs and trailing spaces not marked:` · `"set nolist` · `set tabstop=3` — seed가 다시 안 깔렸다는 것이
   바이트 수로 보인다. `ls -l`에 `gitconfig`(820) · `vimrc`(857).
5. Task 6-6의 `tools` 체인. `exit=0` · `PASS`에 1분 00.59초, `the initrd carries the four bones and all 87
   tools the list names`.
6. Task 7의 mutation 다섯. 사본 `diff` 여섯이 전부 한 줄 차이, `mounted:`가 전부 기대값.

   | mutation | `exit=` | 시간 | 어디서 빨개졌나 |
   |---|---|---|---|
   | 3 seed에 `set tabstop=3` | 1 | (`config_test`만) | `FAIL: the vimrc seed has a line vim will run:` 다음 줄 `  set tabstop=3`, `error: BadSeed` 1 |
   | 1 링크 줄 삭제 | config 1 · tools 1 | 1분 00.49초 | `FAIL(boot 1): vim did not list /.vimrc as its user vimrc` → `FAIL: first boot did not seed and edit /config/tars.conf`, 화면에 `defaults.vim` 2건. `tools`는 부팅 전 `FAIL: .vimrc is missing from the initrd` |
   | 2 `seedVimrc()` 삭제 | 1 | 59.99초 | mutation 1의 config와 같은 두 `FAIL`, `defaults.vim` 2건 |
   | 4 `.EXCL` → `.TRUNC` | 1 | 1분 20.15초 | 1차 전부 초록 → `FAIL(boot 2): vim did not see tabstop=3 from /.vimrc after the reboot` → `FAIL: second boot never started a console shell`, 화면에 `tabstop=8` 4건(`tabstop=3` 1건은 FAIL 문구 안의 글자) |
   | 5 seed에 `set nolistx` + `config_test` 끔 | 1 | 37.12초 | `FAIL(boot 1): vim reported an error while reading its vimrc files` → `FAIL: first boot …`, 화면에 `Error detected while processing /.vimrc:` · `E518: Unknown option: nolistx` · `2: /.vimrc` 각 1건 — 양성 기다림은 초록이었고 음성 검사가 잡았다(확정 3) |

   7-6 뒤 `build exit=0` · `test exit=0` · `^PASS` 2줄, 0바이트 파일 없음.
7. 루트 게이트. 18체인 × 3 전부 PASS, 1시간 8분 03.52초(PE-M1의 1시간 7분 14초보다 49초 길다 — `config`
   체인이 약 7초 길어진 것이 세 번과 initrd 재생성), `FAIL` 0줄. `config`(CP-M2)의 회차마다 `boot 1: vim read
   /etc/vim/vimrc, then the seeded /config/vimrc through /.vimrc, with no error`와 `boot 2: vim read tabstop=3
   from /.vimrc, the line the first boot appended`가 한 번씩(합계 각 3). `copy`의 검사 21 · 22와 `service`도
   3/3. 열여덟 체인이 전부 새 initrd(`/.vimrc` 링크 · 새 `init`)로 떴고, 설정 디스크를 붙이는 체인들의 1차
   부팅이 `seeded /config/vimrc`를 한 줄 더 찍어도 어느 검사도 흔들리지 않았다(확정 7).
8. Task 8-4 · 8-6. design 넷 자리(결정 7 · 8 · 검증 mutation 4 · 실측 6)에 plan이 바로잡은 것을 덧붙였고,
   옛 design · 기억 여덟 자리에 "PE가 바꿨다"를 적었다. lessons에 실측 74(`vim -e`의 대체 화면과 `-T dumb` ·
   `HOME=/`의 경로 · zsh의 `?`) · 75(셸 셋과 vim의 모드 2004, fish의 성질 둘)와 핵심 파일 둘
   (`config/check.sh` · `kernel/vim/`)을 더했다. 기억 `docs/decisions/project_paste_ergonomics.md`,
   `MEMORY.md` · `CLAUDE.md` 표 · `HANDOFF.md` 한 줄씩. 전부 이 commit에 함께 넣었다.

## 닫을 때

PE-M2는 서브프로젝트 PE의 마지막 milestone이다. 닫는 일의 목록은 Task 8-6에 있다.
