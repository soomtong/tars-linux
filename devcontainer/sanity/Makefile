# ZM-M3: 컨테이너가 arm64가 되면서 네이티브 gcc로는 x86 코드를 못 만든다.
# 크로스 툴체인(gcc-multilib-x86-64-linux-gnu)을 쓴다. -m32/-m16과
# `ld -m elf_i386`은 그대로다 — 32비트 코드 생성 능력은 multilib 쪽 패키지가
# 준다.
CC := x86_64-linux-gnu-gcc
LD := x86_64-linux-gnu-ld

CFLAGS  := -m32 -ffreestanding -fno-pic -fno-stack-protector -Wall -Wextra -std=gnu11 -O2
ASFLAGS := -m32
LDFLAGS := -m elf_i386 -T linker.ld -nostdlib

all: sanity.elf

boot.o: boot.S
	$(CC) $(ASFLAGS) -c boot.S -o boot.o

kmain.o: kmain.c
	$(CC) $(CFLAGS) -c kmain.c -o kmain.o

sanity.elf: boot.o kmain.o linker.ld
	$(LD) $(LDFLAGS) -o sanity.elf boot.o kmain.o

clean:
	rm -f boot.o kmain.o sanity.elf

.PHONY: all clean
