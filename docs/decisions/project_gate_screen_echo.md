# 게이트의 화면 판정은 자기가 친 명령도 화면으로 센다

NW-M3(2026-09-14)에서 검사 하나를 쓰다가 드러난 성질이다. 이 저장소의 체인
여덟이 같은 방식으로 판정하고 있어서 전부에 해당한다.

## 무엇이 문제인가

`gate_lib.sh`의 `wait_for_screen`은 로그에서 `terminal: screen>` 줄을 전부
모아 패턴을 건다. 마지막 프레임이 아니라 부팅 이후 찍힌 모든 프레임이다.

게스트에 친 명령은 셸이 에코해서 화면에 나타난다. 그러니까 명령줄 자체가
판정 대상 안에 있다 — 패턴이 명령줄 안의 글자면, 그 명령이 아무 일도 안 해도
검사가 초록이 된다.

```bash
# 이렇게 쓰면 dhcpcd가 죽어 있어도 통과한다
type_keys p g r e p spc minus l spc d h c p c d ret
wait_for_screen "dhcpcd"        # 친 명령의 에코가 이미 dhcpcd다
```

증상이 조용하다는 것이 이 함정의 성질이다. 검사는 늘 초록이고, 그것이
"기능이 산다"인지 "검사가 자기를 본다"인지가 화면에서 안 갈린다.

## 처방 — 출력에만 생기는 글자를 만든다

명령 치환으로 값을 만들어 붙이면 명령줄과 출력의 글자가 갈린다.

```bash
# echo dhcpcd-alive=$(pgrep -c dhcpcd)
#   명령줄:  dhcpcd-alive=$(pgrep -c dhcpcd)
#   출력:    dhcpcd-alive=1
type_keys e c h o spc d h c p c d minus a l i v e equal \
  shift-4 shift-9 p g r e p spc minus c spc d h c p c d shift-0 ret
wait_for_screen "dhcpcd-alive=[1-9]"
```

`$(`가 `shift-4 shift-9`, `)`가 `shift-0`이다. fish가 `$(...)`를 읽는다는
것은 `config/check.sh`의 `NEG_COUNT_KEYS`가 이미 증명했다.

다른 길도 있다. 판정 글자를 우리가 바깥에서 넣는 것이다 — `net/check.sh`의
검사 9가 그 모양이다. QEMU가 `guestfwd`로 흘려 넣는 `nwm3-outbound-ok`는
게스트가 실제로 연결을 열었을 때만 화면에 생기고, 명령줄(`nc -w 5
10.0.2.100 8080`)에는 그 글자가 없다.

## 검사를 쓸 때 물어볼 것

1. 이 패턴이 내가 친 명령줄 안에 있나. 있으면 그 검사는 늘 초록이다.
2. 없다면, 그 글자를 만들 수 있는 것이 실행 결과뿐인가.

둘째가 중요하다. 명령줄에 없어도 그 화면 어딘가에 이미 있는 글자면 같은
문제다 — 프롬프트, 앞선 명령의 출력, 배너가 전부 화면이다.

## 관련된 다른 자리

같은 병이 화면이 아닌 곳에서도 나온다. SD 실측 11이 그것인데, 그쪽은 게스트
히스토리 파일이다 — `grep`의 명령줄이 실행 전에 히스토리 파일에 써져서
패턴이 자기를 세고, 음성 기대값이 0이 아니라 1이 된다. 처방도 같은 종류다
(`grep -x`로 줄 전체 일치를 요구한다).

즉 규칙은 "판정 대상에 우리가 친 명령이 들어가는가"를 먼저 묻는 것이고,
화면이든 파일이든 답이 같다.

관련: [[project_shell_history]] · [[project_gate_accuracy]] ·
[[project_guest_network]]
