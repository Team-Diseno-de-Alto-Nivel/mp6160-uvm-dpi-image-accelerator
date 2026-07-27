BUILD_DIR := build
RTL_SRCS  := src/rtl/axi4_ram.v
DPI_SRCS  := src/dpi/axi_ram_dpi.sv

.PHONY: all configure clean run lint rtl run-rtl uvm

# ── Pure SystemC model (default flow, needs neither Verilator nor Vivado) ─────
all: configure
	$(MAKE) -C $(BUILD_DIR)

configure:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_POLICY_VERSION_MINIMUM=3.5

clean:
	rm -rf $(BUILD_DIR) obj_dir xsim.dir

run: all
	./$(BUILD_DIR)/sim

# ── RTL and verification flows ───────────────────────────────────────────────
# These need Verilator 5 (co-simulation) and Vivado XSim (UVM testbench).

lint:
	@command -v verilator >/dev/null 2>&1 || \
		{ echo "verilator not found — install Verilator 5 (see README)"; exit 1; }
	verilator --lint-only -Wall $(RTL_SRCS)
	verilator --lint-only -Wall --top-module axi_ram_dpi \
		+incdir+src/dpi $(RTL_SRCS) $(DPI_SRCS)

# Standalone verilate, no CMake involved. The assignment asks for a script that
# builds the model together with DPI and the RTL, and this is it.
#
# Note this is NOT how `run-rtl` builds the simulator: CMake runs verilate()
# itself as part of the `sim` target. This target exists for the deliverable and
# for debugging the RTL in isolation.
rtl:
	./scripts/build_rtl.sh

# Depends on `all`, not on `rtl`: the simulator that serves `--rtl-ram` is the
# one CMake builds. Depending on `rtl` used to run the standalone script
# needlessly — and that script refuses to run from a path containing spaces,
# which broke this target on exactly the machines that need it most.
run-rtl: all
	./$(BUILD_DIR)/sim --rtl-ram

uvm:
	./scripts/run_uvm.sh $(TEST)
