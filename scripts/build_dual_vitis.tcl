# xsct scripts/build_dual_vitis.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set xsa [file join $root build dual_adau1979.xsa]
if {![file exists $xsa]} {error "Build/export hardware first: $xsa"}
setws [file join $root build vitis]
set platforms [platform list -dict]
if {[string first dual_platform $platforms]>=0} {
    platform active dual_platform
    platform config -updatehw $xsa
} else {
    platform create -name dual_platform -hw $xsa -proc ps7_cortexa9_0 -os standalone
}
platform generate
if {[string first dual_capture [app list -dict]]<0} {
    app create -name dual_capture -platform dual_platform -domain standalone_domain -lang c -template {Empty Application}
}
foreach src [glob [file join $root ws1 design_1_wrapper_lianxu_ src *]] {
    file copy -force $src [file join $root build vitis dual_capture src [file tail $src]]
}
app build -name dual_capture
puts "DUAL_VITIS_BUILD_PASS"
