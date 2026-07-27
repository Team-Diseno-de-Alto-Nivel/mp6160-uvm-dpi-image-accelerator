#!/usr/bin/env bash
#
# run_uvm.sh — corre el testbench UVM de la RAM AXI4-Full en Vivado XSim.
#
# Requiere Vivado (o Vitis) en el PATH. XSim trae UVM 1.2, que se habilita con
# `-L uvm` tanto en xvlog como en xelab.
#
# Uso:
#   ./scripts/run_uvm.sh                  # corre smoke_test
#   ./scripts/run_uvm.sh burst_test       # corre un test específico
#   ./scripts/run_uvm.sh random_test --gui
#   UVM_VERBOSITY=UVM_HIGH ./scripts/run_uvm.sh smoke_test
#
# IMPORTANTE: xsim devuelve código 0 aunque UVM reporte errores. Este script
# parsea el reporte final de UVM y devuelve ≠ 0 si hay UVM_ERROR o UVM_FATAL,
# que es lo que permite usarlo como paso de verificación.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TB_DIR="${ROOT}/src/tb"
RUN_DIR="${ROOT}/build/uvm"

TEST="${1:-smoke_test}"
GUI=""
if [[ "${2:-}" == "--gui" ]]; then
    GUI="--gui"
fi

UVM_VERBOSITY="${UVM_VERBOSITY:-UVM_MEDIUM}"
SNAPSHOT="tb_snap"
TOP="tb_top"
LOG="${RUN_DIR}/${TEST}.log"

# ── Comprobaciones previas ───────────────────────────────────────────────────
if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog no está en el PATH." >&2
    echo "       Cargá el entorno de Vivado antes de correr esto:" >&2
    echo "         source /tools/Xilinx/Vivado/<version>/settings64.sh" >&2
    exit 1
fi

if [[ ! -f "${TB_DIR}/files.f" ]]; then
    echo "ERROR: no existe ${TB_DIR}/files.f" >&2
    exit 1
fi

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

# ── 1. Análisis ──────────────────────────────────────────────────────────────
echo "==> xvlog: analizando fuentes"
xvlog -sv -L uvm -f "${TB_DIR}/files.f"

# ── 2. Elaboración ───────────────────────────────────────────────────────────
# -relax hace a XSim menos estricto con construcciones que UVM 1.2 usa.
echo "==> xelab: elaborando ${TOP}"
xelab -L uvm -timescale 1ns/1ps -relax -s "${SNAPSHOT}" "${TOP}"

# ── 3. Simulación ────────────────────────────────────────────────────────────
echo "==> xsim: corriendo ${TEST}"
if [[ -n "${GUI}" ]]; then
    xsim "${SNAPSHOT}" --gui \
        -testplusarg "UVM_TESTNAME=${TEST}" \
        -testplusarg "UVM_VERBOSITY=${UVM_VERBOSITY}"
    exit 0
fi

xsim "${SNAPSHOT}" -R \
    -testplusarg "UVM_TESTNAME=${TEST}" \
    -testplusarg "UVM_VERBOSITY=${UVM_VERBOSITY}" | tee "${LOG}"

# ── 4. Veredicto ─────────────────────────────────────────────────────────────
# El reporte final de UVM se ve así:
#   ** Report counts by severity
#   UVM_INFO :   42
#   UVM_WARNING :    0
#   UVM_ERROR :    0
#   UVM_FATAL :    0
count_of() {
    grep -E "^${1}\s*:" "${LOG}" | tail -1 | grep -oE '[0-9]+$' || echo "missing"
}

ERRORS="$(count_of UVM_ERROR)"
FATALS="$(count_of UVM_FATAL)"

echo
echo "──────────────────────────────────────────"
if [[ "${ERRORS}" == "missing" || "${FATALS}" == "missing" ]]; then
    echo "FAIL — no se encontró el reporte final de UVM en ${LOG}."
    echo "       La simulación probablemente abortó antes de terminar."
    exit 1
fi

echo "  test        : ${TEST}"
echo "  UVM_ERROR   : ${ERRORS}"
echo "  UVM_FATAL   : ${FATALS}"
echo "  log         : ${LOG}"
echo "──────────────────────────────────────────"

if [[ "${ERRORS}" -ne 0 || "${FATALS}" -ne 0 ]]; then
    echo "FAIL"
    exit 1
fi

echo "PASS"
