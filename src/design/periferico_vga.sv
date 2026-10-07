// Los puertos del bus llevan sufijo _i/_o porque la seccion 4.5.5 del enunciado los define asi, es la excepcion al prefijo del resto del repo
// addr_i es de 9 bits y no de 2, el enunciado lo permite para el VGA porque se comporta como memoria
module periferico_vga #(parameter WIDTH = 32) (
  input logic clk_i, // reloj del sistema, el mismo del procesador
  input logic rst_i,
  input logic write_enable_i,
  input logic [8:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  input logic clk_pix_i, // 25 MHz desde el PLL del top
  output logic vga_hsync_o,
  output logic vga_vsync_o,
  output logic [3:0] vga_r_o,
  output logic [3:0] vga_g_o,
  output logic [3:0] vga_b_o
  );

  // 640 x 480 @ 60 Hz, los numeros son los del estandar, con 25 MHz da 59,52 Hz y los monitores lo aceptan
  localparam int H_VISIBLE = 640; //DEfine el espacio de 640 pixeles
  localparam int H_FRONT = 16; //Front porch - define el tiempo para terminar una línea (pintado espacios en negro)
  localparam int H_SYNC = 96; 
  localparam int H_BACK = 48;//Back porch - Es el tiempo donde se pinta en negro antes de iniciar una línea nueva
  localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

  localparam int V_VISIBLE = 480;
  localparam int V_FRONT = 10;
  localparam int V_SYNC = 2;
  localparam int V_BACK = 33;
  localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

  // 512 palabras es todo el rango 0x0001_1000-0x0001_17FF, la cuadricula de 20 x 15 solo usa las primeras 300
  localparam int PALABRAS = 512;
  localparam int COLUMNAS = 20;

  localparam int COLOR_WIDTH = 3;
  localparam int RGB_WIDTH = 12;

  // Bit 3 de la palabra en 1: la casilla lleva una linea de 1 pixel en su contorno, en LINEA_RGB. Entre dos
  // casillas con borde la linea queda de 2 pixeles. En cero la casilla es un bloque solido, como antes
  localparam int BIT_BORDE = 3;
  localparam logic [RGB_WIDTH-1:0] LINEA_RGB = 12'h000;

  // Texto encima del color de la casilla, en ASCII - 32 (0 es espacio, sin caracter). Glifos de 5 x 7 de
  // fuente_caracteres ampliados x2, 10 x 14 pixeles, en la franja de las filas 10 a 23 de la casilla:
  //   bits [9:4]   caracter de la mitad izquierda (pixeles 0 a 15 de la casilla)
  //   bits [15:10] caracter de la mitad derecha (pixeles 16 a 31)
  //   bit 16       centrado: dibuja solo el caracter de [9:4], en el centro de la casilla
  // Dos caracteres por casilla dan 40 por fila de pantalla. El texto sale en negro sobre los fondos claros
  // y en blanco sobre el resto
  localparam int CAR_LSB = 4;
  localparam int CAR_WIDTH = 6;
  localparam int CAR2_LSB = 10;
  localparam int BIT_CENTRADO = 16;
  localparam logic [3:0] GLIFO_FILA0 = 4'd5; // el glifo arranca en la fila de 2 pixeles 5, pixel 10 de la casilla
  localparam logic [RGB_WIDTH-1:0] TEXTO_CLARO = 12'hFFF;
  localparam logic [RGB_WIDTH-1:0] TEXTO_OSCURO = 12'h000;

  // ---------------------------------------------------------------- memoria de video

  // RAM distribuida y no BRAM, el puerto A se lee combinacional igual que la RAM de datos del nucleo uniciclo,
  // si fuera sincrono el lw recibiria el dato un ciclo tarde
  logic [WIDTH-1:0] memoria_video [0:PALABRAS-1];

  // El reset no la borra, borrar la pantalla es un lazo de software. Arranca en ceros (agua) por la configuracion de la FPGA
  initial begin
    for (int i = 0; i < PALABRAS; i++) memoria_video[i] = '0;
  end

  // Puerto A, dominio clk_i, escritura sincrona y lectura combinacional
  always_ff @(posedge clk_i) begin
    if (write_enable_i) memoria_video[addr_i] <= wdata_i;
  end

  assign rdata_o = memoria_video[addr_i];

  // ---------------------------------------------------------------- reset en el dominio de pixel

  // rst_i viene del dominio clk_i, pasa por dos flip-flops antes de tocar los contadores
  logic rst_meta;
  logic rst_pix;

  always_ff @(posedge clk_pix_i) begin
    rst_meta <= rst_i;
    rst_pix <= rst_meta;
  end

  // ---------------------------------------------------------------- generador de sincronismos

  logic [9:0] h_count;
  logic [9:0] v_count;
  logic fin_linea;
  logic fin_cuadro;

  assign fin_linea = (h_count == H_TOTAL - 1);
  assign fin_cuadro = (v_count == V_TOTAL - 1);

  always_ff @(posedge clk_pix_i) begin
    if (rst_pix) h_count <= '0;
    else if (fin_linea) h_count <= '0;
    else h_count <= h_count + 10'd1;
  end

  // El vertical solo avanza al terminar cada linea
  always_ff @(posedge clk_pix_i) begin
    if (rst_pix) v_count <= '0;
    else if (fin_linea) begin
      if (fin_cuadro) v_count <= '0;
      else v_count <= v_count + 10'd1;
    end
  end

  logic video_on;
  logic hsync_n;
  logic vsync_n;

  assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
  // Polaridad negativa en los dos, el pulso es bajo
  assign hsync_n = ~((h_count >= H_VISIBLE + H_FRONT) && (h_count < H_VISIBLE + H_FRONT + H_SYNC));
  assign vsync_n = ~((v_count >= V_VISIBLE + V_FRONT) && (v_count < V_VISIBLE + V_FRONT + V_SYNC));

  // ---------------------------------------------------------------- calculo del indice

  // Casillas de 32 x 32, dividir entre 32 es quedarse con los bits altos
  logic [4:0] col;
  logic [3:0] fila;
  logic [8:0] indice_pix;

  assign col = h_count[9:5];
  assign fila = v_count[8:5];

  // fila * 20 = fila * 16 + fila * 4, sin multiplicador. Fuera del area visible apunta a cualquier lado pero video_on lo tapa
  assign indice_pix = {1'b0, fila, 4'b0000} + {3'b000, fila, 2'b00} + {4'b0000, col};

  // ---------------------------------------------------------------- puerto B y retardo de control

  // Puerto B, dominio clk_pix_i, solo lectura y registrada. El registro es lo que lo deja sincronizado al reloj de pixel
  logic [COLOR_WIDTH-1:0] color;
  logic borde;
  logic [CAR_WIDTH-1:0] caracter;
  logic [CAR_WIDTH-1:0] caracter2;
  logic centrado;

  always_ff @(posedge clk_pix_i) begin
    color <= memoria_video[indice_pix][COLOR_WIDTH-1:0];
    borde <= memoria_video[indice_pix][BIT_BORDE];
    caracter <= memoria_video[indice_pix][CAR_LSB +: CAR_WIDTH];
    caracter2 <= memoria_video[indice_pix][CAR2_LSB +: CAR_WIDTH];
    centrado <= memoria_video[indice_pix][BIT_CENTRADO];
  end

  // Primer o ultimo pixel de la casilla en cualquiera de los dos ejes, son los 5 bits bajos de cada contador
  logic en_contorno;

  assign en_contorno = (h_count[4:0] == 5'd0) || (h_count[4:0] == 5'd31) ||
                       (v_count[4:0] == 5'd0) || (v_count[4:0] == 5'd31);

  // El control se atrasa el mismo ciclo que la lectura, si no la imagen sale corrida un pixel contra los sincronismos
  logic video_on_d;
  logic hsync_d;
  logic vsync_d;
  logic en_contorno_d;
  logic [3:0] celda_col_d; // columna y fila del pixel en la cuadricula de 16 x 16 de la casilla, 2 pixeles cada una
  logic [3:0] celda_fila_d;

  always_ff @(posedge clk_pix_i) begin
    if (rst_pix) begin
      video_on_d <= 1'b0;
      hsync_d <= 1'b1;
      vsync_d <= 1'b1;
      en_contorno_d <= 1'b0;
      celda_col_d <= '0;
      celda_fila_d <= '0;
    end
    else begin
      video_on_d <= video_on;
      hsync_d <= hsync_n;
      vsync_d <= vsync_n;
      en_contorno_d <= en_contorno;
      celda_col_d <= h_count[4:1];
      celda_fila_d <= v_count[4:1];
    end
  end

  // ---------------------------------------------------------------- caracter

  logic [CAR_WIDTH-1:0] codigo;
  logic [3:0] glifo_col; // columna del glifo, de 0 a 4 cuando el pixel cae sobre el
  logic [3:0] glifo_fila;
  logic en_col;
  logic en_fila;
  logic [4:0] glifo_bits;
  logic pixel_texto;
  logic fondo_claro;

  // Cada mitad de la casilla son 8 celdas de 2 pixeles y el glifo ocupa las celdas 1 a 5 de su mitad.
  // Centrado, el glifo ocupa las celdas 5 a 9 de la casilla entera, pixeles 10 a 19
  always_comb begin
    if (centrado) begin
      codigo = caracter;
      glifo_col = celda_col_d - 4'd5;
    end
    else begin
      codigo = celda_col_d[3] ? caracter2 : caracter;
      glifo_col = {1'b0, celda_col_d[2:0]} - 4'd1;
    end
  end

  assign glifo_fila = celda_fila_d - GLIFO_FILA0;
  assign en_col = (glifo_col <= 4'd4);   // la resta da la vuelta si la celda queda antes del glifo
  assign en_fila = (glifo_fila <= 4'd6);

  fuente_caracteres u_fuente (
    .codigo_i (codigo),
    .fila_i   (glifo_fila[2:0]),
    .bits_o   (glifo_bits)
  );

  // La columna 0 del glifo es el bit 4 de la fila
  assign pixel_texto = en_col && en_fila && glifo_bits[3'd4 - glifo_col[2:0]];

  // Blanco (011), cursor amarillo (100) y verde (110) son claros, ahi el texto va en negro
  assign fondo_claro = (color == 3'b011) || (color == 3'b100) || (color == 3'b110);

  // ----------------------------------------------------------------
  //paleta

  // Los cuatro primeros son los que pide el enunciado, y coinciden con los estados de casilla que el programa guarda en RAM
  logic [RGB_WIDTH-1:0] rgb;
  logic [RGB_WIDTH-1:0] rgb_pix;

  always_comb begin
    case (color)
      3'b000: rgb = 12'h04A; // agua
      3'b001: rgb = 12'h888; // barco propio
      3'b010: rgb = 12'hF00; // impacto
      3'b011: rgb = 12'hFFF; // fallo
      3'b100: rgb = 12'hFF0; // cursor
      3'b101: rgb = 12'h000; // fondo y separadores del HUD
      3'b110: rgb = 12'h0F0; // turno del jugador 1
      3'b111: rgb = 12'hF0F; // turno del jugador 2
      default: rgb = 12'h000;
    endcase
  end

  // Fuera del area visible el monitor espera negro, lo usa para medir el nivel de referencia
  always_comb begin
    if (!video_on_d) rgb_pix = '0;
    else if (borde && en_contorno_d) rgb_pix = LINEA_RGB;
    else if (pixel_texto) rgb_pix = fondo_claro ? TEXTO_OSCURO : TEXTO_CLARO;
    else rgb_pix = rgb;
  end

  // ---------------------------------------------------------------- registro de salida

  // Los pines salen todos de flip-flops, asi los glitches de la paleta no llegan al conector
  always_ff @(posedge clk_pix_i) begin
    if (rst_pix) begin
      vga_r_o <= '0;
      vga_g_o <= '0;
      vga_b_o <= '0;
      vga_hsync_o <= 1'b1;
      vga_vsync_o <= 1'b1;
    end
    else begin
      vga_r_o <= rgb_pix[11:8];
      vga_g_o <= rgb_pix[7:4];
      vga_b_o <= rgb_pix[3:0];
      vga_hsync_o <= hsync_d;
      vga_vsync_o <= vsync_d;
    end
  end

endmodule
