# xsct scripts/program_dual.tcl -- volatile JTAG load of the matching build.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build vivado dual_adau1979.runs impl_1 design_1_wrapper.bit]
set elf [file join $root build vitis dual_capture Debug dual_capture.elf]
set psinit [file join $root build vitis dual_platform hw ps7_init.tcl]
foreach path [list $bit $elf $psinit] {
    if {![file exists $path]} {error "Build hardware and application first: $path"}
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
puts "BOARD_DOWNLOAD_PASS"
disconnect
exit
