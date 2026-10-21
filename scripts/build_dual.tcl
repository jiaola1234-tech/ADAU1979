# Vivado 2022.2: vivado -mode batch -source scripts/build_dual.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root ip_repo adau1979_capture_1.0 scripts package_ip.tcl]
create_project -force dual_adau1979 [file join $root build vivado] -part xc7z020clg400-2
set_property ip_repo_paths [list [file join $root ip_repo adau1979_capture_1.0]] [current_project]
update_ip_catalog
file mkdir [file join $root build bd]
file copy -force [file join $root vivado dual_adau1979 design_1.bd] [file join $root build bd design_1.bd]
add_files -norecurse [file join $root build bd design_1.bd]
open_bd_design [file join $root build bd design_1.bd]
# Refresh a cached BD instance after repackaging the same VLNV/revision.
upgrade_bd_cells [get_bd_cells adau1979_capture_0]
source [file join $root scripts dual_config.tcl]
set_property -dict $capture_config [get_bd_cells adau1979_capture_0]
# Both fabric interfaces share the same FCLK_CLK0 (100 MHz), as in the proven BD.
validate_bd_design
save_bd_design
write_bd_tcl -force [file join $root build resolved_bd.tcl]
generate_target all [get_files design_1.bd]
set wrappers [make_wrapper -files [get_files design_1.bd] -top]
add_files -norecurse $wrappers
add_files -fileset constrs_1 -norecurse [file join $root vivado dual_adau1979 adau1979.xdc]
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1
set fh [open [file join $root build compile_sources.txt] w]
puts $fh [join [get_files -compile_order sources -used_in synthesis] "\n"]
close $fh
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match *Complete* [get_property STATUS [get_runs synth_1]]]} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match *Complete* [get_property STATUS [get_runs impl_1]]]} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $root build timing_summary.rpt]
if {[get_property SLACK [get_timing_paths -max_paths 1]] < 0} {error "Timing failed"}
write_hw_platform -fixed -include_bit -force -file [file join $root build dual_adau1979.xsa]
puts "DUAL_BUILD_PASS"
