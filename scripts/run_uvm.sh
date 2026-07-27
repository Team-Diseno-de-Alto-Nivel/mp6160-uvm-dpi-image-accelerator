#!/usr/bin/env bash
#
# run_uvm.sh — runs the AXI4-Full RAM's UVM testbench in Vivado XSim.
#
# Needs Vivado (or Vitis) on the PATH. XSim ships UVM 1.2, enabled with `-L uvm`
# in both xvlog and xelab.
#
# Usage:
#   ./scripts/run_uvm.sh                  # runs smoke_test
#   ./scripts/run_uvm.sh burst_test       # runs a specific test
#   ./scripts/run_uvm.sh random_test --gui
#   UVM_VERBOSITY=UVM_HIGH ./scripts/run_uvm.sh smoke_test
#
# IMPORTANT: xsim exits 0 even when UVM reports errors. This script parses UVM's
# final report and exits non-zero on any UVM_ERROR or UVM_FATAL, which is what
# makes it usable as a verification step.

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

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog is not on the PATH." >&2
    echo "       Source the Vivado environment before running this:" >&2
    echo "         source /tools/Xilinx/Vivado/<version>/settings64.sh" >&2
    exit 1
fi

if [[ ! -f "${TB_DIR}/files.f" ]]; then
    echo "ERROR: ${TB_DIR}/files.f does not exist" >&2
    exit 1
fi

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

# ── 1. Analysis ──────────────────────────────────────────────────────────────
echo "==> xvlog: analysing sources"
xvlog -sv -L uvm -f "${TB_DIR}/files.f"

# ── 2. Elaboration ───────────────────────────────────────────────────────────
# -relax makes XSim less strict about constructs UVM 1.2 relies on.
echo "==> xelab: elaborating ${TOP}"
xelab -L uvm -timescale 1ns/1ps -relax -s "${SNAPSHOT}" "${TOP}"

# ── 3. Simulation ────────────────────────────────────────────────────────────
echo "==> xsim: running ${TEST}"
if [[ -n "${GUI}" ]]; then
    xsim "${SNAPSHOT}" --gui \
        -testplusarg "UVM_TESTNAME=${TEST}" \
        -testplusarg "UVM_VERBOSITY=${UVM_VERBOSITY}"
    exit 0
fi

xsim "${SNAPSHOT}" -R \
    -testplusarg "UVM_TESTNAME=${TEST}" \
    -testplusarg "UVM_VERBOSITY=${UVM_VERBOSITY}" | tee "${LOG}"

# ── 4. Verdict ───────────────────────────────────────────────────────────────
# UVM's final report looks like this:
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
    echo "FAIL — no UVM final report found in ${LOG}."
    echo "       The simulation most likely aborted before finishing."
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
