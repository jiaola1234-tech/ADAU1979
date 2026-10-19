# ADAU1979 Capture IP

本工程固定使用一颗 ADAU1979，I²C 7 位地址为 `0x11`。配置寄存器保持原工程的 48 kHz、24-bit I2S、32-bit slot 参数，并由该器件产生 BCLK/LRCLK。

## 数据路径

`adau_sdata[2]`/`adau_sdata[3]` 接收单颗器件的 `SDATAOUT11/12`。每个 LRCLK 帧包含 4 个有效通道：

- `m00_axis_tdata[31:0]`：SDATAOUT11 左时隙
- `m00_axis_tdata[63:32]`：SDATAOUT11 右时隙
- `m00_axis_tdata[95:64]`：SDATAOUT12 左时隙
- `m00_axis_tdata[127:96]`：SDATAOUT12 右时隙
- `[255:128]`：零填充，仅用于保持原有 256-bit AXI/DMA 帧宽

I²S 接收器 → 256-bit FIFO → AXI DMA S2MM → DDR。DDR 每帧仍占 32 字节，地址按帧递增 32 字节；每个有效采样占 32 位，其中高 8 位为 24 位有符号采样的符号扩展。

## I²C 约定

初始化状态机只访问 `0x11`，没有第二器件参数、地址扫描或器件选择。I²C 控制器接收 7 位地址；写事务内部生成 `0x22`，读事务内部生成 `0x23`。

## Vivado / Vitis

AXI DMA S2MM 保持 256 bit，DMA 长度必须是 `采样帧数 * 32` 字节。重新打包 IP、生成 BD 输出产品、综合实现并导出 XSA 后，再编译 Vitis 示例。
