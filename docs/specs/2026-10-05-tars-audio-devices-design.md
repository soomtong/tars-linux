# TARS Audio Devices — Design

Date: 2026-10-05
Status: 쓰는 중. M0 plan(`docs/plans/2026-10-05-tars-audio-devices-au-m0.md`)까지 썼고 구현 전이다. 사본에서의 측정은
2026-10-05~06에 했다.

사용자의 요청(2026-10-05)에서 시작한다.

> 1. 오디오(마이크/이어폰/스피커) 기기 활성화.

같은 요청의 2번(마이크로 음성 전사, macOS 앱 Voxio의 포팅)은 이 서브프로젝트가 닫힌 뒤 Voice Dictation(VD)으로 따로 연다.
VD는 `arecord`로 WAV를 뜨고 `curl`로 전사 API에 보내는 모양이 될 것이므로, 이 서브프로젝트가 세울 것은 "게스트에서
`arecord`가 마이크의 바이트를 뜨고 `aplay`가 스피커로 바이트를 낸다"이다.

## 한 줄 요약

커널이 사운드 카드를 올리고, 사람은 노트북에서 쓰던 명령(`aplay` · `arecord` · `amixer` · `speaker-test`)을 그대로 친다.
우리 코드가 짜는 자리는 부팅에 믹서를 켜고 기억하는 것(M1)과 게이트뿐이다. 나머지는 커널의 ALSA와 Debian의 alsa-utils다.

```
AU-M0   aplay tone.wav                →  커널 HDA 드라이버 → 코덱 → 스피커(게이트: 샘플이 값까지 같게 QEMU 밖에 닿는다)
        arecord -d 2 x.wav            →  마이크 → 코덱 → x.wav(게이트: QEMU 밖에서 넣은 샘플이 값까지 같게 파일에 남는다)
        speaker-test -c 2 -t wav      →  왼쪽에서 "Front Left", 오른쪽에서 "Front Right"
        부팅 직후                      →  Master · Capture가 꺼져 있다. 사람이 `amixer sset Master unmute`로 켠다
AU-M1   부팅 직후                      →  소리가 켜져 있다. 사람이 바꾼 볼륨이 다음 부팅에도 남는다
AU-M2   노트북의 HDA 코덱 · 헤드폰 잭 · USB 헤드셋  →  같은 명령이 실기에서 소리를 낸다
AU-M3   DSP를 거치는 노트북(Intel SOF · AMD ACP)의 내장 마이크  →  firmware와 함께
```

## 왜 새 서브프로젝트인가

지금 커널에는 소리가 아예 없다(`# CONFIG_SOUND is not set`, 실측 1). 게스트에는 소리를 다루는 도구도 라이브러리도 없다
(실측 2). 그래서 이 일은 기존 서브프로젝트의 비목표를 다시 여는 것이 아니라 층 셋을 새로 쌓는 것이다.

| 층 | 무엇 | 누구의 것 |
|---|---|---|
| 커널 | 사운드 카드를 찾아 `/dev/snd/*`로 내놓는다. 코덱의 핀 · 앰프 · 잭을 다룬다 | Linux ALSA |
| 유저랜드 | WAV를 읽고 쓰는 명령, 믹서, 기본 장치(여러 프로그램을 섞는 dmix · dsnoop) | Debian alsa-utils · alsa-lib |
| 활성화 | 부팅에 믹서를 켜고, 사람이 바꾼 것을 기억한다 | 우리(`init`) — M1 |
| 게이트 | 스피커로 나간 샘플과 마이크로 들어온 샘플을 값까지 본다 | 우리 — 새 체인 `audio/check.sh` |

Pointer Devices(PD)가 마우스로 공통 부분을 끝까지 만든 뒤 터치패드를 얹었듯이, 여기서는 QEMU가 흉내 낼 수 있는
HDA로 세 층을 끝까지 만든 뒤(M0 · M1) 실기의 드라이버를 얹는다(M2 · M3).

## 모델

샘플 하나가 지나는 길이다. 재생은 위에서 아래로, 녹음은 아래에서 위로 간다.

| 자리 | 재생(`aplay x.wav`) | 녹음(`arecord x.wav`) |
|---|---|---|
| 프로그램 | WAV를 읽어 libasound에 쓴다 | libasound에서 읽어 WAV로 쓴다 |
| libasound의 `default` | `/usr/share/alsa/alsa.conf` → `plug`(형식 · 속도 변환) → `dmix`(여러 프로그램을 섞는다) | `plug` → `dsnoop`(여러 프로그램이 같은 마이크를 나눈다) |
| 노드 | `/dev/snd/pcmC0D0p` | `/dev/snd/pcmC0D0c` |
| 커널 | `snd-hda-intel`(컨트롤러의 DMA) → 코덱 드라이버(핀 · 앰프) | 같다 |
| 하드웨어 | 코덱의 DAC → 앰프(Master) → 스피커 | 마이크 → 앰프(Capture) → 코덱의 ADC |

믹서는 노드 하나(`/dev/snd/controlC0`)를 거쳐 코덱의 앰프를 만진다. 커널의 HDA 드라이버는 Master와 Capture를
최소값에 꺼 둔 채 카드를 올린다(실측 7) — 그래서 위의 길이 전부 맞아도 사람에게는 아무 소리도 안 들린다. 이 자리가
결정 4이고 M1의 일이다.

## 결정

### 결정 1 — 커널은 ALSA 코어 · HDA 컨트롤러 · 범용 코덱과 `SYSVIPC`를 켠다. 실기의 드라이버는 뒤 milestone이다

M0이 `scripts/config -e`로 적는 것은 다섯이다. 전부 내장(`=y`)이다 — 이 커널에는 모듈이 없다(`# CONFIG_MODULES is not set`).

| 심볼 | 왜 |
|---|---|
| `SOUND` · `SND` | ALSA 코어. `olddefconfig`가 `SND_PCM` · `SND_TIMER` · `SND_JACK` · `SND_PROC_FS` · `SND_VMASTER` 등을 끌어온다 |
| `SND_HDA_INTEL` | HDA 컨트롤러. 노트북 소리의 거의 전부가 이 컨트롤러를 지난다 — Intel PCH와 AMD의 아날로그 출력 · 헤드폰 잭 |
| `SND_HDA_GENERIC` | 범용 코덱 파서. QEMU의 HDA 코덱(`QEMU Generic`)을 이것이 맡는다. 실기에서도 전용 코덱 드라이버가 없는 코덱을 이것이 받는다 |
| `SYSVIPC` | 결정 3. alsa-lib의 기본 장치가 SysV 세마포어와 공유 메모리를 쓴다 |

`olddefconfig`가 더하는 것 중 둘을 적어 둔다. `SND_INTEL_DSP_CONFIG`(HDA 컨트롤러가 Intel의 DSP 경로를 쓸지 고르는 표)가
따라 켜지는데, 그 표의 항목이 전부 `IS_ENABLED(CONFIG_SND_SOC_SOF_…)`로 감싸여 있어서 SOF를 안 켠 커널에서는 언제나
HDA로 간다(커널 소스 `sound/hda/core/intel-dsp-config.c`). DSP를 쓰는 노트북도 M0~M2의 커널에서는 HDA로 스피커와 헤드폰
잭이 붙고 DMIC(내장 디지털 마이크)만 안 붙는다는 뜻이다. 그리고 `SND_JACK_INPUT_DEV`가 켜진다 — 프롬프트가 없고
`INPUT=y`면 무조건이다. 실기의 HDA 코덱은 잭마다 입력 장치(`HDA Intel PCH Headphone` 같은 것)를 하나씩 만든다(위험 2).

| 후보 | 왜 아닌가 |
|---|---|
| (a) HDA 컨트롤러 + 범용 코덱 | 고른 것. QEMU가 흉내 내는 노트북 모양이 이것이고, 게이트가 바이트로 볼 수 있는 길이 이것뿐이다 |
| (b) 여기에 실기 코덱(Realtek · Conexant · Cirrus 등)까지 | M2. 코덱 드라이버는 노트북마다의 quirk 표이고 QEMU에 그 코덱이 없다. 게이트가 심볼과 표로만 보는 덩어리라 QEMU 경로와 섞지 않는다 |
| (c) 여기에 DSP(Intel SOF · AMD ACP)까지 | M3. firmware · topology가 붙고 QEMU에 없다 |
| (d) `virtio-sound` | QEMU에는 있지만 노트북에는 없다. TARS는 일반 x86_64 노트북에서 돈다(`project_target_hardware`) |
| (e) QEMU의 옛 장치(AC97 · ES1370 · SB16) | 같은 이유. 노트북에 없다 |

크기와 시간(실측 11). bzImage가 7,758,848 → 7,955,456바이트(+196,608, 2.5%)이고 커널 증분 빌드가 125초였다. `Run /init`은
늦어지지 않고 오히려 0.7초 빨라졌다 — PD 실측 3(lessons PD-3)이 적은 코드 배치의 몫이다. 그래서 `install` 체인 부팅 7의
여유가 1,100 · 1,200ms에서 1,800 · 1,900ms로 늘었다. 다음 커널 변경이 그것을 다시 움직일 수 있다.

### 결정 2 — 유저랜드는 alsa-utils를 그대로 쓴다. 넣는 것은 바이너리 넷과 링크 하나, 설정 트리, 목소리 파일 둘이다

| 후보 | 왜 아닌가 |
|---|---|
| (a) alsa-utils의 일부와 libasound를 sysroot에서 initrd로 | 고른 것 |
| (b) PipeWire · PulseAudio | 데몬 · D-Bus · 세션이 딸려 온다. 하는 일의 대부분이 앱 사이의 섞기 · 라우팅 정책이고 그것은 비목표 2다. 기본 장치의 섞기는 alsa-lib의 dmix가 이미 한다(결정 3) |
| (c) 재생 · 녹음을 Zig로 직접 짠다 | `project_write_or_reuse`의 두 기준에 다 안 걸린다. 원하는 동작이 `aplay` · `arecord`와 글자 그대로 같고, 잘 짜도 아무도 모른다. VD가 기대하는 것도 `arecord`의 WAV다 |

넣는 것(실측 5).

| 이름 | 자리 | 왜 |
|---|---|---|
| `aplay` | `guest_tools.sh` 층 14 | 재생 |
| `arecord` | `make_initrd.sh`의 링크 `arecord -> aplay` | 녹음. 바이너리 하나가 argv[0]으로 가른다 — `vi -> vim`과 같은 자리 |
| `amixer` | 층 14 | 믹서. M0에서는 사람이 소리를 켜는 유일한 길이다(결정 4) |
| `alsamixer` | 층 14 | 같은 일의 화면판. 게이트가 못 치는 대화형이라 목록 검사가 전부다 |
| `speaker-test` | 층 14 | 왼쪽 · 오른쪽을 목소리로 확인한다 |
| `libasound.so.2` | `copy_lib_deps`가 따라온다 | 넷이 부르는 것. 새 라이브러리는 이것 하나(1,178,192바이트). `alsamixer`의 form · menu · panel은 libncursesw6 패키지에 이미 있다 |
| `/usr/share/alsa` | `make_initrd.sh`가 통째로 | libasound가 컴파일 타임에 박아 둔 설정 트리. 파일 86개 182,416바이트. 없으면 `aplay -l`부터 죽는다 |
| `Front_Left.wav` · `Front_Right.wav` | `make_initrd.sh` | `speaker-test -c 2 -t wav`가 읽는 둘. 나머지 일곱 채널의 목소리는 노트북에 없는 채널이다 |

`alsactl`은 M0에 안 넣는다. 믹서를 저장하고 되살리는 도구이고, 그것을 쓸지는 M1이 정한다(결정 4).

비용(실측 12). initrd가 89,701,730 → 90,542,534바이트(+840,804, gzip과 firmware 꼬리 포함)이고 게스트 도구가 87 → 91이다.
Dockerfile이 받는 패키지는 셋(`alsa-utils:amd64` · `libasound2t64:amd64` · `libasound2-data`)이다.

### 결정 3 — 기본 장치(dmix · dsnoop)가 돌게 한다: `SYSVIPC`와 `audio` 그룹

사람이 치는 `aplay x.wav`는 장치를 안 고른다. 그러면 libasound가 `default`를 여는데, HDA 카드의 `default`는 `plug`를
거쳐 `dmix`(재생) · `dsnoop`(녹음)이다. 둘은 여러 프로그램이 한 장치를 같이 쓰게 하려고 SysV 세마포어와 공유 메모리를
만든다. 사본에서 두 겹으로 막혔다(실측 6).

```
SYSVIPC가 꺼진 커널     ALSA lib pcm_direct.c:2178:(_snd_pcm_direct_new) unable to create IPC semaphore
                       aplay: main:850: audio open error: Function not implemented
audio 그룹이 없을 때    ALSA lib pcm_direct.c:2048:(snd1_pcm_direct_parse_open_conf) The field ipc_gid must be a valid group (create group audio)
                       aplay: main:850: audio open error: Invalid argument
```

둘 다 `-D hw:0,0`(장치를 직접 고른다)으로는 돈다. 사람에게는 "가끔만 안 된다"로 보이는 고장이라 원인에서 멀다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) `SYSVIPC=y`와 `/etc/group`의 `audio:x:29:` | 고른 것. alsa-lib의 설정을 한 글자도 안 바꾸고 Debian과 같은 동작을 얻는다. 29는 Debian의 번호다 |
| (b) `/etc/asound.conf`로 `default`를 `plughw:0`에 묶는다 | `SYSVIPC` 없이 돈다. 그러나 두 프로그램이 동시에 못 쓴다 — 하나가 재생하는 동안 다른 하나는 `Device or resource busy`다. 그리고 우리 파일 하나가 alsa-lib의 기본값을 덮는다 |
| (c) 그대로 두고 사람이 `-D hw:0`을 친다 | VD와 사람이 둘 다 장치 이름을 알아야 한다. 노트북마다 다르다 |

`SYSVIPC`는 커널 크기를 거의 안 늘린다. 더불어 `SYSVIPC_SYSCTL` · `IPC_NS`가 따라 켜진다.

### 결정 4 — 커널은 소리를 꺼 둔 채 뜬다. M0에서는 사람이 켜고, 부팅이 켜고 기억하는 것은 M1이다

카드가 올라온 직후의 믹서다(실측 7).

```
Master   Front Left: Playback 0 [0%] [-74.00dB] [off]
Capture  Front Left: Capture 0 [0%] [-74.00dB] [off]
```

QEMU의 HDA 코덱은 이 앰프 값을 샘플에 그대로 곱한다. 그래서 이대로 재생하면 QEMU 밖에 0만 나오고, 녹음하면 0만
들어온다 — 게이트가 이 상태를 바이트로 볼 수 있다는 뜻이다(결정 5의 검사 4). 실기의 HDA 코덱도 같은 커널 코드(가상
Master)를 지나므로 같은 상태로 뜰 것으로 보지만 실기에서 재지는 않았다. Debian은 이 일을 udev 규칙(`alsactl restore`)과
systemd 유닛(`alsa-restore.service` · `alsa-state.service`)으로 한다. 우리에게는 둘 다 없다.

M0에서는 사람이 친다.

```
amixer sset Master unmute 80%
amixer sset Capture cap 80%
```

M1이 정할 것. 셋이고, 다 M1 plan의 몫이다.

1. 무엇이 켜나. 후보는 `init`이 `alsactl`을 `fork` · `execve`로 부르는 것(firewall의 `nft -f`와 같은 모양), 감독 목록에
   `alsactl`의 daemon을 넣는 것(DS의 dhcpcd · chronyd와 같은 모양), 우리가 control 노드에 ioctl을 직접 쏘는 것이다.
2. 무엇을 기억하나. `/config`가 붙으면 `/config/asound.state` 같은 파일 하나다. 사람이 바꾼 볼륨이 다음 부팅에 남아야 한다.
3. 늦게 오는 카드. HDA 코덱 탐색은 커널의 일 큐에서 돌고, USB 헤드셋은 부팅 뒤에 꽂힌다. 부팅에 한 번 켜는 것만으로는
   그 카드가 꺼진 채다.

M1이 알고 시작할 사실(실측 10). `alsactl init`은 QEMU 코덱에서 Master를 -20dB 켜짐으로, Capture를 0dB 켜짐으로 만들고,
`/usr/share/alsa/ucm2/ucm.conf`가 없다는 경고 두 줄을 찍는다(UCM 설정은 alsa-ucm-conf 패키지다). alsa-utils 1.2.14의 daemon
(`alsactl daemon` · `rdaemon`)은 새 카드를 SIGUSR1을 받아야만 다시 훑고, SIGTERM에는 저장 없이 끝나며, 저장하고 끝나는 것은
SIGUSR2다(`alsactl/daemon.c`). 우리의 종료 경로는 SIGTERM 뒤에 SIGHUP을 보낸다(SL) — 그대로 감독 목록에 넣으면 끄기
직전의 변경을 잃는다.

### 결정 5 — 게이트는 새 체인 `audio/check.sh`(스무번째) 하나, 부팅 하나, 판정은 바이트

QEMU에 노트북의 HDA를 흉내 내는 장치를 붙인다 — q35 · `ich9-intel-hda` · `hda-micro`(스피커 하나와 마이크 하나를 가진
코덱). 어려운 것은 마이크다. QEMU의 오디오 백엔드 넷(`none` · `alsa` · `oss` · `wav`) 중 파일에서 마이크를 공급하는 것이
없다(lead 실측). 후보를 재 봤다(실측 8 · 9).

| 후보 | 무엇을 보나 | 왜 아닌가 |
|---|---|---|
| (a) `wav` 백엔드 | 재생만. 녹음 쪽 voice가 없어 QEMU가 `Could not create a backend for voice 'adc'`를 찍고 게스트의 `arecord -D hw:0,0`이 `Input/output error`다 | 마이크를 못 본다 |
| (b) `none` 백엔드 | 녹음은 되는데 0만 들어온다 | "녹음이 됐다"와 "Capture가 꺼져 있다"가 같은 바이트다 |
| (c) 게스트 안의 `snd-aloop`(lead의 틀) | `aplay`의 바이트가 커널 안에서 `arecord`로 돌아온다 | HDA의 마이크 길(코덱 · ADC · Capture 앰프)을 한 바이트도 안 지난다. 게이트 전용 드라이버를 제품 커널에 넣어야 한다(hwsim과 같은 값) |
| (d) `alsa` 백엔드 + 컨테이너 alsa-lib의 `file` 플러그인 | 둘 다, 값까지 | 고른 것 |

(d)의 모양. QEMU의 `alsa` 백엔드는 컨테이너의 libasound를 쓰고, 그 libasound는 `$HOME/.asoundrc`를 읽는다. 거기에 장치
둘을 정의한다 — `null`이 시간을 내고 `file` 플러그인이 바이트를 바꿔친다. 둘 다 alsa-lib에 들어 있는 플러그인이라
컨테이너에 더 깔 것이 없다.

```
pcm.tarstap  { type file  slave.pcm "null"  file "$WORK/tap.raw"  format "raw" }                       # 스피커 → 파일
pcm.tarsfeed { type file  slave.pcm "null"  file "/dev/null"  infile "$WORK/feed.raw"  format "raw" }  # 파일 → 마이크
```

백엔드를 48kHz 스테레오 16비트로 박으면 QEMU가 샘플을 안 바꾼다. 사본에서 게스트의 사각파(±8000) 48,000프레임이
`tap.raw`에 정확히 48,000프레임 있었고, `feed.raw`의 상수(3000, -5000)가 게스트의 `cap.wav`에 96,000프레임 중
96,000프레임 있었다 — 기본 장치(dmix · dsnoop)를 지나서다.

게스트 쪽은 타이핑하지 않는다. 설정 디스크의 `services.d/probe`(= `audio/probe.sh`)를 `init`이 띄우고, 그 스크립트가
사람이 치는 명령 그대로를 치고 결과를 콘솔에 `audio-probe:` 줄로 찍는다. `wifi` 체인의 `services.d/ap`과 같은 모양이다.
녹음 파일은 설정 디스크에 남기고 체인이 QEMU를 끈 뒤 `debugfs`로 꺼낸다. monitor를 안 쓰므로 포트가 없다 — 45491은
그대로 비어 있다(뒤 milestone이 `device_add`를 쓰면 그때 받는다).

검사(M0).

| 검사 | 본다 |
|---|---|
| 1(부팅 없음) | `.config`의 다섯 심볼 · initrd의 `arecord` 링크 · libasound · `alsa.conf`와 `HDA-Intel.conf` · `dmix.conf` · `dsnoop.conf` · 목소리 둘 · `/etc/group`의 `audio` |
| 2 | 커널이 코덱을 설정했다(`snd_hda_codec_generic … autoconfig for Generic`) · `/proc/asound/cards`의 카드 0이 HDA-Intel · 노드 넷 |
| 3 | `aplay -l` · `arecord -l`이 카드 0 장치 0을 본다(라이브러리와 설정 트리를 지났다) |
| 4 | 부팅 직후 Master · Capture가 `0 [0%] … [off]`이고, `amixer`가 Master를 0dB 켜짐으로 만든다. 검사 5 · 7의 대조군이고 M1이 뒤집는다 |
| 5 | `aplay`(기본 장치)의 사각파가 `tap.raw`에 47,000프레임 이상, 섞이거나 깎인 프레임 0 |
| 6 | `speaker-test -c 2 -t wav`의 목소리가 왼쪽만 · 오른쪽만인 프레임으로 각각 10,000 이상, 왼쪽이 먼저 |
| 7 | `arecord`(기본 장치) 2초가 96,000프레임 전부 (3000, -5000) |

mutation(M0 plan이 사본에서 다 돌렸다 — plan 확정 7).

| 심는 고장 | 잡은 자리 |
|---|---|
| `SND_HDA_INTEL` 끄기 | 검사 1. 건너뛰면 검사 2(코덱 줄이 없다, `--- no soundcards ---`) |
| `SYSVIPC` 끄기(검사 1을 건너뛴 체인) | 검사 5(`unable to create IPC semaphore`) |
| `/etc/group`의 `audio` 빼기 | 검사 1. 건너뛰면 검사 5(`ipc_gid must be a valid group`) |
| `/usr/share/alsa` 빼기 | 검사 1. 건너뛰면 검사 3(`Cannot access file /usr/share/alsa/alsa.conf`) |
| 프로브의 `amixer` 두 줄 빼기 | 검사 4의 셋째(`amixer`가 Master를 못 켰다). 그것을 건너뛴 체인에서는 검사 5(사각파 0프레임 — 무음), 검사 5 · 6도 건너뛰면 검사 7(일치 0) |

### 결정 6 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가 한다

PD 결정 11 · EL · CB와 같다. plan은 milestone마다 그 시점에 Opus 서브에이전트가 쓰고, 코드를 저장소 밖 사본에서 컴파일 ·
체인 · mutation까지 돌린 뒤 `old_string` · `new_string`을 기계로 뽑아 넘긴다. M0의 구현은 Sonnet을 권한다 — 판단이 새로
필요한 자리가 없고(새 파일 둘은 사본을 복사하고, 편집 여덟은 글자 그대로 넣고, 커널은 정해진 명령을 친다) 일의 대부분이
이미지 굽기 · 커널 빌드 · 체인 · mutation을 정해진 순서로 돌리는 것이다. M1은 `init`에 코드가 들어가고 결정 4의 셋을 정해야
하므로 Opus다.

## lead의 전제를 바로잡은 것

1. 마이크 증명에 게스트 안 루프백(`snd-aloop`)이 필요하지 않다. 컨테이너 alsa-lib의 `file` 플러그인이 QEMU의 HDA
   마이크에 바이트를 공급한다(결정 5의 (d)). 그래서 M1의 "마이크 경로 증명"이 M0으로 들어오고, 루프백은 아무
   milestone에도 없다. 루프백은 HDA의 마이크 길을 안 지나므로 증명으로서도 더 약하다.
2. 재생의 증명도 `wav` 백엔드가 아니다. `wav`는 녹음 쪽이 없어서 마이크와 함께 쓸 수 없다. `alsa` 백엔드 하나가 두 방향을
   다 받는다.
3. 기본 장치가 돌려면 커널의 `SYSVIPC`와 `/etc/group`의 `audio`가 필요하다(결정 3). lead의 틀에 없던 것이고, 빠지면 `-D hw:0`은
   돌고 사람이 치는 `aplay x.wav`만 죽는다.
4. milestone이 셋이 아니라 넷이다. lead의 M2(SOF · ACP · USB Audio)를 firmware가 없는 것(M2: 실기 HDA 코덱 · USB Audio
   Class)과 있는 것(M3: SOF · ACP)으로 나눴다. 아래 Milestone 절이 근거다.
5. 포트를 안 쓴다. 이 체인은 monitor가 필요 없다(타이핑도 `device_add`도 없다). 45491은 다음 새 체인의 몫으로 남는다.

## 검증

호스트 검사는 없다 — M0에는 우리가 짠 Zig 코드가 한 줄도 없다. 판정은 결정 5의 체인 하나와, 커널과 initrd가 바뀌므로
regression 셋이다. 사본에서 돈 값(실측 11 · 12 · 13).

| 체인 | 왜 | 사본의 결과 |
|---|---|---|
| `audio`(새) | M0의 모든 것 | 네 판 초록. 캐시를 지운 첫 판 1분 56초(커널 재빌드 포함), 데운 판 17 · 18초 |
| `install` | 커널이 바뀌면 부팅 7의 창이 움직인다(PD-3) | 두 판 초록. `init waited` 1,800 · 1,900ms(HEAD는 1,100 · 1,200ms) |
| `tools` | 도구 목록이 87 → 91, initrd에 넣는 것이 는다 | M0 plan 확정 8 |
| `boot` | limine이 BIOS로 initrd를 읽는다. initrd가 커졌다 | M0 plan 확정 8 |
| `machine` | q35 · OVMF · simpledrm. 새 커널이 실기의 길에서 뜨는가 | M0 plan 확정 8 |

## Milestone

### AU-M0 — 커널 · 유저랜드 · 게이트(소리는 사람이 켠다)

결정 1 · 2 · 3 · 5. `kernel/.config` · `devcontainer/Dockerfile` · `kernel/guest_tools.sh` · `kernel/make_initrd.sh` · `check.sh`를
고치고 `audio/check.sh` · `audio/probe.sh`를 새로 만든다. 우리 Zig 코드는 0줄이다. plan은
`docs/plans/2026-10-05-tars-audio-devices-au-m0.md`.

### AU-M1 — 부팅이 믹서를 켜고 기억한다

결정 4의 셋. `init`에 코드가 들어가는 유일한 milestone이다. 체인은 검사 4를 뒤집고(부팅 직후 소리가 켜져 있다), 같은
디스크로 두 번 떠서 사람이 바꾼 볼륨이 남는 것을 본다. 늦게 오는 카드를 게이트로 볼지(QEMU의 `device_add`로 HDA를 부팅 뒤에
붙일 수 있는지는 재지 않았다)는 M1 plan이 잰다.

### AU-M2 — 실기의 HDA 코덱 · 헤드폰 잭 · USB 오디오

firmware가 없는 실기 드라이버다. HDA 코덱 드라이버(Realtek — 6.18에서 계열마다 심볼이 갈렸다 — · Conexant · Cirrus ·
Senarytech 등)는 노트북의 스피커 · 헤드폰 잭 · 아날로그 마이크와 헤드폰을 꽂으면 스피커가 꺼지는 것(auto-mute)을 맡는다.
`SND_USB_AUDIO`는 USB 헤드셋 · 이어폰 동글이다. 정할 것 하나가 기본 카드다 — libasound의 `default`는 카드 0이라 USB 헤드셋이
카드 1로 오면 안 쓰인다(`ALSA_CARD` env · `/etc/asound.conf` · `tars.conf` 키 중 무엇으로 고를지). 게이트는 심볼 · modinfo alias
(UW의 방식)와 QEMU `usb-audio`(재생만 있다)로 본다. HDMI · DisplayPort 오디오는 GPU 드라이버와 짝이라 비목표 6이다.

### AU-M3 — DSP를 거치는 노트북의 내장 마이크(Intel SOF · AMD ACP)

2019년 이후의 Intel 노트북 다수와 Ryzen 노트북의 내장 마이크는 HDA 코덱이 아니라 DSP 뒤의 DMIC다. Intel SOF(`sof-firmware`의
firmware와 topology, SoundWire 코덱을 쓰는 기계는 `sof_sdw`)와 AMD ACP(세대별 PCI 드라이버와 DMI 표)를 켜고 firmware를 WL처럼
initrd 꼬리에 붙인다. UCM(alsa-ucm-conf)이 필요한지, DMIC가 카드의 몇 번 장치로 오고 `default`가 그것을 고르게 할지가 이
milestone의 정할 것이다. QEMU에 길이 없어서 게이트는 심볼 · alias · firmware 목록이다.

M2와 M3을 나눈 이유. 둘 다 실기 드라이버지만 M2는 firmware가 없고 게이트에 QEMU 장치(`usb-audio`)가 하나 있으며, M3은
firmware · topology가 수십 MB 붙고 QEMU에 길이 없다. lead의 틀대로 한 milestone이면 하루에 안 끝나고, 실기에서 무엇이
안 될 때 원인이 firmware인지 코덱 quirk인지 갈리지 않는다.

## 위험

1. 커널 코드 배치가 TCG의 initramfs 풀기를 움직인다(lessons PD-3). M0은 운 좋게 0.7초 빨라졌고 `install` 부팅 7의 여유가 늘었다.
   M2 · M3이 켤 심볼이 많아서 반대 방향으로 움직일 수 있다 — 그때마다 부팅 7의 `init waited`를 잰다.
2. 실기의 HDA 코덱은 잭마다 입력 장치를 만든다(`SND_JACK_INPUT_DEV`, 끌 수 없다). `EV_SW`(헤드폰 · 마이크 꽂힘)만 내고, 헤드셋
   버튼이 있는 코덱은 `EV_KEY`의 `KEY_PLAYPAUSE` 같은 것을 낸다. `init`의 키보드 탐색과 terminal의 포인터 분류는 capability로
   고르므로 이것을 키보드나 포인터로 안 볼 것으로 보지만, QEMU의 코덱에는 잭 감지가 없어 게이트가 못 본다. 실기에서 키보드를
   못 찾거나 엉뚱한 장치를 열면 이것부터 본다.
3. M0만 들어간 실기는 조용하다. 커널이 소리를 꺼 둔 채 뜨고(결정 4), 많은 노트북의 스피커는 범용 코덱 파서로는 앰프(EAPD)가
   안 켜진다(M2). M0을 실기에서 확인하는 사람은 `amixer`로 켜고, 그래도 조용하면 M2를 기다린다는 것을 running-tars.md에 적는다.
4. 컨테이너의 QEMU가 `alsa` 오디오 모듈(`/usr/lib/aarch64-linux-gnu/qemu/audio-alsa.so`)을 계속 싣는다는 데 기댄다. Debian이
   그 모듈을 다른 패키지로 떼면 체인이 부팅에서 `audio: Unknown audio driver`로 빨개진다. 조용히 초록이 되지는 않는다.
5. 게이트의 판정 글자 일부가 alsa-utils의 출력 형식이다(`aplay -l`의 `card 0: Intel [HDA Intel], device 0: Generic Analog`,
   `speaker-test`의 ` 0 - Front Left`, `amixer`의 `Playback 0 [0%] [-74.00dB] [off]`). Debian이 alsa-utils를 올리면 함께 본다.

## 비목표

1. Bluetooth 오디오(이어폰 · 헤드셋). 블루투스 스택 자체가 없다.
2. PipeWire · PulseAudio · JACK, 앱 사이의 섞기 · 라우팅 정책. 섞기는 alsa-lib의 dmix까지다(결정 3).
3. 터미널이 소리를 내는 것(벨, `\a`). terminal은 소리 장치를 안 연다.
4. VD의 전사 파이프라인. 경계는 이렇다 — AU는 "`arecord`가 마이크의 바이트를 WAV로 쓰고 `aplay`가 WAV를 스피커로 낸다"까지이고,
   그 WAV로 무엇을 하는지(전사 API · 키 · 화면에 넣는 것)는 VD다.
5. 노트북의 볼륨 · 음소거 키(`KEY_VOLUMEUP` 등). 키 이벤트는 오지만 그것을 믹서에 잇는 것은 입력 쪽의 일이다. M1 뒤에 다시 본다.
6. HDMI · DisplayPort 오디오. HDA의 HDMI 코덱은 GPU 드라이버(i915 · amdgpu)와 짝으로 붙는데 TARS는 GPU 드라이버를 안 켠다(RM).
7. MIDI · 시퀀서 · OSS 에뮬레이션.
8. 코덱 절전(`SND_HDA_POWER_SAVE_DEFAULT`). 기본값 0(끔) 그대로다.

## 착수 전에 실측한 것

1 ~ 4는 lead(Fable)가 2026-10-05에 쟀고 그대로 인용한다. 5부터는 이 design을 쓰며 저장소 사본(`/tmp/run/au0/repo/`, HEAD
`83d282b`)과 컨테이너에서 쟀다. 측정 파일은 `/tmp/run/au0/meas/`에 있다.

1. (lead) 게스트 커널 `kernel/.config`가 `# CONFIG_SOUND is not set`이다. `CONFIG_PCI=y` · `CONFIG_USB=y` · `CONFIG_I2C=y`.
2. (lead) sysroot(`/usr/local/amd64-sysroot`)에 `arecord` · `aplay` · `amixer` · `libasound`가 없다. `libssl.so.3` ·
   `libgnutls.so.30`은 있다(curl이 데려왔다).
3. (lead) 컨테이너 QEMU 10.0.13의 사운드 장치는 `AC97` · `ES1370` · `hda-duplex` · `hda-micro` · `hda-output` · `ich9-intel-hda` ·
   `intel-hda` · `sb16` · `gus` · `usb-audio` · `virtio-sound-pci`이고, audiodev 백엔드는 `none` · `alsa` · `oss` · `wav`뿐이다.
4. (lead) 컨테이너에 `python3` · `rg`가 없고 `perl` 5.40이 있다. 게스트에 `curl`(TLS) · `jq` · `bash` · `fish` · `zsh`가 있다.
5. 패키지와 의존(trixie, alsa-utils 1.2.14-1, libasound2t64 1.2.14-1+deb13u1). `aplay` · `arecord` · `alsactl`의 NEEDED는
   `libasound.so.2` · `libc.so.6`, `amixer` · `speaker-test`는 여기에 `libm.so.6`, `alsamixer`는 `libformw` · `libmenuw` ·
   `libpanelw` · `libncursesw` · `libtinfo` · `libasound` · `libm` · `libc`다. `libasound.so.2`(1,178,192바이트)의 NEEDED는 `libm` ·
   `libc` · 로더다. 크기는 `aplay` 80,232 · `amixer` 59,784 · `alsamixer` 86,248 · `speaker-test` 39,288바이트이고 `arecord`는
   패키지 안에서 `aplay`로 가는 링크다. `/usr/share/alsa`는 파일 86개 182,416바이트(`alsa.conf` · `cards` · `ctl` · `init` ·
   `pcm`), `/usr/share/sounds/alsa`는 목소리 아홉 1,228,928바이트이고 그중 `Front_Left.wav` · `Front_Right.wav`가 289,118바이트다.
   alsa-utils의 Depends 중 `libatopology2t64` · `libfftw3-single3` · `libsamplerate0` · `kmod`는 우리가 싣는 넷이 안 부른다.
6. 기본 장치의 두 겹(결정 3). HEAD 설정(`# CONFIG_SYSVIPC is not set`)에 sound만 켠 커널과 `audio` 그룹을 넣은 initrd에서
   `aplay`가 `unable to create IPC semaphore … Function not implemented`였고, `SYSVIPC`를 켜고 그룹을 뺀 initrd에서
   `The field ipc_gid must be a valid group (create group audio) … Invalid argument`였다. 두 경우 다 `aplay -D hw:0,0`은 돌았다.
7. 카드가 올라온 직후의 믹서(결정 4). QEMU `hda-micro`에서 simple control은 `Master`(Playback 0~74)와 `Capture`(0~74) 둘이고,
   둘 다 `0 [0%] [-74.00dB] [off]`였다. 74가 0dB다. 이 상태로 `-D hw:0,0` 재생을 `wav` 백엔드로 받은 파일이 92,590샘플 전부
   0이었다. `amixer sset Master 0dB unmute` 뒤에는 값이 그대로 나왔다(실측 9).
8. `wav` 백엔드(`-audiodev wav,id=snd0,path=…,out.frequency=48000` + `hda-micro`). QEMU가 `audio: Could not create a backend for
   voice 'adc'`를 찍고, 게스트의 `arecord -D hw:0,0`이 `pcm_read:2272: read error: Input/output error`로 44바이트(헤더만)를 남겼다.
9. `alsa` 백엔드와 `file` 플러그인(결정 5의 (d)). `out.dev=tarstap` · `in.dev=tarsfeed`, 48kHz · 2채널 · s16, `try-poll=off`. 게스트
   `aplay`(기본 장치) 1초 사각파가 `tap.raw`에 (8000, 8000) · (-8000, -8000)으로 정확히 48,000프레임, 그 밖의 0이 아닌 프레임 0이었고,
   `arecord`(기본 장치) 2초가 96,000프레임 전부 (3000, -5000)이었다. `-D hw:0,0`도 같았다. 컨테이너의 libasound(arm64)는
   `libasound2t64` 1.2.14-1+deb13u1이고 qemu-system-x86이 이미 데려온 것이다.
10. M1을 위한 사실. 게스트에서 `alsactl -f /tmp/none.state init`이 `Found hardware: "HDA-Intel" "QEMU Generic" …`, `Hardware is
    initialized using a generic method`를 찍고 Master를 `54 [73%] [-20.00dB] [on]`, Capture를 `74 [100%] [0.00dB] [on]`으로 만들었다.
    그 앞에 `Unable to find the top-level configuration file '/usr/share/alsa/ucm2/ucm.conf'`와 `failed to import hw:0 use case
    configuration -2` 두 줄이 찍혔다. `alsactl store`의 상태 파일은 100줄이었다. alsa-utils v1.2.14의 `alsactl/daemon.c`를 읽었다
    — 카드 목록은 시작할 때와 SIGUSR1을 받을 때만 다시 훑고, SIGTERM · SIGINT는 저장 없이 끝내고, SIGUSR2가 저장하고 끝낸다.
    변경은 `period`초가 지나야 쓴다. Debian은 udev 규칙(`90-alsa-restore.rules`, 카드마다 `alsactl restore N`)과
    `alsa-restore.service`(부팅 `restore` · 종료 `store`) 또는 `alsa-state.service`(`rdaemon`)로 이것을 한다.
11. 커널(M0의 다섯을 `scripts/config -e`로 적고 `olddefconfig`로 되접은 판). bzImage 7,758,848 → 7,955,456바이트, 증분 빌드 125초,
    `.config` +147 −2줄. `olddefconfig`가 켠 것 중 `=y`는 `SYSVIPC_SYSCTL` · `IPC_NS` · `ACPI_NHLT` · `SND_TIMER` · `SND_PCM` ·
    `SND_JACK` · `SND_JACK_INPUT_DEV` · `SND_PCM_TIMER` · `SND_SUPPORT_OLD_API` · `SND_PROC_FS` · `SND_VERBOSE_PROCFS` ·
    `SND_CTL_FAST_LOOKUP` · `SND_VMASTER` · `SND_DMA_SGBUF` · `SND_DRIVERS` · `SND_PCI` · `SND_HDA` · `SND_HDA_CORE` ·
    `SND_INTEL_NHLT` · `SND_INTEL_DSP_CONFIG` · `SND_INTEL_SOUNDWIRE_ACPI` · `SND_USB` · `SND_X86` · `XARRAY_MULTI`다(`SND_USB` ·
    `SND_X86`은 메뉴이고 그 아래 드라이버는 안 켜졌다). render 체인과 같은 QEMU 호출(pc, 디스크 없음)로 세 번씩 띄운 `Run /init`이
    HEAD 3.73 · 3.75 · 3.75초, M0 3.03 · 3.04 · 3.05초였다. `inflate_fast`의 페이지 안 자리가 HEAD 0xec0, M0 0xb40이다. `install`
    체인 부팅 7의 `init waited`는 HEAD 1,100 · 1,200ms, M0 1,800 · 1,900ms였다(두 판씩, 한 판 103~108초).
12. initrd(firmware 꼬리 포함, gzip). HEAD 89,701,730 → M0 90,542,534바이트(+840,804). 전부 푼 크기 230,984,704 → 233,062,400바이트
    (+2,077,696). 게스트 도구 87 → 91.
13. 체인. `audio/check.sh` 네 판이 초록이었고 판마다 `tap: … tone=48000 left=53060 right=71059 other=0`, `cap: frames=96000
    match=96000`으로 같았다. `speaker-test -c 2 -t wav -l 1`은 기본 장치로 왼쪽 목소리 뒤 오른쪽 목소리를 냈다. regression의 값은
    M0 plan 확정 8에 있다.
14. 커널 소스(6.18.42)에서 읽은 것. `SND_JACK_INPUT_DEV`는 프롬프트가 없고 `default y if INPUT=y`다. `intel-dsp-config.c`의 기계 표는
    전부 `IS_ENABLED(CONFIG_SND_SOC_SOF_…)` 안에 있다. Realtek 코덱은 6.18에서 `SND_HDA_CODEC_REALTEK` 아래 계열 심볼 열둘로
    갈렸다(`ALC260` · `ALC262` · `ALC268` · `ALC269` 등).
15. 서비스 스크립트의 첫 줄은 `#!/usr/bin/bash`여야 한다. 게스트에 `/bin/bash`가 없어서 `#!/bin/bash`이면 `init`이
    `execve … failed (errno 2)`를 세 번 찍고 포기한다. `#!/bin/sh`(bash 링크)도 되지만 프로브는 bash의 기능을 쓴다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜, AU-M0~M3)`로 고친다. milestone이 줄거나 늘면 그 사실을 한 줄로.
- `CLAUDE.md`의 완료 표에 한 줄. 예: "노트북의 스피커 · 마이크 · 헤드폰 잭 · USB 헤드셋에 `aplay` · `arecord`가 닿는다 — 커널
  ALSA와 alsa-utils 그대로, 우리 코드는 부팅의 믹서와 게이트. 게이트는 QEMU HDA에 컨테이너 alsa-lib의 file 플러그인으로 샘플을
  값까지 본다 — 스무번째 체인 `audio/check.sh`".
- `docs/decisions/project_audio_devices.md`를 만들고 `MEMORY.md`에 한 줄. 담을 것 — 기본 장치의 두 겹(`SYSVIPC` · `audio` 그룹),
  커널이 소리를 꺼 둔 채 뜬다, QEMU `alsa` 백엔드 + `file` 플러그인이라는 게이트의 수법, 루프백을 안 쓴 이유, VD와의 경계.
- `docs/decisions/project_target_hardware.md`에 소리 한 줄(무엇이 켜졌고 무엇이 M2 · M3인가).
- `docs/guides/lessons.md`. 포트 절에 "audio는 monitor를 안 쓴다". 로그 문구 절에 `audio-probe:` 줄들과 커널의
  `snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic`. "서브프로젝트를 넘어 유효한 실측"에 QEMU 오디오의 수법(백엔드 ·
  `file` 플러그인의 `infile` · 48kHz 고정)과 서비스 스크립트의 `#!/usr/bin/bash`. 핵심 파일 절의 게이트에 `audio/check.sh`.
- `docs/guides/running-tars.md`에 소리 절. 사용자가 실기에서 볼 것.

  ```
  cat /proc/asound/cards               # 카드가 올라왔나
  aplay -l ; arecord -l                # 스피커 · 마이크 장치
  amixer sset Master unmute 80%        # M1 전에는 부팅마다(소리가 꺼진 채 뜬다)
  amixer sset Capture cap 80%
  speaker-test -c 2 -t wav -l 1        # 왼쪽 "Front Left", 오른쪽 "Front Right"
  arecord -d 3 -f cd /tmp/m.wav && aplay /tmp/m.wav   # 마이크 → 스피커
  alsamixer                            # 화면으로 볼륨 · 음소거(M 키)
  ```

  이어폰은 M2부터다. HDA 헤드폰 잭은 꽂으면 스피커가 꺼지고, USB 헤드셋은 카드 1로 온다(기본 카드를 고르는 법은 M2가 정한다).
- `HANDOFF.md`. VD를 열 사람에게 경계(비목표 4)와 `arecord -f S16_LE -r 16000 -c 1`이 기본 장치(`plug` → `dsnoop`)로 도는지는
  안 쟀다는 것을 넘긴다.

## 관련

- `docs/specs/2026-09-28-tars-wireless-design.md` — firmware를 initrd 꼬리에 붙이는 법(M3), 게이트 전용 장치를 다루는 법(hwsim)
- `docs/specs/2026-09-28-tars-usb-wireless-design.md` — QEMU에 없는 장치를 심볼 · modinfo alias · 등록 줄로 보는 법(M2 · M3)
- `docs/specs/2026-10-05-tars-pointer-devices-design.md` — 커널 심볼을 켠 뒤 `install` 부팅 7을 재는 이유(결정 9, 실측 PD-3)
- `docs/specs/2026-09-27-tars-boot-services-design.md` — `services.d`(게이트의 프로브가 들어가는 자리)
- `docs/specs/2026-09-27-tars-daemon-supervision-design.md` — 감독 목록에 데몬을 넣는 모양(M1의 후보 하나)
- `docs/specs/2026-09-27-tars-firewall-design.md` — `init`이 외부 도구를 `fork` · `execve` · `wait4`로 기다리는 모양(M1의 후보 하나)
- `docs/decisions/project_kernel_config.md` · `project_measuring_tool_cost.md` · `project_write_or_reuse.md` · `project_target_hardware.md` ·
  `project_pointer_devices.md` · `feedback_scripting_runtimes.md`
