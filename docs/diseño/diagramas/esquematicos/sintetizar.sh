# sintetizar.sh top archivo.sv "chparam" "grupos_fsm" BLOQUE:ini-fin ... deja top.all.json con un submódulo por bloque, EXTRA agrega archivos (cajas negras)
D=$(dirname "$(readlink -f "$0")")
top=$1; sv=$2; cp=$3; conos=$4; shift 4
yosys -q -p "read_verilog -sv $sv $EXTRA; ${cp:+chparam $cp $top;} hierarchy -top $top; proc; opt_merge; write_json pre.json"
python3 "$D/agrupar.py" pre.json $top $sv "$@"
for g in $conos; do python3 "$D/conos.py" pre.json $top $g; done
# keep evita que abc se trague las señales con nombre
yosys -q -p "read_json pre.json; ${EXTRA:+read_verilog -sv $EXTRA;} hierarchy -top $top; submod; setattr -set keep 1 w:[a-zA-Z]*; opt; wreduce; opt; techmap; opt -fast; dfflegalize -cell \$_DFF_P_ x; abc -g AND,OR,XOR,MUX; opt_clean; write_json $top.all.json" 2>&1 | grep -v combinational
