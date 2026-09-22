module transmisor_uart #(parameter WIDTH = 32, parameter WORD_MAXLEN = 12) (
  input logic clk,
  input logic rst,
  input logic [2:0] i_state,       // desde la fsm
  input logic i_modo,              // desde la fsm
  input logic [1:0] i_letra_state, // 00 fallo, 01 acierto, 10 repetida, desde M07_Comparador-letra
  input logic i_letra_lista,       // pulso de un ciclo que acompaña a i_letra_state, desde M07
  input logic [2:0] i_intentos,    // intentos fallidos acumulados, desde M12_Contador-Intentos
  input logic [3:0] i_word_length, // longitud de la palabra, desde REG_Palabra-escogida
  input logic [WORD_MAXLEN-1:0] i_mascara, // posiciones reveladas, desde M07_Comparador-letra
  input logic [WIDTH-1:0] i_rdata,      // bus de WIDTH bits compartido con PERIFERICO_UART
  input logic i_bus_libre,         // desde el arbitro, el receptor tiene prioridad y este se aguanta

  output logic o_write_enable,
  output logic [1:0] o_addr,
  output logic [WIDTH-1:0] o_wdata
  );

  // Códigos de estado de la FSM principal, la fsm junta las dos derrotas en PERDIO
  localparam JUEGO = 3'b010;
  localparam GANO = 3'b011;
  localparam PERDIO = 3'b100;

  // Causas que viajan en la trama de fin, la app de pc ya las lee así
  localparam CAUSA_INTENTOS = 3'b100;
  localparam CAUSA_TIEMPO = 3'b101;

  localparam MAX_INTENTOS = 6;

  // El enunciado fija el registro de datos de transmision en addr_i=2'b00, la del control la elige el equipo
  localparam ADDR_UART_CTRL = 2'b10;
  localparam ADDR_UART_TX = 2'b00;
  localparam BIT_SEND = 0;

  // El dato serial son 8 bits fijos, no una fraccion del ancho del bus
  localparam int BYTE_WIDTH = 8;

  localparam IDLE = 2'b00;
  localparam LOAD_DATA = 2'b01;
  localparam LOAD_CTRL = 2'b10;
  localparam WAIT = 2'b11;

  //Detección de disparo: entrada a JUEGO, entrada a un estado de fin, y cada letra evaluada
  // (la repetida también manda trama, si no la PC se queda sin respuesta y vuelve a escribir)
  logic dec_juego, dec_juego_prev, pulso_ini;
  logic dec_fin, dec_fin_prev, pulso_fin;

  assign dec_juego = (i_state == JUEGO);
  assign dec_fin = (i_state == GANO) || (i_state == PERDIO);

  always_ff @(posedge clk) begin
    if (rst) begin
      dec_juego_prev <= 1'b0;
      dec_fin_prev <= 1'b0;
    end
    else begin
      dec_juego_prev <= dec_juego;
      dec_fin_prev <= dec_fin;
    end
  end

  assign pulso_ini = dec_juego & ~dec_juego_prev;
  assign pulso_fin = dec_fin & ~dec_fin_prev;

  // 2. Banderas "pendiente", se quedan en alto hasta que la FSM interna las consume, para no
  // perder un evento que llega mientras se sigue enviando una trama anterior
  logic [1:0] estado, estado_sig;
  logic estado_wait_libre; // WAIT con send ya libre, usado por la FSM y por CNT_BYTE
  logic hay_pendiente, consumir;
  logic pend_ini, pend_ini_next;
  logic pend_letra, pend_letra_next;
  logic pend_fin, pend_fin_next;
  logic [1:0] pend_letra_val;
  logic [2:0] pend_intentos_val;
  logic [WORD_MAXLEN-1:0] pend_mascara_val;
  logic [2:0] pend_fin_causa;

  assign hay_pendiente = pend_fin | pend_letra | pend_ini;
  assign consumir = (estado == IDLE) && hay_pendiente && i_bus_libre; // atado a la transicion, si no se limpiaria una pendiente que nunca se manda

  // El set tiene prioridad sobre el clear si coinciden en el mismo ciclo, para no perder un
  // evento nuevo justo cuando se está consumiendo uno viejo del mismo tipo
  always_comb begin
    pend_ini_next = pend_ini;
    pend_letra_next = pend_letra;
    pend_fin_next = pend_fin;
    if (consumir) begin
      if (pend_fin) pend_fin_next = 1'b0;
      else if (pend_letra) pend_letra_next = 1'b0;
      else if (pend_ini) pend_ini_next = 1'b0;
    end
    if (pulso_ini) pend_ini_next = 1'b1;
    if (i_letra_lista) pend_letra_next = 1'b1;
    if (pulso_fin) pend_fin_next = 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pend_ini <= 1'b0;
      pend_letra <= 1'b0;
      pend_fin <= 1'b0;
    end
    else begin
      pend_ini <= pend_ini_next;
      pend_letra <= pend_letra_next;
      pend_fin <= pend_fin_next;
    end
    // valores capturados: se sobreescriben con el más reciente aunque el anterior siga sin atender
    if (i_letra_lista) begin
      pend_letra_val <= i_letra_state;
      pend_intentos_val <= i_intentos;
      pend_mascara_val <= i_mascara;
    end
    // PERDIO ya no dice por qué se perdió, pero contador_intentos solo se limpia en CARGA y todavía tiene la cuenta al entrar
    if (pulso_fin) begin
      if (i_state == GANO) pend_fin_causa <= GANO;
      else if (i_intentos >= MAX_INTENTOS) pend_fin_causa <= CAUSA_INTENTOS;
      else pend_fin_causa <= CAUSA_TIEMPO;
    end
  end

  // 3. Máquina de estados: IDLE decide cuál pendiente atender (prioridad fin > letra > inicio),
  // LOAD_DATA/LOAD_CTRL/WAIT recorren la trama byte a byte contra el handshake de un bit `send`
  logic send_busy;
  logic [2:0] cnt_byte;
  logic [2:0] reg_len; // la trama de letra son 5 bytes, con dos bits no alcanzaba
  logic [BYTE_WIDTH-1:0] reg_trama [0:4];

  logic [2*BYTE_WIDTH-1:0] mascara_ext;
  assign mascara_ext = {{(2*BYTE_WIDTH-WORD_MAXLEN){1'b0}}, pend_mascara_val}; // la mascara viaja en dos bytes, poco significativo primero

  assign send_busy = i_rdata[BIT_SEND];
  assign estado_wait_libre = (estado == WAIT) && !send_busy && i_bus_libre; // sin el bus, send_busy llega en ceros y no significa nada

  always_comb begin
    estado_sig = estado;
    case (estado)
      IDLE: if (hay_pendiente && i_bus_libre) estado_sig = LOAD_DATA;
      LOAD_DATA: if (i_bus_libre) estado_sig = LOAD_CTRL; // si el arbitro le corta el paso, reintenta la escritura el ciclo siguiente
      LOAD_CTRL: if (i_bus_libre) estado_sig = WAIT;
      WAIT: if (estado_wait_libre) estado_sig = (cnt_byte == reg_len - 1) ? IDLE : LOAD_DATA;
      default: estado_sig = IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) estado <= IDLE;
    else estado <= estado_sig;
  end

  always_ff @(posedge clk) begin
    if (rst) cnt_byte <= 3'd0;
    else if (consumir) cnt_byte <= 3'd0;
    else if (estado_wait_libre && (cnt_byte != reg_len - 1)) cnt_byte <= cnt_byte + 1'b1;
  end

  // Carga de la trama al consumir la pendiente de mayor prioridad
  always_ff @(posedge clk) begin
    if (consumir) begin
      if (pend_fin) begin
        reg_trama[0] <= 8'h46; // "F"
        reg_trama[1] <= {5'b0, pend_fin_causa};
        reg_len <= 3'd2;
      end
      else if (pend_letra) begin
        reg_trama[0] <= 8'h4C; // "L"
        reg_trama[1] <= {6'b0, pend_letra_val};
        reg_trama[2] <= {5'b0, pend_intentos_val};
        // la pc solo debe mirar los primeros i_word_length bits, arriba de eso va el relleno que M07 deja en unos
        reg_trama[3] <= mascara_ext[BYTE_WIDTH-1:0];
        reg_trama[4] <= mascara_ext[2*BYTE_WIDTH-1:BYTE_WIDTH];
        reg_len <= 3'd5;
      end
      else begin // pend_ini
        reg_trama[0] <= 8'h49; // "I"
        reg_trama[1] <= {{(BYTE_WIDTH-1){1'b0}}, i_modo};
        reg_trama[2] <= {4'b0, i_word_length};
        reg_len <= 3'd3;
      end
    end
  end

  // 4. Salidas hacia el bus
  always_comb begin
    o_write_enable = 1'b0;
    o_addr = ADDR_UART_CTRL;
    o_wdata = '0;
    case (estado)
      LOAD_DATA: begin
        o_addr = ADDR_UART_TX;
        o_wdata = {{(WIDTH-BYTE_WIDTH){1'b0}}, reg_trama[cnt_byte]};
        o_write_enable = 1'b1;
      end
      LOAD_CTRL: begin
        o_addr = ADDR_UART_CTRL;
        o_wdata = WIDTH'(1); // bit 0 = send
        o_write_enable = 1'b1;
      end
      default: ; // IDLE y WAIT no escriben
    endcase
  end

endmodule
