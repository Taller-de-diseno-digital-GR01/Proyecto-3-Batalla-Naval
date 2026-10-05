// RISC-V SiMPLE SV -- generic register
// BSD 3-Clause License
// (c) 2017-2019, Arthur Matos, Marcus Vinicius Lamar, Universidade de Brasília,
//                Marek Materzok, University of Wrocław
//
// Modificado para el Proyecto 3 de EL3313 (ver docs/diseño/modulos/PROCESADOR_UNICICLO.md):
// reset síncrono, como el resto del diseño. El original usaba @(posedge clock or posedge reset).

`include "config.sv"
`include "constants.sv"

module register #(
    parameter  WIDTH    = 32,
    parameter  INITIAL  = 0
) (
    input  clock,
    input  reset,
    input  write_enable,
    input  [WIDTH-1:0] next,

    output logic [WIDTH-1:0] value
);

   initial value = INITIAL;

   always_ff @ (posedge clock)
       if (reset) value <= INITIAL;
       else if (write_enable) value <= next;

endmodule
