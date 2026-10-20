---
name: project_config_persistence
description: "설정은 virtio-blk 디스크 전체의 ext2를 MS_SYNCHRONOUS로 마운트한 /config/tars.conf 하나 · 읽는 것은 PID 1뿐이고 부팅 시점에 한 번 · load의 null은 ENOENT만이라 못 읽은 파일을 덮어쓰지 않는다 · 마운트 실패 후 /config에 쓰면 tmpfs 가짜 영속성 · 영속성은 QEMU 두 번 띄우는 게이트와 2차의 'created 없음'으로만 증명된다"
metadata:
  node_type: memory
  type: project
---

Config Persistence(CP) M0~M2(2026-08-14~15)가 세웠다. 코드는
`init/src/config.zig`, 디스크는 `config/make_disk.sh`, 게이트는 `config/check.sh`다.
[[project_boot_shell_selection]]의 요청이 여기서 완성됐다.
milestone별 경과와 게이트 시간은 2026-10-20에 지웠다(커밋 이력에 있다).

```
PID 1 = tars-init
  ├─ /proc /sys /dev /dev/pts     ← 전부 메모리 위(재부팅하면 사라진다)
  └─ /config  ← /dev/vda, ext2, MS_SYNCHRONOUS
       └─ tars.conf   shell=fish|bash|zsh
```

## 저장소를 이렇게 만든 이유

파티션 테이블 없이 디스크 전체가 ext2라 게스트가 보는 이름은 `/dev/vda1`이
아니라 `/dev/vda`다(MBR/GPT 파싱은 이 단계에서 배울 대상이 아니었다). ext2는
저널이 없어서 골랐다 — 어쩌다 한 번 쓰는 설정 파일에서는 저널이 방어하는
상황이 거의 없다. FAT은 유닉스 퍼미션이 없어 마운트 옵션 잡음이 있었고,
raw 블록은 사용자가 손으로 고칠 수 없어 가장 먼저 탈락했다.

`MS_SYNCHRONOUS`가 제일 중요한 한 줄이다. 시나리오는 "설정을 고치고 전원을
끈다"이고 게이트도 쓴 직후 QEMU를 죽인다. 동기 마운트면 `write(2)`가 돌아온
시점에 이미 디스크에 있다 — `fsync`를 안 부르는 것이 실수가 아니라 이 플래그의
값어치다.

커널 config는 셋이다. `CONFIG_BLK_DEV=y`가 있어야 블록 드라이버 메뉴가 열려
`VIRTIO_BLK`이 보이고, 거기에 `CONFIG_VIRTIO_BLK=y`, `CONFIG_EXT2_FS=y`.

## 설정이 흐르는 방향 — 읽는 것은 PID 1 하나뿐

`config.zig`가 `load`/`parse`/`save`를 갖는다. libc가 없어
`linux.open/read/write/close`를 직접 쓰고, 힙이 없어 파일 전체를 4KB 스택
버퍼에 읽는다([[project_zig_c_uapi_rule]]).

`load`는 `?Config`이고 null의 뜻은 오직 ENOENT다. 그때만 first-boot
seeding(`save`)을 한다. 열기 · 읽기 · 파싱 실패는 null이 아니라 기본값을
돌려준다 — 못 읽은 파일을 덮어쓰면 사용자가 손으로 쓴 설정이 사라진다.

실행할 것은 `Child`(`kind` · `path` · `argv`, `init/src/main.zig`)가 들고 있다. 전역 변수도, `supervise`→`start`→`spawn` 인자 릴레이도
아니다. "설정은 부팅 시점에 한 번만 읽는다"를 타입으로 표현한 것이라 감독
루프는 설정을 모르고, 자식을 재시작할 때도 `Child`에 적힌 그것을 다시
띄운다([[project_init_supervisor]]).

`terminal`도 설정 파일을 읽지 않는다. `init`이 `/terminal`을 exec할 때
`argv[1]`에 셸 경로, `argv[2]`에 no-config 플래그를 싣고 `terminal`은 그것을
`pty.spawn`에 그대로 넘긴다. 파서가 두 벌이 되면 두 프로세스가 같은 파일에서
다른 답을 얻는다. 이름 → 경로 → 플래그 매핑은 `Shell` enum 한 곳뿐이다
(`fish --no-config` / `bash --norc` / `zsh -f`).

## 깨진 설정으로 부팅이 막히지 않게 하는 장치 넷

설정 파일은 사람이 손으로 고치므로 깨진 입력이 규칙이다.

1. 화이트리스트가 곧 enum이다. 값은 이름만 받고 `std.meta.stringToEnum`이
   검사한다 — `shell=/etc/passwd`가 성립하지 않고 검사 목록을 따로 둘 필요도
   없다. 경로 매핑도 같은 enum의 메서드라 이름을 더하면 switch가 컴파일
   에러를 낸다.
2. 모르는 키 · 모르는 값은 로그만 남기고 기본값으로 간다.
3. 마운트 실패는 치명적이지 않다. `-drive`가 없는 체인은 매 부팅 이 경로를
   지난다(`failed to mount ext2 at /config (errno 2)` →
   `no config storage, using defaults`). 함정은 반대쪽이다 — 마운트 실패를
   무시하고 설정을 읽으러 가면 `/config`는 initrd 안의 빈 디렉터리(tmpfs)라
   `O_CREAT`가 성공해 버리고, 재부팅하면 사라지는 가짜 영속성은 아무것도 없는
   것보다 나쁘다. 그래서 `mountFs`가 `bool`을 돌려준다.
4. 바이너리 부재 폴백. 이름이 화이트리스트를 통과해도 initrd에 그 셸이 없을
   수 있다. `access(path, X_OK)`로 미리 보지 않으면 execve가 127로 죽고 →
   1초 backoff로 세 번 재시작 → 포기 → 셸이 없는 부팅이 되고, 원인은 로그
   깊숙한 execve 한 줄뿐이다.

## 게이트: 영속성은 한 번의 부팅으로 증명할 수 없다

`config/check.sh`는 한 스크립트 안에서 QEMU를 두 번 띄운다
([[project_gate_chain_composition]]).

- `make_disk.sh`는 1차 앞에서만 부른다. 두 부팅 사이에서 다시 부르면 게이트는
  통과하면서 아무것도 증명하지 않는다. 반대로 회차마다 새로 굽지 않으면
  seeding 경로가 다시는 안 돈다(루트 `check.sh`의 `clean()`이 `out`을 지우는
  것이 이 보장의 절반이다).
- 1차 QEMU를 `kill` 후 `wait`까지 하고 2차를 띄운다. 두 QEMU가 같은 이미지를
  동시에 열면 파일시스템이 깨지고, 그 실패는 검증하려는 것과 구분이 안 된다.
- 부정 검사가 심장이다. 2차 로그에 `created`가 없어야 한다. 긍정 검사만 있으면
  "매 부팅 새로 만들어지는" 상황도 초록불이 난다.
- 게스트 안에서 타이핑한다. 호스트에서 `debugfs`로 이미지를 고치면 "게스트가
  쓴 것이 디스크에 도달했는가"(파일시스템 쓰기 + 동기 마운트)를 통째로
  건너뛴다. monitor `sendkey`는 문자가 아니라 키를 보내므로 `=`는 `equal`,
  `>`는 `shift-dot`, `/`는 `slash`이고, 그것을 문자로 되돌리는 것은
  `terminal/src/input.zig`의 keymap이다 — 게이트가 그 두 겹도 함께 검사한다.
- exec된 바이너리는 밖에서 볼 방법이 없어 `init`이
  `started console shell (pid N, /usr/bin/zsh)`처럼 경로를 찍는다. 파싱
  결과(`config shell=`)와 이 줄의 개수가 짝을 이루는지가 증명이다.

## 셸 패키징에서 알게 된 것

- Debian trixie는 usrmerge가 끝나 bash/zsh 둘 다 `/usr/bin`에 있다. initrd
  안의 자리는 우리가 정하며 `Shell.path()`와 `make_initrd.sh`가 같아야 한다.
- zsh 기능 대부분은 dlopen되는 `.so` 모듈이고 그 자리
  (`/usr/lib/x86_64-linux-gnu/zsh/<버전>`)가 바이너리에 박혀 있다 —
  라이브러리처럼 `/lib/x86_64-linux-gnu`로 모으면 안 되는 유일한 예외다.
- 모듈 38개 중 `zsh/curses`(libncursesw)와 `zsh/db/gdbm`(libgdbm)만 sysroot에
  없는 라이브러리를 요구한다. 둘 다 `zmodload`로 여는 선택적 모듈이라
  라이브러리를 더하는 대신 모듈을 뺐다.
- `/usr/share/zsh`(zsh-common, 17MB)는 넣지 않았다. 전부 fpath에서 autoload되는
  함수이고 `~/.zshrc`가 없는 게스트는 `compinit`을 부르지 않는다. 패키지는
  sysroot에 있어 필요하면 네트워크 없이 한 줄로 켠다.
- `TERM`은 커널이 PID 1에게 `HOME=/`와 함께 `TERM=linux`로 넘기고
  (`init/main.c`의 `envp_init`) `init`이 자식에게 물려준다. terminfo가 없어도
  zsh는 죽지 않았다 — 게이트가 본 것은 "죽지 않았다"까지다.

## How to apply

앞으로 생기는 설정은 `/config/tars.conf`에 키를 더하는 방식으로 얹는다 —
`Config`에 필드를 추가하고 `parse`에 `else if` 한 줄이면 되고, 기본값이 곧
"설정 파일이 없을 때의 TARS"다. 값을 동작에 잇는 코드는 부팅 시점에 한 번 읽어
넘기는 지금 구조를 따른다. 설정 스키마 버전은 의도적으로 비워 둔 자리다.

관련: [[project_boot_shell_selection]] · [[project_init_supervisor]] ·
[[project_gate_chain_composition]] · [[project_build_host_arch]] ·
[[project_zig_c_uapi_rule]]
