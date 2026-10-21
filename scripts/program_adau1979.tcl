# Volatile download of the matching ADAU1979 bitstream and Vitis ELF.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build adau1979.bit]
set elf [file join $root build vitis_adau1979 adau1979 Debug adau1979.elf]
set psinit [file join $root build vitis_adau1979 adau1979_platform hw ps7_init.tcl]
foreach path [list $bit $elf $psinit] {
    if {![file exists $path]} {error "Build the named ADAU1979 deliverables first: $path"}
}
connect -url TCP:127.0.0.1:3121
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000
fpga -file $bit
targets -set -nocase -filter {name =~ "ARM*#0"}
catch {stop}
configparams force-mem-access 1
source $psinit
ps7_init
ps7_post_config
dow $elf
configparams force-mem-access 0
con
puts "ADAU1979_DOWNLOAD_PASS"
disconnect
exit
