// ============================================================================
// main.c - DMEM Background Scrubber - SEU injection validation
// ----------------------------------------------------------------------------
// Purpose:
//   Prepare memory for deterministic SEU injection (via VIO on port B) and
//   watch the scrubber detect / correct the injected errors
//
// How it works:
//   1. test_block is filled with a single constant value. Every word becomes
//      a valid SECDED codeword (the encoder runs on each CPU write).
//   2. The scrubber is enabled. The loop only verifies and prints status
//   3. You inject an SEU via VIO. The scrubber finds the mismatch 
//      on its next pass: (1 bit fixed, 2 bit detected)
//
// Injection values:
//   FILL_VALUE = 0xA5A5A5A5
//   1-bit SEU (flip bit 0)  : inject_data = 0xA5A5A5A4
//   2-bit SEU (flip bits 0,1): inject_data = 0xA5A5A5A6
//   inject_word_addr = WORD INDEX
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
#define FILL_VALUE     0xA5A5A5A5u  // constant value written to every word

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

// ----------------------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------------------

// Fill every word with the constant value
void fill_test_block(void)
{
    for (int i = 0; i < TEST_WORDS; i++) {
        test_block[i] = FILL_VALUE;
    }
}

// Check every word still holds the constant value. A mismatch means a SEU
int verify_test_block(void)
{
    int errors = 0;

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t got = test_block[i];
        if (got != FILL_VALUE) {
            errors++;
            neorv32_uart0_printf("MISMATCH word %u  addr 0x%x  got 0x%x  exp 0x%x\n",
                                 (uint32_t)i,
                                 (uint32_t)&test_block[i],
                                 got, (uint32_t)FILL_VALUE);
        }
    }
    return errors;
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
    neorv32_uart0_printf("=== Scrubber SEU injection test ===\n");

    // Fill the test memory with the constant value
    fill_test_block();

    // Report the region so it can be cross checked against the scrubber range
    uint32_t base = (uint32_t)&test_block[0];
    uint32_t end  = (uint32_t)&test_block[TEST_WORDS - 1];
    neorv32_uart0_printf("test_block: %u words, fill 0x%x\n",
                         (uint32_t)TEST_WORDS, (uint32_t)FILL_VALUE);
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
    neorv32_uart0_printf("Scrubber enabled. Inject SEUs via VIO. Monitoring...\n");

    // ------------------------------------------------------------------------
    // Monitoring loop: verify and print status only.
    // ------------------------------------------------------------------------
    uint32_t pass = 0;

    while (1) {
        int errors = verify_test_block();
        pass++;

        if (errors == 0) {
            neorv32_uart0_printf("pass %u: OK\n", pass);
        } else {
            neorv32_uart0_printf("pass %u: %d word(s) currently corrupted\n",
                                 pass, errors);
        }

        // Read and print the scrubber status registers
        print_scrub_status();

        // Clear status reg
        SCRUB_CTRL = CTRL_STATUS_CLEAR;

        // delay 200ms so the UART output is readable
        neorv32_aux_delay_ms(NEORV32_SYSINFO->CLK, 200);
    }

    return 0;
}