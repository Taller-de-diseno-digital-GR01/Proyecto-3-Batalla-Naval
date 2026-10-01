#!/usr/bin/env bash
# ensamblar.sh
# Ensambla un programa rv32i para la ROM del Proyecto 3 con binutils de GNU.
#
# Uso:    bash sw/ensamblar.sh sw/<nombre>.s
# Genera: sw/build/<nombre>.o    objeto del ensamblador
#         sw/build/<nombre>.elf  ejecutable enlazado en 0x0000_0000
#         sw/build/<nombre>.lst  desensamblado, para depurar
#         sw/<nombre>.hex        imagen de la ROM para $readmemh
#
# El programa tiene que declarar ".globl INICIO" y empezar en esa etiqueta.
# Solo la seccion .text pasa a la ROM.

set -e    # cortar en el primer comando que falle

if [ $# -ne 1 ]; then
    echo "Uso: bash sw/ensamblar.sh sw/<nombre>.s"
    exit 1
fi

FUENTE="$1"
NOMBRE=$(basename "$FUENTE" .s)
DIR=$(dirname "$FUENTE")
BUILD="$DIR/build"
P=riscv64-unknown-elf

# Lista base del instructivo. El instructivo escribe "sltui", el nombre real es sltiu.
PERMITIDAS='lw|sw|sll|slli|srl|srli|sra|srai|add|and|xor|or|sub|addi|andi|xori|ori|beq|bne|blt|bge|slt|slti|sltu|sltiu|jal|jalr'

mkdir -p "$BUILD"

# 1. Ensamblar.
$P-as -march=rv32i -mabi=ilp32 -o "$BUILD/$NOMBRE.o" "$FUENTE"

# 2. Enlazar. --fatal-warnings convierte en error, por ejemplo, olvidar ".globl INICIO".
$P-ld -m elf32lriscv -Ttext=0 --no-relax -e INICIO --fatal-warnings \
      -o "$BUILD/$NOMBRE.elf" "$BUILD/$NOMBRE.o"

# 3. Desensamblar a un listado.
$P-objdump -d -M no-aliases "$BUILD/$NOMBRE.elf" > "$BUILD/$NOMBRE.lst"

# 4. Chequear que todas las instrucciones esten en la lista base.
#    Imprime la linea completa (direccion incluida) de cada instruccion prohibida.
PROHIBIDAS=$(awk -v ok="^($PERMITIDAS)$" '/^ +[0-9a-f]+:/ && $3 !~ ok' "$BUILD/$NOMBRE.lst")
if [ -n "$PROHIBIDAS" ]; then
    echo "ERROR: instrucciones fuera de la lista base del nucleo:"
    echo "$PROHIBIDAS"
    exit 1
fi

# 5. Generar la imagen de la ROM, una instruccion de 32 bits por palabra.
$P-objcopy -O verilog --verilog-data-width=4 -j .text "$BUILD/$NOMBRE.elf" "$DIR/$NOMBRE.hex"

echo "OK: $DIR/$NOMBRE.hex ($(grep -c '^ \+[0-9a-f]\+:' "$BUILD/$NOMBRE.lst") instrucciones)"
