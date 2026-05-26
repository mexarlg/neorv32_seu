// ============================================================================
// main.c - DMEM Background Scrubber
// ----------------------------------------------------------------------------
// Purpose:
//   Validates on hardware that the scrubber does not corrupt good data,
//   exercise the conflict logic with CPU writes, and drive / read the
//   scrubber through its memory mapped registers (or through VIO)
//
// How it works:
//   1. test_block is an initialized .data array - valid SECDED codewords
//      after crt0, so the scrubber can run over it safely.
//   2. The program enables the scrubber via the CTRL register, then loops:
//      verifies the region, does a CPU write burst, and prints status
//
// Register block: top 4 words of the DMEM address space.
//   CTRL   : bit0 = scrub_en, bit1 = flog_clear, bit2 = status_clear
//   STATUS : bit0 = corrected, bit1 = detected, bit2 = full_pass,
//            bit3 = busy, bits[6:4] = state
//   FLOG   : bits[7:0] = flog_count, bit8 = overflow
//   FADDR  : flog_last_addr
// ============================================================================

#include <stdint.h>
#include "neorv32.h"

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
#define BAUD_RATE      19200
#define TEST_WORDS     512          // size of the test region, in 32-bit words
#define CONFLICT_HITS  64           // CPU writes per conflict burst

#define DMEM_BASE      0x80000000u
#define DMEM_SIZE      (32u * 1024u)            // 32 KB DMEM

// Scrubber register block: top 4 words of DMEM
#define SCRUB_REG_BASE (DMEM_BASE + DMEM_SIZE - 16u)
#define SCRUB_CTRL     (*(volatile uint32_t*)(SCRUB_REG_BASE + 0x0u))
#define SCRUB_STATUS   (*(volatile uint32_t*)(SCRUB_REG_BASE + 0x4u))
#define SCRUB_FLOG     (*(volatile uint32_t*)(SCRUB_REG_BASE + 0x8u))
#define SCRUB_FADDR    (*(volatile uint32_t*)(SCRUB_REG_BASE + 0xCu))

// CTRL register bits
#define CTRL_SCRUB_EN     (1u << 0)
#define CTRL_FLOG_CLEAR   (1u << 1)
#define CTRL_STATUS_CLEAR (1u << 2)

// STATUS register bit fields
#define ST_CORRECTED   (1u << 0)
#define ST_DETECTED    (1u << 1)
#define ST_FULL_PASS   (1u << 2)
#define ST_BUSY        (1u << 3)
#define ST_STATE(s)    (((s) >> 4) & 0x7u)

// FLOG register bit fields
#define FLOG_COUNT(f)  ((f) & 0xFFu)
#define FLOG_OVF(f)    (((f) >> 8) & 0x1u)

volatile uint32_t test_block[TEST_WORDS];   // memory under test (real DMEM)
uint32_t expected[TEST_WORDS];              // software mirror of expected values

// ----------------------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------------------

// Iterates through all words to write, same with mirror memory
void fill_test_block(void)
{
    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t v = 0xA5A50000u + (uint32_t)i;
        test_block[i] = v;
        expected[i]   = v;          // keep mirror in sync
    }
}

// Iterates through all words checking word in memory is same as mirror word
int verify_test_block(void)
{
    int errors = 0;

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t got = test_block[i];
        if (got != expected[i]) {
            errors++;
            neorv32_uart0_printf("MISMATCH word %u  addr 0x%x  got 0x%x  exp 0x%x\n",
                                 (uint32_t)i,
                                 (uint32_t)&test_block[i],
                                 got, expected[i]);
        }
    }
    return errors;
}

// CPU write burst into the scrubber - creates conflicts.
void cpu_write_burst(uint32_t seed)
{
    for (int k = 0; k < CONFLICT_HITS; k++) {
        int i = (int)((seed + (uint32_t)k) % TEST_WORDS);
        uint32_t v = 0xC0FFEE00u + seed + (uint32_t)k;
        test_block[i] = v;          // real CPU write -> DMEM port A
        expected[i]   = v;          // keep mirror in sync
    }
}

// Read and print the scrubber status / fault log registers.
void print_scrub_status(void)
{
    uint32_t st = SCRUB_STATUS;
    uint32_t fl = SCRUB_FLOG;

    neorv32_uart0_printf("  [scrub] state=%u busy=%u corrected=%u detected=%u "
                         "full_pass=%u\n",
                         ST_STATE(st),
                         (st & ST_BUSY)      ? 1u : 0u,
                         (st & ST_CORRECTED) ? 1u : 0u,
                         (st & ST_DETECTED)  ? 1u : 0u,
                         (st & ST_FULL_PASS) ? 1u : 0u);

    neorv32_uart0_printf("  [scrub] flog_count=%u overflow=%u last_addr=0x%x\n",
                         FLOG_COUNT(fl), FLOG_OVF(fl), SCRUB_FADDR);
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
int main(void)
{
    // Set up UART0
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_printf("\n");
    neorv32_uart0_printf("=== Scrubber test ===\n");

    // Fill the test memory with the known pattern
    fill_test_block();

    // Report the region so it can be cross checked against the scrubber range
    uint32_t base = (uint32_t)&test_block[0];
    uint32_t end  = (uint32_t)&test_block[TEST_WORDS - 1];
    neorv32_uart0_printf("test_block: %u words\n", (uint32_t)TEST_WORDS);
    neorv32_uart0_printf("  start addr 0x%x  (word index %u)\n",
                         base, (base - DMEM_BASE) / 4u);
    neorv32_uart0_printf("  end   addr 0x%x  (word index %u)\n",
                         end, (end - DMEM_BASE) / 4u);
    neorv32_uart0_printf("scrub registers at 0x%x\n", (uint32_t)SCRUB_REG_BASE);

    // Sanity check before the scrubber is enabled
    int initial = verify_test_block();
    if (initial == 0) {
        neorv32_uart0_printf("Initial check OK - all %u words correct.\n",
                             (uint32_t)TEST_WORDS);
    } else {
        neorv32_uart0_printf("WARNING: %d words wrong BEFORE scrubber.\n", initial);
    }

    // Clear the fault log and any stale sticky flags, then enable the scrubber
    SCRUB_CTRL = CTRL_FLOG_CLEAR | CTRL_STATUS_CLEAR;
    SCRUB_CTRL = CTRL_SCRUB_EN;
    neorv32_uart0_printf("Scrubber enabled via CTRL register. Monitoring...\n");

    // ------------------------------------------------------------------------
    // Monitoring loop: verify, CPU write burst, print scrubber status.
    // ------------------------------------------------------------------------
    uint32_t pass = 0;

    while (1) {
        int errors = verify_test_block();
        pass++;

        if (errors == 0) {
            neorv32_uart0_printf("pass %u: OK\n", pass);
        } else {
            neorv32_uart0_printf("pass %u: %d MISMATCH(es) - "
                                 "scrubber corrupted data!\n", pass, errors);
        }

        // CPU write burst -> collides with the scrubber
        cpu_write_burst(pass);

        // Read and print the scrubber status registers
        print_scrub_status();

        // Clear the event flags so next pass shows fresh events
        SCRUB_CTRL = CTRL_SCRUB_EN | CTRL_STATUS_CLEAR;

        // delay 200ms so the UART output is readable
        neorv32_aux_delay_ms(NEORV32_SYSINFO->CLK, 200);
    }

    return 0;
}