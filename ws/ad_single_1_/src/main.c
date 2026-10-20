/*
 * Bare-metal application for the single ADAU1979 design.
 *
 * The PL performs the ADAU1979 initialization at fixed 7-bit I2C address
 * 0x11.  The application only waits for that status, arms AXI DMA S2MM,
 * starts the capture, and inspects the 32-byte DDR frame layout:
 *
 *   word 0: SDATAOUT11 left slot
 *   word 1: SDATAOUT11 right slot
 *   word 2: SDATAOUT12 left slot
 *   word 3: SDATAOUT12 right slot
 *   word 4..7: zero padding to retain the original 256-bit DMA frame
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"
#include "sleep.h"

#include "adau1979_capture.h"

#ifndef XPAR_ADAU1979_CAPTURE_0_BASEADDR
#error "The exported platform is missing XPAR_ADAU1979_CAPTURE_0_BASEADDR"
#endif

#ifndef XPAR_AXI_DMA_0_DEVICE_ID
#error "The exported platform is missing XPAR_AXI_DMA_0_DEVICE_ID"
#endif

#define ADAU1979_BASEADDR       XPAR_ADAU1979_CAPTURE_0_BASEADDR
#define DMA_DEVICE_ID           XPAR_AXI_DMA_0_DEVICE_ID

#define CAPTURE_FRAMES          1024u
#define WORDS_PER_FRAME         8u
#define BYTES_PER_FRAME         32u
#define DMA_BYTES               (CAPTURE_FRAMES * BYTES_PER_FRAME*2)
#define INIT_TIMEOUT_MS         5000u
#define DMA_TIMEOUT_MS          10000u
#define PRINT_FRAMES            8u

static XAxiDma AxiDma;
static u32 RxBuffer[CAPTURE_FRAMES * WORDS_PER_FRAME]
    __attribute__((aligned(64)));

static void print_ip_status(const char *tag)
{
    u32 status = adau1979_read(ADAU1979_BASEADDR,
                               ADAU1979_CAPTURE_STATUS_OFFSET);
    u32 i2s_frames = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_I2S_FRAMES_OFFSET);
    u32 dma_frames = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_DMA_FRAMES_OFFSET);
    u32 fifo_level = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET);
    u32 fifo_ovf = adau1979_read(ADAU1979_BASEADDR,
                                 ADAU1979_CAPTURE_FIFO_OVF_OFFSET);
    u32 errors = adau1979_read(ADAU1979_BASEADDR,
                               ADAU1979_CAPTURE_ERROR_COUNT_OFFSET);

    xil_printf("%s status=0x%08x i2s=%u dma=%u fifo=%u ovf=%u err=%u\r\n",
               tag, (unsigned int)status, (unsigned int)i2s_frames,
               (unsigned int)dma_frames, (unsigned int)fifo_level,
               (unsigned int)fifo_ovf, (unsigned int)errors);
}

static int wait_for_init(void)
{
    u32 elapsed;

    for (elapsed = 0u; elapsed < INIT_TIMEOUT_MS; ++elapsed) {
        u32 status = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_STATUS_OFFSET);

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u) {
            xil_printf("ADAU1979 init failed: status=0x%08x last_dev=0x%02x "
                       "last_reg_data=0x%08x ack=0x%02x\r\n",
                       (unsigned int)status,
                       (unsigned int)adau1979_read(
                           ADAU1979_BASEADDR,
                           ADAU1979_CAPTURE_I2C_LAST_DEV_OFFSET),
                       (unsigned int)adau1979_read(
                           ADAU1979_BASEADDR,
                           ADAU1979_CAPTURE_I2C_LAST_REGDATA_OFFSET),
                       (unsigned int)adau1979_read(
                           ADAU1979_BASEADDR,
                           ADAU1979_CAPTURE_I2C_ACK_BITS_OFFSET));
            return XST_FAILURE;
        }

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u) {
            xil_printf("ADAU1979 init done (7-bit I2C address 0x11)\r\n");
            return XST_SUCCESS;
        }

        usleep(1000u);
    }

    xil_printf("ADAU1979 init timeout\r\n");
    print_ip_status("init-timeout");
    return XST_FAILURE;
}

static int init_dma(void)
{
    XAxiDma_Config *config = XAxiDma_LookupConfig(DMA_DEVICE_ID);
    u32 reset_wait;

    if (config == NULL) {
        xil_printf("AXI DMA configuration not found\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_CfgInitialize(&AxiDma, config) != XST_SUCCESS) {
        xil_printf("AXI DMA initialization failed\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("AXI DMA is in scatter-gather mode; simple S2MM required\r\n");
        return XST_FAILURE;
    }

    XAxiDma_Reset(&AxiDma);
    for (reset_wait = 0u; reset_wait < 1000000u; ++reset_wait) {
        if (XAxiDma_ResetIsDone(&AxiDma))
            break;
        if (reset_wait == 999999u) {
            xil_printf("AXI DMA reset timeout\r\n");
            return XST_FAILURE;
        }
        /* The reset is normally complete within a few PL clock cycles. */
    }

    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static void print_frames(u32 count)
{
    u32 frame;

    if (count > CAPTURE_FRAMES)
        count = CAPTURE_FRAMES;

    for (frame = 0u; frame < count; ++frame) {
        u32 *word = &RxBuffer[frame * WORDS_PER_FRAME];
        xil_printf("frame[%u] ch1=%08x ch2=%08x ch3=%08x ch4=%08x "
                   "pad=%08x,%08x,%08x,%08x\r\n",
                   (unsigned int)frame,
                   (unsigned int)word[0], (unsigned int)word[1],
                   (unsigned int)word[2], (unsigned int)word[3],
                   (unsigned int)word[4], (unsigned int)word[5],
                   (unsigned int)word[6], (unsigned int)word[7]);
    }
}

int main(void)
{
    u32 elapsed;
    int result;

    xil_printf("\r\nADAU1979 single-device capture\r\n");
    xil_printf("IP base=0x%08x DMA device=%u\r\n",
               (unsigned int)ADAU1979_BASEADDR,
               (unsigned int)DMA_DEVICE_ID);
    xil_printf("Frame layout: 4 valid 32-bit words + 4 zero words, 32 bytes\r\n");

    result = init_dma();
    if (result != XST_SUCCESS)
        return XST_FAILURE;

    result = wait_for_init();
    if (result != XST_SUCCESS)
        return XST_FAILURE;

    /* The S2MM DRE is disabled, so use the 64-byte aligned buffer above. */
    Xil_DCacheFlushRange((UINTPTR)RxBuffer, DMA_BYTES);
    result = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)RxBuffer, DMA_BYTES,
                                    XAXIDMA_DEVICE_TO_DMA);
    if (result != XST_SUCCESS) {
        xil_printf("Could not start AXI DMA S2MM: %d\r\n", result);
        return XST_FAILURE;
    }

    /* Start the PL FIFO only after the DMA receiver is armed. */
    adau1979_write(ADAU1979_BASEADDR,
                   ADAU1979_CAPTURE_SAMPLE_LEN_OFFSET, CAPTURE_FRAMES);
    adau1979_write(ADAU1979_BASEADDR,
                   ADAU1979_CAPTURE_CONTROL_OFFSET,
                   ADAU1979_CAPTURE_CTRL_START);

    for (elapsed = 0u; elapsed < DMA_TIMEOUT_MS; ++elapsed) {
        if (!XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA))
            break;
        usleep(1000u);
    }

    if (elapsed == DMA_TIMEOUT_MS) {
        xil_printf("DMA timeout: check ADAU BCLK/LRCLK/SDATA inputs\r\n");
        print_ip_status("dma-timeout");
        return XST_FAILURE;
    }

    Xil_DCacheInvalidateRange((UINTPTR)RxBuffer, DMA_BYTES);
    print_ip_status("capture-done");
    print_frames(PRINT_FRAMES);
    xil_printf("Capture complete\r\n");
    return XST_SUCCESS;
}
