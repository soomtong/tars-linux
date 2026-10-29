# 서브프로젝트를 넘어 유효한 실측 — 다시 조사하지 말 것

`docs/guides/lessons.md`(허브)에서 2026-10-26에 떼어 냈다(LS-M0). 규칙 — 줄 번호를 적지 않는다, 낡은 항목은 고치거나
지운다, 서브프로젝트 하나에만 해당하는 것은 그 design에 — 은 허브의 것을 따른다.
번호는 옮기기 전과 같다. 다른 문서의 `lessons N` · `lessons 실측 N`은 이 파일의 N번이다.


1. `Action`이나 `Keys`나 `Copy`를 건드리면 `zig build`도 함께 돌린다.
Zig가 참조되지 않는 함수를 분석하지 않아서, `readKeys`가 쓰는 `State.scrolls`
필드가 통째로 사라진 것을 `zig build test`가 두 번 놓쳤다. `input_test`는
`handleKey`만 부른다. CS-M0은 그 셋을 하나도 안 건드렸지만 `zig build && zig
build test`를 매번 함께 돌렸고, Task 4(`main.zig`만 고침)에서 그것이 유일한
안전장치였다.

2. 키의 의미를 바꾸는 것은 enum을 넓히는 것과 다른 축이다. `Copy`에
variant를 더하는 것 자체는 `input_test`를 안 깨뜨리는데, 키의 뜻이 바뀌면
그것을 보던 검사가 깨진다. 두 축을 따로 센다.

3. 그 축을 막는 것은 "모드 밖 대조군" 검사다. `input_test`의 검사 14가
`w`·`b`, 검사 21이 `/`·`?`, 검사 22가 `n`을 모드 밖에서 보아 여전히 바이트로
나가는 것을 확인한다.

4. `sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.

5. `sendkey meta_l-shift-c`가 세 키 조합을 게스트까지 옮긴다.

6. `sendkey`의 키 이름은 전부 소문자다. `sendkey F`는 없는 이름이라 QEMU가
조용히 버린다. 대문자를 치려면 `shift-f`처럼 앞에 붙인다. 공백은 `space`가
아니라 `spc`다 — SD-M0이 `space`로 한 회차를 버렸고, 증상은 에러가 아니라
글자가 붙어서 나오는 것이다(`echo sdscreen…`이 `echosdscreen…`이 됐다).
`:`도 `colon`이 아니라 `shift-semicolon`이다(PD).

7. copy 커서는 셸 커서 자리에서 시작하고, 셸 커서가 화면 밖이면 `{0, 0}`이다
(`copyEnter`). 뷰포트가 바닥이면 셸 커서가 맨 아랫줄이라
`row=46`(화면은 47줄)이 된다. "언제나 맨 아랫줄"이라고 적어 두었던 것이
2026-08-30에 틀린 것으로 드러났다 — 검색으로 뷰포트를 올려 둔 채 모드를
나갔다 들어오면 `row=0`이고, 그 자리가 하필 직전 매치라서 `/`가 그것을
건너뛴다. 검사 15의 102줄이 여기서 나왔다.

8. `copyMove`의 좌우는 줄을 넘나들지 않고 x를 0과 `cols-1`에서 멈춘다.

9. 게이트에서 col을 세려면 대상 줄을 새로 만든다. 화면에 이미 있는 줄들은
프롬프트가 섞여 있어 셀 수 없다.

10. 게이트에서 검색 이동을 볼 때는 `scroll> offset`을 더해 절대 행으로 센다.
`copy> row=`은 뷰포트 안의 행인데 `copyPlace`가 매치를 뷰포트 맨 위로
올리므로 검색에서는 늘 0이다.

11. 스크롤백 한도는 값 둘을 함께 줘야 걸린다. `bytes = null`을 함께 준다.

12. "바닥에 있다"는 `offset == total - len`이다.

13. `RenderState`에서 격자 크기를 읽으면 조용히 no-op이 된다. 새 화면으로
검사를 쓸 때는 `cells()`를 한 번 부르고 시작한다. CS-M0의 `findSpans`도 격자를
`pages`에서 읽는다.

14. 가지치기는 tracked pin을 무효로 만들지 않는다 — 살아 있는 이웃 페이지의
왼쪽 위로 옮긴다. 그래서 증상은 "조용히 엉뚱한 자리를 복사한다"이고,
`selection == null`로는 감지할 수 없다.

15. "빌드가 최신인가"를 mtime으로 판정하려는 시도는 두 번 다 실패했다.
처방은 둘 다 내용을 보는 것이다 — 입력의 sha256을 산출물 옆에 적는다.

16. 게이트 시간의 8할은 빌드였다. 부팅은 2%가 안 됐다(GL 전의 값이다 —
`type_keys`의 `sleep 0.3` 11%는 GL-M2가 없앴다). 단계별 실측값은 `project_gate_latency`의 첫 절에 있다.

17. `gzip -9`는 값을 못 하는 압축 레벨이다. initrd는 `-6`으로 만든다.

18. `terminal`도 `init`도 `ReleaseSafe`다(GL-M3). glibc fortify가 `@cImport`를 깨뜨리는
것은 맞지만 `@cDefine("_FORTIFY_SOURCE", "0")`으로 끄면 되고, 끌 자리는 한
곳이 아니라 glibc 헤더를 읽는 블록 전부다(`drm.zig` · `main.zig` · `pty.zig`).
자세한 것은 `project_zig_c_uapi_rule`에 있다.

19. 프레임버퍼 쓰기는 픽셀 수에 정비례한다 (RC-M0). 91,520픽셀과
1,024,000픽셀이 8.11 대 8.27 ns/px다. 4MB 버퍼를 통째로 훑어도 366KB만
훑을 때와 픽셀당 비용이 같으므로, "큰 영역을 한 번에 쓰는 편이 유리하다"는
가정을 세우지 않는다. 그리고 한 프레임은 `fill` 18.0 · `glyph` 1.5 ·
`bg` 0.9 · `present` 0.8밀리초로 합쳐 21.3밀리초다(TCG 위의 값).

20. 디버그 allocator가 해제한 메모리를 `0xAA`로 채운다. 라이브러리가 준 값에
`0xAA`가 보이면 그것은 "초기화 안 됨"이 아니라 "이미 해제됨"이다. CS-M0이
이것으로 `matches()`의 수명을 찾아냈다.

21. 게스트 셸에 명령을 넣으려면 `-serial stdio`에 FIFO를 물린다 (CC-M0).
QEMU monitor의 `sendkey`는 PS/2 키보드로 가므로 시리얼 콘솔의 fish에는 닿지
않는다. FIFO는 `exec 4<>`(읽기·쓰기 겸용)로 열어야 안 막히고, `-monitor
none`을 함께 줘야 QEMU가 stdio를 두 번 쓰려다 죽지 않는다. 게스트 셸이
fish라 `(...)`가 command substitution이다 — 글로브를 괄호로 감싸면 첫 경로가
명령으로 실행된다.

22. 대화형 셸은 자기에게 온 SIGTERM을 무시한다 (SD-M0 실측 2). 보낸 뒤에도
살아서 다음 명령을 실행한다. 그래서 "나갈 때 무엇을 하나"를 SIGTERM으로 재면
아무 일도 안 나는 것을 재게 된다. 죽이면서 정리 동작을 보려면 SIGHUP을 쓰거나
그 셸의 PTY 주인을 죽인다 — PTY가 닫히면 커널이 안쪽 셸에게 SIGHUP을 보낸다.
이것이 TARS에서 화면 셸과 콘솔 셸의 운명을 가른다(`terminal`이 PTY 주인이고
콘솔 셸은 닫히지 않는 `/dev/console`을 잡는다).

23. 컨테이너에 zsh도 fish도 없다 (bash 5.2.37만 있다). 대화형 셸을 재려면
`apt-get install -y zsh fish`로 넣고(zsh 5.9 · fish 4.0.2, 게스트와 같은 Debian
trixie 스냅샷) PTY를 줘야 한다 — `script -qfc "zsh -i"`에 fifo를 물리고
`exec 4<>`로 연다. `zsh -c`로는 대화형 셸의 성질을 아예 못 잰다.

24. 히스토리를 증분으로 쓰는 zsh에서는 `grep` 명령줄이 실행 전에 파일에
써진다 (SD-M0 실측 11). 그래서 판정 패턴에 앵커를 붙인다 —
`grep -c '^echo target$'`가 1이고, 앵커를 빼면 자기 명령줄까지 세어 2가 된다.
음성 검사에서는 그 차이가 0과 1이라 검사가 조용히 죽는다.

25. `sendkey`가 `$(`와 `)`를 게스트까지 옮긴다 (SD-M2 실측 17).
`shift-4`($) · `shift-9`(`(`) · `shift-0`(`)`)이고, 게이트가 명령 치환을 칠 수
있다는 뜻이다. 판정 글자를 우리가 만들 때 쓴다.

26. `wait_for_screen`은 마지막 프레임이 아니라 로그 전체를 본다
(`gate_lib.sh`). 그래서 `0`이나 `1` 같은 한 글자는 판정 글자가 못 된다 —
앞선 어느 프레임에 걸릴 여지가 있다. SD-M2의 처방은 숫자를
`echo neg$(grep -cx …)`로 감싸 `neg0`을 만드는 것이고, 실패했을 때 화면에
`neg1`이 남는 것이 덤으로 진단이 된다.

27. 게스트에 `/dev/fd`가 있다 (BH-M2가 세웠다). devtmpfs는 그 링크를 안
만들고 우리는 udev를 안 쓰므로 원래 없었고, bash의 process
substitution(`< <(…)`)이 게스트에서만 실패했다. `main.zig`의 `linkDevFd()`가
`/proc`과 `/dev`가 붙은 뒤 만든다. 이 링크를 지우면 seed의 fzf 훅이 부팅할
때마다 한 줄을 찍는다 — `config/check.sh`의 1차 부팅이 그 로그를 본다.

그 링크를 지운 사본으로 재 보면(BB 실측 13) `power` 체인의 화면에도 그 줄이
찍히는데 그 체인은 통과한다. 그 체인의 대기가 `screen>.*bash-`(프롬프트)라
앞줄에 무엇이 있어도 만족되기 때문이다. 그래서 "게이트가 밟는다"와 "게이트가
판정한다"를 같은 것으로 읽으면 안 된다.

28. `script -qfc "<셸> -i"`는 `sh -c` 래퍼를 하나 끼운다 (BH 실측 10).
그래서 자식 pid로 찾은 것에 시그널을 보내면 셸이 아니라 래퍼가 받고, 래퍼가
죽으면 `script`도 끝나 PTY가 닫히므로 결과가 전부 "SIGHUP을 받았다"로
수렴한다. SD 실측 7의 "bash는 SIGHUP에서 안 쓴다"가 이것 때문에 틀렸다.
처방은 `exec`를 넣는 것(`script -qfc "exec bash -i"`)과
`/proc/<pid>/cmdline`을 함께 찍는 것이다.

29. 시그널을 보낸 세션의 파일은 정리보다 먼저 읽는다 (BH-M0). `kill -KILL`로
PTY 주인을 치우는 것 자체가 SIGHUP을 만들어서, 정리 뒤에 읽으면 모든 케이스가
ptyclose가 된다. 그 오류를 알려 주는 것은 SIGKILL 칸이다 — 핸들러가 없는
시그널이 정리 동작을 할 수는 없으므로, 그 칸에 값이 있으면 측정이 틀린 것이다.

30. 복사해 온 `.zig-cache`는 소스 변경을 가린다 (BH-M1 실측 11).
`cp -r init /tmp/w`로 옮긴 뒤 거기서 소스를 바꿔 가며 `zig build test`를
돌리면 옛 산출물이 다시 실행된다. 에러도 경고도 없고 `PASS` 한 줄이 정상
통과와 글자 그대로 같아서, 되돌림 검증에서는 결론이 정확히 거꾸로 뒤집힌다.
처방은 복사 직후 `rm -rf .zig-cache zig-out` 한 줄이다. 같은 자리에서 소스만
바꾸는 것은 zig가 정상으로 감지하므로 회차마다 지울 필요는 없다.

31. 비대화형 bash는 `PROMPT_COMMAND`를 아예 실행하지 않는다 (BH 실측 5).
`bash -c '<줄>'`로 재면 오타 난 프롬프트 훅도 stdout·stderr가 0바이트다.
대화형 세션을 띄워 화면 바이트를 재야 하고, 오타는 프롬프트가 그려질 때마다
찍힌다. zsh의 `setopt` 오타가 기동할 때 한 번인 것과 다르다.

32. bash의 `history -a`는 직전 명령까지만 쓴다 (BH 실측 4). zsh의
`INC_APPEND_HISTORY`는 명령을 읽자마자 써서 실행 중인 명령이 이미 파일에
있는데(실측 24), bash는 `PROMPT_COMMAND`에서 돌기 때문에 자기 줄이 아직 없다.
게이트에서 파일을 세는 자리의 기대값이 이 한 칸으로 달라진다.

33. 인자 하나인 `z`는 zoxide DB를 안 본다 (BB 실측 6). 그 인자가 현재
디렉터리 아래의 실제 디렉터리면 그냥 `cd`한다 — `/`에서 `z bin`은 `/bin`으로
가고, 게스트에는 `/usr/bin`(도구들)과 `/bin`(`sh` 링크 하나)이 서로 다른
실체로 있다. 판정에 쓸 질의는 인자를 둘로 만든다(`z usr bin` · `z terminfo x`).
증상이 "훅이 안 걸려도 검사가 초록"이라 조용하다.

34. `mkfs.ext2 -d`로 설정 디스크에 파일을 미리 담을 수 있다 (IP-M2가 열었고
`power/make_disk.sh`·`hangul/make_disk.sh`가 쓴다). `tars.conf` 한 줄을 담은
디렉터리를 주면 조사용 부팅이 하나로 끝난다 — `config` 체인처럼 "1차에서
고치고 2차에서 읽는" 두 부팅이 필요 없다. `config` 체인 자신은 여전히 빈
디스크로 시작해야 한다(1차의 seeding 경로가 그 전제다).

그리고 그 두 파일을 읽으면 "어느 체인이 어느 셸로 뜨는가"를 알 수 있다.
`power`가 bash이고 `hangul`이 기본값과 다른 자판을 심는다. BB가 착수 전에
`config` 체인만 보고 "게이트에 bash 부팅이 없다"고 적었다가 끝난 뒤에
정정했다 — 셸이나 설정으로 갈리는 일을 시작할 때는 `*/make_disk.sh`를 전부
먼저 읽는다.

35. `Kconfig`에 프롬프트가 없으면 눌러도 되돌아온다 (`project_kernel_config`).
`ACPI_EC`와 `PNP_DEBUG_MESSAGES`는 둘 다 프롬프트가 있어서 CC-M0이 누른 값이
`olddefconfig`를 견뎠다. 끈 항목에 `depends on`으로 딸린 것은 심볼째 없어져
`.config`에서 줄이 사라진다 — `ACPI_EC_DEBUGFS`가 그랬다.

36. fish는 SIGTERM에 죽는다 (SL 실측 3). "대화형 셸은 SIGTERM을 무시한다"가
셋 다에 해당하지 않는다 — zsh와 bash만 그렇다. SD-M0이 zsh로만 재서 생긴
일반화였고 `project_shutdown_signals`에 정정이 달려 있다. 게스트 기본값이
fish이므로 설정 디스크 없이 뜨는 부팅의 종료는 원래부터 138밀리초였다.

37. `GRACE_SECONDS = 3`은 상한이지 실제 대기가 아니다 (SL 실측 7).
`reapAll()`의 deadline이 `monotonicSeconds() + 3`인데 그 함수가 초 단위로
자르므로, 끝까지 가더라도 실제 대기가 2~3초 사이에서 흔들린다. 관측값이
타이핑 없는 회차 2495~2506, 타이핑 둘 있는 회차 2895~2898이었다. 종료
시각의 소수부가 유일한 변수다.

38. `debugfs -R "cat <파일>" <이미지>`로 설정 디스크를 부팅 없이 읽는다
(SL-M0 측정 6). 컨테이너에 e2fsprogs 1.47.2가 있어서
`/usr/sbin/debugfs`가 선다. `config` 체인처럼 "고치고 다시 부팅해서 읽는"
두 부팅이 필요 없다 — 끈 뒤에 호스트에서 바로 본다. `ls -l /`을 함께
찍어 두면 파일 이름이 틀렸을 때 바로 갈린다.

39. 게스트 셸에 `system_powerdown`으로 종료를 걸면 타이핑이 전혀 필요 없다
(SL-M0). ACPI 전원 버튼이라 셸을 안 거치므로, 셸 셋을 도는 측정에서 셸마다
다른 명령을 찾을 필요가 없다. `power` 체인이 `kill -TERM 1`을 타이핑하는
것과 갈리는 자리이고, 그 체인이 그렇게 하는 이유는 시그널 경로 자체를
판정하기 때문이다.

40. 도구의 무게는 `Installed-Size`가 아니라 `readelf -d`로 잰다 (NW 착수
조사). 패키지 의존과 바이너리 의존이 크게 다르다. `dhcpcd-base`는
`libssl3t64`(설치 8.1MB)를 요구하지만 `dhcpcd` 바이너리는 `libcrypto.so.3`와
`libc.so.6`만 부른다 — `libssl`은 `dlopen`으로 열리는 udev 플러그인 몫이라
`copy_lib_deps`가 안 따라온다. `iproute2`도 패키지가 3.7MB에 의존 열둘인데
`ip` 하나는 여섯만 부르고 그중 셋이 게스트에 이미 있다. 반대로 `curl`은
`libcurl.so.4`가 LDAP·RTMP·brotli까지 `DT_NEEDED`에 적어 두어서 안 쓰는
것이 전부 따라온다. 판정 명령은 위 "범용 명령"에 있다.

41. 컨테이너에 `nc`·`ncat`·`socat`·`python3`·`busybox`가 없다 (NW 착수 조사).
bash의 `/dev/tcp`는 거는 것만 되고 듣지는 못한다. 들어야 하면 perl이다 — 45번,
그리고 FW-M0의 `echo.pl`이 `IO::Socket::INET`으로 TCP와 UDP를 함께 들었다. 게스트에서 컨테이너로 연결을 받아야 하면 QEMU의
`guestfwd`를 쓴다 —
`-netdev user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:cat <파일>`이면 게스트가
그 주소에 붙을 때 QEMU가 명령을 실행해 출력을 흘려 넣는다. 듣는 프로세스가
없으므로 체인이 관리할 상태가 안 늘고 QEMU가 사라지면 함께 사라진다.

42. Debian의 alternatives 링크는 `dpkg -x`로 푼 sysroot에 없다. postinst가
만드는 것이기 때문이다. `nc`(실체 `nc.traditional`)가 그렇고, UT-M3이
`pager`에서 같은 것을 겪었으며 `vi`·`editor`도 같은 자리다. `install_tool`은
없는 파일에서 죽으므로 목록에는 실체 이름을 적고, 사람이 치는 이름은
`make_initrd.sh`에 `ln -sf`로 따로 세운다.

43. 게스트 glibc는 2.41이고 `nss_files`·`nss_dns`가 `libc.so.6` 안에 있다
(NW 착수 조사. `_nss_dns_gethostbyname2_r` 심볼을 직접 확인했다). glibc
2.34부터의 변화라 `libnss_*.so.2`를 따로 안 넣어도 된다. 만약 그 이전
버전이었다면 그 파일들은 `DT_NEEDED`에 안 나와서 `copy_lib_deps`가 절대 못
잡았을 것이다 — `make_initrd.sh`가 zsh 모듈에 대해 손으로 처리하고 있는
것과 같은 종류의 구멍이다.

44. 게스트의 벽시계는 부팅 시점에 이미 호스트 시각이다 (TS-M0 실측 4).
`CONFIG_RTC_CLASS`가 꺼져 있어 `/dev/rtc0`가 없는데도 그렇다 —
`CONFIG_RTC_MC146818_LIB=y`로 x86 timekeeping이 CMOS를 직접 읽고 QEMU가 그
CMOS를 호스트 시각으로 채우기 때문이다. 게스트가 `2026-09-14T23:19:47Z`를
찍은 순간 호스트가 `23:21:51Z`였고 그 차이가 하네스가 돈 시간 전부였다.
그래서 시각과 관련된 게이트 판정은 "안 맞는 것이 맞아졌다"로 세울 수 없다 —
현실과 뚜렷이 다른 값을 우리가 만들어 넣어야 갈린다.

45. 나가는 UDP는 SLIRP을 아무 설정 없이 지난다 (TS-M0 실측 2). `hostfwd`도
`guestfwd`도 필요 없다. 게스트가 `10.0.2.2`로 보내면 컨테이너의
`127.0.0.1`에서 받고(SLIRP가 호스트를 loopback으로 NAT), 컨테이너 자신의
IP로 보내면 그 IP에서 받는다(호스트 스택을 통해 돌아온다). 길이도 내용도
안 가린다. 컨테이너에 UDP 리스너가 필요하면 perl이 있다 — 41번이 센 다섯은
전부 없지만 `perl`과 `IO::Socket::INET`은 있고, 컨테이너가 `uid=0`이라
1024 미만 포트도 바로 묶인다.

46. bash의 `read`는 datagram을 잘라 먹는다 (TS-M0 실측 3). `-N` 없는 `read`는
한 바이트씩 `read()`를 부르는데, datagram 소켓에서는 한 번의 `read()`가
datagram을 통째로 소비하고 요구한 길이 너머를 버린다. 그래서 10바이트 응답이
`got=[t] rc=142`(128+SIGALRM)로 보이고, 그 모양이 "답이 안 왔다"와 거의
구별되지 않는다. `read -r -t 3 -N 10 x <&3`이나 `head -c 10 <&3`을 쓰면
전문이 온다. TCP에서는 `-N` 없이도 맞으므로 IN이 쓴 방법을 UDP에 그대로
옮기면 안 된다.

47. 시계를 몇 년 뛰어도 게스트가 그대로 돈다 (TS-M0 실측 6). 2026년에서
2031년으로 뛴 뒤에도 셸 · dhcpcd · `eth0`의 주소 · 파일 쓰기가 전부 정상이고,
커널도 init도 한 줄을 안 찍는다. dhcpcd의 `valid_lft`가 남아 있는 것이
특히 중요하다 — 리스 만료를 벽시계로 쟀다면 즉시 만료됐을 것이다. 파일
mtime은 새 시각을 따라간다.



48. 판정의 재료를 판정 대상과 같은 파일로 두지 않는다 (LB 실측 17). 기대값을
그 기대값이 지켜야 할 파일에서 읽으면, 그 파일이 틀려도 검사가 초록이다. 체인이
"무엇을 기대하나"를 체인 자신의 변수로 갖는다(`firewall/check.sh`의 포트 변수들).

49. 컨테이너에 `sfdisk`가 없다(`perl` · `mke2fs` · `debugfs`는 있다). 파티션 표가
필요한 하네스는 MBR을 `perl`로 쓰거나(DC-M0) 게스트의 `sfdisk`를 부른다(DC-M2).

50. QEMU는 `-cdrom` 없이도 빈 CD 장치를 붙인다(DI-M0 실측 9). 그래서 게스트에
`/dev/sr0` 노드가 늘 있다 — 노드가 있는 것으로 매체를 판정하면 틀린다.
`mkfs.vfat`이 찍는 iconv 경고 세 줄은 gconv가 없어 내장 CP850 표를 쓴다는 것이고
결과는 같다.

51. raw 시리얼 로그의 줄 끝은 `\r\n`이다. 정규식에 `$`를 쓰려면 실제 CR 바이트를
넣는다(`install/check.sh`의 `CR` 상수).

52. 코드를 바꾸는 mutation은 체인이 부팅 전에 돌리는 `zig build test`가 먼저 잡을 수
있다. 게이트의 판정을 보려면 그 검사의 기대값도 함께 바꾼다. 그리고 돌리기 전에
`git diff`로 편집이 실제로 들어갔는지 본다 — `sd -F`가 Zig의 `\\`를 못 맞춘 판이
있었고(TD), 여러 줄 문자열을 조용히 못 맞춘 판도 있었다(FW-M2). 빗나가도 에러가
없다.

53. 게이트는 이스케이프 바이트를 타이핑으로 만들 수 없다 — fish → bash → `printf`를
거치며 죽는다(TQ-M1). 그런 질의는 initrd 안의 스크립트(`tq-probe`)가 보낸다. 그리고
터미널의 답은 tty가 되울려(ECHOCTL) 화면에 `^[[4;1R`처럼 나오므로, 판정 글자를 행
첫머리에 기대면 안 된다.

54. `nic` 체인 출력의 `usbnet: failed control transaction` 세 줄과
`netdev n1 has no peer`는 게스트가 아니라 QEMU의 stderr이고 해가 없다(WN 실측 18).
드라이버가 커널에 있으면 장치가 없어도 `e1000e: Intel(R) PRO/1000 …` 배너가
찍힌다 — "장치가 붙었다"는 인터페이스 이름으로 센다.

55. 첫 부팅에 `init`은 설정 디스크 후보를 한 번 훑는다. 설치된 디스크로 떴을 때만
파티션을 보고 최대 5초 기다린다(DC). ISO로 뜬 세션은 설정 없이 기본값으로 돈다
(`among 14 candidates`)는 것이 의도다. 디스크 전체가 `tars-` ext2인 스틱을 꽂아
두면 p2보다 그 스틱이 먼저 붙는다.

56. 게스트의 `/bin`에는 `sh`(bash) 하나만 산다. `#!/bin/bash` 스크립트는 execve가
`ENOENT`로 실패하고 셸은 127을 낸다 — 게스트에 심는 스크립트는 전부 `#!/bin/sh`로 쓴다
(SV-M1 실측 9). `init`의 execve 실패 줄은 SV-M2부터 errno를 찍는다. 설정 디스크의
`services.d/` 스크립트도 같다 — `#!/bin/bash`이면 `init`이 `execve … failed (errno 2)`를 세 번 찍고
포기한다(AU-M1).

57. ext2의 `getdents64`는 만든 순서를 돌려준다(SV-M1 실측 11). `debugfs`로 디스크를
심는 체인에서 "순서가 맞다"를 판정하려면 역순으로 써야 정렬이 빠진 것이 드러난다.

58. Debian의 `ncurses-term`에는 `ghostty` · `kitty`는 있어도 두 터미널이 실제로 보내는
`xterm-ghostty` · `xterm-kitty`가 없다. `infocmp -x -A <dir> ghostty`의 첫 줄에 이름을
더해 `tic -x -o`로 굽는다. 컨테이너(arm64)의 `tic`으로 구운 것이 게스트에서 그대로
읽힌다(SV 실측 14).

59. `sd -F`는 치환 문자열의 `\n`을 줄바꿈이 아니라 글자 두 개로 넣는다(DS-M1). 그리고
`sd` 1.0은 줄 단위라 패턴의 `\n`도 못 맞춘다(TC). 여러 줄로 바꾸는 편집은 python이나
perl이나 Edit로 한다.

60. `zig build test`가 `file contents changed during update`로 멈추면 편집 직후의 파일을
빌드가 읽은 것이다(DS-M1). 코드와 무관하고 다시 돌리면 된다.

61. 감독 목록에 넣은 데몬이 갈라지면 감독자는 "1초 만에 exit 0"을 세 번 보고 포기하는데,
갈라진 손자가 일을 계속해서 "일이 됐다"만 보는 검사는 전부 초록이다(DS-M2 mutation —
dhcpcd에서 `-B`를 빼도 net 검사 1~28이 초록이었다). 판정은 "쥔 pid가 곧 그 데몬인가"로
한다.

62. 커널은 initrd 자리에 이어 붙인 cpio 여럿을 차례로 풀어 한 트리로 합친다 — gzip한 것끼리
이어 붙여도 된다(WL-M0 실측 9). 그런데 `gzip -dc initrd.cpio | cpio -it`는 첫 archive의 끝
표시에서 멈춰서 뒤의 것이 목록에 안 나온다. 무선 firmware가 initrd 꼬리에 따로 붙어 있고,
`tools` 검사 1b가 꼬리를 바이트로 대조하는 이유가 이것이다. 게스트에 측정용 파일을 넣을 때도
initrd를 다시 굽지 않고 cpio 하나를 이어 붙이면 된다.

63. iwlwifi는 firmware 이름을 실행 중에 짓는다 — 칩의 MAC · stepping · RF로 접두사를 만들고
커널의 최대 API 번호부터 아래로 요청하며, `c99` 다음은 `101`이다(WL-M0 실측 3). 그래서
`modules.builtin.modinfo`의 `firmware=` 줄을 그대로 쓰면 안 되고, linux-firmware의 "가장 새
파일"(`c101`~`c107`)은 커널 6.18이 절대 요청하지 않는다. 커널이나 linux-firmware를 올리면
`kernel/guest_firmware.sh`의 iwlwifi 줄을 다시 고른다. tarball의 iwlwifi 파일은
`intel/iwlwifi/`에 있고 드라이버는 `/lib/firmware/` 맨 위를 찾는다 — 둘을 잇는 `WHENCE`의
`Link:`는 tarball에 링크로 들어 있지 않다. `regulatory.db`는 linux-firmware가 아니라
wireless-regdb에 있다.

64. x86 커널의 내장 cmdline(`CONFIG_CMDLINE`)은 부트로더 cmdline 앞에 붙고, 같은 param이 두 번
오면 뒤의 것이 이긴다(WL-M0 실측 2). 모듈이 꺼진 커널에서 게이트 전용 드라이버(hwsim)를
제품에 넣고 기본값만 끄는 길이 이것이다. hwsim은 라디오가 0이어도 `hwsim0`(type 803,
radiotap)을 만든다 — `phy80211`이 없고 dhcpcd가 안 건드린다.

65. Debian의 wpa_supplicant 2.10에는 이름 패턴으로 인터페이스를 고르는 `-M`이 없다(WL-M0 실측
5). 대신 `-g`(전역 소켓)와 `interface_add`가 있다. 이미 있는 인터페이스를 다시 넣으면 `FAIL`이고
연결은 그대로다. 명령줄 `-i`로 받은 인터페이스가 초기화 중에 사라지면 wpa_supplicant 전체가
status 255로 죽고, 다 잡은 뒤에 사라지면 같은 pid로 산다(WL 실측 13). wpa_supplicant는
`p2p-dev-wlan0`을 스스로 만든다(해는 없다).

66. dhcpcd는 새 인터페이스마다 hook을 `reason=PREINIT`으로 부르고 무선이면 `ifwireless=1`을
준다. 순서는 `PREINIT` → `NOCARRIER` → `CARRIER` → `BOUND`, 떠날 때 `DEPARTED`다(WL-M0 실측 7).
무선 인터페이스는 연결 전에는 carrier가 없고, 연결되면 dhcpcd가 아무 도움 없이 lease를 받는다.

67. hwsim 라디오를 `iw phy phyN set netns name X`로 다른 netns에 옮기면 게스트 안에 "다른 기계"가
생긴다 — root ns의 wpa_supplicant · dhcpcd가 그 인터페이스를 못 보고, 두 ns 사이의 패킷은
로컬 지름길이 아니라 hwsim의 공중을 지난다. `ip netns exec X iw phy phyN set netns 1`로 되돌리면
root ns에는 새 인터페이스가 생긴 것과 같다 — 부팅 뒤 꽂는 장치를 흉내 내는 방법이다(WL-M3).

68. 콘솔 줄에는 앞에 셸 프롬프트의 escape가, 끝에 tty의 `\r`이 붙을 수 있다. 게스트가
`/dev/console`에 찍은 줄을 판정할 때 `^` · `$` 앵커를 쓰지 않는다. 목록의 끝을 봐야 하면 찍는
쪽이 `[wlan0]`처럼 괄호로 감싼다(WL-M3).

69. 이 기계의 호스트 셸은 zsh이고 도구 환경이 몇 개를 바꿔 둔다. `$r:lib`의 `:l`은 소문자
수식어, `$s[= ]`는 배열 첨자로 읽힌다 — 셸 변수 뒤에 글자가 오면 `${r}`로 감싼다. `du`는
`dua`의 alias라 `/usr/bin/du`로 부른다(WL-M0).

70. 커널의 `scripts/config`는 심볼 이름을 대문자로 바꾼다. `MT76x0U`처럼 소문자가 섞인
심볼은 `--keep-case` 없이 켜면 없는 이름(`MT76X0U`)이 적히고 `olddefconfig`가 조용히 버린다.
켠 뒤에는 해소된 `build/.config`에 `=y`로 남았는지 반드시 센다(2026-09-28 USB 동글 측정).
AU-M0이 `ACP6x`로 같은 자리에 걸렸다 — `-k` 없이는 `ACP6X`가 적히고 조용히 사라진다.

71. 게스트의 기본 셸 fish는 작은따옴표 안에서도 `\\`를 `\` 하나로 접는다. `printf`에 백슬래시를
넘기려면 8진수 `\134`로 쓴다 — `\033`처럼 printf만 해석한다. 그리고 fish는 따옴표 문자열 전체에
구문 강조 색(`F0C674`)을 입혀서, 긴 `printf` 명령 줄 하나가 `style>` 덤프의 16셀 상한을 넘긴다.
상한을 보는 음성 검사가 있는 체인에 긴 명령을 치면 그 검사의 범위를 명령 앞으로 좁힌다
(TG-M2 · `render/check.sh`의 `IMG_LOG_START`).

72. vendor된 ghostty의 `src/terminal/c/*.zig`(C API)는 Zig 쪽에서 직접 못 쓰는 계산의 정답지다.
C 래퍼 타입을 받거나 안쪽 함수가 `pub`이 아니라 부를 수는 없지만, ghostty 앱 렌더러보다 작고
라이브러리가 스스로 검사하는 모양이다. kitty placement의 viewport 좌표는
`placement_render_info`를 옮겨 적었다(TG-M1).

73. dhcpcd는 `eth0: leased 10.0.2.15 for … seconds`를 찍은 다음에 주소를 인터페이스에 붙이고,
경로를 만들며 `eth0: adding route to 10.0.2.0/24`와 `eth0: adding default route via 10.0.2.2`를
찍는다(PE design 실측 8 — `dhcp_bind`가 로그를 먼저 찍고 `ipv4_applyaddr`를 뒤에 부른다). 그래서
`leased` 줄을 본 순간의 게스트는 아직 10.0.2.15가 아닐 수 있다. 그 사이에 hostfwd로 붙으면 SLIRP은
호스트 쪽 연결을 받아 주지만 게스트가 SYN을 버려서, `ssh-keyscan`은 빈 값을 내고 ssh는
`Connection timed out during banner exchange`로 죽는다. hostfwd로 게스트에 붙는 체인은
`eth0: adding default route via 10\.0\.2\.2` 줄까지 기다린다 — `service/check.sh`의 `boot_ssh`가
그 모양이다(PE-M0, 2026-10-04). 2026-09-28과 2026-10-04의 service 실패 둘을 처음에는 "검사가
`Server listening`만 기다리고 바로 keyscan을 친다"로 진단했는데, 그 진단이 틀렸다. `boot_ssh`는
2026-09-27(`c89157d`)부터 `leased`를 기다리고 있었고, 두 실패 다 그 기다림 뒤에 났다. 같은
모양(임대를 기다린 뒤 hostfwd)이 `firewall/check.sh`에도 있지만, 그쪽은 붙기 전에 게스트에 타이핑을
먼저 해서 그 시간 차가 지나가고 실패가 관측된 적이 없어 그대로 두었다(PE 비목표 6). SLIRP이 버려진
SYN을 언제 다시 보내는지는 재지 않았다. PE-M0 뒤에 같은 증상이 다시 나면 이 판단이 틀린 것이다 —
그 회차의 시리얼 로그에서 `adding default route` 줄과 ssh 사이에 sshd가 무엇을 찍었는지부터 본다
(PE 위험 1).

74. `vim -e`(Ex 모드)는 `TERM=xterm-256color`에서도 terminfo의 smcup(`ESC[?1049h`)을 보내 대체 화면에
들어가 거기에 찍고, 나가면서(`ESC[?1049l`) 출력이 화면에서 사라진다. 게이트가 vim의 Ex 출력
(`+scriptnames` · `+'set ts?'`)을 `screen>`으로 보려면 `vim -T dumb -e …`다 — 게스트에 `dumb` terminfo가
없어도 vim은 내장 항목으로 조용히 넘어가고 맨 아래 행부터 찍는다(PE-M2 plan 확정 1, 2026-10-04). 이것을
design 단계에서 놓친 이유는 측정에 쓴 pyte가 1049를 구현하지 않아 출력이 남아 보였기 때문이다 — pyte로
잰 화면은 대체 화면에 대해 믿지 않는다. 덤으로 둘. 게스트의 `HOME=/`에서는 `scriptnames`가 `~/.vimrc`가
아니라 `  2: /.vimrc`를 찍는다(`HOME`을 빈 디렉터리로 두고 재면 `~`로 축약된다). zsh에서 `?`를 따옴표
없이 치면(`+set\ ts?`) glob으로 펴려다 `zsh: no matches found`로 명령을 안 돌린다 — `+'set ts?'`로 감싼다.
게이트 키 이름은 `+` `shift-equal` · `'` `apostrophe` · `?` `shift-slash`.

75. 게스트의 셸 셋(zsh 5.9 · bash 5.2 · fish 4.0.2)과 vim 9.1은 전부 `ESC[?2004h`(bracketed paste)를
보내고, 셸 셋은 명령을 띄우기 전에 `ESC[?2004l`을 보낸다(PE design 실측 1, 2026-10-04). bash는
`libreadline`을 링크하지 않고 자기 안의 readline을 쓴다 — 그 문자열은 `/usr/bin/bash` 본체에 있다. zsh의
것은 본체가 아니라 ZLE 모듈 `zle.so`에 있다. fish 4.0.2는 프롬프트 내내 켜 두지 않는다 — 인자를 치기
시작하면 끄고 다음 키까지 꺼진 채이고, 감싼 두 줄을 받은 직후에도 꺼진다(PE-M1 plan 확정 2). 그리고
fish는 꼬리 `ESC[201~`가 올 때까지 붙인 글자를 하나도 그리지 않고 그동안 오는 키(Enter · ctrl-c 포함)를
전부 삼킨다(PE-M1 plan 확정 1). ghostty vt의 모드 2004는 화면별이 아니라 `Terminal.modes` 하나이고
RIS가 끈다(`vt_test` 95 · 96).

76. 핫플러그는 netlink uevent로 받는다 — 커널 config가 필요 없고 노드는 uevent가 올 때 이미 있다.
PD-M0이 `CONFIG_INOTIFY_USER`를 켰다가 `install` 부팅 7의 창이 닫혀 루트 게이트가 두 번 빨갰는데,
늦어진 0.8초의 진짜 원인은 그 옵션의 일이 아니라 코드 배치였다 — gzip `inflate_fast`가 커널 이미지
안에서 페이지 경계를 넘게 밀리면 QEMU TCG가 그 번역 블록을 직접 잇지 못해 initramfs 풀기가 2.6초에서
3.8초가 된다(`X86_INTEL_LPSS` 하나로 재현, 드라이버 초기화는 전부 5ms 아래). 실기와 무관한 게이트의
비용이고 어느 커널 변경이든 다시 움직인다. 커널을 바꾸면 System.map의 `inflate_fast` 주소 끝 세
자리와 `install` 부팅 7의 `init waited`를 본다(PD).

77. ioctl 매크로(`EVIOCGBIT` · `EVIOCGPROP` · `EVIOCGNAME` · `EVIOCGABS`)는 translate-c 패키지가
inline fn으로 넘긴다. HD 조사 6("매크로를 손으로 푼다")은 `@cImport` 시절의 사실이다(PD).

78. QEMU HMP `mouse_move dx dy [dz]` · `mouse_button N`은 `-display none`에서도 usb-mouse로 가고,
`device_add usb-mouse,id=X` · `device_del X`가 핫플러그다. 127을 넘는 이동은 보고 셋으로 쪼개지고
합이 보존되며, 휠 한 눈금에 `REL_WHEEL_HI_RES` ±120이 함께 온다. pc 머신은 PS/2 마우스를 늘 갖고
있어 `MOUSE_PS2`를 켜면 모든 pc 체인에 `ImExPS/2 Generic Explorer Mouse`가 생긴다 — `i8042.noaux`로
끈다(PD).

79. 부팅 때 `-device usb-audio`를 꽂아 둔 QEMU는 열 판 중 넷이 안 떴다(열거 누락 하나 · 시리얼 없이
선 셋). `device_add`로 부팅 뒤에 꽂은 판은 스무 번 남짓 다 0.2초 안에 열거됐다 — 게이트의 USB 장치는
부팅 뒤에 꽂는다(AU).

80. 게스트에 `od` · `xxd` · `hexdump` · `timeout` · `dd`가 없다 — 바이트는 `head -c N … | cat -v`,
파일 머리 고치기는 `printf` + `tail -c +45`(PD · VD).

81. QEMU 오디오를 게이트가 값까지 보는 수법 — `-audiodev alsa,…`에 48kHz · 2채널 · s16을 박고
`HOME="$WORK"`로 컨테이너 libasound가 `$WORK/.asoundrc`의 `file` 플러그인 둘(스피커는 `file`,
마이크는 `infile`, `slave.pcm "null"`)을 읽게 한다. `wav` 백엔드는 녹음 쪽이 없고(`Could not create a
backend for voice 'adc'`), 기본 속도 44100으로 두면 QEMU가 리샘플해 값이 바뀐다. 그리고 게이트의
오디오 시간은 게스트 시계와 다르다 — `max_seconds=30` 녹음이 게스트 시계로 23초에 끝났다. 판정은
시간이 아니라 바이트 수로(AU · VD).

82. `alsactl init`의 exit 99는 성공이다(규칙 표에 없는 카드를 범용 규칙으로 켰다). `restore`는 파일이
없으면 init을 하고도 exit 2. `-f`로 기본 경로가 아닌 파일을 주면 잠금 파일을 안 만든다. daemon 모드는
SIGTERM에 저장 없이 끝나고 SIGUSR2가 저장한다(AU).

83. `snd_pci_acp6x` · `snd_pci_ps`는 PCI 표가 `modules.builtin.modinfo`의 alias로 안 나온다 — 그
드라이버가 켜졌는지는 심볼로 본다(AU).

84. alsa-lib의 `plug`가 스테레오를 모노로 접을 때 왼쪽 채널만 가져간다 — 녹음 판정에 두 채널이 같은
값이기를 기대하지 않는다(VD).

85. 게스트의 `curl`은 `libssl`을 링크하지만 인증 기관 목록이 initrd에 없으면 https가 전부 `curl: (77)
error setting certificate file`이다. `make_initrd.sh`가 sysroot의 ca-certificates(mozilla 150장)를
`/etc/ssl/certs/ca-certificates.crt`로 이어 붙인다. 컨테이너 자신의 묶음은 OrbStack의 개발용 인증
기관 둘이 섞여 있어 안 쓴다. 게이트는 `openssl s_server`(자기 서명)에 대고 "목록을 읽었다"를 exit
60(77이 아니라)으로 본다(VD).

86. `arecord -d N`을 SIGINT로 멈추면 WAV 머리를 거의 못 고친다(스물네 판 중 스물하나가 `pcm_read …
Interrupted system call`로 머리를 그대로 둔다). 샘플은 멀쩡하다 — `tars-dictate`가 머리 44바이트를
실제 길이로 다시 쓴다(VD).

87. 게스트의 `jq`는 1.7이라 `trim`이 없다(`sub`로 strip을 정의한다). Oniguruma 정규식이라 `\p{L}` ·
`\p{N}`은 안다 — 한글이 글자여야 하는 판정은 bash + `jq`가 Zig보다 맞았다(Zig std에 유니코드 범주
표가 없다)(VD).

88. 시그널은 pid가 아니라 프로세스 그룹에 보낸다. 자식을 `setpgid`로 제 그룹에 두지 않으면
`kill(-pid)`가 `ESRCH`이고 아무도 안 죽는다 — `tars-dictate`의 `arecord`가 상한까지 녹음했고(VD-M1
mutation 2), terminal은 setsid를 안 해서 제 그룹이 없어 CT-M1부터 있던 SIGKILL 시한이 서비스에만
서고 terminal에는 안 서 있었다(TC-M3 plan 확정 2). 콘솔 셸의 tty는 `console`이 아니라 `ttyS0`이다 —
`TIOCSCTTY`가 그 밑의 장치를 주고 `pgrep -t console`은 빈다(TC).

89. 비밀번호 프롬프트의 판정은 `ECHO`가 아니라 `ICANON && !ECHO`다 — 셸의 줄 편집기와 vim은 둘을
함께 끄므로 `ECHO`만 보면 모든 프롬프트가 비밀번호다. master에 `tcgetattr`를 하면 slave의 termios를
준다(VD).

90. QEMU `sendkey meta_r`가 게스트의 `KEY_RIGHTMETA`다. hold를 안 적으면 누른 시간 7 ~ 23ms · 두
누름 사이 20ms로 사람 손과 다르다 — `sendkey meta_r 80` 둘이 누른 시간 80ms · 사이 160ms다.
`type_keys`로는 못 친다(수정키 하나는 로그가 없어 키마다 0.3초를 기다린다)(VD).

91. fzf picker를 닫은 직후의 키는 샌다 — 그 뒤에 화면을 바꾸는 명령(`reload terminal`)을 치지
않는다. config 1차의 TC-M3 검사가 Ctrl+R 검사 앞에 있는 이유다. 그리고 반쪽 패널(pane 체인 부팅
B)에서 긴 줄은 접힌다 — 판정 패턴을 한 줄 안에 두거나 `joined_screen_dump`로 본다(TC).

92. 게스트 코드(terminal · init)에 `std.debug.print`를 쓰지 않는다 — 컨테이너 Zig의 그것은(0.16에서 잰 것, 0.17도 같은 규칙)
64바이트 버퍼로 stderr를 잠그고 비워 한 줄이 write 여럿이고, 두 프로세스가 같은 콘솔에 쓰면 호출
사이가 끼어들 틈이다(TC-M3 게이트를 하룻밤에 두 번 빨갛게 했다). `logline.zig`가 한 줄을 write
하나로 보내고(2048 = 커널 tty chunk), 루트 `check.sh`가 회차마다 끼어든 줄 A · B와 잘린 줄 C를 센다.
끼어듦은 드물어(한 판 42회차에 2 ~ 8) 되돌린 치환을 런타임이 잡는 것은 운이고, 진입 검사(게스트
파일의 `std.debug.print` 0곳)가 결정적으로 지킨다(AL).

93. 게스트 패닉 trace는 Zig 0.17 · ReleaseSafe에서 파일:줄까지 나오고, `--strip-debug` 판은 `.symtab`으로 함수 이름만
(`???:?:?: 0x1190982 in main.App.dumpFrame`) 낸다. 주소는 두 판이 같고 바이너리가 non-PIE라 호스트의 `zig-out` 원본에
`x86_64-linux-gnu-addr2line -f -i -C -e …`로 그대로 풀린다 — `-i`가 게스트 trace에 없는 inline 사슬까지 낸다. libc 프레임은 어느
판이든 `???`다(Debian `.so`는 strip돼 있다). panic은 SIGABRT(signal 6)이고 init이 1초 뒤 다시 띄운다(LI-M0 실측 3).

94. 통째 경로에서 패널의 빈 칸은 패널의 기본 배경이 아니라 `MARGIN_COLOR`다(DR-M2). `cells()`가 `cp == 0 and bg == default_bg`인
셀을 안 내보내고(`vt.zig`) `renderPane`은 내보낸 셀만 칠하므로, `fill(MARGIN_COLOR)`의 색이 남는다. OSC 11로 기본 배경을 바꿔도
빈 칸은 그대로다. 부분 갱신이 행을 지우는 색이 그래서 `MARGIN_COLOR`이고, verify의 정답지도 그 경로다.

95. 커널 6.18.42의 DIRTYFB clip 처리 — virtio-gpu(`virtgpu_plane.c`)는 `drm_atomic_helper_damage_merged`로 clip 전부를 경계 상자
하나로 합쳐 그 사각형만 `transfer_to_host_2d` · `resource_flush`하고, simpledrm(`sysfb/drm_sysfb_modeset.c`)은
`drm_atomic_for_each_plane_damage`로 clip마다 `drm_fb_blit`를 한다. 둘 다 `drm_atomic_helper_dirtyfb`가 clip을 plane의
`fb_damage_clips` blob으로 바꾼다. ioctl 상한은 `DRM_MODE_FB_DIRTY_MAX_CLIPS` 256. QEMU TCG에서 clip 셋을 넘기는 DIRTYFB는 clip
없는 것보다 약 0.1ms 더 든다(0.21 → 0.32ms, DR-M2 프로브) — 옮기는 픽셀이 줄어 얻는 것은 QEMU에서 안 보인다.

96. 부분 갱신 뒤 키 하나의 그리기(DR-M2 프로브, 부팅 3회 중앙값): frame 2.45 → 1.36ms. 남은 구간은 cells 0.63(46%) · 행 하나 다시
칠하기 0.14 · 행 비교 0.03 · overlay(상태 줄 띠 1280 × 28 지우기 + 글자) 0.20 · present 0.32. `seq 1 200000`은 1135 → 1105ms로
잡음 안 — 스크롤 프레임은 모든 행이 dirty다. verify(픽셀 + 화면 흉내, 4MB 비교 둘) 한 번은 게이트 TCG에서 약 12ms(M1의 하나일 때
6~7ms).
