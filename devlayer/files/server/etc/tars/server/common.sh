# shellcheck shell=sh # /etc/tars/services/<서버>가 source한다(실행하지 않는다).
# TARS 개발 도구 층 server — 서비스 템플릿 다섯의 공통 준비(TP-M11 plan 결정 A · D).
#
# init은 서비스를 root로 띄운다(SV design 결정 3). 템플릿은 root인 동안 자리를 만들고, 마지막에 서버를 TARS 사용자(uid 1000)로
# exec한다 — 서비스 계정은 없다(사용자 결정 2026-11-08).
#
#   데이터   /var/lib/<서버> -> /home/.tars/var/<서버>   /var는 RAM이라 부팅마다 링크를 다시 건다. 실체는 p3(/home)에 남는다.
#   설정     /etc/tars/server/의 원본(묶음의 것, 부팅마다 이 모양) + /config/<서버>.d/의 조각(사람의 것, 남는다)
#   로그     stdout · stderr 그대로 — init 콘솔(시리얼)로 간다. 파일은 만들지 않는다.

TARS_VAR=/home/.tars/var

# uid 1000 줄에서 이름 · gid · 홈. init이 부팅마다 /etc/passwd에 더한다(login.zig).
tars_user() {
  line=$(awk -F: '$3 == 1000 { print; exit }' /etc/passwd)
  if [ -z "$line" ]; then
    echo "$SERVER: no user with uid 1000 in /etc/passwd"
    exit 1
  fi
  TARS_NAME=$(echo "$line" | cut -d: -f1)
  TARS_GID=$(echo "$line" | cut -d: -f4)
  TARS_HOME=$(echo "$line" | cut -d: -f6)
}

# tars_data <표준 경로>: 실체 $TARS_VAR/$SERVER를 사용자에게 주고 표준 경로를 그리로 링크한다.
tars_data() {
  std="$1"
  real="$TARS_VAR/$SERVER"
  if [ ! -d /home/.tars ]; then
    echo "$SERVER: /home/.tars is missing (no installed disk?)"
    exit 1
  fi
  mkdir -p "$real" || exit 1
  chown "1000:$TARS_GID" "$real" || exit 1
  if [ -L "$std" ]; then
    [ "$(readlink "$std")" = "$real" ] && return 0
    rm -f "$std" || exit 1
  elif [ -d "$std" ]; then
    # 비어 있으면 치운다. 무언가 있으면 손대지 않는다 — 사람이 직접 둔 것이다.
    if ! rmdir "$std" 2>/dev/null; then
      echo "$SERVER: $std is a non-empty directory; move it to $real yourself"
      exit 1
    fi
  fi
  mkdir -p "$(dirname "$std")" || exit 1
  ln -s "$real" "$std" || exit 1
}

# 사람의 조각 자리. root 것이다 — 사람은 sudo로 쓴다.
tars_confdir() {
  mkdir -p "/config/$SERVER.d" && chmod 755 "/config/$SERVER.d" || exit 1
}

# 기계별 자체 서명 인증서(결정 D). 없을 때 한 번 만든다. 기본 설정은 쓰지 않는다 — tars-help devtools가 쓰는 줄을 보인다.
#
# init은 켜진 서비스를 한꺼번에 띄운다 — 템플릿 여럿이 동시에 여기 온다. key와 cert를 각자의 임시 디렉터리에 함께 만들고
# 디렉터리째 한 번에 옮긴다(`mv -T`는 차 있는 디렉터리 위로 옮기지 못한다). 먼저 옮긴 하나만 남고, 짝이 섞이지 않는다.
TARS_SSL=/config/ssl/tars-selfsigned
tars_selfsigned() {
  [ -e "$TARS_SSL/cert.pem" ] && return 0
  host=$(cat /proc/sys/kernel/hostname 2>/dev/null)
  [ -n "$host" ] || host=tars
  mkdir -p /config/ssl && chmod 755 /config/ssl || return 0
  tmp=/config/ssl/.new.$$
  rm -rf "$tmp"
  mkdir "$tmp" || return 0
  if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
      -subj "/CN=$host" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:$host" \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null &&
    chown "0:$TARS_GID" "$tmp/key.pem" && chmod 640 "$tmp/key.pem" && chmod 644 "$tmp/cert.pem" &&
    chmod 755 "$tmp"; then
    if mv -T "$tmp" "$TARS_SSL" 2>/dev/null; then
      echo "$SERVER: generated a self-signed certificate in $TARS_SSL"
      return 0
    fi
  else
    # 인증서는 서버가 서는 데 필요하지 않다 — 한 줄만 남기고 계속 간다.
    echo "$SERVER: could not generate $TARS_SSL"
  fi
  rm -rf "$tmp"
}

# 공통 준비 전부. 템플릿은 SERVER를 정하고 이것을 부른 뒤 자기 일을 한다.
tars_prepare() {
  tars_user
  tars_data "$1"
  tars_confdir
  tars_selfsigned
}

# tars_run <명령> <인자>...: 사용자로 사용자 몫의 일 하나(초기화 등). 실패하면 그 rc.
tars_run() {
  setpriv --reuid=1000 --regid="$TARS_GID" --init-groups \
    env HOME="$TARS_HOME" USER="$TARS_NAME" LOGNAME="$TARS_NAME" "$@"
}

# tars_exec <명령> <인자>...: 사용자로 서버를 exec한다. 감독은 init이 이 프로세스를 그대로 본다.
tars_exec() {
  exec setpriv --reuid=1000 --regid="$TARS_GID" --init-groups \
    env HOME="$TARS_HOME" USER="$TARS_NAME" LOGNAME="$TARS_NAME" "$@"
}
