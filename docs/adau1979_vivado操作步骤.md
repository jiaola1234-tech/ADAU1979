# ADAU1979 采集 IP 使用步骤

## 1. 接口结论

ADAU1979 的采样数据不是通过 SPI 输出。SPI/I2C 只用于配置寄存器，采样数据通过 `BCLK + LRCLK + SDATAOUT` 输出。

两片 ADAU1979 同时采集时，Zynq 的 PL 可以同时接收 U1/U2 的 4 路 SDATA：

- `sdata[0]` = U1 `SDATAOUT01` = U1C1/U1C2
- `sdata[1]` = U1 `SDATAOUT02` = U1C3/U1C4
- `sdata[2]` = U2 `SDATAOUT11` = U2C1/U2C2
- `sdata[3]` = U2 `SDATAOUT12` = U2C3/U2C4

IP 输出 `m00_axis_tdata[255:0]`，顺序为：

```text
[31:0]     U1C1
[63:32]    U1C2
[95:64]    U1C3
[127:96]   U1C4
[159:128]  U2C1
[191:160]  U2C2
[223:192]  U2C3
[255:224]  U2C4
```

## 2. 默认配置

- 采样率：48 kHz
- MCLK：24.576 MHz，由 ADAU1979 小板板载晶振提供
- 格式：I2S
- 数据：24 bit，32 bit slot
- 输出：256 bit AXI-Stream
- 控制：PL-I2C
- U1 地址：`0x11`
- U2 地址：`0x31`
- U1：slave
- U2：master，输出 BCLK/LRCLK

### 小板地址电阻必须修改

原理图中 U1、U2 的 `ADDR1` 和 `ADDR0` 都同时装有 10 kΩ 上拉和 10 kΩ 下拉，分压约为 1.65 V。该电平不是可靠的数字 0/1，而且两片器件会得到相同地址，不能在共用的 I2C 总线上分别配置主从模式。

请按下面方式改成 IP 默认使用的两个地址：

```text
U1 = 0x11 (ADDR1=0, ADDR0=0)
  拆除 R11.0、R12.0
  保留 R13.0、R14.0

U2 = 0x31 (ADDR1=0, ADDR0=1)
  拆除 R11.1、R14.1
  保留 R13.1、R12.1
```

焊接后断电测量：U1 的 ADDR1/ADDR0 都应接近 0 V；U2 的 ADDR1 应接近 0 V、ADDR0 应接近 3.3 V。未完成这一步时，PL-I2C 初始化会出现 ACK 错误或两片器件被写入相同配置。

## 3. Vivado 中导入 IP

Vivado 相关文件已经集中放在：

```text
C:/Users/weitong/Desktop/ADAU1979/vivado
```

推荐直接在 Vivado Tcl Console 执行：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/01_clone_and_patch_ad7606_project.tcl
```

它会把原 AD7606 工程复制成新的 ADAU1979 工程，并自动替换 BD 里的采集 IP。生成位置：

```text
C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.xpr
```

生成后可以执行检查：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/03_check_adau1979_project.tcl
```

如果你想手动操作，也可以按下面的方式：

1. 打开现有 AD7606 Vivado 工程。
2. 先打包 IP：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/00_package_adau1979_ip.tcl
```

3. 在当前工程中替换 AD7606：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/02_replace_ad7606_with_adau1979_bd.tcl
```

可选：在 Vivado Tcl Console 里先做一次 IP 独立综合检查：

```tcl
source C:/Users/weitong/Desktop/ADAU1979/scripts/check_adau1979_ip_synth.tcl
```

## 4. Block Design 连接

连接方式：

- `s00_axi_aclk` -> PS 输出的 100 MHz PL clock
- `m00_axis_aclk` -> 同一个 100 MHz PL clock
- `s00_axi_aresetn` -> 对应 100 MHz 的低有效复位
- `m00_axis_aresetn` -> 对应 100 MHz 的低有效复位
- `S00_AXI` -> PS `M_AXI_GP0` 侧 AXI interconnect
- `M00_AXIS` -> AXI DMA 的 `S_AXIS_S2MM`
- `adau_bclk/lrclk/sdata/scl/sda/pd_rst` -> Make External 后接板外引脚

注意：AXI DMA 的 S2MM Stream Data Width 要设置为 `256`。

## 5. XDC 管脚

如果使用黑金/ALINX AX7020，并把 ADAU1979 小板接到 J11 扩展口，直接添加这个约束文件：

```text
C:/Users/weitong/Desktop/ADAU1979/vivado/constraints/ax7020_adau1979_j11.xdc
```

该文件假设 J11 为 3.3V BANK35 IO，接线如下：

```text
ADAU1979 H4-1 SCL        -> AX7020 J11-3  F17 -> adau_scl
ADAU1979 H4-2 SDA        -> AX7020 J11-4  F16 -> adau_sda
ADAU1979 H4-3 BCLK       -> AX7020 J11-5  F20 -> adau_bclk
ADAU1979 H4-4 LCLK/LRCLK -> AX7020 J11-6  F19 -> adau_lrclk
ADAU1979 H4-5 SDATAOUT02 -> AX7020 J11-7  G20 -> adau_sdata[1]
ADAU1979 H4-6 SDATAOUT01 -> AX7020 J11-8  G19 -> adau_sdata[0]
ADAU1979 H4-7 SDATAOUT12 -> AX7020 J11-9  H18 -> adau_sdata[3]
ADAU1979 H4-8 SDATAOUT11 -> AX7020 J11-10 J18 -> adau_sdata[2]
ADAU1979 H4-9 PD/RST     -> AX7020 J11-11 L20 -> adau_pd_rst
ADAU1979 H4-10 GND       -> AX7020 J11 GND
```

如果 Vivado 生成 wrapper 后端口名被自动加了 `_0`，在 Tcl Console 执行 `get_ports *adau*`，然后把 XDC 里的端口名改成实际名称。

注意：J11 是 3.3V FPGA IO，不要接 5V 电平。

替换 AD7606 后，要把旧工程里的 `ad7606.xdc` 禁用或移除；否则旧的 `ADC_PORT_0_ad7606_*` 端口已经不存在，Vivado 可能会报约束找不到对象。

小板 H4 顺序：

```text
1 SCL
2 SDA
3 BCLK
4 LCLK
5 SDATAOUT02
6 SDATAOUT01
7 SDATAOUT12
8 SDATAOUT11
9 PD/RST
10 GND
```

## 6. Vitis 启动流程

裸机测试例程：

```text
C:/Users/weitong/Desktop/ADAU1979/examples/vitis_adau1979_dma_test.c
```

启动顺序：

1. 初始化 AXI DMA，并确认 DMA 是 simple mode。
2. 轮询 IP 状态寄存器 `0x08`，等待 `INIT_DONE=1` 且 `INIT_ERROR=0`。
3. 先启动 AXI DMA S2MM 接收，接收长度必须是 `采样帧数 * 32` 字节。
4. 写采样帧数到 `0x04`。
5. 写 `0x01` 到 `0x00` 启动采集。
6. 等 DMA 完成中断或轮询 DMA 完成。
7. DDR 中每 32 字节是一帧 8 通道数据。

如果 Vitis 编译时报 `XPAR_AXIDMA_0_DEVICE_ID` 或 `XPAR_ADAU1979_CAPTURE_0_C_S00_AXI_BASEADDR` 未定义，打开 BSP 生成的 `xparameters.h`，把例程开头的这两个宏改成你工程里实际的名字：

```c
#define DMA_DEV_ID XPAR_AXIDMA_0_DEVICE_ID
#define ADAU1979_CAPTURE_BASEADDR XPAR_ADAU1979_CAPTURE_0_C_S00_AXI_BASEADDR
```

## 7. 需要上板确认

- 示波器确认 `MCLK=24.576 MHz`。
- 初始化完成后确认 `BCLK=3.072 MHz`、`LRCLK=48 kHz`。
- 确认 `SCL/SDA` 有上拉。
- 确认 U1 地址为 `0x11`、U2 地址为 `0x31`，不要让地址脚停在 1.65 V。
- 如果 `ERROR_COUNT` 增加，优先检查 I2C ACK 和 I2S 位对齐。
