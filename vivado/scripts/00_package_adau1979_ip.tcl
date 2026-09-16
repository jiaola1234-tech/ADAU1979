# Run from a fresh Vivado Tcl Console or with:
#   vivado -mode batch -source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/00_package_adau1979_ip.tcl

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_ip_pack_script [file join $adau_root_dir ip_repo adau1979_capture_1.0 scripts package_ip.tcl]

if {![file exists $adau_ip_pack_script]} {
    error "Cannot find IP pack script: $adau_ip_pack_script"
}

puts "Packaging ADAU1979 capture IP..."
source $adau_ip_pack_script

set adau_component_xml [file join $adau_root_dir ip_repo adau1979_capture_1.0 component.xml]
if {![file exists $adau_component_xml]} {
    error "IP packaging finished but component.xml was not generated: $adau_component_xml"
}

puts "ADAU1979 capture IP package is ready:"
puts "  $adau_component_xml"
