# NUCLEO_UART_RX

## a) Nombre del módulo

NUCLEO_UART_RX, módulo `uart_rx` en `src/design/uart_rx.sv`.

## b) Diagrama modular

```mermaid
flowchart LR
    IN_RX(["i_rx<br/>(pin B18)"]) --> NUC_RX["NUCLEO_UART_RX<br/>uart_rx, TICKS_X16 = 54"]
    NUC_RX --> OUT_DATO(["o_dato[7:0]<br/>(REG_DATOS_RX)"])
    NUC_RX --> OUT_LISTO(["o_dato_listo<br/>(REG_DATOS_RX, REG_CONTROL)"])
```

## c) Objetivo del módulo

Recuperar los bytes 8N1 a 115200 baudios que llegan por la línea serial desde la app de PC. Es la
transcripción a SystemVerilog de `UART_rx.vhd`, el núcleo que da el curso, con la misma máquina de
estados y los mismos tiempos. Solo se cambió el genérico del baudaje, porque el original venía
calculado para un reloj de 16 MHz.

## d) Entradas

- `clk`, reloj del sistema de 100 MHz.
- `rst`, reset síncrono.
- `i_rx`, línea serial cruda desde el pin B18. Reposa en uno.

El módulo tiene el parámetro `TICKS_X16 = 54`, ciclos de reloj por tick de sobremuestreo.

## e) Salidas

- `o_dato[7:0]`, último byte recibido. Queda estable hasta que termina el siguiente.
- `o_dato_listo`, pulso de un ciclo que avisa que `o_dato` tiene un byte nuevo.

## f) Relación con otros módulos

Solo lo instancia `PERIFERICO_UART`, como `nucleo_rx`. `o_dato` va a `REG_DATOS_RX` y `o_dato_listo`
es la condición que carga ese registro y sube `new_rx` en `REG_CONTROL`. Como el pulso dura un ciclo,
el programa no podría sondearlo directo, y por eso el periférico lo convierte en la bandera `new_rx`.

Hacia afuera `i_rx` llega directo del pin `RsRx` del puente USB-UART, por donde entra lo que manda la
app de PC del Jugador 2.

## g) Explicación de funcionamiento

Un contador libre da un pulso `tick_x16` cada `TICKS_X16` ciclos, dieciséis veces por tiempo de bit.
La máquina de estados solo avanza en esos pulsos.

En reposo mira la línea en cada tick. Cuando la ve en cero cree que empezó un bit de arranque y cuenta
ocho ticks más, medio bit, revisando que la línea siga en cero. Si en ese medio bit la línea vuelve a
uno, era ruido y regresa a reposo. Si no, ya está parado en el centro del bit de arranque, y desde ahí
cuenta de 16 en 16 para muestrear el centro de cada uno de los ocho bits de datos, del menos
significativo al más significativo. Dieciséis ticks después del último dato, en el centro del bit de
parada, copia el byte a `o_dato` y levanta `fin_rx`. Un detector de flanco lo recorta a un pulso de un
ciclo en `o_dato_listo`.

## h) Diseño

### Divisor de sobremuestreo

`cuenta_tick` baja de `TICKS_X16 - 1` a cero, y en cero da el pulso y se recarga. El tick tiene que ir
a 16 veces el baudaje, `868.06 / 16 = 54.25`, se usa 54. El genérico original era 9.

Ese redondeo es el que aprieta. Cada tick sale 0.47% más rápido de lo ideal. El último bit de datos se
muestrea en el tick 136 contado desde el tick que vio el flanco, o sea a `136 x 54 = 7344` ciclos. El
centro real de ese bit está en `8.5 x 868.06 = 7379` ciclos. El desfase es de 35 ciclos contra los 434
que serían medio bit, más de diez veces de margen. A eso se suma hasta un tick de atraso en ver el
flanco, 54 ciclos, que también cabe.

### Máquina de estados

| Estado     | Condición en `tick_x16`         | Acción                                            | Siguiente  |
| ---------- | ------------------------------- | ------------------------------------------------- | ---------- |
| `REPOSO`   | `i_rx = 0`                      | limpia `dato_parcial`, `cuenta_bit`, `indice_bit` | `ARRANQUE` |
| `ARRANQUE` | `i_rx = 1`                      | nada, era ruido                                   | `REPOSO`   |
| `ARRANQUE` | `i_rx = 0` y `cuenta_bit = 7`   | `cuenta_bit = 0`                                  | `DATOS`    |
| `ARRANQUE` | `i_rx = 0` y `cuenta_bit < 7`   | `cuenta_bit + 1`                                  | `ARRANQUE` |
| `DATOS`    | `cuenta_bit = 15`               | `dato_parcial[indice_bit] = i_rx`, `cuenta_bit = 0` | `PARADA` si `indice_bit = 7`, si no `DATOS` con `indice_bit + 1` |
| `DATOS`    | `cuenta_bit < 15`               | `cuenta_bit + 1`                                  | `DATOS`    |
| `PARADA`   | `cuenta_bit = 15`               | `o_dato = dato_parcial`, `fin_rx = 1`             | `REPOSO`   |
| `PARADA`   | `cuenta_bit < 15`               | `cuenta_bit + 1`                                  | `PARADA`   |

`fin_rx` baja en el siguiente tick, ya en `REPOSO`, así que queda alto un tick de sobremuestreo.

En `PARADA` no se revisa que la línea esté en uno. Un byte con el bit de parada malo se entrega igual,
sin bandera de error de trama. El protocolo del juego lo cubre con el `0xAA` de inicio y el checksum
XOR que valida el ensamblador.

### Entrada sin sincronizador

`i_rx` entra directo a la máquina de estados, sin los dos flip-flops que recomienda la sección 3.3 de
`investigacion-previa.md`. Así viene el `UART_rx.vhd` del curso, y el profesor confirmó el 22 de
setiembre que no hace falta agregarlos. La línea cambia a lo sumo una vez cada 868 ciclos, lo que hace
muy improbable caer en metaestabilidad, aunque no la descarta. La mitigación estándar serían dos
flip-flops en cascada antes de `i_rx`.

### Latches

Todos los bloques son `always_ff` con reset síncrono. Sintetizado con yosys dentro de
`periferico_uart` no aparece ningún `Latch inferred`.

## i) Diagrama esquemático detallado del diseño

![Esquemático por compuertas de NUCLEO_UART_RX](../diagramas/uart_rx.png)

El esquemático sale de sintetizar el `.sv` con yosys, bajarlo a AND, OR, XOR, NOT, MUX y flip-flops D
con `abc`, y dibujarlo con netlistsvg. Cada compuerta o flip-flop lleva encima el nombre de la señal que
produce cuando esa señal tiene nombre en el RTL. Las que no tienen nombre son la lógica que yosys arma
para el reset y los `if` de cada registro.

Arriba está el núcleo con `DIVISOR` y `DETECTOR_FIN`, uno por `always` del `.sv`. La máquina de estados
está partida por registro, `FSM_ESTADO`, `FSM_CUENTA_BIT`, `FSM_INDICE_BIT`, `FSM_DATO_PARCIAL`,
`FSM_O_DATO` y `FSM_FIN_RX`, y las comparaciones que usan varios de ellos quedan en `FSM_COMUN` con
salidas como `estado==DATOS` o `cuenta_bit==15`. Abajo está cada bloque abierto a compuertas.

Se genera con `TICKS_X16 = 4`, dato de 2 bits e `indice_bit` de 1 bit. Con los valores reales cambia el
ancho de los contadores y la cantidad de copias por bit de dato, no la estructura.

`cuenta_tick`, `cuenta_bit` e `indice_bit` se dibujan de 2, 4 y 1 bits. En el `.sv` están declarados
como `int`, y yosys los sintetiza como contadores de 32 bits aunque no pasen de 53, 15 y 7. Con esos
tres en 32 bits la máquina de estados sola da más de 800 compuertas. TODO: Revisar si se cambian a
`logic` con el ancho justo.

## j) Diagrama completo de conexiones del diseño

Conexiones dentro de `PERIFERICO_UART`:

- `clk`, a `clk_i`.
- `rst`, a `rst_i`.
- `i_rx`, a `rx_i`, que en el top viene del pin B18 con `IOSTANDARD LVCMOS33`.
- `o_dato_listo`, a `listo_rx`.
- `o_dato`, a `dato_rx`.

Igual que en los demás módulos, el diagrama por chips que pide el método no aplica a un diseño que se
sintetiza dentro de una sola FPGA, y esta lista de puertos es el reemplazo propuesto.
