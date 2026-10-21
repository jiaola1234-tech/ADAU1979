# 双 ADAU1979 八通道连续采集

本次集成以目标仓库 `jiaola1234-tech/ADAU1979` 的 `main` 提交
`1042461f01a76b6c1cc35a39c3c14a39963878bb` 为基础。
连续采集参考 `jiaola1234-tech/adau1979-single-ad-test` 的
`d81b9c7`，保留 Simple S2MM 中断、8 块 DDR 环形缓冲、每块 1024 帧、
每帧 32 字节。没有迁回旧的单次 DMA 应用。

## 实际构建入口

通过平台脚本、XPR、BD 和 IP VLNV 交叉核对：参考仓库的
`ws1/design_1_wrapper_lianxu/platform.tcl` 指向
`vivado/adau1979_lwip/design_1_wrapper_lianxu.xsa`；对应工程是
`vivado/adau1979_lwip/adau1979_lwip.xpr`，BD 使用
`user.org:user:adau1979_capture:1.1`，源码来自
`ip_repo/adau1979_capture_1.0/hdl`。
`vivado/ad_slave` 的 BD 使用 `adau1979_capture_slave:1.1.3`，不是此应用的硬件入口。
状态文档和 XPR 中 AutoDisabled 的旧源码条目不能作为参与构建的依据。

最终交付的入口：

| 项目 | 路径/标识 |
|---|---|
| 硬件构建 | `scripts/build_dual.tcl`，Vivado 2022.2，xc7z020clg400-2 |
| 构建配置 | `scripts/dual_config.tcl` |
| BD 主源 | `vivado/dual_adau1979/design_1.bd`，从上述实际连续采集 BD 迁移 |
| IP 主源 | `ip_repo/adau1979_capture_1.0/hdl`，VLNV 升为 `user.org:user:adau1979_capture:1.2` |
| IP 打包 | `ip_repo/adau1979_capture_1.0/scripts/package_ip.tcl`、`component.xml`、`xgui/adau1979_capture_v1_2.tcl` |
| 有效 XDC | `vivado/dual_adau1979/adau1979.xdc` |
| Vitis 应用主源 | `ws1/design_1_wrapper_lianxu_/src/main.c` |
| 应用构建 | `scripts/build_dual_vitis.tcl`，生成 `build/vitis/dual_capture` |
| 交付 Vitis 工程 | `scripts/build_adau1979_vitis.tcl`，平台 `adau1979_platform`，应用 `adau1979` |
| 软件寄存器头 | 上述 src 内与 IP drivers 内的 `adau1979_capture.h`，两者保持一致 |

构建脚本生成 `build/vivado/dual_adau1979.xpr`、`build/dual_adau1979.xsa`，
仅在 `build` 内生成 BD/IP/BSP/ELF，使用仓库内相对路径。
旧的 Vivado 工程和 Vitis 应用保留，不是本次双芯片构建入口。
交付下载文件由同一 XSA/位流生成：`build/adau1979.xsa`、`build/adau1979.bit`、
`build/vitis_adau1979/adau1979/Debug/adau1979.elf`；使用 `scripts/program_adau1979.tcl` 下载。
不要使用旧平台缓存，也不要直接重新导入含原机器绝对路径的旧 `.prj`。

## 地址、角色与接线

逻辑设备 A 对应输出前四路，逻辑设备 B 对应输出后四路。
当前配置为 A=0x31、B=0x11，0x11 保持已验证的时钟主机角色；
**逻辑编号、I²C 地址、原理图 U1/U2 位号、SDATA 下标是独立概念**。
历史地址绑带说明曾按 U1=0x11、U2=0x31 记录，但不足以证明当前实物位号与数据线对应。
当前实物路径保持 `0x11 + sdata[2]/[3]`、`0x31 + sdata[0]/[1]`，不会根据 U1/U2 字样交换数据线。
上板前需以电阻绑带和通断测量确认此表；软件能读回地址/角色/映射，不能识别物理丝印。

| 逻辑芯片 | 默认 7 位地址 | 音频角色 | CH1/2 数据线 | CH3/4 数据线 | DDR 字 |
|---|---|---|---|---|---|
| A：前四路 | 0x31 | 从机，0x06=0x00 | sdata[0]，Y16，H4 pin6 | sdata[1]，Y17，H4 pin5 | word0..3 / ch1..4 |
| B：后四路 | 0x11 | 主机，0x06=0x01 | sdata[2]，V15，H4 pin8 | sdata[3]，W15，H4 pin7 | word4..7 / ch5..8 |

| 公共信号 | FPGA 管脚 | 说明 |
|---|---|---|
| SCL | W19 | 外部上拉，开漏；两个器件共用 |
| SDA | W18 | 外部上拉，开漏；两个器件共用 |
| BCLK | U15 | 唯一音频主机输出，其余器件和 FPGA 输入 |
| LRCLK | U14 | 同上，公共帧边界 |
| PD/RST | Y14 | 两颗共用，每次完整初始化只复位一次 |
| MCLK | 保持成功单芯片的外部来源 | 本采集工程不产生 MCLK；两颗采用同一已验证时钟方案 |

旧 XDC 注释把 BCLK/LRCLK 写为 R14/P14，实际 `PACKAGE_PIN` 为 U15/U14。
本交付保留实际约束并修正注释；H4 数据线位置来自原接线说明，
新增芯片的实物接线仍必须按表核实。

在 `scripts/dual_config.tcl` 分别设置 `DEVICE_A_ADDR`、`DEVICE_B_ADDR`（当前十进制 49、17），
`AUDIO_MASTER`（0=A、1=B，当前为 1），以及 `A_SDATA0/1`（当前 0/1）、`B_SDATA0/1`（当前 2/3）。
实际工程配置以该脚本和 BD 实例参数为准；可复用 IP 的 HDL 缺省参数仍保留原始选项。
I²C 引擎始终接收 7 位地址，内部追加 R/W；不能传入 0x22/0x23。
构建时检查地址取自合法绑带候选 0x11/0x31/0x51/0x71、地址不同、四线不重复、主机唯一。
要交换角色，只修改 `AUDIO_MASTER`，不会改变字顺序或数据线。
当前双芯片配置还显式设置 `LR_POLARITY=0`，匹配实际保留的 ADC `0x04=0xBF`
中的 `LR_POL=1`：CH1/3 在 LRCLK 高时隙，随后低时隙为 CH2/4。
这是接收器已有参数，选择整帧起点，不是事后交换相邻帧中的字。
`single` 恢复保留原已验证配置的 `LR_POLARITY=1`；其物理通道顺序仍需信号注入核验。

## 初始化和数据行为

公共复位后先完整配置/校验从机，再配置/启动并校验主机，两个 I²C 引擎不会同时运行。
每颗在配置前先独立发送 `START → addr-W → ACK → STOP` 探测地址，
不发送寄存器或数据字节，不以写寄存器代替地址探测。地址保持 7 位。
从机完成校验后额外等待 **100 ms**，公共 PD/RST 保持高、两个 I²C 引擎空闲，
再探测并配置主机（默认 0x11）。这段等待只发生在初始化切换器件时，不进入连续 DMA 包边界。
地址探测失败立即中止初始化，串口分别打印 attempted、done、address_ACK；
失败寄存器字段 `FF` 代表地址探测阶段，没有访问实际寄存器 0xFF。
保留原寄存器脚本：0x01=0x43、0x04=0xBF、0x05=0x02，
0x07=0x10、0x08=0x32、0x0A..0x0D=0xA0、0x09=0xF0、0x0E=0x02、0x1A=0x0F，
最后 0x00=0x01；只按角色改变 0x06。
维持原 48 kHz、24 位 I²S、每声道 32 个 BCLK、增益和高通设置。
PLL 最多轮询 20 次，随后逐项比较 0x00/01/04/05/06。
预期读回为 `01 C3 BF 02 01`（主机）或 `01 C3 BF 02 00`（从机）；
C3 包含 PLL_LOCK bit7 和原配置的低 7 位 43。
每项分别记录实际值、总线读取成功、失败标志；读成功但值不匹配时 valid=1/error=1。
失败立即停止本次初始化，保留地址/寄存器/原因，尚未处理的器件会显示未验证。
只有启用的所有器件都通过，`init_done` 才有效；硬件和软件都据此禁止未验证采集。

接收器保留原上升沿采样、同步器、I²S 延迟和左右时隙判定。
接收器 `LR_POLARITY=1` 时低时隙在前，`0` 时高时隙在前；
当前双芯片选择高时隙起始，以匹配 ADC 已启用的 LRCLK 反转。
I²S 一个 BCLK 延迟、上升沿采样及完整首时隙有效标记保持不变，避免混合相邻帧。
八个 24 位值统一符号扩展，256 位低字在 DDR 中先出现，目标物理通道顺序为：

`0x31 CH1, 0x31 CH2, 0x31 CH3, 0x31 CH4, 0x11 CH1, 0x11 CH2, 0x11 CH3, 0x11 CH4`。

TLAST 每 1024 个成功 AXIS 握手出现一次；包边界只重置包内索引，
不清 FIFO、不重新初始化、不清 START，也不重置 I²S 接收器。
ISR 仅确认中断、登记已完成块、提交下一个环形 DMA 地址。
主循环约每 100 ms 打印最近完成块最后一帧的八通道十六进制符号扩展样本，
每秒打印 DMA 累计块、I²S 帧、AXIS 成功帧、FIFO 水位/溢出、同步错误、I²C 错误、DMASR。
使用硬件时间计数器，串口耗时不会被误算为固定 1 ms。

串口显示主动跳过旧块计为 `display_skipped_blocks`，这是显示降采样；
`fifo_overflows` 增量才表示 FIFO 因无法背压 ADC 而丢弃了输入帧，
同步错误增量表示输入帧结构异常；这些计数不能互相替代。
I²S 总帧数从 FPGA 复位累计，包含正式采集前的时钟帧，
因此不可直接拿绝对值与 `dma_blocks*1024` 比较，需比较运行区间增量并考虑 FIFO/在途块。
每 1024 帧约 21.333 ms，预期 46.875 块/秒，60 秒约 2812/2813 块。

缓存处理：启动前一次性 flush 全环；之后 CPU 不写 DMA 环。
主循环仅在很短的 IRQ 临界区内选择最新完成块，invalidate 并复制最后 32 字节到私有样本数组，
然后恢复 IRQ 再打印。临界区内 DMA 只能继续写当前块，ISR 无法把完成块重新提交。
不会从 DMA 当前块读取，也不会在 UART 打印过程中持有即将复用的环形内存指针。
按 q/Q 停止；DMA 错误或 10 秒无进展也会关闭采集并复位 DMA。

本次同时修复两个由仿真证实的问题：

- I²C 读取的 ACK 阶段提前增加字节索引，导致跳过寄存器地址。现按刚完成的字节调度，
  保证完整的 `addr-W → reg → repeated START → addr-R → data`。
- FIFO 的 count 不含输出寄存器，原 can_load 条件却可能在空 RAM 同周期写入时读取旧值。
  现在只有 RAM 确有排队数据、输出为空或已握手时才加载；不依赖 BRAM 写穿透。

## AXI 地址兼容性

IP 基址维持 `0x44A00000`，DMA 基址维持 `0x40400000`。
原 `0x00..0x5C` 布局保留，包括 0x40..0x54 的逻辑 A 诊断（当前为 0x31）；0x10 仍是原包内索引。
地址译码覆盖完整 8 位 AXI 地址，打包、顶层、AXI 子模块及 BD 均为 8 位。
DMA 仍是 Simple S2MM，输入 256 位、TKEEP=32'hFFFFFFFF，未改变 BD DMA/互连拓扑。

| 新偏移 | 内容 |
|---|---|
| 0x60 | ABI=0xAD790208，旧硬件会被软件拒绝 |
| 0x64 | dual[0]、master-index[1]、A0[8:7]、A1[10:9]、B0[12:11]、B1[14:13] |
| 0x80 / 0xA0 | A / B 状态 |
| 0x84..0x94 / 0xA4..0xB4 | A / B 的 0x00、01、04、05、06 实际读回，每 4 字节一项 |
| 0xB8 | 失败寄存器[7:0]、7 位设备地址[14:8]、有效[15]、原因[17:16] |
| 0xBC | 累计成功 AXIS 握手帧数 |
| 0xC0 / 0xC4 | A / B 配置前地址探测：attempted[0]、done[1]、ACK[2]、addr7[14:8]，只读 |

设备状态：busy[0]、done[1]、valid[6:2]、error[11:7]、PLL[12]、
全部写 ACK[13]、全部校验通过[14]、启用[15]、音频主机[16]、地址[23:17]。
失败原因：1=I²C 写或读失败，2=PLL 超时，3=读回不匹配。
原 0x30 的低字节是失败预期值，次低字节是实际值；启动汇总会打印全部细节。

## 重新构建与运行

在仓库根目录、已配置 Vivado/Vitis 2022.2 的 PowerShell 中顺序执行：

```powershell
$env:VIVADO_BIN = 'E:\Vivado2022\Vivado\2022.2\bin' # 换成实际安装目录
python tests/run_rtl.py
& "$env:VIVADO_BIN\vivado.bat" -mode batch -source scripts/build_dual.tcl
# 将 Vitis bin 加入 PATH 后：
xsct.bat scripts/build_dual_vitis.tcl
```

1. 仿真必须显示 `ALL RTL TESTS PASS`。
2. Vivado 自动打包 1.2 IP、导入 BD、刷新 IP 实例、验证、生成 wrapper、综合、实现、时序检查和 XSA。
   构建后的实际编译文件清单在 `build/compile_sources.txt`，可核对用到的 IP 副本。
3. XSCT 从这份 XSA 创建/更新独立 `dual_platform`，复制本仓库连续采集源码并编译 ELF。
   输出为 `build/vitis/dual_capture/Debug/dual_capture.elf`。
4. 连接正确的 AX7020，下载 `build/vivado/dual_adau1979.runs/impl_1/design_1_wrapper.bit`，
   用该 XSA 对应的 PS 初始化和 ELF 调试运行。UART **921600 8N1**（沿用 BD 的 UART1 设置）。
   单块板连接本机 hw_server:3121 时，可执行 `xsct.bat scripts/program_dual.tcl`，
   自动复位 PS、下载位流、执行匹配的 ps7_init、下载并启动 ELF；该操作仅加载易失配置。
5. 保留原 s/r 启动交互，可先在 Hardware Manager arm ILA，再输入 s。
   ILA 不是必须的，s 会请求一次完整公共复位/初始化。
6. 汇总两颗均 verified=1 后才开始正式 DMA；q 停止。

恢复已验证的单芯片路径：

```powershell
& "$env:VIVADO_BIN\vivado.bat" -mode batch -source scripts/build_dual.tcl -tclargs single
xsct.bat scripts/build_dual_vitis.tcl
```

此配置只初始化 A=0x11、A 作主机，保留 sdata[2]/[3] 及原 LR_POLARITY=1，word4..7 补零。
仍使用相同连续 DMA 环，不是旧单次测试。重新回到双芯片时不加 `-tclargs single` 即可。
若实物新增芯片未复位/重新上电，切换主机前必须确保公共复位实际连到两颗，不能只依赖 FPGA 配置重载。

## 验证与上板验收

实际执行结果见 `tests/results/validation.md` 和 `tests/results/rtl-summary.txt`。
`init_tb.sv` 使用开漏引脚模型连接真实 I²C 引擎，验证成功、B NACK、B PLL 超时、B 配置值错误、
主机交换、单芯片恢复及公共复位只出现一次、I²C 不并发、没有两颗同时输出时钟。
`stream_tb.sv` 的每根线/左右槽/每帧均有区分数据，包含负满幅、正满幅、-1，
检查 3072 帧逐字顺序、符号扩展、三次 TLAST、随机样式背压与包间连续性，
并覆盖默认映射、交换映射和单芯片模式。
`axi_tb.sv` 通过真实 AXI 事务检查两个诊断 bank、完整 8 位地址无旧寄存器别名、
失败禁止出流、成功后 START 跨包保持及累计 AXIS 帧数。
新增检查确认探测不写任何寄存器、主机探测距从机验证完成至少 100 ms，
覆盖主机地址 NACK、延迟后 ACK、地址 ACK 后首笔配置 NACK，以及探测寄存器只读且不覆盖旧地址。

上板需要真实电源、MCLK、两颗正确地址绑带和接线，不能由仿真替代：

1. 核对两颗地址、0x06 角色、五项实际读回和 valid/error。
2. 连续运行至少 60 秒，DMA 块数持续增长；FIFO 溢出不增长，同步错误不持续增长，
   DMASR 无内部/从机/译码错误。可安装 pyserial 后运行：
   `python tests/board_acceptance.py --port COM5 --seconds 60`。
   该脚本默认 921600 波特，发送 s、保存 UART 文本，至少观察首个进展之后 60 秒，最后发送 q；
   初始化失败时继续接收两颗完整诊断汇总，再保存并返回失败。
   COM 号必须改为实际板卡。计数异常或超时返回失败，显示跳块不算采集丢帧。
3. 逐路向 A CH1..4、B CH1..4 输入可区分信号，分别确认 ch1..ch8 打印位置；
   检查其余通道没有串位。100 ms 快照不能代替波形/频率质量分析。
4. 手动保存实物位号—地址—SDATA—打印通道记录和 UART 日志，才可宣称双芯片上板通过。

当前默认配置为 0x31 前四路、0x11 后四路，0x11 仍为时钟主机。
19:44 的 JTAG 扫描链故障在用户重新连接后恢复，新的芯片组顺序已下载并通过至少 60 秒连续采集。
DMA 46→2861；I²S 和 AXIS 均增加 2882395；溢出/同步/I²C/DMA 错误均为 0；q 停止确认。
原始记录见 `tests/results/board-reordered-60s-uart.txt` 和对应 summary JSON。

用户确认将 1 kHz、1 Vpp 信号接入 0x31 VIN1/CH1。修正接收器极性之前，
七个完整 DDR 块（7168 帧）中强信号出现在 ch2，过零周期估算约 1000.03 Hz（假定 48 kHz）。
结合标准 I²S 时序图、ADC 0x04 bit7 的反转配置，接收器改为 LR_POLARITY=0，
以高→低时隙组成同一帧；没有修改采样边沿、延迟、增益或 ADC 初始化脚本。
最终构建和复测见 `tests/results/validation.md`；其余七路仍需逐路注入，不能宣称全部物理映射通过。
采样曾出现满幅码，不能据此宣称模拟幅度或失真合格。

此前在旧输出顺序下，2026-10-21 19:28–19:29，用户重焊 0x11 后，使用同一双芯片构建重新下载，
两颗的地址 ACK、配置写 ACK、PLL 和五项读回均通过，正式八通道连续采集至少 60 秒通过。
DMA 完成块从 46 增至 2861；I²S 和 AXIS 帧均增加 2882396；
FIFO 溢出、同步错误和 I²C 错误全程为 0，DMASR 无错误；q 停止得到确认。
当时没有信号源；当前已进行 0x31 VIN1 的单路注入，其余七路仍待测试。
完整结果见 `tests/results/validation.md`、`tests/results/board-60s-summary.json`，
原始串口文本见 `tests/results/board-60s-uart.txt`。
重焊前的 NACK 记录保留在 `tests/results/board-init.txt`、`tests/results/board-probe-init.txt`。

本仓库既有约定忽略 bit/xsa/elf/dcp 等生成物。本交付提交源码、打包、BD、XDC、
应用、脚本和验证说明，不把本机缓存、凭据、临时文件或旧构建产物上传。
