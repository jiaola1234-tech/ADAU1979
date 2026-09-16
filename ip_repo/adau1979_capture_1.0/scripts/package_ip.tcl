create_project -force adau1979_capture_packager {C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/.packager} -part xc7z020clg400-2

add_files -norecurse {
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/adau1979_capture_v1_0.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/adau1979_capture_v1_0_S00_AXI.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/adau1979_capture_core.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/adau1979_i2s_rx.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/adau1979_i2c_init.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/i2c_master_write8.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/i2c_master_read8.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0/hdl/axis_fifo_256.v
}
set_property top adau1979_capture_v1_0 [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir {C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0} -vendor user.org -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]

set_property name adau1979_capture $core
set_property version 1.1 $core
set_property display_name {ADAU1979 8CH Capture} $core
set_property description {Dual ADAU1979 8-channel I2S capture with PL I2C initialization and 256-bit AXI-Stream output} $core
set_property vendor_display_name {User} $core
set_property company_url {https://example.local} $core

ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

set_property value 32 [ipx::get_hdl_parameters C_S00_AXI_DATA_WIDTH -of_objects $core]
set_property value 6 [ipx::get_hdl_parameters C_S00_AXI_ADDR_WIDTH -of_objects $core]

if {[llength [ipx::get_bus_interfaces M00_AXIS -of_objects $core]]} {
    set busif [ipx::get_bus_interfaces M00_AXIS -of_objects $core]
    set_property interface_mode master $busif
}
if {[llength [ipx::get_bus_interfaces S00_AXI -of_objects $core]]} {
    set busif [ipx::get_bus_interfaces S00_AXI -of_objects $core]
    set_property interface_mode slave $busif
    if {![llength [ipx::get_memory_maps S00_AXI -of_objects $core]]} {
        ipx::add_memory_map S00_AXI $core
        ipx::add_address_block reg0 [ipx::get_memory_maps S00_AXI -of_objects $core]
        set block [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps S00_AXI -of_objects $core]]
        set_property range 4096 $block
        set_property width 32 $block
    }
    set_property slave_memory_map_ref S00_AXI $busif
}

set clk_bus [ipx::get_bus_interfaces s00_axi_aclk -of_objects $core]
if {[llength $clk_bus]} {
    set_property interface_mode slave $clk_bus
    set assoc_busif [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk_bus]
    if {[llength $assoc_busif]} {
        set_property value S00_AXI $assoc_busif
    }
    set assoc_reset [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk_bus]
    if {[llength $assoc_reset]} {
        set_property value s00_axi_aresetn $assoc_reset
    }
}

set axis_clk_bus [ipx::get_bus_interfaces m00_axis_aclk -of_objects $core]
if {[llength $axis_clk_bus]} {
    set_property interface_mode slave $axis_clk_bus
    set assoc_busif [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $axis_clk_bus]
    if {[llength $assoc_busif]} {
        set_property value M00_AXIS $assoc_busif
    }
    set assoc_reset [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $axis_clk_bus]
    if {[llength $assoc_reset]} {
        set_property value m00_axis_aresetn $assoc_reset
    }
}

set rst_bus [ipx::get_bus_interfaces s00_axi_aresetn -of_objects $core]
if {[llength $rst_bus]} {
    set_property interface_mode slave $rst_bus
    set rst_polarity [ipx::get_bus_parameters POLARITY -of_objects $rst_bus]
    if {[llength $rst_polarity]} {
        set_property value ACTIVE_LOW $rst_polarity
    }
}

set axis_rst_bus [ipx::get_bus_interfaces m00_axis_aresetn -of_objects $core]
if {[llength $axis_rst_bus]} {
    set_property interface_mode slave $axis_rst_bus
    set axis_rst_polarity [ipx::get_bus_parameters POLARITY -of_objects $axis_rst_bus]
    if {[llength $axis_rst_polarity]} {
        set_property value ACTIVE_LOW $axis_rst_polarity
    }
}

ipx::update_checksums $core
ipx::save_core $core
close_project
