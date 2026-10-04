DESIGN_DIR := src/design
SIM_DIR    := src/sim
BUILD_DIR  := src/build

IVERILOG       := iverilog
IVERILOG_FLAGS := -g2012
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

APP_DIR    := sw
PYTHON     := python3

DESIGN_SRCS := $(wildcard $(DESIGN_DIR)/*.sv)
TB_SRCS     := $(wildcard $(SIM_DIR)/tb_*.sv)
TBS         := $(patsubst $(SIM_DIR)/tb_%.sv,%,$(TB_SRCS))

TB ?= $(firstword $(TBS))
SYNTH_TOP ?= top

VVP_OUT := $(BUILD_DIR)/tb_$(TB).vvp
VCD_OUT := $(BUILD_DIR)/tb_$(TB).vcd
SVG_OUT := $(or $(SVG),$(BUILD_DIR)/tb_$(TB).svg)
RECORTE_OUT := $(BUILD_DIR)/tb_$(TB)_recorte.vcd

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

.PHONY: all help list sim wave dump test test-app synth bitstream program connect app clean check-tb check-fpga-toolchain FORCE

# Si una receta falla, borra el archivo que estaba generando. Sin esto un paso que
# escribe con redirección (ej. fasm2frames > top.frames) deja un archivo vacío que
# make da por hecho la próxima vez, y el .bit sale en blanco sin avisar.
.DELETE_ON_ERROR:

all: bitstream program app

help:
	@echo "make all                genera el bitstream, lo carga a la FPGA, y abre la app de PC (bitstream + program + app)"
	@echo "make list              lista los testbenches disponibles"
	@echo "make sim  TB=<modulo>  compila y corre src/sim/tb_<modulo>.sv"
	@echo "make wave TB=<modulo>  corre la simulación y abre GTKWave"
	@echo "make dump TB=<modulo> SIGS=sig1,sig2,...  corre la simulación y exporta un SVG con vecdump"
	@echo "                        DESDE=/HASTA= recortan la ventana (unidades del timescale), SVG= cambia la salida"
	@echo "make test"
	@echo "make test-app           corre las pruebas de la app de PC con unittest, no necesita la tarjeta"
	@echo "make synth SYNTH_TOP=<modulo>  sintetiza con yosys (genérico) y revisa que no haya latches inferidos"
	@echo "make bitstream          genera $(BIT_OUT) con yosys + nextpnr-xilinx + prjxray (openXC7, sin Vivado)"
	@echo "                        toma el toolchain de OPENXC7=$(OPENXC7) y PRJXRAY_PY=$(PRJXRAY_PY), no hace falta"
	@echo "                        correr 'source .../export.sh' antes"
	@echo "make program            reconstruye el bitstream si hace falta y lo carga al Basys3 con openFPGALoader"
	@echo "make program BIT=<archivo.bit>  carga ese .bit tal cual, sin reconstruir nada"
	@echo "make connect             verifica que la Basys3 esté detectable por USB/JTAG antes de programar"
	@echo "make app                 corre la app de PC del Jugador 2 (Batalla Naval por UART)"
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
	$(error Uso, make dump TB=<modulo> SIGS=sig1,sig2,...  ej. make dump TB=periferico_vga SIGS=clk_pix_tb,hsync_tb,vsync_tb)
endif
ifneq ($(strip $(DESDE)$(HASTA)),)
	$(PYTHON) $(SIM_DIR)/recortar_vcd.py $(VCD_OUT) $(RECORTE_OUT) $(or $(DESDE),0) $(or $(HASTA),999999999999999999)
	$(VECDUMP) $(RECORTE_OUT) -s $(SIGS) -o $(SVG_OUT)
else
	$(VECDUMP) $(VCD_OUT) -s $(SIGS) -o $(SVG_OUT)
endif
	@awk 'NR==1{print; print "<rect width=\"100%\" height=\"100%\" fill=\"#fff\"/>"; next} 1' $(SVG_OUT) > $(SVG_OUT).tmp && mv $(SVG_OUT).tmp $(SVG_OUT)
	@echo ".svg generado en $(SVG_OUT)"

# Ej:
# make dump TB=periferico_vga SIGS=clk_pix_tb,rst_tb,hsync_tb,vsync_tb
# Hay que conocer las señales que se quieren ver, eso es lo único malo.
# vecdump dibuja la simulación entera; para ver solo un tramo se recorta el VCD con
# DESDE/HASTA, en unidades del timescale del VCD (ps con Icarus), y SVG= cambia la salida:
# make dump TB=periferico_vga SIGS=clk_pix_tb,hsync_tb DESDE=0 HASTA=40000000 SVG=docs/informe/img/hsync.svg
# vecdump deja el fondo transparente y en el modo oscuro de GitHub no se ven las líneas negras,
# por eso el awk le mete un rectángulo blanco justo después de la etiqueta <svg>.

$(NETLIST_OUT): $(DESIGN_SRCS) $(TOOLCHAIN_STAMP) | $(BUILD_DIR)
	@$(YOSYS) -p " \
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
# módulo hoja como periferico_vga). No sirve para testbenches (tb_*.sv no está en DESIGN_SRCS).
synth: $(NETLIST_OUT)
	@echo "Netlist generado en $(NETLIST_OUT)"

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
	@[ -f $(XDC) ] || \
		{ echo "ERROR: falta $(XDC), sin las restricciones de pines no se puede rutear."; exit 1; }
	@[ -f $(CHIPDB) ] || \
		{ echo "ERROR: chipdb no encontrado en $(CHIPDB) (revisar la instalación de openXC7)"; exit 1; }
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
$(JSON_OUT): $(DESIGN_SRCS) $(TOOLCHAIN_STAMP) | $(BUILD_DIR)
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

$(BIT_OUT): $(FRAMES_OUT)
	$(XC7FRAMES2BIT) --part_file $(PRJXRAY_DB_ROOT)/$(PART)/part.yaml --part_name $(PART) \
		--frm_file $(FRAMES_OUT) --output_file $(BIT_OUT)

bitstream: check-fpga-toolchain $(BIT_OUT)
	@echo "Bitstream generado en $(BIT_OUT)"

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

# Terminal interactiva, busca la tarjeta sola si no se pasa PUERTO. El nombre del script
# todavía no está definido, se cambia aquí o con make app APP_MAIN=<archivo>
APP_MAIN ?= $(APP_DIR)/batalla_naval_pc.py

app:
	@[ -f $(APP_MAIN) ] || \
		{ echo "ERROR: no existe $(APP_MAIN). Se puede indicar otro con make app APP_MAIN=<archivo>"; exit 1; }
	$(PYTHON) $(APP_MAIN) $(if $(PUERTO),-p $(PUERTO))

test: check-tb # <-- Esto corre make sim para cada testbench en $(TBS), uno por uno
	@estado=0; \
	for modulo in $(TBS); do \
		echo "--> $$modulo"; \
		$(MAKE) --no-print-directory sim TB=$$modulo || estado=1; \
	done; \
	exit $$estado

# -t $(APP_DIR) es lo que deja importar los modulos sin paquete, igual que cuando corre la app
test-app:
	@[ -d $(APP_DIR)/pruebas ] || \
		{ echo "ERROR: no existe $(APP_DIR)/pruebas, la app de PC todavía no tiene pruebas."; exit 1; }
	$(PYTHON) -m unittest discover -s $(APP_DIR)/pruebas -t $(APP_DIR)

clean:
	rm -rf $(BUILD_DIR)
