# uart.sh, se corre desde la raíz del repo y regenera los esquemáticos de la UART, incluidos los tres módulos del Proyecto 2 que ya no se instancian
set -e
D=$(dirname "$(readlink -f "$0")"); R=$(pwd); T=$(mktemp -d); cd $T
# anchos reducidos solo para que el dibujo se pueda leer, los docs lo aclaran
sed -e 's/^  int cuenta_tick;/  logic [1:0] cuenta_tick;/' -e 's/\[7:0\]/[1:0]/g' -e 's/logic \[2:0\] indice;/logic [0:0] indice;/' -e "s/3'd0/1'd0/" -e "s/indice == 3'd7/indice == 1'd1/" "$R"/src/design/uart_tx.sv > uart_tx.sv
sed -e 's/^  int cuenta_tick;/  logic [1:0] cuenta_tick;/' -e 's/^  int cuenta_bit;/  logic [3:0] cuenta_bit;/' -e 's/^  int indice_bit;/  logic [0:0] indice_bit;/' -e 's/\[7:0\]/[1:0]/g' -e "s/8'h00/2'h0/g" -e 's/indice_bit == 7/indice_bit == 1/' "$R"/src/design/uart_rx.sv > uart_rx.sv
sed 's/localparam int BYTE_WIDTH = 8;/localparam int BYTE_WIDTH = 2;/' "$R"/src/design/periferico_uart.sv > periferico_uart.sv
cat > cajas.sv <<'V'
(* blackbox *) module uart_tx #(parameter TICKS_BIT = 868) (input logic clk, rst, i_enviar, input logic [1:0] i_dato, output logic o_listo, o_tx);
endmodule
(* blackbox *) module uart_rx #(parameter TICKS_X16 = 54) (input logic clk, rst, i_rx, output logic o_dato_listo, output logic [1:0] o_dato);
endmodule
V
bash "$D/sintetizar.sh" uart_tx uart_tx.sv "-set TICKS_BIT 4" FSM DIVISOR:28-41 CAPTURA:44-50 CONT_INDICE:53-56 FSM:58-96 DETECTOR_FIN:99-108
bash "$D/sintetizar.sh" uart_rx uart_rx.sv "-set TICKS_X16 4" FSM DIVISOR:26-39 FSM:41-90 DETECTOR_FIN:93-102
EXTRA=cajas.sv bash "$D/sintetizar.sh" periferico_uart periferico_uart.sv "-set WIDTH 4" "" REG_DATOS_TX:50-53 REG_DATOS_RX:55-59 REG_CONTROL:61-72 MUX_RD:74-81
cp "$R"/src/design/arbitro_uart.sv "$R"/src/design/receptor_uart.sv .
# sin mem2reg yosys deja reg_trama como memoria y no la baja a flip-flops
sed -e "s/reg_len - 1/reg_len - 3'd1/" -e 's/^  logic \[BYTE_WIDTH-1:0\] reg_trama \[0:4\];/  (* mem2reg *) logic [BYTE_WIDTH-1:0] reg_trama [0:4];/' "$R"/src/design/transmisor_uart.sv > transmisor_uart.sv
bash "$D/sintetizar.sh" arbitro_uart arbitro_uart.sv "-set WIDTH 4" "" PETICION:31-34 RECOMP_CTRL:37-40 MUX_BUS:45-63 MUX_RDATA:66-67
bash "$D/sintetizar.sh" receptor_uart receptor_uart.sv "-set WIDTH 8" FSM_BUS FILTRO:29-30 FSM_BUS:33-53 SALIDAS:56-64
bash "$D/sintetizar.sh" transmisor_uart transmisor_uart.sv "-set WIDTH 8 -set WORD_MAXLEN 4" "PENDIENTES FSM" DETECTOR:48-63 PENDIENTES:78-120 FSM:132-149 CNT_BYTE:151-155 CARGA_TRAMA:158-181 SALIDAS:184-201
for t in periferico_uart uart_tx uart_rx arbitro_uart receptor_uart transmisor_uart; do bash "$D/componer.sh" $t.all.json $t "$R/docs/diseño/diagramas/$t.png"; done
rm -rf $T
