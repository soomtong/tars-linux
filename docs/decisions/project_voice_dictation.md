---
name: project_voice_dictation
description: Voxio(macOS 받아쓰기 앱)를 TARS로 옮겼다 — 오른쪽 Cmd 두 번 → arecord → Groq Whisper → LLM 정리(길이 가드 · 실패하면 원문) → 두 번을 누른 패널의 커서 자리에 붙여넣기 → /config/dictation.jsonl. 자리 나누기(terminal은 트리거 · 상태 · 삽입, 게스트 bash tars-dictate가 나머지), CA 목록이 없던 https, SIGINT가 못 고치는 WAV 머리, 비밀번호 판정은 ICANON && !ECHO, 게이트는 perl stub으로 Groq를 절대 안 부른다(VD-M0~M2, 2026-10-06 종료)
metadata:
  type: project
---

Voice Dictation(VD)은 2026-10-06에 열어 같은 날 VD-M0~M2로 닫혔다. 사용자의 요청
("2. 마이크로 음성 전사 (Voxio 포팅). /Users/dp/Repository/Voxio")에서 시작했고,
같은 요청의 1번은 [[project_audio_devices]]가 먼저 세웠다(AU 비목표 4가 경계 —
"`arecord`가 마이크의 바이트를 WAV로 쓴다"까지가 AU, 그 WAV로 하는 일이 VD).
design은 `docs/specs/2026-10-06-tars-voice-dictation-design.md`(결정 12 · 전제 정정 9 ·
위험 9 · 비목표 14 · 실측 14, Voxio D1 ~ D16 대응표), plan은 `-vd-m0.md` ~ `-vd-m2.md`이고
각 끝의 "실측한 것" 절이 값이다. 실기 안내는 `docs/guides/running-tars.md`의 받아쓰기 절.

design과 plan 셋은 Opus 서브에이전트가, 구현 셋은 Sonnet 서브에이전트가 했다. 포팅이지
복제가 아니다 — macOS에만 있는 것(TCC · Keychain · 메뉴바 · 오버레이 · AX 포커스 ·
클립보드 경유)은 TARS의 같은 뜻을 가진 자리(상태 줄 · `/config`의 파일 · 포커스 패널 ·
PTY에 직접)로 옮기거나 비목표로 보냈다.

## 자리 나누기 — terminal은 트리거 · 상태 · 삽입, 게스트 프로그램이 나머지

terminal이 오른쪽 Cmd 두 번(`KEY_RIGHTMETA`, PC 자판은 오른쪽 Alt)에 `/usr/bin/tars-dictate`를
fork하고(`pipe2` 둘 · `setpgid` · `execve`, terminal은 이미 libc를 링크하므로 `std.c`)
표준 출력을 poll로 읽어 EOF에 두 번을 누른 패널에 `pasteParts`(bracketed)로 넣는다.
둘째 더블 탭은 그룹에 SIGINT(녹음 끝 → 전사), 녹음 중의 Esc는 SIGTERM(취소, PTY로 안
간다). 판정기(`dictation.zig`의 `DoubleTap`)는 "녹음 중"을 들지 않는다 — 시작인지
끝인지는 자식의 단계가 정한다. 단계 넷(`starting` · `recording` · `transcribing` ·
`cancelling`)은 자식의 표준 에러 두 줄(`tars-dictate: recording; ` · `recording stopped `)이
옮긴다 — 그 두 줄이 M0 · M1 사이의 계약이다.

`tars-dictate`는 bash + `arecord` + `curl` + `jq`다([[project_write_or_reuse]] — 순서와
갈래는 우리 것, 소리 · HTTP · JSON은 남의 것. 무음 판정에 한글이 글자여야 해서 `jq`의
`\p{L}`이 Zig보다 맞았다). 설정은 `/config/dictation.conf`(키 여덟 — `tars.conf`에 안
더했다: 쓰는 것이 이 스크립트 하나이고 재부팅이 필요 없고 seed 48줄 · argv를 안 건드린다),
키는 `/config/groq.key`(또는 `GROQ_API_KEY`, `curl -K -`의 표준 입력으로 보내 cmdline에 안
보인다), 기록은 `/config/dictation.jsonl`(원문 · 정리본 · 넣은 것, 오디오는 안 남긴다 —
Voxio 불변식 1 "전사가 된 순간부터 남는다"를 첫 milestone부터).

## 실측이 바로잡은 전제들

- 게스트의 `curl`은 TLS 라이브러리는 있지만 인증 기관 목록이 없어 https가 전부 `(77)`이었다.
  sysroot의 ca-certificates 150장을 initrd에 잇는다(컨테이너의 묶음은 OrbStack 인증 기관이
  섞여 있어 안 쓴다).
- `arecord`를 SIGINT로 멈추면 WAV 머리를 거의 못 고친다(24판 중 21판). `tars-dictate`가
  머리 44바이트를 다시 쓴다.
- 비밀번호 프롬프트의 판정은 `ECHO`가 아니라 `ICANON && !ECHO`다 — 셸의 줄 편집기가
  `ECHO`를 끈다. 시작할 때와 넣을 때 두 번 본다(상태 줄 `PASSWORD`). fish의 `read -s`처럼
  자기 편집기로 가리는 것은 못 본다.
- QEMU `sendkey meta_r`는 hold 80을 줘야 사람 손과 비슷하다(기본은 누른 시간 10ms).
- M0의 SIGINT 틈(`arecord` 전의 SIGINT를 기억만 하고 상한까지 녹음)을 M2가 닫았다.
- 정리의 상한은 매 실행이 새 `curl`이라 DNS · TLS까지 센다 — Voxio의 1.5초는 데워진 연결의
  값이었다. `cleanup_timeout` 키를 열었다(기본 1.5, 실기에서 매번 넘으면 늘리거나 끈다).

## 게이트는 Groq를 절대 안 부른다

스물한번째 체인 `dictation/check.sh`. 전사 · 정리 API는 perl stub(`guestfwd` `cmd:`)이고
경로의 첫 마디가 답(`/ok` · `/ctrl` · `/blank` · `/notext` · `/fail`, 정리는 `/chat/<답>/<갈래>`),
판정은 stub이 받은 바이트(WAV 머리 · 칸 · 샘플의 최빈값 — 마이크는 AU의 `file` 플러그인
`infile`로 넣는다)와 기록 파일이다. 부팅 A는 게스트에 한 글자도 안 치고(프로브가
`tars-dictate`를 스물한 갈래로 친다), 부팅 B(monitor 45493)는 `sendkey meta_r 80` 둘로
더블 탭을 치고 화면 · 상태 줄 · `dictate>` 줄을 본다. 두 부팅 모두 게스트의 `/etc/hosts`가
`api.groq.com`을 127.0.0.1로 돌린다 — 설정을 빠뜨린 갈래가 진짜 Groq에 닿지 않게. 인증 기관
목록은 `openssl s_server`(45492, 자기 서명)에 대고 exit 60(77이 아니라)으로 본다. 호스트에서
`tars-dictate`를 돌리지 않는다 — 호스트 셸에 사람의 진짜 키가 있다(M2 planner가 한 번 stub
로그에 찍었고 지웠다).

## 남긴 것

비목표 14 — 로컬 모델 · 오버레이 · hold 모드 · 알림음 · 정리 프롬프트 키 · 스트리밍 ·
상주 프로세스(연결 재사용) · 기록 회전. 실기에서 볼 것은 running-tars의 받아쓰기 절(진짜
Groq · 첫 연결 지연 · SOF DMIC의 앞부분 0).

관련: [[project_audio_devices]] · [[project_write_or_reuse]] · [[project_paste_ergonomics]] ·
[[project_input_policy]] · [[project_input_status]] · [[feedback_scripting_runtimes]] ·
[[project_seeding_a_config_disk]]
