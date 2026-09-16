# ADAU1979 八通道 VOFA 测试步骤

## 当前测试链路

```text
ADAU1979 x 2 -> PL I2S 接收 -> 256 bit AXI-Stream
              -> AXI DMA S2MM -> DDR -> PS UART1 -> VOFA
```

- ADAU1979 原始采样率：默认按 48 kHz 处理。
- 每个采样帧：8 路，每路为符号扩展后的 32 bit 数据。
- DMA：每次接收 1024 帧，即 32768 字节。
- 串口输出：每 48 个采样帧输出 1 帧，约为 1 kHz。
- VOFA 数据：8 个 `float`，后接 JustFloat 帧尾 `00 00 80 7F`。
- 浮点范围：24 bit 原始码除以 `8388608.0`，正常约在 `-1.0` 到 `+1.0`。

## 一、重新导出硬件

必须确保 XSA 包含当前 ADAU1979 IP 和最新 bitstream。

1. 打开：

   `C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.xpr`

2. 检查 Block Design，确认：

   - `adau1979_capture_0/m00_axis` 接到 `axi_dma_0/S_AXIS_S2MM`。
   - AXI DMA 为 Simple mode，启用 S2MM，流宽为 256 bit。
   - PS UART0 已关闭。
   - PS UART1 已启用，并使用 MIO 48/49。

   如果 Vivado 报告 UART 参数校验错误，在
   Tcl Console 中执行：

   ```tcl
   source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/06_config_ps_uart1.tcl
   ```

   AX7020 板载 CP2102 的 `UART_TX/UART_RX` 分别连接到
   `PS_MIO48/PS_MIO49`，对应 Zynq 的物理 UART1。
   Vivado 2022.2 中应使用主开关 `PCW_EN_UART0/1` 选择物理 UART。
   当前工程为 `PCW_EN_UART0=0`、`PCW_EN_UART1=1`。UART0 关闭后，
   `PCW_UART0_PERIPHERAL_ENABLE` 的有效范围会变为 `NA`，不要再手工将
   这个派生参数写成 `0`，否则会出现 `value '0' is out of range { NA }`。

3. 重新执行 Generate Bitstream。

4. 选择 `File -> Export -> Export Hardware`，勾选 Include bitstream，覆盖导出到：

   `C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.xsa`

也可以在 Vivado Tcl Console 执行：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/04_build_bitstream_and_export_xsa.tcl
```

## 二、创建 Vitis 工程

1. 启动 Vitis 2022.2，选择一个新的 workspace。
2. 选择 `File -> New -> Platform Project`。
3. 平台名可填 `adau1979_platform`。
4. 选择 `Create from hardware specification (XSA)`，加载上面的 XSA。
5. 操作系统选择 `standalone`，处理器选择 `ps7_cortexa9_0`。
6. Build 平台工程。
7. 选择 `File -> New -> Application Project`。
8. 选择 `adau1979_platform`，应用名可填 `adau1979_vofa`。
9. Domain 选择 `standalone`，模板选择 `Empty Application`。

## 三、加入代码

把以下文件加入应用工程的 `src`：

```text
C:/Users/weitong/Desktop/ADAU1979/examples/vitis_adau1979_vofa.c
C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/drivers/adau1979_capture_v1_0/src/adau1979_capture.h
```

可以在应用工程的 `src` 上右键，选择 `Import Sources`。如果工程中自动生成了 `helloworld.c`，将它删除，保证只有一个 `main()`。

编译前检查生成的 `xparameters.h` 中存在以下定义：

```c
XPAR_AXIDMA_0_DEVICE_ID
XPAR_ADAU1979_CAPTURE_0_C_S00_AXI_BASEADDR
XPAR_PS7_UART_1_DEVICE_ID
```

如果 ADAU1979 的宏名称稍有不同，以 `xparameters.h` 中实际名称修改代码第 27 行的宏。

## 四、下载运行

1. 用 USB-JTAG/UART 连接 AX7020，给 Zynq 板和 ADAU1979 板正确供电并共地。
2. 在 Vitis 中选择 `Xilinx -> Program FPGA`，下载最新 bitstream。
3. Build 应用工程。
4. 右键应用工程，选择 `Run As -> Launch on Hardware (Single Application Debug)`。

程序启动后会：

1. 将 PS UART1 设置为 921600、8 数据位、无校验、1 停止位。
2. 等待 PL 端完成两片 ADAU1979 的 I2C 初始化。
3. 用 AXI DMA 反复接收八通道数据。
4. 抽取为约 1 kHz，并持续发送 JustFloat 二进制帧。

代码进入数据发送后不能再调用 `xil_printf`，否则文本会破坏 VOFA 二进制帧。

## 五、设置 VOFA+

1. 选择板载 USB 转串口对应的 COM 口。
2. 串口参数设置为 `921600, 8, None, 1`，关闭流控。
3. 协议引擎选择 `JustFloat`。
4. 打开串口后应识别出 8 个通道。
5. 在波形控件中添加 `ch0` 到 `ch7`（名称以 VOFA 当前版本显示为准）。

曲线顺序为：

```text
ch0 = U1C1
ch1 = U1C2
ch2 = U1C3
ch3 = U1C4
ch4 = U2C1
ch5 = U2C2
ch6 = U2C3
ch7 = U2C4
```

## 六、第一次上板的检查顺序

1. 先给一个通道输入低频正弦波，例如 100 Hz，其他通道接地或保持稳定。
2. 检查 VOFA 中是否只有对应通道出现正弦波。
3. 依次移动输入，核对八通道顺序。
4. 若完全无数据，先检查 I2C 地址、`PD/RST`、MCLK、BCLK 和 LRCLK。
5. 若有数据但波形失真或通道交错，检查 I2S 模式、LRCLK 极性、24 bit 数据宽度和 32 bit slot 设置。

当前程序只显示原始采样波形，没有滤波、FFT、峰值或其他计算。确认八路采集正确后，再在 PS 端加入计算代码。
