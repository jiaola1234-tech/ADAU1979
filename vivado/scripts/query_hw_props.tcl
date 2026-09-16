open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices] 1]
puts "DEV=$dev"
puts "MASK=[get_property BSCAN_SWITCH_USER_MASK $dev]"
puts "TYPE=[get_property CLASS $dev]"
report_property $dev
close_hw_manager
