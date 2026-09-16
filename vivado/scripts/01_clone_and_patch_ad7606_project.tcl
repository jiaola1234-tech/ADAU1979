# Clone the existing AD7606 Vivado project into this ADAU1979 workspace, then
# replace the AD7606 capture block with the ADAU1979 capture block.
#
# Run from a fresh Vivado Tcl Console or with:
#   vivado -mode batch -source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/01_clone_and_patch_ad7606_project.tcl

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_src_xpr {C:/Users/weitong/Desktop/finalversion/vivado/ad7606_lwip.xpr}
set adau_src_dir [file dirname $adau_src_xpr]
set adau_dst_dir [file join $adau_root_dir vivado adau1979_lwip]
set adau_dst_name {adau1979_lwip}
set adau_package_script [file join $adau_root_dir vivado scripts 00_package_adau1979_ip.tcl]
set adau_replace_script [file join $adau_root_dir vivado scripts 02_replace_ad7606_with_adau1979_bd.tcl]

if {![file exists $adau_src_xpr]} {
    error "Cannot find source AD7606 project: $adau_src_xpr"
}

if {[llength [current_project -quiet]]} {
    close_project
}

source $adau_package_script

if {[file exists $adau_dst_dir]} {
    error "Destination project directory already exists: $adau_dst_dir. Remove only an incomplete generated copy before rerunning."
}

# save_project_as is unreliable with this Windows desktop path in Vivado
# 2022.2. Copy the complete reference project and open the copied project.
file copy -force $adau_src_dir $adau_dst_dir
set adau_dst_xpr [file join $adau_dst_dir ${adau_dst_name}.xpr]
file rename -force [file join $adau_dst_dir ad7606_lwip.xpr] $adau_dst_xpr
open_project $adau_dst_xpr

source $adau_replace_script

puts "ADAU1979 Vivado project created:"
puts "  [file join $adau_dst_dir ${adau_dst_name}.xpr]"
