create_project -force adau1979_capture_slave_packager {C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/.packager} -part xc7z020clg400-2

add_files -norecurse {
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau1979_capture_v1_0.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau1979_capture_v1_0_S00_AXI.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau1979_capture_core.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau1979_i2s_rx.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau1979_i2c_init.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/adau_audio_clock_gen.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/i2c_master_write8.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/i2c_master_read8.v
    C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0/hdl/axis_fifo_256.v
}
set_property top adau1979_capture_v1_0 [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir {C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_slave_1.0} -vendor user.org -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name adau1979_capture_slave $core
# Bump the packaged IP version whenever the RTL changes so Vivado can
# identify the new implementation and offer an IP upgrade in the BD.
set_property version 1.1.2 $core
set_property display_name {ADAU1979 8CH Capture - U1 Master, U1 First, ACK Only} $core
set_property description {Dual ADAU1979 capture with U1 as audio serial clock master, initialized before U2; write ACK checked without readback compare} $core
set_property vendor_display_name {User} $core
set_property company_url {https://example.local} $core

ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

set_property value 32 [ipx::get_hdl_parameters C_S00_AXI_DATA_WIDTH -of_objects $core]
set_property value 6 [ipx::get_hdl_parameters C_S00_AXI_ADDR_WIDTH -of_objects $core]

foreach {busif mode} {m00_axis master s00_axi slave} {
    if {[llength [ipx::get_bus_interfaces $busif -of_objects $core]]} {
        set_property interface_mode $mode [ipx::get_bus_interfaces $busif -of_objects $core]
    }
}

set clk_bus [ipx::get_bus_interfaces s00_axi_aclk -of_objects $core]
if {[llength $clk_bus]} {
    set_property interface_mode slave $clk_bus
    set p [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk_bus]
    if {[llength $p]} { set_property value s00_axi $p }
    set p [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk_bus]
    if {[llength $p]} { set_property value s00_axi_aresetn $p }
}
set axis_clk_bus [ipx::get_bus_interfaces m00_axis_aclk -of_objects $core]
if {[llength $axis_clk_bus]} {
    set_property interface_mode slave $axis_clk_bus
    set p [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $axis_clk_bus]
    if {[llength $p]} { set_property value m00_axis $p }
    set p [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $axis_clk_bus]
    if {[llength $p]} { set_property value m00_axis_aresetn $p }
}
foreach rst_name {s00_axi_aresetn m00_axis_aresetn} {
    set rst_bus [ipx::get_bus_interfaces $rst_name -of_objects $core]
    if {[llength $rst_bus]} {
        set_property interface_mode slave $rst_bus
        set p [ipx::get_bus_parameters POLARITY -of_objects $rst_bus]
        if {[llength $p]} { set_property value ACTIVE_LOW $p }
    }
}
ipx::update_checksums $core
ipx::save_core $core
close_project
