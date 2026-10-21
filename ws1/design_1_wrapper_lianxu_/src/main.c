/* Continuous Simple S2MM: 8 DDR blocks, 1024 frames/block, 32 bytes/frame.
 * word0..3 = logical A CH1..4; word4..7 = logical B CH1..4.
 * Hardware configuration and verified readback are read from the ABI registers.
 * Proven single-device recovery uses DUAL_ENABLE=0 in the BD build config.
 */

#include "xparameters.h"
#include "xaxidma.h"
#include "xaxidma_hw.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xstatus.h"
#include "xscugic.h"
#include "xuartps.h"
#include "sleep.h"
#include "xtime_l.h"

#include "adau1979_capture.h"

#ifndef XPAR_ADAU1979_CAPTURE_0_BASEADDR
#error "The exported platform is missing XPAR_ADAU1979_CAPTURE_0_BASEADDR"
#endif

#ifndef XPAR_AXI_DMA_0_DEVICE_ID
#error "The exported platform is missing XPAR_AXI_DMA_0_DEVICE_ID"
#endif

#define ADAU1979_BASEADDR       XPAR_ADAU1979_CAPTURE_0_BASEADDR
#define DMA_DEVICE_ID           XPAR_AXI_DMA_0_DEVICE_ID
#define DMA_BASEADDR            XPAR_AXI_DMA_0_BASEADDR
#define DMA_INTR_ID             XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR
#define INTC_DEVICE_ID          XPAR_SCUGIC_0_DEVICE_ID

#define CAPTURE_FRAMES          1024u
#define WORDS_PER_FRAME         8u
#define BYTES_PER_FRAME         32u
/* One AXI beat is one 256-bit (32-byte) audio frame. */
#define DMA_BYTES               (CAPTURE_FRAMES * BYTES_PER_FRAME)
#define RING_BLOCKS             8u
#define RING_WORDS              (RING_BLOCKS * CAPTURE_FRAMES * WORDS_PER_FRAME)
#define RING_BYTES              (RING_BLOCKS * DMA_BYTES)
#define INIT_TIMEOUT_MS         5000u
#define DMA_TIMEOUT_MS          10000u
#define PRINT_PERIOD_MS         100u  /* 10 latest-sample lines per second */
#define STATUS_PERIOD_MS        1000u

static XAxiDma AxiDma;
static XScuGic Intc;
static u32 RxBuffer[RING_WORDS]
    __attribute__((aligned(64)));
static volatile u32 active_block;
static volatile u32 completed_blocks;
static volatile u32 last_completed_block;
static volatile u32 dma_irq_error;
static volatile u32 stop_capture;

static void dma_s2mm_handler(void *callback);
static u32 read_dma_s2mm_status(void);

static void print_ip_status(const char *tag, u32 dma_blocks,
                            u32 display_skipped_blocks)
{
    u32 status = adau1979_read(ADAU1979_BASEADDR,
                               ADAU1979_CAPTURE_STATUS_OFFSET);
    u32 i2s_frames = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_I2S_FRAMES_OFFSET);
    u32 fifo_level = adau1979_read(ADAU1979_BASEADDR,
                                   ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET);
    u32 fifo_ovf = adau1979_read(ADAU1979_BASEADDR,
                                 ADAU1979_CAPTURE_FIFO_OVF_OFFSET);
    u32 errors = adau1979_read(ADAU1979_BASEADDR,
                               ADAU1979_CAPTURE_ERROR_COUNT_OFFSET);
    u32 i2s_sync_errors = adau1979_read(
        ADAU1979_BASEADDR, ADAU1979_CAPTURE_I2S_SYNC_ERROR_OFFSET);
    u32 i2c_ack_errors = adau1979_read(
        ADAU1979_BASEADDR, ADAU1979_CAPTURE_I2C_ACK_ERROR_OFFSET);

    xil_printf("%s status=0x%08x i2s_frames=%u dma_blocks=%u fifo_frames=%u "
               "fifo_overflows=%u err_total=%u i2s_sync_err=%u "
               "i2c_ack_err=%u display_skipped_blocks=%u axis_frames=%u DMASR=%08x\r\n",
               tag, (unsigned int)status, (unsigned int)i2s_frames,
               (unsigned int)dma_blocks, (unsigned int)fifo_level,
               (unsigned int)fifo_ovf, (unsigned int)errors,
               (unsigned int)i2s_sync_errors, (unsigned int)i2c_ack_errors,
               (unsigned int)display_skipped_blocks,
               (unsigned int)adau1979_read(ADAU1979_BASEADDR, ADAU1979_CAPTURE_AXIS_FRAMES_OFFSET),
               (unsigned int)read_dma_s2mm_status());
}

/* Read the AXI DMA S2MM status directly for timeout diagnosis. */
static u32 read_dma_s2mm_status(void)
{
    return Xil_In32(DMA_BASEADDR + XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
}

static void print_dma_status(const char *tag)
{
    u32 status = read_dma_s2mm_status();

    xil_printf("%s DMA S2MM status=0x%08x halted=%u idle=%u "
               "internal_err=%u slave_err=%u decode_err=%u\r\n",
               tag, (unsigned int)status,
               (unsigned int)((status & XAXIDMA_HALTED_MASK) != 0u),
               (unsigned int)((status & XAXIDMA_IDLE_MASK) != 0u),
               (unsigned int)((status & XAXIDMA_ERR_INTERNAL_MASK) != 0u),
               (unsigned int)((status & XAXIDMA_ERR_SLAVE_MASK) != 0u),
               (unsigned int)((status & XAXIDMA_ERR_DECODE_MASK) != 0u));
}

static int print_i2c_readback(void)
{
    static const u32 regs[5] = {0x00u,0x01u,0x04u,0x05u,0x06u};
    u32 bank, index;
    int all_ok = 1;
    for (bank=0u; bank<2u; ++bank) {
        u32 base = bank ? ADAU1979_CAPTURE_DEVICE_B_OFFSET : ADAU1979_CAPTURE_DEVICE_A_OFFSET;
        u32 status = adau1979_read(ADAU1979_BASEADDR,base);
        u32 addr = (status>>17)&0x7Fu;
        u32 master = (status>>16)&1u;
        u32 probe = adau1979_read(ADAU1979_BASEADDR,
            bank ? ADAU1979_CAPTURE_PROBE_B_OFFSET : ADAU1979_CAPTURE_PROBE_A_OFFSET);
        xil_printf("device %c addr7=0x%02x role=%s enabled=%u PLL=%u write_ACK=%u verified=%u status=%08x\r\n",
            'A'+bank,(unsigned)addr,master ? "master" : "slave",
            (unsigned)((status>>15)&1u),(unsigned)((status>>12)&1u),
            (unsigned)((status>>13)&1u),(unsigned)((status>>14)&1u),(unsigned)status);
        if (!(status & 0x8000u)) continue;
        xil_printf(" pre-config probe addr7=0x%02x attempted=%u done=%u address_ACK=%u status=%08x\r\n",
            (unsigned)((probe>>8)&0x7Fu),(unsigned)(probe&1u),
            (unsigned)((probe>>1)&1u),(unsigned)((probe>>2)&1u),(unsigned)probe);
        if ((probe & 7u)!=7u || ((probe>>8)&0x7Fu)!=addr) all_ok=0;
        if ((status & ADAU1979_CAPTURE_DEVICE_PASS_MASK) != ADAU1979_CAPTURE_DEVICE_PASS_MASK ||
            (status & ADAU1979_CAPTURE_DEVICE_ERROR_MASK)) all_ok=0;
        for (index=0u; index<5u; ++index) {
            u32 value=adau1979_read(ADAU1979_BASEADDR,base+4u+4u*index)&0xFFu;
            u32 expected = index==0u ? 1u : index==1u ? 0xC3u :
                           index==2u ? 0xBFu : index==3u ? 2u : master;
            xil_printf(" addr=%02x reg=%02x actual=%02x expected=%02x valid=%u error=%u\r\n",
                (unsigned)addr,(unsigned)regs[index],(unsigned)value,(unsigned)expected,
                (unsigned)((status>>(2u+index))&1u),(unsigned)((status>>(7u+index))&1u));
            if (value!=expected) all_ok=0;
        }
    }
    {
        u32 failure=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_FAILURE_OFFSET);
        u32 detail=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_DEBUG_STATUS_OFFSET);
        if (failure & 0x8000u) {
            xil_printf("INIT FAIL code=%u addr7=%02x reg=%02x actual=%02x expected=%02x\r\n",
                (unsigned)((failure>>16)&3u),(unsigned)((failure>>8)&0x7Fu),
                (unsigned)(failure&0xFFu),(unsigned)((detail>>8)&0xFFu),(unsigned)(detail&0xFFu));
            if ((failure&0xFFu)==0xFFu)
                xil_printf(" failure phase=pre-config address probe; no register/data bytes sent\r\n");
            all_ok=0;
        }
    }
    return all_ok ? XST_SUCCESS : XST_FAILURE;
}

static int print_configuration(void)
{
    u32 abi=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_ABI_OFFSET);
    u32 map=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_MAPPING_OFFSET);
    u32 dev_a=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_DEVICE_A_OFFSET);
    u32 dev_b=adau1979_read(ADAU1979_BASEADDR,ADAU1979_CAPTURE_DEVICE_B_OFFSET);
    if (abi!=ADAU1979_CAPTURE_ABI) {
        xil_printf("Hardware ABI mismatch: actual=%08x expected=%08x; rebuild/export XSA\r\n",
            (unsigned)abi,(unsigned)ADAU1979_CAPTURE_ABI);
        return XST_FAILURE;
    }
    xil_printf("A addr7=%02x role=%s; B addr7=%02x role=%s enabled=%u\r\n",
        (unsigned)((dev_a>>17)&0x7Fu),(dev_a&0x10000u) ? "master":"slave",
        (unsigned)((dev_b>>17)&0x7Fu),(dev_b&0x10000u) ? "master":"slave",
        (unsigned)((dev_b>>15)&1u));
    xil_printf("dual=%u audio_master=%c A SDATA=%u/%u -> word0..3; B SDATA=%u/%u -> word4..7\r\n",
        (unsigned)(map&1u),'A'+((map>>1)&1u),
        (unsigned)((map>>7)&3u),(unsigned)((map>>9)&3u),
        (unsigned)((map>>11)&3u),(unsigned)((map>>13)&3u));
    return XST_SUCCESS;
}

/*
 * The Native ILA is armed from Vivado Hardware Manager (JTAG).  The PS cannot
 * write that arm state.  The UART command below is the PS-side "start" button:
 * after the ILA is armed, it requests a fresh ADAU reset/I2C initialization.
 * Probe 2 (adau_pd_rst) can therefore be used as the ILA trigger.  The
 * application then waits for the PL init-done flag before starting DMA.
 */
static int wait_for_ila_start(void)
{
    char c;
    u32 elapsed;

    xil_printf("Arm Native ILA in Hardware Manager, set probe2 rising-edge trigger,\r\n");
    xil_printf("then press 's' here to start ADAU1979 init/capture (r is also accepted)\r\n");
    do {
        c = inbyte();
    } while (c != 's' && c != 'S' && c != 'r' && c != 'R');

    adau1979_write(ADAU1979_BASEADDR,
                   ADAU1979_CAPTURE_CONTROL_OFFSET,
                   ADAU1979_CAPTURE_CTRL_REINIT);
    /* Wait for new busy, avoiding a stale done flag from power-on init. */
    for (elapsed=0u; elapsed<1000u; ++elapsed) {
        if (adau1979_read(ADAU1979_BASEADDR, ADAU1979_CAPTURE_STATUS_OFFSET) &
            ADAU1979_CAPTURE_STATUS_INIT_BUSY) break;
        usleep(100u);
    }
    if (elapsed==1000u) {
        xil_printf("ADAU1979 reinit did not enter busy\r\n");
        return XST_FAILURE;
    }
    xil_printf("PS start accepted: ADAU1979 reset/I2C transaction requested; waiting for init-done\r\n");
    return XST_SUCCESS;
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
            print_i2c_readback();
            return XST_FAILURE;
        }

        if ((status & ADAU1979_CAPTURE_STATUS_INIT_DONE) != 0u) {
            xil_printf("ADAU1979 initialization complete; checking both device banks\r\n");
            if (print_configuration()!=XST_SUCCESS) return XST_FAILURE;
            return print_i2c_readback();
        }

        usleep(1000u);
    }

    xil_printf("ADAU1979 init timeout\r\n");
    print_ip_status("init-timeout", 0u, 0u);
    print_i2c_readback();
    return XST_FAILURE;
}

static int init_dma(void)
{
    XAxiDma_Config *config = XAxiDma_LookupConfig(DMA_DEVICE_ID);
    XScuGic_Config *intc_config;
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
    intc_config = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (intc_config == NULL ||
        XScuGic_CfgInitialize(&Intc, intc_config,
                              intc_config->CpuBaseAddress) != XST_SUCCESS) {
        xil_printf("GIC initialization failed\r\n");
        return XST_FAILURE;
    }
    if (XScuGic_Connect(&Intc, DMA_INTR_ID,
                        (Xil_InterruptHandler)dma_s2mm_handler,
                        &AxiDma) != XST_SUCCESS) {
        xil_printf("DMA interrupt connection failed\r\n");
        return XST_FAILURE;
    }
    XScuGic_Enable(&Intc, DMA_INTR_ID);
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                  (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                  &Intc);
    Xil_ExceptionEnable();
    XAxiDma_IntrEnable(&AxiDma,
                       XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK,
                       XAXIDMA_DEVICE_TO_DMA);
    print_dma_status("DMA initialized:");
    return XST_SUCCESS;
}

/* IRQ exclusion covers only a 32-byte cache invalidate and copy.  DMA can
 * finish the active block meanwhile, but cannot be rearmed onto this completed
 * block until IRQs resume. UART never holds IRQs or touches the DMA ring. */
static int snapshot_latest(u32 *sample, u32 *sequence)
{
    u32 block, index;
    const u32 *last;
    Xil_ExceptionDisableMask(XIL_EXCEPTION_IRQ);
    block=last_completed_block;
    *sequence=completed_blocks;
    if (*sequence==0u || block==active_block) {
        Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
        return 0;
    }
    last=&RxBuffer[block*CAPTURE_FRAMES*WORDS_PER_FRAME + (CAPTURE_FRAMES-1u)*WORDS_PER_FRAME];
    Xil_DCacheInvalidateRange((UINTPTR)last, BYTES_PER_FRAME);
    for (index=0u; index<WORDS_PER_FRAME; ++index) sample[index]=last[index];
    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
    return 1;
}

static void print_latest_frame(const u32 *word, u32 sequence)
{
    xil_printf("sample seq=%u ch1=%08x ch2=%08x ch3=%08x ch4=%08x ch5=%08x ch6=%08x ch7=%08x ch8=%08x\r\n",
        (unsigned)sequence,(unsigned)word[0],(unsigned)word[1],(unsigned)word[2],(unsigned)word[3],
        (unsigned)word[4],(unsigned)word[5],(unsigned)word[6],(unsigned)word[7]);
}

static int stop_requested(void)
{
#ifdef STDIN_BASEADDRESS
    if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        char c = inbyte();
        return c == 'q' || c == 'Q';
    }
#endif
    return 0;
}

/* Submit one fixed-size Simple S2MM block.  The PL capture remains enabled
 * while the DMA destination advances through the DDR ring. */
static int start_dma_block(u32 block_index)
{
    u32 *block_buffer = &RxBuffer[block_index * CAPTURE_FRAMES * WORDS_PER_FRAME];
    int result;

    /* Ring was flushed before capture. CPU only invalidates/reads samples. */
    result = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)block_buffer,
                                    DMA_BYTES, XAXIDMA_DEVICE_TO_DMA);
    if (result != XST_SUCCESS)
        return result;

    active_block = block_index;
    return XST_SUCCESS;
}

static void dma_s2mm_handler(void *callback)
{
    XAxiDma *instance = (XAxiDma *)callback;
    u32 irq_status = XAxiDma_IntrGetIrq(instance, XAXIDMA_DEVICE_TO_DMA);

    XAxiDma_IntrAckIrq(instance, irq_status, XAXIDMA_DEVICE_TO_DMA);
    if ((irq_status & XAXIDMA_IRQ_ERROR_MASK) != 0u) {
        dma_irq_error = irq_status;
        stop_capture = 1u;
        return;
    }

    if (stop_capture != 0u) return;
    if ((irq_status & XAXIDMA_IRQ_IOC_MASK) != 0u) {
        u32 finished = active_block;
        u32 next = (active_block + 1u) % RING_BLOCKS;
        last_completed_block = finished;
        completed_blocks++;
        if (start_dma_block(next) != XST_SUCCESS) {
            dma_irq_error = 0x80000000u | next;
            stop_capture = 1u;
        }
    }
}

int main(void)
{
    XTime now, last_print, last_status, last_progress;
    u32 sample[WORDS_PER_FRAME];
    u32 observed_seq = 0u;
    u32 displayed_seq = 0u;
    u32 latest_seq = 0u;
    u32 display_skipped_blocks = 0u;
    int result;

    xil_printf("\r\nDual ADAU1979 continuous capture\r\n");
    xil_printf("IP base=0x%08x DMA device=%u\r\n",
               (unsigned int)ADAU1979_BASEADDR,
               (unsigned int)DMA_DEVICE_ID);
    xil_printf("Frame layout: A CH1..4 then B CH1..4, signed 24->32, 32 bytes\r\n");
    xil_printf("Simple DMA ring: %u blocks x %u frames = %u bytes; press q to stop\r\n",
               (unsigned int)RING_BLOCKS, (unsigned int)CAPTURE_FRAMES,
               (unsigned int)RING_BYTES);

    if (print_configuration()!=XST_SUCCESS) return XST_FAILURE;
    result = init_dma();
    if (result != XST_SUCCESS)
        return XST_FAILURE;

    if (wait_for_ila_start()!=XST_SUCCESS) return XST_FAILURE;

    result = wait_for_init();
    if (result != XST_SUCCESS)
        return XST_FAILURE;

    /* Start the first Simple S2MM block.  The IOC interrupt immediately
     * submits each subsequent block and wraps the address through the ring. */
    active_block = 0u;
    completed_blocks = 0u;
    last_completed_block = 0u;
    dma_irq_error = 0u;
    stop_capture = 0u;
    Xil_DCacheFlushRange((UINTPTR)RxBuffer, RING_BYTES);
    result = start_dma_block(0u);
    if (result != XST_SUCCESS) {
        xil_printf("Could not start AXI DMA S2MM: %d\r\n", result);
        print_dma_status("DMA submit error:");
        return XST_FAILURE;
    }
    /* One start arms the PL packetizer.  It remains enabled across every
     * 1024-frame TLAST; only an explicit q below clears it. */
    adau1979_write(ADAU1979_BASEADDR,
                   ADAU1979_CAPTURE_SAMPLE_LEN_OFFSET, CAPTURE_FRAMES);
    adau1979_write(ADAU1979_BASEADDR,
                   ADAU1979_CAPTURE_CONTROL_OFFSET,
                   ADAU1979_CAPTURE_CTRL_START);
    print_dma_status("DMA armed:");

    XTime_GetTime(&last_print); last_status=last_print; last_progress=last_print;
    for (;;) {
        XTime_GetTime(&now);
        if (completed_blocks != observed_seq) {
            observed_seq=completed_blocks; last_progress=now;
        }
        if (now-last_print >= COUNTS_PER_SECOND/10u) {
            if (snapshot_latest(sample,&latest_seq) && latest_seq!=displayed_seq) {
                /* Unsigned sequence arithmetic also handles counter wrap. */
                display_skipped_blocks += latest_seq-displayed_seq-1u;
                displayed_seq=latest_seq;
                print_latest_frame(sample,latest_seq);
            }
            last_print=now;
        }
        if (now-last_status >= COUNTS_PER_SECOND) {
            print_ip_status("ring-progress",completed_blocks,display_skipped_blocks);
            last_status=now;
        }
        if (stop_requested()) {
            stop_capture = 1u;
            break;
        }
        if (dma_irq_error != 0u || stop_capture != 0u)
            break;
        if (now-last_progress >= (XTime)DMA_TIMEOUT_MS*COUNTS_PER_SECOND/1000u) {
            xil_printf("DMA stalled: no completed block in %u ms\r\n",DMA_TIMEOUT_MS);
            print_ip_status("dma-timeout",completed_blocks,display_skipped_blocks);
            dma_irq_error=0x40000000u;
            break;
        }
        usleep(1000u);
    }
    stop_capture=1u;
    adau1979_write(ADAU1979_BASEADDR, ADAU1979_CAPTURE_CONTROL_OFFSET, 0u);
    XAxiDma_IntrDisable(&AxiDma,XAXIDMA_IRQ_ALL_MASK,XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_Reset(&AxiDma);

    if (dma_irq_error != 0u) {
        xil_printf("DMA interrupt error=0x%08x\r\n",
                   (unsigned int)dma_irq_error);
        print_dma_status("DMA error:");
        return XST_FAILURE;
    }

    xil_printf("Capture stopped; DDR ring retains the most recent %u blocks\r\n",
               (unsigned int)RING_BLOCKS);
    return XST_SUCCESS;
}
