# TARS 개발용 진입점 — 빌드 순서를 사람의 손에서 빼앗아 한 줄로 만든다.
#
# 여기서 하는 일은 저장소의 스크립트를 부르는 것뿐이다. 순서와 staleness
# 판정은 그 스크립트들에 있다(kernel/build.sh가 .config 해시를 보는 것,
# terminal/prepare.sh가 vendor 산출물을 건너뛰는 것). 그 판정을 여기서 다시
# 구현하면 두 벌이 되고, 둘이 어긋났을 때의 증상은 부팅 뒤에 나온다.
#
# 컨테이너에서 도는 것과 호스트에서 도는 것이 갈리는 이유:
#
#   컨테이너  커널 빌드 도구 · amd64 sysroot · zig · mkfs.ext2 · xorriso ·
#             limine 빌드. 전부 devcontainer/Dockerfile이 굽는다. ZM-M3부터
#             컨테이너가 arm64라 게스트용 바이너리는 sysroot에서만 온다.
#   호스트    QEMU 하나. 화면 창은 호스트의 것이라야 뜬다 — 컨테이너의
#             qemu로는 cocoa 창이 안 열린다.
#
# 게이트(check.sh)와 겹치지 않는다. 게이트는 판정이고 여기는 개발 중에 자주
# 치는 것이다. 인자 없는 make는 help를 찍는다.

CONTAINER   ?= tars-devcontainer
DOCKER      ?= docker

QEMU        ?= qemu-system-x86_64
QEMU_MEM    ?= 1024
QEMU_EXTRA  ?=
ISO         ?= out/tars.iso

# 오래 쓰는 설정 디스크. 게이트의 out/config.img와 이름을 나눈 이유가 있다 —
# 게이트는 매 회차 그 이미지를 새로 굽는 것이 검증의 일부이고(첫 부팅의
# seeding 경로를 매번 밟는다), 이쪽은 부팅 사이에 남아야 한다(별칭·히스토리·
# `git config --global`이 여기 쌓인다). README의 손 절차와 같은 이름이다.
CONFIG_DISK ?= out/tars-config.img

# 화면 창은 호스트에 따라 다르다. macOS는 cocoa, 그 밖은 gtk.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
QEMU_DISPLAY ?= -display cocoa
else
QEMU_DISPLAY ?= -display gtk
endif

# 시리얼은 기본이 지금 터미널이다. 로그를 남기려면
#   make boot-qemu QEMU_SERIAL='-serial file:/tmp/tars.log'
QEMU_SERIAL ?= -serial stdio

# 설정 디스크를 안 붙이려면 CONFIG_DISK= (빈 값)으로 둔다. 그 부팅은
# `tars-init: no disk labelled tars-*`를 찍고 /config가 initrd 안의 빈
# 디렉터리로 남는다 — 씨앗이 하나도 안 깔리는 경로이고, 그 경로도 볼 때가
# 있다(README의 "디스크가 없으면 시리얼에 이렇게 나오고"가 그것이다).
#
# 콤마가 든 값이라 $(if)에 직접 못 넣는다 — 함수 인자는 콤마로 갈리므로
# 변수 하나에 담아 참조한다.
DISK_ARGS = -drive file=$(CONFIG_DISK),if=virtio,format=raw
ifeq ($(strip $(CONFIG_DISK)),)
DISK_ARGS =
DISK_GUARD = @echo "설정 디스크 없이 띄운다 (CONFIG_DISK가 비어 있다) — 씨앗이 안 깔린다"
else
DISK_GUARD = @test -f $(CONFIG_DISK) || { echo "$(CONFIG_DISK)가 없다 — make disk"; exit 1; }
endif

# 컨테이너 안에서 한 줄을 돌린다. 게이트의 체인들이 docker run에 넘기는
# 것과 같은 모양이다(저장소 전체를 /workspace에 붙인다).
IN_CONTAINER = $(DOCKER) run --rm -v "$(CURDIR)":/workspace -w /workspace $(CONTAINER) bash -c

.DEFAULT_GOAL := help
.PHONY: help container kernel init terminal initrd iso disk disk-fresh boot-qemu run-qemu gate check shell clean

# 도움말의 백틱은 이스케이프한다. recipe는 셸이 읽으므로 안 하면 그 자리가
# 명령 치환이 되고, `make`가 조용히 /bin/sh를 부른다(help에서 실제로 그랬다).
help:
	@echo "TARS — make가 아는 전부. 컨테이너가 필요한 것은 컨테이너 안에서, QEMU만 호스트에서 돈다"
	@echo
	@echo "빌드 (부르는 스크립트가 순서와 staleness 판정을 갖고 있다. 여기서 다시 구현하지 않는다)"
	@echo
	@echo "  make kernel"
	@echo "      kernel/build.sh. 커널 6.18.42를 tarball에서 풀어 make한다. .config와 그"
	@echo "      스크립트의 해시가 산출물 옆에 적힌 것과 같으면 make를 아예 안 부르고 1초에 끝난다"
	@echo
	@echo "  make init"
	@echo "      init/zig build. PID 1이다. ReleaseSafe로 굳는다(build.zig) — Debug 11.7MB를"
	@echo "      3.3MB로 줄인 것이 부팅 시간에 반영됐다"
	@echo
	@echo "  make terminal"
	@echo "      terminal/prepare.sh. vendor 셋(stb_truetype · ghostty lib-vt · unifont)을"
	@echo "      준비하고 zig build. ghostty-src는 트리가 없을 때만 받으므로 첫 회차에만"
	@echo "      네트워크가 필요하다"
	@echo
	@echo "  make initrd"
	@echo "      위 셋을 기다린 뒤 kernel/make_initrd.sh. 게스트 도구 75개와 셸 셋, 폰트를"
	@echo "      모아 40MB cpio를 gzip -6으로 17MB로 만든다(약 10초)"
	@echo
	@echo "  make iso"
	@echo "      initrd 뒤에 boot/build.sh(limine을 -B로 다시 빌드한다 — 배포 tarball의 실행"
	@echo "      파일은 호스트 아키텍처 것이라 컨테이너가 바뀌면 못 쓴다)와 boot/make_iso.sh"
	@echo "      (xorriso). ISO 하나가 BIOS와 UEFI를 둘 다 태운다. 증분이면 13초"
	@echo
	@echo "설정 디스크 ($(CONFIG_DISK)) — 게스트가 기억하는 자리"
	@echo
	@echo "  make disk"
	@echo "      없을 때만 만든다(16MiB, ext2, 라벨 tars-config). 있으면 그대로 둔다 —"
	@echo "      별칭·히스토리·git 설정·XDG 데이터가 그 안에 쌓이고, 지우면 그게 사라진다."
	@echo "      게이트의 out/config.img와 이름을 나눈 이유가 이것이다(게이트는 매 회차 새로 굽는다)"
	@echo
	@echo "  make disk-fresh"
	@echo "      지우고 다시 굽는다. 첫 부팅이 tars.conf와 씨앗 넷(rc 셋 + gitconfig)을 깐다."
	@echo "      그 파일들에 직접 더해 둔 줄은 함께 사라진다"
	@echo
	@echo "실행"
	@echo
	@echo "  make boot-qemu"
	@echo "      iso와 disk를 만든 뒤 QEMU로 띄운다. 화면 창 + 시리얼이 이 터미널. Ctrl+C로 끝난다."
	@echo "      게스트가 못 뜨면 시리얼의 tars-init: 줄이 진단의 전부다"
	@echo
	@echo "  make run-qemu"
	@echo "      빌드 없이 방금 만든 것으로 띄운다. 게스트 안의 설정만 고칠 때 빠르다"
	@echo
	@echo "게이트 (판정. 컨테이너 안에서 돈다)"
	@echo
	@echo "  make check CHAIN=x"
	@echo "      체인 하나만 돌린다. x는 boot terminal config input power device render"
	@echo "      copy hangul machine tools net 중 하나. 대개 2~8분이고, 그 체인이 스스로"
	@echo "      빌드하므로 무엇을 고쳤든 그 체인만 다시 돌리면 된다"
	@echo
	@echo "  make gate"
	@echo "      루트 check.sh — 12체인을 각각 3회. 16~35분(호스트 부하에 따라 흔들린다)."
	@echo "      시작할 때 out/을 통째로 지우므로 설정 디스크를 out/ 밖에 두거나"
	@echo "      CONFIG_DISK로 이 파일을 따로 잡아 둬라"
	@echo
	@echo "그 밖"
	@echo
	@echo "  make help"
	@echo "      이 목록. 인자 없는 make가 이걸 부른다"
	@echo
	@echo "  make container"
	@echo "      devcontainer/에서 tars-devcontainer를 굽는다. 없으면 다른 타깃들이 알아서"
	@echo "      부른다. 커널 도구·amd64 sysroot·zig·mkfs.ext2·xorriso가 전부 그 안에 있다"
	@echo
	@echo "  make shell"
	@echo "      컨테이너 셸. sysroot 안을 들여다보거나 게스트용 바이너리를 그 자리에서"
	@echo "      시험할 때 쓴다. 저장소는 /workspace에 붙어 있다"
	@echo
	@echo "  make clean"
	@echo "      빌드 산출물을 지운다: kernel/build init/zig-out init/.zig-cache terminal/zig-out"
	@echo "      terminal/.zig-cache out. 설정 디스크는 옆으로 옮겼다 되돌린다(날아가면 다시"
	@echo "      만들 수 없는 물건이다). terminal/ghostty-src · vendor · zig-pkg와"
	@echo "      boot/limine-binary는 안 지운다 — 앞의 셋은 네트워크가 있어야 복구된다"
	@echo
	@echo "변수 (예: make boot-qemu QEMU_MEM=2048)"
	@echo
	@echo "  QEMU_MEM=$(QEMU_MEM)"
	@echo "      게스트 메모리. 128이면 부팅이 안 된다 — initramfs가 tmpfs라 84MB가 RAM에 남고,"
	@echo "      커널이 \`System is deadlocked on memory\`로 죽는다(UT-M2 실측: 256부터 뜬다)"
	@echo
	@echo "  QEMU_DISPLAY=$(QEMU_DISPLAY)"
	@echo "      화면 창. macOS는 cocoa, 그 밖은 gtk. \`-display none\`이면 창 없이 돈다"
	@echo
	@echo "  QEMU_SERIAL=$(QEMU_SERIAL)"
	@echo "      시리얼이 지금 터미널로 온다. \`-serial file:/tmp/tars.log\`로 두면 로그가 남고,"
	@echo "      나중에 \`grep tars-init: /tmp/tars.log\`로 진단한다"
	@echo
	@echo "  QEMU_EXTRA=$(QEMU_EXTRA)"
	@echo "      QEMU 줄 끝에 그대로 얹힌다. 게이트와 같은 장치로 보려면"
	@echo "      QEMU_EXTRA='-vga none -device virtio-gpu-pci'"
	@echo
	@echo "  CONFIG_DISK=$(CONFIG_DISK)"
	@echo "      붙일 설정 디스크. 게스트가 기억하는 자리다. 빈 값(CONFIG_DISK=)이면"
	@echo "      안 붙인다 — 그 부팅은 씨앗 없이 뜨고 /config가 빈 채로 남는다."
	@echo "      이미지를 컨테이너가 굽기 때문에 저장소 안 경로여야 한다(예: out/tars-verify.img)"
	@echo
	@echo "  ISO=$(ISO)"
	@echo "      부팅할 ISO. boot/check.sh는 ISO 대신 -kernel/-initrd로 직접 띄운다"
	@echo
	@echo "  CONTAINER=$(CONTAINER)"
	@echo "  DOCKER=$(DOCKER)"
	@echo "      이미지 이름과 docker 실행 파일. 다른 태그를 쓰려면 여기를 덮는다"

# 이미지가 없으면 굽는다. 첫 사람만 겪는 일이고, 없을 때 docker run이 내는
# 메시지("Unable to find image ... locally")는 무엇을 해야 하는지 안 알려준다.
container:
	@$(DOCKER) image inspect $(CONTAINER) >/dev/null 2>&1 || { \
	  echo "devcontainer/에서 $(CONTAINER)를 굽는다 (처음 한 번, 몇 분)"; \
	  $(DOCKER) build -t $(CONTAINER) devcontainer/; }

kernel: container
	$(IN_CONTAINER) 'cd kernel && ./build.sh'

init: container
	$(IN_CONTAINER) 'cd init && zig build'

terminal: container
	$(IN_CONTAINER) 'cd terminal && ./prepare.sh'

# 셋을 다 기다린다. make_initrd.sh가 셋의 산출물을 전부 복사하기 때문이다
# (커널 bzImage는 안 쓰지만 init은 `zig build`의 결과이고 terminal은
# prepare.sh의 것이다 — 순서를 여기 적어 두는 것이 이 타깃의 전부다).
initrd: kernel init terminal
	$(IN_CONTAINER) 'cd kernel && ./make_initrd.sh'

# limine을 소스에서 다시 빌드한다(-B). boot/build.sh의 주석이 그 이유를 적고
# 있다 — 배포 tarball의 실행 파일은 호스트 아키텍처의 것이라 컨테이너가
# 바뀌면 못 쓴다.
iso: initrd
	$(IN_CONTAINER) 'cd boot && ./build.sh && ./make_iso.sh'

$(CONFIG_DISK):
	$(IN_CONTAINER) 'mkdir -p out && truncate -s 16M $(CONFIG_DISK) && mkfs.ext2 -F -q -m 0 -L tars-config $(CONFIG_DISK)'
	@echo "$(CONFIG_DISK)를 만들었다 (16MiB, ext2, 라벨 tars-config) — 첫 부팅이 tars.conf와 씨앗 넷(rc 셋 + gitconfig)을 깐다"

# 붙일 디스크가 없으면(CONFIG_DISK=) 둘 다 할 일이 없다. recipe 줄마다 셸이
# 갈리므로 한 줄 안에서 `exit 0`을 써야 다음 줄이 안 돈다 — 그 대신
# 조건부 정의로 갈랐다.
ifeq ($(strip $(CONFIG_DISK)),)
disk disk-fresh:
	@echo "CONFIG_DISK가 비어 있다 — 굽지 않는다"
else
disk:
	@test -f $(CONFIG_DISK) \
	  && echo "$(CONFIG_DISK)가 이미 있다 (새로 구우려면 make disk-fresh)" \
	  || $(MAKE) --no-print-directory $(CONFIG_DISK)

disk-fresh:
	@rm -f $(CONFIG_DISK)
	@$(MAKE) --no-print-directory $(CONFIG_DISK)
endif

# QEMU는 호스트에서 돈다. 없을 때 QEMU가 내는 메시지는 이 타깃이 무엇을
# 하려던 것인지에 대해 아무 말도 안 하므로 셋을 먼저 확인한다.
run-qemu:
	@command -v $(QEMU) >/dev/null 2>&1 || { echo "PATH에 $(QEMU)가 없다 (macOS: brew install qemu)"; exit 1; }
	@test -f $(ISO) || { echo "$(ISO)가 없다 — make iso 또는 make boot-qemu"; exit 1; }
	$(DISK_GUARD)
	$(QEMU) -m $(QEMU_MEM) \
	  -cdrom $(ISO) \
	  $(DISK_ARGS) \
	  $(QEMU_DISPLAY) $(QEMU_SERIAL) $(QEMU_EXTRA) -no-reboot

# 빌드가 끝난 뒤에 띄운다. `boot-qemu: iso disk run-qemu`로 적으면 -j에서
# 셋이 동시에 시작해 낡은 ISO로 부팅할 수 있다.
boot-qemu: iso disk
	@$(MAKE) --no-print-directory run-qemu

gate: container
	$(IN_CONTAINER) './check.sh'

# 체인 하나. CHAIN을 안 주면 무엇을 줄지 알려주고 멈춘다 — 조용히 루트
# 게이트를 돌리면 16분을 기다린 뒤에야 잘못 친 것을 알게 된다.
check: container
	@test -n "$(CHAIN)" || { echo "make check CHAIN=<chain> — boot terminal config input power device render copy hangul machine tools net"; exit 1; }
	@test -x "$(CHAIN)/check.sh" || { echo "$(CHAIN)/check.sh 가 없다"; exit 1; }
	$(IN_CONTAINER) 'cd $(CHAIN) && ./check.sh'

shell: container
	@$(DOCKER) run --rm -it -v "$(CURDIR)":/workspace -w /workspace $(CONTAINER) bash

# 지우는 것이 게이트의 clean()과 같다. 다른 점이 하나 있다 — 게이트의
# clean()은 out/을 통째로 지우는데 여기서는 오래 쓰는 설정 디스크를 먼저
# 옆으로 옮긴다. 그 이미지는 사용자의 것이고(별칭·히스토리·git 설정),
# 날아가면 다시 만들 수 없는 종류다.
clean:
	@mv -f $(CONFIG_DISK) .tars-config.img.keep 2>/dev/null || true
	@rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
	@mkdir -p out
	@mv -f .tars-config.img.keep $(CONFIG_DISK) 2>/dev/null || true
	@echo "지웠다: kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out"
	@echo "안 지웠다: terminal/ghostty-src terminal/vendor terminal/zig-pkg boot/limine-binary"
	@echo "           (앞의 셋은 네트워크가 있어야 복구되고, limine-binary는 다시 빌드된다)"
	@test -f $(CONFIG_DISK) && echo "살렸다: $(CONFIG_DISK)" || true
