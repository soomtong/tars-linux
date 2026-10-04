# TARS Boot Services — Design

접두사: SV

Status: 끝났다(2026-09-27) — M0~M2, 결정 9 · 실측 1~19. 열여섯번째 체인 `service/check.sh`(부팅 셋, 검사 열다섯).

관련 문서: `2026-08-01-tars-boot-foundation-design.md`(BF. 감독 루프의 뿌리) ·
`2026-09-27-tars-firewall-design.md`(FW. 여는 길과 "기본 꺼짐, 켜면 닫힘") ·
`2026-09-26-tars-loopback-design.md`(LB. `lo`가 늘 선다) ·
`2026-09-14-tars-inbound-network-design.md`(IN. 바깥에서 게스트 포트에 붙는 판정) ·
`docs/decisions/project_init_supervisor.md` · `docs/decisions/project_write_or_reuse.md` ·
`docs/decisions/project_measuring_tool_cost.md` ·
`docs/decisions/project_seeding_a_config_disk.md` ·
`docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

사람이 `/config/services.d/`에 실행 파일을 두면 `init`이 부팅 때 그것을 띄우고
terminal · 콘솔 셸과 같은 규칙으로 감독한다. 첫 세입자는 sshd다 — initrd에 구운
템플릿을 링크 한 줄로 켜고, 키는 `/config/ssh/`에 있어 부팅을 넘는다.

## 왜 지금인가

LB가 `lo`를, FW가 "들어오는 것 중 무엇을 받는가"를 세웠다. 받을 것을 고르는 층은
있는데 받을 쪽 — 부팅 때 떠서 계속 도는 프로그램 — 을 사람이 정하는 길이 없다.
지금 `init`이 띄우는 것은 전부 코드에 박혀 있다(terminal · 콘솔 셸 · nft ·
dhcpcd · chronyd).

2026-09-27에 사용자가 후보(패키지 매니저 · 부팅 때 뜨는 서비스 · IPv6) 중 이것을
골랐고 셋을 정했다 — 범용 메커니즘과 첫 세입자 sshd를 함께 한다 · 서비스 하나는
실행 스크립트 하나다 · 감독은 우리 감독자를 넓혀서 한다. 아래 결정 1 · 2 · 3이
그 셋이다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — 감독 목록은 크기 둘의 고정 배열이다

`init/src/main.zig`의 `children`은 `[_]Child{ terminal, console_shell }`이고
`supervise()`가 그것을 돈다. 규칙은 재시작 1초(`POLL_TIMEOUT_MS`) · 10초 안에
죽으면 "빨리" · 연속 셋이면 포기(`MAX_FAST_RESTARTS`)다. `Kind`는 제어 터미널을
잡는가와 로그 이름만 정한다. 힙이 없어서 argv도 길이 8로 고정이다.

### 확인 2 — dhcpcd · chronyd · nft는 목록 밖이다

`net.zig:174`의 주석대로 목록 밖에서 fork되고 `init`은 기다리지 않는다. 죽으면
`reaped orphan`으로 거둬질 뿐 다시 안 뜬다. 이 사이클은 그것을 바꾸지 않는다
(비목표 5).

### 확인 3 — 종료 경로는 이미 모든 프로세스를 덮는다

`power.zig:231`이 `kill(-1, sig)`로 SIGTERM · SIGHUP을 보내고 유예 3초 뒤
SIGKILL이다. 서비스가 목록에 들어와도 종료 쪽은 고칠 것이 없다.

### 확인 4 — 게스트에 사람이 띄울 데몬이 없다

`kernel/guest_tools.sh`의 65개 중 서버 역할은 `nc.traditional` 하나다. sshd는
없다.

### 확인 5 — 게스트의 사용자는 root 하나이고 셸은 `/bin/sh`(bash)다

`make_initrd.sh:315`의 `/etc/passwd`가 `root:x:0:0:root:/:/bin/sh` 한 줄이다.
`/bin/sh`는 언제나 bash다(`make_initrd.sh:161`). 비밀번호 필드가 `x`인데
`/etc/shadow`가 없으므로 비밀번호 로그인은 처음부터 불가능하다.

### 확인 6 — 사람이 적는 디렉터리의 선례가 둘 있다

`/config/chrony.d/`(TD)와 `/config/nftables.d/`(FW). 둘 다 "파일 하나가 항목
하나"이고, 디렉터리가 없어도 에러가 아니다.

## 결정

### 결정 1 — 범용 메커니즘과 sshd를 함께 한다

메커니즘만 하면 게이트는 `nc`로 판정할 수 있지만 사람이 쓸 것이 생기지 않는다.
sshd만 하면 dhcpcd · chronyd처럼 키 하나(`ssh=on`)와 배관이 하나 더 늘 뿐이다.
사용자가 둘을 함께 골랐다. 순서는 메커니즘이 먼저다(M1) — sshd는 그 위에 얹히는
첫 파일이고(M2), 그 파일에 `init` 코드가 한 줄도 안 든다는 것이 메커니즘의
증명이기도 하다.

### 결정 2 — 서비스 하나는 `/config/services.d/<이름>` 실행 파일 하나다

`init`은 그 파일을 파싱하지 않고 `execve`한다. shebang은 커널이 푼다. runit의
`run`과 같은 모양이다. 준비 작업(키 만들기 · 디렉터리 만들기)은 스크립트가 하고
끝에 `exec`한다.

대안은 "명령 한 줄을 적은 `.conf`"였다. 실행 비트가 필요 없다는 장점이 있지만
준비 작업을 못 하므로 sshd 호스트 키 생성 같은 것이 `init`의 Zig 코드로
들어온다. 그러면 결정 1의 "sshd에 `init` 코드가 안 든다"가 깨진다. 사용자가
실행 파일 쪽을 골랐다. 실행 비트를 잊는 실수는 결정 4의 사전 확인이 한 줄로
알려 준다.

### 결정 3 — 감독은 우리 감독자를 넓혀서 한다

`Kind`에 `.service`를 더하고, `services.d`에서 읽은 항목을 `children` 배열에서
terminal · 콘솔 셸 뒤에 붙인다. 규칙은 그 둘과 글자 그대로 같다 — 재시작 1초 ·
빨리 셋이면 포기. 탈출로(`rescue`)는 없다.

대안은 runit의 `runsvdir`를 자식 하나로 감독하는 것이었다. 우리 코드는 0줄에
가깝지만 형식이 runit의 디렉터리/`run`이 되고, 감독자가 두 자리에 선다.
`project_write_or_reuse`의 기준으로 이 자리는 직접 짤 자리다 — 감독자는 BF 이래
이 저장소가 이미 가진 코드이고, 고정 목록 둘을 설정에서 온 가변 목록으로 바꾸는
것이 PID 1을 다시 읽는 일이다. 사용자가 이쪽을 골랐다.

### 결정 4 — 읽는 것은 부팅 때 한 번이고, 실패는 부팅을 안 세운다

- 자리. `main()`에서 `clock.start` 뒤, `supervise` 직전이다. 서비스가 뜨는
  시점에 방화벽 규칙과 dhcpcd가 이미 서 있다 — FW 결정 5의 "규칙이 서기 전에
  받는 틈이 없다"가 서비스에도 이어진다.
- 읽는 법. `getdents64`로 읽고 이름순으로 정렬한다 — 시작 순서가 부팅마다 같다.
  `.`으로 시작하는 이름은 건너뛴다. 심볼릭 링크는 따라간다(결정 6의 켜는 법이
  링크다). 부팅 뒤에 바뀐 것은 다음 부팅에 반영된다 — `tars.conf`와 같은 정책이다.
- 사전 확인. 일반 파일이 아니거나 실행 비트가 없으면 목록에 안 넣고 한 줄을
  찍는다(`tars-init: service foo is not executable, skipped`). `resolveShell`과
  같은 생각이다 — 그냥 넘기면 execve가 127로 셋 죽고 포기되며 원인은 로그 깊숙이
  묻힌다.
- 한도. 서비스는 최대 8개다. 힙이 없어서 `children`의 크기를 컴파일 타임에
  정한다. 아홉째부터는 한 줄씩 찍고 뺀다. 이름도 길이 한도를 둔다(M1 plan이 정한다).
- 자식 쪽. argv는 `{path}` 하나, envp는 다른 자식과 같은 블록(`PATH` · `TZ`)이다.
  `setsid`로 자기 세션을 갖고 콘솔을 제어 터미널로 안 잡는다. stdout · stderr는
  물려받은 콘솔이다 — 서비스 출력이 시리얼 로그에 남는다.
- 로그. `started service sshd (pid N, /config/services.d/sshd)`. 포기는
  `giving up on service sshd after 3 fast exits`.

경우별 결과.

| 경우 | 결과 |
|---|---|
| `/config` 안 붙음 · `services.d` 없음 | 서비스 0개, 로그 한 줄 |
| 실행 비트 없음 · 디렉터리 · 장치 | 사전 확인에서 제외, 한 줄 |
| shebang이 틀림 · 곧바로 죽는 스크립트 | 1초 재시작 셋 → `giving up on service X` |
| exec 없이 매달리는 스크립트 | 살아 있으므로 그대로 둔다(terminal과 같다) |
| sshd에 키 파일이 없음 | sshd는 뜨고 로그인만 실패한다. 서비스 자체는 건강하다 |
| 8개 초과 | 아홉째부터 한 줄씩, 제외 |

어느 서비스도 부팅 경로에서 동기로 기다리지 않는다. `supervise`가 fork만 하므로
셸은 지금과 같은 시각에 뜬다.

### 결정 5 — 기본은 아무것도 안 뜬다

`services.d`가 비면 아무것도 안 뜬다. `init`은 `services.d`에 파일을 seed로
심지 않는다 — 심으면 모든 기계에서 그 서비스가 켜진다. FW 결정 1의 "기본 꺼짐,
켜면 닫힘"과 같은 방향이다. `tars.conf`에 켜고 끄는 키도 두지 않는다 — 디렉터리가
곧 스위치다.

### 결정 6 — sshd는 initrd의 템플릿이고, 사람이 링크로 켠다

- 게스트에 sshd와 ssh-keygen, 그리고 그 둘의 재귀 `DT_NEEDED`가 들어간다. 비용은
  M0이 `project_measuring_tool_cost` 절차로 잰다.
- 저장소에서 오는 파일.
  - `/etc/ssh/sshd_config` — `HostKey /config/ssh/ssh_host_ed25519_key` ·
    `AuthorizedKeysFile /config/ssh/authorized_keys` · `PasswordAuthentication no` ·
    `PermitRootLogin prohibit-password` · `UsePAM no`.
  - `/etc/tars/services/sshd` — 호스트 키가 없으면 `ssh-keygen -t ed25519`로 한
    번 만들고 `exec sshd -D -e`.
  - `/etc/passwd`에 privilege separation 사용자 `sshd`, 그리고 빈 `/run/sshd`.
- 켜는 법(사람이 한다). `ln -s /etc/tars/services/sshd /config/services.d/`와
  `/config/ssh/authorized_keys`에 공개 키.
- 인증은 키 하나다. root에 비밀번호가 없으므로(확인 5) 비밀번호 로그인은 처음부터
  없다.
- 호스트 키가 `/config/ssh/`에 있어 부팅을 넘는다 — 재부팅할 때마다 클라이언트가
  "호스트 키가 바뀌었다"를 보지 않는다.
- 방화벽. `firewall=on`이면 22번은 `/config/nftables.d/ssh.nft`를 더하기 전까지
  닫혀 있다. 의도된 동작이고 가이드에 적는다.

### 결정 7 — 게이트는 열여섯번째 체인 `service/check.sh`다

설정 디스크는 `debugfs`로 심는다(`project_seeding_a_config_disk`). 실행 비트와
심볼릭 링크까지 `debugfs`로 되는지는 M0이 잰다.

- 부팅 A(메커니즘). 서비스 넷을 심는다.
  - `echo` — `nc`로 받은 바이트를 돌려주는 스크립트. 뜨고, 호스트가 hostfwd로 그
    바이트를 되읽는다.
  - `die` — 곧바로 죽는다. 재시작 셋 뒤 포기.
  - `noexec` — 실행 비트 없음. 사전 확인에서 제외.
  - `.hidden` — 무시.
  - 시작 순서가 이름순이다. 콘솔 셸이 평소대로 뜬다 — 서비스가 부팅을 안 세웠다는
    판정이다.
- 부팅 B(sshd). 템플릿 링크와 `authorized_keys`를 심고, devcontainer의 `ssh`가
  로그인해 `echo tars-ssh-ok`의 출력을 읽는다. 음성으로 등록 안 된 키는 거절된다.
- 부팅 C(영속성). 같은 디스크로 다시 떠서 호스트 키 지문이 B와 같다 — 키를 다시
  안 만들었다는 증명이다.
- `firewall=on` 조합(22번이 `ssh.nft` 전에는 닫혀 있다)을 B나 C에 M2에서 더한다.
- 새 QEMU 호출은 `-netdev`를 명시한다(`require_explicit_nic`).

### 결정 8 — ssh로 붙는 터미널의 terminfo를 흔한 것 몇 개 더 넣는다

SV-M0 실측 7 뒤에 사용자가 정했다(2026-09-27). 게스트에 없는 `TERM`에서 `less`가
멈추는 것을 가이드가 아니라 게스트에서 푼다. `ncurses-term` 통째(1,802개 · 12MB)는
안 넣는다 — "무엇이 왜 필요한가"가 흐려진다(`make_initrd.sh`의 terminfo 주석과 같은
판단). 목록과 `xterm-ghostty`를 만드는 법은 M2 plan이 실측으로 정한다 — Debian의
`ncurses-term`에는 `ghostty`는 있어도 Ghostty가 실제로 보내는 이름 `xterm-ghostty`가
없다.

### 결정 9 — ssh 세션은 `tars.conf`의 `shell`과 `init`의 env를 따른다

같은 날 사용자가 정했다. 비목표 7을 목표로 옮긴다. 콘솔에서 쓰는 셸과 ssh로 붙은
셸이 같은 셸 · 같은 rc · 같은 히스토리 · 같은 `TZ`여야 한다. 방법(`passwd`의 셸 자리 ·
sshd의 `SetEnv`)은 M2 plan이 실측으로 정한다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- SV-M0 — 실측, 코드 0줄. sshd · ssh-keygen의 비용. 게스트에서 sshd를 손으로
  띄워 필요한 것(privsep 사용자 · `/run/sshd` · StrictModes · `TERM`)을 잰다.
  `debugfs`가 실행 비트와 심볼릭 링크를 만드는가.
- SV-M1 — 메커니즘. `init/src/services.zig` · `Kind`와 `children` 확장 · 체인
  `service/check.sh`의 부팅 A.
- SV-M2 — sshd. 패키지 · `sshd_config` · 템플릿 · `passwd` 줄 · 부팅 B · C ·
  방화벽 조합 · 가이드의 절.

## 비목표

1. 서비스 핫 리로드. 부팅 뒤에 바뀐 `services.d`는 다음 부팅에 반영된다.
2. 서비스 사이의 의존 · 순서 제약. 이름순으로 띄울 뿐이다.
3. 서비스 로그를 파일로 남기는 것. 출력은 콘솔(시리얼 로그)로 간다.
4. (CT가 목표로 옮겼다 — `2026-09-27-tars-service-control-design.md`) 서비스를 멈추고 다시 띄우는 명령.
5. dhcpcd · chronyd를 감독 목록에 넣는 것. 그 둘은 지금처럼 목록 밖이다.
6. 비밀번호 로그인과 root 아닌 사용자.
7. (결정 9로 옮겼다) ssh 세션의 로그인 셸이 `tars.conf`의 `shell`을 따르는 것.
8. 실기 LAN에서 다른 컴퓨터가 붙는 것. 게이트는 SLIRP 안에서만 판정한다(IN 비목표
   3 · FW 비목표 3과 같다).

## 위험

### 위험 1 — sshd가 끌고 오는 라이브러리가 크다

`curl`이 그랬듯 재귀 `DT_NEEDED`가 예상보다 클 수 있다. M0에서 재고, 크면 M1에
들어가기 전에 사용자와 다시 정한다.

### 위험 2 — StrictModes가 `/`나 `/config/ssh`의 권한을 거절한다

root의 홈이 `/`이고 `authorized_keys`가 홈 밖(`/config/ssh/`)에 있다. sshd가
경로의 소유자와 권한을 따지므로 ext2에 심은 권한이 맞아야 한다. M0이 잰다.

### 위험 3 — 클라이언트의 `TERM`에 맞는 terminfo가 게스트에 없다

ssh는 클라이언트의 `TERM`을 넘긴다. 게스트의 terminfo는 우리 터미널용으로 골라
넣은 것이라(`project_guest_environment`) 호스트 터미널의 `TERM`이 없으면 `less` ·
`vim` 같은 것이 깨진다. M0이 흔한 값(`xterm-256color`)을 확인한다.

### 위험 4 — 서비스 수만큼 로그 노이즈가 는다

`die`처럼 곧바로 죽는 서비스는 재시작 셋의 줄을 찍는다. BF 체인이 terminal의
재시작 수를 정확히 3으로 세듯, 다른 체인이 로그 줄 수를 세는 자리가 있으면 거기에
영향이 없어야 한다. 서비스는 `/config`의 파일에서만 오므로 설정 디스크가 없는
체인에는 한 줄(서비스 0개)만 늘어난다. 그 한 줄을 세는 체인이 있는지 M1에서 본다.

### 위험 5 — 이 사이클이 증명하는 것보다 넓게 읽힌다

게이트가 증명하는 것은 "SLIRP 안에서 sshd에 키로 로그인된다"다. 실기 LAN에서
노출되는 sshd의 보안(무차별 대입 · 키 관리)은 이 사이클이 판정하지 않는다. 가이드는
`firewall=on`과 함께 쓰라고 적는다.

## SV-M0이 실행으로 증명한 것

2026-09-27. plan은 `plans/2026-09-27-tars-boot-services-sv-m0.md`. 코드와 커널
설정은 한 줄도 안 바뀌었다. 부팅은 둘을 돌렸다 — 첫 회가 측정 6의 한 갈래에서
매달려 멈췄고(실측 7), 하네스에 `timeout`을 더하고 디스크를 새로 구워 다시 돌렸다.
아래 로그는 둘째 회의 것이고, 측정 2 ~ 5는 두 회가 지문 말고는 같다.

### 실측 1 — sshd가 initrd에 더하는 것은 바이너리 넷과 라이브러리 일곱, 5,459,664바이트다

패키지는 `openssh-server` 1:10.0p1-7+deb13u4다(실행하면 `OpenSSH_10.0p2
Debian-7+deb13u4, OpenSSL 3.5.7`). 닫힘이 패키지 75개였는데, `apt-get download`에
한 번에 넘기면 `Architecture: all`인 것(`runit-helper` · `ucf` 등)이 `:amd64` 후보가
없어 목록 전체가 멈춘다 — 하나씩 받아야 한다.

실행 파일 넷. sshd는 연결마다 `sshd-session`을, 인증에 `sshd-auth`를 exec한다(10.0부터
셋으로 갈렸다). 둘의 경로 `/usr/lib/openssh/`는 sshd에 컴파일되어 있다.

```
SVM0-BIN sshd 568224
SVM0-BIN ssh-keygen 567744
SVM0-BIN sshd-session 1122368
SVM0-BIN sshd-auth 1076640
```

재귀 `DT_NEEDED`는 21개이고 `MISSING`은 없다. 그중 14개가 이미 initrd에 있다 —
걱정했던 Kerberos 계열(`libgssapi_krb5` · `libkrb5` · `libk5crypto` ·
`libkrb5support` · `libcom_err` · `libkeyutils`)과 `libcrypto` · `libselinux` ·
`libpcre2-8` · `libzstd`까지 curl과 git이 먼저 들여놓았다. 새 것은 일곱이다.

```
26616 libwtmpdb.so.0
30632 libcap-ng.so.0
47976 libwrap.so.0
67584 libpam.so.0
174008 libaudit.so.1
206776 libcrypt.so.1
1571096 libsqlite3.so.0
```

합이 2,124,688바이트이고 그 74%가 `libsqlite3` 하나다. `sshd-session`이
`libwtmpdb`(로그인 기록)를 부르고 그것이 sqlite를 부른다. 바이너리 넷(3,334,976)과
더해 5,459,664바이트, 압축 전 기준이다. 지금 `initrd.cpio`(압축)가 43,799,286바이트다.

위험 1은 닫힌다 — M2가 그대로 넣는다.

### 실측 2 — `debugfs`가 실행 비트와 링크를 만든다

빈 이미지에서 `write`는 원본 파일의 모드를 따르고(644 → `Mode: 0644`), `sif <이름>
mode 0100755`가 `0755`로 바꾸고, `symlink link /config/svc/execd`가 `Type: symlink`를
만든다. 셋 다 `User: 0 Group: 0`이다. 게스트에서 본 모양이 같다.

```
SVM0-STAT execd -rwxr-xr-x root:root regular file ->
SVM0-STAT link lrwxrwxrwx root:root symbolic link -> /config/svc/execd
```

`mkfs.ext2 -d`는 원본의 모드를 그대로 싣는다(`hello` 755 · `noexec` 644). 소유자는
컨테이너 안에서 `chown -R 0:0`한 뒤 구웠다 — macOS 바인드 마운트의 uid를 싣지 않으려고.

### 실측 3 — `/config`에서 스크립트가 직접 실행된다

```
SVM0-MOUNT /dev/vda /config ext2 rw,sync,nosuid,nodev,relatime,errors=continue 0 0
SVM0-EXEC hello rc=0 out=[SVM0-RAN hello /config/svc/hello 94;]
SVM0-EXEC noexec rc=126 out=[/config/svm0.sh: line 13: /config/svc/noexec: Permission denied;]
SVM0-EXEC execd rc=0 out=[SVM0-RAN execd /config/svc/execd;]
SVM0-EXEC link rc=0 out=[SVM0-RAN execd /config/svc/link;]
```

`noexec`가 옵션에 없다(`mountConfig`가 `NOSUID | NODEV`만 준다). shebang `#!/bin/sh`를
커널이 풀어 bash가 돈다. 링크로 부르면 `$0`이 링크의 경로다 — 결정 6의 템플릿을
링크로 켜도 스크립트는 자기가 어디서 불렸는지 안다. 실행 비트가 없으면 execve가
`EACCES`이고 셸은 126을 낸다. `init`에서는 execve의 반환값이 그 errno다 — M1의
사전 확인이 이 경우를 미리 잡고, 못 잡아도 자식이 127로 셋 죽고 포기된다.

결정 2가 그대로 선다.

### 실측 4 — sshd는 호스트 키 · privsep 사용자 · `/run/sshd` 셋을 요구한다

`sshd -t`를 하나씩 채우며 돌렸다.

```
SVM0-TEST bare rc=1 err=[Unable to load host key: /config/ssh/ssh_host_ed25519_key;sshd: no hostkeys available -- exiting.;]
SVM0-TEST key rc=255 err=[Privilege separation user sshd does not exist;]
SVM0-TEST user rc=255 err=[Missing privilege separation directory: /run/sshd;]
SVM0-TEST rundir rc=0 err=[]
SVM0-LISTEN 1 pid=189
```

사용자 줄은 `sshd:x:100:65534::/run/sshd:/usr/sbin/nologin`, 그룹은
`nogroup:x:65534:`를 더했다. `/usr/sbin/nologin`은 게스트에 없지만 sshd는 그 자리를
실행하지 않으므로 상관없다. 이 셋이 전부이고, 그 뒤에는 PAM · shadow 없이
(`UsePAM no`, `/etc/shadow` 없음) 키 로그인이 된다(실측 5).

M2가 initrd에 구울 목록 — `passwd` · `group`에 두 줄, 빈 `/run/sshd`(755). 호스트 키는
템플릿이 만든다.

### 실측 5 — 키 로그인은 되고 모르는 키는 거절된다. StrictModes는 root 그룹 쓰기를 봐준다

```
SVM0-SCAN 256 SHA256:HGvcsYznQ2GeqBw0iRXqGM5oboaxtQIrtEo24g3dMWg [127.0.0.1]:45422 (ED25519)
SVM0-FPR 256 SHA256:HGvcsYznQ2GeqBw0iRXqGM5oboaxtQIrtEo24g3dMWg root@(none) (ED25519)
SVM0-LOGIN good rc=0 ms=265 out=[...;sh|/bin/sh|dumb|/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin|0;xterm;xterm-256color;]
SVM0-LOGIN bad rc=255 ms=158 out=[root@127.0.0.1: Permission denied (publickey).;]
SVM0-PERM 770 root:root;600 root:root;
SVM0-LOGIN perm rc=0 ms=283 out=[...]
```

바깥의 `ssh-keyscan` 지문과 게스트의 `ssh-keygen -l` 지문이 같다 — 호스트가 붙은
상대가 우리 sshd다. 로그인은 0.3초 안이다.

`/config/ssh`를 770(그룹 쓰기)으로 열어도 로그인이 됐다. 위험 2가 예상한 거절이
안 났다. Debian의 openssh에는 `user-group-modes` 패치가 있어서, 그룹 쓰기 비트가
있어도 그 그룹의 구성원이 사용자 하나뿐이면 봐준다 — `root` 그룹의 구성원은 root
하나다. 그래서 이 게스트에서 StrictModes가 막는 것은 다른 사용자 소유이거나 모두
쓰기(`o+w`)인 경우다. M2 게이트는 StrictModes 음성 검사를 두지 않고, 가이드는
`chmod 700`을 권한다. 위험 2는 닫힌다.

sshd 로그(`-e`)에는 세션마다 두 줄의 소음이 섞인다.

```
SVM0-SSHD lastlog_openseek: Couldn't stat /var/log/lastlog: No such file or directory
SVM0-SSHD syslogin_perform_logout: logout() returned an error
```

`/var/log`가 게스트에 없어서다. 로그인에는 영향이 없다. M2가 `sshd_config`의
`PrintLastLog no`로 없앨 수 있는지, 아니면 그대로 둘지를 정한다.

### 실측 6 — ssh 세션은 `sh`로 불린 bash이고 `PATH`는 sshd의 기본값이다

`$0`이 `sh`, `$SHELL`이 `/bin/sh`(`passwd`의 그 자리), 비대화형이라 `TERM`은 `dumb`,
uid 0. `PATH`는 `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`이다 —
`init`이 짓는 `/usr/bin:/bin`이 아니라 sshd가 컴파일된 기본값이다. 두 PATH 모두
게스트에서 `/usr/bin`을 포함하므로 도구는 이름으로 불린다. `TZ` · `XDG_*` ·
`HISTFILE` 같은 `init`의 env는 ssh 세션에 없다 — sshd는 자기 env를 세션에 안 넘긴다.
비목표 7(로그인 셸이 `tars.conf`를 따르는 것)과 같은 자리의 일이고, M2에서 사용자와
함께 본다.

### 실측 7 — terminfo가 없는 `TERM`에서 `less`가 멈춰 기다린다

```
SVM0-PTYRC xterm-256color 0
SVM0-PTY xterm-256color out=[xterm-256color;[?1h=x;[K[?1l>rc=0;Connection to 127.0.0.1 closed.;]
SVM0-PTYRC xterm-ghostty 124
SVM0-PTY xterm-ghostty out=[xterm-ghostty;WARNING: terminal is not fully functional;Press RETURN to continue Connection to 127.0.0.1 closed.;]
```

`-tt`로 pty를 받으면 클라이언트의 `TERM`이 그대로 온다. 게스트의 terminfo는
`xterm` · `xterm-256color` 둘뿐이라, 그 밖의 이름에서 `less`는 경고를 찍고 RETURN을
기다린다. 첫 회는 여기서 하네스가 매달렸다(15초 `timeout`이 124로 잘랐다). 위험 3이
실제로 난다. 사람이 Ghostty 같은 터미널에서 ssh로 붙으면 첫 `less` · `git log`에서
이것을 본다.

처방 후보 — 게스트에 terminfo를 더 넣는다(흔한 이름 몇 개, 또는 `ncurses-term`의 것),
가이드에 `TERM=xterm-256color ssh …`를 적는다, 또는 클라이언트 쪽 `SetEnv`. M2 plan에서
사용자와 정한다.

### M0이 M1 · M2에 넘기는 것

- M1 — 결정 2 · 4가 바뀌지 않는다. 체인의 디스크는 `mkfs.ext2 -d`로 모드를 싣고,
  `debugfs`의 `sif` · `symlink`로 덧댈 수 있다. 실행 비트 없는 파일의 실패는 `EACCES`다.
- M2 — sshd 넷 · 라이브러리 일곱(`make_initrd.sh`의 `copy_lib_deps`가 따라간다),
  `sshd-session` · `sshd-auth`는 `/usr/lib/openssh/`에, `sshd`는 `usr/sbin/sshd:usr/bin/sshd`로.
  `passwd` · `group` 두 줄과 `/run/sshd`. devcontainer에 `openssh-client`(하네스의
  `ssh` · `ssh-keyscan`). 사용자와 정할 것 둘 — terminfo(실측 7)와 ssh 세션의 셸 · env(실측 6).

## SV-M1이 실행으로 증명한 것

2026-09-27. plan은 `plans/2026-09-27-tars-boot-services-sv-m1.md`. 코드는 커밋 둘 —
`4505f22`(`services.zig` · `services_test.zig` · `build.zig`)와 `f1bff34`(`main.zig`).

### 실측 8 — 호스트 검사가 첫 컴파일에 초록이고, 로그 문구가 거기서 먼저 보인다

`services_test`는 이름 판정 · 정렬 · 없는 디렉터리 · 실제 디렉터리 넷을 본다. 실제
디렉터리의 열여섯 항목에서 `discover`가 찍은 줄이 plan M1-E의 문구 그대로다.

```
tars-init: service name bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb is longer than 32 bytes, skipped
tars-init: service k-broken cannot be read (errno 2), skipped
tars-init: service m-noexec is not an executable file, skipped
tars-init: service n6 ignored, at most 8 services
tars-init: service subdir is not an executable file, skipped
tars-init: service z-last ignored, at most 8 services
tars-init: 8 services from /tmp/tars-services-test/services.d
```

끊어진 링크는 `statx`가 `ENOENT`(2)다. 디렉터리(`subdir`)가 실행 파일로 안 잡히는 것이
`access(X_OK)` 대신 `statx`를 쓴 이유(M1-B)의 실제 모양이다. Zig 0.16의 API는 plan에
적은 이름(`getdents64` · `statx` · `linux.S.ISREG` · `std.sort.insertion`) 그대로였다.

`init` 바이너리는 3,581,480 → 3,619,968바이트(+38,488)다.

### 실측 9 — 체인의 첫 판은 체인 쪽 실수로 빨갰다. `#!/bin/bash`는 게스트에 없다

```
tars-init: started service d-link (pid 76, /config/services.d/d-link)
tars-init: execve /config/services.d/d-link failed
tars-init: service d-link exited (pid 76, status 127, lived 1s)
...
tars-init: giving up on service d-link after 3 fast exits
```

체인이 심은 `linked.sh`의 shebang이 `#!/bin/bash`였다. 게스트의 `/bin`에는 `sh` 하나만
산다(`make_initrd.sh:81`) — 커널이 인터프리터를 못 찾아 execve가 `ENOENT`다. 사전
확인은 링크 끝이 실행 파일인 것만 보므로 통과했다. `#!/bin/sh`로 고쳤다.

이것은 사람이 서비스 스크립트를 쓸 때 그대로 밟을 수 있는 자리다. 지금 로그에는
`execve … failed`만 있고 errno가 없어서 "무엇이 없는가"가 안 보인다 — M2의 가이드가
`#!/bin/sh`를 쓰라고 적는다. execve 줄에 errno를 더하는 것은 M2에서 함께 본다.

### 실측 10 — 체인이 검사 여덟으로 초록이다

```
init picked three services from /config/services.d
c-noexec was skipped before it could fail
.hidden left no trace
a-greet, b-die, d-link started in name order after the console shell
b-die started three times and was given up on
d-link ran through its link, leads its own session and reads EOF on stdin
a-greet answered from outside with init's PATH
a-greet, d-link and the console shell stayed up
SV chain PASS
```

`a-greet`이 바깥에 보낸 줄이 `sv-greet /config/services.d/a-greet /usr/bin:/bin`이다 —
init의 env 블록이 서비스까지 온다. 서비스의 출력(`sv-linked …`)은 콘솔로 가서 시리얼
로그에 남는다.

### 실측 11 — 반사실 셋이 겨냥한 검사에서 겨냥한 문구로 죽었다

| 반사실 | 호스트 검사 | 부팅 |
|---|---|---|
| `sortNames` 호출을 지운다 | `path …/z-last, want …/a-first` | 검사 4 — `shell=276 a=279 b=278 d=277` |
| `check`가 늘 `.ok` | `path …/m-noexec, want …/n0` | 검사 1 — `4 services from`, `c-noexec exited (… status 127 …)` |
| `.service => {}` (세션 · stdin 없음) | (해당 없음) | 검사 6 — `sid=0 pid=39 stdin-rc=142` |

부팅 쪽을 보려고 앞의 둘은 체인의 `zig build test` 단계를 잠시 막았다 — 호스트
검사와 부팅 검사가 각각 따로 선다.

정렬이 없을 때의 순서 `d · b · a`는 디스크에 쓴 순서(`.hidden` · `d-link` · `c-noexec` ·
`b-die` · `a-greet`) 그대로다. ext2의 `getdents64`가 만든 순서를 돌려준다는 실측이다.

세션을 안 떼면 `sid=0`이다 — PID 1이 있는 커널의 첫 세션이다. stdin이 콘솔이면 `read -t 1`이
1초를 채우고 142(128 + SIGALRM)다. 콘솔 셸과 콘솔 입력을 나눠 읽는 상태가 바로 이것이다.

### 실측 12 — 이웃 다섯이 그대로 초록이다

boot(31초) · device(14초) · machine(16초) · config(139초) · firewall(46초), 전부 PASS.
설정 디스크가 없는 boot 체인에는 `tars-init: no /config/services.d, 0 services` 한 줄이
늘었고, 그 체인이 세는 terminal 재시작 3은 그대로다(`label`이 `"terminal"` 글자
그대로라서). 위험 4는 닫힌다. 루트 게이트는 M2가 끝날 때 돈다.

### M1이 M2에 넘기는 것

- sshd 템플릿은 `#!/bin/sh`로 쓴다(실측 9).
- 체인은 부팅 A 하나다. M2는 같은 체인에 부팅 B · C(sshd)를 더한다 — 포트는 45483부터.
- execve 실패 줄에 errno가 없다. 사람이 쓴 서비스가 127로 죽을 때 원인이 안 보인다.

## SV-M2 착수 전 실측 — 결정 8 · 9의 방법

2026-09-27. 하네스는 M0의 것을 넓힌 `/tmp/sv/boot2.sh`와 게스트 스크립트 `svm2.sh`이고
(커밋 안 함), 코드는 안 바뀌었다. `shell=zsh`로 떠서 M0처럼 sshd를 세운 뒤, `init`이
M2에서 할 일을 게스트 안에서 손으로 했다.

### 실측 13 — `passwd`의 셸 자리와 `SetEnv` 한 줄이면 ssh 세션이 콘솔과 같다

손으로 한 것 둘. `/etc/passwd`의 root 줄 끝을 `/usr/bin/zsh`로 바꾸고, 콘솔 셸이 물려받은
env를 sshd의 drop-in 한 줄로 옮겼다(`sshd_config` 맨 위에 `Include
/etc/ssh/sshd_config.d/*.conf`).

```
SVM2-DROPIN SetEnv TZ="UTC" XDG_DATA_HOME="/config/xdg" HISTFILE="/config/zsh_history" HISTSIZE="5000" SAVEHIST="5000" PATH="/usr/bin:/bin"
SVM2-PASSWD root:x:0:0:root:/:/usr/bin/zsh
SVM2-TEST rc=0 err=[]
```

비대화형 세션(`ssh host '명령'`)의 `$0|$SHELL|TZ|PATH|HISTFILE|SAVEHIST|XDG_DATA_HOME`:

```
zsh|/usr/bin/zsh|UTC|/usr/bin:/bin|/config/zsh_history|5000|/config/xdg
```

`SetEnv`의 `PATH`가 sshd의 컴파일된 기본값(실측 6)을 이긴다. 대화형 세션(`-tt`에 줄을
흘려 넣었다)에서는 rc가 읽혔고(`type ls` → `ls is an alias for eza` — seed rc의 별칭이다),
친 명령이 `/config/zsh_history`에 남았다(`grep -c` → 1, 끝 줄 `echo svm2-hist-$((6*7))` ·
`exit`). 콘솔과 ssh가 같은 히스토리 파일을 쓴다.

그래서 M2에서 `init`이 할 일은 둘이다 — 부팅 때 `/etc/passwd`의 root 셸 자리를
`resolveShell`의 결과로 쓰고, env 블록의 `TZ` · `XDG_DATA_HOME` · 셸별 히스토리 env ·
`PATH`를 `/etc/ssh/sshd_config.d/`의 파일 하나에 `SetEnv`로 쓴다. 둘 다 initramfs의
루트(쓸 수 있다)에 쓰고 `/config`에는 안 쓴다 — 부팅마다 설정에서 새로 나온다.

### 실측 14 — `xterm-ghostty`는 `tic`으로 이름 하나를 더해 만든다

Debian `ncurses-term` 6.5+20250216에는 `ghostty` · `kitty`는 있어도 두 터미널이 실제로
보내는 `xterm-ghostty` · `xterm-kitty`가 없다. `infocmp -x`로 풀어 첫 줄에 이름을 더하고
`tic -x`로 다시 굽는다.

```
xterm-ghostty|ghostty|Ghostty terminal emulator,
xterm-kitty|kitty|KovId's TTY,
-rw-r--r-- 3753 ti/x/xterm-ghostty      lrwxrwxrwx ti/g/ghostty -> ../x/xterm-ghostty
-rw-r--r-- 3596 ti/x/xterm-kitty        lrwxrwxrwx ti/k/kitty -> ../x/xterm-kitty
```

게스트에 넣고 `-tt`로 `less`를 돌린 결과 — 셋 다 경고 없이 `rc=0`이다(M0 실측 7에서
`xterm-ghostty`는 RETURN을 기다리며 매달렸다).

```
SVM2-PTY xterm-ghostty rc=0 out=[...;xterm-ghostty;[?1h=x;[K[?1l>rc=0;...]
SVM2-PTY xterm-kitty rc=0 out=[...;xterm-kitty;[?1hx;[K[?1lrc=0;...]
SVM2-PTY alacritty rc=0 out=[...;alacritty;[?1h=x;[K[?1l>rc=0;...]
```

파일 하나가 4KB 안팎이다. `tmux-256color` · `screen-256color`는 sysroot의
`ncurses-base`에 이미 있다. `tic`은 컨테이너(arm64)의 것을 써도 결과가 아키텍처와
무관하다(terminfo는 바이트 순서가 정해진 형식이다).

### 실측 15 — 호스트 키가 바뀌면 클라이언트가 이렇게 말한다

이 부팅의 디스크는 호스트 키 없이 새로 구웠고, 하네스의 `known_hosts`에는 M0 둘째 회의
키가 남아 있었다. 모든 연결의 앞에 `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`가
찍혔다(`StrictHostKeyChecking=no`라 연결은 됐다). 결정 6이 키를 `/config/ssh/`에 두는
이유가 이 한 화면이다 — 부팅 C의 판정이 이것이 안 나오는 것이다.

## SV-M2가 실행으로 증명한 것

2026-09-27. plan은 `plans/2026-09-27-tars-boot-services-sv-m2.md`. 커밋 — `806010b`(`login.zig`) ·
`fc6a5cf`(`main.zig`) · `70adb49`(Dockerfile 층 11 · `guest_tools.sh` · `make_initrd.sh`) ·
`c89157d`(체인 부팅 B · C) · `a7a6cf2`(가이드).

### 실측 16 — 이미지는 캐시로 1분 15초, initrd는 압축 2,470,635바이트가 늘었다

Dockerfile 층 11(패키지 열)과 기본 apt의 `openssh-client`를 더해 이미지를 다시 구웠다.
`initrd.cpio`가 43,799,286 → 46,269,921바이트다. 들어간 것 — 실행 파일 넷(`usr/bin/sshd` ·
`usr/bin/ssh-keygen` · `usr/lib/openssh/sshd-session` · `sshd-auth`), 라이브러리 일곱(M0 실측
1 그대로), `etc/ssh/sshd_config` · `sshd_config.d/` · `etc/tars/services/sshd` · `run/sshd`,
terminfo 일곱과 링크 둘(`g/ghostty` · `k/kitty`는 `tic`이 이름 둘을 한 파일로 구운 흔적이다).

`login_test`는 첫 컴파일에 초록이었다. `std.Io.Writer.fixed`는 0.16에서 그 이름 그대로다.

### 실측 17 — 체인이 부팅 셋 · 검사 열다섯으로 첫 판에 섰다

```
=== boot B: sshd linked, firewall=on without ssh.nft ===
init set root's shell to zsh and wrote sshd's env
the linked template started sshd and generated SHA256:Fg4YxVAIU5spnfXeiAlwAYtbvowsjoNahiP03+8gpbc
with firewall=on and no ssh.nft, port 22 stayed shut
=== boot C: the same disk plus nftables.d/ssh.nft ===
the host key survived the reboot and is what the client sees
a registered key logged in to zsh with init's PATH and history
an unregistered key was refused
less ran under TERM=xterm-ghostty without a warning
SV chain PASS
```

사람이 한 것은 링크 하나와 공개 키 하나, 그리고 C 앞의 `ssh.nft` 한 줄이다. `init`에
sshd를 아는 코드는 없다 — 결정 1의 "sshd에 `init` 코드가 안 든다"가 선다(`login.zig`는
sshd가 아니라 로그인 셸 · env를 쓴다).

### 실측 18 — 반사실 다섯. 하나는 겨냥한 검사보다 앞에서 죽었다

| 반사실 | 빨간 검사 |
|---|---|
| `login.apply` 호출을 지운다 | 검사 9 — `init did not write the login shell and the ssh env` |
| 템플릿의 `if [ ! -e "$key" ]`를 `if true` | 부팅 C의 `sshd never listened` (검사 12보다 앞) |
| 같은 자리를 `rm -f "$key" "$key.pub"; if true` | 검사 12 — `the host key was generated again on the second boot` |
| 부팅 B에도 `ssh.nft` | 검사 11 — `firewall=on without ssh.nft still let an ssh login through` |
| terminfo 굽는 루프를 지운다 | 검사 15 — `less still warns under TERM=xterm-ghostty` |

둘째 줄이 plan과 달랐다. 키가 이미 있으면 `ssh-keygen`이 `Overwrite (y/n)?`를 묻는데
서비스의 stdin이 `/dev/null`(M1-C)이라 EOF를 "아니오"로 읽고 1로 끝난다. 템플릿은
`|| exit 1`이라 서비스가 셋 죽고 포기됐다.

```
/config/ssh/ssh_host_ed25519_key already exists.
Overwrite (y/n)? tars-init: service sshd exited (pid 38, status 1, lived 2s)
...
tars-init: giving up on service sshd after 3 fast exits
```

그래서 템플릿의 `if`를 빼도 키는 덮이지 않는다 — `ssh-keygen` 자신이 두 번째 울타리다.
검사 12를 겨냥하려면 키를 지우고 다시 굽게 해야 했고(셋째 줄), 그러면 겨냥한 검사에서
빨갛다.

### 실측 19 — 루트 게이트 16체인 3/3, 49분 25초

```
=== SV-M2 run 3/3 PASSED ===
SV-M2 PASS: 3/3 consecutive runs succeeded
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

`FAIL` 0줄. FW 때(15체인 46분 26초)보다 약 3분이 늘었다 — 새 체인의 부팅 셋 × 3회다.
이웃 체인 어디에도 `services` 줄 하나 · `label` · `login shell` 줄이 판정을 흔든 자리가
없다.
