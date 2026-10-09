`timescale 1ns/1ps

module tb_periferico_buzzer;

  // reescalado, a 100 kHz una unidad de 50 ms son 5000 ciclos y el medio periodo mas largo, A3, 227
  localparam CLK_FREQ_HZ = 100_000;
  localparam UNIDAD_MS = 50;
  localparam U = CLK_FREQ_HZ / 1000 * UNIDAD_MS;

  localparam logic [1:0] ADDR_SONIDO = 2'b00;
  localparam SILENCIO = 0;
  localparam IMPACTO = 1;
  localparam FALLO = 2;
  localparam HUNDIDO = 3;
  localparam INVALIDA = 4;
  localparam VICTORIA = 5;

  logic clk_tb;
  logic rst_tb;
  logic we_tb;
  logic [1:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic buzzer_tb;

  int pruebas = 0;
  int errores = 0;
  int ciclos = 0;

  periferico_buzzer #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .UNIDAD_MS(UNIDAD_MS)) dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .buzzer_o(buzzer_tb)
  );

  // solo para leerle los divisores a 100 MHz, nunca corre
  periferico_buzzer dut_100 (.clk_i(1'b0), .rst_i(1'b1), .write_enable_i(1'b0), .addr_i(2'b00), .wdata_i(32'b0), .rdata_o(), .buzzer_o());

  always #5 clk_tb = ~clk_tb;

  always @(posedge clk_tb) ciclos <= ciclos + 1;

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
    addr_tb = ADDR_SONIDO;
  endtask

  task automatic chequear_reg(input string nombre, input logic [31:0] esperado);
    addr_tb = ADDR_SONIDO;
    #1;
    anotar(nombre, rdata_tb === esperado,
           $sformatf("esperaba %08h y dio %08h", esperado, rdata_tb));
  endtask

  task automatic esperar_hasta(input int t);
    while (ciclos < t) ciclo();
  endtask

  // la tabla de secuenciador_melodia.md escrita aparte del RTL, hz = 0 es silencio y dur = 0 es fin
  task automatic paso_esperado(input int s, input int p, output int hz, output int dur);
    hz = 0;
    dur = 0;
    case (s)
      IMPACTO: case (p)
        0: begin hz = 784; dur = 1; end
        1: begin hz = 1047; dur = 1; end
        2: begin hz = 1319; dur = 2; end
      endcase
      FALLO: case (p)
        0: begin hz = 392; dur = 2; end
        1: begin hz = 330; dur = 2; end
        2: begin hz = 262; dur = 3; end
      endcase
      HUNDIDO: case (p)
        0: begin hz = 1319; dur = 1; end
        1: begin hz = 1047; dur = 1; end
        2: begin hz = 784; dur = 1; end
        3: begin hz = 659; dur = 1; end
        4: begin hz = 523; dur = 1; end
        5: begin hz = 0; dur = 1; end
        6: begin hz = 523; dur = 4; end
      endcase
      INVALIDA: case (p)
        0: begin hz = 220; dur = 2; end
        1: begin hz = 0; dur = 1; end
        2: begin hz = 220; dur = 2; end
      endcase
      VICTORIA: case (p)
        0: begin hz = 523; dur = 2; end
        1: begin hz = 659; dur = 2; end
        2: begin hz = 784; dur = 2; end
        3: begin hz = 1047; dur = 4; end
        4: begin hz = 0; dur = 1; end
        5: begin hz = 784; dur = 1; end
        6: begin hz = 1047; dur = 7; end
      endcase
      default: ;
    endcase
  endtask

  // ciclos entre la subida y la bajada de buzzer_o, -1 si no hubo onda en el tiempo dado
  task automatic medir_medio_periodo(input int limite, output int medido);
    int n;
    medido = -1;
    n = 0;
    while (buzzer_tb !== 1'b0 && n < limite) begin ciclo(); n++; end
    while (buzzer_tb !== 1'b1 && n < limite) begin ciclo(); n++; end
    if (n >= limite) return;
    medido = 0;
    while (buzzer_tb === 1'b1 && n < limite) begin ciclo(); n++; medido++; end
    if (n >= limite) medido = -1;
  endtask

  task automatic chequear_silencio(input string nombre, input int duracion);
    int subidas;
    subidas = 0;
    for (int c = 0; c < duracion; c++) begin
      ciclo();
      if (buzzer_tb !== 1'b0) subidas++;
    end
    anotar(nombre, subidas == 0, $sformatf("buzzer_o estuvo alto %0d ciclos", subidas));
  endtask

  // escribe el codigo y recorre la melodia paso por paso midiendo la nota en la mitad de cada uno
  task automatic tocar(input string nombre, input int s, input logic [31:0] dato);
    int t0;
    int inicio;
    int hz;
    int dur;
    int medido;
    int esperado;
    int p;
    escribir(ADDR_SONIDO, dato);
    t0 = ciclos;
    chequear_reg($sformatf("%s, el registro guarda el codigo %0d", nombre, s), s);
    inicio = t0;
    p = 0;
    paso_esperado(s, p, hz, dur);
    while (dur != 0) begin
      esperar_hasta(inicio + U / 4);
      if (hz == 0) begin
        chequear_silencio($sformatf("%s, paso %0d es un silencio", nombre, p), U / 2);
      end
      else begin
        esperado = CLK_FREQ_HZ / (2 * hz);
        medir_medio_periodo(U / 2, medido);
        anotar($sformatf("%s, paso %0d suena a %0d Hz", nombre, p, hz), medido == esperado,
               $sformatf("medio periodo de %0d ciclos, esperaba %0d", medido, esperado));
      end
      inicio += dur * U;
      p++;
      paso_esperado(s, p, hz, dur);
    end
    esperar_hasta(inicio - 2);
    chequear_reg($sformatf("%s, dos ciclos antes del final sigue sonando", nombre), s);
    esperar_hasta(inicio + 2);
    chequear_reg($sformatf("%s, al terminar el registro vuelve solo a cero", nombre), 0);
    chequear_silencio($sformatf("%s, y el buzzer se queda callado", nombre), U);
  endtask

  initial begin
    $dumpfile("tb_periferico_buzzer.vcd");
    $dumpvars(0, tb_periferico_buzzer);
  end

  initial begin
    clk_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = ADDR_SONIDO;
    wdata_tb = 32'b0;

    anotar("a 100 MHz los N calzan con la tabla del doc",
           dut_100.u_secuenciador.N_A3 == 227271 && dut_100.u_secuenciador.N_G5 == 63774 && dut_100.u_secuenciador.N_G6 == 31886,
           $sformatf("A3 %0d, G5 %0d, G6 %0d", dut_100.u_secuenciador.N_A3, dut_100.u_secuenciador.N_G5, dut_100.u_secuenciador.N_G6));
    anotar("y el mas grave cabe en los 18 bits de n_nota", dut_100.u_secuenciador.N_A3 < 2 ** 18,
           $sformatf("A3 da %0d", dut_100.u_secuenciador.N_A3));
    anotar("la unidad de 50 ms son 5 millones de ciclos", dut_100.u_secuenciador.CICLOS_UNIDAD == 5_000_000,
           $sformatf("dio %0d", dut_100.u_secuenciador.CICLOS_UNIDAD));

    repeat (3) ciclo();
    chequear_reg("el reset deja el registro en cero", 0);
    rst_tb = 1'b0;
    chequear_silencio("en reposo el buzzer no suena", U);
    chequear_reg("y el registro sigue en cero aunque o_fin este alto", 0);

    tocar("impacto", IMPACTO, IMPACTO);
    tocar("fallo", FALLO, FALLO);
    tocar("hundido", HUNDIDO, HUNDIDO);
    tocar("invalida", INVALIDA, INVALIDA);
    tocar("victoria", VICTORIA, VICTORIA);

    tocar("con basura arriba", IMPACTO, 32'hFFFF_FFF9);

    // una escritura a media melodia la corta y la nueva arranca desde su primer paso
    escribir(ADDR_SONIDO, VICTORIA);
    repeat (U + U / 2) ciclo();
    tocar("fallo encima de la victoria", FALLO, FALLO);

    escribir(ADDR_SONIDO, HUNDIDO);
    repeat (U / 2) ciclo();
    escribir(ADDR_SONIDO, SILENCIO);
    anotar("escribir cero apaga el buzzer en el mismo ciclo", buzzer_tb === 1'b0,
           $sformatf("buzzer_o dio %0b", buzzer_tb));
    chequear_reg("y el registro queda en cero", 0);
    chequear_silencio("sin que vuelva a sonar el resto del hundido", 6 * U);

    for (int s = 6; s < 8; s++) begin
      escribir(ADDR_SONIDO, s);
      ciclo();
      chequear_reg($sformatf("el codigo %0d no tiene melodia y el registro se limpia solo", s), 0);
      chequear_silencio($sformatf("y con %0d no suena nada", s), U);
    end

    escribir(2'b01, VICTORIA);
    chequear_reg("una escritura en la direccion 01 no arranca nada", 0);
    chequear_silencio("ni hace sonar el buzzer", U);
    addr_tb = 2'b01;
    #1;
    anotar("y leerla da cero", rdata_tb === 32'h0, $sformatf("dio %08h", rdata_tb));
    addr_tb = ADDR_SONIDO;

    escribir(ADDR_SONIDO, VICTORIA);
    repeat (3 * U) ciclo();
    rst_tb = 1'b1;
    ciclo();
    anotar("el reset a media melodia apaga el buzzer", buzzer_tb === 1'b0,
           $sformatf("buzzer_o dio %0b", buzzer_tb));
    rst_tb = 1'b0;
    chequear_reg("y deja el registro en cero", 0);
    chequear_silencio("sin que la victoria siga despues", 16 * U);

    tocar("despues del reset", INVALIDA, INVALIDA);

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_buzzer termino con fallos");
    $finish;
  end

endmodule
