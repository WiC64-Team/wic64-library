include Makefile.inc
SOURCES = *.asm

.PHONY: all clean

all: wic64.bin

wic64.bin: $(SOURCES)
	$(ASM) $(ASMFLAGS) -l wic64.sym --setpc 0x1000 -o $@ wic64.asm

wic64-complete.bin: $(SOURCES)
	$(ASM) $(ASMFLAGS) \
		-Dwic64_zeropage_pointer=166 \
		-Dwic64_include_return_to_portal=1 \
		-Dwic64_use_unused_labels=1 \
		-l wic64.sym \
		--setpc 0x1000 \
		-o $@ \
		wic64.asm

wic64.dasm: wic64-complete.bin
	@which ruby &>/dev/null || (echo "ERROR: ruby is required to build wic64.dasm" && false)
	@which da65 &>/dev/null || (echo "ERROR: da65 (part of cc65) is required to build wic64.dasm" && false)

	ruby tools/export.rb \
		--source wic64.asm \
		--binary wic64-complete.bin \
		--symbols wic64.sym \
		--ranges bytetable:wic64_data_section_start:wic64_data_section_end \
		> wic64.dasm

	@rm -f wic64-complete.bin

wic64-standalone.dasm: wic64-complete.bin
	ruby tools/export.rb \
		--source wic64.asm \
		--binary wic64-complete.bin \
		--symbols wic64.sym \
		--standalone \
		--ranges bytetable:wic64_data_section_start:wic64_data_section_end \
		> wic64-standalone.dasm

wic64-dasm.bin: wic64-standalone.dasm
	dasm wic64-standalone.dasm -owic64-dasm.bin -f3 -R

verify-dasm-export: wic64-complete.bin wic64-dasm.bin
	diff wic64-complete.bin wic64-dasm.bin
	@rm -f wic64-complete.bin wic64-dasm.bin wic64-standalone.dasm

clean:
	rm -f *.{prg,sym,bin,dasm}
