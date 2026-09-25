# uart.sh, se corre desde la raíz del repo y regenera periferico_uart.png, uart_tx.png y uart_rx.png
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
for t in periferico_uart uart_tx uart_rx; do bash "$D/componer.sh" $t.all.json $t "$R/docs/diseño/diagramas/$t.png"; done
rm -rf $T
