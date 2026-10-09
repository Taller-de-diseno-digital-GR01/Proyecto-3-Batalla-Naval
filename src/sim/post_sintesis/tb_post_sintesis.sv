`timescale 1ns/1ps

// Sistema completo despues de la sintesis: el top es el netlist que sale de synth_xilinx (LUT, FDRE,
// CARRY4, RAM64M/RAM128X1D, MUXF7...) y se simula con los modelos de esas primitivas de yosys
// (cells_sim.v) y el de PLLE2_BASE de esta carpeta. Corre con 'make post-sintesis'.
//
// En el netlist ya no hay jerarquia ni nombres internos, asi que la prueba solo mira pines: hace de
// aplicacion de PC por rx/tx y de Jugador 1 con los botones, y revisa las tramas que salen por tx, el
// LED, los displays, el buzzer y hsync. Cubre el arranque del programa desde la ROM, la colocacion de las
// dos flotas (con un rechazo de cada jugador), el inicio de la batalla y la validacion de disparos:
// impacto y repetido del Jugador 1, fallo y repetido del Jugador 2.
//
// Sin POST_SINTESIS el mismo testbench corre sobre el RTL, para comparar.
module tb_post_sintesis;

  // 33,33 MHz y 115200 baudios dan TICKS_BIT = 289 ciclos de 30 ns
  localparam int BIT_NS = 289 * 30;

  localparam int BTN_ABAJO = 1;
  localparam int BTN_DER = 3;
  localparam int BTN_OK = 5;

  logic clk_tb = 1'b0;
  logic [6:0] botones = '0;
  logic rx_tb = 1'b1;
  logic tx_tb;
  logic [3:0] vga_r, vga_g, vga_b;
  logic vga_hsync, vga_vsync;
  logic [6:0] seg;
  logic [3:0] an;
  logic dp;
  logic [2:0] led;
  logic buzzer;

  int pruebas = 0;
  int errores = 0;

`ifdef POST_SINTESIS
  top dut (
`else
  top #(.ARCHIVO_HEX("../../sw/programa.hex")) dut (
`endif
    .clk         (clk_tb),
    .btn_arriba  (botones[0]),
    .btn_abajo   (botones[1]),
    .btn_izq     (botones[2]),
    .btn_der     (botones[3]),
    .btn_sel     (botones[4]),
    .btn_ok      (botones[5]),
    .btn_rst     (botones[6]),
    .rx_i        (rx_tb),
    .tx_o        (tx_tb),
    .vga_r_o     (vga_r),
    .vga_g_o     (vga_g),
    .vga_b_o     (vga_b),
    .vga_hsync_o (vga_hsync),
    .vga_vsync_o (vga_vsync),
    .seg         (seg),
    .an          (an),
    .dp          (dp),
    .led         (led),
    .buzzer      (buzzer)
  );

  always #5 clk_tb = ~clk_tb; // 100 MHz, como el oscilador de la Basys 3

  // ---------------------------------------------------------------- lado de la PC

  logic [7:0] bytes_pc [0:255];
  int recibidos = 0;

  initial begin
    logic [7:0] dato;
    forever begin
      @(negedge tx_tb);
      #(BIT_NS / 2);
      if (tx_tb === 1'b0) begin
        for (int i = 0; i < 8; i++) begin
          #(BIT_NS);
          dato[i] = tx_tb;
        end
        #(BIT_NS);
        if (recibidos < 256) bytes_pc[recibidos] = dato;
        recibidos++;
      end
    end
  end

  task automatic enviar_byte(input logic [7:0] dato);
    rx_tb = 1'b0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      rx_tb = dato[i];
      #(BIT_NS);
    end
    rx_tb = 1'b1;
    #(BIT_NS);
  endtask

  task automatic enviar_trama(input logic [7:0] tipo, input logic [7:0] d1, input logic [7:0] d2);
    logic [7:0] trama [0:4];
    trama[0] = 8'hAA;
    trama[1] = tipo;
    trama[2] = d1;
    trama[3] = d2;
    trama[4] = tipo ^ d1 ^ d2;
    for (int i = 0; i < 5; i++) begin
      enviar_byte(trama[i]);
      #20_000;
    end
  endtask

  task automatic chequear_trama(input string nombre, input int desde,
                                input logic [7:0] tipo, input logic [7:0] d1, input logic [7:0] d2);
    logic [39:0] esperada;
    logic [39:0] vista;
    int espera_us;
    espera_us = 0;
    while (recibidos < desde + 5 && espera_us < 3000) begin
      #1000;
      espera_us++;
    end
    esperada = {8'hAA, tipo, d1, d2, tipo ^ d1 ^ d2};
    vista = (recibidos >= desde + 5) ?
            {bytes_pc[desde], bytes_pc[desde+1], bytes_pc[desde+2], bytes_pc[desde+3], bytes_pc[desde+4]} : 'x;
    anotar(nombre, vista === esperada,
           $sformatf("esperaba %010h y llego %010h (%0d bytes en total)", esperada, vista, recibidos));
  endtask

  // ---------------------------------------------------------------- lado del Jugador 1

  task automatic presionar(input int boton);
    botones[boton] = 1'b1;
    #300_000;
    botones[boton] = 1'b0;
    #300_000;
  endtask

  // ---------------------------------------------------------------- utilidades

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

  int pulsos_hsync = 0;
  always @(negedge vga_hsync) pulsos_hsync++;

  int flancos_buzzer = 0;
  always @(posedge buzzer) flancos_buzzer++;

  // ---------------------------------------------------------------- prueba

  initial begin
    int antes;
    int marca;

    // Arranque: el programa sale de la ROM, limpia todo y avisa a la PC
    chequear_trama("la primera trama es Estado, fase de colocacion", 0, 8'h20, 8'h00, 8'h00);
    anotar("el LED marca la fase de colocacion", led === 3'b001, $sformatf("led dio %03b", led));
    anotar("el display muestra 00 00",
           seg === 7'b1000000 && (an === 4'b1110 || an === 4'b1101 || an === 4'b1011 || an === 4'b0111),
           $sformatf("seg dio %07b y an %04b", seg, an));

    antes = pulsos_hsync;
    #100_000;
    anotar("el VGA genera hsync con el reloj de pixel", pulsos_hsync - antes == 3,
           $sformatf("en 100 us hubo %0d pulsos de hsync", pulsos_hsync - antes));

    // Jugador 1 con los botones: barco 0 en (0,0), y el barco 1 en el mismo lugar se traslapa
    presionar(BTN_OK);
    antes = flancos_buzzer;
    presionar(BTN_OK);
    // El sonido de colocacion invalida es grave (A3, 220 Hz, un flanco cada 4,5 ms)
    #12_000_000;
    anotar("la colocacion invalida del Jugador 1 hace sonar el buzzer", flancos_buzzer - antes >= 2,
           $sformatf("el buzzer dio %0d flancos de subida en 12,6 ms", flancos_buzzer - antes));
    presionar(BTN_ABAJO);
    presionar(BTN_OK);
    presionar(BTN_ABAJO);
    presionar(BTN_OK);

    // Jugador 2 por la UART: barcos en las filas 0, 2 y 4, con un repetido en el medio
    marca = recibidos;
    enviar_trama(8'h10, 8'h00, 8'h00);
    chequear_trama("el barco 0 del Jugador 2 se acepta", marca, 8'h21, 8'h00, 8'h00);
    marca = recibidos;
    enviar_trama(8'h10, 8'h00, 8'h33);
    chequear_trama("el mismo barco otra vez se rechaza como repetido", marca, 8'h21, 8'h00, 8'h03);
    marca = recibidos;
    enviar_trama(8'h10, 8'h01, 8'h20);
    chequear_trama("el barco 1 del Jugador 2 se acepta", marca, 8'h21, 8'h01, 8'h00);
    marca = recibidos;
    enviar_trama(8'h10, 8'h02, 8'h40);
    chequear_trama("el barco 2 del Jugador 2 se acepta", marca, 8'h21, 8'h02, 8'h00);
    chequear_trama("arranca la batalla", marca + 5, 8'h20, 8'h01, 8'h00);
    chequear_trama("con el turno del Jugador 1", marca + 10, 8'h20, 8'h02, 8'h00);
    anotar("el LED pasa a batalla", led === 3'b010, $sformatf("led dio %03b", led));

    // Disparo del Jugador 1 en (0,0), donde esta el barco 0 del Jugador 2
    marca = recibidos;
    presionar(BTN_OK);
    chequear_trama("el disparo del Jugador 1 en (0,0) es impacto", marca, 8'h23, 8'h00, 8'h00);
    chequear_trama("y pasa el turno al Jugador 2", marca + 5, 8'h20, 8'h02, 8'h01);

    // Disparo del Jugador 2 en (5,5), agua en el tablero del Jugador 1
    marca = recibidos;
    enviar_trama(8'h11, 8'h55, 8'h00);
    chequear_trama("el disparo del Jugador 2 en (5,5) es fallo", marca, 8'h22, 8'h55, 8'h01);
    chequear_trama("y vuelve el turno al Jugador 1", marca + 5, 8'h20, 8'h02, 8'h00);

    // El Jugador 1 repite (0,0): se ignora y no cambia el turno
    marca = recibidos;
    presionar(BTN_OK);
    #2_000_000;
    anotar("el disparo repetido del Jugador 1 no manda nada ni cambia el turno", recibidos == marca,
           $sformatf("llegaron %0d bytes", recibidos - marca));

    // Sigue siendo su turno: (0,1) tambien es del barco 0
    presionar(BTN_DER);
    presionar(BTN_OK);
    chequear_trama("el disparo del Jugador 1 en (0,1) es impacto", marca, 8'h23, 8'h01, 8'h00);
    chequear_trama("y pasa el turno al Jugador 2", marca + 5, 8'h20, 8'h02, 8'h01);

    // El Jugador 2 repite (5,5): la FPGA contesta repetido y el turno sigue siendo suyo
    marca = recibidos;
    enviar_trama(8'h11, 8'h55, 8'h00);
    chequear_trama("el disparo repetido del Jugador 2 se contesta como repetido", marca, 8'h22, 8'h55, 8'h03);
    #2_000_000;
    anotar("y no cambia el turno", recibidos == marca + 5,
           $sformatf("llegaron %0d bytes despues de la respuesta", recibidos - marca - 5));

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_post_sintesis termino con fallos");
    $finish;
  end

  initial begin
    #100_000_000;
    $fatal(1, "tb_post_sintesis no termino en 100 ms");
  end

endmodule
