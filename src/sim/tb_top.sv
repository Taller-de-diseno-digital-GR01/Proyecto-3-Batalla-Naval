`timescale 1ns/1ps

// Sistema completo con el programa real (sw/programa.hex). El PLL va con el modelo de simulacion de
// generador_relojes.sv, con las mismas frecuencias que en la tarjeta. La prueba no mira el
// procesador por dentro: arranca la partida, hace de aplicacion de PC por la UART y de Jugador 1
// con los botones, y revisa lo que queda en las salidas, en la RAM y en la memoria de video.
module tb_top;

  // 33,33 MHz y 115200 baudios dan TICKS_BIT = 289 ciclos de 30 ns
  localparam int BIT_NS = 289 * 30;

  // Direcciones de palabra en la RAM, de los .equ de programa.s divididos entre 4
  localparam int RAM_TABLERO_J1 = 'h000 / 4;
  localparam int RAM_TABLERO_J2 = 'h100 / 4;
  localparam int RAM_COLOCADOS_J1 = 'h208 / 4;
  localparam int RAM_COLOCADOS_J2 = 'h20C / 4;

  // Casilla de pantalla de la casilla (0, columna) de cada tablero: (3 + fila) * 20 + 1 + 10 * jugador + columna
  localparam int VGA_J1_FILA0 = 3 * 20 + 1;
  localparam int VGA_J2_FILA0 = 3 * 20 + 11;

  localparam logic [2:0] C_AGUA = 3'd0;
  localparam logic [2:0] C_BARCO = 3'd1;
  localparam logic [2:0] C_CURSOR = 3'd4;
  localparam logic [2:0] SND_INVALIDA = 3'd4;

  // Bits de botones en el mismo orden que el registro de estado del periferico de entradas
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

  // build/ es el directorio desde donde corre vvp
  top #(.ARCHIVO_HEX("../../sw/programa.hex")) dut (
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

  // Receptor de la PC, corre aparte y guarda cada byte que sale por tx_o
  logic [7:0] bytes_pc [0:63];
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
        if (recibidos < 64) bytes_pc[recibidos] = dato;
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

  // Trama de 5 bytes con el checksum de protocolo.py, con una pausa entre bytes como la aplicacion
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

  // Espera a que la PC tenga 5 bytes mas desde 'desde' y los compara con la trama esperada
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

  // Mantiene el boton 300 us y lo suelta otros 300 us. Tiene que pasar de la vuelta mas larga del lazo,
  // un repintado del tablero tarda unos 100 us a 33 MHz y una presion mas corta se pierde completa adentro.
  // En la tarjeta una presion dura decenas de milisegundos
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

  function automatic logic [2:0] color_vga(input int casilla);
    return dut.u_periferico_vga.memoria_video[casilla][2:0];
  endfunction

  function automatic logic [31:0] ram(input int palabra);
    return dut.u_ram.mem[palabra];
  endfunction

  // Cuenta los pulsos de hsync durante un tiempo, para ver que el barrido corre con clk_pix
  int pulsos_hsync = 0;
  always @(negedge vga_hsync) pulsos_hsync++;

  // ---------------------------------------------------------------- prueba

  initial begin
    int antes;
    int marca;

    // Reinicio, sale solo cuando el modelo del PLL engancha
    #100;
    anotar("el sistema arranca en reinicio mientras el PLL no engancha", dut.rst === 1'b1,
           $sformatf("rst dio %0b", dut.rst));
    wait (dut.rst === 1'b0);
    anotar("el reinicio baja despues del locked", dut.pll_locked === 1'b1,
           $sformatf("locked dio %0b", dut.pll_locked));

    // Arranque: el programa limpia todo, avisa a la PC y queda en colocacion
    chequear_trama("la primera trama es Estado, fase de colocacion", 0, 8'h20, 8'h00, 8'h00);
    anotar("el LED marca la fase de colocacion", led === 3'b001,
           $sformatf("led dio %03b", led));
    anotar("la vista previa del barco 0 queda en el tablero del Jugador 1",
           color_vga(VGA_J1_FILA0) === C_CURSOR && color_vga(VGA_J1_FILA0 + 3) === C_CURSOR &&
           color_vga(VGA_J1_FILA0 + 4) === C_AGUA,
           $sformatf("casillas (0,0), (0,3) y (0,4) dieron %0d, %0d y %0d",
                     color_vga(VGA_J1_FILA0), color_vga(VGA_J1_FILA0 + 3), color_vga(VGA_J1_FILA0 + 4)));

    // 7 segmentos: un solo anodo activo y el digito en cero (abcdef encendidos, g apagado)
    anotar("el display muestra 00 00 de partidas ganadas",
           seg === 7'b1000000 && (an === 4'b1110 || an === 4'b1101 || an === 4'b1011 || an === 4'b0111),
           $sformatf("seg dio %07b y an %04b", seg, an));

    antes = pulsos_hsync;
    #100_000;
    // Una linea dura 800 pixeles de 40 ns, 32 us, en 100 us caben 3
    anotar("el VGA genera hsync con el reloj de pixel", pulsos_hsync - antes == 3,
           $sformatf("en 100 us hubo %0d pulsos de hsync", pulsos_hsync - antes));

    // Jugador 2 por la UART: barco 0 horizontal en (0,0)
    marca = recibidos;
    enviar_trama(8'h10, 8'h00, 8'h00);
    chequear_trama("la colocacion valida del Jugador 2 se acepta", marca, 8'h21, 8'h00, 8'h00);
    anotar("el barco del Jugador 2 queda en su tablero en RAM",
           ram(RAM_TABLERO_J2) === 32'd1 && ram(RAM_TABLERO_J2 + 3) === 32'd1 && ram(RAM_TABLERO_J2 + 4) === 32'd0,
           $sformatf("casillas (0,0), (0,3) y (0,4) dieron %0h, %0h y %0h",
                     ram(RAM_TABLERO_J2), ram(RAM_TABLERO_J2 + 3), ram(RAM_TABLERO_J2 + 4)));
    anotar("y colocados_j2 marca el barco 0", ram(RAM_COLOCADOS_J2) === 32'd1,
           $sformatf("colocados_j2 dio %0h", ram(RAM_COLOCADOS_J2)));
    anotar("el barco del Jugador 2 no se pinta en el VGA", color_vga(VGA_J2_FILA0) === C_AGUA,
           $sformatf("casilla (0,0) del Jugador 2 dio %0d", color_vga(VGA_J2_FILA0)));

    marca = recibidos;
    enviar_trama(8'h10, 8'h00, 8'h33);
    chequear_trama("el mismo barco otra vez se rechaza como repetido", marca, 8'h21, 8'h00, 8'h03);

    // Jugador 1 con los botones: cursor una columna a la derecha y confirmar
    presionar(BTN_DER);
    presionar(BTN_OK);
    #200_000; // repintado del tablero
    anotar("el barco 0 del Jugador 1 queda en (0,1)-(0,4) en RAM",
           ram(RAM_TABLERO_J1) === 32'd0 && ram(RAM_TABLERO_J1 + 1) === 32'd1 &&
           ram(RAM_TABLERO_J1 + 4) === 32'd1 && ram(RAM_TABLERO_J1 + 5) === 32'd0,
           $sformatf("casillas (0,0), (0,1), (0,4) y (0,5) dieron %0h, %0h, %0h y %0h",
                     ram(RAM_TABLERO_J1), ram(RAM_TABLERO_J1 + 1), ram(RAM_TABLERO_J1 + 4), ram(RAM_TABLERO_J1 + 5)));
    anotar("y colocados_j1 pasa a 1", ram(RAM_COLOCADOS_J1) === 32'd1,
           $sformatf("colocados_j1 dio %0h", ram(RAM_COLOCADOS_J1)));
    // La vista previa del barco 1 (largo 3) tapa (0,1)-(0,3) y deja ver el barco en (0,4)
    anotar("el VGA pinta el barco y la vista previa del barco 1",
           color_vga(VGA_J1_FILA0 + 1) === C_CURSOR && color_vga(VGA_J1_FILA0 + 4) === C_BARCO,
           $sformatf("casillas (0,1) y (0,4) dieron %0d y %0d",
                     color_vga(VGA_J1_FILA0 + 1), color_vga(VGA_J1_FILA0 + 4)));

    // El barco 1 en el mismo lugar traslapa: suena la melodia de colocacion invalida
    presionar(BTN_OK);
    anotar("una colocacion invalida del Jugador 1 dispara el buzzer", dut.buzzer_dout[2:0] === SND_INVALIDA,
           $sformatf("el registro del buzzer dio %0d", dut.buzzer_dout[2:0]));
    anotar("y no cuenta como colocado", ram(RAM_COLOCADOS_J1) === 32'd1,
           $sformatf("colocados_j1 dio %0h", ram(RAM_COLOCADOS_J1)));
    anotar("el LED sigue en colocacion", led === 3'b001, $sformatf("led dio %03b", led));

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_top termino con fallos");
    $finish;
  end

  // Por si el programa se queda trabado y nunca llega una trama
  initial begin
    #20_000_000;
    $fatal(1, "tb_top no termino en 20 ms");
  end

endmodule
