open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set fpga [lindex [get_hw_devices xc7z020_1] 0]
set_property BSCAN_SWITCH_USER_MASK 0x1 $fpga
set_property PROGRAM.FILE {C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.runs/impl_1/design_1_wrapper.bit} $fpga
set_property PROBES.FILE {C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.runs/impl_1/design_1_wrapper.ltx} $fpga
program_hw_devices $fpga
refresh_hw_device $fpga
puts "ILAS=[get_hw_ilas -of_objects $fpga]"
close_hw_manager
