# DM-M0 — 판정 셋을 먼저 넣고, 지금 코드에서 빨간 것을 본다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `65b6f30` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: DM design 결정 7의 판정 8 · 9 · 10을 `keyboard/check.sh`에 넣는다. 지금 terminal(`65b6f30`)에서 셋 다 빨갛고, 빨강의 이유가
design의 "지금 코드는" 문장과 같다는 것을 로그와 화면으로 확인한다. 위험 1(QEMU가 두 장치의 같은 키를 따로 보내는가)이 여기서
닫힌다. terminal 코드는 0줄이다.

Architecture: 체인 하나의 끝에 판정 셋을 붙인다. 기계 · 설정 디스크 · 도우미(`qmp_key` · `type_keys` · `wait_for_screen` ·
`open_path`)는 KH-M2가 만든 그대로 쓰고, 도우미 하나(`hangul_count`)만 더한다. 체인 수는 27 그대로다.

## 착수 전에 확인한 것 (2026-11-04)

- KH 판정 7b가 끝난 뒤의 기계: 열린 키보드는 k1 하나다. `keyboard> open` 줄이 넷(k1 · k2 · k2 · k2), `close`가 셋이다. 한/영은
  꺼져 있다(판정 5 끝의 `shift-spc`). 화면 셸은 `root@(none) ~#`에서 기다린다.
- 키를 보내는 길(KH 실측 1 · 2): k2를 `display=gpu`로 꽂으면 `qmp_key gpu …`가 k2로, `qmp_key - …` · `type_keys`(HMP
  `sendkey`)가 k1로 간다. k2가 없으면 `qmp_key -`도 k1으로 간다.
- qcode `shift` · `ctrl`은 왼쪽 키다(`KEY_LEFTSHIFT` · `KEY_LEFTCTRL`). 판정 8 · 10은 두 장치에서 같은 왼쪽 키를 겹쳐 쥔다.
- `lctrl_tap`은 기본으로 켜져 있다(`input.zig`의 기본 `toggles`). 체인의 `tars.conf`는 자판만 바꾸므로 그대로다.
- 한/영이 바뀌면 `readKeys`가 `redraw`를 켜고, `readKeyboard`가 `terminal: hangul> on=<bool> preedit=…`를 찍는다(`dumpHangul`).
  한/영이 꺼져 있는 동안은 `on=true` 줄이 새로 안 생긴다. 판정 10은 그 줄의 수로 본다.
- 출력 글자는 앞 판정의 것(`qZq0` · `qxq0` · `qyq0` · `kh10`~`kh30`)과 겹치지 않게 고른다 — `wait_for_screen`은 화면 전체를
  보므로, 겹치면 앞 판정이 남긴 줄로 초록이 된다.
- `report_failure`는 첫 빨강에서 체인을 끝낸다. 그래서 셋을 한 판에 다 보려면 Task 3의 일회용 사본이 필요하다.

## Task 1: `keyboard/check.sh`에 판정 셋

머리 주석의 "판정 일곱" 목록에 셋을 더하고(DM design 결정 7), 마지막 줄을 `=== KH-M2 · DM-M0: all eleven checks passed ===`로
바꾼다. 판정마다 KH의 모양(`# ── 판정 N: … ──` 머리, 근거 주석, `echo "=== N. … ==="`, 끝의 한 줄 요약)을 따른다.

도우미 하나를 `keyboard_count` 옆에 더한다.

```bash
hangul_count() {
  grep -ac "terminal: hangul> on=$1" "$LOG" || true
}
```

### 판정 8 — 겹쳐 쥔 Shift의 한쪽 뗌

```
device_add usb-kbd,bus=xhci.0,id=k2,display=gpu   → wait_for_keyboard_count open 5, K2D_PATH="$(open_path 5)", sleep 0.5
type_keys e c h o spc w
qmp_key gpu shift true          # k2가 Shift를 쥔다
sleep 0.1
qmp_key - shift true            # k1도 Shift를 쥔다
sleep 0.1
qmp_key - shift false           # k1만 뗀다
sleep 0.1
qmp_key - z true; qmp_key - z false
sleep 0.1
qmp_key gpu shift false
sleep 0.3
type_keys w shift-4 s t a t u s ret
```

판정은 `wait_for_screen 'w[zZ]w0'`로 둘 중 어느 쪽이든 기다린 뒤 가른다. `wZw0`면 초록이다. `wzw0`면 `report_failure`인데, 문구는
"k1's Shift key-up released the Shift k2 still holds (wzw0)"이다. 15초 동안 둘 다 안 나오면 키가 안 간 것이므로 문구를 따로 둔다.
이렇게 가르는 것은 M1 뒤에도 빨강의 이유를 문구가 바로 말하게 하려는 것이다.

### 판정 9 — 남은 키보드의 Shift

```
type_keys e c h o spc v
qmp_key - shift true            # k1이 Shift를 쥔다(k2는 판정 8에서 아무것도 안 쥐었다)
sleep 0.3
echo "device_del k2" >&3        → wait_for_log "terminal: keyboard> close ${K2D_PATH}"
sleep 0.5
qmp_key - z true; qmp_key - z false     # k2가 없으니 `-`는 k1이다
sleep 0.1
qmp_key - shift false
sleep 0.3
type_keys v shift-4 s t a t u s ret
```

판정은 `v[zZ]v0`을 기다려 가른다. `vZv0`가 초록이고, `vzv0`는 "k2 left and took k1's held Shift with it (vzv0)"이다. k2는 아무 키도
안 쥐었으므로 커널의 흉내 뗌(KH 실측 9)이 없다. 지금 코드에서 이 Shift를 지우는 것은 `closeKeyboard` → `releaseHeld` 하나뿐이다.

### 판정 10 — 겹친 왼쪽 Ctrl tap, 그리고 양성 대조

```
device_add usb-kbd,bus=xhci.0,id=k2,display=gpu   → wait_for_keyboard_count open 6, sleep 0.5
ON0="$(hangul_count true)"
qmp_key gpu ctrl true           # k2가 왼쪽 Ctrl을 쥔다
sleep 0.05
qmp_key - ctrl true             # k1의 왼쪽 Ctrl을 짧게
sleep 0.05
qmp_key - ctrl false
sleep 0.05
qmp_key gpu ctrl false          # k2도 뗀다. 누름부터 여기까지 약 150ms(TAP_MAX_US 300ms 안)
sleep 1
ON1="$(hangul_count true)"
```

`ON1`이 `ON0`보다 크면 `report_failure`이고, 문구는 "overlapping left Ctrl on two keyboards toggled hangul"이다. 지금 코드에서는
k1의 뗌이 k2의 누름에 짝지어져 한/영이 켜진다(DM design 결정 2, KH 시나리오 S5).

그 뒤 양성 대조를 둔다. 음성 판정 하나만 있으면 tap 길이 통째로 죽어 있어도(QMP의 키가 늦게 와 300ms를 넘겨도) 초록이 되기
때문이다.

```
qmp_key - ctrl true; sleep 0.05; qmp_key - ctrl false
→ hangul_count true가 ON1보다 커질 때까지 기다린다(15초). 안 커지면 report_failure "a lone left Ctrl tap on k1 did not toggle hangul — check 10 proves nothing"
qmp_key - ctrl true; sleep 0.05; qmp_key - ctrl false
→ 한/영이 다시 꺼질 때까지 기다린다(hangul_count false가 는다)
```

기다림은 `wait_for_log`가 아니라 수를 세는 꼴이다(`wait_for_keyboard_count`와 같은 모양으로 `wait_for_hangul_count`를 만든다).
`on=true` · `on=false` 줄은 앞 판정이 이미 찍었으므로, 있기만을 보는 `wait_for_log`는 곧바로 초록이 된다.

### 판정 순서

8 → 9 → 10. 9가 k2를 빼고 10이 다시 꽂는다. KH 판정 7b가 SIGSTOP으로 terminal을 멈췄다가 풀었으므로, 8의 첫 `device_add` 전에
화면 셸이 `qyq0`까지 그린 것은 7b의 끝이 이미 보았다.

## Task 2: 정적 검사

`make quick`(shellcheck note까지 · fmt · ast-check · shared · init 빌드). 이 milestone이 고치는 것은 셸 하나라 shellcheck가 본질이다.
`git diff --stat`과 `git diff | rg '^-'`로 지운 줄이 머리 주석의 목록과 마지막 줄뿐인지 본다.

## Task 3: 지금 코드에서 셋 다 빨간가 (위험 1)

체인을 그대로 돌리면 판정 8에서 끝나 9 · 10을 못 본다. 그래서 일회용 사본을 쓴다.

1. `keyboard/check.sh`를 `keyboard/dm-m0-probe.sh`로 복사한다. 체인이 `cd "$(dirname "$0")"`와 `../`로 길을 잡으므로 같은 자리에
   둬야 한다. 사본에서 판정 8 · 9 · 10의 `report_failure`만 `echo "RED: …"`로 바꾼다(`sed`, 앞 판정과 기계 준비는 그대로).
2. 컨테이너에서 사본을 돌린다(약 1분).
   `docker run --rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace tars-devcontainer ./keyboard/dm-m0-probe.sh`
3. 기대: 판정 1~7b 초록, 8은 `wzw0`, 9는 `vzv0`, 10은 `ON1 > ON0`(한/영이 켜짐)이고 양성 대조는 초록이다.
4. 사본을 지운다. 커밋에 안 들어간다.

갈래.
- 8이나 10이 지금 코드에서 초록이면 위험 1이 열린 것이다 — QEMU가 k1의 같은 키 누름을 게스트에 안 보냈을 수 있다. KH-M0 하네스
  모양(설정 디스크의 서비스가 k1 노드를 `cat`해 `/config`에 쓰고, 끝난 뒤 `debugfs rdump`로 꺼내 `<qqHHi`로 푼다)으로 k1 노드에
  `KEY_LEFTSHIFT`(또는 `KEY_LEFTCTRL`)의 누름 · 뗌이 왔는지 본다. 안 왔으면 design 위험 1의 처방대로 그 판정을 체인에서 빼고
  M1의 단위 검사로만 둔다. design에 그 사실을 적고 사용자에게 알린다.
- 10의 양성 대조가 빨가면 QMP의 키가 300ms를 넘겨 온 것이다. `sleep`을 줄이고 다시 본다. 그래도 안 되면 판정 10을 단위 검사로
  옮기는 것을 사용자와 정한다.
- 9가 초록이면 design 확인 4나 KH 실측 9가 틀린 것이다 — 멈추고 원인을 본다.

## Task 4: 문서

- DM design에 "실측 (M0)" 절. 실측 1 — 판정 셋의 빨강과 그 화면 · 로그 줄(Task 3의 3), 위험 1의 닫음. 실측 2 — 체인의 늘어난
  시간(KH 실측 10의 34초와 비교).
- design Status 줄을 "DM-M0 끝남, 다음 DM-M1"로.
- HANDOFF: M0 끝, 그리고 "`keyboard` 체인은 M1 커밋까지 판정 8에서 빨강이 정상이다 — 이 사이에 루트 게이트를 돌리면 26/27이다".

## Task 5: 커밋

사용자 승인 뒤. add 대상은 `keyboard/check.sh` · design · 이 plan · `HANDOFF.md` 넷으로 좁힌다. `keyboard/dm-m0-probe.sh`가
`git status`에 없는지 먼저 본다.

M0 커밋부터 M1 커밋까지 main의 `keyboard` 체인이 빨갛다. 판정이 고칠 결함을 먼저 붙박는 것이 이 milestone의 뜻이고, 그 사이
빨강은 의도한 결과다. CI(`checks.yml`)는 체인을 안 돌리므로 배지는 안 바뀐다.

## 시간

셸 몇십 줄. 정적 검사 1분, 사본 체인 한 판 약 1분. 루트 게이트는 이 milestone에서 안 돌린다(체인 하나만 바뀌었고, 그 체인은 빨강이
기대값이다).

## 결과 (2026-11-04)

Task 3의 첫 판에서 8 · 9가 초록이었다. 원인은 위험 1(QEMU)이 아니라 커널 자동 반복이 쥔 수정키의 비트를 다시 켠 것이다. 체인에
`stop_repeat`을 더해 판정 8 · 9의 전제로 두었고, 둘째 판에서 셋 다 기대한 이유로 빨갰다. 자세한 것은 DM design 실측 1 · 2.
