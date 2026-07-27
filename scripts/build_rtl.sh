#!/usr/bin/env bash
#
# build_rtl.sh — verilata la RAM AXI4-Full y el wrapper DPI en una librería C++
# que el modelo SystemC enlaza para correr con la RAM RTL (`sim --rtl-ram`).
#
# El enunciado pide "scripts para automatizar la construcción del modelo, junto
# con DPI/VPI y el RTL": este es el camino standalone, sin depender de CMake.
# `make rtl` hace lo mismo a través de CMake.
#
# Uso:
#   ./scripts/build_rtl.sh              # build normal
#   ./scripts/build_rtl.sh --trace      # además genera waveforms VCD
#   MEM_DEPTH=65536 ./scripts/build_rtl.sh   # RAM más chica (debug rápido)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/build/rtl"
TOP_MODULE="axi_ram_dpi"

# 64 MB por defecto — el mismo tamaño que la RAM C++ de referencia.
MEM_DEPTH="${MEM_DEPTH:-67108864}"

TRACE_FLAGS=()
if [[ "${1:-}" == "--trace" ]]; then
    TRACE_FLAGS=(--trace --trace-depth 3)
    echo "==> Trazas VCD habilitadas"
fi

if ! command -v verilator >/dev/null 2>&1; then
    echo "ERROR: verilator no está instalado." >&2
    echo "       Usá el devcontainer (ya lo trae) o instalá Verilator 5:" >&2
    echo "       https://verilator.org/guide/latest/install.html" >&2
    exit 1
fi

# El verilated.mk de Verilator es un Makefile de GNU Make, que no soporta rutas
# con espacios. El verilate() de CMake tampoco: su parser JSON se rompe.
case "${ROOT}" in
    *[[:space:]]*)
        echo "ERROR: la ruta del proyecto contiene espacios:" >&2
        echo "       ${ROOT}" >&2
        echo "" >&2
        echo "       Verilator no puede construir ahí. Cloná el repo en una" >&2
        echo "       ruta sin espacios, o usá el devcontainer (monta en" >&2
        echo "       /workspace). Los caracteres acentuados también pueden" >&2
        echo "       romper el verilate() de CMake." >&2
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

echo "==> Compilando el modelo verilated"
make -C "${OUT_DIR}" -f "V${TOP_MODULE}.mk" -j"$(getconf _NPROCESSORS_ONLN)"

echo "==> Listo: ${OUT_DIR}/V${TOP_MODULE}__ALL.a"
