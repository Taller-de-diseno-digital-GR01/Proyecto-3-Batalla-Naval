# PERIFERICO_LED

## a) Nombre del módulo

PERIFERICO_LED, módulo `periferico_led` en `src/design/periferico_led.sv`.

## b) Diagrama modular

```mermaid
flowchart LR
    IN_WE(["write_enable_i<br/>(AND_WE)"]) --> PL["PERIFERICO_LED<br/>0x0001_0138 a 0x0001_013F"]
    IN_ADDR(["addr_i[1:0]<br/>({1'b0, DataAddress_o[2]})"]) --> PL
    IN_WD(["wdata_i[31:0]<br/>(DataOut_o)"]) --> PL
    PL --> OUT_RD(["rdata_o[31:0]<br/>(MUX_LECTURA)"])
    PL --> OUT_LED(["leds_o[2:0]<br/>(LD0 a LD2)"])
```

Es el bloque `PERIFERICO_LED` del nivel 2 visto desde afuera. Lo que tiene adentro está en el inciso i).

## c) Objetivo del módulo

Mostrar en los LEDs de la Basys 3 en qué fase está la partida, colocación, batalla o resultado, como pide la
sección 4.5.4 del enunciado. Cada fase tiene su propio LED, así que se distinguen de un vistazo.

El periférico no sabe en qué fase está el juego. El programa la lleva y escribe el patrón de LEDs cada vez que
cambia de fase. El hardware solo guarda lo escrito y lo saca a los pines.

## d) Entradas

- `clk_i`, `rst_i`.
- `write_enable_i`, habilitación de escritura, desde `AND_WE` del bus de datos (`we_o` del CPU en AND con
  `sel_led`).
- `addr_i[1:0]`, dirección del registro. No sale directo de `DataAddress_o[3:2]`, ver el inciso f).
- `wdata_i[WIDTH-1:0]`, dato a escribir, desde `DataOut_o` del CPU.

El módulo tiene el parámetro `WIDTH = 32`.

## e) Salidas

- `rdata_o[WIDTH-1:0]`, contenido del registro apuntado por `addr_i`, hacia el multiplexor de lectura que
  llega a `DataIn_i` del CPU.
- `leds_o[2:0]`, a LD0, LD1 y LD2. Activos en alto.

## f) Relación con otros módulos

Habla con un solo maestro, el CPU, a través de `BUS_DATOS`. No instancia ningún submódulo.

La decodificación de dirección tiene la misma trampa que `PERIFERICO_7SEG`, vista desde el otro lado. Los
displays están en `0x0001_0130` y el LED en `0x0001_0138`, dentro del mismo bloque de 16 bytes. `sel_led` sale
de comparar `DataAddress_o[31:3]` contra `0x0001_0138 >> 3`, y el periférico queda en `0x0001_0138` a
`0x0001_013F`.

Con eso `DataAddress_o[3]` vale 1 en todo el rango del LED. Si `addr_i` fuera `DataAddress_o[3:2]` como en
los demás periféricos, el registro de offset `0x00` llegaría con `addr_i = 2'b10`. En el top `addr_i` se
arma como `{1'b0, DataAddress_o[2]}`, y así `0x0001_0138` llega como `2'b00`, que es el offset que da la
tabla del enunciado. El periférico sigue la interfaz estándar sin saber en qué bloque está.

Hacia afuera los pines van a los tres primeros LEDs de la Basys 3.
