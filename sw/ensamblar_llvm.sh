#!/usr/bin/env bash
# ensamblar_llvm.sh
# Igual que ensamblar.sh pero con LLVM, para las máquinas que no tienen binutils de GNU para RISC-V
# (en Ubuntu basta con el paquete llvm). Con el mismo programa da el mismo .hex palabra por palabra.
#
# Uso:    bash sw/ensamblar_llvm.sh sw/<nombre>.s
# Genera: sw/build/<nombre>.o    objeto del ensamblador
#         sw/build/<nombre>.lst  desensamblado, para depurar
#         sw/<nombre>.hex        imagen de la ROM para $readmemh
#
# No hace falta enlazar: el programa es un solo archivo, todo en .text, y sin relajación
# (-relax) llvm-mc resuelve los saltos dentro del mismo objeto. Si quedara alguna relocación
# (una etiqueta que no existe, por ejemplo) el script lo rechaza.

set -e    # cortar en el primer comando que falle

if [ $# -ne 1 ]; then
    echo "Uso: bash sw/ensamblar_llvm.sh sw/<nombre>.s"
    exit 1
fi

FUENTE="$1"
NOMBRE=$(basename "$FUENTE" .s)
DIR=$(dirname "$FUENTE")
BUILD="$DIR/build"

# Acepta llvm-mc o llvm-mc-<versión>, como los instala Ubuntu
buscar() {
    for h in "$1" "$1"-{21,20,19,18,17,16,15,14}; do
        command -v "$h" >/dev/null 2>&1 && { echo "$h"; return; }
    done
    echo "ERROR: no se encontró $1" >&2
    exit 1
}
MC=$(buscar llvm-mc)
OBJDUMP=$(buscar llvm-objdump)
OBJCOPY=$(buscar llvm-objcopy)
READELF=$(buscar llvm-readelf)

# La misma lista que ensamblar.sh
PERMITIDAS='lw|sw|sll|slli|srl|srli|sra|srai|add|and|xor|or|sub|addi|andi|xori|ori|beq|bne|blt|bge|slt|slti|sltu|sltiu|jal|jalr|lui'

mkdir -p "$BUILD"

# 1. Ensamblar sin relajación ni instrucciones comprimidas.
$MC -triple=riscv32 -mattr=-relax,-c -filetype=obj -o "$BUILD/$NOMBRE.o" "$FUENTE"

if $READELF -r "$BUILD/$NOMBRE.o" | grep -q "R_RISCV"; then
    echo "ERROR: quedaron relocaciones sin resolver, revisar que todas las etiquetas existan:"
    $READELF -r "$BUILD/$NOMBRE.o"
    exit 1
fi

# 2. Desensamblar a un listado.
$OBJDUMP -d -M no-aliases "$BUILD/$NOMBRE.o" > "$BUILD/$NOMBRE.lst"

# 3. Chequear que todas las instrucciones esten en la lista base. En el listado de LLVM el
#    mnemonico es el sexto campo, despues de la direccion y los cuatro bytes.
PROHIBIDAS=$(awk -v ok="^($PERMITIDAS)$" '/^ +[0-9a-f]+:/ && $6 !~ ok' "$BUILD/$NOMBRE.lst")
if [ -n "$PROHIBIDAS" ]; then
    echo "ERROR: instrucciones fuera de la lista base del nucleo:"
    echo "$PROHIBIDAS"
    exit 1
fi

# 4. Generar la imagen de la ROM con el mismo formato que objcopy -O verilog de GNU:
#    @00000000 y cuatro palabras de 32 bits por linea.
$OBJCOPY -O binary -j .text "$BUILD/$NOMBRE.o" "$BUILD/$NOMBRE.bin"
{
    echo "@00000000"
    od -An -v -t x4 -w16 "$BUILD/$NOMBRE.bin" | sed 's/^ *//' | tr 'a-f' 'A-F'
} > "$DIR/$NOMBRE.hex"

echo "OK: $DIR/$NOMBRE.hex ($(grep -c '^ \+[0-9a-f]\+:' "$BUILD/$NOMBRE.lst") instrucciones)"
