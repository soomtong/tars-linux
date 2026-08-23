#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# 매 회차 전에 지우는 것은 "빌드 산출물"뿐이다.
#
# 지우면 안 되는 것들(전부 .gitignore 대상이라 눈에 안 띈다):
#   terminal/ghostty-src  GitHub tarball로 받아온 vendor 소스 트리
#   terminal/vendor       stb_truetype.h + unifont + libghostty-vt 산출물
#   terminal/zig-pkg      Zig 0.16의 프로젝트 로컬 패키지 캐시
# 이 셋은 네트워크가 있어야만 복구되므로, clean 대상에 넣으면 매 회차 수백
# MB를 다시 받고 오프라인에서는 아예 복구가 불가능하다.
clean() {
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
}

run_chain() {
  local name="$1"
  local script="$2"

  for i in 1 2 3; do
    echo "=== ${name} run ${i}/3 ==="
    clean
    if ! "$script"; then
      echo "${name} FAIL: run ${i}/3 failed"
      exit 1
    fi
    echo "=== ${name} run ${i}/3 PASSED ==="
  done

  echo "${name} PASS: 3/3 consecutive runs succeeded"
}

# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. 한때 있던 DF 체인
# (display/check.sh)과 kernel/check.sh는 ZM-M2에서 파일까지 지웠다 — 은퇴
# 사유는 docs/decisions/project_gate_chain_composition.md 참고.
#
# CP 체인은 영속 저장소를 본다. 세 체인 중 유일하게 -drive로 디스크를 물고
# 부팅하며, 나머지 둘은 디스크 없이 부팅해도 통과해야 한다는 것 자체가
# 검사 대상이다(설정 저장소가 없다고 부팅이 막히면 안 된다).
#
# CP-M1부터 이 체인만 회차당 QEMU를 **두 번** 띄운다. 영속성은 한 번의
# 부팅으로 증명할 수 없기 때문이다 — 1차가 쓴 파일을 2차가 읽는다. 그래서
# 루트 게이트 한 번의 총 부팅 횟수는 9회가 아니라 12회다.
#
# CP-M2부터는 그 1차 부팅에서 monitor sendkey로 **게스트 셸에 직접 타이핑**해
# 설정을 고친다. 그래서 이 체인만 회차당 20초쯤 더 걸린다.
#
# IP 체인은 키보드 입력 정책을 본다. CP처럼 monitor sendkey로 게스트에
# 타이핑한다.
#
# IP-M2부터 이 체인도 회차당 QEMU를 **두 번** 띄운다. 1차는 디스크 없이
# 떠서 Ctrl+C · TERM · 방향키 · Option/Cmd를 보고, 2차는 keyboard=pc가 이미
# 적힌 디스크를 물고 떠서 그 한 줄이 Alt와 Meta를 맞바꾸는 것을 본다.
# 부팅을 하나 더 붙인 이유는 디스크가 없으면 설정이 영원히 기본값(apple)이라
# pc 경로를 **구조적으로** 밟을 수 없기 때문이다 — 게이트가 못 보는 것은
# 게이트가 통과시킨다.
#
# 그래서 루트 게이트 한 번의 총 부팅 횟수는 15회에서 18회가 된다.
# 이 체인에서 비싼 쪽은 부팅(~4초)이 아니라 타이핑(글자당 0.3초)이다.
#
# PM 체인은 전원 관리를 본다. 게스트 셸에 `kill -TERM 1`을 타이핑하고,
# PID 1이 자식을 정리한 뒤 reboot(2)를 부르는 것까지 로그로 확인한다.
# 이 체인만 shell=bash가 적힌 디스크를 물고 뜬다 — kill이 initrd에
# 바이너리로 없어서 빌트인이 확실한 셸이 필요하기 때문이다.
#
# PM-M1부터 이 체인도 회차당 QEMU를 **두 번** 띄운다. 1차는 -no-reboot을 단
# 채로 끄는 경로를(kill -TERM 1 → HALT), 2차는 그것을 **뺀** 채로 되살리는
# 경로를 본다(설정 편집 → ctrl-alt-delete → 재부팅 → 새 설정으로 zsh). 두
# 부팅의 QEMU 옵션이 이렇게 갈리는 것이 PM을 기존 체인에 얹지 않은 이유다.
#
# 그래서 총 부팅 횟수는 18회에서 24회가 된다.
#
# BF 체인도 PM-M1부터 몇 초 길어진다. 배너 뒤에 감독 루프가 /terminal을
# 포기하는 것까지 기다리기 때문이다 — 재시작 backoff가 1초라 3초 남짓이다.
#
# HD 체인은 하드웨어 탐색과 전원 버튼을 본다. 여섯 체인 중 유일하게 게스트에
# 한 글자도 타이핑하지 않는다 — 종료 명령이 QEMU monitor의 system_powerdown
# 으로 오기 때문이다. 디스크도 물지 않는다(전원 버튼은 설정과 무관하다).
# 회차당 부팅 1회라 총 부팅 횟수는 24회에서 27회가 된다.
#
# PM 체인과 나란히 놓으면 자리가 분명해진다. PM은 셸에서 시작하는 종료를,
# HD는 바깥에서 눌린 버튼으로 시작하는 종료를 본다. 마지막 절반은 같고 첫
# 절반이 다르다.
#
# HD-M2가 감독 루프를 poll 구조로 바꿨다는 것도 여기 적어 둔다. 그 변경은
# 이 체인들 **전부**가 딛고 선 코드를 건드린 것이라, 앞으로 그 자리를
# 고치는 사람은 HD 체인 하나만 보아서는 안 된다 — BF의 "started terminal
# 정확히 3회"와 PM의 "종료 중 되살리지 않는다"가 그 코드의 진짜 계약이다.
#
# TR 체인은 색상 렌더링을 본다. 다른 여섯 체인과 다른 점은 **화면의 픽셀을
# 직접 되읽는다**는 것이다 — 나머지는 전부 로그 문자열만 본다. 게스트에
# printf 한 줄을 타이핑하고, 파서가 뽑은 색(style>)과 프레임버퍼에 실제로
# 들어간 색(pixel>)이 같은지를 대조한다. 회차당 부팅 1회라 총 부팅 횟수는
# 27회에서 30회가 된다.
#
# 이 체인이 더하는 비용의 대부분은 부팅이 아니라 **커널 빌드 3회**(약 2분
# 40초)다. 2026-08-22에 CONFIG_PRINTK_TIME을 켜서 잰 결과 부팅 하나가
# 1.5초라는 것이 밝혀졌다(docs/decisions/project_kernel_config.md).
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
run_chain "IP-M2" ./input/check.sh
run_chain "PM-M1" ./power/check.sh
run_chain "HD-M2" ./device/check.sh
run_chain "TR-M1" ./render/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
