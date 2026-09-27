# TARS Boot Services — Design

접두사: SV

Status: 설계(2026-09-27). M0 착수 전.

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

`services.d`가 비면 아무것도 안 뜬다. `init`은 `services.d`에 파일을 씨앗으로
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
4. 서비스를 멈추고 다시 띄우는 명령(`sv`나 `systemctl` 같은 것).
5. dhcpcd · chronyd를 감독 목록에 넣는 것. 그 둘은 지금처럼 목록 밖이다.
6. 비밀번호 로그인과 root 아닌 사용자.
7. ssh 세션의 로그인 셸이 `tars.conf`의 `shell`을 따르는 것. 지금은 `passwd`의
   `/bin/sh`(bash)다. M0의 실측을 보고 다시 판단한다.
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
