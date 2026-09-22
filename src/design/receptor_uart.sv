// BYTE_WIDTH va como localparam de la lista porque el dato serial son 8 bits fijos, no una fraccion del bus
module receptor_uart #(parameter WIDTH = 32, localparam int BYTE_WIDTH = 8) (
  input logic clk,
  input logic rst,
  input logic [WIDTH-1:0] i_rdata, // lo que devuelve el periférico uart en la dirección que le estoy poniendo
  input logic [2:0] i_state, // desde la fsm, de acá solo me interesa JUEGO

  output logic [1:0] o_addr,
  output logic o_write_enable,
  output logic [WIDTH-1:0] o_wdata,
  output logic [BYTE_WIDTH-1:0] o_letra, // hacia REG_Letra-in
  output logic o_valid_w // habilitación de carga de esa letra
  );

  // TODO: Revisar ADDR_CTRL con el frente de uart, el enunciado no le fija direccion y M11 tiene que usar la misma
  localparam ADDR_CTRL = 2'b10;
  localparam ADDR_DATOS_RX = 2'b01; // el enunciado la fija asi, registro de datos 1 en addr_i=2'b01
  localparam BIT_NEW_RX = 1;

  localparam JUEGO = 3'b010;

  localparam ESPERA = 2'b00;
  localparam LEE = 2'b01;
  localparam LIMPIA = 2'b10;

  logic [1:0] estado;
  logic new_rx, en_rango;

  assign new_rx = i_rdata[BIT_NEW_RX]; // solo vale mientras o_addr esté apuntando al registro de control
  assign en_rango = (i_rdata[BYTE_WIDTH-1:0] >= 8'h41) && (i_rdata[BYTE_WIDTH-1:0] <= 8'h5A); // A-Z, solo mayúsculas

  // 1. Sondeo del periférico, tres ciclos por byte contra los 87 us que tarda uno a 115200 baudios
  always_ff @(posedge clk) begin
    o_valid_w <= 1'b0;
    if (rst) begin
      estado <= ESPERA;
      o_letra <= '0;
    end
    else begin
      case (estado)
        ESPERA: if (new_rx) estado <= LEE;
        // Acá se botan las letras que llegan en selección de modo o mostrando resultado, sin tocar la partida
        LEE: begin
          estado <= LIMPIA;
          o_letra <= i_rdata[BYTE_WIDTH-1:0];
          o_valid_w <= en_rango && (i_state == JUEGO);
        end
        // Limpia a new_rx, pase lo que pase con el byte, si no el receptor queda trabado y no recibe nunca más
        LIMPIA: estado <= ESPERA;
        default: estado <= ESPERA;
      endcase
    end
  end

  // 2. Salidas hacia el bus, el dato del periférico es combinacional respecto a o_addr
  always_comb begin
    o_addr = ADDR_CTRL;
    o_write_enable = 1'b0;
    o_wdata = '0; // escribir ceros baja new_rx y de paso no pulsa el send del transmisor
    case (estado)
      LEE: o_addr = ADDR_DATOS_RX;
      LIMPIA: o_write_enable = 1'b1;
    endcase
  end

endmodule
