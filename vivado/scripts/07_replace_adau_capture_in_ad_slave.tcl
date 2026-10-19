# Replace the legacy ADAU1979 capture instance in the ad_slave project with
# the dedicated audio-serial-slave IP.  The legacy IP remains in ip_repo.

set root_dir {C:/Users/weitong/Desktop/ADAU1979}
set project_file [file join $root_dir vivado ad_slave ad_slave.xpr]
set repo_dir [file join $root_dir ip_repo]

if {![llength [current_project -quiet]]} {
    open_project $project_file
}

set_property ip_repo_paths [list $repo_dir] [current_project]
update_ip_catalog -rebuild

set bd_file [lindex [get_files -quiet */design_1.bd] 0]
if {$bd_file eq ""} {
    error "Cannot find design_1.bd in ad_slave project."
}
open_bd_design $bd_file

set ipdef [lindex [get_ipdefs -quiet -all user.org:user:adau1979_capture_slave:1.0.2] end]
if {$ipdef eq ""} {
    error "New IP user.org:user:adau1979_capture_slave:1.0.2 is not in the catalog."
}

set old_cell [get_bd_cells -quiet adau1979_capture_0]
if {[llength $old_cell]} {
    puts "Removing legacy capture instance: [get_property VLNV $old_cell]"
    delete_bd_objs $old_cell
}

# Remove orphaned interface nets left by the deleted cell.  This is harmless
# when Vivado has already removed them as part of delete_bd_objs.
foreach net_name {adau1979_capture_0_m00_axis ps7_0_axi_periph_M01_AXI} {
    set nets [get_bd_intf_nets -quiet $net_name]
    if {[llength $nets]} {
        delete_bd_objs $nets
    }
}

create_bd_cell -type ip -vlnv $ipdef adau1979_capture_0
set capture [get_bd_cells adau1979_capture_0]
set_property -dict [list \
    CONFIG.CLK_HZ {100000000} \
    CONFIG.I2C_HZ {100000} \
    CONFIG.FIFO_ADDR_WIDTH {10} \
    CONFIG.SLOT_BITS {32} \
    CONFIG.WORD_BITS {24} \
    CONFIG.LR_POLARITY {1} \
    CONFIG.I2S_DELAY {1} \
    CONFIG.U1_I2C_ADDR {0010001} \
    CONFIG.U2_I2C_ADDR {0010001} \
] $capture

set dma [get_bd_cells -quiet axi_dma_0]
if {![llength $dma]} {
    error "Cannot find axi_dma_0 in ad_slave block design."
}
set_property CONFIG.c_s_axis_s2mm_tdata_width {256} $dma
connect_bd_intf_net [get_bd_intf_pins $capture/M00_AXIS] \
                    [get_bd_intf_pins $dma/S_AXIS_S2MM]

set axi_master [get_bd_intf_pins -quiet ps7_0_axi_periph/M01_AXI]
if {![llength $axi_master]} {
    error "Cannot find ps7_0_axi_periph/M01_AXI."
}
connect_bd_intf_net $axi_master [get_bd_intf_pins $capture/S00_AXI]

set fclk [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net $fclk [get_bd_pins $capture/s00_axi_aclk] \
                    [get_bd_pins $capture/m00_axis_aclk]
set resetn [get_bd_pins -quiet rst_ps7_0_100M/peripheral_aresetn]
if {![llength $resetn]} {
    error "Cannot find rst_ps7_0_100M/peripheral_aresetn."
}
connect_bd_net $resetn [get_bd_pins $capture/s00_axi_aresetn] \
                       [get_bd_pins $capture/m00_axis_aresetn]

# Keep the existing external pin names and the ILA probes, but reconnect them
# to the new instance.  BCLK/LRCLK are outputs in the new design.  Vivado can
# retain a net with the same port name while replacing a cell, so explicitly
# disconnect only the endpoints below before making the new connections.
proc disconnect_endpoint {obj} {
    foreach net [get_bd_nets -quiet -of_objects $obj] {
        disconnect_bd_net $net $obj
    }
}

foreach port_name {adau_bclk adau_lrclk adau_sdata adau_pd_rst adau_scl adau_sda} {
    if {![llength [get_bd_ports -quiet $port_name]]} {
        if {$port_name eq "adau_sdata"} {
            create_bd_port -dir I -from 3 -to 0 $port_name
        } elseif {$port_name eq "adau_sda"} {
            create_bd_port -dir IO $port_name
        } else {
            create_bd_port -dir O $port_name
        }
    }
}
foreach pin_name {adau_bclk adau_lrclk adau_sdata adau_pd_rst adau_scl adau_sda i2c_scl_dbg i2c_sda_dbg i2c_debug} {
    disconnect_endpoint [get_bd_pins $capture/$pin_name]
}
foreach port_name {adau_bclk adau_lrclk adau_sdata adau_pd_rst adau_scl adau_sda} {
    disconnect_endpoint [get_bd_ports $port_name]
}
connect_bd_net [get_bd_pins $capture/adau_bclk] [get_bd_ports adau_bclk]
connect_bd_net [get_bd_pins $capture/adau_lrclk] [get_bd_ports adau_lrclk]
connect_bd_net [get_bd_pins $capture/adau_sdata] [get_bd_ports adau_sdata]
connect_bd_net [get_bd_pins $capture/adau_pd_rst] [get_bd_ports adau_pd_rst]
connect_bd_net [get_bd_pins $capture/adau_scl] [get_bd_ports adau_scl]
connect_bd_net [get_bd_pins $capture/adau_sda] [get_bd_ports adau_sda]

set ila [get_bd_cells -quiet ila_i2c_debug]
if {[llength $ila]} {
    set_property -dict [list \
        CONFIG.C_MONITOR_TYPE {Native} \
        CONFIG.C_ENABLE_ILA_AXI_MON {false} \
        CONFIG.C_NUM_OF_PROBES {8} \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE1_WIDTH {1} \
        CONFIG.C_PROBE2_WIDTH {1} \
        CONFIG.C_PROBE3_WIDTH {64} \
        CONFIG.C_PROBE4_WIDTH {1} \
        CONFIG.C_PROBE5_WIDTH {1} \
        CONFIG.C_PROBE6_WIDTH {4} \
        CONFIG.C_PROBE7_WIDTH {1} \
        CONFIG.C_DATA_DEPTH {2048} \
    ] $ila
    foreach probe_name {probe0 probe1 probe2 probe3 probe4 probe5 probe6 probe7} {
        disconnect_endpoint [get_bd_pins $ila/$probe_name]
    }
    connect_bd_net [get_bd_pins $capture/i2c_scl_dbg] [get_bd_pins $ila/probe0]
    connect_bd_net [get_bd_pins $capture/i2c_sda_dbg] [get_bd_pins $ila/probe1]
    connect_bd_net [get_bd_pins $capture/adau_pd_rst] [get_bd_pins $ila/probe2]
    connect_bd_net [get_bd_pins $capture/i2c_debug] [get_bd_pins $ila/probe3]
    connect_bd_net [get_bd_pins $capture/adau_bclk] [get_bd_pins $ila/probe4]
    connect_bd_net [get_bd_pins $capture/adau_lrclk] [get_bd_pins $ila/probe5]
    connect_bd_net [get_bd_ports adau_sdata] [get_bd_pins $ila/probe6]
    connect_bd_net [get_bd_pins $capture/m00_axis_tvalid] [get_bd_pins $ila/probe7]
}

set segs [get_bd_addr_segs -quiet $capture/S00_AXI/*]
if {[llength $segs]} {
    assign_bd_address -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
                      -offset 0x44A00000 -range 64K $segs
}

validate_bd_design
save_bd_design
reset_target all $bd_file
generate_target all $bd_file
update_compile_order -fileset sources_1

# The copied ad_slave project inherited a few AutoDisabled output-product
# references from the old adau1979_lwip project.  Remove only entries that are
# actually missing after the new BD targets have been generated; this keeps
# the project from reopening with stale adau1979_capture_0_7 warnings.
foreach src_file [get_files -quiet -of_objects [get_filesets sources_1]] {
    if {![file exists [get_property NAME $src_file]]} {
        puts "Removing missing sources_1 entry: $src_file"
        remove_files -fileset sources_1 $src_file
    }
}
update_compile_order -fileset sources_1
if {[file exists $project_file]} {
    update_ip_catalog
}
puts "ad_slave now uses user.org:user:adau1979_capture_slave:1.0.2 with raw SDATAOUT and AXIS-valid ILA probes"
close_project
