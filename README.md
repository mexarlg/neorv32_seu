# SEU-Resilient NEORV32 RISC-V Core (Student Research Project)

This is a student research project at **ISAE SUPAERO** focused on improving the fault tolerance of a RISC-V soft-core processor by implementing **Single Event Upset (SEU) mitigation techniques**. The base processor used in this work is the **NEORV32 RISC-V CPU**, which is being extended and modified at the RTL level to study and demonstrate hardware level reliability improvements.

The main objective of this project is to investigate and implement architectural and circuit-level mitigation techniques against SEUs, including:

- Redundancy based techniques (reinforced TMR)
- Error detection and correction mechanisms for memory and caches (EDAC)
- Parity bits on registers
- DLD protection on control logic
- Fault detection strategies (Watch-dog)

## 1. What you Need — Hardware

| Item | Purpose |
|---|---|
| Digilent Zybo Z7-20 board | The FPGA development board |
| USB Micro-B cable | Programs the FPGA bitstream and powers the board |
| 3.3V USB-to-TTL serial adapter | Communicates with the NEORV32 bootloader over UART |
| JTAG debug probe (optional) | For on-chip GDB debugging |


## 2. What You Need — Software

| Tool | Purpose |
|---|---|
| Xilinx Vivado (2025.2, free WebPACK edition) | Synthesises RTL and programs the FPGA |
| ModelSim (2020.1, free) | Simulation of testebenches for RTL modules |
| RISC-V GCC toolchain (`riscv32-unknown-elf-gcc`) | Compiles C code for the NEORV32 |
| Make | Runs the NEORV32 build system (.elf .bin...) |
| PuTTY or minicom | Serial terminal to see UART program output |
| Git | Version control |
| WSL2 if using windows | Provides a Linux environment for the build tools |
| Python 3 (optional) | Useful for future output scripting |


---

## 3. Pre-installation of the Software Tools

### 3.1 Vivado 2025.2

1. Go to [https://www.xilinx.com/support/download.html](https://www.xilinx.com/support/download.html)
2. Download **Vivado ML Edition** (free WebPACK licence is sufficient)
3. During installation, select only **Zynq-7000** support to save disk space
4. After installation, open Vivado and activate the free WebPACK licence:
   `Help → Manage Licence → Get Free WebPACK Licence`

### 3.2 ModelSim 2020.1
1. Go to the Intel FPGA software download page: https://fpgasoftware.intel.com
2. Download ModelSim Intel FPGA Edition 2020.1
3. Install ModelSim to a known directory (e.g. C:\intelFPGA\20.1\modelsim_ase)

### 3.3 Install WSL2 (if on Windows only, Linux machine with shared files with windows)

All build tools (GCC, Make, Python) run inside WSL2. Open **PowerShell as
Administrator** and run:

```powershell
wsl --install
```

Restart your PC. Ubuntu will finish installing on first launch. Create a
username and password when prompted. Then open the **Ubuntu** app from the
Start menu for all following steps.

### 3.3 RISC-V GCC Toolchain, Make, Python and UART serial terminal for linux

Inside a Linux terminal:

```bash
# Install build dependencies
sudo apt update
# Install Make
sudo apt install make -y
make --version
# Install python (might need other command instead)
sudo apt install make python3 python3-pip git -y

# To install NEORV32 GCC:
# Download the prebuilt NEORV32 toolchain from:
# https://github.com/stnolting/riscv-gcc-prebuilt/releases
# Download the file named: riscv32-unknown-elf.gcc-13.2.0.tar.gz (or latest)

# Create install directory and extract
sudo mkdir -p /opt/riscv
sudo tar -xzf riscv32-unknown-elf.gcc-13.2.0.tar.gz -C /opt/riscv

# Add to PATH — this makes the compiler available in every terminal session
echo 'export PATH="/opt/riscv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify the installation
riscv32-unknown-elf-gcc --version
# Expected output: riscv32-unknown-elf-gcc (gc891d8dc23e) 13.2.0 ...

# Install Uart serial terminal
sudo apt install minicom -y

```

### 3.4 Give USB Serial Port Access (Linux / WSL2 only)

By default your user cannot open serial ports (USB). Fix this once:

```bash
sudo usermod -aG dialout $USER
# Log out and back in for this to take effect
```

**On WSL2**, the USB adapter also needs to be forwarded from Windows. In
**PowerShell as Administrator** (usb cables should be connected to be detected!!!):

```powershell
# Install usbipd
winget install usbipd
# List connected USB devices — find your serial adapter
usbipd list
# Forward it to WSL2 (replace 2-3 with your actual bus ID from the list above)
usbipd attach --wsl --busid 2-3
```

Then inside WSL2, verify it appeared:
```bash
ls /dev/ttyUSB*
# Expected: /dev/ttyUSB0
```

### 3.5 Install Git and VsCode with extensions etc...

Go to the official web page and install Git into your Windows/Linux system and clone the repository

### 3.6 OpenOCD and On-Chip Debugger (needed for JTAG debugging)

**OpenOCD** runs on your PC and speaks the JTAG protocol over the
Pmod JD connector to the NEORV32 On-Chip Debugger (OCD) inside the FPGA.

**GDB** is the debugger that connects to OpenOCD and gives you live
control over the CPU: set breakpoints, inspect registers, read and write
memory, and manually inject faults to validate SEU mitigations.

Neither tool is needed for basic program upload — they are only used
during SEU validation and live hardware debugging.

Run all of the following commands from inside your WSL2 terminal.

#### Step 1 — Install build dependencies

```bash
sudo apt install libtool pkg-config libusb-1.0-0-dev libftdi1-dev \
  autoconf automake texinfo libjim-dev libhidapi-dev -y
git clone https://github.com/openocd-org/openocd.git
cd openocd
./bootstrap
./configure --enable-ftdi
make -j$(nproc)
sudo make install
```

> **Note:** Stay inside the `openocd/` folder for all steps above.
> If you close the terminal and come back later, run `cd openocd` before
> continuing from where you left off.

#### Step 2 — Verify OpenOCD and GDB

```bash
openocd --version
# Expected: Open On-Chip Debugger 0.12.0 or similar
riscv32-unknown-elf-gdb --version
# Expected: GNU gdb ... 13.2.0 or similar
```

---

#### Step 3 - Possible errors if --version fails

**`jimtcl is required but not found via pkg-config`**

```bash
sudo apt install libjim-dev -y
./configure --enable-ftdi
```

If configure still complains about other missing packages, install the
full dependency set:

```bash
sudo apt install libtool pkg-config libusb-1.0-0-dev libftdi1-dev \
  autoconf automake texinfo libjim-dev libhidapi-dev -y
```

Then run `./bootstrap` again followed by `./configure --enable-ftdi`.

**`riscv32-unknown-elf-gdb: error while loading shared libraries: libpython3.8.so.1.0: cannot open shared object file`**

The prebuilt GDB binary was compiled against Python 3.8 but your Ubuntu
has a newer version. Fix it by creating a symlink from the available
Python library to the name GDB is looking for.

First check which Python library you have:

```bash
ls /usr/lib/x86_64-linux-gnu/libpython*
```

Then create the symlink pointing to your version (example shows 3.12,
use whatever version appeared in the output above):

```bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libpython3.12.so.1.0 \
           /usr/lib/x86_64-linux-gnu/libpython3.8.so.1.0
```

Refresh the linker cache and verify:

```bash
sudo ldconfig
riscv32-unknown-elf-gdb --version
```

**`riscv32-unknown-elf-gdb: command not found`**

The toolchain is installed but not on PATH. Fix it:

```bash
echo 'export PATH="/opt/riscv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
riscv32-unknown-elf-gdb --version
```

---

## 4. Project Directory Structure

The repository has the following organization. **Do not change these folder
names** as the TCL script depends on them.

```
neorv32_seu/
│
├── rtl/
│   ├── core/                   ← NEORV32 upstream RTL files (from neorv32/rtl/core/)
│   │                             Never modify these files.
│   ├── top/            ← The top-level wrappers for the Zybo Z7-20
│   │   └── neorv32_seu_chip_debugger_top.vhd
│   └── seu/                    ← SEU protection modules
│
├── constraints/
│   └── zybo_z7_neorv32.xdc     ← Pin assignments for the Zybo Z7-20 (should have same names as tcl script)
│
├── scripts/
│   └── run_neorv32.tcl      ← Script to automatically create vivado project (IMPORTANT!)
│
├── sw/                         ← Software program examples to run on NEORV32 (from neorv32/sw/)
│   ├── example/
│   │   └── hello_world/
│   └── lib/
│
├── build/                     ← Source for vivado projects, should be ignored on git
│
└── README.md                   ← This file
```

---

## 5. Physical Setup — How to connect everything?

### 5.1 Power and Programming Cable

Connect the **USB Micro-B cable** between your PC and the **PROG/UART** port (J13) on
the Zybo Z7-20. This single cable both powers the board and allows Vivado to
program the FPGA.

Flip the power switch to ON. The green DONE LED should light only after the FPGA is programmed.

### 5.2 UART Serial Adapter — Pmod JB

The NEORV32 UART (used for bootloader to implement any c program into neorv32) is routed to
**Pmod JB**. Connect your 3.3V USB-to-TTL adapter to Pmod JB as follows:

```
Zybo Pmod JB          USB-TTL Adapter
─────────────         ───────────────
Pin 1  (T20)  TXD ──→ RXD
Pin 2  (U20)  RXD ←── TXD
Pin 5         GND ─── GND
```

```
Pmod JB pinout (top view):
┌─────────────────────────┐
│  1    2    3    4    5  │  ← top row  (Pin 5 = GND)
│  7    8    9   10   11  │  ← bottom row
└─────────────────────────┘
```

### 5.3 JTAG Debug Probe — Pmod JD

Only needed if you want to use GDB for live debugging. Connect an FTDI-based
JTAG probe to **Pmod JD**:

```
Zybo Pmod JD          JTAG Probe
─────────────         ──────────
Pin 1  (T14)  TCK ──→ TCK
Pin 2  (T15)  TDI ──→ TDI
Pin 3  (P14)  TDO ←── TDO
Pin 4  (R14)  TMS ──→ TMS
Pin 5         GND ─── GND
Pin 6         3V3 ─── VTREF (if your probe needs it)
```

### 5.4 Reset Button

**BTN0** (the leftmost push button on the board) is wired as the NEORV32 reset.
Press it at any time to reset the CPU. The bootloader will restart and wait for
a new upload.

---

## 6. HOW TO RUN ANY PROGRAM INTO THE NEORV32

The Vivado project is generated from a TCL script. This ensures the project is fully reproducible.

### Step 1 — Open the Vivado TCL Console

Open Vivado. In the main window click **Window → Tcl Console** if it is not
already visible at the bottom. In the TCL console, run the following file to recreate the project:

```tcl
neorv32_seu/scripts/run_neorv32.tcl
```

### Step 2 — Run Synthesis and Implementation

In the **Flow Navigator** panel on the left, click **Run Synthesis**.
This takes 5–15 minutes. When it finishes, click **Open Synthesized Design**
and check:

- No **errors** in the log (warnings are usually fine)
- Open **Reports → Utilisation** and save the baseline numbers

Click **Run Implementation** in the Flow Navigator. When done, open the
timing report and confirm **WNS (Worst Negative Slack) is positive or zero**.
A negative WNS means timing is not met and the design may malfunction.

### Step 3 — Generate Bitstream

Click **Generate Bitstream**. This produces the `.bit` file that programs the
FPGA. It takes a few minutes.

### Step 4 — Program the rtl onto the FPGA

1. Make sure the Zybo is powered on and connected via USB Micro-B
2. In Vivado: **Open Hardware Manager → Open Target → Auto Connect**
3. Vivado should detect `xc7z020_1`
4. Click **Program Device** → select the `.bit` file → **Program**
5. The green **DONE** LED on the Zybo should light up

The FPGA now contains the NEORV32. It will start running the bootloader
immediately and wait for you to upload a program.

> **Note:** the bitstream is loaded into volatile FPGA configuration memory.
> It is lost when the board is powered off.

### Step 5 — Open a Serial Terminal

**On Linux / WSL2:**
```bash
minicom -D /dev/ttyUSB0 -b 19200
```

Press **BTN0** on the board to reset the CPU. You should see:

```
<< NEORV32 Bootloader >>
BLDV: ...
HWV:  0x01090004
CLK:  0x07735940     ← 125 MHz shown in hex
...
Autoboot in 8s. Press any key to abort.
CMD:>
```

If you see this, the CPU is alive and we have established UART comms!
If the terminal is blank or shows garbage, check the baud rate and the TXD/RXD wiring.

### Step 6 — Compile a Test Program

Open a Linux terminal and go to any program example to compile it. This command will essentially call Make (from Make file), 
which builds, executes the Neorv32 compiler and cleans previous .bin or .elf files.

```bash
cd your_project/sw/example/hello_world

make RISCV_PREFIX=riscv32-unknown-elf- clean_all exe
```

Once compiled, this will produce several files:
(Memory image ~ the program to be run in NEORV32 in machine instructions):
- .elf: Memory image with metadata for the debugger (with variables, symbols...)
- .bin: Memory image on binary to be shared via uart
- .hex: Memory image on hex format for better human understanding of addresses
- .vhdl: Memory image on rtl to be implemented on hardware (code programmed in ROM, already in presynthesis!)

### Step 7 — Upload the Binary

Now we have the program compiled, but we need to transfer it to the NEORV32 via bootloader in our case (UART).
This is done with a bash script:

```bash
# Make executable (only once)
chmod +x ../../image_gen/uart_upload.sh

# Upload program via uart (path relative from sw/examples, select Uart USB port, .bin is the compiled program on binary)
../../image_gen/uart_upload.sh /dev/ttyUSB0 neorv32_exe.bin
```

The script will automatically press `u` to trigger an upload, send the binary,
then press `e` to execute it. You should see:

```
Hello world! :)
```

The program is running on the NEORV32!

---

### Additional — Writing Your Own Programs

Copy an existing example as a starting point:
Edit `main.c`. The NEORV32 HAL provides these commonly used functions:

```c
#include <neorv32.h>
// Print text over UART
neorv32_uart0_printf("Value: %d\n", my_value);
// Busy-wait delay
neorv32_cpu_delay_ms(500);           // wait 500 milliseconds
```

Compile and upload exactly as in Steps 2 and 3.

---

## Additional - Adding SEU Mitigation techniques

When you are ready to start implementing protections, follow this pattern to
keep your work clean and measurable:

### RTL Placement

Place every new mitigation module in `rtl/seu/`:

```
rtl/seu/
├── tmr_voter.vhd          ← example: triple modular redundancy voter
├── register_scrubber.vhd  ← example: register file scrubbing
└── ecc_wrapper.vhd        ← example: error correcting code wrapper
```

The TCL script automatically picks up all `.vhd` files from this folder.

### Workflow for Each New Module

```
1. Write your module in rtl/seu/my_module.vhd
         ↓
2. Verify by creating a testbench and check on ModelSim
         ↓
3. Verify again with more complex testbenches!!
         ↓
4. Use ip packaging on Vivado and wrap it in AXIL (Master or Slave)
         ↓
5. Use ip on block design on Vivado and test it by using JTAG-TO-AXI core
         ↓
6. This can easily be done with a TCL script and ILA cores
         ↓
7. If more complexity, use the PS (Vitis) to generate the control sequence and check with ILA
         ↓
8. If validated, integrate on neorv32_top or neorv32_cpu or top layer depending on module impact
         ↓
9. Write bitstream and test with either PS (vitis), C program (neorv32) or TCL script (can use ILA)
         ↓
10. Test with neorv32 and check if SEU is mitigated (ILA, debugger)
         ↓
11. Check performance change and commit!
```

---

## Authors - SEU mitigation techniques

- Aldo Lupio
- Olivier Oribes
- Teresa Bäurle

## License (NEORV32)

This is an open-source project that is free of charge and provided under an
permissive [license](https://github.com/stnolting/neorv32/blob/main/LICENSE).
See the [legal](https://stnolting.github.io/neorv32/#_legal) section for more information.

