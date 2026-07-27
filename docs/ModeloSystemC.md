# Modelo SystemC/TLM: transacciones y mapa de memoria

Detalle del modelo a nivel de transacciones que se construyó en la **Evaluación 2** y que sigue siendo la base del sistema. El enunciado de la Evaluación 4 ya no pide estas dos secciones en el README, pero la información sigue siendo válida y explica cómo se comunican los módulos, así que vive acá.

Ver [ArquitecturaDPI.md](ArquitecturaDPI.md) para la capa nueva: la RAM en Verilog con puerto AXI4-Full y su integración por DPI.

---

## Formato de las transacciones

Toda la comunicación entre módulos usa el generic payload de TLM 2.0 (`tlm::tlm_generic_payload`).

| Campo | Tipo | Descripción |
|---|---|---|
| `command` | `tlm_command` | `TLM_READ_COMMAND` o `TLM_WRITE_COMMAND` |
| `address` | `uint64_t` | Dirección byte absoluta en el bus (el Bus resuelve el target) |
| `data_ptr` | `unsigned char*` | Puntero al buffer de datos |
| `data_length` | `unsigned int` | Tamaño de la transferencia en bytes |
| `response_status` | `tlm_response_status` | `TLM_OK_RESPONSE` al tener éxito, un código de error si no |

### Transacción de configuración del Accelerator

Cuando el CPU configura el Accelerator emite un único WRITE de 24 bytes a la dirección base del acelerador:

| Offset | Tamaño | Campo |
|---|---|---|
| `+0` | 8 B | Dirección base de la imagen de entrada en RAM (RGB) |
| `+8` | 8 B | Dirección base donde escribir la salida (escala de grises) |
| `+16` | 8 B | Cantidad total de pixeles |

Estos tres campos son exactamente los que el enunciado exige que el CPU le indique al acelerador.

### Transacción del registro de estado

El CPU **no** se bloquea en el WRITE de configuración: el Accelerator lanza el bucle de procesamiento de forma asíncrona con `sc_spawn` y retorna de inmediato. Para saber cuándo terminó, el CPU sondea un registro de 4 bytes en `accel_base + 0x18` con un READ, esperando 100 ns entre sondeos mientras el valor sea `0`:

| Offset | Tamaño | Campo | Valores |
|---|---|---|---|
| `+24` (`0x18`) | 4 B | Registro de estado | `0` = procesando, `1` = terminado |

---

## Mapa de memoria

El Bus rutea las transacciones según el rango de direcciones.

| Región | Dirección base | Tamaño | Módulo |
|---|---|---|---|
| Imagen de entrada RGB | `0x00000000` | 6 220 800 B (~5.9 MB) | RAM |
| Imagen de salida en grises | `0x00600000` | 2 073 600 B (~1.9 MB) | RAM |
| *(RAM libre)* | `0x007F9C00` | ~56 MB restantes | RAM |
| Configuración del Accelerator | `0x10000000` | 24 B | Accelerator |
| Estado del Accelerator | `0x10000018` | 4 B | Accelerator |
| Disk | `0x20000000` | — | Disk |

Capacidad total de la RAM: **64 MB** (`0x00000000` – `0x03FFFFFF`), como exige el enunciado.

Las constantes viven en [`src/model/config/memory_map.h`](../src/model/config/memory_map.h).

### Relevancia para la capa RTL

El Bus **no traduce direcciones**: reenvía el payload sin tocarlo. Como `RAM_BASE` es `0x0`, la dirección absoluta coincide con el offset dentro de la RAM, y por eso se puede pasar tal cual al puerto AXI4 del RTL sin restar una base. Si alguna vez `RAM_BASE` deja de ser cero, [`ram_axi.cpp`](../src/model/modules/ram_axi/ram_axi.cpp) tiene que restarla antes de llamar a `axi_dpi_req()`.
