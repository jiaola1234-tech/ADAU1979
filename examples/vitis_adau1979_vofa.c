/*
 * ADAU1979 -> AXI DMA -> DDR -> VOFA JustFloat example.
 *
 * The PL capture rate remains 48 kHz.  One frame is sent to VOFA every
 * VOFA_DECIMATION input frames, so the default output rate is 1 kHz.
 * Each VOFA frame contains eight IEEE-754 floats followed by the JustFloat
 * marker 00 00 80 7f.
 *
 * Do not print normal text after the binary stream starts.  Text bytes would
 * be interpreted as part of the JustFloat stream by VOFA.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_types.h"
#include "xstatus.h"
#include "xuartps.h"
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

#if defined(XPAR_PS7_UART_1_DEVICE_ID)
#define VOFA_UART_DEV_ID XPAR_PS7_UART_1_DEVICE_ID
#else
#error "PS UART1 is not enabled in the Vivado hardware design"
#endif

#define AUDIO_SAMPLE_RATE       48000u
#define VOFA_OUTPUT_RATE        1000u
#define VOFA_DECIMATION        (AUDIO_SAMPLE_RATE / VOFA_OUTPUT_RATE)
#define CAPTURE_FRAMES          1024u
#define WORDS_PER_FRAME         8u
#define BYTES_PER_FRAME         (WORDS_PER_FRAME * sizeof(u32))
#define DMA_RX_BYTES            (CAPTURE_FRAMES * BYTES_PER_FRAME)
#define UART_BAUD_RATE          921600u
#define INIT_TIMEOUT_LOOPS      5000000u
#define DMA_TIMEOUT_LOOPS       50000000u
#define ADC_FULL_SCALE          8388608.0f
#define DMA_BUFFER_COUNT        2u

#if (AUDIO_SAMPLE_RATE % VOFA_OUTPUT_RATE) != 0
#error "VOFA_OUTPUT_RATE must divide AUDIO_SAMPLE_RATE"
#endif

static XAxiDma AxiDma;
static XUartPs UartPs;
static u32 RxBuffer[DMA_BUFFER_COUNT][CAPTURE_FRAMES * WORDS_PER_FRAME]
    __attribute__((aligned(64)));
static u32 decimation_phase;

static int init_uart(void)
{
    XUartPs_Config *cfg;
    XUartPsFormat format;

    cfg = XUartPs_LookupConfig(VOFA_UART_DEV_ID);
    if (cfg == NULL)
        return XST_FAILURE;

    if (XUartPs_CfgInitialize(&UartPs, cfg, cfg->BaseAddress) != XST_SUCCESS)
        return XST_FAILURE;

    XUartPs_SetOperMode(&UartPs, XUARTPS_OPER_MODE_NORMAL);
    format.BaudRate = UART_BAUD_RATE;
    format.DataBits = XUARTPS_FORMAT_8_BITS;
    format.Parity = XUARTPS_FORMAT_NO_PARITY;
    format.StopBits = XUARTPS_FORMAT_1_STOP_BIT;
    if (XUartPs_SetDataFormat(&UartPs, &format) != XST_SUCCESS)
        return XST_FAILURE;

    return XST_SUCCESS;
}

static int uart_send_blocking(const u8 *data, u32 length)
{
    u32 sent_total = 0u;

    while (sent_total < length) {
        u32 sent = XUartPs_Send(&UartPs,
                                (u8 *)&data[sent_total],
                                length - sent_total);

        if (sent == 0u)
            continue;

        sent_total += sent;
    }

    while (XUartPs_IsSending(&UartPs)) {
    }

    return XST_SUCCESS;
}

static int wait_adau1979_init_done(void)
{
    u32 timeout = INIT_TIMEOUT_LOOPS;

    while (timeout-- != 0u) {
        u32 status = ADAU1979_CAPTURE_mReadReg(
            ADAU1979_CAPTURE_BASEADDR,
            ADAU1979_CAPTURE_STATUS_OFFSET);

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_ERROR) != 0u)
            return XST_FAILURE;

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u)
            return XST_SUCCESS;
    }

    return XST_FAILURE;
}

static int init_dma(void)
{
    XAxiDma_Config *cfg;

    cfg = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (cfg == NULL)
        return XST_FAILURE;

    if (XAxiDma_CfgInitialize(&AxiDma, cfg) != XST_SUCCESS)
        return XST_FAILURE;

    if (XAxiDma_HasSg(&AxiDma))
        return XST_FAILURE;

    XAxiDma_IntrDisable(&AxiDma,
                        XAXIDMA_IRQ_ALL_MASK,
                        XAXIDMA_DEVICE_TO_DMA);
    return XST_SUCCESS;
}

static int wait_capture_idle(void)
{
    u32 timeout = INIT_TIMEOUT_LOOPS;

    while (timeout-- != 0u) {
        u32 status = ADAU1979_CAPTURE_mReadReg(
            ADAU1979_CAPTURE_BASEADDR,
            ADAU1979_CAPTURE_STATUS_OFFSET);

        if ((status & ADAU1979_CAPTURE_STATUS_CAPTURING) == 0u)
            return XST_SUCCESS;
    }

    return XST_FAILURE;
}

static int start_capture(u32 *buffer)
{
    /* Ensure the previous packet has released the start bit before rearming. */
    ADAU1979_CAPTURE_mWriteReg(ADAU1979_CAPTURE_BASEADDR,
                               ADAU1979_CAPTURE_CONTROL_OFFSET,
                               0u);
    if (wait_capture_idle() != XST_SUCCESS)
        return XST_FAILURE;

    /* The DMA buffer is written by PL, so discard stale CPU cache lines. */
    Xil_DCacheFlushRange((UINTPTR)buffer, DMA_RX_BYTES);

    if (XAxiDma_SimpleTransfer(&AxiDma,
                               (UINTPTR)buffer,
                               DMA_RX_BYTES,
                               XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS)
        return XST_FAILURE;

    ADAU1979_CAPTURE_SetSampleLen(ADAU1979_CAPTURE_BASEADDR,
                                   CAPTURE_FRAMES);
    ADAU1979_CAPTURE_Start(ADAU1979_CAPTURE_BASEADDR);

    return XST_SUCCESS;
}

static int wait_capture_complete(u32 *buffer)
{
    u32 timeout = DMA_TIMEOUT_LOOPS;

    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA) &&
           timeout-- != 0u) {
    }

    if (timeout == 0u)
        return XST_FAILURE;

    /* Make the data written by DMA visible to the ARM CPU. */
    Xil_DCacheInvalidateRange((UINTPTR)buffer, DMA_RX_BYTES);
    return XST_SUCCESS;
}

static float adc_word_to_float(u32 word)
{
    /* The PL IP sign-extends the 24-bit ADAU1979 sample to a signed u32. */
    return (float)((s32)word) / ADC_FULL_SCALE;
}

static int send_vofa_frame(const u32 *frame)
{
    float values[WORDS_PER_FRAME];
    static const u8 justfloat_tail[4] = {0x00u, 0x00u, 0x80u, 0x7Fu};
    u32 channel;

    for (channel = 0u; channel < WORDS_PER_FRAME; channel++)
        values[channel] = adc_word_to_float(frame[channel]);

    if (uart_send_blocking((const u8 *)values, sizeof(values)) != XST_SUCCESS)
        return XST_FAILURE;

    return uart_send_blocking(justfloat_tail, sizeof(justfloat_tail));
}

static int send_decimated_block(const u32 *buffer)
{
    u32 frame_index;

    for (frame_index = 0u; frame_index < CAPTURE_FRAMES; frame_index++) {
        const u32 *frame = &buffer[frame_index * WORDS_PER_FRAME];

        if (decimation_phase == 0u) {
            if (send_vofa_frame(frame) != XST_SUCCESS)
                return XST_FAILURE;
        }

        decimation_phase++;
        if (decimation_phase == VOFA_DECIMATION)
            decimation_phase = 0u;
    }

    return XST_SUCCESS;
}

int main(void)
{
    u32 current_buffer = 0u;
    u32 next_buffer;

    /* No text is sent here: the first UART bytes must be valid JustFloat. */
    if (init_uart() != XST_SUCCESS)
        return XST_FAILURE;

    if (init_dma() != XST_SUCCESS)
        return XST_FAILURE;

    if (wait_adau1979_init_done() != XST_SUCCESS)
        return XST_FAILURE;

    if (start_capture(RxBuffer[current_buffer]) != XST_SUCCESS)
        return XST_FAILURE;

    if (wait_capture_complete(RxBuffer[current_buffer]) != XST_SUCCESS)
        return XST_FAILURE;

    for (;;) {
        next_buffer = current_buffer ^ 1u;

        /* Capture the next block while the CPU sends the current block. */
        if (start_capture(RxBuffer[next_buffer]) != XST_SUCCESS)
            return XST_FAILURE;

        if (send_decimated_block(RxBuffer[current_buffer]) != XST_SUCCESS)
            return XST_FAILURE;

        if (wait_capture_complete(RxBuffer[next_buffer]) != XST_SUCCESS)
            return XST_FAILURE;

        current_buffer = next_buffer;
    }
}
