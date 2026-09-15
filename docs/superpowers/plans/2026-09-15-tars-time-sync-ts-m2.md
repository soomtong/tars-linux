# TS-M2 — DHCP가 알려 준 서버를 쓴다

Date: 2026-09-15
design: `docs/superpowers/specs/2026-09-15-tars-time-sync-design.md`
앞 milestone: `docs/superpowers/plans/2026-09-15-tars-time-sync-ts-m1.md`

TS-M1이 `ntp=<IPv4>` 한 갈래를 끝냈다. 설정에 주소를 적으면 우리 코드가 그
주소에 SNTP로 묻고 시계를 뛴다. 남은 갈래가 `ntp=dhcp`이고, 그것이 실기계의
기본 경로다 — 사람이 주소를 적는 것보다 공유기가 알려 주는 것을 쓰는 편이
옳다.

Goal: `tars.conf`에 `ntp=dhcp`를 적은 기계가 DHCP 서버(실기계에서는 공유기)가
option 42로 알려 준 주소에 묻는다. 그 주소가 안 닿아도 부팅은 평소대로
끝난다. 둘 다 게이트 안에서 매번 증명된다.

Architecture: 경로를 넷으로 자른 것이 design 결정 4이고 M2가 그 자름의 세
조각을 만든다.

```
dhcpcd ──(option 42)──> hook 30-tars-ntp ──> /run/tars/ntp_servers ──> SNTP 자식
        [dhcpcd의 계약]      [우리 sh 4줄]          [파일]            [우리 Zig]
        미증명(위험 3)       호스트 검사가 본다      부팅 B가 본다
```

M1이 이미 마지막 화살표를 세워 두었다(결정 M1-D — 파일이 있으면 읽는다).
M2가 더하는 것은 앞의 둘과, 마지막 화살표에 "없으면 생길 때까지 기다린다"를
붙이는 일이다.

Tech Stack: Zig 0.16(`std.os.linux`만) · POSIX sh(hook 4줄) · bash · cpio ·
QEMU 10.0.11 · debugfs(e2fsprogs)

---

## 착수 전에 컨테이너에서 확인한 것 하나

design 위험 3의 처방(`dhcpcd`의 argv에 `-o ntp_servers`)이 파일을 요구하지
않는다는 것을 sysroot에서 직접 봤다.

```
$ ls /usr/local/amd64-sysroot/usr/share/dhcpcd/
hooks                      ← 정의 파일이 없다. 디렉터리 하나뿐이다
$ grep -ac "define 42 array ipaddress ntp_servers" .../usr/sbin/dhcpcd
1                          ← 정의가 바이너리 안에 박혀 있다
$ grep -n ntp /usr/local/amd64-sysroot/etc/dhcpcd.conf
35:option ntp_servers       ← 이 파일은 initrd에 안 들어간다(M0 실측 8)
```

이것이 이 milestone의 가장 큰 미지수를 하나 지웠다. `dhcpcd`가
`/usr/share/dhcpcd/dhcpcd-definitions.conf` 같은 파일을 읽어야 옵션 이름을
안다면, 그 파일이 없는 initrd에서 `-o ntp_servers`는 "unknown option"으로
죽고 증상이 검사 4~10(주소가 안 붙는다)에서 나온다 — 우리가 고친 자리와
멀다. 정의가 바이너리 안에 있으므로 그 길이 없다.

그리고 `20-resolv.conf`의 이웃인 `50-timesyncd.conf`가 실제로
`$new_ntp_servers`를 쓰는 기성 hook이라는 것도 봤다. 우리 hook이 지어낸
계약이 아니라 dhcpcd가 이미 여러 벌 쓰고 있는 이름이라는 뜻이다.

## design에 없던 결정 여섯

M1이 그랬듯 design을 고치지 않고(틀린 것이 아니라 덜 적힌 것이다) 이 plan이
근거와 함께 정한다.

### 결정 M2-A — 기다림은 자식 안에 둔다. `sync()`가 fork를 먼저 한다

design 결정 3이 "부모는 한 순간도 안 기다린다"이므로 기다림을 부모에 둘 수
없다. 그런데 지금 `sync()`는 부모가 파일을 읽어 주소를 정한 뒤에 fork한다
(`sntp.zig:349-353`). 즉 갈래 구조를 바꿔야 한다.

바뀐 모양은 이렇다.

| | M1 | M2 |
|---|---|---|
| 주소를 정하는 쪽 | 부모 | 자식 |
| `ntp=dhcp`인데 파일이 없으면 | 부모가 로그 한 줄 찍고 fork 안 함 | 자식이 30초까지 기다렸다가 로그 한 줄 찍고 죽음 |
| 부모의 마지막 로그 줄 | `will ask 10.0.2.2` | `will ask 10.0.2.2` 또는 `will ask dhcp` |

부모의 줄이 `want.arg()`로 바뀌는데 `.server` 갈래에서는 글자가 그대로다 —
`arg()`가 주소를 점 넷으로 돌려주기 때문이다. 그래서 부팅 A의 로그가 안
바뀐다.

갈래 하나가 없어진다. M1에는 "부모가 파일을 못 읽어서 fork를 안 하는" 상태가
있었고 M2에는 없다 — `ntp=dhcp`면 언제나 자식이 태어난다. 그 자식이 기다리다
죽는 것과 태어나지도 않는 것 중 어느 쪽이 나은가는 로그가 답한다: 태어나면
`sntp child (pid N) will ask dhcp`와 `gave up waiting`이 둘 다 남고, 안
태어나면 그 사이에 무슨 일이 있었는지 아무도 모른다.

### 결정 M2-B — hook은 저장소 파일이다. `make_initrd.sh`가 복사한다

`make_initrd.sh`가 파일을 만드는 방법이 둘 있다 — 복사(`20-resolv.conf`처럼)
와 heredoc(`/etc/passwd`처럼). hook은 복사 쪽으로 간다.

근거는 호스트 검사다(design 결정 4의 2번). 그 검사가 하는 일이 hook을
`sh`로 직접 돌려 보는 것인데, heredoc이면 그 글자가 `make_initrd.sh` 안에
있어서 검사가 스크립트를 실행하지 않고는 그 파일을 만들 수 없다. 저장소에
파일로 있으면 검사가 `sh ../kernel/dhcpcd-hooks/30-tars-ntp` 한 줄이다.

자리는 `kernel/dhcpcd-hooks/30-tars-ntp`다. 디렉터리를 새로 만드는 이유는
이름이 initrd 안의 자리(`/usr/lib/dhcpcd/dhcpcd-hooks/`)와 같아야 읽는
사람이 어디로 가는 파일인지 바로 알기 때문이다.

### 결정 M2-C — hook이 파일 경로를 변수로 한 번 정한다

호스트 검사가 hook을 그대로 돌리면 컨테이너의 진짜 `/run/tars/ntp_servers`에
쓴다. `--rm` 컨테이너라 아무도 안 읽지만, 검사가 시스템 경로에 쓰는 것을 이
저장소에 남기고 싶지 않다.

그래서 hook의 첫 줄이 이렇다.

```sh
: "${tars_ntp_file:=/run/tars/ntp_servers}"
```

기본값이 하나뿐이라 "길이 둘"이 아니다(design 결정 9가 `/etc/localtime`을
안 만든 기준). 덮어쓰는 자리는 호스트 검사 한 곳이고, 게스트에서는 그 변수가
없으므로 언제나 기본값이다.

이름에 `tars_` 접두사를 붙이는 이유는 hook이 실행되는 것이 아니라
`dhcpcd-run-hooks`에 source되기 때문이다(그 스크립트의 352행이 `. "$hook"`
이다). 변수가 hook들 사이에 새므로 흔한 이름은 남의 것과 부딪친다.

같은 이유로 `return`을 안 쓴다. source될 때는 맞는 문장이지만 호스트 검사는
`sh <파일>`로 실행하고, 그러면 셸이 "함수도 source도 아닌 자리의 return"이라고
말한다. `if` 한 겹이 두 방식에서 다 옳다.

### 결정 M2-D — 부팅 B의 initrd는 cpio 조각을 뒤에 이어 붙여 만든다

부팅 B는 `/run/tars/ntp_servers`가 미리 있는 initrd를 요구한다(design 결정
7). 그런데 `kernel/initrd.cpio`는 열두 체인이 함께 쓰는 산출물이라 거기에
심으면 실기계용 initrd가 죽은 NTP 주소를 싣고 다닌다.

갈래가 셋이었다.

| 갈래 | 비용 |
|---|---|
| 조각을 이어 붙인다 | `net/check.sh`에 4줄. 커널의 initramfs가 여러 archive를 잇는 성질에 기댄다 |
| `make_initrd.sh`에 출력 경로·추가 디렉터리 인자를 만든다 | 공용 빌드 스크립트의 인터페이스가 늘고 체인이 initrd를 두 번 굽는다(+약 5초) |
| 게스트 셸로 심는다 | 못 한다. SNTP 자식은 셸보다 먼저 돈다 |

첫째로 간다. 커널의 `unpack_to_rootfs`가 버퍼를 다 쓸 때까지 archive를 이어
읽고, 뒤의 archive가 앞의 것을 덮는다 — 마이크로코드를 앞에 붙이는 흔한
수법의 반대 방향이다. gzip 두 덩이를 이어 붙인 것도 그 자체로 정상적인 gzip
stream이라 어느 쪽 경로로 풀리든 결과가 같다.

그 성질에 기대는 것이 이 plan의 유일한 미지수이므로 Task 5의 첫 부팅이 그것을
바로 답한다. 안 되면 증상이 명확하다 — 검사 21이 "파일이 없다"로 죽고
게스트 로그에 `ntp=dhcp but /run/tars/ntp_servers is not there`가 찍힌다.
그때 둘째 갈래로 옮긴다.

### 결정 M2-E — 죽은 주소는 `192.0.2.1`이다

RFC 5737의 TEST-NET-1이다. 문서용으로 예약돼 있어서 어느 네트워크에도 실물이
없고, 그래서 "답이 안 오는 것"이 이 기계 바깥 사정으로 뒤집히지 않는다.

SLIRP 안의 주소(예: `10.0.2.200`)를 쓰지 않는 이유는 실패의 모양이 다르기
때문이다. 같은 서브넷이면 ARP가 실패하고, 바깥 주소면 기본 경로를 밟아
나갔다가 답이 안 온다. 뒤가 실기계에서 NTP 서버가 죽었을 때의 모양에 가깝다.

### 결정 M2-F — "셸이 제때 떴다"는 부팅 A와의 차이로 잰다

design의 끝 기준이 "그 부팅의 셸이 뜨는 시각이 다른 부팅과 같다"인데, 같은
체인 안에 비교 대상이 이미 있다(부팅 A). 그래서 둘 다 QEMU를 띄우기 직전과
프롬프트를 본 직후에 `date +%s`를 찍고 차이를 본다.

상한은 10초다. 근거가 둘이다 — 막히는 경우에 붙는 시간이 60초 이상이고
(자식이 30회 × 2초를 쓴다), 게이트의 부팅 하나가 TCG에서 12초 안팎이라 잡음이
몇 초다. 10초는 그 사이가 넓게 비어 있는 자리다.

이 검사가 무엇을 못 보는지도 적어 둔다. 부팅 A와 부팅 B가 똑같이 60초씩
늦어지면 차이가 0이라 초록이다 — 그 고장은 이 검사가 아니라 체인 단독 시간
(Task 8)이 본다.

## Task 0 — 지금 상태를 재고 시작한다

- [ ] Step 1: 호스트 검사가 지금 초록인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: `PASS`가 여섯 번(config · power · devices · storage · environ · sntp).
빨간불이면 이 milestone이 만든 것이 아니므로 먼저 가른다.

- [ ] Step 2: `net` 체인 단독 시간을 잰다 (약 50초)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } 2>&1 | tail -20
```

기대: `PASS`와 49초 안팎(M1 실측 15가 49.223초였다). 이 값이 부팅 B를 더하기
전의 기준선이고 Task 8에서 같은 명령으로 다시 잰다.

## Task 1 — hook 파일과 그것을 직접 돌리는 호스트 검사

- [ ] Step 1: `kernel/dhcpcd-hooks/30-tars-ntp`를 만든다

```sh
# dhcpcd가 option 42로 받은 NTP 서버를 init이 읽을 자리에 적는다(TS design
# 결정 4). 이 파일이 그 경로의 둘째 조각이고, 셋째가 파일이며 넷째가
# init/src/sntp.zig다.
#
# 이 자리에 우리 파일을 두는 근거는 이웃들이다. make_initrd.sh가 같은
# 디렉터리에 20-resolv.conf를 넣고 있고, 그것이 $new_domain_name_servers로
# /etc/resolv.conf를 쓰는 것이 지금 게이트에서 매번 돈다. 우리는 글자 그대로
# 같은 계약을 $new_ntp_servers에 대해 쓴다. sysroot에 안 넣는 50-timesyncd.conf
# 도 같은 변수를 쓰는 기성 hook이다 — 우리가 지어낸 이름이 아니다.
#
# 실행되는 것이 아니라 source된다(dhcpcd-run-hooks:352의 `. "$hook"`). 그래서
# 두 가지를 지킨다 — 변수 이름에 tars_ 접두사를 붙여 남의 hook과 안 부딪치게
# 하고, return을 안 쓴다. return은 source될 때만 맞는 문장이고 호스트 검사는
# 이 파일을 sh로 직접 돌린다.
#
# 경로를 변수로 한 번 정하는 이유가 그 호스트 검사다. 기본값이 하나뿐이라
# 길이 둘이 되지 않고, 덮어쓰는 자리는 net/check.sh의 검사 한 곳이다.
: "${tars_ntp_file:=/run/tars/ntp_servers}"

# dirname을 안 부른다. 게스트에 있는지 없는지를 이 파일 하나 때문에 확인해야
# 하는 의존을 만들지 않으려는 것이고, 셸의 접미사 제거로 같은 값이 나온다.
# mkdir은 20-resolv.conf가 이미 부르고 있으므로 게스트에 있다.
if [ -n "${new_ntp_servers:-}" ]; then
	mkdir -p "${tars_ntp_file%/*}"
	printf '%s\n' "$new_ntp_servers" > "$tars_ntp_file"
fi
```

들여쓰기가 탭인 것은 이웃 hook들과 같다.

- [ ] Step 2: `net/check.sh`의 빌드 절 뒤에 호스트 검사를 넣는다

`make_initrd.sh` 호출 바로 다음, `make_disk.sh` 앞이다. 게스트도 QEMU도
필요 없으므로 첫 부팅보다 훨씬 앞에서 죽는 것이 진단에 좋다.

```bash
# ── 호스트 검사: hook 네 줄이 실제로 파일을 쓰는가 (TS-M2) ────────────
#
# design 결정 4의 2번이다. 경로 넷 중 "hook → 파일" 조각은 게스트도 QEMU도
# 없이 증명된다 — dhcpcd가 하는 일이 변수를 채우고 이 파일을 source하는
# 것뿐이므로, 변수를 우리가 채우면 같은 코드가 같은 일을 한다.
#
# tars_ntp_file을 덮어쓰는 유일한 자리다(결정 M2-C). 안 덮으면 이 검사가
# 컨테이너의 진짜 /run/tars에 쓴다.
HOOK=../kernel/dhcpcd-hooks/30-tars-ntp
HOOKDIR="$(mktemp -d)"

if ! new_ntp_servers='192.0.2.1 198.51.100.7' \
     tars_ntp_file="${HOOKDIR}/ntp_servers" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero"
  rm -rf "$HOOKDIR"
  exit 1
fi
HOOK_FIRST="$(awk 'NR==1 {print $1}' "${HOOKDIR}/ntp_servers" 2>/dev/null || true)"
if [ "$HOOK_FIRST" != "192.0.2.1" ]; then
  echo "FAIL: the dhcpcd hook wrote [${HOOK_FIRST}] where 192.0.2.1 was expected"
  rm -rf "$HOOKDIR"
  exit 1
fi

# 음성. 변수가 안 오는 reason(예: option 42가 없는 리스)에서 파일을 만들면,
# init이 빈 파일을 읽고 "주소를 못 읽었다"로 30초를 기다린다. 아무것도 안
# 하는 것이 맞는 동작이다.
rm -f "${HOOKDIR}/ntp_servers"
if ! tars_ntp_file="${HOOKDIR}/ntp_servers" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero with no ntp servers"
  rm -rf "$HOOKDIR"
  exit 1
fi
if [ -e "${HOOKDIR}/ntp_servers" ]; then
  echo "FAIL: the dhcpcd hook wrote a file with no ntp servers to write"
  rm -rf "$HOOKDIR"
  exit 1
fi
rm -rf "$HOOKDIR"
echo "the dhcpcd hook writes the first ntp server and nothing else"
```

`$HOOKDIR`을 `trap`이 아니라 손으로 지우는 이유는 이 검사가 첫 부팅보다
앞이고, 여기서 죽으면 `cleanup`이 아직 걸리기 전이기 때문이다(`trap`은 아래
QEMU 절에서 걸린다).

- [ ] Step 3: 그 검사만 먼저 돌려 본다 (약 40초 — 빌드가 앞에 있다)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh 2>&1 | grep -E "dhcpcd hook|FAIL"
```

기대: `the dhcpcd hook writes the first ntp server and nothing else`. 이 줄이
나온 뒤로 체인이 계속 돌아 `PASS`로 끝나야 한다(아직 부팅 B가 없으므로).

## Task 2 — hook을 initrd에 넣고 dhcpcd에 옵션을 준다

- [ ] Step 1: `kernel/make_initrd.sh`의 hook 복사 절 끝에 두 줄을 더한다

`cp "$SYSROOT/.../20-resolv.conf" ...` 바로 뒤다.

```bash
# TS-M2. 우리 hook. 옆의 20-resolv.conf와 계약이 같다 — dhcpcd-run-hooks가
# 이 디렉터리를 훑어 있는 파일을 전부 source하고, 각 hook은 new_* 변수에서
# 자기 몫을 꺼낸다. 저쪽은 $new_domain_name_servers로 /etc/resolv.conf를,
# 이쪽은 $new_ntp_servers로 /run/tars/ntp_servers를 쓴다.
#
# 0644인 것도 옆의 것과 같다. 실행이 아니라 source라서 실행 권한이 필요 없다.
cp dhcpcd-hooks/30-tars-ntp "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0644 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/30-tars-ntp"
```

- [ ] Step 2: `init/src/net.zig`의 argv에 `-o ntp_servers`를 더한다

`net.zig:138` 한 줄을 이렇게 바꾸고 그 위에 주석을 붙인다.

```zig
        // `-o ntp_servers`가 TS design 위험 3의 처방이다(TS-M0 실측 8).
        // dhcpcd의 요청 목록은 /etc/dhcpcd.conf와 컴파일 타임 기본값에서
        // 오는데, sysroot의 그 파일에 `option ntp_servers`가 있고
        // make_initrd.sh가 그 파일을 initrd에 안 넣는다. 파일을 넣는 대신
        // 한 단어를 argv에 적는다 — 그 파일에는 우리가 안 고른 줄이 서른
        // 넘게 들어 있어서, 넣으면 무엇이 왜 켜졌는지가 흐려진다.
        //
        // 옵션 이름을 dhcpcd가 파일 없이 아는 것을 sysroot에서 확인했다 —
        // /usr/share/dhcpcd에 정의 파일이 없고 바이너리 안에
        // `define 42 array ipaddress ntp_servers`가 박혀 있다.
        //
        // 이것이 실기계에서만 뜻이 있다. 게이트의 SLIRP는 option 42를 영영
        // 안 주므로(TS 확인 5) 이 단어가 있든 없든 게이트의 답이 같다.
        const argv = [_:null]?[*:0]const u8{
            DHCPCD_PATH.ptr, "-o", "ntp_servers", "eth0", null,
        };
```

- [ ] Step 2b: 편집 뒤 지운 줄을 확인한다

```bash
git diff --stat init/src/net.zig kernel/make_initrd.sh
git diff init/src/net.zig | grep '^-' | grep -v '^---'
```

기대: `net.zig`에서 지워진 줄이 argv 한 줄뿐이고 `make_initrd.sh`는 지운 줄
0이다.

- [ ] Step 3: 빌드와 호스트 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: `PASS` 여섯. 이 변경은 호스트 검사가 보는 것을 안 건드린다.

- [ ] Step 4: 체인을 한 판 돌려 dhcpcd가 그 옵션으로도 사는지 본다 (약 50초)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh 2>&1 | tail -25
```

기대: `PASS`. 여기서 죽으면 증상이 검사 5~10(주소·경로·dhcpcd 생존)이고,
그 경우 `-o ntp_servers`를 되돌리고 `/etc/dhcpcd.conf`를 initrd에 넣는
갈래로 옮긴다(위험 3의 나머지 처방).

확인할 것 하나가 더 있다. 이 부팅에서 SLIRP가 혹시 option 42를 준다면
게스트에 `/run/tars/ntp_servers`가 실제로 생긴다 — 그러면 부팅 B가 심은
파일을 dhcpcd가 덮어쓸 수 있다. 위 실행 로그에 우리 hook이 남긴 흔적이 있는지
`grep -a "ntp_servers"`로 본다. 기대는 아무것도 없는 것이고(libslirp의
bootp에 NTP 옵션이 없다), 있으면 결정 M2-E의 주소를 부팅 B에서 다시 본다.

## Task 3 — 자식이 파일을 기다린다

`init/src/sntp.zig` 하나만 고친다. 세 자리다.

- [ ] Step 1: 상수 둘을 더한다 (`MAX_TRIES` 아래)

```zig
/// `ntp=dhcp`일 때 파일이 생기기를 기다리는 상한과 간격(TS-M2).
///
/// 30초인 근거는 `MAX_TRIES`와 같은 자리에서 온다. 이 파일을 쓰는 것은
/// dhcpcd의 hook이고 hook은 리스를 받은 뒤에 불리므로, 기다리는 대상이
/// 결국 리스다 — `net/check.sh`의 리스 대기 상한이 60초이고 실제 관측이
/// 10초 안팎이다(TS-M1 실측 10).
///
/// 이 수가 부팅 시간에 영향을 안 준다는 것이 design 결정 3의 덤이다. 부모는
/// 이미 다음 줄로 갔고, 이 기다림은 자식 안에서만 돈다(결정 M2-A).
const FILE_WAIT_TRIES: usize = 60;
const FILE_WAIT_SLEEP_MS: isize = 500;
```

- [ ] Step 2: `serverFromFile()`의 실패 로그를 ENOENT에서만 조용하게 만들고
      기다리는 루프를 그 아래에 더한다

`serverFromFile()`의 `open` 실패 갈래를 이렇게 바꾼다.

```zig
    if (failed(rc)) |e| {
        // ENOENT는 조용히 지나간다. M2부터 이 함수는 아래 루프 안에서
        // 불리고, 그 루프의 정상 상태가 "아직 없다"이기 때문이다 — 안
        // 가리면 로그에 같은 줄이 예순 번 찍혀서 정말 이상한 실패(권한 ·
        // 마운트)를 덮는다.
        if (e != .NOENT) {
            std.debug.print("tars-init: cannot open {s} (errno {d})\n", .{
                SERVER_FILE, @intFromEnum(e),
            });
        }
        return null;
    }
```

그리고 `serverFromFile()` 바로 아래에 더한다.

```zig
/// 파일이 생길 때까지 기다린다. 자식 안에서만 불린다(결정 M2-A).
///
/// 왜 inotify가 아닌가. init에 libc도 힙도 없으므로 `inotify_add_watch`를
/// 직접 다뤄야 하고, 그러면 "디렉터리가 아직 없을 때"를 또 다뤄야 한다 —
/// /run/tars를 만드는 것도 hook이다. 0.5초마다 열어 보는 쪽이 코드가 절반이고
/// 최악의 손해가 0.5초다.
///
/// 기다리는 것을 먼저 알린다. 이 줄이 없으면 `will ask dhcp` 다음이 30초
/// 침묵이라, 로그만 보는 사람이 그 침묵을 매달림으로 읽는다.
fn waitForServerFile() ?[4]u8 {
    std.debug.print("tars-init: ntp=dhcp, waiting for {s}\n", .{SERVER_FILE});
    var tries: usize = 0;
    while (tries < FILE_WAIT_TRIES) : (tries += 1) {
        if (serverFromFile()) |ip| return ip;
        sleepMillis(FILE_WAIT_SLEEP_MS);
    }
    // 실기계에서 이 줄이 뜻하는 것은 "공유기가 option 42를 안 준다"이고,
    // 그것이 design 위험 3이 게이트로 못 가리는 바로 그 상태다. 그래서 이
    // 문장이 진단의 시작점이 되도록 파일 이름을 함께 찍는다.
    std.debug.print("tars-init: gave up waiting for {s}\n", .{SERVER_FILE});
    return null;
}
```

- [ ] Step 3: `sync()`의 갈래 구조를 바꾼다

`const server: [4]u8 = switch (want) { ... };`부터 끝까지를 이렇게 바꾼다.

```zig
    // M1에서는 부모가 주소를 정한 뒤에 fork했다. M2는 순서가 반대다
    // (결정 M2-A) — `ntp=dhcp`의 주소는 기다려야 나오고, 기다리는 일은
    // 부모가 할 수 없기 때문이다(design 결정 3).
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for sntp (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        // 첫 줄이어야 한다(TS-M1 결정 M1-A). `execve`를 안 하는 자식이라
        // 부모의 SIGTERM 핸들러를 그대로 갖고 있고, 그대로 두면 전원을 끌 때
        // 이 자식만 안 죽는다. M2의 부팅 B가 그것의 진짜 시험이다 — 안 닿는
        // 주소를 60초 동안 묻는 자식이 전원을 끄는 순간 살아 있다.
        power.resetToDefault();
        const server: [4]u8 = switch (want) {
            .off => unreachable, // 위에서 돌아갔다
            .dhcp => waitForServerFile() orelse linux.exit(0),
            .server => |ip| ip,
        };
        askAndStep(server);
        linux.exit(0);
    }
    // net/check.sh가 이 줄을 grep하지는 않는다. `net.zig`의
    // `started dhcpcd on eth0 (pid N)`과 짝이 되는 자리이고, 자식이 아무 말도
    // 못 하고 죽은 회차에 "태어나기는 했다"를 남긴다.
    //
    // 주소가 아니라 설정값을 찍는다. 부모는 이제 주소를 모르고(자식이
    // 정한다), `.server` 갈래에서는 `arg()`가 점 넷을 돌려주므로 M1과 글자가
    // 같다 — 부팅 A의 로그가 안 바뀐다.
    std.debug.print("tars-init: sntp child (pid {d}) will ask {s}\n", .{
        pid, want.arg(&ntp_buf),
    });
}
```

- [ ] Step 4: 편집 뒤 지운 줄을 읽는다

```bash
git diff --stat init/src/sntp.zig
git diff init/src/sntp.zig | grep '^-' | grep -v '^---'
```

기대: 지워진 줄이 `sync()`의 옛 `switch` 블록(6줄)과 옛 fork 블록의 자식
부분, 그리고 `serverFromFile`의 옛 로그 줄 셋이다. `askAndStep`과 순수 함수
셋에서는 한 줄도 안 지워져야 한다.

- [ ] Step 5: 호스트 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: `PASS` 여섯. `sntp_test`가 보는 것은 순수 함수 셋이라 이 변경에 안
흔들린다 — 그것이 M1이 순수 계산과 시스템 콜을 가른 값이다.

## Task 4 — 부팅 B가 쓸 디스크와 initrd

- [ ] Step 1: `net/make_disk.sh`에 셋째 이미지를 더한다 (파일 끝)

```bash
# TS-M2. 부팅 B가 쓰는 디스크. 부팅 A와 다른 것은 ntp의 값 하나다 —
# 주소가 설정에 없고 initrd에 심은 /run/tars/ntp_servers에서 온다.
#
# 이 디스크가 증명하는 문장이 부팅 A와 다르다. 저쪽은 "우리가 적은 주소에
# 묻는다"이고 이쪽은 "DHCP가 알려 준 주소를 읽어서 묻는다"이다. 값이 같은
# 코드 경로를 두 번 도는 것이 아니라, sntp.zig의 갈래 둘 중 안 밟힌 쪽을
# 밟는다.
bake ../out/net-ntp-dhcp.img tars-ntp-dhcp 'net=dhcp
ntp=dhcp
'
```

라벨이 셋 다 다르다(`tars-net` · `tars-ntp` · `tars-ntp-dhcp`). 근거는 M1과
같다 — 같은 라벨이면 엉뚱한 이미지를 물린 회차의 게스트 로그가 똑같이 생긴다.

- [ ] Step 2: `net/check.sh`의 TS-M1 상수 블록 아래에 M2 상수와 initrd
      만드는 함수를 더한다

```bash
# ── TS-M2 ───────────────────────────────────────────────────────────────
#
# 부팅 B가 쓰는 것들이다. 이 체인의 세 번째 QEMU이고 부팅 A가 꺼진 뒤에 뜬다.
#
# 45468은 monitor 대역(45455~45464 · 45471)과 IN의 둘(45465 · 45466)과
# TS-M1의 하나(45467) 밖이다.
NTP_DHCP_MONITOR_PORT=45468

# 심는 주소. RFC 5737의 TEST-NET-1이라 어느 네트워크에도 실물이 없다
# (결정 M2-E). 죽은 주소여야 이 부팅의 값이 두 배가 된다 — 살아 있는 주소를
# 심으면 파일 경로만 증명되고, 죽은 주소를 심으면 design 결정 3의 음성
# ("안 닿는 서버가 부팅을 안 막는다")까지 함께 증명된다.
NTP_DEAD_SERVER=192.0.2.1

# 셸이 뜨는 데 걸린 시간이 부팅 A보다 이만큼 넘게 길면 실패다(결정 M2-F).
# 막히는 경우에 붙는 시간이 60초 이상이고(자식이 30회 × 2초) 부팅 하나가
# TCG에서 12초 안팎이라, 10초는 그 사이가 넓게 비어 있는 자리다.
BOOT_DELTA_MAX=10

LOGB="$(mktemp)"
INITRD_B="$(mktemp)"
QEMU_PID_B=""
BOOT_A_SECONDS=0
BOOT_B_SECONDS=0

# 부팅 B의 initrd를 짓는다(결정 M2-D).
#
# kernel/initrd.cpio를 안 건드린다. 그 파일은 열두 체인이 함께 쓰는
# 산출물이고, 거기에 심으면 실기계용 initrd가 죽은 NTP 주소를 싣고 다닌다.
#
# 대신 cpio 한 조각을 뒤에 이어 붙인다. 커널의 initramfs 언패커가 버퍼를 다
# 쓸 때까지 archive를 이어 읽고 뒤의 것이 앞의 것을 덮는다 — 마이크로코드를
# 앞에 이어 붙이는 흔한 수법의 반대 방향이다. gzip 두 덩이를 이어 붙인 것도
# 그 자체로 정상적인 gzip stream이라 어느 경로로 풀리든 결과가 같다.
#
# init에게는 우리가 심은 파일과 dhcpcd의 hook이 쓴 파일이 구별되지 않는다.
# 그것이 design 결정 4가 경로를 자른 이유다 — SLIRP가 option 42를 영영 안
# 줘도 "파일 → init" 조각이 게이트 안에서 초록이 된다.
build_ntp_initrd() {
  local extra seg
  extra="$(mktemp -d)"
  seg="$(mktemp)"

  mkdir -p "${extra}/run/tars"
  printf '%s\n' "$NTP_DEAD_SERVER" > "${extra}/run/tars/ntp_servers"

  (cd "$extra" && find . | cpio -o -H newc --quiet) | gzip -6 > "$seg"
  cat ../kernel/initrd.cpio "$seg" > "$INITRD_B"

  rm -rf "$extra" "$seg"
}
```

`cleanup()`에 세 줄을 더한다(부팅 B의 QEMU와 임시 initrd).

```bash
  if [ -n "$QEMU_PID_B" ] && kill -0 "$QEMU_PID_B" 2>/dev/null; then
    kill "$QEMU_PID_B" 2>/dev/null || true
    wait "$QEMU_PID_B" 2>/dev/null || true
  fi
  rm -f "$INITRD_B"
```

- [ ] Step 3: 부팅 A의 ready 루프에 시간 측정을 붙인다

QEMU를 띄우는 줄 바로 앞에 한 줄, ready 루프 뒤에 두 줄이다.

```bash
# 결정 M2-F. 부팅 B가 이 값과 비교된다 — "셸이 다른 부팅과 같은 시각에
# 뜬다"를 재려면 같은 방법으로 잰 상대가 있어야 한다.
BOOT_A_START="$(date +%s)"
```

```bash
BOOT_A_SECONDS=$(( $(date +%s) - BOOT_A_START ))
echo "the ntp guest reached a prompt in ${BOOT_A_SECONDS}s"
```

## Task 5 — 부팅 B와 검사 20·21·22

- [ ] Step 1: `net/check.sh`의 부팅 A 절 끝(stub을 죽이고 답한 횟수를 찍는
      줄) 다음, `echo "PASS"` 앞에 부팅 B 절을 넣는다

```bash
# ══ 부팅 B: DHCP가 알려 준 서버를 쓴다 (TS-M2) ═════════════════════════
#
# 여기서부터 게스트가 또 새로 뜬다. 앞의 둘과 다른 것이 둘이다 — 디스크가
# out/net-ntp-dhcp.img(ntp=dhcp)이고, initrd에 /run/tars/ntp_servers가 미리
# 있다.
#
# 이 부팅이 증명하는 것이 둘이다.
#   1. init이 그 파일을 읽는다 — 로그가 심은 주소를 이름 대며 찍는다
#   2. 안 닿는 서버가 부팅을 안 막는다 — 셸이 부팅 A와 같은 시각에 뜬다
#
# 상대가 없는 것이 이 부팅의 설계다. stub은 위에서 이미 죽였고 심은 주소는
# 어느 네트워크에도 없다. 그래서 자식은 서른 번을 다 쓰고, 전원을 끄는
# 순간까지 살아 있다 — 그것이 TS-M1 결정 M1-A의 진짜 시험이다.
echo "=== booting again with ntp=dhcp and a planted ${NTP_DEAD_SERVER} ==="

build_ntp_initrd
echo "planted ${NTP_DEAD_SERVER} in /run/tars/ntp_servers of the boot-B initrd"

LOG="$LOGB"
BOOT_B_START="$(date +%s)"

qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd "$INITRD_B" \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="${REPO_ROOT}/out/net-ntp-dhcp.img",if=virtio,format=raw \
  -serial file:"$LOGB" \
  -monitor tcp:127.0.0.1:${NTP_DHCP_MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID_B=$!

READY_B=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOGB" >/dev/null; then READY_B=1; break; fi
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then break; fi
  sleep 1
done
BOOT_B_SECONDS=$(( $(date +%s) - BOOT_B_START ))
[ "$READY_B" = "1" ] || fail "the ntp=dhcp guest never rendered a prompt"
echo "the ntp=dhcp guest reached a prompt in ${BOOT_B_SECONDS}s"

# ── 검사 20: 설정이 읽혔고 ntp=dhcp인가 ───────────────────────────────
# 검사 17과 같은 자리를 다른 값에 대해 한 번 더 본다. 이것이 없으면 아래
# 둘이 실패했을 때 "엉뚱한 디스크를 물었다"와 "코드가 틀렸다"가 안 갈린다 —
# 세 디스크의 라벨을 서로 다르게 둔 것과 같은 이유다.
if ! grep -aE "tars-init: config shell=.* net=dhcp ntp=dhcp" "$LOGB" >/dev/null; then
  fail "the ntp=dhcp config disk did not reach init" "tars-init: config shell="
fi
echo "the guest read ntp=dhcp off the config disk"

# ── 검사 21: init이 심은 파일을 읽었나 ────────────────────────────────
# design 결정 4의 1번이다. 이 줄이 나오면 경로 넷 중 "파일 → init" 조각이
# 게이트 안에서 닫힌 것이고, 그 조각은 SLIRP가 option 42를 주든 안 주든
# 같은 코드다.
#
# 기다리는 이유는 자식의 첫 줄이 파일을 여는 것이 아니기 때문이다. fork 뒤에
# 시그널 정책을 되돌리고, 파일을 열고, 그 다음이 이 줄이다 — 부팅 A의 검사
# 18보다 훨씬 이르지만 0초는 아니다.
READ_FILE=0
for _ in $(seq 1 60); do
  if grep -a "tars-init: ntp server ${NTP_DEAD_SERVER} came from /run/tars/ntp_servers" \
       "$LOGB" >/dev/null; then
    READ_FILE=1; break
  fi
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READ_FILE" = "1" ] || \
  fail "init never read ${NTP_DEAD_SERVER} out of /run/tars/ntp_servers" \
    "tars-init: ntp" "tars-init: sntp"
echo "init read ${NTP_DEAD_SERVER} out of the planted /run/tars/ntp_servers"

# ── 검사 22: 안 닿는 서버가 부팅을 안 막았나 ──────────────────────────
# design 결정 3의 음성이다. 이 체인에서 우리가 못 박으려는 제약이 "네트워크가
# 꺼져 있거나 안 닿아도 부팅은 평소대로 끝난다"이고, 그 제약은 양성 검사로는
# 절대 안 보인다 — 시계가 맞는 것과 부팅이 안 막히는 것은 서로 다른 사실이다.
#
# 이 순간 게스트 안에서는 자식이 192.0.2.1에 세 번째쯤 묻고 있다. 그 자식이
# 부모를 한 순간도 안 세웠다는 것을 두 수의 차이가 말한다.
#
# 이 검사가 못 보는 것도 적어 둔다 — 부팅 A와 B가 똑같이 늦어지면 차이가 0이라
# 초록이다. 그 고장은 체인 단독 시간이 본다.
BOOT_DELTA=$(( BOOT_B_SECONDS - BOOT_A_SECONDS ))
if [ "$BOOT_DELTA" -gt "$BOOT_DELTA_MAX" ]; then
  fail "the dead ntp server delayed the prompt by ${BOOT_DELTA}s (boot A ${BOOT_A_SECONDS}s, boot B ${BOOT_B_SECONDS}s)" \
    "tars-init: sntp" "tars-init: started console shell"
fi
echo "the dead ntp server cost ${BOOT_DELTA}s of boot time (limit ${BOOT_DELTA_MAX}s)"

# ── 부팅 B를 끈다 ─────────────────────────────────────────────────────
CONNECTED_B=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${NTP_DHCP_MONITOR_PORT}"; then CONNECTED_B=1; break; fi
  sleep 0.5
done
[ "$CONNECTED_B" = "1" ] || fail "could not connect to the ntp=dhcp guest's QEMU monitor" \
  "terminal: screen>"

echo "=== sending system_powerdown to the ntp=dhcp guest ==="
echo "system_powerdown" >&3
sleep 0.3
exec 3<&-
exec 3>&-

GONE_B=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then GONE_B=1; break; fi
  sleep 1
done
[ "$GONE_B" = "1" ] || fail "the ntp=dhcp guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것. 이 부팅에서 이 검사가 셋 중 가장 크다 — 여기가 TS-M1
# 결정 M1-A가 겨냥한 바로 그 상태다. 자식이 안 닿는 주소를 묻는 중이라 전원을
# 끄는 순간 분명히 살아 있고, power.resetToDefault()가 없으면 그 자식이
# 부모의 SIGTERM 핸들러를 물려받아 안 죽는다. 그러면 reapAll()이 유예 3초를
# 다 쓰고 `grace period expired`를 찍는다.
if grep -a "grace period expired" "$LOGB" >/dev/null; then
  fail "something outlived SIGTERM in the ntp=dhcp guest" "grace period expired"
fi
echo "nothing outlived SIGTERM — the sntp child took the default policy"
```

- [ ] Step 2: 체인 헤더 주석에 부팅 B 절을 더한다

파일 맨 위 TS-M1 절 다음이다.

```bash
# TS-M2가 부팅을 하나 더 얹었다. 부팅 A가 "우리가 적은 주소에 묻는다"였다면
# 이쪽은 "DHCP가 알려 준 주소를 읽어서 묻는다"이고, 덤으로 음성 하나를 판다:
#
#   initrd에 심은 /run/tars/ntp_servers → init이 그 주소를 읽는다
#   그 주소가 어디에도 없다 → 자식이 답 없이 재시도만 한다
#   → 그런데도 셸이 부팅 A와 같은 시각에 뜬다(design 결정 3)
#
# 그 경로의 첫 조각(dhcpcd가 option 42를 hook에 넘기는 것)만 게이트가 못
# 본다. SLIRP가 그 옵션을 안 주기 때문이고(TS 확인 5), 대신 hook 자체는
# 빌드 절의 호스트 검사가 직접 돌려서 본다.
```

- [ ] Step 3: 체인을 돌린다 (약 1분 10초)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh 2>&1 | tail -30
```

기대: 검사 20·21·22가 차례로 초록이고 `PASS`.

여기가 결정 M2-D의 시험이다. 이어 붙인 조각을 커널이 안 푼다면 검사 21이
죽고 게스트 로그에 `ntp=dhcp, waiting for /run/tars/ntp_servers`와
`gave up waiting`이 남는다(검사 21의 상한 60초보다 자식의 기다림 30초가
짧으므로 로그가 먼저 나온다). 그 경우 Task 6으로 간다. 초록이면 Task 6을
건너뛴다.

- [ ] Step 4: 실패했으면 시리얼 로그를 꺼내 온다

통과해도 한 번은 꺼내 보는 것이 이 저장소의 절차다(IN-M1). 화면에 실제로
무엇이 찍혔는지는 `--rm`과 함께 사라진다.

```bash
mkdir -p /tmp/tsm2
docker run --rm -v "$PWD":/workspace -v /tmp/tsm2:/tmp/tsm2 -w /workspace \
  tars-devcontainer bash -c '
  bash net/check.sh > /tmp/tsm2/net.log 2>&1; echo "exit=$?"
  i=0
  for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then
      i=$((i+1)); cp "$f" "/tmp/tsm2/serial${i}.log"
    fi
  done'
grep -aE "tars-init: (sntp|ntp|clock)" /tmp/tsm2/serial3.log | head -40
```

부팅 셋이므로 시리얼 로그도 셋이다. 부팅 B의 것이 파일 셋 중
`ntp=dhcp`가 나오는 것이고, 거기서 자식의 재시도 줄 수를 세면 실측이 된다.

## Task 6 — (조건부) 이어 붙이기가 안 되면 initrd를 따로 굽는다

Task 5 Step 3이 검사 21에서 죽었을 때만 한다. 초록이면 이 Task 전체를
건너뛰고 그 사실을 실측으로 적는다.

- [ ] Step 1: `kernel/make_initrd.sh`에 환경변수 둘을 받는 갈래를 만든다

```bash
# TS-M2. 게이트가 부팅 B용 initrd를 따로 구울 때만 쓰는 둘이다. 기본값이
# 지금까지의 동작과 글자 그대로 같아서, 이 변수를 안 주는 열두 체인은
# 아무것도 안 달라진다.
INITRD_OUT="${TARS_INITRD_OUT:-initrd.cpio}"
EXTRA_TREE="${TARS_INITRD_EXTRA:-}"
```

맨 끝 줄 앞에 복사를, 맨 끝 줄에 출력 경로를 쓴다.

```bash
if [ -n "$EXTRA_TREE" ]; then
  cp -a "$EXTRA_TREE"/. "$WORKDIR"/
fi
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -6 > "$INITRD_OUT"
```

- [ ] Step 2: `net/check.sh`의 `build_ntp_initrd()`를 그것으로 바꾼다

```bash
build_ntp_initrd() {
  local extra
  extra="$(mktemp -d)"
  mkdir -p "${extra}/run/tars"
  printf '%s\n' "$NTP_DEAD_SERVER" > "${extra}/run/tars/ntp_servers"
  (cd ../kernel && TARS_INITRD_OUT="$INITRD_B" TARS_INITRD_EXTRA="$extra" \
    ./make_initrd.sh) || fail "could not build the boot-B initrd"
  rm -rf "$extra"
}
```

비용이 initrd 한 번 더 굽기다. Task 8에서 그 증가분을 잰다.

## Task 7 — 반사실: 파일을 안 심으면 검사 21에서 죽는다

design의 M2 끝 기준이 이것이다. 검사가 실제로 무엇을 보고 있는지는 초록만으로
증명되지 않는다.

- [ ] Step 1: `/tmp` 사본을 만들어 심는 줄만 눕힌다

```bash
mkdir -p /tmp/tsm2
cp net/check.sh /tmp/tsm2/check.sh
sd -s -- '  printf '"'"'%s\n'"'"' "$NTP_DEAD_SERVER" > "${extra}/run/tars/ntp_servers"' \
   '  :' /tmp/tsm2/check.sh
chmod +x /tmp/tsm2/check.sh
grep -n 'run/tars/ntp_servers' /tmp/tsm2/check.sh
```

`chmod +x`를 함께 치는 이유는 NW-M2 실측 22다 — 권한이 없으면 엉뚱한 자리
(`config disk build failed`)에서 죽어서 우리가 보려던 것과 관계없는 증상이
나온다. 여기서는 체인 자신을 덮으므로 더 직접적이다.

- [ ] Step 2: 그 사본으로 돌린다 (약 1분 40초 — 검사 21이 60초를 쓴다)

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/tsm2/check.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh 2>&1 | tail -30
```

기대: 검사 20까지 초록으로 지나고 검사 21에서
`FAIL: init never read 192.0.2.1 out of /run/tars/ntp_servers`로 죽는다.
게스트 로그 발췌에 `gave up waiting for /run/tars/ntp_servers`가 보여야
한다 — 그 줄이 "자식이 태어나서 기다리다 포기했다"와 "자식이 안 태어났다"를
가른다.

검사 22가 아니라 21에서 죽는 것이 중요하다. 22에서 죽으면 파일이 없는 것과
부팅이 막히는 것을 이 체인이 못 가른다는 뜻이고, 그러면 검사를 나눈 값이
없다.

## Task 8 — 값을 재고 문서를 고친다

- [ ] Step 1: `net` 체인 단독 시간을 다시 잰다

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh ; } 2>&1 | tail -20
```

Task 0 Step 2와 비교해 증가분을 적는다. 예상은 부팅 하나(약 13초)에 검사
21·22의 대기(약 1~3초)를 더한 15초 안팎이고, 게이트는 그것을 세 번 도니 약
45초다. design 위험 5의 나머지 절반이 이 수다.

- [ ] Step 2: 루트 게이트를 한 판 돌린다 (약 33분, background로)

TS가 아직 한 판도 안 돌렸다. M1이 `init`을 고치고 M2가 `net.zig`·
`make_initrd.sh`까지 고쳤으므로 여기서 친다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

Bash 도구의 10분 한도를 넘으므로 `run_in_background`로 돌린다. 기대:
열두 체인 3/3, `skipping make` 35회, 32~33분.

이 판이 보는 것이 하나 더 있다. `-o ntp_servers`와 새 hook이 `net` 체인 밖의
체인들을 안 건드리는지 — 열한 체인은 `net=off`라 dhcpcd 자체가 안 뜨므로
안 건드리는 것이 맞다.

- [ ] Step 3: design에 "TS-M2가 실행으로 증명한 것" 절을 더한다

실측 16부터 이어서 번호를 매긴다. 최소한 이 여섯이다.

1. 이어 붙인 cpio 조각을 커널이 푸는가(결정 M2-D의 답)
2. `-o ntp_servers`를 준 dhcpcd가 그대로 사는가
3. init이 심은 파일을 읽는 데 걸린 시간
4. 안 닿는 주소가 부팅에 더한 시간(검사 22의 실제 숫자)
5. 전원을 끌 때 자식이 살아 있었는가 — `grace period expired`가 안 나온 것이
   결정 M1-A의 증명이다. 자식의 재시도 줄 수를 세서 그때 몇 번째였는지 적는다
6. 체인 단독 시간과 게이트 시간

위험 3의 상태도 함께 고친다. 여전히 미증명이지만 처방이 코드에 들어갔으므로
"M2가 argv에 넣었고, 남은 것은 실기계의 공유기가 실제로 option 42를 주는지
하나"로 줄어든다.

- [ ] Step 4: `HANDOFF.md`를 고친다

- 맨 위 제목과 "지금 어디인가"를 M2로
- TS 커밋 표에 M2 줄 둘(plan · 구현)
- "TS-M2가 알아낸 것 — 다음 세션이 먼저 읽을 다섯"
- "바로 다음에 할 것"을 TS-M3(zoneinfo와 `timezone` 키)로
- 게이트 현황의 숫자와 `net` 체인 단독 시간
- 명령 모음에 부팅 B의 반사실 한 덩이

- [ ] Step 5: 커밋

```bash
git status --short
```

`M`과 신규를 가르고, 신규가 `kernel/dhcpcd-hooks/30-tars-ntp`와 plan 파일
둘인지 확인한다. `out/*.img`는 `.gitignore`에 있어야 한다 — 없으면 셋째
이미지가 새로 잡히므로 여기서 본다.

커밋을 둘로 나눈다. plan 하나, 구현 하나. 구현 커밋의 메시지 첫 줄 후보는
`Read the ntp server the network handed us`.

## 실제로 돌린 것이 이 plan과 갈린 자리 다섯

plan을 그대로 밟되 실측이 다르면 실측이 답이다. 갈린 곳을 적어 둔다.

1. Task 0 Step 1의 기대값이 틀렸다. "PASS가 여섯 번"이라고 적었는데 실제로는
   `PASS` 줄이 둘이다 — 그것은 `zig build test`의 스텝 수이고, 모듈별 검사는
   devices 8 · sntp 6 · power 4 · storage 1 · environ 1로 따로 찍힌다.
2. Task 5가 부팅 B에서는 첫 회에 초록인데 체인이 다른 자리에서 죽었다.
   IN-M2의 검사 15이고, 조사해 보니 TS와 무관한 흔들리는 검사였다(실측 23).
   그래서 plan에 없던 일이 붙었다 — 체인을 열일곱 판 돌려 빈도를 재고, 실패한
   판의 시리얼 로그를 잡아 화면을 복원하고, 그 과정에서 둘째 흔들림(실측 22)
   까지 찾아 둘 다 고쳤다.
3. Task 6을 통째로 건너뛰었다. 결정 M2-D가 기댄 성질이 실제로 성립해서
   `make_initrd.sh`의 인터페이스를 안 늘렸다.
4. Task 7의 반사실을 `sd` 치환이 아니라 `grep -Fv` 한 줄로 만들었다. 지우려는
   줄에 작은따옴표와 `$`와 `>`가 다 들어 있어서 `sd -s`의 인자로 옮기는 것이
   따옴표 중첩 문제를 만든다 — 줄 하나를 통째로 빼는 것이 같은 결과이고 읽기
   쉽다.
5. Task 8 Step 2의 게이트가 한 판이 아니라 두 판이 됐다. 첫 판이 위의
   흔들리는 검사에서 죽었고, 고친 뒤 다시 돌렸다.

## 이 milestone이 증명하게 될 문장

"`ntp=dhcp`로 둔 기계가 DHCP가 알려 준 주소를 읽어서 묻는다. 그 주소가 어디에도
없어도 셸은 평소와 같은 시각에 뜬다."

그 이상이 아니다. 실기계의 공유기가 option 42를 실제로 주는지는 이 게이트가
영영 못 본다(design 위험 3). 그리고 사람이 읽는 시각이 되는 것은 M3의 일이다 —
이 milestone이 끝나도 게스트의 `date`는 UTC를 찍는다.
