# FPGA ADAU1979 I²C diagnostic delivery

基线提交：`ab4f1db`（本地分支，未推送）。实际 XPR 入口为
`vivado/adau1979_lwip/adau1979_lwip.xpr`；其源文件和 `vivado/ad_slave/ad_slave.xpr`
都引用 `ip_repo/adau1979_capture_1.0/hdl`。因此本次修改落在该目录，而不是只改
未接入构建的 `adau1979_capture_slave_1.0`。

## 已修改

* `i2c_master_read8.v`：寄存器地址 ACK 后增加完整 SCL-low 阶段，再产生
  repeated START；读地址 ACK 后同样结束 ACK 时钟低相位再进入接收。末字节仍由主机
 发送 NACK 后 STOP。
* 将已有增强诊断逻辑合并到实际引用的 IP：复位低/释放各 100 ms 保留；地址扫描、
  PLL 读地址 ACK/数据有效/锁定超时分类、每个写事务三段 ACK、首次 verify 失败锁存、
  64 项事件日志和 AXI 读回寄存器均已接入。正常写 ACK 失败会置 `init_error`，不会
  报告 `init_done`。
* 原有 AXI 偏移 0x00--0x28 保留；新增 0x2C--0x3C：失败摘要、状态/读回摘要、
  日志索引及 64-bit 日志低/高字。日志事件包含写事务（设备/寄存器/数据/三 ACK）、
  PLL 读、地址扫描、读回和初始化结束。
* `i2c_scl_dbg` 明确标注为兼容性的 fabric 驱动意图（`~adau_scl_oe_n`），不是
  实际 SCL 引脚回读；当前 XPR 的顶层 SCL 仍是 output-only，不能据此证明线上为高。

## 仿真与检查

`addebug/sim/i2c_master_read8_tb.v` 提供开漏/上拉读时序回归骨架，要求两次 START、
一次 STOP、读地址 0x23、末字节主机 NACK，并拒绝 ACK 高相位直接跳 repeated START。
当前环境未发现 `iverilog`、`verilator` 或 Vivado 可执行文件，因此本次未执行 RTL 仿真、
综合、实现或 DRC；测试平台需要在装有 Vivado/xsim（或 Icarus）的机器上运行。模型不应
被改成迎合旧错误时序。

## 重建

1. 在 Vivado 打开 `vivado/adau1979_lwip/adau1979_lwip.xpr`。
2. 运行 `vivado/scripts/05_refresh_adau1979_ip.tcl`，确认 IP 版本和 HDL 来源为
   `ip_repo/adau1979_capture_1.0/hdl`，重新生成 BD/IP output products。
3. 运行 `vivado/scripts/06_direct_build_bitstream.tcl`，执行 validate、综合、实现、
   bitstream 和 XSA 导出；再用该 XSA 重建 Vitis BSP/application。

## 上板顺序

先只读状态/日志，记录 U1/U2 配置地址和访问顺序；分别执行“只重新 I²C”和“硬件复位后
再测”，等待值先用默认 100 ms，再用 1 s 诊断构建。预期首个探测写帧为 U1 `0x22,0x00,STOP`，
随后 U2 `0x62,0x00,STOP`。若 U1 地址阶段 NACK 而 U2 三段 ACK，支持“U1 物理路径/复位
状态或器件未应答”假设，但不能单凭 FPGA 结果区分；交换访问顺序后结果若随物理位置保持，
更支持板级/复位路径问题。只有逻辑分析仪同时确认真实 SCL/SDA 和 PD/RST 后，才能排除
IOBUF/引脚连接问题。

## 结论边界

已确认缺陷是 repeated START 前缺少 ACK 结束低相位；它影响后续寄存器读取，不解释首次
写地址 NACK。诊断扫描、日志和复位等待是可配置/可观测手段，不是“必须先探测才能工作”的
根因结论。U1 无 ACK 是否已解决仍需上板波形和日志验证。
