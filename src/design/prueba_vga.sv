// Top de prueba fisica del VGA, sin procesador. Solo usa generador_relojes y periferico_vga: un
// contador recorre las 300 casillas al salir del reinicio y escribe un patron fijo por el puerto del
// CPU (write_enable_i, addr_i, wdata_i), igual que lo haria un sw. Si la imagen sale bien, el PLL, el
// barrido y la escritura del VGA funcionan por su cuenta.
//
//   make bitstream SYNTH_TOP=prueba_vga
//   make program BIT=src/build/prueba_vga.bit
//
// Patron en la cuadricula de 20 x 15, con la misma distribucion que la pantalla del juego:
//   - fondo negro (101) y en la fila 1 las barras del HUD, verde (110) y magenta (111)
//   - dos tableros de 8 x 8 en agua (000) con el bit de borde (bit 3) encendido, en las filas 3 a 10 y las
//     columnas 1 a 8 y 11 a 18, para ver las lineas del grid
//   - casillas de ejemplo con borde: un barco de 4 (001) y una vista previa de 3 (100) en el tablero
//     izquierdo, un impacto (010) y dos fallos (011) en el derecho
//
// LEDs: LD0 locked del PLL, LD1 patron ya escrito, LD2 parpadea a 1,5 Hz con clk_pix
module prueba_vga (
  input  logic       clk, // 100 MHz, pin W5

  output logic [3:0] vga_r_o,
  output logic [3:0] vga_g_o,
  output logic [3:0] vga_b_o,
  output logic       vga_hsync_o,
  output logic       vga_vsync_o,

  output logic [2:0] led
  );

  localparam int COLUMNAS = 20;
  localparam int FILAS = 15;

  // Esquina superior izquierda de cada tablero en la pantalla, los mismos TAB_FILA0 y TAB_COL0 de programa.s
  localparam int TAB_FILA0 = 3;
  localparam int TAB_COL0_J1 = 1;
  localparam int TAB_COL0_J2 = 11;
  localparam int TAB_LADO = 8;
  localparam int HUD_FILA = 1;

  localparam logic [2:0] C_AGUA = 3'b000;
  localparam logic [2:0] C_BARCO = 3'b001;
  localparam logic [2:0] C_IMPACTO = 3'b010;
  localparam logic [2:0] C_FALLO = 3'b011;
  localparam logic [2:0] C_CURSOR = 3'b100;
  localparam logic [2:0] C_FONDO = 3'b101;
  localparam logic [2:0] C_J1 = 3'b110;
  localparam logic [2:0] C_J2 = 3'b111;

  // ---------------------------------------------------------------- relojes y reinicio, igual que en top

  logic clk_sys;
  logic clk_pix;
  logic pll_locked;

  generador_relojes u_generador_relojes (
    .clk_i     (clk),
    .clk_sys_o (clk_sys),
    .clk_pix_o (clk_pix),
    .locked_o  (pll_locked)
  );

  logic [1:0] sinc_rst = 2'b11;
  logic       rst;

  always_ff @(posedge clk_sys) sinc_rst <= {sinc_rst[0], ~pll_locked};

  assign rst = sinc_rst[1];

  // ---------------------------------------------------------------- escritor del patron

  // Recorre fila y columna, una casilla por ciclo de clk_sys. 300 ciclos, 9 us
  logic [3:0] fila;
  logic [4:0] col;
  logic       escribiendo;

  always_ff @(posedge clk_sys) begin
    if (rst) begin
      fila <= '0;
      col <= '0;
      escribiendo <= 1'b1;
    end
    else if (escribiendo) begin
      if (col == COLUMNAS - 1) begin
        col <= '0;
        if (fila == FILAS - 1) escribiendo <= 1'b0;
        else fila <= fila + 4'd1;
      end
      else col <= col + 5'd1;
    end
  end

  logic       en_fila_tablero;
  logic       en_j1;
  logic       en_j2;
  logic [3:0] tf; // fila dentro del tablero
  logic [4:0] tc1; // columna dentro del tablero del Jugador 1
  logic [4:0] tc2; // columna dentro del tablero del Jugador 2
  logic [2:0] color;
  logic       borde;
  logic [8:0] indice;

  assign en_fila_tablero = (fila >= TAB_FILA0) && (fila < TAB_FILA0 + TAB_LADO);
  assign en_j1 = en_fila_tablero && (col >= TAB_COL0_J1) && (col < TAB_COL0_J1 + TAB_LADO);
  assign en_j2 = en_fila_tablero && (col >= TAB_COL0_J2) && (col < TAB_COL0_J2 + TAB_LADO);
  assign tf = fila - 4'(TAB_FILA0);
  assign tc1 = col - 5'(TAB_COL0_J1);
  assign tc2 = col - 5'(TAB_COL0_J2);
  assign borde = en_j1 || en_j2;

  always_comb begin
    color = C_FONDO;
    if (fila == HUD_FILA && col >= TAB_COL0_J1 && col < TAB_COL0_J1 + TAB_LADO) color = C_J1;
    else if (fila == HUD_FILA && col >= TAB_COL0_J2 && col < TAB_COL0_J2 + TAB_LADO) color = C_J2;
    else if (en_j1) begin
      color = C_AGUA;
      if (tf == 0 && tc1 <= 3) color = C_BARCO; // barco de 4 en (0,0)-(0,3)
      else if (tc1 == 5 && tf >= 2 && tf <= 4) color = C_CURSOR; // vista previa vertical en (2,5)-(4,5)
    end
    else if (en_j2) begin
      color = C_AGUA;
      if (tf == 2 && tc2 == 3) color = C_IMPACTO;
      else if (tf == 5 && (tc2 == 1 || tc2 == 6)) color = C_FALLO;
    end
  end

  // fila * 20 + col, la misma cuenta que hace el programa para la direccion de una casilla
  assign indice = {1'b0, fila, 4'b0000} + {3'b000, fila, 2'b00} + {4'b0000, col};

  // ---------------------------------------------------------------- periferico VGA

  periferico_vga u_periferico_vga (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (escribiendo && !rst),
    .addr_i         (indice),
    .wdata_i        ({28'b0, borde, color}),
    .rdata_o        (),
    .clk_pix_i      (clk_pix),
    .vga_hsync_o    (vga_hsync_o),
    .vga_vsync_o    (vga_vsync_o),
    .vga_r_o        (vga_r_o),
    .vga_g_o        (vga_g_o),
    .vga_b_o        (vga_b_o)
  );

  // ---------------------------------------------------------------- LEDs de diagnostico

  // 25 MHz / 2^24 = 1,5 Hz. Si parpadea, el PLL esta dando clk_pix
  logic [23:0] latido = '0;

  always_ff @(posedge clk_pix) latido <= latido + 24'd1;

  assign led[0] = pll_locked;
  assign led[1] = !escribiendo && !rst;
  assign led[2] = latido[23];

endmodule
