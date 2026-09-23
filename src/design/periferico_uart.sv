// Los puertos del bus llevan sufijo _i/_o porque la seccion 4.5.5 del enunciado los define asi, es la excepcion al prefijo del resto del repo
module periferico_uart #(parameter WIDTH = 32, parameter TICKS_BIT = 868, parameter TICKS_X16 = 54) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i,
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  input logic rx_i, // linea serial desde el pin
  output logic tx_o // linea serial hacia el pin
  );

  // El mapa lo fija la tabla de la seccion 4.4.3, control en 0x0001_0040, TX en 0x44 y RX en 0x48
  localparam logic [1:0] ADDR_CONTROL = 2'b00;
  localparam logic [1:0] ADDR_DATOS_TX = 2'b01;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b10;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  // El dato serial son 8 bits fijos, los nucleos del curso los traen asi y no depende del ancho del bus
  localparam int BYTE_WIDTH = 8;

  logic [BYTE_WIDTH-1:0] reg_tx;
  logic [BYTE_WIDTH-1:0] reg_rx;
  logic [WIDTH-1:0] reg_control;

  logic listo_tx;
  logic listo_rx;
  logic [BYTE_WIDTH-1:0] dato_rx;

  // send va sostenido y no como pulso, el nucleo tiene una ventana muerta de un bit donde se come los pulsos cortos
  uart_tx #(.TICKS_BIT(TICKS_BIT)) nucleo_tx (
    .clk(clk_i),
    .rst(rst_i),
    .i_enviar(reg_control[BIT_SEND]),
    .i_dato(reg_tx),
    .o_listo(listo_tx),
    .o_tx(tx_o)
  );

  uart_rx #(.TICKS_X16(TICKS_X16)) nucleo_rx (
    .clk(clk_i),
    .rst(rst_i),
    .i_rx(rx_i),
    .o_dato_listo(listo_rx),
    .o_dato(dato_rx)
  );

  always_ff @(posedge clk_i) begin
    if (rst_i) reg_tx <= '0;
    else if (write_enable_i && addr_i == ADDR_DATOS_TX) reg_tx <= wdata_i[BYTE_WIDTH-1:0];
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) reg_rx <= '0;
    else if (listo_rx) reg_rx <= dato_rx;
    else if (write_enable_i && addr_i == ADDR_DATOS_RX) reg_rx <= wdata_i[BYTE_WIDTH-1:0];
  end

  // Cada campo se actualiza por su indice, los bits sin campo se quedan en cero porque nadie los asigna despues del reset
  always_ff @(posedge clk_i) begin
    if (rst_i) reg_control <= '0;
    else begin
      // send es WC, sube cuando se lo escriben y lo baja el periferico solo, bajarlo con listo_tx deja un bit entero de margen antes de que el nucleo se rearme y mande el byte dos veces
      if (write_enable_i && addr_i == ADDR_CONTROL && wdata_i[BIT_SEND]) reg_control[BIT_SEND] <= 1'b1;
      else if (listo_tx) reg_control[BIT_SEND] <= 1'b0;

      // new_rx es RW, un byte que llega le gana a la escritura del mismo ciclo, si no se perderia el dato recien recibido
      if (listo_rx) reg_control[BIT_NEW_RX] <= 1'b1;
      else if (write_enable_i && addr_i == ADDR_CONTROL) reg_control[BIT_NEW_RX] <= wdata_i[BIT_NEW_RX];
    end
  end

  always_comb begin
    case (addr_i)
      ADDR_CONTROL: rdata_o = reg_control;
      ADDR_DATOS_TX: rdata_o = {{(WIDTH-BYTE_WIDTH){1'b0}}, reg_tx};
      ADDR_DATOS_RX: rdata_o = {{(WIDTH-BYTE_WIDTH){1'b0}}, reg_rx};
      default: rdata_o = '0; // la direccion 11 no se usa, devuelve ceros
    endcase
  end

endmodule
