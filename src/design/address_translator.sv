// Mapa: EL3313_proyecto3_2S2026, secciones 4.4.2 y 4.4.3.
// Solo control: DataOut y los rdata NO pasan por este modulo.
module address_translator (
    input  logic [31:0] address_i,       // CPU.DataAddress_o
    input  logic        write_enable_i, // CPU.we_o
    output logic ram_we,
    output logic uart_we,
    output logic gpio_we,
    output logic display_we,
    output logic led_we,
    output logic buzzer_we,
    output logic vga_we,
    output logic [2:0] mux_sel
);
    logic sel_ram, sel_uart, sel_gpio, sel_display;
    logic sel_led, sel_buzzer, sel_vga;
    logic aligned;

    assign aligned = (address_i[1:0] == 2'b00);

    // 4096 bytes = 1024 palabras. Ultima palabra: 0x0000_2FFC.
    assign sel_ram = aligned && (address_i[31:12] == 20'h00002);
    assign sel_uart = (address_i == 32'h0001_0040) ||
                      (address_i == 32'h0001_0044) ||
                      (address_i == 32'h0001_0048);
    assign sel_gpio    = (address_i == 32'h0001_0120);
    assign sel_display = (address_i == 32'h0001_0130);
    assign sel_led     = (address_i == 32'h0001_0138);
    assign sel_buzzer  = (address_i == 32'h0001_0140);
    // 2048 bytes = 512 palabras. Ultima palabra: 0x0001_17FC.
    assign sel_vga = aligned && (address_i[31:11] == 21'h00022);

    assign ram_we     = write_enable_i && sel_ram;
    assign uart_we    = write_enable_i && sel_uart;
    assign gpio_we    = 1'b0; // Estado de botones: solo lectura.
    assign display_we = write_enable_i && sel_display;
    assign led_we     = write_enable_i && sel_led;
    assign buzzer_we  = write_enable_i && sel_buzzer;
    assign vga_we     = write_enable_i && sel_vga;

    always_comb begin
        mux_sel = 3'b111; // Direccion no asignada o no alineada.
        if      (sel_ram)     mux_sel = 3'b000;
        else if (sel_uart)    mux_sel = 3'b001;
        else if (sel_gpio)    mux_sel = 3'b010;
        else if (sel_display) mux_sel = 3'b011;
        else if (sel_led)     mux_sel = 3'b100;
        else if (sel_buzzer)  mux_sel = 3'b101;
        else if (sel_vga)     mux_sel = 3'b110;
    end
endmodule
