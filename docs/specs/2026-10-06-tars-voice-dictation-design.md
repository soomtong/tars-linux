# TARS Voice Dictation — Design

Date: 2026-10-06
Status: 진행 중. M0 · M1이 끝났다(2026-10-06) — 게스트 파이프라인 `tars-dictate` · 인증 기관 목록 · 스물한번째 체인(M0), terminal의 오른쪽 Cmd 더블 탭 · `tars-dictate` 자식 · 상태 줄 · 붙여넣기 경로 삽입 · 비밀번호 거절(M1). 다음은 M2(정리 단계 · 실기 안내, `docs/plans/2026-10-06-tars-voice-dictation-vd-m2.md`). plan은 `-vd-m0.md` · `-vd-m1.md`이고 각 끝의 "실측한 것" 절이 값이다.

사용자의 요청(2026-10-05)에서 시작한다.

> 2. 마이크로 음성 전사 (Voxio 포팅). /Users/dp/Repository/Voxio

같은 요청의 1번(오디오 기기 활성화)은 Audio Devices(AU)로 먼저 열어 2026-10-06에 닫았다. AU가 세운 것은 "게스트에서 `arecord`가
마이크의 바이트를 WAV로 쓴다"까지다(AU design 비목표 4). 그 WAV로 하는 일 전부가 여기다.

## 한 줄 요약

오른쪽 Cmd를 두 번 누르면 마이크가 열리고, 말한 것이 지금 패널의 커서 자리에 글자로 들어간다 — macOS 앱 Voxio(1.0.1)를 TARS로
옮긴다. 녹음 · 전사 · 기록은 게스트의 bash 스크립트 하나(`tars-dictate`)가 `arecord` · `curl` · `jq`로 하고, 트리거 · 상태 표시 ·
삽입은 terminal이 맡는다.

```
VD-M0   셸에서 tars-dictate → 말하고 Ctrl+C   →  받아 적은 글자가 표준 출력에, 원문이 /config/dictation.jsonl에
        게이트: QEMU HDA 마이크에 넣은 상수가 값까지 같게 전사 API(stub)에 닿는다. Groq를 한 번도 안 부른다
VD-M1   오른쪽 Cmd 두 번 → 상태 줄의 녹음 표시 → 다시 두 번  →  그 패널의 커서 자리에 글자(bracketed paste). Esc는 취소
VD-M2   전사 뒤 LLM 정리(군더더기 제거 · 길이 가드 · 실패하면 원문) · 실기 안내
```

## 왜 새 서브프로젝트인가

Voxio의 일을 층 다섯으로 나누면 TARS에는 위의 둘만 있고, 그중 하나(전사)는 인증 기관 목록이 없어 반쪽이다.

| 층 | 무엇 | 누구의 것 | 지금 |
|---|---|---|---|
| 녹음 | 기본 장치에서 16kHz 모노 16비트 WAV | `arecord`(AU) | 있다. 16kHz 모노가 기본 장치로 도는지는 이 design이 쟀다(실측 3) |
| 전사 · 정리 | HTTP multipart · JSON · TLS | Groq API · `curl` · `jq` | 도구는 있다. 인증 기관 목록이 없어서 https는 전부 실패한다(실측 1) |
| 파이프라인 | 순서와 갈래 · 무음 판정 · 제어 문자 · WAV 머리 · 기록 | 우리 — `tars-dictate`(M0, 정리는 M2) | 없다 |
| 트리거 · 상태 · 삽입 | 오른쪽 Cmd 두 번 · 상태 줄 · PTY에 붙여 넣기 | 우리 — terminal(M1) | 붙여 넣기 경로(`dumpPaste` · `pasteParts`)만 있다 |
| 게이트 | 전사 API stub · 마이크 상수 · TLS 상대 | 우리 — 새 체인 `dictation/check.sh` | 없다 |

## 모델

한 번의 발화가 지나는 길이다. Voxio의 파이프라인(ARCHITECTURE 3절)을 한 줄씩 TARS의 자리에 대 본다.

| Voxio의 단계 | TARS의 자리 | milestone |
|---|---|---|
| 더블 탭 감지(이벤트 탭) | terminal이 evdev에서 오른쪽 Cmd(`KEY_RIGHTMETA`, 자판 맞바꿈 뒤)를 두 번 본다 | M1 |
| 사전 점검(API 키) | `tars-dictate`가 마이크를 열기 전에 키를 본다. 없으면 exit 3 | M0 |
| 포커스 앱 · 비밀번호 칸 확인 | 없다. 트리거를 누른 순간의 포커스 패널이 대상이다(비목표 8, 위험 2) | — |
| 오버레이 "연결 중" · "녹음 중" | 상태 줄 꼬리(`COPY`와 같은 자리) | M1 |
| 마이크 열기 · 살아남 판정 | `arecord`가 기본 장치를 연다. 살아남 판정은 없다(위험 1) | M0 |
| 더블 탭 · Esc · 시간 초과로 끝 | 둘째 더블 탭은 그룹에 SIGINT, Esc는 그룹에 SIGTERM, 시간 초과는 `arecord -d` | M0 · M1 |
| WAV 확정(길이 0이면 끝) | `tars-dictate`가 머리를 실제 길이로 다시 쓴다(결정 7). 0바이트면 exit 2 | M0 |
| 전사 API(실패하면 알림만) | `curl` multipart. 실패하면 exit 4, 표준 출력과 기록이 빈다 | M0 |
| 오디오 삭제 | `/tmp`의 WAV를 `trap EXIT`가 지운다. 죽은 실행이 남긴 것은 다음 실행이 지운다 | M0 |
| 정리 API(실패하면 원문) | `curl` chat/completions · 길이 가드 | M2 |
| 대상 앱 활성화 · 클립보드 → ⌘V → 복원 | 없다. terminal이 그 패널의 PTY에 직접 쓴다 — 클립보드를 안 만지므로 복원 문제가 없다 | M1 |
| 기록 저장 | `/config/dictation.jsonl`에 한 줄. 표준 출력보다 먼저 쓴다 | M0 |

Voxio의 불변식 둘 중 첫째("전사가 성공한 순간부터 원문은 반드시 기록에 들어간다")는 M0부터 지켜진다 — `tars-dictate`가 기록을 쓴 뒤에
표준 출력을 낸다. 둘째("말하세요" 신호는 마이크가 실제로 살아난 뒤에만)는 TARS에 그 신호가 따로 없다. `arecord`는 장치를 열자마자
받고, Voxio가 이 판정을 만든 이유인 블루투스가 TARS에 없다(AU 비목표 1). 남는 틈은 위험 1이다.

## 결정

### 결정 1 — 자리 나누기: terminal은 트리거 · 상태 · 삽입, 게스트 프로그램 하나가 녹음 · 전사 · 기록

lead의 틀 그대로다. terminal이 오른쪽 Cmd 두 번에 `tars-dictate`를 fork하고, 표준 출력을 파이프로 읽어 EOF에 그 패널에 붙여 넣는다.
녹음을 끝내는 것과 취소는 시그널이다(결정 6).

| 후보 | 왜 아닌가 |
|---|---|
| (a) terminal이 트리거 · 삽입, `tars-dictate`가 나머지 | 고른 것. 사람이 셸에서 `tars-dictate`를 직접 쳐도 같은 일을 하므로 M0만으로 쓸 수 있고, 게이트가 terminal 없이 파이프라인 전부를 본다 |
| (b) terminal이 Zig로 전부(`std.http` · TLS · multipart) | terminal은 화면을 그리는 프로세스다. 네트워크와 녹음을 그 안에 들이면 poll 루프에 블록하는 일이 둘 생기고, TLS의 인증 기관 · HTTP 갈래를 우리가 짠다(`project_write_or_reuse` 기준 둘 다 아니다) |
| (c) `init`이 한다 | PID 1이 네트워크를 기다릴 이유가 없다(`feedback_boot_never_blocks`). 트리거는 어차피 terminal에서 온다 |
| (d) 감독 목록의 데몬 하나(services.d)와 소켓 | 상태가 둘로 늘고(데몬과 terminal) 데몬이 늘 떠 있다. 한 번 말하고 끝나는 일에 맞지 않는다 |

terminal은 지금 PTY 셸 말고는 자식을 안 띄운다. fork하고 표준 출력을 poll에 넣는 자리가 M1에서 처음 생긴다 — `init`의 `audio.zig`
일꾼(fork · 안 기다림 · 거둘 때 결과를 읽음)이 같은 모양의 선례다.

### 결정 2 — `tars-dictate`는 bash 스크립트다: 순서와 갈래는 우리 것, 소리 · HTTP · JSON은 남의 것

`kernel/dictation/tars-dictate`(303줄, 대부분 주석)가 initrd의 `/usr/bin/tars-dictate`로 간다. `arecord` · `curl` · `jq`는 게스트에 이미
있다(`kernel/guest_tools.sh`). 새로 싣는 바이너리가 없다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) bash + `arecord` + `curl` + `jq` | 고른 것 |
| (b) Zig 실행 파일(`tars-install` · `tars-service`처럼 `init/`에서 빌드) | 우리 몫의 순수한 부분이 둘뿐이다 — 무음 판정과 제어 문자 지우기. 무음 판정은 "글자나 숫자가 하나라도 있는가"이고 한글이 글자여야 하는데, Zig 표준 라이브러리에 유니코드 범주 표가 없다(직접 표를 들여야 한다). `jq`의 정규식(Oniguruma)은 `\p{L}` · `\p{N}`을 안다(실측 6). 나머지는 프로세스 배관이고 HTTP · TLS · multipart는 `curl`의 일이다 |
| (c) 게스트에 python · perl을 들인다 | `feedback_scripting_runtimes` — 들인다면 넷을 한 묶음으로. 지금 필요가 없다 |

Voxio가 호스트 검사로 못 박은 것(파이프라인 갈래 34 · 클라이언트 26 · 무음 판정 · 제어 문자)은 여기서 체인이 진짜 프로세스로 본다 —
같은 프로그램을 stub 서버에 대고 열 갈래로 돌린다(결정 9). Zig와 호스트 검사의 값은 M1의 트리거 판정(Voxio의 `DoubleTapDetector` ·
`TriggerEventRouter`, 검사 43)에 몰려 있고, 그쪽은 terminal의 Zig다.

bash의 위험(따옴표 · 갈래 빠뜨림)은 `set -u`, 체인 검사 1의 `bash -n`, 그리고 mutation 일곱이 막는다(M0 plan 확정 7).

### 결정 3 — 설정은 `/config/dictation.conf`다. `tars.conf`에 키를 안 더한다

lead의 틀은 `tars.conf`의 키 몇이었다. 바로잡는다(전제 2).

| 후보 | 왜 아닌가 |
|---|---|
| (a) `/config/dictation.conf`, `tars-dictate`가 실행마다 읽는다 | 고른 것 |
| (b) `tars.conf`의 키 | 그 파일은 `init`이 부팅에 읽어 argv로 terminal에 넘기는 설정이다(`Edit and reboot to apply`). 전사 주소 · 모델 · 언어를 쓰는 것은 `tars-dictate` 하나라 `init`과 terminal이 나를 뿐이고, 바꾸면 재부팅해야 한다. seed가 이미 48줄이라 게스트 화면 47줄을 넘고 `config` 체인 25번째 줄 검사가 걸려 있다(lessons 이월 숙제). argv 칸이 늘면 CB-M0처럼 `[9:null]` 자리를 다 고친다 |
| (c) 환경 변수 | 프로세스가 태어날 때 정해진다. 떠 있는 terminal이 바뀐 값을 못 본다 |

문법은 `tars.conf`와 같다 — `#` 주석, 첫 `=`에서 나누고 양쪽 공백을 뗀다, 모르는 키와 틀린 값은 한 줄 경고하고 기본값에 머문다.
`/config`에 도구가 자기 파일을 읽는 선례가 이미 여럿이다(`wpa_supplicant.conf` · `chrony.d/` · `nftables.d/` · `gitconfig` · `vimrc`).

키는 M0에 넷, M2에 셋이다. 기본값이 Voxio의 것이고 대부분의 사람은 파일을 안 만든다. seed하지 않는다 — seed는 `init`이 쓰는 것이라
그것 하나 때문에 `init`을 고치게 되고, 기본값이 스크립트와 seed 두 자리에 적힌다. 무엇을 적을 수 있는지는 `tars-dictate -h`와
running-tars.md가 말한다.

| 키 | 기본값 | Voxio D16 | milestone |
|---|---|---|---|
| `transcribe_url` | `https://api.groq.com/openai/v1/audio/transcriptions` | `transcription.endpoint` | M0 |
| `transcribe_model` | `whisper-large-v3-turbo` | `transcription.model` | M0 |
| `language` | 빈 값(자동 감지) | `transcription.language` — Voxio가 `ko`로 고정했다가 영어 발화가 한국어로 번역돼 꽂힌 뒤 비웠다(2026-09-18) | M0 |
| `max_seconds` | 300(1 ~ 600) | `trigger.maxRecordingSec` | M0 |
| `cleanup` | `on` | `cleanup.enabled` | M2 |
| `cleanup_url` | `https://api.groq.com/openai/v1/chat/completions` | `cleanup.endpoint` | M2 |
| `cleanup_model` | `qwen/qwen3.8-27b` | `cleanup.model`(Voxio V7이 정했다) | M2 |

게이트에는 이 파일이 결정적이다 — `transcribe_url`로 stub을 가리키고, 경로로 stub의 답을 고른다.

### 결정 4 — API 키는 `/config/groq.key` 한 파일(또는 `GROQ_API_KEY`). 사람이 쓰고 seed하지 않는다

Voxio D14의 Keychain 자리다. 앞뒤 공백 · 개행을 떼고, 비면 "키가 없다"(exit 3)로 마이크를 열기 전에 끝난다 — 30초를 말한 뒤에
알게 하지 않는다(Voxio 3절의 사전 점검). 환경 변수가 먼저다(Voxio D14와 같다, 개발할 때 파일을 안 고치고 바꿔 보는 길).

키는 `curl -K -`의 설정으로 표준 입력에 실어 보낸다. 명령줄에 두면 `/proc/<pid>/cmdline`으로 보인다. 그 설정 문법에서 따옴표와
역슬래시가 뜻을 가지므로 키의 글자를 `[A-Za-z0-9._~+/=-]`로 좁힌다(Groq 키는 `gsk_`로 시작하는 영숫자다).

평문 파일이다. Voxio의 Keychain만큼 지키지 못한다 — 위험 6.

### 결정 5 — 기록은 `/config/dictation.jsonl`, 전사가 성공한 것만, 표준 출력보다 먼저

Voxio D9 그대로 원문과 넣은 것을 나란히 남기고 오디오는 안 남긴다. SQLite 대신 JSON Lines다 — 한 줄이 한 발화이고 `jq`가 짓고
`jq` · `tail`로 읽는다(`tail -n 5 /config/dictation.jsonl | jq -r .inserted`).

```
{"at":"2026-10-06T02:17:33Z","raw":"안녕하세요 vd0-dictated","cleaned":null,"inserted":"안녕하세요 vd0-dictated","audio_ms":1896,"latency_ms":177}
```

| 칸 | 뜻 | Voxio 스키마 |
|---|---|---|
| `at` | UTC ISO 8601(`jq`의 `now \| todate`) | `created_at` |
| `raw` | 받은 그대로(앞뒤 공백만 뗀) — 제어 문자도 JSON 이스케이프로 남는다 | `raw_text` |
| `cleaned` | M2의 정리본. 끄거나 실패하면 null | `cleaned_text` |
| `inserted` | 표준 출력으로 낸 것(제어 문자를 지운 것) | `inserted_text` |
| `audio_ms` · `latency_ms` | 녹음 길이, 녹음이 끝나서 출력까지 | 같다 |

`target_bundle_id` · `insert_result`는 없다. 넣는 것은 terminal이고(M1), PTY에 쓰는 일은 실패가 사실상 없다. 무음 · 실패 · 취소는 한 줄도
안 남는다(Voxio와 같다 — 남길 텍스트가 없다). `/config`가 안 붙었으면 안 쓴다 — 그 자리는 RAM 위의 빈 디렉터리라 끌 때 사라지고,
그것을 기록이라 부르지 않는다. 설정 파티션이 1GiB라(`disk.zig`의 `SFDISK_SCRIPT`) 한 줄 200바이트 남짓이 쌓여도 회전은 필요 없다(비목표 13).

lead의 틀은 기록을 M2에 두었다. M0으로 옮긴다(전제 3) — 불변식 1이 첫 milestone부터 지켜져야 M1의 삽입이 실패해도 말한 것이 남고,
`jq` 한 번과 `printf` 한 줄이라 M0의 크기가 거의 안 는다.

### 결정 6 — 시그널은 프로세스 그룹으로, 종료 코드가 terminal과의 계약이다

| 시그널 | 녹음 중 | 그 뒤(전사 · 기록) |
|---|---|---|
| SIGINT | 녹음을 끝내고 전사로 간다 | 취소, exit 130 |
| SIGTERM | 취소 — API를 안 부르고 오디오를 지운다, exit 143 | 취소, exit 143 |

그룹으로 받는 것이 셸의 Ctrl+C와 같은 모양이다 — tty는 앞의 작업 그룹 전체(bash와 `arecord`)에 보낸다. `arecord`가 그 시그널을
직접 받아 끝나고, bash는 앞에서 돌던 `arecord`가 끝난 뒤에 trap을 돌린다(실측 7). terminal(M1)은 자식을 `setpgid`로 제 그룹에 두고
`kill(-pgid, …)`로 보낸다. 스크립트가 `arecord`에 시그널을 다시 보내는 모양(전달)은 안 고른다 — 그룹으로 이미 받은 `arecord`가 둘째를
받는다.

| 종료 코드 | 뜻 | M1의 terminal이 할 일(제안) |
|---|---|---|
| 0 | 표준 출력에 넣을 글자가 있다 | 그 패널에 붙여 넣는다 |
| 1 | 녹음을 못 했다(장치) | 상태 줄에 알린다 |
| 2 | 넣을 것이 없다(0바이트 · 무음 전사) | 조용히 끝 |
| 3 | API 키가 없다 | 상태 줄에 알린다(설정 문제) |
| 4 | 전사 실패(네트워크 · HTTP · 응답에 text가 없다) | 상태 줄에 알린다 |
| 64 | 인자가 틀렸다 | — |
| 130 · 143 | 취소됐다 | 조용히 끝 |

M1이 정한 실제 값 — 0 넣는다(`insert` 줄), 1 `NO MIC`, 2 · 130 · 143 조용, 3 `NO KEY`, 4 · 64 · 127(`execve` 실패) · 시그널 · 64KB 넘음
`FAILED`. 취소 중(`cancelling`)이었으면 무엇으로 끝났든 조용하다. 그리고 M0의 표준 에러 두 줄(`tars-dictate: recording; ` ·
`tars-dictate: recording stopped `)이 terminal과의 계약이 됐다 — M1이 파이프로 받아 단계를 옮기고 시리얼에 그대로 다시 찍는다. M0의
`tars-dictate`를 고치는 사람은 그 두 줄의 글자를 안 바꾼다.

표준 에러는 사람이 읽는 줄(`tars-dictate: …`)이고 받아 적은 글자는 안 찍는다 — 길이와 시간만 찍는다(Voxio `69aebc9`의 "로그에 말한
내용을 평문으로 남기지 않는다"). 표준 출력은 글자만이고 끝에 개행을 안 붙인다(끝의 개행은 Enter다). 표준 출력이 tty면(사람이 셸에서
쳤다) 개행을 하나 준다.

### 결정 7 — WAV 머리는 `tars-dictate`가 실제 길이로 다시 쓴다

`arecord -d 300`은 시작할 때 머리에 300초 분량(9,600,000바이트)을 적고 끝날 때 고친다. SIGINT로 멈추면 거의 늘 못 고친다 — 스물네 판 중
스물하나가 `pcm_read:2272: read error: Interrupted system call`을 찍고 머리를 그대로 둔 채 끝났다(실측 4). 문구로 보아 읽기 도중에 시그널을
받은 판이 그 자리에서 나가는 것이다. 샘플은 멀쩡하지만 머리가 틀린 WAV를 받아 줄지는 서버에 달렸다. 형식이 우리가 고른 것(16kHz 모노 16비트 PCM)이므로 머리
44바이트를 통째로 다시 짓는다. 게스트에 `dd`가 없어서 `printf`로 머리를 쓰고 `tail -c +45`로 샘플을 이어 새 파일을 만든다.

lead의 틀("두 번째 트리거는 시그널로 녹음을 끝낸다")에 숨어 있던 비용이다(전제 4). Voxio에는 없는 문제다 — 녹음을 자기 코드
(`AVCaptureSession` + `WavWriter`)로 했다.

### 결정 8 — initrd가 인증 기관 목록을 싣는다(sysroot의 ca-certificates로 짓는다)

게스트의 `curl`은 TLS 라이브러리(`libssl`)를 링크하지만 무엇을 믿을지가 initrd에 없다. libcurl이 컴파일 타임에 박아 둔 자리가
`/etc/ssl/certs/ca-certificates.crt`이고 그 파일이 없으니 https는 전부 `curl: (77) error setting certificate file`로 죽는다(실측 1). lead의
틀은 "TLS가 붙은 curl이 있다"였다 — 반만 맞다(전제 1). Groq는 https라 이것이 없으면 M0을 실기에서 한 번도 못 쓴다.

| 후보 | 왜 아닌가 |
|---|---|
| (a) sysroot에 `ca-certificates`(Architecture: all)를 받고 `make_initrd.sh`가 mozilla 인증서 150장을 이어 붙인다 | 고른 것. Debian의 `update-ca-certificates`가 기본 설정으로 하는 일과 같다(끝에 개행이 없는 파일 뒤에 개행까지) |
| (b) 컨테이너 자신의 `/etc/ssl/certs/ca-certificates.crt`를 복사한다 | 그 파일은 152장이다 — OrbStack이 넣은 개발용 인증 기관 둘(`OrbStack Development Root CA` · `Caddy Local Authority - 2026 ECC Root`)이 섞여 있다(실측 2). 게스트가 믿을 이유가 없다. 출처를 sysroot 하나로 두는 TS 결정 10의 값이 여기서 드러났다 |
| (c) `curl -k` | 검증을 끈다. API 키가 실린 요청이다 |
| (d) 게스트 `curl`에 `--cacert`로 우리 파일 하나 | (a)와 같은 파일을 다른 자리에 둘 뿐이고, 사람이 치는 `curl https://…`는 여전히 실패한다 |

비용. Dockerfile에 패키지 하나(이미지 굽기 30초), initrd에 224,449바이트 파일 하나(gzip 뒤 initrd가 135KB 안팎 는다 — 실측 10), 새 라이브러리 0개.
목록은 이미지를 다시 구울 때 Debian의 판으로 바뀐다.

### 결정 9 — 게이트는 새 체인 `dictation/check.sh`(스물한번째) 하나, 부팅 하나, 판정은 stub이 받은 바이트

AU 체인의 마이크 수법과 net 체인의 guestfwd를 합친다.

```
컨테이너 feed.raw(1234, 1234) ─ file 플러그인 infile ─▶ QEMU hda-micro ─▶ 게스트 arecord(plug → dsnoop, 16kHz 모노)
게스트 curl ─▶ 10.0.2.100:8080 ─ guestfwd cmd(연결마다) ─▶ 컨테이너 perl stub.pl ─▶ stub.log(머리 · 칸 · 샘플)
게스트 curl ─▶ 10.0.2.2:45492 ─ SLIRP ─▶ 컨테이너 openssl s_server(자기 서명) — 인증 기관 목록을 읽는가
```

- 게스트 쪽은 설정 디스크의 `services.d/probe`(= `dictation/probe.sh`)다. 사람이 셸에서 하는 일(`/config/dictation.conf`를 고치고
  `tars-dictate`를 치고 Ctrl+C)을 열 갈래로 하고 `dictate-probe:` 줄을 찍은 뒤 `kill -TERM 1`로 끈다. Ctrl+C는 `set -m`으로 제 그룹에
  띄운 `tars-dictate`에 `kill -INT -- -pgid`다(실측 7). 게이트는 게스트에 한 글자도 안 치고 monitor를 안 쓴다.
- stub은 경로의 첫 마디로 답을 고른다(`/ok` · `/ctrl` · `/blank` · `/notext` · `/fail` = 429). 둘째 마디가 갈래 이름이라 stub 로그에서
  요청을 가른다. 받은 WAV의 머리 · 칸(`file` · `model` · `response_format` · `language`) · 샘플의 최빈값과 그 수를 한 줄에 적는다.
- 마이크의 상수는 두 채널이 같다(1234). `plug`가 스테레오를 모노로 접을 때 왼쪽만 가져가는데(실측 3) 그 규칙은 alsa-lib의 것이라
  체인이 기대지 않는다.
- 기록은 끈 뒤에 `debugfs`로 꺼낸다(`project_seeding_a_config_disk`).

검사 열셋이다. 표는 M0 plan 확정 5에 있다. 요지 — 녹음이 마이크를 지나 API에 닿는다(샘플이 전부 1234, 16kHz 모노, 머리가 길이와 같다) ·
설정 셋이 요청에 실린다 · SIGTERM은 API를 안 부른다 · 키가 없으면 2초 안에 녹음 없이 끝난다 · 429 · 무음 · 제어 문자 · text 없음 ·
모르는 키 · 요청은 여덟 · 기록은 다섯.

lead의 틀은 "화면(`wait_for_screen`)에 삽입된 글자가 보이는지"였다 — 그것은 terminal이 넣는 M1의 판정이다. M0의 체인은 화면을 안 본다(전제 9).

### 결정 10 — 트리거는 오른쪽 Cmd 자리의 더블 탭, 판정은 terminal의 Zig에(M1)

Voxio D6 그대로 시작과 끝을 같은 제스처로 둔다. evdev 코드는 `handleKey` 맨 앞의 자판 맞바꿈 뒤 `KEY_RIGHTMETA`다 — Apple 자판은
오른쪽 Cmd, PC 자판(`keyboard=pc`)은 오른쪽 Alt가 그 자리다. 둘 다 "스페이스 오른쪽의 Cmd 자리"이고 Voxio가 고른 오른쪽 ⌘ ·
오른쪽 ⌥와 같은 손 모양이다. 판정 창은 Voxio 기본값 300ms다(`TAP_MAX_US`와 같은 크기).

Voxio D6의 함정 셋이 evdev에서는 이렇다(M1 plan이 코드로 못 박는다).

| Voxio의 함정 | evdev에서 | M1에서 |
|---|---|---|
| 1. 같은 down이 다시 온다(`.flagsChanged` 재전달) | 커널 입력 코어는 상태가 바뀔 때만 1을 보내고, 누른 채면 자동 반복 2를 보낸다. 모양이 다를 뿐 있다 | `Tap.down`이 이미 눌린 키의 2를 무시한다(HI-M3). 같은 구조를 쓴다 |
| 2. 놓친 key-up(탭 비활성화) | 읽기가 밀려 커널 버퍼가 넘치면 `SYN_DROPPED`가 오고 그 사이의 이벤트는 사라진다. 지금 키보드 경로는 `EV_KEY` 말고는 안 보고(`readKeys`) `SYN_DROPPED`를 모른다 — 수정 키 전부의 오래된 구멍이다 | `SYN_DROPPED`를 보면 탭 판정을 비운다(Voxio의 `recoverFromDroppedEvents`). 포인터 · 터치패드는 이미 그렇게 한다 |
| 3. 키 없이 끝나는 길(시간 초과 · 실패) 뒤에 판정기가 "녹음 중"에 남는다 | 있다 — `max_seconds` · 키 없음 · 전사 실패로 `tars-dictate`가 스스로 끝난다 | "녹음 중"을 키 순서가 아니라 자식이 살아 있는가에서 읽는다. 자식의 표준 출력 EOF가 유일하게 상태를 되돌리는 자리다 |

Voxio의 나머지 규칙도 옮긴다 — 다른 키가 끼면 판정을 버리고(`Tap.consumed`가 이미 그 일을 한다), 다른 수정 키가 눌려 있으면 발동하지
않는다(`State`의 수정 키 비트로 본다).

> M1이 정한 것(2026-10-06, `-vd-m1.md` 확정 1 ~ 3). 판정기는 순수 모듈 `dictation.zig`의 `DoubleTap`이고 "녹음 중"을 들지 않는다 — 두 번
> 눌렸다는 사실만 말하고, 시작인지 끝인지는 자식의 단계가 정한다(`onTap`). 단계는 넷 — `starting`(띄움) · `recording`(자식의 표준 에러
> `recording; …`) · `transcribing`(둘째 더블 탭의 SIGINT, 또는 자식의 `recording stopped …`) · `cancelling`(Esc의 SIGTERM). `starting` ·
> `transcribing` · `cancelling`의 더블 탭은 무시한다(`ignored` 줄) — `starting`을 무시하는 근거는 M0의 틈이다: `tars-dictate`가 `arecord`
> 전에 받은 SIGINT를 기억만 하고 상한까지 녹음한다(M2가 함께 본다). 함정 2는 `readKeys`가 `SYN_DROPPED`에서 판정을 비운다. 자리는
> `handleKey` 0번 단계의 수정키 `switch`(`KEY_RIGHTMETA` 갈래)라 모든 모드 · 한글 조합 중에도 같다. `tars.conf` 키는 없다. 자식은
> `pipe2` 둘(표준 출력 · 표준 에러) → `fork` → `setpgid`(양쪽) → `execve`이고, terminal이 이미 libc를 링크하므로 `std.c`로 부른다
> (`project_zig_c_uapi_rule`의 "libc 없이"는 `init`의 길이다 — `close_range` 하나만 `std.os.linux`). poll에 두 칸, 두 파이프의 EOF에
> `waitpid`. terminal은 녹음 시간을 안 센다 — 상한은 `max_seconds`가 지키고 그 줄로 안다.

### 결정 11 — 상태는 상태 줄의 꼬리, 삽입은 붙여 넣기 경로(M1)

- 상태 줄 꼬리에 녹음 중과 처리 중을 가르는 칸 하나(`COPY` · 워크스페이스 칸과 같은 자리). 글자와 색은 M1 plan이 정한다. 오버레이
  창 · 레벨 미터는 비목표 2다.
- 삽입은 트리거를 누른 순간의 패널(Voxio D8 1번 — 누를 때 기억하고 거기에 넣는다)에 `pasteParts`로 쓴다. 자식이 모드 2004를 켰으면
  bracketed paste다. 그 패널이 그사이 닫혔으면 넣지 않는다(기록에 있다). 클립보드는 안 만진다.
- 제어 문자는 `tars-dictate`가 이미 지웠다. terminal이 PTY 앞에서 한 번 더 지울지(방어 한 겹)는 M1 plan이 정한다 — Voxio는 넣는 자리에
  걸었다.
- Esc는 녹음 중에만 취소이고 그때는 PTY로 안 보낸다(Voxio D11a — 취소한 Esc가 뒤의 프로그램까지 가면 안 된다). EL의 `esc_latin`과의
  순서는 M1 plan이 정한다.

> M1이 정한 것(2026-10-06, 확정 3 ~ 5). 상태 줄 꼬리의 맨 끝 칸 — `REC`(`starting` · `recording`) · `WAIT`(`transcribing`) · `NO MIC` ·
> `NO KEY` · `FAILED` · `PASSWORD` · `NO PANE`, 색은 전용 `STATUS_DICT` = `0xF07070`(`status> dict ink=`로 센다), `MAX_LEN` 46 → 56. 알림은
> 무언가를 한 다음 키에 사라진다(수정키만 누르고 뗀 배치는 안 센다 — 세면 더블 탭의 마지막 뗌이 방금 뜬 `PASSWORD`를 지운다). 시간으로
> 지우지 않는다. 대상은 두 번을 누른 순간의 포커스 패널 — 그 패널 셸의 pid로 든다(닫히면 `NO PANE`). 넣는 순서 — 패널 → 비밀번호(위험 2)
> → `dictation.sanitize`(terminal이 PTY 앞에서 한 번 더 거른다 — 돌이킬 수 없는 유일한 자리) → 그 패널이 포커스이고 한글 조합 중이면
> 먼저 확정 → `pasteParts`. Esc는 `handleKey` 1.3번 단계 — `Cmd+V` · find · copy 표 · 한글 층보다 앞이라 copy mode · 조합 중인 글자 ·
> `esc_latin`이 그대로다. 수정키가 있는 Esc는 평소의 길이다.

### 결정 12 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가 한다

AU 결정 6과 같다. plan은 milestone마다 그 시점에 Opus 서브에이전트가 쓰고, 코드를 저장소 밖 사본에서 컴파일 · 체인 · mutation까지
돌린 뒤 넘긴다. M0의 구현은 Sonnet을 권한다 — Zig가 한 줄도 없고 새 파일 넷은 사본을 복사하고 편집 다섯은 글자 그대로 넣는다. M1은
terminal의 Zig(트리거 판정 · fork · poll · 상태 줄)라 plan은 Opus가 쓰고 구현자는 그 plan이 정한다.

## lead의 전제를 바로잡은 것

1. 게스트의 `curl`은 TLS 라이브러리만 있고 인증 기관 목록이 없다. https는 전부 77로 죽는다(실측 1). M0이 sysroot의 ca-certificates로
   목록을 싣는다(결정 8).
2. 설정은 `tars.conf`의 키가 아니라 `/config/dictation.conf`다(결정 3). 쓰는 것이 `tars-dictate` 하나이고, 재부팅 없이 다음 실행부터
   맞고, seed와 argv를 안 건드린다.
3. 기록을 M2에서 M0으로 옮겼다(결정 5). 불변식 1이 첫 milestone부터 지켜진다.
4. `arecord`는 SIGINT에 WAV 머리를 거의 늘 못 고친다(실측 4). `tars-dictate`가 다시 쓴다(결정 7).
5. 시그널은 `tars-dictate`의 pid가 아니라 그 프로세스 그룹에 보낸다(결정 6). 셸의 Ctrl+C와 같은 모양이고 `arecord`가 한 번만 받는다.
6. M0은 포트를 monitor로 안 쓴다. 45492는 TLS 상대(`openssl s_server`)가 컨테이너에서 듣는 번호다. M1이 타이핑을 하면 monitor는
   45493부터다.
7. `arecord -f S16_LE -r 16000 -c 1`은 기본 장치(`plug` → `dsnoop`)로 돈다 — 상수가 값까지 같게 16kHz 모노로 왔다(실측 3). 걱정할 것이
   아니었다.
8. 게스트의 `jq`는 1.7이고 `trim`이 없다(실측 6). `tars-dictate`가 `sub`로 자기 `strip`을 정의한다.
9. M0의 체인은 화면을 안 본다. "삽입된 글자가 화면에 보인다"는 terminal이 넣는 M1의 판정이다(결정 9).

## Voxio의 결정 D1 ~ D16을 어디로 옮겼나

| Voxio | 무엇 | TARS |
|---|---|---|
| D1 | 메뉴바 에이전트 하나 | 없다. 게스트 프로그램 하나와 terminal의 기능이다. 메뉴바 · Dock · URL 스킴은 비목표 5 |
| D2 | 식별자 · 이름 | 이름 `tars-dictate`, 파일 셋(`groq.key` · `dictation.conf` · `dictation.jsonl`) |
| D3 | self-signed 서명 · `/Applications` 한 벌 | 해당 없음(TCC가 없다). 비목표 5 |
| D4 | SwiftPM, 외부 의존 0 | 반대로 간다 — 남의 도구 셋(`arecord` · `curl` · `jq`)이고 셋 다 이미 게스트에 있다. 새로 싣는 것은 인증 기관 목록뿐(결정 8) |
| D5 | Core · Mac · App 경계, 실패 갈래를 네트워크 없이 시험 | `tars-dictate`(파이프라인) · terminal(트리거 · 삽입) · 게이트 stub. 실패 갈래 시험은 stub 체인이 이어받는다(결정 2 · 9) |
| D6 | 오른쪽 수식키 더블 탭, hold 모드, 함정 셋 | 더블 탭은 M1(결정 10). hold는 비목표 3 |
| D7 | 외부 API만 | 그대로. 로컬 모델은 비목표 1 |
| D8 | 클립보드 경유 삽입 · 복원 · 비밀번호 칸 | 바뀐다 — PTY에 직접(결정 11), 클립보드를 안 만진다. 포커스 조회 · 비밀번호 칸 판정은 비목표 8(위험 2) |
| D9 | 기록은 남기고 오디오는 안 남긴다 | `/config/dictation.jsonl`(결정 5), 오디오는 `/tmp`에서 지운다 |
| D10 | 마이크 우선순위 목록 | 비목표 6. AU 결정 7 · 8의 기본 장치(USB 마이크 · 내장 DMIC · 장치 0)가 대신한다 |
| D10a | 세션마다 새 레코더 | 저절로 — `arecord`가 실행마다 새 프로세스다 |
| D10b | 살아남 판정 · 블루투스 꼬리 대기 | 없다. 블루투스가 없다(AU 비목표 1). 남는 틈은 위험 1, 비목표 7 |
| D11 | 설정 UI | `/config/dictation.conf`와 `tars-dictate -h`(결정 3) |
| D11a | 녹음 오버레이 · Esc 취소 | 상태 줄 꼬리와 Esc(결정 11, M1). 오버레이 창 · 레벨 미터는 비목표 2 |
| D11b | 알림음 | 비목표 4 |
| D12 | LLM 정리 · 길이 가드 · 실패하면 원문 | M2. 프롬프트 · 모델 · 0.5 · 1500ms를 Voxio의 값 그대로 가져온다 |
| D13 | 권한 둘 | 해당 없음(root, `/dev/snd`는 `audio` 그룹) |
| D14 | Keychain, `GROQ_API_KEY` 우선 | `/config/groq.key`, `GROQ_API_KEY` 우선(결정 4) |
| D15 | 실행 컨텍스트 셋 | terminal의 poll 루프 하나와 자식 프로세스 하나. 스레드가 없다 |
| D16 | 설정 키 스물넷 | 일곱(결정 3의 표). 나머지는 비목표 · 결정 · 상수로 간다 — `meta.settingsVersion`은 옮길 설정이 없어 필요 없고, 알림음 · Dock · 로그인 · 오버레이 둘은 비목표, `trigger.key` · `mode` · `doubleTapWindowMs`는 M1의 상수(Cmd 자리 · toggle · 300ms), `audio.preferredDevices`는 AU의 기본 장치, `transcription.prompt`는 비목표 12, `timeoutSec`(30) · `cleanup.timeoutMs`(1500) · `minLengthRatio`(0.5) · `systemPrompt`는 상수, `insertion.restoreDelayMs`는 클립보드가 없어 필요 없고, `history.retentionDays`는 비목표 13 |

## 검증

호스트 검사는 없다 — M0에 우리가 짠 Zig 코드가 한 줄도 없다. 판정은 결정 9의 체인과 regression 다섯이다. 사본에서 돈 값(M0 plan 확정 6 · 8).

| 체인 | 왜 | 사본의 결과 |
|---|---|---|
| `dictation`(새) | M0의 모든 것 | 초록. 캐시를 지운 첫 판 1분 59초, 데운 판 33 · 34 · 35초 |
| `tools` | initrd의 `/usr/bin`에 스크립트 하나가 는다 | 66 · 61초, `all 92 tools` 그대로 |
| `net` | guestfwd를 쓰는 선례. 같은 이미지의 `curl` | 170 · 171초 |
| `audio` | 같은 HDA · file 플러그인 수법 | 44 · 43초 |
| `boot` | limine이 BIOS로 initrd를 읽는다. initrd가 135KB 안팎 커졌다 | 25 · 24초 |
| `install` | initrd가 바뀌면 부팅 7의 창(lessons PD-3) | 109 · 108초, `init waited 1700ms` 두 번(HEAD와 같다) |

mutation 일곱을 아홉 판으로 두 번 돌렸고(주석을 고치기 전과 뒤) 두 번 다 전부 겨냥한 검사에서 빨갰다(M0 plan 확정 7). regression은 두 판씩이다.

## Milestone

### VD-M0 — 게스트 파이프라인(셸에서 친다)

결정 2 ~ 9. `devcontainer/Dockerfile` · `kernel/make_initrd.sh` · `check.sh`를 고치고 `kernel/dictation/tars-dictate` · `dictation/check.sh` ·
`dictation/probe.sh` · `dictation/stub.pl`을 새로 만든다. 7 files, +965. 우리 Zig 코드는 0줄이다. 루트 게이트가 스물한 체인이 된다.
plan은 `docs/plans/2026-10-06-tars-voice-dictation-vd-m0.md`.

### VD-M1 — terminal의 트리거 · 상태 · 삽입

했다(2026-10-06, `-vd-m1.md`). 정할 것 여섯의 답은 결정 10 · 11의 M1 문단과 위험 2 · 실측 11에 있다. 아래는 쓸 때의 글이다.

결정 10 · 11. terminal에 Zig가 들어가는 유일한 milestone이다. 정할 것.

1. 판정의 자리. 탭 판정은 순수 상태 기계로 `input.zig`(또는 새 파일)에 두고 호스트 검사로 Voxio의 검사(더블 탭 창 · 늦은 둘째 탭 · 다른 키 ·
   다른 수정 키 · 자동 반복 · `SYN_DROPPED`)를 옮긴다. `handleKey`의 분기 순서(find → copy 표 → 한글 층 → `chord()`) 어느 자리에 넣는지.
2. 자식. `main.zig`에서 fork · `setpgid` · 표준 출력 파이프 · `execve("/usr/bin/tars-dictate")`, poll에 파이프 하나, EOF에 `waitpid`와 종료 코드.
   표준 에러를 어디로 보낼지(상태 줄의 알림 재료가 될 수 있다).
3. 상태 줄의 글자 · 색과 알림(키 없음 · 실패)을 얼마나 보여 줄지.
4. 대상 패널과 그 패널이 닫힌 경우, 워크스페이스를 옮긴 경우.
5. Esc와 EL의 `esc_latin` · copy mode · find 프롬프트의 순서.
6. 게이트. 같은 stub · 마이크 수법에 타이핑(monitor 45493부터)을 더해 `wait_for_screen`으로 셸 프롬프트에 들어간 글자를 본다. 오른쪽 Cmd를
   QEMU `sendkey`로 보내는 이름(`meta_r`)과 300ms 안의 두 번을 재야 한다.

### VD-M2 — 정리 단계 · 실기 안내

결정 3의 `cleanup*` 키 셋과 Voxio D12. 전사 뒤에 chat/completions를 한 번(`curl --max-time 1.5`), 응답의 첫 choice, 바깥 따옴표 벗기기
(Voxio `stripWrappingQuotes`), 길이 가드(앞뒤 공백을 뗀 글자 수가 원문의 0.5 미만이면 버린다), 실패 · 시간 초과 · 가드면 원문. 기록의
`cleaned`가 채워진다. 프롬프트는 Voxio의 `defaultSystemPrompt` 그대로이고 요청 본문은 `jq --arg`로 짓는다(전사문이 사용자 메시지에
그대로). stub에 `/chat` 갈래 몇(정리본 · 요약 · 빈 답 · 500 · 느린 답)을 더한다. running-tars.md의 받아쓰기 절과 실기 확인(진짜 Groq ·
첫 요청 지연 · 위험 5)도 여기다.

M0와 M2를 나눈 이유. M0만으로 사람이 셸에서 쓸 수 있다(정리 없이 원문). 정리는 Voxio에서도 "부가 단계, 필수 경로 아님"이고 V9가 효과를
아직 못 쟀다. M1(트리거)이 M2보다 앞인 것은 사용자가 원한 제스처가 그쪽이기 때문이다.

## 위험

1. 살아남 판정이 없다. Voxio D10b는 "마이크가 실제로 소리를 내기 시작한 뒤에만 말하라고 알린다"였다. `arecord`는 장치를 열자마자 받고
   QEMU의 HDA에서 첫 샘플부터 상수였다. 실기의 HDA · DMIC도 같을 것으로 보지만 재지 않았다. SOF DMIC가 첫 몇백 ms를 0으로 내는 기계가
   있으면 첫 단어를 잃는다 — 실기에서 `arecord` 앞부분이 0인지 본다(running-tars.md).
2. 비밀번호 프롬프트. terminal이 PTY에 직접 넣으므로 `sudo` · `ssh`가 echo를 끈 프롬프트에도 글자가 들어간다(Enter는 안 붙는다). Voxio는
   AX로 비밀번호 칸을 보고 마이크를 안 열었다(V10). TARS에서 그 판정은 tty의 termios다 — M1이 정했다: `ECHO`가 꺼졌는가가 아니라
   `ICANON`이 켜지고 `ECHO`가 꺼졌는가다. 셸의 줄 편집기(readline · zle · fish)와 vim은 둘을 함께 끄므로 `ECHO`만 보면 모든 셸
   프롬프트가 비밀번호다(사본의 fish 프롬프트가 `icanon=false echo=false`, `read -s`가 `icanon=true echo=false` — M1 plan 확정 9).
   vendored ghostty가 같은 판정을 쓴다. master에 `tcgetattr`를 하면 slave의 termios를 준다. 보는 때는 시작(마이크를 안 연다)과 넣기
   (말하는 사이에 `sudo`가 뜰 수 있다) 둘이고 상태 줄이 `PASSWORD`라 말한다. 못 보는 것 — 자기 편집기로 가리는 프롬프트(fish의
   `read -s`)에는 글자가 들어간다(Enter는 안 붙는다). lead의 "lead가 정할 것" 넷의 답 — 결정 3 · 5를 받는다, 21체인을 받는다, 위험 5의
   연결 비용은 실기에서 잰다.
3. bracketed paste가 꺼진 프로그램(`cat`, `read`)에서 Whisper가 준 글자 안의 개행은 줄 입력이다. 끝의 개행은 `tars-dictate`가 지운다.
4. Groq 무료 티어 — 분당 20 · 일 2,000 요청, 요청마다 최소 10초로 센다(Voxio 7절). 짧게 자주 쓰면 요청 수가 먼저 닿는다. 429는 exit 4와
   "too many requests"다. 게이트는 Groq를 절대 안 부른다(키도 바깥 길도 없다).
5. 첫 요청 지연. Voxio V12는 프로세스의 첫 요청(TLS 핸드셰이크 포함)이 4초, 그다음이 0.4초대였다. `tars-dictate`는 실행마다 새 `curl`이라
   매번 첫 요청이다 — DNS와 TLS를 매번 치른다. 실기에서 잰다. 크면 연결을 붙잡아 두는 상주 프로세스가 필요하다(결정 1의 (d)를 다시 연다).
6. 키가 평문이다. `/config`는 ext2 파티션(설치된 디스크의 p2 또는 USB 스틱)이고 그 스틱을 잃으면 키가 샌다. 키를 바꾸는 것이 처방이다.
7. TLS는 시계에 기댄다. 시계가 틀리면 인증서가 "아직 유효하지 않음"으로 60이 난다. TARS는 부팅에 RTC를 읽고 `net=dhcp`면 chronyd가 맞춘다.
8. 인증 기관 목록은 이미지를 구운 날의 Debian 판이다. 오래 안 구우면 낡는다.
9. 게이트의 오디오 시간과 게스트 시계가 다르다. `max_seconds=30` 녹음이 게스트 시계로 23초에 끝났다(M0 plan 확정 7의 mutation 4) — QEMU
   TCG의 오디오가 게스트 시계보다 빨리 샘플을 낸다. 판정은 바이트 수로 하므로 체인은 안 흔들리지만, M1에서 "녹음이 몇 초 걸렸다"를
   시간으로 판정하면 틀린다.

## 비목표

1. 로컬 모델(whisper.cpp). Voxio D7과 같은 이유다.
2. 녹음 오버레이 창 · 레벨 미터(Voxio D11a). 상태 줄 꼬리로 대신한다.
3. hold 모드(누르는 동안만 녹음, Voxio D6). 더블 탭 하나로 시작한다.
4. 알림음(Voxio D11b). Voxio가 시작음을 둔 이유는 블루투스 개통 지연(최대 2.5초)인데 TARS에 블루투스가 없고, 상태 줄이 신호다. 그리고
   시작음은 녹음에 함께 들어간다(Voxio V12 — 들어가도 전사가 안 더러워졌다는 것까지만 쟀다). `aplay`로 낼 수는 있다(AU) — 실기에서 상태 줄이
   눈에 안 들어오면 다시 연다.
5. 메뉴바 · Dock · URL 스킴 · 로그인 항목 · TCC · 서명 · Keychain(Voxio D1 · D3 · D13 · D14). 해당하는 것이 TARS에 없다.
6. 마이크 우선순위 목록(Voxio D10). AU의 기본 장치가 대신한다. 다른 장치를 쓰려면 `ALSA_CARD`(AU 결정 7).
7. 살아남 판정 · 블루투스 꼬리 대기(Voxio D10b). 위험 1.
8. 포커스 앱 조회 · 비밀번호 칸 판정(Voxio D8 · V10). 포커스 패널이 곧 대상이다. 위험 2.
9. Groq 밖 제공자의 UI. `transcribe_url` · `transcribe_model`로 OpenAI 호환 엔드포인트는 이미 바꿀 수 있다(Voxio 6절의 "프로바이더 확장").
10. 실시간 스트리밍 전사(Voxio 6절).
11. 기록을 고르는 UI · 최근 5건 다시 넣기(Voxio 메뉴의 ⌘1~⌘5). `tail` · `jq`로 본다.
12. `transcription.prompt`(고유명사 철자 힌트). 필요해지면 `dictation.conf`의 키 하나와 `--form-string` 한 줄이다.
13. 기록 보존 기간 · 회전. 설정 파티션이 1GiB이고 한 줄이 200바이트 남짓이다.

## 착수 전에 실측한 것

lead(Fable)가 AU를 열 때 잰 것은 그대로 인용한다 — 게스트에 TLS가 붙은 `curl` · `jq` · `bash` · `arecord`(AU)가 있다, 컨테이너에 python3이 없고
perl 5.40이 있다, 게이트는 `guestfwd=tcp:10.0.2.100:8080-cmd:…`로 바깥 없이 닫는다(net 체인), 삽입은 `dumpPaste` · `pasteParts`의 자리다,
트리거는 `input.zig`의 탭 판정이 선례다, `arecord` 16kHz는 안 쟀다, 키는 `/config`의 파일 하나, Groq 무료 티어는 게이트가 건드리지 않는다.

아래는 이 design을 쓰며 저장소 사본(`/tmp/run/vd0/repo/`, HEAD `52188ab`)과 따로 구운 이미지(`tars-devcontainer-vd0`)로 쟀다. 측정 파일은
`/tmp/run/vd0/meas/`(체인 로그 · 시리얼 로그 · regression · 측정용 체인 변형)와 `/tmp/run/vd0/mut/` · `mut_final/`(mutation 두 판)에 있다.

1. 인증 기관 목록. HEAD의 initrd에 `libcurl.so.4` · `libssl.so.3` · `libgnutls.so.30`이 있고 `/etc/ssl`이 없다. libcurl이 박아 둔 자리는
   `/etc/ssl/certs`와 `/etc/ssl/certs/ca-certificates.crt`(`strings`). 그 목록을 뺀 initrd로 게스트에서 `curl https://10.0.2.2:45492/`가
   `curl: (77) error setting certificate file: /etc/ssl/certs/ca-certificates.crt`였고, 목록을 넣은 initrd에서는 같은 명령이 `curl: (60) SSL
   certificate problem: self-signed certificate`였다. 같은 인증서를 `--cacert`로 주면 `s_server -www`의 상태 페이지까지 받았다.
2. ca-certificates. sysroot에 `apt-get download ca-certificates`(20250419, Architecture: all)를 풀면 `/usr/share/ca-certificates/mozilla/*.crt`
   150장이 있고 묶음은 없다(postinst가 짓는다). 이어 붙인 묶음이 224,449바이트 · `BEGIN CERTIFICATE` 150개다. 컨테이너의
   `/etc/ssl/certs/ca-certificates.crt`는 152개 — 더한 둘이 `/usr/local/share/ca-certificates/orbstack-root.crt`에서 온 OrbStack Development Root CA와
   Caddy Local Authority - 2026 ECC Root다. mozilla 파일 이름 목록은 둘이 같았다. 이미지 굽기 29.6초.
3. 16kHz 모노 녹음. 게스트의 `arecord -q -t wav -f S16_LE -r 16000 -c 1`(장치를 안 고른다)이 QEMU HDA(48kHz 스테레오) → `dsnoop` → `plug`를 지나
   16,000Hz 1채널 16비트 WAV를 썼다. 마이크에 (1234, 1234)를 넣으면 샘플 30,349개가 전부 1234였다. (3000, -5000)을 넣으면 전부 3000이었다 —
   `plug`가 스테레오를 모노로 접을 때 왼쪽 채널을 가져간다(평균이 아니다). `-d 1`은 정확히 32,000바이트이고 머리도 맞다.
4. `arecord`의 SIGINT. `-d 300`으로 녹음하다 0.7초 뒤 그룹에 SIGINT를 보내는 것을 열두 번씩 두 판 했다. 스물네 번 모두 exit 1이었고, 스물한
   번은 `arecord: pcm_read:2272: read error: Interrupted system call`을 찍고 머리를 300초 분량(9,600,000)으로 둔 채 끝났다. 세 번만 에러 없이
   머리를 고쳤다. 샘플은 늘 멀쩡했다.
5. 게스트에 `dd`가 없다(`cmp` · `tail` · `head` · `stat`은 있다). 머리를 다시 쓰는 것은 `printf`와 `tail -c +45`로 새 파일을 짓는다.
6. `jq`. 게스트의 `jq --version`이 `jq-1.7`이다. `trim`이 없어 `jq: error: trim/0 is not defined`로 컴파일부터 실패한다. `test("[\\p{L}\\p{N}]")`은
   한글 문장에서 참, `" ."`에서 거짓이다. `explode` · `implode`로 제어 문자를 고를 수 있다. `now | todate`는 `2026-10-06T…Z`다.
7. bash의 시그널. 비대화형 bash가 앞에서 돌리는 자식이 SIGINT를 스스로 처리하고 끝나면, 그 뒤에 bash의 INT trap이 돈다 — 녹음 중의
   Ctrl+C가 "녹음을 끝내고 전사로"가 되고, 둘째 Ctrl+C가 "취소"가 됐다(컨테이너의 bash로 쟀다 — 둘째 때 앞에 있던 것은 `sleep`이었다). 서비스처럼 tty 없이(`setsid`)
   도는 bash에서 `set -m` 뒤의 `&`가 제 그룹을 받고 `kill -INT -- -pid`가 그 그룹에 닿았다.
8. guestfwd의 `cmd:perl …/stub.pl …/stub.log`가 연결마다 새로 실행돼 HTTP 요청 하나를 읽고 답했다. `curl -F`의 칸 순서는 `file` · `model` ·
   `response_format` · `language`이고 파일 칸의 `Content-Type`은 `audio/wav`, 이름은 `tars-dictate.<pid>.wav`다.
9. 시간(게이트, TCG). 녹음이 끝나서 표준 출력까지 115 ~ 210ms(stub이 컨테이너에 있다, 판 넷). 키가 없는 실행이 21 ~ 23ms. 체인은 캐시를 지운 첫 판
   1분 59초, 데운 판 33 ~ 35초. 부팅에서 `kill -TERM 1`까지 21 ~ 25초.
10. initrd. 96,866,774 → 97,001,653바이트(+134,879, firmware 꼬리 포함). 주석을 고치기 전의 판은 +137,764였다 — cpio에 든 시각과 gzip 때문에 판마다 몇 KB 다르다. `tars-dictate` 14,897바이트.
11. 설정 파티션. `tars-install`이 만드는 p2가 1GiB다(`init/src/disk.zig`의 `SFDISK_SCRIPT`).
12. 키보드의 `SYN_DROPPED`. terminal의 `readKeys`는 `EV_KEY`가 아니면 건너뛴다 — 포인터(`pointer.zig`)와 터치패드(`touchpad.zig`)만
    `SYN_DROPPED`를 다룬다(결정 10의 함정 2).

13. (M1 planner) QEMU의 `sendkey meta_r`가 게스트의 `KEY_RIGHTMETA`(126)다. hold를 안 적으면 누른 시간이 7 ~ 23ms · 두 누름 사이가
    19 ~ 22ms로 사람 손과 다르다. `sendkey meta_r 80` 둘이면 누른 시간 78 ~ 83ms · 두 누름 사이 159 ~ 163ms(판 열넷) — 체인은 이쪽을 쓴다.
    QEMU가 뗌을 지연과 함께 입력 큐에 넣고 다음 `sendkey`가 그 뒤에 줄을 선다. master의 `tcgetattr`가 slave의 termios를 준다
    (`tty_mode_ioctl`이 master면 `tty->link`). 부팅 B가 monitor 45493을 쓴다(M0의 45492는 TLS 상대) — 새 체인은 45494부터.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜, VD-M0~M2)`로 고친다. milestone이 줄거나 늘면 그 사실을 한 줄로.
- `CLAUDE.md`의 완료 표에 한 줄. 예: "오른쪽 Cmd 두 번에 말한 것이 커서 자리에 들어간다 — Voxio를 옮겼다. 녹음 · 전사 · 기록은 게스트의
  bash 스크립트 `tars-dictate`(arecord · curl · jq), 트리거와 삽입은 terminal. 게이트는 perl stub과 HDA 마이크의 상수 — 스물한번째 체인
  `dictation/check.sh`".
- `docs/decisions/project_voice_dictation.md`를 만들고 `MEMORY.md`에 한 줄. 담을 것 — 자리 나누기, 설정이 `tars.conf`가 아닌 이유, 시그널
  그룹과 종료 코드의 계약, `arecord` 머리, 인증 기관 목록(OrbStack의 둘), Groq를 안 부르는 게이트.
- `docs/guides/lessons.md`. 포트 절에 "VD의 `dictation`은 45492를 TLS 상대(`openssl s_server`)로 쓰고 monitor를 안 쓴다". 로그 문구 절에
  `dictate-probe:` 줄들과 `tars-dictate:` 줄들(정본은 M0 plan "이 milestone이 끝나면"). 실측 절에 VD 몫 — 인증 기관 목록이 없던 것 · 컨테이너의
  묶음에 OrbStack 인증 기관이 섞인 것 · `arecord`의 SIGINT 머리 · `plug`의 모노는 왼쪽 · 게스트 `jq` 1.7에 `trim`이 없다 · 게스트에 `dd`가 없다 ·
  TCG의 오디오가 게스트 시계보다 빠르다. 핵심 파일 절의 게이트에 `dictation/check.sh` · `probe.sh` · `stub.pl`.
- `docs/guides/running-tars.md`에 받아쓰기 절. 사용자가 실기에서 할 것.

  ```
  printf '%s\n' 'gsk_…' > /config/groq.key      # 키. tars.conf에 net=dhcp가 있어야 한다
  tars-dictate                                  # 말하고 Ctrl+C. 받아 적은 글자가 나온다
  tail -n 5 /config/dictation.jsonl | jq -r .raw  # 기록
  tars-dictate -h                               # /config/dictation.conf에 적을 수 있는 키
  ```

  M1부터는 오른쪽 Cmd(PC 자판은 오른쪽 Alt)를 두 번. 첫 실행이 느리면 위험 5, `curl: (60)`이면 시계(위험 7), 첫 단어가 빠지면 위험 1을 적어
  알린다.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-10-05-tars-audio-devices-design.md` — `arecord`와 기본 장치(결정 3 · 7 · 8), 게이트의 마이크 수법(결정 5), VD와의 경계(비목표 4)
- `docs/specs/2026-09-13-tars-guest-network-design.md` — guestfwd로 바깥 없이 닫는 법(결정 7), `curl`을 들인 값(결정 10)
- `docs/specs/2026-10-04-tars-paste-ergonomics-design.md` — bracketed paste와 `pasteParts`(M1의 삽입)
- `docs/specs/2026-08-31-tars-hangul-input-design.md` — 탭 판정 `Tap`(M1의 트리거, 결정 8)
- `docs/specs/2026-09-02-tars-input-status-design.md` · `docs/specs/2026-10-03-tars-copy-indicator-design.md` — 상태 줄 꼬리(M1)
- `docs/decisions/project_write_or_reuse.md` · `feedback_boot_never_blocks.md` · `feedback_scripting_runtimes.md` · `project_seeding_a_config_disk.md` ·
  `project_gate_screen_echo.md`
- Voxio — `/Users/dp/Repository/Voxio/docs/ARCHITECTURE.md`(D1 ~ D16 · 3절 · 7절) · `docs/VERIFICATION.md` · `Sources/VoxioCore/`
