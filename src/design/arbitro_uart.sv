// Multiplexa el bus de 32 bits entre el receptor y el transmisor, que son dos maestros sobre un periferico de un solo puerto
module arbitro_uart #(parameter WIDTH = 32) (
  // Cara del receptor, M10. Tiene prioridad absoluta porque usa el bus 3 ciclos de cada 8640 y no sabe esperar
  input logic [1:0] i_rx_addr,
  input logic i_rx_we,
  input logic [WIDTH-1:0] i_rx_wdata,
  output logic [WIDTH-1:0] o_rx_rdata,

  // Cara del transmisor, M11. Aguanta demora sin perder eventos, para eso tiene sus banderas pendientes
  input logic [1:0] i_tx_addr,
  input logic i_tx_we,
  input logic [WIDTH-1:0] i_tx_wdata,
  output logic [WIDTH-1:0] o_tx_rdata,
  output logic o_tx_bus_libre,

  // Cara del periferico
  output logic [1:0] o_addr,
  output logic o_we,
  output logic [WIDTH-1:0] o_wdata,
  input logic [WIDTH-1:0] i_rdata
  );

  localparam logic [1:0] ADDR_CONTROL = 2'b10;
  localparam BIT_SEND = 0;
  localparam BIT_NEW_RX = 1;

  logic rx_pide;
  logic tx_pide;

  // Sondear el control no cuenta como pedir el bus, los dos pueden leerlo a la vez sin estorbarse
  assign rx_pide = (i_rx_addr != ADDR_CONTROL) || i_rx_we;
  assign tx_pide = (i_tx_addr != ADDR_CONTROL) || i_tx_we;

  assign o_tx_bus_libre = !rx_pide;

  // Se rearma la palabra rescatando el bit del otro de la lectura live, que es del mismo ciclo porque el
  logic [WIDTH-1:0] wdata_control;
  assign wdata_control = {{(WIDTH-2){1'b0}},
                          rx_pide ? i_rx_wdata[BIT_NEW_RX] : i_rdata[BIT_NEW_RX],
                          rx_pide ? i_rdata[BIT_SEND] : i_tx_wdata[BIT_SEND]};
                          // wdata_controll es 30 bits + i_rx_wdata[BIT_NEW_RX] + i_rdata[BIT_SEND] si rx_pide == 1
                          // wdata_controll es 30 bits + i_rdata[BIT_NEW_RX] + i_tx_data[BIT_SEND] si rx_pide == 0
                          // Ya sumado son 32 bits entonces está bien porque wdata_control son 32 bits.

  always_comb begin
    if (rx_pide) begin
      o_addr = i_rx_addr;
      o_we = i_rx_we;
      o_wdata = i_rx_wdata;
    end
    else if (tx_pide) begin
      o_addr = i_tx_addr;
      o_we = i_tx_we;
      o_wdata = i_tx_wdata;
    end
    else begin
      o_addr = ADDR_CONTROL; // en reposo se deja apuntando al control, que es lo que los dos quieren leer
      o_we = 1'b0;
      o_wdata = '0;
    end

    if (o_we && o_addr == ADDR_CONTROL) o_wdata = wdata_control;
  end

  // Al que no tiene el bus se le devuelven ceros, si no leeria el registro ajeno creyendo que es el control
  assign o_rx_rdata = (rx_pide || !tx_pide) ? i_rdata : '0;
  assign o_tx_rdata = rx_pide ? '0 : i_rdata;

endmodule
