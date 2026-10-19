# Repair the BD for the single ADAU1979 audio-clock master.
# This script does not change any ILA settings.

set root {C:/Users/weitong/Desktop/adsingle}
set project [file join $root vivado ad_slave ad_slave.xpr]
set bd_file [file join $root vivado ad_slave ad_slave.srcs sources_1 bd design_1 design_1.bd]
set ip_repo [file join $root ip_repo]

open_project $project
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog

open_bd_design $bd_file
set cell [get_bd_cells -quiet adau1979_capture_0]
if {![llength $cell]} {
    error "Cannot find BD cell adau1979_capture_0"
}

# Refresh the packaged IP so the AXI clock associations are read from the
# corrected 1.0.6 component.xml (one ASSOCIATED_BUSIF name per clock).
upgrade_ip $cell

# The single ADAU1979 is the audio-clock master. These external BD ports are therefore inputs
# to the FPGA, and feed both the capture IP and the existing ILA probe nets.
foreach name {adau_bclk adau_lrclk} {
    set port [get_bd_ports -quiet $name]
    if {![llength $port]} {
        error "Cannot find external BD port $name"
    }
    set_property DIR I $port
}

save_bd_design
set bd_obj [get_files -quiet $bd_file]
reset_target all $bd_obj
generate_target all $bd_obj
validate_bd_design
report_ip_status
puts "Single-device audio-master BD repair completed; ILA settings were not changed."
close_project
