# AU-M2 — 노트북의 코덱 드라이버와 USB 오디오, 기본 카드는 번호가 가장 큰 것

Date: 2026-10-06
Design: `docs/specs/2026-10-05-tars-audio-devices-design.md`
Status: 끝났다(2026-10-06). plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "AU-M2가 실측한 것"에 있다. 다음은 AU-M3(`-au-m3.md`).

## 누가 무엇을 하나

design 결정 6. Task 0~5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 이 milestone에서 정할 것(드라이버 목록 · 늦게 온 카드 · 기본 카드 · 게이트의 모양)은 이 plan이 사본에서
정했고(확정 1~4), 커널 설정은 정해진 `scripts/config` 한 줄로, `init`의 코드와 체인은 컴파일 · 호스트 검사 · 체인 · regression ·
mutation까지 사본에서 돌린 글자 그대로 넘긴다. 구현자에게 남는 판단이 없다 — 편집 열아홉을 글자 그대로 넣고, 커널을 정해진
명령으로 빌드하고, 체인 · regression · mutation을 정해진 순서로 돌린다. plan의 기대와 다른 값이 나오면 고치지 말고 보고한다.
Opus로 올릴 이유는 하나다 — 루트 게이트에서 이 plan이 못 돌린 체인이 빨개져 원인을 찾아야 할 때. 그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/au2/repo/`)에 먼저 넣어 호스트 검사 · 체인 · regression · mutation까지 돌렸고, 아래의
`old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/au2/render.py`). 기준은 AU-M1 commit(`9eee60f`)의 파일
(`/tmp/run/au2/base/`)이고 편집 뒤의 파일은 `/tmp/run/au2/new/`다. 구현자는 코드를 새로 짓지 않는다. 편집은 Edit 도구에 글자 그대로
넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고 — EL · CB · AU-M1의 구현자가 그렇게 했다), 각 Task 끝에서 `new/`와 `cmp`해 같은지
본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를
보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `kernel/.config` | 코덱 드라이버 일곱(Cirrus는 CS8409까지)과 USB 오디오를 켜고(`-e` 아홉), 그것이 끌고 오는 입력 쪽 둘을 끈다(`-d HID_APPLE` · `-d INPUT_LEDS`). `olddefconfig`로 되접는다(Task 1) | +133 −9 |
| `init/src/audio.zig` | 편집 하나 — 파일 끝에 "기본 카드" 절(순수 셋 `addNode` · `defaultsFor` · `render`, 시스템 콜 쪽 `follow`) | +172 |
| `init/src/audio_test.zig` | 편집 둘 — 머리 주석 · 순수 셋의 호스트 검사 | +50 |
| `init/src/main.zig` | 편집 하나 — 감독 루프 머리의 `audio.follow()` | +6 |
| `audio/probe.sh` | 편집 셋 — 머리 주석 · 셋째 갈래 `usb`를 고르는 줄 · 그 갈래(꽂기 → 볼륨 · 재생 · 녹음 → 뽑기 → 재생) | +49 −1 |
| `audio/check.sh` | 편집 열 — 머리 주석 · 검사 1의 코덱 · USB · 입력 쪽 음성 · 부팅 D의 디스크 · `.asoundrc`의 `tarsusb` · `start_guest usb` · 부팅 D와 검사 12~15 | +178 −5 |
| `check.sh` | 편집 둘 — AU 문단의 부팅 수 3 → 4와 포트 · `CHAINS`의 이름 `AU-M1` → `AU-M2` | +3 −2 |

합해서 7 files, +591 −17다. 새 파일은 없다. Dockerfile · `guest_tools.sh` · `make_initrd.sh` · `config.zig`(seed) · `power.zig`는 안
바뀐다 — 게스트에 더 싣는 것이 없고(USB 카드의 설정 `cards/USB-Audio.conf`는 M0이 `/usr/share/alsa`를 통째로 실을 때 이미 들어갔다),
`tars.conf`에 키가 없다(확정 4).

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/au2/impl/` 아래에 둔다. `/tmp/run/au2/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도
lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다. 이미지는 M0의
`tars-devcontainer` 그대로다. 이 milestone은 이미지를 안 굽는다.

## 이 milestone이 끝나면

- 노트북의 HDA 코덱이 전용 드라이버로 붙는다. Realtek(ALC2xx를 포함한 계열 열 전부) · Conexant · Senarytech · Cirrus(CS420x ·
  CS421x · CS8409) · Analog Devices · IDT/Sigmatel · VIA. 스피커 앰프(EAPD) · 헤드폰 잭의 auto-mute · 노트북별 핀 quirk는 이 드라이버들의
  일이다. 범용 파서만 있던 M1까지는 많은 노트북의 스피커가 조용했다(design 위험 3).
- USB 헤드셋 · 이어폰 동글 · USB 스피커가 카드로 붙는다(`snd-usb-audio`, USB Audio Class 1 · 2).
- 사람이 치는 `aplay x.wav` · `speaker-test` · `amixer`가 꽂은 USB로 간다. `init`이 `/dev/snd`를 1초마다 보고 `/etc/asound.conf`에
  기본 카드를 적는다 — 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것. 마이크 없는 USB 스피커를 꽂으면 재생은 USB로,
  `arecord`는 내장 마이크로 간다. 뽑으면 1초 안에 내장으로 돌아온다. `tars.conf`에 키는 없다.
- 부팅 뒤에 꽂은 USB 카드에는 `alsactl`을 안 부른다. 커널은 USB 카드를 끄지 않는다(장치가 가진 볼륨 그대로 켜져 온다 — 확정 3).
- `audio` 체인이 부팅 넷이 된다. 부팅 D가 monitor(포트 45491, 첫 사용)로 QEMU `usb-audio`를 꽂고 뽑아 소리가 어느 카드로
  갔는지를 샘플의 값으로 본다. 검사 1이 코덱 드라이버 · USB 오디오의 심볼과 modinfo alias를 보고, 입력 쪽 둘(`HID_APPLE` ·
  `INPUT_LEDS`)이 꺼졌는지 본다.

로그 줄(정본 — `init/src/audio.zig`가 찍고 `audio/check.sh`가 이 글자를 본다). 사본의 부팅 D에서 뽑았다.

```
# 부팅 A · B · C (HDA만) — 감독 루프의 첫 바퀴
tars-init: audio: default card is 0 for playback, 0 for capture

# 부팅 D — HDA로 떠서 USB 스피커를 꽂고 뽑는다
tars-init: audio: default card is 0 for playback, 0 for capture
audio-probe: default before plug [default "0"|default "0"|ctl.card 0]
audio-probe: plug now
usb 1-1: new full-speed USB device number 2 using xhci_hcd
tars-init: audio: default card is 1 for playback, 0 for capture
audio-probe: usb card [ 1 [Audio          ]: USB-Audio - QEMU USB Audio]
audio-probe: default after plug [default "1"|default "0"|ctl.card 1]
audio-probe: usb volume [  Front Right: Playback 256 [100%] [8.00dB] [on]]
audio-probe: plugged aplay exit 0 []
audio-probe: plugged arecord exit 0 []
audio-probe: unplug now
tars-init: audio: default card is 0 for playback, 0 for capture
audio-probe: default after unplug [default "0"|default "0"|ctl.card 0]
audio-probe: unplugged aplay exit 0 []
```

그 밖의 갈래(`audio.zig`가 정본). 소리 장치가 없는 기계(다른 열아홉 체인)는 `/dev/snd`에 `pcmC*`가 없으므로 한 줄도 안 찍고
파일도 안 쓴다.

```
tars-init: audio: no sound card left, removed /etc/asound.conf      카드가 다 빠졌을 때
tars-init: audio: cannot write /etc/asound.conf (errno <N>)
```

`/etc/asound.conf`의 글자(부팅 D에서 USB를 꽂은 뒤).

```
# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.
# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.
# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.
pcm.!default {
	type asym
	playback.pcm {
		@func concat
		strings [ "sysdefault:CARD=" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default "1" } ]
	}
	capture.pcm {
		@func concat
		strings [ "sysdefault:CARD=" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default "0" } ]
	}
}
defaults.ctl.card 1
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 커널 소스(6.18.42의 `sound/hda/codecs/*/Kconfig` · `sound/hda/common/bind.c` · `sound/usb/Kconfig` ·
`drivers/leds/Kconfig`)와 alsa-lib 1.2.14의 소스(`src/confmisc.c` · `src/conf/alsa.conf` · `pcm/default.conf` · `cards/USB-Audio.conf`,
`/tmp/run/au2/meas/src/`)를 읽어 정했고, 저장소 사본(`/tmp/run/au2/repo/`)과 M0 이미지(`tars-devcontainer`)로 쟀다. HEAD 쪽 대조는
같은 사본을 편집 전에 떠 둔 `/tmp/run/au2/head/`다. 측정 파일은 `/tmp/run/au2/meas/`(되접기 `kc_*.config` · `kfold.out` ·
`kbuild.out`, 측정 부팅 `exp/exp1_serial.log` · `exp/exp2.out`, 시간 `timing_head.log` · `timing_m2.log`, 체인 · regression 로그)에
있다. 저장소의 작업 트리는 이 plan 말고는 한 글자도 안 바뀌었다.

1. 커널 — 무엇을 켜고 무엇을 끄나.

   `scripts/config`로 적는 것은 열하나다. 전부 `=y`다(이 커널에는 모듈이 없다).

   ```
   -e SND_HDA_CODEC_REALTEK -e SND_HDA_CODEC_CONEXANT -e SND_HDA_CODEC_CIRRUS -e SND_HDA_CODEC_SENARYTECH
   -e SND_HDA_CODEC_ANALOG -e SND_HDA_CODEC_SIGMATEL -e SND_HDA_CODEC_VIA -e SND_HDA_CODEC_CS8409 -e SND_USB_AUDIO
   -d HID_APPLE -d INPUT_LEDS
   ```

   Realtek은 계열을 고를 수 없다. 6.18의 `SND_HDA_CODEC_ALC260` ~ `ALC882` 열은 프롬프트가 `if EXPERT`이고 `default y`다. 이 커널은
   `# CONFIG_EXPERT is not set`이라 메뉴(`SND_HDA_CODEC_REALTEK`)를 켜면 열이 다 켜지고, `-d SND_HDA_CODEC_ALC260`을 적어도
   `olddefconfig`가 되돌린다(사본에서 재 봤다 — `kc_try_alc260_off.config`). 노트북의 ALC2xx(ALC256 · ALC257 · ALC295 · ALC236 …)는
   `ALC269` 하나가 받는다(그 모듈의 alias 42개). `EXPERT`를 켜는 것은 커널 전체의 프롬프트를 바꾸는 일이라 안 한다. 크기로 봐도
   Realtek 열이 bzImage에 더하는 것이 73,728바이트다. Cirrus 메뉴는 CS420x · CS421x를 따라 켜고, CS8409(Dell · Apple의 HDA 다리 — CS42L42를 잇는다)는
   `default`가 없어 `-e`로 따로 켠다(lead의 결정, 2026-10-06). 그 하나가 bzImage에 더하는 것은 8,192바이트다.

   켜지 않는 코덱 — HDMI(design 비목표 6, GPU 드라이버가 없다), Creative CA0110 · CA0132(데스크톱 카드), C-Media(데스크톱),
   SI3054(모뎀). 그리고 `side-codecs`의 스피커 앰프(CS35L41 · CS35L56 · TAS2781)는 `SND_SOC`와 firmware가 있어야 붙는다 — 그런
   노트북(2022년 이후 ASUS · Lenovo · HP 일부)은 이 milestone 뒤에도 내장 스피커가 조용하고 헤드폰 잭은 된다. M3(SOF · ACP와 같은
   층)의 일이다. `SND_HDA_INPUT_BEEP` · `SND_HDA_PATCH_LOADER` · `SND_HDA_RECONFIG` · `SND_HDA_HWDEP`는 그대로 꺼져 있다 — 잭 감지와
   auto-mute는 코덱 드라이버 안의 일이라 더 켤 것이 없다.

   `-d` 둘의 이유. Realtek · Conexant · Senarytech · Sigmatel이 `SND_HDA_GENERIC_LEDS`(노트북의 음소거 LED)를 고르고, 그것이
   `SND_CTL_LED`를 거쳐 `NEW_LEDS` · `LEDS_TRIGGERS`를 `select`한다. 지금까지 `NEW_LEDS`가 꺼져 있어서 숨어 있던 심볼 일곱이 그러면
   기본값으로 켜진다. 그중 둘이 입력 쪽이다.

   | 심볼 | 기본값 | 어떻게 |
   |---|---|---|
   | `HID_APPLE` | `!EXPERT` = y | 끈다. Apple 키보드의 fn 키를 커널이 바꾼다 — `keyboard=apple`과 부딪칠 수 있다(lessons 이월 숙제의 `RTL8XXXU`와 같은 벽, UW design) |
   | `INPUT_LEDS` | `INPUT` = y | 끈다. 키보드 LED를 LED 클래스 장치로 내놓는 입력 핸들러다. 소리와 무관하고 입력 쪽을 안 건드린다 |
   | `MAC80211_LEDS` · `RFKILL_LEDS` · `IWLWIFI_LEDS` · `MT76_LEDS` · `RTW88_LEDS` | y | 그대로 둔다. 무선 드라이버의 LED 트리거이고 다섯 다 프롬프트가 없어(`MAC80211_LEDS`는 `IWLWIFI_LEDS`가 `select`한다) `-d`가 안 먹는다. 그래서 regression에 `wifi`가 들어간다(확정 11) |

   되접은 `.config`는 +133 −9줄이다. `=y`로 새로 서는 것은 35다 — 위 아홉과 Realtek 열 · `REALTEK_LIB` · `CS420X` · `CS421X` ·
   `SCODEC_COMPONENT`, `SND_HWDEP` · `SND_RAWMIDI`(USB 오디오가 `select`), `SND_CTL_LED` · `SND_HDA_GENERIC_LEDS` · `NEW_LEDS` ·
   `LEDS_CLASS` · `LEDS_TRIGGERS`, 무선 LED 다섯. `# … is not set`이 70줄 더해지고(LED 드라이버 메뉴가 펴진다) 지워지는 아홉 줄은 전부 `# … is not set`이다.

   크기(증분 빌드, `kbuild.out`).

   | 단계 | bzImage | 늘어난 것 | 빌드 |
   |---|---|---|---|
   | M1 | 7,955,456 | — | — |
   | + Realtek | 8,029,184 | +73,728 | 48초 |
   | + 나머지 코덱 여섯 | 8,057,856 | +28,672 | 18초 |
   | + USB 오디오 · `-d` 둘 | 8,205,312 | +147,456 | 18초 |
   | + CS8409(최종) | 8,213,504 | +8,192 | 18초 |

   합해서 +258,048바이트(3.2%)다. `size`로 본 덩어리는 Realtek 150,431 · IDT 39,419 · Conexant 12,427 · VIA 10,395 · Cirrus 9,468 ·
   Analog 7,482 · Senarytech 2,101 · USB 오디오 365,612 · LED 16,275바이트(text+data+bss, 압축 전)다. `inflate_fast`는
   `ffffffff8147ab40` → `ffffffff8147fb40`이고 페이지 안 자리 `0xb40`이 그대로다(lessons PD-3, 확정 9).

2. USB 오디오 — 게이트에서 무엇을 보나.

   QEMU의 `usb-audio`는 48kHz 스테레오 16비트 재생 하나뿐인 USB Audio Class 1 장치다. q35에 `qemu-xhci`를 붙이고 그 위에 꽂는다
   (`usb-ehci`에 꽂으면 QEMU가 바로 끝났다 — 이 장치는 full-speed다). 커널은 그것을 카드 1(`id` `Audio`, `/proc/asound/cards`의
   ` 1 [Audio          ]: USB-Audio - QEMU USB Audio`)로 올리고 노드 둘(`controlC1` · `pcmC1D0p`)을 만든다. 스피커 쪽 샘플은 HDA와
   같은 수법으로 받는다 — 둘째 `-audiodev alsa`(`out.dev=tarsusb`)와 `.asoundrc`의 `file` 플러그인 하나.

   값까지 같으려면 볼륨이 100%여야 한다. QEMU의 `usb-audio`는 자기 볼륨을 샘플에 곱한다(0~255). 꽂힌 직후의 믹서는
   `'Audio Output Volume Control'` `240 [94%] [-0.50dB] [on]`이고 그대로 재생하면 8000이 7529, -8000이 -7530이 된다(240/255).
   `amixer`로 241(0.03dB)로 올려도 같았고, 100%(256, `[8.00dB]`)에서 47,424 ~ 47,952프레임이 값까지 같았다(세 판, other 0). 그래서
   부팅 D의 프로브가 "사람이 꽂고 볼륨을 올린다"를 `amixer -q sset 'Audio Output Volume Control' 100%`로 친다 — `-c` 없이. 그 값이
   USB 카드에 닿으면 믹서의 기본(`defaults.ctl.card`)도 따라간 것이다(검사 13의 첫째).

   부팅 때 꽂아 둔 판은 게이트에 안 쓴다. `qemu-xhci`에 `-device usb-audio`를 붙인 채 열 번 띄웠더니 여섯 번만 됐다. 한 번은 커널이
   장치를 아예 못 봤고(`usb 1-1: new full-speed …` 줄이 15초까지 없었다), 세 번은 QEMU가 시리얼에 한 줄도 안 내고 60초를 섰다(SIGTERM으로
   끝났고 stderr에 다른 말이 없었다, `exp/exp3_qemu_*.log`). `device_add`로 꽂은 판은 측정과 체인을 합해 스무 번 남짓 다 0.2초 안에
   열거됐다. 부팅 때 있는
   카드와 부팅 뒤에 꽂힌 카드는 `init`에게 같은 길이다(`/dev/snd`의 이름이 늘었다) — 다른 것은 M1의 일꾼이 그 카드를 `alsactl init`에
   함께 넣느냐뿐이고, 그것은 사본에서 한 번 봤다(`exp1`의 첫 판, `Found hardware: "USB-Audio" "USB Mixer" …`, 볼륨은 240 그대로).

3. 늦게 온 카드의 믹서 — `alsactl`을 안 부른다.

   design 결정 4의 셋째와 M1 plan 확정 1의 셋째가 넘긴 질문이다. 재 보니 USB 카드는 꺼진 채 오지 않는다. 커널의 `snd-usb-audio`는
   장치에게 지금 볼륨을 물어 그대로 내놓는다 — QEMU 장치는 꽂을 때마다 `240 [-0.50dB] [on]`이었다. HDA가 꺼진 채 뜨는 것은 커널의
   HDA 드라이버가 가상 Master를 0에 두기 때문이고(design 실측 7) USB 쪽에는 그런 자리가 없다. 실제 USB 헤드셋도 장치가 기억하는
   볼륨으로 온다. 그래서 design이 적은 "부팅 뒤에 꽂은 카드는 꺼진 채다"는 HDA의 사실을 USB에 옮긴 것이었다 — 아래 "design에 덧붙일
   것" 2.

   `alsactl -U init 1`은 그 카드에 범용 규칙을 돌리고 99로 끝나며 볼륨을 안 바꿨다(240 그대로). `alsactl -U -f <없는 파일> restore 1`도
   99였다(파일이 없으면 init을 거친다). 없는 카드를 주면(`restore 5`) 2로 끝난다(`Cannot find soundcard '5'`). 꽂을 때마다 `restore N`을
   부르면 "그 헤드셋의 지난 볼륨"이 돌아오지만, 그것은 사람이 그 카드를 꽂은 채 꺼야 파일에 남고(M1의 store는 끄는 순간 있는 카드만
   적는다), 부르려면 감독 루프가 일꾼을 하나 더 거둬야 한다. 지금 얻는 것이 작아서 안 한다 — 비목표 하나로 남긴다.

4. 기본 카드 — `init`의 감독 루프가 `/dev/snd`를 1초마다 보고 `/etc/asound.conf`를 쓴다.

   libasound의 `default`는 `defaults.pcm.card`(기본 0)이고, 그것을 덮는 자리는 env(`ALSA_CARD`)와 설정 파일(`/etc/asound.conf` ·
   `~/.asoundrc`) 둘뿐이다. 프로그램이 장치를 열 때마다 설정 파일을 새로 읽으므로 파일을 고쳐 쓰면 다음 `aplay`부터 따라간다.

   | 후보 | 왜 아닌가 |
   |---|---|
   | (a) 감독 루프의 1초 바퀴에 `/dev/snd`를 읽고, 바뀌었으면 파일을 쓴다 | 고른 것 |
   | (b) alsa-lib 설정만으로 "나중 카드"를 고른다 | 안 된다. `confmisc.c`의 함수(`getenv` · `refer` · `card_inum` · `card_driver` · `pcm_args_by_class` …)에 "있는 카드 중 가장 큰 번호"나 "없으면 다른 카드" 같은 것이 없다. `pcm_args_by_class`는 첫 번째를 준다 |
   | (c) `tars.conf`의 `audio_card=` | 꽂을 때마다 사람이 고쳐야 한다. 카드 번호는 꽂는 순서로 바뀐다. seed가 한 줄 늘어 `config` 체인 25번째 줄 검사를 함께 봐야 한다(lessons 이월 숙제) |
   | (d) `ALSA_CARD` env | 프로세스가 태어날 때 정해진다. 이미 떠 있는 셸에서 꽂은 헤드셋을 못 따라간다 |
   | (e) 커널 인자(`snd_usb_audio.index=0`)로 USB가 0번을 잡게 | 뽑으면 0번이 사라져 `default`가 아무것도 못 연다 |
   | (f) netlink uevent 소켓(PD의 terminal과 같은 것)을 `init`의 poll에 하나 더, 또는 그것을 듣는 일꾼 | 된다. 그러나 감독 루프는 이미 1초마다 깨고, 카드가 오고 가는 일에 1초는 사람에게 안 보인다. 소켓 · 파싱 · 일꾼의 수명이 다 없어도 같은 결과다 |
   | (g) 커널의 uevent helper(`CONFIG_UEVENT_HELPER`)로 스크립트를 부른다 | 커널 설정이 하나 더 들고, uevent마다(USB 하나 꽂는 데 열 남짓) 셸이 하나씩 뜬다 |

   (a)의 비용은 바퀴마다 `open` · `getdents64` · `close` 셋이다. 쓰기는 바뀌었을 때만 하고 로그도 그때만 한 줄이다. 소리 장치가 없는
   기계(게이트의 다른 열아홉 체인)는 이름이 하나도 안 걸리므로 한 번도 안 쓰고 한 줄도 안 찍는다 — "처음 기억"이 "카드 없음"이라서다.
   쓰기는 `/etc/asound.conf.tars`에 쓰고 `rename`한다(반쯤 쓴 파일을 `aplay`가 읽지 않게). `/etc`는 initramfs의 rootfs라 쓸 수 있다.

   규칙은 "재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것"이다.
   - 번호가 큰 것. 내장 HDA는 부팅 때 PCI probe에서 0번을 잡고, USB 카드는 열거가 끝나야 생기므로 그 뒤 번호를 받는다. 그래서
     "USB가 꽂혀 있으면 USB"가 된다. 둘을 꽂았다 하나를 뽑고 다른 것을 꽂으면 빈 번호를 다시 쓰므로 "가장 나중"과 "가장 큰"이 어긋날 수
     있다 — 상태가 없는 규칙을 고르고 그 경우를 위험으로 둔다.
   - 재생과 녹음을 따로. 마이크 없는 USB 스피커 · DAC를 꽂아도 녹음은 내장 마이크에 남는다. 한 번호로 묶으면 그 카드에 녹음 장치가
     없어 `arecord`가 죽는다 — 부팅 D가 바로 그 모양이다(mutation 3).
   - 장치 0. `sysdefault:CARD=N`(그 카드의 `default`)은 장치 0을 연다. 그리고 HDMI 코덱만 가진 HDA 카드(AMD 노트북의 GPU 쪽 컨트롤러)는
     HDMI 드라이버가 없으면 범용 파서가 받는데(`bind.c`의 `codec_bind_generic`), 디지털 출력이라 장치 1로 나온다 — 소리가 안 나는 그
     카드가 기본이 되지 않는다. QEMU에 그런 카드가 없어 게이트는 호스트 검사(`pcmC2D1p`를 안 센다)로만 본다.

   파일의 모양. `pcm.!default`를 `asym`으로 덮고 두 방향에 `sysdefault:CARD=N`을 단다. N은 글자로 박지 않고 `getenv`의 기본값
   자리에 둔다(아래 env 문단). `sysdefault`는 alsa.conf가 카드의 원래
   `default`(HDA는 `plug` → `softvol` → `dmix` · `dsnoop`, USB는 `plug` → `dmix`)에 붙여 둔 이름이라, 덮은 뒤에도 섞기 · 형식 변환이
   M0 · M1과 같다 — 부팅 A · B의 사각파 · 녹음 판정이 이 파일을 지나서도 그대로 초록이다(확정 7). 믹서의 기본(`defaults.ctl.card`)은
   재생 쪽 카드다 — 사람이 볼륨을 만지는 것은 소리가 나는 카드다. 그래서 USB를 꽂은 동안 `amixer sset Master …`는 USB 카드에 `Master`가
   없어 실패한다(`amixer: Unable to find simple control 'Master',0` — 사본에서 봤다, `-c 0`을 주면 된다).

   env. alsa-lib의 원래 `default`(`pcm/default.conf`)는 카드를 고르기 전에 `ALSA_PCM_CARD` · `ALSA_CARD`를 본다. 첫 판은 파일에
   `"sysdefault:CARD=1"`을 글자로 박았는데, 그러면 `pcm.!default`를 덮은 순간 그 길이 사라져 `ALSA_CARD=0 aplay`가 USB로 갔다(사본에서
   쟀다 — HDA 쪽 0프레임, USB 쪽 48,000). 믹서 쪽은 `ctl.!default`를 안 덮으므로 같은 env가 먹어서(`ALSA_CARD=0 amixer`는 카드 0)
   둘이 엇갈렸다. 그래서 두 방향을 `@func concat` + `@func getenv … default "N"`으로 쓴다 — env가 있으면 그것, 없으면 init이 고른 카드.
   고친 판에서 `aplay`는 USB로(48,000), `ALSA_CARD=0 aplay`는 HDA로(48,000), `arecord`는 HDA로 갔고, `ALSA_CARD=1 arecord`는
   `audio open error: No such file or directory`로 끝났다(env는 두 방향 다 그 카드라 녹음 장치 없는 USB를 연다 — Debian과 같은 뜻).
   두 판씩 쟀다(`exp/exp3c.out`). `tars.conf` 키는 없다. 사람이 다른 카드를 원하면 `ALSA_CARD=N`이나 `aplay -D sysdefault:CARD=N`이다.

5. 코드의 모양. `audio.zig` 끝에 절 하나를 붙인다. 위 절반이 순수 셋(`addNode` — `/dev/snd`의 이름 하나를 재생 · 녹음 비트 집합에
   더한다, `defaultsFor` — 집합에서 가장 큰 번호, `render` — 파일의 글자)이고 아래가 시스템 콜(`scanCards` · `writeConf` · `follow`)이다.
   M1의 가름(`clock.zig`와 같은)을 그대로 따른다. PID 1의 기억은 전역 하나(`defaults_now`)다. `main.zig`에는 감독 루프 머리 —
   `power.take()` 바로 뒤, 아이들을 띄우기 전 — 에 `audio.follow()` 한 줄이다. 그 자리라서 첫 바퀴에 파일이 서비스 · 콘솔 셸보다
   먼저 선다(측정 부팅 `exp/exp1_serial.log`에서 `default card is 0 …`이 `started console shell` · `started service probe`보다 앞이었고, USB를 꽂아 둔 채 뜬 `exp/exp2_xhci.*.log` 셋에서는 첫 줄부터 `default card is 1 for playback, 0 for capture`였다).

   크기. `init`이 3,776,512 → 3,817,752바이트(+41,240), initrd가 90,604,814 → 90,620,022바이트(+15,208, gzip)다.

6. 호스트 검사. `audio_test`가 순수 셋을 본다 — HDA에 USB 스피커가 꽂힌 실제 이름 일곱(`controlC0` · `controlC1` · `pcmC0D0c` ·
   `pcmC0D0p` · `pcmC1D0p` · `timer` · `seq`)이 재생 `0b11` · 녹음 `0b01`이 되는 것, 장치 0이 아니거나 모양이 다른 이름 아홉(`pcmC2D1p` ·
   `pcmC2D3p` · `pcmC32D0p` · `pcmCxD0p` …)을 안 세는 것, 가장 큰 번호 넷(스피커 1/0 · 헤드셋 2/2 · 없음 · 31), 파일의 글자 셋(따로 ·
   녹음만 · 없음 — `getenv`의 기본값 자리에 번호가 들어간다)을 손으로 적은 글자와 비교. 사본에서 `zig build test`가 exit 0이고 열두 검사가 전부 돌았다.

7. 체인. 부팅 넷, 검사 열다섯.

   | 검사 | 부팅 | 본다 | 사본의 값 |
   |---|---|---|---|
   | 1 | 없음 | M1 그대로에 더해 코덱 드라이버 · USB 오디오의 심볼 열하나(`SND_HDA_CODEC_REALTEK` · `ALC269` · `CONEXANT` · `SENARYTECH` · `CIRRUS` · `CS420X` · `CS8409` · `ANALOG` · `SIGMATEL` · `VIA` · `SND_USB_AUDIO`), `HID_APPLE` · `INPUT_LEDS`가 `=y`가 아님, modinfo alias 아홉(드라이버마다 하나 — ALC256 `10EC0256` · CX11880 `14F11F86` · SN6186 `1FA86186` · CS4208 `10134208` · CS8409 `10138409` · AD1984 `11D41984` · 92HD99BXX `111D76E5` · VT1818S `11060440` · USB Audio Class `ic01isc01`) | 초록 |
   | 2 ~ 11 | A · B · C | M1 그대로. 이제 `aplay` · `arecord`가 `init`이 쓴 `/etc/asound.conf`(0/0)를 지난다 | `tone=48000 … other=0` · `match=96000` |
   | 12 | D | `usbcore: registered new interface driver snd-usb-audio` · 카드 1이 `USB-Audio` · 꽂기 전 파일 `[default "0"\|default "0"\|ctl.card 0]` · `default card is 1 for playback, 0 for capture` · 꽂은 뒤 파일 `[default "1"\|default "0"\|ctl.card 1]` | 초록 |
   | 13 | D | `-c` 없는 `amixer`가 USB 볼륨을 256으로 · `plugged aplay exit 0` · USB 쪽 사각파 40,000 이상 other 0 · HDA 쪽 사각파 0 | `usb tap: … tone=48000 … other=0` · `hda tap: frames=0` |
   | 14 | D | `plugged arecord exit 0` · 끈 뒤 디스크의 `cap.wav`가 48,000프레임 전부 (3000, -5000) — 녹음은 HDA에 남았다 | `frames=48000 match=48000` |
   | 15 | D | `default card is 0 for playback, 0 for capture`가 두 번(부팅 · 뽑은 뒤) · 뽑은 뒤 파일 `[default "0"\|default "0"\|ctl.card 0]` · `unplugged aplay exit 0` · HDA 쪽 사각파 40,000 이상 other 0 | `hda tap after unplug: … tone=47726 ~ 48000 … other=0` |

   부팅 D는 자기 디스크(`out/audio-usb.img`, 같은 씨앗에 표지 파일 `audio/usb`)로 뜬다. 프로브가 그 표지를 보고 셋째 갈래 `usb`로 가고,
   `plug now` · `unplug now`를 찍으면 체인이 monitor(45491)로 `device_add usb-audio,id=usbspk,audiodev=snd1,bus=xhci.0` ·
   `device_del usbspk`를 친다. 체인은 monitor에 `plug now`를 본 뒤에 붙는다 — 그때는 QEMU가 포트를 연 지 오래라 `Connection refused`가
   로그에 안 남는다. 프로브는 `/etc/asound.conf`의 `defaults.ctl.card N` 줄이 기다리는 카드로 바뀔 때까지 10초를 보고(`wait_conf`), 사람이 치는 그대로 `amixer` ·
   `aplay` · `arecord`를 `-c` · `-D` 없이 친다. 프로브는 `usb` 갈래에서 전원을 안 끈다(체인이 QEMU를 죽인다).

8. 시간. 캐시를 지운 첫 판이 1분 0초(커널은 이미 빌드된 것 · init · terminal 빌드 포함, 커널까지 증분이면 2분 1초), 데운 판이 40 · 41초였다(M1의 29초에 부팅 D 12초 남짓).
   루트 게이트는 이 체인을 두 번 돌리므로 M1의 게이트에 25초 안팎을 더한 것으로 본다. 커널 증분 빌드는 구현자의 작업 트리에서
   1분 30초 안팎이다(세 단계 합 84초, 한 번에 하면 그보다 짧다).

9. 커널 코드 배치(lessons PD-3, design 위험 1). HEAD(M1)와 M2를 같은 컨테이너에서 나란히 쟀다(`/tmp/run/au0/meas/timing.sh` — render
   체인과 같은 QEMU 호출 셋, `install` 체인 둘).

   | | bzImage | `inflate_fast` | `Run /init` 세 판 | `install` 부팅 7의 `init waited` |
   |---|---|---|---|---|
   | HEAD(M1) | 7,955,456 | `ffffffff8147ab40` | 3.09 · 3.05 · 3.02초 | 1,800 · 1,900ms |
   | M2 | 8,213,504 | `ffffffff8147fb40` | 3.04 · 3.04 · 3.03초 | 1,800 · 1,800ms |

   커널이 258KB 커졌지만 `inflate_fast`가 페이지 안 같은 자리(`0xb40`)에 떨어져 풀기가 안 늦었다. 다음 커널 변경이 이것을 다시
   움직일 수 있다.

10. mutation. 일곱 가지를 열세 판(대조군 하나 포함)으로 체인에서, 둘을 호스트 검사에서 돌렸다(`/tmp/run/au2/make_mut.py` · `run_mut.sh`,
    로그는 `/tmp/run/au2/mut/`). 앞 검사가 먼저 잡는 것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다(lessons
    "mutation이 겨냥한 검사에 걸릴 것이라고 믿기"). 커널 셋은 `.config` 사본을 덮고 `build.sh`가 다시 빌드한다.

    | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
    |---|---|---|---|---|---|
    | (대조군) | `m0` | 없음 | — | `AU check PASS` | 61초 |
    | 1 감독 루프의 `audio.follow()` 빼기 | `m1` | `main_m1.zig` | 검사 12(파일이 아예 없다) | `FAIL: before the plug /etc/asound.conf did not point both ways at card 0` | 79초 |
    | | `m1_play` | + `check_no12.sh` | 검사 13의 첫째(`-c` 없는 `amixer`가 카드 0으로 갔다) | `FAIL: amixer without -c did not reach the USB speaker's volume` | 80초 |
    | | `m1_tap` | + `check_no12vol.sh` | 검사 13(사각파가 HDA로 갔다) | `FAIL: the square wave did not reach the USB speaker sample for sample (frames=0 tone=0 …)` | 80초 |
    | 2 가장 작은 번호(`@ctz`) | `m2` | `audio_m2.zig` | 검사 12 | `FAIL: init did not move the default playback card to the plugged USB speaker` | 68초 |
    | | `m2_play` | + `check_no12.sh` | 검사 13의 첫째 | `FAIL: amixer without -c did not reach the USB speaker's volume` | 68초 |
    | 3 녹음이 재생 카드를 따라간다 | `m3` | `audio_m3.zig` | 검사 12(`1 for playback, 1 for capture`) | `FAIL: init did not move the default playback card to the plugged USB speaker` | 56초 |
    | | `m3_rec` | + `check_no12.sh` | 검사 14(녹음 장치 없는 USB를 연다) | `FAIL: arecord through the default device failed with the USB speaker in` | 57초 |
    | 4 기본이 더 낮은 번호로 안 내려간다 | `m4` | `audio_m4.zig` | 검사 15 | `FAIL: init did not move the default back to card 0 after the USB speaker went` | 69초 |
    | K1 `SND_USB_AUDIO` 끄기 | `k1` | `config_k1` | 검사 1 | `FAIL: CONFIG_SND_USB_AUDIO is not =y in kernel/.config` | 43초 |
    | | `k1_boot` | + `check_no1usb.sh` | 검사 12(커널이 드라이버를 안 올렸다) | `FAIL: usbcore never registered snd-usb-audio` | 68초 |
    | K2 `HID_APPLE` 켜기(`-d`를 빠뜨린 판) | `k2` | `config_k2` | 검사 1의 음성 | `FAIL: CONFIG_HID_APPLE came on with the LED class; the sound drivers must not touch input` | 43초 |
    | K3 Realtek 끄기 | `k3` | `config_k3` | 검사 1 | `FAIL: CONFIG_SND_HDA_CODEC_REALTEK is not =y in kernel/.config` | 43초 |

    호스트 검사 mutation 둘(`audio.zig`를 사본으로 바꿔 `zig build test`).

    | mutation | `FAIL` 줄 |
    |---|---|
    | 2(`audio_m2.zig`) | `FAIL: HDA plus a USB speaker picks playback 0 capture 0, want 1 and 0` |
    | 3(`audio_m3.zig`) | `FAIL: HDA plus a USB speaker picks playback 1 capture 1, want 1 and 0` |

    읽을 것 둘.
    - mutation 4는 호스트 검사가 못 잡는다 — `follow`의 "지난번과 다를 때만"은 시스템 콜 쪽이다. 체인의 검사 15만 본다.
    - 커널 판(`k*`)은 `kernel/build`를 다른 설정으로 빌드해 둔다. 되돌림(5-3)의 체인이 지금 `.config`로 다시 빌드하고 `inflate_fast`가
      `ffffffff8147fb40`로 돌아온 것을 봤다(77초). CS8409를 더한 뒤 K3만 다시 돌렸고 같은 줄로 빨갰다(43초), 되돌림은 59초였다.

11. regression. 커널(코덱 · USB · LED)과 `init`의 감독 루프가 바뀌므로 여덟을 사본에서 돌렸다.

    | 체인 | 시간 | 왜 돌렸나 |
    |---|---|---|
    | `install` | 106초 | 커널이 바뀌면 부팅 7의 창이 움직인다(PD-3). `init waited 1800ms for the late USB disk` — HEAD와 같다 |
    | `tools` | 65초 | initrd의 `init`이 커졌다. `the initrd carries the four bones and all 92 tools the list names` |
    | `boot` | 24초 | limine이 BIOS로 bzImage · initrd를 읽는다. 둘 다 커졌다 |
    | `machine` | 18초 | q35 · OVMF · simpledrm. 새 커널이 실기의 길에서 뜨는가 |
    | `wifi` | 96초 | `NEW_LEDS`가 무선 드라이버 다섯의 LED 트리거를 켰다(확정 1). hwsim의 연결 · 늦은 인터페이스 · usbcore 등록 열하나가 그대로다 |
    | `power` | 49초 | 감독 루프 머리에 `audio.follow()`가 들어갔다. 끄는 길과 되살리는 길이 그대로다 |
    | `service` | 70초 | 감독 루프 · `tars-service`가 그대로다 |
    | `pointer` | 74초 | USB 핫플러그(같은 xHCI · `device_add`)와 입력 쪽. `HID_APPLE` · `INPUT_LEDS`가 꺼진 채라 `pointer> open`의 셈이 그대로다 |

    여덟 다 exit 0, 합해서 8분 24초다. 파일의 글자를 `getenv`로 바꾸기 전(확정 4의 env 문단)에도 한 번 돌아 여덟 다 초록이었다(8분 35초).

12. 낡은 산출물. 이 milestone은 Zig 코드와 커널 설정을 고친다. 아래 명령은 `init`의 캐시 삭제를 같은 `docker run` 안에 둔다
    (`project_zig_out_staleness`). 커널은 `build.sh`의 sha256 스탬프가 `.config`의 변화를 보고 다시 빌드한다.

13. 앵커. 편집 열아홉의 `old_string`이 M1 commit의 파일에 정확히 한 번씩 있고(`python3 /tmp/run/au2/anchors.py pre "$PWD"` →
    `pre: 19 edits, 0 bad`), `new_string`이 사본에 정확히 한 번씩 있다(`post: 19 edits, 0 bad`). 진입 검사 셋도 사본의
    `audio/check.sh`에서 `ENTRY-OK`였다. main 작업 트리의 여섯 파일과 `kernel/.config`가 `/tmp/run/au2/base/`와 바이트까지 같다(lead의
    M1 commit `9eee60f` 뒤에 대조).

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

   기대: 맨 위 commit이 `9eee60f AU-M1: Boot turns the mixer on …`이거나 그 위에 lead의 문서 commit이 있다. `git status`는 이 plan이
   commit 전이면 그것 하나이고, lead가 고치는 중일 수 있는 design · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/`가 더 있을 수 있다.
   그 밖의 소스 파일이 `M`이면 멈추고 보고한다.

3. 편집의 앵커와 기준 파일을 본다(확정 13).

   ```bash
   python3 /tmp/run/au2/anchors.py pre "$PWD"
   for f in kernel/.config init/src/audio.zig init/src/audio_test.zig init/src/main.zig audio/check.sh audio/probe.sh check.sh; do
     cmp $f /tmp/run/au2/base/$f && echo "BASE $f"; done
   ```

   기대: `pre: 19 edits, 0 bad`와 `BASE` 일곱. 하나라도 다르면 그 파일을 보고하고 멈춘다 — 앵커를 다시 뽑아야 한다.

## Task 1: `kernel/.config` — 코덱 드라이버 · USB 오디오, 입력 쪽 둘은 끈 채

확정 1. M0 plan Task 1과 같은 모양이다 — 적고, 빌드하고(`build.sh`가 `olddefconfig`를 친다), 되접은 것을 다시 넣고, 한 번 더
빌드해 고정점인지 본다. 증분이라 2분 안팎이다.

```bash
mkdir -p /tmp/run/au2/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
    kernel/src/linux-6.18.42/scripts/config --file kernel/.config \
      -e SND_HDA_CODEC_REALTEK -e SND_HDA_CODEC_CONEXANT -e SND_HDA_CODEC_CIRRUS -e SND_HDA_CODEC_SENARYTECH \
      -e SND_HDA_CODEC_ANALOG -e SND_HDA_CODEC_SIGMATEL -e SND_HDA_CODEC_VIA -e SND_HDA_CODEC_CS8409 -e SND_USB_AUDIO \
      -d HID_APPLE -d INPUT_LEDS
    (cd kernel && ./build.sh > /tmp/k1.log 2>&1); echo "build 1 exit=$?"
    cp kernel/build/.config kernel/.config
    (cd kernel && ./build.sh > /tmp/k2.log 2>&1); echo "build 2 exit=$?"
    diff kernel/.config kernel/build/.config && echo FOLDED
    stat -c "%s bzImage" kernel/build/arch/x86/boot/bzImage
    grep " inflate_fast$" kernel/build/System.map' ; } 2>&1 | tail -8
rmdir /tmp/run/docker.lock
```

기대: `build 1 exit=0` · `build 2 exit=0` · `FOLDED` · `8213504 bzImage` · `ffffffff8147fb40 T inflate_fast`.

```bash
cmp kernel/.config /tmp/run/au2/new/kernel/.config && echo SAME-config
git diff --stat kernel/.config
git diff kernel/.config | rg '^[-+]CONFIG' | rg -v 'is not set'
```

기대: `SAME-config`, `+133 −9`, 그리고 `+CONFIG_…=y` 35줄(확정 1)과 `-` 줄 없음(지워지는 아홉 줄은 전부 `# … is not set`이다).
`HID_APPLE` · `INPUT_LEDS`가 `=y`로 보이면 `-d`가 빠진 것이다 — 멈추고 보고한다.

## Task 2: `init` — 기본 카드

확정 4 · 5 · 6. `audio.zig`의 끝에 절 하나, 그 호스트 검사, 감독 루프의 한 줄이다.

### 2-1. `init/src/audio.zig` — 편집 하나

E1 — `old_string`(기준 파일 280줄부터):

```zig
        .killed => |sig| std.debug.print("tars-init: audio: alsactl store was killed (signal {d})\n", .{sig}),
    }
}
```

`new_string`:

```zig
        .killed => |sig| std.debug.print("tars-init: audio: alsactl store was killed (signal {d})\n", .{sig}),
    }
}

// ── AU-M2. 기본 카드 ─────────────────────────────────────────────────────
//
// libasound의 `default`는 카드 0이다. 내장 HDA가 부팅 때 0번을 잡고 USB 헤드셋은 그
// 뒤 번호로 오므로, 아무것도 안 하면 사람이 치는 `aplay x.wav`가 헤드셋이 아니라
// 내장 스피커로 간다. 그래서 PID 1이 /dev/snd의 이름을 보고 /etc/asound.conf를
// 쓴다 — 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.
//
// 둘을 따로 고르는 이유. 마이크 없는 USB 스피커 · DAC가 꽂혀도 녹음은 내장 마이크에
// 남아야 한다. 한 번호로 묶으면 그 카드에 녹음 장치가 없어 `arecord`가 죽는다.
// 장치 0만 보는 이유. HDMI 코덱만 가진 카드(AMD 노트북의 GPU 쪽 HDA)는 범용 파서가
// 장치 1(디지털)로만 내놓는다 — 소리가 안 나는 그 카드가 기본이 되지 않는다.
//
// 듣지 않고 본다. 감독 루프는 이미 1초마다 깨므로, 깰 때마다 이름을 읽고 지난번과
// 다를 때만 파일을 쓴다. uevent 소켓도 일꾼도 없다(AU-M2 plan 확정 4).

pub const ASOUND_CONF_PATH: [:0]const u8 = "/etc/asound.conf";
/// 다 쓴 뒤 rename한다. 반쯤 쓴 파일을 aplay가 읽지 않게.
const ASOUND_CONF_TMP: [:0]const u8 = "/etc/asound.conf.tars";
const SND_DIR: [:0]const u8 = "/dev/snd";

/// 카드 번호의 상한. 커널의 SNDRV_CARDS(`CONFIG_SND_MAX_CARDS`의 기본 32)와 같다.
pub const MAX_CARDS = 32;

/// 장치 0에 재생 · 녹음이 있는 카드의 집합. 비트 하나가 카드 하나다.
pub const Cards = struct {
    playback: u32 = 0,
    capture: u32 = 0,
};

/// /dev/snd의 이름 하나를 `cards`에 더한다. `pcmC<카드>D0p` · `pcmC<카드>D0c`만
/// 세고 나머지(control · timer · 장치 1 이상)는 버린다. 순수 함수다.
pub fn addNode(cards: *Cards, name: []const u8) void {
    const prefix = "pcmC";
    if (!std.mem.startsWith(u8, name, prefix)) return;
    const rest = name[prefix.len..];
    const d = std.mem.indexOfScalar(u8, rest, 'D') orelse return;
    if (d == 0 or !std.ascii.isDigit(rest[0])) return;
    const card = std.fmt.parseInt(u8, rest[0..d], 10) catch return;
    if (card >= MAX_CARDS) return;
    const bit = @as(u32, 1) << @intCast(card);
    if (std.mem.eql(u8, rest[d..], "D0p")) {
        cards.playback |= bit;
    } else if (std.mem.eql(u8, rest[d..], "D0c")) {
        cards.capture |= bit;
    }
}

pub const Defaults = struct {
    playback: ?u8 = null,
    capture: ?u8 = null,

    pub fn eql(a: Defaults, b: Defaults) bool {
        return a.playback == b.playback and a.capture == b.capture;
    }
};

fn highest(mask: u32) ?u8 {
    if (mask == 0) return null;
    return @intCast(31 - @clz(mask));
}

/// 재생과 녹음 각각 번호가 가장 큰 카드. 순수 함수다.
pub fn defaultsFor(cards: Cards) Defaults {
    return .{ .playback = highest(cards.playback), .capture = highest(cards.capture) };
}

/// /etc/asound.conf의 글자. 둘 다 없으면 null이다(파일을 지운다). 순수 함수다.
///
/// `sysdefault:CARD=N`은 alsa.conf가 그 카드의 원래 `default`(plug → dmix · dsnoop)에
/// 붙여 둔 이름이다. `pcm.!default`를 덮은 뒤에도 그 길이 그대로 남으므로 섞기 ·
/// 형식 변환은 카드 0일 때와 같다. 믹서(`amixer` · `alsamixer`)의 기본은 재생 쪽
/// 카드다 — 사람이 볼륨을 만지는 것은 소리가 나는 카드이기 때문이다.
///
/// 카드 번호를 글자로 박지 않고 `getenv`의 기본값으로 둔다. alsa-lib의 원래
/// `default`는 `ALSA_PCM_CARD` · `ALSA_CARD`를 먼저 보는데(pcm/default.conf),
/// `pcm.!default`를 덮으면 그 길이 사라져 `ALSA_CARD=0 aplay`가 env를 무시한다
/// (AU-M2 plan 확정 4). 믹서 쪽(`ctl.!default`)은 안 덮으므로 env가 그대로 먹는다.
pub fn render(buf: []u8, d: Defaults) ?[]const u8 {
    const ctl = d.playback orelse d.capture orelse return null;
    var w: std.Io.Writer = .fixed(buf);
    w.writeAll("# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n") catch return null;
    if (d.playback) |n| w.print(DIRECTION, .{ "playback", n }) catch return null;
    if (d.capture) |n| w.print(DIRECTION, .{ "capture", n }) catch return null;
    w.print("}}\ndefaults.ctl.card {d}\n", .{ctl}) catch return null;
    return w.buffered();
}

/// 한 방향. `{s}`가 playback · capture이고 `{d}`가 env가 없을 때의 카드다.
const DIRECTION =
    "\t{s}.pcm {{\n" ++
    "\t\t@func concat\n" ++
    "\t\tstrings [ \"sysdefault:CARD=\" {{ @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"{d}\" }} ]\n" ++
    "\t}}\n";

/// 지금 /dev/snd에 있는 카드. 디렉터리가 없으면(소리 장치가 없는 기계) 빈 집합이다.
fn scanCards() Cards {
    var cards: Cards = .{};
    const rc = linux.open(SND_DIR.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return cards;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [2048]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n) != null or n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const ent: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += ent.reclen;
            addNode(&cards, std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&ent.name)), 0));
        }
    }
    return cards;
}

fn writeConf(text: []const u8) ?linux.E {
    const rc = linux.open(ASOUND_CONF_TMP.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    if (failed(rc)) |e| return e;
    const fd: i32 = @intCast(rc);
    var done: usize = 0;
    while (done < text.len) {
        const n = linux.write(fd, text[done..].ptr, text.len - done);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            _ = linux.close(fd);
            return e;
        }
        done += n;
    }
    _ = linux.close(fd);
    return failed(linux.rename(ASOUND_CONF_TMP.ptr, ASOUND_CONF_PATH.ptr));
}

/// 지난번에 쓴 기본. 처음은 "카드 없음"이라 소리 장치가 없는 기계에서는 한 번도
/// 안 쓰고 한 줄도 안 찍는다.
var defaults_now: Defaults = .{};

/// 감독 루프가 깰 때마다 부른다. 카드가 오거나 갔으면 /etc/asound.conf를 다시 쓴다.
///
/// 쓰기가 실패해도 기억은 새 값으로 바꾼다 — 안 바꾸면 매 초 같은 실패를 찍는다.
/// 다음 변화가 다시 쓴다.
pub fn follow() void {
    const want = defaultsFor(scanCards());
    if (want.eql(defaults_now)) return;
    defaults_now = want;

    var buf: [1024]u8 = undefined;
    const text = render(&buf, want) orelse {
        _ = linux.unlink(ASOUND_CONF_PATH.ptr);
        std.debug.print("tars-init: audio: no sound card left, removed {s}\n", .{ASOUND_CONF_PATH});
        return;
    };
    if (writeConf(text)) |e| {
        std.debug.print("tars-init: audio: cannot write {s} (errno {d})\n", .{ ASOUND_CONF_PATH, @intFromEnum(e) });
        return;
    }
    var pb: [3]u8 = undefined;
    var cb: [3]u8 = undefined;
    std.debug.print("tars-init: audio: default card is {s} for playback, {s} for capture\n", .{
        cardText(&pb, want.playback), cardText(&cb, want.capture),
    });
}

/// 로그용. 카드 번호를 글자로, 없으면 "none". 번호는 32 아래라 두 자리면 된다.
fn cardText(buf: *[3]u8, n: ?u8) []const u8 {
    const v = n orelse return "none";
    return std.fmt.bufPrint(buf, "{d}", .{v}) catch unreachable;
}
```

### 2-2. `init/src/audio_test.zig` — 편집 둘

E1 — `old_string`(기준 파일 6줄부터):

```zig
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.
```

`new_string`:

```zig
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.
//
// AU-M2. 기본 카드를 고르는 순수한 쪽 셋(`addNode` · `defaultsFor` · `render`). 꽂고 뽑을
// 때 소리가 실제로 그 카드로 가는 것은 audio 체인의 부팅 D가 본다.
```

E2 — `old_string`(기준 파일 79줄부터):

```zig
    std.debug.print("audio_test: the mixer is stored only when it was set this boot and /config is there\n", .{});
}
```

`new_string`:

```zig
    std.debug.print("audio_test: the mixer is stored only when it was set this boot and /config is there\n", .{});

    // ── 어느 카드가 기본인가(AU-M2) ────────────────────────────────────
    //
    // /dev/snd의 이름에서 장치 0의 재생 · 녹음만 센다. 아래 목록은 게스트의 실제
    // 모양이다 — HDA(카드 0, 재생과 녹음)에 USB 스피커(카드 1, 재생만)가 꽂힌 것.
    var cards: audio.Cards = .{};
    for ([_][]const u8{ "controlC0", "controlC1", "pcmC0D0c", "pcmC0D0p", "pcmC1D0p", "timer", "seq" }) |name| audio.addNode(&cards, name);
    if (cards.playback != 0b11 or cards.capture != 0b01) return fail("HDA plus a USB speaker reads as playback 0x{x} capture 0x{x}, want 0x3 0x1", .{ cards.playback, cards.capture });
    // 장치 0이 아닌 것 · 모양이 다른 것은 안 센다. HDMI 코덱만 가진 카드는 장치 1(디지털)이다.
    var none: audio.Cards = .{};
    for ([_][]const u8{ "pcmC2D1p", "pcmC2D3p", "pcmC0D0", "pcmCD0p", "pcmC32D0p", "pcmCxD0p", "pcmC1D0px", "hwC0D0", "midiC1D0" }) |name| audio.addNode(&none, name);
    if (none.playback != 0 or none.capture != 0) return fail("names that are not device 0 counted as playback 0x{x} capture 0x{x}", .{ none.playback, none.capture });
    std.debug.print("audio_test: only pcmC<card>D0p and pcmC<card>D0c count\n", .{});

    // 재생과 녹음 각각 번호가 가장 큰 카드. 마이크 없는 USB 스피커가 꽂혀도 녹음은 0에 남는다.
    const split = audio.defaultsFor(cards);
    if (split.playback != 1 or split.capture != 0) return fail("HDA plus a USB speaker picks playback {?d} capture {?d}, want 1 and 0", .{ split.playback, split.capture });
    const headset = audio.defaultsFor(.{ .playback = 0b101, .capture = 0b101 });
    if (headset.playback != 2 or headset.capture != 2) return fail("a headset on card 2 picks playback {?d} capture {?d}, want 2 and 2", .{ headset.playback, headset.capture });
    const empty = audio.defaultsFor(.{});
    if (empty.playback != null or empty.capture != null) return fail("no card picks playback {?d} capture {?d}, want none", .{ empty.playback, empty.capture });
    const top = audio.defaultsFor(.{ .playback = 0x8000_0001, .capture = 0 });
    if (top.playback != 31 or top.capture != null) return fail("card 31 picks playback {?d} capture {?d}", .{ top.playback, top.capture });
    std.debug.print("audio_test: the highest card wins, for playback and capture apart\n", .{});

    // 파일의 글자. 손으로 적은 글자와 비교한다(tautology가 아니게). 카드 번호는 getenv의
    // 기본값 자리에 들어간다 — ALSA_CARD가 있으면 그것이 이긴다.
    var buf: [1024]u8 = undefined;
    const head = "# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n";
    const play1 = "\tplayback.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"1\" } ]\n\t}\n";
    const cap0 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } ]\n\t}\n";
    const cap3 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"3\" } ]\n\t}\n";
    try expectText("split", audio.render(&buf, split), head ++ play1 ++ cap0 ++ "}\ndefaults.ctl.card 1\n");
    try expectText("capture only", audio.render(&buf, .{ .capture = 3 }), head ++ cap3 ++ "}\ndefaults.ctl.card 3\n");
    if (audio.render(&buf, .{}) != null) return fail("no card must render no file", .{});
    std.debug.print("audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file\n", .{});
}

fn expectText(what: []const u8, got: ?[]const u8, want: []const u8) !void {
    const g = got orelse return fail("{s} rendered nothing", .{what});
    if (!std.mem.eql(u8, g, want)) return fail("{s} rendered\n{s}\nwant\n{s}", .{ what, g, want });
}
```

### 2-3. `init/src/main.zig` — 편집 하나

E1 — `old_string`(기준 파일 554줄부터):

```zig
        if (power.take()) |action| power.shutdown(action);
```

`new_string`:

```zig
        if (power.take()) |action| power.shutdown(action);

        // AU-M2. 사운드 카드가 오거나 갔으면 /etc/asound.conf의 기본 카드를 다시
        // 쓴다. 이 루프가 1초마다 깨는 것에 얹혀 있다 — 부팅 뒤에 꽂은 USB 헤드셋도
        // 1초 안에 기본이 된다. 아이들을 띄우기 전이라 첫 바퀴에서는 파일이 서비스 ·
        // 셸보다 먼저 선다.
        audio.follow();
```

### 2-4. 확인과 호스트 검사

```bash
for f in init/src/audio.zig init/src/audio_test.zig init/src/main.zig; do cmp $f /tmp/run/au2/new/$f && echo "SAME $f"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init; zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep "^audio_test:" /tmp/t.log'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 셋 · `test exit=0` · `audio_test:` 일곱 줄(M1의 넷과 M2의 셋 — `only pcmC<card>D0p and pcmC<card>D0c count` ·
`the highest card wins, for playback and capture apart` · `/etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file`).

## Task 3: `audio/probe.sh` · `audio/check.sh` · `check.sh`

확정 2 · 7.

### 3-1. `audio/probe.sh` — 편집 셋

E1 — `old_string`(기준 파일 15줄부터):

```bash
#   again  믹서를 안 만지고 소리를 낸다. 첫 부팅이 바꾼 볼륨이 남았는지를 본다
```

`new_string`:

```bash
#   again  믹서를 안 만지고 소리를 낸다. 첫 부팅이 바꾼 볼륨이 남았는지를 본다
# 셋째 갈래는 따로 만든 디스크다(AU-M2). /config/audio/usb가 있으면 그것이다.
#   usb    부팅 뒤에 꽂힌 USB 스피커로 기본 카드가 가고, 녹음은 HDA에 남고, 뽑으면
#          기본이 돌아오는 것을 소리로 본다. 꽂고 뽑는 것은 체인이 monitor로 한다
```

E2 — `old_string`(기준 파일 26줄부터):

```bash
if [ -e /config/asound.state ]; then boot=again; else boot=first; fi
```

`new_string`:

```bash
if [ -e /config/audio/usb ]; then boot=usb
elif [ -e /config/asound.state ]; then boot=again
else boot=first; fi
```

E3 — `old_string`(기준 파일 47줄부터):

```bash
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"
```

`new_string`:

```bash
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

if [ "$boot" = usb ]; then
  # U. 기본 카드가 USB를 따라가나(AU-M2). init은 /dev/snd를 1초마다 보고
  # /etc/asound.conf를 다시 쓴다. 여기는 그 파일이 바뀔 때까지 기다리고 사람이
  # 치는 그대로 amixer · aplay · arecord를 친다 — 카드를 고르는 -c · -D 없이.
  # 꽂고 뽑는 것은 체인이 monitor로 한다. 이 갈래가 "plug now" · "unplug now"를 찍는다.
  # 파일의 카드 번호는 셋이다 — 재생 · 녹음의 getenv 기본값과 믹서의 카드. 믹서는
  # 재생 쪽을 따르므로 기다리는 것은 그 줄 하나다.
  wait_conf() { # $1 = 기다리는 재생 카드
    for _ in $(seq 1 50); do
      grep -qx "defaults.ctl.card $1" /etc/asound.conf 2>/dev/null && return 0
      sleep 0.2
    done
    return 1
  }
  conf() { say "$1 [$(grep -oE 'default "[0-9]+"|ctl\.card [0-9]+' /etc/asound.conf 2>&1 | flat)]"; }
  # HDA의 Master를 0dB로 둔다. 기본이 USB로 안 가고 HDA로 새면 그 사각파가 값까지
  # 같게 HDA 쪽 파일에 남아 체인이 그것을 본다.
  amixer -q -c 0 sset Master 0dB
  wait_conf 0
  conf "default before plug"
  say "plug now"
  wait_conf 1
  say "usb card [$(grep -E '^ ?1 \[' /proc/asound/cards | flat)]"
  conf "default after plug"
  # 사람이 하는 일 — 꽂은 USB의 볼륨을 올린다. -c가 없으므로 믹서의 기본 카드
  # (defaults.ctl.card)로 간다. QEMU usb-audio는 이 값으로 샘플을 줄이고 꽂힌 직후의
  # 240(-0.5dB)이면 8000이 7529가 된다 — 100%(256)라야 값이 그대로 나간다.
  amixer -q sset 'Audio Output Volume Control' 100%
  say "usb volume [$(amixer -c 1 sget 'Audio Output Volume Control' 2>&1 | tail -n 1)]"
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "plugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  out="$(arecord -q -d 1 -f S16_LE -r 48000 -c 2 /config/audio/cap.wav 2>&1)"; rc=$?
  say "plugged arecord exit ${rc} [$(printf '%s' "$out" | flat)]"
  sync
  say "unplug now"
  wait_conf 0
  conf "default after unplug"
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "unplugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  say "done"
  exec sleep 100000
fi
```

### 3-2. `audio/check.sh` — 편집 열

E1 — `old_string`(기준 파일 33줄부터):

```bash
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘 · 부팅 뒤에 꽂힌 카드(AU-M2 · M3).

# $GUEST_MEM 하나 때문에 source한다. nic · wifi 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh
```

`new_string`:

```bash
#   D  다른 디스크로 떠서 부팅 뒤에 monitor로 USB 스피커(QEMU usb-audio)를 꽂는다.
#      init이 기본 재생 카드를 USB로 옮기고(검사 12 · 13), 녹음은 HDA에 남고(검사 14),
#      뽑으면 기본이 HDA로 돌아온다(검사 15). 판정은 여전히 샘플의 값이다 — USB 쪽
#      소리는 QEMU의 둘째 오디오 백엔드가 또 하나의 file 플러그인으로 받는다
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등, 검사 1이 심볼과 표로만 본다) ·
# DSP(SOF · ACP, AU-M3) · 헤드폰 잭의 꽂힘(QEMU 코덱에 잭 감지가 없다) · 마이크 달린
# USB 헤드셋(QEMU usb-audio는 재생뿐이다).

# $GUEST_MEM 하나 때문에 source한다. nic · wifi 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

# 부팅 D만 monitor를 쓴다 — USB 스피커를 뽑고 꽂는 device_del · device_add(AU-M2).
MONITOR_PORT=45491
```

E2 — `old_string`(기준 파일 60줄부터):

```bash
DISK=../out/audio.img
```

`new_string`:

```bash
DISK=../out/audio.img
DISK_USB=../out/audio-usb.img
```

E3 — `old_string`(기준 파일 90줄부터):

```bash
    "tars-init: audio: stored the mixer" \
```

`new_string`:

```bash
    "tars-init: audio: stored the mixer" \
    "tars-init: audio: default card is" \
    "audio-probe: unplug now" \
    "audio-probe: plug now" \
```

E4 — `old_string`(기준 파일 148줄부터):

```bash
# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
```

`new_string`:

```bash
# AU-M2. 노트북의 코덱 드라이버와 USB 오디오. QEMU의 코덱은 범용 파서가 받으므로 코덱
# 드라이버는 부팅으로 못 본다 — 심볼과, 커널이 코덱의 번호(벤더 · 장치)를 드라이버에
# 잇는 표(modinfo alias)를 드라이버마다 하나씩 본다(UW의 방식). Realtek은 6.18에서 계열
# 열로 갈렸고 EXPERT 없이는 하나씩 못 끈다 — 노트북의 거의 전부인 ALC2xx는 ALC269 계열이다.
for sym in SND_HDA_CODEC_REALTEK SND_HDA_CODEC_ALC269 SND_HDA_CODEC_CONEXANT \
  SND_HDA_CODEC_SENARYTECH SND_HDA_CODEC_CIRRUS SND_HDA_CODEC_CS420X SND_HDA_CODEC_CS8409 SND_HDA_CODEC_ANALOG \
  SND_HDA_CODEC_SIGMATEL SND_HDA_CODEC_VIA SND_USB_AUDIO; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
# 코덱 드라이버 넷이 SND_CTL_LED를 거쳐 NEW_LEDS를 켜고, 그러면 기본값이 y인 입력 쪽
# 둘이 따라 켜진다. HID_APPLE은 Apple 키보드의 fn 키를 커널이 바꿔 keyboard=apple과
# 부딪칠 수 있고, INPUT_LEDS는 키보드 LED를 LED 클래스로 내놓는다 — 둘 다 소리와
# 무관하므로 끈 채 둔다(AU-M2 plan 확정 1).
for sym in HID_APPLE INPUT_LEDS; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} came on with the LED class; the sound drivers must not touch input"
    exit 1
  fi
done
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in snd_hda_codec_alc269.alias=hdaudio:v10EC0256r snd_hda_codec_conexant.alias=hdaudio:v14F11F86r \
  snd_hda_codec_senarytech.alias=hdaudio:v1FA86186r snd_hda_codec_cs420x.alias=hdaudio:v10134208r \
  snd_hda_codec_cs8409.alias=hdaudio:v10138409r \
  snd_hda_codec_analog.alias=hdaudio:v11D41984r snd_hda_codec_idt.alias=hdaudio:v111D76E5r \
  snd_hda_codec_via.alias=hdaudio:v11060440r 'snd_usb_audio.alias=usb:v*p*d*dc*dsc*dp*ic01isc01ip*in*'; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*alias=}"
    exit 1
  fi
done

# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
```

E5 — `old_string`(기준 파일 173줄부터):

```bash
echo "the kernel carries ALSA and HDA, and the initrd carries arecord, libasound, its config, two voices and the audio group"
```

`new_string`:

```bash
echo "the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group"
```

E6 — `old_string`(기준 파일 198줄부터):

```bash
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK"
```

`new_string`:

```bash
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK"
# 부팅 D의 디스크. 같은 씨앗에 표지 파일 하나가 더 있어 프로브가 usb 갈래로 간다.
touch "$WORK/seed/audio/usb"
rm -f "$DISK_USB"
truncate -s 16M "$DISK_USB"
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK_USB"
```

E7 — `old_string`(기준 파일 216줄부터):

```bash
}
EOF
```

`new_string`:

```bash
}
pcm.tarsusb {
  type file
  slave.pcm "null"
  file "$WORK/usb.raw"
  format "raw"
}
EOF
```

E8 — `old_string`(기준 파일 226줄부터):

```bash
start_guest() {
  local drive=()
  [ "$1" = with-disk ] && drive=(-drive file="$DISK",if=virtio,format=raw)
```

`new_string`:

```bash
# usb는 부팅 D다 — 자기 디스크에, xHCI 컨트롤러와 USB 스피커가 쓸 둘째 오디오 백엔드
# (tarsusb), 꽂고 뽑을 monitor가 붙는다. 스피커 자체는 부팅 뒤에 device_add로 꽂는다 —
# 부팅 때 꽂아 둔 usb-audio는 다섯 판 중 한 판에서 커널이 아예 못 봤다(AU-M2 plan 확정 4).
# usb-audio는 48kHz 스테레오 16비트 재생 하나뿐인 장치라 백엔드를 HDA 쪽과 같은
# 모양으로 박는다.
start_guest() {
  local drive=() usb=()
  case "$1" in
    with-disk) drive=(-drive file="$DISK",if=virtio,format=raw) ;;
    usb)
      drive=(-drive file="$DISK_USB",if=virtio,format=raw)
      usb=(-audiodev alsa,id=snd1,out.dev=tarsusb,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off
        -device qemu-xhci,id=xhci
        -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait)
      ;;
  esac
```

E9 — `old_string`(기준 파일 243줄부터):

```bash
    -device hda-micro,audiodev=snd0 \
```

`new_string`:

```bash
    -device hda-micro,audiodev=snd0 \
    "${usb[@]}" \
```

E10 — `old_string`(기준 파일 463줄부터):

```bash
echo "AU check PASS"
```

`new_string`:

```bash
# ══ 부팅 D: 부팅 뒤에 꽂는 USB 스피커 (AU-M2) ═══════════════════════════
# HDA(카드 0)로 떠서 USB 스피커를 꽂으면 카드 1이 생긴다. init은 /dev/snd를 1초마다
# 보고 /etc/asound.conf에 기본 카드를 적는다 — 재생과 녹음 각각, 장치 0을 가진 카드 중
# 번호가 가장 큰 것. 그래서 재생은 USB로, 녹음은 마이크 없는 USB 대신 HDA로 간다.
# 프로브가 "plug now" · "unplug now"를 찍으면 이 스크립트가 monitor로 꽂고 뽑는다.
#
# 소리가 어디로 갔는지는 두 파일로 본다. HDA 쪽 TAP은 QEMU가 부팅 때 한 번 열고, USB
# 쪽 USB_TAP은 스피커를 꽂을 때 연다. 뽑기 전에 둘 다 옆으로 떠 두고 센다.
echo "=== boot D: an HDA card, then a USB speaker plugged and unplugged with the monitor ==="
rm -f "$WORK/tap.raw" "$WORK/usb.raw"
start_guest usb
wait_for_log 'audio-probe: plug now' 90 \
  || report_failure "boot D: the probe never asked for the USB speaker"
# QEMU가 monitor 포트를 연 지 오래인 시점이라 첫 번에 붙는다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "boot D: could not connect to the QEMU monitor"
echo "device_add usb-audio,id=usbspk,audiodev=snd1,bus=xhci.0" >&3
wait_for_log 'audio-probe: unplug now' 60 \
  || report_failure "boot D: the probe never got to unplugging the USB speaker"

# ── 검사 12: 꽂힌 USB 스피커가 카드 1이 되고 init이 기본 재생을 그리로 옮겼다 ──
# usbcore 줄은 커널이 snd-usb-audio를 USB 코어에 올렸다는 뜻이고(장치와 무관하게
# 찍힌다), 카드 줄은 그 드라이버가 꽂힌 장치를 실제로 받았다는 뜻이다. init의 줄
# 둘은 부팅 때(HDA뿐)와 꽂은 뒤다.
grep -a 'usbcore: registered new interface driver snd-usb-audio' "$LOG" >/dev/null \
  || report_failure "usbcore never registered snd-usb-audio"
grep -aE 'audio-probe: usb card \[ ?1 \[.*\]: USB-Audio - ' "$LOG" >/dev/null \
  || report_failure "the plugged USB speaker did not become card 1"
grep -aF 'audio-probe: default before plug [default "0"|default "0"|ctl.card 0]' "$LOG" >/dev/null \
  || report_failure "before the plug /etc/asound.conf did not point both ways at card 0"
grep -aF 'tars-init: audio: default card is 1 for playback, 0 for capture' "$LOG" >/dev/null \
  || report_failure "init did not move the default playback card to the plugged USB speaker"
grep -aF 'audio-probe: default after plug [default "1"|default "0"|ctl.card 1]' "$LOG" >/dev/null \
  || report_failure "/etc/asound.conf does not send playback to card 1 and capture to card 0"
echo "the plugged USB speaker came up as card 1 and init made it the default for playback"

# ── 검사 13: 사람이 친 amixer · aplay가 USB 스피커로 갔다 ────────────────
# amixer에 -c가 없으므로 그 100%는 믹서의 기본 카드(defaults.ctl.card)가 받은 것이다.
# 사각파는 값까지 같게 USB 쪽에 있고 HDA 쪽에는 한 프레임도 없다.
grep -aE "audio-probe: usb volume \[.*Playback 256 \[100%\]" "$LOG" >/dev/null \
  || report_failure "amixer without -c did not reach the USB speaker's volume"
grep -aF 'audio-probe: plugged aplay exit 0 []' "$LOG" >/dev/null \
  || report_failure "aplay through the default device failed with the USB speaker in"
cp "$WORK/usb.raw" "$WORK/usb_1.raw" 2>/dev/null || report_failure "QEMU never opened the USB speaker's side (no usb tap file)"
cp "$WORK/tap.raw" "$WORK/tap_1.raw" 2>/dev/null || : > "$WORK/tap_1.raw"
USB_1="$(count_tap "$WORK/usb_1.raw")"
HDA_1="$(count_tap "$WORK/tap_1.raw")"
echo "usb tap: ${USB_1}"
echo "hda tap: ${HDA_1}"
if [ "$(field "$USB_1" tone)" -lt 40000 ] || [ "$(field "$USB_1" other)" -ne 0 ]; then
  report_failure "the square wave did not reach the USB speaker sample for sample (${USB_1})"
fi
if [ "$(field "$HDA_1" tone)" -ne 0 ]; then
  report_failure "the square wave also reached the HDA speaker (${HDA_1})"
fi
echo "amixer and aplay went to the USB speaker, and the HDA speaker stayed silent"

# ── 검사 14: 녹음은 HDA의 마이크에 남았다 (판정은 아래, 끈 뒤에 파일로) ──
# USB 스피커에는 녹음 장치가 없다. 기본을 한 카드로 묶었다면 arecord가 여기서 죽는다.
grep -aF 'audio-probe: plugged arecord exit 0 []' "$LOG" >/dev/null \
  || report_failure "arecord through the default device failed with the USB speaker in"

# ── 뽑는다 ─────────────────────────────────────────────────────────────
echo "device_del usbspk" >&3
wait_for_log 'audio-probe: done' 30 \
  || report_failure "boot D: the probe did not finish after the USB speaker went"

# ── 검사 15: 뽑으면 기본이 HDA로 돌아온다 ─────────────────────────────
# init의 "0 for playback, 0 for capture"가 두 번이다 — 부팅 때와 뽑은 뒤.
if [ "$(grep -acF 'tars-init: audio: default card is 0 for playback, 0 for capture' "$LOG")" -ne 2 ]; then
  report_failure "init did not move the default back to card 0 after the USB speaker went"
fi
grep -aF 'audio-probe: default after unplug [default "0"|default "0"|ctl.card 0]' "$LOG" >/dev/null \
  || report_failure "after the unplug /etc/asound.conf still points away from card 0"
grep -aF 'audio-probe: unplugged aplay exit 0 []' "$LOG" >/dev/null \
  || report_failure "aplay failed after the USB speaker went"
sleep 0.5
HDA_2="$(count_tap "$WORK/tap.raw")"
echo "hda tap after unplug: ${HDA_2}"
if [ "$(field "$HDA_2" tone)" -lt 40000 ] || [ "$(field "$HDA_2" other)" -ne 0 ]; then
  report_failure "after the unplug the square wave did not reach the HDA speaker sample for sample (${HDA_2})"
fi
stop_guest
echo "unplugged, the default went back to the HDA card and aplay played there"

debugfs -R "dump audio/cap.wav $WORK/cap_d.wav" "$DISK_USB" >/dev/null 2>&1
[ -s "$WORK/cap_d.wav" ] || report_failure "boot D left no cap.wav on its config disk"
CAP_D="$(perl -e '
  open(my $f, "<:raw", $ARGV[0]) or die; local $/; my $d = <$f>;
  my ($n, $m) = (0, 0);
  for (my $p = 44; $p + 4 <= length $d; $p += 4) { $n++; $m++ if substr($d, $p, 4) eq pack("s<s<", 3000, -5000) }
  print "frames=$n match=$m\n";' "$WORK/cap_d.wav")"
echo "cap D: ${CAP_D}"
if [ "$(field "$CAP_D" frames)" -ne 48000 ] || [ "$(field "$CAP_D" match)" -ne 48000 ]; then
  report_failure "with the USB speaker in, arecord did not record the HDA microphone (${CAP_D}, want 48000 of each)"
fi
echo "with the USB speaker in, arecord still recorded the HDA microphone, 48000 frames of 48000"

echo "AU check PASS"
```

### 3-3. `check.sh` — 편집 둘

E1 — `old_string`(기준 파일 343줄부터):

```bash
# 같은 디스크로 두 번 떠서 보고, 설정 디스크 없이 한 번 더 뜬다. 회차당 부팅 3회.
```

`new_string`:

```bash
# 같은 디스크로 두 번 떠서 보고, 설정 디스크 없이 한 번 더 뜬다. 넷째 부팅은 monitor(45491)로
# USB 스피커를 꽂고 뽑아 기본 카드가 따라가는 것을 본다(AU-M2). 회차당 부팅 4회.
```

E2 — `old_string`(기준 파일 367줄부터):

```bash
  "AU-M1:./audio/check.sh"
```

`new_string`:

```bash
  "AU-M2:./audio/check.sh"
```

### 3-4. 확인

```bash
for f in audio/probe.sh audio/check.sh check.sh; do cmp $f /tmp/run/au2/new/$f && echo "SAME $f"; done
bash -n audio/probe.sh && bash -n audio/check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./audio/check.sh && require_no_early_exit_pipe ./audio/check.sh &&
  require_explicit_nic ./audio/check.sh && echo ENTRY-OK'
python3 /tmp/run/au2/anchors.py post "$PWD"
```

기대: `SAME` 셋 · `SYNTAX-OK` · `ENTRY-OK` · `post: 19 edits, 0 bad`.

## Task 4: 체인 한 번과 regression

### 4-1. `audio` 체인

캐시를 지운 판이라 2분 남짓이다. 로그를 호스트에서 읽게 `/tmp/run/au2`를 함께 붙인다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/au2:/tmp/run/au2 -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache init/zig-out terminal/.zig-cache terminal/zig-out
    bash audio/check.sh > /tmp/run/au2/impl/audio.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
rg -a -v '^qemu-system' /tmp/run/au2/impl/audio.log | tail -n 30
```

기대: `exit=0`, 그리고 마지막 서른 줄이 사본의 것과 같은 모양이다.

```
vendor_firmware: firmware.cpio.gz matches the list, skipping
258807 blocks
the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group
=== boot A: q35 with an HDA controller and a speaker + microphone codec, a fresh config disk ===
the kernel configured the codec as card 0 with a playback and a capture node
aplay -l and arecord -l both see card 0 device 0
the boot turned Master and Capture on with alsactl init, and amixer raised Master to 0dB
tap: frames=194578 tone=47935 left=53060 right=71059 other=0 doubled=0 zero=22524 first_left=50822 first_right=122599
aplay's square wave reached the speaker sample for sample
speaker-test spoke on the left channel, then on the right
cap: frames=96000 match=96000
arecord got the microphone's constant on both channels, 96000 frames of 96000
the power-off stored the mixer, and asound.state keeps Master at 74 (0dB)
shutdown: asked at 9.26s, powered down at 9.459929s
=== boot B: the same disk again ===
the second boot restored Master at 0dB and Capture on from the disk
tap B: frames=50591 tone=48000 left=0 right=0 other=0 doubled=0 zero=2591 first_left=-1 first_right=-1
with no amixer, aplay's square wave reached the speaker sample for sample
=== boot C: no config disk ===
without a config disk the boot still turned the mixer on with alsactl init
=== boot D: an HDA card, then a USB speaker plugged and unplugged with the monitor ===
the plugged USB speaker came up as card 1 and init made it the default for playback
usb tap: frames=50112 tone=48000 left=0 right=0 other=0 doubled=0 zero=2112 first_left=-1 first_right=-1
hda tap: frames=0 tone=0 left=0 right=0 other=0 doubled=0 zero=0 first_left=-1 first_right=-1
amixer and aplay went to the USB speaker, and the HDA speaker stayed silent
hda tap after unplug: frames=49248 tone=48000 left=0 right=0 other=0 doubled=0 zero=1248 first_left=-1 first_right=-1
unplugged, the default went back to the HDA card and aplay played there
cap D: frames=48000 match=48000
with the USB speaker in, arecord still recorded the HDA microphone, 48000 frames of 48000
AU check PASS
```

`tap:` · `tap B:` · `usb tap:` · `hda tap after unplug:`의 `frames` · `zero` · `first_*`, 그리고 `tone`의 자투리(47,4xx ~ 48,000)와
`shutdown:`의 두 수는 판마다 다르다. `cap:` · `cap D:` 줄과 `hda tap:`(꽂힌 동안 HDA 쪽, 0프레임)은 판마다 같았다. 빨개지면
`report_failure`가 찍는 표식 · `audio-probe` · `tars-init: audio` 줄 · 마지막 40줄을 그대로 보고한다.

### 4-2. regression — `install` · `tools` · `boot` · `machine` · `wifi` · `power` · `service` · `pointer`

확정 11의 여덟이다. 한 컨테이너에서 차례로 돈다. 9분 안팎 걸려 Bash 한 번의 상한(10분)을 넘으므로 `run_in_background`로 돌리고
기다린다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/au2:/tmp/run/au2 -w /workspace tars-devcontainer bash -c '
  for c in install tools boot machine wifi power service pointer; do s=$(date +%s); bash $c/check.sh > /tmp/run/au2/impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/au2/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/au2/impl/reg.out
rg -a 'init waited|tools the list names' /tmp/run/au2/impl/reg_install.log /tmp/run/au2/impl/reg_tools.log
```

기대: 여덟 다 `exit=0`. `init waited`가 1,500ms 이상(사본 1,800ms)이고 `all 92 tools`다. `init waited`가 500ms 아래면 멈추고
보고한다(lessons PD-3).

## Task 5: mutation

확정 10의 표다. 사본은 `/tmp/run/au2/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 5-0. 사본을 만든다

```bash
python3 /tmp/run/au2/make_mut.py "$PWD" /tmp/run/au2/impl/mut
M=/tmp/run/au2/impl/mut
for p in main_m1.zig:init/src/main.zig audio_m2.zig:init/src/audio.zig audio_m3.zig:init/src/audio.zig \
  audio_m4.zig:init/src/audio.zig config_k1:kernel/.config config_k2:kernel/.config config_k3:kernel/.config \
  check_no12.sh:audio/check.sh check_no12vol.sh:audio/check.sh check_no1usb.sh:audio/check.sh; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 10`, 그리고 바뀐 줄 수가 `main_m1.zig 1` · `audio_m2.zig 2` · `audio_m3.zig 2` · `audio_m4.zig 2` ·
`config_k1 2` · `config_k2 2` · `config_k3 2` · `check_no12.sh 16` · `check_no12vol.sh 18` · `check_no1usb.sh 4`. 다르면 돌리지 말고 보고한다.

`make_mut.py`:

```python
"""AU-M2 plan Task 5의 mutation 사본을 만든다.

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


# mutation 1 — 감독 루프가 기본 카드를 안 본다(/etc/asound.conf가 안 생긴다)
make('init/src/main.zig', 'main_m1.zig', '        audio.follow();\n', '')
# mutation 2 — 번호가 가장 작은 카드를 고른다
make('init/src/audio.zig', 'audio_m2.zig',
     '    return @intCast(31 - @clz(mask));\n', '    return @intCast(@ctz(mask));\n')
# mutation 3 — 녹음도 재생 카드를 따라간다(마이크 없는 USB 스피커로 녹음이 간다)
make('init/src/audio.zig', 'audio_m3.zig',
     '    return .{ .playback = highest(cards.playback), .capture = highest(cards.capture) };\n',
     '    return .{ .playback = highest(cards.playback), .capture = highest(cards.playback | cards.capture) };\n')
# mutation 4 — 기본이 더 낮은 번호로는 안 내려간다(뽑아도 기본이 USB에 남는다)
make('init/src/audio.zig', 'audio_m4.zig',
     '    if (want.eql(defaults_now)) return;\n',
     '    if (want.eql(defaults_now) or (want.playback orelse 0) < (defaults_now.playback orelse 0)) return;\n')
# 커널 mutation 셋 — .config 사본. 체인의 build.sh가 해시가 달라진 것을 보고 다시 빌드한다
make('kernel/.config', 'config_k1', 'CONFIG_SND_USB_AUDIO=y\n', '# CONFIG_SND_USB_AUDIO is not set\n')
make('kernel/.config', 'config_k2', '# CONFIG_HID_APPLE is not set\n', 'CONFIG_HID_APPLE=y\n')
make('kernel/.config', 'config_k3', 'CONFIG_SND_HDA_CODEC_REALTEK=y\n', '# CONFIG_SND_HDA_CODEC_REALTEK is not set\n')

# 앞 검사를 건너뛰는 체인 사본(겨냥한 검사까지 가게 한다 — lessons "mutation이 겨냥한 검사에 걸릴 것이라고 믿기")
cut('audio/check.sh', 'check_no12.sh', '# ── 검사 12:', '# ── 검사 13:')
# 검사 12와 검사 13의 첫째(-c 없는 amixer)를 함께 뺀 사본 — mutation 1이 소리의 자리(USB 쪽 사각파)까지 가게 한다
s = open(os.path.join(out, 'check_no12.sh')).read()
old = """grep -aE "audio-probe: usb volume \\[.*Playback 256 \\[100%\\]" "$LOG" >/dev/null \\
  || report_failure "amixer without -c did not reach the USB speaker's volume"
"""
assert s.count(old) == 1
open(os.path.join(out, 'check_no12vol.sh'), 'w').write(s.replace(old, ''))
os.chmod(os.path.join(out, 'check_no12vol.sh'), 0o755)
# 검사 1의 USB 오디오 둘(심볼 · alias)을 뺀 사본 — 커널 mutation 1이 부팅 D까지 가게 한다
make('audio/check.sh', 'check_no1usb.sh',
     "  SND_HDA_CODEC_SIGMATEL SND_HDA_CODEC_VIA SND_USB_AUDIO; do\n",
     "  SND_HDA_CODEC_SIGMATEL SND_HDA_CODEC_VIA; do\n")
s = open(os.path.join(out, 'check_no1usb.sh')).read()
old = "snd_hda_codec_via.alias=hdaudio:v11060440r 'snd_usb_audio.alias=usb:v*p*d*dc*dsc*dp*ic01isc01ip*in*'; do\n"
assert s.count(old) == 1
open(os.path.join(out, 'check_no1usb.sh'), 'w').write(s.replace(old, "snd_hda_codec_via.alias=hdaudio:v11060440r; do\n"))
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. 덮은 Zig 파일이 빌드에 들어가게 판마다 `init`의 캐시를
지운다. 커널 사본(`config_k*`)은 `build.sh`의 스탬프가 해시 차이를 보고 다시 빌드한다(판마다 20 ~ 50초 더).

```bash
#!/bin/bash
# AU-M2 plan Task 5의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 audio 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 아홉 자리는 차례로 "follow 호출 · 가장 큰 번호 · 녹음 따로 · 내려가는 기본 · USB 오디오 심볼 ·
# HID_APPLE 꺼짐 · Realtek 심볼 · 검사 12 · 검사 1의 USB 둘"의 수다. 덮지 않은 판은 111111111이다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  echo \"mounted: \$(grep -c '^        audio.follow();' init/src/main.zig)\$(grep -c '31 - @clz(mask)' init/src/audio.zig)\$(grep -c 'capture = highest(cards.capture) }' init/src/audio.zig)\$(grep -c '^    if (want.eql(defaults_now)) return;' init/src/audio.zig)\$(grep -c '^CONFIG_SND_USB_AUDIO=y' kernel/.config)\$(grep -c '^# CONFIG_HID_APPLE is not set' kernel/.config)\$(grep -c '^CONFIG_SND_HDA_CODEC_REALTEK=y' kernel/.config)\$(grep -c '^# ── 검사 12:' audio/check.sh)\$(grep -c 'SND_HDA_CODEC_VIA SND_USB_AUDIO; do' audio/check.sh)\"
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^AU check PASS' "$mut/$name.log" | head -2
```

### 5-1. 체인 열세 판

판마다 1분 안팎, 합해서 14분 남짓 걸린다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/au2/impl/mut; X=/tmp/run/au2/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M m1 main_m1.zig:init/src/main.zig
  $X $R $I $M m1_play main_m1.zig:init/src/main.zig check_no12.sh:audio/check.sh
  $X $R $I $M m1_tap main_m1.zig:init/src/main.zig check_no12vol.sh:audio/check.sh
  $X $R $I $M m2 audio_m2.zig:init/src/audio.zig
  $X $R $I $M m2_play audio_m2.zig:init/src/audio.zig check_no12.sh:audio/check.sh
  $X $R $I $M m3 audio_m3.zig:init/src/audio.zig
  $X $R $I $M m3_rec audio_m3.zig:init/src/audio.zig check_no12.sh:audio/check.sh
  $X $R $I $M m4 audio_m4.zig:init/src/audio.zig
  $X $R $I $M k1 config_k1:kernel/.config
  $X $R $I $M k1_boot config_k1:kernel/.config check_no1usb.sh:audio/check.sh
  $X $R $I $M k2 config_k2:kernel/.config
  $X $R $I $M k3 config_k3:kernel/.config; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 10의 표에서 그 판의 `FAIL` 줄이고 `m0`은 `AU check PASS`다. `mounted:`는 `m0`이 `111111111`이고 덮은 자리의 숫자가
0이다(`m1*` 첫째 · `m2*` 둘째 · `m3*` 셋째 · `m4` 넷째 · `k1*` 다섯째 · `k2` 여섯째 · `k3` 일곱째, `*_play` · `*_rec`는 여덟째도,
`k1_boot`은 아홉째도). `check_no12vol.sh`는 검사 13의 첫째 줄만 더 지운 것이라 `mounted:`에 따로 안 잡힌다. 로그에 `Killed`가 보이고 `FAIL: … build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른
컨테이너가 없는지 보고 그 판만 다시 돈다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 덮기를
의심한다(`mounted:`).

### 5-2. 호스트 검사 두 판

```bash
M=/tmp/run/au2/impl/mut
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
for m in m2 m3; do
  docker run --rm -v "$PWD":/workspace -v $M/audio_$m.zig:/workspace/init/src/audio.zig:ro -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache; cd init; zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep "^FAIL" /tmp/t.log'
done
rmdir /tmp/run/docker.lock
```

기대: 두 판 다 `test exit=`가 0이 아니고, `FAIL` 줄이 확정 10의 둘째 표와 같다.

### 5-3. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. 커널 사본 판이 `kernel/build`를 다른 설정으로 빌드해 두었으므로
체인이 지금 `.config`로 다시 빌드하고(20초 남짓), `init`과 initrd도 지금 소스로 다시 만든다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /tmp/a.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/a.log
  grep " inflate_fast$" kernel/build/System.map; stat -c "%s bzImage" kernel/build/arch/x86/boot/bzImage'
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `AU check PASS` · `ffffffff8147fb40 T inflate_fast` · `8213504 bzImage`. `git status`는 `M` 일곱(`kernel/.config` ·
`init/src/audio.zig` · `init/src/audio_test.zig` · `init/src/main.zig` · `audio/probe.sh` · `audio/check.sh` · `check.sh`)이고, plan이
commit 전이면 그것이 더 있다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 5-4. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `7 files changed, 591 insertions(+), 17 deletions(-)`였다.
- Task 0의 출력.
- Task 1의 출력(`FOLDED` · 크기 · `inflate_fast` · `+CONFIG` 35줄).
- Task 2 · 3의 확인 출력(`SAME` · `SYNTAX-OK` · `ENTRY-OK` · `anchors.py` · 호스트 검사).
- Task 4의 `exit=` · `real` · 마지막 서른 줄과 regression 여덟의 줄 · `init waited` · `all 92 tools` · `default card` 셈.
- Task 5의 `diff` 수 아홉 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 5-2의 두 판, 5-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 6: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 일곱 파일을 `/tmp/run/au2/new/`와 `cmp`한다. Task 4의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스무 체인 × 2다. 판정은 `PASS: 2/2` × 20과 `AU check PASS` 둘이다. `run_in_background`로
   돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다. 게이트 첫 회차가 `kernel/build`를 지우므로 커널을 처음부터 빌드한다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_au2.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_au2.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_au2.log`가 20,
   `rg -c 'AU check PASS' /tmp/gate_au2.log`가 2여야 한다.
3. 실측 절 채우기, design에 덧붙이기(아래 "design에 덧붙일 것"), design `Status:`(M2 끝, M3 plan 차례).
4. commit. 넣는 것은 일곱 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다.
5. lessons의 포트 절에 45491(audio 부팅 D)을 적는다 — 새 체인은 45492부터다.

## design에 덧붙일 것

design 본문은 이 plan이 안 고쳤다. lead가 넣을 것.

1. 결정 1 끝에 "M2가 켠 것" 문단 — 확정 1의 열(`-e` 여덟 · `-d` 둘)과 이유, Realtek은 `EXPERT` 없이 계열을 못 고른다, `NEW_LEDS`가
   끌고 오는 일곱 중 입력 쪽 둘을 끄고 무선 LED 다섯은 둔다, 크기 +258,048바이트, `inflate_fast` 자리가 그대로라 `Run /init`과
   `init waited`가 HEAD와 같다. 그리고 결정 1의 표 (b) "M2" 행을 "M2가 했다"로.
2. lead의 전제를 바로잡은 것 — "부팅 뒤에 꽂은 카드는 꺼진 채다"(결정 4의 셋째 · M1이 넘긴 것)는 USB에는 틀렸다. 커널은 USB 카드를
   끄지 않고 장치가 가진 볼륨으로 내놓는다(QEMU `240 [-0.50dB] [on]`, 확정 3). 그래서 꽂을 때 `alsactl`을 부르는 자리가 없다.
3. 결정 하나를 새로 — 기본 카드(확정 4). 규칙 · 자리(감독 루프의 1초 바퀴) · 파일의 모양(`asym` + `sysdefault:CARD=N`, 믹서는 재생
   쪽) · 후보 표 (b) ~ (g) · `tars.conf` 키 없음.
4. 결정 5(게이트)의 검사 표 — 검사 1이 넓어지고 부팅 D와 검사 12 ~ 15가 더해졌다. 포트 45491을 처음 쓴다(결정 5의 "monitor를 안
   쓴다"와 lead의 전제 5가 M2에서 바뀐다). QEMU `usb-audio`의 볼륨이 샘플을 줄인다(240/255)는 것과, 부팅 때 꽂아 둔 판이 열 판
   중 넷에서 안 됐다는 것(한 번은 열거가 빠졌고 세 번은 QEMU가 시리얼에 한 줄도 없이 섰다) — 그래서 게이트는 부팅 뒤에 꽂는다.
5. 위험 셋 — (1) 번호를 다시 쓰면 "가장 큰"이 "가장 나중"과 어긋난다(USB 둘을 꽂았다 하나를 뽑고 셋째를 꽂을 때). (2) 스피커 앰프가
   side codec(CS35L41 · CS35L56 · TAS2781)인 노트북은 내장 스피커가 조용하다 — M3과 같은 층(`SND_SOC` · firmware). (3) USB를 꽂은
   동안 `amixer sset Master`가 `Unable to find simple control 'Master',0`으로 실패한다 — 믹서의 기본이 USB 카드이고 거기에 `Master`가
   없다. `amixer -c 0`. 그리고 실측 하나 — 파일의 카드 번호를 `getenv`의 기본값으로 둔 이유(확정 4의 env 문단). 그리고 design 위험 2(잭 입력 장치)가 M2부터 실기에서 현실이 된다 — `init`의
   키보드 판정(`KEY_ESC` ~ `KEY_D` 전부)과 terminal의 포인터 판정(`REL_X` · `REL_Y` · `BTN_LEFT` 또는 터치패드의 ABS)은 잭 장치
   (`EV_SW`, 헤드셋 버튼의 `KEY_PLAYPAUSE` 등)를 안 고른다는 것을 코드로 읽었다.
6. 비목표 하나 — 꽂을 때 그 카드의 지난 볼륨을 되살리는 것(`alsactl restore N`, 확정 3). 그리고 CS8409(Dell · Apple의 HDA 다리)는
   lead가 켜기로 정했다(2026-10-06) — `default`가 없는 심볼이라 `-e`로 따로 적는다(+8,192바이트).
7. Milestone 절의 AU-M2를 "했다"로 — 그리고 "닫을 때"의 running-tars.md 소리 절에 둘. USB 헤드셋을 꽂으면 1초 안에 기본이 되고
   `cat /etc/asound.conf`로 볼 수 있다. 내장 카드의 믹서는 `amixer -c 0 sset Master …`.

## 이 milestone에서 안 하는 것

- 꽂을 때 그 카드의 지난 볼륨을 되살리는 것(확정 3).
- 스피커 앰프 side codec(CS35L41 · CS35L56 · TAS2781)과 DSP(SOF · ACP) — M3.
- 마이크 달린 USB 헤드셋의 녹음을 게이트로 보는 것. QEMU `usb-audio`는 재생뿐이다. 규칙(녹음도 번호가 가장 큰 카드)은 호스트 검사
  (`headset` 2/2)로만 본다.
- `tars.conf`의 소리 키. 볼륨 · 음소거 키(design 비목표 5). HDMI 오디오(비목표 6).
- `running-tars.md`의 소리 절. lead가 서브프로젝트를 닫을 때 쓴다.

## AU-M2가 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-06에 main 작업 트리에서 했고, lead가 일곱 파일을 `/tmp/run/au2/new/`와 `cmp`해 전부 같은
것을 봤다. plan의 기대와 글자나 수가 다른 것은 없었다. 로그는 `/tmp/run/au2/impl/`, 루트 게이트는 `/tmp/gate_au2.log`(빨간 첫 판)와
`/tmp/gate_au2b.log`(초록).

1. 편집과 검사. 커널 `build 1` · `build 2` exit 0 · `FOLDED` · bzImage 8,213,504 · `inflate_fast` `ffffffff8147fb40`(58초). `git diff --stat`이
   7 files +591 −17, 지운 줄은 전부 의도한 것(`.config`의 `is not set` 아홉 · 체인 다섯 · 프로브 하나 · `check.sh` 둘). `zig build test` exit 0에
   `audio_test` 줄 일곱. `audio` 체인 2분 3초 초록 — `usb tap` `tone=48000 other=0`, `hda tap` `frames=0`, 뽑은 뒤 `tone=48000`, `cap D`
   48,000/48,000. regression 여덟 전부 exit 0(`install` 105초 `init waited 1800ms` · `tools` 65초 `all 92 tools` · `boot` 22 · `machine` 20 ·
   `wifi` 99 · `power` 49 · `service` 69 · `pointer` 75). mutation 열세 판 + 호스트 검사 두 판이 확정 10의 표와 같은 자리 · 글자로 빨갰다.
2. 루트 게이트 첫 판(`/tmp/gate_au2.log`, 49분 37초)이 열아홉째 `pointer` 체인의 2회차 부팅 B에서 `seq 200 did not finish`로 빨갰다 —
   `audio`는 돌지도 못했다. 원인은 M2가 아니라 게이트의 읽기였다. 시리얼 로그에서 terminal의 `screen>` 덤프 줄 한가운데에 커널의
   `[    7.359211] random: crng init done`이 끼어 줄이 둘로 갈라졌고, 뒤 조각(`197 | 198 | 199 | 200 | root@(none) ~#`)에는 머리가 없어
   `wait_for_screen`이 못 봤다. 커널 콘솔 출력은 UART에 직접 쓰므로 유저랜드의 한 줄을 어디서든 자른다(한 write()로 써도 같다 — 자르는
   것은 전송이다). lead가 `gate_lib.sh`에 `joined_screen_dump`를 더해 꼬리에 커널 시각 표식이 붙은 `screen>` 줄을 다음 줄과 이어 붙이고
   `wait_for_screen`이 그것을 읽게 했다(+26 −1). 실제로 갈라졌던 줄로 시험해 `| 200 | root@\(none\) ~#`에 맞는 것을 봤다. lessons
   "커널 printk가 terminal의 화면 줄을 가운데서 자른다".
3. 그 함수의 처음 이름 `screen_lines`가 `pointer/check.sh`의 같은 이름(화면 줄 개수)과 충돌해 `pointer`가 세 판 내리 32초에
   "the shell prompt never showed up"로 빨갰다(`wait_for_screen`이 화면 대신 숫자 "3"을 받았다 — `set -x`가 보여 줬다). 이름을 바꾼 뒤
   `pointer` 74초 · `terminal` 24초 초록.
4. 루트 게이트 둘째 판(`/tmp/gate_au2b.log`). 스무 체인 × 2회, 51분 10초, `PASS: 2/2` 스물 · `AU check PASS` 둘 · `skipping make` 39.
   `audio`의 두 회차 — 부팅 A `tone` 48,000 둘(`other` · `doubled` 0), `cap` 96,000/96,000, 부팅 B `tone` 48,000, 부팅 D `usb tap`
   `tone` 48,000 둘 · `hda tap` 0 · 뽑은 뒤 48,000 · `cap D` 48,000/48,000. `install` 부팅 7 `init waited` 1,800ms 둘. M1의 50분 54초에
   16초가 더해졌다(확정 8이 본 25초 안팎).
5. lead가 이 milestone에 함께 넣은 것 — `gate_lib.sh`의 `joined_screen_dump`, lessons 셋(printk 자름 · dmix xrun · 함수 이름 충돌),
   design의 M2 덧붙임 일곱("design에 덧붙일 것" 그대로 — 결정 1의 M2 문단 · 결정 7 · 전제 7 · 8 · 검사 표 · 위험 8~10 · 비목표 9 ·
   Milestone · 닫을 때의 running-tars 줄).
