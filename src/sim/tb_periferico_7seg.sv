`timescale 1ns/1ps

module tb_periferico_7seg;

  // reescalado, con 4 bits cada digito dura 4 ciclos y el barrido completo 16
  localparam REFRESH_BITS = 4;
  localparam CICLOS_BARRIDO = 2 ** REFRESH_BITS;

  localparam logic [1:0] ADDR_DIGITOS = 2'b00;
  localparam logic [6:0] APAGADO = 7'b1111111;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic [6:0] seg_tb;
  logic [3:0] an_tb;
  logic dp_tb;

  int pruebas = 0;
  int errores = 0;

  // gfedcba activos en bajo, sale de los segmentos que enciende cada numero en el display de la Basys 3
  logic [6:0] seg_esperado [10] = '{
    7'b1000000, 7'b1111001, 7'b0100100, 7'b0110000, 7'b0011001,
    7'b0010010, 7'b0000010, 7'b1111000, 7'b0000000, 7'b0010000
  };

  periferico_7seg #(.REFRESH_BITS(REFRESH_BITS)) dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .seg_o(seg_tb),
    .an_o(an_tb),
    .dp_o(dp_tb)
  );

  // solo para leerle el parametro por defecto, nunca corre
  periferico_7seg dut_real (.clk_i(1'b0), .rst_i(1'b1), .write_enable_i(1'b0), .addr_i(2'b00), .wdata_i(32'b0), .rdata_o(), .seg_o(), .an_o(), .dp_o());

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
    addr_tb = ADDR_DIGITOS;
  endtask

  task automatic chequear_reg(input string nombre, input logic [1:0] a, input logic [31:0] esperado);
    addr_tb = a;
    #1;
    anotar(nombre, rdata_tb === esperado,
           $sformatf("addr %02b esperaba %08h y dio %08h", a, esperado, rdata_tb));
    addr_tb = ADDR_DIGITOS;
  endtask

  // lo que se vio en cada anodo durante el ultimo barrido, vistos queda en cero si un anodo no aparecio
  logic [6:0] segs [4];
  logic [3:0] puntos;
  logic [3:0] vistos;
  bit un_anodo;

  task automatic barrer();
    vistos = '0;
    puntos = '0;
    un_anodo = 1'b1;
    for (int k = 0; k < 4; k++) segs[k] = 'x;
    for (int c = 0; c < CICLOS_BARRIDO; c++) begin
      ciclo();
      if (an_tb !== 4'b1110 && an_tb !== 4'b1101 && an_tb !== 4'b1011 && an_tb !== 4'b0111) un_anodo = 1'b0;
      for (int k = 0; k < 4; k++) begin
        if (an_tb[k] === 1'b0) begin
          vistos[k] = 1'b1;
          segs[k] = seg_tb;
          puntos[k] = ~dp_tb;
        end
      end
    end
  endtask

  task automatic chequear_display(input string nombre, input logic [15:0] digitos, input logic [3:0] puntos_esp);
    bit ok;
    logic [3:0] d;
    logic [6:0] esp;
    string detalle;
    barrer();
    ok = un_anodo && vistos == 4'b1111 && puntos == puntos_esp;
    detalle = $sformatf("anodos vistos %04b, uno a la vez %0b, puntos %04b esperaba %04b", vistos, un_anodo, puntos, puntos_esp);
    for (int k = 0; k < 4; k++) begin
      d = digitos[k*4 +: 4];
      esp = d < 10 ? seg_esperado[d] : APAGADO;
      if (segs[k] !== esp) begin
        ok = 1'b0;
        detalle = {detalle, $sformatf(", AN%0d con %0d dio %07b y esperaba %07b", k, d, segs[k], esp)};
      end
    end
    anotar(nombre, ok, detalle);
  endtask

  initial begin
    $dumpfile("tb_periferico_7seg.vcd");
    $dumpvars(0, tb_periferico_7seg);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_DIGITOS;
    wdata_tb = 32'b0;

    // con 18 bits a 100 MHz cada digito se ve 655 us, el barrido entero da unos 380 Hz y no parpadea
    anotar("en la tarjeta REFRESH_BITS queda en 18", dut_real.REFRESH_BITS == 18,
           $sformatf("dio %0d", dut_real.REFRESH_BITS));

    repeat (3) ciclo();
    chequear_reg("el reset deja el registro en cero", ADDR_DIGITOS, 32'h0);
    rst_tb = 1'b0;
    chequear_display("al arrancar el display muestra 00 00 sin puntos", 16'h0000, 4'b0000);

    escribir(ADDR_DIGITOS, 32'h0000_0312);
    chequear_reg("el registro se lee de vuelta", ADDR_DIGITOS, 32'h0000_0312);
    chequear_display("3 del J1 y 12 del J2 se ven como 03 12", 16'h0312, 4'b0000);

    escribir(ADDR_DIGITOS, 32'h0000_9999);
    chequear_display("el maximo de 99 y 99", 16'h9999, 4'b0000);

    for (int d = 0; d < 10; d++) begin
      escribir(ADDR_DIGITOS, {16'b0, {4{4'(d)}}});
      chequear_display($sformatf("el %0d en los cuatro digitos", d), {4{4'(d)}}, 4'b0000);
    end

    escribir(ADDR_DIGITOS, 32'h0000_ABCF);
    chequear_display("los nibbles de 10 a 15 apagan el digito", 16'hABCF, 4'b0000);
    escribir(ADDR_DIGITOS, 32'h0000_DE07);
    chequear_display("y se pueden mezclar con digitos normales", 16'hDE07, 4'b0000);

    for (int k = 0; k < 4; k++) begin
      escribir(ADDR_DIGITOS, {12'b0, 4'(1 << k), 16'h1234});
      chequear_display($sformatf("el bit %0d enciende solo el punto de AN%0d", 16 + k, k), 16'h1234, 4'(1 << k));
    end
    escribir(ADDR_DIGITOS, 32'h000F_5678);
    chequear_display("los cuatro puntos juntos", 16'h5678, 4'b1111);

    escribir(ADDR_DIGITOS, 32'hFFFF_FFFF);
    chequear_reg("los bits 31 a 20 se ignoran y se leen en cero", ADDR_DIGITOS, 32'h000F_FFFF);

    // el programa cambia el contador del J2 con lw, cambia sus dos nibbles y sw
    escribir(ADDR_DIGITOS, 32'h0000_0507);
    begin : rmw_j2
      logic [31:0] valor;
      addr_tb = ADDR_DIGITOS;
      #1;
      valor = rdata_tb;
      escribir(ADDR_DIGITOS, {valor[31:8], 8'h08});
    end
    chequear_display("leer, cambiar los nibbles del J2 y escribir deja intacto al J1", 16'h0508, 4'b0000);

    addr_tb = ADDR_DIGITOS;
    wdata_tb = 32'h0000_1111;
    repeat (3) ciclo();
    wdata_tb = 32'b0;
    chequear_reg("sin write_enable el dato del bus no entra", ADDR_DIGITOS, 32'h0000_0508);

    for (int a = 1; a < 4; a++) begin
      escribir(2'(a), 32'h0000_4444);
      chequear_reg($sformatf("la direccion %02b devuelve cero", 2'(a)), 2'(a), 32'h0);
    end
    chequear_reg("y escribirles no toco el registro", ADDR_DIGITOS, 32'h0000_0508);

    rst_tb = 1'b1;
    ciclo();
    rst_tb = 1'b0;
    chequear_reg("el reset borra las ganadas", ADDR_DIGITOS, 32'h0);
    chequear_display("y el display vuelve a 00 00", 16'h0000, 4'b0000);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_7seg termino con fallos");
    $finish;
  end

endmodule
