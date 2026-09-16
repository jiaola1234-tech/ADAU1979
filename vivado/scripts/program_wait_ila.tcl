open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices] 1]
set_property PROGRAM.FILE {C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.runs/impl_1/design_1_wrapper.bit} $dev
set_property PROBES.FILE {C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.runs/impl_1/design_1_wrapper.ltx} $dev
program_hw_devices $dev
after 15000
refresh_hw_device $dev
puts "ILAS=[get_hw_ilas -of_objects $dev]"
close_hw_manager
