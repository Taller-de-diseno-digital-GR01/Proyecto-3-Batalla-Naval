# 7seg.sh, se corre desde la raíz del repo y regenera los esquemáticos de PERIFERICO_7SEG y marcador
set -e
D=$(dirname "$(readlink -f "$0")"); R=$(pwd); T=$(mktemp -d); cd $T
# registro de 6 bits en vez de 20 solo para que el dibujo se pueda leer, un nibble de dígito y dos puntos
sed -e 's/ANCHO_DIGITOS = 20;/ANCHO_DIGITOS = 6;/' -e 's/reg_digitos\[15:0\]/reg_digitos[3:0]/' -e 's/reg_digitos\[19:16\]/reg_digitos[5:4]/' "$R"/src/design/periferico_7seg.sv > periferico_7seg.sv
cp "$R"/src/design/marcador.sv .
# proc a secas convierte los case de constantes en una ROM $mem y el dibujo queda sin compuertas
sed -e 's/proc;/proc -norom;/' -e "s|^D=.*|D=\"$D\"|" "$D/sintetizar.sh" > sintetizar_norom.sh
cat > cajas.sv <<'V'
(* blackbox *) module marcador #(parameter REFRESH_BITS = 18) (input logic clk, rst, input logic [3:0] i_digitos, input logic [1:0] i_puntos, output logic [6:0] o_seg, output logic [3:0] o_an, output logic o_dp);
endmodule
V
# el contador de refresco se dibuja de 4 bits
EXTRA=cajas.sv bash "$D/sintetizar.sh" periferico_7seg periferico_7seg.sv "-set WIDTH 8" "" DECOD_DIR:32-32 REG_DIGITOS:35-38 MUX_RD:40-45
bash sintetizar_norom.sh marcador marcador.sv "-set REFRESH_BITS 4" "" CONT_REFRESCO:18-23 SELECTOR_DIGITO:25-50 DECOD_BCD_7SEG:52-66
for t in periferico_7seg marcador; do bash "$D/componer.sh" $t.all.json $t "$R/docs/diseño/diagramas/$t.png"; done
rm -rf $T
