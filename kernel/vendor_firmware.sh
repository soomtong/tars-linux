#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# 무선 firmware를 받아 guest_firmware.sh의 목록대로 골라 cpio 하나로 만든다
# (WL-M1). make_initrd.sh가 부르고, 그 cpio를 initrd 뒤에 이어 붙인다.
# AU-M3부터 소리 DSP(Intel SOF)의 firmware와 topology도 같은 cpio에 들어간다.
#
# 버전을 고정하고 sha256을 확인한다. terminal/vendor_fonts.sh와 같은 이유다 —
# 다른 파일이 조용히 들어오면 실패가 "실기에서 무선이 안 뜬다"로 나타나는데,
# 게이트는 실칩을 못 보므로(WL design 위험 4) 그 실패는 원인에서 가장 멀다.
# 해시는 kernel.org의 sha256sums.asc와 대조했다(WL design 실측 3).
LF_VERSION="20260916"
LF_TARBALL="linux-firmware-${LF_VERSION}.tar.xz"
LF_URL="https://cdn.kernel.org/pub/linux/kernel/firmware/${LF_TARBALL}"
LF_SHA256="f80dcb757a623deda62200c08e0e1a88c76fb6b54964f31b35fa74da1c90ccc5"

REGDB_VERSION="2026.09.03"
REGDB_TARBALL="wireless-regdb-${REGDB_VERSION}.tar.xz"
REGDB_URL="https://cdn.kernel.org/pub/software/network/wireless-regdb/${REGDB_TARBALL}"
REGDB_SHA256="b22e0901227b820cd1c280abe681a15b773a5103a5e10dc442e94ebb34cbf58d"

# AU-M3. Intel SOF의 firmware · topology는 linux-firmware에 없다(MediaTek 것만 있다).
# SOF 프로젝트가 서명된 바이너리를 sof-bin 릴리스로 내고, 배포판의 sof-firmware ·
# firmware-sof-signed가 그것을 그대로 담는다. 해시는 GitHub 릴리스 자산의
# digest와 대조했다(AU-M3 plan 확정 3). gz라 linux-firmware(xz)와 압축이 다르다.
SOF_VERSION="2026.09.1"
SOF_TARBALL="sof-bin-${SOF_VERSION}.tar.gz"
SOF_URL="https://github.com/thesofproject/sof-bin/releases/download/v${SOF_VERSION}/${SOF_TARBALL}"
SOF_SHA256="42ce40ec98f366365eab8e046d779b416d80b6ff2513b8f6be2a61a88e679b73"

# 커널 소스와 같은 자리다. .gitignore에 있고 check.sh의 clean()이 안 지운다 —
# linux-firmware는 662MB라 게이트가 매번 받으면 안 된다.
CACHE=src/firmware
OUT="$CACHE/firmware.cpio.gz"
STAMP="$CACHE/.stamp"

# 받은 것은 버리지 않는다. 목록이 바뀌면 다시 풀어야 하는데 다시 받는 것은
# 푸는 것보다 훨씬 비싸다.
fetch() {
  local url="$1" file="$CACHE/$2" sha="$3"
  if [ -f "$file" ]; then
    return 0
  fi
  echo "vendor_firmware: downloading ${url}"
  curl -sSL -o "${file}.tmp" "$url"
  if ! echo "${sha}  ${file}.tmp" | sha256sum -c --status -; then
    echo "FAIL: 내려받은 파일의 sha256이 기대값과 다르다" >&2
    echo "  URL:  ${url}" >&2
    echo "  기대: ${sha}" >&2
    echo "  실제: $(sha256sum < "${file}.tmp" | cut -d' ' -f1)" >&2
    rm -f "${file}.tmp"
    exit 1
  fi
  mv "${file}.tmp" "$file"
}

# build.sh의 GL-M1 스탬프와 같은 모양이다. 이 cpio의 입력은 목록과 이 파일
# (버전이 여기 있다) 둘뿐이다. 둘의 해시가 같으면 푸는 것도 압축도 건너뛴다 —
# gzip이 make_initrd.sh 시간의 거의 전부였고(GL-M1) 이 cpio는 38MB다.
INPUTS="$(cat guest_firmware.sh vendor_firmware.sh | sha256sum | cut -d' ' -f1)"
if [ -f "$OUT" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$INPUTS" ]; then
  echo "vendor_firmware: firmware.cpio.gz matches the list, skipping"
  exit 0
fi

mkdir -p "$CACHE"
fetch "$LF_URL" "$LF_TARBALL" "$LF_SHA256"
fetch "$REGDB_URL" "$REGDB_TARBALL" "$REGDB_SHA256"
fetch "$SOF_URL" "$SOF_TARBALL" "$SOF_SHA256"

. ./guest_firmware.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# tarball 안의 이름은 버전이 붙은 디렉터리 아래에 있다. 목록의 출처 이름을
# 그 디렉터리로 바꿔 tar에게 풀 것만 알려 준다. tar는 목록에 있는데 archive에
# 없는 이름을 만나면 실패로 끝난다 — 그것이 목록이 낡은 것을 잡는 자리다.
# 압축은 tar가 파일을 보고 고른다(xz 둘 · gz 하나).
declare -A ROOT=([linux-firmware]="linux-firmware-${LF_VERSION}"
                 [wireless-regdb]="wireless-regdb-${REGDB_VERSION}"
                 [sof-bin]="sof-bin-${SOF_VERSION}")
declare -A TARBALL=([linux-firmware]="$LF_TARBALL" [wireless-regdb]="$REGDB_TARBALL"
                    [sof-bin]="$SOF_TARBALL")
for origin in linux-firmware wireless-regdb sof-bin; do
  for entry in "${GUEST_FIRMWARE[@]}"; do
    src="${entry%%:*}"
    case "$src" in "$origin"/*) echo "${ROOT[$origin]}/${src#*/}" ;; esac
  done | sort -u > "$WORK/$origin.list"
  tar -xf "$CACHE/${TARBALL[$origin]}" -C "$WORK" -T "$WORK/$origin.list"
done

# 목록의 쌍대로 initrd 안의 자리에 놓는다. 한 원본이 두 자리로 갈 수 있다
# (ath11k WCN6855 hw2.1).
mkdir -p "$WORK/root"
for entry in "${GUEST_FIRMWARE[@]}"; do
  src="${entry%%:*}" dest="${entry#*:}"
  origin="${src%%/*}"
  mkdir -p "$WORK/root/$(dirname "$dest")"
  cp "$WORK/${ROOT[$origin]}/${src#*/}" "$WORK/root/$dest"
  chmod 0644 "$WORK/root/$dest"
done

# initrd.cpio와 같은 형식(newc)과 압축(gzip -6)이다. 커널은 이어 붙인 cpio를
# 차례로 푼다(WL design 실측 9).
(cd "$WORK/root" && find . | cpio -o -H newc --quiet) | gzip -6 > "${OUT}.tmp"
mv "${OUT}.tmp" "$OUT"
echo "$INPUTS" > "$STAMP"
echo "vendor_firmware: ${#GUEST_FIRMWARE[@]} files, $(stat -c %s "$OUT") bytes"
