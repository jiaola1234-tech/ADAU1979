# Replace the old AD7606 capture block in the opened project with the new
# ADAU1979 capture IP. Run this after opening or cloning the original project.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_ip_repo_dir {C:/Users/weitong/Desktop/ADAU1979/ip_repo}
set adau_xdc_file {C:/Users/weitong/Desktop/ADAU1979/vivado/constraints/ax7020_adau1979_j11.xdc}

if {![llength [current_project -quiet]]} {
    error "Open a Vivado project first, then source this script."
}

if {![file exists [file join $adau_ip_repo_dir adau1979_capture_1.0 component.xml]]} {
    error "ADAU1979 IP is not packaged yet. Run 00_package_adau1979_ip.tcl first."
}

set adau_repo_paths [get_property ip_repo_paths [current_project]]
if {$adau_repo_paths eq ""} {
    set adau_repo_paths [list]
}
if {[lsearch -exact $adau_repo_paths $adau_ip_repo_dir] < 0} {
    lappend adau_repo_paths $adau_ip_repo_dir
}
set_property ip_repo_paths $adau_repo_paths [current_project]
update_ip_catalog -rebuild

if {[file exists $adau_xdc_file]} {
    if {![llength [get_files -quiet $adau_xdc_file]]} {
    add_files -fileset constrs_1 -norecurse {C:/Users/weitong/Desktop/ADAU1979/vivado/constraints/ax7020_adau1979_j11.xdc}
    }
} else {
    error "Cannot find ADAU1979 XDC file: $adau_xdc_file"
}

foreach old_xdc [get_files -quiet *ad7606.xdc] {
    puts "Disabling old AD7606 constraint file: $old_xdc"
    set_property IS_ENABLED false $old_xdc
}

set adau_bd_files [get_files -quiet */design_1.bd]
if {![llength $adau_bd_files]} {
    set adau_bd_files [get_files -quiet design_1.bd]
}
if {![llength $adau_bd_files]} {
    error "Cannot find design_1.bd in the current project."
}
open_bd_design [lindex $adau_bd_files 0]

set adau_ip_vlnv [get_ipdefs -quiet -all user.org:user:adau1979_capture:*]
if {![llength $adau_ip_vlnv]} {
    error "Cannot find user.org:user:adau1979_capture in the IP catalog."
}
set adau_ip_vlnv [lindex $adau_ip_vlnv end]

set old_adau_nets [list]
foreach old_adau_obj [get_bd_ports -quiet adau*] {
    foreach old_adau_net [get_bd_nets -quiet -of_objects $old_adau_obj] {
        lappend old_adau_nets $old_adau_net
    }
}

if {[llength [get_bd_cells -quiet adau1979_capture_0_upgraded_ipi]]} {
    puts "Removing stale Vivado IP-upgrade replacement cell."
    delete_bd_objs [get_bd_cells adau1979_capture_0_upgraded_ipi]
}

if {[llength [get_bd_cells -quiet adau1979_capture_0]]} {
    puts "Removing existing adau1979_capture_0 before rebuilding connections."
    delete_bd_objs [get_bd_cells adau1979_capture_0]
}

if {[llength [get_bd_cells -quiet ad7606_sample_0]]} {
    puts "Removing old ad7606_sample_0."
    delete_bd_objs [get_bd_cells ad7606_sample_0]
}
if {[llength [get_bd_intf_ports -quiet ADC_PORT_0]]} {
    puts "Removing old ADC_PORT_0 external interface."
    delete_bd_objs [get_bd_intf_ports ADC_PORT_0]
}
foreach old_intf_net {
    ad7606_sample_0_ADC_PORT
    ad7606_sample_0_M00_AXIS
    ps7_0_axi_periph_M01_AXI
} {
    if {[llength [get_bd_intf_nets -quiet $old_intf_net]]} {
        puts "Removing old interface net: $old_intf_net"
        delete_bd_objs [get_bd_intf_nets $old_intf_net]
    }
}

create_bd_cell -type ip -vlnv $adau_ip_vlnv adau1979_capture_0
set_property -dict [list \
    CONFIG.CLK_HZ {100000000} \
    CONFIG.I2C_HZ {100000} \
    CONFIG.FIFO_ADDR_WIDTH {10} \
    CONFIG.SLOT_BITS {32} \
    CONFIG.WORD_BITS {24} \
    CONFIG.LR_POLARITY {1} \
    CONFIG.I2S_DELAY {1} \
] [get_bd_cells adau1979_capture_0]

if {[llength [get_bd_cells -quiet axi_dma_0]]} {
    puts "Setting axi_dma_0 S2MM stream width to 256 bits."
    set_property -dict [list CONFIG.c_s_axis_s2mm_tdata_width {256}] [get_bd_cells axi_dma_0]
} else {
    error "Cannot find axi_dma_0. The original AD7606 project topology changed."
}

connect_bd_intf_net [get_bd_intf_pins adau1979_capture_0/M00_AXIS] \
                    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

if {[llength [get_bd_intf_pins -quiet ps7_0_axi_periph/M01_AXI]]} {
    connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] \
                        [get_bd_intf_pins adau1979_capture_0/S00_AXI]
} else {
    error "Cannot find ps7_0_axi_periph/M01_AXI for the ADAU1979 AXI-Lite port."
}

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins adau1979_capture_0/s00_axi_aclk] \
               [get_bd_pins adau1979_capture_0/m00_axis_aclk]

if {[llength [get_bd_pins -quiet rst_ps7_0_100M/peripheral_aresetn]]} {
    connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
                   [get_bd_pins adau1979_capture_0/s00_axi_aresetn] \
                   [get_bd_pins adau1979_capture_0/m00_axis_aresetn]
} else {
    error "Cannot find rst_ps7_0_100M/peripheral_aresetn."
}

foreach adau_port_name {
    adau_bclk
    adau_lrclk
    adau_sdata
    adau_pd_rst
    adau_scl
    adau_sda
} {
    if {[llength [get_bd_ports -quiet $adau_port_name]]} {
        delete_bd_objs [get_bd_ports $adau_port_name]
    }
}

foreach old_adau_net [lsort -unique $old_adau_nets] {
    if {[llength [get_bd_nets -quiet $old_adau_net]]} {
        delete_bd_objs [get_bd_nets $old_adau_net]
    }
}

create_bd_port -dir I adau_bclk
create_bd_port -dir I adau_lrclk
create_bd_port -dir I -from 3 -to 0 adau_sdata
create_bd_port -dir O adau_pd_rst
create_bd_port -dir O adau_scl
create_bd_port -dir IO adau_sda

connect_bd_net [get_bd_pins adau1979_capture_0/adau_bclk] [get_bd_ports adau_bclk]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_lrclk] [get_bd_ports adau_lrclk]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_sdata] [get_bd_ports adau_sdata]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_pd_rst] [get_bd_ports adau_pd_rst]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_scl] [get_bd_ports adau_scl]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_sda] [get_bd_ports adau_sda]

# Add an ILA for the I2C bring-up path.  Probe the actual external pins and
# the internal open-drain/initialization state so ACK failures can be
# distinguished from a missing pull-up or a wrong address.
if {[llength [get_bd_cells -quiet ila_i2c_debug]]} {
    delete_bd_objs [get_bd_cells ila_i2c_debug]
}
create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_i2c_debug
# Vivado's ILA IP defaults to AXI monitor mode when instantiated in a block
# design.  That mode silently replaces the requested six native probes with
# the AXI monitor's generated probe bundle (and produces dozens of <const0>
# entries in the .ltx).  Explicitly select Native mode before setting widths.
set_property CONFIG.C_MONITOR_TYPE {Native} [get_bd_cells ila_i2c_debug]
set_property -dict [list \
    CONFIG.C_ENABLE_ILA_AXI_MON {false} \
    CONFIG.C_NUM_OF_PROBES {6} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {64} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_DATA_DEPTH {4096} \
] [get_bd_cells ila_i2c_debug]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins ila_i2c_debug/clk]
connect_bd_net [get_bd_pins adau1979_capture_0/i2c_scl_dbg] \
               [get_bd_pins ila_i2c_debug/probe0]
connect_bd_net [get_bd_pins adau1979_capture_0/i2c_sda_dbg] \
               [get_bd_pins ila_i2c_debug/probe1]
connect_bd_net [get_bd_pins adau1979_capture_0/adau_pd_rst] \
               [get_bd_pins ila_i2c_debug/probe2]
set adau_i2c_debug_pin [get_bd_pins -quiet adau1979_capture_0/i2c_debug]
if {![llength $adau_i2c_debug_pin]} {
    error "The loaded ADAU1979 IP has no i2c_debug port. Re-run 00_package_adau1979_ip.tcl, close/reopen the Vivado project, then run 05_refresh_adau1979_ip.tcl."
}
connect_bd_net $adau_i2c_debug_pin \
               [get_bd_pins ila_i2c_debug/probe3]
connect_bd_net [get_bd_ports adau_bclk] \
               [get_bd_pins ila_i2c_debug/probe4]
connect_bd_net [get_bd_ports adau_lrclk] \
               [get_bd_pins ila_i2c_debug/probe5]

# M00 controls AXI DMA and M01 controls ADAU1979. M02 has no slave and only
# creates an incomplete address path warning.
set_property CONFIG.NUM_MI {2} [get_bd_cells ps7_0_axi_periph]

set adau_addr_segs [get_bd_addr_segs -quiet adau1979_capture_0/S00_AXI/*]
if {[llength $adau_addr_segs]} {
    puts "Assigning ADAU1979 AXI-Lite base address 0x44A00000."
    assign_bd_address -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
                      -offset 0x44A00000 -range 64K $adau_addr_segs
} else {
    puts "Address segment not found by wildcard; running automatic address assignment."
    assign_bd_address
}

validate_bd_design
save_bd_design

puts "AD7606 block replacement finished."
puts "External ADAU ports:"
puts "  [get_bd_ports -quiet adau*]"
