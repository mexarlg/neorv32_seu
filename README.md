# SEU Resilient NEORV32 RISC-V Core

Student research project at **ISAE SUPAERO** focused on improving the fault tolerance of a RISC-V soft-core processor by implementing **Single Event Upset (SEU) mitigation techniques**. The base processor is the **NEORV32 RISC-V CPU v1.11.6**, extended and modified at the RTL level to study hardware-level reliability improvements.

Mitigation techniques under investigation:
- Redundancy based techniques (TMR)
- Error detection and correction for memory (EDAC)
- Parity bits on registers
- DLD protection on control logic
- Fault detection strategies (Watchdog)

---

## 1. Hardware Needed

| Item | Purpose |
|---|---|
| Digilent Zybo Z7-20 | FPGA development board |
| USB Micro-B cable | Programs the FPGA and powers the board |
| Digilent PmodUSBUART | UART communication with the NEORV32 bootloader |
| Digilent JTAG-HS2 (optional) | On-chip GDB debugging via Pmod JD |

---

## 2. Software Needed

| Tool | Purpose |
|---|---|
| Xilinx Vivado 2025.2 (free WebPACK) | Synthesise RTL and program the FPGA |
| ModelSim 2020.1 (free) | Simulate and verify RTL modules |
| `riscv32-unknown-elf-gcc 13.2.0` | Compile C programs for the NEORV32 |
| Make | Runs the NEORV32 build system |
| minicom | Serial terminal to see UART output |
| Git | Version control |
| WSL2 (Windows only) | Linux environment for build tools |

---

## 3. Software Installation

### 3.1 Vivado

1. Download **Vivado ML Edition** from [xilinx.com/support/download.html](https://www.xilinx.com/support/download.html)
2. During installation select only **Zynq-7000** support to save disk space
3. Activate the free WebPACK licence: `Help → Manage Licence → Get Free WebPACK Licence`

### 3.2 ModelSim

1. Download ModelSim Intel FPGA Edition 2020.1 from [fpgasoftware.intel.com](https://fpgasoftware.intel.com)
2. Install to a known directory (e.g. `C:\intelFPGA\20.1\modelsim_ase`)

### 3.3 WSL2 (Windows only)

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

Restart your PC. Ubuntu will finish installing on first launch. After that open the **Ubuntu** app from the Start menu for all following steps.

### 3.4 RISC-V Toolchain and Build Tools

Inside a Linux or WSL2 terminal:

```bash
# Install Make and minicom
sudo apt update
sudo apt install make minicom -y

# Download the NEORV32 prebuilt GCC toolchain
# Go to: https://github.com/stnolting/riscv-gcc-prebuilt/releases
# Download: riscv32-unknown-elf.gcc-13.2.0.tar.gz
# Then install:
sudo mkdir -p /opt/riscv
sudo tar -xzf riscv32-unknown-elf.gcc-13.2.0.tar.gz -C /opt/riscv

# Add to PATH permanently
echo 'export PATH="/opt/riscv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
riscv32-unknown-elf-gcc --version
# Expected: riscv32-unknown-elf-gcc 13.2.0
```

> **Important:** the toolchain must be configured for `rv32i`. Verify with:
> ```bash
> riscv32-unknown-elf-gcc -Q --help=target | grep march
> # Must show: rv32i (NOT rv32e)
> ```
> If it shows `rv32e` the toolchain is wrong — download the correct one from the link above.

### 3.5 USB Serial Port Permissions

```bash
# Fix permanently (log out and back in after this)
sudo usermod -aG dialout $USER
```

### 3.6 USB Forwarding to WSL2 (Windows only)

Install usbipd in **PowerShell as Administrator**:

```powershell
winget install usbipd
```

Every session, with USB cables connected, run:

```powershell
# List devices to find the BUSID of your PmodUSBUART
usbipd list
# Expected entry: 0403:6001  USB Serial Converter

# Bind once (first time only per device)
usbipd bind --busid 4-3

# Attach to WSL2 every session
usbipd attach --wsl --busid 4-3
```

Verify in WSL2:

```bash
ls /dev/ttyUSB*
# Expected: /dev/ttyUSB0
```

### 3.7 OpenOCD and GDB (optional — for JTAG debugging only)

Only needed when using the JTAG-HS2 probe for live CPU debugging.

```bash
# Install dependencies
sudo apt install libtool pkg-config libusb-1.0-0-dev libftdi1-dev \
  autoconf automake texinfo libjim-dev libhidapi-dev -y

# Build OpenOCD from source
git clone https://github.com/openocd-org/openocd.git
cd openocd
./bootstrap
./configure --enable-ftdi
make -j$(nproc)
sudo make install

# Verify
openocd --version
riscv32-unknown-elf-gdb --version
```

If GDB fails with `libpython3.8.so.1.0: No such file or directory`:

```bash
# Find your Python library version
ls /usr/lib/x86_64-linux-gnu/libpython*

# Create symlink (replace 3.12 with your actual version)
sudo ln -s /usr/lib/x86_64-linux-gnu/libpython3.12.so.1.0 \
           /usr/lib/x86_64-linux-gnu/libpython3.8.so.1.0
sudo ldconfig
riscv32-unknown-elf-gdb --version
```

---

## 4. Project Structure

```
neorv32_seu/
├── rtl/
│   ├── core/          ← NEORV32 v1.11.6 RTL files — do not modify
│   ├── top/           ← Your top-level wrapper for the Zybo Z7-20
│   └── seu/           ← SEU mitigation modules go here
├── constraints/
│   └── zybo_z7_neorv32.xdc   ← Zybo Z7-20 pin assignments
├── scripts/
│   ├── run_neorv32.tcl       ← Creates the Vivado project automatically
│   └── neorv32_run.sh        ← Compiles and uploads programs to the board
├── sw/                ← NEORV32 v1.11.6 software framework
│   ├── example/       ← Example C programs
│   └── lib/           ← NEORV32 HAL (hardware drivers)
├── build/             ← Vivado project files (ignored by git)
└── README.md
```

> **Version note:** both `rtl/core/` and `sw/` must be from **NEORV32 v1.11.6**.
> Mixing versions causes bootloader signature mismatches and upload failures.
> Verify at any time with:
> ```bash
> grep "hw_version" rtl/core/neorv32_package.vhd
> # Must show: x"01110600"
> ```

---

## 5. Physical Connections

### 5.1 Power and Programming

Connect the **USB Micro-B cable** to the **PROG/UART port (J13)** on the Zybo.
This powers the board and lets Vivado program the FPGA. Flip the power switch ON.
The green DONE LED only lights up after the FPGA is programmed.

### 5.2 UART — PmodUSBUART on Pmod JB

Plug the PmodUSBUART directly into **Pmod JB** (right side of board, second connector from top).
Align pin 1 of the module with pin 1 of the connector (marked with a small triangle on the PCB).
Connect the module's micro-USB cable to your PC.

> Set jumper **JP1 to LCL** on the PmodUSBUART since the Zybo is already powered by the programming cable.

### 5.3 JTAG — JTAG-HS2 on Pmod JD (optional)

Connect the JTAG-HS2 individual pins to **Pmod JD** using jumper wires:

```
HS2 Pin 1 (TCK) → Pmod JD Pin 1 (T14)
HS2 Pin 2 (GND) → Pmod JD Pin 5 (GND)
HS2 Pin 3 (TDO) → Pmod JD Pin 3 (P14)
HS2 Pin 4 (TDI) → Pmod JD Pin 2 (T15)
HS2 Pin 5 (VDD) → Pmod JD Pin 6 (3V3)
HS2 Pin 6 (TMS) → Pmod JD Pin 4 (R14)
```

### 5.4 Reset Button

**BTN0** (leftmost button on the board) resets the NEORV32 CPU.
Press it any time to restart the bootloader.

---

## 6. Running a Program on the NEORV32

### Step 1 — Create the Vivado Project

Open Vivado and in the TCL console run:

```tcl
source C:/path/to/neorv32_seu/scripts/run_neorv32.tcl
```

> Use forward slashes `/` even on Windows inside the Vivado TCL console.

### Step 2 — Synthesise, Implement and Generate Bitstream

In the Flow Navigator:
1. **Run Synthesis** — check for no errors and save the utilisation report as your baseline
2. **Run Implementation** — confirm **WNS ≥ 0** in the timing report
3. **Generate Bitstream**

### Step 3 — Program the FPGA

1. **Open Hardware Manager → Open Target → Auto Connect**
2. Vivado detects `xc7z020_1`
3. **Program Device** → select the `.bit` file → **Program**
4. The green **DONE** LED lights up — the NEORV32 is running

### Step 4 — Verify the Bootloader

Attach the PmodUSBUART to WSL2 (once per session in PowerShell as Administrator):

```powershell
usbipd attach --wsl --busid 4-3
```

Then open a serial terminal in WSL2:

```bash
minicom -D /dev/ttyUSB0 -b 19200
```

Press **BTN0**. You should see:

```
<< NEORV32 Bootloader >>
HWV:  0x01110600        ← confirms v1.11.6 is running
CLK:  0x07735940        ← 125 MHz
...
Auto-boot in 10s. Press any key to abort.
```

`HWV: 0x01110600` confirms the correct version. Exit minicom with `Ctrl+A` then `X`.

### Step 5 — Compile and Upload a Program

Use the provided script from the project root:

```bash
# First time only — make executable
chmod +x scripts/neorv32_run.sh

# Compile, upload and open serial monitor automatically
./scripts/neorv32_run.sh hello_world
./scripts/neorv32_run.sh demo_blink_led
```

Expected output for hello world:

```
Hello world! :)
```

### Step 6 — Write Your Own Program

Copy an example and edit `main.c`:

```bash
cp -r sw/example/hello_world sw/example/my_program
```

Useful HAL functions:

```c
#include <neorv32.h>

neorv32_uart0_printf("Value: %d\n", my_value);  // print over UART
neorv32_gpio_port_set(0xF);                      // set GPIO outputs
neorv32_cpu_delay_ms(500);                       // wait 500ms
```

Then run it:

```bash
./scripts/neorv32_run.sh my_program
```

---

## 7. Adding SEU Mitigation Modules

Place new mitigation modules in `rtl/seu/`. The TCL script picks them up automatically.

```
rtl/seu/
├── tmr_voter.vhd
├── register_scrubber.vhd
└── ecc_wrapper.vhd
```

Recommended workflow for each new module:

```
1. Write module in rtl/seu/
2. Verify with a ModelSim testbench
3. Package as Vivado IP and test with JTAG-to-AXI
4. Integrate into neorv32_top or top wrapper
5. Generate bitstream and test on hardware
6. Validate SEU mitigation with ILA and/or GDB debugger
7. Record utilisation and timing vs baseline — commit
```

---

## Authors

- Aldo Lupio
- Olivier Oribes
- Teresa Bäurle

## License

NEORV32 is open-source under the BSD-3-Clause license.
See [neorv32/LICENSE](https://github.com/stnolting/neorv32/blob/main/LICENSE) for details.
