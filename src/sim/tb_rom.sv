`timescale 1ns / 1ps

// Testbench autoverificable de rom.sv, ver docs/diseño/modulos/ROM.md inciso h).
// Carga src/sim/rom_prueba.hex, donde la palabra n vale C0DE_0000 + n en los tramos
// 0 a 7, 1024 a 1031 y 2047. El resto no se carga.

module tb_rom;

  logic [31:0] addr;
  logic [31:0] instr;

  int errores = 0;
  int chequeos = 0;

  // make sim corre desde src/build
  rom #(.ARCHIVO_HEX("../sim/rom_prueba.hex")) dut (
    .addr_i (addr),
    .instr_o(instr)
  );

  function automatic logic [31:0] valor(input int n);
    return 32'hC0DE_0000 + n;
  endfunction

  task automatic revisar(input logic [31:0] direccion, input logic [31:0] esperado, input string caso);
    addr = direccion;
    #1;
    chequeos++;
    if (instr !== esperado) begin
      errores++;
      $display("FALLA %s: addr = 0x%08h, instr = 0x%08h, esperado 0x%08h", caso, direccion, instr, esperado);
    end
  endtask

  int cargadas[$];
  int n;

  initial begin
    for (int n = 0; n < 8; n++) cargadas.push_back(n);
    for (int n = 1024; n < 1032; n++) cargadas.push_back(n);
    cargadas.push_back(2047);

    foreach (cargadas[i]) begin
      n = cargadas[i];

      // 1. Cada palabra en su direccion 4n, y los bits [1:0] no cambian nada
      for (int b = 0; b < 4; b++)
        revisar(4 * n + b, valor(n), "lectura");

      // 2. Los bits [31:13] se ignoran, fuera de rango la ROM se repite
      revisar(32'h0000_2000 + 4 * n, valor(n), "repeticion 0x2000");
      revisar(32'h0001_0000 + 4 * n, valor(n), "repeticion 0x1_0000");
      revisar(32'hFFFF_E000 + 4 * n, valor(n), "repeticion bits altos en 1");
    end

    // 3. Las palabras que el archivo no carga se leen como X
    revisar(4 * 8,    'x, "sin cargar, palabra 8");
    revisar(4 * 500,  'x, "sin cargar, palabra 500");
    revisar(4 * 1032, 'x, "sin cargar, palabra 1032");
    revisar(4 * 2046, 'x, "sin cargar, palabra 2046");

    if (errores == 0)
      $display("PASS tb_rom: %0d chequeos", chequeos);
    else
      $display("FAIL tb_rom: %0d errores en %0d chequeos", errores, chequeos);
    $finish;
  end

endmodule
