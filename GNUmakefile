DESIGN_DIR := src/design
SIM_DIR    := src/sim
BUILD_DIR  := src/build

IVERILOG       := iverilog
# -I para los `include "config.sv" y "constants.sv" del núcleo RISC-V. yosys los busca solo
# en la carpeta del archivo que los incluye, iverilog no
IVERILOG_FLAGS := -g2012 -I $(DESIGN_DIR)
VVP            := vvp
GTKWAVE        := gtkwave
VECDUMP        := vecdump # Programa para pasar de .vcd a .svg
YOSYS          := yosys
OPENFPGALOADER := openFPGALoader
BOARD          := basys3

# doas es lo normal en FreeBSD pero casi nunca está en Linux, y el demo puede terminar
# corriendo desde otra máquina del equipo. Se puede forzar con make program PRIV=sudo
PRIV := $(shell command -v doas >/dev/null 2>&1 && echo doas || echo sudo)

# Toolchain openXC7 (yosys + nextpnr-xilinx + prjxray), sin Vivado.
#
# No hace falta correr 'source /opt/openxc7/export.sh' antes: el makefile arma solo
# el PATH y el PYTHONPATH que necesitan nextpnr-xilinx y fasm2frames.py. Si el
# toolchain está en otro lado se sobreescribe con, por ejemplo,
#   make bitstream OPENXC7=/ruta/openxc7 PRJXRAY_PY=/ruta/prjxray
OPENXC7    ?= /opt/openxc7
# Repo clonado de prjxray, de ahí sale el módulo de python 'prjxray' que importa
# fasm2frames.py (el paquete 'fasm' sí viene dentro de openXC7)
PRJXRAY_PY ?= $(HOME)/prjxray

export PATH       := $(OPENXC7)/bin:$(PATH)
export PYTHONPATH := $(OPENXC7)/lib/python:$(PRJXRAY_PY)$(if $(PYTHONPATH),:$(PYTHONPATH))
export NEXTPNR_XILINX_PYTHON_DIR := $(OPENXC7)/lib/python
export PRJXRAY_DB_DIR            := $(OPENXC7)/share/nextpnr/prjxray-db

NEXTPNR_XILINX  := nextpnr-xilinx
FASM2FRAMES      = $(PYTHON) $(OPENXC7)/bin/fasm2frames.py
XC7FRAMES2BIT   := xc7frames2bit
PART            := xc7a35tcpg236-1
PRJXRAY_DB_ROOT := $(PRJXRAY_DB_DIR)/artix7
CHIPDB          := $(OPENXC7)/share/nextpnr-xilinx/chipdb/xc7a35tcpg236.bin
XDC             := src/fpga/basys3.xdc
VELOCIDAD_CONFIG := src/fpga/velocidad_config.py

APP_DIR    := sw
PYTHON     := python3

# Vivado solo para la simulación post-implementación temporizada (make sim-post), el bitstream
# sigue saliendo de openXC7. Se cambia la ruta con make sim-post XILINX_VIVADO=/ruta/Vivado
XILINX_VIVADO ?= /opt/Xilinx/2026.1/Vivado
VIVADO_BIN    := $(XILINX_VIVADO)/bin
TIMESIM_DIR   := $(BUILD_DIR)/timesim
TIMESIM_TCL   := src/fpga/vivado_timesim.tcl
TIMESIM_TB    := $(SIM_DIR)/tb_top_temporizado.sv
TIMESIM_NET   := $(TIMESIM_DIR)/top_timesim.v
# El gcc que trae xsim para enlazar la simulación no busca en la carpeta de libc del sistema, y en
# Ubuntu 24.04 (y derivados) falla con "cannot find crti.o"
XSIM_ENV      := LIBRARY_PATH=/usr/lib/x86_64-linux-gnu$(if $(LIBRARY_PATH),:$(LIBRARY_PATH))

DESIGN_SRCS := $(wildcard $(DESIGN_DIR)/*.sv)
TB_SRCS     := $(wildcard $(SIM_DIR)/tb_*.sv)
TBS         := $(patsubst $(SIM_DIR)/tb_%.sv,%,$(TB_SRCS))

TB ?= $(firstword $(TBS))
SYNTH_TOP ?= top

# Programa en ensamblador que carga la ROM con $readmemh. ensamblar.sh usa binutils de GNU
# para RISC-V (riscv64-unknown-elf-*), que solo hacen falta para volver a ensamblar.
PROG_SRC  := sw/programa.s
PROG_HEX  := sw/programa.hex
ENSAMBLAR := sw/ensamblar.sh

VVP_OUT := $(BUILD_DIR)/tb_$(TB).vvp
VCD_OUT := $(BUILD_DIR)/tb_$(TB).vcd
SVG_OUT := $(BUILD_DIR)/tb_$(TB).svg

NETLIST_OUT := $(BUILD_DIR)/$(SYNTH_TOP)_synth.v
SYNTH_LOG   := $(BUILD_DIR)/$(SYNTH_TOP)_synth.log

JSON_OUT   := $(BUILD_DIR)/$(SYNTH_TOP).json
ROUTED_OUT := $(BUILD_DIR)/$(SYNTH_TOP)_routed.json
FASM_OUT   := $(BUILD_DIR)/$(SYNTH_TOP).fasm
FRAMES_OUT := $(BUILD_DIR)/$(SYNTH_TOP).frames
BIT_OUT    := $(BUILD_DIR)/$(SYNTH_TOP).bit
BIT        ?= $(BIT_OUT)

# Identifica el toolchain (ruta + versión de iverilog/yosys/nextpnr-xilinx) para invalidar
# el build si src/build/ quedó con binarios de otra máquina
TOOLCHAIN_STAMP := $(BUILD_DIR)/.toolchain

# Linter y simulación del netlist de síntesis del sistema completo (siempre el top)
VERILATOR     := verilator
LINT_LOG      := $(BUILD_DIR)/lint.log
PS_DIR        := $(SIM_DIR)/post_sintesis
PS_NETLIST    := $(BUILD_DIR)/top_netlist.v
PS_VVP        := $(BUILD_DIR)/tb_post_sintesis.vvp
# Modelos de simulación de las primitivas de Xilinx que trae yosys (LUT, FDRE, CARRY4, RAM64M...)
CELLS_SIM     := $(OPENXC7)/share/yosys/xilinx/cells_sim.v

.PHONY: all help list sim wave dump test test-app synth lint post-sintesis bitstream program flash connect app clean check-tb check-fpga-toolchain programa sim-post check-vivado FORCE

# Si una receta falla, borra el archivo que estaba generando. Sin esto un paso que
# escribe con redirección (ej. fasm2frames > top.frames) deja un archivo vacío que
# make da por hecho la próxima vez, y el .bit sale en blanco sin avisar.
.DELETE_ON_ERROR:

all: bitstream program

help:
	@echo "make all                genera el bitstream y lo carga a la FPGA (bitstream + program)"
	@echo "make list              lista los testbenches disponibles"
	@echo "make sim  TB=<modulo>  compila y corre src/sim/tb_<modulo>.sv"
	@echo "make wave TB=<modulo>  corre la simulación y abre GTKWave"
	@echo "make dump TB=<modulo> SIGS=sig1,sig2,...  corre la simulación y exporta un SVG con vecdump"
	@echo "make test               corre todos los testbenches, uno por uno"
	@echo "make test-app           corre las pruebas de la app de PC con unittest, no necesita la tarjeta"
	@echo "make programa           ensambla $(PROG_SRC) con $(ENSAMBLAR) y regenera $(PROG_HEX)"
	@echo "make synth SYNTH_TOP=<modulo>  sintetiza con yosys (genérico) y revisa que no haya latches inferidos"
	@echo "make lint               pasa verilator --lint-only -Wall por el top y falla si encuentra latches o drivers múltiples"
	@echo "make post-sintesis      simula el netlist de synth_xilinx del top con el programa real (src/sim/post_sintesis)"
	@echo "make sim-post           implementa top con Vivado y corre $(TIMESIM_TB) sobre el netlist ruteado con sus"
	@echo "                        retardos (SDF) en xsim: arranque del programa, colocación y un disparo de cada jugador."
	@echo "                        Tarda cerca de una hora. Usa Vivado de XILINX_VIVADO=$(XILINX_VIVADO), deja todo en $(TIMESIM_DIR)"
	@echo "make bitstream          genera $(BIT_OUT) con yosys + nextpnr-xilinx + prjxray (openXC7, sin Vivado)"
	@echo "                        toma el toolchain de OPENXC7=$(OPENXC7) y PRJXRAY_PY=$(PRJXRAY_PY), no hace falta"
	@echo "                        correr 'source .../export.sh' antes"
	@echo "make program            reconstruye el bitstream si hace falta y lo carga al Basys3 con openFPGALoader"
	@echo "make program BIT=<archivo.bit>  carga ese .bit tal cual, sin reconstruir nada"
	@echo "make flash              igual que program pero graba el bitstream en la flash, para que el botón PROG reconfigure"
	@echo "                        la FPGA sin la PC. Acepta BIT= igual, y la tarjeta arranca de ahí con el jumper JP1 en QSPI"
	@echo "make connect             verifica que la Basys3 esté detectable por USB/JTAG antes de programar"
	@echo "make app                 corre la app de PC (terminal remota del Jugador 2 por UART)"
	@echo "make clean"
	@echo ""
	@echo "Testbenches disponibles, $(TBS)"
	@echo "TB por defecto si no se indica, $(TB)"
	@echo "SYNTH_TOP por defecto si no se indica, $(SYNTH_TOP)"

list:
	@echo "Testbenches disponibles, $(TBS)"

# Falla si no hay ningún testbench para correr (TB vacío)
check-tb:
ifeq ($(strip $(TB)),)
	$(error No se encontró ningún testbench en $(SIM_DIR)/tb_*.sv)
endif

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Prerrequisito vacío que nunca existe como archivo, obliga a rehacer lo que lo tenga.
# Va acá y no antes de 'all' para no robarle el lugar de target por defecto.
FORCE:

# FORCE hace que la receta corra en cada make: sin eso el stamp solo se escribía la
# primera vez (make lo veía siempre al día por existir) y nunca invalidaba nada. El cmp
# de abajo es el que decide, solo le mueve la fecha si el toolchain cambió de verdad.
$(TOOLCHAIN_STAMP): FORCE | $(BUILD_DIR)
	@{ echo "$$($(IVERILOG) -V 2>/dev/null | head -1)|$$(command -v $(IVERILOG))"; \
	   echo "$$($(YOSYS) -V 2>/dev/null)|$$(command -v $(YOSYS))"; \
	   echo "$$(command -v $(NEXTPNR_XILINX))"; } > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null && rm -f $@.tmp || mv $@.tmp $@

$(VVP_OUT): $(DESIGN_SRCS) $(SIM_DIR)/tb_$(TB).sv $(TOOLCHAIN_STAMP) | $(BUILD_DIR) check-tb
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(DESIGN_SRCS) $(SIM_DIR)/tb_$(TB).sv

sim: check-tb $(VVP_OUT)
	cd $(BUILD_DIR) && $(VVP) $(notdir $(VVP_OUT))

wave: sim
	$(GTKWAVE) $(VCD_OUT) &

dump: sim
ifeq ($(strip $(SIGS)),)
	$(error Uso, make dump TB=<modulo> SIGS=sig1,sig2,...  ej. make dump TB=marcador SIGS=clk,rst,o_an)
endif
	$(VECDUMP) $(VCD_OUT) -s $(SIGS) -o $(SVG_OUT)
	@echo ".svg generado en $(SVG_OUT)"

# Ej:
# make dump TB=marcador SIGS=clk,rst,o_an
# Hay que conocer las señales que se quieren ver, eso es lo único malo.

# programa.hex va versionado, así que esta regla no depende de programa.s y solo corre si
# el .hex falta. Si dependiera del .s, después de un clone o un checkout las fechas de los
# dos archivos quedan en cualquier orden y make intentaría ensamblar en una máquina sin
# binutils de RISC-V. Para volver a ensamblar después de cambiar el programa: make programa
$(PROG_HEX):
	bash $(ENSAMBLAR) $(PROG_SRC)

programa:
	bash $(ENSAMBLAR) $(PROG_SRC)

# $(PROG_HEX) está en los prerrequisitos de la síntesis porque la ROM lo lee con $readmemh:
# si falta se genera, y si cambia se vuelve a sintetizar
#
# read_verilog -lib carga las primitivas de Xilinx (BUFG, PLLE2_BASE de generador_relojes) como
# cajas negras. Sin eso hierarchy -check corta en el top porque no las encuentra. synth_xilinx,
# el de make bitstream, ya las carga solo
$(NETLIST_OUT): $(DESIGN_SRCS) $(PROG_HEX) $(TOOLCHAIN_STAMP) | $(BUILD_DIR)
	@$(YOSYS) -p " \
		read_verilog -lib +/xilinx/cells_sim.v +/xilinx/cells_xtra.v; \
		read_verilog -sv $(DESIGN_SRCS); \
		hierarchy -check -top $(SYNTH_TOP); \
		proc; opt; \
		prep -top $(SYNTH_TOP); \
		opt_clean; \
		stat; \
		write_verilog $(NETLIST_OUT) \
	" > $(SYNTH_LOG) 2>&1; status=$$?; \
	if [ $$status -ne 0 ]; then \
		cat $(SYNTH_LOG); \
		echo ""; \
		echo "ERROR: yosys falló sintetizando '$(SYNTH_TOP)' (ver $(SYNTH_LOG))"; \
		exit 1; \
	fi; \
	if grep "Latch inferred" $(SYNTH_LOG) | grep -qv "^No "; then \
		echo "ERROR: yosys detectó latch(es) no intencionados en '$(SYNTH_TOP)':"; \
		grep "Latch inferred" $(SYNTH_LOG) | grep -v "^No "; \
		exit 1; \
	fi; \
	stat_line=$$(grep -n "Printing statistics" $(SYNTH_LOG) | tail -1 | cut -d: -f1); \
	tail -n +$$stat_line $(SYNTH_LOG)

# Nota: SYNTH_TOP debe ser un módulo instanciable de verdad (ej. top, o cualquier
# módulo hoja como marcador). No sirve para testbenches (tb_*.sv no está en DESIGN_SRCS).
synth: $(NETLIST_OUT)
	@echo "Netlist generado en $(NETLIST_OUT)"

# Linter del sistema completo. Sin SYNTHESIS definido, generador_relojes entra con su modelo de
# simulación, porque verilator no conoce PLLE2_BASE ni BUFG. -Wall muestra también los avisos de
# estilo (anchos, señales sin usar), que no detienen el make. Lo que sí lo detiene es un latch, una
# asignación con retardo en lógica combinacional o una señal con más de un driver.
lint: | $(BUILD_DIR)
	@$(VERILATOR) --lint-only -Wall -Wno-fatal -I$(DESIGN_DIR) --top-module top $(DESIGN_SRCS) > $(LINT_LOG) 2>&1; \
	grep -o "%Warning-[A-Z]*" $(LINT_LOG) | sort | uniq -c; \
	if grep -q "%Error\|%Warning-LATCH\|%Warning-COMBDLY\|%Warning-MULTIDRIVEN\|%Warning-BLKANDNBLK" $(LINT_LOG); then \
		cat $(LINT_LOG); \
		echo "ERROR: verilator encontró latches, drivers múltiples o errores (ver $(LINT_LOG))"; \
		exit 1; \
	fi; \
	echo "Lint sin latches ni drivers múltiples. Detalle en $(LINT_LOG)"

# Simulación del netlist de síntesis: el mismo top.json que va a nextpnr, escrito como Verilog de
# primitivas y simulado con sus modelos y con el de PLLE2_BASE de $(PS_DIR). El testbench solo mira
# pines, porque el netlist ya no tiene jerarquía. Tarda bastante más que la simulación RTL.
$(PS_NETLIST): $(JSON_OUT)
	$(YOSYS) -q -p "read_json $(JSON_OUT); write_verilog -noattr $(PS_NETLIST)"

post-sintesis: $(PS_NETLIST)
	$(IVERILOG) -g2012 -DPOST_SINTESIS -o $(PS_VVP) $(PS_NETLIST) $(CELLS_SIM) $(PS_DIR)/PLLE2_BASE.v \
		$(PS_DIR)/tb_post_sintesis.sv -s tb_post_sintesis
	cd $(BUILD_DIR) && $(VVP) $(notdir $(PS_VVP))

# Falla temprano y con un mensaje claro si falta algo del toolchain openXC7. Se revisa
# todo acá y no a medio camino, porque un paso que falla tarde (típicamente fasm2frames
# por el PYTHONPATH) deja un .bit en blanco que la tarjeta acepta sin quejarse.
check-fpga-toolchain:
	@command -v $(YOSYS) >/dev/null 2>&1 || \
		{ echo "ERROR: '$(YOSYS)' no encontrado. Revisar que OPENXC7=$(OPENXC7) sea la ruta correcta."; exit 1; }
	@command -v $(NEXTPNR_XILINX) >/dev/null 2>&1 || \
		{ echo "ERROR: '$(NEXTPNR_XILINX)' no encontrado. Revisar que OPENXC7=$(OPENXC7) sea la ruta correcta."; exit 1; }
	@command -v $(XC7FRAMES2BIT) >/dev/null 2>&1 || \
		{ echo "ERROR: '$(XC7FRAMES2BIT)' no encontrado. Revisar que OPENXC7=$(OPENXC7) sea la ruta correcta."; exit 1; }
	@[ -f $(CHIPDB) ] || \
		{ echo "ERROR: chipdb no encontrado en $(CHIPDB)"; exit 1; }
	@[ -d $(PRJXRAY_DB_ROOT)/$(PART) ] || \
		{ echo "ERROR: base de datos de prjxray no encontrada en $(PRJXRAY_DB_ROOT)/$(PART)"; exit 1; }
	@$(PYTHON) -c "import fasm, prjxray" 2>/dev/null || \
		{ echo "ERROR: fasm2frames.py no puede importar sus módulos de python."; \
		  echo "       PYTHONPATH actual: $$PYTHONPATH"; \
		  echo "       'fasm' sale de $(OPENXC7)/lib/python y 'prjxray' del repo clonado en PRJXRAY_PY=$(PRJXRAY_PY)."; \
		  echo "       Si prjxray está en otro lado: make bitstream PRJXRAY_PY=/ruta/prjxray"; \
		  exit 1; }

# Bitstream para el Basys3 (XC7A35T, part $(PART)) con el toolchain openXC7 (yosys ->
# nextpnr-xilinx -> fasm2frames -> xc7frames2bit), sin Vivado. Ver src/fpga/basys3.xdc.
$(JSON_OUT): $(DESIGN_SRCS) $(PROG_HEX) $(TOOLCHAIN_STAMP) | $(BUILD_DIR)
	$(YOSYS) -p " \
		read_verilog -sv $(DESIGN_SRCS); \
		synth_xilinx -flatten -abc9 -nobram -arch xc7 -top $(SYNTH_TOP); \
		write_json $(JSON_OUT) \
	"

$(ROUTED_OUT) $(FASM_OUT) &: $(JSON_OUT) $(XDC) $(CHIPDB)
	$(NEXTPNR_XILINX) --chipdb $(CHIPDB) --xdc $(XDC) --json $(JSON_OUT) \
		--write $(ROUTED_OUT) --fasm $(FASM_OUT)

$(FRAMES_OUT): $(FASM_OUT)
	$(FASM2FRAMES) --part $(PART) --db-root $(PRJXRAY_DB_ROOT) $(FASM_OUT) > $(FRAMES_OUT)
	@[ -s $(FRAMES_OUT) ] || \
		{ echo "ERROR: $(FRAMES_OUT) salió vacío, el .bit que saldría de ahí no configura nada."; \
		  rm -f $(FRAMES_OUT); exit 1; }

# velocidad_config.py sube CCLK de ~3 a 33 MHz: sin eso la tarjeta tarda ~6 s en cargar el
# diseño desde la flash después de PROG, y con eso ~0,5 s
$(BIT_OUT): $(FRAMES_OUT) $(VELOCIDAD_CONFIG)
	$(XC7FRAMES2BIT) --part_file $(PRJXRAY_DB_ROOT)/$(PART)/part.yaml --part_name $(PART) \
		--frm_file $(FRAMES_OUT) --output_file $(BIT_OUT)
	$(PYTHON) $(VELOCIDAD_CONFIG) $(BIT_OUT)

bitstream: check-fpga-toolchain $(BIT_OUT)
	@echo "Bitstream generado en $(BIT_OUT)"

# Simulación post-implementación temporizada. Vivado sintetiza, coloca y rutea top igual que para
# una tarjeta, y exporta el netlist en primitivas SIMPRIM con un SDF de los retardos de celdas y
# rutas (vivado_timesim.tcl). xsim corre tb_top_temporizado sobre ese netlist con -maxdelay, los
# retardos del peor caso, y con los chequeos de setup y hold de cada flip-flop. La misma prueba
# corre con make sim TB=top_temporizado sobre el RTL.
#
# Diferencias con la tarjeta: la implementación es la de Vivado y no la de nextpnr-xilinx (nextpnr
# no exporta un netlist que se pueda simular con los modelos de Xilinx), y la UART va a 694444
# baudios para que la partida quepa en una corrida, ver vivado_timesim.tcl.
#
# Los retardos van con el modelo inercial, el de xelab por defecto: un pulso más corto que el
# retardo de la celda no pasa. Con -transport_int_delays y -pulse_r 0 pasa cada glitch de la ROM,
# que es un árbol de LUTs, y la simulación va 3 veces más lenta. Aun así toma cerca de una hora.
check-vivado:
	@[ -x $(VIVADO_BIN)/vivado ] || \
		{ echo "ERROR: no está Vivado en $(VIVADO_BIN). Pasar la ruta con make sim-post XILINX_VIVADO=/ruta/Vivado"; exit 1; }

# Vivado escribe en el log si leyó el .hex de la ROM, pero si no lo encuentra solo avisa y la ROM
# queda en cero, así que eso se revisa aquí
$(TIMESIM_NET): $(DESIGN_SRCS) $(PROG_HEX) $(XDC) $(TIMESIM_TCL) | $(BUILD_DIR)
	@mkdir -p $(TIMESIM_DIR)
	$(VIVADO_BIN)/vivado -mode batch -nojournal -log $(TIMESIM_DIR)/vivado.log \
		-source $(TIMESIM_TCL) -tclargs $(TIMESIM_DIR) > /dev/null || \
		{ grep -E "^(ERROR|CRITICAL)" $(TIMESIM_DIR)/vivado.log; exit 1; }
	@grep -q "readmem data file '$(PROG_HEX)' is read successfully" $(TIMESIM_DIR)/vivado.log || \
		{ echo "ERROR: Vivado no leyó $(PROG_HEX) para la ROM, ver $(TIMESIM_DIR)/vivado.log"; rm -f $@; exit 1; }
	@grep "^WNS de setup" $(TIMESIM_DIR)/vivado.log

# xvlog y xelab corren dentro de $(TIMESIM_DIR) porque el $$sdf_annotate del netlist busca
# top_timesim.sdf en la carpeta actual. xsim no devuelve error cuando la prueba llama $$fatal, por
# eso el resultado sale del log que escribe xsim
sim-post: check-vivado $(TIMESIM_NET)
	cd $(TIMESIM_DIR) && \
		$(VIVADO_BIN)/xvlog $(XILINX_VIVADO)/data/verilog/src/glbl.v top_timesim.v > xvlog.log && \
		$(VIVADO_BIN)/xvlog -sv -d POST_IMPL $(CURDIR)/$(TIMESIM_TB) >> xvlog.log && \
		$(XSIM_ENV) $(VIVADO_BIN)/xelab -L simprims_ver -L secureip -maxdelay -mt auto \
			-s tb_top_temporizado work.tb_top_temporizado work.glbl > xelab.log || \
		{ grep -E "ERROR|cannot find" $(TIMESIM_DIR)/xvlog.log $(TIMESIM_DIR)/xelab.log; exit 1; }
	cd $(TIMESIM_DIR) && $(XSIM_ENV) $(VIVADO_BIN)/xsim tb_top_temporizado -R -log xsim.log | \
		grep -E "^(ok|fallo|  )|pruebas,|Fatal|FATAL" || true
	@grep -q "pruebas, 0 fallos" $(TIMESIM_DIR)/xsim.log || \
		{ echo "ERROR: la simulación temporizada falló, ver $(TIMESIM_DIR)/xsim.log"; exit 1; }
	@echo "Onda del arranque y del disparo del Jugador 1 en $(TIMESIM_DIR)/tb_top_temporizado.vcd"

# Diagnóstico de conectividad antes de programar: revisa que openFPGALoader esté
# en PATH, que la Basys3 aparezca en el bus USB, y que se pueda hablar JTAG con
# ella. En FreeBSD el chip FT2232 de la Basys3 suele quedar acaparado por el
# driver de puerto serie uftdi(4), que le bloquea el acceso exclusivo a
# libusb/openFPGALoader -- este target lo detecta y avisa, no lo descarga solo
# (kldunload necesita root y es una acción del sistema, no del build).
connect: | $(BUILD_DIR)
	@echo "== make connect: verificando acceso a la Basys3 =="
	@command -v $(OPENFPGALOADER) >/dev/null 2>&1 || \
		{ echo "ERROR: '$(OPENFPGALOADER)' no encontrado en PATH."; exit 1; }
	@case "$$(uname)" in \
		FreeBSD) \
			if command -v usbconfig >/dev/null 2>&1; then \
				if ! $(PRIV) usbconfig list 2>/dev/null | grep -qi "FT2232"; then \
					echo "ERROR: no se detecta el chip FT2232 (Basys3) en el bus USB (usbconfig list)."; \
					echo "       revisá el cable (debe ser de datos, no solo carga), el puerto usado,"; \
					echo "       y que el switch de encendido (SW16) de la tarjeta esté en ON."; \
					exit 1; \
				fi; \
				echo "OK: Basys3 (FT2232) detectada en el bus USB."; \
			fi; \
			if command -v kldstat >/dev/null 2>&1 && kldstat -q -m uftdi 2>/dev/null; then \
				echo "AVISO: el módulo uftdi está cargado y puede acaparar el FT2232 antes que"; \
				echo "       libusb/openFPGALoader -- si el chequeo de JTAG de abajo falla, corré:"; \
				echo "         $(PRIV) kldunload uftdi"; \
				echo "       y volvé a conectar el cable USB de la Basys3 antes de reintentar."; \
			fi ;; \
		*) \
			if command -v lsusb >/dev/null 2>&1 && ! lsusb 2>/dev/null | grep -qi "FTDI\|Future Technology"; then \
				echo "ERROR: no se detecta el chip FTDI (Basys3) en lsusb."; \
				exit 1; \
			fi; \
			for iface in /sys/bus/usb/devices/*:1.0; do \
				dev=$${iface%%:*}; \
				[ "$$(cat $$dev/idVendor 2>/dev/null)$$(cat $$dev/idProduct 2>/dev/null)" = "04036010" ] || continue; \
				[ "$$(basename $$(readlink -f $$iface/driver 2>/dev/null) 2>/dev/null)" = usbfs ] || continue; \
				echo "AVISO: la interfaz JTAG del FT2232 ya está tomada por otro proceso (driver usbfs)."; \
				if command -v lsof >/dev/null 2>&1; then \
					lsof /dev/bus/usb/$$(printf %03d $$(cat $$dev/busnum))/$$(printf %03d $$(cat $$dev/devnum)) \
						2>/dev/null | tail -n +2 | awk '{print "       lo tiene " $$1 " (PID " $$2 ")"}'; \
				fi; \
				echo "       Casi siempre es el hw_server de Vivado: cerrá el Hardware Manager, o corré"; \
				echo "         pkill hw_server"; \
				echo "       y reintentá. La interfaz de UART (/dev/ttyUSB*) no estorba, esa es otra."; \
			done ;; \
	esac
	@if ! $(PRIV) $(OPENFPGALOADER) --detect > $(BUILD_DIR)/.connect.log 2>&1; then \
		echo "ERROR: openFPGALoader no logra hablar JTAG con la tarjeta:"; \
		cat $(BUILD_DIR)/.connect.log; \
		echo ""; \
		echo "Si el chip sí aparece en el bus pero esto falla, es porque alguien más tiene tomada la"; \
		echo "interfaz JTAG: en Linux casi siempre el hw_server de Vivado, en FreeBSD el driver uftdi."; \
		echo "Mirá el AVISO de arriba, ahí va el proceso concreto cuando se puede averiguar."; \
		exit 1; \
	fi
	@echo "OK: openFPGALoader detecta la FPGA por JTAG. Todo listo para 'make program' / 'make all'."

# Si no se pidió un .bit específico con BIT=, se reconstruye $(BIT_OUT) antes de cargarlo,
# para no terminar programando un bitstream viejo de una versión anterior del RTL.
#
# Los dos prerequisitos van en una sola regla y en este orden a propósito: primero compilar
# (un error de síntesis se ve sin necesidad de tener la tarjeta conectada) y de último el
# chequeo de JTAG, que así queda justo antes de programar. Partirlo en dos reglas no sirve,
# make corre primero los prerequisitos de la regla que trae la receta, sin importar el orden
# en que estén escritas.
PROGRAM_DEPS := connect
ifeq ($(BIT),$(BIT_OUT))
PROGRAM_DEPS := bitstream connect
endif

program: $(PROGRAM_DEPS)
	$(PRIV) $(OPENFPGALOADER) -b $(BOARD) $(BIT)

# make program deja el diseño solo en la SRAM de la FPGA y PROG lo borra, y como el reinicio general del proyecto es PROG el bitstream tiene que estar en la flash
flash: $(PROGRAM_DEPS)
	$(PRIV) $(OPENFPGALOADER) -b $(BOARD) -f $(BIT)

# Terminal interactiva, busca la tarjeta sola si no se pasa PUERTO
app:
	$(PYTHON) $(APP_DIR)/batalla_pc.py $(if $(PUERTO),-p $(PUERTO))

test: check-tb # <-- Esto corre make sim para cada testbench en $(TBS), uno por uno
	@estado=0; \
	for modulo in $(TBS); do \
		echo "--> $$modulo"; \
		$(MAKE) --no-print-directory sim TB=$$modulo || estado=1; \
	done; \
	exit $$estado

# -t $(APP_DIR) es lo que deja importar los modulos sin paquete, igual que cuando corre la app
test-app:
	$(PYTHON) -m unittest discover -s $(APP_DIR)/pruebas -t $(APP_DIR)

clean:
	rm -rf $(BUILD_DIR)
