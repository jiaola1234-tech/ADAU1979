# ADAU1979 单器件调试模式

`adau1979_i2c_init.v` 现在支持通过两个已有的 IP 地址参数选择单器件调试，
不需要修改 PCB 电阻，也不需要新增 AXI 寄存器。

## 参数设置

在 Vivado 的 `adau1979_capture_0` IP 配置窗口中设置：

| 目的 | `U1_I2C_ADDR` | `U2_I2C_ADDR` |
|---|---:|---:|
| 只调 U1 | `0x11` | `0x11` |
| 只调 U2 | `0x31` | `0x31` |
| 恢复双器件 | `0x11` | `0x31` |

判断规则是两个参数相等时进入单器件模式。单器件模式只执行脚本的前 15 笔写入，
并且只轮询所选地址的 PLL；两个参数不相等时保持原来的 U1→U2 双器件流程。

## 每次切换地址后的 Vivado 顺序

1. 打开 `adau1979_lwip.xpr`。
2. 双击 BD 中的 `adau1979_capture_0`。
3. 修改 `U1_I2C_ADDR` 和 `U2_I2C_ADDR`，点击 `OK`。
4. `Generate Output Products`。
5. `Run Synthesis`，确认通过后 `Run Implementation`。
6. `Generate Bitstream`。
7. 重新导出包含 bitstream 的 XSA（如果要运行 Vitis）。
8. Hardware Manager 下载本次生成的 bit，并加载同一次实现生成的 ltx。

切换地址后不能只重新运行 Vitis；地址参数在 FPGA 综合结果中，必须重新生成 bitstream。

## 单器件测试判据

单调 U1 时，ILA/串口应只看到 `last_dev_addr=0x11`；单调 U2 时应只看到
`last_dev_addr=0x31`。每笔写事务的 `ACK_BITS` 期望为 `3'b111`，最终状态应为：

```text
init_busy = 0
init_done = 1
init_error = 0
```

如果单调 U1 仍然失败，而单调 U2 成功，说明问题已经与“双器件初始化顺序”隔离开，
应继续检查 U1 的地址脚、局部 SDA/SCL、PD/RST、供电或器件状态。

