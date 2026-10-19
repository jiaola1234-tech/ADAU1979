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

static void adau1979_print_debug_log(void)
{
    u32 status = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_DEBUG_STATUS_OFFSET);
    u32 count = (status >> 26) & 0x3fu;
    u32 i;

    xil_printf("DEBUG_STATUS=0x%08x LOG_COUNT=%d\r\n",
               (unsigned int)status, (unsigned int)count);
    xil_printf("\r\n===== ADAU1979 DEBUG LOG (%d entries) =====\r\n",
               (unsigned int)count);
    for (i = 0u; i < count; i++) {
        u32 lo, hi;
        u32 index_readback;
        u32 type, step, dev, reg, data, ack, err, lock, poll;

        ADAU1979_CAPTURE_mWriteReg(ADAU1979_CAPTURE_BASEADDR,
                                   ADAU1979_CAPTURE_DEBUG_INDEX_OFFSET, i);
        index_readback = ADAU1979_CAPTURE_mReadReg(
            ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_DEBUG_INDEX_OFFSET);
        lo = ADAU1979_CAPTURE_mReadReg(
            ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_DEBUG_DATA_LOW_OFFSET);
        hi = ADAU1979_CAPTURE_mReadReg(
            ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_DEBUG_DATA_HIGH_OFFSET);
        if ((index_readback & 0x3fu) != i) {
            xil_printf("TRACE_INDEX_MISMATCH req=%d got=%d\r\n",
                       (unsigned int)i,
                       (unsigned int)(index_readback & 0x3fu));
        }

        type = (hi >> 28) & 0xfu;
        step = (hi >> 20) & 0xffu;
        dev  = (hi >> 13) & 0x7fu;
        reg  = (hi >> 5) & 0xffu;
        data = ((hi & 0x1fu) << 3) | ((lo >> 29) & 0x7u);
        ack  = (lo >> 26) & 0x7u;
        err  = (lo >> 25) & 0x1u;
        lock = (lo >> 24) & 0x1u;
        poll = (lo >> 16) & 0xffu;
        xil_printf("TRACE[%d] raw_hi=%08x raw_lo=%08x type=%d\r\n",
                   (unsigned int)i, (unsigned int)hi, (unsigned int)lo,
                   (unsigned int)type);

        if (type == 0u) {
            xil_printf("W step=%02x dev=%02x reg=%02x data=%02x ack=%d%d%d err=%d\r\n",
                       (unsigned int)step, (unsigned int)dev,
                       (unsigned int)reg, (unsigned int)data,
                       (unsigned int)((ack >> 2) & 1u),
                       (unsigned int)((ack >> 1) & 1u),
                       (unsigned int)(ack & 1u), (unsigned int)err);
        } else if (type == 1u) {
            xil_printf("PLL dev=%02x data=%02x lock=%d err=%d poll=%d\r\n",
                       (unsigned int)dev, (unsigned int)data,
                       (unsigned int)lock, (unsigned int)err,
                       (unsigned int)poll);
        } else if (type == 3u) {
            xil_printf("SCAN dev=%02x reg=%02x data=%02x ack=%s err=%d\r\n",
                       (unsigned int)dev, (unsigned int)reg,
                       (unsigned int)data, err ? "NACK" : "ACK",
                       (unsigned int)err);
        } else if (type == 4u) {
            xil_printf("VERIFY dev=%02x reg=%02x addr_ack=%d data_valid=%d data=%02x err=%d\r\n",
                       (unsigned int)dev, (unsigned int)reg,
                       (unsigned int)((ack >> 1) & 1u),
                       (unsigned int)((ack >> 2) & 1u),
                       (unsigned int)data, (unsigned int)err);
        } else if (type == 2u) {
            xil_printf("INIT DONE errors=%02x result=%s\r\n",
                       (unsigned int)data, lock ? "PASS" : "FAIL");
        }
    }
}
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
    u32 verify_info = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_VERIFY_INFO_OFFSET);
    u32 verify_data = ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_DEBUG_STATUS_OFFSET);
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
    xil_printf("VERIFY_INFO=0x%08x VERIFY_EXPECT=0x%02x VERIFY_ACTUAL=0x%02x\r\n",
               (unsigned int)verify_info,
               (unsigned int)(verify_data & 0xffu),
               (unsigned int)((verify_data >> 8) & 0xffu));
}

static int wait_adau1979_init_done(void)
{
    u32 timeout = INIT_TIMEOUT_LOOPS;
    int seen_busy = 0;

    while (timeout-- != 0u) {
        u32 status = ADAU1979_CAPTURE_mReadReg(ADAU1979_CAPTURE_BASEADDR,
                                               ADAU1979_CAPTURE_STATUS_OFFSET);

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_BUSY) != 0u)
            seen_busy = 1;

        /* U1 may fail while PL is deliberately continuing with U2.  Do not
         * stop or dump the trace until the complete diagnostic run ends. */
        if (seen_busy &&
            (status & ADAU1979_CAPTURE_STATUS_INIT_BUSY) == 0u &&
            (status & ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u) {
            xil_printf("ADAU1979 init error\r\n");
            print_init_diagnostics(status);
            adau1979_print_debug_log();
            return XST_FAILURE;
        }

        if (seen_busy &&
            (status & ADAU1979_CAPTURE_STATUS_INIT_BUSY) == 0u &&
            (status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u) {
            xil_printf("ADAU1979 init done\r\n");
            print_init_diagnostics(status);
            adau1979_print_debug_log();
            return XST_SUCCESS;
        }
    }

    xil_printf("ADAU1979 init timeout\r\n");
    print_init_diagnostics(ADAU1979_CAPTURE_mReadReg(
        ADAU1979_CAPTURE_BASEADDR, ADAU1979_CAPTURE_STATUS_OFFSET));
    adau1979_print_debug_log();
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
    xil_printf("DIAG_BUILD=PL-I2C-U1-FIRST-ACK-CHECK\r\n");
    xil_printf("CONFIG_MODE=PL_I2C_ACK_CHECK_NO_READBACK_COMPARE\r\n");
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
