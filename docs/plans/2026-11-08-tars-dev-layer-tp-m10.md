# TP-M10 — 서버(실행 파일): postgresql · mysql · nginx · redis · caddy

> 2026-11-08, `dc90c98` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design의 도구 목록 "서버" 줄(nginx · caddy · postgresql 18 · mysql 9.7 LTS · redis)의 실행 파일을 새 묶음 `server`(열째)에 싣는다.
design 결정 1의 종류 `vendor-repo`(도구 쪽이 운영하는 Debian 저장소)를 처음 세운다. 판정은 묶음마다의 것 — 망 없이 사용자로 서버를 띄워 응답을 받는다.

이 milestone이 하지 않는 것: 서버의 데이터 · 설정 · 로그가 재부팅을 넘는 장치, 서비스로 띄우기(`tars-service`) · 서비스 계정 · 첫 시작의 초기화.
그것은 서버(서비스) milestone의 몫이다(TP design "닫은 것(2026-11-07)", 기억 `project_server_persistence`). 이 milestone의 서버는 사용자가 손으로 띄우고,
데이터 경로를 `~` 아래로 준다.

사용자 결정(2026-11-08, 조사 결과를 보고 — 셋 다 추천대로):
- mysql은 Oracle의 trixie apt 저장소(`vendor-repo`). generic tarball(`upstream`)이 결정 1의 순서로는 앞서지만 trixie에서 서지 않는다(확인 3) — 순서의 예외 하나.
- nginx는 stable 갈래 1.30(결정 3의 "LTS가 있으면 최신 LTS"). mainline 1.31은 싣지 않는다.
- redis는 packages.redis.io의 Redis 8.10(모듈 넷 포함). Debian의 valkey가 아니다.

## 착수 전 확인 (2026-11-07 ~ 08)

받기는 호스트, 풀기 · 실행은 amd64 trixie-slim(사용자는 root 아닌 `u`). 확인 1 · 2 · 4 · 5는 `[trusted=yes]`로 판 목록만 읽었고, 서명은 확인 6에서 따로 봤다.

1. 판(trixie용, 2026-11-07의 각 저장소):

   | 서버 | 판 | 저장소 | 비고 |
   |---|---|---|---|
   | postgresql | `postgresql-18` 18.6-1.pgdg13+2 | PGDG `trixie-pgdg main` | Debian trixie 자신은 17.11. client는 `postgresql-client-18`(= 같은 판, 의존) |
   | mysql | `mysql-community-server-core` · `mysql-community-client-core` 9.7.4-1debian13 | repo.mysql.com `trixie mysql-9.7-lts` | Debian에 `mysql-server` 없음(mariadb 11.8뿐) |
   | nginx | 1.30.6-1~trixie | nginx.org `packages/debian trixie nginx`(stable) | mainline은 1.31.8, Debian은 1.26.3 |
   | redis | `redis-server` · `redis-tools` 6:8.10.3-1rl1~trixie1 | packages.redis.io `trixie main` | Debian trixie에 redis 없음(valkey 8.1.1) |
   | caddy | 2.11.9(2026-11-05) | GitHub `caddy_2.11.9_linux_amd64.tar.gz` | Debian은 2.6.2. tarball 안은 `caddy` · `LICENSE` · `README.md` |

2. 크기(새로 생긴 `/usr` · `/etc` 파일을 tar로 모아 zstd15, 차례로 깔며 잰 것): postgresql 3,658파일 131MiB → 34MiB, nginx 27파일 3 → 1MiB,
   redis 21파일 28 → 9MiB, mysql 240파일 251 → 67MiB, caddy 정적 실행 파일 하나 → 15MiB. 합 약 126MiB(base와 겹치는 perl 등은 묶음 사이 `shared`로 빠질 것).
   ISO 1.86GB에서 2GiB까지 약 285MB — 넣은 뒤 약 160MB가 남는다(AI milestone의 자리).
3. mysql generic tarball(`mysql-9.7.4-linux-glibc2.28-x86_64-minimal.tar.xz`, 83MB, 풀면 418MB — 그중 `lib/mecab` 130MB, `libmysqlclient.a` 24MB): openssl · icu ·
   krb5 · protobuf · absl은 `lib/private`(RUNPATH `$ORIGIN/../lib/private`)에 싣지만 `libaio.so.1` · `libnuma.so.1` · `libncurses.so.6`은 시스템에서 찾는다.
   trixie의 `libaio1t64`는 time64 전환으로 SONAME이 `libaio.so.1t64`라 `libnuma1` · `libncurses6`을 깔아도 `mysqld`가 `libaio.so.1: cannot open shared object file`로
   서지 않는다. 사용자 결정의 근거다. CDN에는 9.7.2 · 9.7.4가 있고 9.7.5는 아직 없다.
4. Oracle apt판: `mysql-community-server-core`의 Installed-Size 219,168KiB, 의존 libaio1t64 · libcurl4t64 · libmecab2 · libnuma1 · libssl3t64 · libtirpc3t64 ·
   `mysql-community-client-plugins` 등. 두 core를 깔면 새 패키지 30. `/usr/sbin/mysqld`, 플러그인 `/usr/lib/mysql`(115MiB). 사용자 `u`로:
   - `mysqld --no-defaults --initialize-insecure --datadir=/tmp/d` → 초기화 끝(빈 root 비밀번호 경고).
   - 그대로 띄우면 `Failed to access directory for --secure-file-priv … /var/lib/mysql-files`로 Aborting(컴파일 기본값). `--secure-file-priv=/tmp --pid-file=/tmp/p
     --socket=/tmp/s --port=3307 --mysqlx=OFF`을 주면 서고 `mysql -uroot -S /tmp/s`가 `select version()` → 9.7.4, `create database t`.
   - 로그의 `Linux Native AIO interface is not supported`는 qemu-user(OrbStack) 탓으로 본다 — InnoDB가 동기 IO로 물러나 계속 돈다. 체인(QEMU 시스템)과 실기에서 다시 본다.
5. 나머지 셋, 사용자 `u`로:
   - postgres: `/usr/lib/postgresql/18/bin/initdb -D ~/pg -A trust` → `pg_ctl -D ~/pg -o "-k /tmp -p 5433" start` → `psql -h /tmp -p 5433 -d postgres` → `PostgreSQL 18.6`.
     `/usr/bin`에는 `psql`(postgresql-client-common의 perl 래퍼 `pg_wrapper`)만 있고 `initdb` · `pg_ctl` · `postgres`는 `/usr/lib/postgresql/18/bin`(36개)에만 있다.
     컴파일 기본 소켓 자리는 `/var/run/postgresql`이다.
   - nginx: 기본 `/etc/nginx/nginx.conf`는 `user nginx` · `/var/log/nginx`를 가정한다. 사용자 설정(pid · error_log · access_log · `*_temp_path` 다섯을 홈 아래로, `listen 8080`)과
     `nginx -e <로그> -p <접두> -c <설정>`으로 섰고 `curl localhost:8080`이 응답했다. `-e`가 없으면 설정을 읽기 전에 컴파일 기본 로그 자리를 연다.
   - redis: `redis-server --port 6380 --dir ~ --daemonize yes` → `redis-cli set/get`, `redis_version:8.10.3`. 모듈 넷이 `/usr/lib/redis/modules`(`redisearch` · `rejson` ·
     `redistimeseries` · `redisbloom`).
6. 서명: 키 넷을 받아 `signed-by=`로 `trusted=yes` 없이 `apt-get update` — 네 저장소 모두 `Err` · `W:` 없이 지났다. 지문(`gpg --show-keys`):

   | 저장소 | 키 URL | 지문 |
   |---|---|---|
   | pgdg | `https://www.postgresql.org/media/keys/ACCC4CF8.asc` | `B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8` |
   | nginx | `https://nginx.org/keys/nginx_signing.key` | `8540A6F18833A80E9C1653A42FD21310B49F6B46` 외 둘(`573BFD6B…` · `9E9BE90E…`) |
   | redis | `https://packages.redis.io/gpg` | `54318FA4052D1E61A6B6F7BB5F4349D6BF53AA0C` 외 하나(`48263292…`) |
   | mysql | `https://repo.mysql.com/RPM-GPG-KEY-mysql-2025` | `BCA43417C3B485DD128EC6D4B7B3B788A8D3785C` 외 하나(`68D2DF05…`) |

   앞의 셋은 서명 없이 붙였을 때 apt가 "Missing key"로 댄 지문과 같다.
7. harvest의 부산물: `harvest.sh`는 `/usr` · `/etc`만 거두고 `passwd` · `group` · `shadow`는 싣지 않는다(줄 114) — postinst가 만드는 `postgres` · `redis` · `nginx` ·
   `mysql` 계정은 묶음에 없다. 그런데 `postgresql-18`의 postinst가 클러스터 `18/main`을 만들어 `/etc/postgresql/18/main/*`(postgresql.conf · pg_hba.conf 등 여섯)이
   생긴다 — 거두면 TARS에 없는 클러스터의 설정이 매 부팅 `/etc`로 복사된다. 데이터 쪽(`/var/lib/postgresql/18/main`)은 거두지 않는다.
8. `PATH`: TARS는 `/usr/local/bin:/usr/bin:/bin`(design 결정 20)이라 `/usr/sbin`의 `mysqld` · `nginx`는 이름으로 닿지 않는다(NW-M0 실측 3과 같은 자리).
   `redis-server` · `redis-cli` · `mysql`은 `/usr/bin`이다.
9. caddy: sha256 `5b8cb7faf8726a2028ad96a66e54e6e81e8f361bc6175e5d22bbd997cc5177fb`. 릴리스의 `caddy_2.11.9_checksums.txt`는 sha512이고 받은 파일과 같다
   (`0e85544340290a16…`).
10. docset(TP-M9 plan 확인 1의 크기): PostgreSQL 4 · MySQL 40 · Redis 213 · Nginx 1MiB, 피드에 있다. Caddy는 피드에 없다(`Caddy.xml` 404).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 종류 `vendor-repo`를 세운다. `debian` 줄과 같이 URL 자리에 패키지 이름, sha256 자리에 `apt`, 다만 패키지 이름 앞에 저장소 이름을 붙인다 — `pgdg/postgresql-18`.
   저장소는 새 파일 `devlayer/repos.tsv` 한 줄씩(이름 · apt 한 줄의 `URI suite component` · 키 파일 · 지문)이고 키는 `devlayer/keys/<이름>.asc`로 저장소에 넣는다.
   harvest가 묶음에 `vendor-repo` 줄이 있으면 그 저장소만 `signed-by=`로 붙이고 `apt-get update` 한다. 키의 지문이 `repos.tsv`와 다르면 이름을 대고 멈춘다.
   선택 키를 늘리지 않는다(다섯 그대로). 서명이 저장소를, `=판`이 패키지를 고정한다 — `debian`과 같은 검증이다.
B. 새 묶음 `server`에 일곱 줄: `postgresql-18`(pgdg) · `mysql-community-server-core` · `mysql-community-client-core`(mysql) · `nginx`(nginx, stable) ·
   `redis-server` · `redis-tools`(redis) · caddy 2.11.9 `upstream`. 의존(`postgresql-client-18` · libaio1t64 등)은 apt가 푼다.
C. 이름으로 닿게: `/usr/local/bin`에 링크 — `mysqld` · `nginx`(확인 8)와 `/usr/lib/postgresql/18/bin`의 실행 파일 전부(확인 5). `devlayer/files/server/usr/local/bin/`의
   심볼릭 링크로 둔다. 그래서 `psql`은 `pg_wrapper`가 아니라 18의 실물이 먼저 잡힌다 — 래퍼는 TARS에 없는 `/etc/postgresql`의 클러스터 목록을 읽는 장치다.
D. postgres의 클러스터 설정(확인 7)은 싣지 않는다 — harvest의 "싣지 않는 것"에 `etc/postgresql/`를 더한다(`etc/postgresql-common/`은 싣는다).
E. 사용자가 홈에서 띄우기 쉽게, 컴파일 기본값이 가리키는 없는 자리를 피하는 기본 설정을 묶음의 `/etc`에 둔다:
   - mysql `etc/mysql/my.cnf`: `[mysqld]`에 `socket=/tmp/mysql.sock` · `secure-file-priv=""`(빈 값 — 제한 없음, 개발용) · `mysqlx=OFF`, `[client]`에 `socket=/tmp/mysql.sock`.
     그러면 `mysqld --initialize-insecure --datadir=~/mysql` → `mysqld --datadir=~/mysql &` → `mysql -uroot`.
   - postgres: 시스템 rc 조각이 `PGHOST`가 비었을 때만 `/tmp`로 — `pg_ctl -D ~/pg -o "-k /tmp" start`와 `psql postgres`가 만난다.
   - nginx · redis · caddy는 기본 설정을 바꾸지 않는다. nginx의 사용자용 설정은 안내(결정 F)에 둔다.
   이 `/etc`는 매 부팅 묶음의 원본으로 돌아간다 — 사용자의 설정을 덧붙이는 자리(`/config/<서버>.d`)는 서비스 milestone이다.
F. 안내: `tars-help devtools`(`docs/help/devtools.md`)에 "서버" 절 — 다섯을 사용자로 띄우는 명령(데이터는 `~` 아래), 재부팅에 남는 것은 `~`의 데이터뿐이라는 것,
   nginx의 사용자용 설정 한 벌. `running-tars.md`의 개발 도구 절에 같은 내용을 줄여서.
G. `tars-docs` 목록에 PostgreSQL · MySQL · Redis · Nginx(확인 10, TP-M9 plan 결정 E의 약속). Redis는 213MiB라 크기를 그대로 보인다.
H. design을 고친다(16판): 결정 1의 `vendor-repo`(결정 A의 모양과 mysql의 순서 예외), 묶음 표에 `server`, 서버 줄의 판.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. 서버 다섯은 한 묶음이다 — 합 약 126MiB, 어느 하나만 쓰는 사람도 page cache라 안 쓰는 서버는 메모리를 먹지 않는다(design 위험 6).
2. 서비스 계정을 만들지 않는다(확인 7) — 사용자가 자기 이름으로 띄운다. postgres · mysql은 root로 띄우기를 거부하므로 이 길이 기본이다.
3. `mysql-community-server`(core가 아닌 것)는 싣지 않는다 — postinst가 `/var/lib/mysql`을 초기화하고 systemd 단위를 놓는 꾸러미다.
4. Redis 모듈 넷은 그대로 싣는다(9MiB 안에 든다).
5. caddy는 `exe=caddy`(tarball 맨 위에 실행 파일, `strip=0`).
6. 키를 저장소에 넣는 것은 판 고정과 같은 이유다 — 받는 기기마다 키를 망에서 다시 받으면 무엇을 믿는지가 기기마다 다를 수 있다. 저장소가 키를 바꾸면
   harvest의 `apt-get update`가 서명 실패로 멈추고, 키를 갈아 지문을 고치는 것은 TARS 버전을 낼 때 한 단계로 한다(design 결정 3).

## 할 일

1. `devlayer/repos.tsv` · `devlayer/keys/*.asc`, `manifest.sh`가 `vendor-repo`의 `<저장소>/<패키지>` 모양을 검사, `harvest.sh`가 저장소를 붙이고 지문 대조(결정 A).
2. 매니페스트: `# ── server` 머리 주석과 일곱 줄(결정 B). harvest의 `etc/postgresql/` 제외(결정 D).
3. `devlayer/files/server/`: `/usr/local/bin` 링크(결정 C), `etc/mysql/my.cnf`, rc 조각 둘(bash · zsh `etc/tars/rc.d/server.sh`, fish `etc/fish/conf.d/10-server.fish` — `PGHOST`).
4. server를 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `ISO_LAYERS` · `LAYERS` · lowerdir · 묶음 수, `rg -n 'media util'`로 한 번 더.
5. `make dev-layers` — 숫자: server의 풀린 크기 · zstd, 거둔 패키지 수, NEEDED, 묶음 사이 `shared`. ISO 크기.
6. chroot(initrd + 묶음들, 사용자 tars)로 체인 덩이를 먼저.
7. 체인 부팅 2에 덩이 하나(사용자 tars, 망 없이, 하나씩 띄우고 끈다): postgres(`initdb` → `pg_ctl start` → `psql -Atc 'select 1'` → stop), mysql(`--initialize-insecure` →
   띄움 → `mysql -uroot -e 'select 1'` → `mysqladmin shutdown`), nginx(안내의 사용자 설정 그대로 → `curl`), redis(`redis-server --daemonize yes` → `redis-cli ping` →
   `shutdown nosave`), caddy(`caddy respond`로 한 줄 → `curl`), man 하나씩. 데이터는 모두 `~` 아래.
8. 빨강: (a) `my.cnf`를 빼면 mysql 덩이가 `secure-file-priv`의 Aborting을 이름으로 대고 멈춘다. (b) `/usr/local/bin`의 `nginx` 링크를 빼면 nginx 덩이가 `command not found`로
   멈춘다. (c) `repos.tsv`의 지문 한 글자를 바꾸면 `make dev-layers`가 저장소 이름을 대고 멈춘다.
9. `tars-help devtools` 절 · `running-tars.md` · `tars-docs` 목록(결정 F · G), `make quick`.
10. 체인 혼자 한 번, 숫자로 상한을 고친다. 루트 게이트(약 35분). design(결정 H), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, server의 NEEDED · 겹침 · 묶음 사이 검사가 지난다. 네 저장소가 서명으로 검증된다.
- 체인의 부팅 2에서 할 일 7의 덩이가 망 없이 사용자로 돈다 — 다섯 서버가 각각 응답한다. 할 일 8의 빨강 (a) · (b) · (c)를 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. 재부팅을 넘는 데이터 · 설정 · 로그, 서비스로 띄우기, 서비스 계정, 첫 시작의 초기화(서비스 milestone — `project_server_persistence`).
2. mysql generic tarball(사용자 결정, 확인 3).
3. 서버 docset을 싣기 — `tars-docs get`으로 망에서(TP-M9의 사용자 결정과 같다).
4. 성능 · 메모리 조정(innodb 버퍼 등). 체인은 응답만 본다.
5. GitHub release의 2GiB 한도(사용자 결정 — 미룸). 이 milestone 뒤 남는 자리는 확인 2.

## 위험

1. 체인 메모리(1GiB, 직전 MemAvailable 약 605MB): mysqld는 기본 innodb 버퍼 128MiB에 스레드가 많다. 하나씩 띄우고 끄므로 겹치지 않는다. 모자라면 체인에서만
   `--innodb-buffer-pool-size`를 줄인다.
2. TCG에서 mysql 초기화가 느릴 수 있다(컨테이너에서 약 5초, TCG는 몇 배). 체인 시간이 직전 729초에서 늘어난다 — 혼자 판에서 재고 상한을 고친다.
3. 저장소가 판을 내린다(PGDG는 옛 판을 `apt-archive`로 옮긴다). 캐시 없는 기기에서 `=판`을 못 찾으면 harvest가 패키지 이름을 대고 멈춘다 — 판을 올리는 것은 버전을 낼 때다.
   (`debian` 줄의 security 판과 같은 사정이다.)
4. 묶음이 열이 된다 — init의 상한은 16(`init/src/layers.zig`의 `MAX`).
5. `etc/mysql/my.cnf`가 initrd나 다른 묶음의 `/etc/mysql`과 겹치는지 — 지금은 없다(mariadb를 싣는 묶음이 없다). verify의 겹침 검사가 본다.

## 확인한 것

구현 중 사용자가 남은 결정을 위임했다(2026-11-08, "수면 모드로 들어갑니다. 남은 결정을 위임합니다"). 아래 2 · 3 · 4 · 5는 Claude가 맡아 정한 것이다.

1. `make dev-layers DEV_LAYERS=server`가 세 판 멈추며 고친 것(모두 harvest):
   - `ssl-cert`(postgresql-common의 의존)의 postinst가 거두기 컨테이너 안에서 자체 서명 인증서와 그 비밀 키(`/etc/ssl/private/ssl-cert-snakeoil.key`)를
     만들어 목록에 들었다 — 실으면 모든 TARS가 같은 비밀 키를 갖는다. `etc/ssl/private/` · snakeoil 인증서 · 그 해시 링크(`etc/ssl/certs/<8자리>.<n>`)를 뺀다.
     해시 링크는 컨테이너에서는 대상이 있어 "끊긴 링크" 거르기에 안 걸린다.
   - 그 결과 openssl의 `usr/lib/ssl/private -> /etc/ssl/private`가 끊겼다(verify `dangling=1`) — 같은 이유로 뺀다.
   - 묶음 사이 대조(TP-M2 결정 E): `/usr/bin/perldoc`이 server와 base에서 다르다. perl의 그 파일은 "perl-doc을 깔라"는 자리표이고 base는 perl-doc이
     divert한 진짜다. perl-doc이 깔리지 않은 거두기에서는 `usr/bin/perldoc`을 싣지 않는다.
2. 결정 A를 바꿨다 — 지문이 아니라 키 파일의 sha256을 대조한다. gpg가 거두기 컨테이너(설치 전에 아무것도 안 깐다)에도 개발 컨테이너에도 없다.
   `repos.tsv`의 셋째 열이 sha256, 넷째 열의 지문은 사람이 읽는 기록이다. 한 바이트가 바뀌어도 멈추므로 지킴은 같다. 저장소 URI는 모두 http다 —
   slim에 ca-certificates가 없다(redis만 https였고 http로도 같은 InRelease를 낸다). 내용은 Release 서명이 지킨다.
3. mysql 클라이언트: `mysql-community-client-core`에는 `mysql` · `mysqldump` 등만 있고 `mysqladmin` · `mysqlcheck` · `mysqlimport` · `mysqlshow`는
   `mysql-community-client`다(chroot 첫 판이 `mysqladmin: command not found`로 섰다). 그 줄을 더했다(+11MiB). 그것이 끄는 `mysql-common`이
   `/etc/mysql/my.cnf`(alternatives → `!includedir /etc/mysql/conf.d/`)를 놓으므로 결정 E의 설정은 `my.cnf`가 아니라 `/etc/mysql/conf.d/tars.cnf`다 —
   서비스 milestone의 "덧붙이기"(b)와 같은 모양이다.
4. 크기: server 166MiB(zstd15, 풀면 545MiB, 파일 5,065, 패키지 67) — 조사의 어림 126MiB보다 크다. perl(풀면 약 58MiB)이 base와 겹쳐 두 번 실리고
   libicu76의 데이터가 31MiB다. 같은 경로 · 같은 내용이라 허용되는 겹침이다. 줄이는 것은 2GiB 한도 결정 때의 후보로 남긴다.
5. chroot(initrd + 묶음 열을 부팅의 겹침 순서로, `--network none`, 사용자 tars): 다섯이 모두 응답했다 — postgres `select 40+2` 42(띄우고 끄기까지 5.1초),
   mysql 42, nginx(사용자 설정) 응답, redis `PONG`, caddy `respond` 응답. 이름은 `/usr/local/bin`의 링크로 닿고 `psql`은 18의 실물이다. `PGHOST=/tmp`.
   mysqld는 SHUTDOWN을 받고 1초에 끝났다(qemu-user의 `Linux Native AIO … not supported`는 동기 IO로 물러난다).
6. 빨강(할 일 8)은 체인 대신 chroot · harvest에서 봤다: (a) `tars.cnf`를 치우면 mysqld가 rc 1, 로그에 `Failed to access directory for --secure-file-priv`.
   (b) `/usr/local/bin/nginx`를 치우면 `nginx: command not found` rc 127. (c) `repos.tsv`의 mysql 키 sha256 첫 글자를 바꾸면 harvest가 rc 1로
   `devlayer/keys/mysql.asc is a4bc…, devlayer/repos.tsv says b4bc…`. 되돌리면 다시 `cached`.
7. 체인 혼자(SandyBridge · 1GiB, 망 없음): PASS, 빌드 뒤 630초(앞 판 609). 서버 덩이 — postgres 6.6초, mysql 26.5초(초기화 포함), nginx+redis+caddy+man
   3.8초 → 상한 120초(첫 판 합 약 37초의 세 배 남짓). ISO 2,034,096,128바이트 — 2GiB까지 약 113MB. 묶음 열 1,803MiB, 설치기 복사 9,859ms, overlay 75ms,
   MemAvailable 592,084kB. `harvest.sh`가 바뀌어 묶음 아홉도 다시 거뒀고 파일 수 · 크기가 모두 앞 판과 같았다(base 21,390 · 243MiB 등).
8. 안내(결정 F): TARS의 기본 셸은 fish라 heredoc이 없다 — nginx 설정은 내용을 따로 보이고 편집기로 저장하게 했다. 설정의 경로는 모두 상대 경로
   (`-p ~/nginx`가 기준 — `-e logs/error.log`도 그 자리에서 푼다, chroot로 확인)라 `$HOME`이 필요 없다. 체인의 nginx도 그 모양 그대로다.
   `tars-docs` 목록의 이름 칸을 8자에서 10자로(`PostgreSQL`). `get` 전부의 합이 약 1,000MiB가 됐다(Redis docset 213MiB).

## 결과

- 판정 셋 모두 초록. `make dev-layers` 초록(server 166MiB, 네 저장소가 키 sha256 대조 뒤 서명으로 검증), 체인 부팅 2의 덩이가 망 없이 사용자로 돈다 —
  다섯 서버가 각각 응답하고 끈다, 빨강 (a) · (b) · (c)는 chroot · harvest에서 봤다(확인한 것 6).
- 루트 게이트 한 판에 31/31, prebuild 354초 + lanes 1,455초, 31개 모두 잘린 줄 0. devtools 753초(빌드 뒤 627초), 서버 덩이 postgres 6,673ms · mysql 23,477ms ·
  나머지 3,728ms. ISO 2,034,094,080바이트. 로그 `out/gate-logs/20261107-163434`.
- 계획 밖에서 더한 것: `mysql-community-client`(확인한 것 3), harvest의 snakeoil · perldoc 자리표 제외(확인한 것 1). 결정 A는 지문 대신 키 sha256(확인한 것 2),
  결정 E의 mysql 설정은 `conf.d/tars.cnf`(확인한 것 3).
- 실기로 남긴 것: InnoDB의 native AIO가 실기 커널에서 켜지는지(qemu-user에서만 꺼짐을 봤다 — 체인 로그는 확인하지 않았다), 에어 2011(2~4GB)에서 mysqld와
  다른 서버를 함께 띄울 때의 메모리.

