# 게스트에 도구를 넣기 전에 그 비용을 재는 방법

2026-09-13, NW-M0에서 세웠다. UT가 도구 65개를 넣을 때 쓴 절차를 한 단계 더
밀어 붙인 것이고, 이 저장소에서 게스트 도구를 다시 저울질할 때마다 쓴다.

## 왜 필요한가

패키지의 `Installed-Size`는 우리가 치를 비용이 아니다. 우리는 패키지를
설치하지 않고 바이너리 하나를 initrd에 복사하며, 딸려 오는 것은
`copy_lib_deps`가 `DT_NEEDED`를 재귀로 따라간 만큼이다. 그 둘이 양쪽으로
어긋난다.

- 적게 잡히는 쪽. `dhcpcd-base`는 `libssl3t64`와 `libudev1`을 요구하지만
  `dhcpcd` 바이너리가 부르는 것은 `libcrypto.so.3`와 `libc.so.6` 둘뿐이고
  둘 다 이미 있다. 실제 비용이 388KB에 새 라이브러리 0개다.
- 많이 잡히는 쪽. `curl` 바이너리의 `DT_NEEDED`는 세 줄뿐인데
  (`libcurl.so.4` · `libz.so.1` · `libc.so.6`) 재귀로 따라가면 새 라이브러리가
  20개에 10,927,904바이트다. 도구 넷을 넣었을 때 늘어난 13MB의 86%가 이
  하나다.

그래서 `readelf -d`의 첫 줄만 보고 판단하면 양쪽으로 다 틀린다.

## 절차

1. 닫힘을 구한다. `apt-get download`는 의존을 안 따라오므로 네 패키지만
   받으면 `make_initrd.sh`가 없는 SONAME을 찍고 그 자리에서 죽는다.

   ```bash
   apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
     --no-breaks --no-replaces --no-enhances <패키지들>:amd64 \
     | grep '^[a-z0-9]' | sed 's/:amd64$//' | sort -u
   ```

2. 스테이징에 풀고 없는 것만 sysroot에 더한다. `dpkg -x`로 sysroot에 바로
   풀면 기존 파일(특히 libc)을 덮을 수 있다.

   ```bash
   for d in /tmp/debs/*.deb; do dpkg -x "$d" /tmp/stage; done
   cp -an /tmp/stage/. "$AMD64_SYSROOT"/
   ```

   컨테이너를 `--rm`으로 버리므로 이미지는 안 바뀐다. Dockerfile을 고쳐
   이미지를 다시 굽는 비용은 실제로 도구를 넣기로 정한 뒤에 치른다.

3. initrd를 실제로 만들어 before/after를 잰다. 압축 크기 · 푼 크기 ·
   `.so` 개수 셋을 다 적는다.

4. 도구별로 귀속한다. 재귀 `DT_NEEDED` 닫힘을 도구마다 따로 구하고, baseline
   initrd에 없던 SONAME만 센다. 귀속의 합이 initrd 증가분과 맞는지 확인한다 —
   NW-M0에서 13,025,248 대 13,029,376으로 4,128바이트(cpio 패딩) 차이였다.

## 크기를 잴 때 밟는 함정 둘

`stat -c %s`를 sysroot의 `.so`에 쓰면 심볼릭 링크 자체의 크기가 나온다.
`libbpf.so.1`이 15바이트로 나오는 식이다. `stat -Lc %s`를 쓰거나, 더 나은
방법으로 initrd 안의 파일을 잰다 — `cp`가 링크를 따라가서 거기 있는 것이
실체다.

macOS에서 `cpio -tv`의 크기는 5번째 필드다(`-rw-r--r-- 1 root wheel 983720`).
경로만 남기려고 `sed 's|.*/||'`를 줄 전체에 걸면 크기까지 지워진다.

## 도구가 sysroot에 있는 이름과 사람이 치는 이름이 다를 수 있다

`dpkg -x`는 alternatives 링크를 안 만든다. `/usr/bin/nc`는 sysroot에 없고
실체는 `nc.traditional`이다. `vi`·`editor`·`pager`도 같은 자리이고
`make_initrd.sh`가 그 셋에 링크를 직접 걸고 있다.

## `/usr/sbin`에 사는 도구는 이름으로 못 부른다

게스트 `PATH`가 `/usr/bin:/bin`이다(`environ.zig`의 `PATH_ENTRY`, UT-M0
결정 1). `dhcpcd`는 sysroot에서 `usr/sbin/dhcpcd`라, 그대로 넣으면 게스트에서
`Unknown command`가 난다. `install_tool`이 `src:dest` 쌍을 받으므로
`usr/sbin/dhcpcd:usr/bin/dhcpcd`로 적어 `/usr/bin`에 놓는다 — `PATH`를
넓히는 것보다 작은 변경이고, 도구를 전부 `/usr/bin`에 모으는 기존 결과
결이 같다.

관련: [[project_userland_tools]] · [[project_guest_network]]
