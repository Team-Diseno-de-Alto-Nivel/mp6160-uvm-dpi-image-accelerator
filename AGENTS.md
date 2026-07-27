# AGENTS.md

Project instructions for all AI coding assistants working in this repository.

See @README.md for architecture overview, build instructions, diagrams, memory map, and transaction format.
See @docs/Enunciado.md for the full assignment specification (Spanish) — read it to understand what must be implemented and what deliverables are required.

## Build

`$SYSTEMC_HOME` is optional. If unset, CMake downloads and compiles SystemC 2.3.4 automatically on first configure (requires internet, ~1–2 min).

```bash
make      # configure + compile
make run  # build and run the simulation (pure SystemC RAM)
```

RTL and verification flows need extra tooling — Verilator 5 for co-simulation, Vivado (XSim) for the UVM testbench:

```bash
make lint     # verilator --lint-only on src/rtl/
make rtl      # verilate the RTL + DPI bridge and build sim with RTL support
make run-rtl  # run the simulation with the Verilog AXI4 RAM instead of the C++ one
make uvm      # run the UVM testbench in Vivado XSim
```

## Non-obvious constraints

- **Separation of concerns is graded**: grayscale logic lives only in Accelerator; all inter-module data transfer via TLM `b_transport`, never direct calls; RAM is the only intermediate buffer; Disk is the only module that touches the filesystem.
- **Accelerator config is a 24-byte TLM WRITE**: 3 × `uint64_t` — src address in RAM, dst address in RAM, pixel count. CPU sends this before the Accelerator starts processing.
- **Image format**: RAW binary, no header, 3 bytes/pixel RGB, row-major, 1920 × 1080. Total: 6,220,800 bytes input, 2,073,600 bytes output.
- **AI usage must be declared** in the README (prompts + type of use). Omitting it is treated as plagiarism per @docs/Enunciado.md.

## Repository layout

All source lives under `src/`, grouped by subsystem (same convention as the sibling repo `mp6160-vitis-hls-accelerator`):

| Directory | Contents |
|---|---|
| `src/model/` | SystemC/TLM 2.0 model (`modules/`, `config/`, `infra/`, `utils/`, `sc_main.cpp`) |
| `src/rtl/` | Verilog RTL — the AXI4-Full RAM |
| `src/tb/uvm/` | SystemVerilog/UVM testbench for the RTL |
| `src/dpi/` | DPI-C bridge wiring the RTL into the SystemC model |

## Coding conventions

### Language

**All comments and identifiers in source files are in English**, regardless of the language used in issues, commit messages or pull requests. This applies to `src/`, `scripts/`, `CMakeLists.txt` and the workflows. Prose documentation under `docs/` is Spanish; `README.md` and this file are English.

> ⚠️ In `.v` / `.sv` files, no comment line may **start** with the word `verilator`. When it is the first token after `//`, Verilator parses it as a metacomment — a directive — and aborts if the directive does not exist. Capitalised counts too. This has bitten us twice; the `lint` CI job catches it.

### SystemC (`src/model/`)
- One `.h` + `.cpp` pair per module under `src/model/modules/<module>/`
- Shared address/config constants under `src/model/config/`; pure non-SystemC helpers under `src/model/utils/`; cross-cutting infra (logging) under `src/model/infra/`
- `#pragma once` in all headers, C++17
- `SC_THREAD` for all module processes
- Initiator sockets on CPU and Bus upstream; target sockets on RAM, Disk, Accelerator, and Bus downstream
- Include root is `src/model/`, so headers resolve as `#include "config/memory_map.h"`

### RTL (`src/rtl/`)
- **Verilog-2001 synthesizable only.** The RTL must elaborate in both Verilator (SystemC co-simulation) and Vivado XSim (UVM testbench); they do not accept the same SystemVerilog subset. Keep SystemVerilog constructs in `src/tb/` and `src/dpi/`, never in `src/rtl/`.
- AXI4 slave signals prefixed `s_axi_`; sizes come from `ADDR_WIDTH` / `DATA_WIDTH` / `ID_WIDTH` parameters, never hardcoded
- `MEM_DEPTH` is in **bytes** and must stay a parameter: 64 MB for co-simulation, 64 KB for the UVM testbench (XSim cannot hold 64 MB)
- Must pass `verilator --lint-only -Wall src/rtl/axi4_ram.v` with zero warnings

### UVM testbench (`src/tb/uvm/`)
- Target **Vivado XSim**, which ships **UVM 1.2** (not IEEE 1800.2). Avoid the register layer (RAL) and advanced factory usage — that is where XSim breaks.
- Run with `./scripts/run_uvm.sh <test_name>`; the script must exit non-zero when the log reports `UVM_ERROR`/`UVM_FATAL`, because XSim itself returns 0 regardless.

### DPI bridge (`src/dpi/`)
- The contract is frozen in `src/dpi/axi_ram_dpi.h` and `src/dpi/axi_ram_dpi.svh` — changing it breaks the RTL, testbench and SystemC sides at once
- Exported DPI functions **must not consume simulation time** (Verilator restriction). Use the request/poll pattern: `axi_dpi_req()` enqueues, the AXI master BFM advances in `always_ff`, C++ polls `axi_dpi_done()`.

## Diagrams

All diagrams use Mermaid fenced blocks. GitHub renders them natively. Block diagram: `graph LR`. Sequence diagram: `sequenceDiagram`.

## AI Usage Declaration

When your AI assistant helps with this project, run `/log-ai` (available in Claude Code and GitHub Copilot Chat) to append a row to the `## AI-Assisted Development` table in `README.md`. Columns: **Model**, **Type of use**, **Prompt**. Required by the course — omitting it counts as plagiarism.
