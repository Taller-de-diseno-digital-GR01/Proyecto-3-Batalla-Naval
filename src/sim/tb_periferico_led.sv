`timescale 1ns/1ps

module tb_periferico_led;

  localparam logic [1:0] ADDR_LEDS = 2'b00;
  localparam logic [2:0] COLOCACION = 3'b001;
  localparam logic [2:0] BATALLA = 3'b010;
  localparam logic [2:0] RESULTADO = 3'b100;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic [2:0] leds_tb;

  int pruebas = 0;
  int errores = 0;

  periferico_led dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .leds_o(leds_tb)
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

  task automatic escribir(input logic [1:0] a, input logic [31:0] d);
    addr_tb = a;
    wdata_tb = d;
    we_tb = 1'b1;
    ciclo();
    we_tb = 1'b0;
    wdata_tb = 32'b0;
  endtask

  task automatic chequear(input string nombre, input logic [2:0] esperado);
    addr_tb = ADDR_LEDS;
    #1;
    anotar(nombre, leds_tb === esperado && rdata_tb === {29'b0, esperado},
           $sformatf("esperaba %03b y dio leds_o %03b, rdata_o %08h", esperado, leds_tb, rdata_tb));
  endtask

  initial begin
    $dumpfile("tb_periferico_led.vcd");
    $dumpvars(0, tb_periferico_led);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_LEDS;
    wdata_tb = 32'b0;

    repeat (3) ciclo();
    chequear("el reset deja los tres LEDs apagados", 3'b000);
    escribir(ADDR_LEDS, {29'b0, BATALLA});
    chequear("con reset alto no se puede escribir", 3'b000);
    rst_tb = 1'b0;

    escribir(ADDR_LEDS, {29'b0, COLOCACION});
    chequear("colocacion enciende LD0", COLOCACION);
    escribir(ADDR_LEDS, {29'b0, BATALLA});
    chequear("batalla pasa a LD1 y apaga LD0", BATALLA);
    escribir(ADDR_LEDS, {29'b0, RESULTADO});
    chequear("resultado pasa a LD2", RESULTADO);

    // el hardware no decodifica nada, lo que escriba el programa es lo que se ve
    escribir(ADDR_LEDS, 32'h7);
    chequear("tres en alto se muestran tal cual, no hay prioridad", 3'b111);

    escribir(ADDR_LEDS, 32'hFFFF_FFF9);
    chequear("de la palabra solo cuentan los tres bits bajos", 3'b001);

    addr_tb = ADDR_LEDS;
    wdata_tb = {29'b0, RESULTADO};
    repeat (3) ciclo();
    chequear("sin write_enable el dato del bus no entra", 3'b001);
    wdata_tb = 32'b0;

    for (int a = 1; a < 4; a++) begin
      escribir(2'(a), {29'b0, BATALLA});
      addr_tb = 2'(a);
      #1;
      anotar($sformatf("la direccion %02b no guarda ni devuelve nada", 2'(a)), rdata_tb === 32'h0 && leds_tb === 3'b001,
             $sformatf("rdata_o %08h, leds_o %03b", rdata_tb, leds_tb));
    end

    escribir(ADDR_LEDS, {29'b0, BATALLA});
    repeat (5) ciclo();
    chequear("el valor se sostiene sin volver a escribirlo", BATALLA);

    // escribir y reset en el mismo ciclo, gana el reset
    rst_tb = 1'b1;
    escribir(ADDR_LEDS, {29'b0, RESULTADO});
    chequear("el reset le gana a una escritura del mismo ciclo", 3'b000);
    rst_tb = 1'b0;
    escribir(ADDR_LEDS, {29'b0, COLOCACION});
    chequear("y despues del reset se vuelve a escribir normal", COLOCACION);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_led termino con fallos");
    $finish;
  end

endmodule
