#!/usr/bin/env bash
#
# check_deliverables.sh — verifies that every deliverable docs/Enunciado.md
# asks for exists.
#
# It does not judge whether the content is correct, only that the artifact is
# there and not empty. The point is not to discover something missing the night
# before submission.
#
# Usage:  ./scripts/check_deliverables.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

FAILED=0
CHECKED=0

# A deliverable satisfied by one specific file.
need_file() {
    local path="$1" what="$2"
    CHECKED=$((CHECKED + 1))
    if [[ -s "${path}" ]]; then
        printf '  ok    %-46s %s\n' "${path}" "${what}"
    else
        printf '  MISS  %-46s %s\n' "${path}" "${what}"
        FAILED=$((FAILED + 1))
    fi
}

# A deliverable satisfied by at least one file matching a glob.
need_glob() {
    local pattern="$1" what="$2"
    CHECKED=$((CHECKED + 1))
    # shellcheck disable=SC2086
    if compgen -G "${pattern}" >/dev/null 2>&1; then
        printf '  ok    %-46s %s\n' "${pattern}" "${what}"
    else
        printf '  MISS  %-46s %s\n' "${pattern}" "${what}"
        FAILED=$((FAILED + 1))
    fi
}

# A section the assignment requires in the README.
need_section() {
    local heading="$1"
    CHECKED=$((CHECKED + 1))
    if grep -qiE "^#+[[:space:]]+${heading}" README.md; then
        printf '  ok    README section: %s\n' "${heading}"
    else
        printf '  MISS  README section: %s\n' "${heading}"
        FAILED=$((FAILED + 1))
    fi
}

echo "Deliverables — docs/Enunciado.md"
echo "================================"
echo
echo "Verilog and SystemVerilog sources (implementation + testbench):"
need_file  "src/rtl/axi4_ram.v"          "RAM with an AXI4-Full port"
need_file  "src/dpi/axi_ram_dpi.sv"      "DPI wrapper + AXI master BFM"
need_glob  "src/tb/uvm/*.sv"             "UVM testbench"

echo
echo "SystemC sources for the accelerator and its helpers:"
need_file  "src/model/modules/accelerator/accelerator.cpp" "Accelerator"
need_file  "src/model/modules/ram_axi/ram_axi.cpp"         "TLM to DPI bridge"
need_file  "src/model/sc_main.cpp"                         "model top level"

echo
# Presence only. build_rtl.sh is additionally *executed* by the build job in
# CI, and run_uvm.sh is exercised by hand — see the README, that flow needs
# Vivado and cannot run on GitHub-hosted runners.
echo "Scripts:"
need_file  "scripts/run_uvm.sh"          "run the SystemVerilog simulation"
need_file  "scripts/build_rtl.sh"        "build model + DPI + RTL"
need_file  "Makefile"                    "unified build entry point"

echo
echo "Images:"
need_file  "images/input/image.raw"      "RAW RGB input"
need_file  "images/output/output.raw"    "output produced by the system"

echo
echo "README — sections the assignment requires:"
need_section "Requirements & Build Instructions"
need_section "Repository Organization"
need_section "Module Organization"
need_section "Block Diagram"
need_section "Sequence Diagram"
need_section "Results"

echo
echo "AI usage declaration:"
CHECKED=$((CHECKED + 1))
if grep -qE '^\| *Claude' README.md; then
    printf '  ok    README: AI-Assisted Development table has rows\n'
else
    printf '  MISS  README: the AI-Assisted Development table is empty\n'
    printf '        Omitting it counts as plagiarism per the assignment.\n'
    FAILED=$((FAILED + 1))
fi

echo
echo "----------------------------------------------"
if [[ ${FAILED} -eq 0 ]]; then
    echo "All deliverables present (${CHECKED} checked)."
    exit 0
fi

echo "${FAILED} of ${CHECKED} deliverables missing."
exit 1
