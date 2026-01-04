`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: semaforo_fsm
// Description: Máquina de estados para semáforo inteligente con EMERGENCIA
//              Incluye estado de emergencia que pausa el estado actual
//              VERSIÓN MEJORADA: Límite de 15 vehículos y lógica de justicia
//////////////////////////////////////////////////////////////////////////////////

module semaforo_fsm(
    input clk,                      // Reloj principal 
    input reset,                    // Reset (btnc)
    input clk_1sec,                 // Reloj de 1 segundo para temporizadores
    input [15:0] sw,                // Switches para configuración y simulación
    input btn_manual,               // Botón para modo manual
    input btn_ciclo,                // Botón para forzar ciclo
    input btn_emergencia,           // Botón de emergencia
    input btn_nocturno,             // Botón modo nocturno
    input emergencia_uart,          // Señal de emergencia desde UART
    
    // Salidas para comunicación con módulo principal
    output reg [2:0] estado_actual = 0, // Estado actual para otros módulos
    output reg [5:0] tiempo_restante = 0, // Tiempo restante en estado actual
    output reg [3:0] trafico_norte = 0,   // Contador tráfico Norte  
    output reg [3:0] trafico_sur = 0,     // Contador tráfico Sur
    output reg [3:0] trafico_este = 0,    // Contador tráfico Este
    output reg [3:0] trafico_oeste = 0,   // Contador tráfico Oeste
    output reg emergencia_activa = 0      // Indicador de emergencia activa
);

    // Definición de estados
    parameter INICIO               = 3'b000;
    parameter EVALUACION           = 3'b001;
    parameter NORTE_SUR_VERDE      = 3'b010;
    parameter NORTE_SUR_AMARILLO   = 3'b011;
    parameter TODO_ROJO_1          = 3'b100;
    parameter ESTE_OESTE_VERDE     = 3'b101;
    parameter ESTE_OESTE_AMARILLO  = 3'b110;
    parameter TODO_ROJO_2          = 3'b111;
    
    // Variables de control
    reg [5:0] contador_tiempo = 0;      // Contador principal de tiempo
    reg modo_nocturno = 0;              // Flag modo nocturno
    reg modo_manual = 0;                // Flag modo manual
    reg [1:0] direccion_emergencia = 0; // 0=NS, 1=EO
    
    // Variables para el estado INICIO
    reg sistema_iniciado = 0;           // Flag para indicar si el sistema ya se inició
    reg [3:0] trafico_norte_config = 0; // Configuración manual Norte
    reg [3:0] trafico_sur_config = 0;   // Configuración manual Sur
    reg [3:0] trafico_este_config = 0;  // Configuración manual Este
    reg [3:0] trafico_oeste_config = 0; // Configuración manual Oeste
    
    // Variables para control de optimización
    reg [5:0] tiempo_sin_trafico = 0;   // Contador de tiempo sin tráfico en dirección actual
    parameter TIEMPO_GRACIA = 4;        // 4 segundos de gracia antes de cambiar
    parameter TIEMPO_VERDE_MIN_ABS = 8; // Tiempo mínimo absoluto en verde (8 segundos)
    reg [5:0] tiempo_en_estado = 0;     // Tiempo transcurrido en el estado actual
    
    // NUEVAS VARIABLES PARA LÓGICA DE JUSTICIA
    reg [4:0] vehiculos_procesados_actual = 0; // Contador de vehículos que han pasado en el estado actual
    parameter MAX_VEHICULOS_ANTES_CAMBIO = 8;  // Máximo 8 vehículos antes de considerar cambio por justicia
    parameter LIMITE_TRAFICO_MAXIMO = 15;      // Nuevo límite máximo de 15 vehículos por cola
    
    // VARIABLES PARA EMERGENCIA
    reg en_emergencia = 0;              // Flag indicando si estamos en emergencia
    reg [2:0] estado_guardado = 0;      // Estado antes de emergencia
    reg [5:0] tiempo_guardado = 0;      // Tiempo restante antes de emergencia
    reg [5:0] contador_emergencia = 0;  // Contador para tiempo de emergencia
    parameter TIEMPO_EMERGENCIA = 10;   // 10 segundos de emergencia
    
    // Temporizadores por estado (en segundos)
    parameter TIEMPO_VERDE_MIN     = 15;    // Verde mínimo
    parameter TIEMPO_VERDE_MAX     = 45;    // Verde máximo
    parameter TIEMPO_AMARILLO      = 3;     // Amarillo fijo
    parameter TIEMPO_TODO_ROJO     = 2;     // Todo rojo (seguridad)
    parameter TIEMPO_EVALUACION    = 3;     // Tiempo para evaluación
    
    // Variables para detección de flancos de botones
    reg btn_manual_prev = 0;
    reg btn_ciclo_prev = 0; 
    reg btn_emergencia_prev = 0;
    reg btn_nocturno_prev = 0;
    reg emergencia_uart_prev = 0;
    
    // Variables para detección de flancos de switches
    reg sw11_prev = 0;
    reg [3:0] sw_trafico_prev = 0;
    
    wire btn_manual_edge = btn_manual && !btn_manual_prev;
    wire btn_ciclo_edge = btn_ciclo && !btn_ciclo_prev;
    wire btn_emergencia_edge = (btn_emergencia && !btn_emergencia_prev) || (emergencia_uart && !emergencia_uart_prev);
    wire btn_nocturno_edge = btn_nocturno && !btn_nocturno_prev;
    wire sw11_edge = sw[11] && !sw11_prev;
    
    // Función: Verificar si hay tráfico pendiente en otras direcciones
    function tiene_trafico_pendiente_otras_direcciones;
        input [2:0] estado_check;
        begin
            case (estado_check)
                NORTE_SUR_VERDE: begin
                    tiene_trafico_pendiente_otras_direcciones = (trafico_este > 0) || (trafico_oeste > 0);
                end
                ESTE_OESTE_VERDE: begin
                    tiene_trafico_pendiente_otras_direcciones = (trafico_norte > 0) || (trafico_sur > 0);
                end
                default: begin
                    tiene_trafico_pendiente_otras_direcciones = 0;
                end
            endcase
        end
    endfunction
    
    // Función: Verificar si la dirección actual no tiene más tráfico
    function no_hay_trafico_direccion_actual;
        input [2:0] estado_check;
        begin
            case (estado_check)
                NORTE_SUR_VERDE: begin
                    no_hay_trafico_direccion_actual = (trafico_norte == 0) && (trafico_sur == 0);
                end
                ESTE_OESTE_VERDE: begin
                    no_hay_trafico_direccion_actual = (trafico_este == 0) && (trafico_oeste == 0);
                end
                default: begin
                    no_hay_trafico_direccion_actual = 0;
                end
            endcase
        end
    endfunction
    
    // NUEVA FUNCIÓN: Verificar condición de justicia (8 vehículos procesados y hay tráfico esperando)
    function debe_cambiar_por_justicia;
        input [2:0] estado_check;
        begin
            debe_cambiar_por_justicia = (vehiculos_procesados_actual >= MAX_VEHICULOS_ANTES_CAMBIO) && 
                                      tiene_trafico_pendiente_otras_direcciones(estado_check);
        end
    endfunction
    
    // Gestión de tráfico en estado INICIO
    always @(posedge clk) begin
        if (reset) begin
            trafico_norte_config <= 0;
            trafico_sur_config <= 0;
            trafico_este_config <= 0;
            trafico_oeste_config <= 0;
            sistema_iniciado <= 0;
        end else if (estado_actual == INICIO && !sistema_iniciado) begin
            // En estado INICIO, usar switches para configurar tráfico manualmente
            if (sw[15] && !sw_trafico_prev[3] && trafico_norte_config < LIMITE_TRAFICO_MAXIMO)
                trafico_norte_config <= trafico_norte_config + 1;
            if (sw[14] && !sw_trafico_prev[2] && trafico_oeste_config < LIMITE_TRAFICO_MAXIMO)
                trafico_oeste_config <= trafico_oeste_config + 1;
            if (sw[13] && !sw_trafico_prev[1] && trafico_sur_config < LIMITE_TRAFICO_MAXIMO)
                trafico_sur_config <= trafico_sur_config + 1;
            if (sw[12] && !sw_trafico_prev[0] && trafico_este_config < LIMITE_TRAFICO_MAXIMO)
                trafico_este_config <= trafico_este_config + 1;
                
            sw_trafico_prev <= sw[15:12];
        end
    end
    
    // Máquina de estados principal
    always @(posedge clk_1sec or posedge reset) begin
        if (reset) begin
            estado_actual <= INICIO;
            contador_tiempo <= 0;
            modo_nocturno <= 0;
            modo_manual <= 0;
            emergencia_activa <= 0;
            direccion_emergencia <= 0;
            trafico_norte <= 0;
            trafico_sur <= 0;
            trafico_este <= 0;
            trafico_oeste <= 0;
            sistema_iniciado <= 0;
            tiempo_sin_trafico <= 0;
            tiempo_en_estado <= 0;
            vehiculos_procesados_actual <= 0;  // Reset contador de vehículos procesados
            // Variables de emergencia
            en_emergencia <= 0;
            estado_guardado <= 0;
            tiempo_guardado <= 0;
            contador_emergencia <= 0;
        end else begin
            // Actualizar registros previos para detección de flancos
            btn_manual_prev <= btn_manual;
            btn_ciclo_prev <= btn_ciclo;
            btn_emergencia_prev <= btn_emergencia;
            btn_nocturno_prev <= btn_nocturno;
            emergencia_uart_prev <= emergencia_uart;
            sw11_prev <= sw[11];
            
            // LÓGICA DE EMERGENCIA
            if (btn_emergencia_edge && !en_emergencia) begin
                en_emergencia <= 1;
                emergencia_activa <= 1;
                estado_guardado <= estado_actual;
                tiempo_guardado <= contador_tiempo;
                contador_emergencia <= TIEMPO_EMERGENCIA;
                // Poner todo en rojo inmediatamente
                estado_actual <= TODO_ROJO_1;
                contador_tiempo <= TIEMPO_EMERGENCIA;
            end else if (emergencia_uart && !en_emergencia) begin
                en_emergencia <= 1;
                emergencia_activa <= 1;
                estado_guardado <= estado_actual;
                tiempo_guardado <= contador_tiempo;
                contador_emergencia <= TIEMPO_EMERGENCIA;
                // Poner todo en rojo inmediatamente
                estado_actual <= TODO_ROJO_1;
                contador_tiempo <= TIEMPO_EMERGENCIA;
            end else if (en_emergencia) begin
                // Gestión del estado de emergencia
                if (contador_emergencia > 0) begin
                    contador_emergencia <= contador_emergencia - 1;
                    contador_tiempo <= contador_emergencia;
                    // Mantener todo en rojo durante emergencia
                    estado_actual <= TODO_ROJO_1;
                end else begin
                    // Fin de emergencia - restaurar estado anterior
                    en_emergencia <= 0;
                    emergencia_activa <= 0;
                    estado_actual <= estado_guardado;
                    contador_tiempo <= tiempo_guardado;
                    contador_emergencia <= 0;
                end
            end else begin
                // Procesar comandos normales solo si no estamos en emergencia
                if (sistema_iniciado) begin
                    if (btn_nocturno_edge) begin
                        modo_nocturno <= !modo_nocturno;
                    end
                    
                    if (btn_manual_edge) begin
                        modo_manual <= !modo_manual;
                    end
                end
                
                // Lógica normal de estados (solo si no estamos en emergencia)
                case (estado_actual)
                    INICIO: begin
                        trafico_norte <= trafico_norte_config;
                        trafico_sur <= trafico_sur_config;
                        trafico_este <= trafico_este_config;
                        trafico_oeste <= trafico_oeste_config;
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        vehiculos_procesados_actual <= 0;
                        
                        if (sw11_edge) begin
                            sistema_iniciado <= 1;
                            contador_tiempo <= TIEMPO_EVALUACION;
                            estado_actual <= EVALUACION;
                        end
                    end
                    
                    EVALUACION: begin
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        vehiculos_procesados_actual <= 0;
                        
                        if (contador_tiempo > 0) begin
                            contador_tiempo <= contador_tiempo - 1;
                        end else begin
                            if ((trafico_norte + trafico_sur) >= (trafico_este + trafico_oeste)) begin
                                contador_tiempo <= calcular_tiempo_verde(trafico_norte + trafico_sur);
                                estado_actual <= NORTE_SUR_VERDE;
                            end else begin
                                contador_tiempo <= calcular_tiempo_verde(trafico_este + trafico_oeste);
                                estado_actual <= ESTE_OESTE_VERDE;
                            end
                        end
                    end
                    
                    NORTE_SUR_VERDE: begin
                        tiempo_en_estado <= tiempo_en_estado + 1;
                        
                        if (no_hay_trafico_direccion_actual(estado_actual)) begin
                            tiempo_sin_trafico <= tiempo_sin_trafico + 1;
                        end else begin
                            tiempo_sin_trafico <= 0;
                        end
                        
                        // LÓGICA MEJORADA: Incluir condición de justicia
                        if (btn_ciclo_edge || (contador_tiempo == 0) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             tiempo_sin_trafico >= TIEMPO_GRACIA && 
                             tiene_trafico_pendiente_otras_direcciones(estado_actual)) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             tiempo_sin_trafico >= TIEMPO_GRACIA && 
                             !tiene_trafico_pendiente_otras_direcciones(estado_actual)) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             debe_cambiar_por_justicia(estado_actual))) begin  // NUEVA CONDICIÓN DE JUSTICIA
                            
                            contador_tiempo <= TIEMPO_AMARILLO;
                            estado_actual <= NORTE_SUR_AMARILLO;
                            tiempo_sin_trafico <= 0;
                            tiempo_en_estado <= 0;
                            vehiculos_procesados_actual <= 0;  // Reset contador para próximo estado
                        end else begin
                            contador_tiempo <= contador_tiempo - 1;
                            // Procesar vehículos y contar los que pasan
                            if (trafico_norte > 0) begin
                                trafico_norte <= trafico_norte - 1;
                                vehiculos_procesados_actual <= vehiculos_procesados_actual + 1;
                            end
                            if (trafico_sur > 0) begin
                                trafico_sur <= trafico_sur - 1;
                                vehiculos_procesados_actual <= vehiculos_procesados_actual + 1;
                            end
                            // Agregar tráfico desde switches con nuevo límite
                            if (sw[0] && trafico_este < LIMITE_TRAFICO_MAXIMO) trafico_este <= trafico_este + 1;
                            if (sw[1] && trafico_oeste < LIMITE_TRAFICO_MAXIMO) trafico_oeste <= trafico_oeste + 1;
                        end
                    end
                    
                    NORTE_SUR_AMARILLO: begin
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        
                        if (contador_tiempo > 0) begin
                            contador_tiempo <= contador_tiempo - 1;
                        end else begin
                            contador_tiempo <= TIEMPO_TODO_ROJO;
                            estado_actual <= TODO_ROJO_1;
                        end
                    end
                    
                    TODO_ROJO_1: begin
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        vehiculos_procesados_actual <= 0;
                        
                        if (contador_tiempo > 0) begin
                            contador_tiempo <= contador_tiempo - 1;
                        end else begin
                            contador_tiempo <= calcular_tiempo_verde(trafico_este + trafico_oeste);
                            estado_actual <= ESTE_OESTE_VERDE;
                        end
                    end
                    
                    ESTE_OESTE_VERDE: begin
                        tiempo_en_estado <= tiempo_en_estado + 1;
                        
                        if (no_hay_trafico_direccion_actual(estado_actual)) begin
                            tiempo_sin_trafico <= tiempo_sin_trafico + 1;
                        end else begin
                            tiempo_sin_trafico <= 0;
                        end
                        
                        // LÓGICA MEJORADA: Incluir condición de justicia
                        if (btn_ciclo_edge || (contador_tiempo == 0) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             tiempo_sin_trafico >= TIEMPO_GRACIA && 
                             tiene_trafico_pendiente_otras_direcciones(estado_actual)) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             tiempo_sin_trafico >= TIEMPO_GRACIA && 
                             !tiene_trafico_pendiente_otras_direcciones(estado_actual)) ||
                            (tiempo_en_estado >= TIEMPO_VERDE_MIN_ABS && 
                             debe_cambiar_por_justicia(estado_actual))) begin  // NUEVA CONDICIÓN DE JUSTICIA
                            
                            contador_tiempo <= TIEMPO_AMARILLO;
                            estado_actual <= ESTE_OESTE_AMARILLO;
                            tiempo_sin_trafico <= 0;
                            tiempo_en_estado <= 0;
                            vehiculos_procesados_actual <= 0;  // Reset contador para próximo estado
                        end else begin
                            contador_tiempo <= contador_tiempo - 1;
                            // Procesar vehículos y contar los que pasan
                            if (trafico_este > 0) begin
                                trafico_este <= trafico_este - 1;
                                vehiculos_procesados_actual <= vehiculos_procesados_actual + 1;
                            end
                            if (trafico_oeste > 0) begin
                                trafico_oeste <= trafico_oeste - 1;
                                vehiculos_procesados_actual <= vehiculos_procesados_actual + 1;
                            end
                            // Agregar tráfico desde switches con nuevo límite
                            if (sw[2] && trafico_norte < LIMITE_TRAFICO_MAXIMO) trafico_norte <= trafico_norte + 1;
                            if (sw[3] && trafico_sur < LIMITE_TRAFICO_MAXIMO) trafico_sur <= trafico_sur + 1;
                        end
                    end
                    
                    ESTE_OESTE_AMARILLO: begin
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        
                        if (contador_tiempo > 0) begin
                            contador_tiempo <= contador_tiempo - 1;
                        end else begin
                            contador_tiempo <= TIEMPO_TODO_ROJO;
                            estado_actual <= TODO_ROJO_2;
                        end
                    end
                    
                    TODO_ROJO_2: begin
                        tiempo_sin_trafico <= 0;
                        tiempo_en_estado <= 0;
                        vehiculos_procesados_actual <= 0;
                        
                        if (contador_tiempo > 0) begin
                            contador_tiempo <= contador_tiempo - 1;
                        end else begin
                            contador_tiempo <= calcular_tiempo_verde(trafico_norte + trafico_sur);
                            estado_actual <= NORTE_SUR_VERDE;
                        end
                    end
                    
                    default: estado_actual <= INICIO;
                endcase
            end
            
            // Asignar tiempo restante para salida
            tiempo_restante <= contador_tiempo;
        end
    end
    
    // Función para calcular tiempo verde basado en tráfico
    function [5:0] calcular_tiempo_verde;
        input [4:0] cantidad_trafico;
        begin
            if (cantidad_trafico <= 2)
                calcular_tiempo_verde = TIEMPO_VERDE_MIN;
            else if (cantidad_trafico >= 8)
                calcular_tiempo_verde = TIEMPO_VERDE_MAX;
            else
                calcular_tiempo_verde = TIEMPO_VERDE_MIN + (cantidad_trafico * 3);
        end
    endfunction

endmodule