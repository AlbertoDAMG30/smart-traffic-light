# Smart Traffic Light Controller (Intelligent Adaptive System)

![Verilog](https://img.shields.io/badge/HDL-Verilog-blue)
![Python](https://img.shields.io/badge/Python-3.x-yellow)
![FPGA](https://img.shields.io/badge/FPGA-Nexys_A7-green)
![UART](https://img.shields.io/badge/communication-UART-red)

## 📋 Description

An **intelligent adaptive traffic light controller** system implemented in Verilog for FPGA with real-time Python GUI monitoring via UART communication. The system uses queueing theory and adaptive control to optimize traffic flow at a 4-way intersection, featuring dynamic timing, fairness logic, and emergency vehicle priority.

**Final Project** (45%) for EL-3310 Digital Systems Design course at Costa Rica Institute of Technology (TEC).

## 🎯 Key Features

### Adaptive Traffic Control
- ✅ **8-State FSM** - Complete intersection control cycle
- ✅ **Dynamic timing** - Adjusts green light duration based on traffic density
- ✅ **Fairness logic** - Max 8 vehicles per cycle to prevent starvation
- ✅ **Queue limits** - Maximum 15 vehicles per direction
- ✅ **Early termination** - Switches when no traffic waiting
- ✅ **Emergency mode** - Priority handling for emergency vehicles

### Communication System
- 🔗 **UART protocol** - 115200 baud bidirectional communication
- 📡 **Real-time data** - Continuous state and traffic updates
- 💻 **Python GUI** - Tkinter-based graphical monitoring interface
- 🎨 **Visual intersection** - Animated traffic lights and vehicle counts
- 📊 **Statistics tracking** - Vehicles processed, state changes, timing

### Traffic Simulation
- 🚗 **4 directions** - North, South, East, West traffic flows
- 🎮 **Switch-based input** - Add vehicles via FPGA switches
- ⏱️ **Real-time queues** - Live traffic counter display
- 🚨 **Emergency button** - Trigger emergency vehicle mode
- 📈 **Queue monitoring** - Track all directions simultaneously

## 🛠️ Technologies Used

### Hardware
- **FPGA**: Nexys A7-100T (Artix-7)
- **HDL**: Verilog
- **IDE**: Xilinx Vivado Design Suite
- **Communication**: UART @ 115200 baud
- **I/O**: Switches, Buttons, LEDs

### Software
- **Language**: Python 3.x
- **GUI**: Tkinter, ttk
- **Serial**: PySerial library
- **Threading**: Multi-threaded for UART + GUI
- **Platform**: Windows/Linux compatible

## 📦 Requirements

### Hardware
- Nexys A7-100T FPGA board
- USB cable (programming + UART)
- Computer with serial port

### Software - FPGA
- Xilinx Vivado (2018.2+)
- Verilog synthesis tools

### Software - Monitor
```bash
# Python 3.x required
pip install pyserial
# Tkinter (usually included with Python)
```

## 🚀 Getting Started

### 1. Clone Repository
```bash
git clone https://github.com/AlbertoDAMG30/smart-traffic-light.git
cd smart-traffic-light
```

### 2. Program FPGA
```
Open in Vivado
Synthesize → Implement → Generate Bitstream
Program Device
```

### 3. Run Python Monitor
```bash
# Linux
python3 monitor_grafico_semaforo.py

# Windows
python monitor_grafico_semaforo.py
```

### 4. Connect and Test
```
1. Select COM port in GUI
2. Click "Conectar"
3. Use switches to add traffic
4. Watch adaptive behavior!
```

## 📂 Project Structure

```
smart-traffic-light/
├── FPGA (Verilog)
│   ├── semaforo_main.v           # Top-level module
│   ├── semaforo_fsm.v            # 8-state FSM controller
│   ├── divisor_reloj_semaforo.v  # Clock divider
│   ├── uart_module.v             # UART communication
│   └── Nexys-A7-100T-Master.xdc  # Constraints file
├── Monitor (Python)
│   └── monitor_grafico_semaforo.py  # GUI monitor (~725 lines)
├── Documentation
│   └── Proyectos_Lab4_IS2025.pdf    # Specifications
└── README.md                         # This file
```

## 🎮 How to Use

### FPGA Controls

| Input | Function |
|-------|----------|
| **SW[15-12]** | Add vehicles (N, W, S, E) - Max 15 each |
| **SW[11]** | Start system from INICIO state |
| **SW[0-3]** | Add vehicles to E, W, S, N during operation |
| **BTNC** | Reset system |
| **BTN Emergency** | Trigger emergency mode (10s all red) |
| **LED[7-5]** | North-South lights (R, Y, G) |
| **LED[2-0]** | East-West lights (R, Y, G) |
| **LED RGB** | Emergency indicator |

### Python GUI Features

**Main Display:**
- Intersection visualization with 4 directions
- Traffic light states (color-coded)
- Vehicle counters for each direction
- Real-time state display
- Timer countdown

**Control Panel:**
- Serial port selection
- Connect/Disconnect button
- Emergency trigger button
- Connection status indicator

**Statistics:**
- Total vehicles processed
- Fairness logic activations
- Message counters
- Error tracking

## 🔄 State Machine (FSM)

### 8 States

```
┌────────┐
│ INICIO │ (Initial State - System startup)
└────┬───┘
     │
     ▼
┌────────────┐
│ EVALUACION │ (Evaluate traffic, decide direction)
└──────┬─────┘
       │
   ┌───┴────────┐
   │            │
   ▼            ▼
┌──────────┐  ┌───────────┐
│ N-S      │  │ E-W       │
│ VERDE    │  │ VERDE     │
└────┬─────┘  └────┬──────┘
     │             │
     ▼             ▼
┌──────────┐  ┌───────────┐
│ N-S      │  │ E-W       │
│ AMARILLO │  │ AMARILLO  │
└────┬─────┘  └────┬──────┘
     │             │
     ▼             ▼
┌────────────┐  ┌────────────┐
│ TODO_ROJO_1│  │ TODO_ROJO_2│
└─────┬──────┘  └─────┬──────┘
      │               │
      └───────┬───────┘
              │
         (Loop back)
```

### State Descriptions

**0: INICIO** - System initialization, all lights red

**1: EVALUACION** - Analyze traffic queues, select direction with most vehicles

**2: NORTE_SUR_VERDE** - North-South green light
- Duration: 15-45s (dynamic based on traffic)
- Processes vehicles from North and South
- Monitors for fairness (max 8 vehicles) or empty queue

**3: NORTE_SUR_AMARILLO** - North-South yellow (3s transition)

**4: TODO_ROJO_1** - All red safety period (2s)

**5: ESTE_OESTE_VERDE** - East-West green light
- Same logic as North-South
- Dynamic timing and fairness

**6: ESTE_OESTE_AMARILLO** - East-West yellow (3s)

**7: TODO_ROJO_2** - All red safety period (2s)

### Emergency State
- **Trigger**: Emergency button press or UART command
- **Effect**: Immediate all-red for 10 seconds
- **Resume**: Returns to previous state after emergency

## 🧠 Adaptive Logic

### Dynamic Green Light Timing

```verilog
if (traffic <= 2)       time = 15s  // Minimum
else if (traffic >= 8)  time = 45s  // Maximum
else                    time = 15 + (traffic × 3)s
```

### Fairness Algorithm

**Problem**: One direction with continuous heavy traffic blocks other direction indefinitely.

**Solution**: "Justicia" (fairness) logic
- Counts vehicles processed per green cycle
- After 8 vehicles, checks if other direction has waiting traffic
- If yes, forces state change to give other direction a turn
- Prevents starvation of low-traffic directions

### Early Termination

**Scenario 1**: Current direction empty + other has traffic
- Wait 4 seconds grace period
- If still empty, switch early (after min 8s)

**Scenario 2**: Current direction empty + no traffic anywhere
- Still wait min 8s then switch

## 📡 UART Communication

### Protocol Specification

**Baud Rate**: 115200
**Data Format**: 8N1 (8 bits, no parity, 1 stop)
**Direction**: Bidirectional

### FPGA → PC (Status Messages)

Format: `ST:X,T:YY,N:ZZ,S:ZZ,E:ZZ,O:ZZ,EM:X\n`

```
ST:2,T:27,N:08,S:03,E:00,O:02,EM:0
│   │    │    │    │    │    └─ Emergency active (0/1)
│   │    │    │    │    └────── West traffic count
│   │    │    │    └─────────── East traffic count  
│   │    │    └──────────────── South traffic count
│   │    └───────────────────── North traffic count
│   └────────────────────────── Time remaining
└────────────────────────────── State (0-7)
```

**Frequency**: ~1 Hz (every second)

### PC → FPGA (Emergency Command)

Format: Single character `E` or `e`

**Trigger**: Emergency button in Python GUI
**Effect**: Sets emergency flag, transitions to all-red

## 🎨 Python GUI Details

### Main Window Features

**Intersection Display** (Canvas):
- 4-way intersection with roads
- Traffic lights with actual colors (red/yellow/green)
- Vehicle counters for each direction (0-15)
- Cardinal direction labels (N, S, E, W)
- Miniature status monitor

**Traffic Indicators** (Progress Bars):
- Color-coded (green→yellow→red as queue fills)
- Shows 0-15 range
- Updates in real-time

**Status Panel**:
- Current state name
- Time remaining countdown
- Emergency indicator (appears when active)
- Fairness status

**Control Panel**:
- COM port dropdown/entry
- Connect/Disconnect button
- Emergency trigger button
- Connection status (color-coded)

### Threading Model

**Main Thread**: GUI rendering (Tkinter)
**Serial Thread**: UART communication
**Queue**: Thread-safe data passing

## 📊 Technical Specifications

### Timing Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Green Min | 15s | Minimum green duration |
| Green Max | 45s | Maximum green duration |
| Yellow | 3s | Warning transition |
| All Red | 2s | Safety clearance |
| Evaluation | 3s | Decision time |
| Emergency | 10s | Emergency vehicle priority |

### Traffic Limits

| Limit | Value | Reason |
|-------|-------|--------|
| Max Queue | 15 | Realistic constraint |
| Fairness Threshold | 8 | Prevent starvation |
| Grace Period | 4s | Avoid rapid switching |
| Min Green Absolute | 8s | Safety minimum |

### Communication

| Parameter | Value |
|-----------|-------|
| Baud Rate | 115200 |
| Clock (FPGA) | 100 MHz |
| Update Rate | 1 Hz |
| Buffer Size | 1024 bytes |

## 🐛 Troubleshooting

### FPGA Issues

**No lights change:**
- Press SW[11] to start
- Check FPGA programmed
- Verify clock divider

**Lights don't match traffic:**
- Check state machine logic
- Verify UART output
- Reset with BTNC

**Emergency doesn't work:**
- Verify UART command received
- Check emergency state logic
- Try physical button

### Python GUI Issues

**Can't connect:**
```bash
# Linux: Check port permissions
sudo chmod 666 /dev/ttyUSB0

# Windows: Verify COM port in Device Manager
# Install PySerial if missing
pip install pyserial
```

**No data received:**
- Verify FPGA UART TX connected
- Check baud rate (115200)
- Restart both FPGA and monitor

**GUI freezes:**
- Threading issue - restart Python
- Check serial buffer not full
- Verify no infinite loops

## 🏆 Project Requirements Compliance

### Mandatory Features ✅
- ✅ Intersection simulation (4-way)
- ✅ Complex state machine (8 states)
- ✅ Traffic simulation (queueing theory)
- ✅ Adaptive control (dynamic timing)
- ✅ Fairness consideration (justice logic)
- ✅ FPGA-PC communication (UART)
- ✅ Real-time monitoring GUI
- ✅ Emergency vehicle priority
- ✅ LED traffic lights
- ✅ Queue size display

### Objectives Achieved ✅
1. ✅ Real-time traffic control design
2. ✅ Complex state machine application
3. ✅ Queueing theory implementation
4. ✅ Real-world system simulation
5. ✅ Optimization + fairness balance
6. ✅ Inter-device communication

## 👨‍💻 Author

**David Alberto Miranda Gonzalez**
- Student ID: 2020207762
- Institution: Costa Rica Institute of Technology (TEC)
- Professor: Javier Rivera Alvarado
- Semester: I-2025

## 📄 License

Educational project for Digital Systems Design course.

## 🙏 Acknowledgments

- Digilent for Nexys A7 resources
- Xilinx for Vivado tools
- TEC Digital Systems Lab

## 📚 References

- Queueing Theory in Traffic Engineering
- Adaptive Traffic Control Systems
- UART Protocol Specification
- Nexys A7 Reference Manual
- Verilog HDL Guide

⭐ **Final Project** - Most complex system combining FPGA hardware control with PC software monitoring!
**Note**: This project demonstrates advanced concepts: adaptive algorithms, fairness in resource allocation, real-time communication, and hybrid hardware-software system design.
