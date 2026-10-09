/* Mapa de memoria del Proyecto 3 para las pruebas oficiales rv32ui:
   código en la ROM desde 0x0000_0000 (vector de reset) y datos en la RAM desde 0x0000_2000. */
OUTPUT_ARCH("riscv")
ENTRY(test)
SECTIONS
{
  . = 0x00000000;
  .text : { *(.text .text.*) }
  . = 0x00002000;
  .data : { *(.data .data.*) *(.sdata .sdata.*) }
}
