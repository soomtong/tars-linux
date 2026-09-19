# TS-M3 — 사람이 읽는 시각이 된다

Date: 2026-09-19
design: `docs/superpowers/specs/2026-09-15-tars-time-sync-design.md`
앞 milestone: `docs/superpowers/plans/2026-09-15-tars-time-sync-ts-m2.md`

TS-M1이 시계를 뛰었고 M2가 그 상대를 네트워크에서 받았다. 그런데 게스트의
`date`는 여전히 UTC를 찍는다 — 2031-03-04 05:06:07을 서울에 앉은 사람이
읽으면 "새벽 다섯 시"이고, 그 사람의 시계는 오후 두 시를 가리킨다. 남은 일이
그 아홉 시간이다.

Goal: `tars.conf`에 `timezone=Asia/Seoul`을 적은 기계의 `date`가 서울 시각을
찍는다. 그 이름이 틀리거나 파일이 없으면 로그 한 줄을 찍고 UTC로 떨어지며,
이 키를 안 적은 기계의 동작은 한 글자도 안 바뀐다. 게이트가 그것을 매번
증명한다.

Architecture: 파일 하나(zoneinfo)와 문자열 하나(`TZ`)가 전부다. glibc가
`TZ=Asia/Seoul`을 보면 `/usr/share/zoneinfo/Asia/Seoul`을 읽어 규칙을 알고,
게스트의 모든 프로세스가 PID 1의 env 블록을 물려받으므로 `date`도 셸도 같은
것을 본다(design 결정 8 · 9). 우리 코드가 하는 일은 그 이름을 설정에서 읽어
파일이 진짜 있는지 한 번 보고 블록에 넣는 것뿐이다.

```
devcontainer/Dockerfile ──(tzdata)──> sysroot ──(make_initrd.sh)──> initrd의 /usr/share/zoneinfo/
                                                                              ▲
tars.conf의 timezone=Asia/Seoul ──> config.zig가 읽는다 ──> main.zig가 파일을 연다(TZif인가)
                                                              └──> environ.zig가 TZ=Asia/Seoul을 블록에 넣는다
                                                                   └──> 셸 · date · 모든 자식이 물려받는다
```

Tech Stack: Zig 0.16(`std.os.linux`만) · Debian tzdata(Architecture: all) ·
bash · cpio · QEMU 10.0.11 · debugfs(e2fsprogs)

---

## 착수 전에 저장소에서 확인한 것 셋

부팅은 안 했고 컨테이너도 안 띄웠다(Docker daemon이 꺼져 있었다). 파일을
읽어서 안 것이다.

1. terminal이 셸을 `forkpty` + `execv`로 띄운다(`terminal/src/pty.zig:39-43`).
   `execv`는 environ을 그대로 물려주므로 PID 1의 블록에 `TZ`를 넣으면 PTY 셸도
   받는다. 시리얼 콘솔 셸은 init이 직접 `execve`한다. 두 길이 다 env 블록
   하나를 지난다 — design 결정 9의 전제가 맞다.
2. `environ.zig`의 `MAX_ENTRIES`가 16이고 지금 가장 많이 쓰는 경우(zsh)가
   커널 둘 + PATH + XDG + 히스토리 셋 = 7이다. `TZ` 하나를 더하면 8이다.
   `environ_test`의 넘침 경계가 하나 움직인다.
3. `net/check.sh`의 검사 17이 `config shell=.* net=dhcp ntp=10.0.2.2`를
   끝 고정 없이 grep한다. 설정 로그 줄의 맨 뒤에 `timezone=…`을 붙여도 그
   grep과 다른 체인의 `config shell=` grep 열 자리가 한 글자도 안 바뀐다.

## design에 없던 결정 여섯

M1·M2가 그랬듯 design을 고치지 않고 이 plan이 근거와 함께 정한다.

### 결정 M3-A — 값은 `Config` 안의 고정 배열에 산다

`Config`는 값으로 돌려지고(`load` → `parse` → `main`) 힙이 없다. `parse`가
받는 `text`는 `load`의 스택 버퍼라서 그 안을 가리키는 슬라이스를 `Config`에
담으면 `load`가 돌아오는 순간 댕글링이다. 그래서 `Timezone`이 배열 64바이트와
길이를 갖는 struct다. IANA 이름 중 가장 긴 것이
`America/Argentina/ComodRivadavia` 32글자라 두 배를 둔다.

`Ntp`가 `[4]u8`을 갖는 것과 같은 모양이고 크기만 다르다. `Config` 하나가
64바이트 커지는데 그것은 `main()`의 스택에 한 번 사는 값이다.

### 결정 M3-B — "있는지 본다"는 첫 넉 자 `TZif`를 읽는 것이다

design 결정 8은 `/usr/share/zoneinfo/<값>`이 있는지만 보라고 했다. `access`로
존재만 보면 두 가지가 샌다.

- `timezone=Asia` — 디렉터리가 있다. glibc는 그것을 못 읽고 POSIX 문자열로
  다시 해석하다 실패해서 이름이 `Asia`인 UTC가 된다. 조용히 틀린다.
- `timezone=zone.tab` — 같은 디렉터리에 사는 텍스트 파일이다. 같은 증상이다.

glibc의 `tzfile.c`가 파일을 받거나 버리는 첫 기준이 처음 넉 자가 `TZif`인
것이다. 우리가 같은 넉 자를 읽으면 glibc가 물을 질문을 미리 묻는 셈이고,
그 값이 "조용히 UTC" 대신 로그 한 줄이다. 값을 해석하는 것이 아니다 — 규칙은
한 바이트도 안 읽고 파일의 종류만 본다.

`UTC`는 이 확인을 안 거친다. glibc는 `TZ=UTC`를 파일 없이도 이름만으로 알고,
그래서 zoneinfo가 통째로 없는 initrd에서도 기본값이 로그를 안 찍는다.

### 결정 M3-C — 그 확인은 `main.zig`의 `resolveShell` 옆에 산다

`resolveShell`이 하는 일이 정확히 이것이다 — "설정이 고른 것이 정말 있는지
확인하고, 없으면 기본값으로 내려온다". 시스템 콜을 하는 부분(`open` · `read`)은
`main.zig`의 `resolveTimezone`이 갖고, 순수한 부분 둘(경로를 조립하는 것 ·
넉 자를 대조하는 것)은 `config.zig`에 두어 `config_test`가 본다. `config.zig`의
`parse`가 순수 함수로 남는 것이 이 저장소의 규칙이고, 그 규칙이 여기서도
선다.

### 결정 M3-D — `environ.zig`는 만들어진 항목을 받는다

`environ.zig`는 `config.zig`를 모른 채 있어야 한다(`withTarsEnv`의 주석 —
그래야 호스트 검사가 순수 계산으로 남는다). 그래서 이름의 최대 길이를 저쪽에서
가져올 수 없다.

`withTarsEnv`가 `hist`를 받는 것과 같은 수법을 쓴다 — "어느 시간대인가"가
아니라 "무엇을 붙일까"를 받는다. `environ.tzEntry(buf, name)`이 `TZ=<name>`을
NUL로 닫아 만들고, `withTarsEnv`는 그 `[:0]const u8`을 하나 더 받아 `XDG` 뒤
`hist` 앞에 넣는다. 버퍼 크기 `TZ_ENTRY_MAX`는 `environ.zig`가 80으로 적고,
`config.TZ_NAME_MAX`(64) + `TZ=`(3) + NUL(1)이 그 안에 드는지는 둘을 다 아는
`main.zig`의 comptime 검사가 못 박는다.

`TZ=UTC`도 항상 넣는다. 안 넣으면 "이 키를 안 적은 기계"와 "적은 기계"의
블록 길이가 갈리고, 넣으면 `date`의 출력이 지금과 글자 그대로 같다(파일도
`TZ`도 없는 지금 glibc가 이미 UTC를 찍는다).

### 결정 M3-E — 게이트는 한 줄로 두 시각을 친다

design의 검사가 "같은 순간의 `date -u`와 `date`가 정해진 만큼 벌어진다"이다.
치는 것은 이것이다.

```
echo tsz=$(date -u +%H)/$(date +%H%Z)
```

기대가 `tsz=05/14KST`다. stub이 답하는 1930367167이 2031-03-04T05:06:07Z이고
서울은 UTC+9라 14:06:07이다. 시각을 뛴 직후에 치므로 시가 바뀌기까지 53분이
남아 있고, 검사 19까지의 타이핑이 그 안에 끝난다. `%Z`가 `KST`인 것이 값을
하나 더 낸다 — 약어는 zoneinfo 파일에만 있어서, 파일을 못 읽고 UTC로 떨어진
게스트는 `14`도 `KST`도 못 찍는다(`05/05UTC`가 된다).

`Asia/Seoul`을 고른 이유는 이 기계를 쓰는 사람의 시간대라는 것과 서머타임이
없어서 연중 어느 날 돌려도 `+0900`이라는 것이다.

### 결정 M3-F — 검사 번호는 23·24이고 자리는 부팅 A다

부팅 B의 검사가 20 · 21 · 22이고 새 둘은 부팅 A(검사 19 뒤)에 들어간다.
번호를 다시 매기면 design 실측 20 · 22와 HANDOFF의 문장 여럿이 낡는다 —
번호는 자리가 아니라 이름이므로 23 · 24를 쓰고 그 사실을 주석 한 줄로
적는다.

---

## Task 0 — 지금 상태를 재고 시작한다

- [ ] Step 0: Docker daemon을 켠다

이 세션을 열 때 `docker images`가 소켓을 못 찾았다. OrbStack이 안 떠 있는
것이다.

```bash
open -a OrbStack
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker images tars-devcontainer --format '{{.Repository}} {{.Size}} {{.CreatedSince}}'
```

기대: 이미지 한 줄. 안 나오면 여기서 멈추고 사용자에게 말한다.

- [ ] Step 1: 호스트 검사가 지금 초록인지 본다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test' 2>&1 | tail -12
```

기대: 모듈별 요약 줄(config · power · devices · storage · environ · sntp)이
전부 나오고 빨간불이 없다. M2 plan이 "PASS 여섯"이라고 잘못 적었던 자리다 —
`PASS`는 `zig build test`의 스텝 수라 둘뿐이다.

- [ ] Step 2: sysroot에 zoneinfo가 없고 컨테이너에는 있는 것을 본다

design 확인 8을 컨테이너에서 다시 본다. 이번에는 트리의 모양(디렉터리 ·
링크)까지 본다 — `cp -r`이 링크를 링크로 복사하는지가 initrd 크기를 정한다.

```bash
docker run --rm tars-devcontainer bash -c '
  echo "sysroot:"; ls -d /usr/local/amd64-sysroot/usr/share/zoneinfo 2>&1
  echo "container:"; du -sh /usr/share/zoneinfo
  echo "files=$(find /usr/share/zoneinfo -type f | wc -l) links=$(find /usr/share/zoneinfo -type l | wc -l) dirs=$(find /usr/share/zoneinfo -type d | wc -l)"
  echo "top-level links:"; find /usr/share/zoneinfo -maxdepth 1 -type l -exec ls -l {} \;
  echo "Asia/Seoul: $(stat -c %s /usr/share/zoneinfo/Asia/Seoul) bytes, head: $(head -c 4 /usr/share/zoneinfo/Asia/Seoul)"
  echo "UTC: $(stat -c %s /usr/share/zoneinfo/UTC) bytes, head: $(head -c 4 /usr/share/zoneinfo/UTC)"
  dpkg -S /usr/share/zoneinfo/Asia/Seoul'
```

기대: sysroot 쪽은 "No such file", 컨테이너 쪽은 2.1M · 파일 443 · 링크 51
(확인 8), 두 파일의 head가 `TZif`, 소유 패키지가 `tzdata`. 수가 다르면 그
수를 적고 진행한다 — 이미지가 확인 8 뒤에 다시 구워졌을 수 있다.

- [ ] Step 3: initrd 크기와 `net` 체인 단독 시간을 잰다 (약 1분)

```bash
ls -l kernel/initrd.cpio
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } 2>&1 | tail -20
```

기대: `PASS`와 56초 안팎(M2 실측 21). 이 둘이 Task 7에서 같은 명령으로 다시
재는 기준선이다. initrd 크기는 체인이 다시 구운 뒤의 값을 적는다(체인이
`make_initrd.sh`를 부른다).

## Task 1 — sysroot에 tzdata

파일: `devcontainer/Dockerfile`

- [ ] Step 1: 목록 끝에 `tzdata`를 더하고 그 앞에 주석 블록을 넣는다

`ENV AMD64_SYSROOT=/usr/local/amd64-sysroot` 바로 위(NW-M2 주석 블록의 끝)에
이것을 더한다.

```
#
# ── TS-M3: 층 6(시간대 데이터) ──────────────────────────────────────────
#
# tzdata 하나다. Architecture: all이라 `:amd64`를 안 붙인다 — fish-common ·
# zsh-common · ncurses-base와 같은 줄이다. 바이너리가 아니라 데이터라 새
# 라이브러리가 0개이고, 푼 것이 2.1MB · initrd에서 약 171KB다(TS 확인 8).
#
# 컨테이너 자신의 /usr/share/zoneinfo와 바이트까지 같은 파일들이다. 그래도
# sysroot를 거치게 하는 이유가 TS design 결정 10이다 — 게스트에 들어가는
# 파일의 출처가 하나여야 make_initrd.sh를 읽는 사람이 "이 파일은 어디서
# 왔나"를 한 자리에서 답한다.
#
# trixie는 옛 이름(US/Pacific · Japan 같은 것)을 tzdata-legacy로 갈라
# 두었다. 안 받는다 — 지역/도시 꼴의 이름이 전부 tzdata에 있다.
```

그리고 다운로드 목록의 마지막 줄을 이렇게 바꾼다.

```
        libmnl0:amd64 \
        tzdata) \
```

- [ ] Step 2: 더한 줄과 지운 줄을 센다

```bash
cd /Users/dp/Repository/tars-linux
git diff --stat devcontainer/Dockerfile
echo "=== 지운 줄 ==="; git diff devcontainer/Dockerfile | grep '^-' | grep -v '^---'
```

기대: 지운 줄이 정확히 하나 — `        libmnl0:amd64) \`. 닫는 괄호가 한 줄
아래로 내려간 것뿐이다.

- [ ] Step 3: 이미지를 다시 굽는다 (NW-M2 기준 약 42초)

```bash
mkdir -p /tmp/tsm3
{ time docker build -t tars-devcontainer devcontainer/ ; } \
  > /tmp/tsm3/image.log 2> /tmp/tsm3/image.time
tail -3 /tmp/tsm3/image.time
```

- [ ] Step 4: sysroot에 들어갔는지 본다

```bash
docker run --rm tars-devcontainer bash -c '
  du -sh /usr/local/amd64-sysroot/usr/share/zoneinfo
  for f in Asia/Seoul UTC Etc/UTC America/Argentina/ComodRivadavia; do
    p=/usr/local/amd64-sysroot/usr/share/zoneinfo/$f
    if [ -f "$p" ]; then echo "  있다   $f ($(head -c 4 "$p"))"; else echo "  없다   $f"; fi
  done
  cmp /usr/local/amd64-sysroot/usr/share/zoneinfo/Asia/Seoul /usr/share/zoneinfo/Asia/Seoul && echo "sysroot == container"'
```

기대: 넷 다 "있다"이고 head가 `TZif`, `cmp`가 조용하다(결정 10의 "바이트까지
같다"를 실제로 본 것이다).

## Task 2 — initrd에 zoneinfo, 그리고 그것을 보는 호스트 검사

파일: `kernel/make_initrd.sh` · `net/check.sh`

- [ ] Step 1: `make_initrd.sh`의 로케일 블록 바로 앞에 이것을 넣는다

`# HI-M1: UTF-8 로케일.` 주석 블록 앞이다. 로케일과 같은 종류의 항목(glibc가
런타임에 읽는 데이터)이라 이웃으로 둔다.

```bash
# TS-M3 결정 8·10. 시간대 규칙 전체. tars.conf의 timezone=Asia/Seoul 같은
# 이름을 init이 TZ 환경변수로 넘기면 glibc가 이 트리에서 그 파일을 읽는다 —
# 로케일과 정확히 같은 종류의 항목이고, 없으면 date가 조용히 UTC를 찍는다.
#
# 통째로 넣는다. 도시 몇을 우리가 고르면 새 도시마다 다시 빌드해야 하고,
# 전체가 압축 171KB라 고를 이유가 없다(TS 확인 8 — dhcpcd 바이너리 하나의
# 절반이 안 된다). TZif 파일은 대부분이 0이라 잘 눌린다.
#
# cp -r은 링크를 링크로 복사한다. 이 트리의 링크 51개가 그대로 링크로
# 남아야 크기가 확인 8의 값이다.
#
# sysroot에서 온다(결정 10). 컨테이너 자신의 /usr/share/zoneinfo와 바이트까지
# 같지만 게스트 파일의 출처를 하나로 유지한다.
mkdir -p "$WORKDIR/usr/share"
cp -r "$SYSROOT/usr/share/zoneinfo" "$WORKDIR/usr/share/"
```

- [ ] Step 2: `net/check.sh`의 hook 호스트 검사 바로 뒤에 initrd 검사를 넣는다

`echo "the dhcpcd hook writes the first ntp server and nothing else"` 다음이고
`# NW-M2. 설정 디스크를 굽는다.` 앞이다. `tools/check.sh`의 검사 1과 같은
방법이다 — 목록을 변수에 한 번 담고 here-string으로 본다(파이프 뒤의
`grep -q`는 게이트의 진입 검사가 막는다).

```bash
# ── 호스트 검사: initrd에 zoneinfo가 들어갔는가 (TS-M3) ──────────────────
#
# 부팅보다 앞에 두는 이유는 진단이다. make_initrd.sh의 cp 한 줄이 빠지면
# 증상이 부팅 A의 검사 24(화면이 05/05UTC를 찍는다)에서 나오고, 그 자리에서는
# "파일이 없다"와 "init이 TZ를 안 넣었다"와 "glibc가 못 읽었다"가 안 갈린다.
# 여기서 죽으면 셋 중 첫째다.
#
# 검사 24가 치는 이름과 기본값의 이름 둘을 본다. 전체를 세는 것은 판정이
# 아니라 사람이 읽는 수다 — tzdata 판이 오르면 수가 바뀐다.
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
for want in "usr/share/zoneinfo/${TZ_NAME}" usr/share/zoneinfo/UTC; do
  if ! grep -qx "$want" <<< "$INITRD_LIST"; then
    echo "FAIL: ${want} is missing from the initrd"
    exit 1
  fi
done
ZONEINFO_COUNT="$(grep -c '^usr/share/zoneinfo/' <<< "$INITRD_LIST")"
echo "the initrd carries ${ZONEINFO_COUNT} zoneinfo entries, ${TZ_NAME} and UTC among them"
```

`$TZ_NAME`은 Task 5 Step 1이 파일 머리에 정한다. 이 Step만 먼저 넣고 체인을
돌리면 `set -u`가 죽이므로, Task 5까지 한 번에 가거나 임시로 값을 적어 둔다.

⚠ cpio 안의 이름이 `usr/...`인지 `./usr/...`인지는 `tools/check.sh:184` 주변
주석이 적어 두었다. 넣기 전에 그 열 줄을 읽고 같은 꼴을 쓴다.

- [ ] Step 3: initrd만 다시 굽고 크기 차이를 잰다 (약 30초)

```bash
cd /Users/dp/Repository/tars-linux
BEFORE=$(stat -f %z kernel/initrd.cpio)
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./make_initrd.sh' 2>&1 | tail -3
AFTER=$(stat -f %z kernel/initrd.cpio)
echo "before=${BEFORE} after=${AFTER} delta=$((AFTER-BEFORE))"
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | grep -c "^usr/share/zoneinfo/"
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | grep -E "zoneinfo/(Asia/Seoul|UTC)$"'
```

기대: delta가 171KB 안팎(확인 8의 174,898바이트는 `-9`였고 initrd는 `-6`이라
조금 더 클 수 있다). 항목 수가 파일 443 + 링크 51 + 디렉터리 수 안팎.
`init`이 아직 안 바뀌었으므로 `zig build`는 안 돌려도 된다 — 이 Step은
`make_initrd.sh`만 본다.

- [ ] Step 4: 더한 줄과 지운 줄을 센다

```bash
git diff --stat kernel/make_initrd.sh net/check.sh
git diff kernel/make_initrd.sh net/check.sh | grep '^-' | grep -v '^---' || echo "(지운 줄 없음)"
```

기대: 지운 줄 0.

## Task 3 — `tars.conf`의 아홉째 키 `timezone` (검사 먼저)

파일: `init/src/config_test.zig` · `init/src/config.zig`

- [ ] Step 1: `config_test.zig`의 `expect`에 필드 비교를 더한다 (RED의 절반)

`got.ntp.eql(want.ntp) and` 바로 아래에 한 줄이다.

```zig
        // TS-M3: 아홉째 필드. `Ntp`와 같이 `eql`이다 — 배열을 가진 struct라
        // `==`가 안 된다.
        got.timezone.eql(want.timezone) and
```

그리고 같은 함수의 `FAIL:` 출력에 `timezone={s}`를 두 줄(got · want)의 맨
뒤에 붙이고 인자 목록에 `got.timezone.slice()` · `want.timezone.slice()`를
각각 `ntp` 인자 다음에 더한다.

```zig
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s}\n",
```

- [ ] Step 2: `main`의 TS-M1 블록(`expectNtpRoundTrip` 넷) 바로 뒤에 검사 블록을 넣는다

```zig
    // ── TS-M3: 아홉째 키 ────────────────────────────────────────────────
    //
    // 둘째 자유 문자열 키다. `ntp`와 다른 것은 값을 해석하지 않는다는
    // 것이다(design 결정 8) — 파서가 하는 일은 담을 수 있는 모양인지 보는 것
    // 뿐이고, 그 이름이 무슨 뜻인지는 glibc가 안다.
    const seoul = config.Timezone.parse("Asia/Seoul") orelse return error.SeoulDidNotParse;
    try expect("timezone=Asia/Seoul\n", .{ .timezone = seoul });
    // 기본값을 적어도 기본값이다.
    try expect("timezone=UTC\n", .{});
    // IANA 이름에 나오는 글자들 — 밑줄 · 붙임표 · 더하기 · 세 단.
    try expect("timezone=America/Argentina/Buenos_Aires\n", .{
        .timezone = config.Timezone.parse("America/Argentina/Buenos_Aires") orelse return error.NameDidNotParse,
    });
    try expect("timezone=America/Port-au-Prince\n", .{
        .timezone = config.Timezone.parse("America/Port-au-Prince") orelse return error.NameDidNotParse,
    });
    try expect("timezone=Etc/GMT+9\n", .{
        .timezone = config.Timezone.parse("Etc/GMT+9") orelse return error.NameDidNotParse,
    });
    // 값의 양쪽 공백은 `parse`가 이미 뗐다.
    try expect("timezone = Asia/Seoul \n", .{ .timezone = seoul });
    // 거르는 것 넷(design 결정 8의 마지막 문단). 위협 모델이 있어서가 아니라
    // 경로를 조립하는 코드가 검증 없이 값을 먹는 것을 안 남기기 위해서다.
    try expect("timezone=\n", .{}); // 값 없음
    try expect("timezone=/etc/passwd\n", .{}); // 절대 경로
    try expect("timezone=../../etc/passwd\n", .{}); // 위로 올라감
    try expect("timezone=Asia/../Seoul\n", .{}); // 가운데서 올라감
    // 길이 경계 양쪽. 64는 담기고 65는 안 담긴다.
    try expect("timezone=" ++ ("a" ** 65) ++ "\n", .{});
    try expect("timezone=" ++ ("a" ** 64) ++ "\n", .{
        .timezone = config.Timezone.parse("a" ** 64) orelse return error.NameDidNotParse,
    });
    // 다른 키와 함께. 부팅 A의 디스크가 실제로 쓰는 세 줄이다.
    try expect("net=dhcp\nntp=10.0.2.2\ntimezone=Asia/Seoul\n", .{
        .net = .dhcp,
        .ntp = .{ .server = .{ 10, 0, 2, 2 } },
        .timezone = seoul,
    });

    // 왕복. `save`가 `slice()`로 쓰고 다음 부팅이 `parse`로 읽는다.
    const seoul_back = config.Timezone.parse(seoul.slice()) orelse return error.TimezoneRoundTripFailed;
    if (!seoul_back.eql(seoul)) {
        std.debug.print("FAIL: timezone round trip changed the value\n", .{});
        return error.TimezoneRoundTripChanged;
    }

    // 기본값이 UTC라는 것. 이 키를 안 적은 기계의 동작이 한 글자도 안 바뀌는
    // 근거가 이 세 글자다(design 확인 10).
    if (!std.mem.eql(u8, config.Timezone.UTC.slice(), "UTC")) {
        std.debug.print("FAIL: the default timezone is '{s}'\n", .{config.Timezone.UTC.slice()});
        return error.WrongDefaultTimezone;
    }

    // `main.zig`가 여는 경로. 순수한 조립이라 여기서 본다(결정 M3-C).
    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    const path = config.zoneinfoPath(&path_buf, seoul);
    if (!std.mem.eql(u8, path, "/usr/share/zoneinfo/Asia/Seoul")) {
        std.debug.print("FAIL: zoneinfo path is '{s}'\n", .{path});
        return error.WrongZoneinfoPath;
    }
    // 가장 긴 이름도 버퍼에 든다 — NUL 자리까지.
    const longest = config.Timezone.parse("a" ** config.TZ_NAME_MAX) orelse return error.NameDidNotParse;
    if (config.zoneinfoPath(&path_buf, longest).len != config.ZONEINFO_PATH_MAX - 1) {
        std.debug.print("FAIL: the longest name does not fill ZONEINFO_PATH_MAX - 1\n", .{});
        return error.WrongZoneinfoPath;
    }

    // 넉 자 대조(결정 M3-B). glibc의 tzfile.c가 보는 것과 같은 넉 자다.
    if (!config.looksLikeTzif("TZif2\x00\x00\x00")) {
        std.debug.print("FAIL: a TZif header was not recognized\n", .{});
        return error.TzifNotRecognized;
    }
    if (config.looksLikeTzif("TZi") or config.looksLikeTzif("") or
        config.looksLikeTzif("# tzdb timezone descriptions"))
    {
        std.debug.print("FAIL: something that is not a TZif file was accepted\n", .{});
        return error.TzifFalsePositive;
    }
```

- [ ] Step 3: 빨간불을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test 2>&1 | head -20'
```

기대: 컴파일 에러. `Config`에 `timezone`이 없고 `config.Timezone`도 없다.

- [ ] Step 4: `config.zig`의 `Ntp` 선언 바로 뒤(`NO_CONFIG_TOKEN` 앞)에 `Timezone`을 넣는다

```zig
/// `timezone` 값의 최대 길이(NUL 제외). IANA 이름 중 가장 긴 것이
/// `America/Argentina/ComodRivadavia` 32글자다. 두 배를 둔다.
pub const TZ_NAME_MAX = 64;

/// zoneinfo가 사는 자리. glibc의 `TZDIR` 기본값이고 Debian도 같다.
/// `kernel/make_initrd.sh`가 sysroot의 같은 경로를 통째로 복사한다 — 둘이
/// 어긋나면 증상은 "모든 시간대가 UTC"이고 원인에서 멀다.
pub const ZONEINFO_DIR = "/usr/share/zoneinfo/";

/// `zoneinfoPath`가 만드는 경로를 담을 버퍼의 크기. 디렉터리 + 가장 긴
/// 이름 + NUL.
pub const ZONEINFO_PATH_MAX = ZONEINFO_DIR.len + TZ_NAME_MAX + 1;

/// TZif 파일의 첫 넉 자. glibc의 `tzfile.c`가 같은 넉 자를 보고 파일을
/// 받거나 버린다. `main.zig`의 `resolveTimezone`이 파일을 열어 이만큼 읽고
/// `looksLikeTzif`에 넘긴다(TS-M3 plan 결정 M3-B).
pub const TZIF_MAGIC = "TZif";

/// 사람이 읽는 시각의 시간대(TS design 결정 8). 값을 해석하지 않는다 —
/// `Asia/Seoul`이 무슨 뜻인지는 glibc가 알고, 이 타입이 하는 일은 그 이름을
/// 힙 없이 담는 것과 담을 수 있는 모양인지 보는 것뿐이다.
///
/// 이 저장소의 둘째 자유 문자열 설정 값이다(첫째는 `ntp`의 주소). `Ntp`가
/// `[4]u8`을 갖는 것과 같은 모양이고 크기만 다르다 — `Config`가 값으로
/// 돌려지고 힙이 없으므로, `parse`가 받은 텍스트를 가리키는 슬라이스를
/// 담으면 `load`가 돌아오는 순간 댕글링이다(TS-M3 plan 결정 M3-A).
pub const Timezone = struct {
    name: [TZ_NAME_MAX]u8,
    len: usize,

    /// 기본값. 이 키를 안 적은 기계의 `date`가 지금과 한 글자도 안 달라지는
    /// 근거가 이 세 글자다 — 파일도 `TZ`도 없는 지금 glibc가 이미 UTC를
    /// 찍고, `TZ=UTC`는 파일 없이도 glibc가 이름만으로 안다.
    pub const UTC: Timezone = parse("UTC") orelse unreachable;

    /// 설정 파일의 값을 이 타입으로 바꾼다. 모르는 값이면 null이고,
    /// 호출자가 로그를 찍고 기본값에 머문다 — 다른 여덟 키와 같은 규칙이다.
    ///
    /// 거르는 것이 넷이다. 빈 값, `/`로 시작하는 것, `..`이 든 것, 버퍼보다
    /// 긴 것. 위협 모델이 있어서가 아니라 경로를 조립하는 코드가 검증 없이
    /// 값을 먹는 것을 이 저장소에 남기지 않기 위해서다(design 결정 8).
    /// 글자 화이트리스트는 안 둔다 — 파일이 정말 있는지는 `main.zig`가
    /// 열어서 보고, 그것이 진짜 판정이다.
    pub fn parse(value: []const u8) ?Timezone {
        if (value.len == 0 or value.len > TZ_NAME_MAX) return null;
        if (value[0] == '/') return null;
        if (std.mem.indexOf(u8, value, "..") != null) return null;
        var tz = Timezone{ .name = [_]u8{0} ** TZ_NAME_MAX, .len = value.len };
        @memcpy(tz.name[0..value.len], value);
        return tz;
    }

    /// 담긴 이름. 로그 · 씨앗 파일 · `TZ` 항목이 전부 이것을 쓴다.
    pub fn slice(self: *const Timezone) []const u8 {
        return self.name[0..self.len];
    }

    /// 두 값이 같은가. `config_test`의 필드 비교가 쓴다 — `Ntp.eql`과 같은
    /// 이유다.
    pub fn eql(self: Timezone, other: Timezone) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }
};

/// `/usr/share/zoneinfo/<이름>`을 NUL로 닫아 buf에 만든다. 시스템 콜이 없는
/// 순수 함수라 `config_test`가 본다 — 여는 것은 `main.zig`다(TS-M3 plan
/// 결정 M3-C).
///
/// `catch unreachable`인 이유는 길이가 구조로 보장되기 때문이다 —
/// `Timezone.parse`가 `TZ_NAME_MAX`를 넘는 이름을 안 만들고 버퍼가 그만큼
/// 크다. 그 관계가 깨지면 `config_test`의 "가장 긴 이름" 검사가 먼저 죽는다.
pub fn zoneinfoPath(buf: *[ZONEINFO_PATH_MAX]u8, tz: Timezone) [:0]const u8 {
    const text = std.fmt.bufPrint(buf, ZONEINFO_DIR ++ "{s}", .{tz.slice()}) catch unreachable;
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

/// 파일의 머리가 TZif인가. `main.zig`가 읽은 넉 자를 넘긴다.
pub fn looksLikeTzif(head: []const u8) bool {
    return head.len >= TZIF_MAGIC.len and
        std.mem.eql(u8, head[0..TZIF_MAGIC.len], TZIF_MAGIC);
}
```

- [ ] Step 5: `Config`에 필드를 더한다

`ntp: Ntp = .off,` 바로 아래다.

```zig
    /// 기본값이 `UTC`인 것은 "꺼짐"이 아니라 "지금과 같은 동작"이다(TS
    /// design 확인 10). zoneinfo가 없던 게스트가 이미 UTC를 찍고 있었고,
    /// 이 키를 안 적은 기계는 한 글자도 안 바뀐다. `net`·`ntp`와 달리 이
    /// 키는 켜는 비용이 없다 — 파일 하나를 읽는 것이 전부다.
    timezone: Timezone = Timezone.UTC,
```

- [ ] Step 6: `parse`에 분기를 더한다

`ntp` 분기 바로 뒤, `else` 앞이다.

```zig
        } else if (std.mem.eql(u8, key, "timezone")) {
            // 둘째 자유 문자열 키다. `ntp`와 다른 것은 값을 해석하지 않는다는
            // 것이다(design 결정 8) — 담을 수 있는 모양인지만 보고, 파일이
            // 정말 있는지는 `main.zig`가 본다. 모르는 값을 흘려보내는 규칙은
            // 같다.
            c.timezone = Timezone.parse(value) orelse {
                std.debug.print("tars-init: unknown timezone '{s}', falling back to {s}\n", .{
                    value, c.timezone.slice(),
                });
                continue;
            };
```

- [ ] Step 7: `save`가 아홉째 줄을 쓰게 한다

`ntp={s}` 다음에 이 넷을 더하고, 인자 목록의 `c.ntp.arg(&ntp_buf),` 뒤에
`c.timezone.slice(),`를 더한다.

```
        \\# timezone: UTC | <IANA 이름. 예: Asia/Seoul>
        \\#   /usr/share/zoneinfo 아래의 이름이다. 없는 이름이면 로그를 찍고
        \\#   UTC로 떨어진다. ntp가 시계를 맞추는 것과 별개다 — 이 값은
        \\#   그 시각을 어느 지역의 시각으로 보여 줄지만 정한다
        \\timezone={s}
```

- [ ] Step 8: 초록을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test 2>&1 | tail -12'
```

기대: config_test의 요약 줄이 나오고 빨간불이 없다.

- [ ] Step 9: 더한 줄과 지운 줄을 센다

```bash
git diff --stat init/src/config.zig init/src/config_test.zig
git diff init/src/config.zig init/src/config_test.zig | grep '^-' | grep -v '^---'
```

기대: 지운 줄이 `expect`의 `FAIL:` 형식 문자열 두 줄뿐이다(`timezone={s}`를
붙이느라 바뀐 것).

## Task 4 — `TZ` 항목과 그것을 넣는 `main.zig` (검사 먼저)

파일: `init/src/environ_test.zig` · `init/src/environ.zig` · `init/src/main.zig`

- [ ] Step 1: `environ_test.zig`를 새 모양에 맞춘다 (RED)

`withTarsEnv`가 인자를 하나 더 받으므로 호출 자리 여섯이 전부 바뀐다. 검사
1~4를 아래로 통째로 바꾸고 검사 7을 더한다. 검사 5 · 6과 헬퍼 셋은 그대로다.

```zig
pub fn main() !void {
    var buf: environ.Block = undefined;
    var tz_buf: [environ.TZ_ENTRY_MAX]u8 = undefined;
    const tz = environ.tzEntry(&tz_buf, "Asia/Seoul");

    // ── 1. 정상 경로(zsh): 커널의 둘 뒤에 우리 것 여섯이 순서대로 붙는다 ──
    //
    // 이것이 이 파일의 심장이다. 순서까지 보는 이유는 덮어쓰는 구현
    // (buf[0]에 PATH를 넣고 나머지를 미는 것)도 개수 검사만으로는 통과하기
    // 때문이다.
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.zsh.histEntries());

        if (count(got) != 8) {
            std.debug.print("FAIL: want 8 entries for zsh, got {d}\n", .{count(got)});
            return error.WrongCount;
        }
        if (!entryIs(got, 0, "HOME=/") or !entryIs(got, 1, "TERM=linux")) {
            std.debug.print("FAIL: the kernel's own entries did not survive in order\n", .{});
            return error.LostKernelEntries;
        }
        // 셸과 무관한 셋이 먼저다. TS-M3이 TZ를 XDG 뒤 · 히스토리 앞에
        // 넣었다 — "셸마다 갈리는 것"은 맨 뒤라는 규칙을 지키기 위해서다.
        if (!entryIs(got, 2, "PATH=/usr/bin:/bin") or
            !entryIs(got, 3, "XDG_DATA_HOME=/config/xdg") or
            !entryIs(got, 4, "TZ=Asia/Seoul"))
        {
            std.debug.print("FAIL: PATH, XDG_DATA_HOME and TZ are not the first three we add\n", .{});
            return error.NoPath;
        }
        // 히스토리 셋이 그 뒤에 순서대로 온다. zsh만 SAVEHIST를 받고,
        // 그것이 없으면 zsh는 HISTFILE이 있어도 한 줄도 안 쓴다(실측 9).
        if (!entryIs(got, 5, "HISTFILE=/config/zsh_history") or
            !entryIs(got, 6, "HISTSIZE=5000") or
            !entryIs(got, 7, "SAVEHIST=5000"))
        {
            std.debug.print("FAIL: the zsh history entries are not appended in order\n", .{});
            return error.NoHistory;
        }
    }

    // ── 2. fish: 히스토리 env가 하나도 없다 ─────────────────────────
    //
    // 대조군이자 결정 3의 절반이다. fish의 히스토리는 XDG_DATA_HOME 아래로
    // 통째로 따라오므로(실측 11·40) 줄 하나도 필요 없고, 줄 수를 정하는
    // 변수도 없다(비목표 4).
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.fish.histEntries());
        if (count(got) != 5 or !entryIs(got, 4, "TZ=Asia/Seoul")) {
            std.debug.print("FAIL: fish should get exactly PATH, XDG_DATA_HOME and TZ, got {d} entries\n", .{count(got)});
            return error.FishBlockWrong;
        }
    }

    // ── 3. 대조군: 커널이 아무것도 안 줬다 ─────────────────────────────
    //
    // 커널은 늘 둘을 주지만, 그 사실에 기대는 구현(예: 무조건 buf[2]에 쓰는
    // 것)을 여기서 잡는다.
    {
        const kernel = kernelBlock(&.{});
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.fish.histEntries());
        if (count(got) != 3 or !entryIs(got, 0, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: an empty kernel block did not yield exactly our three\n", .{});
            return error.EmptyBlockWrong;
        }
    }

    // ── 4. 넘침 — 경계 양쪽을 본다 ─────────────────────────────────
    //
    // PATH가 없는 것이 부팅이 안 되는 것보다 낫다. 버퍼를 넘겨 쓰면 PID 1이
    // 스택을 밟고 기계가 아예 안 켜진다 — 증상이 원인에서 가장 먼 종류다.
    //
    // 경계가 M2에서 한 번(하나 → 다섯), TS-M3에서 또 한 번(다섯 → 여섯)
    // 움직였다. 그래서 "넘치면 통과시킨다"만 보지 않고 바로 아래는 여전히
    // 붙는다도 본다 — 한쪽만 보면 `return kernel`을 맨 위로 올린 구현도
    // 초록이다.
    {
        var many: [environ.MAX_ENTRIES]([:0]const u8) = undefined;
        for (&many) |*m| m.* = "X=1";
        const hist = config.Shell.zsh.histEntries(); // 셋 → added = 6

        // n + 6 == MAX_ENTRIES → 닫는 null 자리가 없다. 그대로 돌려준다.
        const over = kernelBlock(many[0 .. environ.MAX_ENTRIES - 6]);
        if (environ.withTarsEnv(over, &buf, tz, hist) != over) {
            std.debug.print("FAIL: an oversized block should have been passed through untouched\n", .{});
            return error.OverflowNotPassedThrough;
        }

        // 한 칸 적으면 딱 들어간다.
        const fits = kernelBlock(many[0 .. environ.MAX_ENTRIES - 7]);
        const got = environ.withTarsEnv(fits, &buf, tz, hist);
        if (got == fits or count(got) != environ.MAX_ENTRIES - 1) {
            std.debug.print("FAIL: a block that fits was passed through instead of extended\n", .{});
            return error.FitNotExtended;
        }
    }
```

검사 6 뒤, 마지막 `std.debug.print` 앞에 검사 7을 더한다.

```zig
    // ── 7. TZ 항목 — 이름이 그대로 붙고, 안 들어가면 UTC다 ──────────────
    //
    // `tzEntry`가 이 파일에서 유일하게 글자를 만드는 함수다(나머지는 포인터를
    // 옮긴다). 넘칠 때 `TZ=UTC`로 떨어지는 것이 부팅을 안 막는 쪽이다 —
    // 이름이 64를 넘는 일은 `config.Timezone.parse`가 먼저 막지만, 이 파일은
    // 그 파일을 모르므로 자기 경계를 자기가 지킨다.
    {
        var b: [environ.TZ_ENTRY_MAX]u8 = undefined;
        if (!std.mem.eql(u8, environ.tzEntry(&b, "Asia/Seoul"), "TZ=Asia/Seoul")) {
            std.debug.print("FAIL: tzEntry gave '{s}'\n", .{environ.tzEntry(&b, "Asia/Seoul")});
            return error.WrongTzEntry;
        }
        // 접두사 셋 + 이름 + NUL이 딱 맞는 길이는 들어간다.
        const fits_name = "a" ** (environ.TZ_ENTRY_MAX - environ.TZ_PREFIX.len - 1);
        if (environ.tzEntry(&b, fits_name).len != environ.TZ_ENTRY_MAX - 1) {
            std.debug.print("FAIL: a name that just fits was not kept\n", .{});
            return error.WrongTzEntry;
        }
        // 한 글자 더 길면 NUL 자리가 없다. UTC로 떨어진다.
        const over_name = "a" ** (environ.TZ_ENTRY_MAX - environ.TZ_PREFIX.len);
        if (!std.mem.eql(u8, environ.tzEntry(&b, over_name), "TZ=UTC")) {
            std.debug.print("FAIL: an oversized name did not fall back to TZ=UTC\n", .{});
            return error.WrongTzEntry;
        }
    }
```

마지막 요약 줄도 넓힌다.

```zig
    std.debug.print("environ_test: PATH, XDG_DATA_HOME, TZ and the shell's history env are appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
```

- [ ] Step 2: 빨간불을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test 2>&1 | head -12'
```

기대: 컴파일 에러 — `environ.TZ_ENTRY_MAX`와 `tzEntry`가 없고 `withTarsEnv`의
인자 수가 다르다.

- [ ] Step 3: `environ.zig`에 상수 셋과 `tzEntry`를 넣고 `withTarsEnv`를 넓힌다

`MAX_ENTRIES` 선언 바로 앞에 이것을 넣는다.

```zig
/// `TZ` 항목의 접두사(TS design 결정 9). 이름은 `config.Timezone`이 갖고
/// 있는데 이 파일은 그 파일을 모른 채 있어야 하므로, `main.zig`가 이름을
/// 넘기고 이 파일이 접두사를 붙인다(TS-M3 plan 결정 M3-D).
pub const TZ_PREFIX = "TZ=";

/// `tzEntry`가 만드는 항목을 담을 버퍼의 크기. `config.TZ_NAME_MAX`(64)에
/// 접두사 셋과 NUL 하나를 더한 68이 들어가고 남는다 — 그 관계를 못 박는
/// comptime 검사가 둘을 다 아는 `main.zig`에 있다.
pub const TZ_ENTRY_MAX: usize = 80;

/// 이름이 안 들어갈 때 쓰는 항목. UTC는 파일이 없어도 glibc가 이름만으로
/// 아는 값이라 이것으로 떨어지면 `date`가 지금과 같은 것을 찍는다.
pub const TZ_UTC_ENTRY: [:0]const u8 = "TZ=UTC";

/// `TZ=<name>`을 NUL로 닫아 buf에 만든다. 이 파일에서 유일하게 글자를
/// 만드는 함수다 — 나머지는 포인터를 옮길 뿐이다.
///
/// 안 들어가면 `TZ_UTC_ENTRY`다. 잘라서 넣는 것보다 낫다 — `TZ=Asia/Seo`는
/// glibc가 파일을 못 찾고 이름이 `Asia/Seo`인 UTC를 만드는데, 그러면 로그
/// 없이 틀린다.
pub fn tzEntry(buf: *[TZ_ENTRY_MAX]u8, name: []const u8) [:0]const u8 {
    const text = std.fmt.bufPrint(buf, TZ_PREFIX ++ "{s}", .{name}) catch return TZ_UTC_ENTRY;
    if (text.len >= buf.len) return TZ_UTC_ENTRY; // NUL 자리가 없다
    buf[text.len] = 0;
    return buf[0..text.len :0];
}
```

`withTarsEnv`를 이렇게 바꾼다. 문서 주석의 표와 본문을 넷으로 넓히고, 인자
`tz`가 `hist` 앞에 온다.

```zig
/// 커널이 준 블록을 buf에 복사하고 우리 것을 뒤에 붙인 뒤 buf를 돌려준다.
///
/// 붙이는 것이 넷이다.
///
///   PATH             자식마다 갈릴 이유가 없다(UT-M0)
///   XDG_DATA_HOME    같다. 배운 것 둘이 여기로 간다(SM-M2 결정 2)
///   TZ               같다. 시간대는 기계의 것이지 셸의 것이 아니다(TS-M3)
///   hist             셸마다 갈린다 — `config.Shell.histEntries()`가 준다
///
/// 셋째와 넷째가 인자인 것이 이 함수의 전부다. 이 파일은 `config.zig`를
/// 모른 채 있어야 하고(그래야 호스트 검사가 순수 계산으로 남는다), 그래서
/// "어느 셸인가 · 어느 시간대인가" 대신 "무엇을 붙일까"를 받는다. 부르는
/// 쪽은 `main.zig` 하나다.
///
/// 순서에 뜻이 있다. 셸과 무관한 셋이 앞이고 셸마다 갈리는 것이 맨 뒤다 —
/// TS-M3이 TZ를 XDG 뒤에 넣은 이유다.
///
/// 자리가 모자라면 커널 블록을 그대로 돌려준다. PATH가 없는 게스트는
/// 불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다.
/// HD 결정 6("못 찾아도 부팅을 막지 않는다")과 같은 종류의 선택이다.
pub fn withTarsEnv(
    kernel: [*:null]const ?[*:0]const u8,
    buf: *Block,
    tz: [:0]const u8,
    hist: []const [:0]const u8,
) [*:null]const ?[*:0]const u8 {
    var n: usize = 0;
    while (kernel[n] != null) n += 1;

    // 우리가 더하는 수. 셸마다 3(fish) · 5(bash) · 6(zsh)다.
    const added = 3 + hist.len;
    // 마지막으로 쓰는 자리가 buf[n + added](닫는 null)이고, 그 자리가 배열의
    // sentinel 자리(MAX_ENTRIES)를 넘으면 안 된다.
    if (n + added >= MAX_ENTRIES) return kernel;

    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = kernel[i];
    buf[n] = PATH_ENTRY.ptr;
    buf[n + 1] = XDG_ENTRY.ptr;
    buf[n + 2] = tz.ptr;
    for (hist, 0..) |entry, j| buf[n + 3 + j] = entry.ptr;
    buf[n + added] = null;
    return buf;
}
```

파일 머리 주석의 "시스템 콜을 하나도 안 한다" 문장은 그대로 참이다.

- [ ] Step 4: `environ_test`만 초록인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test 2>&1 | tail -12'
```

기대: `environ_test`의 요약 줄이 나온다. `zig build`(init 바이너리)는 아직
빨갛다 — `main.zig`가 옛 인자 수로 부르고 있다. `zig build test`는
`main.zig`를 안 컴파일하므로 여기서는 안 걸린다.

- [ ] Step 5: `main.zig`에 `resolveTimezone`을 넣는다

`resolveShell` 바로 뒤, `logDrmDevicePresence` 앞이다.

```zig
/// 설정이 고른 시간대의 zoneinfo 파일이 정말 있는지 확인하고, 없으면 UTC로
/// 내려온다. `resolveShell`과 같은 자리의 같은 선택이다 — 이름은
/// `config.Timezone.parse`가 모양만 보고 받아 주지만, initrd에 그 파일이 없는
/// 이름은 모양이 맞아도 glibc가 못 읽는다.
///
/// 존재가 아니라 첫 넉 자를 본다(TS-M3 plan 결정 M3-B). `access`로 존재만
/// 보면 디렉터리(`timezone=Asia`)와 같은 자리에 사는 텍스트 파일
/// (`timezone=zone.tab`)이 새고, 그때 glibc는 POSIX 문자열로 다시 해석하다
/// 실패해서 이름만 그 글자인 UTC를 만든다 — 로그 없이 틀리는 종류다. 넉 자
/// `TZif`는 glibc의 tzfile.c가 파일을 받는 첫 기준이라, 우리가 같은 넉 자를
/// 보면 glibc가 물을 질문을 미리 묻는 셈이다.
///
/// UTC는 안 본다. glibc가 파일 없이도 이름만으로 아는 값이고, 그래서
/// zoneinfo가 통째로 없는 initrd에서도 기본값은 로그를 안 찍는다.
fn resolveTimezone(want: config.Timezone) config.Timezone {
    if (want.eql(config.Timezone.UTC)) return want;

    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    const path = config.zoneinfoPath(&path_buf, want);
    if (zoneinfoIsTzif(path)) return want;

    std.debug.print("tars-init: timezone {s} has no zoneinfo file at {s}, falling back to {s}\n", .{
        want.slice(), path, config.Timezone.UTC.slice(),
    });
    return config.Timezone.UTC;
}

/// path를 열어 첫 넉 자가 TZif인지 본다. 못 열거나 못 읽거나 넉 자가 다르면
/// 전부 거짓이다 — 셋을 안 가르는 이유는 처방이 같기 때문이다(UTC로 간다).
fn zoneinfoIsTzif(path: [:0]const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var head: [config.TZIF_MAGIC.len]u8 = undefined;
    const n = linux.read(fd, &head, head.len);
    if (failed(n)) |_| return false;
    return config.looksLikeTzif(head[0..n]);
}
```

- [ ] Step 6: `main.zig`의 설정 로그 줄을 넓힌다

`tars-init: config shell=...` 줄의 맨 뒤에 `timezone={s}`를 붙이고 인자
목록의 `cfg.ntp.arg(&ntp_buf),` 뒤에 `cfg.timezone.slice(),`를 더한다. 맨
뒤여야 하는 이유는 그 위 주석(TS-M1이 적었다)과 같다 — 체인 열 자리가 이
줄의 앞부분을 grep한다.

```zig
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s} timezone={s}\n",
        .{
            @tagName(cfg.shell),
            @tagName(cfg.keyboard),
            @tagName(cfg.hangul_layout),
            @tagName(cfg.latin_layout),
            toggle_arg,
            @tagName(cfg.shell_config),
            @tagName(cfg.net),
            cfg.ntp.arg(&ntp_buf),
            cfg.timezone.slice(),
        },
    );
```

- [ ] Step 7: env 블록을 짓는 자리를 넓힌다

`const shell_path = shell.path();` 바로 뒤에 시간대를 정하고, `withTarsEnv`
호출에 넘기고, 로그 줄을 넓힌다.

```zig
    // TS-M3. `resolveShell`과 같은 자리의 같은 선택이다 — 설정이 고른 이름의
    // 파일이 initrd에 정말 있는지 보고, 없으면 UTC다. 이 값이 env 블록에
    // 들어가면 게스트의 모든 프로세스가 물려받는다(design 결정 9) — 셸도
    // `date`도 같은 것을 본다.
    const tz = resolveTimezone(cfg.timezone);
    // 이 버퍼도 `main()`의 스택에 산다. 아래 env_buf가 이 안의 포인터를 담고
    // `supervise()`가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다.
    var tz_buf: [environ.TZ_ENTRY_MAX]u8 = undefined;
    const tz_entry = environ.tzEntry(&tz_buf, tz.slice());
```

```zig
    var env_buf: environ.Block = undefined;
    const envp = environ.withTarsEnv(
        init.environ.block.slice.ptr,
        &env_buf,
        tz_entry,
        shell.histEntries(),
    );
```

로그 줄은 `tools/check.sh:233`이 `tars-init: env PATH=/usr/bin:/bin`을 grep
하므로 앞을 안 바꾸고 뒤에 붙인다. `net/check.sh`의 검사 23이 이 줄 전체를
본다.

```zig
    if (envp != init.environ.block.slice.ptr) {
        std.debug.print("tars-init: env {s} {s} {s}\n", .{
            environ.PATH_ENTRY, environ.XDG_ENTRY, tz_entry,
        });
```

그 위 주석 "withTarsEnv가 자리 부족으로 폴백했으면 이 줄들이 안 나온다"는
그대로 참이다.

- [ ] Step 8: 파일 맨 아래에 comptime 검사를 넣는다

`environ.zig`와 `config.zig`를 둘 다 아는 유일한 파일이 여기다.

```zig
// TS-M3 plan 결정 M3-D. `environ.zig`는 `config.zig`를 모르므로 `TZ` 버퍼의
// 크기를 자기 수(80)로 적었다. 그 수가 가장 긴 이름 + 접두사 + NUL을 담는지는
// 둘을 다 아는 이 파일이 못 박는다 — 어느 쪽 상수를 바꾸든 여기서 걸린다.
comptime {
    if (environ.TZ_PREFIX.len + config.TZ_NAME_MAX + 1 > environ.TZ_ENTRY_MAX)
        @compileError("environ.TZ_ENTRY_MAX cannot hold the longest timezone name");
}
```

- [ ] Step 9: 빌드와 호스트 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test 2>&1 | tail -12'
```

기대: 둘 다 초록.

- [ ] Step 10: 더한 줄과 지운 줄을 센다

```bash
git diff --stat init/src/environ.zig init/src/environ_test.zig init/src/main.zig
git diff init/src/environ.zig init/src/main.zig | grep '^-' | grep -v '^---'
```

기대: `environ.zig`의 지운 줄이 문서 주석 몇 줄과 `const added = 2 + ...` ·
`for (hist, 0..) |entry, j| buf[n + 2 + j]` 둘, `main.zig`의 지운 줄이 설정
로그 형식 문자열 하나와 `tars-init: env {s} {s}` 줄 하나다. 그 밖의 `-`가
있으면 읽고 이유를 안다. `environ_test.zig`는 검사 1~4를 통째로 바꿨으므로
지운 줄이 많은 것이 맞다 — 헬퍼 셋과 검사 5 · 6이 안 지워졌는지만 본다.

## Task 5 — 부팅 A의 디스크와 검사 23·24

파일: `net/make_disk.sh` · `net/check.sh`

- [ ] Step 1: `net/check.sh`의 TS-M1 블록 끝(`STUB_YEAR=2031` 뒤)에 상수를 더한다

```bash
# TS-M3. 부팅 A의 디스크가 적는 시간대와, 그 시간대에서 stub의 시각이
# 어떻게 보이는가. 1930367167 = 2031-03-04T05:06:07Z이고 서울은 UTC+9라
# 14:06:07이다. 서머타임이 없어서 연중 어느 날 돌려도 아홉 시간이다.
#
# 시(hour)만 보는 이유는 분·초가 타이핑 사이에 흐르기 때문이다. 시계를 뛴
# 직후에 치므로 시가 바뀌기까지 53분이 남고, 검사 19까지의 타이핑이 그 안에
# 끝난다.
#
# 약어 KST가 값을 하나 더 낸다 — 약어는 zoneinfo 파일에만 있어서, 파일을
# 못 읽고 UTC로 떨어진 게스트는 14도 KST도 못 찍는다(05/05UTC가 된다).
TZ_NAME=Asia/Seoul
TZ_ABBR=KST
STUB_HOUR_UTC=05
STUB_HOUR_LOCAL=14
```

- [ ] Step 2: `make_disk.sh`가 둘째 인자로 시간대를 받아 부팅 A의 디스크에 적는다

`NTP_SERVER="${1:-10.0.2.2}"` 아래에 이것을 더한다.

```bash
# TS-M3. 부팅 A가 쓰는 시간대. 첫째 인자와 같은 이유로 체인이 넘긴다 —
# 이 이름을 아는 자리가 net/check.sh 한 곳이어야 검사 24의 기대값과 안
# 어긋난다.
TZ_NAME="${2:-Asia/Seoul}"
```

부팅 A의 `bake`를 세 줄로 넓힌다. 주석도 함께 고친다.

```bash
# TS-M1. 부팅 A가 쓰는 디스크. 위의 것과 다른 것이 ntp 한 줄이었고 TS-M3이
# timezone 한 줄을 더했다 — 시계를 뛰는 부팅에서 그 시각을 사람이 읽는
# 모양으로 보는 것까지가 한 부팅의 일이다.
#
# 라벨을 tars-ntp로 다르게 두는 이유는 진단이다. 두 디스크가 같은 라벨이면
# 엉뚱한 이미지를 물린 회차에 게스트 로그가 똑같이 생긴다.
bake ../out/net-ntp.img tars-ntp "net=dhcp
ntp=${NTP_SERVER}
timezone=${TZ_NAME}
"
```

`net.img`와 `net-ntp-dhcp.img`는 안 건드린다. 검사 1~16과 부팅 B는 기본값
(UTC)으로 돌아야 "이 키를 안 적은 기계"가 게이트 안에 남는다.

- [ ] Step 3: `net/check.sh`의 `make_disk.sh` 호출에 인자를 넘긴다

```bash
if ! ./make_disk.sh "$NTP_SERVER" "$TZ_NAME"; then
```

주석 "TS-M1이 인자를 하나 더했다" 뒤에 한 줄을 더한다.

```bash
# TS-M3이 둘째 인자(시간대)를 더했다. 부팅 A의 디스크에만 들어간다.
```

- [ ] Step 4: 검사 17의 grep을 넓힌다

설정 로그 줄의 맨 뒤가 `timezone=`이 됐으므로 검사 17이 그것까지 본다. 안
넓히면 디스크에 `timezone=` 줄이 빠져도 초록이다.

```bash
if ! grep -aE "tars-init: config shell=.* net=dhcp ntp=${NTP_SERVER} timezone=${TZ_NAME}" "$LOGA" >/dev/null; then
  fail "the ntp config disk did not reach init" "tars-init: config shell="
fi
echo "the guest read ntp=${NTP_SERVER} and timezone=${TZ_NAME} off the config disk"
```

- [ ] Step 5: 검사 19 뒤 · "부팅 A를 끈다" 앞에 검사 23 · 24를 넣는다

```bash
# ── 검사 23: init이 TZ를 env 블록에 넣었나 (TS-M3) ────────────────────
# 번호가 자리와 어긋난다 — 20~22는 부팅 B이고 M2가 먼저 매겼다. 번호는
# 자리가 아니라 이름이라 다시 안 매긴다(TS-M3 plan 결정 M3-F).
#
# 검사 24와 같은 사실을 우리 코드의 입으로 먼저 듣는다. 이것이 초록이고
# 24가 빨강이면 원인이 우리 코드 밖(zoneinfo 파일 · glibc)이고, 이것부터
# 빨강이면 resolveTimezone이 UTC로 떨어진 것이다 — 그때 로그에
# `tars-init: timezone ... has no zoneinfo file` 한 줄이 있다.
if ! grep -a "tars-init: env PATH=/usr/bin:/bin XDG_DATA_HOME=/config/xdg TZ=${TZ_NAME}" "$LOGA" >/dev/null; then
  fail "init did not put TZ=${TZ_NAME} in the env block" \
    "tars-init: env" "tars-init: timezone"
fi
echo "init put TZ=${TZ_NAME} in the env block"

# ── 검사 24: 사람이 그것을 읽나 ───────────────────────────────────────
# design의 문장 그대로다 — 같은 순간의 `date -u`와 `date`가 정해진 만큼
# 벌어진다. 한 줄에 둘을 치고 시(hour) 둘과 약어를 한 단어로 찍는다.
#
# 판정 글자가 명령줄에 없어야 한다(검사 19와 같다). 친 줄에는 `tsz=$(date`가
# 남고 `tsz=05`는 출력에만 생긴다.
#
# 키 이름 중 slash와 shift-z가 이 저장소에서 처음 쓰인다. 나머지는 검사
# 19가 이미 친 것들이다.
echo "=== typing 'echo tsz=\$(date -u +%H)/\$(date +%H%Z)' ==="
type_keys e c h o spc t s z equal \
  shift-4 shift-9 d a t e spc minus u spc shift-equal shift-5 shift-h shift-0 \
  slash \
  shift-4 shift-9 d a t e spc shift-equal shift-5 shift-h shift-5 shift-z shift-0 ret

if ! wait_for_screen "tsz=${STUB_HOUR_UTC}/${STUB_HOUR_LOCAL}${TZ_ABBR}"; then
  fail "the guest does not show ${STUB_HOUR_UTC}Z as ${STUB_HOUR_LOCAL}${TZ_ABBR} on screen" \
    "terminal: screen>" "tars-init: timezone"
fi
echo "the guest shows ${STUB_HOUR_UTC}Z as ${STUB_HOUR_LOCAL}${TZ_ABBR} — nine hours, read off zoneinfo"
```

- [ ] Step 6: 체인 머리의 설명 주석을 넓힌다

TS-M2 문단 뒤, "이 체인은 check.sh의 CHAINS에 열두번째로" 앞에 넣는다.

```bash
#
# TS-M3이 부팅 A에 검사 둘을 더했다. 시계가 맞는 것과 사람이 그것을 자기
# 시간대로 읽는 것은 다른 사실이다:
#
#   설정 디스크의 timezone=Asia/Seoul → init이 zoneinfo 파일의 머리를 보고
#   → TZ=Asia/Seoul을 env 블록에 넣는다 → date가 05Z를 14KST로 찍는다
#
# 우리 코드는 이름을 읽고 파일을 한 번 열어 보는 것뿐이고, 아홉 시간은
# glibc가 zoneinfo에서 읽는다. 그 파일이 initrd에 있는지는 빌드 절의 호스트
# 검사가 부팅 전에 본다.
```

- [ ] Step 7: 문법을 본다

```bash
bash -n net/check.sh && bash -n net/make_disk.sh && bash -n kernel/make_initrd.sh && echo ok
```

## Task 6 — 체인을 돌리고 반사실을 본다

- [ ] Step 1: `net` 체인을 돌린다 (약 1분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } > /tmp/tsm3/net.log 2>&1; echo "exit=$?"
grep -E "^(PASS|FAIL|the |init |with |nothing )|real" /tmp/tsm3/net.log | tail -30
```

기대: `PASS`. 새 줄 넷 — `the initrd carries N zoneinfo entries` ·
`the guest read ntp=10.0.2.2 and timezone=Asia/Seoul` · `init put TZ=Asia/Seoul` ·
`the guest shows 05Z as 14KST`.

- [ ] Step 2: 첫 회가 깨졌으면 이 순서로 가른다

1. 호스트 검사에서 죽었다 → `make_initrd.sh`의 cp 줄 또는 cpio 이름 꼴
   (`./` 접두사)이다. Task 2 Step 2의 ⚠을 다시 본다.
2. 검사 17에서 죽었다 → 디스크에 줄이 안 들어갔거나 로그 줄의 모양이
   다르다. `grep -a "config shell=" /tmp/tsm3/net.log`로 실제 줄을 본다.
3. 검사 23에서 죽었다 → `grep -a "tars-init: timezone" /tmp/tsm3/net.log`.
   그 줄이 있으면 `resolveTimezone`이 UTC로 떨어진 것이고 경로가 그 줄에
   있다. 없으면 env 줄의 모양이 다르다.
4. 검사 24에서 죽었다 → `fail`이 찍은 마지막 화면을 본다. `05/05UTC`면
   glibc가 파일을 못 읽은 것이고(TZ는 들어갔다), `05/14KST`가 있는데 죽었으면
   `wait_for_screen`의 15초를 넘긴 것이다.

- [ ] Step 3: 게스트 로그에서 새 줄 둘을 눈으로 본다

```bash
grep -aE "tars-init: (config shell=|env |timezone)" /tmp/tsm3/net.log | head -6
```

기대: 부팅 셋의 `config shell=` 줄이 각각 `timezone=UTC` · `timezone=Asia/Seoul` ·
`timezone=UTC`로 끝나고, `env` 줄이 `TZ=UTC` · `TZ=Asia/Seoul` · `TZ=UTC`다.
`tars-init: timezone ... has no zoneinfo` 줄은 하나도 없다.

- [ ] Step 4: 반사실 — zoneinfo를 안 넣은 initrd는 호스트 검사에서 죽는가

`make_initrd.sh`의 cp 한 줄을 뺀 사본으로 체인을 돌린다. 저장소 파일은
안 건드린다 — `-v`로 덮어 씌운다.

```bash
grep -Fv 'cp -r "$SYSROOT/usr/share/zoneinfo" "$WORKDIR/usr/share/"' kernel/make_initrd.sh \
  > /tmp/tsm3/make_initrd.sh
chmod +x /tmp/tsm3/make_initrd.sh
docker run --rm -v "$PWD":/workspace \
  -v /tmp/tsm3/make_initrd.sh:/workspace/kernel/make_initrd.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh > /tmp/tsm3/cf.log 2>&1; echo "exit=$?"
grep -E "^FAIL|zoneinfo" /tmp/tsm3/cf.log | head
```

기대: `exit=1`이고 `FAIL: usr/share/zoneinfo/Asia/Seoul is missing from the initrd`.
부팅 전에 죽는다 — 겨냥한 자리다.

- [ ] Step 5: 반사실 뒤에 initrd를 원래대로 다시 굽는다

반사실이 `kernel/initrd.cpio`를 zoneinfo 없이 덮어썼다. 그대로 두면 다음
체인이 그 파일로 뜬다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd kernel && ./make_initrd.sh' 2>&1 | tail -2
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | grep -c "^usr/share/zoneinfo/"'
git status --short
```

기대: 수가 Task 2 Step 3과 같고 `git status`에 `/tmp` 사본의 흔적이 없다.

## Task 7 — 값을 재고 문서를 고친다

- [ ] Step 1: `net` 체인 단독 시간과 initrd 크기를 다시 잰다

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } 2>&1 | tail -4
ls -l kernel/initrd.cpio
```

Task 0 Step 3과 비교한다. 예상은 타이핑 약 40키(약 2~4초)와 호스트 검사의
cpio 목록 한 번(약 1초)이다. initrd 증가분은 Task 2 Step 3의 값이다.

- [ ] Step 2: 루트 게이트를 한 판 돌린다 (약 33분, background로)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

Bash 도구의 10분 한도를 넘으므로 `run_in_background`로 돌린다. 기대: 열두
체인 3/3, `skipping make` 35회, 33분 안팎.

이 판이 보는 것이 하나 더 있다 — `TZ=UTC`가 열한 체인의 블록에 새로 들어갔다.
그 체인들의 화면 좌표와 `tars-init: env PATH=` grep(`tools`)이 안 흔들리는지를
이 판이 본다.

- [ ] Step 3: design에 "TS-M3이 실행으로 증명한 것" 절을 더한다

실측 25부터 이어서 번호를 매긴다. 최소한 이 여섯이다.

1. sysroot의 zoneinfo가 컨테이너의 것과 바이트까지 같은가(Task 1 Step 4의 `cmp`)
2. initrd 증가분(확인 8의 171KB와 비교)과 항목 수
3. `TZif` 넉 자 확인이 실제로 도는가 — 부팅 A의 로그에 UTC 폴백 줄이 없고
   화면에 `KST`가 찍혔다는 것이 그 증명이다
4. 검사 24의 실제 화면 줄
5. 반사실이 겨냥한 자리에서 죽었는가
6. 체인 단독 시간 · initrd 크기 · 게이트 시간

그리고 세 자리를 고친다 — `Status:` 줄을 "닫혔다(2026-09-19)"로, "TS-M3 —
사람이 읽는 시각이 된다" 제목에 "(끝났다)"와 plan이 더한 결정 여섯의 요약을,
위험 6을 "M3이 쳤다"로.

- [ ] Step 4: `CLAUDE.md`의 완료 표에 TS 줄을 더한다

IN 줄 아래다.

```
| Time Sync (TS-M0~M3) | 2026-09-19 | 부팅에 SNTP로 한 번 묻고 시계를 뛴다. 상대는 설정의 주소든 DHCP가 알려 준 것이든 되고, `timezone=Asia/Seoul`이 그 시각을 사람이 읽는 모양으로 만든다. 네트워크가 없어도 부팅은 평소대로 끝난다 — `net/check.sh`가 검사 스물넷에 부팅 셋 |
```

- [ ] Step 5: `HANDOFF.md`를 고친다

- 맨 위 제목과 "지금 어디인가"를 "TS가 닫혔다"로
- TS 커밋 표에 M3 줄 둘(plan · 구현)
- "TS-M3이 알아낸 것 — 다음 세션이 먼저 읽을 것들"
- "바로 다음에 할 것"을 TS 뒤의 후보(패키지 매니저 · 실머신 NIC · IN이 미룬
  넷)를 사용자가 고르는 것으로
- 게이트 현황의 숫자와 `net` 체인 단독 시간 · initrd 크기
- 명령 모음에 반사실 한 덩이(Task 6 Step 4)와 이미지 재빌드 한 줄

- [ ] Step 6: 커밋

```bash
git status --short
```

`M`과 신규를 가른다. 신규가 plan 파일 하나뿐이어야 한다. `out/*.img`와
`kernel/initrd.cpio`는 `.gitignore`에 있다.

커밋을 셋으로 나눈다 — plan 하나(이 파일, Task 0 전에), 구현 하나, 문서(design ·
CLAUDE.md · HANDOFF) 하나. 구현 커밋의 메시지 첫 줄 후보는
`Show the time in the zone the config names`.

## 실제로 돌린 것이 이 plan과 갈린 자리

(실행하면서 채운다. plan을 그대로 밟되 실측이 다르면 실측이 답이다.)

## 이 milestone이 증명하게 될 문장

"`timezone=Asia/Seoul`을 적은 기계의 `date`가 서울 시각을 찍는다. 그 이름의
파일이 없으면 로그 한 줄을 남기고 UTC로 떨어진다. 이 키를 안 적은 기계는 한
글자도 안 바뀐다."

그 이상이 아니다. 서머타임이 있는 시간대에서 규칙이 맞는지는 glibc의 일이고
게이트는 서울 하나만 본다.
