# AX7020 + ADAU1979 constraint file
#
# Assumption:
# - Board: ALINX / HeiJin AX7020
# - Expansion header used: J10
# - PL bank: BANK35, LVCMOS33
# - Reference: AX7020 user manual, J10 expansion header pin table
#   https://ax7020-20231-v101.readthedocs.io/zh-cn/latest/AX7020UserManual_CN/AX7020UserManual.html
#
# Electrical note:
# - J11 is 3.3 V FPGA IO. Do not connect 5 V logic to these signals.
# - ADAU1979 SCL/SDA need pull-ups. The ADAU1979 schematic already has them;
#   otherwise enable board-level pull-ups or add external pull-up resistors.
#
# Signal mapping:
# - adau_scl      -> ADAU1979 H4 pin 1  / J10 pin 3  / W19
# - adau_sda      -> ADAU1979 H4 pin 2  / J10 pin 4  / W18
# - adau_bclk     -> ADAU1979 H4 pin 3  / J10 pin 5  / R14
# - adau_lrclk    -> ADAU1979 H4 pin 4  / J10 pin 6  / P14
# - adau_sdata[1] -> ADAU1979 H4 pin 5  / J10 pin 7  / Y17
# - adau_sdata[0] -> ADAU1979 H4 pin 6  / J10 pin 8  / Y16
# - adau_sdata[3] -> ADAU1979 H4 pin 7  / J10 pin 9  / W15
# - adau_sdata[2] -> ADAU1979 H4 pin 8  / J10 pin 10 / V15
# - adau_pd_rst   -> ADAU1979 H4 pin 9  / J10 pin 11 / Y14
#
# These names match the generated ADAU1979 capture IP top-level ports.
# If Vivado auto-renames the external ports in your BD wrapper, first run:
#   get_ports *adau*
# then adjust the port names below to match the actual top-level names.

set_property PACKAGE_PIN W19 [get_ports adau_scl]
set_property PACKAGE_PIN W18 [get_ports adau_sda]
set_property PACKAGE_PIN R14 [get_ports adau_bclk]
set_property PACKAGE_PIN P14 [get_ports adau_lrclk]
set_property PACKAGE_PIN Y17 [get_ports {adau_sdata[1]}]
set_property PACKAGE_PIN Y16 [get_ports {adau_sdata[0]}]
set_property PACKAGE_PIN W15 [get_ports {adau_sdata[3]}]
set_property PACKAGE_PIN V15 [get_ports {adau_sdata[2]}]
set_property PACKAGE_PIN Y14 [get_ports adau_pd_rst]

set_property IOSTANDARD LVCMOS33 [get_ports adau_scl]
set_property IOSTANDARD LVCMOS33 [get_ports adau_sda]
set_property IOSTANDARD LVCMOS33 [get_ports adau_bclk]
set_property IOSTANDARD LVCMOS33 [get_ports adau_lrclk]
set_property IOSTANDARD LVCMOS33 [get_ports {adau_sdata[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports adau_pd_rst]

# The audio data lines come from ADAU1979 and are sampled inside PL with sync
# registers, so treat them as asynchronous to the 100 MHz AXI/PL clock.
set_false_path -from [get_ports adau_bclk]
set_false_path -from [get_ports adau_lrclk]
set_false_path -from [get_ports {adau_sdata[*]}]

# The I2C slave response and the power-down/reset output are slow control
# signals without a source-synchronous relationship to FCLK_CLK0.
set_false_path -from [get_ports adau_sda]
set_false_path -to [get_ports adau_scl]
set_false_path -to [get_ports adau_sda]
set_false_path -to [get_ports adau_pd_rst]
