# AU-M1 — 부팅이 alsactl로 믹서를 켜고, 끌 때 `/config/asound.state`에 적는다

Date: 2026-10-06
Design: `docs/specs/2026-10-05-tars-audio-devices-design.md`
Status: 끝났다(2026-10-06). plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "AU-M1이 실측한 것"에 있다. 다음은 AU-M2(`-au-m2.md`).

## 누가 무엇을 하나

design 결정 6. Task 0~5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. design 결정 6은 M1을 Opus로 적었다 — `init`에 코드가 들어가고 결정 4의 셋을 정해야 해서다. 그 셋은
이 plan이 사본에서 정했고(확정 1), `init`의 코드는 컴파일 · 호스트 검사 · 체인 · regression · mutation까지 사본에서 돌린 글자 그대로
넘긴다. 구현자에게 남는 판단이 없다 — 새 파일 둘은 사본을 복사하고, 편집 스물여섯은 글자 그대로 넣고, 나머지는 체인 · regression ·
mutation을 정해진 순서로 돌린다. 판단이 필요해 보이는 자리(plan의 기대와 다른 값)가 나오면 고치지 말고 보고한다는 규칙이 그것을
lead에게 돌린다. Opus로 올릴 이유는 하나다 — 루트 게이트에서 이 plan이 못 돌린 체인이 빨개져 원인을 찾아야 할 때. 그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/au1/repo/`)에 먼저 넣어 호스트 검사 · 체인 · regression · mutation까지 돌렸고, 아래의 새 파일
본문과 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/au1/render.py`). 기준은 AU-M0 commit(`c855ae3`)의 파일
(`/tmp/run/au1/base/`)이고 편집 뒤의 파일은 `/tmp/run/au1/new/`다. 구현자는 코드를 새로 짓지 않는다. 새 파일은 `new/`에서 `cp -p`하고,
편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고 — EL · CB의 구현자가 그렇게 했다), 각 Task 끝에서
`new/`와 `cmp`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면
고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `init/src/audio.zig` | 새 파일 — 동사 · argv · wait status · 적을지(순수 넷), 일꾼을 띄우고(`start`) 거두고(`reaped`) 끌 때 적는(`store`) 자리 | +282 |
| `init/src/audio_test.zig` | 새 파일 — 순수 넷의 호스트 검사 | +80 |
| `init/src/main.zig` | 편집 셋 — import · 감독 루프의 고아 갈래 앞에 `audio.reaped` · `firewall.up` 앞에 `audio.start` | +10 |
| `init/src/power.zig` | 편집 둘 — import · `reapAll` 뒤 `sync` 앞의 `audio.store()` | +6 |
| `init/build.zig` | 편집 둘 — `audio_test` 모듈과 `test` 단계 | +15 |
| `kernel/guest_tools.sh` | 편집 셋 — 층 14의 `amixer` 주석 · M0의 "alsactl은 안 싣는다" 주석 · `usr/sbin/alsactl:usr/bin/alsactl` | +15 −5 |
| `audio/probe.sh` | 편집 넷 — 두 부팅의 갈래(`first` · `again`) · 부팅이 켠 믹서를 기다림 · 사람의 볼륨 변경 · `kill -TERM 1` | +33 −6 |
| `audio/check.sh` | 편집 열하나 — 부팅 셋(A 새 디스크 · B 같은 디스크 · C 디스크 없음) · 검사 4 뒤집기 · 검사 8~11 | +159 −35 |
| `check.sh` | 편집 하나 — AU 문단의 "회차당 부팅 1회" → 3회 | +2 −1 |

합해서 9 files, +602 −47이다. 커널 · Dockerfile · `make_initrd.sh` · `config.zig`(seed)는 안 바뀐다. `tars.conf`에 키가 없다(확정 1의
넷째). `tools/check.sh`도 안 고친다 — 검사 1이 `guest_tools.sh`를 되읽어 92가 된다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/au1/impl/` 아래에 둔다. `/tmp/run/au1/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도
lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다. 이미지는 M0의
`tars-devcontainer` 그대로다 — `alsactl`은 M0이 받은 alsa-utils 패키지 안에 이미 있다(`$AMD64_SYSROOT/usr/sbin/alsactl`,
130,584바이트). 이 milestone은 이미지를 안 굽는다.

## 이 milestone이 끝나면

- 소리가 켜진 채 뜬다. 커널은 여전히 Master · Capture를 0에 꺼 둔 채 카드를 올리고, `init`이 그 위에서 `alsactl`을 한 번 부른다.
  설정 디스크에 `/config/asound.state`가 있으면 `alsactl restore`가 그 값을 되살리고, 없으면(그 디스크의 첫 부팅 · ISO만 꽂은 부팅)
  `alsactl init`이 Master -20dB · Capture 0dB로 켠다.
- 부팅은 그것을 안 기다린다. `init`은 일꾼 하나를 `fork`하고 곧장 다음 줄로 간다. 일꾼이 카드(`/dev/snd/controlC0`)를 5초까지
  기다렸다가 `alsactl`이 되고, 그 끝은 감독 루프가 거둘 때 `audio.zig`가 로그 한 줄로 남긴다. 소리 장치가 없는 기계(다른 열아홉
  체인이 전부 그렇다)는 일꾼이 5초 뒤에 "no sound card" 한 줄을 남기고 끝난다.
- 사람이 `amixer`나 `alsamixer`로 바꾼 볼륨이 다음 부팅에 남는다. 전원 버튼(또는 `kill -TERM 1`)으로 끄면 `init`이 모든 프로세스를
  거둔 뒤, sync 앞에서 `alsactl store`로 `/config/asound.state`를 쓴다. 기다림은 2초가 상한이고 사본에서는 50ms 남짓이었다. 이
  부팅에 믹서를 못 세웠으면(카드가 없었다 · alsactl이 실패했다 · 일꾼이 끝나기 전에 꺼졌다) 안 적는다 — 커널의 꺼진 기본값이
  사람의 파일을 덮지 않게.
- 게스트에 `alsactl`이 이름으로 선다(`guest_tools.sh` 층 14, 도구 91 → 92).
- `audio` 체인이 부팅 셋이 된다 — 새 디스크(A) · 같은 디스크(B) · 디스크 없음(C). 검사 4가 뒤집혀 "부팅이 소리를 켰다"를 보고,
  검사 8~11이 더해진다. 게이트는 여전히 게스트에 한 글자도 안 치고 monitor를 안 쓴다 — 전원은 프로브가 `kill -TERM 1`로 끈다.

로그 줄(정본 — `init/src/audio.zig`가 찍고 `audio/check.sh`가 이 글자를 본다). 사본의 세 부팅에서 뽑았다. `Found hardware` 두
줄은 `alsactl init`이 직접 찍는 것이다.

```
# 부팅 A — 새 디스크
tars-init: audio: alsactl init once a sound card shows up (pid 50)
Found hardware: "HDA-Intel" "QEMU Generic" "HDA:1af40032,1af40032,00100101" "0x1af4" "0x1100"
Hardware is initialized using a generic method
tars-init: audio: alsactl init turned the mixer on (generic rules, exit 99)
audio-probe: boot first
audio-probe: master at boot [  Front Right: Playback 54 [73%] [-20.00dB] [on]]
audio-probe: capture at boot [  Front Right: Capture 74 [100%] [0.00dB] [on]]
audio-probe: master now [  Front Right: Playback 74 [100%] [0.00dB] [on]]
audio-probe: powering off at uptime 9.27
tars-init: every child is gone (reaped 4)
tars-init: audio: stored the mixer in /config/asound.state
tars-init: filesystems synced

# 부팅 B — 같은 디스크
tars-init: audio: alsactl restore once a sound card shows up (pid 51)
tars-init: audio: alsactl restore set the mixer from /config/asound.state
audio-probe: boot again
audio-probe: master at boot [  Front Right: Playback 74 [100%] [0.00dB] [on]]
audio-probe: capture at boot [  Front Right: Capture 74 [100%] [0.00dB] [on]]

# 부팅 C — 디스크 없음
tars-init: no disk labelled tars-* among 14 candidates
tars-init: audio: alsactl init once a sound card shows up (pid 50)
tars-init: audio: alsactl init turned the mixer on (generic rules, exit 99)

# 소리 장치 없음(다른 체인의 모양) — 전원을 늦게 누른 판과 일꾼이 기다리는 중에 누른 판
tars-init: audio: no sound card within 5000ms, the mixer is left alone
tars-init: audio: mixer not stored, it was not set this boot
```

그 밖의 갈래(`audio.zig`가 정본).

```
tars-init: audio: sound card appeared after <N>ms                         카드를 기다린 적이 있을 때만(일꾼이 찍는다)
tars-init: audio: alsactl <verb> exited <N>, the mixer is left as the kernel set it
tars-init: audio: alsactl <verb> was killed (signal <N>)
tars-init: cannot exec /usr/bin/alsactl                                   일꾼이 찍고 127로 끝난다
tars-init: audio: mixer not stored, no /config
tars-init: audio: alsactl store did not finish in 2000ms, killed it
tars-init: audio: alsactl store exited <N>
tars-init: audio: cannot fork (errno <N>), the mixer is left as the kernel set it
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 코드와 alsa-utils 1.2.14의 `alsactl` 소스(`alsactl.c` · `state.c` · `lock.c` · `init_parse.c` ·
`init_ucm.c`, `/tmp/run/au1/meas/src/`)를 읽어 정했고, 저장소 사본(`/tmp/run/au1/repo/`)과 M0 이미지(`tars-devcontainer`)로 쟀다.
측정 파일은 `/tmp/run/au1/meas/`(시리얼 로그 `serial_a/b/c.log` · `serial_nocard_late/early.log`, 상태 파일 `asound.state`, 체인 ·
regression 로그)에 있다. 저장소의 작업 트리는 이 plan 말고는 한 글자도 안 바뀌었다.

1. design 결정 4의 셋과 그 곁의 둘.

   첫째 — 무엇이 켜나. `init`이 `alsactl`을 부른다. 그러나 firewall의 `nft -f`처럼 기다리지 않는다. `audio.start`가 일꾼 하나를
   `fork`하고 곧장 돌아오며, 일꾼이 카드 노드를 5초까지 100ms 간격으로 보다가 `alsactl`로 `execve`한다. 일꾼은 execve 전에 우리
   코드로 최대 5초를 머무르므로 `power.resetToDefault()`를 먼저 부른다(그 함수의 주석이 적은 경우 그대로다 — 안 부르면 전원 버튼의
   SIGTERM에 안 죽어 종료가 유예 3초를 다 쓴다).

   | 후보 | 왜 아닌가 |
   |---|---|
   | (a) 일꾼을 fork하고 안 기다린다 | 고른 것 |
   | (b) firewall처럼 `fork` · `execve` · `wait4`로 기다린다(lead의 추천) | 카드가 PID 1보다 늦을 수 있다(HDA는 코덱 탐색을 커널의 일 큐에서 한다). 기다리는 모양이면 PID 1이 카드를 기다려야 하고, 소리 장치가 없는 기계는 매번 상한만큼 선다 — DC는 "설치된 디스크로 떴다"는 표지가 있을 때만 기다렸는데 카드에는 그런 표지가 없다. 그리고 firewall이 기다리는 이유(규칙이 dhcpcd보다 먼저 서야 한다)가 여기는 없다 — 부팅 경로의 누구도 믹서를 안 기다린다(`feedback_boot_never_blocks`) |
   | (c) 감독 목록에 `alsactl daemon` · `rdaemon` | design 실측 10. SIGTERM에 저장 없이 끝나고 SIGUSR2여야 저장한다 — 우리 종료 경로는 SIGTERM · SIGHUP이다. 그리고 감독자는 끝난 것을 되살리는데 restore · init은 한 번 하고 끝나는 일이다 |
   | (d) control 노드에 ioctl을 직접 쏜다 | `project_write_or_reuse`. 원하는 동작이 `alsactl`과 글자 그대로 같다 |

   동사는 둘이다. 파일이 있으면 `alsactl -U -f /config/asound.state restore`, 없으면 `alsactl -U init`. restore 하나로 안 쓰는 이유 —
   restore도 파일이 없으면 카드를 init해 주지만 그러고도 exit 2(ENOENT)를 돌려준다(`state.c`의 `load_state`, `finalerr = err`). 그러면
   "켰다"와 "실패했다"가 종료 코드로 안 갈린다.

   종료 코드 99는 성공이다. `alsactl init`이 사본에서 믹서를 켜고도 99로 끝났다(첫 판이 이것을 "실패"로 읽어 빨갰다). alsactl.1의 init
   절이 "If device is not known, error code 99 is returned"이고, 그 뜻은 "규칙 표(`/usr/share/alsa/init`)에 이 카드가 없어 범용 규칙으로
   켰다"다(`init_parse.c`가 `err <= -99`를 "non-fatal"로 센다). QEMU의 코덱이 이 길이고 표에 없는 노트북 코덱도 그럴 것이다. 로그는 끝에
   `(generic rules, exit 99)`를 붙인다. restore도 파일과 카드의 컨트롤이 어긋나면 init을 거쳐 99가 될 수 있다 — 같은 갈래로 읽는다.

   일꾼의 끝은 감독 루프가 거둔다. 감독 목록에 없는 pid는 지금까지 `reaped orphan pid N`이었는데, 그 앞에서 `audio.reaped(pid, status)`에
   먼저 묻는다. 고아로 찍지 않는 이유는 둘이다 — 그 줄이 일꾼의 끝(믹서가 섰는가)을 못 말하고, `terminal/check.sh:230`이 `reaped orphan
   pid`를 "재부모화된 셸을 거뒀다"의 증거로 보는데 우리 일꾼이 모든 부팅에서 그 줄을 찍으면 그 검사가 우리 덕에 초록이 될 수 있다.

   둘째 — 무엇을 기억하나. `/config/asound.state` 하나다(chrony.drift와 같은 자리의 같은 성질 — 기계가 배운 것이다). 적는 것은 종료
   경로다. `power.shutdown`이 `kill(-1)` 둘 · `reapAll` · (필요하면 SIGKILL) 뒤, `sync` 앞에서 `audio.store()`를 부른다. 모든 프로세스가
   거둬진 뒤라 그 뒤로 믹서를 만질 것이 없고, sync 앞이라 적은 것이 디스크에 닿는다(`/config`는 `MS_SYNCHRONOUS`로 붙어 있다).
   `alsactl store`는 이 시점에 fork되므로 `kill(-1)`을 안 받는다. 기다림은 50ms 간격으로 2초가 상한이고, 넘기면 SIGKILL하고 전원은
   그대로 내린다.

   적는 조건은 둘이다(`storeDecision`). 이 부팅에 일꾼의 alsactl이 0이나 99로 끝났고(`mixer_set`), `/config`가 붙었다. 앞의 것이 빠지면
   커널의 꺼진 기본값이 사람의 파일을 덮는다 — 일꾼이 카드를 기다리는 사이에 전원 버튼이 눌린 판이 그 경우다(사본에서 재 봤다, 확정 9).
   alsactl의 `save_state`는 기존 파일을 먼저 읽고 지금 있는 카드의 항목만 바꿔 `.new`에 쓴 뒤 `rename`한다 — 그래서 없는 카드의
   항목은 지워지지 않는다. `-f`로 기본 경로(`/var/lib/alsa/asound.state`)가 아닌 파일을 주면 alsactl이 잠금 파일을 안 만든다
   (`alsactl.c`의 `do_lock`, `lock.c`의 `state_lock_`) — 게스트에 `/var/lock`이 없어도 된다.

   상태 파일은 사본에서 134줄이었고 Master는 이렇게 남는다.

   ```
   		name 'Master Playback Volume'
   		value.0 74
   		value.1 74
   ```

   셋째 — 늦게 오는 카드. M1은 HDA의 시각만 쟀다. 사본의 QEMU에서 코덱 줄이 0.55초, `Run /init`이 3.07초였다 — 카드가 PID 1보다
   2.5초 먼저 섰고 일꾼은 한 번도 기다리지 않았다(`sound card appeared after` 줄이 없다). 실기의 HDA는 `azx_probe`가 카드 등록을
   일 큐로 미루므로 늦을 수 있고, 일꾼의 5초가 그 몫이다. 부팅 뒤에 꽂히는 USB 헤드셋은 재지 않고 M2로 넘긴다. M1의 커널에는
   `SND_USB_AUDIO`가 없어서 QEMU `device_add usb-audio`가 카드를 만들 수 없다 — 재는 일 자체가 M2의 커널을 요구한다. M2가 알고 시작할
   것: 일꾼의 restore와 끄는 길의 store는 카드 인자 없이 부르므로 그 순간 있는 카드 전부를 다룬다. 부팅 때 꽂혀 있던 USB 카드는 되살고,
   부팅 뒤에 꽂은 카드의 볼륨은 끌 때 적히지만 다음 부팅에 그 카드가 꽂혀 있어야 되산다. 꽂는 순간 켜는 것(uevent를 듣는 자리 또는
   `alsactl rdaemon` + SIGUSR1)과 기본 카드는 M2가 정한다. 포트 45491은 이번에도 안 썼다.

   넷째 — UCM. `-U`를 준다. 안 주면 alsactl이 initrd에 없는 `/usr/share/alsa/ucm2/ucm.conf`를 찾다가 부팅마다 경고 두 줄을 찍고 범용
   방법으로 내려온다(design 실측 10). restore도 같은 시도를 한다(`load_state`가 카드마다 `init_ucm`을 부르고 에러를 무시한다). UCM이
   필요한 기계(DSP 뒤의 마이크)는 M3이고, 그때 alsa-ucm-conf와 함께 이 플래그를 다시 본다. 체인 검사 4의 음성이 이 줄들을 본다.

   다섯째 — `tars.conf` 키. 없다. 소리를 끄고 싶은 사람은 `amixer sset Master mute`로 끄면 그것이 기억된다. 키를 두면 "파일의 값"과
   "사람이 마지막으로 맞춘 값" 둘이 같은 것을 다투고, seed가 한 줄 늘어 `config` 체인의 25번째 줄 검사(lessons 이월 숙제)를 함께 봐야 한다.

2. 코드의 모양. `audio.zig`의 위 절반이 순수 넷(`verbFor` · `argvFor`와 argv 상수 셋 · `outcome` · `storeDecision`)이고 아래 절반이
   시스템 콜(`start` · `reaped` · `store`)이다 — `clock.zig`와 같은 가름이다. PID 1의 기억은 전역 넷(`worker_pid` · `worker_verb` ·
   `storage` · `mixer_set`)과 env 포인터 하나다. PID 1은 스레드가 없고 시그널 핸들러는 이것들을 안 만진다. `power.zig`와
   `audio.zig`가 서로를 import한다(power → `audio.store`, audio → `power.resetToDefault`). Zig는 파일 사이의 순환 import를 받고,
   `power_test`도 그대로 컴파일된다. `main.zig`에서 `audio.start`가 놓인 자리는 env 블록이 선 뒤 · `firewall.up` 앞이다 — env 블록이
   있어야 alsactl에 같은 env를 주고, nft를 기다리는 동안 일꾼이 함께 돈다.

   크기. `init`이 3,712,888 → 3,776,512바이트(+63,624), initrd가 90,543,425 → 90,608,710바이트(+65,285, gzip — 대부분 alsactl)다.

3. 호스트 검사. `audio_test`가 순수 넷을 본다 — 동사 네 갈래, argv 셋을 손으로 적은 글자와 비교(tautology가 아니게), wait status
   일곱(0 · 99 · 254 · 127 · 2 · SIGKILL · SIGTERM), 적을지 네 갈래. `build.zig`의 `test` 단계에 열두째로 붙는다. 사본에서
   `zig build test`가 exit 0이고 열두 검사가 전부 돌았다(캐시를 지운 판 10초).

4. 프로브. 같은 디스크로 두 번 뜨므로 시작할 때 `/config/asound.state`를 보고 갈래를 고른다 — 그 파일은 `init`이 끌 때 쓰므로 첫 부팅의
   프로브가 시작할 때는 아직 없다. `first`는 M0의 일(재생 둘 · 녹음)에 두 가지가 바뀐다. 볼륨을 `amixer sset Master 0dB`로 올리는 것이
   "사람이 바꾼 것"이고(unmute와 Capture는 안 친다 — 부팅이 켰다), 일을 마치면 uptime을 찍고 `kill -TERM 1`로 전원을 끈다(power 체인이
   타이핑하는 것과 같은 길). `again`은 믹서를 안 만지고 사각파 하나만 낸다.

   프로브가 부팅이 켠 믹서를 읽기 전에 기다리는 이유가 있다. 일꾼과 프로브가 같은 카드를 보고 나란히 돈다 — 사본의 부팅 A에서
   `audio-probe: boot first`가 `alsactl init turned the mixer on`보다 먼저 찍혔다. 그래서 `alsactl` 프로세스가 없고 Master가 `[on]`일
   때까지 10초를 본다(`pgrep -x alsactl` · `amixer`). 켜는 것이 아무도 없으면 10초 뒤에 꺼진 그대로를 찍고 검사 4가 그 값으로 빨개진다
   (mutation 3 · 4가 그 판이다).

5. 체인. 부팅 셋, 검사 열하나. QEMU 호출은 `start_guest with-disk|no-disk` 한 함수로 모았다(`-nic none` · `-drive`의 유무만 다르다 —
   진입 검사 `require_explicit_nic`이 함수 안의 호출을 그대로 본다). 로그 파일 하나를 부팅마다 비워 쓴다.

   | 검사 | 부팅 | 본다 | 사본의 값 |
   |---|---|---|---|
   | 1 | 없음 | M0 그대로 | 초록 |
   | 2 · 3 | A | M0 그대로 | 초록 |
   | 4 | A | `alsactl init turned the mixer on` · `boot first` · Master `54 [73%] [-20.00dB] [on]` · Capture `74 [100%] [0.00dB] [on]` · `amixer` 뒤 Master `74 [100%] [0.00dB] [on]` · 음성 `ucm2/ucm.conf` 없음 | 초록 |
   | 5 · 6 · 7 | A | M0 그대로. 7(녹음 96,000프레임 전부 상수)이 이제 "부팅이 켠 Capture"의 바이트 증명이다 — 프로브가 Capture를 안 만진다 | `tone=48000 left=53060 right=71059 other=0` · `match=96000` |
   | 8 | A | 게스트가 스스로 꺼진다(30초) · `stored the mixer in /config/asound.state` · 디스크의 asound.state에서 `Master Playback Volume`의 `value.0`이 74 | `shutdown: asked at 9.27s, powered down at 9.471931s` |
   | 9 | B | `alsactl restore set the mixer from /config/asound.state` · `boot again` · Master `74 … [0.00dB] [on]` · Capture `74 … [on]` | 초록 |
   | 10 | B | `aplay exit 0 []` · tap B의 사각파 47,000 이상 · other 0 — 프로브가 `amixer`를 안 친 판이다 | `tone=48000`(판마다 47,842~48,000) |
   | 11 | C | `alsactl init turned the mixer on` · `no disk labelled tars-* among` | 초록 |

   검사 8의 `shutdown:` 줄은 판정이 아니라 기록이다 — 프로브가 `kill -TERM 1`을 친 uptime과 커널의 `reboot: Power down` 시각이다. 사본에서
   store가 있는 판이 0.19 · 0.20초, store를 뺀 판(mutation 2의 사본)이 0.14초였다. store가 종료에 더하는 몫은 50ms 남짓이다.

6. 시간. 캐시를 지운 첫 판이 1분 44초(init · terminal 빌드 포함), 데운 판이 29초 · 29초였다(M0의 한 부팅 17~18초에 부팅 둘). 부팅 B의
   tap은 `tone`이 47,842~48,000으로 판마다 조금씩 다르다(스트림 앞뒤의 자투리) — 여유 1,000 안이다. 루트 게이트는 이 체인을 두 번
   돌리므로 M0의 50분 34초에 25초 안팎을 더한 것으로 본다.

7. mutation. 여섯 가지를 열한 판(대조군 하나 포함)으로 체인에서, 둘을 호스트 검사에서 돌렸다(`/tmp/run/au1/make_mut.py` · `run_mut.sh`,
   로그는 `/tmp/run/au1/mut/`). 앞 검사가 먼저 잡는 것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다(lessons
   "mutation이 겨냥한 검사에 걸릴 것이라고 믿기").

   | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | (대조군) | `m0` | 없음 | — | `AU check PASS` | 48초 |
   | 1 restore 갈래 빼기(`verbFor`가 언제나 init) | `m1` | `audio_m1.zig` | 검사 9 | `FAIL: init did not restore the mixer from /config/asound.state` | 43초 |
   | 2 끄는 길의 `audio.store()` 빼기 | `m2` | `power_m2.zig` | 검사 8 | `FAIL: init did not store the mixer on the way down` | 38초 |
   | | `m2_b` | + `check_no8.sh` | 검사 9(B가 다시 init이다) | `FAIL: init did not restore the mixer from /config/asound.state` | 47초 |
   | 3 게스트에서 `alsactl` 빼기 | `m3` | `guest_tools_m3.sh` | 검사 4(로그 `alsactl init exited 127` — 프로브는 `done`까지 가고 전원도 꺼졌다. 부팅이 안 막혔다) | `FAIL: init did not turn the mixer on with alsactl init` | 52초 |
   | | `m3_play` | + `check_no4.sh` | 검사 5(Master가 커널의 꺼짐 그대로 — 프로브는 이제 unmute를 안 친다) | `FAIL: the square wave did not reach the speaker (tone frames 0 of 48000); silence means the mixer was muted` | 52초 |
   | 4 감독 루프의 `audio.reaped` 빼기 | `m4` | `main_m4.zig` | 검사 4(믹서는 섰지만 init이 모른다 — 일꾼이 고아로 찍힌다) | `FAIL: init did not turn the mixer on with alsactl init` | 38초 |
   | | `m4_store` | + `check_no4.sh` | 검사 8(로그 `mixer not stored, it was not set this boot`) | `FAIL: init did not store the mixer on the way down` | 38초 |
   | 5 프로브의 `amixer sset Master 0dB` 빼기 | `m5` | `probe_m5.sh` | 검사 4의 다섯째 | `FAIL: amixer could not set Master to 0dB` | 37초 |
   | | `m5_play` | + `check_nonow.sh` | 검사 5(-20dB가 샘플을 바꾼다) | `FAIL: the square wave did not reach the speaker (tone frames 0 of 48000); silence means the mixer was muted` | 37초 |
   | 6 init argv의 `-U` 빼기 | `m6` | `audio_m6.zig` | 검사 4의 음성 | `FAIL: alsactl looked for UCM; init must pass -U until AU-M3 ships alsa-ucm-conf` | 36초 |

   호스트 검사 mutation 둘(`audio.zig`를 사본으로 바꿔 `zig build test`).

   | mutation | `FAIL` 줄 |
   |---|---|
   | 1(`audio_m1.zig`) | `FAIL: mounted with a state file must restore` |
   | 6(`audio_m6.zig`) | `FAIL: init argv is '/usr/bin/alsactl init', want '/usr/bin/alsactl -U init'` |

   읽을 것 둘.
   - mutation 3이 lead가 물은 "alsactl이 없을 때 부팅이 평소대로 끝나는가"의 답이다. 일꾼이 127로 끝나고(`alsactl init exited 127, the mixer is left as the kernel set it`), 프로브는
     `done`까지 가고, 전원 버튼 경로(검사 8의 앞부분인 스스로 꺼짐)도 돌았다. 빨개진 것은 "소리가 켜졌는가" 하나다.
   - mutation 4의 `m4`가 검사 4의 첫째에서 빨개지는 것은 일꾼이 `reaped orphan pid`로 찍혀 `audio:` 줄이 안 나오기 때문이다. 그 판의
     로그에는 `reaped orphan pid` 줄이 생긴다 — 확정 1이 그 줄을 피한 이유가 이것이다.

8. regression. `init`의 감독 루프 · 종료 경로 · 부팅 순서와 initrd가 바뀌므로 일곱을 사본에서 돌렸다. 일곱 다 exit 0이다.

   | 체인 | 시간 | 왜 돌렸나 |
   |---|---|---|
   | `power` | 49초 | 종료 경로에 `audio.store()`가 들어갔다. 음성 둘(`grace period expired` · `sent SIGKILL`)이 그대로 초록이다 |
   | `service` | 74초 | 감독 루프의 거두기 갈래에 한 줄. 감독 목록 · `tars-service`가 그대로다 |
   | `tools` | 59초 | `the initrd carries the four bones and all 92 tools the list names` |
   | `config` | 159초 | 같은 디스크로 여러 번 뜨는 체인. `init`의 부팅 순서에 일꾼이 끼었다 |
   | `terminal` | 24초 | `reaped orphan pid`를 보는 체인(확정 1). 일꾼이 그 줄을 안 찍어도 진짜 고아로 초록이다 |
   | `boot` | 25초 | `-vga none`의 terminal 재시작 셈(정확히 3). 일꾼은 그 셈에 안 든다 |
   | `install` | 104초 | initrd가 65KB 커졌다. `init waited 1800ms for the late USB disk` — M0과 같다 |

9. 부팅은 안 기다린다. 소리 장치 없는 q35(다른 체인의 모양)를 두 번 띄워 전원 버튼(`system_powerdown`)을 눌렀다
   (`/tmp/run/au1/meas/nocard.sh` — 측정에만 monitor를 썼고 체인에는 없다).
   - 늦게 누른 판(콘솔 셸 뒤 8초). `alsactl init once a sound card shows up` → `started console shell` → 5초 뒤 `no sound card within 5000ms,
     the mixer is left alone` → 버튼 → `every child is gone (reaped 3)` → `mixer not stored, it was not set this boot`. 콘솔 셸이 일꾼보다
     5초 먼저 섰다.
   - 일꾼이 기다리는 중에 누른 판(콘솔 셸 직후). `every child is gone (reaped 3)` — 셋째가 일꾼이다. `grace period expired`가 없고
     `Run /init` 3.13초에서 `reboot: Power down` 3.34초까지였다. `resetToDefault`가 일꾼을 SIGTERM에 죽게 했다.

10. 낡은 산출물. 이 milestone은 Zig 코드를 고친다. 아래 명령은 전부 캐시 삭제를 같은 `docker run` 안에 둔다
    (`project_zig_out_staleness`). 커널은 안 바뀐다 — `build.sh`의 sha256 스탬프가 M0의 것 그대로다.

11. 앵커. 편집 스물여섯의 `old_string`이 M0 commit의 파일에 정확히 한 번씩 있고(`python3 /tmp/run/au1/anchors.py pre "$PWD"` →
    `pre: 26 edits, 0 bad`), `new_string`이 사본에 정확히 한 번씩 있다(`post: 26 edits, 0 bad`). 진입 검사 셋도 사본의
    `audio/check.sh`에서 `ENTRY-OK`였다. main 작업 트리의 일곱 파일이 `/tmp/run/au1/base/`와 바이트까지 같다(lead의 M0 commit 뒤에 대조).

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

   컨테이너가 있으면 끝나기를 기다린다(위 lock 절차). 남의 컨테이너를 죽이지 않는다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: 맨 위 commit이 `c855ae3 AU-M0: Kernel ALSA and HDA, …`이거나 그 위에 lead의 문서 commit이 있다. `git status`는 이 plan이
   commit 전이면 그것 하나이고, lead가 고치는 중일 수 있는 design · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/`가 더 있을 수 있다.
   그 밖의 소스 파일이 `M`이면 멈추고 보고한다.

3. 편집의 앵커와 기준 파일을 본다(확정 11).

   ```bash
   python3 /tmp/run/au1/anchors.py pre "$PWD"
   for f in init/src/main.zig init/src/power.zig init/build.zig kernel/guest_tools.sh audio/check.sh audio/probe.sh check.sh; do
     cmp $f /tmp/run/au1/base/$f && echo "BASE $f"; done
   ```

   기대: `pre: 26 edits, 0 bad`와 `BASE` 일곱. 하나라도 다르면 그 파일을 보고하고 멈춘다 — 앵커를 다시 뽑아야 한다.

## Task 1: `init` — 새 파일 둘과 편집 일곱, 호스트 검사

확정 1 · 2 · 3. 부팅에 일꾼을 띄우는 자리(`main.zig`), 감독 루프가 그 일꾼을 거두는 자리(`main.zig`), 끄는 길에서 적는 자리
(`power.zig`), 검사를 등록하는 자리(`build.zig`)다.

### 1-1. 새 파일 둘

```bash
cp -p /tmp/run/au1/new/init/src/audio.zig /tmp/run/au1/new/init/src/audio_test.zig init/src/
```

`init/src/audio.zig`:

```zig
const std = @import("std");
const linux = std.os.linux;
const power = @import("power.zig");

// 부팅이 믹서를 켜고, 끌 때 기억한다(AU design 결정 4). 믹서를 실제로 만지는 것은
// alsa-utils의 alsactl이다 — 이 파일은 그것을 언제 · 어떤 인자로 부르고 그 끝을
// 어떻게 읽는지만 정한다(project_write_or_reuse).
//
// 켜는 쪽은 기다리지 않는다. `start`가 일꾼 하나를 fork하고 곧장 돌아오며, 일꾼이
// 카드를 기다렸다가 alsactl이 된다. 일꾼의 끝은 감독 루프가 거둘 때 `reaped`가
// 읽는다. 끄는 쪽(`store`)은 기다린다 — 종료 경로는 이 뒤에 sync와 전원 끄기뿐이라
// 기다리지 않으면 파일이 반쯤 쓰인 채 전원이 나간다. 그 기다림에 상한이 있다.

/// 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// guest_tools.sh 층 14가 usr/sbin/alsactl을 여기로 넣는다. dhcpcd · chronyd와
/// 같은 이유(PATH가 /usr/bin:/bin)로 /usr/sbin을 안 쓴다.
pub const ALSACTL_PATH: [:0]const u8 = "/usr/bin/alsactl";

/// 사람이 바꾼 믹서가 부팅을 넘는 자리. `/config`가 붙은 부팅에서만 읽고 쓴다.
/// chrony.drift와 같은 자리의 같은 성질이다 — 기계가 배운 것이고 사람이 손으로
/// 고칠 일이 없다.
pub const STATE_PATH: [:0]const u8 = "/config/asound.state";

/// 카드 0의 제어 노드. 이것이 서면 alsactl이 그 카드를 연다.
const CARD_PATH: [:0]const u8 = "/dev/snd/controlC0";

/// 일꾼이 카드를 기다리는 상한. HDA는 코덱 탐색을 커널의 일 큐에서 하므로 카드가
/// PID 1보다 늦게 설 수 있다. 소리 장치가 없는 기계(게이트의 체인 대부분)에서는
/// 일꾼이 이만큼 살다가 끝난다 — 부팅은 안 기다린다.
pub const CARD_WAIT_MS: u32 = 5000;
const CARD_POLL_MS: u32 = 100;

/// 끌 때 alsactl store를 기다리는 상한. 넘기면 SIGKILL이고 전원은 그대로 꺼진다.
pub const STORE_WAIT_MS: u32 = 2000;
const STORE_POLL_MS: u32 = 50;

/// 일꾼이 카드를 못 보고 끝날 때의 종료 코드. alsactl은 음수 errno를 뒤집어
/// 돌려주므로(1~133) 거기 안 겹치는 값이다. 127은 execve 실패로 이미 쓴다.
pub const NO_CARD_EXIT: u8 = 254;

/// alsactl이 카드를 자기 규칙 표(/usr/share/alsa/init)에서 못 찾아 범용 규칙으로
/// 켰을 때의 종료 코드다(alsactl.1의 init 절 — "If device is not known, error code 99
/// is returned"). 믹서는 선 것이다. QEMU의 코덱이 이 길이고(AU-M1 실측), 표에 없는
/// 노트북의 코덱도 그럴 것이다. restore도 파일과 카드의 컨트롤이 어긋나면 init을
/// 거치므로 같은 99가 나올 수 있다(state.c의 load_state).
pub const GENERIC_EXIT: u8 = 99;

pub const Verb = enum {
    /// `/config/asound.state`를 되살린다. 파일에 없는 카드는 alsactl이 init한다.
    restore,
    /// 커널의 기본값(꺼짐)을 alsactl의 기본값(Master -20dB · Capture 0dB, 켜짐)으로.
    init,
};

/// 어느 동사로 켤지. 시스템 콜이 없는 순수 함수다(audio_test가 본다).
///
/// 파일이 없으면 restore가 아니라 init을 부른다. restore도 파일이 없으면 카드를
/// init해 주지만 그러고도 exit 2(ENOENT)를 돌려준다(alsactl의 state.c
/// `load_state`) — 그러면 "켰다"와 "실패했다"가 종료 코드로 안 갈린다.
pub fn verbFor(storage_mounted: bool, state_exists: bool) Verb {
    return if (storage_mounted and state_exists) .restore else .init;
}

/// alsactl의 argv. 셋 다 같은 모양이고 순수하다.
///
///   -U   UCM을 안 쓴다. 쓰면 alsa-ucm-conf가 없는 initrd에서 `Unable to find the
///        top-level configuration file '/usr/share/alsa/ucm2/ucm.conf'`와 `failed to
///        import hw:0 use case configuration -2` 두 줄을 부팅마다 찍고 범용 방법으로
///        내려온다(design 실측 10). UCM이 필요한 기계(DSP 뒤의 마이크)는 AU-M3이고,
///        그때 alsa-ucm-conf와 함께 이 플래그를 다시 본다
///   -f   기본 경로(/var/lib/alsa/asound.state)가 아닌 파일을 주면 alsactl이 잠금
///        파일을 안 만든다(lock.c). 게스트에 /var/lock이 없어도 된다
///
/// init은 파일을 안 읽으므로 -f가 없다.
pub const RESTORE_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-U", "-f", STATE_PATH.ptr, "restore" };
pub const INIT_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-U", "init" };
pub const STORE_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-f", STATE_PATH.ptr, "store" };

pub fn argvFor(verb: Verb) [*:null]const ?[*:0]const u8 {
    return switch (verb) {
        .restore => &RESTORE_ARGV,
        .init => &INIT_ARGV,
    };
}

pub const Outcome = union(enum) {
    /// alsactl이 0으로 끝났다. 믹서가 섰다
    done,
    /// alsactl이 99로 끝났다. 범용 규칙으로 믹서가 섰다
    generic,
    /// 일꾼이 CARD_WAIT_MS 안에 카드를 못 봤다
    no_card,
    /// alsactl이 0이 아닌 코드로 끝났다. 127이면 execve가 실패한 것이다
    exited: u8,
    /// 시그널에 죽었다
    killed: u32,
};

/// wait의 status를 읽는다. 순수 함수다.
pub fn outcome(status: u32) Outcome {
    if (linux.W.IFEXITED(status)) {
        const code = linux.W.EXITSTATUS(status);
        if (code == 0) return .done;
        if (code == GENERIC_EXIT) return .generic;
        if (code == NO_CARD_EXIT) return .no_card;
        return .{ .exited = code };
    }
    return .{ .killed = @intCast(@intFromEnum(linux.W.TERMSIG(status))) };
}

pub const StoreDecision = enum {
    /// 적는다
    store,
    /// 이 부팅에 믹서를 세우지 못했다. 적으면 커널의 꺼진 기본값이 사람이 남긴
    /// 상태를 덮는다 — 카드가 없었거나, alsactl이 실패했거나, 일꾼이 끝나기 전에
    /// 전원이 눌렸다
    not_set,
    /// `/config`가 없다. tmpfs에 적으면 재부팅에 사라지는 가짜 기억이다
    no_config,
};

/// 끌 때 적을지. 순수 함수다.
pub fn storeDecision(set_this_boot: bool, storage_mounted: bool) StoreDecision {
    if (!set_this_boot) return .not_set;
    if (!storage_mounted) return .no_config;
    return .store;
}

// ── 여기서부터는 시스템 콜을 한다. 위의 넷만 audio_test가 본다 ─────────

/// PID 1의 기억. PID 1은 스레드가 없고 시그널 핸들러는 이 셋을 안 만지므로
/// 그냥 전역이다.
var worker_pid: linux.pid_t = -1;
var worker_verb: Verb = .init;
var storage: bool = false;
/// 일꾼의 alsactl이 0으로 끝났다. `store`가 이것만 본다.
var mixer_set: bool = false;
/// `start`가 받은 env 블록. 끌 때 alsactl store에 같은 것을 준다. 블록은 `main()`의
/// 스택에 살고 `supervise()`가 영영 반환하지 않으므로 종료 경로에서도 유효하다.
const NO_ENV = [_:null]?[*:0]const u8{};
var env: [*:null]const ?[*:0]const u8 = &NO_ENV;

fn sleepMillis(ms: u32) void {
    const req = linux.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast(@as(u64, ms % 1000) * 1_000_000),
    };
    _ = linux.nanosleep(&req, null);
}

fn exists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

/// 카드 노드를 기다린다. 기다린 밀리초를 돌려주고, 상한까지 없으면 null이다.
fn waitForCard() ?u32 {
    var waited: u32 = 0;
    while (true) {
        if (exists(CARD_PATH)) return waited;
        if (waited >= CARD_WAIT_MS) return null;
        sleepMillis(CARD_POLL_MS);
        waited += CARD_POLL_MS;
    }
}

/// 부팅에 한 번 부른다. 일꾼을 fork하고 곧장 돌아온다(feedback_boot_never_blocks).
///
/// 일꾼은 execve 전에 우리 코드로 최대 5초를 머무므로 시그널 정책을 기본값으로
/// 되돌린다(power.resetToDefault의 주석) — 안 그러면 그 사이에 눌린 전원 버튼의
/// SIGTERM에 안 죽고 종료가 유예 3초를 다 쓴다.
pub fn start(storage_mounted: bool, envp: [*:null]const ?[*:0]const u8) void {
    storage = storage_mounted;
    env = envp;
    worker_verb = verbFor(storage_mounted, storage_mounted and exists(STATE_PATH));

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: audio: cannot fork (errno {d}), the mixer is left as the kernel set it\n", .{@intFromEnum(e)});
        return;
    }
    if (pid == 0) {
        power.resetToDefault();
        const waited = waitForCard() orelse linux.exit(NO_CARD_EXIT);
        // 기다린 적이 있을 때만 찍는다(mountConfig와 같은 규칙).
        if (waited > 0) std.debug.print("tars-init: audio: sound card appeared after {d}ms\n", .{waited});
        _ = linux.execve(ALSACTL_PATH.ptr, argvFor(worker_verb), envp);
        std.debug.print("tars-init: cannot exec {s}\n", .{ALSACTL_PATH});
        linux.exit(127);
    }
    worker_pid = @intCast(pid);
    std.debug.print("tars-init: audio: alsactl {s} once a sound card shows up (pid {d})\n", .{ @tagName(worker_verb), pid });
}

/// 감독 루프가 감독 목록에 없는 pid를 거둘 때 먼저 묻는다. 일꾼이면 그 끝을 로그
/// 한 줄로 남기고 true다. 아니면 false이고 감독 루프가 고아로 센다.
///
/// 따로 묻는 이유는 terminal 체인이 `reaped orphan pid`를 "재부모화된 셸을
/// 거뒀다"의 증거로 보기 때문이다. 일꾼을 고아로 찍으면 그 검사가 우리 일꾼
/// 덕에 초록이 될 수 있다.
pub fn reaped(pid: linux.pid_t, status: u32) bool {
    if (worker_pid < 0 or pid != worker_pid) return false;
    worker_pid = -1;
    const verb = @tagName(worker_verb);
    const got = outcome(status);
    switch (got) {
        .done, .generic => {
            mixer_set = true;
            // 99는 끝에 덧붙인다. 앞머리가 같아야 게이트가 한 글자로 둘을 다 받는다.
            const tail: []const u8 = if (got == .generic) " (generic rules, exit 99)" else "";
            switch (worker_verb) {
                .restore => std.debug.print("tars-init: audio: alsactl restore set the mixer from {s}{s}\n", .{ STATE_PATH, tail }),
                .init => std.debug.print("tars-init: audio: alsactl init turned the mixer on{s}\n", .{tail}),
            }
        },
        .no_card => std.debug.print("tars-init: audio: no sound card within {d}ms, the mixer is left alone\n", .{CARD_WAIT_MS}),
        .exited => |code| std.debug.print("tars-init: audio: alsactl {s} exited {d}, the mixer is left as the kernel set it\n", .{ verb, code }),
        .killed => |sig| std.debug.print("tars-init: audio: alsactl {s} was killed (signal {d})\n", .{ verb, sig }),
    }
    return true;
}

/// 종료 경로에서 한 번 부른다(power.shutdown). 모든 프로세스가 거둬진 뒤이고 sync
/// 앞이다. 기다리되 STORE_WAIT_MS가 상한이다.
///
/// 자식은 곧바로 execve하므로 시그널 정책을 되돌릴 일이 없다. 그리고 이 자식은
/// `kill(-1, …)` 뒤에 태어나므로 그 시그널을 안 받는다.
pub fn store() void {
    switch (storeDecision(mixer_set, storage)) {
        .store => {},
        .not_set => {
            std.debug.print("tars-init: audio: mixer not stored, it was not set this boot\n", .{});
            return;
        },
        .no_config => {
            std.debug.print("tars-init: audio: mixer not stored, no /config\n", .{});
            return;
        },
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: audio: cannot fork for alsactl store (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    if (pid == 0) {
        _ = linux.execve(ALSACTL_PATH.ptr, &STORE_ARGV, env);
        std.debug.print("tars-init: cannot exec {s}\n", .{ALSACTL_PATH});
        linux.exit(127);
    }

    var waited: u32 = 0;
    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, linux.W.NOHANG, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: audio: waiting for alsactl store failed (errno {d})\n", .{@intFromEnum(e)});
            return;
        }
        if (rc != 0) break;
        if (waited >= STORE_WAIT_MS) {
            _ = linux.kill(@intCast(pid), .KILL);
            _ = linux.wait4(@intCast(pid), &status, 0, null);
            std.debug.print("tars-init: audio: alsactl store did not finish in {d}ms, killed it\n", .{STORE_WAIT_MS});
            return;
        }
        sleepMillis(STORE_POLL_MS);
        waited += STORE_POLL_MS;
    }
    switch (outcome(status)) {
        .done => std.debug.print("tars-init: audio: stored the mixer in {s}\n", .{STATE_PATH}),
        .generic => std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{GENERIC_EXIT}),
        .no_card => std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{NO_CARD_EXIT}),
        .exited => |code| std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{code}),
        .killed => |sig| std.debug.print("tars-init: audio: alsactl store was killed (signal {d})\n", .{sig}),
    }
}
```

`init/src/audio_test.zig`:

```zig
const std = @import("std");
const audio = @import("audio.zig");

// AU-M1. 믹서를 켜고 적는 배관의 순수한 쪽 넷. 게스트에서 alsactl이 실제로 믹서를
// 바꾸는 것은 audio 체인이 샘플의 값으로 본다 — 여기는 그 앞에서 "어느 동사로 ·
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.

fn fail(comptime fmt: []const u8, args: anytype) error{Mismatch} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Mismatch;
}

/// argv를 글자 하나로 펴서 기대하는 글자와 비교한다. 기대값을 상수에서 다시 짓지
/// 않고 손으로 적는다 — 그래야 이 검사가 tautology가 아니다(clock_test와 같은 이유).
fn expectArgv(what: []const u8, argv: [*:null]const ?[*:0]const u8, want: []const u8) !void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    var i: usize = 0;
    while (argv[i]) |arg| : (i += 1) {
        const a = std.mem.span(arg);
        if (i > 0) {
            buf[len] = ' ';
            len += 1;
        }
        @memcpy(buf[len .. len + a.len], a);
        len += a.len;
    }
    if (!std.mem.eql(u8, buf[0..len], want)) return fail("{s} argv is '{s}', want '{s}'", .{ what, buf[0..len], want });
}

fn expectOutcome(status: u32, want: audio.Outcome) !void {
    const got = audio.outcome(status);
    if (!std.meta.eql(got, want)) return fail("status 0x{x} reads as {any}, want {any}", .{ status, got, want });
}

pub fn main() !void {
    // ── 어느 동사로 켜나 ────────────────────────────────────────────────
    //
    // 파일은 `/config`가 붙었을 때만 의미가 있다. 붙지 않은 부팅의 `/config`는 tmpfs의
    // 빈 디렉터리라 파일이 있을 수 없지만, 있다고 해도 init이어야 한다.
    if (audio.verbFor(true, true) != .restore) return fail("mounted with a state file must restore", .{});
    if (audio.verbFor(true, false) != .init) return fail("mounted without a state file must init", .{});
    if (audio.verbFor(false, false) != .init) return fail("no /config must init", .{});
    if (audio.verbFor(false, true) != .init) return fail("no /config must init even if a file is seen", .{});
    std.debug.print("audio_test: restore only with /config and a state file, init otherwise\n", .{});

    // ── 어떤 인자로 ─────────────────────────────────────────────────────
    //
    // -U가 빠지면 부팅마다 UCM 경고 두 줄이 찍힌다. -f가 빠지면 alsactl이 기본 경로
    // (/var/lib/alsa)를 쓰고 잠금 파일을 /var/lock에 만들려 든다 — 게스트에 둘 다 없다.
    try expectArgv("restore", audio.argvFor(.restore), "/usr/bin/alsactl -U -f /config/asound.state restore");
    try expectArgv("init", audio.argvFor(.init), "/usr/bin/alsactl -U init");
    try expectArgv("store", &audio.STORE_ARGV, "/usr/bin/alsactl -f /config/asound.state store");
    std.debug.print("audio_test: alsactl gets -U, and -f /config/asound.state wherever a file is read or written\n", .{});

    // ── 끝을 어떻게 읽나 ────────────────────────────────────────────────
    //
    // wait status의 모양은 커널의 것이다 — 정상 종료는 코드가 둘째 바이트, 시그널은
    // 첫 바이트의 아래 일곱 비트. 99는 alsactl이 범용 규칙으로 켠 것(성공)이고, 254는
    // 일꾼이 카드를 못 본 것이고, 2는 restore가
    // 파일을 못 연 것(ENOENT)이고, 127은 execve가 실패한 것이다.
    try expectOutcome(0x0000, .done);
    try expectOutcome(99 << 8, .generic);
    try expectOutcome(254 << 8, .no_card);
    try expectOutcome(127 << 8, .{ .exited = 127 });
    try expectOutcome(2 << 8, .{ .exited = 2 });
    try expectOutcome(9, .{ .killed = 9 });
    try expectOutcome(15, .{ .killed = 15 });
    std.debug.print("audio_test: a wait status reads as done, generic (99), no card, an exit code or a signal\n", .{});

    // ── 끌 때 적나 ─────────────────────────────────────────────────────
    //
    // 이 부팅에 믹서를 못 세웠으면 안 적는다. 적으면 커널의 꺼진 기본값이 사람이
    // 남긴 파일을 덮는다 — 일꾼이 카드를 기다리는 사이에 전원 버튼이 눌린 경우다.
    if (audio.storeDecision(true, true) != .store) return fail("set and mounted must store", .{});
    if (audio.storeDecision(true, false) != .no_config) return fail("set without /config must not store", .{});
    if (audio.storeDecision(false, true) != .not_set) return fail("not set must not store", .{});
    if (audio.storeDecision(false, false) != .not_set) return fail("not set without /config must not store", .{});
    std.debug.print("audio_test: the mixer is stored only when it was set this boot and /config is there\n", .{});
}
```

### 1-2. `main.zig` — 편집 셋

E1이 import, E2가 감독 루프의 고아 갈래 앞에 일꾼을 묻는 한 줄, E3이 `firewall.up` 앞에 일꾼을 띄우는 한 줄이다.

E1 — `old_string`(기준 파일 14줄부터):

```zig
const control = @import("control.zig");
```

`new_string`:

```zig
const control = @import("control.zig");
const audio = @import("audio.zig");
```

E2 — `old_string`(기준 파일 598줄부터):

```zig
            const c = find(children, pid) orelse {
```

`new_string`:

```zig
            const c = find(children, pid) orelse {
                // AU-M1. 소리 일꾼은 감독 목록에 없지만 고아도 아니다 — 그 끝을
                // audio.zig가 읽는다(믹서를 세웠는지가 끌 때 적을지를 정한다).
                if (audio.reaped(pid, status)) continue;
```

E3 — `old_string`(기준 파일 950줄부터):

```zig
    // FW-M1. dhcpcd보다 앞인 것이 이 한 줄의 유일한 제약이다(FW design 결정
```

`new_string`:

```zig
    // AU-M1. 믹서를 켠다(AU design 결정 4). 기다리지 않는다 — 일꾼 하나를 fork하고
    // 곧장 다음 줄로 간다. 일꾼이 카드를 기다렸다가 alsactl이 되고, 그 끝은 감독
    // 루프가 거둘 때 audio.zig가 읽는다. 아래 nft를 기다리는 동안 함께 돈다.
    // `/config`가 붙었는지가 restore와 init을 가르고, 끌 때 적을지도 정한다.
    audio.start(storage_mounted, envp);

    // FW-M1. dhcpcd보다 앞인 것이 이 한 줄의 유일한 제약이다(FW design 결정
```

### 1-3. `power.zig` — 편집 둘

E1이 import, E2가 `reapAll` 뒤 · `sync` 앞의 `audio.store()`다.

E1 — `old_string`(기준 파일 2줄부터):

```zig
const linux = std.os.linux;
```

`new_string`:

```zig
const linux = std.os.linux;
const audio = @import("audio.zig");
```

E2 — `old_string`(기준 파일 249줄부터):

```zig
    // 커널은 reboot(2)에서 sync를 대신 해주지 않는다. 리눅스 소스의
```

`new_string`:

```zig
    // AU-M1. 믹서를 /config/asound.state에 적는다(AU design 결정 4). 모든 프로세스가
    // 거둬진 뒤인 이유는 그 뒤로 믹서를 만질 것이 아무도 없어서이고, sync 앞인 이유는
    // 적은 것이 디스크에 닿아야 해서다. 적을지 말지와 기다리는 상한은 audio.zig가 정한다.
    audio.store();

    // 커널은 reboot(2)에서 sync를 대신 해주지 않는다. 리눅스 소스의
```

### 1-4. `build.zig` — 편집 둘

E1 — `old_string`(기준 파일 242줄부터):

```zig
    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

`new_string`:

```zig
    // AU-M1: 믹서를 켜고 적는 배관의 순수한 쪽(동사 · argv · wait status · 적을지).
    // clock_test와 같은 이유로 host_target이다 — audio.zig에서 시스템 콜을 하는
    // 부분은 이 넷 아래에만 있다.
    const audio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/audio_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const audio_test = b.addExecutable(.{
        .name = "audio_test",
        .root_module = audio_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
```

E2 — `old_string`(기준 파일 257줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(wifi_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(wifi_test).step);
    test_step.dependOn(&b.addRunArtifact(audio_test).step);
```

### 1-5. 확인과 호스트 검사

```bash
for f in init/src/audio.zig init/src/audio_test.zig init/src/main.zig init/src/power.zig init/build.zig; do
  cmp $f /tmp/run/au1/new/$f && echo "SAME $f"; done
mkdir -p /tmp/run/au1/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out
  cd init
  zig build test > /tmp/test.log 2>&1; echo "test exit=$?"
  grep -E "^audio_test:|FAIL|error:" /tmp/test.log
  zig build && stat -c "%s init" zig-out/bin/init'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 다섯, `test exit=0`, `audio_test:` 줄 넷, `3776512 init`.

```
audio_test: restore only with /config and a state file, init otherwise
audio_test: alsactl gets -U, and -f /config/asound.state wherever a file is read or written
audio_test: a wait status reads as done, generic (99), no card, an exit code or a signal
audio_test: the mixer is stored only when it was set this boot and /config is there
```

## Task 2: `kernel/guest_tools.sh` — 층 14에 `alsactl`

확정 1의 첫째. 편집 셋 — `amixer` 주석을 M1의 사실로 고치고, M0의 "alsactl은 안 싣는다" 두 줄을 지우고, `alsactl`을 더한다.

E1 — `old_string`(기준 파일 355줄부터):

```bash
  #   amixer        믹서. 커널이 소리를 꺼 둔 채 뜨므로(AU design 결정 4) 사람이
  #                 처음 치는 것이 `amixer sset Master unmute`다. AU-M1이 그 일을
  #                 부팅으로 옮길 때까지는 이것이 유일한 길이다
```

`new_string`:

```bash
  #   amixer        믹서. 커널은 소리를 꺼 둔 채 뜨고(AU design 결정 4) 부팅이
  #                 아래 alsactl로 켠다(AU-M1). 사람은 이것으로 볼륨을 바꾸고,
  #                 바꾼 것은 끌 때 /config/asound.state에 남는다
```

E2 — `old_string`(기준 파일 365줄부터):

```bash
  # 것이고 initrd에는 이번에 처음 들어간다. alsactl은 안 싣는다 — 부팅에 믹서를
  # 되살리는 일은 AU-M1이고, 어떻게 할지는 그 milestone이 정한다.
```

`new_string`:

```bash
  # 것이고 initrd에는 이번에 처음 들어간다.
```

E3 — `old_string`(기준 파일 372줄부터):

```bash
  usr/bin/speaker-test:usr/bin/speaker-test
```

`new_string`:

```bash
  usr/bin/speaker-test:usr/bin/speaker-test

  # AU-M1. 믹서를 파일로 되살리고 파일에 적는 도구다. 사람보다 init이 먼저 쓴다 —
  # 부팅에 `alsactl restore`(파일이 없으면 `alsactl init`)로 소리를 켜고, 끌 때
  # `alsactl store`로 사람이 바꾼 볼륨을 /config/asound.state에 남긴다
  # (init/src/audio.zig, AU design 결정 4). 사람이 직접 칠 일은 드물다.
  #
  # dhcpcd · chronyd와 같은 이유로 왼쪽과 오른쪽이 다르다 — 패키지는 /usr/sbin에
  # 두는데 게스트의 PATH는 /usr/bin:/bin이다. 오른쪽이 audio.zig의 ALSACTL_PATH와
  # 같은 글자여야 한다. 130,584바이트, 새 라이브러리 0개(libasound는 위 넷이
  # 이미 데려왔다).
  usr/sbin/alsactl:usr/bin/alsactl
```

```bash
cmp kernel/guest_tools.sh /tmp/run/au1/new/kernel/guest_tools.sh && echo SAME-guest_tools
bash -n kernel/guest_tools.sh && echo SYNTAX-OK
git diff kernel/guest_tools.sh | rg '^-[^-]'
```

기대: `SAME-guest_tools` · `SYNTAX-OK`, 지운 줄 다섯은 `amixer` 주석 셋과 "alsactl은 안 싣는다" 두 줄이다.

## Task 3: `audio/probe.sh` · `audio/check.sh` · `check.sh`

확정 4 · 5.

### 3-1. `audio/probe.sh` — 편집 넷

E1 — `old_string`(기준 파일 12줄부터):

```bash
# 끝나면 잠든다. 감독자는 끝난 서비스를 다시 띄우므로(SV), 일을 마친 뒤에 나가면
```

`new_string`:

```bash
# 같은 디스크로 두 번 뜬다(AU-M1). 어느 쪽인지는 /config/asound.state가 가른다 —
# 그 파일은 init이 끌 때 쓰므로 첫 부팅의 프로브가 시작할 때는 아직 없다.
#   first  사람이 볼륨을 바꾸고, 소리를 내고 받고, 전원을 끈다(kill -TERM 1)
#   again  믹서를 안 만지고 소리를 낸다. 첫 부팅이 바꾼 볼륨이 남았는지를 본다
#
# 끝나면 잠든다. 감독자는 끝난 서비스를 다시 띄우므로(SV), 일을 마친 뒤에 나가면
```

E2 — `old_string`(기준 파일 19줄부터):

```bash
flat() { tr '\n' '|' | sed 's/|$//'; }
```

`new_string`:

```bash
flat() { tr '\n' '|' | sed 's/|$//'; }

if [ -e /config/asound.state ]; then boot=again; else boot=first; fi
say "boot ${boot}"
```

E3 — `old_string`(기준 파일 31줄부터):

```bash
# 2. 부팅이 남긴 믹서. 커널의 HDA 드라이버는 Master와 Capture를 0에 꺼 둔 채 뜬다.
# AU-M1이 부팅에서 되살리기 전까지는 사람이 아래 3을 손으로 한다.
say "master at boot [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

# 3. 사람이 하는 일 — 소리를 켠다. 0dB인 이유는 체인이 샘플을 바이트로 비교하기
# 때문이다. QEMU의 HDA 코덱이 이 값을 샘플에 그대로 곱한다.
amixer -q -c 0 sset Master 0dB unmute
amixer -q -c 0 sset Capture 0dB cap
```

`new_string`:

```bash
# 2. 부팅이 켠 믹서(AU-M1). init의 일꾼도 이 카드를 기다렸다가 alsactl이 되므로 이
# 프로브와 나란히 돈다. alsactl이 끝나고 Master가 켜질 때까지 10초를 기다린다 —
# 켜는 것이 아무도 없으면 10초 뒤에 꺼진 그대로를 찍고, 체인이 그 값으로 빨개진다.
for _ in $(seq 1 100); do
  if ! pgrep -x alsactl >/dev/null && amixer -c 0 sget Master 2>/dev/null | grep '\[on\]' >/dev/null; then break; fi
  sleep 0.1
done
say "master at boot [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

if [ "$boot" = again ]; then
  # 3'. 믹서를 안 만지고 재생한다. 사각파가 값까지 같게 나가면 첫 부팅이 바꾼 0dB가
  # 되살아난 것이다 — alsactl init의 -20dB였다면 값이 바뀐다.
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  say "done"
  exec sleep 100000
fi

# 3. 사람이 하는 일 — 볼륨을 바꾼다. 부팅이 켠 Master는 -20dB이고 이것을 0dB로 올린다.
# 0dB인 이유는 체인이 샘플을 바이트로 비교하기 때문이다(QEMU의 HDA 코덱이 이 값을
# 샘플에 그대로 곱한다). Capture는 안 만진다 — 부팅이 켠 0dB 그대로 아래 5에서 쓴다.
amixer -q -c 0 sset Master 0dB
```

E4 — `old_string`(기준 파일 53줄부터):

```bash

exec sleep 100000
```

`new_string`:

```bash

# 6. 전원을 끈다. 사람이 전원 버튼을 누르는 것과 같은 길이다(PID 1의 SIGTERM). init이
# 모두를 거둔 뒤 alsactl store로 위 3의 0dB를 /config/asound.state에 적는다. uptime은
# 체인이 커널의 `reboot: Power down` 시각과 빼서 끄는 데 걸린 시간을 찍는 데 쓴다.
say "powering off at uptime $(cut -d' ' -f1 /proc/uptime)"
kill -TERM 1
exec sleep 100000
```

### 3-2. `audio/check.sh` — 편집 열하나

E1 — `old_string`(기준 파일 25줄부터):

```bash
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘(AU-M2 · M3), 부팅이 믹서를 되살리는 것(AU-M1). 검사 4가 지금은 "부팅이 소리를
# 꺼 둔 채 둔다"를 보고, M1이 그 검사를 뒤집는다.
```

`new_string`:

```bash
# 부팅이 셋이다(AU-M1).
#
#   A  새 디스크. init이 alsactl init으로 소리를 켠다(검사 4). 프로브가 사람처럼 Master를
#      0dB로 올리고, 소리를 내고 받고(검사 5~7), 전원을 끈다. init이 끄는 길에서
#      alsactl store로 그 0dB를 디스크의 asound.state에 적는다(검사 8)
#   B  같은 디스크. init이 alsactl restore로 0dB를 되살리고, 프로브는 믹서를 안 만진 채
#      재생한다 — 사각파가 값까지 같으면 A의 0dB가 남은 것이다(검사 9 · 10)
#   C  설정 디스크 없이(ISO와 같은 모양). init이 alsactl init으로 켜기만 한다(검사 11)
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘 · 부팅 뒤에 꽂힌 카드(AU-M2 · M3).
```

E2 — `old_string`(기준 파일 72줄부터):

```bash
    "tars-init: started service probe (pid" \
```

`new_string`:

```bash
    "tars-init: audio: alsactl" \
    "tars-init: started service probe (pid" \
    "audio-probe: boot " \
```

E3 — `old_string`(기준 파일 79줄부터):

```bash
    "audio-probe: done"; do
```

`new_string`:

```bash
    "audio-probe: done" \
    "tars-init: audio: stored the mixer" \
    "tars-init: calling reboot"; do
```

E4 — `old_string`(기준 파일 86줄부터):

```bash
  echo "--- audio-probe lines ---"
  grep -a "audio-probe:" "$LOG" | tail -n 20
```

`new_string`:

```bash
  echo "--- audio lines ---"
  grep -aE "audio-probe:|tars-init: audio:" "$LOG" | tail -n 24
```

E5 — `old_string`(기준 파일 106줄부터):

```bash
  QEMU_PID=""
```

`new_string`:

```bash
  QEMU_PID=""
}

# 게스트가 스스로 꺼지기를 기다린다(power 체인과 같은 판정 — 로그의 글자가 아니라
# 프로세스가 사라졌는가). 꺼졌으면 거두고 0이다.
wait_for_exit() {
  local seconds="$1" i
  for i in $(seq 1 "$seconds"); do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      wait "$QEMU_PID" 2>/dev/null || true
      QEMU_PID=""
      return 0
    fi
    sleep 1
  done
  return 1
```

E6 — `old_string`(기준 파일 192줄부터):

```bash
# ══ 부팅 하나 ═══════════════════════════════════════════════════════════
# q35인 이유는 nic · machine 체인과 같다 — 노트북에 가까운 칩셋이고, ich9-intel-hda가
```

`new_string`:

```bash
# q35인 이유는 nic · machine 체인과 같다 — 노트북에 가까운 칩셋이고, ich9-intel-hda가
```

E7 — `old_string`(기준 파일 198줄부터):

```bash
echo "=== boot: q35 with an HDA controller and a speaker + microphone codec ==="
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!
```

`new_string`:

```bash
#
# 인자 하나가 설정 디스크를 붙일지를 고른다(부팅 C는 안 붙인다). 로그는 부팅마다 비운다.
start_guest() {
  local drive=()
  [ "$1" = with-disk ] && drive=(-drive file="$DISK",if=virtio,format=raw)
  : > "$LOG"
  HOME="$WORK" qemu-system-x86_64 \
    -machine q35 \
    -nic none \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    "${drive[@]}" \
    -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
    -device ich9-intel-hda \
    -device hda-micro,audiodev=snd0 \
    -serial file:"$LOG" \
    -no-reboot &
  QEMU_PID=$!
}

# ══ 부팅 A: 새 디스크 ═══════════════════════════════════════════════════
echo "=== boot A: q35 with an HDA controller and a speaker + microphone codec, a fresh config disk ==="
start_guest with-disk
```

E8 — `old_string`(기준 파일 219줄부터):

```bash
# 여는 파일이다 — 제어(controlC0) · 재생(pcmC0D0p) · 녹음(pcmC0D0c).
```

`new_string`:

```bash
# 여는 파일이다 — 제어(controlC0) · 재생(pcmC0D0p) · 녹음(pcmC0D0c).
#
# 프로브는 일을 마치면 kill -TERM 1로 전원을 끈다. 그래서 여기서는 QEMU를 죽이지 않고
# 스스로 사라지기를 기다린다 — 그 길에서 init이 믹서를 적는다(검사 8).
```

E9 — `old_string`(기준 파일 223줄부터):

```bash
  || report_failure "the probe did not finish"
stop_guest
```

`new_string`:

```bash
  || report_failure "the probe did not finish"
wait_for_exit 30 \
  || report_failure "the guest never switched itself off after the probe's kill -TERM 1"
```

E10 — `old_string`(기준 파일 244줄부터):

```bash
# ── 검사 4: 부팅은 소리를 꺼 둔 채 둔다 (AU-M1이 뒤집는다) ─────────────
# 아래 검사 5 · 7의 대조군이다. 프로브가 켜기 전의 믹서가 꺼져 있으므로, 5 · 7이
# 초록이면 그것은 프로브의 amixer 두 줄이 한 일이다 — 그 두 줄을 지우면 5가 무음으로
# 빨개진다(AU-M0 plan의 mutation 3). M1이 부팅에서 소리를 켜면 이 검사가 그 일을 본다.
if ! grep -aE 'audio-probe: master at boot \[.*Playback 0 \[0%\].*\[off\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not muted at boot; if something now unmutes it, AU-M1 owns this check"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 0 \[0%\].*\[off\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not off at boot; if something now turns it on, AU-M1 owns this check"
fi
if ! grep -aE 'audio-probe: master now \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "amixer could not set Master to 0dB and unmute it"
fi
echo "the boot leaves Master and Capture muted, and amixer turns them on"
```

`new_string`:

```bash
# ── 검사 4: 부팅이 소리를 켠다 (AU-M1) ──────────────────────────────────
# 커널은 Master와 Capture를 0에 꺼 둔 채 카드를 올린다(AU-M0의 이 검사가 그것을 봤다).
# 새 디스크에는 asound.state가 없으므로 init이 alsactl init을 부르고, 그 기본값이
# Master -20dB · Capture 0dB, 둘 다 켜짐이다. 프로브는 Capture를 안 만지므로 아래
# 검사 7의 녹음이 값까지 같으면 그것은 부팅이 켠 Capture가 한 일이다.
if ! grep -aF 'tars-init: audio: alsactl init turned the mixer on' "$LOG" >/dev/null; then
  report_failure "init did not turn the mixer on with alsactl init"
fi
if ! grep -aF 'audio-probe: boot first' "$LOG" >/dev/null; then
  report_failure "the probe found an asound.state on a fresh disk"
fi
if ! grep -aE 'audio-probe: master at boot \[.*Playback 54 \[73%\] \[-20\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not at alsactl init's -20dB and on at boot"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not at alsactl init's 0dB and on at boot"
fi
if ! grep -aE 'audio-probe: master now \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "amixer could not set Master to 0dB"
fi
# 음성. init은 alsactl에 -U를 준다 — 빠지면 alsactl이 initrd에 없는 UCM 설정을 찾다가
# 부팅마다 경고 두 줄을 찍는다(AU design 실측 10). UCM은 AU-M3의 질문이다.
if grep -aF 'ucm2/ucm.conf' "$LOG" >/dev/null; then
  report_failure "alsactl looked for UCM; init must pass -U until AU-M3 ships alsa-ucm-conf"
fi
echo "the boot turned Master and Capture on with alsactl init, and amixer raised Master to 0dB"
```

E11 — `old_string`(기준 파일 328줄부터):

```bash
echo "AU check PASS"
```

`new_string`:

```bash
# ── 검사 8: 끄는 길에서 init이 믹서를 디스크에 적었나 ──────────────────
# store는 모든 프로세스를 거둔 뒤, sync 앞이다. 디스크의 asound.state에서 Master의
# 볼륨 줄을 읽어 프로브가 올린 74(0dB)인지 본다 — 부팅 B가 되살리는 것이 이 값이다.
if ! grep -aF 'tars-init: audio: stored the mixer in /config/asound.state' "$LOG" >/dev/null; then
  report_failure "init did not store the mixer on the way down"
fi
debugfs -R "dump asound.state $WORK/asound.state" "$DISK" >/dev/null 2>&1
[ -s "$WORK/asound.state" ] || report_failure "the config disk holds no asound.state after the power-off"
STATE_MASTER="$(perl -0777 -ne "print \$1 if /name 'Master Playback Volume'\s+value\.0 (\d+)/" "$WORK/asound.state")"
if [ "$STATE_MASTER" != 74 ]; then
  report_failure "asound.state keeps Master Playback Volume at '${STATE_MASTER}', want 74 (0dB)"
fi
echo "the power-off stored the mixer, and asound.state keeps Master at 74 (0dB)"
# 판정이 아니라 기록이다. 프로브가 kill -TERM 1을 친 uptime부터 커널이 전원을 내린
# 시각까지 — store가 종료 경로에 더한 몫이 이 안에 있다(상한 STORE_WAIT_MS 2초).
ASKED="$(grep -aoE 'audio-probe: powering off at uptime [0-9.]+' "$LOG" | grep -oE '[0-9.]+$')"
DOWN="$(grep -aoE '\[ *[0-9.]+\] reboot: Power down' "$LOG" | grep -oE '[0-9]+\.[0-9]+')"
echo "shutdown: asked at ${ASKED:-?}s, powered down at ${DOWN:-?}s"

# ══ 부팅 B: 같은 디스크 ════════════════════════════════════════════════
# 같은 tap 파일 이름을 QEMU가 다시 연다. A의 것은 옆으로 치운다.
mv "$WORK/tap.raw" "$WORK/tap_a.raw"
echo "=== boot B: the same disk again ==="
start_guest with-disk
wait_for_log 'audio-probe: done' 90 \
  || report_failure "the probe did not finish on the second boot"
stop_guest

# ── 검사 9: 부팅이 사람이 남긴 볼륨을 되살렸나 ─────────────────────────
# alsactl init이었다면 Master가 -20dB다. 0dB이면 A의 store를 B의 restore가 읽은 것이다.
if ! grep -aF 'tars-init: audio: alsactl restore set the mixer from /config/asound.state' "$LOG" >/dev/null; then
  report_failure "init did not restore the mixer from /config/asound.state"
fi
if ! grep -aF 'audio-probe: boot again' "$LOG" >/dev/null; then
  report_failure "the probe did not find the asound.state the first boot stored"
fi
if ! grep -aE 'audio-probe: master at boot \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not back at the 0dB the first boot left"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not back at 0dB and on"
fi
echo "the second boot restored Master at 0dB and Capture on from the disk"

# ── 검사 10: 되살린 믹서로 사각파가 값까지 나가나 ─────────────────────
# 프로브는 이 부팅에서 amixer를 안 친다. 그래서 값이 같으면 그것은 되살린 0dB의 일이다.
if ! grep -aF 'audio-probe: aplay exit 0 []' "$LOG" >/dev/null; then
  report_failure "aplay failed on the second boot"
fi
[ -f "$WORK/tap.raw" ] || report_failure "QEMU never opened the speaker side on the second boot"
TAP_B="$(count_tap "$WORK/tap.raw")"
echo "tap B: ${TAP_B}"
if [ "$(field "$TAP_B" tone)" -lt 47000 ] || [ "$(field "$TAP_B" other)" -ne 0 ]; then
  report_failure "the restored mixer did not carry the square wave sample for sample (${TAP_B})"
fi
echo "with no amixer, aplay's square wave reached the speaker sample for sample"

# ══ 부팅 C: 설정 디스크 없이 ═══════════════════════════════════════════
# ISO만 꽂은 노트북과 같은 모양이다. 기억할 자리가 없으니 init만 한다. 프로브도 없으므로
# init의 줄 하나를 기다리고 끈다.
echo "=== boot C: no config disk ==="
start_guest no-disk

# ── 검사 11: 디스크가 없어도 소리가 켜진다 ─────────────────────────────
wait_for_log 'tars-init: audio: alsactl init turned the mixer on' 60 \
  || report_failure "without a config disk init did not turn the mixer on"
stop_guest
if ! grep -aF 'tars-init: no disk labelled tars-* among' "$LOG" >/dev/null; then
  report_failure "boot C found a config disk; it must boot without one"
fi
echo "without a config disk the boot still turned the mixer on with alsactl init"

echo "AU check PASS"
```

### 3-3. `check.sh` — AU 문단의 부팅 수

E1 — `old_string`(기준 파일 342줄부터):

```bash
# 같은지로 닫힌다. 게스트에 한 글자도 안 친다. 회차당 부팅 1회.
```

`new_string`:

```bash
# 같은지로 닫힌다. 게스트에 한 글자도 안 친다. 부팅이 믹서를 켜고 끌 때 적는 것(AU-M1)을
# 같은 디스크로 두 번 떠서 보고, 설정 디스크 없이 한 번 더 뜬다. 회차당 부팅 3회.
```

### 3-4. 확인

```bash
for f in check.sh audio/check.sh audio/probe.sh; do cmp $f /tmp/run/au1/new/$f && echo "SAME $f"; done
bash -n audio/check.sh && bash -n audio/probe.sh && bash -n check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./audio/check.sh && require_no_early_exit_pipe ./audio/check.sh &&
  require_explicit_nic ./audio/check.sh && echo ENTRY-OK'
python3 /tmp/run/au1/anchors.py post "$PWD"
ls -l audio/probe.sh
```

기대: `SAME` 셋 · `SYNTAX-OK` · `ENTRY-OK` · `post: 26 edits, 0 bad`, `audio/probe.sh`가 여전히 `-rwxr-xr-x`다.

## Task 4: 체인 한 번과 regression

체인은 하나씩 돈다. 캐시 삭제를 같은 `docker run` 안에 둔다(확정 10).

### 4-1. `audio` 체인

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/au1:/tmp/run/au1 -w /workspace tars-devcontainer bash -c '
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash audio/check.sh > /tmp/run/au1/impl/audio.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
rg -a -n '^(the |aplay|speaker-test|arecord|with|without|tap|cap:|shutdown:|=== boot|AU check|FAIL)' /tmp/run/au1/impl/audio.log
```

기대: `exit=0`, `real`이 2분 안팎. `rg`는 이렇다(사본의 마지막 판).

```
the kernel carries ALSA and HDA, and the initrd carries arecord, libasound, its config, two voices and the audio group
=== boot A: q35 with an HDA controller and a speaker + microphone codec, a fresh config disk ===
the kernel configured the codec as card 0 with a playback and a capture node
aplay -l and arecord -l both see card 0 device 0
the boot turned Master and Capture on with alsactl init, and amixer raised Master to 0dB
tap: frames=194374 tone=48000 left=53060 right=71059 other=0 zero=22255 first_left=50506 first_right=122283
aplay's square wave reached the speaker sample for sample
speaker-test spoke on the left channel, then on the right
cap: frames=96000 match=96000
arecord got the microphone's constant on both channels, 96000 frames of 96000
the power-off stored the mixer, and asound.state keeps Master at 74 (0dB)
shutdown: asked at 9.27s, powered down at 9.471931s
=== boot B: the same disk again ===
the second boot restored Master at 0dB and Capture on from the disk
tap B: frames=49616 tone=48000 left=0 right=0 other=0 zero=1616 first_left=-1 first_right=-1
with no amixer, aplay's square wave reached the speaker sample for sample
=== boot C: no config disk ===
without a config disk the boot still turned the mixer on with alsactl init
AU check PASS
```

`tap:` · `tap B:`의 `frames` · `zero` · `first_*`와 `tap B`의 `tone`(47,842~48,000), `shutdown:`의 두 수는 판마다 다르다. `tap:`의
`tone=48000`(한 판은 47,960이었다) · `left=53060` · `right=71059` · `other=0`과 `cap:` 줄은 판마다 같았다. 빨개지면 `report_failure`가
찍는 표식 · `audio-probe` · `tars-init: audio` 줄 · 마지막 40줄을 그대로 보고한다.

### 4-2. regression — `power` · `service` · `tools` · `config` · `terminal` · `boot` · `install`

확정 8의 일곱이다. 한 컨테이너에서 차례로 돈다. 약 9분이라 Bash 한 번의 상한(10분)에 붙으므로 `run_in_background`로 돌리고 기다린다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/au1:/tmp/run/au1 -w /workspace tars-devcontainer bash -c '
  for c in power service tools config terminal boot install; do s=$(date +%s); bash $c/check.sh > /tmp/run/au1/impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/au1/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/au1/impl/reg.out
rg -a 'init waited|tools the list names' /tmp/run/au1/impl/reg_install.log /tmp/run/au1/impl/reg_tools.log
```

기대: 일곱 다 `exit=0`. `all 92 tools`이고 `init waited`가 1,500ms 이상(사본 1,800ms)이다. `init waited`가 500ms 아래면 멈추고 보고한다.

## Task 5: mutation

확정 7의 표다. 사본은 `/tmp/run/au1/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 5-0. 사본을 만든다

```bash
python3 /tmp/run/au1/make_mut.py "$PWD" /tmp/run/au1/impl/mut
M=/tmp/run/au1/impl/mut
for p in audio_m1.zig:init/src/audio.zig power_m2.zig:init/src/power.zig guest_tools_m3.sh:kernel/guest_tools.sh \
  main_m4.zig:init/src/main.zig probe_m5.sh:audio/probe.sh audio_m6.zig:init/src/audio.zig \
  check_no4.sh:audio/check.sh check_nonow.sh:audio/check.sh check_no8.sh:audio/check.sh; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 9`, 그리고 바뀐 줄 수가 `audio_m1.zig 4` · `power_m2.zig 1` · `guest_tools_m3.sh 1` · `main_m4.zig 1` ·
`probe_m5.sh 1` · `audio_m6.zig 2` · `check_no4.sh 27` · `check_nonow.sh 2` · `check_no8.sh 19`. 다르면 돌리지 말고 보고한다.

`make_mut.py`:

```python
"""AU-M1 plan Task 6의 mutation 사본을 만든다.

사용: python3 make_mut.py <저장소 루트> <출력 디렉터리>
저장소 파일은 읽기만 한다. 사본마다 바꾼 자리가 정확히 한 군데인지 assert한다.
"""
import os
import sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def make(src, dst, old, new):
    s = open(os.path.join(root, src)).read()
    assert s.count(old) == 1, (dst, old[:60])
    path = os.path.join(out, dst)
    open(path, 'w').write(s.replace(old, new))
    os.chmod(path, 0o755)


def cut(src, dst, start, end):
    """src에서 start 줄이 있는 자리부터 end 줄 앞까지를 지운 사본."""
    s = open(os.path.join(root, src)).read()
    assert s.count(start) == 1 and s.count(end) == 1, dst
    a, b = s.index(start), s.index(end)
    path = os.path.join(out, dst)
    open(path, 'w').write(s[:a] + s[b:])
    os.chmod(path, 0o755)


# mutation 1 — restore가 없다(파일이 있어도 init)
make('init/src/audio.zig', 'audio_m1.zig',
     '    return if (storage_mounted and state_exists) .restore else .init;\n',
     '    _ = storage_mounted;\n    _ = state_exists;\n    return .init;\n')
# mutation 2 — 끄는 길에서 안 적는다
make('init/src/power.zig', 'power_m2.zig', '    audio.store();\n', '')
# mutation 3 — 게스트에 alsactl이 없다(execve 실패, 부팅은 계속)
make('kernel/guest_tools.sh', 'guest_tools_m3.sh', '  usr/sbin/alsactl:usr/bin/alsactl\n', '')
# mutation 4 — 감독 루프가 일꾼을 고아로 거둔다(믹서는 섰지만 init이 모른다)
make('init/src/main.zig', 'main_m4.zig', '                if (audio.reaped(pid, status)) continue;\n', '')
# mutation 5 — 프로브가 볼륨을 안 바꾼다(사람이 아무것도 안 했다)
make('audio/probe.sh', 'probe_m5.sh', 'amixer -q -c 0 sset Master 0dB\n', '')
# mutation 6 — -U가 빠진다(호스트 검사와 검사 4의 음성)
make('init/src/audio.zig', 'audio_m6.zig',
     'pub const INIT_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-U", "init" };\n',
     'pub const INIT_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "init" };\n')

# 앞 검사를 건너뛰는 체인 사본(겨냥한 검사까지 가게 한다 — lessons "mutation이 겨냥한 검사에 걸릴 것이라고 믿기")
cut('audio/check.sh', 'check_no4.sh', '# ── 검사 4:', '# TAP의 프레임을 갈래로 센다.')
make('audio/check.sh', 'check_nonow.sh', "if ! grep -aE 'audio-probe: master now",
     "if false && ! grep -aE 'audio-probe: master now")
cut('audio/check.sh', 'check_no8.sh', '# ── 검사 8:', '# ══ 부팅 B: 같은 디스크')
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. 덮은 Zig 파일이 빌드에 들어가게 판마다 `init`의 캐시를
지운다.

```bash
#!/bin/bash
# AU-M1 plan Task 6의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 audio 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 여섯 자리는 차례로 "restore 갈래 · store 호출 · alsactl 줄 · reaped 훅 · 프로브의 amixer · init의 -U"의 수다.
# 덮지 않은 판은 111111이다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  echo \"mounted: \$(grep -c '.restore else .init;' init/src/audio.zig)\$(grep -c '^    audio.store();' init/src/power.zig)\$(grep -c 'usr/sbin/alsactl:usr/bin/alsactl' kernel/guest_tools.sh)\$(grep -c 'audio.reaped(pid, status)' init/src/main.zig)\$(grep -c '^amixer -q -c 0 sset Master 0dB' audio/probe.sh)\$(grep -c '\"-U\", \"init\"' init/src/audio.zig)\"
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^AU check PASS' "$mut/$name.log" | head -2
```

### 5-1. 체인 열한 판

판마다 40초 안팎, 합해서 8분 남짓이다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/au1/impl/mut; X=/tmp/run/au1/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M m1 audio_m1.zig:init/src/audio.zig
  $X $R $I $M m2 power_m2.zig:init/src/power.zig
  $X $R $I $M m2_b power_m2.zig:init/src/power.zig check_no8.sh:audio/check.sh
  $X $R $I $M m3 guest_tools_m3.sh:kernel/guest_tools.sh
  $X $R $I $M m3_play guest_tools_m3.sh:kernel/guest_tools.sh check_no4.sh:audio/check.sh
  $X $R $I $M m4 main_m4.zig:init/src/main.zig
  $X $R $I $M m4_store main_m4.zig:init/src/main.zig check_no4.sh:audio/check.sh
  $X $R $I $M m5 probe_m5.sh:audio/probe.sh
  $X $R $I $M m5_play probe_m5.sh:audio/probe.sh check_nonow.sh:audio/check.sh
  $X $R $I $M m6 audio_m6.zig:init/src/audio.zig; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 7의 표에서 그 판의 `FAIL` 줄이고 `m0`은 `AU check PASS`다. `mounted:`는 `m0`이 `111111`, `m1`이 `011111`, `m2*`가 `101111`,
`m3*`가 `110111`, `m4*`가 `111011`, `m5*`가 `111101`, `m6`이 `111110`이다. 로그에 `Killed`가 보이고 `FAIL: … build failed`로 끝나면
mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시 돈다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어
보고한다. 초록이면 먼저 덮기를 의심한다(`mounted:`).

### 5-2. 호스트 검사 두 판

```bash
M=/tmp/run/au1/impl/mut
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
for m in m1 m6; do
  docker run --rm -v "$PWD":/workspace -v $M/audio_$m.zig:/workspace/init/src/audio.zig:ro -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache; cd init; zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep "^FAIL" /tmp/t.log'
done
rmdir /tmp/run/docker.lock
```

기대: 두 판 다 `test exit=`가 0이 아니고, `FAIL` 줄이 확정 7의 둘째 표와 같다.

### 5-3. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. `init`과 initrd만 지금 소스로 다시 만들고 체인을 한 번 더 돈다
(데운 판, 1분 안쪽).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /tmp/a.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/a.log'
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `AU check PASS`. `git status`는 `M` 일곱(`check.sh` · `audio/check.sh` · `audio/probe.sh` · `init/build.zig` ·
`init/src/main.zig` · `init/src/power.zig` · `kernel/guest_tools.sh`)과 `??` 둘(`init/src/audio.zig` · `init/src/audio_test.zig`)이고,
plan이 commit 전이면 그것이 더 있다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 5-4. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `7 files changed, 240 insertions(+), 47 deletions(-)`였다(새 파일
  둘은 `git diff`에 안 나온다 — `git add -N` 뒤에는 9 files, 602 insertions).
- Task 0의 출력.
- Task 1~3의 확인 출력(`SAME` · `SYNTAX-OK` · `ENTRY-OK` · `anchors.py` · 호스트 검사).
- Task 4의 `exit=` · `real` · `rg` 출력과 regression 일곱의 줄 · `init waited` · `all 92 tools`.
- Task 5의 `diff` 수 아홉 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 5-2의 두 판, 5-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 6: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 아홉 파일을 `/tmp/run/au1/new/`와 `cmp`한다. Task 4의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스무 체인 × 2다. 판정은 `PASS: 2/2` × 20과 `AU check PASS` 둘이다. `run_in_background`로
   돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_au1.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_au1.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_au1.log`가 20,
   `rg -c 'AU check PASS' /tmp/gate_au1.log`가 2여야 한다.
3. 실측 절 채우기, design에 덧붙이기(아래 "design과 다르게 적은 것"), design `Status:`(M1 끝, M2 plan 차례).
4. commit. 넣는 것은 아홉 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다.

## design과 다르게 적은 것

design 본문은 이 plan이 안 고쳤다. lead가 넣을 것.

1. 결정 4의 "M1이 정할 것" 셋에 답이 생겼다 — 확정 1의 첫째~다섯째가 그 본문이다. design의 결정 4 끝에 "M1이 정한 것" 문단으로
   붙이거나 결정 7로 따로 세운다. 요지: 일꾼을 fork하고 안 기다린다 · 파일이 있으면 restore 없으면 init · `-U` · 99는 성공 · 끄는 길의
   `reapAll` 뒤 `sync` 앞에서 store(2초 상한) · 이 부팅에 믹서를 세웠고 `/config`가 있을 때만 적는다 · `tars.conf` 키 없음.
2. lead의 전제를 바로잡은 것 한 줄 — `init`이 firewall처럼 alsactl을 기다리는 모양이 아니다. 근거는 확정 1의 표 (b).
3. 결정 5(게이트)의 검사 표 — 검사 4가 뒤집혔고 8~11이 더해졌다. 부팅이 셋이고, 전원은 프로브의 `kill -TERM 1`로 끈다(monitor 없음,
   45491은 여전히 비어 있다).
4. 실측 한 덩이 — `alsactl init`의 종료 코드 99(범용 규칙), restore가 파일이 없을 때 exit 2, `-f`가 잠금을 끈다, `save_state`가 카드별로
   합친다, QEMU에서 카드가 PID 1보다 2.5초 먼저 선다, 상태 파일 134줄, store가 종료에 더하는 50ms 남짓.
5. Milestone 절의 AU-M2 — 부팅 뒤에 꽂힌 카드(확정 1의 셋째)가 M2의 정할 것에 더해진다.
6. 위험 하나 — 프로브가 일꾼과 나란히 돌아 부팅이 켠 믹서를 기다린다(확정 4). 체인이 느린 판에서 10초를 넘기면 검사 4가 꺼진 값으로
   빨개진다. 사본에서는 1초 안이었다.
7. design의 "닫을 때"의 running-tars.md 명령 — `amixer sset Master unmute 80%` 줄의 주석 "M1 전에는 부팅마다"를 "M1부터는 부팅이 켜고,
   바꾼 볼륨은 끌 때 남는다"로.

## 이 milestone에서 안 하는 것

- 부팅 뒤에 꽂힌 카드를 켜는 것(M2). M1의 커널에는 USB 오디오 드라이버가 없다.
- UCM(alsa-ucm-conf) — M3. 그때 `-U`를 다시 본다.
- `tars.conf`의 소리 키. 사람의 볼륨이 곧 설정이다.
- 볼륨 · 음소거 키(design 비목표 5).
- `running-tars.md`의 소리 절. lead가 서브프로젝트를 닫을 때 쓴다.

## AU-M1이 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-06에 main 작업 트리에서 했고, lead가 아홉 파일을 `/tmp/run/au1/new/`와 `cmp`해 전부 같은
것을 봤다. 로그는 `/tmp/run/au1/impl/`(`audio.log` · `audio_try1.log` · `reg_*.log` · `mut/` · `flaky/`), 루트 게이트는
`/tmp/gate_au1.log`.

1. 편집과 검사. `git diff --stat`이 7 files +240 −47(새 파일 둘은 밖), 지운 줄은 전부 의도한 것. `zig build test` exit 0에 `audio_test`
   줄 넷, `init` 3,776,512바이트. regression 일곱이 전부 exit 0 — `power` 54초 · `service` 68초 · `tools` 60초(`all 92 tools`) · `config`
   158초 · `terminal` 24초 · `boot` 23초 · `install` 103초(`init waited 1900ms`). mutation 열한 판 + 호스트 검사 두 판이 확정 7의 표와
   같은 자리에서 빨갰다(`m4_store`의 첫 판만 아래 2).
2. 기대와 다른 것 하나 — 검사 5의 간헐 실패. 첫 `audio` 체인 판과 `m4_store` 첫 판에서 `other`가 16 · 19이고 `tone`이 47,446 · 47,898로
   빨갰고, 재실행은 초록이었다. lead가 재현했다 — 부하 없이 열다섯 판은 전부 `other=0`, 컨테이너에 CPU 부하 여섯(`perl -e '1 while 1'`)을
   걸면 다섯 판 중 둘이 `other=17`. 남긴 `tap.raw`(`/tmp/run/au1/impl/flaky/load2` · `load3`)의 그 프레임은 찢어진 것이 아니라 정확히
   두 배(±16000) 49프레임이 한 덩어리로 있고 그 뒤가 0이었다 — dmix가 xrun 구간을 하드웨어 버퍼에 두 번 더한 것이다. 호스트 부하로
   TCG 게스트의 하드웨어 포인터가 밀린 것이고, 우리 코드도 볼륨도 아니다(볼륨이 틀리면 값이 ±800이 되어 `tone`이 0이다).
   lead가 `audio/check.sh`를 고쳤다(이 plan의 글자 밖, +17 −5) — `count_tap`에 `doubled` 갈래를 더해 세기만 하고 판정에 안 쓰고, 사각파
   하한을 47,000에서 40,000으로 내렸다(부하 아래 최소가 47,425였다. 하한의 일은 음소거 · 틀린 볼륨을 잡는 것이고 둘 다 `tone`이 0이다).
   고친 뒤 부하 아래 다섯 판이 초록(`tone` 47,789~47,935 · `doubled` 0)이었고, 프로브의 `amixer … 0dB`를 뺀 판(mutation 5의 모양)은
   `tone=0 · other=48000`으로 여전히 빨갰다. design 실측 17 · 위험 7.
3. 루트 게이트. 스무 체인 × 2회, 50분 54초, `PASS: 2/2` 스물 · `AU check PASS` 둘 · `skipping make` 39. `audio`의 두 회차 — 부팅 A
   `tone` 47,943 · 48,000(`other` · `doubled` 0), `cap` 96,000/96,000, 끄는 데 `asked 9.22s → powered down 9.42s` · `9.19 → 9.39`, 부팅 B
   `tone` 48,000 둘. 1회차의 47,943은 부하가 없는 게이트에서도 xrun이 프레임을 떨어뜨린다는 뜻이다 — 하한을 내린 이유가 거기서도 보였다.
   M0의 50분 34초에 20초가 더해졌다(확정 6이 본 25초 안팎).
4. `check.sh`의 `CHAINS` 표식을 `AU-M0`에서 `AU-M1`로 바꿨다(게이트 뒤, 글자뿐).
