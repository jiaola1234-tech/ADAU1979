# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S00_AXI_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FIFO_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "I2C_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "I2S_DELAY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LR_POLARITY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SLOT_BITS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "U1_I2C_ADDR" -parent ${Page_0}
  ipgui::add_param $IPINST -name "U2_I2C_ADDR" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WORD_BITS" -parent ${Page_0}


}

proc update_PARAM_VALUE.CLK_HZ { PARAM_VALUE.CLK_HZ } {
	# Procedure called to update CLK_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_HZ { PARAM_VALUE.CLK_HZ } {
	# Procedure called to validate CLK_HZ
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S00_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S00_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to update C_S00_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S00_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.FIFO_ADDR_WIDTH { PARAM_VALUE.FIFO_ADDR_WIDTH } {
	# Procedure called to update FIFO_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FIFO_ADDR_WIDTH { PARAM_VALUE.FIFO_ADDR_WIDTH } {
	# Procedure called to validate FIFO_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.I2C_HZ { PARAM_VALUE.I2C_HZ } {
	# Procedure called to update I2C_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.I2C_HZ { PARAM_VALUE.I2C_HZ } {
	# Procedure called to validate I2C_HZ
	return true
}

proc update_PARAM_VALUE.I2S_DELAY { PARAM_VALUE.I2S_DELAY } {
	# Procedure called to update I2S_DELAY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.I2S_DELAY { PARAM_VALUE.I2S_DELAY } {
	# Procedure called to validate I2S_DELAY
	return true
}

proc update_PARAM_VALUE.LR_POLARITY { PARAM_VALUE.LR_POLARITY } {
	# Procedure called to update LR_POLARITY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LR_POLARITY { PARAM_VALUE.LR_POLARITY } {
	# Procedure called to validate LR_POLARITY
	return true
}

proc update_PARAM_VALUE.SLOT_BITS { PARAM_VALUE.SLOT_BITS } {
	# Procedure called to update SLOT_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SLOT_BITS { PARAM_VALUE.SLOT_BITS } {
	# Procedure called to validate SLOT_BITS
	return true
}

proc update_PARAM_VALUE.U1_I2C_ADDR { PARAM_VALUE.U1_I2C_ADDR } {
	# Procedure called to update U1_I2C_ADDR when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.U1_I2C_ADDR { PARAM_VALUE.U1_I2C_ADDR } {
	# Procedure called to validate U1_I2C_ADDR
	return true
}

proc update_PARAM_VALUE.U2_I2C_ADDR { PARAM_VALUE.U2_I2C_ADDR } {
	# Procedure called to update U2_I2C_ADDR when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.U2_I2C_ADDR { PARAM_VALUE.U2_I2C_ADDR } {
	# Procedure called to validate U2_I2C_ADDR
	return true
}

proc update_PARAM_VALUE.WORD_BITS { PARAM_VALUE.WORD_BITS } {
	# Procedure called to update WORD_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WORD_BITS { PARAM_VALUE.WORD_BITS } {
	# Procedure called to validate WORD_BITS
	return true
}


proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.SLOT_BITS { MODELPARAM_VALUE.SLOT_BITS PARAM_VALUE.SLOT_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SLOT_BITS}] ${MODELPARAM_VALUE.SLOT_BITS}
}

proc update_MODELPARAM_VALUE.WORD_BITS { MODELPARAM_VALUE.WORD_BITS PARAM_VALUE.WORD_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WORD_BITS}] ${MODELPARAM_VALUE.WORD_BITS}
}

proc update_MODELPARAM_VALUE.LR_POLARITY { MODELPARAM_VALUE.LR_POLARITY PARAM_VALUE.LR_POLARITY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LR_POLARITY}] ${MODELPARAM_VALUE.LR_POLARITY}
}

proc update_MODELPARAM_VALUE.I2S_DELAY { MODELPARAM_VALUE.I2S_DELAY PARAM_VALUE.I2S_DELAY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.I2S_DELAY}] ${MODELPARAM_VALUE.I2S_DELAY}
}

proc update_MODELPARAM_VALUE.FIFO_ADDR_WIDTH { MODELPARAM_VALUE.FIFO_ADDR_WIDTH PARAM_VALUE.FIFO_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FIFO_ADDR_WIDTH}] ${MODELPARAM_VALUE.FIFO_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.CLK_HZ { MODELPARAM_VALUE.CLK_HZ PARAM_VALUE.CLK_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_HZ}] ${MODELPARAM_VALUE.CLK_HZ}
}

proc update_MODELPARAM_VALUE.I2C_HZ { MODELPARAM_VALUE.I2C_HZ PARAM_VALUE.I2C_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.I2C_HZ}] ${MODELPARAM_VALUE.I2C_HZ}
}

proc update_MODELPARAM_VALUE.U1_I2C_ADDR { MODELPARAM_VALUE.U1_I2C_ADDR PARAM_VALUE.U1_I2C_ADDR } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.U1_I2C_ADDR}] ${MODELPARAM_VALUE.U1_I2C_ADDR}
}

proc update_MODELPARAM_VALUE.U2_I2C_ADDR { MODELPARAM_VALUE.U2_I2C_ADDR PARAM_VALUE.U2_I2C_ADDR } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.U2_I2C_ADDR}] ${MODELPARAM_VALUE.U2_I2C_ADDR}
}

