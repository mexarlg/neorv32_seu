// ============================================================================
// scrub_test.c - DMEM Background Scrubber
// ----------------------------------------------------------------------------
// Purpose:
//   Validate on real hardware that the scrubber does NOT corrupt good data.
//
// How it works:
//   1. A large initialized global array (test_block) is placed in .data.
//      crt0 fills it with known values before main() runs, so every word
//      is already a valid SECDED codeword by the time the scrubber starts.
//   2. The program prints a banner, then loops forever re-checking that
//      every word of test_block still holds its expected value.
//   3. You enable the scrubber (VIO click) AFTER the banner appears.
//   4. If the scrubber is sound, the check stays green forever.
//      If the scrubber corrupts a word, the mismatch is printed over UART.
//
// ============================================================================

#include <stdint.h>
#include "neorv32.h"

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
#define BAUD_RATE      19200
#define TEST_WORDS     512          // size of the test region, in 32-bit words
#define EXPECTED(i)    (0xA5A50000u + (uint32_t)(i))   // known value per word

volatile uint32_t test_block[TEST_WORDS];

// ----------------------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------------------
void fill_test_block(void)
{
    for (int i = 0; i < TEST_WORDS; i++) {
        test_block[i] = EXPECTED(i);
    }
}

int verify_test_block(void)
{
    int errors = 0;

    for (int i = 0; i < TEST_WORDS; i++) {
        uint32_t got = test_block[i];
        uint32_t exp = EXPECTED(i);
        if (got != exp) {
            errors++;
            neorv32_uart0_printf("MISMATCH word %u  addr 0x%x  got 0x%x  exp 0x%x\n",
                                 (uint32_t)i,
                                 (uint32_t)&test_block[i],
                                 got, exp);
        }
    }
    return errors;
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
                         base, (base - 0x80000000u) / 4u);
    neorv32_uart0_printf("  end   addr 0x%x  (word index %u)\n",
                         end, (end - 0x80000000u) / 4u);

    // Sanity check before the scrubber is enabled
    int initial = verify_test_block();
    if (initial == 0) {
        neorv32_uart0_printf("Initial check OK - all %u words correct.\n",
                             (uint32_t)TEST_WORDS);
    } else {
        neorv32_uart0_printf("WARNING: %d words wrong BEFORE scrubber - "
                             "check crt0 / .data init.\n", initial);
    }

    neorv32_uart0_printf("Enable scrubber (VIO). Monitoring...\n");

    // ------------------------------------------------------------------------
    // Continuous no harm monitoring loop.
    // Prints a heartbeat every pass so a silent UART means the program hung
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

        // small delay so the UART is readable
        for (volatile int d = 0; d < 200000; d++) { }
    }

    return 0;
}