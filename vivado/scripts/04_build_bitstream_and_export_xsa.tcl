# Build the generated ADAU1979 Vivado project and export hardware for Vitis.
# Run after 01_clone_and_patch_ad7606_project.tcl and 03_check_adau1979_project.tcl.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_default_xpr [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xpr]
set adau_xsa_file [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xsa]

if {![llength [current_project -quiet]]} {
    if {[file exists $adau_default_xpr]} {
        open_project $adau_default_xpr
    } else {
        error "No project is open and default project does not exist: $adau_default_xpr"
    }
}

set adau_bd_files [get_files -quiet */design_1.bd]
if {![llength $adau_bd_files]} {
    set adau_bd_files [get_files -quiet design_1.bd]
}
if {[llength $adau_bd_files]} {
    open_bd_design [lindex $adau_bd_files 0]
    validate_bd_design
    save_bd_design
    # Force regeneration: reset_run may remove generated IP DCPs while the BD
    # still reports its targets as up-to-date.
    reset_target all [lindex $adau_bd_files 0]
    generate_target all [lindex $adau_bd_files 0]
}

update_compile_order -fileset sources_1

# Regenerating the BD can invalidate an existing completed run. Reset both
# run records before launching so the script is repeatable across Vivado
# versions and old project copies.
reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synth_1 did not complete successfully: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "impl_1 did not complete bitstream successfully: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
write_hw_platform -fixed -include_bit -force -file $adau_xsa_file

puts "Bitstream build and XSA export finished:"
puts "  $adau_xsa_file"
