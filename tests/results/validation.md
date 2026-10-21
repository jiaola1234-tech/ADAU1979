# 实际验证记录

日期：2026-10-21（Asia/Shanghai）。以下记录来自本次实际执行，仿真数据不是板卡读回。

| 检查 | 结果 |
|---|---|
| XSim 2022.2 RTL | 加入探测/延时后 14 个场景全部 PASS，逐项输出见 `rtl-summary.txt` |
| 完整 BD 验证 | PASS，8 位寄存器地址、256 位 AXIS，Simple S2MM 拓扑保留 |
| Vivado 2022.2 综合/布局布线/bitstream | PASS，脚本输出 `DUAL_BUILD_PASS` |
| 时序（加入探测/延时后重新实现） | WNS=0.622 ns，TNS=0，WHS=0.013 ns，THS=0，WPWS=3.870 ns，TPWS=0 |
| XSA 导出 | PASS，`build/dual_adau1979.xsa` |
| Vitis 2022.2 ARM Cortex-A9 应用编译/链接 | PASS，`dual_capture.elf`，使用新 XSA 创建/更新的平台 |
| 两份寄存器头 | 字节一致 |
| 构建副本核对 | 以下 8 个实际编译 RTL 副本均与提交主源字节一致，无参考仓库本地路径依赖 |
| 生成路径核对 | 新构建编译清单中仓库外路径为 0；构建脚本重建 BD 的 XCI 元数据，避免复用旧 gen_directory |
| Python 工具语法 | `py_compile` PASS |
| FPGA 上板下载 | PASS：用户检查电源/JTAG 后检测到 arm_dap_0、xc7z020_1；位流、匹配 PS 初始化及 ELF 下载运行成功 |
| 真实双芯片初始化（最新 19:04） | FAIL：COM5/921600，0x31 探测及配置校验通过；加入 100 ms 延时后，0x11 配置前地址探测仍 NACK |
| 初始化失败采集门控 | PASS：init_done=0、init_error=1、START=0、累计 AXIS 帧=0，DMA 未启动 |
| 60 秒双芯片实采/逐路信号注入 | 尚未完成，当前被 0x11 无 ACK 阻断，不能宣称双芯片上板通过 |

- `adau1979_capture_core.v`: exactly one compiled copy, byte-identical to the delivered source.
- `adau1979_capture_v1_0.v`: exactly one compiled copy, byte-identical to the delivered source.
- `adau1979_capture_v1_0_S00_AXI.v`: exactly one compiled copy, byte-identical to the delivered source.
- `adau1979_i2c_init.v`: exactly one compiled copy, byte-identical to the delivered source.
- `adau1979_i2s_rx.v`: exactly one compiled copy, byte-identical to the delivered source.
- `axis_fifo_256.v`: exactly one compiled copy, byte-identical to the delivered source.
- `i2c_master_read8.v`: exactly one compiled copy, byte-identical to the delivered source.
- `i2c_master_write8.v`: exactly one compiled copy, byte-identical to the delivered source.

成功仿真的两个器件实际模型读回与标志：

| 逻辑设备 | 7 位地址 | 角色 | 00 | 01 | 04 | 05 | 06 | valid | error | PLL | write_ACK | verified |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 11 | master | 01 | C3 | BF | 02 | 01 | 1F | 00 | 1 | 1 | 1 |
| B | 31 | slave | 01 | C3 | BF | 02 | 00 | 1F | 00 | 1 | 1 | 1 |

故障注入：B=0x31 NACK 时在配置前地址探测失败，阶段标记 FF、code=1，未写配置、未放行采集；
B PLL 始终不锁时失败寄存器 0x01、code=2，未放行采集；
B 0x04 读回 BE（期望 BF）时 code=3，读取成功 valid=1，比较错误 error=1，未放行采集。
A/B 角色交换与 A-only 连续模式均通过对应仿真。
新增 A=0x11 地址探测 NACK、延迟满 100 ms 才应答、地址探测 ACK 后首笔写配置 NACK 三项。
仿真按周期断言从机 verified 至主机首笔事务至少为 CLK_HZ/10，
每颗成功探测只有地址字节、其后恰好 15 笔配置写入。
每次初始化仿真公共 PD/RST 只释放一次，两个 I²C 引擎未并发，没有两个音频主机同时有效。

流仿真每个配置验证 3072 帧，共三包；每帧八个字逐项核对，并在背压时检查
TDATA/TVALID/TLAST 保持。默认映射和交换映射均通过；单芯片恢复模式保持前四字有效、后四字零。
AXI 仿真覆盖新寄存器银行、写高地址不能改旧控制寄存器、NACK 门控、START 跨包保持和累计帧数。

本地生成文件（bit/xsa/elf/dcp、工具日志、BSP 和 IP 缓存）按目标仓库既有约定忽略，不提交。
可用 `scripts/build_dual.tcl`、`scripts/build_dual_vitis.tcl` 重建；
`tests/board_acceptance.py` 已实际连接 COM5 执行；初始化失败返回非零，未将未执行的 60 秒计数检查写为 PASS。

## 加入 100 ms 延时和地址探测后的最新实测

2026-10-21 19:04（Asia/Shanghai）。重新完成 14 项 XSim、Vivado 实现/位流/XSA、
Vitis 编译链接，核对平台 XSA 与导出文件、应用源码与交付文件字节一致。
首次 JTAG 下载在 ps7_init 报 Invalid context，重连并在 PS 初始化前停止 Cortex-A9 #0 后，
整套位流/PS 初始化/ELF 下载运行成功（BOARD_DOWNLOAD_PASS）。

`python tests/board_acceptance.py --port COM5 --seconds 60 --output build/board-probe-acceptance.txt`
实际返回非零，完整串口记录见 `board-probe-init.txt`：

| 设备 | 角色 | 探测 attempted/done/ACK | 探测状态 | 配置结果 |
|---|---|---|---|---|
| A=0x11 | 主机 | 1 / 1 / 0 | 00001103 | 地址 NACK，未发送寄存器/数据，未执行 PLL 和配置读回 |
| B=0x31 | 从机 | 1 / 1 / 1 | 00003107 | write_ACK=1、PLL=1、verified=1，读回 01/C3/BF/02/00，valid=1F/error=00 |

本版在 B 校验完成后保持公共复位释放，延时 100 ms，再对 A 发地址探测。
INIT FAIL code=1、addr7=11、reg=FF、actual=00、expected=01：
FF 是地址探测阶段标记，00/01 表示实际未 ACK/预期 ACK，不是寄存器数据。
此前的“首笔配置写入 NACK”进一步定位为“配置之前地址已经无 ACK”；
100 ms 延时未解决当前板卡的 0x11 应答问题，具体物理原因仍未确定。
程序没有放行 DMA，60 秒连续实采及逐路信号注入仍未完成。

## 加入探测/延时前的实际板卡诊断

2026-10-21 18:08（Asia/Shanghai），用户确认两颗共用时钟/复位、
0x11→SDATA[2]/[3]、0x31→SDATA[0]/[1]；该接线描述不等于逐路信号注入验证。
完整串口文本见 `board-init.txt`。此前 115200 无响应，核对 BD 后确认 UART1 为 921600；
验收脚本和说明已修正，未改动硬件时钟或串口配置。

| 逻辑设备 | 地址 | 配置角色 | status | 写 ACK | PLL | verified | valid | error | 00/01/04/05/06 实际读回 |
|---|---|---|---|---|---|---|---|---|---|
| A | 0x11 | master | 00238000 | 0 | 未执行 | 0 | 00 | 00 | 均未执行，银行中的 00 是复位值，不能视为读取成功 |
| B | 0x31 | slave | 0062F07E | 1 | 1 | 1 | 1F | 00 | 01 / C3 / BF / 02 / 00 |

JTAG 核对 ABI=AD790208、mapping=00002701，failure=00019100：
有效位=1、code=1（总线失败）、addr7=11、reg=00。写引擎 ACK bits=000。
失败汇总的 actual=FF 是写失败哨兵值，expected=00 是本次尝试写入的数据；
两者都不是 A 的寄存器读回。A 在首笔写入即失败，尚未执行主机设置 0x06=01。
0x31 已完整通过且未再次公共复位；尚不能仅凭 NACK 确定 0x11 的物理故障原因。

仍需：排查 0x11 芯片实际供电、PD/RST、SCL/SDA 连通及地址绑带，
两颗通过后重跑 `python tests/board_acceptance.py --port COM5 --seconds 60`，
核对 DMA/FIFO/同步错误/DMASR，并逐路注入确认八个物理通道。
