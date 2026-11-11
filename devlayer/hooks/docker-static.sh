#!/usr/bin/env bash
# Docker의 static tarball을 묶음 뿌리에 깐다 — manifest.toml의 `hook = "docker-static"`(CE-M2 plan 확인한 것).
#
#   docker-static.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/docker-29.9.3)>
#
# 푸는 것은 다른 upstream 줄과 같다(맨 위 디렉터리 docker/를 벗긴다). 하나를 싣지 않는다: ctr(containerd의 진단용 CLI, 23MB).
# dockerd도 docker도 부르지 않고, 묶음을 실은 ISO가 GitHub release의 2GiB 한도에 닿아 있다(CE design 확인 8). tarball의 목록이
# 아는 여덟과 다르면(판이 바뀌었으면) 멈춘다 — 새 실행 파일을 말없이 싣거나 빠뜨리지 않는다.
set -euo pipefail

tarball="${1:?usage: docker-static.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
dest="${root}/${dir}"

want="containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
[[ -d "${work}/docker" ]] || { echo "not a docker static tarball (no docker/)" >&2; exit 1; }
have="$(find "${work}/docker" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')"
[[ "${have% }" == "${want}" ]] || { echo "docker/ holds '${have% }', expected '${want}' (new docker version?)" >&2; exit 1; }
rm "${work}/docker/ctr"

mkdir -p "${dest}"
cp -a "${work}/docker/." "${dest}/"
echo "left out ctr"
