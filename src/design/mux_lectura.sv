// Misma codificacion que address_translator.sv.
module mux_lectura (
    input  logic [2:0] mux_sel,
    input  logic [31:0] ram_dout, uart_dout, gpio_dout,
    input  logic [31:0] display_dout, led_dout, buzzer_dout, vga_dout,
    output logic [31:0] rdata_o // CPU.DataIn_i
);
    always_comb begin
        case (mux_sel)
            3'b000: rdata_o = ram_dout;
            3'b001: rdata_o = uart_dout;
            3'b010: rdata_o = gpio_dout;
            3'b011: rdata_o = display_dout;
            3'b100: rdata_o = led_dout;
            3'b101: rdata_o = buzzer_dout;
            3'b110: rdata_o = vga_dout;
            default: rdata_o = 32'h0000_0000;
        endcase
    end
endmodule
