# TARS Render Speed RS-M2 — 그리는 간격의 하한 (frame cap)

Design: `docs/specs/2026-10-11-tars-render-speed-design.md` · 앞 milestone: RS-M1(`7610860`)

RS-M0이 "프레임 수 = PTY 읽기 횟수"(365 = 365)를 쟀다. 읽기 한 번이 4,095바이트이고 그때마다 화면 전체를 그린다. 이
관계를 끊는다. 처음 계획은 "더 읽고 한 번 그리기"(drain)였고, 측정이 그것을 버리게 해 "그리기를 미루기"(frame cap)로
바꿨다(사용자 승인, 2026-10-11).

## 착수 전에 확정한 것 (2026-10-11 조사, 서브에이전트 + lead 대조)

1. PTY master는 blocking이다(`pty.zig`의 `forkpty`, 저장소 어디도 `O_NONBLOCK`을 안 건다).
2. 질의의 답(`takeReplies`)은 덩이마다 돌려줘야 한다. `REPLY_MAX`가 512(`vt.zig`)이고 넘치면 답을 통째로 버린다.
3. 게이트에서 확실히 깨지는 검사는 없다. 프레임 수를 세는 검사(`pointer`의 `screen_lines -eq`)는 "그리지 않았다"를 보므로
   프레임이 줄어도 맞고, 나머지는 "어느 프레임에든" 또는 "마지막 프레임"을 본다. 하나만 불확실하다 — `tools/check.sh`의
   `ps ax` 뒤 `wait_for_screen "/terminal"`(출력이 약 75줄을 넘으면 그 줄이 마지막 화면에서 밀려난다).
4. `needs_redraw`를 읽는 자리는 루프 끝의 `if (!needs_redraw)` 하나다.

## 첫 구현 — drain, 버렸다

PTY 루프에서 `feed` 뒤 `poll(fd, 0)`으로 "더 있나"를 묻고, 있으면 16ms까지 더 읽어 먹인 뒤 한 번 그렸다. 같은 코드가
판마다 갈렸다.

| 판 | (b) span | frames | 프레임당 읽기 |
|---|---|---|---|
| M1 | 2,959ms | 367 | 1 |
| drain, 프로브 판(3회 × 두 번) | 5,600ms 안팎 | 187 | 2 |
| drain + `feed` · `read` 둘레에 시계 호출을 더한 진단 판(4회) | 2,100ms 안팎 | 96 | 4 |

시계 호출 몇 개가 결과를 두 배 넘게 바꿨다. 진단 판이 잰 것: M1의 4KB 프레임 하나는 `feed` 4.1ms · `read` 0.7ms ·
그리기 1.8ms · 덤프 1.2ms이고 메인 `poll`의 대기는 0이다. 느린 drain 판은 4KB에 약 14.5ms였다.

원인은 게스트의 스케줄링이다. 커널이 `# CONFIG_SMP is not set` · `PREEMPT_NONE` · `HZ=250`이라 CPU 하나를 자식(`seq`)과
터미널이 나눠 쓰고, 커널의 PTY 버퍼(n_tty)는 4KB다 — 그래서 읽기가 늘 4,095바이트였다. 터미널이 읽으면 `seq`가 깨지만
터미널이 막히거나 틱 경계에서 스케줄러가 바꿔 줄 때까지 못 돈다. `poll(0)`은 안 막히므로 "더 있나"의 답이 `feed`(약
4ms) 동안 우연히 틱(4ms)이 와서 `seq`가 돌았는지에 달린다. 위상이 맞물리는 정도가 결과를 갈랐다. 먹이는 쪽이 CPU를
쥔 채 생산자를 기다리는 구조라 성립 자체가 운이다. 진단 판의 로그는 `/tmp/rs-logs/diag-*.log`(저장소 밖).

## 바꾸는 것 — frame cap

더 읽을지 묻지 않고 그리기를 미룬다. 기다리는 자리가 `poll`이라 그동안 CPU가 자식에게 넘어가 버퍼가 다시 찬다 — CPU를
내놓는 것이 우연이 아니라 구조다.

| 파일 | 변경 |
|---|---|
| `pacing.zig`(새) | 순수 모듈. `MIN_GAP_MS` 16 · `wait(now, last, pending)`(그릴 것이 없으면 -1, 처음 프레임과 하한이 지났으면 0, 아니면 남은 ms) · `soonest(a, b)`(-1은 무한이라 `@min`을 그대로 못 쓴다) |
| `pacing_test.zig`(새) · `build.zig` | 호스트 검사 넷. `zig build test`에 건다 |
| `main.zig` | `output_pending` · `last_frame_ms`를 더한다. PTY 출력 뒤의 `needs_redraw = true`를 `output_pending = true`로. `poll` timeout을 `soonest(배터리, wait(…, output_pending))`로. 루프 끝 `if (!needs_redraw)` 앞에서 출력이 있고 하한이 지났으면 `needs_redraw`를 켠다. 그린 뒤 둘을 고친다 |

- 미루는 것은 PTY 출력 때문에 생긴 그리기뿐이다. 키 · 포인터 · 배터리 · 패널 닫힘은 곧바로 그린다. 하한의 목적이 출력
  폭주이고, 미룬 바퀴가 포인터의 화살표 갈래를 타면 `at` 줄이 그 프레임의 `scroll>`보다 앞에 찍혀 pointer 검사 11의
  순서를 깰 수 있어서다. 다른 이유로 어차피 그리는 바퀴는 기다리지 않고 출력도 함께 그린다.
- 읽기 루프는 M1 그대로다(읽기 한 번, `feed` 한 번, 답 돌려주기). 질의의 답 · EOF 갈래를 안 건드린다.
- 키 하나의 지연은 안 는다. 마지막 프레임이 16ms보다 오래전이면 곧바로 그린다.
- 모듈 이름이 `frame`이었다가 `pacing`이 됐다. `main.zig`에 `|frame|` capture가 있어 Zig의 이름 가리기 금지에 걸렸다.

## 게이트

1. `zig build test`(호스트 검사, `pacing_test` 포함).
2. 프로브 3회(`m2`). 기대: (b)의 `frames`가 365에서 크게 준다, `reads`는 그대로 약 365, `other`는 그대로. (a)는 그대로.
3. 루트 게이트(약 10분).

## 결과 (2026-10-11)

호스트 검사 PASS(`pacing_test` 1~4).

프로브 3회(`m2`):

```
m2-run1  (b) span=2207ms frames=125 frame_sum=254ms dump_sum=166ms other=1787ms reads=366   (a) frame=3.15  dump=3.069
m2-run2  (b) span=2274ms frames=129 frame_sum=259ms dump_sum=207ms other=1808ms reads=367   (a) frame=5.396 dump=4.544
m2-run3  (b) span=2179ms frames=126 frame_sum=241ms dump_sum=185ms other=1754ms reads=367   (a) frame=4.749 dump=4.873
```

| | M0 | M1 | M2 |
|---|---|---|---|
| (b) span | 5,501ms | 2,959ms | 2,207ms |
| (b) frames | 365 | 367 | 126 |
| (b) frame 합 | 3,364ms | 698ms | 254ms |
| (b) dump 합 | 377ms | 452ms | 185ms |
| (b) other | 1,783ms | 1,809ms | 1,787ms |
| (a) frame | 11.6ms | 4.9ms | 4.7ms |

프레임 하나에 읽기 약 셋(16ms 동안 쌓인 양)이 합쳐진다. 세 판이 ±2% 안이라 drain처럼 갈리지 않는다. 남은 2.2초의 81%가
파서(`other`)이고 이것이 RS-M0이 말한 하한(약 1.8초)이다.

### 루트 게이트 — 첫 판에서 둘이 빨갰다, 게이트 쪽을 고쳤다

첫 판(22체인 × 1): 20 PASS, `PD-M4`(pointer) · `BS-M1`(battery)이 "the shell prompt never showed up". battery 체인을 단독으로
돌려(`-e TMPDIR=`로 로그를 남겼다) 재현했다. 콘솔(`/dev/console`)에 도는 두 번째 fish(project_init_supervisor)의 프롬프트가
줄바꿈 없이 시리얼에 찍히고, 바로 다음에 쓰인 `terminal: screen>` 줄이 그 뒤에 붙는다. `gate_lib.sh`의 `joined_screen_dump`가
줄머리의 `terminal: screen>`만 보므로 그 줄이 안 보였다. 전부터 있던 일이고(RS-M0 프로브의 실패 로그에도 같은 모양이 있다),
PTY 쪽 fish의 프롬프트가 여러 번에 나눠 읽혀 프레임이 여럿이던 동안은 뒤에 붙지 않은 화면 줄이 하나 더 왔다. M2가 그것을
한 프레임으로 합쳐 드러났다.

처방은 `joined_screen_dump`가 줄 중간의 `terminal: screen>`도 화면 줄로 읽고 그 앞의 조각을 떼는 것이다(이을 차례에 오는
붙은 줄도 경계로 본다). 실패한 battery 로그에 대고 고치기 전 · 후를 비교했다 — 전은 마지막 화면 줄이 빈 줄, 후는
`root@(none) ~#`. 프로브 러너의 `until_prompt`도 같은 이유로 줄 중간의 `screen>`을 본다.

둘째 판: 22체인 전부 `PASS: 1/1`, prebuild 243초 + 줄 319초 = 9분 22초, `skipping make` 22, 잘린 줄 0. `tools`의 `ps ax`
검사(확정 3의 불확실한 하나)도 지나갔다.
