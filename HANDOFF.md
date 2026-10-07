# HANDOFF: 사용자의 요청 둘이 다 닫혔다 — Audio Devices(AU-M0~M3)와 Voice Dictation(VD-M0~M2)

## 지금 어디인가

2026-10-05 사용자의 요청 둘("1. 오디오(마이크/이어폰/스피커) 기기 활성화. 2. 마이크로 음성 전사 (Voxio 포팅).
/Users/dp/Repository/Voxio" — "별도 도메인이니 순차", "계획 수립과 구현 방법 그리고 구현 작업에 목적에 맞는 모델을 사용하는 서브
에이전트를 할당")을 AU와 VD로 열어 2026-10-06에 둘 다 닫았다. AU의 표는 아래 "그 앞" 절에 있다. VD의 commit은 이렇다.

| 커밋 | 무엇 |
|---|---|
| `1bc451c` | VD design · M0 plan · HANDOFF의 AU commit 해시 |
| `11039e6` | M0 — 게스트 bash `tars-dictate`(`arecord` 16kHz 모노 → `curl` multipart → `jq`, WAV 머리 다시 쓰기, 시그널은 그룹, 종료 코드 여덟) · `/config/dictation.conf` · `groq.key` · `dictation.jsonl` · initrd의 CA 목록 150장 · 스물한번째 체인 `dictation/check.sh`(perl stub, `openssl s_server` 45492). 구현 Sonnet. 루트 게이트 21체인 2/2, 53분 28초 |
| `be9352c` | M1 — terminal의 `dictation.zig`(`DoubleTap` · `Phase` 넷 · `outcome` · `isPassword` · `sanitize`) · `input.zig`의 트리거(0번 단계)와 Esc(1.3번) · `main.zig`의 자식(fork · poll 두 칸 · `waitpid` · `pasteParts`) · 상태 줄 낱말 일곱(`MAX_LEN` 56) · 체인 부팅 B(monitor 45493, `sendkey meta_r 80`) 검사 14 ~ 23. 구현 Sonnet. 21체인 2/2, 54분 48초 |
| `cbde2be` | M2 — `tars-dictate`의 정리 단계(Voxio 프롬프트 그대로 · 길이 가드 · 실패 · 시간 초과면 원문 · `cleanup` · `cleanup_url` · `cleanup_model` · `cleanup_timeout`) · SIGINT 틈 닫기 · stub `/chat/<답>/<갈래>` · 게스트 `/etc/hosts`로 Groq 막기 · 검사 24 ~ 29. 구현 Sonnet. 루트 게이트는 M2 plan 실측 절 |
| `e914deb` | design `Status:` · CLAUDE.md 표 · `project_voice_dictation.md` · MEMORY.md · lessons(포트 · 로그 문구 · VD 실측 아홉 · 핵심 파일) · running-tars 받아쓰기 절 · HANDOFF |

design은 `docs/specs/2026-10-06-tars-voice-dictation-design.md`(결정 12 · 전제 정정 9 · 위험 9 · 비목표 14 · 실측 14, Voxio D1 ~ D16
대응표), plan은 `-vd-m0.md` ~ `-vd-m2.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은 `docs/decisions/project_voice_dictation.md`.
실기 안내는 `docs/guides/running-tars.md`의 받아쓰기 절(키 파일 · 키 여덟 · 상태 줄 낱말 일곱 · 종료 코드 · 기록 읽기 · 안 될 때 ·
무료 티어).

방식은 AU와 같다 — planner(Opus) 셋이 저장소 밖 사본(`/tmp/run/vd0` ~ `vd2`)에서 코드를 돌리고 `old_string` · `new_string`을 기계로
뽑았고, 구현자(Sonnet) 셋이 글자 그대로 넣었다. 세 milestone 모두 plan 코드를 고친 곳이 없었다. planner들이 lead의 전제를 아홉
바로잡았다 — CA 목록 없음 · 설정은 `tars.conf`가 아니라 `dictation.conf` · 기록은 M0부터 · SIGINT가 WAV 머리를 못 고침 · 시그널은
그룹 · M0는 monitor 없음 · `arecord` 16kHz는 됨 · jq 1.7에 `trim` 없음 · M0 체인은 화면을 안 봄, 그리고 M1이 `ECHO` → `ICANON && !ECHO`,
M2가 부팅 B 전체를 정리 켠 채로 · Groq 막기.

알릴 것 하나 — M2 planner가 호스트에서 `tars-dictate`를 한 번 돌려 호스트 셸의 진짜 `GROQ_API_KEY`가 127.0.0.1의 stub 로그에
찍혔다. 바깥에 안 나갔고 지웠으며 `/tmp/run/vd2` 전체에 키 모양이 0개인 것을 다시 확인했다. plan에 "호스트에서 `tars-dictate`를
돌리지 말 것"을 적었다. 키를 바꿀지는 사용자의 판단이다.

## 2026-10-07 — Config Tool(TC-M0 ~ M3) 닫혔다. 후속 하나를 열었다 — 로그 줄을 write 한 번에(std.debug.print의 64바이트 버퍼)

### Atomic Log Lines(AL) 진행 중 — M0 구현 중, M1 plan 작성 중

design `docs/specs/2026-10-07-tars-atomic-log-lines-design.md`(`22061fc`, 결정 7 · 전제 정정 3 · 실측 F), M0 plan `-al-m0.md`(`037744a`).
`logline.zig` 사본 둘(init/src · terminal/src, 진입 검사가 cmp로 지킨다), 줄은 2048바이트까지 write 한 번(넘치면 UTF-8 경계에서 자르고 ` [cut]`),
화면 dump는 격자 크기 버퍼에 조립, 게스트 파일의 `std.debug.print` 전부 치환(terminal 98 · init 153), 루트 `check.sh`의 `run_chain`이 회차마다
`TMPDIR=<GATE_LOGS>/<체인>-<회차>`를 주고 끝나면 끼어든 줄을 센다(A = `terminal:` 줄 안의 `tars-init:` — M0부터 FAIL, B = 반대 — M1부터
FAIL). 지금 값은 회차당 A+B 2 ~ 8이다. 로그를 지우던 8체인 14자리가 로그를 남긴다. M0 = terminal, M1 = init. 사본 `/tmp/run/al0`(측정 ·
mutation · 도구), M1은 `/tmp/run/al1`. 구현자 Sonnet(`tc-m0-impl`) · planner Opus(`tc-design`)가 TC에서 이어서 한다.


사용자의 요청("tars-config 실행 파일을 만들어서 시스템 전체 세팅을 할 수 있게 … 쉘 스크립트가 아니라면 어떤 언어로")에서 열었다.
design `docs/specs/2026-10-06-tars-config-tool-design.md`(결정 11 + 덧붙임, 전제 정정 7+), plan `-tc-m0.md`. 사용자 결정 셋 — seed의 별칭
`tars-config` · `tars-rc`는 지운다(cat과 다를 게 없다), 언어는 Zig(`config.zig` 재사용), M1 · M2까지 끝까지 간다("진정한 user experience 개선").

| 커밋 | 무엇 |
|---|---|
| `6968026` | TC design · M0 plan(Opus planner `tc-design`, 사본 `/tmp/run/tc0`) |
| `5d58520` · `0758b4a` | M1 plan · design 결정 12 ~ 17(앞문 넷 · 남의 문법은 주인이 짓는다 · 가르는 것은 방화벽 하나 · 방화벽만 그 자리에서 `nft -f`) |
| `e493bfd` | M1 — `init/src/config_front.zig` · `config_front_edit.zig` · `config_front_edit_test.zig`, 동사 `wifi` · `ssh on|off` · `ssh-key add|list` · `firewall allow|deny` · `dictation key|set`, `check`에 다섯 더. 새 체인 없이 wifi · service · firewall · dictation 체인에 검사 하나씩. 구현 Sonnet, plan 코드 고친 곳 0. 루트 게이트 21체인 2/2 두 번(56:36 · 56:42) |
| `3f8598d` · `9455d44` | M3 plan · 구현 — `tars-config reload terminal`(argv 칸 일곱을 바꾸고 pid로 SIGTERM, 대기가 없으면 아무것도 안 함), 드러난 잠재 버그 `kill(-pid)`(terminal은 그룹이 없다) 수정, 콘솔 셸 `exit` 게이트. 5b: `gate_lib.sh`의 `joined_screen_dump`가 `tars-init: ` 조각도 잇고 루트 `check.sh`에 진입 검사 `require_screen_dump_joins`. 5c: 프로브가 연달아 찍는 줄은 줄마다 기다린다(wifi 12 · config 1차). 루트 게이트 네 번, 완주 통과 둘(59:20 · 59:17), 빨감 셋은 전부 게이트 쪽 간헐 |
| `2f69ce2` | TC 닫기 — running-tars "설정 — tars-config" 절(동사 열두 줄)과 손 명령 자리 일곱, 기억 `project_config_tool.md` · `project_config_reload.md`, lessons(핵심 파일 · TC 실측 열 · 이월 숙제 둘 · 게이트 교훈 둘), CLAUDE.md 표 |
| `2f14550` + `eed8556` | M2 plan · 구현 — `init/src/reload.zig` · `reload_test.zig`, `main.zig`의 `Live` · 칸 열셋 · `config_off` · `doReload`, `control.zig` 동사 둘(`config` · `reload`), `firewall.down`, `tars-config reload`와 두 칸 보기, `services.d` 다시 읽기. 체인 넷에 검사 하나씩. 루트 게이트 처음 둘이 net 검사 31에서 간헐로 빨개(단독은 초록) Task 5b(set의 답을 본 뒤 reload · 진단)가 생겼고, 그 뒤 21체인 2/2 두 번(58:19 · 58:24) |
| `76ef474` · `5621281` | M2 reload design(결정 11 — `init.sock`에 `config` · `reload`, 키를 넷으로 가른다, 원자성 · 순서, 감독 루프를 안 막는다, `services.d` 다시 읽기) |
| `8671f56` | M0 — `init/src/config_cli.zig`(root · 시스템 콜) · `config_edit.zig`(순수) · `config_edit_test.zig`(호스트), `config.zig`의 로그 24줄 → `log()`(root의 `configLog`가 가로챈다), seed 별칭 둘 제거, config 체인 1차에 동사 다섯 + `list`, 2차의 `echo`가 `set`으로. 구현 Sonnet `tc-m0-impl`, plan 코드 고친 곳 0. 루트 게이트 21체인 2/2 두 번(56:01 · 55:52) |

동사는 여섯 — 인자 없음(보기) · `get` · `set` · `reset` · `check` · `list`(+ `help`). `unset`은 안 받고 `reset`을 가리킨다(design 결정 1 덧붙임).
`set`은 이기는 줄 하나만 바꾸고 재부팅(`kill -INT 1`)이 필요하다고 매번 말한다.

알릴 것 — 쓰던 설정 디스크(`out/tars-config.img` · 실기 p2)의 rc에는 `alias tars-config='cat …'`가 남아 있어 그 셸에서 실행 파일이 가려진다.
처방은 design 결정 6의 세 줄(`sd 'alias tars-(config|rc)=.*' '' /config/fish.config /config/bashrc /config/zshrc` 또는 `command tars-config`).

다음(열어 둔 후속): 로그 줄을 write 한 번에. Zig 0.16 `std.debug.print`의 내부 버퍼가 64바이트라 그보다 긴 줄은 write 둘 이상으로 나가고,
그 사이에 다른 프로세스의 write가 끼어든다 — terminal의 화면 dump · `pointer>` 줄(65바이트 자리에서 잘렸다)과 init의 `tars-init: audio: no sound
card within 5000ms`가 하룻밤에 게이트를 두 번 빨갛게 했다(M3 실측 2). M3 5b의 joiner는 `screen>`만 잇는다. 고칠 자리는 terminal(`std.debug.print`
90곳, 화면 dump는 칸마다 print) · init(55곳 + 모듈들)의 로그 줄을 한 버퍼에 지어 write 한 번으로 내는 helper다. planner(`tc-design`)에게 design을
맡겼다 — 이름 · 범위 · 게이트(모든 게스트 로그에서 `terminal: ` 줄 안의 `tars-init:` 0개를 세는 검사)는 그 design이 정한다.

실기에서 칠 것(TC): 쓰던 디스크의 rc에 `alias tars-config`가 남아 있다(처방은 running-tars "seed는 한 번만 깔린다" 절). `tars-config wifi …` ·
`tars-config dictation key`의 tty 길(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp` · `tars-config reload`, `tars-config reload terminal`.
게이트가 못 보는 넷 — tty 질문 · `--country` · `firewall deny` · `firewall=off`의 말. (M1 때의 메모: planner가 M1 plan — 표면 넷의 앞문(`wifi` · `ssh-key add` · `firewall allow` · `dictation
key/set`), 원칙은 결정 10(남의 문법을 다시 짓지 않는다). 그 뒤 Sonnet 구현 → 루트 게이트 2회 → commit. M2(`reload`)는 따로 design을 쓴다.
서브프로젝트를 닫을 때 lead가 할 것은 design "닫을 때" 절(CLAUDE.md 표 · `project_config_tool.md` · lessons · running-tars의 `tars-config` 절 ·
"네트워크와 시계" 절의 `sd` 세 줄을 `tars-config set`으로).

lead의 실수 하나 — 루트 게이트를 커널 컴파일 중에 멈춰 `kernel/build`가 깨졌었다(vd2 사본의 빌드로 복구). 게이트를 멈출 때는 `kernel: ` 줄이
지나갔는지 먼저 본다.

## 2026-10-06 저녁 — net · ntp 기본값은 그대로, 켜는 법을 문서로

사용자가 QEMU에서 VD를 보려다 `tars.conf`의 `net=off` · `ntp=off`를 보고 "기본 seed 값에 활성화하자"고 했고, `config.zig` 기본값
둘을 `dhcp`로 바꿔 config · tools · service 체인이 초록인 채 루트 게이트를 돌리던 중 "비활성화 상태로 두고 활성화하는 방법을 담은
문서를 남기자"로 바꿨다. 코드는 전부 되돌렸고(작업 트리에 코드 변경 0줄) 남은 것은 `docs/guides/running-tars.md`의 새 절
"네트워크와 시계 — 기본은 꺼져 있다"(왜 꺼져 있나 · 세 줄 켜기 · QEMU의 SLIRP는 NTP 서버를 안 알려 준다 · 켜졌는지 보는 법)와
기억 `docs/decisions/feedback_network_default_stays_off.md`다. 그 앞에 "게스트 curl에 CA 목록이 없다"는 보고를 확인했다 — VD-M0
이전 상태이고 오늘 18:48의 ISO · initrd에는 150장이 있다(호스트 curl이 그 번들만으로 Groq 체인을 검증했다).

## 바로 다음에 할 것 — 실기에서 둘을 본다, 그리고 다음 서브프로젝트

사용자가 실기 노트북에서 볼 것이 둘이다. 둘 다 `running-tars.md`에 명령이 있다.

- 소리(AU) — `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test` · `arecord → aplay`, 헤드폰 잭 · USB 헤드셋, SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- 받아쓰기(VD) — `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 진짜 Groq · 첫 연결 지연(정리가 매번 `cleanup timed out`이면
  `cleanup_timeout`을 늘리거나 끈다) · SOF DMIC의 앞부분이 0인지(design 위험 1).

다음 서브프로젝트 후보 — AU 비목표 10(SoundWire 코덱 노트북 · side-codec 스피커 앰프, 실기가 요구하면), VD 비목표(상주 프로세스로 연결
재사용 — 첫 연결 지연이 크면, 알림음, hold 모드), 그리고 앞 절의 것들(ZU-M2 · 패키지 매니저 · IPv6 · USB 동글 층 B · WP-M3 방향 포커스 ·
vim-runtime · 더블클릭 단어 선택 · 휠 방향 · 포인터 가속 · CB `workspace` 범위). 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"(AU 다섯 ·
PD 넷 · …).

측정 파일(저장소 밖, 지워도 된다): `/tmp/run/au0` ~ `au3` · `/tmp/run/vd0` ~ `vd2`(planner · 구현자 사본과 로그) · `/tmp/gate_au0.log` ~
`gate_au3.log` · `/tmp/gate_vd0.log` ~ `gate_vd2.log`(루트 게이트). 이미지 `tars-devcontainer-au0` · `-vd0`는 지워도 된다.

### 그 앞 — Audio Devices(AU)가 M0~M3으로 닫혔다


2026-10-05 사용자의 요청 둘("1. 오디오(마이크/이어폰/스피커) 기기 활성화. 2. 마이크로 음성 전사 (Voxio 포팅).
/Users/dp/Repository/Voxio")을 받았다. "별도 도메인이니 개발 과정은 병렬로 진행하지 말고 순차 진행", "계획 수립과 구현 방법 그리고
구현 작업에 목적에 맞는 모델을 사용하는 서브 에이전트를 할당"이 지시다. 1번을 AU로 열어 2026-10-06에 닫았고, 2번 VD는 아직 안 열었다.

| 커밋 | 무엇 |
|---|---|
| `6e179c1` | AU design · M0 plan · 기억 `feedback_scripting_runtimes`(컨테이너에 런타임을 들일 때는 python3 · lua · nodejs(bun) · ruby 한 묶음으로 — 지금은 perl) |
| `c855ae3` | M0 — 커널 `SOUND` · `SND` · `SND_HDA_INTEL` · `SND_HDA_GENERIC` · `SYSVIPC`, 게스트 alsa-utils 넷 + `arecord` 링크 · libasound · `/usr/share/alsa` · 목소리 둘 · `/etc/group`의 `audio`, 스무번째 체인 `audio/check.sh`(QEMU `alsa` 백엔드 + 컨테이너 alsa-lib `file` 플러그인으로 샘플을 값까지). 우리 코드 0줄. 구현 Sonnet. 루트 게이트 20체인 2/2, 50분 34초 |
| `9eee60f` | M1 — `init/src/audio.zig`(일꾼 fork · `alsactl -U restore|init` · 99는 성공 · 끄는 길의 `store` · `/config/asound.state`) · `alsactl` 싣기 · 체인 부팅 셋 검사 열하나. 간헐 실패 하나를 lead가 추적 — dmix xrun의 두 배 프레임(`doubled` 갈래 · 하한 40,000). 구현 Sonnet. 20체인 2/2, 50분 54초 |
| `cd9c12e` | M2 — 커널 HDA 코덱 여덟(Realtek 계열 전부 · Conexant · Senarytech · Cirrus · CS8409 · Analog · IDT · VIA) · `SND_USB_AUDIO` · `HID_APPLE` · `INPUT_LEDS` 끔, `audio.follow`(1초마다 `/dev/snd` → `/etc/asound.conf`, 재생 · 녹음 각각 가장 큰 번호), 체인 부팅 D(monitor 45491, `usb-audio` 꽂고 뽑기) 검사 열다섯. 첫 루트 게이트가 `pointer`에서 빨갰다 — 커널 printk가 화면 줄을 자른 것, `gate_lib.sh`의 `joined_screen_dump`. 구현 Sonnet. 20체인 2/2, 51분 10초 |
| `257b5e1` | M3 — 커널 Intel SOF 열한 세대 · AMD ACP PDM 셋 + 범용, sof-bin v2026.09.1 firmware · topology 42개(`vendor_firmware.sh`가 받는다, firmware 목록 77 → 119), 녹음의 세 단(USB 마이크 · 내장 DMIC(`/proc/asound/pcm`) · 장치 0), postinit 규칙 한 줄(`Dmic0 Capture Switch`), 검사 열일곱. 구현 Sonnet. 루트 게이트는 M3 plan의 실측 절 |
| `52188ab` | design `Status:` · CLAUDE.md 표 · `project_audio_devices.md` · MEMORY.md · target_hardware · lessons(포트 · 로그 문구 · AU 실측 일곱 · 이월 숙제 다섯 · 핵심 파일) · running-tars 소리 절 · HANDOFF |

design은 `docs/specs/2026-10-05-tars-audio-devices-design.md`(결정 8 · 전제 정정 12 · 위험 16 · 비목표 10 · 실측 19), plan은
`-au-m0.md` ~ `-au-m3.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은 `docs/decisions/project_audio_devices.md`.

방식은 PD · EL · CB와 같다 — planner(Opus)가 저장소 밖 사본(`/tmp/run/au0` ~ `au3`)에서 컴파일 · 체인 · mutation까지 돌리고
`old_string` · `new_string`을 기계로 뽑아 넘기고, 구현자(Sonnet 넷)가 글자 그대로 넣었다. 네 milestone 모두 plan 코드를 고친 곳이 없고
보고와 파일이 어긋난 자리도 없었다. 다음 milestone의 plan은 앞 milestone의 루트 게이트가 도는 동안 docker 금지(lock) 조건으로 미리
썼다. planner들이 lead의 전제를 열둘 바로잡았다(design "lead의 전제를 바로잡은 것") — 게스트 안 루프백 불필요 · `wav` 백엔드는 녹음
없음 · `SYSVIPC` · `audio` 그룹 · milestone 넷 · 포트 · 일꾼은 기다리지 않는다 · USB 카드는 켜진 채 온다 · firmware는 sof-bin ·
AMD는 PDM · UCM 안 싣는다 · SoundWire 제외. 게이트가 빨개진 둘(dmix xrun · printk 자름)은 lead가 재현해 원인을 잡았고 둘 다
우리 코드가 아니었다(lessons).

#### (AU를 닫을 때의) 바로 다음에 할 것 — VD

사용자의 요청 2번. Voxio(`/Users/dp/Repository/Voxio`, Swift, macOS 메뉴바 앱 1.0.1)는 "오른쪽 ⌘ 두 번 → 마이크 → Groq Whisper API로
전사 → LLM으로 군더더기 정리 → 커서 자리에 붙여넣기"다. 기록은 로컬 SQLite에 남고 원본 오디오는 안 남긴다. 읽을 것은 `README.md` ·
`docs/ARCHITECTURE.md`(결정 D1~D16 · 파이프라인 3절 · Groq 무료 티어 7절) · `Sources/VoxioCore/`(플랫폼 독립 코어 —
`DictationPipeline.swift` · `GroqClient.swift` · `TranscriptText.swift` · `DoubleTapDetector.swift` · `AudioPolicy.swift`).

lead(Fable)가 AU를 열 때 재 둔 것 —
- 게스트에 TLS가 붙은 `curl`과 `jq` · `bash`가 이미 있다(`kernel/guest_tools.sh`). Groq 호출은 `curl`로 그대로 옮길 수 있다.
- 게이트는 바깥에 못 나간다 — `net/check.sh`의 `guestfwd=tcp:10.0.2.100:8080-cmd:…` 방식으로 Groq 흉내 서버를 세운다. 컨테이너에
  python3이 없고 perl이 있다(`feedback_scripting_runtimes`). 전사 API의 주소는 `tars.conf` 키(예: `dictation_url=`)로 바꿀 수 있어야
  게이트가 stub을 가리킨다.
- 삽입은 terminal이 PTY를 쥐고 있으므로 `Cmd+V` 붙여넣기 경로(`dumpPaste` · `pasteParts`, bracketed paste)와 같은 자리다. 트리거는
  terminal이 evdev를 직접 읽으니 오른쪽 Cmd 두 번(`KEY_RIGHTMETA`)을 `input.zig`에서 잡을 수 있다 — `capslock_tap` · `lctrl_tap`의
  탭 판정이 선례다. 녹음 중 표시는 상태 줄(`status.zig`, `COPY`와 같은 자리)이다.
- 녹음은 AU가 세운 `arecord`다. `arecord -f S16_LE -r 16000 -c 1`(Whisper가 받는 모양)이 기본 장치(`plug` → `dsnoop`)로 도는지는
  안 쟀다 — VD의 첫 실측. 게이트의 마이크는 `audio/check.sh`의 `file` 플러그인 `infile`로 넣는다(값까지 안다).
- API 키는 `/config`에 파일 하나(Voxio의 Keychain 자리). 기록은 `/config`에 텍스트로(Voxio D9 — 오디오는 안 남긴다).
- 틀(바꿔도 된다) — terminal이 트리거 · 상태 · 삽입을 쥐고, 게스트 쪽 스크립트 하나(`tars-dictate`: `arecord` → `curl` 전사 → `curl` 정리
  → stdout)를 terminal이 fork해 stdout을 읽고 EOF에 붙여넣는다. 두 번째 트리거는 시그널로 녹음을 끝내고, Esc는 취소. 우리 코드는
  파이프라인의 상태 기계와 삽입이고 HTTP · 오디오는 남의 것(`project_write_or_reuse`).

AU가 VD에 넘긴 경계 — AU는 "`arecord`가 마이크의 바이트를 WAV로 쓰고 `aplay`가 WAV를 스피커로 낸다"까지(design 비목표 4).

### AU가 남긴 것

- 비목표 10 — SoundWire 코덱 노트북(`sof_sdw`)과 side-codec 스피커 앰프(CS35L41 · CS35L56 · TAS2781). 실기가 요구하면 새
  서브프로젝트. 크기는 design 비목표 10에.
- lessons 이월 숙제 다섯 — 늦은 내장 카드(위험 14) · firmware의 RAM(위험 16) · 사각파 하한 · 화면 줄을 직접 읽는 자리 67곳 · 실기에서
  볼 것.
- 실기에서 볼 것은 `running-tars.md`의 소리 절.

측정 파일(저장소 밖, 지워도 된다): `/tmp/run/au0` ~ `au3`(planner · 구현자 사본과 로그, `au1/impl/flaky`에 dmix xrun의 tap) ·
`/tmp/gate_au0.log` ~ `gate_au3.log`(루트 게이트 — `gate_au2.log`는 빨간 첫 판). 이미지 `tars-devcontainer-au0`는 지워도 된다.

### 그 앞 — Escape Latin(EL)과 Clipboard Scope(CB)가 같은 날 닫혔다


2026-10-05 사용자의 요청 둘("터미널 패널이나 워크스페이스 사이 clipboard를 공유해서 사용하는 옵션; 기본적으로 전체
공유 활성화" · "esc키 누르면 한글 자판인 경우 영문자판으로 전환; vim 사용할 때 큰 도움이 됨")을 서브프로젝트 둘로 열어
같은 날 닫았다. 사용자는 "별도 도메인"이라 했고 "안전하게 순차 진행해도 좋다"고 정했다. 지시는 PD와 같다 — "계획
수립과 구현 방법 그리고 구현 작업에 목적에 맞는 모델을 사용하는 서브 에이전트를 할당".

| 커밋 | 무엇 |
|---|---|
| `dfd761a` | EL-M0 — `hangulLayer`의 Esc 갈래(확정 · 끄기 · null) · `readKeys`의 `hangul_on` 앞뒤 비교 · `tars.conf`의 `esc_latin=on\|off`(따로 있는 키, argv는 전환 키 목록 끝에 이름을 붙여) · hangul 검사 21~24(24는 실제 vim). 구현 Sonnet. 루트 게이트 19체인 2/2, 50분 58초 |
| `a541411` | EL 닫기 — design Status · CLAUDE.md 표 · `project_escape_latin.md` · HI design 결정 7 덧붙임 · lessons · running-tars의 한/영 절 |
| `1db4602` | CB-M0 — 순수 `clipboard.zig`(`Scope` · `Clipboard` · `pick`) · `vt.Screen`의 `clip`과 `clipboard()`를 지우고 `copyYank(clip)` · `findPaste(text)` · `main.zig`의 `Clips`(`of` · `yank` · `paste`) · `tars.conf`의 `clipboard=shared\|pane` · argv 아홉째 칸(`[8:null]` → `[9:null]` 여섯 자리) · pane 검사 10~15와 부팅 B(45490). 덤으로 EL의 `esc_latin=on$` 판정을 `( \|$)`로. 구현 Opus. 루트 게이트 19체인 2/2, 51분 15초 |
| (이 커밋) | CB 닫기 — design Status · CLAUDE.md 표 · `project_clipboard_scope.md` · MEMORY.md · CM 결정 1과 WP 비목표 덧붙임 · 기억 둘 · running-tars의 클립보드 절 · lessons(포트 45490 · 로그 문구 · 줄 끝 앵커 · `clipboard.zig`) · HANDOFF |

design은 `docs/specs/2026-10-05-tars-escape-latin-design.md`(결정 4 · 위험 4 · 비목표 6 · 실측 8)와
`-clipboard-scope-design.md`(결정 6 · 위험 5 · 비목표 7 · 실측 10), plan은 `-el-m0.md` · `-cb-m0.md`이고 각 끝의 "실측한 것"
절이 값이다. 기억은 `docs/decisions/project_escape_latin.md` · `project_clipboard_scope.md`.

planner 둘이 lead의 전제를 하나씩 바로잡았다. EL — `hangul_toggle` 목록의 다섯째 이름이 아니라 따로 있는 키여야 한다
(seed가 목록 넷을 글자 그대로 적어 두어 옛 설정 파일에서 꺼진 채로 뜬다). CB — 사용자의 "워크스페이스마다 독립"은 실제로
패널마다였고, 그래서 옛 동작의 이름이 `pane`이다. 그리고 CB 구현자가 regression에서 EL의 판정 하나(`esc_latin=on$`,
줄 끝 고정)가 다음 키에 깨지는 것을 잡았다 — lessons "로그 문구는 두 곳에 중복된다"에 적었다.

방식은 PD-M4와 같되 서브에이전트 둘이 같은 시간에 돌았다. planner 둘(Opus)이 저장소 밖 사본(`/tmp/run/el0` · `/tmp/run/cb0`)
에서 컴파일 · 체인 · mutation까지 돌리고 `old_string` · `new_string`을 기계로 뽑았고, 컨테이너는 `/tmp/run/docker.lock`
(mkdir로 잡고 rmdir로 푼다)으로 하나씩만 썼다 — `Killed`는 한 번도 안 났다. 구현은 사용자의 결정으로 순차(EL → 루트 게이트
→ commit → CB 앵커 재추출 → CB → 루트 게이트 → commit)였다. 두 구현자 모두 Edit 대신 plan 본문에서 블록을 기계로 뽑아
넣었고(`/tmp/run/*/impl/apply.py`), 파일은 planner의 사본과 바이트까지 같았다.

#### (EL · CB를 닫을 때의) 바로 다음에 할 것

후보는 아래 PD 절의 것들(더블클릭 단어 선택 · `tars.conf`의 휠 방향 · 포인터 가속 · ZU-M2 · 패키지 매니저 · IPv6 · USB 동글
층 B · WP-M3 방향 포커스 · vim-runtime)에 이번에 열어 둔 둘이 더해진다.

- CB 범위 `workspace`(같은 워크스페이스 안에서만 나눈다, design 비목표 1). 사용자가 "워크스페이스가 독립"이라 한 것이 그
  동작을 원한 것이면 `Workspace`의 칸 · 닫을 때 해제 · `pick`의 셋째 갈래 셋을 더한다.
- EL 비목표 — Shift+Esc와 `Ctrl+[`, 반대 방향(insert로 돌아갈 때 한글 되살리기), 패널마다 한/영.

작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다. EL이 하나 더했다 — seed `tars.conf`의 `ntp:` 주석이 TD 전의
설명으로 남아 있다(고치면 seed의 글자가 바뀌어 `config` 체인을 함께 본다). seed는 이제 48줄이라 게스트 화면 47줄을 넘는다 —
다음에 키를 더하는 사람은 `config` 체인 1차의 `| shell_config=on`(25번째 줄) 검사를 함께 본다.

측정 파일(저장소 밖, 지워도 된다): `/tmp/run/el0` · `/tmp/run/cb0`(planner · 구현자 사본과 로그) · `/tmp/gate_el0.log` ·
`/tmp/gate_cb0.log`(루트 게이트 로그).

### 그 앞 — Pointer Devices(PD)가 M0~M4로 닫혔다


2026-10-05 사용자의 요청("마우스 장치 지원: 마우스 포인터 및 인터렉션(드래그 선택). 터치패드 역시 지원")으로 열어 같은 날
닫았다. 사용자는 결정권을 lead(Fable)에게 위임하고 자리를 비웠다. design은
`docs/specs/2026-10-05-tars-pointer-devices-design.md`(결정 11 · 위험 8 · 비목표 13 · 실측 15, `Status: 끝났다`), plan은
`-pd-m0.md` ~ `-pd-m3.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은 `docs/decisions/project_pointer_devices.md`.

사용자의 지시("계획 수립과 구현 방법 그리고 구현 작업에 목적에 맞는 모델을 사용하는 서브 에이전트를 할당")로 design과
plan 넷은 Opus 서브에이전트가, 구현은 M0 · M2 · M3을 Opus, M1(정해진 모양을 옮긴다)을 Sonnet 서브에이전트가 했다. Fable은
착수 전 실측 · 대조 · 루트 게이트 · commit · 결정을 맡았다. planner들이 plan 코드를 저장소 밖 사본에서 컴파일 · 체인 ·
mutation까지 돌린 뒤 `old_string` · `new_string`을 기계로 뽑아 넘기고(`anchors.py`), 구현자는 그것을 글자 그대로 넣었다 —
네 milestone 모두 plan 코드를 고친 곳이 없고 보고와 파일이 어긋난 자리도 없었다. 다음 milestone의 plan은 앞 milestone의
루트 게이트가 도는 동안 docker 금지 조건으로 미리 썼다.

| 커밋 | 무엇 |
|---|---|
| `0c2e6f5` | design |
| `8f8a030` | M0 — `pointer.zig`(`classify` · `Mouse` · `Pointer` · `ueventAddedNode`) · netlink uevent 핫플러그 · 장치 칸 여덟 · poll `pty_base` · `pointer>` 줄 · 열아홉번째 체인 `pointer/check.sh`(45488). 커널은 안 바뀌었다. 루트 게이트 19체인 3/3, 1시간 8분 39초 |
| `3b57b66` · `6f4dfb2` | 사용자의 결정 — 루트 게이트 반복 3 → 2(`feedback_gate_runs`), `check.sh`의 `RUNS=2` |
| `8dcf6f1` | M1 — 화살표(save-under, `ink` 118) · 보이는 조건 셋 · 휠 세 줄 · `layout.Tree.hit`. 구현 Sonnet. 19체인 3/3(마지막 3회), 1시간 8분 41초 |
| `e937b92` · `1ecb973` | M2 — `Gesture` · `copyEnterAt` · `copyPointTo` · `pointerMode` · 클릭 포커스 · 드래그 = copy mode · 뗌 = `copyYank` · clamp · 누른 채 휠(사용자 요청 1 끝). 19체인 2/2, 47분 46초. 그리고 `kernel/.config` 되접기(UW의 USB 무선 select 여덟) |
| `38bb649` | M3 — `touchpad.zig`(MT B · 탭 · 두 손가락 휠 · 물리 버튼) · 커널 심볼 41개(PS/2 · SMBus · I2C-HID · THC QuickI2C · uinput, +323,584바이트) · `pointer/replay/tp-replay`(uinput 가짜 패드) · 부팅 B(45489) 검사 19~25 · `install` 부팅 7 `delay_use=4`. 19체인 2/2, 49분 29초 |
| (이 커밋) | design Status · CLAUDE.md 표 · 기억 · MEMORY.md · HD/WP/CM/IP/TF 비목표에 한 줄 · running-tars.md · lessons(PD-1~7 · 이월 숙제 · 핵심 파일 · 포트) |

PD가 남긴 가장 큰 사실은 커널이 아니라 게이트의 것이다. M0에서 `CONFIG_INOTIFY_USER=y`를 켰더니 `FSNOTIFY`가 따라 켜진
커널이 TCG에서 initramfs 풀기를 1.2초 늦춰 `install` 체인 부팅 7의 창(`usb-storage.delay_use=3`)을 닫았고 루트 게이트가 두 번
빨갰다 — inotify를 버리고 netlink uevent로 갔다. M3이 커널 심볼 41개를 켜며 같은 증상을 다시 겪고 진짜 원인을 찾았다:
드라이버가 아니라 코드 배치다(gzip `inflate_fast`가 페이지 경계를 넘으면 QEMU TCG가 번역 블록을 직접 잇지 못한다, `X86_INTEL_LPSS`
하나로 재현). 실기와 무관한 게이트 비용이고, 부팅 7의 `delay_use`를 4로 올려 여유를 900ms로 되돌렸다(lessons PD-3 · 이월 숙제).

열지 않은 것(design 비목표 13): 마우스 보고(SGR 1006 — 다음 서브프로젝트의 첫 후보, vim `mouse=a` · fzf · lazygit) · 더블클릭 ·
가장자리 자동 스크롤 · 절대 좌표 장치 · 뗀 뒤 반전 남기기 · 가속과 터치패드의 나머지 · `tars.conf` 항목(휠 방향 먼저) · 왼손잡이 ·
키보드 핫플러그 · Apple 트랙패드 · 패널 비율 드래그 · 시간 기반 숨김 · THC QuickSPI. 실기에서 볼 것 셋은 `running-tars.md`에
있다(`kind=` · 터치패드 출발값 셋 · 두 손가락 방향).

#### PD-M4 — 마우스 보고(같은 날 덧붙인 milestone)

M0~M3을 닫은 직후 사용자의 결정("마우스 보고 기능은 지금 마일스톤에 이어서 M4 태스크로 진행하자. 같은 맥락이라 새로운
마일스톤으로 빼는 것이 합리적이지 않은 것 같아")으로 비목표 1을 결정 12 · PD-M4로 열어 같은 날 닫았다. design 절과 plan은
Opus planner가, 구현은 Opus가 했다.

| 커밋 | 무엇 |
|---|---|
| `1050b6f` | 다시 열기(design Status · HANDOFF) |
| `c29f3eb` | M4 — `pointer.Owner` · `Grab`(첫 누름이 주인) · `wheelRoute` · `Gesture.handOff` · `vt.mouseEncode`(ghostty `encodeMouse` 감싸개, 형식 다섯) · `wheelKeys`(모드 1007) · `input.State.modifiers` · `main.zig` 편집 열 · 게스트 vimrc `mouse=a ttymouse=sgr` · GE design 덧붙임 셋 · `pointer/check.sh` 검사 26~32(설정 디스크의 bash `read -N` 프로브 · vim 클릭) · 호스트 검사 OK 140 · 82 · 16 · 루트 게이트 19체인 2/2, 49분 56초 |
| (이 커밋) | 다시 닫기 — design Status · CLAUDE.md 표 `PD-M0~M4` · 기억 · MEMORY.md · lessons 이월 숙제 · HANDOFF |

규칙 하나로 가른다: 누른 패널의 자식이 모드 9 · 1000 · 1002 · 1003을 켰고 copy mode가 아니고 Shift가 없으면 자식의 것이다.
포커스가 아닌 패널이면 포커스를 먼저 옮기고 그 패널에 보고한다(tmux 순서). 휠은 copy mode면 무시 · Shift면 우리 스크롤 ·
자식이 원하면 버튼 4 · 5 · 대체 화면에 1007이면 화살표 키 세 번 · 그 밖은 우리 스크롤. 비목표로 남은 것은 design 14~18(1004
포커스 보고 · XTSHIFTESCAPE · OSC 52 · 가로 휠과 포인터 모양 · 보고 끄기 설정).

#### (PD를 닫을 때의) 바로 다음에 할 것

후보는 아래 PE 절의 "그 다음 후보"(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB 동글 층 B · WP-M3 방향
포커스 · vim-runtime)와 PD의 비목표(더블클릭 단어 선택 · `tars.conf`의 휠 방향 · 포인터 가속)다. 작은 것은
`docs/guides/lessons.md`의 "이월 숙제"에 있다. 실기에서 볼 것 셋(`pointer> open`의 `kind=` · 터치패드 출발값 셋 · 두 손가락
방향)과 넷째(vim에서 클릭이 커서를 옮기나)는 `running-tars.md`에 있다.

### PD-M0~M3을 닫을 때의 "다음 후보"(M4 뒤에 유효)

후보는 마우스 보고(위), 그리고 아래 PE 절의 "그 다음 후보"(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB
동글 층 B · WP-M3 방향 포커스 · vim-runtime)다. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

측정 파일(저장소 밖, 지워도 된다): `/tmp/run/mp0`(lead 실측) · `/tmp/run/pdm0` ~ `pdm3`(planner · 구현자 사본과 로그) ·
`/tmp/gate_pd0.log` ~ `gate_pd3.log`(루트 게이트 로그).

### 그 앞 — Paste Ergonomics(PE)가 M0~M2로 닫혔다


2026-10-04 GE를 닫은 직후 열어 같은 날 닫았다. GE가 남긴 둘(터미널의 bracketed paste · 사용자 vimrc
영속)에 루트 게이트를 흔들던 `service` 체인 경합 하나를 M0으로 묶었다. design은
`docs/specs/2026-10-04-tars-paste-ergonomics-design.md`(결정 9 · 위험 7 · 실측 10, `Status: 끝났다`),
plan은 `-pe-m0.md` · `-pe-m1.md` · `-pe-m2.md`이고 각 끝의 "실측한 것" 절이 값이다. 기억은
`docs/decisions/project_paste_ergonomics.md`.

사용자의 지시("계획 수립과 구현을 목적에 맞는 model을 선택하고 sub agents를 사용하여")로 design과
plan 셋은 Opus 서브에이전트가, 구현은 M0 · M2(이미 있는 모양을 옮긴다)를 Sonnet · M1(판단과 화면
판정을 새로 만든다)을 Opus 서브에이전트가 했고 Fable이 사실 조사 · 대조 · 루트 게이트 · commit을
맡았다. 이번에는 mutation도 구현자가 돌리고 Fable은 로그를 읽었다. 구현자는 전부 main 작업 트리에서
편집했다(루트 게이트와 겹치지 않게 순서를 두었다 — M2 planner만 M1의 게이트가 도는 동안 썼고, 그때
빌드 · QEMU · 저장소 편집을 금지했다).

planner들이 lead · design의 전제를 여럿 바로잡았다. 이것이 이 방식의 값이었다.
- M0: "부팅 C · D가 임대를 안 기다린다"가 아니라 셋 다 `boot_ssh`에서 기다리고 있었고, 원인은 dhcpcd가
  `leased`를 주소를 붙이기 전에 찍는 것이었다(lessons 실측 73). 이월 숙제의 진단이 틀렸던 것이다.
- M1: 꼬리 `ESC[201~`를 빠뜨리면 fish가 그 뒤의 키를 전부 삼킨다(mutation 3이 새 검사가 아니라 기존
  검사 11에서 잡혔다) · fish 4.0.2는 인자를 치는 중에 모드 2004를 끈다(design 위험 4에 덧붙였다) ·
  `cat` 아래의 에코와 출력 순서는 스케줄이 정한다(화면 모양 대신 개수로 판정).
- M2: `vim -e`가 `xterm-256color`에서 대체 화면에 찍어 출력이 사라진다(`-T dumb`, lessons 실측 74) ·
  `HOME=/`에서는 `~/.vimrc`가 아니라 `/.vimrc`로 찍힌다 · `seedOneFile`에 `O_TRUNC`가 없어 `.EXCL`만
  빼는 mutation은 잡히지 않는다(`.TRUNC`로 바꿨다). design 실측의 pyte가 대체 화면을 구현하지 않아
  첫째를 놓쳤다 — pyte로 잰 화면은 대체 화면에 대해 믿지 않는다.

| 커밋 | 무엇 |
|---|---|
| `d237fb2` | M0 — `service/check.sh`의 `boot_ssh`가 `leased` 뒤에 `eth0: adding default route via 10.0.2.2`를 30초까지 더 기다린다. 코드 0줄. 루트 게이트 대신 `service` 체인 5/5(1분 11~15초), 스무 로그 중 순서가 뒤바뀐 것 0 |
| `2c0443e` | M1 — `vt.Screen.pasteParts`(모드 2004를 보고 머리 · 본문 · 꼬리 셋) · `dumpPaste`가 `pty.write` 세 번, 로그 `clip> paste len=N bracketed=0\|1`(`len=`은 본문 그대로라 기존 판정 안 바뀜) · `vt_test` 93~96 · `copy/check.sh` 검사 21(fish 프롬프트에 두 줄 — Enter 전에 안 돌고 뒤에 둘 다 돈다) · 22(`cat` 아래 — 화면에 `[200~` 없음). mutation 넷 전부 빨감. 루트 게이트 18체인 3/3(1시간 7분 14초, M0의 기록도 됨) |
| (이 커밋) | M2 — initrd 링크 `/.vimrc -> config/vimrc` · `init`의 `VIMRC_SEED`(주석 21줄 843바이트) · `seedVimrc()` · `config_test`의 `expectVimrcSeed`(규칙 다섯) · `kernel/vim/vimrc` 주석 · `config/check.sh` 1차 셋(`vim -T dumb -e +scriptnames +qa` → `2: /.vimrc` · 에러 없음 · `>> /.vimrc` 되읽기) + 2차 하나(`+'set ts?'` → `tabstop=3`) · `tools/check.sh` `WANT`에 `.vimrc`. mutation 다섯 전부 빨감. 루트 게이트는 M2 plan 실측 7 |

열지 않은 것(design 비목표): 모드가 꺼진 갈래의 `\n` → `\r`과 제어 바이트 치환(`encodePaste`로 옮길
자리 — 클립보드가 화면 밖에서 오게 되면) · 감싸지 않는 여러 줄 붙여넣기를 막거나 묻는 것 · OSC 52 ·
`/.viminfo`를 `/config`로 · 큰 붙여넣기에서 `pty.write`가 멈추는 것(non-blocking 쓰기와 큐) · SLIRP의
SYN 재전송 시각 · vim의 계단을 게이트에서 보는 것 · fish의 확장 키 모드 · `tars.conf`로 bracketed
paste를 끄고 켜는 것.

### PE를 닫을 때 적어 둔 다음 후보(그대로 유효)

후보는 아래 "그 다음 후보" 절(ZU-M2는 ghostty의 Zig 0.17 전환 대기 · 패키지 매니저 · IPv6 · USB
동글 층 B)과 WP-M3(방향 포커스), GE가 남긴 `vim-runtime`(38MB — 문법 색 · filetype, syntax 파일 몇
개만 고르는 길과 함께)이다. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다 — PE-M0이
service 두 항목을 지워서 지금 그 목록에 체인 경합은 없다.

### 그 앞 — Guest Ergonomics(GE)가 M0 · M1로 닫혔다

2026-10-04 같은 날 PE 바로 앞에 닫았다. `which`(debianutils의 sh 스크립트, `copy_lib_deps`의 ELF magic
검사, M0 `a53f57b`)와 plugin · 런타임 없는 모던 시스템 vimrc(M1 `48431e7`). design은
`docs/specs/2026-10-04-tars-guest-ergonomics-design.md`, 기억은 `docs/decisions/project_guest_ergonomics.md`.
GE가 비워 둔 위험 2(autoindent 계단)와 비목표 2(사용자 vimrc) · 4(bracketed paste)를 PE가 채웠다.

### 그 앞 — Cursor Shape(CU)가 M0 · M1로 닫혔다

2026-10-04 같은 날 GE 바로 앞에 닫았다. 우리 렌더러가 DECSCUSR 모양 셋을 그리고(M0, `8d65077`),
게스트 vi를 `vim-tiny`(`-cursorshape`)에서 `vim.basic`으로 바꿔 시스템 vimrc 세 줄과 stub
`defaults.vim`을 initrd에 넣었다(M1, `9f97b4b`). 그 vimrc를 GE-M1이 넓혔다. design은
`docs/specs/2026-10-04-tars-cursor-shape-design.md`, 기억은 `docs/decisions/project_cursor_shape.md`.

### 그 앞 — Workspace Panes(WP)가 M0~M2로 닫혔다

2026-10-03 사용자의 요청으로 열어 2026-10-04에 닫았다 — "Cmd+1~9 workspace 전환, Cmd+D ·
Cmd+Shift+D pane split", 이어서 "Cmd+W로 닫기", "포커스 이동", "Cmd+T 새 탭". 모델은 iTerm2
그대로다: 워크스페이스가 탭(아홉까지), 각 워크스페이스는 패널을 이진 분할로 여덟까지, 패널
하나가 셸 하나(PTY · `vt.Screen` · 격자 안 사각형). design은
`docs/specs/2026-10-03-tars-workspace-panes-design.md`(`Status: 끝났다`), 기억은
`docs/decisions/project_workspace_panes.md`, plan은 `-wp-m0.md` · `-wp-m1.md` · `-wp-m2.md`이고
각 plan의 "실측한 것" 절이 값이다.

이 서브프로젝트는 설계를 Fable이, 구현을 Opus 서브에이전트가 했다(사용자의 지시). 서브에이전트는
commit하지 않고 diff · 로그만 보고했고, Fable이 파일 · 로그를 직접 대조한 뒤 commit했다. 세
milestone 모두 보고와 파일이 어긋난 자리는 없었다. 관찰: 서브에이전트가 mutation에서 plan의 구멍을
둘 찾아 검사를 스스로 더했다(`$COLUMNS` · `caps ink off=`) — 그것이 이 방식의 값이었다.

| 커밋 | 무엇 |
|---|---|
| `37798ad` | M0 — `layout.zig`(순수 트리) · `Pane` · `Workspace` · `spawnPane` · `paneOrigin`. 눈에 보이는 변화 0 |
| `ef0f0c3` | M1 — `Cmd+D` · `Cmd+Shift+D` · `Cmd+W`(SIGHUP, 닫힘은 EOF 경로 하나) · `Cmd+]` · `Cmd+[` · `Screen.resize` · `pty.resize` · 구분선 · `pane>` 줄 · 열여덟번째 체인 `pane/check.sh` |
| `778f5bb` | M2 — `Cmd+T` · `Cmd+1~9` · 상태 줄 `W2` 칸 · 워크스페이스 삭제 · 닫은 뒤 포커스를 형제로(`Tree.heir`). `pane/check.sh` 검사 열여섯 · 루트 게이트 18체인 3/3(1시간 4분 30초) |

열지 않은 것: WP-M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor` — design Milestone 절에
모양이 있다. 순환만으로 네 패널을 다니는 것이 불편해지면 연다) · 패널 간 클립보드 · 비율 조절.
사용자가 그대로 두기로 한 것: M1이 바꾼 `Cmd+Shift+←·→·Backspace`(Shift를 무시하던 것이 맨
키로 나간다).

### 그 앞 — Zig Upgrade(ZU)가 M1까지 왔다, M2는 ghostty의 Zig 0.17 전환을 기다린다

Zig 0.17.0이 나왔다(2026-10-03). 사용자의 다른 저장소(`_a-book/monorepo`, `3aad8cc`)는 같은 날
올렸지만 이 저장소는 ghostty가 막는다. `terminal`이 ghostty 소스를 패키지로 물고, ghostty의
`requireZig`가 major · minor 정확 일치를 요구한다. 업스트림 0.17 전환은 draft PR #14519 · 이슈
#14518에 있다(2026-10-02 개설, 0.16 때는 석 달 반 걸렸다).

사용자의 결정: 0.16에서 고쳐도 되는 것만 지금 고치고, ghostty가 0.17로 가면 그때 마무리한다.
design은 `docs/specs/2026-10-03-tars-zig-upgrade-design.md`(결정 5 · 위험 3 · 실측 1~5), plan은
`-zu-m0.md` · `-zu-m1.md`다.

| 커밋 | 무엇 |
|---|---|
| `a4953c0` | M0 — 배열 곱 `**` 25줄 → `@splat`(0.17이 문법을 없앴다) |
| `1a71c6c` | M1 — `@cImport` 다섯 → translate-c 패키지(ghostty가 0.16에서 쓰는 `80f8b6e` 판). fortify를 끄는 자리가 셋에서 `c_poll` stub 헤더의 `#undef` 하나로 줄었다 · 루트 게이트 17체인 3/3(1시간 1분 50초) |

0.17 컴파일러로 `ast-check`하면 `init` · `terminal/src` 오류가 0줄이다. 남은 것은 0.16에 없는 이름
(`@backingInt` · `std.lang`)과 버전 줄뿐이다.

### 그 사이 — Copy Indicator(CI)가 M0 하나로 닫혔다

2026-10-03 사용자의 요청 한 줄("copy mode에 있을 때 맨 아랫줄에 표시를")로 열고 같은 날
닫았다. copy mode에 있는 동안 상태 줄(IS) 꼬리에 다섯째 칸 `COPY`가 뜨고 Esc로 나가면
사라진다. 앞 넷은 안 움직이고, 색은 전용 `STATUS_COPY`라 `caps ink` 판정이 그대로 산다.
`status.zig`는 `vt.zig`를 모른 채 `copy: bool` 하나를 더 받는다.

design은 `docs/specs/2026-10-03-tars-copy-indicator-design.md`(결정 6 · 위험 3 · 실측 1~6),
plan은 `-ci-m0.md`, 기억은 `docs/decisions/project_copy_indicator.md`다. 새 체인은 없고
`copy/check.sh`가 검사 2a · 6a(글자와 픽셀을 짝으로)를 더했다. mutation(`st.copy` 무시)은
`text=`가 맞는데 `ink=0`으로 잡혔다 — 글자만 보는 판정이었으면 통과했을 고장이다.
루트 게이트 17체인 3/3 PASS, 약 1시간 2분(2026-10-03). 커밋 `362e36d`.

사용자가 요청에 적은 진입 키는 `Cmd+Shift+V`였지만 실제 진입 키는 `Cmd+Shift+C`다
(`Cmd+V`는 붙이기). 코드 기준으로 진행했다.

### 그 앞 — Terminal Graphics(TG)가 M3로 닫혔다

TG가 2026-10-03 하루에 M0~M3로 닫혔다(design `Status: 끝났다`). 자식이 kitty graphics로 보낸
이미지를 우리 렌더러가 그린다. 해석과 저장은 ghostty vt가 하고, 우리 몫은 셀 픽셀 크기 알리기 ·
placement를 픽셀 사각형으로 바꾸기(`vt.zig`) · 그리기(`image.zig`) · PNG 디코더(`png.zig`,
`stb_image`)다.

design은 `docs/specs/2026-10-03-tars-terminal-graphics-design.md`(결정 7 · 위험 3 · 실측 1~9),
plan은 `docs/plans/2026-10-03-tars-terminal-graphics-tg-m0.md` ~ `-tg-m3.md`, 기억은
`docs/decisions/project_terminal_graphics.md`다.

| 커밋 | 무엇 |
|---|---|
| `b90a7d0` | design · M0 실측(코드 0줄) |
| `4cda837` | M1 — `CellPx` · `Screen.images()` · `vt_test` 65~74 |
| `a8a68d0` | M2 — `image.zig` · `render()`의 층 셋 · `render` 체인 검사 15~18 |
| `cc934d9` | M3 — PNG(`stb_image`) · `vt_test` 75~77 · 검사 19 · mutation · 루트 게이트 · 문서 |

새 체인은 없다. 루트 게이트 17체인 3/3(1시간 1분 25초, `FAIL` 0줄, 2026-10-03). mutation(PNG
디코더 설치 줄 빼기)은 `vt_test` 75가 부팅 전에 잡았다.

superpowers 없이 연 첫 서브프로젝트였다. 관찰은 `docs/decisions/feedback_superpowers_off.md`
끝에 있다 — plugin이 막았을 누락은 못 봤다.

### 그 다음 후보 — 새 서브프로젝트를 고른다 (ZU-M2는 ghostty 대기)

WP-M3(방향 포커스)은 맨 위 절에 있다. 아래는 ZU-M2와 그 밖의 후보에 대한 메모다.

ZU-M2를 여는 신호는 ghostty main의 `build.zig.zon`이 `minimum_zig_version = "0.17.0"`이 되는 것이다
(`curl -sSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/build.zig.zon | rg minimum_zig`).
태그 릴리즈는 기다리지 않는다 — SHA로 고정한다. M2가 할 것은 design의 Milestone 절에 있다:
`Dockerfile`의 `ZIG_VERSION` · `vendor_libghostty_vt.sh`의 `GHOSTTY_SHA` · zon의 `minimum_zig_version`과
translate-c URL · hash(codeberg `875969d`) · 0.17 `zig fmt`(원래 있던 fmt 차이 61줄이 섞인다, 실측 2) ·
`std.builtin` → `std.lang` · "0.16"을 적은 문서들. 첫 일은 ghostty `src/terminal`의 API 변화 읽기(위험 2).
호스트 macOS의 0.17은 `~/.local/zig/zig-aarch64-macos-0.17.0/zig`에 있다(빌드는 컨테이너가 한다).

2026-10-03 다시 봤을 때도 신호는 없었다 — ghostty main은 `"0.16.0"`, PR #14519는 draft에 CI 실패
(`test` · `test-lib-vt`). 그 사이 호스트 `PATH`의 첫 `zig`가 `/opt/homebrew/bin/zig` 0.17이 됐다.
호스트에서 `terminal` · `init`을 직접 `zig build`하면 깨질 수 있으니 빌드는 계속 컨테이너에서 한다.

TG를 닫은 뒤 이미지 뷰어를 다음으로 열려 했다가 2026-10-03에 사용자가 접었다. 재 보니 Debian
`chafa`(1.14.5)는 바이너리가 190KB인데 재귀 `DT_NEEDED`가 sysroot에 없는 `.so` 69개, 44.6MB를
끌고 온다 — `libSvtAv1Enc` 7.8MB · `librsvg-2` 6.1MB · `libaom` 5.5MB · `librav1e` 3.2MB(AVIF ·
SVG 로더 때문) · glib · cairo · X11 · harfbuzz. RAM 위 initrd에 늘 얹기에는 크다.

사용자의 결정: 뷰어는 기본 이미지에 넣지 않고, 필요한 사람이 패키지 관리자(brew)로 설치하게
남긴다. 그래서 이 일은 후보 "패키지 매니저"의 본론이 된다. brew 쪽에서 확인한 사실:
- Homebrew `install.sh`의 `check_run_command_as_root`가 root이면 `Don't run this as root!`로
  멈춘다. 예외는 컨테이너 표지(`/.dockerenv` · `/run/.containerenv` · cgroup 이름)뿐이다.
  게스트는 전부 root다 — termium이 막힌 자리와 같다. non-root 사용자가 먼저다.
- 설치물은 디스크의 prefix(`/home/linuxbrew/.linuxbrew`)에 놓여야 한다. DI의 설치 디스크 위다.

어느 뷰어든 `pty.zig`의 `ws_xpixel` · `ws_ypixel`(지금 0)은 우리가 채워야 한다 — 이월 숙제에 있다.

남은 후보 — 패키지 매니저(위의 brew · non-root · 디스크 prefix) · IPv6(방화벽 표를 `inet`으로,
FW design 위험 6) · USB 동글 층 B. 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

⚠ 이어받는 사람이 볼 것:
- Docker는 OrbStack이다. 소켓이 없다고 나오면 `orb start`.
- 새로 받은 저장소면 이미지부터 굽는다(Dockerfile 층 12, WL). 첫 빌드가 linux-firmware
  662MB를 `kernel/src/firmware/`에 받고 `clean()`이 안 지운다. TG-M3부터 `prepare.sh`가
  `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(lessons 62).
- 실칩 무선은 PCIe도 USB도 한 번도 안 떴다 — 실기와 실제 동글이 생기면 그것이 새 사실이다.

## 어디를 보면 되는가

2026-09-27에 이 파일을 193KB에서 줄였다. 서브프로젝트마다 쌓이던 "그 앞" 절들
(SD부터 LB까지)은 지웠다 — 각 서브프로젝트의 경과는 그 design의 실측 절과
`docs/decisions/`의 기억에 있고, 지운 원문은 `git show 76c668e:HANDOFF.md`로 본다.

| 무엇 | 어디 |
|---|---|
| 협업 규칙 · 끝난 서브프로젝트 표 | `CLAUDE.md` |
| 세션을 넘는 기억(색인) | `MEMORY.md` → `docs/decisions/` |
| 게이트를 돌리고 읽는 법 · 범용 명령 · 다시 조사하지 말 실측 · 안 되는 접근 · 이월 숙제 · 핵심 파일 지도 | `docs/guides/lessons.md` |
| 사람이 TARS를 띄우는 법 | `docs/guides/running-tars.md` |
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열여덟) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
