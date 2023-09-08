include Makefile.inc
SOURCES = *.asm

.PHONY: all clean

all: wic64.bin

wic64.bin: $(SOURCES)
	$(ASM) $(ASMFLAGS) -l wic64.sym --setpc 0xC000 -o $@ wic64.asm

wic64-optimized-for-size.bin: $(SOURCES)
	$(ASM) $(ASMFLAGS) -Dwic64_optimize_for_size=1 -l wic64.sym --setpc 0xC000 -o $@  wic64.asm

clean:
	rm -f *.{prg,sym,bin}
