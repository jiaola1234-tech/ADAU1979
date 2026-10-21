# Decimal values are 7-bit addresses (17=0x11, 49=0x31).
# Logical A is the already verified device. Never infer this from U1/U2 silk.
set capture_config [list CONFIG.DUAL_ENABLE 1 CONFIG.DEVICE_A_ADDR 17 CONFIG.DEVICE_B_ADDR 49 \
    CONFIG.AUDIO_MASTER 0 CONFIG.A_SDATA0 2 CONFIG.A_SDATA1 3 CONFIG.B_SDATA0 0 CONFIG.B_SDATA1 1 \
    CONFIG.C_S00_AXI_ADDR_WIDTH 8]
# Recovery: vivado ... -tclargs single (same continuous ring, A-only, B words zero).
if {[llength $argv] && [lindex $argv 0] eq "single"} {
    dict set capture_config CONFIG.DUAL_ENABLE 0
    dict set capture_config CONFIG.AUDIO_MASTER 0
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
