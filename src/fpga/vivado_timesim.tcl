# vivado_timesim.tcl
# Implementa top con Vivado y exporta el netlist ruteado con sus retardos, para la simulacion
# post-implementacion temporizada (make sim-post). El bitstream de la tarjeta sigue saliendo de
# openXC7 (make bitstream), Vivado se usa solo para esto: nextpnr-xilinx no exporta un netlist
# que se pueda simular con los modelos de Xilinx.
#
# Uso, desde la raiz del repo:
#   vivado -mode batch -source src/fpga/vivado_timesim.tcl -tclargs <carpeta de salida>
#
# Deja en la carpeta de salida:
#   top_timesim.v        netlist post-implementacion en primitivas SIMPRIM
#   top_timesim.sdf      retardos de celdas y rutas, lo carga el $sdf_annotate del netlist
#   top_timing.rpt       resumen de timing, el WNS de cada reloj
#   top_utilizacion.rpt  recursos usados

set salida [lindex $argv 0]
file mkdir $salida

set part xc7a35tcpg236-1

# Todos los .sv de src/design, como en make bitstream: con -top top los que no cuelgan de top
# (prueba_vga.sv) se descartan. -include_dirs es por los `include "config.sv" del nucleo RISC-V
set fuentes [lsort [glob src/design/*.sv]]
read_verilog -sv $fuentes
read_xdc src/fpga/basys3.xdc

# La ROM lee sw/programa.hex con $readmemh, relativo a la raiz del repo, desde donde corre Vivado.
# Si no lo encuentra solo avisa y la ROM queda vacia, el Makefile revisa eso en el log. Vivado
# define SYNTHESIS igual que yosys, asi que generador_relojes.sv usa el PLLE2_BASE
#
# BAUDIOS sube la UART de 115200 a 694444 baudios (TICKS_BIT = 48 y TICKS_X16 = 3 con clk_sys de
# 33,33 MHz, 16 * 3 = 48 asi que el receptor no acumula error). Es lo unico que cambia frente al
# diseno de la tarjeta: xsim avanza menos de 1 us de simulacion por segundo, y a 115200 cada trama
# de 5 bytes son 434 us
synth_design -top top -part $part -include_dirs src/design -generic BAUDIOS=694444

opt_design
place_design
route_design

report_timing_summary -file $salida/top_timing.rpt
report_utilization -file $salida/top_utilizacion.rpt

# El WNS negativo se avisa pero no se corta: la simulacion temporizada es justo para ver que pasa
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS de setup: $wns ns"

write_verilog -mode timesim -sdf_anno true -force $salida/top_timesim.v
write_sdf -mode timesim -force $salida/top_timesim.sdf
