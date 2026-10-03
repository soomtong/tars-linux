# LB-M2 — `localhost`와 `*.localhost`가 풀린다

> 이 plan을 실행하는 사람에게: 고치는 것은 `devcontainer/Dockerfile`(패키지 한 줄과
> 층 주석) · `kernel/make_initrd.sh`(`/etc` 파일 둘과 모듈 하나)다. `init` 코드는
> 0줄이다(design 결정 5). 게이트 검사는 M3이 세운다.

Goal: `net` 설정과 무관하게 게스트에서 `localhost` · `app.localhost` ·
`a.b.localhost`가 NSS를 거쳐 `127.0.0.1`로 풀리고, 그 이름으로 `nc`가 왕복한다.

Architecture: M0 실측 7에서 손으로 한 것을 initrd가 한다. `/etc/hosts`(`127.0.0.1
localhost`) · `/etc/nsswitch.conf`(`hosts: files myhostname dns`) · 
`/lib/x86_64-linux-gnu/libnss_myhostname.so.2`. 모듈은 `dlopen` 대상이라 의존 추적에 안
잡히므로(design 확인 6) 이름으로 복사하고, 그 모듈에 `copy_lib_deps`를 돌려 의존이
빠지면 빌드가 죽게 한다 — zsh 모듈과 같은 방식이다.

Tech Stack: Dockerfile(`apt-get download`) · bash(`make_initrd.sh`) · M0 하네스 `/tmp/lb/`

---

## 결정

- M2-A 파일 둘은 저장소의 별도 파일이 아니라 `make_initrd.sh`의 heredoc이다. design
  결정 5는 "저장소에 두고 복사한다"였는데, 바로 옆의 `/etc/passwd` · `/etc/group`이
  heredoc이고, dhcpcd hook을 파일로 둔 이유(`net/check.sh`가 호스트에서 직접 돌린다)가
  이 둘에는 없다. 한 줄짜리 둘이라 이웃과 같은 모양이 읽기에 맞다. design에 이 수정을
  적는다.
- M2-B `nsswitch.conf`에는 `hosts:` 한 줄만 쓴다. 없는 데이터베이스(`passwd` · `group`
  등)는 glibc가 기본값(`files`)으로 본다. 그 가정이 틀리면 `whoami` · `id`가
  깨진다. 처음에는 "`tools` 체인이 본다"고 적었는데 틀렸다 — 그 체인은 `whoami`를
  안 친다. 그래서 Task 4 Step 2가 부팅 한 번으로 직접 본다.
- M2-C 모듈은 `find_in_sysroot`로 찾는다. 못 찾으면 빌드가 죽는다 — Dockerfile을
  안 고친 이미지로 돌리면 여기서 멈춘다. 조용히 빠진 채로 게스트가 뜨는 것보다 낫다.

## Task 1 — Dockerfile에 패키지 한 줄 (이미지 빌드 약 1분)

**Files:** Modify `devcontainer/Dockerfile` — 층 8 주석 뒤(`ENV AMD64_SYSROOT` 앞)에 층
9 주석, 다운로드 목록의 `libmd0:amd64 \` 다음에 한 줄.

- [ ] Step 1: 주석을 넣는다

```dockerfile
#
# ── LB-M2: 층 9(이름 풀이) ──────────────────────────────────────────────
#
# libnss-myhostname 하나다(LB design 결정 5). glibc가 /etc/nsswitch.conf의
# `myhostname`을 보고 dlopen하는 NSS 모듈이고, `*.localhost`를 loopback으로
# 답한다(RFC 6761). 174,288바이트 · NEEDED는 libcap.so.2와 libc뿐이라 새
# 라이브러리가 0개다(LB-M0 실측 6). dlopen 대상이라 make_initrd.sh가 이름으로
# 복사한다 — 바이너리의 DT_NEEDED를 따라가는 copy_lib_deps에는 안 잡힌다.
```

- [ ] Step 2: 목록에 한 줄을 넣는다

`        libmd0:amd64 \` 다음 줄에 `        libnss-myhostname:amd64 \`.

- [ ] Step 3: 이미지를 다시 굽고 sysroot에 있는지 본다

```bash
{ time docker build -t tars-devcontainer devcontainer/ > /tmp/lb/docker-build.log 2>&1 ; } 2>&1 | tail -3
tail -3 /tmp/lb/docker-build.log
docker run --rm tars-devcontainer ls -la /usr/local/amd64-sysroot/usr/lib/x86_64-linux-gnu/libnss_myhostname.so.2
```

기대: 빌드 성공, 파일이 174,288바이트.

## Task 2 — `make_initrd.sh`가 파일 둘과 모듈을 넣는다

**Files:** Modify `kernel/make_initrd.sh` — `/etc/group` heredoc 다음.

- [ ] Step 1: 넣는다

```bash

# LB-M2. 이름 풀이(LB design 결정 5). 셋이 한 묶음이다.
#
#   /etc/hosts          localhost 한 이름. NSS를 안 거치는 resolver(정적 Go
#                       등)도 이 파일은 읽는다
#   /etc/nsswitch.conf  hosts만 적는다. 파일 → *.localhost → DNS 순서다.
#                       안 적은 데이터베이스(passwd 등)는 glibc가 files로 본다
#   libnss_myhostname   *.localhost를 127.0.0.1로 답하는 모듈
#
# 이 셋이 없을 때 localhost는 net=dhcp에서만, SLIRP 너머 호스트 DNS가 답해
# 줄 때만 풀렸다(LB-M0 실측 4). 파일은 passwd 옆이라 같은 heredoc이다.
cat > "$WORKDIR/etc/hosts" <<'EOF'
127.0.0.1 localhost
EOF
cat > "$WORKDIR/etc/nsswitch.conf" <<'EOF'
hosts: files myhostname dns
EOF

# glibc가 nsswitch.conf의 이름을 보고 실행 중에 dlopen하는 모듈이라 어느
# 바이너리의 DT_NEEDED에도 없다 — 이름으로 복사한다. 그 모듈의 의존은
# copy_lib_deps로 따라간다(zsh 모듈과 같은 이유다: 빠진 것이 부팅 뒤 dlopen
# 때가 아니라 여기서 드러나게). 지금 NEEDED는 libcap.so.2 · libc뿐이고 둘 다
# 이미 있다(LB-M0 실측 6).
if ! NSS_MYHOSTNAME="$(find_in_sysroot libnss_myhostname.so.2)"; then
  echo "make_initrd: libnss_myhostname.so.2 not in the sysroot (rebuild the devcontainer)" >&2
  exit 1
fi
cp "$NSS_MYHOSTNAME" "${WORKDIR}${LIB_DEST}/"
copy_lib_deps "${WORKDIR}${LIB_DEST}/libnss_myhostname.so.2"
```

- [ ] Step 2: diff를 읽고 initrd를 짓는다

```bash
git diff --stat
git diff | grep '^-[^-]'
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd kernel && ./build.sh >/dev/null) && (cd init && zig build >/dev/null) &&
  (cd terminal && ./prepare.sh >/dev/null) && (cd kernel && ./make_initrd.sh >/dev/null) &&
  zcat kernel/initrd.cpio | cpio -it 2>/dev/null | grep -E "^etc/|libnss_myhostname"'
```

기대: 지운 줄 없음. `etc/group` · `etc/hosts` · `etc/nsswitch.conf` · `etc/passwd` ·
`lib/x86_64-linux-gnu/libnss_myhostname.so.2`.

## Task 3 — 부팅으로 본다 (부팅 둘, 각 약 1분)

M0 하네스에서 손으로 하던 `raise` · `nss`를 빼고 `before` · `names`만 친다. 이번
`names`가 M0의 `nss` 단계와 같은 답을 내야 한다.

- [ ] Step 1

```bash
sed -e '/^run raise/d' -e '/^run after/d' -e '/^run nss/d' /tmp/lb/boot.sh \
  | awk '/^run names/ && seen++ {next} {print}' > /tmp/lb/boot-m2.sh
chmod +x /tmp/lb/boot-m2.sh
grep '^run ' /tmp/lb/boot-m2.sh
for B in A B; do
  docker run --rm -v "$PWD":/workspace -v /tmp/lb:/tmp/lb -w /workspace \
    tars-devcontainer bash /tmp/lb/boot-m2.sh $B > /tmp/lb/run-m2-$B.log 2>&1; echo "$B exit=$?"
  grep -aoE "LBM0-(ETC|GETENT|NC) .*" /tmp/lb/guest-$B.log | tr -d '\r' | cut -c1-160
done
```

기대: `run before` · `run names` 두 줄. 두 부팅 모두 `ETC`에 `hosts nsswitch.conf`가
있고, `localhost` · `app.localhost`의 `GETENT`가 `rc=0 out=[127.0.0.1 ...]`, `NC`가
`got=[hello-…]`.

## Task 4 — 가까운 체인 둘 (약 3분)

- [ ] Step 1

```bash
for C in net tools; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash $C/check.sh > /tmp/lb/chain-m2-$C.log 2>&1; echo "$C exit=$?"
  grep -c '^FAIL' /tmp/lb/chain-m2-$C.log; tail -2 /tmp/lb/chain-m2-$C.log
done
```

기대: 둘 다 `exit=0` · `FAIL` 0줄.

- [ ] Step 2: M2-B의 가정을 직접 본다

설정 디스크 A에 `who.sh`(`whoami` · `id` · `ls -ld /`의 소유자를 `LBM0-WHO` 한 줄로
찍는다)를 더해 굽고, 하네스의 `run before`를 `bash /config/who.sh` 한 줄로 바꿔
부팅한다. 기대: `whoami=[root] id=[uid=0(root) gid=0(root) groups=0(root)]
ls=[root:root]`.

## Task 5 — design에 적고 커밋한다

- [ ] Step 1: design에 "LB-M2가 실행으로 증명한 것"(실측 12부터)과 M2-A의 수정을
  적고, `Status:`를 "M2 끝났다"로 고친다. 결정 5의 "저장소에 두고 복사한다" 문단 끝에
  "M2-A가 heredoc으로 바꿨다"는 한 줄을 덧붙인다(원문은 지우지 않는다).

- [ ] Step 2

```bash
git status --short
git diff --stat
git add devcontainer/Dockerfile kernel/make_initrd.sh \
        docs/specs/2026-09-26-tars-loopback-design.md \
        docs/plans/2026-09-26-tars-loopback-lb-m2.md
git commit -m "Close LB-M2: hosts, nsswitch.conf and myhostname resolve .localhost"
```

## 이 milestone이 끝난 자리

사람이 쓰는 모든 것이 섰다. M3이 그것을 게이트에 묶는다.
