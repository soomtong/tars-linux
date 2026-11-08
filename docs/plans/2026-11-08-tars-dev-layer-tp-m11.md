# TP-M11 — 서버(서비스): 켜면 부팅마다 뜨고, 데이터 · 설정이 재부팅을 넘는다

> 2026-11-08, `4d213c3` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP-M10이 실은 서버 다섯(postgres · mysql · redis · nginx · caddy)을 SV(Boot Services)의 서비스로 켤 수 있게 한다. 켠 서버는 부팅마다 뜨고,
데이터는 `/home`에, 사람이 덧붙인 설정은 `/config`에 있어 재부팅 · 갱신을 넘는다. 함께: 기계별 자체 서명 인증서와 시스템 신뢰(사용자 2026-11-08 "둘 다").

원래 방향(TP design "닫은 것(2026-11-07)", 기억 `project_server_persistence`): (a) 데이터는 표준 경로를 지키고 실체만 `/home` 쪽으로, (b) 설정은 `/etc` 원본을 두고
`/config/<서버>.d`를 덧붙여 읽게, (c) 로그는 stdout으로 init 콘솔.

사용자 결정(2026-11-08, 조사 결과를 보고 — 셋 다 추천대로):
- 서버는 TARS 사용자(uid 1000)로 돈다. 서비스 계정을 만들지 않는다.
- (a)의 링크 · 디렉터리 · 첫 초기화는 서비스 템플릿 스크립트가 한다 — init 코드 0줄(SV design 결정 1 · 2의 원칙). 앞서 권한 "init의 범용 장치"를 뒤집었다.
- 켜고 끄는 명령은 `tars-service enable|disable <이름>`.

## 착수 전 확인 (2026-11-08)

1. SV(`docs/specs/2026-09-27-tars-boot-services-design.md`): 서비스 하나는 `/config/services.d/<이름>` 실행 파일 하나(결정 2), init이 부팅 때 읽어 root로 띄우고
   감독한다(재시작 1초, 빠르게 셋이면 포기 — 결정 3 · 4). 출력은 물려받은 콘솔 — (c)는 이미 이 장치의 기본이다. 기본은 아무것도 안 뜬다(결정 5). 상한 8개(`services.MAX`).
   sshd가 선례다: initrd의 템플릿 `/etc/tars/services/sshd`가 호스트 키를 `/config/ssh/`에 한 번 만들고 `exec sshd`(결정 6), `tars-config ssh on`이 링크를 만든다
   (`init/src/config_front.zig`의 `SSHD_LINK`).
2. 부팅 순서(`init/src/main.zig`): `/home`(1240) → 묶음 겹치기 · 묶음 `etc/` 복사(1243) → 쓰기 가능한 `/usr/local`(1245) → `services.discover`(1490).
   그래서 server 묶음의 `etc/tars/services/<서버>`가 `services.d`를 읽기 전에 `/etc`에 있다.
3. reload(`docs/specs/2026-10-07-tars-config-reload-design.md` 결정 11): `tars-config reload`가 `services.d`를 다시 읽어 새 이름은 빈 칸에 띄우고, 사라진 이름은
   멈춘다(`config_off`). 사람이 `tars-service stop`한 것은 그대로. 그래서 enable = 링크 + reload, disable = 링크 지우기 + reload로 새 감독 장치가 없다.
4. 덧붙이기(b) — trixie 컨테이너, 서버마다 include 자리가 빈 디렉터리 · 없는 디렉터리 · 파일 하나일 때:
   nginx `include /x.d/*.conf` 셋 다 통과, redis 설정 파일의 `include /x.d/*.conf` 셋 다 통과(파일의 `maxmemory 64mb`가 적용됨), caddy `import /x.d/*.caddy`
   셋 다 `Valid configuration`, mysql `!includedir /x.d` — 빈 디렉터리는 통과, 없는 디렉터리는 `Fatal error in defaults handling`으로 멈춘다(템플릿이 먼저 만든다 —
   그리고 사람이 손으로 띄울 때 읽는 `conf.d/tars.cnf`에는 이 줄을 두지 않는다).
5. `/config`는 p2 256MiB ext2(HP design 결정 1) — 설정 조각의 자리다. 데이터는 `/home`(p3 ext4, 나머지 전부).
6. 사용자 셋(postgres · mysql은 root로 안 뜬다): 게스트에 `setpriv`가 있다(devtools 체인의 `as_tars`가 쓴다). 사용자 줄은 init이 부팅마다 `/etc/passwd`에 uid 1000으로
   더한다(`init/src/login.zig` · `account.zig`). 1024 아래 포트는 root만 열 수 있다 — 사용자로 도는 nginx · caddy는 8080 · 8081.
7. 시스템 신뢰: CA 묶음 `/etc/ssl/certs/ca-certificates.crt`는 `make_initrd.sh`가 mozilla 인증서를 이어 붙여 굽는다(526~541줄) — `/etc`는 부팅마다 initrd의 그것이다.
   `mkcert -install`은 `update-ca-certificates`가 PATH에 있으면 `/usr/local/share/ca-certificates/`에 CA를 쓰고(sudo) 그 명령을 부른다(TP-M10 덧붙임 3에서 봤다 —
   TARS에는 그 명령이 없다). `/usr/local`은 쓰기 가능하고 재부팅에 남는다(TP-M4).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 템플릿 다섯: server 묶음의 `devlayer/files/server/etc/tars/services/{postgres,mysql,redis,nginx,caddy}`(sh, 0755). 모양은 sshd와 같다 — 준비하고 끝에 `exec`.
   공통 준비는 `etc/tars/server/common.sh`(템플릿이 source):
   - 사용자: `/etc/passwd`의 uid 1000 줄(이름 · 홈). 없으면 한 줄 찍고 `exit 1`(SV의 "빠르게 셋이면 포기"가 받는다).
   - 데이터: `/home/.tars/var/<서버>`를 만들고 uid 1000에 준다. 표준 경로에서 그리로 링크 — `/var/lib/postgresql` · `/var/lib/mysql` · `/var/lib/redis` ·
     `/var/lib/nginx` · `/var/lib/caddy`. `/var`는 RAM이라 부팅마다 템플릿이 다시 건다(이미 있으면 그대로).
   - 설정: `/config/<서버>.d/`를 만든다(root, 0755 — 사람은 sudo로 쓴다).
   - 끝: `exec setpriv --reuid=1000 --regid=1000 --init-groups env HOME=<홈> USER=<이름> <서버> …`. 출력은 stdout · stderr 그대로(c).
B. 서버마다(설정 원본은 `etc/tars/server/`, 사람의 조각은 `/config/<서버>.d/`):
   - postgres: 데이터 `/var/lib/postgresql/18/main`(Debian의 자리 그대로). 없으면 `initdb --auth-local=trust --auth-host=trust`(사용자 = 슈퍼유저, 개발 기계 —
     `listen_addresses`는 기본 localhost)와 `postgresql.conf` 끝에 `include_dir '/config/postgresql.d'` 한 줄. `exec postgres -D … -k /tmp`(PGHOST=/tmp와 만난다).
   - mysql: 데이터 `/var/lib/mysql`, 없으면 `mysqld --initialize-insecure`. `exec mysqld --defaults-extra-file=/etc/tars/server/mysql.cnf`(datadir · `!includedir /config/mysql.d`).
     소켓 · secure-file-priv는 TP-M10의 `conf.d/tars.cnf` 그대로.
   - redis: `exec redis-server /etc/tars/server/redis.conf` — `dir /var/lib/redis`, `bind 127.0.0.1 -::1`, `daemonize no`, `logfile ""`, `include /config/redis.d/*.conf`.
   - nginx: `exec nginx -p /var/lib/nginx -e stderr -c /etc/tars/server/nginx.conf -g 'daemon off;'` — 기본 사이트 `:8080`(`/usr/share/nginx/html`), `include /config/nginx.d/*.conf`.
   - caddy: `exec caddy run --adapter caddyfile --config /etc/tars/server/Caddyfile` — `admin off`, 기본 사이트 `:8081`(`respond`), `import /config/caddy.d/*.caddy`,
     `XDG_DATA_HOME=/var/lib/caddy`(caddy가 인증서 · 상태를 두는 자리도 남는 쪽으로).
C. `tars-service enable|disable <이름>`(`init/src/service_cli.zig`): enable은 `/etc/tars/services/<이름>`이 실행 파일인지 보고 `/config/services.d/<이름>` 링크를 만든 뒤
   init에 reload를 보낸다(`tars-config reload`와 같은 요청) — 답에 그 이름이 띄워졌는지 찍는다. disable은 링크를 지우고 reload. root만(EX_NOPERM 77 — 소켓이 root 0600).
   템플릿이 없는 이름은 64로 알려 주고 있는 템플릿 이름을 보인다. `tars-config ssh on`은 그대로 둔다(같은 링크를 만든다 — `tars-service enable sshd`와 같은 결과).
D. 기계별 자체 서명 인증서: `etc/tars/server/common.sh`의 함수 하나 — `/config/ssl/tars-selfsigned.{crt,key}`가 없으면 server 묶음의 `openssl`로 한 번(SAN localhost ·
   127.0.0.1 · 호스트 이름, 10년), key는 0640 root:<사용자 그룹>. 서버 템플릿 다섯이 시작할 때 부른다(sshd가 호스트 키를 만드는 자리와 같다). 기본 설정은 이것을
   쓰지 않는다 — 안내가 nginx · postgres에서 쓰는 두 줄을 보인다. 사람이 신뢰까지 원하면 결정 E로 `.crt`를 넣는다.
E. 시스템 신뢰: initrd에 `update-ca-certificates`(sh, `/usr/bin` — sudo의 `secure_path`에 든다). 하는 일은 하나 — `/etc/ssl/certs/ca-certificates.crt`를
   initrd의 원본(`/usr/share/tars/ca-certificates.crt`로 옮겨 둔다) + `/usr/local/share/ca-certificates/*.crt`로 다시 쓴다. init은 `/usr/local`을 연 뒤
   그 디렉터리에 `.crt`가 하나라도 있을 때만 이 명령을 한 번 돌리고 기다린다(시한 5초 — 넘으면 한 줄 찍고 원본 그대로). 그러면 `sudo mkcert -install`이 그대로 서고
   재부팅에도 남는다.
F. 안내: `tars-help devtools` "서버" 절에 켜기 · 끄기 · 기본 포트 · 데이터와 설정의 자리 · 자체 서명 인증서 · `mkcert -install`. `tars-help services`에 enable · disable
   (FS의 `docs/help/check.sh`가 `tars-service` 하위 명령을 소스의 USAGE와 대조한다). `running-tars.md`의 서버 절.
G. design: 결정 16(서비스는 다음 milestone)을 닫는 글자, 기억 `project_server_persistence` 갱신.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. 데이터의 실체는 `/home/.tars/var/<서버>`다(사용자 홈 안이 아니다) — 사람이 실수로 지우기 어렵고 홈 백업에 섞이지 않는다. 사용자 uid가 가진다.
2. postgres의 인증은 trust(로컬 · localhost)다. 혼자 쓰는 개발 기계이고 `listen_addresses`가 localhost라 바깥은 닿지 않는다. 방화벽과 별개로 안내에 적는다.
3. 기본 포트는 nginx 8080 · caddy 8081(사용자로 돈다). postgres 5432 · mysql 3306 · redis 6379는 기본 그대로, 모두 localhost.
4. 로그 파일은 만들지 않는다 — stdout으로 init 콘솔(시리얼). 남겨야 하면 사람이 `/config/<서버>.d`에서 바꾼다(예: nginx `access_log /home/.tars/var/nginx/access.log`).
5. 기본 꺼짐(SV 결정 5) — 켜는 것은 사람이다. 에어 2011의 RAM(2~4GB)에서 다섯을 늘 띄우지 않는다.

## 할 일

1. 템플릿 다섯 + `common.sh` + 설정 원본 다섯(결정 A · B · D) — 먼저 trixie 컨테이너(사용자 uid 1000, root로 실행 → setpriv)에서 하나씩 세운다.
2. `tars-service enable|disable`(결정 C) + `service_cli`의 Zig 검사(링크 · 이름 · 템플릿 없음).
3. `update-ca-certificates`와 init의 부팅 한 번(결정 E), `make_initrd.sh`의 원본 자리.
4. 체인(devtools — 이미 설치된 디스크로 부팅을 넷 돈다):
   - 부팅 2(root 콘솔): `tars-service enable` 다섯 → 각각 응답(사용자 tars로 psql · mysql · redis-cli · curl 8080 · 8081), 데이터 하나씩 쓰기(표 · 키), `/config/nginx.d`에
     조각 하나, `/usr/local/share/ca-certificates`에 mkcert CA → `update-ca-certificates` → `curl`이 `--cacert` 없이 https를 믿는다.
   - 부팅 3(재부팅): 다섯이 저절로 뜨고 부팅 2의 데이터 · nginx 조각 · CA 신뢰가 남아 있다. `tars-service disable redis` → 멈춘다.
   - 부팅 4(갱신) 뒤는 지금 그대로.
5. 빨강: (a) mysql 템플릿의 `mkdir /config/mysql.d`를 빼면 mysqld가 defaults 오류로 셋 죽고 `giving up on service mysql`. (b) init의 CA 한 번을 빼면 부팅 3의 https가
   실패. (c) 템플릿의 `/var/lib` 링크를 빼면 부팅 3에서 postgres의 표가 없다.
6. 안내 · design · 기억(결정 F · G), `make quick`, 체인 혼자, 루트 게이트.

## 판정

- 체인 부팅 2 · 3에서 다섯이 서비스로 뜨고, 부팅 3이 부팅 2의 데이터 · 덧붙인 설정 · CA 신뢰를 그대로 본다. 빨강 셋을 봤다.
- `tars-service enable|disable`이 링크와 reload로 띄우고 멈춘다. root가 아니면 77.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. 서비스 계정(사용자 결정 — TARS 사용자로 돈다).
2. 서비스 파일의 내용이 바뀐 것을 보고 다시 띄우기(reload 비목표 그대로 — `tars-service restart`).
3. 서버의 성능 · 메모리 조정, 로그 회전.
4. 1024 아래 포트(사용자로 돈다 — 결정 3).
5. 브라우저 신뢰(NSS) — TARS에 그래픽 브라우저가 없다.

## 위험

1. 체인 메모리(1GiB): 부팅 3에서 다섯이 함께 뜬다 — mysqld가 가장 크다. 모자라면 체인의 `/config/mysql.d`에 `innodb_buffer_pool_size`를 줄이는 조각(사람이 쓰는 자리 그대로).
2. 끄기: SV의 stop은 SIGTERM 뒤 3초에 SIGKILL이다. postgres의 SIGTERM은 smart shutdown(접속이 끝나길 기다린다), mysqld는 큰 버퍼면 3초를 넘을 수 있다 —
   SIGKILL이면 다음 시작이 복구를 돈다(데이터는 서지만 느리다). 체인은 부팅 3의 시작 로그에서 복구가 도는지 본다. 3초를 서비스마다 늘리는 것은 다음 일이다.
3. 서비스 수: 다섯 + sshd = 여섯, 상한 8.
4. init을 고친다(결정 E) — 부팅 경로. `.crt`가 없으면 아무것도 안 하고, 있어도 시한이 있다. 다른 체인은 그 디렉터리가 비어 있다.

## 확인한 것

## 결과
