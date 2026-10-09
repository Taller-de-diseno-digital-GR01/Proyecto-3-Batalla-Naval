# entradas.sh, se corre desde la raíz del repo y regenera el esquemático de PERIFERICO_ENTRADAS
set -e
D=$(dirname "$(readlink -f "$0")"); R=$(pwd); T=$(mktemp -d); cd $T
cp "$R"/src/design/periferico_entradas.sv .
# bus de 8 bits solo para que el dibujo se pueda leer, los siete botones no cambian
bash "$D/sintetizar.sh" periferico_entradas periferico_entradas.sv "-set WIDTH 8" "" REG_ESTADO:18-21 MUX_RD:23-28
bash "$D/componer.sh" periferico_entradas.all.json periferico_entradas "$R/docs/diseño/diagramas/periferico_entradas.png"
rm -rf $T
