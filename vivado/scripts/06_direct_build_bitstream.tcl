# Single-process Vivado build.  This avoids the Windows cscript run-wrapper
# (which can fail with "Loading your settings failed (Access is denied)").
set root {C:/Users/weitong/Desktop/adsingle}
set xpr [file join $root vivado adau1979_lwip adau1979_lwip.xpr]
set xsa [file join $root vivado adau1979_lwip adau1979_lwip.xsa]
open_project $xpr
set_property ip_repo_paths [file join $root ip_repo] [current_project]
update_ip_catalog
set bd [lindex [get_files -quiet */design_1.bd] 0]
open_bd_design $bd
validate_bd_design
reset_target all $bd
generate_target all $bd
update_compile_order -fileset sources_1
set wrapper_v [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 hdl design_1_wrapper.v]
set bd_v [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 synth design_1.v]
set ip_v_files [glob -nocomplain [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 ip * synth *.v]]
set ip_vhdl_files [glob -nocomplain [file join $root vivado adau1979_lwip adau1979_lwip.gen sources_1 bd design_1 ip * synth *.vhd]]
set vivado_ip_hdl [file join {E:/Vivado2022/Vivado/2022.2} data ip xilinx]
set rtl_v_files [glob -nocomplain [file join $root ip_repo adau1979_capture_1.0 hdl *.v]]
close_project
create_project -in_memory -part xc7z020clg400-2
read_verilog -library xil_defaultlib $wrapper_v
read_verilog -library xil_defaultlib $bd_v
foreach ip_v $ip_v_files { read_verilog -library xil_defaultlib $ip_v }
foreach ip_vhdl $ip_vhdl_files { read_vhdl -library xil_defaultlib $ip_vhdl }
# The generated AXI infrastructure stubs reference the Xilinx primitive
# libraries by entity name.  Read the matching RTL models explicitly because
# this in-memory build does not inherit the normal IP compile-order libraries.
foreach ip_model [glob -nocomplain \
    [file join $vivado_ip_hdl axi_dwidth_converter_v2_1 hdl axi_dwidth_converter_v2_1_vl_rfs.v] \
    [file join $vivado_ip_hdl axi_protocol_converter_v2_1 hdl *.v] \
    [file join $vivado_ip_hdl axi_interconnect_v2_1 hdl *.v] \
    [file join $vivado_ip_hdl axi_crossbar_v2_1 hdl *.v] \
    [file join $vivado_ip_hdl proc_sys_reset_v5_0 hdl *.vhd]] {
    if {[string match *.vhd $ip_model]} {
        read_vhdl -library xil_defaultlib $ip_model
    } else {
        read_verilog -library xil_defaultlib $ip_model
    }
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
