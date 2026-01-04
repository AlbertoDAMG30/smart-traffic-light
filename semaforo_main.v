`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: semaforo_main
// Description: Módulo principal del Semáforo Inteligente con Emergencia
//              Integra FSM, comunicación UART y control de emergencia
//              VERSIÓN CORREGIDA - Emergencia UART funciona simulando botón físico
//////////////////////////////////////////////////////////////////////////////////

module semaforo_main(
    input clk,                  // Reloj principal 100MHz
    input btnc,                 // Reset general
    input btn_manual,           // Modo manual
    input btn_ciclo,            // Forzar ciclo
    input btn_emergencia,       // Emergencia
    input btn_nocturno,         // Modo nocturno
    input [15:0] sw,            // Switches para configuración
    input rx,                   // UART RX
    
    // Salidas
    output tx,                  // UART TX
    // LEDs de semáforo (añadidos de vuelta para visualización)
    output led_ns_verde,
    output led_ns_amarillo,
    output led_ns_rojo,
    output led_eo_verde,
    output led_eo_amarillo,
    output led_eo_rojo,
    output led_emergencia,      // LED RGB rojo para emergencia
    output [1:0] led_estado     // LEDs de estado
);

    // Señales de reloj
    wire clk_1sec;       // 1 Hz para temporizadores del semáforo
    wire clk_fast;       // ~100 Hz para actualizaciones rápidas
    
    // Señales de la máquina de estados del semáforo
    wire [2:0] estado_actual;
    wire [5:0] tiempo_restante;
    wire [3:0] trafico_norte, trafico_sur, trafico_este, trafico_oeste;
    wire emergencia_activa_fsm;
    
    // Señales UART
    wire tx_busy;
    wire rx_ready;
    wire [7:0] rx_data;
    reg tx_start = 0;
    reg [7:0] tx_data = 0;
    
    // ============================================
    // SIMULACIÓN DE BOTÓN DE EMERGENCIA VIA UART
    // ============================================
    reg btn_emergencia_uart = 0;
    reg [15:0] uart_btn_timer = 0;
    reg emergencia_uart_flag = 0;

    // Parámetros para simular presión de botón
    parameter BTN_PRESS_DURATION = 16'd5000;   // ~50µs a 100MHz (suficiente para detectar edge)
    parameter BTN_RELEASE_DURATION = 16'd5000; // ~50µs de pausa antes de poder presionar otra vez
    
    // Estados para comunicación UART
    reg [2:0] uart_state = 0;
    parameter UART_IDLE = 3'b000;
    parameter UART_SEND_BYTE = 3'b001;
    parameter UART_WAIT_COMPLETE = 3'b010;
    parameter UART_NEXT_BYTE = 3'b011;
    parameter UART_DONE = 3'b100;
    
    // Contador para envío periódico
    reg [27:0] send_timer = 0;
    parameter SEND_INTERVAL = 100_000_000; // 1 segundo a 100MHz
    
    // Buffer para mensajes UART
    reg [7:0] status_message [0:34];
    reg [5:0] byte_index = 0;
    reg [5:0] message_length = 0;
    reg send_trigger = 0;
    
    // Registro para detectar cuando tx_busy baja
    reg tx_busy_prev = 0;
    
    // Divisor de reloj especializado para semáforo
    divisor_reloj_semaforo divisor(
        .clk(clk),
        .clk_1sec(clk_1sec),
        .clk_fast(clk_fast)
    );
    
    // Máquina de estados del semáforo
    semaforo_fsm fsm(
        .clk(clk),
        .reset(btnc),
        .clk_1sec(clk_1sec),
        .sw(sw),
        .btn_manual(btn_manual),
        .btn_ciclo(btn_ciclo),
        .btn_emergencia(btn_emergencia || btn_emergencia_uart), // ← COMBINAMOS AMBAS SEÑALES
        .btn_nocturno(btn_nocturno),
        // ELIMINAMOS: .emergencia_uart ya no se necesita
        
        // Estado para comunicación
        .estado_actual(estado_actual),
        .tiempo_restante(tiempo_restante),
        .trafico_norte(trafico_norte),
        .trafico_sur(trafico_sur),
        .trafico_este(trafico_este),
        .trafico_oeste(trafico_oeste),
        .emergencia_activa(emergencia_activa_fsm)
    );
    
    // Módulo UART
    uart_module uart(
        .clk(clk),
        .reset(btnc),
        .rx(rx),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(tx),
        .tx_busy(tx_busy),
        .rx_ready(rx_ready),
        .rx_data(rx_data)
    );
    
    // Control de LEDs del semáforo según estado
    assign led_ns_verde = (estado_actual == 3'b010) && !emergencia_activa_fsm;  // NORTE_SUR_VERDE
    assign led_ns_amarillo = (estado_actual == 3'b011) && !emergencia_activa_fsm; // NORTE_SUR_AMARILLO
    assign led_ns_rojo = (estado_actual != 3'b010 && estado_actual != 3'b011) || emergencia_activa_fsm;
    
    assign led_eo_verde = (estado_actual == 3'b101) && !emergencia_activa_fsm;  // ESTE_OESTE_VERDE
    assign led_eo_amarillo = (estado_actual == 3'b110) && !emergencia_activa_fsm; // ESTE_OESTE_AMARILLO
    assign led_eo_rojo = (estado_actual != 3'b101 && estado_actual != 3'b110) || emergencia_activa_fsm;
    
    // LED de emergencia (RGB rojo)
    assign led_emergencia = emergencia_activa_fsm;
    
    // LEDs de estado
    assign led_estado = estado_actual[1:0];
    
    // ============================================
    // PROCESAMIENTO DE COMANDOS UART - VERSIÓN SIMPLE
    // ============================================
    always @(posedge clk) begin
        if (btnc) begin
            btn_emergencia_uart <= 0;
            uart_btn_timer <= 0;
            emergencia_uart_flag <= 0;
        end else begin
            // Detectar comando de emergencia UART
            if (rx_ready && (rx_data == 8'h45 || rx_data == 8'h65) && !emergencia_uart_flag) begin
                // Iniciar simulación de presión de botón
                btn_emergencia_uart <= 1;
                uart_btn_timer <= BTN_PRESS_DURATION;
                emergencia_uart_flag <= 1;
            end else if (uart_btn_timer > 0) begin
                // Mantener botón presionado durante el timer
                uart_btn_timer <= uart_btn_timer - 1;
                if (uart_btn_timer == 1) begin
                    // Soltar botón al final del timer
                    btn_emergencia_uart <= 0;
                end
            end else if (emergencia_uart_flag && uart_btn_timer == 0) begin
                // Cooldown después de soltar el botón
                emergencia_uart_flag <= 0; // Permitir nueva activación
            end
        end
    end
    
    // Timer para envío periódico
    always @(posedge clk) begin
        if (btnc) begin
            send_timer <= 0;
            send_trigger <= 0;
        end else begin
            if (send_timer >= SEND_INTERVAL) begin
                send_timer <= 0;
                send_trigger <= 1;
            end else begin
                send_timer <= send_timer + 1;
                send_trigger <= 0;
            end
        end
    end
    
    // Control de transmisión UART
    always @(posedge clk) begin
        if (btnc) begin
            uart_state <= UART_IDLE;
            tx_start <= 0;
            byte_index <= 0;
            tx_busy_prev <= 0;
        end else begin
            // Guardar estado previo de tx_busy para detectar flancos
            tx_busy_prev <= tx_busy;
            
            case (uart_state)
                UART_IDLE: begin
                    tx_start <= 0;
                    if (send_trigger && !tx_busy) begin
                        // Preparar mensaje
                        prepare_status_message();
                        byte_index <= 0;
                        uart_state <= UART_SEND_BYTE;
                    end
                end
                
                UART_SEND_BYTE: begin
                    if (!tx_busy && !tx_start) begin
                        // Cargar siguiente byte
                        if (byte_index < message_length) begin
                            tx_data <= status_message[byte_index];
                            tx_start <= 1;
                            uart_state <= UART_WAIT_COMPLETE;
                        end else begin
                            // Mensaje completo
                            uart_state <= UART_DONE;
                        end
                    end
                end
                
                UART_WAIT_COMPLETE: begin
                    // Desactivar tx_start después de un ciclo
                    tx_start <= 0;
                    
                    // Esperar a que tx_busy baje (transmisión completa)
                    if (tx_busy_prev && !tx_busy) begin
                        uart_state <= UART_NEXT_BYTE;
                    end
                end
                
                UART_NEXT_BYTE: begin
                    byte_index <= byte_index + 1;
                    uart_state <= UART_SEND_BYTE;
                end
                
                UART_DONE: begin
                    // Pequeña pausa antes de volver a IDLE
                    uart_state <= UART_IDLE;
                end
                
                default: uart_state <= UART_IDLE;
            endcase
        end
    end
    
    // Tarea para preparar mensaje de estado expandido con emergencia
    task prepare_status_message;
        begin
            // Formato: "ST:X,T:YY,N:ZZ,S:ZZ,E:ZZ,O:ZZ,EM:X\n"
            status_message[0]  = 8'h53;  // 'S'
            status_message[1]  = 8'h54;  // 'T'
            status_message[2]  = 8'h3A;  // ':'
            status_message[3]  = 8'h30 + estado_actual;  // Estado (0-7)
            status_message[4]  = 8'h2C;  // ','
            status_message[5]  = 8'h54;  // 'T'
            status_message[6]  = 8'h3A;  // ':'
            
            // Tiempo en dos dígitos
            if (tiempo_restante > 99) begin
                status_message[7] = 8'h39;  // '9'
                status_message[8] = 8'h39;  // '9'
            end else begin
                status_message[7] = 8'h30 + (tiempo_restante / 10);
                status_message[8] = 8'h30 + (tiempo_restante % 10);
            end
            
            status_message[9]  = 8'h2C;  // ','
            status_message[10] = 8'h4E;  // 'N'
            status_message[11] = 8'h3A;  // ':'
            
            // Tráfico norte (dos dígitos)
            if (trafico_norte > 99) begin
                status_message[12] = 8'h39;  // '9'
                status_message[13] = 8'h39;  // '9'
            end else begin
                status_message[12] = 8'h30 + (trafico_norte / 10);
                status_message[13] = 8'h30 + (trafico_norte % 10);
            end
            
            status_message[14] = 8'h2C;  // ','
            status_message[15] = 8'h53;  // 'S'
            status_message[16] = 8'h3A;  // ':'
            
            // Tráfico sur (dos dígitos)
            if (trafico_sur > 99) begin
                status_message[17] = 8'h39;  // '9'
                status_message[18] = 8'h39;  // '9'
            end else begin
                status_message[17] = 8'h30 + (trafico_sur / 10);
                status_message[18] = 8'h30 + (trafico_sur % 10);
            end
            
            status_message[19] = 8'h2C;  // ','
            status_message[20] = 8'h45;  // 'E'
            status_message[21] = 8'h3A;  // ':'
            
            // Tráfico este (dos dígitos)
            if (trafico_este > 99) begin
                status_message[22] = 8'h39;  // '9'
                status_message[23] = 8'h39;  // '9'
            end else begin
                status_message[22] = 8'h30 + (trafico_este / 10);
                status_message[23] = 8'h30 + (trafico_este % 10);
            end
            
            status_message[24] = 8'h2C;  // ','
            status_message[25] = 8'h4F;  // 'O'
            status_message[26] = 8'h3A;  // ':'
            
            // Tráfico oeste (dos dígitos)
            if (trafico_oeste > 99) begin
                status_message[27] = 8'h39;  // '9'
                status_message[28] = 8'h39;  // '9'
            end else begin
                status_message[27] = 8'h30 + (trafico_oeste / 10);
                status_message[28] = 8'h30 + (trafico_oeste % 10);
            end
            
            // Estado de emergencia
            status_message[29] = 8'h2C;  // ','
            status_message[30] = 8'h45;  // 'E'
            status_message[31] = 8'h4D;  // 'M'
            status_message[32] = 8'h3A;  // ':'
            status_message[33] = emergencia_activa_fsm ? 8'h31 : 8'h30;  // '1' o '0'
            
            status_message[34] = 8'h0A;  // '\n'
            message_length = 35;
        end
    endtask

endmodule