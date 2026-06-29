.PHONY: help sync fm blm render lut st_init simulate clean

help:
	@echo "Available targets:"
	@echo "  sync    - install/sync dependencies"
	@echo "  fm      - run the float64 model (ORBIT=<config>)"
	@echo "  blm     - run the bit-level model (ORBIT=<config>)"
	@echo "  render  - render simulation output"
	@echo "  lut     - generate the Newton LUT header"
	@echo "  st_init - generate simulation/st_init.mem (ORBIT=<config>)"
	@echo "  simulate - run accelerator_tb.sv in VCS"
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
	gcc modeling/bitlevel_model.c modeling/orbits.c -o modeling/bitlevel_model.exe -lm
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

simulate:
	mkdir -p output
	cd simulation && vcs -sverilog -full64 -timescale=1ns/1ps ../rtl/*.sv accelerator_tb.sv +incdir+../rtl -top accelerator_tb -o simv && ./simv

clean:
	rm -f *.exe
	rm -f modeling/*.exe
	rm -f output/*
	rm -rf simulation/csrc simulation/simv simulation/simv.daidir simulation/ucli.key simulation/vc_hdrs.h simulation/DVEfiles simulation/*.vpd simulation/*.fsdb

