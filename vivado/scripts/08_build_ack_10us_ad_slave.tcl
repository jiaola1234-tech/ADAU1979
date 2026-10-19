# Build the ACK-duration comparison bitstream for the active ad_slave project.
# The packaged RTL holds each slave ACK high phase for 10 us while data bits
# remain at 100 kHz. The original 100 kHz bit/ltx are backed up separately.

set root_dir {C:/Users/weitong/Desktop/ADAU1979}
set project_file [file join $root_dir vivado ad_slave ad_slave.xpr]
set output_dir [file join $root_dir vivado ad_slave ack_test_10us]

# Re-package the source tree first.  Without this step Vivado can keep using
# the previous IP cache, making RTL fixes in ip_repo appear to have no effect.
source [file join $root_dir vivado scripts 00_package_adau1979_slave_ip.tcl]

open_project $project_file
set_property ip_repo_paths [list [file join $root_dir ip_repo]] [current_project]
update_ip_catalog -rebuild

set bd_file [lindex [get_files -quiet */design_1.bd] 0]
if {$bd_file eq ""} { error "design_1.bd was not found" }
open_bd_design $bd_file
set capture [get_bd_cells -quiet adau1979_capture_0]
if {![llength $capture]} { error "adau1979_capture_0 was not found" }
upgrade_bd_cells $capture
if {[get_property CONFIG.I2C_HZ $capture] ne "100000"} {
    error "Expected the data-bit I2C rate to remain 100000 Hz"
}
validate_bd_design
save_bd_design
reset_target all $bd_file
generate_target all $bd_file
update_compile_order -fileset sources_1

# Fail before synthesis if Vivado silently reused the old packaged RTL.
set generated_write [glob -nocomplain [file join $root_dir vivado ad_slave ad_slave.gen sources_1 bd design_1 ipshared * hdl i2c_master_write8.v]]
set generated_read [glob -nocomplain [file join $root_dir vivado ad_slave ad_slave.gen sources_1 bd design_1 ipshared * hdl i2c_master_read8.v]]
set generated_init [glob -nocomplain [file join $root_dir vivado ad_slave ad_slave.gen sources_1 bd design_1 ipshared * hdl adau1979_i2c_init.v]]
if {[llength $generated_write] == 0 || [llength $generated_read] == 0 || [llength $generated_init] == 0} {
    error "Generated I2C RTL was not found"
}
foreach generated_file [concat $generated_write $generated_read] {
    set fd [open $generated_file r]
    set contents [read $fd]
    close $fd
    if {[string first "ack_high_extra_tick" $contents] < 0} {
        error "Old I2C RTL was reused: $generated_file"
    }
}
set fd [open [lindex $generated_init 0] r]
set init_contents [read $fd]
close $fd
if {[string first "VERIFY_M_POWER_STRICT" $init_contents] < 0} {
    error "Generated init RTL was not refreshed from the current source"
}

set ip_run design_1_adau1979_capture_0_11_synth_1
reset_run $ip_run
launch_runs $ip_run -jobs 4
wait_on_run $ip_run
if {![string match *Complete* [get_property STATUS [get_runs $ip_run]]]} {
    error "ADAU1979 IP synthesis failed: [get_property STATUS [get_runs $ip_run]]"
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match *Complete* [get_property STATUS [get_runs synth_1]]]} {
    error "Top-level synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match *Complete* [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

set run_dir [file join $root_dir vivado ad_slave ad_slave.runs impl_1]
set bit_file [file join $run_dir design_1_wrapper.bit]
set ltx_file [file join $run_dir design_1_wrapper.ltx]
if {![file exists $bit_file] || ![file exists $ltx_file]} {
    error "ACK comparison bitstream or ILA probes file was not produced"
}
file mkdir $output_dir
file copy -force $bit_file [file join $output_dir design_1_wrapper_ack10us.bit]
file copy -force $ltx_file [file join $output_dir design_1_wrapper_ack10us.ltx]
puts "ACK_10US_BUILD_COMPLETE"
puts "BIT=[file join $output_dir design_1_wrapper_ack10us.bit]"
puts "LTX=[file join $output_dir design_1_wrapper_ack10us.ltx]"
close_project
