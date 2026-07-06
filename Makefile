.PHONY: help sync fm blm render lut st_init sim synth clean

help:
	@echo "Available targets:"
	@echo "  sync    - install/sync dependencies"
	@echo "  fm      - run the float64 model (ORBIT=<config>)"
	@echo "  blm     - run the bit-level model (ORBIT=<config>)"
	@echo "  render  - render simulation output"
	@echo "  lut     - generate the Newton LUT header"
	@echo "  st_init - generate simulation/st_init.mem (ORBIT=<config>)"
	@echo "  sim 	 - run accelerator_tb.sv in VCS (ORBIT=<config>, VCD=1 to dump waveform)"
	@echo "  synth   - run Design Compiler synthesis (outputs to synthesis/)"
	@echo "  clean   - remove build artifacts and output"
	@echo ""
	@echo "Available ORBIT configs:"
	@uv run python -c "from modeling.orbits import CONFIGS; print('\n'.join(f'  {name}' for name in CONFIGS))"

sync:
	uv sync

fm:
	mkdir -p output
	uv run python modeling/float64_model.py $(ORBIT)

blm:
	mkdir -p output
	gcc modeling/bitlevel_model.c modeling/orbits.c -Wall -Werror -o modeling/bitlevel_model.exe -lm
	./modeling/bitlevel_model.exe $(ORBIT)

render:
	uv run python modeling/render.py

lut:
	gcc modeling/gen_lut.c -o modeling/gen_lut.exe -lm
	modeling/gen_lut.exe > modeling/newton_lut.h

st_init:
	mkdir -p simulation
	gcc modeling/gen_st_init.c modeling/orbits.c -o modeling/gen_st_init.exe -lm
	./modeling/gen_st_init.exe $(ORBIT)

# VCD=1 (or t/true/yes) opts into the waveform dump; off by default since a
# full-hierarchy dump over a long run (e.g. solar_system's ~80000 steps) can
# reach tens of GB and blow through a disk quota
VCD ?= 0
VCD_ARG := $(if $(filter 0,$(VCD)),,+VCD)

sim: st_init
	mkdir -p output
	cd simulation && vcs -sverilog -full64 -timescale=1ns/1ps -debug_access+all ../rtl/*.sv accelerator_tb.sv +incdir+../rtl -top accelerator_tb -o simv && ./simv $(VCD_ARG)

synth:
	mkdir -p synthesis/build
	cd synthesis/build && dc_shell -x "set script_dir .." -f ../synth.tcl | tee ../synth.log

clean:
	rm -f *.exe
	rm -f modeling/*.exe
	rm -f output/*
	rm -rf simulation/csrc simulation/simv simulation/simv.daidir simulation/ucli.key simulation/vc_hdrs.h simulation/DVEfiles simulation/*.vpd simulation/*.fsdb
	rm -rf synthesis/build synthesis/report synthesis/synth.log synthesis/command.log synthesis/filenames.log synthesis/cksum_dir
	rm -rf synthesis/*.pvl
	rm -rf synthesis/*.syn
	rm -rf synthesis/*.mr

