`timescale 1ns/1ps

module tb_periferico_uart;

  // reescalado, a 1.6 MHz y 10000 baudios salen TICKS_BIT = 160 y TICKS_X16 = 10
  localparam CLK_FREQ_HZ = 1_600_000;
  localparam BAUDIOS = 10_000;
  localparam TICKS_BIT = 160;

  localparam logic [1:0] ADDR_CONTROL = 2'b00;
  localparam logic [1:0] ADDR_DATOS_TX = 2'b01;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b10;
  localparam logic [1:0] ADDR_LIBRE = 2'b11;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic linea; // el tx se realimenta al rx, asi una sola instancia prueba las dos direcciones

  int pruebas = 0;
  int errores = 0;

  periferico_uart #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUDIOS(BAUDIOS)) dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .rx_i(linea),
    .tx_o(linea)
  );

  // solo se instancian para leerles los divisores, nunca corren una trama
  periferico_uart dut_100 (.clk_i(1'b0), .rst_i(1'b1), .write_enable_i(1'b0), .addr_i(2'b00), .wdata_i(32'b0), .rdata_o(), .rx_i(1'b1), .tx_o());
  periferico_uart #(.CLK_FREQ_HZ(25_000_000)) dut_25 (.clk_i(1'b0), .rst_i(1'b1), .write_enable_i(1'b0), .addr_i(2'b00), .wdata_i(32'b0), .rdata_o(), .rx_i(1'b1), .tx_o());

  always #5 clk_tb = ~clk_tb;

  // cuenta los bytes que vuelven por el lazo, para ver que send sostenido no manda nada de mas
  logic limpiar_conteo;
  int bytes_recibidos;

  always_ff @(posedge clk_tb) begin
    if (rst_tb || limpiar_conteo) bytes_recibidos <= 0;
    else if (dut.listo_rx) bytes_recibidos <= bytes_recibidos + 1;
  end

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

  task automatic leer(input logic [1:0] a, output logic [31:0] d);
    addr_tb = a;
    ciclo();
    d = rdata_tb;
  endtask

  task automatic chequear_reg(input string nombre, input logic [1:0] a, input logic [31:0] esperado);
    logic [31:0] visto;
    leer(a, visto);
    anotar(nombre, visto === esperado,
           $sformatf("addr %02b esperaba %08h y dio %08h", a, esperado, visto));
  endtask

  task automatic esperar_new_rx(input string nombre);
    int n;
    n = 0;
    addr_tb = ADDR_CONTROL;
    while (!rdata_tb[BIT_NEW_RX] && n < TICKS_BIT * 20) begin
      ciclo();
      n++;
    end
    anotar(nombre, rdata_tb[BIT_NEW_RX] === 1'b1,
           $sformatf("new_rx nunca subio, control quedo en %08h", rdata_tb));
  endtask

  task automatic esperar_send_bajo();
    int n;
    n = 0;
    addr_tb = ADDR_CONTROL;
    while (rdata_tb[BIT_SEND] && n < TICKS_BIT * 20) begin
      ciclo();
      n++;
    end
    // el eco por rx termina medio bit despues de que send baja, se espera para que no caiga en la prueba siguiente
    repeat (TICKS_BIT * 2) ciclo();
  endtask

  task automatic limpiar();
    limpiar_conteo = 1'b1;
    ciclo();
    limpiar_conteo = 1'b0;
  endtask

  initial begin
    $dumpfile("tb_periferico_uart.vcd");
    $dumpvars(0, tb_periferico_uart);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_CONTROL;
    wdata_tb = 32'b0;
    limpiar_conteo = 1'b0;

    anotar("a 100 MHz los divisores son 868 y 54", dut_100.TICKS_BIT == 868 && dut_100.TICKS_X16 == 54,
           $sformatf("dieron %0d y %0d", dut_100.TICKS_BIT, dut_100.TICKS_X16));
    anotar("a 25 MHz salen redondeados en 217 y 14", dut_25.TICKS_BIT == 217 && dut_25.TICKS_X16 == 14,
           $sformatf("dieron %0d y %0d", dut_25.TICKS_BIT, dut_25.TICKS_X16));
    anotar("y los del tb calzan con lo reescalado", dut.TICKS_BIT == 160 && dut.TICKS_X16 == 10,
           $sformatf("dieron %0d y %0d", dut.TICKS_BIT, dut.TICKS_X16));

    repeat (4) ciclo();
    chequear_reg("el reset deja el control en ceros", ADDR_CONTROL, 32'h0);
    chequear_reg("el registro de transmision tambien", ADDR_DATOS_TX, 32'h0);
    chequear_reg("y el de recepcion", ADDR_DATOS_RX, 32'h0);
    anotar("la linea arranca en reposo alto", linea === 1'b1, $sformatf("tx_o dio %0b", linea));
    rst_tb = 1'b0;

    chequear_reg("la direccion 11 no se usa y devuelve ceros", ADDR_LIBRE, 32'h0);
    escribir(ADDR_LIBRE, 32'hFFFF_FFFF);
    chequear_reg("escribirle no hace nada, sigue en ceros", ADDR_LIBRE, 32'h0);
    chequear_reg("ni toca el control", ADDR_CONTROL, 32'h0);

    escribir(ADDR_DATOS_TX, 32'h41);
    chequear_reg("el registro de transmision guarda lo que le escriben", ADDR_DATOS_TX, 32'h41);
    chequear_reg("y escribirlo no toca el control", ADDR_CONTROL, 32'h0);
    escribir(ADDR_DATOS_TX, 32'hFFFF_FF41);
    chequear_reg("los bits de arriba del byte se ignoran y se leen en cero", ADDR_DATOS_TX, 32'h41);

    escribir(ADDR_DATOS_RX, 32'hFFFF_FF5A);
    chequear_reg("el de recepcion tambien es de escritura y guarda solo el byte", ADDR_DATOS_RX, 32'h5A);
    escribir(ADDR_DATOS_RX, 32'h00);

    escribir(ADDR_CONTROL, 32'hFFFF_FFFE);
    chequear_reg("los bits reservados del control no se guardan, solo new_rx", ADDR_CONTROL, 32'h2);
    escribir(ADDR_CONTROL, 32'h0);
    repeat (TICKS_BIT * 2) ciclo();
    anotar("escribir el control sin send no saca nada por la linea", linea === 1'b1,
           $sformatf("tx_o dio %0b", linea));

    // el byte sale por tx y vuelve por rx
    limpiar();
    escribir(ADDR_CONTROL, 32'h1);
    chequear_reg("send se lee alto apenas se escribe", ADDR_CONTROL, 32'h1);
    addr_tb = ADDR_CONTROL;
    repeat (TICKS_BIT * 2) ciclo();
    anotar("y sigue alto mientras el byte va saliendo, es la bandera de ocupado", rdata_tb[BIT_SEND] === 1'b1,
           $sformatf("control dio %08h", rdata_tb));

    // es lo que hace la ROM al recibir, sw x0 al control, y no puede cancelar un envio en curso
    escribir(ADDR_CONTROL, 32'h0);
    chequear_reg("escribir cero no baja send a media transmision, es WC", ADDR_CONTROL, 32'h1);

    esperar_new_rx("el byte da la vuelta y levanta new_rx");
    chequear_reg("y aparece entero en el registro de recepcion", ADDR_DATOS_RX, 32'h41);
    esperar_send_bajo();
    chequear_reg("send se baja solo al terminar y new_rx sigue esperando", ADDR_CONTROL, 32'h2);

    repeat (TICKS_BIT * 15) ciclo();
    anotar("sostener send no manda el byte dos veces", bytes_recibidos === 1,
           $sformatf("volvieron %0d bytes por el lazo, se esperaba 1", bytes_recibidos));

    escribir(ADDR_CONTROL, 32'h0);
    chequear_reg("escribir cero en el bit 1 limpia new_rx", ADDR_CONTROL, 32'h0);
    chequear_reg("pero el dato recibido se queda donde estaba", ADDR_DATOS_RX, 32'h41);

    // segundo byte, para ver que el periferico no se traba despues del primero
    escribir(ADDR_DATOS_TX, 32'h5A);
    escribir(ADDR_CONTROL, 32'h1);
    esperar_new_rx("un segundo byte tambien da la vuelta");
    chequear_reg("y llega con su valor", ADDR_DATOS_RX, 32'h5A);
    esperar_send_bajo();
    escribir(ADDR_CONTROL, 32'h0);

    // una trama de 5 bytes como la manda la ROM, sondeando send entre byte y byte
    limpiar();
    begin : trama_rom
      static logic [7:0] trama [5] = '{8'hA5, 8'h03, 8'h12, 8'h00, 8'hB6};
      logic [31:0] control;
      for (int i = 0; i < 5; i++) begin
        escribir(ADDR_DATOS_TX, {24'b0, trama[i]});
        leer(ADDR_CONTROL, control);
        escribir(ADDR_CONTROL, control | 32'h1);
        esperar_new_rx($sformatf("byte %0d de una trama", i));
        chequear_reg($sformatf("byte %0d llega como %02h", i, trama[i]), ADDR_DATOS_RX, {24'b0, trama[i]});
        escribir(ADDR_CONTROL, 32'h0);
        esperar_send_bajo();
      end
    end
    anotar("la trama completa son 5 bytes, ni uno de mas", bytes_recibidos === 5,
           $sformatf("volvieron %0d bytes", bytes_recibidos));

    // la escritura que arranca un envio pisa new_rx, por eso la ROM hace lw, ori 1 y sw en vez de un sw 1 directo
    escribir(ADDR_DATOS_TX, 32'h37);
    escribir(ADDR_CONTROL, 32'h1);
    esperar_new_rx("llega un byte y queda esperando que lo lean");
    esperar_send_bajo();
    escribir(ADDR_DATOS_TX, 32'h38);
    escribir(ADDR_CONTROL, 32'h1);
    chequear_reg("un sw 1 directo borra new_rx con el byte sin leer", ADDR_CONTROL, 32'h1);
    esperar_new_rx("el 38 vuelve y levanta new_rx otra vez");
    esperar_send_bajo();
    begin : envio_rmw
      logic [31:0] control;
      escribir(ADDR_DATOS_TX, 32'h39);
      leer(ADDR_CONTROL, control);
      escribir(ADDR_CONTROL, control | 32'h1);
    end
    chequear_reg("con lw, ori 1 y sw new_rx se conserva", ADDR_CONTROL, 32'h3);
    esperar_send_bajo();
    escribir(ADDR_CONTROL, 32'h0);

    // send que se pide justo en el ciclo en que el nucleo avisa que termino, la escritura tiene que ganar
    limpiar();
    escribir(ADDR_DATOS_TX, 32'h61);
    escribir(ADDR_CONTROL, 32'h1);
    while (!dut.listo_tx) ciclo();
    escribir(ADDR_CONTROL, 32'h1);
    chequear_reg("send escrito en el mismo ciclo que o_listo se queda alto", ADDR_CONTROL, 32'h1);
    esperar_send_bajo();
    repeat (TICKS_BIT * 3) ciclo();
    anotar("y el byte sale otra vez, se pidieron dos envios", bytes_recibidos === 2,
           $sformatf("volvieron %0d bytes, se esperaban 2", bytes_recibidos));
    escribir(ADDR_CONTROL, 32'h0);

    // un byte que llega en el mismo ciclo en que la ROM limpia new_rx no se puede perder
    escribir(ADDR_DATOS_TX, 32'h62);
    escribir(ADDR_CONTROL, 32'h1);
    while (!dut.listo_rx) ciclo();
    escribir(ADDR_CONTROL, 32'h0);
    chequear_reg("el byte que llega le gana a la limpieza del mismo ciclo", ADDR_CONTROL, 32'h2);
    chequear_reg("y el dato es el nuevo", ADDR_DATOS_RX, 32'h62);
    esperar_send_bajo();
    escribir(ADDR_CONTROL, 32'h0);

    // reset a media transmision, la linea vuelve a reposo y los registros a cero
    escribir(ADDR_DATOS_TX, 32'h00);
    escribir(ADDR_CONTROL, 32'h1);
    repeat (TICKS_BIT * 4) ciclo();
    rst_tb = 1'b1;
    repeat (2) ciclo();
    anotar("el reset a media transmision suelta la linea en alto", linea === 1'b1,
           $sformatf("tx_o dio %0b", linea));
    chequear_reg("y deja el control en ceros", ADDR_CONTROL, 32'h0);
    rst_tb = 1'b0;
    limpiar();
    repeat (TICKS_BIT * 15) ciclo();
    anotar("el byte cortado no aparece despues del reset", bytes_recibidos === 0,
           $sformatf("volvieron %0d bytes", bytes_recibidos));
    escribir(ADDR_DATOS_TX, 32'h7E);
    escribir(ADDR_CONTROL, 32'h1);
    esperar_new_rx("despues del reset el periferico sigue funcionando");
    chequear_reg("y el byte llega bien", ADDR_DATOS_RX, 32'h7E);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_uart termino con fallos");
    $finish;
  end

endmodule
