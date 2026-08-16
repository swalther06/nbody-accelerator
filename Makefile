.PHONY: help sync fm blm refsim sw_metrics hw_metrics compare compare_only render lut st_init sim mult_tb accel_unit_tb synth clean syn_search nuke

help:
	@echo "Available targets:"
	@echo "  sync    - install/sync dependencies"
	@echo "  fm      - run the float64 model (ORBIT=<config>)"
	@echo "  blm     - run the bit-level model (ORBIT=<config>)"
	@echo "  refsim  - run the double-precision software baseline (ORBIT=<config>, ARGS=..., REFFLAGS=...)"
	@echo "  compare - run RTL + software and print a side-by-side comparison"
	@echo "            (N=<bodies>, STEPS=<n> for a faster run, ORBIT=..., PERIOD=<ns>)"
	@echo "            logs land in sim_log/hardware.log and sim_log/software.log"
	@echo "  compare_only - re-print the comparison from existing sim_log/ files"
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

REFFLAGS ?= -O3
refsim: sw_metrics

# --- hardware vs software comparison ---------------------------------------
# Both runs write to sim_log/ (hardware.log, software.log), each ending in a
# machine-readable [metrics] block that modeling/compare.py parses. PERIOD is
# the synthesized clock in ns -- the 10ns testbench clock is arbitrary, so
# ns/step and ns/pair are meaningless without it.
PERIOD ?= $(shell cat synthesis/clock 2>/dev/null || echo 2.5)

# TECH selects the standard cell library in synthesis/synth.tcl:
#   lec25     TSMC 250nm educational (default, the only one with no strings)
#   n16       TSMC 16nm ADFP -- foundry PDK, check its TERMS_AND_CONDITIONS pdf
#   freepdk45 Nangate 45nm Open Cell Library, expected under $TECH_HOME (~/tech)
TECH ?= lec25

# N=<count> overrides the body count for BOTH sides of the comparison. It has to
# reach every compile that sees definitions.h/defs.svh -- including gen_st_init,
# since st_init.mem's field layout is N-dependent and a mismatch between the
# generator and the testbench corrupts the initial state silently. Unset leaves
# each header's own default alone.
# N / PIPES / LANES override the guarded macros in defs.svh (and definitions.h
# for N) without editing either file. They must reach every consumer that sees
# those headers -- gcc, VCS, AND dc_shell -- or the benchmark and the area
# report end up describing different designs.
NDEF_C  := $(if $(N),-DN=$(N),)
NDEF_SV := $(strip $(if $(N),+define+N=$(N),) \
                   $(if $(PIPES),+define+NUMPIPES=$(PIPES),) \
                   $(if $(LANES),+define+NUMLANES=$(LANES),))
# dc_shell wants a Tcl list of NAME=value, consumed by synth.tcl's rtl_defines
RTL_DEFINES := $(strip $(if $(N),N=$(N),) \
                       $(if $(PIPES),NUMPIPES=$(PIPES),) \
                       $(if $(LANES),NUMLANES=$(LANES),))

# STEPS=<n> sets the timestep count on BOTH sides (default 1500, i.e. the RTL's
# tend=15.0 at dt=0.01). This is the knob for a faster run: cycles/step is a
# steady-state figure and does not change with it, but energy drift accumulates
# over time, so keep a long run when validating accuracy rather than speed.
STEPSDEF_C  := $(if $(STEPS),-DREF_STEPS=$(STEPS),)
STEPS_ARG   := $(if $(STEPS),+steps=$(STEPS),)

sw_metrics:
	mkdir -p sim_log
	gcc modeling/reference_sim.c modeling/orbits.c -Wall -Werror $(NDEF_C) $(STEPSDEF_C) $(REFFLAGS) -o modeling/reference_sim.exe -lm
	./modeling/reference_sim.exe $(ORBIT) $(ARGS)

# synchronous RTL run (unlike 'sim', which detaches into tmux) so it can be
# sequenced ahead of the comparison
hw_metrics: st_init
	mkdir -p sim_log output
	cd simulation && vcs -sverilog -full64 -timescale=1ns/1ps ../rtl/*.sv accelerator_tb.sv +incdir+../rtl $(NDEF_SV) $(DW_ARGS) -top accelerator_tb -o simv_metrics
	cd simulation && ./simv_metrics +period=$(PERIOD) +orbit=$(if $(ORBIT),$(ORBIT),figure8) $(STEPS_ARG)

compare: hw_metrics sw_metrics
	@uv run python modeling/compare.py

# re-run just the comparison against whatever is already in sim_log/
compare_only:
	@uv run python modeling/compare.py

render:
	uv run python modeling/render.py

lut:
	gcc modeling/gen_lut.c -o modeling/gen_lut.exe -lm
	modeling/gen_lut.exe > modeling/newton_lut.h

st_init:
	mkdir -p simulation
	gcc modeling/gen_st_init.c modeling/orbits.c $(NDEF_C) -o modeling/gen_st_init.exe -lm
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
	cd synthesis/build && dc_shell -x "set script_dir ..; set rtl_defines {$(RTL_DEFINES)}; set tech $(TECH)" -f ../synth.tcl | tee ../synth.log

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