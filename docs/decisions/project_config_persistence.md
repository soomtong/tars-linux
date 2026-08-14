---
name: project_config_persistence
description: "TARS의 설정은 virtio-blk 디스크 전체에 얹은 ext2를 MS_SYNCHRONOUS로 마운트한 /config/tars.conf 하나다 — 설정을 읽는 것은 PID 1뿐이고 부팅 시점에 한 번만 읽으며, 깨진 설정으로 부팅이 막히지 않게 하는 장치가 넷이고, 영속성은 한 스크립트에서 QEMU를 두 번 띄우는 게이트로만 증명된다"
metadata:
  node_type: memory
  type: project
---

2026-08-14~15, Config Persistence(CP) 서브프로젝트 M0~M2. 그 전까지 TARS는
루트가 initramfs(tmpfs)뿐이라 **아무것도 기억하지 못했다.** 지금은 재부팅을
넘어 살아남는 저장소가 있고, 그 위의 설정 한 줄이 어느 셸을 띄울지 바꾼다.
2026-08-11 사용자 요청([[project_boot_shell_selection]])이 여기서 완성됐다.

```
PID 1 = tars-init
  ├─ /proc /sys /dev /dev/pts     ← 전부 메모리 위(재부팅하면 사라진다)
  └─ /config  ← /dev/vda, ext2, MS_SYNCHRONOUS
       └─ tars.conf   shell=fish|bash|zsh
```

## 저장소를 이렇게 만든 이유

**파티션 테이블 없이 디스크 전체가 ext2다.** 그래서 게스트가 보는 이름이
`/dev/vda1`이 아니라 **`/dev/vda`**다. MBR/GPT 파싱은 이 단계에서 배울 대상이
아니라고 판단했다.

**ext2를 고른 이유는 저널이 없어서다.** 저널링(ext4)은 "전원이 끊겨도
메타데이터가 일관적"을 위한 장치인데, 설정 파일을 어쩌다 한 번 쓰는 워크로드
에서는 저널이 방어하는 상황 자체가 거의 없다. FAT은 유닉스 퍼미션이 없어
마운트 옵션으로 흉내 내야 하는 잡음이 있었다. 파일시스템 없이 raw 블록에 쓰는
안은 **사용자가 `echo`로 고칠 대상이 없어서** 가장 먼저 탈락했다 — "사람이
손으로 고칠 수 있어야 한다"가 곧 "파일시스템이 있어야 한다"였다.

**`MS_SYNCHRONOUS`가 이 서브프로젝트에서 제일 중요한 한 줄이다.** 보통 파일에
쓴 내용은 page cache에만 올라가고 커널이 나중에 내려보낸다. 그런데 우리
시나리오는 "설정을 고치고 전원을 끈다"이고 게이트는 실제로 쓴 직후 QEMU를
죽인다. 동기 마운트면 `write(2)`가 돌아온 시점에 이미 디스크에 있다 —
`fsync`를 안 부르는 것이 실수가 아니라 이 플래그의 값어치다. CP-M1의 2차 부팅이
`created`를 다시 찍지 않은 것이 이 플래그가 실제로 일했다는 증거다.

커널 config는 세 줄이었다(`CONFIG_BLK_DEV=y`가 있어야 블록 *드라이버* 메뉴가
열려서 `VIRTIO_BLK`이 보인다, `CONFIG_VIRTIO_BLK=y`, `CONFIG_EXT2_FS=y`).
virtio 버스는 DF에서 GPU 때문에 이미 켜져 있었다.

## 설정이 흐르는 방향 — 읽는 것은 PID 1 하나뿐

`init/src/config.zig`가 `load`/`parse`/`save` 셋을 갖는다. libc가 없어
`std.fs`가 아니라 `linux.open/read/write/close`를 직접 쓰고, 힙이 없어 파일
전체를 4KB 스택 버퍼에 읽는다([[project_zig_c_uapi_rule]]).

**`load`가 `?Config`이고 null의 뜻은 오직 ENOENT다.** 그때만 first-boot
seeding(`save`)을 한다. 열기/읽기/파싱 실패는 null이 아니라 기본값을 돌려준다 —
**못 읽은 파일을 덮어쓰면 사용자가 손으로 쓴 설정이 사라지기 때문이다.**

CP-M2에서 그 값이 실제 동작이 될 때 택한 구조:

```zig
const Child = struct {
    kind: Kind,
    path: [:0]const u8,              // 실행할 바이너리
    argv: [3:null]?[*:0]const u8,    // execve에 그대로 넘긴다
    ...
};
```

전역 변수도, `supervise`→`start`→`spawn` 인자 릴레이도 아니라 **`Child`가
실행할 것을 들고 있다.** 코드가 짧아서가 아니라 **"설정은 부팅 시점에 한 번만
읽는다"를 타입으로 표현하기 때문이다** — 감독 루프는 설정을 아예 모르고,
자식이 죽어 재시작할 때도 `Child`에 적힌 그것을 다시 띄운다. "재시작할 때
설정을 다시 읽어야 하나?"라는 질문이 성립하지 않는다([[project_init_supervisor]]).

**`terminal`도 설정 파일을 읽지 않는다.** `init`이 `/terminal`을 exec할 때
`argv[1]`에 셸 경로, `argv[2]`에 no-config 플래그를 실어 보내고 `terminal`은
그것을 `pty.spawn`에 그대로 넘긴다. 파서가 두 벌이 되면 두 프로세스가 같은
파일에서 **다른 답을 얻을 수 있다.** 이름 → 경로 → 플래그 매핑은 `config.zig`의
`Shell` enum 한 곳뿐이다(`fish --no-config` / `bash --norc` / `zsh -f`).

## 깨진 설정으로 부팅이 막히지 않게 하는 장치 넷

설정 파일은 사람이 손으로 고치는 물건이므로 **깨진 입력이 예외가 아니라
규칙**이다.

1. **화이트리스트가 곧 enum이다.** 값은 이름(`fish`/`bash`/`zsh`)만 받고
   `std.meta.stringToEnum`이 검사한다 — `shell=/etc/passwd`가 애초에 성립하지
   않고, 검사 목록을 따로 유지할 필요도 없다. 경로 매핑도 같은 enum의 메서드라
   이름을 추가하면 switch가 컴파일 에러를 낸다.
2. **모르는 키·모르는 값은 로그만 남기고 기본값으로 간다.**
3. **마운트 실패는 치명적이지 않다.** BF·TF 체인은 `-drive`가 없어 매 부팅 이
   경로를 지난다(`failed to mount ext2 at /config (errno 2)` →
   `no config storage, using defaults`). 반대로 **마운트 실패를 무시하고 설정을
   읽으러 가면 안 된다** — `/config`는 initrd 안의 빈 디렉터리(tmpfs)라
   `O_CREAT`가 성공해 버리고, 그건 재부팅하면 사라지는 **가짜 영속성**이라
   아무것도 없는 것보다 나쁘다. 그래서 `mountFs`가 `bool`을 돌려준다.
4. **바이너리 부재 폴백(CP-M2).** 이름이 화이트리스트를 통과해도 initrd에 그
   셸이 없으면 실행되지 않는다. `access(path, X_OK)`로 미리 보지 않으면
   execve가 127로 죽고 → 1초 backoff로 세 번 재시작 → 포기 → **셸이 하나도 없는
   부팅**이 되고, 원인은 로그 깊숙한 execve 한 줄뿐이다.

## 게이트: 영속성은 한 번의 부팅으로 증명할 수 없다

`config/check.sh`는 **한 스크립트 안에서 QEMU를 두 번 띄운다.** 세 체인 중
유일한 모양이다([[project_gate_chain_composition]]).

- **`make_disk.sh`는 1차 앞에서만 부른다.** 두 부팅 사이에서 다시 부르면
  게이트는 통과하면서 아무것도 증명하지 않는다. 반대로 회차마다 새로 굽지
  않으면 seeding 경로가 다시는 실행되지 않는다(루트 `check.sh`의 `clean()`이
  `out`을 지우는 것이 이 보장의 절반이다).
- **1차 QEMU를 `kill` 후 `wait`까지 하고 2차를 띄운다.** 두 QEMU가 같은 이미지를
  동시에 열면 파일시스템이 깨지고, 그 실패는 검증하려는 것과 구분이 안 되는
  모양으로 나타난다.
- **부정 검사가 심장이다.** 2차 로그에 `created`가 **없어야** 한다. 긍정 검사만
  있으면 "매 부팅 새로 만들어지는" 상황도 초록불이 난다.
- **게스트 안에서 타이핑한다.** 호스트에서 `debugfs`로 이미지를 편집하는 쉬운
  길을 버린 이유는, 그러면 "게스트가 쓴 것이 디스크에 도달했는가"(파일시스템
  쓰기 + 동기 마운트)를 통째로 건너뛰기 때문이다. monitor `sendkey`는 **문자가
  아니라 키**를 보내므로 `=`는 `equal`, `>`는 `shift-dot`, `/`는 `slash`이고,
  게스트 쪽에서 그것을 문자로 되돌리는 것은 우리 코드(`terminal/src/input.zig`의
  keymap)다 — 게이트가 그 두 겹까지 함께 검사하는 셈이다.
- **exec된 바이너리는 밖에서 볼 방법이 없다.** 그래서 `init`이
  `started console shell (pid N, /usr/bin/zsh)`처럼 경로를 로그에 찍는다.
  파싱 결과(`config shell=`)와 이 줄의 개수가 **짝을 이루는지**가 CP-M2의 증명
  이었다(루트 게이트 1회에서 9:3 두 쌍).

## 셸 패키징에서 알게 된 것 (2026-08-15 실측)

- Debian trixie는 usrmerge가 끝나 bash/zsh 둘 다 **`/usr/bin`**에 있다. initrd
  안의 자리는 우리가 정하며 `Shell.path()`와 `make_initrd.sh`가 같아야 한다.
- **zsh는 바이너리 하나가 아니다.** 기능 대부분이 dlopen되는 `.so` 모듈이고
  그 자리(`/usr/lib/x86_64-linux-gnu/zsh/<버전>`)가 바이너리에 박혀 있다 —
  라이브러리처럼 `/lib/x86_64-linux-gnu`로 모으면 안 되는 **유일한 예외**다.
- 모듈 38개 중 `zsh/curses`(libncursesw)와 `zsh/db/gdbm`(libgdbm)만 sysroot에
  없는 라이브러리를 요구한다. 둘 다 `zmodload`로 불러야 열리는 선택적 모듈이라
  **모듈을 뺐다** — 라이브러리를 더하는 대신.
- **`/usr/share/zsh`(zsh-common)는 17MB라 넣지 않았다.** 전부 fpath에서
  autoload되는 함수이고 `~/.zshrc`가 없는 우리 게스트는 `compinit`을 부르지
  않는다. 패키지는 sysroot에 구워져 있어 필요해지면 네트워크 없이 한 줄로 켠다.
- **`TERM`은 원래부터 있었다.** 커널이 PID 1에게 `HOME=/`와 `TERM=linux`를
  넘기고(`init/main.c`의 `envp_init`) `init`이 자식에게 물려준다. terminfo
  데이터베이스가 없어도 zsh는 죽지 않았다 — 다만 게이트가 본 것은 "죽지
  않았다"까지이고, 화면에서 실제로 써 보기 전까지 이 숙제는 열려 있다.

**How to apply:** 앞으로 생기는 설정(폰트 크기·색상·키바인딩)은 전부
`/config/tars.conf`에 키를 더하는 방식으로 얹는다 — `Config` 구조체에 필드를
추가하고 `parse`에 `else if` 한 줄이면 되고, 기본값이 곧 "설정 파일이 없을 때의
TARS"다. 값을 실제 동작에 잇는 코드는 **부팅 시점에 한 번 읽어 넘기는** 지금
구조를 따른다. 게스트에서 설정을 바꾸는 명령(`tars-config`)·재부팅 시그널
처리·설정 스키마 버전은 **의도적으로 비워둔 자리**다. 관련:
[[project_boot_shell_selection]], [[project_init_supervisor]],
[[project_gate_chain_composition]], [[project_build_host_arch]],
[[project_zig_c_uapi_rule]]
