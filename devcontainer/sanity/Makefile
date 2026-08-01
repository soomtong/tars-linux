CC := gcc
LD := ld

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
