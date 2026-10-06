# AU-M3 — DSP 뒤의 내장 마이크(Intel SOF · AMD ACP), firmware와 녹음의 기본 장치

Date: 2026-10-06
Design: `docs/specs/2026-10-05-tars-audio-devices-design.md`
Status: 끝났다(2026-10-06). plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "AU-M3가 실측한 것"에 있다. 이것으로 AU가 닫혔다.

## 누가 무엇을 하나

design 결정 6. Task 0~5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 이 milestone에서 정할 것(범위 · 커널 심볼 · firmware의 출처와 목록 · UCM과 마이크 스위치 · 녹음의 기본
장치 · 게이트의 모양)은 이 plan이 커널 소스와 alsa-lib · alsa-utils · alsa-ucm-conf 1.2.14 소스, 그리고 사본에서 정했고(확정 1~7),
커널 설정은 정해진 `scripts/config` 한 줄로, 나머지는 컴파일 · 호스트 검사 · 체인 · regression · mutation까지 사본에서 돌린 글자
그대로 넘긴다. 구현자에게 남는 판단이 없다 — 편집 서른둘을 글자 그대로 넣고, 커널을 정해진 명령으로 빌드하고, 체인 · regression ·
mutation을 정해진 순서로 돌린다. plan의 기대와 다른 값이 나오면 고치지 말고 보고한다. Opus로 올릴 이유는 하나다 — 루트 게이트에서
이 plan이 못 돌린 체인이 빨개져 원인을 찾아야 할 때. 그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/au3/repo/`)에 먼저 넣어 호스트 검사 · 체인 · regression · mutation까지 돌렸고, 아래의
`old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/au3/render.py`). 기준은 AU-M2 commit(`cd9c12e`)의 파일
(`/tmp/run/au3/base/`)이고 편집 뒤의 파일은 `/tmp/run/au3/new/`다. 구현자는 코드를 새로 짓지 않는다. 편집은 Edit 도구에 글자 그대로
넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고 — EL · CB · AU-M1 · M2의 구현자가 그렇게 했다), 각 Task 끝에서 `new/`와 `cmp`해
같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그
자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `kernel/.config` | ASoC · Intel SOF(세대 열하나와 HDA 코덱 · 범용 machine) · HDMI 코덱(범용 machine이 depends) · AMD ACP(세대마다의 셋과 7.x의 범용 드라이버)를 켜고(`-e` 열여덟), 따라 켜지는 것 일곱을 끈다(`-d`). `olddefconfig`로 되접는다(Task 1) | +473 −3 |
| `kernel/guest_firmware.sh` | 편집 셋 — 머리 주석 둘 · 목록 끝의 "소리 — Intel SOF" 절(firmware 19 · DRC 모듈 1 · topology 22) | +68 −4 |
| `kernel/vendor_firmware.sh` | 편집 다섯 — 머리 주석 · sof-bin의 버전 · URL · sha256 · 내려받기 · 출처 표에 `sof-bin` · `tar -xJf` → `tar -xf` | +18 −4 |
| `kernel/make_initrd.sh` | 편집 하나 — alsactl init의 postinit 규칙 파일(`Dmic0 Capture Switch`를 켠다) | +16 |
| `init/src/audio.zig` | 편집 아홉 — `-U` 주석 · 기본 카드 절이 `/dev/snd` 대신 `/proc/asound/pcm`을 읽고(`addNode` → `addPcmLine`), 녹음이 세 단(USB 마이크 · 내장 DMIC · 장치 0)을 고르고, 장치 0이 아닌 녹음은 `plughw:CARD=N,DEV=D`로 쓴다 | +113 −36 |
| `init/src/audio_test.zig` | 편집 넷 — 머리 주석 · 기본 카드 검사를 `/proc/asound/pcm` 줄로 · SOF · AMD · USB의 세 단 · 파일의 DMIC 글자 | +82 −15 |
| `audio/probe.sh` | 편집 둘 — 머리 주석 · `usb` 갈래 끝에 DSP 드라이버 등록 · 카드 0의 드라이버 · `dsp_driver` 파라미터 · 마이크 스위치 규칙 | +22 −1 |
| `audio/check.sh` | 편집 여섯 — 머리 주석 · 표식 둘 · 검사 1의 SOF · ACP 심볼과 음성 · alias · firmware 이름 대조 · initrd의 규칙 파일 · 검사 16 · 17 | +107 −3 |
| `check.sh` | 편집 하나 — `CHAINS`의 이름 `AU-M2` → `AU-M3` | +1 −1 |
| `tools/check.sh` | 편집 하나 — 검사 1b 머리 주석의 "무선" → "무선 · 소리" | +1 −1 |

합해서 10 files, +901 −68다. 새 파일은 없다. Dockerfile · `guest_tools.sh` · `main.zig` · `config.zig`(seed)는 안 바뀐다 — 이미지를
안 굽고(firmware는 `vendor_firmware.sh`가 GitHub의 sof-bin 릴리스에서 받는다), 게스트에 더 싣는 도구가 없고, `tars.conf`에 키가 없다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/au3/impl/` 아래에 둔다. `/tmp/run/au3/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도
lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다. 이미지는 M0의
`tars-devcontainer` 그대로다. 이 milestone은 이미지를 안 굽는다. 첫 빌드가 GitHub에서 sof-bin 17,555,075바이트를 한 번 받는다
(`kernel/src/firmware/`에 남고, 그 뒤로는 안 받는다 — linux-firmware와 같은 자리).

## 이 milestone이 끝나면

- 내장 디지털 마이크(DMIC)가 DSP에 붙은 Intel 노트북(Cannon Lake · Comet Lake ~ Panther Lake · Wildcat Lake, 코덱은 HDA)이 SOF로
  간다. 스피커 · 헤드폰은 같은 HDA 코덱 드라이버(M2)가 SOF 아래에서 받고, DMIC는 SOF 카드(`sof-hda-dsp`)의 장치 6으로 선다. firmware
  열아홉과 범용 topology 스물둘이 initrd 꼬리에 붙는다(sof-bin v2026.09.1). DMIC가 없는 Intel 노트북은 M2 그대로 `snd_hda_intel`이다.
- AMD Ryzen 노트북(Renoir · Yellow Carp/Rembrandt · ACP6.3 · ACP7.x)의 DMIC가 ACP의 PDM으로 카드 하나가 된다 — 6.3까지는 세대마다의
  드라이버, 7.x는 범용 ACP 드라이버와 legacy machine이다. firmware는 없다.
- 사람이 치는 `arecord x.wav`가 내장 마이크로 간다. `init`의 기본 카드 규칙이 녹음을 세 단으로 고른다 — 꽂힌 USB 마이크 · 헤드셋,
  없으면 내장 DMIC(SOF는 장치 6, AMD는 ACP 카드), 없으면 장치 0(M2 그대로). 재생은 M2 그대로다.
- 부팅이 DMIC 스위치를 켠다. SOF는 `Dmic0 Capture Switch`를 꺼진 채 올리고 alsactl의 범용 규칙은 그 이름을 모른다 — initrd의
  postinit 규칙 한 줄이 켠다. UCM(alsa-ucm-conf)은 싣지 않는다.
- SoundWire 코덱 노트북(`sof_sdw`)과 스피커 앰프 side codec(CS35L41 · CS35L56 · TAS2781)은 이 milestone 뒤에도 조용하다(확정 1).
- `audio` 체인은 부팅 넷 그대로이고 검사가 열일곱이 된다. 검사 1이 SOF · ACP의 심볼 · alias와 "커널이 찾는 SOF firmware 이름이
  전부 목록에 있다"를 보고, 부팅 D의 끝에서 검사 16(드라이버 등록 · QEMU의 HDA는 여전히 `snd_hda_intel` · 탈출로 파라미터)과
  검사 17(postinit 규칙이 `Dmic0 Capture Switch`를 켠다)을 본다.

로그 줄(정본 — `init/src/audio.zig`가 찍고 `audio/check.sh`가 이 글자를 본다). 사본의 부팅 D에서 뽑았다. M2의 줄은 글자 그대로다.

```
audio-probe: dsp drivers [snd_acp_pci|snd_pci_acp6x|snd_pci_ps|snd_rn_pci_acp3x|sof-audio-pci-intel-cnl|sof-audio-pci-intel-icl|sof-audio-pci-intel-lnl|sof-audio-pci-intel-mtl|sof-audio-pci-intel-ptl|sof-audio-pci-intel-tgl]
audio-probe: card 0 driver [snd_hda_intel]
audio-probe: dsp_driver [0]
audio-probe: dmic control made exit 0 [  : values=off]
audio-probe: dmic after init exit 99 [  : values=on]
```

녹음이 장치 0이 아닐 때의 `init` 줄(QEMU에는 없는 갈래 — 호스트 검사가 그 글자의 재료를 본다).

```
tars-init: audio: default card is 0 for playback, 0 (device 6) for capture      SOF 노트북
```

`/etc/asound.conf`의 글자(SOF 노트북 — 호스트 검사 `sof`가 손으로 적은 글자와 같다).

```
# tars-init이 쓴다(AU-M2 · M3). 사운드 카드가 오고 갈 때마다 다시 쓴다.
# 재생은 장치 0을 가진 카드 중 번호가 가장 큰 것, 녹음은 USB 마이크 · 내장 DMIC ·
# 그 밖의 장치 0 순으로 처음 있는 단에서 번호가 가장 큰 것이다.
# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.
pcm.!default {
	type asym
	playback.pcm {
		@func concat
		strings [ "sysdefault:CARD=" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default "0" } ]
	}
	capture.pcm {
		@func concat
		strings [ "plughw:CARD=" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default "0" } ",DEV=6" ]
	}
}
defaults.ctl.card 0
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 커널 소스(6.18.42의 `sound/hda/core/intel-dsp-config.c` · `i915.c` · `sound/soc/sof/` · `sound/soc/intel/boards/` ·
`sound/soc/amd/` · `sound/soc/sdca/` · `sound/core/pcm.c` · `sound/soc/soc-pcm.c` · `sound/usb/stream.c`), alsa-lib · alsa-utils ·
alsa-ucm-conf 1.2.14의 소스, linux-firmware-20260916과 sof-bin v2026.09.1의 목록을 읽어 정했고, 저장소 사본(`/tmp/run/au3/repo/`)과
M0 이미지(`tars-devcontainer`)로 쟀다. HEAD 쪽 대조는 같은 사본을 기준 파일로 되돌린 `/tmp/run/au3/head/`다. 측정 파일은
`/tmp/run/au3/meas/`(되접기 `kc_*.config` · `kfold.out` · `kbuild.out` · `modinfo_sound.txt`, 시간 `timing_head.log` · `timing_m3.log`,
체인 · regression 로그, 시리얼 `serial_*.log`, 내려받은 목록 `lf.list` · `sof.list` · `deb_sof_filelist.html`, 소스 `alsa-*-1.2.14/` ·
`ucm/`)에 있다. 저장소의 작업 트리는 이 plan 말고는 한 글자도 안 바뀌었다.

1. 범위 — DSP 뒤의 DMIC 중 "코덱은 HDA이고 DSP는 마이크만 받는" 노트북과 AMD의 PDM이다. SoundWire와 스피커 앰프는 넘긴다.

   2019년 이후 Intel 노트북의 내장 마이크는 둘 중 하나다. (a) 스피커 · 헤드폰은 HDA 코덱(Realtek 등)이 받고 DMIC만 DSP에 붙은
   노트북 — 커널은 이것을 SOF의 범용 machine(`skl_hda_dsp_generic`) 하나로 받고, topology는 이름 몇 개(`sof-hda-generic-*`)뿐이다.
   (b) 코덱까지 SoundWire(RT711 · RT1316 · CS42L43 …)인 노트북 — machine이 `sof_sdw`이고 SoundWire 버스 · 코덱 드라이버 열 남짓과
   기계마다 다른 topology(sof-bin의 `sof-tplg` 294개 · `sof-ipc4-tplg` 247개, 합해서 24MB)가 든다. AMD는 Renoir 이후 노트북의 DMIC를
   ACP의 PDM이 받고 firmware가 없다. 6.3까지는 세대마다 PCI 드라이버 하나와 machine 하나이고, 7.x(Ryzen AI 300 이후)는 범용 ACP
   드라이버(`snd_acp_pci`)와 legacy machine이 받는다(확정 2).

   | 갈래 | M2까지 | 이 milestone |
   |---|---|---|
   | Intel (a) HDA 코덱 + DMIC | DSP 표가 HDA로 보내 스피커 · 헤드폰은 되고 DMIC는 없다(design 결정 1) | 한다. SOF + 범용 machine + firmware · topology |
   | Intel (b) SoundWire 코덱 | 코덱이 HDA가 아니라 아무 소리도 없다 | 안 한다. 뒤에도 조용하다 — 나빠지지 않는다(커널에 `SOUNDWIRE`가 없어 DSP 표의 SoundWire 갈래가 안 선다) |
   | AMD ACP PDM(Renoir · Yellow Carp/Rembrandt · ACP6.3 · ACP7.x) | 스피커는 아날로그 HDA, DMIC는 없다 | 한다. 6.3까지는 세대마다 드라이버 + machine, 7.x는 범용 ACP 드라이버 + legacy machine. firmware 없음 |
   | AMD SOF(DMI 표에 오른 Rembrandt 이후 일부) | 같다 | 안 한다. firmware(`amd/sof/`)가 linux-firmware-20260916에도 sof-bin에도 없다. AMD는 DMI 표에 없는 기계를 PDM 드라이버로 보낸다(`acp-config.c`) |
   | side codec 스피커 앰프(CS35L41 · CS35L56 · TAS2781) | 내장 스피커가 조용하다(M2 확정 1) | 안 한다 |

   (b)와 앰프를 넘기는 이유. 둘 다 lead의 틀(M3에 `sof_sdw`)에 있었다. (b)는 machine이 기계마다의 코덱 조합이고 topology를 고르는
   근거가 기계마다의 ACPI 표라 "이름 몇 개"로 줄지 않는다 — 다 실으면 topology만 24MB이고, 고르면 실기 없이 고르는 것이다. 앰프는
   스피커 보호 firmware가 노트북 SSID마다 따로다(linux-firmware `cirrus/cs35l4*` · `cs35l5*` 674개 5,485,748바이트, `ti/` 310개
   12,047,190바이트). 둘 다 지금 조용한 기계를 조용한 채 두는 것이라 이 milestone이 나빠지게 만드는 기계가 없다. 이 둘을 빼서
   M3가 하루 크기가 됐다(아래 lead가 결정할 것 1).

2. 커널 — `-e` 열여덟, `-d` 일곱. 전부 `=y`다.

   ```
   -k
   -e SND_SOC -e SND_SOC_SOF_TOPLEVEL -e SND_SOC_SOF_PCI -e SND_SOC_SOF_INTEL_TOPLEVEL
   -e SND_SOC_SOF_HDA_LINK -e SND_SOC_SOF_HDA_AUDIO_CODEC -e SND_HDA_CODEC_HDMI -e SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH
   -e SND_SOC_AMD_RENOIR -e SND_SOC_AMD_RENOIR_MACH -e SND_SOC_AMD_ACP6x -e SND_SOC_AMD_YC_MACH -e SND_SOC_AMD_PS -e SND_SOC_AMD_PS_MACH
   -e SND_SOC_AMD_ACP_COMMON -e SND_SOC_AMD_ACP_PCI -e SND_AMD_ASOC_ACP70 -e SND_SOC_AMD_LEGACY_MACH
   -d SND_SOC_SOF_SKYLAKE -d SND_SOC_SOF_KABYLAKE -d SND_SOC_SOF_APOLLOLAKE -d SND_SOC_SOF_GEMINILAKE
   -d SND_SOC_SOF_MERRIFIELD -d SND_SST_ATOM_HIFI2_PLATFORM_ACPI -d SND_SOC_SDCA_HID
   ```

   `-k`. `scripts/config`는 기본으로 이름을 대문자로 바꾼다. `SND_SOC_AMD_ACP6x`의 `x`는 이름의 일부라 `-k` 없이 적으면
   `ACP6X`가 되고 `olddefconfig`가 조용히 버린다 — 첫 되접기에서 그렇게 AMD 둘이 빠졌다(지금의 `kc_amd.config`는 `-k`를 넣어 다시 접은 판이다).

   세대. `SND_SOC_SOF_PCI`를 켜면 세대마다의 심볼이 그것을 기본값으로 따라 켜진다(`sound/soc/sof/intel/Kconfig`). 그대로 두는 열하나와
   끄는 다섯이다.

   | 세대 심볼 | PCI 드라이버 | 기본 IPC · firmware | 어떻게 |
   |---|---|---|---|
   | CANNONLAKE · COFFEELAKE · COMETLAKE | `sof-audio-pci-intel-cnl` | IPC3 · `intel/sof/sof-cnl.ri` · `sof-cfl.ri` · `sof-cml.ri` | 둔다 |
   | ICELAKE · JASPERLAKE | `sof-audio-pci-intel-icl` | IPC3 · `sof-icl.ri` · `sof-jsl.ri` | 둔다 |
   | TIGERLAKE · ELKHARTLAKE · ALDERLAKE | `sof-audio-pci-intel-tgl` | IPC3 · `sof-tgl.ri` · `sof-tgl-h.ri` · `sof-ehl.ri` · `sof-adl.ri` · `sof-adl-s.ri` · `sof-adl-n.ri` · `sof-rpl.ri` · `sof-rpl-s.ri` | 둔다 |
   | METEORLAKE | `sof-audio-pci-intel-mtl` | IPC4 · `intel/sof-ipc4/{mtl,arl,arl-s}/` | 둔다 |
   | LUNARLAKE | `sof-audio-pci-intel-lnl` | IPC4 · `intel/sof-ipc4/lnl/` | 둔다 |
   | PANTHERLAKE | `sof-audio-pci-intel-ptl` | IPC4 · `intel/sof-ipc4/{ptl,wcl}/` | 둔다 |
   | SKYLAKE · KABYLAKE | — | AVS의 것 | 끈다. AVS가 꺼진 커널에서 DSP 표가 그 둘을 HDA로 묶는다(`intel-dsp-config.c`의 "force to legacy as SOF doesn't work for SKL or KBL") — 켜도 아무도 안 받는다 |
   | APOLLOLAKE · GEMINILAKE | — | — | 끈다. DSP 표가 SOF로 보내는 것은 UP 보드 · Chromebook · ES8336 I2S 코덱 기계뿐이고, 그 machine(`sof_es8336`)도 안 켠다 |
   | MERRIFIELD | — | — | 끈다. 태블릿(Tangier) |

   ELKHARTLAKE(임베디드)는 둔다. 끄려면 `-d` 하나지만, EHL의 PCI ID는 `pci-tgl.c`의 표에 함께 있어 그 이름(`sof-ehl.ri`)이 커널 안에
   남는다. "커널이 찾는 이름은 전부 싣는다"(확정 3)를 예외 없이 세우는 값이 firmware 하나(525,056바이트)다.

   나머지 `-e`. `SND_SOC_SOF_HDA_LINK` · `SND_SOC_SOF_HDA_AUDIO_CODEC`는 SOF 아래에서 HDA 코덱(M2의 Realtek 등)을 받는 자리이고,
   `SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH`가 그 코덱과 DMIC를 카드 하나로 묶는 범용 machine이다. 그 machine이 Kconfig에서
   `depends on SND_HDA_CODEC_HDMI`라서 HDMI 코덱을 함께 켠다 — `EXPERT`가 없어 Intel · ATI · NVIDIA · Tegra · simple 다섯이 다 켜진다
   (design 비목표 6은 그대로다 — HDMI로 소리를 내는 것은 GPU 드라이버가 없어 목표가 아니다).

   AMD. 넷이 같은 PCI ID(`1022:15e2`)를 두고 차례로 묻고, 자기 것이 아니면 `-ENODEV`로 물러난다. 무엇이 받는지는 ACP의 리비전과
   `snd_amd_acp_find_config`(`acp-config.c`)가 정한다 — 리비전 0x70 아래는 DMI 표(오른 것은 Google · Valve 기기뿐)이고 거기 없으면 0, 0x70
   이상은 BIOS의 ACPI 속성 `acp-audio-config-flag`이고 없으면 `FLAG_AMD_LEGACY_ONLY_DMIC`다.

   | 리비전 | 세대 | 0일 때 받는 것 | `LEGACY_ONLY_DMIC`일 때 받는 것 |
   |---|---|---|---|
   | 0x01 | Renoir 계열(ACP3.x) | `snd_rn_pci_acp3x` + `acp_pdm_mach` | — |
   | 0x60 · 0x6f | Yellow Carp/Rembrandt(ACP6.x) | `snd_pci_acp6x` + `acp_yc_mach` | — |
   | 0x63 | ACP6.3 | `snd_pci_ps` + `acp_ps_mach` | — |
   | 0x70 · 0x71 · 0x72 | ACP7.x | `snd_pci_ps` + `acp_ps_mach`(BIOS가 0을 줄 때) | `snd_acp_pci` + legacy machine(`acp-pdm-mach`) — 7.x의 기본 |

   그래서 7.x를 받으려면 범용 ACP 드라이버 넷(`SND_SOC_AMD_ACP_COMMON` · `ACP_PCI` · `SND_AMD_ASOC_ACP70` · `LEGACY_MACH`)이 든다. legacy
   machine이 Chromebook류의 I2C 코덱 일곱(RT5682 · RT5682S · RT1019 · MAX98357A · MAX98388 · NAU8825 · NAU8821)을 `select`한다 — I2C · ACPI
   드라이버로 등록만 되고, 그 코덱을 묶는 machine이 없는 기계에서는 카드가 안 선다. 이 넷이 bzImage에 더하는 것이 77,824바이트다.
   0x62(ACP6.2)는 받는 PDM 드라이버가 6.18에 없다 — `SND_SOC_AMD_RPL_ACP6x`는 그 리비전의 전원만 다룬다(`rpl/rpl-pci-acp6x.c`). 비목표다.

   GPU 드라이버가 없는 것이 왜 괜찮은가. HDMI 코덱이 켜지면 SOF가 probe에서 i915의 오디오 컴포넌트를 찾는다(`sof/intel/hda.c`의
   `hda_codec_i915_init`). 그 함수의 실체(`snd_hdac_i915_init`)는 `SND_HDA_I915`일 때만 서고, 그 심볼은 `DRM_I915` · `DRM_XE`만
   `select`한다. 이 커널에는 둘 다 없어 stub이 `-ENODEV`를 돌려주고 SOF는 HDMI 없이 계속 간다(`ret != -ENODEV`일 때만 멈춘다). 서
   있으면 GPU 드라이버가 안 올라오는 기계에서 `-EPROBE_DEFER`로 카드를 영영 안 만들 수 있다 — 그래서 체인의 검사 1이 `SND_HDA_I915`가
   꺼진 것을 본다.

   `-d SND_SST_ATOM_HIFI2_PLATFORM_ACPI`. `SND_SOC`를 켜면 `default ACPI`로 따라 켜지는 Bay Trail · Cherry Trail 태블릿의 SST다.
   `-d SND_SOC_SDCA_HID`. `SND_SOC`가 SoundWire Device Class(SDCA) 라이브러리를 끌고 오고, 그 아래 "잭 버튼을 HID로 알린다"가
   `default y`다. 이 커널에 SoundWire가 없어 실제로 돌 일은 없지만 M2가 `HID_APPLE` · `INPUT_LEDS`를 끈 것과 같은 원칙(소리 드라이버는
   입력을 안 건드린다)으로 끈다.

   되접은 `.config`는 +473 −3줄이다. `+CONFIG_` 101줄 — `=y` 100과 `SND_MAX_CARDS=32` — 이고 나머지 +372는 `# … is not set`과 메뉴
   주석(커널이 쓴다)이다. 지워지는 셋은 `SND_DYNAMIC_MINORS` · `SND_HDA_CODEC_HDMI` · `SND_SOC`의 `is not set`이다. 소리 밖에서 서는
   것은 `AUXILIARY_BUS` · `REGMAP_I2C` · `REGMAP_IRQ` 셋(기반 코드)뿐이고 입력 · 네트워크 · 전원 쪽은 없다. `HID_APPLE` · `INPUT_LEDS`는
   M2 그대로 꺼져 있다. `SND_DYNAMIC_MINORS`가 HDMI 코덱을 따라 켜지면서 카드 수의 상한(`SNDRV_CARDS`)이 8에서 32가 된다 —
   `init/src/audio.zig`의 `MAX_CARDS = 32`가 이제 커널과 같다(M2에서는 커널 쪽이 8이었다, `include/sound/core.h`).

   크기(증분 빌드, `kbuild.out`).

   | 단계 | bzImage | 늘어난 것 | 빌드 |
   |---|---|---|---|
   | M2 | 8,213,504 | — | — |
   | + ASoC · Intel SOF · HDMI 코덱 | 8,496,128 | +282,624 | 26초 |
   | + AMD 세대마다의 셋 | 8,508,416 | +12,288 | 19초 |
   | + AMD ACP7.x 범용 넷(최종) | 8,586,240 | +77,824 | 19초 |

   합해서 +372,736바이트(4.5%)다. `size`로 본 덩어리는 `sound/soc` 1,096,978(그중 SOF 342,901 · Intel machine 107,311 · AMD 159,991 ·
   ASoC 코덱 279,146) · HDMI 코덱 51,444바이트(text+data+bss, 압축 전)다. `inflate_fast`는 `ffffffff8147fb40` → `ffffffff8148db40`이고
   페이지 안 자리 `0xb40`이 그대로다(lessons PD-3, 확정 9).

3. firmware — 출처는 sof-bin 릴리스, 목록은 커널이 찾는 이름 전부와 범용 topology.

   linux-firmware-20260916에는 Intel SOF가 없다(`mediatek/sof*`뿐, WHENCE에 Intel SOF 항목이 없다). Intel이 서명한 SOF firmware와
   topology는 SOF 프로젝트의 sof-bin 릴리스가 내고, 배포판 패키지(Debian `firmware-sof-signed`, Arch `sof-firmware`)가 그것을 담는다.

   | 후보 | 왜 아닌가 |
   |---|---|
   | (a) sof-bin v2026.09.1 tarball을 `vendor_firmware.sh`가 받는다(버전 · sha256 고정) | 고른 것. linux-firmware와 같은 길이라 이미지를 안 굽고(Dockerfile 그대로) `guest_firmware.sh`의 형식에 출처 하나(`sof-bin/`)만 는다. sha256은 GitHub 릴리스 자산의 digest(`42ce40ec…79b73`)와 내려받은 파일이 같았다 |
   | (b) Debian trixie `firmware-sof-signed`(2025.01-1)를 Dockerfile이 받는다(lead의 틀) | Panther Lake · Wildcat Lake의 firmware가 없다(`intel/sof-ipc4/` 아래가 adl · adl-n · adl-s · arl · arl-s · ehl · lnl · mtl · rpl · rpl-s · tgl · tgl-h뿐 — packages.debian.org의 파일 목록). 커널 6.18은 그 둘을 켠다. 그리고 이미지를 다시 구워야 한다 |
   | (c) linux-firmware를 올린다 | 들어 있지 않으니 올려도 없다 |

   firmware가 없을 때 무슨 일이 나나(lead가 짚은 위험, 커널 소스로 확인). DMIC(ACPI NHLT의 PDM 끝점)가 있는 Intel 노트북은
   `intel-dsp-config.c`가 HDA 대신 SOF를 고르고 `snd_hda_intel`은 그 컨트롤러를 놓는다. 그 뒤 SOF가 firmware나 topology를 못 찾으면
   `sof_create_ipc_file_profile`이 `SOF firmware and/or topology file not found.`를 찍고 probe가 끝난다 — HDA로 돌아오는 길은 없다.
   M2까지 되던 스피커와 헤드폰까지 조용해진다는 뜻이다. 그래서 셋을 둔다.

   - 켜는 세대마다 기본 IPC의 firmware를 싣는다. 체인의 검사 1이 커널 이미지와 SOF Intel 드라이버의 오브젝트에 함께 있는 `sof-*.ri`
     이름(지금 19개)을 전부 목록의 initrd 경로 끝에서 찾는다 — 커널을 올리거나 세대를 하나 더 켜면 여기서 걸린다. 이미지만 보지 않는
     이유는 AMD SOF용 machine 표(`sound/soc/amd/acp-config.c`의 `sof-rn` · `sof-rmb` · `sof-vangogh`)가 이미지에 들어 있기 때문이다 —
     AMD SOF 드라이버는 꺼져 있어 아무도 그 이름을 안 찾는다.
   - topology는 범용 machine이 짓는 이름을 다 싣는다. `sof/intel/hda.c`가 "sof-hda-generic"에 (HDMI 코덱뿐이면) "-idisp"와 (NHLT의
     DMIC 수 N이면) "-Nch"를 붙인다. 이름으로 날 수 있는 것이 IPC3 쪽 여덟(`intel/sof-tplg/`), IPC4 쪽 일곱(MTL · ARL은
     `intel/sof-ace-tplg/`, LNL 이후는 `intel/sof-ipc4-tplg/` — sof-bin 안에서 같은 디렉터리라 같은 원본이 두 자리로)이다. IPC4 쪽에
     `-3ch`는 sof-bin에 없다 — DMIC 셋인 MTL 이후 노트북은 topology를 못 찾는다(위험).
   - 탈출로. 실기에서 SOF가 실패하면 커널 인자 `snd_intel_dspcfg.dsp_driver=1`이 DSP 표를 무시하고 HDA로 보낸다(그 노트북은 M2처럼
     스피커 · 헤드폰은 되고 DMIC는 없다). 그 파라미터 자리가 커널에 있는 것을 부팅 D가 본다(검사 16).

   목록은 42줄이고 무선과 합해 77 → 119다.

   | 무엇 | 줄 | 원본 바이트 |
   |---|---|---|
   | firmware(IPC3 열셋 · IPC4 여섯, intel-signed만 — community 서명은 Chromebook · UP 보드의 것이다, `sof-pci-dev.c`) | 19 | 12,750,280 |
   | LNL의 DRC 모듈(`intel/sof-ipc4-lib/lnl/B36EE4DA-….bin`, topology가 UUID로 부른다) | 1 | 57,452 |
   | topology(`sof-hda-generic*`) | 22 | 893,316 |
   | 합 | 42 | 13,701,048 |

   sof-bin 안의 링크(cfl · cml → cnl, rpl → adl, rpl-s → adl-s, arl → mtl)는 실체를 가리켜 적는다 — `tar -T`는 링크를 풀 뿐 대상을
   따라가지 않는다. firmware cpio(gzip -6)는 38,788,577 → 45,029,489바이트(+6,240,912)다.

4. 녹음의 기본 장치 — 세 단. `init`이 `/proc/asound/pcm`을 읽는다.

   SOF 카드의 장치 0 녹음은 헤드셋 잭이고 DMIC는 장치 6("DMIC (*)")이다(topology의 PCM 표 — `sof-hda-generic-2ch.tplg`에 `HDA Analog 0` ·
   `DMIC 6` · `DMIC16kHz 7` · `HDMI1 3` …). M2의 규칙("장치 0을 가진 카드 중 번호가 가장 큰 것")대로면 `arecord`가 아무것도 안 꽂힌
   잭을 듣는다. AMD는 DMIC가 따로 카드 하나(ACP, 녹음만 장치 0)이고 아날로그 HDA 카드도 장치 0에 녹음(잭)이 있다 — 둘 중 어느 쪽이
   큰 번호일지는 probe 순서라 정해져 있지 않다. 그래서 녹음만 세 단을 차례로 보고 처음 걸리는 단에서 번호가 가장 큰 카드를 고른다.

   | 단 | 무엇 | 어떻게 알아보나 |
   |---|---|---|
   | 1 | 꽂힌 USB 마이크 · 헤드셋(장치 0) | 녹음 PCM의 id가 `USB Audio`로 시작한다 — snd-usb-audio가 언제나 그렇게 짓는다(`sound/usb/stream.c`) |
   | 2 | 내장 DMIC(그 PCM의 장치) | 녹음 PCM의 id에 `DMIC`(대소문자 무관)가 든다. SOF는 `DMIC (*)`(ASoC의 동적 FE가 `"%s (*)"`), AMD 넷은 `DMIC capture dmic-hifi-N`(`"%s %s-%d"`, stream_name이 넷 다 `DMIC capture`이고 N은 링크 번호 — 세대마다의 셋은 0). 둘 이상이면 가장 작은 장치(SOF의 6, 16kHz인 7이 아니라) |
   | 3 | 그 밖의 장치 0 녹음 | M2 그대로. QEMU의 HDA, DMIC 없는 노트북의 아날로그 마이크 |

   재생은 M2 그대로다(SOF의 장치 0이 `HDA Analog` 재생이다).

   | 후보 | 왜 아닌가 |
   |---|---|
   | (a) 세 단 | 고른 것 |
   | (b) M2 그대로 | SOF 노트북의 `arecord`가 잭을 듣는다 — 이 milestone의 목적(내장 마이크)이 사람이 치는 명령으로는 안 닿는다 |
   | (c) DMIC를 언제나 먼저 | 사람이 일부러 꽂은 USB 헤드셋 마이크를 내장 DMIC가 이긴다. VD(받아쓰기)를 헤드셋으로 하는 사람에게 틀린 기본이다 |
   | (d) UCM에 맡긴다 | alsa-lib의 `default`는 UCM을 안 본다. UCM의 장치 선택을 쓰는 것은 PipeWire · PulseAudio다(확정 5) |
   | (e) `tars.conf` 키 | 기계마다 장치 번호를 사람이 알아야 한다. seed가 한 줄 늘어 `config` 체인을 함께 봐야 한다(lessons 이월 숙제) |

   읽는 자리. M2는 `/dev/snd`의 이름(`pcmC0D0c`)을 셌다. 이름에는 PCM의 id가 없으므로 `/proc/asound/pcm` 한 파일로 바꾼다 — 커널의
   `snd_pcm_proc_read`가 `CC-DD: id : name : playback N : capture N`을 쓰고(있는 방향만), 내부 PCM(BE 링크의 `(dmic01)` 같은 것)은
   procfs에 안 나온다(`snd_pcm_new_internal`). 감독 루프의 1초 바퀴에 `open` · `read` · `close`이고 M2의 `getdents64`와 같은 값이다.
   소리 장치가 없는 기계는 파일이 비어 있어 M2처럼 한 줄도 안 찍고 파일도 안 쓴다.

   파일의 글자. 장치 0이면 M2의 `sysdefault:CARD=N` 그대로다(QEMU의 체인 글자가 안 바뀐다). 장치 0이 아니면 `plughw:CARD=N,DEV=D`다 —
   `sysdefault`는 장치 0만 연다. SOF · ACP 카드에는 alsa-lib의 카드 설정(`cards/*.conf`)이 없어서 그 카드의 `sysdefault`도 원래
   `plug` → `hw`다(`pcm/default.conf`의 `default` 갈래). 섞기(dsnoop)가 없는 것은 장치 0일 때와 같다 — 두 프로그램이 동시에 DMIC를
   열면 둘째가 `Device or resource busy`다(위험). env(`ALSA_CARD`)는 M2처럼 카드 번호 자리만 바꾼다.

   로그. 장치 0이면 M2의 글자 그대로(`default card is 0 for playback, 0 for capture`), 아니면 `0 (device 6) for capture`다.

5. UCM은 싣지 않는다. `-U`는 그대로이고, 내장 마이크 스위치는 alsactl init의 postinit 규칙 한 줄이 켠다.

   SOF는 topology의 스위치 컨트롤을 꺼짐(0)으로 올린다(`ipc3-topology.c`의 switch 갈래는 값을 안 넣고, `ipc4-topology.c`는 "off (0) for
   switch controls"라고 적어 둔다). 볼륨은 0dB다(`VOL_ZERO_DB`). DMIC의 스위치 이름은 IPC3 · IPC4 모두 `Dmic0 Capture Switch`다 — IPC4
   topology에는 그 글자 그대로, IPC3 topology에는 위젯 `Dmic0`과 컨트롤 `Capture Switch`로 있고 ASoC가 위젯 이름을 앞에 붙인다. alsactl의
   범용 규칙(`init/default`)은 이름이 정확히 `Capture Switch`인 것만 켜므로(`do_search`의 `ctl_match`) 그대로 두면 `arecord`가 0만 받는다.

   | 후보 | 왜 아닌가 |
   |---|---|
   | (a) `/usr/share/alsa/init/postinit/00-tars-dmic.conf` 한 줄 | 고른 것. postinit은 alsactl init이 카드마다 표준 규칙 뒤에 읽는 자리다(`init/00main`). 이름이 없는 카드에서는 건너뛰고(`CTL{do_search}=="1"`), 99로 끝나는 범용 길도 그대로다 |
   | (b) alsa-ucm-conf를 싣고 `-U`를 뺀다(lead가 물은 것, Debian의 길) | sof-hda-dsp의 부팅 순서가 `Dmic0`을 70%로 켜지만 같은 파일이 `/HDA/init.conf`를 include하고, 그것이 `Speaker Playback Switch off` · `Headphone Playback Switch off` · `Master 60%`다 — 장치를 켜는 것은 사운드 서버(PipeWire)의 몫으로 본다. 우리에게 그것이 없어 SOF 노트북의 스피커가 꺼진다. 그리고 UCM이 성공한 카드는 alsactl이 범용 init을 건너뛴다(`init_parse.c`의 `init`). 범용 HDA 카드는 `HDA.conf`가 "UCM is not supported for this HDA model"로 물러나지만 ACP 카드가 있는 AMD 노트북에서는 그 HDA 카드에도 위 순서가 붙는다. 트리는 파일 572개 564,160바이트이고 부팅 순서가 `/bin/rm` · `/bin/mkdir` · `nhlt-dmic-info`를 부른다 |
   | (c) 프로브처럼 `init`이 `amixer cset`을 한 번 더 부른다 | 일꾼이 alsactl 하나가 아니라 둘을 띄워야 하고 M1의 끝 읽기(`reaped`)가 바뀐다. (a)는 alsactl 안에서 끝난다 |
   | (d) control 노드에 ioctl을 직접 | M1이 버린 길이다(M1 plan 확정 1) |

   이 규칙은 일꾼이 `alsactl init`을 부를 때(첫 부팅 · `/config` 없음)와 `restore`가 파일에 없는 카드를 init으로 내려갈 때 돈다. 한
   번 켜진 스위치는 끌 때의 `alsactl store`가 `/config/asound.state`에 적어 다음부터는 restore가 되살린다 — 사람이 `amixer`로 끈 것도
   그대로 남는다. 볼륨은 커널의 0dB 그대로 둔다(UCM은 70%로 둔다 — 실기에서 크거나 작으면 사람이 `amixer`로 맞추고 그 값이 남는다).

   QEMU에서 본다. QEMU의 코덱에는 `Dmic0` 컨트롤이 없으므로 부팅 D의 프로브가 같은 이름의 사용자 컨트롤을 꺼진 채 하나 만들고
   (`alsactl -I restore`가 접근에 `user`가 든 항목을 만든다 — `state.c`), 일꾼과 같은 argv(`-U init`)로 다시 init해 켜지는 것을
   본다(검사 17). 사본에서 `dmic control made exit 0 [  : values=off]` → `dmic after init exit 99 [  : values=on]`였다.

6. 호스트 검사. `audio_test`의 기본 카드 절이 `/proc/asound/pcm`의 줄을 먹는다. QEMU의 HDA + USB 스피커(M2의 판정 그대로 재생 1 · 녹음
   0), 장치 0이 아니거나 모양이 다른 줄 여덟(카드 32 · 숫자 아닌 카드 · `card 0: …`(aplay -l의 줄) …)을 안 세는 것, SOF 노트북(녹음 0의
   장치 6), SOF + USB 헤드셋(녹음 1의 장치 0 — 꽂은 것이 이긴다), SOF + USB 스피커(녹음은 DMIC에 남는다), AMD 두 차례(ACP가 2번이든
   1번이든 녹음은 ACP), 파일의 글자 넷(M2 셋에 SOF의 `plughw:CARD=…,DEV=6`)을 손으로 적은 글자와 비교한다. SOF · AMD의 줄은 커널의
   `snd_pcm_proc_read` 모양에 그 드라이버들이 짓는 id를 넣은 것이다(QEMU에 그 장치가 없다). 사본에서 `zig build test`가 exit 0이고
   `audio_test:` 아홉 줄이 다 돌았다.

7. 체인. 부팅 넷 그대로, 검사 열일곱.

   | 검사 | 부팅 | 본다 | 사본의 값 |
   |---|---|---|---|
   | 1 | 없음 | M2 그대로에 더해 SOF · ACP 심볼 스물여덟이 `=y`, 꺼져 있어야 하는 일곱(SKL · KBL · APL · GLK · Merrifield · Atom SST · `SND_HDA_I915`), modinfo alias 열넷(SOF PCI 일곱 — CML · ICL · TGL · ADL · MTL · LNL · PTL, 범용 machine, Renoir PCI, 범용 ACP PCI, AMD machine 넷), 커널의 `sof-*.ri` 이름 열아홉이 전부 목록에 있다, initrd의 `init/00main`과 규칙 파일 | `the kernel carries SOF for 19 Intel firmware names and AMD ACP, …` |
   | 2 ~ 15 | A ~ D | M2 그대로 | `tone=48000 … other=0` · `match=96000` · `cap D: frames=48000 match=48000` |
   | 16 | D | PCI 버스에 SOF 여섯 · AMD 넷이 등록됐다 · QEMU의 HDA(ICH9)는 여전히 `snd_hda_intel` · `snd_intel_dspcfg.dsp_driver`가 있고 0이다 | 초록 |
   | 17 | D | 사용자 컨트롤 `Dmic0 Capture Switch`(꺼짐)가 `alsactl -U init` 뒤에 켜진다(99) | 초록 |

   AMD 둘(`snd_pci_acp6x` · `snd_pci_ps`)은 PCI 표가 modinfo에 alias로 안 나온다(Renoir와 범용 ACP만 나온다) — 그 둘은 machine의
   platform alias와 검사 16의 PCI 등록으로 본다. QEMU의 컨트롤러가 SOF 뒤에도 `snd_hda_intel`인 것은 ICH9(`8086:293e`)가 DSP 표에 없어서이고, 위 검사
   2 ~ 15가 그 카드로 도는 것이 regression의 판정이다. 부팅 D에서 프로브가 `alsactl -U init 0`을 한 번 더 부르므로 HDA의 Master가
   -20dB로 돌아가는데, 소리를 보는 검사가 다 끝난 뒤라 판정에 안 닿는다.

8. 시간. firmware cpio를 다시 만드는 첫 판이 2분 10초(linux-firmware를 다시 풀고, 커널은 이미 빌드된 것), `init` · terminal 캐시를
   지운 판이 2분 5초, 데운 판이 44초였다(M2의 40 · 41초에 검사 16 · 17의 2초 남짓과 늘어난 initrd). 루트 게이트는 이 체인을 두 번
   돌리고 다른 체인도 initrd가 커진 만큼 조금씩 늦으므로 M2의 게이트에 1분 안팎을 더한 것으로 본다. 커널 증분 빌드는 사본에서 세 단계 합 64초였다(한 번에 하면 그보다 짧다).

9. 커널 코드 배치 · initrd · 메모리(lessons PD-3, design 위험 1). HEAD(M2)와 M3를 같은 컨테이너에서 나란히 쟀다(`timing.sh` — render
   체인과 같은 QEMU 호출 셋, `install` 체인 둘, 그리고 부팅 D의 프로브 머리에서 `MemAvailable` 세 판씩).

   | | bzImage | `inflate_fast` | initrd(gzip) | 다 푼 크기 | `Run /init` 세 판 | `install` 부팅 7의 `init waited` | `MemAvailable` |
   |---|---|---|---|---|---|---|---|
   | HEAD(M2) | 8,213,504 | `ffffffff8147fb40` | 90,619,917 | 233,298,432 | 3.05 · 3.06 · 3.03초 | 1,800 · 1,900ms | 192,664 · 190,296 · 192,504kB |
   | M3 | 8,586,240 | `ffffffff8148db40` | 96,869,254 | 247,030,784 | 3.22 · 3.20 · 3.20초 | 1,700 · 1,700ms | 184,436 · 184,532 · 182,276kB |

   `inflate_fast`가 페이지 안 같은 자리(`0xb40`)라 풀기의 속도는 그대로이고, `Run /init`의 +0.16초는 풀 바이트가 늘어난 몫이다
   (initramfs를 다 푸는 시각이 3.00 → 3.16초). `init waited`의 여유가 100 ~ 200ms 줄었고 하한(500ms)의 세 배가 넘게 남는다. 다 푼
   크기가 13.7MB(firmware 원본) 늘었고 512MB 게스트의 `MemAvailable`은 8MB 남짓 줄었다(판마다 2MB쯤 흔들린다 — lessons 이월 숙제
   "firmware가 게스트 RAM에 늘 있다"가 커졌다). 중간 판(ACP7.x 넷 전)의 커널로 잰 첫 판이 177,532kB였는데 같은 커널을 다시 재지 않아
   흔들림인지 가리지 못했다 — 표의 M3 세 판은 최종 커널이다.

10. mutation. 다섯 가지를 여섯 판(대조군 하나 포함)으로 체인에서, 셋을 호스트 검사에서 돌렸다(`/tmp/run/au3/make_mut.py` · `run_mut.sh`,
    로그는 `/tmp/run/au3/mut/`). 앞 검사가 먼저 잡는 것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다(lessons
    "mutation이 겨냥한 검사에 걸릴 것이라고 믿기"). 커널 둘은 `.config` 사본을 덮고 `build.sh`가 다시 빌드하며, 목록 하나는
    `vendor_firmware.sh`가 cpio를 다시 만든다.

    | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
    |---|---|---|---|---|---|
    | (대조군) | `m0` | 없음 | — | `AU check PASS` | 64초 |
    | K1 세대 하나(Tiger Lake)를 끈다 | `k1` | `config_k1` | 검사 1 | `FAIL: CONFIG_SND_SOC_SOF_TIGERLAKE is not =y in kernel/.config` | 44초 |
    | K2 끈 채 둘 세대(Skylake)가 켜진다(`-d`를 빠뜨린 판) | `k2` | `config_k2` | 검사 1의 음성 | `FAIL: CONFIG_SND_SOC_SOF_SKYLAKE is on; AU-M3 keeps it off` | 45초 |
    | F1 firmware 목록에서 `sof-tgl.ri` 한 줄이 빠진다 | `f1` | `guest_firmware_f1.sh` | 검사 1의 이름 대조 | `FAIL: the kernel asks for sof-tgl.ri but kernel/guest_firmware.sh does not carry it` | 51초 |
    | P1 `make_initrd.sh`가 postinit 규칙을 안 쓴다 | `p1` | `make_initrd_p1.sh` | 검사 1의 initrd 목록 | `FAIL: usr/share/alsa/init/postinit/00-tars-dmic.conf is missing from the initrd` | 33초 |
    | | `p1_boot` | + `check_no1dmic.sh` | 검사 17 | `FAIL: alsactl init did not turn Dmic0 Capture Switch on; the postinit rule is missing or wrong` | 63초 |

    합해서 5분 0초다. 호스트 검사 mutation 셋(`audio.zig`를 사본으로 바꿔 `zig build test`).

    | mutation | `FAIL` 줄 |
    |---|---|
    | Z1 녹음의 둘째 단(내장 DMIC)이 없다 — M2의 규칙으로 돌아간다(`audio_z1.zig`) | `FAIL: a SOF laptop picks playback 0 capture 0:0, want 0 and 0:6` |
    | Z2 첫째 단(USB 마이크)이 없다 — 꽂은 헤드셋보다 내장 DMIC가 이긴다(`audio_z2.zig`) | `FAIL: a SOF laptop with a USB headset picks playback 1 capture 0:6, want 1 and 1:0` |
    | Z3 장치 0이 아닌 녹음도 `sysdefault`로 쓴다(`audio_z3.zig`) | `FAIL: sof rendered`(뒤에 그 글자와 기대 글자가 이어진다) |

    읽을 것 둘.
    - Z1 · Z2 · Z3은 체인이 못 잡는다 — QEMU에 DMIC PCM이 없어 체인의 녹음은 언제나 셋째 단이다. 녹음 규칙의 판정은 호스트 검사뿐이다.
    - 커널 판(`k*`)은 `kernel/build`를, 목록 판(`f1`)은 firmware cpio를 다른 입력으로 만들어 두지만, 뒤 판이 지금 파일로 다시 만든다. 되돌림
      판(5-4)에서 둘 다 `skipping`이었고 `inflate_fast`가 `ffffffff8148db40`로 그대로였다(1분 3초). 이 표는 최종 파일로 다시 돈 것이고, ACP7.x
      넷을 더하기 전에 한 판(4분 59초)도 같은 여섯 줄이었다.

11. regression. 커널(SOF · ASoC · HDMI 코덱 · AMD)과 initrd(firmware +6.2MB · 규칙 파일)와 `init`의 감독 루프(`/proc/asound/pcm`)가
    바뀌므로 아홉을 사본에서 돌렸다.

    | 체인 | 시간 | 왜 돌렸나 |
    |---|---|---|
    | `install` | 108 · 107초 | 커널이 바뀌면 부팅 7의 창이 움직인다(PD-3). `init waited 1700ms for the late USB disk` 두 판 |
    | `tools` | 65초 | firmware 목록이 77 → 119. `all 92 tools` · `all 119 files the list names` |
    | `boot` | 25초 | limine이 BIOS로 bzImage · initrd를 읽는다. initrd가 6.2MB 커졌다 |
    | `machine` | 18초 | q35 · OVMF · simpledrm. 새 커널이 실기의 길에서 뜨는가 |
    | `wifi` | 97초 | 같은 firmware cpio에 무선이 그대로 있고, hwsim · usbcore 등록 열하나가 그대로다 |
    | `pointer` | 75초 | 입력 쪽(`SND_SOC_SDCA_HID`를 끈 채, `HID_APPLE` · `INPUT_LEDS` 그대로)과 USB 핫플러그 |
    | `nic` | 32초 | 커널이 바뀐 뒤의 유선 드라이버 · `-nic none` |
    | `power` | 50초 | 감독 루프의 `audio.follow()`가 이제 procfs를 읽는다. 끄는 길과 되살리는 길이 그대로다 |
    | `service` | 73초 | 감독 루프 · `tars-service`가 그대로다 |

    아홉 다 exit 0이고 `install` 밖의 여덟이 합해서 7분 15초다(`install`은 확정 9의 두 판). ACP7.x 넷을 더하기 전의 커널로도 한 번 돌아
    아홉 다 초록이었다(7분 23초).

12. 낡은 산출물. 이 milestone은 Zig 코드 · 커널 설정 · firmware 목록을 고친다. `init`의 캐시 삭제는 같은 `docker run` 안에 둔다
    (`project_zig_out_staleness`). 커널은 `build.sh`의 sha256 스탬프가 `.config`를, firmware cpio는 `vendor_firmware.sh`의 스탬프가
    `guest_firmware.sh` · `vendor_firmware.sh`를 보고 다시 만든다.

13. 앵커. 편집 서른둘의 `old_string`이 M2 commit의 파일에 정확히 한 번씩 있고(`python3 /tmp/run/au3/anchors.py pre "$PWD"` →
    `pre: 32 edits, 0 bad`), `new_string`이 사본에 정확히 한 번씩 있다(`post: 32 edits, 0 bad`). 진입 검사 셋도 사본의 `audio/check.sh`에서
    `ENTRY-OK`였다. main 작업 트리의 열 파일이 `/tmp/run/au3/base/`와 바이트까지 같다(lead의 M2 commit `cd9c12e` 뒤에 대조).

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

   기대: 맨 위 commit이 `cd9c12e AU-M2: Laptop HDA codecs, USB audio, …`이거나 그 위에 lead의 문서 commit이 있다. `git status`는 이
   plan이 commit 전이면 그것 하나이고, lead가 고치는 중일 수 있는 design · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/`가
   더 있을 수 있다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.

3. 편집의 앵커와 기준 파일을 본다(확정 13).

   ```bash
   python3 /tmp/run/au3/anchors.py pre "$PWD"
   for f in kernel/.config kernel/guest_firmware.sh kernel/vendor_firmware.sh kernel/make_initrd.sh init/src/audio.zig \
     init/src/audio_test.zig audio/probe.sh audio/check.sh check.sh tools/check.sh; do
     cmp $f /tmp/run/au3/base/$f && echo "BASE $f"; done
   ```

   기대: `pre: 32 edits, 0 bad`와 `BASE` 열. 하나라도 다르면 그 파일을 보고하고 멈춘다 — 앵커를 다시 뽑아야 한다.

## Task 1: `kernel/.config` — SOF · ACP, 따라 켜지는 일곱은 끈 채

확정 2. M2 plan Task 1과 같은 모양이다 — 적고, 빌드하고(`build.sh`가 `olddefconfig`를 친다), 되접은 것을 다시 넣고, 한 번 더
빌드해 고정점인지 본다. `-k`가 맨 앞에 있어야 한다 — `scripts/config`는 기본으로 심볼 이름을 대문자로 바꾸는데 `SND_SOC_AMD_ACP6x`는
소문자 `x`가 이름의 일부다(빼면 `ACP6X`가 되어 조용히 사라진다, 확정 2). 증분이라 3분 안팎이다.

```bash
mkdir -p /tmp/run/au3/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
    kernel/src/linux-6.18.42/scripts/config --file kernel/.config -k \
      -e SND_SOC -e SND_SOC_SOF_TOPLEVEL -e SND_SOC_SOF_PCI -e SND_SOC_SOF_INTEL_TOPLEVEL \
      -e SND_SOC_SOF_HDA_LINK -e SND_SOC_SOF_HDA_AUDIO_CODEC -e SND_HDA_CODEC_HDMI -e SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH \
      -e SND_SOC_AMD_RENOIR -e SND_SOC_AMD_RENOIR_MACH -e SND_SOC_AMD_ACP6x -e SND_SOC_AMD_YC_MACH \
      -e SND_SOC_AMD_PS -e SND_SOC_AMD_PS_MACH \
      -e SND_SOC_AMD_ACP_COMMON -e SND_SOC_AMD_ACP_PCI -e SND_AMD_ASOC_ACP70 -e SND_SOC_AMD_LEGACY_MACH \
      -d SND_SOC_SOF_SKYLAKE -d SND_SOC_SOF_KABYLAKE -d SND_SOC_SOF_APOLLOLAKE -d SND_SOC_SOF_GEMINILAKE \
      -d SND_SOC_SOF_MERRIFIELD -d SND_SST_ATOM_HIFI2_PLATFORM_ACPI -d SND_SOC_SDCA_HID
    (cd kernel && ./build.sh > /tmp/k1.log 2>&1); echo "build 1 exit=$?"
    cp kernel/build/.config kernel/.config
    (cd kernel && ./build.sh > /tmp/k2.log 2>&1); echo "build 2 exit=$?"
    diff kernel/.config kernel/build/.config && echo FOLDED
    stat -c "%s bzImage" kernel/build/arch/x86/boot/bzImage
    grep " inflate_fast$" kernel/build/System.map' ; } 2>&1 | tail -8
rmdir /tmp/run/docker.lock
```

기대: `build 1 exit=0` · `build 2 exit=0` · `FOLDED` · `8586240 bzImage` · `ffffffff8148db40 T inflate_fast`.

```bash
cmp kernel/.config /tmp/run/au3/new/kernel/.config && echo SAME-config
git diff --stat kernel/.config
git diff kernel/.config | rg '^[-+]CONFIG' | rg -v 'is not set'
git diff kernel/.config | rg '^-' | rg -v '^---'
```

기대: `SAME-config`, `+473 −3`, `+CONFIG_…` 101줄(확정 2의 =y 100과 `SND_MAX_CARDS=32`), 지워지는 줄은 `# CONFIG_SND_DYNAMIC_MINORS is not set` ·
`# CONFIG_SND_HDA_CODEC_HDMI is not set` · `# CONFIG_SND_SOC is not set` 셋뿐이다. `SND_SOC_AMD_ACP6x=y` · `SND_SOC_AMD_YC_MACH=y`가 없으면
`-k`가 빠진 것이다. `SND_SOC_SOF_SKYLAKE` · `SND_SOC_SDCA_HID` 같은 `-d`의 일곱 중 하나라도 `=y`로 보이면 멈추고 보고한다.

## Task 2: firmware 목록과 내려받기, initrd의 규칙 파일

확정 3 · 5.

### 2-1. `kernel/guest_firmware.sh` — 편집 셋

E1 — `old_string`(기준 파일 1줄부터):

```bash
# 게스트에 들어가는 무선 firmware 목록 — 이것이 사는 유일한 자리다(WL-M1).
```

`new_string`:

```bash
# 게스트에 들어가는 무선 · 소리 firmware 목록 — 이것이 사는 유일한 자리다(WL-M1 ·
# AU-M3).
```

E2 — `old_string`(기준 파일 11줄부터):

```bash
# 출처는 둘이다. linux-firmware와 wireless-regdb — 버전은 이름에 없고
# vendor_firmware.sh에 있다. 둘이 다를 수 있는 것이 이 형식의 이유다(WL design
# 실측 3). iwlwifi 파일은 tarball 안에서 intel/iwlwifi/에 있는데 드라이버는
```

`new_string`:

```bash
# 출처는 셋이다. linux-firmware와 wireless-regdb, 그리고 sof-bin(AU-M3) — 버전은
# 이름에 없고 vendor_firmware.sh에 있다. 둘이 다를 수 있는 것이 이 형식의 이유다(WL
# design 실측 3). iwlwifi 파일은 tarball 안에서 intel/iwlwifi/에 있는데 드라이버는
```

E3 — `old_string`(기준 파일 131줄부터):

```bash
  wireless-regdb/regulatory.db.p7s:lib/firmware/regulatory.db.p7s
```

`new_string`:

```bash
  wireless-regdb/regulatory.db.p7s:lib/firmware/regulatory.db.p7s

  # ── 소리 — Intel SOF(AU-M3) ─────────────────────────────────────────────
  #
  # 내장 디지털 마이크(DMIC)가 있는 Intel 노트북은 커널이 HDA 대신 SOF로 간다
  # (sound/hda/core/intel-dsp-config.c). 그때 firmware나 topology가 없으면 SOF는
  # HDA로 돌아오지 않고 카드를 아예 안 만든다 — 스피커까지 조용해진다. 그래서 커널이
  # 켠 세대마다 그 이름이 여기 있어야 하고, audio 체인의 검사 1이 커널 안의 이름
  # (`sof-*.ri`)을 전부 이 목록에서 찾는다.
  #
  # firmware. 세대마다 기본 IPC가 정한 자리 하나다 — CNL ~ RPL은 IPC3이라
  # intel/sof/, MTL 이후는 IPC4라 intel/sof-ipc4/<세대>/. sof-bin 안의 링크(cfl ·
  # cml → cnl, rpl → adl, arl → mtl)는 실체를 가리켜 적는다(tar -T가 링크의 대상을
  # 안 따라간다). intel-signed만 넣는다 — community 서명은 Chromebook과 UP 보드의
  # 것이다(sof-pci-dev.c). LNL은 topology가 부르는 DRC 모듈이 따로 있다(UUID 이름).
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cnl.ri
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cfl.ri
  sof-bin/sof/intel-signed/sof-cnl.ri:lib/firmware/intel/sof/sof-cml.ri
  sof-bin/sof/intel-signed/sof-icl.ri:lib/firmware/intel/sof/sof-icl.ri
  sof-bin/sof/intel-signed/sof-jsl.ri:lib/firmware/intel/sof/sof-jsl.ri
  sof-bin/sof/intel-signed/sof-tgl.ri:lib/firmware/intel/sof/sof-tgl.ri
  sof-bin/sof/intel-signed/sof-tgl-h.ri:lib/firmware/intel/sof/sof-tgl-h.ri
  sof-bin/sof/intel-signed/sof-ehl.ri:lib/firmware/intel/sof/sof-ehl.ri
  sof-bin/sof/intel-signed/sof-adl.ri:lib/firmware/intel/sof/sof-adl.ri
  sof-bin/sof/intel-signed/sof-adl-s.ri:lib/firmware/intel/sof/sof-adl-s.ri
  sof-bin/sof/intel-signed/sof-adl-n.ri:lib/firmware/intel/sof/sof-adl-n.ri
  sof-bin/sof/intel-signed/sof-adl.ri:lib/firmware/intel/sof/sof-rpl.ri
  sof-bin/sof/intel-signed/sof-adl-s.ri:lib/firmware/intel/sof/sof-rpl-s.ri
  sof-bin/sof-ipc4/mtl/intel-signed/sof-mtl.ri:lib/firmware/intel/sof-ipc4/mtl/sof-mtl.ri
  sof-bin/sof-ipc4/mtl/intel-signed/sof-mtl.ri:lib/firmware/intel/sof-ipc4/arl/sof-arl.ri
  sof-bin/sof-ipc4/arl-s/intel-signed/sof-arl-s.ri:lib/firmware/intel/sof-ipc4/arl-s/sof-arl-s.ri
  sof-bin/sof-ipc4/lnl/intel-signed/sof-lnl.ri:lib/firmware/intel/sof-ipc4/lnl/sof-lnl.ri
  sof-bin/sof-ipc4/ptl/intel-signed/sof-ptl.ri:lib/firmware/intel/sof-ipc4/ptl/sof-ptl.ri
  sof-bin/sof-ipc4/wcl/intel-signed/sof-wcl.ri:lib/firmware/intel/sof-ipc4/wcl/sof-wcl.ri
  sof-bin/sof-ipc4-lib/lnl/intel-signed/drc.llext:lib/firmware/intel/sof-ipc4-lib/lnl/B36EE4DA-006F-47F9-A06D-FECBE2D8B6CE.bin
  #
  # topology. HDA 코덱 + DMIC 노트북은 범용 machine(skl_hda_dsp_generic) 하나가 받고,
  # 커널이 이름을 "sof-hda-generic" + (HDMI 코덱뿐이면 "-idisp") + (DMIC 수 N이면
  # "-Nch")로 짓는다(sof/intel/hda.c). 그 이름들만 넣는다. IPC3은 intel/sof-tplg,
  # MTL · ARL은 intel/sof-ace-tplg, LNL 이후는 intel/sof-ipc4-tplg다 — 뒤 둘은 sof-bin
  # 안에서 같은 디렉터리라 같은 원본이 두 자리로 간다. IPC4 쪽에는 3ch가 없다.
  # SoundWire 코덱(sof_sdw)의 기계별 topology 수백은 넣지 않는다(AU-M3 비목표).
  sof-bin/sof-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic.tplg
  sof-bin/sof-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-3ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-3ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-tplg/sof-hda-generic-idisp-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-ace-tplg/sof-hda-generic-idisp-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-1ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-1ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-2ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-4ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-4ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp-2ch.tplg
  sof-bin/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg:lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-idisp-4ch.tplg
```

### 2-2. `kernel/vendor_firmware.sh` — 편집 다섯

E1 — `old_string`(기준 파일 7줄부터):

```bash
# (WL-M1). make_initrd.sh가 부르고, 그 cpio를 initrd 뒤에 이어 붙인다.
```

`new_string`:

```bash
# (WL-M1). make_initrd.sh가 부르고, 그 cpio를 initrd 뒤에 이어 붙인다.
# AU-M3부터 소리 DSP(Intel SOF)의 firmware와 topology도 같은 cpio에 들어간다.
```

E2 — `old_string`(기준 파일 21줄부터):

```bash
REGDB_SHA256="b22e0901227b820cd1c280abe681a15b773a5103a5e10dc442e94ebb34cbf58d"
```

`new_string`:

```bash
REGDB_SHA256="b22e0901227b820cd1c280abe681a15b773a5103a5e10dc442e94ebb34cbf58d"

# AU-M3. Intel SOF의 firmware · topology는 linux-firmware에 없다(MediaTek 것만 있다).
# SOF 프로젝트가 서명된 바이너리를 sof-bin 릴리스로 내고, 배포판의 sof-firmware ·
# firmware-sof-signed가 그것을 그대로 담는다. 해시는 GitHub 릴리스 자산의
# digest와 대조했다(AU-M3 plan 확정 3). gz라 linux-firmware(xz)와 압축이 다르다.
SOF_VERSION="2026.09.1"
SOF_TARBALL="sof-bin-${SOF_VERSION}.tar.gz"
SOF_URL="https://github.com/thesofproject/sof-bin/releases/download/v${SOF_VERSION}/${SOF_TARBALL}"
SOF_SHA256="42ce40ec98f366365eab8e046d779b416d80b6ff2513b8f6be2a61a88e679b73"
```

E3 — `old_string`(기준 파일 60줄부터):

```bash
fetch "$REGDB_URL" "$REGDB_TARBALL" "$REGDB_SHA256"
```

`new_string`:

```bash
fetch "$REGDB_URL" "$REGDB_TARBALL" "$REGDB_SHA256"
fetch "$SOF_URL" "$SOF_TARBALL" "$SOF_SHA256"
```

E4 — `old_string`(기준 파일 70줄부터):

```bash
declare -A ROOT=([linux-firmware]="linux-firmware-${LF_VERSION}"
                 [wireless-regdb]="wireless-regdb-${REGDB_VERSION}")
declare -A TARBALL=([linux-firmware]="$LF_TARBALL" [wireless-regdb]="$REGDB_TARBALL")
for origin in linux-firmware wireless-regdb; do
```

`new_string`:

```bash
# 압축은 tar가 파일을 보고 고른다(xz 둘 · gz 하나).
declare -A ROOT=([linux-firmware]="linux-firmware-${LF_VERSION}"
                 [wireless-regdb]="wireless-regdb-${REGDB_VERSION}"
                 [sof-bin]="sof-bin-${SOF_VERSION}")
declare -A TARBALL=([linux-firmware]="$LF_TARBALL" [wireless-regdb]="$REGDB_TARBALL"
                    [sof-bin]="$SOF_TARBALL")
for origin in linux-firmware wireless-regdb sof-bin; do
```

E5 — `old_string`(기준 파일 78줄부터):

```bash
  tar -xJf "$CACHE/${TARBALL[$origin]}" -C "$WORK" -T "$WORK/$origin.list"
```

`new_string`:

```bash
  tar -xf "$CACHE/${TARBALL[$origin]}" -C "$WORK" -T "$WORK/$origin.list"
```

### 2-3. `kernel/make_initrd.sh` — 편집 하나

E1 — `old_string`(기준 파일 279줄부터):

```bash
cp -r "$SYSROOT/usr/share/alsa" "$WORKDIR/usr/share/"
```

`new_string`:

```bash
cp -r "$SYSROOT/usr/share/alsa" "$WORKDIR/usr/share/"

# AU-M3. alsactl init의 규칙 하나를 더한다 — DSP 뒤의 내장 디지털 마이크를 켠다.
# SOF는 topology의 스위치 컨트롤을 꺼짐(0)으로 올리고(sof/ipc3-topology.c ·
# ipc4-topology.c), alsactl의 범용 규칙(init/default)은 이름이 정확히 "Capture Switch"인
# 것만 켠다. 그대로 두면 arecord가 내장 마이크에서 0만 받는다. Debian은 이 일을
# alsa-ucm-conf의 부팅 순서로 하는데 그 순서가 Speaker · Headphone 스위치도 꺼서
# (HDA/init.conf — 켜는 것은 PipeWire의 몫으로 본다) 우리는 UCM을 안 싣는다
# (init/src/audio.zig의 -U 주석). postinit은 alsactl init이 카드마다 표준 규칙 뒤에
# 읽는 자리라(init/00main) 다른 카드에는 아무 일도 안 한다 — 이름이 없으면 건너뛴다.
# 볼륨은 커널이 0dB로 올리므로(VOL_ZERO_DB) 안 만진다.
mkdir -p "$WORKDIR/usr/share/alsa/init/postinit"
cat > "$WORKDIR/usr/share/alsa/init/postinit/00-tars-dmic.conf" <<'EOF'
# tars(AU-M3): SOF 카드의 내장 디지털 마이크를 켠다. kernel/make_initrd.sh가 쓴다.
CTL{reset}="mixer"
CTL{name}="Dmic0 Capture Switch",CTL{do_search}=="1",CTL{values}="on"
EOF
```

### 2-4. `tools/check.sh` — 편집 하나

E1 — `old_string`(기준 파일 237줄부터):

```bash
# ── 검사 1b: initrd 꼬리에 무선 firmware가 전부 있는가 (WL-M1, 정적) ────
```

`new_string`:

```bash
# ── 검사 1b: initrd 꼬리에 무선 · 소리 firmware가 전부 있는가 (WL-M1 · AU-M3) ─
```

### 2-5. 확인

```bash
for f in kernel/guest_firmware.sh kernel/vendor_firmware.sh kernel/make_initrd.sh tools/check.sh; do
  cmp $f /tmp/run/au3/new/$f && echo "SAME $f"; done
bash -n kernel/guest_firmware.sh && bash -n kernel/vendor_firmware.sh && bash -n kernel/make_initrd.sh && echo SYNTAX-OK
bash -c '. kernel/guest_firmware.sh; echo "${#GUEST_FIRMWARE[@]} entries"'
```

기대: `SAME` 넷 · `SYNTAX-OK` · `119 entries`(무선 77 + 소리 42).

## Task 3: `init` — 녹음의 세 단

확정 4 · 6.

### 3-1. `init/src/audio.zig` — 편집 아홉

E1 — `old_string`(기준 파일 74줄부터):

```zig
///        내려온다(design 실측 10). UCM이 필요한 기계(DSP 뒤의 마이크)는 AU-M3이고,
///        그때 alsa-ucm-conf와 함께 이 플래그를 다시 본다
```

`new_string`:

```zig
///        내려온다(design 실측 10). AU-M3이 다시 봤고 그대로 둔다 — alsa-ucm-conf를
///        실어도 그 부팅 순서(HDA/init.conf)가 Speaker · Headphone 스위치를 끈다. 켜는
///        것은 사운드 서버(PipeWire)의 몫이라고 보는 설정이고 우리에게는 그것이 없다.
///        DSP 뒤의 마이크(Dmic0) 스위치는 alsactl init의 postinit 규칙 하나가 켠다
///        (make_initrd.sh의 AU-M3 절)
```

E2 — `old_string`(기준 파일 297줄부터):

```zig
// 다를 때만 파일을 쓴다. uevent 소켓도 일꾼도 없다(AU-M2 plan 확정 4).
```

`new_string`:

```zig
// 다를 때만 파일을 쓴다. uevent 소켓도 일꾼도 없다(AU-M2 plan 확정 4).
//
// AU-M3. 녹음은 장치 0이 아닐 수 있다. DSP 뒤의 내장 디지털 마이크(DMIC)는 Intel
// SOF 카드에서 장치 6("DMIC (*)")이고 장치 0의 녹음은 헤드셋 잭이다 — 장치 0만 보면
// arecord가 아무것도 안 꽂힌 잭을 듣는다. AMD는 DMIC가 따로 카드 하나(ACP)이고
// 아날로그 HDA 카드와 어느 쪽이 큰 번호일지 정해져 있지 않다. 그래서 녹음은 세 단을
// 차례로 본다 — 꽂힌 USB 마이크, 내장 DMIC, 그 밖의 장치 0. 무엇이 DMIC이고 무엇이
// USB인지는 PCM의 이름으로 안다. 그래서 /dev/snd의 노드 이름 대신 /proc/asound/pcm을
// 읽는다(AU-M3 plan 확정 4).
```

E3 — `old_string`(기준 파일 302줄부터):

```zig
const SND_DIR: [:0]const u8 = "/dev/snd";
```

`new_string`:

```zig
/// 카드마다 PCM 한 줄 — 번호 · 이름 · 방향. 소리 장치가 없으면 빈 파일이다.
const PCM_PROC: [:0]const u8 = "/proc/asound/pcm";
```

E4 — `old_string`(기준 파일 307줄부터):

```zig
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
```

`new_string`:

```zig
/// 장치 0에 재생 · 녹음이 있는 카드의 집합과 녹음 쪽의 표지 둘. 비트 하나가 카드
/// 하나다.
pub const Cards = struct {
    playback: u32 = 0,
    capture: u32 = 0,
    /// 녹음이 되는 USB 카드(헤드셋 · USB 마이크). snd-usb-audio는 PCM id를 언제나
    /// "USB Audio"로 짓는다(sound/usb/stream.c).
    usb_capture: u32 = 0,
    /// 녹음 PCM의 id에 "DMIC"가 든 카드. SOF는 "DMIC (*)"(장치 6)와 "DMIC16kHz (*)"
    /// (장치 7), AMD ACP는 "DMIC capture dmic-hifi-0"(장치 0)이다.
    dmic: u32 = 0,
    /// 카드마다 그 DMIC PCM의 장치 번호. 둘 이상이면 처음 본 것(가장 작은 번호)이다.
    dmic_dev: [MAX_CARDS]u8 = [_]u8{0} ** MAX_CARDS,
};

/// /proc/asound/pcm의 한 줄을 `cards`에 더한다. 순수 함수다.
///
///   00-00: HDA Analog (*) :  : playback 1 : capture 1
///   00-06: DMIC (*) :  : capture 1
///   01-00: USB Audio : USB Audio : playback 1 : capture 1
///
/// 커널의 snd_pcm_proc_read가 쓰는 모양이다 — 카드와 장치 두 자리씩, id, name, 그리고
/// 있는 방향만 " : playback N" · " : capture N". 모양이 다르거나 카드가 상한 밖이면
/// 버린다.
pub fn addPcmLine(cards: *Cards, line: []const u8) void {
    if (line.len < 7 or line[2] != '-' or !std.mem.startsWith(u8, line[5..], ": ")) return;
    if (!std.ascii.isDigit(line[0]) or !std.ascii.isDigit(line[3])) return;
    const card = std.fmt.parseInt(u8, line[0..2], 10) catch return;
    const dev = std.fmt.parseInt(u8, line[3..5], 10) catch return;
    if (card >= MAX_CARDS) return;
    const rest = line[7..];
    const id = rest[0 .. std.mem.indexOf(u8, rest, " : ") orelse return];
    const playback = std.mem.indexOf(u8, rest, " : playback ") != null;
    const capture = std.mem.indexOf(u8, rest, " : capture ") != null;
    const bit = @as(u32, 1) << @intCast(card);
    if (dev == 0 and playback) cards.playback |= bit;
    if (dev == 0 and capture) cards.capture |= bit;
    if (!capture) return;
    if (std.mem.startsWith(u8, id, "USB Audio")) cards.usb_capture |= bit;
    if (std.ascii.indexOfIgnoreCase(id, "dmic") != null and cards.dmic & bit == 0) {
        cards.dmic |= bit;
        cards.dmic_dev[card] = dev;
```

E5 — `old_string`(기준 파일 334줄부터):

```zig

    pub fn eql(a: Defaults, b: Defaults) bool {
        return a.playback == b.playback and a.capture == b.capture;
```

`new_string`:

```zig
    /// 녹음 카드의 장치. 내장 DMIC를 고를 때만 0이 아닐 수 있다(AU-M3).
    capture_dev: u8 = 0,

    pub fn eql(a: Defaults, b: Defaults) bool {
        return a.playback == b.playback and a.capture == b.capture and a.capture_dev == b.capture_dev;
```

E6 — `old_string`(기준 파일 345줄부터):

```zig
/// 재생과 녹음 각각 번호가 가장 큰 카드. 순수 함수다.
pub fn defaultsFor(cards: Cards) Defaults {
    return .{ .playback = highest(cards.playback), .capture = highest(cards.capture) };
```

`new_string`:

```zig
/// 재생은 장치 0을 가진 카드 중 번호가 가장 큰 것. 녹음은 세 단을 차례로 보고 처음
/// 걸리는 단에서 번호가 가장 큰 카드다(AU-M3). 순수 함수다.
///
///   1. 꽂힌 USB 마이크 · 헤드셋(장치 0). 사람이 일부러 꽂은 것이 이긴다
///   2. 내장 DMIC(그 PCM의 장치). SOF 카드의 장치 0 녹음은 헤드셋 잭이라 고르지 않는다
///   3. 그 밖의 장치 0 녹음(AU-M2 그대로 — HDA의 아날로그 마이크, QEMU의 코덱)
pub fn defaultsFor(cards: Cards) Defaults {
    var d: Defaults = .{ .playback = highest(cards.playback) };
    if (highest(cards.usb_capture & cards.capture)) |c| {
        d.capture = c;
    } else if (highest(cards.dmic)) |c| {
        d.capture = c;
        d.capture_dev = cards.dmic_dev[c];
    } else {
        d.capture = highest(cards.capture);
    }
    return d;
```

E7 — `old_string`(기준 파일 364줄부터):

```zig
    w.writeAll("# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n") catch return null;
    if (d.playback) |n| w.print(DIRECTION, .{ "playback", n }) catch return null;
    if (d.capture) |n| w.print(DIRECTION, .{ "capture", n }) catch return null;
```

`new_string`:

```zig
    w.writeAll("# tars-init이 쓴다(AU-M2 · M3). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생은 장치 0을 가진 카드 중 번호가 가장 큰 것, 녹음은 USB 마이크 · 내장 DMIC ·\n" ++
        "# 그 밖의 장치 0 순으로 처음 있는 단에서 번호가 가장 큰 것이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n") catch return null;
    if (d.playback) |n| w.print(DIRECTION, .{ "playback", n }) catch return null;
    if (d.capture) |n| {
        if (d.capture_dev == 0) {
            w.print(DIRECTION, .{ "capture", n }) catch return null;
        } else {
            w.print(DIRECTION_DEV, .{ "capture", n, d.capture_dev }) catch return null;
        }
    }
```

E8 — `old_string`(기준 파일 381줄부터):

```zig
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
```

`new_string`:

```zig
/// 장치 0이 아닌 녹음(내장 DMIC, AU-M3). `sysdefault`는 장치 0만 열므로 `plughw`에 장치를
/// 준다. SOF · ACP 카드에는 alsa-lib의 카드 설정(cards/*.conf)이 없어 그 카드의
/// `sysdefault`도 원래 `plughw`다 — 섞기(dsnoop)가 없는 것은 장치 0일 때와 같다.
const DIRECTION_DEV =
    "\t{s}.pcm {{\n" ++
    "\t\t@func concat\n" ++
    "\t\tstrings [ \"plughw:CARD=\" {{ @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"{d}\" }} \",DEV={d}\" ]\n" ++
    "\t}}\n";

/// 지금 있는 카드. /proc/asound/pcm을 줄마다 `addPcmLine`에 준다. 파일이 없거나
/// 비었으면(소리 장치가 없는 기계) 빈 집합이다. 한 줄이 80바이트 안팎이고 노트북 한
/// 대가 열 줄 남짓이라 8KB면 넉넉하다 — 넘으면 넘은 줄을 안 본다.
fn scanCards() Cards {
    var cards: Cards = .{};
    const rc = linux.open(PCM_PROC.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return cards;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [8192]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        len += n;
    }
    var lines = std.mem.splitScalar(u8, buf[0..len], '\n');
    while (lines.next()) |line| addPcmLine(&cards, line);
```

E9 — `old_string`(기준 파일 444줄부터):

```zig
    var cb: [3]u8 = undefined;
    std.debug.print("tars-init: audio: default card is {s} for playback, {s} for capture\n", .{
        cardText(&pb, want.playback), cardText(&cb, want.capture),
    });
```

`new_string`:

```zig
    var cb: [16]u8 = undefined;
    std.debug.print("tars-init: audio: default card is {s} for playback, {s} for capture\n", .{
        cardText(&pb, want.playback), captureText(&cb, want),
    });
}

/// 로그용. 녹음 카드와, 장치 0이 아니면 그 장치. "0 (device 6)"처럼 — 장치 0일 때는
/// AU-M2의 글자 그대로다(게이트가 그 글자를 본다).
fn captureText(buf: *[16]u8, d: Defaults) []const u8 {
    const c = d.capture orelse return "none";
    if (d.capture_dev == 0) return std.fmt.bufPrint(buf, "{d}", .{c}) catch unreachable;
    return std.fmt.bufPrint(buf, "{d} (device {d})", .{ c, d.capture_dev }) catch unreachable;
```

### 3-2. `init/src/audio_test.zig` — 편집 넷

E1 — `old_string`(기준 파일 9줄부터):

```zig
// 때 소리가 실제로 그 카드로 가는 것은 audio 체인의 부팅 D가 본다.
```

`new_string`:

```zig
// 때 소리가 실제로 그 카드로 가는 것은 audio 체인의 부팅 D가 본다.
//
// AU-M3. `addNode`(/dev/snd의 이름)가 `addPcmLine`(/proc/asound/pcm의 줄)이 됐다. 녹음의
// 세 단(USB 마이크 · 내장 DMIC · 장치 0)은 QEMU에 DMIC가 없어 여기서만 본다 — 아래
// SOF · AMD의 줄은 커널의 snd_pcm_proc_read 모양에 그 드라이버들이 짓는 id를 넣은 것이다.
```

E2 — `old_string`(기준 파일 84줄부터):

```zig
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
```

`new_string`:

```zig
    // ── 어느 카드가 기본인가(AU-M2 · M3) ───────────────────────────────
    //
    // /proc/asound/pcm의 줄에서 장치 0의 재생 · 녹음과, 녹음 쪽의 USB · DMIC 표지를
    // 센다. 첫 목록은 게스트의 실제 모양이다 — QEMU의 HDA(카드 0, 재생과 녹음)에 USB
    // 스피커(카드 1, 재생만)가 꽂힌 것.
    const qemu = scan(&.{
        "00-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "01-00: USB Audio : USB Audio : playback 1",
        "",
    });
    if (qemu.playback != 0b11 or qemu.capture != 0b01 or qemu.usb_capture != 0 or qemu.dmic != 0)
        return fail("HDA plus a USB speaker reads as playback 0x{x} capture 0x{x} usb 0x{x} dmic 0x{x}, want 0x3 0x1 0 0", .{ qemu.playback, qemu.capture, qemu.usb_capture, qemu.dmic });
    // 장치 0이 아닌 것 · 모양이 다른 것은 장치 0으로 안 센다. HDMI 코덱만 가진 카드는 장치
    // 1(디지털)이나 3(HDMI)이다.
    const none = scan(&.{
        "02-01: ALC257 Digital : ALC257 Digital : playback 1",
        "02-03: HDMI 0 : HDMI 0 : playback 1",
        "32-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "x0-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "0-00: Generic Analog : Generic Analog : playback 1",
        "00-00 Generic Analog : Generic Analog : playback 1",
        "00-00: Generic Analog",
        "card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]",
    });
    if (none.playback != 0 or none.capture != 0 or none.dmic != 0)
        return fail("lines that are not device 0 counted as playback 0x{x} capture 0x{x} dmic 0x{x}", .{ none.playback, none.capture, none.dmic });
    std.debug.print("audio_test: only device 0 counts for playback, from /proc/asound/pcm lines\n", .{});

    // 재생과 녹음 각각 번호가 가장 큰 카드. 마이크 없는 USB 스피커가 꽂혀도 녹음은 0에 남는다.
    const split = audio.defaultsFor(qemu);
    if (split.playback != 1 or split.capture != 0 or split.capture_dev != 0) return fail("HDA plus a USB speaker picks playback {?d} capture {?d}:{d}, want 1 and 0:0", .{ split.playback, split.capture, split.capture_dev });
```

E3 — `old_string`(기준 파일 108줄부터):

```zig
    // 파일의 글자. 손으로 적은 글자와 비교한다(tautology가 아니게). 카드 번호는 getenv의
    // 기본값 자리에 들어간다 — ALSA_CARD가 있으면 그것이 이긴다.
    var buf: [1024]u8 = undefined;
    const head = "# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n";
```

`new_string`:

```zig
    // Intel SOF(sof-hda-dsp). 장치 0의 녹음은 헤드셋 잭, 내장 마이크는 장치 6이다.
    const sof_lines = [_][]const u8{
        "00-00: HDA Analog (*) :  : playback 1 : capture 1",
        "00-03: HDMI1 (*) :  : playback 1",
        "00-04: HDMI2 (*) :  : playback 1",
        "00-05: HDMI3 (*) :  : playback 1",
        "00-06: DMIC (*) :  : capture 1",
        "00-07: DMIC16kHz (*) :  : capture 1",
        "00-31: Deepbuffer HDA Analog (*) :  : playback 1",
    };
    const sof = audio.defaultsFor(scan(&sof_lines));
    if (sof.playback != 0 or sof.capture != 0 or sof.capture_dev != 6) return fail("a SOF laptop picks playback {?d} capture {?d}:{d}, want 0 and 0:6", .{ sof.playback, sof.capture, sof.capture_dev });
    // 같은 노트북에 USB 헤드셋. 사람이 꽂은 마이크가 내장 DMIC를 이긴다.
    const sof_usb = audio.defaultsFor(scan(&(sof_lines ++ [_][]const u8{"01-00: USB Audio : USB Audio : playback 1 : capture 1"})));
    if (sof_usb.playback != 1 or sof_usb.capture != 1 or sof_usb.capture_dev != 0) return fail("a SOF laptop with a USB headset picks playback {?d} capture {?d}:{d}, want 1 and 1:0", .{ sof_usb.playback, sof_usb.capture, sof_usb.capture_dev });
    // 마이크 없는 USB 스피커는 녹음을 안 가져간다.
    const sof_spk = audio.defaultsFor(scan(&(sof_lines ++ [_][]const u8{"01-00: USB Audio : USB Audio : playback 1"})));
    if (sof_spk.playback != 1 or sof_spk.capture != 0 or sof_spk.capture_dev != 6) return fail("a SOF laptop with a USB speaker picks playback {?d} capture {?d}:{d}, want 1 and 0:6", .{ sof_spk.playback, sof_spk.capture, sof_spk.capture_dev });
    // AMD. GPU 쪽 HDA(HDMI뿐) · 아날로그 HDA · ACP(DMIC)가 따로 카드다. 번호의 차례는
    // probe 순서라 정해져 있지 않다 — 어느 차례든 녹음은 ACP다.
    const amd = audio.defaultsFor(scan(&.{
        "00-03: HDMI 0 : HDMI 0 : playback 1",
        "01-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1",
        "02-00: DMIC capture dmic-hifi-0 :  : capture 1",
    }));
    if (amd.playback != 1 or amd.capture != 2 or amd.capture_dev != 0) return fail("an AMD laptop picks playback {?d} capture {?d}:{d}, want 1 and 2:0", .{ amd.playback, amd.capture, amd.capture_dev });
    const amd_swapped = audio.defaultsFor(scan(&.{
        "00-03: HDMI 0 : HDMI 0 : playback 1",
        "01-00: DMIC capture dmic-hifi-0 :  : capture 1",
        "02-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1",
    }));
    if (amd_swapped.playback != 2 or amd_swapped.capture != 1 or amd_swapped.capture_dev != 0) return fail("an AMD laptop with the ACP first picks playback {?d} capture {?d}:{d}, want 2 and 1:0", .{ amd_swapped.playback, amd_swapped.capture, amd_swapped.capture_dev });
    std.debug.print("audio_test: capture goes to a plugged USB mic, else the built-in DMIC, else device 0\n", .{});

    // 파일의 글자. 손으로 적은 글자와 비교한다(tautology가 아니게). 카드 번호는 getenv의
    // 기본값 자리에 들어간다 — ALSA_CARD가 있으면 그것이 이긴다.
    var buf: [1024]u8 = undefined;
    const head = "# tars-init이 쓴다(AU-M2 · M3). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생은 장치 0을 가진 카드 중 번호가 가장 큰 것, 녹음은 USB 마이크 · 내장 DMIC ·\n" ++
        "# 그 밖의 장치 0 순으로 처음 있는 단에서 번호가 가장 큰 것이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n";
    const play0 = "\tplayback.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } ]\n\t}\n";
```

E4 — `old_string`(기준 파일 121줄부터):

```zig
    try expectText("split", audio.render(&buf, split), head ++ play1 ++ cap0 ++ "}\ndefaults.ctl.card 1\n");
    try expectText("capture only", audio.render(&buf, .{ .capture = 3 }), head ++ cap3 ++ "}\ndefaults.ctl.card 3\n");
    if (audio.render(&buf, .{}) != null) return fail("no card must render no file", .{});
    std.debug.print("audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file\n", .{});
```

`new_string`:

```zig
    const cap0dmic = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"plughw:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } \",DEV=6\" ]\n\t}\n";
    try expectText("split", audio.render(&buf, split), head ++ play1 ++ cap0 ++ "}\ndefaults.ctl.card 1\n");
    try expectText("capture only", audio.render(&buf, .{ .capture = 3 }), head ++ cap3 ++ "}\ndefaults.ctl.card 3\n");
    try expectText("sof", audio.render(&buf, sof), head ++ play0 ++ cap0dmic ++ "}\ndefaults.ctl.card 0\n");
    if (audio.render(&buf, .{}) != null) return fail("no card must render no file", .{});
    std.debug.print("audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file\n", .{});
    std.debug.print("audio_test: a DMIC that is not device 0 is opened as plughw:CARD=N,DEV=D\n", .{});
}

/// /proc/asound/pcm의 줄들을 차례로 더한다.
fn scan(lines: []const []const u8) audio.Cards {
    var cards: audio.Cards = .{};
    for (lines) |line| audio.addPcmLine(&cards, line);
    return cards;
```

### 3-3. 확인과 호스트 검사

```bash
for f in init/src/audio.zig init/src/audio_test.zig; do cmp $f /tmp/run/au3/new/$f && echo "SAME $f"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init; zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep "^audio_test:" /tmp/t.log'
rmdir /tmp/run/docker.lock
```

기대: `SAME` 둘 · `test exit=0` · `audio_test:` 아홉 줄 — M1의 넷과 아래 다섯.

```
audio_test: only device 0 counts for playback, from /proc/asound/pcm lines
audio_test: the highest card wins, for playback and capture apart
audio_test: capture goes to a plugged USB mic, else the built-in DMIC, else device 0
audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file
audio_test: a DMIC that is not device 0 is opened as plughw:CARD=N,DEV=D
```

## Task 4: `audio/probe.sh` · `audio/check.sh` · `check.sh`

확정 7.

### 4-1. `audio/probe.sh` — 편집 둘

E1 — `old_string`(기준 파일 18줄부터):

```bash
#          기본이 돌아오는 것을 소리로 본다. 꽂고 뽑는 것은 체인이 monitor로 한다
```

`new_string`:

```bash
#          기본이 돌아오는 것을 소리로 본다. 꽂고 뽑는 것은 체인이 monitor로 한다.
#          끝에 DSP 쪽 둘을 본다(AU-M3) — 커널이 SOF · ACP 드라이버를 올렸는지, 그리고
#          alsactl init의 postinit 규칙이 내장 마이크 스위치(Dmic0)를 켜는지
```

E2 — `old_string`(기준 파일 92줄부터):

```bash
  say "unplugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
```

`new_string`:

```bash
  say "unplugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"

  # AU-M3. QEMU에는 SOF · ACP 장치가 없으므로 드라이버가 "등록됐다"까지만 본다. 그리고
  # QEMU의 HDA(ICH9)는 DSP 표(intel-dsp-config)에 없으니 여전히 snd_hda_intel이어야 한다.
  say "dsp drivers [$(ls /sys/bus/pci/drivers | grep -E '^(sof-audio-pci-intel-|snd_rn_pci_acp3x$|snd_pci_acp6x$|snd_pci_ps$|snd_acp_pci$)' | flat)]"
  say "card 0 driver [$(basename "$(readlink /sys/class/sound/card0/device/driver)")]"
  # 실기에서 SOF가 실패할 때의 탈출로는 커널 인자 snd_intel_dspcfg.dsp_driver=1(HDA로)이다.
  # 그 파라미터가 이 커널에 있는지 본다 — 기본값 0은 "DSP 표대로"다.
  say "dsp_driver [$(cat /sys/module/snd_intel_dspcfg/parameters/dsp_driver 2>&1)]"
  # postinit 규칙(make_initrd.sh의 AU-M3 절). QEMU의 코덱에는 Dmic0 컨트롤이 없어서 같은
  # 이름의 사용자 컨트롤을 꺼진 채 하나 만든다 — alsactl restore가 접근에 user가 든
  # 항목을 만들어 준다(-I는 파일에 없는 컨트롤 때문에 init으로 내려가지 않게). 그 뒤
  # init의 일꾼과 같은 argv(-U init)로 이 카드를 다시 init해 스위치가 켜지는지 본다.
  printf '%s\n' 'state.Intel {' '	control.1 {' '		iface MIXER' "		name 'Dmic0 Capture Switch'" \
    '		value false' '		comment {' "			access 'read write user'" '			type BOOLEAN' \
    '			count 1' '		}' '	}' '}' > /tmp/dmic.state
  out="$(alsactl -U -I -f /tmp/dmic.state restore 0 2>&1)"; rc=$?
  say "dmic control made exit ${rc} [$(amixer -c 0 cget name='Dmic0 Capture Switch' 2>&1 | grep ': values=' | flat)]"
  out="$(alsactl -U init 0 2>&1)"; rc=$?
  say "dmic after init exit ${rc} [$(amixer -c 0 cget name='Dmic0 Capture Switch' 2>&1 | grep ': values=' | flat)]"
```

### 4-2. `audio/check.sh` — 편집 여섯

E1 — `old_string`(기준 파일 38줄부터):

```bash
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등, 검사 1이 심볼과 표로만 본다) ·
# DSP(SOF · ACP, AU-M3) · 헤드폰 잭의 꽂힘(QEMU 코덱에 잭 감지가 없다) · 마이크 달린
# USB 헤드셋(QEMU usb-audio는 재생뿐이다).
```

`new_string`:

```bash
#      부팅 D는 끝에 DSP 쪽 둘도 본다(AU-M3) — 커널이 SOF · ACP 드라이버를 올렸고 QEMU의
#      HDA는 여전히 snd_hda_intel이다(검사 16), alsactl init이 내장 마이크 스위치를
#      켠다(검사 17)
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등, 검사 1이 심볼과 표로만 본다) ·
# DSP의 실제 probe와 firmware 로딩(SOF · ACP — QEMU에 그 장치가 없어 검사 1이 심볼 ·
# 표 · firmware 이름으로, 검사 16 · 17이 드라이버 등록과 마이크 스위치 규칙으로만
# 본다) · 녹음이 DMIC로 가는 것(호스트 검사 audio_test만 본다) · 헤드폰 잭의
# 꽂힘(QEMU 코덱에 잭 감지가 없다) · 마이크 달린 USB 헤드셋(QEMU usb-audio는 재생뿐이다).
```

E2 — `old_string`(기준 파일 102줄부터):

```bash
    "audio-probe: plug now" \
```

`new_string`:

```bash
    "audio-probe: plug now" \
    "audio-probe: dsp drivers [" \
    "audio-probe: dmic after init exit" \
```

E3 — `old_string`(기준 파일 194줄부터):

```bash
# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
```

`new_string`:

```bash
# AU-M3. DSP 뒤의 내장 마이크. Intel은 SOF(세대마다 하나)와 그 아래 HDA 코덱을 받는
# 범용 machine, AMD는 세대마다의 PDM 드라이버(Renoir · Yellow Carp · ACP6.3)와 그
# machine, 그리고 ACP 7.x를 받는 범용 ACP 드라이버와 legacy machine이다(7.x는 BIOS가
# 따로 말하지 않으면 "DMIC만 legacy"로 정해져 PDM 드라이버가 물러난다 — acp-config.c).
# QEMU에 둘 다 없어서 심볼과 표(modinfo alias)로 본다. 범용 machine이 HDMI 코덱에 걸려
# 있어(Kconfig depends) SND_HDA_CODEC_HDMI도 켜진다.
for sym in SND_SOC SND_SOC_SOF_TOPLEVEL SND_SOC_SOF_PCI SND_SOC_SOF_INTEL_TOPLEVEL \
  SND_SOC_SOF_CANNONLAKE SND_SOC_SOF_COFFEELAKE SND_SOC_SOF_COMETLAKE SND_SOC_SOF_ICELAKE \
  SND_SOC_SOF_JASPERLAKE SND_SOC_SOF_TIGERLAKE SND_SOC_SOF_ELKHARTLAKE SND_SOC_SOF_ALDERLAKE \
  SND_SOC_SOF_METEORLAKE SND_SOC_SOF_LUNARLAKE SND_SOC_SOF_PANTHERLAKE \
  SND_SOC_SOF_HDA_LINK SND_SOC_SOF_HDA_AUDIO_CODEC SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH SND_HDA_CODEC_HDMI \
  SND_SOC_AMD_RENOIR SND_SOC_AMD_RENOIR_MACH SND_SOC_AMD_ACP6x SND_SOC_AMD_YC_MACH \
  SND_SOC_AMD_PS SND_SOC_AMD_PS_MACH SND_SOC_AMD_ACP_PCI SND_AMD_ASOC_ACP70 SND_SOC_AMD_LEGACY_MACH; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
# 꺼져 있어야 하는 것. SOF_PCI를 켜면 세대마다의 심볼이 기본값으로 따라 켜지는데, 아래
# 넷(SKL · KBL · APL · GLK)과 Merrifield는 노트북에서 SOF로 안 가거나(SKL · KBL은 DSP
# 표가 HDA로 묶는다) Chromebook · UP 보드 · 태블릿의 것이고 firmware도 싣지 않는다.
# Atom의 SST는 ACPI면 기본으로 켜진다. SND_HDA_I915는 GPU 드라이버(i915 · xe)가 켤 때만
# 선다 — 서 있으면 SOF가 i915의 오디오 컴포넌트를 기다리느라 카드를 안 만들 수 있다
# (sound/soc/sof/intel/hda.c의 hda_codec_i915_init). 지금은 그 자리가 -ENODEV stub이다.
for sym in SND_SOC_SOF_SKYLAKE SND_SOC_SOF_KABYLAKE SND_SOC_SOF_APOLLOLAKE SND_SOC_SOF_GEMINILAKE \
  SND_SOC_SOF_MERRIFIELD SND_SST_ATOM_HIFI2_PLATFORM_ACPI SND_HDA_I915; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is on; AU-M3 keeps it off"
    exit 1
  fi
done
for alias in snd_sof_pci_intel_cnl.alias=pci:v00008086d000002C8 snd_sof_pci_intel_icl.alias=pci:v00008086d000034C8 \
  snd_sof_pci_intel_tgl.alias=pci:v00008086d0000A0C8 snd_sof_pci_intel_tgl.alias=pci:v00008086d000051C8 \
  snd_sof_pci_intel_mtl.alias=pci:v00008086d00007E28 snd_sof_pci_intel_lnl.alias=pci:v00008086d0000A828 \
  snd_sof_pci_intel_ptl.alias=pci:v00008086d0000E428 snd_soc_skl_hda_dsp.alias=platform:skl_hda_dsp_generic \
  'snd_rn_pci_acp3x.alias=pci:v00001022d000015E2sv*sd*bc04sc80i00*' snd_acp3x_rn.alias=platform:acp_pdm_mach \
  snd_soc_acp6x_mach.alias=platform:acp_yc_mach snd_soc_ps_mach.alias=platform:acp_ps_mach \
  'snd_acp_pci.alias=pci:v00001022d000015E2sv*sd*bc*sc*i*' snd_acp_legacy_mach.alias=platform:acp-pdm-mach; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*alias=}"
    exit 1
  fi
done
# SOF는 firmware가 없으면 HDA로 돌아오지 않고 카드를 아예 안 만든다(스피커까지 조용).
# 그래서 커널 안에 있는 SOF firmware 이름(sof-<세대>.ri)이 전부 firmware 목록의 initrd
# 경로 끝에 있어야 한다. 이름은 커널 이미지에서 읽는다 — 커널이 세대를 하나 더 켜거나
# 커널을 올리면 여기서 걸린다. 목록의 파일이 initrd에 실제로 있는지는 tools 체인의
# 검사 1b가 본다.
. ../kernel/guest_firmware.sh
FW_DESTS=$'\n'"$(printf '%s\n' "${GUEST_FIRMWARE[@]}" | sed 's/^[^:]*://; s#.*/##')"$'\n'
# 이름은 커널 이미지와 SOF Intel 드라이버의 오브젝트 둘에 다 있는 것이다. 이미지에는 AMD
# SOF용 machine 표(sound/soc/amd/acp-config.c — sof-rn · sof-rmb · sof-vangogh)도 들어
# 있는데 AMD SOF 드라이버는 꺼져 있어 아무도 그 이름을 안 찾는다. 오브젝트만 보면 지난
# 설정으로 빌드된 채 남은 것까지 센다 — 둘의 교집합이 "지금 링크된 Intel SOF"다.
SOF_NAMES="$(comm -12 <(strings -n 6 ../kernel/build/vmlinux | grep -xE 'sof-[a-z0-9-]+\.ri' | sort -u) \
  <(strings -n 6 ../kernel/build/sound/soc/sof/intel/*.o | grep -xE 'sof-[a-z0-9-]+\.ri' | sort -u))"
if [ -z "$SOF_NAMES" ]; then
  echo "FAIL: no sof-*.ri name in the kernel image; SOF did not build"
  exit 1
fi
for name in $SOF_NAMES; do
  case "$FW_DESTS" in
    *$'\n'"${name}"$'\n'*) ;;
    *)
      echo "FAIL: the kernel asks for ${name} but kernel/guest_firmware.sh does not carry it"
      exit 1
      ;;
  esac
done

# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
```

E4 — `old_string`(기준 파일 202줄부터):

```bash
  usr/share/sounds/alsa/Front_Left.wav usr/share/sounds/alsa/Front_Right.wav; do
```

`new_string`:

```bash
  usr/share/sounds/alsa/Front_Left.wav usr/share/sounds/alsa/Front_Right.wav \
  usr/share/alsa/init/00main usr/share/alsa/init/postinit/00-tars-dmic.conf; do
```

E5 — `old_string`(기준 파일 219줄부터):

```bash
echo "the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group"
```

`new_string`:

```bash
echo "the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group"
echo "the kernel carries SOF for $(printf '%s\n' $SOF_NAMES | wc -l) Intel firmware names and AMD ACP, and the firmware list carries every one of those names"
```

E6 — `old_string`(기준 파일 613줄부터):

```bash
  || report_failure "aplay failed after the USB speaker went"
```

`new_string`:

```bash
  || report_failure "aplay failed after the USB speaker went"

# ── 검사 16: 커널이 DSP 드라이버를 올렸고, QEMU의 HDA는 HDA에 남았다 (AU-M3) ──
# SOF 여섯(세대 묶음마다 PCI 드라이버 하나)과 AMD 넷이 PCI 버스에 등록됐다. 장치가 없어
# probe는 안 돈다. 그리고 QEMU의 컨트롤러(ICH9)는 DSP 표에 없으므로 SOF를 켠 뒤에도
# snd_hda_intel이 받는다 — 위 검사 2 ~ 15가 그 카드로 돈 것이다.
grep -aF 'audio-probe: dsp drivers [snd_acp_pci|snd_pci_acp6x|snd_pci_ps|snd_rn_pci_acp3x|sof-audio-pci-intel-cnl|sof-audio-pci-intel-icl|sof-audio-pci-intel-lnl|sof-audio-pci-intel-mtl|sof-audio-pci-intel-ptl|sof-audio-pci-intel-tgl]' "$LOG" >/dev/null \
  || report_failure "the kernel did not register the six SOF and four AMD ACP PCI drivers"
grep -aF 'audio-probe: card 0 driver [snd_hda_intel]' "$LOG" >/dev/null \
  || report_failure "QEMU's HDA controller is not driven by snd_hda_intel any more"
# 실기에서 SOF가 실패하면 사람이 커널 인자 snd_intel_dspcfg.dsp_driver=1로 HDA에 돌아온다.
# 그 이름이 커널에 있어야 그 탈출로가 선다.
grep -aF 'audio-probe: dsp_driver [0]' "$LOG" >/dev/null   || report_failure "the kernel has no snd_intel_dspcfg.dsp_driver parameter; the way back to HDA is gone"
echo "the kernel registered the SOF and ACP drivers, QEMU's HDA stayed with snd_hda_intel, and snd_intel_dspcfg.dsp_driver is there"

# ── 검사 17: alsactl init이 내장 마이크 스위치를 켠다 (AU-M3) ───────────
# SOF는 Dmic0 Capture Switch를 꺼진 채 올리고 alsactl의 범용 규칙은 그 이름을 모른다.
# initrd의 postinit 규칙이 켠다. QEMU에는 그 컨트롤이 없어서 프로브가 같은 이름의 사용자
# 컨트롤을 꺼진 채 만들고 init의 일꾼과 같은 argv로 다시 init한다 — 99는 범용 규칙으로
# 켰다는 뜻이고 M1의 일꾼도 같은 코드를 받는다.
grep -aF 'audio-probe: dmic control made exit 0 [  : values=off]' "$LOG" >/dev/null \
  || report_failure "the probe could not make a Dmic0 Capture Switch to test the rule on"
grep -aF 'audio-probe: dmic after init exit 99 [  : values=on]' "$LOG" >/dev/null \
  || report_failure "alsactl init did not turn Dmic0 Capture Switch on; the postinit rule is missing or wrong"
echo "alsactl init turned a Dmic0 Capture Switch on through the postinit rule"
```

### 4-3. `check.sh` — 편집 하나

E1 — `old_string`(기준 파일 368줄부터):

```bash
  "AU-M2:./audio/check.sh"
```

`new_string`:

```bash
  "AU-M3:./audio/check.sh"
```

### 4-4. 확인

```bash
for f in audio/probe.sh audio/check.sh check.sh; do cmp $f /tmp/run/au3/new/$f && echo "SAME $f"; done
bash -n audio/probe.sh && bash -n audio/check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./audio/check.sh && require_no_early_exit_pipe ./audio/check.sh &&
  require_explicit_nic ./audio/check.sh && echo ENTRY-OK'
python3 /tmp/run/au3/anchors.py post "$PWD"
```

기대: `SAME` 셋 · `SYNTAX-OK` · `ENTRY-OK` · `post: 32 edits, 0 bad`.

## Task 5: 체인 한 번 · regression · mutation

### 5-1. `audio` 체인

firmware cpio를 다시 만드느라(linux-firmware 662MB를 다시 풀고 sof-bin을 처음 받는다) 첫 판이 3분 안팎이다. 로그를 호스트에서 읽게
`/tmp/run/au3`을 함께 붙인다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/au3:/tmp/run/au3 -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache init/zig-out terminal/.zig-cache terminal/zig-out
    bash audio/check.sh > /tmp/run/au3/impl/audio.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
rg -a -v '^qemu-system' /tmp/run/au3/impl/audio.log | tail -n 36
```

기대: `exit=0`, 그리고 마지막 줄들이 사본의 것과 같은 모양이다.

```
vendor_firmware: firmware.cpio.gz matches the list, skipping
258851 blocks
the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group
the kernel carries SOF for 19 Intel firmware names and AMD ACP, and the firmware list carries every one of those names
=== boot A: q35 with an HDA controller and a speaker + microphone codec, a fresh config disk ===
the kernel configured the codec as card 0 with a playback and a capture node
aplay -l and arecord -l both see card 0 device 0
the boot turned Master and Capture on with alsactl init, and amixer raised Master to 0dB
tap: frames=194917 tone=48000 left=53060 right=71059 other=0 doubled=0 zero=22798 first_left=50555 first_right=122332
aplay's square wave reached the speaker sample for sample
speaker-test spoke on the left channel, then on the right
cap: frames=96000 match=96000
arecord got the microphone's constant on both channels, 96000 frames of 96000
the power-off stored the mixer, and asound.state keeps Master at 74 (0dB)
shutdown: asked at 9.43s, powered down at 9.627108s
=== boot B: the same disk again ===
the second boot restored Master at 0dB and Capture on from the disk
tap B: frames=49670 tone=48000 left=0 right=0 other=0 doubled=0 zero=1670 first_left=-1 first_right=-1
with no amixer, aplay's square wave reached the speaker sample for sample
=== boot C: no config disk ===
without a config disk the boot still turned the mixer on with alsactl init
=== boot D: an HDA card, then a USB speaker plugged and unplugged with the monitor ===
the plugged USB speaker came up as card 1 and init made it the default for playback
usb tap: frames=49824 tone=48000 left=0 right=0 other=0 doubled=0 zero=1824 first_left=-1 first_right=-1
hda tap: frames=0 tone=0 left=0 right=0 other=0 doubled=0 zero=0 first_left=-1 first_right=-1
amixer and aplay went to the USB speaker, and the HDA speaker stayed silent
the kernel registered the SOF and ACP drivers, QEMU's HDA stayed with snd_hda_intel, and snd_intel_dspcfg.dsp_driver is there
alsactl init turned a Dmic0 Capture Switch on through the postinit rule
hda tap after unplug: frames=49656 tone=48000 left=0 right=0 other=0 doubled=0 zero=1656 first_left=-1 first_right=-1
unplugged, the default went back to the HDA card and aplay played there
cap D: frames=48000 match=48000
with the USB speaker in, arecord still recorded the HDA microphone, 48000 frames of 48000
AU check PASS
```

위는 사본의 둘째 판(firmware cpio가 이미 있는 판)이다. 구현자의 첫 판은 cpio를 새로 만들므로 첫 줄이
`vendor_firmware: 119 files, 45029489 bytes`이다(사본의 첫 판이 그랬다 — 크기는 gzip이 적는 시각 때문에 판마다 몇십 바이트 다를 수 있다). `tap:` · `tap B:` · `usb tap:` · `hda tap after unplug:`의 `frames` · `zero` · `first_*`와
`tone`의 자투리, `shutdown:`의 두 수는 판마다 다르다. 빨개지면 `report_failure`가 찍는 표식 · `audio-probe` · `tars-init: audio` 줄 ·
마지막 40줄을 그대로 보고한다.

### 5-2. regression — `install` · `tools` · `boot` · `machine` · `wifi` · `pointer` · `nic` · `power` · `service`

확정 11의 아홉이다. 한 컨테이너에서 차례로 돈다. 11분 안팎 걸려 Bash 한 번의 상한(10분)을 넘으므로 `run_in_background`로 돌리고
기다린다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/au3:/tmp/run/au3 -w /workspace tars-devcontainer bash -c '
  for c in install tools boot machine wifi pointer nic power service; do s=$(date +%s); bash $c/check.sh > /tmp/run/au3/impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/au3/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/au3/impl/reg.out
rg -a 'init waited|tools the list names|files the list names' /tmp/run/au3/impl/reg_install.log /tmp/run/au3/impl/reg_tools.log
```

기대: 아홉 다 `exit=0`. `init waited`가 1,500ms 이상(사본 1,700ms 두 판)이고, `all 92 tools` · `all 119 files the list names`다.
`init waited`가 500ms 아래면 멈추고 보고한다(lessons PD-3).

### 5-3. mutation

확정 10의 표다. 사본은 `/tmp/run/au3/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

```bash
python3 /tmp/run/au3/make_mut.py "$PWD" /tmp/run/au3/impl/mut
M=/tmp/run/au3/impl/mut
for p in config_k1:kernel/.config config_k2:kernel/.config guest_firmware_f1.sh:kernel/guest_firmware.sh \
  make_initrd_p1.sh:kernel/make_initrd.sh check_no1dmic.sh:audio/check.sh audio_z1.zig:init/src/audio.zig \
  audio_z2.zig:init/src/audio.zig audio_z3.zig:init/src/audio.zig; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 8`, 그리고 바뀐 줄 수가 `config_k1 2` · `config_k2 2` · `guest_firmware_f1.sh 1` · `make_initrd_p1.sh 16` ·
`check_no1dmic.sh 2` · `audio_z1.zig 3` · `audio_z2.zig 4` · `audio_z3.zig 2`. 다르면 돌리지 말고 보고한다.

`make_mut.py`:

```python
"""AU-M3 plan Task 5의 mutation 사본을 만든다.

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
    """src에서 start가 있는 자리부터 end 앞까지를 지운 사본."""
    s = open(os.path.join(root, src)).read()
    assert s.count(start) == 1 and s.count(end) == 1, dst
    a, b = s.index(start), s.index(end)
    path = os.path.join(out, dst)
    open(path, 'w').write(s[:a] + s[b:])
    os.chmod(path, 0o755)


# 커널 K1 — 세대 하나(Tiger Lake)를 끈다
make('kernel/.config', 'config_k1', 'CONFIG_SND_SOC_SOF_TIGERLAKE=y\n', '# CONFIG_SND_SOC_SOF_TIGERLAKE is not set\n')
# 커널 K2 — 끈 채 두어야 할 세대(Skylake)가 켜진다(-d를 빠뜨린 판)
make('kernel/.config', 'config_k2', '# CONFIG_SND_SOC_SOF_SKYLAKE is not set\n', 'CONFIG_SND_SOC_SOF_SKYLAKE=y\n')
# firmware F1 — 목록에서 Tiger Lake firmware 한 줄이 빠진다
make('kernel/guest_firmware.sh', 'guest_firmware_f1.sh',
     '  sof-bin/sof/intel-signed/sof-tgl.ri:lib/firmware/intel/sof/sof-tgl.ri\n', '')
# postinit P1 — make_initrd.sh가 규칙 파일을 안 쓴다
cut('kernel/make_initrd.sh', 'make_initrd_p1.sh',
    '# AU-M3. alsactl init의 규칙 하나를 더한다', '# speaker-test -t wav가 채널마다 읽는 목소리 파일.')
# 검사 1의 initrd 목록에서 규칙 파일을 뺀 체인 사본 — P1이 검사 17까지 가게 한다
make('audio/check.sh', 'check_no1dmic.sh',
     '  usr/share/alsa/init/00main usr/share/alsa/init/postinit/00-tars-dmic.conf; do\n',
     '  usr/share/alsa/init/00main; do\n')
# 호스트 검사 Z1 — 녹음의 둘째 단(내장 DMIC)이 없다(AU-M2의 규칙으로 돌아간다)
make('init/src/audio.zig', 'audio_z1.zig',
     '    } else if (highest(cards.dmic)) |c| {\n        d.capture = c;\n        d.capture_dev = cards.dmic_dev[c];\n    } else {\n',
     '    } else {\n')
# 호스트 검사 Z2 — 첫째 단(USB 마이크)이 없다. 꽂은 헤드셋보다 내장 DMIC가 이긴다
make('init/src/audio.zig', 'audio_z2.zig',
     '    if (highest(cards.usb_capture & cards.capture)) |c| {\n        d.capture = c;\n    } else if (highest(cards.dmic)) |c| {\n',
     '    if (highest(cards.dmic)) |c| {\n')
# 호스트 검사 Z3 — 장치 0이 아닌 녹음도 sysdefault로 쓴다(장치 6이 사라진다)
make('init/src/audio.zig', 'audio_z3.zig',
     '        if (d.capture_dev == 0) {\n',
     '        if (true) {\n')
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. 커널 사본(`config_k*`)은 `build.sh`의 스탬프가 해시
차이를 보고 다시 빌드하고, 목록 사본(`guest_firmware_f1.sh`)은 `vendor_firmware.sh`의 스탬프가 보고 firmware cpio를 다시 만든다(판마다
1 ~ 2분 더).

```bash
#!/bin/bash
# AU-M3 plan Task 5의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 audio 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 다섯 자리는 차례로 "Tiger Lake 심볼 · Skylake 꺼짐 · sof-tgl.ri 줄 · postinit 규칙 · 검사 1의
# 규칙 파일"의 수다. 덮지 않은 판은 11111이다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  echo \"mounted: \$(grep -c '^CONFIG_SND_SOC_SOF_TIGERLAKE=y' kernel/.config)\$(grep -c '^# CONFIG_SND_SOC_SOF_SKYLAKE is not set' kernel/.config)\$(grep -c 'intel-signed/sof-tgl.ri:' kernel/guest_firmware.sh)\$(grep -c '00-tars-dmic.conf\" <<' kernel/make_initrd.sh)\$(grep -c 'postinit/00-tars-dmic.conf; do' audio/check.sh)\"
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^AU check PASS' "$mut/$name.log" | head -2
```

체인 여섯 판(대조군 하나 포함). 판마다 1분 안팎, 합해서 5분 안팎 걸린다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/au3/impl/mut; X=/tmp/run/au3/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M k1 config_k1:kernel/.config
  $X $R $I $M k2 config_k2:kernel/.config
  $X $R $I $M f1 guest_firmware_f1.sh:kernel/guest_firmware.sh
  $X $R $I $M p1 make_initrd_p1.sh:kernel/make_initrd.sh
  $X $R $I $M p1_boot make_initrd_p1.sh:kernel/make_initrd.sh check_no1dmic.sh:audio/check.sh; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 10의 표에서 그 판의 `FAIL` 줄이고 `m0`은 `AU check PASS`다. `mounted:`는 `m0`이 `11111`이고 덮은 자리의 숫자가 0이다(`k1`
첫째 · `k2` 둘째 · `f1` 셋째 · `p1*` 넷째, `p1_boot`은 다섯째도). 로그에 `Killed`가 보이고 `FAIL: … build failed`로 끝나면 mutation의
결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시 돈다. 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다.
초록이면 먼저 덮기를 의심한다(`mounted:`).

호스트 검사 세 판(`audio.zig`를 사본으로 바꿔 `zig build test`).

```bash
M=/tmp/run/au3/impl/mut
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
for m in z1 z2 z3; do
  docker run --rm -v "$PWD":/workspace -v $M/audio_$m.zig:/workspace/init/src/audio.zig:ro -w /workspace tars-devcontainer bash -c '
    rm -rf init/.zig-cache; cd init; zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep "^FAIL" /tmp/t.log'
done
rmdir /tmp/run/docker.lock
```

기대: 세 판 다 `test exit=`가 0이 아니고, `FAIL` 줄이 확정 10의 둘째 표와 같다.

### 5-4. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. 커널 사본 판이 `kernel/build`를, 목록 사본 판이 firmware cpio를 다른
입력으로 만들어 두었으면 체인이 지금 파일로 다시 만든다(사본에서는 뒤 판이 이미 되돌려 두어 둘 다 `skipping`이었다).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out
  bash audio/check.sh > /tmp/a.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/a.log
  grep " inflate_fast$" kernel/build/System.map; stat -c "%s bzImage" kernel/build/arch/x86/boot/bzImage'
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `AU check PASS` · `ffffffff8148db40 T inflate_fast` · `8586240 bzImage`. `git status`는 `M` 열(`kernel/.config` ·
`kernel/guest_firmware.sh` · `kernel/vendor_firmware.sh` · `kernel/make_initrd.sh` · `init/src/audio.zig` · `init/src/audio_test.zig` ·
`audio/probe.sh` · `audio/check.sh` · `check.sh` · `tools/check.sh`)이고, plan이 commit 전이면 그것이 더 있다. 다른 것이 보이면(특히
`-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 5-5. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `10 files changed, 901 insertions(+), 68 deletions(-)`였다.
- Task 0의 출력.
- Task 1의 출력(`FOLDED` · 크기 · `inflate_fast` · `+CONFIG` 101줄 · `-` 세 줄).
- Task 2 · 3 · 4의 확인 출력(`SAME` · `SYNTAX-OK` · `119 entries` · `ENTRY-OK` · `anchors.py` · 호스트 검사).
- Task 5의 `exit=` · `real` · 마지막 줄들과 regression 아홉의 줄 · `init waited` · `all 92 tools` · `all 119 files`, mutation의
  `diff` 수 여덟 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 호스트 검사 세 판, 5-4의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 6: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 열 파일을 `/tmp/run/au3/new/`와 `cmp`한다. Task 5의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스무 체인 × 2다. 판정은 `PASS: 2/2` × 20과 `AU check PASS` 둘이다. `run_in_background`로
   돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다. 게이트 첫 회차가 `kernel/build`를 지우므로 커널을 처음부터 빌드한다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_au3.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_au3.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_au3.log`가 20,
   `rg -c 'AU check PASS' /tmp/gate_au3.log`가 2여야 한다.
3. 실측 절 채우기, design에 덧붙이기(아래 "design에 덧붙일 것"), design `Status:`.
4. commit. 넣는 것은 열 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다. sof-bin tarball과
   firmware cpio(`kernel/src/firmware/`)는 `.gitignore` 안이라 안 들어간다 — `git status`로 확인한다.
5. "lead가 결정할 것"(아래)을 정한다.

## design에 덧붙일 것

design 본문은 이 plan이 안 고쳤다. lead가 넣을 것.

1. 결정 1 끝에 "M3가 켠 것" 문단 — 확정 2의 열(`-e` 열여덟 · `-d` 일곱, `-k`)과 이유, Intel 세대 표와 AMD 리비전 표(7.x는 BIOS가 말하지
   않으면 범용 ACP 드라이버가 받는다), 범용 machine이 HDMI 코덱에 걸려 있어 HDMI 코덱 다섯이 켜진다는 것(비목표 6은 그대로),
   `SND_HDA_I915`가 없어 SOF가 GPU를 안 기다린다는 것, `SND_SOC_SDCA_HID`를 끈 이유, 크기 +372,736바이트, `inflate_fast`의 `0xb40`이
   그대로라 `init waited`가 1,700ms. 그리고 결정 1의 둘째 문단("SOF를 안 켠 커널에서는
   언제나 HDA로 간다")에 "M3부터는 DMIC가 있는 Intel 노트북이 SOF로 간다 — firmware가 없으면 HDA로 돌아오지 않는다"를 덧붙이고, 표의
   (c) 행을 "M3가 했다(SoundWire 코덱 · 앰프 제외)"로.
2. lead의 전제를 바로잡은 것 넷.
   - firmware의 출처가 Debian `firmware-sof-signed`가 아니라 sof-bin 릴리스다. trixie의 패키지(2025.01)에는 Panther Lake · Wildcat Lake가
     없고 이미지를 다시 구워야 한다. `vendor_firmware.sh`가 linux-firmware와 같은 방식(버전 · sha256)으로 받는다(확정 3).
   - AMD는 SOF가 아니라 PDM 드라이버다. AMD SOF의 firmware는 linux-firmware에도 sof-bin에도 없고, DMI 표에 없는 Ryzen 노트북의
     DMIC는 firmware 없는 PDM 드라이버가 받는다 — lead의 틀에 있던 `ACP63` · `ACP70`은 세대마다의 PDM 드라이버(`snd_pci_ps`)와, 7.x의
     기본 길인 범용 ACP 드라이버(`snd_acp_pci` + legacy machine)다(확정 1 · 2).
   - UCM은 싣지 않고 `-U`는 그대로다. alsa-ucm-conf의 부팅 순서가 Speaker · Headphone 스위치를 끈다(사운드 서버가 켠다고 본다). DMIC
     스위치는 alsactl의 postinit 규칙 한 줄이 켠다(확정 5).
   - SoundWire 코덱(`sof_sdw`)과 스피커 앰프 side codec은 M3에서 뺐다(확정 1). 둘 다 지금 조용한 기계를 그대로 두는 것이다.
3. 결정 하나를 새로 — 녹음의 기본 장치(확정 4). 세 단(USB 마이크 · 내장 DMIC · 장치 0), `/proc/asound/pcm`의 id로 알아본다, 장치 0이
   아니면 `plughw:CARD=N,DEV=D`, 후보 표 (b) ~ (e). 결정 4의 M1 덧붙임 문단 끝에 "UCM은 M3에서 다시 봤고 그대로 끈다(-U)"도.
4. 결정 5(게이트)의 검사 표 — 검사 1이 넓어지고(SOF · ACP 심볼 스물다섯 · 음성 일곱 · alias 열둘 · firmware 이름 대조 · 규칙 파일)
   부팅 D 끝에 검사 16 · 17이 더해졌다. 검사 17의 수법(사용자 컨트롤을 `alsactl -I restore`로 만들고 일꾼의 argv로 init)은 "QEMU에 없는
   컨트롤에 규칙을 시험하는 법"으로 lessons에도.
5. 위험 여섯.
   - (1) DMIC가 있는 Intel 노트북은 이제 스피커까지 SOF를 지난다. firmware · topology가 맞지 않거나 SOF가 그 기계에서 실패하면 M2까지
     되던 스피커가 조용해진다. 탈출로는 커널 인자 `snd_intel_dspcfg.dsp_driver=1`(running-tars.md에).
   - (2) IPC4(MTL 이후)의 범용 topology에 `-3ch`가 없다. DMIC 셋인 그 노트북은 topology를 못 찾는다(1)과 같은 증상).
   - (3) DMIC를 `plughw`로 연다 — 두 프로그램이 동시에 녹음하면 둘째가 `Device or resource busy`다(SOF · ACP 카드에는 alsa-lib의 dsnoop
     설정이 없다).
   - (4) M1의 일꾼은 `controlC0`이 서는 순간 있는 카드만 init한다. 카드가 여럿인 AMD 노트북(GPU 쪽 HDA · 아날로그 HDA · ACP)이나 SOF가
     firmware를 늦게 올려 5초(`CARD_WAIT_MS`)를 넘긴 Intel 노트북에서는 늦은 카드가 커널의 기본값(HDA는 꺼짐, DMIC 스위치 꺼짐)으로
     남는다. M2 확정 3의 "USB는 켜진 채 온다"는 내장 카드에는 안 맞는다. 실기에서 보면 lead가 결정할 것 2.
   - (5) DMIC를 PCM 이름(`DMIC`)으로 알아본다. 이름을 그렇게 안 짓는 machine(이 milestone이 안 켠 I2S 기계 등)은 장치 0 단으로 떨어진다.
   - (6) 게스트 RAM. firmware 원본 13.7MB가 initramfs에 늘 있고 512MB 게스트의 `MemAvailable`이 8MB 남짓 줄었다(세 판씩 190,296 ~
     192,664 → 182,276 ~ 184,532kB).
6. 실측 둘. `SND_DYNAMIC_MINORS`가 HDMI 코덱을 따라 켜져 `SNDRV_CARDS`가 8 → 32가 됐다(M2의 `MAX_CARDS = 32` 주석은 M2에서는 커널 쪽이
   8이었다). 그리고 `snd_pci_acp6x` · `snd_pci_ps`는 PCI 표가 `modules.builtin.modinfo`의 alias로 안 나온다(Renoir만 나온다).
7. Milestone 절의 AU-M3을 "했다"로, 그리고 다음 후보(lead가 결정할 것 1). "닫을 때"의 running-tars.md 소리 절에 넷 — `dmesg | grep -i sof`로
   `Firmware file:` · `Topology file:` 두 줄이 보이면 SOF가 선 것이고 `SOF firmware and/or topology file not found.`면 그 이름을 적어 알린다,
   탈출로 `snd_intel_dspcfg.dsp_driver=1`, `arecord -l`에서 `DMIC`가 든 장치가 기본 녹음이다(`cat /etc/asound.conf`), `amixer -c 0 sget 'Dmic0'`로
   내장 마이크의 스위치 · 볼륨.

## lead가 결정할 것

1. SoundWire 코덱 노트북(`sof_sdw`)과 스피커 앰프 side codec(CS35L41 · CS35L56 · TAS2781)을 M4로 열지, 비목표로 닫을지. 이 plan은 둘 다
   뺐다(확정 1). M4로 연다면 크기는 이렇게 본다 — `SOUNDWIRE` · `SOUNDWIRE_INTEL` · `SND_SOC_INTEL_SOUNDWIRE_SOF_MACH`와 코덱 열 남짓,
   topology는 sof-bin의 SoundWire 것 전부(24MB 원본) 또는 실기 목록에서 고른 것, 앰프는 SSID마다의 firmware(cirrus 5.5MB · ti 12MB). 게이트는
   이번과 같이 심볼 · alias · firmware 이름이다.
2. 늦은 내장 카드(design에 덧붙일 것 5의 위험 4). M1의 일꾼이 `controlC0` 하나만 기다렸다가 그 순간의 카드 전부에 alsactl을 부르므로
   카드가 여럿이거나 늦은 기계에서 일부가 꺼진 채 남을 수 있다. 고치는 자리는 둘이다 — 일꾼이 `/dev/snd`가 잠잠해질 때까지(예: 1초 동안
   안 바뀔 때까지, 상한 그대로) 기다리는 것, 또는 M2의 `follow`가 새 카드를 볼 때 `alsactl -U init N`을 부르는 것(M2 확정 3이 USB에는
   필요 없다고 정한 자리). QEMU의 체인은 카드 하나라 못 본다. 실기에서 겪은 뒤 정해도 된다.
3. ELKHARTLAKE를 둘지. 임베디드 세대지만 그 PCI ID가 TGL 드라이버의 표에 함께 있어 "커널이 찾는 이름은 전부 싣는다"를 예외 없이 세우려고
   두었다(firmware 525,056바이트). 끄면 검사 1의 이름 대조에서 `sof-ehl.ri`를 예외로 적어야 한다.
4. initrd와 RAM의 값 — gzip +6.25MB, `MemAvailable` −8MB 남짓. lessons의 이월 숙제(firmware가 게스트 RAM에 늘 있다)가 커졌다. 다음에
   firmware를 더하는 milestone(M4 등)은 그 숙제를 함께 본다.

## 이 milestone에서 안 하는 것

- SoundWire 코덱 노트북(`sof_sdw`)과 스피커 앰프 side codec(CS35L41 · CS35L56 · TAS2781) — 확정 1, lead가 결정할 것 1.
- AMD ACP6.2(리비전 0x62) — 6.18에 그 리비전의 PDM 드라이버가 없다(확정 2).
- AMD SOF(DMI 표에 오른 기계, firmware가 없다)와 Steam Deck(Vangogh, NAU8821 I2S) · Raven의 I2S machine · Intel I2S 코덱 machine(ES8336 ·
  RT5682 · MAX98357A 등 — 주로 Chromebook과 싼 노트북).
- UCM(alsa-ucm-conf) — 확정 5.
- 여러 프로그램이 DMIC를 함께 여는 것(dsnoop을 SOF · ACP 카드에 거는 alsa-lib 설정) — 위험 3.
- 헤드셋을 잭에 꽂았을 때 녹음이 잭 마이크로 넘어가는 것. 녹음의 기본은 꽂은 USB · 내장 DMIC · 장치 0이고 잭은 고르지 않는다 — 사람이
  `arecord -D plughw:0,0`(SOF)로 고른다. 자동으로 넘기는 것은 사운드 서버(PipeWire)의 일이다(design 비목표 2).
- 늦은 내장 카드를 켜는 것 — lead가 결정할 것 2.
- HDMI · DisplayPort 오디오(design 비목표 6). HDMI 코덱 드라이버가 범용 machine 때문에 켜졌지만 GPU 드라이버가 없다.
- `running-tars.md`의 소리 절. lead가 서브프로젝트를 닫을 때 쓴다.

## AU-M3가 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-06에 main 작업 트리에서 했고, lead가 열 파일을 `/tmp/run/au3/new/`와 `cmp`해 전부 같은
것을 봤다. 로그는 `/tmp/run/au3/impl/`, 루트 게이트는 `/tmp/gate_au3.log`.

1. 편집과 검사. 커널 `build 1` · `build 2` exit 0 · `FOLDED` · bzImage 8,586,240 · `inflate_fast` `ffffffff8148db40`. `.config` +473 −3
   (지운 줄은 `SND_DYNAMIC_MINORS` · `SND_HDA_CODEC_HDMI` · `SND_SOC`의 `is not set` 셋). sof-bin tarball 17,555,075바이트, sha256
   `42ce40ec…79b73` 일치, 한 번에 받았다. `git diff --stat` 10 files +901 −68. `zig build test` exit 0에 `audio_test` 줄 아홉.
   `audio` 체인 2분 13초 초록(`vendor_firmware: 119 files`). regression 아홉 전부 exit 0(`install` 108초 `init waited 1700ms` · `tools` 65 ·
   `boot` 24 · `machine` 20 · `wifi` 99 · `pointer` 75 · `nic` 32 · `power` 50 · `service` 71). mutation 체인 여섯 판 + 호스트 검사 셋이
   확정의 표와 같은 자리 · 글자로 빨갰다.
2. 기대와 다른 것은 바이트 수 둘뿐 — firmware cpio 45,027,634(plan 45,029,489) · initrd 96,866,530(plan 96,869,254). gzip 시각의 몫이다.
   `install` 로그의 `init waited`는 한 줄(1,700ms)이었다.
3. 루트 게이트. 스무 체인 × 2회, 52분 21초, `PASS: 2/2` 스물 · `AU check PASS` 둘 · `skipping make` 39. `audio`의 두 회차 — 부팅 A `tone`
   48,000 둘, `cap` 96,000/96,000, 부팅 D `usb tap` 48,000 둘 · 뽑은 뒤 48,000 · 47,879(xrun 자투리, `doubled` 0) · `cap D` 48,000/48,000.
   `install` 부팅 7 `init waited` 1,700ms. M2의 51분 10초에 1분 11초가 더해졌다 — 첫 회차의 firmware 내려받기와 initrd 6.3MB의 몫으로 본다.
