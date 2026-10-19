# Refresh the ADAU1979 IP instance in the final project after RTL changes.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_xpr [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xpr]

if {![llength [current_project -quiet]]} {
    open_project $adau_xpr
}

# Make the local packaged IP (including adau_audio_clock_gen.v) visible before
# refreshing the BD instance.  This avoids silently reusing the old 1.0 IP
# cache whose BCLK/LRCLK ports were inputs.
set_property ip_repo_paths [file join $adau_root_dir ip_repo] [current_project]
update_ip_catalog

source [file join $adau_root_dir vivado scripts 02_replace_ad7606_with_adau1979_bd.tcl]

set adau_cells [get_bd_cells -quiet adau1979_capture_0]
if {[llength $adau_cells]} {
    upgrade_ip $adau_cells
}

set adau_bd [lindex [get_files -quiet */design_1.bd] 0]
reset_target all $adau_bd
generate_target all $adau_bd
update_compile_order -fileset sources_1
puts "ADAU1979 IP refresh finished."
close_project
