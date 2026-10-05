// RISC-V SiMPLE SV -- common configuration for testbench
// BSD 3-Clause License
// (c) 2017-2021, Arthur Matos, Marcus Vinicius Lamar, Universidade de Brasília,
//                Marek Materzok, University of Wrocław
//
// Modificado para el Proyecto 3 de EL3313 (ver docs/diseño/modulos/PROCESADOR_UNICICLO.md):
// INITIAL_PC en 0x0000_0000, el vector de reset del enunciado, y sin las macros de las
// memorias de ejemplo, porque la ROM y la RAM son las del proyecto.

`ifndef RV_CONFIG
`define RV_CONFIG

// Select ISA extensions
// `define M_MODULE    // multiplication and division

//////////////////////////////////////////
//              Memory config           //
//////////////////////////////////////////

// Program counter initial value
`define INITIAL_PC      32'h00000000

`endif
