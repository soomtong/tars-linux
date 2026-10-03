# TARS Time Discipline — Design

접두사: TD

Status: 끝났다(2026-09-26). M0 · M1 · M2 — 실측 1~22가 아래 절 셋에 있다.

관련 문서: `2026-09-15-tars-time-sync-design.md`(TS. 부팅에 한 번 뛰는 것을
세운 문서이고, 아래에서 "TS 결정 N" · "TS 실측 N"은 전부 그 문서의 것이다) ·
`2026-09-13-tars-guest-network-design.md`(NW. dhcpcd를 들인 문서) ·
`docs/decisions/feedback_boot_never_blocks.md` ·
`docs/decisions/project_write_or_reuse.md`.

## 한 줄 요약

시계에 관한 일을 전부 chronyd에게 넘긴다. 부팅 때의 점프도 chronyd가 하고,
그 뒤로 켜져 있는 동안 이 기계의 시계가 얼마나 빠르거나 느린지를 배워 서서히
맞춘다. 배운 값은 `/config`에 남아 다음 부팅이 그 값으로 시작한다. 우리
코드는 프로토콜에서 손을 떼고 배관(fork · 서버 결정 · 설정 쓰기 · `execve`)만
남는다.

## 왜 지금인가

TS 결정 1이 "시계를 길들이지 않는다"고 정하며 다시 열릴 조건을 적어 두었다 —
TARS가 drift가 보일 만큼 오래 켜져 있게 되는 것. DI · DC가 설치된 디스크로
USB 없이 뜨는 기계를 세웠으므로, 이 기계는 이제 한 번 켜 두고 쓰는 물건이다.

2026-09-26에 사용자가 후보 넷(실머신 NIC · 패키지 매니저 · IN이 미룬 것 ·
chrony) 중에서 chrony를 골랐고, 목적으로 "오래 켜 둔 기계의 drift"를 골랐다.
그리고 접근 둘(SNTP가 뛴 뒤 chronyd로 넘긴다 · 전면 교체) 중에서 전면 교체를
골랐다(결정 1).

## 착수 전에 읽거나 잰 것 — 부팅은 한 번도 안 했다

여섯이다. 셋은 저장소를 읽은 것이고 셋은 컨테이너에서 패키지를 풀어 잰
것이다.

### 확인 1 — `sntp.zig`는 프로토콜과 배관이 반반이다

`init/src/sntp.zig` 425줄과 `sntp_test.zig` 196줄. 나누면 이렇다.

- 프로토콜 — `buildRequest` · `parseReply`(TS 결정 12의 검증 넷) · era 상수
  둘(TS 결정 11) · `makeNonce` · `step`(`clock_settime`) · `askAndStep`의
  소켓 · 타임아웃 · 재시도 30회.
- 배관 — `sync`의 갈래(TS 결정 3의 표) · `fork`와 `power.resetToDefault()` ·
  `ntp=dhcp`의 `waitForServerFile` · `serverFromFile` · `parseServerFile`.

chrony는 "서버 주소가 적힌 파일이 생길 때까지 기다렸다가 시작한다"를 스스로
못 한다. 그래서 배관은 교체 뒤에도 누군가 해야 하고, 그것이 우리 코드로
남는다.

### 확인 2 — 종료 경로는 이미 이 자식을 안다

`power.zig:87`의 주석이 적어 둔 대로, `execve`를 안 하는 자식만 시그널 정책을
손으로 되돌려야 하고 지금 그런 자식이 SNTP 자식 하나다. 교체 뒤에는 그 자식이
`execve`를 하므로 dhcpcd와 같은 쪽으로 옮겨 간다. `shutdown()`의 SIGTERM이
그대로 chronyd에 닿고, SL-M2의 음성 검사(`grace period expired`가 없어야
한다)가 chronyd에도 그대로 걸린다.

### 확인 3 — `net/check.sh`에서 `sntp`를 보는 자리가 열하나다

검사 18(`tars-init: clock stepped to ${STUB_UNIX}`) · 21(`ntp server ... came
from /run/tars/ntp_servers`) · 22(안 닿는 서버의 부팅 지연) · 부팅 B의 종료
검사, 그리고 실패할 때 꼬리로 보여 줄 로그 접두사들이다. 판정하는 사실은
그대로 두고 그 사실을 말해 주는 줄만 옮기면 된다.

검사 18만은 사실이 바뀐다. 지금 stub은 몇 번을 묻든 같은 `1930367167`을
답한다(`net/sntp_stub.pl`). chrony는 여러 번 물어 그 사이에 흐른 시간으로
주파수를 추정하므로, 멈춘 시계를 상대로는 엉뚱한 값을 배운다. stub의 시계가
흘러야 한다(결정 7).

### 확인 4 — chrony 4.6.1의 비용은 라이브러리 하나 또는 셋이다 (컨테이너에서 잼)

trixie의 `chrony_4.6.1-3+deb13u2`를 `apt-get download` · `dpkg -x`로 풀었다.

| 바이너리 | 크기 | `DT_NEEDED` | sysroot에 없는 것 |
|---|---|---|---|
| `usr/sbin/chronyd` | 338,760 | libm · libnettle · libgnutls · libcap · libseccomp · libc | `libseccomp.so.2` |
| `usr/bin/chronyc` | 117,896 | libm · libnettle · libedit · libc | `libedit.so.2` |

`libgnutls`와 `libnettle`은 이미 다른 도구가 끌고 왔다. `libseccomp2`는 설치
크기 201KB에 의존이 libc뿐이다. `libedit2`는 262KB이고 `libbsd0` ·
`libtinfo6`를 요구한다. 그 둘이 sysroot에 이미 있는지는 M0이 재귀
`DT_NEEDED`로 본다(`project_measuring_tool_cost`의 절차).

패키지에는 ifupdown · NetworkManager · dhclient · ppp용 hook이 딸려 온다.
우리는 dhcpcd를 쓰므로 하나도 안 싣는다.

### 확인 5 — 바이너리가 `_chrony`와 `/run/chrony`를 박아 두었다 (컨테이너에서 잼)

`strings`에 `_chrony` · `/etc/chrony/chrony.conf` · `/run/chrony/chronyd.pid` ·
`/run/chrony/chronyd.sock`이 있다. 게스트의 `/etc/passwd`는 root 한 줄뿐이다
(`make_initrd.sh:315`). 그래서 기본값대로 띄우면 권한을 내릴 사용자가 없다.

Debian의 `/etc/default/chrony`는 `DAEMON_OPTS="-F 1"`이다 — seccomp 필터를
켠다.

### 확인 6 — 커널에 seccomp가 없다

`kernel/.config:569`가 `# CONFIG_SECCOMP is not set`이다. `-F 1`을 주면
chronyd가 필터를 걸지 못한다. 안 준다(결정 3). 라이브러리는 동적 링크 때문에
여전히 실어야 한다.

같은 파일에서 `CONFIG_RTC_CLASS`가 꺼져 있고(TS 확인 1과 같다)
`CONFIG_HIGH_RES_TIMERS`도 꺼져 있다. 앞의 것은 비목표 3이 다루고, 뒤의
것이 chrony의 정밀도에 무엇을 하는지는 M0이 본다.

## 결정

### 결정 1 — 시계를 쓰는 주체는 chronyd 하나다. 프로토콜 코드를 지운다

사용자가 골랐다. 확인 1의 프로토콜 부분과 그 테스트를 지운다.

이것은 TS 결정 2("묻는 주체는 우리 코드다")를 뒤집는다. 그 결정의 근거 셋 중
첫째는 "결정 1이 어려운 부분을 뺐으므로 남은 일에서는 chrony도 우리도 같은
코드를 쓴다"였다. 이번 사이클의 목적이 그 어려운 부분이므로 근거가 먼저
무너졌다. `project_write_or_reuse`의 기준 둘로도 clock discipline은 DHCP와
같은 쪽이다 — 원하는 모양이 남의 것과 같고, 품질 차이는 크지만 배움으로
돌아오지 않는다.

뒤집으면서 따라오는 것이 넷이다. TS 비목표 2(서버 여럿) · 4(DNS 이름) ·
7(왕복 지연 보정)이 chrony 안에 있고, 부팅 점프가 샘플 하나가 아니라 `iburst`로
모은 여럿을 거른 값이 된다.

잃는 것도 적는다. 실패가 `tars-init: sntp ...` 한 줄로 읽히던 것이 chronyd의
로그로 바뀐다. 그리고 첫 점프가 답 하나가 아니라 몇 초 뒤에 온다. 부팅은
안 막으므로 셸이 뜨는 시각은 안 변한다(결정 6).

### 결정 2 — 남는 배관은 `clock.zig`로 이름을 바꾼다

프로토콜이 없는 파일이 `sntp.zig`로 남으면 이름이 거짓말을 한다. 남는 일은
"시계를 맡을 자식을 띄운다"이므로 `init/src/clock.zig`로 옮긴다. 순서는 이렇다.

1. `sync`의 갈래(`ntp=off` · `net=off`)는 그대로 로그 한 줄로 끝난다.
2. `fork`한다. 부모는 곧장 다음 줄로 간다.
3. 자식이 서버를 정한다. `ntp=<주소>`면 그 주소, `ntp=dhcp`면 지금처럼
   `/run/tars/ntp_servers`를 기다린다.
4. 자식이 `/run/tars/chrony.conf`를 쓴다(결정 4).
5. 자식이 `execve("/usr/bin/chronyd", ...)`를 한다. pid는 그대로다.

`parseServerFile`과 그 테스트는 남는다. 순수 함수라 호스트에서 검사할 수 있는
유일한 자리이기 때문이다. 설정 파일을 만드는 함수도 같은 이유로 순수하게
쓴다 — 서버 주소와 `/config`가 붙었는지를 받아 바이트를 돌려준다.

`execve`를 하므로 `power.resetToDefault()`를 부를 필요가 없어진다(확인 2).
지운다. 그 함수의 주석이 "지금 그런 자식은 `sntp.zig`의 것 하나다"라고 말하고
있으므로 함수 자체가 쓸 데가 없어지는지 M1 plan이 센다.

⚠ M1 plan이 이 문단을 뒤집었다(결정 M1-A). 자식은 `ntp=dhcp`일 때 `execve`
전에 우리 코드로 서버 파일을 최대 30초 기다리고, 그 창에서는 부모의 SIGTERM
핸들러를 갖고 있다. 그래서 `resetToDefault()`는 fork 직후 첫 줄로 남았다.

설정 파일의 인자에서 `/config`는 M2 몫이라 M1의 `renderConf`는 주소 하나만
받는다.

### 결정 3 — chronyd는 `-d -u root -f /run/tars/chrony.conf`로 뜬다

- `-d` — 데몬으로 갈라지지 않는다. 갈라지면 pid가 바뀌어 fork한 자식이 곧장
  죽고, 실제 chronyd는 PID 1이 모르는 고아가 된다. `reapAll()`이 거두기는
  하지만 "이 자식이 chronyd다"라는 사실이 사라진다. 로그는 stderr로 가고,
  그 stderr는 `tars-init:` 줄과 같은 콘솔이다 — 게이트가 한 로그에서 둘을
  함께 읽는다.
- `-u root` — 확인 5. 사용자를 하나 더 만드는 것은 게스트에 권한 분리를
  들이는 일이고, 게스트의 모든 것이 root로 도는 지금 chronyd 하나만 내려서
  얻는 것이 없다.
- `-F`를 안 준다 — 확인 6.
- `-f` — 설정은 `/etc`가 아니라 `/run`에 둔다. `init`이 부팅마다 새로 쓰는
  파일이기 때문이다. `/etc/chrony/`는 initrd에 안 만든다.

pidfile과 명령 소켓은 기본 자리 `/run/chrony/`를 쓴다. 디렉터리를 chronyd가
만드는지 M0이 본다.

### 결정 4 — 설정 파일은 다섯 줄 남짓이고 사람이 덧붙일 자리를 연다

`init`이 쓰는 모양이다.

```
confdir /config/chrony.d
server <주소> iburst
makestep 1 3
driftfile /config/chrony.drift
cmdport 0
```

TD-M0이 순서와 마지막 줄을 고쳤다(실측 9 · 실측 2). `confdir`가 맨 앞인 것은
같은 서버가 두 번 적히면 먼저 적힌 것이 이기기 때문이고, `cmdport 0`은 IPv6
없는 커널에서 매번 찍히는 `Could not open command socket` 줄을 없앤다.

- `server` — `ntp=` 값 하나. `iburst`가 첫 네 번을 2초 간격으로 묻는다.
- `makestep 1 3` — 첫 세 번의 갱신까지는 1초보다 틀리면 뛴다. TS가 하던 부팅
  점프가 이것이다. 그 뒤로는 절대 안 뛰고 slew한다. chrony의 기본값은 뛰지
  않는 것이라, 이 줄이 없으면 2031년으로 가는 데 몇 달이 걸린다(TS 결정 2가
  지적한 비용이 이 한 줄이다).
- `driftfile` · `confdir` — `/config`가 붙었을 때만 쓴다(결정 5 · 결정 8).
  M1에서는 둘 다 없다.

`rtcsync`는 안 쓴다(비목표 3). `cmdport`는 기본값으로 둔다 — `chronyc`가
붙을 자리다(결정 9).

### 결정 5 — 배운 drift는 `/config/chrony.drift`에 남는다

chronyd는 배운 주파수 오차를 driftfile에 쓴다 — 한 시간마다 한 번, 그리고
SIGTERM을 받고 끝날 때 한 번. 다음 부팅의 chronyd는 그 값에서 출발하므로 처음
몇 분의 추정을 건너뛴다. "오래 켜 둔 기계"가 부팅을 넘어서도 이어지는 자리가
이 파일이다.

`/config`는 SM이 `zoxide` · 히스토리를 남기는 자리와 같다. `/config`가 없는
부팅(설정 디스크가 없는 ISO 부팅 등)은 `driftfile` 줄 없이 돈다. 배운 것은
그 부팅과 함께 사라지고, 로그 한 줄이 그 사실을 남긴다.

### 결정 6 — 부팅을 절대 안 막는다. 구조는 TS 그대로다

`feedback_boot_never_blocks`. TS 결정 3의 표 넷이 그대로 선다. 달라지는 것은
마지막 줄 하나다 — 서버가 안 답하면 자식이 포기하고 죽는 것이 아니라,
chronyd가 살아서 계속 묻는다. 부팅 입장에서는 같다. 부모가 안 기다리기
때문이다.

게이트의 음성 검사(부팅 B · 안 닿는 주소)가 그대로 이것을 증명한다.

### 결정 7 — stub의 시계가 흐르고, 일부러 빠르다

`sntp_stub.pl`이 고정 시각 대신 `STUB_UNIX + (지금 − 시작) × (1 + r)`을
답한다. `r`은 게이트가 정하는 비율이고 M2가 쓴다. M1에서는 `r = 0`이다 —
시계가 흐르기만 한다.

`r`을 수백 ppm으로 주면, 실기계에서는 며칠 걸려 드러나는 수정 결정의 오차를
게이트가 몇십 초 안에 본다. chrony 입장에서는 "내 시계가 서버보다 그만큼
느리다"이다. 값은 M0이 정한다 — 실제 수정 결정은 수십 ppm이지만 TCG 위의
잡음을 넘어서야 판정이 선다.

그 밖에 chrony가 받아들이려면 stub이 갖춰야 할 것(root dispersion · reference
timestamp · receive와 transmit이 다른 값)을 M0이 chronyd에게 직접 물어 본다.

### 결정 8 — 게이트는 `/config/chrony.d/`로 폴링을 줄인다

chrony의 기본 폴링은 64초부터다. 게이트가 drift를 보려면 그 간격이 몇 초여야
한다. 그런데 운영용 설정에 게이트용 간격을 박을 수 없고, `tars.conf`에 키를
더하는 것은 IN 결정 2가 경계한 반사다.

그래서 결정 4의 `confdir`를 연다. 게이트는 설정 디스크를 만들 때 `debugfs`로
`/config/chrony.d/gate.conf`를 심고(`project_seeding_a_config_disk`), 그 파일에
짧은 폴링을 적는다. 정확한 줄은 M0이 정한다.

이 자리는 게이트 전용이 아니다. 사람이 같은 디렉터리에 `pool pool.ntp.org
iburst`를 적으면 DNS 이름으로 서버를 고른다 — `init`에 resolver가 없어 TS
비목표 4였던 것이 chronyd의 libc로 풀린다. 셸 rc가 그렇듯, `tars.conf`는
켜고 끄는 스위치이고 세부는 도구의 설정 파일이 맡는다.

### 결정 9 — `chronyc`를 싣는다

사람이 drift를 보는 창이 `chronyc tracking`이다. 그것이 없으면 이 사이클이
세운 것을 사람이 볼 방법이 로그뿐이다. 비용은 확인 4의 `libedit` 한 줄기다.
M0이 그 줄기가 sysroot에 다 있는지 재고, 셋 넘게 새 라이브러리가 필요하면 이
결정을 다시 연다.

게이트도 `chronyc`로 판정한다. 화면 판정 규칙(`project_gate_screen_echo`)대로,
판정 글자가 명령줄에 없고 출력에만 생기게 만든다.

### 결정 10 — 새 설정 키가 없다

`ntp=off | dhcp | <주소>`가 그대로 스위치다. `off`면 chronyd가 안 뜨고, 켜지면
뜬다. drift를 끄고 싶다는 요구는 아직 없다.

## 비목표

1. `chronyd`를 감독 목록에 넣는 것. dhcpcd와 같은 자리에 둔다. 죽으면 그
   부팅 동안은 시계를 안 길들인다. 다시 열릴 조건: chronyd가 죽는 것을
   실제로 겪는 것.
2. 권한 분리(`_chrony` 사용자 · seccomp). 결정 3. 다시 열릴 조건: 게스트에
   root 아닌 사용자가 생기는 것.
3. RTC에 되쓰기(`rtcsync`). TS 비목표 3 그대로다. x86에서는
   `CONFIG_RTC_CLASS` 없이도 커널이 CMOS를 11분마다 쓸 수 있는 길이 있다고
   알려져 있으나 이 저장소는 그것을 재 본 적이 없다. 다시 열릴 조건:
   네트워크 없이 부팅해도 시각이 맞아야 하는 요구.
4. 게스트가 NTP 서버 노릇을 하는 것(`allow`). TS 비목표 6 그대로다.
5. NTS(인증). chronyd가 할 수 있지만(`libgnutls`가 그 몫이다) 게이트에 NTS
   서버가 없다. 다시 열릴 조건: 사람이 `/config/chrony.d/`에 `nts`를 적고
   안 되는 것을 겪는 것.
6. 실기계에서 drift를 재는 것. 게이트는 stub이 일부러 만든 오차로 증명한다.
   실기계의 값은 사람이 `chronyc tracking`으로 본다.

## 위험

### 위험 1 — chronyd가 TCG 위에서 주파수를 못 잡을 수 있다

TD-M0이 닫았다(실측 5). 잡음이 한 자릿수 ppm이고 500ppm을 8초 안에 배운다.

QEMU TCG는 게스트 시간을 호스트 시간에 맞춰 흘리지만 그 사이에 잡음이 크다.
그 잡음이 `r`보다 크면 판정이 흔들린다. M0이 `r` 없이 돌려서 chronyd가
보고하는 주파수의 퍼짐을 먼저 재고, `r`을 그 퍼짐보다 뚜렷이 크게 잡는다.

### 위험 2 — chronyd의 stderr가 터미널 화면에 섞일 수 있다

TD-M0이 닫았다(실측 7). `/dev/console`이 `ttyS0` 하나다.

`-d`의 로그가 콘솔로 간다. 콘솔이 시리얼뿐이면 문제없고, `tty0`에도 걸려
있으면 terminal이 그리는 화면과 겹칠 수 있다. `tars-init:` 줄이 지금 어디에
나오는지와 같은 답이므로 M0이 로그와 화면을 함께 본다.

### 위험 3 — 종료 때 driftfile을 쓰는 시간이 유예 3초 안에 드는가

TD-M0이 닫았다(실측 6). SIGTERM부터 끝까지 20ms 안이다(tmpfs 기준).

SL-M2의 유예는 3초다. chronyd가 SIGTERM에 driftfile을 쓰고 끝나는 데 걸리는
시간을 M0이 잰다. `/config`가 ext2 · 동기 쓰기가 아니므로 짧을 것으로
보지만 잰 적이 없다.

### 위험 4 — 게이트가 길어진다

M2가 부팅을 하나 더한다(배우고 끈 뒤 다시 켜서 읽는다). `net` 체인 단독이
지금 57~59초이고, 부팅 하나가 대략 20초에 판정 대기를 더한다. 루트 게이트는
그 세 배가 는다.

## TD-M0이 실행으로 증명한 것

2026-09-26. plan은 `plans/2026-09-26-tars-time-discipline-td-m0.md`. 저장소
initrd 뒤에 chrony 조각을 이어 붙인 부팅 한 번(하네스 3분 25초, `tdm0-run`
180초)과 컨테이너의 네이티브 chrony 4.6.1로 설정 해석을 본 것 하나다. 저장소의
코드는 한 글자도 안 바뀌었다.

### 실측 1 — 새 라이브러리는 넷, 547,688바이트다

| 라이브러리 | 바이트 | 누가 부르나 |
|---|---|---|
| `libseccomp.so.2` | 182,560 | chronyd |
| `libedit.so.2` | 220,752 | chronyc |
| `libbsd.so.0` | 84,904 | libedit |
| `libmd.so.0` | 59,472 | libbsd |

나머지 열셋(`libgnutls` · `libnettle` · `libcap` · `libtinfo` 등)은 initrd에
이미 있다(initrd의 라이브러리 102개와 basename으로 대조). gzip 조각으로는
chronyd · chronyc · 넷이 424,273바이트이고, chronyc 줄기(바이너리 + 셋)를 빼면
224,411바이트다. chronyc의 값은 압축 뒤 약 200KB다. 결정 9의 기준("셋 넘게")에
딱 맞으므로 결정 9를 유지한다.

하네스의 결함 하나. `frag.sh`가 initrd 목록을 경로 sed로 뽑다가 0개를 세어
`libc`까지 `new`로 찍었다. 부팅에는 해가 없고(같은 파일을 한 번 더 덮었다) 위
표는 basename 대조로 다시 센 것이다.

### 실측 2 — `-d -u root`로 뜨고 `/run/chrony`를 스스로 만든다

```
TDM0-A-ALIVE up=12.72 pid=77 alive=yes run-chrony=[drwxr-x--- 2 root root 0 Sep 26  2026 /run/chrony]
... Running with root privileges
... Could not open command socket on [::1]:323
```

부팅 전에는 `/run/chrony`가 없었다(`RUNCHRONY-BEFORE`). `-F`를 안 준 chronyd가
seccomp 없는 커널에서 문제없이 돈다(결정 3 · 확인 6).

셋째 줄은 커널에 IPv6가 없어서다(`kernel/.config:823`, `# CONFIG_IPV6 is not
set`). chronyc는 root일 때 UDP가 아니라 `/run/chrony/chronyd.sock`으로 붙으므로
이 실패와 무관하게 `tracking`이 매번 답했다. M1은 설정에 `cmdport 0`을 넣어 이
줄을 없앤다 — UDP 명령 포트는 원격 chronyc용이고 우리는 안 쓴다.

### 실측 3 — 첫 점프가 1초 안이다

```
00:01:41Z chronyd version 4.6.1 starting (...)
00:01:42Z Selected source 10.0.2.2
00:01:42Z System clock wrong by 139986278.596724 seconds
2031-03-04T05:06:20Z System clock was stepped by 139986278.596724 seconds
```

`tdm0-run`의 표지로는 기동 11.64 → 2031년 12.75(uptime 초)다. TS의 SNTP 한 번과
같은 자리에 온다. 결정 1이 "첫 점프가 몇 초 뒤에 온다"고 잃는 쪽에 적었는데,
`iburst`의 첫 답에서 바로 뛰었으므로 그 비용은 사실상 없다.

`-d`의 로그 타임스탬프는 벽시계다. 그래서 점프의 앞뒤 줄이 2026년과 2031년으로
갈린다.

### 실측 4 — 게이트가 grep할 줄

| 줄 | 뜻 |
|---|---|
| `Selected source 10.0.2.2` | 서버를 믿기로 했다 |
| `System clock wrong by N seconds` | 뛸 만큼 틀렸다 |
| `System clock was stepped by N seconds` | 실제로 뛰었다 |
| `Frequency F +/- S ppm read from PATH` | driftfile을 읽었다 |
| `Initial frequency F ppm` | driftfile 없이 커널이 들고 있던 값에서 출발했다(실측 8) |
| `chronyd exiting` | SIGTERM을 받고 끝났다 |
| `Could not add source A` | 같은 주소가 두 번 적혔다(실측 9) |

### 실측 5 — 잡음은 한 자릿수 ppm이고 500ppm을 8초 안에 배운다

`chronyc -c tracking`의 frequency를 2초마다 적었다.

- 국면 A(`r = 0`, 60초): 첫 두 번(−11 · +14)을 지나면 3.05~11.32ppm 사이에 있다.
  skew는 끝으로 가며 4.6~5.6ppm. 0 둘레가 아니라 양수 쪽에 머문다 — TCG 위의
  게스트 시계에 한 자릿수 ppm의 치우침이 있다고 읽는다.
- 국면 B(`r = 500`, 90초): 3초 뒤 −524.3, 5초 뒤 −501.0, 7초 뒤 −499.9이고, 그
  뒤로는 −488.4~−498.9에 있다. driftfile에 남은 값이 −494.72(skew 13.29)다.

부호는 "서버가 빠르다 → 음수"다. chronyd가 보기에 자기 시계가 느린 것이고,
`chronyc tracking`의 사람용 출력으로는 `ppm slow`다.

그래서 `r = 500`을 유지한다. 잡음의 약 50배다. M2의 판정 창은 −550~−450ppm,
대기는 기동 뒤 20초면 넉넉하다.

### 실측 6 — SIGTERM부터 끝까지 20ms 안이고 driftfile이 그때 쓰인다

| 국면 | `term-at` | `EXIT` 표지 | driftfile |
|---|---|---|---|
| A | 74.99 | 75.01 | `4.363088 18.879450` |
| B | 169.47 | 169.48 | `-494.719607 13.285745` |
| C | 191.44 | 191.46 | `-494.188483 9.897614` |

표지를 찍는 비용까지 합친 값이다. SL-M2의 유예 3초에 견주면 위험 3은 닫힌다.
이것은 tmpfs(`/run`)에 쓴 값이고 M2의 `/config`는 ext2이지만, 두 자릿수 ms의
100배 여유를 ext2가 다 먹을 것으로는 안 본다. M2가 그 부팅에서 한 번 더 본다.

국면 C는 B가 남긴 파일을 읽었다.

```
Frequency -494.720 +/- 13.286 ppm read from /run/tdm0/drift-b
```

C의 첫 `TRACK`이 −494.720이다. 결정 5가 선다.

### 실측 7 — `/dev/console`은 `ttyS0` 하나다

`/proc/consoles`가 `ttyS0 -W- (EC p a) 4:64` 한 줄이다. chronyd의 stderr는
시리얼로만 간다. 실기의 `limine.conf`도 `console=ttyS0`이므로 위험 2는 닫힌다.

### 실측 8 — 커널이 주파수를 들고 있다 (plan에 없던 것)

국면 B는 driftfile 없이 시작했는데 로그가 이렇다.

```
Initial frequency 4.363 ppm
```

4.363은 국면 A가 끝날 때의 값이다. chronyd는 주파수 보정을 `adjtimex`로 커널에
넣고, 커널은 chronyd가 죽어도 그 값을 들고 있는다. 다음 chronyd는 driftfile이
없으면 커널에서 읽는다.

그래서 "한 부팅 안에서 다시 띄운 chronyd가 배운 값에서 출발한다"는 driftfile의
증거가 아니다. M2의 판정은 부팅을 넘어서(커널이 새로 시작해서 0이다) 보고, 그
증거는 `read from /config/chrony.drift` 줄이다.

### 실측 9 — 같은 주소가 두 번이면 먼저 적힌 것이 이긴다 (plan에 없던 것)

결정 8의 gate.conf는 `init`이 쓴 것과 같은 `10.0.2.2`를 폴링만 바꿔 다시 적는다.
컨테이너의 네이티브 chrony로 `-Q`(시계를 안 만지고 묻기만)를 돌렸다.

| 설정 순서 | 결과 |
|---|---|
| `server … iburst` → `confdir` | gate.conf의 줄이 `Could not add source`, 끝까지 4초 |
| `confdir` → `server … iburst` | `init`의 줄이 `Could not add source`, 끝까지 1초(gate.conf의 `minpoll -2`가 이겼다) |
| 없는 디렉터리를 `confdir` | 말없이 넘어간다 |
| 없는 디렉터리에 `driftfile` | 도는 동안은 말이 없고 끝날 때 `Could not open /nonexistent/x.drift.tmp` |

그래서 결정 4를 고친다. `confdir`를 맨 앞에 둔다. 사람이(또는 게이트가)
`/config/chrony.d/`에 같은 서버를 적으면 그쪽의 옵션이 이긴다 — 사람이 적은
것이 `init`의 기본값보다 앞선다는, 셸 rc와 같은 순서다.

### 실측 10 — 하네스의 결함 둘

- 국면 B · C의 `STEPPED`는 뜻이 없다. 연도만 보므로 국면 A가 이미 2031년으로
  뛴 뒤에는 항상 참이다. 점프의 증거는 국면 A의 것과 로그 줄뿐이다.
- `CLOCK0`이 표지 grep(`[A-Z]+`)에 안 걸렸다. 따로 뽑으면
  `2026-09-26T00:01:41Z`이고 TS 실측 4(CMOS가 호스트 시각이다)와 같다.

### M1 · M2가 가져다 쓸 넷

1. 싣는 것 — `usr/sbin/chronyd:usr/bin/chronyd` · `usr/bin/chronyc:usr/bin/chronyc`,
   Dockerfile의 `apt-get download`에 `chrony` · `libseccomp2` · `libedit2` ·
   `libbsd0` · `libmd0`. initrd는 gzip으로 약 424KB 는다.
2. 로그 줄 — 실측 4의 표.
3. `r = 500`, 판정 창 −550~−450ppm, 기동 뒤 20초.
4. gate.conf — `server 10.0.2.2 iburst minpoll -2 maxpoll -2` 한 줄. `init`의
   설정은 `confdir /config/chrony.d`를 맨 앞에, `cmdport 0`을 더한다.

## TD-M1이 실행으로 증명한 것

2026-09-26. plan은 `plans/2026-09-26-tars-time-discipline-td-m1.md`. 커밋은
`49d2631`(이미지) · `2f4f537`(initrd) · `51807a8`(`clock.zig`) · `ea72b85`(기본
경로 기다림을 걷어 냄) · `9d79185`(체인)이다.

### 실측 11 — 이미지는 33초에 다시 구워지고 initrd는 425,905바이트 는다

`docker build`가 33.1초였다. 앞 층이 캐시에 있어서 다운로드 층 하나만 다시
돈다. initrd는 42,793,036 → 43,218,941바이트로, M0 실측 1의 "약 424KB"와 맞다.
`tools` 체인이 `all 77 tools the list names`로 초록이다(36.3초).

### 실측 12 — 호스트 검사가 게이트보다 먼저 `makestep`을 잡는다

반사실로 `renderConf`에서 `makestep 1 3`만 지웠더니, `net` 체인이 부팅 전에
돌리는 `zig build test`에서 `clock_test`가 `FAIL: got …`으로 죽었다(20.9초).
원인에 가장 가까운 자리가 먼저 잡은 것이다.

게이트가 그것을 잡는지 보려고 `clock_test`의 기대 문자열에서도 같은 줄을 뺐다.
그러자 부팅 A의 검사 18이 셋째 줄에서 멈췄다.

```
FAIL: chronyd never stepped the clock
```

90초를 다 기다려 2분 46초가 걸렸다. `Selected source`까지는 나온다 — chronyd는
stub을 믿지만, 뛸 허락이 없으면 1.4억 초를 slew로만 따라간다.

첫 시도는 무효였다. `sd`의 고정 문자열 패턴이 Zig의 `\\` 두 글자와 줄바꿈을
못 맞춰 편집이 일어나지 않았고, 멀쩡한 코드로 `PASS`가 나왔다. 그 뒤로는
반사실을 돌리기 전에 `git diff`로 바뀐 줄을 먼저 찍었다.

### 실측 13 — 기본 경로를 기다릴 필요가 없었다 (plan의 결정 M1-B가 틀렸다)

plan은 "주소가 붙기 전에 chronyd가 뜨면 `iburst`의 네 번이 `ENETUNREACH`로
날아가고 64초로 물러난다"고 보고, 자식이 `/proc/net/route`의 기본 경로를
기다린 뒤 `execve`하게 했다(`51807a8`). plan이 적어 둔 반사실로 그 한 줄을
빼고 쟀다.

| | chronyd가 뜬 때 | `Selected source`까지 | 점프한 stub 시각 |
|---|---|---|---|
| 기다림 있음 | 리스 뒤(`default route is up after 8500 ms`) | 뜬 지 5초 | 05:06:23 |
| 기다림 없음 | fork 직후 | 뜬 지 14초(리스 뒤 수 초) | 05:06:24 |

점프가 부팅 기준으로 1초 차이다. 기다림을 걷어 낸 최종판에서 stub이 받은
요청이 넷이었다. 주소가 붙기 전에 보내기에 실패한 요청을 chrony가 버스트의
네 번으로 세지 않고, 붙은 뒤의 응답 넷으로 버스트를 채운 것으로 읽는다. chrony의
소스를 읽어 확인한 것은 아니고, 이 두 판과 맞는 설명이다.

그래서 기다리는 코드(`hasDefaultRoute` · `routeIsUp` · `waitForRoute`와 그
검사, 약 50줄)를 `ea72b85`가 걷어 냈다. 측정된 이득이 없는 코드였다.

### 실측 14 — 부팅 A가 이렇게 흐른다

기다림을 걷어 낸 최종판의 시리얼 로그다.

```
260 tars-init: chronyd will ask 10.0.2.2 (/run/tars/chrony.conf)
261 tars-init: clock child (pid 35) will ask 10.0.2.2
265 2026-09-26T00:30:20Z chronyd version 4.6.1 starting (...)
321 eth0: adding default route via 10.0.2.2
323 2026-09-26T00:30:32Z Selected source 10.0.2.2
324 2026-09-26T00:30:32Z System clock wrong by 139984550.428113 seconds
325 2031-03-04T05:06:22Z System clock was stepped by 139984550.428113 seconds
...
5776 2031-03-04T05:06:27Z chronyd exiting
```

자식의 `chronyd will ask`가 부모의 `clock child`보다 먼저 찍힌다. fork 뒤에
누가 먼저 도는지는 스케줄러가 정하고, 자식은 이제 기다릴 것이 없어서 부모보다
앞선다. 게이트는 두 줄의 순서를 안 본다.

### 실측 15 — 부팅 B의 chronyd는 핸들러를 걸기 전에 SIGTERM을 받는다 (plan에 없던 것)

부팅 B는 심어 둔 파일 덕에 커널 기준 3.7초 만에 전원이 내려간다.

```
tars-init: sent SIGTERM to every process
[    3.701164] random: chronyd: uninitialized urandom read (4096 bytes read)
[    3.960593] random: crng init done
tars-init: every child is gone (reaped 6)
```

`chronyd exiting`이 없다. chronyd가 커널의 난수 풀이 준비되기 전에
`/dev/urandom`을 읽으며 초기화하던 중에 SIGTERM이 왔고, 자기 핸들러를 걸기
전이라 기본 동작으로 조용히 죽었다. `grace period expired`는 없으므로 판정은
초록이다.

M2에 뜻이 있다. driftfile은 chronyd의 핸들러가 SIGTERM을 받아야 쓰인다. 뜨자마자
끄면 안 쓰이지만, 그때는 배운 것도 없으므로 잃는 것도 없다.

기다림이 있던 판(`51807a8`)에서는 부팅 B가 우리 코드의 기다림 안에서 꺼졌다.
그 판은 결정 M1-A의 `resetToDefault()` 창을 게이트가 밟은 유일한 판이었고
초록이었다. 걷어 낸 뒤로는 그 창이 `ntp=dhcp`의 파일 기다림뿐이고, 게이트는
파일을 미리 심으므로 밟지 않는다.

### 실측 16 — 체인 단독 1분 02초

캐시가 있을 때 1분 02.20초, `init`을 처음부터 빌드하면 1분 23초다. TS-M3의
57.5~59.3초에서 3~5초 늘었다. 부팅 B의 차이는 0초(`cost 0s of boot time`)다.

### 실측 17 — 루트 게이트

13체인 3/3 통과(`TARS check PASS`, `FAIL` 0줄, 39분 50.48초, 2026-09-26). `net`
체인의 `chronyd selected 10.0.2.2 and stepped the clock`이 3회, `skipping make`가
38회(`13 × 3 − 1`)다. DC-M2의 38분 38.07초와 같은 `clean` 조건이고 1분 12초 길다 —
`net` 체인의 회차당 3~5초와 이미지가 바뀐 판의 몫이 섞여 있다.

## TD-M2가 실행으로 증명한 것

2026-09-26. plan은 `plans/2026-09-26-tars-time-discipline-td-m2.md`. 커밋은
`ebb0234`(`renderConf`의 `keep`) · `484abcd`(drift 디스크) · `64684bd`(부팅 C · D)다.

plan이 결정 9를 하나 조정했다(결정 M2-B). 게이트는 `chronyc` 대신 전원이 꺼진
디스크 이미지를 `debugfs`로 읽는다. 그 한 번이 "배웠다"와 "끌 때 썼다"를 함께
보고, 화면 타이핑이 없다.

### 실측 18 — 첫 판에 초록이다

```
the stub answered 77 requests in 20s — chrony.d came first
/config/chrony.drift holds -492.583587 ppm after the power-off
the next boot's chronyd started from -492.584 ppm read off /config/chrony.drift
```

77은 0.25초 폴링의 기대값 80과 맞다. −492.58은 M0 실측 6의 −494.72와 같은
자리이고 그때의 창(−550~−450)의 한가운데다. 창은 실측 22가 −600~−400으로 넓혔다. 부팅 D의 줄 전체는
`Frequency -492.584 +/- 53.724 ppm read from /config/chrony.drift`이고, skew
53.7이 M0의 13.3보다 큰 것은 20초만 배웠기 때문이다 — chronyd가 그 값을 얼마나
믿는지를 함께 적어 둔다.

부팅 C는 점프 뒤 21초를 살고 `chronyd exiting`으로 끝났다. M1 실측 15의 "핸들러를
걸기 전에 죽는" 경우를 피한 것이 결정 M2-D의 몫이다.

### 실측 19 — 부팅 A · B도 driftfile을 쓴다

두 부팅도 설정 디스크를 물므로 `keeps its drift`를 찍는다. 그 디스크는 회차마다
`make_disk.sh`가 새로 굽기 때문에 다음 회차로 넘어가는 것이 없다.

### 실측 20 — 반사실 둘이 겨냥한 자리에서 죽었다

코드와 `clock_test`의 기대값을 함께 바꾸고, `git diff`로 편집이 들어간 것을
먼저 확인했다(실측 12의 교훈).

| 반사실 | 결과 |
|---|---|
| `driftfile` 줄을 뺀다 | 검사 26까지 초록(`77 requests`), 검사 27에서 `/config/chrony.drift holds ''` |
| `confdir`를 `server` 뒤로 | 검사 26에서 `the stub answered only 1 request(s) in 20s` |

둘째가 결정 4 · 실측 9의 순서를 게이트가 지킨다는 증거다. `Could not add source`는
두 판 모두에 찍히므로 증거로 못 쓴다는 것도 확인됐다.

### 실측 21 — 체인 단독 1분 42초

M1의 1분 02초에서 40초 늘었다. 부팅 C가 리스 · 선택 · 20초 배움 · 종료를, 부팅
D가 기동 · 읽기 · 종료를 치른다. `init`을 새로 빌드하는 반사실 판은 1분 57초다.

### 실측 22 — 루트 게이트, 그리고 창을 넓혔다

13체인 3/3 통과(`TARS check PASS`, `FAIL` 0줄, 41분 08.74초, 2026-09-26). `skipping
make`가 38회(`13 × 3 − 1`)로 M1과 같은 `clean` 조건이고, M1의 39분 50.48초보다 1분
18초 길다 — 부팅 C · D의 40초 × 3회차와 맞는다.

회차별 값이 이렇다.

| 회차 | 요청 | 디스크의 drift | 다음 부팅이 읽은 값 |
|---|---|---|---|
| 1 | 78 | −500.756067 | −500.756 |
| 2 | 78 | −491.373005 | −491.373 |
| 3 | 78 | −470.381313 | −470.381 |

셋 다 −550~−450 안이었지만 셋째는 끝에서 20ppm 안쪽이다. 실측 5의 "잡음 한 자릿수"는
60~90초를 배운 뒤의 값이었고, 20초만 배운 값은 훨씬 넓게 퍼진다(부팅 D가 찍은 skew
53.7이 그 폭이다). 그대로 두면 게이트가 코드와 무관하게 빨개질 수 있어서 창을
−600~−400으로 넓혔다. 판정이 가르려는 것은 "500을 배웠다"와 "0 근처"이고, 넓힌 창도
0과 400ppm 떨어져 있다. 넓힌 뒤 체인 단독이 초록이다(1분 39초, −495.34).

루트 게이트는 넓히기 전의 창으로 돈 것이다. 창을 넓히는 것은 판정을 느슨하게 하는
방향이라 그 3/3이 넓힌 창에서도 그대로 성립한다.

## 마일스톤

### TD-M0 — 잰다

저장소 파일을 한 글자도 안 바꾼다. `/tmp`의 하네스로 게스트를 띄우고
chronyd를 손으로 돌린다. 잴 것:

- `libedit` 줄기의 재귀 `DT_NEEDED`와 initrd 증가량(결정 9).
- `-d -u root`로 뜨는가, `/run/chrony`를 스스로 만드는가(결정 3).
- 흐르는 stub에 `makestep`으로 2031년까지 뛰는가, 몇 초 걸리는가.
- 로그 줄의 실제 글자 — 게이트가 grep할 것.
- 짧은 폴링에서 `r = 0`일 때 주파수의 퍼짐과, `r`을 줬을 때 몇 초에 수렴하는가
  (위험 1 · 결정 7 · 결정 8).
- SIGTERM부터 끝날 때까지의 시간과 driftfile의 내용(위험 3).
- 로그가 화면에 나오는가(위험 2).

### TD-M1 — 교체한다

`sntp.zig`를 `clock.zig`로 줄이고 `execve chronyd`로 끝낸다. chronyd ·
chronyc · 라이브러리를 initrd에 싣는다. stub이 흐른다(`r = 0`). `net/check.sh`의
검사들이 같은 사실을 새 로그 줄에서 본다 — 2031년으로 뛰었다 · 서버가 DHCP
파일에서 왔다 · 안 닿는 서버가 부팅을 안 막았다 · 종료가 유예를 안 쓴다.

### TD-M2 — drift를 배우고 부팅을 넘긴다

`confdir`와 `driftfile`을 켠다. 게이트가 `/config/chrony.d/gate.conf`를 심고
stub에 `r`을 준다. 판정 셋 — `chronyc tracking`의 주파수가 `r` 근처다 · 전원을
끈 뒤 `/config/chrony.drift`가 있다 · 다시 켠 부팅의 chronyd가 그 값에서
출발한다.
