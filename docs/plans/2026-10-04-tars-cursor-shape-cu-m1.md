# CU-M1 — 게스트 vi가 모드마다 모양을 바꾼다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-cursor-shape-design.md`
Status: plan을 썼다(2026-10-04). 구현 전이다.

## 이 milestone이 끝나면

- 게스트의 `vim` · `vi` · `editor`가 Debian `vim.basic`(패키지 `vim`
  `2:9.1.1230-2`)이다. 이름 셋에 실체 하나라는 모양은 그대로이고, 바뀌는 것은
  실체 하나다(design 결정 7).
- initrd에 파일 둘이 더 들어간다. `/etc/vim/vimrc`는 커서 세 줄(`t_SI` ·
  `t_SR` · `t_EI`)이고, `/usr/share/vim/vim91/defaults.vim`은 주석뿐인 stub이다.
  원본은 저장소의 `kernel/vim/`에 있다.
- 사용자 vimrc가 없어도 vim이 insert에서 bar, replace에서 underline, normal에서
  block을 보낸다. 화면에 `E1187`도 `Press ENTER`도 없다.
- 탈출로는 `vim -u NONE`이다. 사람이 `/.vimrc`에 `set t_SI= t_SR= t_EI=`를 쓰면
  끈다(design 실측 5).
- `render/check.sh`에 검사 25~32가 더해진다. 새 체인은 없다.
- `tools/check.sh`의 검사 1이 새 파일 둘을 literal로 본다. 도구 수 65는 그대로다.

## 착수 전에 확정한 것

1. 선행 조건이 있다. CU-M0이 commit돼 있어야 한다. 이 plan을 쓰는 동안 CU-M0의
   루트 게이트가 돌고 있었고, CU-M0의 변경(`vt.zig` · `main.zig` · `vt_test.zig` ·
   `render/check.sh` · lessons)은 아직 commit 전이다. CU-M1의 게이트 검사는 CU-M0의
   `cursor>` 줄과 헬퍼(`last_frame` · `last_cursor` · `wait_for_cursor` ·
   `inverted_now` · `truncated_now` · `settle` · `CU_ROW` · `CU_COL`)를 그대로 쓴다.
2. 이미지 재빌드는 돌고 있는 게이트가 없을 때만 한다. `docker build`가
   `tars-devcontainer` 태그를 옮기면, 돌고 있는 게이트의 다음 `docker run`이
   새 sysroot를 본다. 시작 전에 `pgrep -f 'tars-devcontainer'`가 비었는지 본다.
3. amd64 패키지를 다시 쟀고 design 실측 7과 바이트까지 같다(2026-10-04, 저장소를
   마운트하지 않은 컨테이너에서 `apt-get download` · `dpkg -x`).

   | 파일 | 바이트 | gzip -6 | `DT_NEEDED` |
   |---|---|---|---|
   | `usr/bin/vim.tiny`(지금) | 1,761,704 | 857,642 | libm · libtinfo · libselinux · libacl · libc |
   | `usr/bin/vim.basic` | 3,921,984 | 1,936,457 | 위 다섯 + libsodium.so.23 · libgpm.so.2 |
   | `libsodium.so.23.3.0` | 375,496 | 둘 합 185,134 | libc · ld-linux |
   | `libgpm.so.2` | 26,552 | | libc |

   `libsodium.so.23`은 sysroot에서 `libsodium.so.23.3.0`을 가리키는 링크다.
   `find_in_sysroot`가 `-e`로 링크 이름을 찾고 `cp`가 링크를 따라가므로 손댈 것이
   없다. 두 라이브러리의 의존은 libc뿐이라 사슬이 더 안 늘어난다. 패키지
   `vim`의 `Depends`에는 `vim-common` · `vim-runtime`이 있지만 `apt-get download`는
   의존을 안 따라가므로(Dockerfile의 UT-M1 주석) 받지 않는다. 런타임이 없는 것이
   design 결정 7의 전제다.
4. 늘어나는 양을 미리 셈하면 압축 전 +2,562,328바이트, gzip으로 약 +1.26MB다.
   initrd의 tmpfs가 그만큼 커진다. 게이트의 512MB에서 `MemAvailable`이
   213MB라(lessons 이월 숙제) 메모리 문제는 아니다. 부팅 시간은 Task 6이 잰다.
5. `vim.basic --version`이 경로 셋을 말한다(arm64 같은 판으로 쟀다).

   ```
      system vimrc file: "/etc/vim/vimrc"
          defaults file: "$VIMRUNTIME/defaults.vim"
     fall-back for $VIM: "/usr/share/vim"
   ```

   `$VIM`이 없으면 `/usr/share/vim`이고, 그 아래 `vim91` 디렉터리가 있으면 그것이
   `$VIMRUNTIME`이다. 그래서 stub이 `/usr/share/vim/vim91/defaults.vim`에 있으면
   읽힌다. 바이너리 안의 문자열도 `/usr/share/vim`과 `vim91`이다.
6. `--version`의 마지막 줄은 여전히 `Linking: gcc …`다. 그래서 `tools/check.sh`
   검사 16(`vi --version` → `wait_for_screen "Linking: gcc"`)은 안 고친다. 그 줄에
   `-lsodium` · `-lgpm`이 더 나오는 것만 다르다.
7. 게스트와 같은 조건을 컨테이너에서 만들고 키를 쳐 보았다. 런타임과 `/etc/vim`을
   치우고, 시스템 vimrc 세 줄과 stub만 두고, `TERM=xterm-256color`, 빈 `HOME`,
   `script`로 47×100 pty를 줬다. 키 사이는 1.5초다. 나온 DECSCUSR과 그 밖의 것을
   적는다.

   | 경우 | 친 것 | DECSCUSR | 그 밖 |
   |---|---|---|---|
   | 기본 | `vim /tmp/cu.txt`, `i` Esc `R` Esc `:q!` | 6 · 2 · 4 · 2 | 에러 없음 |
   | 파일 없이 | `vim`, `i` Esc `:q!` | 6 · 2 | 인트로 화면이 `ESC[34m`으로 색을 입힌다 |
   | `-u NONE` | `i` `ab` Esc `:q!` | 없음 | `ab`가 1행에 찍힌다 |
   | Ctrl-O | `i` Ctrl-O `:q!` | 6 · 2 | Ctrl-O가 `t_EI`를 보낸다 |
   | stub 없음 | `i` Esc `:q!` | 6 · 2 | `E1187` · `Press ENTER` |
   | 시스템 vimrc 없음 | `i` Esc `:q!` | 없음 | 에러 없음 |

   여기서 게이트 설계에 닿는 사실이 다섯 개 나왔다.

   - 사용자 vimrc가 없으면 vim은 `compatible`이고 `showmode`가 꺼져 있다.
     `-- INSERT --`가 화면에 안 나온다. 그래서 insert에 들어갔다는 증거는
     `cursor>`의 `vt=bar`이고, 대조군(`-u NONE`)에서는 친 글자 `ab`와 커서의
     `col=2`가 증거다.
   - 새 파일 메시지는 `"/tmp/cu.txt" [New File]`이다(`[New]`가 아니다). vim이 첫
     화면을 다 그렸다는 표시로 쓴다.
   - 파일 인자 없이 띄우면 인트로 글자에 색이 입혀져 `style>` 셀이 늘어난다. 파일
     인자를 주면 인트로가 없다. 그래서 검사는 파일 인자를 준다. `~` 45줄은
     `ESC[94m`이라 `style>` 셀이 45개 나오고, 상한 96(`STYLE_DUMP_LIMIT`) 안이다.
   - stub이 없으면 `E1187: Failed to source defaults.vim`과
     `Press ENTER or type command to continue`가 대체 화면에 들어가기 전, 기본
     화면에 찍히고 vim이 키를 기다린다. 다음 키가 그 프롬프트를 닫고 명령으로도
     쓰인다(`i`를 치면 insert로 들어가 bar가 된다). 그래서 에러 판정은 `i`를 치기
     전에, 기동 직후에 해야 한다.
   - vim은 어떤 길로 나가든 마지막 DECSCUSR이 `2`(block)다. Esc도 Ctrl-O도
     `t_EI`를 보내고, 그 뒤 `ESC[?1049l`로 대체 화면을 나간다. 그래서 `:q!` 뒤
     프롬프트가 block인 것은 design 실측 10("대체 화면의 모양이 기본 화면으로 안
     샌다")의 판정이 못 된다. 그 판정은 vim이 아니라 printf로 만든다(검사 32).
8. vim이 커서를 두는 자리. 파일 하나를 열면 vim은 맨 아래 줄(`ESC[47;1H`)에 메시지를
   쓰고 `~`를 그린 뒤 `ESC[1;1H`로 돌아온다. 빈 버퍼라 insert · replace · normal
   모두 `row=0 col=0`이다. `-u NONE`에서 `ab`를 치면 `row=0 col=2`다. 기동할 때
   vim은 `t_EI`를 미리 보내지 않으므로(design 실측 4) 기동 직후의 모양은 셸에서
   물려받은 block이다.
9. 명령 줄을 `printf '\033[H\033[2J'; vim /tmp/cu.txt`로 친다. printf가 화면을
   지우면 커서가 (0,0)이고, vim이 1049로 그 자리를 저장했다가 나올 때 되돌리며,
   fish가 거기에 프롬프트를 그린다. 그래서 vim을 나온 뒤의 커서는 검사 20이 찾은
   `CU_ROW` · `CU_COL`(CU-M0 실측 2에서 `0,15`)과 같다. CU-M0의
   `cursor_shape_check`와 같은 이유로, 화면을 지우면 `style>` 상한에도 안 닿는다.
10. `type_text`에 없는 글자가 넷이다. `.`(`dot`) · `:`(`shift-semicolon`) ·
    `!`(`shift-1`) · `?`(`shift-slash`). 나머지(`v i m` · 공백 · `/` · `-` · `'` ·
    `\` · `[` · `;` · 대문자 `H` `J` `N` `O` `E`)는 이미 있다. Esc와 Enter는
    `type_keys esc` · `type_keys ret`로 친다. `R`은 `type_keys shift-r`다(lessons
    실측 6 — `sendkey`의 키 이름은 전부 소문자다).
11. 탈출로 대조군의 파일 이름은 다르게 한다(`/tmp/cunone.txt`). `wait_for_screen`은
    마지막 프레임이 아니라 로그 전체를 보므로(lessons 실측 26), 같은 이름이면
    검사 25의 `[New File]`에 곧바로 걸린다. 이름이 다르면 swap 파일도 안
    부딪친다. vim은 `/tmp`에 swap 파일을 만들고 `:q!`로 지운다.
12. 게스트로 나가는 설정 파일의 주석은 영어 ASCII로 쓴다. `firewall.nft` ·
    `sshd_config` · `services/sshd`가 그렇게 했고, 사람이 게스트에서 `cat`으로 여는
    파일이다. "왜"의 긴 설명은 `make_initrd.sh`의 한국어 주석에 둔다. vimrc에는
    줄 이음(`\`)을 쓰지 않는다. `compatible`의 `cpoptions`에 `C`가 있어 이어 쓴
    줄이 안 읽힌다.
13. 반사실은 `make_initrd.sh` 사본을 `-v`로 덮어서 한다. 그 스크립트는
    `cd "$(dirname "$0")"`라 덮어쓴 파일도 `/workspace/kernel`에서 돈다. 반사실을
    돌리면 저장소의 `kernel/initrd.cpio`가 망가진 판으로 남지만, 다음 체인이 언제나
    `make_initrd.sh`를 다시 부르므로 따로 지울 것은 없다.

## Task 0: 바꾸기 전의 기준값

이미지를 다시 굽기 전에 지금(vim.tiny) 값을 잰다. Task 6이 같은 방법으로 다시 잰다.

1. `render/check.sh`를 lessons "범용 명령"의 첫 블록으로 한 번 돌리고 시리얼 로그를
   꺼낸다(`net/check.sh`를 `render/check.sh`로 바꾼다). 약 2분이다.
2. 로그에서 커널의 initramfs 풀기 두 줄을 찾는다.

   ```bash
   grep -aiE 'unpack|Freeing initrd memory' /tmp/run/serial_1.log
   ```

   두 줄의 타임스탬프 차이와 `Freeing initrd memory: NNNNK`의 K를 적는다. WL design이
   같은 방법으로 1.48초(46,100K) → 2.44초(83,904K)를 쟀다.
3. `ls -l kernel/initrd.cpio`와 `gzip -dc kernel/initrd.cpio | wc -c`를 적는다.
   firmware 꼬리도 gzip 멤버라 `gzip -dc`가 함께 푼다. 차이만 볼 것이라 상관없다.
4. 체인 시간(`{ time … ; }`)을 적는다.

## Task 1: `devcontainer/Dockerfile`

1. sysroot `RUN`의 `apt-get download` 목록에서 `vim-tiny:amd64`를 `vim:amd64`로
   바꾼다. 같은 줄 자리다.
2. 같은 목록에 `libsodium23:amd64`와 `libgpm2:amd64`를 더한다. `libselinux1:amd64`
   바로 뒤에 둔다. vim이 함께 부르는 라이브러리들 옆이다.
3. 주석 블록을 하나 더한다. 자리는 `# ── WL-M2: 층 12(무선) ──` 블록 뒤,
   `ENV AMD64_SYSROOT=` 앞이다. 제목은 `# ── CU-M1: 층 3의 편집기를 vim.basic으로 ──`.
   담을 것:
   - 왜 바꾸나. `vim-tiny`는 `-cursorshape`로 빌드돼서 `t_SI`를 어떻게 설정해도
     한 바이트도 안 보낸다(CU design 실측 2). 컴파일 시점의 기능이라 설정으로는
     못 켠다.
   - 무엇이 따라오나. 확정 3의 표를 줄여 적는다. 새 SONAME은 둘이고 둘 다 libc만
     부른다.
   - `vim-common` · `vim-runtime`은 안 받는다는 것과 그 이유. 런타임이 없어서
     stub `defaults.vim`이 필요하다는 것은 `make_initrd.sh`가 설명한다고
     가리킨다.
4. UT-M3 블록의 표(`vim.tiny libm · libtinfo · …`)는 그때의 기록이라 고치지 않는다.
   대신 그 줄 아래에 한 줄을 붙인다: `(CU-M1이 vim.basic으로 바꿨다. 아래 CU-M1 블록)`.
5. 이미지를 다시 굽는다(확정 2를 먼저 본다).

   ```bash
   { time docker build -t tars-devcontainer devcontainer/ ; } 2>&1 | tail -3
   ```

   다운로드 층과 그 뒤의 Zig 층이 다시 돈다. 선례는 28.8초~1분 10초다(FW · TD ·
   LB · DI design). 끝나면 sysroot에 둘이 있는지 본다.

   ```bash
   docker run --rm tars-devcontainer bash -c 'ls -l $AMD64_SYSROOT/usr/bin/vim.basic \
     $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/libsodium.so.23* \
     $AMD64_SYSROOT/usr/lib/x86_64-linux-gnu/libgpm.so.2; ls $AMD64_SYSROOT/usr/bin/vim.tiny'
   ```

   `vim.tiny`는 없어야 한다(`No such file`).

## Task 2: `kernel/guest_tools.sh`

1. `usr/bin/vim.tiny:usr/bin/vim`을 `usr/bin/vim.basic:usr/bin/vim`으로 바꾼다.
   오른쪽은 그대로다. 배열 길이가 그대로라 도구 수 65가 안 바뀐다.
2. 주석 다섯 자리를 고친다(`rg -n 'vim' kernel/guest_tools.sh`).
   - 층 2 머리의 "libm은 vim.tiny와 hyperfine이 여전히 부른다" → "vim과 hyperfine".
   - 층 3 머리의 "줄 둘에 새 라이브러리가 하나도 안 딸려 온다 … vim.tiny는 …"
     문단. UT-M3의 기록으로 남기고, 끝에 한 문단을 더한다. CU-M1이 실체를
     `vim.basic`으로 바꿨고 그것이 `libsodium` · `libgpm` 둘을 더 데려온다는 것,
     이유는 커서 모양이라는 것(CU design 결정 7)을 적는다.
   - `usr/bin/vim.tiny:usr/bin/vim` 바로 위 문단의 "1.76MB짜리 사본이 두 벌" →
     "3.9MB짜리 사본이 두 벌". 그리고 "실체는 vim 하나"는 그대로 맞다.
   - 층 4의 "libm은 vim.tiny가 이미 데려왔다" → "vim이".
   - 층 5의 "vim.tiny→vi에 이어" → "vim.basic→vim에 이어".

## Task 3: `kernel/vim/vimrc` · `kernel/vim/defaults.vim` · `kernel/make_initrd.sh`

저장소에 소스를 두는 자리는 `kernel/` 아래의 하위 디렉터리다. `kernel/dhcpcd-hooks/` ·
`kernel/wifi/`가 같은 모양이다(우리가 쓴 파일을 initrd로 복사한다).

`kernel/vim/vimrc` — 주석 머리와 세 줄이다.

```vim
" TARS system vimrc (CU design decision 7). It comes from the initrd; do not edit.
" vim reads this before any user vimrc. Without a user vimrc vim stays in
" 'compatible' mode, so these three lines are the only change from plain vim.
" They make vim send DECSCUSR on mode changes: bar in insert, underline in
" replace, block in normal. To turn them off, put this in /.vimrc:
"   set t_SI= t_SR= t_EI=
" To start vim with no vimrc at all: vim -u NONE
let &t_SI = "\e[6 q"
let &t_SR = "\e[4 q"
let &t_EI = "\e[2 q"
```

`kernel/vim/defaults.vim` — 주석만 있다.

```vim
" TARS stub for $VIMRUNTIME/defaults.vim (CU design decision 7).
" vim sources this file when no user vimrc exists. The guest has no vim runtime,
" and without this file vim shows "E1187: Failed to source defaults.vim" and
" waits for ENTER on every start. The real file (5,412 bytes) turns on syntax,
" filetype plugins and the mouse, which need the runtime this guest does not have.
" Keep this file free of commands.
```

`kernel/make_initrd.sh` — `ln -sf vim "$WORKDIR/usr/bin/editor"` 블록 바로 뒤에
둔다. vim에 딸린 것을 한자리에 모은다.

```bash
mkdir -p "$WORKDIR/etc/vim" "$WORKDIR/usr/share/vim/vim91"
install -m 0644 vim/vimrc "$WORKDIR/etc/vim/vimrc"
install -m 0644 vim/defaults.vim "$WORKDIR/usr/share/vim/vim91/defaults.vim"
```

`cp` · `chmod` 두 줄 대신 `install -m 0644` 한 줄인 이유는 Task 6의 반사실이다. 파일
하나를 빼는 것이 줄 하나를 지우는 것이 된다. 0644인 이유는 `30-tars-ntp`와 같다 —
실행이 아니라 읽히는 파일이다.

그 위에 한국어 주석을 단다. 담을 것:

- 시스템 vimrc가 왜 여기인가. `/config`가 아니라 initrd에 있어서 모든 부팅에서
  된다 — ISO로 뜬 세션과 설정 디스크가 없는 `render` 체인에서도. 사용자 vimrc는
  그 뒤에 읽히므로 사람이 끌 수 있다(design 결정 7의 후보 표를 가리킨다).
- stub이 왜 필요한가. `vim.basic`은 사용자 vimrc가 없으면 `defaults.vim`을 읽으려
  하고, 런타임이 없으면 `E1187`과 `Press ENTER`를 띄운다. 시스템 vimrc의
  `skip_defaults_vim`으로는 못 막는다 — 그 변수를 보는 코드가 `defaults.vim` 안에
  있다(design 실측 6). `vim.tiny`에는 없던 증상이다.
- 경로에 버전이 박혀 있다. Debian이 vim 9.2로 올리면 `vim92`가 되어 stub이 안
  읽힌다(design 위험 4). 그날은 `render` 검사 25가 `E1187`로 빨개진다.
- sysroot가 아니라 저장소에서 온다. 우리가 쓴 파일이기 때문이다(`30-tars-ntp`와
  같은 자리).

`make_initrd.sh`의 vim 이름 주석 둘도 고친다. `ln -sf vim "$WORKDIR/usr/bin/vi"`
위의 "1.76MB짜리 사본" → "3.9MB짜리 사본", `pager` 블록의 "vim.tiny→vi" →
"vim.basic→vim"이다.

## Task 4: `tools/check.sh`

1. 검사 1의 literal 목록에 둘을 더한다. 자리는 `WANT+=(usr/bin/tars-install)` 뒤다.

   ```bash
   # CU-M1: vim의 시스템 vimrc와 stub defaults.vim. tq-probe와 같은 자리다 — 배열에
   # 없고 make_initrd.sh가 손으로 넣는 파일이라 여기 적어야 tautology가 아니다.
   # 빠지면 render 체인의 vim 검사(부팅 뒤)가 아니라 여기서 먼저 드러난다.
   WANT+=(etc/vim/vimrc usr/share/vim/vim91/defaults.vim)
   ```

2. 머리 주석의 "UT-M3이 층 3(git · vim.tiny)을 더하고"는 그때의 기록이라 둔다.
   그 문단 끝에 한 줄을 붙인다: `CU-M1이 vim의 실체를 vim.basic으로 바꿨다. 검사
   16은 그대로다 — --version의 마지막 줄이 여전히 Linking: gcc다.`
3. 검사 16(`vi --version`)은 안 고친다(확정 6).

## Task 5: `render/check.sh` — 검사 25~32

검사 24 뒤, `# ── 음성 검사` 앞에 둔다. 앞 검사들의 기대값은 하나도 안 바뀐다.

### 손볼 곳

- `type_text`에 네 줄(확정 10).

  ```bash
  '.') keys+=(dot) ;;
  ':') keys+=(shift-semicolon) ;;
  '!') keys+=(shift-1) ;;
  '?') keys+=(shift-slash) ;;
  ```

- 헬퍼 둘. CU-M0의 헬퍼 옆에 둔다.

  ```bash
  # 로그의 한 지점 뒤에 찍힌 screen> 줄들. vim을 띄운 뒤의 화면만 보려는 것이다.
  # 파이프 끝이 -q 없는 grep이라 진입 검사에 안 걸린다. 0줄이면 1이라 || true.
  screens_since() { tail -c +"$(($1 + 1))" "$LOG" | grep -a 'terminal: screen>' || true; }

  # 모양 하나를 기다리고 세 층과 반전 셀 수를 본다. cursor_shape_check와 같은 판정을
  # 키를 친 뒤에 한다(그 함수는 printf를 스스로 친다).
  #   $1 설명   $2 기다릴 cursor> 패턴   $3 기대 "ink=N box=WxH"   $4 기대 반전 셀 수
  vim_shape_check() { … }
  ```

  `vim_shape_check`의 본문은 `cursor_shape_check`의 `type_text`/`type_keys` 두 줄을
  뺀 나머지와 같다 — `wait_for_cursor "$2"` → `settle || true` → `truncated_now`가 0 →
  `ink=` `box=` 비교 → `inverted_now` 비교 → 한 줄 출력. 실패 메시지는 `$1`과
  `last_cursor` 줄 전체를 담는다. `cursor_shape_check`를 이 함수 위에 다시 쓰는
  것은 하지 않는다. CU-M0의 초록을 흔들 이유가 없다.

### 검사 표

| 검사 | 친다 | 본다 |
|---|---|---|
| 25 | `VIM_LOG_START`에 로그 크기를 담고 `printf '\033[H\033[2J'; vim /tmp/cu.txt` Enter | 아래 기다림 패턴 뒤 `settle`. 그다음 `screens_since "$VIM_LOG_START"`에 `E1187` · `Press ENTER` · `E[0-9]{2,4}:`가 없다. `last_cursor`가 `vt=block drawn=block row=0 col=0 cols=1 ink=0 box=0x0`이고 반전 셀이 1이다. vim이 기동만 했고 아직 모양을 안 바꿨다는 대조다(확정 8) |
| 26 | `i` | `vim_shape_check "insert" 'vt=bar drawn=bar row=0 col=0 ' "ink=32 box=2x16" 0` |
| 27 | `esc` | `'vt=block drawn=block row=0 col=0 '` · `ink=0 box=0x0` · 반전 1 |
| 28 | `shift-r` | `'vt=underline drawn=underline row=0 col=0 '` · `ink=16 box=8x2` · 반전 0 |
| 29 | `esc` | 27과 같다 |
| 30 | `:q!` Enter | `"vt=block drawn=block row=${CU_ROW} col=${CU_COL} "` · `ink=0 box=0x0` · 반전 1. 그리고 마지막 프레임의 `screen>` 줄에 `New File`이 없다(vim을 나온 프레임이다) |
| 31 | `VIM_NONE_START`를 담고 `printf '\033[H\033[2J'; vim -u NONE /tmp/cunone.txt` Enter, `cunone\.txt" \[New File\]`을 기다린 뒤 `i` `a` `b` | `'vt=block drawn=block row=0 col=2 '` · `ink=0 box=0x0` · 반전 1. `col=2`가 `ab`가 들어갔다는, 곧 insert에 들어갔다는 증거이고, 그런데도 block이다 — 26의 bar가 우리 시스템 vimrc에서 왔다는 증명이다. 이어서 `esc`, `:q!` Enter를 치고 30과 같은 프롬프트 판정을 한다 |
| 32 | `printf '\033[H\033[2J\033[?1049h\033[6 q\033[?1049l'` Enter | `"vt=block drawn=block row=${CU_ROW} col=${CU_COL} "` · `ink=0 box=0x0` · 반전 1. 대체 화면에서 bar를 정하고 나왔는데 프롬프트가 block이다(design 실측 10). 같은 printf에서 1049 둘만 뺀 것이 검사 21이고 그쪽은 bar다 — 그것이 이 검사의 양성 대조다 |

검사 31 뒤, 32 앞에서 vim 구간 전체의 에러를 한 번 더 본다.
`screens_since "$VIM_LOG_START"`에 `E[0-9]{2,4}:`와 `Press ENTER`가 없어야 한다.
검사 25는 기동 직후만 보았고, 이것은 두 vim 세션 전체를 본다.

검사 25의 기다림은 이것이다.

```bash
wait_for_screen '\[New File\]|Press ENTER'
```

`Press ENTER`를 넣는 이유. stub이 없으면 vim은 `[New File]`을
그리기 전에 기본 화면에서 키를 기다린다(확정 7). 패턴이 `[New File]`뿐이면 15초를 다
쓰고 "vim이 안 떴다"로 죽는다. 둘 중 하나를 기다리고 나서 에러 줄을 보면, 실패
메시지가 `E1187`을 직접 말한다.

검사 26~29는 `type_keys` 하나를 치고 `vim_shape_check`를 부른다. 기다림 패턴에
`row=0 col=0`을 넣는 이유는 CU-M0 실측 3과 같다. vim은 메시지를 쓰려고 커서를 맨
아래 줄로 옮겼다가 돌아오므로, 그 사이 프레임에서 판정하지 않으려는 것이다.

검사 30 · 31의 프롬프트 판정은 `vim_shape_check`로 한다. 패턴이 `CU_ROW` ·
`CU_COL`이라 vim이 아직 떠 있으면(커서가 `row=0 col=0`이나 맨 아래 줄) 안 맞는다.

모든 검사가 block으로 끝난다. 이 뒤에 검사를 더하는 사람이 다른 모양을 물려받지
않는다.

마지막 `echo "TR-M2 PASS: …"` 끝에 ", and vim switches the cursor shape between
modes"를 붙인다.

진입 검사 셋을 게이트 전에 대 본다(lessons "게이트를 돌리고 읽는 법"의 `ENTRY-OK`
명령, `X`를 `render`로). 새 헬퍼의 파이프 끝 grep에 `-q`가 없어야 한다.

## Task 6: 게이트

모두 컨테이너에서 한다. 체인은 하나씩, 겹치지 않게 돌린다(WP-M0 실측 8).

1. 이미지 재빌드(Task 1의 5).
2. `tools/check.sh` 한 번. 검사 1이 `etc/vim/vimrc`와 defaults stub을 찾고, 검사 16이
   `Linking: gcc`를 찾아야 한다. 끝 줄의 도구 수가 65다. 약 3분이다.
3. `render/check.sh` 한 번. lessons "범용 명령"의 첫 블록으로 시리얼 로그를 꺼내
   온다. 검사 25~32 자리의 `cursor>` · `style>` 줄과 검사 25의 마지막 `screen>`
   줄을 "실측한 것"에 옮긴다. Task 0과 같은 두 줄(`unpack` · `Freeing initrd
   memory`)의 타임스탬프와 initrd 크기 둘(`ls -l` · `gzip -dc | wc -c`)도 함께
   적는다. 기준값과 비교하는 것이 design 위험 5의 답이다. 체인은 CU-M0의 1분
   36초~1분 59초보다 vim 구간만큼(약 30~60초) 길어질 것이다.
4. 반사실 둘. 저장소 파일은 안 고치고 `make_initrd.sh` 사본을 `-v`로 덮는다
   (lessons "범용 명령"). 돌리기 전에 사본에 편집이 실제로 들어갔는지 `diff`로
   본다(lessons 실측 52).

   ```bash
   mkdir -p /tmp/run
   cp kernel/make_initrd.sh /tmp/run/make_initrd.sh
   # (a) 시스템 vimrc. (b)는 이 줄 대신 vim/defaults.vim의 install 줄을 지운다.
   sd -F 'install -m 0644 vim/vimrc "$WORKDIR/etc/vim/vimrc"' '' /tmp/run/make_initrd.sh
   chmod +x /tmp/run/make_initrd.sh; diff kernel/make_initrd.sh /tmp/run/make_initrd.sh
   docker run --rm -v "$PWD":/workspace \
     -v /tmp/run/make_initrd.sh:/workspace/kernel/make_initrd.sh:ro \
     -w /workspace tars-devcontainer bash render/check.sh
   ```

   - (a) 시스템 vimrc를 뺀다. 기대: 검사 25는 초록(에러가 없다), 검사 26의
     `wait_for_cursor`가 15초를 다 쓰고 마지막 줄이 `vt=block drawn=block row=0
     col=0`이다.
   - (b) stub `defaults.vim`을 뺀다. 기대: 검사 25가 `E1187`(과 `Press ENTER`)으로
     빨갛다.

   반사실이 예상과 다른 검사에서 죽거나 통과하면 그대로 적는다. 같은 사본으로
   `tools/check.sh`를 돌리면 부팅 전의 검사 1에서 `… is missing from the initrd`로
   죽어야 한다 — (b) 하나로 한 번만 본다(약 1분).
5. regression은 루트 게이트가 맡는다. initrd가 바뀌므로 열여덟 체인이 전부 새
   initrd로 부팅하고, 바이너리를 바꾼 것은 `vim` 하나다.
6. 루트 게이트 3/3. 18체인, 약 1시간 5분이다. `run_in_background`로 돌리고
   `{ time …; }`로 감싼다. 완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가
   비었는지 먼저 본다.

## Task 7: 문서

- 이 plan의 `Status:`와 맨 아래 "CU-M1이 실측한 것" 절. 검사 25~32의 실제 줄,
  반사실 둘, 이미지 재빌드 시간, initrd 크기와 풀기 시간의 전후, 체인 시간, 루트
  게이트 시간을 적는다.
- design의 `Status:`를 `끝났다(날짜)`로 고친다. 실측 절 끝에 이 plan의 확정 7에서
  design과 다르게 드러난 것을 짧게 더한다 — `showmode`가 꺼져 `-- INSERT --`가 없다는
  것, `[New File]`, E1187이 대체 화면 전에 찍힌다는 것, Ctrl-O도 `t_EI`를 보내서
  vim으로는 실측 10을 판정할 수 없다는 것.
- `docs/decisions/project_cursor_shape.md` 신설과 `MEMORY.md`에 한 줄. 무엇이
  바뀌었나(렌더러 모양 셋 · vim.basic · 시스템 vimrc · stub), 다시 조사하지 말 것
  (vim-tiny는 `-cursorshape`라 설정으로 안 된다 · 셸 셋은 DECSCUSR을 안 보낸다 ·
  stub이 없으면 E1187 · 경로의 `vim91`), 탈출로, 관련 기억(`project_userland_tools`).
- `docs/decisions/project_userland_tools.md`의 "착수 전 실측" 9(편집기를 `vim.tiny`로
  정했다) 끝에 한 줄을 붙인다. CU-M1이 커서 모양 때문에 `vim.basic`으로 바꿨다는
  것과 `[[project_cursor_shape]]`.
- `CLAUDE.md`의 완료 표에 한 줄. 끝난 날, 그리고 "vim의 insert는 bar, replace는
  underline, normal은 block이다 — 렌더러가 DECSCUSR 모양 셋을 그리고, 게스트 vi를
  `vim.basic`으로 바꿔 시스템 vimrc 세 줄을 initrd에 넣었다. 새 체인 없이 `render`
  체인이 본다".
- `docs/guides/lessons.md`.
  - "핵심 파일"의 게이트 절, `kernel/build.sh` 항목 근처에 `kernel/vim/` 한 항목.
    시스템 vimrc와 stub의 자리, 경로의 `vim91`이 vim 판에 묶여 있다는 것, stub을
    지우면 E1187이라는 것.
  - 같은 절의 `render/check.sh` 항목. 검사 스물넷 → 서른둘, 검사 25~31이 vim을
    띄운다는 것과 그 화면 판정이 기동 직후에 에러 줄을 본다는 것.
  - 실측 42(alternatives 링크)는 그대로 맞다. `vi` · `editor`가 여전히 링크다.
- `HANDOFF.md`는 lead가 쓴다.

## CU-M1이 실측한 것

(구현 뒤에 채운다.)
