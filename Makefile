BUILD_DIR := build
RTL_SRCS  := src/rtl/axi4_ram.v

.PHONY: all configure clean run lint rtl run-rtl uvm

# ── Modelo SystemC puro (flujo por defecto, no requiere Verilator ni Vivado) ──
all: configure
	$(MAKE) -C $(BUILD_DIR)

configure:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_POLICY_VERSION_MINIMUM=3.5

clean:
	rm -rf $(BUILD_DIR) obj_dir xsim.dir

run: all
	./$(BUILD_DIR)/sim

# ── Flujos RTL / verificación ────────────────────────────────────────────────
# Requieren Verilator 5 (co-simulación) y Vivado XSim (testbench UVM).

lint:
	@command -v verilator >/dev/null 2>&1 || \
		{ echo "verilator no encontrado — instalar Verilator 5 (ver README)"; exit 1; }
	verilator --lint-only -Wall $(RTL_SRCS)

rtl:
	./scripts/build_rtl.sh
	@echo "TODO(integrante 4) — T4.2: enlazar el modelo verilated al target sim en CMakeLists.txt"

run-rtl: rtl
	./$(BUILD_DIR)/sim --rtl-ram

uvm:
	./scripts/run_uvm.sh $(TEST)
