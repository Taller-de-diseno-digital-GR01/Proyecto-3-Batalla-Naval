// Port a SystemVerilog de UART/src/UART_rx.vhd, misma fsm y mismos tiempos, nombres traducidos al estilo del repo
module uart_rx #(parameter TICKS_X16 = 54) ( // (100e6 / 115200) / 16 = 54.25, el generico original venia en 9 para 16 MHz
  input logic clk,
  input logic rst,
  input logic i_rx, // linea serial cruda desde el pin

  output logic o_dato_listo, // pulso de un ciclo, avisa que hay byte nuevo en o_dato
  output logic [7:0] o_dato
  );

  localparam logic [1:0] REPOSO = 2'd0;
  localparam logic [1:0] ARRANQUE = 2'd1;
  localparam logic [1:0] DATOS = 2'd2;
  localparam logic [1:0] PARADA = 2'd3;

  logic [1:0] estado;
  logic tick_x16;
  logic [7:0] dato_parcial;
  logic fin_rx;
  logic fin_rx_prev;
  int cuenta_tick;
  int cuenta_bit;
  int indice_bit;

  // Sobremuestreo a 16 veces el baudaje, es lo que permite caer al centro del bit y no a la orilla
  always_ff @(posedge clk) begin
    if (rst) begin
      tick_x16 <= 1'b0;
      cuenta_tick <= TICKS_X16 - 1;
    end
    else if (cuenta_tick == 0) begin
      tick_x16 <= 1'b1;
      cuenta_tick <= TICKS_X16 - 1;
    end
    else begin
      tick_x16 <= 1'b0;
      cuenta_tick <= cuenta_tick - 1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      estado <= REPOSO;
      dato_parcial <= 8'h00;
      o_dato <= 8'h00;
      fin_rx <= 1'b0;
      cuenta_bit <= 0;
      indice_bit <= 0;
    end
    else if (tick_x16) begin
      case (estado)
        REPOSO: begin
          fin_rx <= 1'b0;
          dato_parcial <= 8'h00;
          cuenta_bit <= 0;
          indice_bit <= 0;
          if (!i_rx) estado <= ARRANQUE; // el bit de arranque es un cero en una linea que reposa en uno
        end
        // Espera medio bit para correr el punto de muestreo al centro, si la linea vuelve a uno era ruido
        ARRANQUE: begin
          fin_rx <= 1'b0;
          if (!i_rx) begin
            if (cuenta_bit == 7) begin
              estado <= DATOS;
              cuenta_bit <= 0;
            end
            else cuenta_bit <= cuenta_bit + 1;
          end
          else estado <= REPOSO;
        end
        DATOS: begin
          if (cuenta_bit == 15) begin
            dato_parcial[indice_bit] <= i_rx; // menos significativo primero
            cuenta_bit <= 0;
            if (indice_bit == 7) estado <= PARADA;
            else indice_bit <= indice_bit + 1;
          end
          else cuenta_bit <= cuenta_bit + 1;
        end
        PARADA: begin
          if (cuenta_bit == 15) begin
            o_dato <= dato_parcial;
            fin_rx <= 1'b1;
            estado <= REPOSO;
          end
          else cuenta_bit <= cuenta_bit + 1;
        end
      endcase
    end
  end

  // fin_rx se queda alto hasta volver a REPOSO, el detector de flanco lo recorta a un solo ciclo
  always_ff @(posedge clk) begin
    if (rst) begin
      o_dato_listo <= 1'b0;
      fin_rx_prev <= 1'b0;
    end
    else begin
      o_dato_listo <= fin_rx && !fin_rx_prev;
      fin_rx_prev <= fin_rx;
    end
  end

endmodule
