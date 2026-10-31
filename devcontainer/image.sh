#!/usr/bin/env bash
# 컨테이너 이미지를 ghcr.io에서 받거나(pull) 굽거나(build) 올린다(push). 받은 것도 구운 것도
# 로컬 태그 tars-devcontainer에 붙이므로 `docker run … tars-devcontainer` 줄은 어디서도 안 바뀐다.
#
# 태그는 Dockerfile 내용의 sha256 앞 12자다 — 커밋이 아니다. Dockerfile에 COPY · ADD가 없어 이
# 파일 하나가 레시피 전부이고, 태그가 없다는 것이 "이 Dockerfile로는 아직 안 구웠다"를 뜻한다.
# Dockerfile을 한 줄이라도 고치면(주석도) 새 태그가 되고 main의 다음 CI가 굽고 올린다.
# 이름 · 태그를 아는 자리는 이 파일 하나다. design: docs/specs/2026-10-31-tars-ghcr-image-design.md
#
# 부르는 자리: Makefile container(pull || build), checks.yml container job(pull || build, main push면 push).
# 로그인은 하지 않는다 — CI가 docker login 뒤 push를 부른다. 로컬에서 올리는 길은 없다(PAT가 필요하다).
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE=ghcr.io/soomtong/tars-devcontainer
LOCAL=tars-devcontainer
TAG="$(shasum -a 256 devcontainer/Dockerfile | cut -c1-12)"

id_of() { docker image inspect --format '{{.Id}}' "$1" | sed 's/^sha256://' | cut -c1-12; }

case "${1:-}" in
  tag)
    echo "$TAG" ;;
  pull)
    if docker pull "$IMAGE:$TAG"; then
      docker tag "$IMAGE:$TAG" "$LOCAL"
      echo "image> pulled $TAG id=$(id_of "$LOCAL")"
    else
      echo "image> pull failed $TAG ($IMAGE) — 없거나 비공개거나 오프라인이다" >&2
      exit 1
    fi ;;
  build)
    docker build -t "$LOCAL" devcontainer/
    docker tag "$LOCAL" "$IMAGE:$TAG"
    docker tag "$LOCAL" "$IMAGE:latest"
    echo "image> built $TAG id=$(id_of "$LOCAL")" ;;
  push)
    docker push "$IMAGE:$TAG"
    docker push "$IMAGE:latest"
    echo "image> pushed $TAG" ;;
  *)
    echo "usage: devcontainer/image.sh tag|pull|build|push" >&2
    exit 2 ;;
esac
