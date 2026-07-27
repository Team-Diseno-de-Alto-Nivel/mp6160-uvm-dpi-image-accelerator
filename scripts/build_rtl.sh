#!/usr/bin/env bash
#
# build_rtl.sh — verilates the AXI4-Full RAM and the DPI wrapper into a C++
# library, which is what the SystemC model links against to run the RTL RAM.
#
# The assignment asks for "scripts to automate building the model together with
# DPI/VPI and the RTL": this is that script, standalone and independent of CMake.
# Note `make run-rtl` does NOT use this — CMake runs verilate() itself as part of
# the `sim` target. This exists for the deliverable and for debugging the RTL on
# its own.
#
# Usage:
#   ./scripts/build_rtl.sh                    # normal build
#   ./scripts/build_rtl.sh --trace            # also emit VCD waveforms
#   MEM_DEPTH=65536 ./scripts/build_rtl.sh    # smaller RAM, faster debug

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/build/rtl"
TOP_MODULE="axi_ram_dpi"

# 64 MB by default — the same size as the C++ reference RAM.
MEM_DEPTH="${MEM_DEPTH:-67108864}"

TRACE_FLAGS=()
if [[ "${1:-}" == "--trace" ]]; then
    TRACE_FLAGS=(--trace --trace-depth 3)
    echo "==> VCD tracing enabled"
fi

if ! command -v verilator >/dev/null 2>&1; then
    echo "ERROR: verilator is not installed." >&2
    echo "       Use the dev container, which ships it, or install Verilator 5:" >&2
    echo "       https://verilator.org/guide/latest/install.html" >&2
    exit 1
fi

# Verilator's verilated.mk is a GNU Make file and does not support paths with
# spaces. CMake's verilate() does not either: its JSON parser breaks.
case "${ROOT}" in
    *[[:space:]]*)
        echo "ERROR: the project path contains spaces:" >&2
        echo "       ${ROOT}" >&2
        echo "" >&2
        echo "       Verilator cannot build there. Clone the repo into a path" >&2
        echo "       without spaces, or use the dev container, which mounts at" >&2
        echo "       /workspace. Accented characters can break CMake's" >&2
        echo "       verilate() as well." >&2
        exit 1
        ;;
esac

echo "==> Verilator $(verilator --version | head -1)"
echo "==> MEM_DEPTH = ${MEM_DEPTH} bytes"

mkdir -p "${OUT_DIR}"

verilator \
    --cc \
    --Mdir "${OUT_DIR}" \
    --top-module "${TOP_MODULE}" \
    --prefix "V${TOP_MODULE}" \
    -GMEM_DEPTH="${MEM_DEPTH}" \
    +incdir+"${ROOT}/src/dpi" \
    -O2 \
    --x-assign fast \
    --x-initial fast \
    -Wall \
    ${TRACE_FLAGS[@]+"${TRACE_FLAGS[@]}"} \
    "${ROOT}/src/rtl/axi4_ram.v" \
    "${ROOT}/src/dpi/axi_ram_dpi.sv"

echo "==> Building the verilated model"
make -C "${OUT_DIR}" -f "V${TOP_MODULE}.mk" -j"$(getconf _NPROCESSORS_ONLN)"

echo "==> Done: ${OUT_DIR}/V${TOP_MODULE}__ALL.a"
