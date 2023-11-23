include ../../Makefile.inc
INCLUDES = -I../.. -I..
SOURCES = *.asm ../../wic64.asm ../../wic64.h

.PHONY: all clean

%.prg: %.asm $(SOURCES)
	$(ASM) $(ASMFLAGS) -Dwic64_build_report=1 $(INCLUDES) -f cbm -l $*.sym -o $*.prg  $*.asm

all: main

main: main.prg

test: main
	$(EMU) $(EMUFLAGS) main.prg

clean:
	rm -f *.{prg,sym}