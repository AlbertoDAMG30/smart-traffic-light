`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: uart_module
// Description: Módulo UART para comunicación bidireccional con la PC
//              Soporta 115200 baudios a 100MHz
//////////////////////////////////////////////////////////////////////////////////

module uart_module(
    input clk,              // Reloj principal 100MHz
    input reset,            
    input rx,               // Línea de recepción UART
    input tx_start,         // Señal para iniciar transmisión
    input [7:0] tx_data,    // Datos a transmitir
    output tx,              // Línea de transmisión UART
    output tx_busy,         // Indica si está transmitiendo
    output rx_ready,        // Indica datos recibidos listos
    output [7:0] rx_data    // Datos recibidos
);

    // Parámetros para 115200 baudios con reloj de 100MHz
    // 100MHz / 115200 = 868
    parameter CLKS_PER_BIT = 868;
    
    //===========================================
    // Transmisor UART
    //===========================================
    reg [9:0] tx_counter = 0;
    reg [3:0] tx_bit_index = 0;
    reg [9:0] tx_shifter = 10'h3FF;  // Inicializado con bits de stop
    reg tx_active = 0;
    
    assign tx = tx_shifter[0];
    assign tx_busy = tx_active;
    
    always @(posedge clk) begin
        if (reset) begin
            tx_counter <= 0;
            tx_bit_index <= 0;
            tx_shifter <= 10'h3FF;
            tx_active <= 0;
        end else begin
            if (!tx_active && tx_start) begin
                // Cargar datos con bit de start (0) y bit de stop (1)
                tx_shifter <= {1'b1, tx_data, 1'b0};
                tx_active <= 1;
                tx_bit_index <= 0;
                tx_counter <= 0;
            end else if (tx_active) begin
                if (tx_counter >= CLKS_PER_BIT - 1) begin
                    tx_counter <= 0;
                    tx_shifter <= {1'b1, tx_shifter[9:1]};
                    tx_bit_index <= tx_bit_index + 1;
                    
                    if (tx_bit_index >= 9) begin
                        tx_active <= 0;
                    end
                end else begin
                    tx_counter <= tx_counter + 1;
                end
            end
        end
    end
    
    //===========================================
    // Receptor UART
    //===========================================
    reg [9:0] rx_counter = 0;
    reg [3:0] rx_bit_index = 0;
    reg [8:0] rx_shifter = 0;
    reg rx_active = 0;
    reg rx_done = 0;
    reg [7:0] rx_byte = 0;
    reg rx_d1 = 1;
    reg rx_d2 = 1;
    
    assign rx_ready = rx_done;
    assign rx_data = rx_byte;
    
    // Sincronización de la señal RX con doble registro
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            rx_counter <= 0;
            rx_bit_index <= 0;
            rx_shifter <= 0;
            rx_active <= 0;
            rx_done <= 0;
            rx_byte <= 0;
        end else begin
            rx_done <= 0;  // Pulso de un ciclo
            
            if (!rx_active && !rx_d2) begin
                // Detectar bit de start
                rx_active <= 1;
                rx_counter <= CLKS_PER_BIT / 2;  // Muestrear en el centro del bit
                rx_bit_index <= 0;
            end else if (rx_active) begin
                if (rx_counter >= CLKS_PER_BIT - 1) begin
                    rx_counter <= 0;
                    
                    if (rx_bit_index < 9) begin
                        rx_shifter <= {rx_d2, rx_shifter[8:1]};
                        rx_bit_index <= rx_bit_index + 1;
                    end else begin
                        // Verificar bit de stop
                        if (rx_d2) begin
                            rx_byte <= rx_shifter[7:0];
                            rx_done <= 1;
                        end
                        rx_active <= 0;
                    end
                end else begin
                    rx_counter <= rx_counter + 1;
                end
            end
        end
    end

endmodule