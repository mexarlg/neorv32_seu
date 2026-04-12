#!/usr/bin/env python3
# =============================================================================
# neorv32_debug_session.py
# NEORV32 GDB Debug Session Template for SEU Mitigation Research
#
# This script drives a complete GDB debug session programmatically using
# GDB's Python MI (Machine Interface). It demonstrates every useful operation
# for SEU validation: reading state, injecting faults, monitoring recovery.
#
# PREREQUISITES:
#   - FPGA programmed with NEORV32 OCD bitstream
#   - JTAG probe connected to Pmod JD (TCK=T14, TDI=T15, TDO=P14, TMS=R14)
#   - OpenOCD running in a separate terminal (see start_openocd.sh)
#   - Program compiled with debug symbols: make clean_all exe
#
# USAGE:
#   # Terminal 1 — start OpenOCD first (leave it running):
#   cd sw/openocd
#   openocd -f openocd_neorv32.cfg
#
#   # Terminal 2 — run GDB interactively (recommended for learning):
#   cd sw/example/hello_world
#   riscv32-unknown-elf-gdb main.elf
#
#   # OR run this script for automated fault injection:
#   python3 scripts/neorv32_debug_session.py
#
# NEORV32 MEMORY MAP (relevant addresses):
#   IMEM (instruction memory):  0x00000000 - 0x00003FFF  (16KB default)
#   DMEM (data memory):         0x80000000 - 0x80001FFF  (8KB default)
#   GPIO base:                  0xFFFC0000
#   UART0 base:                 0xFFFFA000
#   Debug Module:               0xFFFF0000
# =============================================================================

import subprocess
import time
import sys

# =============================================================================
# CONFIGURATION — adjust these to match your setup
# =============================================================================
GDB_EXECUTABLE  = "riscv32-unknown-elf-gdb"
ELF_FILE        = "sw/example/hello_world/main.elf"
OPENOCD_HOST    = "localhost"
OPENOCD_PORT    = 3333

# NEORV32 memory layout — must match your VHDL generics
IMEM_BASE       = 0x00000000
IMEM_SIZE       = 16 * 1024   # 16KB — change if you changed MEM_INT_IMEM_SIZE
DMEM_BASE       = 0x80000000
DMEM_SIZE       = 8  * 1024   # 8KB  — change if you changed MEM_INT_DMEM_SIZE


# =============================================================================
# PART 1 — INTERACTIVE GDB COMMANDS REFERENCE
# Copy-paste these into a GDB terminal session. This is the recommended way
# to learn the debugger before running automated scripts.
# =============================================================================

INTERACTIVE_SESSION_GUIDE = """
# ============================================================================
# NEORV32 INTERACTIVE GDB SESSION — complete command reference
# Run from the example folder: riscv32-unknown-elf-gdb main.elf
# OpenOCD must already be running in another terminal.
# ============================================================================

# --- 1. INITIALISATION -------------------------------------------------------

# Connect to OpenOCD (always do this first)
target extended-remote localhost:3333

# Reset the CPU and immediately halt it before it executes anything
monitor reset halt

# Load the ELF file symbols (if not passed on command line)
file main.elf

# Upload the program binary into IMEM via JTAG
load

# Verify the upload was correct (optional but recommended)
compare-sections


# --- 2. BASIC EXECUTION CONTROL ---------------------------------------------

# Resume execution (run until breakpoint or manual halt)
continue
c                           # short form

# Halt execution at any time
# Press Ctrl+C in the GDB terminal

# Step one machine instruction at a time
stepi
si                          # short form

# Step one C source line at a time (steps over function calls)
next
n                           # short form

# Step one C source line, stepping INTO function calls
step
s                           # short form

# Run until the current function returns
finish

# Reset and halt the CPU (restart from beginning)
monitor reset halt


# --- 3. BREAKPOINTS AND WATCHPOINTS -----------------------------------------

# Break at a C function name
break main
break neorv32_uart0_printf

# Break at a specific source line
break main.c:42

# Break at a specific memory address (useful when you have no symbols)
break *0x000001A4

# List all breakpoints
info breakpoints

# Delete a breakpoint by number
delete 1

# Disable/enable without deleting
disable 2
enable 2

# Hardware watchpoint — halt when a memory address is written
watch *(int*)0x80000100

# Hardware watchpoint — halt when a memory address is read
rwatch *(int*)0x80000100

# Hardware watchpoint — halt on either read or write
awatch *(int*)0x80000100


# --- 4. READING CPU REGISTERS ------------------------------------------------

# Show all general-purpose registers (x0-x31 plus pc)
info registers

# Show a specific register by ABI name
print $t0
print $sp                   # stack pointer
print $ra                   # return address
print/x $pc                 # program counter in hex

# Show all registers in hex format
info registers all

# RISC-V register ABI names reference:
#   x0  = zero  (always 0)
#   x1  = ra    (return address)
#   x2  = sp    (stack pointer)       ← critical for SEU testing
#   x3  = gp    (global pointer)
#   x4  = tp    (thread pointer)
#   x5  = t0    (temporary)           ← good for fault injection tests
#   x6  = t1    (temporary)
#   x7  = t2    (temporary)
#   x8  = s0/fp (saved / frame ptr)
#   x9  = s1    (saved register)
#   x10 = a0    (arg/return value)    ← function return values live here
#   x11 = a1    (arg/return value)
#   x12 = a2    (argument)
#   ...
#   x28 = t3    (temporary)
#   x29 = t4    (temporary)
#   x30 = t5    (temporary)
#   x31 = t6    (temporary)


# --- 5. READING RISC-V CSRs (Control and Status Registers) ------------------
# These are the most important registers for SEU research.
# They reveal CPU execution state, trap causes, and performance counters.

# Read the machine cycle counter (counts every clock tick)
monitor reg mcycle

# Read the instruction-retired counter (counts every completed instruction)
monitor reg minstret

# Read the machine status register (privilege mode, interrupt enable bits)
monitor reg mstatus

# Read the trap cause register — CRITICAL for SEU detection
# After an unexpected exception, this tells you WHAT went wrong:
#   0x00000000 = instruction address misaligned
#   0x00000001 = instruction access fault
#   0x00000002 = illegal instruction        ← SEU corrupting instruction bits
#   0x00000003 = breakpoint
#   0x00000004 = load address misaligned
#   0x00000005 = load access fault
#   0x00000006 = store address misaligned
#   0x00000007 = store access fault
#   0x0000000B = environment call (ecall)
#   0x80000007 = machine timer interrupt    ← CLINT timer
monitor reg mcause

# Read the trap value register (additional info about the trap)
# For instruction faults: contains the faulting instruction address
# For load/store faults: contains the faulting memory address
monitor reg mtval

# Read the machine exception program counter
# Contains the address of the instruction that caused the trap
monitor reg mepc

# Read the machine ISA register (shows enabled extensions)
monitor reg misa

# Read NEORV32-specific custom CSR: hardware configuration
monitor reg mxisa


# --- 6. READING AND WRITING MEMORY ------------------------------------------

# Read 10 words (32-bit) from IMEM (instruction memory)
x/10w 0x00000000

# Read as instructions (disassemble from address)
x/10i 0x00000000

# Read 10 words from DMEM (data memory)
x/10w 0x80000000

# Read a C variable by name (requires debug symbols)
print my_variable
print *my_pointer
print my_array[0]

# Write a value to a memory address
set {int}0x80000100 = 0x12345678

# Read back to confirm
x/1w 0x80000100

# Read NEORV32 GPIO output register (base + 0x04 = output port)
x/1w 0xFFFC0004

# Read NEORV32 UART0 control register
x/1w 0xFFFFA000


# --- 7. SEU FAULT INJECTION — MANUAL ----------------------------------------
# These commands simulate a Single Event Upset by corrupting CPU state.
# Run your target program first, then halt it and inject faults.

# --- 7a. Register corruption (simulates SEU in register file) ---

# Flip a single bit in register t0 (bit 0)
set $t0 = $t0 ^ 0x00000001

# Flip a specific bit (bit 15) in register a0
set $a0 = $a0 ^ 0x00008000

# Completely corrupt a register with a random value
set $t1 = 0xDEADBEEF

# Corrupt the stack pointer (severe fault — will likely cause crash)
# Use this to test if your mitigation can detect stack corruption
set $sp = $sp + 4

# Corrupt the return address (will cause jump to wrong address on return)
set $ra = 0xDEADBEEF

# Corrupt the program counter (CPU immediately jumps to wrong address)
set $pc = 0x00000100

# --- 7b. Memory corruption (simulates SEU in data memory) ---

# Flip bit 0 of a word in DMEM
set {int}0x80000200 = {int}0x80000200 ^ 0x00000001

# Corrupt an entire word in DMEM
set {int}0x80000200 = 0xDEADBEEF

# Corrupt the first word of IMEM (corrupts first instruction — extreme fault)
# WARNING: this will corrupt instruction memory — CPU will crash
# Only use this to confirm fault detection, then reset
set {int}0x00000000 = 0xDEADBEEF

# --- 7c. After injecting a fault, resume and observe ---
continue

# Check what happened if a trap fired
monitor reg mcause
monitor reg mepc
monitor reg mtval


# --- 8. SEU MITIGATION VERIFICATION PATTERN ---------------------------------
# Standard workflow for testing a mitigation module:

# Step 1: Upload and run program to a known good state
monitor reset halt
load
break main
continue                    # run to main()

# Step 2: Confirm CPU is executing correctly
info registers
print $pc

# Step 3: Run to the function protected by your mitigation
break protected_function
continue

# Step 4: Inject a fault into the protected register/memory
set $s0 = $s0 ^ 0x00000004   # flip bit 2 of s0

# Step 5: Resume and observe behaviour
continue

# Step 6: Check if the trap handler fired (mitigation should prevent this)
monitor reg mcause
# If mcause == 0: no trap → mitigation corrected the fault ✓
# If mcause != 0: trap fired → mitigation failed or detected but not corrected

# Step 7: Reset and repeat for next fault scenario
monitor reset halt


# --- 9. LOADING A PROGRAM WITHOUT THE BOOTLOADER ----------------------------
# You can also load programs via JTAG instead of the UART bootloader.
# This is faster for iterative testing during SEU research.

monitor reset halt
file main.elf
load
monitor resume 0x00000000    # jump to address 0 and run


# --- 10. USEFUL GDB SETTINGS ------------------------------------------------

# Show source code around current instruction
list

# Set number of lines shown by list
set listsize 20

# Show disassembly of current function
disassemble

# Show disassembly with source code mixed
disassemble /s main

# Print a value every time execution stops (useful for monitoring a variable)
display my_variable
display $pc
display $mcause

# Stop displaying
undisplay 1

# Log GDB output to a file (useful for automated experiments)
set logging file gdb_session.log
set logging on
# ... run your commands ...
set logging off

# Exit GDB
quit
"""


# =============================================================================
# PART 2 — OPENOCD CONFIGURATION
# The repository provides sw/openocd/openocd_neorv32.cfg and interface.cfg
# This section explains what they contain and how to adapt them.
# =============================================================================

OPENOCD_CONFIG_NOTES = """
# ============================================================================
# OPENOCD CONFIGURATION NOTES
# ============================================================================
#
# The NEORV32 repository provides two OpenOCD config files in sw/openocd/:
#
#   openocd_neorv32.cfg  — NEORV32 target configuration (do not modify)
#   interface.cfg        — JTAG adapter configuration (YOU must adapt this)
#
# HOW TO START OPENOCD:
#   cd sw/openocd
#   openocd -f openocd_neorv32.cfg
#
# The interface.cfg file needs to match your JTAG probe hardware.
# Common adapters and their OpenOCD interface files:
#
#   FTDI FT2232H breakout:   interface/ftdi/um232h.cfg
#   FTDI FT232H breakout:    interface/ftdi/ft232h-module-swd.cfg
#   Digilent JTAG-HS2:       interface/ftdi/digilent_jtag_hs2.cfg
#   J-Link:                  interface/jlink.cfg
#
# Example interface.cfg for a generic FTDI FT2232H:
#
#   adapter driver ftdi
#   ftdi vid_pid 0x0403 0x6010
#   ftdi channel 0
#   ftdi layout_init 0x0008 0x000b
#   adapter speed 2000
#
# SUCCESSFUL CONNECTION OUTPUT:
#   Info : JTAG tap: neorv32.cpu tap/device found: 0x00000001
#   Info : [neorv32.cpu] Examination succeed
#   Info : Listening on port 3333 for gdb connections
#   Target RESET and HALTED. Ready for remote connections.
#
# COMMON ERRORS:
#   "JTAG scan chain interrogation failed: all zeroes"
#     → Check wiring. TCK/TDI/TDO/TMS/GND all connected to Pmod JD?
#     → Is the FPGA programmed and powered?
#     → Try reducing adapter speed: adapter speed 500
#
#   "libusb_open() failed"
#     → USB adapter not forwarded to WSL2
#     → Run: usbipd attach --wsl --busid X  (in PowerShell as Administrator)
#
#   "dtmcontrol is 0"
#     → OCD not enabled in bitstream generics (OCD_EN must be true)
#     → Wrong JTAG adapter or wrong interface config file
# ============================================================================
"""


# =============================================================================
# PART 3 — AUTOMATED FAULT INJECTION USING GDB/MI
# This class drives GDB programmatically for systematic SEU testing.
# =============================================================================

class NEORV32Debugger:
    """
    Drives a GDB session programmatically for automated SEU fault injection.

    Example usage:
        dbg = NEORV32Debugger("main.elf")
        dbg.connect()
        dbg.reset_and_halt()
        dbg.load_program()
        dbg.run_to_function("main")

        # Read baseline state
        pc  = dbg.read_register("pc")
        t0  = dbg.read_register("t0")
        print(f"PC=0x{pc:08X}  t0=0x{t0:08X}")

        # Inject fault
        dbg.inject_register_fault("t0", bit=3)

        # Resume and check for trap
        dbg.resume()
        time.sleep(0.1)
        cause = dbg.read_csr("mcause")
        if cause == 0:
            print("PASS: No trap — mitigation corrected fault")
        else:
            print(f"FAIL: Trap fired, mcause=0x{cause:08X}")

        dbg.close()
    """

    def __init__(self, elf_file):
        self.elf_file = elf_file
        self.process  = None

    def connect(self):
        """Start GDB and connect to OpenOCD."""
        print(f"[DBG] Starting GDB with {self.elf_file}")
        self.process = subprocess.Popen(
            [GDB_EXECUTABLE, "--interpreter=mi", self.elf_file],
            stdin  = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE,
            text   = True
        )
        self._wait_for_prompt()

        print(f"[DBG] Connecting to OpenOCD at {OPENOCD_HOST}:{OPENOCD_PORT}")
        self._send(f"target extended-remote {OPENOCD_HOST}:{OPENOCD_PORT}")
        self._wait_for_prompt()

    def reset_and_halt(self):
        """Reset the CPU and halt it immediately."""
        print("[DBG] Resetting and halting CPU")
        self._send("monitor reset halt")
        self._wait_for_prompt()

    def load_program(self):
        """Upload the ELF binary into IMEM via JTAG."""
        print(f"[DBG] Loading {self.elf_file} into IMEM")
        self._send("load")
        self._wait_for_prompt()

    def run_to_function(self, function_name):
        """Set a breakpoint at a function and run to it."""
        print(f"[DBG] Running to function: {function_name}")
        self._send(f"break {function_name}")
        self._wait_for_prompt()
        self._send("continue")
        self._wait_for_prompt()

    def run_to_address(self, address):
        """Set a breakpoint at an address and run to it."""
        print(f"[DBG] Running to address: 0x{address:08X}")
        self._send(f"break *0x{address:08X}")
        self._wait_for_prompt()
        self._send("continue")
        self._wait_for_prompt()

    def resume(self):
        """Resume CPU execution."""
        self._send("continue")

    def halt(self):
        """Halt CPU execution."""
        self._send("interrupt")
        self._wait_for_prompt()

    # -------------------------------------------------------------------------
    # Register operations
    # -------------------------------------------------------------------------

    def read_register(self, reg_name):
        """Read a general-purpose register. Returns integer value."""
        self._send(f"print/x ${reg_name}")
        output = self._wait_for_prompt()
        # Parse the value from GDB output like: $1 = 0x000001a4
        for line in output.split("\n"):
            if "= 0x" in line or "= -" in line or "= " in line:
                try:
                    val = line.split("=")[-1].strip()
                    return int(val, 16) if "0x" in val else int(val)
                except ValueError:
                    pass
        return None

    def write_register(self, reg_name, value):
        """Write a value to a general-purpose register."""
        print(f"[DBG] Writing ${reg_name} = 0x{value:08X}")
        self._send(f"set ${reg_name} = 0x{value:08X}")
        self._wait_for_prompt()

    def inject_register_fault(self, reg_name, bit):
        """
        Inject a single-bit fault into a register by flipping one bit.
        This simulates a Single Event Upset in the register file.

        Args:
            reg_name: register ABI name e.g. 't0', 'a0', 's1'
            bit:      bit position to flip (0=LSB, 31=MSB)
        """
        mask = 1 << bit
        print(f"[DBG] Injecting fault: ${reg_name} bit {bit} flip (mask=0x{mask:08X})")
        self._send(f"set ${reg_name} = ${reg_name} ^ 0x{mask:08X}")
        self._wait_for_prompt()

    def read_all_registers(self):
        """Read and return all general-purpose registers as a dict."""
        reg_names = [
            "zero","ra","sp","gp","tp",
            "t0","t1","t2",
            "s0","s1",
            "a0","a1","a2","a3","a4","a5","a6","a7",
            "s2","s3","s4","s5","s6","s7","s8","s9","s10","s11",
            "t3","t4","t5","t6",
            "pc"
        ]
        registers = {}
        for name in reg_names:
            val = self.read_register(name)
            if val is not None:
                registers[name] = val
        return registers

    # -------------------------------------------------------------------------
    # CSR operations
    # -------------------------------------------------------------------------

    def read_csr(self, csr_name):
        """
        Read a RISC-V Control and Status Register.

        Key CSRs for SEU research:
            mcause   - trap cause (0 = no trap)
            mepc     - exception program counter
            mtval    - trap value (faulting address)
            mstatus  - machine status
            mcycle   - cycle counter
            minstret - instruction counter
        """
        self._send(f"monitor reg {csr_name}")
        output = self._wait_for_prompt()
        for line in output.split("\n"):
            if "0x" in line:
                try:
                    val = line.split("0x")[-1].strip().split()[0]
                    return int(val, 16)
                except ValueError:
                    pass
        return None

    # -------------------------------------------------------------------------
    # Memory operations
    # -------------------------------------------------------------------------

    def read_memory_word(self, address):
        """Read a 32-bit word from memory."""
        self._send(f"x/1w 0x{address:08X}")
        output = self._wait_for_prompt()
        for line in output.split("\n"):
            if "0x" in line and ":" in line:
                try:
                    val = line.split(":")[-1].strip().split()[0]
                    return int(val, 16)
                except ValueError:
                    pass
        return None

    def write_memory_word(self, address, value):
        """Write a 32-bit word to memory."""
        print(f"[DBG] Writing memory 0x{address:08X} = 0x{value:08X}")
        self._send(f"set {{int}}0x{address:08X} = 0x{value:08X}")
        self._wait_for_prompt()

    def inject_memory_fault(self, address, bit):
        """
        Inject a single-bit fault into a memory word.
        Simulates an SEU in IMEM or DMEM.

        Args:
            address: 32-bit memory address
            bit:     bit to flip (0-31)
        """
        mask = 1 << bit
        current = self.read_memory_word(address)
        if current is not None:
            new_val = current ^ mask
            print(f"[DBG] Memory fault at 0x{address:08X}: "
                  f"0x{current:08X} → 0x{new_val:08X} (bit {bit} flipped)")
            self.write_memory_word(address, new_val)

    # -------------------------------------------------------------------------
    # SEU experiment helpers
    # -------------------------------------------------------------------------

    def capture_cpu_state(self):
        """
        Capture a complete snapshot of CPU state.
        Call before fault injection to establish a baseline,
        and after resuming to detect state corruption.
        """
        state = {
            "registers": self.read_all_registers(),
            "mcause":    self.read_csr("mcause"),
            "mepc":      self.read_csr("mepc"),
            "mtval":     self.read_csr("mtval"),
            "mstatus":   self.read_csr("mstatus"),
            "mcycle":    self.read_csr("mcycle"),
        }
        return state

    def print_cpu_state(self, state, label="CPU State"):
        """Pretty-print a captured CPU state."""
        print(f"\n{'='*60}")
        print(f" {label}")
        print(f"{'='*60}")
        regs = state.get("registers", {})
        print(f"  PC      = 0x{regs.get('pc',  0):08X}")
        print(f"  SP      = 0x{regs.get('sp',  0):08X}")
        print(f"  RA      = 0x{regs.get('ra',  0):08X}")
        print(f"  A0      = 0x{regs.get('a0',  0):08X}")
        print(f"  T0      = 0x{regs.get('t0',  0):08X}")
        print(f"  mcause  = 0x{state.get('mcause', 0):08X}  "
              f"({'no trap' if state.get('mcause', 0) == 0 else 'TRAP FIRED'})")
        print(f"  mepc    = 0x{state.get('mepc',   0):08X}")
        print(f"  mtval   = 0x{state.get('mtval',  0):08X}")
        print(f"  mcycle  = {state.get('mcycle', 0)}")
        print(f"{'='*60}\n")

    def run_fault_injection_sweep(self, register, num_bits=32):
        """
        Systematically inject single-bit faults into every bit of a register
        and record whether each fault caused a trap.

        This is the core of systematic SEU validation.
        Returns a list of (bit, caused_trap, mcause) tuples.

        Args:
            register:  register name e.g. 't0'
            num_bits:  number of bits to test (default 32)
        """
        results = []
        print(f"\n[SEU SWEEP] Testing all {num_bits} bits of ${register}")
        print("-" * 60)

        for bit in range(num_bits):
            # Reset to clean state
            self.reset_and_halt()
            self.load_program()
            self.run_to_function("main")

            # Inject fault
            self.inject_register_fault(register, bit)

            # Resume briefly
            self.resume()
            time.sleep(0.05)
            self.halt()

            # Check for trap
            mcause = self.read_csr("mcause") or 0
            caused_trap = (mcause != 0)
            results.append((bit, caused_trap, mcause))

            status = f"TRAP(0x{mcause:08X})" if caused_trap else "no trap"
            print(f"  bit {bit:2d}: {status}")

        # Print summary
        trap_count = sum(1 for _, t, _ in results if t)
        print(f"\n[SEU SWEEP] Results: {trap_count}/{num_bits} bits caused traps")
        print(f"  Bits causing traps: "
              f"{[b for b, t, _ in results if t]}")
        return results

    # -------------------------------------------------------------------------
    # Internal GDB communication
    # -------------------------------------------------------------------------

    def _send(self, command):
        """Send a command to GDB."""
        if self.process and self.process.stdin:
            self.process.stdin.write(command + "\n")
            self.process.stdin.flush()

    def _wait_for_prompt(self, timeout=10.0):
        """Wait for GDB to finish processing and return output."""
        output = ""
        start  = time.time()
        while time.time() - start < timeout:
            line = self.process.stdout.readline()
            output += line
            if "(gdb)" in line or "^done" in line or "^error" in line:
                break
        return output

    def close(self):
        """Clean up the GDB session."""
        if self.process:
            self._send("quit")
            self.process.terminate()
            print("[DBG] GDB session closed")


# =============================================================================
# PART 4 — EXAMPLE AUTOMATED EXPERIMENT
# Demonstrates a complete fault injection experiment.
# =============================================================================

def run_example_experiment():
    """
    Example: inject faults into register t0 while hello_world runs
    and check if they cause unexpected traps.

    Adapt this function for your specific mitigation under test.
    """

    print("=" * 60)
    print(" NEORV32 SEU Fault Injection Experiment")
    print("=" * 60)
    print(f" Target ELF:  {ELF_FILE}")
    print(f" OpenOCD:     {OPENOCD_HOST}:{OPENOCD_PORT}")
    print()

    dbg = NEORV32Debugger(ELF_FILE)

    try:
        # --- Connect ---
        dbg.connect()
        dbg.reset_and_halt()
        dbg.load_program()

        # --- Capture baseline state ---
        dbg.run_to_function("main")
        baseline = dbg.capture_cpu_state()
        dbg.print_cpu_state(baseline, "BASELINE STATE (before fault injection)")

        # --- Single fault injection test ---
        print("[EXP] Injecting single-bit fault into t0 (bit 7)...")
        dbg.inject_register_fault("t0", bit=7)
        dbg.resume()
        time.sleep(0.1)
        dbg.halt()

        post_fault = dbg.capture_cpu_state()
        dbg.print_cpu_state(post_fault, "POST-FAULT STATE")

        # Evaluate result
        mcause = post_fault.get("mcause", 0)
        if mcause == 0:
            print("[RESULT] PASS — No trap. Mitigation corrected the fault.")
        else:
            print(f"[RESULT] FAIL — Trap fired. mcause=0x{mcause:08X}")
            print("         Mitigation did not prevent the fault.")

        # --- Full bit sweep (uncomment to run all 32 bits) ---
        # results = dbg.run_fault_injection_sweep("t0", num_bits=32)

    except Exception as e:
        print(f"[ERROR] {e}")
        raise

    finally:
        dbg.close()


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    # Print the interactive session guide so it is visible
    print(INTERACTIVE_SESSION_GUIDE)
    print(OPENOCD_CONFIG_NOTES)

    # Uncomment to run the automated experiment:
    # run_example_experiment()
