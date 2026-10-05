`timescale 1ns / 1ps

// Testbench autoverificable de ram.sv, ver docs/diseño/modulos/RAM.md inciso h).
// La palabra n se llena con valor(n), distinto para cada una, y se compara contra ese valor.

module tb_ram;

  logic        clk = 0;
  logic        we = 0;
  logic [31:0] addr = 32'h0000_2000;
  logic [31:0] wdata = '0;
  logic [31:0] rdata;

  int errores = 0;
  int chequeos = 0;
  int n;

  always #10 clk = ~clk; // 50 MHz

  ram dut (
    .clk_i         (clk),
    .write_enable_i(we),
    .addr_i        (addr),
    .wdata_i       (wdata),
    .rdata_o       (rdata)
  );

  function automatic logic [31:0] valor(input int n);
    return {n[15:0], ~n[15:0]};
  endfunction

  function automatic logic [31:0] dir(input int n);
    return 32'h0000_2000 + 4 * n;
  endfunction

  // Lectura sin reloj: cambia la direccion, espera 1 ns y compara
  task automatic revisar(input logic [31:0] direccion, input logic [31:0] esperado, input string caso);
    addr = direccion;
    #1;
    chequeos++;
    if (rdata !== esperado) begin
      errores++;
      $display("FALLA %s: addr = 0x%08h, rdata = 0x%08h, esperado 0x%08h", caso, direccion, rdata, esperado);
    end
  endtask

  // Un ciclo de escritura: se arma en el flanco de bajada y se guarda en el de subida
  task automatic escribir(input logic [31:0] direccion, input logic [31:0] dato, input logic habilitar);
    @(negedge clk);
    addr  = direccion;
    wdata = dato;
    we    = habilitar;
    @(posedge clk);
    #1;
    we = 0;
  endtask

  initial begin
    // 1. Antes de escribir, la RAM no tiene contenido
    revisar(dir(0),    'x, "sin escribir, palabra 0");
    revisar(dir(500),  'x, "sin escribir, palabra 500");
    revisar(dir(1023), 'x, "sin escribir, palabra 1023");

    // 2. Llenar las 1024 palabras. Una de cada cuatro se escribe con bits ignorados
    //    distintos de cero, para comprobar que tampoco cambian donde se escribe
    for (n = 0; n < 1024; n++) begin
      case (n % 4)
        0: escribir(dir(n), valor(n), 1);
        1: escribir(dir(n) + 32'h0000_1000, valor(n), 1);          // [31:12] = 0x00003
        2: escribir(dir(n) ^ 32'hFFFF_F000, valor(n), 1);          // [31:12] todos invertidos
        3: escribir(dir(n) + 3, valor(n), 1);                      // [1:0] = 11
      endcase
    end

    // 3. Leer todas, sin reloj de por medio entre una y otra (lectura asincrona)
    @(negedge clk);
    for (n = 0; n < 1024; n++)
      revisar(dir(n), valor(n), "lectura");

    // 4. Los bits [1:0] y [31:12] no cambian que palabra se lee
    for (n = 0; n < 1024; n += 37) begin
      revisar(dir(n) + 1,                valor(n), "lectura con [1:0] = 01");
      revisar(dir(n) + 2,                valor(n), "lectura con [1:0] = 10");
      revisar(dir(n) + 3,                valor(n), "lectura con [1:0] = 11");
      revisar(dir(n) - 32'h0000_2000,    valor(n), "lectura con [31:12] = 0x00000");
      revisar(dir(n) + 32'h0001_0000,    valor(n), "lectura con [31:12] = 0x00012");
    end

    // 5. La escritura ocurre en el flanco: antes se ve el valor viejo, despues el nuevo
    @(negedge clk);
    addr  = dir(100);
    wdata = 32'hCAFE_0100;
    we    = 1;
    #1;
    chequeos++;
    if (rdata !== valor(100)) begin
      errores++;
      $display("FALLA antes del flanco: rdata = 0x%08h, esperado el valor viejo 0x%08h", rdata, valor(100));
    end
    @(posedge clk);
    #1;
    we = 0;
    chequeos++;
    if (rdata !== 32'hCAFE_0100) begin
      errores++;
      $display("FALLA despues del flanco: rdata = 0x%08h, esperado 0xCAFE0100", rdata);
    end

    // La escritura no toco a las vecinas
    revisar(dir(99),  valor(99),  "vecina anterior");
    revisar(dir(101), valor(101), "vecina siguiente");

    // 6. Con write_enable_i en cero el flanco no cambia nada
    escribir(dir(200), 32'hBAD0_0200, 0);
    revisar(dir(200), valor(200), "sin write_enable");
    escribir(dir(1023), 32'hBAD0_03FF, 0);
    revisar(dir(1023), valor(1023), "sin write_enable, ultima palabra");

    // 7. Un lw justo despues de un sw a la misma direccion lee el valor nuevo
    escribir(dir(1023), 32'h0000_2FFC, 1);
    revisar(dir(1023), 32'h0000_2FFC, "lw despues de sw");

    if (errores == 0)
      $display("PASS tb_ram: %0d chequeos", chequeos);
    else
      $display("FAIL tb_ram: %0d errores en %0d chequeos", errores, chequeos);
    $finish;
  end

endmodule
