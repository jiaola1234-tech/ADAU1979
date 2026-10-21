# 实际验证记录

日期：2026-10-21（Asia/Shanghai）。以下记录来自本次实际执行，仿真数据不是板卡读回。

| 检查 | 结果 |
|---|---|
| XSim 2022.2 RTL | 11 个场景全部 PASS，逐项输出见 `rtl-summary.txt` |
| 完整 BD 验证 | PASS，8 位寄存器地址、256 位 AXIS，Simple S2MM 拓扑保留 |
| Vivado 2022.2 综合/布局布线/bitstream | PASS，脚本输出 `DUAL_BUILD_PASS` |
| 时序 | WNS=0.617 ns，TNS=0，WHS=0.051 ns，THS=0，WPWS=3.870 ns，TPWS=0 |
| XSA 导出 | PASS，`build/dual_adau1979.xsa` |
| Vitis 2022.2 ARM Cortex-A9 应用编译/链接 | PASS，`dual_capture.elf`，使用新 XSA 创建/更新的平台 |
| 两份寄存器头 | 字节一致 |
| 构建副本核对 | 以下 8 个实际编译 RTL 副本均与提交主源字节一致，无参考仓库本地路径依赖 |
| Python 工具语法 | `py_compile` PASS |
| FPGA 上板 | 未执行：检测到 Digilent 适配器，但打开目标报 `Labtools 27-2269 No devices detected` |
| 60 秒双芯片实采/逐路信号注入 | 未执行，等待真实 FPGA、两颗芯片及接线条件 |

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

故障注入：B=0x31 NACK 时失败寄存器 0x00、code=1，未放行采集；
B PLL 始终不锁时失败寄存器 0x01、code=2，未放行采集；
B 0x04 读回 BE（期望 BF）时 code=3，读取成功 valid=1，比较错误 error=1，未放行采集。
A/B 角色交换与 A-only 连续模式均通过对应仿真。
每次初始化仿真公共 PD/RST 只释放一次，两个 I²C 引擎未并发，没有两个音频主机同时有效。

流仿真每个配置验证 3072 帧，共三包；每帧八个字逐项核对，并在背压时检查
TDATA/TVALID/TLAST 保持。默认映射和交换映射均通过；单芯片恢复模式保持前四字有效、后四字零。
AXI 仿真覆盖新寄存器银行、写高地址不能改旧控制寄存器、NACK 门控、START 跨包保持和累计帧数。

本地生成文件（bit/xsa/elf/dcp、工具日志、BSP 和 IP 缓存）按目标仓库既有约定忽略，不提交。
可用 `scripts/build_dual.tcl`、`scripts/build_dual_vitis.tcl` 重建；
`tests/board_acceptance.py` 是待接板执行的 60 秒 UART 检查工具，本次没有将它的结果写为 PASS。
