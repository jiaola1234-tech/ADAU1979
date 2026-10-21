#ifndef ADAU1979_CAPTURE_H
#define ADAU1979_CAPTURE_H

#include "xil_io.h"
#include "xil_types.h"

/* AXI-Lite register map of the dual-device ADAU1979 capture IP. */
#define ADAU1979_CAPTURE_CONTROL_OFFSET          0x00u
#define ADAU1979_CAPTURE_SAMPLE_LEN_OFFSET       0x04u
#define ADAU1979_CAPTURE_STATUS_OFFSET           0x08u
#define ADAU1979_CAPTURE_I2S_FRAMES_OFFSET       0x0Cu
#define ADAU1979_CAPTURE_DMA_FRAMES_OFFSET       0x10u
#define ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET       0x14u
#define ADAU1979_CAPTURE_FIFO_OVF_OFFSET         0x18u
#define ADAU1979_CAPTURE_ERROR_COUNT_OFFSET      0x1Cu
#define ADAU1979_CAPTURE_I2C_LAST_DEV_OFFSET     0x20u
#define ADAU1979_CAPTURE_I2C_LAST_REGDATA_OFFSET 0x24u
#define ADAU1979_CAPTURE_I2C_ACK_BITS_OFFSET     0x28u
#define ADAU1979_CAPTURE_DEBUG_STATUS_OFFSET     0x30u
#define ADAU1979_CAPTURE_I2S_SYNC_ERROR_OFFSET   0x58u
#define ADAU1979_CAPTURE_I2C_ACK_ERROR_OFFSET    0x5Cu
#define ADAU1979_CAPTURE_DIAG_STATUS_OFFSET      0x40u
#define ADAU1979_CAPTURE_DIAG_REG00_OFFSET       0x44u
#define ADAU1979_CAPTURE_DIAG_REG01_OFFSET       0x48u
#define ADAU1979_CAPTURE_DIAG_REG04_OFFSET       0x4Cu
#define ADAU1979_CAPTURE_DIAG_REG05_OFFSET       0x50u
#define ADAU1979_CAPTURE_DIAG_REG06_OFFSET       0x54u
#define ADAU1979_CAPTURE_DIAG_DONE               0x00000002u
#define ADAU1979_CAPTURE_DIAG_VALID_MASK         0x0000007Cu
#define ADAU1979_CAPTURE_DIAG_ERROR_MASK         0x00000F80u

#define ADAU1979_CAPTURE_ABI_OFFSET              0x60u
#define ADAU1979_CAPTURE_ABI                     0xAD790208u
#define ADAU1979_CAPTURE_MAPPING_OFFSET          0x64u
#define ADAU1979_CAPTURE_DEVICE_A_OFFSET         0x80u
#define ADAU1979_CAPTURE_DEVICE_B_OFFSET         0xA0u
#define ADAU1979_CAPTURE_FAILURE_OFFSET          0xB8u
#define ADAU1979_CAPTURE_AXIS_FRAMES_OFFSET      0xBCu
/* Device status: busy[0], done[1], read-valid[6:2], read-error[11:7],
 * PLL[12], writes-ACKed[13], verified[14], enabled[15], master[16], addr[23:17].
 * Device bank +4,+8,+12,+16,+20: actual 0x00,01,04,05,06 bytes.
 * Mapping: dual[0], master-index[1], A0[8:7], A1[10:9], B0[12:11], B1[14:13].
 * Failure: reg[7:0], addr[14:8], valid[15], code[17:16] (1=bus,2=PLL,3=value).
 */
#define ADAU1979_CAPTURE_DEVICE_PASS_MASK        0x0000707Eu
#define ADAU1979_CAPTURE_DEVICE_ERROR_MASK       0x00000F80u

#define ADAU1979_CAPTURE_CTRL_START              0x00000001u
#define ADAU1979_CAPTURE_CTRL_REINIT             0x00000002u

#define ADAU1979_CAPTURE_STATUS_CAPTURING        0x00000001u
#define ADAU1979_CAPTURE_STATUS_INIT_BUSY        0x00000002u
#define ADAU1979_CAPTURE_STATUS_INIT_DONE        0x00000004u
#define ADAU1979_CAPTURE_STATUS_INIT_ERROR       0x00000008u
#define ADAU1979_CAPTURE_STATUS_FIFO_FULL        0x00000010u

/* AXI DMA S2MM status bits are defined by xaxidma_hw.h. */

static inline void adau1979_write(u32 base, u32 offset, u32 value)
{
    Xil_Out32(base + offset, value);
}

static inline u32 adau1979_read(u32 base, u32 offset)
{
    return Xil_In32(base + offset);
}

#endif
