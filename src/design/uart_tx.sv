// Port a SystemVerilog de UART/src/UART_tx.vhd, misma fsm y mismos tiempos, nombres traducidos al estilo del repo
module uart_tx #(parameter TICKS_BIT = 868) ( // 100e6 / 115200 = 868.06, el generico original venia en 139 para 16 MHz
  input logic clk,
  input logic rst,
  input logic i_enviar, // pulso de un ciclo, arranca la transmision de i_dato
  input logic [7:0] i_dato,

  output logic o_listo, // pulso de un ciclo al terminar de soltar el byte
  output logic o_tx // linea serial hacia el pin
  );

  localparam logic [1:0] REPOSO = 2'd0;
  localparam logic [1:0] ARRANQUE = 2'd1;
  localparam logic [1:0] DATOS = 2'd2;
  localparam logic [1:0] PARADA = 2'd3;

  logic [1:0] estado;
  logic tick_bit;
  logic [7:0] dato_guardado;
  logic [2:0] indice;
  logic indice_en_pausa;
  logic arranque_pedido;
  logic limpiar_arranque;
  logic fin_tx;
  logic fin_tx_prev;
  int cuenta_tick;

  always_ff @(posedge clk) begin
    if (rst) begin
      tick_bit <= 1'b0;
      cuenta_tick <= TICKS_BIT - 1;
    end
    else if (cuenta_tick == 0) begin
      tick_bit <= 1'b1;
      cuenta_tick <= TICKS_BIT - 1;
    end
    else begin
      tick_bit <= 1'b0;
      cuenta_tick <= cuenta_tick - 1;
    end
  end

  // Atrapa el pulso de un ciclo de i_enviar y lo sostiene, porque la fsm solo despierta en los ticks de baudaje
  always_ff @(posedge clk) begin
    if (rst || limpiar_arranque) arranque_pedido <= 1'b0;
    else if (i_enviar && !arranque_pedido) begin
      arranque_pedido <= 1'b1;
      dato_guardado <= i_dato; // congelado aca, para que la fuente pueda soltar i_dato durante la transmision
    end
  end

  // El original lo declara range 0 to 7 y se pasa de rango en el ultimo tick, aca de 3 bits da la vuelta sin romper nada
  always_ff @(posedge clk) begin
    if (rst || indice_en_pausa) indice <= 3'd0;
    else if (tick_bit) indice <= indice + 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      estado <= REPOSO;
      indice_en_pausa <= 1'b1;
      limpiar_arranque <= 1'b1;
      o_tx <= 1'b1; // la linea reposa en uno, es el estandar
      fin_tx <= 1'b0;
    end
    else if (tick_bit) begin
      case (estado)
        REPOSO: begin
          fin_tx <= 1'b0;
          indice_en_pausa <= 1'b1;
          limpiar_arranque <= 1'b0;
          o_tx <= 1'b1;
          if (arranque_pedido) estado <= ARRANQUE;
        end
        ARRANQUE: begin
          fin_tx <= 1'b0;
          indice_en_pausa <= 1'b0;
          o_tx <= 1'b0; // bit de arranque
          estado <= DATOS;
        end
        DATOS: begin
          o_tx <= dato_guardado[indice]; // menos significativo primero
          if (indice == 3'd7) begin
            indice_en_pausa <= 1'b1;
            estado <= PARADA;
          end
        end
        PARADA: begin
          o_tx <= 1'b1; // bit de parada
          limpiar_arranque <= 1'b1;
          fin_tx <= 1'b1;
          estado <= REPOSO;
        end
      endcase
    end
  end

  // fin_tx se queda alto hasta volver a REPOSO, el detector de flanco lo recorta a un solo ciclo
  always_ff @(posedge clk) begin
    if (rst) begin
      o_listo <= 1'b0;
      fin_tx_prev <= 1'b0;
    end
    else begin
      o_listo <= fin_tx && !fin_tx_prev;
      fin_tx_prev <= fin_tx;
    end
  end

endmodule
