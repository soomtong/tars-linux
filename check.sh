#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# 매 회차 전에 지우는 것은 "빌드 산출물"뿐이다.
#
# 지우면 안 되는 것들(전부 .gitignore 대상이라 눈에 안 띈다):
#   terminal/ghostty-src  GitHub tarball로 받아온 vendor 소스 트리
#   terminal/vendor       stb_truetype.h + unifont
#   terminal/zig-pkg      Zig 0.16의 프로젝트 로컬 패키지 캐시
# 이 셋은 네트워크가 있어야만 복구되므로, clean 대상에 넣으면 매 회차 수백
# MB를 다시 받고 오프라인에서는 아예 복구가 불가능하다.
clean() {
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
}

# GL-M0: 체인이 자기가 부팅할 것을 스스로 빌드하는지 확인한다.
#
# clean()이 매 회차 지우던 시절에는 이 검사가 필요 없었다 — 빌드 스텝을
# 빠뜨린 체인은 `cp: cannot stat ...`으로 즉시 죽었다. 실제로 그 죽음이 사고
# 둘을 잡았다(DF-M3의 kms, TF-M4의 terminal 바이너리). clean을 게이트 시작
# 1회로 옮기면 그 체인은 대신 **남이 만들어 둔 산출물로 조용히 통과한다.**
#
# 그래서 부팅 전에 스크립트를 읽어서 판정한다. 산출물이 신선한지는 보지
# 않는다 — Zig는 내용 해시로 판단해서 touch를 무시하므로 mtime 비교는 내용이
# 같고 mtime만 새것인 상황(git checkout, 편집했다 되돌리기)에서 거짓 실패한다.
# 빌드를 부르기만 하면 반영은 Zig와 make가 보장한다. **부르는지만 본다.**
#
# 패턴에 './'가 들어 있는 것은 실행과 언급을 가르기 위함이다
# (input/check.sh:88의 echo 문자열이 실제 예다). 주석 줄을 걸러내는 것은
# 호출을 지우는 대신 #으로 막아 두는 손버릇을 잡기 위함이다.
#
# **빌드 스텝이 새로 생기면 이 목록도 함께 고쳐야 한다.**
BUILD_STEPS=(
  'cd ../kernel && ./build.sh)'
  'cd ../init && zig build)'
  './prepare.sh'
  './make_initrd.sh'
)

require_build_steps() {
  local script="$1"
  local step body missing=0

  body="$(grep -vE '^[[:space:]]*#' "$script")"

  for step in "${BUILD_STEPS[@]}"; do
    case "$body" in
      *"$step"*) ;;
      *)
        echo "check FAIL: ${script} never calls '${step}'" >&2
        missing=1
        ;;
    esac
  done

  return "$missing"
}

run_chain() {
  local name="$1"
  local script="$2"

  for i in 1 2 3; do
    echo "=== ${name} run ${i}/3 ==="
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
# HI 체인은 한글 입력을 본다. CM 체인과 판정 도구가 같다 — `key>` 줄 개수의
# **음성** 검사가 이 체인의 값이고, 조합 중인 자모가 PTY로 새는 것이 이
# 기능의 가장 흔한 실패 방식이다.
#
# 여기만 쓰는 도구가 하나 있다: **반전된 셀의 개수**다. 한글은 두 칸이라
# (HI-M0 실측 3) 조합 중에는 커서가 두 칸을 먹는데, 하나만 반전되면 게스트
# 화면에서 글자의 오른쪽 절반이 사라진다. 로그만 보는 게이트가 그 사고를
# 잡는 길이 그 개수다.
#
# 회차당 부팅 1회라 총 부팅 횟수는 30회에서 33회가 된다.
#
# 이름과 경로를 한 곳에 모은다. 진입 검사와 실행이 같은 목록을 쓰므로,
# 체인을 더하거나 뺄 때 고칠 자리가 하나다.
CHAINS=(
  "BF-M4:./boot/check.sh"
  "TF-M4:./terminal/check.sh"
  "CP-M2:./config/check.sh"
  "IP-M2:./input/check.sh"
  "PM-M1:./power/check.sh"
  "HD-M2:./device/check.sh"
  "TR-M2:./render/check.sh"
  "CM-M2:./copy/check.sh"
  "HI-M2:./hangul/check.sh"
)

# 진입 검사는 **첫 부팅 전에** 아홉 개를 전부 훑는다. 하나라도 빠뜨렸으면
# 게이트를 시작하지 않는다 — 한 체인에서 멈추지 않고 끝까지 훑는 것은
# 고칠 자리를 한 번에 다 보여주기 위함이다.
entry_failed=0
for entry in "${CHAINS[@]}"; do
  require_build_steps "${entry#*:}" || entry_failed=1
done
if [ "$entry_failed" -ne 0 ]; then
  echo "TARS check FAIL: a chain would have run without building what it boots" >&2
  exit 1
fi

# GL-M0: clean은 여기서 한 번만 부른다. 예전에는 run_chain이 회차마다 불렀고
# 그것이 게이트 54분 중 약 45분을 만들었다(같은 산출물을 24번 빌드했다).
#
# 3회 반복이 잡는 것은 부팅과 게스트 입력의 flakiness이지 빌드 재현성이
# 아니다 — 같은 소스를 같은 컨테이너에서 다시 빌드하는 것이라 1회차가 통과한
# 것을 2·3회차가 실패시킬 경로가 사실상 없다. **반복의 목적을 부팅에 돌려주는
# 변경이지 반복을 줄이는 변경이 아니다.**
clean

for entry in "${CHAINS[@]}"; do
  run_chain "${entry%%:*}" "${entry#*:}"
done

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
