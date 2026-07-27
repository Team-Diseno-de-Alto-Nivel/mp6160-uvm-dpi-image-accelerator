# Plan de verificación — RAM AXI4-Full

Plan de verificación del DUT [`src/rtl/axi4_ram.v`](../src/rtl/axi4_ram.v) con un testbench UVM en SystemVerilog.

**Simulador:** Vivado XSim, que trae **UVM 1.2** (no IEEE 1800.2). Habilitado con `-L uvm` en `xvlog` y `xelab`.

> **Restricción de XSim:** evitar el register layer (RAL) y usos avanzados del factory — es donde XSim se rompe. Un TB de esclavo AXI4 no los necesita.

---

## Arquitectura del testbench

```
tb_top.sv
 ├── generación de clk / aresetn
 ├── axi4_if          (interface con clocking blocks)
 ├── axi4_ram  #(MEM_DEPTH = 65536)   ← DUT, RAM chica: XSim no aguanta 64 MB
 └── run_test()
       └── axi4_env
             ├── axi4_agent (master activo)
             │     ├── sequencer
             │     ├── driver    → maneja los 5 canales AXI
             │     └── monitor   → reconstruye transacciones desde las señales
             ├── axi4_scoreboard  (modelo de referencia: byte mem[longint])
             └── axi4_coverage    (covergroups)
```

El agente es **master**: el DUT es el esclavo, así que el TB genera las transacciones y verifica las respuestas.

---

## Features a verificar

| # | Feature | Cómo se verifica |
|---|---|---|
| F1 | Escritura y lectura de un solo beat | `smoke_test` — escribir, leer, comparar |
| F2 | Ráfagas `INCR` de 1, 2, 16, 256 beats | `burst_test` — el scoreboard predice cada beat |
| F3 | Ráfagas `FIXED` | La dirección no debe avanzar entre beats |
| F4 | Transferencias angostas (`AWSIZE` < `DATA_WIDTH/8`) | Solo los carriles correspondientes se escriben |
| F5 | Escrituras parciales con `WSTRB` | Los bytes con strobe en 0 no se modifican |
| F6 | `RLAST` en el último beat, y solo ahí | Chequeo en el monitor |
| F7 | Transacciones back-to-back sin burbujas | `VALID` alto en ciclos consecutivos |
| F8 | Acceso fuera de rango | Debe responder `SLVERR`, no `OKAY` |
| F9 | Comportamiento en reset | Todos los `VALID` de salida en bajo mientras `aresetn` esté en bajo |
| F10 | Independencia de canales | AW y AR concurrentes no se interfieren |
| F11 | Aleatorio con constraints | `random_test` — combinaciones no previstas |

---

## Tests

| Test | Features | Descripción |
|---|---|---|
| `base_test` | — | Clase base: construye el env y configura el reporte |
| `smoke_test` | F1, F9 | Reset, una escritura, una lectura, comparar |
| `burst_test` | F2, F3, F6, F7 | Barrido de largos y tipos de ráfaga |
| `narrow_test` | F4, F5 | Transferencias angostas y `WSTRB` parcial |
| `error_test` | F8 | Direcciones fuera de `MEM_DEPTH` |
| `random_test` | F10, F11 | N transacciones aleatorias con constraints |

### Cómo correrlos

**Linux / macOS** — con Vivado ya en el `PATH`:

```bash
source /tools/Xilinx/Vivado/2019.2/settings64.sh
./scripts/run_uvm.sh smoke_test
```

**Windows** — el script carga el entorno de Vivado solo, actualiza el repo, corre los seis tests y deja todo en `exports\<timestamp>\`:

```bat
scripts\run_uvm_windows.bat
scripts\run_uvm_windows.bat -Test burst_test
scripts\run_uvm_windows.bat -VivadoPath "D:\Xilinx\Vivado\2019.2"
scripts\run_uvm_windows.bat -Test smoke_test -Gui
```

Para una corrida limpia desde cero, sin clon previo:

```bat
scripts\run_uvm_windows.bat -Repo https://github.com/Team-Diseno-de-Alto-Nivel/mp6160-uvm-dpi-image-accelerator.git -WorkDir C:\work
```

Cada corrida deja en `exports\<timestamp>\`:

| Contenido | Qué es |
|---|---|
| `summary.txt` | Veredicto por test, rama, commit, fecha y host |
| `logs/` | `xvlog.log`, `xelab.log` y un `<test>.log` por cada test |
| `waveforms/` | Los `.wdb` que haya generado el testbench |
| `coverage/` | La base de datos de cobertura, si se generó |

`exports/` está en el `.gitignore`: son evidencia para adjuntar al PR, no artefactos versionados.

---

## Cobertura funcional

Covergroups en `axi4_coverage.sv`:

| Covergroup | Bins |
|---|---|
| `cg_burst_len` | `AWLEN`/`ARLEN`: 0, 1, 2-15, 16-63, 64-254, 255 |
| `cg_burst_size` | `AWSIZE`/`ARSIZE`: todos los valores válidos hasta `DATA_WIDTH/8` |
| `cg_burst_type` | `FIXED`, `INCR`, `WRAP` |
| `cg_wstrb` | Todos los bytes, ninguno, parcial |
| `cg_resp` | `OKAY`, `SLVERR` |
| `cross len × size` | Cruce de largo y tamaño de beat |
| `cg_align` | Direcciones alineadas vs. no alineadas al ancho del bus |

**Meta:** 100 % en `cg_burst_type`, `cg_resp` y `cg_wstrb`; ≥ 90 % en el resto.

---

## Criterio de aceptación

1. Los seis tests corren con `UVM_ERROR : 0` y `UVM_FATAL : 0`.
2. La cobertura funcional alcanza las metas de arriba.
3. `verilator --lint-only -Wall src/rtl/axi4_ram.v` sin warnings.
4. El RTL elabora limpio en las dos herramientas: `xvlog` y `verilator`.

> `run_uvm.sh` parsea el reporte final de UVM y devuelve código ≠ 0 si hay errores — **xsim devuelve 0 aunque UVM falle**, así que no sirve confiar en su código de salida.

---

## Limitación conocida

El testbench UVM **no corre en CI**: Vivado no está disponible en GitHub Actions. Lo que CI sí cubre es el lint de Verilator y la equivalencia bit a bit entre la RAM RTL y la RAM C++ de referencia sobre la imagen completa.

Los logs de XSim se adjuntan manualmente al pull request como evidencia.

---

> **TODO(integrante 2)** — A medida que se implemente: llenar la matriz de trazabilidad feature → test → covergroup con resultados reales, y anotar los bugs del RTL que el TB haya encontrado (eso último es lo que demuestra que el testbench sirve).

---

## Referencias

- [AMBA AXI Protocol Specification (ARM IHI 0022)](https://developer.arm.com/documentation/ihi0022/latest/)
- [UVM 1.2 User's Guide (Accellera)](https://www.accellera.org/downloads/standards/uvm)
- [Vivado Design Suite User Guide: Logic Simulation (UG900)](https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation)
- [ArquitecturaDPI.md](ArquitecturaDPI.md) — el puerto AXI4 y cómo se integra al modelo SystemC
