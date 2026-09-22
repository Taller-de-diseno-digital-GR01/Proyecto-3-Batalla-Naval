// Los puertos del bus llevan sufijo _i/_o porque la seccion 3.4.3 del enunciado los define asi, es la excepcion al prefijo del resto del repo
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

  // Las dos direcciones de datos las fija el enunciado, la del control la escogio el equipo
  localparam logic [1:0] ADDR_DATOS_TX = 2'b00;
  localparam logic [1:0] ADDR_DATOS_RX = 2'b01;
  localparam logic [1:0] ADDR_CONTROL = 2'b10;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  // El dato serial son 8 bits fijos, los nucleos del curso los traen asi y no depende del ancho del bus
  localparam int BYTE_WIDTH = 8;

  logic [BYTE_WIDTH-1:0] reg_tx;
  logic [BYTE_WIDTH-1:0] reg_rx;
  logic send;
  logic new_rx;

  logic listo_tx;
  logic listo_rx;
  logic [BYTE_WIDTH-1:0] dato_rx;

  // send va sostenido y no como pulso, el nucleo tiene una ventana muerta de un bit donde se come los pulsos cortos
  uart_tx #(.TICKS_BIT(TICKS_BIT)) nucleo_tx (
    .clk(clk_i),
    .rst(rst_i),
    .i_enviar(send),
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

  // send es WC, sube cuando se lo escriben y lo baja el periferico solo al terminar la transferencia
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      reg_tx <= '0;
      send <= 1'b0;
    end
    else begin
      if (write_enable_i && addr_i == ADDR_DATOS_TX) reg_tx <= wdata_i[BYTE_WIDTH-1:0];
      // Bajarlo con listo_tx deja un bit entero de margen antes de que el nucleo se rearme y mande el byte dos veces
      if (write_enable_i && addr_i == ADDR_CONTROL && wdata_i[BIT_SEND]) send <= 1'b1;
      else if (listo_tx) send <= 1'b0;
    end
  end

  // new_rx es RW, o sea que una escritura al control lo deja en lo que diga el bit 1, tal como pide el enunciado
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      reg_rx <= '0;
      new_rx <= 1'b0;
    end
    // Un byte que llega le gana a la escritura del mismo ciclo, si no se perderia el dato recien recibido
    else if (listo_rx) begin
      reg_rx <= dato_rx;
      new_rx <= 1'b1;
    end
    else if (write_enable_i) begin
      if (addr_i == ADDR_DATOS_RX) reg_rx <= wdata_i[BYTE_WIDTH-1:0];
      if (addr_i == ADDR_CONTROL) new_rx <= wdata_i[BIT_NEW_RX];
    end
  end

  always_comb begin
    case (addr_i)
      ADDR_DATOS_TX: rdata_o = {{(WIDTH-BYTE_WIDTH){1'b0}}, reg_tx};
      ADDR_DATOS_RX: rdata_o = {{(WIDTH-BYTE_WIDTH){1'b0}}, reg_rx};
      ADDR_CONTROL: rdata_o = {{(WIDTH-2){1'b0}}, new_rx, send};
      default: rdata_o = '0; // la direccion 11 no se usa, devuelve ceros
    endcase
  end

endmodule
