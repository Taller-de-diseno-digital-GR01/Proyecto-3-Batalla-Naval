# led.sh, se corre desde la raíz del repo y regenera el esquemático de PERIFERICO_LED
set -e
D=$(dirname "$(readlink -f "$0")"); R=$(pwd); T=$(mktemp -d); cd $T
cp "$R"/src/design/periferico_led.sv .
# bus de 4 bits solo para que el dibujo se pueda leer, el doc lo aclara
bash "$D/sintetizar.sh" periferico_led periferico_led.sv "-set WIDTH 4" "" DECOD_DIR:19-19 REG_LEDS:22-25 MUX_RD:29-34
bash "$D/componer.sh" periferico_led.all.json periferico_led "$R/docs/diseño/diagramas/periferico_led.png"
rm -rf $T
