# AU-M0 — 커널의 ALSA · HDA, 게스트의 alsa-utils, 샘플을 값까지 보는 스무번째 체인

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-audio-devices-design.md`
Status: 끝났다(2026-10-06). plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에, 구현과 루트 게이트의 값은 맨 아래 "AU-M0이 실측한 것"에 있다. 다음은 AU-M1(`-au-m1.md`).

## 누가 무엇을 하나

design 결정 6. Task 0~6은 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. 권하는 모델은 Sonnet이다 — 판단이
새로 필요한 자리가 없다. 새 파일 둘은 사본을 복사하고, 편집 여덟은 글자 그대로 넣고, 커널 설정은 정해진 명령 한 줄과
되접기이고, 나머지는 이미지 굽기 · 체인 · mutation을 정해진 순서로 돌리는 일이다. Task 7(루트 게이트 2회 · 실측 절 ·
commit · 다음 plan)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/au0/repo/`)에 먼저 넣어 이미지 굽기 · 커널 빌드 · 체인 · regression · mutation까지
돌렸고, 아래의 새 파일 본문과 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/au0/render.py`). 기준은
HEAD `83d282b`의 파일(`/tmp/run/au0/base/`)이고 편집 뒤의 파일은 `/tmp/run/au0/new/`다. 구현자는 코드를 새로 짓지 않는다.
새 파일은 `new/`에서 `cp -p`하고, 편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고 — EL · CB의
구현자가 그렇게 했다), 각 Task 끝에서 `new/`와 `cmp`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다.
plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `kernel/.config` | 심볼 다섯(`SOUND` · `SND` · `SND_HDA_INTEL` · `SND_HDA_GENERIC` · `SYSVIPC`)을 `scripts/config`로 적고 `olddefconfig`로 되접는다(Task 1) | +147 −2 |
| `devcontainer/Dockerfile` | 편집 둘 — 층 14 주석 · 패키지 셋 | +22 |
| `kernel/guest_tools.sh` | 층 14 — 바이너리 넷 | +25 |
| `kernel/make_initrd.sh` | 편집 셋 — `arecord` 링크 · `/usr/share/alsa` · 목소리 둘 / `audio` 그룹의 주석 / `/etc/group`의 한 줄 | +31 |
| `audio/probe.sh` | 새 파일 — 게스트 쪽 프로브(설정 디스크의 `services.d/probe`) | +54 |
| `audio/check.sh` | 새 파일 — 스무번째 체인 | +328 |
| `check.sh` | 체인 설명 문단과 `CHAINS`의 `"AU-M0:./audio/check.sh"` | +7 |

합해서 7 files, +614 −2다. `init/` · `terminal/`의 Zig 코드는 한 줄도 안 바뀐다. `tools/check.sh`도 안 고친다 — 그 체인의
검사 1이 `guest_tools.sh`를 되읽어 새 바이너리 넷을 저절로 본다. `.gitignore`도 그대로다 — 체인이 만드는 디스크
`out/audio.img`는 `out/` 아래이고 루트 `check.sh`의 `clean()`이 지운다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다. M0은
서브프로젝트를 안 닫으므로 lead가 Task 7에서 실측 절과 design `Status:`만 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/au0/impl/` 아래에 둔다. `/tmp/run/au0/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run` · `docker build`를 아래로
감싼다. 명령이 실패해도 lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

이 milestone은 이미지(`tars-devcontainer`)를 다시 굽는다(Task 2). 구운 뒤의 이미지가 루트 게이트의 이미지다. 다른 에이전트가
그 이미지로 돌고 있으면 굽기를 미룬다.

## 이 milestone이 끝나면

- 커널이 사운드 카드를 안다. HDA 컨트롤러(`snd-hda-intel`)와 범용 코덱 파서가 QEMU의 HDA를 카드 0으로 올리고, `/dev/snd`에
  `controlC0` · `pcmC0D0p` · `pcmC0D0c` · `timer`가 생긴다. 실기의 노트북에서도 HDA 컨트롤러는 같은 드라이버가 잡는다 — 코덱의
  전용 드라이버(M2)와 DSP(M3)가 없을 뿐이다.
- 게스트에 `aplay` · `arecord` · `amixer` · `alsamixer` · `speaker-test`가 이름으로 있다. `aplay x.wav` · `arecord x.wav`처럼 장치를
  안 고른 명령이 기본 장치(dmix · dsnoop)로 돈다 — 커널의 `SYSVIPC`와 `/etc/group`의 `audio` 덕이다(design 결정 3).
- 부팅 직후 믹서는 꺼져 있다(Master · Capture 둘 다 `0 [0%] [-74.00dB] [off]`). 사람이 `amixer sset Master unmute 80%`를 쳐야
  들린다. 부팅이 켜는 것은 AU-M1이다(design 결정 4).
- 스무번째 체인 `audio/check.sh`가 생긴다. QEMU q35에 `ich9-intel-hda`와 `hda-micro`를 붙이고, QEMU의 `alsa` 백엔드가 컨테이너
  alsa-lib의 `file` 플러그인으로 스피커의 샘플을 파일에 받고 파일의 샘플을 마이크로 넣는다. 게스트 쪽은 설정 디스크의
  `services.d/probe`다. 게이트가 게스트에 한 글자도 안 치고, monitor를 안 쓰므로 포트도 없다.

로그 줄(정본 — `audio/probe.sh`가 찍고 `audio/check.sh`가 이 글자를 본다). 커널 줄 하나와 프로브 줄 열둘이다.

```
snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic: line_outs=1 (0x3/0x0/0x0/0x0/0x0) type:speaker
audio-probe: card [ 0 [Intel          ]: HDA-Intel - HDA Intel]
audio-probe: nodes [controlC0 pcmC0D0c pcmC0D0p timer]
audio-probe: aplay -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]
audio-probe: arecord -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]
audio-probe: master at boot [  Front Right: Playback 0 [0%] [-74.00dB] [off]]
audio-probe: capture at boot [  Front Right: Capture 0 [0%] [-74.00dB] [off]]
audio-probe: master now [  Front Right: Playback 74 [100%] [0.00dB] [on]]
audio-probe: aplay exit 0 []
audio-probe: speaker-test exit 0 [ 0 - Front Left| 1 - Front Right]
audio-probe: arecord exit 0 []
audio-probe: done
```

콘솔 줄에는 앞에 fish 프롬프트의 escape(`]7;file://(none)/` 같은 것)가 붙을 수 있다(lessons 68). 체인의 판정은 그래서 줄
머리 앵커를 안 쓰고, 끝을 봐야 하는 값은 프로브가 대괄호로 감싼다.

## 착수 전에 확정한 것

2026-10-05~06에 이 plan을 쓰며 코드와 커널 소스를 읽어 정했고, 저장소 사본(`/tmp/run/au0/repo/`)과 따로 구운 이미지
(`tars-devcontainer-au0`)로 쟀다. HEAD 쪽의 값은 HEAD를 그대로 복제한 `/tmp/run/au0/head/`에서 HEAD 이미지로 쟀다.
저장소의 작업 트리는 design과 이 plan 말고는 한 글자도 안 바뀌었다.

1. 커널. HEAD의 `kernel/.config`는 `olddefconfig`의 고정점이다(사본에서 `diff kernel/.config kernel/build/.config`가 비었다). 그래서
   PD-M3처럼 정규화 commit을 따로 만들 일이 없고, 이 milestone의 diff가 곧 소리가 들여온 줄의 전부다. Task 1의 명령(`scripts/config`
   다섯 · `olddefconfig`)을 HEAD 설정에 그대로 친 결과가 `new/kernel/.config`와 바이트까지 같았다(`FOLD-SAME`). `.config`는 +147 −2줄이고,
   `olddefconfig`가 따라 켠 `=y`는 design 실측 11에 있다. bzImage 7,758,848 → 7,955,456바이트, 증분 빌드 125초.

2. Dockerfile. 다운로드 목록에 `alsa-utils:amd64` · `libasound2t64:amd64` · `libasound2-data` 셋을 `libdbus-1-3:amd64` 바로 뒤에
   넣는다(`hostapd` · `busybox`는 게이트 전용이라 그 앞에 둔다). `libasound2-data`는 Architecture: all이라 `:amd64`가 없다. 이미지
   굽기가 1분 51초였다 — 다운로드 층이 통째로 다시 돈다. 구운 뒤 sysroot에 `usr/bin/aplay` · `usr/lib/x86_64-linux-gnu/libasound.so.2` ·
   `usr/share/alsa/alsa.conf`가 있다.

3. initrd. `guest_tools.sh` 층 14에 넷(`aplay` · `amixer` · `alsamixer` · `speaker-test`)이고 게스트 도구가 87 → 91이 된다. `arecord`는
   `ln -sf aplay`(패키지 안에서도 링크다), `/usr/share/alsa`는 `cp -r`(파일 86개 182,416바이트), 목소리는 `Front_Left.wav` ·
   `Front_Right.wav` 둘(289,118바이트), `/etc/group`에 `audio:x:29:`. initrd가 89,701,730 → 90,542,534바이트(+840,804)다.
   `copy_lib_deps`가 `libasound.so.2`와 `alsamixer`의 `libformw` · `libmenuw` · `libpanelw`를 따라온다.

4. 체인의 모양(design 결정 5). QEMU 호출은 q35 · `-nic none` · `ich9-intel-hda` · `hda-micro,audiodev=snd0`에
   `-audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,…`이고, 앞에 `HOME="$WORK"`를 붙여 컨테이너 alsa-lib이 체인이 쓴
   `$WORK/.asoundrc`를 읽게 한다. 백엔드의 속도 · 채널 · 형식을 48000 · 2 · s16으로 박는다 — QEMU의 기본 속도(44100)로 두면 QEMU가
   리샘플해 값이 바뀐다. `try-poll=off`는 `null` 장치에 기다릴 fd가 없어서다. 사각파(`tone.wav`)와 상수(`feed.raw`)는 체인이 perl로
   짓는다(컨테이너에 python이 없다 — `feedback_scripting_runtimes`). 설정 디스크는 `mkfs.ext2 -d`로 `tars.conf`(`shell=fish`) ·
   `services.d/probe` · `audio/tone.wav`를 한 번에 담는다(라벨 `tars-audio`). 녹음 파일은 프로브가 `/config/audio/cap.wav`에 쓰고
   `sync`하며, 체인이 QEMU를 끈 뒤 `debugfs -R "dump …"`로 꺼낸다.

   검사 일곱이다. 판정 글자는 위 "로그 줄"과 체인 파일의 `report_failure` 문구가 정본이다.

   | 검사 | 부팅 | 본다 | 사본의 값 |
   |---|---|---|---|
   | 1 | 없음 | `.config`의 다섯 · initrd의 여덟(`usr/bin/arecord` · libasound · `alsa.conf` · `HDA-Intel.conf` · `dmix.conf` · `dsnoop.conf` · 목소리 둘) · initrd `/etc/group`의 `audio:x:` | 초록 |
   | 2 | 있음 | 코덱 줄 · `card [ 0 [Intel …]: HDA-Intel - ` · 노드 넷 | 초록 |
   | 3 | 있음 | `aplay -l` · `arecord -l`이 카드 0 장치 0 | 초록 |
   | 4 | 있음 | 부팅 직후 Master · Capture가 `0 [0%] … [off]`, `amixer` 뒤 Master `74 [100%] [0.00dB] [on]` | 초록 |
   | 5 | 있음 | `aplay exit 0 []`, `tap.raw`의 사각파 프레임 47,000 이상, 그 밖의 양쪽 0 아닌 프레임 0 | `tone=48000 other=0` |
   | 6 | 있음 | `speaker-test exit 0 [ 0 - Front Left| 1 - Front Right]`, 왼쪽만 · 오른쪽만 각각 10,000 이상, 왼쪽이 먼저 | `left=53060 right=71059` |
   | 7 | 있음 | `arecord exit 0 []`, `cap.wav` 96,000프레임 전부 (3000, -5000) | `frames=96000 match=96000` |

   검사 2~7은 프로브가 `done`을 찍은 뒤 QEMU를 끄고 나서 본다. 프로브가 끝나기까지 부팅 뒤 10초 안팎이다.

5. 프로브. 첫 줄이 `#!/usr/bin/bash`다 — 게스트에 `/bin/bash`가 없어서 `#!/bin/bash`이면 `init`이 `execve … failed (errno 2)`를
   세 번 찍고 포기했다(design 실측 15). 카드 노드(`/dev/snd/controlC0`)를 5초까지 기다린 뒤 시작한다. 볼륨을 `100%`가 아니라 `0dB`로
   적는 이유는 체인이 샘플을 값으로 비교하기 때문이다 — QEMU의 코덱이 앰프 값을 샘플에 곱하고, 74단계 중 74가 0dB다. 일을 마치면
   `exec sleep 100000`으로 잠든다. 감독자는 끝난 서비스를 다시 띄우므로 나가면 같은 소리를 세 번 낸다.

6. 시간과 `install` 부팅 7. 커널이 바뀌면 코드 배치가 TCG의 initramfs 풀기를 움직인다(lessons PD-3). 같은 컨테이너 판에서 HEAD와
   M0을 나란히 쟀다(`/tmp/run/au0/meas/timing.sh`).

   | 무엇 | HEAD | M0 |
   |---|---|---|
   | `inflate_fast`(System.map) | `ffffffff81470ec0` | `ffffffff8147ab40` |
   | `Run /init`(render 체인과 같은 QEMU 호출, 세 번) | 3.73 · 3.75 · 3.75초 | 3.03 · 3.04 · 3.05초 |
   | `install` 체인 부팅 7의 `init waited`(두 판) | 1,100 · 1,200ms | 1,800 · 1,900ms |
   | `install` 체인 한 판 | 107 · 108초 | 103 · 104초 |

   M0 쪽이 0.7초 빠르다. 소리 드라이버가 일을 덜 하는 것이 아니라 풀기 루프가 놓인 자리의 몫으로 본다. 부팅 7의 여유가 늘었으므로
   `install/check.sh`는 안 고친다. 다음 커널 변경이 이것을 다시 움직일 수 있다.

7. mutation. 다섯 가지를 아홉 판으로 돌렸다(`/tmp/run/au0/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/au0/mut2/`). 앞 검사가 먼저
   잡는 것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다(lessons "mutation이 겨냥한 검사에 걸릴 것이라고 믿기").

   | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | 1 `SND_HDA_INTEL` 끄기 | `m1` | `config_m1` | 검사 1 | `FAIL: CONFIG_SND_HDA_INTEL is not =y in kernel/.config` | 24초 |
   | | `m1_boot` | + `check_nostatic.sh` | 검사 2(프로브는 `card [--- no soundcards ---]`) | `FAIL: the HDA codec was never configured (no snd_hda_codec_generic autoconfig line)` | 67초 |
   | 2 `SYSVIPC` 끄기 | `m2_boot` | `config_m2` + `check_nostatic.sh` | 검사 5(`unable to create IPC semaphore`) | `FAIL: aplay through the default device failed` | 127초 |
   | 3 프로브의 `amixer` 두 줄 빼기 | `m3` | `probe_m3.sh` | 검사 4의 셋째 | `FAIL: amixer could not set Master to 0dB and unmute it` | 18초 |
   | | `m3_play` | + `check_nonow.sh` | 검사 5 | `FAIL: the square wave did not reach the speaker (tone frames 0 of 48000); silence means the mixer was muted` | 17초 |
   | | `m3_rec` | + `check_nonow_no56.sh` | 검사 7 | `FAIL: the microphone did not deliver the fed constant (frames=96000 match=0, want 96000 of each); zeros mean Capture was off` | 18초 |
   | 4 `/etc/group`의 `audio` 빼기 | `m4` | `initrd_m4.sh` | 검사 1 | `FAIL: the initrd's /etc/group has no audio group; dmix and dsnoop need its name` | 8초 |
   | | `m4_boot` | + `check_nogroup.sh` | 검사 5(`The field ipc_gid must be a valid group`) | `FAIL: aplay through the default device failed` | 13초 |
   | 5 `/usr/share/alsa` 빼기 | `m5` | `initrd_m5.sh` | 검사 1 | `FAIL: usr/share/alsa/alsa.conf is missing from the initrd` | 7초 |
   | | `m5_boot` | + `check_nostatic.sh` | 검사 3(`Cannot access file /usr/share/alsa/alsa.conf`) | `FAIL: aplay -l does not list the speaker` | 11초 |

   읽을 것 셋.
   - mutation 3의 `m3_play`가 이 체인의 중심이다. 프로브가 소리를 안 켜면 QEMU 밖에 0만 나온다(`tone=0 … zero=196433`). 검사 5는
     "aplay가 성공했다"가 아니라 "샘플이 값까지 닿았다"를 보므로 꺼진 믹서를 잡는다. AU-M1이 부팅에서 소리를 켜면 같은 고장을
     검사 4가 뒤집힌 모양으로 본다.
   - mutation 2와 4는 같은 문구(`aplay through the default device failed`)로 빨개지고, 원인은 `report_failure`가 찍는 `audio-probe:` 줄이
     가른다. 둘 다 `-D hw:0,0`으로는 도는 고장이라 사람이 치는 모양(장치를 안 고른다)으로만 드러난다.
   - mutation 1의 `m1` 판 24초는 커널 재빌드가 조금이라서다(HDA 컨트롤러 파일 몇 개). `m2_boot`의 127초가 `SYSVIPC`가 끌어가는 재빌드다.

8. regression. 커널과 initrd가 바뀌므로 넷을 사본에서 돌렸다. 넷 다 exit 0이다.

   | 체인 | 시간(데운 판) | 왜 돌렸나 |
   |---|---|---|
   | `install` | 103 · 104초 | 부팅 7의 창(확정 6) |
   | `tools` | 64초 | 도구 목록이 91이 됐다. `the initrd carries the four bones and all 91 tools the list names` |
   | `boot` | 23초 | limine이 BIOS로 initrd를 읽는다. initrd가 0.8MB 커졌다 |
   | `machine` | 19초 | q35 · OVMF · simpledrm. 새 커널이 실기의 길에서 뜬다 |

   그 밖의 체인은 QEMU에 소리 장치를 안 붙이므로 커널의 HDA 드라이버가 할 일이 없다. 루트 게이트가 전부를 본다.

9. `audio` 체인 시간. 사본에서 `init` · `terminal`의 캐시를 지운 첫 판이 1분 56초(커널 재빌드 포함), 데운 판이 17 · 18초였다. 세
   판의 `tap:` · `cap:` 값이 같았다. 루트 게이트는 이 체인을 두 번 돌리므로 PD-M4 · CB 뒤의 값(51분 남짓)에 1분 안쪽을 더한 것으로 본다
   — 첫 체인의 커널 전체 빌드는 이 milestone이 없어도 치르던 것이다.

10. 낡은 산출물. 이 milestone은 Zig 코드를 안 고치지만 아래 명령은 전부 캐시 삭제를 같은 `docker run` 안에 둔다
    (`project_zig_out_staleness`). 커널은 `build.sh`의 sha256 스탬프가 지킨다.

11. 앵커. 편집 여덟의 `old_string`이 HEAD 파일에 정확히 한 번씩 있고(`python3 /tmp/run/au0/anchors.py pre "$PWD"` → `pre: 8 edits, 0 bad`),
    `new_string`이 사본에 정확히 한 번씩 있다(`post: 8 edits, 0 bad`). 진입 검사 셋도 사본의 `audio/check.sh`에서 `ENTRY-OK`였다.

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

   기대: `git status`는 이 plan과 design이 commit 전이면 그 둘뿐이고, lead가 고치는 중일 수 있는 `HANDOFF.md` · `MEMORY.md` ·
   `docs/decisions/`의 기억 파일이 더 있을 수 있다. 맨 위 commit이 `83d282b Close clipboard scope: …`이거나 그 위에 lead의 commit이
   있다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 11).

   ```bash
   python3 /tmp/run/au0/anchors.py pre "$PWD"
   ```

   기대: `pre: 8 edits, 0 bad`. 하나라도 `bad`면 그 줄을 보고하고 멈춘다.

4. 커널 설정이 고정점인지 본다(확정 1). `kernel/build`가 없으면 이 단계는 건너뛰고 그렇다고 적는다.

   ```bash
   diff kernel/.config kernel/build/.config && echo FIXED-POINT
   ```

   기대: `FIXED-POINT`.

## Task 1: `kernel/.config` — 심볼 다섯과 되접기

design 결정 1 · 3. `.config`에는 주석을 안 쓴다(`project_kernel_config`). 커널 빌드가 2분 남짓, 되접은 뒤의 빌드가 30초 안팎이다.

### 1-1. 적고, 빌드하고, 되접는다

```bash
mkdir -p /tmp/run/au0/impl
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
    kernel/src/linux-6.18.42/scripts/config --file kernel/.config \
      -e SOUND -e SND -e SND_HDA_INTEL -e SND_HDA_GENERIC -e SYSVIPC
    (cd kernel && ./build.sh > /tmp/k1.log 2>&1); echo "build 1 exit=$?"
    cp kernel/build/.config kernel/.config
    (cd kernel && ./build.sh > /tmp/k2.log 2>&1); echo "build 2 exit=$?"
    diff kernel/.config kernel/build/.config && echo FOLDED
    stat -c "%s bzImage" kernel/build/arch/x86/boot/bzImage
    grep " inflate_fast$" kernel/build/System.map' ; } 2>&1 | tail -8
rmdir /tmp/run/docker.lock
```

기대: `build 1 exit=0` · `build 2 exit=0` · `FOLDED` · `7955456 bzImage` · `ffffffff8147ab40 T inflate_fast`.

### 1-2. 확인

```bash
cmp kernel/.config /tmp/run/au0/new/kernel/.config && echo SAME-config
git diff --stat kernel/.config
git diff kernel/.config | rg '^-[^-]'
```

기대: `SAME-config`, `1 file changed, 147 insertions(+), 2 deletions(-)`, 지운 줄 둘은 `-# CONFIG_SYSVIPC is not set` · `-# CONFIG_SOUND is not set`.

## Task 2: `devcontainer/Dockerfile` — 패키지 셋과 이미지

design 결정 2. 편집 둘을 넣고 이미지를 다시 굽는다. 굽기가 2분 안팎이다.

### 2-1. 편집

E1 — `old_string`(기준 파일 297줄부터):

```
# initrd에는 안 들어간다. 라이브러리는 0개다 — 스크립트다.
```

`new_string`:

```
# initrd에는 안 들어간다. 라이브러리는 0개다 — 스크립트다.
#
# ── AU-M0: 층 14(소리) ────────────────────────────────────────────────
#
# alsa-utils의 바이너리 넷(aplay · amixer · alsamixer · speaker-test)과 그것이
# 부르는 libasound, 그리고 libasound가 여는 설정 트리다. 넷 다 NEEDED가
# libasound.so.2 · libm · libc뿐이고, alsamixer만 ncurses의 form · menu ·
# panel을 더 부른다 — 셋 다 libncursesw6 안에 이미 있다(AU design 실측 5).
# 그래서 새 라이브러리는 libasound 하나다.
#
#   alsa-utils        바이너리. 나머지(alsactl · alsaloop · alsabat · aseq*
#                     · amidi 등)는 sysroot에만 풀린다
#   libasound2t64     libasound.so.2, 1,178,192바이트
#   libasound2-data   /usr/share/alsa(alsa.conf · cards · pcm). libasound가
#                     컴파일 타임에 박아 둔 경로라 없으면 aplay -l부터 죽는다.
#                     Architecture: all이라 :amd64를 안 붙인다
#
# alsa-utils의 Depends 중 libatopology · libfftw3 · libsamplerate는 안 받는다 —
# alsatplg · alsabat · alsaloop의 것이고 우리는 그 셋을 안 싣는다. kmod도
# 안 받는다(커널에 모듈이 없다).
```

E2 — `old_string`(기준 파일 429줄부터):

```
        libdbus-1-3:amd64 \
```

`new_string`:

```
        libdbus-1-3:amd64 \
        alsa-utils:amd64 \
        libasound2t64:amd64 \
        libasound2-data \
```

### 2-2. 이미지를 굽고 sysroot를 본다

```bash
cmp devcontainer/Dockerfile /tmp/run/au0/new/devcontainer/Dockerfile && echo SAME-Dockerfile
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker build -t tars-devcontainer devcontainer/ > /tmp/run/au0/impl/image.log 2>&1 ; echo "build exit=$?" ; } 2>&1 | tail -4
docker run --rm tars-devcontainer bash -c 'cd $AMD64_SYSROOT && ls usr/bin/aplay usr/bin/arecord usr/bin/amixer usr/bin/alsamixer usr/bin/speaker-test usr/lib/x86_64-linux-gnu/libasound.so.2 usr/share/alsa/alsa.conf usr/share/sounds/alsa/Front_Left.wav'
rmdir /tmp/run/docker.lock
```

기대: `SAME-Dockerfile`, `build exit=0`, `ls`가 여덟 경로를 에러 없이 찍는다. `--platform`을 붙이지 않는다(`project_build_host_arch`).

## Task 3: `kernel/guest_tools.sh` · `kernel/make_initrd.sh` — 바이너리 넷 · 링크 · 설정 트리 · 목소리 · 그룹

design 결정 2 · 3.

### 3-1. `guest_tools.sh` — 층 14

E1 — `old_string`(기준 파일 347줄부터):

```bash
  usr/bin/which.debianutils:usr/bin/which
```

`new_string`:

```bash
  usr/bin/which.debianutils:usr/bin/which

  # ── 층 14 · 소리(AU-M0) ────────────────────────────────────────────────
  # 사용자가 2026-10-05에 요청했다("오디오(마이크/이어폰/스피커) 기기 활성화").
  # 커널의 ALSA가 /dev/snd에 내놓은 장치를 사람이 이름으로 부르는 넷이다.
  #
  #   aplay         재생. 녹음(arecord)은 같은 바이너리의 두 번째 이름이라
  #                 여기 없고 make_initrd.sh가 링크로 건다(vi와 같은 자리)
  #   amixer        믹서. 커널이 소리를 꺼 둔 채 뜨므로(AU design 결정 4) 사람이
  #                 처음 치는 것이 `amixer sset Master unmute`다. AU-M1이 그 일을
  #                 부팅으로 옮길 때까지는 이것이 유일한 길이다
  #   alsamixer     같은 일의 화면판. 화면을 통째로 가져가는 대화형이라 게이트가
  #                 못 친다(htop · btop과 같다) — 목록 검사가 전부다
  #   speaker-test  왼쪽 · 오른쪽 스피커를 목소리로 확인한다. 그 목소리 파일 둘은
  #                 make_initrd.sh가 넣는다
  #
  # 새 라이브러리는 libasound 하나다(1,178,192바이트). alsamixer가 부르는
  # libformw · libmenuw · libpanelw는 sysroot의 libncursesw6 패키지에 이미 있던
  # 것이고 initrd에는 이번에 처음 들어간다. alsactl은 안 싣는다 — 부팅에 믹서를
  # 되살리는 일은 AU-M1이고, 어떻게 할지는 그 milestone이 정한다.
  # audio/check.sh가 넷 중 aplay · arecord · amixer · speaker-test를 게스트에서
  # 실제로 돌린다.
  usr/bin/aplay:usr/bin/aplay
  usr/bin/amixer:usr/bin/amixer
  usr/bin/alsamixer:usr/bin/alsamixer
  usr/bin/speaker-test:usr/bin/speaker-test
```

### 3-2. `make_initrd.sh` — 편집 셋

E1이 `nc` 링크 뒤에 소리 블록을, E2가 `/etc/passwd` heredoc 앞의 주석에 `audio` 그룹의 이유를, E3이 `/etc/group`에 한 줄을 넣는다.

E1 — `old_string`(기준 파일 265줄부터):

```bash
# NW-M2. dhcpcd가 쓰는 자리 둘(M0 실측 7). 리스는 /var/lib/dhcpcd/eth0.lease에
```

`new_string`:

```bash
# AU-M0. 소리에 딸린 것 셋. 바이너리 넷은 guest_tools.sh의 층 14에 있다.
#
# arecord는 aplay의 두 번째 이름이다. 바이너리 하나가 argv[0]을 보고 재생과 녹음을
# 가른다 — .deb 안에서도 arecord -> aplay 링크다. vi -> vim과 같은 이유로 링크를
# 건다(guest_tools.sh에 두 줄을 적으면 install_tool이 링크를 따라가 같은 실체를 두
# 벌 복사한다).
ln -sf aplay "$WORKDIR/usr/bin/arecord"

# /usr/share/alsa는 libasound가 컴파일 타임에 박아 둔 설정 트리다. alsa.conf가
# 없으면 aplay -l부터 `Cannot access file /usr/share/alsa/alsa.conf`로 죽는다.
# cards/HDA-Intel.conf · pcm/dmix.conf 등 파일 86개가 182,416바이트라 고르지 않고
# 통째로 넣는다(zoneinfo와 같은 판단). init/ 아래는 alsactl init의 규칙이라 지금은
# 아무도 안 읽지만 같은 트리의 일부다.
mkdir -p "$WORKDIR/usr/share"
cp -r "$SYSROOT/usr/share/alsa" "$WORKDIR/usr/share/"

# speaker-test -t wav가 채널마다 읽는 목소리 파일. 2채널(-c 2)이 읽는 둘만
# 넣는다 — 나머지 일곱(Center · Rear · Side · Noise)은 노트북에 없는 채널이다.
# 둘이 289,118바이트다. 사람이 왼쪽에서 "Front Left"를 듣는 것이 스피커 배선을
# 확인하는 가장 빠른 길이다.
mkdir -p "$WORKDIR/usr/share/sounds/alsa"
cp "$SYSROOT/usr/share/sounds/alsa/Front_Left.wav" \
  "$SYSROOT/usr/share/sounds/alsa/Front_Right.wav" "$WORKDIR/usr/share/sounds/alsa/"

# NW-M2. dhcpcd가 쓰는 자리 둘(M0 실측 7). 리스는 /var/lib/dhcpcd/eth0.lease에
```

E2 — `old_string`(기준 파일 401줄부터):

```bash
# /usr/sbin/nologin은 게스트에 없지만 sshd는 그 자리를 실행하지 않는다.
```

`new_string`:

```bash
# /usr/sbin/nologin은 게스트에 없지만 sshd는 그 자리를 실행하지 않는다.
#
# AU-M0: audio 그룹. alsa-lib의 기본 장치(dmix · dsnoop)가 공유 메모리를 그
# 그룹의 것으로 만들려고 이름을 찾는다. 없으면 `aplay x.wav`가 `The field ipc_gid
# must be a valid group (create group audio)`로 죽는다 — -D hw:0으로 장치를 직접
# 고르면 돌아서, 사람은 "가끔만 안 된다"로 겪는다(AU design 결정 3). 29는 Debian의
# 번호다. 우리는 root로 돌므로 구성원을 안 적는다.
```

E3 — `old_string`(기준 파일 408줄부터):

```bash
nogroup:x:65534:
```

`new_string`:

```bash
audio:x:29:
nogroup:x:65534:
```

### 3-3. 확인

```bash
for f in kernel/guest_tools.sh kernel/make_initrd.sh; do cmp $f /tmp/run/au0/new/$f && echo "SAME $f"; done
bash -n kernel/make_initrd.sh && bash -n kernel/guest_tools.sh && echo SYNTAX-OK
```

기대: `SAME` 둘과 `SYNTAX-OK`.

## Task 4: `audio/probe.sh` · `audio/check.sh`(새 파일) · `check.sh`

design 결정 5.

### 4-1. 새 파일 둘

사본에서 실행 비트째 복사한다.

```bash
mkdir -p audio
cp -p /tmp/run/au0/new/audio/probe.sh /tmp/run/au0/new/audio/check.sh audio/
ls -l audio/
```

기대: 둘 다 `-rwxr-xr-x`. 본문은 아래와 같다.

`audio/probe.sh`:

```bash
#!/usr/bin/bash
# AU 체인의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(wifi/ap.sh와 같은 자리).
#
# init이 /config/services.d의 실행 파일로 이것을 띄우고, 표준 출력은 init의 것(=
# /dev/console = 시리얼 로그)이다. 그래서 여기서 찍는 줄을 audio/check.sh가 시리얼
# 로그에서 본다. 게이트가 게스트에 한 글자도 안 치는 이유가 이것이다.
#
# 사람이 노트북에서 치는 것과 같은 명령만 쓴다 — aplay · arecord · amixer ·
# speaker-test, 장치를 고르는 -D 없이. 기본 장치(dmix · dsnoop)까지 지나야
# "사람이 aplay x.wav를 치면 소리가 난다"를 본 것이 되기 때문이다(AU design 결정 3).
#
# 끝나면 잠든다. 감독자는 끝난 서비스를 다시 띄우므로(SV), 일을 마친 뒤에 나가면
# 같은 소리를 세 번 내고 포기한다.

say() { echo "audio-probe: $*"; }

# 여러 줄 출력을 한 줄로. 콘솔 줄은 앞뒤에 다른 바이트가 붙을 수 있어서(lessons 68)
# 체인이 줄 끝을 앵커로 못 쓴다 — 끝을 봐야 하는 것은 대괄호로 감싼다.
flat() { tr '\n' '|' | sed 's/|$//'; }

# 1. 카드. HDA 코덱 탐색은 커널이 일 큐에서 하므로 init보다 늦을 수 있다. 5초까지 본다.
for _ in $(seq 1 50); do
  [ -e /dev/snd/controlC0 ] && break
  sleep 0.1
done
say "card [$(head -n 1 /proc/asound/cards)]"
say "nodes [$(ls /dev/snd | tr '\n' ' ' | sed 's/ $//')]"
say "aplay -l [$(aplay -l 2>&1 | grep '^card ' | flat)]"
say "arecord -l [$(arecord -l 2>&1 | grep '^card ' | flat)]"

# 2. 부팅이 남긴 믹서. 커널의 HDA 드라이버는 Master와 Capture를 0에 꺼 둔 채 뜬다.
# AU-M1이 부팅에서 되살리기 전까지는 사람이 아래 3을 손으로 한다.
say "master at boot [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

# 3. 사람이 하는 일 — 소리를 켠다. 0dB인 이유는 체인이 샘플을 바이트로 비교하기
# 때문이다. QEMU의 HDA 코덱이 이 값을 샘플에 그대로 곱한다.
amixer -q -c 0 sset Master 0dB unmute
amixer -q -c 0 sset Capture 0dB cap
say "master now [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"

# 4. 재생 둘. 둘 다 기본 장치로 간다.
out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
say "aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
out="$(speaker-test -c 2 -t wav -l 1 2>&1)"; rc=$?
say "speaker-test exit ${rc} [$(printf '%s' "$out" | grep -E 'error|Front' | flat)]"

# 5. 녹음 2초. 파일은 설정 디스크에 남기고 체인이 끈 뒤에 debugfs로 꺼낸다.
out="$(arecord -q -d 2 -f S16_LE -r 48000 -c 2 /config/audio/cap.wav 2>&1)"; rc=$?
say "arecord exit ${rc} [$(printf '%s' "$out" | flat)]"
sync
say "done"

exec sleep 100000
```

`audio/check.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# AU 체인 — 게스트의 스피커와 마이크에 바이트가 오간다.
#
# QEMU에 노트북의 HDA를 흉내 내는 장치를 붙인다(q35의 ich9-intel-hda와 스피커 하나 ·
# 마이크 하나를 가진 hda-micro 코덱). 커널의 snd-hda-intel과 범용 코덱 드라이버가 그것을
# 카드 0으로 올리고, 설정 디스크의 services.d/probe(= audio/probe.sh)가 사람이 치는 명령
# 그대로(aplay · speaker-test · arecord) 소리를 내고 받는다. 이 스크립트는 게스트에 한
# 글자도 안 친다.
#
# 판정이 바이트로 닫히는 것이 이 체인의 성질이다(AU design 결정 5). QEMU의 오디오
# 백엔드를 alsa로 두고, 컨테이너의 alsa-lib이 읽는 .asoundrc에 file 플러그인 둘을
# 정의한다.
#
#   스피커 → tarstap   게스트가 낸 샘플이 컨테이너의 파일(TAP)에 그대로 쌓인다
#   마이크 ← tarsfeed  컨테이너의 파일(FEED)이 게스트의 마이크로 들어간다
#
# 그래서 "재생이 됐다"는 게스트가 보낸 사각파가 TAP에 값까지 같게 있는 것이고, "녹음이
# 됐다"는 FEED의 상수가 게스트가 쓴 cap.wav에 값까지 같게 있는 것이다. QEMU의 wav
# 백엔드는 녹음 쪽이 없어서(`Could not create a backend for voice 'adc'`) 마이크를 못 본다.
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘(AU-M2 · M3), 부팅이 믹서를 되살리는 것(AU-M1). 검사 4가 지금은 "부팅이 소리를
# 꺼 둔 채 둔다"를 보고, M1이 그 검사를 뒤집는다.

# $GUEST_MEM 하나 때문에 source한다. nic · wifi 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

DISK=../out/audio.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG" "$WORK"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "snd_hda_codec_generic hdaudioC0D0: autoconfig" \
    "tars-init: started service probe (pid" \
    "audio-probe: card [" \
    "audio-probe: aplay -l [card 0" \
    "audio-probe: master now [" \
    "audio-probe: aplay exit 0" \
    "audio-probe: speaker-test exit 0" \
    "audio-probe: arecord exit 0" \
    "audio-probe: done"; do
    if grep -aF "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- audio-probe lines ---"
  grep -a "audio-probe:" "$LOG" | tail -n 20
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

wait_for_log() {
  local pattern="$1" seconds="$2" i
  for i in $(seq 1 "$seconds"); do
    if grep -aE "$pattern" "$LOG" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
}

# ── 검사 1: 커널과 initrd가 소리를 안다 (부팅 없음) ─────────────────────
# 심볼 다섯. SYSVIPC가 여기 있는 이유는 alsa-lib의 기본 장치(dmix · dsnoop)가 SysV
# 세마포어와 공유 메모리로 여러 프로그램을 섞기 때문이다 — 꺼져 있으면 -D hw:0은 돌고
# 기본 장치만 `unable to create IPC semaphore`로 죽는다(AU design 결정 3).
CONFIG=../kernel/.config
for sym in SOUND SND SND_HDA_INTEL SND_HDA_GENERIC SYSVIPC; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done

# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
# 목록에 없고 make_initrd.sh가 손으로 넣는 것만 literal로 적는다 — 그래야 이 검사가
# tautology가 아니다(tools 체인의 WANT와 같은 이유).
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
for want in usr/bin/arecord lib/x86_64-linux-gnu/libasound.so.2 \
  usr/share/alsa/alsa.conf usr/share/alsa/cards/HDA-Intel.conf \
  usr/share/alsa/pcm/dmix.conf usr/share/alsa/pcm/dsnoop.conf \
  usr/share/sounds/alsa/Front_Left.wav usr/share/sounds/alsa/Front_Right.wav; do
  case "$PADDED_LIST" in
    *$'\n'"${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} is missing from the initrd"
      exit 1
      ;;
  esac
done
GROUPS_FILE="$(gzip -dc ../kernel/initrd.cpio | cpio -i --to-stdout etc/group 2>/dev/null)"
case $'\n'"${GROUPS_FILE}" in
  *$'\n'"audio:x:"*) ;;
  *)
    echo "FAIL: the initrd's /etc/group has no audio group; dmix and dsnoop need its name"
    exit 1
    ;;
esac
echo "the kernel carries ALSA and HDA, and the initrd carries arecord, libasound, its config, two voices and the audio group"

# ── 재료: 사각파 · 마이크에 넣을 상수 · 설정 디스크 · .asoundrc ─────────
# 컨테이너에 python이 없어서 perl로 짓는다(lessons).
#
# tone.wav — 48kHz 스테레오 16비트 1초. 24프레임마다 +8000과 -8000을 오가는 1kHz
# 사각파다. 값이 둘뿐이라 TAP에서 그 둘을 세면 된다. 48kHz인 이유는 dmix의 기본
# 속도와 같아서 리샘플이 안 끼기 때문이다 — 끼면 값이 바뀐다.
# feed.raw — 왼쪽 3000 · 오른쪽 -5000의 상수 10초. 두 채널이 다른 값이라 좌우가
# 바뀌어도 드러난다. 10초는 녹음 2초보다 넉넉하게.
TONE_FRAMES=48000
perl -e '
  my $n = shift; my $data = "";
  for my $i (0 .. $n - 1) { my $v = (int($i / 24) % 2) ? -8000 : 8000; $data .= pack("s<s<", $v, $v); }
  print "RIFF", pack("V", 36 + length $data), "WAVEfmt ", pack("VvvVVvv", 16, 1, 2, 48000, 192000, 4, 16),
        "data", pack("V", length $data), $data;' "$TONE_FRAMES" > "$WORK/tone.wav"
perl -e 'print pack("s<s<", 3000, -5000) x 480000' > "$WORK/feed.raw"

mkdir -p ../out "$WORK/seed/services.d" "$WORK/seed/audio"
cp probe.sh "$WORK/seed/services.d/probe"
chmod 0755 "$WORK/seed/services.d/probe"
cp "$WORK/tone.wav" "$WORK/seed/audio/tone.wav"
printf 'shell=fish\n' > "$WORK/seed/tars.conf"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK"

# null이 시간을 내고 file이 바이트를 바꿔치기한다. 녹음 쪽은 null이 준 무음을 infile의
# 바이트로 덮고, 재생 쪽은 받은 바이트를 file에 쓴다. 둘 다 alsa-lib에 들어 있는
# 플러그인이라 컨테이너에 더 깔 것이 없다.
cat > "$WORK/.asoundrc" <<EOF
pcm.tarstap {
  type file
  slave.pcm "null"
  file "$WORK/tap.raw"
  format "raw"
}
pcm.tarsfeed {
  type file
  slave.pcm "null"
  file "/dev/null"
  infile "$WORK/feed.raw"
  format "raw"
}
EOF

# ══ 부팅 하나 ═══════════════════════════════════════════════════════════
# q35인 이유는 nic · machine 체인과 같다 — 노트북에 가까운 칩셋이고, ich9-intel-hda가
# 노트북의 HDA 컨트롤러와 같은 계열이다. hda-micro는 스피커 하나와 마이크 하나를 가진
# 코덱이다(노트북의 내장 스피커 · 마이크와 같은 모양). 백엔드의 속도와 형식을 48kHz
# 스테레오 16비트로 박아 QEMU가 샘플을 바꾸지 않게 한다. try-poll=off는 null 장치에
# 기다릴 fd가 없어서다.
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

# ── 검사 2: 커널이 코덱을 찾아 카드 0을 만들었나 ────────────────────────
# 코덱 줄은 커널의 것이고 카드 줄은 /proc/asound/cards의 첫 줄이다. 노드 셋은 사람이
# 여는 파일이다 — 제어(controlC0) · 재생(pcmC0D0p) · 녹음(pcmC0D0c).
wait_for_log 'snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic' 60 \
  || report_failure "the HDA codec was never configured (no snd_hda_codec_generic autoconfig line)"
wait_for_log 'audio-probe: done' 90 \
  || report_failure "the probe did not finish"
stop_guest
if ! grep -aE 'audio-probe: card \[ ?0 \[.*\]: HDA-Intel - ' "$LOG" >/dev/null; then
  report_failure "card 0 is not the HDA controller"
fi
if ! grep -aF 'audio-probe: nodes [controlC0 pcmC0D0c pcmC0D0p timer]' "$LOG" >/dev/null; then
  report_failure "/dev/snd does not hold the control, playback and capture nodes of card 0"
fi
echo "the kernel configured the codec as card 0 with a playback and a capture node"

# ── 검사 3: 도구가 라이브러리와 설정을 지나 카드를 보나 ─────────────────
# aplay · arecord는 libasound를 부르고, libasound는 /usr/share/alsa/alsa.conf를 읽어야
# 장치 목록을 낸다. 둘 중 하나라도 빠지면 이 줄들의 대괄호 안이 비거나 에러다.
if ! grep -aF 'audio-probe: aplay -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]' "$LOG" >/dev/null; then
  report_failure "aplay -l does not list the speaker"
fi
if ! grep -aF 'audio-probe: arecord -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]' "$LOG" >/dev/null; then
  report_failure "arecord -l does not list the microphone"
fi
echo "aplay -l and arecord -l both see card 0 device 0"

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

# TAP의 프레임을 갈래로 센다. tone은 사각파의 두 값, left · right는 한쪽만 소리가 있는
# 것(speaker-test의 목소리), other는 두 채널이 다 0이 아니면서 사각파도 아닌 것이다.
# first_*는 그 갈래가 처음 나온 프레임 번호다.
count_tap() {
  perl -e '
    open(my $f, "<:raw", $ARGV[0]) or die "cannot open $ARGV[0]\n"; local $/; my $d = <$f>;
    my ($i, $tone, $l, $r, $o, $z, $fl, $fr) = (0, 0, 0, 0, 0, 0, -1, -1);
    for (my $p = 0; $p + 4 <= length $d; $p += 4, $i++) {
      my ($a, $b) = unpack("s<s<", substr($d, $p, 4));
      if (($a == 8000 && $b == 8000) || ($a == -8000 && $b == -8000)) { $tone++ }
      elsif ($a == 0 && $b == 0) { $z++ }
      elsif ($b == 0) { $l++; $fl = $i if $fl < 0 }
      elsif ($a == 0) { $r++; $fr = $i if $fr < 0 }
      else { $o++ }
    }
    print "frames=$i tone=$tone left=$l right=$r other=$o zero=$z first_left=$fl first_right=$fr\n";' "$1"
}
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# ── 검사 5: 재생 — 게스트의 사각파가 값까지 같게 스피커에 닿았나 ───────
# 48,000프레임 중 47,000 이상을 요구한다. 기본 장치(dmix)는 한 프로그램만 쓸 때 샘플을
# 안 바꾸고, 사본에서 세 판 다 48,000이었다. 여유 1,000은 스트림 끝의 자투리 몫이다.
# other가 0인 것은 섞이거나 깎인 샘플이 없다는 뜻이다.
if ! grep -aF 'audio-probe: aplay exit 0 []' "$LOG" >/dev/null; then
  report_failure "aplay through the default device failed"
fi
[ -f "$WORK/tap.raw" ] || report_failure "QEMU never opened the speaker side (no tap file)"
TAP="$(count_tap "$WORK/tap.raw")"
echo "tap: ${TAP}"
if [ "$(field "$TAP" tone)" -lt 47000 ]; then
  report_failure "the square wave did not reach the speaker (tone frames $(field "$TAP" tone) of ${TONE_FRAMES}); silence means the mixer was muted"
fi
if [ "$(field "$TAP" other)" -ne 0 ]; then
  report_failure "the speaker got $(field "$TAP" other) frame(s) that are neither the square wave nor one-sided"
fi
echo "aplay's square wave reached the speaker sample for sample"

# ── 검사 6: 왼쪽이 먼저, 오른쪽이 나중 ─────────────────────────────────
# speaker-test -c 2 -t wav는 "Front Left"를 왼쪽 채널에만, 그다음 "Front Right"를 오른쪽에만
# 낸다. 좌우가 바뀌거나 목소리 파일이 없으면 여기서 갈린다.
if ! grep -aF 'audio-probe: speaker-test exit 0 [ 0 - Front Left| 1 - Front Right]' "$LOG" >/dev/null; then
  report_failure "speaker-test did not play Front Left then Front Right"
fi
if [ "$(field "$TAP" left)" -lt 10000 ] || [ "$(field "$TAP" right)" -lt 10000 ]; then
  report_failure "speaker-test's voices did not reach one channel each (left $(field "$TAP" left), right $(field "$TAP" right))"
fi
if [ "$(field "$TAP" first_left)" -ge "$(field "$TAP" first_right)" ]; then
  report_failure "the right channel spoke before the left one"
fi
echo "speaker-test spoke on the left channel, then on the right"

# ── 검사 7: 녹음 — 마이크에 넣은 상수가 값까지 같게 파일에 남았나 ──────
# 2초 × 48kHz = 96,000프레임 전부가 (3000, -5000)이어야 한다. 기본 장치(dsnoop)를 지난다.
if ! grep -aF 'audio-probe: arecord exit 0 []' "$LOG" >/dev/null; then
  report_failure "arecord through the default device failed"
fi
debugfs -R "dump audio/cap.wav $WORK/cap.wav" "$DISK" >/dev/null 2>&1
[ -s "$WORK/cap.wav" ] || report_failure "the guest left no cap.wav on the config disk"
CAP="$(perl -e '
  open(my $f, "<:raw", $ARGV[0]) or die; local $/; my $d = <$f>;
  my ($n, $m) = (0, 0);
  for (my $p = 44; $p + 4 <= length $d; $p += 4) { $n++; $m++ if substr($d, $p, 4) eq pack("s<s<", 3000, -5000) }
  print "frames=$n match=$m\n";' "$WORK/cap.wav")"
echo "cap: ${CAP}"
if [ "$(field "$CAP" frames)" -ne 96000 ] || [ "$(field "$CAP" match)" -ne 96000 ]; then
  report_failure "the microphone did not deliver the fed constant (${CAP}, want 96000 of each); zeros mean Capture was off"
fi
echo "arecord got the microphone's constant on both channels, 96000 frames of 96000"

echo "AU check PASS"
```

### 4-2. `check.sh` — 문단 하나와 `CHAINS` 한 줄

E1 — `old_string`(기준 파일 338줄부터):

```bash
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

`new_string`:

```bash
# AU 체인은 소리를 본다. q35에 HDA 컨트롤러와 스피커 · 마이크 코덱(hda-micro)을 붙여
# 뜨고, 설정 디스크의 services.d/probe가 aplay · speaker-test · arecord를 사람이 치는
# 그대로 친다. QEMU의 오디오 백엔드가 컨테이너의 alsa-lib이고 그 file 플러그인이
# 스피커로 나온 샘플을 파일에 받고 파일의 샘플을 마이크로 넣으므로, 판정이 값까지
# 같은지로 닫힌다. 게스트에 한 글자도 안 친다. 회차당 부팅 1회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

E2 — `old_string`(기준 파일 359줄부터):

```bash
  "PD-M4:./pointer/check.sh"
```

`new_string`:

```bash
  "PD-M4:./pointer/check.sh"
  "AU-M0:./audio/check.sh"
```

### 4-3. 확인

```bash
for f in check.sh audio/check.sh audio/probe.sh; do cmp $f /tmp/run/au0/new/$f && echo "SAME $f"; done
bash -n audio/check.sh && bash -n audio/probe.sh && bash -n check.sh && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./audio/check.sh && require_no_early_exit_pipe ./audio/check.sh &&
  require_explicit_nic ./audio/check.sh && echo ENTRY-OK'
python3 /tmp/run/au0/anchors.py post "$PWD"
```

기대: `SAME` 셋 · `SYNTAX-OK` · `ENTRY-OK` · `post: 8 edits, 0 bad`.

## Task 5: 체인 한 번과 regression

체인은 하나씩 돈다. 캐시 삭제를 같은 `docker run` 안에 둔다(확정 10).

### 5-1. `audio` 체인

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/au0:/tmp/run/au0 -w /workspace tars-devcontainer bash -c '
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash audio/check.sh > /tmp/run/au0/impl/audio.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
rg -a -n '^(the |aplay|speaker-test|arecord|tap:|cap:|=== boot|AU check|FAIL)' /tmp/run/au0/impl/audio.log
```

기대: `exit=0`. 캐시를 지웠으므로 `real`이 2~5분이다(Task 1이 커널을 이미 빌드했다). `rg`는 이렇다(사본의 판).

```
the kernel carries ALSA and HDA, and the initrd carries arecord, libasound, its config, two voices and the audio group
=== boot: q35 with an HDA controller and a speaker + microphone codec ===
the kernel configured the codec as card 0 with a playback and a capture node
aplay -l and arecord -l both see card 0 device 0
the boot leaves Master and Capture muted, and amixer turns them on
tap: frames=199068 tone=48000 left=53060 right=71059 other=0 zero=26949 first_left=54995 first_right=126772
aplay's square wave reached the speaker sample for sample
speaker-test spoke on the left channel, then on the right
cap: frames=96000 match=96000
arecord got the microphone's constant on both channels, 96000 frames of 96000
AU check PASS
```

`tap:`의 `frames` · `zero` · `first_*`는 판마다 조금씩 다르다(스트림 앞뒤의 무음 길이). `tone=48000` · `left=53060` · `right=71059` ·
`other=0`과 `cap:` 줄은 세 판 다 같았다. 줄 번호는 보고에 그대로 붙인다. 빨개지면 `report_failure`가 찍는 표식 · `audio-probe` 줄 ·
마지막 40줄을 그대로 보고한다.

### 5-2. regression — `install` · `tools` · `boot` · `machine`

확정 8의 넷이다. 한 컨테이너에서 차례로 돈다. 약 4분이다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/au0:/tmp/run/au0 -w /workspace tars-devcontainer bash -c '
    for c in install tools boot machine; do s=$(date +%s); bash $c/check.sh > /tmp/run/au0/impl/reg_$c.log 2>&1
      echo "$c exit=$? $(( $(date +%s) - s ))s"; done' ; } 2>&1 | tail -6
rmdir /tmp/run/docker.lock
rg -a 'init waited|tools the list names' /tmp/run/au0/impl/reg_install.log /tmp/run/au0/impl/reg_tools.log
```

기대: 넷 다 `exit=0`. `init waited`가 1,500ms 이상(사본 1,800 · 1,900ms)이고 `all 91 tools`다. `init waited`가 500ms 아래면 멈추고
보고한다 — lessons의 이월 숙제가 말하는 그 신호이고, 이 milestone이 고칠지 lead가 정한다.

## Task 6: mutation

확정 7의 표다. 사본은 `/tmp/run/au0/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 6-0. 사본을 만든다

```bash
python3 /tmp/run/au0/make_mut.py "$PWD" /tmp/run/au0/impl/mut
M=/tmp/run/au0/impl/mut
for p in config_m1:kernel/.config config_m2:kernel/.config probe_m3.sh:audio/probe.sh initrd_m4.sh:kernel/make_initrd.sh \
  initrd_m5.sh:kernel/make_initrd.sh check_nostatic.sh:audio/check.sh check_nogroup.sh:audio/check.sh \
  check_nonow.sh:audio/check.sh check_nonow_no56.sh:audio/check.sh; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 9`, 그리고 바뀐 줄 수가 `config_m1 2` · `config_m2 2` · `probe_m3.sh 2` · `initrd_m4.sh 1` · `initrd_m5.sh 1` ·
`check_nostatic.sh 33` · `check_nogroup.sh 2` · `check_nonow.sh 2` · `check_nonow_no56.sh 34`. 다르면 돌리지 말고 보고한다.

`make_mut.py`:

```python
"""AU-M0 plan Task 6의 mutation 사본을 만든다.

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


# mutation 1 · 2 — 커널 심볼 하나씩
make('kernel/.config', 'config_m1', 'CONFIG_SND_HDA_INTEL=y\n', '# CONFIG_SND_HDA_INTEL is not set\n')
make('kernel/.config', 'config_m2', 'CONFIG_SYSVIPC=y\n', '# CONFIG_SYSVIPC is not set\n')
# mutation 3 — 프로브가 소리를 안 켠다
make('audio/probe.sh', 'probe_m3.sh',
     'amixer -q -c 0 sset Master 0dB unmute\namixer -q -c 0 sset Capture 0dB cap\n', '')
# mutation 4 — /etc/group에서 audio를 뺀다
make('kernel/make_initrd.sh', 'initrd_m4.sh', 'audio:x:29:\n', '')
# mutation 5 — /usr/share/alsa를 안 넣는다
make('kernel/make_initrd.sh', 'initrd_m5.sh', 'cp -r "$SYSROOT/usr/share/alsa" "$WORKDIR/usr/share/"\n', '')

# 앞 검사를 건너뛰는 체인 사본(겨냥한 검사까지 가게 한다 — lessons "mutation이 겨냥한 검사에 걸릴 것이라고 믿기")
cut('audio/check.sh', 'check_nostatic.sh', 'CONFIG=../kernel/.config\n', 'echo "the kernel carries ALSA and HDA')
make('audio/check.sh', 'check_nogroup.sh', '  *$\'\\n\'"audio:x:"*) ;;\n', '  *) ;;\n')
make('audio/check.sh', 'check_nonow.sh', "if ! grep -aE 'audio-probe: master now",
     "if false && ! grep -aE 'audio-probe: master now")
s = open(os.path.join(out, 'check_nonow.sh')).read()
a, b = s.index('# ── 검사 5:'), s.index('# ── 검사 7:')
open(os.path.join(out, 'check_nonow_no56.sh'), 'w').write(s[:a] + s[b:])
os.chmod(os.path.join(out, 'check_nonow_no56.sh'), 0o755)
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. 첫 줄 `mounted:`의 다섯 자리는 차례로 "HDA 꺼짐 ·
SYSVIPC 꺼짐 · 프로브의 unmute 줄 · audio 그룹 줄 · alsa 트리 복사 줄"의 수다. 덮지 않은 판은 `00111`이다.

```bash
#!/bin/bash
# AU-M0 plan Task 6의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 audio 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  echo \"mounted: \$(grep -c 'CONFIG_SND_HDA_INTEL is not set' kernel/.config)\$(grep -c 'CONFIG_SYSVIPC is not set' kernel/.config)\$(grep -c 'sset Master 0dB unmute' audio/probe.sh)\$(grep -c '^audio:x:29:' kernel/make_initrd.sh)\$(grep -c 'usr/share/alsa\" \"\$WORKDIR' kernel/make_initrd.sh)\"
  bash audio/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^AU check PASS' "$mut/$name.log" | head -2
```

### 6-1. 커널을 안 건드리는 일곱 판

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/au0/impl/mut; X=/tmp/run/au0/run_mut.sh
$X $R $I $M m3 probe_m3.sh:audio/probe.sh
$X $R $I $M m3_play probe_m3.sh:audio/probe.sh check_nonow.sh:audio/check.sh
$X $R $I $M m3_rec probe_m3.sh:audio/probe.sh check_nonow_no56.sh:audio/check.sh
$X $R $I $M m4 initrd_m4.sh:kernel/make_initrd.sh
$X $R $I $M m4_boot initrd_m4.sh:kernel/make_initrd.sh check_nogroup.sh:audio/check.sh
$X $R $I $M m5 initrd_m5.sh:kernel/make_initrd.sh
$X $R $I $M m5_boot initrd_m5.sh:kernel/make_initrd.sh check_nostatic.sh:audio/check.sh
```

기대는 확정 7의 표에서 그 판의 `FAIL` 줄이다. `mounted:`는 `m3*`가 `00011`, `m4*`가 `00101`, `m5*`가 `00110`이다. 2분 안팎이다.

### 6-2. 커널을 바꾸는 세 판

덮은 `.config`로 커널이 다시 빌드되므로 `kernel/build`를 먼저 떠 두고 끝나면 되돌린다. APFS의 `cp -c`라 즉시 끝난다. 4분 안팎이다.

```bash
rm -rf /tmp/run/au0/impl/build.keep && cp -Rc kernel/build /tmp/run/au0/impl/build.keep
R="$PWD"; I=tars-devcontainer; M=/tmp/run/au0/impl/mut; X=/tmp/run/au0/run_mut.sh
$X $R $I $M m1 config_m1:kernel/.config
$X $R $I $M m1_boot config_m1:kernel/.config check_nostatic.sh:audio/check.sh
$X $R $I $M m2_boot config_m2:kernel/.config check_nostatic.sh:audio/check.sh
rm -rf kernel/build && cp -Rc /tmp/run/au0/impl/build.keep kernel/build
cat kernel/build/.tars-build-stamp; (cd kernel && cat .config build.sh | shasum -a 256)
```

기대: `m1*`의 `mounted:`가 `10111`, `m2_boot`가 `01111`이고 `FAIL` 줄이 표와 같다. 마지막 두 줄의 해시가 같다(되돌린 빌드가 지금
`.config`의 것이다).

로그에 `Killed`가 보이고 `FAIL: … build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시
돈다. mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 덮기를 의심한다(`mounted:`).

### 6-3. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. initrd만 지금 소스로 다시 만들고 체인을 한 번 더 돈다(데운 판, 30초 안팎).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash audio/check.sh > /tmp/a.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/a.log'; rc=$?
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `AU check PASS`. `git status`는 `M` 다섯(`check.sh` · `devcontainer/Dockerfile` · `kernel/.config` · `kernel/guest_tools.sh` ·
`kernel/make_initrd.sh`)과 `?? audio/`이고, plan과 design이 commit 전이면 그 둘이 더 있다. 다른 것이 보이면(특히 `-v`로 없는
파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 6-4. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `5 files changed, 232 insertions(+), 2 deletions(-)`였고(새 파일 둘은
  `git diff`에 안 나온다 — `git add -N audio/` 뒤에는 7 files, 614 insertions), 지운 줄은 `kernel/.config`의 둘뿐이다.
- Task 0의 출력.
- Task 1~4의 확인 출력(`FOLDED` · `SAME` · `SYNTAX-OK` · `ENTRY-OK` · `anchors.py`).
- Task 5의 `exit=` · `real` · `rg` 출력과 regression 넷의 줄 · `init waited`.
- Task 6의 `diff` 수 아홉 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 6-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 7: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 일곱 파일을 `/tmp/run/au0/new/`와 `cmp`한다. Task 5의 로그를 대조한다. 이미지가 새로 구워졌는지
   (`docker images tars-devcontainer`의 시각) 본다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스무 체인 × 2다. 판정은 `PASS: 2/2` × 20과 `AU check PASS` 둘이다. 첫 체인이 커널 전체
   빌드를 치른다(`clean()`). `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_au0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_au0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_au0.log`가 20,
   `rg -c 'AU check PASS' /tmp/gate_au0.log`가 2여야 한다. `skipping make`는 `20 × 2 − 1 = 39`다(lessons GL-M1).
3. 실측 절 채우기와 design `Status:`(M0 끝, M1 plan 차례).
4. commit. 넣는 것은 `kernel/.config` · `devcontainer/Dockerfile` · `kernel/guest_tools.sh` · `kernel/make_initrd.sh` · `check.sh` ·
   `audio/check.sh` · `audio/probe.sh` · 이 plan이고, design이 commit 전이면 함께 넣는다. `git add`는 경로를 하나씩 지정한다(`audio/`를
   통째로 넣지 않는다 — 지금은 둘뿐이지만 규칙이다).
5. M1 plan은 M0 commit 뒤에 새로 쓴다(design 결정 4의 셋, 체인의 검사 4를 뒤집는 것).

## design과 다르게 적은 것

없다. design은 이 plan과 같은 날 함께 썼고, 이 plan이 사본에서 잰 것을 반영했다. lead의 전제와 다른 다섯은 design의 "lead의 전제를
바로잡은 것"에 있다.

## 이 milestone에서 안 하는 것

- 부팅이 믹서를 켜고 기억하는 것(M1). 그래서 `alsactl`도 안 싣는다.
- 실기의 코덱 · USB 오디오(M2), DSP와 firmware(M3).
- `running-tars.md`의 소리 절. lead가 서브프로젝트를 닫을 때 쓴다(design "닫을 때"). M0 뒤 실기에서 미리 보고 싶으면 design의 그 절에
  명령이 있다.
- 포트. 이 체인은 monitor를 안 쓴다. 45491은 다음 새 체인의 몫이다.

## AU-M0이 실측한 것

구현은 Sonnet 서브에이전트가 2026-10-06에 main 작업 트리에서 했고, lead가 일곱 파일을 `/tmp/run/au0/new/`와 `cmp`해 전부
같은 것을 봤다. plan의 기대와 글자나 수가 다른 것은 없었다. 로그는 `/tmp/run/au0/impl/`(`audio.log` · `reg_*.log` · `mut/`),
루트 게이트는 `/tmp/gate_au0.log`.

1. 커널. `build 1` · `build 2` 둘 다 exit 0, `FOLDED`, bzImage 7,955,456바이트, `inflate_fast`가 `ffffffff8147ab40` — 확정 1 · 6의
   값 그대로다. 두 빌드를 합한 `real`이 2분 6초. `.config`의 diff는 +147 −2이고 지운 줄은 `SYSVIPC` · `SOUND`의 `is not set` 둘이다.
2. 이미지. 굽기가 1분 51초가 아니라 2.7초였다 — 모든 층이 `CACHED`였고, 구운 뒤의 `tars-devcontainer`가 planner의
   `tars-devcontainer-au0`와 같은 이미지 ID(`c13e9834eb62`)였다. Dockerfile이 사본과 바이트까지 같아서 Docker가 같은 층을 돌려준
   것이다. sysroot의 `aplay` · `libasound.so.2` · `alsa.conf`를 lead가 다시 확인했다.
3. `audio` 체인. 캐시를 지운 판이 1분 40초(plan의 기대 2~5분 안), `tap: tone=48000 left=53060 right=71059 other=0` ·
   `cap: frames=96000 match=96000`으로 사본과 같다. `frames` · `zero` · `first_*`만 판마다 다르다(확정 4가 적은 대로).
4. regression. `install` 102초(`init waited 1800ms`) · `tools` 65초(`all 91 tools`) · `boot` 23초 · `machine` 19초, 넷 다 exit 0.
5. mutation. 열 판이 전부 겨냥한 검사에서 빨갰고 `FAIL` 줄이 확정 7의 표와 글자까지 같다. 시간은 m3 계열 18초 · m4 8 · 12초 ·
   m5 7 · 11초 · m1 23 · 67초 · m2_boot 127초. 되돌린 뒤 `kernel/build`의 스탬프와 `.config` · `build.sh`의 해시가 같았고
   체인이 다시 `AU check PASS`였다.
6. 루트 게이트. 스무 체인 × 2회, 50분 34초, `PASS: 2/2` 스물 · `AU check PASS` 둘 · `skipping make` 39. `audio` 체인의 두 회차가
   `tap: frames=199424 … tone=48000 left=53060 right=71059 other=0`와 `frames=198417 … tone=48000 left=53060 right=71059 other=0`,
   `cap: frames=96000 match=96000` 둘이었다. CB-M0의 19체인 51분 15초에서 1분 안쪽이 줄었다 — 확정 9가 본 대로 새 체인의
   비용은 1분 안쪽이고, 커널이 0.7초 빨라진 것(확정 6)이 부팅 마흔 번 남짓에 걸쳐 그것을 되돌려 준 것으로 본다.
