# Decimal values are 7-bit addresses (17=0x11, 49=0x31).
# Logical A is the first four output words; B is the last four. No U1/U2 inference.
# 0x31 -> word0..3, SDATA[0]/[1]; 0x11 -> word4..7, SDATA[2]/[3].
# Keep the proven physical clock master at 0x11 (now logical B).
# Register 0x04=0xBF has LR_POL=1: CH1/3 are on LRCLK high.
# RX LR_POLARITY=0 starts on the high slot, then pairs the following low slot.
set capture_config [list CONFIG.DUAL_ENABLE 1 CONFIG.DEVICE_A_ADDR 49 CONFIG.DEVICE_B_ADDR 17 \
    CONFIG.AUDIO_MASTER 1 CONFIG.A_SDATA0 0 CONFIG.A_SDATA1 1 CONFIG.B_SDATA0 2 CONFIG.B_SDATA1 3 \
    CONFIG.LR_POLARITY 0 CONFIG.C_S00_AXI_ADDR_WIDTH 8]
# Recovery: vivado ... -tclargs single (same continuous ring, A-only, B words zero).
if {[llength $argv] && [lindex $argv 0] eq "single"} {
    dict set capture_config CONFIG.LR_POLARITY 1
    dict set capture_config CONFIG.DUAL_ENABLE 0
    dict set capture_config CONFIG.AUDIO_MASTER 0
    dict set capture_config CONFIG.DEVICE_A_ADDR 17
    dict set capture_config CONFIG.DEVICE_B_ADDR 49
    dict set capture_config CONFIG.A_SDATA0 2
    dict set capture_config CONFIG.A_SDATA1 3
    dict set capture_config CONFIG.B_SDATA0 0
    dict set capture_config CONFIG.B_SDATA1 1
}
set dual [dict get $capture_config CONFIG.DUAL_ENABLE]
set master [dict get $capture_config CONFIG.AUDIO_MASTER]
if {$dual ni {0 1} || $master ni {0 1} || (!$dual && $master!=0)} {error "Invalid device/master selection"}
foreach key {DEVICE_A_ADDR DEVICE_B_ADDR} {
    if {[dict get $capture_config CONFIG.$key] ni {17 49 81 113}} {error "Use a strapped ADAU1979 7-bit address"}
}
if {$dual && [dict get $capture_config CONFIG.DEVICE_A_ADDR]==[dict get $capture_config CONFIG.DEVICE_B_ADDR]} {error "Device addresses must differ"}
set lanes {}
foreach key {A_SDATA0 A_SDATA1 B_SDATA0 B_SDATA1} {
    set lane [dict get $capture_config CONFIG.$key]
    if {$lane ni {0 1 2 3}} {error "SDATA index out of range"}
    lappend lanes $lane
}
if {[llength [lsort -unique $lanes]]!=4} {error "SDATA lanes must be a permutation of 0..3"}
