/*
 * Bare-metal Vitis smoke test for the ADAU1979 capture IP.
 *
 * Flow:
 * 1. Initialize AXI DMA in simple S2MM mode.
 * 2. Wait for PL-I2C ADAU1979 initialization to finish.
 * 3. Arm DMA receive.
 * 4. Start the ADAU1979 capture IP.
 * 5. Print the first captured 8-channel frames.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"
#include "adau1979_capture.h"

#ifndef DMA_DEV_ID
#define DMA_DEV_ID XPAR_AXIDMA_0_DEVICE_ID
#endif

#ifndef ADAU1979_CAPTURE_BASEADDR
#if defined(XPAR_ADAU1979_CAPTURE_0_C_S00_AXI_BASEADDR)
#define ADAU1979_CAPTURE_BASEADDR XPAR_ADAU1979_CAPTURE_0_C_S00_AXI_BASEADDR
#elif defined(XPAR_ADAU1979_CAPTURE_0_BASEADDR)
#define ADAU1979_CAPTURE_BASEADDR XPAR_ADAU1979_CAPTURE_0_BASEADDR
#else
#error "ADAU1979 capture IP base-address macro is missing from xparameters.h"
#endif
#endif

#define CAPTURE_FRAMES       1024u
#define WORDS_PER_FRAME      8u
#define BYTES_PER_FRAME      32u
#define DMA_RX_BYTES         (CAPTURE_FRAMES * BYTES_PER_FRAME)
#define INIT_TIMEOUT_LOOPS   5000000u
#define DMA_TIMEOUT_LOOPS    50000000u

static XAxiDma AxiDma;
static u32 RxBuffer[CAPTURE_FRAMES * WORDS_PER_FRAME] __attribute__((aligned(64)));

static void print_init_diagnostics(u32 status)
{
    u32 error_count = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_ERROR_COUNT_OFFSET);
    u32 i2s_frames = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_I2S_FRAMES_OFFSET);
    u32 fifo_level = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET);
    u32 fifo_overflow = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_FIFO_OVF_OFFSET);
    u32 last_dev = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_I2C_LAST_DEV_OFFSET);
    u32 last_regdata = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_I2C_LAST_REGDATA_OFFSET);
    u32 ack_bits = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_I2C_ACK_BITS_OFFSET);
    unsigned int init_step = (unsigned int)((status >> 8) & 0xffu);

    xil_printf("STATUS=0x%08x step=%d busy=%d done=%d error=%d\r\n",
               (unsigned int)status,
               init_step,
               (status & ADAU1979_CAPTURE_STATUS_INIT_BUSY) != 0u,
               (status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u,
               (status & ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u);
    xil_printf("ERROR_COUNT=%d\r\n", (unsigned int)error_count);
    xil_printf("I2S_FRAME_COUNT=%d FIFO_LEVEL=%d FIFO_OVERFLOW=%d\r\n",
               (unsigned int)i2s_frames,
               (unsigned int)fifo_level,
               (unsigned int)fifo_overflow);
    xil_printf("I2C_LAST_DEV=0x%02x I2C_LAST_REG=0x%02x I2C_LAST_DATA=0x%02x ACK_BITS=%d\r\n",
               (unsigned int)(last_dev & 0x7fu),
               (unsigned int)((last_regdata >> 8) & 0xffu),
               (unsigned int)(last_regdata & 0xffu),
               (unsigned int)(ack_bits & 0x7u));
}

static int wait_adau1979_init_done(void)
{
    u32 timeout = INIT_TIMEOUT_LOOPS;

    while (timeout-- != 0u) {
        u32 status = ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                               ADAU1979_CAPTURE_STATUS_OFFSET);

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u) {
            xil_printf("ADAU1979 init error\r\n");
            print_init_diagnostics(status);
            return XST_FAILURE;
        }

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u) {
            xil_printf("ADAU1979 init done\r\n");
            print_init_diagnostics(status);
            return XST_SUCCESS;
        }
    }

    xil_printf("ADAU1979 init timeout\r\n");
    print_init_diagnostics(ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_STATUS_OFFSET));
    return XST_FAILURE;
}

static int init_dma(void)
{
    XAxiDma_Config *cfg;

    xil_printf("DMA_INIT_BEGIN\r\n");
    cfg = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (cfg == NULL) {
        xil_printf("No AXI DMA config found\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_CfgInitialize(&AxiDma, cfg) != XST_SUCCESS) {
        xil_printf("AXI DMA init failed\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("AXI DMA must be configured in simple mode\r\n");
        return XST_FAILURE;
    }

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    xil_printf("DMA_INIT_DONE\r\n");
    return XST_SUCCESS;
}

/*
 * Keep the processor alive long enough to arm the Vivado ILA.  The PL
 * initialization normally starts when the FPGA is configured, which is
 * before the Vitis application is running.  Waiting for an explicit UART
 * command lets Hardware Manager arm first, then produces a fresh I2C
 * transaction on demand.
 */
static void wait_for_ila_reinit(void)
{
    char c;

    do {
        c = inbyte();
    } while (c != 'r' && c != 'R');

    ADAU1979_CAPTURE_Reinit(ADAU1979_CAPTURE_BASEADDR);
    xil_printf("ADAU1979 reinit requested\r\n");
}

static void print_frames(u32 frame_count)
{
    u32 f;

    for (f = 0u; f < frame_count; f++) {
        u32 *p = &RxBuffer[f * WORDS_PER_FRAME];
        xil_printf("F%d: %08x %08x %08x %08x %08x %08x %08x %08x\r\n",
                   (unsigned int)f,
                   (unsigned int)p[0], (unsigned int)p[1],
                   (unsigned int)p[2], (unsigned int)p[3],
                   (unsigned int)p[4], (unsigned int)p[5],
                   (unsigned int)p[6], (unsigned int)p[7]);
    }
}

int main(void)
{
    u32 timeout;
    int status;

    /* Keep the first line human-readable for a serial-terminal smoke test. */
    xil_printf("HelloWorld\r\n");
    xil_printf("ADAU1979 capture DMA test\r\n");
    xil_printf("UART: 921600 8N1 (PS UART1)\r\n");
    xil_printf("DIAG_BUILD=20260913-ILA\r\n");
    xil_printf("READY: Arm ILA, then send 'r' to reinitialize ADAU1979\r\n");

    xil_printf("IP base=0x%08x, CTRL=0x%08x, STATUS=0x%08x\r\n",
               (unsigned int)ADAU1979_CAPTURE_BASEADDR,
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_CONTROL_OFFSET),
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_STATUS_OFFSET));

    status = init_dma();
    if (status != XST_SUCCESS)
        return XST_FAILURE;

    wait_for_ila_reinit();

    status = wait_adau1979_init_done();
    if (status != XST_SUCCESS)
        return XST_FAILURE;

    xil_printf("Init flags: DONE=%d ERROR=%d\r\n",
               (ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                           ADAU1979_CAPTURE_STATUS_OFFSET) &
                ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u,
               (ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                           ADAU1979_CAPTURE_STATUS_OFFSET) &
                ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u);

    Xil_DCacheFlushRange((UINTPTR)RxBuffer, DMA_RX_BYTES);

    status = XAxiDma_SimpleTransfer(&AxiDma,
                                    (UINTPTR)RxBuffer,
                                    DMA_RX_BYTES,
                                    XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: Start S2MM transfer failed, code=%d\r\n", status);
        return XST_FAILURE;
    }

    ADAU1979_CAPTURE_SetSampleLen(ADAU1979_CAPTURE_BASEADDR, CAPTURE_FRAMES);
    ADAU1979_CAPTURE_Start(ADAU1979_CAPTURE_BASEADDR);

    timeout = DMA_TIMEOUT_LOOPS;
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA) && timeout-- != 0u) {
    }

    if (timeout == 0u) {
        u32 st = ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                           ADAU1979_CAPTURE_STATUS_OFFSET);
        u32 err = ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                            ADAU1979_CAPTURE_ERROR_COUNT_OFFSET);
        xil_printf("ERROR: DMA timeout, status=0x%08x, err=%d, fifo_level=%d, fifo_ovf=%d\r\n",
                   (unsigned int)st, (unsigned int)err,
                   (unsigned int)ADAU1979_CAPTURE_mReadReg(
                       ADAU1979_CAPTURE_BASEADDR,
                       ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET),
                   (unsigned int)ADAU1979_CAPTURE_mReadReg(
                       ADAU1979_CAPTURE_BASEADDR,
                       ADAU1979_CAPTURE_FIFO_OVF_OFFSET));
        return XST_FAILURE;
    }

    Xil_DCacheInvalidateRange((UINTPTR)RxBuffer, DMA_RX_BYTES);

    xil_printf("Capture finished\r\n");
    xil_printf("I2S frames: %d\r\n",
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_I2S_FRAMES_OFFSET));
    xil_printf("DMA frames: %d\r\n",
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_DMA_FRAMES_OFFSET));
    xil_printf("FIFO ovf  : %d\r\n",
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_FIFO_OVF_OFFSET));
    xil_printf("Errors    : %d\r\n",
               (unsigned int)ADAU1979_CAPTURE_mReadReg(
                   ADAU1979_CAPTURE_BASEADDR,
                   ADAU1979_CAPTURE_ERROR_COUNT_OFFSET));

    print_frames(8u);
    return XST_SUCCESS;
}
