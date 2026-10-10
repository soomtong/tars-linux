# TARS Render Speed RS-M0 — 기준 측정

Design: `docs/specs/2026-10-11-tars-render-speed-design.md`

저장소의 코드(`terminal/src/`)는 한 줄도 안 바꾼다. 더하는 것은 프로브 셋(`probe/`)이고, M1~M3이 끝날 때마다 같은 것을
다시 돌린다.

## 프로브

| 파일 | 하는 일 |
|---|---|
| `probe/patch.pl` | `main.zig`의 사본에 세 자리를 더한다 — 루프 앞의 세는 값과 시계, `feed` 앞의 읽기 횟수 · 바이트, 프레임의 마지막 덤프 뒤 `terminal: probe>` 한 줄. anchor가 정확히 한 번이 아니면 멈춘다 |
| `probe/run.sh` | 컨테이너 안에서 부팅 한 번. 시나리오 (b) `seq 1 200000; echo DONE$status` → (a) `echo` 네 글자. 로그를 `out/probe-rs/<label>-run<N>.log`로 |
| `probe/report.pl` | 로그마다 (b)의 span · 프레임 수 · frame 합 · dump 합 · 나머지(other) · 읽기, (a)의 frame · dump 중앙값, 끝에 회차 중앙값 |

돌리는 법(호스트, 저장소 루트):

```bash
mkdir -p /tmp/rs-probe && perl probe/patch.pl terminal/src/main.zig /tmp/rs-probe/main.zig
diff terminal/src/main.zig /tmp/rs-probe/main.zig     # 더한 줄 3 · 2 · 9, 지운 줄 0
for n in 1 2 3; do
  docker run --rm -v "$PWD":/workspace \
    -v /tmp/rs-probe/main.zig:/workspace/terminal/src/main.zig:ro \
    -w /workspace tars-devcontainer bash probe/run.sh <label> $n
done
perl probe/report.pl out/probe-rs/<label>-run*.log
```

부팅 한 번이 약 1분 10초다(커널은 스탬프로 건너뛴다).

## 착수하며 고친 것

1. 셸 대기를 `Welcome to fish`로 썼다가 실패했다 — 지금 첫 화면에 그 인사가 없다. 프롬프트 `~# `로 기다린다.
   처음에는 `~# *$`였는데 시리얼의 줄 끝에 `\r`이 있어 `$`가 안 맞았다.
2. (a)의 시작 표식을 시리얼 로그에 덧붙이려다 뺐다. QEMU가 같은 파일에 제 offset으로 쓰고 있어 덧붙인 줄이 덮일 수
   있다. `DONE0` 프레임 뒤의 `key>` 다음 프레임을 (a)로 센다.
3. (b)를 `seq 1 20000`으로 처음 쟀더니 0.53초 · 34프레임이라 잡음에 묻히기 쉬웠다. 열 배로 늘렸다.

## 결과 (2026-10-11, HEAD `2c49fbd`, 부팅 3회)

```
m0-run1  (b) span=5638ms frames=366 frame_sum=3414ms dump_sum=392ms other=1833ms reads=366 bytes=1489365
         (a) frame=11.363 ms dump=2.593 ms
m0-run2  (b) span=5489ms frames=365 frame_sum=3364ms dump_sum=371ms other=1755ms reads=365 bytes=1489218
         (a) frame=12.76 ms dump=2.728 ms
m0-run3  (b) span=5501ms frames=365 frame_sum=3341ms dump_sum=377ms other=1783ms reads=365 bytes=1489218
         (a) frame=10.989 ms dump=2.566 ms
중앙값   (b) span=5501ms frames=365 frame_sum=3364ms dump_sum=377ms   (a) frame=11.644 ms dump=2.593 ms (n=12)
```

회차 사이의 폭이 2~3%다. 전후 비교의 기준으로 쓸 만하다.

## 읽은 것

1. 프레임 수 = 읽기 횟수다(365 = 365). 읽기 한 번이 4,095바이트이고 그때마다 화면 전체를 다시 그린다(배경 3 확인).
2. (b)의 시간은 그리기 61% · 덤프 7% · 그 밖 32%다. 그 밖은 4KB를 VT 파서에 먹이는 `feed` · poll · read · 프로브 줄이다 —
   프레임마다 약 4.9ms. 라이브러리 몫이 대부분이라 이 서브프로젝트의 대상이 아니다.
3. 덤프는 생각보다 싸다. (b)에서 프레임당 약 1ms, (a)에서 2.6ms다. design 결정 5(덤프를 끌지)는 지금 열 이유가 없다.
4. (a)의 `frame` 11.6ms는 RC-M0의 21.3ms와 다르다. 측정 조건(호스트 · 프로브의 경계 · `kms:` 줄 포함 여부)이 달라서 두
   값을 섞지 않는다. 이후의 비교는 이 표하고만 한다.

## M1 · M2가 겨냥하는 자리

- M1(칠하기 `@memset`)은 (a)의 `frame`과 (b)의 `frame_sum`을 줄인다. (b)의 61%가 대상이다.
- M2(프레임 합치기)는 (b)의 `frames`를 줄인다. 읽기 한 번에 프레임 하나인 관계를 끊는 것이다. 그리기 몫이 프레임 수에
  비례해 줄고, 덤프도 같이 준다. `other`는 바이트 수에 비례하므로 남는다 — (b)의 하한은 약 1.8초다.
