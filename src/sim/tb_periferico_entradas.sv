`timescale 1ns/1ps

module tb_periferico_entradas;

  localparam logic [1:0] ADDR_ESTADO = 2'b00;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic [6:0] botones_tb;

  int pruebas = 0;
  int errores = 0;

  periferico_entradas dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .botones_i(botones_tb)
  );

  always #5 clk_tb = ~clk_tb;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  task automatic anotar(input string nombre, input bit ok, input string detalle);
    pruebas++;
    if (ok) begin
      $display("ok %s", nombre);
    end
    else begin
      errores++;
      $display("fallo %s", nombre);
      $display("  %s", detalle);
    end
  endtask

  task automatic chequear_reg(input string nombre, input logic [1:0] a, input logic [31:0] esperado);
    addr_tb = a;
    #1;
    anotar(nombre, rdata_tb === esperado,
           $sformatf("addr %02b esperaba %08h y dio %08h", a, esperado, rdata_tb));
  endtask

  initial begin
    $dumpfile("tb_periferico_entradas.vcd");
    $dumpvars(0, tb_periferico_entradas);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_ESTADO;
    wdata_tb = 32'b0;
    botones_tb = 7'h7F;

    repeat (3) ciclo();
    chequear_reg("con reset se lee cero aunque esten todos apretados", ADDR_ESTADO, 32'h0);
    rst_tb = 1'b0;
    botones_tb = 7'h00;
    ciclo();
    chequear_reg("al soltar el reset sin botones sigue en cero", ADDR_ESTADO, 32'h0);

    // el flip-flop atrasa un ciclo, el programa no lo nota pero el registro tiene que estar
    botones_tb = 7'h01;
    #1;
    anotar("el pin no pasa directo a rdata_o en el mismo ciclo", rdata_tb === 32'h0,
           $sformatf("dio %08h antes del flanco", rdata_tb));
    ciclo();
    chequear_reg("un ciclo despues ya se lee", ADDR_ESTADO, 32'h1);

    for (int i = 0; i < 7; i++) begin
      botones_tb = 7'(1 << i);
      ciclo();
      chequear_reg($sformatf("el boton %0d cae en el bit %0d", i, i), ADDR_ESTADO, 32'(1 << i));
    end

    botones_tb = 7'h7F;
    ciclo();
    chequear_reg("los siete juntos dan 7F y lo de arriba queda en cero", ADDR_ESTADO, 32'h7F);

    botones_tb = 7'h2A;
    ciclo();
    chequear_reg("una combinacion cualquiera se lee tal cual", ADDR_ESTADO, 32'h2A);
    botones_tb = 7'h00;
    ciclo();
    chequear_reg("y al soltarlos vuelve a cero", ADDR_ESTADO, 32'h0);

    // es de solo lectura, una escritura que se cuele no puede pisar el estado
    botones_tb = 7'h15;
    addr_tb = ADDR_ESTADO;
    wdata_tb = 32'hFFFF_FFFF;
    we_tb = 1'b1;
    ciclo();
    we_tb = 1'b0;
    wdata_tb = 32'b0;
    chequear_reg("escribirle no cambia nada, se sigue leyendo el pin", ADDR_ESTADO, 32'h15);

    for (int a = 1; a < 4; a++) begin
      chequear_reg($sformatf("la direccion %02b no existe y devuelve cero", 2'(a)), 2'(a), 32'h0);
    end
    chequear_reg("y volver a 00 muestra los botones otra vez", ADDR_ESTADO, 32'h15);

    botones_tb = 7'h7F;
    ciclo();
    rst_tb = 1'b1;
    ciclo();
    chequear_reg("el reset limpia aunque sigan apretados", ADDR_ESTADO, 32'h0);
    rst_tb = 1'b0;
    ciclo();
    chequear_reg("y al soltarlo los vuelve a ver", ADDR_ESTADO, 32'h7F);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_entradas termino con fallos");
    $finish;
  end

endmodule
