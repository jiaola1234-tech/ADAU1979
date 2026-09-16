/*
 * AX7020 bare-metal UART-only smoke test.
 *
 * This program intentionally does not access ADAU1979, AXI DMA, or any
 * programmable-logic register. It verifies only CPU execution and the
 * board's PS UART1 -> CP2102 -> PC serial path.
 */

#include "sleep.h"
#include "xil_printf.h"
#include "xil_types.h"

int main(void)
{
    u32 count = 0u;

    xil_printf("HelloWorld\r\n");
    xil_printf("UART-only test started\r\n");
    xil_printf("ADAU1979: disconnected / not accessed\r\n");
    xil_printf("AXI DMA: not accessed\r\n");
    xil_printf("RESULT: UART startup PASS\r\n");

    for (;;) {
        xil_printf("UART heartbeat: %u\r\n", (unsigned int)count);
        count++;
        sleep(1u);
    }
}
