// Sistema completo de la Batalla Naval en la Basys 3: procesador uniciclo, ROM, RAM, controlador de
// mapeo (address_translator + mux_lectura) y los seis perifericos. No agrega logica propia aparte del
// reinicio, solo conecta. Mapa de memoria en la seccion 4.4 del enunciado y en Address_Translator.md.
//
// No hay pin de reset. El reinicio general es el boton PROG, que vuelve a configurar la FPGA, y rst
// queda en alto hasta que el PLL engancha. BTN_RST es una entrada mas del periferico de entradas y
// lo atiende el programa, para conservar las partidas ganadas.
module top #(
  parameter ARCHIVO_HEX = "sw/programa.hex" // programa de la ROM, relativo a la raiz del repo
  ) (
  input  logic       clk, // 100 MHz, pin W5

  // Entradas del Jugador 1, en el orden de los bits del registro de estado
  input  logic       btn_arriba, // btnU
  input  logic       btn_abajo,  // btnD
  input  logic       btn_izq,    // btnL
  input  logic       btn_der,    // btnR
  input  logic       btn_sel,    // btnC
  input  logic       btn_ok,     // SW0
  input  logic       btn_rst,    // SW15

  // UART hacia la aplicacion de PC del Jugador 2
  input  logic       rx_i,
  output logic       tx_o,

  // VGA
  output logic [3:0] vga_r_o,
  output logic [3:0] vga_g_o,
  output logic [3:0] vga_b_o,
  output logic       vga_hsync_o,
  output logic       vga_vsync_o,

  // 7 segmentos
  output logic [6:0] seg,
  output logic [3:0] an,
  output logic       dp,

  output logic [2:0] led, // LD0 colocacion, LD1 batalla, LD2 resultado
  output logic       buzzer
  );

  // Frecuencia de clk_sys, 1000 MHz / 30 del PLL (ver generador_relojes.sv). La UART y el buzzer
  // cuentan sus tiempos con ella
  localparam int CLK_SYS_HZ = 33_333_333;

  // ---------------------------------------------------------------- relojes y reinicio

  logic clk_sys;
  logic clk_pix;
  logic pll_locked;

  generador_relojes u_generador_relojes (
    .clk_i     (clk),
    .clk_sys_o (clk_sys),
    .clk_pix_o (clk_pix),
    .locked_o  (pll_locked)
  );

  // ~locked pasa por dos flip-flops en clk_sys antes de llegar a los bloques. Arrancan en uno por la
  // configuracion de la FPGA, asi el sistema sale del bitstream ya en reinicio
  logic [1:0] sinc_rst = 2'b11;
  logic       rst;

  always_ff @(posedge clk_sys) sinc_rst <= {sinc_rst[0], ~pll_locked};

  assign rst = sinc_rst[1];

  // ---------------------------------------------------------------- procesador y memorias

  logic [31:0] prog_address;
  logic [31:0] prog_in;
  logic [31:0] data_address;
  logic [31:0] data_out;
  logic [31:0] data_in;
  logic        we;

  procesador_uniciclo u_procesador (
    .clk_i         (clk_sys),
    .rst_i         (rst),
    .ProgAddress_o (prog_address),
    .ProgIn_i      (prog_in),
    .DataAddress_o (data_address),
    .DataOut_o     (data_out),
    .DataIn_i      (data_in),
    .we_o          (we)
  );

  rom #(.ARCHIVO_HEX(ARCHIVO_HEX)) u_rom (
    .addr_i  (prog_address),
    .instr_o (prog_in)
  );

  // ---------------------------------------------------------------- controlador de mapeo

  logic       ram_we;
  logic       uart_we;
  logic       gpio_we;
  logic       display_we;
  logic       led_we;
  logic       buzzer_we;
  logic       vga_we;
  logic [2:0] mux_sel;

  address_translator u_address_translator (
    .address_i      (data_address),
    .write_enable_i (we),
    .ram_we         (ram_we),
    .uart_we        (uart_we),
    .gpio_we        (gpio_we),
    .display_we     (display_we),
    .led_we         (led_we),
    .buzzer_we      (buzzer_we),
    .vga_we         (vga_we),
    .mux_sel        (mux_sel)
  );

  logic [31:0] ram_dout;
  logic [31:0] uart_dout;
  logic [31:0] gpio_dout;
  logic [31:0] display_dout;
  logic [31:0] led_dout;
  logic [31:0] buzzer_dout;
  logic [31:0] vga_dout;

  mux_lectura u_mux_lectura (
    .mux_sel      (mux_sel),
    .ram_dout     (ram_dout),
    .uart_dout    (uart_dout),
    .gpio_dout    (gpio_dout),
    .display_dout (display_dout),
    .led_dout     (led_dout),
    .buzzer_dout  (buzzer_dout),
    .vga_dout     (vga_dout),
    .rdata_o      (data_in)
  );

  // ---------------------------------------------------------------- RAM de datos

  // Toma la direccion completa y usa [11:2], el AT ya reviso que caiga en 0x0000_2000-0x0000_2FFF
  ram u_ram (
    .clk_i          (clk_sys),
    .write_enable_i (ram_we),
    .addr_i         (data_address),
    .wdata_i        (data_out),
    .rdata_o        (ram_dout)
  );

  // ---------------------------------------------------------------- perifericos

  // Los de un solo registro van con addr_i fijo en 00. El AT solo los selecciona en su offset 0x00,
  // asi que DataAddress_o[3:2] no les sirve: el LED en 0x0001_0138 traeria 10 y no 00

  // Control 0x40, TX 0x44 y RX 0x48, el registro sale de DataAddress_o[3:2]
  periferico_uart #(.CLK_FREQ_HZ(CLK_SYS_HZ)) u_periferico_uart (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (uart_we),
    .addr_i         (data_address[3:2]),
    .wdata_i        (data_out),
    .rdata_o        (uart_dout),
    .rx_i           (rx_i),
    .tx_o           (tx_o)
  );

  periferico_entradas u_periferico_entradas (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (gpio_we),
    .addr_i         (2'b00),
    .wdata_i        (data_out),
    .rdata_o        (gpio_dout),
    .botones_i      ({btn_rst, btn_ok, btn_sel, btn_der, btn_izq, btn_abajo, btn_arriba})
  );

  periferico_7seg u_periferico_7seg (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (display_we),
    .addr_i         (2'b00),
    .wdata_i        (data_out),
    .rdata_o        (display_dout),
    .seg_o          (seg),
    .an_o           (an),
    .dp_o           (dp)
  );

  periferico_led u_periferico_led (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (led_we),
    .addr_i         (2'b00),
    .wdata_i        (data_out),
    .rdata_o        (led_dout),
    .leds_o         (led)
  );

  periferico_buzzer #(.CLK_FREQ_HZ(CLK_SYS_HZ)) u_periferico_buzzer (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (buzzer_we),
    .addr_i         (2'b00),
    .wdata_i        (data_out),
    .rdata_o        (buzzer_dout),
    .buzzer_o       (buzzer)
  );

  // Memoria de video en 0x0001_1000-0x0001_17FF, una palabra por casilla, el indice es DataAddress_o[10:2]
  periferico_vga u_periferico_vga (
    .clk_i          (clk_sys),
    .rst_i          (rst),
    .write_enable_i (vga_we),
    .addr_i         (data_address[10:2]),
    .wdata_i        (data_out),
    .rdata_o        (vga_dout),
    .clk_pix_i      (clk_pix),
    .vga_hsync_o    (vga_hsync_o),
    .vga_vsync_o    (vga_vsync_o),
    .vga_r_o        (vga_r_o),
    .vga_g_o        (vga_g_o),
    .vga_b_o        (vga_b_o)
  );

endmodule
