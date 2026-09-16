# Create and build the Vitis 2022.2 workspace for ADAU1979.
# Run with:
#   xsct.bat scripts/create_vitis_workspace.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
set workspace [file join $root vitis_workspace]
set xsa [file join $root vivado adau1979_lwip adau1979_lwip.xsa]
set driver_src [file join $root ip_repo adau1979_capture_1.0 drivers adau1979_capture_v1_0 src adau1979_capture.h]
set vofa_src [file join $root examples vitis_adau1979_vofa.c]
set dma_src [file join $root examples vitis_adau1979_dma_test.c]

if {![file exists $xsa]} {
    error "Missing hardware platform: $xsa"
}
if {![file exists $driver_src]} {
    error "Missing ADAU1979 driver header: $driver_src"
}
if {![file exists $vofa_src] || ![file exists $dma_src]} {
    error "Missing Vitis application source files under $root/examples"
}

file mkdir $workspace
setws $workspace

# Re-running the script should refresh the platform from the newest XSA.
if {[llength [platform list -dict]]} {
    catch {platform remove adau1979_platform}
}
platform create -name adau1979_platform -hw $xsa -proc ps7_cortexa9_0 -os standalone
platform generate

set existing_apps {}
catch {set existing_apps [app list -dict]}
if {[llength $existing_apps]} {
    catch {app remove adau1979_dma_test}
    catch {app remove adau1979_vofa}
}

app create -name adau1979_dma_test -platform adau1979_platform \
    -domain standalone_domain -lang c -template "Empty Application"
app create -name adau1979_vofa -platform adau1979_platform \
    -domain standalone_domain -lang c -template "Empty Application"

importsources -name adau1979_dma_test -path $dma_src
importsources -name adau1979_dma_test -path $driver_src
importsources -name adau1979_vofa -path $vofa_src
importsources -name adau1979_vofa -path $driver_src

platform active adau1979_platform
domain active standalone_domain
platform generate
app build -all

puts "Vitis workspace created and applications built:"
puts "  $workspace"
puts "  [file join $workspace adau1979_dma_test Debug adau1979_dma_test.elf]"
puts "  [file join $workspace adau1979_vofa Debug adau1979_vofa.elf]"
