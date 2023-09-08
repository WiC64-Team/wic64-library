include ../../Makefile.inc
INCLUDES = -I../..
SOURCES = *.asm ../../wic64.asm

.PHONY: all clean

%.prg: %.asm $(SOURCES)
	$(ASM) $(ASMFLAGS) $(INCLUDES) -f cbm -l $*.sym -o $*.prg  $*.asm

all: main

main: main.prg

test: main
	$(EMU) $(EMUFLAGS) main.prg

clean:
	rm -f *.{prg,sym}
