.PHONY: help sync fm blm render lut clean

help:
	@echo "Available targets:"
	@echo "  sync    - install/sync dependencies"
	@echo "  fm      - run the float64 model (ORBIT=<config>)"
	@echo "  blm     - run the bit-level model (ORBIT=<config>)"
	@echo "  render  - render simulation output"
	@echo "  lut     - generate the Newton LUT header"
	@echo "  clean   - remove build artifacts and output"
	@echo ""
	@echo "Available ORBIT configs:"
	@uv run python -c "from simulation.orbits import CONFIGS; print('\n'.join(f'  {name}' for name in CONFIGS))"

sync:
	uv sync

fm:
	mkdir -p simulation/output
	uv run python simulation/float64_model.py $(ORBIT)

blm:
	mkdir -p simulation/output
	gcc simulation/bitlevel_model.c simulation/orbits.c -o simulation/bitlevel_model.exe -lm
	./simulation/bitlevel_model.exe $(ORBIT)

render:
	uv run python simulation/render.py

lut:
	gcc simulation/gen_lut.c -o simulation/gen_lut.exe -lm
	simulation/gen_lut.exe > simulation/newton_lut.h

clean:
	rm -f *.exe
	rm -f simulation/*.exe
	rm -f simulation/output/*

