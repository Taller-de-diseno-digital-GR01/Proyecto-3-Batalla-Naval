# Nivel 2

## Diagrama de segundo nivel

```mermaid
flowchart TD
    subgraph FPGA
        ROM["Memoria de programa<br/>ROM"]
        CPU["Procesador uniciclo<br/>RISC-V"]
        MAP["Controlador de mapeo"]
        RAM["Memoria de datos<br/>RAM"]
        GPIO["Entradas<br/>botones"]
        UART["UART"]
        VGA["VGA"]
        DISP["Display 7 segmentos<br/>y LED de estado"]
        BUZ["Buzzer"]
    end

    PC["Aplicación de PC<br/>Jugador 2"]

    CPU -->|"ProgAddress_o"| ROM
    ROM -->|"ProgIn_i"| CPU
    CPU -->|"DataAddress_o, DataOut_o, we_o"| MAP
    MAP -->|"DataIn_i"| CPU
    MAP <--> RAM
    GPIO --> MAP
    MAP <--> UART
    MAP <--> VGA
    MAP --> DISP
    MAP --> BUZ
    PC <-->|"UART RX/TX"| UART
```

## Objetivos

- Subdividir el sistema del nivel 1 en sus bloques principales, agrupando dentro de la FPGA el procesador, las memorias y los periféricos.
- Distinguir el camino de instrucciones entre ROM y procesador del camino de datos que pasa por el controlador de mapeo.
- Mostrar que la aplicación de PC es externa a la FPGA y se comunica exclusivamente mediante UART.

## Descripciones

### Bloque 1: Procesador uniciclo

Ejecuta el programa ensamblador que organiza las colocaciones, los turnos, los disparos y el resultado. Solicita instrucciones a la ROM y lee o escribe RAM y periféricos mediante el controlador de mapeo. La lógica de las reglas reside en el programa, no en los periféricos.

### Bloque 2: Memoria de programa (ROM)

Guarda las instrucciones del programa. Recibe `ProgAddress_o` del procesador y le entrega la instrucción mediante `ProgIn_i`. Su camino es independiente del acceso a los datos.

### Bloque 3: Memoria de datos (RAM)

Guarda los tableros, el turno, el progreso de colocación y los contadores de la partida. El procesador accede a ella a través del controlador de mapeo.

### Bloque 4: Controlador de mapeo

Decodifica las direcciones de datos, selecciona RAM o el periférico correspondiente y devuelve al procesador el dato leído. Recibe del procesador `DataAddress_o`, `DataOut_o` y `we_o`; devuelve `DataIn_i`. No interviene en la conexión independiente con ROM.

### Bloque 5: Entradas (botones)

Sincroniza y filtra los botones del Jugador 1. Expone sus estados al procesador mediante un registro mapeado; el programa interpreta la navegación, la selección, la confirmación y el reinicio.

### Bloque 6: UART

Intercambia mensajes con la PC: recibe colocaciones y disparos, y transmite validaciones, turnos, resultados y el final de partida. El programa del procesador interpreta y construye los mensajes.

### Bloque 7: VGA

Lee su mapa de casillas para generar la imagen del Jugador 1. El procesador actualiza las casillas mediante accesos al espacio de memoria de video. El periférico genera los sincronismos y la imagen, sin aplicar reglas del juego.

### Bloque 8: Display de siete segmentos y LED de estado

El display presenta las victorias acumuladas de ambos jugadores. El LED distingue colocación, batalla y resultado; el programa determina qué información mostrar.

### Bloque 9: Buzzer

Genera sonidos para colocación inválida, impacto, fallo, barco hundido y victoria. El programa indica el evento y el periférico produce la señal sonora.

### Elemento externo: Aplicación de PC

Permite al Jugador 2 elegir acciones y ver sus tableros, turno y resultados. Se comunica con la FPGA por UART y no decide reglas ni recibe ubicaciones ocultas del Jugador 1.

### Interfaz principal

- **ROM ↔ procesador:** `ProgAddress_o` y `ProgIn_i` son los nombres indicados en el enunciado.
- **Procesador ↔ controlador:** `DataAddress_o`, `DataOut_o`, `we_o` y `DataIn_i` son los nombres indicados en el enunciado.
- **Controlador ↔ memorias y periféricos:** se decodifican las direcciones del mapa de memoria. Los nombres concretos de las conexiones de cada bloque se fijarán al diseñar sus interfaces.
- **UART ↔ aplicación de PC:** enlace serial bidireccional; la PC actúa como interfaz del Jugador 2.

El diagrama presenta las conexiones funcionales del segundo nivel. El reloj y el reinicio llegan a los bloques que los requieren, pero se omiten sus líneas repetidas para mantenerlo legible.
