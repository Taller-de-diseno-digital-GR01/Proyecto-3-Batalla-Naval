module secuenciador_melodia #(parameter CLK_FREQ_HZ = 100_000_000, parameter UNIDAD_MS = 50) (
  input logic clk,
  input logic rst,
  input logic i_iniciar, // pulso de un ciclo con la escritura del programa
  input logic [2:0] i_sonido, // desde REG_SONIDO

  output logic [17:0] o_n, // medio periodo menos uno, hacia generador_tono
  output logic o_sonar,
  output logic o_fin // en alto mientras la melodia este terminada, limpia REG_SONIDO
  );

  localparam logic [2:0] SILENCIO = 3'd0;
  localparam logic [2:0] IMPACTO = 3'd1;
  localparam logic [2:0] FALLO = 3'd2;
  localparam logic [2:0] HUNDIDO = 3'd3;
  localparam logic [2:0] INVALIDA = 3'd4;
  localparam logic [2:0] VICTORIA = 3'd5;

  localparam logic [3:0] NOTA_SIL = 4'd0;
  localparam logic [3:0] NOTA_A3 = 4'd1;
  localparam logic [3:0] NOTA_C4 = 4'd2;
  localparam logic [3:0] NOTA_E4 = 4'd3;
  localparam logic [3:0] NOTA_G4 = 4'd4;
  localparam logic [3:0] NOTA_C5 = 4'd5;
  localparam logic [3:0] NOTA_E5 = 4'd6;
  localparam logic [3:0] NOTA_G5 = 4'd7;
  localparam logic [3:0] NOTA_C6 = 4'd8;
  localparam logic [3:0] NOTA_E6 = 4'd9;
  localparam logic [3:0] NOTA_G6 = 4'd10;

  // N = f_clk / (2 f) - 1, igual que en el P2, asi en simulacion se reescalan solos con CLK_FREQ_HZ
  localparam int N_A3 = CLK_FREQ_HZ / (2 * 220) - 1;
  localparam int N_C4 = CLK_FREQ_HZ / (2 * 262) - 1;
  localparam int N_E4 = CLK_FREQ_HZ / (2 * 330) - 1;
  localparam int N_G4 = CLK_FREQ_HZ / (2 * 392) - 1;
  localparam int N_C5 = CLK_FREQ_HZ / (2 * 523) - 1;
  localparam int N_E5 = CLK_FREQ_HZ / (2 * 659) - 1;
  localparam int N_G5 = CLK_FREQ_HZ / (2 * 784) - 1;
  localparam int N_C6 = CLK_FREQ_HZ / (2 * 1047) - 1;
  localparam int N_E6 = CLK_FREQ_HZ / (2 * 1319) - 1;
  localparam int N_G6 = CLK_FREQ_HZ / (2 * 1568) - 1;

  localparam int CICLOS_UNIDAD = CLK_FREQ_HZ / 1000 * UNIDAD_MS;
  localparam int ANCHO_CICLOS = $clog2(CICLOS_UNIDAD);

  logic [ANCHO_CICLOS-1:0] cont_ciclos;
  logic [2:0] cont_unidades;
  logic [2:0] paso;
  logic [6:0] palabra;
  logic [3:0] nota;
  logic [2:0] dur;
  logic tick_unidad;
  logic fin_nota;

  // Cada palabra es {nota, dur}, dur en unidades de 50 ms y dur = 0 marca el fin
  always_comb begin
    case ({i_sonido, paso})
      {IMPACTO, 3'd0}: palabra = {NOTA_G5, 3'd1};
      {IMPACTO, 3'd1}: palabra = {NOTA_C6, 3'd1};
      {IMPACTO, 3'd2}: palabra = {NOTA_E6, 3'd2};

      {FALLO, 3'd0}: palabra = {NOTA_G4, 3'd2};
      {FALLO, 3'd1}: palabra = {NOTA_E4, 3'd2};
      {FALLO, 3'd2}: palabra = {NOTA_C4, 3'd3};

      {HUNDIDO, 3'd0}: palabra = {NOTA_E6, 3'd1};
      {HUNDIDO, 3'd1}: palabra = {NOTA_C6, 3'd1};
      {HUNDIDO, 3'd2}: palabra = {NOTA_G5, 3'd1};
      {HUNDIDO, 3'd3}: palabra = {NOTA_E5, 3'd1};
      {HUNDIDO, 3'd4}: palabra = {NOTA_C5, 3'd1};
      {HUNDIDO, 3'd5}: palabra = {NOTA_SIL, 3'd1};
      {HUNDIDO, 3'd6}: palabra = {NOTA_C5, 3'd4};

      {INVALIDA, 3'd0}: palabra = {NOTA_A3, 3'd2};
      {INVALIDA, 3'd1}: palabra = {NOTA_SIL, 3'd1};
      {INVALIDA, 3'd2}: palabra = {NOTA_A3, 3'd2};

      {VICTORIA, 3'd0}: palabra = {NOTA_C5, 3'd2};
      {VICTORIA, 3'd1}: palabra = {NOTA_E5, 3'd2};
      {VICTORIA, 3'd2}: palabra = {NOTA_G5, 3'd2};
      {VICTORIA, 3'd3}: palabra = {NOTA_C6, 3'd4};
      {VICTORIA, 3'd4}: palabra = {NOTA_SIL, 3'd1};
      {VICTORIA, 3'd5}: palabra = {NOTA_G5, 3'd1};
      {VICTORIA, 3'd6}: palabra = {NOTA_C6, 3'd7};

      default: palabra = {NOTA_SIL, 3'd0}; // SILENCIO, 110 y 111 son fin en todos sus pasos y el secuenciador queda en reposo
    endcase
  end

  assign nota = palabra[6:3];
  assign dur = palabra[2:0];

  always_comb begin
    case (nota)
      NOTA_A3: o_n = N_A3[17:0];
      NOTA_C4: o_n = N_C4[17:0];
      NOTA_E4: o_n = N_E4[17:0];
      NOTA_G4: o_n = N_G4[17:0];
      NOTA_C5: o_n = N_C5[17:0];
      NOTA_E5: o_n = N_E5[17:0];
      NOTA_G5: o_n = N_G5[17:0];
      NOTA_C6: o_n = N_C6[17:0];
      NOTA_E6: o_n = N_E6[17:0];
      NOTA_G6: o_n = N_G6[17:0];
      default: o_n = '0;
    endcase
  end

  assign tick_unidad = cont_ciclos == ANCHO_CICLOS'(CICLOS_UNIDAD - 1);
  assign fin_nota = tick_unidad && cont_unidades == dur - 3'd1;

  // i_iniciar va primero para cortar una melodia en cualquier punto, y el fin antes que fin_nota para no seguir contando sobre una terminada
  always_ff @(posedge clk) begin
    if (rst || i_iniciar) begin
      cont_ciclos <= '0;
      cont_unidades <= '0;
      paso <= '0;
    end
    else if (dur == 3'd0) begin
      cont_ciclos <= '0;
      cont_unidades <= '0;
    end
    else if (fin_nota) begin
      cont_ciclos <= '0;
      cont_unidades <= '0;
      paso <= paso + 3'd1;
    end
    else if (tick_unidad) begin
      cont_ciclos <= '0;
      cont_unidades <= cont_unidades + 3'd1;
    end
    else cont_ciclos <= cont_ciclos + 1'b1;
  end

  assign o_fin = dur == 3'd0;
  assign o_sonar = dur != 3'd0 && nota != NOTA_SIL;

endmodule
