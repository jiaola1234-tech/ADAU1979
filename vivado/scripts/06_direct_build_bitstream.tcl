# Single-process Vivado build.  This avoids the Windows cscript run-wrapper
# (which can fail with "Loading your settings failed (Access is denied)").
set root {C:/Users/weitong/Desktop/ADAU1979}
set xpr [file join $root vivado adau1979_lwip adau1979_lwip.xpr]
set xsa [file join $root vivado adau1979_lwip adau1979_lwip.xsa]
open_project $xpr
set bd [lindex [get_files -quiet */design_1.bd] 0]
open_bd_design $bd
validate_bd_design
reset_target all $bd
generate_target all $bd
update_compile_order -fileset sources_1
set wrapper_v [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 hdl design_1_wrapper.v]
set bd_v [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 synth design_1.v]
set ip_v_files [glob -nocomplain [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 ip * synth *.v]]
set rtl_v_files [glob -nocomplain [file join $root ip_repo adau1979_capture_1.0 hdl *.v]]
close_project
create_project -in_memory -part xc7z020clg400-2
read_verilog -library xil_defaultlib $wrapper_v
read_verilog -library xil_defaultlib $bd_v
foreach ip_v $ip_v_files { read_verilog -library xil_defaultlib $ip_v }
foreach ip_v [glob -nocomplain [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 ip * synth *.v]] {
    read_verilog $ip_v
}
foreach rtl_v $rtl_v_files {
    read_verilog $rtl_v
}
read_xdc [file join $root vivado constraints ax7020_adau1979_j11.xdc]
synth_design -top design_1_wrapper -part xc7z020clg400-2
opt_design
place_design
phys_opt_design
route_design
write_bitstream -force [file join $root vivado adau1979_lwip adau1979_lwip.bit]
write_hw_platform -fixed -include_bit -force -file $xsa
puts "DIRECT_BUILD_COMPLETE"
puts "BIT=[file join $root vivado adau1979_lwip adau1979_lwip.bit]"
puts "XSA=$xsa"
close_project
