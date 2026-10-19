set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_ip_pack_script [file join $adau_root_dir ip_repo adau1979_capture_slave_1.0 scripts package_ip.tcl]
if {![file exists $adau_ip_pack_script]} {
    error "Cannot find IP pack script: $adau_ip_pack_script"
}
source $adau_ip_pack_script
puts "ADAU1979 slave-clock capture IP package is ready."
