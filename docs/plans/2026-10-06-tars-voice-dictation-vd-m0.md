# VD-M0 — 게스트의 `tars-dictate`가 마이크를 전사 API에 보내고, initrd가 인증 기관 목록을 싣는다

Date: 2026-10-06
Design: `docs/specs/2026-10-06-tars-voice-dictation-design.md`
Status: 구현 전. plan을 쓰며 사본에서 돈 값은 "착수 전에 확정한 것"에 있고, 맨 아래 "VD-M0이 실측한 것" 절은 구현 뒤에 lead가 채운다.

## 누가 무엇을 하나

design 결정 12. Task 0~5는 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 6(루트 게이트 2회 · 실측 절 ·
design 덧붙임 · commit)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의
명령 출력을 그대로 보고한다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 이 milestone에서 정할 것(자리 나누기 · 언어 · 설정의 자리 · 시그널과 종료 코드 · WAV 머리 · 인증 기관 목록 ·
게이트의 모양)은 design과 이 plan이 사본에서 정했고(확정 1 ~ 5), Zig 코드가 한 줄도 없다. 구현자에게 남는 판단이 없다 — 새 파일 넷은
사본을 복사하고, 편집 다섯은 글자 그대로 넣고, 이미지 굽기 · 체인 · regression · mutation을 정해진 순서로 돌린다. plan의 기대와 다른
값이 나오면 고치지 말고 보고한다. Opus로 올릴 이유는 하나다 — 루트 게이트에서 이 plan이 못 돌린 체인이 빨개져 원인을 찾아야 할 때.
그때는 lead가 정한다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/vd0/repo/`)에 먼저 넣어 이미지 굽기 · 체인 · regression · mutation까지 돌렸고, 아래의 새 파일
본문과 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/vd0/render.py`). 기준은 HEAD `52188ab`의 파일
(`/tmp/run/vd0/base/`)이고 편집 뒤의 파일은 `/tmp/run/vd0/new/`다. 구현자는 코드를 새로 짓지 않는다. 새 파일은 `new/`에서 `cp -p`하고,
편집은 Edit 도구에 글자 그대로 넣고(또는 plan 본문에서 블록을 기계로 뽑아 넣고 — EL · CB · AU의 구현자가 그렇게 했다), 각 Task 끝에서
`new/`와 `cmp`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 `new/`가 서로 다르다고 보이면
고치지 말고 그 자리를 보고한다. 편집은 한 파일 안에서 E1부터 차례로 넣는다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `devcontainer/Dockerfile` | 편집 둘 — 층 15 주석 · 다운로드 목록의 `ca-certificates` 한 줄 | +17 |
| `kernel/make_initrd.sh` | 편집 하나 — `tq-probe` 뒤에 `tars-dictate`를 `/usr/bin`에 넣고 인증 기관 목록을 짓는 두 블록 | +25 |
| `kernel/dictation/tars-dictate` | 새 파일 — 받아쓰기 프로그램(bash, 대부분 주석) | +303 |
| `dictation/check.sh` | 새 파일 — 스물한번째 체인 | +375 |
| `dictation/probe.sh` | 새 파일 — 게스트 쪽 프로브(설정 디스크의 `services.d/probe`) | +122 |
| `dictation/stub.pl` | 새 파일 — 전사 API 흉내(perl, guestfwd가 연결마다 띄운다) | +115 |
| `check.sh` | 편집 둘 — 체인 설명 문단 · `CHAINS`의 `"VD-M0:./dictation/check.sh"` | +8 |

합해서 7 files, +965 −0이다. `init/` · `terminal/`의 Zig 코드는 한 줄도 안 바뀐다. 커널(`kernel/.config`)도 안 바뀐다. `kernel/guest_tools.sh`도
안 고친다 — `tars-dictate`가 부르는 `arecord` · `curl` · `jq`는 이미 있고, 그 목록은 sysroot의 바이너리를 적는 자리라 우리 스크립트는
`make_initrd.sh`가 직접 넣는다(`tq-probe` · `tars-wifi`와 같다). `tools/check.sh`도 그대로다(`all 92 tools`). `.gitignore`도 그대로다 — 체인이
만드는 디스크 `out/dictation.img`는 `out/` 아래이고 루트 `check.sh`의 `clean()`이 지운다.

design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다. 구현자의 측정용 파일은
`/tmp/run/vd0/impl/` 아래에 둔다. `/tmp/run/vd0/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6).
컨테이너는 언제나 하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run` · `docker build`를 아래로
감싼다. 명령이 실패해도 lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

이 milestone은 이미지(`tars-devcontainer`)를 다시 굽는다(Task 1). 구운 뒤의 이미지가 루트 게이트의 이미지다. 다른 에이전트가
그 이미지로 돌고 있으면 굽기를 미룬다. plan을 쓰며 구운 이미지 `tars-devcontainer-vd0`은 대조용이다 — 구현자는 그것을 안 쓴다.

## 이 milestone이 끝나면

- 게스트에서 사람이 `tars-dictate`를 치고 말한 뒤 Ctrl+C를 누르면, 녹음이 Groq Whisper API로 가고 받아 적은 글자가 표준 출력에 나온다.
  원문은 `/config/dictation.jsonl`에 한 줄로 남는다(표준 출력보다 먼저). 오디오는 `/tmp`에 잠깐 있다가 어떤 길로 끝나든 지워진다.
- 사람이 할 일은 키 하나다 — `/config/groq.key`(또는 `GROQ_API_KEY`). 키가 없으면 마이크를 열기 전에 끝난다. 그 밖의 설정은
  `/config/dictation.conf`의 키 넷(`transcribe_url` · `transcribe_model` · `language` · `max_seconds`)이고 없으면 Voxio의 기본값이다.
  `tars-dictate -h`가 그것을 보여 준다. `tars.conf`는 안 바뀐다.
- 게스트의 `curl`이 https에서 인증 기관 목록(`/etc/ssl/certs/ca-certificates.crt`, 150장)을 쓴다. 이 milestone 전에는 https가 전부
  `curl: (77)`로 죽었다(design 실측 1). 사람이 치는 `curl https://…`도 이제 된다.
- 스물한번째 체인 `dictation/check.sh`가 생긴다. QEMU HDA 마이크에 상수를 넣고(AU의 수법), 전사 API는 컨테이너의 perl stub이다
  (guestfwd가 연결마다 띄운다). Groq를 한 번도 안 부른다. 게스트에 한 글자도 안 치고 monitor를 안 쓴다. 포트는 45492 하나 —
  TLS 상대 `openssl s_server`가 컨테이너에서 듣는다.
- 오른쪽 Cmd 두 번(트리거) · 상태 줄 · 커서 자리에 넣기는 아직 없다(VD-M1). 정리 단계(LLM)도 없다(VD-M2) — 기록의 `cleaned`가 늘 null이다.

로그 줄(정본 — `tars-dictate`가 표준 에러에 찍는다. `dictation/probe.sh`가 그것을 `err [ … | … ]`로 모아 찍고 `dictation/check.sh`가 이 글자를
본다). 받아 적은 글자는 표준 에러에 안 찍힌다.

```
tars-dictate: recording; Ctrl+C stops (at most 300s)
tars-dictate: recording stopped by SIGINT after 1896ms
tars-dictate: recording stopped at the 1s limit
tars-dictate: transcribed 1896ms of audio into 18 characters in 210ms
tars-dictate: cancelled                                                   SIGTERM(언제든) · 녹음 뒤의 SIGINT
tars-dictate: no API key; write it to /config/groq.key (or set GROQ_API_KEY)
tars-dictate: transcription failed: HTTP 429, too many requests; try again shortly
tars-dictate: the transcript is blank; nothing to insert
tars-dictate: transcription failed: the response has no text (jq: error (at /tmp/tars-dictate.492.body:0): no text field )
tars-dictate: unknown key 'colour' in /config/dictation.conf
tars-dictate: max_seconds '0' is not 1..600, keeping 1
```

그 밖의 갈래(`tars-dictate`가 정본).

```
tars-dictate: config line without '=' ignored: <줄>
tars-dictate: the API key has characters an API key does not have; check /config/groq.key     exit 3
tars-dictate: recording failed (arecord exit <N>): <arecord의 에러>                              exit 1
tars-dictate: nothing was recorded                                                               exit 2
tars-dictate: transcription failed (curl exit <N>): <curl의 에러>                                exit 4
tars-dictate: transcription failed: HTTP <N> <본문 앞 200바이트>                                 exit 4
tars-dictate: could not append to /config/dictation.jsonl
tars-dictate: no /config; the transcript is not kept
```

프로브의 줄(사본의 마지막 판에서 뽑았다). 콘솔 줄에는 앞에 다른 바이트가 붙을 수 있어서(lessons 68) 체인의 판정은 줄 머리 앵커를
안 쓰고, 끝을 봐야 하는 값은 대괄호로 감싼다. `out`은 `jq -Rs .`가 만든 JSON 문자열이다 — 탭 · 개행이 `\t` · `\n`으로 보인다.

```
dictate-probe: start
dictate-probe: tars-dictate is [/usr/bin/tars-dictate]
dictate-probe: jq [jq-1.7]
dictate-probe: route [default via 10.0.2.2 dev eth0 proto dhcp src 10.0.2.15 metric 1002 ]
dictate-probe: capture [  Front Right: Capture 74 [100%] [0.00dB] [on]]
dictate-probe: tls default exit 60 [curl: (60) SSL certificate problem: self-signed certificate|More details here: …]
dictate-probe: tls pinned [s_server]
dictate-probe: s1 exit 0 ms 1824 out ["안녕하세요 vd0-dictated"] err [tars-dictate: recording; Ctrl+C stops (at most 300s)|…]
dictate-probe: s1 leftover wav []
  … s2 ~ s10도 같은 모양 …
dictate-probe: history lines [5]
dictate-probe: done
dictate-probe: powering off at uptime 24.78
```

stub의 줄(`$WORK/stub.log`, 요청 하나에 한 줄).

```
stub: POST /ok/s1 auth=[Bearer vd0-test-key] parts=[file,model,response_format] model=[whisper-large-v3-turbo] language=[-] response_format=[json] file=[name=tars-dictate.218.wav type=audio/wav bytes=60742] wav=[rate=16000 ch=1 bits=16 data=60698 header_data=60698] samples=[n=30349 mode=1234 mode_count=30349]
```

## 착수 전에 확정한 것

2026-10-06에 이 plan을 쓰며 Voxio(`/Users/dp/Repository/Voxio`, 1.0.1)의 `docs/ARCHITECTURE.md` · `docs/VERIFICATION.md` ·
`Sources/VoxioCore/`와 저장소의 코드를 읽어 정했고, 저장소 사본(`/tmp/run/vd0/repo/`)과 따로 구운 이미지(`tars-devcontainer-vd0`)로 쟀다.
측정 파일은 `/tmp/run/vd0/meas/`(체인 · 시리얼 · regression 로그, `work/`에 마지막 판의 stub 로그와 디스크 재료)와
`/tmp/run/vd0/mut_final/`(mutation)에 있다. 저장소의 작업 트리는 design과 이 plan 말고는 한 글자도 안 바뀌었다.

1. 자리와 언어(design 결정 1 · 2). 받아쓰기의 게스트 쪽은 bash 스크립트 하나다. Voxio의 `DictationPipeline` · `GroqClient` ·
   `TranscriptText` · `CleanupGuard`가 하는 일 중 M0의 몫(사전 점검 · 녹음 · 전사 · 무음 판정 · 제어 문자 · 기록)을 순서대로 옮겼다.
   우리 몫의 순수한 계산은 `jq` 필터 셋(`strip` · `blank` · `printable`)이고, 무음 판정이 한글을 글자로 봐야 해서 `jq`의 `\p{L}` · `\p{N}`을
   쓴다(Zig 표준 라이브러리에 유니코드 범주 표가 없다).

2. Dockerfile과 이미지(design 결정 8). 다운로드 목록에 `ca-certificates`(Architecture: all이라 `:amd64`가 없다)를 `libasound2-data` 바로
   뒤에 넣는다. 사본의 이미지 굽기가 29.6초였다(다운로드 층이 통째로 다시 돈다). 구운 뒤 sysroot에 `usr/share/ca-certificates/mozilla/`의
   `.crt` 150장이 있고 묶음(`etc/ssl/certs/ca-certificates.crt`)은 없다 — postinst가 짓는 것이라 `dpkg -x`에는 없다.

3. initrd. `make_initrd.sh`의 `tq-probe` 블록 뒤에 둘이다. `tars-dictate`를 `/usr/bin/tars-dictate`(0755)로, mozilla 인증서를 전부 이어 붙여
   `/etc/ssl/certs/ca-certificates.crt`(0644, 224,449바이트, `BEGIN CERTIFICATE` 150개)로. 끝에 개행이 없는 파일 뒤에 개행을 넣는 것은
   `update-ca-certificates`와 같다(`set -e` 아래라 `[ … ] && echo` 대신 `if`로 쓴다). 컨테이너 자신의 묶음은 152장이다 — OrbStack이 넣은
   개발용 인증 기관 둘이 섞여 있어서 복사하지 않는다(design 실측 2). initrd가 96,866,774 → 97,001,653바이트(+134,879, firmware 꼬리 포함. 주석을 고치기 전의 판은 +137,764였다 — cpio의 시각과 gzip 때문에 판마다 몇 KB 다르다)로 커지고, 새 라이브러리는 0개다.

4. `tars-dictate`의 계약(design 결정 3 ~ 7).

   | 무엇 | 값 |
   |---|---|
   | 키 | `GROQ_API_KEY`, 없으면 `/config/groq.key`(앞뒤 공백을 뗀다). 비면 exit 3. 글자는 `[A-Za-z0-9._~+/=-]`만. `curl -K -`의 표준 입력으로 보낸다(명령줄에 안 보인다) |
   | 설정 | `/config/dictation.conf`(없어도 된다). `transcribe_url` · `transcribe_model` · `language`(빈 값이면 칸을 안 보낸다) · `max_seconds`(1 ~ 600, 기본 300). 모르는 키 · 틀린 값은 경고하고 기본값 |
   | 녹음 | `arecord -q -t wav -f S16_LE -r 16000 -c 1 -d <max_seconds> /tmp/tars-dictate.<pid>.wav`, 장치를 안 고른다(AU의 기본 장치). 앞에서 돈다(백그라운드가 아니다) |
   | 시그널 | 프로세스 그룹으로. SIGINT는 녹음 중이면 멈추고 전사로, 그 뒤면 취소(130). SIGTERM은 언제든 취소(143) |
   | 머리 | 녹음이 끝나면 WAV 머리 44바이트를 실제 길이로 다시 짓는다(`printf` + `tail -c +45`, 게스트에 `dd`가 없다) |
   | 전사 | `curl -sS -K - --max-time 30 -F file=@…;type=audio/wav --form-string model=… --form-string response_format=json [--form-string language=…]` |
   | 응답 | 2xx가 아니면 exit 4(429는 문구가 따로). `.text`가 문자열이 아니면 exit 4. 앞뒤 공백을 뗀 원문에 글자 · 숫자가 없으면 exit 2 |
   | 기록 | `/config`가 붙었으면 `/config/dictation.jsonl`에 `{"at","raw","cleaned":null,"inserted","audio_ms","latency_ms"}` 한 줄, 표준 출력보다 먼저 |
   | 출력 | `inserted` = 원문에서 C0(탭 · 개행 빼고) · DEL · C1을 지우고 다시 앞뒤를 뗀 것. 끝에 개행 없음. 표준 출력이 tty면 개행 하나 |
   | 종료 코드 | 0 글자 있음 · 1 녹음 못 함 · 2 넣을 것 없음 · 3 키 없음 · 4 전사 실패 · 64 인자 · 130/143 취소 |

   재 본 것 넷. (a) `arecord`는 SIGINT에 머리를 거의 늘 못 고친다 — 스물네 판 중 스물하나(design 실측 4). 머리를 다시 쓰는 줄을 뺀
   mutation 2가 그래서 거의 늘 빨갛다. (b) 게스트의 `jq`는 1.7이고 `trim`이 없다 — 처음 판이 `trim/0 is not defined`로 모든 전사를 실패시켰다.
   `strip`을 `sub`로 정의한다. (c) bash는 앞에서 돌던 자식이 SIGINT를 스스로 처리하고 끝나면 그 뒤에 INT trap을 돌린다 — 그래서 "녹음 중"과
   "그 뒤"가 한 trap의 `phase` 변수로 갈린다(design 실측 7). (d) 표준 출력은 `$(…)`로 받지 않고 `jq -j`가 바로 쓴다 — 명령 치환은 끝의 개행을
   먹는다.

5. 체인의 모양(design 결정 9). 부팅 하나다. QEMU 호출은 audio 체인의 HDA(`-machine q35` · `ich9-intel-hda` · `hda-micro` ·
   `-audiodev alsa,…,in.dev=tarsfeed,…` · `HOME="$WORK"`)에 net 체인의 SLIRP(`-netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:perl
   $PWD/stub.pl $STUBLOG"` · `-device virtio-net-pci`)를 더한 것이다. `-netdev`가 있어 `-nic none`이 없다(진입 검사
   `require_explicit_nic`가 `-netdev`를 받는다). 설정 디스크(라벨 `tars-dictate`)는 `mkfs.ext2 -d`로 `tars.conf`(`net=dhcp`) · `groq.key`
   (`vd0-test-key`) · `services.d/probe` · `vd0-tls.pem`을 한 번에 담는다. 마이크의 상수는 두 채널 다 1234, 120초다. TLS 상대는 체인이
   `openssl req`로 지은 자기 서명 인증서(SAN `IP:10.0.2.2`)로 `openssl s_server -www`를 `127.0.0.1:45492`에 띄운 것이다.

   프로브의 갈래 열이다. 끝내는 법은 `int`(1.5초 뒤 그룹에 SIGINT) · `term`(1초 뒤 그룹에 SIGTERM) · `cap`(`max_seconds`가 끝낸다)이다.

   | 갈래 | `dictation.conf` | 끝 | 보는 것 |
   |---|---|---|---|
   | s1 | `/ok/s1` | int | 기본값 · 마이크의 상수가 API까지 |
   | s2 | `/ok/s2` · `language=ko` · `transcribe_model=vd0-model` · `max_seconds=1` | cap | 설정 셋이 요청에 실린다 · 정확히 1초 |
   | s3 | `/ok/s3` · 30초 | term | 취소 — API를 안 부른다 |
   | s4 | `/ok/s4` · 30초, 키 파일을 치운다 | cap | 키가 없으면 녹음 전에 끝난다 |
   | s5 | `/ok/s5` · 1초, 키 파일 없이 `GROQ_API_KEY=vd0-env-key` | cap | 환경 변수의 키 |
   | s6 | `/fail/s6` · 1초 | cap | 429 |
   | s7 | `/blank/s7` · 30초 | int | 무음 전사 `" ."` |
   | s8 | `/ctrl/s8` · 1초 | cap | 제어 문자를 지운다 |
   | s9 | `/notext/s9` · 30초 | int | 응답에 `text`가 없다 |
   | s10 | `/ok/s10` · 1초, `colour=blue` · `max_seconds=0`을 더 적는다 | cap | 모르는 키 · 틀린 값 |

   s1 · s7 · s9가 SIGINT로 끝나는 이유는 머리 검사(검사 12)다 — `arecord`가 머리를 고치는 판이 열에 하나쯤이라, 머리를 다시 쓰는 줄이
   빠지면 셋 중 하나에는 거의 반드시 드러난다.

   검사 열셋이다. 판정 글자는 위 "로그 줄"과 체인 파일의 `report_failure` 문구가 정본이다.

   | 검사 | 본다 | 사본의 값 |
   |---|---|---|
   | 1(부팅 없음) | initrd에 `usr/bin/tars-dictate` · `etc/ssl/certs/ca-certificates.crt`, 그 묶음의 인증서 수 = sysroot의 mozilla `.crt` 수(100 이상), `bash -n` | 150 |
   | 2 | `tls default exit 60 [curl: (60) SSL certificate problem: self-signed certificate` · `tls pinned [s_server]` | 초록 |
   | 3 | s1 — exit 0, 표준 출력 `"안녕하세요 vd0-dictated"`, `stopped by SIGINT`, stub의 인증 · 칸 셋 · 기본 모델 · `language=[-]` · `audio/wav` · 16000/1/16, 머리 = 길이(0.5초 이상), 샘플 전부 1234 | `data=60698 header_data=60698`, `mode=1234x30349` |
   | 4 | s2 — 칸 넷 · `vd0-model` · `ko` · `data=32000 header_data=32000` · 샘플 16000개 전부 1234, `stopped at the 1s limit` | 초록 |
   | 5 | s3 — exit 143, 표준 출력 빔, `cancelled`, stub에 s3 없음, 열 갈래 전부 `leftover wav []` | 초록 |
   | 6 | s4 — exit 3, `no API key`, 2초 안, stub에 s4 없음 · s5 — exit 0, `auth=[Bearer vd0-env-key]` | s4 21ms |
   | 7 · 8 · 9 · 10 | s6 exit 4 `HTTP 429` · s7 exit 2 `blank` · s8 exit 0 표준 출력 `"vd0-ctrl a[201~bc\td\nef"` · s9 exit 4 `no text` | 초록 |
   | 11 | s10 — exit 0, `unknown key 'colour'` · `max_seconds '0' is not 1..600, keeping 1`, 요청이 32,000바이트 | 초록 |
   | 12 | stub의 요청이 여덟이고 모든 요청의 `header_data` = `data` | 8 |
   | 13 | 끈 뒤 디스크의 `dictation.jsonl`이 다섯 줄 — s1 · s2 · s5 · s8 · s10 순서, `raw` · `inserted` · `audio_ms`, `at`의 모양, `cleaned` null. s8의 `raw`에 ESC · CR · NEL · 끝의 ESC가 남고 `inserted`에는 없다 | 초록 |

   검사 13의 기대값은 체인 파일에 글자로 있다. 제어 문자는 perl이 `\x{1b}`처럼 바꿔 찍는다. s1의 `audio_ms`는 판마다 다를 수 있어 stub이
   본 길이에서 셈한다.

6. 시간. 사본에서 `init` · `terminal`의 캐시를 지운 첫 판이 1분 59초(커널은 스탬프로 건너뛴다), 데운 판이 33 ~ 35초(판 여섯)였다. 부팅에서 프로브의
   `kill -TERM 1`까지 21 ~ 25초다. 루트 게이트는 이 체인을 두 번 돌리므로(마지막 체인이라 늘 데운 판이다) 지금(AU-M3)의 값에 1분 남짓을
   더한 것으로 본다.

7. mutation. 일곱 가지를 아홉 판(대조군 하나 포함)으로 돌렸다(`/tmp/run/vd0/make_mut.py` · `run_mut.sh`, 로그는 `/tmp/run/vd0/mut_final/`).
   주석을 고치기 전의 판(`/tmp/run/vd0/mut/`)에서도 아홉 판이 같은 자리에서 빨갰다 — 아래 표는 고친 뒤의 판이다.
   앞 검사가 먼저 잡는 것은 그 검사를 건너뛴 체인 사본을 함께 덮어 겨냥한 검사까지 보냈다(lessons "mutation이 겨냥한 검사에 걸릴 것이라고
   믿기").

   | mutation | 판 | 덮는 사본 | 잡은 자리 | `FAIL` 줄 | 시간 |
   |---|---|---|---|---|---|
   | (대조군) | `m0` | 없음 | — | `VD check PASS` | 34초 |
   | 1 initrd에 인증 기관 목록이 없다(HEAD의 모양) | `m1` | `initrd_m1.sh` | 검사 1 | `FAIL: etc/ssl/certs/ca-certificates.crt is missing from the initrd` | 7초 |
   | | `m1_boot` | + `check_no1ca.sh` | 검사 2(프로브는 `tls default exit 77 [curl: (77) error setting certificate file: /etc/ssl/certs/ca-certificates.crt]`) | `FAIL: curl did not load the CA bundle (want exit 60 against a self-signed peer, not 77)` | 33초 |
   | 2 WAV 머리를 다시 안 쓴다 | `m2` | `dictate_m2` | 검사 3(stub이 받은 s1의 머리가 300초 분량) | `FAIL: s1: the WAV's header says 9600000 bytes of samples, the file has 60698 (want equal and at least 0.5s)` | 34초 |
   | 3 제어 문자를 안 지운다 | `m3` | `dictate_m3` | 검사 9 | `FAIL: s8: stdout was not "vd0-ctrl a[201~bc\td\nef" (…)` | 36초 |
   | 4 사전 점검이 없다 | `m4` | `dictate_m4` | 검사 6(s4가 30초를 녹음하고 빈 키로 API를 불렀다) | `FAIL: s4: tars-dictate did not exit 3 (…)` | 58초 |
   | 5 기록을 안 남긴다 | `m5` | `dictate_m5` | 검사 13 | `FAIL: the config disk holds no dictation.jsonl` | 33초 |
   | 6 무음 판정이 없다 | `m6` | `dictate_m6` | 검사 8(s7이 `"."`을 냈다) | `FAIL: s7: tars-dictate did not exit 2 (…)` | 33초 |
   | 7 SIGTERM이 취소가 아니라 "녹음 끝"이다 | `m7` | `dictate_m7` | 검사 5(s3이 전사까지 갔다) | `FAIL: s3: tars-dictate did not exit 143 (…)` | 35초 |

   읽을 것 셋.
   - `m1_boot`이 design 전제 1의 증거다. 목록이 없는 initrd(HEAD의 모양)에서 게스트의 `curl`이 `curl: (77) error setting certificate file:
     /etc/ssl/certs/ca-certificates.crt`였다 — Groq에 한 번도 못 닿았을 것이다.
   - `m4`(사전 점검을 뺐다)는 s4가 30초를 녹음하고 빈 키(`auth=[Bearer ]`)로 API를 불렀다. 걸린 시간이 게스트 시계로 23초인 것은 TCG의
     오디오가 게스트 시계보다 빨리 샘플을 내기 때문이다(design 위험 9) — 판정이 바이트로 닫혀 체인은 안 흔들린다.
   - `m7`(SIGTERM을 "녹음 끝"으로 바꿨다)은 취소가 사라진 모양이다. s3이 전사까지 가서 exit 0이었다 — 취소의 판정은 종료 코드와 stub의 요청
     둘이 한다.

8. regression. initrd와 이미지가 바뀌므로 다섯을 사본에서 돌렸다. 다섯 다 exit 0이다.

   | 체인 | 시간(사본, 두 판) | 왜 돌렸나 |
   |---|---|---|
   | `tools` | 66 · 61초 | initrd의 `/usr/bin`에 스크립트 하나가 는다. `the initrd carries the four bones and all 92 tools the list names` 그대로 |
   | `net` | 170 · 171초 | guestfwd를 쓰는 선례이고 같은 이미지의 `curl`을 쓴다 |
   | `audio` | 44 · 43초 | 같은 HDA · file 플러그인 수법. `AU check PASS` |
   | `boot` | 25 · 24초 | limine이 BIOS로 initrd를 읽는다. initrd가 135KB 안팎 커졌다 |
   | `install` | 109 · 108초 | initrd가 바뀌면 부팅 7의 창이 움직인다(lessons PD-3). `init waited 1700ms` — HEAD(AU-M3)와 같다 |

   둘째 판은 주석만 고친 뒤의 판이다(코드는 같다).

   그 밖의 체인은 `tars-dictate`를 부르지 않고 https를 쓰지 않는다. 루트 게이트가 전부를 본다.

9. 낡은 산출물. 이 milestone은 Zig 코드를 안 고친다. 커널도 안 고친다 — `build.sh`의 sha256 스탬프가 HEAD의 것 그대로라 체인마다
   `skipping make`다. initrd는 체인마다 `make_initrd.sh`가 새로 짓는다. 그래도 아래 명령은 첫 판에 캐시 삭제를 같은 `docker run` 안에 둔다
   (`project_zig_out_staleness`).

10. 앵커. 편집 다섯의 `old_string`이 HEAD 파일에 정확히 한 번씩 있고(`python3 /tmp/run/vd0/anchors.py pre "$PWD"` → `pre: 5 edits, 0 bad`),
    `new_string`이 사본에 정확히 한 번씩 있다(`post: 5 edits, 0 bad`). 진입 검사 셋도 사본의 `dictation/check.sh`에서 `ENTRY-OK`였다. main
    작업 트리의 세 파일이 `/tmp/run/vd0/base/`와 바이트까지 같다.

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

   기대: 맨 위 commit이 `52188ab Close audio devices: …`이거나 그 위에 lead의 commit(design · 이 plan)이 있다. `git status`는 lead가 고치는 중일
   수 있는 `HANDOFF.md` · design · 이 plan · `MEMORY.md` · `docs/decisions/`가 있을 수 있다. 그 밖의 소스 파일이 `M`이면 멈추고 보고한다.
   `kernel/dictation/` · `dictation/`이 이미 있으면 멈추고 보고한다.

3. 편집의 앵커와 기준 파일을 본다(확정 10).

   ```bash
   python3 /tmp/run/vd0/anchors.py pre "$PWD"
   for f in devcontainer/Dockerfile kernel/make_initrd.sh check.sh; do cmp $f /tmp/run/vd0/base/$f && echo "BASE $f"; done
   ```

   기대: `pre: 5 edits, 0 bad`와 `BASE` 셋. 하나라도 다르면 그 파일을 보고하고 멈춘다 — 앵커를 다시 뽑아야 한다.

## Task 1: `devcontainer/Dockerfile` — `ca-certificates`와 이미지

design 결정 8 · 확정 2. 편집 둘을 넣고 이미지를 다시 굽는다. 굽기가 30초 ~ 2분이다.

### 1-1. 편집

E1 — `old_string`(기준 파일 316줄부터):

```dockerfile
# 안 받는다(커널에 모듈이 없다).
```

`new_string`:

```dockerfile
# 안 받는다(커널에 모듈이 없다).
#
# ── VD-M0: 층 15(TLS가 믿는 인증 기관) ─────────────────────────────────
#
# ca-certificates 하나다. 게스트의 curl은 NW-M2부터 TLS 라이브러리(libssl)를 링크해
# 왔지만 무엇을 믿을지(인증 기관 목록)가 initrd에 없었다 — libcurl이 컴파일 타임에
# 박아 둔 /etc/ssl/certs/ca-certificates.crt가 비어 있어서 https는 전부
# `curl: (77) error setting certificate file`로 죽었다(VD design 실측 1). Voice Dictation이
# Groq API(https)에 닿으려면 이것이 있어야 한다.
#
# Architecture: all이라 :amd64를 안 붙인다. 패키지에는 인증서가 한 장씩
# (/usr/share/ca-certificates/mozilla/*.crt) 들어 있고, 한 파일로 묶는 것은 postinst의
# update-ca-certificates다 — dpkg -x로 푼 여기에는 그 묶음이 없다(lessons 42와 같은 성질).
# 그래서 kernel/make_initrd.sh가 같은 일(전부 이어 붙이기)을 한다. 실행 파일이 아니라
# 데이터라 새 라이브러리는 0개다. 컨테이너 자신의 /etc/ssl/certs를 복사하지 않는 이유는
# tzdata와 같고(TS design 결정 10) 하나가 더 있다 — 그 묶음에는 OrbStack이 넣은 개발용
# 인증 기관 둘이 섞여 있다(VD design 실측 2).
```

E2 — `old_string`(기준 파일 451줄부터):

```dockerfile
        libasound2-data \
```

`new_string`:

```dockerfile
        libasound2-data \
        ca-certificates \
```

### 1-2. 이미지를 굽고 sysroot를 본다

```bash
mkdir -p /tmp/run/vd0/impl
cmp devcontainer/Dockerfile /tmp/run/vd0/new/devcontainer/Dockerfile && echo SAME-Dockerfile
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker build -t tars-devcontainer devcontainer/ > /tmp/run/vd0/impl/image.log 2>&1 ; echo "build exit=$?" ; } 2>&1 | tail -4
docker run --rm tars-devcontainer bash -c 'ls $AMD64_SYSROOT/usr/share/ca-certificates/mozilla/*.crt | wc -l; ls $AMD64_SYSROOT/etc/ssl/certs/ca-certificates.crt 2>&1 | tail -1'
rmdir /tmp/run/docker.lock
```

기대: `SAME-Dockerfile`, `build exit=0`, 숫자 `150`, 그리고 `ls`의 `No such file or directory`(sysroot에 묶음은 없다 — `make_initrd.sh`가 짓는다).
숫자가 150이 아니면 Debian의 판이 바뀐 것이니 그 수를 보고한다(체인 검사 1은 수를 sysroot에서 읽으므로 그대로 돈다). `--platform`을
붙이지 않는다(`project_build_host_arch`).

## Task 2: `kernel/dictation/tars-dictate`(새 파일) · `kernel/make_initrd.sh`

design 결정 2 ~ 8 · 확정 3 · 4.

### 2-1. 새 파일

사본에서 실행 비트째 복사한다.

```bash
mkdir -p kernel/dictation
cp -p /tmp/run/vd0/new/kernel/dictation/tars-dictate kernel/dictation/
ls -l kernel/dictation/
```

기대: `-rwxr-xr-x … tars-dictate`. 본문은 아래와 같다(읽기용 — 넣는 것은 위의 `cp -p`다).

`kernel/dictation/tars-dictate`:

```bash
#!/usr/bin/bash
# tars-dictate — 마이크로 녹음해 Groq Whisper API로 받아 적고, 그 글자를 표준 출력으로
# 낸다(VD design 결정 2). Voxio(macOS 받아쓰기 앱)의 파이프라인을 게스트로 옮긴 것이다.
#
#   1. 사전 점검   API 키가 없으면 마이크를 열기 전에 끝난다(exit 3). 30초를 말한 뒤에
#                  "키가 없다"를 알게 하지 않는다(Voxio 3절)
#   2. 녹음       arecord가 기본 장치(plug → dsnoop)에서 16kHz 모노 16비트 WAV를 /tmp에
#                  쓴다. Whisper가 받는 모양이라 업로드가 작다(Voxio D10a)
#   3. 전사       curl이 multipart로 올리고 jq가 응답의 text를 꺼낸다
#   4. 기록       전사가 성공하면 원문을 /config/dictation.jsonl에 한 줄로 남긴다 —
#                  표준 출력보다 먼저다. 그 뒤에 무엇이 실패해도 말한 것은 남는다(Voxio D9)
#   5. 출력       제어 문자를 지운 글자를 표준 출력에 낸다. 개행은 안 붙인다 —
#                  터미널이 이것을 그대로 붙여 넣는데(VD-M1), 끝의 개행은 Enter다
#
# 우리 코드는 순서와 갈래(이 파일)와 jq 필터 둘(빈 전사 · 제어 문자)이다. 오디오는
# arecord, HTTP와 TLS는 curl, JSON은 jq의 것이다(project_write_or_reuse).
#
# 시그널은 프로세스 그룹으로 받는다. 셸에서 친 사람의 Ctrl+C가 그 모양이고(tty가 앞의
# 작업 그룹 전체에 보낸다), 터미널도 같은 모양으로 보낸다(VD-M1, kill(-pgid)).
#   SIGINT   녹음 중이면 녹음을 끝내고 전사로 간다. 그 뒤면 취소다(exit 130)
#   SIGTERM  언제든 취소다. 오디오를 지우고 API를 안 부르거나 그 호출을 버린다(exit 143)
# arecord는 같은 그룹이라 그 시그널을 직접 받아 끝난다. 이 스크립트는 arecord에 시그널을
# 다시 보내지 않는다 — 그룹으로 이미 받은 arecord에 둘째가 간다. arecord는 SIGINT에 WAV
# 머리를 거의 늘 못 고치고 끝나므로(VD design 실측 4) 머리는 아래에서 다시 쓴다.
#
# 종료 코드가 터미널과의 계약이다.
#   0    표준 출력에 넣을 글자가 있다
#   1    녹음을 못 했다(마이크 · 장치)
#   2    넣을 것이 없다(녹음이 0바이트 · 무음 전사)
#   3    API 키가 없다
#   4    전사가 실패했다(네트워크 · HTTP 상태 · 응답에 text가 없다)
#   64   인자가 틀렸다
#   130  SIGINT로 취소됐다(녹음이 끝난 뒤)
#   143  SIGTERM으로 취소됐다
#
# 받아 적은 글자는 표준 에러에 안 찍는다. 길이와 시간만 찍는다(Voxio 69aebc9 — 로그에
# 말한 내용이 평문으로 남지 않게).

set -u

KEY_FILE=/config/groq.key
CONF_FILE=/config/dictation.conf
HISTORY_FILE=/config/dictation.jsonl

# 기본값. /config/dictation.conf가 덮는다. 빈 language는 "자동 감지"다 — Voxio가 처음
# ko로 고정했다가 영어로 한 말이 한국어로 번역돼 꽂힌 뒤(2026-09-18) 비웠다.
transcribe_url=https://api.groq.com/openai/v1/audio/transcriptions
transcribe_model=whisper-large-v3-turbo
language=
max_seconds=300

say() { printf 'tars-dictate: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
usage: tars-dictate

Records from the default microphone until Ctrl+C (SIGINT to the process group),
transcribes it with the Groq Whisper API and prints the text on stdout.
SIGTERM cancels. The text is also kept in /config/dictation.jsonl.

  /config/groq.key         the API key (or GROQ_API_KEY in the environment)
  /config/dictation.conf   optional, key=value lines:
      transcribe_url    https://api.groq.com/openai/v1/audio/transcriptions
      transcribe_model  whisper-large-v3-turbo
      language          empty = detect (or ko, en, ...)
      max_seconds       300 (1..600), recording stops by itself after this

exit: 0 text printed, 1 no recording, 2 nothing to insert, 3 no API key,
      4 transcription failed, 130/143 cancelled
EOF
}

case $# in
  0) ;;
  *)
    case $1 in
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 64 ;;
    esac
    ;;
esac

# 앞뒤 공백을 뗀다. tars.conf의 파서(init/src/config.zig)와 같은 규칙이다.
trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# ── 설정 ───────────────────────────────────────────────────────────────
# tars.conf와 같은 문법이다 — `#` 주석, 첫 `=`에서 키와 값을 나누고 양쪽 공백을 뗀다,
# 모르는 키는 한 줄 경고하고 넘어간다. 매번 읽으므로 고친 값은 다음 실행부터 맞는다
# (재부팅이 필요 없다 — tars.conf와 다른 점이고, 이 파일이 따로 있는 이유다).
if [ -r "$CONF_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "$line")
    case $line in
      ''|'#'*) continue ;;
      *=*) ;;
      *) say "config line without '=' ignored: $line"; continue ;;
    esac
    key=$(trim "${line%%=*}")
    value=$(trim "${line#*=}")
    case $key in
      transcribe_url) transcribe_url=$value ;;
      transcribe_model) transcribe_model=$value ;;
      language) language=$value ;;
      max_seconds)
        # 상한 600초는 업로드 한도 안쪽이다 — 16kHz 모노 16비트는 초당 32KB이고 Groq
        # 무료 티어의 한도가 25MB(약 13분)다(Voxio 7절).
        if [[ $value =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 600 ]; then
          max_seconds=$value
        else
          say "max_seconds '$value' is not 1..600, keeping $max_seconds"
        fi
        ;;
      *) say "unknown key '$key' in $CONF_FILE" ;;
    esac
  done < "$CONF_FILE"
fi

# ── 1. 사전 점검: 키 ───────────────────────────────────────────────────
# 환경 변수가 먼저다(Voxio D14 — 개발할 때 파일을 안 고치고 바꿔 보는 길). 복사해 붙인
# 키에는 개행이 붙고 빈 파일도 있을 수 있다 — 둘 다 "키가 없다"로 끝나야 한다. 빈 키로
# 보낸 요청의 401은 "키가 틀렸다"로 읽히지만 실은 넣지 않은 것이다(Voxio GroqClient).
key=${GROQ_API_KEY:-}
if [ -z "$key" ] && [ -r "$KEY_FILE" ]; then
  key=$(trim "$(< "$KEY_FILE")")
fi
if [ -z "$key" ]; then
  say "no API key; write it to $KEY_FILE (or set GROQ_API_KEY)"
  exit 3
fi
# 키는 curl의 설정으로 표준 입력에 실어 보낸다 — 명령줄에 두면 /proc/<pid>/cmdline으로
# 보인다. 그 설정 문법에서 따옴표와 역슬래시는 뜻이 있으므로 키에 올 수 있는 글자로
# 좁힌다. Groq의 키는 gsk_로 시작하는 영숫자다.
if ! [[ $key =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
  say "the API key has characters an API key does not have; check $KEY_FILE"
  exit 3
fi

# ── 2. 녹음 ────────────────────────────────────────────────────────────
# 오디오는 /tmp(RAM)에 두고 어떤 길로 끝나든 지운다(Voxio D9 — 오디오는 안 남긴다).
# 지난 실행이 죽어서 남긴 파일은 그 pid가 없으면 지운다. 다른 패널에서 도는 실행의
# 파일은 건드리지 않는다.
for old in /tmp/tars-dictate.*.wav; do
  [ -e "$old" ] || continue
  pid=${old#/tmp/tars-dictate.}
  pid=${pid%.wav}
  [ -d "/proc/$pid" ] || rm -f "$old"
done
wav=/tmp/tars-dictate.$$.wav
body=/tmp/tars-dictate.$$.body
errs=/tmp/tars-dictate.$$.err
trap 'rm -f "$wav" "$body" "$errs"' EXIT

phase=recording
stopped=0
on_int() {
  if [ "$phase" = recording ]; then
    stopped=1
  else
    say "cancelled"
    exit 130
  fi
}
on_term() {
  say "cancelled"
  exit 143
}
trap on_int INT
trap on_term TERM

say "recording; Ctrl+C stops (at most ${max_seconds}s)"
# 앞에서 돈다(백그라운드가 아니다). 그래서 bash는 arecord가 끝날 때까지 trap을 미루고,
# arecord는 그룹으로 온 시그널을 자기가 받아 끝난다(머리는 아래에서 다시 쓴다).
arecord -q -t wav -f S16_LE -r 16000 -c 1 -d "$max_seconds" "$wav" 2> "$errs"
rec_rc=$?
phase=processing
t0=$EPOCHREALTIME

# 판정은 파일로 한다. WAV 머리는 44바이트(arecord의 PCM WAV)이고 그 뒤가 전부 샘플이다.
# 샘플이 있으면 arecord의 종료 코드와 무관하게 전사로 간다 — 시그널로 멈춘 arecord는
# 0이 아닌 값으로 끝날 수 있다. 샘플이 없을 때만 종료 코드가 "장치를 못 열었다"와
# "열자마자 멈췄다"를 가른다.
size=$(stat -c %s "$wav" 2>/dev/null || echo 0)
data=$(( size > 44 ? size - 44 : 0 ))
if [ "$data" -eq 0 ]; then
  if [ "$rec_rc" -ne 0 ] && [ "$stopped" = 0 ]; then
    say "recording failed (arecord exit ${rec_rc}): $(tr '\n' ' ' < "$errs")"
    exit 1
  fi
  say "nothing was recorded"
  exit 2
fi
audio_ms=$(( data * 1000 / 32000 ))

# 머리를 실제 길이로 다시 쓴다. arecord는 시작할 때 -d의 길이(300초면 9,600,000바이트)를
# 머리에 적고 끝날 때 고치는데, SIGINT를 받으면 대부분 `pcm_read: read error: Interrupted
# system call`을 찍고 고치지 못한 채 끝난다(VD design 실측 4 — 같은 Ctrl+C가 판마다
# 다르다). 그 파일도 샘플은 멀쩡하지만 머리가 틀린 WAV를 받아 주는지는 서버에 달렸다.
# 형식은 우리가 고른 것(16kHz 모노 16비트 PCM)이라 머리 44바이트를 통째로 다시 짓는다.
# 게스트에 dd가 없어서 새 파일로 쓰고 바꾼다.
le32() {
  printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)))"
}
{
  printf 'RIFF'; le32 $((36 + data)); printf 'WAVEfmt '; le32 16
  printf '\x01\x00\x01\x00'; le32 16000; le32 32000; printf '\x02\x00\x10\x00'
  printf 'data'; le32 "$data"
  tail -c +45 "$wav"
} > "$wav.new" && mv "$wav.new" "$wav"
if [ "$stopped" = 1 ]; then
  say "recording stopped by SIGINT after ${audio_ms}ms"
else
  say "recording stopped at the ${max_seconds}s limit"
fi

# ── 3. 전사 ────────────────────────────────────────────────────────────
# Voxio GroqClient.transcribe와 같은 요청이다 — file · model · response_format=json,
# language는 비어 있으면 안 보낸다(빈 언어 코드는 400이다). --form-string은 값의 @ · <를
# 파일로 읽지 않는다. 상한 30초는 Voxio의 transcription.timeoutSec이다.
lang_field=()
[ -n "$language" ] && lang_field=(--form-string "language=${language}")
code=$(printf 'header = "Authorization: Bearer %s"\n' "$key" | curl -sS -K - \
  --max-time 30 \
  -o "$body" -w '%{http_code}' \
  -F "file=@${wav};type=audio/wav" \
  --form-string "model=${transcribe_model}" \
  --form-string "response_format=json" \
  "${lang_field[@]}" \
  "$transcribe_url" 2> "$errs")
curl_rc=$?
if [ "$curl_rc" -ne 0 ]; then
  say "transcription failed (curl exit ${curl_rc}): $(tr '\n' ' ' < "$errs")"
  exit 4
fi
case $code in
  2??) ;;
  429)
    say "transcription failed: HTTP 429, too many requests; try again shortly"
    exit 4
    ;;
  *)
    say "transcription failed: HTTP ${code} $(head -c 200 "$body" | tr '\n' ' ')"
    exit 4
    ;;
esac

# jq 하나가 응답을 읽고 기록 한 줄을 짓는다.
#   strip      앞뒤 공백을 뗀다. 게스트의 jq 1.7에는 trim이 없다(VD design 실측 6) — Whisper는
#              " 안녕하세요"처럼 앞에 한 칸을 붙이고, 그대로 넣으면 커서 앞에 빈칸이 남는다
#   blank      글자도 숫자도 하나 없으면 무음이다. 길이로 보면 안 된다 — Whisper는 무음에
#              빈 문자열이 아니라 " ."을 준다(Voxio TranscriptText.isBlank). \p{L} · \p{N}은
#              jq의 정규식(Oniguruma)이 아는 유니코드 분류라 한글도 글자다
#   printable  탭과 개행만 남기고 C0 · DEL · C1을 지운다. 꽂히는 곳이 셸이라서다 — ESC가
#              살면 `ESC[201~`로 bracketed paste를 끝내고 뒤를 명령으로 흘릴 수 있고, CR은
#              bracketed paste가 꺼진 셸에서 곧 실행이다(Voxio 94e0e64). 말해서 이런 글자가
#              나오는 길은 없으므로 지워지는 것은 응답이 만든 것뿐이다
# inserted는 지운 뒤에 다시 앞뒤를 뗀다. 끝의 ESC가 지워지면 그 앞의 개행이 끝에 남을 수
# 있고, 끝의 개행은 Enter다. raw는 받은 그대로(앞뒤만 뗀) 남긴다 — 무엇이 지워졌는지를
# 나중에 볼 수 있게.
if ! rec=$(jq -c --argjson audio_ms "$audio_ms" --argjson t0 "$t0" '
    def strip: sub("^\\s+"; "") | sub("\\s+$"; "");
    def blank: test("[\\p{L}\\p{N}]") | not;
    def printable: [explode[] | select(. == 9 or . == 10 or (. >= 32 and . != 127 and (. < 128 or . >= 160)))] | implode;
    if (.text | type) != "string" then error("no text field") else . end
    | (.text | strip) as $raw
    | if ($raw | blank) then {blank: true}
      else {at: (now | todate), raw: $raw, cleaned: null, inserted: ($raw | printable | strip),
            audio_ms: $audio_ms, latency_ms: ((now - $t0) * 1000 | floor)}
      end' "$body" 2> "$errs"); then
  say "transcription failed: the response has no text ($(tr '\n' ' ' < "$errs"))"
  exit 4
fi
if [ "$rec" = '{"blank":true}' ]; then
  say "the transcript is blank; nothing to insert"
  exit 2
fi

# ── 4. 기록 ────────────────────────────────────────────────────────────
# /config가 붙어 있을 때만 쓴다. 안 붙었으면 /config는 RAM 위의 빈 디렉터리라 쓰면 끌 때
# 사라진다 — 그것을 기록이라고 부르지 않는다.
config_mounted=0
while read -r _ mnt _; do
  [ "$mnt" = /config ] && config_mounted=1
done < /proc/mounts
if [ "$config_mounted" = 1 ]; then
  printf '%s\n' "$rec" >> "$HISTORY_FILE" || say "could not append to $HISTORY_FILE"
else
  say "no /config; the transcript is not kept"
fi

# ── 5. 출력 ────────────────────────────────────────────────────────────
chars=$(jq -r '.inserted | length' <<< "$rec")
say "transcribed ${audio_ms}ms of audio into ${chars} characters in $(jq -r '.latency_ms' <<< "$rec")ms"
jq -j '.inserted' <<< "$rec"
# 사람이 셸에서 쳤으면 프롬프트가 글자 뒤에 붙지 않게 개행을 하나 준다. 표준 출력이
# 파이프면(터미널이 읽는다) 안 준다.
[ -t 1 ] && echo
exit 0
```

### 2-2. `make_initrd.sh` — 편집 하나

`tq-probe` 블록 뒤, `UT-M3 결정 8`(`.gitconfig`) 주석 앞에 두 블록이 들어간다.

E1 — `old_string`(기준 파일 372줄부터):

```bash
# UT-M3 결정 8. git은 전역 설정을 $HOME/.gitconfig에서 읽고 게스트의 HOME은
```

`new_string`:

```bash
# VD-M0. 받아쓰기(VD design 결정 2). 사람이 셸에서 이름으로 치고, VD-M1부터는 터미널이
# 오른쪽 Cmd 두 번에 이것을 띄운다. tq-probe와 같은 이유로 저장소에서 와서 /usr/bin에
# 간다. bash 스크립트라 copy_lib_deps가 따라갈 것이 없다 — 부르는 arecord · curl · jq는
# guest_tools.sh가 이미 싣는다.
cp dictation/tars-dictate "$WORKDIR/usr/bin/tars-dictate"
chmod 0755 "$WORKDIR/usr/bin/tars-dictate"

# VD-M0. curl이 https에서 믿을 인증 기관 목록. libcurl이 컴파일 타임에 박아 둔 경로가
# /etc/ssl/certs/ca-certificates.crt이고, 그 파일이 없으면 https는 전부
# `curl: (77)`로 죽는다(VD design 실측 1). Debian은 이 묶음을 postinst의
# update-ca-certificates로 짓는다 — dpkg -x로 푼 sysroot에는 인증서가 한 장씩만 있다.
# 같은 일을 여기서 한다. 기본 설정(/etc/ca-certificates.conf)이 mozilla 디렉터리를
# 전부 켜므로 전부 이어 붙이고, 끝에 개행이 없는 파일 뒤에 개행을 넣는 것까지 그
# 스크립트와 같다.
#
# 컨테이너 자신의 /etc/ssl/certs/ca-certificates.crt를 복사하지 않는 이유가 하나 더
# 있다. 그 파일에는 OrbStack이 넣은 개발용 인증 기관 둘(OrbStack Development Root CA ·
# Caddy Local Authority)이 들어 있다(VD design 실측 2) — 게스트가 그것을 믿을 이유가 없다.
mkdir -p "$WORKDIR/etc/ssl/certs"
for crt in "$SYSROOT"/usr/share/ca-certificates/mozilla/*.crt; do
  cat "$crt"
  if [ -n "$(tail -c 1 "$crt")" ]; then echo; fi
done > "$WORKDIR/etc/ssl/certs/ca-certificates.crt"
chmod 0644 "$WORKDIR/etc/ssl/certs/ca-certificates.crt"

# UT-M3 결정 8. git은 전역 설정을 $HOME/.gitconfig에서 읽고 게스트의 HOME은
```

### 2-3. 확인

```bash
cmp kernel/dictation/tars-dictate /tmp/run/vd0/new/kernel/dictation/tars-dictate && echo SAME-tars-dictate
cmp kernel/make_initrd.sh /tmp/run/vd0/new/kernel/make_initrd.sh && echo SAME-make_initrd
bash -n kernel/dictation/tars-dictate && bash -n kernel/make_initrd.sh && echo SYNTAX-OK
```

기대: `SAME` 둘과 `SYNTAX-OK`.

## Task 3: `dictation/`(새 파일 셋) · `check.sh`

design 결정 9 · 확정 5.

### 3-1. 새 파일 셋

```bash
mkdir -p dictation
cp -p /tmp/run/vd0/new/dictation/check.sh /tmp/run/vd0/new/dictation/probe.sh /tmp/run/vd0/new/dictation/stub.pl dictation/
ls -l dictation/
```

기대: 셋 다 `-rwxr-xr-x`. 루트 `check.sh`가 체인을 실행 파일로 부르므로(`run_chain`의 `"$script"`) `check.sh`의 실행 비트가 필요하다.

`dictation/check.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# VD 체인 — 게스트의 tars-dictate가 마이크의 바이트를 전사 API에 보내고 받은 글자를 낸다.
#
# 전사 API는 Groq가 아니라 컨테이너의 stub.pl이다(VD design 결정 5). QEMU의 guestfwd가
# 게스트의 10.0.2.100:8080 연결마다 그것을 띄운다 — 게이트는 바깥에 안 나가고 Groq의
# 무료 티어 한도를 한 번도 안 쓴다. 게스트의 /config/dictation.conf가 transcribe_url로 그
# 주소를 가리키고, 경로의 첫 마디가 stub의 답(정상 · 제어 문자 · 무음 · text 없음 · 429)을
# 고른다.
#
# 마이크는 audio 체인과 같은 수법이다(AU design 결정 5). QEMU의 HDA 마이크에 컨테이너
# alsa-lib의 file 플러그인(infile)이 상수를 넣는다. stub이 받은 WAV의 샘플이 그 상수면
# "녹음이 진짜 마이크를 지나 API까지 왔다"이다.
#
# 게스트에 한 글자도 안 친다. 설정 디스크의 services.d/probe(= probe.sh)가 사람이 셸에서
# 하는 일(설정 파일을 고치고 tars-dictate를 치고 Ctrl+C로 멈춘다)을 열 갈래로 하고
# `dictate-probe:` 줄로 찍는다. 끝나면 kill -TERM 1로 끄고, 이 스크립트가 디스크의
# dictation.jsonl을 debugfs로 꺼낸다. monitor를 안 쓴다.
#
# 하나 더 — TLS. 게스트의 curl이 인증 기관 목록(/etc/ssl/certs/ca-certificates.crt)을
# 읽는지를 컨테이너의 openssl s_server로 본다(검사 2). Groq는 https다.
#
# 이 체인이 못 보는 것 — 진짜 Groq의 답(사람이 키를 넣고 실기에서 본다, running-tars.md) ·
# 실기 마이크의 소리 · 터미널이 글자를 커서 자리에 넣는 것(VD-M1).

# $GUEST_MEM 하나 때문에 source한다. audio 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

# openssl s_server가 듣는 컨테이너의 포트. 게스트는 10.0.2.2:이 번호로 붙는다 — SLIRP이
# 그것을 컨테이너의 127.0.0.1로 잇는다(lessons 45). 45492는 VD의 첫 번호다(lessons 포트 절).
TLS_PORT=45492

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

DISK=../out/dictation.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
STUBLOG="$WORK/stub.log"
QEMU_PID=""
TLS_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ -n "$TLS_PID" ] && kill -0 "$TLS_PID" 2>/dev/null; then
    kill "$TLS_PID" 2>/dev/null || true
    wait "$TLS_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG" "$WORK"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: started service probe (pid" \
    "dictate-probe: start" \
    "dictate-probe: route [default via 10.0.2.2" \
    "dictate-probe: capture [" \
    "dictate-probe: tls default exit" \
    "dictate-probe: s1 exit" \
    "dictate-probe: s10 exit" \
    "dictate-probe: done" \
    "tars-init: calling reboot"; do
    if grep -aF "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- probe lines ---"
  grep -a "dictate-probe:" "$LOG" | tail -n 30
  echo "--- stub log ---"
  cat "$STUBLOG" 2>/dev/null
  echo "--- last 30 lines ---"
  tail -n 30 "$LOG"
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

# 게스트가 스스로 꺼지기를 기다린다(audio 체인과 같다).
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
}

# ── 검사 1: initrd가 tars-dictate와 인증 기관 목록을 싣는다 (부팅 없음) ──
# 목록의 수는 sysroot의 ca-certificates 패키지가 담은 인증서 수와 같아야 한다 —
# make_initrd.sh가 그것을 전부 이어 붙인다(update-ca-certificates가 하는 일).
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
for want in usr/bin/tars-dictate etc/ssl/certs/ca-certificates.crt; do
  case "$PADDED_LIST" in
    *$'\n'"${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} is missing from the initrd"
      exit 1
      ;;
  esac
done
BUNDLE_CERTS="$(gzip -dc ../kernel/initrd.cpio | cpio -i --to-stdout etc/ssl/certs/ca-certificates.crt 2>/dev/null | grep -c 'BEGIN CERTIFICATE')"
SYSROOT_CERTS="$(ls "${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"/usr/share/ca-certificates/mozilla/*.crt | wc -l)"
if [ "$SYSROOT_CERTS" -lt 100 ] || [ "$BUNDLE_CERTS" -ne "$SYSROOT_CERTS" ]; then
  echo "FAIL: the initrd's CA bundle holds ${BUNDLE_CERTS} certificate(s), the sysroot has ${SYSROOT_CERTS}"
  exit 1
fi
if ! bash -n ../kernel/dictation/tars-dictate; then
  echo "FAIL: kernel/dictation/tars-dictate does not parse"
  exit 1
fi
echo "the initrd carries tars-dictate and a CA bundle of ${BUNDLE_CERTS} certificates"

# ── 재료: 마이크의 상수 · TLS 상대 · 설정 디스크 · .asoundrc ────────────
# feed.raw — 두 채널이 같은 상수 1234, 120초. 녹음은 48kHz 스테레오에서 plug가 16kHz
# 모노로 바꾼다. 두 채널을 같게 둔 것은 그 변환이 채널을 어떻게 섞든 값이 1234로 남게
# 하려는 것이다(채널을 섞는 규칙은 alsa-lib의 것이고 이 체인이 볼 것이 아니다). 120초는
# 열 번의 녹음과 그 사이를 넉넉히 덮는다.
FEED_VALUE=1234
perl -e 'print pack("s<s<", $ARGV[0], $ARGV[0]) x (48000 * 120)' "$FEED_VALUE" > "$WORK/feed.raw"

# 자기 서명 인증서. 10.0.2.2라는 IP를 이름으로 갖는다 — 게스트가 그 주소로 붙는다.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=vd0-tls \
  -addext subjectAltName=IP:10.0.2.2 \
  -keyout "$WORK/tls.key" -out "$WORK/tls.pem" >/dev/null 2>&1 \
  || { echo "FAIL: openssl could not make the test certificate"; exit 1; }
openssl s_server -quiet -accept "127.0.0.1:${TLS_PORT}" -cert "$WORK/tls.pem" -key "$WORK/tls.key" -www \
  > "$WORK/tls.log" 2>&1 < /dev/null &
TLS_PID=$!
sleep 0.5
kill -0 "$TLS_PID" 2>/dev/null || { echo "FAIL: openssl s_server died at startup"; cat "$WORK/tls.log"; exit 1; }

mkdir -p ../out "$WORK/seed/services.d"
cp probe.sh "$WORK/seed/services.d/probe"
chmod 0755 "$WORK/seed/services.d/probe"
cp "$WORK/tls.pem" "$WORK/seed/vd0-tls.pem"
printf 'net=dhcp\n' > "$WORK/seed/tars.conf"
printf 'vd0-test-key\n' > "$WORK/seed/groq.key"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-dictate -d "$WORK/seed" "$DISK"

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

# q35 · HDA는 audio 체인과 같고, 네트워크는 net 체인과 같은 SLIRP이다. guestfwd의 cmd는
# 연결마다 새로 실행된다 — 경로에 쉼표가 없어야 한다(QEMU 옵션은 쉼표로 갈린다).
echo "=== boot: q35 with an HDA microphone, SLIRP with a transcription stub at 10.0.2.100:8080 ==="
: > "$LOG"
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:perl $PWD/stub.pl $STUBLOG" \
  -device virtio-net-pci,netdev=n0 \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

wait_for_log 'dictate-probe: done' 240 \
  || report_failure "the probe did not finish"
wait_for_exit 30 \
  || report_failure "the guest never switched itself off after the probe's kill -TERM 1"
grep -aF 'dictate-probe: tars-dictate is [/usr/bin/tars-dictate]' "$LOG" >/dev/null \
  || report_failure "tars-dictate is not on the guest's PATH"
grep -aF 'dictate-probe: route [default via 10.0.2.2' "$LOG" >/dev/null \
  || report_failure "the guest got no default route; the stub and the TLS peer are out of reach"
grep -aE 'dictate-probe: capture \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null \
  || report_failure "the boot did not turn Capture on; the microphone would record zeros"

# 프로브 한 갈래의 줄(`dictate-probe: s1 exit 0 ms 1777 out ["…"] err […]`)과 그 판정.
#   $1 갈래  $2 종료 코드  $3 표준 출력(jq가 만든 JSON 문자열)  $4 표준 에러에 있어야 할 글자
# 비교는 글자 그대로다 — case 패턴의 따옴표 안은 [ ] *가 특별하지 않다.
probe_line() { grep -aoE "dictate-probe: $1 exit [0-9]+ ms [0-9]+ out .*" "$LOG" | head -n 1; }
expect_run() {
  local line
  line="$(probe_line "$1")"
  [ -n "$line" ] || report_failure "$1: the probe printed no result for it"
  case "$line" in *" $1 exit $2 ms "*) ;; *) report_failure "$1: tars-dictate did not exit $2 (${line})" ;; esac
  case "$line" in *" out [$3] err ["*) ;; *) report_failure "$1: stdout was not $3 (${line})" ;; esac
  case "$line" in *"$4"*) ;; *) report_failure "$1: stderr does not say '$4' (${line})" ;; esac
}
# stub이 받은 요청. 경로의 둘째 마디가 갈래 이름이다. 뒤의 공백까지 넣어 s1과 s10을 가른다.
stub_line() { grep -aE "^stub: POST /[a-z]+/$1 " "$STUBLOG" | head -n 1; }
stub_count() { grep -acE "^stub: POST /[a-z]+/$1 " "$STUBLOG"; }
# stub 줄에서 key=값 하나(대괄호 안의 낱말 하나)를 꺼낸다.
stub_field() { printf '%s\n' "$1" | grep -oE "(^| |\[)$2=[^] ]*" | head -n 1 | sed "s/^.*$2=//"; }
OK_OUT='"안녕하세요 vd0-dictated"'

# ── 검사 2: TLS — curl이 인증 기관 목록을 읽고, TLS 라이브러리가 돈다 ──────
# 상대는 컨테이너의 openssl s_server(자기 서명)다. 목록을 읽었으면 그 상대를 못 믿어 60이고,
# 목록이 없으면 그 앞에서 77이다(VD design 실측 1) — 60이 "목록이 있다"의 증거다. 같은
# 인증서를 --cacert로 주면 핸드셰이크와 응답까지 간다(s_server -www의 상태 페이지).
grep -aF 'dictate-probe: tls default exit 60 [curl: (60) SSL certificate problem: self-signed certificate' "$LOG" >/dev/null \
  || report_failure "curl did not load the CA bundle (want exit 60 against a self-signed peer, not 77)"
grep -aF 'dictate-probe: tls pinned [s_server]' "$LOG" >/dev/null \
  || report_failure "curl could not finish a TLS handshake with a peer it was told to trust"
echo "curl loads the CA bundle (60 against a self-signed peer) and finishes a TLS handshake with a pinned one"

# ── 검사 3: 기본값 — 마이크의 바이트가 API에 가고 받은 글자가 나온다 ────
# 사람이 Ctrl+C로 멈춘 갈래다(프로브가 1.5초 뒤 그룹에 SIGINT). stub이 받은 WAV가 16kHz
# 모노 16비트이고 샘플이 전부 체인이 넣은 상수면 녹음이 진짜 마이크를 지났다. language는
# 기본이 비어 있어 칸 자체가 없다(Voxio — 빈 언어 코드는 400이다). 머리의 길이가 실제
# 샘플 길이와 같아야 한다 — arecord는 SIGINT에 대부분 머리를 못 고치고 끝나며(VD design
# 실측 4) tars-dictate가 다시 쓴다.
expect_run s1 0 "$OK_OUT" 'recording stopped by SIGINT after'
S1="$(stub_line s1)"
[ -n "$S1" ] || report_failure "s1: the stub got no request"
for want in 'auth=[Bearer vd0-test-key]' 'parts=[file,model,response_format]' 'model=[whisper-large-v3-turbo]' \
  'language=[-]' 'response_format=[json]' 'type=audio/wav' 'wav=[rate=16000 ch=1 bits=16 '; do
  case "$S1" in *"$want"*) ;; *) report_failure "s1: the request lacks ${want} (${S1})" ;; esac
done
S1_DATA="$(stub_field "$S1" data)"
S1_HDR="$(stub_field "$S1" header_data)"
S1_N="$(stub_field "$S1" n)"
S1_MODE="$(stub_field "$S1" mode)"
S1_MODE_COUNT="$(stub_field "$S1" mode_count)"
echo "s1: data=${S1_DATA} header_data=${S1_HDR} samples=${S1_N} mode=${S1_MODE}x${S1_MODE_COUNT}"
if [ "${S1_DATA:-0}" -lt 16000 ] || [ "$S1_HDR" != "$S1_DATA" ]; then
  report_failure "s1: the WAV's header says ${S1_HDR} bytes of samples, the file has ${S1_DATA} (want equal and at least 0.5s)"
fi
if [ "$S1_MODE" != "$FEED_VALUE" ] || [ "$S1_MODE_COUNT" != "$S1_N" ]; then
  report_failure "s1: the recording is not the microphone's constant (${S1_MODE_COUNT} of ${S1_N} samples are ${S1_MODE}, want all ${FEED_VALUE})"
fi
echo "Ctrl+C stopped the recording, the microphone's constant reached the API as 16kHz mono, and the text came back on stdout"

# ── 검사 4: 설정 — language · 모델 · 상한 ───────────────────────────────
# max_seconds=1이면 아무도 안 눌러도 정확히 1초(32,000바이트)에서 끝난다. 상한으로 끝난
# 녹음도 전사로 간다(Voxio의 maxRecordingSec와 같다).
expect_run s2 0 "$OK_OUT" 'recording stopped at the 1s limit'
S2="$(stub_line s2)"
for want in 'parts=[file,model,response_format,language]' 'model=[vd0-model]' 'language=[ko]' \
  'data=32000 header_data=32000' 'samples=[n=16000 mode=1234 mode_count=16000]'; do
  case "$S2" in *"$want"*) ;; *) report_failure "s2: the request lacks ${want} (${S2})" ;; esac
done
echo "dictation.conf set the language, the model and a 1s limit, and the limit ended the recording at 32000 bytes"

# ── 검사 5: 녹음 중의 SIGTERM은 취소다 ──────────────────────────────────
# API를 안 부르고(stub에 s3이 없다) 표준 출력이 비고 오디오가 안 남는다.
expect_run s3 143 '""' 'cancelled'
[ "$(stub_count s3)" -eq 0 ] || report_failure "s3: a cancelled recording still reached the API"
if grep -aE 'dictate-probe: s[0-9]+ leftover wav \[[^]]' "$LOG" >/dev/null; then
  report_failure "a run left its audio in /tmp ($(grep -aoE 'dictate-probe: s[0-9]+ leftover wav \[[^]]+' "$LOG" | head -n 1))"
fi
echo "SIGTERM cancelled the recording without calling the API, and no run left audio behind"

# ── 검사 6: 키가 없으면 녹음 전에 끝난다 · 환경 변수의 키 ─────────────────
# s4는 max_seconds=30이다. 녹음했다면 30초를 걸린다 — 2초 안에 끝난 것이 마이크를 안 연
# 증거이고, stub에 s4가 없는 것이 API를 안 부른 증거다.
expect_run s4 3 '""' 'no API key'
S4_MS="$(probe_line s4 | sed -E 's/.* ms ([0-9]+) out .*/\1/')"
[ "$S4_MS" -lt 2000 ] || report_failure "s4: without a key tars-dictate took ${S4_MS}ms; it must stop before recording"
[ "$(stub_count s4)" -eq 0 ] || report_failure "s4: without a key the request still reached the API"
expect_run s5 0 "$OK_OUT" 'transcribed 1000ms of audio'
case "$(stub_line s5)" in *'auth=[Bearer vd0-env-key]'*) ;; *) report_failure "s5: GROQ_API_KEY did not reach the request ($(stub_line s5))" ;; esac
echo "without a key tars-dictate stopped in ${S4_MS}ms before recording, and GROQ_API_KEY stood in for the file"

# ── 검사 7 · 8 · 9 · 10: 서버의 답 넷 ───────────────────────────────────
# 429는 실패(4)이고 표준 출력이 빈다. 무음 전사 " ."은 넣을 것이 없다(2). 제어 문자는
# 탭과 개행만 남기고 지운다 — ESC · CR · NEL(C1) · 끝의 ESC. text가 없는 응답은 실패(4)다.
expect_run s6 4 '""' 'HTTP 429'
expect_run s7 2 '""' 'the transcript is blank'
expect_run s8 0 '"vd0-ctrl a[201~bc\td\nef"' 'transcribed 1000ms of audio into 22 characters'
expect_run s9 4 '""' 'the response has no text'
echo "a 429 failed with nothing on stdout, a blank transcript inserted nothing, control characters were stripped, and a reply without text failed"

# ── 검사 11: 설정 파일의 모르는 키와 틀린 값 ──────────────────────────────
expect_run s10 0 "$OK_OUT" "unknown key 'colour'"
expect_run s10 0 "$OK_OUT" "max_seconds '0' is not 1..600, keeping 1"
case "$(stub_line s10)" in *'data=32000 header_data=32000'*) ;; *) report_failure "s10: the bad max_seconds was not ignored ($(stub_line s10))" ;; esac
echo "an unknown key and a bad value only warned, and the run kept the earlier max_seconds"

# ── 검사 12: stub이 받은 요청은 여덟이고, 어느 WAV의 머리도 거짓말을 안 한다 ──
# 취소(s3)와 키 없음(s4)만 API에 안 간다. 머리의 길이는 SIGINT로 멈춘 셋(s1 · s7 · s9)이
# 본다 — arecord가 고치지 못한 머리를 tars-dictate가 다시 쓴다(검사 3의 주석).
REQUESTS="$(grep -ac '^stub: POST ' "$STUBLOG")"
[ "$REQUESTS" -eq 8 ] || report_failure "the stub got ${REQUESTS} request(s), want 8 (s3 and s4 must not call it)"
while IFS= read -r req; do
  [ "$(stub_field "$req" header_data)" = "$(stub_field "$req" data)" ] \
    || report_failure "a WAV reached the API with a header that does not match its length (${req})"
done < <(grep -a '^stub: POST ' "$STUBLOG")
echo "the stub got eight requests, and every WAV's header matched its length"

# ── 검사 13: 기록 — 전사가 성공한 다섯만 원문과 함께 남는다 ───────────────
# 끈 뒤 디스크에서 꺼낸다. 원문(raw)은 받은 그대로라 s8의 제어 문자가 JSON 이스케이프로
# 남고, inserted는 지운 것이다. 실패 · 무음 · 취소 · 키 없음은 한 줄도 안 남는다.
debugfs -R "dump dictation.jsonl $WORK/dictation.jsonl" "$DISK" >/dev/null 2>&1
[ -s "$WORK/dictation.jsonl" ] || report_failure "the config disk holds no dictation.jsonl"
HISTORY="$(perl -MJSON::PP -e '
  binmode STDOUT, ":utf8";
  my $j = JSON::PP->new->utf8;
  # 제어 문자는 \x{1b}처럼 보이게 바꾼다 — 기대값을 이 파일에 글자로 적기 위해서다.
  sub show { my $s = shift; $s =~ s/([\x00-\x1f\x7f-\x9f])/sprintf("\\x{%x}", ord $1)/ge; $s }
  open(my $f, "<:raw", $ARGV[0]) or die;
  while (my $l = <$f>) {
    my $r = $j->decode($l);
    my $ok = ($r->{at} =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/ && !defined $r->{cleaned}
              && $r->{latency_ms} =~ /\A\d+\z/) ? "ok" : "bad";
    printf "raw=%s|inserted=%s|%d|%s\n", show($r->{raw}), show($r->{inserted}), $r->{audio_ms}, $ok;
  }' "$WORK/dictation.jsonl")" || report_failure "dictation.jsonl is not JSON lines"
echo "--- history ---"
printf '%s\n' "$HISTORY"
EXPECT_HISTORY='raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|S1|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=vd0-ctrl a\x{1b}[201~b\x{d}c\x{9}d\x{a}e\x{85}f\x{1b}|inserted=vd0-ctrl a[201~bc\x{9}d\x{a}ef|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok'
EXPECT_HISTORY="${EXPECT_HISTORY/S1/$(( S1_DATA * 1000 / 32000 ))}"
[ "$HISTORY" = "$EXPECT_HISTORY" ] || report_failure "dictation.jsonl does not hold the five successful runs as expected"
echo "dictation.jsonl keeps the five successful runs with the raw text next to what was inserted, and nothing else"

echo "VD check PASS"
```

`dictation/probe.sh`:

```bash
#!/usr/bin/bash
# VD 체인의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(audio/probe.sh와 같은 자리).
#
# init이 /config/services.d의 실행 파일로 이것을 띄우고, 표준 출력은 /dev/console(= 시리얼
# 로그)이다. 여기서 찍는 `dictate-probe:` 줄을 dictation/check.sh가 본다. 게이트는 게스트에
# 한 글자도 안 친다.
#
# 사람이 셸에서 하는 일 그대로를 한다 — /config/dictation.conf를 고치고, tars-dictate를
# 치고, Ctrl+C로 멈춘다. Ctrl+C는 tty가 앞의 작업 그룹 전체에 보내는 SIGINT이므로 여기서는
# tars-dictate를 제 그룹으로 띄우고(set -m) 그 그룹에 kill -INT를 보낸다. 전사 API는
# 컨테이너의 stub.pl이다 — 경로의 첫 마디가 답을 고르고 둘째 마디가 이 갈래의 이름이다.
#
# 끝나면 kill -TERM 1로 전원을 끈다. 체인이 그 뒤에 설정 디스크의 dictation.jsonl을 꺼낸다.

say() { echo "dictate-probe: $*"; }
flat() { tr '\n' '|' | sed 's/|$//'; }
STUB=http://10.0.2.100:8080

# 설정 파일을 사람처럼 통째로 다시 쓴다. 인자는 key=value 줄들이다.
conf() { printf '%s\n' "# written by the VD probe" "$@" > /config/dictation.conf; }

# tars-dictate를 한 번 돌리고 결과를 한 줄로 찍는다.
#   $1  갈래 이름(로그에서 찾는 글자)
#   $2  끝내는 법 — cap(max_seconds가 끝낸다) · int(1.5초 뒤 그룹에 SIGINT) ·
#       term(1초 뒤 그룹에 SIGTERM)
# out은 jq로 JSON 문자열을 만든다 — 개행 · 탭 · ESC가 그대로 콘솔에 나가면 줄이 깨진다.
# 걸린 시간(ms)도 찍는다. 키가 없을 때 "녹음 전에 끝났다"를 이 값으로 본다.
dictate() {
  local t0=$EPOCHREALTIME pid rc
  set -m
  tars-dictate > /tmp/vd-out 2> /tmp/vd-err &
  pid=$!
  set +m
  case $2 in
    int) sleep 1.5; kill -INT -- "-$pid" ;;
    term) sleep 1; kill -TERM -- "-$pid" ;;
  esac
  wait "$pid"
  rc=$?
  local ms=$(( (${EPOCHREALTIME/./} - ${t0/./}) / 1000 ))
  say "$1 exit ${rc} ms ${ms} out [$(jq -Rs . < /tmp/vd-out)] err [$(flat < /tmp/vd-err)]"
  say "$1 leftover wav [$(ls /tmp/tars-dictate.*.wav 2>/dev/null | flat)]"
}

say "start"
say "tars-dictate is [$(command -v tars-dictate)]"
say "jq [$(jq --version)]"

# 네트워크. stub(10.0.2.100)과 TLS 상대(10.0.2.2)에 닿으려면 dhcpcd가 주소를 붙이고
# 경로를 만들어야 한다. leased 줄은 주소보다 먼저 찍히므로(lessons 73) 경로를 본다.
for _ in $(seq 1 120); do
  ip -4 route show default 2>/dev/null | grep 'via 10.0.2.2' >/dev/null && break
  sleep 0.25
done
say "route [$(ip -4 route show default 2>&1 | flat)]"

# 소리 카드. HDA 코덱 탐색은 커널의 일 큐에서 돈다(audio/probe.sh와 같다). 부팅이 믹서를
# 켜는 것(AU-M1)도 기다린다 — 꺼져 있으면 녹음이 0만 받는다.
for _ in $(seq 1 100); do
  if [ -e /dev/snd/controlC0 ] && ! pgrep -x alsactl >/dev/null \
    && amixer -c 0 sget Capture 2>/dev/null | grep '\[on\]' >/dev/null; then break; fi
  sleep 0.1
done
say "capture [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

# 1. TLS. curl이 인증 기관 목록을 읽는가 — 목록이 없으면 77, 있는데 상대를 못 믿으면 60이다.
# 상대는 컨테이너의 openssl s_server(자기 서명 인증서)다. 같은 인증서를 --cacert로 주면
# 핸드셰이크까지 끝나 0이다(TLS 라이브러리가 돈다).
out="$(curl -sS -o /dev/null https://10.0.2.2:45492/ 2>&1)"; rc=$?
say "tls default exit ${rc} [$(printf '%s' "$out" | flat)]"
out="$(curl -sS --cacert /config/vd0-tls.pem https://10.0.2.2:45492/ 2>&1 | grep -o 's_server' | head -n 1)"
say "tls pinned [${out}]"

# 2. 기본값으로 — language 없음, 모델 기본, 사람이 Ctrl+C로 멈춘다.
conf "transcribe_url=${STUB}/ok/s1"
dictate s1 int

# 3. 설정 셋 — language · 모델 · 1초 상한. 사람이 아무것도 안 눌러도 끝난다.
conf "transcribe_url=${STUB}/ok/s2" "language=ko" "transcribe_model=vd0-model" "max_seconds=1"
dictate s2 cap

# 4. 녹음 중에 취소 — API를 안 부르고 오디오를 지운다.
conf "transcribe_url=${STUB}/ok/s3" "max_seconds=30"
dictate s3 term

# 5. 키가 없다 — 녹음 전에 끝난다(max_seconds=30이라 녹음했다면 30초를 걸린다).
mv /config/groq.key /config/groq.key.off
conf "transcribe_url=${STUB}/ok/s4" "max_seconds=30"
dictate s4 cap
# 같은 자리에서 환경 변수의 키 — 파일이 없어도 그것을 쓴다.
conf "transcribe_url=${STUB}/ok/s5" "max_seconds=1"
GROQ_API_KEY=vd0-env-key dictate s5 cap
mv /config/groq.key.off /config/groq.key

# 6. 서버가 거절한다(429).
conf "transcribe_url=${STUB}/fail/s6" "max_seconds=1"
dictate s6 cap

# 7. 무음 전사(" .") — 넣을 것이 없다. 이 갈래와 9는 Ctrl+C로 멈춘다 — arecord가 SIGINT에
# WAV 머리를 못 고치는 일이 판마다 달라서(VD design 실측 4), 머리를 다시 쓰는 tars-dictate의
# 줄이 빠지면 SIGINT 셋(s1 · s7 · s9) 중 하나에는 거의 반드시 드러나게 한다.
conf "transcribe_url=${STUB}/blank/s7" "max_seconds=30"
dictate s7 int

# 8. 응답에 제어 문자 — 지워서 낸다.
conf "transcribe_url=${STUB}/ctrl/s8" "max_seconds=1"
dictate s8 cap

# 9. 응답에 text가 없다.
conf "transcribe_url=${STUB}/notext/s9" "max_seconds=30"
dictate s9 int

# 10. 설정 파일의 모르는 키와 틀린 값은 경고만 하고 기본값으로 돈다.
conf "transcribe_url=${STUB}/ok/s10" "max_seconds=1" "colour=blue" "max_seconds=0"
dictate s10 cap

sync
say "history lines [$(wc -l < /config/dictation.jsonl 2>/dev/null || echo none)]"
say "done"
say "powering off at uptime $(cut -d' ' -f1 /proc/uptime)"
kill -TERM 1
exec sleep 100000
```

`dictation/stub.pl`:

```perl
#!/usr/bin/perl
# VD 체인의 Groq 흉내(VD design 결정 5). QEMU의 guestfwd가 게스트의 10.0.2.100:8080
# 연결마다 이것을 하나씩 띄우고 표준 입출력을 그 연결에 잇는다 — 듣는 프로세스가
# 없다(lessons 41, net 체인의 cat과 같은 자리). 그래서 요청 하나를 읽고 답 하나를
# 쓰고 끝난다.
#
# 하는 일 둘.
#   1. 받은 것을 로그(인자 1) 한 줄로 남긴다 — 경로 · 인증 헤더 · multipart의 각 칸 ·
#      file 칸의 WAV 머리와 샘플. 체인은 이 줄로 "녹음이 마이크를 지나 API까지 왔다"를 본다
#   2. 경로의 첫 마디로 답을 고른다. 게스트의 dictation.conf가 transcribe_url로 어느
#      답을 받을지 정한다(둘째 마디는 갈래의 이름이라 로그에서 요청을 가른다)
#        /ok/…      200 {"text":" 안녕하세요 vd0-dictated"}  앞의 공백은 Whisper의 버릇이다
#        /ctrl/…    200 text에 ESC · CR · 탭 · 개행이 섞였다 — 지워지는지 본다
#        /blank/…   200 {"text":" ."}                         Whisper가 무음에 주는 답
#        /notext/…  200 {"error":null}                        text 칸이 없다
#        /fail/…    429                                       무료 티어의 분당 한도
#
# 컨테이너에 python이 없어서 perl로 쓴다(feedback_scripting_runtimes). 코어 모듈만 쓴다.
use strict;
use warnings;

my $log = shift or die "usage: stub.pl <log>\n";
binmode STDIN;
binmode STDOUT;
$| = 1;

sub line_in {
  my $l = <STDIN>;
  return undef unless defined $l;
  $l =~ s/\r?\n\z//;
  return $l;
}

my $request = line_in() // exit 0;
my ($method, $path) = split / /, $request;
my %h;
while (defined(my $l = line_in())) {
  last if $l eq '';
  my ($k, $v) = split /:\s*/, $l, 2;
  $h{lc $k} = $v;
}
# curl은 큰 본문 앞에 Expect: 100-continue를 붙이고 1초를 기다린다. 답하면 기다림이 없다.
if (($h{expect} // '') =~ /100-continue/i) {
  print "HTTP/1.1 100 Continue\r\n\r\n";
}
my $len = $h{'content-length'} // 0;
my $body = '';
while (length($body) < $len) {
  my $n = read(STDIN, my $chunk, $len - length($body));
  last unless $n;
  $body .= $chunk;
}

# multipart의 칸을 이름으로 모은다.
my %part;
my @order;
my $file_desc = '-';
if (($h{'content-type'} // '') =~ /boundary=(\S+)/) {
  my $b = $1;
  for my $p (split /--\Q$b\E/, $body) {
    next unless $p =~ /\A\r\n(.*?)\r\n\r\n(.*)\r\n\z/s;
    my ($ph, $pv) = ($1, $2);
    next unless $ph =~ /name="([^"]+)"/;
    my $name = $1;
    push @order, $name;
    $part{$name} = $pv;
    if ($name eq 'file') {
      my ($fn) = $ph =~ /filename="([^"]*)"/;
      my ($ty) = $ph =~ /Content-Type:\s*(\S+)/i;
      $file_desc = sprintf 'name=%s type=%s bytes=%d', $fn // '-', $ty // '-', length $pv;
    }
  }
}

# WAV 머리와 샘플. 녹음이 진짜 마이크를 지났다면 체인이 넣은 상수가 거의 전부다.
# mode는 가장 많이 나온 값, mode_count는 그 개수다.
my $wav_desc = '-';
my $sample_desc = '-';
if (defined $part{file} && length($part{file}) >= 44 && substr($part{file}, 0, 4) eq 'RIFF') {
  my $w = $part{file};
  my ($ch, $rate, $bits) = (unpack('v', substr($w, 22, 2)), unpack('V', substr($w, 24, 4)), unpack('v', substr($w, 34, 2)));
  my $hdr_data = unpack('V', substr($w, 40, 4));
  my $data = substr($w, 44);
  $wav_desc = sprintf 'rate=%d ch=%d bits=%d data=%d header_data=%d', $rate, $ch, $bits, length $data, $hdr_data;
  my %count;
  my $n = 0;
  for (my $i = 0; $i + 2 <= length $data; $i += 2) {
    $count{unpack('s<', substr($data, $i, 2))}++;
    $n++;
  }
  my ($mode) = sort { $count{$b} <=> $count{$a} } keys %count;
  $sample_desc = sprintf 'n=%d mode=%s mode_count=%d', $n, $mode // '-', defined $mode ? $count{$mode} : 0;
}

my $field = sub { my $v = $part{$_[0]}; defined $v ? $v : '-' };
open(my $lf, '>>', $log) or die "cannot open $log\n";
printf $lf "stub: %s %s auth=[%s] parts=[%s] model=[%s] language=[%s] response_format=[%s] file=[%s] wav=[%s] samples=[%s]\n",
  $method // '-', $path // '-', $h{authorization} // '-', join(',', @order),
  $field->('model'), $field->('language'), $field->('response_format'), $file_desc, $wav_desc, $sample_desc;
close $lf;

my ($kind) = ($path // '') =~ m{\A/([a-z]+)};
my ($status, $json) = (200, '{"text":" 안녕하세요 vd0-dictated"}');
if (!defined $kind) { ($status, $json) = (404, '{"error":"no such path"}') }
elsif ($kind eq 'ok') { }
elsif ($kind eq 'ctrl') { $json = '{"text":"vd0-ctrl a\u001b[201~b\rc\td\ne\u0085f\u001b"}' }
elsif ($kind eq 'blank') { $json = '{"text":" ."}' }
elsif ($kind eq 'notext') { $json = '{"error":null}' }
elsif ($kind eq 'fail') { ($status, $json) = (429, '{"error":{"message":"Rate limit reached"}}') }
else { ($status, $json) = (404, '{"error":"no such path"}') }

my $reason = { 200 => 'OK', 404 => 'Not Found', 429 => 'Too Many Requests' }->{$status};
# 본문의 한글은 UTF-8 바이트 그대로다(이 파일이 UTF-8이고 use utf8이 없다).
print "HTTP/1.1 $status $reason\r\nContent-Type: application/json\r\nContent-Length: " . length($json)
  . "\r\nConnection: close\r\n\r\n$json";
```

### 3-2. `check.sh` — 문단 하나와 `CHAINS` 한 줄

E1 — `old_string`(기준 파일 346줄부터):

```bash
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

`new_string`:

```bash
# VD 체인은 받아쓰기를 본다. 게스트의 tars-dictate가 마이크(audio 체인과 같은 HDA와
# file 플러그인)에서 녹음해 전사 API에 올리고 받은 글자를 낸다. API는 Groq가 아니라
# 컨테이너의 perl stub이다 — QEMU의 guestfwd가 게스트의 10.0.2.100:8080 연결마다 띄운다.
# 설정 디스크의 services.d/probe가 사람이 셸에서 하는 일(설정 파일을 고치고 치고 Ctrl+C)을
# 열 갈래로 하고, stub은 받은 WAV의 샘플까지 로그에 적는다. curl이 인증 기관 목록을 읽는지는
# 컨테이너의 openssl s_server(45492)로 본다. 게스트에 한 글자도 안 친다. 회차당 부팅 1회.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
```

E2 — `old_string`(기준 파일 368줄부터):

```bash
  "AU-M3:./audio/check.sh"
```

`new_string`:

```bash
  "AU-M3:./audio/check.sh"
  "VD-M0:./dictation/check.sh"
```

### 3-3. 확인

```bash
for f in dictation/check.sh dictation/probe.sh dictation/stub.pl check.sh; do cmp $f /tmp/run/vd0/new/$f && echo "SAME $f"; done
bash -n dictation/check.sh && bash -n dictation/probe.sh && bash -n check.sh && perl -c dictation/stub.pl && echo SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./dictation/check.sh && require_no_early_exit_pipe ./dictation/check.sh &&
  require_explicit_nic ./dictation/check.sh && echo ENTRY-OK'
python3 /tmp/run/vd0/anchors.py post "$PWD"
```

기대: `SAME` 넷, `dictation/stub.pl syntax OK`와 `SYNTAX-OK`, `ENTRY-OK`, `post: 5 edits, 0 bad`. 호스트(macOS)에 perl이 없으면 `perl -c`를
빼고 그렇다고 적는다.

## Task 4: 체인 한 번과 regression

체인은 하나씩 돈다.

### 4-1. `dictation` 체인

첫 판은 캐시를 지운 판이다(2분 안팎). 시리얼 로그와 stub 로그를 남기려고 정리 함수의 `rm`을 바꾼 사본을 덮어 돈다 — 저장소 파일은 안 바뀐다.

```bash
sed 's#rm -rf "\$LOG" "\$WORK"#cp "$LOG" /impl/serial.log; rm -rf /impl/work; cp -r "$WORK" /impl/work; rm -rf "$LOG" "$WORK"#' \
  dictation/check.sh > /tmp/run/vd0/impl/check_keep.sh && chmod +x /tmp/run/vd0/impl/check_keep.sh
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/vd0/impl:/impl \
    -v /tmp/run/vd0/impl/check_keep.sh:/workspace/dictation/check.sh:ro -w /workspace tars-devcontainer bash -c '
    rm -rf terminal/.zig-cache terminal/zig-out init/.zig-cache init/zig-out
    bash dictation/check.sh > /impl/dictation.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rmdir /tmp/run/docker.lock
grep -av '^stub:' /tmp/run/vd0/impl/dictation.log | tail -n 19
```

기대: `exit=0`, `real`이 2분 안팎. 끝 열아홉 줄은 이렇다(사본의 마지막 판).

```
the initrd carries tars-dictate and a CA bundle of 150 certificates
=== boot: q35 with an HDA microphone, SLIRP with a transcription stub at 10.0.2.100:8080 ===
curl loads the CA bundle (60 against a self-signed peer) and finishes a TLS handshake with a pinned one
s1: data=60698 header_data=60698 samples=30349 mode=1234x30349
Ctrl+C stopped the recording, the microphone's constant reached the API as 16kHz mono, and the text came back on stdout
dictation.conf set the language, the model and a 1s limit, and the limit ended the recording at 32000 bytes
SIGTERM cancelled the recording without calling the API, and no run left audio behind
without a key tars-dictate stopped in 21ms before recording, and GROQ_API_KEY stood in for the file
a 429 failed with nothing on stdout, a blank transcript inserted nothing, control characters were stripped, and a reply without text failed
an unknown key and a bad value only warned, and the run kept the earlier max_seconds
the stub got eight requests, and every WAV's header matched its length
--- history ---
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1896|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=vd0-ctrl a\x{1b}[201~b\x{d}c\x{9}d\x{a}e\x{85}f\x{1b}|inserted=vd0-ctrl a[201~bc\x{9}d\x{a}ef|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
dictation.jsonl keeps the five successful runs with the raw text next to what was inserted, and nothing else
VD check PASS
```

`s1:`의 `data` · `samples`와 `history`의 첫 줄 `1896`, `stopped in 21ms`의 수는 판마다 조금 다를 수 있다(사본의 판들은 같았다). 빨개지면
`report_failure`가 찍는 표식 · 프로브 줄 · stub 로그 · 마지막 30줄을 그대로 보고한다. 프로브의 줄 전부는
`grep -a 'dictate-probe:' /tmp/run/vd0/impl/serial.log`다.

### 4-2. regression — `tools` · `net` · `audio` · `boot` · `install`

확정 8의 다섯이다. 한 컨테이너에서 차례로 돈다. 약 7분이라 Bash 한 번의 상한(10분)에 붙으므로 `run_in_background`로 돌리고 기다린다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -v /tmp/run/vd0/impl:/impl -w /workspace tars-devcontainer bash -c '
  for c in tools net audio boot install; do s=$(date +%s); bash $c/check.sh > /impl/reg_$c.log 2>&1
    echo "$c exit=$? $(( $(date +%s) - s ))s"; done' > /tmp/run/vd0/impl/reg.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/vd0/impl/reg.out
rg -a 'init waited|tools the list names|AU check PASS' /tmp/run/vd0/impl/reg_install.log /tmp/run/vd0/impl/reg_tools.log /tmp/run/vd0/impl/reg_audio.log
```

기대: 다섯 다 `exit=0`. `all 92 tools`, `AU check PASS`, `init waited`가 1,500ms 이상(사본 1,700ms)이다. `init waited`가 500ms 아래면 멈추고 보고한다.

## Task 5: mutation

확정 7의 표다. 사본은 `/tmp/run/vd0/impl/mut/`에 만든다. 만드는 스크립트와 도는 스크립트는 plan을 쓰며 쓴 것을 그대로 쓴다.

### 5-0. 사본을 만든다

```bash
python3 /tmp/run/vd0/make_mut.py "$PWD" /tmp/run/vd0/impl/mut
M=/tmp/run/vd0/impl/mut
for p in initrd_m1.sh:kernel/make_initrd.sh check_no1ca.sh:dictation/check.sh dictate_m2:kernel/dictation/tars-dictate \
  dictate_m3:kernel/dictation/tars-dictate dictate_m4:kernel/dictation/tars-dictate dictate_m5:kernel/dictation/tars-dictate \
  dictate_m6:kernel/dictation/tars-dictate dictate_m7:kernel/dictation/tars-dictate; do
  echo "${p%%:*} $(diff ${p#*:} $M/${p%%:*} | rg -c '^[<>]')"; done
```

기대: `mutation copies: 8`, 그리고 바뀐 줄 수가 `initrd_m1.sh 18` · `check_no1ca.sh 9` · `dictate_m2 16` · `dictate_m3 2` · `dictate_m4 12` ·
`dictate_m5 2` · `dictate_m6 2` · `dictate_m7 2`. 다르면 돌리지 말고 보고한다.

`make_mut.py`:

```python
"""VD-M0 plan Task 5의 mutation 사본을 만든다.

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
    assert a < b, dst
    path = os.path.join(out, dst)
    open(path, 'w').write(s[:a] + s[b:])
    os.chmod(path, 0o755)


# mutation 1 — initrd에 인증 기관 목록이 없다(HEAD의 모양)
cut('kernel/make_initrd.sh', 'initrd_m1.sh', '# VD-M0. curl이 https에서 믿을', '# UT-M3 결정 8.')
# 그것을 검사 1이 먼저 잡으므로, 검사 1의 목록 부분을 뺀 체인 사본으로 검사 2까지 보낸다
make('dictation/check.sh', 'check_no1ca.sh',
     'for want in usr/bin/tars-dictate etc/ssl/certs/ca-certificates.crt; do\n',
     'for want in usr/bin/tars-dictate; do\n')
s = open(os.path.join(out, 'check_no1ca.sh')).read()
a = s.index('BUNDLE_CERTS="$(')
b = s.index('if ! bash -n ../kernel/dictation/tars-dictate; then')
s = s[:a] + 'BUNDLE_CERTS=skipped\n' + s[b:]
open(os.path.join(out, 'check_no1ca.sh'), 'w').write(s)
# mutation 2 — WAV 머리를 다시 쓰지 않는다(arecord가 SIGINT에 못 고친 머리가 그대로 간다)
cut('kernel/dictation/tars-dictate', 'dictate_m2', '\n# 머리를 실제 길이로 다시 쓴다.', 'if [ "$stopped" = 1 ]; then')
# mutation 3 — 제어 문자를 안 지운다
make('kernel/dictation/tars-dictate', 'dictate_m3',
     'inserted: ($raw | printable | strip)', 'inserted: $raw')
# mutation 4 — 사전 점검이 없다(키가 없어도 녹음하고 빈 키로 보낸다)
cut('kernel/dictation/tars-dictate', 'dictate_m4', 'if [ -z "$key" ]; then\n  say "no API key', '# ── 2. 녹음')
# mutation 5 — 기록을 안 남긴다
make('kernel/dictation/tars-dictate', 'dictate_m5',
     '  printf \'%s\\n\' "$rec" >> "$HISTORY_FILE" || say "could not append to $HISTORY_FILE"\n', '  :\n')
# mutation 6 — 무음 판정이 없다(" ."을 넣는다)
make('kernel/dictation/tars-dictate', 'dictate_m6',
     'def blank: test("[\\\\p{L}\\\\p{N}]") | not;', 'def blank: false;')
# mutation 7 — SIGTERM을 받아도 녹음을 끝내고 전사로 간다(취소가 없다)
make('kernel/dictation/tars-dictate', 'dictate_m7',
     'trap on_term TERM\n', "trap 'stopped=1' TERM\n")
print('mutation copies:', len(os.listdir(out)))
```

`run_mut.sh` — 사본을 저장소 경로 위에 읽기 전용으로 덮어 체인 한 판을 돈다. Zig를 안 고치므로 캐시를 안 지운다(initrd는 체인이 매번 짓는다).

```bash
#!/bin/bash
# VD-M0 plan Task 5의 mutation 한 판을 돈다.
# 사용: run_mut.sh <저장소 루트> <이미지> <사본 디렉터리> <판 이름> <사본:저장소 경로>...
# 사본을 저장소 경로 위에 읽기 전용으로 덮어 dictation 체인을 한 번 돌리고, 로그를 <사본 디렉터리>/<판 이름>.log에 둔다.
# 첫 줄 mounted:의 여덟 자리는 차례로 "인증 기관 목록 · 머리 다시 쓰기 · 제어 문자 지우기 · 키 점검 ·
# 기록 · 무음 판정 · SIGTERM 취소 · 검사 1의 목록 대조"의 수다. 덮지 않은 판은 11111111이다.
repo=$1; img=$2; mut=$3; name=$4; shift 4
mounts=""
for m in "$@"; do mounts="$mounts -v $mut/${m%%:*}:/workspace/${m#*:}:ro"; done
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
s=$(date +%s)
docker run --rm -v "$repo":/workspace $mounts -v "$mut":/mut -w /workspace "$img" bash -c "
  D=kernel/dictation/tars-dictate
  echo \"mounted: \$(grep -c '^done > \"\$WORKDIR/etc/ssl/certs/ca-certificates.crt\"' kernel/make_initrd.sh)\$(grep -c '^} > \"\$wav.new\" && mv' \$D)\$(grep -c 'inserted: (\$raw | printable | strip)' \$D)\$(grep -c 'say \"no API key' \$D)\$(grep -c '>> \"\$HISTORY_FILE\"' \$D)\$(grep -c 'def blank: test(' \$D)\$(grep -c '^trap on_term TERM' \$D)\$(grep -c 'for want in usr/bin/tars-dictate etc/ssl' dictation/check.sh)\"
  bash dictation/check.sh > /mut/$name.log 2>&1; echo \"exit=\$?\""
rmdir /tmp/run/docker.lock
echo "== $name $(( $(date +%s) - s ))s"
grep -a '^FAIL\|^VD check PASS' "$mut/$name.log" | head -2
```

### 5-1. 체인 아홉 판

판마다 35초 안팎(`m1`은 7초, `m4`는 1분), 합해서 5분 남짓이다. `run_in_background`로 돌리고 기다린다.

```bash
R="$PWD"; I=tars-devcontainer; M=/tmp/run/vd0/impl/mut; X=/tmp/run/vd0/run_mut.sh
{ $X $R $I $M m0
  $X $R $I $M m1 initrd_m1.sh:kernel/make_initrd.sh
  $X $R $I $M m1_boot initrd_m1.sh:kernel/make_initrd.sh check_no1ca.sh:dictation/check.sh
  $X $R $I $M m2 dictate_m2:kernel/dictation/tars-dictate
  $X $R $I $M m3 dictate_m3:kernel/dictation/tars-dictate
  $X $R $I $M m4 dictate_m4:kernel/dictation/tars-dictate
  $X $R $I $M m5 dictate_m5:kernel/dictation/tars-dictate
  $X $R $I $M m6 dictate_m6:kernel/dictation/tars-dictate
  $X $R $I $M m7 dictate_m7:kernel/dictation/tars-dictate; } > $M/run.out 2>&1
cat $M/run.out
```

기대는 확정 7의 표에서 그 판의 `FAIL` 줄이고 `m0`은 `VD check PASS`다. `mounted:`는 `m0`이 `11111111`, `m1`이 `01111111`, `m1_boot`이
`01111110`, `m2`가 `10111111`, `m3`이 `11011111`, `m4`가 `11101111`, `m5`가 `11110111`, `m6`이 `11111011`, `m7`이 `11111101`이다. 로그에
`Killed`가 보이고 `FAIL: … build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시 돈다.
예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 덮기를 의심한다(`mounted:`).

`m2`만 운에 기댄다. `arecord`가 SIGINT에 머리를 고치는 판이 열에 하나쯤이라(design 실측 4) s1이 우연히 맞는 머리를 낼 수 있다 — 그때는 같은 판의
s7이나 s9가 검사 12에서 잡는다. 셋이 모두 고친 판이 나올 확률은 천에 하나 남짓이다. 초록이면 한 번 더 돌리고 둘 다 보고한다.

### 5-2. 되돌림을 본다

mutation은 `-v`로 덮어 돌렸으므로 작업 트리의 파일은 그대로다. 체인을 한 번 더 돈다(데운 판, 40초 안쪽).

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash dictation/check.sh > /tmp/d.log 2>&1; echo "exit=$?"; tail -n 1 /tmp/d.log'
rmdir /tmp/run/docker.lock
git status --short
```

기대: `exit=0` · `VD check PASS`. `git status`는 `M` 셋(`check.sh` · `devcontainer/Dockerfile` · `kernel/make_initrd.sh`)과 `??` 둘(`dictation/` ·
`kernel/dictation/`)이고, lead의 문서가 commit 전이면 그것이 더 있다. 다른 것이 보이면(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트
파일) 그 목록을 보고한다.

### 5-3. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체). 사본에서는 `3 files changed, 50 insertions(+)`였고 지운 줄이 없다(새 파일 넷은
  `git diff`에 안 나온다 — `git add -N` 뒤에는 7 files, 965 insertions).
- Task 0의 출력.
- Task 1 ~ 3의 확인 출력(`SAME` · `build exit` · `150` · `SYNTAX-OK` · `ENTRY-OK` · `anchors.py`).
- Task 4의 `exit=` · `real` · 끝 열아홉 줄과 regression 다섯의 줄 · `init waited` · `all 92 tools` · `AU check PASS`.
- Task 5의 `diff` 수 여덟 · 판마다 `mounted:` · `exit=` · 시간 · `FAIL` 줄, 5-2의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 6: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 일곱 파일을 `/tmp/run/vd0/new/`와 `cmp`한다. Task 4의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 스물한 체인 × 2다. 판정은 `PASS: 2/2` × 21과 `VD check PASS` 둘이다. `run_in_background`로
   돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_vd0.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_vd0.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다. `rg -c 'PASS: 2/2' /tmp/gate_vd0.log`가 21,
   `rg -c 'VD check PASS' /tmp/gate_vd0.log`가 2여야 한다.
3. 실측 절 채우기, design에 덧붙이기(아래 "design과 다르게 적은 것"), design `Status:`(M0 끝, M1 plan 차례).
4. commit. 넣는 것은 일곱 파일과 이 plan이고 design이 바뀌었으면 함께 넣는다. `git add`는 경로를 하나씩 지정한다(`dictation/` 아래 셋과
   `kernel/dictation/tars-dictate`를 이름으로).
5. 실기. 사용자가 키를 넣고 `tars-dictate`를 쳐 보는 것은 M0 뒤에 바로 할 수 있다 — design "닫을 때"의 running-tars.md 명령. 진짜 Groq의
   첫 응답 시간(design 위험 5)과 인증서 검증(위험 7)을 거기서 본다.

## design과 다르게 적은 것

design 본문은 이 plan과 같은 날 같은 사람이 썼으므로 어긋난 자리가 없다. 구현 뒤에 lead가 고칠 것.

1. design `Status:`.
2. 결정 8의 initrd 증분과 검증 절의 표는 사본의 값이다. 루트 게이트의 값이 다르면 실측 절에 적는다.

## 이 milestone에서 안 하는 것

- 트리거(오른쪽 Cmd 두 번) · 상태 줄 · 커서 자리에 넣기(VD-M1).
- 정리 단계(LLM) · `cleanup*` 키 · running-tars.md의 받아쓰기 절(VD-M2. running-tars.md는 lead가 서브프로젝트를 닫을 때 쓴다).
- 진짜 Groq. 게이트는 Groq를 절대 안 부른다(키도 바깥 길도 없다). 실기에서 사용자가 본다.
- `tars.conf`의 받아쓰기 키 · seed(design 결정 3).

## VD-M0이 실측한 것

(구현 뒤에 lead가 채운다.)
