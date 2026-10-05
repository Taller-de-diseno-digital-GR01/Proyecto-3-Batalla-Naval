#!/usr/bin/env bash
# armar.sh
# Genera las imágenes .hex de las pruebas oficiales rv32ui para tb_procesador_uniciclo.sv.
#
# Uso:    bash src/sim/riscv-tests/armar.sh
# Genera: src/sim/riscv-tests/<prueba>.text.hex  código, para la ROM
#         src/sim/riscv-tests/<prueba>.data.hex  datos, para la RAM (solo si la prueba tiene)
#
# Los .hex van versionados, así que este script solo hace falta si cambia una prueba.
# Necesita cpp (el preprocesador de C de Ubuntu) y binutils de GNU para RISC-V. No hace falta
# el gcc de RISC-V: cpp expande las macros de los .S y as ensambla.

set -e    # cortar en el primer comando que falle

DIR=$(cd "$(dirname "$0")" && pwd)
P=riscv64-unknown-elf
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PRUEBAS="lw sw lui add addi and andi or ori xor xori sub sll slli srl srli sra srai
         slt slti sltu sltiu beq bne blt bge jal jalr simple"

for t in $PRUEBAS; do
    # 1. Expandir las macros. __riscv_xlen lo define el gcc de RISC-V, acá va a mano
    cpp -x assembler-with-cpp -P -D__riscv_xlen=32 -I "$DIR" "$DIR/$t.S" > "$TMP/$t.s"

    # 2. Ensamblar y enlazar con el mapa del proyecto
    $P-as -march=rv32i -mabi=ilp32 -o "$TMP/$t.o" "$TMP/$t.s"
    $P-ld -m elf32lriscv -T "$DIR/link.ld" --no-relax -o "$TMP/$t.elf" "$TMP/$t.o"

    # 3. Código y datos por separado, una palabra de 32 bits por posición.
    #    Los datos se corren a 0 para cargarlos desde la primera palabra de la RAM
    $P-objcopy -O verilog --verilog-data-width=4 -j .text "$TMP/$t.elf" "$DIR/$t.text.hex"
    $P-objcopy -O verilog --verilog-data-width=4 -j .data --change-addresses -0x2000 \
               "$TMP/$t.elf" "$DIR/$t.data.hex"

    # La mayoría de las pruebas no tiene datos y el .data.hex sale vacío. No se guarda:
    # el testbench solo carga la RAM si el archivo existe y tiene contenido
    [ -s "$DIR/$t.data.hex" ] || rm "$DIR/$t.data.hex"

    echo "OK: $t"
done
