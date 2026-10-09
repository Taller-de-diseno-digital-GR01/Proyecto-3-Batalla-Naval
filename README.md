# Proyecto 3, Batalla Naval sobre RISC-V con VGA, EL3313 Taller de Diseño Digital

Profesor:
- Dr.-Ing. Jeferson González-Gómez, Ing. Rolen Coto Calderón

Integrantes:
- Carlos Castro Villegas
- Jefferson Chinchilla Quesada
- Mattio Coghi Quirós
- Nicolás Mena Valerio

II Semestre 2026

## Propósito

Juego de Batalla Naval para dos jugadores sobre una FPGA Basys 3 (Artix-7 XC7A35T). Dentro de la
FPGA corre un microprocesador RISC-V rv32i de ciclo único que ejecuta un programa en ensamblador, y
todas las reglas del juego viven en ese programa: la colocación de los barcos, la validación de
cada disparo, el cambio de turno, los barcos hundidos y el fin de la partida. El hardware solo
aporta periféricos mapeados en memoria que hacen el manejo de bajo nivel (temporización VGA,
tramas UART a nivel de bit, barrido de los displays, generación de tonos).

Cada jugador tiene un tablero de 8 × 8 con tres barcos de 4, 3 y 2 casillas. El Jugador 1 juega en
la FPGA, con los botones de la Basys 3 y un monitor VGA de 640 × 480 a 60 Hz que muestra su
tablero, los disparos que hizo sobre el rival y un HUD con la fase del juego. El Jugador 2 juega
desde una aplicación de PC en Python, una terminal sin reglas propias que se comunica con la FPGA
por UART a 115200 baudios. Ninguno de los dos ve la flota del otro. Los displays de 7 segmentos
llevan las partidas ganadas por cada jugador, tres LED indican la fase y un buzzer da cinco sonidos
distintos (impacto, agua, hundido, colocación inválida y victoria).

El enunciado completo del proyecto está en [`EL3313_proyecto3_2S2026.pdf`](EL3313_proyecto3_2S2026.pdf).

## Estructura del repo

- `EL3313_proyecto3_2S2026.pdf`: enunciado e indicaciones del proyecto.
- `docs/diseño/`: planteamiento del diseño, con la investigación previa, los diagramas por nivel y
  las specs por módulo.
- `docs/diseño/diagramas/esquematicos/`: scripts que generan los esquemáticos por compuertas de
  los docs de módulo a partir del RTL, con yosys y netlistsvg.
- `docs/informe/`: informe técnico final.
- `src/design/`: RTL en SystemVerilog, un archivo por módulo. `top.sv` es el sistema completo. El
  núcleo RISC-V parte de [riscv-simple-sv](https://github.com/tilk/riscv-simple-sv) (licencia en
  `LICENSE.riscv-simple-sv`). `prueba_vga.sv` es un top de prueba física del VGA sin procesador.
- `src/sim/`: testbenches autoverificables (`tb_<modulo>.sv`), más `tb_top.sv` del sistema
  completo con el programa real y `tb_top_temporizado.sv`, la prueba de la simulación
  post-implementación temporizada.
- `src/sim/riscv-tests/`: pruebas rv32ui oficiales de RISC-V, armadas para la ROM, que usa
  `tb_procesador_uniciclo.sv`.
- `src/fpga/`: constraints de la Basys3 (`basys3.xdc`), `velocidad_config.py`, que acelera la
  carga del bitstream desde la flash, y `vivado_timesim.tcl`, que implementa el diseño con Vivado
  y exporta el netlist con retardos para `make sim-post`.
- `sw/programa.s`: programa en ensamblador rv32i que corre en el procesador, y `sw/programa.hex`,
  su imagen para la ROM.
- `sw/ensamblar.sh` y `sw/ensamblar_llvm.sh`: ensamblan el programa con binutils de GNU o con LLVM,
  y rechazan cualquier instrucción que el núcleo no implemente.
- `sw/batalla_pc.py` y sus módulos (`enlace.py`, `protocolo.py`, `partida.py`, `vista.py`,
  `terminal.py`, `dibujo.py`): aplicación de PC del Jugador 2.
- `sw/pruebas/`: pruebas de la app de PC.
- `GNUmakefile`: flujo del proyecto (Linux, WSL, FreeBSD y macOS): simulación, síntesis completa
  con el toolchain abierto openXC7 (sin Vivado), programación de la tarjeta, ensamblado del
  programa y app de PC. Solo la simulación post-implementación temporizada usa Vivado.
- `Makefile`: envoltorio para FreeBSD, que pasa cada target a GNU make (`gmake`).

## Diseño modular

### Investigación previa

- [Investigación previa](docs/diseño/investigacion-previa.md)

### Nivel 1: Sistema completo

- [Diagrama de primer nivel](docs/diseño/diagramas/nivel01.md)

### Nivel 2: Bloques principales

- [Diagrama de segundo nivel](docs/diseño/diagramas/nivel02.md), con la justificación del PLL y
  de la frecuencia del reloj del sistema (33,33 MHz).

### Nivel 3: Módulos

- [Diagrama de tercer nivel](docs/diseño/diagramas/nivel03.md), con el mapa de memoria, la
  organización de los datos en RAM y el protocolo UART entre la FPGA y la PC.

### Nivel 4: Diseño detallado por módulo

Procesador y memorias:

- [Procesador uniciclo RISC-V](docs/diseño/modulos/PROCESADOR_UNICICLO.md)
- [ROM de programa](docs/diseño/modulos/ROM.md)
- [RAM de datos](docs/diseño/modulos/RAM.md)
- [Address Translator](docs/diseño/modulos/Address_Translator.md)

Periféricos y sus submódulos:

- [Periférico VGA](docs/diseño/modulos/PERIFERICO_VGA.md)
  - [Fuente de caracteres](docs/diseño/modulos/FUENTE_CARACTERES.md)
- [Periférico UART](docs/diseño/modulos/PERIFERICO_UART.md)
  - [Núcleo UART TX](docs/diseño/modulos/NUCLEO_UART_TX.md)
  - [Núcleo UART RX](docs/diseño/modulos/NUCLEO_UART_RX.md)
- [Periférico de entradas](docs/diseño/modulos/PERIFERICO_ENTRADAS.md)
- [Periférico de 7 segmentos](docs/diseño/modulos/PERIFERICO_7SEG.md)
  - [Marcador](docs/diseño/modulos/marcador.md)
- [Periférico LED de estado](docs/diseño/modulos/PERIFERICO_LED.md)
- [Periférico buzzer](docs/diseño/modulos/PERIFERICO_BUZZER.md)
  - [Secuenciador de melodía](docs/diseño/modulos/secuenciador_melodia.md)
  - [Generador de tono](docs/diseño/modulos/generador_tono.md)

El programa en ensamblador, que no es hardware pero es donde viven las reglas del juego:

- [Programa: organización del código, convención de llamado, subrutinas y fases del juego](docs/diseño/modulos/PROGRAMA.md)

## Dependencias

### Hardware

- Tarjeta Basys 3 (Xilinx Artix-7 XC7A35T) y cable USB de datos. El mismo cable programa la FPGA
  por JTAG y expone el puerto serie virtual de la UART, mediante el chip FTDI de la tarjeta.
- Monitor VGA y cable VGA.
- Buzzer conectado entre el pin 4 del Pmod JC (JC4, pin P18) y tierra.
- Computadora para la app del Jugador 2.

### Software

- Python 3 y la librería `pyserial` (`sw/requirements.txt`), para la app de PC. La app lee el
  teclado con `termios`, así que corre en Linux, macOS, FreeBSD o WSL, no en Windows nativo.
- [Icarus Verilog](https://github.com/steveicarus/iverilog) **13** (`iverilog`, `vvp`),
  obligatorio para correr las simulaciones. La versión 12 que traen los repositorios de varias
  distribuciones no acepta `return` dentro de un `task` ni los literales `'{...}` de arreglos que
  usan los testbenches, así que hay que compilarlo desde el tag `v13_0`. En Ubuntu 24.04 y
  derivadas, las herramientas de compilación van con `apt` y el Icarus queda en `~/.local`, sin
  `sudo`:

  ```sh
  sudo apt install autoconf gperf flex bison g++ make
  git clone --depth 1 --branch v13_0 https://github.com/steveicarus/iverilog.git
  cd iverilog && sh autoconf.sh && ./configure --prefix=$HOME/.local && make -j && make install
  ```

  `~/.local/bin` tiene que ir antes que `/usr/bin` en el `PATH`, y `iverilog -V` debe decir 13.0.
- [GTKWave](https://gtkwave.sourceforge.net/), opcional, solo para inspeccionar formas de onda
  (`make wave`).
- [yosys](https://github.com/YosysHQ/yosys), para la síntesis.
- Toolchain abierto [openXC7](https://github.com/openXC7) (`nextpnr-xilinx`, `prjxray`,
  `fasm2frames.py`, `xc7frames2bit`) y
  [`openFPGALoader`](https://github.com/trabucayre/openFPGALoader), para generar el bitstream y
  cargarlo en la tarjeta.
- Binutils de GNU para RISC-V (`riscv64-unknown-elf-as` y `-ld`) o LLVM (`llvm-mc`), opcionales,
  solo para volver a ensamblar el programa. `sw/programa.hex` ya está versionado.
- Vivado (probado con 2026.1, la edición gratuita alcanza para el XC7A35T), opcional, solo para la
  simulación post-implementación temporizada (`make sim-post`). Por defecto se toma de
  `/opt/Xilinx/2026.1/Vivado`, otra ruta se pasa con `XILINX_VIVADO=<ruta>`.

## Instalación

1. Clonar el repositorio.
2. Crear un entorno virtual e instalar la app de PC:

   ```sh
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r sw/requirements.txt
   ```

3. Instalar Icarus Verilog 13 y dejarlo en el `PATH`.
4. Instalar el toolchain openXC7 en `/opt/openxc7` (o en otra ruta, pasando `OPENXC7=<ruta>` a
   `make`), clonar el repo de `prjxray` (por defecto en `~/prjxray`, o pasando
   `PRJXRAY_PY=<ruta>`) e instalar `openFPGALoader`. El `GNUmakefile` arma solo el `PATH` y el
   `PYTHONPATH` que esas herramientas necesitan, no hace falta correr `source .../export.sh` a mano.
5. En WSL, la Basys 3 se pasa de Windows a Linux con
   [usbipd-win](https://github.com/dorssel/usbipd-win) (`usbipd attach --wsl --busid <id>`) antes de programarla
   o de abrir la app.
6. Verificar que la tarjeta se detecte:

   ```sh
   make connect
   ```

`make help` lista todos los targets disponibles.

## Compilación y simulación

Cada módulo de `src/design/` tiene su testbench autoverificable en `src/sim/tb_<modulo>.sv`, que
imprime cuántas pruebas pasaron y cuántas fallaron.

```sh
make list                       # lista los testbenches disponibles
make sim TB=<modulo>            # compila y corre un testbench puntual
make test                       # corre todos los testbenches, uno por uno
make wave TB=<modulo>           # corre la simulación y abre GTKWave
make synth SYNTH_TOP=<modulo>   # sintetiza con yosys y revisa que no haya latches inferidos
make test-app                   # pruebas de la app de PC (unittest), no necesita la tarjeta
make programa                   # vuelve a ensamblar sw/programa.s y regenera sw/programa.hex
make sim-post                   # simulación post-implementación temporizada con Vivado, ~1 hora
```

Los testbenches se corren siempre con `make`, porque los que cargan un `.hex` en la ROM esperan
`src/build/` como carpeta de trabajo. Los mensajes `ERROR: $readmemh` que aparecen en testbenches
que no usan la ROM son esperados: iverilog compila `rom.sv` igual y no encuentra el archivo.

Verificación principal:

- `tb_procesador_uniciclo` corre las 29 pruebas rv32ui oficiales sobre el núcleo.
- `tb_top` simula el sistema completo con el programa real: arranque, colocación de los dos
  jugadores, rechazo de colocaciones inválidas, privacidad en el VGA, una partida completa hasta
  la victoria y el reinicio de partida con `BTN_RST`.
- `make sim-post` implementa el diseño con Vivado y corre `tb_top_temporizado` sobre el netlist
  ruteado con sus retardos (SDF) en xsim: el arranque del programa, revisando cada instrucción que
  sale de la ROM y el flujo del PC, la colocación de las dos flotas y un disparo de cada jugador.
  Para que quepa en una hora, ese netlist lleva la UART a 694 444 baudios, el de la tarjeta sigue en
  115 200. La misma prueba corre sobre el RTL con `make sim TB=top_temporizado`. Detalles en la
  sección 10.7 del informe.

## Ejecución

### Cargar el sistema completo en la Basys3

El flujo usa yosys, nextpnr-xilinx y prjxray (openXC7), sin Vivado.

```sh
make bitstream   # sintetiza e implementa src/design/top.sv -> src/build/top.bit
make program     # reconstruye el bitstream si hace falta y lo carga en la SRAM de la FPGA
make flash       # igual que program, pero graba el bitstream en la flash de la tarjeta
make all         # bitstream + program
```

El reinicio general del sistema es el botón **PROG** de la Basys 3, que vuelve a configurar la FPGA
desde la flash. Por eso, para jugar, el bitstream se graba con `make flash` y el jumper **JP1**
queda en **QSPI**. Con `make program` el diseño vive solo en la SRAM y PROG lo borra.
`make bitstream` aplica además `src/fpga/velocidad_config.py`, que hace que la tarjeta cargue el
diseño desde la flash en unos 0,5 s en lugar de unos 6 s.

`make bitstream` revisa antes que estén todas las herramientas, el chipdb y la base de datos de
prjxray, y se detiene si falta algo. Si `fasm2frames.py` fallara a medio camino, el `.bit` saldría
en blanco y la tarjeta lo aceptaría sin avisar.

### Jugar en la FPGA (Jugador 1)

| Control | Acción |
|---|---|
| `btnU`, `btnD`, `btnL`, `btnR` | Mover el cursor |
| `btnC` | Rotar el barco que se está colocando |
| SW0 | Confirmar la colocación o el disparo (se sube para confirmar y se baja antes de volver a usarlo) |
| SW15 | Partida nueva, conserva las partidas ganadas |
| PROG | Reinicio general, pone en cero las partidas ganadas |

Los LED LD0, LD1 y LD2 indican la fase (colocación, batalla y resultado) y los displays de
7 segmentos muestran las partidas ganadas de cada jugador. Durante la colocación los dos jugadores
avanzan a la vez. Durante la batalla el turno se alterna tras cada disparo válido, y la partida
acaba cuando una flota queda hundida.

### Jugar desde la PC (Jugador 2)

Con la FPGA ya programada y conectada:

```sh
python3 sw/batalla_pc.py --lista       # lista los puertos donde se detecta la Basys 3
python3 sw/batalla_pc.py               # busca la tarjeta sola y abre la terminal del juego
python3 sw/batalla_pc.py -p <puerto>   # o se indica el puerto a mano

# equivalente con make
make app
make app PUERTO=<puerto>
```

Dentro de la terminal, las flechas o `h`, `j`, `k`, `l` mueven el cursor, `r` rota el barco,
`Enter` coloca un barco o dispara, y `Esc` o `Ctrl+D` cierra la app. El protocolo de tramas de
5 bytes entre la FPGA y la PC está documentado en la sección "Mensajes UART que usa el flujo" de
[`docs/diseño/diagramas/nivel03.md`](docs/diseño/diagramas/nivel03.md).
