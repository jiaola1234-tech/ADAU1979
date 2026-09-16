# Configure the AX7020 onboard CP2102 USB-UART connection.
# AX7020 UART_TX is PS MIO48 and UART_RX is PS MIO49, using physical UART1.
# Run this script from the Vivado Tcl Console with the ADAU1979 project open.

set adau_root_dir {C:/Users/weitong/Desktop/ADAU1979}
set adau_default_xpr [file join $adau_root_dir vivado adau1979_lwip adau1979_lwip.xpr]

if {![llength [current_project -quiet]]} {
    if {[file exists $adau_default_xpr]} {
        open_project $adau_default_xpr
    } else {
        error "No project is open and default project does not exist: $adau_default_xpr"
    }
}

set bd_files [get_files -quiet */design_1.bd]
if {![llength $bd_files]} {
    set bd_files [get_files -quiet design_1.bd]
}
if {![llength $bd_files]} {
    error "Cannot find design_1.bd in the current project."
}

open_bd_design [lindex $bd_files 0]

set ps_cell [get_bd_cells -quiet processing_system7_0]
if {![llength $ps_cell]} {
    error "Cannot find processing_system7_0 in design_1.bd."
}

# Select the physical UART1 connected to the onboard CP2102.  The
# Disable the currently selected UART0 through the main UART enable switch.
# This updates the dependent UART0 parameters and releases MIO42/43.
set_property CONFIG.PCW_EN_UART0 {0} $ps_cell
set_property CONFIG.PCW_UART0_PERIPHERAL_ENABLE {NA} $ps_cell
set_property CONFIG.PCW_UART0_UART0_IO {NA} $ps_cell

# Enable UART1 before selecting its MIO group.  Manually changing a disabled
# PCW_UARTx_PERIPHERAL_ENABLE parameter can produce an {NA} range error.
set_property CONFIG.PCW_EN_UART1 {1} $ps_cell
set_property CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} $ps_cell
set_property CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} $ps_cell
set_property CONFIG.PCW_UART1_BAUD_RATE {921600} $ps_cell

validate_bd_design
save_bd_design

puts "PS UART0 is disabled."
puts "PS UART1 is enabled on MIO 48/49 for the AX7020 onboard CP2102."
puts "The Vitis VOFA application also sets UART1 to 921600 baud at runtime."
