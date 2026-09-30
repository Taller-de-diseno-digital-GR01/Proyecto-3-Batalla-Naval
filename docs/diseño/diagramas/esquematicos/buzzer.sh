# buzzer.sh, se corre desde la raíz del repo y regenera los esquemáticos de PERIFERICO_BUZZER, secuenciador_melodia y generador_tono
set -e
D=$(dirname "$(readlink -f "$0")"); R=$(pwd); T=$(mktemp -d); cd $T
# anchos reducidos solo para que el dibujo se pueda leer, los docs lo aclaran
sed 's/\[17:0\]/[3:0]/g' "$R"/src/design/periferico_buzzer.sv > periferico_buzzer.sv
sed 's/\[17:0\]/[3:0]/g' "$R"/src/design/secuenciador_melodia.sv > secuenciador_melodia.sv
cp "$R"/src/design/generador_tono.sv .
# proc a secas convierte los case de constantes en una ROM $mem y el dibujo queda sin compuertas
sed -e 's/proc;/proc -norom;/' -e "s|^D=.*|D=\"$D\"|" "$D/sintetizar.sh" > sintetizar_norom.sh
cat > cajas.sv <<'V'
(* blackbox *) module secuenciador_melodia #(parameter CLK_FREQ_HZ = 100_000_000, parameter UNIDAD_MS = 50) (input logic clk, rst, i_iniciar, input logic [2:0] i_sonido, output logic [3:0] o_n, output logic o_sonar, o_fin);
endmodule
(* blackbox *) module generador_tono #(parameter ANCHO_N = 18) (input logic clk, rst, input logic [3:0] i_n, input logic i_sonar, output logic o_sound);
endmodule
V
EXTRA=cajas.sv bash "$D/sintetizar.sh" periferico_buzzer periferico_buzzer.sv "-set WIDTH 4" "" DECOD_DIR:22-22 REG_SONIDO:43-47 MUX_RD:49-54
bash sintetizar_norom.sh secuenciador_melodia secuenciador_melodia.sv "-set CLK_FREQ_HZ 4000 -set UNIDAD_MS 1" CONTADORES ROM_MELODIAS:56-91 ROM_NOTAS:93-107 FIN_NOTA:109-110 CONTADORES:113-133 SALIDAS:135-136
bash "$D/sintetizar.sh" generador_tono generador_tono.sv "-set ANCHO_N 3" "" REG_ONDA:32-36
# u_cont y u_cmp ya son módulos en el .sv, se renombran para que componer.sh los abra debajo del top
python3 - generador_tono.all.json <<'P'
import json, re, sys
p = sys.argv[1]; d = json.load(open(p))
ren = lambda s: re.sub(r"^\$paramod\\([^\\]+)\\.*$", r"generador_tono_\1", s)
d['modules'] = {ren(k): v for k, v in d['modules'].items()}
for v in d['modules'].values():
    for c in v.get('cells', {}).values(): c['type'] = ren(c['type'])
json.dump(d, open(p, 'w'))
P
for t in periferico_buzzer secuenciador_melodia generador_tono; do bash "$D/componer.sh" $t.all.json $t "$R/docs/diseño/diagramas/$t.png"; done
rm -rf $T
