.PHONY: help sync fm blm render lut st_init sim mult_tb accel_unit_tb synth clean syn_search nuke

help:
	@echo "Available targets:"
	@echo "  sync    - install/sync dependencies"
	@echo "  fm      - run the float64 model (ORBIT=<config>)"
	@echo "  blm     - run the bit-level model (ORBIT=<config>)"
	@echo "  render  - render simulation output"
	@echo "  lut     - generate the Newton LUT header"
	@echo "  st_init - generate simulation/st_init.mem (ORBIT=<config>)"
	@echo "  sim 	 - run accelerator_tb.sv in VCS (ORBIT=<config>, VCD=1 to dump waveform)"
	@echo "  mult_tb - run multiplier_tb.sv in VCS (standalone rad4_booth_reduction_multiplier check)"
	@echo "  accel_unit_tb - run accel_unit_tb.sv in VCS (standalone accel_unit check)"
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
DEBUG_ARG := $(if $(filter 0,$(VCD)),,-debug_access+all)

# accelerator.sv instantiates DW_div_pipe (see accelerator.sv's num_total_steps
# comment); VCS needs the DesignWare behavioral sim models to resolve it, plus
# an incdir so DW_div.v's own `include finds DW_div_function.inc alongside it.
DW_SIM_LIB := /usr/caen/synopsys-synth-2023.12-SP5/dw/sim_ver
DW_ARGS := -y $(DW_SIM_LIB) +libext+.v +incdir+$(DW_SIM_LIB)

sim: st_init
	mkdir -p output
	tmux new-session -d -s sim_run 'cd simulation  && vcs -sverilog -full64 -timescale=1ns/1ps $(DEBUG_ARG) ../rtl/*.sv accelerator_tb.sv +incdir+../rtl $(DW_ARGS) -top accelerator_tb -o simv && ./simv $(VCD_ARG); echo "--- done, press enter to close ---"; read'
	@echo 'started in tmux session 'sim_run''

mult_tb:
	cd simulation && vcs -sverilog -full64 -timescale=1ns/1ps ../rtl/*.sv multiplier_tb.sv +incdir+../rtl -top multiplier_tb -o simv_mult && ./simv_mult

accel_unit_tb:
	cd simulation && vcs -sverilog -full64 -timescale=1ns/1ps ../rtl/*.sv accel_unit_tb.sv +incdir+../rtl -top accel_unit_tb -o simv_accel_unit && ./simv_accel_unit

synth:
	mkdir -p synthesis/build
	cd synthesis/build && dc_shell -x "set script_dir .." -f ../synth.tcl | tee ../synth.log

syn_search:
	tmux new-session -d -s syn_search 'bash synthesis/find_min_period.sh; echo "--- done, press enter to close ---"; read'
	@echo "started in tmux session 'syn_search' -- attach with: tmux attach -t syn_search"

clean:
	rm -f *.exe
	rm -f modeling/*.exe
	rm -f output/*
	rm -rf simulation/csrc simulation/simv simulation/simv_* simulation/ucli.key simulation/vc_hdrs.h simulation/DVEfiles simulation/*.vpd simulation/*.fsdb
	rm -rf synthesis/build synthesis/cksum_dir
	rm -rf synthesis/*.pvl
	rm -rf synthesis/*.syn
	rm -rf synthesis/*.mr

nuke:
	rm -f *.exe
	rm -f modeling/*.exe
	rm -f output/*
	rm -rf simulation/csrc simulation/simv simulation/simv_* simulation/work simulation/ucli.key simulation/vc_hdrs.h simulation/*.mem simulation/DVEfiles simulation/*.vpd simulation/*.fsdb
	rm -rf synthesis/build synthesis/report synthesis/cksum_dir synthesis/logs
	rm -rf synthesis/*.pvl
	rm -rf synthesis/*.syn
	rm -rf synthesis/*.mr
	rm -rf synthesis/*.log 