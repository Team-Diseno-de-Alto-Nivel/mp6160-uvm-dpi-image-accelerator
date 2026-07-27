#!/usr/bin/env bash
#
# check_deliverables.sh — verifica que exista cada entregable que pide
# docs/Enunciado.md (Evaluación 4).
#
# No juzga si el contenido es correcto, sólo que el artefacto esté y no esté
# vacío. Sirve para no descubrir la víspera de la entrega que falta algo.
#
# Uso:  ./scripts/check_deliverables.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

FAILED=0
CHECKED=0

# Un entregable satisfecho por un archivo concreto.
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

# Un entregable satisfecho por al menos un archivo que matchee un glob.
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

# Una sección que el enunciado exige en el README.
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

echo "Entregables — docs/Enunciado.md (Evaluación 4)"
echo "=============================================="
echo
echo "Código fuente en Verilog y SystemVerilog (implementación + testbench):"
need_file  "src/rtl/axi4_ram.v"          "RAM con puerto AXI4-Full"
need_file  "src/dpi/axi_ram_dpi.sv"      "wrapper DPI + AXI master BFM"
need_glob  "src/tb/uvm/*.sv"             "testbench UVM"

echo
echo "Código fuente en SystemC del acelerador y sus auxiliares:"
need_file  "src/model/modules/accelerator/accelerator.cpp" "Accelerator"
need_file  "src/model/modules/ram_axi/ram_axi.cpp"         "puente TLM ↔ DPI"
need_file  "src/model/sc_main.cpp"                         "top del modelo"

echo
echo "Scripts:"
need_file  "scripts/run_uvm.sh"          "correr la simulación SystemVerilog"
need_file  "scripts/build_rtl.sh"        "construir modelo + DPI + RTL"
need_file  "Makefile"                    "entrada unificada del build"

echo
echo "Imágenes:"
need_file  "images/input/image.raw"      "entrada RAW RGB"
need_file  "images/output/output.raw"    "salida generada por el sistema"

echo
echo "README — secciones que exige el enunciado:"
need_section "Requirements & Build Instructions"
need_section "Repository Organization"
need_section "Module Organization"
need_section "Block Diagram"
need_section "Sequence Diagram"
need_section "Results"

echo
echo "Declaración de uso de IA:"
CHECKED=$((CHECKED + 1))
if grep -qE '^\| *Claude' README.md; then
    printf '  ok    README: tabla AI-Assisted Development con filas\n'
else
    printf '  MISS  README: la tabla AI-Assisted Development está vacía\n'
    printf '        Su omisión se trata como plagio según el enunciado.\n'
    FAILED=$((FAILED + 1))
fi

echo
echo "----------------------------------------------"
if [[ ${FAILED} -eq 0 ]]; then
    echo "Todos los entregables presentes (${CHECKED} verificados)."
    exit 0
fi

echo "Faltan ${FAILED} de ${CHECKED} entregables."
exit 1
