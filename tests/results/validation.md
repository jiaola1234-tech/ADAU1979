# 实际验证记录

日期：2026-10-21（Asia/Shanghai）。以下记录来自本次实际执行，仿真数据不是板卡读回。

| 检查 | 结果 |
|---|---|
| XSim 2022.2 RTL | 当前输出顺序及反转 LRCLK 场景共 18 项；最终输出见 `rtl-summary.txt` |
| 完整 BD 验证 | PASS，8 位寄存器地址、256 位 AXIS，Simple S2MM 拓扑保留 |
| Vivado 2022.2 综合/布局布线/bitstream | PASS，脚本输出 `DUAL_BUILD_PASS` |
| 时序（0x31 前四路 / 0x11 后四路） | WNS=1.316 ns，TNS=0，WHS=0.035 ns，THS=0，WPWS=3.870 ns，TPWS=0 |
| XSA 导出 | PASS，`build/dual_adau1979.xsa` |
| Vitis 2022.2 ARM Cortex-A9 应用编译/链接 | PASS，`dual_capture.elf`，使用新 XSA 创建/更新的平台 |
| 两份寄存器头 | 字节一致 |
| 构建副本核对 | 以下 8 个实际编译 RTL 副本均与提交主源字节一致，无参考仓库本地路径依赖 |
| 生成路径核对 | 新构建编译清单中仓库外路径为 0；构建脚本重建 BD 的 XCI 元数据，避免复用旧 gen_directory |
| Python 工具语法 | `py_compile` PASS |
| FPGA 上板下载 | PASS：用户检查电源/JTAG 后检测到 arm_dap_0、xc7z020_1；位流、匹配 PS 初始化及 ELF 下载运行成功 |
| 真实双芯片初始化（旧顺序，重焊后 19:28） | PASS：COM5/921600，0x11 主机、0x31 从机均通过地址 ACK、全部配置写 ACK、PLL 和五项读回 |
| 初始化失败采集门控 | PASS：init_done=0、init_error=1、START=0、累计 AXIS 帧=0，DMA 未启动 |
| 60 秒双芯片连续实采（旧顺序） | PASS：61 条进度记录，首末至少 60 秒；DMA 46→2861，FIFO 溢出/同步错误/I²C 错误均为 0，DMASR=0 |
| 当前芯片组顺序上板（极性修正前） | PASS：恢复 JTAG 后下载，61 条进度、至少 60 秒；DMA 46→2861，I²S/AXIS 均增加 2882395，全部错误为 0 |
| q 停止 | PASS：串口返回 Capture stopped，环形缓冲保留 |
| 物理信号对应（极性修正前） | 发现不符：用户确认 0x31 VIN1/CH1 注入 1 kHz/1 Vpp，强信号出现在 ch2；其余七路待注入 |

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
`tests/board_acceptance.py` 已实际连接 COM5 执行；早先初始化失败返回非零，重焊后完整 60 秒检查返回 0。

## 当前输出顺序：0x31 前四路、0x11 后四路

按用户要求调整逻辑 A/B 与物理地址、数据线的对应，保持物理 0x11 为时钟主机。
主从物理初始化顺序仍是先 0x31 从机、等待 100 ms、再 0x11 主机；共享复位及 DMA 环不变。

| 逻辑设备 | 地址 | 角色 | SDATA | DDR / 打印 |
|---|---|---|---|---|
| A | 0x31 | slave，06=00 | 0/1 | word0..3 / ch1..4 |
| B | 0x11 | master，06=01 | 2/3 | word4..7 / ch5..8 |

BD 主源与实际导出的 resolved_bd.tcl 参数一致：DEVICE_A_ADDR=49、DEVICE_B_ADDR=17、
AUDIO_MASTER=1、A_SDATA=0/1、B_SDATA=2/3；映射寄存器预期 00007203。
所有编译路径均在仓库内，八个 RTL 编译副本与交付源字节一致，平台 XSA 与导出文件一致。
Vitis 主循环 DMA 逻辑未改；增加初始化后的配置打印，使 UART 日志能记录实际映射。

18 项 XSim 全部通过（含反转 LRCLK 场景），新增当前地址/角色组合初始化，以及当前映射 AXI 成功和 0x31 NACK 门控。
四根线可区分数据的 SWAP=1 流仿真检查当前顺序的 3072 帧、符号扩展、3 个 TLAST 和背压稳定。
XSCT 直接执行配置脚本，确认默认双芯片配置和 single 参数恢复的原 0x11 主机/SDATA[2]/[3] 配置均正确。
完整 Vivado/Vitis 构建通过，时序见表。

19:44 JTAG 下载未发现 APU，只有 whole scan chain (DR shift through all zeroes)；
Hardware Manager 降至 1 MHz 重扫仍报 No devices detected。
用户重新连接后重试下载成功，实际完成当前芯片组顺序的 60 秒采集。
61 条进度；DMA 46→2861，I²S 855954→3738349，AXIS 48044→2930439，
I²S 与 AXIS 均增加 2882395。FIFO 水位快照均为 0，溢出/同步/I²C/DMA 错误全程为 0。
q 停止确认。记录见 `board-reordered-60s-uart.txt`、`board-reordered-60s-summary.json`。

用户确认 0x31 VIN1/CH1 接入 1 kHz、1 Vpp，原输出却为 ch2。停止后 JTAG 读取物理 DDR，
状态 active=6、completed=2862、last=5，与 UART 末值相符；排除 active6，
按 7/0/1/2/3/4/5 连接七个完整块，共 7168 帧，57344 个字符号扩展全部正确。
ch2 AC RMS 约 4306289 ADC 码，其余通道最大约 461 码；
末块过零中位周期估算 1000.03 Hz（假定 48 kHz）。部分样本触及满幅码，不能判定幅度或失真合格。

用户提供的图 22 是标准 I²S：低电平 CH1/3、高电平 CH2/4，MSB 延后一个 BCLK。
但实际两颗 0x04=BF，bit7 LR_POL=1；
Analog Devices 维护的 [Linux ADAU1977/1978/1979 驱动](https://github.com/torvalds/linux/blob/master/sound/soc/codecs/adau1977.c)
在 BLOCK_POWER_SAI 定义 bit7 为 LR_POL，并由 set_dai_fmt 的 invert_lrclk 控制。
当前接收器原参数 LR_POLARITY=1 选择低时隙先，与反转后的高时隙 CH1 不匹配。
因此只将双芯片工程已有 LR_POLARITY 参数设为 0，高→低组成一个公共完整帧；
不修改采样边沿、同步器、I²S 延迟、ADC 寄存器脚本或 DMA。
single 恢复原 LR_POLARITY=1，保留原单芯片采集行为，物理通道仍需核验。
新增反转 LRCLK 仿真：每线/时隙/帧均有不同样本，核对 3072 帧、3 次 TLAST、符号扩展、背压，
能发现仅交换字而将相邻帧配对的错误。此后的构建与实测单独记录。

## 0x11 重焊后的首次 60 秒连续采集实测（19:28，调整顺序前）

2026-10-21 19:28–19:29（Asia/Shanghai）。用户重新焊接 0x11 后，
重新通过 JTAG 加载提交 `86b83667d0bd0f3a9c7994fc12c35e1478a76835` 的同一位流与 ELF，
下载成功。本次没有修改 RTL、应用或配置，没有再次构建或回退单芯片模式。
仍使用从机先配置、100 ms 间隔、配置前地址探测及八块连续 DMA 环。

| 实际设备 | 角色 | probe status | device status | 00 | 01 | 04 | 05 | 06 | valid/error | PLL/write_ACK/verified |
|---|---|---|---|---|---|---|---|---|---|---|
| A=0x11 | master | 00001107 | 0023F07E | 01 | C3 | BF | 02 | 01 | 1F / 00 | 1 / 1 / 1 |
| B=0x31 | slave | 00003107 | 0062F07E | 01 | C3 | BF | 02 | 00 | 1F / 00 | 1 / 1 / 1 |

命令：`python tests/board_acceptance.py --port COM5 --seconds 60 --output build/board-resolder-acceptance.txt`。
退出码 0，输出 `PASS UART counters for 60+ seconds`。脚本使用单调时钟，
在首条进度后继续观察至少 60 秒；共有 61 条进度、607 条八通道样本打印。
原始串口文本见 `board-60s-uart.txt`，计数和已下载 bit/elf 的 SHA-256 见 `board-60s-summary.json`。

| 指标 | 首条 | 末条 | 结论 |
|---|---|---|---|
| DMA 完成块 | 46 | 2861 | 每条持续增长，区间增加 2815 块 |
| I²S 帧 | 1308201 | 4190597 | 增加 2882396 |
| AXIS 成功帧 | 48044 | 2930440 | 同样增加 2882396，与 I²S 区间增量一致 |
| FIFO 水位 | 0 | 0 | 所有进度快照均为 0；没有测量两次快照之间的峰值 |
| FIFO 溢出 | 0 | 0 | 全程不增长 |
| I²S 同步错误 / I²C 错误 / err_total | 0 / 0 / 0 | 0 / 0 / 0 | 全程为 0 |
| DMASR | 00000000 | 00000000 | 所有进度行均无 DMA 错误位 |
| display_skipped_blocks | 33 | 2253 | 100 ms 显示取最新块所跳过的旧块，不是采集丢帧 |

对全部 607×8 个已打印字做 24→32 符号扩展检查均通过，八个打印位置均出现变化。
脚本末尾发送 q，实际收到 `Capture stopped; DDR ring retains the most recent 8 blocks`。
仅据这些数字不能确认八个物理输入的顺序、串音或模拟性能；
用户确认暂时没有信号源，逐路输入测试留待具备条件后执行。

## 加入 100 ms 延时和地址探测后的首次实测（19:04，重焊前）

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

当时待排查的 0x11 无 ACK 问题在用户重焊后不再复现，最新连续采集结果见前文；
尚待逐路注入确认八个物理通道。
