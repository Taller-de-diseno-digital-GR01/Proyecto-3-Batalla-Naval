# PERIFERICO_ENTRADAS

## a) Nombre del módulo

PERIFERICO_ENTRADAS, módulo `periferico_entradas` en `src/design/periferico_entradas.sv`.

## b) Diagrama modular

```mermaid
flowchart LR
    IN_WE(["write_enable_i<br/>(AND_WE)"]) --> PE["PERIFERICO_ENTRADAS<br/>0x0001_0120 a 0x0001_012F"]
    IN_ADDR(["addr_i[1:0]<br/>(DataAddress_o[3:2])"]) --> PE
    IN_WD(["wdata_i[31:0]<br/>(DataOut_o)"]) --> PE
    IN_BTN(["botones_i[6:0]<br/>(botones del Jugador 1)"]) --> PE
    PE --> OUT_RD(["rdata_o[31:0]<br/>(MUX_LECTURA)"])
```

Es el bloque `PERIFERICO_ENTRADAS` del nivel 2 visto desde afuera. Lo que tiene adentro está en el inciso i).

## c) Objetivo del módulo

Poner el estado de los siete botones del Jugador 1 en el bus de datos, en un solo registro de lectura en
`0x0001_0120`, como pide la sección 4.5.2 del enunciado.

El periférico no sabe qué hace cada botón ni si una presión es nueva. Eso lo decide el programa. El hardware
solo registra los pines y los entrega cuando el CPU lee esa dirección.

## d) Entradas

- `clk_i`, `rst_i`.
- `write_enable_i`, habilitación de escritura, desde `AND_WE` del bus de datos. El periférico no tiene nada
  que escribir y la ignora, está solo porque es parte de la interfaz estándar de la sección 4.5.5.
- `addr_i[1:0]`, dirección del registro, sale de `DataAddress_o[3:2]` del CPU.
- `wdata_i[WIDTH-1:0]`, desde `DataOut_o` del CPU. Se ignora igual que `write_enable_i`.
- `botones_i[6:0]`, los siete botones del Jugador 1 directo de los pines, activos en alto. El orden es el
  mismo de los bits del registro, `botones_i[0]` es `BTN_ARRIBA` y `botones_i[6]` es `BTN_RST`.

El módulo tiene el parámetro `WIDTH = 32`.

## e) Salidas

- `rdata_o[WIDTH-1:0]`, registro de estado con `addr_i = 2'b00` y ceros en cualquier otra dirección, hacia el
  multiplexor de lectura que llega a `DataIn_i` del CPU.

## f) Relación con otros módulos

Habla con un solo maestro, el CPU, a través de `BUS_DATOS`. No instancia ningún submódulo.

La decodificación de dirección es la sencilla. En el bloque de 16 bytes de `0x0001_0120` no hay otro
periférico, así que `sel_entradas` sale de comparar `DataAddress_o[31:4]` contra `0x0001_012`, igual que la
UART. El periférico ocupa `0x0001_0120` a `0x0001_012F` aunque solo use la primera palabra.

Hacia afuera los pines van a los cinco botones de la Basys 3 y a dos botones externos en el Pmod JC.

## g) Explicación de funcionamiento

`REG_ESTADO` copia los siete pines en cada flanco del reloj. El programa hace `lw` en `0x0001_0120` y recibe
esa copia en los bits bajos. Un bit en 1 significa que ese botón estaba presionado en el ciclo anterior.

El registro da niveles, no presiones. Si el Jugador 1 deja apretado `BTN_DER`, el bit 3 se lee en 1 en todas
las vueltas del lazo mientras siga apretado. Para mover el cursor una sola casilla por presión, el programa
guarda la lectura anterior en un registro y se queda con los bits que pasaron de 0 a 1.

```asm
lw   t0, 0(s1)        # s1 = 0x0001_0120, t0 = estado actual
xori t1, s2, -1       # s2 = estado de la vuelta anterior, t1 = ~anterior
and  t1, t0, t1       # t1 = botones recién presionados
addi s2, t0, 0        # para la próxima vuelta
```

Son cuatro instrucciones del conjunto mínimo. El ejemplo solo muestra la idea, el programa real y sus
registros se documentan en el diseño del ensamblador.

Una presión dura decenas de milisegundos y una vuelta del lazo principal dura microsegundos, así que el
programa ve cada presión muchas veces seguidas y no se le escapa ninguna mientras ninguna rutina se quede
tanto tiempo sin volver al lazo.

## h) Diseño

### Mapa de registros

La tabla de la sección 4.4.3 del enunciado fija un registro de estado en `0x0001_0120`. El orden de los bits
es el que propone la investigación previa (sección 6.3).

- `2'b00` (`0x0001_0120`), registro de estado, solo lectura.
  - `[0]`, `BTN_ARRIBA`, mueve el cursor una fila arriba.
  - `[1]`, `BTN_ABAJO`, mueve el cursor una fila abajo.
  - `[2]`, `BTN_IZQ`, mueve el cursor una columna a la izquierda.
  - `[3]`, `BTN_DER`, mueve el cursor una columna a la derecha.
  - `[4]`, `BTN_SEL`, rota el barco que se está colocando.
  - `[5]`, `BTN_OK`, confirma una colocación o un disparo.
  - `[6]`, `BTN_RST`, reinicia la partida conservando los contadores de ganadas.
  - `[31:7]`, reservados, se leen en cero.
- `2'b01`, `2'b10` y `2'b11` (`0x0001_0124` a `0x0001_012C`), sin asignar. Las lecturas devuelven ceros.

Las escrituras no tienen efecto en ninguna dirección. Lo que hace cada botón en el juego lo decide el
programa, la lista solo dice para qué lo va a usar.

### Sin antirrebote

La sección 4.5.2 pide debouncing, pero según el profesor los botones de la Basys 3 ya llegan filtrados por la
tarjeta y no hace falta repetirlo en el periférico. Con eso el `debounce` y el detector de flanco de
`botones.sv` del Proyecto 2 no se traen. El flanco lo saca el programa, como se ve en el inciso g).

Eso vale para los cinco botones de la tarjeta. `BTN_SEL` y `BTN_OK` son botones externos en el Pmod JC y
no pasan por el filtrado de la Basys 3, así que pueden rebotar. Un rebote en `BTN_OK` se leería como dos
confirmaciones seguidas, y en la batalla eso puede ser un disparo de más.

TODO: Revisar con el profesor si `BTN_SEL` y `BTN_OK` en el Pmod JC también se pueden leer sin antirrebote, o si se filtran por software en el programa.

### REG_ESTADO

| Condición | `estado'`         |
| --------- | ----------------- |
| `rst_i`   | `0`               |
| resto     | `botones_i[6:0]`  |

Es de 7 bits y no tiene habilitación. Está por timing, no para sincronizar. Sin él, el pin iría por
`MUX_RD`, `MUX_LECTURA` y `DataIn_i` hasta el banco de registros del CPU en un solo camino combinacional que
arranca en un pin asíncrono y que nadie restringe. Con el registro el pin termina en un flip-flop, y lo que
lee el CPU no cambia en medio del ciclo. Es un solo flip-flop por bit, sin la cadena de dos de un
sincronizador.

### MUX_RD

| `addr_i`   | `rdata_o`                         |
| ---------- | --------------------------------- |
| `2'b00`    | `{{(WIDTH-7){1'b0}}, estado}`     |
| resto      | `0`                               |

### Pines de BTN_SEL y BTN_OK

La Basys 3 trae cinco botones y el enunciado pide siete. Los cuatro de la cruz van a la navegación y el
central a `BTN_RST`, como dice `nivel01.md`. `BTN_SEL` y `BTN_OK` van a los mismos pines del Pmod JC que en el
Proyecto 2, N17 y P18, con los mismos dos botones externos. Pasarlos a switches evitaba el rebote, pero un
switch no vuelve solo y cada confirmación serían dos movimientos.

### Reset y BTN_RST

`rst_i` es el reinicio general. Después de `rst_i` los siete bits se leen en cero, que es lo correcto porque
nadie está presionando nada al arrancar.

`BTN_RST` no puede llegar a `rst_i` de este periférico. Si llegara, mientras el botón esté apretado
`REG_ESTADO` estaría en reset y el bit 6 se leería en cero, así que el programa nunca vería la presión.
`BTN_RST` es un bit más del registro, y el reinicio de la partida lo hace el programa, que es lo que ya dice
`nivel01.md`.

TODO: Revisar cuál es el reinicio general del sistema, el enunciado no lo define. Es la misma pregunta abierta que en `PERIFERICO_7SEG.md` y `PERIFERICO_BUZZER.md`.

### Latches

`REG_ESTADO` va en un `always_ff` con reset síncrono. `MUX_RD` es un `always_comb` con `case` y rama
`default`.

## i) Diagrama esquemático detallado del diseño

```mermaid
flowchart LR
    BTN(["botones_i[6:0]"]) --> REG["REG_ESTADO<br/>registro 7b"]
    REG -->|"estado[6:0]"| MUX_RD{{"MUX_RD<br/>addr_i == 00"}}
    ADDR(["addr_i[1:0]"]) --> MUX_RD
    MUX_RD --> OUT_RD(["rdata_o[31:0]"])
```

`clk_i` y `rst_i` entran a `REG_ESTADO` aunque no se dibujen. `write_enable_i` y `wdata_i` no se conectan a
nada.

TODO: Revisar y reemplazar por el esquemático por compuertas generado desde `periferico_entradas.sv` cuando exista, igual que en `PERIFERICO_UART.md`.

## j) Diagrama completo de conexiones del diseño

Es el único módulo con puertos hacia los botones, así que acá van las restricciones de pin que tienen que
quedar en `src/fpga/basys3.xdc`.

- `botones_i[0]`, `BTN_ARRIBA`, a T18, `btnU` de la Basys 3.
- `botones_i[1]`, `BTN_ABAJO`, a U17, `btnD`.
- `botones_i[2]`, `BTN_IZQ`, a W19, `btnL`.
- `botones_i[3]`, `BTN_DER`, a T17, `btnR`.
- `botones_i[4]`, `BTN_SEL`, a N17, pin JC3 del Pmod JC, igual que en el Proyecto 2.
- `botones_i[5]`, `BTN_OK`, a P18, pin JC4 del Pmod JC, igual que en el Proyecto 2.
- `botones_i[6]`, `BTN_RST`, a U18, `btnC`.
- Todos con `IOSTANDARD LVCMOS33`.

Conexiones en el top.

- `clk_i`, al reloj global de 100 MHz, pin W5.
- `rst_i`, al reinicio general del sistema, nunca a `BTN_RST`.
- `write_enable_i`, a la salida de `AND_WE`, en alto solo cuando `we_o` está en alto y `DataAddress_o` cae
  entre `0x0001_0120` y `0x0001_012F`.
- `addr_i[1:0]`, a `DataAddress_o[3:2]`.
- `wdata_i[31:0]`, a `DataOut_o`.
- `rdata_o[31:0]`, a `MUX_LECTURA`, que alimenta `DataIn_i` del CPU.
- `botones_i[6:0]`, a los siete puertos de botón del top en el orden de la lista de arriba.

Igual que en los demás módulos, el diagrama por chips que pide el método no aplica a un diseño que se
sintetiza dentro de una sola FPGA, y esta lista de puertos es el reemplazo propuesto.
