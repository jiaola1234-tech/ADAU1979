create_project -force adau1979_capture_check {C:/Users/weitong/Desktop/ADAU1979/.vivado_check} -part xc7z020clg400-2

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

synth_design -top adau1979_capture_v1_0 -part xc7z020clg400-2 -mode out_of_context

report_utilization -file {C:/Users/weitong/Desktop/ADAU1979/.vivado_check/utilization.rpt}
report_timing_summary -file {C:/Users/weitong/Desktop/ADAU1979/.vivado_check/timing_summary.rpt}

puts "ADAU1979 capture IP OOC synthesis check finished."
puts "Reports:"
puts "  C:/Users/weitong/Desktop/ADAU1979/.vivado_check/utilization.rpt"
puts "  C:/Users/weitong/Desktop/ADAU1979/.vivado_check/timing_summary.rpt"

close_project
