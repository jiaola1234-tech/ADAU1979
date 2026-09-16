open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set d [get_hw_devices]
puts "DEVICES=$d"
set fpga [lindex [get_hw_devices xc7z020_1] 0]
puts "FPGA_PART=[get_property PART $fpga] PROGRAMMED=[get_property PROGRAM.MEM.USR_ACCESS $fpga]"
puts "DEBUG_CORES=[get_hw_ilas -of_objects $fpga]"
close_hw_manager
