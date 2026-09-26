# WN-M3 — 열네번째 체인 `nic/check.sh`: 붙은 NIC와 꽂힌 NIC가 주소를 받는다

Design: `docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md`(결정 2 · 5 · 6, 실측 3 · 6 · 12~14)
Date: 2026-09-26

## 이 milestone이 하는 일

design 결정 5의 체인을 세우고 `CHAINS`에 넣는다. `net` 체인이 virtio 위에서
프로토콜(DHCP · 포트 · 시계)을 본다면, 이 체인은 드라이버와 장치를 본다 — "노트북에
흔한 장치가 붙어 주소를 받는다" 하나다. 우리 코드는 한 줄도 안 바뀐다. M1 · M2가
세운 것을 게이트가 매번 보게 하는 일이다.

## 정한 것

### 1. 판정은 전부 시리얼 로그다 — 타이핑이 없다

M2가 dhcpcd에 `-j /dev/console`을 준 덕에 lease · 핫플러그가 전부 시리얼에 나온다.
`device` 체인처럼 게스트에 한 글자도 안 치므로 빠르고, 화면 좌표에 안 묶인다.

### 2. 부팅 B의 핵심 판정은 "같은 dhcpcd가 잡았다"다

`-j`의 줄머리에 pid가 있다(`Sep 26 11:10:08 [79]: usb0: leased …`). NIC 없이 뜬
부팅에서 `[N]: no valid interfaces found`를 찍은 pid와 꽂은 뒤 `[M]: usb0: leased`를
찍은 pid가 같아야 한다. 같으면 부팅 때 뜬 dhcpcd 하나가 살아서 기다리다 새 장치를
잡은 것이다(결정 4의 핫플러그 · 결정 6의 "부팅을 안 막는다"). 다르면 누군가 dhcpcd를
다시 띄운 것이고 그것은 이 design이 세운 성질이 아니다.

### 3. 부팅 B는 꽂기 전에 음성 둘을 본다

- `terminal: screen>`이 나온다 — NIC가 없어도 부팅이 끝까지 간다(결정 6).
- 로그에 `eth0`도 `usb0`도 없다 — `-netdev`만 주고 NIC 장치를 안 주면 QEMU가 기본
  NIC를 안 붙인다(실측 5). 이것이 깨지면 부팅 B의 lease가 꽂은 장치의 것인지 못
  가른다.

### 4. 설정 디스크는 체인 안에서 굽는다

`net=dhcp` 한 줄, 라벨 `tars-nic`. `net/make_disk.sh`의 debugfs 수법(특권 없음)을
함수 하나로 옮긴다. 파일을 따로 안 만드는 이유는 디스크가 하나이고 내용이 한 줄이라서다.
`ntp`는 기본값 `off`이므로 시계 자식이 안 뜬다.

### 5. `usbnet: failed control transaction`은 실패가 아니다

실측 6. QEMU `usb-net`이 문자열 descriptor 요청에 답하지 않아 세 줄이 나오고 곧이어
등록이 성공한다. 체인은 이 글자를 안 본다. 주석으로만 남긴다 — 다음 사람이 로그에서
보고 놀라지 않게.

### 6. 포트와 기계

monitor는 A가 45472, B가 45473(45455~45471과 안 겹친다). 둘 다 `-machine q35` +
`-kernel`(`install` 체인의 `boot_kernel_usb`와 같은 모양)이고 `-netdev`를 가지므로
`require_explicit_nic`를 통과한다.

## 검사 목록

| 번호 | 부팅 | 무엇 | 로그 |
|---|---|---|---|
| 1 | 없음 | 드라이버 아홉이 `=y`이고 끈 셋은 `is not set` | `kernel/.config` |
| 2 | A | `e1000e`가 장치에 붙어 `eth0`이 됐다 | `e1000e 0000:… eth0:` |
| 3 | A | `init`은 dhcpcd를 띄우기만 했다 | `started dhcpcd (pid` 있음 · `net link` 없음 |
| 4 | A | dhcpcd가 `eth0`으로 lease를 받았다 | `eth0: leased 10.0.2.15` |
| 5 | B | NIC 없이 부팅이 끝났고 인터페이스가 없다 | `terminal: screen>` · `eth0`/`usb0` 없음 |
| 6 | B | dhcpcd가 살아서 기다린다 | `[N]: no valid interfaces found` |
| 7 | B | 꽂은 `usb-net`에 `cdc_ether`가 붙었다 | `cdc_ether … usb0: register` |
| 8 | B | 같은 dhcpcd가 `usb0`으로 lease를 받았다 | `[N]: usb0: leased 10.0.2.15` |

## Task 1 — 체인을 쓴다

- [ ] `nic/check.sh`(실행 권한). 빌드 스텝 넷은 `require_build_steps`가 찾는 글자
  그대로. `report_failure`는 표지 목록과 로그 끝 60줄.
- [ ] 음성 확인 — 검사 8의 pid 대조가 실제로 가르는지. 하네스를 저장소에 안 두고
  한 번만 본다: 체인 사본에서 기대 pid를 `N+1`로 바꿔 돌리면 검사 8에서 빨개야 한다.

## Task 2 — 체인 한 판 (약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash nic/check.sh > /tmp/wn/m3-nic.log 2>&1; echo "exit=$?"; tail -20 /tmp/wn/m3-nic.log
```

## Task 3 — `CHAINS`에 넣는다

`"WN-M3:./nic/check.sh"`를 `DC-M2` 뒤에. `check.sh`의 체인 설명 문단에 이 체인의
자리(타이핑 없음 · 부팅 둘 · q35 · 판정이 `-j` 로그의 pid)를 더한다. 진입 검사만 먼저
돌려(`sed -n "/^clean$/q;p" check.sh | bash -s`) 새 체인이 빌드 스텝 · 조기 종료 파이프
· NIC 명시 셋을 통과하는지 본다.

## Task 4 — 루트 게이트 3/3 (약 44분)

부팅이 회차당 둘 늘어 여섯이 더해진다. 기준선은 M2의 40분 52.90초. 판정은 `pgrep`이
비는 것을 보고 한다.

## Task 5 — 닫는다

- design `Status: 끝났다` · "WN-M3이 실행으로 증명한 것"
- `docs/decisions/project_wired_nic.md` + `MEMORY.md` 한 줄
- `CLAUDE.md`의 완료 표에 한 줄
- `HANDOFF.md` — 다음은 새 서브프로젝트 고르기
- 커밋
