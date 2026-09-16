open_checkpoint C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.runs/impl_1/design_1_wrapper_routed.dcp
puts "DEBUG_CORES=[get_cells -hier -filter {NAME =~ *ila*}]"
set dbg [get_debug_cores dbg_hub]
puts "DBG_HUB=[get_property C_USER_SCAN_CHAIN $dbg]"
report_debug_core
close_design
