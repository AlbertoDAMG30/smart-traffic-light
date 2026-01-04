`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: divisor_reloj_semaforo
// Description: Divisor de reloj simplificado para semáforo inteligente
//              Genera frecuencias esenciales para el funcionamiento
//////////////////////////////////////////////////////////////////////////////////

module divisor_reloj_semaforo(
    input clk,                  // Reloj de entrada 100 MHz
    output reg clk_1sec = 0,    // 1 Hz para temporizadores del semáforo
    output reg clk_fast = 0     // ~100 Hz para comunicación UART
);

    reg [26:0] contador = 0;

    always @(posedge clk) begin
        contador <= contador + 1;
        
        // clk_fast: ~100 Hz para comunicación UART y actualizaciones rápidas
        // 100MHz / 100Hz = 1,000,000 → 2^20 ≈ 1,048,576 (aproximado)
        clk_fast <= contador[19];
        
        // clk_1sec: 1 Hz para temporizadores principales
        // 100MHz / 1Hz = 100,000,000 → 2^26 = 67,108,864 (aproximado)
        clk_1sec <= contador[25];
    end

endmodule