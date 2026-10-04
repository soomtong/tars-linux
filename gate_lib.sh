# 게이트 체인들이 함께 쓰는 것 둘 — 게스트 메모리 크기와 타이핑 헬퍼.
#
# 왜 파일 하나인가. GL-M2 전까지 아래 함수는 다섯 체인에 글자 그대로 같은
# 모양으로 다섯 벌 있었고, terminal 체인에는 같은 일을 하는 인라인 for 루프가
# 둘 더 있었다. 대기 방식을 바꾸려면 일곱 자리를 함께 고쳐야 하는데, 고친
# 것을 다시 일곱 벌로 두면 이 저장소가 이미 앓고 있는 병(로그 문구가 init
# 코드와 check.sh 양쪽에 있는 것)을 한 자리 더 만든다.
#
# 체인은 여전히 단독으로 실행할 수 있다. 같은 저장소 안의 파일이라 네트워크도
# 빌드도 필요 없고, 체인이 전부 `cd "$(dirname "$0")"`으로 시작하므로 경로가
# ../gate_lib.sh 하나로 고정된다.

# ── 게스트 메모리 — UT-M2가 실측으로 강제한 값 ──────────────────────
#
# QEMU의 기본값은 128MiB이고, UT-M2의 initrd는 거기서 못 뜬다.
#
#   [    1.27] Kernel panic - not syncing: System is deadlocked on memory
#
# initramfs는 tmpfs다 — cpio를 푼 84MB가 통째로 RAM에 남는다. 거기에 커널
# 코드와 예약이 48MB라 128MiB 안에 자리가 없다. 도구가 못 도는 것이 아니라
# 기계가 안 켜진다. 2026-09-11에 넷을 재서 경계를 찾았다:
#
#   128M  panic (available 80,964K)
#   256M  뜬다 (available 209,716K)
#   512M  뜬다      1024M  뜬다
#
# 256이 아니라 512를 고른다. 256은 뜨지만 tmpfs 84MB를 빼면 여유가
# 125MB뿐이고, UT-M3이 git과 vim.tiny를 더한다. 경계에서 두 칸 떨어져 있는
# 편이 낫다 — 이 수를 다시 재는 비용이 게이트 한 판(16분)이다.
#
# 실기에는 영향이 없다. 128MiB는 QEMU의 기본값이지 이 기계의 요구사항이
# 아니고, RM이 겨냥한 노트북은 GB 단위다. 이것은 게이트만의 제약이다.
#
# 왜 여기 있는가. 이 수를 쓰는 QEMU 호출이 열둘이고 전부 같은 initrd를
# 부팅한다 — 하나만 낮으면 그 체인만 panic하고, 증상이 "도구가 없다"가 아니라
# "부팅이 안 된다"라 원인에서 멀다. UT-M1이 도구 목록에 한 것과 같은 이유로
# 한 자리에 둔다(결정 7). machine/check.sh만 RM 때부터 -m 512를 손으로
# 갖고 있었다 — 나머지 열하나는 QEMU의 기본값으로 돌고 있었고, 아무도 그
# 수를 고른 적이 없다는 것이 UT-M2 전까지 드러나지 않았다.
#
# boot/check.sh와 device/check.sh는 타이핑을 안 하는데도 이 파일을 source한다.
# 이 수 하나 때문이다.
GUEST_MEM=512

# 게스트에 키를 한 개씩 보내고, 게스트가 반응할 때까지 기다린다.
#
# 부르는 쪽이 갖춰야 하는 것 둘:
#   fd 3    QEMU monitor에 연결돼 있어야 한다
#   $LOG    그 부팅의 시리얼 로그 파일 경로
# 둘 중 하나라도 없으면 그 자리에서 죽는다(체인들이 set -u다). 막지 않는
# 것이 의도다 — 빠뜨린 사람에게 가장 빨리 알려준다.
#
# 왜 고정 sleep이 아닌가. GL-M2 전에는 키마다 0.3초를 무조건 쉬었다.
# 그 0.3은 "이만하면 충분할 것이다"라는 짐작이고, 짐작이 틀리는 날의 증상은
# 게이트가 가끔 깨지는 것이다. 로그가 자라는 것을 보면 짐작이 사라진다.
#
# 왜 문자열이 아니라 파일 크기인가. 어느 줄이 찍히는지는 키마다 다르다 —
# 셸로 가는 글자는 에코를 거쳐 screen>을, copy 명령은 copy>를, 검색 프롬프트
# 안의 글자는 find> type을 만든다. 어느 줄인지 알 필요 없이 "무언가 반응했다"
# 만 알면 되므로 크기를 본다.
#
# 이 판정이 서는 이유는 로그가 조용하기 때문이다. main.zig의 렌더가
# needs_redraw를 문지기로 두고 있어서(TR-M2) 아무 일도 없으면 프레임이 안
# 찍힌다. 그 성질을 깨는 사람은 이 함수도 함께 봐야 한다.
#
# 아래 한도 0.05초는 CM-M0의 실측이다 — 0.05초 간격으로 80번을 보내도 하나도
# 안 떨어진다. 위 한도는 0.05 + 0.01 × 25 = 0.3초이고 GL-M2 전의 값과 같다:
# 로그를 한 글자도 안 만드는 키가 있어도 이 변경이 지금보다 느려지지 않는다.
type_keys() {
  local k before i
  for k in "$@"; do
    before="$(wc -c < "$LOG")"
    echo "sendkey $k" >&3
    sleep 0.05
    for i in $(seq 1 25); do
      if [ "$(wc -c < "$LOG")" -gt "$before" ]; then break; fi
      sleep 0.01
    done
  done
}

# 화면 줄에 패턴이 나타날 때까지 기다린다. 있으면 0, 15초가 지나면 1.
#
# UT-M2가 이것을 만든 이유. 명령을 친 뒤 `sleep 2`를 하고 한 번 grep하는
# 것이 이 저장소의 오래된 모양인데, UT-M2에서 그것이 8회 중 2회 깨졌다.
# 깨진 회차의 마지막 화면에는 찾던 글자가 정확히 찍혀 있었다 —
#
#   eza vendor | fonts | root@(none) ~# fd otf vendor | vendor/fonts/unifont.otf
#
# 출력이 틀린 것이 아니라 검사가 먼저 본 것이다. `ps ax`가 화면을 통째로
# 채운 뒤로 격자 전체를 다시 그려야 하고(RC-M0: 한 프레임의 84.7%가 fill),
# 게이트는 arm64 호스트에서 x86_64를 TCG로 흉내내는 중이라 그 한 프레임이
# 2초를 넘는 회차가 있다. 2라는 수를 아무도 잰 적이 없다.
#
# type_keys가 GL-M2에서 배운 것과 같다 — 고정 sleep은 짐작이고, 짐작이
# 틀리는 날의 증상은 게이트가 가끔 깨지는 것이다. 로그를 보면 짐작이 사라진다.
#
# 찾으면 즉시 돌아오므로 이 변경은 게이트를 느리게 하지 않는다. 오히려
# 빠르다: UT 체인의 고정 sleep 합계가 부팅당 17초였다.
#
# 한도 15초는 "이 정도면 렌더가 아니라 진짜 실패"의 선이다. 못 찾고 돌아오면
# 부르는 쪽이 fail()로 진단을 찍는다 — 막지 않고 알린다.
#
# 2초를 넘게 기다린 회차는 말해 준다. 그 줄이 자주 보이기 시작하면 렌더가
# 느려진 것이고, 침묵보다 낫다.
#
# 패턴은 ERE다(grep -E). 파이프 대신 here-string을 쓰는 것은 이 스크립트들의
# pipefail 때문이다 — `grep | grep -q`는 앞단에 SIGPIPE를 일으킬 수 있고
# pipefail이 그것을 파이프라인 실패로 올린다.
#
# 다른 체인들은 아직 고정 sleep이다. UT 체인만 고친 것은 깨지는 것을 이
# 자리에서 봤기 때문이고, 나머지 열은 3/3을 여러 판 지나왔다. 다음에 깨지는
# 체인이 있으면 그 체인이 이 함수를 쓰면 된다.
wait_for_screen() {
  local pattern="$1" i screen
  for i in $(seq 1 150); do
    screen="$(grep -a "terminal: screen>" "$LOG")"
    if grep -aqE -- "$pattern" <<<"$screen"; then
      if [ "$i" -gt 20 ]; then
        echo "  (the screen took about $((i / 10))s to show /${pattern}/)"
      fi
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# ── loopback 왕복 — LB-M3 ────────────────────────────────────────────
#
# 게스트 안의 두 프로세스가 이름 셋으로 TCP를 한 번씩 주고받게 친다.
# tools 체인(net=off)과 net 체인(net=dhcp)이 같은 것을 치므로 여기 있다.
# 판정은 부르는 쪽이 한다 — 마지막 줄의 출력이
#
#   /tmp/lb-ip.txt:1   /tmp/lb-lh.txt:1   /tmp/lb-app.txt:1
#
# 이고, 친 명령줄에는 파일 이름 뒤에 `:`가 안 붙으므로 에코와 안 겹친다.
# 받은 것이 없으면 `:0`이다. 세는 것은 흘려 보낸 /etc/passwd의 `root`다.
#
#   ip   127.0.0.1      lo가 UP인가(init의 loopbackUp)
#   lh   localhost      /etc/hosts 또는 myhostname
#   app  app.localhost  myhostname만 답한다
#
# 리스너의 stdin을 /dev/null로 돌리는 것이 중요하다. 배경 job이 터미널을
# 읽으면 SIGTTIN으로 멈추고 받은 것을 파일에 안 쓴다(net/check.sh 검사 14).
# -q 1은 보내는 쪽 stdin의 EOF 뒤 1초에 닫는다.
#
# 흘려 보내는 것이 /etc/passwd인 데 이유가 있다. 처음에는 /etc/hosts였는데
# mutation(그 파일을 비움)에서 세 이름이 전부 `:0`이 됐다 — 연결은 셋 다
# 됐는데(`has ended`) 보낼 내용이 사라진 것이다(LB design 실측). 게이트가
# "loopback을 못 건넜다"고 말하면서 원인은 딴 데 있는 모양이라, 판정의 재료를
# 판정 대상(이름 풀이)과 무관한 파일로 옮겼다. passwd는 늘 있고 LB가 안
# 만진다.
type_loopback_roundtrips() {
  # nc -l -p 9101 < /dev/null > /tmp/lb-ip.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 1 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus i p dot t x t spc shift-7 ret
  # nc -q 1 127.0.0.1 9101 < /etc/passwd
  type_keys n c spc minus q spc 1 spc 1 2 7 dot 0 dot 0 dot 1 spc 9 1 0 1 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # nc -l -p 9102 < /dev/null > /tmp/lb-lh.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 2 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus l h dot t x t spc shift-7 ret
  # nc -q 1 localhost 9102 < /etc/passwd
  type_keys n c spc minus q spc 1 spc l o c a l h o s t spc 9 1 0 2 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # nc -l -p 9103 < /dev/null > /tmp/lb-app.txt &
  type_keys n c spc minus l spc minus p spc 9 1 0 3 spc shift-comma spc \
    slash d e v slash n u l l spc shift-dot spc \
    slash t m p slash l b minus a p p dot t x t spc shift-7 ret
  # nc -q 1 app.localhost 9103 < /etc/passwd
  type_keys n c spc minus q spc 1 spc a p p dot l o c a l h o s t spc 9 1 0 3 spc \
    shift-comma spc slash e t c slash p a s s w d ret

  # grep -c root /tmp/lb-ip.txt /tmp/lb-lh.txt /tmp/lb-app.txt
  type_keys g r e p spc minus c spc r o o t spc \
    slash t m p slash l b minus i p dot t x t spc \
    slash t m p slash l b minus l h dot t x t spc \
    slash t m p slash l b minus a p p dot t x t ret
}
