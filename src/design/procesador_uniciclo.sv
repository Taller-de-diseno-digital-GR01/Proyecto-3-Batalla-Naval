// Envoltorio del nucleo riscv_core (riscv-simple-sv, ciclo unico) con los puertos de la figura 2
// del enunciado. No agrega logica, solo renombra. Ver docs/diseño/modulos/PROCESADOR_UNICICLO.md.

module procesador_uniciclo (
  input  logic        clk_i,
  input  logic        rst_i,          // sincrono, activo en alto

  output logic [31:0] ProgAddress_o,  // PC, hacia la ROM
  input  logic [31:0] ProgIn_i,       // instruccion, desde la ROM

  output logic [31:0] DataAddress_o,  // direccion de lw y sw
  output logic [31:0] DataOut_o,      // dato de sw
  input  logic [31:0] DataIn_i,       // dato de lw, desde MUX_LECTURA
  output logic        we_o            // en alto durante un sw
  );

  // El bus del enunciado no tiene mascara de bytes ni habilitacion de lectura.
  // Con lw y sw alineados, que es lo unico que usa el programa, no hacen falta
  logic [3:0] byte_enable_sin_usar;
  logic       read_enable_sin_usar;

  riscv_core nucleo (
    .clock            (clk_i),
    .reset            (rst_i),
    .inst             (ProgIn_i),
    .pc               (ProgAddress_o),
    .bus_address      (DataAddress_o),
    .bus_read_data    (DataIn_i),
    .bus_write_data   (DataOut_o),
    .bus_read_enable  (read_enable_sin_usar),
    .bus_write_enable (we_o),
    .bus_byte_enable  (byte_enable_sin_usar)
  );

endmodule
