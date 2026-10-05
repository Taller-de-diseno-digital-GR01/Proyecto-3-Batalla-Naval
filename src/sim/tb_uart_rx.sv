`timescale 1ns/1ps

module tb_uart_rx;

  // reescalado, lo real son 54 y 868, aca 10 y 160 para que 16*TICKS_X16 calce exacto con un bit
  localparam TICKS_X16 = 10;
  localparam TICKS_BIT = TICKS_X16 * 16;

  // 25 y 10 MHz con los divisores redondeados que saca periferico_uart, para revisar lo que dice PERIFERICO_UART.md
  localparam TICKS_X16_25MHZ = 14;
  localparam TICKS_BIT_25MHZ = 217;
  localparam TICKS_X16_10MHZ = 5;
  localparam TICKS_BIT_10MHZ = 87;

  logic clk_tb;
  logic rst_tb;
  logic linea;
  logic o_dato_listo_tb;
  logic [7:0] o_dato_tb;

  logic linea_25;
  logic listo_25;
  logic [7:0] dato_25;
  logic linea_10;
  logic listo_10;
  logic [7:0] dato_10;

  int pruebas = 0;
  int errores = 0;

  uart_rx #(.TICKS_X16(TICKS_X16)) dut (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rx(linea),
    .o_dato_listo(o_dato_listo_tb),
    .o_dato(o_dato_tb)
  );

  uart_rx #(.TICKS_X16(TICKS_X16_25MHZ)) dut_25 (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rx(linea_25),
    .o_dato_listo(listo_25),
    .o_dato(dato_25)
  );

  uart_rx #(.TICKS_X16(TICKS_X16_10MHZ)) dut_10 (
    .clk(clk_tb),
    .rst(rst_tb),
    .i_rx(linea_10),
    .o_dato_listo(listo_10),
    .o_dato(dato_10)
  );

  always #5 clk_tb = ~clk_tb;

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  // o_dato_listo tiene que ser un pulso, si sale como nivel el periferico levantaria new_rx otra vez despues de que lo limpien
  logic limpiar_conteo;
  int ciclos_listo;

  always_ff @(posedge clk_tb) begin
    if (rst_tb || limpiar_conteo) ciclos_listo <= 0;
    else if (o_dato_listo_tb) ciclos_listo <= ciclos_listo + 1;
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

  localparam LINEA = 0;
  localparam LINEA_25 = 1;
  localparam LINEA_10 = 2;

  task automatic poner(input int cual, input logic v);
    case (cual)
      LINEA: linea = v;
      LINEA_25: linea_25 = v;
      LINEA_10: linea_10 = v;
    endcase
  endtask

  // hace de PC, arma la trama completa con ciclos_bit por bit para poder simular un emisor corrido de baudaje
  task automatic mandar(input int cual, input logic [7:0] b, input int ciclos_bit);
    poner(cual, 1'b0);
    repeat (ciclos_bit) @(posedge clk_tb);
    for (int i = 0; i < 8; i++) begin
      poner(cual, b[i]);
      repeat (ciclos_bit) @(posedge clk_tb);
    end
    poner(cual, 1'b1);
    repeat (ciclos_bit) @(posedge clk_tb);
  endtask

  task automatic esperar_listo(input string nombre, input logic [7:0] esperado);
    int n;
    n = 0;
    while (!o_dato_listo_tb && n < TICKS_BIT * 20) begin
      ciclo();
      n++;
    end
    anotar(nombre, o_dato_listo_tb === 1'b1 && o_dato_tb === esperado,
           $sformatf("esperaba %02h y dio %02h con listo=%0b", esperado, o_dato_tb, o_dato_listo_tb));
  endtask

  task automatic recibir(input string nombre, input logic [7:0] b, input int ciclos_bit);
    fork
      mandar(LINEA, b, ciclos_bit);
      esperar_listo(nombre, b);
    join
    repeat (TICKS_BIT) ciclo();
  endtask

  initial begin
    $dumpfile("tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    linea = 1'b1;
    linea_25 = 1'b1;
    linea_10 = 1'b1;
    limpiar_conteo = 1'b0;

    repeat (4) ciclo();
    anotar("el reset deja el dato en cero y sin aviso", o_dato_tb === 8'h00 && o_dato_listo_tb === 1'b0,
           $sformatf("o_dato dio %02h y o_dato_listo %0b", o_dato_tb, o_dato_listo_tb));
    rst_tb = 1'b0;

    repeat (TICKS_BIT * 3) ciclo();
    anotar("con la linea en reposo no aparece ningun byte", ciclos_listo === 0,
           $sformatf("o_dato_listo subio %0d veces", ciclos_listo));

    recibir("la A llega entera", 8'h41, TICKS_BIT);
    recibir("un byte de puros ceros no se queda pegado esperando la parada", 8'h00, TICKS_BIT);
    recibir("un byte de puros unos", 8'hFF, TICKS_BIT);
    recibir("bits alternados, el orden es menos significativo primero", 8'hA5, TICKS_BIT);
    recibir("y al reves tambien", 8'h5A, TICKS_BIT);

    repeat (TICKS_BIT * 4) ciclo();
    anotar("el ultimo byte se queda en o_dato hasta que llegue otro", o_dato_tb === 8'h5A,
           $sformatf("o_dato dio %02h", o_dato_tb));

    limpiar_conteo = 1'b1;
    ciclo();
    limpiar_conteo = 1'b0;
    recibir("otro byte para medir el ancho de o_dato_listo", 8'h37, TICKS_BIT);
    repeat (TICKS_BIT * 2) ciclo();
    anotar("o_dato_listo dura exactamente un ciclo por byte", ciclos_listo === 1,
           $sformatf("o_dato_listo estuvo alto %0d ciclos, se esperaba 1", ciclos_listo));

    // un cero de menos de medio bit no llega al centro del arranque, el receptor lo descarta y vuelve a reposo
    limpiar_conteo = 1'b1;
    ciclo();
    limpiar_conteo = 1'b0;
    linea = 1'b0;
    repeat (TICKS_X16 * 4) ciclo();
    linea = 1'b1;
    repeat (TICKS_BIT * 12) ciclo();
    anotar("un pulso corto en la linea se toma como ruido", ciclos_listo === 0,
           $sformatf("o_dato_listo subio %0d veces con un ruido de 4 ticks", ciclos_listo));
    recibir("y despues del ruido sigue recibiendo bien", 8'h6B, TICKS_BIT);

    // las tramas de la app van con un solo bit de parada entre byte y byte cuando no hay espaciado
    limpiar_conteo = 1'b1;
    ciclo();
    limpiar_conteo = 1'b0;
    fork
      begin
        mandar(LINEA, 8'hA5, TICKS_BIT);
        mandar(LINEA, 8'h3C, TICKS_BIT);
      end
      begin
        esperar_listo("el primero de dos bytes pegados", 8'hA5);
        ciclo();
        esperar_listo("y el segundo no se pierde", 8'h3C);
      end
    join
    repeat (TICKS_BIT) ciclo();

    // la PC y la tarjeta nunca tienen exactamente el mismo baudaje
    recibir("un emisor 3% mas rapido igual se entiende", 8'hC3, TICKS_BIT * 97 / 100);
    recibir("y uno 3% mas lento tambien", 8'h3C, TICKS_BIT * 103 / 100);

    // a 25 MHz el divisor redondeado se corre 3.1%, el doc dice que todavia cae dentro del ultimo bit
    fork
      mandar(LINEA_25, 8'h96, TICKS_BIT_25MHZ);
      begin
        int n;
        n = 0;
        while (!listo_25 && n < TICKS_BIT_25MHZ * 20) begin
          ciclo();
          n++;
        end
        anotar("con los divisores de 25 MHz todavia recibe", listo_25 === 1'b1 && dato_25 === 8'h96,
               $sformatf("esperaba 96 y dio %02h con listo=%0b", dato_25, listo_25));
      end
    join

    // a 10 MHz el desfase pasa de medio bit antes del ultimo dato, el bit 7 se muestrea encima del 6
    mandar(LINEA_10, 8'h40, TICKS_BIT_10MHZ);
    repeat (TICKS_BIT_10MHZ * 2) ciclo();
    anotar("con los divisores de 10 MHz ya no recibe, como dice el doc", dato_10 !== 8'h40,
           $sformatf("dio %02h, se esperaba un byte corrido", dato_10));

    // el reset a media trama tiene que dejar el receptor listo para la siguiente, sin arrastrar bits viejos
    fork
      mandar(LINEA, 8'hFF, TICKS_BIT);
      begin
        repeat (TICKS_BIT * 4) ciclo();
        rst_tb = 1'b1;
        ciclo();
        rst_tb = 1'b0;
      end
    join
    anotar("el reset a media trama limpia el dato", o_dato_tb === 8'h00,
           $sformatf("o_dato dio %02h", o_dato_tb));
    repeat (TICKS_BIT * 2) ciclo();
    recibir("y despues del reset recibe normal", 8'h81, TICKS_BIT);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_uart_rx termino con fallos");
    $finish;
  end

endmodule
