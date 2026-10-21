# ADAU1979

双 ADAU1979 八通道连续采集的当前入口、地址/角色/接线表、构建及验收方法见
[双芯片连续采集说明](docs/dual-adau1979.md)。

硬件：`scripts/build_dual.tcl`；软件：`scripts/build_dual_vitis.tcl`；
应用主源：`ws1/design_1_wrapper_lianxu_/src/main.c`。
使用 Vivado/Vitis 2022.2，保留 256 位数据通路和 8×1024 帧 Simple S2MM 连续环。

原有工程与应用保留，具体历史状态请参见原 docs；双芯片的验证范围以
[本次验证记录](tests/results/validation.md) 为准。
