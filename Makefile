include Makefile.inc
SOURCES = *.asm *.h

C64ASS = c64ass
C64ASSFLAGS = -I W1000 -LIB .

.PHONY: all dasm-export-verify dasm-export c64ass-acme-verify test prompt clean clean-artefacts

all: wic64.bin c64ass-acme-verify dasm-export-verify dasm-export clean-artefacts

/tmp/wic64-tmp.asm: $(SOURCES)
	echo -e '*=0x1000\n!src <wic64.h>\n!src <wic64.asm>\n' > $@

wic64.bin: $(SOURCES) /tmp/wic64-tmp.asm
	ACME=. $(ASM) $(ASMFLAGS) -l wic64.sym -o $@ /tmp/wic64-tmp.asm

wic64-complete.bin: $(SOURCES) /tmp/wic64-tmp.asm
	ACME=. $(ASM) $(ASMFLAGS) \
		-Dwic64_zeropage_pointer=166 \
		-Dwic64_include_return_to_portal=1 \
		-Dwic64_use_unused_labels=1 \
		-l wic64.sym \
		-o $@ \
		/tmp/wic64-tmp.asm

wic64-complete-c64ass.bin: $(SOURCES) /tmp/wic64-tmp.asm
	$(C64ASS) $(C64ASSFLAGS) \
		-F PLAIN \
		-D wic64_include_return_to_portal=1 \
		-D wic64_zeropage_pointer=166 \
		-D wic64_use_unused_labels=1 \
		-O $@ \
		/tmp/wic64-tmp.asm

wic64.dasm: wic64-complete.bin
	@which ruby &>/dev/null || (echo "ERROR: ruby is required to build wic64.dasm" && false)
	@which da65 &>/dev/null || (echo "ERROR: da65 (part of cc65) is required to build wic64.dasm" && false)

	ruby tools/export.rb \
		--source wic64.asm \
		--binary wic64-complete.bin \
		--symbols wic64.sym \
		--ranges bytetable:wic64_data_section_start:wic64_data_section_end \
		> wic64.dasm

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

dasm-export: wic64.dasm

dasm-export-verify: wic64-complete.bin wic64-dasm.bin
	diff wic64-complete.bin wic64-dasm.bin

c64ass-acme-verify: wic64-complete.bin wic64-complete-c64ass.bin
	diff wic64-complete.bin wic64-complete-c64ass.bin

prompt:
	@echo "Press any key to run example $$(basename $$EXAMPLE)"
	@read -n1

test:
	@for d in ./examples/*; do EXAMPLE="$$d" make prompt; make -C "$$d" clean test; done

clean-artefacts:
	@rm -f *.bin
	@rm -f wic64-standalone.dasm
	@rm -f /tmp/wic64-tmp.asm

clean:
	rm -f *.{prg,sym,bin,dasm}
