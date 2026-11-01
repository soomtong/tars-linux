---
name: project_audio_devices
description: 노트북의 스피커 · 마이크 · 헤드폰 잭 · USB 헤드셋 · DSP 뒤 내장 마이크에 aplay · arecord가 닿는다 — 커널 ALSA · HDA 코덱 · SOF · ACP와 alsa-utils 그대로이고 우리 코드는 부팅의 믹서(alsactl 일꾼 · /config/asound.state)와 기본 카드(/etc/asound.conf)와 게이트다. 기본 장치의 두 겹(SYSVIPC · audio 그룹), 커널이 소리를 꺼 둔 채 뜬다, QEMU alsa 백엔드 + file 플러그인, dmix xrun의 두 배 프레임, printk가 화면 줄을 자른다(AU-M0~M3, 2026-10-06 종료)
metadata:
  type: project
---

Audio Devices(AU)는 2026-10-05에 열어 2026-10-06에 AU-M0~M3으로 닫혔다. 사용자의
요청("오디오(마이크/이어폰/스피커) 기기 활성화")에서 시작했고, 같은 요청의 2번
(마이크로 음성 전사, Voxio 포팅)은 뒤에 Voice Dictation(VD)으로 따로 연다. design은
`docs/specs/2026-10-05-tars-audio-devices-design.md`(결정 8 · 전제 정정 12 · 위험 16 ·
비목표 10 · 실측 19), plan은 `-au-m0.md` ~ `-au-m3.md`이고 각 끝의 "실측한 것" 절이 값이다.

## 무엇을 직접 짜고 무엇을 그대로 썼나

[[project_write_or_reuse]]의 기준이 또렷이 갈린 서브프로젝트다. 커널의 ALSA ·
HDA 컨트롤러 · 코덱 드라이버 여덟 · SOF · ACP, Debian의 alsa-utils(`aplay` ·
`arecord` · `amixer` · `alsamixer` · `speaker-test` · `alsactl`)와 alsa-lib의 설정
트리, sof-bin의 firmware · topology 42개는 그대로다. 우리가 짠 것은 `init`의
`audio.zig` 하나 — 부팅에 `alsactl`을 부르는 일꾼(M1), 끄는 길의 `alsactl store`(M1),
`/dev/snd` · `/proc/asound/pcm`을 1초마다 보고 `/etc/asound.conf`에 기본 카드를 적는
`follow`(M2 · M3) — 와 initrd의 alsactl postinit 규칙 한 줄(M3), 그리고 게이트다.

## 사람이 치는 `aplay x.wav`가 되려면 두 겹이 더 필요하다

장치를 안 고른 `aplay`는 libasound의 `default` → `dmix`(재생) · `dsnoop`(녹음)으로
간다. 둘은 여러 프로그램이 한 장치를 나누려고 SysV 세마포어와 공유 메모리를 쓴다.
커널에 `SYSVIPC`가 없으면 `unable to create IPC semaphore`, initrd의 `/etc/group`에
`audio`가 없으면 `ipc_gid must be a valid group`이다. 둘 다 `-D hw:0`으로는 돌아서
"가끔만 안 되는" 고장으로 보인다(design 결정 3, 실측 6).

## 커널은 소리를 꺼 둔 채 뜬다

HDA 드라이버는 가상 Master · Capture를 0에 음소거로 올린다(design 실측 7). Debian은
udev 규칙과 systemd 유닛으로 `alsactl restore`를 돌리는데 우리는 둘 다 없다. 그래서
`init`이 일꾼을 fork하고 기다리지 않는다 — 일꾼이 `controlC0`를 5초까지 기다렸다가
`alsactl -U restore`(파일이 있으면) 또는 `alsactl -U init`(없으면)이 된다. 99는 성공
(범용 규칙), 끄는 길의 `reapAll` 뒤 `sync` 앞에서 `alsactl store`, 이 부팅에 믹서를
세웠고 `/config`가 있을 때만 적는다(design 결정 4). USB 카드는 꺼진 채 오지 않는다 —
장치가 기억하는 볼륨으로 온다(전제 7).

## 기본 카드와 녹음의 세 단

libasound의 `default`는 카드 0이라 USB 헤드셋(카드 1)이 안 쓰인다. `init`의 감독
루프가 1초마다 `/dev/snd`를 읽고 바뀌었을 때만 `/etc/asound.conf`를 쓴다 — 재생은
장치 0을 가진 카드 중 가장 큰 번호, 녹음은 USB 마이크 · 내장 DMIC(SOF는 장치 6,
`/proc/asound/pcm`의 이름으로) · 장치 0 순이다. 번호는 `getenv`의 기본값 자리에 두어
`ALSA_CARD`가 위를 덮는다(결정 7 · 8). `tars.conf` 키는 없다 — 사람이 `amixer`로
맞춘 값이 곧 설정이다.

## 게이트가 샘플을 값까지 보는 수법

QEMU `-audiodev alsa` + 컨테이너 libasound의 `file` 플러그인 둘(스피커 `tap.raw` · 마이크
`infile`)이다 — 수법과 함정(`wav` 백엔드 · 44100 리샘플 · 게스트 시계)은 measurements 81.
게스트 안 루프백은 HDA의 마이크 길을 안 지나서 안 쓴다(결정 5). 게스트 쪽은 설정 디스크의
`services.d/probe`라 체인이 게스트에 한 글자도 안 친다. 부팅 D만 monitor로 `usb-audio`를
꽂고 뽑는다(포트는 lessons의 포트 절).

## 게이트가 빨개진 두 자리 — 둘 다 우리 코드가 아니었다

둘 다 `docs/guides/lessons.md`에 절로 있다 — "호스트 부하 아래 dmix가 xrun 구간을 두 번
더한다(AU-M1)"와 "커널 printk가 terminal의 화면 줄을 가운데서 자른다(AU-M2)".

## VD와의 경계

AU는 "`arecord`가 마이크의 바이트를 WAV로 쓰고 `aplay`가 WAV를 스피커로 낸다"까지다.
그 WAV로 무엇을 하는지(전사 API · 키 · 화면에 넣는 것)는 VD다(비목표 4).
`arecord -f S16_LE -r 16000 -c 1`이 기본 장치(`plug` → `dsnoop`)로 도는지는 안 쟀다.

관련: [[project_write_or_reuse]] · [[project_kernel_config]] · [[project_pointer_devices]] ·
[[project_seeding_a_config_disk]] · [[feedback_boot_never_blocks]] · [[feedback_scripting_runtimes]]
