#!/usr/bin/env python3
"""
Monitor Gráfico de Semáforo Inteligente vía UART
Visualización de intersección con interfaz gráfica y control de emergencia
Versión COMPACTA: Optimizada para pantallas pequeñas
"""

import serial
import tkinter as tk
from tkinter import ttk
import threading
import queue
import time
from datetime import datetime
import sys

# Diccionario de estados
ESTADOS = {
    '0': 'INICIO',
    '1': 'EVALUACION',
    '2': 'NORTE_SUR_VERDE',
    '3': 'NORTE_SUR_AMARILLO',
    '4': 'TODO_ROJO_1',
    '5': 'ESTE_OESTE_VERDE',
    '6': 'ESTE_OESTE_AMARILLO',
    '7': 'TODO_ROJO_2'
}

class SemaforoGUI:
    def __init__(self, master):
        self.master = master
        self.master.title("Semáforo Inteligente - MEJORADO (Límite 15 + Justicia)")
        self.master.geometry("900x650")  # Tamaño más pequeño
        self.master.configure(bg='#f0f0f0')
        
        # Cola para comunicación entre threads
        self.data_queue = queue.Queue()
        
        # Variables de estado
        self.estado_actual = '0'
        self.tiempo_restante = 0
        self.trafico_norte = 0
        self.trafico_sur = 0
        self.trafico_este = 0
        self.trafico_oeste = 0
        self.emergencia_activa = False
        
        # Variables para estadísticas
        self.vehiculos_procesados = 0
        self.cambios_por_justicia = 0
        
        # Serial connection
        self.ser = None
        
        # Crear interfaz
        self.crear_interfaz()
        
        # Iniciar thread serial
        self.serial_thread = None
        self.running = True
        
    def crear_interfaz(self):
        # Frame principal
        main_frame = tk.Frame(self.master, bg='#f0f0f0')
        main_frame.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        
        # Título compacto
        titulo = tk.Label(main_frame, text="🚦 Semáforo Inteligente MEJORADO", 
                         font=('Arial', 13, 'bold'), bg='#f0f0f0', fg='darkgreen')
        titulo.pack()
        
        # Subtítulo compacto
        subtitulo = tk.Label(main_frame, text="Límite 15 vehículos + Lógica de Justicia (8 veh máx)", 
                           font=('Arial', 9), bg='#f0f0f0', fg='darkblue')
        subtitulo.pack()
        
        # Frame superior: Estado + Conexión en una fila
        top_frame = tk.Frame(main_frame, bg='#f0f0f0')
        top_frame.pack(fill=tk.X, pady=3)
        
        # Estado e información (lado izquierdo)
        estado_frame = tk.Frame(top_frame, bg='#f0f0f0')
        estado_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.estado_label = tk.Label(estado_frame, text="Estado: INICIO", 
                                    font=('Arial', 11, 'bold'), bg='#f0f0f0', fg='blue')
        self.estado_label.pack(side=tk.LEFT)
        
        self.tiempo_label = tk.Label(estado_frame, text="Tiempo: 00s", 
                                    font=('Arial', 11, 'bold'), bg='#f0f0f0', fg='red')
        self.tiempo_label.pack(side=tk.LEFT, padx=10)
        
        # Indicador de emergencia
        self.emergencia_label = tk.Label(estado_frame, text="🚨 EMERGENCIA", 
                                       font=('Arial', 11, 'bold'), bg='#f0f0f0', fg='red')
        
        # Controles de conexión (lado derecho)
        conexion_frame = tk.Frame(top_frame, bg='#f0f0f0')
        conexion_frame.pack(side=tk.RIGHT)
        
        tk.Label(conexion_frame, text="Puerto:", bg='#f0f0f0', font=('Arial', 9)).pack(side=tk.LEFT, padx=2)
        self.puerto_var = tk.StringVar(value="COM6")
        self.puerto_entry = tk.Entry(conexion_frame, textvariable=self.puerto_var, width=8, font=('Arial', 9))
        self.puerto_entry.pack(side=tk.LEFT, padx=2)
        
        self.btn_conectar = tk.Button(conexion_frame, text="Conectar", 
                                     command=self.toggle_conexion, bg='#4CAF50', fg='white', font=('Arial', 9))
        self.btn_conectar.pack(side=tk.LEFT, padx=3)
        
        self.conexion_label = tk.Label(conexion_frame, text="Desconectado", 
                                      bg='#f0f0f0', fg='red', font=('Arial', 9))
        self.conexion_label.pack(side=tk.LEFT, padx=3)
        
        # Botón de emergencia
        self.btn_emergencia = tk.Button(conexion_frame, text="🚨 EMERGENCIA", 
                                       command=self.enviar_emergencia, bg='#ff4444', fg='white',
                                       font=('Arial', 9, 'bold'))
        self.btn_emergencia.pack(side=tk.LEFT, padx=3)
        
        # Frame de tráfico compacto
        trafico_frame = tk.LabelFrame(main_frame, text="Tráfico (Límite: 15 c/u)", 
                                     font=('Arial', 10, 'bold'), bg='#f0f0f0')
        trafico_frame.pack(fill=tk.X, pady=3)
        
        # Grid compacto para tráfico
        trafico_grid = tk.Frame(trafico_frame, bg='#f0f0f0')
        trafico_grid.pack(pady=2)
        
        # Fila 1: Norte y Sur
        tk.Label(trafico_grid, text="N:", font=('Arial', 10, 'bold'), bg='#f0f0f0').grid(row=0, column=0, padx=3)
        self.trafico_norte_label = tk.Label(trafico_grid, text="0", font=('Arial', 10), 
                                           bg='white', relief=tk.SUNKEN, width=3)
        self.trafico_norte_label.grid(row=0, column=1, padx=2)
        self.norte_progress = ttk.Progressbar(trafico_grid, length=80, maximum=15)
        self.norte_progress.grid(row=0, column=2, padx=3)
        
        tk.Label(trafico_grid, text="S:", font=('Arial', 10, 'bold'), bg='#f0f0f0').grid(row=0, column=3, padx=3)
        self.trafico_sur_label = tk.Label(trafico_grid, text="0", font=('Arial', 10), 
                                         bg='white', relief=tk.SUNKEN, width=3)
        self.trafico_sur_label.grid(row=0, column=4, padx=2)
        self.sur_progress = ttk.Progressbar(trafico_grid, length=80, maximum=15)
        self.sur_progress.grid(row=0, column=5, padx=3)
        
        # Fila 2: Este y Oeste
        tk.Label(trafico_grid, text="E:", font=('Arial', 10, 'bold'), bg='#f0f0f0').grid(row=1, column=0, padx=3)
        self.trafico_este_label = tk.Label(trafico_grid, text="0", font=('Arial', 10), 
                                          bg='white', relief=tk.SUNKEN, width=3)
        self.trafico_este_label.grid(row=1, column=1, padx=2)
        self.este_progress = ttk.Progressbar(trafico_grid, length=80, maximum=15)
        self.este_progress.grid(row=1, column=2, padx=3)
        
        tk.Label(trafico_grid, text="O:", font=('Arial', 10, 'bold'), bg='#f0f0f0').grid(row=1, column=3, padx=3)
        self.trafico_oeste_label = tk.Label(trafico_grid, text="0", font=('Arial', 10), 
                                           bg='white', relief=tk.SUNKEN, width=3)
        self.trafico_oeste_label.grid(row=1, column=4, padx=2)
        self.oeste_progress = ttk.Progressbar(trafico_grid, length=80, maximum=15)
        self.oeste_progress.grid(row=1, column=5, padx=3)
        
        # Frame para canvas más pequeño
        canvas_frame = tk.Frame(main_frame, bg='white', relief=tk.RAISED, borderwidth=1)
        canvas_frame.pack(fill=tk.BOTH, expand=True, pady=3)
        
        # Canvas más pequeño
        self.canvas = tk.Canvas(canvas_frame, bg='#e8e8e8', width=700, height=350)
        self.canvas.pack(fill=tk.BOTH, expand=True, padx=3, pady=3)
        
        # Dibujar intersección
        self.dibujar_interseccion()
        
        # Frame inferior compacto para estadísticas e instrucciones
        bottom_frame = tk.Frame(main_frame, bg='#f0f0f0')
        bottom_frame.pack(fill=tk.X, pady=2)
        
        # Estadísticas compactas
        stats_frame = tk.Frame(bottom_frame, bg='#f0f0f0')
        stats_frame.pack(side=tk.LEFT)
        
        tk.Label(stats_frame, text="Veh:", font=('Arial', 9), bg='#f0f0f0').pack(side=tk.LEFT)
        self.vehiculos_label = tk.Label(stats_frame, text="0", font=('Arial', 9, 'bold'), 
                                       bg='white', relief=tk.SUNKEN, width=4)
        self.vehiculos_label.pack(side=tk.LEFT, padx=2)
        
        tk.Label(stats_frame, text="Just:", font=('Arial', 9), bg='#f0f0f0').pack(side=tk.LEFT, padx=(10,0))
        self.justicia_label = tk.Label(stats_frame, text="0", font=('Arial', 9, 'bold'), 
                                      bg='white', relief=tk.SUNKEN, width=4)
        self.justicia_label.pack(side=tk.LEFT, padx=2)
        
        # Estadísticas de mensajes
        self.stats_label = tk.Label(bottom_frame, text="Mensajes: 0", 
                                   bg='#f0f0f0', font=('Arial', 9))
        self.stats_label.pack(side=tk.RIGHT)
        
        # Instrucciones en la parte inferior
        self.instrucciones_label = tk.Label(main_frame, 
                                           text="INICIO: SW[15-12] agregar vehículos (N,O,S,E) máx 15 c/u, SW[11] iniciar", 
                                           font=('Arial', 9), bg='#f0f0f0', fg='green', wraplength=850)
        self.instrucciones_label.pack(pady=2)
        
    def enviar_emergencia(self):
        """Envía comando de emergencia por UART"""
        if self.ser and self.ser.is_open:
            try:
                self.ser.write(b'E')
                self.btn_emergencia.config(text="Enviado!", bg='#ff6666')
                self.master.after(2000, lambda: self.btn_emergencia.config(text="🚨 EMERGENCIA", bg='#ff4444'))
            except:
                pass
        
    def dibujar_interseccion(self):
        # Limpiar canvas
        self.canvas.delete("all")
        
        # Dimensiones más pequeñas
        width = 700
        height = 350
        centro_x = width // 2
        centro_y = height // 2
        ancho_calle = 60
        
        # Color de fondo (césped)
        self.canvas.create_rectangle(0, 0, width, height, fill='#90EE90', outline='')
        
        # Dibujar calles
        self.canvas.create_rectangle(0, centro_y - ancho_calle//2, 
                                    width, centro_y + ancho_calle//2, 
                                    fill='#808080', outline='')
        
        self.canvas.create_rectangle(centro_x - ancho_calle//2, 0, 
                                    centro_x + ancho_calle//2, height, 
                                    fill='#808080', outline='')
        
        # Líneas divisorias
        self.canvas.create_line(0, centro_y, width, centro_y, 
                               fill='yellow', width=2, dash=(8, 4))
        self.canvas.create_line(centro_x, 0, centro_x, height, 
                               fill='yellow', width=2, dash=(8, 4))
        
        # Puntos cardinales con contadores
        offset_texto = 80
        
        # Norte
        self.canvas.create_text(centro_x, centro_y - offset_texto, text="N", 
                               font=('Arial', 14, 'bold'), fill='black')
        self.trafico_norte_canvas = self.canvas.create_text(centro_x, centro_y - offset_texto + 20, 
                                                           text="0/15", font=('Arial', 10, 'bold'), 
                                                           fill='blue')
        
        # Sur
        self.canvas.create_text(centro_x, centro_y + offset_texto, text="S", 
                               font=('Arial', 14, 'bold'), fill='black')
        self.trafico_sur_canvas = self.canvas.create_text(centro_x, centro_y + offset_texto - 20, 
                                                         text="0/15", font=('Arial', 10, 'bold'), 
                                                         fill='blue')
        
        # Oeste
        self.canvas.create_text(centro_x - offset_texto, centro_y, text="O", 
                               font=('Arial', 14, 'bold'), fill='black')
        self.trafico_oeste_canvas = self.canvas.create_text(centro_x - offset_texto, centro_y + 20, 
                                                           text="0/15", font=('Arial', 10, 'bold'), 
                                                           fill='blue')
        
        # Este
        self.canvas.create_text(centro_x + offset_texto, centro_y, text="E", 
                               font=('Arial', 14, 'bold'), fill='black')
        self.trafico_este_canvas = self.canvas.create_text(centro_x + offset_texto, centro_y + 20, 
                                                          text="0/15", font=('Arial', 10, 'bold'), 
                                                          fill='blue')
        
        # Dibujar semáforos
        self.dibujar_semaforos()
        
        # Monitor compacto
        self.dibujar_monitor_estado()
        
    def dibujar_semaforos(self):
        # Posiciones más compactas
        centro_x = 350
        centro_y = 175
        offset = 65
        
        # Semáforos Norte-Sur
        self.semaforos_ns = {
            'norte': {'x': centro_x - 25, 'y': centro_y - offset},
            'sur': {'x': centro_x + 25, 'y': centro_y + offset}
        }
        
        # Semáforos Este-Oeste
        self.semaforos_eo = {
            'oeste': {'x': centro_x - offset-35, 'y': centro_y + 25},
            'este': {'x': centro_x + offset+35, 'y': centro_y - 25}
        }
        
        # Dibujar semáforos
        self.luces_ns = {}
        self.luces_eo = {}
        
        for nombre, pos in self.semaforos_ns.items():
            self.luces_ns[nombre] = self.dibujar_semaforo_individual(pos['x'], pos['y'])
            
        for nombre, pos in self.semaforos_eo.items():
            self.luces_eo[nombre] = self.dibujar_semaforo_individual(pos['x'], pos['y'])
    
    def dibujar_semaforo_individual(self, x, y):
        # Semáforo más pequeño
        self.canvas.create_rectangle(x-10, y-25, x+10, y+25, fill='black', outline='')
        
        luces = {
            'rojo': self.canvas.create_oval(x-7, y-20, x+7, y-6, 
                                          fill='#400000', outline='black'),
            'amarillo': self.canvas.create_oval(x-7, y-5, x+7, y+9, 
                                              fill='#404000', outline='black'),
            'verde': self.canvas.create_oval(x-7, y+10, x+7, y+24, 
                                           fill='#004000', outline='black')
        }
        return luces
    
    def dibujar_monitor_estado(self):
        # Monitor más pequeño
        mon_x = 500
        mon_y = 250
        mon_width = 180
        mon_height = 90
        
        # Fondo del monitor
        self.canvas.create_rectangle(mon_x, mon_y, mon_x + mon_width, mon_y + mon_height,
                                   fill='#2b2b2b', outline='gray', width=1)
        
        # Título del monitor
        self.canvas.create_text(mon_x + mon_width//2, mon_y + 12, 
                               text="Estado del Sistema", font=('Arial', 10, 'bold'), 
                               fill='white')
        
        # Estado actual
        self.estado_monitor = self.canvas.create_text(mon_x + mon_width//2, mon_y + 30, 
                                                     text="INICIO", font=('Arial', 9, 'bold'), 
                                                     fill='yellow')
        
        # Tiempo restante
        self.tiempo_monitor = self.canvas.create_text(mon_x + mon_width//2, mon_y + 45, 
                                                     text="Tiempo: 00s", font=('Arial', 9), 
                                                     fill='white')
        
        # Indicador de justicia
        self.justicia_monitor = self.canvas.create_text(mon_x + mon_width//2, mon_y + 60, 
                                                       text="Justicia: OK", font=('Arial', 8), 
                                                       fill='lightgreen')
        
        # Semáforos en miniatura más pequeños
        # Norte-Sur
        self.canvas.create_text(mon_x + 30, mon_y + 75, text="N-S", 
                               font=('Arial', 8), fill='white')
        self.mon_ns_rojo = self.canvas.create_oval(mon_x + 20, mon_y + 80, 
                                                  mon_x + 28, mon_y + 88, 
                                                  fill='#400000', outline='white')
        self.mon_ns_amarillo = self.canvas.create_oval(mon_x + 30, mon_y + 80, 
                                                       mon_x + 38, mon_y + 88, 
                                                       fill='#404000', outline='white')
        self.mon_ns_verde = self.canvas.create_oval(mon_x + 40, mon_y + 80, 
                                                   mon_x + 48, mon_y + 88, 
                                                   fill='#004000', outline='white')
        
        # Este-Oeste
        self.canvas.create_text(mon_x + 150, mon_y + 75, text="E-O", 
                               font=('Arial', 8), fill='white')
        self.mon_eo_rojo = self.canvas.create_oval(mon_x + 135, mon_y + 80, 
                                                  mon_x + 143, mon_y + 88, 
                                                  fill='#400000', outline='white')
        self.mon_eo_amarillo = self.canvas.create_oval(mon_x + 145, mon_y + 80, 
                                                       mon_x + 153, mon_y + 88, 
                                                       fill='#404000', outline='white')
        self.mon_eo_verde = self.canvas.create_oval(mon_x + 155, mon_y + 80, 
                                                   mon_x + 163, mon_y + 88, 
                                                   fill='#004000', outline='white')
    
    def actualizar_semaforos(self, estado):
        # Misma lógica pero más compacta
        off_red = '#400000'
        off_yellow = '#404000'
        off_green = '#004000'
        on_red = '#ff0000'
        on_yellow = '#ffff00'
        on_green = '#00ff00'
        
        if self.emergencia_activa:
            # Todo rojo durante emergencia
            for nombre, luces in {**self.luces_ns, **self.luces_eo}.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            # Monitor
            for led in [self.mon_ns_rojo, self.mon_eo_rojo]:
                self.canvas.itemconfig(led, fill=on_red)
            for led in [self.mon_ns_amarillo, self.mon_ns_verde, self.mon_eo_amarillo, self.mon_eo_verde]:
                self.canvas.itemconfig(led, fill=off_yellow if 'amarillo' in str(led) else off_green)
            return
        
        # Estados normales
        if estado == '2':  # Norte-Sur Verde
            for nombre, luces in self.luces_ns.items():
                self.canvas.itemconfig(luces['rojo'], fill=off_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=on_green)
            for nombre, luces in self.luces_eo.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            # Monitor
            self.canvas.itemconfig(self.mon_ns_rojo, fill=off_red)
            self.canvas.itemconfig(self.mon_ns_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_ns_verde, fill=on_green)
            self.canvas.itemconfig(self.mon_eo_rojo, fill=on_red)
            self.canvas.itemconfig(self.mon_eo_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_eo_verde, fill=off_green)
            
        elif estado == '3':  # Norte-Sur Amarillo
            for nombre, luces in self.luces_ns.items():
                self.canvas.itemconfig(luces['rojo'], fill=off_red)
                self.canvas.itemconfig(luces['amarillo'], fill=on_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            for nombre, luces in self.luces_eo.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            # Monitor
            self.canvas.itemconfig(self.mon_ns_rojo, fill=off_red)
            self.canvas.itemconfig(self.mon_ns_amarillo, fill=on_yellow)
            self.canvas.itemconfig(self.mon_ns_verde, fill=off_green)
            self.canvas.itemconfig(self.mon_eo_rojo, fill=on_red)
            self.canvas.itemconfig(self.mon_eo_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_eo_verde, fill=off_green)
            
        elif estado == '5':  # Este-Oeste Verde
            for nombre, luces in self.luces_ns.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            for nombre, luces in self.luces_eo.items():
                self.canvas.itemconfig(luces['rojo'], fill=off_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=on_green)
            # Monitor
            self.canvas.itemconfig(self.mon_ns_rojo, fill=on_red)
            self.canvas.itemconfig(self.mon_ns_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_ns_verde, fill=off_green)
            self.canvas.itemconfig(self.mon_eo_rojo, fill=off_red)
            self.canvas.itemconfig(self.mon_eo_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_eo_verde, fill=on_green)
            
        elif estado == '6':  # Este-Oeste Amarillo
            for nombre, luces in self.luces_ns.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            for nombre, luces in self.luces_eo.items():
                self.canvas.itemconfig(luces['rojo'], fill=off_red)
                self.canvas.itemconfig(luces['amarillo'], fill=on_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            # Monitor
            self.canvas.itemconfig(self.mon_ns_rojo, fill=on_red)
            self.canvas.itemconfig(self.mon_ns_amarillo, fill=off_yellow)
            self.canvas.itemconfig(self.mon_ns_verde, fill=off_green)
            self.canvas.itemconfig(self.mon_eo_rojo, fill=off_red)
            self.canvas.itemconfig(self.mon_eo_amarillo, fill=on_yellow)
            self.canvas.itemconfig(self.mon_eo_verde, fill=off_green)
            
        else:  # Todo rojo
            for nombre, luces in {**self.luces_ns, **self.luces_eo}.items():
                self.canvas.itemconfig(luces['rojo'], fill=on_red)
                self.canvas.itemconfig(luces['amarillo'], fill=off_yellow)
                self.canvas.itemconfig(luces['verde'], fill=off_green)
            # Monitor
            for led in [self.mon_ns_rojo, self.mon_eo_rojo]:
                self.canvas.itemconfig(led, fill=on_red)
            for led in [self.mon_ns_amarillo, self.mon_ns_verde, self.mon_eo_amarillo, self.mon_eo_verde]:
                self.canvas.itemconfig(led, fill=off_yellow if 'amarillo' in str(led) else off_green)
    
    def actualizar_trafico(self):
        # Actualizar canvas
        self.canvas.itemconfig(self.trafico_norte_canvas, text=f"{self.trafico_norte}/15")
        self.canvas.itemconfig(self.trafico_sur_canvas, text=f"{self.trafico_sur}/15")
        self.canvas.itemconfig(self.trafico_este_canvas, text=f"{self.trafico_este}/15")
        self.canvas.itemconfig(self.trafico_oeste_canvas, text=f"{self.trafico_oeste}/15")
        
        # Actualizar labels
        self.trafico_norte_label.config(text=str(self.trafico_norte))
        self.trafico_sur_label.config(text=str(self.trafico_sur))
        self.trafico_este_label.config(text=str(self.trafico_este))
        self.trafico_oeste_label.config(text=str(self.trafico_oeste))
        
        # Actualizar barras de progreso con colores
        for progress, valor in [(self.norte_progress, self.trafico_norte),
                               (self.sur_progress, self.trafico_sur),
                               (self.este_progress, self.trafico_este),
                               (self.oeste_progress, self.trafico_oeste)]:
            progress['value'] = valor
            if valor >= 15:
                progress.configure(style='red.Horizontal.TProgressbar')
            elif valor >= 12:
                progress.configure(style='yellow.Horizontal.TProgressbar')
            else:
                progress.configure(style='green.Horizontal.TProgressbar')
    
    def toggle_conexion(self):
        if self.serial_thread is None or not self.serial_thread.is_alive():
            self.iniciar_conexion()
        else:
            self.detener_conexion()
    
    def iniciar_conexion(self):
        puerto = self.puerto_var.get()
        self.serial_thread = threading.Thread(target=self.leer_serial, args=(puerto,))
        self.serial_thread.daemon = True
        self.running = True
        self.serial_thread.start()
        
        self.btn_conectar.config(text="Desconectar", bg='#f44336')
        self.conexion_label.config(text="Conectando...", fg='orange')
    
    def detener_conexion(self):
        self.running = False
        if self.serial_thread:
            self.serial_thread.join(timeout=1)
        
        if self.ser and self.ser.is_open:
            self.ser.close()
            self.ser = None
        
        self.btn_conectar.config(text="Conectar", bg='#4CAF50')
        self.conexion_label.config(text="Desconectado", fg='red')
    
    def leer_serial(self, puerto):
        try:
            self.ser = serial.Serial(puerto, 115200, timeout=0.1)
            self.master.after(0, lambda: self.conexion_label.config(text="Conectado", fg='green'))
            
            buffer = b''
            message_count = 0
            error_count = 0
            
            while self.running:
                if self.ser.in_waiting > 0:
                    chunk = self.ser.read(self.ser.in_waiting)
                    buffer += chunk
                    
                    while b'\n' in buffer:
                        line, buffer = buffer.split(b'\n', 1)
                        parsed = self.parse_message(line)
                        
                        if parsed:
                            message_count += 1
                            parsed['message_count'] = message_count
                            parsed['error_count'] = error_count
                            self.data_queue.put(parsed)
                        else:
                            error_count += 1
                
                time.sleep(0.05)
            
            self.ser.close()
            
        except serial.SerialException as e:
            self.master.after(0, lambda: self.conexion_label.config(
                text=f"Error: {str(e)}", fg='red'))
        except Exception as e:
            self.master.after(0, lambda: self.conexion_label.config(
                text=f"Error: {str(e)}", fg='red'))
    
    def parse_message(self, data):
        try:
            message = data.decode('ascii').strip()
            
            # Formato: ST:X,T:YY,N:ZZ,S:ZZ,E:ZZ,O:ZZ,EM:X
            if not message.startswith('ST:'):
                return None
            
            parts = message.split(',')
            if len(parts) < 6:
                return None
            
            estado = parts[0].split(':')[1]
            tiempo = parts[1].split(':')[1]
            trafico_norte = parts[2].split(':')[1]
            trafico_sur = parts[3].split(':')[1]
            trafico_este = parts[4].split(':')[1]
            trafico_oeste = parts[5].split(':')[1]
            
            # Verificar emergencia
            emergencia = False
            if len(parts) >= 7 and 'EM:' in parts[6]:
                emergencia = parts[6].split(':')[1] == '1'
            
            return {
                'estado': estado,
                'estado_nombre': ESTADOS.get(estado, 'DESCONOCIDO'),
                'tiempo': int(tiempo),
                'trafico_norte': int(trafico_norte),
                'trafico_sur': int(trafico_sur),
                'trafico_este': int(trafico_este),
                'trafico_oeste': int(trafico_oeste),
                'emergencia': emergencia,
                'timestamp': datetime.now().strftime('%H:%M:%S')
            }
        except:
            return None
    
    def procesar_datos(self):
        try:
            while not self.data_queue.empty():
                data = self.data_queue.get_nowait()
                
                # Detectar vehículos procesados
                trafico_anterior = self.trafico_norte + self.trafico_sur + self.trafico_este + self.trafico_oeste
                trafico_actual = data['trafico_norte'] + data['trafico_sur'] + data['trafico_este'] + data['trafico_oeste']
                
                if trafico_anterior > trafico_actual:
                    self.vehiculos_procesados += (trafico_anterior - trafico_actual)
                
                # Actualizar estado
                self.estado_actual = data['estado']
                self.tiempo_restante = data['tiempo']
                self.trafico_norte = data['trafico_norte']
                self.trafico_sur = data['trafico_sur']
                self.trafico_este = data['trafico_este']
                self.trafico_oeste = data['trafico_oeste']
                self.emergencia_activa = data.get('emergencia', False)
                
                # Actualizar interfaz
                if self.emergencia_activa:
                    self.estado_label.config(text="Estado: EMERGENCIA", fg='red')
                    self.emergencia_label.pack(side=tk.LEFT, padx=5)
                    self.canvas.itemconfig(self.justicia_monitor, text="Emergencia", fill='red')
                else:
                    self.estado_label.config(text=f"Estado: {data['estado_nombre']}", fg='blue')
                    self.emergencia_label.pack_forget()
                    
                    # Verificar condición de justicia
                    if ((self.estado_actual == '2' and (self.trafico_este > 0 or self.trafico_oeste > 0)) or 
                        (self.estado_actual == '5' and (self.trafico_norte > 0 or self.trafico_sur > 0))):
                        self.canvas.itemconfig(self.justicia_monitor, text="Esperando...", fill='orange')
                    else:
                        self.canvas.itemconfig(self.justicia_monitor, text="Justicia: OK", fill='lightgreen')
                
                self.tiempo_label.config(text=f"Tiempo: {data['tiempo']:02d}s")
                self.stats_label.config(text=f"Msg: {data['message_count']} | Err: {data['error_count']}")
                
                # Actualizar estadísticas
                self.vehiculos_label.config(text=str(self.vehiculos_procesados))
                self.justicia_label.config(text=str(self.cambios_por_justicia))
                
                # Actualizar monitor del canvas
                if self.emergencia_activa:
                    self.canvas.itemconfig(self.estado_monitor, text="EMERGENCIA", fill='red')
                else:
                    self.canvas.itemconfig(self.estado_monitor, text=data['estado_nombre'], fill='yellow')
                
                self.canvas.itemconfig(self.tiempo_monitor, text=f"Tiempo: {data['tiempo']:02d}s")
                
                # Actualizar instrucciones (más compactas)
                if self.emergencia_activa:
                    self.instrucciones_label.config(
                        text="🚨 EMERGENCIA ACTIVA: Todos en rojo por 10 segundos",
                        fg='red')
                elif self.estado_actual == '0':
                    self.instrucciones_label.config(
                        text="INICIO: SW[15-12] agregar vehículos (N,O,S,E) máx 15 c/u, SW[11] iniciar",
                        fg='green')
                elif self.estado_actual == '1':
                    self.instrucciones_label.config(
                        text="EVALUACIÓN: Analizando tráfico...",
                        fg='orange')
                elif self.estado_actual in ['2', '5']:
                    direccion = "N-S" if self.estado_actual == '2' else "E-O"
                    self.instrucciones_label.config(
                        text=f"VERDE {direccion}: Procesando. Cambio automático tras 8 veh si hay tráfico esperando",
                        fg='green')
                else:
                    self.instrucciones_label.config(
                        text="Sistema operando con lógica de justicia mejorada",
                        fg='blue')
                
                # Actualizar visualización
                self.actualizar_semaforos(self.estado_actual)
                self.actualizar_trafico()
                
        except queue.Empty:
            pass
        
        # Programar próxima actualización
        self.master.after(50, self.procesar_datos)
    
    def cerrar(self):
        self.running = False
        if self.serial_thread and self.serial_thread.is_alive():
            self.serial_thread.join(timeout=1)
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.master.destroy()

def main():
    root = tk.Tk()
    
    # Configurar estilos para barras de progreso
    style = ttk.Style()
    style.theme_use('clam')
    style.configure('green.Horizontal.TProgressbar', background='green')
    style.configure('yellow.Horizontal.TProgressbar', background='orange')
    style.configure('red.Horizontal.TProgressbar', background='red')
    
    app = SemaforoGUI(root)
    
    # Iniciar procesamiento de datos
    app.procesar_datos()
    
    # Manejar cierre de ventana
    root.protocol("WM_DELETE_WINDOW", app.cerrar)
    
    # Hacer la ventana redimensionable
    root.resizable(True, True)
    root.minsize(800, 600)
    
    # Iniciar GUI
    root.mainloop()

if __name__ == "__main__":
    main()