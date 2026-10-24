# GF-M1 — 게이트의 로그가 컨테이너보다 오래 산다

Date: 2026-10-24
Design: `docs/specs/2026-10-24-tars-gate-flakes-design.md`
Status: 끝났다(2026-10-24). 첫 루트 게이트 21/22(PD-M4가 printk 자름으로 — 아래 실측), GF-M2와 함께 돈 둘째 판 22/22.

## 누가 무엇을 하나

lead가 직접 넣는다. 편집 다섯, 지우는 것 하나.

| 파일 | 무엇을 |
|---|---|
| `check.sh` | `GATE_LOGS`를 만든 직후 EXIT trap — 트리를 `out/gate-logs/<시작 시각>/`으로 옮기고 경로를 찍는다(결정 4) |
| `Makefile` | `check` 타깃이 `TMPDIR=/tmp/gate-logs/<체인>`으로 돌리고 끝에 `out/gate-logs/<체인>/`으로 옮긴다(결정 5) |
| `render/check.sh` | `report_failure`의 `cp … ../out/render-failed-serial.log` 두 줄과 그 주석을 지운다(결정 4) |
| `dictation/check.sh` | B4의 둘째 `got[]` 창 `seq 1 100` → `seq 1 200`(결정 6) |
| `docs/guides/lessons.md` | "회차의 로그는 …" 절과 "게이트 로그를 조사하는 법" · "범용 명령"의 `/tmp/tmp.*` 처방을 새 경로로 |
| `README.md` | 검증 절에 "로그는 `out/gate-logs/`에 남는다" 한 줄 |

## 착수 전에 확정한 것

1. `check.sh`의 `exit 1` 자리는 넷이다 — `cd` 실패(4줄), 진입 검사 실패(586줄), prebuild 실패(618줄), 빨간 체인(714줄). 셋은 `GATE_LOGS`를
   만든 뒤다. trap은 `GATE_LOGS="$(mktemp -d …)"` 바로 다음 줄에 둔다 — 그 뒤의 어느 `exit`도, 사람이 Ctrl+C로 보낸 SIGINT도(bash는
   SIGINT 뒤 EXIT trap을 돈다) 같은 길로 나간다.
2. `clean()`이 `out`을 지우는 것은 게이트 시작 때고 trap은 끝이다. `out/gate-logs/`는 `mkdir -p`로 그때 만든다.
3. `mv`는 overlay(`/tmp`)에서 bind mount(`/workspace/out`)로 가므로 복사 뒤 삭제다. 걸린 초를 `time: logs <n>s`로 찍는다(design 위험 3).
   마지막 줄 `(logs in …)`은 이미 찍힌 뒤라 그대로 두고, trap이 `logs moved to out/gate-logs/<시각>` 한 줄을 더 찍는다.
4. `make check`의 `IN_CONTAINER`는 `bash -c '<한 줄>'`이다. 그 한 줄 안에서 `TMPDIR`을 주고 종료 코드를 잡고 옮긴다 — `set -e`가
   없는 bash라 `rc=$?`가 산다.
5. dictation B4의 두 `for` 가운데 둘째(`got[]`)만 넓힌다. 첫째(`pw> `)는 빨갰던 적이 없다.
6. `render/check.sh`의 `cleanup`(EXIT trap)은 `LOG`를 지우지 않는다(AL-M0) — 복사를 지워도 루트 게이트의 로그는 `TMPDIR`에 남고,
   체인 하나는 결정 5가 남긴다.

## Task 1: `check.sh`

`GATE_LOGS` 줄 바로 뒤:

```bash
# GF-M1 결정 4. 컨테이너는 --rm이라 /tmp의 로그는 게이트와 함께 사라진다. 어떻게 끝나든(초록 · 빨강 ·
# Ctrl+C) 트리를 저장소의 out/gate-logs/<시작 시각>/으로 옮긴다 — 간헐은 통과한 판과 빨간 판을 나란히
# 놓고 보는 것이라 통과한 판도 남긴다. 처음부터 bind mount에 쓰지 않는 이유는 QEMU의 -serial file:이
# 작은 write를 많이 내기 때문이다.
GATE_STAMP="$(date +%Y%m%d-%H%M%S)"
keep_logs() {
  local start dest
  start="$(date +%s)"
  dest="out/gate-logs/${GATE_STAMP}"
  mkdir -p out/gate-logs
  if mv "$GATE_LOGS" "$dest" 2>/dev/null; then
    echo "time: logs $(( $(date +%s) - start ))s"
    echo "logs moved to ${dest}"
  else
    echo "logs stayed in ${GATE_LOGS} (mv failed)"
  fi
}
trap keep_logs EXIT
```

## Task 2: `Makefile`

```make
check: container
	@test -n "$(CHAIN)" || …
	@test -x "$(CHAIN)/check.sh" || …
	$(IN_CONTAINER) 'mkdir -p /tmp/gate-logs/$(CHAIN) && \
	  (cd $(CHAIN) && TMPDIR=/tmp/gate-logs/$(CHAIN) ./check.sh); rc=$$?; \
	  mkdir -p out/gate-logs && rm -rf out/gate-logs/$(CHAIN) && mv /tmp/gate-logs/$(CHAIN) out/gate-logs/ && \
	  echo "logs moved to out/gate-logs/$(CHAIN)"; exit $$rc'
```

도움말의 `make check` 설명에 "로그는 out/gate-logs/<체인>/에 남는다(앞 판은 지운다)"를 더한다.

## Task 3: `render/check.sh` · `dictation/check.sh`

render: `report_failure` 첫 세 줄(주석 둘 · `cp` 하나)을 지운다. dictation: 770줄의 `seq 1 100`을 `seq 1 200`으로, 그 위 주석에
"BS-M0 루트 게이트에서 10초 창을 한 번 놓쳤다(GF-M1 결정 6)"를 한 줄.

## Task 4: 문서

lessons의 세 자리(위 표)와 README 한 줄. "이월 숙제"는 닫을 때 손본다.

## Task 5: 검사와 게이트

1. `bash -n` · `shellcheck -S warning` — `check.sh` · `render/check.sh` · `dictation/check.sh`.
2. `make check CHAIN=device`(가장 짧은 체인, 약 20초 + 빌드). 끝에 `logs moved to out/gate-logs/device`가 찍히고 그 아래에
   시리얼 로그가 있다. `du -sh out/gate-logs/device`.
3. `make check CHAIN=tools` — 1d의 initrd 사본 98MB가 함께 옮겨지는 것과 그 시간.
4. 루트 게이트. 끝에 `time: logs <n>s` · `logs moved to out/gate-logs/<시각>`. `ls out/gate-logs/<시각>/`에 22체인 디렉터리 ·
   `lane-*.out` · `times.tsv` · `prebuild.out`. `du -sh`.
5. dictation 체인은 루트 게이트 안에서 본다(B4 글자는 안 바뀌었다).

## 끝 조건

- 루트 게이트 22/22, `out/gate-logs/<시각>/`에 트리 전체.
- `make check CHAIN=device` 뒤 `out/gate-logs/device/`에 시리얼 로그.
- `rg 'render-failed-serial' -g '*.sh' .`가 0줄.

## 닫을 때(lead의 몫)

design "닫을 때" 절 그대로 — 이 milestone이 GF의 마지막이다.

## GF-M1이 실측한 것

| 항목 | 값 |
|---|---|
| `make check CHAIN=device` | 35초, `out/gate-logs/device/` 24KB(시리얼 로그 하나) |
| `make check CHAIN=tools` | 66초, `out/gate-logs/tools/` 103MB(1d의 initrd 사본 98MB 포함) |
| 루트 게이트 1판(2026-10-24 09:48 UTC) | 21/22 — PD-M4 하나 빨강. prebuild 257초 · lanes 289초 · `time: logs 0s` |
| 옮긴 트리 `out/gate-logs/20261024-094856/` | 141MB. 체인 디렉터리 22 · 시리얼 로그 57 · `lane-*.out` 20 · `times.tsv` 22행 · `prebuild.out` · `failed` |
| `skipping initrd` / `was rebuilt` / A=0 B=0 C=0 | 22 / 0 / 22 (GF-M0의 성질 그대로) |
| dictation B4(결정 6) | 통과 — `a password prompt that appeared while speaking got nothing …` |

PD-M4의 빨강은 M1의 변경과 무관하고, 옮긴 로그가 처음으로 쓰인 자리다. `wait_for_at`이 기다린 줄
`^terminal: pointer> at x=679 y=499 … ink=118$`의 끝에 커널 printk가 끼어 있었다 —

```
terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=118[   12.315317] random: crng init done
```

AU-M2가 `screen>` 줄에서 본 것과 같은 자름이다(lessons "커널 printk가 terminal의 화면 줄을 가운데서 자른다"). `joined_screen_dump`는
`screen>` 줄만 잇고, `pointer>` · `style>` · `pixel>` · `scroll>` 줄을 직접 읽는 자리는 그대로라 그 줄이 마지막 줄이면 한 번의 자름이
곧 실패다. 같은 판의 로그 57개를 훑으니 terminal 줄 안에 커널 시각 표식이 든 체인이 여섯이었다(CM `style>` · CP `style>` · IP `pixel>` ·
PD `pointer>` · PM `scroll>` · TR) — 빨개진 것은 그중 그 줄을 `$`로 대조한 PD 하나다. 커널 콘솔을 `loglevel=4`로 조용히 하는 길은
pointer(`input: QEMU QEMU USB Mouse`) · audio · wifi(`usbcore: registered new interface driver`)가 info 수준의 printk를 판정에 쓰고
있어 바로는 못 간다.
