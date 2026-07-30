# Arquitectura: RAM AXI4-Full en Verilog integrada por DPI

Este documento describe cómo la RAM descrita en Verilog con puerto **AXI4-Full** se conecta al modelo SystemC/TLM que ya existía, usando **DPI-C**. Es la referencia compartida entre los tres frentes de trabajo: el RTL, el testbench UVM y el puente DPI.

Las secciones marcadas con **TODO** las completa quien implementa esa capa.

---

## Panorama

```
sc_main (SystemC, top)
  CPU ── Bus ── Disk
          ├──── Accelerator
          └──── RAM  ──► selección en tiempo de ejecución (--rtl-ram)
                          ├─ RAM     (C++, std::vector)   ← por defecto
                          └─ RamAxi  (TLM target ↔ DPI)
                                 │  llamadas DPI-C
                                 ▼
                          axi_ram_dpi.sv  (AXI master BFM)
                                 │  AXI4-Full
                                 ▼
                          axi4_ram.v      ← el mismo RTL que verifica el TB UVM
```

**Regla:** el mismo `src/rtl/axi4_ram.v` alimenta los dos flujos. Verilator lo compila para la co-simulación con SystemC; Vivado XSim lo elabora para el testbench UVM. Por eso el RTL es Verilog-2001 y no SystemVerilog — los dos simuladores no aceptan el mismo subconjunto.

---

## Paso 1: El puerto AXI4-Full

**Archivo:** [`src/rtl/axi4_ram.v`](../src/rtl/axi4_ram.v)

### Parámetros

| Parámetro | Default | Descripción |
|---|---|---|
| `ADDR_WIDTH` | 32 | Ancho del bus de direcciones |
| `DATA_WIDTH` | 64 | Ancho del bus de datos, múltiplo de 8 |
| `ID_WIDTH` | 4 | Ancho de los IDs de transacción |
| `MEM_DEPTH` | 67108864 | Tamaño en **bytes**. 64 MB en co-simulación, **65536 en el TB UVM** — XSim no aguanta 64 MB |
| `READ_LATENCY` | 1 | Ciclos de latencia en el camino de lectura |

### Canales

AXI4 separa cada transacción en cinco canales independientes, cada uno con su propio handshake `VALID`/`READY`:

| Canal | Prefijo | Dirección | Para qué |
|---|---|---|---|
| Write Address | `s_axi_aw*` | master → esclavo | Dirección, largo y tipo de la ráfaga de escritura |
| Write Data | `s_axi_w*` | master → esclavo | Los datos, con `WSTRB` como byte enables y `WLAST` en el último beat |
| Write Response | `s_axi_b*` | esclavo → master | `BRESP`: `OKAY` o `SLVERR` |
| Read Address | `s_axi_ar*` | master → esclavo | Dirección, largo y tipo de la ráfaga de lectura |
| Read Data | `s_axi_r*` | esclavo → master | Los datos, con `RRESP` y `RLAST` |

**Regla del handshake:** la transferencia ocurre en el flanco donde `VALID` y `READY` están ambos en alto. Ninguno de los dos puede esperar al otro para levantarse — generar `READY` combinacionalmente a partir de `VALID` en el mismo ciclo es la fuente clásica de deadlock aquí.

### Codificación de ráfaga

| `AWBURST`/`ARBURST` | Tipo | Comportamiento |
|---|---|---|
| `2'b00` | `FIXED` | La dirección no avanza — útil para FIFOs |
| `2'b01` | `INCR` | La dirección avanza `2^SIZE` bytes por beat |
| `2'b10` | `WRAP` | Como INCR pero da la vuelta en un límite alineado |

`AWLEN`/`ARLEN` codifica **beats − 1**, o sea de 1 a 256 beats.

**Transferencias angostas.** Cada beat activa sólo la ventana de `2^AWSIZE` (o `2^ARSIZE`) bytes que empieza en `addr mod (DATA_WIDTH/8)` — el carril lo decide la dirección del beat, no un offset fijo en 0. En una escritura de ancho completo (`SIZE = log2(DATA_WIDTH/8)`, lo único que emiten hoy el BFM y el driver UVM) esa ventana cubre el bus entero, así que el comportamiento es idéntico al de antes de soportar transferencias angostas.

**`WSTRB` en escritura parcial.** Cada carril del `WSTRB` se respeta de forma independiente del ancho del beat: un byte sólo se escribe si cae dentro de la ventana activa **y** su strobe está en alto. Fuera de la ventana, el dato de esa ventana ni se lee ni se escribe.

**Condición de `SLVERR`.** Se dispara si algún byte accedido por la ráfaga cae fuera de `MEM_DEPTH`. En lectura, `RRESP` es genuinamente por beat (cada beat es independiente), así que se calcula en el momento en que se arma ese beat. En escritura, `BRESP` es un único valor para toda la ráfaga: el error de cada beat se acumula en un registro y se combina con el del último beat recién en el momento de responder — evita el error clásico de "leer tarde" un registro no-bloqueante que todavía no reflejó el beat que se acaba de procesar.

**`FIXED` y `WRAP`.** `FIXED` mantiene la misma dirección (y por lo tanto el mismo carril) en todos los beats de la ráfaga. `WRAP` avanza igual que `INCR`, pero si el próximo beat cruzaría el final de la ventana de la ráfaga (`(AWLEN+1) × 2^AWSIZE` bytes, alineada), la dirección vuelve al inicio de esa ventana en lugar de seguir creciendo.

**`READ_LATENCY`.** Son los ciclos entre el handshake de `ARVALID`/`ARREADY` y el primer `RVALID` de la ráfaga; no afecta el espaciado entre beats ya en curso. Con el valor por defecto (`READ_LATENCY = 1`) el timing es idéntico al de antes de que el parámetro fuera configurable.

---

## Paso 2: El contrato DPI

**Archivos:** [`src/dpi/axi_ram_dpi.h`](../src/dpi/axi_ram_dpi.h) (C++) y [`src/dpi/axi_ram_dpi.svh`](../src/dpi/axi_ram_dpi.svh) (SystemVerilog)

**Contrato congelado.** Cambiarlo rompe las tres capas a la vez.

### Las cinco funciones

| Función | Dirección | Qué hace |
|---|---|---|
| `axi_dpi_req(cmd, addr, len)` | C++ → SV | Encola una petición. **No consume tiempo**, retorna de inmediato |
| `axi_dpi_done()` | C++ → SV | `1` cuando la petición encolada terminó |
| `axi_dpi_resp()` | C++ → SV | `OKAY` o `SLVERR`; solo válido cuando `done()` es 1 |
| `axi_dpi_get_wbyte(idx)` | SV → C++ | El BFM pide el byte `idx` del buffer de escritura |
| `axi_dpi_put_rbyte(idx, val)` | SV → C++ | El BFM entrega el byte `idx` leído de la RAM |

### Por qué request/poll y no una tarea bloqueante

Lo natural sería una tarea DPI que bloquee hasta que la transacción AXI termine. **Verilator no lo permite:** una función DPI exportada no puede consumir tiempo de simulación.

La solución es partir la operación en tres:

1. `axi_dpi_req()` solo **encola** y retorna.
2. El AXI master BFM hace el trabajo real en su `always_ff`, avanzando a medida que el lado C++ hace tick del reloj.
3. El lado C++ **sondea** `axi_dpi_done()` entre ticks.

Efecto colateral bueno: como el reloj avanza de verdad, en modo `--rtl-ram` el `sc_time_stamp()` de SystemC por fin refleja tiempo real de transferencia, cosa que el modelo puramente C++ no hace (ver la sección *Simulated vs. wall-clock time* del README).

Este patrón también funciona en XSim y en Questa, así que el wrapper queda portable.

### Flujo de una transacción completa

```
RamAxi::b_transport()
  │
  ├─ WRITE? → axi_dpi::load_write_buffer(payload.get_data_ptr(), len)
  │
  ├─ axi_dpi_req(cmd, addr, len)          ← encola, retorna ya
  │
  ├─ while (!axi_dpi_done()) {            ← bucle de sondeo
  │      axi_dpi::tick();                 ← medio período del reloj RTL
  │      wait(HALF_PERIOD);               ← ...y otro tanto de tiempo SystemC
  │  }                                       (el BFM llama a get_wbyte /
  │                                            put_rbyte durante estos ticks)
  ├─ READ? → axi_dpi::store_read_buffer(payload.get_data_ptr(), len)
  │
  └─ payload.set_response_status(axi_dpi_resp() == OKAY ? TLM_OK : TLM_GENERIC_ERROR)
```

### La máquina de estados del BFM

`axi_ram_dpi.sv` implementa el master con una FSM de siete estados:

```
S_IDLE ──► S_WR_ADDR ──► S_WR_DATA ⇄ S_WR_DATA_NEXT ──► S_WR_RESP ──┐
   │                                                                 │
   │                          (si quedan bytes, vuelve a S_WR_ADDR)  │
   ◄─────────────────────────────────────────────────────────────────┘
   │
   └────► S_RD_ADDR ──► S_RD_DATA ──► (siguiente ráfaga o S_IDLE)
```

**Partición en ráfagas.** `beats_for_burst()` calcula cuántos beats caben desde la posición actual respetando tres cotas a la vez: el final de la petición, el **límite de 4 KB** (AXI prohíbe que una ráfaga lo cruce) y el máximo de **256 beats** de AXI4. Cuando la petición no cabe en una ráfaga, la FSM vuelve a `S_WR_ADDR` / `S_RD_ADDR` y emite la siguiente.

**Beats de ancho completo.** Todos los beats usan `AWSIZE = log2(DATA_WIDTH/8)`; la cobertura parcial en los extremos de una petición no alineada se resuelve activando `WSTRB` sólo en los carriles cuyo byte cae dentro del rango. Es más simple que emitir beats angostos y ejercita el camino de byte-enables del DUT.

**Por qué existe `S_WR_DATA_NEXT`.** `build_write_beat()` lee `next_byte` y `beat_base`, que se actualizan con asignación no bloqueante. Dentro del mismo ciclo todavía tienen el valor viejo, así que armar el beat siguiente requiere un ciclo extra. Cuesta un ciclo por beat y evita un bug silencioso de datos corridos.

**Período de reloj:** 10 ns (`HALF_PERIOD = 5 ns` en `ram_axi.cpp`).

---

## Gotchas encontrados durante la implementación

Tres cosas que costaron tiempo y no son evidentes:

### 1. `svSetScope` es obligatorio

Llamar una función DPI **exportada** desde C++ sin fijar antes el scope de SystemVerilog aborta con:

```
%Error: Testbench C called 'axi_dpi_req' but scope wasn't set
```

Verilator registra el scope como `"<nombre del modelo>.<nombre del módulo>"`, donde el nombre del modelo es `TOP` por defecto — o sea `"TOP.axi_ram_dpi"`. `axi_dpi::init()` lo compone en runtime desde `g_top->name()` para no depender de ese default.

### 2. Ninguna palabra `verilator` al inicio de un comentario

En un archivo de RTL, `// verilator <algo>` como **primer token** después de `//` se interpreta como metacomentario, es decir una directiva. Si no la reconoce, el parseo aborta. Pasa también con mayúscula inicial.

### 3. Verilator no construye en rutas con espacios

El `verilated.mk` es un Makefile de GNU Make, que no soporta espacios en las rutas. El `verilate()` de CMake tampoco: su parser JSON se rompe, y los caracteres acentuados descompuestos lo empeoran.

`scripts/build_rtl.sh` lo detecta y avisa. Para trabajar localmente hay que clonar en una ruta sin espacios, o usar el devcontainer, que monta en `/workspace`. En CI no aparece: el runner usa `/home/runner/work/...`.

---

## Partición de transferencias grandes

El buffer de intercambio del puente está acotado a `AXI_DPI_MAX_BYTES` (1 MB), pero el CPU transfiere la imagen completa de un tiro: 6 220 800 B al cargar y 2 073 600 B al guardar.

`RamAxi::b_transport` parte el payload en chunks de hasta 1 MB y emite una petición DPI por chunk. La partición vive en la capa SystemC **a propósito**: así el tamaño del buffer no queda atado al de la imagen, y el contrato DPI no cambia si mañana se procesa 4K.

---

## Paso 3: El módulo SystemC

**Archivo:** `src/model/modules/ram_axi/ram_axi.{h,cpp}`

Debe exponer **la misma interfaz** que [`ram.h`](../src/model/modules/ram/ram.h) para ser drop-in:

```cpp
SC_MODULE(RamAxi)
{
public:
    tlm_utils::simple_target_socket<RamAxi> target_socket;
    SC_CTOR(RamAxi);
    void b_transport(tlm::tlm_generic_payload& payload,
                     sc_core::sc_time& delay);
};
```

El Bus no traduce direcciones — reenvía el payload sin tocarlo (ver [`bus.cpp`](../src/model/modules/bus/bus.cpp)). Como `RAM_BASE` es `0x0`, la dirección absoluta coincide con el offset dentro de la RAM, así que se puede pasar tal cual al RTL.

Implementado en `ram_axi.cpp`. `b_transport` parte el payload en chunks, encola cada uno con `axi_dpi_req()`, avanza el reloj del RTL con `axi_dpi::tick()` intercalando `wait(HALF_PERIOD)`, y traduce `axi_dpi_resp()` al `tlm_response_status`.

Incluye una cota de seguridad de 10 000 000 flancos por transacción: si el BFM no termina, reporta `SC_REPORT_ERROR` señalando los handshakes AXI en vez de colgarse para siempre. Es lo que aparece hoy al correr contra el stub de `axi4_ram.v`.

---

## Paso 4: Selección del backend

**Archivo:** [`src/model/sc_main.cpp`](../src/model/sc_main.cpp)

`argc`/`argv` hoy están sin usar. La bandera `--rtl-ram` elige qué módulo se enlaza a `bus.init_socket_ram`; sin ella, el comportamiento es exactamente el de hoy.

`sc_main` parsea `argv` y, según encuentre `--rtl-ram`, instancia `RamAxi` o `RAM` y enlaza `bus.init_socket_ram` al elegido. Sólo se construye el backend en uso.

Si el binario se compiló sin Verilator, `--rtl-ram` falla con un mensaje explícito en vez de ignorarse en silencio; el modo por defecto sigue funcionando igual.

---

## Cómo construir y correr

```bash
# Modelo SystemC puro (no requiere Verilator ni Vivado)
make run

# Co-simulación con la RAM RTL
make lint         # verilator --lint-only -Wall src/rtl/axi4_ram.v
make rtl          # verilata RTL + wrapper DPI
make run-rtl      # corre el sistema completo contra la RAM Verilog

# Testbench UVM (requiere Vivado en el PATH)
make uvm TEST=smoke_test
```

### Prueba de aceptación

La que demuestra que la integración DPI es correcta: correr los dos backends y comparar la salida bit a bit sobre 8 294 400 bytes de tráfico real.

```bash
make run     && cp images/output/output.raw /tmp/ref.raw
make run-rtl && cmp /tmp/ref.raw images/output/output.raw && echo "RTL == C++ ✅"
```

---

## Referencias

- [AMBA AXI Protocol Specification (ARM IHI 0022)](https://developer.arm.com/documentation/ihi0022/latest/)
- [Verilator — Connecting to C++ / DPI](https://verilator.org/guide/latest/connecting.html)
- [IEEE 1800-2017, Cláusula 35 — Direct Programming Interface](https://ieeexplore.ieee.org/document/8299595)
- [CrearModuloSystemC.md](CrearModuloSystemC.md) — cómo se implementa un módulo SystemC en este proyecto
- [PlanUVM.md](PlanUVM.md) — plan de verificación del RTL
