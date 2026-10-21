set ip_root [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $ip_root .. ..]]
create_project -force adau1979_capture_packager [file join $root build package] -part xc7z020clg400-2
add_files -norecurse [glob [file join $ip_root hdl *.v]]
set_property top adau1979_capture_v1_0 [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_root -vendor user.org -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]

set_property name adau1979_capture $core
set_property version 1.2 $core
set_property display_name {Dual ADAU1979 8CH Continuous Capture} $core
set_property description {Dual ADAU1979 address ACK probes, 100 ms master settling, verified initialization and continuous 256-bit AXI stream} $core
set_property vendor_display_name {User} $core
set_property company_url {https://example.local} $core

ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interfaces xilinx.com:signal:reset_rtl:1.0 $core

set_property value 32 [ipx::get_hdl_parameters C_S00_AXI_DATA_WIDTH -of_objects $core]
set_property value 8 [ipx::get_hdl_parameters C_S00_AXI_ADDR_WIDTH -of_objects $core]

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

# Resolve every GUI parameter directly into the matching HDL parameter.
foreach name {DUAL_ENABLE DEVICE_A_ADDR DEVICE_B_ADDR AUDIO_MASTER A_SDATA0 A_SDATA1 B_SDATA0 B_SDATA1} {
    set hp [ipx::get_hdl_parameters $name -of_objects $core]
    set up [ipx::get_user_parameters $name -of_objects $core]
    set_property value_resolve_type user $up
    set_property value_source user $up
    set_property value_resolve_type generated $hp
    set_property value_dependency "spirit:decode(id('PARAM_VALUE.$name'))" $hp
}
ipx::create_xgui_files $core
# Keep repeated packaging deterministic: Vivado appends an empty GUI line.
set gui_path [file join $ip_root xgui adau1979_capture_v1_2.tcl]
set gui_handle [open $gui_path r]
set gui_text [string trimright [read $gui_handle] "\r\n"]
close $gui_handle
set gui_handle [open $gui_path w]
puts $gui_handle $gui_text
close $gui_handle
ipx::update_checksums $core
ipx::save_core $core
close_project
