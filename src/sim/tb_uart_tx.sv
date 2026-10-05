`timescale 1ns/1ps

module tb_uart_tx;

  // reescalado, lo real son 868 y 54, aca 160 y 10 para que 16*TICKS_X16 calce exacto con TICKS_BIT
  localparam TICKS_BIT = 160;
  localparam TICKS_X16 = TICKS_BIT / 16;

  logic clk_tb;
  logic rst_tb;
  logic i_enviar_tb;
  logic [7:0] i_dato_tb;
  logic o_listo_tb;
  logic linea;

  logic rx_listo;
  logic [7:0] rx_dato;

  int pruebas = 0;
  int errores = 0;

  uart_tx #(.TICKS_BIT(TICKS_BIT)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_enviar(i_enviar_tb),
    .i_dato(i_dato_tb),
    .o_listo(o_listo_tb),
    .o_tx(linea)
  );

  // el receptor ya portado hace de contraparte, si el lazo cierra los dos nucleos se entienden
  uart_rx #(.TICKS_X16(TICKS_X16)) espejo (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rx(linea),
    .o_dato_listo(rx_listo),
    .o_dato(rx_dato)
  );

  always #5 clk_tb = ~clk_tb;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // o_listo tiene que ser un pulso, si sale como nivel el periferico contaria de mas los bytes que van saliendo
  logic limpiar_conteo;
  int ciclos_listo;

  always_ff @(posedge clk_tb) begin
    if (rst_tb || limpiar_conteo) ciclos_listo <= 0;
    else if (o_listo_tb) ciclos_listo <= ciclos_listo + 1;
  end

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

  task automatic enviar(input logic [7:0] b);
    i_dato_tb = b;
    i_enviar_tb = 1'b1;
    ciclo();
    i_enviar_tb = 1'b0;
  endtask

  task automatic esperar_arranque(output bit hubo);
    int n;
    n = 0;
    while (linea !== 1'b0 && n < TICKS_BIT * 15) begin
      @(posedge clk_tb);
      n++;
    end
    hubo = (n < TICKS_BIT * 15);
  endtask

  // sostiene i_enviar hasta que el nucleo arranca, que es lo que va a tener que hacer periferico_uart con el bit send
  task automatic enviar_sostenido(input logic [7:0] b);
    bit hubo;
    i_dato_tb = b;
    i_enviar_tb = 1'b1;
    esperar_arranque(hubo);
    i_enviar_tb = 1'b0;
  endtask

  // muestrea la linea al centro de cada bit y rearma el byte, para comprobar la trama y no solo el dato
  task automatic espiar(input string nombre, input logic [7:0] esperado);
    logic arranque;
    logic parada;
    logic [7:0] visto;
    bit hubo;
    esperar_arranque(hubo);
    if (!hubo) begin
      anotar(nombre, 1'b0, "la linea nunca arranco, el pulso de i_enviar se perdio");
      return;
    end
    repeat (TICKS_BIT/2) @(posedge clk_tb);
    arranque = linea;
    for (int i = 0; i < 8; i++) begin
      repeat (TICKS_BIT) @(posedge clk_tb);
      visto[i] = linea;
    end
    repeat (TICKS_BIT) @(posedge clk_tb);
    parada = linea;
    anotar(nombre, arranque === 1'b0 && visto === esperado && parada === 1'b1,
           $sformatf("esperaba arranque=0 byte=%02h parada=1, y dio arranque=%0b byte=%02h parada=%0b",
                     esperado, arranque, visto, parada));
  endtask

  task automatic esperar_espejo(input string nombre, input logic [7:0] esperado);
    int n;
    n = 0;
    while (!rx_listo && n < TICKS_BIT * 20) begin
      ciclo();
      n++;
    end
    anotar(nombre, rx_listo === 1'b1 && rx_dato === esperado,
           $sformatf("el espejo esperaba %02h y dio %02h con listo=%0b", esperado, rx_dato, rx_listo));
  endtask

  initial begin
    $dumpfile("tb_uart_tx.vcd");
    $dumpvars(0, tb_uart_tx);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    i_enviar_tb = 1'b0;
    i_dato_tb = 8'h00;

    repeat (4) ciclo();
    anotar("el reset deja la linea en reposo alto", linea === 1'b1,
           $sformatf("o_tx dio %0b", linea));
    rst_tb = 1'b0;

    repeat (TICKS_BIT * 2) ciclo();
    anotar("sin nada que mandar la linea no se mueve", linea === 1'b1,
           $sformatf("o_tx dio %0b", linea));

    fork
      enviar(8'h41);
      espiar("la A sale con su bit de arranque, ocho de dato y el de parada", 8'h41);
    join
    esperar_espejo("y el receptor la reconstruye entera", 8'h41);

    repeat (TICKS_BIT) ciclo();

    fork
      enviar(8'h00);
      espiar("un byte de puros ceros no se confunde con el arranque", 8'h00);
    join
    esperar_espejo("el espejo tambien lo saca bien", 8'h00);

    repeat (TICKS_BIT) ciclo();

    fork
      enviar(8'hFF);
      espiar("un byte de puros unos tampoco se come el bit de parada", 8'hFF);
    join
    esperar_espejo("y el espejo lo confirma", 8'hFF);

    repeat (TICKS_BIT) ciclo();

    // la fuente puede soltar i_dato apenas dispara, el nucleo lo congela adentro
    i_dato_tb = 8'h5A;
    i_enviar_tb = 1'b1;
    ciclo();
    i_enviar_tb = 1'b0;
    i_dato_tb = 8'h00;
    esperar_espejo("cambiar i_dato a mitad de la transmision no corrompe el byte", 8'h5A);

    repeat (TICKS_BIT) ciclo();
    anotar("o_listo no se queda pegado", o_listo_tb === 1'b0,
           $sformatf("o_listo dio %0b", o_listo_tb));

    limpiar_conteo = 1'b1;
    ciclo();
    limpiar_conteo = 1'b0;
    fork
      enviar(8'h37);
      espiar("otro byte para medir el ancho de o_listo", 8'h37);
    join
    esperar_espejo("el espejo lo saca", 8'h37);
    repeat (TICKS_BIT * 2) ciclo();
    anotar("o_listo dura exactamente un ciclo por byte", ciclos_listo === 1,
           $sformatf("o_listo estuvo alto %0d ciclos, se esperaba 1", ciclos_listo));

    // Entre el bit de parada y el siguiente tick de reposo el detector queda en pausa, un pulso de un ciclo ahi se pierde
    fork
      enviar("H");
      espiar("el primero de un par pegado", 8'h48);
    join
    esperar_espejo("y el espejo lo saca", 8'h48);

    i_dato_tb = "X";
    i_enviar_tb = 1'b1;
    ciclo();
    i_enviar_tb = 1'b0;
    repeat (TICKS_BIT * 3) ciclo();
    anotar("un pulso de un ciclo apenas termina el byte anterior se pierde", linea === 1'b1,
           "la linea arranco, se esperaba que el detector en pausa se comiera el pulso");

    // sostenido si entra, el nucleo lo agarra apenas el detector se reactiva
    fork
      enviar_sostenido("I");
      espiar("sostener i_enviar si atraviesa la ventana muerta", 8'h49);
    join
    esperar_espejo("el espejo saca el segundo del par", 8'h49);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_uart_tx termino con fallos");
    $finish;
  end

endmodule
