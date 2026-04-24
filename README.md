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
| Xilinx Vivado 2025.2 | Synthesise RTL and program the FPGA |
| ModelSim 2020.1 | Simulate and verify RTL modules |
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
```

#### Option A — Prebuilt toolchain (recommended)

```bash
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

> **Important — verify the architecture is rv32i not rv32e:**
> ```bash
> riscv32-unknown-elf-gcc -Q --help=target | grep march
> # Must show: rv32i (NOT rv32e)
> ```
> If it shows `rv32e` the toolchain was built for the wrong architecture.
> Download the correct one from the stnolting prebuilt releases link above —
> specifically the package named `riscv32-unknown-elf`.

#### Option B — Build from source (Linux/Fedora only, takes 30-60 minutes)

Only use this if the prebuilt toolchain does not work on your system:

```bash
bash --noprofile --norc
export PATH=/usr/bin:/bin:/usr/local/bin
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32i --with-abi=ilp32
sudo make -j$(nproc)
```

You’ll need to run sudo make -j$(nproc) until the toolchain is fully installed. It builds in three stages, so you’ll have to run it three times.
Once the installation is complete, add the toolchain to your PATH in .bashrc.

```bash
# Add to PATH
echo 'export PATH=/opt/riscv/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 3.5 USB Serial Port Permissions

```bash
# Fix permanently (log out and back in after this)
sudo usermod -aG dialout $USER
```

### 3.6 USB Forwarding to WSL2 (Need USB (uart) cable connected!)

Install usbipd in **PowerShell as Administrator**:

```powershell
winget install usbipd
```

Now lets make sure you find the uart port:

```powershell
# List devices to find the BUSID of your PmodUSBUART
usbipd list
# Expected entry: 0403:6001  USB Serial Converter

# Bind once (first time only per device, use the (4-3) id of 6001 - uart)
usbipd bind --busid 4-3
```

Every time in a new session, the usb port should be passed to WSL. But for now this is enough!

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
│   ├── run_neorv32.tcl                   ← Creates the Vivado project automatically
│   ├── build_neorv32_bitstream.tcl       ← Creates the bitstream and runs reports
│   ├── neorv32_debug_session.py          ← Template module for debugging and testing using openOCD
compile_neorv32.sh     ← Compiles and uploads programs to cpu (FPGA programmed, neorv32 restarted)
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

## 5. LETS START PLAYING! - Physical Connections

### 5.1 Power and Programming

Connect the **USB Micro-B cable** to the **PROG/UART port (J12)** on the Zybo.
This powers the board and lets Vivado program the FPGA. Flip the power switch ON.
The green DONE LED only lights up after the FPGA is programmed.

### 5.2 UART — PmodUSBUART on Pmod JB

> Set jumper **JP1 connecting LCL and VCC** on the PmodUSBUART (blue cap) since the Zybo is already powered by the programming cable.

Plug the PmodUSBUART directly into **Pmod JB** (top row of JB, with blue jumper cap of converter board up).
This is aligning pin 1 of the pmod with pin 1 of the pcb (marked with a "1" on pcb, and a "square" on the pmod).
Connect the module's micro-USB cable to your PC.

### 5.3 JTAG — JTAG-HS2 on Pmod JD (optional)

Connect the JTAG-HS2 individual pins to **Pmod JD** using jumper wires:

```
jtag_tck_i   → Pmod JD pin 1                 (T14)
jtag_tdi_i   → Pmod JD pin 2                 (T15)
jtag_tdo_o   → Pmod JD pin 3                 (P14)
jtag_tms_i   → Pmod JD pin 4                 (R14)
```

### 5.4 Reset Button

**BTN0** (leftmost button on the board) resets the NEORV32 CPU.
Press it any time to restart the NEORV32 bootloader.

---

## 6. Running a Program on the NEORV32

### Step 1 — Create the Vivado Project

Open Vivado and run TCL script:

```tcl
neorv32_seu/scripts/run_neorv32.tcl
```

### Step 2 — Synthesise, Implement and Generate Bitstream

In the Flow Navigator:
1. **Run Synthesis** — check for no errors and save the utilisation report as your baseline
2. **Run Implementation** — confirm **WNS ≥ 0** in the timing report
3. **Generate Bitstream**

Or run the following tcl script to generate reports and the bitstream:

```tcl
neorv32_seu/scripts/build_neorv32_bitstream.tcl
```

### Step 3 — Program the FPGA

1. **Open Hardware Manager → Open Target → Auto Connect**
2. Vivado detects `xc7z020_1`
3. **Program Device** → select the `.bit` file → **Program**
4. The green **DONE** LED lights up — the NEORV32 is running

### Step 4 — Verify the Bootloader

Attach the PmodUSBUART port to WSL2 (ONCE PER SESSION in PowerShell as Administrator):

(Check id of usb port so it corresponds to the single uart (6001), in my case its id 4-3)

```powershell
usbipd attach --wsl --busid 4-3
```
Verify in WSL2:

```bash
ls /dev/ttyUSB*
# Expected: /dev/ttyUSB0
```

Then open a serial terminal in WSL2:

```bash
minicom -D /dev/ttyUSB0 -b 19200
```

Press **BTN0** to restart NEORV32. You should see:

```
<< NEORV32 Bootloader >>
HWV:  0x01110600        ← confirms v1.11.6 is running
CLK:  0x07735940        ← 125 MHz
...
Auto-boot in 10s. Press any key to abort.
```

`HWV: 0x01110600` confirms the correct version. Exit minicom with `Ctrl+A` then `X` and `Enter`.

The FPGA is set. The neorv32 is set. And the uart communication between both is set. Now lets run a program!

### Step 5 — Compile and Upload a Program

Use the provided script from the project root:

```bash
# If this is the first time: — make executable
chmod +x compile_neorv32.sh

# Compile, upload a program example (more details inside compile_neorv32 file)
./compile_neorv32.sh hello_world
# Every time a different program is run, the neorv32 should be rst (btn0)!
./compile_neorv32.sh demo_blink_led
```

Expected output for hello world:

```
Hello world! :)
```

### Step 6 — Write Your Own Program

Copy an example, create its foulder inside sw/example and edit the `main.c`:

```c
#include <neorv32.h>

neorv32_uart0_printf("Value: %d\n", my_value);  // print over UART
neorv32_gpio_port_set(0xF);                      // set GPIO outputs
neorv32_cpu_delay_ms(500);                       // wait 500ms
```

Then run it:

```bash
./neorv32_run.sh my_program
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
