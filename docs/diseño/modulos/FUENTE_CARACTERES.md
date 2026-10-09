# FUENTE_CARACTERES

## a) Nombre del módulo

FUENTE_CARACTERES, módulo `fuente_caracteres` en `src/design/fuente_caracteres.sv`.

## b) Diagrama modular

```mermaid
flowchart LR
    IN_COD(["codigo_i[5:0]<br/>(caracter o caracter2 de la casilla)"]) --> FUE["FUENTE_CARACTERES<br/>ROM combinacional 5 × 7"]
    IN_FILA(["fila_i[2:0]<br/>(glifo_fila)"]) --> FUE
    FUE --> OUT(["bits_o[4:0]<br/>(al selector de píxel)"])
```

## c) Objetivo del módulo

Guardar la forma de cada letra y número que el VGA puede dibujar dentro de una casilla. Con el
código de un carácter y una de sus filas, devuelve qué columnas de esa fila van encendidas. Es lo
que deja al HUD escribir títulos, letras de columna, números de fila y mensajes.

No sabe dónde está la casilla ni de qué color es. Solo guarda dibujos.

## d) Entradas

- `codigo_i[5:0]`, código del carácter en ASCII − 32, desde los registros `caracter` o `caracter2` del puerto B de
  la memoria de video. `0` es el espacio.
- `fila_i[2:0]`, fila del glifo, de 0 (arriba) a 7. La 7 siempre sale en blanco.

## e) Salidas

- `bits_o[4:0]`, los 5 puntos de esa fila. `bits_o[4]` es la columna izquierda y `bits_o[0]` la
  derecha. Un 1 es un punto encendido.

## f) Relación con otros módulos

Solo lo instancia `PERIFERICO_VGA`, como `u_fuente`. `codigo_i` le llega de `caracter` (bits `[9:4]`
de la palabra de la casilla) o de `caracter2` (bits `[15:10]`), según la mitad de la casilla que
se está barriendo y el bit `centrado`. `fila_i` le llega de `glifo_fila`, que es `v_count[4:1]`
atrasado un ciclo menos 5. `bits_o` va al multiplexor que elige el punto de la columna
`glifo_col`, y de ahí al selector de píxel. La fuente es una sola y la comparten las dos mitades,
porque en cada píxel solo se dibuja una.

El testbench `tb_periferico_vga` también lo instancia, una vez y por separado, para leer la tabla
completa al arrancar y usarla en su modelo.

## g) Explicación de funcionamiento

Es una tabla. La entrada `{codigo_i, fila_i}` selecciona una de 512 filas posibles, y cada fila
guarda 5 bits. Para el carácter `A` (código 33):

```
fila 0   01110    .###.
fila 1   10001    #...#
fila 2   10001    #...#
fila 3   10001    #...#
fila 4   11111    #####
fila 5   10001    #...#
fila 6   10001    #...#
fila 7   00000    .....
```

El periférico amplía cada punto a 2 × 2 píxeles, así que la letra mide 10 × 14 píxeles y entran
dos por casilla de 32 × 32, una en cada mitad.

## h) Diseño

### Por qué ASCII − 32

Los caracteres imprimibles empiezan en el espacio, `0x20`. Restar 32 deja el espacio en 0, que
es justo el valor de una casilla sin texto, y deja el rango `0x20`–`0x5F` (espacio, signos, dígitos
y mayúsculas) en los 64 códigos de 6 bits. El programa obtiene el código de cualquier letra con la
misma cuenta, sin tabla: `'A' − 32 = 33`, `'0' − 32 = 16`.

### Qué caracteres trae

Espacio, `0` a `9`, `A` a `Z`, y `!`, `-`, `:`. Son 40 de los 64 códigos posibles. Los demás caen
en el `default` y salen en blanco. El HUD solo usa letras y dígitos.

Para agregar un carácter basta con sumar sus 7 filas al `case`, con su código. No hace falta
tocar el periférico ni el programa.

### La fuente

Es una fuente de 5 × 7 del mismo estilo que la de las pantallas de caracteres tipo HD44780. Se
eligió 5 × 7 porque, ampliada × 2, entran dos letras por casilla y 40 por fila de pantalla, que es
lo que necesitan los mensajes del HUD, y se sigue leyendo bien desde lejos. Ampliar × 2 es tomar
`h_count[4:1]` y `v_count[4:1]`, sin divisor.

### Implementación

`always_comb` con un `case` sobre `{codigo_i, fila_i}` y una rama `default` en cero, así que no
infiere latches. En la FPGA queda como lógica en LUT, de solo lectura. Corre en el dominio de
`clk_pix_i` porque su entrada sale de registros de ese dominio, y tiene un ciclo completo de 40 ns
para resolverse dentro del selector de píxel.

## i) Diagrama esquemático detallado del diseño

```mermaid
flowchart LR
    COD(["codigo_i[5:0]"]) --> CAT["{codigo_i, fila_i}<br/>9 bits"]
    FILA(["fila_i[2:0]"]) --> CAT
    CAT --> ROM{{"ROM 512 × 5<br/>case con default 0"}}
    ROM --> OUT(["bits_o[4:0]"])
```

Es combinacional, no recibe reloj.

## j) Diagrama completo de conexiones del diseño

No tiene puertos hacia pines de la Basys 3, así que no agrega nada a `src/fpga/basys3.xdc`.

Conexiones dentro de `PERIFERICO_VGA`, instancia `u_fuente`:

- `codigo_i`, a `codigo`, que es `caracter` o `caracter2` según la mitad de la casilla y `centrado`.
- `fila_i`, a `glifo_fila[2:0]`.
- `bits_o`, a `glifo_bits`.

Igual que en los demás módulos, el diagrama por chips que pide el método no aplica a un diseño que se
sintetiza dentro de una sola FPGA, y esta lista de puertos es el reemplazo propuesto.

## Verificación

`tb_periferico_vga` revisa a mano que la `A` sea la de la sección g) y que el espacio no
dibuje nada. El resto de la tabla lo usa el modelo del testbench para revisar dónde y de qué color
sale cada glifo, cuadro completo por cuadro completo, con caracteres al azar en todas las casillas.
`tb_top` revisa los textos que escribe el programa leyendo el código de cada casilla.
