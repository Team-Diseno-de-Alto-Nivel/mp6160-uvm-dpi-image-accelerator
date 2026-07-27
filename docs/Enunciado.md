**Evaluación Corta 4** 

**Nombre:** 

**Semana # 8: 2/Julio/2026** 

**Diseño de Alto Nivel - MP6160: II Cuatrimestre 2026** 

**Profesor: Luis G. León-Vega, Ph.D** 

## **Instrucciones:** 

Para esta evaluación, cada grupo deberá desarrollar un módulo en Verilog que le permita hacer un testbench con UVM. Asimismo, debe interconectarlo con VPI/DPI mediante SystemC. Esto con el sistema ya realizado previamente en SystemC. 

Recordando que el sistema implementa el siguiente flujo: 

1. El **CPU** debe cargar una imagen desde un almacenamiento persistente (módulo de SC), representado por una carpeta en el computador. 

2. La imagen debe estar en formato **RAW RGB** y corresponder a una resolución de **1080p** . 

3. El CPU debe almacenar la imagen en una **memoria RAM de 64 MB** . 

4. El CPU debe indicar al acelerador: 

   - La dirección base de la imagen de entrada en RAM. 

   - La dirección base donde debe escribirse la imagen de salida. 

   - La cantidad total de pixeles a procesar. 

5. El **acelerador** debe leer la imagen RGB desde memoria, convertirla a escala de grises y escribir el resultado en otra región de la RAM. 

6. Finalmente, el CPU debe leer la imagen procesada desde memoria y almacenarla nuevamente en disco. 

# **Requerimientos de la implementación** 

Se deben satisfacer: 

- Describir el módulo de memoria RAM en Verilog, con un puerto AXI4 Full. 

- Crear un testbench siguiendo el estándar UVM y SystemVerilog. 

- Integrar el módulo de RAM en el modelo del sistema (hecho en la segunda evaluación) usando DPI/VPI. 

# **Entregables** 

Considere la entrega en un repositorio de GitHub con lo siguiente: 

- Código fuente en Verilog y SystemVerilog: implementación + testbench. 

- Código fuente en SystemC del acelerador y sus auxiliares. 

- Scripts para correr la simulación en SystemVerilog 

- Scripts para automatizar la construcción del modelo, junto con DPI/VPI y el RTL. 

- Imagen de entrada en formato RAW RGB. 

- Imagen de salida generada por el sistema. 

- Diagrama de bloques de la arquitectura propuesta. 

- README con contenido técnico explicando: 

   - Instrucciones para satisfacer requisitos y compilación. 

   - Organización del repo. 

   - Organización de los módulos. 

   - Diagrama de bloques. 

   - Diagrama de secuencias. 

   - Resultados obtenidos. 

# **En caso de uso de Inteligencia Artificial** 

_De acuerdo con el incentivo de uso de Inteligencia Artificial, si esta se utiliza para alguna evaluación, debe indicarse una declaración sobre su uso, incluyendo los prompts y la clase de utilización que se da, por ejemplo: revisión de código, consulta de conceptos, depuración, generación de diagramas o mejora de redacción. Una falla en esta declaración implicará la aplicación de la normativa de plagio._ 

**Fecha de Entrega** : 30 de Julio del 2026. 

