#ifndef ADAU1979_CAPTURE_H
#define ADAU1979_CAPTURE_H

#include "xil_io.h"
#include "xil_types.h"

/* AXI-Lite register map of the single-device ADAU1979 capture IP. */
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

#define ADAU1979_CAPTURE_CTRL_START              0x00000001u
#define ADAU1979_CAPTURE_CTRL_REINIT             0x00000002u

#define ADAU1979_CAPTURE_STATUS_CAPTURING        0x00000001u
#define ADAU1979_CAPTURE_STATUS_INIT_BUSY        0x00000002u
#define ADAU1979_CAPTURE_STATUS_INIT_DONE        0x00000004u
#define ADAU1979_CAPTURE_STATUS_INIT_ERROR       0x00000008u
#define ADAU1979_CAPTURE_STATUS_FIFO_FULL        0x00000010u

static inline void adau1979_write(u32 base, u32 offset, u32 value)
{
    Xil_Out32(base + offset, value);
}

static inline u32 adau1979_read(u32 base, u32 offset)
{
    return Xil_In32(base + offset);
}

#endif
