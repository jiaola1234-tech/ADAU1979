# ADAU1979 Capture IP

This IP captures 8 channels from two ADAU1979 chips and outputs one 256-bit AXI-Stream word per audio frame.

## Data path

- `adau_bclk`, `adau_lrclk`, `adau_sdata[3:0]` -> I2S receiver
- 8 x 32-bit packed frame -> FIFO
- FIFO -> 256-bit AXI-Stream
- `adau_scl`, `adau_sda`, `adau_pd_rst` -> PL I2C initialization

## Register map

- `0x00` control
  - bit0: start capture
  - bit1: re-init request
- `0x04` sample_len
- `0x08` status
- `0x0C` I2S frame count
- `0x10` DMA frame count
- `0x14` FIFO level
- `0x18` FIFO overflow count
- `0x1C` error count

## Notes

- The sample data does not use SPI. SPI/I2C is only for register programming.
- U1 is the first ADAU1979, U2 is the second ADAU1979.
- Default configuration assumes:
  - 48 kHz
  - 24.576 MHz MCLK
  - I2S
  - 24-bit audio in 32-bit slots
  - U2 master, U1 slave

## Vivado integration

1. Add `ip_repo/adau1979_capture_1.0` to the IP repository path.
2. Package the IP using `scripts/package_ip.tcl` if needed.
3. Replace the old AD7606 IP in the BD with `adau1979_capture_v1_0`.
4. Connect:
   - `m00_axis_*` to AXI DMA S2MM
   - `s00_axi_*` to PS `M_AXI_GP0`
   - `m00_axis_aclk` and `s00_axi_aclk` to your 100 MHz PL clock
   - board pins to `adau_*`
5. Set AXI DMA stream width to 256 bits.
6. Make sure the DMA transfer length is a multiple of 32 bytes.

## Current hardware expectation

- U1/U2 remain the two ADAU1979 chips on the board.
- The board's onboard 24.576 MHz oscillator is used as MCLK.
- One chip is configured as BCLK/LRCLK master and the other as slave.
- The schematic populates both pull-up and pull-down resistors on every ADDR pin. Rework the straps before use: U1 `0x11` by removing `R11.0/R12.0`; U2 `0x31` by removing `R11.1/R14.1`.
- If you later change the hardware to expose SPI pins, the control block can be swapped out without touching the capture path.

## Current code status

This is a first working RTL skeleton. Before final board use, verify:

- I2S bit alignment on a scope or logic analyzer
- I2C ACK and PLL lock
- `TLAST` boundary and DMA packet length
- exact PACKAGE_PIN mapping in your board XDC

## Vitis usage

Use this smoke-test example as a starting point:

```text
C:/Users/weitong/Desktop/ADAU1979/examples/vitis_adau1979_dma_test.c
```

1. Wait until status shows init done.
2. Arm AXI DMA S2MM first.
3. Write sample length.
4. Set start bit.
5. Read data from DDR through DMA.
