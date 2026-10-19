#ifndef ADAU1979_CAPTURE_H
#define ADAU1979_CAPTURE_H

#include "xil_io.h"
#include "xil_types.h"

#define ADAU1979_CAPTURE_CONTROL_OFFSET       0x00u
#define ADAU1979_CAPTURE_SAMPLE_LEN_OFFSET    0x04u
#define ADAU1979_CAPTURE_STATUS_OFFSET        0x08u
#define ADAU1979_CAPTURE_I2S_FRAMES_OFFSET    0x0Cu
#define ADAU1979_CAPTURE_DMA_FRAMES_OFFSET    0x10u
#define ADAU1979_CAPTURE_FIFO_LEVEL_OFFSET    0x14u
#define ADAU1979_CAPTURE_FIFO_OVF_OFFSET      0x18u
#define ADAU1979_CAPTURE_ERROR_COUNT_OFFSET   0x1Cu
#define ADAU1979_CAPTURE_I2C_LAST_DEV_OFFSET  0x20u
#define ADAU1979_CAPTURE_I2C_LAST_REGDATA_OFFSET 0x24u
#define ADAU1979_CAPTURE_I2C_ACK_BITS_OFFSET  0x28u
#define ADAU1979_CAPTURE_VERIFY_INFO_OFFSET   0x2Cu
#define ADAU1979_CAPTURE_DEBUG_STATUS_OFFSET  0x30u /* also verify data */
#define ADAU1979_CAPTURE_DEBUG_INDEX_OFFSET   0x34u
#define ADAU1979_CAPTURE_DEBUG_DATA_LOW_OFFSET  0x38u
#define ADAU1979_CAPTURE_DEBUG_DATA_HIGH_OFFSET 0x3Cu

/* DEBUG_STATUS: count[31:26], ACK error count[23:20], flags[19:16],
 * verify_actual[15:8], verify_expected[7:0].
 * DEBUG_INDEX selects one of 64 64-bit entries. */
#define ADAU1979_DEBUG_EVENT_WRITE       0u
#define ADAU1979_DEBUG_EVENT_PLL_READ    1u
#define ADAU1979_DEBUG_EVENT_INIT_DONE   2u
#define ADAU1979_DEBUG_EVENT_SCAN        3u
#define ADAU1979_DEBUG_EVENT_VERIFY      4u

#define ADAU1979_CAPTURE_CTRL_START           0x00000001u
#define ADAU1979_CAPTURE_CTRL_REINIT          0x00000002u

#define ADAU1979_CAPTURE_STATUS_CAPTURING     0x00000001u
#define ADAU1979_CAPTURE_STATUS_INIT_BUSY     0x00000002u
#define ADAU1979_CAPTURE_STATUS_INIT_DONE     0x00000004u
#define ADAU1979_CAPTURE_STATUS_INIT_ERROR    0x00000008u
#define ADAU1979_CAPTURE_STATUS_FIFO_FULL     0x00000010u

#define ADAU1979_CAPTURE_mWriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))

#define ADAU1979_CAPTURE_mReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))

static inline void ADAU1979_CAPTURE_SetSampleLen(u32 BaseAddress, u32 frames)
{
    ADAU1979_CAPTURE_mWriteReg(BaseAddress,
                               ADAU1979_CAPTURE_SAMPLE_LEN_OFFSET,
                               frames);
}

static inline void ADAU1979_CAPTURE_Start(u32 BaseAddress)
{
    ADAU1979_CAPTURE_mWriteReg(BaseAddress,
                               ADAU1979_CAPTURE_CONTROL_OFFSET,
                               ADAU1979_CAPTURE_CTRL_START);
}

static inline void ADAU1979_CAPTURE_Reinit(u32 BaseAddress)
{
    ADAU1979_CAPTURE_mWriteReg(BaseAddress,
                               ADAU1979_CAPTURE_CONTROL_OFFSET,
                               ADAU1979_CAPTURE_CTRL_REINIT);
}

#endif
