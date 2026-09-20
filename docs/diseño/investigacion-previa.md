# Investigación Previa

**EL3313 — Taller de Diseño Digital · II Semestre 2026**
**Proyecto 3: Batalla Naval sobre un microprocesador RISC-V con periférico VGA**

Profesores: Dr.-Ing. Jeferson González-Gómez, Ing. Rolen Coto Calderón

Integrantes: Carlos Castro Villegas, Jefferson Chinchilla Quesada, Mattio Coghi Quirós, Nicolás Mena Valerio

---

## Índice

1. [Arquitectura RISC-V y el subconjunto `rv32i`](#1-arquitectura-risc-v-y-el-subconjunto-rv32i)
2. [Organizaciones clásicas de *datapath* y unidad de control](#2-organizaciones-clásicas-de-datapath-y-unidad-de-control)
3. [Mapeo de periféricos en memoria (*memory-mapped I/O*)](#3-mapeo-de-periféricos-en-memoria-memory-mapped-io)
4. [Fundamentos de la generación de video VGA](#4-fundamentos-de-la-generación-de-video-vga)
5. [Gráficos por *tiles* frente a *framebuffer* completo](#5-gráficos-por-tiles-frente-a-framebuffer-completo)
6. [Técnicas de *debouncing* para pulsadores](#6-técnicas-de-debouncing-para-pulsadores)
7. [Reglas clásicas del juego Batalla Naval](#7-reglas-clásicas-del-juego-batalla-naval)
8. [Protocolo UART y reutilización del periférico del Proyecto 2](#8-protocolo-uart-y-reutilización-del-periférico-del-proyecto-2)
9. [Aplicación de PC con `pyserial`](#9-aplicación-de-pc-con-pyserial)
10. [Referencias](#referencias)

---

## 1. Arquitectura RISC-V y el subconjunto `rv32i`

### 1.1. Qué es RISC-V y por qué `rv32i`

RISC-V es una arquitectura de conjunto de instrucciones (ISA) abierta y libre de regalías, desarrollada originalmente en la Universidad de California en Berkeley y mantenida actualmente por RISC-V International [1]. Su especificación se divide en un documento *unprivileged* (instrucciones de usuario) y uno *privileged* (modos de ejecución, CSR, excepciones) [2]. La ISA está organizada de forma **modular**: existe un núcleo base obligatorio y una serie de extensiones opcionales identificadas por letras (`M` multiplicación/división, `A` atómicas, `F`/`D` punto flotante, `C` instrucciones comprimidas de 16 bits, etc.).

El núcleo base de enteros de 32 bits se denomina **RV32I**. Es justamente el mínimo que la especificación define como suficiente para ejecutar software completo, y es la base adecuada para este proyecto por tres razones:

- **No requiere multiplicador ni divisor en hardware.** La extensión `M` no forma parte del base, lo que evita instanciar bloques DSP costosos. La lógica del juego (índices de tablero, comparaciones, máscaras) se resuelve con sumas, restas, desplazamientos y operaciones lógicas.
- **Es cerrada y pequeña.** RV32I contiene alrededor de 40 instrucciones, y la lista solicitada en la Sección 4.4.1 del enunciado (`lw`, `sw`, desplazamientos, aritmético-lógicas, inmediatos, saltos condicionales, comparaciones y `jal`/`jalr`) es un subconjunto de ella, perfectamente implementable en un diseño de ciclo único.
- **Tiene herramientas maduras.** Existe ensamblador y *toolchain* GNU oficial ([`riscv-gnu-toolchain`](https://github.com/riscv-collab/riscv-gnu-toolchain)) [4] y un manual de ensamblador de referencia [3], de modo que el programa del juego puede escribirse, ensamblarse y volcarse a la ROM con herramientas estándar en lugar de un ensamblador ad hoc.

> **Decisión de diseño derivada.** El procesador implementará estrictamente el subconjunto `rv32i` listado en el enunciado, sin extensión `M` ni `C`. Toda multiplicación necesaria en el juego (por ejemplo `fila * 8` para indexar el tablero, o `fila * 20 + columna` para la memoria de video) se realizará por desplazamientos y sumas, lo que es exacto porque 8 y 32 son potencias de dos y 20 = 16 + 4.

### 1.2. Banco de registros

RV32I define **32 registros de propósito general de 32 bits** (`x0`–`x31`) más el contador de programa `pc` [2]. La característica clave es que **`x0` está cableado al valor cero**: escribir en él no tiene efecto y leerlo siempre devuelve `0x0000_0000`. Esto permite sintetizar muchas pseudo-instrucciones sin hardware adicional:

| Pseudo-instrucción | Expansión real | Uso en el proyecto |
|---|---|---|
| `nop` | `addi x0, x0, 0` | Relleno / espera |
| `mv rd, rs` | `addi rd, rs, 0` | Copia de registros |
| `li rd, imm` | `addi rd, x0, imm` (imm pequeño) | Constantes de color, códigos de trama UART |
| `not rd, rs` | `xori rd, rs, -1` | Máscaras de casillas |
| `beqz rs, lbl` | `beq rs, x0, lbl` | Comparaciones contra cero |
| `j lbl` | `jal x0, lbl` | Salto sin guardar retorno |
| `ret` | `jalr x0, x1, 0` | Retorno de subrutina |

La ABI estándar asigna nombres simbólicos a los registros [3], y conviene respetarla aunque el procesador sea propio, porque hace el ensamblador legible y compatible con el *toolchain*:

| Registro | Nombre ABI | Rol | Uso previsto en el juego |
|---|---|---|---|
| `x0` | `zero` | Constante cero | Comparaciones, inicialización |
| `x1` | `ra` | Dirección de retorno | `jal`/`jalr` en subrutinas |
| `x2` | `sp` | Puntero de pila | Pila en la RAM (`0x0000_2FFF` hacia abajo) |
| `x5`–`x7`, `x28`–`x31` | `t0`–`t6` | Temporales (*caller-saved*) | Cálculos de índices y direcciones |
| `x8`–`x9`, `x18`–`x27` | `s0`–`s11` | Guardados (*callee-saved*) | Estado de partida, turno, punteros a tablero |
| `x10`–`x17` | `a0`–`a7` | Argumentos y retorno | Paso de fila/columna/barco a subrutinas |

Para el hardware, el banco de registros se implementa como una memoria de 32×32 bits con **dos puertos de lectura asíncronos** (`rs1`, `rs2`) y **un puerto de escritura síncrono** (`rd`), con la escritura inhibida cuando `rd == 0`. Esta estructura es la que exige un *datapath* de ciclo único, donde ambos operandos deben estar disponibles combinacionalmente dentro del mismo ciclo [5][6].

### 1.3. Formatos de instrucción y codificación

Todas las instrucciones de RV32I son de **32 bits de ancho fijo** y están alineadas a 4 bytes. La especificación define seis formatos [2]. La propiedad de diseño más importante es que **`rs1`, `rs2` y `rd` ocupan siempre las mismas posiciones de bits en todos los formatos**, de modo que la decodificación de los índices de registro no depende del tipo de instrucción y puede cablearse directamente desde `instr` hacia el banco de registros:

```
 31        25 24     20 19     15 14  12 11      7 6        0
+------------+---------+---------+------+---------+----------+
|  funct7    |   rs2   |   rs1   |funct3|   rd    |  opcode  |  R
+------------+---------+---------+------+---------+----------+
|      imm[11:0]       |   rs1   |funct3|   rd    |  opcode  |  I
+------------+---------+---------+------+---------+----------+
| imm[11:5]  |   rs2   |   rs1   |funct3|imm[4:0] |  opcode  |  S
+------------+---------+---------+------+---------+----------+
|imm[12|10:5]|   rs2   |   rs1   |funct3|imm[4:1|11]| opcode |  B
+------------+---------+---------+------+---------+----------+
|            imm[31:12]                 |   rd    |  opcode  |  U
+---------------------------------------+---------+----------+
|      imm[20|10:1|11|19:12]            |   rd    |  opcode  |  J
+---------------------------------------+---------+----------+
```

- **Tipo R** — `add`, `sub`, `and`, `or`, `xor`, `sll`, `srl`, `sra`, `slt`, `sltu`. Registro-registro; `funct7` distingue `add`/`sub` y `srl`/`sra` (bit 30).
- **Tipo I** — `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `lw`, `jalr` y los desplazamientos por inmediato (`slli`, `srli`, `srai`, donde `imm[11:5]` funciona como `funct7` y `imm[4:0]` es el `shamt`).
- **Tipo S** — `sw`. El inmediato aparece partido en dos campos precisamente para no mover `rs1`/`rs2` de lugar.
- **Tipo B** — `beq`, `bne`, `blt`, `bge`. El inmediato codifica un desplazamiento **en múltiplos de 2 bytes** con los bits barajados, lo que parece arbitrario pero mantiene cada bit del inmediato en una posición fija respecto al formato S, minimizando los multiplexores del extensor de signo [2].
- **Tipo U** — `lui`, `auipc` (necesarias para cargar las direcciones de periféricos como `0x0001_1000`, que no caben en 12 bits).
- **Tipo J** — `jal`.

Todos los inmediatos se **extienden con signo** al ancho de 32 bits, con la única excepción de los desplazamientos (`shamt`) y de `lui`/`auipc`, que colocan el inmediato en los bits altos.

> **Consecuencia práctica.** El módulo extensor de inmediato (*immediate generator*) es puramente combinacional y se selecciona con un campo de 3 bits derivado del `opcode`. El decodificador principal necesita sólo `opcode[6:0]`, `funct3[14:12]` y `funct7[30]` para determinar por completo la operación, como se muestra en la sección siguiente.

> **Nota sobre `lui` y `auipc`.** El enunciado no las lista explícitamente entre las instrucciones mínimas, pero sin ellas no es posible construir constantes de 32 bits (por ejemplo `VGA_BASE = 0x0001_1000`) en una sola secuencia corta. Se implementarán ambas por ser parte de RV32I y por ser indispensables para el direccionamiento de periféricos.

---

## 2. Organizaciones clásicas de *datapath* y unidad de control

### 2.1. Ciclo único, multiciclo y segmentado

La literatura clásica de arquitectura de computadores describe tres organizaciones canónicas para un mismo ISA [5][6]:

| Organización | CPI | *T*<sub>clk</sub> | Complejidad de control | Recursos |
|---|---|---|---|---|
| **Ciclo único** | 1 | Largo (ruta crítica = instrucción más lenta, típicamente `lw`) | Mínima: control puramente combinacional | Memorias separadas de instrucción y dato (Harvard), un sumador extra para `pc+4` |
| **Multiciclo** | 3–5 | Corto | Media: FSM de estados por instrucción, registros intermedios | Una sola memoria, ALU reutilizada |
| **Segmentado (*pipeline*)** | ≈1 (ideal) | Corto | Alta: detección de riesgos, *forwarding*, *stalls*, *flush* de saltos | Registros de etapa, lógica de riesgos |

Para este proyecto se selecciona el **ciclo único**, y la justificación es concreta y verificable:

1. **El enunciado impone una organización Harvard.** La Figura 1 y la Figura 2 del enunciado definen buses independientes `ProgAddress_o`/`ProgIn_i` hacia la ROM y `DataAddress_o`/`DataOut_o`/`DataIn_i`/`we_o` hacia la RAM y los periféricos. Esa separación es exactamente el requisito estructural del ciclo único: permite leer una instrucción y acceder a un dato en el mismo ciclo sin conflicto de recurso [6].
2. **El presupuesto de desempeño es holgado.** El sistema corre a 100 MHz y las tareas del juego (mover un cursor, validar un disparo, escribir 300 palabras de video) son de latencia irrelevante frente a la percepción humana y frente al refresco VGA de 60 Hz. Un CPI de 1 a una frecuencia incluso reducida sobra ampliamente.
3. **Reduce el riesgo de verificación.** Sin riesgos de datos ni de control, el comportamiento esperado de cada instrucción se comprueba con un *testbench* autoverificable instrucción por instrucción, lo que se alinea con la rúbrica de simulación autoverificable del enunciado (peso 15 %).
4. **La ruta crítica es tolerable.** La ruta más larga es la de `lw`: `PC → ROM → decodificación → banco de registros → ALU → RAM/periférico → mux de escritura → banco de registros`. Si esa ruta no cerrara *timing* a 100 MHz, la mitigación no es rediseñar a *pipeline*, sino **derivar del PLL un reloj de CPU más lento** (por ejemplo 50 MHz), manteniendo intacta la arquitectura. Esto es posible porque el PLL ya se requiere para generar el reloj de píxel.

### 2.2. Estructura del *datapath* de ciclo único

El *datapath* de ciclo único para RV32I se organiza en torno a cinco bloques y un conjunto de multiplexores controlados por la unidad de control [6]:

```
        +4 ──┐
             ├─> [mux PCSrc] ──> PC ──> ROM ──> instr
  PCTarget ──┘                         │
                                       ├─> ImmGen ──────────┐
                                       ├─> RegFile(rs1,rs2) │
                                       │        │    │      │
                                       │        │    └─> [mux ALUSrc] ──┐
                                       │        └────────────────────> ALU ──> DataAddress_o
                                       │                                  │
                                       │                     DataOut_o <──┘ (rs2)
                                       └─> Control Unit ──> {RegWrite, MemWrite(we_o),
                                                             ALUControl, ALUSrc, ImmSrc,
                                                             ResultSrc, Branch, Jump}

        Resultado escrito en rd = [mux ResultSrc]{ALUResult, DataIn_i, PC+4, ImmExt}
```

Elementos y su justificación:

- **PC y su lógica de siguiente dirección.** Registro de 32 bits con reinicio al **vector de reset `0x0000_0000`**, tal como especifica la Sección 4.4.2 del enunciado. El siguiente PC se elige entre `PC+4` y `PC + immExt` (saltos relativos) o `rs1 + immExt` con el bit 0 forzado a cero (`jalr`).
- **ALU.** Debe soportar `add`, `sub`, `and`, `or`, `xor`, `sll`, `srl`, `sra`, `slt` (con signo) y `sltu` (sin signo). Su bandera de cero y el signo del resultado alimentan la decisión de salto. Un detalle de corrección frecuentemente omitido: `blt`/`bge` comparan **con signo** y por lo tanto la condición correcta es `(N ⊕ V)`, no simplemente el bit de signo, cuando se implementa vía resta.
- **Extensor de inmediato.** Combinacional, seleccionado por `ImmSrc`, con los seis formatos descritos en §1.3.
- **Interfaz de memoria de datos.** `DataAddress_o` proviene de la ALU, `DataOut_o` del registro `rs2` y `we_o` de la señal `MemWrite`. Es el mismo bus que alcanza a todos los periféricos (§3).

### 2.3. Unidad de control

La unidad de control de un diseño de ciclo único es **puramente combinacional** y se descompone clásicamente en dos niveles [6]:

1. **Decodificador principal**, función de `opcode[6:0]`, que produce `RegWrite`, `ImmSrc`, `ALUSrc`, `MemWrite`, `ResultSrc`, `Branch`, `Jump` y un `ALUOp` de 2 bits.
2. **Decodificador de ALU**, función de `ALUOp`, `funct3` y el bit `funct7[5]` (bit 30 de la instrucción), que produce `ALUControl`.

Esta descomposición en dos niveles reduce el tamaño de la tabla de verdad y aísla la extensión del repertorio: agregar una instrucción aritmética nueva sólo toca el segundo decodificador.

> **Riesgo a controlar: *latches* no intencionados.** El enunciado exige explícitamente que no se generen *latches*. En SystemVerilog, la causa habitual es un `always_comb` con un `case` incompleto o un `if` sin `else` que deja alguna señal de control sin asignar en algún camino. Las dos medidas preventivas que se adoptarán son (a) **asignar valores por defecto a todas las señales de control al inicio de cada bloque `always_comb`**, y (b) usar `always_comb`/`always_ff` en lugar de `always`, de modo que la herramienta reporte el error en lugar de inferir memoria silenciosamente. La ausencia de *latches* se confirmará en el reporte de síntesis, en el *netlist* y con el *linter*, como pide el enunciado [8].

> **Distinción importante.** La unidad de control del procesador **no** es la máquina de estados del juego. En los Proyectos 1 y 2 el control de la aplicación vivía en FSM de SystemVerilog; aquí la FSM del juego (colocación → batalla → fin) es **software**, una variable de estado en RAM manipulada por el programa en ensamblador (Sección 4.1 del enunciado). La unidad de control en hardware sólo sabe de instrucciones, no de barcos.

---

## 3. Mapeo de periféricos en memoria (*memory-mapped I/O*)

### 3.1. Concepto y alternativas

Existen dos formas clásicas de que un procesador converse con periféricos [5]:

- **E/S por instrucciones dedicadas (*port-mapped I/O*)**, como `IN`/`OUT` en x86: los periféricos viven en un espacio de direcciones separado y requieren instrucciones y señales de bus propias.
- **E/S mapeada en memoria (*memory-mapped I/O*)**: los registros de los periféricos ocupan direcciones dentro del mismo espacio de memoria y se acceden con las mismas instrucciones de carga y almacenamiento.

RISC-V, como prácticamente todas las arquitecturas RISC modernas, **no define instrucciones de E/S**: la única forma de hablar con un periférico es `lw`/`sw` sobre una dirección mapeada [2]. Esto es una ventaja de diseño: no hay que añadir instrucciones, señales de bus ni lógica de decodificación adicional al *datapath*; el mismo bus `DataAddress_o`/`DataOut_o`/`DataIn_i`/`we_o` de la Figura 2 del enunciado sirve para RAM y para periféricos.

### 3.2. Decodificación de direcciones para este sistema

El mapa de memoria especificado en la Sección 4.4.2 del enunciado es:

| Región | Rango | Tamaño | Contenido |
|---|---|---|---|
| ROM (programa) | `0x0000_0000` – `0x0000_1FFF` | 8 KiB = 2048 instrucciones | Programa en ensamblador |
| RAM (datos) | `0x0000_2000` – `0x0000_2FFF` | 4 KiB = 1024 palabras | Tableros, turno, contadores, pila |
| Periféricos | `0x0001_0000` – `0x0001_FFFF` | 64 KiB | Registros + memoria de video |

Dado que el bus es de palabra (todos los accesos son `lw`/`sw` alineados a 4 bytes), la decodificación puede hacerse con muy pocos bits:

- **`DataAddress_o[16]`** distingue espacio de datos (`0`) de espacio de periféricos (`1`), porque `0x0001_0000` tiene el bit 16 en 1 y toda la RAM está por debajo de `0x0001_0000`.
- Dentro del espacio de periféricos, **`DataAddress_o[15:12]`** distingue la memoria de video (`0x1xxx` → nibble `1`) del banco de registros de periféricos (`0x0xxx` → nibble `0`).
- Dentro del banco de registros, **`DataAddress_o[11:4]`** selecciona el periférico (UART `0x04`, entradas `0x12`, displays `0x13`, LED `0x13`, *buzzer* `0x14`) y **`DataAddress_o[3:2]`** forma el `addr_i[1:0]` que el enunciado define en la interfaz estándar de la Sección 4.5.5.

Esta correspondencia entre `DataAddress_o[3:2]` y `addr_i[1:0]` es el punto que más suele confundirse: la interfaz de periférico tiene direcciones **de registro** (00, 01, 10, 11), mientras que el CPU emite direcciones **de byte** que avanzan de 4 en 4 (offsets `0x00`, `0x04`, `0x08`, `0x0C`). Los dos bits inferiores de la dirección de byte son siempre cero en accesos alineados y por eso se descartan.

Tabla resultante, consistente con la Sección 4.4.3 del enunciado:

| Periférico | Dirección | `addr_i[1:0]` | Registro | Acceso |
|---|---|---|---|---|
| UART | `0x0001_0040` | `00` | Control / Estado | L/E |
| UART | `0x0001_0044` | `01` | Datos TX | E |
| UART | `0x0001_0048` | `10` | Datos RX | L |
| Entradas J1 | `0x0001_0120` | `00` | Estado de botones (ya *debounced*) | L |
| Displays 7 seg | `0x0001_0130` | `00` | Datos (4 dígitos BCD) | E |
| LED de estado | `0x0001_0138` | `00` | Datos | E |
| *Buzzer* | `0x0001_0140` | `00` | Control (tono/patrón) | E |
| Memoria de video | `0x0001_1000` – `0x0001_17FF` | — | 512 palabras (300 usadas) | L/E |

### 3.3. Buenas prácticas de diseño de registros de 32 bits

De las guías de diseño de bloques de registros de proyectos abiertos como OpenTitan [9] y de especificaciones de bus como Wishbone [10] se extraen las siguientes reglas, que se adoptarán en el proyecto:

1. **Un registro, un propósito.** No mezclar campos de control (escritura) y de estado (solo lectura) con semánticas contradictorias en la misma dirección sin documentarlo. Cuando se comparte dirección —como en el registro Control/Estado de la UART—, debe documentarse explícitamente qué significa cada bit al leer y al escribir, porque no tienen por qué coincidir.
2. **Documentar el ancho real y dejar el resto reservado en cero.** Un registro de estado de botones usa 6 bits de 32; los 26 restantes deben leerse como cero y no deben usarse, para permitir extensiones futuras sin romper el software.
3. **Lecturas sin efectos colaterales cuando sea posible.** Un registro cuya lectura borra una bandera (*read-to-clear*) es válido y a veces necesario (típico para `RX_VALID` en una UART), pero debe documentarse, porque hace que leer dos veces produzca resultados distintos y complica la depuración.
4. **Sin bloqueo del CPU.** Ningún periférico debe insertar estados de espera: el enunciado exige que la actualización de una casilla VGA ocurra en un único ciclo de escritura sin bloquear el programa. El *handshake* con periféricos lentos (UART) se hace por **sondeo (*polling*)** de bits de estado (`TX_READY`, `RX_VALID`) desde el software, no por espera en hardware.
5. **Sincronización de entradas asíncronas.** Todo lo que llega de fuera del dominio de reloj (botones, `RX` de la UART) se registra con al menos **dos *flip-flops* en cascada** antes de usarse, para reducir la probabilidad de propagación de metaestabilidad.
6. **Reinicio bien definido.** Todo registro de periférico debe tener un valor conocido tras el reset, y el reinicio del sistema (síncrono o asíncrono) debe usarse de forma consistente en todo el diseño, como pide la Sección 4.5.5 del enunciado.

> **Aplicación a la memoria de video.** El enunciado señala que el VGA es la excepción a la interfaz estándar: se comporta como memoria, no como banco de registros, y por eso requiere un `addr_i` más ancho. Para indexar 20 × 15 = 300 casillas se necesitan **9 bits** de dirección de palabra (2⁹ = 512 ≥ 300). El rango reservado `0x0001_1000`–`0x0001_17FF` son 2048 bytes = 512 palabras, exactamente coherente con esos 9 bits.

---

## 4. Fundamentos de la generación de video VGA

### 4.1. La señal VGA y su origen

La interfaz VGA es una señal de video **analógica y progresiva** heredada de los monitores de tubo de rayos catódicos. El haz recorre la pantalla línea por línea de izquierda a derecha y de arriba a abajo; al terminar una línea debe regresar al inicio de la siguiente (*retrazado horizontal*) y al terminar la pantalla debe volver a la esquina superior izquierda (*retrazado vertical*). Durante esos retrazados el haz debe apagarse, y el monitor necesita un pulso que le indique cuándo ocurren: son las señales **HS** (*horizontal sync*) y **VS** (*vertical sync*). Los tres canales de color (R, G, B) son analógicos, de 0 a 0,7 V sobre 75 Ω [12].

Aunque los monitores LCD modernos no tienen haz, **conservan exactamente la misma temporización** por compatibilidad, incluidos los intervalos de borrado que ya no corresponden a ningún fenómeno físico. Las temporizaciones estándar están normalizadas por VESA en el documento *Display Monitor Timing* (DMT) [11].

### 4.2. Temporización de 640 × 480 a 60 Hz

El modo 640 × 480 @ 60 Hz es el modo VGA base y el especificado por el enunciado. Sus parámetros canónicos son [12][13]:

**Temporización horizontal (en píxeles):**

| Etapa | Píxeles | Acumulado |
|---|---|---|
| Video activo (*visible area*) | 640 | 640 |
| Pórtico frontal (*front porch*) | 16 | 656 |
| Pulso de sincronismo (*sync pulse*) | 96 | 752 |
| Pórtico trasero (*back porch*) | 48 | 800 |
| **Total por línea** | **800** | |

**Temporización vertical (en líneas):**

| Etapa | Líneas | Acumulado |
|---|---|---|
| Video activo | 480 | 480 |
| Pórtico frontal | 10 | 490 |
| Pulso de sincronismo | 2 | 492 |
| Pórtico trasero | 33 | 525 |
| **Total por cuadro** | **525** | |

**Polaridad:** ambos pulsos son **activos en bajo** (negativos) en este modo.

**Reloj de píxel:** el estándar especifica 25,175 MHz. De aquí se verifica la frecuencia de refresco:

```
f_línea  = 25,175 MHz / 800            = 31,469 kHz
f_cuadro = 31,469 kHz / 525            = 59,94 Hz  ≈ 60 Hz
```

El enunciado permite usar **25 MHz** generados por el PLL a partir de los 100 MHz de entrada. Esto da:

```
f_cuadro = 25 MHz / (800 × 525) = 59,52 Hz
```

es decir, un error de **−0,7 %** respecto a 59,94 Hz. Esta desviación está dentro de la tolerancia de prácticamente todos los monitores VGA, y tiene además la ventaja decisiva de que **25 MHz se obtiene como división entera por 4 de los 100 MHz** del oscilador de la tarjeta, lo que la hace exacta y sin *jitter* de fraccionamiento.

> **Decisión de diseño.** Se generará el reloj de píxel de 25 MHz mediante un MMCM/PLL instanciado con el *Clocking Wizard* de Vivado [14], no con un divisor por contador. La razón es que un reloj producido por lógica de usuario no entra a la red global de reloj de forma limpia y complica el análisis de *timing*; el MMCM entrega un reloj con *buffer* global (`BUFG`) que las herramientas analizan correctamente. La señal `locked` del PLL se usará además como parte de la condición de reinicio del sistema.

### 4.3. Estructura del generador de sincronismos

El generador se implementa con dos contadores en el dominio del reloj de píxel:

```systemverilog
// Estructura conceptual (no es el RTL final)
if (h_count == H_TOTAL-1) begin
    h_count <= 0;
    v_count <= (v_count == V_TOTAL-1) ? 0 : v_count + 1;
end else begin
    h_count <= h_count + 1;
end

hs_o    <= ~((h_count >= H_SYNC_START) && (h_count < H_SYNC_END));  // activo bajo
vs_o    <= ~((v_count >= V_SYNC_START) && (v_count < V_SYNC_END));  // activo bajo
video_on <= (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
```

Dos precauciones bien documentadas en la práctica:

1. **Las salidas deben registrarse.** Si `hs_o`, `vs_o` y los colores salen por lógica combinacional directa desde los contadores, aparecen *glitches* y desalineaciones de un píxel entre el color y el sincronismo. Registrarlos introduce un retardo uniforme de un ciclo que no afecta la imagen.
2. **El color debe forzarse a negro fuera del área activa.** Si se emite color durante los pórticos o los pulsos de sincronismo, el monitor puede perder el enganche o mostrar la imagen desplazada. La señal `video_on` debe enmascarar los tres canales.

### 4.4. Salida de color en la tarjeta

La Basys3 implementa la salida VGA con una **escalera de resistencias (R-2R) de 4 bits por canal**, lo que da 4096 colores disponibles [13]. El proyecto requiere como mínimo 4 colores distinguibles para los estados de casilla (agua, barco propio, impacto, fallo), más algunos para el HUD, lo cual cabe holgadamente en los 3 bits de `color` que la Sección 4.5.1 del enunciado reserva en cada palabra de la memoria de video (8 combinaciones). La traducción de esos 3 bits a los 12 bits RGB se hace con una tabla de búsqueda combinacional (paleta) dentro del periférico VGA.

---

## 5. Gráficos por *tiles* frente a *framebuffer* completo

### 5.1. El problema de memoria

Un *framebuffer* completo almacena el color de **cada píxel** de forma individual. Para 640 × 480 con 12 bits de color:

```
640 × 480 × 12 bits = 3 686 400 bits ≈ 450 KiB
```

La Basys3 (Artix-7 XC7A35T) dispone de **1800 kbit = 225 KiB** de Block RAM en total [13][15]. Es decir, **un framebuffer de color completo sencillamente no cabe**, y aun reduciendo a 1 bit por píxel (307 200 bits ≈ 37,5 KiB) consumiría cerca del 17 % de toda la BRAM del dispositivo para una imagen monocromática.

Hay además un segundo problema, independiente del tamaño: **el ancho de banda de escritura del CPU**. Pintar una casilla de 32 × 32 píxeles en un *framebuffer* requiere 1024 escrituras `sw`. Borrar la pantalla completa requeriría 307 200. A un CPI de 1 y 100 MHz eso son 3 ms sólo para borrar, y el programa del juego quedaría dominado por operaciones de dibujo en lugar de lógica de juego.

### 5.2. La alternativa: mapa de bloques (*tiles*)

El enfoque por *tiles* —el mismo que usaban las consolas y computadoras de 8 y 16 bits, y el modo texto de las tarjetas VGA— divide la pantalla en una cuadrícula de bloques y almacena **un descriptor por bloque** en lugar de un color por píxel [16]. La lógica de video, mientras barre la pantalla, usa las partes altas de los contadores `h_count`/`v_count` para saber en qué bloque está, lee su descriptor y genera el color correspondiente.

Con la geometría propuesta en el enunciado (bloques de 32 × 32 píxeles):

```
Columnas = 640 / 32 = 20 bloques
Filas    = 480 / 32 = 15 bloques
Total    = 300 bloques → 300 palabras de 32 bits = 1200 bytes ≈ 1,2 KiB
```

La reducción es de **450 KiB a 1,2 KiB**, un factor de aproximadamente 375, y el costo de pintar una casilla completa pasa de 1024 instrucciones `sw` a **una sola**.

### 5.3. Indexación y justificación de la geometría

El enunciado define el cálculo de dirección como:

```
dirección = VGA_BASE + (fila × NUM_COLUMNAS + columna) × 4
          = 0x0001_1000 + (fila × 20 + columna) × 4
```

En el hardware VGA, la operación inversa es puramente de cableado y **no requiere ningún divisor**:

```
columna_bloque = h_count[9:5]     // h_count / 32
fila_bloque    = v_count[8:5]     // v_count / 32
píxel_x_dentro = h_count[4:0]     // h_count % 32
píxel_y_dentro = v_count[4:0]     // v_count % 32
```

Que 32 sea potencia de dos es lo que hace esto gratis en hardware, y es la razón principal para elegir ese tamaño de bloque.

**Verificación de que la geometría alcanza para el contenido requerido.** La cuadrícula de 20 × 15 debe alojar simultáneamente:

- el tablero propio del Jugador 1: 8 × 8 = 64 bloques;
- el tablero conocido del rival: 8 × 8 = 64 bloques;
- separación entre ambos: al menos 1 columna;
- HUD (turno activo, partidas ganadas, mensajes): las filas restantes.

Con 8 + 1 + 8 = 17 columnas de las 20 disponibles y 8 filas de las 15, queda espacio para **3 columnas y 7 filas** de HUD, suficiente para los indicadores requeridos. Esta verificación responde al requisito explícito del enunciado de "documentar y justificar la resolución exacta de la cuadrícula elegida y su relación con el tamaño de los tableros y la información de HUD requerida".

### 5.4. Doble puerto y cruce de dominios de reloj

El enunciado especifica que el periférico VGA se implemente como **memoria de doble puerto**:

- **Puerto A (escritura):** síncrono al reloj del sistema (100 MHz), accedido por el CPU con `write_enable_i`/`addr_i`/`wdata_i`.
- **Puerto B (lectura):** solo lectura, síncrono al reloj de píxel (25 MHz), leído continuamente por la lógica de barrido.

Esto es una **BRAM de doble puerto verdadero (*true dual-port*) con relojes independientes**, una primitiva nativa del Artix-7 que Vivado infiere a partir de un patrón de codificación estándar: un arreglo `logic [31:0] mem [0:511]` accedido desde dos bloques `always_ff` con relojes distintos [8][15].

**Tratamiento del cruce de dominios de reloj (CDC).** Es el punto que el enunciado pide documentar explícitamente. El análisis es el siguiente:

- La BRAM es un recurso de hardware diseñado para operación con relojes asíncronos; no hay riesgo de metaestabilidad en el arreglo de memoria en sí.
- El único escenario problemático es una **colisión**: que el CPU escriba en la misma dirección que el puerto de video está leyendo en ese instante. El resultado de la lectura en ese caso es indeterminado (podría devolver el valor viejo, el nuevo, o un valor corrupto en ese ciclo) [15].
- **Impacto real: nulo en la práctica.** Una lectura corrupta afecta un único bloque durante un único cuadro de 16,7 ms, produciendo a lo sumo un parpadeo imperceptible. No hay corrupción del estado del juego, porque **el estado de verdad del juego vive en la RAM de datos, no en la memoria de video**. La memoria de video es únicamente una proyección de ese estado.
- **No se requiere sincronizador ni FIFO** para los datos, porque no se transfieren señales de control de un dominio a otro: cada dominio tiene su propio puerto independiente.
- Los relojes de 100 MHz y 25 MHz provienen del **mismo MMCM**, por lo que están relacionados en fase. Se declararán las restricciones de *timing* correspondientes y, si la herramienta reporta rutas cruzadas espurias, se aplicará `set_false_path` únicamente sobre rutas verificadas como seguras.
- Se aplica además la práctica de **no cruzar señales de control de múltiples bits** sin un protocolo adecuado; para señales de un solo bit que deban cruzar (si las hubiera, por ejemplo un indicador de fin de cuadro hacia el CPU) se usará un sincronizador de dos *flip-flops* [17].

> **Sobre el borrado de pantalla.** El enunciado indica que no se requiere un bit de `clear` en hardware: limpiar la pantalla es un lazo de software que escribe el color de fondo en las 300 posiciones. A 1 instrucción `sw` por bloque más el control del lazo (≈ 4 instrucciones por iteración), son unas 1200 instrucciones, es decir **12 µs a 100 MHz** — completamente imperceptible. Este es un ejemplo directo del principio de "hardware mínimo, control en software" que estructura todo el proyecto.

---

## 6. Técnicas de *debouncing* para pulsadores

### 6.1. El fenómeno del rebote

Un pulsador mecánico no conmuta de forma limpia: al cerrarse, los contactos metálicos rebotan físicamente varias veces antes de asentarse, produciendo una ráfaga de transiciones. La duración típica está entre **1 y 10 ms**, aunque puede llegar a decenas de milisegundos en interruptores desgastados o de baja calidad; Jack Ganssle documentó mediciones sistemáticas sobre decenas de interruptores comerciales y encontró rebotes de hasta 157 ms en casos extremos [18].

A 100 MHz, el periodo de reloj es de 10 ns. Un rebote de 5 ms abarca **500 000 ciclos de reloj**. Sin filtrado, cada pulsación del botón de navegación movería el cursor una cantidad impredecible de casillas, y cada pulsación de `BTN_OK` dispararía múltiples veces. En este proyecto la consecuencia sería directamente **una violación de las reglas del juego** (varios disparos con un solo turno) y una pérdida visible de puntos en la rúbrica de presentación funcional, que evalúa explícitamente que los botones "funcionan libres de rebotes".

### 6.2. Técnicas y elección

| Técnica | Principio | Evaluación para este proyecto |
|---|---|---|
| **RC + Schmitt trigger** | Filtro pasabajos externo más histéresis | Requiere componentes externos; no aplicable, los botones están cableados en la tarjeta |
| **Contador de estabilidad** | Se acepta el nuevo nivel sólo tras verlo estable N ciclos consecutivos | **Elegida.** Simple, sintetizable, un solo contador por botón, comportamiento determinista y fácil de verificar en simulación |
| **Muestreo lento** | Muestrear a ~100 Hz; los rebotes caen entre muestras | Sencilla pero añade latencia variable y puede perder pulsaciones muy cortas |
| **Máquina de estados con temporizador** | FSM que espera un tiempo de guarda tras cada flanco | Equivalente al contador, con más lógica de control |

**Implementación adoptada:**

```
btn_raw ──> [FF] ──> [FF] ──> btn_sync   (sincronizador de 2 etapas, metaestabilidad)
                                │
                                ├──> comparador contra btn_stable
                                │      ├─ distintos → contador ← 0, cuenta
                                │      └─ iguales   → contador++
                                │
                        contador == N → btn_stable <= btn_sync
                                │
btn_stable ──> [FF] ──> detector de flanco ──> btn_pulse (1 ciclo)
```

**Dimensionamiento del contador.** Con un tiempo de guarda de **10 ms** a 100 MHz:

```
N = 10 ms × 100 MHz = 1 000 000 ciclos → contador de 20 bits (2²⁰ = 1 048 576)
```

Diez milisegundos es el valor recomendado como punto de partida en la práctica industrial [18]: es mayor que el rebote típico y, al mismo tiempo, muy inferior al umbral de percepción humana de latencia (~100 ms), por lo que la interfaz se siente instantánea.

**Dos elementos que suelen omitirse y que sí se incluirán:**

1. **El sincronizador de dos *flip-flops* es obligatorio y es distinto del *debouncer*.** Resuelve un problema diferente: la señal del botón es asíncrona respecto al reloj de 100 MHz y puede violar los tiempos de *setup/hold* de un *flip-flop*, provocando metaestabilidad. El *debouncer* filtra en el dominio del tiempo (milisegundos); el sincronizador protege en el dominio de la incertidumbre eléctrica (nanosegundos). Ambos son necesarios [17].
2. **Detección de flanco, no de nivel.** El registro de estado del periférico de entradas debe exponer, según el enunciado, "el estado ya filtrado (sin rebotes)". Para que el software pueda distinguir una pulsación nueva de un botón mantenido presionado, el periférico generará un **pulso de un ciclo por flanco de subida**, registrado como una bandera *sticky* que el software lee y limpia. De lo contrario, el lazo de sondeo del programa leería el botón como presionado durante miles de iteraciones consecutivas y el cursor se movería descontroladamente — un rebote de software equivalente al de hardware.

### 6.3. Mapeo de bits propuesto

Registro de ESTADO del periférico de entradas, en `0x0001_0120` (offset `0x00`, `addr_i = 00`):

| Bit | Señal | Función en el juego |
|---|---|---|
| 0 | `BTN_UP` | Mover cursor arriba |
| 1 | `BTN_DOWN` | Mover cursor abajo |
| 2 | `BTN_LEFT` | Mover cursor izquierda |
| 3 | `BTN_RIGHT` | Mover cursor derecha |
| 4 | `BTN_SEL` | Rotar orientación del barco (horizontal/vertical) |
| 5 | `BTN_OK` | Confirmar colocación / confirmar disparo |
| 6 | `BTN_RST` | Reiniciar partida conservando contadores |
| 31:7 | Reservado | Leen 0 |

La Basys3 dispone de exactamente cinco pulsadores en cruz más el central, lo que encaja con este mapeo [13].

---

## 7. Reglas clásicas del juego Batalla Naval

### 7.1. Origen y reglas canónicas

Batalla Naval (*Battleship*) es un juego de adivinanza para dos jugadores, originado como juego de lápiz y papel a principios del siglo XX y comercializado por Milton Bradley (hoy Hasbro) como juego de tablero en 1967 [19][20]. Las reglas canónicas son:

1. Cada jugador tiene dos cuadrículas: la **propia** (donde coloca su flota y registra los disparos recibidos) y la **de seguimiento** (donde registra sus propios disparos contra el rival).
2. Cada jugador coloca su flota en secreto. Los barcos se ubican en **orientación horizontal o vertical** (nunca diagonal), sin salirse de la cuadrícula y **sin traslaparse** entre sí.
3. Los jugadores se alternan turnos anunciando una coordenada. El rival responde **impacto** (*hit*) si hay parte de un barco en esa casilla, o **fallo** (*miss*) en caso contrario.
4. Un barco se considera **hundido** cuando todas sus casillas han sido impactadas, y esto se anuncia.
5. **Gana el jugador que hunde toda la flota del rival primero.**

La regla invariante y no negociable de todo el juego es la **información asimétrica**: ningún jugador puede conocer la disposición de la flota del otro salvo por deducción a partir de los resultados de sus propios disparos.

### 7.2. Especialización de las reglas para este proyecto

El enunciado especifica una variante reducida respecto al juego comercial (que usa cuadrícula 10 × 10 y cinco barcos):

| Parámetro | Juego comercial | **Este proyecto** |
|---|---|---|
| Cuadrícula | 10 × 10 | **8 × 8 = 64 casillas** |
| Flota | 5 barcos (5,4,3,3,2) | **3 barcos (4, 3, 2 casillas)** |
| Casillas ocupadas | 17 de 100 (17 %) | **9 de 64 (14 %)** |
| Estados de casilla | — | **agua, barco propio, impacto, fallo** |
| Disparo repetido | — | **Se ignora, no consume turno** |

Reglas específicas del enunciado que condicionan el diseño del software:

- **Colocación concurrente.** Ambos jugadores colocan su flota de forma simultánea e independiente; el avance de uno no debe bloquear al otro. Esto implica que el programa mantenga **dos banderas separadas** de "colocación completa" y que el lazo principal atienda alternadamente las entradas locales y las tramas UART. Es un requisito de estructura, no de reglas: el programa no puede quedarse esperando a un jugador.
- **Validación de colocación.** Debe rechazarse toda colocación que se traslape con un barco ya ubicado o que se salga del tablero, señalizándolo con el *buzzer* (Jugador 1) o con una respuesta de rechazo por UART (Jugador 2). Para un barco de longitud *L* colocado en (*f*, *c*) con orientación horizontal, la validación es: `c + L ≤ 8` y ninguna de las casillas `(f, c)…(f, c+L−1)` ocupada. Análogo para vertical con la fila.
- **Disparo repetido se ignora y no consume turno.** Esta es una regla explícita del enunciado que difiere de algunas variantes del juego y debe implementarse con cuidado: el programa comprueba el estado de la casilla *antes* de evaluar el impacto, y si ya fue disparada, regresa al inicio del turno del mismo jugador sin alternar.
- **Detección de barco hundido.** Requiere llevar, por cada barco, un contador de impactos recibidos o la lista de sus casillas. La estructura de datos elegida debe permitir, dado un impacto en la casilla (*f*, *c*), determinar a qué barco pertenece y si ese barco quedó completo.
- **Condición de victoria.** Se gana al hundir **los tres barcos** del rival, es decir, tras 4 + 3 + 2 = **9 impactos** sobre casillas distintas.

### 7.3. Organización de datos propuesta en RAM

El enunciado exige documentar la organización de datos en RAM. La propuesta es un arreglo de 64 bytes por jugador (o 64 palabras, según convenga al acceso `lw`/`sw`), más metadatos:

| Estructura | Tamaño | Contenido |
|---|---|---|
| `tablero_j1[64]` | 64 palabras | Estado por casilla: `0`=agua, `1`=barco, `2`=impacto, `3`=fallo, con el identificador de barco en bits altos |
| `tablero_j2[64]` | 64 palabras | Igual, para el Jugador 2 |
| `impactos_barco_j1[3]` | 3 palabras | Contador de impactos por barco (comparado contra 4, 3, 2) |
| `impactos_barco_j2[3]` | 3 palabras | Igual |
| `estado_juego` | 1 palabra | 0 = colocación, 1 = batalla, 2 = fin |
| `turno_activo` | 1 palabra | 0 = Jugador 1, 1 = Jugador 2 |
| `colocacion_lista_j1/j2` | 2 palabras | Banderas de flota completa |
| `ganadas_j1`, `ganadas_j2` | 2 palabras | Contadores acumulados 00–99 (se conservan tras `BTN_RST`) |
| `disparos_totales` | 1 palabra | Para el resumen final por UART |
| Pila | resto | Crece hacia abajo desde `0x0000_2FFC` |

Total aproximado: 64 + 64 + 3 + 3 + 8 ≈ **142 palabras de las 1024 disponibles** (14 % de la RAM), dejando amplio margen para la pila y variables temporales.

El indexado de una casilla es `índice = fila × 8 + columna`, que en ensamblador se calcula con `slli t0, fila, 3` seguido de `add t0, t0, columna` y `slli t0, t0, 2` para pasar a *offset* de byte — sin necesidad de multiplicador.

> **Requisito de privacidad, en términos de diseño.** El enunciado exige que ningún jugador vea la flota del otro. En este sistema eso no es una restricción de las reglas sino una **propiedad de qué se escribe en cada canal de salida**: al pintar el tablero rival en la memoria de video del Jugador 1, el programa debe traducir el estado interno de la casilla del Jugador 2 a `agua` siempre que no haya sido disparada, nunca a `barco`. Simétricamente, ninguna trama UART hacia la PC debe contener información sobre casillas del Jugador 1 que el Jugador 2 no haya descubierto por disparo propio. Esto se verifica revisando cada punto del programa donde se escribe a la memoria de video o al registro TX de la UART.

---

## 8. Protocolo UART y reutilización del periférico del Proyecto 2

### 8.1. Fundamentos de la UART

UART (*Universal Asynchronous Receiver/Transmitter*) es un protocolo serie **asíncrono**: no transmite reloj junto con los datos. Emisor y receptor deben acordar de antemano la velocidad (baudios) y el formato de trama; el receptor recupera la temporización a partir del flanco de inicio de cada trama [21][22].

La trama estándar **8N1** (8 bits de datos, sin paridad, 1 bit de parada), que es la del Proyecto 2 y la que se reutiliza aquí, es:

```
 reposo    inicio   D0  D1  D2  D3  D4  D5  D6  D7   parada   reposo
 ───────┐         ┌───┬───┬───┬───┬───┬───┬───┬───┐         ┌───────
   '1'   └────────┤   │   │   │   │   │   │   │   ├─────────┘  '1'
          '0'      LSB primero                       '1'
          
          |<------------- 10 tiempos de bit --------------->|
```

Puntos clave:

- La línea en reposo está en **nivel alto**; el bit de inicio es un **`0`**, cuyo flanco de bajada dispara la recepción.
- Los datos se envían con el **bit menos significativo primero**.
- El bit de parada es un `1` y garantiza que exista un flanco de bajada al inicio de la siguiente trama.

### 8.2. Generación y recuperación de la temporización a 115200 baudios

El sistema corre a 100 MHz y la velocidad especificada es **115200 baudios**.

**Transmisión.** El divisor es:

```
divisor_TX = 100 000 000 / 115 200 = 868,06 → 868
baudios reales = 100 000 000 / 868 = 115 207 baud
error = (115 207 − 115 200) / 115 200 = +0,006 %
```

**Recepción con sobremuestreo 16×.** La práctica estándar es muestrear la línea a 16 veces la velocidad de bit y tomar el valor en el **centro** de cada bit, lo que da máxima tolerancia a desalineación y a ruido [21][22]:

```
divisor_16x = 100 000 000 / (115 200 × 16) = 54,25 → 54
baudios efectivos = 100 000 000 / (54 × 16) = 115 741 baud
error = +0,47 %
```

**¿Es tolerable ese 0,47 %?** Sí, y conviene justificarlo cuantitativamente. El error acumulado a lo largo de una trama se mide desde el flanco de inicio hasta el último bit muestreado (el bit de parada, el décimo tiempo de bit):

```
desviación acumulada = 0,47 % × 10 tiempos de bit ≈ 0,047 tiempos de bit
```

Como el muestreo se hace en el centro del bit, el margen disponible antes de muestrear el bit equivocado es de **±0,5 tiempos de bit**. Una desviación de 0,047 representa menos del 10 % de ese margen. El criterio habitual en la literatura es que el error combinado de ambos extremos del enlace se mantenga por debajo de **±2 %** [22], y este diseño está holgadamente dentro.

**Secuencia de recepción.** Al detectar el flanco de bajada del bit de inicio, el receptor espera **8 tics** del reloj de sobremuestreo (medio tiempo de bit) y verifica que la línea siga en `0`; si no lo está, descarta el flanco como ruido. Luego muestrea cada **16 tics**, capturando así el centro de cada bit de datos. Esta verificación de medio bit es el mecanismo de rechazo de glifos espurios y es lo que hace robusto al receptor frente a picos de ruido.

### 8.3. Conexión física en la Basys3

La Basys3 integra un **FTDI FT2232HQ** que provee un puente USB–UART: el mismo cable micro-USB que programa la tarjeta expone un puerto serie virtual en la PC [13]. Las señales `RsRx` y `RsTx` están conectadas a pines dedicados de la FPGA, declarados en el archivo de *constraints* (XDC) provisto por Digilent. En Linux el dispositivo aparece típicamente como `/dev/ttyUSB1` (el `ttyUSB0` suele corresponder al canal JTAG del mismo FT2232).

> **Nota de cableado que causa errores frecuentes.** `RsRx` en el XDC de Digilent es una **entrada** a la FPGA (datos que llegan desde la PC) y `RsTx` es una **salida**. El cruce TX/RX ya está resuelto en la tarjeta; no debe invertirse nuevamente en el RTL.

### 8.4. Protocolo de aplicación sobre UART

El enunciado deja el formato exacto de trama a criterio del equipo, pero exige que sea **consistente y esté completamente documentado**, y que todo byte que no corresponda a un mensaje válido sea **descartado por la FPGA sin afectar la partida en curso**. Se propone un protocolo de **longitud fija con delimitador y suma de verificación**, por las razones que se detallan a continuación.

**Estructura de trama (5 bytes):**

```
+--------+--------+--------+--------+--------+
| 0xAA   |  TIPO  | DATO_1 | DATO_2 | CHKSUM |
+--------+--------+--------+--------+--------+
  SOF      comando   arg 1    arg 2   XOR de
  fijo                                bytes 1-3
```

**Justificación de cada campo:**

- **SOF (*start of frame*) fijo `0xAA`.** Permite que el receptor se re-sincronice tras una desconexión o un byte perdido: si el primer byte no es `0xAA`, se descarta y se sigue buscando. El valor `0xAA` (`10101010`) se elige porque alterna bits, lo que lo hace improbable como resultado de ruido y fácil de identificar en un analizador lógico.
- **Longitud fija de 5 bytes.** Simplifica enormemente el receptor en ensamblador: un contador de 0 a 4 en lugar de un analizador de longitud variable. Con nueve tipos de mensaje y dos argumentos como máximo, la longitud variable no aporta nada.
- **Suma de verificación XOR.** Detecta errores de un solo bit y la mayoría de los errores de trama. Es la verificación más barata posible en ensamblador (`xor` sobre tres registros) y cumple el requisito de descartar tramas inválidas.

**Tabla de mensajes PC → FPGA:**

| TIPO | Mensaje | DATO_1 | DATO_2 |
|---|---|---|---|
| `0x10` | Colocar barco | `id_barco` (0–2) | `(fila<<4) \| columna`, bit 7 = orientación |
| `0x11` | Disparo | `fila` (0–7) | `columna` (0–7) |
| `0x12` | Confirmación de recepción | — | — |

**Tabla de mensajes FPGA → PC:**

| TIPO | Mensaje | DATO_1 | DATO_2 |
|---|---|---|---|
| `0x20` | Inicio de fase de colocación | — | — |
| `0x21` | Colocación aceptada | `id_barco` | — |
| `0x22` | Colocación rechazada | `id_barco` | Motivo: `0`=traslape, `1`=fuera de tablero |
| `0x23` | Inicio de fase de batalla | — | — |
| `0x24` | Cambio de turno | `0`=J1, `1`=J2 | — |
| `0x25` | Resultado de disparo propio (J2) | `(fila<<4)\|columna` | `0`=fallo, `1`=impacto, `2`=hundido |
| `0x26` | Disparo recibido del J1 | `(fila<<4)\|columna` | `0`=fallo, `1`=impacto, `2`=hundido |
| `0x27` | Fin de partida | `0`=gana J1, `1`=gana J2 | `disparos_totales` |

Esta tabla cubre exhaustivamente los seis eventos que la Sección 4.5.3 del enunciado exige notificar a la PC. Nótese que los mensajes `0x25` y `0x26` están deliberadamente separados: uno informa del resultado del disparo *propio* del Jugador 2 sobre el tablero rival, y el otro del disparo *recibido* del Jugador 1 sobre el tablero propio. Esta separación es la que permite a la aplicación de PC mantener las dos vistas actualizadas sin inferir nada, respetando el requisito de que la PC no contenga lógica de juego.

**Manejo del flujo en el software del CPU.** La UART no tiene FIFO profunda; el programa debe sondear `RX_VALID` con frecuencia suficiente para no perder bytes. A 115200 baudios, un byte tarda ≈ 87 µs, lo que a 100 MHz son **8700 ciclos de CPU** — es decir, miles de instrucciones entre byte y byte. El lazo principal del juego tiene margen sobrado siempre que no ejecute operaciones largas y bloqueantes entre sondeos. La operación más larga identificada es el borrado de pantalla (≈ 12 µs), muy por debajo del presupuesto.

---

## 9. Aplicación de PC con `pyserial`

### 9.1. La biblioteca

`pyserial` es la biblioteca estándar de facto para acceso a puertos serie desde Python. Proporciona una interfaz uniforme sobre Windows, Linux y macOS, y soporta tanto acceso bloqueante como con tiempo de espera [23].

Instalación y uso básico:

```bash
pip install pyserial
python -m serial.tools.list_ports   # identificar el puerto de la Basys3
```

```python
import serial

ser = serial.Serial(
    port='/dev/ttyUSB1',    # 'COMx' en Windows
    baudrate=115200,
    bytesize=serial.EIGHTBITS,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    timeout=0.1,            # timeout de lectura en segundos
)
```

Los parámetros `bytesize`, `parity` y `stopbits` deben coincidir exactamente con la configuración 8N1 del periférico UART de la FPGA; una discordancia produce bytes corruptos de forma sistemática y difícil de diagnosticar.

### 9.2. Aspectos prácticos a considerar

1. **`timeout` es obligatorio en la práctica.** Con `timeout=None`, `ser.read()` bloquea indefinidamente y la aplicación queda congelada si la FPGA no responde. Con `timeout` definido, `read(n)` devuelve lo que haya recibido (posiblemente menos de *n* bytes, o `b''`) al expirar el plazo, permitiendo que el lazo principal siga vivo y pueda reintentar o informar al usuario. Esto es lo que hace cumplir el requisito del enunciado de que la aplicación no se bloquee.
2. **`read(n)` puede devolver menos de *n* bytes.** Es el error más común al implementar protocolos de trama fija. La lectura debe acumularse en un búfer hasta completar los 5 bytes:

   ```python
   def leer_trama(ser):
       buf = b''
       while len(buf) < 5:
           chunk = ser.read(5 - len(buf))
           if not chunk:
               return None          # timeout, sin trama completa
           buf += chunk
       return buf
   ```

   Alternativamente, `ser.read_until(expected=..., size=5)` o el atributo `in_waiting` permiten estrategias no bloqueantes.
3. **Re-sincronización con el byte SOF.** Si el primer byte leído no es `0xAA`, debe descartarse y volver a leer byte por byte hasta encontrarlo. Esto es lo que permite recuperarse de una desconexión a mitad de trama.
4. **Buffers del sistema operativo.** El puerto serie tiene búferes en el controlador del SO que pueden contener datos antiguos de una ejecución anterior. Al abrir el puerto conviene llamar `ser.reset_input_buffer()` y `ser.reset_output_buffer()`.
5. **Concurrencia de la interfaz.** La aplicación debe simultáneamente esperar entrada del usuario (por teclado) y atender mensajes entrantes de la FPGA (cambio de turno, disparo recibido). Las alternativas son un **hilo lector** que deposita tramas en una `queue.Queue`, o un **lazo único no bloqueante** que alterna entre comprobar `ser.in_waiting` y comprobar la entrada del usuario con tiempo de espera. Para una aplicación de consola, el hilo lector con cola es la opción más limpia y evita perder notificaciones mientras el usuario piensa su jugada.
6. **Validación antes de transmitir.** El enunciado exige que la aplicación valide la entrada del usuario (por ejemplo, coordenadas fuera de rango) antes de enviarla. Esto no es lógica de juego —no decide si hay impacto ni si la colocación es legal, eso lo hace la FPGA—, sino **validación de formato de entrada**, que es responsabilidad legítima de una terminal.
7. **Permisos en Linux.** El acceso a `/dev/ttyUSB*` requiere pertenecer al grupo `dialout`:

   ```bash
   sudo usermod -a -G dialout $USER   # requiere cerrar y reabrir sesión
   ```

### 9.3. Frontera de responsabilidades

El enunciado es enfático: la aplicación de PC es una **terminal de entrada/salida remota sin lógica de juego propia**. La siguiente delimitación guiará la implementación:

| La aplicación de PC **sí** hace | La aplicación de PC **no** hace |
|---|---|
| Solicitar al usuario coordenadas y orientación | Decidir si una colocación es válida |
| Validar el **formato** de la entrada (rango 0–7, carácter correcto) | Decidir si hay impacto, fallo o hundimiento |
| Serializar y transmitir tramas | Llevar el turno por su cuenta |
| Recibir tramas y actualizar su vista | Determinar el ganador |
| Dibujar los dos tableros en consola | Almacenar el estado autoritativo de la partida |
| Reintentar una colocación si la FPGA la rechaza | Inferir la flota del rival |

Toda decisión de reglas proviene de un mensaje explícito de la FPGA. Si la aplicación necesitara "adivinar" algo, es señal de que falta un mensaje en el protocolo — criterio que se usará para validar la completitud de la tabla de §8.4.

---

## Referencias

### Arquitectura RISC-V

[1] RISC-V International. *RISC-V Technical Specifications*.
<https://riscv.org/technical/specifications/>

[2] A. Waterman, K. Asanović et al. *The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture*. RISC-V International. Repositorio oficial:
<https://github.com/riscv/riscv-isa-manual>

[3] RISC-V Non-ISA Specifications. *RISC-V Assembly Programmer's Manual* (registros, nombres ABI, pseudo-instrucciones, directivas).
<https://github.com/riscv-non-isa/riscv-asm-manual>

[4] RISC-V Collab. *riscv-gnu-toolchain* — compilador, ensamblador y utilidades GNU para RISC-V.
<https://github.com/riscv-collab/riscv-gnu-toolchain>

### Organización de computadores y diseño de *datapath*

[5] D. A. Patterson y J. L. Hennessy. *Computer Organization and Design RISC-V Edition: The Hardware Software Interface*. Morgan Kaufmann. Capítulo 4 (El procesador) y Apéndice A (Ensamblador).
<https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-820331-6>

[6] S. L. Harris y D. Harris. *Digital Design and Computer Architecture, RISC-V Edition*. Morgan Kaufmann. Capítulo 7 (Microarquitectura): *datapath* de ciclo único, multiciclo y segmentado, unidad de control en dos niveles. Materiales del libro:
<https://pages.hmc.edu/harris/ddca/ddcarv.html>

[7] C. Wolf. *PicoRV32 — A Size-Optimized RISC-V CPU*. Implementación abierta de referencia de un núcleo RV32I en Verilog.
<https://github.com/YosysHQ/picorv32>

### Síntesis, FPGA y herramientas

[8] AMD/Xilinx. *Vivado Design Suite User Guide: Synthesis* (UG901) — inferencia de RAM de doble puerto, atributos de síntesis, prevención de *latches*.
<https://docs.amd.com/r/en-US/ug901-vivado-synthesis>

[9] lowRISC / OpenTitan. *Register Tool (`reggen`) and Register Definition Guidelines* — convenciones para definir bancos de registros de periféricos.
<https://opentitan.org/book/util/reggen/index.html>

[10] OpenCores. *Wishbone B4 — WISHBONE System-on-Chip (SoC) Interconnection Architecture for Portable IP Cores*. Referencia de handshake y mapeo de registros en buses simples.
<https://cdn.opencores.org/downloads/wbspec_b4.pdf>

[14] AMD/Xilinx. *Clocking Wizard LogiCORE IP Product Guide* (PG065) — generación de relojes derivados con MMCM/PLL.
<https://docs.amd.com/r/en-US/pg065-clk-wiz>

[15] AMD/Xilinx. *7 Series FPGAs Memory Resources User Guide* (UG473) — Block RAM, modos de doble puerto verdadero, relojes independientes y comportamiento en colisión.
<https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources>

[17] C. E. Cummings. *Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog*. SNUG. Referencia estándar sobre sincronizadores de dos *flip-flops* y cruce de dominios.
<http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf>

### VGA y video

[11] VESA. *Display Monitor Timing (DMT) Standard*.
<https://vesa.org/vesa-standards/>

[12] TinyVGA. *VGA Signal 640 × 480 @ 60 Hz Industry Standard Timing* — tabla de temporizaciones horizontal y vertical, polaridades y reloj de píxel.
<http://www.tinyvga.com/vga-timing/640x480@60Hz>

[13] Digilent. *Basys 3 FPGA Board Reference Manual* — puerto VGA con DAC R-2R de 4 bits por canal, pulsadores, displays de 7 segmentos, puente USB-UART FT2232HQ, oscilador de 100 MHz.
<https://digilent.com/reference/programmable-logic/basys-3/reference-manual>

[16] NESdev Wiki. *PPU pattern tables / nametables* — documentación del enfoque clásico de gráficos por *tiles* usado en hardware con memoria limitada.
<https://www.nesdev.org/wiki/PPU_nametables>

### Interfaces y entradas

[18] J. Ganssle. *A Guide to Debouncing* — mediciones experimentales de rebote en pulsadores comerciales y comparación de técnicas de filtrado en hardware y software.
<https://www.ganssle.com/debouncing.htm>

[21] Wikibooks. *Serial Programming / 8250 UART Programming* — formato de trama, bits de inicio/parada, sobremuestreo y cálculo de divisores de baudios.
<https://en.wikibooks.org/wiki/Serial_Programming/8250_UART_Programming>

[22] Nandland. *UART Serial Port Module in VHDL and Verilog* — implementación de referencia de transmisor y receptor UART con sobremuestreo, y análisis de tolerancia de error de baudios en FPGA.
<https://nandland.com/uart-serial-port-module/>

[23] C. Liechti. *pySerial Documentation* — API `serial.Serial`, parámetros de configuración, `timeout`, `in_waiting`, `read_until`, herramientas de listado de puertos.
<https://pyserial.readthedocs.io/en/latest/>

### Reglas del juego

[19] Hasbro. *Battleship — Instrucciones oficiales del juego* (reglas de colocación, disparo, hundimiento y victoria).
<https://instructions.hasbro.com/en-us/instruction/battleship-game>

[20] Board Game Geek. *Battleship (1967)* — ficha del juego, historia y variantes de reglas.
<https://boardgamegeek.com/boardgame/2425/battleship>

### Documento del curso

[24] J. González-Gómez y R. Coto Calderón. *Proyecto 3 — Batalla Naval: juego de dos jugadores sobre un microprocesador RISC-V con periférico VGA*. EL3313 Taller de Diseño Digital, Escuela de Ingeniería Electrónica, Instituto Tecnológico de Costa Rica, II Semestre 2026. (`EL3313_proyecto3_2S2026.pdf`)
