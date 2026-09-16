# Check the generated/opened ADAU1979 Vivado project.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_default_xpr [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xpr]

if {![llength [current_project -quiet]]} {
    if {[file exists $adau_default_xpr]} {
        open_project $adau_default_xpr
    } else {
        error "No project is open and default project does not exist: $adau_default_xpr"
    }
}

set adau_repo_paths [get_property ip_repo_paths [current_project]]

set adau_bd_files [get_files -quiet */design_1.bd]
if {![llength $adau_bd_files]} {
    set adau_bd_files [get_files -quiet design_1.bd]
}
if {![llength $adau_bd_files]} {
    error "Cannot find design_1.bd."
}
open_bd_design [lindex $adau_bd_files 0]

set failed 0

proc require_count {kind objects description} {
    upvar failed failed
    if {![llength $objects]} {
        puts "ERROR: missing $description"
        set failed 1
    } else {
        puts "OK: $description"
    }
}

require_count cell [get_bd_cells -quiet adau1979_capture_0] "BD cell adau1979_capture_0"
require_count cell [get_bd_cells -quiet axi_dma_0] "BD cell axi_dma_0"

set adau_ila [get_bd_cells -quiet ila_i2c_debug]
if {[llength $adau_ila]} {
    set adau_ila_mode [get_property CONFIG.C_MONITOR_TYPE $adau_ila]
    set adau_ila_probes [get_property CONFIG.C_NUM_OF_PROBES $adau_ila]
    if {$adau_ila_mode ne "Native" || $adau_ila_probes ne "6"} {
        puts "ERROR: ila_i2c_debug is not a six-probe Native ILA (mode=$adau_ila_mode, probes=$adau_ila_probes)"
        set failed 1
    } else {
        puts "OK: ila_i2c_debug Native mode with 6 probes"
    }
} else {
    puts "WARNING: ila_i2c_debug is not present; ILA capture will not be available"
}

if {[llength [get_bd_cells -quiet ad7606_sample_0]]} {
    puts "ERROR: old BD cell ad7606_sample_0 is still present"
    set failed 1
} else {
    puts "OK: old BD cell ad7606_sample_0 removed"
}

foreach port_name {
    adau_bclk
    adau_lrclk
    adau_sdata
    adau_pd_rst
    adau_scl
    adau_sda
} {
    require_count port [get_bd_ports -quiet $port_name] "BD external port $port_name"
}

validate_bd_design

puts "Top-level ADAU ports visible to constraints:"
puts "  [get_ports -quiet *adau*]"

if {$failed} {
    error "ADAU1979 project check failed."
}

puts "ADAU1979 project check passed."
