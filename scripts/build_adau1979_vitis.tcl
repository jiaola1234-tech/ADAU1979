# Build the deliverable Vitis platform/application with the requested names.
set root [file normalize [file join [file dirname [info script]] ..]]
set xsa [file join $root build dual_adau1979.xsa]
if {![file exists $xsa]} {error "Build/export hardware first: $xsa"}

set ws [file join $root build vitis_adau1979]
file mkdir $ws
setws $ws

if {[string first adau1979_platform [platform list -dict]] < 0} {
    platform create -name adau1979_platform -hw $xsa -proc ps7_cortexa9_0 -os standalone
} else {
    platform active adau1979_platform
    platform config -updatehw $xsa
}
platform generate

set app_list {}
catch {set app_list [app list -dict]}
if {[string first adau1979 $app_list] < 0} {
    app create -name adau1979 -platform adau1979_platform \
        -domain standalone_domain -lang c -template {Empty Application}
}
foreach src [glob [file join $root ws1 design_1_wrapper_lianxu_ src *]] {
    file copy -force $src [file join $ws adau1979 src [file tail $src]]
}
app build -name adau1979
puts "ADAU1979_VITIS_BUILD_PASS"
