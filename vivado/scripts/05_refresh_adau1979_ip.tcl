# Refresh the ADAU1979 IP instance in the final project after RTL changes.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_xpr [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xpr]

if {![llength [current_project -quiet]]} {
    open_project $adau_xpr
}

source [file join $adau_root_dir vivado scripts 02_replace_ad7606_with_adau1979_bd.tcl]

set adau_bd [lindex [get_files -quiet */design_1.bd] 0]
reset_target all $adau_bd
generate_target all $adau_bd
update_compile_order -fileset sources_1
puts "ADAU1979 IP refresh finished."
close_project
