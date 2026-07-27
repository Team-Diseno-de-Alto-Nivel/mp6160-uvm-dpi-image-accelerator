**Evaluación Corta 2** 

**Nombre:** 

**Semana # 4: 4/Junio/2026** 

## **Diseño de Alto Nivel - MP6160: II Cuatrimestre 2026** 

**Profesor: Luis G. León-Vega, Ph.D** 

## **Instrucciones:** 

Para esta evaluación, cada grupo deberá desarrollar un modelo de sistema a nivel electrónico utilizando **SystemC** y **TLM 2.0** . El objetivo es modelar, a nivel de transacciones, una arquitectura compuesta por un procesador, una memoria RAM, un almacenamiento persistente y un acelerador de procesamiento de imagen. 

El sistema deberá implementar el siguiente flujo: 

1. El **CPU** debe cargar una imagen desde un almacenamiento persistente (módulo de SC), representado por una carpeta en el computador. 

2. La imagen debe estar en formato **RAW RGB** y corresponder a una resolución de **1080p** . 

3. El CPU debe almacenar la imagen en una **memoria RAM de 64 MB** . 

4. El CPU debe indicar al acelerador: 

   - La dirección base de la imagen de entrada en RAM. 

   - La dirección base donde debe escribirse la imagen de salida. 

   - La cantidad total de pixeles a procesar. 

5. El **acelerador** debe leer la imagen RGB desde memoria, convertirla a escala de grises y escribir el resultado en otra región de la RAM. 

6. Finalmente, el CPU debe leer la imagen procesada desde memoria y almacenarla nuevamente en disco. 

## **Requerimientos del modelo** 

Se deben satisfacer: 

- El sistema debe estar descrito en **SystemC** . 

- La comunicación entre los componentes debe modelarse usando **TLM 2.0** . 

- El bus de datos debe representarse mediante transacciones TLM entre los módulos. 

- La memoria RAM debe tener una capacidad máxima de **64 MB** . 

- El almacenamiento persistente puede modelarse como acceso a archivos dentro de una carpeta local. 

- El acelerador debe implementar la conversión RGB a escala de grises. 

- El modelo debe mostrar claramente la separación entre: 

- Procesamiento funcional. 

- Comunicación mediante TLM. 

- Almacenamiento temporal en memoria. 

- Entrada y salida persistente. 

## **Componentes esperados** 

- **CPU:** controla el flujo general del sistema, carga la imagen, configura el acelerador y guarda el resultado. 

- **Memoria RAM:** almacena la imagen original y la imagen procesada. 

- **Almacenamiento persistente:** representa el disco o sistema de archivos desde donde se lee y escribe la imagen. 

- **Acelerador:** procesa la imagen RGB y genera una versión en escala de grises. 

- **Bus TLM:** modela la comunicación entre CPU, memoria y acelerador mediante transacciones. 

## **Entregables** 

Considere la entrega en un repositorio de GitHub con lo siguiente: 

- Código fuente en SystemC. 

- Imagen de entrada en formato RAW RGB. 

- Imagen de salida generada por el sistema. 

- Diagrama de bloques de la arquitectura propuesta. 

- README con contenido técnico explicando: 

   - Instrucciones para satisfacer requisitos y compilación. 

   - Organización del repo. 

   - Organización de los módulos. 

   - Diagrama de bloques. 

   - Diagrama de secuencias. 

   - Formato de las transacciones. 

   - Mapa de memoria utilizado. 

   - Resultados obtenidos. 

## **En caso de uso de Inteligencia Artificial** 

_De acuerdo con el incentivo de uso de Inteligencia Artificial, si esta se utiliza para alguna evaluación, debe indicarse una declaración sobre su uso, incluyendo los prompts y la clase de utilización que se da, por ejemplo: revisión de código, consulta de conceptos, depuración, generación de diagramas o mejora de redacción. Una falla en esta declaración implicará la aplicación de la normativa de plagio._ 

**Fecha de Entrega** : 18 de Junio del 2026. 

